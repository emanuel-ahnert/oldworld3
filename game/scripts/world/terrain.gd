class_name Terrain
extends Node3D
## Heightmap terrain of one zone (design/world.md, section 2). Centered on the origin, Y up.
## Generated from a seed: the same seed always gives the same terrain.

const SIZE := 512.0          ## zone size in meters
const STEP := 2.0            ## meters between height samples
const N := 257               ## samples per side (SIZE / STEP + 1)
const CHUNK := 32            ## quads per chunk side (64 m)
const PLAZA_RADIUS := 22.0        ## flat settlement area (the bare-earth plaza is smaller)
const ROAD_WIDTH := 4.0

var heights := PackedFloat32Array()
var dirt := PackedFloat32Array()     ## 0..1 per sample: roads and plaza
var roads: Array[PackedVector2Array] = []
var shore := PackedFloat32Array()    ## 0..1 per sample: sand at lake shores
var lakes: Array[Dictionary] = []    ## {center: Vector2, radius, level}
var crossings: Array[Vector2] = []   ## zone-local points on the border where roads lead through
var material: ShaderMaterial
var zone: Zone
var frozen := false

const CROSS_H := 1.0                 ## terrain height at every crossing (same on both sides)


## Generates the zone's terrain. Hills come from world-space noise (continuous across zones);
## roads, lakes and the rim from the zone; crossings are shared with the neighbor zone.
func generate(seed: int, p_zone: Zone = null, world_seed := 1) -> void:
	compute(seed, p_zone, world_seed)
	build()


## The data part (heights, roads, crossings, lakes): no rendering or physics objects, so it can
## run on a worker thread while the game renders (see ZoneManager).
func compute(seed: int, p_zone: Zone = null, world_seed := 1) -> void:
	zone = p_zone
	var origin := Vector2(zone.position.x, zone.position.z) if zone else Vector2.ZERO
	var cell := zone.cell if zone else Vector2i.ZERO
	frozen = zone != null and bool(zone.info.get("frozen_lakes", false))
	var hills := FastNoiseLite.new()
	hills.seed = world_seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 1.0 / 150.0
	hills.fractal_octaves = 4
	var big := FastNoiseLite.new()
	big.seed = world_seed + 1
	big.frequency = 1.0 / 380.0
	big.fractal_octaves = 2
	# Mountains on the border rim: ridged noise gives peaks, ridges and saddles. World
	# coordinates, so both zones meet at the same height on their common border.
	var ridge := FastNoiseLite.new()
	ridge.seed = world_seed + 7
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 1.0 / 130.0
	ridge.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_make_crossings(cell, world_seed)
	_make_roads(rng)
	heights.resize(N * N)
	dirt.resize(N * N)
	var center_h := hills.get_noise_2d(origin.x, origin.y) * 8.0
	for j in N:
		for i in N:
			var x := -SIZE / 2 + i * STEP
			var z := -SIZE / 2 + j * STEP
			var d := Vector2(x, z).length()
			var h := hills.get_noise_2d(x + origin.x, z + origin.y) * 8.0
			var b := big.get_noise_2d(x + origin.x, z + origin.y) * 0.5 + 0.5
			h += b * b * 28.0 * smoothstep(70.0, 220.0, d)
			# Flat settlement area in the middle.
			h = lerpf(center_h, h, smoothstep(PLAZA_RADIUS + 8.0, PLAZA_RADIUS + 45.0, d))
			# Roads: pull the terrain toward a smoothed height and paint dirt.
			var rd := _road_distance(Vector2(x, z))
			var road := 1.0 - smoothstep(ROAD_WIDTH * 0.5, ROAD_WIDTH * 0.5 + 1.5, rd)
			h = lerpf(h, h * 0.85 + center_h * 0.15, road * 0.5)
			# Border rim: cliffs and hills toward the zone edge, with a gap where a road leads
			# through to a crossing; at a crossing both zones meet at the same height.
			var edge := maxf(absf(x), absf(z))
			var r := ridge.get_noise_2d(x + origin.x, z + origin.y) * 0.5 + 0.5      # 0..1, sharp crests
			var rim := pow(smoothstep(195.0, 256.0, edge), 1.6) * (32.0 + pow(r, 1.6) * 62.0)
			rim += smoothstep(150.0, 230.0, edge) * r * r * r * 14.0               # craggy foothills
			h += rim * smoothstep(5.0, 16.0, rd)
			for c in crossings:
				var w := (1.0 - smoothstep(0.0, 70.0, Vector2(x, z).distance_to(c))) * (1.0 - smoothstep(4.0, 18.0, rd))
				h = lerpf(h, CROSS_H, w)
			heights[j * N + i] = h
			dirt[j * N + i] = maxf(road, 1.0 - smoothstep(10.0, 15.0, d))
	_carve_lakes(rng)


## The node part (material, meshes, water, collision): on the main thread.
func build() -> void:
	_build_material()
	_build_meshes()
	_build_water()
	_build_collision()


