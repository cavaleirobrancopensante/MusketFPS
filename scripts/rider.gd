extends "res://scripts/unit.gd"
## A cavalryman in a field battle (Tests > Field battle): a trooper with a
## sabre on a horse, or a lizard with a cleaver on a riding raptor.
##
## Cavalry is about speed and the shock of the charge:
##   - it walks in formation, trots to close, and charges at a gallop
##   - a charge that arrives fast hits whoever it meets hard (and knocks
##     them flying), and shakes their regiment; then the riders lose their
##     speed and cut at whoever is near
##   - braced pikes are the answer: a charge into their front is stopped
##     on the points, and every pike thrust at a horse hurts it badly
##   - riders don't stay in a melee they're losing: their regiment pulls
##     them out to charge again (regiment.gd)
##
## The mount is the unit's rig (kind "horse" / "raptor"); the rider is a
## second rig sitting on its body.


const IMPACT := 55.0
const CUT := 34.0
const CUT_COOLDOWN := 1.35
const WINDUP := 0.35
const REACH := 2.4

var reg = null
var field
var side := 0
var mount := "horse"
var rider # Rig3D
var slot_index := 0
var target: Node3D = null
var windup := -1.0
var stagger_time := 0.0
var _knock := Vector3.ZERO
var speed_now := 0.0
var _cut_t := 0.0
var _hit_list := {} # instance id -> true: already ridden down in this charge
var in_melee_t := -99.0
var kills := 0
var _rear_t := 0.0
var walk_speed := 3.2
var trot_speed := 6.5
var charge_speed := 11.0


static func make(b, f, s: int, m: String):
	var me = load("res://scripts/rider.gd").new()
	me.battle = b
	me.field = f
	me.side = s
	me.mount = m
	me.frames = b.soldier_frames if m == "horse" else b.lizard_frames
	return me


func _ready() -> void:
	add_to_group("enemies" if side == 1 else "friendlies")
	rig_kind = "cavalry" if mount == "horse" else "raptor_rider"
	rig_look = mount
	hp = 240.0 if mount == "horse" else 260.0
	if mount == "raptor":
		walk_speed = 3.4
		trot_speed = 6.5
		charge_speed = 10.0
	tempo = randf_range(0.92, 1.08)
	walk_speed *= field.pace
	trot_speed *= field.pace
	charge_speed *= lerpf(1.0, field.pace, 0.5) # (still fast enough to ride men down)
	think_every = 2
	if sprite_kind == "":
		sprite_kind = "soldier" if mount == "horse" else "lizard"
	rig_gear = {"saddle_col": Color(0.62, 0.12, 0.1) if side == 1 and mount == "horse" else (Color(0.16, 0.24, 0.55) if mount == "horse" else Color(0.5, 0.36, 0.2))}
	_setup_body(4 if side == 0 else 2, 0.75, 2.7, 2.9)
	rider = Rig3D.new()
	rider.seated = true
	if mount == "horse":
		rider.kind = "soldier"
		rider.gear = {"head": "tricorne" if side == 1 else "shako", "torso": "coat", "primary": "none", "secondary": "", "sword": "saber"}
		rider.pack = {"rations": 0, "water": 0, "ammo": 0}
		rider.hand_item = "saber"
		if side == 1:
			rider.coat_override = Color(0.62, 0.12, 0.1)
		rider.position = Rig3D.SADDLE_HORSE
	else:
		rider.kind = "lizard"
		rider.position = Rig3D.SADDLE_RAPTOR + Vector3(0, -0.08, 0)
	rig.body.add_child(rider)
	if mount == "raptor":
		rider.scale = Vector3.ONE * 1.0


func _process(delta: float) -> void:
	super._process(delta)
	if rider != null and alive and rig.visible:
		rider.facing = facing
		rider.anim = anim if mount == "horse" else {"charge": "walk", "windup": "windup", "strike": "strike"}.get(anim, "idle")
		rider.anim_time = anim_time
		rider.move_speed = 0.0
		rider.tint = rig.tint
		rig.anim = "rear" if _rear_t > 0.0 else "walk"


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var dt := _think(delta)
	if dt >= 0.0 and reg != null:
		_cav_brain(dt)


