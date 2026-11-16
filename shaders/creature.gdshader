shader_type spatial;
// The creature's skin, cel shaded. Colours are painted per vertex by the
// model baker (alpha = how scaly the spot is). Scales are projected from the
// rest pose, stored in UV (x, y) and UV2 (z), so they stick to the skin as
// it moves, and are drawn as flat tones with ink lines between them.
// UV2.y is how much the spot glows (the Balrog's armour and scar), and
// crack_glow lights the lines between the scales like cooling lava.

uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.4;
uniform vec3 crack_glow : source_color = vec3(0.0);

varying vec3 rest_pos;
varying float glow;

void vertex() {
	rest_pos = vec3(UV.x, UV.y, UV2.x);
	glow = UV2.y;
}

void fragment() {
	vec3 rc = cross(dFdx(rest_pos), dFdy(rest_pos));
	vec3 rn = dot(rc, rc) > 1e-14 ? normalize(rc) : vec3(0.0, 1.0, 0.0);
	vec3 w = pow(abs(rn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = rest_pos * tex_scale;
	vec3 d = texture(detail_tex, p.zy).rgb * w.x + texture(detail_tex, p.xz).rgb * w.y + texture(detail_tex, p.xy).rgb * w.z;

	float scaly = clamp(COLOR.a, 0.0, 1.0);
	float line = mix(1.0, mix(0.3, 1.0, smoothstep(0.34, 0.44, d.r)), scaly);
	float tone = mix(1.0, mix(0.84, 1.0, smoothstep(0.5, 0.55, d.g)), scaly);
	// max() matters: at polygon edges the interpolated colour can dip below zero.
	ALBEDO = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)) * line * tone;
	float lit = clamp(glow, 0.0, 1.0);
	// The glow breathes, like embers in a draught.
	float ember = 0.75 + 0.25 * sin(TIME * 2.6 + rest_pos.y * 1.7 + rest_pos.x * 2.3);
	EMISSION = ALBEDO * lit * 1.3 * ember + crack_glow * ember * (1.0 - smoothstep(0.3, 0.42, d.r)) * scaly * (1.0 - lit);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

#include "res://shaders/toon.gdshaderinc"
