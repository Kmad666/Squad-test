extends RefCounted
## MODEL VIEWER: every variant of the universal soldier on a slow turntable,
## in daylight, so the model can be judged up close. Your squad stands behind
## the line-up (walk around them with WASD, zoom with the wheel). No enemies.

const SoldierModel = preload("res://scripts/soldier_model.gd")
const UI_FONT = preload("res://fonts/ShareTechMono-Regular.ttf")

const NAME := "MODEL VIEWER"
const NIGHT := false
const GROUND := "field"
const START := Vector3(0, 0, 9)
const AT_TEAM := Vector3(40, 0, 44)
const OBJECTIVE := "MODEL VIEWER  -  UNIVERSAL SOLDIER, IDLE POSE  -  M FOR NEXT MAP"
const COMPLETE := ""
const BOXES := []
const AREAS := []

## [label, role, side, sergeant, crouched, signal]
const LINEUP := [
	["RIFLEMAN", "rifleman", "friendly", false, false, ""],
	["SERGEANT", "rifleman", "friendly", true, false, ""],
	["GRENADIER", "grenadier", "friendly", false, false, ""],
	["ROCKETMAN", "anti_armor", "friendly", false, false, ""],
	["ENEMY RIFLEMAN", "rifleman", "enemy", false, false, ""],
	["CROUCHED", "rifleman", "friendly", false, true, ""],
	["SIGNALS (LOOP)", "rifleman", "friendly", true, false, "loop"],
]


static func build_extras(main: Node3D) -> void:
	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = Color(0.32, 0.32, 0.3)
	for i in LINEUP.size():
		var e: Array = LINEUP[i]
		var x := (float(i) - float(LINEUP.size() - 1) * 0.5) * 2.6
		var base := Vector3(x, 0, 0)

		var plinth := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7
		cm.bottom_radius = 0.75
		cm.height = 0.06
		plinth.mesh = cm
		plinth.material_override = plinth_mat
		plinth.position = base + Vector3(0, 0.03, 0)
		main.add_child(plinth)

		var turntable := Node3D.new()
		turntable.position = base + Vector3(0, 0.06, 0)
		turntable.rotation.y = PI      # start facing the camera
		main.add_child(turntable)
		var m: Node3D = SoldierModel.new()
		turntable.add_child(m)
		m.build(e[1], e[2], i)
		if e[3]:
			m.set_sergeant(true)
		if e[4]:
			m.set_crouch(true)
		var tw := turntable.create_tween().set_loops()
		tw.tween_property(turntable, "rotation:y", PI + TAU, 14.0).from(PI)
		if e[5] == "loop":
			var sig := m.create_tween().set_loops()
			for kind in ["move", "halt", "cover", "fire"]:
				sig.tween_callback(m.gesture.bind(kind, 0.0))
				sig.tween_interval(2.0)

		var label := Label3D.new()
		label.font = UI_FONT
		label.font_size = 36
		label.outline_size = 8
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.45, 1.0, 0.3)
		label.outline_modulate = Color(0, 0.08, 0, 0.8)
		label.text = e[0]
		label.position = base + Vector3(0, 2.35, 0)
		main.add_child(label)
