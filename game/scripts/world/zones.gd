class_name ZoneManager
extends Node3D
## Loads zones around the hero (design/world.md, section 1): the hero's zone, and a neighbor as
## soon as the hero comes within LOAD_DIST of its border. Zones two cells away are unloaded.

const LOAD_DIST := 140.0

var world_seed := 1
var zones := {}              ## Vector2i -> Zone
var with_enemies := true
var streaming := true        ## false: never load neighbors (test runs)
var _current := Vector2i(999, 999)
var _pending := {}           ## Vector2i -> {zone, task}: zones being built on a worker thread

signal entered_zone(zone: Zone)
signal loading(text: String)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / Terrain.SIZE), roundi(p.z / Terrain.SIZE))


## The zone at `cell`, built now if needed (blocks; used for the start zone).
func ensure(cell: Vector2i) -> Zone:
	if zones.has(cell):
		return zones[cell]
	if _pending.has(cell):
		var pend: Dictionary = _pending[cell]
		WorkerThreadPool.wait_for_task_completion(pend.task)
		var z0: Zone = pend.zone
		for i in range(maxi(0, int(pend.step)), Zone.STEPS):
			z0.build_step(i)
		_pending.erase(cell)
		_attach(cell, z0)
		return z0
	var z := Zone.new()
	z.build(cell, world_seed, with_enemies)
	_attach(cell, z)
	return z


## Starts building the zone at `cell` on a worker thread (zones near the hero's borders), so
## crossing into new lands doesn't freeze the game. Nodes are created outside the scene tree
## there and attached on the main thread when done (see update).
func request(cell: Vector2i) -> void:
	if zones.has(cell) or _pending.has(cell):
		return
	var z := Zone.new()
	var task := WorkerThreadPool.add_task(z.compute.bind(cell, world_seed, with_enemies), false, "zone %s" % cell)
	_pending[cell] = {"zone": z, "task": task, "step": -1}


## Zones whose data is ready get their nodes built, one step per frame, then attached.
func _process(_dt: float) -> void:
	for cell: Vector2i in _pending.keys():
		var pend: Dictionary = _pending[cell]
		if int(pend.step) < 0:
			if not WorkerThreadPool.is_task_completed(pend.task):
				continue
			WorkerThreadPool.wait_for_task_completion(pend.task)
			pend.step = 0
		var z: Zone = pend.zone
		z.build_step(int(pend.step))
		pend.step = int(pend.step) + 1
		if int(pend.step) >= Zone.STEPS:
			_pending.erase(cell)
			_attach(cell, z)
		return          # at most one step per frame


func _attach(cell: Vector2i, z: Zone) -> void:
	add_child(z)
	zones[cell] = z
	for e in z.enemies:
		World.enemies.append(e)
	print("zone %s: %s (%s, difficulty %d), %d enemies" % [cell, z.zone_name, z.type, z.difficulty, z.enemies.size()])


func zone_at(p: Vector3) -> Zone:
	return zones.get(cell_of(p))


func height_at(x: float, z: float) -> float:
	var zn: Zone = zones.get(cell_of(Vector3(x, 0, z)))
	if zn == null:
		return 0.0
	return zn.terrain.height_at(x - zn.position.x, z - zn.position.z)


## Called every second or so with the hero's position.
func update(p: Vector3) -> void:
	var c := cell_of(p)
	var z := ensure(c)
	if c != _current:
		_current = c
		entered_zone.emit(z)
	# Neighbors near the borders.
	var l := z.to_local2(p)
	var half: float = Terrain.SIZE / 2
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var dist := half - (l.x * d.x + l.y * d.y)
		if dist < LOAD_DIST and streaming:
			request(c + d)
	# Unload zones far away.
	for k in zones.keys():
		var kc: Vector2i = k
		if maxi(absi(kc.x - c.x), absi(kc.y - c.y)) > 1:
			zones[kc].free_zone()
			zones.erase(kc)
