extends Control
## One Clash-Royale-style spawn card: a textured button with a one-time orange "tap me"
## pulse (retired on the first interaction with any card), press-pop / can't-afford-wiggle
## juice, optional cost-drop pips, and a radial affordability sweep driven by the elixir economy.
##
## Self-contained: the battle manager builds one card per spawnable unit. ALL
## gameplay (base check, afford test, spend, spawn) lives in the `on_press`
## callback the manager supplies — this node only renders feedback. The callback
## returns one of the result codes below and the card plays the matching juice.

# Radial affordability sweep: a dark overlay over the card art whose clockwise pie
# wedge clears from 12 o'clock as current/cost climbs (0 = fully dark, 1 = clear).
# canvas_item shader, COLOR written directly (MODULATE is a compile error here).
const RADIAL_SHADER := """shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;    // current_elixir / cost
uniform float dark_alpha : hint_range(0.0, 1.0) = 0.8;  // darkness of the not-yet-earned wedge
uniform float light_alpha : hint_range(0.0, 1.0) = 0.32; // slight dim on the already-earned slice
uniform sampler2D mask_tex : hint_default_white;          // the button art; its alpha clips the sweep to the button shape
void fragment() {
	vec2 p = UV - vec2(0.5);
	float ang = atan(p.x, -p.y);          // 0 at top (12 o'clock), grows clockwise
	if (ang < 0.0) { ang += 6.2831853; }  // wrap to [0, TAU)
	float frac = ang / 6.2831853;         // 0..1 clockwise from the top
	float dark = step(progress, frac);    // 1 where the wedge hasn't reached yet, else 0
	float a = mix(light_alpha, dark_alpha, dark);  // earned slice: light dim; rest: darker
	float mask = texture(mask_tex, UV).a;  // 0 in the transparent corners outside the squircle
	COLOR = vec4(0.0, 0.0, 0.0, a * mask);
}"""

# Press result codes the manager's on_press callback returns.
enum { IGNORED = 0, SPAWNED = 1, REJECTED = 2 }

var _cost: float = 1.0
var _elixir = null                 # elixir model (res://scripts/elixir.gd); untyped for duck typing
var _controller = null             # deploy_controller.gd — handles the drag-to-deploy
var _unit_def: Dictionary = {}     # { glb, scale, spawn_fn } handed to the controller on press

var _btn: TextureButton = null
var _hint_tween: Tween = null      # looping orange "tap me" pulse on the button
var _hint_done: bool = false       # latched once the player engages any card; the pulse never returns
var _affordable: bool = false
var _afford_inited: bool = false
var _radial: ColorRect = null      # dark radial "cooldown" sweep over the art (RADIAL_SHADER)

# button_size: square button edge (px). drop_count: cost pips to overlay in the
# top-right (0 = none). controller: deploy_controller.gd. unit_def: { glb, scale,
# spawn_fn } describing what this card deploys (drives the ghost + the spawn).
func setup(button_size: float, texture: Texture2D, cost: float, drop_count: int,
		drop_texture: Texture2D, elixir_node, controller, unit_def: Dictionary) -> void:
	_cost = cost
	_elixir = elixir_node
	_controller = controller
	_unit_def = unit_def
	_build(button_size, texture, drop_count, drop_texture)
	if _elixir != null and _elixir.has_signal("changed"):
		_elixir.changed.connect(_on_elixir_changed)
		# Initial paint off the current economy (the card may be built mid-regen).
		_set_affordable(_elixir.current >= _cost)
		_update_radial(_elixir.current)

func _build(button_size: float, texture: Texture2D, drop_count: int, drop_texture: Texture2D) -> void:
	# The button fills the card rect; scale/rotate from its centre for the juice.
	_btn = TextureButton.new()
	if texture != null:
		_btn.texture_normal = texture
	_btn.ignore_texture_size = true
	_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_btn.pivot_offset = Vector2(button_size * 0.5, button_size * 0.5)
	_btn.keep_pressed_outside = true   # keep the press alive while dragging onto the field
	_btn.button_down.connect(_on_down)
	_btn.button_up.connect(_on_up)
	add_child(_btn)
	_start_hint_pulse()   # gentle orange "tap me" pulse until the first interaction

	# Radial affordability sweep over the art. Sits above the button, below the cost
	# pips (added next), and ignores the mouse so the button still receives presses.
	_radial = ColorRect.new()
	_radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radial.color = Color(0, 0, 0, 0)   # irrelevant — the shader writes COLOR directly
	var rsh := Shader.new()
	rsh.code = RADIAL_SHADER
	var rmat := ShaderMaterial.new()
	rmat.shader = rsh
	rmat.set_shader_parameter("progress", 0.0)
	rmat.set_shader_parameter("mask_tex", texture)   # clip the sweep to the button's opaque shape
	_radial.material = rmat
	add_child(_radial)

	if drop_count > 0 and drop_texture != null:
		_build_drops(button_size, drop_count, drop_texture)

# Cost pips: `drop_count` elixir drops clustered at the top-right, stacking left
# and overlapping slightly so a pair reads as "2".
func _build_drops(button_size: float, drop_count: int, drop_texture: Texture2D) -> void:
	var drop_size := button_size * 0.32
	var spacing := drop_size * 0.60
	var inset := button_size * 0.04
	for i in drop_count:
		var d := TextureRect.new()
		d.texture = drop_texture
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		var right := -inset - float(i) * spacing   # measured from the right edge
		d.offset_right = right
		d.offset_left = right - drop_size
		d.offset_top = inset
		d.offset_bottom = inset + drop_size
		add_child(d)

