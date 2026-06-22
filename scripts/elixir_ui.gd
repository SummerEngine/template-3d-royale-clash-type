extends CanvasLayer
## Clash-Royale-style elixir HUD, built entirely in code (no .tscn).
## A glossy purple liquid tube that fills bottom->top, plus a purple drop
## sprite with the current whole-number elixir count on it.
##
## Contract:
##   bind(elixir_node) is called by the battle manager BEFORE add_child().
##   The elixir model exposes: var current: float, @export var max_elixir: float (=10),
##   and signal changed(current_amount, maximum).

# --- Palette ---------------------------------------------------------------
const COL_BRIGHT  := Color(0.78, 0.30, 0.92)   # bright liquid (top)
const COL_DARK    := Color(0.45, 0.12, 0.62)   # dark liquid (bottom)
const COL_GLOSS   := Color(1.0, 1.0, 1.0)      # near-white highlight
const COL_GLASS   := Color(0.10, 0.08, 0.16, 0.55)
const COL_BORDER  := Color(0.55, 0.40, 0.70, 0.9)

# --- Layout ----------------------------------------------------------------
const MARGIN      := 24.0
const TUBE_W      := 64.0
const TUBE_H      := 300.0
const DROP_SIZE   := 84.0
const SEGMENTS    := 10                          # 10 elixir = 10 segments

# --- Runtime references ----------------------------------------------------
var _elixir = null                # the elixir model (res://scripts/elixir.gd); untyped for cross-script duck typing
var _fill: Control = null         # liquid fill node; we drive its anchor_top
var _surface: ColorRect = null    # bright line riding the top of the liquid
var _number_label: Label = null   # integer count drawn on the drop
var _was_full: bool = false
const SFX := preload("res://scripts/sfx.gd")

# Optional smooth-fill state (purely visual liquid easing).
var _target_ratio: float = 0.0
var _shown_ratio: float = 0.0

# Reject feedback (can't-afford): whole-HUD shake + red flash over the glass.
var _root: Control = null
var _red_flash: ColorRect = null
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_amp: float = 0.0


# Called by the battle manager BEFORE add_child().
func bind(elixir_node: Node) -> void:
	_elixir = elixir_node


func _ready() -> void:
	_build_ui()
	if _elixir != null:
		_elixir.changed.connect(_on_elixir_changed)
		# Initial paint.
		_on_elixir_changed(_elixir.current, _elixir.max_elixir)


func _on_elixir_changed(current_amount: float, maximum: float) -> void:
	# Tube fill ratio.
	var ratio: float = 0.0
	if maximum > 0.0:
		ratio = clampf(current_amount / maximum, 0.0, 1.0)
	_target_ratio = ratio
	if current_amount >= maximum - 0.001 and not _was_full:
		_was_full = true
		SFX.play(self, "res://audio/elixir_full")
	elif current_amount < maximum - 0.5:
		_was_full = false
	_apply_ratio(ratio)   # direct set; _process eases toward it for liquid feel.

	# Number = floor(current) as an int (can't spend fractional elixir).
	if _number_label != null:
		_number_label.text = str(int(floor(current_amount)))


# Smoothly ease the displayed liquid toward the target (optional polish).
func _process(delta: float) -> void:
	_process_shake(delta)
	if _fill == null:
		return
	if absf(_shown_ratio - _target_ratio) > 0.0005:
		_shown_ratio = lerpf(_shown_ratio, _target_ratio, clampf(delta * 10.0, 0.0, 1.0))
		_set_fill_ratio(_shown_ratio)


# Called by the battle manager when the player can't afford a spawn: shake the
# whole HUD and flash the glass red.
func reject() -> void:
	_shake_amp = 16.0
	_shake_dur = 0.4
	_shake_t = 0.4
	if _red_flash != null:
		_red_flash.color = Color(1.0, 0.15, 0.15, 0.55)
		var t := create_tween()
		t.tween_property(_red_flash, "color:a", 0.0, 0.45)


