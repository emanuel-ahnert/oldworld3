class_name Enemy
extends CharacterBody3D
## An enemy in the world (design/world.md, section 4; design/mechanics.md, section 7):
## idle and wander at its spawn point, aggro by radius, chase and fight in real time, help its
## group, leash home when dragged too far, die, respawn after a while.

enum State { IDLE, CHASE, RETURN, DEAD }

const LEASH := 40.0
## Past LEASH an enemy still follows while the hero keeps hurting it (kiting): it evades only
## after LEASH_GRACE seconds without damage.
const LEASH_GRACE := 6.0
const SOCIAL := 10.0
const RESPAWN := 300.0
const CORPSE := 30.0
const GRAVITY := 20.0

var kind := ""
var data: Dictionary
var stats: Combatant
var home := Vector3.ZERO
var group: Array[Enemy] = []
var state := State.IDLE
var humanoid: Humanoid
var nameplate: Label3D

var _model: Node3D
var _visual: Node3D          ## creature mesh (procedural motion)
var _canim: CreatureAnim     ## the creature's clips when it has a rigged model (else procedural)
var _last_yaw := 0.0
var _base_scale := Vector3.ONE  ## _model's scale when it died (kind, champion), for respawn
var _swing_at := 0.0
var _cooldowns := {}
var _wander_to := Vector3.ZERO
var _wander_at := 0.0
var _died_at := -1.0
var _charge_until := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit := false
var _howled := false
var _smoked := false
var _phase := 0.0
var _lunge := 0.0
var _flinch := 0.0
var _last_hurt := 0.0
var _sleep := 0
var silenced_until := 0.0    ## Stone Shock: no special abilities until then
var champion := ""           ## the name of a champion, "" for ordinary enemies
var modifier := ""           ## champions: Burning, Swift, Shielded, Thorned or Winged
var _aura_at := 0.0
var _steer_dir := Vector3.ZERO   ## the way around an obstacle chosen last (Vector3.ZERO: none)
var _steer_side := 0             ## which side it goes around (1 left, -1 right), kept a while
var _side_until := 0.0
var _steer_frame := 0
var _progress_at := 0.0          ## stuck check: where it was, and when
var _progress_pos := Vector3.ZERO
var _detour_until := 0.0
var _shield_at := 0.0


