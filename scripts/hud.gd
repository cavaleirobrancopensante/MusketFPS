extends Control
## Touch HUD, Call of Duty Mobile style:
##   left side  - floating move joystick (appears where your thumb lands)
##   right side - drag anywhere to look
##   FIRE       - fires your musket; keep dragging from it to aim while firing
##   BAYONET    - switch to melee; FIRE becomes four swing buttons (OVER,
##                LEFT, RIGHT, THRUST): press to wind up, hold to charge,
##                release to strike; drag from the button to keep aiming
##   BLOCK      - hold to parry (melee only)
##   VOLLEY!    - the company fires every loaded musket
##   top right  - FOLLOW / HOLD / fire mode toggle
##
## In a field battle (field.gd) the top right is your army instead: a card for
## every regiment (tap to select, tap again to let go; several at once). With
## some selected, a row of their orders appears, and a tap in the world sends
## them: on an enemy regiment, at it; on the ground, there; you point and
## shout it. With none selected, the row is your own company's orders. A
## minimap on the left (tap it for the command view), and the SPYGLASS in
## the weapon row.
##
## Touches are handled by hand (not Buttons) so several fingers work at once.
const UI := preload("res://scripts/ui.gd")

const JOY_RADIUS := 90.0

# Swing directions (same values as player.gd's Swing enum).
const NONE := -1
const OVERHEAD := 0
const LEFT := 1
const RIGHT := 2
const THRUST := 3

var battle
var player

var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_index := -1
var look_last := Vector2.ZERO
var _look_start := Vector2.ZERO
var _look_t0 := 0
var _look_moved := 0.0
var _minimap: ImageTexture
const MAP_RECT := Rect2(14, 150, 196, 196)
var swing_index := -1 # finger holding a swing button
var block_index := -1

var message := ""
var message_time := 0.0
var restart_visible := false
var hurt_flash := 0.0
var hit_marker := 0.0
var block_flash := 0.0
var pressed_id := ""
var pressed_time := 0.0
var font: Font
var display: Font
var _box_cache := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = UI.font("alegreya_sans_500")
	display = UI.display_font()
	player.fired.connect(_on_fired)
	player.hurt.connect(_on_hurt)
	player.melee_hit.connect(_on_melee_hit)
	player.blocked.connect(_on_blocked)
	player.struck_shield.connect(_on_struck_shield)
	player.shot_hit.connect(func(): hit_marker = 0.35)
	player.friendly_fire.connect(_on_friendly_fire)


var story_speaker := ""
var story_text := ""
var story_time := 0.0


var hint_text := ""
var hint_time := 0.0


## A tutorial hint: a gold-edged box on the left, between the banner and
## the move stick.
func show_hint(text: String, seconds: float) -> void:
	hint_text = text
	hint_time = seconds


## A line of dialogue, shown as a subtitle in the lower middle of the screen.
func show_story(speaker: String, text: String, seconds: float) -> void:
	story_speaker = speaker
	story_text = text
	story_time = seconds


func show_message(text: String, seconds: float) -> void:
	message = text
	message_time = seconds


func show_restart() -> void:
	restart_visible = true


func _on_fired(hit: bool) -> void:
	if hit:
		hit_marker = 0.35


func _on_melee_hit(count: int) -> void:
	if count > 0:
		hit_marker = 0.35


func _on_blocked() -> void:
	block_flash = 0.5


var shield_flash := 0.0


func _on_struck_shield() -> void:
	shield_flash = 0.6


func _on_friendly_fire(by_you: bool) -> void:
	if by_you:
		show_message(Lang.t("You shot one of your own men!"), 2.0)
	else:
		show_message(Lang.t("Watch your fire! Hit by a ball from our own line."), 2.0)


func _on_hurt() -> void:
	hurt_flash = 1.0


func _melee() -> bool:
	return player.is_melee()


const WEAPON_LABELS := {"musket": "MUSKET", "melee": "BAYONET", "pistol": "PISTOL", "saber": "SABRE",
	"bow": "BOW", "crossbow": "CROSSBOW", "spyglass": "SPYGLASS"}


## The command view, once the army is yours to command (the prologue gives
## it to you partway).
func _field_ui():
	if battle.field != null and battle.field.ui != null and battle.can_command():
		return battle.field.ui
	return null


# ---------------------------------------------------------------- layout

