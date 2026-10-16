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
## Touches are handled by hand (not Buttons) so several fingers work at once.

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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
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
		show_message("You shot one of your own men!", 2.0)
	else:
		show_message("Watch your fire! Hit by a ball from our own line.", 2.0)


func _on_hurt() -> void:
	hurt_flash = 1.0


func _melee() -> bool:
	return player.weapon == "melee"


# ---------------------------------------------------------------- layout

func _buttons() -> Array:
	var s := size
	var list := []
	var c := Vector2(s.x - 150, s.y - 165)
	if _melee():
		# Four swing buttons in a diamond where FIRE was: the button you
		# press is where the blow comes from.
		var gap := 84.0
		list.append({"id": "swing0", "circle": true, "pos": c + Vector2(0, -gap), "r": 46.0, "label": "OVER"})
		list.append({"id": "swing1", "circle": true, "pos": c + Vector2(-gap, 0), "r": 46.0, "label": "LEFT"})
		list.append({"id": "swing2", "circle": true, "pos": c + Vector2(gap, 0), "r": 46.0, "label": "RIGHT"})
		list.append({"id": "swing3", "circle": true, "pos": c + Vector2(0, gap), "r": 46.0, "label": "THRUST"})
		list.append({"id": "block", "circle": true, "pos": Vector2(s.x - 310, s.y - 280), "r": 52.0, "label": "BLOCK"})
	else:
		list.append({"id": "fire", "circle": true, "pos": c, "r": 80.0, "label": "FIRE"})
		list.append({"id": "aim", "circle": true, "pos": Vector2(s.x - 215, s.y - 305), "r": 46.0, "label": "AIM"})
	list.append({"id": "weapon", "circle": true, "pos": Vector2(s.x - 58, s.y - 330), "r": 46.0,
		"label": "MUSKET" if _melee() else "BAYONET"})
	list.append({"id": "grenade", "circle": true, "pos": Vector2(s.x - 470, s.y - 120), "r": 44.0,
		"label": "GRENADE %d" % player.grenades})
	list.append({"id": "volley", "circle": true, "pos": Vector2(s.x - 335, s.y - 95), "r": 56.0, "label": "VOLLEY!"})
	var bw := 150.0
	var bh := 56.0
	var y := 18.0
	var mode_label := "AT WILL" if battle.is_at_will() else "ON COMMAND"
	list.append({"id": "follow", "circle": false, "rect": Rect2(s.x - 4 * (bw + 10), y, bw, bh), "label": "FOLLOW"})
	list.append({"id": "hold", "circle": false, "rect": Rect2(s.x - 3 * (bw + 10), y, bw, bh), "label": "HOLD"})
	list.append({"id": "charge", "circle": false, "rect": Rect2(s.x - 2 * (bw + 10), y, bw, bh), "label": "CHARGE"})
	list.append({"id": "mode", "circle": false, "rect": Rect2(s.x - (bw + 10), y, bw, bh), "label": mode_label})
	list.append({"id": "menu", "circle": false, "rect": Rect2(20, 92, 110, 46), "label": "MENU"})
	list.append({"id": "view", "circle": false, "rect": Rect2(140, 92, 150, 46),
			"label": "3RD PERSON" if player.third_person else "1ST PERSON"})
	if restart_visible:
		list.append({"id": "restart", "circle": false, "rect": Rect2(s.x * 0.5 - 130, s.y * 0.5 + 30, 260, 72),
			"label": "CONTINUE" if Company.active else "RESTART"})
	return list


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


func _touch_up(idx: int) -> void:
	if idx == joy_index:
		joy_index = -1
		player.move_input = Vector2.ZERO
	if idx == look_index:
		look_index = -1
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
	# Sighting down the barrel replaces the crosshair dot.
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
		_text_center("BLOCKED", c + Vector2(0, 60), 30, Color(0.95, 0.78, 0.3, block_flash * 2.0))
	if shield_flash > 0.0:
		_text_center("SHIELD! charge your blow", c + Vector2(0, 60), 26, Color(0.85, 0.85, 0.9, shield_flash * 1.8))

	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.7, 0.0, 0.0, 0.35 * hurt_flash))

	# Health bar and status.
	draw_rect(Rect2(20, 20, 264, 24), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(22, 22, 260.0 * player.hp / player.max_hp, 20), Color(0.8, 0.15, 0.1))
	_text(battle.status_line(), Vector2(22, 72), 20, Color(1, 1, 1, 0.9))
	if Settings.stress:
		var fps := Engine.get_frames_per_second()
		var fcol := Color(0.4, 1, 0.4) if fps >= 55 else (Color(1, 0.85, 0.3) if fps >= 30 else Color(1, 0.4, 0.3))
		_text("%d FPS   units %d" % [fps, battle.soldiers.size() + battle.enemies.size()], Vector2(310, 40), 26, fcol)

	# Move joystick.
	if joy_index != -1:
		draw_circle(joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 2)
		var knob := joy_origin + (joy_pos - joy_origin).limit_length(JOY_RADIUS)
		draw_circle(knob, 38, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(170, s.y - 170)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 2)
		_text_center("MOVE", hint, 18, Color(1, 1, 1, 0.25))

	_draw_objective()

	for b in _buttons():
		_draw_button(b)

	_draw_story()
	_draw_hint()

	# Message banner.
	if message_time > 0.0 and message != "":
		var alpha := clampf(message_time / 0.4, 0.0, 1.0)
		var mc := Vector2(s.x * 0.5, s.y * 0.3)
		_text_center(message, mc + Vector2(2, 2), 40, Color(0, 0, 0, 0.6 * alpha))
		_text_center(message, mc, 40, Color(1, 0.93, 0.75, alpha))


