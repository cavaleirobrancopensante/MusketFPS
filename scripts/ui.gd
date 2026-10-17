extends RefCounted
## Small shared UI helpers for touch screens.
##
## scroll(): a ScrollContainer you can swipe anywhere, even over the buttons
## inside it (Godot's own touch scrolling stops at the first button, which
## eats the press). A press that moves more than DRAG_START pixels becomes a
## swipe and cancels the button underneath; a short press is still a tap.
## The pattern comes from Robot Fighting (ui.gd DragScroll).

const DRAG_START := 14.0
const MIN_TOUCH := 56.0 # the smallest thing a finger should have to hit

# ---------------------------------------------------------------- the look
# The UI wears the regiment's coat: blue wool panels edged with pipeclay
# piping, brass for the things that matter, madder red when something is
# pressed or wrong. Titles are set in IM Fell (old printers' type, an order
# book's headings); everything else in Alegreya Sans, which stays readable
# small on a phone. Settings applies the theme to the whole window at start.

const NIGHT := Color("10172a") # behind everything
const WOOL := Color("1c2742") # panels
const WOOL_LIGHT := Color("2a3858") # buttons
const WOOL_DARK := Color("121a2e") # the shadow under a button
const PIPECLAY := Color("e8e4d8") # text, and the piping round panels
const BRASS := Color("c9a14a") # headings and the main action
const MADDER := Color("9e2a22") # pressed, selected, danger
const SLATE := Color("8d97ad") # secondary text

static var _theme: Theme
static var _fonts := {}


## A font from res://fonts (imported by the editor, or read raw if not yet).
static func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var path := "res://fonts/%s.woff2" % name
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path)
	if f == null and FileAccess.file_exists(path):
		var ff := FontFile.new()
		ff.data = FileAccess.get_file_as_bytes(path)
		f = ff
	if f == null:
		f = ThemeDB.fallback_font
	# The symbols (♪ ▲ ★ ⚔ ✕ ...) aren't in the text fonts, and a browser
	# has no system fonts to fall back on: a small DejaVu subset has them.
	if name != "symbols":
		var sym := font("symbols")
		if sym != f and sym not in f.fallbacks:
			f.fallbacks = f.fallbacks + [sym]
	_fonts[name] = f
	return f


static func display_font() -> Font:
	return font("fell_sc")


## A panel's box: wool with a thin pipeclay edge.
static func box(col := WOOL, pad := 12, radius := 6, piping := 0.16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.border_color = Color(PIPECLAY, piping)
	sb.set_border_width_all(1 if piping > 0.0 else 0)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, pad)
	sb.anti_aliasing = true
	return sb


## A button state: a raised wool tab (a darker lip along the bottom), brass
## when it's the main action, madder when pressed.
static func button_box(state: String, primary := false) -> StyleBoxFlat:
	var base := BRASS if primary else WOOL_LIGHT
	var col := base
	match state:
		"hover": col = base.lightened(0.1)
		"pressed": col = MADDER if not primary else BRASS.darkened(0.2)
		"disabled": col = Color(base.darkened(0.35), 0.55)
		"focus": col = Color(0, 0, 0, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(5)
	sb.anti_aliasing = true
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	if state == "focus":
		sb.draw_center = false
		sb.border_color = Color(BRASS, 0.8)
		sb.set_border_width_all(2)
	elif state != "pressed" and state != "disabled":
		sb.border_color = (WOOL_DARK if not primary else BRASS.darkened(0.45))
		sb.border_width_bottom = 3
		sb.border_color.a = 0.9
	else:
		sb.content_margin_top = 8
		sb.content_margin_bottom = 6
	return sb


## Style one button by hand (when it needs the brass look, or sits on a
## screen that overrides its own styles).
static func style_button(b: Button, primary := false) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, button_box(st, primary))
	var fc := NIGHT if primary else PIPECLAY
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", PIPECLAY if not primary else NIGHT)
	b.add_theme_color_override("font_focus_color", fc)


## "THE COMPANY · 18 men" -> "The company · 18 men": shouted words in
## sentence case, so the small-capitals face can do the work.
static func title_case(text: String) -> String:
	var out: PackedStringArray = []
	var first := true
	for w in text.split(" "):
		var letters := w.strip_edges()
		if letters.length() > 1 and letters == letters.to_upper() and letters != letters.to_lower():
			w = (w.substr(0, 1) + w.substr(1).to_lower()) if first else w.to_lower()
		if letters != "" and letters != "·":
			first = letters.ends_with(":") or letters.ends_with(".")
		out.append(w)
	return " ".join(out)


## Big labels become headings: the display face, a touch larger (it runs
## small), and sentence case.
static func dress(l: Label, size: int) -> void:
	if size < 22:
		return
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size + 4)
	l.text = title_case(l.text)


