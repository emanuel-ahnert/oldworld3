// Weathered wood (well.gd): brown, grain along the plank's length (local y or x by `along_x`),
// a little greyed, cracks and grit.
shader_type spatial;
render_mode cull_back;

uniform bool along_x = false;
uniform vec3 tint : source_color = vec3(0.30, 0.19, 0.10);

varying vec3 lp;

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 g = along_x ? vec2(lp.z * 60.0 + lp.y * 40.0, lp.x * 3.0) : vec2(lp.x * 60.0 + lp.z * 40.0, lp.y * 3.0);
	float grain = n2(g) * 0.6 + n2(g * vec2(3.0, 2.0)) * 0.4;
	float crack = smoothstep(0.82, 0.9, n2(g * vec2(0.7, 0.4)));
	vec3 c = mix(tint, vec3(0.3, 0.26, 0.22), 0.12) * (0.7 + 0.45 * grain);
	c *= 1.0 - 0.5 * crack;
	c *= 0.85 + 0.25 * n2(lp.xz * 40.0 + lp.y * 17.0);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
