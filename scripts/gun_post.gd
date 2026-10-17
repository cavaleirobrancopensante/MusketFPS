extends "res://scripts/unit.gd"
## A field gun of a battery in a field battle (Tests > Field battle), as
## something the enemy can shoot and hack at: the gun and its crew of four
## (gun_crew.gd draws them and works the drill). Hits thin the crew, so the
## gun loads slower; when it's down the crew is cut down and the gun falls
## silent. Its battery (regiment.gd, kind "gun") lays and fires it.

const GunCrew := preload("res://scripts/gun_crew.gd")

var reg = null
var field
var side := 0
var crew # GunCrew
var slot_index := 0
var windup := -1.0
var target = null
var stagger_time := 0.0
var in_melee_t := -99.0
var max_hp := 260.0
var kills := 0
var light := false # the artillery officer's galloper
var manned := false # you're laying it (player_gun.gd): the battery leaves it to you


static func make(b, f, s: int, at: Vector3, yaw: float):
	var me = load("res://scripts/gun_post.gd").new()
	me.battle = b
	me.field = f
	me.side = s
	me.position = at
	me.light = f._making_light
	me.crew = GunCrew.make(b, at, yaw, me.base_reload())
	me.crew.light = me.light
	if s == 1:
		me.crew.coat_col = Color(0.62, 0.12, 0.1)
	return me


## Seconds for the drill: a light gun is quicker; your Gunnery quickens
## every gun of yours.
func base_reload() -> float:
	var r: float = (6.5 if light else 9.0) / float(field.pace)
	if side == 0:
		r *= Company.Officer.gun_reload_mult()
	return r


func _ready() -> void:
	add_to_group("enemies" if side == 1 else "friendlies")
	rig_kind = "gun"
	collision_layer = 0
	collision_mask = 0
	hp = max_hp
	hit_radius = 1.5
	hit_height = 1.6
	battle.add_child(crew)


func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not alive or reg == null:
		return
	if manned:
		moving = false
		return
	# Manhandled to its place in the battery; the crew can't load on the move.
	var slot: Vector3 = reg.slot(slot_index)
	var to := slot - global_position
	to.y = 0.0
	if to.length() > 0.6:
		var dv := to.normalized() * minf(1.5 * delta, to.length())
		position = field.terrain.step(position, dv)
		crew.position = position
		crew.want_yaw = atan2(-to.x, -to.z)
		crew.rotation.y = lerp_angle(crew.rotation.y, crew.want_yaw, 1.0 - exp(-2.0 * delta))
		crew.t = minf(crew.t, 0.6)
		moving = true
	else:
		moving = false


var moving := false


## Lay on a point and fire if loaded, laid and the line is clear (by the
## battery). Returns true if it fired.
func try_fire(aim: Vector3) -> bool:
	if not alive or moving:
		return false
	crew.lay_on(aim)
	if not crew.ready() or absf(angle_difference(crew.rotation.y, crew.want_yaw)) > 0.06:
		return false
	var muzzle: Vector3 = crew.barrel.global_transform * Vector3(0, 0, crew.MUZZLE_Z)
	if not field.terrain.clear_line(muzzle + Vector3.UP * 0.3, aim + Vector3.UP * 0.6):
		return false
	if battle.projectiles.line_blocked(muzzle, aim, self):
		return false # (our own men in front of the muzzle)
	reg.fired()
	return crew.fire_at(aim, 30.0)


func take_damage(amount: float, from: Node3D = null) -> void:
	if not alive:
		return
	if from != null:
		last_hit_by = from
	hp -= amount * (0.5 if _shot else 1.0) # (the gun and the limber take a lot of it)
	crew.reload = base_reload() * lerpf(2.0, 1.0, clampf(hp / max_hp, 0.0, 1.0))
	if reg != null:
		reg.hurt(amount)
	if hp <= 0.0:
		_die()


func receive_blow(damage: float, from: Node3D, _heavy: bool) -> String:
	take_damage(damage, from)
	return "hit"


func stagger(_push: Vector3, _seconds: float) -> void:
	pass


func _die() -> void:
	alive = false
	remove_from_group("enemies")
	remove_from_group("friendlies")
	crew.overrun()
	battle.play_sound("grunt", global_position + Vector3.UP * 1.5, -2.0)
	field.unit_died(self)
