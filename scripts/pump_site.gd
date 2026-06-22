extends Node3D
# Half-finished elixir pump — the construction site a Builder raises while it
# hammers. It is an INERT, destructible structure: it registers with the manager
# like a real pump (so enemies target + smash it, and units brush around it) but
# it generates NO elixir and has no "+1" feedback. The Builder calls complete()
# and drops a finished pump in its place when the build succeeds; if the Builder
# dies first, the site is simply left standing for the enemy to tear down.
#
# Spawned by the Builder: instantiate the half-pump glb, set_script(this),
# add_child() + global_position, then setup(team, manager, scale, radius).

@export var max_hp: float = 75.0      # half the finished pump (150) — it's incomplete
@export var radius: float = 1.6       # targeting / push-out radius (overridden by setup)
@export var fade_time: float = 0.6    # crumble duration on death

const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")
const HEALTH_BAR := preload("res://scripts/health_bar.gd")

# --- Runtime state (duck-typed like units/pumps: team / alive / hp / radius) ---
var team: int = 0
var alive: bool = true
var hp: float = 0.0

var _manager = null          # BattleManager — untyped for cross-script duck typing
var _rest_scale: float = 1.0

# Called by the Builder AFTER add_child() + global_position are set.
func setup(p_team: int, p_manager, target_scale: float, r: float) -> void:
	team = p_team
	_manager = p_manager
	_rest_scale = target_scale
	radius = r
	hp = max_hp
	alive = true
	if is_instance_valid(_manager) and _manager.has_method("register_pump"):
		_manager.register_pump(self, radius, team)   # push-out + enemy targeting; NO elixir
	_apply_tint()
	_add_health_bar()
	# Pop in from nothing so it reads as "just started".
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * _rest_scale, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Damage / death (same duck-typed contract attackers expect) ---
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * _rest_scale)
	if hp <= 0.0:
		alive = false   # manager skips dead sites for targeting/push-out, drops them once freed
		_die()

func _die() -> void:
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.visible = false
	SFX.play(self, "res://audio/house_hit", 3.0)   # crumble thunk (reuse)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ZERO, fade_time).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y - 0.4 * _rest_scale, fade_time)
	await tw.finished
	if is_instance_valid(self):
		queue_free()

# Builder finished the real pump here: drop the site silently (no crumble fx). It
# stops being a target/obstacle immediately (alive=false), then frees itself.
func complete() -> void:
	alive = false
	queue_free()

# --- Subtle team tint so player vs enemy sites are tellable apart -----------
func _apply_tint() -> void:
	var mesh := _find_mesh_instance(self)
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.45, 0.95, 0.18) if team == 0 else Color(0.9, 0.2, 0.2, 0.18)
	mesh.material_overlay = mat

func _add_health_bar() -> void:
	var bar = HEALTH_BAR.new()
	bar.name = "HealthBar"
	bar.height_above = 1.4
	if _rest_scale != 0.0:
		bar.scale = Vector3.ONE / _rest_scale   # counter the site scale so the bar stays unit-sized
	add_child(bar)

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null
