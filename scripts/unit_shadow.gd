extends Node3D
## Cheap fake "blob" shadow — a flat dark circle on the ground under a unit. No
## real-time shadow maps: one soft-circle texture + material + mesh are built ONCE
## and shared by every unit, so adding shadows to a whole army is essentially free.
##
## Add as a child of a unit in its _ready(): it inherits the unit's scale, so bigger
## units (giant) get a bigger shadow automatically.

@export var size: float = 2.0     # shadow diameter in the unit's local space
@export var height: float = 0.03  # lift off the ground to avoid z-fighting with the grass

# Shared across all instances (built on first use, kept for the whole session).
static var _mesh: PlaneMesh = null
static var _mat: StandardMaterial3D = null

func _ready() -> void:
	_ensure_shared()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.position = Vector3(0.0, height, 0.0)
	mi.scale = Vector3(size, 1.0, size)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

static func _ensure_shared() -> void:
	if _mesh != null:
		return
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(1.0, 1.0)   # 1x1 in XZ, normal +Y — already flat on the ground
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # constant dark, ignores lighting
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = _make_shadow_tex(64)
	_mat.albedo_color = Color(1, 1, 1, 1)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

# A soft radial circle: opaque-ish black at the centre, fading to transparent at the rim.
static func _make_shadow_tex(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) - c, float(y) - c).length() / r   # 0 centre .. 1 rim
			# Solid dark core (inner ~60% fully opaque-ish) with a soft feathered rim.
			var a := clampf((1.0 - dist) * 1.7, 0.0, 1.0) * 0.6   # max ~0.6 alpha
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	return ImageTexture.create_from_image(img)
