class_name BatSwarm
extends Node3D
## The Bat Swarm's body (EnemyData "swarm"): COUNT small bats built here (a furry body with
## head and ears, two leathery wings on pivots) flapping and weaving round the swarm's center
## (this node, which Enemy bobs at the creature's float height). The swarm's health is its bats:
## set_alive(n) keeps the first n flying; the others drop out of the air, tumble down and lie
## on the ground, wings spread (their own spot in the world, not following the swarm). The
## last one falls with the swarm's last hit point.

const COUNT := 6
const FLAP_HZ := 6.5
const GRAVITY := 9.8

static var _body_mesh: Mesh
static var _wing_mesh: Mesh
static var _mat: StandardMaterial3D
static var _wing_mat: StandardMaterial3D

var _bats: Array[Dictionary] = []
var _t := 0.0


func _init() -> void:
	_make_meshes()
	for i in COUNT:
		var b := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = _body_mesh
		body.material_override = _mat
		b.add_child(body)
		var wings: Array[Node3D] = []
		for side in [1.0, -1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.025, 0.012, -0.01)
			pivot.scale.x = side
			var w := MeshInstance3D.new()
			w.mesh = _wing_mesh
			w.material_override = _wing_mat
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			pivot.add_child(w)
			b.add_child(pivot)
			wings.append(pivot)
		var s := randf_range(1.1, 1.45)
		b.scale = Vector3.ONE * s
		add_child(b)
		_bats.append({
			"node": b, "wings": wings, "alive": true, "falling": false, "vel": Vector3.ZERO,
			"spin": Vector3.ZERO, "ground": 0.0,
			# The bat's loop round the center: radius, speed, tilt, phase; its own flap phase.
			"r": randf_range(0.3, 0.85), "w": randf_range(1.6, 2.8) * (1.0 if randf() < 0.6 else -1.0),
			"a0": randf() * TAU, "h": randf_range(0.12, 0.4), "hw": randf_range(1.1, 2.3),
			"flap": randf() * TAU, "base_scale": s,
		})


## How many bats still fly (0..COUNT); the rest drop. More than now: the fallen rise again.
func set_alive(n: int) -> void:
	n = clampi(n, 0, COUNT)
	for i in COUNT:
		var b := _bats[i]
		if i < n and not b.alive:
			_revive(b)
		elif i >= n and b.alive:
			_drop(b)


func alive_count() -> int:
	var n := 0
	for b in _bats:
		n += int(b.alive)
	return n


## All bats back up (the swarm respawns).
func reset() -> void:
	for b in _bats:
		_revive(b)
		(b.node as Node3D).position = Vector3.ZERO


func _drop(b: Dictionary) -> void:
	b.alive = false
	b.falling = true
	var n: Node3D = b.node
	n.top_level = true                       # keeps its place in the world from here on
	b.vel = Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1))
	b.spin = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-8, 8))
	b.ground = World.height_at(n.global_position.x, n.global_position.z) if is_inside_tree() else 0.0


func _revive(b: Dictionary) -> void:
	b.alive = true
	b.falling = false
	(b.node as Node3D).top_level = false     # flies back into the swarm (eased in _process)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	for b in _bats:
		var n: Node3D = b.node
		var wings: Array = b.wings
		if b.alive:
			# Weaving round the center: a tilted loop, up and down, the body along its path.
			var p := _orbit(b, _t)
			var ahead := _orbit(b, _t + 0.06)
			var k := 1.0 - exp(-10.0 * dt)
			n.position = n.position.lerp(p, k)
			var dir := ahead - p
			if dir.length() > 0.001:
				var bank := clampf(float(b.w) * 0.25, -0.6, 0.6)
				n.basis = Basis.looking_at(dir.normalized(), Vector3.UP).rotated(dir.normalized(), bank).scaled(Vector3.ONE * float(b.base_scale))
			var ph := float(b.flap) + _t * TAU * FLAP_HZ
			var flap := sin(ph)
			for w: Node3D in wings:
				w.rotation.z = flap * 0.95 + 0.15
			n.position.y += cos(ph) * 0.02                  # each beat lifts the body
		elif b.falling:
			# Dropping out of the air, tumbling; on the ground: lying flat, wings spread.
			b.vel.y -= GRAVITY * dt
			n.global_position += b.vel * dt
			n.rotation += b.spin * dt
			for w: Node3D in wings:
				w.rotation.z = lerpf(w.rotation.z, 1.2, 1.0 - exp(-6.0 * dt))     # wings fold up
			if n.global_position.y <= b.ground + 0.03:
				b.falling = false
				var yaw := randf() * TAU
				n.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(b.base_scale)), Vector3(n.global_position.x, b.ground + 0.03, n.global_position.z))
				for w: Node3D in wings:
					w.rotation.z = randf_range(-0.15, 0.1)          # spread on the ground


