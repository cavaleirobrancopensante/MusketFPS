extends Control
## A new campaign: who you are before the ship goes down.
##
##   left    your name, and the difficulty (Easy, Normal, Hard, Ironman)
##   middle  what kind of officer you are: the line, pikes, artillery or
##           horse. Each brings its own skills, kit and men, and its own
##           first battle on the beach (field_prologue.gd)
##   right   your attributes and skills: points to spend (- takes one back)
##
## BEGIN starts the campaign in the slot the menu chose (the shipwreck
## first); BACK returns to the menu.

const UI := preload("res://scripts/ui.gd")
const Officer := preload("res://scripts/officer.gd")
const INTRO := "res://scenes/intro.tscn"
const MENU := "res://scenes/menu.tscn"

const GOLD := Color("d4ad55")
const DIM := Color("9aa3b8")
const GREEN := Color(0.55, 0.9, 0.55)
const CARD := Color("263352")
const CARD_ON := Color("3a4a70")

const ATTR_POINTS := 4 # to spend over the base of 5 in each
const SKILL_POINTS := 5 # to spend on top of what your branch gives
const ATTR_BASE := 5
const ATTR_START_MAX := 8

var difficulty := "normal"
var branch := "line"
var attrs := {}
var spent := {} # skill -> points you put in
var _name_edit: LineEdit
var _diff_btns := {}
var _diff_text: Label
var _branch_btns := {}
var _branch_text: RichTextLabel
var _attr_rows := {}
var _skill_rows := {}
var _attr_pts: Label
var _skill_pts: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in Officer.ATTRS:
		attrs[k] = ATTR_BASE
	var bg := ColorRect.new()
	bg.color = UI.NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UI.heading(Lang.t("A New Campaign"), 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := _button(Lang.t("Back"), func(): Loading.change(MENU))
	back.custom_minimum_size = Vector2(150, 54)
	top.add_child(back)
	var begin := _button(Lang.t("BEGIN"), _on_begin, true)
	begin.custom_minimum_size = Vector2(220, 54)
	top.add_child(begin)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	root.add_child(cols)
	cols.add_child(_left_column())
	cols.add_child(_middle_column())
	cols.add_child(_right_column())
	_refresh()


func _panel(stretch: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(UI.WOOL, 14, 6, 0.2))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = stretch
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	p.set_meta("box", v)
	return v


func _wrap(v: VBoxContainer) -> Control:
	return v.get_parent()


func _label(text: String, fsize: int, col: Color = UI.PIPECLAY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	b.add_theme_font_size_override("font_size", 20)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	return b


func _small(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(48, 40)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- the columns

func _left_column() -> Control:
	var v := _panel(0.8)
	v.add_child(UI.heading(Lang.t("Your name"), 22))
	_name_edit = LineEdit.new()
	_name_edit.text = String(Officer.blank()["name"])
	_name_edit.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.max_length = 28
	v.add_child(_name_edit)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	v.add_child(UI.heading(Lang.t("Difficulty"), 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for d in Officer.DIFFICULTY_ORDER:
		var b := _button(Lang.t(Officer.DIFFICULTY[d]["name"]), _on_difficulty.bind(d))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		_diff_btns[d] = b
	_diff_text = _label("", 16, DIM)
	v.add_child(_diff_text)
	return _wrap(v)


func _middle_column() -> Control:
	var v := _panel(1.25)
	v.add_child(UI.heading(Lang.t("What kind of officer are you?"), 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for k in Officer.BRANCH_ORDER:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_branch.bind(k))
		var emblem := Emblem.new()
		emblem.kind = k
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emblem.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		emblem.offset_right = 86
		b.add_child(emblem)
		var l := _label(Lang.t(Officer.BRANCHES[k]["short"]), 19)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.offset_left = 92
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
		grid.add_child(b)
		_branch_btns[k] = b
	_branch_text = RichTextLabel.new()
	_branch_text.bbcode_enabled = true
	_branch_text.fit_content = true
	_branch_text.scroll_active = false
	_branch_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_branch_text.add_theme_font_size_override("normal_font_size", 17)
	_branch_text.add_theme_font_size_override("bold_font_size", 19)
	v.add_child(_branch_text)
	return _wrap(v)


func _right_column() -> Control:
	var v := _panel(1.0)
	var h := HBoxContainer.new()
	v.add_child(h)
	var ah := UI.heading(Lang.t("Attributes"), 22)
	ah.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ah)
	_attr_pts = _label("", 16, GOLD)
	_attr_pts.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(_attr_pts)
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	for k in Officer.ATTRS:
		_attr_rows[k] = _row(list, Lang.t(Officer.ATTR_NAMES[k]), _on_attr.bind(k, -1), _on_attr.bind(k, 1))
	var sh := HBoxContainer.new()
	list.add_child(sh)
	var sk := UI.heading(Lang.t("Skills"), 22)
	sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sk)
	_skill_pts = _label("", 16, GOLD)
	_skill_pts.autowrap_mode = TextServer.AUTOWRAP_OFF
	sh.add_child(_skill_pts)
	for k in Officer.SKILL_ORDER:
		_skill_rows[k] = _row(list, Lang.t(Officer.SKILLS[k]["name"]), _on_skill.bind(k, -1), _on_skill.bind(k, 1))
	return _wrap(v)


## A name, its value, and - / + buttons.
func _row(parent: Control, name: String, minus: Callable, plus: Callable) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var l := _label(name, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := _label("", 20, GOLD)
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.custom_minimum_size = Vector2(34, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(val)
	var m := _small("−", minus)
	h.add_child(m)
	var p := _small("+", plus)
	h.add_child(p)
	return [val, m, p, l]


# ---------------------------------------------------------------- the rules

func _attr_left() -> int:
	var used := 0
	for k in attrs:
		used += int(attrs[k]) - ATTR_BASE
	return ATTR_POINTS - used


func _skill_left() -> int:
	var used := 0
	for k in spent:
		used += int(spent[k])
	return SKILL_POINTS - used


## A skill's level as you'd start: Tongues 1 (you've a little of the
## language of the coast traders), your branch's, and what you spent.
func _skill(k: String) -> int:
	var base := 1 if k == "tongues" else 0
	return base + int(Officer.BRANCHES[branch]["skills"].get(k, 0)) + int(spent.get(k, 0))


func _cap(k: String) -> int:
	return int(attrs[String(Officer.SKILLS[k]["attr"])])


func _on_difficulty(d: String) -> void:
	difficulty = d
	_refresh()


func _on_branch(k: String) -> void:
	branch = k
	# Points over a skill's cap come back to you.
	for s in spent.keys():
		while int(spent[s]) > 0 and _skill(s) > _cap(s):
			spent[s] = int(spent[s]) - 1
	_refresh()


func _on_attr(k: String, d: int) -> void:
	var v := int(attrs[k]) + d
	if d > 0 and (_attr_left() <= 0 or v > ATTR_START_MAX):
		return
	if d < 0 and v < ATTR_BASE - 1:
		return # (a point below 5 buys a point elsewhere, no more)
	attrs[k] = v
	# Lowering an attribute can push a skill over its cap: take those back.
	for s in spent.keys():
		while int(spent[s]) > 0 and _skill(s) > _cap(s):
			spent[s] = int(spent[s]) - 1
	_refresh()


func _on_skill(k: String, d: int) -> void:
	var v := int(spent.get(k, 0)) + d
	if v < 0:
		return
	if d > 0 and (_skill_left() <= 0 or _skill(k) + 1 > _cap(k)):
		return
	spent[k] = v
	_refresh()


func _refresh() -> void:
	for d in _diff_btns:
		(_diff_btns[d] as Button).button_pressed = d == difficulty
	_diff_text.text = Lang.t(Officer.DIFFICULTY[difficulty]["text"])
	for k in _branch_btns:
		(_branch_btns[k] as Button).button_pressed = k == branch
	var br: Dictionary = Officer.BRANCHES[branch]
	var gives: Array = []
	for s in br["skills"]:
		gives.append("%s +%d" % [Lang.t(Officer.SKILLS[s]["name"]), int(br["skills"][s])])
	var kit := ""
	match branch:
		"line": kit = Lang.t("+%d musketeers") % int(br["extra_men"])
		"pike": kit = Lang.t("+%d pikemen, and a pike of your own") % int(br["extra_men"])
		"artillery": kit = Lang.t("a light gun and its crew")
		"cavalry": kit = Lang.t("a horse, a lance, a sabre and a pistol")
	_branch_text.text = Lang.t("[b][color=#%s]%s[/color][/b]\n%s\n\n[color=#%s]%s[/color] %s\n[color=#%s]%s[/color] %s") % [
		GOLD.to_html(false), Lang.t(br["name"]), Lang.t(br["text"]),
		DIM.to_html(false), Lang.t("Skills:"), ", ".join(gives), DIM.to_html(false), Lang.t("You bring:"), kit]
	_attr_pts.text = Lang.t("%d to spend") % _attr_left()
	for k in _attr_rows:
		var row: Array = _attr_rows[k]
		(row[0] as Label).text = str(int(attrs[k]))
		(row[1] as Button).disabled = int(attrs[k]) <= ATTR_BASE - 1
		(row[2] as Button).disabled = _attr_left() <= 0 or int(attrs[k]) >= ATTR_START_MAX
	_skill_pts.text = Lang.t("%d to spend") % _skill_left()
	for k in _skill_rows:
		var row: Array = _skill_rows[k]
		var lv := _skill(k)
		(row[0] as Label).text = str(lv)
		(row[0] as Label).add_theme_color_override("font_color", GREEN if int(br["skills"].get(k, 0)) > 0 else GOLD)
		(row[1] as Button).disabled = int(spent.get(k, 0)) <= 0
		(row[2] as Button).disabled = _skill_left() <= 0 or lv + 1 > _cap(k)
		(row[3] as Label).tooltip_text = Lang.t(String(Officer.SKILLS[k]["help"]))


func _on_begin() -> void:
	var skills := {}
	for k in Officer.SKILL_ORDER:
		skills[k] = _skill(k)
	Settings.delete_slot(Settings.slot)
	Company.new_campaign({"difficulty": difficulty, "branch": branch, "name": _name_edit.text,
		"attrs": attrs.duplicate(), "attr_points": maxi(0, _attr_left()),
		"skills": skills, "skill_points": maxi(0, _skill_left())})
	World.reset() # a new land for a new campaign
	Loading.change(INTRO) # the shipwreck, then the beach


## A branch's badge: crossed muskets, a pike head, a gun, a horse's head.
class Emblem extends Control:
	var kind := "line"

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.4
		var col := Color("d4ad55")
		var dark := Color("10172a")
		draw_circle(c, s * 1.05, Color(0, 0, 0, 0.25))
		match kind:
			"line":
				for sgn in [-1.0, 1.0]:
					var a := c + Vector2(-s * 0.6 * sgn, s * 0.6)
					var b := c + Vector2(s * 0.5 * sgn, -s * 0.5)
					draw_line(a, b, col, s * 0.14)
					draw_line(b, b + (b - a).normalized() * s * 0.35, Color(0.85, 0.85, 0.9), s * 0.06)
					draw_rect(Rect2(a - Vector2(s * 0.12, s * 0.12), Vector2(s * 0.24, s * 0.24)), col.darkened(0.3))
			"pike":
				draw_line(c + Vector2(0, s), c + Vector2(0, -s * 0.5), col.darkened(0.25), s * 0.12)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.05), c + Vector2(s * 0.22, -s * 0.5), c + Vector2(0, -s * 0.38), c + Vector2(-s * 0.22, -s * 0.5)]), Color(0.85, 0.85, 0.9))
				draw_line(c + Vector2(-s * 0.3, -s * 0.35), c + Vector2(s * 0.3, -s * 0.35), col, s * 0.08)
			"artillery":
				draw_line(c + Vector2(-s * 0.9, s * 0.05), c + Vector2(s * 0.85, -s * 0.35), col, s * 0.3)
				draw_circle(c + Vector2(-s * 0.95, s * 0.08), s * 0.2, col)
				draw_circle(c + Vector2(-s * 0.15, s * 0.45), s * 0.45, dark)
				draw_arc(c + Vector2(-s * 0.15, s * 0.45), s * 0.42, 0.0, TAU, 20, col, s * 0.1)
				for i in 6:
					var a2 := TAU * i / 6.0
					draw_line(c + Vector2(-s * 0.15, s * 0.45), c + Vector2(-s * 0.15, s * 0.45) + Vector2(cos(a2), sin(a2)) * s * 0.4, col, s * 0.05)
			"cavalry":
				# A horse's head in profile, facing left.
				var pts := PackedVector2Array([
					c + Vector2(s * 0.5, s * 0.95), c + Vector2(s * 0.45, s * 0.1), c + Vector2(s * 0.25, -s * 0.55),
					c + Vector2(s * 0.05, -s * 0.95), c + Vector2(-s * 0.05, -s * 0.7), c + Vector2(-s * 0.35, -s * 0.5),
					c + Vector2(-s * 0.9, s * 0.05), c + Vector2(-s * 0.85, s * 0.3), c + Vector2(-s * 0.55, s * 0.35),
					c + Vector2(-s * 0.2, s * 0.1), c + Vector2(-s * 0.1, s * 0.95)])
				draw_colored_polygon(pts, col)
				draw_circle(c + Vector2(-s * 0.3, -s * 0.3), s * 0.07, dark)
				draw_line(c + Vector2(s * 0.3, -s * 0.5), c + Vector2(s * 0.6, s * 0.6), col.darkened(0.4), s * 0.1)
