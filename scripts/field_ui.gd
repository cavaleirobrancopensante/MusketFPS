extends Control
## The command view of a field battle (Tests > Field battle): the general's
## seat, made for a thumb, not a mouse.
##
## Open it any time with COMMAND (top of the battle HUD). The camera rises
## over the field; time slows to a crawl (SLOW), stops (PAUSE) or runs (PLAY).
##
##   your regiments   a card each along the bottom: what they are, how many
##                    are left (bar), their nerve (bar), and WAVERING /
##                    ROUTING when it goes. Tap a card (or the regiment on the
##                    field) to select it; ALL selects every one.
##   orders           with a regiment selected:
##                      tap the ground          march there (deploying: stand
##                                              there in a column of twos)
##                      drag on the ground      form a line along the drag, as
##                                              long as the drag, facing away
##                                              from you (a short drag: march
##                                              there and face the way you
##                                              dragged)
##                      tap an enemy regiment   attack it (shooters close to
##                                              range and fire; the rest charge)
##                    and the buttons on the right: HALT, CHARGE (the nearest
##                    enemy, or the one you're attacking), FIRE AT WILL / HOLD
##                    FIRE, VOLLEY, FALL BACK, RUN (double time); your own
##                    company also has FOLLOW ME.
##   the camera       one finger drags it when nothing is selected; two
##                    fingers always pan, pinch to zoom and twist to turn it;
##                    a mouse wheel zooms.
##   alerts           a regiment wavering, breaking or hit from behind shows
##                    at the top left (tap it to look); with AUTO-PAUSE on,
##                    the important ones open this view, paused, wherever
##                    you are.
##
## The battle starts here, paused, to deploy: move your regiments anywhere
## in your half of the field (they're placed at once), then BEGIN.

const UI := preload("res://scripts/ui.gd")
const Terrain := preload("res://scripts/field_terrain.gd")

const SLOW := 0.2
const BLUE := Color(0.55, 0.72, 1.0)
const RED := Color(1.0, 0.45, 0.38)
const CARD_W := 132.0
const CARD_H := 92.0

var field
var battle
var active := false
var deploying := true
var speed := "slow" # pause, slow, play
var auto_pause := false
var _auto_t := -99.0 # (real seconds) the last time an alert pulled you up here
var selected: Array = []
var cam: Camera3D
var focus := Vector3(0, 0, 40)
var yaw := 0.0
var pitch := deg_to_rad(52.0)
var dist := 120.0
var alerts: Array = [] # [text, regiment, age]

var _touches := {} # index -> position
var _press := {} # the one-finger press: idx, start, ground, moved, time
var _two := {} # two-finger gesture state
var _banners := {} # regiment -> Label3D
var _overlay: MeshInstance3D
var _imesh: ImmediateMesh
var _drag_arrow := [] # [from, to] while dragging an order
var font: Font
var display: Font
var _pressed_id := ""
var _pressed_t := 0.0
var _hint_t := 0.0
## A lesson shown in the middle while the view is open (the prologue's first
## command): a title, then lines. Cleared when you leave the view.
var lesson: Array = []
var _ambient := -1.0 # the night's ambient light while the view brightens it


func setup(f) -> void:
	field = f
	battle = f.battle
	f.ui = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = UI.font("alegreya_sans_500")
	display = UI.display_font()
	auto_pause = bool(f.cfg.get("auto_pause", false))
	cam = Camera3D.new()
	cam.far = 900.0
	cam.fov = 55.0
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.add_child(cam)
	_imesh = ImmediateMesh.new()
	_overlay = MeshInstance3D.new()
	_overlay.mesh = _imesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	_overlay.material_override = m
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.add_child(_overlay)
	for r in field.regs:
		add_banner(r)
	battle.batcher.process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_view()


## A regiment's name over it, seen from up here (one that joins the battle
## later gets one too).
func add_banner(r) -> void:
	if _banners.has(r):
		return
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.no_depth_test = true
	l.font = display
	l.font_size = 30
	l.outline_size = 9
	l.outline_modulate = Color(0.05, 0.06, 0.1, 0.9)
	l.modulate = BLUE if r.side == 0 else RED
	l.render_priority = 11
	l.process_mode = Node.PROCESS_MODE_ALWAYS
	l.visible = active
	battle.add_child(l)
	_banners[r] = l


func _setup_view() -> void:
	# Start over your own army, looking at theirs.
	var p0: Vector3 = field.player_reg.pos if field.player_reg != null else Vector3(0, 0, 60)
	focus = Vector3(p0.x, 0, p0.z - 34.0)
	dist = 150.0
	if field.test_mode or ("--shots" in OS.get_cmdline_user_args() and not "--deploy" in OS.get_cmdline_user_args()):
		deploying = false
		return
	if bool(field.cfg.get("ambush", false)):
		# No time to deploy: they're on you.
		deploying = false
		battle.hud.show_message("AMBUSH! No time to form up!", 4.0)
		return
	if field.prologue:
		deploying = false
		return
	if field.camp:
		deploying = false # (they're on you in the dark)
		return
	dist = clampf(field.deploy_z * 1.8, 70.0, 150.0)
	focus = Vector3(p0.x, 0, p0.z - field.deploy_z * 0.5)
	open(true)
	_hint_t = 12.0


# ---------------------------------------------------------------- open / close

