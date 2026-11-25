// Armor layers (tools/pipeline/armor.py): polished steel shells with brass trim along their
// top and bottom edges and lames (overlapping plate bands) on the skirt, drawn crisply from
// per-vertex data: UV.x = height above the piece's bottom edge (m); COLOR = (inside of the
// shell, lame spacing / 0.1 m, trim width / 0.05 m, piece height in m).
shader_type spatial;

uniform vec3 steel : source_color = vec3(0.56, 0.58, 0.62);
uniform vec3 brass : source_color = vec3(0.72, 0.55, 0.28);
uniform vec3 inside : source_color = vec3(0.16, 0.16, 0.18);
uniform float stealth = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float u = UV.x;
	float h = COLOR.a;
	float edge = min(u, h - u);
	float tw = COLOR.b * 0.05;
	float aa = fwidth(edge) + 0.0005;
	float trim = 1.0 - smoothstep(tw - aa, tw + aa, edge);
	// A thin dark groove just inside the trim.
	float groove = (1.0 - smoothstep(0.0, aa * 1.5, abs(edge - tw - 0.003))) * (1.0 - trim);
	vec3 c = steel;
	float lames = COLOR.g * 0.1;
	if (lames > 0.001) {
		float f = fract(u / lames);
		c *= 0.78 + 0.22 * f;                                     // each lame darker at its lower edge
		c *= mix(0.45, 1.0, smoothstep(0.0, 0.06, f));            // the overlap line
	}
	// Uneven polish and faint scratches.
	float n = noise(local_pos * 18.0) * 0.6 + noise(local_pos * 70.0) * 0.4;
	c *= 0.9 + 0.2 * n;
	c = mix(c, brass, trim);
	c *= 1.0 - 0.6 * groove;
	c = mix(c, inside, step(0.5, COLOR.r));
	ALBEDO = mix(c, c * vec3(0.18, 0.2, 0.3), stealth);
	METALLIC = mix(0.75, 0.85, trim) * (1.0 - step(0.5, COLOR.r));
	ROUGHNESS = mix(0.3, 0.45, n) + trim * 0.05;
}
