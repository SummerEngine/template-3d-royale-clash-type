extends Node
## Clash-Royale-style drag-to-deploy. One instance, created by the battle manager.
##
## A spawn card calls begin() on press (if affordable) and release() on let-go.
## While active, a translucent ghost of the unit (plus a ground ring) tracks the
## cursor across the player's half: the player controls BOTH the lateral
## (camera-right) position and the forward DEPTH, each clamped to bounds — depth
## runs from just past the base up to just below the center line, Clash-Royale
## style. Spend + spawn happen on release over the field; releasing back over the
## card cancels (no spend).

@export var deploy_distance: float = 6.0      # forward offset for a TAP (no-drag) deploy, toward center
@export var lateral_half_width: float = 10.0  # max sideways offset from the line center (world units)
# Forward (depth) placement range, like Clash Royale's "your half up to the river".
# Distance from the player base toward map center is ~19.8 units, so the max sits
# just short of the center line. Min keeps drops clear of the base footprint.
@export var deploy_forward_min: float = 3.0   # nearest the base you may drop (world units forward)
@export var deploy_forward_max: float = 18.0  # furthest forward — just below the arena center
@export var drag_threshold: float = 10.0      # px the cursor must move before it counts as a drag (vs a tap)
@export var ghost_alpha: float = 0.5
@export var ghost_tint: Color = Color(0.45, 0.85, 1.0)   # cyan deploy hologram
@export var island_octagon_limit: float = 30.0   # |x|+|z| bound so placement stays inside the arena

var _manager = null
var _cam: Camera3D = null
var _player_base: Node3D = null
var _cam_pan = null      # camera_pan.gd — suspended while a deploy drag is active

var _active: bool = false
var _engaged: bool = false        # has the cursor moved far enough to count as a drag?
var _press_mouse: Vector2 = Vector2.ZERO
var _cost: float = 0.0
var _spawn_fn: Callable = Callable()
var _ghost: Node3D = null
var _ring: MeshInstance3D = null
var _last_pos: Vector3 = Vector3.ZERO

func bind(manager, cam: Camera3D, player_base: Node3D, cam_pan) -> void:
	_manager = manager
	_cam = cam
	_player_base = player_base
	_cam_pan = cam_pan

# Card press. unit_def = { "glb": PackedScene, "scale": float, "spawn_fn": Callable(team, pos) }.
# Returns true if a deploy drag started. Affordability is intentionally NOT checked
# here — you can always start dragging; the can't-afford check (and its shake +
# buzz) happens on release, in the manager's try_deploy.
func begin(_card, cost: float, unit_def: Dictionary) -> bool:
	if _active or _manager == null or _cam == null:
		return false
	_cost = cost
	_spawn_fn = unit_def.get("spawn_fn", Callable())
	_active = true
	_engaged = false
	_press_mouse = _mouse()
	_make_ghost(unit_def)
	_last_pos = _line_center()
	_update_ghost(_last_pos)
	if _cam_pan != null and _cam_pan.has_method("set_active"):
		_cam_pan.set_active(false)   # don't pan the camera mid-deploy
	return true

# Card release. Deploys at the ghost (or line center for a tap); cancels if the
# cursor came back over the originating card.
func release(card) -> void:
	if not _active:
		return
	var do_deploy := true
	var pos := _last_pos
	if not _engaged:
		pos = _line_center()        # a tap: deploy at the line center
	elif _over_card(card):
		do_deploy = false           # dragged back onto the card -> cancel, no spend
	if do_deploy:
		var res: int = _manager.try_deploy(_cost, _spawn_fn, pos)
		if res == 1 and card != null and card.has_method("success_pop"):
			card.success_pop()
		elif res == 2 and card != null and card.has_method("reject_wiggle"):
			card.reject_wiggle()
	_clear()

func _process(_delta: float) -> void:
	if not _active:
		return
	var m := _mouse()
	if not _engaged and m.distance_to(_press_mouse) > drag_threshold:
		_engaged = true
	if _engaged:
		_last_pos = _compute_pos(m)
		_update_ghost(_last_pos)

