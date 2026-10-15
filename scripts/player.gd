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
signal hurt
signal died

enum Swing { NONE = -1, OVERHEAD, LEFT, RIGHT, THRUST }

const SPEED := 5.0
const GRAVITY := 20.0
const RELOAD_TIME := 3.5
const RANGE := 90.0
const SPREAD := 0.012 # radians of random error per shot
const LOOK_SENS := 0.005 # radians per pixel of drag

const FIX_TIME := 1.1 # draw the bayonet from its scabbard and lock it on
const UNFIX_TIME := 0.9
## Reload progress (0..1) at which the ramrod hits bottom: one clink each.
const RAM_STROKES := [0.46, 0.58, 0.70]
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

# Melee state, read by the HUD to animate the viewmodel.
var weapon := "musket" # "musket" or "melee"
var switch_left := 0.0
var switch_total := 1.0
var switch_target := "musket"
var swing_phase := "idle" # idle, windup, strike, recover
var swing_dir: int = Swing.NONE
var phase_time := 0.0
var strike_charge := 0.0
var blocking := false
var block_held := false

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
	camera.fov = 72.0
	camera.far = 400.0
	add_child(camera)
	camera.make_current()


# ---------------------------------------------------------------- called by the HUD

func add_look(drag: Vector2) -> void:
	if not alive:
		return
	rotation.y -= drag.x * LOOK_SENS
	camera.rotation.x = clampf(camera.rotation.x - drag.y * LOOK_SENS, -1.2, 1.2)


func request_fire() -> void:
	_want_fire = true


func toggle_weapon() -> void:
	if not alive or switch_left > 0.0 or swing_phase != "idle":
		return
	switch_target = "melee" if weapon == "musket" else "musket"
	switch_total = FIX_TIME if switch_target == "melee" else UNFIX_TIME
	switch_left = switch_total
	_bayonet_sound_done = false


func is_switching() -> bool:
	return switch_left > 0.0


## Start winding up a blow. Returns false if you can't swing right now.
func begin_swing() -> bool:
	if not alive or weapon != "melee" or switch_left > 0.0 or swing_phase != "idle":
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
	return 1.0 - reload_left / RELOAD_TIME


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
		var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if kb != Vector2.ZERO:
			input = kb
		var speed := SPEED
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
		blocking = block_held and weapon == "melee" and swing_phase == "idle" and switch_left <= 0.0

		if _want_fire:
			_want_fire = false
			if weapon == "musket" and switch_left <= 0.0:
				_fire()

		# You need both hands on the musket to reload it.
		if not loaded and weapon == "musket" and switch_left <= 0.0:
			reload_left -= delta
			var p := reload_progress()
			for stroke in RAM_STROKES:
				if _last_reload_p < stroke and p >= stroke:
					battle.play_sound_ui("ramrod", -8.0)
			_last_reload_p = p
			if reload_left <= 0.0:
				loaded = true
				_last_reload_p = 1.0
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
	if Input.is_action_just_pressed("block"):
		block_held = true
	if Input.is_action_just_released("block"):
		block_held = false
	if weapon == "musket":
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
	if not _bayonet_sound_done and switch_progress() >= click_at:
		_bayonet_sound_done = true
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
			if not _hit_done and phase_time >= STRIKE_TIME * 0.5:
				_hit_done = true
				_apply_melee()
			if phase_time >= STRIKE_TIME:
				swing_phase = "recover"
				phase_time = 0.0
		"recover":
			phase_time += delta
			if phase_time >= RECOVER_TIME:
				swing_phase = "idle"
				phase_time = 0.0
				swing_dir = Swing.NONE


func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _apply_melee() -> void:
	var data: Dictionary = SWINGS[swing_dir]
	var reach: float = data["reach"]
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

	var damage: float = data["damage"] + data["charge_damage"] * strike_charge
	var knock: float = data["knock"] * (1.0 + strike_charge * 0.5)
	var right := global_transform.basis.x
	var count := 0
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
		e.take_damage(damage, self)
		e.stagger(push * knock, 0.35 + 0.25 * strike_charge)
		count += 1
	battle.play_sound_ui("stab" if count > 0 else "swish", -2.0 if count > 0 else -6.0)
	melee_hit.emit(count)


func _fire() -> void:
	if not loaded:
		return
	loaded = false
	reload_left = RELOAD_TIME
	_last_reload_p = 0.0
	battle.play_sound_ui("musket", 0.0)

	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var err := Vector3(randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD))
	fwd = (fwd + err).normalized()
	# Layer 2 = enemies only (no friendly fire in this prototype).
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * RANGE, 2)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var hit := false
	if not result.is_empty():
		var collider: Object = result["collider"]
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", 100.0, self)
			hit = true

	var right := camera.global_transform.basis.x
	battle.spawn_smoke(from + fwd * 2.5 + right * 0.4 - Vector3.UP * 0.3, 0.8)
	battle.spawn_flash(from + fwd * 1.2 + right * 0.3 - Vector3.UP * 0.25)
	fired.emit(hit)


func take_damage(amount: float, from: Node3D = null) -> void:
	if not alive:
		return
	if blocking and from != null and is_instance_valid(from):
		var to := from.global_position - global_position
		to.y = 0.0
		if rad_to_deg(_flat_forward().angle_to(to)) <= BLOCK_ARC:
			# Parried: no damage, and the attacker reels back.
			if from.has_method("stagger"):
				from.stagger(to.normalized() * 2.5, 0.5)
			battle.play_sound_ui("clang", -3.0)
			blocked.emit()
			return
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
