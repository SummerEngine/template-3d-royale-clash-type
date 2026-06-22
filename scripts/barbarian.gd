extends Node3D
# Barbarian combat unit for a team-vs-team auto-battler.
# Spawned from a greg_walking.glb instance via set_script(). The manager calls
# setup() then add_child()s us and sets global_position.
#
# State machine (per frame in _process):
#   - Pick a target: nearest alive enemy unit within aggro_radius, else the
#     enemy base (while it lives), else nothing -> idle.
#   - In attack range -> stop, face target, attack on cooldown (one swing clip
#     per hit, idle between). An in-progress swing is never interrupted.
#   - Out of range -> face + walk toward target.

# --- Tunables (designer-balanced; no clamps/floors added) ---
@export var max_hp: float = 40.0
@export var damage: float = 8.0
@export var move_speed: float = 2.2       # units/sec
@export var turn_speed: float = 6.0       # yaw lerp factor
@export var attack_range: float = 0.9
@export var attack_cooldown: float = 1.1
@export var aggro_radius: float = 7.0
@export var radius: float = 0.91          # soft-collision radius; read by manager (0.7 base, +30% to match the +30% model scale)
@export var visual_scale: float = 1.3     # uniform model scale (+30%)
@export var swing_time: float = 0.32      # duration of the procedural attack chop
@export var swing_angle: float = 0.7      # peak forward pitch of the chop (radians)
@export var attack_anim_speed: float = 2.0   # play the attack clip this much faster
@export var attack_hit_delay: float = 0.5    # seconds into the swing before damage lands
@export var fade_time: float = 0.8        # seconds to fade the corpse out after the death clip
# Sword equip (placement is exported because the hand-bone frame can't be eyeballed from code — TUNE).
@export var equip_weapon: bool = true
@export var weapon_bone: String = "RightHand"
@export var weapon_scale: float = 80.0    # ~100x to cancel the rig's 0.01 (cm) armature scale
@export var weapon_offset_pos: Vector3 = Vector3.ZERO     # local position in the hand
@export var weapon_offset_rot: Vector3 = Vector3(-90, 0, 0)   # pitch blade from down-the-arm to forward

const SWORD_SCENE := preload("res://models/sword.glb")
const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")

# --- Runtime state ---
var team: int = 0
var alive: bool = true
var hp: float = 0.0

var _manager = null        # BattleManager — untyped for cross-script duck typing
var _enemy_base = null      # HouseBase — untyped for cross-script duck typing

# Target acquisition is throttled (see _pick_target): re-scan only a few times a
# second instead of every frame. Removes the per-frame O(n^2) nearest-enemy scan
# that dominated CPU time on mobile, with no perceptible change to behavior.
const RETARGET_INTERVAL := 0.2
var _cached_target = null
var _retarget_t: float = 0.0

var _base_y: float = 0.0
var _attack_timer: float = 0.0            # counts down to next allowed swing
var _swing_t: float = -1.0                # >=0 while a procedural chop is animating

# --- Animation ---
var _anim: AnimationPlayer = null
var _walk_clip: String = ""
var _idle_clip: String = ""
var _attack_clip: String = ""
var _attacking: bool = false              # true while a swing clip plays

func setup(p_team: int, p_manager: Node, p_enemy_base: Node3D) -> void:
	team = p_team
	_manager = p_manager
	_enemy_base = p_enemy_base
	_apply_tint()

func _ready() -> void:
	hp = max_hp
	scale = Vector3.ONE * visual_scale
	_base_y = position.y
	_retarget_t = randf() * RETARGET_INTERVAL   # stagger so units don't all re-scan the same frame
	_anim = _find_anim_player(self)
	if _anim:
		# Merge the Viking's extra clips (attack/idle/run) into an editable library.
		# Each clip ships in its own GLB on the same Armature; walk comes from the
		# base model. Imported "" libraries are read-only, so we add a new "extra".
		var vclips := VikingAnims.clips()
		if not vclips.is_empty() and not _anim.has_animation_library("extra"):
			var extra := AnimationLibrary.new()
			for cname in vclips:
				extra.add_animation(cname, vclips[cname])
			_anim.add_animation_library("extra", extra)
		_walk_clip = _match_clip(["walk"])
		_idle_clip = _match_clip(["idle", "stand", "tpose", "rest"])
		_attack_clip = _match_clip(["attack", "swing", "slash", "punch"])
		_anim.animation_finished.connect(_on_anim_finished)
	# Floating health bar above this unit (covers all units, since every unit runs this).
	var bar := preload("res://scripts/health_bar.gd").new()
	bar.name = "HealthBar"
	add_child(bar)
	_equip_weapon()
	SFX.play(self, "res://audio/barbarian_spawn", -24.0)

# --- Damage / death ---
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * visual_scale)
	if hp <= 0.0:
		alive = false
		if is_instance_valid(_manager):
			_manager.notify_died(self)
		_die()

# Death: stop fighting, play the death clip, then fade the corpse out and free.
func _die() -> void:
	set_process(false)
	SFX.play(self, "res://audio/barbarian_death", -14.0)
	_attacking = false
	_swing_t = -1.0
	rotation.x = 0.0
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.visible = false
	# Play the death clip and hold for its real length (min 0.8s if missing/empty).
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
	# Fade out: replace this unit's materials with per-instance transparent copies
	# (so only this corpse fades, not the shared material) and tween their alpha.
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
	mat.albedo_color = Color(0.2, 0.45, 0.95, 0.22) if team == 0 else Color(0.9, 0.2, 0.2, 0.22)
	mesh.material_overlay = mat

