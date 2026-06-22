extends Control
## One Clash-Royale-style spawn card: a textured button with a "ready" glow halo
## behind it, press-pop / can't-afford-wiggle juice, optional cost-drop pips, and
## an affordability pulse driven by the shared elixir economy.
##
## Self-contained: the battle manager builds one card per spawnable unit. ALL
## gameplay (base check, afford test, spend, spawn) lives in the `on_press`
## callback the manager supplies — this node only renders feedback. The callback
## returns one of the result codes below and the card plays the matching juice.

const PAD := 20.0   # glow-halo padding around the button, in px

# Press result codes the manager's on_press callback returns.
enum { IGNORED = 0, SPAWNED = 1, REJECTED = 2 }

var _cost: float = 1.0
var _elixir = null                 # elixir model (res://scripts/elixir.gd); untyped for duck typing
var _controller = null             # deploy_controller.gd — handles the drag-to-deploy
var _unit_def: Dictionary = {}     # { glb, scale, spawn_fn } handed to the controller on press

var _btn: TextureButton = null
var _glow: Panel = null
var _glow_tween: Tween = null
var _affordable: bool = false
var _afford_inited: bool = false

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

func _build(button_size: float, texture: Texture2D, drop_count: int, drop_texture: Texture2D) -> void:
	# Soft "ready" glow halo behind the button (card rect + PAD), pulsed by afford.
	_glow = Panel.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.offset_left = -PAD
	_glow.offset_top = -PAD
	_glow.offset_right = PAD
	_glow.offset_bottom = PAD
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(1, 1, 1, 1)   # actual colour comes from self_modulate
	glow_style.set_corner_radius_all(int((button_size + 2.0 * PAD) * 0.5))
	_glow.add_theme_stylebox_override("panel", glow_style)
	_glow.self_modulate = Color(1.0, 0.85, 0.35)
	_glow.modulate.a = 0.0
	add_child(_glow)

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
	if _controller == null:
		return
	if _controller.begin(self, _cost, _unit_def):
		press_pop()          # immediate flash the moment the press lands
	else:
		reject_wiggle()

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

# Recolour + pulse the glow to signal whether THIS card is affordable right now.
func _set_affordable(can: bool) -> void:
	if _afford_inited and can == _affordable:
		return
	_afford_inited = true
	_affordable = can
	if _glow == null:
		return
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	if can:
		_glow.self_modulate = Color(1.0, 0.85, 0.35)   # warm gold = ready
		_glow_tween = create_tween().set_loops()
		_glow_tween.tween_property(_glow, "modulate:a", 0.6, 0.6).set_trans(Tween.TRANS_SINE)
		_glow_tween.tween_property(_glow, "modulate:a", 0.18, 0.6).set_trans(Tween.TRANS_SINE)
	else:
		_glow.self_modulate = Color(0.6, 0.6, 0.65)     # dull = can't afford
		_glow.modulate.a = 0.0
