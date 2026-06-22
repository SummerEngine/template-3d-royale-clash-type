extends Node3D
# Auto-wander: pick a random point on the island, turn + walk toward it,
# pause on arrival (and sometimes throw an attack), then pick a new point.
# No player input. Plays real baked clips found on the model's AnimationPlayer.

@export var half_extent: float = 17.0   # inset from the 20-unit island half-width
@export var move_speed: float = 2.2      # units/sec (tuned to the walk cycle)
@export var turn_speed: float = 6.0      # yaw slerp factor
@export var arrive_dist: float = 0.6
@export var pause_min: float = 0.6
@export var pause_max: float = 1.8
@export var attack_chance: float = 0.4   # chance to attack during a pause

var _target: Vector3
var _pause_timer: float = 0.0
var _base_y: float = 0.0
var _anim: AnimationPlayer
var _walk_clip: String = ""
var _idle_clip: String = ""
var _attack_clip: String = ""
var _attacking: bool = false

func _ready() -> void:
	_base_y = position.y
	_anim = _find_anim_player(self)
	if _anim:
		_walk_clip = _match_clip(["walk"])
		_idle_clip = _match_clip(["idle", "stand", "tpose", "rest"])
		_attack_clip = _match_clip(["attack", "swing", "slash", "punch"])
		_anim.animation_finished.connect(_on_anim_finished)
	_pick_target()

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

func _pick_target() -> void:
	_target = Vector3(
		randf_range(-half_extent, half_extent),
		_base_y,
		randf_range(-half_extent, half_extent)
	)

func _play(clip: String, loop_it: bool) -> void:
	if _anim == null or clip == "" or _anim.current_animation == clip:
		return
	_anim.play(clip)
	var anim := _anim.get_animation(clip)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if loop_it else Animation.LOOP_NONE

func _on_anim_finished(anim_name: String) -> void:
	if anim_name == _attack_clip:
		_attacking = false

# Stand still: play an idle clip if the model has one, otherwise stop the
# AnimationPlayer so he settles into his rest pose instead of walking in place.
func _stand() -> void:
	if _idle_clip != "":
		_play(_idle_clip, true)
	elif _anim and _anim.is_playing():
		_anim.stop()

func _process(delta: float) -> void:
	# Let an in-progress attack finish before doing anything else.
	if _attacking:
		return

	if _pause_timer > 0.0:
		_pause_timer -= delta
		_stand()
		return

	var to_target := _target - position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist <= arrive_dist:
		_pause_timer = randf_range(pause_min, pause_max)
		# Maybe throw an attack on arrival.
		if _attack_clip != "" and randf() < attack_chance:
			_attacking = true
			_play(_attack_clip, false)
		else:
			_stand()
		_pick_target()
		return

	var dir := to_target / dist

	# Face the direction of travel (yaw only), smoothly.
	var desired_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))

	# Move + play the walk cycle.
	position += dir * move_speed * delta
	position.y = _base_y
	_play(_walk_clip, true)
