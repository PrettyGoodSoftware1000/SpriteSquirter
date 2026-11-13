// Cel shading shared by every lit shader: light lands in flat bands with a
// hard edge instead of a smooth gradient, and sun shadows have crisp edges.

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.02, 0.04, ndl) * 0.6 + smoothstep(0.5, 0.56, ndl) * 0.4;
	float att = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		att = smoothstep(0.3, 0.6, att);
	}
	DIFFUSE_LIGHT += band * att * LIGHT_COLOR / PI;
}
