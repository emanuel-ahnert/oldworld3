// The well's hole (settlement.gd): a disc on the ground inside the ring, dark stone at its edge
// fading to black in the middle, so the shaft seems to go down without end.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float radius = 1.0;
varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float r = length(lp) / radius;
	ALBEDO = mix(vec3(0.0), vec3(0.016, 0.014, 0.012), smoothstep(0.45, 1.0, r));   // linear: dark brown-grey on screen
}
