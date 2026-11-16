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
		# The first two tabs: this mission's briefing, then the guides.
		var t0: String = main.manual._tabs.get_tab_title(0)
		var t1: String = main.manual._tabs.get_tab_title(1)
		var brief: String = main.manual._tabs.get_child(0).get_parsed_text()
		print("tabs 0, 1: ", t0, ", ", t1)
		var bad := 0
		if t0 != "BRIEFING" or t1 != "GUIDES":
			bad += 1
			print("FAIL first tabs should be BRIEFING and GUIDES")
		if not brief.contains("ROADBLOCK".to_lower().capitalize()) and not brief.contains("Roadblock"):
			bad += 1
			print("FAIL the briefing is not this map's (LAMPLIGHTER)")
		if brief.contains("{h}") or brief.contains("[color"):
			bad += 1
			print("FAIL briefing markup left unconverted")
		main.manual.open_tab("GUIDES")
		if main.manual._tabs.current_tab != 1 or not main.manual.is_open:
			bad += 1
			print("FAIL open_tab(GUIDES)")
		main.manual.close()
		# Every map has a briefing.
		for m in main.MAPS:
			if m.get_script_constant_map().get("BRIEFING", "") == "":
				bad += 1
				print("FAIL no BRIEFING on ", m.NAME)
		# Nothing on G but the door stack (it used to toggle graphics too).
		var q: bool = main.low_quality
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_G; ev.pressed = true
		main._unhandled_key_input(ev)
		if main.low_quality != q:
			bad += 1
			print("FAIL G still toggles graphics")
		print("manual test failures: ", bad)
		quit(1 if bad > 0 else 0)
	return false
