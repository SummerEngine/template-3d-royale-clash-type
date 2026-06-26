extends Node3D
# Cannon — a placeable defensive building. Spawned at runtime by a hotbar card
# (catalog kind "building"): it stands still, rotates to face the nearest enemy in
# range and lobs a big cannonball (boom + recoil kick), and slowly ROTS (loses HP
# over time) so it's temporary.
# Registers with the battle manager as a "pump" (the generic targetable + immovable
# structure channel), so enemy troops attack it and walking units get shoved out of
# its footprint. Destroying it does NOT end the match.
#
# Spawn contract (the building card path in battle_manager): setup(team, manager) is
# called BEFORE add_child(); global_position is set by the spawner AFTER add_child().

@export var max_hp: float = 80.0
@export var decay_per_sec: float = 2.0     # passive rot — 80 / 2 = ~40s if never attacked
@export var radius: float = 1.6            # footprint push-out + targeting radius
@export var visual_scale: float = 2.6      # the GLB imports ~1 unit; scale it up to building size
@export var attack_range: float = 10.0     # horizontal range it can shoot within
@export var shot_damage: float = 8.0       # damage per cannonball
@export var fire_interval: float = 0.8     # seconds between shots
@export var fade_time: float = 0.7         # crumble duration on death
# Cannon aiming / muzzle (the GLB's barrel facing can't be known from code — tune).
@export var aim_yaw_offset: float = 0.0    # degrees added to the facing yaw if the model points the wrong way
@export var muzzle_height: float = 1.1     # muzzle Y above the base, in rest-scale units
@export var muzzle_forward: float = 0.9    # muzzle forward offset toward the target, in rest-scale units
@export var cannonball_scale: float = 0.8  # uniform scale of the cannonball model (the glb imports ~1 unit)

const SFX := preload("res://scripts/sfx.gd")
const HITFX := preload("res://scripts/hit_fx.gd")
const HOUSE_BAR := preload("res://scripts/house_health_bar.gd")
const CANNONBALL_PATH := "res://models/cannonball/cannonball.glb"   # loaded at runtime; falls back to a sphere if missing

var team: int = 0
var hp: float = 0.0
var alive: bool = true
var _manager = null            # BattleManager — untyped for cross-script duck typing
var _rest_scale: float = 1.0
var _fire_t: float = 0.0


func setup(team_: int, manager) -> void:
	team = team_
	_manager = manager


func _ready() -> void:
	scale = Vector3.ONE * visual_scale
	_rest_scale = visual_scale
	hp = max_hp
	alive = true
	_fire_t = fire_interval * 0.5   # stagger the first shot a little
	if _manager != null and _manager.has_method("register_pump"):
		_manager.register_pump(self, radius, team)   # targetable + immovable, same channel as pumps
	_apply_team_tint()
	_add_health_bar()


func _process(delta: float) -> void:
	if not alive:
		return
	# Passive rot: bleed HP over time so the tower is temporary.
	hp -= decay_per_sec * delta
	if hp <= 0.0:
		alive = false
		_die()
		return
	# Fire at the nearest enemy in range on a fixed cadence.
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = fire_interval
		_try_fire()


func _try_fire() -> void:
	if _manager == null or not _manager.has_method("get_nearest_enemy"):
		return
	var target = _manager.get_nearest_enemy(global_position, team)
	if target == null or not is_instance_valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	if to.length() > attack_range:
		return
	_fire_at(target)


func _fire_at(target) -> void:
	# Rotate the cannon to face the target (yaw only), then lob a cannonball from the muzzle.
	var dir: Vector3 = target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z) + deg_to_rad(aim_yaw_offset)
	var muzzle := _muzzle_point(target.global_position)
	_fire_juice(muzzle)
	_spawn_cannonball(muzzle, target.global_position + Vector3(0.0, 0.6, 0.0), target)


# World point at the barrel tip: up off the base, then forward toward the target.
func _muzzle_point(target_pos: Vector3) -> Vector3:
	var fwd := target_pos - global_position
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return global_position + Vector3.UP * (_rest_scale * muzzle_height) + fwd * (_rest_scale * muzzle_forward)


