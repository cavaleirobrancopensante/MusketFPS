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
	_cargo_head = RichTextLabel.new()
	_cargo_head.bbcode_enabled = true
	_cargo_head.fit_content = true
	_cargo_head.scroll_active = false
	_cargo_head.add_theme_font_size_override("normal_font_size", 18)
	_cargo.add_child(_cargo_head)
	var sc := UI.scroll()
	sc.custom_minimum_size = Vector2(0, 330)
	_cargo.add_child(sc)
	_cargo_list = VBoxContainer.new()
	_cargo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_cargo_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_cargo_btn = _button(Lang.t("CARGO"), _toggle_cargo)
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
		if not offer.is_empty():
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
	for o in Company.market_offers(String(m["kind"]), String(m["faction"])):
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
	_cargo_btn.text = Lang.t("SUPPLIES") if _cargo.visible else Lang.t("CARGO")
	_fill_cargo()


## Everything in the wagon: stores and spare kit, with their weight.
func _fill_cargo() -> void:
	if not _cargo.visible:
		return
	var load := Company.wagon_load()
	_cargo_head.text = Lang.t("[b]CARGO[/b]   %d / %d kg   ·   space %.0f / %.0f") % [int(load[0]), int(Company.wagon_kg()),
		load[1], Company.wagon_space()]
	for c in _cargo_list.get_children():
		c.queue_free()
	var rows: Array = []
	for k in Company.CONSUMABLES:
		if int(Company.stores.get(k, 0)) > 0:
			rows.append([k, int(Company.stores[k])])
	for id in Company.stores["items"]:
		rows.append([id, int(Company.stores["items"][id])])
	for r in rows:
		var l := Company.load_of(String(r[0]), int(r[1]))
		_cargo_list.add_child(_label(Lang.t("%s ×%d   ·   %.1f kg   ·   %.1f space") % [Company.item_label(r[0]), int(r[1]), l[0], l[1]],
			18, Color.WHITE))
