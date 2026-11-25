// Lake water: transparent, glossy, slow waves from a scrolling noise normal map.
shader_type spatial;
render_mode cull_disabled, depth_draw_always;

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 shallow : source_color = vec4(0.25, 0.45, 0.42, 1.0);
uniform vec4 deep : source_color = vec4(0.08, 0.2, 0.28, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / 9.0;
	vec3 n1 = texture(wave_normal, uv + TIME * vec2(0.012, 0.007)).rgb;
	vec3 n2 = texture(wave_normal, uv * 1.7 - TIME * vec2(0.009, 0.013)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.5 + 0.3 * fres);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = mix(0.72, 0.92, fres);
}
