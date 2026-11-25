class_name Villager
extends Node3D
## Village people (design/world.md, 7): the merchant stands at the stall, villagers stroll
## between spots on the plaza and pause. No collision, no combat; they turn to face the hero
## when close. Zone-local position under the settlement.

const WALK := 1.3                 ## m/s

var outfit := "villager"
var wander := true
var home := Vector3.ZERO          ## zone-local
var terrain: Terrain
var _model: Humanoid
var _target := Vector3.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_outfit: String, p_home: Vector3, p_terrain: Terrain, p_wander: bool, seed: int) -> void:
	outfit = p_outfit
	home = p_home
	terrain = p_terrain
	wander = p_wander
	_rng.seed = seed


func _ready() -> void:
	BlobShadow.attach(self, 0.5)
	_model = Humanoid.new()
	add_child(_model)
	var dir := "res://assets/characters/%s/" % outfit
	_model.build({"outfit": dir + outfit, "pick": [1, 1, 1, 1, 1]})
	position = home
	position.y = terrain.height_at(home.x, home.z)
	rotation.y = atan2(home.x, home.z)          # face the plaza's center (units face -Z)
	_target = home
	_wait = _rng.randf_range(1.0, 6.0)
	for gi in _model.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 90.0


func _process(dt: float) -> void:
	var p := World.player
	var close := p != null and p.global_position.distance_to(global_position) < 6.0
	var to := _target - position
	to.y = 0.0
	if close and to.length() < 0.5 or (close and not wander):
		# Face the hero.
		var d := p.global_position - global_position
		_face(Vector3(d.x, 0, d.z), dt)
		_model.anim.set_move("idle")
		return
	if not wander:
		_model.anim.set_move("idle")
		return
	if to.length() < 0.3:
		_model.anim.set_move("idle")
		_wait -= dt
		if _wait <= 0.0:
			# Next spot: somewhere on the plaza around home.
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 12.0)
			_target = home + Vector3(cos(a) * r, 0, sin(a) * r)
			_wait = _rng.randf_range(3.0, 10.0)
		return
	var step := to.normalized() * minf(WALK * dt, to.length())
	position += step
	position.y = terrain.height_at(position.x, position.z)
	_face(to, dt)
	_model.anim.set_move("walk", WALK / float(CharAnimator.CLIP_SPEED.walk))


func _face(dir: Vector3, dt: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z)        # units face -Z
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, dt * 5.0))