## One crossing per border, at a place both zones derive from the same hash, so the road
## continues on the other side (Oldworld2: crossings from hash(seed, zoneA, zoneB)).
func _make_crossings(cell: Vector2i, world_seed: int) -> void:
	crossings.clear()
	var half := SIZE / 2
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var a: Vector2i = cell
		var b: Vector2i = cell + d
		var lo: Vector2i = a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
		var hi: Vector2i = b if lo == a else a
		var off := float(absi(hash([world_seed, lo.x, lo.y, hi.x, hi.y])) % 260) - 130.0
		if d.x != 0:
			crossings.append(Vector2(half * d.x, off))
		else:
			crossings.append(Vector2(off, half * d.y))
## Two or three shallow lakes on flat ground, away from the settlement, roads and the edge
## (design/world.md, section 2). The hero can wade through them (at most about 1.2 m deep).
func _carve_lakes(rng: RandomNumberGenerator) -> void:
	lakes.clear()
	shore.resize(N * N)
	shore.fill(0.0)
	var want := rng.randi_range(2, 4)
	var tries := 0
	while lakes.size() < want and tries < 600:
		tries += 1
		var c := Vector2(rng.randf_range(-190, 190), rng.randf_range(-190, 190))
		var r := rng.randf_range(16.0, 28.0)
		if c.length() < 90.0 or _road_distance(c) < r * 1.5 + 6.0:
			continue
		var bad := false
		for l in lakes:
			if c.distance_to(l.center) < r + float(l.radius) + 40.0:
				bad = true
		# Water level below the lowest point of the surrounding rim, so it never spills over;
		# steep slopes are left out.
		var lo_h := INF
		var hi_h := -INF
		for k in 16:
			var a := TAU * k / 16.0
			for rr: float in [1.0, 1.5]:
				var q := c + Vector2(cos(a), sin(a)) * r * rr
				var hq := height_at(q.x, q.y)
				lo_h = minf(lo_h, hq)
				hi_h = maxf(hi_h, hq)
		if hi_h - lo_h > 6.0:
			bad = true
		if bad:
			continue
		var level := lo_h - 0.4
		var ph := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		lakes.append({"center": c, "radius": r, "level": level, "ph": ph})
		var i0 := clampi(int((c.x - r * 1.6 + SIZE / 2) / STEP), 0, N - 1)
		var i1 := clampi(int((c.x + r * 1.6 + SIZE / 2) / STEP), 0, N - 1)
		var j0 := clampi(int((c.y - r * 1.6 + SIZE / 2) / STEP), 0, N - 1)
		var j1 := clampi(int((c.y + r * 1.6 + SIZE / 2) / STEP), 0, N - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(-SIZE / 2 + i * STEP, -SIZE / 2 + j * STEP)
				var d := p.distance_to(c) / (r * _shape(lakes[-1], p - c))
				var k := j * N + i
				if d < 1.0:
					heights[k] = minf(heights[k], (level - 0.05) if frozen else (level - 1.2 * (1.0 - d * d) - 0.15))
				elif d < 1.5:
					var bank := level + 0.25 + (d - 1.0) * 1.2
					heights[k] = lerpf(minf(heights[k], bank), heights[k], smoothstep(1.0, 1.5, d))
				shore[k] = maxf(shore[k], 1.0 - smoothstep(0.85, 1.25, d))


## Irregular shoreline: the lake's radius varies with the direction.
func _shape(l: Dictionary, v: Vector2) -> float:
	var a := v.angle()
	var ph: Vector3 = l.ph
	return 1.0 + 0.2 * sin(3.0 * a + ph.x) + 0.1 * sin(5.0 * a + ph.y) + 0.06 * sin(8.0 * a + ph.z)


func is_water(x: float, z: float) -> bool:
	for l in lakes:
		if Vector2(x, z).distance_to(l.center) < float(l.radius) * 1.1:
			return true
	return false


## Distance from a point to the nearest lake's shore (negative inside a lake).
func lake_distance(x: float, z: float) -> float:
	var best := INF
	for l in lakes:
		var v := Vector2(x, z) - Vector2(l.center)
		best = minf(best, v.length() - float(l.radius) * _shape(l, v))
	return best


func _build_water() -> void:
	if frozen:
		var ice := StandardMaterial3D.new()
		ice.albedo_texture = load("res://assets/terrain/ice.png") if ResourceLoader.exists("res://assets/terrain/ice.png") else null
		ice.albedo_color = Color(0.85, 0.92, 1.0)
		ice.uv1_triplanar = true
		ice.uv1_world_triplanar = true
		ice.uv1_scale = Vector3(0.12, 0.12, 0.12)
		ice.roughness = 0.15
		ice.metallic_specular = 0.8
		for l in lakes:
			var mi := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = float(l.radius) * 1.45
			disc.bottom_radius = float(l.radius) * 1.45
			disc.height = 0.02
			disc.radial_segments = 48
			mi.mesh = disc
			mi.material_override = ice
			mi.position = Vector3(l.center.x, float(l.level), l.center.y)
			add_child(mi)
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	nt.noise = fn
	mat.set_shader_parameter("wave_normal", nt)
	for l in lakes:
		var mi := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(l.radius) * 1.45
		disc.bottom_radius = float(l.radius) * 1.45
		disc.height = 0.02
		disc.radial_segments = 48
		disc.cap_bottom = false
		mi.mesh = disc
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(l.center.x, float(l.level), l.center.y)
		mi.name = "Lake"
		add_child(mi)


func _make_roads(rng: RandomNumberGenerator) -> void:
	roads.clear()
	for cr in crossings:
		var dir := cr.normalized()
		# Straight out of the crossing for 20 m, then winding toward the plaza.
		var inward := Vector2(-signf(cr.x), 0) if absf(cr.x) >= SIZE / 2 - 0.1 else Vector2(0, -signf(cr.y))
		var pts := PackedVector2Array([dir * PLAZA_RADIUS, cr + inward * 20.0])
		for _pass in 4:
			var next := PackedVector2Array()
			for k in pts.size() - 1:
				var a := pts[k]
				var c := pts[k + 1]
				var mid := (a + c) * 0.5
				var side := Vector2(-(c - a).y, (c - a).x).normalized()
				next.append(a)
				next.append(mid + side * rng.randf_range(-0.18, 0.18) * a.distance_to(c))
			next.append(pts[pts.size() - 1])
			pts = next
		pts.append(cr)
		roads.append(pts)


func _road_distance(p: Vector2) -> float:
	var best := INF
	for pts in roads:
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + (b - a) * t))
	return best


