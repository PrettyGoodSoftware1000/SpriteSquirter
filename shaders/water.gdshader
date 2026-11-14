shader_type spatial;
// Cel-shaded water for lakes and rivers. The mesh sits at the water's
// surface (lakes can be at any height); depth is the surface minus the
// terrain height texture: flat colour bands by depth, a hard foam line
// along the shore, and drifting highlight streaks.

// Samples along one side of the terrain data textures (map size + 1).
uniform float world_n = 257.0;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.6, 0.58);
uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.4);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 0.97);

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 muv = (w_pos.xz + world_n * 0.5) / world_n;
	float ground = texture(height_tex, muv).r;
	// No water on dry land or out in the void.
	if (ground > w_pos.y + 0.02 || ground < -40.0) {
		discard;
	}
	float depth = w_pos.y - ground;
	float ripple = texture(noise_tex, w_pos.xz * 0.35 + vec2(TIME * 0.05, TIME * 0.02)).b;
	float streaks = texture(noise_tex, w_pos.xz * vec2(0.06, 0.2) + vec2(TIME * 0.04, 0.0)).r;
	float foam = step(depth + (ripple - 0.5) * 0.25 + sin(TIME * 1.3 + depth * 9.0) * 0.05, 0.16);
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.55, 0.65, depth));
	water = mix(water, shallow_color * 1.25, step(0.68, streaks) * 0.5);
	ALBEDO = mix(water, foam_color, foam);
	ALPHA = mix(0.82, 1.0, foam);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

#include "res://shaders/toon.gdshaderinc"
