extends CharacterBody3D
## You: an officer with a musket. First-person movement, looking, the musket
## (one slow, inaccurate, devastating shot, then a long reload) and the bayonet.
##
## Melee works like Mount & Blade: press to wind up, choose where the blow
## comes from, release to strike. Holding longer charges a heavier blow.
##   OVERHEAD   - comes down from above: big damage, one target
##   LEFT/RIGHT - sweeps across from that side: wide arc, can hit two
##   THRUST     - straight bayonet lunge: longest reach, one target
## Blocking (hold) stops a lizardman's hack from the front and staggers him.

signal fired(hit: bool)
signal melee_hit(count: int)
signal blocked
signal struck_shield # your blow landed on a lizardman's shield
signal shot_hit # one of your musket balls struck a lizardman
signal friendly_fire(by_you: bool) # a ball between you and your men
signal hurt
signal died

enum Swing { NONE = -1, OVERHEAD, LEFT, RIGHT, THRUST }

const Rig3D := preload("res://scripts/rig3d.gd")
const PlayerBody := preload("res://scripts/player_body.gd")

const SPEED := 5.0
const GRAVITY := 20.0
const RELOAD_TIME := 5.5 # bite, prime, close the pan, pour, ram three times, return the rod, cock
const PISTOL_RELOAD := 5.0
const PISTOL_SPEED := 260.0
const PISTOL_SPREAD := 0.034
const PISTOL_AIM_SPREAD := 0.012
const DRAW_TIME := 0.55 # a pistol from the belt or a sabre from the scabbard
## How each blade swings, relative to the bayonet the swings were tuned for:
## [damage x, reach x, strike speed x, recovery speed x].
const BLADES := {"melee": [1.0, 1.0, 1.0, 1.0], "saber": [1.0, 0.85, 1.0, 1.6]}
const RANGE := 90.0
const BALL_SPEED := 340.0
const GRENADES_PER_BATTLE := 3
const THROW_TIME := 0.8 # wind back, throw, recover
const THROW_RELEASE := 0.42 # when in the throw the grenade leaves your hand
const THROW_SPEED := 13.0
const SPREAD := 0.018 # radians of random error per shot from the hip
const AIM_SPREAD := 0.005 # ...and sighting down the barrel
const LOOK_SENS := 0.005 # radians per pixel of drag
const FOV := 72.0
const AIM_FOV := 48.0 # aiming down the sights zooms in
const AIM_TIME := 0.22 # seconds to bring the musket up to your cheek

const FIX_TIME := 1.1 # draw the bayonet from its scabbard and lock it on
const UNFIX_TIME := 0.9
## Reload progress (0..1) at which the ramrod hits bottom: one clink each.
const RAM_STROKES := [0.5, 0.58, 0.66] # (fractions of the reload; see player_body.gd)
const MIN_WINDUP := 0.18 # fastest possible blow
const FULL_CHARGE := 0.8 # hold this long for a fully charged blow
const STRIKE_TIME := 0.16
const RECOVER_TIME := 0.28
const BLOCK_ARC := 70.0 # degrees either side of where you look

## Per-direction tuning. "cone" is degrees either side of where you look.
const SWINGS := {
	Swing.OVERHEAD: {"reach": 2.3, "cone": 30.0, "targets": 1, "damage": 70.0, "charge_damage": 45.0, "knock": 3.5},
	Swing.LEFT: {"reach": 2.2, "cone": 75.0, "targets": 2, "damage": 45.0, "charge_damage": 30.0, "knock": 3.0},
	Swing.RIGHT: {"reach": 2.2, "cone": 75.0, "targets": 2, "damage": 45.0, "charge_damage": 30.0, "knock": 3.0},
	Swing.THRUST: {"reach": 2.8, "cone": 18.0, "targets": 1, "damage": 60.0, "charge_damage": 45.0, "knock": 4.0},
}

var battle
var hp := 100.0
var max_hp := 100.0
var alive := true
var loaded := true
var reload_left := 0.0
var move_input := Vector2.ZERO # set by the HUD joystick, -1..1
var camera: Camera3D
var pitch := 0.0 # looking up (+) or down (-), radians

