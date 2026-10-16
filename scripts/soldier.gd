extends "res://scripts/unit.gd"
## One musketeer of your company. Keeps his place in the line, loads, fires
## (on your command or at will) and uses the bayonet when lizardmen close in.
##
## Every man is a little different, so the company obeys as a body but never
## moves like one machine:
##   reaction  - how long before he notices the line moving or wheeling
##   pace      - how briskly he walks and works his musket
##   steadiness- quick on the trigger or slow and deliberate; shaky men
##               flinch more and fire wider
##   reload    - his own reload time, which varies a little every time
## He also glances around while standing, and his musket can misfire (a
## "flash in the pan") and need re-priming.
##
## In close combat he fights to survive: gives ground and parries when a
## lizardman rears up, keeps bayonet distance, and thrusts when the enemy is
## open. Under the CHARGE order he picks his own fight, fires if he has a
## shot, and falls back to you when badly wounded.
##
## Animations: idle, walk, aim (musket levelled, shot coming), fire, reload
## (ramming), guard (bayonet charged), block and thrust.

const SPEED := 3.8
const RANGE := 40.0
const MELEE_RANGE := 1.8
const MELEE_DAMAGE := 34.0
const MELEE_COOLDOWN := 1.2
const ENGAGE_RANGE := 3.2 # a lizardman this close gets his full attention
const LEASH := 2.5 # in line orders, how far he'll give ground behind his place
const BACKPEDAL := 1.3 # m/s stepping back under attack
const WOUNDED := 35.0 # below this, a charging man falls back to you
const MISFIRE_CHANCE := 0.04
const REPRIME_TIME := 1.3

var slot_index := 0
var loaded := true
var reload_time := 5.5
var reload_left := 0.0
var shot_timer := -1.0 # >= 0 means a shot is scheduled
var melee_timer := 0.0
var retarget_timer := 0.0
var target: Node3D = null

# Personality.
var reaction := 0.5
var pace := 1.0
var steadiness := 0.5

var _ram_sound_t := 0.0
var _history: Array = [] # [time, slot position, line facing], for delayed reactions
var _seen_slot := Vector3.ZERO
var _seen_forward := Vector3.FORWARD
var _clock := 0.0
var _glance_t := 0.0
var _glance := 0.0 # radians he's looking off to the side
var _reprime_left := 0.0
var blocking := false # musket up, catching a hack on the stock


func _ready() -> void:
	add_to_group("friendlies")
	rig_kind = "soldier"
	reaction = randf_range(0.15, 1.1)
	pace = randf_range(0.85, 1.15)
	steadiness = randf()
	reload_time = randf_range(4.0, 5.6) / pace
	tempo = pace
	retarget_timer = randf() * 0.4
	_glance_t = randf_range(1.0, 4.0)
	_setup_body(4, 0.35, 1.8, 1.8)
	_seen_slot = global_position
	_seen_forward = battle.line_forward


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_clock += delta
	_update_perception()
	if not loaded:
		reload_left -= delta
		_ram_sound_t -= delta
		if _ram_sound_t <= 0.0 and reload_left > 0.8:
			_ram_sound_t = 0.8 / pace
			battle.play_sound("ramrod", global_position + Vector3.UP * 1.4, -14.0)
		if reload_left <= 0.0:
			loaded = true
	_reprime_left -= delta
	melee_timer -= delta
	retarget_timer -= delta
	if retarget_timer <= 0.0 or not is_valid_target(target):
		retarget_timer = 0.4
		target = battle.nearest_enemy(global_position, RANGE)

	var dist_t := INF
	if is_valid_target(target):
		dist_t = global_position.distance_to(target.global_position)

	blocking = false
	# Close combat: a lizardman within reach takes priority over everything.
	var threat: Node3D = battle.nearest_enemy(global_position, ENGAGE_RANGE)
	if threat != null:
		shot_timer = -1.0
		_melee(delta, threat)
		return

	# CHARGE: every man picks his own fight.
	if battle.is_charging() and _charge(delta):
		return

	# March to where he *thinks* his slot is (he reacts a moment late).
	var to_slot := _seen_slot - global_position
	to_slot.y = 0.0
	var gap := to_slot.length()
	var v := Vector3.ZERO
	if gap > 0.35:
		var spd := SPEED * pace * (1.4 if gap > 6.0 else 1.0)
		v = to_slot / gap * minf(spd, gap * 2.5)
	var push: Vector3 = battle.separation(self, battle.soldiers, 1.0)
	velocity = v + push * 2.0
	move_and_slide()

	# Shooting.
	if shot_timer >= 0.0:
		shot_timer -= delta
		if shot_timer < 0.0:
			_shoot()
	elif loaded and _reprime_left <= 0.0 and battle.is_at_will() and dist_t <= RANGE and gap < 1.5:
		# Shaky men fire sooner and from further out; steady men wait.
		shot_timer = randf_range(0.3, 1.2) + steadiness * 1.5

	# Look and animation.
	if shot_timer >= 0.0 and is_valid_target(target):
		face_toward(target.global_position - global_position)
		set_base_anim("aim")
	elif gap > 0.35:
		face_toward(v)
		set_base_anim("walk")
	else:
		_glance_t -= delta
		if _glance_t <= 0.0:
			# Now and then he looks along the line or at the enemy.
			_glance_t = randf_range(2.0, 6.0)
			_glance = 0.0 if randf() < 0.5 else randf_range(-0.5, 0.5)
		var look := _seen_forward
		if dist_t < 25.0 and randf() < 0.02:
			_glance = 0.0
		face_toward(Basis(Vector3.UP, _glance) * look)
		set_base_anim("idle" if loaded else "reload")


