extends Control
# Main menu: Start loads + launches the diorama (behind a loading overlay), Options
# shows the audio panel.
# Expects this exact node tree (paths below must match menu.tscn):
#   Menu (Control, this script)
#   ├── Splash (TextureRect)
#   ├── Buttons (VBoxContainer)
#   │   ├── StartButton / OptionsButton (TextureButton)
#   └── OptionsPanel (Panel)
#       ├── MusicRow/MusicSlider (HSlider 0..1)
#       ├── SfxRow/SfxSlider (HSlider 0..1)
#       └── BackButton (TextureButton)

const SETTINGS_PATH := "user://settings.cfg"
const MAIN_SCENE := "res://scenes/main.tscn"
const LOADOUT := preload("res://scripts/loadout.gd")
const PROFILE := preload("res://scripts/profile.gd")

# Button feel: a quick scale + tint on hover and press, plus a click on release.
const HOVER_SCALE := 1.05
const PRESS_SCALE := 0.95
const HOVER_TINT := Color(1.14, 1.14, 1.14)   # slight brighten on hover
const PRESS_TINT := Color(0.82, 0.82, 0.82)    # slight darken while held
const FEEL_TIME := 0.08                          # tween duration, snappy

@onready var options_panel: Panel = $OptionsPanel
@onready var music_slider: HSlider = $OptionsPanel/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $OptionsPanel/SfxRow/SfxSlider

var _click: AudioStreamPlayer
var _theme: AudioStreamPlayer   # looping main-menu theme on the Music bus
var _feel_tweens := {}   # button -> active Tween, so a new state cancels the old
var _backdrop: ColorRect   # dim layer behind the options panel (built in _style_options)

# Loading overlay (raised by Start while the battle scene finishes loading).
var _loading := false
var _loading_overlay: Control
var _loading_bar: ProgressBar
var _loading_label: Label
var _load_shown := 0.0   # smoothed bar fill (eases toward the real progress)
var _load_dots := 0.0    # drives the animated "Loading..." dots

func _ready() -> void:
	# Warm the battle scene (and every GLB/texture it pulls in) on a background
	# thread while the menu sits idle, so tapping Start is an instant switch
	# instead of a synchronous load stall. Kicked off first to maximize headroom.
	ResourceLoader.load_threaded_request(MAIN_SCENE)
	options_panel.visible = false
	$Buttons/StartButton.pressed.connect(_on_start)
	$Buttons/OptionsButton.pressed.connect(_on_options)
	$OptionsPanel/BackButton.pressed.connect(_on_back)
	# Shared one-shot click player, routed through the SFX bus (slider-controlled).
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://assets/audio/ui_click.mp3")
	_click.bus = "SFX"
	add_child(_click)
	# Looping title theme, routed through the Music bus (slider-controlled).
	_theme = AudioStreamPlayer.new()
	var theme_stream: AudioStream = load("res://audio/menu_theme.mp3")
	if theme_stream is AudioStreamMP3:
		theme_stream.loop = true   # seamlessly repeat the 60s loop
	_theme.stream = theme_stream
	_theme.bus = "Music"
	_theme.volume_db = -4.0
	add_child(_theme)
	_theme.play()
	# Give every menu button hover/press feedback + the click sound.
	for b in [$Buttons/StartButton, $Buttons/OptionsButton,
			$OptionsPanel/BackButton]:
		_wire_feel(b)
	# "Army" loadout button — duplicate Options so it matches the menu style exactly,
	# slot it directly under Start, and open the loadout overlay on press.
	# duplicate(0): copy the node + Label child + style, but NOT signal connections
	# (otherwise it'd inherit Options' pressed->_on_options and open both).
	var army = $Buttons/OptionsButton.duplicate(0)
	army.name = "ArmyButton"
	army.get_node("Label").text = "Army"
	$Buttons.add_child(army)
	$Buttons.move_child(army, 1)
	army.pressed.connect(_on_army)
	_wire_feel(army)
	# Apply saved settings before wiring slider signals so we don't re-save on load.
	_load_settings()
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	# "Royal Clash" title logo across the top, above the buttons.
	_add_title()
	# Persistent level + XP badge (top-left), reflecting wins from past sessions.
	_add_level_badge()
	# Persistent coin counter (top-right).
	_add_coin_badge()
	# Re-skin the audio options panel to match the wooden menu. Runs AFTER the title
	# logo is added so the panel + dim backdrop layer above it when opened.
	_style_options()

func _on_start() -> void:
	# Don't switch straight to the battle scene — its first-ever load decodes a pile
	# of GLBs/textures and stalls for several seconds. Instead raise a loading overlay
	# and let _process animate a bar over the background (threaded) load that _ready
	# already kicked off, switching only once the scene is fully in memory.
	if _loading:
		return
	_begin_loading()

