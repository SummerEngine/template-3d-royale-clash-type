extends Control
## "Your Army" loadout screen — a full-screen overlay over the main menu (built in
## code, added/removed by menu.gd; no scene file). Drag any card from the collection
## at the top into one of the 3 deck slots at the bottom to choose which 3 spawn
## buttons you take into a match. Keeps the deck to 3 distinct cards (dropping a
## card that's already slotted swaps it) and saves to user://settings.cfg via
## card_catalog.gd. Touch works through Godot's emulate-mouse-from-touch.

const CATALOG := preload("res://scripts/card_catalog.gd")

const SLOT_SIZE := 156.0
const TILE_SIZE := 124.0
const ACCENT := Color(1.0, 0.85, 0.35)

var _deck: Array = []          # the 3 chosen ids, in slot order
var _slot_icons: Array = []    # TextureRect per slot (filled by _build_slots)
var _tiles: Dictionary = {}    # id -> collection tile Control (for in-deck dimming)
var _click: AudioStreamPlayer = null


# --- Drag source: one collection card -------------------------------------
class CardTile extends Panel:
	var card_id: String = ""
	var tex: Texture2D = null
	func _get_drag_data(_at_position: Vector2) -> Variant:
		var prev := TextureRect.new()
		prev.texture = tex
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prev.custom_minimum_size = Vector2(124, 124)
		prev.size = Vector2(124, 124)
		prev.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(prev)
		return { "card_id": card_id }


# --- Drop target: one deck slot -------------------------------------------
class DeckSlot extends Panel:
	var index: int = 0
	var screen = null   # the loadout screen (untyped: we call its _assign, not a Control method)
	func _can_drop_data(_at_position: Vector2, data) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("card_id")
	func _drop_data(_at_position: Vector2, data) -> void:
		if screen != null:
			screen._assign(index, str(data["card_id"]))


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
		var music := AudioStreamPlayer.new()
		var ms = load(theme_path)
		if ms is AudioStreamMP3:
			ms.loop = true
		music.stream = ms
		music.bus = "Music"
		music.volume_db = -5.0
		add_child(music)
		music.play()
	_build_ui()


func _build_ui() -> void:
	# Opaque base FIRST so the main menu behind us can never show through — not even
	# for a frame while the backdrop texture is still importing/loading. This is what
	# makes the loadout read as its own screen rather than a floating overlay.
	var base := ColorRect.new()
	base.color = Color(0.13, 0.17, 0.10)   # camp-green floor beneath the art
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	_add_label("YOUR ARMY", 44, ACCENT, 40.0, 104.0)
	_add_label("Drag a card down into your 3 slots", 22, Color(1, 1, 1, 0.7), 108.0, 150.0)

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
	for def in CATALOG.all():
		var tile := _make_tile(def)
		wrap.add_child(tile)
		_tiles[def["id"]] = tile


func _make_tile(def: Dictionary) -> Control:
	var tile := CardTile.new()
	tile.card_id = def["id"]
	tile.tex = CATALOG.load_texture(def["texture"])
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
	return tile


func _tile_style(in_deck: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.13, 0.09, 1.0)
	s.set_corner_radius_all(14)
	s.set_border_width_all(3)
	s.border_color = ACCENT if in_deck else Color(0.5, 0.4, 0.28)
	return s


func _build_slots() -> void:
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
	queue_free()


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
	if _click != null and _click.stream != null:
		_click.play()


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
