extends Control
class_name TouchJoystick

## On-screen movement stick for mobile. Drag anywhere inside it (finger or,
## for testing in the editor, the mouse) and `output` tracks the direction
## and strength of the drag, roughly -1..1 on each axis, snapping back to
## zero when released.

@export var base_radius: float = 70.0
@export var knob_radius: float = 32.0
@export var dead_zone: float = 0.15

var output: Vector2 = Vector2.ZERO

var _touch_index: int = -1
var _knob_offset: Vector2 = Vector2.ZERO

const MOUSE_TOUCH_INDEX := -2


func _ready() -> void:
	custom_minimum_size = Vector2(base_radius, base_radius) * 2.0


func _draw() -> void:
	var center: Vector2 = size / 2.0
	draw_circle(center, base_radius, Color(1, 1, 1, 0.15))
	draw_circle(center, base_radius, Color(1, 1, 1, 0.35), false, 3.0)
	draw_circle(center + _knob_offset, knob_radius, Color(1, 1, 1, 0.55))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_knob(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(MOUSE_TOUCH_INDEX, event.position, event.pressed)
	elif event is InputEventMouseMotion and _touch_index == MOUSE_TOUCH_INDEX:
		_update_knob(event.position)


func _handle_touch(index: int, screen_position: Vector2, pressed: bool) -> void:
	if pressed:
		if _touch_index != -1:
			return
		var local_position: Vector2 = screen_position - global_position
		if local_position.distance_to(size / 2.0) <= base_radius * 1.4:
			_touch_index = index
			_update_knob(screen_position)
	else:
		if index == _touch_index:
			_touch_index = -1
			_knob_offset = Vector2.ZERO
			output = Vector2.ZERO
			queue_redraw()


func _update_knob(screen_position: Vector2) -> void:
	var local_position: Vector2 = screen_position - global_position
	var center: Vector2 = size / 2.0
	var delta: Vector2 = local_position - center
	var distance: float = delta.length()

	if distance > base_radius:
		delta = delta.normalized() * base_radius
		distance = base_radius

	_knob_offset = delta

	var magnitude: float = distance / base_radius
	if magnitude < dead_zone:
		output = Vector2.ZERO
	else:
		output = delta / base_radius

	queue_redraw()
