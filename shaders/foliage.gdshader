shader_type spatial;
render_mode cull_disabled;
// Leaf cards for tree canopies and bushes. Normals point away from the
// middle of each clump so the whole canopy shades like one soft volume.
// Vertex colour: R = brightness, G = how much the wind moves the vertex.

uniform sampler2D leaf_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 color_dark : source_color = vec3(0.1, 0.25, 0.06);
uniform vec3 color_light : source_color = vec3(0.4, 0.6, 0.12);
uniform float wind = 1.0;

instance uniform float burn = 0.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * 1.7 + w_pos.x * 0.31 + w_pos.z * 0.23;
	float flutter = sin(TIME * 5.3 + w_pos.x * 2.1 + w_pos.y * 1.7 + w_pos.z * 1.3);
	vec3 sway = vec3(sin(phase) * 0.12 + flutter * 0.025, flutter * 0.02, cos(phase * 0.8) * 0.08);
	VERTEX += sway * COLOR.g * wind;
}

void fragment() {
	vec4 leaf = texture(leaf_tex, UV);
	// Leaves burn away one by one as the fire takes hold.
	float gone = smoothstep(0.25, 1.0, burn) * 1.05;
	if (leaf.a < 0.5 || leaf.g < gone) {
		discard;
	}
	vec3 albedo = mix(color_dark, color_light, clamp(max(COLOR.r, 0.0) * (0.55 + 0.6 * leaf.r), 0.0, 1.0));
	albedo *= 0.85 + 0.3 * leaf.g;
	vec3 burnt = mix(vec3(0.3, 0.14, 0.04), vec3(0.03), smoothstep(0.3, 0.8, burn));
	albedo = mix(albedo, burnt, smoothstep(0.0, 0.4, burn));
	float ember = smoothstep(0.1, 0.4, burn) * (1.0 - smoothstep(0.6, 1.0, burn)) * step(0.88, fract(leaf.g * 7.0 + TIME * 0.6));
	ALBEDO = albedo;
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	BACKLIGHT = color_light * 0.8 * (1.0 - burn);
	// A touch of self-glow stands in for light scattered inside the canopy.
	EMISSION = vec3(1.0, 0.35, 0.05) * ember * 2.0 + albedo * 0.07 * (1.0 - burn);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
