shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Camera-facing sprite for CPUParticles3D: flames, embers, smoke and dust.
// `glow` above 1 pushes flames into the bloom range. Smoke and dust set
// `ambient` so they darken with the time of day.

uniform sampler2D sprite_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 color_hot : source_color = vec3(1.0, 0.85, 0.3);
uniform vec3 color_cool : source_color = vec3(1.0, 0.3, 0.05);
uniform vec3 ambient : source_color = vec3(1.0);
uniform float glow = 1.0;
uniform float use_ramp = 1.0;

void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	world = world * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	world = world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 sprite = texture(sprite_tex, vec2(UV.x, 1.0 - UV.y));
	// With the ramp on, the sprite's bright core picks the hot colour.
	vec3 ramp = mix(color_cool, color_hot, sprite.r);
	vec3 base = mix(vec3(sprite.r), ramp, use_ramp);
	ALBEDO = base * COLOR.rgb * ambient * glow;
	ALPHA = sprite.a * COLOR.a;
}
