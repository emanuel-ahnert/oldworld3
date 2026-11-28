class_name ZoneTypes
extends RefCounted
## Zone types (design/world.md, section 2): ground textures, trees, enemies, buildings, music,
## names and light per type. Grassland in the middle, the North beyond it (Oldworld2's grid).

const TYPES := {
	"grassland": {
		"clouds": 0.5,
		"name": "Grassland",
		"ground": {"grass": "res://assets/terrain/grass.png", "dirt": "res://assets/terrain/dirt.png", "rock": "res://assets/terrain/cliff.png", "rock_top": "res://assets/terrain/cliff_top.png"},
		"ground_tint": Color(1, 1, 1), "snow": 0.0, "snow_line": 82.0,
		"trees": {"beech": 0.35, "linden": 0.3, "birch": 0.25, "oak": 0.1},
		"bushes": true,
		"enemies": {"wolf": 12, "boar": 10, "spider": 6, "bear": 5, "goblin": 6, "bandit": 6},
		"inn": "res://assets/buildings/inn.glb", "houses": ["res://assets/buildings/house1.glb", "res://assets/buildings/house2.glb"],
		"music": "grassland", "village_music": "village", "names": "grassland",
		"fog": Color(0.66, 0.77, 0.9), "sun": Color(1.0, 0.95, 0.85), "frozen_lakes": false,
		"rock_tint": Color(1.06, 0.94, 0.8), "rock_moss": Color(0.3, 0.42, 0.15, 0.6),
	},
	"north": {
		"clouds": 0.55,
		"name": "North",
		"ground": {"grass": "res://assets/terrain/snow.png", "dirt": "res://assets/terrain/dirt.png", "rock": "res://assets/terrain/cliff.png", "rock_top": "res://assets/terrain/cliff_top.png"},
		"ground_tint": Color(1, 1, 1), "snow": 1.0, "snow_line": 40.0,
		"trees": {"pine1": 0.6, "pine2": 0.4},
		"bushes": false,
		"enemies": {"snow_wolf": 14, "frost_wisp": 8, "ice_troll": 6, "berserker": 6},
		"inn": "res://assets/buildings/longhouse.glb", "houses": ["res://assets/buildings/longhouse.glb"],
		"music": "north", "village_music": "hall", "names": "north",
		"fog": Color(0.76, 0.84, 0.95), "sun": Color(0.94, 0.96, 1.0), "frozen_lakes": true,
		"rock_tint": Color(0.86, 0.93, 1.08),
		"road_tint": Color(0.46, 0.47, 0.5, 0.12),   # roads: dark grey gravel and trodden snow, not brown
	},
	"desert": {
		"clouds": 0.0,
		"name": "Desert",
		"ground": {"grass": "res://assets/terrain/sand.png", "dirt": "res://assets/terrain/sandpath.png", "rock": "res://assets/terrain/desertrock.png"},
		"ground_tint": Color(1, 1, 1), "snow": 1.0, "tree_density": 0.3,
		"trees": {"palm": 0.45, "cactus": 0.35, "drybush": 0.2},
		"bushes": false,
		"enemies": {"sand_snake": 12, "scorpion": 12, "ember_spirit": 8, "nomad": 6},
		"inn": "res://assets/buildings/sandinn.glb", "houses": ["res://assets/buildings/domehouse.glb"],
		"music": "desert", "village_music": "oasis", "names": "desert",
		"fog": Color(0.92, 0.84, 0.7), "distance_fog": false, "sun": Color(1.0, 0.92, 0.78), "frozen_lakes": false,
		"sky": [Color(0.3, 0.52, 0.85), Color(0.9, 0.82, 0.68)],
	},
	"ancient": {
		"clouds": 0.0,
		"name": "Ancient Desert",
		"ground": {"grass": "res://assets/terrain/sand.png", "dirt": "res://assets/terrain/sandpath.png", "rock": "res://assets/terrain/desertrock.png"},
		"ground_tint": Color(1, 0.97, 0.9), "snow": 1.0, "tree_density": 0.15,
		"trees": {"palm": 0.7, "drybush": 0.3},
		"bushes": false,
		"enemies": {"scarab": 10, "cobra": 10, "mummy": 10, "tomb_guardian": 5},
		"inn": "res://assets/buildings/temple.glb", "houses": ["res://assets/buildings/mudhouse.glb"],
		"landmarks": true,
		"music": "ancient", "village_music": "oasis", "names": "ancient",
		"fog": Color(0.95, 0.86, 0.68), "distance_fog": false, "sun": Color(1.0, 0.9, 0.72), "frozen_lakes": false,
		"sky": [Color(0.28, 0.5, 0.85), Color(0.95, 0.85, 0.65)],
	},
	"mediterranean": {
		"clouds": 0.34,
		"name": "Mediterranean",
		"ground": {"grass": "res://assets/terrain/med_grass.png", "dirt": "res://assets/terrain/med_path.png", "rock": "res://assets/terrain/cliff.png", "rock_top": "res://assets/terrain/cliff_top.png"},
		"ground_tint": Color(1, 1, 1), "snow": 0.5, "bare": 0.7, "tree_density": 0.6,
		"trees": {"olive": 0.55, "cypress": 0.45},
		"bushes": true, "bush_kind": "lavender",
		"enemies": {"crab": 10, "wind_spirit": 8, "corsair": 6, "hoplite": 6},
		"inn": "res://assets/buildings/villa.glb", "houses": ["res://assets/buildings/whitehouse.glb", "res://assets/buildings/villa.glb"],
		"grime": 1.0,         # the whitewashed houses came out spotless: weathered hard (Placement.weather)
		"distance_fog": false,  # clear Mediterranean air, like the deserts
		"music": "mediterranean", "village_music": "harbor", "names": "mediterranean",
		"fog": Color(0.72, 0.82, 0.94), "sun": Color(1.0, 0.95, 0.84), "frozen_lakes": false,
		"rock_tint": Color(1.12, 1.0, 0.8), "rock_moss": Color(0.42, 0.44, 0.2, 0.35),
	},
	"unholy": {
		"clouds": 0.75, "cloud_tint": Color(0.55, 0.55, 0.6),
		"name": "Unholy lands",
		"ground": {"grass": "res://assets/terrain/unholy_grass.png", "dirt": "res://assets/terrain/unholy_path.png", "rock": "res://assets/terrain/cliff.png", "rock_top": "res://assets/terrain/cliff_top.png"},
		# A dark, dense, misty forest with a sickly green hue; eyes flare up in the bushes
		# (BushEyes). grass_tint: color the grass is pulled toward, alpha = how far.
		"ground_tint": Color(1, 1, 1), "grass_tint": Color(0.4, 0.45, 0.33, 0.35), "snow": 0.5, "bare": 0.9, "tree_density": 1.5, "forest_min": 0.52, "view_range": 105.0,
		"trees": {"deadtree": 0.4, "darkpine": 0.6},
		"bushes": true, "bush_kind": "deadbush", "bush_density": 2.5, "eyes": true,
		"graveyards": 5,      # fenced graveyards with a crypt (Graveyard), not stones in the woods
		"enemies": {"dire_wolf": 14, "bat_swarm": 10, "cultist": 3, "cultist_zealot": 2, "vampire": 6},
		"inn": "res://assets/buildings/gothichouse.glb", "houses": ["res://assets/buildings/gothichouse.glb", "res://assets/buildings/crypt.glb"],
		"music": "unholy", "village_music": "chapel", "names": "unholy",
		"fog": Color(0.34, 0.37, 0.33), "fog_density": 0.011, "fog_end": 170.0, "sun": Color(0.8, 0.88, 0.66), "sun_energy": 0.68, "frozen_lakes": false,
		"sky": [Color(0.16, 0.12, 0.2), Color(0.36, 0.42, 0.3)],
		"rock_tint": Color(0.86, 0.78, 0.95), "rock_moss": Color(0.3, 0.38, 0.16, 0.45),
		"night_fog": Color(0.1, 0.15, 0.11), "night_sky": [Color(0.02, 0.05, 0.03), Color(0.07, 0.12, 0.08)],
	},
}


