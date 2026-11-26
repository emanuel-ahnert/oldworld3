// Terrain: grass, dirt (vertex color R: roads, plaza) and rock on steep slopes.
// Textures tile in world space; grass is sampled at two scales to hide the repetition.
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex_plain : source_color, filter_linear_mipmap, repeat_enable;   // the same texture, cheaper filtering (the second, blended read)
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;      // cliff faces
uniform sampler2D rock_top_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;  // rock seen from above
uniform float grass_tile = 2.2;   // meters per texture repeat (the grass textures hold 2x2 copies: small blades)
uniform float dirt_tile = 1.6;
uniform float rock_tile = 12.0;
uniform vec3 road_tint = vec3(0.66, 0.56, 0.44);           // per zone: roads and plaza (North: grey)
uniform float road_sat = 0.5;                              // how much of the dirt texture's color stays
uniform vec3 rock_tint : source_color = vec3(1.0);        // per zone: warm, cool or purple rock
uniform vec4 rock_moss = vec4(0.33, 0.42, 0.18, 0.0);     // rgb: moss on rock facing up, a: how much
uniform vec4 grass_tint = vec4(1.0, 1.0, 1.0, 0.0);   // rgb: color the grass is pulled toward, a: how far
uniform float snow = 0.0;
// Variety: a tileable noise (terrain.gd) drives drier/darker grass patches, ragged bare-soil
// patches (`bare` = how much; per zone) and fine soil grit between the grass.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float bare = 0.5;
uniform float snow_line = 1000.0;   // snow caps on mountains above this height (per zone)
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;  // plain soil, all zones          // 1 in snow zones: the "grass" texture is snow, keep it bright

varying vec3 wpos;
varying vec3 wnorm;
varying float dirt_w;
varying float shore_w;
// Large-scale variation (tens of meters), read once per vertex (2 m apart) instead of per pixel:
// x: the meadow's brightness (grass texture, 97 m, blurred), y: its warmth (for the roads),
// z: patches (noise, 46 m), w: the rock's tint (noise, 90 m). Texture reads were the main cost.
varying vec4 large;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	dirt_w = COLOR.r;
	shore_w = COLOR.g;
	vec3 big = textureLod(grass_tex_plain, wpos.xz / 97.0, 5.0).rgb;
	large = vec4(big.g, big.r,
		textureLod(noise_tex, wpos.xz / 46.0, 1.0).r,
		textureLod(noise_tex, wpos.xz / 90.0 + vec2(wpos.y / 120.0, 0.0), 1.0).r);
}

// Reads inside branches use explicit derivatives (textureGrad, from dx/dy of the world position
// taken once outside them): a plain texture() needs its neighbors' coordinates, so the GPU
// compiler pulled such reads out of their branches and ran them for every pixel (rock, roads
// and shores everywhere: the terrain was half the frame on an integrated GPU).
vec3 rock_triplanar_t(vec3 p, vec3 n, float tile, vec3 dx, vec3 dy) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 c = vec3(0.0);
	if (w.x > 0.02) {
		c += textureGrad(rock_tex, vec2(p.z, -p.y) / tile, vec2(dx.z, -dx.y) / tile, vec2(dy.z, -dy.y) / tile).rgb * w.x;
	}
	if (w.y > 0.02) {
		c += textureGrad(rock_top_tex, p.xz / tile, dx.xz / tile, dy.xz / tile).rgb * w.y;
	}
	if (w.z > 0.02) {
		c += textureGrad(rock_tex, vec2(p.x, -p.y) / tile, vec2(dx.x, -dx.y) / tile, vec2(dy.x, -dy.y) / tile).rgb * w.z;
	}
	return c / max(w.x * step(0.02, w.x) + w.y * step(0.02, w.y) + w.z * step(0.02, w.z), 0.001);
}