func open(paused: bool) -> void:
	active = true
	cam.current = true
	_set_speed("pause" if paused else ("slow" if not deploying else "pause"))
	battle.hud.visible = false
	battle.hud.process_mode = Node.PROCESS_MODE_DISABLED
	if field.env != null:
		if battle.night and _ambient < 0.0:
			_ambient = field.env.ambient_light_energy
			field.env.ambient_light_energy = _ambient * 2.6 # (at night, a general's eye: or nothing shows)
		field.env.fog_density = 0.0007 # (from up here the haze would grey it all out)
		field.env.fog_height_density = 0.0
	battle.player.set_process_input(false)
	for r in _banners:
		_banners[r].visible = true
	_overlay.visible = true
	queue_redraw()


func close() -> void:
	if not battle.player.alive:
		_set_speed("play")
		return # (you're down: the view is all you have)
	active = false
	lesson = []
	selected.clear()
	_press.clear()
	_two.clear()
	_touches.clear()
	get_tree().paused = false
	Engine.time_scale = 1.0
	battle.player.camera.current = true
	battle.hud.visible = true
	battle.hud.process_mode = Node.PROCESS_MODE_INHERIT
	battle.hud.message_time = minf(battle.hud.message_time, 1.5) # (nothing stale waiting below)
	if field.env != null:
		field.env.fog_density = field.fog
		if _ambient >= 0.0:
			field.env.ambient_light_energy = _ambient
			_ambient = -1.0
		field.env.fog_height_density = 0.0015
	battle.player.set_process_input(true)
	for r in _banners:
		_banners[r].visible = false
	_overlay.visible = false
	queue_redraw()


func _set_speed(s: String) -> void:
	speed = s
	get_tree().paused = s == "pause"
	Engine.time_scale = SLOW if s == "slow" else 1.0


func _begin() -> void:
	deploying = false
	battle.hud.show_message("Form the line! The battle begins.", 3.0)
	close()


## Something to know: listed at the top left; important ones open the view
## (paused) if AUTO-PAUSE is on.
func alert(r, text: String, important: bool) -> void:
	alerts.push_front([text, r, 0.0])
	if alerts.size() > 5:
		alerts.pop_back()
	var now := Time.get_ticks_msec() / 1000.0
	if important and auto_pause and not active and not deploying and battle.player.alive and not field.test_mode and now - _auto_t > 30.0:
		_auto_t = now
		open(true)
		if r != null and r.side == 0:
			selected = [r]
			focus = Vector3(r.centroid.x, 0, r.centroid.z)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001) if not get_tree().paused else delta
	_pressed_t -= real
	_hint_t -= real
	for a in alerts:
		a[2] = float(a[2]) + real
	while not alerts.is_empty() and float(alerts[alerts.size() - 1][2]) > 14.0:
		alerts.pop_back()
	if not active:
		if not alerts.is_empty():
			queue_redraw()
		return
	selected = selected.filter(func(r): return not r.gone())
	_place_camera()
	_update_banners()
	_draw_overlay()
	queue_redraw()