func _buttons() -> Array:
	var s := size
	var list := []
	var c := Vector2(s.x - 150, s.y - 165)
	if _melee():
		# Four swing buttons in a diamond where FIRE was: the button you
		# press is where the blow comes from.
		var gap := 84.0
		list.append({"id": "swing0", "circle": true, "pos": c + Vector2(0, -gap), "r": 46.0, "label": Lang.t("OVER")})
		list.append({"id": "swing1", "circle": true, "pos": c + Vector2(-gap, 0), "r": 46.0, "label": Lang.t("LEFT")})
		list.append({"id": "swing2", "circle": true, "pos": c + Vector2(gap, 0), "r": 46.0, "label": Lang.t("RIGHT")})
		list.append({"id": "swing3", "circle": true, "pos": c + Vector2(0, gap), "r": 46.0, "label": Lang.t("THRUST")})
		list.append({"id": "block", "circle": true, "pos": Vector2(s.x - 310, s.y - 280), "r": 52.0, "label": Lang.t("BLOCK")})
	else:
		list.append({"id": "fire", "circle": true, "pos": c, "r": 80.0, "label": Lang.t("FIRE")})
		list.append({"id": "aim", "circle": true, "pos": Vector2(s.x - 215, s.y - 305), "r": 46.0, "label": Lang.t("AIM")})
	# A small button for every weapon you carry, along the very bottom.
	var ws: Array = player.weapons().duplicate()
	if _field_ui() != null:
		ws.append("spyglass")
	var ww := 118.0 if ws.size() <= 4 else 96.0
	var x0 := s.x * 0.5 - (ws.size() * (ww + 8.0) - 8.0) * 0.5 - 70.0 # clear of VOLLEY
	for i in ws.size():
		list.append({"id": "w_" + String(ws[i]), "circle": false, "rect": Rect2(x0 + i * (ww + 8.0), s.y - 48.0, ww, 40.0),
			"label": Lang.t(WEAPON_LABELS[ws[i]]), "small": true})
	list.append({"id": "grenade", "circle": true, "pos": Vector2(s.x - 470, s.y - 120), "r": 44.0,
		"label": Lang.t("GRENADE %d") % player.grenades})
	list.append({"id": "volley", "circle": true, "pos": Vector2(s.x - 335, s.y - 95), "r": 56.0, "label": Lang.t("VOLLEY!")})
	var bw := 150.0
	var bh := 56.0
	var y := 18.0
	var mode_label := Lang.t("AT WILL") if battle.is_at_will() else Lang.t("ON COMMAND")
	var fui = _field_ui()
	if fui != null:
		_army_buttons(list, fui, mode_label)
	else:
		list.append({"id": "follow", "circle": false, "rect": Rect2(s.x - 4 * (bw + 10), y, bw, bh), "label": Lang.t("FOLLOW")})
		list.append({"id": "hold", "circle": false, "rect": Rect2(s.x - 3 * (bw + 10), y, bw, bh), "label": Lang.t("HOLD")})
		list.append({"id": "charge", "circle": false, "rect": Rect2(s.x - 2 * (bw + 10), y, bw, bh), "label": Lang.t("CHARGE")})
		list.append({"id": "mode", "circle": false, "rect": Rect2(s.x - (bw + 10), y, bw, bh), "label": mode_label})
	list.append({"id": "menu", "circle": false, "rect": Rect2(20, 92, 110, 46), "label": Lang.t("MENU")})
	list.append({"id": "view", "circle": false, "rect": Rect2(140, 92, 150, 46),
			"label": Lang.t("3RD PERSON") if player.third_person else Lang.t("1ST PERSON")})
	if _field_ui() != null:
		list.append({"id": "command", "circle": false, "rect": Rect2(300, 92, 170, 46), "label": Lang.t("COMMAND")})
	if Settings.playground:
		# The range's own controls, down the left side.
		var pl := [["pg_still1", Lang.t("+1 TARGET")], ["pg_still5", Lang.t("+5 TARGETS")], ["pg_charge5", Lang.t("+5 CHARGING")],
			["pg_charge20", Lang.t("+20 CHARGING")], ["pg_clear", Lang.t("CLEAR")]]
		var gun_label := Lang.t("FIRE GUN")
		if battle.range_gun != null and not battle.range_gun.ready():
			gun_label = Lang.t("LOADING %d%%") % int(battle.range_gun.progress() * 100.0)
		pl.append(["pg_gun", gun_label])
		for i in pl.size():
			list.append({"id": pl[i][0], "circle": false, "rect": Rect2(20, 160 + i * 54, 170, 46), "label": pl[i][1]})
	if restart_visible:
		list.append({"id": "restart", "circle": false, "rect": Rect2(s.x * 0.5 - 130, s.y * 0.5 + 30, 260, 72),
			"label": Lang.t("CONTINUE") if Company.active else Lang.t("RESTART")})
	return list


