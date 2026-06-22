extends Node3D
# Builder unit — a non-combat dwarf for the team-vs-team battler. Spawned from a
# Flying Dwarf GLB via set_script(). The manager calls setup() then add_child()s
# us and sets global_position.
#
# Behavior (per frame in _process):
#   - On first frame, pick a build spot a short way out from spawn toward map
#     center.
#   - Walk to the build spot (walk clip), then plant and play the hammer "build"
#     animation in a loop ("building").
#   - It does NOT attack. It can be attacked and dies like any unit (death clip
#     + fade). After build_time seconds of hammering it raises an elixir pump
#     (elixir_pump.gd on the glb), then marches forward toward the enemy and
#     builds another — on and on until it's killed.

# --- Tunables (designer-balanced; no clamps/floors added) ---
@export var max_hp: float = 50.0
@export var move_speed: float = 1.9       # units/sec
@export var turn_speed: float = 6.0       # yaw lerp factor
@export var radius: float = 0.91          # soft-collision radius; read by manager
@export var visual_scale: float = 1.3     # uniform model scale (+30%, matches other units)
@export var fade_time: float = 0.8        # seconds to fade the corpse out after the death clip
@export var march_jitter: float = 0.4     # +/- fraction randomness on the march distance so pumps space out
@export var pump_spacing: float = 4.0     # won't build this close to an existing pump — marches on to clear ground
@export var build_anim_speed: float = 2.0 # play the hammer "build" clip this much faster
@export var build_time: float = 5.0       # seconds of hammering before the pump structure appears
@export var pump_scale: float = 2.4       # uniform scale of the elixir pump (+20% visual; collision = pump_radius)
@export var pump_radius: float = 0.3      # small push-out radius so troops brush past; only shoved if nearly on top
@export var site_offset: float = 1.6      # how far ahead (toward the enemy) to plant the half-finished pump
@export var moat_clear: float = 2.8       # won't build if the pump would land within this of the moat centre
@export var forward_step: float = 6.0     # distance marched toward the enemy before building the next pump
@export var field_limit: float = 18.0     # keep build spots just inside the island walls so they stay reachable
# Hammer equip (placement is exported because the hand-bone frame can't be eyeballed from code — TUNE).
@export var equip_hammer: bool = true
@export var hammer_bone: String = "RightHand"
@export var hammer_scale: float = 80.0    # ~100x to cancel the rig's 0.01 (cm) armature scale
@export var hammer_offset_pos: Vector3 = Vector3.ZERO     # local position in the hand
@export var hammer_offset_rot: Vector3 = Vector3.ZERO     # local rotation (degrees) in the hand

const HAMMER_PATH := "res://models/hammer.glb"   # loaded at runtime: may not exist until generated
const PUMP_PATH := "res://models/elixir_pump.glb"   # the structure the builder builds; loaded at runtime
const PUMP := preload("res://scripts/elixir_pump.gd")   # script applied to the spawned pump glb
const SITE_PATH := "res://models/elixir_pump_building.glb"   # half-finished pump raised while building
const SITE := preload("res://scripts/pump_site.gd")          # script applied to the half-finished pump glb
const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")

# --- Runtime state ---
var team: int = 0
var alive: bool = true
var hp: float = 0.0

var _manager = null        # BattleManager — untyped for cross-script duck typing
var _enemy_base = null      # unused (peaceful) — kept for setup() parity with other units

var _base_y: float = 0.0
var _building: bool = false        # false = marching toward the enemy; true = planted and hammering
var _walked: float = 0.0           # distance marched on the current leg
var _walk_target: float = -1.0     # leg length before we plant (<0 = pick a fresh leg)
var _build_sfx_t: float = 0.0
var _build_progress: float = 0.0   # seconds spent hammering at the current spot
var _built: bool = false           # (vestigial; retained in case other systems read it)
var _site = null                   # the half-finished pump we're hammering on (pump_site.gd); null while marching

# --- Animation ---
var _anim: AnimationPlayer = null
var _walk_clip: String = ""
var _idle_clip: String = ""
var _build_clip: String = ""   # the hammer-swing, repurposed as "build"

