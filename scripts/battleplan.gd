extends Control
## The battle plan: where every man stands when a fight starts.
##
##   left and centre   the tactical map: you (the star) in the middle, the
##                     enemy's side at the top, every man a dot coloured by
##                     his tag, the wagon a box (usually at the rear)
##   right             the tag dropdown (+ NEW to make one, e.g. "Ranged 2"),
##                     what a tap or drag on the map does (LINE / MAN /
##                     WAGON), and the list of men (tap a name to pick him,
##                     tap his tag to put him in the selected tag)
##
## LINE: drag across the map and the selected tag forms a line along it,
## evenly spaced, in more ranks if the line is too short; a tap makes a line
## centred there. MAN: tap to put the picked man there. WAGON: tap to put the
## wagon. You can always drag a single dot (or the wagon) to move it.
##
## Places are metres from you: x to the right, y toward the enemy. In battle
## the formation turns and moves with you (FOLLOW), or stays put (HOLD).
## Opened from the map (PLAN), and before a fight you saw coming.

const UI := preload("res://scripts/ui.gd")
const MAP := "res://scenes/map.tscn"
const BATTLE := "res://scenes/battle.tscn"
const GOLD := Color(0.95, 0.8, 0.45)
const DIM := Color(0.72, 0.74, 0.8)
const TAG_COLORS := [Color(0.35, 0.55, 1.0), Color(0.95, 0.45, 0.3), Color(0.4, 0.85, 0.45),
	Color(0.9, 0.8, 0.3), Color(0.8, 0.45, 0.9), Color(0.3, 0.85, 0.85), Color(1.0, 0.6, 0.75), Color(0.75, 0.75, 0.75)]
const X_RANGE := 32.0 # metres either side shown
const Y_FWD := 20.0 # metres ahead shown
const Y_BACK := 22.0 # metres behind shown
const SPACING := 1.5 # metres between men in a line
const RANK_GAP := 1.6

var _mode := "line"
var _tag := "Musketeers"
var _sel = null # the picked man (Dictionary)
var _field: Control
var _tags: OptionButton
var _list: VBoxContainer
var _mode_btns := {}
var _new_tag: LineEdit
var _hint: Label
var _press := Vector2.ZERO
var _pressed := false
var _drag_what = null # a man (Dictionary), "wagon", or null
var _line_end := Vector2.ZERO
var _fighting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fighting = bool(Company.next_battle.get("planning", false))
	_ensure_places()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	for side in ["left", "right", "top", "bottom"]:
		row.set("offset_" + side, 10 if side in ["left", "top"] else -10)
	add_child(row)

	_field = Control.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_field.clip_contents = true
	_field.draw.connect(_draw_field)
	_field.gui_input.connect(_on_field_input)
	row.add_child(_field)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(340, 0)
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	side.add_child(_label("BATTLE PLAN", 26, GOLD))
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	side.add_child(tr)
	_tags = OptionButton.new()
	_tags.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	_tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tags.add_theme_font_size_override("font_size", 20)
	_tags.item_selected.connect(func(i): _tag = _tags.get_item_text(i); _refresh())
	tr.add_child(_tags)
	tr.add_child(_button("NEW", _on_new_tag, 80))
	_new_tag = LineEdit.new()
	_new_tag.placeholder_text = "Name the new tag, e.g. Ranged 2"
	_new_tag.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	_new_tag.add_theme_font_size_override("font_size", 18)
	_new_tag.visible = false
	_new_tag.text_submitted.connect(func(_t): _on_new_tag())
	side.add_child(_new_tag)
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 6)
	side.add_child(mr)
	for m in ["line", "man", "wagon"]:
		var b := _button(m.to_upper(), _set_mode.bind(m), 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		mr.add_child(b)
		_mode_btns[m] = b
	_hint = _label("", 15, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_hint)
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	side.add_child(br)
	var reset := _button("ONE LINE", _preset_line, 0)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(reset)
	var pk := _button("PIKES AHEAD", _preset_pikes, 0)
	pk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(pk)
	var done := _button("FIGHT!" if _fighting else "DONE", _on_done, 0)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(done)
	_field.resized.connect(_field.queue_redraw)
	_set_mode("line")
	if "--plantest" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


# ---------------------------------------------------------------- helpers

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, UI.MIN_TOUCH)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _men() -> Array:
	return Company.fit_men()


## Men placed on the field (the wagon crew goes with the wagon).
func _placed() -> Array:
	return _men().filter(func(m): return m["tag"] != "Wagon")


func _tag_color(tag: String) -> Color:
	var i := Company.tags.find(tag)
	return TAG_COLORS[maxi(i, 0) % TAG_COLORS.size()]


