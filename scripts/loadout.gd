extends Control
## "Your Army" loadout screen — a full-screen overlay over the main menu (built in
## code, added/removed by menu.gd; no scene file). Drag any card from the collection
## at the top into one of the 3 deck slots at the bottom to choose which 3 spawn
## buttons you take into a match. Keeps the deck to 3 distinct cards (dropping a
## card that's already slotted swaps it) and saves to user://settings.cfg via
## card_catalog.gd. Touch works through Godot's emulate-mouse-from-touch.

const CATALOG := preload("res://scripts/card_catalog.gd")
const UNIT_INSPECT := preload("res://scripts/unit_inspect.gd")

const SLOT_SIZE := 156.0
const TILE_SIZE := 124.0
const ACCENT := Color(1.0, 0.85, 0.35)

var _deck: Array = []          # the 3 chosen ids, in slot order
var _slot_icons: Array = []    # TextureRect per slot (filled by _build_slots)
var _tiles: Dictionary = {}    # id -> collection tile Control (for in-deck dimming)
var _wrap: HFlowContainer = null   # the collection container (rebuilt on unlock)
var _gold_label: Label = null      # top-right gold counter
var _click: AudioStreamPlayer = null
var _music: AudioStreamPlayer = null   # camp theme; gated by set_active (page is kept alive)
var on_back: Callable = Callable()   # set by the menu pager; called instead of self-freeing
var on_gold_changed: Callable = Callable()   # set by the menu; called when an unlock spends gold


# --- Drag source: one collection card -------------------------------------
class CardTile extends Panel:
	var card_id: String = ""
	var tex: Texture2D = null
	var locked: bool = false     # locked cards can't be dragged; a tap tries to unlock
	var screen = null            # the loadout screen (untyped; we call its _inspect)
	var _dragging: bool = false  # set when a drag starts, so a release isn't read as a tap
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if locked:
			return null          # no drag-to-deck until it's unlocked
		_dragging = true
		if screen != null:
			screen._play_click(1.05)   # pickup blip when a drag starts
		var prev := TextureRect.new()
		prev.texture = tex
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prev.custom_minimum_size = Vector2(124, 124)
		prev.size = Vector2(124, 124)
		prev.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(prev)
		return { "card_id": card_id }
	# A plain tap (press + release with no drag) opens the inspect popup; a drag still
	# routes through _get_drag_data to the deck slots untouched.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = false
			elif not _dragging and screen != null:
				# Tapping any card (locked or not) opens its details popup; that popup is
				# where a locked card is actually bought.
				screen._inspect(card_id)


# --- Drop target: one deck slot -------------------------------------------
class DeckSlot extends Panel:
	var index: int = 0
	var screen = null   # the loadout screen (untyped: we call its _assign / _inspect_slot)
	var _press: Vector2 = Vector2.ZERO
	var _pressed_in: bool = false
	func _can_drop_data(_at_position: Vector2, data) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("card_id")
	func _drop_data(_at_position: Vector2, data) -> void:
		if screen != null:
			screen._assign(index, str(data["card_id"]))
	# A plain tap on a slot opens the inspector for the card sitting in it (same popup
	# as the collection tiles). A press+release that moved more than a few px reads as a
	# swipe, not a tap, so dragging the menu pager over a slot won't pop the inspector.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press = event.position
				_pressed_in = true
			elif _pressed_in:
				_pressed_in = false
				if event.position.distance_to(_press) <= 10.0 and screen != null:
					screen._inspect_slot(index)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_deck = CATALOG.load_loadout()
	var click_path := "res://assets/audio/ui_click.mp3"
	if ResourceLoader.exists(click_path):
		_click = AudioStreamPlayer.new()
		_click.stream = load(click_path)
		_click.bus = "SFX"
		add_child(_click)
	# Calm camp theme on the Music bus (slider-controlled). It plays while this
	# screen exists and stops automatically when the node frees on Back.
	var theme_path := "res://audio/army_theme.mp3"
	if ResourceLoader.exists(theme_path):
		_music = AudioStreamPlayer.new()
		var ms = load(theme_path)
		if ms is AudioStreamMP3:
			ms.loop = true
		_music.stream = ms
		_music.bus = "Music"
		_music.volume_db = -5.0
		add_child(_music)
		_music.play()
		_music.stream_paused = true   # built ahead of time; the menu unpauses it on show
	_build_ui()


# The menu pager calls this on slide: the Army page is built ahead of time and kept,
# so its camp theme is gated to play only while the page is actually on screen.
func set_active(active: bool) -> void:
	if _music != null:
		_music.stream_paused = not active


