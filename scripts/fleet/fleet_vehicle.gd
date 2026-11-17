extends Node3D
## One armored vehicle of the fleet (fleet_main.gd drives it): a hull that
## drives to its place in the formation over the hills, sitting on the
## ground and tilting with it, and a turret that turns its 125mm gun (and the
## coaxial machine gun beside it) onto the aim point. A mortar tube on the
## rear deck lobs rounds over the hills (it needs no turret: the arc aims it).

static var MORTAR_RELOAD := 8.0       # s between mortar rounds

const HULL := Vector3(3.4, 1.4, 6.6)
const TURRET := Vector3(2.4, 0.85, 2.9)
static var MAX_SPEED := 14.0         # m/s
static var ACCEL := 9.0
const HULL_TURN := 1.6          # rad/s
static var TURRET_TURN := 1.4        # rad/s
const GUN_ELEV := 0.6           # rad/s
static var MAIN_RELOAD := 4.0        # s between main gun shots
static var MG_RATE := 0.09           # s between machine gun rounds
const ON_TARGET := 0.06         # rad: turret this close to the aim point fires

var fleet: Node3D               # fleet_main
var index := 0
var slot := Vector3.ZERO        # place in the formation (fleet space: -Z ahead)
var vel := Vector3.ZERO
var hull_yaw := 0.0
var turret_yaw := 0.0           # relative to the hull
var gun_pitch := 0.0
var reload := 0.0               # 125mm: seconds until loaded
var mortar_reload := 0.0        # mortar: seconds until ready
var shots_mortar := 0
var mortar_tip: Node3D          # where mortar rounds leave the tube
var mg_t := 0.0
var shots_main := 0
var shots_mg := 0

var _body: Node3D               # hull + turret, tilted with the ground
var _turret: Node3D
var _gun: Node3D                # elevates
var muzzle: Node3D              # main gun
var mg_muzzle: Node3D           # coaxial machine gun


func build(col: Color) -> void:
	_body = Node3D.new()
	add_child(_body)
	_box(_body, HULL, Vector3(0, HULL.y / 2.0 + 0.35, 0), col)
	_box(_body, Vector3(HULL.x + 0.3, 0.7, HULL.z - 0.6), Vector3(0, 0.35, 0), col.darkened(0.55))   # tracks
	_box(_body, Vector3(HULL.x - 0.4, 0.3, 1.2), Vector3(0, HULL.y + 0.2, -HULL.z / 2.0 + 0.7), col.darkened(0.15))   # glacis
	_turret = Node3D.new()
	_turret.position = Vector3(0, HULL.y + 0.35, 0.4)
	_body.add_child(_turret)
	_box(_turret, TURRET, Vector3(0, TURRET.y / 2.0, 0), col.lightened(0.08))
	_box(_turret, Vector3(0.7, 0.35, 0.7), Vector3(0.55, TURRET.y + 0.17, 0.5), col.darkened(0.2))   # hatch
	_gun = Node3D.new()
	_gun.position = Vector3(0, TURRET.y * 0.5, -TURRET.z / 2.0)
	_turret.add_child(_gun)
	_box(_gun, Vector3(0.24, 0.24, 4.2), Vector3(0, 0, -2.1), Color(0.12, 0.13, 0.11))
	_box(_gun, Vector3(0.4, 0.4, 0.5), Vector3(0, 0, -4.1), Color(0.1, 0.1, 0.09))     # muzzle brake
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -4.4)
	_gun.add_child(muzzle)
	_box(_gun, Vector3(0.09, 0.09, 1.0), Vector3(0.42, 0.05, -0.4), Color(0.05, 0.05, 0.05))   # coax MG
	mg_muzzle = Node3D.new()
	mg_muzzle.position = Vector3(0.42, 0.05, -0.95)
	_gun.add_child(mg_muzzle)
	# Mortar: a stubby tube on the rear deck, tilted up and forward.
	var tube := Node3D.new()
	tube.position = Vector3(-0.9, HULL.y + 0.55, HULL.z / 2.0 - 0.9)
	tube.rotation.x = 1.05
	_body.add_child(tube)
	_box(tube, Vector3(0.62, 0.62, 0.35), Vector3(0, 0, 0.35), col.darkened(0.35))           # base
	_box(tube, Vector3(0.36, 0.36, 1.5), Vector3(0, 0, -0.5), Color(0.14, 0.15, 0.12))      # tube
	mortar_tip = Node3D.new()
	mortar_tip.position = Vector3(0, 0, -1.3)
	tube.add_child(mortar_tip)


func _box(parent: Node3D, size: Vector3, at: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi


## Drive toward `goal` (world, on the ground), aim at `aim` (world).
func drive(goal: Vector3, aim: Vector3, delta: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	var want := Vector3.ZERO
	if dist > 0.8:
		want = to.normalized() * minf(maxf(MAX_SPEED, fleet.SPEED * 1.15), dist * 2.5)   # always able to keep up
	# Keep clear of the other vehicles.
	for v in fleet.vehicles:
		if v == self:
			continue
		var d: Vector3 = global_position - v.global_position
		d.y = 0.0
		if d.length() < 8.0 and d.length() > 0.01:
			want += d.normalized() * (8.0 - d.length()) * 1.5
	vel = vel.move_toward(want, ACCEL * delta)
	var p := global_position + vel * delta
	p = fleet.keep_out_of_target(p, 5.0)
	p.x = clampf(p.x, -fleet.HALF + 10.0, fleet.HALF - 10.0)
	p.z = clampf(p.z, -fleet.HALF + 10.0, fleet.HALF - 10.0)
	p.y = fleet.height(p.x, p.z)
	global_position = p
	# Hull turns toward where it's driving (a tank turns, it doesn't slide).
	if vel.length() > 1.0:
		var face := atan2(-vel.x, -vel.z)
		hull_yaw += clampf(wrapf(face - hull_yaw, -PI, PI), -HULL_TURN * delta, HULL_TURN * delta)
	# Sit on the ground: tilt with the slope under the hull.
	var n: Vector3 = fleet.normal(p.x, p.z)
	var yb := Basis(Vector3.UP, hull_yaw)
	var fwd := -yb.z
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	_body.global_basis = Basis(right, n, -fwd)
	# Turret and gun onto the aim point.
	var tw: Transform3D = _turret.global_transform
	var local := tw.affine_inverse() * aim
	var yaw_err := atan2(-local.x, -local.z)
	turret_yaw += clampf(yaw_err, -TURRET_TURN * delta, TURRET_TURN * delta)
	_turret.rotation.y = turret_yaw
	var gl: Vector3 = _gun.global_transform.affine_inverse() * aim
	var want_pitch := clampf(gun_pitch + atan2(gl.y, -gl.z), -0.15, 0.35)
	gun_pitch = move_toward(gun_pitch, want_pitch, GUN_ELEV * delta)
	_gun.rotation.x = gun_pitch
	reload = maxf(0.0, reload - delta)
	mortar_reload = maxf(0.0, mortar_reload - delta)
	mg_t = maxf(0.0, mg_t - delta)


## How far (rad) the main gun points off the aim point.
func aim_error(aim: Vector3) -> float:
	var dir: Vector3 = -_gun.global_basis.z
	return dir.angle_to(aim - muzzle.global_position)


func gun_dir() -> Vector3:
	return -_gun.global_basis.z.normalized()