func _orbit(b: Dictionary, t: float) -> Vector3:
	var a := float(b.a0) + t * float(b.w)
	var r := float(b.r) * (1.0 + 0.25 * sin(t * 0.7 + float(b.a0)))
	return Vector3(cos(a) * r, sin(t * float(b.hw) + float(b.a0)) * float(b.h), sin(a) * r)


## One bat's meshes (shared by all bats): the body (a furry egg, the head with a snout, two
## pointed ears) and a wing (a membrane fanned from the shoulder to three finger tips, the edge
## scalloped between them), facing -Z, about 0.5 m across with both wings.
static func _make_meshes() -> void:
	if _body_mesh:
		return
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.13, 0.1, 0.09)
	_mat.roughness = 1.0
	_mat.metallic_specular = 0.2
	_wing_mat = StandardMaterial3D.new()
	_wing_mat.albedo_color = Color(0.2, 0.13, 0.11)
	_wing_mat.roughness = 0.9
	_wing_mat.metallic_specular = 0.25
	_wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wing_mat.backlight_enabled = true
	_wing_mat.backlight = Color(0.25, 0.08, 0.05)      # thin skin: light shows through reddish
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := SphereMesh.new()
	body.radius = 0.045
	body.height = 0.13
	body.radial_segments = 10
	body.rings = 6
	st.append_from(body, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(1.0, 1.0, 0.85)), Vector3(0, 0, 0.01)))
	var head := SphereMesh.new()
	head.radius = 0.032
	head.height = 0.058
	head.radial_segments = 8
	head.rings = 5
	st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 0.012, -0.065)))
	var snout := SphereMesh.new()
	snout.radius = 0.016
	snout.height = 0.03
	snout.radial_segments = 6
	snout.rings = 4
	st.append_from(snout, 0, Transform3D(Basis(), Vector3(0, 0.004, -0.092)))
	for side in [1.0, -1.0]:
		var ear := CylinderMesh.new()
		ear.top_radius = 0.0
		ear.bottom_radius = 0.013
		ear.height = 0.05
		ear.radial_segments = 4
		ear.rings = 1
		st.append_from(ear, 0, Transform3D(Basis(Vector3.FORWARD, -side * 0.35), Vector3(side * 0.016, 0.05, -0.065)))
	_body_mesh = st.commit()
	# The wing (the right one; the left is mirrored): in the XZ plane, from the shoulder out.
	var pts := [
		Vector3(0.0, 0, -0.025), Vector3(0.09, 0.012, -0.05), Vector3(0.15, 0.02, -0.055),    # arm to the wrist
		Vector3(0.27, 0.0, -0.02),                                                               # first finger
		Vector3(0.2, 0.0, 0.01), Vector3(0.24, 0.0, 0.06),                                       # scallop, second finger
		Vector3(0.16, 0.0, 0.05), Vector3(0.15, 0.0, 0.1),                                       # scallop, third finger
		Vector3(0.08, 0.0, 0.07), Vector3(0.0, 0.0, 0.05),                                       # scallop to the leg
	]
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0.05, 0.005, 0.0)
	for i in pts.size() - 1:
		for v in [c, pts[i], pts[i + 1]]:
			ws.set_normal(Vector3.UP)
			ws.add_vertex(v)
	_wing_mesh = ws.commit()
