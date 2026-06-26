extends Node3D
# Bomber (Bomb-Carrying Skeleton) — a fast, fragile suicide unit. Spawned from the
# skeleton Walking GLB via set_script(); the manager calls setup() then add_child()s
# us and sets global_position.
#
# It does NOT attack. It sprints toward the nearest enemy (unit OR building) and,
# once close enough, COMMITS to a jumping suicide: it plays the Basic_Jump clip and
# a beat later detonates — a big area-of-effect blast that damages every enemy unit
# and building in radius — then is consumed by the explosion. Once it starts the
# jump it can no longer be killed (the bomb is going off no matter what), so focus-
# firing only helps if it dies BEFORE it leaps.
#
# State machine (per frame in _process):
#   - Detonating? -> do nothing (the jump + scheduled blast run on timers).
#   - Pick nearest enemy; within trigger range -> start the suicide jump.
#   - Otherwise -> face + run toward it (routed around the moat).

# --- Tunables (designer-balanced; no clamps/floors added) ---
@export var max_hp: float = 26.0           # fragile, like a wizard
@export var move_speed: float = 2.7        # fast — it wants to reach the line and blow up
@export var turn_speed: float = 7.0        # yaw lerp factor
@export var radius: float = 0.91           # soft-collision radius; read by manager
@export var visual_scale: float = 1.43     # uniform model scale (matches the rank-and-file)
@export var trigger_range: float = 1.4     # gap to the target (plus its radius) at which it commits to the jump
@export var leap_max: float = 3.5          # cap on the forward lunge distance, so it never overshoots the target
@export var explosion_radius: float = 6.75   # AoE radius of the blast (horizontal) — wide, catches whole clumps
@export var explosion_damage: float = 50.0   # AoE hit
@export var jump_anim_speed: float = 2.0   # snappier leap so it fits the ~0.6s fuse
@export var explode_delay: float = 0.6     # time from commit to blast (also caps the leap-clip wait)
@export var fade_time: float = 0.8         # corpse fade IF killed before it can jump

const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")

# --- Runtime state ---
var team: int = 0
var alive: bool = true
var hp: float = 0.0

var _manager = null         # BattleManager — untyped for cross-script duck typing
var _enemy_base = null      # HouseBase — untyped for cross-script duck typing

const RETARGET_INTERVAL := 0.2
var _cached_target = null
var _retarget_t: float = 0.0

var _base_y: float = 0.0
var _detonating: bool = false   # committed to the suicide jump; can't be killed or retargeted

# --- Animation ---
var _anim: AnimationPlayer = null
var _walk_clip: String = ""
var _jump_clip: String = ""

func setup(p_team: int, p_manager: Node, p_enemy_base: Node3D) -> void:
	team = p_team
	_manager = p_manager
	_enemy_base = p_enemy_base
	_apply_tint()

func _ready() -> void:
	hp = max_hp
	scale = Vector3.ONE * visual_scale
	_base_y = position.y
	_retarget_t = randf() * RETARGET_INTERVAL
	_anim = _find_anim_player(self)
	if _anim:
		# Merge the skeleton's extra clips (run/dead/jump) into an editable library;
		# walk comes from the base model. Imported "" libraries are read-only.
		var sclips := SkeletonAnims.clips()
		if not sclips.is_empty() and not _anim.has_animation_library("extra"):
			var extra := AnimationLibrary.new()
			for cname in sclips:
				extra.add_animation(cname, sclips[cname])
			_anim.add_animation_library("extra", extra)
		_walk_clip = _match_clip(["walk"])
		_jump_clip = _match_clip(["jump", "basic"])
	var bar := preload("res://scripts/health_bar.gd").new()
	bar.name = "HealthBar"
	add_child(bar)
	add_child(preload("res://scripts/unit_shadow.gd").new())   # cheap blob shadow under the unit
	SFX.play(self, "res://audio/bomber_spawn", -8.0)   # dry skeletal rattle + cackle

# --- Damage / death ---
func take_damage(amount: float) -> void:
	if not alive or _detonating:
		return   # once the jump starts, the bomb goes off no matter what
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * visual_scale, true, amount)
	if hp <= 0.0:
		alive = false
		if is_instance_valid(_manager):
			_manager.notify_died(self)
		_die()

