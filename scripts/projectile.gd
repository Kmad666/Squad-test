extends Node3D
## Rocket (straight, fast), enemy cannon shell (straight, fast)
## or grenade (lobbed arc, can drop over cover). Hostile projectiles hit
## soldiers; friendly ones pass through them. Explodes on contact with anything, or when its fuse runs out.
## It draws nothing of its own: in flight it is a tracer streak (main.tracers).

const GRENADE_GRAVITY := -12.0

var main: Node3D
var weapon: Dictionary
var vel := Vector3.ZERO
var direct_target: Node3D = null
var hostile := false

var _gravity := 0.0
var _life := 5.0
var _done := false
var _t := 0.0
var _wobble := Vector2.ZERO


func setup(m: Node3D, w: Dictionary, from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> void:
	main = m
	weapon = w
	position = from
	if w["kind"] in ["rocket", "shell"]:
		vel = (to - from).normalized() * float(w["speed"])
		if w["kind"] == "rocket":
			_wobble = Vector2(rng.randf_range(0.3, 0.8), rng.randf_range(7.0, 11.0))
	else:
		# Solve the launch velocity for a lob that lands on `to`.
		var flight := clampf(from.distance_to(to) / float(w["speed"]), 0.5, 2.6)
		_gravity = GRENADE_GRAVITY
		vel = (to - from - 0.5 * Vector3(0, _gravity, 0) * flight * flight) / flight
		_life = flight + 1.5


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

	var q := PhysicsRayQueryParameters3D.create(prev, next, (1 | 2) if hostile else (1 | 4))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit["collider"]
		direct_target = c as Node3D if c.has_method("take_damage") else null
		_explode(hit["position"])
		return

	global_position = next
	main.spawn_tracer(prev - step * 2.0, next, hostile, 0.09 if weapon["kind"] == "rocket" else 0.06, 0.05)
	_life -= delta
	if _life <= 0.0 or next.y < -0.5:
		_explode(next)


func _explode(at: Vector3) -> void:
	_done = true
	global_position = at
	main.spawn_explosion(at, weapon, direct_target, hostile)
	queue_free()