void fragment() {
	// Texture reads are the main cost on integrated graphics (the terrain was half of the frame):
	// rock and dirt are only sampled where they show (branches are coherent: whole screen areas
	// are meadow), the slow variation comes from the vertices (`large`).
	vec2 uv = wpos.xz;
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	vec3 g = texture(grass_tex, uv / grass_tile).rgb;
	// Second read, rotated and a little larger, hides the repetition (a much larger scale
	// showed giant blades).
	vec2 ruv = vec2(uv.x * 0.8 - uv.y * 0.6, uv.x * 0.6 + uv.y * 0.8);
	vec3 g2 = texture(grass_tex_plain, ruv / (grass_tile * 2.9) + vec2(0.37, 0.71)).rgb;
	g = mix(g, g2, 0.45);
	// Large-scale tint variation so meadows are not one flat green.
	g *= mix(0.82, 1.08, large.x);
	g = mix(mix(vec3(dot(g, vec3(0.3, 0.59, 0.11))), g, 0.82) * 0.88, g * 1.02, snow);   // grass: a bit less saturated
	g = mix(g, vec3(dot(g, vec3(0.3, 0.59, 0.11))) * grass_tint.rgb * 2.0, grass_tint.a);
	float n_big = large.z;                                        // patches, tens of meters
	vec2 nm = texture(noise_tex, uv / 5.3 + vec2(0.31, 0.77)).rg;
	float n_mid = nm.r;                                          // their ragged edges
	float n_fine = nm.g;                                         // grit speckles (0.9 m)
	float grassy = snow > 0.99 ? 0.0 : 1.0;      // off on snow and sand
	// Drier, yellowish grass in some places, darker lush grass in others.
	g = mix(g, g * vec3(1.12, 1.02, 0.66), smoothstep(0.58, 0.78, n_big) * 0.55 * grassy);
	g *= mix(1.0, mix(0.8, 1.06, n_mid), grassy);
	// Bare soil: patches with ragged edges, and grit showing between the blades.
	float patch = smoothstep(0.7, 0.82, n_big * 0.75 + n_mid * 0.35) * 0.8 * bare;
	float grit = smoothstep(0.6, 0.85, n_fine) * 0.5 * bare;
	vec3 col = g;
	float soil = max(patch, grit) * grassy;
	if (soil > 0.01) {
		// Soil shaded by the grass texture's light and dark (no read of its own: it showed
		// almost everywhere, the grit is all over the meadows).
		float gl = dot(g, vec3(0.3, 0.59, 0.11));
		vec3 d = vec3(0.36) * (0.55 + 1.3 * gl) * vec3(0.55, 0.47, 0.38) * 1.25 * mix(0.75, 1.05, n_mid);
		d = mix(d, d * grass_tint.rgb * 2.0, grass_tint.a) * (grass_tint.a > 0.0 ? 0.65 : 1.0);   // Unholy: dark olive soil
		col = mix(col, d, soil);
	}
	if (dirt_w > 0.01) {
		// Ragged road edges and grass patches growing into the road: compare the dirt weight
		// with a noise pattern (the grass texture's brightness at a mid scale).
		float n = n_mid * 0.6 + 0.2;
		float dw = smoothstep(0.35, 0.65, dirt_w * 1.15 - (n - 0.45) * 0.9);
		vec3 d = textureGrad(dirt_tex, uv / dirt_tile, dpx.xz / dirt_tile, dpy.xz / dirt_tile).rgb;
		// Pull the generated soil toward a muted earth brown, with large-scale variation.
		d = mix(vec3(dot(d, vec3(0.33))), d, road_sat) * road_tint;
		d *= mix(0.85, 1.1, large.y);
		col = mix(col, d, dw);
	}
	if (shore_w > 0.01) {
		// Lake shores and beds: pale wet sand.
		vec3 sand = textureGrad(dirt_tex, uv / 2.4, dpx.xz / 2.4, dpy.xz / 2.4).rgb;
		sand = mix(vec3(dot(sand, vec3(0.33))), sand, 0.4) * vec3(0.82, 0.76, 0.62);
		col = mix(col, sand, smoothstep(0.1, 0.6, shore_w));
	}
	float slope = 1.0 - wnorm.y;
	float rock_w = smoothstep(0.16, 0.30, slope);
	if (rock_w > 0.001) {
		// Mountains: the rock at two scales (faces don't repeat every few meters), warm and cool
		// tints over the range, darker strata bands.
		vec3 rk = rock_triplanar_t(wpos, wnorm, rock_tile, dpx, dpy);
		vec3 rk_big = rock_triplanar_t(wpos, wnorm, rock_tile * 4.7, dpx, dpy);
		rk = mix(rk, rk * rk_big * 2.0, 0.5);
		float n_rock = large.w;
		rk *= mix(vec3(0.86, 0.9, 1.0), vec3(1.1, 1.0, 0.86), n_rock);
		float band = sin(wpos.y * 0.21 + n_rock * 4.0);                     // broad layers
		rk *= 0.88 + 0.12 * smoothstep(-0.3, 0.5, band);
		rk *= rock_tint;
		// Moss and grass in the ledges (rock facing up), patchy.
		float moss = rock_moss.a * smoothstep(0.5, 0.8, wnorm.y) * smoothstep(0.3, 0.6, n_rock + n_mid * 0.5);
		rk = mix(rk, rock_moss.rgb * (0.7 + 0.6 * dot(rk, vec3(0.333))), moss);
		col = mix(col, rk, rock_w);
	}
	// Snow caps: above the zone's snow line, on the flatter parts.
	if (wpos.y > snow_line - 12.0) {
		float sw = smoothstep(snow_line, snow_line + 10.0, wpos.y + (n_mid - 0.5) * 16.0) * smoothstep(0.45, 0.72, wnorm.y);
		col = mix(col, vec3(0.9, 0.92, 0.96), sw);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
