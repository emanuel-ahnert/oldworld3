class_name Sheep
extends Node3D
## A polymorphed enemy (Enemy.polymorph): a small woolly sheep built in code. A cloud of white
## wool puffs for the body, a dark face with ears, four thin dark legs that step while it walks
## (`walking`), and the head dipping to graze while it stands. Faces -Z like the game's units.

var walking := false
var _legs: Array[Node3D] = []
var _head: Node3D
var _t := randf() * 10.0

static var _wool: StandardMaterial3D
static var _dark: StandardMaterial3D


func _init() -> void:
	if _wool == null:
		_wool = StandardMaterial3D.new()
		_wool.albedo_color = Color(0.78, 0.76, 0.71)
		_wool.roughness = 1.0
		_dark = StandardMaterial3D.new()
		_dark.albedo_color = Color(0.16, 0.14, 0.13)
		_dark.roughness = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# The body: overlapping wool puffs in an egg shape.
	for i in 14:
		var p := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.42, 0.66), rng.randf_range(-0.32, 0.3))
		_ball(self, p, rng.randf_range(0.13, 0.19), _wool)
	_ball(self, Vector3(0, 0.55, 0), 0.25, _wool).scale = Vector3(1.0, 0.85, 1.4)
	# The head: a dark muzzle, a woolly cap, ears.
	_head = Node3D.new()
	_head.position = Vector3(0, 0.62, -0.42)
	add_child(_head)
	_ball(_head, Vector3(0, 0, -0.05), 0.11, _dark).scale = Vector3(0.85, 0.95, 1.35)
	_ball(_head, Vector3(0, 0.08, 0.02), 0.1, _wool)
	for side in [-1.0, 1.0]:
		var ear := _ball(_head, Vector3(side * 0.11, 0.04, 0.02), 0.045, _dark)
		ear.scale = Vector3(1.6, 0.6, 1.0)
		_ball(_head, Vector3(side * 0.045, 0.03, -0.13), 0.016, _wool)          # eyes (pale)
	# Legs: thin dark cylinders, hinged at the top.
	for p in [Vector3(-0.12, 0.42, -0.2), Vector3(0.12, 0.42, -0.2), Vector3(-0.12, 0.42, 0.22), Vector3(0.12, 0.42, 0.22)]:
		var hinge := Node3D.new()
		hinge.position = p
		add_child(hinge)
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.032
		cm.bottom_radius = 0.026
		cm.height = 0.42
		cm.radial_segments = 8
		leg.mesh = cm
		leg.material_override = _dark
		leg.position.y = -0.21
		hinge.add_child(leg)
		_legs.append(hinge)


func _ball(parent: Node3D, p: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = p
	parent.add_child(mi)
	return mi


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	for i in _legs.size():
		var phase := _t * 9.0 + (PI if i in [1, 2] else 0.0)
		_legs[i].rotation.x = sin(phase) * 0.45 if walking else lerpf(_legs[i].rotation.x, 0.0, 0.2)
	# Standing: the head goes down to graze now and then; walking: it bobs.
	var graze := 0.0 if walking else clampf(sin(_t * 0.7) * 2.0 - 0.6, 0.0, 1.0)
	_head.rotation.x = -graze * 0.9 + (sin(_t * 9.0) * 0.05 if walking else 0.0)
	_head.position.y = 0.62 - graze * 0.18
