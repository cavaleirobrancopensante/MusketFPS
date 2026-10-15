extends Control
## Touch HUD, Call of Duty Mobile style:
##   left side  - floating move joystick (appears where your thumb lands)
##   right side - drag anywhere to look
##   FIRE       - fires your musket; keep dragging from it to aim while firing
##   VOLLEY!    - the company fires every loaded musket
##   top right  - FOLLOW / HOLD / fire mode toggle
## Also draws the first-person musket as a 2D overlay (Doom-style viewmodel).
##
## Touches are handled by hand (not Buttons) so several fingers work at once.

const JOY_RADIUS := 90.0

var battle
var player

var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_index := -1
var look_last := Vector2.ZERO

var message := ""
var message_time := 0.0
var restart_visible := false
var recoil := 0.0
var flash := 0.0
var hurt_flash := 0.0
var hit_marker := 0.0
var pressed_id := ""
var pressed_time := 0.0
var font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	player.fired.connect(_on_fired)
	player.hurt.connect(_on_hurt)


func show_message(text: String, seconds: float) -> void:
	message = text
	message_time = seconds


func show_restart() -> void:
	restart_visible = true


func _on_fired(hit: bool) -> void:
	recoil = 1.0
	flash = 1.0
	if hit:
		hit_marker = 0.35


func _on_hurt() -> void:
	hurt_flash = 1.0


# ---------------------------------------------------------------- layout

func _buttons() -> Array:
	var s := size
	var list := []
	list.append({"id": "fire", "circle": true, "pos": Vector2(s.x - 140, s.y - 150), "r": 80.0, "label": "FIRE"})
	list.append({"id": "volley", "circle": true, "pos": Vector2(s.x - 305, s.y - 105), "r": 58.0, "label": "VOLLEY!"})
	var bw := 160.0
	var bh := 56.0
	var y := 18.0
	var mode_label := "AT WILL" if battle.is_at_will() else "ON COMMAND"
	list.append({"id": "follow", "circle": false, "rect": Rect2(s.x - 3 * (bw + 10), y, bw, bh), "label": "FOLLOW"})
	list.append({"id": "hold", "circle": false, "rect": Rect2(s.x - 2 * (bw + 10), y, bw, bh), "label": "HOLD"})
	list.append({"id": "mode", "circle": false, "rect": Rect2(s.x - (bw + 10), y, bw, bh), "label": mode_label})
	if restart_visible:
		list.append({"id": "restart", "circle": false, "rect": Rect2(s.x * 0.5 - 130, s.y * 0.5 + 30, 260, 72), "label": "RESTART"})
	return list


func _hit(b: Dictionary, p: Vector2) -> bool:
	if b["circle"]:
		return p.distance_to(b["pos"]) <= float(b["r"]) * 1.15
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


func _press(id: String, idx: int, p: Vector2) -> void:
	pressed_id = id
	pressed_time = 0.15
	match id:
		"fire":
			player.request_fire()
			# Like CoD Mobile: the fire button also aims if you drag from it.
			if look_index == -1:
				look_index = idx
				look_last = p
		"volley":
			battle.order_volley()
		"follow":
			battle.order_follow()
		"hold":
			battle.order_hold()
		"mode":
			battle.toggle_fire_mode()
		"restart":
			battle.restart()


