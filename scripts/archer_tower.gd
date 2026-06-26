extends Node3D
# Archer Tower — a placeable wooden defensive building. Spawned at runtime by a
# hotbar card (catalog kind "building"): it stands still, rains arrows on the
# nearest enemy in range, and slowly ROTS (loses HP over time) so it's temporary.
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
@export var attack_range: float = 7.0      # horizontal range it can shoot within
@export var arrow_damage: float = 8.0      # damage per arrow
@export var fire_interval: float = 0.8     # seconds between shots
@export var fade_time: float = 0.7         # crumble duration on death

const SFX := preload("res://scripts/sfx.gd")
const HITFX := preload("res://scripts/hit_fx.gd")
const HOUSE_BAR := preload("res://scripts/house_health_bar.gd")

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
	# A quick arrow tracer from the lookout to the target, plus the damage.
	var top: Vector3 = global_position + Vector3(0.0, _rest_scale * 1.2, 0.0)
	var aim: Vector3 = target.global_position + Vector3(0.0, 0.6, 0.0)
	_spawn_arrow(top, aim)
	if target.has_method("take_damage"):
		target.take_damage(arrow_damage)


func _spawn_arrow(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 0.9)   # a short shaft
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.34, 0.16)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	var host = get_parent()
	if host == null:
		host = self
	host.add_child(mi)
	mi.global_position = from
	if from.distance_to(to) > 0.05:
		mi.look_at(to, Vector3.UP)
	var t := mi.create_tween()
	t.tween_property(mi, "global_position", to, 0.12)
	t.tween_callback(mi.queue_free)


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
