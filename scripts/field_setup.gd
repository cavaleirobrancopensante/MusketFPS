extends Control
## Tests > Field battle: choose the ground and both armies, then fight.
##
##   Battlefield   open field, hills, river crossing, town, woods
##   Unit size     men in a regiment (cavalry half, brutes fewer; a battery
##                 is always two guns)
##   Your army     how many regiments of each kind, on top of your own
##                 company of musketeers that you lead on foot
##   The enemy     a lizard warband (warriors, javelin throwers, brutes,
##                 raptor riders) or a rival army in red coats (the same
##                 kinds as yours), and how many of each
##
## The count at the bottom warns when the battle gets big for a phone.

const UI := preload("res://scripts/ui.gd")
const Field := preload("res://scripts/field.gd")
const Terrain := preload("res://scripts/field_terrain.gd")
const BATTLE := "res://scenes/battle.tscn"
const MENU := "res://scenes/menu.tscn"

const HUMAN_INFO := {
	"musket": ["Musketeers", "Two ranks of muskets: volleys at 60 m, bayonets after."],
	"pike": ["Pikemen", "Three ranks of long pikes. Stand still and no horse gets through."],
	"bow": ["Bowmen", "Light archers: quick, long-ranged, lob arrows over the line."],
	"xbow": ["Crossbowmen", "Slow to span, but a bolt goes through anything."],
	"cav": ["Cavalry", "Sabres on horseback. Charge home, wheel away, charge again."],
	"gun": ["Cannon", "A battery of two field guns and their crews. Round shot and canister."],
}
const LIZARD_INFO := {
	"liz_warrior": ["Warriors", "Shield and cleaver, in a howling mob."],
	"liz_skirm": ["Javelin throwers", "Out in front, throwing from 30 m. Run from blades."],
	"liz_brute": ["Brutes", "Huge, slow, hard to kill. Their blows knock men flat."],
	"liz_raptor": ["Raptor riders", "Lizards on running raptors: fast, and they go for the flanks."],
}
const SIZES := [[12, "Small · 12"], [20, "Medium · 20"], [30, "Large · 30"]]