func _place_camera() -> void:
	focus.x = clampf(focus.x, -Terrain.HALF, Terrain.HALF)
	focus.z = clampf(focus.z, -Terrain.HALF - 20.0, Terrain.HALF + 20.0)
	focus.y = field.terrain.height(focus.x, focus.z)
	dist = clampf(dist, 18.0, 260.0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.global_position = focus + dir * dist
	cam.look_at(focus, Vector3.UP)


func _update_banners() -> void:
	for r in _banners:
		var l: Label3D = _banners[r]
		if r.gone():
			l.visible = false
			continue
		l.visible = true
		var c: Vector3 = r.centroid
		# (a battery's name above the infantry's: on the beach they share a centre)
		l.global_position = c + Vector3.UP * (5.0 + dist * (0.025 if not r.is_gun() else 0.06))
		var st := ""
		match r.state:
			"wavering": st = "  WAVERING"
			"routing": st = "  ROUTING"
			"shattered": st = "  BROKEN"
		var you := "★ " if r.player_led else ""
		l.text = "%s%s %d%s" % [you, r.info["short"], r.members.size(), st]
		var col := BLUE if r.side == 0 else RED
		if r in selected:
			col = UI.BRASS.lightened(0.3)
		if r.broken():
			col = col.darkened(0.35)
		l.modulate = col


## On the ground: every regiment's block (yours blue, theirs red, the
## selected brass), the way they face, and where the selected ones are going.
func _draw_overlay() -> void:
	_imesh.clear_surfaces()
	# Each block filled in its colour, so the battle reads from up here
	# like a map (the men themselves are specks at this height).
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in field.regs:
		if r.gone() or r.members.is_empty():
			continue
		var fc := Color(BLUE.darkened(0.2), 0.32) if r.side == 0 else Color(RED.darkened(0.2), 0.32)
		if r in selected:
			fc = Color(UI.BRASS, 0.42)
		if r.broken():
			fc.a = 0.12
		var hw: float = maxf(2.5, r.width() * 0.5 + 1.0)
		var depth: float = maxf(2.0, ceilf(float(r.members.size()) / r.files_now()) * r.rank_gap)
		_quad(r.centroid, r.forward, r.right(), hw, depth * 0.5, fc)
		if r in selected and r.is_ranged() and not r.broken():
			_cone_fill(r)
	_imesh.surface_end()
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for r in field.regs:
		if r.gone() or r.members.is_empty():
			continue
		var col := Color(BLUE, 0.75) if r.side == 0 else Color(RED, 0.75)
		if r in selected:
			col = Color(UI.BRASS.lightened(0.2), 1.0)
		if r.broken():
			col.a = 0.3
		var c: Vector3 = r.centroid
		var f: Vector3 = r.forward
		var rt: Vector3 = r.right()
		var hw: float = maxf(2.5, r.width() * 0.5 + 1.0)
		var depth: float = maxf(2.0, ceilf(float(r.members.size()) / r.files_now()) * r.rank_gap)
		var front: Vector3 = c + f * depth * 0.5
		var back: Vector3 = c - f * depth * 0.5
		var pts := [front - rt * hw, front + rt * hw, back + rt * hw, back - rt * hw]
		for i in 4:
			_line(pts[i], pts[(i + 1) % 4], col)
		# A chevron at the front.
		_line(front - rt * 1.2, front + f * 1.6, col)
		_line(front + rt * 1.2, front + f * 1.6, col)
		if r in selected:
			var from := c
			if r.order == "move" or (r.order == "attack" and not r.path.is_empty()):
				for p in r.path:
					_line(from, p, Color(UI.BRASS, 0.9))
					from = p
				if not r.path.is_empty():
					var last: Vector3 = r.path[r.path.size() - 1]
					_line(last, last + r.dest_forward * 6.0, Color(UI.BRASS, 0.9))
			if r.target != null and not r.target.gone():
				_line(c, r.target.centroid, Color(UI.MADDER.lightened(0.3), 0.9))
			if r.is_ranged() and not r.broken():
				_cone_edge(r)
	if _drag_arrow.size() == 2 and (_drag_arrow[1] - _drag_arrow[0]).length() >= LINE_DRAG:
		# The line it will form: along the drag, an arrow for the way it faces.
		var a2: Vector3 = _drag_arrow[0]
		var b2: Vector3 = _drag_arrow[1]
		var f2 := _line_facing(a2, b2)
		var sd2 := f2.cross(Vector3.UP)
		_line(a2, b2, UI.BRASS)
		_line(a2 - f2 * 1.5, a2 + f2 * 1.5, UI.BRASS)
		_line(b2 - f2 * 1.5, b2 + f2 * 1.5, UI.BRASS)
		var m2 := (a2 + b2) * 0.5
		_line(m2, m2 + f2 * 7.0, UI.BRASS)
		_line(m2 + f2 * 7.0, m2 + f2 * 4.5 + sd2 * 2.0, UI.BRASS)
		_line(m2 + f2 * 7.0, m2 + f2 * 4.5 - sd2 * 2.0, UI.BRASS)
	elif _drag_arrow.size() == 2:
		var a: Vector3 = _drag_arrow[0]
		var b: Vector3 = _drag_arrow[1]
		var d := b - a
		d.y = 0.0
		if d.length() > 0.5:
			var fw := d.normalized()
			var sd := fw.cross(Vector3.UP)
			var w := 8.0
			_line(a - sd * w, a + sd * w, UI.BRASS)
			_line(a, a + fw * 7.0, UI.BRASS)
			_line(a + fw * 7.0, a + fw * 4.5 + sd * 2.0, UI.BRASS)
			_line(a + fw * 7.0, a + fw * 4.5 - sd * 2.0, UI.BRASS)
	_imesh.surface_end()


## A ranged regiment's reach: a fan on the ground out to its range, as wide
## as the arc it can shoot into.
func _cone_pts(r) -> Array:
	var c: Vector3 = r.centroid
	var arc: float = r.fire_arc()
	var out: Array = []
	var n := 16
	for i in n + 1:
		var a := lerpf(-arc, arc, float(i) / n)
		out.append(c + (Basis(Vector3.UP, a) * r.forward) * r.range_m())
	return out


func _cone_fill(r) -> void:
	var c: Vector3 = r.centroid
	c.y = field.terrain.height(c.x, c.z) + 0.25
	var pts := _cone_pts(r)
	var col := Color(1.0, 0.85, 0.4, 0.09)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		a.y = field.terrain.height(a.x, a.z) + 0.25
		b.y = field.terrain.height(b.x, b.z) + 0.25
		for q in [c, a, b]:
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex(q)


func _cone_edge(r) -> void:
	var pts := _cone_pts(r)
	var col := Color(1.0, 0.85, 0.4, 0.75)
	_line(r.centroid, pts[0], col)
	_line(r.centroid, pts[pts.size() - 1], col)
	for i in pts.size() - 1:
		_line(pts[i], pts[i + 1], col)


## A rectangle on the ground (centre c, half-width hw along `rt`, half-depth
## hd along `f`), in pieces so it follows the lie of the land.
func _quad(c: Vector3, f: Vector3, rt: Vector3, hw: float, hd: float, col: Color) -> void:
	var nx := maxi(1, int(hw * 2.0 / 5.0))
	var nz := maxi(1, int(hd * 2.0 / 5.0))
	for i in nx:
		for j in nz:
			var x0 := -hw + 2.0 * hw * i / nx
			var x1 := -hw + 2.0 * hw * (i + 1) / nx
			var z0 := -hd + 2.0 * hd * j / nz
			var z1 := -hd + 2.0 * hd * (j + 1) / nz
			var p := [c + rt * x0 + f * z0, c + rt * x1 + f * z0, c + rt * x1 + f * z1, c + rt * x0 + f * z1]
			for k in 4:
				var q: Vector3 = p[k]
				q.y = field.terrain.height(q.x, q.z) + 0.3
				p[k] = q
			for idx in [0, 1, 2, 0, 2, 3]:
				_imesh.surface_set_color(col)
				_imesh.surface_add_vertex(p[idx])


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	# Follow the ground in short steps so lines don't vanish into hills.
	var n := maxi(1, int(a.distance_to(b) / 6.0))
	var prev := Vector3(a.x, field.terrain.height(a.x, a.z) + 0.35, a.z)
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		p.y = field.terrain.height(p.x, p.z) + 0.35
		_imesh.surface_set_color(col)
		_imesh.surface_add_vertex(prev)
		_imesh.surface_set_color(col)
		_imesh.surface_add_vertex(p)
		prev = p


# ---------------------------------------------------------------- layout

func _my_regs() -> Array:
	return field.regs.filter(func(r): return r.side == 0 and not r.gone())


func _buttons() -> Array:
	var s := size
	var out: Array = []
	if not active:
		return out
	var bw := 112.0
	var y := 14.0
	out.append({"id": "pause", "rect": Rect2(14, y, bw, 52), "label": "PAUSE", "on": speed == "pause"})
	out.append({"id": "slow", "rect": Rect2(14 + (bw + 8), y, bw, 52), "label": "SLOW", "on": speed == "slow"})
	out.append({"id": "play", "rect": Rect2(14 + 2 * (bw + 8), y, bw, 52), "label": "PLAY", "on": speed == "play"})
	if deploying:
		out.append({"id": "begin", "rect": Rect2(s.x * 0.5 - 150, y, 300, 60), "label": "BEGIN THE BATTLE", "primary": true})
	elif battle.player.alive:
		out.append({"id": "close", "rect": Rect2(s.x - 214, y, 200, 52), "label": "TO YOUR MEN", "primary": true})
	out.append({"id": "autopause", "rect": Rect2(s.x - 214 - (0 if deploying or not battle.player.alive else 210), y + (0 if deploying or not battle.player.alive else 0), 200, 52),
		"label": "AUTO-PAUSE " + ("ON" if auto_pause else "OFF"), "on": auto_pause})
	if field.over != "":
		out.append({"id": "restart", "rect": Rect2(s.x * 0.5 - 130, s.y * 0.5 - 36, 260, 72), "label": "RESTART", "primary": true})
		out.append({"id": "menu", "rect": Rect2(s.x * 0.5 - 130, s.y * 0.5 + 46, 260, 60), "label": "MENU"})
	# Zoom and turn, for one thumb.
	var zx := s.x - 70.0
	var zy := 92.0
	for k in [["zoom_in", "+"], ["zoom_out", "−"], ["turn_l", "⟲"], ["turn_r", "⟳"]]:
		out.append({"id": k[0], "rect": Rect2(zx, zy, 56, 50), "label": k[1]})
		zy += 56.0
	# Orders for the selection.
	if not selected.is_empty():
		var ox := s.x - 214.0
		var oy := zy + 10.0
		var r0 = selected[0]
		var list: Array = [["halt", "HALT"], ["charge", "CHARGE"]]
		var any_ranged := selected.any(func(r): return r.is_ranged())
		if any_ranged:
			list.append(["fire", "FIRE: AT WILL" if r0.fire_at_will else "FIRE: HOLDING"])
			list.append(["volley", "VOLLEY"])
		list.append(["run", "RUN: " + ("ON" if r0.run else "OFF")])
		list.append(["fallback", "FALL BACK"])
		if selected.size() == 1 and r0.player_led and battle.player.alive:
			list.append(["follow", "FOLLOW ME"])
		ox = s.x - 214.0 - 66.0
		oy = 92.0
		for k in list:
			out.append({"id": "o_" + k[0], "rect": Rect2(ox, oy, 200, 48), "label": k[1]})
			oy += 54.0
	out.append({"id": "all", "rect": Rect2(14, s.y - CARD_H - 18 - 58, 120, 48), "label": "ALL"})
	if not selected.is_empty():
		out.append({"id": "none", "rect": Rect2(142, s.y - CARD_H - 18 - 58, 120, 48), "label": "NONE"})
	return out


func _cards() -> Array:
	var regs := _my_regs()
	var s := size
	var out: Array = []
	var total := regs.size() * (CARD_W + 8.0) - 8.0
	var x := maxf(14.0, s.x * 0.5 - total * 0.5)
	var w := CARD_W
	if total > s.x - 28.0:
		w = (s.x - 28.0 - 8.0 * (regs.size() - 1)) / regs.size()
		x = 14.0
	for r in regs:
		out.append([r, Rect2(x, s.y - CARD_H - 12.0, w, CARD_H)])
		x += w + 8.0
	return out


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist *= 0.9
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist *= 1.1
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index, t.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position)
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, p: Vector2) -> void:
	_touches[idx] = p
	if _touches.size() == 2:
		# A second finger: the one-finger press becomes a camera gesture.
		_press.clear()
		_drag_arrow = []
		var ps: Array = _touches.values()
		_two = {"mid": (ps[0] + ps[1]) * 0.5, "len": (ps[0] as Vector2).distance_to(ps[1]), "ang": (ps[1] - ps[0]).angle()}
		return
	if _touches.size() > 2:
		return
	for b in _buttons():
		if (b["rect"] as Rect2).grow(6).has_point(p):
			_pressed_id = b["id"]
			_pressed_t = 0.15
			_button(b["id"])
			_touches.erase(idx)
			return
	for c in _cards():
		if (c[1] as Rect2).has_point(p):
			_tap_card(c[0])
			_touches.erase(idx)
			return
	for i in alerts.size():
		if Rect2(14, 84 + i * 34, 520, 30).has_point(p):
			var r = alerts[i][1]
			if r != null:
				focus = Vector3(r.centroid.x, 0, r.centroid.z)
				if r.side == 0 and not r.gone():
					selected = [r]
			_touches.erase(idx)
			return
	_press = {"idx": idx, "start": p, "last": p, "ground": _ground_at(p), "moved": false}


