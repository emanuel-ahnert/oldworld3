class_name Scatter
extends Node3D
## Places trees, bushes and boulders on the terrain (design/world.md, section 3) as one
## MultiMeshInstance3D per kind and 64 m chunk, so far chunks can be culled and drop out of
## view. Trees get trunk collision.

const CHUNK := 64.0
var view_range := 160.0


## A new view range for the vegetation already placed.
func set_view(r: float) -> void:
	view_range = r
	for c in get_children():
		if c is MultiMeshInstance3D:
			(c as MultiMeshInstance3D).visibility_range_end = r

## kind -> {path, height range (m), sink (m), trunk radius (m, 0 = no collision)}
const KINDS := {
	"beech": {"path": "res://assets/nature/beech.glb", "h": Vector2(12.0, 17.0), "sink": 0.2, "trunk": 0.4},
	"linden": {"path": "res://assets/nature/linden.glb", "h": Vector2(10.0, 14.0), "sink": 0.3, "trunk": 0.45},
	"birch": {"path": "res://assets/nature/birch.glb", "h": Vector2(9.0, 14.0), "sink": 0.2, "trunk": 0.25},
	"oak": {"path": "res://assets/nature/oak.glb", "h": Vector2(8.0, 12.0), "sink": 0.5, "trunk": 0.8},
	"palm": {"path": "res://assets/nature/palm.glb", "h": Vector2(7.0, 11.0), "sink": 0.2, "trunk": 0.3},
	"cactus": {"path": "res://assets/nature/cactus.glb", "h": Vector2(3.0, 5.5), "sink": 0.3, "trunk": 0.35},
	"drybush": {"path": "res://assets/nature/drybush.glb", "h": Vector2(1.0, 1.8), "sink": 0.1, "trunk": 0.0},
	"olive": {"path": "res://assets/nature/olive.glb", "h": Vector2(5.0, 8.0), "sink": 0.2, "trunk": 0.4},
	"cypress": {"path": "res://assets/nature/cypress.glb", "h": Vector2(9.0, 14.0), "sink": 0.1, "trunk": 0.3},
	"lavender": {"path": "res://assets/nature/lavender.glb", "h": Vector2(0.6, 1.1), "sink": 0.05, "trunk": 0.0},
	"deadtree": {"path": "res://assets/nature/deadtree.glb", "h": Vector2(6.0, 10.0), "sink": 0.2, "trunk": 0.35},
	"darkpine": {"path": "res://assets/nature/darkpine.glb", "h": Vector2(11.0, 16.0), "sink": 0.2, "trunk": 0.35, "tint": Color(0.27, 0.34, 0.26)},
	"gravestone": {"path": "res://assets/props/gravestone.glb", "h": Vector2(0.8, 1.3), "sink": 0.1, "trunk": 0.0},
	"pine1": {"path": "res://assets/nature/pine1.glb", "h": Vector2(11.0, 17.0), "sink": 0.2, "trunk": 0.35},
	"pine2": {"path": "res://assets/nature/pine2.glb", "h": Vector2(7.0, 11.0), "sink": 0.2, "trunk": 0.25},
	"bush": {"path": "res://assets/nature/bush.glb", "h": Vector2(1.0, 1.8), "sink": 0.3, "trunk": 0.0},
	"deadbush": {"path": "res://assets/nature/shrub.glb", "h": Vector2(0.9, 1.5), "sink": 0.08, "trunk": 0.0, "tint": Color(0.3, 0.42, 0.27)},
	"boulder": {"path": "res://assets/nature/boulder.glb", "h": Vector2(0.8, 2.6), "sink": 0.25, "trunk": 0.0},
}

## How wide each model is at the ground (roots, low branches), as a fraction of its height
## (measured from the meshes). On a slope a wide base would hang in the air on the downhill side:
## the tree is sunk to the lowest point under it, or, when that is more than MAX_DROP m, a
## narrow-based tree of the zone grows there instead (or none).
const BASE := {"beech": 0.04, "linden": 0.05, "birch": 0.02, "oak": 0.37, "palm": 0.2, "cactus": 0.35,
	"olive": 0.1, "cypress": 0.02, "deadtree": 0.48, "darkpine": 0.06, "pine1": 0.34, "pine2": 0.4}
const MAX_DROP := 0.45

## Vegetation within x m of the camera is invisible, from y m on solid (dithered between).
const NEAR_FADE := Vector2(2.0, 5.5)

## Forest trees and how often each species is picked; the gnarled oak is the rare one.
const TREES := {"beech": 0.35, "linden": 0.3, "birch": 0.25, "oak": 0.1}