## champion_name: a named champion of this kind (design/world.md, 7): 2.5× health, +15%
## Attack and Defense, bigger, always drops gear.
func setup(p_kind: String, level: int, pos: Vector3, champion_name := "", p_modifier := "") -> void:
	kind = p_kind
	data = EnemyData.get_kind(kind)
	home = pos
	champion = champion_name
	modifier = p_modifier
	stats = Combatant.new()
	stats.name = "Stats"
	stats.display_name = data.name if champion == "" else champion
	stats.tier = data.tier if champion == "" else "champion"
	stats.swing_time = data.swing
	stats.base_crit = data.get("crit", 0.05)
	stats.crit_chance = stats.base_crit
	stats.dodge_chance = data.get("dodge", 0.05)    # slow or bodiless kinds: 0 (enemy_data)
	var m := 1.0 if champion == "" else 1.15
	stats.setup(level, {"hp": float(data.hp) * (1.0 if champion == "" else 2.5), "attack": float(data.attack) * m, "defense": float(data.defense) * m, "resistance": float(data.get("resistance", 8)) * m, "magic": float(data.get("magic", 4)) * m})
	if modifier == "Swift":
		stats.swing_time *= 0.75
	stats.types = data.get("types", ["Physical"])
	stats.affinities = stats.types
	stats.body = self
	add_child(stats)
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func _ready() -> void:
	BlobShadow.attach(self, float(data.radius) * 1.4 * float(data.get("scale", 1.0)) * (1.2 if champion != "" else 1.0))
	collision_layer = 2      # enemies (picking); they don't block the hero or each other
	collision_mask = 1       # terrain and trees
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = data.radius
	cap.height = 1.6 * data.get("scale", 1.0) if String(data.model).begins_with("humanoid") else 1.0
	col.shape = cap
	col.position.y = cap.height / 2
	add_child(col)
	floor_max_angle = deg_to_rad(50)
	_model = Node3D.new()
	add_child(_model)
	var m: String = data.model
	if m.begins_with("creature:"):
		var path := m.trim_prefix("creature:")
		if not ResourceLoader.exists(path):
			path = data.fallback
		# Rigged and animated version (tools/build_creatures.sh) when there is one.
		var rigged := path.get_basename() + "_rig.glb"
		if ResourceLoader.exists(rigged) and not OS.get_cmdline_user_args().has("--static-creatures"):
			path = rigged
		_visual = load(path).instantiate()
		_visual.rotation.y = PI          # models face +Z; units face -Z
		_model.add_child(_visual)
		_canim = CreatureAnim.attach(_visual, path)
	else:
		humanoid = Humanoid.new()
		_model.add_child(humanoid)
		humanoid.build(_humanoid_cfg(m.trim_prefix("humanoid:")))
		_model.scale = Vector3.ONE * float(data.get("scale", 1.0))
	nameplate = Label3D.new()
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font_size = 36
	nameplate.outline_size = 8
	nameplate.pixel_size = 0.005
	nameplate.position.y = (2.1 * float(data.get("scale", 1.0))) if humanoid else 1.6
	nameplate.text = plate_name()
	nameplate.modulate = Color(1, 0.85, 0.3) if data.behavior == "defensive" else Color(1, 0.4, 0.35)
	if champion != "":
		nameplate.modulate = Color(1, 0.6, 0.15)
		nameplate.position.y *= 1.2
		_model.scale *= 1.2
		if modifier == "Burning":
			var glow := OmniLight3D.new()
			glow.light_color = Color(1, 0.5, 0.15)
			glow.light_energy = 2.5
			glow.omni_range = 5.0
			glow.position.y = 1.2
			add_child(glow)
	nameplate.visible = false
	add_child(nameplate)
	for gi in _model.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 140.0
	_wander_at = Combatant.now() + randf_range(3, 12)
	rotation.y = randf() * TAU


func plate_name() -> String:
	if champion != "":
		return "%s  %d  (%s Champion)" % [champion, stats.level, modifier] if modifier != "" else "%s  %d  (Champion)" % [champion, stats.level]
	return "%s  %d" % [data.name, stats.level] + ("  (Elite)" if data.tier == "elite" else "")


func _humanoid_cfg(outfit: String) -> Dictionary:
	var dir := "res://assets/characters/%s/" % outfit
	var cfg := {"pick": [1, 1, 1, 1, 1], "outfit": dir + outfit}
	if not ResourceLoader.exists(dir + outfit + "_color.png"):
		# No outfit generated yet: the base body, tinted.
		cfg.pick = [0, 0, 0, 0, 0]
		cfg.tint_a = data.get("tint", Color(0.55, 0.75, 0.45) if outfit == "goblin" else Color(0.7, 0.6, 0.55))
	var w := "res://assets/weapons/%s.glb" % data.get("weapon", "dagger")
	if data.has("weapon") and ResourceLoader.exists(w):
		cfg.weapon = w
	if data.get("shield", false):
		cfg.shield = "res://assets/weapons/shield.glb"
	return cfg


