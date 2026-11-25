class_name Clutter
extends Node3D
## Ground clutter around the hero (WoW style): small grass tufts, a few flowers and pebbles in
## 12 m chunks within `radius`, built as the hero moves (at most two chunks per frame) and
## dropped behind. Placement is fixed per chunk (seeded by its coordinates). Nothing on roads,
## water, the village plaza or steep slopes. The amount follows the graphics quality
## (GameMenu.QUALITY: few on Low and Medium, many on High); instances shrink away at the edge.

const CHUNK := 12.0

## Per zone type: tuft color (as the terrain shader shows the grass), tufts / flowers / pebbles
## per chunk at density 1, flower colors, pebble color.
const LOOKS := {
	"grassland": {"tuft": Color(0.215, 0.33, 0.112), "tufts": 150, "flowers": 8, "pebbles": 6,
		"blossoms": [Color(0.95, 0.95, 0.9), Color(0.95, 0.82, 0.25), Color(0.6, 0.45, 0.85)], "pebble": Color(0.42, 0.4, 0.37)},
	"mediterranean": {"tuft": Color(0.37, 0.38, 0.163), "tufts": 110, "flowers": 5, "pebbles": 14,
		"blossoms": [Color(0.85, 0.2, 0.15), Color(0.95, 0.9, 0.8)], "pebble": Color(0.6, 0.56, 0.5)},
	"unholy": {"tuft": Color(0.23, 0.235, 0.16), "tufts": 130, "flowers": 0, "pebbles": 12,
		"blossoms": [], "pebble": Color(0.33, 0.34, 0.31)},
	"north": {"tuft": Color(0.45, 0.4, 0.28), "tufts": 6, "flowers": 0, "pebbles": 5,
		"blossoms": [], "pebble": Color(0.45, 0.46, 0.5)},
	"desert": {"tuft": Color(0.55, 0.45, 0.27), "tufts": 6, "flowers": 0, "pebbles": 14,
		"blossoms": [], "pebble": Color(0.6, 0.5, 0.38)},
	"ancient": {"tuft": Color(0.55, 0.45, 0.27), "tufts": 5, "flowers": 0, "pebbles": 14,
		"blossoms": [], "pebble": Color(0.62, 0.52, 0.4)},
}

static var radius := 22.0
static var density := 0.6
static var instance: Clutter

var _chunks := {}            ## Vector2i -> Node3D
var _mats := {}
var _meshes := {}


func _ready() -> void:
	instance = self
	_meshes = {"tuft": _tuft_mesh(), "flower": _flower_mesh(), "pebble": _pebble_mesh()}
	for k in _meshes:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/clutter.gdshader")
		m.set_shader_parameter("flower", k == "flower")
		m.set_shader_parameter("up_normal", k != "pebble")
		m.set_shader_parameter("wind", 0.0 if k == "pebble" else 1.0)
		_mats[k] = m
	_apply_range()


## New quality: drop everything and rebuild with the new amount.
static func set_quality(p_radius: float, p_density: float) -> void:
	radius = p_radius
	density = p_density
	if instance:
		for c in instance._chunks.values():
			c.queue_free()
		instance._chunks.clear()
		instance._apply_range()


func _apply_range() -> void:
	for m in _mats.values():
		m.set_shader_parameter("fade_start", radius - 6.0)
		m.set_shader_parameter("fade_end", radius - 1.0)


func _process(_dt: float) -> void:
	var p := World.player
	if p == null or World.zones == null or density <= 0.0:
		return
	var here := Vector2i(floori(p.global_position.x / CHUNK), floori(p.global_position.z / CHUNK))
	var r := int(ceil(radius / CHUNK))
	var built := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := here + Vector2i(dx, dz)
			if _chunks.has(c) or not _in_range(c, p.global_position, radius):
				continue
			if built >= 2:
				break
			_chunks[c] = _build(c)
			built += 1
	for c in _chunks.keys():
		if not _in_range(c, p.global_position, radius + CHUNK):
			_chunks[c].queue_free()
			_chunks.erase(c)


func _in_range(c: Vector2i, pos: Vector3, r: float) -> bool:
	var center := Vector2((c.x + 0.5) * CHUNK, (c.y + 0.5) * CHUNK)
	return center.distance_to(Vector2(pos.x, pos.z)) < r + CHUNK * 0.71


