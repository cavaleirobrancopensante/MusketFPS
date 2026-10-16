extends Control
## Main menu: continue the last campaign, start a new one or load another
## from the save slots (each slot is its own campaign in its own land), or
## run the stress test (50 musketeers against 200 lizardmen with an FPS
## counter). Built in code like the rest of the game.

const BATTLE := "res://scenes/battle.tscn"
const CAMP := "res://scenes/aftermath.tscn"
const COMPANY := "res://scenes/company.tscn"
const INTRO := "res://scenes/intro.tscn"
const MusicBar := preload("res://scripts/music_bar.gd")
const MAP := "res://scenes/map.tscn"

var _tp_check: CheckButton
var _slots_panel: PanelContainer
var _slots_box: VBoxContainer
var _slots_title: Label
var _mode := "new" # the slot panel is for "new" or "load"
var _armed := "" # a destructive button waiting for its second tap


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Headless test runs skip the menu:
	#   -- --autotest [--stress] [--tp]   a stand-alone battle
	#   -- --autotest --campaign          a new campaign, battle after battle
	var args := OS.get_cmdline_user_args()
	for a in ["--intro", "--intro-render", "--maptest", "--company", "--autotest", "--shots", "--plantest", "--loottest", "--officer"]:
		if a in args:
			Settings.slot = 99 # tests never touch the player's saves
	if "--intro" in args or "--intro-render" in args:
		if "--intro" in args:
			Engine.time_scale = 4.0
		Company.new_campaign()
		get_tree().change_scene_to_file.call_deferred(INTRO)
		return
	if "--maptest" in args:
		# Headless check of the map: a new campaign straight after the beach.
		Company.new_campaign()
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.reset()
		get_tree().change_scene_to_file.call_deferred(MAP)
		return
	if "--loottest" in args:
		Company.new_campaign()
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		# A wagon packed to the brim and two men down: their kit can't all fit.
		Company.stow("rations", 99999)
		var men := {}
		for m in Company.roster:
			men[int(m["id"])] = {"status": "ok", "kills": 0}
		for m in Company.roster.slice(0, 2):
			men[int(m["id"])] = {"status": "killed", "kills": 0}
		Company.apply_battle({"won": true, "slain": 30, "officer_kills": 2, "men": men, "enemy": "lizards"})
		get_tree().change_scene_to_file.call_deferred("res://scenes/loot.tscn")
		return
	if "--plantest" in args:
		Company.new_campaign()
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred("res://scenes/battleplan.tscn")
		return
	if "--officer" in args:
		Company.new_campaign()
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred("res://scenes/officer.tscn")
		return
	if "--company" in args:
		# Headless check of the Company screen after the prologue.
		Company.new_campaign()
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred(COMPANY)
		return
	if "--autotest" in args or "--shots" in args:
		Settings.third_person = "--tp" in args
		Settings.stress = "--stress" in args
		if "--camp" in args:
			# A night camp attacked: -- --autotest --camp [--spotted]
			Company.new_campaign()
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			for m in Company.roster:
				m["wounded_days"] = 0
			var fit := Company.fit_men()
			Company.next_battle = {"enemy": 18, "terrain": 3, "party": -1, "ambush": false, "camp": true,
				"spotted": "--spotted" in args, "night": true, "watch": [int(fit[0]["id"]), int(fit[1]["id"])]}
		elif "--campaign" in args:
			Company.new_campaign()
		else:
			Company.active = false
		get_tree().change_scene_to_file.call_deferred(BATTLE)
		return

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	Music.set_context("menu")
	MusicBar.attach(self, Vector2(20, 20))

	var title := Label.new()
	title.text = "MUSKET FPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Lead your company against the lizardmen"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	box.add_child(sub)

	var last := Settings.slot_summary(Settings.slot)
	if not last.is_empty():
		var cont := _button("CONTINUE", _on_continue)
		cont.text = "CONTINUE  ·  slot %d, day %d" % [Settings.slot, int(last["day"])]
		box.add_child(cont)
	box.add_child(_button("NEW CAMPAIGN", _open_slots.bind("new")))
	box.add_child(_button("LOAD", _open_slots.bind("load")))

	var stress := _button("STRESS TEST  (50 vs 200)", _on_stress)
	stress.custom_minimum_size = Vector2(520, 64)
	stress.add_theme_font_size_override("font_size", 22)
	box.add_child(stress)

	_tp_check = CheckButton.new()
	_tp_check.text = "Start battles in third person"
	_tp_check.button_pressed = Settings.third_person
	_tp_check.add_theme_font_size_override("font_size", 22)
	_tp_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_tp_check)
	_build_slots()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 84)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	return b


