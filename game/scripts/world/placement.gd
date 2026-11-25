class_name Placement
extends RefCounted
## Puts a generated model (about 1 unit, centered, Y up) into the world at a real size.


## Scales `n` so its largest horizontal side is `size` meters (or its height, when
## by_height), puts its bottom on the terrain at `pos` and turns it by `yaw`.
static func put_on_ground(n: Node3D, terrain: Terrain, pos: Vector3, size: float, yaw: float, by_height := false, sink := 0.05) -> void:
	var aabb := _aabb(n)
	var ref := aabb.size.y if by_height else maxf(aabb.size.x, aabb.size.z)
	var s := size / maxf(ref, 0.001)
	n.scale = Vector3.ONE * s
	n.rotation.y = yaw
	var c := aabb.get_center()
	var off := Basis(Vector3.UP, yaw) * Vector3(-c.x * s, 0, -c.z * s)
	# Lowest terrain point under the footprint, so nothing floats on slopes.
	var r := maxf(aabb.size.x, aabb.size.z) * s * 0.5
	var g := terrain.height_at(pos.x, pos.z)
	for k in 8:
		var a := TAU * k / 8
		g = minf(g, terrain.height_at(pos.x + cos(a) * r, pos.z + sin(a) * r))
	# Zone-local: the parent (settlement, spawner) sits at the zone's origin.
	n.position = Vector3(pos.x + off.x, g - aabb.position.y * s - sink, pos.z + off.z)


static func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Box collision over a placed model's footprint (a bit smaller than its bounds).
static func add_box_collision(n: Node3D, shrink := 0.8) -> void:
	var aabb := _aabb(n)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * shrink, aabb.size.y, aabb.size.z * shrink) * n.scale.x
	cs.shape = box
	body.add_child(cs)
	n.add_child(body)
	body.position = aabb.get_center()
	body.scale = Vector3.ONE / n.scale.x


static var _weathered := {}
static var _grime_shader: Shader


## Generated buildings and props look new and polished: their materials come with metallic
## 1.0 and a metal map (a sheen like painted metal) and clean, even colours. Made matte, with a
## weathering pass over them (shaders/grime.gdshader: dirt splashed up from the ground, rain
## streaks, mottled plaster), `strength` 0..1. Once per model (its materials are shared).
static func weather(n: Node, path: String, strength: float) -> void:
	var key := "%s@%.2f" % [path, strength]
	if _weathered.has(path):
		return
	_weathered[path] = true
	if _grime_shader == null:
		_grime_shader = load("res://shaders/grime.gdshader")
	var grime := ShaderMaterial.new()
	grime.shader = _grime_shader
	grime.set_shader_parameter("strength", strength)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			mat.metallic = 0.0
			mat.metallic_texture = null
			mat.metallic_specular = 0.3
			mat.roughness = 0.95
			if strength > 0.0:
				mat.next_pass = grime
