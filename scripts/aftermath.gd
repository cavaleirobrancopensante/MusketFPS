extends Control
## Between battles: the aftermath of the last fight and the company in camp.
##
## Left: what happened (slain, bounty, the fallen, the wounded, promotions)
## and what you can do: hire recruits, march on to the next fight, read the
## roll of honour. Right: every man in the company with his rank, record,
## progress to the next rank and whether he's fit to fight.

const UI := preload("res://scripts/ui.gd")
const MusicBar := preload("res://scripts/music_bar.gd")
const BATTLE := "res://scenes/battle.tscn"
const MENU := "res://scenes/menu.tscn"
const COMPANY := "res://scenes/company.tscn"
const MAP := "res://scenes/map.tscn"
const LOOT := "res://scenes/loot.tscn"
const Men := preload("res://scripts/men.gd")
const LogisticsPopup := preload("res://scripts/logistics_popup.gd")

const GOLD := Color("d4ad55") # brass (ui.gd)
const RED := Color(0.95, 0.42, 0.35)
const GREEN := Color(0.55, 0.9, 0.55)
const DIM := Color("9aa3b8") # slate (ui.gd)
const BG := UI.NIGHT
const PANEL := UI.WOOL

var _summary: RichTextLabel
var _header: Label
var _sub: Label
var _list: VBoxContainer
var _list_title: Label
var _hire: Button
var _march: Button
var _honour: Button
var _showing_honour := false
var _logistics


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	# ---- left: what happened, and what to do next
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	_header = _label("", 46, GOLD)
	left.add_child(_header)
	_sub = _label("", 20, DIM)
	left.add_child(_sub)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("normal_font_size", 21)
	_summary.add_theme_font_size_override("bold_font_size", 21)
	left.add_child(_summary)
	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 12)
	buttons.add_theme_constant_override("v_separation", 12)
	left.add_child(buttons)
	_march = _button(Lang.t("TO THE MAP"), _on_march)
	_hire = _button("", _on_hire)
	_honour = _button(Lang.t("ROLL OF HONOUR"), _on_honour)
	if not Company.loot.is_empty():
		var lb := _button(Lang.t("LOOT THE FIELD (%d)") % Company.loot.size(), func():
			Company.results_unseen = false
			Loading.change(LOOT))
		lb.add_theme_color_override("font_color", GOLD)
		buttons.add_child(lb)
	buttons.add_child(_button(Lang.t("YOU"), func():
		get_tree().set_meta("officer_back", "res://scenes/aftermath.tscn")
		Loading.change("res://scenes/officer.tscn")))
	buttons.add_child(_button(Lang.t("COMPANY & KIT"), _on_company))
	buttons.add_child(_button(Lang.t("WAGON"), func(): _logistics.open()))
	buttons.add_child(_march)
	buttons.add_child(_hire)
	buttons.add_child(_honour)
	buttons.add_child(_button(Lang.t("SAVE & MENU"), _on_menu))

	# ---- right: the company
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UI.box(PANEL, 16)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	right.add_theme_stylebox_override("panel", sb)
	row.add_child(right)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 8)
	right.add_child(rbox)
	_list_title = _label("", 24, GOLD)
	rbox.add_child(_list_title)
	var scroll := UI.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	Music.set_context("camp")
	MusicBar.attach(self, Vector2(get_viewport_rect().size.x - 84, get_viewport_rect().size.y - 84))
	_logistics = LogisticsPopup.new()
	add_child(_logistics)
	_logistics.changed.connect(_refresh)
	_refresh()


# ---------------------------------------------------------------- building blocks

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.dress(l, size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 64)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b


static func _n(n: int, word: String) -> String:
	return "%d %s" % [n, Lang.t(word + ("" if n == 1 else "s"))]


static func _hex(c: Color) -> String:
	return c.to_html(false)


# ---------------------------------------------------------------- content

