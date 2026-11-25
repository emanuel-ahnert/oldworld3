class_name Graveyard
extends Node3D
## A graveyard in the Unholy lands (instead of gravestones scattered through the forest): a
## clearing with a wrought-iron fence, its gate toward the settlement, a crypt at the back, rows
## of gravestones on both sides of a path from the gate (some missing, some leaning or turned),
## two dead trees in the corners and a faint green light at the crypt. The fence is one mesh
## built here; its sides block walking (box colliders per section).

const W := 20.0              ## m across (along the gate side)
const D := 20.0              ## m deep
const GATE := 3.2            ## m wide opening in the middle of the front side
const CLEARING := 17.0       ## m around the middle kept free of trees (Scatter)
const FENCE_H := 1.45
const BAR := 0.22            ## m between the fence's bars
const STONE := "res://assets/props/gravestone.glb"
const CRYPT := "res://assets/buildings/crypt.glb"
const TREE := "res://assets/nature/deadtree.glb"

static var _iron: StandardMaterial3D


## Where a zone's graveyards go: `count` spots 60–200 m from the settlement on flat ground,
## clear of roads, lakes, shrines and each other. Zone-local, computed before the vegetation.
static func spots(terrain: Terrain, count: int, seed: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 130
	for tries in 800:
		var a := rng.randf() * TAU
		var d := rng.randf_range(60.0, 200.0)
		var p := Vector3(sin(a) * d, 0, cos(a) * d)
		if terrain.road_distance(p.x, p.z) < 22.0 or terrain.lake_distance(p.x, p.z) < 22.0:
			continue
		var flat := true
		for k in 9:
			var q := p + (Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * 11.0 if k < 8 else Vector3.ZERO)
			if terrain.normal_at(q.x, q.z).y < 0.94:
				flat = false
				break
		if not flat:
			continue
		if out.any(func(o): return o.distance_to(p) < 90.0):
			continue
		if Settlement.shrine_spots(terrain).any(func(s): return Vector2(s.x - p.x, s.z - p.z).length() < 35.0):
			continue
		p.y = terrain.height_at(p.x, p.z)
		out.append(p)
		if out.size() >= count:
			break
	return out


## Builds the graveyard at zone-local `center`, its gate facing the settlement (the origin).
## The node is added to `parent` (the settlement, at the zone's origin).
static func build(parent: Node3D, terrain: Terrain, center: Vector3, seed: int) -> Graveyard:
	var g := Graveyard.new()
	g.name = "Graveyard"
	parent.add_child(g)
	g._make(terrain, center, seed)
	return g


func _make(terrain: Terrain, center: Vector3, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var yaw := atan2(-center.x, -center.z)          # +Z (local front, the gate) toward the settlement
	var basis := Basis(Vector3.UP, yaw)
	var at := func(lx: float, lz: float) -> Vector3:
		return center + basis * Vector3(lx, 0, lz)
	# The crypt at the back, its door toward the gate.
	if ResourceLoader.exists(CRYPT):
		_put(CRYPT, terrain, at.call(0.0, -6.0), 7.5, yaw, false, true)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.45, 1.0, 0.55)
		glow.light_energy = 0.6
		glow.omni_range = 8.0
		add_child(glow)
		var gp: Vector3 = at.call(0.0, 0.5)
		glow.position = Vector3(gp.x, terrain.height_at(gp.x, gp.z) + 1.6, gp.z)
	# Gravestone rows on both sides of the path from the gate; beside the crypt too.
	var places: Array = []
	for z in [-0.5, 2.5, 5.5, 8.3]:
		for x in [-8.3, -5.6, -2.9, 2.9, 5.6, 8.3]:
			places.append(Vector2(x, z))
	for z in [-4.0, -7.5]:
		for x in [-8.3, -6.0, 6.0, 8.3]:
			places.append(Vector2(x, z))
	for pl: Vector2 in places:
		if rng.randf() < 0.15:
			continue                                  # an empty grave
		var p: Vector3 = at.call(pl.x + rng.randf_range(-0.3, 0.3), pl.y + rng.randf_range(-0.25, 0.25))
		var n := _put(STONE, terrain, p, rng.randf_range(0.85, 1.3), yaw + rng.randf_range(-0.2, 0.2) + (PI if rng.randf() < 0.06 else 0.0), true, true)
		if n and rng.randf() < 0.3:
			# Leaning: tipped a little forward, back or to a side.
			n.rotate_object_local(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			n.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.15, 0.15))
	# Dead trees in the back corners.
	if ResourceLoader.exists(TREE):
		for x in [-1.0, 1.0]:
			_put(TREE, terrain, at.call(x * (W / 2 - 1.5), -D / 2 + 1.5), rng.randf_range(6.5, 9.0), rng.randf() * TAU, true, false)
	_fence(terrain, center, basis)


