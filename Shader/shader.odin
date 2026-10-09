package Shader
import rl "vendor:raylib"
import "core:c"

Shader_locations :: struct {
    res_loc : c.int,
    screen_size_loc: c.int,
    light_loc: c.int,
    uTime: c.int
}

Shader_args :: struct {
    target : rl.RenderTexture2D,
    screen_size: rl.Vector2,
    light_pos: rl.Vector2,
    screen_resolution: rl.Vector2
}

Shader_manager :: struct {
    shader: rl.Shader,
    shader_args: Shader_args
}

get_shader_locs :: proc(shader: rl.Shader) -> Shader_locations {
    resolutionLoc := rl.GetShaderLocation(shader, "resolution")
    
       
    screenSizeLoc := rl.GetShaderLocation(shader, "screenSize")
    lightPosLoc   := rl.GetShaderLocation(shader, "lightPos")
    uTimeLoc := rl.GetShaderLocation(shader, "uTime")
    return {
        res_loc = resolutionLoc,
        screen_size_loc = screenSizeLoc,
        light_loc = lightPosLoc,
        uTime = uTimeLoc
    }
}

init_shader :: proc (shader_mg : ^Shader_manager, screen_w, screeen_h : i32) {
    shader_mg.shader = rl.LoadShader("", "shader/shader.frag")
    shader_mg.shader_args.target = rl.LoadRenderTexture(screen_w, screeen_h)

    locs := get_shader_locs(shader_mg.shader)
    resolution := [2]f32 {
        f32(screen_w),
        f32(screeen_h),
    }
    rl.SetShaderValue(
        shader_mg.shader,
        locs.screen_size_loc,
        &resolution[0],
        rl.ShaderUniformDataType.VEC2,
    )
  
    rl.BeginTextureMode(shader_mg.shader_args.target)
    rl.ClearBackground(rl.Color {12, 191, 234, 255})
    rl.EndTextureMode()
}

update_time :: proc(shader_mg : ^Shader_manager, time: rawptr) {
    locs := get_shader_locs(shader_mg.shader)
    rl.SetShaderValue(
        shader_mg.shader,
        locs.uTime,
        time,
        rl.ShaderUniformDataType.FLOAT
    )
}

update_light :: proc(shader_mg : ^Shader_manager, light: rawptr) {
    locs := get_shader_locs(shader_mg.shader)
    rl.SetShaderValue(
        shader_mg.shader,
        locs.light_loc,
        light,
        rl.ShaderUniformDataType.VEC2
    )
}