extends Control
## YOUR character sheet: the officer, as the Company screen is for the men.
##
##   left    your picture (a live 3D model in your kit; drag to turn), your
##           name (tap to rename), rank, level and experience, your record
##   middle  ATTRIBUTES with + buttons while you have points; YOUR KIT (tap a
##           slot to change it from the wagon; your cartridge box); and what
##           it all adds up to in battle: hit points, reload, spread, blade...
##   right   SKILLS: level, the cap set by the governing attribute, + while
##           you have points, and what each one does for you right now
##
## Opened from the map (YOU), the camp and the Company screen; BACK returns
## to wherever you came from (tree meta "officer_back").

const UI := preload("res://scripts/ui.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const Officer := preload("res://scripts/officer.gd")
const CAMP := "res://scenes/aftermath.tscn"

const GOLD := Color("d4ad55") # brass (ui.gd)
const RED := Color(0.95, 0.42, 0.35)
const GREEN := Color(0.55, 0.9, 0.55)
const DIM := Color("9aa3b8") # slate (ui.gd)
const BG := UI.NIGHT
const PANEL := UI.WOOL
const CARD := Color("263352")

var _view: SubViewport
var _rig_holder: Node3D
var _rig: Node3D
var _turn := 0.0
var _dragging := false
var _name_edit: LineEdit
var _rank: Label
var _xp_bar: ProgressBar
var _xp_l: Label
var _record: Label
var _attr_pts: Label
var _attr_rows := {} # attr -> [value Label, + Button]
var _cards := {} # slot -> Button
var _ammo_l: Label
var _derived: RichTextLabel
var _skill_pts: Label
var _skill_list: VBoxContainer
var _picker: PanelContainer
var _picker_list: VBoxContainer
var _picker_title: Label
var _picker_slot := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Officer.migrate(Company.officer)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_build_left())
	row.add_child(_build_middle())
	row.add_child(_build_right())
	_build_picker()
	_refresh()
	if "--officer" in OS.get_cmdline_user_args():
		_self_test.call_deferred()


# ---------------------------------------------------------------- building blocks

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	UI.dress(l, size)
	return l


func _panel(col: Color, pad: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(col, pad))
	return p


func _button(text: String, size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _plus(cb: Callable) -> Button:
	var b := _button("+", 26, cb)
	b.custom_minimum_size = Vector2(54, 48)
	return b


# ---------------------------------------------------------------- left: you

func _build_left() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(270, 0)
	col.add_theme_constant_override("separation", 6)
	var frame := _panel(PANEL, 0)
	frame.custom_minimum_size = Vector2(270, 300)
	col.add_child(frame)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(270, 300)
	holder.gui_input.connect(_on_portrait_input)
	frame.add_child(holder)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_view)
	_build_stage()
	_name_edit = LineEdit.new()
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	_name_edit.tooltip_text = Lang.t("Your name: tap to change it")
	_name_edit.text_changed.connect(func(t):
		if t.strip_edges() != "":
			Company.officer["name"] = t.strip_edges())
	col.add_child(_name_edit)
	_rank = _label("", 18, GOLD)
	col.add_child(_rank)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 14)
	_xp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	_xp_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(_xp_bar)
	_xp_l = _label("", 15, DIM)
	col.add_child(_xp_l)
	_record = _label("", 15, Color.WHITE)
	_record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_record)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	col.add_child(_button(Lang.t("BACK"), 20, _on_back))
	return col


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	_view.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.5
	_view.add_child(rim)
	var batcher := BatcherScript.new()
	batcher.add_to_group("batcher")
	_view.add_child(batcher)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.65
	disc.bottom_radius = 0.65
	disc.height = 0.04
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.25, 0.17)
	disc.material = gm
	ground.mesh = disc
	ground.position.y = -0.02
	_view.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30.0
	var at := Vector3(0, 1.15, 5.1)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.98, 0) - at), at)
	_view.add_child(cam)
	_rig_holder = Node3D.new()
	_view.add_child(_rig_holder)


func _show_model() -> void:
	if _rig != null:
		_rig.queue_free()
	_rig = Rig3D.new()
	_rig.kind = "officer"
	_rig.gear = Company.officer["gear"]
	_rig.facing = Basis(Vector3.UP, _turn) * Vector3.BACK
	_rig_holder.add_child(_rig)


func _on_portrait_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_turn += (event as InputEventScreenDrag).relative.x * 0.012
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		_turn += (event as InputEventMouseMotion).relative.x * 0.012
	elif event is InputEventScreenTouch:
		_dragging = (event as InputEventScreenTouch).pressed