## Metres (x right, y forward) <-> pixels on the tactical map.
func _ppm() -> float:
	return minf(_field.size.x / (2.0 * X_RANGE), _field.size.y / (Y_FWD + Y_BACK))


func _to_px(m: Vector2) -> Vector2:
	var k := _ppm()
	var origin := Vector2(_field.size.x * 0.5, Y_FWD * k + (_field.size.y - (Y_FWD + Y_BACK) * k) * 0.5)
	return origin + Vector2(m.x, -m.y) * k


func _to_m(px: Vector2) -> Vector2:
	var k := _ppm()
	var origin := Vector2(_field.size.x * 0.5, Y_FWD * k + (_field.size.y - (Y_FWD + Y_BACK) * k) * 0.5)
	var m := (px - origin) / k
	return Vector2(clampf(snappedf(m.x, 0.5), -X_RANGE, X_RANGE), clampf(snappedf(-m.y, 0.5), -Y_BACK, Y_FWD))


func _pos_of(m: Dictionary) -> Vector2:
	var p = m.get("plan")
	return Vector2(float(p[0]), float(p[1])) if p is Array and p.size() == 2 else Vector2.ZERO


## Men without a place yet join the end of the line.
func _ensure_places() -> void:
	var men := _men()
	var placed := men.filter(func(m): return m.get("plan") is Array)
	if placed.is_empty():
		_preset_line()
		return
	var x := 0.0
	for m in placed:
		x = maxf(x, absf(_pos_of(m).x))
	for m in men:
		if not m.get("plan") is Array:
			x += SPACING
			m["plan"] = [x, 0.0]
		if not Company.tags.has(String(m.get("tag", ""))):
			m["tag"] = Company.tags[0]


# ---------------------------------------------------------------- the list

func _refresh() -> void:
	_tags.clear()
	for t in Company.tags:
		var n := _men().filter(func(m): return m["tag"] == t).size()
		_tags.add_item("%s (%d)" % [t, n])
	var idx := Company.tags.find(_tag)
	if idx < 0:
		_tag = Company.tags[0]
		idx = 0
	_tags.select(idx)
	_tags.set_item_text(idx, _tag + " (%d)" % _men().filter(func(m): return m["tag"] == _tag).size())
	for c in _list.get_children():
		c.queue_free()
	for m in _men():
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 4)
		var name_b := Button.new()
		name_b.text = Company.surname_title(m) + (" (pike)" if String(m["gear"]["primary"]) in ["pike", "spear"] else "")
		name_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_b.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
		name_b.add_theme_font_size_override("font_size", 16)
		name_b.toggle_mode = true
		name_b.button_pressed = m == _sel
		name_b.pressed.connect(func(): _sel = m; _set_mode("man"))
		r.add_child(name_b)
		var tag_b := Button.new()
		tag_b.text = String(m["tag"])
		tag_b.custom_minimum_size = Vector2(120, UI.MIN_TOUCH)
		tag_b.add_theme_font_size_override("font_size", 14)
		tag_b.add_theme_color_override("font_color", _tag_color(m["tag"]))
		tag_b.tooltip_text = "Put him in " + _tag
		tag_b.pressed.connect(func(): m["tag"] = _tag; Company.save(); _refresh())
		r.add_child(tag_b)
		_list.add_child(r)
	_field.queue_redraw()


func _set_mode(m: String) -> void:
	_mode = m
	for k in _mode_btns:
		(_mode_btns[k] as Button).button_pressed = k == m
	match m:
		"line":
			_hint.text = "LINE: drag across the field and the %s form a line along it (more ranks if it's short). Tap a name's tag button to put a man in %s." % [_tag, _tag]
		"man":
			_hint.text = "MAN: tap the field to put %s there. Pick another man from the list." % (Company.surname_title(_sel) if _sel != null else "the picked man")
		"wagon":
			_hint.text = "WAGON: tap to place the wagon. The men in the Wagon tag haul it (two at the shafts) and guard it. When looters come, each does what his nerve allows: runs, stands and shoots, or fights."
	_refresh()


func _on_new_tag() -> void:
	if not _new_tag.visible:
		_new_tag.visible = true
		_new_tag.text = "Group %d" % (Company.tags.size() + 1)
		_new_tag.grab_focus()
		_new_tag.select_all()
		return
	var name := _new_tag.text.strip_edges().substr(0, 18)
	_new_tag.visible = false
	if name == "" or Company.tags.has(name):
		return
	Company.tags.append(name)
	_tag = name
	Company.save()
	_refresh()


