class_name Chest
extends Node3D
## A treasure chest (design/items.md, 7): walk up to it outside of combat and it opens: money,
## often a potion, often an item of the zone's level. Opened chests stay open (saved by key).
## The minimap shows chests within 40 m.

const OPEN_DIST := 2.4

var key := ""                  ## "x,z:i", unique per zone and chest
var level := 1
var opened := false
var _model: Node3D
var terrain: Terrain


func setup(p_key: String, p_level: int, p_terrain: Terrain) -> void:
	key = p_key
	level = p_level
	terrain = p_terrain


func _ready() -> void:
	opened = World.player != null and World.player.opened_chests.has(key)
	_show()


func _show() -> void:
	if _model:
		_model.queue_free()
	var path := "res://assets/props/chest_open.glb" if opened else "res://assets/props/chest.glb"
	if not ResourceLoader.exists(path):
		path = "res://assets/props/crate.glb"
	_model = load(path).instantiate()
	add_child(_model)
	# Scale to ~1.1 m wide, bottom on the ground.
	var box := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := 1.1 / maxf(maxf(box.size.x, box.size.z), 0.01)
	_model.scale = Vector3.ONE * s
	_model.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	for gi in _model.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 90.0


func _process(_dt: float) -> void:
	if opened:
		return
	var p := World.player
	if p == null:
		return
	if p.opened_chests.has(key):
		# Opened in an earlier session (the start zone is built before the save is applied).
		opened = true
		_show()
		return
	if p.stats.dead or p.stats.in_combat():
		return
	if p.global_position.distance_to(global_position) < OPEN_DIST:
		_open(p)


func _open(p: Player) -> void:
	opened = true
	p.opened_chests[key] = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cash := level * rng.randi_range(10, 20)
	p.money += cash
	var got := [Items.money_text(cash)]
	if rng.randf() < 0.5 and p.add_item(Items.POTION.duplicate(true)):
		got.append("Healing Potion")
	if rng.randf() < 0.7:
		var item := Items.generate(level, Items.roll_rarity("elite", rng), p.cls if rng.randf() < 0.6 else "", rng)
		if p.add_item(item):
			got.append(item.name)
	p.message.emit("Treasure! " + ", ".join(got))
	World.float_text(global_position + Vector3(0, 1.6, 0), "Treasure!", Color(1, 0.85, 0.3), 48)
	Audio.sfx("coins")
	p.inventory_changed.emit()
	p.saved_point.emit()
	_show()