## A field battle's top right: a card per regiment, and the orders row under
## it (the selection's, or your company's when nothing is selected).
func _army_buttons(list: Array, fui, mode_label: String) -> void:
	var s := size
	var regs: Array = fui._my_regs()
	var x0 := 486.0
	var avail := s.x - 14.0 - x0
	var cw := minf(100.0, (avail - 6.0 * (regs.size() - 1)) / maxf(1.0, regs.size()))
	var x := s.x - 14.0 - (cw + 6.0) * regs.size() + 6.0
	for r in regs:
		list.append({"id": "u_%d" % r.id, "circle": false, "rect": Rect2(x, 12, cw, 58), "label": "", "reg": r})
		x += cw + 6.0
	var row: Array = []
	if fui.selected.is_empty():
		row = [["follow", Lang.t("FOLLOW")], ["hold", Lang.t("HOLD")], ["charge", Lang.t("CHARGE")], ["mode", mode_label]]
	else:
		var r0 = fui.selected[0]
		row = [["o_halt", Lang.t("HALT")], ["o_charge", Lang.t("CHARGE")]]
		if fui.selected.any(func(r): return r.is_ranged()):
			row.append(["o_fire", Lang.t("FIRE: AT WILL") if r0.fire_at_will else Lang.t("FIRE: HOLD")])
			row.append(["o_volley", Lang.t("VOLLEY")])
		if fui.selected.any(func(r): return r.can_square()):
			row.append(["o_square", Lang.t("SQUARE") if not r0.square else Lang.t("IN SQUARE")])
		row.append(["o_run", Lang.t("RUN") if not r0.run else Lang.t("RUNNING")])
		row.append(["o_fallback", Lang.t("FALL BACK")])
		if fui.selected.size() == 1 and r0.player_led:
			row.append(["o_follow", Lang.t("FOLLOW ME")])
		row.append(["o_none", "✕"])
	# Right-aligned rows of order buttons, clear of the buttons on the left.
	var ow := 108.0
	var per := maxi(1, int((s.x - 14.0 - x0) / (ow + 6.0)))
	var i := 0
	while i < row.size():
		var chunk: Array = row.slice(i, i + per)
		var ox := s.x - 14.0 - (ow + 6.0) * chunk.size() + 6.0
		for k in chunk:
			list.append({"id": k[0], "circle": false, "rect": Rect2(ox, 78 + (i / per) * 50, ow, 44), "label": k[1]})
			ox += ow + 6.0
		i += per
	list.append({"id": "minimap", "circle": false, "rect": MAP_RECT, "label": ""})


func _hit(b: Dictionary, p: Vector2) -> bool:
	if b["circle"]:
		return p.distance_to(b["pos"]) <= float(b["r"]) * 1.12
	var r: Rect2 = b["rect"]
	return r.grow(10).has_point(p)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := make_input_local(event) as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := make_input_local(event) as InputEventScreenDrag
		if d.index == joy_index:
			joy_pos = d.position
		elif d.index == look_index:
			player.add_look(d.position - look_last)
			_look_moved = maxf(_look_moved, d.position.distance_to(_look_start))
			look_last = d.position


func _touch_down(idx: int, p: Vector2) -> void:
	for b in _buttons():
		if _hit(b, p):
			_press(b["id"], idx, p)
			return
	if p.x < size.x * 0.45 and p.y > size.y * 0.25 and joy_index == -1:
		joy_index = idx
		joy_origin = p
		joy_pos = p
	elif look_index == -1:
		look_index = idx
		look_last = p
		_look_start = p
		_look_t0 = Time.get_ticks_msec()
		_look_moved = 0.0


func _touch_up(idx: int) -> void:
	if idx == joy_index:
		joy_index = -1
		player.move_input = Vector2.ZERO
	if idx == look_index:
		look_index = -1
		# A quick tap in the world, with regiments selected: an order.
		var fui = _field_ui()
		if fui != null and _look_moved < 14.0 and Time.get_ticks_msec() - _look_t0 < 350 and swing_index == -1:
			fui.fp_tap(look_last)
	if idx == swing_index:
		swing_index = -1
		player.release_swing()
	if idx == block_index:
		block_index = -1
		player.set_block(false)


