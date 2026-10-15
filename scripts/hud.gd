extends Control
## Touch HUD, Call of Duty Mobile style:
##   left side  - floating move joystick (appears where your thumb lands)
##   right side - drag anywhere to look
##   FIRE       - fires your musket; keep dragging from it to aim while firing
##   BAYONET    - switch to melee; the FIRE button becomes the SWING joystick:
##                press to wind up, drag up/left/right/down to choose where the
##                blow comes from, release to strike (hold longer = heavier)
##   BLOCK      - hold to parry (melee only)
##   VOLLEY!    - the company fires every loaded musket
##   top right  - FOLLOW / HOLD / fire mode toggle
## Also draws your weapon as a 2D overlay (Doom-style viewmodel).
##
## Touches are handled by hand (not Buttons) so several fingers work at once.

const JOY_RADIUS := 90.0
const SWING_RADIUS := 70.0
const SWING_DEADZONE := 26.0

# Swing directions (same values as player.gd's Swing enum).
const NONE := -1
const OVERHEAD := 0
const LEFT := 1
const RIGHT := 2
const THRUST := 3

# Viewmodel poses: [grip position as a fraction of the screen, angle, scale].
# The angle is where the muzzle points, in screen space (0 = right, -PI/2 = up).
const POSE_MUSKET := [Vector2(0.71, 0.82), -2.34, 1.0]
const POSE_MELEE_IDLE := [Vector2(0.70, 0.88), -2.25, 1.0]
const POSE_BLOCK := [Vector2(0.55, 0.80), -3.05, 1.0]
const POSE_WINDUP := {
	OVERHEAD: [Vector2(0.62, 0.50), -1.75, 1.0],
	LEFT: [Vector2(0.20, 0.80), -0.75, 1.0],
	RIGHT: [Vector2(0.88, 0.74), -2.45, 1.0],
	THRUST: [Vector2(0.78, 1.00), -2.3, 0.85],
}
const POSE_STRIKE := {
	OVERHEAD: [Vector2(0.62, 1.02), -2.6, 1.0],
	LEFT: [Vector2(0.86, 0.84), -2.6, 1.0],
	RIGHT: [Vector2(0.18, 0.86), -0.6, 1.0],
	THRUST: [Vector2(0.60, 0.72), -2.3, 1.18],
}

var battle
var player

var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_index := -1
var look_last := Vector2.ZERO
var swing_index := -1
var swing_origin := Vector2.ZERO
var swing_pos := Vector2.ZERO
var block_index := -1

var message := ""
var message_time := 0.0
var restart_visible := false
var recoil := 0.0
var flash := 0.0
var hurt_flash := 0.0
var hit_marker := 0.0
var block_flash := 0.0
var pressed_id := ""
var pressed_time := 0.0
var font: Font

# Smoothed viewmodel pose.
var pose_grip := Vector2(0.71, 0.82)
var pose_angle := -2.34
var pose_scale := 1.0
var trail: Array = [] # recent bayonet-tip positions during a strike


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	player.fired.connect(_on_fired)
	player.hurt.connect(_on_hurt)
	player.melee_hit.connect(_on_melee_hit)
	player.blocked.connect(_on_blocked)


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


func _on_melee_hit(count: int) -> void:
	if count > 0:
		hit_marker = 0.35


func _on_blocked() -> void:
	block_flash = 0.5


func _on_hurt() -> void:
	hurt_flash = 1.0


func _melee() -> bool:
	return player.weapon == "melee"


# ---------------------------------------------------------------- layout

func _buttons() -> Array:
	var s := size
	var list := []
	var main_label := "SWING" if _melee() else "FIRE"
	list.append({"id": "fire", "circle": true, "pos": Vector2(s.x - 140, s.y - 150), "r": 80.0, "label": main_label})
	list.append({"id": "weapon", "circle": true, "pos": Vector2(s.x - 140, s.y - 310), "r": 48.0,
		"label": "MUSKET" if _melee() else "BAYONET"})
	list.append({"id": "volley", "circle": true, "pos": Vector2(s.x - 305, s.y - 105), "r": 58.0, "label": "VOLLEY!"})
	if _melee():
		list.append({"id": "block", "circle": true, "pos": Vector2(s.x - 300, s.y - 260), "r": 54.0, "label": "BLOCK"})
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
		return p.distance_to(b["pos"]) <= float(b["r"]) * 1.12
	var r: Rect2 = b["rect"]
	return r.grow(10).has_point(p)


