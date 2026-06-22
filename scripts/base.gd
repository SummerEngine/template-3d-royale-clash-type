extends Node3D
# House base: each team owns one. Units march to the enemy house and attack it;
# the first house to drop to 0 HP is destroyed, and its team loses.

@export var team: int = 0          # 0 = player (blue), 1 = enemy (red)
@export var max_hp: float = 220.0
@export var radius: float = 2.772  # soft-collision radius; the battle manager and units read this (3.6 -30% then +10%)

var hp: float
var alive: bool = true

signal destroyed(team)

const HITFX := preload("res://scripts/hit_fx.gd")
const SFX := preload("res://scripts/sfx.gd")

func _ready() -> void:
	hp = max_hp
	_apply_team_tint()

# Tint the house by team at runtime (blue = player, red = enemy). Done in code
# because instanced-child material overrides in the .tscn don't survive saves.
func _apply_team_tint() -> void:
	var mesh := _find_mesh_instance(self)
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.45, 0.95, 0.18) if team == 0 else Color(0.9, 0.2, 0.2, 0.18)
	mesh.material_overlay = mat

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null

# Apply damage. Raw subtraction, no clamping — the designer balances deliberately.
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	HITFX.play(self, _find_mesh_instance(self), scale, false)
	SFX.play(self, "res://audio/house_hit")
	if hp <= 0.0:
		alive = false
		emit_signal("destroyed", team)
		print("[base] team %d destroyed" % team)
		visible = false
		SFX.play(self, "res://audio/house_destroyed", 2.0)   # Node3D: hides this node and its whole subtree
