// The well's masonry (well.gd): courses of rough stones round the ring, mortar joints, each stone
// its own shade and grit, grime and moss toward the ground. stone_color(p) takes the point in
// the well's space (y up from the ground, the ring round the y axis).

float ws_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ws_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ws_hash(i), ws_hash(i + vec2(1, 0)), f.x), mix(ws_hash(i + vec2(0, 1)), ws_hash(i + vec2(1, 1)), f.x), f.y);
}

// relief: the masonry's height at p (0 in the mortar, up to 1 on a stone's face), for bumps.
vec3 stone_color(vec3 p, float radius, out float relief) {
	float ang = atan(p.z, p.x);
	float around = ang * radius;                     // m along the ring
	// Rough fieldstone: courses of uneven height, stones of uneven length, wobbly joints.
	float wob = 0.03 * (ws_noise(vec2(around * 6.0, p.y * 2.0)) - 0.5);
	float course = (p.y + wob) / 0.16;
	float row = floor(course);
	float len = mix(0.22, 0.42, ws_hash(vec2(row, 7.7)));
	float u = (around + 0.04 * (ws_noise(vec2(p.y * 9.0, around)) - 0.5)) / len + ws_hash(vec2(row, 3.1));
	float fu = fract(u);
	float fv = fract(course);
	float edge = min(min(fu, 1.0 - fu) * len / 0.16, min(fv, 1.0 - fv));
	float jitter = 0.04 * ws_noise(vec2(around, p.y) * 30.0);
	float mortar = 1.0 - smoothstep(0.04, 0.1 + jitter, edge);
	float id = ws_hash(vec2(floor(u), row));
	vec3 c = mix(vec3(0.22, 0.19, 0.155), vec3(0.32, 0.27, 0.21), id) * (0.78 + 0.32 * ws_hash(vec2(floor(u) * 1.7, row + 0.3)));
	// Grit: speckles and pits in the stone.
	float grit = ws_noise(vec2(around, p.y) * 90.0) * 0.6 + ws_noise(vec2(around, p.y) * 240.0) * 0.4;
	relief = smoothstep(0.02, 0.14, edge) * (0.75 + 0.25 * grit) + 0.15 * ws_noise(vec2(around, p.y) * 18.0);
	c *= 0.78 + 0.32 * grit;
	c *= 1.0 - 0.25 * smoothstep(0.6, 0.85, ws_noise(vec2(around, p.y) * 7.0));    // stains
	c = mix(c, vec3(0.1, 0.085, 0.07) * (0.8 + 0.4 * grit), mortar);
	// Moss and grime toward the ground.
	float low = 1.0 - smoothstep(0.0, 0.45, p.y);
	float moss = smoothstep(0.5, 0.75, ws_noise(vec2(around, p.y) * 3.5)) * low;
	c = mix(c, vec3(0.2, 0.26, 0.12) * (0.8 + 0.4 * grit), moss * 0.7);
	c *= 1.0 - 0.25 * low;
	return c;
}


// Bump lighting from the relief (surface gradient through screen derivatives: no tangents).
vec3 ws_bump(vec3 n, vec3 pos, float h, float strength) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - grad * strength);
}
