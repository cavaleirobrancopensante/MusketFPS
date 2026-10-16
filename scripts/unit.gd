extends CharacterBody3D
## Shared base for the soldiers and lizardmen: their look, a hit capsule for
## musket rays, animation state, damage and death.
##
## The look is either a Doom-style billboard sprite with front/side/back
## frames (2D mode) or a low-poly 3D model with procedural animation (3D mode),
## chosen in the main menu. AI and combat never touch the look directly: they
## just set `facing` and an animation name, and the look follows.
##
## Nothing here is drawn on its own: sprites are instances in the Batcher's
## atlas batch (one draw call per kind), and 3D rigs write their parts into
## the Batcher's shared batches. In 3D, a unit far from the camera switches
## to its sprite (a cheap stand-in) and back as you approach.
##
## Units don't use physics to walk (collision_mask = 0); they steer directly
## on the flat field, which is far cheaper on a phone than real pathfinding.

const Rig3D := preload("res://scripts/rig3d.gd")

## Frames per second for looping animations (others hold a single frame).
const ANIM_FPS := {"walk": 8.0, "reload": 2.5}
## 3D: beyond this distance the unit is drawn as a sprite (with hysteresis).
const STANDIN_FAR := 40.0
const STANDIN_NEAR := 35.0

var battle
var frames: Dictionary # sprite atlas info from the Batcher: cells + counts
var rig_kind := "soldier" # also the sprite kind
var hp := 100.0
var alive := true
var rig # Rig3D in 3D mode
var visual: Node3D # what squash/stretch and corpse tweens act on
var sprite_node: Node3D # transform for the sprite (position, scale, corpse pose)
var sprite_on := false # drawn as a sprite this frame

var facing := Vector3.FORWARD # where the unit's body points (flat)
var anim := "idle"
var anim_time := 0.0
var tempo := 1.0 # personal animation speed (a brisk or a slow man)
var _base_anim := "idle"
var _oneshot_left := 0.0
var _tint := Color.WHITE
var _flash_left := 0.0
var _sprite_h := 1.8
var _cell := Vector2i.ZERO
var _flip := false
var _lying := false
var _sprite_col := Color.WHITE
var _visual_scale := Vector3.ONE


func _setup_body(layer: int, radius: float, height: float, sprite_height_m: float) -> void:
	collision_layer = layer
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	shape.shape = cap
	shape.position.y = height * 0.5
	add_child(shape)

	# The sprite always exists (2D look, or the far stand-in in 3D).
	_sprite_h = sprite_height_m
	sprite_node = Node3D.new()
	add_child(sprite_node)
	battle.batcher.add_sprite(rig_kind, self)
	_update_sprite_frame()

	if Settings.use_3d:
		rig = Rig3D.new()
		rig.kind = rig_kind
		add_child(rig)
		visual = rig
	else:
		visual = sprite_node
		sprite_on = true
	_visual_scale = visual.scale


func _exit_tree() -> void:
	if battle != null and battle.batcher != null:
		battle.batcher.remove_sprite(rig_kind, self)


## Units never collide with anything (they steer around each other), so
## skip the physics engine and just move: much cheaper with hundreds of them.
func _move(delta: float) -> void:
	position += Vector3(velocity.x, 0.0, velocity.z) * delta


func is_valid_target(t: Node3D) -> bool:
	return t != null and is_instance_valid(t) and t.get("alive") == true


# ---------------------------------------------------------------- animation

## The animation the unit is in by default (walk, aim, reload...).
func set_base_anim(name: String) -> void:
	_base_anim = name
	if _oneshot_left <= 0.0 and anim != name:
		anim = name
		anim_time = randf() * 0.5 # so loops never march in lockstep


## A short animation that plays once (fire, thrust, strike), then returns.
func play_oneshot(name: String, seconds: float) -> void:
	anim = name
	anim_time = 0.0
	_oneshot_left = seconds / tempo


