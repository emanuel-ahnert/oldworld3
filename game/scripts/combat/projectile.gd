class_name Projectile
extends Node3D
## A spell flying to its target (Fire Bolt, Ice Bolt): a glowing ball that homes in and calls
## `on_hit` when it arrives (or vanishes if the target is gone). An arrow (arrow()) flies faster
## in a shallow arc, pointing along its path, and sticks in the target for a moment.

var target: Node3D
var speed := 24.0
var on_hit: Callable
var _height := 1.1


static func launch(from: Vector3, p_target: Node3D, color: Color, p_on_hit: Callable, size := 0.18) -> Projectile:
	var p := Projectile.new()
	p.target = p_target
	p.on_hit = p_on_hit
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	# A small trail of fading copies makes the bolt read at speed.
	World.root.add_child(p)
	p.global_position = from
	return p


const ARROW_SPEED := 38.0
const ARROW_STICK := 2.0         ## seconds an arrow stays in its target
static var _arrow_parts: Array = []  ## [mesh, material] of shaft, head, fletching (shared)

var _arrow := false
var _flat := Vector3.ZERO        ## an arrow's position without its arc
var _dist0 := 1.0                ## its distance at launch (for the arc)
var _stuck := -1.0               ## when it stuck in the target


## An arrow from `from` to the target's chest: a wooden shaft, a steel head, red fletching.
static func arrow(from: Vector3, p_target: Node3D, p_on_hit: Callable) -> Projectile:
	var p := Projectile.new()
	p.target = p_target
	p.on_hit = p_on_hit
	p.speed = ARROW_SPEED
	p._arrow = true
	p._height = 1.0
	if _arrow_parts.is_empty():
		_build_arrow_parts()
	# The model points along -Z (look_at); its tip at the node, the shaft behind it.
	for part: Array in _arrow_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		mi.transform = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(mi)
	World.root.add_child(p)
	p.global_position = from
	p._flat = from
	p._dist0 = maxf(1.0, from.distance_to(p_target.global_position + Vector3(0, p._height, 0)))
	return p


static func _build_arrow_parts() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.4, 0.24)
	wood.roughness = 0.8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.72, 0.75)
	steel.metallic = 0.8
	steel.roughness = 0.35
	var feather := StandardMaterial3D.new()
	feather.albedo_color = Color(0.75, 0.2, 0.15)
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	feather.roughness = 0.9
	var along := Basis(Vector3.RIGHT, -PI / 2)        # a mesh's +Y -> -Z
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.011
	shaft.bottom_radius = 0.011
	shaft.height = 0.78
	shaft.radial_segments = 6
	shaft.rings = 1
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.026
	head.height = 0.09
	head.radial_segments = 4
	head.rings = 1
	var fl := QuadMesh.new()
	fl.size = Vector2(0.06, 0.16)                      # x: out from the shaft, y: along it
	_arrow_parts = [
		[shaft, wood, Transform3D(along, Vector3(0, 0, 0.09 + 0.39))],
		[head, steel, Transform3D(along, Vector3(0, 0, 0.045))],
	]
	for i in 3:
		var b := Basis(Vector3.BACK, TAU * i / 3.0) * along
		var off := b * Vector3(0.035, 0, 0)
		_arrow_parts.append([fl, feather, Transform3D(b, Vector3(0, 0, 0.78) + Vector3(off.x, off.y, 0))])


func _process(dt: float) -> void:
	if _stuck >= 0.0:
		# Stuck in the target: gone after a while, or with the target.
		if Time.get_ticks_msec() / 1000.0 - _stuck > ARROW_STICK or not is_instance_valid(target) \
				or not target.visible or (target.get("stats") != null and target.stats.dead):
			queue_free()
		return
	if target == null or not is_instance_valid(target) or not target.visible:
		queue_free()
		return
	var goal := target.global_position + Vector3(0, _height, 0)
	if _arrow:
		_fly_arrow(goal, dt)
		return
	var d := goal - global_position
	if d.length() < speed * dt + 0.3:
		if on_hit.is_valid():
			on_hit.call()
		queue_free()
		return
	global_position += d.normalized() * speed * dt


## Homes in like a bolt (on `_flat`) with a shallow arc on top, nose along its path. On arrival
## it hits and stays stuck in the target, a little sunk in.
func _fly_arrow(goal: Vector3, dt: float) -> void:
	var d := goal - _flat
	var dir := d.normalized()
	if d.length() < speed * dt + 0.3:
		if on_hit.is_valid():
			on_hit.call()
		var at := goal - dir * 0.25 + Vector3(randf_range(-0.12, 0.12), randf_range(-0.15, 0.15), 0)
		var xf := Transform3D(Basis.looking_at(dir), at)
		reparent(target)
		global_transform = xf.translated(dir * 0.12)     # the head sunk in
		_stuck = Time.get_ticks_msec() / 1000.0
		return
	_flat += dir * speed * dt
	var s := clampf(1.0 - _flat.distance_to(goal) / _dist0, 0.0, 1.0)
	var arc := minf(_dist0 * 0.05, 1.2) * 4.0 * s * (1.0 - s)
	var pos := _flat + Vector3(0, arc, 0)
	var step := pos - global_position
	global_position = pos
	if step.length() > 0.001:
		global_basis = Basis.looking_at(step.normalized())