# Killed before it could jump: a plain corpse fade, no explosion (the bomb fizzles).
func _die() -> void:
	set_process(false)
	SFX.play(self, "res://audio/bomber_death", -8.0)
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.visible = false
	var dead := _match_clip(["dead", "death"])
	var hold := 0.8
	if dead != "" and _anim:
		_play(dead, false)
		var a := _anim.get_animation(dead)
		if a and a.length > 0.0:
			hold = a.length
	await get_tree().create_timer(hold).timeout
	if not is_instance_valid(self):
		return
	var mesh := _find_mesh_instance(self)
	var tw := create_tween()
	tw.set_parallel(true)
	var fading := false
	if mesh and mesh.mesh:
		for i in mesh.mesh.get_surface_count():
			var m = mesh.get_active_material(i)
			if m is BaseMaterial3D:
				var dm: BaseMaterial3D = m.duplicate()
				dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh.set_surface_override_material(i, dm)
				tw.tween_property(dm, "albedo_color:a", 0.0, fade_time)
				fading = true
		if mesh.material_overlay is BaseMaterial3D:
			tw.tween_property(mesh.material_overlay, "albedo_color:a", 0.0, fade_time)
			fading = true
	if fading:
		await tw.finished
	else:
		await get_tree().create_timer(fade_time).timeout
	queue_free()

# --- Suicide jump + blast ---------------------------------------------------
# Commit to the attack: stop the AI, play the jump wind-up, then detonate a beat
# later. Guarded so it can only ever fire once.
func _begin_detonation(target) -> void:
	if _detonating:
		return
	_detonating = true
	set_process(false)
	# Lunge forward ONTO the target's near edge (capped by leap_max so it never
	# overshoots), then detonate where it lands — the blast (damage + fireball) is
	# centred at global_position, which the leap carries to `land`.
	var land := global_position
	if is_instance_valid(target):
		_face_instant(target.global_position)
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.01:
			var leap_dist: float = clampf(d - target.radius, 0.0, leap_max)
			land = global_position + (to / d) * leap_dist
	land.y = _base_y
	# Play the jump attack, then explode. Timed to the clip (shorter when sped up),
	# capped at explode_delay (~0.6s); explode_delay is also the fallback with no clip.
	var wait := explode_delay
	if _jump_clip != "" and _anim != null:
		_play(_jump_clip, false, jump_anim_speed)
		var a := _anim.get_animation(_jump_clip)
		if a != null and a.length > 0.0:
			wait = minf(a.length / jump_anim_speed, explode_delay)   # never drag past ~0.6s
	SFX.play(self, "res://audio/bomber_leap", -4.0)   # fuse sizzle + "hup" as it leaps
	_leap_to(land, wait)   # arc forward onto the target during the fuse, so the blast is at the target
	await get_tree().create_timer(wait).timeout
	if not is_instance_valid(self):
		return
	_explode()

# Arc from where we committed onto `dest` over `dur`, with a hop, so the explosion
# goes off at the target instead of back where we decided to jump. _process is off
# during the leap, so these tweens own our position.
func _leap_to(dest: Vector3, dur: float) -> void:
	if dur <= 0.0:
		position = Vector3(dest.x, _base_y, dest.z)
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:x", dest.x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:z", dest.z, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Hop: rise to a peak by mid-leap, drop back to ground by the end.
	var hop := create_tween()
	hop.tween_property(self, "position:y", _base_y + 1.8, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(self, "position:y", _base_y, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _explode() -> void:
	alive = false
	if is_instance_valid(_manager):
		_manager.notify_died(self)
		if _manager.has_method("explode_damage"):
			_manager.explode_damage(global_position, explosion_radius, explosion_damage, team)
	_explosion_fx()
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.visible = false
	# The skeleton is consumed by the blast: a fast pop-and-vanish, then free.
	var mesh := _find_mesh_instance(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ONE * visual_scale * 1.4, 0.12)
	if mesh and mesh.mesh:
		for i in mesh.mesh.get_surface_count():
			var m = mesh.get_active_material(i)
			if m is BaseMaterial3D:
				var dm: BaseMaterial3D = m.duplicate()
				dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh.set_surface_override_material(i, dm)
				tw.tween_property(dm, "albedo_color:a", 0.0, 0.18)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		queue_free()

# Big fiery blast at our feet: a shake/slow-mo/debris boom (Juice) plus an expanding
# additive fire sphere + flash light. Parented to the battle root so the visuals
# outlive us when we free.
func _explosion_fx() -> void:
	Juice.boom(global_position, 1.6)
	SFX.play(self, "res://audio/big_explosion", 5.0)
	var host := get_parent()
	if host == null:
		return
	var center := global_position + Vector3(0.0, 0.8, 0.0)

	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
	ball.material_override = mat
	host.add_child(ball)
	ball.global_position = center
	ball.scale = Vector3.ONE * 0.4
	var bt := ball.create_tween()
	bt.set_parallel(true)
	bt.tween_property(ball, "scale", Vector3.ONE * explosion_radius, 0.32).set_ease(Tween.EASE_OUT)
	bt.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	bt.set_parallel(false)
	bt.tween_callback(ball.queue_free)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.omni_range = explosion_radius * 2.0
	flash.light_energy = 6.0
	host.add_child(flash)
	flash.global_position = center
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.3)
	ft.tween_callback(flash.queue_free)

# --- Team-color overlay on the skinned mesh ---
func _apply_tint() -> void:
	var mesh := _find_mesh_instance(self)
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.45, 0.95, 0.22) if team == 0 else Color(0.95, 0.14, 0.14, 0.42)
	mesh.material_overlay = mat