# 3D mode: your own body, and first/third-person view.
var rig = null
var third_person := false

# Melee state, read by the HUD to animate the viewmodel.
var weapon := "musket" # "musket", "melee" (bayonet fixed), "pistol" or "saber"
# The sidearms you carry (from your kit).
var has_pistol := true
var has_saber := true
var pistol_loaded := true
var pistol_reload_left := 0.0
var _last_pistol_p := 1.0
var switch_from := "musket"
var switch_left := 0.0
var switch_total := 1.0
var switch_target := "musket"
var swing_phase := "idle" # idle, windup, strike, recover
var swing_dir: int = Swing.NONE
var phase_time := 0.0
var strike_charge := 0.0
var blocking := false
var block_held := false

var kills := 0
# From your character sheet (officer.gd) in a campaign; plain values otherwise.
var reload_time := RELOAD_TIME
var spread_mult := 1.0
var speed_mult := 1.0
var melee_mult := 1.0
var saber_mult := 1.3
var block_arc := BLOCK_ARC
var armour := 0.0
var misfire_chance := 0.0
var ammo := -1 # cartridges in your box; -1 = no count (stand-alone battles)
var ammo_used := 0
var _reprime := 0.0
var asleep_left := 0.0 # night camp: still asleep for this long (see battle._setup_camp)
var wake_left := 0.0 # ...then getting up off the bedroll
const WAKE_TIME := 1.5
var _shot := false
var grenades := GRENADES_PER_BATTLE
var throw_left := 0.0
var _thrown := false
var _shake := 0.0
var aim_wanted := false
var aim_amount := 0.0 # 0 = hip, 1 = fully sighted

var _want_fire := false
var _last_reload_p := 1.0
var _bayonet_sound_done := false
var _release_requested := false
var _hit_done := false


func _ready() -> void:
	add_to_group("friendlies")
	collision_layer = 8
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	camera.fov = FOV
	camera.near = 0.03 # so your own musket doesn't clip in first person
	camera.far = 400.0
	add_child(camera)
	camera.make_current()

	# Your own body: arms and musket in first person, the whole officer in third.
	third_person = Settings.third_person
	rig = Rig3D.new()
	rig.kind = "officer"
	if Company.active:
		_apply_sheet()
		rig.gear = Company.officer.get("gear", {})
	rig.manual = true
	add_child(rig)
	var ctrl := PlayerBody.new()
	ctrl.player = self
	ctrl.rig = rig
	add_child(ctrl)
	_update_camera()


## Your attributes, skills and kit (see officer.gd and the YOU screen).
func _apply_sheet() -> void:
	var O = Company.Officer
	max_hp = O.max_hp()
	hp = max_hp
	reload_time = RELOAD_TIME * O.reload_mult()
	spread_mult = O.spread_mult()
	speed_mult = O.speed_mult()
	melee_mult = O.melee_mult()
	saber_mult = O.saber_mult()
	block_arc = O.block_arc()
	armour = O.armour()
	misfire_chance = O.misfire() * 0.5 # you look after your own lock
	ammo = int(Company.officer.get("pack", {}).get("ammo", 30))
	loaded = ammo > 0
	var g: Dictionary = Company.officer.get("gear", {})
	has_pistol = String(g.get("pistol", "")) != ""
	has_saber = String(g.get("sword", "")) != ""
	pistol_loaded = has_pistol and ammo > 1


## 3D mode: switch between first and third person.
func toggle_view() -> void:
	if rig != null:
		third_person = not third_person


func _process(delta: float) -> void:
	if alive:
		# Raise or lower the musket smoothly; the view zooms with it.
		var target := 1.0 if is_aiming() else 0.0
		aim_amount = move_toward(aim_amount, target, delta / AIM_TIME)
		var k := aim_amount * aim_amount * (3.0 - 2.0 * aim_amount)
		camera.fov = lerpf(FOV, AIM_FOV, k)
		_shake = move_toward(_shake, 0.0, delta * 1.5)
		_update_camera()


