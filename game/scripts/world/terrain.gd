class_name Terrain
extends Node3D
## Heightmap terrain of one zone (design/world.md, section 2). Centered on the origin, Y up.
## Generated from a seed: the same seed always gives the same terrain.

const SIZE := 1024.0         ## zone size in meters (was 512)
const HALF := SIZE / 2
const STEP := 2.0            ## meters between height samples
const N := 513               ## samples per side (SIZE / STEP + 1)
const CHUNK := 32            ## quads per chunk side (64 m)
const PLAZA_RADIUS := 22.0        ## flat settlement area (the bare-earth plaza is smaller)
const ROAD_WIDTH := 4.0

var heights := PackedFloat32Array()
var dirt := PackedFloat32Array()     ## 0..1 per sample: roads and plaza
var roads: Array[PackedVector2Array] = []
var shore := PackedFloat32Array()    ## 0..1 per sample: sand at lake shores
var lakes: Array[Dictionary] = []    ## {center: Vector2, radius, level}
var crossings: Array[Vector2] = []   ## zone-local points on the border where roads lead through
## The zone's own landscape (_plan_features, from its seed): the rim pushed in by `_intrude`
## (spurs of the border mountains), and maybe a ridge across it, a river through it, or in the
## Mediterranean a volcano.
var ridges: Array[Dictionary] = []   ## {pts: PackedVector2Array, height, width}
var rivers: Array[Dictionary] = []   ## {pts: PackedVector2Array (every ~4 m), levels: PackedFloat32Array, width}
var volcano: Dictionary = {}         ## {center: Vector2, radius, height, crater, floor}
var _intrude: FastNoiseLite
var _mtn := PackedFloat32Array()     ## per sample: m of mountain on the ground (border range, ridges)
var _crag: FastNoiseLite
var _crag_origin := Vector2.ZERO
var _rdist := PackedFloat32Array()   ## per sample: distance to the nearest river's bank (INF: none near)
var _rlevel := PackedFloat32Array()  ## per sample: that river's water level
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
	var foot := FastNoiseLite.new()           # the foothills' own lumps
	foot.seed = world_seed + 13
	foot.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	foot.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	foot.frequency = 1.0 / 75.0
	foot.fractal_octaves = 3
	# Crags on the mountains: fine ridged noise (broken crests, gullies, ledges), only where
	# there are mountains; world coordinates (the same on both sides of a border).
	_crag = FastNoiseLite.new()
	_crag.seed = world_seed + 11
	_crag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crag.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_crag.frequency = 1.0 / 34.0
	_crag.fractal_octaves = 3
	_crag_origin = origin
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_make_crossings(cell, world_seed)
	_make_roads(rng)
	# The landscape's own rng (the lakes' sequence stays as it was).
	var frng := RandomNumberGenerator.new()
	frng.seed = seed * 31 + 977
	_intrude = FastNoiseLite.new()
	_intrude.seed = seed + 5
	_intrude.frequency = 1.0 / 170.0
	_intrude.fractal_octaves = 2
	_plan_features(frng, zone.type if zone else "grassland")
	_river_field()
	if OS.get_cmdline_user_args().has("--feature-log"):
		print("FEATURES %s ridges %d rivers %d volcano %s" % [cell, ridges.size(), rivers.size(), volcano])
	heights.resize(N * N)
	dirt.resize(N * N)
	_mtn.resize(N * N)
	_mtn.fill(0.0)
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
			# The rim's line pushed in here and there (spurs and bays of the border mountains);
			# on the border itself it stays full height, the same on both zones.
			var intr := clampf(_intrude.get_noise_2d(x, z) * 2.0, 0.0, 1.0) * INTRUDE
			if not _rdist.is_empty():
				intr *= smoothstep(25.0, 110.0, _rdist[j * N + i])     # no spurs in a river's valley
			if not volcano.is_empty():
				# Nor round the volcano and its lava lake (beyond its foot).
				intr *= smoothstep(float(volcano.radius) * 1.15, float(volcano.radius) * 1.7, Vector2(x, z).distance_to(volcano.center))
			var edge0 := maxf(absf(x), absf(z))           # the border's own line (the steep top)
			var edge := edge0 + intr                       # pushed in by the spurs (the slopes)
			var r := ridge.get_noise_2d(x + origin.x, z + origin.y) * 0.5 + 0.5      # 0..1, sharp crests
			# A mountain range, not a wall: slopes rising over 230 m with their own lumps and
			# spurs, the high range over the last 170 m up to the border, peaks and saddles of
			# very different heights along it. Slopes stay climbable: the border's invisible wall
			# (_build_border) closes the zone.
			var r2 := foot.get_noise_2d(x + origin.x, z + origin.y) * 0.5 + 0.5
			var rim := pow(smoothstep(HALF - 230.0, HALF, edge), 1.6) * (14.0 + pow(r2, 1.4) * 40.0)
			rim += pow(smoothstep(HALF - 170.0, HALF, edge0), 1.9) * (22.0 + pow(r, 1.8) * 70.0)   # the high range at the border
			rim += _crags(x, z, rim)
			h += rim * smoothstep(5.0, 16.0, rd)
			_mtn[j * N + i] = rim * smoothstep(5.0, 16.0, rd)
			for c in crossings:
				var w := (1.0 - smoothstep(0.0, 70.0, Vector2(x, z).distance_to(c))) * (1.0 - smoothstep(4.0, 18.0, rd))
				h = lerpf(h, CROSS_H, w)
			heights[j * N + i] = h
			dirt[j * N + i] = maxf(road, 1.0 - smoothstep(10.0, 15.0, d))
	shore.resize(N * N)
	shore.fill(0.0)
	_apply_features()
	if OS.get_cmdline_user_args().has("--feature-log") and not volcano.is_empty():
		var vc: Vector2 = volcano.center
		print("VOLCANO h center %.1f  r/2 %.1f  rim %.1f  outside %.1f floor %s" % [height_at(vc.x, vc.y), height_at(vc.x + volcano.radius * 0.5, vc.y), height_at(vc.x + volcano.crater * 1.3, vc.y), height_at(vc.x + volcano.radius * 1.1, vc.y), volcano.get("floor")])
	_carve_lakes(rng)


