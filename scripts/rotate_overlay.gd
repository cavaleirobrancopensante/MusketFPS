extends CanvasLayer
## Registered as the `RotateOverlay` autoload: while the window is taller
## than it is wide (a phone held upright, in the browser), it covers the game
## and asks you to turn the phone sideways. The game is laid out for
## landscape. Drawn in the game itself, above every scene, so it works in
## any browser.

const UI := preload("res://scripts/ui.gd")

var _cover: Control
var _was := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = _Cover.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.visible = false
	add_child(_cover)


func _process(_delta: float) -> void:
	var s := DisplayServer.window_get_size()
	var portrait := s.y > s.x * 1.05
	if portrait != _was:
		_was = portrait
		_cover.visible = portrait
	if portrait:
		_cover.queue_redraw() # (the phone turns)


class _Cover extends Control:
	func _gui_input(e: InputEvent) -> void:
		accept_event() # (nothing reaches the game underneath)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UI.NIGHT)
		var c := size * 0.5
		var u := minf(size.x, size.y) / 10.0
		# A phone turning from upright to sideways, and back.
		var k := fmod(Time.get_ticks_msec() / 2400.0, 1.0)
		var turn := smoothstep(0.2, 0.55, k) * (1.0 - smoothstep(0.85, 1.0, k))
		var at := c + Vector2(0, -u * 1.6)
		draw_set_transform(at, -turn * PI * 0.5, Vector2.ONE)
		var phone := Rect2(Vector2(-u * 0.95, -u * 1.6), Vector2(u * 1.9, u * 3.2))
		draw_rect(phone, UI.BRASS, false, maxf(3.0, u * 0.12))
		draw_rect(Rect2(Vector2(-u * 0.25, u * 1.25), Vector2(u * 0.5, u * 0.1)), UI.BRASS)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var f := UI.display_font()
		var t := Lang.t("Turn your phone sideways")
		var fs := int(u * 0.62)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > size.x * 0.9:
			fs = int(fs * size.x * 0.9 / tw)
			tw = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - tw * 0.5, c.y + u * 1.6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.BRASS)
		var b := UI.font("alegreya_sans_400")
		var t2 := Lang.t("Musket FPS is played in landscape.")
		var fs2 := int(u * 0.4)
		var tw2 := b.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		if tw2 > size.x * 0.9:
			fs2 = int(fs2 * size.x * 0.9 / tw2)
			tw2 = b.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(b, Vector2(c.x - tw2 * 0.5, c.y + u * 2.4), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UI.PIPECLAY)