func setup(p_team: int, p_manager: Node, p_enemy_base: Node3D) -> void:
	team = p_team
	_manager = p_manager
	_enemy_base = p_enemy_base
	_apply_tint()

func _ready() -> void:
	hp = max_hp
	scale = Vector3.ONE * visual_scale
	_base_y = position.y
	_anim = _find_anim_player(self)
	if _anim:
		# Merge the dwarf's extra clips (idle / run / dead / hammer) into an editable
		# "extra" library; walk comes from the running GLB. Imported "" is read-only.
		var dclips := DwarfAnims.clips()
		if not dclips.is_empty() and not _anim.has_animation_library("extra"):
			var extra := AnimationLibrary.new()
			for cname in dclips:
				extra.add_animation(cname, dclips[cname])
			_anim.add_animation_library("extra", extra)
		_walk_clip = _match_clip(["walk"])
		_idle_clip = _match_clip(["idle", "stand", "rest"])
		_build_clip = _match_clip(["hammer", "swing", "build", "attack"])
	# Floating health bar above this unit.
	var bar := preload("res://scripts/health_bar.gd").new()
	bar.name = "HealthBar"
	add_child(bar)
	_equip_hammer()
	SFX.play(self, "res://audio/barbarian_spawn", -24.0)

# --- Damage / death (same contract as the other units) ---
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

func _die() -> void:
	set_process(false)
	SFX.play(self, "res://audio/barbarian_death", -14.0)
	_building = false
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

# --- Main loop: march toward the enemy, then plant and build where we end up ---
func _process(delta: float) -> void:
	if not alive:
		return
	if _building:
		_build_in_place(delta)
	else:
		_march_toward_enemy(delta)

# March toward the enemy base. Once we've covered a (randomized) leg distance AND
# we're on clear ground (no pump too close), plant and start building right here —
# we never aim at a precise pre-chosen point.
func _march_toward_enemy(delta: float) -> void:
	if _walk_target < 0.0:
		_walk_target = forward_step * (1.0 + randf_range(-march_jitter, march_jitter))
		_walked = 0.0
	var goal := _enemy_goal()
	if is_instance_valid(_manager) and _manager.has_method("moat_route"):
		goal = _manager.moat_route(global_position, _enemy_goal())
	var to := goal - global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.001:
		var dir := to / d
		_face(goal, delta)
		var step := move_speed * delta
		position += dir * step
		_walked += step
	position.y = _bridge_y()
	_play(_walk_clip, true)
	if _walked >= _walk_target and _spot_is_clear():
		_begin_build()

# Start building here: raise the half-finished pump just ahead, then commit to it.
func _begin_build() -> void:
	_building = true
	_build_progress = 0.0
	_spawn_site()

# Drop the half-finished pump (a destructible, inert site) a step ahead toward the
# enemy, so we hammer next to it. Parented to the battle root so it survives our
# death — the enemy can then tear the abandoned site down.
func _spawn_site() -> void:
	_site = null
	if not ResourceLoader.exists(SITE_PATH):
		return
	var ps = load(SITE_PATH)
	if ps == null:
		return
	var host := get_parent()
	if host == null:
		return
	var dir := _enemy_goal() - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var site_pos := global_position + dir * site_offset
	site_pos.y = 0.0
	var s = ps.instantiate()
	s.set_script(SITE)
	host.add_child(s)
	s.global_position = site_pos
	s.setup(team, _manager, pump_scale, pump_radius)
	_site = s

# Plant and hammer next to the half-finished pump. No fixed spot — pushes just
# drift us; committed until the pump is done. If the site is destroyed under us
# (enemy smashed it), abandon this one and march on.
func _build_in_place(delta: float) -> void:
	if ResourceLoader.exists(SITE_PATH) and not is_instance_valid(_site):
		_building = false
		_walk_target = -1.0
		return
	var look: Vector3 = _site.global_position if is_instance_valid(_site) else _enemy_goal()
	_face(look, delta)
	if _build_clip != "":
		_play(_build_clip, true, build_anim_speed)
	else:
		_stand()
	position.y = _bridge_y()
	_on_build_tick(delta)

