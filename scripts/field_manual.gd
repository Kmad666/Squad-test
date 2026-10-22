extends CanvasLayer
## FIELD MANUAL: Esc pauses the game and opens a tabbed reference for every
## mechanic. Esc again (or RESUME) closes it; click to start aiming again.
##
## In the browser, Esc while aiming makes the browser release the mouse
## itself (the key may never reach the game), so losing the mouse grab
## unexpectedly also opens the manual. That doubles as pause-on-alt-tab.
##
## Keep the text below up to date when mechanics change: it's the one place
## that explains how everything works.

const K := "#ffbf33"     # key names
const H := "#ffffff"     # headings
const D := "#8fbf80"     # notes

var is_open := false
var _was_captured := false
var _expect_release := false
var _root: Control
var _lock_cb: JavaScriptObject   # browser "pointer lock changed" listener (web only)
var _tabs: TabContainer
var ui_theme: Theme             # set by main before adding (neon font + colours)


## The game is about to release the mouse on purpose (e.g. the reticle
## panel): don't treat it as "open the manual".
func allow_release() -> void:
	_expect_release = true


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	# In the browser, Esc while aiming is eaten by the browser (it releases the
	# pointer lock), so listen for that release directly.
	if OS.has_feature("web"):
		_lock_cb = JavaScriptBridge.create_callback(_on_pointer_lock_change)
		var doc := JavaScriptBridge.get_interface("document")
		doc.addEventListener("pointerlockchange", _lock_cb)


func _on_pointer_lock_change(_args: Array) -> void:
	var locked: bool = JavaScriptBridge.eval("!!document.pointerLockElement", true)
	if locked or is_open:
		return
	if _expect_release:
		_expect_release = false
		return
	call_deferred("open")


func _process(_delta: float) -> void:
	if _lock_cb:
		return     # web: the browser's pointer-lock event handles this
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and not is_open:
		if _expect_release:
			_expect_release = false
		else:
			open()
	_was_captured = captured


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.physical_keycode in [KEY_LEFT, KEY_RIGHT]:
		var n := _tabs.get_tab_count()
		_tabs.current_tab = (_tabs.current_tab + (1 if event.physical_keycode == KEY_RIGHT else n - 1)) % n
		get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	_root.visible = false
	get_tree().paused = false
	_was_captured = false


# ---------------------------------------------------------------- layout

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ui_theme:
		_root.theme = ui_theme
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(980, 600)
	panel.offset_left = -490
	panel.offset_top = -300
	panel.offset_right = 490
	panel.offset_bottom = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.05, 0.01, 0.95)
	sb.border_color = Color(0.45, 1.0, 0.3, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "FIELD MANUAL  //  GAME PAUSED"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Click a tab or use LEFT / RIGHT.   ESC or RESUME to return, then click to aim."
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.7)
	box.add_child(sub)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_bg := StyleBoxFlat.new()
	tab_bg.bg_color = Color(0.0, 0.03, 0.0, 0.9)
	tab_bg.set_content_margin_all(10)
	_tabs.add_theme_stylebox_override("panel", tab_bg)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.08, 0.25, 0.06)
	sel.set_content_margin_all(5)
	var unsel := StyleBoxFlat.new()
	unsel.bg_color = Color(0.02, 0.08, 0.02)
	unsel.set_content_margin_all(5)
	_tabs.add_theme_stylebox_override("tab_selected", sel)
	_tabs.add_theme_stylebox_override("tab_unselected", unsel)
	_tabs.add_theme_stylebox_override("tab_hovered", sel)
	_tabs.add_theme_color_override("font_selected_color", Color(1, 1, 1))
	_tabs.add_theme_color_override("font_unselected_color", Color(0.45, 1.0, 0.3))
	_tabs.add_theme_color_override("font_hovered_color", Color(0.8, 1.0, 0.7))
	_tabs.add_theme_font_size_override("font_size", 12)
	box.add_child(_tabs)

	for page in PAGES:
		var r := RichTextLabel.new()
		r.name = page[0]
		r.bbcode_enabled = true
		r.scroll_active = true
		r.selection_enabled = false
		r.add_theme_font_size_override("normal_font_size", 14)
		r.add_theme_color_override("default_color", Color(0.45, 1.0, 0.3))
		r.text = _style(page[1])
		_tabs.add_child(r)

	var resume := Button.new()
	resume.text = "RESUME  (ESC)"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(close)
	box.add_child(resume)


## Light markup: {k}text{/k} = key, {h}text{/h} = heading, {d}text{/d} = note.
func _style(t: String) -> String:
	return t.replace("{k}", "[color=%s]" % K).replace("{/k}", "[/color]") \
		.replace("{h}", "[color=%s]" % H).replace("{/h}", "[/color]") \
		.replace("{d}", "[color=%s]" % D).replace("{/d}", "[/color]")


