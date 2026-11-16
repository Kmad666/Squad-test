extends CanvasLayer
## FIELD MANUAL: Esc pauses the game and opens a tabbed reference for every
## mechanic. Esc again (or RESUME) closes it; click to start aiming again.
##
## In the browser, Esc while aiming makes the browser release the mouse
## itself (the key may never reach the game), so losing the mouse grab
## unexpectedly also opens the manual. That doubles as pause-on-alt-tab.
##
## Tabs: BRIEFING (the mission you're on, from the map's BRIEFING const; it
## opens by itself the first time you play each map), GUIDES (step-by-step
## walkthroughs), then a reference page per mechanic.
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
var briefing := ""              # set by main before adding: this map's BRIEFING
var briefing_title := ""        # ... and its name


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


## Open on the BRIEFING tab (the first time a map is played).
func open_briefing() -> void:
	open()
	_tabs.current_tab = 0


## Open on a tab by its name (e.g. "GUIDES").
func open_tab(title: String) -> void:
	open()
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == title:
			_tabs.current_tab = i


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
	title.text = "FIELD MANUAL  //  GAME PAUSED" + (("  //  " + briefing_title) if briefing_title != "" else "")
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Click a tab or use LEFT / RIGHT.   New here? Read BRIEFING, then GUIDES.   ESC or RESUME to return, then click to aim."
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

	var pages: Array = []
	if briefing != "":
		pages.append(["BRIEFING", briefing + BRIEFING_FOOTER])
	for page in PAGES:                  # the guides first, then the reference pages
		if page[0] == "GUIDES":
			pages.append(page)
	for page in PAGES:
		if page[0] != "GUIDES":
			pages.append(page)
	for page in pages:
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
	return _tabs.get_tab_count()


const BRIEFING_FOOTER := """

{d}This briefing opens by itself the first time you play a map. It's always here: {k}ESC{/k}, first tab. The {h}GUIDES{/h} tab has step-by-step walkthroughs; the other tabs explain each mechanic in full.{/d}"""


# ---------------------------------------------------------------- content

