extends Node3D
## An enemy weapon mount, attached to a dummy or the APC at its muzzle.
## Picks a soldier it can see, waits a reaction beat, then fires bursts
## (bullets) or shells. Incoming fire suppresses it: it shoots slower and
## worse, and when pinned it stops shooting until the fire lets up.

const Weapons = preload("res://scripts/weapons.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")

var main: Node3D
var host: Node3D            # the dummy / vehicle this gun belongs to
var weapon: Dictionary
var turret: Node3D = null   # optional: swivels toward the target (APC)
var suppression := 0.0      # 0..1
var target: Node3D = null
var shots := 0
var reaction_min := 0.6     # seconds to bring the gun onto a new target
var reaction_max := 1.4
var spot_range := 45.0      # an unalerted sentry only notices you this close
var blind_t := 0.0          # flashbanged: can't see or shoot

var _rng := RandomNumberGenerator.new()
var _retarget := 0.0
var _fire_timer := 0.0
var _burst_left := 0
var _since_incoming := 99.0
var _reaction := 0.0
var _flash: MeshInstance3D
var _flash_t := 0.0


func _ready() -> void:
	_rng.randomize()
	if Atmosphere.night:
		spot_range = 35.0     # harder to spot you in the dark
	_fire_timer = _rng.randf_range(1.0, 3.0)
	_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12 if weapon["kind"] == "bullet" else 0.3
	sm.height = sm.radius * 2.0
	_flash.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.25)
	m.disable_fog = true
	_flash.material_override = m
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)


func add_suppression(amount: float) -> void:
	suppression = minf(1.0, suppression + amount)
	_since_incoming = 0.0


func blind(seconds: float) -> void:
	blind_t = maxf(blind_t, seconds)
	target = null


func pinned() -> bool:
	return suppression > 0.85


func _physics_process(delta: float) -> void:
	_since_incoming += delta
	if _since_incoming > 1.2:
		suppression = maxf(0.0, suppression - 0.22 * delta)
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash.visible = false
	if not host.alive:
		target = null
		suppression = 0.0
		return
	if blind_t > 0.0:
		blind_t -= delta
		_since_incoming = 0.0      # stays pinned while blinded
		return

	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = _rng.randf_range(0.4, 0.8)
		# Stick with the current target while it's still visible; only switch
		# when it's gone (or now and then), so the reaction delay isn't reset.
		var keep: bool = target != null and is_instance_valid(target) and not target.dead \
			and global_position.distance_to(target.global_position) <= weapon["max"] and _can_see(target) \
			and _rng.randf() > 0.1
		var t: Node3D = target if keep else _pick_target()
		if t != target:
			target = t
			_reaction = _rng.randf_range(reaction_min, reaction_max)
			if t and host.has_method("on_spotted"):
				host.on_spotted()
	if target == null or not is_instance_valid(target) or target.dead:
		target = null
		return

	if turret:
		var local: Vector3 = host.to_local(target.global_position)
		turret.rotation.y = lerp_angle(turret.rotation.y, atan2(local.x, local.z), clampf(3.0 * delta, 0.0, 1.0))

	_reaction -= delta
	if _reaction > 0.0 or pinned():
		return
	if host.has_method("can_fire") and not host.can_fire():
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	if weapon["kind"] == "bullet":
		if _burst_left <= 0:
			_burst_left = _rng.randi_range(weapon["burst_min"], weapon["burst_max"])
		_shoot()
		_burst_left -= 1
		_fire_timer = weapon["cycle"] if _burst_left > 0 else _rng.randf_range(weapon["pause_min"], weapon["pause_max"]) * (1.0 + 2.5 * suppression)
	else:
		_fire_shell()
		_fire_timer = weapon["reload"] * (1.0 + suppression)


func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var reach: float = weapon["max"]
	if "area" in host and not host.area.is_empty() and not host.area.get("alerted", false):
		reach = minf(reach, spot_range)
	for s in main.squad.soldiers:
		var d := global_position.distance_to(s.global_position)
		if d > reach or not _can_see(s):
			continue
		var score := d + _rng.randf_range(0.0, 10.0)
		if score < best_score:
			best_score = score
			best = s
	return best


## Line of sight to the part of the soldier that shows (crouched behind a
## low crate = hidden).
func _can_see(s: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, s.exposed_point(), 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == s


func _shoot() -> void:
	var from := global_position
	var c: Vector3 = target.exposed_point()
	var chance := Weapons.enemy_hit_chance(weapon, target, from.distance_to(c), suppression)
	var aim: Vector3
	if _rng.randf() < chance:
		aim = c + Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1))
	else:
		var dir := (c - from).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var off := side * _rng.randf_range(-1.0, 1.0) + Vector3.UP * _rng.randf_range(-0.4, 0.9)
		if off.length() < 0.2:
			off = side
		aim = c + off.normalized() * _rng.randf_range(0.6, 2.0)
	var to := from + (aim - from).normalized() * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var col: Object = hit["collider"]
		if col.has_method("take_damage") and col.has_method("exposed_point"):
			col.take_damage(weapon["soft"], from)
			main.spawn_impact(end, hit["normal"], false, Color(0.6, 0.05, 0.03))
		else:
			main.spawn_impact(end, hit["normal"], false)
	main.suppress_squad(from, end, weapon["suppress"])
	main.spawn_tracer(from, end, true)
	shots += 1
	_flash.visible = true
	_flash_t = 0.05


func _fire_shell() -> void:
	var from := global_position
	var c: Vector3 = target.global_position + Vector3(0, 0.6, 0)
	var chance := Weapons.enemy_hit_chance(weapon, target, from.distance_to(c), suppression)
	var to := c
	if _rng.randf() >= chance:
		var side := (c - from).cross(Vector3.UP).normalized()
		var off := side * _rng.randf_range(-1.0, 1.0) + (c - from).normalized() * _rng.randf_range(-1.0, 1.0)
		off.y = 0
		to = c + off.normalized() * _rng.randf_range(2.0, 5.0)
		to.y = 0.3
	var p: Node3D = ProjectileScript.new()
	p.hostile = true
	p.setup(main, weapon, from, to, _rng)
	main.add_child(p)
	shots += 1
	_flash.visible = true
	_flash_t = 0.08
	main.on_enemy_cannon(from)