## Type of the zone at grid cell (cx, cz): the start is Grassland; going north leads to the North
## (Oldworld2: the larger offset decides the direction; the first ring stays Grassland with 30%
## chance); south leads to the Desert (Middle Eastern or Ancient), east to the Unholy lands,
## west to the Mediterranean.
static func type_at(cell: Vector2i, seed: int) -> String:
	if cell == Vector2i.ZERO:
		return "grassland"
	var vertical := absi(cell.y) >= absi(cell.x)
	var ring := maxi(absi(cell.x), absi(cell.y))
	var r := float(absi(hash([seed, cell.x, cell.y, 77])) % 1000) / 1000.0
	var stay := 0.3 if ring == 1 else (0.15 if ring == 2 else 0.05)
	if r < stay:
		return "grassland"
	if vertical:
		if cell.y < 0:
			return "north"
		# A desert zone is the Middle Eastern or the Ancient (Egyptian) Desert; smooth noise over
		# the grid makes neighbors usually share the theme (Oldworld2, world.md 2.3.2).
		var n := FastNoiseLite.new()
		n.seed = seed + 404
		n.frequency = 0.35
		return "ancient" if n.get_noise_2d(cell.x, cell.y) > 0.0 else "desert"
	return "unholy" if cell.x > 0 else "mediterranean"


## The zone the hero started in (difficulty 1); difficulty rises by one per ring around it
## (Oldworld2: the chosen start zone is difficulty 1).
static var home := Vector2i.ZERO

const START_TYPES := ["grassland", "north", "desert", "ancient", "mediterranean", "unholy"]


static func difficulty(cell: Vector2i) -> int:
	return 1 + maxi(absi(cell.x - home.x), absi(cell.y - home.y))


## The zone of this type closest to the world's center (by ring, then from the north
## clockwise), where a new game of that start type begins.
static func nearest(type: String, seed: int) -> Vector2i:
	for r in 13:
		for cell in _ring(r):
			if type_at(cell, seed) == type:
				return cell
	return Vector2i.ZERO


static func _ring(r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if r == 0:
		out.append(Vector2i.ZERO)
		return out
	for x in range(-r, r + 1):
		out.append(Vector2i(x, -r))
	for y in range(-r + 1, r + 1):
		out.append(Vector2i(r, y))
	for x in range(r - 1, -r - 1, -1):
		out.append(Vector2i(x, r))
	for y in range(r - 1, -r, -1):
		out.append(Vector2i(-r, y))
	return out
