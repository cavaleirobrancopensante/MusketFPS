extends Control
## Logistics: tap the wagon to see what the company has left and share it
## out. A full-screen overlay used by the camp and the Company screen (and
## later the campaign map).
##
## For water, rations, cartridges and rum: what's in the wagon, what the men
## carry, what a day costs, and how many days that lasts, with one tap to
## share it evenly and one to buy more from the sutler. Also: whether the
## water is foul and served as grog, how even the rations are, and the
## company's morale and health.
##
## Emits `changed` after anything that moves stores, so the screen beneath
## can refresh.

signal changed

const Men := preload("res://scripts/men.gd")
const UI := preload("res://scripts/ui.gd")
const GOLD := Color("d4ad55") # brass (ui.gd)
const RED := Color(0.95, 0.42, 0.35)
const GREEN := Color(0.55, 0.9, 0.55)
const DIM := Color("9aa3b8") # slate (ui.gd)
const WagonView := preload("res://scripts/wagon_view.gd")

## A line on each store, for the wagon view's details.
const STORE_TEXT := {
	"water": "Drinking water in the barrels: a day's water a man. Fill them at wells, rivers, lakes and springs (the button shows on the map when you're close); they also top up at midnight from the best water you passed that day, and from the rain if you collect it.",
	"rations": "Biscuit, salt meat, smoked meat and bread: a ration a man a day.",
	"meat": "Fresh meat and fish: it goes off on the march, but the men smoke it into rations whenever you make camp.",
	"grain": "Grain: bake it into bread (CRAFT).",
	"ammo": "Paper cartridges, powder and ball: what the muskets fire.",
	"powder": "Gunpowder, by the pound: roll it into cartridges with lead.",
	"lead": "Lead, by the pound: cast into balls for cartridges.",
	"rum": "Rum, by the tot: grog makes foul water safe, and a tot on feast days cheers the men.",
	"arrows": "Arrows for the bowmen.",
	"bolts": "Bolts for the crossbowmen.",
	"saltpetre": "Saltpetre: three parts in four of gunpowder (CRAFT).",
	"sulphur": "Sulphur: a tenth of gunpowder (CRAFT).",
	"charcoal": "Charcoal: for powder, for smelting, for smoking meat.",
	"ore": "Ore: smelt it into lead, or a smith forges it into blades and barrels.",
	"wood": "Timber: tools, pikes, wooden shot.",
}

var _wagon
var _detail: RichTextLabel
var _detail_btns: HBoxContainer
var _pick := ""

