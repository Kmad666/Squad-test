extends Node3D
## Rocket (straight, fast, smoke trail) or grenade (lobbed arc, can drop over
## cover). Explodes on contact with anything, or when its fuse runs out.

const GRENADE_GRAVITY := -12.0

var main: Node3D
var weapon: Dictionary
var vel := Vector3.ZERO
var direct_target: Node3D = null

var _gravity := 0.0
var _life := 5.0
var _done := false
var _body: Node3D
var _trail: CPUParticles3D
var _t := 0.0
var _wobble := Vector2.ZERO


func setup(m: Node3D, w: Dictionary, from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> void:
	main = m
	weapon = w
	position = from
	if w["kind"] == "rocket":
		vel = (to - from).normalized() * float(w["speed"])
		_wobble = Vector2(rng.randf_range(0.3, 0.8), rng.randf_range(7.0, 11.0))
	else:
		# Solve the launch velocity for a lob that lands on `to`.
		var flight := clampf(from.distance_to(to) / float(w["speed"]), 0.5, 2.6)
		_gravity = GRENADE_GRAVITY
		vel = (to - from - 0.5 * Vector3(0, _gravity, 0) * flight * flight) / flight
		_life = flight + 1.5


func _ready() -> void:
	var rocket: bool = weapon["kind"] == "rocket"
	_body = Node3D.new()
	add_child(_body)

	var shell := MeshInstance3D.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.17, 0.12)
	dark.roughness = 0.3
	if rocket:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.06
		cm.height = 0.55
		shell.mesh = cm
		shell.rotation.x = PI / 2.0
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		shell.mesh = sm
	shell.material_override = dark
	_body.add_child(shell)

	# Hot glowing exhaust / fuse that blooms.
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.09 if rocket else 0.04
	gm.height = gm.radius * 2.0
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1.0, 0.75, 0.35) if rocket else Color(1.0, 0.35, 0.15)
	gmat.disable_fog = true
	glow.material_override = gmat
	glow.position = Vector3(0, 0, 0.3) if rocket else Vector3.ZERO
	_body.add_child(glow)

	_trail = CPUParticles3D.new()
	_trail.amount = 70 if rocket else 24
	_trail.lifetime = 1.2 if rocket else 0.5
	_trail.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35) if rocket else Vector2(0.12, 0.12)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tm.vertex_color_use_as_albedo = true
	q.material = tm
	_trail.mesh = q
	_trail.color = Color(0.55, 0.55, 0.55, 0.35) if rocket else Color(0.6, 0.6, 0.6, 0.25)
	_trail.direction = Vector3.UP
	_trail.spread = 180.0
	_trail.initial_velocity_min = 0.1
	_trail.initial_velocity_max = 0.5
	_trail.gravity = Vector3(0, 0.4, 0)
	_trail.scale_amount_min = 0.6
	_trail.scale_amount_max = 1.8
	_trail.position = Vector3(0, 0, 0.35) if rocket else Vector3.ZERO
	_body.add_child(_trail)
	_trail.emitting = true


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var prev := global_position
	vel.y += _gravity * delta
	var step := vel * delta
	if weapon["kind"] == "rocket":
		# Slight corkscrew wobble so it looks unguided.
		var side := vel.cross(Vector3.UP).normalized()
		step += side * sin(_t * _wobble.y) * _wobble.x * delta + Vector3.UP * cos(_t * _wobble.y * 0.8) * _wobble.x * 0.5 * delta
	var next := prev + step

	var q := PhysicsRayQueryParameters3D.create(prev, next, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit["collider"]
		direct_target = c as Node3D if c.has_method("take_damage") else null
		_explode(hit["position"])
		return

	global_position = next
	if step.length() > 0.001:
		_body.look_at(next + step, Vector3.UP if absf(step.normalized().y) < 0.98 else Vector3.RIGHT)
	_life -= delta
	if _life <= 0.0 or next.y < -0.5:
		_explode(next)


func _explode(at: Vector3) -> void:
	_done = true
	global_position = at
	main.spawn_explosion(at, weapon, direct_target)
	for c in _body.get_children():
		if c != _trail:
			c.visible = false
	_trail.emitting = false
	get_tree().create_timer(1.5).timeout.connect(queue_free)
