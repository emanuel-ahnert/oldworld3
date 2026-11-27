// A ripple on the water (Wake): a ring that grows from the legs and fades, a fainter one
// behind it. age 0..1 over the ripple's life (per instance).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

instance uniform float age = 0.0;
instance uniform float strength = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = clamp(age, 0.0, 1.0);
	float R = mix(0.12, 0.96, sqrt(a));
	float w = mix(0.016, 0.042, a);               // thin lines (they read as bands thicker)
	float ring = 1.0 - smoothstep(0.0, w, abs(r - R));
	float ring2 = 1.0 - smoothstep(0.0, w * 1.3, abs(r - R * 0.62));
	float fade = pow(1.0 - a, 1.6);
	ALBEDO = vec3(0.82, 0.9, 0.94);
	ALPHA = clamp((ring * 0.45 + ring2 * 0.2) * fade * strength, 0.0, 1.0) * step(r, 1.0);
}