func _physics_process(dt: float) -> void:
	var t := Combatant.now()
	if state == State.DEAD:
		_dead_process(t)
		return
	var p := World.player
	var to_player := (p.global_position - global_position) if p else Vector3.ZERO
	var dist := Vector2(to_player.x, to_player.z).length()
	# Far away and idle: sleep (no physics), check again now and then.
	if state == State.IDLE and dist > 70.0:
		_sleep += 1
		if _sleep % 15 != 0:
			return
	_sleep = 0
	var want := Vector3.ZERO
	var speed := 0.0
	match state:
		State.IDLE:
			if p and not p.stats.dead and _aggro_radius() > 0.0 and dist < _aggro_radius():
				engage()
			elif t > _wander_at:
				_wander_at = t + randf_range(6, 16)
				_wander_to = home + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			var w := _wander_to - global_position
			w.y = 0
			if _wander_to != Vector3.ZERO and w.length() > 0.8:
				want = w.normalized()
				speed = 1.6
		State.CHASE:
			if p == null or p.stats.dead or (global_position.distance_to(home) > LEASH and t - _last_hurt > LEASH_GRACE):
				_go_home()
			else:
				stats.mark_combat()
				var reach: float = data.reach + 0.45
				speed = data.speed * stats.move_factor() * (1.4 if modifier == "Swift" else 1.0)
				_champion_process(t, dist)
				if t < _charge_until:
					want = _charge_dir
					speed = 15.0
					if not _charge_hit and dist < reach + 0.3:
						_charge_hit = true
						_charge_until = 0.0
						_hit_player(55.0, "Tusk Charge")
						p.knockback(_charge_dir * 6.0)
				elif not stats.stunned():
					_use_abilities(t, dist)
					var ranged: float = data.get("ranged", 0.0)
					if ranged > 0.0:
						reach = ranged
					if dist > reach:
						want = Vector3(to_player.x, 0, to_player.z).normalized()
					else:
						# In reach: face the hero and swing (or shoot) on the swing timer.
						speed = 0.0
						_face(to_player, dt, 10.0)
						if t >= _swing_at:
							_swing_at = t + stats.swing_time / stats.buff_mult("attack_speed")
							_auto_attack()
					# Spread out around the hero instead of stacking on one spot.
					var sep := _separation(to_player, dist)
					if sep.length() > 0.05:
						want = (want * (1.0 if speed > 0.0 else 0.0) + sep).normalized()
						speed = maxf(speed, 2.5)
				else:
					speed = 0.0
		State.RETURN:
			var h := home - global_position
			h.y = 0
			if h.length() < 1.0:
				state = State.IDLE
				stats.hp = stats.max_hp
				stats.dots.clear()
				stats.buffs.clear()
			else:
				want = h.normalized()
				speed = data.speed * 1.2
	if want != Vector3.ZERO and speed > 0.5 and steering:
		want = _steer(want, speed, t)
	if want != Vector3.ZERO:
		_face(want, dt, 8.0)
	velocity.x = want.x * speed
	velocity.z = want.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	_animate(dt, speed)
	nameplate.visible = state == State.CHASE or (p != null and p.target == self)
	if nameplate.visible:
		nameplate.text = plate_name() + ("  %d%%" % roundi(100.0 * stats.hp / stats.max_hp) if stats.hp < stats.max_hp else "")


## Going around obstacles (tree trunks, houses, crates, cliffs): probes ahead along `want`;
## when blocked, takes the clear direction closest to it, going around on one side and keeping
## that side for a while (no dithering at a wall). When it still makes no headway for half a
## second, it sidesteps along the wall for a moment. Probes run every third frame.
const PROBE_ANGLES := [30.0, 55.0, 80.0, 110.0, 140.0]
static var steering := true           ## off: straight at the goal (test: --no-steer)