## Toggle aiming down the sights (musket only). The wish is remembered, so
## the musket comes back up by itself after each reload.
func toggle_aim() -> void:
	if is_gun() and switch_left <= 0.0:
		aim_wanted = not aim_wanted


## Actually sighting right now: wanted, loaded, a gun in hand.
func is_aiming() -> bool:
	return alive and aim_wanted and is_gun() and switch_left <= 0.0 and is_loaded() \
		and throw_left <= 0.0


## A firearm in hand (musket or pistol), or a blade (bayonet or sabre).
func is_gun() -> bool:
	return weapon == "musket" or weapon == "pistol"


func is_melee() -> bool:
	return weapon == "melee" or weapon == "saber"


## The weapon in hand is loaded (for the HUD's FIRE button).
func is_loaded() -> bool:
	return pistol_loaded if weapon == "pistol" else loaded


## The weapons you can take up, in the order of the buttons along the bottom.
func weapons() -> Array:
	var out := ["musket", "melee"]
	if has_pistol:
		out.append("pistol")
	if has_saber:
		out.append("saber")
	return out


## Throw a grenade: musket in your left hand, wind back, lob it in an arc.
func throw_grenade() -> void:
	if not alive or grenades <= 0 or throw_left > 0.0 or switch_left > 0.0 or swing_phase != "idle" \
			or asleep_left > 0.0 or wake_left > 0.0:
		return
	grenades -= 1
	throw_left = THROW_TIME
	_thrown = false
	blocking = false


func is_throwing() -> bool:
	return throw_left > 0.0


## 0..1 through the throw.
func throw_progress() -> float:
	return 1.0 - throw_left / THROW_TIME


## A blast nearby rattles your view (0..1).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _update_throw(delta: float) -> void:
	if throw_left <= 0.0:
		return
	throw_left -= delta
	if not _thrown and throw_progress() >= THROW_RELEASE / THROW_TIME:
		_thrown = true
		# Out of the right hand, along where you look, lofted into an arc.
		var fwd := -camera.global_transform.basis.z
		var right := global_transform.basis.x
		var from := global_position + Vector3.UP * 1.75 + right * 0.25 + _flat_forward() * 0.3
		var vel := fwd * THROW_SPEED + Vector3.UP * 3.5 + Vector3(velocity.x, 0.0, velocity.z) * 0.5
		battle.projectiles.fire("grenade", from, vel, self)
		battle.play_sound_ui("swish", -4.0)
	if throw_left < 0.0:
		throw_left = 0.0


func _update_camera() -> void:
	if third_person and rig != null:
		# Over the right shoulder; the orbit follows your pitch. Aiming pulls
		# the camera in tight over the shoulder (the HUD keeps a small sight).
		var k := aim_amount * aim_amount * (3.0 - 2.0 * aim_amount)
		var pivot := Vector3(lerpf(0.45, 0.72, k), lerpf(1.65, 1.74, k), 0.0)
		var offset := Basis(Vector3.RIGHT, pitch) * Vector3(0.0, lerpf(0.2, 0.06, k), lerpf(2.6, 1.6, k))
		var pos := pivot + offset
		pos.y = maxf(pos.y, 0.35)
		camera.position = pos
	else:
		# Eye at the head; your own torso is hidden in first person, and the
		# arms rise from below the screen, so nothing of you blocks the view.
		camera.position = Vector3(0, 1.64, 0.02)
		# Looking down at yourself, the eye leans out over your chest so you
		# see your coat, belt and boots rather than the inside of your collar.
		var down := clampf((-pitch - 0.25) / 0.8, 0.0, 1.0)
		camera.position += Vector3(0, -0.04, -0.17) * down
	camera.rotation = Vector3(pitch, 0, 0)
	if asleep_left > 0.0 or wake_left > 0.0:
		# On your back by the fire, looking at the stars, then up on your feet.
		var up := 0.0 if asleep_left > 0.0 else 1.0 - wake_left / WAKE_TIME
		up = up * up * (3.0 - 2.0 * up)
		camera.position.y = lerpf(0.32, camera.position.y, up)
		camera.rotation.x = lerpf(1.25, pitch, up)
	if _shake > 0.0:
		var s := _shake * _shake
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.06 * s
		camera.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03 * s


