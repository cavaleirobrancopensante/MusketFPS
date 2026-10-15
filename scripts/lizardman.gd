extends "res://scripts/unit.gd"
## A lizardman warrior. Dumb on purpose: pick the nearest man (or you), charge,
## hack. Their danger comes from numbers, which keeps the AI cheap.
##
## Every hack has a short wind-up (the sprite rears up and glows orange) so you
## can read it: block, step back, or hit it first. Hitting a lizardman
## staggers it, knocks it back and cancels its swing.

const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 22.0
const ATTACK_COOLDOWN := 1.0
const WINDUP_TIME := 0.5
const WINDUP_TINT := Color(1.0, 0.55, 0.25)

var speed := 4.6
var target: Node3D = null
var retarget_timer := 0.0
var attack_timer := 0.0
var windup := -1.0 # >= 0 while rearing up for a hack
var stagger_time := 0.0
var knockback := Vector3.ZERO


func _ready() -> void:
	add_to_group("enemies")
	_setup_body(2, 0.45, 1.9, 1.95)
	speed = randf_range(4.0, 5.2)
	retarget_timer = randf() * 0.5
	attack_timer = randf() * 0.4


func _physics_process(delta: float) -> void:
	if not alive:
		return
	attack_timer -= delta
	retarget_timer -= delta

	# Staggered: slide back from the blow, can't act.
	if stagger_time > 0.0:
		stagger_time -= delta
		velocity = knockback
		knockback = knockback.move_toward(Vector3.ZERO, 12.0 * delta)
		sprite.position.y = 0.0
		move_and_slide()
		return

	if retarget_timer <= 0.0 or not is_valid_target(target):
		retarget_timer = 0.5
		if windup < 0.0: # don't switch targets mid-swing
			target = battle.nearest_friendly(global_position)
	var push: Vector3 = battle.separation(self, battle.enemies, 1.1)
	if not is_valid_target(target):
		_cancel_windup()
		velocity = push * 2.0
		move_and_slide()
		return

	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var d := to_t.length()

	if windup >= 0.0:
		# Rearing up: stand, glow, then strike.
		windup += delta
		var k := clampf(windup / WINDUP_TIME, 0.0, 1.0)
		sprite.modulate = Color.WHITE.lerp(WINDUP_TINT, k)
		sprite.scale = Vector3(1.0 - 0.08 * k, 1.0 + 0.12 * k, 1.0)
		velocity = push * 2.0
		if windup >= WINDUP_TIME:
			_strike(d)
	elif d <= ATTACK_RANGE:
		velocity = push * 2.0
		sprite.position.y = 0.0
		if attack_timer <= 0.0:
			windup = 0.0
	else:
		velocity = to_t / d * speed + push * 3.0
		_bob(0.14, 11.0)
	velocity.y = 0.0
	move_and_slide()


func _strike(dist: float) -> void:
	windup = -1.0
	attack_timer = ATTACK_COOLDOWN
	sprite.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector3(1.18, 0.88, 1.0), 0.08)
	tw.tween_property(sprite, "scale", Vector3.ONE, 0.25)
	# A step of reach so backing off at the last instant is a real dodge, not a guarantee.
	if dist <= ATTACK_RANGE + 0.4 and randf() < 0.75:
		target.take_damage(ATTACK_DAMAGE, self)


func _cancel_windup() -> void:
	if windup >= 0.0:
		windup = -1.0
		sprite.modulate = Color.WHITE
		sprite.scale = Vector3.ONE


## Knocked back by a blow (or a parried hack). `push` is a horizontal velocity.
func stagger(push: Vector3, seconds: float) -> void:
	if not alive:
		return
	_cancel_windup()
	stagger_time = maxf(stagger_time, seconds)
	knockback = push
	attack_timer = maxf(attack_timer, 0.3)


func _on_died() -> void:
	_cancel_windup()
	remove_from_group("enemies")
	battle.on_enemy_died(self)
	# Leave the corpse a while, then clean up to keep the phone happy.
	var tw := create_tween()
	tw.tween_interval(15.0)
	tw.tween_property(sprite, "scale", Vector3.ONE * 0.01, 1.5)
	tw.tween_callback(queue_free)
