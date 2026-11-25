// The well's stone above the ground (outside, rim, the inside of the ring), lit.
shader_type spatial;
render_mode cull_back;
#include "well_stone.gdshaderinc"

uniform float radius = 1.0;
uniform float rim = 0.85;          // m: the ring's top
uniform bool inside = false;       // the inner wall: shadowed, darker toward the ground
uniform bool cap = false;          // the rim's capstones: darker, worn

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float relief;
	vec3 c = stone_color(lp, radius, relief);
	if (inside) {
		c *= mix(0.25, 0.7, clamp(lp.y / rim, 0.0, 1.0));
	}
	if (cap) {
		c *= 0.72;
	}
	NORMAL = ws_bump(NORMAL, VERTEX, relief, 0.045);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
