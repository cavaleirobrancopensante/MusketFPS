extends Node3D
## Your horse (a cavalry officer's, Company.officer.horse): ridden, or
## standing where you got down.
##
## Riding: push the stick the way you want to go (as on foot, relative to
## where you look). The horse turns toward it at a rate that falls as it
## speeds up, gathers speed (walk, trot, gallop) the further you push, and
## can't go sideways. Let go and it slows to a stand. Ask it to turn right
## round and it slows to do it.
##
## At speed it rides men down: a lizard in its path is knocked flying and
## hurt, and the horse loses some of its pace. Blows aimed at you often land
## on the horse instead; a horse that's killed throws you (player.gd).

const Rig3D := preload("res://scripts/rig3d.gd")

const GALLOP := 10.5 # m/s
const ACCEL := 3.6
const BRAKE := 8.0
const RIDE_DOWN_AT := 6.0 # m/s: fast enough to bowl a man over
const SADDLE_Y := 0.8 # the rider's rig stands this high (rig3d's SADDLE_HORSE)

var battle
var player = null # while ridden
var rig
var yaw := 0.0 # where the horse faces (world, like rotation.y)
var speed := 0.0
var hp := 220.0
var max_hp := 220.0
var dead := false
var _hit := {} # instance id -> time: already ridden down this pass
var _t := 0.0


static func make(b, at: Vector3, facing_yaw: float, hp_now: float, hp_max: float):
	var h = load("res://scripts/player_horse.gd").new()
	h.battle = b
	h.position = at
	h.yaw = facing_yaw
	h.hp = hp_now
	h.max_hp = hp_max
	return h


func _ready() -> void:
	rig = Rig3D.new()
	rig.kind = "horse"
	rig.gear = {"saddle_col": Color(0.16, 0.24, 0.55)}
	add_child(rig)
	rotation.y = yaw


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The rider's eye bobs with the horse's back.
func bob() -> float:
	return rig.body.position.y if rig != null and rig.body != null else 0.0


## How fast the horse can go (your Riding, the field's pace, a wounded horse).
func top_speed() -> float:
	var hurt := clampf(hp / max_hp, 0.0, 1.0)
	return GALLOP * Company.Officer.horse_speed_mult() * lerpf(0.65, 1.0, hurt)


## One physics step under the rider: the stick (as player.move_input) in
## the rider's frame. Returns the horse's velocity on the flat.
func drive(input: Vector2, basis_y: Basis, delta: float) -> Vector3:
	var want := Vector3.ZERO
	if input.length() > 0.12:
		want = basis_y * Vector3(input.x, 0.0, input.y)
		want.y = 0.0
	var target := 0.0
	if want.length_squared() > 0.0001:
		var want_yaw := atan2(-want.x, -want.z)
		var diff := angle_difference(yaw, want_yaw)
		# Quick on the turn at a walk, wide at a gallop.
		var rate := lerpf(2.8, 1.25, clampf(speed / GALLOP, 0.0, 1.0)) * Company.Officer.horse_speed_mult()
		yaw += clampf(diff, -rate * delta, rate * delta)
		target = clampf(input.length(), 0.0, 1.0) * top_speed() * battle.ground_speed(global_position) # (scrambling over the works)
		if absf(diff) > 1.9:
			target = minf(target, 2.0) # turning round: steady first
	if target > speed:
		speed = minf(target, speed + ACCEL * delta)
	else:
		speed = maxf(target, speed - BRAKE * delta)
	return forward() * speed


func _process(delta: float) -> void:
	_t += delta
	if dead:
		return
	rotation.y = yaw
	if player != null:
		global_position = player.global_position
	rig.facing = forward()
	rig.move_speed = speed
	rig.anim_time += delta
	rig.anim = "walk"
	# From the saddle in first person its head would hide the field.
	rig.neck_dip = -0.55 if player != null and not player.third_person else 0.0


## Whistled for: it trots over to you and stands.
var _called_by = null


func call_to(p) -> void:
	_called_by = p


func _physics_process(delta: float) -> void:
	if not dead and player == null and _called_by != null:
		_come(delta)
		return
	if dead or player == null or speed < RIDE_DOWN_AT:
		return
	# Riding them down: whoever's just in front of the chest.
	var front := global_position + forward() * 1.3
	for e in battle.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector3 = e.global_position - front
		to.y = 0.0
		if to.length() > 1.25:
			continue
		var id: int = e.get_instance_id()
		if _hit.has(id) and _t - float(_hit[id]) < 1.5:
			continue
		_hit[id] = _t
		var dmg := (18.0 + 4.0 * speed) * Company.Officer.mounted_blow_mult()
		if e.has_method("receive_blow"):
			var r: String = e.receive_blow(dmg, player, true)
			if r == "hit" and e.has_method("stagger"):
				e.stagger((forward() + to.normalized() * 0.5).normalized() * 6.0, 0.9)
		else:
			e.take_damage(dmg, player)
		battle.play_sound("stab", e.global_position + Vector3.UP, -2.0)
		speed *= 0.72 # the shock costs the horse its pace
		player.shake(0.3)


func _come(delta: float) -> void:
	var to: Vector3 = _called_by.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d < 2.4:
		speed = move_toward(speed, 0.0, BRAKE * delta)
		if speed <= 0.01:
			_called_by = null
	else:
		var want_yaw := atan2(-to.x, -to.z)
		var diff := angle_difference(yaw, want_yaw)
		yaw += clampf(diff, -2.4 * delta, 2.4 * delta)
		speed = move_toward(speed, minf(6.0, d * 1.2) * (0.4 if absf(diff) > 1.2 else 1.0), ACCEL * delta)
	global_position += forward() * speed * delta
	global_position.y = battle.ground_y(global_position)


## A blow or a shot that found the horse. Returns true if that killed it.
func hurt(amount: float) -> bool:
	if dead:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_die()
		return true
	return false


func _die() -> void:
	dead = true
	speed = 0.0
	rig.move_speed = 0.0
	battle.play_sound("grunt", global_position + Vector3.UP * 1.4, 2.0)
	# Down on its side (the rig stops posing itself, and draws the fall).
	rig._dead = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(rig.body, "rotation:z", 1.45, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(rig.body, "position:y", -0.55, 0.7)
	rig.tint = Color(0.6, 0.6, 0.6)
