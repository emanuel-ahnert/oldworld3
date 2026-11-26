class_name ZoneManager
extends Node3D
## Loads zones around the hero (design/world.md, section 1): the hero's zone, and a neighbor as
## soon as the hero comes within LOAD_DIST of its border. Zones two cells away are unloaded.

const LOAD_DIST := 300.0       ## m from a border: the neighbor starts building (in the background)

var world_seed := 1
var zones := {}              ## Vector2i -> Zone
var with_enemies := true
var streaming := true        ## false: never load neighbors (test runs)
var _current := Vector2i(999, 999)
var _pending := {}           ## Vector2i -> {zone, task}: zones being built on a worker thread
var _staging: Array = []     ## [parent, child] still to add to an attached zone (a few per frame)
const ATTACH_BUDGET := 4.0   ## ms per frame for adding a zone's nodes

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
## crossing into new lands doesn't freeze the game: its data and all its nodes (terrain mesh,
## houses, vegetation, colliders, enemies) are made there, outside the scene tree; the main
## thread only attaches the finished zone (see _process). Building the nodes step by step on the
## main thread cost 0.4 s (terrain) and 0.85 s (vegetation) in single frames.
func request(cell: Vector2i) -> void:
	if zones.has(cell) or _pending.has(cell):
		return
	var z := Zone.new()
	var task := WorkerThreadPool.add_task(_build_off_thread.bind(z, cell), false, "zone %s" % cell)
	_pending[cell] = {"zone": z, "task": task, "step": Zone.STEPS}


func _build_off_thread(z: Zone, cell: Vector2i) -> void:
	z.compute(cell, world_seed, with_enemies)
	for i in Zone.STEPS:
		z.build_step(i)


## Finished zones are attached a little at a time: adding a whole zone at once cost 1.5 s in one
## frame (every collider registered, every enemy building its model). The zone goes in with its
## sections (terrain, settlement, vegetation, enemies) emptied; their nodes follow, ATTACH_BUDGET
## ms worth per frame. An enemy joins World.enemies when it is added.
func _process(_dt: float) -> void:
	Enemy.prepare_some(4.0)
	var t0 := Time.get_ticks_usec()
	var timing := OS.get_cmdline_user_args().has("--zone-timing")
	while not _staging.is_empty() and (Time.get_ticks_usec() - t0) / 1000.0 < ATTACH_BUDGET:
		var pc: Array = _staging.pop_front()
		var t1 := Time.get_ticks_usec()
		if is_instance_valid(pc[0]) and is_instance_valid(pc[1]):
			(pc[0] as Node).add_child(pc[1])
			if pc[1] is Enemy:
				World.enemies.append(pc[1])
		if timing and (Time.get_ticks_usec() - t1) > 8000:
			print("ZONE slow node %s: %.1f ms" % [(pc[1] as Node).name, (Time.get_ticks_usec() - t1) / 1000.0])
	if not _staging.is_empty():
		return
	for cell: Vector2i in _pending.keys():
		var pend: Dictionary = _pending[cell]
		if not WorkerThreadPool.is_task_completed(pend.task):
			continue
		WorkerThreadPool.wait_for_task_completion(pend.task)
		_pending.erase(cell)
		var z: Zone = pend.zone
		for section in z.get_children():
			if section == z.terrain:
				continue                  # the ground goes in at once: nobody may fall through it
			for c in section.get_children():
				section.remove_child(c)
				_staging.append([section, c])
		_attach(cell, z, false)
		if timing:
			print("ZONE %s attached, %d nodes to add" % [cell, _staging.size()])
		return


## At exit: nodes still waiting to be added, and zones still being built, are freed (otherwise
## they leaked: engine warnings on quitting).
func _exit_tree() -> void:
	for pc in _staging:
		if is_instance_valid(pc[1]) and not (pc[1] as Node).is_inside_tree():
			(pc[1] as Node).free()
	_staging.clear()
	for cell in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[cell].task)
		(_pending[cell].zone as Node).free()
	_pending.clear()


## The hero is somewhere no zone is attached yet. Returns true when it is there now (attached,
## its waiting nodes added); false while it is still being built on the worker (the hero then
## waits where he is: the main thread mustn't wait for the worker, which may need the main
## thread itself: that hung the game). Rare: zones start building 300 m before their border.
func ensure_here(p: Vector3) -> bool:
	var c := cell_of(p)
	if not zones.has(c):
		if not _pending.has(c):
			request(c)
			return false
		if not WorkerThreadPool.is_task_completed(_pending[c].task):
			return false
		WorkerThreadPool.wait_for_task_completion(_pending[c].task)
		var z: Zone = _pending[c].zone
		_pending.erase(c)
		_attach(c, z)
	while not _staging.is_empty():
		var pc: Array = _staging.pop_front()
		if is_instance_valid(pc[0]) and is_instance_valid(pc[1]):
			(pc[0] as Node).add_child(pc[1])
			if pc[1] is Enemy:
				World.enemies.append(pc[1])
	return true


func _attach(cell: Vector2i, z: Zone, with_enemies := true) -> void:
	add_child(z)
	zones[cell] = z
	if with_enemies:
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


## The water surface over a world point (NAN on dry land).
func water_level(x: float, z: float) -> float:
	var zn: Zone = zones.get(cell_of(Vector3(x, 0, z)))
	if zn == null:
		return NAN
	return zn.terrain.water_level(x - zn.position.x, z - zn.position.z)


## Called every second or so with the hero's position.
func update(p: Vector3) -> void:
	var c := cell_of(p)
	if not zones.has(c) and _pending.has(c):
		return                     # still building on the worker: never wait for it here (ensure_here)
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