## The node part (material, meshes, water, collision): on the main thread.
func build() -> void:
	_build_material()
	_build_meshes()
	_build_water()
	_build_rivers()
	_build_volcano()
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
		var off := float(absi(hash([world_seed, lo.x, lo.y, hi.x, hi.y])) % int(HALF)) - HALF / 2.0
		if d.x != 0:
			crossings.append(Vector2(half * d.x, off))
		else:
			crossings.append(Vector2(off, half * d.y))
## Two or three shallow lakes on flat ground, away from the settlement, roads and the edge
## (design/world.md, section 2). The hero can wade through them (at most about 1.2 m deep).
func _carve_lakes(rng: RandomNumberGenerator) -> void:
	lakes.clear()
	var want := rng.randi_range(5, 9)            # (zones four times the area of the first ones)
	var tries := 0
	while lakes.size() < want and tries < 600:
		tries += 1
		var c := Vector2(rng.randf_range(-HALF + 66, HALF - 66), rng.randf_range(-HALF + 66, HALF - 66))
		var r := rng.randf_range(16.0, 28.0)
		if c.length() < 90.0 or _road_distance(c) < r * 1.5 + 6.0:
			continue
		if river_distance(c.x, c.y) < r * 1.6 + 16.0 or _in_volcano(c, r + 20.0):
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
	if river_distance(x, z) < 0.0:
		return true
	for l in lakes:
		if Vector2(x, z).distance_to(l.center) < float(l.radius) * 1.1:
			return true
	return false


## The water surface's height over a point (zone-local), or NAN on dry land (or ice): where a
## lake's water lies above the ground.
func water_level(x: float, z: float) -> float:
	if frozen:
		return NAN
	var rl := river_level(x, z)
	if not is_nan(rl):
		return rl
	for l in lakes:
		if Vector2(x, z).distance_to(l.center) < float(l.radius) * 1.45 and float(l.level) > height_at(x, z):
			return float(l.level)
	return NAN


## Distance from a point to the nearest lake's shore (negative inside a lake).
func lake_distance(x: float, z: float) -> float:
	var best := river_distance(x, z)
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


static var _noise_tex: ImageTexture


## One tileable noise for all zones (the terrain shader's variety). Red: the noise; green: the
## same noise six times smaller, tiled (read with the red at one scale, it gives the fine grit
## a texture read of its own used to cost).
static func _noise() -> ImageTexture:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012
		n.fractal_octaves = 4
		const S := 516                       # 6 x 86
		var img := n.get_seamless_image(S, S)
		img.convert(Image.FORMAT_L8)
		var small := img.duplicate() as Image
		small.resize(S / 6, S / 6, Image.INTERPOLATE_CUBIC)
		var a := img.get_data()
		var b := small.get_data()
		var rg := PackedByteArray()
		rg.resize(S * S * 2)
		var w := S / 6
		for y in S:
			var row := (y % w) * w
			for x in S:
				var i := y * S + x
				rg[i * 2] = a[i]
				rg[i * 2 + 1] = b[row + x % w]
		var out := Image.create_from_data(S, S, false, Image.FORMAT_RG8, rg)
		out.generate_mipmaps()
		_noise_tex = ImageTexture.create_from_image(out)
	return _noise_tex


func _build_material() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var g: Dictionary = zone.info.ground if zone else {"grass": "res://assets/terrain/grass.png", "dirt": "res://assets/terrain/dirt.png", "rock": "res://assets/terrain/rock.png"}
	for k in ["grass", "dirt", "rock"]:
		var path: String = g[k] if ResourceLoader.exists(g[k]) else "res://assets/terrain/%s.png" % k
		material.set_shader_parameter(k + "_tex", load(path))
		if k == "grass":
			material.set_shader_parameter("grass_tex_plain", load(path))
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
					st.set_color(Color(dirt[j * N + i], shore[j * N + i], _ash(x, z)))
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