func _steer(want: Vector3, speed: float, t: float) -> Vector3:
	# Stuck check: less than a quarter of the expected way in half a second.
	if t - _progress_at > 0.5:
		var moved := Vector2(global_position.x - _progress_pos.x, global_position.z - _progress_pos.z).length()
		if _progress_at > 0.0 and moved < speed * 0.5 * 0.25 and t > _detour_until:
			if _steer_side == 0:
				_steer_side = 1 if randf() < 0.5 else -1
			_side_until = t + 2.0
			_detour_until = t + 0.8
		_progress_at = t
		_progress_pos = global_position
	if t < _detour_until:
		var d := want.rotated(Vector3.UP, deg_to_rad(80.0) * _steer_side)
		return d if _clear(d) else want.rotated(Vector3.UP, deg_to_rad(120.0) * _steer_side)
	_steer_frame += 1
	if _steer_frame % 3 != 0 and _steer_dir != Vector3.ZERO:
		# Between probes keep the way found, turned with the goal.
		return _steer_dir
	if _clear(want):
		_steer_dir = Vector3.ZERO
		if t > _side_until:
			_steer_side = 0
		return want
	var sides := [_steer_side] if _steer_side != 0 else [1, -1]
	if _steer_side == 0:
		sides.shuffle()
	for a: float in PROBE_ANGLES:
		for side: int in sides:
			var d := want.rotated(Vector3.UP, deg_to_rad(a) * side)
			if _clear(d):
				_steer_side = side
				_side_until = t + 2.0
				_steer_dir = d
				return d
	# Boxed in on the committed side: try the other one next time.
	_steer_side = -_steer_side if _steer_side != 0 else 1
	_steer_dir = Vector3.ZERO
	return want


## Nothing that blocks within reach along `dir` (horizontal rays at knee height in the middle
## and at both shoulders); walkable slopes don't count.
func _clear(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var r: float = data.radius
	var from := global_position + Vector3(0, 0.6, 0)
	var side := Vector3(-dir.z, 0, dir.x) * r * 0.8
	var reach := r + 1.4
	for off: Vector3 in [Vector3.ZERO, side, -side]:
		var q := PhysicsRayQueryParameters3D.create(from + off, from + off + dir * reach, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.6:
			return false
	return true


func _separation(to_player: Vector3, dist: float) -> Vector3:
	var sep := Vector3.ZERO
	var me: float = data.radius
	for o in World.enemies:
		if o == self or o.state != State.CHASE:
			continue
		var d := global_position - o.global_position
		d.y = 0.0
		var l := d.length()
		var min_d: float = me + float(o.data.radius) + 0.3
		if l < min_d:
			sep += (d / l if l > 0.01 else Vector3(randf() - 0.5, 0, randf() - 0.5)) * (min_d - l)
	var keep := me + 0.5
	if dist < keep:
		sep -= Vector3(to_player.x, 0, to_player.z).normalized() * (keep - dist) * 2.0
	return sep


func _aggro_radius() -> float:
	var base: float = EnemyData.AGGRO[data.behavior]
	if base <= 0.0:
		return 0.0
	var diff := World.player.stats.level - stats.level
	var r := maxf(4.0, base - diff)
	return r * 0.3 if World.player.stealthed else r


func _face(dir: Vector3, dt: float, rate: float) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-rate * dt))


## Starts fighting the hero and pulls group members nearby along.
func engage() -> void:
	if state == State.CHASE or state == State.DEAD:
		return
	state = State.CHASE
	stats.mark_combat()
	_swing_at = Combatant.now() + 0.6
	Audio.sfx("alert", -8.0)
	for m in group:
		if m != self and m.state == State.IDLE and m.global_position.distance_to(global_position) < SOCIAL:
			m.engage()


func _go_home() -> void:
	if state != State.RETURN:
		World.float_text(global_position + Vector3(0, 2.0, 0), "Evade", Color(0.85, 0.85, 0.85), 32, self)
	state = State.RETURN
	# Evading: the hero lets go of it (target and auto-attack), like in WoW.
	var p := World.player
	if p and p.target == self:
		p.set_target(null)


