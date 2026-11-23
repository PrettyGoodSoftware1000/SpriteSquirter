shader_type spatial;
// A giant with a painted texture (a Meshy model, UV mapped), cel shaded like
// everything else: flat bands of light from toon.gdshaderinc, and the ink
// outline as a second pass. The hottest parts of the texture glow: the
// bright, strongly coloured spots (lava cracks, a fiery mouth, glowing
// armour and eyes) breathe like embers in a draught. Dull or dark colours
// (hide, horn, bone, iron) never glow.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
// How brightly the hot spots glow, and from how bright and how strongly
// coloured a texel counts as hot.
uniform float glow = 1.6;
uniform float glow_from = 0.55;
uniform float glow_saturation = 0.55;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 c = tex.rgb;
	float top = max(c.r, max(c.g, c.b));
	float low = min(c.r, min(c.g, c.b));
	float sat = top > 0.001 ? (top - low) / top : 0.0;
	// Measured in the texture's own (sRGB) brightness, so the cut-offs read
	// as they look in an image editor.
	vec3 srgb = pow(c, vec3(1.0 / 2.2));
	float bright = max(srgb.r, max(srgb.g, srgb.b));
	float hot = smoothstep(glow_from, glow_from + 0.2, bright) * smoothstep(glow_saturation, glow_saturation + 0.2, sat);
	float ember = 0.75 + 0.25 * sin(TIME * 2.6 + UV.x * 23.0 + UV.y * 17.0);
	ALBEDO = c;
	EMISSION = c * hot * glow * ember;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

#include "res://shaders/toon.gdshaderinc"
