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
