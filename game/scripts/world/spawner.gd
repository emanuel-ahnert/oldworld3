class_name Spawner
extends Node3D
## Places the Grassland's enemy groups (design/world.md, section 5): wolves at forest edges,
## boars on meadows, goblin camps and bandit camps (tent, fire) near roads. Groups keep 30 m
## apart, nothing spawns near the settlement, levels rise with the distance from it.

const MIN_GAP := 30.0
const SAFE := 60.0            ## no enemies this close to the settlement
const ELITE_SAFE := 170.0      ## elite groups only beyond this: the ring around the settlement is
                               ## for levelling on normal enemies first

var groups: Array = []        ## [{kind, pos, members}]


var zone: Zone


func generate(p_zone: Zone, seed: int, forest_noise: FastNoiseLite) -> void:
	zone = p_zone
	var terrain := zone.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 50
	var placed: Array[Vector3] = []
	var wanted: Dictionary = zone.info.enemies
	for kind in wanted:
		var made := 0
		var tries := 0
		while made < wanted[kind] and tries < 4000:
			tries += 1
			var x := rng.randf_range(-220, 220)
			var z := rng.randf_range(-220, 220)
			var d := Vector2(x, z).length()
			if d < (ELITE_SAFE if EnemyData.get_kind(kind).tier == "elite" else SAFE):
				continue
			if terrain.normal_at(x, z).y < 0.85 or terrain.lake_distance(x, z) < 5.0:
				continue
			var road := terrain.road_distance(x, z)
			var forest := forest_noise.get_noise_2d(x, z) * 0.5 + 0.5
			match kind:
				"crab":
					var cl := terrain.lake_distance(x, z)
					if cl < 5.0 or cl > 30.0:
						continue
				"sand_snake", "bat_swarm", "wind_spirit":
					if road < 10.0:
						continue
				"spider":
					# Spiders lurk deep in the woods.
					if forest < 0.62 or road < 12.0:
						continue
				"bear":
					if forest < 0.5 or road < 15.0:
						continue
				"wolf", "snow_wolf", "dire_wolf":
					if forest < 0.5 or forest > 0.66 or road < 10.0:
						continue
				"boar", "frost_wisp", "scorpion", "ember_spirit":
					if forest > 0.5 or road < 12.0:
						continue
				"ice_troll":
					if forest < 0.45 or road < 15.0:
						continue
				"goblin":
					# Goblin camps by the water (design/world.md).
					var ld := terrain.lake_distance(x, z)
					if forest > 0.6 or road < 20.0 or ld < 8.0 or ld > 30.0:
						continue
				"tomb_guardian":
					# Tomb guardians watch the pyramids (Oldworld2 world.md 2.3.4).
					if zone.landmarks.is_empty() or not zone.landmarks.any(func(q): return Vector2(x - q.x, z - q.z).length() < 72.0):
						continue
				"mummy", "scarab", "cobra":
					if forest > 0.55 or road < 10.0:
						continue
				"bandit", "berserker", "nomad", "corsair", "hoplite", "cultist", "vampire":
					if road < 14.0 or road > 40.0 or forest > 0.6:
						continue
			if zone.landmarks.any(func(q): return Vector2(x - q.x, z - q.z).length() < 50.0):
				continue
			var pos := Vector3(x, terrain.height_at(x, z), z)
			var ok := true
			for sh in Settlement.shrine_spots(terrain):
				if sh.distance_to(pos) < 25.0:
					ok = false
			for p in placed:
				if p.distance_to(pos) < MIN_GAP:
					ok = false
					break
			if not ok:
				continue
			placed.append(pos)
			_spawn_group(kind, pos, d, rng, terrain)
			made += 1
	_spawn_champion(rng, terrain, placed)
	if OS.get_cmdline_user_args().has("--spawn-report"):
		var near := 0
		var elite_d := 1e9
		for g in groups:
			var gd := Vector2(g.pos.x, g.pos.z).length()
			if EnemyData.get_kind(g.kind).tier == "elite":
				elite_d = minf(elite_d, gd)
			elif gd < ELITE_SAFE:
				near += 1
		print("SPAWN %s: %d normal groups within %d m, nearest elite group %d m" % [zone.info.get("name", zone.cell), near, ELITE_SAFE, elite_d])
	_place_chests(rng, terrain)


## Treasure chests: one beside an elite camp, one or two hidden in the woods (or in front of a
## pyramid in the Ancient Desert). Deterministic per zone; opened ones are saved by key.
func _place_chests(rng: RandomNumberGenerator, terrain: Terrain) -> void:
	var spots: Array[Vector3] = []
	for g in groups:
		if EnemyData.get_kind(g.kind).tier == "elite" and not g.has("champion"):
			spots.append(g.pos + Vector3(-4.0, 0, -3.5))
			break
	for c in zone.landmarks:
		var fwd := Vector3(-c.x, 0, -c.z).normalized()
		spots.append(c + fwd * 22.0)
		break
	var want := 3
	for tries in 1500:
		if spots.size() >= want:
			break
		var x := rng.randf_range(-215, 215)
		var z := rng.randf_range(-215, 215)
		var f := zone.scatter.forest.get_noise_2d(x, z) * 0.5 + 0.5
		if Vector2(x, z).length() < 90.0 or terrain.road_distance(x, z) < 25.0 or terrain.lake_distance(x, z) < 6.0:
			continue
		if terrain.normal_at(x, z).y < 0.9 or (zone.info.get("bushes", true) and f < 0.6):
			continue
		if zone.landmarks.any(func(q): return Vector2(x - q.x, z - q.z).length() < 50.0):
			continue
		spots.append(Vector3(x, 0, z))
	for i in spots.size():
		var sp := spots[i]
		var ch := Chest.new()
		ch.setup("%s:%d" % [Quests.key_of(zone.cell), i], 5 * zone.difficulty, terrain)
		ch.position = Vector3(sp.x, terrain.height_at(sp.x, sp.z), sp.z)
		ch.rotation.y = rng.randf() * TAU
		add_child(ch)
		zone.chests.append(ch)


