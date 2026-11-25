class_name Settlement
extends Node3D
## The zone's settlement and road shrines (design/world.md, section 3): the inn north of the
## plaza, houses around it (clear of the roads), a well on the plaza, and a checkpoint shrine
## halfway along each long road. The inn and shrines are checkpoints: coming close outside of
## combat makes one the respawn point and heals fully.

const CHECK_RADIUS := 6.0

var _at_inn := false
var checkpoints: Array[Dictionary] = []     ## {name, pos, spawn}
var _active := -1


## Shrine spots, computed before vegetation so trees keep clear of them.
static func shrine_spots(terrain: Terrain) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for pts in terrain.roads:
		var total := 0.0
		for k in pts.size() - 1:
			total += pts[k].distance_to(pts[k + 1])
		if total < 180.0:
			continue
		var half := total * 0.5
		for k in pts.size() - 1:
			var seg := pts[k].distance_to(pts[k + 1])
			if half <= seg:
				var p := pts[k].lerp(pts[k + 1], half / seg)
				var dir := (pts[k + 1] - pts[k]).normalized()
				var side := Vector2(-dir.y, dir.x) * 7.0
				var s := p + side
				out.append(Vector3(s.x, terrain.height_at(s.x, s.y), s.y))
				break
			half -= seg
	return out