## The zone's border: an invisible wall along each side (the mountains can be climbed up to it),
## open for BORDER_GAP m round each crossing where the road leads through.
const BORDER_GAP := 14.0
const BORDER_LAYER := 16


func _build_border(body: StaticBody3D) -> void:
	for side in 4:
		# The side's line: points along it from -HALF to HALF, gaps round its crossings.
		var cuts: Array[float] = []
		for c in crossings:
			var on := (side == 0 and c.x >= HALF - 0.1) or (side == 1 and c.x <= -HALF + 0.1) or (side == 2 and c.y >= HALF - 0.1) or (side == 3 and c.y <= -HALF + 0.1)
			if on:
				cuts.append(c.y if side < 2 else c.x)
		cuts.sort()
		var start := -HALF
		var pieces: Array[Vector2] = []
		for cv in cuts:
			pieces.append(Vector2(start, cv - BORDER_GAP))
			start = cv + BORDER_GAP
		pieces.append(Vector2(start, HALF))
		for pc in pieces:
			if pc.y - pc.x < 0.5:
				continue
			var mid := (pc.x + pc.y) * 0.5
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(pc.y - pc.x, 400.0, 1.0) if side >= 2 else Vector3(1.0, 400.0, pc.y - pc.x)
			cs.shape = box
			var e := HALF - 0.5
			match side:
				0:
					cs.position = Vector3(e, 100.0, mid)
				1:
					cs.position = Vector3(-e, 100.0, mid)
				2:
					cs.position = Vector3(mid, 100.0, e)
				3:
					cs.position = Vector3(mid, 100.0, -e)
			body.add_child(cs)


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
	# The border's wall on its own layer (BORDER_LAYER): the hero and monsters stop at it, the
	# camera's arm doesn't (it would be pushed about near the border).
	var wall := StaticBody3D.new()
	wall.name = "BorderWall"
	wall.collision_layer = BORDER_LAYER
	wall.collision_mask = 0
	_build_border(wall)
	add_child(wall)


# --- the zone's landscape ----------------------------------------------------------------

static var force_feature := ""       ## test (--feature ridge|river|volcano|none): every zone gets it
const INTRUDE := 200.0               ## m the rim reaches in at most (its spurs)
const FEATURE_SAFE := 170.0          ## m round the settlement kept clear of ridges and rivers
## Per zone type: chances of a ridge, a river, a volcano (the rest: none of them).
const FEATURES := {
	"grassland": [0.35, 0.45, 0.0], "north": [0.5, 0.25, 0.0], "desert": [0.45, 0.15, 0.0],
	"ancient": [0.3, 0.45, 0.0], "mediterranean": [0.25, 0.2, 0.4], "unholy": [0.45, 0.2, 0.0],
}


func _plan_features(rng: RandomNumberGenerator, ztype: String) -> void:
	ridges.clear()
	rivers.clear()
	volcano = {}
	_rdist = PackedFloat32Array()
	var w: Array = FEATURES.get(ztype, FEATURES.grassland)
	var r := rng.randf()
	if force_feature != "":
		r = {"ridge": 0.0, "river": float(w[0]) + 0.0001, "volcano": float(w[0]) + float(w[1]) + 0.0001, "none": 2.0}.get(force_feature, r)
		if force_feature == "volcano":
			w = [w[0], w[1], 1.0]
	if r < float(w[0]):
		_plan_ridge(rng)
	elif r < float(w[0]) + float(w[1]):
		_plan_river(rng)
	elif r < float(w[0]) + float(w[1]) + float(w[2]):
		_plan_volcano(rng)


## A point on side `side` (0 +x, 1 -x, 2 +z, 3 -z), `inset` m in from the border, at `along`.
func _side_point(side: int, along: float, inset: float) -> Vector2:
	var e := HALF - inset
	match side:
		0:
			return Vector2(e, along)
		1:
			return Vector2(-e, along)
		2:
			return Vector2(along, e)
	return Vector2(along, -e)


## A winding line from a to b (midpoint displacement), kept FEATURE_SAFE m off the settlement.
func _wander(rng: RandomNumberGenerator, a: Vector2, b: Vector2, sway: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	for level in 4:
		var next := PackedVector2Array()
		for k in pts.size() - 1:
			var p := pts[k]
			var q := pts[k + 1]
			next.append(p)
			var m := (p + q) * 0.5
			var side := (q - p).orthogonal().normalized()
			m += side * rng.randf_range(-sway, sway) * p.distance_to(q)
			if m.length() < FEATURE_SAFE:
				m = m.normalized() * FEATURE_SAFE
			next.append(m)
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)


