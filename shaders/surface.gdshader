shader_type spatial;
// Stylised textured surface for buildings, rocks, trunks and villagers.
// Textures are projected from three sides in object space (triplanar), so
// meshes need no UVs and pieces keep their texture when they fly apart.

uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.6);
uniform vec3 color_b : source_color = vec3(0.45);
uniform vec3 moss_color : source_color = vec3(0.2, 0.34, 0.1);
uniform float tex_scale = 0.4;
uniform float normal_strength = 1.0;
uniform float roughness = 0.85;
uniform float moss = 0.0;
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_energy = 0.0;

instance uniform float burn = 0.0;
instance uniform vec3 tint : source_color = vec3(1.0);

varying vec3 o_pos;
varying vec3 o_nrm;

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
}

void fragment() {
	vec3 n = normalize(o_nrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 p = o_pos * tex_scale;

	vec3 d = texture(detail_tex, p.zy).rgb * w.x + texture(detail_tex, p.xz).rgb * w.y + texture(detail_tex, p.xy).rgb * w.z;

	vec3 tx = texture(normal_tex, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(normal_tex, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(normal_tex, p.xy).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy * normal_strength + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy * normal_strength + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy * normal_strength + n.xy, abs(tz.z) * n.z);
	vec3 obj_n = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	vec3 world_n = normalize(MODEL_NORMAL_MATRIX * obj_n);

	// Vertex colours are authored like colour-picker values, so convert them.
	vec3 albedo = mix(color_a, color_b, d.g) * (0.3 + 0.9 * d.r) * tint * pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float moss_w = moss * smoothstep(0.35, 0.8, world_n.y + (d.b - 0.5) * 0.5);
	albedo = mix(albedo, moss_color * (0.6 + 0.6 * d.r), moss_w);

	// Burning: char the surface and let embers glow in the cracks.
	float flicker = 0.7 + 0.3 * sin(TIME * 9.0 + o_pos.x * 3.0 + o_pos.y * 5.0);
	float cracks = pow(clamp(1.0 - d.b, 0.0, 1.0), 9.0) * smoothstep(0.35, 0.6, fract(d.g * 3.7 + d.r * 1.3));
	float ember = smoothstep(0.02, 0.35, burn) * (1.0 - smoothstep(0.7, 1.0, burn)) * cracks * flicker;
	albedo = mix(albedo, vec3(0.035, 0.03, 0.028) * (0.5 + d.r), smoothstep(0.0, 0.85, burn));

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	EMISSION = vec3(1.0, 0.32, 0.04) * ember * 5.0 + glow_color * glow_energy * (0.6 + 0.4 * d.r);
}
