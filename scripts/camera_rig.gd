extends Node3D
## Raised third-person camera. It sits high behind the squad and looks
## down-range, so the screen centre (and the reticle) is where the squad will
## be shooting, not the squad itself. The squad sits in the lower third.
## Click to grab the mouse, Esc to release, wheel to zoom.
## Tab switches between aiming (mouse grabbed) and command mode (free mouse,
## camera up over the field, WASD moves it, RMB drag pans, clicks give orders:
## command_mode.gd).
## Shake and FOV kick come from main.fire_heat (how hard the squad is firing).

const Atmosphere = preload("res://scripts/atmosphere.gd")
const PIVOT_HEIGHT := 1.9     # pivot above the squad's anchor
const INDOOR_PITCH := -1.0     # looking down into rooms (rad)
const INDOOR_DIST := 9.5
const CAM_LIFT := 1.7         # extra camera height above the pivot line
const COMMAND_PITCH := -0.9   # command mode (Tab): looking down over the field (rad)
const COMMAND_DIST := 17.0
const PAN_SPEED := 22.0       # command mode: WASD moves the camera this fast (m/s, at the usual zoom)
const CLICK_PX := 6.0         # RMB moving less than this before release: a click (an order), not a pan

var target: Node3D
var main: Node3D
var yaw := 0.0
var pitch := -0.16            # shallow: looking down-range, not down at the squad
var dist := 8.5

var cam: Camera3D
var _arm: SpringArm3D
var _snapped := false
var _shake_t := 0.0
var indoors := false          # the squad is inside a house: look down into the rooms
var _in := 0.0
var free_mouse := false       # Tab: command mode (cursor free; see command_mode.gd)
var _panning := false
var _pan_from := Vector2.ZERO
var _rmb_down := false        # RMB held in command mode, not yet a pan
var _cmd := 0.0               # 0..1 easing into the command view
var pan := Vector3.ZERO       # command mode: camera moved off the squad (WASD)


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


## Tab: aim <-> free mouse.
func toggle_aim() -> void:
	_end_pan()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		free_mouse = true
		if main and main.manual:
			main.manual.allow_release()    # not a pause
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# If the browser refuses the grab from a key press, free_mouse is
		# already off, so the next click grabs instead.
		free_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Bodies the camera arm shouldn't bump into (the LAV the squad walks behind).
func ignore(body: CollisionObject3D) -> void:
	_arm.add_excluded_object(body.get_rid())


func _end_pan() -> void:
	if not _panning:
		return
	_panning = false
	if Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(_pan_from)   # the cursor comes back where the drag started


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if free_mouse and not captured or _panning:
		# RMB: a click is an order (command mode), a drag pans.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_rmb_down = true
				_pan_from = event.position
			else:
				if _rmb_down and not _panning and main and main.command:
					main.command.right_click(event.position)
				_rmb_down = false
				_end_pan()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and _rmb_down:
			if not _panning and event.position.distance_to(_pan_from) > CLICK_PX:
				_panning = true
				if not OS.has_feature("web"):
					Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
			if _panning:
				_turn(event.relative)
			return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if not captured and not free_mouse:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					get_viewport().set_input_as_handled()   # the grabbing click doesn't fire
			MOUSE_BUTTON_WHEEL_UP:
				dist = clampf(dist - 1.0, 4.0, 20.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				dist = clampf(dist + 1.0, 4.0, 20.0)
	elif event is InputEventMouseMotion and captured:
		_turn(event.relative)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_end_pan()
		free_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _turn(rel: Vector2) -> void:
	yaw -= rel.x * 0.0035
	pitch = clampf(pitch - rel.y * 0.0035, -0.95, 0.3)


func _process(delta: float) -> void:
	if target == null:
		return
	# Command mode: WASD moves the camera over the field; back to aiming, it
	# comes back to the squad.
	if free_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		pan += get_yaw_basis() * Vector3(inp.x, 0, inp.y) * PAN_SPEED * (dist / 8.5) * delta
		var lim: float = main.nav_half if main else 200.0
		var f0: Vector3 = target.get_focus()
		pan.x = clampf(f0.x + pan.x, -lim, lim) - f0.x
		pan.z = clampf(f0.z + pan.z, -lim, lim) - f0.z
	else:
		pan = pan.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	_cmd = move_toward(_cmd, 1.0 if free_mouse else 0.0, delta * 2.5)
	var focus: Vector3 = target.get_focus() + pan + Vector3(0, PIVOT_HEIGHT, 0)
	if not _snapped:
		global_position = focus
		_snapped = true
	else:
		global_position = global_position.lerp(focus, 1.0 - exp(-8.0 * delta))
	# Indoors the camera swings up to look steeply down into the rooms (the
	# storeys above are lifted off by main) and comes in a little.
	_in = move_toward(_in, 1.0 if indoors else 0.0, delta * 2.5)
	var ease_in := smoothstep(0.0, 1.0, _in)
	var ease_cmd := smoothstep(0.0, 1.0, _cmd)
	var p := lerpf(pitch, minf(pitch, INDOOR_PITCH), ease_in)
	var d := lerpf(dist, minf(dist, INDOOR_DIST), ease_in)
	rotation = Vector3(lerpf(p, minf(p, COMMAND_PITCH), ease_cmd), yaw, 0)
	_arm.spring_length = lerpf(_arm.spring_length, lerpf(d, maxf(d * 2.0, COMMAND_DIST), ease_cmd), clampf(10.0 * delta, 0.0, 1.0))

	# Firing intensity -> rattling shake and a slight FOV punch.
	var heat: float = main.fire_heat if main else 0.0
	_shake_t += delta * 38.0
	var amp := heat * heat * 0.12
	cam.h_offset = (sin(_shake_t * 1.7) + sin(_shake_t * 3.1) * 0.5) * amp
	cam.v_offset = (cos(_shake_t * 2.3) + sin(_shake_t * 4.3) * 0.5) * amp
	cam.fov = lerpf(cam.fov, 65.0 - heat * 3.5, clampf(12.0 * delta, 0.0, 1.0))


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
