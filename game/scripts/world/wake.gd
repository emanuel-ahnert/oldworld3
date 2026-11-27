class_name Wake
extends Node3D
## Water stirred by legs (the hero, monsters near him) wading through a lake: rings of ripples
## spread from them (one every RING_EVERY s while moving, none standing still) and every
## footfall while running throws up a splash of droplets. Pools of ripple quads
## (shaders/ripple) and one-shot particle bursts, reused; made on first use under World.root.

const RINGS := 48
const SPLASHES := 10
const RING_LIFE := 1.3
const RING_SIZE := 1.7             ## m radius at the end
const RING_EVERY := 0.28           ## s between rings while moving
const STILL_EVERY := 1.4           ## s between rings standing in the water
const CHECK := 0.1                 ## s between water checks per body

static var _inst: Wake

var _rings: Array[Dictionary] = []     ## {mi, born, life}
var _next_ring := 0
var _splashes: Array[CPUParticles3D] = []
var _next_splash := 0
var _bodies := {}                      ## instance id -> {check, level, ring, step}


## A body at pos moving at speed (m/s, horizontal) this frame: ripples and splashes if it
## stands in water.
static func stir(body: Node3D, speed: float) -> void:
	if World.zones == null or World.root == null:
		return
	if _inst == null or not is_instance_valid(_inst):
		_inst = Wake.new()
		_inst.name = "Wake"
		World.root.add_child(_inst)
	_inst._stir(body, speed)


func _stir(body: Node3D, speed: float) -> void:
	var t := Combatant.now()
	var id := body.get_instance_id()
	var b: Dictionary = _bodies.get(id, {"check": 0.0, "level": NAN, "ring": 0.0, "step": 0.0})
	_bodies[id] = b
	var p := body.global_position
	if t >= float(b.check):
		b.check = t + CHECK
		b.level = World.zones.water_level(p.x, p.z)
	var level: float = b.level
	if is_nan(level) or p.y > level + 0.1:
		return
	var moving := speed > 0.6
	if moving and t >= float(b.ring):
		# (Standing still: none; the slow rings round a resting hero looked busy.)
		b.ring = t + RING_EVERY * clampf(4.0 / maxf(speed, 0.1), 0.6, 1.4)
		_ring(Vector3(p.x, level + 0.015, p.z), 1.0, RING_SIZE)
	if moving and speed > 2.0 and t >= float(b.step):
		# Footfalls: a splash each step (faster running, faster steps).
		b.step = t + clampf(1.5 / speed, 0.18, 0.45)
		var side := 0.15 if randf() < 0.5 else -0.15
		var fwd := -body.global_basis.z
		var q := p + fwd * 0.35 + body.global_basis.x * side
		_splash(Vector3(q.x, level + 0.02, q.z), clampf(speed / 6.0, 0.5, 1.3))


func _ring(pos: Vector3, strength: float, size: float) -> void:
	if _rings.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/ripple.gdshader")
		var q := PlaneMesh.new()
		q.size = Vector2(2, 2)
		for i in RINGS:
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			add_child(mi)
			_rings.append({"mi": mi, "born": -1.0, "life": RING_LIFE})
	var r: Dictionary = _rings[_next_ring]
	_next_ring = (_next_ring + 1) % RINGS
	var mi: MeshInstance3D = r.mi
	mi.global_position = pos
	mi.scale = Vector3(size, 1, size)
	mi.rotation.y = randf() * TAU
	mi.set_instance_shader_parameter("strength", strength)
	mi.set_instance_shader_parameter("age", 0.0)
	mi.visible = true
	r.born = Combatant.now()
	r.life = RING_LIFE * (1.0 if strength >= 1.0 else 1.5)


func _splash(pos: Vector3, power: float) -> void:
	if _splashes.is_empty():
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _drop_texture()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.07, 0.07)
		quad.material = mat
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.9, 0.95, 1.0, 0.85))
		ramp.set_color(1, Color(0.9, 0.95, 1.0, 0.0))
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.7))
		curve.add_point(Vector2(0.3, 1.0))
		curve.add_point(Vector2(1, 0.5))
		for i in SPLASHES:
			var ps := CPUParticles3D.new()
			ps.mesh = quad
			ps.amount = 16
			ps.lifetime = 0.6
			ps.one_shot = true
			ps.explosiveness = 0.95
			ps.emitting = false
			ps.local_coords = false
			ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			ps.emission_sphere_radius = 0.12
			ps.direction = Vector3.UP
			ps.spread = 38.0
			ps.initial_velocity_min = 1.4
			ps.initial_velocity_max = 3.0
			ps.gravity = Vector3(0, -9.8, 0)
			ps.scale_amount_min = 0.6
			ps.scale_amount_max = 1.4
			ps.scale_amount_curve = curve
			ps.color_ramp = ramp
			add_child(ps)
			_splashes.append(ps)
	var s := _splashes[_next_splash]
	_next_splash = (_next_splash + 1) % SPLASHES
	s.global_position = pos
	s.initial_velocity_max = 3.0 * power
	s.initial_velocity_min = 1.4 * power
	s.restart()
	_ring(pos, 0.8, 0.8)                    # the foot's own small ring


## A soft round droplet (made once).
static var _drop: Texture2D


static func _drop_texture() -> Texture2D:
	if _drop:
		return _drop
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)))
	_drop = ImageTexture.create_from_image(img)
	return _drop


func _process(_dt: float) -> void:
	var t := Combatant.now()
	for r in _rings:
		var mi: MeshInstance3D = r.mi
		if not mi.visible:
			continue
		var a := (t - float(r.born)) / float(r.life)
		if a >= 1.0:
			mi.visible = false
		else:
			mi.set_instance_shader_parameter("age", a)
	# Forget bodies that are gone.
	if Engine.get_process_frames() % 300 == 0:
		for id in _bodies.keys():
			if not is_instance_id_valid(id):
				_bodies.erase(id)
