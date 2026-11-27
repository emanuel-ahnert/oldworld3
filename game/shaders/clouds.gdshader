// Clouds (day_night.gd): drawn on a dome around the camera, inside the far plane (behind the
// world, in front of the moon). Each view ray is followed up to a flat cloud layer; there a
// drifting, layered noise is the cloud cover (`coverage` per zone type). Sunlit tops (`light`),
// grey undersides (`shade`), soft edges, faded into the horizon (`horizon`) near it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.5;         // 0 none .. 1 overcast
uniform vec3 light : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 shade : source_color = vec3(0.62, 0.66, 0.74);
uniform vec3 horizon : source_color = vec3(0.7, 0.78, 0.86);
uniform vec2 wind = vec2(0.006, 0.0025);
uniform float scale = 0.55;           // the layer's noise scale (bigger: smaller clouds)
uniform float opacity = 0.92;

varying vec3 dir;

void vertex() {
	dir = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < 0.01 || coverage <= 0.001) {
		discard;
	}
	// Where the ray meets the layer (height 1, so distances grow toward the horizon).
	vec2 p = d.xz / max(d.y, 0.06) * scale + CAMERA_POSITION_WORLD.xz * 0.0004;
	vec2 t = TIME * wind;
	float n = texture(noise_tex, p * 0.35 + t).r * 0.62
		+ texture(noise_tex, p * 1.1 - t * 1.6 + vec2(0.37, 0.71)).r * 0.28
		+ texture(noise_tex, p * 3.3 + t * 2.4 + vec2(0.13, 0.29)).r * 0.1;
	float edge = 1.0 - coverage;
	float a = smoothstep(edge * 0.82 + 0.1, edge * 0.82 + 0.34, n);
	// Lit from above: denser parts darker below.
	float thick = smoothstep(edge * 0.82 + 0.2, edge * 0.82 + 0.6, n);
	vec3 c = mix(light, shade, thick * 0.8);
	// Into the horizon: thinner and in its color.
	float h = smoothstep(0.02, 0.28, d.y);
	c = mix(horizon, c, h * 0.85 + 0.15);
	ALBEDO = c;
	ALPHA = a * opacity * h;
}
