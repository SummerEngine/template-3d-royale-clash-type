extends Node
## Subtle swipe-to-pan. Dragging across the screen (touch or left-mouse) nudges
## the camera within a small rectangle and leaves it there, like dragging the
## viewport in a phone game. The clamp keeps it from ever straying far, so what
## you're looking at only shifts a little.
##
## Created from code by the battle manager; bind(camera) BEFORE add_child().
## The camera never rotates, so we capture its screen-plane axes once and only
## ever slide along them.

const PAN_ENABLED := false   # swipe-to-pan disabled for now — flip to true to restore it

@export var pan_speed: float = 0.012   # world units moved per pixel of drag
@export var max_pan_x: float = 3.0     # half-width of the allowed rectangle (camera-right axis)
@export var max_pan_y: float = 2.2     # half-height of the allowed rectangle (camera-up axis)

var _cam: Camera3D = null
var _home: Vector3
var _right: Vector3
var _up: Vector3
var _pan_x: float = 0.0
var _pan_y: float = 0.0
var _enabled: bool = true   # the deploy controller suspends panning mid-drag

# --- Trauma-based camera shake (fed by the Juice hub via add_trauma) ---
@export var trauma_decay: float = 1.6      # trauma units lost per second
@export var shake_max_offset: float = 0.55 # world-units of shake at full trauma
var _trauma: float = 0.0
var _shaking: bool = false


# Called by the battle manager BEFORE add_child().
func bind(cam: Camera3D) -> void:
	_cam = cam


# Toggled off by the deploy controller so a deploy drag doesn't also pan the camera.
func set_active(on: bool) -> void:
	_enabled = on


func _ready() -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
	if _cam == null:
		return
	_home = _cam.global_position
	# Project the screen-plane axes onto the world X-Z plane so panning slides the
	# view horizontally at a constant height (never tilts the camera up/down).
	var bx := _cam.global_transform.basis.x
	var by := _cam.global_transform.basis.y
	_right = Vector3(bx.x, 0.0, bx.z).normalized()
	_up = Vector3(by.x, 0.0, by.z).normalized()


func _unhandled_input(event: InputEvent) -> void:
	if not PAN_ENABLED or _cam == null or not _enabled:
		return
	var rel := Vector2.ZERO
	if event is InputEventScreenDrag:
		rel = event.relative
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		rel = event.relative
	else:
		return
	# Grab-the-world: drag right and the view follows your finger (camera slides
	# left); drag down and the view follows down. Clamped to the small rectangle.
	_pan_x = clampf(_pan_x - rel.x * pan_speed, -max_pan_x, max_pan_x)
	_pan_y = clampf(_pan_y + rel.y * pan_speed, -max_pan_y, max_pan_y)
	_cam.global_position = _home + _right * _pan_x + _up * _pan_y


# Called by the Juice hub on heavy hits / structure falls.
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


# Apply shake as an offset on top of the current pan position. Only drives the
# camera while shaking (and one settle frame after), so normal panning is untouched.
func _process(delta: float) -> void:
	if _cam == null:
		return
	var base := _home + _right * _pan_x + _up * _pan_y
	if _trauma > 0.0:
		_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
		var s := _trauma * _trauma   # square for a snappier falloff
		var ox := randf_range(-1.0, 1.0) * shake_max_offset * s
		var oy := randf_range(-1.0, 1.0) * shake_max_offset * s
		_cam.global_position = base + _right * ox + _up * oy
		_shaking = true
	elif _shaking:
		_cam.global_position = base   # settle exactly back onto the pan position once
		_shaking = false