var cfg := {}
var _counts := {} # "you:kind" / "foe:kind" -> Label
var _foe_box: VBoxContainer
var _map_buttons := {}
var _size_buttons := {}
var _army_buttons := {}
var _pace_buttons := {}
var _total: Label
var _auto: CheckButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cfg = Settings.field_last.duplicate(true)
	if cfg.is_empty() or not cfg.has("you"):
		cfg = {"map": "hills", "size": 20, "foe_army": "lizards", "auto_pause": false,
			"you": {"musket": 2, "pike": 1, "bow": 1, "xbow": 0, "cav": 1, "gun": 1},
			"foe": {"liz_warrior": 3, "liz_skirm": 1, "liz_brute": 1, "liz_raptor": 1},
			"foe_h": {"musket": 3, "pike": 1, "bow": 1, "xbow": 0, "cav": 1, "gun": 1},
			"foe_l": {"liz_warrior": 3, "liz_skirm": 1, "liz_brute": 1, "liz_raptor": 1}}
	var bg := ColorRect.new()
	bg.color = UI.NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UI.heading(Lang.t("Field battle"), 36))
	var sub := Label.new()
	sub.text = Lang.t("   Regiments against regiments. You lead your company on foot; COMMAND gives every regiment its orders.")
	sub.add_theme_color_override("font_color", UI.SLATE)
	sub.add_theme_font_size_override("font_size", 17)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# The ground and the size of a regiment.
	var left := _panel(cols, 0.8)
	left.add_child(_sub(Lang.t("Battlefield")))
	var maps := GridContainer.new()
	maps.columns = 2
	maps.add_theme_constant_override("h_separation", 6)
	maps.add_theme_constant_override("v_separation", 6)
	left.add_child(maps)
	for m in Terrain.MAPS:
		var b := _toggle(Lang.t(Terrain.MAP_NAMES[m]), func(): _set_map(m))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		maps.add_child(b)
		_map_buttons[m] = b
	left.add_child(_sub(Lang.t("Men in a regiment")))
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 6)
	left.add_child(sizes)
	for sz in SIZES:
		var b2 := _toggle(str(sz[0]), func(): _set_men(int(sz[0])))
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sizes.add_child(b2)
		_size_buttons[int(sz[0])] = b2
	left.add_child(_sub(Lang.t("Pace")))
	var paces := HBoxContainer.new()
	paces.add_theme_constant_override("separation", 6)
	left.add_child(paces)
	for pc in [[1.0, "Brisk"], [0.75, "Steady"], [0.55, "Slow"]]:
		var b3 := _toggle(pc[1], func(): _set_pace(float(pc[0])))
		b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		paces.add_child(b3)
		_pace_buttons[float(pc[0])] = b3
	var size_note := Label.new()
	size_note.text = Lang.t("Horse come in half that, brutes fewer; a battery is two guns.")
	size_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_note.add_theme_font_size_override("font_size", 14)
	size_note.add_theme_color_override("font_color", UI.SLATE)
	left.add_child(size_note)
	_auto = CheckButton.new()
	_auto.text = Lang.t("Auto-pause on trouble")
	_auto.button_pressed = bool(cfg.get("auto_pause", false))
	_auto.add_theme_font_size_override("font_size", 18)
	_auto.toggled.connect(func(on): cfg["auto_pause"] = on)
	left.add_child(_auto)

	# Your army.
	var mid := _panel(cols, 1.25)
	mid.add_child(_sub(Lang.t("Your army")))
	var note := Label.new()
	note.text = Lang.t("With your own company of musketeers, which you lead.")
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", UI.SLATE)
	mid.add_child(note)
	for k in Field.HUMAN_KINDS:
		mid.add_child(_row("you", k, HUMAN_INFO[k]))

	# The enemy.
	var right := _panel(cols, 1.25)
	right.add_child(_sub(Lang.t("The enemy")))
	var armies := HBoxContainer.new()
	armies.add_theme_constant_override("separation", 8)
	right.add_child(armies)
	for a in [["lizards", Lang.t("Lizard warband")], ["humans", Lang.t("Rival army")]]:
		var b3 := _toggle(a[1], func(): _set_army(a[0]))
		b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		armies.add_child(b3)
		_army_buttons[a[0]] = b3
	_foe_box = VBoxContainer.new()
	_foe_box.add_theme_constant_override("separation", 6)
	right.add_child(_foe_box)

	# Fight.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	root.add_child(foot)
	var back := Button.new()
	back.text = Lang.t("Back")
	back.custom_minimum_size = Vector2(180, 64)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU))
	foot.add_child(back)
	_total = Label.new()
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_total.add_theme_font_size_override("font_size", 19)
	_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_total)
	var go := Button.new()
	go.text = Lang.t("Fight")
	go.theme_type_variation = "PrimaryButton"
	go.custom_minimum_size = Vector2(240, 64)
	go.add_theme_font_size_override("font_size", 28)
	go.pressed.connect(_fight)
	foot.add_child(go)

	_set_map(String(cfg["map"]))
	_set_men(int(cfg["size"]))
	_set_army(String(cfg["foe_army"]))
	_set_pace(float(cfg.get("pace", 0.75)))


func _panel(parent: Control, stretch: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(UI.WOOL, 0.96), 14, 6, 0.2))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = stretch
	parent.add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _sub(text: String) -> Label:
	var l := UI.heading(text, 24)
	return l


