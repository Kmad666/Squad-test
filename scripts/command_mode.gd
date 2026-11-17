extends Node3D
## Command mode: Tab frees the mouse and the camera lifts for an overview;
## the game keeps running in real time.
##   LMB on a man          select him (SHIFT: add / remove)
##   LMB drag              box-select
##   LMB on empty ground   clear the selection: orders go to the whole team
##   RMB on the ground     nothing selected: the team moves there (like E);
##                         men selected: they leave the formation and hold
##                         that spot (cover there if any, else flat if a fight
##                         is on) until they rejoin
##   RMB on an enemy       mark him: everybody concentrates on him
##   RMB drag              pan the camera (as before)
##   WASD                  move the camera, not the squad
##   U                     rejoin: the selected detached men, or all of them
## The move preview orbs follow the cursor (and the selection).

const PICK_PX := 30.0           # a click this close to a man (on screen) picks him
const DRAG_PX := 8.0            # the mouse moving further than this with LMB down: a box

var main: Node3D
var selection: Array = []
var _press: Variant = null       # where LMB went down (screen), while held
var _box: ColorRect
var _hint: Label
var _rings: Array = []           # selection rings under the selected men
var _tags: Array = []            # markers over the detached men
var _ring_mat: StandardMaterial3D
var _tag_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	_ring_mat = _mat(Color(0.45, 1.0, 0.35, 0.75))
	_tag_mat = _mat(Color(1.0, 0.72, 0.22, 0.85))
	_build_box.call_deferred()            # the HUD may not be built yet


func _build_box() -> void:
	_box = ColorRect.new()
	_box.color = Color(0.45, 1.0, 0.35, 0.12)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	var edge := ReferenceRect.new()
	edge.border_color = Color(0.45, 1.0, 0.35, 0.8)
	edge.border_width = 1.5
	edge.editor_only = false
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.add_child(edge)
	main.ui_root.add_child(_box)
	# The controls, while in command mode: a strip above the specials bar.
	_hint = Label.new()
	_hint.text = "LMB select / drag box    RMB move / mark    WASD camera    U rejoin    TAB aim"
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.55, 1.0, 0.45))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -78
	_hint.offset_bottom = -56
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	main.ui_root.add_child(_hint)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = c
	m.render_priority = 3
	return m


func active() -> bool:
	return main.cam_rig != null and main.cam_rig.free_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


## The selection as orders see it: [] means "the team". A selection that is
## exactly a whole team (nobody detached in it) is that team too.
func selected_men() -> Array:
	selection = selection.filter(func(s): return is_instance_valid(s) and main.squad.soldiers.has(s))
	if selection.is_empty():
		return []
	var sq = main.squad
	for t in 2:
		var team: Array = sq.team_members(t)
		if not team.is_empty() and team.size() == selection.size() and team.all(func(s): return selection.has(s)):
			return []
	return selection


## The team a whole-team selection means (or the one you command).
func _selected_team() -> int:
	var sq = main.squad
	if not selection.is_empty() and sq.split:
		return selection[0].team
	return sq.active


# ---------------------------------------------------------------- picking

## The ground under a screen point (a roof or a wall: the ground below it).
func ground_at(pos: Vector2) -> Variant:
	var cam: Camera3D = main.cam_rig.cam
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0, 1)
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["position"].y < 0.6:
		return Vector3(hit["position"].x, 0, hit["position"].z)
	if dir.y > -0.01:
		return null                    # sky
	var p: Vector3 = from + dir * (-from.y / dir.y)    # over a roof: the ground below (orders push it out of the building)
	return Vector3(p.x, 0, p.z)


func _on_screen(p: Vector3) -> Variant:
	var cam: Camera3D = main.cam_rig.cam
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


