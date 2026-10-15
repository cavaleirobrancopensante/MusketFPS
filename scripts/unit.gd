extends CharacterBody3D
## Shared base for the soldiers and lizardmen: their look (a "visual"), a hit
## capsule for musket rays, animation state, damage and death.
##
## The visual is either a Doom-style billboard sprite with front/side/back
## frames (2D mode) or a low-poly 3D model with procedural animation (3D mode),
## chosen in the main menu. AI and combat never touch the visual directly: they
## just set `facing` and an animation name, and the visual follows.
##
## Units don't use physics to walk (collision_mask = 0); they steer directly
## on the flat field, which is far cheaper on a phone than real pathfinding.

const Rig3D := preload("res://scripts/rig3d.gd")

## Frames per second for looping animations (others hold a single frame).
const ANIM_FPS := {"walk": 8.0, "reload": 2.5}

var battle
var frames: Dictionary # 2D: from SpriteFactory; empty in 3D mode
var rig_kind := "soldier" # 3D: which model to build
var hp := 100.0
var alive := true
var sprite: Sprite3D
var rig # Rig3D in 3D mode
var visual: Node3D # whichever of the two is in use

var facing := Vector3.FORWARD # where the unit's body points (flat)
var anim := "idle"
var anim_time := 0.0
var _base_anim := "idle"
var _oneshot_left := 0.0
var _tex_key := ""
var _tint := Color.WHITE
var _flash_left := 0.0


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

	if Settings.use_3d:
		rig = Rig3D.new()
		rig.kind = rig_kind
		add_child(rig)
		visual = rig
	else:
		sprite = Sprite3D.new()
		var first: Texture2D = frames["front_idle_0"]
		sprite.texture = first
		var tex_h := float(first.get_height())
		sprite.pixel_size = sprite_height_m / tex_h
		sprite.offset = Vector2(0, tex_h * 0.5) # stand on the ground, not float at the centre
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		visual = sprite


func is_valid_target(t: Node3D) -> bool:
	return t != null and is_instance_valid(t) and t.get("alive") == true


# ---------------------------------------------------------------- animation

## The animation the unit is in by default (walk, aim, reload...).
func set_base_anim(name: String) -> void:
	_base_anim = name
	if _oneshot_left <= 0.0 and anim != name:
		anim = name
		anim_time = 0.0


## A short animation that plays once (fire, thrust, strike), then returns.
func play_oneshot(name: String, seconds: float) -> void:
	anim = name
	anim_time = 0.0
	_oneshot_left = seconds


func face_toward(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		facing = dir.normalized()


## Body tint: used for the lizardmen's orange wind-up glow.
func set_tint(c: Color) -> void:
	_tint = c


func _process(delta: float) -> void:
	if not alive:
		return
	anim_time += delta
	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		if _oneshot_left <= 0.0:
			anim = _base_anim
			anim_time = 0.0
	_flash_left -= delta
	var col := _tint
	if _flash_left > 0.0:
		col = Color(1.0, 0.35, 0.35)
	if rig != null:
		rig.facing = facing
		rig.anim = anim
		rig.anim_time = anim_time
		rig.move_speed = Vector2(velocity.x, velocity.z).length()
		rig.tint = col
	else:
		sprite.modulate = col
		_update_sprite_frame()


## Doom-style rotation: pick the front, side or back frames by comparing the
## way the unit faces with the direction to the camera.
func _update_sprite_frame() -> void:
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
			sprite.flip_h = facing.dot(cam.global_transform.basis.x) < 0.0
	var counts: Dictionary = frames["counts"]
	var n: int = counts.get(anim, 1)
	var idx := 0
	if n > 1:
		idx = int(anim_time * float(ANIM_FPS.get(anim, 6.0))) % n
	var key := "%s_%s_%d" % [view, anim, idx]
	if key != _tex_key and frames.has(key):
		_tex_key = key
		sprite.texture = frames[key]


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
	tw.tween_property(visual, "scale", squash, seconds * 0.3)
	tw.tween_property(visual, "scale", Vector3.ONE, seconds * 0.7)


func _die() -> void:
	alive = false
	collision_layer = 0
	velocity = Vector3.ZERO
	if rig != null:
		rig.die()
	else:
		# Lay the side frame flat on the ground as a corpse.
		sprite.texture = frames["side_idle_0"]
		sprite.flip_h = false
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.position = Vector3(0, 0.05, 0)
		sprite.rotation = Vector3(-PI * 0.5, 0, 0)
		sprite.modulate = Color(0.55, 0.55, 0.55)
	rotation.y = randf() * TAU
	_on_died()


func _on_died() -> void:
	pass
