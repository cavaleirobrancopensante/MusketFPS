extends Control
## The wagon, drawn: its bed seen through the canvas, cut into slots (one
## slot is one unit of the wagon's space, Company.WAGON_SPACE), and every
## store and spare piece of kit in it taking up the slots its bulk needs.
## The water barrels hang on its side, showing how full they are. Tap a
## stack to pick it (`picked` with its id; "" for none).
##
## Used by the logistics popup (logistics_popup.gd) on the map, in camp and
## on the Company screen.

signal picked(id: String)

const COLS := 12
const GOLD := Color("d4ad55")
const DIM := Color("9aa3b8")
const RED := Color(0.95, 0.42, 0.35)
const WOOD := Color(0.42, 0.28, 0.16)
const WOOD_D := Color(0.27, 0.18, 0.1)
const CLOTH := Color(0.86, 0.82, 0.7)

## What each kind of thing looks like in the wagon: [shape, colour].
const LOOKS := {
	"water": ["barrel", Color(0.35, 0.55, 0.8)], "rum": ["barrel", Color(0.6, 0.35, 0.2)],
	"rations": ["sack", Color(0.78, 0.68, 0.45)], "grain": ["sack", Color(0.85, 0.75, 0.4)],
	"meat": ["sack", Color(0.72, 0.3, 0.28)], "saltpetre": ["sack", Color(0.9, 0.9, 0.88)],
	"sulphur": ["sack", Color(0.9, 0.82, 0.25)], "charcoal": ["sack", Color(0.2, 0.2, 0.22)],
	"ore": ["sack", Color(0.5, 0.5, 0.55)], "wood": ["logs", Color(0.55, 0.4, 0.25)],
	"ammo": ["crate", Color(0.55, 0.42, 0.28)], "powder": ["keg", Color(0.3, 0.3, 0.32)],
	"lead": ["ingot", Color(0.55, 0.57, 0.62)], "wood_shot": ["crate", Color(0.6, 0.48, 0.3)],
	"arrows": ["bundle", Color(0.6, 0.5, 0.3)], "bolts": ["bundle", Color(0.45, 0.4, 0.35)],
}

var stacks: Array = [] # [id, count, slots, shape, colour]
var selected := ""
var _cells: Array = [] # cell index -> stack index (-1 empty)
var _grid := Rect2()
var _cell := 40.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(600, 380)


## Rebuild the stacks from the wagon's stores.
func refresh() -> void:
	stacks.clear()
	var s: Dictionary = Company.stores
	for k in ["water", "rum", "rations", "meat", "grain", "ammo", "powder", "lead", "arrows", "bolts",
			"saltpetre", "sulphur", "charcoal", "ore", "wood"]:
		var n := int(s.get(k, 0))
		if n > 0:
			_add(k, n)
	var ids: Array = (s["items"] as Dictionary).keys()
	ids.sort_custom(func(a, b): return String(Company.ITEMS.get(a, {}).get("slot", "")) < String(Company.ITEMS.get(b, {}).get("slot", "")))
	for id in ids:
		if int(s["items"][id]) > 0:
			_add(String(id), int(s["items"][id]))
	if selected != "" and not stacks.any(func(st): return st[0] == selected):
		selected = ""
	queue_redraw()


func _add(id: String, n: int) -> void:
	var sp: float = Company.load_of(id, n)[1]
	var slots := maxi(1, int(ceil(sp - 0.001)))
	var look: Array = LOOKS.get(id, _item_look(id))
	stacks.append([id, n, slots, look[0], look[1]])


static func _item_look(id: String) -> Array:
	var it: Dictionary = Company.ITEMS.get(id, {})
	match String(it.get("slot", "")):
		"primary", "secondary":
			return ["arms", Color(0.62, 0.6, 0.58)]
		"sword", "pistol":
			return ["blade", Color(0.75, 0.75, 0.78)]
		"head":
			return ["helm", Color(0.55, 0.56, 0.6)]
		"torso":
			return ["coat", Color(0.5, 0.42, 0.55)]
	if id in Company.TOOLS or id.ends_with("_broken"):
		return ["tool", Color(0.6, 0.5, 0.38)]
	return ["crate", Color(0.5, 0.45, 0.4)]