static func _line_dist(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for k in pts.size() - 1:
		best = minf(best, _seg_dist(p, pts[k], pts[k + 1]))
	return best


## A mountain ridge: from one side across the zone to another (or most of the way: a spur),
## never through the settlement; the roads cross it at passes.
func _plan_ridge(rng: RandomNumberGenerator) -> void:
	for tries in 30:
		var sa := rng.randi() % 4
		var sb := (sa + 1 + rng.randi() % 3) % 4
		var a := _side_point(sa, rng.randf_range(-HALF * 0.75, HALF * 0.75), 30.0)
		var b := _side_point(sb, rng.randf_range(-HALF * 0.75, HALF * 0.75), 30.0)
		if rng.randf() < 0.35:
			b = a.lerp(b, rng.randf_range(0.55, 0.75))          # a spur that stops in the open
		if _seg_dist(Vector2.ZERO, a, b) < FEATURE_SAFE + 40.0:
			continue
		ridges.append({"pts": _wander(rng, a, b, 0.18), "height": rng.randf_range(45.0, 75.0), "width": rng.randf_range(45.0, 70.0)})
		return


## A river: from the mountains on one side to those on another, winding, never through the
## settlement; shallow enough to wade (fords where roads cross).
func _plan_river(rng: RandomNumberGenerator) -> void:
	for tries in 30:
		var sa := rng.randi() % 4
		var sb := (sa + 1 + rng.randi() % 3) % 4
		var a := _side_point(sa, rng.randf_range(-HALF * 0.7, HALF * 0.7), 70.0)
		var b := _side_point(sb, rng.randf_range(-HALF * 0.7, HALF * 0.7), 70.0)
		if _seg_dist(Vector2.ZERO, a, b) < FEATURE_SAFE + 30.0:
			continue
		var raw := _wander(rng, a, b, 0.22)
		# Even spacing (~4 m) for the carving and the water's surface.
		var pts := PackedVector2Array([raw[0]])
		for k in raw.size() - 1:
			var p := raw[k]
			var q := raw[k + 1]
			var n := maxi(1, int(p.distance_to(q) / 4.0))
			for i in range(1, n + 1):
				pts.append(p.lerp(q, float(i) / n))
		rivers.append({"pts": pts, "levels": PackedFloat32Array(), "width": rng.randf_range(6.0, 9.0)})
		return


## A volcano (Mediterranean): a broad cone off to one side, away from the roads, its crater
## filled with glowing lava.
func _plan_volcano(rng: RandomNumberGenerator) -> void:
	for tries in 80:
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rng.randf_range(230.0, 300.0)
		var rad := rng.randf_range(120.0, 150.0)
		if _road_distance(c) < rad + 20.0:
			continue
		if maxf(absf(c.x), absf(c.y)) + rad * 1.3 > HALF - 60.0:
			continue                    # its foot and lava lake clear of the border's mountains
		volcano = {"center": c, "radius": rad, "height": rng.randf_range(85.0, 110.0), "crater": rng.randf_range(18.0, 24.0)}
		# Lava flows down the flank (the first, the main one, away from the village: it feeds the
		# lava lake beyond the foot), each its own wander.
		var away := c.angle()
		var flows: Array = []
		for f in rng.randi_range(1, 3):
			var ang := away + (0.0 if f == 0 else rng.randf_range(-2.4, 2.4))
			flows.append({"angle": ang, "wiggle": rng.randf_range(0.08, 0.2), "phase": rng.randf() * TAU,
				"width": rng.randf_range(3.0, 4.5), "main": f == 0})
		volcano["flows"] = flows
		volcano["lake_r"] = rng.randf_range(16.0, 22.0)
		return


func _in_volcano(p: Vector2, margin := 0.0) -> bool:
	return not volcano.is_empty() and p.distance_to(volcano.center) < float(volcano.radius) + margin


## The volcano's ash on the ground (0..1): all of the cone, fading out round its foot.
func _ash(x: float, z: float) -> float:
	if volcano.is_empty():
		return 0.0
	var d := Vector2(x, z).distance_to(volcano.center)
	if d > float(volcano.radius) * 1.7:
		return 0.0                                  # (far off: no flow or lake reaches here)
	var a := 1.0 - smoothstep(float(volcano.radius) * 0.8, float(volcano.radius) * 1.05, d)
	if volcano.has("lake"):
		var lk: Dictionary = volcano.lake
		a = maxf(a, 1.0 - smoothstep(float(lk.radius) + 6.0, float(lk.radius) + 30.0, Vector2(x, z).distance_to(lk.center)))
	for fl in volcano.get("flow_pts", []):
		a = maxf(a, 1.0 - smoothstep(8.0, 22.0, _line_dist(Vector2(x, z), fl)))
	return a


## How much mountain stands here (m above the land around: the border's range, a ridge; the
## volcano counts as all mountain). Camps and monsters keep to the low land.
func mountain(x: float, z: float) -> float:
	if _in_volcano(Vector2(x, z), 15.0):
		return 100.0
	if _mtn.is_empty():
		return 0.0
	return _mtn[_sample(x, z)]


## Whether a spot is low, flat land for `radius` m round it (a camp's tents, a group): no
## mountain, gentle slopes, no step in the ground.
func open_ground(x: float, z: float, radius: float) -> bool:
	var h0 := height_at(x, z)
	for r in [0.0, radius * 0.5, radius]:
		for k in (1 if r == 0.0 else 8):
			var a := TAU * k / 8.0
			var px: float = x + cos(a) * r
			var pz: float = z + sin(a) * r
			if mountain(px, pz) > 2.0 or normal_at(px, pz).y < 0.85 or absf(height_at(px, pz) - h0) > 3.0:
				return false
	return true


## Whether nothing grows here (the volcano's slopes).
func barren(x: float, z: float) -> bool:
	return _in_volcano(Vector2(x, z), -10.0)


## Adds ridges and the volcano to the heights and carves the rivers (after the base terrain,
## before the lakes). Only the samples near each feature are visited.
func _apply_features() -> void:
	for rd_ in ridges:
		var pts: PackedVector2Array = rd_.pts
		var hgt := float(rd_.height)
		var wid := float(rd_.width)
		var crest := FastNoiseLite.new()
		crest.seed = int(hgt * 1000.0)
		crest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		crest.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		crest.frequency = 1.0 / 90.0
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		# An end in the open (a spur's) tapers off; ends at the border run into the rim.
		var a_end := pts[0]
		var b_end := pts[pts.size() - 1]
		var a_open := absf(a_end.x) < HALF - 40.0 and absf(a_end.y) < HALF - 40.0
		var b_open := absf(b_end.x) < HALF - 40.0 and absf(b_end.y) < HALF - 40.0
		_each_sample(lo - Vector2(wid, wid), hi + Vector2(wid, wid), func(k: int, p: Vector2):
			var d := _line_dist(p, pts)
			if d >= wid:
				return
			var prof := pow(1.0 - smoothstep(0.0, wid, d), 1.4)
			var c := crest.get_noise_2d(p.x, p.y) * 0.5 + 0.5        # peaks and saddles along it
			var ends := 1.0
			if a_open:
				ends = minf(ends, smoothstep(0.0, 90.0, p.distance_to(a_end)))
			if b_open:
				ends = minf(ends, smoothstep(0.0, 90.0, p.distance_to(b_end)))
			var pass_ := smoothstep(6.0, 26.0, _road_distance(p))     # the roads go over passes
			var add := prof * hgt * (0.55 + 0.6 * c) * ends
			heights[k] += (add + _crags(p.x, p.y, add)) * pass_
			_mtn[k] += (add + _crags(p.x, p.y, add)) * pass_)
	if not volcano.is_empty():
		var c: Vector2 = volcano.center
		var rad := float(volcano.radius)
		var hgt := float(volcano.height)
		var cr := float(volcano.crater)
		var base := height_at(c.x, c.y)
		var top := base + hgt
		var rim_r := cr * 1.35                       # the crater's rim: the highest ring
		var depth := cr * 0.9
		volcano["floor"] = top - depth
		# Not a perfect cone: its foot wanders in and out with the direction, lumps on the slope,
		# gullies run down it, the rim is jagged with a breach where the main flow pours out.
		var vn := FastNoiseLite.new()
		vn.seed = int(rad * 977.0)
		vn.frequency = 1.0 / 40.0
		vn.fractal_octaves = 3
		var breach := float(volcano.flows[0].angle) if volcano.has("flows") else 0.0
		var rad_out := rad * 1.18
		_each_sample(c - Vector2(rad_out, rad_out), c + Vector2(rad_out, rad_out), func(k: int, p: Vector2):
			var v := p - c
			var d := v.length()
			var ang := v.angle()
			var foot := rad * (1.0 + 0.1 * sin(ang * 3.0 + rad) + 0.06 * sin(ang * 7.0 + 1.3) + 0.08 * vn.get_noise_1d(ang * 60.0))
			if d >= foot:
				return
			var h: float
			var rr := rim_r * (1.0 + 0.08 * sin(ang * 5.0 + 2.0))
			if d > rr:
				var u := (foot - d) / (foot - rr)        # 0 at the foot .. 1 at the rim
				var g := 1.0 - smoothstep(0.0, 0.5, u)
				h = heights[k] * g + base * (1.0 - g) + hgt * pow(u, 1.7)
				# Gullies down the flanks (deeper midway), lumps of old flows.
				var warp := vn.get_noise_2d(p.x, p.y) * 1.6
				var gully := pow(absf(sin(ang * 13.0 + warp)), 6.0)
				h -= gully * 5.5 * sin(PI * u) * smoothstep(0.0, 0.2, u)
				h += vn.get_noise_2d(p.x * 2.2, p.y * 2.2) * 5.0 * sin(PI * minf(u * 1.2, 1.0))
				# The rim: jagged, lower where the breach lets the main flow out.
				var notch := exp(-pow(angle_difference(ang, breach) / 0.22, 2.0))
				h -= (vn.get_noise_1d(ang * 90.0) * 0.5 + 0.5) * 4.0 * smoothstep(0.8, 1.0, u)
				h -= notch * 7.0 * smoothstep(0.75, 1.0, u)
			else:
				h = top - depth * (1.0 - pow(d / rr, 2.0)) - exp(-pow(angle_difference(ang, breach) / 0.22, 2.0)) * 7.0 * smoothstep(0.6, 1.0, d / rr)
			heights[k] = h)
		# Small side cones (vents) on the flanks.
		var vents: int = 1 + (int(rad) % 2)
		for vi in vents:
			var va := breach + PI * 0.75 + vi * 1.9
			var vd := rad * (0.55 + 0.12 * vi)
			var vc := c + Vector2(cos(va), sin(va)) * vd
			var vr := 22.0 - vi * 4.0
			var vh := 14.0 - vi * 3.0
			_each_sample(vc - Vector2(vr, vr), vc + Vector2(vr, vr), func(k: int, p: Vector2):
				var dd := p.distance_to(vc)
				if dd >= vr:
					return
				var cone := vh * pow(1.0 - dd / vr, 1.5)
				if dd < vr * 0.25:
					cone -= (1.0 - dd / (vr * 0.25)) * vh * 0.35          # its little crater
				heights[k] += cone)
		_lava_features()
	for rv in rivers:
		var pts: PackedVector2Array = rv.pts
		var wid := float(rv.width)
		# The water falls along the river: the ground under it, never rising downstream.
		var levels := PackedFloat32Array()
		var lvl := INF
		for p in pts:
			lvl = minf(lvl, height_at(p.x, p.y) - 1.0)
			levels.append(lvl)
		# Smoothed (no steps), still never rising.
		for pass_i in 3:
			for i in range(1, levels.size() - 1):
				levels[i] = minf(levels[i], (levels[i - 1] + levels[i] * 2.0 + levels[i + 1]) / 4.0)
		rv["levels"] = levels
		var reach := wid * 2.2
		var touched := _river_touched
		for k: int in touched:
			_rlevel[k] = lerpf(levels[_rseg[k]], levels[mini(_rseg[k] + 1, levels.size() - 1)], _rt[k])
		for k: int in touched:
			if _rdist[k] + wid >= reach:
				continue
			var i_ := k % N
			var j_ := k / N
			var p := Vector2(-HALF + i_ * STEP, -HALF + j_ * STEP)
			var level := _rlevel[k]
			var q := (_rdist[k] + wid) / wid
			var ford := 1.0 - smoothstep(4.0, 10.0, _road_distance(p)) if q < 2.2 else 0.0     # shallow where a road crosses
			var depth := lerpf(1.1, 0.45, ford)
			if q < 1.0:
				heights[k] = minf(heights[k], level - depth * (1.0 - q * q) - 0.15)
			else:
				var bank := level + 0.25 + (q - 1.0) * 1.6
				heights[k] = lerpf(minf(heights[k], bank), heights[k], smoothstep(1.0, 2.2, q))
			shore[k] = maxf(shore[k], 1.0 - smoothstep(0.8, 1.35, q))


## The river's distance field (before the heights: the border's spurs keep out of its valley):
## per sample near it the distance to its bank, its nearest segment and where along it. Each
## segment visits only the samples within VALLEY of it.
const VALLEY := 120.0
var _rseg := PackedInt32Array()
var _rt := PackedFloat32Array()
var _river_touched := {}


func _river_field() -> void:
	_rdist = PackedFloat32Array()
	_river_touched = {}
	if rivers.is_empty():
		return
	var rv: Dictionary = rivers[0]
	var pts: PackedVector2Array = rv.pts
	var wid := float(rv.width)
	_rdist.resize(N * N)
	_rdist.fill(INF)
	_rlevel.resize(N * N)
	_rseg.resize(N * N)
	_rt.resize(N * N)
	for sgi in pts.size() - 1:
		var a := pts[sgi]
		var b := pts[sgi + 1]
		_each_sample(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(VALLEY, VALLEY), Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(VALLEY, VALLEY), func(k: int, p: Vector2):
			var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a + (b - a) * t) - wid
			if d < _rdist[k]:
				_rdist[k] = d
				_rseg[k] = sgi
				_rt[k] = t
				if d < wid * 1.3:
					_river_touched[k] = true)


