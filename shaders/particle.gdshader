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
// 1 draws a flame tongue instead of the sprite: a wavering teardrop with
// ragged edges and hard bands of colour, different for every particle.
uniform float flame = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying float v_seed;

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.61803);
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	world = world * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	world = world * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	if (flame > 0.5) {
		vec2 uv = vec2(UV.x, 1.0 - UV.y);
		// The colour ramp's alpha runs from 1 to 0 over the particle's life.
		float age = 1.0 - COLOR.a;
		float t = TIME * 1.7 + v_seed * 20.0;
		float sway = texture(noise_tex, vec2(v_seed * 3.1, uv.y * 0.35 - t * 0.22)).r - 0.5;
		float x = uv.x - 0.5 - sway * 0.6 * uv.y;
		float width = 0.34 * pow(clamp(1.0 - uv.y, 0.0, 1.0), 0.75) * smoothstep(0.0, 0.16, uv.y);
		float ragged = texture(noise_tex, vec2(uv.x * 0.9 + v_seed, uv.y * 0.5 - t * 0.3)).g - 0.5;
		float d = abs(x) / max(width, 0.001) + ragged * 0.9 * (0.3 + uv.y) + age * 0.7;
		// Hottest in the middle and low down; cooler towards the tip and with age.
		float heat = 1.0 - d - uv.y * 0.5 - age * 0.3;
		vec3 fire = vec3(0.82, 0.13, 0.03);
		fire = mix(fire, vec3(1.0, 0.42, 0.05), step(0.05, heat));
		fire = mix(fire, vec3(1.0, 0.78, 0.2), step(0.3, heat));
		fire = mix(fire, vec3(1.0, 0.96, 0.66), step(0.55, heat));
		ALBEDO = fire * glow;
		ALPHA = 1.0 - smoothstep(0.9, 1.0, d);
	} else {
	vec4 sprite = texture(sprite_tex, vec2(UV.x, 1.0 - UV.y));
	// With the ramp on, the sprite's bright core picks the hot colour.
	vec3 ramp = mix(color_cool, color_hot, sprite.r);
	vec3 base = mix(vec3(sprite.r), ramp, use_ramp);
	ALBEDO = base * COLOR.rgb * ambient * glow;
	ALPHA = sprite.a * COLOR.a;
	}
}
