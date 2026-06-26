extends Control
## Unit inspect popup for the Army screen. Built in code (no scene file): a dimmed
## backdrop + a centered parchment card showing the unit's portrait, name, elixir
## cost, stat rows and flavor text. Tapping the backdrop or the Close button shuts
## it. Instantiate, call setup(def) with a card_catalog def, then add_child().

const CARD_W := 600.0
const CARD_H := 1000.0   # tall enough for a 3-line flavor blurb without clipping
const CARD_VSHIFT := -28.0   # raise the whole card slightly

# Wooden / parchment palette (matches the menu + options skin).
const WOOD_DARK := Color(0.28, 0.16, 0.07)
const BROWN := Color(0.25, 0.13, 0.05)
const PARCH := Color(0.91, 0.82, 0.63)
const GOLD := Color(0.87, 0.64, 0.23)

const CATALOG := preload("res://scripts/card_catalog.gd")

var _def: Dictionary = {}
var _card: Panel
var _backdrop: ColorRect
var _click: AudioStreamPlayer = null
var _chime: AudioStreamPlayer = null     # triumphant unlock-purchase sound
var _denied: AudioStreamPlayer = null    # can't-afford buzz (reuses the in-match one)
var _unlock_btn: Button = null           # only built for locked cards
var _upgrade_btn: Button = null          # only built for unlocked cards
var _level_lbl: Label = null             # "Level N (+X%)" line, unlocked cards only
var _scalable_rows: Array = []           # {node:Label, base:String} stat rows that scale with level
var on_unlocked: Callable = Callable()   # loadout refresh, called after a buy/upgrade

func setup(def: Dictionary) -> void:
	_def = def

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# One-shot UI click (SFX bus) for the close action.
	var click_path := "res://assets/audio/ui_click.mp3"
	if ResourceLoader.exists(click_path):
		_click = AudioStreamPlayer.new()
		_click.stream = load(click_path)
		_click.bus = "SFX"
		add_child(_click)
	# Triumphant chime for a successful unlock purchase.
	var chime_path := "res://audio/unlock.wav"
	if ResourceLoader.exists(chime_path):
		_chime = AudioStreamPlayer.new()
		_chime.stream = load(chime_path)
		_chime.bus = "SFX"
		add_child(_chime)
	# Can't-afford buzz — reuse the in-match deploy-denied sound.
	var denied_path := "res://audio/spawn_denied.wav"
	if ResourceLoader.exists(denied_path):
		_denied = AudioStreamPlayer.new()
		_denied.stream = load(denied_path)
		_denied.bus = "SFX"
		_denied.volume_db = -2.0
		add_child(_denied)

	# Dim backdrop — eats clicks to the screen behind; tap it to close.
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	_backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_close())
	create_tween().tween_property(_backdrop, "color", Color(0, 0, 0, 0.55), 0.18)

	_build_card()

