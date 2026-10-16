extends Control
## Main menu: pick the 2D (sprites) or 3D (models) version of the battle.
## Built in code like the rest of the game.

const BATTLE := "res://scenes/battle.tscn"

var _tp_check: CheckButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Headless test runs skip the menu: `-- --autotest [--3d]`.
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args or "--shots" in args:
		Settings.use_3d = "--3d" in args
		Settings.third_person = "--tp" in args
		Settings.stress = "--stress" in args
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
	box.add_theme_constant_override("separation", 22)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	var title := Label.new()
	title.text = "MUSKET FPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Hold the line against the lizardmen"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	box.add_child(sub)

	box.add_child(_button("PLAY  —  2D SPRITES", false))
	box.add_child(_button("PLAY  —  3D MODELS", true))

	var stress_row := HBoxContainer.new()
	stress_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stress_row.add_theme_constant_override("separation", 16)
	stress_row.add_child(_small_button("STRESS TEST 2D", false))
	stress_row.add_child(_small_button("STRESS TEST 3D", true))
	box.add_child(stress_row)

	_tp_check = CheckButton.new()
	_tp_check.text = "3D: start in third person"
	_tp_check.button_pressed = Settings.third_person
	_tp_check.add_theme_font_size_override("font_size", 22)
	_tp_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_tp_check)


func _button(text: String, use_3d: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 90)
	b.add_theme_font_size_override("font_size", 32)
	b.pressed.connect(func(): _start(use_3d))
	return b


## 50 musketeers vs 200 lizardmen, with an FPS counter.
func _small_button(text: String, use_3d: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(252, 64)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func(): _start(use_3d, true))
	return b


func _start(use_3d: bool, stress := false) -> void:
	Settings.stress = stress
	Settings.use_3d = use_3d
	Settings.third_person = _tp_check.button_pressed
	get_tree().change_scene_to_file(BATTLE)
