package main

import "core:strings"
import rl "vendor:raylib"
import fb "FileBrowser"
import shader "Shader"

App_settings :: struct {
    app_time: f32,
    light_pos: rl.Vector2
}
Image :: struct {
    size: rl.Vector2,
    texture : rl.Texture2D
}
App :: struct {
    settings: App_settings,
    file_browser : fb.File_Browser,
    image: Image,
    shader_manager: shader.Shader_manager
}


app_init :: proc(app: ^App) {
    app.file_browser = fb.init_file_browser()
    shader.init_shader(&app.shader_manager, WINDOW_W, WINDOW_H)
}

app_destroy :: proc(app: ^App) {
    
    rl.UnloadTexture(app.image.texture)
    fb.destroy_file_browser(&app.file_browser)
}

app_update:: proc(app: ^App) {

    app.settings.app_time += rl.GetFrameTime() 
    // app.settings.light_pos = {rl.GetMousePosition().x / f32(rl.GetScreenWidth()) , rl.GetMousePosition().y / f32(rl.GetScreenHeight())}
    app.settings.light_pos = {rl.GetMousePosition().x, f32(rl.GetScreenHeight()) - rl.GetMousePosition().y}
    shader.update_time(&app.shader_manager, &app.settings.app_time)
    shader.update_light(&app.shader_manager, &app.settings.light_pos)

    if rl.IsKeyPressed(.H) {
        app.file_browser.is_hidden = !app.file_browser.is_hidden
    }
    confirm, path := fb.update_file_browser(&app.file_browser)
    if confirm {
        texture := rl.LoadTexture(strings.clone_to_cstring(path, context.temp_allocator))
        app.image.texture  = texture
        app.image.size = {f32(texture.width), f32(texture.height)}
        draw_size : rl.Vector2 = { app.image.size.x / app.image.size.y * 960, 960}
        rl.BeginTextureMode(app.shader_manager.shader_args.target)
        rl.ClearBackground(rl.Color{75,75,75,255})

        rl.DrawTexturePro(
            app.image.texture, 
            rl.Rectangle{
                x = 0,
                y = 0,
                width = app.image.size.x,
                height = app.image.size.y
            },
            rl.Rectangle {
                x = f32(rl.GetScreenWidth() ) / 2 - draw_size.x / 2,
                y = 0,
                width = draw_size.x,
                height = draw_size.y
            },
            0,
            0,
            rl.WHITE
        )
        rl.EndTextureMode()
    }
}

app_draw :: proc(app: ^App) {
    
    
    shader_target := app.shader_manager.shader_args.target
    rl.BeginShaderMode(app.shader_manager.shader)
    rl.DrawTextureRec(
        shader_target.texture,
        rl.Rectangle{
            0,
            0,
            f32(shader_target.texture.width),
            -f32(shader_target.texture.height),
        },
        rl.Vector2{0, 0},
        rl.WHITE,
    )
    rl.EndShaderMode()
    
    if !app.file_browser.is_hidden {
        if rl.GuiButton({0, 0, 50, 40}, "Load") {
            fb.open_file_browser(&app.file_browser)
        }
    }
    fb.draw_file_browser(&app.file_browser)
}