// The well's shaft below the ground (well.gd): the ring's inner wall going on down, darkening to
// a black bottom; drawn only where the opening was seen (stencil 1) and through the terrain.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_front, shadows_disabled, fog_disabled;
stencil_mode read, compare_equal, 1;
#include "well_stone.gdshaderinc"

uniform float depth = 3.5;
uniform float radius = 0.72;
uniform float rim = 0.85;
uniform vec3 light = vec3(0.8, 0.8, 0.78);     // how the lit inner wall looks at the ground

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float d = clamp(-lp.y / depth, 0.0, 1.0);
	// The same stones as above ground, as dark as the inner wall is at the ground, then darker.
	float relief;
	vec3 c = stone_color(lp, radius, relief) * (0.75 + 0.25 * relief) * light * 0.25 * exp(-d * 4.0) * (1.0 - d);
	if (lp.y < -depth + 0.02) {
		c = vec3(0.0);
	}
	ALBEDO = c;
	ALPHA = 1.0;
}
