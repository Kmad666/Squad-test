extends MultiMeshInstance3D
## Tracer rounds: the one thing a shot draws. Every tracer is an instance of
## a single MultiMesh (one draw call for all of them, one shader, made once);
## a shot moves an idle instance into place for a few hundredths of a second.
## Nothing is created or freed per shot.

const COUNT := 128
const LIFE := 0.06               # s a tracer stays up
const WIDTH := 0.04              # m
const FRIENDLY := Color(1.0, 0.82, 0.4)
const ENEMY := Color(1.0, 0.25, 0.15)

var _life := PackedFloat32Array()
var _next := 0
var _active := 0
var _gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = COUNT
	for i in COUNT:
		mm.set_instance_transform(i, _gone)
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-4000, -500, -4000), Vector3(8000, 3000, 8000))   # never culled, never re-measured
	_life.resize(COUNT)


## A tracer from `from` to `to`.
func fire(from: Vector3, to: Vector3, col := FRIENDLY, width := WIDTH, life := LIFE) -> void:
	var v := to - from
	var length := v.length()
	if length < 0.05:
		return
	var b := Basis.looking_at(v, Vector3.UP if absf(v.y) < length * 0.99 else Vector3.RIGHT)
	b = Basis(b.x * width, b.y * width, b.z * length)
	var i := _next
	_next = (_next + 1) % COUNT
	if _life[i] <= 0.0:
		_active += 1
	_life[i] = life
	multimesh.set_instance_transform(i, Transform3D(b, (from + to) * 0.5))
	multimesh.set_instance_color(i, col)


## Tracers up right now (tests).
func active() -> int:
	return _active


func _process(delta: float) -> void:
	if _active == 0:
		return
	for i in COUNT:
		if _life[i] > 0.0:
			_life[i] -= delta
			if _life[i] <= 0.0:
				multimesh.set_instance_transform(i, _gone)
				_active -= 1
