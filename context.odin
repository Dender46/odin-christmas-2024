package graphs

import rl "vendor:raylib"

Window :: struct {
    name            : cstring,
    posX            : i32,
    posY            : i32,
    width           : i32,
    height          : i32,
    fps             : i32,
    configFlags     : rl.ConfigFlags,
}

SnowParticle :: struct {
    color           : rl.Color,
    pos             : rl.Vector2,
    radius          : f32,
}

Context :: struct {
    window                  : Window,
    textures                : [dynamic]rl.Texture2D,
    models                  : [dynamic]rl.Model,
    snowParticles           : [256]SnowParticle,

    newSnowParticleTimer    : f32,

    perlinTex               : rl.Texture2D,
}

ctx: ^Context