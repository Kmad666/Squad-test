extends RefCounted
## Going to another level from anywhere (the level select menu, the Esc
## pause menu in an operation, the fleet's pause screen), and the list of
## level buttons those pause screens show.

const FLEET := 100              # menu.gd's index for the armored fleet scene


## Unpause and load level `map_index` (a main.gd map, or FLEET).
static func deploy(tree: SceneTree, map_index: int) -> void:
	tree.paused = false
	if map_index == FLEET:
		tree.change_scene_to_file("res://fleet.tscn")
		return
	load("res://scripts/main.gd").picked_map = map_index
	tree.change_scene_to_file("res://main.tscn")


static func to_menu(tree: SceneTree) -> void:
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.change_scene_to_file("res://menu.tscn")


## A two-column grid of buttons, one per level on the level select (same
## order and numbers), each going straight there. `current` is marked.
static func build_list(tree: SceneTree, current: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	var entries: Array = load("res://scripts/menu.gd").ENTRIES
	for i in entries.size():
		var e: Array = entries[i]
		var b := Button.new()
		b.name = "Level%d" % e[0]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(440, 54)
		b.text = "[%d]  %s%s\n      %s" % [i + 1, e[1], "   (HERE NOW)" if e[0] == current else "", _short(e[3])]
		b.add_theme_font_size_override("font_size", 14)
		var idx: int = e[0]
		b.pressed.connect(func() -> void: deploy(tree, idx))
		grid.add_child(b)
	return grid


static func _short(blurb: String) -> String:
	var s := blurb.split(".")[0]
	return s if s.length() <= 52 else s.substr(0, 50) + "..."