func _touch_move(idx: int, p: Vector2) -> void:
	if not _touches.has(idx):
		return
	_touches[idx] = p
	if _touches.size() == 2 and not _two.is_empty():
		var ps: Array = _touches.values()
		var mid: Vector2 = (ps[0] + ps[1]) * 0.5
		var l: float = (ps[0] as Vector2).distance_to(ps[1])
		var ang: float = (ps[1] - ps[0]).angle()
		_pan(mid - _two["mid"])
		if float(_two["len"]) > 10.0 and l > 10.0:
			dist *= float(_two["len"]) / l
		yaw += angle_difference(ang, float(_two["ang"]))
		_two = {"mid": mid, "len": l, "ang": ang}
		return
	if _press.is_empty() or int(_press["idx"]) != idx:
		return
	if not _press["moved"] and p.distance_to(_press["start"]) > 14.0:
		_press["moved"] = true
	if not _press["moved"]:
		return
	if selected.is_empty():
		_pan(p - _press["last"])
	else:
		var g = _ground_at(p)
		if g != null and _press["ground"] != null:
			_drag_arrow = [_press["ground"], g]
	_press["last"] = p


func _touch_up(idx: int, p: Vector2) -> void:
	_touches.erase(idx)
	if _touches.size() < 2:
		_two.clear()
	if _press.is_empty() or int(_press["idx"]) != idx:
		return
	var pr := _press
	_press = {}
	var g0 = pr["ground"]
	if not pr["moved"]:
		_tap(p, g0)
	elif not selected.is_empty() and g0 != null and _drag_arrow.size() == 2:
		var face: Vector3 = _drag_arrow[1] - _drag_arrow[0]
		face.y = 0.0
		if face.length() >= LINE_DRAG:
			_order_line(_drag_arrow[0], _drag_arrow[1])
		else:
			_order_move(g0, face.normalized() if face.length() > 2.0 else Vector3.ZERO)
	_drag_arrow = []


