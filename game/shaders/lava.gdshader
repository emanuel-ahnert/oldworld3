// The volcano's lava pool (Terrain._build_volcano): glowing orange cells with dark crust drifting
// between them, slowly churning.
shader_type spatial;
render_mode unshaded, cull_disabled;

float l_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float l_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(l_hash(i), l_hash(i + vec2(1, 0)), f.x), mix(l_hash(i + vec2(0, 1)), l_hash(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * 0.18;
	float n = l_noise(p + TIME * 0.05) * 0.55 + l_noise(p * 2.3 - TIME * 0.08) * 0.3 + l_noise(p * 6.0 + TIME * 0.12) * 0.15;
	float crust = smoothstep(0.45, 0.62, n);
	vec3 hot = mix(vec3(1.0, 0.85, 0.3), vec3(1.0, 0.35, 0.05), smoothstep(0.2, 0.5, n));
	ALBEDO = mix(hot * 1.5, vec3(0.12, 0.05, 0.03), crust);
}