# ---------------------------------------------------------------- the field

func _on_field_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_pressed = true
			_press = e.position
			_line_end = e.position
			_drag_what = _hit(e.position)
		elif _pressed:
			_pressed = false
			_release(e.position)
	elif e is InputEventMouseMotion and _pressed:
		_line_end = e.position
		if _drag_what != null:
			var at := _to_m(e.position)
			if _drag_what is String:
				Company.wagon_plan = [at.x, at.y]
			else:
				_drag_what["plan"] = [at.x, at.y]
		_field.queue_redraw()


## A man's dot or the wagon under the finger (generous: 18 px).
func _hit(px: Vector2):
	if _to_px(Vector2(Company.wagon_plan[0], Company.wagon_plan[1])).distance_to(px) < 26.0:
		return "wagon"
	var best = null
	var bd := 18.0
	for m in _placed():
		var d := _to_px(_pos_of(m)).distance_to(px)
		if d < bd:
			bd = d
			best = m
	return best


func _release(px: Vector2) -> void:
	if _drag_what != null:
		if not _drag_what is String:
			_sel = _drag_what
		_drag_what = null
		Company.save()
		_refresh()
		return
	var a := _to_m(_press)
	var b := _to_m(px)
	match _mode:
		"wagon":
			Company.wagon_plan = [b.x, b.y]
		"man":
			if _sel != null:
				_sel["plan"] = [b.x, b.y]
		"line":
			if a.distance_to(b) < 1.0:
				# A tap: a line across the field, centred here.
				var n := _men().filter(func(m): return m["tag"] == _tag).size()
				var half := maxf(n - 1, 0) * SPACING * 0.5
				a = b - Vector2(half, 0)
				b = b + Vector2(half, 0)
			_form_line(_tag, a, b)
	Company.save()
	_refresh()


## The men of `tag` spread evenly along a..b (left to right as they stand
## now, so nobody crosses), in as many ranks as it takes.
func _form_line(tag: String, a: Vector2, b: Vector2) -> void:
	if tag == "Wagon":
		_hint.text = "The Wagon tag hauls and guards the wagon: move the wagon (WAGON) and they go with it."
		return
	var men := _men().filter(func(m): return m["tag"] == tag)
	if men.is_empty():
		return
	if a.x > b.x:
		var t := a
		a = b
		b = t
	var length := a.distance_to(b)
	var per_rank := clampi(int(length / SPACING) + 1, 1, men.size())
	var ranks := ceili(float(men.size()) / per_rank)
	men.sort_custom(func(m1, m2): return _pos_of(m1).x < _pos_of(m2).x)
	var dir := (b - a).normalized() if length > 0.01 else Vector2.RIGHT
	var back := Vector2(dir.y, -dir.x) # behind the line, away from the enemy
	if back.y > 0.0:
		back = -back
	for i in men.size():
		var rank := i / per_rank
		var k := i % per_rank
		var in_rank := mini(per_rank, men.size() - rank * per_rank)
		var f := 0.5 if in_rank == 1 else float(k) / (in_rank - 1)
		var p := a.lerp(b, f) if in_rank > 1 or length > 0.01 else a
		if in_rank == 1:
			p = a.lerp(b, 0.5)
		p += back * RANK_GAP * rank
		men[i]["plan"] = [snappedf(p.x, 0.25), snappedf(p.y, 0.25)]
	if ranks > 1:
		_hint.text = "%s: %d men in %d ranks." % [tag, men.size(), ranks]


func _preset_line() -> void:
	# Everyone in one line through you, pikes in the middle; the wagon behind.
	var men := _placed()
	men.sort_custom(func(m1, m2): return int(m1["tag"] == "Pikes") > int(m2["tag"] == "Pikes"))
	var order: Array = []
	for i in men.size():
		order.insert(order.size() / 2 if i % 2 == 0 else (order.size() + 1) / 2, men[i])
	var n := order.size()
	for i in n:
		var x := (i - (n - 1) * 0.5) * SPACING
		x += SPACING * 0.5 * (1.0 if x >= 0.0 else -1.0) # a gap for you
		order[i]["plan"] = [x, 0.0]
	Company.wagon_plan = [0.0, -12.0]
	Company.save()
	if _list != null:
		_refresh()