func page_count() -> int:
	return PAGES.size()


# ---------------------------------------------------------------- content

const PAGES := [
["KEYS", """{h}MOVE & LOOK{/h}
  {k}W A S D{/k}        Move the squad (or the team you command)
  {k}MOUSE{/k}          Aim the camera. {k}Click{/k} to grab the mouse
  {k}WHEEL{/k}          Zoom
  {k}E{/k}              Move to the spot under the reticle
  {k}C / SPACE{/k}      Take cover against where the camera faces / leave cover
  {k}H{/k}              Hold position (WASD scouts with the camera instead)

{h}FIRE{/h}
  {k}LEFT MOUSE{/k}     Hold: focus fire on the reticle
  {k}F{/k}              Auto fire on/off (fire at will)
  {k}RIGHT MOUSE{/k}    One click: one man uses one special
  {k}1 2 3 4{/k}        Pick special: frag / flashbang / grenade launcher / rocket
  {k}X{/k}              Next special that still has ammo

{h}FIRE TEAMS{/h}
  {k}T{/k}              Split into teams A + B / join back up
  {k}Q{/k}              Switch which team you command
  {k}B{/k}              Bounding advance to the spot under the reticle

{h}GAME{/h}
  {k}ESC{/k}            This manual (pauses)
  {k}F1{/k}             Controls panel on/off
  {k}TAB{/k}            Reticle settings
  {k}G{/k}              Graphics HIGH / LOW
  {k}M{/k}              Next map
  {k}R{/k}              Restart
"""],
["MOVEMENT & COVER", """{h}THE SERGEANT & HAND SIGNALS{/h}
One man is the {h}sergeant{/h}: amber chevrons on his sleeves, radio antenna on his pack, {h}SGT{/h} in the squad panel. Your orders go through him: he signals with his left hand, and each man reacts after a beat that grows with his distance from him (roughly 0.3-0.8 s in a tight group, over a second if spread out). He reacts first.
  - {h}Move out{/h}: forward chopping motion when you start moving
  - {h}Halt{/h}: raised fist when the unit stops; men stop where they are
  - {h}Take cover{/h}: palm-down pumping
  - {h}Open fire{/h}: points at the reticle; ceasing fire is a little quicker
If he goes down, a rifleman takes over. When split into teams, the other team's leader signals for it.
Men speed up and slow down with weight; they don't snap to a run or a stop.

{h}THE SQUAD MOVES AS ONE{/h}
You steer an invisible point. Each man keeps his own spot in a loose cluster around it and finds his own way around cars and crates. Buildings and compound walls stop the squad; small cover doesn't. If men fall behind, the group slows so nobody gets left.

{h}MOVE ORDER  ({k}E{/k}){/h}
The squad (or your active team) moves to the ground under the reticle center. A green ring marks the spot. {k}WASD{/k} cancels.

{h}TAKE COVER  ({k}C{/k} / {k}SPACE{/k}){/h}
After the sergeant's signal, every man runs (heavy, flat out) to the nearest free spot that puts cover between him and {h}where the camera is looking{/h}, with a pull toward the group. No two men share a spot.
{h}Leaving cover{/h} (moving, or {k}C{/k} again): each man comes out on his own beat and moves {h}low and slow{/h} for about 2 s, firing at any enemy inside the reticle to cover the move, then stands and moves normally.
  - {h}Low cover{/h} (crates, cars, barriers, sandbags, dumpsters): crouched = hidden. He pops up to shoot, then ducks.
  - {h}Tall cover{/h} (tall crates, building corners, compound walls): can't shoot over it. He leans out past the edge, fires, and steps back. Each man claims his own corner.
  {d}Crouched behind low cover, enemies can't see or hit you. Only lobbed grenades reach over it.{/d}

{h}HOLD & SCOUT  ({k}H{/k}){/h}
Nobody moves. {k}WASD{/k} slides the camera up to 30 m ahead so you can look around corners. {k}H{/k} again snaps back.
"""],
["FIRE CONTROL", """{h}DEFAULT: HOLD FIRE{/h}
Your men don't shoot until told to. That lets you sneak up on positions that haven't spotted you.

{h}FOCUS FIRE  (hold {k}LEFT MOUSE{/k}){/h}
Everyone fires only at enemies inside the reticle. With nobody in it, they pour rounds into the area under it (suppressing fire). Focus fire is more accurate and fires faster.

{h}FIRE AT WILL  ({k}F{/k}){/h}
Each man picks any enemy he can see and fires on his own rhythm. Stays on until you press {k}F{/k} again.

{h}TARGET SQUARES{/h}
Empty squares mark every enemy inside the reticle, meaning what the squad will engage.
  - {h}Green{/h} = infantry, {h}orange{/h} = vehicle
  - {h}Thicker{/h} = someone is shooting at it right now
  - {h}Amber bar{/h} under it = how suppressed it is. {h}PINNED{/h} = it has stopped shooting

{h}EVERY SHOT ROLLS TO HIT{/h}
Misses visibly go wide. See WEAPONS for the numbers.
"""],
["SPECIALS", """{h}WHAT YOUR MEN CARRY{/h}
  - {h}Riflemen:{/h} one hand grenade each, a {h}frag{/h} or a {h}flashbang{/h} (mixed across the squad)
  - {h}Grenadier:{/h} 6 grenade-launcher rounds
  - {h}Rocket men{/h} (anti-armor team): 2 rockets each

{h}USING THEM  ({k}RIGHT MOUSE{/k}){/h}
One click = {h}one{/h} man uses {h}one{/h} special of the selected kind. The closest man carrying it pops up, faces the target and throws or fires after a split second.
  - Target: the best enemy inside the reticle that the special can reach (rockets go for vehicles first; grenades and flashbangs for infantry). Otherwise, the ground under the reticle.
  - Aimed further than he can throw? It goes as far as it can in that direction.
  - Rockets fly straight, so a man with a clear line of fire is picked when possible.

{h}PICKING ONE{/h}
{k}1{/k} frag   {k}2{/k} flashbang   {k}3{/k} grenade launcher   {k}4{/k} rocket   {k}X{/k} next with ammo.
The bar at the bottom shows how many are left. Callouts (FRAG OUT!, ROCKET AWAY!, RELOADING) appear under it.
  - Selected kind empty? The click switches to the next kind with ammo and uses it, so it's never wasted.
  - Whole unit out? Right click only flashes {h}NO EXPLOSIVES LEFT{/h}.
  - Split into teams? Only your active team's specials are available.

{h}EFFECTS{/h}
  - {h}Frag{/h} (30 m throw): blast 4.5 m. Lobbed: drops over cover.
  - {h}Flashbang{/h} (30 m throw): no damage. Enemies within 7 m with no wall in between are {h}blinded{/h} (can't shoot) and pinned for 3.5 s. Your own men too close get rattled.
  - {h}Grenade launcher{/h} (55 m): blast 4 m, lobbed, 1.6 s reload between rounds.
  - {h}Rocket{/h} (90 m): blast 3 m, 120 damage to armor. 5 s reload. The APC takes 3 hits.
"""],
["FIRE TEAMS", """{h}SPLIT  ({k}T{/k}){/h}
The squad splits into {h}team A{/h} (green helmet patch) and {h}team B{/h} (amber patch), side by side. Specialists are spread across both. {k}T{/k} again regroups everyone on the team you command.

{h}COMMAND  ({k}Q{/k}){/h}
You control one team at a time: movement, cover, fire mode and specials. The camera follows it.
The {h}other team{/h} holds where it is and acts as your base of fire: once a fight is on, it fires at will. It won't start a fight on its own.

{h}BOUNDING ADVANCE  ({k}B{/k}){/h}
Point the reticle at where you want to go and press {k}B{/k}. It splits the squad if needed. One team gets down in cover facing the objective while the other moves about 9 m ahead and takes cover; then they swap, leapfrogging until both teams reach the spot. {k}WASD{/k} or {k}E{/k} cancels.

{h}OTHER RULES{/h}
  - Either team can pick up a waiting team (it joins the team that reached it).
  - If one team is wiped out, the survivors regroup into one squad.
"""],
["HEALTH & SUPPRESSION", """{h}HEALTH{/h}
Each man has 100 HP. Below 50 he's {h}wounded{/h}: slower and less accurate. At 0 he's {h}down{/h}. He stays where he fell and the squad closes ranks. The panel at bottom right shows every man's health and special; the screen edge flashes red when someone is hit.

{h}SUPPRESSION (BOTH SIDES){/h}
Rounds passing close (about 2 m) build suppression; it fades about 1.5 s after the fire stops. Hits rattle more. Fire from far away is less frightening than fire from close up.
  - {h}Your men:{/h} suppressed = shorter looks over cover, worse aim. {h}PINNED{/h} = they stay down. The {h}FIRE ON US{/h} bar shows the squad average; the screen drains of color as it climbs.
  - {h}Enemies:{/h} suppressed = slower, worse fire. {h}PINNED{/h} = they stop shooting.

{h}THE CORE LOOP{/h}
Pin them with focus fire, then flank with a fire team, or finish them with a grenade or rocket.
"""],
["WEAPONS", """{h}YOUR WEAPONS{/h}
  WEAPON            ACCURACY  RANGE (eff / max)   DAMAGE (inf / armor)
  Rifle             55%       30 / 60 m           1 / 0       2-4 round bursts
  Burst rifle       65%       40 / 65 m           1.2 / 0     3-round bursts
  Frag              75%       15 / 30 m           10 / 5      4.5 m blast
  Flashbang         80%       15 / 30 m           blind 3.5 s 7 m radius
  Grenade launcher  45%       25 / 55 m           10 / 15     4 m blast
  Rocket            70%       45 / 90 m           20 / 120    3 m blast

{h}HIT CHANCE{/h}
accuracy x range x target size x modifiers, always between 3% and 95%.
  - Beyond effective range, accuracy drops toward 30% at max range
  - Vehicles are big: x1.7. Rockets vs infantry: x0.55
  - Shooter moving x0.6, aimed (focus fire, specials) x1.15, follow-up rounds in a burst x0.85
  - Suppressed: up to x0.5. Wounded: x0.85
  {d}Bullets bounce off armor. Only explosives hurt the APC.{/d}

{h}ENEMY WEAPONS{/h}
  Enemy rifle       32%       30 / 60 m     16 damage
  APC machine gun   30%       40 / 65 m     14 damage
  APC cannon        50%       45 / 70 m     55 damage, 3.5 m blast (x0.3 behind cover), 7 s reload
Enemy hit chance is lower against men who are moving (x0.75) or fighting from cover (x0.6), and drops as the shooter gets suppressed.
"""],
["ENEMIES", """{h}RIFLEMEN{/h}  {d}(grey uniform, red armband){/d}
They guard an area. Until alerted they stand at their post and only notice you within {h}45 m in daylight, 35 m at night{/h}, or when they're shot at. Once one spots you, the whole area goes on alert (CONTACT in the HUD).
Alerted riflemen:
  - run to cover in their area that shields them from your squad
  - crouch, then pop up or lean out to shoot
  - stay down when pinned, peek less when suppressed
  - move to new cover when you flank their position
  - fall back to cover further away when wounded
  - never leave their own area

{h}APC{/h}  {d}(enemy vehicle, label shows its HP){/d}
Heavy armor, 360 HP. Patrols a short route; stops the moment it sees you or takes fire. The turret tracks you with a machine gun and fires explosive cannon shells. Bullets ricochet, so use rockets (3 hits), or grenades for a little damage. Once destroyed it burns and stays down.

{h}WAITING TEAMS{/h}
The {h}anti-armor team{/h} (tan uniforms, green label) waits to link up. Walk the squad within about 7 m and they join, bringing 3 burst rifles and 6 rockets.
"""],
["MISSIONS", """{h}OPERATION LAMPLIGHTER{/h}  {d}(night){/d}
{h}Objective:{/h} secure the compound at the end of the road.
You start at the south end of a street between two rows of buildings.
  - {h}Main road:{/h} parked and crashed cars, a {h}roadblock{/h} mid-street (2 riflemen).
  - {h}Back alley:{/h} parallel on the west side, joined to the road by two side passages. The {h}anti-armor team{/h} waits in the first passage. An {h}ambush{/h} (2 riflemen) covers the far end.
  - {h}Compound:{/h} walled, gate on the road, breach at the alley mouth. 4 riflemen and the APC; a floodlight on the HQ glares at the gate.
{d}Tips: link up with the rocket team first. Send a team down the alley to flank the roadblock. Save rockets for the APC.{/d}

{h}TEST FIELD{/h}  {d}(day){/d}
Open ground with crates and walls. Three small positions: {h}ALPHA{/h} (2 riflemen), {h}BRAVO{/h} (3), {h}CHARLIE{/h} (2 + APC on patrol). Good for trying mechanics.

{h}MODEL VIEWER{/h}  {d}(day, no enemies){/d}
Every variant of the universal soldier on a turntable: rifleman, sergeant, grenadier, rocketman, enemy, crouched, and a sergeant looping his hand signals. Further along: the gaits, animated in place: walk, run, crouch-walk, strafe and backpedal. Your squad holds back; {k}WASD{/k} pans along the line-up, wheel zooms.

{h}SWITCHING{/h}
{k}M{/k} loads the next map (remembered). {k}R{/k} restarts the current one.
"""],
["SETTINGS", """{h}GRAPHICS  ({k}G{/k}){/h}
HIGH: shadows, bloom, anti-aliasing, full-resolution 3D, full screen effects.
LOW: no shadows or bloom, 3D drawn at 70% resolution, lighter screen effects. For weaker machines; remembered in your browser.

{h}RETICLE  ({k}TAB{/k}){/h}
Sliders for width, height, corner length, line thickness, vertical offset, glow, opacity and flicker; a switch to show the measurements; reset to defaults. Saved in your browser.

{h}CONTROLS PANEL  ({k}F1{/k}){/h}
The key summary in the top right. Hides itself after 25 s.

{h}SCREEN EFFECTS{/h}
Heavy firing shakes the camera, blurs the edges and flashes the screen. Being under fire drains color. A hit on one of your men flashes the screen edge red.
"""],
]