## The crags on `mountain` m of mountain at a point: up to about a fifth of it (no more than
## 14 m), nothing on the flat; ridged, so crests break and gullies cut in.
func _crags(x: float, z: float, mountain: float) -> float:
	if mountain < 1.0 or _crag == null:
		return 0.0
	var n := _crag.get_noise_2d(x + _crag_origin.x, z + _crag_origin.y) * 0.5 + 0.5
	var fine := _crag.get_noise_2d((x + _crag_origin.x) * 3.1, (z + _crag_origin.y) * 3.1) * 0.5 + 0.5
	var amt := minf(mountain * 0.22, 14.0) * smoothstep(1.0, 12.0, mountain)
	return (n * n - 0.3) * amt + (fine - 0.5) * amt * 0.25


## Calls f(sample index, zone-local point) for every height sample in the box lo..hi.
func _each_sample(lo: Vector2, hi: Vector2, f: Callable) -> void:
	var i0 := clampi(int((lo.x + HALF) / STEP), 0, N - 1)
	var i1 := clampi(int((hi.x + HALF) / STEP) + 1, 0, N - 1)
	var j0 := clampi(int((lo.y + HALF) / STEP), 0, N - 1)
	var j1 := clampi(int((hi.y + HALF) / STEP) + 1, 0, N - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			f.call(j * N + i, Vector2(-HALF + i * STEP, -HALF + j * STEP))


## Distance to the nearest river's bank (negative in it); INF without one.
func river_distance(x: float, z: float) -> float:
	if _rdist.is_empty():
		return INF
	return _rdist[_sample(x, z)]


## The river's water level over a point, or NAN when it isn't in a river.
func river_level(x: float, z: float) -> float:
	if _rdist.is_empty():
		return NAN
	var k := _sample(x, z)
	if _rdist[k] < float(rivers[0].width) * 0.3 and _rlevel[k] > height_at(x, z):
		return _rlevel[k]
	return NAN


## The nearest height sample's index.
func _sample(x: float, z: float) -> int:
	var i := clampi(roundi((x + HALF) / STEP), 0, N - 1)
	var j := clampi(roundi((z + HALF) / STEP), 0, N - 1)
	return j * N + i


## The rivers' water: a strip along each, at its level, a little wider than the bed (the banks
## hide its edge); ice in frozen lands.
func _build_rivers() -> void:
	for rv in rivers:
		var pts: PackedVector2Array = rv.pts
		var levels: PackedFloat32Array = rv.levels
		var w := float(rv.width) * 1.35
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var na := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).orthogonal().normalized() * w
			var nb := (pts[mini(i + 2, pts.size() - 1)] - pts[i]).orthogonal().normalized() * w
			var la := levels[i]
			var lb := levels[i + 1]
			var v0 := Vector3(a.x + na.x, la, a.y + na.y)
			var v1 := Vector3(a.x - na.x, la, a.y - na.y)
			var v2 := Vector3(b.x + nb.x, lb, b.y + nb.y)
			var v3 := Vector3(b.x - nb.x, lb, b.y - nb.y)
			for v in [v0, v1, v2, v1, v3, v2]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "River"
		if frozen:
			var ice := StandardMaterial3D.new()
			ice.albedo_color = Color(0.85, 0.92, 1.0)
			ice.roughness = 0.15
			ice.metallic_specular = 0.8
			mi.material_override = ice
		else:
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
			mi.material_override = mat
		add_child(mi)


