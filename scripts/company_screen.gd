extends Control
## The Company screen: look at every man and hand out the wagon's stores.
##
##   left    his full-body picture (a live 3D model wearing his kit; drag to
##           turn him), and under it his name and stats
##   middle  his kit on a body diagram: Head, Torso, Primary weapon,
##           Secondary weapon, and his Pack (water, rations, cartridges).
##           Tap a slot to choose from the wagon; +/- move pack stores.
##   right   every man in the company; tap one to look at him. Under the
##           list: the wagon. Tap it for Logistics (share out, buy, grog).
##
## Under his name: his four attributes, with + buttons while he has points
## from levelling up, then morale, health and what he's suffering from.
##
## Opened from camp (later, from the campaign map).

const UI := preload("res://scripts/ui.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const Men := preload("res://scripts/men.gd")
const LogisticsPopup := preload("res://scripts/logistics_popup.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const CAMP := "res://scenes/aftermath.tscn"

const GOLD := Color("d4ad55") # brass (ui.gd)
const RED := Color(0.95, 0.42, 0.35)
const GREEN := Color(0.55, 0.9, 0.55)
const DIM := Color("9aa3b8") # slate (ui.gd)
const BG := UI.NIGHT
const PANEL := UI.WOOL
const CARD := Color("263352")

var _sel: Dictionary = {} # the man on show
var _picker_slot := "" # a slot's choices are open

# Left
var _view: SubViewport
var _rig_holder: Node3D
var _rig: Node3D
var _turn := 0.0
var _dragging := false
var _name: Label
var _sub: Label
var _stats: RichTextLabel
var _points: Label
var _attr_rows := {} # attr -> [value Label, + Button]
var _logistics
# Middle
var _doll: Control
var _cards := {} # slot -> Button
var _pack_rows := {} # key -> Label
var _picker: PanelContainer
var _picker_list: VBoxContainer
var _picker_title: Label
# Right
var _list: VBoxContainer
var _wagon: RichTextLabel
var _group := ButtonGroup.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	row.add_child(_build_left())
	row.add_child(_build_middle())
	row.add_child(_build_right())
	_logistics = LogisticsPopup.new()
	add_child(_logistics)
	_logistics.changed.connect(func():
		if not _sel.is_empty():
			_select(_sel)
		_fill_list()
		_refresh_wagon())

	if Company.roster.size() > 0:
		_select(_sorted_men()[0])
	_fill_list()
	_refresh_wagon()

	if "--company" in OS.get_cmdline_user_args():
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
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(cb)
	return b


func _sorted_men() -> Array:
	var men: Array = Company.roster.duplicate()
	men.sort_custom(func(a, b): return int(a["xp"]) > int(b["xp"]))
	return men


# ---------------------------------------------------------------- left: picture and stats

func _build_left() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 6)

	var frame := _panel(PANEL, 0)
	frame.custom_minimum_size = Vector2(300, 290)
	col.add_child(frame)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(300, 290)
	holder.gui_input.connect(_on_portrait_input)
	frame.add_child(holder)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_view)
	_build_stage()

	_name = _label("", 24, Color.WHITE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_name)
	_sub = _label("", 17, GOLD)
	col.add_child(_sub)
	_points = _label("", 16, GOLD)
	col.add_child(_points)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	for k in Men.ATTRS:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(145, 0)
		var n := _label(Lang.t({"aim": "Aim", "strength": "Strength", "constitution": "Constit.", "fitness": "Fitness"}[k]), 16, DIM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.tooltip_text = Lang.t(Men.ATTR_HELP[k])
		cell.add_child(n)
		var v := _label("", 17, Color.WHITE)
		cell.add_child(v)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(52, 46)
		plus.add_theme_font_size_override("font_size", 24)
		plus.pressed.connect(_on_spend.bind(k))
		cell.add_child(plus)
		grid.add_child(cell)
		_attr_rows[k] = [v, plus]
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats.add_theme_font_size_override("normal_font_size", 15)
	_stats.add_theme_font_size_override("bold_font_size", 15)
	col.add_child(_stats)
	return col


## A little stage in its own 3D world: light, a patch of ground, a camera,
## and a batcher to draw the model (Rig3D draws through one).
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


func _show_model(m: Dictionary) -> void:
	if _rig != null:
		_rig.queue_free()
	_rig = Rig3D.new()
	_rig.kind = "soldier"
	_rig.gear = m["gear"]
	_rig.pack = m["pack"]
	_rig.facing = Basis(Vector3.UP, _turn) * Vector3.BACK
	_rig_holder.add_child(_rig)


func _on_portrait_input(event: InputEvent) -> void:
	# Drag across the picture to turn him round.
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
		_turn += delta * 0.35 # a slow turntable
	_rig.facing = Basis(Vector3.UP, _turn) * Vector3.BACK
	_rig.anim = "idle"


func _fill_stats(m: Dictionary) -> void:
	var rank := int(m["rank"])
	_name.text = String(m["name"])
	var wd := int(m["wounded_days"])
	_sub.text = Lang.t("%s  ·  Level %d  ·  %s") % [Lang.t(Company.RANKS[rank]), Men.level(m), Lang.t("WOUNDED, %d days") % wd if wd > 0 else Lang.t("Fit for duty")]
	_sub.add_theme_color_override("font_color", RED if wd > 0 else GOLD)
	var pts := int(m["points"])
	var to_next := Men.LEVEL_XP - int(m["xp"]) % Men.LEVEL_XP
	_points.text = (Lang.t("%d POINTS TO SPEND  ·  ") % pts if pts > 0 else "") + Lang.t("%d xp to next level") % to_next
	var pen := Men.penalty(m)
	for k in Men.ATTRS:
		var row: Array = _attr_rows[k]
		var base := int(m["attrs"][k])
		var eff := Men.attr(m, k)
		(row[0] as Label).text = str(eff) if eff == base else "%d/%d" % [eff, base]
		(row[0] as Label).add_theme_color_override("font_color", RED if eff < base else Color.WHITE)
		(row[1] as Button).visible = pts > 0 and base < Men.ATTR_MAX
	var st := Men.combat_stats(m)
	var morale := int(m["morale"])
	var mcol := GREEN if morale >= 60 else (Color(1, 0.8, 0.4) if morale >= 35 else RED)
	var t := ""
	t += Lang.t("Morale [color=#%s][b]%d %s[/b][/color]   Health [b]%d[/b]   HP [b]%d[/b]\n") % [
		mcol.to_html(false), morale, Men.morale_word(morale), int(m["health"]), int(st["hp"])]
	t += Lang.t("Battles [b]%d[/b]  Kills [b]%d[/b]  Steadiness [b]%d[/b]\n") % [int(m["battles"]), int(m["kills"]),
		int(clampf(float(m["steadiness"]) + 0.1 * rank + float(st["steady"]), 0.0, 1.0) * 100)]
	t += Lang.t("Spread [b]×%.2f[/b]  Bayonet [b]%d[/b]  Pace [b]%d%%[/b]\n") % [float(st["spread"]),
		int(float(st["melee"]) + 5.0 * rank), int(float(m["pace"]) * (1.0 + float(st["pace"])) * 100)]
	var cond := Men.conditions(m)
	if pen > 0:
		cond.append(Lang.t("-%d to all attributes") % pen)
	if cond.size() > 0:
		t += "[color=#%s]%s[/color]" % [RED.to_html(false), ", ".join(cond)]
	_stats.text = t


func _on_spend(k: String) -> void:
	if Men.spend(_sel, k):
		Company.save()
		_fill_stats(_sel)
		_fill_list()


static func _signed(v: float, what: String) -> String:
	if absf(v) < 0.001:
		return ""
	return "(%s%d %s)" % ["+" if v > 0 else "", int(round(v * 100)), what]


static func _reaction(r: float) -> String:
	if r < 0.4:
		return "quick"
	if r < 0.75:
		return "steady"
	return "slow"


# ---------------------------------------------------------------- middle: kit on a body

func _build_middle() -> Control:
	var panel := _panel(PANEL, 12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := Control.new()
	stack.clip_contents = true
	panel.add_child(stack)

	_doll = Control.new()
	_doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_doll.draw.connect(_draw_doll)
	_doll.resized.connect(_layout_doll)
	stack.add_child(_doll)
	_doll.add_child(_label(Lang.t("KIT"), 22, GOLD))

	for slot in Company.SLOTS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size = Vector2(212, 78)
		b.size = Vector2(212, 78)
		b.pressed.connect(_open_picker.bind(slot))
		_style_card(b)
		_doll.add_child(b)
		_cards[slot] = b

	var pack := _panel(CARD, 10)
	pack.name = "Pack"
	_doll.add_child(pack)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	pack.add_child(pv)
	pv.add_child(_label(Lang.t("PACK"), 15, DIM))
	for key in Company.PACK:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		pv.add_child(r)
		var l := _label("", 18, Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		_pack_rows[key] = l
		for spec in [["-", -1], ["+", 1], [Lang.t("FILL"), 99]]:
			var b := _button(spec[0], 18, _on_pack.bind(key, spec[1]))
			b.custom_minimum_size = Vector2(56 if spec[1] != 99 else 70, 42)
			r.add_child(b)

	# Choices from the wagon, over the diagram.
	_picker = _panel(Color(0.09, 0.1, 0.16), 14)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.visible = false
	stack.add_child(_picker)
	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	_picker.add_child(pvb)
	_picker_title = _label("", 22, GOLD)
	pvb.add_child(_picker_title)
	var scroll := UI.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pvb.add_child(scroll)
	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_picker_list)
	pvb.add_child(_button(Lang.t("CANCEL"), 20, _close_picker))
	return panel


func _style_card(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := UI.box(CARD.lightened(0.08 if state == "hover" else (0.15 if state == "pressed" else 0.0)), 0, 5, 0.0)
		sb.border_color = Color(UI.BRASS, 0.7 if state != "normal" else 0.3)
		sb.set_border_width_all(1)
		sb.border_width_left = 4 # a brass edge, like a facing
		sb.content_margin_left = 12
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)


## Where the body is drawn and where each slot card sits, from the panel size.
func _geom() -> Dictionary:
	var w := _doll.size.x
	var cx := w * 0.5
	return {
		"cx": cx, "head": Vector2(cx, 92), "torso": Rect2(cx - 46, 132, 92, 128),
		"r_hand": Vector2(cx + 70, 230), "l_hand": Vector2(cx - 70, 230), "hip": Vector2(cx, 268),
	}


func _layout_doll() -> void:
	var w := _doll.size.x
	var g := _geom()
	var cw := minf(212.0, (w - 140.0) * 0.5)
	var places := {
		"head": Vector2(0, 40), "torso": Vector2(0, 170),
		"primary": Vector2(w - cw, 90), "secondary": Vector2(w - cw, 210),
	}
	for slot in _cards:
		var b: Button = _cards[slot]
		b.position = places[slot]
		b.size = Vector2(cw, 78)
	var pack: Control = _doll.get_node("Pack")
	pack.position = Vector2(0, 404)
	pack.size = Vector2(w, 0)
	pack.custom_minimum_size = Vector2(w, 0)
	_doll.queue_redraw()
	g.clear()


## A plain figure in the middle with leader lines from each card to the part
## it dresses.
func _draw_doll() -> void:
	var g := _geom()
	var body := Color(0.32, 0.36, 0.48)
	var line := Color(0.95, 0.8, 0.45, 0.45)
	var cx: float = g["cx"]
	var torso: Rect2 = g["torso"]
	# Legs, arms, torso, head.
	_doll.draw_line(Vector2(cx - 22, 258), Vector2(cx - 30, 392), body, 22)
	_doll.draw_line(Vector2(cx + 22, 258), Vector2(cx + 30, 392), body, 22)
	_doll.draw_line(Vector2(cx - 50, 142), g["l_hand"], body, 18)
	_doll.draw_line(Vector2(cx + 50, 142), g["r_hand"], body, 18)
	_doll.draw_rect(torso, body)
	_doll.draw_circle(g["head"], 30, body)
	# The musket across the body, held at the right hand.
	_doll.draw_line(Vector2(cx + 94, 130), Vector2(cx + 50, 300), Color(0.45, 0.3, 0.16), 6)
	# Leader lines.
	for slot in _cards:
		var b: Button = _cards[slot]
		var from := b.position + Vector2(b.size.x if b.position.x < cx else 0.0, b.size.y * 0.5)
		var to: Vector2
		match slot:
			"head": to = g["head"] + Vector2(-30, 0)
			"torso": to = Vector2(torso.position.x, torso.get_center().y)
			"primary": to = g["r_hand"] + Vector2(14, -40)
			"secondary": to = Vector2(cx + 92, 134)
		_doll.draw_line(from, to, line, 2)
		_doll.draw_circle(to, 4, line)
	var pack: Control = _doll.get_node("Pack")
	_doll.draw_line(Vector2(cx, 268), Vector2(cx, pack.position.y), line, 2)


func _fill_kit(m: Dictionary) -> void:
	var gear: Dictionary = m["gear"]
	for slot in Company.SLOTS:
		var id := String(gear.get(slot, ""))
		var b: Button = _cards[slot]
		b.text = "%s\n%s\n%s" % [Lang.t(String(Company.SLOT_NAMES[slot])).to_upper(), Company.item_name(id), _effect(id, slot)]
	var pack: Dictionary = m["pack"]
	for key in Company.PACK:
		var spec: Dictionary = Company.PACK[key]
		var n := int(pack[key])
		var l: Label = _pack_rows[key]
		var nm := Lang.t(String(spec["name"]))
		var unit := String(spec["unit"])
		var warn_empty := n == 0
		if key == "ammo":
			# What's in his pouch depends on his weapon.
			var sk := Company.shot_key(m)
			nm = Lang.t({"ammo": "Cartridges", "arrows": "Arrows", "bolts": "Bolts", "": "Shot"}[sk])
			unit = {"ammo": "cartridge", "arrows": "arrow", "bolts": "bolt", "": "shot"}[sk]
			if sk == "":
				warn_empty = false
				nm = Lang.t("Shot (pike: none needed)")
		l.text = "%s   %d / %d %s" % [nm, n, int(spec["max"]), Lang.t(unit + ("" if n == 1 else "s"))]
		l.add_theme_color_override("font_color", RED if warn_empty else Color.WHITE)
	_doll.queue_redraw()


## One short line on what an item does.
static func _effect(id: String, slot: String) -> String:
	if id == "":
		return Lang.t("clubs with the musket butt") if slot == "secondary" else Lang.t("bare-headed")
	var it: Dictionary = Company.ITEMS[id]
	var bits: PackedStringArray = []
	if it.has("steady"):
		bits.append(Lang.t("+%d steadiness") % int(float(it["steady"]) * 100))
	if it.has("armour"):
		bits.append(Lang.t("turns %d%% of a hack") % int(float(it["armour"]) * 100))
	if it.has("pace"):
		bits.append(Lang.t("%+d%% pace") % int(float(it["pace"]) * 100))
	if it.has("missile"):
		bits.append({"arrow": Lang.t("shoots arrows, %d m") % int(it.get("range", 40)), "bolt": Lang.t("shoots bolts, %d m") % int(it.get("range", 40))}.get(String(it["missile"]), ""))
		if it.has("dmg"):
			bits.append(Lang.t("+%d%% damage") % int((float(it["dmg"]) - 1.0) * 100))
		bits.append(Lang.t("quick to loose") if float(it["reload"]) < 0.8 else Lang.t("slow to span"))
	elif it.has("spread"):
		if float(it["spread"]) < 1.0:
			bits.append(Lang.t("accurate, slow to load"))
		elif float(it["spread"]) > 1.0:
			bits.append(Lang.t("misfires, scatters"))
		else:
			bits.append(Lang.t("reliable"))
	if it.has("melee"):
		bits.append(Lang.t("%d damage") % int(it["melee"]))
	return ", ".join(bits) if bits.size() > 0 else Lang.t("no effect")


func _open_picker(slot: String) -> void:
	if _sel.is_empty():
		return
	_picker_slot = slot
	_picker_title.text = Lang.t("%s: from the wagon") % Lang.t(String(Company.SLOT_NAMES[slot])).to_upper()
	for c in _picker_list.get_children():
		c.queue_free()
	var current := String(_sel["gear"].get(slot, ""))
	_picker_list.add_child(_label(Lang.t("Wearing: %s") % Company.item_name(current), 18, DIM))
	var options := Company.stored_for(slot)
	for o in options:
		var id: String = o[0]
		if id == current:
			continue
		var b := _button("%s   ×%d\n%s" % [Company.item_name(id), int(o[1]), Lang.t(Company.ITEMS[id]["desc"])], 18,
			_on_pick.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 76)
		_picker_list.add_child(b)
	if current != "" and slot != "primary" and slot != "torso":
		_picker_list.add_child(_button(Lang.t("Take it off (back to the wagon)"), 18, _on_pick.bind("")))
	if options.is_empty() or (options.size() == 1 and options[0][0] == current):
		_picker_list.add_child(_label(Lang.t("Nothing spare for this slot in the wagon."), 18, DIM))
	_picker.visible = true


func _close_picker() -> void:
	_picker.visible = false
	_picker_slot = ""


func _on_pick(id: String) -> void:
	if Company.equip(_sel, _picker_slot, id):
		_close_picker()
		_select(_sel)
		_fill_list()
		_refresh_wagon()
	else:
		_close_picker()


func _on_pack(key: String, amount: int) -> void:
	if _sel.is_empty():
		return
	Company.pack_move(_sel, key, amount)
	Company.save()
	_fill_kit(_sel)
	_show_model(_sel) # the canteen, haversack and cartridge box show what he carries
	_fill_list()
	_refresh_wagon()


# ---------------------------------------------------------------- right: the men, the wagon

func _build_right() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(310, 0)
	col.add_theme_constant_override("separation", 8)
	var men := _panel(PANEL, 10)
	men.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(men)
	var mv := VBoxContainer.new()
	men.add_child(mv)
	mv.add_child(_label(Lang.t("THE MEN  ·  %d") % Company.roster.size(), 20, GOLD))
	var scroll := UI.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var wagon := _panel(PANEL, 10)
	col.add_child(wagon)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 6)
	wagon.add_child(wv)
	_wagon = RichTextLabel.new()
	_wagon.bbcode_enabled = true
	_wagon.fit_content = true
	_wagon.scroll_active = false
	_wagon.add_theme_font_size_override("normal_font_size", 16)
	_wagon.add_theme_font_size_override("bold_font_size", 16)
	wv.add_child(_wagon)
	# Tap the wagon for Logistics.
	wagon.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_logistics.open())
	_wagon.mouse_filter = Control.MOUSE_FILTER_PASS
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	wv.add_child(acts)
	var issue := _button(Lang.t("LOGISTICS"), 17, func(): _logistics.open())
	issue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(issue)
	var you := _button(Lang.t("YOU"), 17, func():
		Company.save()
		get_tree().set_meta("officer_back", "res://scenes/company.tscn")
		Loading.change("res://scenes/officer.tscn"))
	you.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(you)
	var back := _button(Lang.t("BACK"), 17, _on_back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(back)
	return col


var _runner_for := -1 # the work party whose runner you're choosing
var _worker_open := -1 # the labourer whose details are showing


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for m in _sorted_men():
		var wd := int(m["wounded_days"])
		var pack: Dictionary = m["pack"]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.button_pressed = m == _sel
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		var status := Lang.t("wounded %dd") % wd if wd > 0 else (Lang.t("sick") if int(m["sick"]) > 0 else Lang.t("fit"))
		var warn := ""
		var shot := Company.shot_key(m)
		if int(pack["ammo"]) == 0 and shot != "":
			warn = Lang.t(" · NO %s") % Company.shot_word(m).to_upper()
		elif int(pack["rations"]) == 0:
			warn = Lang.t(" · NO FOOD")
		var pts := "  [+%d]" % int(m["points"]) if int(m["points"]) > 0 else ""
		var role: String = {"musket": "", "pike": Lang.t(" · pike"), "bow": Lang.t(" · bow"), "crossbow": Lang.t(" · crossbow"), "dragoon": Lang.t(" · dragoon"), "lancer": Lang.t(" · lancer")}[Company.role_of(m)]
		var shot_txt := ("%d %s · " % [int(pack["ammo"]), Company.shot_word(m)]) if shot != "" else ""
		b.text = Lang.t("%s%s%s\n%s · morale %d · %s%d food%s") % [Company.title(m), pts, role, status, int(m["morale"]),
			shot_txt, int(pack["rations"]), warn]
		if wd > 0 or warn != "":
			b.add_theme_color_override("font_color", RED if warn != "" else Color(1, 0.75, 0.45))
		b.custom_minimum_size = Vector2(0, 58)
		b.pressed.connect(_select.bind(m))
		_list.add_child(b)
	# Who works but doesn't fight, and who's away working.
	if not Company.workers.is_empty():
		_list.add_child(_label(Lang.t("LABOURERS  ·  %d") % Company.workers.size(), 18, GOLD))
		for w in Company.workers:
			Company.ensure_worker(w)
			var wid := int(w["id"])
			var state := Lang.t("  ·  away scouting") if w.get("away", false) else (Lang.t("  ·  sick") if int(w["sick"]) > 0 else (Lang.t("  ·  hungry") if int(w["hunger"]) > 0 else ""))
			var wb := _button("%s  ·  %s%s\n%s %d" % [w["name"], Company.trade_name(String(w["trade"])).to_lower(), state,
				Lang.t("morale"), int(w["morale"])], 15, func():
				_worker_open = -1 if _worker_open == wid else wid
				_fill_list())
			wb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			wb.custom_minimum_size = Vector2(0, 54)
			if int(w["morale"]) < 25 or int(w["hunger"]) > 0:
				wb.add_theme_color_override("font_color", RED)
			_list.add_child(wb)
			if _worker_open == wid:
				var bits: Array = []
				for k in Men.ATTRS:
					bits.append("%s %d" % [Lang.t(Men.ATTR_NAMES[k]), Men.attr(w, k)])
				var info := _label("  ·  ".join(bits) + "\n" + Lang.t("Best at: %s. Scouting ★%d. Doesn't fight; eats a ration and drinks a day's water; paid %d crown a week.") % [
					", ".join(Company.TRADES.get(String(w["trade"]), []).map(func(k2): return Lang.t(String(World.RESOURCES[k2]["name"])).to_lower())) if not Company.TRADES.get(String(w["trade"]), []).is_empty() else Lang.t("any work"),
					int(round(Company.aptitude(w, "scout"))), Company.LABOURER_WAGE], 14, DIM)
				info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_list.add_child(info)
				var db := _button(Lang.t("LET %s GO HOME") % String(w["name"]).split(" ")[0].to_upper(), 15, func():
					Company.dismiss_worker(w)
					_worker_open = -1
					_fill_list())
				db.disabled = w.get("away", false)
				_list.add_child(db)
	if not Company.posts.is_empty():
		_list.add_child(_label(Lang.t("WORK PARTIES"), 18, GOLD))
		for key in Company.posts:
			var post: Dictionary = Company.posts[key]
			var spec: Dictionary = World.RESOURCES.get(String(post.get("kind", "")), {})
			var names: Array = []
			for m in post["men"]:
				names.append(Company.title(m))
			for w in post["workers"]:
				names.append(String(w["name"]))
			var l2 := _label(Lang.t("At the %s: %s") % [Lang.t(String(spec.get("name", "site"))).to_lower(), ", ".join(names)], 15, DIM)
			l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list.add_child(l2)
			# Calling them back costs a man: a runner goes to fetch them.
			var sid := int(key)
			var rb := _button(Lang.t("SEND A RUNNER TO CALL THEM BACK"), 15, func():
				_runner_for = -1 if _runner_for == sid else sid
				_fill_list())
			rb.disabled = Company.fit_men().is_empty()
			_list.add_child(rb)
			if _runner_for == sid:
				# Who runs: the fastest first (fitness, then stamina).
				_list.add_child(_label(Lang.t("Who goes? The quickest first. He's gone until they're back."), 14, DIM))
				for m in Company.ranked(Company.fit_men(), "runner").slice(0, 6):
					var mid := int(m["id"])
					var mb := _button(Lang.t("%s  ★%d") % [Company.title(m), int(round(Company.aptitude(m, "runner")))], 15, func():
						var why := Company.send_runner(sid, mid)
						_runner_for = -1
						if why == "":
							World.save()
						_fill_list())
					_list.add_child(mb)
	var coming: Array = World.parties.filter(func(p): return p["kind"] == "detachment") if World.is_ready else []
	for p in coming:
		var l3 := _label(Lang.t("A work party is on its way back to you: %d of them.") % int(p["size"]), 15, GOLD)
		l3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l3)


