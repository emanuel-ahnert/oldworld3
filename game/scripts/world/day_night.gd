class_name DayNight
extends Node
## Day and night (design/game-design.md, 9): one day lasts PERIOD seconds. The sun arcs over
## the sky; after sunset a bluish moon lights the world at a third of the strength, so nights
## stay playable. Sky, fog and ambient light follow. The zone type sets the daytime colors
## (set_zone); the menu can switch the cycle off (fixed morning light).

const PERIOD := 2400.0            ## seconds per day (40 min)
const NIGHT_SKY := [Color(0.03, 0.05, 0.12), Color(0.1, 0.13, 0.24)]
const NIGHT_FOG := Color(0.12, 0.15, 0.24)
const DUSK := Color(1.0, 0.55, 0.3)
const NIGHT_AMBIENT := Color(0.3, 0.38, 0.58)
const DIST_FOG_END := 210.0       ## m: distance fog (all zone types but the deserts) full here
const DIST_FOG_MAX := 0.97        ## its opacity at the end: the rim mountains only a faint shape
const MOON_DIR := Vector3(-42, 150, 0)   ## degrees: the moonlight's rotation (high in the south)
const MOON_SIZE := 4.2            ## degrees across (the real moon: 0.5; a game sky wants it bigger)
const MOON_HALO := 2.6           ## the moon quad in moon diameters (its halo; moon.gdshader halo_size)
const FIXED := 0.36               ## time of day when the cycle is off (morning, sun at ~48°)

static var instance: DayNight

var time := 0.3                   ## 0 = midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset
var enabled := true
var sun: DirectionalLight3D
var env: Environment
var sky: ProceduralSkyMaterial
var _moon: MeshInstance3D
var _moon_mat: ShaderMaterial
var _moon_strength := 0.0
var _day := {"sun": Color(1, 0.96, 0.88), "energy": 1.3, "sky": [Color(0.32, 0.5, 0.78), Color(0.7, 0.78, 0.86)], "fog": Color(0.68, 0.76, 0.85)}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_zone(info: Dictionary) -> void:
	_day = {
		"sun": info.sun, "energy": 1.3 * float(info.get("sun_energy", 1.0)),
		"sky": info.get("sky", [Color(0.32, 0.5, 0.78), Color(0.7, 0.78, 0.86)]), "fog": info.fog,
		"fog_density": float(info.get("fog_density", 0.002)),
		"distance_fog": bool(info.get("distance_fog", true)), "fog_end": float(info.get("fog_end", DIST_FOG_END)),
		"night_fog": info.get("night_fog", NIGHT_FOG), "night_sky": info.get("night_sky", NIGHT_SKY),
	}
	apply()


## Sun height in degrees: up to 60° at noon, down to -60° at midnight; days a bit longer.
func elevation() -> float:
	var t := time if enabled else FIXED
	return sin(TAU * (t - 0.25)) * 60.0 + 8.0


var _applied_at := -1.0


func _process(dt: float) -> void:
	_moon_process()
	if not enabled:
		return
	time = fmod(time + dt / PERIOD, 1.0)
	# Changing the sky re-renders its radiance map: only every ~1.2 s of game time (cost: ~3 FPS
	# when done every frame).
	if absf(time - _applied_at) > 0.0005:
		apply()