## The volcano's crater: a pool of glowing lava, its light, and smoke rising.
func _build_volcano() -> void:
	if volcano.is_empty():
		return
	var c: Vector2 = volcano.center
	var lava := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = float(volcano.crater) * 0.9
	disc.bottom_radius = disc.top_radius
	disc.height = 0.05
	disc.radial_segments = 40
	lava.mesh = disc
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lava.gdshader")
	lava.material_override = m
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fl := float(volcano.floor) + 2.5             # the lava a little above the bowl's floor
	lava.position = Vector3(c.x, fl, c.y)
	lava.name = "Lava"
	add_child(lava)
	_build_lava(m)
	lava.visible = not OS.get_cmdline_user_args().has("--no-lava")       # test
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.12)
	light.light_energy = 6.0
	light.omni_range = 70.0
	light.position = Vector3(c.x, fl + 8.0, c.y)
	add_child(light)
	# The smoke: a tall plume rising from the crater (shaders/plume).
	var plume := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(110.0, 220.0)
	qm.center_offset = Vector3(0, 110.0, 0)
	plume.mesh = qm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/plume.gdshader")
	plume.material_override = pm
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.position = Vector3(c.x, fl - 2.0, c.y)
	plume.custom_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 260, 240))
	plume.name = "Plume"
	add_child(plume)


