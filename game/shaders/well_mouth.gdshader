// The well's opening (settlement.gd): an invisible disc on the ground inside the ring that marks
// where the shaft can be seen (stencil 1). Depth-tested like anything else, so the ring and
// people in front of it hide it; it writes no colour and no depth.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