func _use_abilities(t: float, dist: float) -> void:
	if t < silenced_until:
		return
	for a in data.abilities:
		if t < float(_cooldowns.get(a, 0.0)):
			continue
		match a:
			"howl":
				if not _howled:
					_howled = true
					World.float_text(global_position + Vector3(0, 1.6, 0), "Howl", Color(1, 0.6, 0.3), 36, self)
					for m in group:
						if not m.stats.dead:
							m.stats.add_buff("howl", 15.0, {"attack": 1.25})
			"tusk_charge":
				if dist > 8.0 and dist < 20.0:
					_cooldowns[a] = t + 12.0
					_charge_until = t + 1.4
					_charge_hit = false
					var d := World.player.global_position - global_position
					_charge_dir = Vector3(d.x, 0, d.z).normalized()
					World.float_text(global_position + Vector3(0, 1.4, 0), "Tusk Charge", Color(1, 0.6, 0.3), 36, self)
			"sling_stone":
				if dist > 10.0 and dist < 25.0:
					_cooldowns[a] = t + 8.0
					_throw_stone()
			"poisoned_blade":
				if dist < float(data.reach) + 0.6:
					_cooldowns[a] = t + 12.0
					var p := World.player
					p.stats.add_dot("poison", 15.0, 1.0 / 32.0, stats)
					_hit_player(20.0, "Poisoned Blade")
					if humanoid:
						humanoid.anim.play_shot("attack2")
			"hard_shell", "shield_wall":
				if stats.hp < stats.max_hp * 0.6 and not stats.has_buff(a):
					_cooldowns[a] = t + 20.0
					stats.add_buff(a, 8.0, {"defense": 2.0})
					World.float_text(global_position + Vector3(0, 2.0, 0), "Hard Shell" if a == "hard_shell" else "Shield Wall", Color(0.8, 0.8, 1.0), 36, self)
			"pistol_shot":
				if dist > 4.0 and dist < 25.0:
					_cooldowns[a] = t + 30.0
					World.float_text(global_position + Vector3(0, 2.0, 0), "Pistol Shot", Color(1, 0.7, 0.4), 36, self)
					Audio.sfx("crit", -6.0)
					_hit_player(60.0, a)
			"dark_pact":
				if not stats.has_buff(a):
					stats.add_buff(a, 30.0, {"attack": 1.25, "magic": 1.25})
					World.float_text(global_position + Vector3(0, 2.0, 0), "Dark Pact", Color(0.7, 0.3, 0.9), 36, self)
			"life_drain":
				if dist < 20.0:
					_cooldowns[a] = t + 15.0
					World.player.stats.add_dot("life_drain", 12.0, 1.0 / 32.0, stats, false, true)
					World.float_text(global_position + Vector3(0, 2.2, 0), "Life Drain", Color(0.8, 0.2, 0.3), 36, self)
			"mesmerize":
				if dist < 10.0 and stats.hp < stats.max_hp * 0.8:
					_cooldowns[a] = t + 25.0
					World.player.stats.stun_until = t + 2.0
					World.float_text(World.player.global_position + Vector3(0, 2.2, 0), "Mesmerized", Color(0.8, 0.3, 0.9), 40, World.player)
			"venom_bite", "fire_brand", "savage_bite":
				if dist < float(data.reach) + 0.6:
					_cooldowns[a] = t + 10.0
					var p := World.player
					var dot: String = {"venom_bite": "poison", "fire_brand": "burn", "savage_bite": "bleed"}[a]
					p.stats.add_dot(dot, 15.0, 1.0 / 32.0, stats)
					_hit_player(30.0 if a == "venom_bite" else 35.0, a)
					World.float_text(global_position + Vector3(0, 1.6, 0), String(a).replace("_", " ").capitalize(), Color(0.6, 1, 0.4) if a == "venom_bite" else Color(1, 0.55, 0.2), 32, self)
					_strike()
					if humanoid:
						humanoid.anim.play_shot("attack2")
			"troll_smash", "cleave":
				if dist < float(data.reach) + 0.6:
					_cooldowns[a] = t + (8.0 if a == "troll_smash" else 7.0)
					if humanoid:
						humanoid.anim.play_shot("strike")
					World.float_text(global_position + Vector3(0, 2.4, 0), "Troll Smash" if a == "troll_smash" else "Cleave", Color(1, 0.6, 0.3), 36, self)
					_hit_player(60.0 if a == "troll_smash" else 55.0, a)
			"berserk":
				if stats.hp < stats.max_hp * 0.5 and not stats.has_buff("berserk"):
					stats.add_buff("berserk", 30.0, {"attack": 1.5, "defense": 0.75})
					World.float_text(global_position + Vector3(0, 2.4, 0), "Berserk!", Color(1, 0.3, 0.2), 44, self)
			"web":
				# Giant Spider: a web from up to 15 m roots the hero for 3 s.
				if dist > 4.0 and dist < 15.0:
					_cooldowns[a] = t + 18.0
					World.player.stats.root_until = t + 3.0
					World.float_text(World.player.global_position + Vector3(0, 2.2, 0), "Webbed", Color(0.9, 0.9, 0.85), 38, World.player)
			"wrap":
				# Mummy: bandages slow the hero by 30% for 5 s.
				if dist < float(data.reach) + 0.6:
					_cooldowns[a] = t + 12.0
					_hit_player(40.0, a)
					World.player.stats.slow(5.0, 0.7)
					World.float_text(global_position + Vector3(0, 2.0, 0), "Wrap", Color(0.9, 0.85, 0.6), 36, self)
					if humanoid:
						humanoid.anim.play_shot("attack2")
			"ancient_curse":
				# Mummy: the hero's Attack drops by a quarter for 10 s.
				if dist < 15.0 and not World.player.stats.has_buff(a):
					_cooldowns[a] = t + 20.0
					World.player.stats.add_buff(a, 10.0, {"attack": 0.75})
					World.float_text(World.player.global_position + Vector3(0, 2.2, 0), "Ancient Curse", Color(0.6, 0.4, 0.8), 36, World.player)
					if humanoid:
						humanoid.anim.play_shot("cast")
			"sun_strike":
				# Tomb Guardian: a Holy melee blow.
				if dist < float(data.reach) + 0.6:
					_cooldowns[a] = t + 8.0
					var r := stats.roll_damage_elem(World.player.stats, 50.0, "Holy")
					World.player.stats.take_damage(r.amount, r.crit, stats)
					World.float_text(global_position + Vector3(0, 2.4, 0), "Sun Strike", Color(1, 0.9, 0.4), 36, self)
					if humanoid:
						humanoid.anim.play_shot("strike")
			"sacred_ward":
				if stats.hp < stats.max_hp * 0.5 and not stats.has_buff(a):
					_cooldowns[a] = t + 25.0
					stats.add_buff(a, 10.0, {"defense": 1.5})
					World.float_text(global_position + Vector3(0, 2.4, 0), "Sacred Ward", Color(1, 0.9, 0.5), 36, self)
			"smoke_screen":
				if not _smoked and stats.hp < stats.max_hp * 0.7:
					_smoked = true
					World.add_smoke(global_position, 5.0, 9.0)
					World.float_text(global_position + Vector3(0, 2.0, 0), "Smoke Screen", Color(0.8, 0.8, 0.8), 36, self)


