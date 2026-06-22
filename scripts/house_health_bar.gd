extends Node3D
## Big billboarded health bar floating above a house — the match objective, so
## unlike the minimal unit bar this one has a dark backing and a team-colored
## frame to read as important. It ramps green -> amber -> red and pulses (flash +
## size throb) once the house drops into the danger zone.
##
## The three quads (frame / backing / fill) all share THIS node's origin so the
## per-quad billboards can never slide apart; layering is done with render_priority
## + no_depth_test, exactly like the unit health bar.
##
## Contract: bind(house) is called by the battle manager BEFORE add_child().
## We are deliberately NOT a child of the house — the house is scaled ~8x and we
## don't want to inherit that — so each frame we park ourselves above it in world
## space. The house exposes: var hp, var max_hp, var alive, var team.

@export var bar_width: float = 4.2
@export var bar_height: float = 0.52
@export var margin_above: float = 2.4    # world units above the house's mesh top

const DANGER_FRAC := 0.30
const FRAME := 0.13        # team-colored frame thickness around the backing (world units)
const BACK_PAD := 0.07     # dark backing padding around the fill (world units)

const COL_GREEN := Color(0.25, 0.85, 0.25)
const COL_AMBER := Color(0.95, 0.75, 0.15)
const COL_RED   := Color(0.90, 0.18, 0.18)

var _house = null         # the house (base.gd); untyped for cross-script duck typing
var _top_y: float = 0.0
var _t: float = 0.0

var _frame: MeshInstance3D
var _frame_mesh: QuadMesh
var _frame_mat: StandardMaterial3D
var _back_mesh: QuadMesh
var _fill_mesh: QuadMesh
var _fill_mat: StandardMaterial3D


# Called by the battle manager BEFORE add_child().
func bind(house) -> void:
	_house = house


func _ready() -> void:
	_top_y = _compute_top_y()
	_build()


# World-space Y just above the top of the house's mesh, so the bar always clears
# the building no matter how the glb is scaled.
func _compute_top_y() -> float:
	if not is_instance_valid(_house):
		return 0.0
	var mesh = _find_mesh(_house)
	if mesh == null:
		return _house.global_position.y + 8.0
	var aabb: AABB = mesh.get_aabb()
	var t: Transform3D = mesh.global_transform
	var top := -1.0e20
	for i in range(8):
		var corner := aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		var wy = (t * corner).y
		if wy > top:
			top = wy
	return top + margin_above


func _find_mesh(n):
	for c in n.get_children():
		if c is MeshInstance3D:
			return c
		var f = _find_mesh(c)
		if f != null:
			return f
	return null


func _build() -> void:
	# Frame (team-colored, biggest, drawn underneath everything).
	_frame_mesh = QuadMesh.new()
	_frame_mesh.size = _frame_size()
	_frame_mat = _mat(_team_color(), 0)
	_frame = MeshInstance3D.new()
	_frame.mesh = _frame_mesh
	_frame.material_override = _frame_mat
	add_child(_frame)

	# Dark backing (the empty part of the bar).
	_back_mesh = QuadMesh.new()
	_back_mesh.size = _back_size()
	var back := MeshInstance3D.new()
	back.mesh = _back_mesh
	back.material_override = _mat(Color(0.05, 0.05, 0.08, 0.92), 1)
	add_child(back)

	# Colored fill (left-anchored; shrinks from the right as HP drops).
	_fill_mesh = QuadMesh.new()
	_fill_mesh.size = Vector2(bar_width, bar_height)
	_fill_mat = _mat(COL_GREEN, 2)
	var fill := MeshInstance3D.new()
	fill.mesh = _fill_mesh
	fill.material_override = _fill_mat
	add_child(fill)


func _process(delta: float) -> void:
	if not is_instance_valid(_house):
		queue_free()
		return
	_t += delta
	# Park above the house in world space (we don't inherit its scale).
	global_position = Vector3(_house.global_position.x, _top_y, _house.global_position.z)
	if not _house.alive:
		visible = false
		return

	var maxhp := float(_house.max_hp)
	var frac := 0.0
	if maxhp > 0.0:
		frac = clampf(float(_house.hp) / maxhp, 0.0, 1.0)

	# Left-anchored shrink: narrow the fill and push its geometry left by half the
	# loss, so the bar drains from a fixed left edge while billboarding.
	_fill_mesh.size = Vector2(bar_width * frac, bar_height)
	_fill_mesh.center_offset = Vector3(-bar_width * 0.5 * (1.0 - frac), 0.0, 0.0)

	var col := _ramp(frac)
	if frac > 0.0 and frac < DANGER_FRAC:
		# Faster, harder pulse the closer to death.
		var freq := lerpf(9.0, 22.0, 1.0 - frac / DANGER_FRAC)
		var pulse := 0.5 + 0.5 * sin(_t * freq)
		col = col.lerp(Color.WHITE, pulse * 0.70)
		var s := 1.0 + pulse * 0.12
		_frame_mesh.size = _frame_size() * s
		_back_mesh.size = _back_size() * s
		_frame_mat.albedo_color = _team_color().lerp(Color.WHITE, pulse)
	else:
		_frame_mesh.size = _frame_size()
		_back_mesh.size = _back_size()
		_frame_mat.albedo_color = _team_color()
	_fill_mat.albedo_color = col


func _frame_size() -> Vector2:
	return Vector2(bar_width + (FRAME + BACK_PAD) * 2.0, bar_height + (FRAME + BACK_PAD) * 2.0)


func _back_size() -> Vector2:
	return Vector2(bar_width + BACK_PAD * 2.0, bar_height + BACK_PAD * 2.0)


# Green when healthy, amber at half, red when low.
func _ramp(frac: float) -> Color:
	if frac >= 0.5:
		return COL_AMBER.lerp(COL_GREEN, (frac - 0.5) * 2.0)
	return COL_RED.lerp(COL_AMBER, frac * 2.0)


func _team_color() -> Color:
	return Color(0.30, 0.55, 0.95) if int(_house.team) == 0 else Color(0.90, 0.25, 0.25)


# A billboarded, unshaded, depth-test-free quad material (priority orders layers).
func _mat(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priority
	return m
