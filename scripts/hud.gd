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
## Also draws your weapon as a 2D overlay (Doom-style viewmodel).
##
## Touches are handled by hand (not Buttons) so several fingers work at once.

const JOY_RADIUS := 90.0

# Swing directions (same values as player.gd's Swing enum).
const NONE := -1
const OVERHEAD := 0
const LEFT := 1
const RIGHT := 2
const THRUST := 3

# Viewmodel poses: [grip position as a fraction of the screen, angle, scale].
# The angle is where the muzzle points, in screen space (0 = right, -PI/2 = up).
const POSE_MUSKET := [Vector2(0.71, 0.82), -2.34, 1.0]
## Aiming down the sights: musket straight up the middle of the screen,
## drawn larger (closer), muzzle and front sight just under the crosshair.
const POSE_AIM := [Vector2(0.5, 1.07), -PI * 0.5, 1.6]
const POSE_MELEE_IDLE := [Vector2(0.70, 0.88), -2.25, 1.0]
const POSE_BLOCK := [Vector2(0.55, 0.80), -3.05, 1.0]
## Musket upright in front of you, muzzle up: reloading and fixing the bayonet.
const POSE_UPRIGHT := [Vector2(0.56, 0.9), -1.66, 1.0]

# Right-hand paths for the reload and bayonet animations: [progress, waypoint].
# Waypoints (see _hand_waypoints): A wrist of the stock, B priming pan,
# C just above the muzzle, D ramrod drawn out, E ramrod home / bayonet on,
# F bayonet held above the muzzle, H bayonet scabbard at your hip.
const RELOAD_PATH := [[0.0, "A"], [0.08, "A"], [0.16, "B"], [0.24, "B"], [0.32, "C"],
	[0.38, "D"], [0.46, "E"], [0.52, "D"], [0.58, "E"], [0.64, "D"], [0.70, "E"],
	[0.76, "D"], [0.84, "B"], [0.92, "A"], [1.0, "A"]]
const FIX_PATH := [[0.0, "A"], [0.1, "A"], [0.3, "H"], [0.55, "F"], [0.72, "E"], [0.85, "E"], [1.0, "A"]]
const UNFIX_PATH := [[0.0, "A"], [0.2, "E"], [0.4, "F"], [0.7, "H"], [1.0, "A"]]
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
var swing_index := -1 # finger holding a swing button
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

# Body motion that makes the arms feel attached to a person.
var bob_t := 0.0
var walk_amount := 0.0
var bob := Vector2.ZERO # walking bob / breathing, in 720p pixels
var look_sway := Vector2.ZERO # weapon lags behind when you turn
var shoulder_twist := Vector2.ZERO # torso turns into big swings


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
	list.append({"id": "volley", "circle": true, "pos": Vector2(s.x - 335, s.y - 95), "r": 56.0, "label": "VOLLEY!"})
	var bw := 160.0
	var bh := 56.0
	var y := 18.0
	var mode_label := "AT WILL" if battle.is_at_will() else "ON COMMAND"
	list.append({"id": "follow", "circle": false, "rect": Rect2(s.x - 3 * (bw + 10), y, bw, bh), "label": "FOLLOW"})
	list.append({"id": "hold", "circle": false, "rect": Rect2(s.x - 2 * (bw + 10), y, bw, bh), "label": "HOLD"})
	list.append({"id": "mode", "circle": false, "rect": Rect2(s.x - (bw + 10), y, bw, bh), "label": mode_label})
	list.append({"id": "menu", "circle": false, "rect": Rect2(20, 92, 110, 46), "label": "MENU"})
	if Settings.use_3d:
		list.append({"id": "view", "circle": false, "rect": Rect2(140, 92, 150, 46),
			"label": "3RD PERSON" if player.third_person else "1ST PERSON"})
	if restart_visible:
		list.append({"id": "restart", "circle": false, "rect": Rect2(s.x * 0.5 - 130, s.y * 0.5 + 30, 260, 72), "label": "RESTART"})
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
			var drag := d.position - look_last
			player.add_look(drag)
			look_sway = (look_sway - drag * 0.25).limit_length(28.0)
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
		"mode":
			battle.toggle_fire_mode()
		"restart":
			battle.restart()
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
	pressed_time -= delta
	recoil = move_toward(recoil, 0.0, delta * 4.0)
	flash = move_toward(flash, 0.0, delta * 14.0)
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 2.5)
	hit_marker = move_toward(hit_marker, 0.0, delta)
	block_flash = move_toward(block_flash, 0.0, delta)
	_update_pose(delta)
	_update_body(delta)
	queue_redraw()


