extends "res://scripts/unit.gd"
## A lizardman warrior. Dumb on purpose: pick the nearest man (or you), charge,
## hack. Their danger comes from numbers, which keeps the AI cheap.
##
## Every hack has a short wind-up (it rears up, cleaver high, and glows orange)
## so you can read it: block, step back, or hit it first. Hitting a lizardman
## staggers it, knocks it back and cancels its swing.
##
## They carry shields. When you wind up a blow close in front of one, he may
## bring his shield up (you'll see it); while it's up he blocks frontal blows
## and won't attack. A fully charged blow smashes through the guard. Now and
## then he snaps the shield up just in time against a soldier's thrust too.
## Shields don't stop musket balls.
##
## Animations: idle, walk, windup, strike, stagger, shield.

const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 22.0
const ATTACK_COOLDOWN := 1.0
const WINDUP_TIME := 0.5
const WINDUP_TINT := Color(1.0, 0.55, 0.25)
const SHIELD_REACT_CHANCE := 0.45 # raises the shield against your wind-up
const SHIELD_SNAP_CHANCE := 0.22 # catches an unannounced thrust anyway
const SHIELD_TIME := 1.1

var speed := 4.6
var target: Node3D = null
var retarget_timer := 0.0
var attack_timer := 0.0
var windup := -1.0 # >= 0 while rearing up for a hack
var stagger_time := 0.0
var knockback := Vector3.ZERO
var _roar_t := 0.0
var shield_up := 0.0 # seconds the shield stays raised
var _read_windup := false # already reacted to the player's current wind-up
var looter := false # would rather plunder the wagon than fight
var looting := false
var carried := 0.0 # share of the wagon in his arms (back to the wagon if he dies)
var eaten := 0 # rations he's already wolfed down (those are gone for good)
var _dig_t := 0.0
var _bites := 0 # rations still to eat from the sack in his hands
var _bite_t := 0.0
var still := false # a target on the weapon range: stands and takes it


func _ready() -> void:
	add_to_group("enemies")
	rig_kind = "lizard"
	_setup_body(2, 0.45, 1.9, 1.95)
	hit_height = 2.05 # the model stands a little taller than his capsule
	speed = randf_range(4.0, 5.2)
	retarget_timer = randf() * 0.5
	attack_timer = randf() * 0.4
	looter = randf() < 0.35
	_roar_t = randf_range(1.0, 8.0)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var dt := _think(delta)
	if dt >= 0.0:
		_brain(dt)


func _brain(delta: float) -> void:
	attack_timer -= delta
	retarget_timer -= delta
	_roar_t -= delta
	if _roar_t <= 0.0:
		_roar_t = randf_range(5.0, 12.0)
		battle.play_sound("roar", global_position + Vector3.UP * 1.6, -6.0)

	if still:
		velocity = Vector3.ZERO
		face_toward(battle.player.global_position - global_position)
		set_base_anim("idle")
		return
	_watch_player()

	# Staggered: slide back from the blow, can't act.
	if stagger_time > 0.0:
		stagger_time -= delta
		velocity = knockback
		knockback = knockback.move_toward(Vector3.ZERO, 12.0 * delta)
		set_base_anim("stagger")
		_move(delta)
		return

	if looter and _go_loot(delta):
		return

	if retarget_timer <= 0.0 or not is_valid_target(target):
		retarget_timer = 0.5
		if windup < 0.0: # don't switch targets mid-swing
			target = battle.nearest_friendly(global_position)
	var push: Vector3 = battle.separation(self, battle.enemies, 1.1)

	# Behind the shield: face the threat and hold.
	if shield_up > 0.0:
		shield_up -= delta
		var p: Node3D = battle.player
		face_toward(p.global_position - global_position)
		set_base_anim("shield")
		velocity = push * 2.0
		velocity.y = 0.0
		_move(delta)
		return

	if not is_valid_target(target):
		_cancel_windup()
		velocity = push * 2.0
		set_base_anim("idle")
		_move(delta)
		return

	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var d := to_t.length()
	face_toward(to_t)
	# Far from a fight he needs fewer decisions: just keep coming.
	think_every = 2 if d < 18.0 and not sprite_on else 4

	if windup >= 0.0:
		# Rearing up: stand, glow, then strike.
		windup += delta
		var k := clampf(windup / WINDUP_TIME, 0.0, 1.0)
		set_tint(Color.WHITE.lerp(WINDUP_TINT, k))
		set_base_anim("windup")
		velocity = push * 2.0
		if windup >= WINDUP_TIME:
			_strike(d)
	elif d <= ATTACK_RANGE:
		velocity = push * 2.0
		set_base_anim("idle")
		if attack_timer <= 0.0:
			windup = 0.0
			battle.play_sound("hiss", global_position + Vector3.UP * 1.6, -8.0)
	else:
		velocity = to_t / d * speed + push * 3.0
		set_base_anim("walk")
	velocity.y = 0.0
	_move(delta)


