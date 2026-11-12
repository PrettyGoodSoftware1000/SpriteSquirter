shader_type spatial;
// Stylised water. Depth comes from the terrain height texture, so shallows
// are clear and turquoise, deep water is dark, and foam hugs the shore.

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.6, 0.58);
uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.4);
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 0.95);
uniform float water_level = 0.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float wave_height(vec2 p) {
	float a = texture(noise_tex, p * 0.035 + vec2(TIME * 0.012, TIME * 0.007)).r;
	float b = texture(noise_tex, p * 0.09 - vec2(TIME * 0.016, -TIME * 0.011)).g;
	float c = texture(noise_tex, p * 0.31 + vec2(-TIME * 0.03, TIME * 0.02)).b;
	return a * 0.5 + b * 0.35 + c * 0.15;
}

void fragment() {
	vec2 muv = (w_pos.xz + 128.5) / 257.0;
	float inside = step(abs(w_pos.x), 128.0) * step(abs(w_pos.z), 128.0);
	float ground = mix(-4.5, texture(height_tex, muv).r, inside);
	float depth = max(water_level - ground, 0.0);

	float e = 0.35;
	float h0 = wave_height(w_pos.xz);
	float hx = wave_height(w_pos.xz + vec2(e, 0.0));
	float hz = wave_height(w_pos.xz + vec2(0.0, e));
	vec3 wn = normalize(vec3((h0 - hx) * 2.2, 1.0, (h0 - hz) * 2.2));

	float ripple = texture(noise_tex, w_pos.xz * 0.4 + vec2(TIME * 0.05, 0.0)).b;
	float foam_line = smoothstep(0.3, 0.0, depth + (ripple - 0.5) * 0.25 + sin(TIME * 1.3 + depth * 9.0) * 0.05);
	float foam = clamp(foam_line * step(0.4, ripple + foam_line * 0.45), 0.0, 1.0) * 0.85;

	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, 3.5, depth));
	ALBEDO = mix(water, foam_color, foam);
	ALPHA = clamp(mix(0.45, 0.97, smoothstep(0.0, 1.6, depth)) + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.06, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
