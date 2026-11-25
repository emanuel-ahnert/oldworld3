class_name Well
extends Node3D
## The village well, built here (the generated model's ring had no inside that met a shaft): a
## round stone wall with a capstone rim, its inner wall going on down SHAFT m into the ground to a
## black bottom, two weathered posts with a beam, a small plank roof, a crank, a rope and a bucket.
## The terrain can't have a hole: below the ground the shaft is a portal (an invisible disc at the
## opening marks it in the stencil buffer, shaders/well_shaft draws it there through the ground).
## The stone is shaders/well_stone (gritty masonry, moss and grime low down), the wood
## shaders/wood_weathered. The origin is on the ground in the middle of the well.

const R_OUT := 1.0         ## m, the wall's outside
const R_IN := 0.72         ## m, its inside (the shaft's)
const RIM := 0.85          ## m above the ground
const SINK := 0.35         ## m the outer wall goes on below the ground (slopes)
const SHAFT := 3.5         ## m deep
const SEG := 40


static func build(parent: Node3D, terrain: Terrain, pos: Vector3, yaw: float) -> Well:
	var w := Well.new()
	w.name = "Well"
	parent.add_child(w)
	# On the lowest ground under it, so it never stands on air on a slope.
	var g := terrain.height_at(pos.x, pos.z)
	for k in 8:
		var a := TAU * k / 8
		g = minf(g, terrain.height_at(pos.x + cos(a) * R_OUT, pos.z + sin(a) * R_OUT))
	w.position = Vector3(pos.x, g, pos.z)
	w.rotation.y = yaw
	w._make(terrain.height_at(pos.x, pos.z) - g + 0.03)
	return w


## open: the ground's height in the middle (above the well's origin, the lowest point under it):
## where the opening and the shaft begin, so the terrain never covers the opening.
func _make(open: float) -> void:
	var stone := ShaderMaterial.new()
	stone.shader = load("res://shaders/well_stone.gdshader")
	stone.set_shader_parameter("radius", R_OUT)
	stone.set_shader_parameter("rim", RIM)
	var inner := ShaderMaterial.new()
	inner.shader = stone.shader
	inner.set_shader_parameter("radius", R_IN)
	inner.set_shader_parameter("rim", RIM)
	inner.set_shader_parameter("inside", true)
	var capm := ShaderMaterial.new()
	capm.shader = stone.shader
	capm.set_shader_parameter("radius", R_OUT)
	capm.set_shader_parameter("cap", true)
	# The wall: outside (down below the ground), the inside down to the ground, the rim's top.
	_mesh(_tube(R_OUT, -SINK, RIM, false), stone)
	_mesh(_tube(R_IN, open, RIM, true), inner)
	_mesh(_ring_top(R_IN - 0.02, R_OUT + 0.04, RIM), capm)
	# The opening (stencil) and the shaft below the ground.
	var mouth_mat := ShaderMaterial.new()
	mouth_mat.shader = load("res://shaders/well_mouth.gdshader")
	mouth_mat.render_priority = -1
	var mouth := _mesh(_disc(R_IN, open), mouth_mat)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shaft_mat := ShaderMaterial.new()
	shaft_mat.shader = load("res://shaders/well_shaft.gdshader")
	shaft_mat.set_shader_parameter("depth", SHAFT)
	shaft_mat.set_shader_parameter("radius", R_IN)
	shaft_mat.render_priority = 1
	var shaft := _mesh(_shaft(R_IN, SHAFT), shaft_mat)
	shaft.position.y = open
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.extra_cull_margin = SHAFT
	# The frame: two posts on the wall, a beam over the opening, a gabled plank roof.
	var wood := ShaderMaterial.new()
	wood.shader = load("res://shaders/wood_weathered.gdshader")
	var wood_x := ShaderMaterial.new()
	wood_x.shader = wood.shader
	wood_x.set_shader_parameter("along_x", true)
	var px := (R_IN + R_OUT) / 2.0
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * px, (RIM + 2.25) / 2.0, 0), Vector3(0.13, 2.25 - RIM, 0.13), wood)
	_box(Vector3(0, 1.95, 0), Vector3(2 * px + 0.3, 0.12, 0.12), wood_x)          # the beam (the winch)
	# The crank on the right post: an arm and a handle.
	_box(Vector3(px + 0.12, 1.95, 0), Vector3(0.1, 0.05, 0.05), wood_x)
	_box(Vector3(px + 0.18, 1.86, 0), Vector3(0.04, 0.2, 0.04), wood)
	for sz in [-1.0, 1.0]:
		var plank := _box(Vector3(0, 2.38, sz * 0.36), Vector3(2 * px + 0.55, 0.05, 0.85), wood_x)
		plank.rotation.x = sz * deg_to_rad(32)
	_box(Vector3(0, 2.62, 0), Vector3(2 * px + 0.6, 0.08, 0.08), wood_x)           # the ridge
	# The rope from the beam and the bucket hanging in the opening.
	var rope := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.012
	rc.bottom_radius = 0.012
	rc.height = 0.8
	rope.mesh = rc
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.45, 0.38, 0.26)
	rope_mat.roughness = 1.0
	rope.material_override = rope_mat
	add_child(rope)
	rope.position = Vector3(0.1, 1.95 - 0.4, 0)
	var bucket := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.16
	bc.bottom_radius = 0.13
	bc.height = 0.24
	bucket.mesh = bc
	bucket.material_override = wood
	add_child(bucket)
	bucket.position = Vector3(0.1, 1.95 - 0.8 - 0.1, 0)
	# Collision: the wall (a cylinder) and the posts.
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R_OUT
	cyl.height = RIM + SINK
	cs.shape = cyl
	cs.position = Vector3(0, (RIM - SINK) / 2.0, 0)
	body.add_child(cs)


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _mesh(b, mat)
	mi.position = pos
	return mi