func _press(id: String, idx: int, p: Vector2) -> void:
	pressed_id = id
	pressed_time = 0.15
	match id:
		"swing0", "swing1", "swing2", "swing3":
			# Press to wind up, hold to charge, release to strike.
			if swing_index == -1 and player.begin_swing():
				player.set_swing_dir(int(id.substr(5)))
				swing_index = idx
				# Dragging from a swing button turns you, so you can track
				# a target while winding up.
				if look_index == -1:
					look_index = idx
					look_last = p
		"fire":
			player.request_fire()
			# Like CoD Mobile: the fire button also aims if you drag from it.
			if look_index == -1:
				look_index = idx
				look_last = p
		"weapon":
			player.toggle_weapon()
		"w_musket", "w_melee", "w_pistol", "w_saber", "w_bow", "w_crossbow":
			player.spyglass = false
			player.switch_to(id.substr(2))
		"w_spyglass":
			player.toggle_spyglass()
		"minimap":
			var fui = _field_ui()
			fui.open(false)
			fui.focus = _map_to_world(p)
		"o_halt", "o_charge", "o_fire", "o_volley", "o_run", "o_fallback", "o_follow", "o_square":
			_field_ui()._order(id.substr(2))
			battle.play_sound_ui("drum", -10.0)
		"o_none":
			_field_ui().selected = []
		"pg_still1":
			battle.playground_spawn(1, true)
		"pg_still5":
			battle.playground_spawn(5, true)
		"pg_charge5":
			battle.playground_spawn(5, false)
		"pg_charge20":
			battle.playground_spawn(20, false)
		"pg_clear":
			battle.playground_clear()
		"pg_gun":
			battle.fire_range_gun()
		"grenade":
			player.throw_grenade()
		"aim":
			player.toggle_aim()
		"block":
			block_index = idx
			player.set_block(true)
		"volley":
			battle.order_volley()
		"follow":
			battle.order_follow()
		"hold":
			battle.order_hold()
		"charge":
			battle.order_charge()
		"mode":
			battle.toggle_fire_mode()
		"restart":
			battle.finish()
		"menu":
			battle.to_menu()
		"view":
			player.toggle_view()
		"command":
			battle.field.ui.open(false)
		_:
			if id.begins_with("u_"):
				var fui2 = _field_ui()
				for r in battle.field.regs:
					if "u_%d" % r.id == id:
						fui2._toggle(r)


func _process(delta: float) -> void:
	if joy_index != -1:
		var v := (joy_pos - joy_origin) / JOY_RADIUS
		if v.length() > 1.0:
			v = v.normalized()
		player.move_input = v
	message_time -= delta
	story_time -= delta
	hint_time -= delta
	pressed_time -= delta
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 2.5)
	hit_marker = move_toward(hit_marker, 0.0, delta)
	block_flash = move_toward(block_flash, 0.0, delta)
	shield_flash = move_toward(shield_flash, 0.0, delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var s := size

	# Crosshair and hit marker.
	var c := s * 0.5
	if player.spyglass:
		_draw_spyglass(c)
	# First person: sighting down the barrel replaces the crosshair dot.
	# Third person has no barrel to sight along: aiming tightens a small
	# ring round the dot instead.
	if player.spyglass:
		pass
	elif player.third_person:
		draw_circle(c, 2.5, Color(1, 1, 1, 0.9))
		var r := lerpf(14.0, 6.0, player.aim_amount)
		draw_arc(c, r, 0.0, TAU, 24, Color(1, 1, 1, 0.35 + 0.45 * player.aim_amount), 1.5)
	else:
		var dot_a := 0.85 * (1.0 - clampf(player.aim_amount * 1.5, 0.0, 1.0))
		if dot_a > 0.01:
			draw_circle(c, 2.5, Color(1, 1, 1, dot_a))
	if hit_marker > 0.0:
		var a := hit_marker / 0.35
		var col := Color(1, 0.3, 0.2, a)
		draw_line(c + Vector2(-14, -14), c + Vector2(-6, -6), col, 3)
		draw_line(c + Vector2(14, -14), c + Vector2(6, -6), col, 3)
		draw_line(c + Vector2(-14, 14), c + Vector2(-6, 6), col, 3)
		draw_line(c + Vector2(14, 14), c + Vector2(6, 6), col, 3)
	_draw_swing_indicator(c)
	if block_flash > 0.0:
		_text_center(Lang.t("BLOCKED"), c + Vector2(0, 60), 30, Color(0.95, 0.78, 0.3, block_flash * 2.0))
	if shield_flash > 0.0:
		_text_center(Lang.t("SHIELD! charge your blow"), c + Vector2(0, 60), 26, Color(0.85, 0.85, 0.9, shield_flash * 1.8))

	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.7, 0.0, 0.0, 0.35 * hurt_flash))

	# Health bar and status, on a strip of night.
	var status: String = battle.status_line()
	var sw := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_style_box(_rbox(Color(UI.NIGHT, 0.55), Color(0, 0, 0, 0), 6), Rect2(12, 12, maxf(300.0, sw + 28.0), 66))
	draw_style_box(_rbox(Color(UI.WOOL_DARK, 0.9), Color(UI.PIPECLAY, 0.35), 4), Rect2(22, 22, 264, 18))
	var hpw := 262.0 * clampf(player.hp / player.max_hp, 0.0, 1.0)
	if hpw > 2.0:
		draw_style_box(_rbox(UI.MADDER.lightened(0.15), Color(0, 0, 0, 0), 3), Rect2(23, 23, hpw, 16))
	_text(status, Vector2(24, 64), 18, Color(UI.PIPECLAY, 0.95))
	if Settings.stress:
		var fps := Engine.get_frames_per_second()
		var fcol := Color(0.4, 1, 0.4) if fps >= 55 else (Color(1, 0.85, 0.3) if fps >= 30 else Color(1, 0.4, 0.3))
		_text(Lang.t("%d FPS   units %d") % [fps, battle.soldiers.size() + battle.enemies.size()], Vector2(310, 40), 26, fcol)

	# Move joystick.
	if joy_index != -1:
		draw_circle(joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 2)
		var knob := joy_origin + (joy_pos - joy_origin).limit_length(JOY_RADIUS)
		draw_circle(knob, 38, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(170, s.y - 170)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 2)
		_text_center(Lang.t("MOVE"), hint, 18, Color(1, 1, 1, 0.25))

	_draw_objective()
	if _field_ui() != null:
		_draw_minimap()

	for b in _buttons():
		_draw_button(b)
	var fui = _field_ui()
	if fui != null and not fui.selected.is_empty():
		_text_center(Lang.t("Tap an enemy regiment to send them at it  ·  tap the ground to march them there"), Vector2(s.x - 330, 194), 16, Color(UI.BRASS.lightened(0.25), 0.9))

	_draw_story()
	_draw_hint()

	# Message banner.
	if message_time > 0.0 and message != "":
		var alpha := clampf(message_time / 0.4, 0.0, 1.0)
		var mc := Vector2(s.x * 0.5, s.y * 0.3)
		_text_center(message, mc + Vector2(2, 3), 46, Color(0, 0, 0, 0.6 * alpha), display)
		_text_center(message, mc, 46, Color(UI.PIPECLAY, alpha), display)


