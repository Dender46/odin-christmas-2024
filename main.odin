package graphs

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

EMPTY_POS                   :: [2]f32{0, 0}
PERLIN_IMAGE_SCALE          :: 10
WINDOW_PADDING              :: 10

P_GRAV_SPEED                :: 100
P_WIND_SPEED                :: 0.5

P_RADIUS_SCALE              :: 0.4
P_RADIUS_MAX                :: 20
P_COLOR_ALPHA_SCALE         :: 0.5

// Variables that don't change, and that should be updated on hot reloaded
// Be careful
update_statics :: proc() {
    when ODIN_OS == .Windows {
        // screenArea: win.RECT
        // win.SystemParametersInfoW(win.SPI_GETWORKAREA, 0, &screenArea, 0)
        // rl.SetWindowPosition(screenArea.right-ctx.window.width, screenArea.bottom-ctx.window.height)
    } else {
        // rl.SetWindowPosition(0, rl.GetMonitorHeight(rl.GetCurrentMonitor())-ctx.window.height)
    }
}

@(export)
game_init :: proc() {
    ctx = new(Context)
    ctx.window = Window{
        name = "Raylib Graphs",
        posX = 0,
        posY = 0,
        width = 1920,
        height = 1080,
        fps = 60,
        configFlags = {
            .MSAA_4X_HINT,
            .WINDOW_UNDECORATED,
            // .WINDOW_TOPMOST,
            .WINDOW_MOUSE_PASSTHROUGH,
            .WINDOW_TRANSPARENT,
        }
    }

    rl.SetConfigFlags(ctx.window.configFlags)
    rl.InitWindow(ctx.window.width, ctx.window.height, ctx.window.name)
    rl.SetTargetFPS(ctx.window.fps)

    // Mouse passthrough, but only when pointed pixel alpha == 0
    // winH := win.HWND(rl.GetWindowHandle())
    // curStyle := win.UINT(win.GetWindowLongW(winH, win.GWL_EXSTYLE))
    // win.SetWindowLongW(winH, win.GWL_EXSTYLE, win.LONG(curStyle | win.WS_EX_LAYERED))
    // win.SetLayeredWindowAttributes(winH, win.RGB(0, 0, 0), 0, 1)

    window_resize()
    context_init()
}

@(export)
game_update :: proc() -> bool {
    update_statics()
    // update window size values outside of update_statics() to avoid issues
    ctx.window.width = rl.GetScreenWidth()
    ctx.window.height = rl.GetScreenHeight()
    dt := rl.GetFrameTime()

    // ========================================
    // Raylib begin drawing
    // ========================================
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLANK)
    // rl.DrawRectangleLinesEx({ 0, 0, f32(ctx.window.width), f32(ctx.window.height) }, 1, rl.GRAY)

    ctx.newSnowParticleTimer -= dt
    // debug_text("New particle in: ", ctx.newSnowParticleTimer)
    @(static) one := false
    if ctx.newSnowParticleTimer <= 0 {
        one = true
        create_new_snowparticle()
        ctx.newSnowParticleTimer = rand.float32_range(0.1, 0.3)
    }

    particlesOnTheScreen := 0
    for &p, idx in ctx.snowParticles {
        if p.pos == EMPTY_POS {
            continue
        }

        color := f32(i8(rl.GetImageColor(ctx.perlinImg, i32(p.pos.x) / PERLIN_IMAGE_SCALE, i32(p.pos.y) / PERLIN_IMAGE_SCALE).x) - 127)
        windForce := color * P_WIND_SPEED * dt
        p.pos.x += windForce

        gForce := (color * 0.008) + p.radius / P_RADIUS_MAX
        p.pos.y += gForce * P_GRAV_SPEED * dt

        windowRect := rl.Rectangle{0, 0, f32(ctx.window.width), f32(ctx.window.height)}
        if !rl.CheckCollisionPointRec(p.pos, windowRect) {
            p.pos = EMPTY_POS
            continue
        }

        particlesOnTheScreen += 1
        rl.DrawCircle(i32(p.pos.x), i32(p.pos.y), p.radius * P_RADIUS_SCALE, rl.ColorAlpha(p.color, P_COLOR_ALPHA_SCALE))
    }
    debug_text("particlesOnTheScreen", particlesOnTheScreen)

    // rl.DrawTextureEx(ctx.perlinTex, 0, 0, PERLIN_IMAGE_SCALE, rl.ColorAlpha(rl.WHITE, 0.7))

    {
        @(static) hotReloadTimer: f32 = 3
        if hotReloadTimer >= 0 {
            draw_centered_text("RELOADED", ctx.window.width/2, ctx.window.height/2, 0, 60, rl.ColorAlpha(rl.RED, hotReloadTimer))
            hotReloadTimer -= rl.GetFrameTime()
            hotReloadTimer = clamp(hotReloadTimer, 0, 3)
        }
    }
    rl.DrawFPS(5, 5)
    rl.EndDrawing()

    debug_reset_text_state()
    free_all(context.temp_allocator)

    return !rl.WindowShouldClose()
}

create_new_snowparticle :: proc() {
    for &p in ctx.snowParticles {
        if p.pos != EMPTY_POS {
            continue
        }

        p.pos.x = rand.float32_range(0, f32(ctx.window.width))
        p.pos.y = 0
    
        p.radius = rand.float32_range(8, P_RADIUS_MAX)
        p.color.r = u8(rand.float32_range(180, 255))
        p.color.g = p.color.r
        p.color.b = 255
        p.color.a = 255
        break
    }
}

@(export)
game_memory :: proc() -> rawptr {
    return ctx
}

@(export)
game_shutdown :: proc() {
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
        delete(ctx.textures)
    }
    rl.UnloadImage(ctx.perlinImg)
    rl.UnloadTexture(ctx.perlinTex)
}

context_init :: proc() {
    ctx.perlinImg = rl.GenImagePerlinNoise(ctx.window.width / PERLIN_IMAGE_SCALE, ctx.window.height / PERLIN_IMAGE_SCALE, 0, 0, 10.0)
    ctx.perlinTex = rl.LoadTextureFromImage(ctx.perlinImg)
}

window_resize :: proc() {
    currMonitor := rl.GetCurrentMonitor()
    ctx.window.width = rl.GetMonitorWidth(currMonitor)
    ctx.window.height = rl.GetMonitorHeight(currMonitor)
    rl.SetWindowSize(ctx.window.width, ctx.window.height)
    rl.SetWindowPosition(ctx.window.posX, ctx.window.posY)
}

// make game use good GPU on laptops etc
@(export)
NvOptimusEnablement: u32 = 1
@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1