## A heading label in the display face.
static func heading(text: String, size := 30, col := BRASS) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var sym := font("symbols")
	if sym not in ThemeDB.fallback_font.fallbacks:
		ThemeDB.fallback_font.fallbacks = ThemeDB.fallback_font.fallbacks + [sym]
	var body := font("alegreya_sans_400")
	var medium := font("alegreya_sans_500")
	var bold := font("alegreya_sans_700")
	var italic := font("alegreya_sans_400-italic")
	t.default_font = body
	t.default_font_size = 20
	t.set_color("font_color", "Label", PIPECLAY)
	# Buttons.
	for type in ["Button", "OptionButton", "CheckButton", "CheckBox", "MenuButton"]:
		t.set_font("font", type, medium)
		t.set_color("font_color", type, PIPECLAY)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, PIPECLAY)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(SLATE, 0.6))
	for type in ["Button", "OptionButton", "MenuButton"]:
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			t.set_stylebox(st, type, button_box(st))
		t.set_stylebox("hover_pressed", type, button_box("pressed"))
	# The main action: brass.
	t.set_type_variation("PrimaryButton", "Button")
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "PrimaryButton", button_box(st, true))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", NIGHT)
	# Toggles: no box, just the text and the switch.
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var e := StyleBoxEmpty.new()
		t.set_stylebox(st, "CheckButton", e)
		t.set_stylebox(st, "CheckBox", e)
	# Panels.
	t.set_stylebox("panel", "PanelContainer", box())
	t.set_stylebox("panel", "Panel", box())
	t.set_stylebox("panel", "PopupMenu", box(WOOL, 8))
	t.set_stylebox("panel", "TooltipPanel", box(WOOL_DARK, 8))
	t.set_color("font_color", "PopupMenu", PIPECLAY)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", box(MADDER, 4, 3, 0.0))
	t.set_font("font", "PopupMenu", medium)
	# Headings.
	t.set_type_variation("HeaderLarge", "Label")
	t.set_font("font", "HeaderLarge", display_font())
	t.set_font_size("font_size", "HeaderLarge", 34)
	t.set_color("font_color", "HeaderLarge", BRASS)
	t.set_type_variation("HeaderMedium", "Label")
	t.set_font("font", "HeaderMedium", display_font())
	t.set_font_size("font_size", "HeaderMedium", 24)
	t.set_color("font_color", "HeaderMedium", BRASS)
	# Rich text.
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font("italics_font", "RichTextLabel", italic)
	t.set_font("bold_italics_font", "RichTextLabel", bold)
	t.set_color("default_color", "RichTextLabel", PIPECLAY)
	# Bars, fields, scroll bars.
	var bar_bg := box(WOOL_DARK, 0, 3, 0.12)
	var bar_fill := box(BRASS, 0, 3, 0.0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", PIPECLAY)
	var field := box(WOOL_DARK, 10, 4, 0.3)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", box(WOOL_DARK, 10, 4, 0.7))
	t.set_color("font_color", "LineEdit", PIPECLAY)
	t.set_color("caret_color", "LineEdit", BRASS)
	for sb_type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(WOOL_DARK, 0.6)
		track.set_corner_radius_all(4)
		track.content_margin_left = 3
		track.content_margin_right = 3
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(BRASS, 0.55)
		grab.set_corner_radius_all(4)
		t.set_stylebox("scroll", sb_type, track)
		t.set_stylebox("grabber", sb_type, grab)
		var grab_hi := grab.duplicate()
		grab_hi.bg_color = BRASS
		t.set_stylebox("grabber_highlight", sb_type, grab_hi)
		t.set_stylebox("grabber_pressed", sb_type, grab_hi)
	_theme = t
	return t


## A swipeable vertical list.
static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = int(DRAG_START)
	drag_scroll(sc)
	return sc


static func drag_scroll(sc: ScrollContainer) -> void:
	var d := DragScroll.new()
	d.sc = sc
	sc.add_child(d)


class DragScroll extends Node:
	var sc: ScrollContainer
	var down := false
	var dragging := false
	var start := Vector2.ZERO
	var last_y := 0.0
	var speed := 0.0 # px per second, for a little glide after the finger lifts

	func _input(ev: InputEvent) -> void:
		if not is_instance_valid(sc) or not sc.is_visible_in_tree():
			return
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				down = sc.get_global_rect().has_point(ev.position)
				# A press on the scroll bar itself is the bar's job.
				var bar := sc.get_v_scroll_bar()
				if bar.is_visible_in_tree() and bar.get_global_rect().grow(6).has_point(ev.position):
					down = false
				dragging = false
				start = ev.position
				last_y = ev.position.y
				speed = 0.0
			else:
				down = false
				dragging = false
		elif ev is InputEventMouseMotion and down:
			if not dragging and absf(ev.position.y - start.y) > DRAG_START:
				dragging = true
				sc.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN) # cancels the press below
			if dragging:
				var dy: float = ev.position.y - last_y
				sc.scroll_vertical -= int(dy)
				speed = -dy / maxf(get_process_delta_time(), 0.001)
				sc.get_viewport().set_input_as_handled()
			last_y = ev.position.y

	func _process(delta: float) -> void:
		if down or absf(speed) < 30.0 or not is_instance_valid(sc):
			speed = 0.0 if not down else speed
			return
		sc.scroll_vertical += int(speed * delta)
		speed = move_toward(speed, 0.0, 2600.0 * delta)