func apply() -> void:
	if sun == null:
		return
	_applied_at = time
	var el := elevation()
	var day := smoothstep(-6.0, 10.0, el)            # 0 night .. 1 day
	var dusk := clampf(1.0 - absf(el - 4.0) / 14.0, 0.0, 1.0) * day   # orange near the horizon
	_moon_strength = 1.0 - smoothstep(-8.0, -1.0, el)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if el > -2.0 else DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	if el > -2.0:
		# The sun: east in the morning, west in the evening (yaw follows the time).
		var t := time if enabled else FIXED
		sun.rotation_degrees = Vector3(-maxf(el, 4.0), -35.0 - (t - 0.5) * 140.0, 0)
		var c: Color = _day.sun
		sun.light_color = c.lerp(DUSK, dusk * 0.7)
		sun.light_energy = float(_day.energy) * maxf(day, 0.5)
	else:
		# The moon, high in the south.
		sun.rotation_degrees = MOON_DIR
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.55
	var sk: Array = _day.sky
	var nsk: Array = _day.get("night_sky", NIGHT_SKY)
	sky.sky_top_color = (nsk[0] as Color).lerp(sk[0], day)
	sky.sky_horizon_color = (nsk[1] as Color).lerp(sk[1], day).lerp(DUSK, dusk * 0.45)
	sky.ground_horizon_color = sky.sky_horizon_color
	env.fog_light_color = (_day.get("night_fog", NIGHT_FOG) as Color).lerp(_day.fog, day).lerp(DUSK, dusk * 0.25)
	var low := World.fog_end > 0.0
	if low or bool(_day.get("distance_fog", true)):
		# Depth fog: dense toward the distance, so the mountains around a zone fade into it
		# (not in the deserts, whose clear air shows the dunes far off). Low quality: the world
		# ends in it (World.set_view). The sky's horizon takes the fog's color so the fogged land
		# runs into it without an edge.
		var end := float(_day.get("fog_end", DIST_FOG_END))
		if low:
			end = minf(end, World.fog_end)
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = end * (0.25 if low else 0.18)
		env.fog_depth_end = end
		env.fog_depth_curve = 1.0 if low else 1.4
		env.fog_density = 1.0 if low else DIST_FOG_MAX
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.0
		sky.sky_horizon_color = sky.sky_horizon_color.lerp(env.fog_light_color, 0.85 if low else 1.0)
		sky.ground_horizon_color = sky.sky_horizon_color
		if not low:
			# The fogged mountains have the horizon's color; a wide horizon band reaches up past
			# their tops, so they melt into the sky instead of standing out against its blue.
			sky.sky_curve = 0.45
		sky.ground_bottom_color = env.fog_light_color
	else:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_aerial_perspective = 0.35
		sky.sky_curve = 0.15
		env.fog_sky_affect = 1.0
		env.fog_density = float(_day.get("fog_density", 0.002))
		sky.ground_bottom_color = Color(0.25, 0.3, 0.2)
	# At night the sky is nearly black: a bluish ambient fill keeps the world readable.
	env.ambient_light_color = NIGHT_AMBIENT.lerp(Color(1, 0.85, 0.7), dusk * 0.5).lerp(Color.WHITE, day * (1.0 - dusk * 0.5))
	env.ambient_light_sky_contribution = lerpf(0.25, 1.0, day)
	env.ambient_light_energy = lerpf(0.85, 0.9, day)


## The moon in the sky at night, where its light comes from: a quad far out (inside the camera's
## far plane, so hills and trees in front hide it), facing the camera, not fogged. The sky's own
## disc for the light is off at night (that was the old moon: a blurry white spot).
func _moon_process() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or sun == null:
		return
	if _moon == null:
		_moon_mat = ShaderMaterial.new()
		_moon_mat.shader = load("res://shaders/moon.gdshader")
		_moon_mat.set_shader_parameter("disc", load("res://assets/sky/moon.png"))
		_moon_mat.set_shader_parameter("halo_size", MOON_HALO)
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_moon = MeshInstance3D.new()
		_moon.mesh = q
		_moon.material_override = _moon_mat
		_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_moon.extra_cull_margin = 16384.0
		add_child(_moon)
	_moon.visible = _moon_strength > 0.001
	if not _moon.visible:
		return
	var dir := Basis.from_euler(MOON_DIR * PI / 180.0).z          # toward the light's source
	var dist := cam.far * 0.85
	var across := 2.0 * dist * tan(deg_to_rad(MOON_SIZE) / 2.0) * MOON_HALO
	_moon.global_transform = Transform3D(Basis().scaled(Vector3(across, across, 1.0)), cam.global_position + dir * dist)
	_moon_mat.set_shader_parameter("strength", _moon_strength)


## "06:30" for the menu / HUD.
func clock() -> String:
	var t := time if enabled else FIXED
	var minutes := int(t * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