func _build_card() -> void:
	_card = Panel.new()
	_card.anchor_left = 0.5; _card.anchor_right = 0.5
	_card.anchor_top = 0.5; _card.anchor_bottom = 0.5
	_card.offset_left = -CARD_W * 0.5; _card.offset_right = CARD_W * 0.5
	_card.offset_top = -CARD_H * 0.5 + CARD_VSHIFT; _card.offset_bottom = CARD_H * 0.5 + CARD_VSHIFT
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCH
	sb.border_color = WOOD_DARK
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(28)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 10)
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 34)
	_card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# Portrait on a darker inset plate so it pops off the parchment.
	var plate := Panel.new()
	plate.custom_minimum_size = Vector2(0, 320)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.16, 0.12, 0.08)
	ps.border_color = WOOD_DARK
	ps.set_border_width_all(4)
	ps.set_corner_radius_all(18)
	plate.add_theme_stylebox_override("panel", ps)
	col.add_child(plate)
	var img := TextureRect.new()
	img.texture = _load_tex(str(_def.get("texture", "")))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(img)

	# Name.
	var name_lbl := Label.new()
	name_lbl.text = str(_def.get("name", "Unit"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", BROWN)
	name_lbl.add_theme_font_size_override("font_size", 48)
	col.add_child(name_lbl)

	# Elixir cost line (gold, centered).
	var cost_lbl := Label.new()
	cost_lbl.text = "Elixir cost: %d" % int(_def.get("cost", 0))
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.62, 0.36, 0.66))
	cost_lbl.add_theme_font_size_override("font_size", 26)
	col.add_child(cost_lbl)

	# Level line (gold) for already-unlocked cards — shows level + current stat bonus.
	var cid := str(_def.get("id", ""))
	if not CATALOG.is_locked(cid):
		_level_lbl = Label.new()
		_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_level_lbl.add_theme_color_override("font_color", GOLD)
		_level_lbl.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.02))
		_level_lbl.add_theme_constant_override("outline_size", 3)
		_level_lbl.add_theme_font_size_override("font_size", 26)
		col.add_child(_level_lbl)
		_refresh_level_label(cid)

	col.add_child(_rule())

	# Stat rows: "Label .... value", left/right justified across the card width. Rows
	# whose label is in this card's "level_stats" scale with its level (and turn gold
	# when boosted); they're recorded so an upgrade can re-render them live.
	var stats: Array = _def.get("stats", [])
	var level_stats: Array = _def.get("level_stats", [])
	var lvl_mult := CATALOG.level_multiplier(cid)
	for pair in stats:
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = str(pair[0])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
		l.add_theme_font_size_override("font_size", 28)
		row.add_child(l)
		var scales: bool = level_stats.has(str(pair[0]))
		var base_val := str(pair[1])
		var v := Label.new()
		v.text = _scale_stat_text(base_val, lvl_mult) if scales else base_val
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_theme_color_override("font_color", BROWN)
		v.add_theme_font_size_override("font_size", 28)
		row.add_child(v)
		col.add_child(row)
		if scales:
			_scalable_rows.append({ "node": v, "base": base_val })

	col.add_child(_rule())

	# Flavor text — wrapped, softer brown.
	var flavor := Label.new()
	flavor.text = str(_def.get("flavor", ""))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.add_theme_color_override("font_color", Color(0.36, 0.26, 0.16))
	flavor.add_theme_font_size_override("font_size", 23)
	flavor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(flavor)

	# Locked card: a prominent gold Unlock button (with its price), and NO Close button
	# — you dismiss it by tapping outside the card. Unlocked cards get a Close button.
	var card_id := str(_def.get("id", ""))
	if CATALOG.is_locked(card_id):
		_unlock_btn = Button.new()
		_unlock_btn.text = "Unlock: %d gold" % CATALOG.unlock_cost(card_id)
		_unlock_btn.custom_minimum_size = Vector2(0, 84)
		_unlock_btn.add_theme_font_size_override("font_size", 32)
		_unlock_btn.add_theme_color_override("font_color", BROWN)
		_unlock_btn.add_theme_color_override("font_color_hover", Color(0.18, 0.09, 0.03))
		_unlock_btn.add_theme_color_override("font_color_disabled", Color(0.35, 0.3, 0.2))
		_unlock_btn.add_theme_stylebox_override("normal", _btn_style(GOLD))
		_unlock_btn.add_theme_stylebox_override("hover", _btn_style(Color(0.96, 0.76, 0.36)))
		_unlock_btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.74, 0.54, 0.18)))
		_unlock_btn.pressed.connect(_on_unlock)
		col.add_child(_unlock_btn)
	else:
		# Unlocked card: a gold UPGRADE button (spends gold to raise its level). No Close
		# button — tapping anywhere outside the card dismisses it (the backdrop).
		_upgrade_btn = Button.new()
		_upgrade_btn.custom_minimum_size = Vector2(0, 84)
		_upgrade_btn.add_theme_font_size_override("font_size", 30)
		_upgrade_btn.add_theme_color_override("font_color", BROWN)
		_upgrade_btn.add_theme_color_override("font_color_hover", Color(0.18, 0.09, 0.03))
		_upgrade_btn.add_theme_stylebox_override("normal", _btn_style(GOLD))
		_upgrade_btn.add_theme_stylebox_override("hover", _btn_style(Color(0.96, 0.76, 0.36)))
		_upgrade_btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.74, 0.54, 0.18)))
		_upgrade_btn.pressed.connect(_on_upgrade)
		col.add_child(_upgrade_btn)
		_refresh_upgrade_label(card_id)

	# Pop in from slightly small + transparent.
	_card.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
	_card.scale = Vector2(0.85, 0.85)
	_card.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_card, "modulate:a", 1.0, 0.18)
	t.tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Buy this card. Success: chime + big "UNLOCKED!" pop, the button becomes OWNED, and
# the loadout refreshes (the card turns draggable). Fail: a low blip + a brief
# "NOT ENOUGH GOLD" on the button.
func _on_unlock() -> void:
	var card_id := str(_def.get("id", ""))
	if CATALOG.try_unlock(card_id):
		if _chime != null and _chime.stream != null:
			_chime.play()
		if _unlock_btn != null:
			_unlock_btn.text = "OWNED"
			_unlock_btn.disabled = true
		_show_banner("UNLOCKED!", GOLD)
		if on_unlocked.is_valid():
			on_unlocked.call()
	else:
		if _denied != null and _denied.stream != null:
			_denied.play()
		elif _click != null and _click.stream != null:
			_click.pitch_scale = 0.7
			_click.play()
		_show_cant_afford()


