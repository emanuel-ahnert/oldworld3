// Ground clutter (world/clutter.gd): grass tufts, flowers, pebbles as MultiMesh instances.
// Color per instance in INSTANCE_CUSTOM.rgb; the vertex color's red channel shades the blades
// from the base (dark) to the tip (light); flowers: alpha 1 marks the blossom (instance color),
// alpha 0 the stem (stem_color). Instances shrink away toward the edge of the clutter range so
// they don't pop, and grass sways in the wind.
shader_type spatial;
render_mode cull_disabled;

uniform float wind = 1.0;
uniform float fade_start = 18.0;
uniform float fade_end = 22.0;
uniform bool up_normal = true;      // blades lit like the ground they stand on
uniform bool flower = false;
uniform vec3 stem_color : source_color = vec3(0.25, 0.38, 0.12);

varying vec3 col;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = length(origin.xz - CAMERA_POSITION_WORLD.xz);
	VERTEX *= 1.0 - smoothstep(fade_start, fade_end, d);
	float h = max(VERTEX.y, 0.0);
	float t = TIME * 1.6 + origin.x * 0.37 + origin.z * 0.23;
	VERTEX.xz += vec2(sin(t), cos(t * 0.83)) * h * h * 0.35 * wind;
	if (up_normal) {
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
	vec3 c = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));     // instance colors are sRGB
	if (flower) {
		col = mix(stem_color * COLOR.r, c, COLOR.a);
	} else {
		col = c * COLOR.r;
	}
}

void fragment() {
	if (up_normal) {
		// World up in view space, also on back faces (Godot flips their normal: dark blades).
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