func _process(delta: float) -> void:
	if joy_index != -1:
		var v := (joy_pos - joy_origin) / JOY_RADIUS
		if v.length() > 1.0:
			v = v.normalized()
		player.move_input = v
	message_time -= delta
	pressed_time -= delta
	recoil = move_toward(recoil, 0.0, delta * 4.0)
	flash = move_toward(flash, 0.0, delta * 14.0)
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 2.5)
	hit_marker = move_toward(hit_marker, 0.0, delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var s := size
	_draw_musket(s)

	# Crosshair and hit marker.
	var c := s * 0.5
	draw_circle(c, 2.5, Color(1, 1, 1, 0.85))
	if hit_marker > 0.0:
		var a := hit_marker / 0.35
		var col := Color(1, 0.3, 0.2, a)
		draw_line(c + Vector2(-14, -14), c + Vector2(-6, -6), col, 3)
		draw_line(c + Vector2(14, -14), c + Vector2(6, -6), col, 3)
		draw_line(c + Vector2(-14, 14), c + Vector2(-6, 6), col, 3)
		draw_line(c + Vector2(14, 14), c + Vector2(6, 6), col, 3)

	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.7, 0.0, 0.0, 0.35 * hurt_flash))

	# Health bar and status.
	draw_rect(Rect2(20, 20, 264, 24), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(22, 22, 260.0 * player.hp / player.max_hp, 20), Color(0.8, 0.15, 0.1))
	var status := "Wave %d/%d   Lizardmen %d   Company %d   Loaded %d" % [
		battle.wave, battle.WAVES.size(), battle.enemies.size(), battle.soldiers.size(), battle.loaded_count()]
	_text(status, Vector2(22, 72), 20, Color(1, 1, 1, 0.9))

	# Joystick.
	if joy_index != -1:
		draw_circle(joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 2)
		var knob := joy_origin + (joy_pos - joy_origin).limit_length(JOY_RADIUS)
		draw_circle(knob, 38, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(170, s.y - 170)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 2)
		_text_center("MOVE", hint, 18, Color(1, 1, 1, 0.25))

	for b in _buttons():
		_draw_button(b)

	# Message banner.
	if message_time > 0.0 and message != "":
		var alpha := clampf(message_time / 0.4, 0.0, 1.0)
		var mc := Vector2(s.x * 0.5, s.y * 0.3)
		_text_center(message, mc + Vector2(2, 2), 40, Color(0, 0, 0, 0.6 * alpha))
		_text_center(message, mc, 40, Color(1, 0.93, 0.75, alpha))


func _draw_musket(s: Vector2) -> void:
	if not player.alive:
		return
	var lower: float = player.reload_lowered()
	var off := Vector2(30, 55) * recoil + Vector2(60, 300) * lower
	var butt := Vector2(s.x * 0.82, s.y + 50) + off
	var lock := Vector2(s.x * 0.71, s.y * 0.82) + off
	var tip := Vector2(s.x * 0.59, s.y * 0.6) + off
	var stock := Color(0.36, 0.21, 0.1)
	var fore := Color(0.44, 0.27, 0.13)
	var steel := Color(0.58, 0.6, 0.64)
	draw_line(lock, tip, steel, 10)
	draw_line(lock, lock.lerp(tip, 0.7), fore, 18)
	draw_line(butt, lock, stock, 36)
	draw_circle(lock + Vector2(-4, -18), 10, Color(0.28, 0.28, 0.3)) # lock plate
	draw_line(lock + Vector2(-4, -18), lock + Vector2(8, -34), Color(0.2, 0.2, 0.22), 5) # hammer
	if flash > 0.0:
		var dir := (tip - lock).normalized()
		draw_circle(tip + dir * 22, 34 * flash, Color(1, 0.72, 0.25, flash))
		draw_circle(tip + dir * 18, 16 * flash, Color(1, 1, 0.85, flash))


func _draw_button(b: Dictionary) -> void:
	var id: String = b["id"]
	var bg := Color(0.08, 0.09, 0.12, 0.5)
	var edge := Color(1, 1, 1, 0.7)
	var label_col := Color(1, 1, 1, 0.95)
	var active: bool = (id == "follow" and battle.is_following()) or (id == "hold" and not battle.is_following())
	if active:
		edge = Color(0.95, 0.78, 0.3)
		label_col = Color(0.95, 0.78, 0.3)
	if id == pressed_id and pressed_time > 0.0:
		bg = Color(1, 1, 1, 0.35)
	if id == "volley" and battle.loaded_count() == 0:
		label_col = Color(1, 1, 1, 0.35)

	if b["circle"]:
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		draw_circle(pos, r, bg)
		draw_arc(pos, r, 0, TAU, 48, edge, 3)
		var label: String = b["label"]
		if id == "fire" and not player.loaded:
			# Reload ring fills up around the fire button.
			draw_arc(pos, r + 9, -PI * 0.5, -PI * 0.5 + TAU * player.reload_progress(), 48, Color(0.95, 0.78, 0.3), 7)
			label = "LOADING"
			label_col = Color(1, 1, 1, 0.5)
		_text_center(label, pos, 24 if id == "fire" else 20, label_col)
	else:
		var rect: Rect2 = b["rect"]
		draw_rect(rect, bg)
		draw_rect(rect, edge, false, 2)
		_text_center(b["label"], rect.get_center(), 20, label_col)


func _text(t: String, pos: Vector2, fsize: int, col: Color) -> void:
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _text_center(t: String, centre: Vector2, fsize: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, centre + Vector2(-w * 0.5, fsize * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
