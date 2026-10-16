extends Control
## Main menu: start a new campaign, continue the saved one, or run the stress
## test (50 musketeers against 200 lizardmen with an FPS counter).
## Built in code like the rest of the game.

const BATTLE := "res://scenes/battle.tscn"
const CAMP := "res://scenes/aftermath.tscn"
const COMPANY := "res://scenes/company.tscn"
const INTRO := "res://scenes/intro.tscn"
const MAP := "res://scenes/map.tscn"

var _tp_check: CheckButton
var _new_btn: Button
var _confirm_new := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Headless test runs skip the menu:
	#   -- --autotest [--stress] [--tp]   a stand-alone battle
	#   -- --autotest --campaign          a new campaign, battle after battle
	var args := OS.get_cmdline_user_args()
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
	if "--company" in args:
		# Headless check of the Company screen after the prologue.
		Company.new_campaign()
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred(COMPANY)
		return
	if "--autotest" in args or "--shots" in args:
		Settings.third_person = "--tp" in args
		Settings.stress = "--stress" in args
		if "--campaign" in args:
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

	var cont := _button("CONTINUE", _on_continue)
	cont.disabled = not Company.has_save()
	if Company.has_save():
		box.add_child(cont)
	_new_btn = _button("NEW CAMPAIGN", _on_new)
	box.add_child(_new_btn)

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
	if Company.load_campaign():
		# Saved before the prologue was fought: back to the beach.
		if Company.prologue:
			get_tree().change_scene_to_file(BATTLE)
		elif Company.results_unseen or not World.has_save():
			get_tree().change_scene_to_file(CAMP)
		else:
			get_tree().change_scene_to_file(MAP) # back on the road


func _on_new() -> void:
	# Don't wipe a campaign with one stray tap.
	if Company.has_save() and not _confirm_new:
		_confirm_new = true
		_new_btn.text = "TAP AGAIN: START OVER?"
		return
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = false
	Company.new_campaign()
	World.reset() # a new land for a new campaign
	get_tree().change_scene_to_file(INTRO) # the shipwreck, then the beach


func _on_stress() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = true
	Company.active = false
	get_tree().change_scene_to_file(BATTLE)