func _pan(screen_delta: Vector2) -> void:
	# Drag the ground with the finger: metres per pixel grow with height.
	var k := dist * 0.0016
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	focus -= right * screen_delta.x * k
	focus += fwd * screen_delta.y * k


func _ground_at(p: Vector2, c: Camera3D = null):
	if c == null:
		c = cam
	var o := c.project_ray_origin(p)
	var d := c.project_ray_normal(p)
	var t := 0.0
	var prev := o
	for i in 400:
		t += 2.0
		var q := o + d * t
		if q.y <= field.terrain.height(q.x, q.z):
			# Halve back to the surface.
			var a := prev
			var b := q
			for k in 8:
				var m := (a + b) * 0.5
				if m.y <= field.terrain.height(m.x, m.z):
					b = m
				else:
					a = m
			return b
		prev = q
	return null


## Which regiment is at this spot on the ground (the nearest man within a
## few metres, or inside its block).
func _reg_at(g: Vector3):
	var best = null
	var bd := 5.0
	for r in field.regs:
		if r.gone():
			continue
		var c: Vector3 = r.centroid
		if Vector2(g.x - c.x, g.z - c.z).length() > r.width() * 0.6 + 12.0:
			continue
		for m in r.members:
			var d := Vector2(g.x - m.global_position.x, g.z - m.global_position.z).length()
			if d < bd:
				bd = d
				best = r
	return best


## Which regiment is under a point on the screen: inside its block as drawn
## on the ground, on its banner, or close to one of its men. With regiments
## selected, an enemy under the finger wins over one of yours.
func pick_screen(p: Vector2, c: Camera3D, with_banners: bool) -> Variant:
	var hits: Array = [] # [regiment, score]
	for r in field.regs:
		if r.gone() or r.members.is_empty():
			continue
		var score := INF
		# The block on the ground.
		var hw: float = maxf(2.5, r.width() * 0.5 + 1.5)
		var hd: float = maxf(2.0, ceilf(float(r.members.size()) / r.files_now()) * r.rank_gap) * 0.5 + 1.5
		var poly := PackedVector2Array()
		var ok := true
		for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var w: Vector3 = r.centroid + r.right() * hw * k[0] + r.forward * hd * k[1]
			w.y = field.terrain.height(w.x, w.z) + 0.5
			if c.is_position_behind(w):
				ok = false
				break
			poly.append(c.unproject_position(w))
		if ok and Geometry2D.is_point_in_polygon(p, poly):
			score = 0.0
		# The banner.
		if with_banners and _banners.has(r):
			var l: Label3D = _banners[r]
			if l.visible and not c.is_position_behind(l.global_position):
				var sp := c.unproject_position(l.global_position)
				var half := Vector2(maxf(40.0, l.text.length() * 8.5), 22.0)
				if Rect2(sp - half, half * 2.0).has_point(p):
					score = minf(score, 0.5)
		# Close to one of its men (far away, a block is a few pixels).
		var step := maxi(1, r.members.size() / 12)
		for i in range(0, r.members.size(), step):
			var m = r.members[i]
			var w2: Vector3 = m.global_position + Vector3.UP
			if c.is_position_behind(w2):
				continue
			var d := c.unproject_position(w2).distance_to(p)
			if d < 42.0:
				score = minf(score, 1.0 + d / 42.0)
		if score < INF:
			hits.append([r, score])
	if hits.is_empty():
		return null
	var want_enemy := not selected.is_empty()
	hits.sort_custom(func(a, b):
		var ea: bool = a[0].side == 1
		var eb: bool = b[0].side == 1
		if want_enemy and ea != eb:
			return ea
		return float(a[1]) < float(b[1]))
	return hits[0][0]


