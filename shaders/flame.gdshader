shader_type spatial;
render_mode unshaded, cull_back;
// A tongue of flame as a solid shape, for CPUParticles3D: a teardrop one
// unit tall that sways as it rises. Being a real shape (not a sprite) it
// looks right from above as well as from the side. Colour comes in hard
// bands, hottest where the shape faces the camera and low down, cooling
// towards the tip, the rim and with the particle's age (the colour ramp's
// alpha runs from 1 to 0 over its life).

uniform float glow = 2.4;

varying float v_seed;
varying float v_h;

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.61803);
	v_h = clamp(VERTEX.y, 0.0, 1.0);
	float t = TIME * 6.0 + v_seed * 40.0;
	// The base stays put; the tip whips about.
	float bend = v_h * v_h;
	VERTEX.x += (sin(t + VERTEX.y * 4.0) * 0.16 + sin(t * 1.7 + 1.3) * 0.08) * bend;
	VERTEX.z += (cos(t * 0.9 + VERTEX.y * 3.0) * 0.16 + sin(t * 1.3 + 4.0) * 0.08) * bend;
}

void fragment() {
	float age = 1.0 - COLOR.a;
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float heat = facing * 0.75 + (1.0 - v_h) * 0.45 - age * 0.75 - 0.3;
	vec3 fire = vec3(0.82, 0.13, 0.03);
	fire = mix(fire, vec3(1.0, 0.42, 0.05), step(0.05, heat));
	fire = mix(fire, vec3(1.0, 0.78, 0.2), step(0.3, heat));
	fire = mix(fire, vec3(1.0, 0.96, 0.66), step(0.55, heat));
	ALBEDO = fire * glow;
}