func _bridge_y() -> float:
	if is_instance_valid(_manager) and _manager.has_method("bridge_height"):
		return _manager.bridge_height(global_position)
	return _base_y

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null

# --- Animation helpers ---
func _find_anim_player(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		if c is AnimationPlayer:
			return c
		var found := _find_anim_player(c)
		if found:
			return found
	return null

func _match_clip(keys: Array) -> String:
	if _anim == null:
		return ""
	for clip in _anim.get_animation_list():
		var lower := String(clip).to_lower()
		for k in keys:
			if lower.find(k) != -1:
				return clip
	return ""

func _play(clip: String, loop_it: bool, speed: float = 1.0) -> void:
	if _anim == null or clip == "":
		return
	if speed == 1.0 and _anim.current_animation == clip:
		return
	_anim.play(clip, -1, speed)
	var anim := _anim.get_animation(clip)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if loop_it else Animation.LOOP_NONE

# --- Target selection: nearest enemy of ANY kind (unit / structure / King base) ---
func _pick_target():
	_retarget_t -= get_process_delta_time()
	if _retarget_t > 0.0 and is_instance_valid(_cached_target) and _cached_target.alive:
		return _cached_target
	_retarget_t = RETARGET_INTERVAL
	_cached_target = _acquire_target()
	return _cached_target

func _acquire_target():
	var best = null
	var best_d := INF
	# Nearest enemy unit or pump (manager scans both).
	if is_instance_valid(_manager) and _manager.has_method("get_nearest_enemy"):
		var u = _manager.get_nearest_enemy(global_position, team)
		if is_instance_valid(u) and u.alive:
			best = u
			best_d = _horiz_dist(global_position, u.global_position)
	# Otherwise (or if it's nearer) push for the enemy King base.
	if is_instance_valid(_enemy_base) and _enemy_base.alive:
		var d := _horiz_dist(global_position, _enemy_base.global_position)
		if d < best_d:
			best = _enemy_base
			best_d = d
	return best

func _horiz_dist(a: Vector3, b: Vector3) -> float:
	var to := b - a
	to.y = 0.0
	return to.length()

# --- Main AI loop ---
func _process(delta: float) -> void:
	if not alive or _detonating:
		return

	var target = _pick_target()
	if target == null:
		# Nothing to rush: keep advancing toward where the base was, or idle-walk.
		_play(_walk_clip, true)
		return

	var trigger_pad: float = trigger_range + target.radius
	var dist := _horiz_dist(global_position, target.global_position)
	if dist <= trigger_pad:
		_begin_detonation(target)
		return

	# Run toward the target, routed around the moat to a bridge.
	var dest: Vector3 = target.global_position
	if is_instance_valid(_manager) and _manager.has_method("moat_route"):
		dest = _manager.moat_route(global_position, target.global_position)
	var to: Vector3 = dest - global_position
	to.y = 0.0
	var to_len := to.length()
	if to_len > 0.001:
		var dir := to / to_len
		_face(dest, delta)
		position += dir * move_speed * delta
	position.y = _bridge_y()
	_play(_walk_clip, true)

func _face(toward: Vector3, delta: float) -> void:
	var to := toward - global_position
	to.y = 0.0
	if to.length() < 0.0001:
		return
	var desired_yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))

func _face_instant(toward: Vector3) -> void:
	var to := toward - global_position
	to.y = 0.0
	if to.length() < 0.0001:
		return
	rotation.y = atan2(to.x, to.z)
