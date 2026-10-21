extends StaticBody3D
## Static practice target. Flashes when hit, tips over after enough hits,
## and pops back up a few seconds later.

const MAX_HP := 8
const RESPAWN_TIME := 5.0

var main: Node3D
var alive := true
var hp := MAX_HP

var _pivot: Node3D
var _col: CollisionShape3D
var _plate: MeshInstance3D
var _plate_mat: StandardMaterial3D
var _hit_mat: StandardMaterial3D
var _flash_timer := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0

	_col = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.8, 0.35)
	_col.shape = shape
	_col.position.y = 0.9
	add_child(_col)

	_pivot = Node3D.new()
	add_child(_pivot)

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.35, 0.3, 0.25)
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = Color(0.92, 0.9, 0.85)
	_hit_mat = StandardMaterial3D.new()
	_hit_mat.albedo_color = Color(1.0, 0.25, 0.15)
	_hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.8, 0.12, 0.1)

	var base := CylinderMesh.new()
	base.top_radius = 0.35
	base.bottom_radius = 0.4
	base.height = 0.12
	_add(base, post_mat, Vector3(0, 0.06, 0))
	var post := BoxMesh.new()
	post.size = Vector3(0.1, 0.8, 0.1)
	_add(post, post_mat, Vector3(0, 0.45, 0))
	var plate := BoxMesh.new()
	plate.size = Vector3(0.56, 0.75, 0.12)
	_plate = _add(plate, _plate_mat, Vector3(0, 1.2, 0))
	var bull := CylinderMesh.new()
	bull.top_radius = 0.14
	bull.bottom_radius = 0.14
	bull.height = 0.02
	_add(bull, red, Vector3(0, 1.22, 0.07), Vector3(PI / 2, 0, 0))
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	_add(head, _plate_mat, Vector3(0, 1.75, 0))


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_pivot.add_child(mi)
	return mi


func take_hit() -> void:
	if not alive:
		return
	hp -= 1
	_plate.material_override = _hit_mat
	_flash_timer = 0.08
	if hp <= 0:
		_knock_down()


func _knock_down() -> void:
	alive = false
	_col.set_deferred("disabled", true)
	if main:
		main.on_dummy_down()
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:x", -1.45, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_interval(RESPAWN_TIME)
	tw.tween_property(_pivot, "rotation:x", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_stand_up)


func _stand_up() -> void:
	hp = MAX_HP
	alive = true
	_col.set_deferred("disabled", false)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_plate.material_override = _plate_mat
