class_name Palisade
extends Node3D
## The settlement's wall: a closed ring of upright logs sharpened at the top, about 2 m high,
## RADIUS m round the plaza (outside the houses and the inn), open where the roads run out
## (a gate GATE m wide, framed by two taller posts). Logs follow the ground, each a little
## different in height, thickness and lean; one MultiMesh for all of them. Collision: thin boxes
## along the ring (the gates open). gates(): where the openings are (zone-local), for the guards.

const RADIUS := 47.0
const GATE := 8.0                   ## m of opening per road
const LOG_R := 0.15                 ## m, a log's radius
const HEIGHT := 2.0

var _gates: Array[Dictionary] = []  ## {pos: Vector3, out: Vector3 (outward), yaw}


static func gate_angles(terrain: Terrain) -> Array[float]:
	## The angles (around the plaza, atan2(x, z)) where roads cross the ring.
	var out: Array[float] = []
	for pts in terrain.roads:
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var la := a.length()
			var lb := b.length()
			if (la - RADIUS) * (lb - RADIUS) <= 0.0 and la != lb:
				var p := a.lerp(b, (RADIUS - la) / (lb - la))
				var ang := atan2(p.x, p.y)
				if not out.any(func(o: float) -> bool: return absf(angle_difference(o, ang)) < 0.05):
					out.append(ang)
	return out


## Whether a point (zone-local) is on the wall's line (vegetation keeps clear of it).
static func on_wall(x: float, z: float) -> bool:
	return absf(Vector2(x, z).length() - RADIUS) < 3.5


func gates() -> Array[Dictionary]:
	return _gates


func build(terrain: Terrain, seed: int) -> void:
	name = "Palisade"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 777
	var openings := gate_angles(terrain)
	var half_gate := (GATE * 0.5) / RADIUS            # radians either side of a road's center
	var step := (LOG_R * 1.9) / RADIUS
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var a := 0.0
	while a < TAU:
		var blocked := false
		for g in openings:
			if absf(angle_difference(g, a)) < half_gate:
				blocked = true
		if not blocked:
			var r := RADIUS + rng.randf_range(-0.04, 0.04)
			var p := Vector3(sin(a) * r, 0, cos(a) * r)
			var y := terrain.height_at(p.x, p.z) - 0.35
			var s := rng.randf_range(0.85, 1.15)
			var h := rng.randf_range(0.92, 1.12)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, h, s))
			b = Basis(Vector3(cos(a), 0, -sin(a)), rng.randf_range(-0.04, 0.04)) * b      # a slight lean
			xf.append(Transform3D(b, Vector3(p.x, y, p.z)))
			var v := rng.randf_range(0.8, 1.08)
			cols.append(Color(v, v * rng.randf_range(0.96, 1.0), v * rng.randf_range(0.92, 1.0)))     # lighter or darker logs
		a += step
	# The gates: two tall posts each, and where the guards stand.
	for g in openings:
		for side in [-1.0, 1.0]:
			var ga: float = g + side * (half_gate + step * 0.5)
			var p := Vector3(sin(ga) * RADIUS, 0, cos(ga) * RADIUS)
			var y := terrain.height_at(p.x, p.z) - 0.35
			xf.append(Transform3D(Basis().scaled(Vector3(1.6, 1.45, 1.6)), Vector3(p.x, y, p.z)))
			cols.append(Color(0.9, 0.85, 0.8))
		var out := Vector3(sin(g), 0, cos(g))
		var c := out * (RADIUS - 2.2)
		_gates.append({"pos": Vector3(c.x, terrain.height_at(c.x, c.z), c.z), "out": out, "yaw": g, "half": half_gate})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _log_mesh(WOOD.get(terrain.zone.type if terrain.zone else "grassland", "oak"))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.visibility_range_end = 260.0
	add_child(mi)
	_collision(terrain, openings, half_gate)


## Thin boxes along the closed stretches of the ring (about 1 m each, up to the gates' edges:
## with 4 m ones, those within reach of a gate were left out, a walk-through gap beside each
## gate post), and a round post at each side of every gate.
func _collision(terrain: Terrain, openings: Array[float], half_gate: float) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var seg := 1.0 / RADIUS
	var a := 0.0
	while a < TAU:
		var mid := a + seg * 0.5
		var blocked := false
		for g in openings:
			if absf(angle_difference(g, mid)) < half_gate:
				blocked = true
		if not blocked:
			var p := Vector3(sin(mid) * RADIUS, 0, cos(mid) * RADIUS)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(seg * RADIUS + 0.1, 3.0, 0.5)
			cs.shape = box
			cs.position = Vector3(p.x, terrain.height_at(p.x, p.z) + 1.0, p.z)
			cs.rotation.y = mid                  # its long side along the ring
			body.add_child(cs)
		a += seg
	var step := (LOG_R * 1.9) / RADIUS
	for g in openings:
		for side in [-1.0, 1.0]:
			var ga: float = g + side * (half_gate + step * 0.5)
			var p := Vector3(sin(ga) * RADIUS, 0, cos(ga) * RADIUS)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = LOG_R * 1.6 + 0.08
			cyl.height = 3.4
			cs.shape = cyl
			cs.position = Vector3(p.x, terrain.height_at(p.x, p.z) + 1.3, p.z)
			body.add_child(cs)


## The wood the walls are built of, by land: oak in the green countryside, pine in the North,
## palm trunks in the Desert, acacia by the pyramids, olive and cypress by the sea, charred wood
## in the Unholy lands (textures generated, tools/pipeline/seamless.py; assets/wood).
const WOOD := {"grassland": "oak", "north": "pine", "desert": "palm", "ancient": "acacia",
	"mediterranean": "olive", "unholy": "charred"}
## Warms a bark that the sky light would otherwise turn grey-blue.
const WARM := {"oak": Color(1.0, 0.86, 0.7), "olive": Color(1.0, 0.9, 0.76)}


## One log: a slightly tapering trunk with bark, its top cut to a point (pale hewn wood); one
## mesh per kind of wood, shared by every wall of that wood.
static var _meshes := {}


static func _log_mesh(wood: String) -> ArrayMesh:
	if _meshes.has(wood):
		return _meshes[wood]
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://assets/wood/%s.png" % wood)
	bark.uv1_scale = Vector3(1.0, 2.4, 1.0)            # a texture's width round the log, ~1 m of it a repeat
	bark.roughness = 0.95
	bark.albedo_color = WARM.get(wood, Color.WHITE)
	bark.vertex_color_use_as_albedo = true             # each log a little lighter or darker
	var cut := StandardMaterial3D.new()
	cut.albedo_texture = load("res://assets/wood/hewn.png")
	cut.uv1_scale = Vector3(1.0, 0.4, 1.0)
	cut.roughness = 0.9
	cut.albedo_color = Color(0.78, 0.64, 0.48) if wood != "charred" else Color(0.45, 0.36, 0.28)   # weathered, not fresh-white
	cut.vertex_color_use_as_albedo = true
	var trunk := CylinderMesh.new()
	trunk.top_radius = LOG_R * 0.9
	trunk.bottom_radius = LOG_R
	trunk.height = HEIGHT + 0.35
	trunk.radial_segments = 7
	trunk.rings = 1
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = LOG_R * 0.9
	tip.height = 0.38
	tip.radial_segments = 7
	tip.rings = 1
	tip.cap_bottom = false
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, trunk.height / 2.0, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, bark)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(tip, 0, Transform3D(Basis(), Vector3(0, trunk.height + tip.height / 2.0, 0)))
	st.commit(mesh)
	mesh.surface_set_material(1, cut)
	_meshes[wood] = mesh
	return mesh