# ---------------------------------------------------------------- called by the HUD

func add_look(drag: Vector2) -> void:
	if not alive:
		return
	# Finer turning while aiming, for steady shots.
	var sens := LOOK_SENS * lerpf(1.0, 0.55, aim_amount)
	rotation.y -= drag.x * sens
	pitch = clampf(pitch - drag.y * sens, -1.2, 1.2)


func request_fire() -> void:
	if asleep_left > 0.0 or wake_left > 0.0:
		return
	_want_fire = true


func toggle_weapon() -> void:
	switch_to("melee" if weapon == "musket" else "musket")


## Take up another weapon: fix or unfix the bayonet, draw the pistol from
## your belt or the sabre from its scabbard (the musket goes over your
## shoulder), or put them away and take up the musket again.
func switch_to(w: String) -> void:
	if not alive or switch_left > 0.0 or swing_phase != "idle" or throw_left > 0.0 or w == weapon:
		return
	if not w in weapons():
		return
	aim_wanted = false
	switch_from = weapon
	switch_target = w
	if (weapon == "musket" and w == "melee") or (weapon == "melee" and w == "musket"):
		switch_total = FIX_TIME if w == "melee" else UNFIX_TIME
	elif w == "melee":
		switch_total = DRAW_TIME + FIX_TIME * 0.8 # musket off the shoulder, then the bayonet
	else:
		switch_total = DRAW_TIME + (0.25 if weapon in ["pistol", "saber"] else 0.0)
	switch_left = switch_total
	_bayonet_sound_done = false


func is_switching() -> bool:
	return switch_left > 0.0


## Start winding up a blow. Returns false if you can't swing right now.
func begin_swing() -> bool:
	if not alive or not is_melee() or switch_left > 0.0 or swing_phase != "idle" or throw_left > 0.0:
		return false
	swing_phase = "windup"
	phase_time = 0.0
	swing_dir = Swing.NONE
	_release_requested = false
	blocking = false
	return true


## Where the blow comes from; can change freely until you release.
func set_swing_dir(dir: int) -> void:
	if swing_phase == "windup":
		swing_dir = dir


func release_swing() -> void:
	if swing_phase == "windup":
		_release_requested = true


func set_block(held: bool) -> void:
	block_held = held


## 0..1 how charged the current wind-up is.
func charge() -> float:
	if swing_phase == "windup":
		return clampf((phase_time - MIN_WINDUP) / (FULL_CHARGE - MIN_WINDUP), 0.0, 1.0)
	if swing_phase == "strike":
		return strike_charge
	return 0.0


## 0 while just fired, 1 when loaded.
func reload_progress() -> float:
	if loaded:
		return 1.0
	return 1.0 - reload_left / reload_time


## How long the cut itself and the recovery take with the blade in hand.
func strike_time() -> float:
	return STRIKE_TIME / float(BLADES.get(weapon, [1, 1, 1, 1])[2])


func recover_time() -> float:
	return RECOVER_TIME / float(BLADES.get(weapon, [1, 1, 1, 1])[3])


## 0..1 through reloading the pistol.
func pistol_reload_progress() -> float:
	if pistol_loaded:
		return 1.0
	return 1.0 - pistol_reload_left / (PISTOL_RELOAD * reload_time / RELOAD_TIME)


