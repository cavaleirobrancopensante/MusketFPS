extends Button
const UI := preload("res://scripts/ui.gd")
## A language's flag on the main menu (drawn, no images): the United States
## for English, Brazil for Portuguese, Spain for Spanish. Pressing it is
## handled by the menu; the chosen one is framed in brass.

var lang := "en"
var chosen := false


func _init(l: String = "en") -> void:
	lang = l
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(96, 64)
	tooltip_text = Lang.NAMES.get(l, l)


func _draw() -> void:
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	if chosen:
		draw_rect(r.grow(5), UI.BRASS)
	else:
		draw_rect(r.grow(2), Color(0, 0, 0, 0.6))
	match lang:
		"en": _usa(r)
		"pt_BR": _brazil(r)
		"es": _spain(r)
	if not chosen:
		draw_rect(r, Color(0, 0, 0, 0.35))


func _usa(r: Rect2) -> void:
	var red := Color("b22234")
	var h := r.size.y / 13.0
	draw_rect(r, Color.WHITE)
	for i in range(0, 13, 2):
		draw_rect(Rect2(r.position + Vector2(0, i * h), Vector2(r.size.x, h)), red)
	var canton := Rect2(r.position, Vector2(r.size.x * 0.4, h * 7))
	draw_rect(canton, Color("3c3b6e"))
	for row in 9:
		var n := 6 if row % 2 == 0 else 5
		for c in n:
			var x := canton.size.x * ((c + (0.5 if row % 2 == 0 else 1.0)) / 6.0)
			var y := canton.size.y * ((row + 0.5) / 9.0)
			draw_circle(canton.position + Vector2(x, y), max(0.8, canton.size.y / 30.0), Color.WHITE)


func _brazil(r: Rect2) -> void:
	draw_rect(r, Color("009c3b"))
	var c := r.get_center()
	var dx := r.size.x * 0.42
	var dy := r.size.y * 0.38
	draw_colored_polygon(PackedVector2Array([c + Vector2(-dx, 0), c + Vector2(0, -dy), c + Vector2(dx, 0), c + Vector2(0, dy)]), Color("ffdf00"))
	var rad := r.size.y * 0.24
	draw_circle(c, rad, Color("002776"))
	# The white band across the globe (an arc rising to the right).
	draw_arc(c + Vector2(-rad * 0.3, rad * 1.6), rad * 1.75, -PI * 0.66, -PI * 0.36, 16, Color.WHITE, max(1.5, rad * 0.22))
	for p in [Vector2(-0.4, 0.4), Vector2(0.1, 0.55), Vector2(0.45, 0.3), Vector2(-0.1, 0.25), Vector2(0.3, 0.65)]:
		draw_circle(c + p * rad, max(0.7, rad * 0.06), Color.WHITE)


func _spain(r: Rect2) -> void:
	var red := Color("aa151b")
	var gold := Color("f1bf00")
	draw_rect(r, red)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.25), Vector2(r.size.x, r.size.y * 0.5)), gold)
	# The arms, simplified: a small shield between two pillars.
	var c := r.position + Vector2(r.size.x * 0.33, r.size.y * 0.5)
	var s := r.size.y * 0.16
	for side in [-1.0, 1.0]:
		draw_rect(Rect2(c + Vector2(side * s * 1.25 - s * 0.15, -s), Vector2(s * 0.3, s * 2.0)), Color("c0c0c0"))
	draw_rect(Rect2(c - Vector2(s * 0.75, s), Vector2(s * 1.5, s * 1.5)), red)
	draw_rect(Rect2(c - Vector2(s * 0.75, s), Vector2(s * 0.75, s * 0.75)), Color("c8102e"))
	draw_circle(c + Vector2(0, s * 0.55), s * 0.75, red)
	draw_rect(Rect2(c - Vector2(s * 0.6, s * 1.35), Vector2(s * 1.2, s * 0.35)), gold.darkened(0.2))
