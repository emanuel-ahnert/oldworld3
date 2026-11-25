// Smoke cloud (World.add_smoke): soft toward its outline, slowly swirling, and fading where it
// meets the ground or a body instead of cutting a hard line (soft particles via the depth buffer).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float alpha = 0.5;
uniform vec3 tint : source_color = vec3(0.62, 0.63, 0.66);
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec3 p = wpos * 0.45 + vec3(0.0, TIME * 0.25, TIME * 0.1);
	float n = noise(p) * 0.6 + noise(p * 2.3) * 0.4;
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float soft = clamp((VERTEX.z - view.z) / 1.2, 0.0, 1.0);
	ALBEDO = tint * (0.85 + 0.3 * n);
	ALPHA = alpha * smoothstep(0.0, 0.8, facing) * smoothstep(0.25, 0.75, n + facing * 0.3) * soft;
}