# Accumulate build progress while hammering; once build_time elapses, raise the
# elixir pump structure at the build spot. Runs every frame in the build state.
func _on_build_tick(delta: float) -> void:
	_build_sfx_t -= delta
	if _build_sfx_t <= 0.0:
		_build_sfx_t = 0.55
		SFX.play(self, "res://audio/house_hit", -7.0)   # hammer tink while building
	_build_progress += delta
	if _build_progress >= build_time:
		_finish_build()

# Build complete: raise the pump, then go back to marching toward the enemy to
# find the next bit of clear ground. build → march → build, until it dies.
func _finish_build() -> void:
	# The finished pump rises where the half-finished one stood (fallback: our spot).
	var at := global_position
	var carried_damage := 0.0
	if is_instance_valid(_site):
		at = _site.global_position
		carried_damage = maxf(0.0, _site.max_hp - _site.hp)   # hits the scaffold took
		_site.complete()   # remove the half-finished placeholder
	_site = null
	_spawn_pump(at, carried_damage)
	_building = false
	_walk_target = -1.0   # pick a fresh march leg next frame

# Drop the pump at our feet, parented to the battle root so it outlives us. The
# pump script self-registers (push-out + targeting), pops itself in, and starts
# generating elixir for our team. Loaded at runtime so the builder still works if
# the asset is missing.
func _spawn_pump(at: Vector3, carried_damage: float = 0.0) -> void:
	if not ResourceLoader.exists(PUMP_PATH):
		return
	var ps = load(PUMP_PATH)
	if ps == null:
		return
	var host := get_parent()
	if host == null:
		return
	var pump = ps.instantiate()
	pump.set_script(PUMP)
	host.add_child(pump)
	pump.global_position = Vector3(at.x, 0.0, at.z)
	pump.setup(team, _manager, pump_scale, pump_radius, carried_damage)
	SFX.play(self, "res://audio/house_hit", 0.0)   # a final, louder "done" thunk

# The enemy base position on the ground plane (the march + face goal); falls back
# to map center if the base is gone.
func _enemy_goal() -> Vector3:
	if is_instance_valid(_enemy_base):
		var p: Vector3 = _enemy_base.global_position
		return Vector3(p.x, 0.0, p.z)
	return Vector3.ZERO

# True when no existing pump crowds our current position, so we keep marching to
# find clear ground instead of stacking pumps on top of each other.
func _spot_is_clear() -> bool:
	# Never plant where the pump would land in the moat (water or a bridge) — check
	# the prospective site spot, a step ahead toward the enemy.
	if is_instance_valid(_manager) and _manager.has_method("over_moat"):
		var dir := _enemy_goal() - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		if _manager.over_moat(global_position + dir * site_offset, moat_clear):
			return false
	if _manager != null and _manager.has_method("pump_near"):
		return not _manager.pump_near(global_position, pump_spacing)
	return true

# --- Hammer equip: attach to the hand bone via a BoneAttachment3D. Loaded at
# runtime (not preloaded) so the unit still works before the hammer asset exists.
func _equip_hammer() -> void:
	if not equip_hammer or not ResourceLoader.exists(HAMMER_PATH):
		return
	var ps = load(HAMMER_PATH)
	if ps == null:
		return
	var skel := _find_skeleton(self)
	if skel == null or skel.find_bone(hammer_bone) == -1:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = hammer_bone
	skel.add_child(att)
	var hammer: Node3D = ps.instantiate()
	att.add_child(hammer)
	hammer.scale = Vector3.ONE * hammer_scale
	hammer.position = hammer_offset_pos
	hammer.rotation_degrees = hammer_offset_rot

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

# --- Animation helpers ---
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
	if _anim.current_animation == clip:
		return   # already on this clip; speed was applied when it started — don't restart
	_anim.play(clip, -1, speed)
	var anim := _anim.get_animation(clip)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if loop_it else Animation.LOOP_NONE

func _stand() -> void:
	if _idle_clip != "":
		_play(_idle_clip, true)
	elif _anim and _anim.is_playing():
		_anim.stop()

# Smooth yaw toward a world-space point (yaw only).
func _face(toward: Vector3, delta: float) -> void:
	var to := toward - global_position
	to.y = 0.0
	if to.length() < 0.0001:
		return
	var desired_yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))
