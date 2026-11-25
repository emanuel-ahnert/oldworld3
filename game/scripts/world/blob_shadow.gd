class_name BlobShadow
extends MeshInstance3D
## A round dark spot on the ground under a unit (old WoW style): stands in for real shadows on
## Low quality, where the sun casts none (GameMenu.apply_quality). Stays on the terrain when the
## unit jumps, and gets smaller and lighter the higher the unit is above it.

static var enabled := false        ## true while sun shadows are off
static var _mat: StandardMaterial3D
static var _mesh: PlaneMesh

var radius := 0.5


## Adds a blob under `unit` (its origin at the feet).
static func attach(unit: Node3D, p_radius: float) -> BlobShadow:
	var b := BlobShadow.new()
	b.radius = p_radius
	unit.add_child(b)
	return b


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(0, 0, 0, 0.72)
		_mat.disable_receive_shadows = true
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(0.55, 1.0, d)))
		var tex := ImageTexture.create_from_image(img)
		_mat.albedo_texture = tex
		_mesh = PlaneMesh.new()             # faces up
		_mesh.size = Vector2(2, 2)
	mesh = _mesh
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true                     # placed on the ground, not carried up by jumps


func _process(_dt: float) -> void:
	var unit := get_parent() as Node3D
	visible = enabled and unit.visible
	if not visible:
		return
	var p := unit.global_position
	var ground := World.height_at(p.x, p.z) if World.zones else p.y
	var lift := clampf((p.y - ground) / 3.0, 0.0, 0.7)
	var r := radius * (1.0 - lift * 0.6)
	global_transform = Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(p.x, ground + 0.04, p.z))
	transparency = lift
