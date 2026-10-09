package main

import rl "vendor:raylib"
import "core:mem"

import "core:fmt"

WINDOW_W :: 1680
WINDOW_H :: 960
main :: proc() {
    rl.InitWindow(WINDOW_W, WINDOW_H, "Image")
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)
    app := App {}
    app_init(&app)
    defer {
        app_destroy(&app)
        mem.tracking_allocator_destroy(&track)
        
        free_all(context.temp_allocator)

        for _, entry in track.allocation_map {
            fmt.eprintf("%v leak %v bytes \n", entry.location, entry.size)
        }
        for entry in track.bad_free_array {
            fmt.eprintf("%v bad free \n", entry.location)
            
        }
        rl.CloseWindow()

    }
    for !rl.WindowShouldClose() {
        app_update(&app)
        rl.BeginDrawing()
        rl.ClearBackground(rl.GRAY)

        app_draw(&app)
        rl.EndDrawing()
    }
}