# --- Placement geometry ----------------------------------------------------
# Center of the deploy line: a fixed distance in front of the player base toward
# map center. Depth here is locked — only the lateral offset below ever changes.
func _line_center() -> Vector3:
	if not is_instance_valid(_player_base):
		return Vector3.ZERO
	var base := _player_base.global_position
	var dir := Vector3.ZERO - base
	dir.y = 0.0
	dir = dir.normalized()
	var c := base + dir * deploy_distance
	c.y = 0.0
	return c

# Camera's right axis projected onto the ground = the "sideways" the player slides along.
func _right_axis() -> Vector3:
	var bx := _cam.global_transform.basis.x
	var r := Vector3(bx.x, 0.0, bx.z)
	return r.normalized() if r.length() > 0.001 else Vector3.RIGHT

# Forward axis: from the player base toward map center (the lane direction). With
# this camera it's perpendicular to _right_axis(), so on screen forward = vertical.
func _forward_axis() -> Vector3:
	if not is_instance_valid(_player_base):
		return Vector3.FORWARD
	var d := Vector3.ZERO - _player_base.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD

func _compute_pos(mouse: Vector2) -> Vector3:
	var base := _player_base.global_position
	base.y = 0.0
	var fwd := _forward_axis()
	var right := _right_axis()
	var ground := _ground_point(mouse, _line_center())
	var rel := ground - base
	rel.y = 0.0
	# Decompose the cursor onto forward (depth) + lateral, clamping each. The player
	# now controls BOTH: lateral within bounds, forward from just past the base up to
	# just below the center line (Clash-Royale "own half" placement).
	var forward_amt := clampf(rel.dot(fwd), deploy_forward_min, deploy_forward_max)
	var lateral := clampf(rel.dot(right), -lateral_half_width, lateral_half_width)
	var p := base + fwd * forward_amt + right * lateral
	var oct := absf(p.x) + absf(p.z)
	if oct > island_octagon_limit:
		var k := island_octagon_limit / oct
		p.x *= k
		p.z *= k
	p.y = 0.0
	return p

# Intersect the camera ray through `mouse` with the ground plane (y = 0).
func _ground_point(mouse: Vector2, fallback: Vector3) -> Vector3:
	var from := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return fallback
	var t := (0.0 - from.y) / dir.y
	if t < 0.0:
		return fallback
	return from + dir * t

func _mouse() -> Vector2:
	return _cam.get_viewport().get_mouse_position() if _cam != null else Vector2.ZERO

func _over_card(card) -> bool:
	if card == null or not card.has_method("button_rect"):
		return false
	return card.button_rect().has_point(_mouse())

# --- Ghost hologram + ground ring ------------------------------------------
func _make_ghost(unit_def: Dictionary) -> void:
	var glb: PackedScene = unit_def.get("glb", null)
	var sc: float = unit_def.get("scale", 1.0)
	if glb != null:
		_ghost = glb.instantiate()
		_manager.add_child(_ghost)
		_ghost.scale = Vector3.ONE * sc
		_ghostify(_ghost)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.15
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(ghost_tint.r, ghost_tint.g, ghost_tint.b, 0.75)
	rm.no_depth_test = true
	_ring.material_override = rm
	_manager.add_child(_ring)

# Replace every mesh surface with a flat translucent tint -> a clean hologram silhouette.
func _ghostify(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(ghost_tint.r, ghost_tint.g, ghost_tint.b, ghost_alpha)
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, mat)
	for c in n.get_children():
		_ghostify(c)

func _update_ghost(pos: Vector3) -> void:
	if is_instance_valid(_ghost):
		_ghost.global_position = pos
		var d := Vector3.ZERO - pos
		d.y = 0.0
		if d.length() > 0.01:
			_ghost.rotation.y = atan2(d.x, d.z)   # face toward map center, like a spawned unit
	if is_instance_valid(_ring):
		_ring.global_position = pos + Vector3(0.0, 0.06, 0.0)

func _clear() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	if is_instance_valid(_ring):
		_ring.queue_free()
	_ghost = null
	_ring = null
	_active = false
	_engaged = false
	_spawn_fn = Callable()
	if _cam_pan != null and _cam_pan.has_method("set_active"):
		_cam_pan.set_active(true)