func _begin_loading() -> void:
	_loading = true
	# The load was requested in _ready; re-issue it only if nothing's in flight
	# (defensive — e.g. if it was already consumed somehow).
	var progress: Array = []
	if ResourceLoader.load_threaded_get_status(MAIN_SCENE, progress) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(MAIN_SCENE)
	_build_loading_overlay()

func _process(delta: float) -> void:
	if not _loading:
		return
	# Animated "Loading..." dots.
	_load_dots += delta * 3.0
	_loading_label.text = "Loading" + ".".repeat(int(_load_dots) % 4)
	# Poll the threaded load and ease the bar toward its real progress.
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE, progress)
	var target := 0.05
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		target = float(progress[0]) if progress.size() > 0 else 0.05
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		target = 1.0
	_load_shown = move_toward(_load_shown, target, delta * 0.8)
	_loading_bar.value = _load_shown * 100.0
	# Switch only once it's fully loaded AND the bar has visually caught up.
	if status == ResourceLoader.THREAD_LOAD_LOADED and _load_shown >= 0.999:
		_finish_loading()

func _finish_loading() -> void:
	_loading = false   # stop polling; the instantiate stall now happens behind the overlay
	_loading_bar.value = 100.0
	_loading_label.text = "Loading..."
	var pack: Resource = ResourceLoader.load_threaded_get(MAIN_SCENE)
	# Defer one frame so this full-bar frame paints, then swap. The (synchronous)
	# instantiate stall happens with the overlay still covering the screen.
	if pack is PackedScene:
		call_deferred("_swap_to", pack)
	else:
		call_deferred("_swap_to_file")

func _swap_to(pack: PackedScene) -> void:
	get_tree().change_scene_to_packed(pack)

func _swap_to_file() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)

# Full-screen loading card raised over the menu while the battle scene finishes
# loading. Dimmed splash backdrop + a wood/gold progress bar matching the menu skin.
func _build_loading_overlay() -> void:
	var wood_dark := Color(0.28, 0.16, 0.07)
	var gold := Color(0.87, 0.64, 0.23)
	var parch := Color(0.91, 0.82, 0.63)

	_loading_overlay = Control.new()
	_loading_overlay.name = "LoadingOverlay"
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks to the menu behind
	add_child(_loading_overlay)
	move_child(_loading_overlay, get_child_count() - 1)         # above title + buttons

	# Dimmed splash backdrop so the load screen reads as part of the menu.
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := _load_tex("res://assets/ui/splash.png")
	if tex != null:
		bg.texture = tex
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(bg)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.02, 0.0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(dim)

	# Progress bar, lower third, centered.
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	_loading_bar.anchor_left = 0.5
	_loading_bar.anchor_right = 0.5
	_loading_bar.anchor_top = 0.72
	_loading_bar.anchor_bottom = 0.72
	_loading_bar.offset_left = -260.0
	_loading_bar.offset_right = 260.0
	_loading_bar.offset_top = 0.0
	_loading_bar.offset_bottom = 36.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.30, 0.18, 0.09)
	track.border_color = wood_dark
	track.set_border_width_all(3)
	track.set_corner_radius_all(10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = gold
	fill.set_corner_radius_all(10)
	_loading_bar.add_theme_stylebox_override("background", track)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading_overlay.add_child(_loading_bar)

	# "Loading..." caption under the bar.
	_loading_label = Label.new()
	_loading_label.text = "Loading"
	_loading_label.add_theme_color_override("font_color", parch)
	_loading_label.add_theme_font_size_override("font_size", 30)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.anchor_left = 0.5
	_loading_label.anchor_right = 0.5
	_loading_label.anchor_top = 0.72
	_loading_label.anchor_bottom = 0.72
	_loading_label.offset_left = -260.0
	_loading_label.offset_right = 260.0
	_loading_label.offset_top = 46.0
	_loading_label.offset_bottom = 86.0
	_loading_overlay.add_child(_loading_label)

	# Fade the card in so the Start press reads smoothly.
	_loading_overlay.modulate.a = 0.0
	create_tween().tween_property(_loading_overlay, "modulate:a", 1.0, 0.2)

func _on_army() -> void:
	# Full-screen loadout overlay built in code; it frees itself on Back. Pause the
	# menu theme while it's up (the loadout plays its own calm track) and resume when
	# it closes, so the two never overlap.
	if _theme != null:
		_theme.stream_paused = true
	var screen = LOADOUT.new()
	screen.tree_exited.connect(_resume_theme)
	add_child(screen)

func _resume_theme() -> void:
	if is_instance_valid(_theme):
		_theme.stream_paused = false

func _on_options() -> void:
	_backdrop.visible = true
	_backdrop.modulate.a = 0.0
	options_panel.visible = true
	# Pop the panel in from slightly small + transparent, with the backdrop fading up.
	options_panel.pivot_offset = options_panel.size * 0.5
	options_panel.scale = Vector2(0.85, 0.85)
	options_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.16)
	tw.tween_property(options_panel, "modulate:a", 1.0, 0.16)
	tw.tween_property(options_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_back() -> void:
	options_panel.visible = false
	_backdrop.visible = false

func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return  # bus only exists at runtime via the project's bus layout
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))