## 0..1 through fixing or unfixing the bayonet (1 when not switching).
func switch_progress() -> float:
	if switch_left <= 0.0:
		return 1.0
	return 1.0 - switch_left / switch_total


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if alive:
		_keyboard_controls()

		var input := move_input
		if rig != null and not third_person:
			# Lying down your own arms and musket would fill the screen: show
			# them once you're half up.
			rig.visible = asleep_left <= 0.0 and wake_left < WAKE_TIME * 0.5
		if asleep_left > 0.0:
			asleep_left -= delta
			if asleep_left <= 0.0:
				wake_left = WAKE_TIME
			input = Vector2.ZERO
		elif wake_left > 0.0:
			wake_left = maxf(0.0, wake_left - delta)
			input = Vector2.ZERO
		var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if kb != Vector2.ZERO:
			input = kb
		var speed := SPEED * speed_mult * lerpf(1.0, 0.5, aim_amount)
		if blocking:
			speed *= 0.5
		elif swing_phase != "idle":
			speed *= 0.7
		var dir := global_transform.basis * Vector3(input.x, 0.0, input.y)
		dir.y = 0.0
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

		_update_switch(delta)
		_update_swing(delta)
		blocking = block_held and is_melee() and swing_phase == "idle" and switch_left <= 0.0

		_update_throw(delta)
		if _want_fire:
			_want_fire = false
			if weapon == "musket" and switch_left <= 0.0 and throw_left <= 0.0:
				_fire()
			elif weapon == "pistol" and switch_left <= 0.0 and throw_left <= 0.0:
				_fire_pistol()

		_reprime = maxf(0.0, _reprime - delta)
		# You need both hands on the musket to reload it (and a cartridge).
		if not loaded and weapon == "musket" and switch_left <= 0.0 and ammo != 0:
			reload_left -= delta
			var p := reload_progress()
			for stroke in RAM_STROKES:
				if _last_reload_p < stroke and p >= stroke:
					battle.play_sound_ui("ramrod", -8.0)
			if _last_reload_p < 0.94 and p >= 0.94:
				battle.play_sound_ui("crack", -20.0) # the hammer clicks back
			_last_reload_p = p
			if reload_left <= 0.0:
				loaded = true
				_last_reload_p = 1.0
		# The pistol loads the same way, only while it's in your hand.
		if not pistol_loaded and weapon == "pistol" and switch_left <= 0.0 and ammo != 0:
			pistol_reload_left -= delta
			var pp := pistol_reload_progress()
			if _last_pistol_p < 0.55 and pp >= 0.55:
				battle.play_sound_ui("ramrod", -12.0)
			if _last_pistol_p < 0.92 and pp >= 0.92:
				battle.play_sound_ui("crack", -20.0)
			_last_pistol_p = pp
			if pistol_reload_left <= 0.0:
				pistol_loaded = true
				_last_pistol_p = 1.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


## PC testing: Space fires / winds up, arrow keys pick the blow, Q switches, E blocks.
func _keyboard_controls() -> void:
	if Input.is_action_just_pressed("switch_weapon"):
		toggle_weapon()
	if Input.is_action_just_pressed("grenade"):
		throw_grenade()
	if Input.is_action_just_pressed("aim"):
		toggle_aim()
	if Input.is_action_just_pressed("toggle_view"):
		toggle_view()
	if Input.is_action_just_pressed("block"):
		block_held = true
	if Input.is_action_just_released("block"):
		block_held = false
	if is_gun():
		if Input.is_action_just_pressed("fire"):
			_want_fire = true
		return
	if Input.is_action_just_pressed("fire"):
		begin_swing()
	if swing_phase == "windup":
		if Input.is_action_pressed("swing_up"):
			swing_dir = Swing.OVERHEAD
		elif Input.is_action_pressed("swing_left"):
			swing_dir = Swing.LEFT
		elif Input.is_action_pressed("swing_right"):
			swing_dir = Swing.RIGHT
		elif Input.is_action_pressed("swing_down"):
			swing_dir = Swing.THRUST
	if Input.is_action_just_released("fire"):
		release_swing()


func _update_switch(delta: float) -> void:
	if switch_left <= 0.0:
		return
	switch_left -= delta
	# Time the scrape-and-click so the click lands as the bayonet locks on.
	var click_at := 0.46 if switch_target == "melee" else 0.05
	if switch_target in ["saber", "pistol"]:
		click_at = 0.5
	if not _bayonet_sound_done and switch_progress() >= click_at:
		_bayonet_sound_done = true
		if switch_target == "saber":
			battle.play_sound_ui("swish", -8.0) # the blade rasps out
		elif switch_target == "pistol":
			battle.play_sound_ui("crack", -22.0) # the hammer pulled back
		else:
			battle.play_sound_ui("bayonet", -6.0)
	if switch_left <= 0.0:
		switch_left = 0.0
		weapon = switch_target


