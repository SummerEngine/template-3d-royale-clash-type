extends Control
# Main menu: Start launches the diorama, Options shows the audio panel, Quit exits.
# Expects this exact node tree (paths below must match menu.tscn):
#   Menu (Control, this script)
#   ├── Splash (TextureRect)
#   ├── Buttons (VBoxContainer)
#   │   ├── StartButton / OptionsButton / QuitButton (TextureButton)
#   └── OptionsPanel (Panel)
#       ├── MusicRow/MusicSlider (HSlider 0..1)
#       ├── SfxRow/SfxSlider (HSlider 0..1)
#       └── BackButton (TextureButton)

const SETTINGS_PATH := "user://settings.cfg"
const MAIN_SCENE := "res://scenes/main.tscn"

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

func _ready() -> void:
	# Warm the battle scene (and every GLB/texture it pulls in) on a background
	# thread while the menu sits idle, so tapping Start is an instant switch
	# instead of a synchronous load stall. Kicked off first to maximize headroom.
	ResourceLoader.load_threaded_request(MAIN_SCENE)
	options_panel.visible = false
	$Buttons/StartButton.pressed.connect(_on_start)
	$Buttons/OptionsButton.pressed.connect(_on_options)
	$Buttons/QuitButton.pressed.connect(_on_quit)
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
	for b in [$Buttons/StartButton, $Buttons/OptionsButton, $Buttons/QuitButton,
			$OptionsPanel/BackButton]:
		_wire_feel(b)
	# Apply saved settings before wiring slider signals so we don't re-save on load.
	_load_settings()
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	# "Royal Clash" title logo across the top, above the buttons.
	_add_title()

func _on_start() -> void:
	# Grab the background-loaded scene. If the load finished (it usually has by the
	# time the player taps Start) this returns instantly; if not, it blocks only for
	# whatever's left — never slower than the old synchronous load. Switch to the
	# in-memory PackedScene so no disk/import work happens during the transition.
	var pack: Resource = ResourceLoader.load_threaded_get(MAIN_SCENE)
	if pack is PackedScene:
		get_tree().change_scene_to_packed(pack)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)

func _on_options() -> void:
	options_panel.visible = true

func _on_back() -> void:
	options_panel.visible = false

func _on_quit() -> void:
	get_tree().quit()

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