func _tap(p: Vector2, g) -> void:
	var r = pick_screen(p, cam, true)
	if r == null and g != null:
		r = _reg_at(g)
	if r != null and r.side == 0:
		_toggle(r)
		return
	if selected.is_empty():
		if r != null:
			focus = Vector3(r.centroid.x, 0, r.centroid.z)
		return
	if r != null and r.side == 1:
		if not deploying:
			order_attack(r)
		return
	if g != null:
		_order_move(g, Vector3.ZERO)


## Add a regiment to the selection, or take it out if it's in.
func _toggle(r) -> void:
	if r in selected:
		selected.erase(r)
	else:
		selected.append(r)


func _tap_card(r) -> void:
	_toggle(r)
	if r in selected and active:
		focus = Vector3(r.centroid.x, 0, r.centroid.z)


## Send the selection at an enemy regiment: they close with it and keep
## after it (shooters to their range, the rest to charge).
func order_attack(r) -> void:
	for s in selected:
		if s.broken():
			continue
		if s.player_led and battle.player.alive and s.order == "follow":
			s.order_hold()
		s.order_attack(r)
	battle.play_sound_ui("drum", -8.0)


## On foot: a tap in the world with regiments selected (the bar at the top
## of the HUD). On an enemy regiment: attack it; on the ground: march there.
## You point, and shout it. Returns true if it was an order.
func fp_tap(p: Vector2) -> bool:
	selected = selected.filter(func(r): return not r.gone() and not r.broken())
	if selected.is_empty() or not battle.player.alive:
		return false
	var c: Camera3D = battle.player.camera
	var r = pick_screen(p, c, false)
	var names := _names(selected)
	if r != null and r.side == 1:
		order_attack(r)
		battle.player.point_at(r.centroid + Vector3.UP * 1.5)
		battle.hud.show_message("%s — at %s!" % [names, r.title.to_lower() if not r.title.begins_with("1st") else "those " + String(r.info["name"]).to_lower()], 2.0)
		battle.play_sound_ui("shout", -2.0)
		return true
	var g = _ground_at(p, c)
	if g == null or (g as Vector3).distance_to(battle.player.global_position) > 320.0:
		return false
	_order_move(g, Vector3.ZERO)
	battle.player.point_at(g + Vector3.UP * 1.0)
	battle.hud.show_message("%s — forward, to there!" % names, 2.0)
	battle.play_sound_ui("shout", -2.0)
	return true


func _names(regs: Array) -> String:
	if regs.size() == 1:
		return "Company" if regs[0].player_led else String(regs[0].title)
	if regs.size() == 2:
		return "%s and %s" % [regs[0].title, regs[1].title]
	return "%d regiments" % regs.size()


## March the selection to `to` (keeping their places side by side if more
## than one), facing `face` (or the way they're going).
func _order_move(to: Vector3, face: Vector3) -> void:
	if selected.is_empty():
		return
	var c := Vector3.ZERO
	for r in selected:
		c += r.pos
	c /= selected.size()
	var way := to - c
	way.y = 0.0
	var f: Vector3 = face if face.length_squared() > 0.01 else (way.normalized() if way.length() > 4.0 else selected[0].forward)
	var rt := f.cross(Vector3.UP).normalized()
	# Side by side along the new front, in their present left-to-right order.
	var sorted := selected.duplicate()
	sorted.sort_custom(func(a, b): return (a.pos - c).dot(rt) < (b.pos - c).dot(rt))
	var widths := 0.0
	for r in sorted:
		widths += r.width() + 8.0
	var x := -(widths - 8.0) * 0.5
	for r in sorted:
		var at: Vector3 = to + rt * (x + r.width() * 0.5)
		x += r.width() + 8.0
		if deploying:
			if face.length_squared() < 0.01 and not r.is_gun() and r.members.size() > 2:
				r.files = 2 # (a tap: a column of twos, ready to march off)
			_deploy_to(r, at, f)
		else:
			if r.player_led and r.order == "follow":
				r.order_hold()
			r.order_move(at, f, r.run)
	battle.play_sound_ui("drum", -10.0)


## A drag at least this long (m) lays out a line; shorter, it's a move with a facing.
const LINE_DRAG := 6.0


## The way a line laid from a to b faces: square to it, away from the camera.
func _line_facing(a: Vector3, b: Vector3) -> Vector3:
	var along := b - a
	along.y = 0.0
	var f := along.normalized().cross(Vector3.UP)
	var look := -cam.global_transform.basis.z
	look.y = 0.0
	if f.dot(look) < 0.0:
		f = -f
	return f