const PAGES := [
["KEYS", """{h}MOVE & LOOK{/h}
  {k}W A S D{/k}        Move the squad (or the team you command)
  {k}MOUSE{/k}          Aim the camera. {k}Click{/k} to grab the mouse
  {k}WHEEL{/k}          Zoom
  {k}E{/k}              Move to the spot under the reticle
  {k}Y{/k}              Formation: WEDGE / FILE / LINE
  {k}J{/k}              Walk on / off
  {k}SHIFT{/k} (hold)    Rush
  {k}C / SPACE{/k}      Take cover against where the camera faces / leave cover
                 (in cover, WASD and E move cover to cover)
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

 {h}HOUSES{/h}  {d}(OPERATION GORDIAN){/d}
  {k}G{/k}              Reticle on a door: stack up beside it. {k}G{/k} again: breach and clear the room

{h}COMBINED ARMS{/h}  {d}(OPERATION SLEIPNIR){/d}
  {k}Z{/k}              LAV with us (it leads, the men stack behind it) / LAV on overwatch

{h}SEEING{/h}
  {k}L{/k}              Weapon lights on/off (on by default at night)
  {k}N{/k}              Night vision on/off
  {k}I{/k}              Thermal sight on/off (inside the reticle)

{h}GAME{/h}
  {k}ESC{/k}            This manual (pauses)
  {k}F1{/k}             Controls panel on/off
  {k}TAB{/k}            Aim / free mouse (free: hold {k}RIGHT MOUSE{/k} and drag to pan)
  {k}O{/k}              Reticle settings (and the move preview orbs on / off)
  {k}F2{/k}             Graphics HIGH / LOW
  {k}F3{/k}             Difficulty EASY / NORMAL (restarts the operation)
  {k}V{/k}              Retro graphics on / off
  {k}M{/k}              Next map
  {k}BACKSPACE{/k}      Level select
  {k}R{/k}              Restart
"""],
["GUIDES", """{d}Step-by-step walkthroughs. The other tabs have the full detail on each mechanic.{/d}

{h}1. YOUR FIRST FIGHT{/h}
  1. Move with {k}WASD{/k}. The squad moves as one; you steer the group, not a man.
  2. Your men {h}hold fire{/h} until told. Press {k}F{/k} for fire at will: everyone shoots whatever he can see. (Or hold {k}LEFT MOUSE{/k}: everyone fires at what's in the reticle.)
  3. Contact? Press {k}C{/k}. Each man runs to the nearest cover facing the enemy.
  4. Watch the {h}FIRE ON US{/h} bar (top left) and your men's health (bottom right). Pinned men fire less and stay down.
  5. Right click throws a grenade at the reticle. {k}1{/k}-{k}4{/k} or {k}X{/k} pick which special.

{h}2. MOVING UNDER FIRE (COVER TO COVER){/h}
  1. Get into cover with {k}C{/k}.
  2. Stay in cover and push {k}WASD{/k} toward where you want to go. The men stay in cover and hop from one piece to the next.
  3. Where there's no cover, they go {h}prone and crawl{/h}: slow, but much harder to hit.
  4. {k}C{/k} again takes the unit out of cover to move fast. Do that once you're out of the fight.

{h}3. THE APPROACH: FORMATION AND PACE{/h}
  1. Crossing open ground toward the enemy: {h}WEDGE{/h} (the default), and {k}J{/k} to {h}walk{/h}. Walking men are spotted late and shoot nearly as well as standing.
  2. Shots fired? Walking, the men can fight back on the move. Or {k}C{/k} for cover.
  3. A gap of open ground between two pieces of cover: hold {k}SHIFT{/k} and {h}rush{/h} it. Fast and hard to hit, but nobody shoots, so get the other team or the LAV to cover you.
  4. Into an alley or a gateway: {k}Y{/k} to {h}FILE{/h} (it also happens by itself where it's narrow).
  5. Going in on a position at close range: {k}Y{/k} to {h}LINE{/h} so every gun points forward, fire at will ({k}F{/k}), walk ({k}J{/k}).

{h}4. FIRE AND MOVEMENT (BOUNDING){/h}
  1. {k}T{/k} splits the squad into two fire teams, side by side. {k}Q{/k} switches which one you command.
  2. Put the reticle where you want to go and press {k}B{/k}. One team moves while the other covers it, then they swap, leapfrogging up.
  3. Or do it by hand: put team A in cover firing at will ({k}C{/k}, {k}F{/k}), switch to team B ({k}Q{/k}) and move it up or round the flank.
  4. {k}T{/k} again joins them back up.

{h}5. WHEN THE ENEMY FLANKS{/h}
  1. The sergeant shouts {h}"ENEMY FLANKING LEFT / RIGHT"{/h} when one of your men sees a flanker.
  2. Cover only protects you from the front, so turn to face him: look his way and press {k}C{/k} twice (out of cover, then straight back in). The men pick new cover against the direction you're looking.
  3. Or split ({k}T{/k}) and turn one team to face him, with focus fire ({k}LEFT MOUSE{/k}) on him.
  4. A flanker caught in the open under heavy fire goes to ground. Pin him, then finish him.

{h}6. CLEARING A HOUSE{/h}  {d}(OPERATION GORDIAN){/d}
  1. Pick your door. A back door from a courtyard is usually better than a front door on a street they're covering.
  2. Put the reticle on the door and press {k}G{/k}. The team stacks single file against the wall beside it. Wait for the status to show everyone in place (e.g. {h}6/6{/h}).
  3. {k}G{/k} again. A flashbang goes in first if the room is occupied and someone carries one. Then four men go through to the corners, firing at will.
  4. {h}ROOM CLEAR{/h}: you're in the room. Put the reticle on the next door and repeat.
  5. No flashbangs left? Throw a frag through the door or window first (right click).

{h}7. FIGHTING WITH THE LAV{/h}  {d}(OPERATION SLEIPNIR){/d}
  1. The LAV leads. Steer as usual; your men stack behind its hull, away from the enemy.
  2. It fires with your fire orders. Press {k}F{/k} and its 25mm does the heavy work at range.
  3. Find the {h}RPG men{/h} at each position and kill them first: four RPG hits destroy the LAV.
  4. {k}Z{/k} leaves the LAV on overwatch where it is, and the men go forward on foot. {k}Z{/k} calls it back.

{h}8. AT NIGHT{/h}  {d}(OPERATION LAMPLIGHTER){/d}
  1. {k}L{/k}: weapon lights. They light up what you aim at, but give you away.
  2. {k}N{/k}: night vision. Brightens everything but flares near lamps and fire.
  3. {k}I{/k}: thermal, inside the reticle only. Bodies glow white, the best way to spot men in the dark.

{h}9. THE ANTI-ARMOR TEAM AND THE APC{/h}
  1. Every operation has a 3-man anti-armor team waiting somewhere near the start (the briefing says where). Walk the squad to them and they join.
  2. Pick rockets ({k}4{/k}), put the reticle on the APC and right click.
  3. Three rocket hits kill it. Grenades and rifles barely scratch it, and the anti-armor team carries six rockets between them, so don't waste them on infantry.

{h}10. THE MOUSE AND THE CAMERA{/h}
  - Click to aim: the mouse turns the camera. {k}ESC{/k} lets go of the mouse and opens this manual.
  - {k}TAB{/k} lets go of the mouse without pausing: the cursor moves freely and you can hold {k}RIGHT MOUSE{/k} and drag to look around. {k}TAB{/k} again to aim.
  - {k}H{/k} holds the squad in place and lets {k}WASD{/k} scout ahead with the camera.
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
You steer an invisible point. Each man keeps his own place in the formation around it and finds his own way around cars and crates. Buildings and compound walls stop the squad; small cover doesn't. If men fall behind, the group slows so nobody gets left.

{h}MOVE PREVIEW (the orbs){/h}
Rest the reticle on the ground for a moment and floating orbs show where each man would end up if you pressed {k}E{/k} now. They follow the same rules as the move itself:
  - {h}green{/h}: behind cover (you're in cover, so they'll go cover to cover)
  - {h}amber{/h}: flat on the ground in the open: no cover there for him
  - {h}blue{/h}: standing in formation (an ordinary move; nobody takes cover)
Lots of amber? Pick a spot with more cover, or go there and spread out. The orbs fade while the reticle sweeps and while the team is already moving. Switch them off in the reticle settings ({k}O{/k}).

{h}FORMATIONS  ({k}Y{/k}){/h}
The formation turns with the way you're heading. When you set off in a new direction or turn hard, the places are dealt out again so each man takes the one nearest him: nobody runs back through the group, and the point is whoever is out front.
  - {h}WEDGE{/h} (start): a point man, the rest spread back to both sides. Everyone can shoot forward and to the flanks. Open ground.
  - {h}FILE{/h}: a staggered column. Narrow, and only the front can shoot ahead. Alleys, gateways, doors.
  - {h}LINE{/h}: everyone abreast, all guns forward. The assault, or a short dash to a wall.
Squeezing through somewhere narrow (a gateway, a gap between walls), a wedge or line closes into a file on its own ({h}FILE, NARROW{/h} on the panel) and opens out again once through.

{h}PACE  ({k}J{/k} walk,  hold {k}SHIFT{/k} rush){/h}
  - {h}WALK{/h} (half speed): steady. The men shoot nearly as well as from a halt and their fire pins the enemy fully. A sentry who hasn't been alerted spots walking men much later ({h}60%{/h} of his usual range). The pace to approach in, and to fight on the move.
  - {h}MOVE{/h}: the usual pace. On NORMAL the men hit very little while moving like this.
  - {h}RUSH{/h} (hold {k}SHIFT{/k}, a third faster): flat out. Hard to hit, but {h}nobody shoots{/h}, and sentries spot you further off. For crossing open ground to the next cover.
The panel shows formation and pace on the {h}FORM{/h} line. A breach or the LAV sets its own pace.

{h}MOVE ORDER  ({k}E{/k}){/h}
The squad (or your active team) moves to the ground under the reticle center. A green ring marks the spot. {k}WASD{/k} cancels. In cover, they go there {h}cover to cover{/h} (below).

{h}TAKE COVER  ({k}C{/k} / {k}SPACE{/k}){/h}
After the sergeant's signal, every man runs (heavy, flat out) to the nearest free spot that puts cover between him and {h}where the camera is looking{/h}, with a pull toward the group. No two men share a spot. A man with no cover within reach {h}goes prone{/h} where he is.
Cover is a state the unit {h}stays in{/h} until you press {k}C{/k} again.
  - {h}Low cover{/h} (crates, cars, barriers, sandbags, dumpsters): crouched = hidden. He pops up to shoot, then ducks.
  - {h}Tall cover{/h} (tall crates, building corners, compound walls): can't shoot over it. He leans out past the edge, fires, and steps back. Each man claims his own corner.
  {d}Crouched behind low cover, enemies can't see or hit you. Only lobbed grenades reach over it.{/d}

{h}COVER TO COVER  ({k}WASD{/k} or {k}E{/k} while in cover){/h}
The unit moves {h}without leaving cover{/h}. Each man heads where you're sending the unit, keeping his place in its spread, and makes for the {h}nearest free cover there{/h} that shields him from where the camera faces, running low from one spot to the next. He stays put until a new spot is clearly better, so a short nudge doesn't shuffle everyone. The unit's point waits for the men if it gets more than 6 m ahead.
{h}No cover where he's going: he goes prone and crawls{/h} (about 1 m/s). Prone, he's a small target: enemy hit chance x0.45, and blasts that reach him do 40% less. He fires from where he lies once he's stopped, and gets up again as soon as there's cover in reach.
{h}Leaving cover{/h} ({k}C{/k} again): each man gets up and comes out on his own beat, moving {h}low and slow{/h} for about 2 s, firing at any enemy inside the reticle to cover the move, then stands and moves normally. A bounding advance ({k}B{/k}) always leaves cover and runs.

{h}HOLD & SCOUT  ({k}H{/k}){/h}
Nobody moves. {k}WASD{/k} slides the camera up to 30 m ahead so you can look around corners. {k}H{/k} again snaps back.
"""],
["FIRE CONTROL", """{h}DEFAULT: HOLD FIRE{/h}
Your men don't shoot until told to. That lets you sneak up on positions that haven't spotted you.

{h}READING YOUR MEN{/h}
A man with his rifle up at the shoulder is engaging; rifle low across the body means he's holding, has no shot, or is ducked. Enemies do the same: a shouldered enemy rifle is about to fire on you.

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
["COMBINED ARMS", """{h}THE LAV-25{/h}  {d}(OPERATION SLEIPNIR){/d}
An eight-wheeled armored vehicle in woodland camo with an orange air-recognition panel on the back deck. Its turret carries a {h}25mm chain gun{/h} firing HE: bursts of 3-5, out to 120 m, a small burst on impact that catches men next to the strike, and enough punch to chew through the enemy APC. It follows your fire orders like the men do: hold, fire at will, focus on the reticle. It shows in the unit panel with its armor.
Bullets bounce off it. Only {h}cannon shells{/h} (the enemy APC) hurt it. Destroyed, it burns and the men carry on on foot.

{h}LAV WITH US  ({k}Z{/k}){/h}
The LAV {h}leads{/h}: it drives to the unit's point (the front) and the infantry {h}stack up behind it{/h} in two tight files, close against the hull. You steer as usual (WASD, E, B, H); the vehicle drives there at a walking pace and the men walk in its shadow. It waits for anyone falling behind, backs up rather than turning round for short moves, and drives round buildings on its own.
  - {h}Which side:{/h} the men keep the hull between them and the nearest enemy of any position that has spotted you; otherwise between them and where the unit is heading. Normally that's behind it; with the enemy off to one flank they shift along the far side. Never in front of it while it's moving. They don't shuffle at every nudge: a side has to be clearly better.
  - {h}Shooting:{/h} the hull is tall cover. A man with a shot {h}leans out past the side of the hull{/h} (or round its nearer end), fires a burst, and ducks back. Pinned, he stays in.
  - {k}C{/k} does nothing while you're stacked: you're already in cover.
  {d}Enemy riflemen will shoot at the LAV when it's all they can see, which draws fire off your men.{/d}

{h}OVERWATCH  ({k}Z{/k} again){/h}
The LAV stops where it is and covers: once a fight is on it fires at will at anything it can see. The men get up and act as normal infantry (cover, cover to cover, prone). {k}Z{/k} calls it back: they stack on it where it is and it leads again.
With fire teams split, the LAV works with team A.
"""],
["HOUSES & ROOM CLEARING", """{h}HOUSES YOU CAN GO INTO{/h}  {d}(OPERATION GORDIAN){/d}
Four houses have a real ground floor: the {h}East House{/h} and {h}West House{/h} either side of the south barricade, the {h}Ketten House{/h} on the tram street, and the {h}North House{/h} by the north strongpoint. You can tell them by the open doorways and window openings at street level. Three are garrisoned; the West House is empty, yours to take and fire from.
  - {h}Doors{/h} are open doorways. Each house has a front door on the street; three have a back door onto their courtyard. Inside, a front row and a back row of rooms, with doors between.
  - {h}Windows{/h} are openings over a sill. The sill is low cover: a man behind it crouches out of sight and pops up to fire through the opening. That works for you too: take a house and your men fire from its windows ({k}C{/k} inside).
  - {h}Inside{/h}, the storeys above lift away and the camera swings up to look down into the rooms. It goes back when you leave.
  - You can simply walk in with {k}WASD{/k} or {k}E{/k}. Against a defended room, don't.

{h}STACK, BREACH, CLEAR  ({k}G{/k}){/h}
  1. {h}Stack:{/h} put the reticle on a door and press {k}G{/k}. The team you command lines up single file against the wall beside it, clear of the opening. (Standing close to a door works too.) Stack from outside, or from inside on a door to the next room.
  2. {h}Go:{/h} {k}G{/k} again. If the room is occupied and anyone still carries a {h}flashbang{/h}, it goes in first: men it catches in the open are blind for a few seconds. Then {h}four men go through{/h}, one behind the other, weapons free whatever your fire orders: the first across the doorway to the far corner, the second hooking round to the near corner, the third and fourth following them along the two side walls. Nobody stops in the doorway, every corner is covered. The rest hold the door.
  3. {h}Clear:{/h} when all four are in and nothing in the room is alive: "ROOM CLEAR", and the team is yours again, standing in that room.
Any move order ({k}WASD{/k}, {k}E{/k}, {k}C{/k}) calls it off.

{h}THE DEFENDERS{/h}
  - A garrison {h}holds its house{/h}: it doesn't come out to flank or fall back down the street. Inside, the men give ground room by room and make a stand in the far rooms. Others may fall back {h}into{/h} a house, or be sent to reinforce it.
  - {h}Close quarters is deadly.{/h} Inside 10 m an enemy gets onto you much faster, rarely misses and hits harder. A man in a doorway facing an unblinded rifle gets hurt. Use the flashbang (you carry two), a frag through the door or window first, or come at the room from a door they aren't watching.
  {d}The back door through the courtyard is usually the better way in than the front door on a street they're covering.{/d}
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
Enemy hit chance is lower against men who are moving (x0.75), fighting from cover (x0.6) or prone (x0.45, crawling or not), and drops as the shooter gets suppressed. Shell blasts do 40% less to a man lying prone.
"""],
["ENEMIES", """{h}RIFLEMEN{/h}  {d}(olive-brown camo, red armband, red mask lenses that glow at night){/d}
They guard an area. Until alerted they stand at their post and only notice you within {h}45 m in daylight, 35 m at night{/h}, or when they're shot at. Once one spots you, the whole area goes on alert (CONTACT in the HUD).
Alerted riflemen:
  - run to cover in their area that shields them from your squad
  - crouch, then pop up or lean out to shoot
  - stay down when pinned, peek less when suppressed
  - move to new cover when you flank their position
  - fall back to cover further away when wounded
  - {h}keep their heads down when you're out of their range{/h} (a quick look now and then): sniping a position from far off doesn't work, you have to close in
  - {h}dive away from a frag{/h} if they see it coming and aren't pinned, which gets them out of their cover

{h}THEIR TACTICS{/h}
Each position fights as a team:
  - {h}Flank:{/h} a few seconds into a fight, one man (two from a big group) goes to fight from cover {h}off to your side{/h} while the rest give covering fire (up more, down less). The sergeant calls "ENEMY FLANKING LEFT / RIGHT" when one of your men sees him. Heavy fire on a flanker in the open puts him to ground, so {h}pin him{/h}, or split a team to face him. Your cover (or the LAV) only shields you from the front.
  - {h}Fall back:{/h} a position worn down to a third of its men gives it up: the survivors run to the next position further from you (the HUD shows it CLEAR and the other one grow). They can't break away while pinned.
  - {h}Reinforce:{/h} a position that's been fighting for a while gets half the riflemen of a quiet one nearby. You're told when it happens: they're in the open on the way.
  - {h}Assault:{/h} if they outnumber you two to one they stop defending and close in, cover to cover.

{h}APC{/h}  {d}(enemy vehicle, label shows its HP){/d}
Heavy armor, 360 HP. Patrols a short route; stops the moment it sees you or takes fire. The turret tracks you with a machine gun and fires explosive cannon shells. Bullets ricochet, so use rockets (3 hits), or grenades for a little damage. Once destroyed it burns and stays down.

{h}WAITING TEAMS{/h}
The {h}anti-armor team{/h} (coyote-brown packs and kit, green label) waits to link up. Walk the squad within about 7 m and they join, bringing 3 burst rifles and 6 rockets.
"""],
["MISSIONS", """{h}LEVEL SELECT{/h}
The game opens on the level select: {k}1{/k}-{k}6{/k} or click a card. {k}BACKSPACE{/k} in game goes back to it.

{h}OPERATION BIFROST{/h}  {d}(day){/d}
{h}Objective:{/h} force the bridge and take the north bank.
You start on the south bank of a river. One road bridge (56 m, no other way across) is choked with abandoned cars, a bus and two box trucks: the bus and trucks are tall cover you lean around, the cars low cover. The parapets only shield you from the sides.
  - {h}Bridgehead:{/h} a sandbag line across the far end of the bridge (3 riflemen).
  - {h}Checkpoint:{/h} barriers and a guard booth at the bridge foot (3 riflemen).
  - {h}Depot:{/h} warehouses and containers behind it, 4 riflemen and the APC on patrol.
  - The {h}anti-armor team{/h} waits on the south bank, west of the start.
{d}Tips: in cover, move vehicle to vehicle (WASD); in the open stretches your men go prone and crawl. Bound team by team. Save rockets for the APC.{/d}

{h}OPERATION LAMPLIGHTER{/h}  {d}(night){/d}
{h}Objective:{/h} secure the compound at the end of the road.
You start at the south end of a street between two rows of buildings.
  - {h}Main road:{/h} parked and crashed cars, a {h}roadblock{/h} mid-street (2 riflemen).
  - {h}Back alley:{/h} parallel on the west side, joined to the road by two side passages. The {h}anti-armor team{/h} waits in the first passage. An {h}ambush{/h} (2 riflemen) covers the far end.
  - {h}Compound:{/h} walled, gate on the road, breach at the alley mouth. 4 riflemen and the APC; a floodlight on the HQ glares at the gate.
{d}Tips: link up with the rocket team first. Send a team down the alley to flank the roadblock. Save rockets for the APC.{/d}

{h}OPERATION GORDIAN{/h}  {d}(day){/d}
{h}Objective:{/h} take the crossroads: clear all eight positions, three of them inside houses. A Berlin crossroads, 190 m across: {h}Gordianstrasse{/h} (asphalt, lindens, parked cars down both kerbs) runs north from your start and crosses {h}Kettenstrasse{/h} (setts, tram rails, a 30 m tram standing east of the crossing). Five-storey houses wall in both streets.
  - {h}Gordian South:{/h} a barricade across the street ahead of you (3 riflemen).
  - {h}Crossing:{/h} sandbags on the far side, a kiosk and the nose of the tram (3).
  - {h}Vacant lot:{/h} a gap in the houses on Kettenstrasse west, behind a hoarding with a break in it (3).
  - {h}Ketten East:{/h} behind the tram, with the APC patrolling the tram street (3 + APC).
  - {h}Gordian North:{/h} the strongpoint up the street: sandbags, a container and a truck across the road (3).
  - {h}East House{/h} (3), {h}Ketten House{/h} (4) and {h}North House{/h} (4): garrisons inside, firing from the windows (see HOUSES & ROOM CLEARING).
  - The {h}West House{/h}, opposite the East House, is empty: its windows look onto the south barricade.
{h}Gateways:{/h} five houses have their carriage gateway open right through to the courtyard behind (look for the dark tunnel in the facade). Three blocks are ways round:
  - {h}East yard:{/h} gateway on your right at the brick house, out again onto Kettenstrasse behind the tram. The {h}anti-armor team{/h} waits in this yard.
  - {h}West yard:{/h} gateway on your left, out through the back of the vacant lot.
  - {h}North-east yard:{/h} from Kettenstrasse round to the flank of Gordian North.
{d}Tips: the streets are long straight fields of fire, so don't walk up the middle. Their flankers and reinforcements use the same gateways, so watch the ones behind you.{/d}

{h}OPERATION SLEIPNIR{/h}  {d}(day){/d}
{h}Objective:{/h} clear all four positions. The biggest map (220 m across): open farmland, an asphalt road winding north, dirt tracks, hedgerows with gaps wide enough for a vehicle. You have a {h}LAV-25{/h} (see COMBINED ARMS).
  - {h}Outpost:{/h} a sandbag checkpoint across the road (3 riflemen).
  - {h}Treeline:{/h} a hedgerow along the west track with trees behind (3 riflemen).
  - {h}Farm:{/h} farmhouse, barn, a walled yard and a truck to the east (4 riflemen).
  - {h}Crossroads:{/h} a village where the road meets the east-west road. 5 riflemen behind sandbags, cars and a container, and the APC patrolling the crossroad.
  - The {h}anti-armor team{/h} waits at the ruined barn east of the start.
{d}Tips: let the LAV's 25mm do the heavy work at range while the men stay stacked behind it. Its cannon wins against riflemen, but the APC's cannon can kill it: bring the rockets.{/d}

{h}TEST FIELD{/h}  {d}(day){/d}
Open ground with crates and walls. Three small positions: {h}ALPHA{/h} (2 riflemen), {h}BRAVO{/h} (3), {h}CHARLIE{/h} (2 + APC on patrol). Good for trying mechanics.

{h}MODEL VIEWER{/h}  {d}(day, no enemies){/d}
Every variant of the universal soldier on a turntable: rifleman, sergeant, grenadier, rocketman, enemy, crouched, and a sergeant looping his hand signals. Further along: the gaits, animated in place: walk, run, crouch-walk, strafe and backpedal, then firing (standing, crouched, on the move), then prone: lying still, crawling, and firing prone. Your squad holds back; {k}WASD{/k} pans along the line-up, wheel zooms.

{h}SWITCHING{/h}
{k}M{/k} loads the next map (remembered). {k}R{/k} restarts the current one. {k}BACKSPACE{/k}: back to the level select.
"""],
["SETTINGS", """{h}DIFFICULTY  ({k}F3{/k}, or on the level select){/h}
NORMAL: the enemy shoots straight, hits hard, reacts fast and wakes up the positions next door when the shooting starts; your men can't hit much while walking. Walking at a position in the open costs most of the squad. Fight from cover, pin them, then move.
EASY: the game as it was: forgiving, a charge usually works.
Changing it restarts the operation. Shown next to UNIT in the top-left; remembered in your browser.

{h}GRAPHICS  ({k}F2{/k}){/h}
HIGH: shadows, bloom, anti-aliasing, full-resolution 3D, full screen effects.
LOW: no shadows or bloom, 3D drawn at 70% resolution, lighter screen effects. For weaker machines; remembered in your browser.

{h}RETRO  ({k}V{/k}){/h}
A late-90s console look, on top of HIGH or LOW: chunky low-poly soldiers with flat colours and slightly wobbly vertices, chunky screen pixels and 15-bit dithered colour. The HD soldiers come back when you switch it off. Remembered in your browser.

{h}DESKTOP BUILD{/h}
The downloadable Windows / Linux version (see the README) runs the full renderer: mist that lamps and weapon lights throw real beams through at night, weapon lights that cast shadows, ambient occlusion, and every man's light on even on LOW. The HUD shows {h}DESKTOP{/h}. On a weak graphics chip use the {h}SquadTest-LowEnd{/h} launcher: the browser's lighter renderer.

{h}WEAPON LIGHTS  ({k}L{/k}){/h}
A white light under every man's barrel, pointing wherever his rifle points: the ground ahead at low ready, the target when he shoulders it. On by default on night maps. On LOW graphics only every third man's light is on (each light costs the graphics card a pass).

{h}NIGHT VISION  ({k}N{/k}){/h}
Classic green goggles over the whole screen: the dark lifted, lights blooming, heavy grain, flicker, scan lines and the round edge of the eyepiece. Washes out in daylight, like the real thing.

{h}THERMAL SIGHT  ({k}I{/k}){/h}
Inside the reticle only: white-hot. Bodies glow (faces and hands hottest, rifles cooler, the dead cooling), the rest of the scene goes cold grey; lamps, muzzle flashes and fires show hot too. Works with night vision on, by day and night, HD or RETRO. Resize the reticle ({k}O{/k}) to see more.

{h}AIM / FREE MOUSE  ({k}TAB{/k}){/h}
Tab lets go of the mouse without pausing: the cursor moves freely and clicks don't fire. Hold the right button and drag to pan the camera. Tab again grabs the mouse and you're aiming. (In the browser, if Tab can't grab the mouse, click.)

{h}UNIT STATUS  (bottom right){/h}
The dial turns with the camera: the notch at the top is where you're looking, the letters show north, and the amber arrow is the way the unit you command is moving (longer = faster; a dot when halted). Next to it: the compass heading and speed, whether the unit is in cover (with how many men are in position and how many are prone), and the last three fire orders with how long ago they were given.

{h}RETICLE  ({k}O{/k}){/h}
Sliders for width, height, corner length, line thickness, vertical offset, glow, opacity and flicker; a switch to show the measurements; reset to defaults. Saved in your browser.

{h}CONTROLS PANEL  ({k}F1{/k}){/h}
The key summary in the top right. Hides itself after 25 s.

{h}SCREEN EFFECTS{/h}
Heavy firing shakes the camera, blurs the edges and flashes the screen. Being under fire drains color. A hit on one of your men flashes the screen edge red.
"""],
]
