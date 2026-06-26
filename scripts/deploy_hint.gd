extends CanvasLayer
# Opening tutorial nudge. If the player hasn't deployed anything `delay` seconds into
# the match (by which they've banked plenty of elixir), fade in a gently pulsing
# "Drag units to the battlefield!". The battle manager calls dismiss() — via the
# "deploy_hint" group — the instant the player places their first unit, fading it out.

@export var delay: float = 5.0

var _label: Label = null
var _dismissed: bool = false

func _ready() -> void:
	layer = 50   # over the 3D field, under the pause / win overlays
	add_to_group("deploy_hint")
	_build()
	await get_tree().create_timer(delay).timeout
	if not _dismissed and is_instance_valid(_label):
		_reveal()

func _build() -> void:
	_label = Label.new()
	_label.text = "Drag units to the battlefield!"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	_label.add_theme_constant_override("outline_size", 8)
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.5
	_label.anchor_bottom = 0.5
	_label.offset_top = 40.0
	_label.offset_bottom = 130.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)

# Fade in + a slow scale pulse to draw the eye.
func _reveal() -> void:
	_label.pivot_offset = _label.size * 0.5
	create_tween().tween_property(_label, "modulate:a", 1.0, 0.4)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_label, "scale", Vector2(1.06, 1.06), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_label, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Player placed their first unit — fade out and free (called via the group).
func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	if not is_instance_valid(_label):
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