var _grid: GridContainer
var _info: RichTextLabel
var _grog: Button
var _title: Label
var _cargo: VBoxContainer
var _cargo_list: VBoxContainer
var _cargo_head: RichTextLabel
var _cargo_btn: Button
var _make: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.WOOL, 18, 6, 0.3))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(980, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_title = _label("", 26, GOLD)
	v.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_grid)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.add_theme_font_size_override("normal_font_size", 18)
	_info.add_theme_font_size_override("bold_font_size", 18)
	v.add_child(_info)
	# The cargo: everything in the wagon by weight and space.
	_cargo = VBoxContainer.new()
	_cargo.visible = false
	_cargo.add_theme_constant_override("separation", 6)
	v.add_child(_cargo)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	_cargo.add_child(wrow)
	_wagon = WagonView.new()
	_wagon.custom_minimum_size = Vector2(620, 400)
	_wagon.picked.connect(_on_pick)
	wrow.add_child(_wagon)
	var dv := VBoxContainer.new()
	dv.custom_minimum_size = Vector2(320, 0)
	dv.add_theme_constant_override("separation", 8)
	wrow.add_child(dv)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.custom_minimum_size = Vector2(320, 0)
	_detail.add_theme_font_size_override("normal_font_size", 17)
	_detail.add_theme_font_size_override("bold_font_size", 19)
	dv.add_child(_detail)
	_detail_btns = HBoxContainer.new()
	_detail_btns.add_theme_constant_override("separation", 8)
	dv.add_child(_detail_btns)
	var dv2 := VBoxContainer.new()
	dv2.add_theme_constant_override("separation", 8)
	dv.add_child(dv2)
	_detail_btns.set_meta("more", dv2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_cargo_btn = _button(Lang.t("SUPPLIES"), _toggle_cargo)
	row.add_child(_cargo_btn)
	_grog = _button("", _on_grog)
	row.add_child(_grog)
	_make = _button("", _on_make)
	row.add_child(_make)
	var all := _button(Lang.t("SHARE EVERYTHING EVENLY"), _on_share_all)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(all)
	row.add_child(_button(Lang.t("CLOSE"), func(): visible = false))
	visible = false


func open() -> void:
	# The wagon itself first: what's in it, and where.
	_cargo.visible = true
	_grid.visible = false
	_info.visible = false
	_cargo_btn.text = Lang.t("SUPPLIES")
	refresh()
	visible = true


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
	b.custom_minimum_size = Vector2(150, 50)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func refresh() -> void:
	var s: Dictionary = Company.stores
	var men := Company.roster.size()
	_title.text = Lang.t("LOGISTICS  ·  THE WAGON  ·  %d crowns  ·  %d men") % [Company.money, men]
	for c in _grid.get_children():
		c.queue_free()
	for h in ["", Lang.t("WAGON"), Lang.t("PACKS"), Lang.t("PER DAY"), Lang.t("DAYS LEFT"), "", ""]:
		_grid.add_child(_label(h, 15, DIM))
	for key in ["water", "rations", "ammo", "arrows", "bolts", "rum", "powder", "lead"]:
		var name: String = {"water": "Water", "rations": "Rations", "ammo": "Cartridges", "arrows": "Arrows",
			"bolts": "Bolts", "rum": Lang.t("Rum (tots)"), "powder": Lang.t("Powder (lb)"), "lead": Lang.t("Lead (lb)")}[key]
		name = Lang.t(name)
		var shot: bool = key in ["ammo", "arrows", "bolts"]
		if key in ["arrows", "bolts"] and int(s.get(key, 0)) == 0 and not Company.roster.any(func(mm): return Company.shot_key(mm) == key):
			continue # nobody shoots these and the wagon has none: keep the table short
		var in_packs := 0
		var shooters := 0
		if Company.PACK.has(key) or shot:
			for m in Company.roster:
				if shot:
					if Company.shot_key(m) == key:
						in_packs += int(m["pack"]["ammo"])
						shooters += 1
				else:
					in_packs += int(m["pack"][key])
		var per_day := men if key in ["water", "rations"] else (men if key == "rum" and bool(s["foul"]) and bool(s["grog"]) else 0)
		var total := int(s.get(key, 0)) + in_packs
		var days := "-"
		var col := Color.WHITE
		if per_day > 0:
			var d := float(total) / per_day
			days = "%.1f" % d
			col = RED if d < 2.0 else (Color(1, 0.8, 0.4) if d < 4.0 else GREEN)
		elif shot:
			days = Lang.t("%d a man") % (total / maxi(1, shooters))
		_grid.add_child(_label(name, 20, Color.WHITE))
		_grid.add_child(_label(str(int(s.get(key, 0))), 20, Color.WHITE))
		_grid.add_child(_label(str(in_packs) if Company.PACK.has(key) or shot else "-", 20, Color.WHITE))
		_grid.add_child(_label(str(per_day) if per_day > 0 else "-", 20, DIM))
		_grid.add_child(_label(days, 20, col))
		if Company.PACK.has(key) or shot:
			var b := _button(Lang.t("SHARE EVENLY"), _on_share.bind("ammo" if shot else key))
			b.add_theme_font_size_override("font_size", 15)
			_grid.add_child(b)
		else:
			_grid.add_child(Control.new())
		# You can only buy where someone sells: at a settlement on the map.
		var offer := _offer(key)
		if key == "water":
			var fs: Array = World.fill_state()
			var fb := _button(String(fs[0]), _on_fill)
			fb.add_theme_font_size_override("font_size", 14)
			fb.disabled = not bool(fs[1])
			_grid.add_child(fb)
		elif not offer.is_empty():
			var buy := _button(Lang.t("BUY %d (%d cr)") % [int(offer[0]), int(offer[1])], _on_buy.bind(key))
			buy.add_theme_font_size_override("font_size", 15)
			buy.disabled = Company.money < int(offer[1])
			_grid.add_child(buy)
		else:
			var why: String = {"water": Lang.t("rivers, lakes, towns"), "ammo": Lang.t("make them: powder + lead"),
				"powder": Lang.t("only the dwarves sell it")}.get(key, "")
			_grid.add_child(_label(why, 15, DIM))

	var t := ""
	var market := World.market_here()
	if market.is_empty():
		t += Lang.t("[color=#%s]Nobody to buy from out here: visit a village, town, city or hold.[/color]\n") % DIM.to_html(false)
	else:
		t += Lang.t("At %s: food%s for sale; more in the town's market.\n") % [market["name"], Lang.t(" and rum") if market["kind"] != "village" else ""]
	if bool(s["foul"]):
		t += Lang.t("[color=#%s][b]The water is foul.[/b][/color] Drunk plain, it makes men sick. ") % RED.to_html(false)
		if bool(s["grog"]) and int(s["rum"]) > 0:
			t += Lang.t("Served as grog: a tot of rum a man a day.\n")
		elif bool(s["grog"]):
			t += Lang.t("[color=#%s]No rum left for grog![/color]\n") % RED.to_html(false)
		else:
			t += Lang.t("Grog is off: they'll drink it plain.\n")
	else:
		t += Lang.t("The water is clean.\n")
	var spread := Company.ration_spread()
	if int(spread[1]) - int(spread[0]) >= 3:
		t += Lang.t("[color=#%s]Rations are uneven: %d to %d days a man. The men with less resent it, and a man who starves while others eat may not forgive it.[/color]\n") % [
			Color(1, 0.75, 0.4).to_html(false), int(spread[0]), int(spread[1])]
	else:
		t += Lang.t("Rations are fair: %d to %d days a man.\n") % [int(spread[0]), int(spread[1])]
	var sick := 0
	var hungry := 0
	var thirsty := 0
	for m in Company.roster:
		sick += 1 if int(m["sick"]) > 0 else 0
		hungry += 1 if int(m["hunger"]) > 0 else 0
		thirsty += 1 if int(m["thirst"]) > 0 else 0
	var cm := Company.company_morale()
	t += Lang.t("Morale [b]%d[/b] (%s)   ·   sick %d   ·   hungry %d   ·   thirsty %d") % [
		cm, Men.morale_word(cm), sick, hungry, thirsty]
	if cm < Company.MUTINY_MORALE:
		t += Lang.t("\n[color=#%s][b]The men are close to mutiny.[/b][/color]") % RED.to_html(false)
	var load := Company.wagon_load()
	t += Lang.t("\nLoad: [b]%d / %d kg[/b]   ·   space [b]%.0f / %.0f[/b]   (CARGO for the full list)") % [
		int(load[0]), int(Company.wagon_kg()), load[1], Company.wagon_space()]
	_info.text = t
	_fill_cargo()
	_grog.text = Lang.t("GROG: ON") if bool(s["grog"]) else Lang.t("GROG: OFF")
	var batches := Company.cartridge_batches()
	_make.text = Lang.t("MAKE %d CARTRIDGES") % Company.CARTRIDGE_BATCH if batches > 0 else Lang.t("NO POWDER/LEAD")
	_make.disabled = batches <= 0
	_make.tooltip_text = Lang.t("1 lb of powder and 3 lb of lead make %d cartridges.") % Company.CARTRIDGE_BATCH


func _on_share(key: String) -> void:
	Company.share_evenly(key)
	refresh()
	changed.emit()


func _on_share_all() -> void:
	Company.resupply_all()
	refresh()
	changed.emit()


## What the settlement you're at sells: [amount, crowns], or [] if nothing.
## Nobody in this land makes gunpowder, so cartridges can't be bought.
func _offer(key: String) -> Array:
	var m := World.market_here()
	if m.is_empty():
		return []
	for o in Company.market_offers(String(m["kind"]), String(m["faction"]), int(m["id"])):
		if String(o[0]) == key:
			return [o[1], Company.price(int(o[2]))]
	return []


func _on_buy(key: String) -> void:
	var offer := _offer(key)
	if offer.is_empty() or Company.money < int(offer[1]):
		return
	if Company.room_for(key) < int(offer[0]):
		return
	Company.money -= int(offer[1])
	Company.stow(key, int(offer[0]))
	var m := World.market_here()
	if not m.is_empty():
		preload("res://scripts/economy.gd").bought(int(m["id"]), key, int(offer[0]))
	Company.save()
	refresh()
	changed.emit()


func _on_make() -> void:
	Company.make_cartridges(1)
	refresh()
	changed.emit()


func _on_grog() -> void:
	Company.stores["grog"] = not bool(Company.stores["grog"])
	Company.save()
	refresh()
	changed.emit()


func _toggle_cargo() -> void:
	_cargo.visible = not _cargo.visible
	_grid.visible = not _cargo.visible
	_info.visible = not _cargo.visible
	_cargo_btn.text = Lang.t("SUPPLIES") if _cargo.visible else Lang.t("THE WAGON")
	_fill_cargo()


## The wagon, drawn (wagon_view.gd), and what you picked in it.
func _fill_cargo() -> void:
	if not _cargo.visible:
		return
	_wagon.selected = _pick
	_wagon.refresh()
	_pick = _wagon.selected
	_fill_detail()


func _on_pick(id: String) -> void:
	_pick = id
	if _wagon.selected != id:
		_wagon.selected = id
		_wagon.queue_redraw()
	_fill_detail()


func _fill_detail() -> void:
	for c in _detail_btns.get_children():
		c.queue_free()
	var more: VBoxContainer = _detail_btns.get_meta("more")
	for c in more.get_children():
		c.queue_free()
	if _pick == "":
		var t := Lang.t("[b]THE WAGON[/b]\nTap anything in it to see what it is, what it weighs and what to do with it.\n\nEvery square is a slot of room in the wagon; the bigger the load, the more slots it takes. The barrels on the side are the drinking water.")
		_detail.text = t
		_water_buttons(more)
		return
	var id := _pick
	var n := int(Company.stores.get(id, 0)) if Company.CONSUMABLES.has(id) else Company.item_count(id)
	var l := Company.load_of(id, n)
	var desc := ""
	if STORE_TEXT.has(id):
		desc = Lang.t(STORE_TEXT[id])
	elif Company.ITEMS.has(id):
		desc = Lang.t(String(Company.ITEMS[id].get("desc", "")))
	var t := Lang.t("[b]%s[/b]  ×%d\n%.1f kg  ·  %d slots\n\n%s") % [Company.item_label(id), n, l[0], maxi(1, int(ceil(l[1] - 0.001))), desc]
	if Company.ITEMS.has(id) and String(Company.ITEMS[id].get("slot", "")) != "":
		t += Lang.t("\n\n[color=#%s]Give it to a man on the COMPANY screen (tap him, then his kit).[/color]") % DIM.to_html(false)
	if id == "water":
		t += Lang.t("\n\n%d days' water for %d men.%s") % [int(Company.days_left("water")), Company.roster.size(),
			Lang.t(" [color=#%s]It's foul: serve it as grog.[/color]") % RED.to_html(false) if bool(Company.stores["foul"]) else ""]
	_detail.text = t
	var share_key := "ammo" if id in ["ammo", "arrows", "bolts"] else id
	if id in ["water", "rations", "ammo", "arrows", "bolts"]:
		_detail_btns.add_child(_button(Lang.t("SHARE OUT"), _on_share.bind(share_key)))
	if id == "water":
		_water_buttons(more)
	if n > 0 and id != "water":
		more.add_child(_button(Lang.t("THROW ONE OUT"), _on_dump.bind(id, 1)))
		if n > 1:
			more.add_child(_button(Lang.t("THROW IT ALL OUT"), _on_dump.bind(id, n)))


## Filling the barrels (from whatever is here, named), and catching rain.
func _water_buttons(box: VBoxContainer) -> void:
	var fs: Array = World.fill_state()
	var fb := _button(String(fs[0]), _on_fill)
	fb.disabled = not bool(fs[1])
	fb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fb.custom_minimum_size = Vector2(320, 54)
	box.add_child(fb)
	var on := bool(Company.stores.get("rain_catch", true))
	var rb := _button(Lang.t("COLLECT RAIN WATER: ON") if on else Lang.t("COLLECT RAIN WATER: OFF"), func():
		Company.stores["rain_catch"] = not bool(Company.stores.get("rain_catch", true))
		Company.save()
		_fill_detail())
	rb.custom_minimum_size = Vector2(320, 54)
	box.add_child(rb)
	var note := _label(Lang.t("When it rains, sailcloth is spread to fill the barrels with clean water; but the rain gets at the powder in the wagon too.") if on \
		else Lang.t("The cover stays shut in the rain: the powder keeps drier, but no rain-water goes into the barrels."), 14, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	box.add_child(note)


## Lighten the wagon: leave things by the road.
func _on_dump(id: String, n: int) -> void:
	if Company.CONSUMABLES.has(id):
		Company.stores[id] = maxi(0, int(Company.stores.get(id, 0)) - n)
	else:
		Company.add_item(id, -n)
	Company.save()
	refresh()
	changed.emit()


func _on_fill() -> void:
	World.fill_barrels()
	refresh()
	changed.emit()
