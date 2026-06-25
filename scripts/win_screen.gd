extends CanvasLayer
# Epic victory / defeat overlay, built in code. The battle manager instantiates it
# when a base falls and calls show_result(won) BEFORE add_child(). On a win it
# dims the field, pops in a "YOU WIN" banner and a celebrating hero, then a wooden
# "Continue" button that returns to the menu. On a loss it's the same choreography
# with the "YOU LOSE" banner and a dejected hero.

const MENU_SCENE  := "res://scenes/menu.tscn"
const PROFILE     := preload("res://scripts/profile.gd")
const BTN_TEX     := "res://assets/ui/button_wide.png"
const BTN_SHADER  := "res://shaders/white_key.gdshader"
const BANNER_TEX  := "res://assets/ui/you_win.png"
const HERO_TEX    := "res://assets/ui/hero_win.png"
const LOSE_BANNER_TEX := "res://assets/ui/you_lose.png"
const SAD_HERO_TEX    := "res://assets/ui/hero_lose.png"
const BTN_BROWN   := Color(0.25, 0.13, 0.05)

var _won: bool = true
var _xp_result: Dictionary = {}   # filled in show_result via Profile.add_xp
var _coins_gained: int = 0        # coins awarded this match

# Random reward ranges, rolled per match (so a gain never exactly fills a level).
const WIN_XP_MIN := 70
const WIN_XP_MAX := 130
const LOSS_XP_MIN := 20
const LOSS_XP_MAX := 45
const WIN_COIN_MIN := 35
const WIN_COIN_MAX := 75
const LOSS_COIN_MIN := 8
const LOSS_COIN_MAX := 22

# XP-panel node refs, used by the fill animation.
var _xp_box: Control
var _xp_bar: ProgressBar
var _xp_lvl_label: Label
var _xp_fill_sb: StyleBoxFlat
var _xp_levelup_label: Label

@export var result_delay: float = 2.0   # seconds the battle keeps playing after a base falls, before freezing + showing the result

# Called by the battle manager BEFORE add_child().
func show_result(won: bool) -> void:
	_won = won
	# Award + persist progression now, so the panel can show the result.
	var xp_gain: int = randi_range(WIN_XP_MIN, WIN_XP_MAX) if won else randi_range(LOSS_XP_MIN, LOSS_XP_MAX)
	_xp_result = PROFILE.add_xp(xp_gain)
	_coins_gained = randi_range(WIN_COIN_MIN, WIN_COIN_MAX) if won else randi_range(LOSS_COIN_MIN, LOSS_COIN_MAX)
	PROFILE.add_coins(_coins_gained)

func _ready() -> void:
	layer = 100
	# This overlay keeps animating + stays clickable while everything else is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Banner pops immediately (same timing as before)...
	_build()
	# ...but the battle keeps running for a beat behind it before we freeze it — feels
	# better than snapping to a frozen field the instant a base falls.
	await get_tree().create_timer(result_delay).timeout
	# Freeze everything: units, buildings, spawn ticks and the sounds they trigger all
	# stop. Un-paused again in _on_continue.
	get_tree().paused = true

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
		_build_result_art(root, HERO_TEX, BANNER_TEX)
	else:
		_build_result_art(root, SAD_HERO_TEX, LOSE_BANNER_TEX)

	_build_xp_panel(root)
	_build_button(root)