## A gold marker over where you need to go (or an arrow at the edge of the
## screen if it's behind you), with its name and distance.
## The gold marker for where you should go (the fallen Major, the cliff
## path...). In view: a diamond over it, with its name and distance, and a
## small arrow bobbing down at it. Out of view (to the side, or behind
## you): a big arrow at the edge of the screen pointing the way to turn,
## "TURN LEFT/RIGHT" under it, pulsing so it can't be missed.
func _draw_objective() -> void:
	var obj: Dictionary = battle.objective
	if obj.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var world: Vector3 = obj["pos"] + Vector3.UP * float(obj.get("height", 2.4))
	var dist: float = player.global_position.distance_to(obj["pos"])
	var label := "%s  %d m" % [obj["label"], int(dist)]
	var gold := Color(0.95, 0.78, 0.3, 0.95)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	var margin := 90.0
	var local: Vector3 = cam.global_transform.affine_inverse() * world
	var in_view := false
	var p := Vector2.ZERO
	if not cam.is_position_behind(world):
		p = cam.unproject_position(world)
		in_view = p.x > margin and p.x < size.x - margin and p.y > margin and p.y < size.y - margin
	if in_view:
		var bob := 6.0 * pulse
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -14), p + Vector2(11, 0), p + Vector2(0, 14), p + Vector2(-11, 0)]), gold)
		var a := p + Vector2(0, -58 - bob)
		draw_colored_polygon(PackedVector2Array([a + Vector2(-13, -14), a + Vector2(13, -14), a + Vector2(0, 6)]), gold)
		_text_center(label, p + Vector2(2, -82 - bob), 20, Color(0, 0, 0, 0.6))
		_text_center(label, p + Vector2(0, -84 - bob), 20, gold)
		return
	# Off screen: which way to turn. (Behind you counts as whichever side
	# it's nearer; straight behind, the right.)
	# (Mostly sideways: it's which way to turn that matters, not up or down.)
	var dir := Vector2(local.x, clampf(-local.y, -absf(local.x), absf(local.x)) * 0.35)
	if local.z > 0.0:
		dir.x = (1.0 if local.x >= 0.0 else -1.0) * maxf(absf(dir.x), absf(local.z))
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	# Kept to the screen's sides (where your eye goes when turning), never
	# under the buttons along the top.
	var c := size * 0.5
	var half := Vector2(size.x * 0.5 - 70.0, size.y * 0.5 - 150.0)
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := c + dir * k
	var r := 34.0 + 8.0 * pulse
	var side := dir.orthogonal()
	var tri := PackedVector2Array([at + dir * r, at - dir * r * 0.6 + side * r * 0.8, at - dir * r * 0.6 - side * r * 0.8])
	draw_colored_polygon(tri, Color(0, 0, 0, 0.45))
	var tri2 := PackedVector2Array([at + dir * (r - 5.0), at - dir * (r - 5.0) * 0.6 + side * (r - 5.0) * 0.8, at - dir * (r - 5.0) * 0.6 - side * (r - 5.0) * 0.8])
	draw_colored_polygon(tri2, gold)
	var turn := Lang.t("TURN RIGHT") if dir.x > 0.0 else Lang.t("TURN LEFT")
	var tp := at - dir * (r + 34.0) + Vector2(0, 6)
	tp.x = clampf(tp.x, 160.0, size.x - 160.0)
	_text_center(label, tp + Vector2(2, 2), 20, Color(0, 0, 0, 0.6))
	_text_center(label, tp, 20, gold)
	_text_center(turn, tp + Vector2(0, 24), 17, Color(gold, 0.7 + 0.3 * pulse))