func _throw_stone() -> void:
	var p := World.player
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	ball.mesh = sm
	World.root.add_child(ball)
	var from := global_position + Vector3(0, 1.2, 0)
	ball.global_position = from
	var tw := ball.create_tween()
	tw.tween_property(ball, "global_position", p.global_position + Vector3(0, 1.2, 0), 0.45)
	tw.tween_callback(func():
		ball.queue_free()
		if not stats.dead and not p.stats.dead:
			_hit_player(30.0, "")
			p.stats.slow(4.0, 0.7))
	if humanoid:
		humanoid.anim.play_shot("attack1")


func _auto_attack() -> void:
	if data.has("ranged"):
		# Casters shoot a bolt instead of hitting (Frost Wisp: ice shard).
		var p := World.player
		Projectile.spell(global_position + Vector3(0, float(data.get("float", 1.0)), 0), p, String(data.get("element", "Ice")), func():
			if stats.dead or p.stats.dead:
				return
			var r := stats.roll_spell(p.stats, Rules.swing_power(stats.swing_time), String(data.get("element", "Ice")))
			p.stats.take_damage(r.amount, r.crit, stats))
		return
	_strike()
	if humanoid:
		humanoid.anim.play_shot(["attack1", "attack2", "attack3"][randi() % 3])
	_hit_player(Rules.swing_power(stats.swing_time), "")