static func _dir_from_drag(v: Vector2) -> int:
	if v.length() < SWING_DEADZONE:
		return NONE
	if absf(v.x) > absf(v.y):
		return LEFT if v.x < 0.0 else RIGHT
	return OVERHEAD if v.y < 0.0 else THRUST


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
		elif d.index == swing_index:
			swing_pos = d.position
			var dir := _dir_from_drag(swing_pos - swing_origin)
			if dir != NONE:
				player.set_swing_dir(dir)
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
		"fire":
			if _melee():
				# The fire button becomes the swing joystick; the stick
				# centres wherever your thumb lands.
				if swing_index == -1 and player.begin_swing():
					swing_index = idx
					swing_origin = p
					swing_pos = p
			else:
				player.request_fire()
				# Like CoD Mobile: the fire button also aims if you drag from it.
				if look_index == -1:
					look_index = idx
					look_last = p
		"weapon":
			player.toggle_weapon()
		"block":
			block_index = idx
			player.set_block(true)
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
	block_flash = move_toward(block_flash, 0.0, delta)
	_update_pose(delta)
	queue_redraw()


## Pick the target pose from the player's state, then ease toward it. Strikes
## ease much faster than wind-ups so blows feel snappy.
func _update_pose(delta: float) -> void:
	var target: Array = POSE_MUSKET
	var rate := 18.0
	if _melee():
		target = POSE_MELEE_IDLE
		var dir: int = player.swing_dir
		match player.swing_phase:
			"windup":
				target = POSE_WINDUP[dir if dir != NONE else THRUST]
				rate = 14.0
			"strike":
				target = POSE_STRIKE[dir]
				rate = 45.0
			"recover":
				target = POSE_STRIKE[dir] if player.phase_time < 0.06 else POSE_MELEE_IDLE
				rate = 12.0
			_:
				if player.blocking:
					target = POSE_BLOCK
					rate = 22.0
	# While the weapon is out of view (switching), snap to the new pose.
	if player.weapon_lowered() > 0.95:
		rate = 1000.0
	var k := 1.0 - exp(-rate * delta)
	pose_grip = pose_grip.lerp(target[0], k)
	pose_angle = lerp_angle(pose_angle, target[1], k)
	pose_scale = lerpf(pose_scale, target[2], k)

	if _melee() and player.swing_phase == "strike":
		trail.append(_tip_position(size))
		if trail.size() > 7:
			trail.pop_front()
	elif not trail.is_empty():
		trail.pop_front()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var s := size
	_draw_weapon(s)

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
	_draw_swing_indicator(c)
	if block_flash > 0.0:
		_text_center("BLOCKED", c + Vector2(0, 60), 30, Color(0.95, 0.78, 0.3, block_flash * 2.0))

	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.7, 0.0, 0.0, 0.35 * hurt_flash))

	# Health bar and status.
	draw_rect(Rect2(20, 20, 264, 24), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(22, 22, 260.0 * player.hp / player.max_hp, 20), Color(0.8, 0.15, 0.1))
	var status := "Wave %d/%d   Lizardmen %d   Company %d   Loaded %d" % [
		battle.wave, battle.WAVES.size(), battle.enemies.size(), battle.soldiers.size(), battle.loaded_count()]
	_text(status, Vector2(22, 72), 20, Color(1, 1, 1, 0.9))

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

	for b in _buttons():
		if b["id"] == "fire" and swing_index != -1:
			_draw_swing_stick()
		else:
			_draw_button(b)

	# Message banner.
	if message_time > 0.0 and message != "":
		var alpha := clampf(message_time / 0.4, 0.0, 1.0)
		var mc := Vector2(s.x * 0.5, s.y * 0.3)
		_text_center(message, mc + Vector2(2, 2), 40, Color(0, 0, 0, 0.6 * alpha))
		_text_center(message, mc, 40, Color(1, 0.93, 0.75, alpha))


func _pose_points(s: Vector2) -> Dictionary:
	var u := s.y / 720.0
	var off: Vector2 = Vector2(30, 55) * recoil * u + Vector2(60, 320) * player.weapon_lowered() * u
	if _melee() and player.swing_phase == "windup" and player.charge() >= 1.0:
		off += Vector2(randf_range(-2, 2), randf_range(-2, 2)) * u # straining at full charge
	var grip := Vector2(pose_grip.x * s.x, pose_grip.y * s.y) + off
	var dir := Vector2.from_angle(pose_angle)
	var length := 230.0 * u * pose_scale
	return {"grip": grip, "dir": dir, "butt": grip - dir * length, "tip": grip + dir * length,
		"u": u * pose_scale}


func _tip_position(s: Vector2) -> Vector2:
	var p := _pose_points(s)
	var tip: Vector2 = p["tip"]
	var dir: Vector2 = p["dir"]
	return tip + dir * 85.0 * float(p["u"])