# Press: ask the deploy controller to start a drag. If it can't (unaffordable),
# the controller plays the denied feedback and the card wiggles.
func _on_down() -> void:
	_dismiss_all_hints()   # first interaction with ANY card retires every orange pulse
	if _controller == null:
		return
	if _controller.begin(self, _cost, _unit_def):
		press_pop()          # immediate flash the moment the press lands
	else:
		reject_wiggle()

# A gentle looping orange tint on the button itself — a "tap me" hint shown until the
# player first engages a card. Drives self_modulate so it stacks cleanly with the press /
# afford pops (which drive modulate) and resets to white when retired.
func _start_hint_pulse() -> void:
	if _btn == null or _hint_done:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_btn.self_modulate = Color(1, 1, 1, 1)
	# Brighten R+G above 1.0 (and pull B down) so it pulses a bright yellow GLOW rather
	# than multiplying toward a darker tint.
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_btn, "self_modulate", Color(1.9, 1.75, 0.55, 1.0), 0.55).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_property(_btn, "self_modulate", Color(1, 1, 1, 1), 0.55).set_trans(Tween.TRANS_SINE)

# The orange pulse is a one-time hint. The moment the player presses or starts dragging
# ANY card, kill every card's pulse for the rest of the match. Cards are all siblings
# under the same CanvasLayer, so we just sweep the parent's children.
func _dismiss_all_hints() -> void:
	var parent := get_parent()
	if parent == null:
		dismiss_hint()
		return
	for c in parent.get_children():
		if c.has_method("dismiss_hint"):
			c.dismiss_hint()

# Retire this card's hint pulse permanently (stops the tween, clears the tint, and latches
# a flag so it can never restart).
func dismiss_hint() -> void:
	_hint_done = true
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	if _btn != null:
		_btn.self_modulate = Color(1, 1, 1, 1)

# Release: hand off to the controller to deploy (over field) or cancel (over card).
func _on_up() -> void:
	if _controller != null:
		_controller.release(self)

# Bounding rect of the button in screen space — the controller uses it to detect
# a cancel (the drag released back over this card).
func button_rect() -> Rect2:
	return _btn.get_global_rect() if _btn != null else Rect2()

# Pressed: a quick squish + bright flash so the press itself feels responsive
# (the bigger elastic pop happens on release in success_pop).
func press_pop() -> void:
	if _btn == null:
		return
	_btn.scale = Vector2(0.9, 0.9)
	_btn.modulate = Color(1.5, 1.5, 1.5, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_btn, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_btn, "modulate", Color(1, 1, 1, 1), 0.18)

# Spawned: elastic scale pop + bright flash back to rest.
func success_pop() -> void:
	if _btn == null:
		return
	_btn.scale = Vector2(1.35, 1.35)
	_btn.modulate = Color(1.7, 1.7, 1.7, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_btn, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_btn, "modulate", Color(1, 1, 1, 1), 0.28)

# Just became affordable: a quick grow + bright flash that says "you can afford
# this now" — a one-shot cue as the radial cooldown sweep finishes clearing.
func afford_pop() -> void:
	if _btn == null:
		return
	_btn.scale = Vector2(1.18, 1.18)
	_btn.modulate = Color(1.7, 1.7, 1.7, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_btn, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_btn, "modulate", Color(1, 1, 1, 1), 0.3)

# Can't afford / cancelled: redden + a quick rotational wiggle back to zero.
func reject_wiggle() -> void:
	if _btn == null:
		return
	_btn.modulate = Color(1.0, 0.25, 0.25, 1.0)
	var t := create_tween()
	t.tween_property(_btn, "modulate", Color(1, 1, 1, 1), 0.4)
	_btn.rotation_degrees = 0.0
	var w := create_tween()
	w.tween_property(_btn, "rotation_degrees", 11.0, 0.05)
	w.tween_property(_btn, "rotation_degrees", -11.0, 0.07)
	w.tween_property(_btn, "rotation_degrees", 7.0, 0.06)
	w.tween_property(_btn, "rotation_degrees", -7.0, 0.06)
	w.tween_property(_btn, "rotation_degrees", 0.0, 0.05)

func _on_elixir_changed(current_amount: float, _maximum: float) -> void:
	_set_affordable(current_amount >= _cost)
	_update_radial(current_amount)

# Drive the radial sweep: clear the dark wedge in proportion to current/cost, and
# drop the overlay entirely once the card is affordable (the glow signals "ready").
func _update_radial(current_amount: float) -> void:
	if _radial == null:
		return
	var progress := 0.0
	if _cost > 0.0:
		progress = clampf(current_amount / _cost, 0.0, 1.0)
	var mat := _radial.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", progress)
	_radial.visible = progress < 1.0

# Fire the one-shot "you can afford this now" pop the moment THIS card crosses into
# affordable (steady-state affordability is shown by the radial sweep, not a glow).
func _set_affordable(can: bool) -> void:
	if _afford_inited and can == _affordable:
		return
	# Just crossed into affordable mid-game (not the initial paint at game start)?
	var just_afforded := _afford_inited and can and not _affordable
	_afford_inited = true
	_affordable = can
	if just_afforded:
		afford_pop()