## He sees the line's position and facing as they were `reaction` seconds ago,
## so when you wheel or halt the company, the movement ripples through it.
func _update_perception() -> void:
	_history.append([_clock, battle.get_slot_position(slot_index), battle.line_forward])
	while _history.size() > 1 and _clock - float(_history[0][0]) > reaction:
		var old: Array = _history.pop_front()
		_seen_slot = old[1]
		_seen_forward = old[2]
	if _history.size() == 1:
		_seen_slot = _history[0][1]
		_seen_forward = _history[0][2]


## Fighting for his life: face the lizardman, give ground and parry when
## he rears up, keep bayonet distance, and thrust when he's open (right
## after a parry or while he reels). In line orders he won't drift more
## than LEASH from his place; when charging he presses the attack.
func _melee(delta: float, e: Node3D) -> void:
	var to_e := e.global_position - global_position
	to_e.y = 0.0
	var d := to_e.length()
	var dir := to_e / maxf(d, 0.01)
	face_toward(dir)
	var charging: bool = battle.is_charging()
	var he_rears: bool = e.get("target") == self and float(e.get("windup")) >= 0.0
	var he_reels: bool = float(e.get("stagger_time")) > 0.0
	var v := Vector3.ZERO

	if he_rears:
		# He sees the blow coming: musket up and step back.
		blocking = true
		set_base_anim("block")
		v = -dir * BACKPEDAL * pace
	else:
		set_base_anim("guard")
		if melee_timer <= 0.0 and d <= MELEE_RANGE + (0.4 if he_reels else 0.0):
			_thrust(e)
		elif he_reels or charging:
			if d > MELEE_RANGE * 0.8:
				v = dir * 2.4 * pace # press him while he's off balance
		elif d < 1.3:
			v = -dir * 1.0 * pace # keep the bayonet's length between us

	if not charging:
		# Hold the line: don't give or take more ground than the leash allows.
		var from_slot := global_position + v * delta - _seen_slot
		from_slot.y = 0.0
		if from_slot.length() > LEASH and v.dot(from_slot) > 0.0:
			v = Vector3.ZERO
	var push: Vector3 = battle.separation(self, battle.soldiers, 1.0)
	velocity = v + push * 1.5
	move_and_slide()


func _thrust(e: Node3D) -> void:
	melee_timer = MELEE_COOLDOWN * randf_range(0.8, 1.25) / pace
	play_oneshot("thrust", 0.3)
	_punch(Vector3.ONE * 1.08, 0.25)
	if randf() >= 0.75:
		battle.play_sound("swish", global_position + Vector3.UP, -8.0)
		return
	var result := "hit"
	if e.has_method("receive_blow"):
		result = e.receive_blow(MELEE_DAMAGE, self, false)
	else:
		e.take_damage(MELEE_DAMAGE, self)
	if result == "hit":
		battle.play_sound("stab", e.global_position + Vector3.UP, -4.0)
		if e.has_method("stagger"):
			var push := (e.global_position - global_position) * Vector3(1, 0, 1)
			e.stagger(push.normalized() * 2.5, 0.25)