## Looters make for the wagon when it's nearer than a fight, and rummage
## in it until it's empty or someone hurts them.
func _go_loot(delta: float) -> bool:
	if not battle.wagon_open():
		looting = false
		return false
	var w: Vector3 = battle.wagon.global_position
	var to_w := w - global_position
	to_w.y = 0.0
	var dw := to_w.length()
	var dt := INF
	if is_valid_target(target):
		dt = global_position.distance_to(target.global_position)
	if not looting and (dw > 30.0 or dw > dt + 8.0):
		return false
	_cancel_windup()
	face_toward(to_w)
	if dw < 2.6:
		# At the wagon: dig through it, then pull out a ration sack and eat.
		looting = true
		velocity = battle.separation(self, battle.enemies, 1.1) * 2.0
		if _bites > 0:
			set_base_anim("eat")
			_bite_t -= delta
			if _bite_t <= 0.0:
				_bite_t = 1.6
				_bites -= 1
				battle.eat_ration(self)
		else:
			set_base_anim("rummage")
			battle.loot_tick(delta, self)
			_dig_t += delta
			if _dig_t > 2.5:
				_dig_t = 0.0
				if battle.rations_left() > 0:
					_bites = randi_range(2, 4)
					_bite_t = 1.2
		if randf() < delta * 0.3:
			battle.play_sound("hiss", global_position + Vector3.UP * 1.4, -12.0)
	else:
		velocity = to_w / dw * speed + battle.separation(self, battle.enemies, 1.1) * 3.0
		set_base_anim("walk")
	velocity.y = 0.0
	_move(delta)
	return true


func _strike(dist: float) -> void:
	windup = -1.0
	attack_timer = ATTACK_COOLDOWN
	set_tint(Color.WHITE)
	play_oneshot("strike", 0.3)
	_punch(Vector3(1.12, 0.92, 1.0), 0.3)
	# A step of reach so backing off at the last instant is a real dodge, not a guarantee.
	if dist <= ATTACK_RANGE + 0.4 and randf() < 0.75:
		target.take_damage(ATTACK_DAMAGE, self)
	else:
		battle.play_sound("swish", global_position + Vector3.UP * 1.4, -6.0)


func _cancel_windup() -> void:
	if windup >= 0.0:
		windup = -1.0
		set_tint(Color.WHITE)


## If you wind up a blow close in front of him, he may raise his shield.
func _watch_player() -> void:
	var p = battle.player
	var winding: bool = p.alive and p.is_melee() and p.swing_phase == "windup"
	if not winding:
		_read_windup = false
		return
	if _read_windup or windup >= 0.0 or stagger_time > 0.0:
		return
	var to_me: Vector3 = global_position - p.global_position
	to_me.y = 0.0
	var p_fwd: Vector3 = -p.global_transform.basis.z
	p_fwd.y = 0.0
	if to_me.length() < 3.2 and p_fwd.normalized().dot(to_me.normalized()) > 0.6:
		_read_windup = true # one decision per wind-up
		if randf() < SHIELD_REACT_CHANCE:
			raise_shield(SHIELD_TIME)


func raise_shield(seconds: float) -> void:
	_cancel_windup()
	shield_up = maxf(shield_up, seconds)


## A melee blow aimed at him. Returns "hit", "blocked" (on the shield) or
## "broken" (a heavy blow that smashes through his guard).
func receive_blow(damage: float, from: Node3D, heavy: bool) -> String:
	if not alive:
		return "hit"
	var to_from := from.global_position - global_position
	to_from.y = 0.0
	var frontal := facing.dot(to_from.normalized()) > 0.3
	var push := -to_from.normalized()
	if frontal and shield_up > 0.0:
		if heavy:
			shield_up = 0.0
			battle.play_sound("clang", global_position + Vector3.UP * 1.3, -2.0)
			take_damage(damage * 0.5, from)
			stagger(push * 4.5, 0.9)
			return "broken"
		battle.play_sound("clang", global_position + Vector3.UP * 1.3, -3.0)
		return "blocked"
	if frontal and windup < 0.0 and stagger_time <= 0.0 and randf() < SHIELD_SNAP_CHANCE:
		raise_shield(0.45)
		battle.play_sound("clang", global_position + Vector3.UP * 1.3, -3.0)
		return "blocked"
	take_damage(damage, from)
	return "hit"


## A thrown weapon (javelin, arrow) arriving: a raised shield catches it if
## it comes from in front.
func catch_projectile(at: Vector3) -> bool:
	var to := at - global_position
	to.y = 0.0
	return shield_up > 0.0 and facing.dot(to.normalized()) > 0.3


## Knocked back by a blow (or a parried hack). `push` is a horizontal velocity.
func stagger(push: Vector3, seconds: float) -> void:
	if not alive:
		return
	_cancel_windup()
	shield_up = 0.0
	stagger_time = maxf(stagger_time, seconds)
	knockback = push
	attack_timer = maxf(attack_timer, 0.3)


func take_damage(amount: float, from: Node3D = null) -> void:
	if from != null and (looter or looting):
		# Hurt while plundering: drop the loot and go for whoever did it.
		looter = false
		looting = false
		_bites = 0
		target = from
	super.take_damage(amount, from)
	if alive and amount < 100.0:
		battle.play_sound("hiss", global_position + Vector3.UP * 1.6, -4.0)


func _on_died() -> void:
	_cancel_windup()
	if carried > 0.0:
		battle.recover_loot(self)
	remove_from_group("enemies")
	if last_hit_by != null and is_instance_valid(last_hit_by) and "kills" in last_hit_by:
		last_hit_by.kills += 1
	battle.play_sound("death", global_position + Vector3.UP * 1.4, -4.0)
	battle.on_enemy_died(self)
	# Leave the corpse a while, then clean up to keep the phone happy.
	battle.lizard_corpses.append(global_position)
	var tw := _fade_corpse(60.0, 1.5) # long enough to be searched after the fight
	tw.tween_callback(queue_free)
