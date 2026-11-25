class_name Game
extends RefCounted
## Game state between scenes and the autosave (design/game-design.md, section 8;
## design/tech-stack.md, section 6): one save in user://save/, written when something changed.

const SAVE_DIR := "user://save"
const SAVE_FILE := "user://save/hero.json"

const DEFAULT_SEED := 42
static var seed := DEFAULT_SEED
static var start_type := "grassland"      ## the zone type a new game starts in (title screen)
static var home := Vector2i.ZERO          ## the start zone (difficulty 1)
static var cls := "warrior"              ## the hero's class for a new game
static var loaded: Dictionary = {}      ## save data to apply when the world starts ({} = new game)


## Quits the game. A tooltip still open at exit leaves its popup's signal connections behind
## (engine errors on stdout): the root viewport is told the mouse left, which closes it.
static func quit(tree: SceneTree) -> void:
	tree.root.notification(Viewport.NOTIFICATION_VP_MOUSE_EXIT)
	tree.quit()


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_FILE)


static func read_save() -> Dictionary:
	if not has_save():
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	return d if d is Dictionary else {}


## Writes the hero's state; a temp file renamed over the old one, so a crash can't corrupt it.
static func write_save(p: Player) -> void:
	if p == null:
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var d := {
		"version": 1, "seed": seed, "class": p.cls, "home": [home.x, home.y],
		"level": p.stats.level, "xp": p.xp, "money": p.money,
		"bag": p.bag, "equipped": p.equipped, "kit": p.kit_given, "tips": p.tips_shown.keys(), "quests": p.quests.to_save(), "visited": p.visited.keys(), "chests": p.opened_chests.keys(),
		"time": DayNight.instance.time if DayNight.instance else 0.3,
		"hp": p.stats.hp, "loadout": p.loadout, "passives": p.passive_loadout,
		"pos": [p.global_position.x, p.global_position.y, p.global_position.z],
		"yaw": p.rotation.y,
		"checkpoint": [p.checkpoint.x, p.checkpoint.y, p.checkpoint.z],
	}
	var tmp := SAVE_FILE + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_FILE))


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FILE))