func _update_swing(delta: float) -> void:
	match swing_phase:
		"windup":
			phase_time += delta
			if _release_requested and phase_time >= MIN_WINDUP:
				strike_charge = charge()
				if swing_dir == Swing.NONE:
					swing_dir = Swing.THRUST # a quick tap is a thrust
				swing_phase = "strike"
				phase_time = 0.0
				_hit_done = false
		"strike":
			phase_time += delta
			var quick: float = BLADES.get(weapon, [1, 1, 1, 1])[2]
			if not _hit_done and phase_time >= STRIKE_TIME * 0.5 / quick:
				_hit_done = true
				_apply_melee()
			if phase_time >= STRIKE_TIME / quick:
				swing_phase = "recover"
				phase_time = 0.0
		"recover":
			phase_time += delta
			if phase_time >= recover_time():
				swing_phase = "idle"
				phase_time = 0.0
				swing_dir = Swing.NONE


func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _apply_melee() -> void:
	var data: Dictionary = SWINGS[swing_dir]
	var blade: Array = BLADES.get(weapon, [1.0, 1.0, 1.0])
	var reach: float = float(data["reach"]) * float(blade[1])
	var cone: float = data["cone"]
	var fwd := _flat_forward()
	var candidates := []
	for e in battle.enemies:
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach or d < 0.01:
			continue
		if rad_to_deg(fwd.angle_to(to)) > cone:
			continue
		candidates.append([d, e])
	candidates.sort_custom(func(a, b): return a[0] < b[0])

	var damage: float = (data["damage"] + data["charge_damage"] * strike_charge) * float(blade[0])
	if weapon == "saber":
		# A sabre is made for cutting: the slashes bite, the thrust less so.
		damage *= saber_mult * (0.75 if swing_dir == Swing.THRUST else 1.0)
	else:
		damage *= melee_mult
	var knock: float = data["knock"] * (1.0 + strike_charge * 0.5)
	var right := global_transform.basis.x
	var count := 0
	var shielded := 0
	for c in candidates:
		if count >= int(data["targets"]):
			break
		var e = c[1]
		var push: Vector3 = (e.global_position - global_position) * Vector3(1, 0, 1)
		push = push.normalized()
		# Side blows also shove sideways, in the direction of the sweep.
		if swing_dir == Swing.LEFT:
			push = (push + right * 0.6).normalized()
		elif swing_dir == Swing.RIGHT:
			push = (push - right * 0.6).normalized()
		# A charged blow (70%+) smashes through a raised shield.
		var result: String = e.receive_blow(damage, self, strike_charge >= 0.7)
		if result == "blocked":
			shielded += 1
			continue
		if result == "hit":
			e.stagger(push * knock, 0.35 + 0.25 * strike_charge)
		count += 1
	if count > 0:
		battle.play_sound_ui("stab", -2.0)
	elif shielded == 0:
		battle.play_sound_ui("swish", -6.0)
	if shielded > 0:
		struck_shield.emit()
	melee_hit.emit(count)


