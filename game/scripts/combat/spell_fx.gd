class_name SpellFx
extends RefCounted
## Spell visuals, all built in code: projectiles by element (a fireball with a flame trail, an
## ice shard, a shadow bolt trailing smoke, a holy orb with sparkles, a thorn with leaves, a
## crackling storm bolt, a water orb), impacts (a burst and a flash of light), the glow gathering
## in a caster's hand, rune circles on the ground, Moonbeam's column of light, and Hellfire
## Rain (its area marked by a burning circle, then meteors falling into it).

const COLORS := {
	"Fire": Color(1.0, 0.45, 0.1), "Ice": Color(0.55, 0.85, 1.0), "Water": Color(0.3, 0.6, 1.0),
	"Nature": Color(0.45, 0.9, 0.3), "Air": Color(0.7, 0.85, 1.0), "Holy": Color(1.0, 0.9, 0.5),
	"Dark": Color(0.65, 0.3, 1.0), "Physical": Color(0.9, 0.9, 0.9),
}

static var _glow: Texture2D
static var _mats := {}


static func color(element: String) -> Color:
	return COLORS.get(element, Color.WHITE)


## A soft round dot (particles and glows).
static func glow_tex() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow = t
	return _glow


## Billboard material for particles and glows: additive (light) or mixed (smoke).
static func _sprite_mat(additive: bool) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = glow_tex()
		m.no_depth_test = false
		m.disable_receive_shadows = true
		_mats[key] = m
	return _mats[key]


