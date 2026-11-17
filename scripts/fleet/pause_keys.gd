extends Node
## The fleet's pause screen keeps listening while the game is paused: Esc
## there resumes.

var fleet: Node


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE and fleet.is_paused():
		fleet.set_paused(false)
		get_viewport().set_input_as_handled()