func _on_music_changed(v: float) -> void:
	_apply_bus("Music", v)
	_save_settings()

func _on_sfx_changed(v: float) -> void:
	_apply_bus("SFX", v)
	_save_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var m: float = cfg.get_value("audio", "music", 1.0)
	var s: float = cfg.get_value("audio", "sfx", 1.0)
	music_slider.value = m
	sfx_slider.value = s
	_apply_bus("Music", m)
	_apply_bus("SFX", s)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_slider.value)
	cfg.set_value("audio", "sfx", sfx_slider.value)
	cfg.save(SETTINGS_PATH)

# --- Button feel ---
# Hover: scale up + brighten. Press: scale down + darken. Release: pop back to
# hover (if still over) or rest, and play the click. Scale pivots from the button
# center, so we keep pivot_offset synced to the container-driven size.
func _wire_feel(btn: BaseButton) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	btn.mouse_entered.connect(func() -> void: _feel(btn, HOVER_SCALE, HOVER_TINT))
	btn.mouse_exited.connect(func() -> void: _feel(btn, 1.0, Color.WHITE))
	btn.button_down.connect(func() -> void: _feel(btn, PRESS_SCALE, PRESS_TINT))
	btn.button_up.connect(func() -> void:
		# On release, settle into hover if the cursor is still over the button.
		var over := btn.get_global_rect().has_point(btn.get_global_mouse_position())
		_feel(btn, HOVER_SCALE if over else 1.0, HOVER_TINT if over else Color.WHITE))
	btn.pressed.connect(func() -> void: _click.play())

func _feel(btn: Control, scale_to: float, tint: Color) -> void:
	var prev = _feel_tweens.get(btn)
	if prev != null and prev.is_valid():
		prev.kill()
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(scale_to, scale_to), FEEL_TIME)
	tw.tween_property(btn, "modulate", tint, FEEL_TIME)
	_feel_tweens[btn] = tw

# --- Title logo ---
# Big "Royal Clash" logo across the top, sized by screen-relative anchors so it
# scales with any resolution and sits above the centered buttons.
func _add_title() -> void:
	var tex := _load_tex("res://assets/ui/title.png")
	if tex == null:
		return
	var title := TextureRect.new()
	title.name = "Title"
	title.texture = tex
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top portion of the screen, centered ~64% of the width; KEEP_ASPECT fits the logo.
	title.anchor_left = 0.18
	title.anchor_right = 0.82
	title.anchor_top = 0.0
	title.anchor_bottom = 0.37
	title.offset_left = 0.0
	title.offset_right = 0.0
	title.offset_top = 0.0
	title.offset_bottom = 0.0
	add_child(title)

# Persistent player level + XP badge, top-left, in the wooden menu style. Reads the
# saved profile so it reflects wins earned in previous sessions.
func _add_level_badge() -> void:
	var wood_dark := Color(0.28, 0.16, 0.07)
	var brown := Color(0.25, 0.13, 0.05)
	var gold := Color(0.87, 0.64, 0.23)
	var level := PROFILE.get_level()
	var xp := PROFILE.get_xp()
	var to_next: int = max(1, PROFILE.xp_to_next(level))

	var panel := Panel.new()
	panel.name = "LevelBadge"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left = 22; panel.offset_top = 82
	panel.offset_right = 22 + 236; panel.offset_bottom = 82 + 92
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.91, 0.82, 0.63, 0.96)
	sb.border_color = wood_dark
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var lvl := Label.new()
	lvl.text = "Lv %d" % level
	lvl.add_theme_color_override("font_color", brown)
	lvl.add_theme_font_size_override("font_size", 34)
	lvl.position = Vector2(16, 6)
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lvl)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = to_next
	bar.value = xp
	bar.position = Vector2(16, 54)
	bar.size = Vector2(204, 24)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.30, 0.18, 0.09)
	track.border_color = wood_dark
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = gold
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	panel.add_child(bar)