# --- the volcano's lava ------------------------------------------------------------------

## The lava flows (down the flank from the crater's rim, each in a shallow channel between low
## banks) and the lava lake (beyond the foot, fed by the main flow). Their paths, widths and the
## lava's surface go into `volcano` (flow_pts, flow_y, flow_w, lake).
func _lava_features() -> void:
	var c: Vector2 = volcano.center
	var rad := float(volcano.radius)
	var rim_r := float(volcano.crater) * 1.35
	var all_pts: Array = []
	var all_y: Array = []
	var all_w: Array = []
	for fl: Dictionary in volcano.flows:
		var ang := float(fl.angle)
		var reach := rad * (1.12 if fl.main else 0.95)
		var pts := PackedVector2Array()
		var d := rim_r + 1.0
		while d < reach:
			var a := ang + float(fl.wiggle) * sin(d / 22.0 + float(fl.phase)) + 0.05 * sin(d / 7.0)
			pts.append(c + Vector2(cos(a), sin(a)) * d)
			d += 4.0
		var wid := float(fl.width)
		var ys := PackedFloat32Array()
		for p in pts:
			ys.append(height_at(p.x, p.y) - 0.35)
		# The channel: a shallow trough, low banks (levees) either side.
		for sgi in pts.size() - 1:
			var a := pts[sgi]
			var b := pts[sgi + 1]
			var ya := ys[sgi]
			var yb := ys[sgi + 1]
			_each_sample(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(wid * 2.0, wid * 2.0), Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(wid * 2.0, wid * 2.0), func(k: int, p: Vector2):
				var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
				var q := p.distance_to(a + (b - a) * t) / wid
				var y := lerpf(ya, yb, t)
				if q < 1.0:
					heights[k] = minf(heights[k], y - 0.5 * (1.0 - q * q))
				elif q < 1.8:
					heights[k] = maxf(heights[k], lerpf(heights[k], y + 0.7, sin((q - 1.0) / 0.8 * PI) * 0.6)))
		all_pts.append(pts)
		all_y.append(ys)
		all_w.append(wid)
		if fl.main:
			# The lake: where the main flow ends, a bowl below the ground round it.
			var lc := pts[pts.size() - 1] + (pts[pts.size() - 1] - c).normalized() * float(volcano.lake_r) * 0.8
			var lr := float(volcano.lake_r)
			var lo_h := INF
			for kk in 16:
				var aa := TAU * kk / 16.0
				lo_h = minf(lo_h, height_at(lc.x + cos(aa) * lr, lc.y + sin(aa) * lr))
			var level := lo_h - 0.6
			volcano["lake"] = {"center": lc, "radius": lr, "level": level}
			_each_sample(lc - Vector2(lr * 1.6, lr * 1.6), lc + Vector2(lr * 1.6, lr * 1.6), func(k: int, p: Vector2):
				var q := p.distance_to(lc) / lr
				if q < 1.0:
					heights[k] = minf(heights[k], level - 1.5 * (1.0 - q * q) - 0.2)
				elif q < 1.6:
					var bank := level + 0.3 + (q - 1.0) * 2.0
					heights[k] = lerpf(minf(heights[k], bank), heights[k], smoothstep(1.0, 1.6, q)))
	volcano["flow_pts"] = all_pts
	volcano["flow_y"] = all_y
	volcano["flow_w"] = all_w