func face_toward(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		facing = dir.normalized()


## Body tint: used for the lizardmen's orange wind-up glow.
func set_tint(c: Color) -> void:
	_tint = c


func _process(delta: float) -> void:
	if rig != null:
		_update_standin()
	if not alive:
		return
	anim_time += delta * tempo
	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		if _oneshot_left <= 0.0:
			anim = _base_anim
			anim_time = 0.0
	_flash_left -= delta
	var col := _tint
	if _flash_left > 0.0:
		col = Color(1.0, 0.35, 0.35)
	if rig != null and rig.visible:
		rig.facing = facing
		rig.anim = anim
		rig.anim_time = anim_time
		rig.move_speed = Vector2(velocity.x, velocity.z).length()
		rig.tint = col
	if sprite_on:
		_sprite_col = col
		_update_sprite_frame()


## 3D only: far from the camera, swap the model for its sprite.
func _update_standin() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	if rig.visible and d > STANDIN_FAR:
		rig.visible = false
		sprite_on = true
		_update_sprite_frame()
	elif not rig.visible and d < STANDIN_NEAR:
		rig.visible = true
		rig.refresh()
		sprite_on = false


## Doom-style rotation: pick the front, side or back frames by comparing the
## way the unit faces with the direction to the camera.
func _update_sprite_frame() -> void:
	if _lying:
		return
	var cam := get_viewport().get_camera_3d()
	var view := "front"
	if cam != null:
		var to_cam := cam.global_position - global_position
		to_cam.y = 0.0
		to_cam = to_cam.normalized()
		var d := facing.dot(to_cam)
		if d > 0.7:
			view = "front"
		elif d < -0.7:
			view = "back"
		else:
			view = "side"
			# Side frames face screen-right; mirror when facing screen-left.
			_flip = facing.dot(cam.global_transform.basis.x) < 0.0
	if view != "side":
		_flip = false
	var per_anim: Dictionary = frames["lookup"][view]
	var arr: Array = per_anim[anim] if per_anim.has(anim) else per_anim["idle"]
	var idx := 0
	if arr.size() > 1:
		idx = int(anim_time * float(ANIM_FPS.get(anim, 6.0))) % arr.size()
	_cell = arr[idx]


## Called by the Batcher: append this unit's sprite instance (20 floats).
func write_sprite(buf: PackedFloat32Array) -> void:
	var t: Transform3D
	var sc := sprite_node.scale
	if _lying:
		t = sprite_node.global_transform * Transform3D(Basis.from_scale(Vector3(_sprite_h, _sprite_h, 1.0)), Vector3.ZERO)
	else:
		t = Transform3D(Basis.from_scale(Vector3(_sprite_h * sc.x, _sprite_h * sc.y, 1.0)), sprite_node.global_position)
	var b := t.basis
	var o := t.origin
	var c := _sprite_col
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z, c.r, c.g, c.b, 1.0,
		float(_cell.x), float(_cell.y), 1.0 if _flip else 0.0, 1.0 if _lying else 0.0])


# ---------------------------------------------------------------- damage

func take_damage(amount: float, _from: Node3D = null) -> void:
	if not alive:
		return
	hp -= amount
	_flash_left = 0.2
	if hp <= 0.0:
		_die()


## Short squash-and-stretch on the visual (strikes, thrusts).
func _punch(squash: Vector3, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", _visual_scale * squash, seconds * 0.3)
	tw.tween_property(visual, "scale", _visual_scale, seconds * 0.7)


## Shrink the corpse away (both looks, whichever is showing).
func _fade_corpse(after: float, seconds: float) -> Tween:
	var tw := create_tween()
	tw.tween_interval(after)
	tw.set_parallel(true)
	tw.tween_property(sprite_node, "scale", Vector3.ONE * 0.01, seconds)
	if rig != null:
		tw.tween_property(rig, "scale", Vector3.ONE * 0.01, seconds)
	tw.set_parallel(false)
	return tw


func _die() -> void:
	alive = false
	collision_layer = 0
	velocity = Vector3.ZERO
	if rig != null:
		rig.die()
	# Sprite corpse: the side frame laid flat on the ground.
	var cells: Dictionary = frames["cells"]
	_cell = cells["side_idle_0"]
	_flip = false
	_lying = true
	sprite_node.position = Vector3(0, 0.05, 0)
	sprite_node.rotation = Vector3(-PI * 0.5, 0, 0)
	_sprite_col = Color(0.55, 0.55, 0.55)
	rotation.y = randf() * TAU
	_on_died()


func _on_died() -> void:
	pass
