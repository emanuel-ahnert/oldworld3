// An enemy's health bar over its name (enemy.gd): a black border, the dark empty part and the
// filled part in the plate's colour, slightly lighter at the top. Always faces the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec2 size = vec2(1.1, 0.13);    // m, the quad's size
uniform float border = 0.022;           // m
instance uniform float fill = 1.0;
instance uniform vec4 color : source_color = vec4(0.85, 0.12, 0.08, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec2 p = UV * size;
	vec3 c = vec3(0.0);
	if (p.x > border && p.x < size.x - border && p.y > border && p.y < size.y - border) {
		float u = (p.x - border) / (size.x - 2.0 * border);
		c = u <= fill ? color.rgb * (1.15 - 0.4 * UV.y) : vec3(0.07, 0.06, 0.06);
	}
	ALBEDO = c;
}