func _fire() -> void:
	if not loaded and ammo == 0:
		battle.hud.show_message("Your cartridge box is empty!", 1.2)
		return
	if not loaded or _reprime > 0.0:
		return
	if randf() < misfire_chance:
		# A flash in the pan: prime it again.
		_reprime = 1.2
		battle.play_sound_ui("crack", -10.0)
		battle.hud.show_message("Misfire!", 1.0)
		return
	loaded = false
	reload_left = reload_time
	if ammo > 0:
		ammo -= 1
		ammo_used += 1
	_last_reload_p = 0.0
	battle.play_sound_ui("musket", 0.0)

	# The ball leaves along your line of sight (so it goes where the crosshair
	# is), starting level with you so in third person it can't hit the men
	# behind you. It flies, drops, and hits whatever is first in its path.
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var to_me := global_position + Vector3.UP * 1.5 - from
	from += fwd * maxf(0.4, to_me.dot(fwd))
	var spread := lerpf(SPREAD, AIM_SPREAD, aim_amount) * spread_mult
	fwd = battle.projectiles.spread_dir(fwd, spread)
	battle.projectiles.fire("ball", from, fwd * BALL_SPEED, self)
	var hit := false

	var right := camera.global_transform.basis.x
	if rig != null:
		var muzzle: Vector3 = rig.muzzle_global()
		battle.spawn_smoke(muzzle + fwd * 1.2, 0.8)
		battle.spawn_flash(muzzle + fwd * 0.1)
	else:
		battle.spawn_smoke(from + fwd * 2.5 + right * 0.4 - Vector3.UP * 0.3, 0.8)
		battle.spawn_flash(from + fwd * 1.2 + right * 0.3 - Vector3.UP * 0.25)
	fired.emit(hit)


## The pistol: one quick shot, short-ranged and wild, then a slow reload.
func _fire_pistol() -> void:
	if not pistol_loaded and ammo == 0:
		battle.hud.show_message("Your cartridge box is empty!", 1.2)
		return
	if not pistol_loaded:
		return
	if randf() < misfire_chance * 1.5:
		battle.play_sound_ui("crack", -10.0)
		battle.hud.show_message("The pistol misfires!", 1.0)
		return
	pistol_loaded = false
	pistol_reload_left = PISTOL_RELOAD * reload_time / RELOAD_TIME
	_last_pistol_p = 0.0
	if ammo > 0:
		ammo -= 1
		ammo_used += 1
	battle.play_sound_ui("musket", -3.0)
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var to_me := global_position + Vector3.UP * 1.5 - from
	from += fwd * maxf(0.4, to_me.dot(fwd))
	fwd = battle.projectiles.spread_dir(fwd, lerpf(PISTOL_SPREAD, PISTOL_AIM_SPREAD, aim_amount) * spread_mult)
	battle.projectiles.fire("pistol", from, fwd * PISTOL_SPEED, self)
	if rig != null:
		var muzzle: Vector3 = rig.pistol_muzzle_global()
		battle.spawn_smoke(muzzle + fwd * 0.6, 0.5)
		battle.spawn_flash(muzzle + fwd * 0.05, 0.7)
	_shake = maxf(_shake, 0.25)
	fired.emit(false)


## Called by the projectile system when one of your balls hits someone.
func on_projectile_hit(u: Node3D) -> void:
	var kind = u.get("rig_kind")
	if kind == "lizard":
		shot_hit.emit()
	elif kind == "soldier":
		friendly_fire.emit(true)


## A ball or a blast: can't be parried.
func take_shot(amount: float, from: Node3D = null) -> void:
	_shot = true
	take_damage(amount, from)
	_shot = false
	if from != null and is_instance_valid(from) and from != self and from.is_in_group("friendlies"):
		friendly_fire.emit(false)


func take_damage(amount: float, from: Node3D = null) -> void:
	if not alive:
		return
	if asleep_left > 0.0:
		asleep_left = 0.01 # that wakes you
	if blocking and not _shot and from != null and is_instance_valid(from):
		var to := from.global_position - global_position
		to.y = 0.0
		if rad_to_deg(_flat_forward().angle_to(to)) <= block_arc:
			# Parried: no damage, and the attacker reels back.
			if from.has_method("stagger"):
				from.stagger(to.normalized() * 2.5, 0.5)
			battle.play_sound_ui("clang", -3.0)
			blocked.emit()
			return
	if not _shot:
		amount *= 1.0 - armour # your coat turns some of a hack
	hp -= amount
	battle.play_sound_ui("stab", -4.0)
	battle.play_sound_ui("grunt", -6.0)
	hurt.emit()
	if hp <= 0.0:
		hp = 0.0
		alive = false
		var tw := create_tween().set_parallel(true)
		tw.tween_property(camera, "position:y", 0.3, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(camera, "rotation:z", 0.6, 0.8)
		died.emit()