func _refresh_wagon() -> void:
	var s: Dictionary = Company.stores
	var spare := 0
	var names: PackedStringArray = []
	for id in s["items"]:
		spare += int(s["items"][id])
		names.append("%s ×%d" % [Company.item_name(id), int(s["items"][id])])
	var load := Company.wagon_load()
	var t := Lang.t("[color=#%s][b]THE WAGON[/b][/color]  %d cr · %d/%d kg · tap for logistics\n") % [
		GOLD.to_html(false), Company.money, int(load[0]), int(Company.wagon_kg())]
	t += Lang.t("Water [b]%d[/b]%s · Food [b]%d[/b] · Shot [b]%d[/b] · Rum [b]%d[/b]\n") % [
		int(s["water"]), Lang.t(" (foul)") if bool(s["foul"]) else "", int(s["rations"]), int(s["ammo"]), int(s["rum"])]
	t += "[color=#%s]%s[/color]" % [DIM.to_html(false), ", ".join(names) if spare > 0 else Lang.t("No spare kit.")]
	_wagon.text = t


func _select(m: Dictionary) -> void:
	_sel = m
	_close_picker()
	_fill_stats(m)
	_fill_kit(m)
	_show_model(m)


func _on_issue() -> void:
	Company.resupply_all()
	if not _sel.is_empty():
		_select(_sel)
	_fill_list()
	_refresh_wagon()