func _cav_brain(delta: float) -> void:
	_cut_t -= delta
	_rear_t -= delta
	if stagger_time > 0.0:
		stagger_time -= delta
		windup = -1.0
		speed_now = 0.0
		velocity = _knock
		_knock = _knock.move_toward(Vector3.ZERO, 8.0 * delta)
		_move(delta)
		return
	if windup >= 0.0:
		windup += delta
		set_base_anim("windup")
		if windup >= WINDUP:
			_cut()
	var routing: bool = reg.state in ["routing", "shattered"]
	if routing:
		windup = -1.0
		var to: Vector3 = reg.flee_point(self) - global_position
		to.y = 0.0
		if to.length() < 5.0 or field.off_field(global_position):
			field.unit_fled(self)
			return
		_ride(to.normalized(), charge_speed * 0.85, delta)
		return
	var foe: Node3D = null
	if reg.foes_close:
		foe = field.nearest_foe(self, REACH + 0.6)
	if reg.charging:
		var cf: Node3D = reg.charge_foe(self)
		if cf != null:
			target = cf
		_charge(delta, foe)
		return
	if foe != null:
		_melee(delta, foe)
		return
	# Formation.
	var slot: Vector3 = reg.slot(slot_index)
	var to_s := slot - global_position
	to_s.y = 0.0
	var gap := to_s.length()
	if gap > 0.8:
		var want: float = minf(reg.march_speed() * (1.5 if gap > 6.0 else 1.0), gap * 1.6)
		_ride(to_s / gap, want, delta)
	else:
		speed_now = move_toward(speed_now, 0.0, 6.0 * delta)
		velocity = Vector3.ZERO
		face_toward(facing.lerp(reg.forward, 0.25))
		set_base_anim("idle" if windup < 0.0 else "windup")
		_move(delta)


## Speed up toward `want` (horses take a moment to get going) and turn
## toward `dir` at a horse's rate, not on the spot.
func _ride(dir: Vector3, want: float, delta: float) -> void:
	var cur := facing
	var ang := cur.signed_angle_to(dir, Vector3.UP)
	var turn := clampf(ang, -2.2 * delta, 2.2 * delta)
	if speed_now < 2.0:
		turn = ang # at a walk he can turn about
	facing = (Basis(Vector3.UP, turn) * cur).normalized()
	var slow_for_turn := 1.0 - clampf(absf(ang) / PI, 0.0, 0.7)
	speed_now = move_toward(speed_now, want * slow_for_turn, (5.0 if want > speed_now else 9.0) * delta)
	velocity = facing * speed_now + battle.separation(self, _own(), 1.8) * 2.0
	if windup < 0.0:
		set_base_anim("charge" if speed_now > 7.5 else "walk")
	_move(delta)


func _own() -> Array:
	return battle.enemies if side == 1 else (battle.soldiers if self in battle.soldiers else battle.allies)


func _charge(delta: float, close: Node3D) -> void:
	if not is_valid_target(target):
		target = field.nearest_foe(self, 80.0)
	if not is_valid_target(target):
		_ride(reg.forward, walk_speed, delta)
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	# Anyone in the way at a gallop gets ridden down.
	if close != null and speed_now > 6.0 and not _hit_list.has(close.get_instance_id()):
		_impact(close)
	elif close != null and speed_now <= 6.0:
		_melee(delta, close)
		return
	_ride(to / maxf(d, 0.01), charge_speed if d > 4.0 or speed_now > 6.0 else trot_speed, delta)


