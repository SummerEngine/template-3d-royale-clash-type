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
@export var enemy_strip_gap: float = 2.0      # forward clearance past map center before the unlocked enemy strip starts (clears the moat)
@export var enemy_strip_depth: float = 5.0    # how far the unlocked enemy strip extends past the moat
@export var drag_threshold: float = 10.0      # px the cursor must move before it counts as a drag (vs a tap)
@export var ghost_alpha: float = 0.5
@export var ghost_tint: Color = Color(0.45, 0.85, 1.0)   # cyan deploy hologram
@export var island_octagon_limit: float = 30.0   # |x|+|z| bound so placement stays inside the arena
@export var buffer_elixir: float = 1.0   # deploy buffer: if a release is this many elixir short, queue it and spawn the instant elixir fills

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
var _zone: Node3D = null           # container for the blue legal-drop patches
var _zone_sig: int = -1            # unlocked-lane signature the zone was last built for
var _last_pos: Vector3 = Vector3.ZERO
var _spell: bool = false        # spell mode: free-aim a target reticle anywhere on the field
var _spell_radius: float = 4.0
var _place_range: float = 0.0   # if > 0 (e.g. archer tower), show an attack-range disc while placing
var _range_ring: MeshInstance3D = null

# Buildings can't be placed overlapping another structure. While placing one we test
# the spot each frame and turn the ghost RED + reject the drop when it's blocked.
var _building: bool = false
var _footprint: float = 1.6     # the building's collision radius (overlap clearance)
var _last_blocked: bool = false

# --- Deploy buffer: a release that's just short parks a "pending" ghost that fires
# the instant elixir fills. Starting another deploy cancels it (player changed mind).
var _pending: bool = false
var _pending_ghost: Node3D = null
var _pending_ring: MeshInstance3D = null
var _pending_cost: float = 0.0
var _pending_pos: Vector3 = Vector3.ZERO
var _pending_spawn_fn: Callable = Callable()
var _pending_card = null
var _pending_building: bool = false   # re-checked for overlap when a buffered building fires
var _pending_footprint: float = 1.6
var _pending_tween: Tween = null

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
	_clear_pending()   # starting a new placement = changed your mind; drop the buffered ghost
	_cost = cost
	_spell = unit_def.get("spell", false)
	_spell_radius = unit_def.get("radius", 4.0)
	_place_range = unit_def.get("range", 0.0)
	_building = unit_def.get("building", false)
	_footprint = unit_def.get("footprint", 1.6)
	_last_blocked = false
	_spawn_fn = unit_def.get("spawn_fn", Callable())
	_active = true
	_engaged = false
	_press_mouse = _mouse()
	_make_ghost(unit_def)
	if not _spell:
		_make_deploy_zone()   # show the legal drop area (units only; spells free-aim)
	_last_pos = _line_center()
	_update_ghost(_last_pos)
	if _building:
		_update_validity()   # red ghost from the first frame if the start spot is blocked
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
	if not _spell and not _engaged:
		pos = _line_center()        # a unit tap: deploy at the line center
	elif _over_card(card):
		do_deploy = false           # released back over the card -> cancel, no spend
	if do_deploy:
		if _building and _building_blocked(pos):
			# Overlapping a structure — invalid spot. Reject, no spend (no buffer).
			_reject(card)
		elif _manager.can_deploy(_cost):
			# Affordable now — deploy immediately.
			var res: int = _manager.try_deploy(_cost, _spawn_fn, pos)
			if res == 1 and card != null and card.has_method("success_pop"):
				card.success_pop()
		elif _manager.deploy_shortfall(_cost) <= buffer_elixir:
			# Just short — BUFFER it: park the ghost and fire the moment elixir fills.
			_begin_pending(pos, card)
			return   # keep the ghost (now the pending indicator); don't _clear() it
		else:
			# Too short — reject (meter shake + buzz).
			var res: int = _manager.try_deploy(_cost, _spawn_fn, pos)
			if res == 2 and card != null and card.has_method("reject_wiggle"):
				card.reject_wiggle()
	_clear()

func _building_blocked(pos: Vector3) -> bool:
	return _manager != null and _manager.has_method("building_blocked") \
		and _manager.building_blocked(pos, _footprint)

func _reject(card) -> void:
	if _manager != null and _manager.has_method("deploy_denied"):
		_manager.deploy_denied()
	if card != null and card.has_method("reject_wiggle"):
		card.reject_wiggle()