func _draw_hint() -> void:
	if hint_time <= 0.0 or hint_text == "":
		return
	var alpha := clampf(hint_time / 0.5, 0.0, 1.0)
	var w := 430.0
	var fsize := 18
	var tsize := font.get_multiline_string_size(hint_text, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, fsize)
	var r := Rect2(20, 262, w, tsize.y + 40.0)
	draw_style_box(_rbox(Color(UI.WOOL, 0.85 * alpha), Color(UI.BRASS, 0.7 * alpha), 6), r)
	draw_string(display, Vector2(32, 286), Lang.t("How to"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UI.BRASS, alpha))
	draw_multiline_string(font, Vector2(32, 308), hint_text, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, fsize, -1,
		Color(1, 1, 1, alpha))


## Dialogue subtitle: who's speaking in gold, the line in white, on a band.
func _draw_story() -> void:
	if story_time <= 0.0 or story_text == "":
		return
	var alpha := clampf(story_time / 0.4, 0.0, 1.0)
	var w := minf(760.0, size.x - 80.0)
	var x := (size.x - w) * 0.5
	var y := size.y * 0.56
	var fsize := 24
	var lines := font.get_multiline_string_size(story_text, HORIZONTAL_ALIGNMENT_CENTER, w - 32.0, fsize)
	var h := lines.y + (34.0 if story_speaker != "" else 0.0) + 24.0
	draw_rect(Rect2(x, y, w, h), Color(0.04, 0.05, 0.08, 0.62 * alpha))
	var ty := y + 12.0
	if story_speaker != "":
		_text_center(story_speaker.to_upper(), Vector2(size.x * 0.5, ty + 12.0), 20, Color(0.95, 0.78, 0.3, alpha))
		ty += 34.0
	draw_multiline_string(font, Vector2(x + 16.0, ty + fsize * 0.8), story_text, HORIZONTAL_ALIGNMENT_CENTER,
		w - 32.0, fsize, -1, Color(1, 1, 1, alpha))


## Gold marker by the crosshair on the side the blow will come from.
func _draw_swing_indicator(c: Vector2) -> void:
	if not _melee() or player.swing_phase != "windup":
		return
	var gold := Color(0.95, 0.78, 0.3, 0.9)
	match player.swing_dir:
		OVERHEAD:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -48), c + Vector2(12, -48), c + Vector2(0, -32)]), gold)
		LEFT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-48, -12), c + Vector2(-48, 12), c + Vector2(-32, 0)]), gold)
		RIGHT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(48, -12), c + Vector2(48, 12), c + Vector2(32, 0)]), gold)
		THRUST:
			draw_arc(c, 16, 0, TAU, 32, gold, 3)
		_:
			draw_arc(c, 16, 0, TAU, 32, Color(1, 1, 1, 0.3), 2)


## A rounded box for drawing (cached by its colours and radius).
func _rbox(bg: Color, edge: Color, radius: int, width := 1) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d" % [bg.to_html(), edge.to_html(), radius, width]
	if _box_cache.has(key):
		return _box_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if edge.a > 0.0:
		sb.border_color = edge
		sb.set_border_width_all(width)
	_box_cache[key] = sb
	return sb


