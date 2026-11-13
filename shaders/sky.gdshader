shader_type sky;
// Soft painted sky: a three-colour gradient, a glowing sun and drifting
// cloud banks. All colours are driven by the Atmosphere moods.

uniform vec3 top_color : source_color = vec3(0.35, 0.5, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.82, 0.76);
uniform vec3 ground_color : source_color = vec3(0.4, 0.45, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.62, 0.7);
uniform float cloud_cover = 0.5;
uniform float sun_glow = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void sky() {
	float y = EYEDIR.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(y, 0.0, 1.0), 0.45));
	// Below the horizon the sky carries on: the island floats above it.
	col = mix(col, ground_color, smoothstep(0.0, -0.6, y));

	float sun_dot = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(sun_dot, 6.0) * 0.35 + pow(sun_dot, 60.0) * 0.6) * sun_glow;
	col += sun_color * smoothstep(0.9993, 0.9997, sun_dot) * 6.0 * sun_glow;

	// Flat-toned cartoon clouds above, and a sea of cloud far below.
	float up = abs(y);
	vec2 uv = EYEDIR.xz / (up + 0.12);
	float scale = y > 0.0 ? 0.045 : 0.07;
	float n = texture(noise_tex, uv * scale).r * 0.6 + texture(noise_tex, uv * scale * 2.4 + 0.4).g * 0.4;
	float cover = y > 0.0 ? cloud_cover : cloud_cover + 0.06;
	float c = smoothstep(1.0 - cover, 1.02 - cover, n);
	float lit = step(0.5, texture(noise_tex, uv * scale + LIGHT0_DIRECTION.xz * 0.03).r);
	vec3 cloud = mix(cloud_shade, cloud_color, lit);
	col = mix(col, cloud, c * smoothstep(0.02, 0.16, up) * 0.92);
	COLOR = col;
}
