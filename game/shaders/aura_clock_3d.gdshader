// A debuff icon over an enemy's nameplate (enemy.gd) with its timer: like aura_clock.gdshader,
// the time passed a darkened pie sweeping clockwise, with a thin red frame. The row of icons is
// turned to the camera by the script; drawn over everything like the nameplate.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, blend_mix;

uniform sampler2D icon : source_color, filter_linear_mipmap;
instance uniform float elapsed = -1.0;

void fragment() {
	vec4 c = texture(icon, UV);
	vec2 d = UV - vec2(0.5);
	if (elapsed >= 0.0) {
		float a = fract(atan(d.x, -d.y) / TAU + 1.0);
		c.rgb *= mix(1.0, 0.32, step(a, elapsed));
		float edge = abs(fract(a - elapsed + 0.5) - 0.5) * length(d) * TAU;
		c.rgb += vec3(1.0, 0.9, 0.6) * smoothstep(0.03, 0.0, edge) * step(0.06, length(d)) * 0.6;
	}
	float frame = step(0.455, max(abs(d.x), abs(d.y)));
	c.rgb = mix(c.rgb, vec3(0.85, 0.25, 0.2), frame);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