func _process(_delta: float) -> void:
	if _pending:
		_process_pending()
	if not _active:
		return
	var m := _mouse()
	if not _engaged and m.distance_to(_press_mouse) > drag_threshold:
		_engaged = true
	if _engaged or _spell:   # spells follow the cursor from the first frame (free aim)
		_last_pos = _compute_pos(m)
		_update_ghost(_last_pos)
	# Keep the blue zone in sync if an enemy tower falls mid-drag (opens a new strip).
	if not _spell and is_instance_valid(_zone) and _zone_unlock_sig() != _zone_sig:
		_refresh_deploy_zone()
	# Buildings: re-tint the ghost red/cyan as the spot becomes blocked/free.
	if _building:
		_update_validity()

# Turn the building ghost (and its ring) RED while it overlaps a structure, cyan when
# free. Only re-tints when the state flips, so it's cheap.
func _update_validity() -> void:
	var blocked := _building_blocked(_last_pos)
	if blocked == _last_blocked and _ghost != null:
		return
	_last_blocked = blocked
	var col: Color = Color(0.95, 0.28, 0.22) if blocked else ghost_tint
	if is_instance_valid(_ghost):
		_tint_ghost(_ghost, col)
	if is_instance_valid(_ring):
		var rm = _ring.material_override
		if rm is StandardMaterial3D:
			rm.albedo_color = Color(col.r, col.g, col.b, 0.75)