## Ancient Desert landmarks (Oldworld2 world.md 2.3.4): two pyramid groups 70–180 m from the
## settlement, clear of roads, lakes and each other. Computed before vegetation and enemies.
static func landmark_spots(terrain: Terrain, info: Dictionary, seed: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not info.get("landmarks", false):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 90
	for tries in 600:
		var a := rng.randf() * TAU
		var d := rng.randf_range(70.0, 180.0)
		var x := sin(a) * d
		var z := cos(a) * d
		if terrain.road_distance(x, z) < 34.0 or terrain.lake_distance(x, z) < 30.0 or terrain.normal_at(x, z).y < 0.93:
			continue
		var p := Vector3(x, terrain.height_at(x, z), z)
		if out.any(func(q): return q.distance_to(p) < 120.0):
			continue
		if shrine_spots(terrain).any(func(q): return q.distance_to(p) < 40.0):
			continue
		out.append(p)
		if out.size() >= 2:
			break
	return out


func build(zone: Zone, seed: int) -> void:
	var terrain := zone.terrain
	var origin := zone.position
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 70
	# The inn north of the plaza, its front toward the plaza center.
	var inn_pos := Vector3(0, 0, -30)
	_place(zone.info.inn, terrain, inn_pos, 13.0 if zone.type == "grassland" else 18.0, 0.0)
	checkpoints.append({"name": "the inn", "pos": inn_pos + origin, "spawn": Vector3(0, 0, -16) + origin})
	# Houses on a ring around the plaza, not on roads and not in front of the inn.
	var houses: Array = zone.info.houses
	var placed := 0
	for i in 12:
		var a := TAU * i / 12.0 + 0.2
		var p := Vector3(sin(a) * 31.0, 0, -cos(a) * 31.0)
		if terrain.road_distance(p.x, p.z) < 11.0 or p.distance_to(inn_pos) < 15.0:
			continue
		var yaw := atan2(p.x, p.z) + PI        # face the plaza
		_place(houses[placed % houses.size()], terrain, p, rng.randf_range(8.5, 10.0) * (1.4 if zone.type == "north" else 1.0), yaw)
		placed += 1
		if placed >= 5:
			break
	# The inn's notice board (quests) and the merchant's stall, on the plaza in front of the inn.
	_place("res://assets/props/noticeboard.glb", terrain, Vector3(-9, 0, -19), 2.6, PI / 2, true)
	_place("res://assets/props/stall.glb", terrain, Vector3(11, 0, -17), 4.0, -0.4)
	# Village people: the merchant beside the stall, two villagers strolling over the plaza.
	var people := [["merchant", Vector3(8.0, 0, -18.5), false], ["villager", Vector3(-5, 0, -3), true], ["villager2", Vector3(4, 0, 5), true]]
	for i in people.size():
		var pp: Array = people[i]
		if not ResourceLoader.exists("res://assets/characters/%s/%s_color.png" % [pp[0], pp[0]]):
			continue
		var v := Villager.new()
		v.setup(pp[0], pp[1], terrain, pp[2], seed + i)
		add_child(v)
	if ResourceLoader.exists("res://assets/props/well.glb"):
		_place("res://assets/props/well.glb", terrain, Vector3(6, 0, -6), 3.0, 0.3)
	for s in shrine_spots(terrain):
		_place("res://assets/buildings/shrine.glb", terrain, s, 2.8, rng.randf() * TAU, true)
		checkpoints.append({"name": "the shrine", "pos": s + origin, "spawn": s + Vector3(2.5, 0, 0) + origin})
	for i in zone.graveyards.size():
		Graveyard.build(self, terrain, zone.graveyards[i], seed + 300 + i)
	if zone.info.get("landmarks", false):
		# Two obelisks in front of the temple (inn); each pyramid group: a big pyramid facing the
		# settlement, two small ones beside it, a pharaoh statue or a sphinx in front.
		const A := "res://assets/props/ancient/"
		for x in [-13.0, 13.0]:
			_place(A + "obelisk.glb", terrain, Vector3(x, 0, -19), 6.0, 0.0, true)
		for i in zone.landmarks.size():
			var c: Vector3 = zone.landmarks[i]
			var yaw := atan2(-c.x, -c.z)          # the entrance (+Z of the model) toward the settlement
			var fwd := Vector3(sin(yaw), 0, cos(yaw))
			var side := Vector3(fwd.z, 0, -fwd.x)
			_place(A + "pyramid.glb", terrain, c, 38.0, yaw)
			_place(A + "pyramid.glb", terrain, c + side * 31.0 - fwd * 6.0, 16.0, yaw)
			_place(A + "pyramid.glb", terrain, c - side * 31.0 - fwd * 6.0, 16.0, yaw)
			if i == 0 or not ResourceLoader.exists(A + "statue.glb"):
				_place(A + "sphinx.glb", terrain, c + fwd * 32.0, 10.0, yaw)
			else:
				_place(A + "statue.glb", terrain, c + fwd * 28.0, 5.0, yaw, true)


func _place(path: String, terrain: Terrain, pos: Vector3, size: float, yaw: float, by_height := false) -> void:
	if not ResourceLoader.exists(path):
		return
	var n: Node3D = load(path).instantiate()
	add_child(n)
	Placement.put_on_ground(n, terrain, pos, size, yaw, by_height, 0.15)
	Placement.add_box_collision(n)


func _process(_dt: float) -> void:
	var p := World.player
	if p == null or p.stats.dead:
		return
	# The inn's merchant: buy and sell in the bags window (B) while close to the inn.
	# The notice board: quests are handed in and taken on when arriving at the inn.
	var near_inn := not checkpoints.is_empty() and p.global_position.distance_to(checkpoints[0].pos) < 24.0
	if near_inn:
		if p.merchant_until < Combatant.now():
			p.message.emit("Merchant: open your bags (B) to buy and sell")
		p.merchant_until = Combatant.now() + 0.5
		if not _at_inn:
			p.visit_inn(get_parent() as Zone)
	_at_inn = near_inn
	if p.stats.in_combat():
		return
	for i in checkpoints.size():
		var c: Dictionary = checkpoints[i]
		if p.global_position.distance_to(c.pos) < CHECK_RADIUS + (6.0 if c.name == "the inn" else 0.0):
			if p.stats.hp < p.stats.max_hp:
				p.stats.hp = p.stats.max_hp
			if _active != i:
				_active = i
				var sp: Vector3 = c.spawn
				p.checkpoint = Vector3(sp.x, World.height_at(sp.x, sp.z) + 0.3, sp.z)
				p.message.emit("Checkpoint: %s" % c.name)
				Audio.sfx("heal")
				p.saved_point.emit()