# Persistent coin counter, top-right, mirroring the level badge.
func _add_coin_badge() -> void:
	var wood_dark := Color(0.28, 0.16, 0.07)
	var brown := Color(0.25, 0.13, 0.05)
	var coins := PROFILE.get_coins()

	var panel := Panel.new()
	panel.name = "CoinBadge"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.anchor_top = 0.0; panel.anchor_bottom = 0.0
	panel.offset_right = -22; panel.offset_left = -22 - 200
	panel.offset_top = 82; panel.offset_bottom = 82 + 64
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.91, 0.82, 0.63, 0.96)
	sb.border_color = wood_dark
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	# Reuse the slider-knob disc as a little gold coin icon.
	var coin := TextureRect.new()
	coin.texture = _make_knob(40, Color(0.96, 0.80, 0.34), Color(0.62, 0.42, 0.12))
	coin.position = Vector2(14, 12)
	coin.size = Vector2(40, 40)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(coin)

	var lbl := Label.new()
	lbl.text = str(coins)
	lbl.add_theme_color_override("font_color", brown)
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.position = Vector2(64, 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

# Load a texture, falling back to a raw image read so it works before Godot has
# imported the PNG (the logo was written straight to disk).
func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null

# --- Options panel skin ---
# Re-dress the default grey Panel + sliders into the game's wooden/parchment look:
# a bordered parchment card over a dim backdrop, a carved brown title, and chunky
# wood-groove sliders with a gold fill and a round knob. All theme overrides, so the
# scene's node tree is untouched.
func _style_options() -> void:
	var wood_dark := Color(0.28, 0.16, 0.07)
	var brown := Color(0.25, 0.13, 0.05)
	var parch := Color(0.91, 0.82, 0.63)
	var gold := Color(0.87, 0.64, 0.23)

	# Lift the panel above the title logo, and slip a full-screen dim backdrop just
	# beneath it so opening Options reads as a focused modal.
	move_child(options_panel, get_child_count() - 1)
	_backdrop = ColorRect.new()
	_backdrop.name = "OptionsBackdrop"
	_backdrop.color = Color(0, 0, 0, 0.5)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks to the menu behind
	_backdrop.visible = false
	add_child(_backdrop)
	move_child(_backdrop, options_panel.get_index())     # directly beneath the panel
	# Click outside the card closes it.
	_backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_on_back())

	# Parchment card: thick wood border, rounded, soft drop shadow.
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = parch
	panel_sb.border_color = wood_dark
	panel_sb.set_border_width_all(7)
	panel_sb.set_corner_radius_all(26)
	panel_sb.shadow_color = Color(0, 0, 0, 0.35)
	panel_sb.shadow_size = 10
	panel_sb.shadow_offset = Vector2(0, 8)
	options_panel.add_theme_stylebox_override("panel", panel_sb)

	# Carved title + a thin rule beneath it.
	var title: Label = options_panel.get_node("Title")
	title.add_theme_color_override("font_color", brown)
	title.add_theme_font_size_override("font_size", 46)
	var rule := ColorRect.new()
	rule.color = Color(wood_dark.r, wood_dark.g, wood_dark.b, 0.55)
	rule.anchor_left = 0.5
	rule.anchor_right = 0.5
	rule.offset_left = -170.0
	rule.offset_right = 170.0
	rule.offset_top = 80.0
	rule.offset_bottom = 83.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	options_panel.add_child(rule)

	# Row labels in brown.
	for p in ["MusicRow/Label", "SfxRow/Label"]:
		var l: Label = options_panel.get_node(p)
		l.add_theme_color_override("font_color", brown)
		l.add_theme_font_size_override("font_size", 30)

	# Slider skin: dark wood groove, gold fill, round wooden knob.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.30, 0.18, 0.09)
	track.border_color = wood_dark
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	track.set_content_margin_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = gold
	fill.set_corner_radius_all(8)
	fill.set_content_margin_all(6)
	var fill_hi: StyleBoxFlat = fill.duplicate()
	fill_hi.bg_color = Color(0.96, 0.74, 0.32)
	var knob := _make_knob(30, Color(0.95, 0.80, 0.42), wood_dark)
	var knob_hi := _make_knob(30, Color(1.0, 0.88, 0.55), wood_dark)
	for sl in [music_slider, sfx_slider]:
		sl.add_theme_stylebox_override("slider", track)
		sl.add_theme_stylebox_override("grabber_area", fill)
		sl.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
		sl.add_theme_icon_override("grabber", knob)
		sl.add_theme_icon_override("grabber_highlight", knob_hi)
		sl.add_theme_icon_override("grabber_disabled", knob)

# A round knob texture: a filled disc with a darker rim, anti-aliased at the edge.
func _make_knob(d: int, fill: Color, rim: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (d - 1) * 0.5
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) - c, float(y) - c).length()
			var a := clampf(r - dist + 0.5, 0.0, 1.0)   # soft outer edge
			if a <= 0.0:
				continue
			var col: Color = rim if (r - dist) < 3.5 else fill
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