## A creature's blow: its attack clip, or the procedural lunge.
func _strike() -> void:
	if _canim:
		_canim.shot("attack")
	else:
		_lunge = 1.0


func _hit_player(power: float, label: String) -> void:
	var p := World.player
	if p == null or p.stats.dead:
		return
	var r := stats.roll_damage(p.stats, power, label == "")
	p.stats.take_damage(r.amount, r.crit, stats)
	Audio.hit(hit_sound(), r.crit, -3.0)


## What this enemy's blows sound like: a humanoid's weapon (fists: a club's thud), a beast's
## claws or bite.
func hit_sound() -> String:
	if humanoid:
		return String(data.get("weapon", "club"))
	return "claw" if kind in ["bear", "scorpion", "crab"] else "bite"


## Champion modifiers in a fight (Oldworld2 world.md 3.1).
func _champion_process(t: float, dist: float) -> void:
	match modifier:
		"Burning":
			# A fire aura: the hero takes Fire damage every 3 s within 5 m.
			if dist < 5.0 and t >= _aura_at:
				_aura_at = t + 3.0
				var r := stats.roll_spell(World.player.stats, 20.0, "Fire")
				World.player.stats.take_damage(r.amount, r.crit, stats)
				World.float_text(World.player.global_position + Vector3(0, 2.4, 0), "Burning", Color(1, 0.5, 0.2), 32, World.player)
		"Shielded":
			# A shield absorbing a quarter of the health, renewed every 30 s.
			if t >= _shield_at:
				_shield_at = t + 30.0
				stats.absorb = roundi(stats.max_hp * 0.25)
				World.float_text(global_position + Vector3(0, 2.6, 0), "Shield", Color(0.7, 0.85, 1.0), 36, self)


## Winged champions and flying creatures dodge half of all melee hits.
func is_flying() -> bool:
	return data.get("flying", false) or modifier == "Winged"


func _on_damaged(amount: int, crit: bool, source: Combatant) -> void:
	_last_hurt = Combatant.now()
	if modifier == "Thorned" and source and source.body is Player and source.body.global_position.distance_to(global_position) < 4.0:
		# Thorns: 15% of melee damage goes back to the attacker.
		source.take_damage(maxi(1, amount * 15 / 100), false, stats)
	_flinch = 1.0
	World.float_text(global_position + Vector3(0, 1.8 * float(data.get("scale", 1.0)) if humanoid else 1.3, 0), str(amount) + ("!" if crit else ""), Color(1, 0.95, 0.4) if crit else Color(1, 1, 1), 64 if crit else 48, self)
	if state == State.IDLE:
		engage()
	if humanoid and randf() < 0.35:
		humanoid.anim.play_shot("hit")
	elif _canim and randf() < 0.5:
		_canim.shot("hit")


func _on_died(killer: Combatant) -> void:
	state = State.DEAD
	_base_scale = _model.scale
	_died_at = Combatant.now()
	nameplate.visible = false
	collision_layer = 0
	if humanoid:
		humanoid.anim.set_move("death")
	if _canim:
		_canim.die()
	if killer and killer.body is Player:
		(killer.body as Player).on_kill(self)


