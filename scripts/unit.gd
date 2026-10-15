extends CharacterBody3D
## Shared base for the soldiers and lizardmen: a billboard sprite (always faces
## the camera, like Doom), a hit capsule for musket rays, damage and death.
##
## Units don't use physics to walk (collision_mask = 0); they steer directly
## on the flat field, which is far cheaper on a phone than real pathfinding.

var battle
var sprite_texture: Texture2D
var hp := 100.0
var alive := true
var sprite: Sprite3D
var _bob_phase := randf() * TAU


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

	sprite = Sprite3D.new()
	sprite.texture = sprite_texture
	var tex_h := float(sprite_texture.get_height())
	sprite.pixel_size = sprite_height_m / tex_h
	sprite.offset = Vector2(0, tex_h * 0.5) # stand on the ground, not float at the centre
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(sprite)


func is_valid_target(t: Node3D) -> bool:
	return t != null and is_instance_valid(t) and t.get("alive") == true


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	sprite.modulate = Color(1.0, 0.35, 0.35)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.25)
	if hp <= 0.0:
		_die()


func _bob(amount: float, speed: float) -> void:
	sprite.position.y = absf(sin(Time.get_ticks_msec() * 0.001 * speed + _bob_phase)) * amount


func _die() -> void:
	alive = false
	collision_layer = 0
	velocity = Vector3.ZERO
	# Lay the sprite flat on the ground as a corpse.
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.position = Vector3(0, 0.05, 0)
	sprite.rotation = Vector3(-PI * 0.5, 0, 0)
	rotation.y = randf() * TAU
	sprite.modulate = Color(0.55, 0.55, 0.55)
	_on_died()


func _on_died() -> void:
	pass