func _tint_ghost(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m = mi.get_surface_override_material(i)
				if m is StandardMaterial3D:
					m.albedo_color = Color(col.r, col.g, col.b, ghost_alpha)
	for c in n.get_children():
		_tint_ghost(c, col)

# --- Deploy buffer ---------------------------------------------------------
# Park the active drag's ghost as a pending deploy: it fires automatically once
# elixir reaches the cost. Reuses the live ghost/ring; the drop-zone patch is dropped.
func _begin_pending(pos: Vector3, card) -> void:
	_clear_pending()                  # only one buffered deploy at a time
	if is_instance_valid(_zone):
		_zone.queue_free()
		_zone = null
	if is_instance_valid(_range_ring):
		_range_ring.queue_free()   # placement-only aid; not needed while a deploy waits
		_range_ring = null
	_place_range = 0.0
	_pending = true
	_pending_ghost = _ghost
	_pending_ring = _ring
	_pending_cost = _cost
	_pending_pos = pos
	_pending_spawn_fn = _spawn_fn
	_pending_card = card
	_pending_building = _building
	_pending_footprint = _footprint
	if is_instance_valid(_pending_ghost):
		_pending_ghost.global_position = pos
		var d := Vector3.ZERO - pos
		d.y = 0.0
		if d.length() > 0.01:
			_pending_ghost.rotation.y = atan2(d.x, d.z)
	if is_instance_valid(_pending_ring):
		_pending_ring.global_position = pos + Vector3(0.0, 0.06, 0.0)
		var rm = _pending_ring.material_override
		if rm is StandardMaterial3D:
			rm.albedo_color = Color(1.0, 0.78, 0.22, 0.85)   # amber = waiting for elixir
			_pending_tween = create_tween().set_loops()
			_pending_tween.tween_property(rm, "albedo_color:a", 0.35, 0.4)
			_pending_tween.tween_property(rm, "albedo_color:a", 0.85, 0.4)
	# Detach from the active drag state WITHOUT freeing the now-pending visuals.
	_ghost = null
	_ring = null
	_active = false
	_engaged = false
	_spell = false
	_spawn_fn = Callable()
	if _cam_pan != null and _cam_pan.has_method("set_active"):
		_cam_pan.set_active(true)

func _process_pending() -> void:
	if _manager == null:
		_clear_pending()
		return
	var short: float = _manager.deploy_shortfall(_pending_cost)
	if short >= 900.0:
		_clear_pending()   # base dead / no economy — drop the buffered deploy
		return
	if short <= 0.0:
		# A buffered building re-checks its spot: if a structure took it meanwhile, drop it
		# (no overlap) instead of spawning.
		if _pending_building and _manager.has_method("building_blocked") and _manager.building_blocked(_pending_pos, _pending_footprint):
			_clear_pending()
			return
		var res: int = _manager.try_deploy(_pending_cost, _pending_spawn_fn, _pending_pos)
		if res == 1 and _pending_card != null and is_instance_valid(_pending_card) and _pending_card.has_method("success_pop"):
			_pending_card.success_pop()
		_clear_pending()

func _clear_pending() -> void:
	if _pending_tween != null and _pending_tween.is_valid():
		_pending_tween.kill()
	_pending_tween = null
	if is_instance_valid(_pending_ghost):
		_pending_ghost.queue_free()
	if is_instance_valid(_pending_ring):
		_pending_ring.queue_free()
	_pending_ghost = null
	_pending_ring = null
	_pending_card = null
	_pending_spawn_fn = Callable()
	_pending = false

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
	if _spell:
		# Spells aim ANYWHERE on the field (both halves), only clamped to the arena octagon.
		var g := _ground_point(mouse, _last_pos)
		g.y = 0.0
		var goct := absf(g.x) + absf(g.z)
		if goct > island_octagon_limit:
			var gk := island_octagon_limit / goct
			g.x *= gk
			g.z *= gk
		return g
	var base := _player_base.global_position
	base.y = 0.0
	var fwd := _forward_axis()
	var right := _right_axis()
	var ground := _ground_point(mouse, _line_center())
	var rel := ground - base
	rel.y = 0.0
	# Decompose the cursor onto forward (depth) + lateral.
	var raw_fwd := rel.dot(fwd)
	var raw_lat := rel.dot(right)
	var center_fwd := (Vector3.ZERO - base).dot(fwd)   # forward distance from base to map centre (the river)

	# Which lateral half(s) past the river are unlocked: each destroyed enemy princess
	# tower opens its own lane (full width once both are down) — Clash-Royale style.
	var un_min := 0.0
	var un_max := 0.0
	var unlocked := false
	if _manager != null and _manager.has_method("destroyed_enemy_tower_positions"):
		for tpos in _manager.destroyed_enemy_tower_positions():
			if (tpos - base).dot(right) >= 0.0:
				un_max = lateral_half_width    # open the right half
			else:
				un_min = -lateral_half_width   # open the left half
			unlocked = true

	var forward_amt: float
	var lateral: float
	if unlocked and raw_fwd > center_fwd and raw_lat >= un_min and raw_lat <= un_max:
		# Unlocked strip just past the moat, on the open lane(s).
		var strip_min := center_fwd + enemy_strip_gap
		forward_amt = clampf(raw_fwd, strip_min, strip_min + enemy_strip_depth)
		lateral = clampf(raw_lat, un_min, un_max)
	else:
		# Own half, up to the river (Clash-Royale "own half" placement).
		forward_amt = clampf(raw_fwd, deploy_forward_min, deploy_forward_max)
		lateral = clampf(raw_lat, -lateral_half_width, lateral_half_width)
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
	var spell: bool = unit_def.get("spell", false)
	if not spell:
		var glb: PackedScene = unit_def.get("glb", null)
		var sc: float = unit_def.get("scale", 1.0)
		if glb != null:
			_ghost = glb.instantiate()
			_manager.add_child(_ghost)
			_ghost.scale = Vector3.ONE * sc
			_ghostify(_ghost)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	if spell:
		torus.outer_radius = _spell_radius                       # reticle matches the blast radius
		torus.inner_radius = maxf(0.3, _spell_radius - 0.35)
	else:
		torus.inner_radius = 0.85
		torus.outer_radius = 1.15
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rc: Color = ghost_tint   # blue aim ring for everything, matching the unit deploy ghosts
	rm.albedo_color = Color(rc.r, rc.g, rc.b, 0.75)
	rm.no_depth_test = true
	_ring.material_override = rm
	_manager.add_child(_ring)

	# Buildings with an attack range (e.g. the archer tower) show a translucent disc
	# of that radius while placing, so the player can cover the area they want.
	if _place_range > 0.0:
		_range_ring = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = _place_range
		disc.bottom_radius = _place_range
		disc.height = 0.04
		disc.radial_segments = 48
		_range_ring.mesh = disc
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(0.45, 0.85, 1.0, 0.13)   # soft cyan range footprint
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_range_ring.material_override = dm
		_manager.add_child(_range_ring)

# Translucent blue patch on the ground covering the legal unit-drop region: the
# "own half up to the river" rectangle (deploy_forward_min..max deep, +/-lateral
# wide), laid out in the base->center forward axis and the camera-right axis so it
# lines up with how the cursor is clamped in _compute_pos. Static for the whole
# drag; the cursor ghost moves within it. (The octagon corner-clip isn't drawn —
# the rectangle slightly overhangs the far corners, which is close enough as a hint.)
func _make_deploy_zone() -> void:
	if not is_instance_valid(_player_base) or _manager == null:
		return
	_zone = Node3D.new()
	_manager.add_child(_zone)
	_zone_sig = -1
	_refresh_deploy_zone()

# Which enemy lanes are currently unlocked, as a bitmask (1 = left half open, 2 =
# right half open). Each destroyed enemy princess tower opens its lane — the same
# rule _compute_pos uses to actually clamp drops. The zone rebuilds whenever this
# changes, so the blue area grows the instant a tower falls.
func _zone_unlock_sig() -> int:
	if _manager == null or not is_instance_valid(_player_base) or not _manager.has_method("destroyed_enemy_tower_positions"):
		return 0
	var base := _player_base.global_position
	var right := _right_axis()
	var sig := 0
	for tpos in _manager.destroyed_enemy_tower_positions():
		if (tpos - base).dot(right) >= 0.0:
			sig |= 2   # right lane
		else:
			sig |= 1   # left lane
	return sig

# (Re)build the blue patches: the always-legal own-half rectangle, plus any
# unlocked enemy strip past the moat. Called on begin and whenever a tower falls.
func _refresh_deploy_zone() -> void:
	if not is_instance_valid(_zone) or not is_instance_valid(_player_base):
		return
	for c in _zone.get_children():
		c.queue_free()
	var base := _player_base.global_position
	base.y = 0.0
	var fwd := _forward_axis()
	var right := _right_axis()
	# Own half, up to the river — always available.
	_add_zone_patch(base, fwd, right, deploy_forward_min, deploy_forward_max, -lateral_half_width, lateral_half_width)
	# Unlocked strip(s) past the moat, on whichever lane(s) lost a tower.
	var sig := _zone_unlock_sig()
	if sig != 0:
		var center_fwd := (Vector3.ZERO - base).dot(fwd)
		var strip_lo := center_fwd + enemy_strip_gap
		var strip_hi := strip_lo + enemy_strip_depth
		var lat_lo := 0.0
		var lat_hi := 0.0
		if sig & 1:
			lat_lo = -lateral_half_width   # left half open
		if sig & 2:
			lat_hi = lateral_half_width    # right half open
		_add_zone_patch(base, fwd, right, strip_lo, strip_hi, lat_lo, lat_hi)
	_zone_sig = sig

# One flat blue rectangle on the ground, given a forward [f_lo,f_hi] x lateral
# [l_lo,l_hi] span in the deploy frame (forward = base->center, right = camera-right).
func _add_zone_patch(base: Vector3, fwd: Vector3, right: Vector3, f_lo: float, f_hi: float, l_lo: float, l_hi: float) -> void:
	var depth := f_hi - f_lo
	var width := l_hi - l_lo
	if depth <= 0.0 or width <= 0.0:
		return
	var center := base + fwd * ((f_lo + f_hi) * 0.5) + right * ((l_lo + l_hi) * 0.5)
	center.y = 0.04   # just above the ground, like the deploy ring
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, depth)   # local X = lateral (right), local Z = depth (forward)
	var patch := MeshInstance3D.new()
	patch.mesh = plane
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.3, 0.6, 1.0, 0.22)   # soft blue deploy zone
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	patch.material_override = m
	_zone.add_child(patch)
	# Orient so local X -> right, local Z -> forward, flat on the ground.
	var b := Basis()
	b.x = right
	b.y = Vector3.UP
	b.z = right.cross(Vector3.UP)
	if b.z.dot(fwd) < 0.0:
		b.z = -b.z
	patch.global_transform = Transform3D(b, center)

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
	if is_instance_valid(_range_ring):
		_range_ring.global_position = Vector3(pos.x, 0.04, pos.z)

func _clear() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	if is_instance_valid(_ring):
		_ring.queue_free()
	if is_instance_valid(_range_ring):
		_range_ring.queue_free()
	if is_instance_valid(_zone):
		_zone.queue_free()
	_ghost = null
	_ring = null
	_range_ring = null
	_place_range = 0.0
	_zone = null
	_zone_sig = -1
	_active = false
	_engaged = false
	_spell = false
	_building = false
	_last_blocked = false
	_spawn_fn = Callable()
	if _cam_pan != null and _cam_pan.has_method("set_active"):
		_cam_pan.set_active(true)
