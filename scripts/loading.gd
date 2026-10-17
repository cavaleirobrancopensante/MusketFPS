extends CanvasLayer
## The loading screen, registered as the `Loading` autoload.
##
##   Loading.go("res://scenes/map.tscn", "To the map")
##
## covers the screen with a title, a bar and what's being done, waits a
## frame so it's actually drawn, then switches scene. The heavy scenes (the
## map, battles, the shipwreck) build themselves in stages and report each
## one from their _ready:
##
##   await Loading.step(0.4, "Raising the hills")
##
## which moves the bar and gives the screen a frame to draw it before the
## next stage freezes things again. The fractions are set from how long each
## stage really takes, so the bar fills at the pace of the wait. When the
## scene is done it calls Loading.done() and the cover fades away.
## While the cover is up the new scene is paused (process_mode disabled), so
## nothing runs half-built.
const UI := preload("res://scripts/ui.gd")

const BG := UI.NIGHT
const GOLD := Color("d4ad55") # brass (ui.gd)
const DIM := Color("9aa3b8") # slate (ui.gd)
const HINTS := [
	"Keep the powder dry and the rations fair: hungry men remember who ate.",
	"A man who runs from the wagon is ashamed of it; a man who fought for it is proud.",
	"Foul water with a tot of rum is grog. Plain, it makes men sick.",
	"Two men stand watch at night. Good eyes see the lizards before they're in the camp.",
	"Looters stop to eat. Kill them quickly and you lose less.",
	"Pikes kneel in front; the muskets fire over them.",
	"Your Logistics decides what the wagon can carry home from the field.",
	"Tap PLAN before a fight you saw coming to form the company your way.",
	"The dead's muskets go back to the wagon: arm the next man with them.",
	"Scouts see further than you do, and sometimes don't come back.",
]

var active := false
var _cover: Control
var _title: Label
var _what: Label
var _hint: Label
var _bar: ProgressBar
var _t0 := 0
var _last_t := 0
var _log := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log = "--loadtimes" in OS.get_cmdline_user_args()
	_cover = Control.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.visible = false
	add_child(_cover)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(760, 0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	_cover.add_child(box)
	_title = _label("", 46, GOLD)
	_title.add_theme_font_override("font", UI.display_font())
	box.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(760, 14)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	var under := UI.box(UI.WOOL_DARK, 0, 4, 0.3)
	var fill := UI.box(UI.BRASS, 0, 4, 0.0)
	_bar.add_theme_stylebox_override("background", under)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	_what = _label("", 20, Color.WHITE)
	box.add_child(_what)
	_hint = _label("", 18, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Cover the screen, then change to `path`. The new scene reports its own
## progress with step() and finishes with done(); a scene that doesn't is
## uncovered as soon as it has been added.
func go(path: String, title := "Loading") -> void:
	_show(title)
	_set_bar(0.04, Lang.t("Opening the page..."))
	await _frame()
	await _frame()
	# Read the scene on a worker thread so the bar can move meanwhile.
	_set_bar(0.05, "Reading...")
	var packed: PackedScene = null
	if ResourceLoader.load_threaded_request(path) == OK:
		var prog := []
		while ResourceLoader.load_threaded_get_status(path, prog) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_set_bar(0.05 + 0.1 * float(prog[0] if prog.size() > 0 else 0.0), "")
			await get_tree().process_frame
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		packed = load(path) as PackedScene
	_mark(Lang.t("load ") + path.get_file())
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene != null and not scene.has_meta("loading_steps"):
		done()


## Change scene: through the loading screen for the heavy ones (the map,
## a battle, the shipwreck), straight away for the light screens.
func change(path: String) -> void:
	var title := ""
	match path.get_file():
		"map.tscn": title = Lang.t("On the march")
		"battle.tscn": title = Lang.t("To arms!")
		"intro.tscn": title = Lang.t("The voyage")
		"town.tscn": title = Lang.t("Through the gate")
	if title == "":
		get_tree().change_scene_to_file(path)
	else:
		go(path, title)


## Put the cover up without changing scene (a long job inside a screen).
func cover(title: String) -> void:
	_show(title)
	await _frame()


## For a scene's _ready: pause it while it builds, so nothing runs half-made.
func begin(scene: Node) -> void:
	if not active:
		return
	scene.set_meta("loading_steps", true)
	scene.process_mode = Node.PROCESS_MODE_DISABLED


## Bar positions for a list of stages from how long each one takes:
## weights [ms, ms, ...] -> where the bar stands as each stage starts,
## running from `start` to 1.
static func plan(weights: Array, start := 0.15) -> Array:
	var total := 0.0
	for w in weights:
		total += float(w)
	var out: Array = []
	var acc := 0.0
	for w in weights:
		out.append(start + (1.0 - start) * acc / maxf(total, 1.0))
		acc += float(w)
	return out


## A stage of the work is done: move the bar to `frac` (0..1), say what's
## next, and let the screen draw it.
func step(frac: float, text: String) -> void:
	if not active:
		return
	_mark(text)
	_set_bar(frac, text)
	await _frame()


## Uncover. `scene` (the one passed to begin) starts running again.
func done(scene: Node = null) -> void:
	if scene != null:
		scene.process_mode = Node.PROCESS_MODE_INHERIT
	if not active:
		return
	_set_bar(1.0, "")
	_mark("done")
	if _log:
		print("LOADTIMES total %d ms" % (Time.get_ticks_msec() - _t0))
	active = false
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_property(_cover, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		if not active:
			_cover.visible = false)


func _show(title: String) -> void:
	active = true
	_t0 = Time.get_ticks_msec()
	_last_t = _t0
	_title.text = title
	_hint.text = Lang.t(HINTS[randi() % HINTS.size()])
	_bar.value = 0.0
	_cover.modulate.a = 1.0
	_cover.visible = true


func _set_bar(frac: float, text: String) -> void:
	_bar.value = maxf(_bar.value, clampf(frac, 0.0, 1.0))
	if text != "":
		_what.text = text


## Wait until the cover has really been drawn.
func _frame() -> void:
	# Two frame starts: the one in between has been drawn. (frame_post_draw
	# would be neater, but never comes in a headless run.)
	await get_tree().process_frame
	await get_tree().process_frame


func _mark(what: String) -> void:
	if _log:
		var now := Time.get_ticks_msec()
		print("LOADTIMES %5d ms  (+%4d)  %s" % [now - _t0, now - _last_t, what])
		_last_t = now
