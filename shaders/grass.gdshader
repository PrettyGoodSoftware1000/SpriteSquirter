shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// Instanced grass. Every terrain chunk reuses the same patch of blade
// clumps; this shader lifts each clump onto the terrain using the height
// texture and hides it on rock, sand, snow, bare dirt, burnt ground, under
// water and off the edge of the island.
// Vertex colour R = 0 at the root, 1 at the tip of a blade.

// Samples along one side of the terrain data textures (map size + 1).
uniform float world_n = 257.0;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D scorch_tex : filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 color_root : source_color = vec3(0.1, 0.24, 0.06);
uniform vec3 color_tip : source_color = vec3(0.4, 0.6, 0.15);
uniform vec3 color_dry : source_color = vec3(0.62, 0.62, 0.22);
uniform float wind_strength = 0.3;
uniform float fade_start = 110.0;
uniform float fade_end = 160.0;

varying float v_t;
varying vec3 v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 muv = (origin.xz + world_n * 0.5) / world_n;
	float texel = 1.0 / world_n;
	float h = textureLod(height_tex, muv, 0.0).r;
	float hx = textureLod(height_tex, muv + vec2(texel, 0.0), 0.0).r;
	float hz = textureLod(height_tex, muv + vec2(0.0, texel), 0.0).r;
	float hxm = textureLod(height_tex, muv - vec2(texel, 0.0), 0.0).r;
	float hzm = textureLod(height_tex, muv - vec2(0.0, texel), 0.0).r;
	vec3 ground = textureLod(ground_tex, muv, 0.0).rgb;
	float slope = length(vec2(hx - h, hz - h));
	float scorch = textureLod(scorch_tex, muv, 0.0).r;
	float bare = textureLod(mask_tex, muv, 0.0).r;
	vec3 nz = textureLod(noise_tex, origin.xz * 0.02, 0.0).rgb;
	vec3 nz2 = textureLod(noise_tex, origin.xz * 0.11 + 0.3, 0.0).rgb;

	// Nothing grows near the void, on sand or stone, or under water.
	float grow = step(-20.0, min(min(h, hx), min(min(hz, hxm), hzm)));
	grow *= 1.0 - smoothstep(0.3, 0.7, ground.r + (nz2.r - 0.5) * 0.5);
	grow *= 1.0 - smoothstep(0.25, 0.6, ground.g + (nz2.g - 0.5) * 0.4);
	grow *= 1.0 - step(0.02, ground.b);
	grow *= 1.0 - smoothstep(0.2, 0.36, slope * 0.75 + (nz2.g - 0.5) * 0.12);
	grow *= 1.0 - smoothstep(29.0, 32.5, h + (nz.b - 0.5) * 4.0);
	grow *= 1.0 - smoothstep(0.25, 0.55, bare + (nz2.b - 0.5) * 0.4);
	grow *= 1.0 - smoothstep(0.1, 0.4, scorch);
	grow *= 0.6 + 0.8 * nz2.g;
	float dist = distance(CAMERA_POSITION_WORLD, origin + vec3(0.0, h, 0.0));
	grow *= 1.0 - smoothstep(fade_start, fade_end, dist);

	float t = COLOR.r;
	vec3 local = (VERTEX - origin) * grow;
	float gust = textureLod(noise_tex, origin.xz * 0.012 + vec2(TIME * 0.035, TIME * 0.02), 0.0).r;
	float phase = TIME * 2.1 + origin.x * 0.45 + origin.z * 0.3;
	vec2 lean = vec2(1.0, 0.45) * (sin(phase) * 0.35 + (gust - 0.35) * 1.6) * wind_strength * t * t * grow;
	VERTEX = origin + local + vec3(lean.x, h - abs(lean.x) * 0.25, lean.y);
	NORMAL = normalize(vec3(lean.x * 0.6, 1.0, lean.y * 0.6));

	v_t = t;
	v_tint = mix(vec3(1.0), color_dry / color_tip, smoothstep(0.5, 0.8, nz.g) * 0.55) * (0.8 + 0.4 * nz.r);
}

void fragment() {
	// Two flat tones per blade: dark base, bright tip.
	vec3 albedo = mix(color_root, color_tip * v_tint, 0.25 + 0.75 * smoothstep(0.4, 0.5, v_t));
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

#include "res://shaders/toon.gdshaderinc"