func _nearest(list: Array, pos: Vector2, height: float) -> Node3D:
	var best: Node3D = null
	var bd := PICK_PX
	for n in list:
		var sp: Variant = _on_screen(n.global_position + Vector3(0, height, 0))
		if sp == null:
			continue
		var d: float = (sp as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = n
	return best


func man_at(pos: Vector2) -> Node3D:
	return _nearest(main.squad.soldiers, pos, 1.0)


func enemy_at(pos: Vector2) -> Node3D:
	return _nearest(main.targets.filter(func(t): return t.alive), pos, 1.0)


## The move preview's aim point in command mode: the ground under the cursor,
## unless the cursor is on an enemy (a click there marks him, not a move).
func hover_point() -> Variant:
	var pos := main.get_viewport().get_mouse_position()
	if enemy_at(pos) != null or _press != null:
		return null
	return ground_at(pos)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not active():
		if _press != null:
			_press = null
			if _box:
				_box.visible = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = event.position
		elif _press != null:
			var from: Vector2 = _press
			_press = null
			_box.visible = false
			if from.distance_to(event.position) > DRAG_PX:
				_box_select(Rect2(from, Vector2.ZERO).expand(event.position), event.shift_pressed)
			else:
				_click_select(event.position, event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _press != null:
		var r := Rect2(_press, Vector2.ZERO).expand(event.position)
		_box.visible = r.size.length() > DRAG_PX
		_box.position = r.position
		_box.size = r.size
	elif event.is_action_pressed("rejoin"):
		rejoin_selected()
		get_viewport().set_input_as_handled()


func _click_select(pos: Vector2, add: bool) -> void:
	var m := man_at(pos)
	if m == null:
		if not add:
			selection = []
		return
	if add:
		if selection.has(m):
			selection.erase(m)
		else:
			selection.append(m)
	else:
		selection = [m]


func _box_select(r: Rect2, add: bool) -> void:
	if not add:
		selection = []
	for s in main.squad.soldiers:
		var sp: Variant = _on_screen(s.global_position + Vector3(0, 1.0, 0))
		if sp != null and r.has_point(sp) and not selection.has(s):
			selection.append(s)


## A short right click (the camera rig tells us; a drag is a pan).
func right_click(pos: Vector2) -> void:
	var sq = main.squad
	var e := enemy_at(pos)
	if e != null:
		sq.mark(e)
		return
	var p: Variant = ground_at(pos)
	if p == null:
		return
	var men := selected_men()
	if men.is_empty():
		var t := _selected_team()
		if t != sq.active:
			sq.switch_team()
		sq.move_to(p)
	else:
		sq.detach(men, p)


## U: the selected detached men rejoin, or (none selected) all of them.
func rejoin_selected() -> void:
	var sq = main.squad
	var men: Array = selection.filter(func(s): return is_instance_valid(s) and sq.soldiers.has(s) and s.detached)
	sq.rejoin(men)


# ---------------------------------------------------------------- markers

func _process(delta: float) -> void:
	_t += delta
	var sq = main.squad
	if sq == null:
		return
	if not active() and not selection.is_empty():
		selection = []                 # back to aiming: the selection goes
	if _hint:
		_hint.visible = active()
	var sel := selection.filter(func(s): return is_instance_valid(s) and sq.soldiers.has(s))
	_pool(_rings, sel.size(), _ring_mesh(), _ring_mat)
	for i in sel.size():
		_rings[i].global_position = sel[i].global_position + Vector3(0, 0.08, 0)
	var det: Array = sq.detached_men()
	_pool(_tags, det.size(), _tag_mesh(), _tag_mat)
	for i in det.size():
		_tags[i].global_position = det[i].global_position + Vector3(0, 2.35 + sin(_t * 2.5 + i) * 0.06, 0)
		_tags[i].rotation.y = _t * 1.5


var _rmesh: Mesh
var _tmesh: Mesh


func _ring_mesh() -> Mesh:
	if _rmesh == null:
		var m := TorusMesh.new()
		m.inner_radius = 0.55
		m.outer_radius = 0.66
		_rmesh = m
	return _rmesh


func _tag_mesh() -> Mesh:
	if _tmesh == null:
		var m := SphereMesh.new()      # a little diamond over his head (seen from any angle)
		m.radius = 0.3
		m.height = 0.75
		m.radial_segments = 4
		m.rings = 1
		_tmesh = m
	return _tmesh


func _pool(list: Array, n: int, mesh: Mesh, mat: Material) -> void:
	while list.size() < n:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		list.append(mi)
	for i in list.size():
		list[i].visible = i < n
