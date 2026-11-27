// A buff/debuff icon with its timer (hud.gd's aura chips): the part of the duration that has
// passed is a darkened pie, sweeping clockwise from 12 o'clock, with a bright edge where it is.
// elapsed: 0..1 (below 0: no timer, the plain icon).
shader_type canvas_item;

uniform float elapsed = -1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (elapsed >= 0.0) {
		vec2 d = UV - vec2(0.5);
		float a = fract(atan(d.x, -d.y) / TAU + 1.0);       // 0 at the top, clockwise
		float past = step(a, elapsed);
		c.rgb *= mix(1.0, 0.32, past);
		// The sweep's edge: a thin light line from the center out.
		float edge = abs(fract(a - elapsed + 0.5) - 0.5) * length(d) * TAU;
		c.rgb += vec3(1.0, 0.9, 0.6) * smoothstep(0.02, 0.0, edge) * step(0.06, length(d)) * 0.6;
	}
	COLOR = c;
}