## Whether a point (zone-local, its height y) is in or right next to lava: the crater's pool, a
## flow, the lava lake (within LAVA_NEAR m of it, at most 3 m above its surface).
const LAVA_NEAR := 1.5


func lava_at(x: float, z: float, y: float) -> bool:
	if volcano.is_empty():
		return false
	var p := Vector2(x, z)
	var c: Vector2 = volcano.center
	if p.distance_to(c) > float(volcano.radius) * 1.6:
		return false
	var pool_y := float(volcano.floor) + 2.5
	if p.distance_to(c) < float(volcano.crater) * 0.9 + LAVA_NEAR and y < pool_y + 3.0:
		return true
	if volcano.has("lake"):
		var lk: Dictionary = volcano.lake
		if p.distance_to(lk.center) < float(lk.radius) + LAVA_NEAR and y < float(lk.level) + 3.0:
			return true
	var fps: Array = volcano.get("flow_pts", [])
	for i in fps.size():
		var pts: PackedVector2Array = fps[i]
		var ys: PackedFloat32Array = volcano.flow_y[i]
		var w := float(volcano.flow_w[i])
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
			if p.distance_to(a + (b - a) * t) < w + LAVA_NEAR and y < lerpf(ys[k], ys[k + 1], t) + 3.0:
				return true
	return false


## The lava's meshes: each flow a strip on its channel's surface, the lake a disc; glowing.
func _build_lava(m: ShaderMaterial) -> void:
	var fps: Array = volcano.get("flow_pts", [])
	for i in fps.size():
		var pts: PackedVector2Array = fps[i]
		var w := float(volcano.flow_w[i]) * 1.1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var na := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).orthogonal().normalized() * w
			var nb := (pts[mini(k + 2, pts.size() - 1)] - pts[k]).orthogonal().normalized() * w
			# On the channel's bed, a little above it (the strip follows the ground).
			var ya := height_at(a.x, a.y) + 0.25
			var yb := height_at(b.x, b.y) + 0.25
			var v0 := Vector3(a.x + na.x, ya, a.y + na.y)
			var v1 := Vector3(a.x - na.x, ya, a.y - na.y)
			var v2 := Vector3(b.x + nb.x, yb, b.y + nb.y)
			var v3 := Vector3(b.x - nb.x, yb, b.y - nb.y)
			for v in [v0, v1, v2, v1, v3, v2]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "LavaFlow"
		add_child(mi)
	if volcano.has("lake"):
		var lk: Dictionary = volcano.lake
		var lake := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(lk.radius) * 1.15
		disc.bottom_radius = disc.top_radius
		disc.height = 0.05
		disc.radial_segments = 40
		lake.mesh = disc
		lake.material_override = m
		lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lake.position = Vector3(lk.center.x, float(lk.level), lk.center.y)
		lake.name = "LavaLake"
		add_child(lake)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.45, 0.12)
		glow.light_energy = 4.0
		glow.omni_range = float(lk.radius) * 3.0
		glow.position = lake.position + Vector3(0, 6.0, 0)
		add_child(glow)
