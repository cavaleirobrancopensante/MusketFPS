extends Control
## After a won fight: what's left on the field, and the wagon it has to fit in.
##
##   left    ON THE FIELD: the enemy's weapons, hides and charms, whatever
##           they'd stolen, and the kit of our own fallen
##   right   THE WAGON: weight and space used, and everything in it
## Tap TAKE to load one, ALL for as many as fit; DROP in the wagon puts one
## back on the field to make room. TAKE EVERYTHING loads the most valuable
## things first (by weight) until the wagon is full. DONE leaves the rest.
## Crowns weigh nothing and go straight into the purse.

const UI := preload("res://scripts/ui.gd")
const CAMP := "res://scenes/aftermath.tscn"
const GOLD := Color("d4ad55") # brass (ui.gd)
const DIM := Color("9aa3b8") # slate (ui.gd)
const RED := Color(0.95, 0.42, 0.35)

var _field: VBoxContainer
var _wagon: VBoxContainer
var _kg: ProgressBar
var _space: ProgressBar
var _load_l: Label
var _done_b: Button
var _confirm := false # DONE tapped once with our fallen's kit still on the field


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top"]:
		v.set("offset_" + side, 14)
	for side in ["right", "bottom"]:
		v.set("offset_" + side, -14)
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(_label("THE FIELD IS YOURS", 30, GOLD))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_field = _column(row, "ON THE FIELD")
	var wcol := _column(row, "THE WAGON")
	_load_l = _label("", 17, Color.WHITE)
	wcol.get_parent().get_parent().get_child(0).add_sibling(_load_l)
	_kg = _bar(Color(0.85, 0.65, 0.3))
	_load_l.add_sibling(_kg)
	_space = _bar(Color(0.4, 0.65, 0.9))
	_kg.add_sibling(_space)
	_wagon = wcol
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 10)
	v.add_child(br)
	var all := _button("TAKE EVERYTHING THAT FITS", _take_all)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(all)
	_done_b = _button("DONE", _done)
	_done_b.custom_minimum_size.x = 260
	br.add_child(_done_b)
	_refresh()
	if "--loottest" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	UI.dress(l, size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UI.MIN_TOUCH * 1.4, UI.MIN_TOUCH)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _bar(col: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(0, 16)
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	p.add_theme_stylebox_override("fill", fill)
	return p


## A titled panel with a swipeable list; returns the list.
func _column(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.box(UI.WOOL, 12))
	parent.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_label(title, 22, GOLD))
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	return list


func _row(text: String, sub: String, buttons: Array) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(_label(text, 18, Color.WHITE))
	tv.add_child(_label(sub, 14, DIM))
	r.add_child(tv)
	for b in buttons:
		var btn := _button(b[0], b[1])
		btn.custom_minimum_size = Vector2(76, UI.MIN_TOUCH)
		btn.disabled = b.size() > 2 and bool(b[2])
		r.add_child(btn)
	return r


func _refresh() -> void:
	for c in _field.get_children():
		c.queue_free()
	for c in _wagon.get_children():
		c.queue_free()
	var loot: Array = Company.loot
	if loot.is_empty():
		_field.add_child(_label("Nothing left worth taking.", 18, DIM))
	for i in loot.size():
		var l: Dictionary = loot[i]
		var id: String = l["id"]
		var each := Company.load_of(id, 1)
		var room := Company.room_for(id)
		var sub := "%.1f kg, %.2f space each" % [each[0], each[1]] if id != "crowns" else "weighs nothing"
		if room <= 0:
			sub += "   ·   no room"
		var desc := _what(id)
		var ours := bool(l.get("ours", false))
		var r := _row("%s ×%d%s" % [Company.item_label(id), int(l["n"]), "   (our fallen)" if ours else ""], sub + desc,
			[["TAKE", _take.bind(i, 1), room <= 0], ["ALL", _take.bind(i, 99999), room <= 0]])
		if ours:
			(r.get_child(0).get_child(0) as Label).add_theme_color_override("font_color", GOLD)
		_field.add_child(r)
	var rows: Array = []
	for k in Company.CONSUMABLES:
		if int(Company.stores.get(k, 0)) > 0:
			rows.append([k, int(Company.stores[k])])
	for id in Company.stores["items"]:
		rows.append([id, int(Company.stores["items"][id])])
	for r in rows:
		var w := Company.load_of(String(r[0]), int(r[1]))
		var step := 10 if String(r[0]) in ["rations", "water", "ammo", "rum", "arrows", "bolts"] else 1
		_wagon.add_child(_row("%s ×%d" % [Company.item_label(r[0]), int(r[1])], "%.1f kg, %.1f space" % [w[0], w[1]],
			[["DROP", _drop.bind(String(r[0]), step)]]))
	_confirm = false
	_done_b.text = "DONE"
	var load := Company.wagon_load()
	_load_l.text = "%d / %d kg     space %.1f / %.0f     %d crowns" % [int(load[0]), int(Company.wagon_kg()), load[1],
		Company.wagon_space(), Company.money]
	_kg.max_value = Company.wagon_kg()
	_kg.value = load[0]
	_space.max_value = Company.wagon_space()
	_space.value = load[1]


static func _what(id: String) -> String:
	if Company.ITEMS.has(id):
		var it: Dictionary = Company.ITEMS[id]
		if it["slot"] == "goods":
			return "   ·   sells for about %d" % int(it.get("value", 0))
		return "   ·   %s" % String(Company.SLOT_NAMES.get(it["slot"], "")).to_lower()
	return ""


func _take(i: int, n: int) -> void:
	Company.take_loot(i, n)
	Company.save()
	_refresh()


func _drop(id: String, n: int) -> void:
	Company.drop_to_loot(id, n)
	Company.save()
	_refresh()


## Load the most valuable things (for their weight) first, as far as they fit.
func _take_all() -> void:
	var order: Array = Company.loot.duplicate()
	order.sort_custom(func(a, b): return _worth(a) > _worth(b))
	for e in order:
		var i: int = Company.loot.find(e)
		if i >= 0:
			Company.take_loot(i, 99999)
	Company.save()
	_refresh()


## Our own dead's muskets and kit come right after powder and money.
static func _worth(e: Dictionary) -> float:
	var id := String(e["id"])
	if bool(e.get("ours", false)) and id not in ["crowns", "ammo"]:
		return 1e5 + _worth({"id": id})
	match id:
		"crowns": return 1e9
		"ammo", "powder": return 1e6 # powder is beyond price in this land
		"lead": return 200.0
		"arrows", "bolts": return 120.0
		"rum": return 50.0
		"rations": return 20.0
		"water": return 1.0
	var it: Dictionary = Company.ITEMS.get(id, {})
	return float(it.get("value", 1)) / maxf(float(it.get("kg", 1.0)), 0.1)


func _done() -> void:
	var left := Company.ours_left()
	if left > 0 and not _confirm:
		_confirm = true
		_done_b.text = "LEAVE %d OF OUR KIT?" % left
		return
	Company.loot = []
	Company.save()
	Loading.change(CAMP)


## `-- --loottest`: a pile of loot, take everything, drop some, check the weight.
func _self_test() -> void:
	print("LOOTTEST pile ", Company.loot)
	print("  before ", Company.wagon_load(), " items ", Company.stores["items"])
	_take_all()
	print("  after  ", Company.wagon_load(), " items ", Company.stores["items"], " left ", Company.loot)
	_drop("rations", 10)
	print("  dropped 10 rations -> ", Company.wagon_load(), " pile ", Company.loot)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
