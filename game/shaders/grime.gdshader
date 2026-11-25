// Weathering over a building (Placement.weather): multiplies the lit surface with dirt splashed
// up from the ground (the first metre), vertical rain streaks and a mottled, uneven plaster
// tone. World-space noise, so every house looks different; fades out with distance.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform float strength = 1.0;

varying vec3 wpos;
varying float ground;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground = NODE_POSITION_WORLD.y;
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

float fbm(vec3 p) {
	return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2;
}

void fragment() {
	float h = wpos.y - ground;
	// Splashed dirt along the bottom, its upper edge ragged.
	float edge = 0.7 + 0.5 * fbm(wpos * vec3(1.6, 0.0, 1.6) + vec3(0.0, 0.0, 3.1));
	float splash = (1.0 - smoothstep(0.0, edge, h)) * (0.6 + 0.4 * fbm(wpos * 3.0));
	// Rain streaks: noise stretched vertically, stronger under the roof line (higher up).
	vec3 sp = vec3(wpos.x * 2.2 + wpos.z * 2.2, wpos.y * 0.18, wpos.z * 2.2 - wpos.x * 2.2);
	float streak = smoothstep(0.55, 0.85, fbm(sp)) * smoothstep(0.5, 3.0, h);
	// Mottled plaster: large soft blotches, fine grit.
	float mottle = fbm(wpos * 0.6);
	float grit = noise(wpos * 23.0);
	float dark = 0.55 * splash + 0.32 * streak + 0.3 * mottle + 0.1 * grit;
	float fade = 1.0 - smoothstep(90.0, 180.0, length(wpos - CAMERA_POSITION_WORLD));
	float k = clamp(1.0 - strength * dark * fade, 0.0, 1.0);
	// Aged lime and sun-bleached paint: a warm cast over everything, the dirt warmer still.
	vec3 aged = mix(vec3(1.0), vec3(0.9, 0.85, 0.76), strength);
	ALBEDO = aged * vec3(k, k * 0.95, k * 0.86);
}