var counts := {}
var _eyes := false             ## eyes flare up in the bushes (Unholy lands, BushEyes)
var forest: FastNoiseLite      ## forest density noise (also used by the enemy spawner)
var _trees: Dictionary = TREES


## avoid: spots kept clear by 9 m (shrines); avoid_big: by 45 m (pyramid groups).
func generate(terrain: Terrain, seed: int, avoid: Array[Vector3] = [], info: Dictionary = {}, avoid_big: Array[Vector3] = []) -> void:
	compute(terrain, seed, avoid, info, avoid_big)
	build()


var _placed := {}     ## kind -> {chunk key -> [[Transform3D, height]]} (compute -> build)
var _trunks := []     ## [origin, height, trunk radius] for the colliders


## Where everything grows: data only, safe on a worker thread (see ZoneManager).
func compute(terrain: Terrain, seed: int, avoid: Array[Vector3] = [], info: Dictionary = {}, avoid_big: Array[Vector3] = [], clearings: Array[Vector3] = []) -> void:
	_trees = info.get("trees", TREES)
	var density: float = info.get("tree_density", 1.0)
	var bushes: bool = info.get("bushes", true)
	var bush_kind: Variant = info.get("bush_kind", "bush")    ## a kind, or {kind: weight}
	var bush_density: float = info.get("bush_density", 1.0)
	var forest_min: float = info.get("forest_min", 0.62)       ## forest noise above this grows trees
	_eyes = info.get("eyes", false)
	forest = FastNoiseLite.new()
	forest.seed = seed + 10
	forest.frequency = 1.0 / 90.0
	forest.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 11
	var placed := {}  # kind -> {chunk key -> Array[Transform3D]}
	for kind in KINDS:
		placed[kind] = {}
	_placed = placed
	_trunks.clear()

	var half := Terrain.SIZE / 2 - 4.0
	var step := 3.0
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-1.4, 1.4)
			var pz := z + rng.randf_range(-1.4, 1.4)
			x += step
			var d := Vector2(px, pz).length()
			if d < Terrain.PLAZA_RADIUS + 18.0:
				continue
			if terrain.road_distance(px, pz) < Terrain.ROAD_WIDTH + 2.0:
				continue
			if terrain.lake_distance(px, pz) < 4.0:
				continue
			var blocked := false
			for q in avoid:
				if Vector2(px - q.x, pz - q.z).length() < 9.0:
					blocked = true
			for q in avoid_big:
				if Vector2(px - q.x, pz - q.z).length() < 45.0:
					blocked = true
			for q in clearings:
				if Vector2(px - q.x, pz - q.z).length() < Graveyard.CLEARING:
					blocked = true
			if blocked:
				continue
			if terrain.normal_at(px, pz).y < 0.8:
				continue
			var edge := maxf(absf(px), absf(pz))
			var f := forest.get_noise_2d(px, pz) * 0.5 + 0.5
			f = maxf(f, smoothstep(Terrain.HALF - 51.0, Terrain.HALF - 21.0, edge))   # forest band toward the border
			var r := rng.randf()
			var kind := ""
			if f > forest_min and r < (f - forest_min) * 1.6 * density:
				kind = _pick_tree(rng.randf())
			elif bushes and r < (0.012 + f * 0.03) * bush_density:
				kind = bush_kind if bush_kind is String else _pick(bush_kind, rng.randf())
			elif r > 0.995:
				kind = "boulder"
			if kind == "":
				continue
			var key := Vector2i(floori(px / CHUNK), floori(pz / CHUNK))
			if not placed[kind].has(key):
				placed[kind][key] = []
			var spec: Dictionary = KINDS[kind]
			var hgt := rng.randf_range(spec.h.x, spec.h.y)
			var ground := terrain.height_at(px, pz)
			var drop := _drop(terrain, px, pz, ground, float(BASE.get(kind, 0.0)) * hgt)
			if drop > MAX_DROP:
				# Too steep for this tree's wide base: the narrowest tree of the zone, if it fits.
				var alt := _narrowest()
				if alt == "" or alt == kind:
					continue
				kind = alt
				spec = KINDS[kind]
				hgt = rng.randf_range(spec.h.x, spec.h.y)
				drop = _drop(terrain, px, pz, ground, float(BASE.get(kind, 0.0)) * hgt)
				if drop > MAX_DROP:
					continue
				key = Vector2i(floori(px / CHUNK), floori(pz / CHUNK))
				if not placed[kind].has(key):
					placed[kind][key] = []
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, ground - spec.sink - drop, pz))
			placed[kind][key].append([t, hgt])
			if spec.trunk > 0.0:
				_trunks.append([t.origin, hgt, float(spec.trunk)])
		z += step


