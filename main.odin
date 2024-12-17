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
        height = 150,
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
    rl.SetTargetFPS(ctx.window.fps)

    // Mouse passthrough, but only when pointed pixel alpha == 0
    // winH := win.HWND(rl.GetWindowHandle())
    // curStyle := win.UINT(win.GetWindowLongW(winH, win.GWL_EXSTYLE))
    // win.SetWindowLongW(winH, win.GWL_EXSTYLE, win.LONG(curStyle | win.WS_EX_LAYERED))
    // win.SetLayeredWindowAttributes(winH, win.RGB(0, 0, 0), 0, 1)

    perlinImg := rl.GenImagePerlinNoise(500, 500, 0, 0, 1.0)
    ctx.perlinTex = rl.LoadTextureFromImage(perlinImg)
    rl.UnloadImage(perlinImg)

    game_hot_reloaded(ctx)
}

@(export)
game_update :: proc() -> bool {
    update_statics()
    // update window size values outside of update_statics() to avoid issues
    ctx.window.width = rl.GetScreenWidth()
    ctx.window.height = rl.GetScreenHeight()

    // ========================================
    // Raylib begin drawing
    // ========================================
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLANK)
    rl.DrawRectangleLinesEx({ 0, 0, f32(ctx.window.width), f32(ctx.window.height) }, 1, rl.GRAY)

    ctx.newSnowParticleTimer -= rl.GetFrameTime()
    debug_text("New particle in: ", ctx.newSnowParticleTimer)
    if ctx.newSnowParticleTimer <= 0 {
        create_new_snowparticle()
        ctx.newSnowParticleTimer = rand.float32_range(0.75, 1.5)
    }

    EMPTY_POS :: [2]f32{0, 0}
    P_RADIUS_SCALE :: 0.6

    for &p, idx in ctx.snowParticles {
        if p.pos == EMPTY_POS {
            continue
        }
        p.pos.y += 100 * rl.GetFrameTime()
        if p.pos.y > f32(ctx.window.height)+20 {
            p.pos = EMPTY_POS
        }

        // rl.DrawCircle(i32(p.pos.x), i32(p.pos.y), p.radius * P_RADIUS_SCALE, p.color)
    }

    // rl.DrawTexture(ctx.perlinTex, 0, 0, rl.WHITE)

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
    EMPTY_POS :: [2]f32{0, 0}
    for &p in ctx.snowParticles {
        if p.pos != EMPTY_POS {
            continue
        }

        p.pos.x = rand.float32_range(10, f32(ctx.window.width)+10)
        p.pos.y = 0
    
        p.radius = rand.float32_range(10, 20)
        p.color.r = 255
        p.color.g = 255
        p.color.b = 255
        p.color.a = 50
        break
    }
}

@(export)
game_memory :: proc() -> rawptr {
    return ctx
}

@(export)
game_shutdown :: proc() {
    free_memory()
    free(ctx)
}

// This is called everytime game is reloaded
// So we can put something that can be trivially reinited
@(export)
game_hot_reloaded :: proc(memFromOldApi: ^Context) {
    ctx = memFromOldApi
    update_statics()

    // rl.SetWindowPosition(ctx.window.posX, ctx.window.posY)
    // currMonitor := rl.GetCurrentMonitor()
    // rl.SetWindowSize(rl.GetMonitorWidth(currMonitor), rl.GetMonitorHeight(currMonitor))

    perlinImg := rl.GenImagePerlinNoise(500, 500, 0, 0, 4)
    ctx.perlinTex = rl.LoadTextureFromImage(perlinImg)
    rl.UnloadImage(perlinImg)

    free_memory()
    // TODO: resetup memory?
}

free_memory :: proc() {
    if cap(ctx.textures) != 0 {
        for t in ctx.textures {
            rl.UnloadTexture(t)
        }
        delete(ctx.textures)
    }
}

// make game use good GPU on laptops etc
@(export)
NvOptimusEnablement: u32 = 1
@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1