## A wall round the y axis from y0 to y1; inward: its faces toward the axis.
static func _tube(r: float, y0: float, y1: float, inward: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEG:
		var a0 := TAU * i / SEG
		var a1 := TAU * (i + 1) / SEG
		var p00 := Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p10 := Vector3(cos(a1) * r, y0, sin(a1) * r)
		var p01 := Vector3(cos(a0) * r, y1, sin(a0) * r)
		var p11 := Vector3(cos(a1) * r, y1, sin(a1) * r)
		var n0 := Vector3(cos(a0), 0, sin(a0)) * (-1.0 if inward else 1.0)
		var n1 := Vector3(cos(a1), 0, sin(a1)) * (-1.0 if inward else 1.0)
		# Godot's front faces wind clockwise as seen from their side.
		var tri := [[p00, n0], [p11, n1], [p01, n0], [p00, n0], [p10, n1], [p11, n1]]
		if inward:
			tri = [[p00, n0], [p01, n0], [p11, n1], [p00, n0], [p11, n1], [p10, n1]]
		for v in tri:
			st.set_normal(v[1])
			st.add_vertex(v[0])
	return st.commit()


## The rim's top: a flat ring at height y, a little rounded at its edges (two bevels).
static func _ring_top(r0: float, r1: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := [[r0, y - 0.04], [r0 + 0.04, y], [r1 - 0.04, y], [r1, y - 0.04]]
	for i in SEG:
		var a0 := TAU * i / SEG
		var a1 := TAU * (i + 1) / SEG
		for k in 3:
			var q := [Vector3(cos(a0) * prof[k][0], prof[k][1], sin(a0) * prof[k][0]), Vector3(cos(a1) * prof[k][0], prof[k][1], sin(a1) * prof[k][0]),
				Vector3(cos(a1) * prof[k + 1][0], prof[k + 1][1], sin(a1) * prof[k + 1][0]), Vector3(cos(a0) * prof[k + 1][0], prof[k + 1][1], sin(a0) * prof[k + 1][0])]
			for v in [q[0], q[2], q[1], q[0], q[3], q[2]]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _disc(r: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEG:
		var a0 := TAU * i / SEG
		var a1 := TAU * (i + 1) / SEG
		for v in [Vector3(0, y, 0), Vector3(cos(a1) * r, y, sin(a1) * r), Vector3(cos(a0) * r, y, sin(a0) * r)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


## The shaft below the ground: the inner wall from 0 down to -depth (faces inward) and the bottom.
static func _shaft(r: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEG:
		var a0 := TAU * i / SEG
		var a1 := TAU * (i + 1) / SEG
		var p00 := Vector3(cos(a0) * r, -depth, sin(a0) * r)
		var p10 := Vector3(cos(a1) * r, -depth, sin(a1) * r)
		var p01 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p11 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		# Outward winding: the shader draws the back faces (cull_front), the inside seen from above.
		for v in [p00, p11, p01, p00, p10, p11]:
			st.add_vertex(v)
		for v in [Vector3(0, -depth, 0), p10, p00]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