func _refresh() -> void:
	var r: Dictionary = Company.last_result
	var fresh: bool = Company.results_unseen and not r.is_empty()
	var fit := Company.fit_men().size()
	var men := Company.roster.size()

	if men == 0 and not Company.can_hire():
		_header.text = Lang.t("THE COMPANY IS NO MORE")
		_header.add_theme_color_override("font_color", RED)
	elif fresh and r.get("prologue", false):
		_header.text = Lang.t("CASTAWAYS")
		_header.add_theme_color_override("font_color", RED)
	elif fresh:
		_header.text = Lang.t("VICTORY") if r["won"] else Lang.t("DEFEAT")
		_header.add_theme_color_override("font_color", GOLD if r["won"] else RED)
	else:
		_header.text = Lang.t("IN CAMP")
		_header.add_theme_color_override("font_color", GOLD)
	_sub.text = Lang.t("%s  ·  Day %d  ·  %s, %d won  ·  %d crowns  ·  wages %d/wk") % [
		Lang.t(Company.officer.get("rank", "Captain")), Company.day, _n(Company.battles, "battle"), Company.victories,
		Company.money, Company.weekly_wages()]

	var t := ""
	if fresh and r.get("prologue", false):
		t += Lang.t("[color=#%s]The beach is lost. %s fell at the earthworks and gave you the company as he died. You led what was left of it up the cliff path into an unknown land, with no ship, no allies and no word from home.[/color]\n\n") % [_hex(DIM), r.get("captain", Lang.t("The Major"))]
		t += Lang.t("You are its captain now. The men are shaken (morale %d).\n") % Company.company_morale()
		t += Lang.t("Lizardmen slain on the field: [b]%d[/b]\n") % int(r["slain"])
		t += _section("Fallen", r["fallen"], RED, Lang.t("None. Every man came back."))
		t += _section("Wounded", r["wounded"], Color(1, 0.7, 0.4), "")
		t += _section(Lang.t("Levelled up (points to spend)"), r.get("levelled", []), GOLD, "")
		var st: Dictionary = Company.stash
		t += Lang.t("\n[color=#%s]The lizards carried off the ship's stores: %d muskets, powder and ball for %d shots, %d guns, %d tots of rum. Getting them back is the first task.[/color]\n") % [
			_hex(RED), int(st.get("muskets", 0)), int(st.get("ammo", 0)), int(st.get("cannons", 0)), int(st.get("rum", 0))]
		t += Lang.t("\n[color=#%s]%d pieces of kit were dropped in the rout. The little wagon you saved holds the Major's rifle and a few days' food. See to your men on the COMPANY & KIT screen.[/color]\n") % [_hex(GOLD), int(r.get("lost_gear", 0))]
	elif fresh:
		var humans := String(r.get("enemy", "lizards")) == "humans"
		t += Lang.t("%s slain: [b]%d[/b]\n") % [Lang.t("Enemy soldiers") if humans else Lang.t("Lizardmen"), int(r["slain"])]
		if r.has("standing_note"):
			t += "[color=#%s]%s[/color]\n" % [_hex(RED), r["standing_note"]]
		if r.has("nest_burned"):
			t += Lang.t("[color=#%s][b]%s burns.[/b] Its mounds are torn open and fired; no more warbands will come out of it.[/color]\n") % [_hex(GOLD), r["nest_burned"]]
		if r.has("stash"):
			t += Lang.t("[color=#%s][b]The ship's stores are ours again:[/b] %s. The guns will march with the company now, each with its crew.[/color]\n") % [_hex(GOLD), r["stash"]]
		var pay := int(r["pay"])
		if int(r.get("rations_spoiled", 0)) > 0 and int(r.get("wagon_looted", 0)) == 0:
			t += Lang.t("Lizards got into the wagon. You took back what they grabbed, but they'd eaten %d rations before you cut them down.\n") % int(r["rations_spoiled"])
		if bool(r.get("left_field", false)):
			t += Lang.t("[color=#%s]You left the field before the battle was decided. Ironman: it counts as a defeat.[/color]\n") % _hex(RED)
		if bool(r.get("horse_lost", false)):
			t += Lang.t("[color=#%s]Your horse was killed under you. A town's market may sell you another.[/color]\n") % _hex(RED)
		if int(r.get("wagon_looted", 0)) > 0:
			t += Lang.t("[color=#%s]Lizards plundered the wagon: %d%% of its stores are gone.[/color]\n") % [_hex(RED), int(r["wagon_looted"])]
		if humans and bool(r.get("won", false)):
			t += Lang.t("No bounty on men: what they carried is on the loot pile.\n")
		elif pay >= 0:
			t += Lang.t("Bounty: [color=#%s]+%d crowns[/color]\n") % [_hex(GOLD), pay]
			if int(r.get("loot", 0)) > 0:
				t += Lang.t("[color=#%s]There's loot on the field: LOOT THE FIELD to pick through it.[/color]\n") % _hex(GOLD)
		else:
			t += Lang.t("Baggage plundered: [color=#%s]%d crowns[/color], half the wagon's stores and %d pieces of kit\n") % [_hex(RED), pay, int(r.get("lost_gear", 0))]
			if r["fallen"].size() > 0:
				t += Lang.t("[color=#%s]The dead were left where they fell, and their muskets with them.[/color]\n") % _hex(RED)
		t += _section("Fallen", r["fallen"], RED, Lang.t("None. Every man came back."))
		t += _section("Wounded", r["wounded"], Color(1, 0.7, 0.4), "")
		t += _section(Lang.t("At the wagon"), r.get("conduct", []), DIM, "")
		t += _section("Promoted", r["promoted"], GOLD, "")
		t += _section(Lang.t("Levelled up (points to spend)"), r.get("levelled", []), GOLD, "")
	else:
		t += "[color=#%s]%s[/color]\n\n" % [_hex(DIM), Company.march_note]
		t += Lang.t("%d men, %d fit to fight. Morale %d (%s).\n") % [men, fit, Company.company_morale(),
			Men.morale_word(Company.company_morale())]
		var no_shot := Company.roster.filter(func(m): return int(m["pack"]["ammo"]) == 0 and Company.shot_key(m) != "").size()
		if no_shot > 0:
			t += Lang.t("[color=#%s]%d men have nothing to shoot.[/color]\n") % [_hex(RED), no_shot]
		pass
	if men > 0 and fit == 0:
		t += Lang.t("\n[color=#%s]Every man is wounded. Marching now means fighting alone.[/color]") % _hex(RED)
	_summary.text = t

	# Recruits can only be found where there are people: a town or city.
	var m := World.market_here()
	var in_town: bool = not m.is_empty() and m["kind"] in ["town", "city"]
	_hire.text = Lang.t("HIRE RECRUIT (%d)") % Company.RECRUIT_COST if in_town else Lang.t("HIRE (in towns)")
	_hire.disabled = not Company.can_hire() or not in_town
	_march.disabled = men == 0 and not Company.can_hire()
	_honour.text = Lang.t("THE COMPANY") if _showing_honour else Lang.t("ROLL OF HONOUR (%d)") % Company.fallen.size()
	if _showing_honour:
		_fill_honour()
	else:
		_fill_roster()