## Pick the target pose from the player's state, then ease toward it. Strikes
## ease much faster than wind-ups so blows feel snappy.
func _update_pose(delta: float) -> void:
	var target: Array = POSE_MUSKET
	var rate := 18.0
	if player.is_switching():
		var sp: float = player.switch_progress()
		var fixing: bool = player.switch_target == "melee"
		rate = 10.0
		if sp > 0.1 and sp < 0.86:
			target = POSE_UPRIGHT
		elif sp <= 0.1:
			target = POSE_MUSKET if fixing else POSE_MELEE_IDLE
		else:
			target = POSE_MELEE_IDLE if fixing else POSE_MUSKET
	elif not _melee() and player.is_aiming():
		target = POSE_AIM
		rate = 16.0
	elif not _melee() and not player.loaded:
		var rp: float = player.reload_progress()
		rate = 10.0
		if rp > 0.06 and rp < 0.9:
			target = POSE_UPRIGHT
	elif _melee():
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


## Walking bob, breathing, look sway and torso twist.
func _update_body(delta: float) -> void:
	var v: Vector3 = player.velocity
	var moving := clampf(Vector2(v.x, v.z).length() / 5.0, 0.0, 1.0)
	walk_amount = lerpf(walk_amount, moving, 1.0 - exp(-6.0 * delta))
	bob_t += delta * (1.7 + 8.0 * walk_amount)
	var walk := Vector2(sin(bob_t) * 9.0, -absf(cos(bob_t)) * 11.0)
	var breathe := Vector2(0.0, sin(bob_t) * 3.0)
	bob = walk * walk_amount + breathe * (1.0 - walk_amount)
	look_sway = look_sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))

	# The shoulders follow the hands a little (the torso twists into a swing),
	# but lag behind them, which is what makes the arms look driven by a body.
	var s := size
	var hands := _hand_positions(_pose_points(s))
	var mid: Vector2 = (hands[0] + hands[1]) * 0.5
	var neutral := Vector2(0.62 * s.x, 0.84 * s.y)
	var target := (mid - neutral) * 0.45
	shoulder_twist = shoulder_twist.lerp(target, 1.0 - exp(-7.0 * delta))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var s := size
	if not Settings.use_3d:
		_draw_weapon(s) # in 3D you see your own 3D arms and musket instead

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
		_draw_button(b)

	# Message banner.
	if message_time > 0.0 and message != "":
		var alpha := clampf(message_time / 0.4, 0.0, 1.0)
		var mc := Vector2(s.x * 0.5, s.y * 0.3)
		_text_center(message, mc + Vector2(2, 2), 40, Color(0, 0, 0, 0.6 * alpha))
		_text_center(message, mc, 40, Color(1, 0.93, 0.75, alpha))


func _pose_points(s: Vector2) -> Dictionary:
	var u := s.y / 720.0
	var off: Vector2 = Vector2(30, 55) * recoil * u
	off += (bob + look_sway) * u
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

	_draw_arms(s, p)

	# Ramrod: while ramming, the rod runs from your hand down into the muzzle.
	if not _melee() and not player.is_switching() and not player.loaded:
		var rp: float = player.reload_progress()
		var hand: Vector2 = _hand_positions(p)[0]
		if rp > 0.34 and rp < 0.77 and (hand - tip).dot(dir) > 0.0:
			draw_line(hand + dir * 6 * u, tip, Color(0.75, 0.77, 0.8), 4 * u)
			draw_circle(hand + dir * 8 * u, 4 * u, Color(0.75, 0.77, 0.8))

	# Front sight: a dark blade on the barrel just behind the muzzle.
	draw_line(tip - dir * 20 * u, tip - dir * 6 * u, Color(0.12, 0.12, 0.14), 4 * u)
	match _bayonet_state():
		"on":
			_draw_bayonet(tip, dir, u)
		"hand":
			var h: Vector2 = _hand_positions(p)[0]
			_draw_bayonet(h, dir, u)
	if not _melee() and not player.is_switching() and flash > 0.0:
		draw_circle(tip + dir * 22 * u, 34 * flash * u, Color(1, 0.72, 0.25, flash))
		draw_circle(tip + dir * 18 * u, 16 * flash * u, Color(1, 1, 0.85, flash))


