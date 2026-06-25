extends CanvasLayer
## Battle countdown clock, pinned top-right (opposite the pause button). Counts down from start_seconds
## (2:00) and stops at 0:00. Built entirely in code; the battle manager spawns one.
## Pauses with the game automatically (default process_mode follows the SceneTree
## pause), so it doesn't tick while the pause menu is up.

@export var start_seconds: float = 120.0   # 2 minutes
@export var warn_seconds: float = 10.0      # turn red + pulse under this

signal finished   # emitted once the moment it reaches 0:00

var _remaining: float = 0.0
var _label: Label = null
var _panel: Panel = null
var _running: bool = false
var _t: float = 0.0

func _ready() -> void:
	_remaining = start_seconds
	_build()
	_update_label()
	_running = true

func _build() -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top-right, mirroring the pause button (top-left, margin 22 / top 52).
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -202.0
	panel.offset_right = -22.0
	panel.offset_top = 55.0
	panel.offset_bottom = 123.0
	panel.pivot_offset = Vector2(90.0, 34.0)   # centre (180x68), for the warn pulse
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.03, 0.62)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.87, 0.64, 0.23, 0.9)   # gold frame, matches the UI
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 44)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	_label.add_theme_constant_override("outline_size", 8)
	panel.add_child(_label)
	_panel = panel

func _process(delta: float) -> void:
	if not _running:
		return
	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining <= 0.0:
		_running = false
		finished.emit()
	_update_label()
	# Final-stretch warning: redden the text and pulse the panel each second.
	if _remaining > 0.0 and _remaining <= warn_seconds:
		_t += delta
		_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		if _panel != null:
			var s := 1.0 + 0.08 * sin(_t * TAU)
			_panel.scale = Vector2(s, s)

func _update_label() -> void:
	if _label == null:
		return
	var t := int(ceil(_remaining))
	_label.text = "%d:%02d" % [t / 60, t % 60]