## A line along the drag: the selection shares it out (by their numbers,
## in their present left-to-right order), each regiment as many files wide
## as its share of the frontage.
func _order_line(a: Vector3, b: Vector3) -> void:
	if selected.is_empty():
		return
	var f := _line_facing(a, b)
	var rt := f.cross(Vector3.UP).normalized()
	var along := b - a
	along.y = 0.0
	if along.dot(rt) < 0.0:
		var t := a
		a = b
		b = t
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var c := Vector3.ZERO
	for r in selected:
		c += r.pos
	c /= selected.size()
	var sorted := selected.duplicate()
	sorted.sort_custom(func(x, y): return (x.pos - c).dot(rt) < (y.pos - c).dot(rt))
	var men := 0
	for r in sorted:
		men += maxi(1, r.members.size())
	var gap := 6.0 if sorted.size() > 1 else 0.0
	var usable := maxf(4.0, length - gap * (sorted.size() - 1))
	var x := 0.0
	for r in sorted:
		var share := usable * maxi(1, r.members.size()) / float(men)
		var at: Vector3 = a + rt * (x + share * 0.5)
		at.y = field.terrain.height(at.x, at.z)
		x += share + gap
		if not r.is_gun():
			r.files = clampi(int(round(share / r.spacing)) + 1, 2, maxi(2, r.members.size()))
		if deploying:
			_deploy_to(r, at, f)
		else:
			if r.player_led and r.order == "follow":
				r.order_hold()
			r.order_move(at, f, r.run)
	battle.play_sound_ui("drum", -10.0)


## Deployment: the regiment is simply put there (your half of the field).
func _deploy_to(r, at: Vector3, f: Vector3) -> void:
	at.z = clampf(at.z, 18.0, Terrain.HALF - 8.0)
	at.x = clampf(at.x, -Terrain.HALF + 8.0, Terrain.HALF - 8.0)
	at = field.terrain.free_spot(at)
	r.pos = at
	r.forward = f
	r.dest_forward = f
	r.path = []
	if r.order != "follow":
		r.order = "hold"
	for m in r.members:
		var sp: Vector3 = field.terrain.free_spot(r.slot(m.slot_index))
		m.global_position = sp
		m.facing = f
		if m.get("crew") != null:
			m.crew.global_position = sp
			m.crew.rotation.y = atan2(-f.x, -f.z)
			m.crew.want_yaw = m.crew.rotation.y
			for role in m.crew._crew:
				m.crew._crew[role]["rig"].refresh()
		if m.rig != null:
			m.rig.facing = f
			m.rig.refresh()
			if m.get("rider") != null:
				m.rider.facing = f
				m.rider.refresh()
	r.centroid = at
	if r.player_led:
		battle.player.global_position = at + Vector3.UP * 0.4
		battle.player.rotation.y = atan2(-f.x, -f.z)


func _button(id: String) -> void:
	match id:
		"pause":
			_set_speed("pause")
		"slow":
			if not deploying:
				_set_speed("slow")
		"play":
			if not deploying:
				_set_speed("play")
		"begin":
			_begin()
		"close":
			close()
		"autopause":
			auto_pause = not auto_pause
		"restart":
			get_tree().paused = false
			Engine.time_scale = 1.0
			battle.restart()
		"menu":
			get_tree().paused = false
			Engine.time_scale = 1.0
			battle.to_menu()
		"zoom_in":
			dist *= 0.8
		"zoom_out":
			dist *= 1.25
		"turn_l":
			yaw += 0.35
		"turn_r":
			yaw -= 0.35
		"all":
			selected = _my_regs().filter(func(r): return not r.broken())
		"none":
			selected = []
		_:
			if id.begins_with("o_"):
				_order(id.substr(2))


func _order(what: String) -> void:
	var fire_v: bool = not selected[0].fire_at_will
	var run_v: bool = not selected[0].run
	for r in selected:
		if r.broken():
			continue
		match what:
			"halt":
				r.order_hold()
				r.pos = r.centroid + r.forward * 1.0
			"charge":
				if not deploying:
					if r.player_led and r.order == "follow":
						r.order_hold()
					r.order_charge(r.target if r.target != null and not r.target.broken() else r.nearest_foe_reg)
			"fire":
				r.fire_at_will = fire_v
			"volley":
				if r.fire_target == null:
					r.fire_target = r.nearest_foe_reg
				r.order_volley()
			"run":
				r.run = run_v
			"fallback":
				if not deploying:
					r.order_fallback()
			"follow":
				r.order_hold()
				r.order = "follow"


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	# Alerts show even in first person.
	var y := 84.0 if active else 150.0
	var ax := 14.0 if active else 226.0
	for a in alerts:
		var age: float = a[2]
		var alpha := clampf(1.0 - (age - 10.0) / 4.0, 0.0, 1.0)
		var r = a[1]
		var col := UI.PIPECLAY
		if r != null and r.side == 0 and String(a[0]).find("rall") < 0:
			col = Color(1.0, 0.72, 0.6)
		draw_style_box(_box(Color(UI.NIGHT, 0.72 * alpha), Color(col, 0.3 * alpha)), Rect2(ax, y, 520 if active else 420, 30))
		draw_string(font, Vector2(ax + 10, y + 22), String(a[0]), HORIZONTAL_ALIGNMENT_LEFT, 500, 19, Color(col, alpha))
		y += 34.0
	if not active:
		return
	var s := size
	# Title.
	var title: String = "DEPLOY YOUR ARMY" if deploying else ("COMMAND  ·  " + {"pause": "PAUSED", "slow": "SLOWED", "play": "RUNNING"}[speed])
	if not battle.player.alive:
		title = "YOU ARE DOWN  ·  COMMAND FROM ABOVE"
	if field.over != "":
		title = "VICTORY" if field.over == "won" else "DEFEAT"
	_text_c(title, Vector2(s.x * 0.5, 104 if deploying else 44), 30, UI.BRASS, display)
	if deploying and _hint_t > 0.0 or deploying:
		_text_c("Select a regiment, then tap the ground (a column of twos) or drag along it (a line as long as the drag).", Vector2(s.x * 0.5, 138), 18, UI.PIPECLAY)
	elif not selected.is_empty() and _hint_t > -30.0:
		_text_c("Tap the ground to march · drag along the ground to form a line · tap an enemy to attack", Vector2(s.x * 0.5, 76), 17, Color(UI.PIPECLAY, 0.85))
	if not lesson.is_empty():
		_draw_lesson()
	for b in _buttons():
		_draw_button(b)
	for c in _cards():
		_draw_card(c[0], c[1])


