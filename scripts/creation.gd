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
const Colours := preload("res://scripts/colours.gd")
const CompanyScript := preload("res://scripts/company.gd")

## In plain words: what each attribute and skill means for you in play
## (the ? beside each opens it; Officer.ATTR_HELP / SKILLS["help"] give the
## exact numbers underneath).
const ATTR_LAY := {
	"aim": "How steady your hands are when you shoot. Higher Aim: your musket and pistol shots land closer to where you point. It also limits how high Marksmanship can go.",
	"strength": "How hard you hit up close. Higher Strength: bayonet, sabre and pike blows do more damage. It limits Bladework.",
	"constitution": "How much punishment you can take. Higher Constitution: more health, so you survive more hits before you go down.",
	"fitness": "How quick and enduring you are. Higher Fitness: you run faster in battle. It limits Pathfinding and Riding.",
	"wits": "How sharp your mind is. At 7 or more you get an extra skill point every time you level up. It limits Tactics, Surgery, Logistics, Tongues and Gunnery.",
	"presence": "How much men respect and follow you. It limits Leadership, Trade and Training: the skills that work through other people.",
}
const SKILL_LAY := {
	"marksmanship": "Your own shooting. Each level, your shots scatter less and you reload a little faster. Take it if you like to fight with the musket in your own hands.",
	"bladework": "Fighting up close yourself. Each level, your blows hurt more and your parry is easier to time. Take it if you charge in with the bayonet, sabre or pike.",
	"riding": "Fighting from horseback. Your horse runs and turns faster and your blows from the saddle land harder. Mostly for an Officer of Horse.",
	"gunnery": "Cannon. Every gun in your company reloads faster, and the shots you aim yourself land closer. Mostly for an Officer of Artillery.",
	"leadership": "Keeping your men brave and loyal. They hold their ground longer in battle before breaking, and fewer desert or mutiny when times are hard.",
	"tactics": "Commanding well. Your orders reach the men faster, your night watch spots attackers more often, and you get away more often when you try to slip off.",
	"surgery": "Saving your wounded. Wounded men get back on their feet sooner, and after a victory some men you thought dead pull through.",
	"logistics": "Packing the wagon well. It carries more food, water, powder and loot before it's full.",
	"pathfinding": "Finding your way across the land. You march faster on the map, see further, spot tracks from further away and read them better, and scouts get lost less.",
	"trade": "Haggling. Towns and villages sell to you cheaper and pay you more for what you sell them.",
	"training": "Teaching your men. They earn experience faster, so recruits become veterans sooner.",
	"tongues": "Languages. You pick up the local languages faster, and people understand you more often, which opens up talk, trade and news.",
}
## What each kind of officer gets, plainly: [heading, line] pairs.
const BRANCH_GETS := {
	"line": [["Your two units", "Two companies of musketeers (4 more men than the others start with)."],
		["Your own kit", "A musket with bayonet, a pistol and a sabre."],
		["Skills", "Marksmanship +3, Leadership +1: you shoot straighter and load faster."],
		["In battle", "You fight in the line with your men; their volleys are your main weapon."]],
	"pike": [["Your two units", "A company of musketeers and a block of pikemen (6 pikemen)."],
		["Your own kit", "A pike: the longest reach of any weapon. Hold BLOCK to brace it and anything that charges you runs onto the point."],
		["Skills", "Bladework +3, Leadership +1."],
		["In battle", "Your pikes stop charges cold (raptor riders, horse, brutes) while the muskets shoot."]],
	"artillery": [["Your two units", "A company of musketeers and a light gun with its crew."],
		["Your own kit", "You aim and fire the gun yourself: round shot far off, canister up close. You can leave it to fight on foot."],
		["Skills", "Gunnery +3, Tactics +1: every gun you ever have reloads faster."],
		["In battle", "Every battle starts with you at the gun."]],
	"cavalry": [["Your two units", "A company of musketeers and a troop of 6 horsemen (dragoons with carbines, and lancers)."],
		["Your own kit", "A horse, a lance, a sabre and a pistol. Couch the lance at the gallop for a deadly charge."],
		["Skills", "Riding +3, Bladework +1."],
		["In battle", "You start mounted; ride down skirmishers and hit them in the flank. Keep your horse alive."]],
}
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
# Your colours (colours.gd): the coat, and the flag.
var coat_i := 0
var field_i := 0
var charge_i := 1
var pattern_i := 0
var _swatches := {} # "coat"/"field"/"charge" -> [Button...]
var _flag_view: TextureRect
var _uniform_view: Control
var _pattern_l: Label


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
	top.add_theme_constant_override("separation", 10)
	var title := UI.heading(Lang.t("A New Campaign"), 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_stretch_ratio = 0.6
	top.add_child(title)
	# Your name, in the middle of the top.
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	nr.alignment = BoxContainer.ALIGNMENT_CENTER
	nr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := UI.heading(Lang.t("Your name"), 22)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nr.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.text = String(Officer.blank()["name"])
	_name_edit.custom_minimum_size = Vector2(300, 54)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.max_length = 28
	nr.add_child(_name_edit)
	nr.add_child(_dice(_random_name))
	top.add_child(nr)
	var back := _button(Lang.t("Back"), func(): Loading.change(MENU))
	back.custom_minimum_size = Vector2(130, 54)
	top.add_child(back)
	var begin := _button(Lang.t("BEGIN"), _on_begin, true)
	begin.custom_minimum_size = Vector2(190, 54)
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
	# Your colours: the coat and the flag, previewed side by side, and big
	# swatches filling the column.
	var v := _panel(1.0)
	v.add_theme_constant_override("separation", 6)
	v.add_child(UI.heading(Lang.t("Your colours"), 22))
	var prev := HBoxContainer.new()
	prev.add_theme_constant_override("separation", 12)
	prev.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(prev)
	_uniform_view = Uniform.new()
	_uniform_view.custom_minimum_size = Vector2(120, 124)
	_uniform_view.owner_screen = self
	prev.add_child(_uniform_view)
	_flag_view = TextureRect.new()
	_flag_view.custom_minimum_size = Vector2(186, 124)
	_flag_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag_view.stretch_mode = TextureRect.STRETCH_SCALE
	_flag_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	prev.add_child(_flag_view)
	v.add_child(_swatch_row(Lang.t("Coat"), "coat", Colours.COATS.map(func(e): return e[1])))
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	v.add_child(pr)
	var pl := _label(Lang.t("Flag"), 19, DIM)
	pl.custom_minimum_size = Vector2(70, 0)
	pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(pl)
	pr.add_child(_small("‹", func(): pattern_i = (pattern_i + Colours.PATTERNS.size() - 1) % Colours.PATTERNS.size(); _refresh()))
	_pattern_l = _label("", 20)
	_pattern_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pattern_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pattern_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pattern_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(_pattern_l)
	pr.add_child(_small("›", func(): pattern_i = (pattern_i + 1) % Colours.PATTERNS.size(); _refresh()))
	v.add_child(_swatch_row(Lang.t("Field"), "field", Colours.FLAG_COLOURS))
	v.add_child(_swatch_row(Lang.t("Device"), "charge", Colours.FLAG_COLOURS))
	# (in a scroll only in case a small screen can't fit it)
	var panel := _wrap(v)
	panel.remove_child(v)
	var sc := UI.scroll()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	panel.add_child(sc)
	return panel


## A row of colour swatches to pick from.
func _swatch_row(title: String, key: String, cols: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l := _label(title, 18, DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(l)
	var h := GridContainer.new()
	h.columns = 5
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	box.add_child(h)
	var list: Array = []
	for i in cols.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("col", cols[i])
		b.pressed.connect(func():
			match key:
				"coat": coat_i = i
				"field": field_i = i
				"charge": charge_i = i
			_refresh())
		h.add_child(b)
		list.append(b)
	_swatches[key] = list
	return box


func _colours() -> Dictionary:
	return {"coat": Colours.to_arr(Colours.COATS[coat_i][1]), "field": Colours.to_arr(Colours.FLAG_COLOURS[field_i]),
		"charge": Colours.to_arr(Colours.FLAG_COLOURS[charge_i]), "pattern": Colours.PATTERNS[pattern_i]}


func _flag_now() -> Dictionary:
	return {"field": Colours.FLAG_COLOURS[field_i], "charge": Colours.FLAG_COLOURS[charge_i], "pattern": Colours.PATTERNS[pattern_i]}


func _refresh_colours() -> void:
	var sel := {"coat": coat_i, "field": field_i, "charge": charge_i}
	for key in _swatches:
		var list: Array = _swatches[key]
		for i in list.size():
			var b: Button = list[i]
			var c: Color = b.get_meta("col")
			for st in ["normal", "hover", "pressed"]:
				var sb := StyleBoxFlat.new()
				sb.bg_color = c
				sb.set_corner_radius_all(4)
				if i == int(sel[key]):
					sb.set_border_width_all(3)
					sb.border_color = UI.BRASS
				else:
					sb.set_border_width_all(1)
					sb.border_color = Color(1, 1, 1, 0.25)
				b.add_theme_stylebox_override(st, sb)
	_flag_view.texture = Colours.flag_texture(_flag_now(), 60, 40)
	_pattern_l.text = Lang.t(Colours.PATTERN_NAMES[Colours.PATTERNS[pattern_i]])
	_uniform_view.queue_redraw()


func _middle_column() -> Control:
	var v := _panel(1.2)
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
		b.custom_minimum_size = Vector2(0, 78)
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
	_branch_text.add_theme_font_size_override("normal_font_size", 16)
	_branch_text.add_theme_font_size_override("bold_font_size", 19)
	v.add_child(_branch_text)
	v.add_child(UI.heading(Lang.t("Difficulty"), 22))
	var dg := HBoxContainer.new()
	dg.add_theme_constant_override("separation", 8)
	v.add_child(dg)
	for d in Officer.DIFFICULTY_ORDER:
		var b := _button(Lang.t(Officer.DIFFICULTY[d]["name"]), _on_difficulty.bind(d))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dg.add_child(b)
		_diff_btns[d] = b
	_diff_text = _label("", 15, DIM)
	v.add_child(_diff_text)
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
	h.add_child(_dice(_random_attrs))
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	for k in Officer.ATTRS:
		_attr_rows[k] = _row(list, Lang.t(Officer.ATTR_NAMES[k]), _on_attr.bind(k, -1), _on_attr.bind(k, 1), _explain.bind("attr", k))
	var sh := HBoxContainer.new()
	list.add_child(sh)
	var sk := UI.heading(Lang.t("Skills"), 22)
	sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sk)
	_skill_pts = _label("", 16, GOLD)
	_skill_pts.autowrap_mode = TextServer.AUTOWRAP_OFF
	sh.add_child(_skill_pts)
	sh.add_child(_dice(_random_skills))
	for k in Officer.SKILL_ORDER:
		_skill_rows[k] = _row(list, Lang.t(Officer.SKILLS[k]["name"]), _on_skill.bind(k, -1), _on_skill.bind(k, 1), _explain.bind("skill", k))
	return _wrap(v)


## A name, its value, and - / + buttons.
func _row(parent: Control, name: String, minus: Callable, plus: Callable, explain: Callable) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var q := _small("?", explain)
	q.custom_minimum_size = Vector2(40, 40)
	q.add_theme_color_override("font_color", GOLD)
	h.add_child(q)
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
	_refresh_colours()
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
		"line": kit = Lang.t("two companies of musketeers (+%d men)") % int(br["extra_men"])
		"pike": kit = Lang.t("a company of musketeers and a block of pikes (+%d pikemen), and a pike of your own") % int(br["extra_men"])
		"artillery": kit = Lang.t("a company of musketeers and a light gun with its crew")
		"cavalry": kit = Lang.t("a company of musketeers, and a horse, a lance, a sabre and a pistol, and a troop of %d dragoons and lancers") % int(br["extra_men"])
	var bt := "[b][color=#%s]%s[/color][/b]\n" % [GOLD.to_html(false), Lang.t(br["name"])]
	bt += Lang.t("[b]What you get:[/b]") + "\n"
	for row in BRANCH_GETS[branch]:
		bt += "[color=#%s]•  %s:[/color] %s\n" % [GOLD.to_html(false), Lang.t(row[0]), Lang.t(row[1])]
	bt += "\n[color=#%s]%s[/color]" % [DIM.to_html(false), Lang.t(br["text"])]
	_branch_text.text = bt
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


# ---------------------------------------------------------------- dice and ?

## A small button with a die on it.
func _dice(cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(UI.MIN_TOUCH, UI.MIN_TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = Lang.t("Roll at random")
	b.pressed.connect(cb)
	var d := Die.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(d)
	return b


func _random_name() -> void:
	_name_edit.text = "%s %s" % [CompanyScript.FIRST_NAMES.pick_random(), CompanyScript.LAST_NAMES.pick_random()]


## Spend the attribute points at random (sometimes lowering one to 4 for an
## extra point elsewhere, as you could by hand).
func _random_attrs() -> void:
	for k in attrs:
		attrs[k] = ATTR_BASE
	if randf() < 0.4:
		attrs[Officer.ATTRS.pick_random()] = ATTR_BASE - 1
	var guard := 0
	while _attr_left() > 0 and guard < 200:
		guard += 1
		var k: String = Officer.ATTRS.pick_random()
		if int(attrs[k]) < ATTR_START_MAX and int(attrs[k]) >= ATTR_BASE:
			attrs[k] = int(attrs[k]) + 1
	spent.clear()
	_refresh()


## Spend the skill points at random, within each skill's cap (favouring
## the ones your attributes are best at).
func _random_skills() -> void:
	spent.clear()
	var guard := 0
	while _skill_left() > 0 and guard < 300:
		guard += 1
		var k: String = Officer.SKILL_ORDER.pick_random()
		if randf() > float(_cap(k)) / 8.0:
			continue
		if _skill(k) + 1 <= _cap(k):
			spent[k] = int(spent.get(k, 0)) + 1
	_refresh()


## The ? beside an attribute or skill: what it means, in plain words and in
## numbers.
func _explain(what: String, k: String) -> void:
	var title := ""
	var lay := ""
	var exact := ""
	if what == "attr":
		title = Lang.t(Officer.ATTR_NAMES[k])
		lay = Lang.t(ATTR_LAY[k])
		exact = Lang.t(Officer.ATTR_HELP[k])
	else:
		var sk: Dictionary = Officer.SKILLS[k]
		title = Lang.t(sk["name"])
		lay = Lang.t(SKILL_LAY[k])
		exact = Lang.t(sk["help"]) + "\n" + Lang.t("Can't be raised above your %s.") % Lang.t(Officer.ATTR_NAMES[String(sk["attr"])])
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(UI.WOOL, 22, 8, 0.25))
	p.custom_minimum_size = Vector2(620, 0)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	shade.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UI.heading(title, 30))
	v.add_child(_label(lay, 21))
	var ex := _label(Lang.t("In numbers: ") + exact, 17, DIM)
	v.add_child(ex)
	var ok := _button(Lang.t("Got it"), func(): shade.queue_free(), true)
	v.add_child(ok)
	shade.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			shade.queue_free())
	# (centre it once it knows its size)
	await get_tree().process_frame
	if is_instance_valid(p):
		p.position = (shade.size - p.size) * 0.5


func _on_begin() -> void:
	var skills := {}
	for k in Officer.SKILL_ORDER:
		skills[k] = _skill(k)
	Settings.delete_slot(Settings.slot)
	Company.new_campaign({"difficulty": difficulty, "branch": branch, "name": _name_edit.text,
		"attrs": attrs.duplicate(), "attr_points": maxi(0, _attr_left()),
		"skills": skills, "skill_points": maxi(0, _skill_left()), "colours": _colours()})
	World.reset() # a new land for a new campaign
	Loading.change(INTRO) # the shipwreck, then the beach


## Your men in the coat you chose: a musketeer, and you beside him in the
## officer's darker coat.
class Uniform extends Control:
	var owner_screen = null

	func _draw() -> void:
		if owner_screen == null:
			return
		var coat: Color = Colours.COATS[owner_screen.coat_i][1]
		var off := coat.darkened(0.42) if coat.get_luminance() > 0.12 else coat.lightened(0.08)
		_man(Vector2(size.x * 0.3, size.y), coat, false)
		_man(Vector2(size.x * 0.72, size.y), off, true)

	func _man(foot: Vector2, coat: Color, officer: bool) -> void:
		var u := size.y / 78.0
		var white := Color(0.92, 0.9, 0.84)
		var black := Color(0.08, 0.08, 0.09)
		draw_rect(Rect2(foot + Vector2(-7, -22) * u, Vector2(6, 20) * u), white) # legs
		draw_rect(Rect2(foot + Vector2(1, -22) * u, Vector2(6, 20) * u), white)
		draw_rect(Rect2(foot + Vector2(-7, -9) * u, Vector2(6, 9) * u), black) # gaiters
		draw_rect(Rect2(foot + Vector2(1, -9) * u, Vector2(6, 9) * u), black)
		draw_rect(Rect2(foot + Vector2(-10, -50) * u, Vector2(20, 30) * u), coat) # coat
		draw_rect(Rect2(foot + Vector2(-14, -48) * u, Vector2(5, 20) * u), coat) # arms
		draw_rect(Rect2(foot + Vector2(9, -48) * u, Vector2(5, 20) * u), coat)
		if officer:
			draw_rect(Rect2(foot + Vector2(-10, -30) * u, Vector2(20, 3) * u), Color(0.75, 0.12, 0.1)) # sash
			draw_rect(Rect2(foot + Vector2(-13, -51) * u, Vector2(7, 3) * u), Color(0.85, 0.66, 0.2)) # epaulettes
			draw_rect(Rect2(foot + Vector2(6, -51) * u, Vector2(7, 3) * u), Color(0.85, 0.66, 0.2))
		else:
			draw_line(foot + Vector2(-9, -49) * u, foot + Vector2(9, -22) * u, white, 2.5 * u) # crossbelts
			draw_line(foot + Vector2(9, -49) * u, foot + Vector2(-9, -22) * u, white, 2.5 * u)
		draw_circle(foot + Vector2(0, -57) * u, 6.5 * u, Color(0.93, 0.76, 0.62)) # head
		if officer:
			draw_colored_polygon(PackedVector2Array([foot + Vector2(-13, -60) * u, foot + Vector2(0, -71) * u, foot + Vector2(13, -60) * u]), black) # bicorne
		else:
			draw_rect(Rect2(foot + Vector2(-6, -74) * u, Vector2(12, 12) * u), black) # shako


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


## A die face (five pips), for the random buttons.
class Die extends Control:
	func _draw() -> void:
		var s := minf(size.x, size.y) * 0.62
		var o := (size - Vector2(s, s)) * 0.5
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.93, 0.9, 0.82)
		sb.set_corner_radius_all(int(s * 0.18))
		draw_style_box(sb, Rect2(o, Vector2(s, s)))
		var pip := Color(0.15, 0.12, 0.1)
		var r := s * 0.09
		for p in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.5, 0.5), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
			draw_circle(o + p * s, r, pip)
