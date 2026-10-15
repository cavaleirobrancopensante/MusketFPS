extends Node3D
## Firing-line prototype.
## You (an officer with a musket) and a company of musketeers hold a field
## against waves of charging lizardmen. Everything is built in code, so the
## scene file is just this one node.
##
## The company is the "squad brain": it owns the line (anchor + facing) and
## hands each soldier a slot. Soldiers and lizardmen themselves stay dumb.

const PlayerScript := preload("res://scripts/player.gd")
const SoldierScript := preload("res://scripts/soldier.gd")
const LizardScript := preload("res://scripts/lizardman.gd")
const HudScript := preload("res://scripts/hud.gd")
const SpriteFactory := preload("res://scripts/sprite_factory.gd")

enum FireMode { ON_COMMAND, AT_WILL }
enum Order { FOLLOW, HOLD }

const COMPANY_SIZE := 8
const LINE_SPACING := 1.5 # metres between men in the line
const LINE_DISTANCE := 0.0 # you stand in the line itself, in the gap at its centre
const REALIGN_ANGLE := 40.0 # degrees you must turn before a following line wheels
const WAVES := [8, 14, 20]
const SPAWN_DISTANCE := 65.0

var fire_mode: int = FireMode.ON_COMMAND
var order: int = Order.FOLLOW
var player
var hud
var soldiers: Array = []
var enemies: Array = []

var line_anchor := Vector3.ZERO
var line_forward := Vector3.FORWARD
var wave := 0
var game_state := "starting" # starting, fighting, between, won, lost
var state_timer := 5.0

var soldier_tex: Texture2D
var lizard_tex: Texture2D
var smoke_tex: Texture2D

var _autotest := false
var _autotest_timer := 0.0


func _ready() -> void:
	_autotest = "--autotest" in OS.get_cmdline_user_args()
	_setup_input()
	soldier_tex = SpriteFactory.soldier_texture()
	lizard_tex = SpriteFactory.lizard_texture()
	smoke_tex = SpriteFactory.smoke_texture()
	_build_world()

	player = PlayerScript.new()
	player.battle = self
	player.position = Vector3(0, 0.1, 8)
	add_child(player)
	player.died.connect(_on_player_died)

	line_forward = Vector3.FORWARD
	line_anchor = Vector3(player.position.x, 0, player.position.z) + line_forward * LINE_DISTANCE
	for i in COMPANY_SIZE:
		var s = SoldierScript.new()
		s.battle = self
		s.sprite_texture = soldier_tex
		soldiers.append(s)
	_reassign_slots()
	for s in soldiers:
		s.position = get_slot_position(s.slot_index)
		add_child(s)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.battle = self
	hud.player = player
	layer.add_child(hud)
	hud.show_message("Form the line! They're coming...", 4.5)


# ---------------------------------------------------------------- orders

func order_follow() -> void:
	order = Order.FOLLOW
	_snap_line_to_player()
	hud.show_message("Company — follow me!", 1.5)


func order_hold() -> void:
	order = Order.HOLD
	_snap_line_to_player() # the line forms where you're looking, then stays
	hud.show_message("Company — halt! Hold here!", 1.5)


func toggle_fire_mode() -> void:
	if fire_mode == FireMode.ON_COMMAND:
		fire_mode = FireMode.AT_WILL
		hud.show_message("Fire at will!", 1.5)
	else:
		fire_mode = FireMode.ON_COMMAND
		hud.show_message("Hold your fire... wait for the order!", 1.5)


func order_volley() -> void:
	if loaded_count() == 0:
		hud.show_message("Nobody's loaded!", 1.0)
		return
	hud.show_message("PRESENT... FIRE!", 1.0)
	for s in soldiers:
		s.volley()


func is_at_will() -> bool:
	return fire_mode == FireMode.AT_WILL


func is_following() -> bool:
	return order == Order.FOLLOW


func loaded_count() -> int:
	var n := 0
	for s in soldiers:
		if s.loaded:
			n += 1
	return n