func _section(title: String, items: Array, col: Color, empty: String) -> String:
	if items.is_empty():
		return "\n[b]%s:[/b] %s\n" % [Lang.t(title), empty] if empty != "" else ""
	return "\n[b]%s:[/b]\n[color=#%s]%s[/color]\n" % [Lang.t(title), _hex(col), "\n".join(items)]


func _clear_list() -> void:
	for c in _list.get_children():
		c.queue_free()


func _fill_roster() -> void:
	_clear_list()
	_list_title.text = Lang.t("THE COMPANY  ·  %d men") % Company.roster.size()
	var men: Array = Company.roster.duplicate()
	# Highest rank first, then most experienced.
	men.sort_custom(func(a, b): return int(a["xp"]) > int(b["xp"]))
	for m in men:
		_list.add_child(_man_row(m))


func _man_row(m: Dictionary) -> Control:
	var rank := int(m["rank"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	box.add_child(top)
	var name_l := _label(Company.title(m), 22, Color.WHITE)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(name_l)
	var wd := int(m["wounded_days"])
	var status := _label(Lang.t("WOUNDED %dd") % wd if wd > 0 else Lang.t("FIT"), 18, RED if wd > 0 else GREEN)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(status)
	var info := "%s  ·  %s  ·  %s  ·  %s" % [Lang.t(Company.RANKS[rank]), _n(int(m["battles"]), "battle"),
		_n(int(m["kills"]), "kill"), _temper(float(m["steadiness"]))]
	box.add_child(_label(info, 17, DIM))
	# Progress to the next rank.
	if rank < Company.RANK_XP.size() - 1:
		var bar := ProgressBar.new()
		bar.min_value = Company.RANK_XP[rank]
		bar.max_value = Company.RANK_XP[rank + 1]
		bar.value = int(m["xp"])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		box.add_child(bar)
	box.add_child(HSeparator.new())
	return box


static func _temper(steadiness: float) -> String:
	if steadiness > 0.7:
		return "steady"
	if steadiness > 0.4:
		return "dependable"
	return "jumpy"


func _fill_honour() -> void:
	_clear_list()
	_list_title.text = Lang.t("ROLL OF HONOUR  ·  %d fallen") % Company.fallen.size()
	if Company.fallen.is_empty():
		_list.add_child(_label(Lang.t("No man of this company has fallen yet."), 20, DIM))
		return
	for i in range(Company.fallen.size() - 1, -1, -1):
		var f: Dictionary = Company.fallen[i]
		_list.add_child(_label("%s %s" % [Lang.t(f["rank"]), f["name"]], 22, Color.WHITE))
		_list.add_child(_label(Lang.t("Fell on day %d  ·  %s  ·  %s") % [
			int(f["day"]), _n(int(f["battles"]), "battle"), _n(int(f["kills"]), "kill")], 17, DIM))
		_list.add_child(HSeparator.new())


# ---------------------------------------------------------------- actions

func _on_hire() -> void:
	var m := Company.hire_recruit()
	if not m.is_empty():
		Company.march_note = Lang.t("%s joins the company with a worn musket and no cartridges. Kit him out on the COMPANY & KIT screen.") % Company.title(m)
		Company.results_unseen = false
		_refresh()


func _on_march() -> void:
	Company.results_unseen = false
	Company.save()
	Loading.change(MAP)


func _on_company() -> void:
	Company.results_unseen = false
	Company.save()
	Loading.change(COMPANY)


func _on_honour() -> void:
	_showing_honour = not _showing_honour
	_refresh()


func _on_menu() -> void:
	Company.save()
	Loading.change(MENU)
