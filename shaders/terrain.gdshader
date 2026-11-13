shader_type spatial;
// Terrain surface: grass, dirt, sand, rock and snow blended by height,
// slope and the masks painted by gameplay (bare ground and scorch marks).

uniform sampler2D scorch_tex : filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.14, 0.3, 0.08);
uniform vec3 grass_b : source_color = vec3(0.26, 0.44, 0.1);
uniform vec3 grass_dry : source_color = vec3(0.5, 0.5, 0.18);
uniform vec3 dirt_a : source_color = vec3(0.40, 0.31, 0.21);
uniform vec3 dirt_b : source_color = vec3(0.3, 0.22, 0.15);
uniform vec3 rock_a : source_color = vec3(0.46, 0.43, 0.4);
uniform vec3 rock_b : source_color = vec3(0.33, 0.32, 0.33);
uniform vec3 sand_color : source_color = vec3(0.72, 0.62, 0.42);
uniform vec3 snow_color : source_color = vec3(0.9, 0.92, 0.96);

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Everything below this height is the void around the floating island.
	if (w_pos.y < -14.0) {
		discard;
	}
	vec3 n = normalize(w_nrm);
	vec2 muv = (w_pos.xz + 128.5) / 257.0;
	float scorch = texture(scorch_tex, muv).r;
	float bare = texture(mask_tex, muv).r;
	vec3 nz = texture(noise_tex, w_pos.xz * 0.02).rgb;
	vec3 nz2 = texture(noise_tex, w_pos.xz * 0.11 + 0.3).rgb;
	float h = w_pos.y;
	float slope = 1.0 - n.y;

	vec3 gd = texture(ground_detail, w_pos.xz * 0.21).rgb;
	vec3 dd = texture(dirt_detail, w_pos.xz * 0.3).rgb;
	vec3 gn = texture(ground_normal, w_pos.xz * 0.21).xyz * 2.0 - 1.0;
	vec3 dn = texture(dirt_normal, w_pos.xz * 0.3).xyz * 2.0 - 1.0;

	vec3 grass = mix(grass_a, grass_b, nz.r);
	grass = mix(grass, grass_dry, smoothstep(0.5, 0.8, nz.g) * 0.45);
	grass *= mix(0.86, 1.0, smoothstep(0.6, 0.64, gd.r));
	vec3 dirt = mix(dirt_a, dirt_b, smoothstep(0.45, 0.5, dd.g)) * mix(0.85, 1.0, smoothstep(0.6, 0.64, dd.r));
	vec3 sand = sand_color * mix(0.9, 1.0, smoothstep(0.6, 0.64, dd.r));

	float dirt_w = smoothstep(0.25, 0.55, bare + (nz2.b - 0.5) * 0.4);
	float sand_w = 1.0 - smoothstep(0.35, 1.1, h + (nz2.r - 0.5) * 0.6);
	float rock_w = smoothstep(0.2, 0.36, slope + (nz2.g - 0.5) * 0.12);
	float snow_w = smoothstep(30.0, 34.0, h + (nz.b - 0.5) * 4.0) * (1.0 - smoothstep(0.4, 0.6, slope));

	vec3 albedo = mix(grass, dirt, dirt_w);
	vec3 flat_n = mix(gn, dn, dirt_w);
	albedo = mix(albedo, sand, sand_w);
	flat_n = mix(flat_n, dn * vec3(0.4, 0.4, 1.0), sand_w);
	vec3 ground_n = normalize(vec3(n.x + flat_n.x * 0.15, n.y, n.z + flat_n.y * 0.15));

	// Rock, projected from three sides so cliffs do not stretch.
	vec3 w = pow(abs(n), vec3(5.0));
	w /= (w.x + w.y + w.z);
	vec3 rp = w_pos * 0.16;
	vec3 rd = texture(rock_detail, rp.zy).rgb * w.x + texture(rock_detail, rp.xz).rgb * w.y + texture(rock_detail, rp.xy).rgb * w.z;
	vec3 tx = texture(rock_normal, rp.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(rock_normal, rp.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(rock_normal, rp.xy).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy * 0.3 + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy * 0.3 + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy * 0.3 + n.xy, abs(tz.z) * n.z);
	vec3 rock_n = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	// Flat rock tones with ink lines in the cracks.
	vec3 rock = mix(rock_a, rock_b, smoothstep(0.45, 0.5, rd.g)) * mix(0.2, 1.0, smoothstep(0.4, 0.5, rd.r));

	albedo = mix(albedo, rock, rock_w);
	vec3 final_n = normalize(mix(ground_n, rock_n, rock_w));
	albedo = mix(albedo, snow_color, snow_w);
	final_n = normalize(mix(final_n, n, snow_w * 0.7));

	// Damp sand at the waterline, then burn marks on top of everything.
	albedo *= mix(0.55, 1.0, smoothstep(-0.3, 0.45, h));
	albedo = mix(albedo, vec3(0.03, 0.027, 0.025) * (0.6 + 0.8 * dd.r), clamp(scorch * 0.95, 0.0, 1.0));

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(final_n, 0.0)).xyz);
}

#include "res://shaders/toon.gdshaderinc"