func _put(path: String, terrain: Terrain, pos: Vector3, size: float, yaw: float, by_height: bool, collide: bool) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = load(path).instantiate()
	add_child(n)
	Placement.put_on_ground(n, terrain, pos, size, yaw, by_height, 0.08)
	if collide:
		Placement.add_box_collision(n)
	return n


## The wrought-iron fence: posts every 2 m, two rails, bars with spear tips between them, the
## gate open; one mesh following the ground, a collider per section.
func _fence(terrain: Terrain, center: Vector3, basis: Basis) -> void:
	if _iron == null:
		_iron = StandardMaterial3D.new()
		_iron.albedo_color = Color(0.07, 0.07, 0.08)
		_iron.metallic = 0.6
		_iron.roughness = 0.45
		_iron.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	add_child(body)
	var hw := W / 2.0
	var hd := D / 2.0
	var corners := [Vector2(-hw, hd), Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[side + 1]
		var length := a.distance_to(b)
		var sections := ceili(length / 2.0)
		for i in sections:
			var p0 := a.lerp(b, float(i) / sections)
			var p1 := a.lerp(b, float(i + 1) / sections)
			# The gate: the front side (side 3, from right to left) is open in the middle.
			if side == 3 and absf((p0.x + p1.x) / 2.0) < GATE / 2.0:
				continue
			var w0 := _ground(terrain, center, basis, p0)
			var w1 := _ground(terrain, center, basis, p1)
			_box(st, w0 + Vector3(0, FENCE_H * 0.55, 0), Vector3(0.09, FENCE_H * 1.1, 0.09), 0.0)     # post
			_box(st, w0 + Vector3(0, FENCE_H * 1.12, 0), Vector3(0.14, 0.1, 0.14), PI / 4)            # post cap
			var dir := (w1 - w0)
			var flat_yaw := atan2(dir.x, dir.z)
			for h in [0.25, FENCE_H - 0.12]:
				var mid := (w0 + w1) / 2.0 + Vector3(0, h, 0)
				_box(st, mid, Vector3(0.04, 0.05, Vector2(dir.x, dir.z).length()), flat_yaw, dir.y)
			var bars := maxi(1, int(Vector2(dir.x, dir.z).length() / BAR))
			for k in range(1, bars):
				var bp := w0.lerp(w1, float(k) / bars)
				bp.y = _ground(terrain, center, basis, p0.lerp(p1, float(k) / bars)).y
				_box(st, bp + Vector3(0, FENCE_H * 0.5, 0), Vector3(0.025, FENCE_H, 0.025), 0.0)
				_box(st, bp + Vector3(0, FENCE_H + 0.05, 0), Vector3(0.05, 0.1, 0.05), PI / 4)   # spear tip
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.2, FENCE_H, Vector2(dir.x, dir.z).length())
			cs.shape = bs
			cs.position = (w0 + w1) / 2.0 + Vector3(0, FENCE_H / 2.0, 0)
			cs.rotation.y = flat_yaw
			body.add_child(cs)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _iron
	add_child(mi)


func _ground(terrain: Terrain, center: Vector3, basis: Basis, local: Vector2) -> Vector3:
	var p := center + basis * Vector3(local.x, 0, local.y)
	p.y = terrain.height_at(p.x, p.z) - 0.05
	return p


## An axis box of `size` at `pos`, turned by `yaw` and tilted along its length by `rise` m.
func _box(st: SurfaceTool, pos: Vector3, size: Vector3, yaw: float, rise := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	if rise != 0.0 and size.z > 0.001:
		b = b * Basis(Vector3.RIGHT, -atan2(rise, size.z))
	var h := size / 2.0
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for i in 8:
		c[i] = pos + b * c[i]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		st.add_vertex(c[f[0]])
		st.add_vertex(c[f[2]])
		st.add_vertex(c[f[1]])
		st.add_vertex(c[f[0]])
		st.add_vertex(c[f[3]])
		st.add_vertex(c[f[2]])
