extends Node
## Subtle swipe-to-pan. Dragging across the screen (touch or left-mouse) nudges
## the camera within a small rectangle and leaves it there, like dragging the
## viewport in a phone game. The clamp keeps it from ever straying far, so what
## you're looking at only shifts a little.
##
## Created from code by the battle manager; bind(camera) BEFORE add_child().
## The camera never rotates, so we capture its screen-plane axes once and only
## ever slide along them.

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
	if _cam == null or not _enabled:
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
