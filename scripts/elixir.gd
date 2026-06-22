# Elixir resource node: Clash-Royale-style regenerating currency for spawning units.
extends Node

@export var max_elixir: float = 10.0
@export var start_elixir: float = 3.0
@export var regen_per_sec: float = 0.33333333  # gain 1 elixir every 3 seconds

var current: float

signal changed(current_amount: float, maximum: float)


func _ready() -> void:
	current = start_elixir
	emit_signal("changed", current, max_elixir)


func _process(delta: float) -> void:
	if current < max_elixir:
		current = min(current + regen_per_sec * delta, max_elixir)  # cap at max is the INTENDED game rule
		emit_signal("changed", current, max_elixir)


func can_afford(cost: float) -> bool:
	return current >= cost


# Add elixir (e.g. produced by an elixir pump), capped at max like passive regen.
func add(amount: float) -> void:
	current = min(current + amount, max_elixir)
	emit_signal("changed", current, max_elixir)


# Spend `cost` if affordable; returns true and deducts, else returns false.
func spend(cost: float) -> bool:
	if current >= cost:
		current -= cost
		emit_signal("changed", current, max_elixir)
		return true
	return false
