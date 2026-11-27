// A volcano's smoke plume (Terrain._build_volcano): a tall quad turned to the camera about the
// up axis; soft billowing smoke drifting up through it, narrow at the crater and spreading
// higher up, warm where the lava lights it from below, fading out at the top.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

float p_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float p_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(i), p_hash(i + vec2(1, 0)), f.x), mix(p_hash(i + vec2(0, 1)), p_hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return p_noise(p) * 0.55 + p_noise(p * 2.1 + 3.7) * 0.28 + p_noise(p * 4.3 + 7.1) * 0.17;
}

void vertex() {
	// Turned to the camera about the world's up axis (the plume stays upright).
	vec3 to_cam = CAMERA_POSITION_WORLD - NODE_POSITION_WORLD;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 world = NODE_POSITION_WORLD + right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float up = 1.0 - UV.y;                                  // 0 at the crater .. 1 at the top
	float half_w = mix(0.12, 0.48, pow(up, 0.7));
	vec2 q = vec2((UV.x - 0.5) * 3.0, up * 4.0 - TIME * 0.06);
	float wob = (fbm(vec2(up * 3.0 - TIME * 0.05, 1.3)) - 0.5) * 0.25 * up;   // the column sways
	float x = abs(UV.x - 0.5 - wob) / half_w;
	float body = 1.0 - smoothstep(0.35, 1.0, x + (fbm(q * 1.4) - 0.5) * 0.6);
	float puffs = smoothstep(0.3, 0.75, fbm(q * 2.0 + vec2(0.0, -TIME * 0.04)));
	float a = body * mix(0.55, 1.0, puffs);
	a *= smoothstep(0.0, 0.06, up) * (1.0 - smoothstep(0.65, 1.0, up));
	vec3 c = mix(vec3(0.24, 0.22, 0.21), vec3(0.5, 0.5, 0.52), smoothstep(0.1, 0.8, up) * puffs);
	c = mix(c, vec3(0.75, 0.35, 0.12), (1.0 - smoothstep(0.0, 0.15, up)) * 0.6);   // lava glow at the bottom
	ALBEDO = c;
	ALPHA = a * 0.8;
}
