extends CanvasLayer
## Match-start "VS" intro splash. Two heraldic banner sprites charge in from the
## sides — the RED enemy banner sits up high, the BLUE player banner down low — and
## a gold VS emblem SLAMS into the centre gap on the gong (white flash), then a
## FIGHT! punch lands on the announcer before the whole thing slides out.
##
## The enemy is given a random name each match. Purely cosmetic and NON-BLOCKING
## (ignores input) so the squads spawning behind it and the player's first drag
## aren't held up. The battle manager adds one at match start; it owns the gong +
## announcer_fight timing so the audio lines up with the visuals, then frees itself.

@export var player_name: String = "YOU"
@export var enemy_name: String = ""        # blank -> a random name is picked at _ready

const SFX := preload("res://scripts/sfx.gd")

const GOLD := Color(0.96, 0.81, 0.36)
const BLUE_BG := Color(0.11, 0.27, 0.62, 0.95)   # fallback band colour if the sprite is missing
const RED_BG := Color(0.60, 0.13, 0.13, 0.95)

const BANNER_W := 660.0
const BANNER_H := 230.0
const BANNER_GAP := 232.0   # how far above / below centre each banner rests

# A grab-bag of rival names — one is picked at random each match.
const ENEMY_NAMES := [
	"Steve", "Mortimer", "Sir Reginald", "Bonk", "Greg the Bold", "Xandar",
	"Lady Vexa", "Gareth", "Old Tom", "Krug", "Pixel", "Duchess", "Vlad",
	"Roland", "Brunhilda", "Zap", "Sir Lancelot", "Mungo", "Thorne", "Victor",
	"Gravy", "Hank", "Wartooth", "Plop", "Queen Mab", "Marcus",
]

var _vp: Vector2 = Vector2.ZERO
var _root: Control = null
var _backdrop: ColorRect = null
var _flash: ColorRect = null
var _player_banner: Control = null
var _enemy_banner: Control = null
var _vs: Label = null

func _ready() -> void:
	layer = 60   # above the HUD / timer / pause button
	randomize()
	if enemy_name == "":
		enemy_name = ENEMY_NAMES[randi() % ENEMY_NAMES.size()]
	_vp = get_viewport().get_visible_rect().size
	_build()
	_play()

# Sounds are parented to our parent (the persistent battle manager), not to us, so
# the gong/announcer tails keep ringing after this overlay frees itself.
func _sfx_host() -> Node:
	var p := get_parent()
	return p if p != null else self

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	var cy := _vp.y * 0.5

	# Enemy banner (red) sits HIGH and charges in from the left.
	_enemy_banner = _make_banner("res://ui/banner_red.png", RED_BG, enemy_name)
	_enemy_banner.position = Vector2(-BANNER_W, cy - BANNER_GAP - _enemy_banner.size.y * 0.5)
	_root.add_child(_enemy_banner)

	# Player banner (blue) sits LOW and charges in from the right.
	_player_banner = _make_banner("res://ui/banner_blue.png", BLUE_BG, player_name)
	_player_banner.position = Vector2(_vp.x, cy + BANNER_GAP - _player_banner.size.y * 0.5)
	_root.add_child(_player_banner)

	# Gold "VS" emblem in the centre gap, hidden until the slam.
	_vs = _make_center_label("VS", 150, GOLD, Color(0.18, 0.08, 0.0), 14, 360, 220)
	_vs.scale = Vector2(4, 4)
	_vs.modulate = Color(1, 1, 1, 0)
	_root.add_child(_vs)

	# Full-screen white flash for the slam.
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

# A banner holder: the sprite if it's imported, else a styled colour band; with the
# name drawn centred on top of it.
func _make_banner(tex_path: String, fallback_bg: Color, who: String) -> Control:
	var tex := _load_tex(tex_path)
	# The sprite PNG is square (banner art letterboxed in transparent margins), so the
	# holder is square when we have it (the empty margins just sit off to the sides);
	# the fallback band is a short wide strip instead.
	var h: float = BANNER_W if tex != null else BANNER_H
	var holder := Control.new()
	holder.size = Vector2(BANNER_W, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.pivot_offset = Vector2(BANNER_W * 0.5, h * 0.5)

	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	else:
		var band := Panel.new()
		band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = fallback_bg
		sb.border_color = GOLD
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(18)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 10
		band.add_theme_stylebox_override("panel", sb)
		holder.add_child(band)

	var lbl := Label.new()
	lbl.text = who
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.add_theme_font_size_override("font_size", 58)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.0))
	lbl.add_theme_constant_override("outline_size", 9)
	holder.add_child(lbl)
	return holder

func _make_center_label(txt: String, fsize: int, col: Color, outline: Color, osize: int, w: float, h: float) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", outline)
	lbl.add_theme_constant_override("outline_size", osize)
	lbl.size = Vector2(w, h)
	lbl.pivot_offset = Vector2(w * 0.5, h * 0.5)
	lbl.position = Vector2(_vp.x * 0.5 - w * 0.5, _vp.y * 0.5 - h * 0.5)
	return lbl

func _play() -> void:
	var rest_x := _vp.x * 0.5 - BANNER_W * 0.5
	var t := create_tween()
	# Beat 1: backdrop dims while both banners charge in (slight overshoot).
	t.tween_callback(func() -> void:
		var a := create_tween().set_parallel(true)
		a.tween_property(_backdrop, "color:a", 0.5, 0.25)
		a.tween_property(_enemy_banner, "position:x", rest_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		a.tween_property(_player_banner, "position:x", rest_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	t.tween_interval(0.44)
	# Beat 2: the VS slams in on the gong, with a white flash.
	t.tween_callback(func() -> void:
		SFX.play(_sfx_host(), "res://audio/gong", -2.0, 0.0)
		var a := create_tween().set_parallel(true)
		a.tween_property(_vs, "modulate:a", 1.0, 0.12)
		a.tween_property(_vs, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var f := create_tween()
		f.tween_property(_flash, "color:a", 0.55, 0.06)
		f.tween_property(_flash, "color:a", 0.0, 0.30))
	t.tween_interval(1.05)
	# Beat 3: FIGHT! punch on the announcer.
	t.tween_callback(func() -> void:
		SFX.play(_sfx_host(), "res://audio/announcer_fight", 2.0, 0.0, 0.64)
		_fight_punch())
	t.tween_interval(0.70)
	# Beat 4: banners slide back out, everything fades, then free.
	t.tween_callback(func() -> void:
		var a := create_tween().set_parallel(true)
		a.tween_property(_enemy_banner, "position:x", -BANNER_W, 0.32).set_ease(Tween.EASE_IN)
		a.tween_property(_player_banner, "position:x", _vp.x, 0.32).set_ease(Tween.EASE_IN)
		a.tween_property(_backdrop, "color:a", 0.0, 0.32)
		a.tween_property(_root, "modulate:a", 0.0, 0.34))
	t.tween_interval(0.42)
	t.tween_callback(queue_free)

# Swap the VS emblem for a big FIGHT! that punches in.
func _fight_punch() -> void:
	var v := create_tween()
	v.tween_property(_vs, "modulate:a", 0.0, 0.12)
	var f := _make_center_label("FIGHT!", 132, Color(1.0, 0.86, 0.3), Color(0.5, 0.05, 0.0), 16, 540, 200)
	f.scale = Vector2(2.2, 2.2)
	f.modulate = Color(1, 1, 1, 0)
	_root.add_child(f)
	var a := create_tween().set_parallel(true)
	a.tween_property(f, "modulate:a", 1.0, 0.10)
	a.tween_property(f, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