## Multimeshes and colliders from compute()'s data: on the main thread.
func build() -> void:
	var placed := _placed
	var colliders := StaticBody3D.new()
	colliders.name = "TreeCollision"
	add_child(colliders)
	# Canopies only stop the camera (layer 8), so it doesn't end up inside the foliage.
	var canopies := StaticBody3D.new()
	canopies.name = "CanopyCollision"
	canopies.collision_layer = 8
	canopies.collision_mask = 0
	add_child(canopies)
	for tr: Array in _trunks:
		var origin: Vector3 = tr[0]
		var hgt: float = tr[1]
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = tr[2]
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = origin + Vector3(0, 2.0, 0)
		colliders.add_child(cs)
		var cc := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = hgt * 0.28
		cc.shape = sph
		cc.position = origin + Vector3(0, hgt * 0.62, 0)
		canopies.add_child(cc)
	for kind in KINDS:
		var spec: Dictionary = KINDS[kind]
		if not ResourceLoader.exists(spec.path):
			push_warning("scatter: missing %s" % spec.path)
			continue
		var model := _load_mesh(spec.path, spec.get("tint", Color.WHITE))
		if model.is_empty():
			continue
		var mesh: Mesh = model.mesh
		var aabb: AABB = model.aabb
		counts[kind] = 0
		for key in placed[kind]:
			var list: Array = placed[kind][key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for k in list.size():
				var t: Transform3D = list[k][0]
				var s: float = list[k][1] / aabb.size.y
				# Scale to the wanted height and put the model's bottom on the ground.
				var local := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s))
				mm.set_instance_transform(k, t * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = view_range
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.name = "%s_%d_%d" % [kind, key.x, key.y]
			add_child(mmi)
			counts[kind] += list.size()
	if _eyes and placed.has("deadbush"):
		var eyes := BushEyes.new()
		eyes.name = "BushEyes"
		for key in placed["deadbush"]:
			for it: Array in placed["deadbush"][key]:
				eyes.spots.append([(it[0] as Transform3D).origin, it[1]])
		add_child(eyes)


## First mesh of a glTF scene and its bounds. Generated models are a single mesh on an
## untransformed node, so the node transform is ignored.
func _load_mesh(path: String, tint := Color.WHITE) -> Dictionary:
	var scene: Node3D = load(path).instantiate()
	var found := scene.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		scene.free()
		return {}
	var mi: MeshInstance3D = found[0]
	var mesh := mi.mesh
	var aabb := mesh.get_aabb()
	scene.free()
	# Every material a copy: recolored by `tint` (e.g. the Unholy pines came out frosty), and
	# dithered out close to the camera (gone within NEAR_FADE.x m, solid from NEAR_FADE.y m), so
	# a camera pushed into a crown sees through the branches instead of a dark wall of them.
	mesh = mesh.duplicate()
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is BaseMaterial3D:
			var c := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			if tint != Color.WHITE:
				c.albedo_color = c.albedo_color * tint
			c.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			c.distance_fade_min_distance = NEAR_FADE.x
			c.distance_fade_max_distance = NEAR_FADE.y
			mesh.surface_set_material(i, c)
	return {"mesh": mesh, "aabb": aabb}


func _pick(weights: Dictionary, r: float) -> String:
	var acc := 0.0
	for k in weights:
		acc += float(weights[k])
		if r < acc:
			return k
	return weights.keys()[-1]


## How far the ground falls below `ground` (at the middle) within `radius` m: 8 points on the
## circle and 4 halfway.
func _drop(terrain: Terrain, x: float, z: float, ground: float, radius: float) -> float:
	if radius < 0.3:
		return 0.0
	var low := ground
	for k in 12:
		var r := radius if k < 8 else radius * 0.5
		var a := TAU * k / (8.0 if k < 8 else 4.0)
		low = minf(low, terrain.height_at(x + cos(a) * r, z + sin(a) * r))
	return ground - low


## The zone's tree with the narrowest base ("" without trees).
func _narrowest() -> String:
	var best := ""
	for k in _trees:
		if best == "" or float(BASE.get(k, 0.0)) < float(BASE.get(best, 0.0)):
			best = k
	return best


func _pick_tree(r: float) -> String:
	for kind in _trees:
		if r < float(_trees[kind]):
			return kind
		r -= float(_trees[kind])
	return _trees.keys()[0]