func _dead_process(t: float) -> void:
	var since := t - _died_at
	var fl: float = data.get("float", 0.0)
	if _visual and fl > 0.0:
		# Flying creatures drop out of the air, tumbling, land on their side and then shrink
		# away (a bat swarm scatters) instead of lying around.
		var fall := clampf(since / 0.7, 0.0, 1.0)
		_visual.position.y = lerpf(fl, 0.15, fall * fall)
		_visual.rotation.x = fall * 1.3
		_model.rotation.z = lerpf(0.0, PI / 2, fall)
		var gone := clampf((since - 2.0) / 1.2, 0.0, 1.0)
		_model.scale = _base_scale * maxf(0.001, 1.0 - gone)
	elif _visual and _canim == null and since < 1.0:
		# Creatures: the blow jerks the head up and the body hops, then the legs give and it
		# drops onto its side (falling faster and faster), bounces once and lies still.
		var side := 1.0 if (get_instance_id() % 2) == 0 else -1.0
		var r := clampf(since / 0.14, 0.0, 1.0)
		var f := clampf((since - 0.1) / 0.36, 0.0, 1.0)
		var b := clampf((since - 0.46) / 0.3, 0.0, 1.0)
		var bounce := sin(b * PI) * (1.0 - b) * 0.22
		_model.rotation.z = side * (PI / 2 * f * f - bounce)
		_model.rotation.x = -0.35 * sin(r * PI)
		_model.position.y = 0.1 * sin(r * PI) + 0.15 * f * f + bounce * 0.15
	# Corpses sink into the ground before they go (instead of vanishing on the spot).
	var sink := clampf((since - (CORPSE - 2.0)) / 2.0, 0.0, 1.0)
	if sink > 0.0:
		_model.position.y = (0.15 if _visual and _canim == null and fl <= 0.0 else 0.0) - sink * sink * 0.9
	if t - _died_at > CORPSE:
		visible = false
	if t - _died_at > RESPAWN and World.player.global_position.distance_to(home) > 60.0:
		_respawn()


func _process(dt: float) -> void:
	if _canim:
		_canim.tick(dt, global_position)


func _respawn() -> void:
	stats.revive()
	state = State.IDLE
	visible = true
	collision_layer = 2
	global_position = home + Vector3(0, 0.5, 0)
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	if _visual:
		_model.scale = _base_scale
		_visual.rotation.x = 0.0
	_howled = false
	_smoked = false
	if humanoid:
		humanoid.anim.set_move("idle")
	if _canim:
		_canim.reset()


func _animate(dt: float, speed: float) -> void:
	_lunge = maxf(0.0, _lunge - dt * 3.0)
	_flinch = maxf(0.0, _flinch - dt * 5.0)
	if humanoid:
		var st := "idle"
		var rate := 1.0
		if speed > 2.2:
			st = "run"
			rate = speed / float(CharAnimator.CLIP_SPEED.run)
		elif speed > 0.1:
			st = "walk"
			rate = speed / float(CharAnimator.CLIP_SPEED.walk)
		else:
			# Turning on the spot (facing the hero): shuffling steps.
			var turn := absf(angle_difference(_last_yaw, rotation.y)) / maxf(dt, 0.001)
			if turn > 0.8:
				st = "walk"
				rate = clampf(turn / 3.0, 0.4, 1.0) * 0.9
		_last_yaw = rotation.y
		if st == "idle" and state == State.CHASE:
			st = "ready"          # fighting: the combat stance
		humanoid.anim.set_move(st, rate)
		return
	if _canim:
		# Rigged creature: its clips. Turning on the spot (facing the hero) walks slowly.
		var turn := absf(angle_difference(_last_yaw, rotation.y)) / maxf(dt, 0.001)
		_last_yaw = rotation.y
		_canim.move(speed if speed > 0.1 or turn < 0.8 else 0.6)
		return
	# Creatures: a trot bob while moving, a lunge forward when biting, a flinch when hit.
	_phase += dt * speed * 2.2
	var moving := speed > 0.1
	var fl: float = data.get("float", 0.0)
	if fl > 0.0:
		_phase += dt * 2.0
		_visual.position.y = fl + sin(_phase) * 0.2
		_visual.rotation.y = PI + sin(_phase * 0.5) * 0.4
		return
	_visual.position.y = (absf(sin(_phase)) * 0.06) if moving else 0.0
	_visual.rotation.x = (sin(_phase * 2.0) * 0.04) if moving else 0.0
	_visual.position.z = -sin(_lunge * PI) * 0.45 + _flinch * 0.12
