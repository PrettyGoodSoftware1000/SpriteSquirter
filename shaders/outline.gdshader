shader_type spatial;
render_mode unshaded, cull_front;
// Ink outline: draws the back faces of a mesh, pushed outwards, in black.
// Used as the second pass of surface materials. The line keeps roughly the
// same thickness on screen whatever the distance.

uniform vec3 ink_color : source_color = vec3(0.045, 0.035, 0.055);
uniform float width = 1.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(world, CAMERA_POSITION_WORLD);
	float model_scale = length(MODEL_MATRIX[0].xyz);
	VERTEX += NORMAL * width * clamp(dist * 0.0026, 0.02, 0.5) / model_scale;
}

void fragment() {
	ALBEDO = ink_color;
}
