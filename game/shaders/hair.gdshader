// A hairstyle layer (tools/pipeline/hair.py): strands along UV.y (root 0 .. tip 1+), fine and
// clumped across UV.x, in hair_color; darker toward the roots and on the inside (both sides
// drawn: a single shell).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 hair_color : source_color = vec3(0.15, 0.09, 0.05);
uniform float strand_scale = 700.0;   // strands round the head (fewer across a crest)

varying float depth;

float h_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float h_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h_hash(i), h_hash(i + vec2(1, 0)), f.x), mix(h_hash(i + vec2(0, 1)), h_hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	depth = COLOR.r;
}

void fragment() {
	// Strands: thin lines along the hair, wavering a little; clumps of lighter and darker.
	float u = UV.x * strand_scale + h_noise(vec2(UV.x * 40.0, UV.y * 3.0)) * 6.0;
	float fine = h_noise(vec2(u, UV.y * 6.0)) * 0.6 + h_noise(vec2(u * 2.3, UV.y * 11.0)) * 0.4;
	float clump = h_noise(vec2(UV.x * 60.0, UV.y * 1.5));
	vec3 c = hair_color * mix(0.5, 1.35, fine * fine) * mix(0.75, 1.15, clump);
	c *= mix(0.7, 1.0, smoothstep(0.0, 0.4, UV.y));             // the roots in shade
	c *= FRONT_FACING ? 1.0 : 0.5;                               // the inside of the shell
	ALBEDO = c;
	ROUGHNESS = 0.68;
	SPECULAR = 0.35;
}