# ---------------------------------------------------------------- arms

const UPPER_ARM := 235.0
const FOREARM := 225.0
const SLEEVE_EDGE := Color(0.06, 0.08, 0.18)
const SLEEVE := Color(0.13, 0.18, 0.38)
const SLEEVE_LIGHT := Color(0.22, 0.3, 0.52)
const CUFF := Color(0.58, 0.1, 0.1)
const GOLD := Color(0.85, 0.68, 0.2)
const SKIN := Color(0.86, 0.67, 0.52)
const SKIN_DARK := Color(0.64, 0.45, 0.33)


## Where each hand holds the weapon: [right hand on the wrist of the stock,
## left hand under the forestock].
func _hand_positions(p: Dictionary) -> Array:
	var grip: Vector2 = p["grip"]
	var dir: Vector2 = p["dir"]
	var u: float = p["u"]
	var forward := 130.0 if not _melee() else 120.0
	var right := grip - dir * 30.0 * u
	if player.is_switching():
		var path: Array = FIX_PATH if player.switch_target == "melee" else UNFIX_PATH
		right = _follow_path(path, player.switch_progress(), _hand_waypoints(p))
	elif not _melee() and not player.loaded:
		right = _follow_path(RELOAD_PATH, player.reload_progress(), _hand_waypoints(p))
	return [right, grip + dir * forward * u]


func _hand_waypoints(p: Dictionary) -> Dictionary:
	var grip: Vector2 = p["grip"]
	var dir: Vector2 = p["dir"]
	var tip: Vector2 = p["tip"]
	var u: float = p["u"]
	var side := -dir.orthogonal()
	return {
		"A": grip - dir * 30.0 * u,
		"B": grip + side * 30.0 * u + dir * 12.0 * u,
		"C": tip + dir * 25.0 * u + side * 6.0 * u,
		"D": tip + dir * 160.0 * u,
		"E": tip + dir * 20.0 * u,
		"F": tip + dir * 110.0 * u + side * 10.0 * u,
		"H": Vector2(size.x * 0.95, size.y * 1.12),
	}


