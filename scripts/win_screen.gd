extends CanvasLayer
# Epic victory / defeat overlay, built in code. The battle manager instantiates it
# when a base falls and calls show_result(won) BEFORE add_child(). On a win it
# dims the field, pops in a "YOU WIN" banner and a celebrating hero, then a wooden
# "Continue" button that returns to the menu. On a loss it shows a "DEFEAT" title
# with the same button.

const MENU_SCENE  := "res://scenes/menu.tscn"
const BTN_TEX     := "res://assets/ui/button_wide.png"
const BTN_SHADER  := "res://shaders/white_key.gdshader"
const BANNER_TEX  := "res://assets/ui/you_win.png"
const HERO_TEX    := "res://assets/ui/hero_win.png"
const BTN_BROWN   := Color(0.25, 0.13, 0.05)

var _won: bool = true

# Called by the battle manager BEFORE add_child().
func show_result(won: bool) -> void:
	_won = won

func _ready() -> void:
	layer = 100
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# --- Dim backdrop (fades in), also eats clicks to the field behind. ---
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	create_tween().tween_property(dim, "color", Color(0, 0, 0, 0.6), 0.4)

	if _won:
		_build_win(root)
	else:
		_build_defeat(root)

	_build_button(root)

func _build_win(root: Control) -> void:
	# Celebrating hero — centred, pops up with an elastic settle.
	var hero := TextureRect.new()
	var ht := _load_tex(HERO_TEX)
	if ht != null:
		hero.texture = ht
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.anchor_left = 0.5; hero.anchor_right = 0.5; hero.anchor_top = 0.5; hero.anchor_bottom = 0.5
	hero.offset_left = -260; hero.offset_right = 260
	hero.offset_top = -200; hero.offset_bottom = 320
	hero.pivot_offset = Vector2(260, 260)
	root.add_child(hero)
	hero.modulate.a = 0.0
	hero.scale = Vector2(0.5, 0.5)
	var hw := create_tween()
	hw.set_parallel(true)
	hw.tween_property(hero, "modulate:a", 1.0, 0.3).set_delay(0.3)
	hw.tween_property(hero, "scale", Vector2.ONE, 0.6).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# "YOU WIN" banner — drops in from the top with a punchy overshoot, above the hero.
	var banner := TextureRect.new()
	var bt := _load_tex(BANNER_TEX)
	if bt != null:
		banner.texture = bt
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_left = 0.5; banner.anchor_right = 0.5; banner.anchor_top = 0.0; banner.anchor_bottom = 0.0
	banner.offset_left = -300; banner.offset_right = 300
	banner.offset_top = 70; banner.offset_bottom = 670
	banner.pivot_offset = Vector2(300, 300)
	root.add_child(banner)
	banner.scale = Vector2(0.2, 0.2)
	var bw := create_tween()
	bw.tween_property(banner, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _build_defeat(root: Control) -> void:
	var lbl := Label.new()
	lbl.text = "DEFEAT"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 120)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0))
	lbl.add_theme_constant_override("outline_size", 10)
	root.add_child(lbl)
	lbl.scale = Vector2(0.3, 0.3)
	lbl.pivot_offset = Vector2(360, 640)
	create_tween().tween_property(lbl, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Wooden "Continue" button (menu recipe), slides up at the bottom. ---
func _build_button(root: Control) -> void:
	var btn := TextureButton.new()
	var tex := _load_tex(BTN_TEX)
	if tex != null:
		btn.texture_normal = tex
		btn.texture_pressed = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	# Chroma-key the button png's white backdrop, exactly like the menu buttons.
	var shader = load(BTN_SHADER)
	if shader is Shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("white_cut", 0.86)
		mat.set_shader_parameter("sat_max", 0.1)
		mat.set_shader_parameter("softness", 0.04)
		btn.material = mat
	btn.anchor_left = 0.5; btn.anchor_right = 0.5; btn.anchor_top = 1.0; btn.anchor_bottom = 1.0
	btn.offset_left = -190; btn.offset_right = 190
	btn.offset_top = -210; btn.offset_bottom = -70
	btn.pressed.connect(_on_continue)
	root.add_child(btn)

	var label := Label.new()
	label.text = "Continue"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", BTN_BROWN)
	label.add_theme_font_size_override("font_size", 44)
	btn.add_child(label)

	# Fade + slide up into place after the banner/hero land.
	btn.modulate.a = 0.0
	var start_off := btn.offset_top
	btn.offset_top = start_off + 80
	btn.offset_bottom += 80
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(btn, "modulate:a", 1.0, 0.3).set_delay(0.7)
	t.tween_property(btn, "offset_top", start_off, 0.4).set_delay(0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(btn, "offset_bottom", start_off + 140.0, 0.4).set_delay(0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_continue() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

# Load a texture, preferring the imported resource but falling back to a raw image
# load so it still works before Godot has imported the freshly-written png.
func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
