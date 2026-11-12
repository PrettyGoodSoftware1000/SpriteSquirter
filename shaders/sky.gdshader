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
	col = mix(col, ground_color, smoothstep(0.0, -0.25, y));

	float sun_dot = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (pow(sun_dot, 6.0) * 0.35 + pow(sun_dot, 60.0) * 0.6) * sun_glow;
	col += sun_color * smoothstep(0.9993, 0.9997, sun_dot) * 6.0 * sun_glow;

	if (y > 0.0) {
		vec2 uv = EYEDIR.xz / (y + 0.12);
		float n = texture(noise_tex, uv * 0.045).r * 0.6 + texture(noise_tex, uv * 0.11 + 0.4).g * 0.4;
		float c = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover * 0.55, n);
		float lit = smoothstep(0.2, 0.9, texture(noise_tex, uv * 0.045 + LIGHT0_DIRECTION.xz * 0.02).r);
		vec3 cloud = mix(cloud_shade, cloud_color, lit) + sun_color * pow(sun_dot, 8.0) * 0.4;
		col = mix(col, cloud, c * smoothstep(0.0, 0.18, y) * 0.9);
	}
	COLOR = col;
}