# Spend gold to raise this card's level. Success: chime + "LEVEL N!" banner, the
# button + level line update, and the army gold badge refreshes. Fail: denied buzz +
# "Not enough gold!" popup.
func _on_upgrade() -> void:
	var card_id := str(_def.get("id", ""))
	var new_lvl := CATALOG.try_upgrade(card_id)
	if new_lvl > 0:
		if _chime != null and _chime.stream != null:
			_chime.play()
		_show_banner("LEVEL %d!" % new_lvl, GOLD)
		_refresh_level_label(card_id)
		_refresh_upgrade_label(card_id)
		_refresh_stats(card_id)
		if on_unlocked.is_valid():
			on_unlocked.call()   # refresh the army gold badge
	else:
		if _denied != null and _denied.stream != null:
			_denied.play()
		_show_cant_afford()


func _refresh_level_label(id: String) -> void:
	if _level_lbl == null:
		return
	var lvl := CATALOG.get_level(id)
	var bonus := int(round((CATALOG.level_multiplier(id) - 1.0) * 100.0))
	if bonus > 0:
		var labels: Array = _def.get("level_stats", [])
		var what := ", ".join(PackedStringArray(labels)) if not labels.is_empty() else "stats"
		_level_lbl.text = "Level %d   (+%d%% %s)" % [lvl, bonus, what]
	else:
		_level_lbl.text = "Level %d" % lvl


func _refresh_upgrade_label(id: String) -> void:
	if _upgrade_btn == null:
		return
	_upgrade_btn.text = "Upgrade to Lvl %d  (%d gold)" % [CATALOG.get_level(id) + 1, CATALOG.upgrade_cost(id)]


# Scale the leading number in a stat value, preserving any suffix (" (AoE)", " / shot").
func _scale_stat_text(val: String, mult: float) -> String:
	if mult <= 1.0001:
		return val
	var i := 0
	while i < val.length() and ((val[i] >= "0" and val[i] <= "9") or val[i] == "."):
		i += 1
	if i == 0:
		return val
	var num := float(val.substr(0, i)) * mult
	return ("%d" % int(round(num))) + val.substr(i)   # always a whole number


# Re-render the scalable stat rows (and recolor them gold) after an upgrade.
func _refresh_stats(id: String) -> void:
	var mult := CATALOG.level_multiplier(id)
	for r in _scalable_rows:
		var v: Label = r["node"]
		if is_instance_valid(v):
			v.text = _scale_stat_text(str(r["base"]), mult)


# Big banner text that pops in over the card, holds, then fades and frees.
func _show_banner(text: String, col: Color) -> void:
	var banner := Label.new()
	banner.text = text
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 78)
	banner.add_theme_color_override("font_color", col)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 9)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	# Scale from the screen centre so the text grows out of the middle.
	banner.pivot_offset = get_viewport_rect().size * 0.5
	banner.scale = Vector2(0.3, 0.3)
	banner.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(banner, "modulate:a", 1.0, 0.12)
	t.tween_property(banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(0.8)
	t.tween_property(banner, "modulate:a", 0.0, 0.4)
	t.tween_callback(banner.queue_free)


# Floating red "Not enough gold!" popup over the card — pops in, holds, fades, frees.
# Leaves the unlock button untouched.
func _show_cant_afford() -> void:
	var lbl := Label.new()
	lbl.text = "Not enough gold!"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 52)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.32, 0.26))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	lbl.pivot_offset = get_viewport_rect().size * 0.5
	lbl.scale = Vector2(0.5, 0.5)
	lbl.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "modulate:a", 1.0, 0.1)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(0.7)
	t.tween_property(lbl, "modulate:a", 0.0, 0.35)
	t.tween_callback(lbl.queue_free)


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(WOOD_DARK.r, WOOD_DARK.g, WOOD_DARK.b, 0.5)
	r.custom_minimum_size = Vector2(0, 3)
	return r

func _btn_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = GOLD
	s.set_border_width_all(3)
	s.set_corner_radius_all(14)
	s.set_content_margin_all(8)
	return s

func _close() -> void:
	if _click != null and _click.stream != null:
		_click.pitch_scale = 0.9   # soft "back" blip, matches the loadout's back sound
		_click.play()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _backdrop != null:
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.set_parallel(true)
	if _card != null:
		t.tween_property(_card, "modulate:a", 0.0, 0.15)
		t.tween_property(_card, "scale", Vector2(0.9, 0.9), 0.15)
	if _backdrop != null:
		t.tween_property(_backdrop, "color", Color(0, 0, 0, 0), 0.15)
	t.set_parallel(false)
	t.tween_callback(queue_free)

# Load a texture, falling back to a raw image read so it works before Godot has
# imported the PNG (same pattern used across the project's UI scripts).
func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
