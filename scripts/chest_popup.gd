extends Control
## Free-gold chest popup (built in code, no scene file). Opened from the menu's chest
## button. Shows a large 3D-look chest; tap it to open — rattle, lid-up swap, gold
## flash, coin burst, a "FREE GOLD!" sprite slam, and a random gold reward. After the
## open animation finishes you can tap again to close. Add as a full-screen overlay.

const PROFILE := preload("res://scripts/profile.gd")
const SFX := preload("res://scripts/sfx.gd")
const WHITE_KEY := preload("res://shaders/white_key.gdshader")

const CHEST_CLOSED := "res://assets/ui/chest_closed.png"
const CHEST_OPEN := "res://assets/ui/chest_open.png"
const FREE_GOLD := "res://assets/ui/free_gold.png"

const CHEST_SIZE := 380.0
const GOLD_MIN := 50
const GOLD_MAX := 300

# Called after gold is awarded so the menu can refresh its coin badge.
var on_gold_changed: Callable = Callable()

var _state: int = 0          # 0 closed, 1 opening (locked), 2 open (tap closes)
var _backdrop: ColorRect
var _chest: TextureRect
var _hint: Label
var _coin_tex: Texture2D
var _center: Vector2

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # this Control catches every tap (see _gui_input)
	var vp := get_viewport_rect().size
	_center = Vector2(vp.x * 0.5, vp.y * 0.5 + 30.0)
	_coin_tex = _make_coin(48)

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	create_tween().tween_property(_backdrop, "color", Color(0, 0, 0, 0.6), 0.2)

	_chest = TextureRect.new()
	_chest.texture = _load_tex(CHEST_CLOSED)
	_chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chest.material = _white_key_material()
	_chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest.size = Vector2(CHEST_SIZE, CHEST_SIZE)
	_chest.position = _center - Vector2(CHEST_SIZE, CHEST_SIZE) * 0.5
	_chest.pivot_offset = Vector2(CHEST_SIZE, CHEST_SIZE) * 0.5
	add_child(_chest)

	_hint = Label.new()
	_hint.text = "Tap the chest!"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 34)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7))
	_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.anchor_left = 0.0; _hint.anchor_right = 1.0
	_hint.offset_top = _center.y + CHEST_SIZE * 0.5 + 20.0
	_hint.offset_bottom = _hint.offset_top + 50.0
	add_child(_hint)

	# Pop the chest + a gentle idle bob to invite the tap.
	_chest.scale = Vector2(0.6, 0.6)
	_chest.modulate.a = 0.0
	var intro := create_tween()
	intro.set_parallel(true)
	intro.tween_property(_chest, "modulate:a", 1.0, 0.2)
	intro.tween_property(_chest, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_hint()

func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not tapped:
		return
	if _state == 0:
		_open()
	elif _state == 2:
		_close()

# Keep nudging the hint so it reads as "tap me".
func _pulse_hint() -> void:
	if not is_instance_valid(_hint):
		return
	var t := create_tween().set_loops()
	t.tween_property(_hint, "modulate:a", 0.4, 0.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(_hint, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

func _open() -> void:
	_state = 1
	_hint.visible = false
	SFX.play(self, "res://audio/ui_button", -6.0, 0.0)

	# 1) Anticipation: a quick rattle.
	var r := create_tween()
	for a in [0.13, -0.13, 0.10, -0.10, 0.05, 0.0]:
		r.tween_property(_chest, "rotation", a, 0.05)
	await r.finished
	if not is_instance_valid(_chest):
		return

	# 2) Burst open: swap to the open chest, big pop, flash, coins, reward, banner.
	_chest.texture = _load_tex(CHEST_OPEN)
	SFX.play(self, "res://audio/elixir_full", 0.0, 0.0)
	SFX.play(self, "res://audio/victory", -4.0, 0.0)
	var pop := create_tween()
	pop.tween_property(_chest, "scale", Vector2(1.28, 1.28), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_chest, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash()
	_coin_burst(22)

	var amount := randi_range(GOLD_MIN, GOLD_MAX)
	PROFILE.add_coins(amount)
	if on_gold_changed.is_valid():
		on_gold_changed.call()
	_show_free_gold(amount)

	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(self):
		return
	_state = 2
	_hint.text = "Tap to close"
	_hint.visible = true

func _close() -> void:
	_state = 1   # block further taps
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.18)
	t.set_parallel(false)
	t.tween_callback(queue_free)

# A bright golden glow that blooms out from the chest and fades.
func _flash() -> void:
	var glow := TextureRect.new()
	glow.texture = _coin_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.modulate = Color(1.0, 0.85, 0.4, 0.9)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	var s0 := 120.0
	glow.size = Vector2(s0, s0)
	glow.pivot_offset = Vector2(s0, s0) * 0.5
	glow.position = _center - Vector2(s0, s0) * 0.5
	add_child(glow)
	move_child(glow, _chest.get_index())   # behind the chest
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(glow, "scale", Vector2(6, 6), 0.45).set_ease(Tween.EASE_OUT)
	t.tween_property(glow, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(glow.queue_free)

# A fountain of spinning gold coins erupting from the chest.
func _coin_burst(n: int) -> void:
	var vp := get_viewport_rect().size
	for i in n:
		var coin := TextureRect.new()
		coin.texture = _coin_tex
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz := randf_range(34.0, 56.0)
		coin.size = Vector2(sz, sz)
		coin.pivot_offset = Vector2(sz, sz) * 0.5
		coin.position = _center - Vector2(sz, sz) * 0.5 + Vector2(randf_range(-40, 40), -CHEST_SIZE * 0.18)
		add_child(coin)
		# Up-and-out arc, then fall off the bottom.
		var ang := randf_range(-2.5, -0.65)   # mostly upward
		var dist := randf_range(140.0, 360.0)
		var apex := coin.position + Vector2(cos(ang), sin(ang)) * dist
		var land := Vector2(apex.x + randf_range(-40, 40), vp.y + 80.0)
		var t := create_tween()
		t.tween_property(coin, "position", apex, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(coin, "position", land, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(coin.queue_free)
		var spin := coin.create_tween().set_loops()
		spin.tween_property(coin, "rotation", TAU, randf_range(0.4, 0.8))

# "FREE GOLD!" sprite slams in from above with a bounce, plus a "+N" gold tally.
func _show_free_gold(amount: int) -> void:
	var banner := TextureRect.new()
	banner.texture = _load_tex(FREE_GOLD)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.material = _white_key_material()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := 460.0
	var bh := 230.0
	banner.size = Vector2(bw, bh)
	banner.pivot_offset = Vector2(bw, bh) * 0.5
	var rest_y := _center.y - CHEST_SIZE * 0.5 - bh + 10.0
	banner.position = Vector2(_center.x - bw * 0.5, rest_y - 220.0)
	banner.scale = Vector2(0.5, 0.5)
	banner.modulate.a = 0.0
	add_child(banner)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(banner, "modulate:a", 1.0, 0.18)
	t.tween_property(banner, "position:y", rest_y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# "+N" gold tally that counts up under the banner.
	var tally := Label.new()
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tally.add_theme_font_size_override("font_size", 52)
	tally.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32))
	tally.add_theme_color_override("font_outline_color", Color(0.18, 0.10, 0.02))
	tally.add_theme_constant_override("outline_size", 8)
	tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tally.anchor_left = 0.0; tally.anchor_right = 1.0
	tally.offset_top = rest_y + bh - 30.0
	tally.offset_bottom = tally.offset_top + 64.0
	tally.text = "+0"
	add_child(tally)
	var tally_cb := func(val: float) -> void:
		if is_instance_valid(tally):
			tally.text = "+%d" % int(round(val))
	create_tween().tween_method(tally_cb, 0.0, float(amount), 0.6).set_delay(0.25)

func _white_key_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WHITE_KEY
	m.set_shader_parameter("white_cut", 0.86)
	m.set_shader_parameter("sat_max", 0.12)
	m.set_shader_parameter("softness", 0.05)
	return m

# A round gold coin texture (disc + darker rim + a soft highlight), drawn in code.
func _make_coin(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (d - 1) * 0.5
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) - c, float(y) - c).length()
			var a := clampf(r - dist + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col: Color
			if (r - dist) < 2.5:
				col = Color(0.62, 0.42, 0.10)            # dark rim
			elif dist < r * 0.45:
				col = Color(1.0, 0.93, 0.55)             # bright center
			else:
				col = Color(0.95, 0.74, 0.22)            # gold body
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