func _on_back() -> void:
	Company.save()
	Loading.change(CAMP)


# ---------------------------------------------------------------- headless check

## `-- --company`: give a man some kit and stores, check the books balance.
func _self_test() -> void:
	var m: Dictionary = _sel
	var before := int(Company.stores["ammo"]) + int(m["pack"]["ammo"])
	_on_pack("ammo", 99)
	_on_pack("ammo", -1)
	var after := int(Company.stores["ammo"]) + int(m["pack"]["ammo"])
	for slot in Company.SLOTS:
		_open_picker(slot)
		var opts := Company.stored_for(slot)
		if opts.size() > 0:
			_on_pick(opts[0][0])
		_close_picker()
	_on_issue()
	m["points"] = 3
	_on_spend("aim")
	_on_spend("constitution")
	_logistics.open()
	_logistics._on_share("rations")
	_logistics._on_buy("rum")
	_logistics._on_grog()
	print("  attrs %s points %d morale %d | wagon %s" % [m["attrs"], int(m["points"]), int(m["morale"]), Company.stores])
	for i in 6:
		print("  march: ", Company.march_on())
		print("    morale %d, men %d" % [Company.company_morale(), Company.roster.size()])
	print("COMPANY SCREEN: %s gear %s pack %s | ammo conserved %s | stores %s" % [
		Company.title(m), m["gear"], m["pack"], before == after, Company.stores])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