func _draw_button(b: Dictionary) -> void:
	var id: String = b["id"]
	if id == "minimap":
		return
	if id.begins_with("u_"):
		_draw_unit_card(b)
		return
	var bg := Color(UI.NIGHT, 0.5)
	var edge := Color(UI.PIPECLAY, 0.6)
	var label_col := Color(UI.PIPECLAY, 0.95)
	var active: bool = (id == "follow" and battle.is_following()) \
		or (id == "hold" and battle.is_holding()) \
		or (id == "charge" and battle.is_charging()) \
		or (id == "block" and player.blocking) \
		or (id == "aim" and player.aim_wanted)
	if active:
		edge = UI.BRASS
		label_col = UI.BRASS.lightened(0.2)
		bg = Color(UI.WOOL, 0.75)
	if id == pressed_id and pressed_time > 0.0:
		bg = Color(UI.MADDER, 0.75)
	if id == "volley" and battle.loaded_count() == 0:
		label_col = Color(1, 1, 1, 0.35)
	if id in ["volley", "follow", "hold", "charge", "mode"] and not battle.can_command():
		label_col = Color(1, 1, 1, 0.3)
		edge = Color(1, 1, 1, 0.25)
	if id == "grenade" and (player.grenades == 0 or player.is_throwing()):
		label_col = Color(1, 1, 1, 0.35)
	var swinging: bool = id.begins_with("swing") and player.swing_phase != "idle" \
		and int(id.substr(5)) == player.swing_dir
	if swinging:
		edge = Color(0.95, 0.78, 0.3)
		label_col = Color(0.95, 0.78, 0.3)
		bg = Color(0.95, 0.78, 0.3, 0.25)

	if b["circle"]:
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		draw_circle(pos, r, bg)
		draw_arc(pos, r, 0, TAU, 48, edge, 2.5, true)
		var label: String = b["label"]
		if id == "fire" and not _melee() and not player.is_loaded():
			# Reload ring fills up around the fire button.
			var prog: float = player.reload_progress_of(player.weapon)
			draw_arc(pos, r + 9, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, Color(0.95, 0.78, 0.3), 7)
			label = {"bow": Lang.t("NOCKING"), "crossbow": Lang.t("SPANNING")}.get(player.weapon, Lang.t("LOADING"))
			label_col = Color(1, 1, 1, 0.5)
		if swinging and player.swing_phase == "windup":
			# Charge ring fills while you hold; white when fully charged.
			var ch: float = player.charge()
			var ring := Color(1, 1, 1) if ch >= 1.0 else Color(0.95, 0.78, 0.3)
			draw_arc(pos, r + 8, -PI * 0.5, -PI * 0.5 + TAU * ch, 40, ring, 6)
		if id == "weapon" and player.is_switching():
			label_col = Color(1, 1, 1, 0.4)
		var fsize := 24 if id == "fire" else (16 if id == "weapon" or id == "grenade" or id.begins_with("swing") else 20)
		_text_center(label, pos, fsize, label_col)
	else:
		var rect: Rect2 = b["rect"]
		if id.begins_with("w_"):
			# The weapon in hand is gold; the one you're switching to pulses.
			var w := id.substr(2)
			var gold := UI.BRASS
			if w == "spyglass":
				if player.spyglass:
					bg = Color(gold, 0.3)
					edge = gold
					label_col = gold
				draw_style_box(_rbox(bg, Color(edge, edge.a * 0.8), 5, 2 if player.spyglass else 1), rect)
				_text_center(b["label"], rect.get_center(), 16, label_col)
				return
			if w == player.weapon and not player.is_switching() and not player.spyglass:
				bg = Color(gold, 0.3)
				edge = gold
				label_col = gold
			elif player.is_switching() and w == player.switch_target:
				edge = Color(gold, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
			# Unloaded guns show how far through the reload they are.
			var prog := 1.0
			if w in ["musket", "pistol", "bow", "crossbow"]:
				prog = player.reload_progress_of(w)
			draw_style_box(_rbox(bg, Color(edge, edge.a * 0.8), 5, 2 if w == player.weapon else 1), rect)
			if prog < 1.0:
				draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 6), Vector2((rect.size.x - 8) * prog, 3)), Color(gold, 0.85))
			_text_center(b["label"], rect.get_center(), 16, label_col)
			return
		draw_style_box(_rbox(bg, Color(edge, edge.a * 0.8), 5, 2 if active else 1), rect)
		_text_center(b["label"], rect.get_center(), 19, label_col)


# ---------------------------------------------------------------- field battle extras

const MAP_BLUE := Color(0.55, 0.72, 1.0)
const MAP_RED := Color(1.0, 0.45, 0.38)


