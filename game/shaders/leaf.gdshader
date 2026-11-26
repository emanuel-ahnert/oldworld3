// Tree and bush leaves (tools/pipeline/tree.py cards; scatter.gd puts this on the leaf surface):
// one double-sided card per sprig. Godot turns a card's normal around on its back side, which
// lit the crown dark from behind; the cards' normals are bent out of the crown (it shades like
// one volume), so both sides keep them. Alpha clip, tint, and the near-camera dither (a camera
// pushed into a crown sees through it) as the standard material had them.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.85;
uniform vec2 near_fade = vec2(0.6, 2.4);     // gone within x m, solid from y m

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	float fade = smoothstep(near_fade.x, near_fade.y, -VERTEX.z);
	// Ordered dither (4x4 Bayer) by screen pixel, as the standard material's pixel dither.
	ivec2 q = ivec2(FRAGCOORD.xy) % 4;
	int i = q.x + q.y * 4;
	float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (fade < (bayer[i] + 0.5) / 16.0) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;               // the card's own (bent) normal on its back as well
	}
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}
