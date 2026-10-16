extends Node3D
## One of the people in a town (see folk.gd for who they are). Walks about
## near their place of work, stops to work or look about, turns to face you
## when you talk, and shows how the talk is going: talking with their hands,
## pointing, cowering, or walking off.

const Rig3D := preload("res://scripts/rig3d.gd")

var person: Dictionary
var home := Vector3.ZERO # where they work
var roam := 5.0
var obstacles: Array = [] # Rect2s (x, z) they won't walk into
var rig
var talking := false
var mood := "" # "talk", "point", "fear" while talking
var leaving := false
var _goal := Vector3.ZERO
var _wait := 0.0
var _speed := 1.1
var _face := Vector3.FORWARD
var _working := false
var _label: Label3D


func _ready() -> void:
	rig = Rig3D.new()
	rig.kind = "civilian"
	rig.gear = {"head": person.get("hat", ""), "torso": "tunic", "primary": "", "secondary": ""}
	rig.cloth = person.get("shirt", Color(0.5, 0.4, 0.3))
	var h: float = rig.cloth.h
	rig.trousers = Color.from_hsv(fposmod(h + 0.5, 1.0), 0.25, 0.3)
	rig.female = person.get("sex", "m") == "f"
	rig.dwarf = person.get("faction", "") == "dwarves"
	add_child(rig)
	if rig.dwarf:
		rig.scale = Vector3(1.12, 0.8, 1.12)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.2 if not rig.dwarf else 1.8, 0)
	_label.font_size = 40
	_label.outline_size = 8
	_label.modulate = Color(1, 0.92, 0.7)
	_label.visible = false
	add_child(_label)
	_speed = randf_range(0.8, 1.3)
	_goal = position
	_wait = randf_range(0.0, 4.0)
	_face = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()


func show_label(text: String) -> void:
	_label.text = text
	_label.visible = text != ""


func face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		_face = d.normalized()


func _process(delta: float) -> void:
	if rig == null:
		return
	rig.anim_time += delta
	var v := Vector3.ZERO
	if talking:
		rig.anim = mood if mood != "" else "idle"
	elif leaving:
		var to := _goal - position
		to.y = 0.0
		if to.length() < 0.5:
			visible = false
			set_process(false)
			return
		v = to.normalized() * 2.2
		_face = v.normalized()
		rig.anim = "walk"
	else:
		_wait -= delta
		var to := _goal - position
		to.y = 0.0
		if to.length() > 0.3 and _wait <= 0.0:
			v = to.normalized() * _speed
			_face = v.normalized()
			rig.anim = "walk"
			_working = false
		else:
			rig.anim = "work" if _working else "idle"
			if _wait <= 0.0:
				_pick_goal()
	position += v * delta
	rig.move_speed = v.length()
	rig.facing = rig.facing.slerp(_face, minf(1.0, delta * 6.0)).normalized() if rig.facing.length() > 0.1 else _face


func _pick_goal() -> void:
	_wait = randf_range(2.5, 8.0)
	_working = randf() < 0.35
	for k in 6:
		var g := home + Vector3(randf_range(-roam, roam), 0, randf_range(-roam, roam))
		if not _blocked(g):
			_goal = g
			return


func _blocked(p: Vector3) -> bool:
	for r in obstacles:
		if (r as Rect2).grow(0.6).has_point(Vector2(p.x, p.z)):
			return true
	return false


## Walk away (the talk ended badly, or they joined and go to your men).
func walk_off(to: Vector3) -> void:
	talking = false
	leaving = true
	_goal = to
