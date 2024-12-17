package christmas2024_hot_reload

import "core:os"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import "core:c/libc"

when ODIN_OS == .Windows {
    DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
    DLL_EXT :: ".dylib"
} else {
    DLL_EXT :: ".so"
}

copy_dll :: proc(to: string) -> bool {
    exit: i32
    when ODIN_OS == .Windows {
        exit = libc.system(fmt.ctprintf("copy game.dll {0}", to))
    } else {
        exit = libc.system(fmt.ctprintf("cp game" + DLL_EXT + " {0}", to))
    }

    if exit != 0 {
        fmt.printfln("Failed to copy game" + DLL_EXT + " to {0}", to)
        return false
    }

    return true
}

GameAPI :: struct {
    init: proc(),
    update: proc() -> bool,
    shutdown: proc(),

    memory: proc() -> rawptr,
    hot_reloaded: proc(rawptr),

    dllTime: os.File_Time,
    apiVersion: int,
    lib: dynlib.Library,
}

main :: proc() {
    defaultAllocator := context.allocator
    trackingAllocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&trackingAllocator, defaultAllocator)
    context.allocator = mem.tracking_allocator(&trackingAllocator)

    reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> (err: bool) {
        totalLeakedBytes: int
        for _, value in a.allocation_map {
            fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
            totalLeakedBytes += value.size
            err = true
        }
        if err {
            fmt.printf("Total leaked bytes: %v", totalLeakedBytes)
        }
        return
    }

    gameApiVersion := 0
    gameApi, gameApi_Ok := load_game_api(gameApiVersion)
    if !gameApi_Ok {
        fmt.println("Something went wrong trying to load game api")
        return
    }

    gameApiVersion += 1

    gameApi.init()

    for {
        if !gameApi.update() {
            break
        }

        dllLastWriteTime, dllLastWriteTime_Ok := os.last_write_time_by_name("game" + DLL_EXT)
        reload := dllLastWriteTime_Ok == os.ERROR_NONE && dllLastWriteTime != gameApi.dllTime

        if reload {
            // Might fail in case of dll still being written by compiler...
            // well, it will try to load api next frame again
            newGameApi, newGameApi_Ok := load_game_api(gameApiVersion)
            if newGameApi_Ok {
                gameMemory := gameApi.memory()

                unload_game_api(gameApi)

                // Swap old GameAPI with new, and tell new one to
                // use memory of old GameAPI
                gameApi = newGameApi
                gameApi.hot_reloaded(gameMemory)

                gameApiVersion += 1 // to load next dll if compiled
            }
        }
    }

    gameApi.shutdown()
    reset_tracking_allocator(&trackingAllocator)
    unload_game_api(gameApi)

    return
}

load_game_api :: proc(newGameApiVersion: int) -> (api: GameAPI, ok: bool) {
    dllName := fmt.tprintf("{0}game_{1}" + DLL_EXT, "./" when ODIN_OS != .Windows else "", newGameApiVersion)
    copy_dll(dllName)

    count, okT := dynlib.initialize_symbols(&api, dllName, "game_", "lib")
    ok = okT
    if !ok {
        fmt.printfln("Failed to initializing symbols: {0}", dynlib.last_error())
        return
    }
    api.apiVersion = newGameApiVersion

    dllLastWriteTime, dllLastWriteTime_Ok := os.last_write_time_by_name("game"+DLL_EXT)
    api.dllTime = dllLastWriteTime

    return
}

unload_game_api :: proc(gameApi: GameAPI) {
    dllName := fmt.tprintf("game_{0}"+DLL_EXT, gameApi.apiVersion)

    if dynlib.unload_library(gameApi.lib) {
        if err := os.remove(dllName); err != os.ERROR_NONE {
            fmt.printfln("Failed to delete library {0}: {1}", dllName, err)
        }
    } else {
        fmt.printfln("Failed to unload library: {0}", dynlib.last_error())
    }

}

// Make game use good GPU on laptops.

// @(export)
// NvOptimusEnablement: u32 = 1
// @(export)
// AmdPowerXpressRequestHighPerformance: i32 = 1