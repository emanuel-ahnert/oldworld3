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
## A guard (Settlement, at the palisade's gates): its own look (Humanoid cfg), standing still,
## facing `face` (world yaw) unless the hero is close.
var look := {}
var face := NAN
## Guards fight: monsters that come for the village (chasing someone, or inside the palisade)
## within SIGHT m of the post are run down and struck (STRIKE of their health a blow, every
## SWING s). A monster a guard has struck gives the hero nothing when it dies (Enemy.guard_hit):
## no XP, no loot, no quest credit. Monsters don't strike back at guards. Past LEASH m from the
## post, or when the monster dies or turns back, the guard walks back to the gate.
var guard := false
const SIGHT := 24.0
const LEASH := 34.0
const REACH := 2.0
const RUN := 5.5                  ## m/s
const SWING := 1.6
const STRIKE := 0.12              ## of the monster's max health per blow
var _foe: Enemy
var _scan_at := 0.0
var _swing_at := 0.0
var _stats: Combatant             ## the guard as a damage source (no health of its own to lose)


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
	_model.build(look if not look.is_empty() else {"outfit": dir + outfit, "pick": [1, 1, 1, 1, 1]})
	position = home
	position.y = terrain.height_at(home.x, home.z)
	rotation.y = atan2(home.x, home.z) if is_nan(face) else face      # face the plaza's center (units face -Z)
	_target = home
	_wait = _rng.randf_range(1.0, 6.0)
	for gi in _model.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 90.0


func _process(dt: float) -> void:
	if guard and _fight(dt):
		return
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
		if not is_nan(face):
			rotation.y = lerp_angle(rotation.y, face, minf(1.0, dt * 3.0))      # back to the post
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


## The post in world space (home is zone-local).
func _post() -> Vector3:
	return get_parent().to_global(home) if get_parent() is Node3D else home


## The guard's fight (true while busy with it: chasing a monster, striking or walking back).
func _fight(dt: float) -> bool:
	var t := Combatant.now()
	var post := _post()
	if t >= _scan_at:
		_scan_at = t + 0.3
		if _foe == null or not _wants(_foe, post, LEASH):
			_foe = null
			var best := SIGHT
			for e in World.enemies:
				var d := e.global_position.distance_to(post)
				if d < best and _wants(e, post, SIGHT):
					best = d
					_foe = e
	if _foe != null:
		var to := _foe.global_position - global_position
		to.y = 0.0
		var reach := REACH + float(_foe.data.get("radius", 0.5))
		if to.length() > reach:
			_move(to, RUN, dt)
			_model.anim.set_move("run", RUN / float(CharAnimator.CLIP_SPEED.run))
		else:
			_face(to, dt)
			_model.anim.set_move("idle")
			if t >= _swing_at:
				_swing_at = t + SWING
				_strike(_foe)
		return true
	# No monster: back to the post.
	var back := post - global_position
	back.y = 0.0
	if back.length() > 0.4:
		_move(back, RUN * 0.6, dt)
		_model.anim.set_move("run", RUN * 0.6 / float(CharAnimator.CLIP_SPEED.run))
		return true
	return false


## Whether the guard goes for monster `e`: alive, near the post, and coming for the village
## (in a chase, or inside the wall); a polymorphed sheep is left alone.
func _wants(e: Enemy, post: Vector3, within: float) -> bool:
	if not is_instance_valid(e) or e.stats == null or e.stats.dead or not e.visible or e.is_sheep():
		return false
	if e.global_position.distance_to(post) > within:
		return false
	var inside: bool = get_parent() is Node3D and (e.global_position - (get_parent() as Node3D).global_position).length() < Palisade.RADIUS
	return e.state == Enemy.State.CHASE or inside


func _move(dir: Vector3, speed: float, dt: float) -> void:
	var step := dir.normalized() * minf(speed * dt, dir.length())
	global_position += step
	position.y = terrain.height_at(position.x, position.z)
	_face(dir, dt)


func _strike(e: Enemy) -> void:
	if _stats == null:
		_stats = Combatant.new()
		_stats.name = "Stats"
		_stats.display_name = "Guard"
		_stats.body = self
		add_child(_stats)
		_stats.setup(10, {"hp": 1000.0, "attack": 20.0, "defense": 20.0})
	_model.anim.play_shot("attack1")
	e.mark_guard_hit()
	e.stats.take_damage(maxi(1, roundi(e.stats.max_hp * STRIKE * randf_range(0.85, 1.0))), false, _stats)
	Audio.hit("sword", false, -4.0, e.surface())
