extends Node3D
# Princess tower — a smaller house that flanks a team's main base (King), two per
# side, forward-left and forward-right, Clash-Royale style. It's a DESTRUCTIBLE
# DEFENSIVE STRUCTURE: enemy units target and attack it like a pump, and it shoves
# units out of its footprint. But unlike the main House (base.gd), destroying a
# Princess tower does NOT end the game — only the King (base) is the loss condition.
#
# Pre-placed in the scene with its transform (incl. scale) baked in. On _ready it
# finds the BattleManager among its siblings and registers itself via register_pump
# (the manager's generic "targetable, immovable enemy structure" channel), so all
# the targeting / push-out / cleanup logic is reused with no manager changes.

@export var team: int = 0          # 0 = player (blue), 1 = enemy (red)
@export var max_hp: float = 140.0  # tankier than a unit, softer than the King (220)
@export var radius: float = 2.0    # targeting / push-out radius (main base is 2.772 at 8x; this is ~6x)
@export var fade_time: float = 0.7 # crumble duration on death

const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")
const HOUSE_BAR := preload("res://scripts/house_health_bar.gd")   # big floating bar, same as the houses

var hp: float = 0.0
var alive: bool = true
var _rest_scale: float = 1.0       # the baked uniform scale, read off our transform
var _manager = null                # BattleManager — untyped for cross-script duck typing

func _ready() -> void:
	hp = max_hp
	alive = true
	_rest_scale = scale.x          # uniform scale baked into the .tscn transform
	_manager = _find_manager()
	if _manager != null and _manager.has_method("register_pump"):
		_manager.register_pump(self, radius, team)   # same channel as elixir pumps: targetable + immovable
	_apply_team_tint()
	_add_health_bar()

# --- Damage / death (the duck-typed contract attackers expect) ---
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), Vector3.ONE * _rest_scale)
	SFX.play(self, "res://audio/house_hit")
	if hp <= 0.0:
		alive = false   # manager skips dead structures for targeting/push-out, drops them once freed
		_die()

# Crumble and free. Notably does NOT emit any game-ending signal — the King lives on.
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

# Find the BattleManager sibling (the node exposing register_pump). Robust to
# _ready ordering: the manager's _pumps array is initialized at construction, so
# registering before the manager's own _ready runs is safe.
func _find_manager():
	var p := get_parent()
	if p == null:
		return null
	for sib in p.get_children():
		if sib.has_method("register_pump"):
			return sib
	return null

# Subtle team tint so player vs enemy towers read apart (matches base.gd / pumps).
func _apply_team_tint() -> void:
	var mesh := _find_mesh_instance(self)
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.45, 0.95, 0.18) if team == 0 else Color(0.9, 0.2, 0.2, 0.18)
	mesh.material_overlay = mat

# Floating health bar — the same big billboarded style as the King/houses, just
# sized down for a tower. Lives in WORLD space (parented to our parent, not us) so
# it never inherits the tower's baked ~6x scale; it parks itself above our mesh and
# reads our hp/max_hp/alive/team, ramping + pulsing exactly like a house bar.
func _add_health_bar() -> void:
	var bar = HOUSE_BAR.new()
	bar.name = "HealthBar"
	bar.bar_width = 2.8       # smaller than the King's 4.2 bar
	bar.bar_height = 0.42
	bar.margin_above = 1.6    # world units above the tower mesh top
	bar.bind(self)            # contract: bind() BEFORE the node enters the tree
	# Defer the add: during our own _ready the parent is still setting up its
	# children, so a direct get_parent().add_child() is refused. bind() already ran,
	# so the bar's _ready sees us fine once it's added next idle frame.
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
