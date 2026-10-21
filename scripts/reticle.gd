extends Control
## Large corner-bracket reticle in neon military green, styled like an analogue
## sight: soft phosphor glow and a faint flicker. Every dimension is a tunable
## parameter; with "show dimensions" on, the sizes are drawn next to it.
## Settings are saved in the browser so tweaks stick between sessions.

const SAVE_PATH := "user://reticle.cfg"
const COLOR := Color(0.45, 1.0, 0.30)

## name -> [default, min, max, step, label]
const PARAMS := {
	"width":     [360.0, 40.0, 1200.0, 2.0, "Width (px)"],
	"height":    [220.0, 40.0, 800.0, 2.0, "Height (px)"],
	"corner":    [40.0, 4.0, 200.0, 1.0, "Corner length (px)"],
	"thickness": [3.0, 1.0, 12.0, 0.5, "Line thickness (px)"],
	"offset_y":  [0.0, -300.0, 300.0, 1.0, "Vertical offset (px)"],
	"glow":      [0.5, 0.0, 1.0, 0.05, "Glow"],
	"opacity":   [0.9, 0.1, 1.0, 0.05, "Opacity"],
	"flicker":   [0.3, 0.0, 1.0, 0.05, "Flicker"],
}

var p := {}
var show_dims := true
var _t := 0.0
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	reset_defaults(false)
	_load()


func reset_defaults(save := true) -> void:
	for k in PARAMS:
		p[k] = PARAMS[k][0]
	show_dims = true
	if save:
		_save()


func set_param(key: String, value: float) -> void:
	p[key] = value
	_save()


func set_show_dims(on: bool) -> void:
	show_dims = on
	_save()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in PARAMS:
		p[k] = float(cfg.get_value("reticle", k, p[k]))
	show_dims = bool(cfg.get_value("reticle", "show_dims", show_dims))


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in PARAMS:
		cfg.set_value("reticle", k, p[k])
	cfg.set_value("reticle", "show_dims", show_dims)
	cfg.save(SAVE_PATH)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5 + Vector2(0, p["offset_y"])
	var hw: float = p["width"] * 0.5
	var hh: float = p["height"] * 0.5
	var corner: float = minf(p["corner"], minf(hw, hh))
	var th: float = p["thickness"]
	var glow: float = p["glow"]

	# Analogue phosphor flicker: two out-of-phase waves so it never looks regular.
	var wave := 0.5 + 0.5 * sin(_t * 53.0) * sin(_t * 7.3)
	var a: float = p["opacity"] * (1.0 - p["flicker"] * 0.3 * wave)

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var k := c + Vector2(sx * hw, sy * hh)
			var pts := PackedVector2Array([k + Vector2(-sx * corner, 0), k, k + Vector2(0, -sy * corner)])
			if glow > 0.0:
				for i in 3:
					draw_polyline(pts, Color(COLOR, a * 0.13 * glow), th + float(i + 1) * 4.0 * glow)
			draw_polyline(pts, Color(COLOR, a), th)

	if show_dims:
		_draw_dims(c, hw, hh, corner, th)


func _draw_dims(c: Vector2, hw: float, hh: float, corner: float, th: float) -> void:
	var dim := Color(COLOR, 0.65)
	var fs := 13
	var sw := maxf(size.x, 1.0)
	var sh := maxf(size.y, 1.0)

	# Width: dashed measuring line above the top edge with end ticks.
	var y := c.y - hh - 14.0
	draw_dashed_line(Vector2(c.x - hw, y), Vector2(c.x + hw, y), dim, 1.0, 5.0)
	draw_line(Vector2(c.x - hw, y - 4), Vector2(c.x - hw, y + 4), dim, 1.0)
	draw_line(Vector2(c.x + hw, y - 4), Vector2(c.x + hw, y + 4), dim, 1.0)
	_text(Vector2(c.x, y - 6), "W %d px  (%d%% of screen)" % [roundi(hw * 2.0), roundi(hw * 2.0 / sw * 100.0)], dim, fs, true)

	# Height: dashed measuring line right of the right edge.
	var x := c.x + hw + 14.0
	draw_dashed_line(Vector2(x, c.y - hh), Vector2(x, c.y + hh), dim, 1.0, 5.0)
	draw_line(Vector2(x - 4, c.y - hh), Vector2(x + 4, c.y - hh), dim, 1.0)
	draw_line(Vector2(x - 4, c.y + hh), Vector2(x + 4, c.y + hh), dim, 1.0)
	_text(Vector2(x + 8, c.y + 4), "H %d px\n(%d%%)" % [roundi(hh * 2.0), roundi(hh * 2.0 / sh * 100.0)], dim, fs, false)

	# Corner + line callout under the bottom-left corner.
	_text(Vector2(c.x - hw, c.y + hh + 20.0),
		"corner %d px   line %.1f px   offset Y %d px" % [roundi(corner), th, roundi(p["offset_y"])], dim, fs, false)
	# Tiny centre cross so the true screen centre is visible while tuning.
	var sc := size * 0.5
	draw_line(sc - Vector2(5, 0), sc + Vector2(5, 0), Color(COLOR, 0.35), 1.0)
	draw_line(sc - Vector2(0, 5), sc + Vector2(0, 5), Color(COLOR, 0.35), 1.0)
	_text(Vector2(sc.x + 8, sc.y - 6), "screen %d x %d" % [roundi(sw), roundi(sh)], Color(COLOR, 0.35), 11, false)


func _text(pos: Vector2, s: String, col: Color, fs: int, centred: bool) -> void:
	var at := pos - Vector2(300, 0) if centred else pos
	var align := HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
	var w := 600.0 if centred else -1.0
	var shadow := Color(0, 0.08, 0, 0.75)
	draw_multiline_string_outline(_font, at, s, align, w, fs, -1, 4, shadow)
	draw_multiline_string(_font, at, s, align, w, fs, -1, Color(col, 1.0))
