extends SceneTree
## Esc opens the field manual (pauses), RIGHT pages tabs, Esc closes (unpauses).
var main
var f := 0
func _initialize():
	load("res://scripts/main.gd").forced_map = 0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d):
	f += 1
	if f == 10:
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_ESCAPE; ev.pressed = true
		Input.parse_input_event(ev)
	if f == 20:
		print("after ESC: open=", main.manual.is_open, " paused=", paused, " pages=", main.manual.page_count())
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_RIGHT; ev.pressed = true
		Input.parse_input_event(ev)
	if f == 30:
		print("tab after RIGHT: ", main.manual._tabs.current_tab, " (", main.manual._tabs.get_tab_title(main.manual._tabs.current_tab), ")")
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_ESCAPE; ev.pressed = true
		Input.parse_input_event(ev)
	if f == 40:
		print("after 2nd ESC: open=", main.manual.is_open, " paused=", paused)
		quit()
	return false