func _draw() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	var cap := int(ceil(Company.wagon_space()))
	var used := 0
	for st in stacks:
		used += int(st[2])
	var rows := int(ceil(float(maxi(cap, used)) / COLS))
	# The wagon from the side: the shaft, the bed, two big wheels, the canvas
	# cover over hoops, cut away to show what's inside.
	var bed_l := 70.0
	var bed_r := w - 20.0
	var wheel_r := minf(48.0, h * 0.13)
	var bed_y := h - wheel_r * 1.6 # the top of the bed's side board
	var top := 34.0
	_cell = minf((bed_r - bed_l - 16.0) / COLS, (bed_y - top - 10.0) / maxi(rows, 1))
	var gw := _cell * COLS
	var gx := bed_l + (bed_r - bed_l - gw) * 0.5
	var gh := _cell * rows
	var gy := bed_y - gh - 4.0
	_grid = Rect2(gx, gy, gw, gh)
	# The cover: a pale arch behind it all.
	var arch := PackedVector2Array()
	var ac := Vector2((bed_l + bed_r) * 0.5, bed_y)
	var rx := (bed_r - bed_l) * 0.5 + 6.0
	var ry := bed_y - gy + 26.0
	for k in 25:
		var a := PI + PI * float(k) / 24.0
		arch.append(ac + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(arch, Color(CLOTH, 0.18))
	draw_polyline(arch, Color(CLOTH, 0.7), 3.0, true)
	for k in 5: # the hoops
		var x := lerpf(bed_l + 12.0, bed_r - 12.0, float(k) / 4.0)
		var t := (x - ac.x) / rx
		var yy := ac.y - ry * sqrt(maxf(0.0, 1.0 - t * t))
		draw_line(Vector2(x, yy), Vector2(x, bed_y), Color(WOOD, 0.55), 3.0)
	# The bed: the floor under the slots.
	draw_rect(Rect2(gx - 6.0, gy - 6.0, gw + 12.0, gh + 12.0), Color(0.18, 0.13, 0.08, 0.85))
	# The slots.
	_cells.clear()
	_cells.resize(rows * COLS)
	_cells.fill(-1)
	var ci := 0
	for si in stacks.size():
		var st: Array = stacks[si]
		for k in int(st[2]):
			if ci < _cells.size():
				_cells[ci] = si
			ci += 1
	for i in rows * COLS:
		var r := _cell_rect(i).grow(-2.0)
		var si: int = _cells[i]
		if si < 0:
			draw_rect(r, Color(1, 1, 1, 0.05) if i < cap else Color(0, 0, 0, 0))
			if i < cap:
				draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
			continue
		var st: Array = stacks[si]
		var col: Color = st[4]
		var over := i >= cap
		draw_rect(r, col.darkened(0.55) if not over else Color(0.5, 0.12, 0.1))
		_icon(String(st[3]), r.grow(-3.0), col)
		var sel := String(st[0]) == selected
		draw_rect(r, GOLD if sel else Color(1, 1, 1, 0.18), false, 3.0 if sel else 1.0)
	# Each stack's count on its first slot.
	ci = 0
	for st in stacks:
		var r0 := _cell_rect(ci)
		var txt := "%d" % int(st[1])
		draw_string_outline(font, r0.position + Vector2(4, r0.size.y - 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
		draw_string(font, r0.position + Vector2(4, r0.size.y - 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		ci += int(st[2])
	# The side board and the wheels.
	draw_rect(Rect2(bed_l - 8.0, bed_y, bed_r - bed_l + 16.0, wheel_r * 0.45), WOOD)
	draw_line(Vector2(bed_l - 8.0, bed_y + wheel_r * 0.22), Vector2(bed_r + 8.0, bed_y + wheel_r * 0.22), WOOD_D, 2.0)
	draw_line(Vector2(bed_l - 8.0, bed_y + wheel_r * 0.3), Vector2(8.0, bed_y + wheel_r * 0.9), WOOD, 6.0) # the shaft
	for wx in [bed_l + wheel_r * 1.3, bed_r - wheel_r * 1.3]:
		var c := Vector2(wx, bed_y + wheel_r * 0.6)
		draw_circle(c, wheel_r, WOOD_D)
		draw_circle(c, wheel_r * 0.82, Color(0.12, 0.1, 0.09))
		for k in 8:
			var a := TAU * k / 8.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * wheel_r * 0.85, WOOD, 3.0)
		draw_circle(c, wheel_r * 0.16, WOOD)
	# The water barrels on the side: how full, and whether it's foul.
	var bx := bed_l + wheel_r * 2.6
	var bw := 30.0
	var bh := wheel_r * 0.9
	var full := clampf(float(Company.stores.get("water", 0)) / Company.WATER_CART, 0.0, 1.0)
	var foul := bool(Company.stores.get("foul", false))
	for k in 3:
		var br := Rect2(bx + k * (bw + 8.0), bed_y + 2.0, bw, bh)
		draw_rect(br, WOOD_D)
		var lv := br.size.y * full
		draw_rect(Rect2(br.position.x + 3, br.end.y - lv, br.size.x - 6, lv), Color(0.42, 0.36, 0.2) if foul else Color(0.35, 0.6, 0.9))
		draw_line(Vector2(br.position.x, br.position.y + bh * 0.3), Vector2(br.end.x, br.position.y + bh * 0.3), Color(0.6, 0.6, 0.62), 2.0)
		draw_line(Vector2(br.position.x, br.position.y + bh * 0.7), Vector2(br.end.x, br.position.y + bh * 0.7), Color(0.6, 0.6, 0.62), 2.0)
	var wl := Lang.t("water: %d%%%s") % [int(full * 100.0), Lang.t(", foul") if foul else ""]
	draw_string(font, Vector2(bx, bed_y + bh + 20.0), wl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, RED if foul or full < 0.25 else DIM)
	# How full it is: weight and space.
	var load := Company.wagon_load()
	_bar(Vector2(10, 6), w * 0.45, float(load[0]) / Company.wagon_kg(), Lang.t("weight %d / %d kg") % [int(load[0]), int(Company.wagon_kg())], font)
	_bar(Vector2(w * 0.52, 6), w * 0.45, float(load[1]) / Company.wagon_space(), Lang.t("space %d / %d slots") % [used, cap], font)


func _bar(at: Vector2, bw: float, f: float, text: String, font: Font) -> void:
	draw_rect(Rect2(at, Vector2(bw, 20)), Color(0, 0, 0, 0.45))
	var col := Color(0.45, 0.75, 0.45) if f < 0.75 else (Color(0.95, 0.75, 0.35) if f <= 1.0 else RED)
	draw_rect(Rect2(at, Vector2(bw * clampf(f, 0.0, 1.0), 20)), col)
	draw_string(font, at + Vector2(6, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _cell_rect(i: int) -> Rect2:
	return Rect2(_grid.position + Vector2((i % COLS) * _cell, (i / COLS) * _cell), Vector2(_cell, _cell))


## A little picture of what's in the slot.
func _icon(shape: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := r.size.x
	match shape:
		"barrel":
			draw_rect(Rect2(c.x - s * 0.32, r.position.y + s * 0.08, s * 0.64, s * 0.84), WOOD)
			draw_rect(Rect2(c.x - s * 0.26, r.position.y + s * 0.12, s * 0.52, s * 0.18), col)
			for f in [0.3, 0.7]:
				draw_line(Vector2(c.x - s * 0.33, r.position.y + s * f), Vector2(c.x + s * 0.33, r.position.y + s * f), Color(0.65, 0.65, 0.68), 2.0)
		"keg":
			draw_rect(Rect2(c.x - s * 0.28, r.position.y + s * 0.2, s * 0.56, s * 0.66), col)
			draw_line(Vector2(c.x - s * 0.28, c.y), Vector2(c.x + s * 0.28, c.y), Color(0.7, 0.6, 0.3), 2.0)
		"sack":
			var pts := PackedVector2Array([Vector2(c.x - s * 0.18, r.position.y + s * 0.18), Vector2(c.x + s * 0.18, r.position.y + s * 0.18),
				Vector2(c.x + s * 0.36, r.end.y - s * 0.12), Vector2(c.x - s * 0.36, r.end.y - s * 0.12)])
			draw_colored_polygon(pts, col)
			draw_line(Vector2(c.x - s * 0.14, r.position.y + s * 0.26), Vector2(c.x + s * 0.14, r.position.y + s * 0.26), WOOD_D, 2.0)
		"crate":
			var cr := Rect2(c.x - s * 0.36, c.y - s * 0.3, s * 0.72, s * 0.6)
			draw_rect(cr, col)
			draw_rect(cr, WOOD_D, false, 2.0)
			draw_line(cr.position, cr.end, WOOD_D, 2.0)
		"ingot":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.36, c.y + s * 0.2), Vector2(c.x + s * 0.36, c.y + s * 0.2),
				Vector2(c.x + s * 0.24, c.y - s * 0.12), Vector2(c.x - s * 0.24, c.y - s * 0.12)]), col)
		"bundle", "logs":
			for k in 4:
				var x := c.x - s * 0.24 + k * s * 0.16
				draw_line(Vector2(x, r.position.y + s * 0.12), Vector2(x + s * 0.06, r.end.y - s * 0.12), col, 3.0 if shape == "bundle" else 6.0)
		"arms":
			draw_line(Vector2(r.position.x + s * 0.12, r.end.y - s * 0.15), Vector2(r.end.x - s * 0.12, r.position.y + s * 0.15), WOOD, 5.0)
			draw_line(Vector2(c.x, c.y), Vector2(r.end.x - s * 0.12, r.position.y + s * 0.15), col, 3.0)
		"blade":
			draw_line(Vector2(r.position.x + s * 0.2, r.end.y - s * 0.2), Vector2(r.end.x - s * 0.15, r.position.y + s * 0.15), col, 3.0)
			draw_line(Vector2(r.position.x + s * 0.18, c.y + s * 0.08), Vector2(c.x - s * 0.06, r.end.y - s * 0.12), GOLD, 3.0)
		"helm":
			draw_circle(Vector2(c.x, c.y + s * 0.1), s * 0.3, col)
			draw_rect(Rect2(c.x - s * 0.38, c.y + s * 0.1, s * 0.76, s * 0.12), col.darkened(0.3))
		"coat":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.16, r.position.y + s * 0.15), Vector2(c.x + s * 0.16, r.position.y + s * 0.15),
				Vector2(c.x + s * 0.38, c.y), Vector2(c.x + s * 0.26, r.end.y - s * 0.1), Vector2(c.x - s * 0.26, r.end.y - s * 0.1), Vector2(c.x - s * 0.38, c.y)]), col)
		"tool":
			draw_line(Vector2(c.x, r.position.y + s * 0.2), Vector2(c.x, r.end.y - s * 0.12), WOOD, 4.0)
			draw_line(Vector2(c.x - s * 0.28, r.position.y + s * 0.22), Vector2(c.x + s * 0.28, r.position.y + s * 0.22), col, 5.0)
		_:
			draw_rect(r.grow(-s * 0.2), col)


func _gui_input(e: InputEvent) -> void:
	var at := Vector2.INF
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		at = e.position
	elif e is InputEventScreenTouch and e.pressed:
		at = e.position
	if at == Vector2.INF:
		return
	accept_event()
	if not _grid.has_point(at):
		return
	var i := int((at.y - _grid.position.y) / _cell) * COLS + int((at.x - _grid.position.x) / _cell)
	if i < 0 or i >= _cells.size() or int(_cells[i]) < 0:
		selected = ""
	else:
		selected = String(stacks[int(_cells[i])][0])
	queue_redraw()
	picked.emit(selected)