func _draw_lesson() -> void:
	var w := minf(size.x - 80.0, 820.0)
	var lines: Array = []
	for i in range(1, lesson.size()):
		lines.append_array(_wrap(String(lesson[i]), w - 48.0, 19))
	var h := 64.0 + lines.size() * 27.0 + 14.0
	var rect := Rect2(size.x * 0.5 - w * 0.5, 132.0, w, h)
	draw_style_box(_box(Color(UI.NIGHT, 0.86), Color(UI.BRASS, 0.7)), rect)
	_text_c(String(lesson[0]), Vector2(size.x * 0.5, rect.position.y + 42.0), 26, UI.BRASS, display)
	var y := rect.position.y + 76.0
	for l in lines:
		draw_string(font, Vector2(rect.position.x + 24.0, y), l, HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 19, UI.PIPECLAY)
		y += 27.0


func _wrap(text: String, width: float, fs: int) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" "):
		var t := word if line == "" else line + " " + word
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out


func _box(bg: Color, edge: Color, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var primary := bool(b.get("primary", false))
	var on := bool(b.get("on", false))
	var bg := Color(UI.WOOL_LIGHT, 0.88)
	var edge := Color(UI.PIPECLAY, 0.25)
	var fc := UI.PIPECLAY
	if primary:
		bg = UI.BRASS
		fc = UI.NIGHT
	elif on:
		bg = Color(UI.MADDER, 0.92)
		edge = Color(UI.BRASS, 0.7)
	if _pressed_id == b["id"] and _pressed_t > 0.0:
		bg = bg.lightened(0.25)
	draw_style_box(_box(bg, edge), r)
	var lab: String = b["label"]
	var fs := 20 if lab.length() > 1 else 30
	_text_c(lab, r.get_center() + Vector2(0, fs * 0.35), fs, fc)


func _draw_card(r, rect: Rect2) -> void:
	var sel: bool = r in selected
	var bg := Color(UI.WOOL, 0.9)
	var edge := Color(UI.PIPECLAY, 0.25)
	if sel:
		bg = Color(UI.WOOL_LIGHT, 0.96)
		edge = UI.BRASS
	if r.broken():
		bg = Color(0.25, 0.1, 0.09, 0.9)
	var sb := _box(bg, edge)
	if sel:
		sb.set_border_width_all(3)
	draw_style_box(sb, rect)
	var x := rect.position.x + 8.0
	var w := rect.size.x - 16.0
	_text_l(String(r.info["short"]) + (" ★" if r.player_led else ""), Vector2(x, rect.position.y + 24), 20, UI.BRASS if sel else UI.PIPECLAY, display)
	var name: String = r.title
	if r.player_led:
		name = "Your company"
	_text_l(name, Vector2(x, rect.position.y + 44), 14, Color(UI.SLATE.lightened(0.3)), null, w)
	# Men left, and nerve.
	var by := rect.position.y + 54.0
	draw_rect(Rect2(x, by, w, 7), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(x, by, w * r.strength(), 7), Color(0.85, 0.82, 0.72))
	draw_rect(Rect2(x, by + 11, w, 7), Color(0, 0, 0, 0.45))
	var m: float = clampf(r.morale / maxf(1.0, r.max_morale), 0.0, 1.0)
	var mc := Color(0.45, 0.75, 0.4).lerp(Color(0.9, 0.3, 0.2), 1.0 - m)
	draw_rect(Rect2(x, by + 11, w * m, 7), mc)
	var st := "%d men" % r.members.size() if not r.is_gun() else "%d guns" % r.members.size()
	var stc := Color(UI.PIPECLAY, 0.8)
	match r.state:
		"wavering":
			st = "WAVERING"
			stc = Color(1.0, 0.75, 0.3)
		"routing":
			st = "ROUTING"
			stc = Color(1.0, 0.4, 0.3)
		"shattered":
			st = "BROKEN"
			stc = Color(1.0, 0.4, 0.3)
	if r.engaged() and not r.broken():
		st += " · FIGHTING"
	_text_l(st, Vector2(x, rect.position.y + CARD_H - 8), 14, stc, null, w)


func _text_c(t: String, centre: Vector2, fs: int, col: Color, f: Font = null) -> void:
	var ff := f if f != null else font
	var w := ff.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(ff, Vector2(centre.x - w * 0.5 + 1, centre.y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(ff, Vector2(centre.x - w * 0.5, centre.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_l(t: String, pos: Vector2, fs: int, col: Color, f: Font = null, max_w := -1.0) -> void:
	var ff := f if f != null else font
	draw_string(ff, pos, t, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, col)