# Decaying random jitter of the whole HUD root while a reject shake is active.
func _process_shake(delta: float) -> void:
	if _shake_t <= 0.0 or _root == null:
		return
	_shake_t -= delta
	if _shake_t <= 0.0:
		_root.position = Vector2.ZERO
		return
	var amp: float = _shake_amp * clampf(_shake_t / _shake_dur, 0.0, 1.0)
	_root.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))


# Direct application (used on bind / initial paint); also seeds the easer.
func _apply_ratio(ratio: float) -> void:
	_shown_ratio = ratio
	_set_fill_ratio(ratio)


# Drive the liquid height: fill is anchored to the bottom and grows up by
# moving its top anchor. anchor_top = 1.0 - ratio means full at ratio = 1.
func _set_fill_ratio(ratio: float) -> void:
	if _fill != null:
		_fill.anchor_top = 1.0 - ratio
		_fill.offset_top = 0.0
		_fill.offset_bottom = 0.0


# ===========================================================================
# UI construction
# ===========================================================================
func _build_ui() -> void:
	# Root control pinned to the whole screen; children pin to bottom-left.
	var root := Control.new()
	root.name = "ElixirRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	var tube := _build_tube(root)
	_build_drop(root, tube)


# --- The glass tube + liquid + ticks --------------------------------------
func _build_tube(root: Control) -> Panel:
	# Glass container: rounded, dark translucent, lighter border.
	var tube := Panel.new()
	tube.name = "Tube"
	tube.clip_contents = true   # clip liquid to the rounded glass shape
	tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor to the left edge, centered vertically (tube's middle at screen center).
	tube.anchor_left = 0.0
	tube.anchor_right = 0.0
	tube.anchor_top = 0.5
	tube.anchor_bottom = 0.5
	tube.offset_left = MARGIN
	tube.offset_right = MARGIN + TUBE_W
	tube.offset_top = -TUBE_H * 0.5
	tube.offset_bottom = TUBE_H * 0.5

	var glass := StyleBoxFlat.new()
	glass.bg_color = COL_GLASS
	glass.set_corner_radius_all(int(TUBE_W * 0.5))
	glass.set_border_width_all(3)
	glass.border_color = COL_BORDER
	tube.add_theme_stylebox_override("panel", glass)
	root.add_child(tube)

	# LIQUID fill: anchored to the bottom, grows upward via anchor_top.
	_fill = Control.new()
	_fill.name = "Fill"
	_fill.clip_contents = false
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.anchor_left = 0.0
	_fill.anchor_right = 1.0
	_fill.anchor_top = 1.0      # start empty; _set_fill_ratio raises this
	_fill.anchor_bottom = 1.0
	_fill.offset_left = 0.0
	_fill.offset_right = 0.0
	_fill.offset_top = 0.0
	_fill.offset_bottom = 0.0
	tube.add_child(_fill)

	# Vertical purple gradient body (bright top -> dark bottom).
	var grad := Gradient.new()
	grad.set_color(0, COL_BRIGHT)
	grad.set_color(1, COL_DARK)
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	grad_tex.width = 4
	grad_tex.height = 64

	var liquid := TextureRect.new()
	liquid.name = "Liquid"
	liquid.texture = grad_tex
	liquid.stretch_mode = TextureRect.STRETCH_SCALE
	liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	liquid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill.add_child(liquid)

	# Soft vertical gloss stripe down the left side of the liquid.
	var gloss := ColorRect.new()
	gloss.name = "Gloss"
	gloss.color = Color(COL_GLOSS.r, COL_GLOSS.g, COL_GLOSS.b, 0.18)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.anchor_left = 0.0
	gloss.anchor_right = 0.0
	gloss.anchor_top = 0.0
	gloss.anchor_bottom = 1.0
	gloss.offset_left = TUBE_W * 0.16
	gloss.offset_right = TUBE_W * 0.34
	gloss.offset_top = 0.0
	gloss.offset_bottom = 0.0
	_fill.add_child(gloss)

	# Bright "surface" line riding the very top of the liquid.
	_surface = ColorRect.new()
	_surface.name = "Surface"
	_surface.color = Color(COL_GLOSS.r, COL_GLOSS.g, COL_GLOSS.b, 0.7)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.anchor_left = 0.0
	_surface.anchor_right = 1.0
	_surface.anchor_top = 0.0
	_surface.anchor_bottom = 0.0
	_surface.offset_top = 0.0
	_surface.offset_bottom = 3.0
	_fill.add_child(_surface)

	# SEGMENT TICKS: 9 faint lines over the liquid, splitting tube into 10.
	for i in range(1, SEGMENTS):
		var tick := ColorRect.new()
		tick.name = "Tick%d" % i
		tick.color = Color(1.0, 1.0, 1.0, 0.12)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.anchor_left = 0.0
		tick.anchor_right = 1.0
		var y_ratio := float(i) / float(SEGMENTS)   # measured from the top
		tick.anchor_top = y_ratio
		tick.anchor_bottom = y_ratio
		tick.offset_left = 4.0
		tick.offset_right = -4.0
		tick.offset_top = -1.0
		tick.offset_bottom = 1.0
		tube.add_child(tick)   # drawn over the liquid (added after fill)

	# Red flash overlay for the "can't afford" reject feedback (clipped to glass).
	_red_flash = ColorRect.new()
	_red_flash.name = "RedFlash"
	_red_flash.color = Color(1.0, 0.15, 0.15, 0.0)
	_red_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tube.add_child(_red_flash)

	return tube


# --- The elixir drop sprite + number label --------------------------------
func _build_drop(root: Control, tube: Panel) -> void:
	# Container pinned just above the tube, centered on the tube's width.
	var drop_box := Control.new()
	drop_box.name = "DropBox"
	drop_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_box.anchor_left = 0.0
	drop_box.anchor_right = 0.0
	drop_box.anchor_top = 0.5
	drop_box.anchor_bottom = 0.5
	# Center the drop horizontally over the tube.
	var center_x := MARGIN + TUBE_W * 0.5
	drop_box.offset_left = center_x - DROP_SIZE * 0.5
	drop_box.offset_right = center_x + DROP_SIZE * 0.5
	# Sit overlapping the top of the (now vertically centered) tube.
	var drop_top := -TUBE_H * 0.5 - DROP_SIZE * 0.55
	drop_box.offset_top = drop_top
	drop_box.offset_bottom = drop_top + DROP_SIZE
	root.add_child(drop_box)


	# Try to load the drop sprite; fall back gracefully so it's never blank.
	var drop_tex: Texture2D = _load_drop_texture()
	if drop_tex != null:
		var sprite := TextureRect.new()
		sprite.name = "DropSprite"
		sprite.texture = drop_tex
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		drop_box.add_child(sprite)
	else:
		# Fallback: a magenta-purple circle via a fully-rounded StyleBoxFlat.
		var circle := Panel.new()
		circle.name = "DropFallback"
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var c_style := StyleBoxFlat.new()
		c_style.bg_color = COL_BRIGHT
		c_style.set_corner_radius_all(int(DROP_SIZE * 0.5))
		c_style.set_border_width_all(4)
		c_style.border_color = COL_DARK
		circle.add_theme_stylebox_override("panel", c_style)
		drop_box.add_child(circle)

	# Bold number label centered on the drop, white with dark outline.
	_number_label = Label.new()
	_number_label.name = "ElixirNumber"
	_number_label.text = "0"
	_number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_number_label.add_theme_font_size_override("font_size", 34)
	_number_label.add_theme_color_override("font_color", Color.WHITE)
	_number_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_number_label.add_theme_constant_override("outline_size", 6)
	drop_box.add_child(_number_label)


# Load the drop sprite, trying ResourceLoader first, then Image.load().
func _load_drop_texture() -> Texture2D:
	var path := "res://ui/elixir_drop.png"
	# Preferred path: imported resource.
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return res as Texture2D
	# Fallback: raw image load (works for un-imported files at runtime).
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
