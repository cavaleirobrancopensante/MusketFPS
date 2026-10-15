extends "res://scripts/unit.gd"
## One musketeer of your company. Keeps his place in the line, loads, fires
## (on your command or at will) and uses the bayonet when lizardmen close in.

const SPEED := 3.8
const RANGE := 40.0
const MELEE_RANGE := 1.8
const MELEE_DAMAGE := 34.0
const MELEE_COOLDOWN := 1.2

var slot_index := 0
var loaded := true
var reload_time := 5.5
var reload_left := 0.0
var shot_timer := -1.0 # >= 0 means a shot is scheduled
var melee_timer := 0.0
var retarget_timer := 0.0
var target: Node3D = null


func _ready() -> void:
	add_to_group("friendlies")
	_setup_body(4, 0.35, 1.8, 1.8)
	reload_time = randf_range(4.5, 5.5)
	retarget_timer = randf() * 0.4


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if not loaded:
		reload_left -= delta
		if reload_left <= 0.0:
			loaded = true
	melee_timer -= delta
	retarget_timer -= delta
	if retarget_timer <= 0.0 or not is_valid_target(target):
		retarget_timer = 0.4
		target = battle.nearest_enemy(global_position, RANGE)

	var dist_t := INF
	if is_valid_target(target):
		dist_t = global_position.distance_to(target.global_position)

	# Bayonet: stand and fight when a lizardman is on top of us.
	if dist_t <= MELEE_RANGE:
		velocity = Vector3.ZERO
		if melee_timer <= 0.0:
			melee_timer = MELEE_COOLDOWN
			_thrust()
			if randf() < 0.75:
				target.take_damage(MELEE_DAMAGE)
		return

	# March to our slot in the line.
	var slot: Vector3 = battle.get_slot_position(slot_index)
	var to_slot := slot - global_position
	to_slot.y = 0.0
	var gap := to_slot.length()
	var v := Vector3.ZERO
	if gap > 0.3:
		var spd := SPEED * (1.4 if gap > 6.0 else 1.0)
		v = to_slot / gap * minf(spd, gap * 3.0)
		_bob(0.06, 9.0)
	else:
		sprite.position.y = 0.0
	var push: Vector3 = battle.separation(self, battle.soldiers, 1.0)
	velocity = v + push * 2.0
	move_and_slide()

	# Shooting.
	if shot_timer >= 0.0:
		shot_timer -= delta
		if shot_timer < 0.0:
			_shoot()
	elif loaded and battle.is_at_will() and dist_t <= RANGE and gap < 1.5:
		shot_timer = randf_range(0.3, 1.8)


## Called by the company when you order a volley.
func volley() -> void:
	if not alive or not loaded:
		return
	if not is_valid_target(target):
		target = battle.nearest_enemy(global_position, RANGE)
	if is_valid_target(target):
		shot_timer = randf_range(0.0, 0.3) # a ragged ripple, not a perfect crack


func _shoot() -> void:
	shot_timer = -1.0
	if not alive or not loaded:
		return
	if not is_valid_target(target):
		target = battle.nearest_enemy(global_position, RANGE)
	if not is_valid_target(target):
		return
	loaded = false
	reload_left = reload_time
	var to_t := target.global_position - global_position
	var d := to_t.length()
	var dir := to_t / maxf(d, 0.01)
	var muzzle := global_position + dir * 0.7 + Vector3.UP * 1.45
	battle.spawn_smoke(muzzle, 1.0)
	battle.spawn_flash(muzzle)
	# Smoothbore muskets: good odds up close, poor at range.
	var chance := clampf(0.8 - d * 0.014, 0.25, 0.8)
	if randf() < chance:
		target.take_damage(100.0)


func _thrust() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector3(1.0, 1.0, 1.0) * 1.12, 0.08)
	tw.tween_property(sprite, "scale", Vector3.ONE, 0.2)


func _on_died() -> void:
	remove_from_group("friendlies")
	battle.on_soldier_died(self)
