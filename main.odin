package christmas2024

import "core:os"
import "core:bufio"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:math"
import "core:slice"
import "core:math/rand"
import rl "vendor:raylib"
import win "core:sys/windows"
import bin "resources"


when ODIN_OS == .Windows {
    foreign import user32 "system:User32.lib"

    @(default_calling_convention="system")
    foreign user32 {
        // For some reason not implemented in Odin :(
        GetLayeredWindowAttributes :: proc(hWnd: win.HWND, crKey: ^win.COLORREF, bAlpha: ^win.BYTE, pdwFlags: ^win.DWORD) -> win.BOOL ---
    }
}

IS_RELEASE :: #config(IS_RELEASE, false)

EMPTY_POS           :: [2]f32{-999, -999}
PERLIN_IMAGE_SCALE  :: 1
WINDOW_PADDING      :: 10
P_RADIUS_MAX        :: 20

P_GRAV_SPEED: f32 = 100
P_WIND_SPEED: f32 = 0.5

P_RADIUS_SCALE: f32 = 0.25
P_TEXTURES_SCALE: f32 = 0.025
P_COLOR_ALPHA_SCALE: f32 = 0.85
P_SPAWN_FREQUENCY: f32 = 1.0

// Variables that don't change, and that should be updated on hot reloaded
// Be careful
update_statics :: proc() {
    bin.GuiLoadStyleBluish()
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 30)
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SPACING), 2)
    when ODIN_OS == .Windows {
        // screenArea: win.RECT
        // win.SystemParametersInfoW(win.SPI_GETWORKAREA, 0, &screenArea, 0)
        // rl.SetWindowPosition(screenArea.right-ctx.window.width, screenArea.bottom-ctx.window.height)
    } else {
        // rl.SetWindowPosition(0, rl.GetMonitorHeight(rl.GetCurrentMonitor())-ctx.window.height)
    }
}

when IS_RELEASE {
    main :: proc() {
        game_init()
        for game_update() {
            continue
        }
        game_shutdown()
    }
}

@(export)
game_init :: proc() {
    ctx = new(Context)
    ctx.window = Window{
        name = "Christmas 2024 Gift",
        posX = 0,
        posY = 0,
        width = 1920,
        height = 1080,
        fps = 60,
        configFlags = {
            .MSAA_4X_HINT,
            .WINDOW_UNDECORATED,
            .WINDOW_TOPMOST,
            .WINDOW_MOUSE_PASSTHROUGH,
            .WINDOW_TRANSPARENT,
        }
    }

    rl.SetConfigFlags(ctx.window.configFlags)
    rl.InitWindow(ctx.window.width, ctx.window.height, ctx.window.name)
    rl.SetWindowState(ctx.window.configFlags)
    iconImg := rl.Image {
        data = rawptr(&bin.ICON_DATA),
        width = bin.ICON_WIDTH,
        height = bin.ICON_HEIGHT,
        mipmaps = 1,
        format = rl.PixelFormat(bin.ICON_FORMAT)
    }
    rl.SetWindowIcon(iconImg)
    rl.SetTargetFPS(ctx.window.fps)

    // Mouse passthrough, but only when pointed pixel alpha == 0
    // winH := win.HWND(rl.GetWindowHandle())
    // curStyle := win.UINT(win.GetWindowLongW(winH, win.GWL_EXSTYLE))
    // win.SetWindowLongW(winH, win.GWL_EXSTYLE, win.LONG(curStyle | win.WS_EX_LAYERED))
    // win.SetLayeredWindowAttributes(winH, win.RGB(0, 0, 0), 0, 1)

    // Just in case preinit particles to -999, -999
    for &p, _ in ctx.snowParticles {
        p.pos = EMPTY_POS
    }

    update_statics()
    window_resize()
    context_init()
}

