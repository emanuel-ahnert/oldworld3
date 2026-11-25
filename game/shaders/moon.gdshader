// The moon (day_night.gd): the generated disc (assets/sky/moon.png) in the middle of a quad
// facing the camera, a soft halo around it; not fogged, faded in at night with `strength`.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D disc : source_color, filter_linear_mipmap;
uniform float halo_size = 2.6;            // the quad's size in moon diameters
uniform float strength = 1.0;
uniform vec3 tint : source_color = vec3(0.93, 0.96, 1.0);
uniform float brightness = 1.08;
uniform vec3 halo_color : source_color = vec3(0.55, 0.65, 0.9);
uniform float halo = 0.28;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec2 p = (UV - 0.5) * halo_size;             // moon radius = 0.5
	vec2 duv = p + 0.5;
	vec4 m = vec4(0.0);
	if (duv.x >= 0.0 && duv.x <= 1.0 && duv.y >= 0.0 && duv.y <= 1.0)
		m = texture(disc, duv);
	float r = length(p) * 2.0;                   // 1 at the moon's edge
	float h = halo * exp(-max(r - 1.0, 0.0) * 3.2) * smoothstep(halo_size, halo_size * 0.6, r);
	vec3 col = mix(halo_color, m.rgb * tint * brightness, m.a);
	ALBEDO = col;
	ALPHA = clamp(max(m.a, h), 0.0, 1.0) * strength;
}