## Walk a hand along timed waypoints, easing between each pair.
func _follow_path(path: Array, t: float, pts: Dictionary) -> Vector2:
	for i in range(1, path.size()):
		var t1: float = path[i][0]
		if t <= t1 or i == path.size() - 1:
			var t0: float = path[i - 1][0]
			var a: Vector2 = pts[path[i - 1][1]]
			var b: Vector2 = pts[path[i][1]]
			var k := clampf((t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
			return a.lerp(b, k * k * (3.0 - 2.0 * k))
	return pts["A"]


## Where the bayonet is: "off" (in its scabbard), "hand", or "on" the muzzle.
func _bayonet_state() -> String:
	if player.is_switching():
		var sp: float = player.switch_progress()
		if player.switch_target == "melee":
			return "off" if sp < 0.3 else ("hand" if sp < 0.72 else "on")
		return "on" if sp < 0.2 else ("hand" if sp < 0.7 else "off")
	return "on" if _melee() else "off"


## Socket bayonet: a short sleeve and a long triangular blade, socket at `base`.
func _draw_bayonet(base: Vector2, dir: Vector2, u: float) -> void:
	var side := dir.orthogonal()
	draw_line(base - dir * 10 * u, base + dir * 6 * u, Color(0.45, 0.46, 0.5), 9 * u)
	draw_colored_polygon(PackedVector2Array([
		base + side * 5 * u, base + dir * 85 * u, base - side * 3 * u]), Color(0.82, 0.84, 0.88))


func _draw_arms(s: Vector2, p: Dictionary) -> void:
	var u0 := s.y / 720.0
	var hands := _hand_positions(p)
	var dir: Vector2 = p["dir"]
	var body := bob * 0.55 * u0 # shoulders move less than the weapon
	# Shoulders sit well below the screen, so mostly forearms rise into view,
	# foreshortened, the way first-person arms usually read.
	var r_shoulder := Vector2(0.80 * s.x, 1.30 * s.y) + shoulder_twist + body
	var l_shoulder := Vector2(0.42 * s.x, 1.36 * s.y) + shoulder_twist * 1.2 + body
	# Left arm first: it's further from the camera on a right-handed hold.
	_draw_arm(l_shoulder, hands[1], Vector2(-0.4, 0.92), dir, u0)
	_draw_arm(r_shoulder, hands[0], Vector2(0.4, 0.92), dir, u0)


## Two-bone IK: given shoulder and hand, find the elbow. Of the two possible
## elbows, take the one bending toward `bend` (outward and down, like a real
## arm). If the hand is out of reach the arm stretches a little rather than
## letting go of the weapon.
func _draw_arm(shoulder: Vector2, hand: Vector2, bend: Vector2, along: Vector2, u: float) -> void:
	var l1 := UPPER_ARM * u
	var l2 := FOREARM * u
	var d := shoulder.distance_to(hand)
	var stretch := clampf(d / (l1 + l2 - 1.0), 1.0, 1.7)
	l1 *= stretch
	l2 *= stretch
	d = clampf(d, absf(l1 - l2) + 1.0, l1 + l2 - 0.5)
	var to := (hand - shoulder).normalized()
	var ang := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var e1 := shoulder + to.rotated(ang) * l1
	var e2 := shoulder + to.rotated(-ang) * l1
	var mid := (shoulder + hand) * 0.5
	var elbow := e1 if (e1 - mid).dot(bend) > (e2 - mid).dot(bend) else e2

	# Perspective: thick near the shoulder (close to the camera), thin at the wrist.
	_limb(shoulder, elbow, 92.0 * u, 66.0 * u)
	_limb(elbow, hand, 62.0 * u, 44.0 * u)
	draw_circle(elbow, 35.0 * u, SLEEVE_EDGE)
	draw_circle(elbow, 32.0 * u, SLEEVE)
	# Red cuff with gold piping at the wrist.
	var fdir := (hand - elbow).normalized()
	var cuff_start := hand - fdir * 40.0 * u
	_limb_flat(cuff_start, hand - fdir * 8.0 * u, 50.0 * u, 48.0 * u, CUFF)
	var n := fdir.orthogonal()
	draw_line(cuff_start + n * 25.0 * u, cuff_start - n * 25.0 * u, GOLD, 3.0 * u)
	_draw_hand(hand, along, elbow, u)


func _limb(a: Vector2, b: Vector2, wa: float, wb: float) -> void:
	var n := (b - a).normalized().orthogonal()
	var u := size.y / 720.0
	_limb_flat(a, b, wa + 6.0 * u, wb + 6.0 * u, SLEEVE_EDGE) # outline
	_limb_flat(a, b, wa, wb, SLEEVE)
	# Light along one edge gives the sleeve some roundness.
	draw_colored_polygon(PackedVector2Array([
		a + n * wa * 0.5, b + n * wb * 0.5, b + n * wb * 0.18, a + n * wa * 0.18]), SLEEVE_LIGHT)


func _limb_flat(a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal()
	draw_colored_polygon(PackedVector2Array([
		a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5]), col)


## A fist wrapped around the weapon: back of the hand facing us, the row of
## knuckles on the far side of the stock, the thumb on the near side.
func _draw_hand(c: Vector2, along: Vector2, elbow: Vector2, u: float) -> void:
	var n := along.orthogonal()
	var arm_side := signf(n.dot(elbow - c))
	if arm_side == 0.0:
		arm_side = 1.0
	draw_circle(c, 23.0 * u, SKIN_DARK)
	draw_circle(c, 21.0 * u, SKIN)
	draw_circle(c + along * 15.0 * u, 19.0 * u, SKIN)
	# Knuckles / curled fingers over the stock.
	for i in 4:
		var k := c - n * arm_side * 15.0 * u + along * (-10.0 + i * 10.0) * u
		draw_circle(k, 7.5 * u, SKIN_DARK)
		draw_circle(k - n * arm_side * 1.5 * u, 6.0 * u, SKIN)
	# Thumb.
	var t := c + n * arm_side * 13.0 * u + along * 16.0 * u
	draw_circle(t, 9.5 * u, SKIN_DARK)
	draw_circle(t, 8.0 * u, SKIN)


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
		or (id == "hold" and not battle.is_following()) \
		or (id == "block" and player.blocking) \
		or (id == "aim" and player.aim_wanted)
	if active:
		edge = Color(0.95, 0.78, 0.3)
		label_col = Color(0.95, 0.78, 0.3)
	if id == pressed_id and pressed_time > 0.0:
		bg = Color(1, 1, 1, 0.35)
	if id == "volley" and battle.loaded_count() == 0:
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
		var fsize := 24 if id == "fire" else (16 if id == "weapon" or id.begins_with("swing") else 20)
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