@(export)
game_update :: proc() -> bool {
    ctx.window.width = rl.GetScreenWidth()
    ctx.window.height = rl.GetScreenHeight()

    dt := rl.GetFrameTime()
    windowRect := rl.Rectangle{0, 0, f32(ctx.window.width), f32(ctx.window.height)}

    // rl.UnloadImage(ctx.perlinImg)
    // ctx.perlinImg = rl.GenImagePerlinNoise(ctx.window.width / PERLIN_IMAGE_SCALE, ctx.window.height / PERLIN_IMAGE_SCALE, i32(rl.GetTime()*5), 0, 10.0)
    // rl.UnloadTexture(ctx.perlinTex)
    // ctx.perlinTex = rl.LoadTextureFromImage(ctx.perlinImg)

    ctx.newSnowParticleTimer -= dt * P_SPAWN_FREQUENCY
    // debug_text("New particle in: ", ctx.newSnowParticleTimer)
    @(static) one := false
    if ctx.newSnowParticleTimer <= 0 {
        one = true
        create_new_snowparticle()
        ctx.newSnowParticleTimer = rand.float32_range(0.05, 0.2)
    }

    // ========================================
    // Raylib begin drawing
    // ========================================
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLANK)
    // rl.DrawRectangleLinesEx({ 0, 0, f32(ctx.window.width), f32(ctx.window.height) }, 1, rl.GRAY)

    particlesOnTheScreen := 0
    for &p, idx in ctx.snowParticles {
        if p.pos == EMPTY_POS {
            continue
        }

        perlinColor := f32(i8(rl.GetImageColor(ctx.perlinImg, i32(p.pos.x) / PERLIN_IMAGE_SCALE, i32(p.pos.y) / PERLIN_IMAGE_SCALE).x) - 127)
        windForce := perlinColor * P_WIND_SPEED * dt
        p.pos.x += windForce
        
        gForce := (perlinColor * 0.001) + p.radius / P_RADIUS_MAX
        p.pos.y += gForce * P_GRAV_SPEED * dt

        if !rl.CheckCollisionPointRec(p.pos, windowRect) {
            p.pos = EMPTY_POS
            continue
        }

        renderColor := p.color
        // smoothstep for some nice fade out at the end
        smoothstepOfPosY := 1 - math.smoothstep(f32(0.75), f32(1.05), p.pos.y / f32(ctx.window.height))
        renderColor.a = u8(f32(renderColor.a) * smoothstepOfPosY * P_COLOR_ALPHA_SCALE)

        if p.isDot {
            rl.DrawCircle(i32(p.pos.x), i32(p.pos.y), p.radius * P_RADIUS_SCALE, renderColor)
        } else {
            p.rot += p.radius / P_RADIUS_MAX * 70 * dt
            rot := math.sin(p.rot * 0.01) * (math.PI * 0.9) * math.DEG_PER_RAD

            tex := &ctx.textures[p.texIndex]
            srcRec := rl.Rectangle{ 0, 0, f32(tex.width), f32(tex.height) }
            
            texW := f32(tex.width) * (p.radius * P_TEXTURES_SCALE)
            texH := f32(tex.height) * (p.radius * P_TEXTURES_SCALE)
            dstRec := rl.Rectangle{ p.pos.x, p.pos.y, texW / 2, texH / 2}
            origin := rl.Vector2{ texW / 4, texH / 4 }
            rl.DrawTexturePro(tex^, srcRec, dstRec, origin, rot, renderColor)
            // rl.DrawCircle(i32(p.pos.x), i32(p.pos.y), p.radius * P_RADIUS_SCALE, rl.ColorAlpha(p.color, 1))
        }

        particlesOnTheScreen += 1
    }

    closeWindow: bool
    if rl.IsWindowFocused() {
        set_mouse_passthrough(false)
        // TODO: figure out disfocus. Maybe enable mouse passthrough, and after 5 sec disable it
        disfocusApp, quitApp := render_ui()
        closeWindow = quitApp
    } else {
        set_mouse_passthrough(true)
    }


    when !IS_RELEASE {
        debug_text("particlesOnTheScreen", particlesOnTheScreen)
        // Test out perlin noise values manually
        if false
        {
            pos := rl.GetMousePosition()
            rl.DrawCircle(i32(pos.x), i32(pos.y), 3, rl.GREEN)
            color := f32(i8(rl.GetImageColor(ctx.perlinImg, i32(pos.x) / PERLIN_IMAGE_SCALE, i32(pos.y) / PERLIN_IMAGE_SCALE).x) - 127)
            windForce := color * P_WIND_SPEED
            // pos.x += windForce

            gForce := (color * 0.001) + (P_RADIUS_MAX*0.9) / P_RADIUS_MAX * P_GRAV_SPEED
            // pos.y += gForce * P_GRAV_SPEED * dt

            rl.DrawTextureEx(ctx.perlinTex, 0, 0, PERLIN_IMAGE_SCALE, rl.ColorAlpha(rl.WHITE, 0.5))
            debug_text("windForce",windForce)
            debug_text("gForce",gForce)
        }

        @(static) hotReloadTimer: f32 = 3
        if hotReloadTimer >= 0 {
            draw_centered_text("RELOADED", ctx.window.width/2, ctx.window.height/2, 0, 60, rl.ColorAlpha(rl.RED, hotReloadTimer))
            hotReloadTimer -= rl.GetFrameTime()
            hotReloadTimer = clamp(hotReloadTimer, 0, 3)
        }
        rl.DrawFPS(10, ctx.window.height/2)
    }
    rl.EndDrawing()

    debug_reset_text_state()
    free_all(context.temp_allocator)

    return !(rl.WindowShouldClose() || closeWindow)
}