func _toggle(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(cb)
	return b


## One kind of regiment: name and what it's for, and − n + .
func _row(side: String, kind: String, info: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.add_theme_constant_override("separation", -2)
	row.add_child(txt)
	var n := Label.new()
	n.text = Lang.t(info[0])
	n.add_theme_font_size_override("font_size", 20)
	n.add_theme_color_override("font_color", UI.PIPECLAY)
	txt.add_child(n)
	var d := Label.new()
	d.text = Lang.t(info[1])
	d.add_theme_font_size_override("font_size", 14)
	d.add_theme_color_override("font_color", UI.SLATE)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(d)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(56, 52)
	minus.add_theme_font_size_override("font_size", 28)
	minus.pressed.connect(func(): _bump(side, kind, -1))
	row.add_child(minus)
	var c := Label.new()
	c.custom_minimum_size = Vector2(34, 0)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_theme_font_override("font", UI.display_font())
	c.add_theme_font_size_override("font_size", 30)
	c.add_theme_color_override("font_color", UI.BRASS)
	row.add_child(c)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(56, 52)
	plus.add_theme_font_size_override("font_size", 28)
	plus.pressed.connect(func(): _bump(side, kind, 1))
	row.add_child(plus)
	_counts[side + ":" + kind] = c
	return row


func _dict(side: String) -> Dictionary:
	return cfg["you"] if side == "you" else cfg["foe"]


func _bump(side: String, kind: String, d: int) -> void:
	var dd := _dict(side)
	dd[kind] = clampi(int(dd.get(kind, 0)) + d, 0, 8)
	_refresh()


func _set_map(m: String) -> void:
	cfg["map"] = m
	for k in _map_buttons:
		_map_buttons[k].button_pressed = k == m
	_refresh()


func _set_men(n: int) -> void:
	cfg["size"] = n
	for k in _size_buttons:
		_size_buttons[k].button_pressed = k == n
	_refresh()


func _set_pace(p: float) -> void:
	cfg["pace"] = p
	for k in _pace_buttons:
		_pace_buttons[k].button_pressed = is_equal_approx(k, p)


func _set_army(a: String) -> void:
	# Keep each army's numbers apart, so switching back and forth keeps them.
	if cfg.get("foe_army", "") == "lizards":
		cfg["foe_l"] = cfg["foe"]
	elif cfg.get("foe_army", "") == "humans":
		cfg["foe_h"] = cfg["foe"]
	cfg["foe_army"] = a
	cfg["foe"] = (cfg.get("foe_l", {}) if a == "lizards" else cfg.get("foe_h", {})).duplicate()
	for k in _army_buttons:
		_army_buttons[k].button_pressed = k == a
	for c in _foe_box.get_children():
		c.queue_free()
	for k in _counts.keys():
		if k.begins_with("foe:"):
			_counts.erase(k)
	if a == "lizards":
		for k in Field.LIZARD_KINDS:
			_foe_box.add_child(_row("foe", k, LIZARD_INFO[k]))
	else:
		for k in Field.HUMAN_KINDS:
			_foe_box.add_child(_row("foe", k, HUMAN_INFO[k]))
	_refresh()


func _men(side: String) -> int:
	var size := int(cfg["size"])
	var n := 0
	for k in _dict(side):
		var info: Dictionary = Field.KINDS[k]
		var each := int(info.get("guns", 0)) * 4 if k == "gun" else maxi(4, int(round(size * float(info["men"]))))
		n += each * int(_dict(side)[k])
	if side == "you":
		n += size
	return n


func _refresh() -> void:
	for key in _counts:
		var parts: PackedStringArray = key.split(":")
		_counts[key].text = str(int(_dict(parts[0]).get(parts[1], 0)))
	if _total == null:
		return
	var a := _men("you")
	var b := _men("foe")
	var t := Lang.t("%d of yours against %d") % [a, b]
	if a + b > 360:
		t += Lang.t("  ·  a big battle: it may run slowly on a phone")
	_total.text = t
	_total.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4) if a + b > 360 else UI.PIPECLAY)


func _fight() -> void:
	var total := 0
	for k in cfg["foe"]:
		total += int(cfg["foe"][k])
	if total == 0:
		cfg["foe"][Field.LIZARD_KINDS[0] if cfg["foe_army"] == "lizards" else "musket"] = 1
	if cfg["foe_army"] == "lizards":
		cfg["foe_l"] = cfg["foe"]
	else:
		cfg["foe_h"] = cfg["foe"]
	Settings.field = cfg.duplicate(true)
	Settings.field_last = cfg.duplicate(true)
	Settings.stress = false
	Settings.mixed = false
	Settings.playground = false
	Settings.siege_test = false
	Company.active = false
	Loading.change(BATTLE)