func _preset_pikes() -> void:
	# Pikes a few paces ahead in the centre, muskets on the wings and behind.
	var pikes := _placed().filter(func(m): return String(m["gear"]["primary"]) in ["pike", "spear"])
	var muskets := _placed().filter(func(m): return not String(m["gear"]["primary"]) in ["pike", "spear"])
	for i in pikes.size():
		pikes[i]["plan"] = [(i - (pikes.size() - 1) * 0.5) * 1.3, 3.0]
	var half := muskets.size() / 2
	for i in muskets.size():
		var left := i < half
		var k := i if left else i - half
		var x := (k + 1) * SPACING + pikes.size() * 0.65
		muskets[i]["plan"] = [-x if left else x, 0.5]
	Company.wagon_plan = [0.0, -12.0]
	Company.save()
	_refresh()


func _draw_field() -> void:
	var f := _field
	var k := _ppm()
	f.draw_rect(Rect2(Vector2.ZERO, f.size), Color(0.2, 0.27, 0.15))
	# A grid every 5 m, the enemy's side at the top.
	for x in range(-30, 31, 5):
		f.draw_line(_to_px(Vector2(x, -Y_BACK)), _to_px(Vector2(x, Y_FWD)), Color(1, 1, 1, 0.07 if x != 0 else 0.15), 1)
	for y in range(-20, 21, 5):
		f.draw_line(_to_px(Vector2(-X_RANGE, y)), _to_px(Vector2(X_RANGE, y)), Color(1, 1, 1, 0.07 if y != 0 else 0.15), 1)
	var font := ThemeDB.fallback_font
	var top := _to_px(Vector2(0, Y_FWD))
	f.draw_string(font, top + Vector2(-60, 26), "▲ ENEMY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.55, 0.45, 0.85))
	f.draw_string(font, Vector2(10, f.size.y - 12), "5 m squares", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.5))
	# The line being drawn.
	if _pressed and _drag_what == null and _mode == "line":
		f.draw_line(_press, _line_end, Color(1, 1, 1, 0.8), 3)
	# The wagon.
	var wp := _to_px(Vector2(Company.wagon_plan[0], Company.wagon_plan[1]))
	f.draw_rect(Rect2(wp - Vector2(0.75, 1.5) * k, Vector2(1.5, 3.0) * k), Color(0.6, 0.48, 0.32))
	f.draw_rect(Rect2(wp - Vector2(0.75, 1.5) * k, Vector2(1.5, 3.0) * k), Color(1, 1, 1, 0.6), false, 2)
	f.draw_string(font, wp + Vector2(k * 1.2, 6), "WAGON", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.8))
	# You.
	var me := _to_px(Vector2.ZERO)
	f.draw_colored_polygon(_star(me, 11.0), GOLD)
	# The men (the wagon crew at the shafts and beside the wagon).
	var r := maxf(0.45 * k, 6.0)
	var crew := 0
	for m in _men():
		var p := _to_px(_pos_of(m))
		if m["tag"] == "Wagon":
			var wpos := Vector2(Company.wagon_plan[0], Company.wagon_plan[1])
			var off: Vector2 = [Vector2(-0.5, 2.6), Vector2(0.5, 2.6)][crew] if crew < 2 else Vector2(-1.8 if crew % 2 == 0 else 1.8, 0.5 - 1.6 * ((crew - 2) / 2))
			p = _to_px(wpos + off)
			crew += 1
		var col := _tag_color(m["tag"])
		if String(m["gear"]["primary"]) in ["pike", "spear"]:
			f.draw_line(p, p + Vector2(0, -r * 2.4), Color(0.85, 0.85, 0.9), 2)
		f.draw_circle(p, r, col)
		if m == _sel:
			f.draw_arc(p, r + 4, 0, TAU, 20, Color.WHITE, 2)


static func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	return pts


func _on_done() -> void:
	Company.save()
	if _fighting:
		Company.next_battle.erase("planning")
		Company.save()
		get_tree().change_scene_to_file(BATTLE)
	else:
		get_tree().change_scene_to_file(MAP)


## `-- --plantest`: draw a line for the muskets, put the pikes ahead, a new tag.
func _self_test() -> void:
	_tag = "Musketeers"
	_form_line("Musketeers", Vector2(-10, 0), Vector2(10, 0))
	_preset_pikes()
	_new_tag.visible = true
	_new_tag.text = "Ranged 2"
	_on_new_tag()
	var men := _men()
	men[0]["tag"] = "Ranged 2"
	_form_line("Ranged 2", Vector2(-3, -4), Vector2(3, -4))
	Company.wagon_plan = [6.0, -14.0]
	_refresh()
	var out: Array = []
	for m in men:
		out.append("%s:%s@%s" % [Company.surname_title(m), m["tag"], m.get("plan", "wagon")])
	print("PLANTEST tags ", Company.tags, " wagon ", Company.wagon_plan)
	print("  ", ", ".join(out))
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
