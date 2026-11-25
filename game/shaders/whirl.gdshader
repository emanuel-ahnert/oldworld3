// Whirlwind (warrior): streaks of wind on an open cylinder around the hero, spiralling up
// around it and turning with its spin (whirl_fx.gd), fading toward the cylinder's rims.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform float strength = 0.0;        // 0..1, faded in and out
uniform float turn = 0.0;            // this band's turn so far (whirl_fx.gd: a share of the hero's spin)
uniform float seed = 0.0;            // per band: its own wobble
uniform float wobble = 0.14;         // radius wobble (fraction)
uniform float bands = 3.0;           // streaks around
uniform float tilt = 0.8;            // turns each streak winds over the cylinder's height

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// The radius breathes in and out unevenly around the circle and over time, so the bands don't
// look like perfect cylinders.
void vertex() {
	float ang = UV.x * 6.2832;
	float w = sin(ang * 2.0 + TIME * 1.7 + seed) * 0.5
		+ sin(ang * 3.0 - TIME * 2.6 + seed * 1.7) * 0.3
		+ sin(TIME * 1.1 + seed * 2.3 + UV.y * 2.0) * 0.4;
	VERTEX.xz *= 1.0 + wobble * w;
	VERTEX.y += sin(ang * 2.0 + TIME * 2.1 + seed * 0.7) * 0.06;
}

void fragment() {
	// The mesh's UV.x runs around with the angle the spin turns (cylinder: x = sin, z = cos).
	float a = (UV.x - turn + UV.y * tilt) * bands;
	float f = fract(a);
	// A thin bright front edge and a short fading tail.
	float streak = smoothstep(0.0, 0.025, f) * pow(1.0 - f, 7.0);
	// Wind lines: thin horizontal threads, shifting along each streak, broken up.
	float lines = 0.35 + 0.65 * smoothstep(0.3, 1.0, sin(UV.y * 46.0 + floor(a) * 2.3 + f * 9.0));
	float breakup = 0.5 + 0.5 * hash(vec2(floor(a), floor(UV.y * 9.0 + a * 3.0)));
	float rim = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.65, UV.y);
	ALBEDO = tint.rgb;
	ALPHA = clamp(streak * lines * breakup * rim * strength * tint.a, 0.0, 1.0);
}
