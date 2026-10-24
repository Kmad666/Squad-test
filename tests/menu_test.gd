extends SceneTree
## Level select: it builds every card, and each key 1-4 deploys onto the
## right map (checked by loading the game scene it switches to).

var menu
var f := 0
var key := 0
var fails := 0
const WANT := [3, 0, 1, 2]     # keys 1-4 -> main.MAPS index


func _initialize() -> void:
	_open()


func _open() -> void:
	menu = load("res://menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu


func _process(_d) -> bool:
	f += 1
	if f % 30 == 10 and key < 4:
		if f == 10:
			for idx in WANT:
				if menu.find_child("Map%d" % idx, true, false) == null:
					fails += 1
					print("FAIL no card for map ", idx)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_1 + key
		ev.pressed = true
		Input.parse_input_event(ev)
	if f % 30 == 25 and key < 4:
		var main = current_scene
		var ok: bool = main != null and main.has_method("toggle_retro") and main.map_index == WANT[key]
		print("key %d -> %s" % [key + 1, main.map.NAME if ok else "WRONG"])
		if not ok:
			fails += 1
			print("FAIL key %d did not deploy map %d" % [key + 1, WANT[key]])
		if main:
			main.queue_free()
		load("res://scripts/main.gd").picked_map = -1
		key += 1
		_open()
	if key >= 4:
		print("menu test failures: ", fails)
		quit(1 if fails > 0 else 0)
	return false
