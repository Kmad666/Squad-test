extends Node3D
## Raised third-person camera. It sits high behind the squad and looks
## down-range, so the screen centre (and the reticle) is where the squad will
## be shooting, not the squad itself. The squad sits in the lower third.
## Click to grab the mouse, Esc to release, wheel to zoom.
## Shake and FOV kick come from main.fire_heat (how hard the squad is firing).

const Atmosphere = preload("res://scripts/atmosphere.gd")
const PIVOT_HEIGHT := 1.9     # pivot above the squad's anchor
const CAM_LIFT := 1.7         # extra camera height above the pivot line

var target: Node3D
var main: Node3D
var yaw := 0.0
var pitch := -0.16            # shallow: looking down-range, not down at the squad
var dist := 8.5

var cam: Camera3D
var _arm: SpringArm3D
var _snapped := false
var _shake_t := 0.0


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.3
	_arm.spring_length = dist
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	_arm.shape = probe
	add_child(_arm)

	cam = Camera3D.new()
	cam.fov = 65.0
	cam.far = 400.0
	cam.position = Vector3(0, CAM_LIFT, 0)
	_arm.add_child(cam)
	cam.current = true

	# Dim cold fill riding with the camera so the squad reads as shapes in the dark.
	if not Atmosphere.night:
		return
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.65, 0.85)
	fill.light_energy = 0.9
	fill.omni_range = 22.0
	fill.omni_attenuation = 1.4
	fill.light_specular = 0.0   # no shiny hotspot on the wet road
	fill.position = Vector3(0, 1.0, -4.0)
	add_child(fill)


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if not captured:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				dist = clampf(dist - 1.0, 4.0, 20.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				dist = clampf(dist + 1.0, 4.0, 20.0)
	elif event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * 0.0035
		pitch = clampf(pitch - event.relative.y * 0.0035, -0.95, 0.3)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null:
		return
	var focus: Vector3 = target.get_focus() + Vector3(0, PIVOT_HEIGHT, 0)
	if not _snapped:
		global_position = focus
		_snapped = true
	else:
		global_position = global_position.lerp(focus, 1.0 - exp(-8.0 * delta))
	rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = lerpf(_arm.spring_length, dist, clampf(10.0 * delta, 0.0, 1.0))

	# Firing intensity -> rattling shake and a slight FOV punch.
	var heat: float = main.fire_heat if main else 0.0
	_shake_t += delta * 38.0
	var amp := heat * heat * 0.12
	cam.h_offset = (sin(_shake_t * 1.7) + sin(_shake_t * 3.1) * 0.5) * amp
	cam.v_offset = (cos(_shake_t * 2.3) + sin(_shake_t * 4.3) * 0.5) * amp
	cam.fov = lerpf(cam.fov, 65.0 - heat * 3.5, clampf(12.0 * delta, 0.0, 1.0))


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