# Visual deck height: 0 on flat ground, an arc while crossing a bridge (manager-driven).
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

func _find_skeleton(n: Node) -> Skeleton3D:
	for c in n.get_children():
		if c is Skeleton3D:
			return c
		var found := _find_skeleton(c)
		if found:
			return found
	return null

# Attach the sword to the hand bone via a BoneAttachment3D. Scale/offset/rotation
# are exported tunables — the hand-bone frame can't be eyeballed from code.
func _equip_weapon() -> void:
	if not equip_weapon:
		return
	var skel := _find_skeleton(self)
	if skel == null or skel.find_bone(weapon_bone) == -1:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = weapon_bone
	skel.add_child(att)
	var sword: Node3D = SWORD_SCENE.instantiate()
	att.add_child(sword)
	sword.scale = Vector3.ONE * weapon_scale
	sword.position = weapon_offset_pos
	sword.rotation_degrees = weapon_offset_rot

# --- Animation helpers (mirrors auto_wander.gd) ---
func _find_anim_player(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		if c is AnimationPlayer:
			return c
		var found := _find_anim_player(c)
		if found:
			return found
	return null

# Return the first clip whose name contains any of the given substrings.
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

# Stand still: idle clip if available, else stop so we settle into rest pose
# instead of walking in place.
func _stand() -> void:
	if _idle_clip != "":
		_play(_idle_clip, true)
	elif _anim and _anim.is_playing():
		_anim.stop()

# --- Target selection ---
# Returns the chosen target node (unit or base) or null if nothing to fight.
# Throttled: reuse the cached target until it dies/goes invalid or the timer
# elapses (a few times a second). The actual nearest-enemy scan is O(n) per unit,
# so running it every frame is O(n^2) — the dominant CPU cost on mobile. A <=0.2s
# delay before switching targets is imperceptible in this slow auto-battler.
func _pick_target():
	_retarget_t -= get_process_delta_time()
	if _retarget_t > 0.0 and is_instance_valid(_cached_target) and _cached_target.alive:
		return _cached_target
	_retarget_t = RETARGET_INTERVAL
	_cached_target = _acquire_target()
	return _cached_target

func _acquire_target():
	var unit = _manager.get_nearest_enemy(global_position, team)
	if is_instance_valid(unit) and unit.alive:
		var d := _horiz_dist(global_position, unit.global_position)
		if d <= aggro_radius:
			return unit
	# Fall back to the enemy base while it still stands.
	if is_instance_valid(_enemy_base) and _enemy_base.alive:
		return _enemy_base
	return null

func _horiz_dist(a: Vector3, b: Vector3) -> float:
	var to := b - a
	to.y = 0.0
	return to.length()

# Deliver the hit partway into the swing so the damage lines up with the animation.
func _schedule_hit(target) -> void:
	await get_tree().create_timer(attack_hit_delay).timeout
	if not alive or not is_instance_valid(target):
		return
	if target.alive:
		target.take_damage(damage)
		SFX.play(self, "res://audio/sword_hit", -12.0)

# --- Main AI loop ---
func _process(delta: float) -> void:
	if not alive:
		return
	# Cooldown always advances.
	if _attack_timer > 0.0:
		_attack_timer -= delta
	# Drive the procedural attack chop (body-pitch overlay), if one is active.
	_update_swing(delta)

	# A real mocap swing clip (if the model ever has one) plays uninterrupted.
	if _attacking:
		return

	var target = _pick_target()
	if target == null:
		_stand()
		return

	# In-range threshold depends on the target's own radius.
	var range_pad: float = attack_range + target.radius
	var dist := _horiz_dist(global_position, target.global_position)

	if dist <= range_pad:
		# --- Attack state: face, keep limbs alive, swing on cooldown ---
		_face(target.global_position, delta)
		_play(_walk_clip, true)   # greg has no idle clip; keep him moving, not T-posed
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			SFX.play(self, "res://audio/sword_swing")
			_schedule_hit(target)   # damage lands partway into the swing, not at frame 0
			if _attack_clip != "":
				_attacking = true
				_play(_attack_clip, false, attack_anim_speed)
			else:
				_swing_t = 0.0    # start a procedural chop
		position.y = _bridge_y()
		return

	# --- Move state: face + walk toward target (routed around the moat) ---
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

# Procedural attack swing: a quick forward chop of the whole body on rotation.x.
# Conflict-free — the AI owns yaw (rotation.y) and the manager owns position, so
# pitching rotation.x is ours alone. Used when the model has no baked attack clip.
func _update_swing(delta: float) -> void:
	if _swing_t < 0.0:
		return
	_swing_t += delta
	var p := _swing_t / swing_time
	if p >= 1.0:
		_swing_t = -1.0
		rotation.x = 0.0
	else:
		# 0 -> peak -> 0 over the swing: a snappy forward chop.
		rotation.x = -sin(p * PI) * swing_angle

# Smooth yaw toward a world-space point (yaw only).
func _face(toward: Vector3, delta: float) -> void:
	var to := toward - global_position
	to.y = 0.0
	if to.length() < 0.0001:
		return
	var desired_yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))