# Hero sprite + result banner with the same pop-in choreography for both outcomes;
# only the textures differ (celebrating hero + "YOU WIN" vs dejected hero + "YOU LOSE").
func _build_result_art(root: Control, hero_path: String, banner_path: String) -> void:
	# Hero — centred, pops up with an elastic settle.
	var hero := TextureRect.new()
	var ht := _load_tex(hero_path)
	if ht != null:
		hero.texture = ht
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.anchor_left = 0.5; hero.anchor_right = 0.5; hero.anchor_top = 0.5; hero.anchor_bottom = 0.5
	hero.offset_left = -260; hero.offset_right = 260
	hero.offset_top = -360; hero.offset_bottom = 160
	hero.pivot_offset = Vector2(260, 260)
	root.add_child(hero)
	hero.z_index = 1   # draw the hero in front of the banner/result text
	hero.modulate.a = 0.0
	hero.scale = Vector2(0.5, 0.5)
	var hw := create_tween()
	hw.set_parallel(true)
	hw.tween_property(hero, "modulate:a", 1.0, 0.3).set_delay(0.3)
	hw.tween_property(hero, "scale", Vector2.ONE, 0.6).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Result banner — drops in from the top with a punchy overshoot, above the hero.
	var banner := TextureRect.new()
	var bt := _load_tex(banner_path)
	if bt != null:
		banner.texture = bt
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_left = 0.5; banner.anchor_right = 0.5; banner.anchor_top = 0.0; banner.anchor_bottom = 0.0
	banner.offset_left = -300; banner.offset_right = 300
	banner.offset_top = 20; banner.offset_bottom = 620
	banner.pivot_offset = Vector2(300, 300)
	root.add_child(banner)
	banner.scale = Vector2(0.2, 0.2)
	var bw := create_tween()
	bw.tween_property(banner, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	btn.offset_top = -260; btn.offset_bottom = -120
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

# XP readout: "+N XP", a level number + filling bar, and a gold "LEVEL UP!" when a
# level was crossed. Centered between the hero and the Continue button.
func _build_xp_panel(root: Control) -> void:
	var gold := Color(0.95, 0.78, 0.32)
	var parch := Color(0.96, 0.90, 0.74)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.anchor_left = 0.5; box.anchor_right = 0.5
	box.anchor_top = 0.63; box.anchor_bottom = 0.63
	box.offset_left = -230; box.offset_right = 230
	box.offset_top = 0; box.offset_bottom = 170
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_xp_box = box

	# "LEVEL UP!" banner — hidden until the bar actually crosses a level mid-fill.
	_xp_levelup_label = Label.new()
	_xp_levelup_label.text = "LEVEL UP!"
	_xp_levelup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_levelup_label.add_theme_color_override("font_color", gold)
	_xp_levelup_label.add_theme_font_size_override("font_size", 44)
	_xp_levelup_label.visible = false
	box.add_child(_xp_levelup_label)

	var gained := Label.new()
	gained.text = "+%d XP" % int(_xp_result.get("gained", 0))
	gained.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gained.add_theme_color_override("font_color", parch)
	gained.add_theme_font_size_override("font_size", 32)
	box.add_child(gained)

	var coins_lbl := Label.new()
	coins_lbl.text = "+%d coins" % _coins_gained
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.40))
	coins_lbl.add_theme_font_size_override("font_size", 28)
	box.add_child(coins_lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var start_level: int = int(_xp_result.get("start_level", 1))
	var start_xp: int = int(_xp_result.get("start_xp", 0))

	_xp_lvl_label = Label.new()
	_xp_lvl_label.text = "Lv %d" % start_level
	_xp_lvl_label.add_theme_color_override("font_color", Color.WHITE)
	_xp_lvl_label.add_theme_font_size_override("font_size", 30)
	row.add_child(_xp_lvl_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(300, 28)
	_xp_bar.min_value = 0
	_xp_bar.max_value = max(1, PROFILE.xp_to_next(start_level))
	_xp_bar.value = start_xp   # start where the bar actually was, then roll up
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.30, 0.18, 0.09)
	track.border_color = Color(0.18, 0.10, 0.04)
	track.set_border_width_all(3)
	track.set_corner_radius_all(9)
	_xp_fill_sb = StyleBoxFlat.new()
	_xp_fill_sb.bg_color = gold
	_xp_fill_sb.set_corner_radius_all(9)
	_xp_bar.add_theme_stylebox_override("background", track)
	_xp_bar.add_theme_stylebox_override("fill", _xp_fill_sb)
	row.add_child(_xp_bar)

	# Pop the panel in after the banner lands; the fill animates as its own coroutine.
	box.modulate.a = 0.0
	var pop := create_tween()
	pop.tween_interval(0.6)
	pop.tween_property(box, "modulate:a", 1.0, 0.25)
	_animate_xp_fill()

# Roll the XP bar up from where it started, crossing level thresholds with a juicy
# flash + pop, then continuing to fill on the next level. Handles multiple levels.
func _animate_xp_fill() -> void:
	await get_tree().create_timer(0.95).timeout   # let the panel finish popping in
	if not is_instance_valid(_xp_bar):
		return
	var level: int = int(_xp_result.get("start_level", 1))
	var xp: int = int(_xp_result.get("start_xp", 0))
	var remaining: int = int(_xp_result.get("gained", 0))
	while remaining > 0 and is_instance_valid(_xp_bar):
		var need: int = PROFILE.xp_to_next(level) - xp
		var step: int = mini(remaining, need)
		var dur: float = clampf(float(step) / 130.0 * 0.6, 0.18, 0.75)
		var tw := create_tween()
		tw.tween_property(_xp_bar, "value", float(xp + step), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await tw.finished
		xp += step
		remaining -= step
		if xp >= PROFILE.xp_to_next(level):
			level += 1
			xp = 0
			await _play_levelup(level)
			if not is_instance_valid(_xp_bar):
				return
			_xp_bar.max_value = max(1, PROFILE.xp_to_next(level))
			_xp_bar.value = 0
			_xp_lvl_label.text = "Lv %d" % level

# Level-up flourish: reveal + pop "LEVEL UP!", flash the bar fill white, punch the
# whole panel, hold a beat, then fade the banner so the next level can keep filling.
func _play_levelup(_new_level: int) -> void:
	if not is_instance_valid(_xp_box) or not is_instance_valid(_xp_levelup_label):
		return
	var gold := Color(0.95, 0.78, 0.32)
	_xp_levelup_label.visible = true
	await get_tree().process_frame   # let the container lay the label out (valid size)
	if not is_instance_valid(_xp_levelup_label):
		return
	_xp_levelup_label.modulate = Color(1, 1, 1, 0)
	_xp_levelup_label.pivot_offset = _xp_levelup_label.size * 0.5
	_xp_levelup_label.scale = Vector2(0.4, 0.4)
	if _xp_fill_sb != null:
		_xp_fill_sb.bg_color = Color.WHITE
	_xp_box.pivot_offset = _xp_box.size * 0.5

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_xp_levelup_label, "modulate:a", 1.0, 0.15)
	t.tween_property(_xp_levelup_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _xp_fill_sb != null:
		t.tween_property(_xp_fill_sb, "bg_color", gold, 0.4)
	t.tween_property(_xp_box, "scale", Vector2(1.12, 1.12), 0.12)
	t.set_parallel(false)
	t.tween_property(_xp_box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished

	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(_xp_levelup_label):
		var ft := create_tween()
		ft.tween_property(_xp_levelup_label, "modulate:a", 0.0, 0.2)
		await ft.finished
		if is_instance_valid(_xp_levelup_label):
			_xp_levelup_label.visible = false

func _on_continue() -> void:
	get_tree().paused = false   # un-freeze before leaving, so the menu runs normally
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
