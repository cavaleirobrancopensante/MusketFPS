extends "res://scripts/unit.gd"
## A lizardman warrior. Dumb on purpose: pick the nearest man (or you), charge,
## hack. Their danger comes from numbers, which keeps the AI cheap.

const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 22.0
const ATTACK_COOLDOWN := 1.1

var speed := 4.6
var target: Node3D = null
var retarget_timer := 0.0
var attack_timer := 0.0


func _ready() -> void:
	add_to_group("enemies")
	_setup_body(2, 0.45, 1.9, 1.95)
	speed = randf_range(4.0, 5.2)
	retarget_timer = randf() * 0.5


func _physics_process(delta: float) -> void:
	if not alive:
		return
	attack_timer -= delta
	retarget_timer -= delta
	if retarget_timer <= 0.0 or not is_valid_target(target):
		retarget_timer = 0.5
		target = battle.nearest_friendly(global_position)
	var push: Vector3 = battle.separation(self, battle.enemies, 1.1)
	if not is_valid_target(target):
		velocity = push * 2.0
		move_and_slide()
		return

	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var d := to_t.length()
	if d <= ATTACK_RANGE:
		velocity = push * 2.0
		sprite.position.y = 0.0
		if attack_timer <= 0.0:
			attack_timer = ATTACK_COOLDOWN
			_swing()
			if randf() < 0.7:
				target.take_damage(ATTACK_DAMAGE)
	else:
		velocity = to_t / d * speed + push * 3.0
		_bob(0.14, 11.0)
	velocity.y = 0.0
	move_and_slide()


func _swing() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector3(1.15, 0.9, 1.0), 0.1)
	tw.tween_property(sprite, "scale", Vector3.ONE, 0.25)


func _on_died() -> void:
	remove_from_group("enemies")
	battle.on_enemy_died(self)
	# Leave the corpse a while, then clean up to keep the phone happy.
	var tw := create_tween()
	tw.tween_interval(15.0)
	tw.tween_property(sprite, "scale", Vector3.ONE * 0.01, 1.5)
	tw.tween_callback(queue_free)