create_new_snowparticle :: proc() {
    for &p in ctx.snowParticles {
        if p.pos != EMPTY_POS {
            continue
        }

        p.pos.x = rand.float32_range(0, f32(ctx.window.width))
        p.pos.y = 0
    
        p.radius = rand.float32_range(8, P_RADIUS_MAX)
        rg := u8(rand.float32_range(170, 230))
        p.color.r = rg
        p.color.g = rg
        p.color.b = 255
        p.color.a = u8(rand.float32_range(100, 255))

        p.isDot = 0.3 < rand.float32_range(0, 1)
        if p.isDot {
            p.texIndex = u8(rand.float32_range(0, f32(len(ctx.textures))))
        }
        break
    }
}

render_ui :: proc() -> (disfocusApp, quitApp: bool) {
    // TODO:
    // Gui controls
    //   [   ] fps
    //    [x]  fade at the bottom
    container := rl.Rectangle{0, 0, 500, 430}
    container.x = (f32(ctx.window.width) - container.width) * 0.5
    container.y = (f32(ctx.window.height) - container.height) * 0.5

    {// background
        using container
        bgColor := rl.GetColor(0xE5EEF1ff)
        bgColor = rl.ColorAlpha(bgColor, 0.95)
        rl.DrawRectangleRounded(container, 0.02, 6, bgColor)
        rl.DrawRectangleRoundedLinesEx(container, 0.02, 6, 12, rl.GetColor(0x5ca6a6ff))
    }

    pad: f32 = 30
    elHeight: f32 = 30
    x := container.x + pad
    y := container.y + pad
    elWidth := container.width / 2 - pad
    rl.GuiSlider({x, y, elWidth, elHeight }, "", "     Falling speed", &P_GRAV_SPEED, 30, 300)
    y += elHeight + pad
    rl.GuiSlider({x, y, elWidth, elHeight }, "", "     Pattern speed", &P_WIND_SPEED, 0.0, 0.5)
    
    y += elHeight + pad + pad
    rl.GuiSlider({x, y, elWidth, elHeight }, "", "     Frequency", &P_SPAWN_FREQUENCY, 0.01, 10.0)
    y += elHeight + pad
    rl.GuiSlider({x, y, elWidth, elHeight }, "", "     Opacity", &P_COLOR_ALPHA_SCALE, 0.0, 1.0)
    y += elHeight + pad
    rl.GuiSlider({x, y, elWidth, elHeight }, "", "     Size", &P_RADIUS_SCALE, 0.1, 0.5)
    P_TEXTURES_SCALE = P_RADIUS_SCALE * 0.1

    y += elHeight + pad + 5
    quitButton := rl.Rectangle{0, 0, elWidth, elHeight}
    quitButton.x = container.x + (container.width - quitButton.width) / 2
    quitButton.y = y
    quitApp = rl.GuiButton(quitButton, "Quit!")
    return
}

