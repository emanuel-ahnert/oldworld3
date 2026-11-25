class_name Zone
extends Node3D
## One zone of the world grid (design/world.md): terrain, settlement, vegetation and enemies,
## all in zone-local coordinates; the node sits at the zone's place in the world.

var cell := Vector2i.ZERO
var type := "grassland"
var info: Dictionary
var difficulty := 1
var zone_name := ""
var terrain: Terrain
var settlement: Settlement
var scatter: Scatter
var spawner: Spawner
var enemies: Array[Enemy] = []
var chests: Array[Chest] = []
var landmarks: Array[Vector3] = []   ## pyramid groups (Ancient Desert), zone-local
var graveyards: Array[Vector3] = []  ## graveyards (Unholy lands), zone-local


var _seed := 0
var _with_enemies := true
const STEPS := 4


## Builds the whole zone at once (the start zone; blocks).
func build(p_cell: Vector2i, world_seed: int, with_enemies := true) -> void:
	compute(p_cell, world_seed, with_enemies)
	for i in STEPS:
		build_step(i)


## The data part: terrain heights, landmarks, where trees grow. No rendering objects are made
## here, so it runs on a worker thread while the game renders; making meshes and loading models
## on a worker deadlocked against the renderer compiling a new material (night log 42).
func compute(p_cell: Vector2i, world_seed: int, with_enemies := true) -> void:
	cell = p_cell
	type = ZoneTypes.type_at(cell, world_seed)
	info = ZoneTypes.TYPES[type]
	difficulty = ZoneTypes.difficulty(cell)
	position = Vector3(cell.x * Terrain.SIZE, 0, cell.y * Terrain.SIZE)
	var seed := hash([world_seed, cell.x, cell.y])
	zone_name = ZoneNames.make(info.names, seed)
	name = "Zone_%d_%d" % [cell.x, cell.y]

	_seed = seed
	_with_enemies = with_enemies
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.compute(seed, self, world_seed)
	landmarks = Settlement.landmark_spots(terrain, info, seed)
	scatter = Scatter.new()
	scatter.name = "Scatter"
	scatter.view_range = minf(World.view_range, float(info.get("view_range", 1000.0)))
	graveyards = Graveyard.spots(terrain, int(info.get("graveyards", 0)), seed)
	scatter.compute(terrain, seed, Settlement.shrine_spots(terrain), info, landmarks, graveyards)


## The node part, one step per frame on the main thread (ZoneManager): 0 terrain meshes,
## 1 settlement, 2 vegetation, 3 enemies.
func build_step(i: int) -> void:
	match i:
		0:
			add_child(terrain)
			terrain.build()
		1:
			settlement = Settlement.new()
			settlement.name = "Settlement"
			add_child(settlement)
			settlement.build(self, _seed)
		2:
			add_child(scatter)
			scatter.build()
		3:
			if _with_enemies:
				spawner = Spawner.new()
				spawner.name = "Spawner"
				add_child(spawner)
				spawner.generate(self, _seed, scatter.forest)


## World position -> this zone's local 2D position.
func to_local2(p: Vector3) -> Vector2:
	return Vector2(p.x - position.x, p.z - position.z)


func contains(p: Vector3) -> bool:
	var l := to_local2(p)
	return absf(l.x) <= Terrain.SIZE / 2 and absf(l.y) <= Terrain.SIZE / 2


func free_zone() -> void:
	for e in enemies:
		World.enemies.erase(e)
	queue_free()