# Boom the instant it fires: a muzzle flash, a kick-back squash, and a report.
func _fire_juice(muzzle: Vector3) -> void:
	SFX.play(self, "res://audio/cannon_fire", -2.0)   # the boom as it fires
	var rest := Vector3.ONE * _rest_scale
	var tw := create_tween()
	tw.tween_property(self, "scale", rest * Vector3(1.12, 0.88, 1.12), 0.05)
	tw.tween_property(self, "scale", rest, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_boom_fx(muzzle, 1.1)


# The flying cannonball: the 3D model if it's imported, else a glowing fallback
# sphere (used before Godot has imported the glb).
func _make_ball() -> Node3D:
	if ResourceLoader.exists(CANNONBALL_PATH):
		var ps = load(CANNONBALL_PATH)
		if ps is PackedScene:
			var inst: Node3D = ps.instantiate()
			inst.scale = Vector3.ONE * cannonball_scale
			return inst
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.1, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.12)
	m.emission_energy_multiplier = 1.8
	mi.material_override = m
	return mi


# Big cannonball that arcs from the muzzle to the target, then explodes and deals
# the damage on impact.
func _spawn_cannonball(from: Vector3, to: Vector3, target) -> void:
	var ball := _make_ball()
	var host = get_parent()
	if host == null:
		host = self
	host.add_child(ball)
	ball.global_position = from
	var dmg := shot_damage
	var tgt = target
	var dur := 0.22
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "global_position:x", to.x, dur)
	tw.tween_property(ball, "global_position:z", to.z, dur)
	var peak: float = maxf(from.y, to.y) + 1.2
	var yt := ball.create_tween()
	yt.tween_property(ball, "global_position:y", peak, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	yt.tween_property(ball, "global_position:y", to.y, dur * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	yt.tween_callback(func() -> void:
		_boom_fx(to, 1.6)
		SFX.play(self, "res://audio/cannon_impact", -4.0)   # cannonball lands
		if is_instance_valid(tgt) and tgt.has_method("take_damage"):
			tgt.take_damage(dmg)
		if is_instance_valid(ball):
			ball.queue_free())


# A quick expanding additive fireball at `center` (muzzle flash + impact burst).
func _boom_fx(center: Vector3, size: float) -> void:
	var host = get_parent()
	if host == null:
		host = self
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.6, 0.25, 0.9)
	ball.material_override = mat
	host.add_child(ball)
	ball.global_position = center
	ball.scale = Vector3.ONE * 0.2
	var t := ball.create_tween()
	t.set_parallel(true)
	t.tween_property(ball, "scale", Vector3.ONE * size, 0.22).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	t.set_parallel(false)
	t.tween_callback(ball.queue_free)


# --- Damage / death (the duck-typed contract attackers expect) ---
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * _rest_scale)
	SFX.play(self, "res://audio/house_hit")
	if hp <= 0.0:
		alive = false
		_die()


func _die() -> void:
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.visible = false
	SFX.play(self, "res://audio/house_destroyed", 2.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ZERO, fade_time).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y - 0.6 * _rest_scale, fade_time)
	tw.tween_property(self, "rotation:y", rotation.y + 0.7, fade_time)
	await tw.finished
	if is_instance_valid(self):
		queue_free()


# Subtle team tint so player vs enemy towers read apart (matches base.gd / pumps).
func _apply_team_tint() -> void:
	var mesh := _find_mesh_instance(self)
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.45, 0.95, 0.16) if team == 0 else Color(0.9, 0.2, 0.2, 0.16)
	mesh.material_overlay = mat


# Floating health bar — same big billboarded style as the houses/princess towers, sized
# down. Lives in WORLD space (parented to our parent, not us) so it never inherits the
# tower's scale; it reads our hp/max_hp/alive/team and auto-hides when we die.
func _add_health_bar() -> void:
	var bar = HOUSE_BAR.new()
	bar.name = "HealthBar"
	bar.bar_width = 2.6
	bar.bar_height = 0.40
	bar.margin_above = 1.4
	bar.bind(self)   # contract: bind() BEFORE the node enters the tree
	# Defer the add: during our own _ready the parent is still busy, so a direct
	# get_parent().add_child() is refused. bind() already ran, so the bar's _ready
	# sees us fine once it's added next idle frame.
	var host := get_parent()
	if host != null:
		host.add_child.call_deferred(bar)
	else:
		add_child.call_deferred(bar)


func _find_mesh_instance(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null
