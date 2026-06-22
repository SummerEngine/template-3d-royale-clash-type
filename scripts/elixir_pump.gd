extends Node3D
# Elixir pump — a buildable, destructible structure raised by a Builder. While it
# stands it produces elixir for its owner team on a timer, with a deliberately
# loud "+1" burst so the player can't miss it. It is a TARGET like a unit/base:
# enemy units attack it when they're near (registered with the manager's
# structures list, scanned by get_nearest_enemy). It is NOT a unit — it isn't in
# the manager's separation/clamp pass, so it just sits where it was built.
#
# Spawned by the Builder: instantiate the glb, set_script(this), add_child() +
# global_position, then setup(team, manager, scale).

@export var max_hp: float = 150.0           # finished pump; the half-built site has 75
@export var radius: float = 1.6             # targeting / attack-range radius read by attackers
@export var generate_interval: float = 10.0 # seconds between elixir ticks
@export var generate_amount: float = 1.0    # elixir produced per tick
@export var fade_time: float = 0.7          # crumble duration on death

const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")
const HEALTH_BAR := preload("res://scripts/health_bar.gd")

# --- Runtime state (duck-typed like the units: team / alive / hp / radius) ---
var team: int = 0
var alive: bool = true
var hp: float = 0.0

var _manager = null          # BattleManager — untyped for cross-script duck typing
var _rest_scale: float = 1.0

# Called by the Builder AFTER add_child() + global_position are set. start_damage
# carries over the hits the half-finished site took, so completing it doesn't heal.
func setup(p_team: int, p_manager, target_scale: float, r: float, start_damage: float = 0.0) -> void:
	team = p_team
	_manager = p_manager
	_rest_scale = target_scale
	radius = r
	hp = max_hp - start_damage   # finished pump inherits the site's damage (no heal-on-complete)
	alive = true
	if is_instance_valid(_manager) and _manager.has_method("register_pump"):
		_manager.register_pump(self, radius, team)   # one entry drives both push-out and enemy targeting
	_apply_tint()
	_add_health_bar()
	# Pop in from nothing so it reads as "just built".
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * _rest_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Elixir generation timer.
	var t := Timer.new()
	t.name = "GenTimer"
	t.wait_time = generate_interval
	t.autostart = true
	t.timeout.connect(_on_generate)
	add_child(t)

# --- Damage / death (same duck-typed contract attackers expect) ---
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * _rest_scale)
	if hp <= 0.0:
		alive = false   # manager skips dead pumps for targeting/push-out and drops them once freed
		_die()

func _die() -> void:
	var t := get_node_or_null("GenTimer")
	if t:
		t.queue_free()
	var hb := get_node_or_null("HealthBar")
	if hb:
		hb.visible = false
	SFX.play(self, "res://audio/house_hit", 3.0)   # crumble thunk (reuse)
	# Crumble: shrink + sink + a little spin, then free.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ZERO, fade_time).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y - 0.6 * _rest_scale, fade_time)
	tw.tween_property(self, "rotation:y", rotation.y + 0.7, fade_time)
	await tw.finished
	if is_instance_valid(self):
		queue_free()

# --- Elixir generation + its (deliberately loud) feedback ------------------
func _on_generate() -> void:
	if not alive:
		return
	if is_instance_valid(_manager) and _manager.has_method("add_elixir"):
		_manager.add_elixir(team, generate_amount)   # only the player (team 0) has an economy
	_generate_fx()

func _generate_fx() -> void:
	# 1) The pump itself bounces (squash up, elastic settle).
	var rest := Vector3.ONE * _rest_scale
	var tw := create_tween()
	tw.tween_property(self, "scale", rest * Vector3(0.86, 1.2, 0.86), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", rest, 0.42).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 2) A drop icon + "+1" that pop, rise, and fade above the pump.
	_float_plus_one()
	# 3) Sound.
	SFX.play(self, "res://audio/elixir_collect", -3.0)

# Spawn the floating "+1 drop" in world space (parented to our parent, which has
# no transform, so the pump's scale/bounce doesn't distort it).
func _float_plus_one() -> void:
	var host := get_parent()
	if host == null:
		return
	var top := global_position + Vector3(0.0, 2.4 * _rest_scale, 0.0)

	var icon := Sprite3D.new()
	var tex := _load_tex("res://ui/elixir_drop.png")
	if tex != null:
		icon.texture = tex
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.pixel_size = 0.0035
	host.add_child(icon)
	icon.position = top + Vector3(-0.7, 0.0, 0.0)
	_rise_and_fade(icon)

	var lbl := Label3D.new()
	lbl.text = "+1"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 110
	lbl.outline_size = 14
	lbl.modulate = Color(0.85, 0.45, 1.0)          # elixir purple
	lbl.outline_modulate = Color(0.05, 0.0, 0.1)
	lbl.pixel_size = 0.012
	host.add_child(lbl)
	lbl.position = top + Vector3(0.35, 0.0, 0.0)
	_rise_and_fade(lbl)

func _rise_and_fade(n: Node3D) -> void:
	n.scale = Vector3.ONE * 0.3
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "position:y", n.position.y + 1.8, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(n.queue_free)

# --- Subtle team tint so player vs enemy pumps are tellable apart ----------
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
	bar.height_above = 1.4               # local; the pump's rest scale lifts it over the dome
	if _rest_scale != 0.0:
		bar.scale = Vector3.ONE / _rest_scale  # counter the pump scale so the bar stays unit-sized
	add_child(bar)

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	return null