func _draw_weapon(s: Vector2) -> void:
	if not player.alive:
		return
	var p := _pose_points(s)
	var grip: Vector2 = p["grip"]
	var dir: Vector2 = p["dir"]
	var butt: Vector2 = p["butt"]
	var tip: Vector2 = p["tip"]
	var u: float = p["u"]
	var stock := Color(0.36, 0.21, 0.1)
	var fore := Color(0.44, 0.27, 0.13)
	var steel := Color(0.58, 0.6, 0.64)

	# Swoosh trail behind the bayonet during a strike.
	for i in range(1, trail.size()):
		var a := float(i) / trail.size()
		draw_line(trail[i - 1], trail[i], Color(1, 1, 1, 0.35 * a), 14.0 * a)

	draw_line(grip, tip, steel, 10 * u)
	draw_line(grip, grip.lerp(tip, 0.7), fore, 18 * u)
	draw_line(butt, grip, stock, 36 * u)
	var side := dir.orthogonal()
	draw_circle(grip + side * 16 * u, 10 * u, Color(0.28, 0.28, 0.3)) # lock plate
	draw_line(grip + side * 16 * u, grip + side * 30 * u + dir * 10 * u, Color(0.2, 0.2, 0.22), 5 * u) # hammer

	if _melee():
		# Socket bayonet: a short sleeve and a long triangular blade.
		var b0 := tip - dir * 10 * u
		var b1 := tip + dir * 85 * u
		draw_line(b0, tip + dir * 6 * u, Color(0.45, 0.46, 0.5), 9 * u)
		draw_colored_polygon(PackedVector2Array([
			tip + side * 5 * u, b1, tip - side * 3 * u]), Color(0.82, 0.84, 0.88))
	elif flash > 0.0:
		draw_circle(tip + dir * 22 * u, 34 * flash * u, Color(1, 0.72, 0.25, flash))
		draw_circle(tip + dir * 18 * u, 16 * flash * u, Color(1, 1, 0.85, flash))


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


## The swing joystick: four sectors, the chosen one lit, plus a charge ring.
func _draw_swing_stick() -> void:
	var o := swing_origin
	var r := SWING_RADIUS
	draw_circle(o, r, Color(0.08, 0.09, 0.12, 0.55))
	var chosen: int = player.swing_dir
	var gold := Color(0.95, 0.78, 0.3)
	# Sector centres: up, left, right, down.
	var centres := {OVERHEAD: -PI * 0.5, LEFT: PI, RIGHT: 0.0, THRUST: PI * 0.5}
	for d in centres:
		var ang: float = centres[d]
		var col := gold if d == chosen else Color(1, 1, 1, 0.35)
		draw_arc(o, r - 6, ang - 0.6, ang + 0.6, 16, col, 8 if d == chosen else 3)
	var labels := {OVERHEAD: "OVER", LEFT: "LEFT", RIGHT: "RIGHT", THRUST: "THRUST"}
	for d in labels:
		var ang2: float = centres[d]
		var lc := gold if d == chosen else Color(1, 1, 1, 0.5)
		_text_center(labels[d], o + Vector2.from_angle(ang2) * (r * 0.62), 13, lc)
	var ch: float = player.charge()
	var ring := Color(1, 1, 1) if ch >= 1.0 else gold
	draw_arc(o, r + 8, -PI * 0.5, -PI * 0.5 + TAU * ch, 48, ring, 6)
	var knob := o + (swing_pos - o).limit_length(r - 20)
	draw_circle(knob, 26, Color(1, 1, 1, 0.5))


func _draw_button(b: Dictionary) -> void:
	var id: String = b["id"]
	var bg := Color(0.08, 0.09, 0.12, 0.5)
	var edge := Color(1, 1, 1, 0.7)
	var label_col := Color(1, 1, 1, 0.95)
	var active: bool = (id == "follow" and battle.is_following()) \
		or (id == "hold" and not battle.is_following()) \
		or (id == "block" and player.blocking)
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
		if id == "fire" and not _melee() and not player.loaded:
			# Reload ring fills up around the fire button.
			draw_arc(pos, r + 9, -PI * 0.5, -PI * 0.5 + TAU * player.reload_progress(), 48, Color(0.95, 0.78, 0.3), 7)
			label = "LOADING"
			label_col = Color(1, 1, 1, 0.5)
		if id == "weapon" and player.is_switching():
			label_col = Color(1, 1, 1, 0.4)
		var fsize := 24 if id == "fire" else (16 if id == "weapon" else 20)
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
