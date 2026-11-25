// A magic circle on the ground (casting, Hellfire Rain's area): rings, a turning band of rune
// ticks and a five-pointed star, glowing in `tint`. Drawn on a flat quad (spell_fx.gd).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float strength = 1.0;        // 0..1 fade
uniform float spin = 0.3;            // turns of the rune band per second
uniform float fill = 0.12;           // the glow filling the circle (an area marker)

float ring(float r, float at, float w) {
	return smoothstep(w, 0.0, abs(r - at));
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float ang = atan(p.y, p.x);
	float t = TIME * spin * 6.2832;
	float v = ring(r, 0.96, 0.035) * 1.2 + ring(r, 0.84, 0.012) + ring(r, 0.58, 0.012) * 0.8;
	// Rune ticks between the outer rings, turning.
	float band = step(0.86, r) * step(r, 0.94);
	float tick = step(0.55, fract((ang + t) * 36.0 / 6.2832)) * step(0.3, fract((ang + t) * 7.0 / 6.2832 + 0.13));
	v += band * tick * 0.7;
	// A star turning the other way.
	float st = 1e3;
	for (int i = 0; i < 5; i++) {
		float a0 = -t * 0.5 + float(i) * 2.5133;
		float a1 = a0 + 2.5133;
		st = min(st, seg(p, vec2(cos(a0), sin(a0)) * 0.84, vec2(cos(a1), sin(a1)) * 0.84));
	}
	v += smoothstep(0.018, 0.0, st) * 0.8;
	v += fill * smoothstep(1.0, 0.2, r) * (0.75 + 0.25 * sin(TIME * 4.0));
	ALBEDO = tint.rgb * v * 2.0;
	ALPHA = clamp(v, 0.0, 1.0) * strength;
}
