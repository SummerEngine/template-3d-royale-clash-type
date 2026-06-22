extends CanvasLayer
## Fixed on-screen health HUD for the two houses — the match objective, so it's
## always visible regardless of camera. Both bars ride the top of the screen at
## the same height: player house top-left (blue), enemy house top-right (red).
## Each bar ramps
## green -> amber -> red, shows a live HP fraction, and pulses (flash + scale
## throb) once that house drops into the danger zone.
##
## Built entirely in code (no .tscn), same as the elixir HUD.
## Contract: bind(player_base, enemy_base) is called by the battle manager BEFORE
## add_child(). Each base exposes: var hp, var max_hp, var alive, var team.

const MARGIN := 28.0
const BAR_W := 380.0
const BAR_H := 28.0
const PANEL_H := 72.0
const DANGER_FRAC := 0.30

const COL_GREEN := Color(0.25, 0.85, 0.25)
const COL_AMBER := Color(0.95, 0.75, 0.15)
const COL_RED   := Color(0.90, 0.18, 0.18)
const COL_BLUE  := Color(0.32, 0.58, 0.96)
const COL_ENEMY := Color(0.93, 0.28, 0.28)

var _player_base = null   # base.gd; untyped for cross-script duck typing
var _enemy_base = null
var _t: float = 0.0
var _p: Dictionary = {}   # widget refs for the player bar
var _e: Dictionary = {}   # widget refs for the enemy bar


# Called by the battle manager BEFORE add_child().
func bind(player_base, enemy_base) -> void:
	_player_base = player_base
	_enemy_base = enemy_base


func _ready() -> void:
	_p = _build_bar("YOUR HOUSE", COL_BLUE, true)
	_e = _build_bar("ENEMY HOUSE", COL_ENEMY, false)


func _process(delta: float) -> void:
	_t += delta
	_update(_p, _player_base)
	_update(_e, _enemy_base)


func _update(refs: Dictionary, base) -> void:
	if refs.is_empty() or not is_instance_valid(base):
		return
	var fill = refs["fill"]
	var hp_lbl = refs["hp"]
	var holder = refs["holder"]
	var style = refs["style"]
	var accent: Color = refs["accent"]

	var maxhp := float(base.max_hp)
	var alive := bool(base.alive)
	var frac := 0.0
	if maxhp > 0.0:
		frac = clampf(float(base.hp) / maxhp, 0.0, 1.0)

	# Fill drains from the right by shrinking its right anchor.
	fill.anchor_right = frac
	fill.offset_right = 0.0

	if not alive:
		hp_lbl.text = "DESTROYED"
		holder.scale = Vector2.ONE
		fill.color = COL_RED.darkened(0.35)
		style.border_color = accent
		return

	hp_lbl.text = "%d / %d" % [int(ceil(maxf(0.0, float(base.hp)))), int(maxhp)]

	var col := _ramp(frac)
	if frac > 0.0 and frac < DANGER_FRAC:
		var freq := lerpf(8.0, 20.0, 1.0 - frac / DANGER_FRAC)
		var pulse := 0.5 + 0.5 * sin(_t * freq)
		col = col.lerp(Color.WHITE, pulse * 0.65)
		var s := 1.0 + pulse * 0.08
		holder.scale = Vector2(s, s)
		style.border_color = accent.lerp(Color.WHITE, pulse)
	else:
		holder.scale = Vector2.ONE
		style.border_color = accent
	fill.color = col


func _ramp(frac: float) -> Color:
	if frac >= 0.5:
		return COL_AMBER.lerp(COL_GREEN, (frac - 0.5) * 2.0)
	return COL_RED.lerp(COL_AMBER, frac * 2.0)


# ===========================================================================
# UI construction
# ===========================================================================
func _build_bar(title: String, accent: Color, left_side: bool) -> Dictionary:
	# Holder pinned to a top screen corner; we scale this whole node to pulse.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.pivot_offset = Vector2(BAR_W * 0.5, PANEL_H * 0.5)
	# Both bars ride the top of the screen at the same height; left_side picks the corner.
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	holder.offset_top = MARGIN
	holder.offset_bottom = MARGIN + PANEL_H
	if left_side:
		holder.anchor_left = 0.0
		holder.anchor_right = 0.0
		holder.offset_left = MARGIN
		holder.offset_right = MARGIN + BAR_W
	else:
		holder.anchor_left = 1.0
		holder.anchor_right = 1.0
		holder.offset_left = -(MARGIN + BAR_W)
		holder.offset_right = -MARGIN
	add_child(holder)

	# Framed dark panel (border is the team accent; we brighten it when pulsing).
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.11, 0.85)
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	holder.add_child(panel)

	# Title across the top of the panel.
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	title_lbl.anchor_left = 0.0
	title_lbl.anchor_right = 1.0
	title_lbl.offset_left = 14.0
	title_lbl.offset_top = 7.0
	title_lbl.offset_right = -14.0
	title_lbl.offset_bottom = 30.0
	holder.add_child(title_lbl)

	# Bar track (dark rounded background; clips the rounded fill).
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.clip_contents = true
	track.anchor_left = 0.0
	track.anchor_right = 1.0
	track.anchor_top = 1.0
	track.anchor_bottom = 1.0
	track.offset_left = 14.0
	track.offset_right = -14.0
	track.offset_top = -(BAR_H + 12.0)
	track.offset_bottom = -12.0
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	track_style.set_corner_radius_all(6)
	track.add_theme_stylebox_override("panel", track_style)
	holder.add_child(track)

	# Fill: left-anchored, drains via anchor_right.
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = COL_GREEN
	fill.anchor_left = 0.0
	fill.anchor_right = 1.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0
	track.add_child(fill)

	# HP fraction centered over the track.
	var hp_lbl := Label.new()
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_lbl.add_theme_font_size_override("font_size", 18)
	hp_lbl.add_theme_color_override("font_color", Color.WHITE)
	hp_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	hp_lbl.add_theme_constant_override("outline_size", 5)
	hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(hp_lbl)

	return {"holder": holder, "style": style, "fill": fill, "hp": hp_lbl, "accent": accent}
