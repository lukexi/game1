#version 330 core

layout (location = 0) in vec3 in_pos;

layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_tex_coords;
layout (location = 3) in vec3 in_tangent_normal;
layout (location = 4) in vec3 in_color;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
    gl_Position = projection * view * model * vec4(in_pos, 1.0);
}