## CHARGE order. Returns false when there's nobody to charge (he then
## regroups on you like FOLLOW).
func _charge(delta: float) -> bool:
	# Badly hurt men fall back behind you instead of dying in the press.
	if hp < WOUNDED:
		var p: Node3D = battle.player
		var back := p.global_position - p.global_transform.basis.z * -3.0 - global_position
		back.y = 0.0
		if back.length() > 1.5:
			velocity = back.normalized() * SPEED * 1.2 * pace
			face_toward(back)
			set_base_anim("walk")
			move_and_slide()
		else:
			set_base_anim("guard")
		return true

	var foe: Node3D = battle.nearest_enemy(global_position, 90.0)
	if foe == null:
		return false
	target = foe
	var to_f := foe.global_position - global_position
	to_f.y = 0.0
	var d := to_f.length()

	# A loaded man may stop to fire first if he has a decent shot.
	if shot_timer < 0.0 and loaded and _reprime_left <= 0.0 and d > 6.0 and d < 22.0 \
			and randf() < delta * (0.4 + steadiness):
		shot_timer = randf_range(0.3, 0.8)
	if shot_timer >= 0.0:
		shot_timer -= delta
		face_toward(to_f)
		set_base_anim("aim")
		velocity = Vector3.ZERO
		if shot_timer < 0.0:
			_shoot()
		return true

	var push: Vector3 = battle.separation(self, battle.soldiers, 1.2)
	velocity = to_f.normalized() * SPEED * 1.25 * pace + push * 2.0
	face_toward(to_f)
	set_base_anim("walk")
	move_and_slide()
	return true


## A parry: if he's blocking and the hack comes from in front, steadier men
## catch it more often, and the lizardman reels, leaving him open.
func take_damage(amount: float, from: Node3D = null) -> void:
	if blocking and alive and from != null and is_instance_valid(from):
		var to_from := from.global_position - global_position
		to_from.y = 0.0
		if facing.dot(to_from.normalized()) > 0.3 and randf() < 0.45 + 0.4 * steadiness:
			battle.play_sound("clang", global_position + Vector3.UP * 1.4, -3.0)
			if from.has_method("stagger"):
				from.stagger(to_from.normalized() * 2.2, 0.45)
			melee_timer = 0.0 # riposte straight away
			return
	super.take_damage(amount, from)


## Called by the company when you order a volley.
func volley() -> void:
	if not alive or not loaded or _reprime_left > 0.0:
		return
	if not is_valid_target(target):
		target = battle.nearest_enemy(global_position, RANGE)
	if is_valid_target(target):
		# He hears the order, presents, takes aim: a ragged ripple, not a crack.
		shot_timer = 0.15 + reaction * 0.4 + randf_range(0.0, 0.25) + steadiness * 0.2


func _shoot() -> void:
	shot_timer = -1.0
	if not alive or not loaded:
		return
	if not is_valid_target(target):
		target = battle.nearest_enemy(global_position, RANGE)
	if not is_valid_target(target):
		return
	var to_t := target.global_position - global_position
	var d := to_t.length()
	var dir := to_t / maxf(d, 0.01)
	face_toward(dir)
	var muzzle := global_position + dir * 0.9 + Vector3.UP * 1.45
	if randf() < MISFIRE_CHANCE:
		# Flash in the pan: a puff by the lock, no shot. Re-prime and try again.
		battle.spawn_flash(muzzle - dir * 0.6)
		battle.play_sound("ramrod", muzzle, -10.0)
		_reprime_left = REPRIME_TIME / pace
		return
	loaded = false
	reload_left = reload_time * randf_range(0.9, 1.15)
	_ram_sound_t = 1.5
	play_oneshot("fire", 0.25)
	battle.spawn_smoke(muzzle, 1.0)
	battle.spawn_flash(muzzle)
	battle.play_sound("musket", muzzle, -2.0)
	# Smoothbore muskets: good odds up close, poor at range; nerves matter.
	var chance := clampf(0.8 - d * 0.014, 0.25, 0.8) * lerpf(0.85, 1.05, steadiness)
	if randf() < chance:
		target.take_damage(100.0)


func _on_died() -> void:
	remove_from_group("friendlies")
	battle.play_sound("grunt", global_position + Vector3.UP * 1.5, -4.0)
	battle.on_soldier_died(self)
