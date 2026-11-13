shader_type spatial;
render_mode cull_disabled;
// A sheet of falling water with streaks of foam, fading into mist at the
// bottom. UV.x runs across the fall, UV.y from the lip (0) to the end (1).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.6, 0.58);
uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.4);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 0.97);

void fragment() {
	float a = texture(noise_tex, vec2(UV.x * 1.3, UV.y * 2.2 - TIME * 0.55)).r;
	float b = texture(noise_tex, vec2(UV.x * 3.1 + 0.3, UV.y * 5.0 - TIME * 0.9)).g;
	float streak = step(0.5, a * 0.55 + b * 0.45);
	float mist = smoothstep(0.35, 1.0, UV.y);
	vec3 water = mix(shallow_color, deep_color, step(0.5, a) * 0.4);
	ALBEDO = mix(water, foam_color, max(streak * 0.75, mist));
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	ALPHA = edge * (1.0 - smoothstep(0.55, 1.0, UV.y)) * mix(0.9, 1.0, streak);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
}

#include "res://shaders/toon.gdshaderinc"
