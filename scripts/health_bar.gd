extends Node3D
# Small billboard health bar above a unit. Reads the parent unit's hp/max_hp
# and resizes a left-anchored fill quad. Built entirely in code (no texture
# import needed). The background and fill quads share a single origin so the
# per-quad billboard can never slide them apart, no matter how the camera or the
# parent unit rotates.

@export var bar_width: float = 0.9
@export var bar_height: float = 0.13
@export var height_above: float = 2.3   # local Y offset above the unit origin

var _fill: MeshInstance3D
var _fill_mesh: QuadMesh
var _fill_mat: StandardMaterial3D
var _target
var _last_frac: float = -1.0

func _ready() -> void:
	_target = get_parent()
	position.y = height_above
	_build()

func _build() -> void:
	# Just the colored fill quad — no background. We left-anchor by shrinking the
	# quad's own geometry (size + center_offset), never by moving the node, so the
	# bar grows/shrinks from a fixed left edge while billboarding to the camera.
	_fill = MeshInstance3D.new()
	_fill_mesh = QuadMesh.new()
	_fill_mesh.size = Vector2(bar_width, bar_height * 0.74)
	_fill_mat = _make_mat(Color(0.25, 0.85, 0.25, 1.0), 1)
	_fill.mesh = _fill_mesh
	_fill.material_override = _fill_mat
	add_child(_fill)

func _make_mat(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priority   # fill (1) always draws over background (0)
	return m

func _process(_delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var maxhp: float = _target.max_hp
	var cur: float = _target.hp
	var frac: float = 0.0
	if maxhp > 0.0:
		frac = clampf(cur / maxhp, 0.0, 1.0)
	if is_equal_approx(frac, _last_frac):
		return   # hp only changes on a hit; skip the rebuild on unchanged frames
	_last_frac = frac
	# Shrink the quad from the right while pinning its left edge: narrow the mesh
	# and push its geometry left by the same half-amount. The node origin stays at
	# (0,0,0), coincident with the background, so the billboards never separate.
	_fill_mesh.size = Vector2(bar_width * frac, bar_height * 0.74)
	_fill_mesh.center_offset = Vector3(-bar_width * 0.5 * (1.0 - frac), 0.0, 0.0)
	# Green when healthy, red when low.
	_fill_mat.albedo_color = Color(0.85, 0.2, 0.2).lerp(Color(0.25, 0.85, 0.25), frac)