func _on_continue() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = false
	Settings.save_prefs()
	World.is_ready = false # load this slot's land fresh
	if Company.load_campaign():
		# Saved before the prologue was fought: back to the beach.
		if Company.prologue:
			get_tree().change_scene_to_file(BATTLE)
		elif Company.results_unseen or not World.has_save():
			get_tree().change_scene_to_file(CAMP)
		else:
			get_tree().change_scene_to_file(MAP) # back on the road


# ---------------------------------------------------------------- save slots

func _build_slots() -> void:
	_slots_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.18)
	sb.set_corner_radius_all(12)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 20)
	_slots_panel.add_theme_stylebox_override("panel", sb)
	_slots_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_slots_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slots_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_slots_panel.custom_minimum_size = Vector2(1000, 0)
	_slots_panel.visible = false
	add_child(_slots_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_slots_panel.add_child(v)
	_slots_title = Label.new()
	_slots_title.add_theme_font_size_override("font_size", 30)
	_slots_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	v.add_child(_slots_title)
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 10)
	v.add_child(_slots_box)
	var back := _button("BACK", func(): _slots_panel.visible = false)
	back.custom_minimum_size = Vector2(200, 60)
	v.add_child(back)


func _open_slots(mode: String) -> void:
	_mode = mode
	_armed = ""
	_fill_slots()
	_slots_panel.visible = true


func _fill_slots() -> void:
	_slots_title.text = "NEW CAMPAIGN: choose a slot (each is a new land)" if _mode == "new" else "LOAD A CAMPAIGN"
	for c in _slots_box.get_children():
		c.queue_free()
	for i in range(1, Settings.SLOTS + 1):
		var info := Settings.slot_summary(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_slots_box.add_child(row)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if info.is_empty():
			l.text = "SLOT %d   ·   empty" % i
			l.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
		else:
			var where := "on the beach" if info["prologue"] else "day %d" % int(info["day"])
			l.text = "SLOT %d   ·   %s, %d men, %d crowns%s\nsaved %s" % [i, where, int(info["men"]),
				int(info["money"]), ("  ·  land %s" % info["seed"]) if info["seed"] != "" else "", info["when"]]
		row.add_child(l)
		var main := ""
		if _mode == "new":
			main = "START HERE" if info.is_empty() else ("TAP AGAIN TO OVERWRITE" if _armed == "new%d" % i else "OVERWRITE")
		else:
			main = "LOAD"
		var b := _button(main, _on_slot.bind(i))
		b.custom_minimum_size = Vector2(250, 60)
		b.add_theme_font_size_override("font_size", 20)
		b.disabled = _mode == "load" and info.is_empty()
		row.add_child(b)
		if not info.is_empty():
			var d := _button("TAP AGAIN" if _armed == "del%d" % i else "DELETE", _on_delete.bind(i))
			d.custom_minimum_size = Vector2(140, 60)
			d.add_theme_font_size_override("font_size", 18)
			row.add_child(d)


func _on_slot(i: int) -> void:
	var used := not Settings.slot_summary(i).is_empty()
	if _mode == "new":
		# Don't wipe a campaign with one stray tap.
		if used and _armed != "new%d" % i:
			_armed = "new%d" % i
			_fill_slots()
			return
		Settings.use_slot(i)
		Settings.third_person = _tp_check.button_pressed
		Settings.stress = false
		Settings.save_prefs()
		Settings.delete_slot(i)
		Company.new_campaign()
		World.reset() # a new land for a new campaign
		get_tree().change_scene_to_file(INTRO) # the shipwreck, then the beach
	else:
		Settings.use_slot(i)
		_on_continue()


func _on_delete(i: int) -> void:
	if _armed != "del%d" % i:
		_armed = "del%d" % i
		_fill_slots()
		return
	Settings.delete_slot(i)
	_armed = ""
	_fill_slots()


func _on_stress() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = true
	Company.active = false
	get_tree().change_scene_to_file(BATTLE)
