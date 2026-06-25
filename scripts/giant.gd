extends Node3D
# Giant (Barbarian Behemoth) — a huge, slow, very tanky unit that ONLY attacks
# BUILDINGS. Spawned from the Behemoth Walking GLB via set_script(); the manager
# calls setup() then add_child()s us and sets global_position.
#
# Unlike the barbarian, the giant ignores enemy UNITS entirely: it marches to the
# nearest enemy structure (princess tower / elixir pump — both live in the manager's
# _pumps list) or the enemy King base, and smashes it with the Heavy Hammer Swing.
# Enemy units can still freely attack the giant; it just won't fight back, so it
# soaks damage while it bee-lines for your towers (classic Clash-Royale Giant).
#
# State machine (per frame in _process):
#   - Pick a target: nearest enemy building, else nothing -> idle.
#   - In range -> stop, face it, swing on cooldown (one clip per hit). A swing in
#     progress is never interrupted.
#   - Out of range -> face + walk toward it (routed around the moat).

# --- Tunables (designer-balanced; no clamps/floors added) ---
@export var max_hp: float = 200.0
@export var damage: float = 30.0
@export var move_speed: float = 1.25      # units/sec — deliberately slow
@export var turn_speed: float = 4.0       # yaw lerp factor
@export var attack_range: float = 1.8     # must exceed structure push-out so the swing connects
@export var attack_cooldown: float = 1.6
@export var radius: float = 1.5           # soft-collision radius; read by manager (big footprint)
@export var visual_scale: float = 2.4     # uniform model scale — towers over the rank-and-file
@export var swing_time: float = 0.4       # fallback procedural chop duration (if no clip)
@export var swing_angle: float = 0.6      # peak forward pitch of the fallback chop (radians)
@export var attack_anim_speed: float = 1.4   # play the hammer clip this much faster
@export var attack_hit_delay: float = 0.95   # seconds into the swing before damage lands
@export var fade_time: float = 1.0        # seconds to fade the corpse out after the death clip

const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")

# --- Runtime state ---
var team: int = 0
var alive: bool = true
var hp: float = 0.0

var _manager = null         # BattleManager — untyped for cross-script duck typing
var _enemy_base = null      # HouseBase — untyped for cross-script duck typing

# Target acquisition is throttled (re-scan a few times/sec, not every frame).
const RETARGET_INTERVAL := 0.25
var _cached_target = null
var _retarget_t: float = 0.0

var _base_y: float = 0.0
var _attack_timer: float = 0.0
var _swing_t: float = -1.0

# --- Animation ---
var _anim: AnimationPlayer = null
var _walk_clip: String = ""
var _idle_clip: String = ""
var _attack_clip: String = ""
var _attacking: bool = false

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
		# Merge the Behemoth's extra clips (idle/run/dead/hammer) into an editable
		# library; walk comes from the base model. Imported "" libraries are read-only.
		var gclips := GiantAnims.clips()
		if not gclips.is_empty() and not _anim.has_animation_library("extra"):
			var extra := AnimationLibrary.new()
			for cname in gclips:
				extra.add_animation(cname, gclips[cname])
			_anim.add_animation_library("extra", extra)
		_walk_clip = _match_clip(["walk"])
		_idle_clip = _match_clip(["idle", "stand", "rest"])
		_attack_clip = _match_clip(["hammer", "swing", "attack", "slash", "punch"])
		_anim.animation_finished.connect(_on_anim_finished)
	# Floating health bar above this unit.
	var bar := preload("res://scripts/health_bar.gd").new()
	bar.name = "HealthBar"
	add_child(bar)
	SFX.play(self, "res://audio/giant_spawn", -6.0)   # dedicated giant arrival stomp

# --- Damage / death ---
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * visual_scale, true, amount)
	if hp <= 0.0:
		alive = false
		if is_instance_valid(_manager):
			_manager.notify_died(self)
		_die()

func _die() -> void:
	set_process(false)
	Juice.boom(global_position, 1.3)   # a giant falling is a big deal
	SFX.play(self, "res://audio/giant_death", -4.0)
	_attacking = false
	_swing_t = -1.0
	rotation.x = 0.0
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

func _on_anim_finished(anim_name: String) -> void:
	if anim_name == _attack_clip:
		_attacking = false

func _stand() -> void:
	if _idle_clip != "":
		_play(_idle_clip, true)
	elif _anim and _anim.is_playing():
		_anim.stop()

# --- Target selection: nearest enemy BUILDING only (towers/pumps + King base) ---
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
	# Nearest enemy structure (princess towers + elixir pumps share the _pumps channel).
	if is_instance_valid(_manager) and _manager.has_method("get_nearest_enemy_structure"):
		var s = _manager.get_nearest_enemy_structure(global_position, team)
		if is_instance_valid(s) and s.alive:
			best = s
			best_d = _horiz_dist(global_position, s.global_position)
	# The enemy King base — fall back to it / pick it if it's the nearest building.
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

func _schedule_hit(target) -> void:
	await get_tree().create_timer(attack_hit_delay).timeout
	if not alive or not is_instance_valid(target):
		return
	if target.alive:
		target.take_damage(damage)
		SFX.play(self, "res://audio/house_hit", 2.0)

# --- Main AI loop ---
func _process(delta: float) -> void:
	if not alive:
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
	_update_swing(delta)
	if _attacking:
		return

	var target = _pick_target()
	if target == null:
		_stand()
		return

	var range_pad: float = attack_range + target.radius
	var dist := _horiz_dist(global_position, target.global_position)

	if dist <= range_pad:
		_face(target.global_position, delta)
		_play(_walk_clip, true)   # keep limbs alive between swings (no dedicated idle hold)
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			SFX.play(self, "res://audio/giant_attack", -2.0)
			_schedule_hit(target)
			if _attack_clip != "":
				_attacking = true
				_play(_attack_clip, false, attack_anim_speed)
			else:
				_swing_t = 0.0
		position.y = _bridge_y()
		return

	# Move toward the building, routed around the moat to a bridge.
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

func _update_swing(delta: float) -> void:
	if _swing_t < 0.0:
		return
	_swing_t += delta
	var p := _swing_t / swing_time
	if p >= 1.0:
		_swing_t = -1.0
		rotation.x = 0.0
	else:
		rotation.x = -sin(p * PI) * swing_angle

func _face(toward: Vector3, delta: float) -> void:
	var to := toward - global_position
	to.y = 0.0
	if to.length() < 0.0001:
		return
	var desired_yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))
