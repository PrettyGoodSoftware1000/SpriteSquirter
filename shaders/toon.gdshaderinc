// Cel shading shared by every lit shader, in the style of an inked and
// screen-printed comic: sunlight is either on or off, and the edge between
// the two (the shaded side of a shape, the rim of a cast shadow) breaks up
// into halftone dots. A second, brighter band picks out faces turned
// straight at the sun. Shadows get their colour from the ambient light.

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float shade = smoothstep(0.3, 0.6, ATTENUATION);
		float tone = min(smoothstep(-0.04, 0.2, ndl), shade);
		// Dots on a grid turned 45 degrees, 6 pixels apart. They grow with
		// `tone` until they merge into full light.
		vec2 cell = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * FRAGCOORD.xy / 6.0;
		float dots = length(fract(cell) - 0.5);
		float lit = 1.0 - smoothstep(tone * 0.8 - 0.03, tone * 0.8, dots);
		float bright = smoothstep(0.52, 0.58, ndl) * shade;
		DIFFUSE_LIGHT += (lit * 0.66 + bright * 0.34) * LIGHT_COLOR / PI;
	} else {
		// Fires and lamps: two flat bands, fading with distance.
		float band = smoothstep(-0.02, 0.04, ndl) * 0.6 + smoothstep(0.5, 0.56, ndl) * 0.4;
		DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
	}
}