const CHAMPION_NAMES := ["Gorran", "Vessa", "Mordrek", "Ilka", "Brann", "Sorvald", "Kesh", "Malva", "Dravic", "Oswin", "Thessa", "Rook"]
const CHAMPION_TITLES := ["the Cruel", "Ironhand", "the Red", "Bonecutter", "the Grim", "Blackheart", "the Butcher", "Two-Scars"]


## One named champion per zone (design/world.md, 7): the zone's elite kind, far from the
## settlement, a level above the zone's strongest enemies, with an orange marker on the map.
func _spawn_champion(rng: RandomNumberGenerator, terrain: Terrain, placed: Array[Vector3]) -> void:
	var kinds: Array = zone.info.enemies.keys().filter(func(k): return EnemyData.get_kind(k).tier == "elite")
	if kinds.is_empty():
		return
	var kind: String = kinds[0]
	for tries in 2000:
		var x := rng.randf_range(-210, 210)
		var z := rng.randf_range(-210, 210)
		if Vector2(x, z).length() < ELITE_SAFE + 20.0 or terrain.normal_at(x, z).y < 0.9 or terrain.lake_distance(x, z) < 8.0 or terrain.road_distance(x, z) < 12.0:
			continue
		if zone.landmarks.any(func(q): return Vector2(x - q.x, z - q.z).length() < 55.0):
			continue
		var pos := Vector3(x, terrain.height_at(x, z), z)
		if placed.any(func(p): return p.distance_to(pos) < MIN_GAP):
			continue
		var name := "%s %s" % [CHAMPION_NAMES[rng.randi() % CHAMPION_NAMES.size()], CHAMPION_TITLES[rng.randi() % CHAMPION_TITLES.size()]]
		var mods := ["Burning", "Swift", "Shielded", "Thorned", "Winged"]
		var e := Enemy.new()
		pos.y += 0.3
		e.setup(kind, 5 * zone.difficulty + 1, pos + zone.position, name, mods[rng.randi() % mods.size()])
		add_child(e)
		e.position = pos
		var g: Array[Enemy] = [e]
		e.group = g
		zone.enemies.append(e)
		groups.append({"kind": kind, "pos": pos, "members": [e], "champion": name})
		return


func _spawn_group(kind: String, center: Vector3, dist: float, rng: RandomNumberGenerator, terrain: Terrain) -> void:
	var data: Dictionary = EnemyData.get_kind(kind)
	var n := rng.randi_range(data.group.x, data.group.y)
	# Difficulty d: levels 5d-4 .. 5d, rising with the distance from the settlement; elites at
	# the top (design/world.md).
	var lo := 5 * zone.difficulty - 4
	var lvl := clampi(lo + int((dist - SAFE) / 45.0), lo, lo + 4)
	if data.tier == "elite":
		lvl = clampi(lvl + 1, lo + 1, lo + 4)
	var members: Array[Enemy] = []
	for i in n:
		var a := TAU * i / n + rng.randf() * 0.5
		var off := Vector3(cos(a), 0, sin(a)) * (2.5 if n > 1 else 0.0)
		var p := center + off
		p.y = terrain.height_at(p.x, p.z) + 0.3
		var e := Enemy.new()
		e.setup(kind, clampi(lvl + rng.randi_range(-1, 0), lo, lo + 4), p + zone.position)
		add_child(e)
		e.position = p
		members.append(e)
		zone.enemies.append(e)       # registered in World.enemies when the zone is attached
	for e in members:
		e.group = members
	if kind in ["bandit", "goblin", "berserker", "nomad", "corsair", "cultist"]:
		_camp(center, rng, terrain, kind != "goblin")
	groups.append({"kind": kind, "pos": center, "members": members})


## A small camp: a fire ring, and for bandits a tent and crates.
func _camp(center: Vector3, rng: RandomNumberGenerator, terrain: Terrain, tent: bool) -> void:
	var props := [["campfire", Vector3(0, 0, 0), 1.2]]
	if tent:
		props.append(["tent", Vector3(4.5, 0, -2.0), 3.2])
		props.append(["crate", Vector3(-3.0, 0, 2.5), 0.8])
		props.append(["crate", Vector3(-3.6, 0, 1.6), 0.7])
	for pr in props:
		var path := "res://assets/props/%s.glb" % pr[0]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = load(path).instantiate()
		add_child(n)
		var p: Vector3 = center + pr[1]
		Placement.put_on_ground(n, terrain, p, float(pr[2]), rng.randf() * TAU)
		if pr[0] != "campfire":
			Placement.add_box_collision(n)
