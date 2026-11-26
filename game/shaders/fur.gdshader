// Fur for the generated creature models (Enemy._matte): their textures come with painted-in
// highlights (a glossy sheen) and smooth skin. Here the painted color is flattened toward its
// blurred average (the highlights go), and fine hair strands are drawn over it: thin dark gaps
// between long strands that flow from the head back to the tail and down the flanks (object
// space: the models face +Z). Fully rough, almost no specular, a soft rim of light on the edges
// (light caught in the fur).
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float flatten = 0.4;            // how far the painted shading goes toward the blur
uniform float strands = 1.0;             // strength of the strand pattern
uniform float scale = 1.0;               // model size (strand size scales with it)
uniform float stealth = 0.0;

varying vec3 opos;
varying vec3 onrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	opos = VERTEX / scale;
	onrm = NORMAL;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 blur = textureLod(albedo_tex, UV, 3.0).rgb;
	// Keep the hue and the darker markings, lose the bright painted sheen.
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	float lb = dot(blur, vec3(0.3, 0.55, 0.15));
	float over = max(l - lb, 0.0);
	c = mix(c, blur, flatten) - (1.0 - flatten) * over * 0.8;
	// The strands: a frame on the surface, u along the hair's flow, v across it.
	vec3 n = normalize(onrm);
	vec3 flow = normalize(vec3(0.0, -0.55, -1.0));
	vec3 u = flow - n * dot(flow, n);
	if (length(u) < 0.05) {
		u = vec3(0.0, -1.0, 0.0) - n * n.y;
	}
	u = normalize(u);
	vec3 v = cross(n, u);
	vec2 q = vec2(dot(opos, v) * 420.0, dot(opos, u) * 26.0);
	q.y += vnoise(q * vec2(0.05, 1.0)) * 2.0;           // the strands waver
	float h = vnoise(q) * 0.6 + vnoise(q * vec2(2.1, 1.7) + 7.3) * 0.4;
	// Fade out where the strands get finer than a pixel (no shimmer at a distance).
	float fine = clamp(1.0 - length(fwidth(q)) * 0.25, 0.0, 1.0);
	float hair = mix(1.0, 0.62 + 0.55 * h, strands * fine);
	// Clumps: larger, softer tufts.
	float clump = vnoise(vec2(dot(opos, v), dot(opos, u)) * vec2(60.0, 9.0));
	hair *= mix(1.0, 0.82 + 0.3 * clump, strands);
	c *= hair;
	ALBEDO = mix(c, c * vec3(0.18, 0.2, 0.3), stealth);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.12;
	AO = mix(1.0, hair, 0.5);
	AO_LIGHT_AFFECT = 0.3;
	RIM = 0.12;
	RIM_TINT = 0.6;
}