func road_distance(x: float, z: float) -> float:
	return _road_distance(Vector2(x, z))


## Terrain height at world position (bilinear).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SIZE / 2) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + SIZE / 2) / STEP, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * N + i]
	var h10 := heights[j * N + i + 1]
	var h01 := heights[(j + 1) * N + i]
	var h11 := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var hl := height_at(x - STEP, z)
	var hr := height_at(x + STEP, z)
	var hd := height_at(x, z - STEP)
	var hu := height_at(x, z + STEP)
	return Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()


static var _noise_tex: NoiseTexture2D


## One tileable noise for all zones (the terrain shader's variety).
static func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012
		n.fractal_octaves = 4
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 512
		_noise_tex.height = 512
		_noise_tex.seamless = true
		_noise_tex.generate_mipmaps = true
		_noise_tex.noise = n
	return _noise_tex


func _build_material() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var g: Dictionary = zone.info.ground if zone else {"grass": "res://assets/terrain/grass.png", "dirt": "res://assets/terrain/dirt.png", "rock": "res://assets/terrain/rock.png"}
	for k in ["grass", "dirt", "rock"]:
		var path: String = g[k] if ResourceLoader.exists(g[k]) else "res://assets/terrain/%s.png" % k
		material.set_shader_parameter(k + "_tex", load(path))
	material.set_shader_parameter("snow", float(zone.info.get("snow", 0.0)) if zone else 0.0)
	var top: String = g.get("rock_top", g.rock)
	material.set_shader_parameter("rock_top_tex", load(top if ResourceLoader.exists(top) else g.rock))
	material.set_shader_parameter("noise_tex", _noise())
	material.set_shader_parameter("soil_tex", load("res://assets/terrain/dirt.png"))
	material.set_shader_parameter("bare", float(zone.info.get("bare", 0.5)) if zone else 0.5)
	material.set_shader_parameter("snow_line", float(zone.info.get("snow_line", 1000.0)) if zone else 1000.0)
	material.set_shader_parameter("rock_tint", zone.info.get("rock_tint", Color.WHITE) if zone else Color.WHITE)
	if zone and zone.info.has("road_tint"):
		var rt: Color = zone.info.road_tint          # rgb: tint, a: saturation kept
		material.set_shader_parameter("road_tint", Vector3(rt.r, rt.g, rt.b))
		material.set_shader_parameter("road_sat", rt.a)
	material.set_shader_parameter("rock_moss", zone.info.get("rock_moss", Color(0, 0, 0, 0)) if zone else Color(0, 0, 0, 0))
	if zone and zone.info.has("grass_tint"):
		material.set_shader_parameter("grass_tint", zone.info.grass_tint)
	if zone and float(zone.info.get("snow", 0.0)) > 0.5:
		material.set_shader_parameter("grass_tile", 7.0)   # snow drifts are large


func _build_meshes() -> void:
	var chunks := (N - 1) / CHUNK
	for cj in chunks:
		for ci in chunks:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(cj * CHUNK, cj * CHUNK + CHUNK + 1):
				for i in range(ci * CHUNK, ci * CHUNK + CHUNK + 1):
					var x := -SIZE / 2 + i * STEP
					var z := -SIZE / 2 + j * STEP
					st.set_color(Color(dirt[j * N + i], shore[j * N + i], 0))
					st.set_normal(normal_at(x, z))
					st.add_vertex(Vector3(x, heights[j * N + i], z))
			var w := CHUNK + 1
			for j in CHUNK:
				for i in CHUNK:
					var a := j * w + i
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + w)
					st.add_index(a + 1)
					st.add_index(a + w + 1)
					st.add_index(a + w)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = material
			mi.name = "Chunk_%d_%d" % [ci, cj]
			add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(STEP, 1.0, STEP)
	body.add_child(cs)
	add_child(body)