set_mouse_passthrough :: proc(enable: bool) {
    if enable {
        ctx.window.configFlags += {.WINDOW_MOUSE_PASSTHROUGH}
        rl.SetWindowState({.WINDOW_MOUSE_PASSTHROUGH})
    } else {
        ctx.window.configFlags -= {.WINDOW_MOUSE_PASSTHROUGH}
        rl.ClearWindowState({.WINDOW_MOUSE_PASSTHROUGH})
    }
}

@(export)
game_memory :: proc() -> rawptr {
    return ctx
}

@(export)
game_shutdown :: proc() {
    delete(ctx.textures)
    delete(ctx.models)
    context_free_memory()
    free(ctx)
}

// This is called everytime game is reloaded
// So we can put something that can be trivially reinited
@(export)
game_hot_reloaded :: proc(memFromOldApi: ^Context) {
    ctx = memFromOldApi
    update_statics()

    window_resize()

    context_free_memory()
    context_init()
}

context_free_memory :: proc() {
    if cap(ctx.textures) != 0 {
        for t in ctx.textures {
            rl.UnloadTexture(t)
        }
    }
    rl.UnloadImage(ctx.perlinImg)
    rl.UnloadTexture(ctx.perlinTex)
}

context_init :: proc() {
    ctx.perlinImg = rl.GenImagePerlinNoise(ctx.window.width / PERLIN_IMAGE_SCALE, ctx.window.height / PERLIN_IMAGE_SCALE, 0, 0, 10.0)
    ctx.perlinTex = rl.LoadTextureFromImage(ctx.perlinImg)
    img := rl.Image {
        data = rawptr(&bin.SNOWFLAKE_A_DATA),
        width = bin.SNOWFLAKE_A_WIDTH,
        height = bin.SNOWFLAKE_A_HEIGHT,
        mipmaps = 1,
        format = rl.PixelFormat(bin.SNOWFLAKE_A_FORMAT),
    }
    append(&ctx.textures, rl.LoadTextureFromImage(img))
    img.data = rawptr(&bin.SNOWFLAKE_B_DATA)
    img.width = bin.SNOWFLAKE_B_WIDTH
    img.height = bin.SNOWFLAKE_B_HEIGHT
    append(&ctx.textures, rl.LoadTextureFromImage(img))
    img.data = rawptr(&bin.SNOWFLAKE_C_DATA)
    img.width = bin.SNOWFLAKE_C_WIDTH
    img.height = bin.SNOWFLAKE_C_HEIGHT
    append(&ctx.textures, rl.LoadTextureFromImage(img))
}

window_resize :: proc() {
    currMonitor := rl.GetCurrentMonitor()
    ctx.window.width = rl.GetMonitorWidth(currMonitor)
    ctx.window.height = rl.GetMonitorHeight(currMonitor)
    rl.SetWindowSize(ctx.window.width, ctx.window.height)
    rl.SetWindowPosition(ctx.window.posX, ctx.window.posY)
}

// Make game use good GPU on laptops.
// This doesn't work with transparent buffer
// @(export)
// NvOptimusEnablement: u32 = 1
// @(export)
// AmdPowerXpressRequestHighPerformance: i32 = 1