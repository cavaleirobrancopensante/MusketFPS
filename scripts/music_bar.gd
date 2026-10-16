extends Control
## The music player: a small ♪ button that opens a panel with what's playing,
## previous / pause / next, random or in-order, Auto (follow the game), music
## on or off, volume steps and the full track list (swipe to scroll, tap to
## play). Volume is −/+ buttons, not a slider, so a swipe can't zero it
## (a lesson from TCG-RPG).
##
## Add it to any screen:  MusicBar.attach(root_control, Vector2(x, y))

const UI := preload("res://scripts/ui.gd")
const GOLD := Color("d4ad55") # brass (ui.gd)
const DIM := Color("9aa3b8") # slate (ui.gd)

var _panel: PanelContainer
var _title: Label
var _sub: Label
var _pause: Button
var _shuffle: Button
var _auto: Button
var _onoff: Button
var _vol: Label
var _list: VBoxContainer


static func attach(parent: Control, at: Vector2) -> Control:
	var bar = load("res://scripts/music_bar.gd").new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	bar._build(at)
	return bar


func _build(at: Vector2) -> void:
	var note := Button.new()
	note.text = "♪"
	note.add_theme_font_size_override("font_size", 28)
	note.custom_minimum_size = Vector2(UI.MIN_TOUCH, UI.MIN_TOUCH)
	note.position = at
	note.focus_mode = Control.FOCUS_NONE
	note.pressed.connect(func(): _panel.visible = not _panel.visible; _refresh(); _fill_list())
	add_child(note)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.box(Color(UI.WOOL, 0.98), 16, 6, 0.3))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(640, 560)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = _label("", 26, GOLD)
	v.add_child(_title)
	_sub = _label("", 17, DIM)
	v.add_child(_sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(_button("PREV", func(): Music.prev()))
	_pause = _button("PAUSE", func(): Music.toggle_pause())
	row.add_child(_pause)
	row.add_child(_button("NEXT", func(): Music.next()))
	_shuffle = _button("", func(): Music.set_shuffle(not Music.shuffle))
	row.add_child(_shuffle)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	v.add_child(row2)
	_auto = _button("", func(): Music.set_auto(not Music.auto))
	row2.add_child(_auto)
	_onoff = _button("", func(): Music.set_enabled(not Music.enabled))
	row2.add_child(_onoff)
	row2.add_child(_button("−", func(): Music.set_volume(Music.volume - 0.1)))
	_vol = _label("", 20, Color.WHITE)
	_vol.custom_minimum_size = Vector2(70, 0)
	_vol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row2.add_child(_vol)
	row2.add_child(_button("+", func(): Music.set_volume(Music.volume + 0.1)))
	var sc := UI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)
	v.add_child(_button("CLOSE", func(): _panel.visible = false))
	Music.track_changed.connect(func(_t): _refresh(); _fill_list())
	Music.state_changed.connect(_refresh)
	_refresh()


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
	b.custom_minimum_size = Vector2(UI.MIN_TOUCH * 1.6, UI.MIN_TOUCH)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _refresh() -> void:
	if _panel == null or not _panel.visible:
		return
	var t: Dictionary = Music.current
	_title.text = "♪ " + (String(t["title"]) if not t.is_empty() else "Nothing playing")
	_sub.text = Music.label(t) + ("" if Music.auto else "  ·  manual")
	if Music.last_error != "":
		_sub.text = Music.last_error
	_pause.text = "PLAY" if Music.paused else "PAUSE"
	_shuffle.text = "RANDOM" if Music.shuffle else "IN ORDER"
	_auto.text = "AUTO: ON" if Music.auto else "AUTO: OFF"
	_onoff.text = "MUSIC: ON" if Music.enabled else "MUSIC: OFF"
	_vol.text = "%d%%" % int(round(Music.volume * 100))


func _fill_list() -> void:
	if _panel == null or not _panel.visible:
		return
	for c in _list.get_children():
		c.queue_free()
	for t in Music.tracks:
		var b := Button.new()
		var playing: bool = not Music.current.is_empty() and Music.current["id"] == t["id"]
		b.text = "%s%s   ·   %s" % ["▶ " if playing else "", t["title"], Music.THEME_NAMES.get(t["theme"], "")]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
		b.add_theme_font_size_override("font_size", 18)
		if playing:
			b.add_theme_color_override("font_color", GOLD)
		b.pressed.connect(Music.choose.bind(t["id"]))
		_list.add_child(b)