func _build_ui() -> void:
	# Opaque base FIRST so the main menu behind us can never show through — not even
	# for a frame while the backdrop texture is still importing/loading. This is what
	# makes the loadout read as its own screen rather than a floating overlay.
	var base := ColorRect.new()
	base.color = Color(0.13, 0.17, 0.10)   # camp-green floor beneath the art
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let swipes pass to the menu pager
	add_child(base)
	# Backdrop: the army-camp art (cover-fit), then a soft dark scrim so the cards
	# and text stay readable on top. The scrim (mouse_filter STOP) also eats input so
	# the menu behind stays inert. All three use anchors+offsets so they fill the
	# whole viewport at any resolution.
	var bg := TextureRect.new()
	bg.texture = CATALOG.load_texture("res://assets/ui/army_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.03, 0.02, 0.5)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE (not STOP) so a horizontal swipe over empty army space reaches the menu's
	# pager handler; the cards and BACK button still capture their own taps/drags.
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_add_label("YOUR ARMY", 44, ACCENT, 120.0, 184.0)
	_add_label("Drag a card down into your 3 slots", 22, Color(1, 1, 1, 0.7), 188.0, 230.0)
	# Gold is shown by the menu's persistent coin badge (fixed across both pages); no
	# separate counter here.

	_build_collection()
	_add_label("YOUR DECK", 26, ACCENT, 612.0, 656.0)
	_build_slots()
	_build_back()
	_refresh()


func _add_label(text: String, size: int, col: Color, top: float, bottom: float) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = bottom
	add_child(l)


func _build_collection() -> void:
	var wrap := HFlowContainer.new()
	wrap.alignment = FlowContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("h_separation", 20)
	wrap.add_theme_constant_override("v_separation", 20)
	wrap.anchor_left = 0.0
	wrap.anchor_right = 1.0
	wrap.offset_left = 40.0
	wrap.offset_right = -40.0
	wrap.offset_top = 260.0
	wrap.offset_bottom = 660.0
	add_child(wrap)
	_wrap = wrap
	_populate_collection()


# (Re)fill the collection container with one tile per card. Called on build and
# again after an unlock, so a freshly-bought card immediately becomes draggable.
func _populate_collection() -> void:
	for c in _wrap.get_children():
		c.queue_free()
	_tiles.clear()
	for def in CATALOG.all():
		var tile := _make_tile(def)
		_wrap.add_child(tile)
		_tiles[def["id"]] = tile


func _make_tile(def: Dictionary) -> Control:
	var tile := CardTile.new()
	tile.card_id = def["id"]
	tile.screen = self
	tile.tex = CATALOG.load_texture(def["texture"])
	tile.locked = CATALOG.is_locked(def["id"])
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.tooltip_text = def["name"]
	tile.add_theme_stylebox_override("panel", _tile_style(false))

	var icon := TextureRect.new()
	icon.texture = tile.tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(icon)

	# Locked: tint the card art and stamp a gold lock icon over it (no text, no black
	# square). Tapping it (see CardTile._gui_input) opens the details popup to buy.
	if tile.locked:
		icon.modulate = Color(0.45, 0.48, 0.58, 0.9)   # cool, dimmed "locked" tint
		var lock := TextureRect.new()
		lock.texture = _lock_tex(80)
		lock.modulate = ACCENT                         # gold-tinted lock
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.anchor_left = 0.5; lock.anchor_right = 0.5
		lock.anchor_top = 0.5; lock.anchor_bottom = 0.5
		lock.offset_left = -40.0; lock.offset_right = 40.0
		lock.offset_top = -40.0; lock.offset_bottom = 40.0
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(lock)
	return tile


# Draw a white padlock (rounded body + shackle + keyhole) on transparent, so it can
# be tinted via modulate. Code-drawn for crisp alpha — no asset to import.
func _lock_tex(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(px) * 0.5
	var sh_cy := float(px) * 0.40    # shackle ring centre
	var r_out := float(px) * 0.24
	var r_in := float(px) * 0.14
	var bx0 := float(px) * 0.24
	var bx1 := float(px) * 0.76
	var by0 := float(px) * 0.46      # body top (also where the shackle legs stop)
	var by1 := float(px) * 0.84
	var kh_cy := (by0 + by1) * 0.5 + float(px) * 0.03
	var kh_r := float(px) * 0.07
	for y in px:
		for x in px:
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			var on := false
			if fy <= by0:   # shackle: ring, top arc + legs down to the body
				var d := Vector2(fx - cx, fy - sh_cy).length()
				if d <= r_out and d >= r_in:
					on = true
			if fx >= bx0 and fx <= bx1 and fy >= by0 and fy <= by1:
				on = true   # body
			if on and Vector2(fx - cx, fy - kh_cy).length() <= kh_r:
				on = false   # carve the keyhole
			if on:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


func _tile_style(in_deck: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.13, 0.09, 1.0)
	s.set_corner_radius_all(14)
	s.set_border_width_all(3)
	s.border_color = ACCENT if in_deck else Color(0.5, 0.4, 0.28)
	return s


func _build_slots() -> void:
	# A little wooden frame grouping the 3 deck slots. Added FIRST so it sits behind them.
	var slots_w := 3.0 * SLOT_SIZE + 2.0 * 30.0   # 3 slots + 2 separations
	var pad := 22.0
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.offset_left = -slots_w * 0.5 - pad
	frame.offset_right = slots_w * 0.5 + pad
	frame.offset_top = 680.0 - pad
	frame.offset_bottom = 680.0 + SLOT_SIZE + pad
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.10, 0.07, 0.04, 0.5)   # subtle dark-wood fill
	fsb.set_corner_radius_all(24)
	fsb.set_border_width_all(4)
	fsb.border_color = ACCENT   # gold border to match the menu
	frame.add_theme_stylebox_override("panel", fsb)
	add_child(frame)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.offset_top = 680.0
	row.offset_bottom = 680.0 + SLOT_SIZE
	add_child(row)
	_slot_icons.resize(3)
	for i in 3:
		var slot := DeckSlot.new()
		slot.index = i
		slot.screen = self
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.06, 0.05, 0.04, 1.0)
		s.set_corner_radius_all(16)
		s.set_border_width_all(4)
		s.border_color = ACCENT
		slot.add_theme_stylebox_override("panel", s)

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		_slot_icons[i] = icon
		row.add_child(slot)


