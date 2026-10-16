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
const GOLD := Color(0.95, 0.8, 0.45)
const RED := Color(0.95, 0.42, 0.35)
const GREEN := Color(0.55, 0.9, 0.55)
const DIM := Color(0.72, 0.74, 0.8)

var _grid: GridContainer
var _info: RichTextLabel
var _grog: Button
var _title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.18)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(0.95, 0.8, 0.45, 0.4)
	sb.set_border_width_all(2)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 18)
	panel.add_theme_stylebox_override("panel", sb)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_grog = _button("", _on_grog)
	row.add_child(_grog)
	var all := _button("SHARE EVERYTHING EVENLY", _on_share_all)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(all)
	row.add_child(_button("CLOSE", func(): visible = false))
	visible = false


func open() -> void:
	refresh()
	visible = true


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
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
	_title.text = "LOGISTICS  ·  THE WAGON  ·  %d crowns  ·  %d men" % [Company.money, men]
	for c in _grid.get_children():
		c.queue_free()
	for h in ["", "WAGON", "PACKS", "PER DAY", "DAYS LEFT", "", ""]:
		_grid.add_child(_label(h, 15, DIM))
	for key in ["water", "rations", "ammo", "rum"]:
		var name: String = {"water": "Water", "rations": "Rations", "ammo": "Cartridges", "rum": "Rum (tots)"}[key]
		var in_packs := 0
		if Company.PACK.has(key):
			for m in Company.roster:
				in_packs += int(m["pack"][key])
		var per_day := men if key in ["water", "rations"] else (men if key == "rum" and bool(s["foul"]) and bool(s["grog"]) else 0)
		var total := int(s[key]) + in_packs
		var days := "-"
		var col := Color.WHITE
		if per_day > 0:
			var d := float(total) / per_day
			days = "%.1f" % d
			col = RED if d < 2.0 else (Color(1, 0.8, 0.4) if d < 4.0 else GREEN)
		elif key == "ammo":
			days = "%d a man" % (total / maxi(1, men))
		_grid.add_child(_label(name, 20, Color.WHITE))
		_grid.add_child(_label(str(int(s[key])), 20, Color.WHITE))
		_grid.add_child(_label(str(in_packs) if Company.PACK.has(key) else "-", 20, Color.WHITE))
		_grid.add_child(_label(str(per_day) if per_day > 0 else "-", 20, DIM))
		_grid.add_child(_label(days, 20, col))
		if Company.PACK.has(key):
			var b := _button("SHARE EVENLY", _on_share.bind(key))
			b.add_theme_font_size_override("font_size", 15)
			_grid.add_child(b)
		else:
			_grid.add_child(Control.new())
		# You can only buy where someone sells: at a settlement on the map.
		var offer := _offer(key)
		if not offer.is_empty():
			var buy := _button("BUY %d (%d cr)" % [int(offer[0]), int(offer[1])], _on_buy.bind(key))
			buy.add_theme_font_size_override("font_size", 15)
			buy.disabled = Company.money < int(offer[1])
			_grid.add_child(buy)
		else:
			var why := "rivers, lakes, towns" if key == "water" else ("nobody here makes powder" if key == "ammo" else "")
			_grid.add_child(_label(why, 15, DIM))

	var t := ""
	var market := World.market_here()
	if market.is_empty():
		t += "[color=#%s]Nobody to buy from out here: visit a village, town, city or hold.[/color]\n" % DIM.to_html(false)
	else:
		t += "At %s: food%s for sale.\n" % [market["name"], " and rum" if market["kind"] != "village" else ""]
	if bool(s["foul"]):
		t += "[color=#%s][b]The water is foul.[/b][/color] Drunk plain, it makes men sick. " % RED.to_html(false)
		if bool(s["grog"]) and int(s["rum"]) > 0:
			t += "Served as grog: a tot of rum a man a day.\n"
		elif bool(s["grog"]):
			t += "[color=#%s]No rum left for grog![/color]\n" % RED.to_html(false)
		else:
			t += "Grog is off: they'll drink it plain.\n"
	else:
		t += "The water is clean.\n"
	var spread := Company.ration_spread()
	if int(spread[1]) - int(spread[0]) >= 3:
		t += "[color=#%s]Rations are uneven: %d to %d days a man. The men with less resent it, and a man who starves while others eat may not forgive it.[/color]\n" % [
			Color(1, 0.75, 0.4).to_html(false), int(spread[0]), int(spread[1])]
	else:
		t += "Rations are fair: %d to %d days a man.\n" % [int(spread[0]), int(spread[1])]
	var sick := 0
	var hungry := 0
	var thirsty := 0
	for m in Company.roster:
		sick += 1 if int(m["sick"]) > 0 else 0
		hungry += 1 if int(m["hunger"]) > 0 else 0
		thirsty += 1 if int(m["thirst"]) > 0 else 0
	var cm := Company.company_morale()
	t += "Morale [b]%d[/b] (%s)   ·   sick %d   ·   hungry %d   ·   thirsty %d" % [
		cm, Men.morale_word(cm), sick, hungry, thirsty]
	if cm < Company.MUTINY_MORALE:
		t += "\n[color=#%s][b]The men are close to mutiny.[/b][/color]" % RED.to_html(false)
	_info.text = t
	_grog.text = "GROG: ON" if bool(s["grog"]) else "GROG: OFF"


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
	if m.is_empty() or key in ["ammo", "water"]:
		return []
	var kind: String = m["kind"]
	if key == "rations":
		return {"village": [10, 5], "town": [20, 9], "city": [20, 8], "hold": [20, 10]}[kind]
	if key == "rum" and kind != "village":
		return [10, 6]
	return []


func _on_buy(key: String) -> void:
	var offer := _offer(key)
	if offer.is_empty() or Company.money < int(offer[1]):
		return
	Company.money -= int(offer[1])
	Company.stores[key] = int(Company.stores[key]) + int(offer[0])
	Company.save()
	refresh()
	changed.emit()


func _on_grog() -> void:
	Company.stores["grog"] = not bool(Company.stores["grog"])
	Company.save()
	refresh()
	changed.emit()
