extends CharacterBody3D
## You: an officer with a musket. First-person movement, looking, and the
## musket itself (one slow, inaccurate, devastating shot, then a long reload).

signal fired(hit: bool)
signal hurt
signal died

const SPEED := 5.0
const GRAVITY := 20.0
const RELOAD_TIME := 3.5
const RANGE := 90.0
const SPREAD := 0.012 # radians of random error per shot
const LOOK_SENS := 0.005 # radians per pixel of drag

var battle
var hp := 100.0
var max_hp := 100.0
var alive := true
var loaded := true
var reload_left := 0.0
var move_input := Vector2.ZERO # set by the HUD joystick, -1..1
var camera: Camera3D
var _want_fire := false


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


func add_look(drag: Vector2) -> void:
	if not alive:
		return
	rotation.y -= drag.x * LOOK_SENS
	camera.rotation.x = clampf(camera.rotation.x - drag.y * LOOK_SENS, -1.2, 1.2)


func request_fire() -> void:
	_want_fire = true


## 0 while just fired, 1 when loaded.
func reload_progress() -> float:
	if loaded:
		return 1.0
	return 1.0 - reload_left / RELOAD_TIME


## How far the musket is lowered for reloading (0 = shouldered, 1 = fully down).
func reload_lowered() -> float:
	if loaded:
		return 0.0
	var elapsed := RELOAD_TIME - reload_left
	return clampf(minf(elapsed - 0.25, reload_left) / 0.35, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if alive:
		var input := move_input
		var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if kb != Vector2.ZERO:
			input = kb
		var dir := global_transform.basis * Vector3(input.x, 0.0, input.y)
		dir.y = 0.0
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED

		if Input.is_action_just_pressed("fire"):
			_want_fire = true
		if _want_fire:
			_want_fire = false
			_fire()

		if not loaded:
			reload_left -= delta
			if reload_left <= 0.0:
				loaded = true
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func _fire() -> void:
	if not loaded:
		return
	loaded = false
	reload_left = RELOAD_TIME

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
			collider.call("take_damage", 100.0)
			hit = true

	var right := camera.global_transform.basis.x
	battle.spawn_smoke(from + fwd * 2.5 + right * 0.4 - Vector3.UP * 0.3, 0.8)
	battle.spawn_flash(from + fwd * 1.2 + right * 0.3 - Vector3.UP * 0.25)
	fired.emit(hit)


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	hurt.emit()
	if hp <= 0.0:
		hp = 0.0
		alive = false
		var tw := create_tween().set_parallel(true)
		tw.tween_property(camera, "position:y", 0.3, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(camera, "rotation:z", 0.6, 0.8)
		died.emit()
