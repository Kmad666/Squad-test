extends Node3D
## Third-person orbit camera that follows the squad's anchor point.
## Click to grab the mouse, Esc to release, wheel to zoom.

var target: Node3D
var yaw := 0.0
var pitch := -0.5
var dist := 12.0

var _arm: SpringArm3D
var _cam: Camera3D
var _snapped := false


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.3
	_arm.spring_length = dist
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	_arm.shape = probe
	add_child(_arm)

	_cam = Camera3D.new()
	_cam.fov = 65.0
	_cam.far = 400.0
	_arm.add_child(_cam)
	_cam.current = true


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if not captured:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				dist = clampf(dist - 1.0, 5.0, 24.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				dist = clampf(dist + 1.0, 5.0, 24.0)
	elif event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * 0.0035
		pitch = clampf(pitch - event.relative.y * 0.0035, -1.25, -0.08)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null:
		return
	var focus: Vector3 = target.get_focus() + Vector3(0, 1.3, 0)
	if not _snapped:
		global_position = focus
		_snapped = true
	else:
		global_position = global_position.lerp(focus, 1.0 - exp(-8.0 * delta))
	rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = lerpf(_arm.spring_length, dist, clampf(10.0 * delta, 0.0, 1.0))


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
