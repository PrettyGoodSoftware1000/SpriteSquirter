shader_type spatial;
// The creature's hide. Colours are painted per vertex by the model baker
// (alpha = how scaly the spot is). Scales are projected from the rest pose,
// stored in UV (x, y) and UV2 (z), so they stick to the skin as it moves.

uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.55;
uniform float bump = 0.05;
uniform float roughness = 0.6;

varying vec3 rest_pos;

void vertex() {
	rest_pos = vec3(UV.x, UV.y, UV2.x);
}

void fragment() {
	// Triplanar weights from the rest-pose surface direction.
	vec3 rc = cross(dFdx(rest_pos), dFdy(rest_pos));
	vec3 rn = dot(rc, rc) > 1e-14 ? normalize(rc) : vec3(0.0, 1.0, 0.0);
	vec3 w = pow(abs(rn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = rest_pos * tex_scale;
	vec3 d = texture(detail_tex, p.zy).rgb * w.x + texture(detail_tex, p.xz).rgb * w.y + texture(detail_tex, p.xy).rgb * w.z;

	float scaly = clamp(COLOR.a, 0.0, 1.0);
	float lum = mix(0.85 + 0.15 * d.r, 0.4 + 0.8 * d.r, scaly);
	// max() matters: at polygon edges the interpolated colour can dip below zero.
	vec3 albedo = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)) * lum;
	albedo = mix(albedo, albedo * vec3(1.15, 1.05, 0.8), d.g * scaly * 0.5);

	// Bump the lighting using the height stored in the blue channel.
	float hgt = d.b * scaly;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(hgt);
	float dhdy = dFdy(hgt);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	vec3 bumped = abs(det) * NORMAL - bump * grad;
	if (abs(det) > 1e-12 && dot(bumped, bumped) > 1e-20) {
		NORMAL = normalize(bumped);
	}

	ALBEDO = albedo;
	ROUGHNESS = mix(0.35, roughness, scaly);
	SPECULAR = 0.45;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