func restart() -> void:
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- formation

func get_slot_position(index: int) -> Vector3:
	var n := soldiers.size()
	var right := line_forward.cross(Vector3.UP).normalized()
	var offset := (float(index) - (n - 1) * 0.5) * LINE_SPACING
	# Leave a gap at the centre of the line for you, the officer.
	offset += LINE_SPACING * 0.5 * (1.0 if offset >= 0.0 else -1.0)
	return line_anchor + right * offset


func _player_forward() -> Vector3:
	var f: Vector3 = -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _snap_line_to_player() -> void:
	line_forward = _player_forward()
	var p: Vector3 = player.global_position
	line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE
	_reassign_slots()


## Give slots left-to-right by where men currently stand, so nobody crosses
## through the line. Also used to "close ranks" when someone falls.
func _reassign_slots() -> void:
	var right := line_forward.cross(Vector3.UP).normalized()
	var anchor := line_anchor
	soldiers.sort_custom(func(a, b): return (a.position - anchor).dot(right) < (b.position - anchor).dot(right))
	for i in soldiers.size():
		soldiers[i].slot_index = i


func separation(unit: Node3D, group: Array, radius: float) -> Vector3:
	var push := Vector3.ZERO
	var p := unit.global_position
	for o in group:
		if o == unit:
			continue
		var d: Vector3 = p - o.global_position
		d.y = 0.0
		var l := d.length()
		if l < radius and l > 0.001:
			push += d / l * (radius - l) / radius
	return push


