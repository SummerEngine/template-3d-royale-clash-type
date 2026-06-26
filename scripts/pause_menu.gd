extends CanvasLayer
# In-match pause. Shows a small wooden pause button in the top-left corner; tapping
# it freezes the battle (get_tree().paused) and pops a "PAUSED" parchment card with
# Continue / Menu. Instantiated by the battle manager. Runs in PROCESS_MODE_ALWAYS
# so the button works during play AND the card's buttons work while the tree is
# paused. Styled to match the wooden menu (button_wide.png + white-key shader).

const MENU_SCENE := "res://scenes/menu.tscn"
const BTN_TEX    := "res://assets/ui/button_wide.png"
const BTN_SHADER := "res://shaders/white_key.gdshader"
const BTN_BROWN  := Color(0.25, 0.13, 0.05)
const PARCH      := Color(0.91, 0.82, 0.63)
const WOOD       := Color(0.28, 0.16, 0.07)

var _overlay: Control = null   # dim + card, hidden until paused
var _card: Panel = null

func _ready() -> void:
	layer = 90   # above the gameplay HUD, below the win screen (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_button()
	_build_overlay()

# --- Corner pause button ---
func _build_pause_button() -> void:
	var btn := TextureButton.new()
	var tex := _load_tex(BTN_TEX)
	if tex != null:
		btn.texture_normal = tex
		btn.texture_pressed = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	_chroma(btn)
	btn.anchor_left = 0.0; btn.anchor_right = 0.0
	btn.anchor_top = 0.0; btn.anchor_bottom = 0.0
	btn.offset_left = 36.0; btn.offset_right = 36.0 + 96.0
	btn.offset_top = 66.0; btn.offset_bottom = 66.0 + 96.0
	btn.pressed.connect(_open)
	add_child(btn)
	# Pause glyph (two brown bars) centered on the wooden button.
	var icon := TextureRect.new()
	icon.texture = _make_pause_icon(48, 48, BTN_BROWN)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centered + inset so the glyph sits on the wood instead of filling the button.
	icon.anchor_left = 0.5; icon.anchor_right = 0.5
	icon.anchor_top = 0.5; icon.anchor_bottom = 0.5
	icon.offset_left = -30.0; icon.offset_right = 30.0
	icon.offset_top = -30.0; icon.offset_bottom = 30.0
	btn.add_child(icon)

# --- "PAUSED" overlay ---
func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	# Dim backdrop that also blocks clicks to the frozen field behind.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	# Parchment card with a wood border + soft shadow (matches the options panel).
	_card = Panel.new()
	_card.anchor_left = 0.5; _card.anchor_right = 0.5
	_card.anchor_top = 0.5; _card.anchor_bottom = 0.5
	_card.offset_left = -230.0; _card.offset_right = 230.0
	_card.offset_top = -220.0; _card.offset_bottom = 220.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCH
	sb.border_color = WOOD
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 8)
	_card.add_theme_stylebox_override("panel", sb)
	_overlay.add_child(_card)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", BTN_BROWN)
	title.add_theme_font_size_override("font_size", 56)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.offset_top = 36.0; title.offset_bottom = 120.0
	_card.add_child(title)

	_wood_button(_card, "Continue", -40.0, _resume)
	_wood_button(_card, "Menu", 74.0, _to_menu)

# A centered wooden button at vertical offset `y` from the card centre.
func _wood_button(parent: Control, text: String, y: float, cb: Callable) -> void:
	var btn := TextureButton.new()
	var tex := _load_tex(BTN_TEX)
	if tex != null:
		btn.texture_normal = tex
		btn.texture_pressed = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	_chroma(btn)
	btn.anchor_left = 0.5; btn.anchor_right = 0.5
	btn.anchor_top = 0.5; btn.anchor_bottom = 0.5
	btn.offset_left = -150.0; btn.offset_right = 150.0
	btn.offset_top = y; btn.offset_bottom = y + 92.0
	btn.pressed.connect(cb)
	parent.add_child(btn)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_color_override("font_color", BTN_BROWN)
	lbl.add_theme_font_size_override("font_size", 38)
	btn.add_child(lbl)

func _open() -> void:
	if _overlay.visible:
		return
	get_tree().paused = true
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.14)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _resume() -> void:
	get_tree().paused = false
	_overlay.visible = false

func _to_menu() -> void:
	get_tree().paused = false   # un-freeze before leaving so the menu runs normally
	get_tree().change_scene_to_file(MENU_SCENE)

# --- Helpers ---
# Chroma-key the button png's white backdrop, exactly like the menu/win buttons.
func _chroma(btn: TextureButton) -> void:
	var shader = load(BTN_SHADER)
	if shader is Shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("white_cut", 0.86)
		mat.set_shader_parameter("sat_max", 0.1)
		mat.set_shader_parameter("softness", 0.04)
		btn.material = mat

# Two solid vertical bars on transparent = a pause glyph.
func _make_pause_icon(w: int, h: int, col: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bw := int(w * 0.26)
	var gap := int(w * 0.20)
	var x0 := int((w - (bw * 2 + gap)) / 2.0)
	var y0 := int(h * 0.18)
	var y1 := int(h * 0.82)
	for y in range(y0, y1):
		for x in range(x0, x0 + bw):
			img.set_pixel(x, y, col)
		for x in range(x0 + bw + gap, x0 + bw + gap + bw):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

# Load a texture, falling back to a raw image read so it works before Godot has
# imported the PNG.
func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