## A gold marker over where you need to go (or an arrow at the edge of the
## screen if it's behind you), with its name and distance.
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
	var margin := 70.0
	if not cam.is_position_behind(world):
		var p := cam.unproject_position(world)
		p.x = clampf(p.x, margin, size.x - margin)
		p.y = clampf(p.y, margin + 60.0, size.y - margin)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -14), p + Vector2(11, 0), p + Vector2(0, 14), p + Vector2(-11, 0)]), gold)
		_text_center(label, p + Vector2(2, -30), 20, Color(0, 0, 0, 0.6))
		_text_center(label, p + Vector2(0, -32), 20, gold)
		return
	# Behind you: an arrow at the bottom of the screen, toward the side it's on.
	var local: Vector3 = cam.global_transform.affine_inverse() * world
	var x := size.x * 0.5 + clampf(local.x * 8.0, -size.x * 0.3, size.x * 0.3)
	var p2 := Vector2(x, size.y - 40.0)
	draw_colored_polygon(PackedVector2Array([p2 + Vector2(-16, -10), p2 + Vector2(16, -10), p2 + Vector2(0, 10)]), gold)
	_text_center(label + "  (behind you)", p2 + Vector2(0, -30), 20, gold)


func _draw_hint() -> void:
	if hint_time <= 0.0 or hint_text == "":
		return
	var alpha := clampf(hint_time / 0.5, 0.0, 1.0)
	var w := 430.0
	var fsize := 18
	var tsize := font.get_multiline_string_size(hint_text, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, fsize)
	var r := Rect2(20, 262, w, tsize.y + 40.0)
	draw_rect(r, Color(0.05, 0.06, 0.1, 0.72 * alpha))
	draw_rect(r, Color(0.95, 0.78, 0.3, 0.8 * alpha), false, 2)
	_text("HOW TO", Vector2(32, 284), 15, Color(0.95, 0.78, 0.3, alpha))
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


func _draw_button(b: Dictionary) -> void:
	var id: String = b["id"]
	var bg := Color(0.08, 0.09, 0.12, 0.5)
	var edge := Color(1, 1, 1, 0.7)
	var label_col := Color(1, 1, 1, 0.95)
	var active: bool = (id == "follow" and battle.is_following()) \
		or (id == "hold" and battle.is_holding()) \
		or (id == "charge" and battle.is_charging()) \
		or (id == "block" and player.blocking) \
		or (id == "aim" and player.aim_wanted)
	if active:
		edge = Color(0.95, 0.78, 0.3)
		label_col = Color(0.95, 0.78, 0.3)
	if id == pressed_id and pressed_time > 0.0:
		bg = Color(1, 1, 1, 0.35)
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
		draw_arc(pos, r, 0, TAU, 48, edge, 3)
		var label: String = b["label"]
		if id == "fire" and not _melee() and not player.loaded:
			# Reload ring fills up around the fire button.
			draw_arc(pos, r + 9, -PI * 0.5, -PI * 0.5 + TAU * player.reload_progress(), 48, Color(0.95, 0.78, 0.3), 7)
			label = "LOADING"
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
		draw_rect(rect, bg)
		draw_rect(rect, edge, false, 2)
		_text_center(b["label"], rect.get_center(), 20, label_col)


func _text(t: String, pos: Vector2, fsize: int, col: Color) -> void:
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _text_center(t: String, centre: Vector2, fsize: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	# Keep labels on screen even when a control sits near the edge.
	var x := clampf(centre.x - w * 0.5, 6.0, size.x - w - 6.0)
	draw_string(font, Vector2(x, centre.y + fsize * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
