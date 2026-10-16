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
## Animations: idle, walk, aim (musket levelled, shot coming), fire, reload
## (ramming), guard (bayonet charged) and thrust.

const SPEED := 3.8
const RANGE := 40.0
const MELEE_RANGE := 1.8
const MELEE_DAMAGE := 34.0
const MELEE_COOLDOWN := 1.2
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

	# Bayonet: stand and fight when a lizardman is on top of us.
	if dist_t <= MELEE_RANGE:
		velocity = Vector3.ZERO
		face_toward(target.global_position - global_position)
		set_base_anim("guard")
		if melee_timer <= 0.0:
			melee_timer = MELEE_COOLDOWN * randf_range(0.8, 1.25) / pace
			play_oneshot("thrust", 0.3)
			_punch(Vector3.ONE * 1.08, 0.25)
			if randf() < 0.75:
				var push := (target.global_position - global_position) * Vector3(1, 0, 1)
				target.take_damage(MELEE_DAMAGE, self)
				battle.play_sound("stab", target.global_position + Vector3.UP, -4.0)
				if target.has_method("stagger"):
					target.stagger(push.normalized() * 2.5, 0.25)
			else:
				battle.play_sound("swish", global_position + Vector3.UP, -8.0)
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