func nearest_enemy(from: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for e in enemies:
		var d: float = from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func nearest_friendly(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	if player.alive:
		best = player
		best_d = from.distance_to(player.global_position)
	for s in soldiers:
		var d: float = from.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func on_soldier_died(s) -> void:
	soldiers.erase(s)
	_reassign_slots()
	if soldiers.size() > 0:
		hud.show_message("Man down! Close ranks!", 1.5)
	else:
		hud.show_message("Your company is gone.", 2.5)


func on_enemy_died(e) -> void:
	enemies.erase(e)


# ---------------------------------------------------------------- loop

func _physics_process(_delta: float) -> void:
	if order == Order.FOLLOW and player.alive:
		var p: Vector3 = player.global_position
		var pf := _player_forward()
		if rad_to_deg(pf.angle_to(line_forward)) > REALIGN_ANGLE:
			line_forward = pf
			line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE
			_reassign_slots()
		else:
			line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("volley"):
		order_volley()
	if Input.is_action_just_pressed("order_follow"):
		order_follow()
	if Input.is_action_just_pressed("order_hold"):
		order_hold()
	if Input.is_action_just_pressed("toggle_fire_mode"):
		toggle_fire_mode()

	match game_state:
		"starting", "between":
			state_timer -= delta
			if state_timer <= 0.0:
				_start_wave()
		"fighting":
			if enemies.is_empty():
				if wave >= WAVES.size():
					game_state = "won"
					hud.show_message("Victory! The line held.", 9999.0)
					hud.show_restart()
				else:
					game_state = "between"
					state_timer = 7.0
					hud.show_message("Wave repulsed! Reload and dress the line.", 4.0)

	if _autotest:
		_run_autotest(delta)


func _start_wave() -> void:
	wave += 1
	game_state = "fighting"
	var count: int = WAVES[wave - 1]
	var right := line_forward.cross(Vector3.UP).normalized()
	var centre := line_anchor + line_forward * SPAWN_DISTANCE
	for i in count:
		var l = LizardScript.new()
		l.battle = self
		l.sprite_texture = lizard_tex
		var pos := centre + right * randf_range(-22.0, 22.0) + line_forward * randf_range(0.0, 15.0)
		l.position = Vector3(pos.x, 0, pos.z)
		enemies.append(l)
		add_child(l)
	hud.show_message("Wave %d — %d lizardmen!" % [wave, count], 2.5)
	if _autotest:
		print("wave ", wave, " start: soldiers ", soldiers.size(), " player hp ", player.hp)


func _on_player_died() -> void:
	game_state = "lost"
	hud.show_message("You have fallen.", 9999.0)
	hud.show_restart()


## Headless smoke test: `godot --headless -- --autotest` fires volleys and the
## player's musket on a timer so every code path runs without a human.
func _run_autotest(delta: float) -> void:
	_autotest_timer += delta
	if _autotest_timer > 1.5:
		_autotest_timer = 0.0
		order_volley()
		player.request_fire()
		if wave == 2 and not is_at_will():
			toggle_fire_mode()
	if game_state == "won" or game_state == "lost":
		print("AUTOTEST END: ", game_state, " wave ", wave, " soldiers ", soldiers.size())
		get_tree().quit()


# ---------------------------------------------------------------- effects

func spawn_smoke(pos: Vector3, size_mult: float) -> void:
	var puff := Sprite3D.new()
	puff.texture = smoke_tex
	puff.pixel_size = 0.02 * size_mult
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.modulate = Color(0.78, 0.78, 0.76, 0.75)
	puff.position = pos
	add_child(puff)
	var tw := puff.create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3.ONE * 3.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(puff, "modulate:a", 0.0, 3.0).set_ease(Tween.EASE_IN)
	tw.tween_property(puff, "position:y", pos.y + 1.2, 3.0)
	tw.chain().tween_callback(puff.queue_free)


func spawn_flash(pos: Vector3) -> void:
	var f := Sprite3D.new()
	f.texture = smoke_tex
	f.pixel_size = 0.012
	f.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	f.modulate = Color(1.0, 0.75, 0.3, 1.0)
	f.position = pos
	add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.1)
	tw.tween_callback(f.queue_free)


# ---------------------------------------------------------------- setup

func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("fire", KEY_SPACE)
	_add_key("volley", KEY_F)
	_add_key("order_follow", KEY_1)
	_add_key("order_hold", KEY_2)
	_add_key("toggle_fire_mode", KEY_3)


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.8, 0.8, 0.76)
	sky_mat.ground_horizon_color = Color(0.55, 0.56, 0.48)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.25)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.76, 0.77, 0.73)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false # shadows are expensive on phones
	add_child(sun)

	# Ground: flat field with a noise texture so movement reads.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	add_child(ground)
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	ground.add_child(col)
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.24, 0.34, 0.15))
	ramp.set_color(1, Color(0.42, 0.47, 0.24))
	noise_tex.color_ramp = ramp
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_texture = noise_tex
	ground_mat.uv1_scale = Vector3(40, 40, 1)
	mesh.material_override = ground_mat
	ground.add_child(mesh)

	_scatter_trees()


## Pines around the edges of the field, drawn with MultiMesh (2 draw calls total).
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1725
	var count := 90
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.25
	trunk.height = 2.0
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.13)
	trunk.material = trunk_mat
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.8
	crown.height = 5.0
	crown.radial_segments = 8
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.13, 0.27, 0.15)
	crown.material = crown_mat

	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk
	trunks.instance_count = count
	var crowns := MultiMesh.new()
	crowns.transform_format = MultiMesh.TRANSFORM_3D
	crowns.mesh = crown
	crowns.instance_count = count
	for i in count:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(95.0, 190.0)
		var s := rng.randf_range(0.8, 1.6)
		var pos := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var basis := Basis().scaled(Vector3(s, s, s))
		trunks.set_instance_transform(i, Transform3D(basis, pos + Vector3(0, 1.0 * s, 0)))
		crowns.set_instance_transform(i, Transform3D(basis, pos + Vector3(0, 4.2 * s, 0)))
	var t_inst := MultiMeshInstance3D.new()
	t_inst.multimesh = trunks
	add_child(t_inst)
	var c_inst := MultiMeshInstance3D.new()
	c_inst.multimesh = crowns
	add_child(c_inst)