## A regiment's card in the top bar: its kind, men left, its nerve as a
## coloured edge along the bottom; brass when selected.
func _draw_unit_card(b: Dictionary) -> void:
	var r = b["reg"]
	var rect: Rect2 = b["rect"]
	var fui = _field_ui()
	var sel: bool = r in fui.selected
	var bg := Color(UI.NIGHT, 0.6) if not sel else Color(UI.WOOL_LIGHT, 0.92)
	if r.broken():
		bg = Color(0.3, 0.08, 0.06, 0.7)
	draw_style_box(_rbox(bg, UI.BRASS if sel else Color(UI.PIPECLAY, 0.4), 5, 2 if sel else 1), rect)
	var lab := Lang.t(String(r.info["short"])) + ("★" if r.player_led else "")
	_text_center(lab, rect.get_center() + Vector2(0, -12), 15 if rect.size.x > 80 else 13, UI.BRASS.lightened(0.2) if sel else Color(UI.PIPECLAY, 0.95))
	var st := "%d" % r.members.size()
	match r.state:
		"wavering": st = Lang.t("WAVERING")
		"routing", "shattered": st = Lang.t("RUNNING")
	if r.engaged() and not r.broken():
		st += " ⚔"
	_text_center(st, rect.get_center() + Vector2(0, 8), 13, Color(1.0, 0.75, 0.35) if r.state == "wavering" else Color(UI.PIPECLAY, 0.75))
	var m: float = clampf(r.morale / maxf(1.0, r.max_morale), 0.0, 1.0)
	var bar := Rect2(rect.position + Vector2(5, rect.size.y - 8), Vector2((rect.size.x - 10) * r.strength(), 4))
	draw_rect(bar, Color(0.45, 0.75, 0.4).lerp(Color(0.9, 0.3, 0.2), 1.0 - m))


## The minimap: the ground (hills shaded, water, houses, woods), every
## regiment as its block, you as an arrow. North (the enemy's side) is up.
func _draw_minimap() -> void:
	var f = battle.field
	if _minimap == null:
		_minimap = ImageTexture.create_from_image(f.terrain.minimap_image(int(MAP_RECT.size.x)))
	draw_style_box(_rbox(Color(UI.NIGHT, 0.6), Color(UI.PIPECLAY, 0.45), 4), MAP_RECT.grow(3))
	draw_texture_rect(_minimap, MAP_RECT, false, Color(1, 1, 1, 0.85))
	var fui = _field_ui()
	for r in f.regs:
		if r.gone() or r.members.is_empty():
			continue
		var col: Color = MAP_BLUE if r.side == 0 else MAP_RED
		if r in fui.selected:
			col = UI.BRASS.lightened(0.3)
		if r.broken():
			col = col.darkened(0.45)
		var hw: float = maxf(3.0, r.width() * 0.5 + 1.0)
		var hd: float = maxf(2.5, ceilf(float(r.members.size()) / r.files_now()) * r.rank_gap * 0.5)
		var pts := PackedVector2Array()
		for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var w: Vector3 = r.centroid + r.right() * hw * k[0] + r.forward * hd * k[1]
			pts.append(_world_to_map(w))
		draw_colored_polygon(pts, col)
	if player.alive:
		var pp := _world_to_map(player.global_position)
		var fwd: Vector3 = -player.global_transform.basis.z
		var d := Vector2(fwd.x, fwd.z).normalized()
		var sd := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([pp + d * 8.0, pp - d * 5.0 + sd * 5.0, pp - d * 5.0 - sd * 5.0]), Color.WHITE)
	_text(Lang.t(" MAP · tap for command"), MAP_RECT.position + Vector2(0, MAP_RECT.size.y + 18), 13, Color(UI.PIPECLAY, 0.6))


func _world_to_map(w: Vector3) -> Vector2:
	var half: float = battle.field.terrain.HALF
	return MAP_RECT.position + Vector2((w.x + half) / (half * 2.0), (w.z + half) / (half * 2.0)) * MAP_RECT.size


func _map_to_world(p: Vector2) -> Vector3:
	var half: float = battle.field.terrain.HALF
	var k := (p - MAP_RECT.position) / MAP_RECT.size
	return Vector3(k.x * half * 2.0 - half, 0, k.y * half * 2.0 - half)


## Through the spyglass: a circle of the world in black, a brass rim and a
## faint cross.
func _draw_spyglass(c: Vector2) -> void:
	var rad := minf(size.x, size.y) * 0.44
	var w := size.x
	draw_arc(c, rad + w * 0.5, 0.0, TAU, 96, Color(0.02, 0.02, 0.03), w)
	draw_arc(c, rad + 3.0, 0.0, TAU, 96, Color(UI.BRASS, 0.85), 6.0)
	draw_line(c + Vector2(-rad * 0.15, 0), c + Vector2(rad * 0.15, 0), Color(0, 0, 0, 0.5), 1.5)
	draw_line(c + Vector2(0, -rad * 0.15), c + Vector2(0, rad * 0.15), Color(0, 0, 0, 0.5), 1.5)


func _text(t: String, pos: Vector2, fsize: int, col: Color) -> void:
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _text_center(t: String, centre: Vector2, fsize: int, col: Color, f: Font = null) -> void:
	if f == null:
		f = font
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	# Keep labels on screen even when a control sits near the edge.
	var x := clampf(centre.x - w * 0.5, 6.0, size.x - w - 6.0)
	draw_string(f, Vector2(x, centre.y + fsize * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