## The shock of a galloping horse: a heavy blow, the man thrown back, his
## regiment shaken. Braced pikes in front stop it dead and hurt the horse.
func _impact(u: Node3D) -> void:
	_hit_list[u.get_instance_id()] = true
	var ureg = u.get("reg")
	var to_me := global_position - u.global_position
	to_me.y = 0.0
	var faces_me: bool = u.get("facing") != null and (u.get("facing") as Vector3).dot(to_me.normalized()) > 0.3
	if ureg != null and ureg.braced and bool(u.get("pike")) and faces_me:
		take_damage(70.0, u)
		battle.play_sound("clang", global_position + Vector3.UP * 1.6, 0.0)
		speed_now = 0.0
		_rear_t = 0.8
		stagger(-velocity.normalized() * 3.0, 0.6)
		return
	var dmg := IMPACT * clampf(speed_now / 9.0, 0.6, 1.3)
	if u == battle.player:
		dmg *= 0.6
	u.take_damage(dmg, self)
	if u.has_method("stagger") and u != battle.player:
		u.stagger(velocity.normalized() * 5.0 + Vector3.UP, 0.8)
	battle.play_sound("thud", u.global_position + Vector3.UP, 2.0)
	if ureg != null:
		ureg.shock(self, 3.0)
	speed_now *= 0.7


func _melee(delta: float, foe: Node3D) -> void:
	in_melee_t = field.clock
	reg.engaged_t = field.clock
	target = foe
	var to := foe.global_position - global_position
	to.y = 0.0
	face_toward(to)
	speed_now = move_toward(speed_now, 0.0, 8.0 * delta)
	var v := Vector3.ZERO
	if to.length() > REACH * 0.9:
		v = to.normalized() * 2.0
	velocity = v + battle.separation(self, _own(), 1.8) * 1.5
	if windup < 0.0 and _cut_t <= 0.0:
		windup = 0.0
	if windup < 0.0:
		set_base_anim("idle")
	_move(delta)


func _cut() -> void:
	windup = -1.0
	_cut_t = CUT_COOLDOWN * randf_range(0.85, 1.2) / field.pace
	play_oneshot("strike", 0.35)
	if not is_valid_target(target) or global_position.distance_to(target.global_position) > REACH + 0.6:
		battle.play_sound("swish", global_position + Vector3.UP * 2.0, -8.0)
		return
	var r := "hit"
	if target.has_method("receive_blow") and target != battle.player:
		r = target.receive_blow(CUT, self, false)
	else:
		target.take_damage(CUT, self)
	battle.play_sound("stab" if r == "hit" else "clang", target.global_position + Vector3.UP * 1.4, -4.0)


func _move(_delta: float) -> void:
	_moving = true
	var d := Vector3(velocity.x, 0, velocity.z)
	_move_f = field.terrain.speed_factor(global_position, d.normalized() if d.length_squared() > 0.01 else Vector3.ZERO)


## New charge: forget who we already rode down.
func new_charge() -> void:
	_hit_list.clear()


## A pike thrust from a pikeman: horses fear the points.
func pike_hit(_by: Node3D, braced: bool) -> void:
	take_damage(28.0 if braced else 12.0, _by)
	if braced:
		_rear_t = 0.6


func receive_blow(damage: float, from: Node3D, heavy: bool) -> String:
	if not alive:
		return "hit"
	if windup < 0.0 and not heavy and randf() < 0.15:
		battle.play_sound("clang", global_position + Vector3.UP * 1.8, -3.0)
		return "blocked"
	take_damage(damage, from)
	return "hit"


func stagger(push: Vector3, seconds: float) -> void:
	if not alive:
		return
	stagger_time = maxf(stagger_time, seconds * 0.5)
	_knock = push * 0.4
	windup = -1.0


func take_damage(amount: float, from: Node3D = null) -> void:
	var was := alive
	super.take_damage(amount, from)
	if was and alive and reg != null:
		reg.hurt(amount)


func _on_died() -> void:
	remove_from_group("enemies")
	remove_from_group("friendlies")
	if rider != null:
		rider.die()
	if last_hit_by != null and is_instance_valid(last_hit_by) and "kills" in last_hit_by:
		last_hit_by.kills += 1
	battle.play_sound("death" if mount == "raptor" else "grunt", global_position + Vector3.UP * 1.6, -2.0)
	field.unit_died(self)
