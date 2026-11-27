// Headgear layers (tools/pipeline/headgear.py): a shell around the head, drawn per kind from
// per-vertex data. UV = (azimuth 0..1 from behind, elevation 0..1 bottom to top); COLOR.r = the
// inside (and the rim); COLOR.g = distance to the nearest edge (face opening, bottom) / 0.1 m.
// kind: 0 cloth hood, 1 mail coif, 2 leather cap, 3 plate helm. The hood takes the robe's
// colors when one is worn (Humanoid.set_robe).
shader_type spatial;

uniform int kind = 0;
uniform vec3 tint : source_color = vec3(0.42, 0.36, 0.29);
uniform vec3 trim : source_color = vec3(0.30, 0.25, 0.19);
uniform float stealth = 0.0;

const float E0 = -85.0;
const float E1 = 90.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float lat = radians(mix(E0, E1, UV.y));
	// Surface coordinates in meters (about: the head's radius ~0.13 m), squeezed toward the top.
	vec2 m = vec2((UV.x - 0.5) * 6.2832 * 0.13 * cos(lat), lat * 0.13);
	float edge = COLOR.g * 0.1;                    // m to the nearest edge
	float aa = fwidth(edge) + 0.0005;
	bool inside = COLOR.r > 0.5;
	vec3 c;
	float metal = 0.0;
	float rough = 0.9;
	if (kind == 0) {
		// Cloth: a fine weave, soft folds, a hem around the edges, a seam over the top.
		float weave = 0.5 + 0.5 * sin(m.x * 2400.0) * sin(m.y * 2400.0);
		float folds = vnoise(m * vec2(30.0, 12.0));
		c = tint * (0.86 + 0.1 * weave + 0.12 * folds);
		float hem = 1.0 - smoothstep(0.016 - aa, 0.016 + aa, edge);
		c = mix(c, trim, hem);
		c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.0025, abs(edge - 0.017)));   // the hem's stitch line
		float seam = 1.0 - smoothstep(0.0, 0.002, abs(m.x));
		c *= 1.0 - 0.25 * seam * step(0.05, m.y);
	} else if (kind == 1) {
		// Mail: rows of rings, every other row shifted half a ring; a leather band at the edges.
		vec2 g = m / vec2(0.0045, 0.0036);
		g.x += 0.5 * mod(floor(g.y), 2.0);
		vec2 f = fract(g) - 0.5;
		float r = length(f * vec2(1.0, 1.25));
		float ring = smoothstep(0.22, 0.3, r) * (1.0 - smoothstep(0.38, 0.48, r));
		c = mix(vec3(0.1, 0.1, 0.11), vec3(0.42, 0.43, 0.45) * (0.85 + 0.3 * f.y), ring * 0.85);
		metal = 0.8 * ring;
		rough = mix(0.8, 0.45, ring);
		float band = 1.0 - smoothstep(0.012 - aa, 0.012 + aa, edge);
		c = mix(c, vec3(0.28, 0.18, 0.1), band);
		metal *= 1.0 - band;
		rough = mix(rough, 0.75, band);
	} else if (kind == 2) {
		// Leather: mottled brown, darker toward the edges, a stitched seam along them and over
		// the top.
		float n = vnoise(m * 90.0) * 0.6 + vnoise(m * 300.0) * 0.4;
		c = tint * (0.8 + 0.35 * n);                    // (dyed: the item's color; plain brown by default)
		c *= mix(0.7, 1.0, smoothstep(0.0, 0.02, edge));
		float stitch_line = 1.0 - smoothstep(0.0, 0.0012, abs(edge - 0.008));
		float dash = step(0.5, fract((m.x + m.y) * 160.0));
		c = mix(c, vec3(0.78, 0.68, 0.5), stitch_line * dash);
		float seam = (1.0 - smoothstep(0.0, 0.0015, abs(m.x))) * step(0.02, m.y);
		c *= 1.0 - 0.4 * seam;
		rough = 0.65;
	} else {
		// Plate: polished steel, a brass rim along the edges and the eye slit, a dark groove inside
		// it.
		float n = vnoise(m * 60.0) * 0.6 + vnoise(m * 220.0) * 0.4;
		c = vec3(0.56, 0.58, 0.62) * (0.9 + 0.2 * n);
		float rim = 1.0 - smoothstep(0.012 - aa, 0.012 + aa, edge);
		float groove = (1.0 - smoothstep(0.0, aa * 1.5, abs(edge - 0.015))) * (1.0 - rim);
		c = mix(c, vec3(0.72, 0.55, 0.28), rim);
		c *= 1.0 - 0.6 * groove;
		metal = mix(0.75, 0.85, rim);
		rough = mix(0.3, 0.45, n);
	}
	if (inside) {
		c *= 0.35;
		metal = 0.0;
		rough = 0.9;
	}
	ALBEDO = mix(c, c * vec3(0.18, 0.2, 0.3), stealth);
	METALLIC = metal;
	ROUGHNESS = rough;
}