static func _emissive(c: Color, energy := 3.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A particle emitter of soft dots. `colors`: start and end colour (alpha fades along).
static func particles(amount: int, life: float, size: float, c0: Color, c1: Color, additive := true,
		spread := 180.0, speed := Vector2(0.2, 0.8), gravity := Vector3.ZERO, box := 0.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.spread = spread
	pm.direction = Vector3.UP
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = gravity
	if box > 0.0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = box
	var ramp := Gradient.new()
	ramp.set_color(0, c0)
	ramp.set_color(1, Color(c1.r, c1.g, c1.b, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.3))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _sprite_mat(additive)
	p.draw_pass_1 = q
	return p


## A glowing ball (billboarded) of `size` m.
static func orb(c: Color, size: float, energy := 2.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := _sprite_mat(true).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = false
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, 1.0)
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A crystal or thorn pointing along -Z: two cones base to base.
static func shard(c: Color, length: float, radius: float, sides := 6, energy := 1.5, alpha := 0.85) -> Node3D:
	var n := Node3D.new()
	var mat := _emissive(c, energy, alpha)
	for front in [true, false]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = radius
		cm.height = length * (0.7 if front else 0.3)
		cm.radial_segments = sides
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# +Y -> -Z (front) or +Z (back); the bases meet at the origin.
		mi.rotation.x = -PI / 2 if front else PI / 2
		mi.position.z = -cm.height / 2 if front else cm.height / 2
		n.add_child(mi)
	return n


## The flying part of a spell: its look by element. Trails are the GPUParticles3D children
## (Projectile leaves them behind to fade when it hits).
static func bolt(element: String) -> Node3D:
	var n := Node3D.new()
	var c := color(element)
	match element:
		"Fire":
			n.add_child(Tail.make(Color(1.0, 0.4, 0.06), 0.42, 0.3))
			n.add_child(orb(Color(1.0, 0.75, 0.3), 0.55, 3.0))
			n.add_child(orb(Color(1.0, 0.95, 0.7), 0.25, 3.0))
			n.add_child(particles(160, 0.35, 0.18, Color(1.0, 0.7, 0.25, 0.6), Color(0.9, 0.15, 0.02), true, 60.0, Vector2(0.4, 1.2), Vector3(0, 1.5, 0), 0.18))
			n.add_child(particles(50, 0.8, 0.4, Color(0.25, 0.2, 0.18, 0.45), Color(0.1, 0.1, 0.1), false, 40.0, Vector2(0.2, 0.5), Vector3(0, 1.0, 0), 0.08))
		"Ice":
			n.add_child(Tail.make(c, 0.16, 0.25))
			n.add_child(shard(c, 0.7, 0.09, 6, 1.8))
			n.add_child(orb(c, 0.35, 1.5))
			n.add_child(particles(30, 0.5, 0.15, Color(0.85, 0.95, 1.0, 1), c, true, 60.0, Vector2(0.1, 0.4), Vector3(0, -1.0, 0), 0.1))
		"Water":
			n.add_child(Tail.make(c, 0.3, 0.3))
			n.add_child(orb(c, 0.5, 2.0))
			n.add_child(particles(30, 0.5, 0.14, Color(0.7, 0.85, 1.0, 1), c, true, 60.0, Vector2(0.2, 0.6), Vector3(0, -4.0, 0), 0.12))
		"Nature":
			n.add_child(Tail.make(c, 0.12, 0.3))
			n.add_child(shard(Color(0.35, 0.6, 0.2), 0.6, 0.05, 4, 1.0, 1.0))
			n.add_child(orb(c, 0.3, 1.6))
			n.add_child(particles(24, 0.7, 0.16, Color(0.5, 1.0, 0.35, 1), Color(0.2, 0.6, 0.1), true, 90.0, Vector2(0.2, 0.7), Vector3(0, -1.5, 0), 0.15))
		"Air":
			n.add_child(Tail.make(Color(0.75, 0.85, 1.0), 0.2, 0.2))
			n.add_child(orb(Color(0.8, 0.9, 1.0), 0.45, 3.5))
			n.add_child(orb(Color(1, 1, 1), 0.18, 4.0))
			var arcs := Crackle.new()
			arcs.tint = Color(0.75, 0.85, 1.0)
			n.add_child(arcs)
			n.add_child(particles(30, 0.3, 0.12, Color(0.9, 0.95, 1.0, 1), c, true, 180.0, Vector2(0.5, 1.5), Vector3.ZERO, 0.1))
		"Holy":
			n.add_child(Tail.make(c, 0.35, 0.35))
			n.add_child(orb(c, 0.6, 2.5))
			n.add_child(orb(Color(1, 1, 0.9), 0.22, 3.0))
			n.add_child(particles(36, 0.6, 0.12, Color(1.0, 0.97, 0.75, 1), c, true, 180.0, Vector2(0.2, 0.6), Vector3(0, 0.5, 0), 0.2))
		"Dark":
			n.add_child(Tail.make(Color(0.5, 0.18, 0.9), 0.4, 0.45))
			n.add_child(orb(Color(0.55, 0.2, 0.95), 0.6, 2.0))
			n.add_child(orb(Color(0.08, 0.02, 0.12), 0.3, 1.0))
			n.add_child(particles(40, 0.7, 0.45, Color(0.18, 0.05, 0.25, 0.8), Color(0.05, 0.0, 0.08), false, 40.0, Vector2(0.1, 0.4), Vector3(0, 0.6, 0), 0.12))
			n.add_child(particles(24, 0.4, 0.2, Color(0.75, 0.4, 1.0, 1), c, true, 60.0, Vector2(0.2, 0.6), Vector3.ZERO, 0.15))
		_:
			n.add_child(orb(c, 0.4, 2.5))
	return n


## Whether bolt(element) has a direction (a shard or thorn turns along its path).
static func pointed(element: String) -> bool:
	return element in ["Ice", "Nature"]


## A spell landing: a burst of particles and a short flash of light, cleaned up after.
static func impact(pos: Vector3, element: String, scale := 1.0) -> void:
	var c := color(element)
	var n := Node3D.new()
	World.root.add_child(n)
	n.global_position = pos
	var burst := particles(int(28 * scale), 0.5, 0.3 * scale, Color(minf(c.r * 1.2, 1), minf(c.g * 1.2, 1), minf(c.b * 1.2, 1), 0.75), c,
		true, 180.0, Vector2(1.5, 4.0) * scale, Vector3(0, -3.0, 0) if element != "Dark" else Vector3(0, 1, 0), 0.1)
	burst.one_shot = true
	burst.explosiveness = 0.95
	n.add_child(burst)
	burst.emitting = true
	if element in ["Fire", "Dark"]:
		var smoke := particles(int(12 * scale), 1.0, 0.7 * scale, Color(0.2, 0.18, 0.16, 0.5), Color(0.1, 0.1, 0.1), false,
			180.0, Vector2(0.3, 1.0) * scale, Vector3(0, 1.0, 0), 0.2)
		smoke.one_shot = true
		smoke.explosiveness = 0.9
		n.add_child(smoke)
		smoke.emitting = true
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 4.0 * scale
	light.omni_range = 4.0 * scale
	light.shadow_enabled = false
	n.add_child(light)
	var tw := n.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_interval(1.0)
	tw.tween_callback(n.queue_free)


## A meteor's blast: flames (orange to deep red) and sparks, rising smoke, a ring of heat
## running out over the ground, a flash of light and a scorch mark that fades.
static func explosion(at: Vector3) -> void:
	var n := Node3D.new()
	World.root.add_child(n)
	n.global_position = at
	var parts: Array[GPUParticles3D] = [
		particles(36, 0.6, 0.9, Color(1.0, 0.45, 0.08, 0.7), Color(0.55, 0.05, 0.0), true, 70.0, Vector2(2.0, 5.0), Vector3(0, -2.0, 0), 0.4),
		particles(30, 0.9, 0.18, Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.3, 0.0), true, 80.0, Vector2(5.0, 10.0), Vector3(0, -9.0, 0), 0.2),
		particles(18, 2.2, 2.0, Color(0.14, 0.1, 0.08, 0.6), Color(0.06, 0.06, 0.06), false, 50.0, Vector2(0.8, 2.0), Vector3(0, 0.8, 0), 0.6),
	]
	for p in parts:
		p.one_shot = true
		p.explosiveness = 0.9
		p.position.y = 0.4
		n.add_child(p)
		p.emitting = true
	# The heat ring on the ground.
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_texture = _ring_tex()
	rm.albedo_color = Color(1.0, 0.45, 0.1, 1.0)
	ring.material_override = rm
	ring.position.y = 0.12
	ring.scale = Vector3.ONE * 0.5
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	# The scorch mark.
	var scorch := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(2.6, 2.6)
	sq.orientation = PlaneMesh.FACE_Y
	scorch.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = glow_tex()
	sm.albedo_color = Color(0.05, 0.03, 0.02, 0.85)
	scorch.material_override = sm
	scorch.position.y = 0.07
	scorch.rotation.y = randf() * TAU
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(scorch)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 7.0
	light.omni_range = 7.0
	light.position.y = 1.0
	n.add_child(light)
	var tw := n.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3.ONE * 6.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rm, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_property(sm, "albedo_color:a", 0.0, 3.0).set_delay(1.5)
	tw.chain().tween_callback(n.queue_free)


static var _ring: Texture2D


## A thin bright ring fading inward and outward (the heat ring of an explosion).
static func _ring_tex() -> Texture2D:
	if _ring == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 0.85, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_ring = t
	return _ring


## Light gathering in a caster's hand while casting (attach it to the hand).
static func hand_glow(element: String) -> Node3D:
	var c := color(element)
	var n := Node3D.new()
	n.add_child(orb(c, 0.3, 2.5))
	n.add_child(orb(Color(1, 1, 1), 0.1, 3.0))
	var swirl := particles(24, 0.6, 0.1, Color(minf(c.r * 1.3, 1), minf(c.g * 1.3, 1), minf(c.b * 1.3, 1), 1), c, true, 180.0, Vector2(0.1, 0.3), Vector3(0, 0.4, 0), 0.25)
	n.add_child(swirl)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.2
	light.omni_range = 2.5
	n.add_child(light)
	return n


## A rune circle lying on the ground, `radius` m, turning.
static func rune(c: Color, radius: float, fill := 0.12, spin := 0.3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rune.gdshader")
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("spin", spin)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Moonbeam: a column of pale light falling onto `pos`, a flash where it lands.
static func beam(pos: Vector3, element := "Holy") -> void:
	var c := Color(0.75, 0.85, 1.0) if element == "Holy" else color(element)
	var n := Node3D.new()
	World.root.add_child(n)
	n.global_position = pos
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.6
	cm.height = 24.0
	cm.cap_top = false
	cm.cap_bottom = false
	col.mesh = cm
	var mat := _emissive(c, 2.5, 0.35)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	col.material_override = mat
	col.position.y = 12.0
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(col)
	var core := col.duplicate() as MeshInstance3D
	core.scale = Vector3(0.35, 1, 0.35)
	n.add_child(core)
	var r := rune(c, 1.8, 0.4, 0.6)
	r.position.y = 0.06
	n.add_child(r)
	var dust := particles(40, 1.0, 0.18, Color(0.9, 0.95, 1.0, 1), c, true, 20.0, Vector2(1.0, 3.0), Vector3.ZERO, 0.6)
	n.add_child(dust)
	impact(pos + Vector3(0, 0.8, 0), element)
	var tw := n.create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.parallel().tween_property(r.material_override, "shader_parameter/strength", 0.0, 0.5)
	tw.tween_callback(func(): dust.emitting = false)
	tw.tween_interval(1.0)
	tw.tween_callback(n.queue_free)


## Hellfire Rain's marker while it is cast: a burning circle the size of the area, glowing in,
## following `follow` (the target) until the spell goes off. Returns it (free it when done).
static func area_marker(radius: float, c := Color(1.0, 0.35, 0.05)) -> Node3D:
	var n := Node3D.new()
	var r := rune(c, radius, 0.22, 0.15)
	r.position.y = 0.08
	n.add_child(r)
	var embers := particles(60, 1.4, 0.22, Color(1.0, 0.6, 0.2, 1), Color(0.8, 0.1, 0.0), true, 15.0, Vector2(0.5, 1.6), Vector3(0, 0.5, 0), radius * 0.8)
	(embers.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	(embers.process_material as ParticleProcessMaterial).emission_ring_radius = radius * 0.95
	(embers.process_material as ParticleProcessMaterial).emission_ring_inner_radius = radius * 0.6
	(embers.process_material as ParticleProcessMaterial).emission_ring_height = 0.1
	(embers.process_material as ParticleProcessMaterial).emission_ring_axis = Vector3.UP
	n.add_child(embers)
	r.material_override.set_shader_parameter("strength", 0.0)
	n.create_tween().tween_property(r.material_override, "shader_parameter/strength", 1.0, 0.4)
	return n


## Hellfire Rain: meteors falling from the sky into the circle at `center` (`radius` m) over
## about a second and a half, each with a flame trail and a burst where it lands; the circle
## flares and burns out. `on_first_land` is called when the first wave lands (the damage).
static func hellfire(center: Vector3, radius: float, on_first_land: Callable, meteors := 16) -> void:
	var n := Node3D.new()
	World.root.add_child(n)
	n.global_position = center
	var r := rune(Color(1.0, 0.3, 0.04), radius, 0.35, 0.4)
	r.position.y = 0.08
	n.add_child(r)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.4, 0.1)
	glow.light_energy = 2.5
	glow.omni_range = radius * 1.6
	glow.position.y = 2.0
	n.add_child(glow)
	var tree := n.get_tree()
	var first := true
	for i in meteors:
		var a := randf() * TAU
		var d := sqrt(randf()) * radius * 0.92
		var land := center + Vector3(cos(a) * d, 0, sin(a) * d)
		land.y = World.height_at(land.x, land.z)
		var delay := 0.08 * i + randf() * 0.1
		var cb := on_first_land if first else Callable()
		first = false
		tree.create_timer(delay).timeout.connect(func(): _meteor(land, cb))
	var tw := n.create_tween()
	tw.tween_interval(0.08 * meteors + 0.8)
	tw.tween_property(r.material_override, "shader_parameter/strength", 0.0, 0.8)
	tw.parallel().tween_property(glow, "light_energy", 0.0, 0.8)
	tw.tween_callback(n.queue_free)


static func _meteor(land: Vector3, on_land: Callable) -> void:
	var m := Node3D.new()
	World.root.add_child(m)
	# From high up and a little to the side, so it comes down at a slant.
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 6.0
	var from := land + Vector3(0, 22.0, 0) + side
	m.global_position = from
	m.add_child(Tail.make(Color(0.85, 0.18, 0.02), 1.1, 0.35))
	m.add_child(orb(Color(1.0, 0.35, 0.05), 1.3, 1.6))
	m.add_child(orb(Color(1.0, 0.75, 0.35), 0.5, 2.0))
	m.add_child(particles(70, 0.45, 0.6, Color(1.0, 0.4, 0.06, 0.55), Color(0.5, 0.04, 0.0), true, 25.0, Vector2(0.3, 1.0), Vector3(0, 2.0, 0), 0.3))
	m.add_child(particles(30, 1.3, 1.3, Color(0.12, 0.08, 0.06, 0.6), Color(0.05, 0.05, 0.05), false, 30.0, Vector2(0.2, 0.6), Vector3(0, 1.0, 0), 0.3))
	var fall := 0.45 + randf() * 0.15
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", land + Vector3(0, 0.3, 0), fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		explosion(land)
		Audio.sfx("fireball", -10.0)
		if on_land.is_valid():
			on_land.call()
		# The trails stay where they are and fade.
		for c in m.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
			elif c is Tail:
				(c as Tail).stop()
			else:
				c.queue_free())
	tw.tween_interval(1.3)
	tw.tween_callback(m.queue_free)


## A continuous glowing ribbon behind a moving spell: the path of the last `life` seconds,
## facing the camera, tapering and fading toward its end. It draws in world space; when its
## spell lands, stop() lets it shrink away on its own.
class Tail extends MeshInstance3D:
	var tint := Color.WHITE
	var width := 0.3
	var life := 0.3
	var _pts: Array = []          ## [time, position]
	var _im := ImmediateMesh.new()
	var _stopped := false

	static func make(c: Color, w: float, l: float) -> Tail:
		var t := Tail.new()
		t.tint = c
		t.width = w
		t.life = l
		return t

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		mesh = _im
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func stop() -> void:
		_stopped = true

	func _process(_dt: float) -> void:
		var now := Time.get_ticks_msec() / 1000.0
		if not _stopped:
			_pts.append([now, (get_parent() as Node3D).global_position])
		while not _pts.is_empty() and now - float(_pts[0][0]) > life:
			_pts.pop_front()
		_im.clear_surfaces()
		if _pts.size() < 2:
			if _stopped:
				queue_free()
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var n := _pts.size()
		for i in n:
			var p: Vector3 = _pts[i][1]
			var along: Vector3 = (_pts[mini(i + 1, n - 1)][1] - _pts[maxi(i - 1, 0)][1])
			var side := along.cross(cam.global_position - p).normalized()
			var k := 1.0 - clampf((now - float(_pts[i][0])) / life, 0.0, 1.0)   # 1 at the head
			var w := width * (0.15 + 0.85 * k)
			var col := Color(tint.r * 1.3, tint.g * 1.3, tint.b * 1.3, k * k * k)
			_im.surface_set_color(col)
			_im.surface_add_vertex(p + side * w * 0.5)
			_im.surface_set_color(col)
			_im.surface_add_vertex(p - side * w * 0.5)
		_im.surface_end()


## Blizzard (mage, channelled): over the circle at `center` an icy rune lies on the ground,
## snow drives down slanting, ice shards crash into it and burst, frost mist swirls low, and a
## cold light hangs over it, until stop().
class Blizzard extends Node3D:
	var radius := 8.0
	var _rune: MeshInstance3D
	var _emitters: Array[GPUParticles3D] = []
	var _light: OmniLight3D
	var _next_shard := 0.0
	var _stopped := false

	static func start(at: Vector3, r: float) -> Blizzard:
		var b := Blizzard.new()
		b.radius = r
		World.root.add_child(b)
		b.global_position = at
		return b

	func _ready() -> void:
		var ice := Color(0.6, 0.85, 1.0)
		_rune = SpellFx.rune(ice, radius, 0.2, 0.12)
		_rune.position.y = 0.08
		_rune.material_override.set_shader_parameter("strength", 0.0)
		add_child(_rune)
		create_tween().tween_property(_rune.material_override, "shader_parameter/strength", 1.0, 0.5)
		# Snow driving down at a slant over the whole circle.
		var snow := SpellFx.particles(1100, 1.3, 0.22, Color(0.95, 0.98, 1.0, 0.9), Color(0.8, 0.9, 1.0), true, 8.0, Vector2(9.0, 13.0), Vector3(2.5, -6.0, 1.0))
		var sm := snow.process_material as ParticleProcessMaterial
		sm.direction = Vector3(0.25, -1, 0.1)
		sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		sm.emission_box_extents = Vector3(radius * 0.85, 0.5, radius * 0.85)
		snow.position.y = 13.0
		snow.visibility_aabb = AABB(Vector3(-radius - 4, -16, -radius - 4), Vector3(radius * 2 + 8, 20, radius * 2 + 8))
		# Frost mist swirling low over the ground.
		var mist := SpellFx.particles(70, 2.2, 2.6, Color(0.75, 0.88, 1.0, 0.22), Color(0.6, 0.75, 0.9), false, 180.0, Vector2(0.2, 0.6), Vector3.ZERO)
		var mm := mist.process_material as ParticleProcessMaterial
		mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		mm.emission_ring_axis = Vector3.UP
		mm.emission_ring_radius = radius * 0.8
		mm.emission_ring_inner_radius = radius * 0.1
		mm.emission_ring_height = 0.2
		mm.orbit_velocity_min = 0.08
		mm.orbit_velocity_max = 0.15
		mist.position.y = 0.5
		for p in [snow, mist]:
			add_child(p)
			_emitters.append(p)
		_light = OmniLight3D.new()
		_light.light_color = ice
		_light.light_energy = 0.0
		_light.omni_range = radius * 1.6
		_light.position.y = 3.0
		add_child(_light)
		create_tween().tween_property(_light, "light_energy", 2.0, 0.5)

	func _process(_dt: float) -> void:
		if _stopped:
			return
		var t := Time.get_ticks_msec() / 1000.0
		if t >= _next_shard:
			_next_shard = t + randf_range(0.08, 0.18)
			_shard()

	## An ice shard crashing down at a random spot of the circle.
	func _shard() -> void:
		var a := randf() * TAU
		var d := sqrt(randf()) * radius * 0.9
		var land := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
		land.y = World.height_at(land.x, land.z)
		var from := land + Vector3(-3.0, 15.0, -1.2)
		var s := SpellFx.shard(Color(0.7, 0.9, 1.0), randf_range(1.0, 1.6), 0.13, 6, 1.8)
		World.root.add_child(s)
		s.global_position = from
		s.global_basis = Basis.looking_at((land - from).normalized())
		var tw := s.create_tween()
		tw.tween_property(s, "global_position", land + Vector3(0, 0.2, 0), randf_range(0.45, 0.6)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			SpellFx.impact(land + Vector3(0, 0.3, 0), "Ice", 1.0)
			s.queue_free())

	## The channel ended: the snow stops, the circle and the light fade.
	func stop() -> void:
		if _stopped:
			return
		_stopped = true
		for p in _emitters:
			p.emitting = false
		var tw := create_tween().set_parallel()
		tw.tween_property(_rune.material_override, "shader_parameter/strength", 0.0, 0.8)
		tw.tween_property(_light, "light_energy", 0.0, 0.8)
		tw.chain().tween_interval(2.0)
		tw.chain().tween_callback(queue_free)


## Lightning crackling around a storm bolt: a few jagged arcs, redrawn every frame.
class Crackle extends MeshInstance3D:
	var tint := Color(0.8, 0.9, 1.0)
	var _im := ImmediateMesh.new()

	func _ready() -> void:
		mesh = _im
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(tint.r * 3.0, tint.g * 3.0, tint.b * 3.0)
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _process(_dt: float) -> void:
		_im.clear_surfaces()
		_im.surface_begin(Mesh.PRIMITIVE_LINES)
		for arc in 3:
			var p := Vector3.ZERO
			var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			for k in 4:
				var q := p + (dir + Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))).normalized() * 0.18
				_im.surface_add_vertex(p)
				_im.surface_add_vertex(q)
				p = q
		_im.surface_end()