func _build_back() -> void:
	# Wooden menu-button look (swapped in from the options screen): a chroma-keyed
	# button_wide.png with a brown "BACK" label.
	var back := TextureButton.new()
	var tex := load("res://assets/ui/button_wide.png")
	if tex is Texture2D:
		back.texture_normal = tex
		back.texture_pressed = tex
	back.ignore_texture_size = true
	back.stretch_mode = TextureButton.STRETCH_SCALE
	var shader = load("res://shaders/white_key.gdshader")
	if shader is Shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("white_cut", 0.86)
		mat.set_shader_parameter("sat_max", 0.1)
		mat.set_shader_parameter("softness", 0.04)
		back.material = mat
	back.custom_minimum_size = Vector2(280, 88)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -140.0
	back.offset_right = 140.0
	back.offset_top = -230.0
	back.offset_bottom = -142.0
	back.pressed.connect(_on_back)
	add_child(back)
	var lbl := Label.new()
	lbl.text = "BACK"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_color_override("font_color", Color(0.25, 0.13, 0.05))
	lbl.add_theme_font_size_override("font_size", 32)
	back.add_child(lbl)


func _on_back() -> void:
	_play_click(0.9)   # soft "back" blip
	if on_back.is_valid():
		on_back.call()   # let the menu pager slide back to the menu and free this page
	else:
		queue_free()


# Top-right gold counter (the same coins the menu badge shows).
func _add_gold_badge() -> void:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = -300.0
	l.offset_right = -28.0
	l.offset_top = 60.0
	l.offset_bottom = 104.0
	add_child(l)
	_gold_label = l
	_update_gold()


func _update_gold() -> void:
	if _gold_label != null:
		_gold_label.text = "Gold: %d" % Profile.get_coins()


# Shared UI click for every interaction on this screen. pitch > 1 reads as
# "confirm/buy", < 1 as "back/denied", so actions feel distinct from one sample.
func _play_click(pitch := 1.0) -> void:
	if _click == null or _click.stream == null:
		return
	_click.pitch_scale = pitch
	_click.play()


# Called by the inspect popup after it successfully buys a locked card: rebuild the
# collection (the card becomes draggable) and refresh the gold counter.
func _refresh_after_unlock() -> void:
	_populate_collection()
	_refresh()
	_update_gold()
	if on_gold_changed.is_valid():
		on_gold_changed.call()   # refresh the menu's persistent coin badge


# Tap on a deck slot -> inspect whichever card currently sits in that slot.
func _inspect_slot(i: int) -> void:
	if i < 0 or i >= _deck.size():
		return
	_inspect(str(_deck[i]))


# Tap on a collection card -> open the inspect popup for that unit.
func _inspect(card_id: String) -> void:
	var def: Dictionary = CATALOG.by_id(card_id)
	if def.is_empty():
		return
	_play_click()
	var popup = UNIT_INSPECT.new()
	popup.setup(def)
	popup.on_unlocked = _refresh_after_unlock   # popup does the buy; we refresh grid + gold
	add_child(popup)


# Drop card `id` into slot `i`, keeping the deck to 3 distinct cards. If the card
# already sits in another slot, the two swap so nothing is lost or duplicated.
func _assign(i: int, id: String) -> void:
	if i < 0 or i >= 3 or _deck[i] == id:
		return
	var j: int = _deck.find(id)
	if j != -1:
		_deck[j] = _deck[i]   # the card displaced from slot i moves into slot j
	_deck[i] = id
	CATALOG.save_loadout(_deck)
	_refresh()
	_play_click(1.08)   # confirm blip when a card lands in a slot


func _refresh() -> void:
	for i in _slot_icons.size():
		var icon: TextureRect = _slot_icons[i]
		if icon == null:
			continue
		var def: Dictionary = CATALOG.by_id(_deck[i]) if i < _deck.size() else {}
		icon.texture = CATALOG.load_texture(def["texture"]) if not def.is_empty() else null
	# Highlight (gold border) + dim the collection cards that are currently in the deck.
	for id in _tiles:
		var tile: Panel = _tiles[id]
		var in_deck: bool = _deck.has(id)
		tile.add_theme_stylebox_override("panel", _tile_style(in_deck))
		tile.modulate = Color(1, 1, 1, 0.45) if in_deck else Color.WHITE