func _build(c: Vector2i) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var center := Vector3((c.x + 0.5) * CHUNK, 0, (c.y + 0.5) * CHUNK)
	var zone: Zone = World.zones.zone_at(center)
	if zone == null:
		return node
	var look: Dictionary = LOOKS.get(zone.type, LOOKS.grassland)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.x, c.y, 991])
	var tufts: Array = []
	var flowers: Array = []
	var pebbles: Array = []
	# Tufts grow in clumps: a few centers, tufts scattered around them.
	var n_tufts := int(float(look.tufts) * density)
	var clumps := maxi(1, n_tufts / 12)
	for k in clumps:
		var cc := Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK)
		for _j in n_tufts / clumps:
			tufts.append(cc + Vector2(rng.randfn(0, 0.8), rng.randfn(0, 0.8)))
	for _k in int(float(look.flowers) * density):
		flowers.append(Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK))
	for _k in int(float(look.pebbles) * density):
		pebbles.append(Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK))
	var base := Vector2(c.x * CHUNK, c.y * CHUNK)
	_add(node, "tuft", tufts, base, zone, rng, func(): return [look.tuft * rng.randf_range(0.9, 1.1), rng.randf_range(0.7, 1.35)])
	var bl: Array = look.blossoms
	if not bl.is_empty():
		_add(node, "flower", flowers, base, zone, rng, func(): return [bl[rng.randi() % bl.size()], rng.randf_range(0.8, 1.2)])
	_add(node, "pebble", pebbles, base, zone, rng, func(): return [look.pebble * rng.randf_range(0.75, 1.2), rng.randf_range(0.05, 0.16)])
	return node


## One MultiMesh of `kind` at the spots that are free ground. style() -> [color, scale].
func _add(node: Node3D, kind: String, spots: Array, base: Vector2, zone: Zone, rng: RandomNumberGenerator, style: Callable) -> void:
	var t := zone.terrain
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for s: Vector2 in spots:
		var w := base + s
		var lx := w.x - zone.position.x
		var lz := w.y - zone.position.z
		if absf(lx) > Terrain.SIZE / 2 or absf(lz) > Terrain.SIZE / 2:
			continue
		if Vector2(lx, lz).length() < Terrain.PLAZA_RADIUS or t.is_water(lx, lz):
			continue
		if t.road_distance(lx, lz) < Terrain.ROAD_WIDTH * 0.5 + 1.2 or t.normal_at(lx, lz).y < 0.82:
			continue
		var st: Array = style.call()
		var sc: float = st[1]
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * (0.6 if kind == "pebble" else 1.0), sc))
		xf.append(Transform3D(b, Vector3(w.x, t.height_at(lx, lz) - 0.02, w.y)))
		cols.append(st[0])
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _meshes[kind]
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
		mm.set_instance_custom_data(k, cols[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mats[kind]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)


## A tuft: 18 tapered, slightly bent blades leaning outward; vertex color red = shade
## (dark at the base, light at the tip).
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 18:
		var a := TAU * k / 18 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.1, 0.22)
		var lean := rng.randf_range(0.1, 0.75)
		var root := out * rng.randf_range(0.0, 0.1)
		var w := 0.026
		var mid := root + out * h * lean * 0.4 + Vector3(0, h * 0.55, 0)
		var tip := root + out * h * lean + Vector3(0, h, 0)
		var p := [root - side * w, root + side * w, mid + side * w * 0.6, mid - side * w * 0.6, tip]
		var shade := [0.6, 0.6, 0.9, 0.9, 1.15]
		for tri in [[0, 1, 2], [0, 2, 3], [3, 2, 4]]:
			for i in tri:
				st.set_color(Color(shade[i], 0, 0, 0))
				st.set_normal(Vector3.UP)
				st.add_vertex(p[i])
	return st.commit()


## A flower: three thin stems with a small blossom (two crossed quads, alpha 1 = blossom).
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 3:
		var a := TAU * k / 3 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.18, 0.3)
		var root := out * 0.03
		var top := root + out * h * 0.25 + Vector3(0, h, 0)
		for tri in [[root - side * 0.006, root + side * 0.006, top]]:
			for i in 3:
				st.set_color(Color(0.6 if i < 2 else 1.0, 0, 0, 0))
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[i])
		var r := 0.03
		for q in [[Vector3(r, 0, 0), Vector3(0, 0, r)], [Vector3(0, 0, r), Vector3(-r, 0, 0)]]:
			var u: Vector3 = q[0]
			var v: Vector3 = q[1]
			var c0 := top - u - v
			var c1 := top + u - v
			var c2 := top + u + v
			var c3 := top - u + v
			for pt in [c0, c1, c2, c0, c2, c3]:
				st.set_color(Color(1, 0, 0, 1))
				st.set_normal(Vector3.UP)
				st.add_vertex(pt)
	return st.commit()


## A pebble: a low-poly lump (unit size, squashed by the instance scale).
static func _pebble_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.7
	sm.radial_segments = 7
	sm.rings = 3
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	for i in verts.size():
		# Lumpy by position (not by index), so the duplicated seam vertices stay together.
		var v := verts[i]
		verts[i] = v * (1.0 + 0.15 * sin(v.x * 17.0 + v.y * 11.0) * cos(v.z * 13.0))
		cols.append(Color(1, 0, 0, 0))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