func _process(delta: float) -> void:
	if _rig == null:
		return
	if not _dragging:
		_turn += delta * 0.35
	_rig.facing = Basis(Vector3.UP, _turn) * Vector3.BACK
	_rig.anim = "idle"


# ---------------------------------------------------------------- middle: attributes, kit, battle numbers

func _build_middle() -> Control:
	var panel := _panel(PANEL, 12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UI.scroll()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label(Lang.t("ATTRIBUTES"), 22, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_attr_pts = _label("", 17, GOLD)
	head.add_child(_attr_pts)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for k in Officer.ATTRS:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 6)
		var n := _label(Lang.t(Officer.ATTR_NAMES[k]), 18, DIM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.tooltip_text = Lang.t(Officer.ATTR_HELP[k])
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(n)
		var val := _label("", 22, Color.WHITE)
		val.custom_minimum_size = Vector2(30, 0)
		cell.add_child(val)
		var plus := _plus(_on_attr.bind(k))
		cell.add_child(plus)
		grid.add_child(cell)
		_attr_rows[k] = [val, plus]
	var help := _label(Lang.t("Aim: shooting · Strength: blows · Constitution: hit points · Fitness: speed · Wits: skill points, Tactics, Surgery, Logistics · Presence: Leadership, Trade, Training. Each attribute also caps its skills."), 13, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)

	v.add_child(_label(Lang.t("YOUR KIT"), 22, GOLD))
	var kit := GridContainer.new()
	kit.columns = 2
	kit.add_theme_constant_override("h_separation", 8)
	kit.add_theme_constant_override("v_separation", 8)
	v.add_child(kit)
	for slot in Company.OFFICER_SLOTS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(0, 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_open_picker.bind(slot))
		_style_card(b)
		kit.add_child(b)
		_cards[slot] = b
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	v.add_child(ar)
	_ammo_l = _label("", 17, Color.WHITE)
	_ammo_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(_ammo_l)
	for spec in [["-", -1], ["+", 1], [Lang.t("FILL"), 99]]:
		var b := _button(spec[0], 18, _on_ammo.bind(spec[1]))
		b.custom_minimum_size = Vector2(58 if spec[1] != 99 else 74, 48)
		ar.add_child(b)

	v.add_child(_label(Lang.t("IN BATTLE"), 22, GOLD))
	_derived = RichTextLabel.new()
	_derived.bbcode_enabled = true
	_derived.fit_content = true
	_derived.scroll_active = false
	_derived.mouse_filter = Control.MOUSE_FILTER_PASS
	_derived.add_theme_font_size_override("normal_font_size", 16)
	_derived.add_theme_font_size_override("bold_font_size", 16)
	v.add_child(_derived)
	return panel


func _style_card(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := UI.box(CARD.lightened(0.08 if state == "hover" else (0.15 if state == "pressed" else 0.0)), 0, 5, 0.0)
		sb.border_color = Color(UI.BRASS, 0.7 if state != "normal" else 0.3)
		sb.set_border_width_all(1)
		sb.border_width_left = 4
		sb.content_margin_left = 10
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(state, sb)


# ---------------------------------------------------------------- right: skills

func _build_right() -> Control:
	var panel := _panel(PANEL, 12)
	panel.custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label(Lang.t("SKILLS"), 22, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_skill_pts = _label("", 17, GOLD)
	head.add_child(_skill_pts)
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_skill_list = VBoxContainer.new()
	_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_list.add_theme_constant_override("separation", 6)
	sc.add_child(_skill_list)
	return panel


func _fill_skills() -> void:
	for c in _skill_list.get_children():
		c.queue_free()
	for k in Officer.SKILL_ORDER:
		var spec: Dictionary = Officer.SKILLS[k]
		var card := _panel(CARD, 8)
		_skill_list.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		card.add_child(h)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 1)
		h.add_child(tv)
		var lv := Officer.skill(k)
		var cap := Officer.cap(k)
		var pips := ""
		for i in Officer.SKILL_MAX:
			pips += "■" if i < lv else ("□" if i < cap else "·")
		var top := RichTextLabel.new()
		top.bbcode_enabled = true
		top.fit_content = true
		top.scroll_active = false
		top.mouse_filter = Control.MOUSE_FILTER_PASS
		top.add_theme_font_size_override("normal_font_size", 17)
		top.add_theme_font_size_override("bold_font_size", 17)
		top.text = Lang.t("[b]%s[/b]  %d  [color=#%s]%s[/color]  [color=#%s](%s caps it at %d)[/color]") % [
			Lang.t(spec["name"]), lv, GOLD.to_html(false), pips, DIM.to_html(false), Lang.t(Officer.ATTR_NAMES[spec["attr"]]), cap]
		tv.add_child(top)
		var now := _label(Lang.t("Now: ") + Officer.skill_now(k), 14, GREEN if lv > 0 else DIM)
		tv.add_child(now)
		var help := _label(Lang.t(String(spec["help"])), 13, DIM)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(help)
		var plus := _plus(_on_skill.bind(k))
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.visible = Officer.can_raise_skill(k)
		h.add_child(plus)


# ---------------------------------------------------------------- filling in

func _refresh() -> void:
	var o: Dictionary = Company.officer
	if not _name_edit.has_focus():
		_name_edit.text = String(o.get("name", ""))
	var lv := Officer.level()
	_rank.text = Lang.t("%s  ·  %s  ·  Level %d") % [Lang.t(String(o.get("rank", "Ensign"))), Lang.t(String(Officer.BRANCHES.get(Officer.branch(), Officer.BRANCHES["line"])["name"])), lv]
	var into := int(o["xp"]) % Officer.LEVEL_XP
	_xp_bar.max_value = Officer.LEVEL_XP
	_xp_bar.value = into
	_xp_l.text = Lang.t("%d xp  ·  %d to the next level") % [int(o["xp"]), Officer.LEVEL_XP - into]
	_record.text = Lang.t("Battles %d  ·  Kills %d\nCompany: %d men, morale %d") % [int(o["battles"]), int(o["kills"]),
		Company.roster.size(), Company.company_morale()]
	var ap := int(o["attr_points"])
	_attr_pts.text = Lang.t("%d point%s to spend") % [ap, "" if ap == 1 else "s"] if ap > 0 else ""
	for k in Officer.ATTRS:
		var r: Array = _attr_rows[k]
		(r[0] as Label).text = str(Officer.attr(k))
		(r[1] as Button).visible = Officer.can_raise_attr(k)
	var spts := int(o["skill_points"])
	_skill_pts.text = Lang.t("%d point%s to spend") % [spts, "" if spts == 1 else "s"] if spts > 0 else ""
	var gear: Dictionary = o["gear"]
	for slot in Company.OFFICER_SLOTS:
		var id := String(gear.get(slot, ""))
		(_cards[slot] as Button).text = "%s\n%s\n%s" % [Lang.t(String(Company.SLOT_NAMES[slot])).to_upper(),
			Company.item_name(id), _effect(id, slot)]
	var ammo := int(o["pack"].get("ammo", 0))
	_ammo_l.text = Lang.t("Cartridge box: %d / %d   (wagon %d)") % [ammo, int(Company.PACK["ammo"]["max"]), int(Company.stores["ammo"])]
	_ammo_l.add_theme_color_override("font_color", RED if ammo == 0 else Color.WHITE)
	var g := Officer.gear_stats()
	var rel := 3.5 * Officer.reload_mult()
	var t := ""
	t += Lang.t("Hit points [b]%d[/b]   ·   Speed [b]%d%%[/b]   ·   Coat turns [b]%d%%[/b] of a hack\n") % [
		int(Officer.max_hp()), int(Officer.speed_mult() * 100), int(Officer.armour() * 100)]
	t += Lang.t("Reload [b]%.1f s[/b]   ·   Spread [b]×%.2f[/b]   ·   Misfires [b]%d%%[/b]\n") % [
		rel, Officer.spread_mult(), int(round(Officer.misfire() * 50))]
	t += Lang.t("Blade [b]×%.2f[/b] (%s)   ·   Parry [b]±%d°[/b]\n") % [Officer.melee_mult(),
		Company.item_name(String(gear.get("secondary", ""))) if String(gear.get("secondary", "")) != "" else Lang.t("musket butt"),
		int(Officer.block_arc())]
	var fw: Array = []
	for k in Company.FORGE_WORK:
		if Officer.forged(k):
			fw.append({"bore": Lang.t("barrel bored true"), "temper": Lang.t("blades tempered"), "lock": Lang.t("a dwarf lock")}[k])
	if not fw.is_empty():
		t += Lang.t("[color=#d4ad55]Dwarf work: %s.[/color]\n") % ", ".join(fw)
	t += Lang.t("[color=#%s]Your men: steadiness +%d, reaction ×%.2f, xp ×%.2f. Wagon %d kg, %.0f space.[/color]") % [
		DIM.to_html(false), int(Officer.men_steady() * 100), Officer.reaction_mult(), Officer.xp_mult(),
		int(Company.wagon_kg()), Company.wagon_space()]
	_derived.text = t
	_fill_skills()
	_show_model()


static func _effect(id: String, slot: String) -> String:
	if id == "":
		return Lang.t("your musket butt") if slot == "secondary" else "nothing"
	var it: Dictionary = Company.ITEMS[id]
	var bits: PackedStringArray = []
	if it.has("steady"):
		bits.append(Lang.t("+%d steadiness") % int(float(it["steady"]) * 100))
	if it.has("armour"):
		bits.append(Lang.t("turns %d%%") % int(float(it["armour"]) * 100))
	if it.has("pace"):
		bits.append(Lang.t("%+d%% pace") % int(float(it["pace"]) * 100))
	if it.has("spread"):
		bits.append(Lang.t("spread ×%.2f, reload ×%.2f") % [float(it["spread"]), float(it["reload"])])
	if it.has("melee") and not it.has("reach"):
		bits.append(Lang.t("%d damage") % int(it["melee"]))
	return ", ".join(bits) if bits.size() > 0 else Lang.t("no effect")


# ---------------------------------------------------------------- actions

func _on_attr(k: String) -> void:
	if Officer.raise_attr(k):
		Company.save()
		_refresh()


func _on_skill(k: String) -> void:
	if Officer.raise_skill(k):
		Company.save()
		_refresh()


func _on_ammo(n: int) -> void:
	Company.pack_move(Company.officer, "ammo", n)
	Company.save()
	_refresh()


## What you may carry in a slot: an officer's primary is always a firearm.
static func _allowed(slot: String, id: String) -> bool:
	var it: Dictionary = Company.ITEMS[id]
	if slot == "primary":
		return it.has("spread")
	if slot == "secondary":
		return it.has("melee") and not it.has("reach")
	return true


func _build_picker() -> void:
	_picker = _panel(Color(0.09, 0.1, 0.16), 14)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_picker.custom_minimum_size = Vector2(620, 520)
	_picker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_picker.grow_vertical = Control.GROW_DIRECTION_BOTH
	_picker.visible = false
	add_child(_picker)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_picker.add_child(v)
	_picker_title = _label("", 22, GOLD)
	v.add_child(_picker_title)
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_constant_override("separation", 8)
	sc.add_child(_picker_list)
	v.add_child(_button(Lang.t("CANCEL"), 20, func(): _picker.visible = false))


func _open_picker(slot: String) -> void:
	_picker_slot = slot
	_picker_title.text = Lang.t("%s: from the wagon") % Lang.t(String(Company.SLOT_NAMES[slot])).to_upper()
	for c in _picker_list.get_children():
		c.queue_free()
	var current := String(Company.officer["gear"].get(slot, ""))
	_picker_list.add_child(_label(Lang.t("Wearing: %s") % Company.item_name(current), 18, DIM))
	var any := false
	for o in Company.stored_for(slot):
		var id: String = o[0]
		if id == current or not _allowed(slot, id):
			continue
		any = true
		var b := _button("%s   ×%d   ·   %s\n%s" % [Company.item_name(id), int(o[1]), _effect(id, slot), Lang.t(Company.ITEMS[id]["desc"])],
			16, _on_pick.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 76)
		_picker_list.add_child(b)
	if current != "" and slot in ["head", "secondary", "pistol", "sword"]:
		_picker_list.add_child(_button(Lang.t("Take it off (back to the wagon)"), 18, _on_pick.bind("")))
	if not any:
		_picker_list.add_child(_label(Lang.t("Nothing spare for this slot in the wagon."), 18, DIM))
	_picker.visible = true


func _on_pick(id: String) -> void:
	Company.equip(Company.officer, _picker_slot, id)
	_picker.visible = false
	_refresh()


func _on_back() -> void:
	Company.save()
	var back := String(get_tree().get_meta("officer_back", CAMP))
	Loading.change(back)


## `-- --officer`: spend points, change kit, check the numbers move.
func _self_test() -> void:
	print("OFFICER before: lvl %d hp %d spread %.2f wagon %d skills %s" % [Officer.level(), int(Officer.max_hp()),
		Officer.spread_mult(), int(Company.wagon_kg()), Company.officer["skills"]])
	_on_attr("constitution")
	for k in ["logistics", "logistics", "marksmanship", "trade"]:
		_on_skill(k)
	Company.add_item("rifle", 1)
	_open_picker("primary")
	_on_pick("rifle")
	_on_ammo(99)
	Officer.gain_xp(300)
	_refresh()
	print("OFFICER after: lvl %d pts %d/%d hp %d spread %.2f reload x%.2f wagon %d price(10)=%d gear %s ammo %d" % [
		Officer.level(), int(Company.officer["attr_points"]), int(Company.officer["skill_points"]), int(Officer.max_hp()),
		Officer.spread_mult(), Officer.reload_mult(), int(Company.wagon_kg()), Company.price(10),
		Company.officer["gear"], int(Company.officer["pack"]["ammo"])])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
