extends Node3D
## The opening cutscene, played in the engine: the troopship in a storm, the
## wreck on uncharted rocks, the survivors rowing ashore at dawn, and the
## regiment digging in on the beach. Then the battle (the tutorial).
## Tap SKIP to go straight to the beach.
##
## A timeline of shots: each has a start time, a camera move and whatever
## happens in it (see _process). Names come from lore.gd.

const Props := preload("res://scripts/props.gd")
const Lore := preload("res://scripts/lore.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const SoundFactory := preload("res://scripts/sound_factory.gd")
const BATTLE := "res://scenes/battle.tscn"

const ROCKS_AT := Vector3(-25, 0, 130) # where she strikes (seen from the beach later)
const LENGTH := 30.0

var _t := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D
var _ship: Node3D
var _sea: MeshInstance3D
var _rain: CPUParticles3D
var _boats: Array = []
var _beach: Node3D
var _men: Array = []
var _caption: Label
var _band: ColorRect
var _fade: ColorRect
var _sounds := {}
var _storm: AudioStreamPlayer
var _surf: AudioStreamPlayer
var _flash := 0.0
var _flashes := [1.8, 4.7, 6.6, 10.25, 12.0]
var _struck := false
var _dawn := false
var _shake := 0.0
var _done := false
var _captions := [
	[0.6, 6.2, "Three weeks out of port, the troopship %s carries %s to the colonies." % [Lore.SHIP, Lore.REGIMENT]],
	[7.2, 12.6, "A storm drives her far off course, onto rocks no chart has ever shown."],
	[14.6, 20.4, "Dawn. Of eight hundred souls aboard, some three hundred reach the shore of an unknown land."],
	[21.2, 29.0, "%s has the guns hauled ashore and the beach entrenched. By noon the scouts hear drums in the forest." % Lore.COMMANDER],
]


func _ready() -> void:
	var batcher := BatcherScript.new()
	batcher.add_to_group("batcher")
	add_child(batcher)
	_sounds = {"thunder": SoundFactory.thunder(), "crack": SoundFactory.crack(), "cannon": SoundFactory.cannon()}

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-40, 150, 0)
	add_child(_sun)

	_sea = Props.sea(900.0, 1.6, 1.4)
	_sea.position = Vector3(0, -0.3, 200)
	add_child(_sea)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	add_child(Props.rocks(ROCKS_AT + Vector3(6, -1.5, -14), 7, 3.5, rng))
	add_child(Props.rocks(ROCKS_AT + Vector3(-10, -1.5, -4), 5, 2.5, rng))

	_ship = Props.ship()
	_ship.position = Vector3(-25, 0, 300)
	add_child(_ship)

	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 900.0
	add_child(_cam)
	_rain = _make_rain()
	_cam.add_child(_rain)

	_build_beach()
	_build_overlay()
	_set_storm(true)

	_storm = _loop(SoundFactory.storm(), -6.0)
	_surf = _loop(SoundFactory.surf(), -80.0)


func _loop(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _play(name: String, db: float, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[name]
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _make_rain() -> CPUParticles3D:
	var r := CPUParticles3D.new()
	r.amount = 700
	r.lifetime = 0.7
	r.local_coords = false
	r.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	r.emission_box_extents = Vector3(18, 1, 18)
	r.position = Vector3(0, 9, -8)
	r.direction = Vector3(0.25, -1, 0)
	r.spread = 4.0
	r.initial_velocity_min = 26.0
	r.initial_velocity_max = 32.0
	r.gravity = Vector3.ZERO
	var m := BoxMesh.new()
	m.size = Vector3(0.015, 0.7, 0.015)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.8, 0.85, 0.35)
	m.material = mat
	r.mesh = m
	return r


## The beach (hidden until dawn): sand, the earthworks, guns, and men at work.
func _build_beach() -> void:
	_beach = Node3D.new()
	_beach.visible = false
	add_child(_beach)
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 120)
	pm.material = Props._mat(Props.SAND)
	sand.mesh = pm
	sand.position = Vector3(0, 0.0, -10)
	_beach.add_child(sand)
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(400, 200)
	gm.material = Props._mat(Color(0.22, 0.3, 0.2))
	grass.mesh = gm
	grass.position = Vector3(0, 0.02, -140)
	_beach.add_child(grass)
	var works := Props.earthwork(80.0, [-15.5, 15.5])
	works.position = Vector3(0, 0, 5)
	_beach.add_child(works)
	for x in [-15.5, 15.5, -37.0, 37.0]:
		var g := Props.cannon()
		g.position = Vector3(x, 0, 7.0)
		_beach.add_child(g)
	# The forest beyond: tall, dark, a little strange.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 70:
		var pos := Vector3(rng.randf_range(-150, 150), 0, rng.randf_range(-85, -140))
		var h := rng.randf_range(9.0, 18.0)
		Props._cyl(_beach, 0.25, 0.45, h, Color(0.25, 0.2, 0.18), pos + Vector3(0, h * 0.5, 0))
		var crown := Props._cyl(_beach, 0.0, rng.randf_range(2.5, 4.0), h * 0.6, Color(0.12, 0.26, 0.24), pos + Vector3(0, h * 0.95, 0))
		crown.scale = Vector3.ONE
	# Men digging, hauling and standing guard.
	for i in 22:
		var r := Rig3D.new()
		r.kind = "soldier"
		r.gear = {"head": "" if i % 3 == 0 else "shako", "torso": "shirt" if i % 2 == 0 else "coat"}
		r.position = Vector3(rng.randf_range(-36, 36), 0, rng.randf_range(6.5, 14.0))
		r.facing = Vector3(rng.randf_range(-0.4, 0.4), 0, -1).normalized()
		r.anim = "reload" if i % 2 == 0 else "idle" # ramming looks like digging from here
		r.anim_time = rng.randf() * 3.0
		_beach.add_child(r)
		_men.append(r)
	for i in 3:
		var b := Props.longboat()
		b.position = Vector3(-14 + i * 12, 0.2, 98 + i * 7)
		b.rotation.y = PI
		add_child(b)
		b.visible = false
		_boats.append(b)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_band = ColorRect.new()
	_band.color = Color(0, 0, 0, 0.45)
	_band.anchor_left = 0.0
	_band.anchor_right = 1.0
	_band.anchor_top = 1.0
	_band.anchor_bottom = 1.0
	_band.offset_top = -150
	_band.offset_bottom = -40
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_band)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_band.add_child(_caption)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	var skip := Button.new()
	skip.text = "SKIP  ▸"
	skip.add_theme_font_size_override("font_size", 22)
	skip.position = Vector2(20, 20)
	skip.size = Vector2(150, 56)
	skip.pressed.connect(_finish)
	root.add_child(skip)


## Night storm or grey dawn.
func _set_storm(on: bool) -> void:
	if on:
		_env.background_color = Color(0.03, 0.04, 0.06)
		_env.ambient_light_color = Color(0.35, 0.4, 0.5)
		_env.ambient_light_energy = 0.5
		_env.fog_light_color = Color(0.05, 0.06, 0.08)
		_env.fog_density = 0.008
		_sun.light_energy = 0.15
		_sun.light_color = Color(0.6, 0.7, 0.9)
	else:
		_env.background_color = Color(0.72, 0.74, 0.74)
		_env.ambient_light_color = Color(0.8, 0.8, 0.78)
		_env.ambient_light_energy = 0.7
		_env.fog_light_color = Color(0.75, 0.76, 0.74)
		_env.fog_density = 0.009
		_sun.light_energy = 0.9
		_sun.light_color = Color(1.0, 0.92, 0.8)
		_sun.rotation_degrees = Vector3(-18, 200, 0)
		var mat := _sea.mesh.material as ShaderMaterial
		mat.set_shader_parameter("height", 0.12)
		mat.set_shader_parameter("speed", 0.6)
		mat.set_shader_parameter("deep", Color(0.16, 0.28, 0.32))
		mat.set_shader_parameter("crest", Color(0.55, 0.65, 0.66))
		_rain.emitting = false
		_beach.visible = true
		for b in _boats:
			b.visible = true
		# The wreck where she struck, heeled over on the rocks.
		_ship.position = ROCKS_AT + Vector3(0, -1.2, 0)
		_ship.rotation = Vector3(-0.1, 0.5, 0.38)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var t := _t
	_update_caption(t)
	_fade.color.a = _fade_amount(t)

	# Lightning.
	for f in _flashes:
		if t - delta < f and t >= f:
			_flash = 1.0
			_play("thunder", -4.0, randf_range(0.8, 1.1))
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	if not _dawn:
		var lit := _flash * (0.7 + 0.3 * sin(t * 60.0))
		_env.background_color = Color(0.03, 0.04, 0.06).lerp(Color(0.6, 0.65, 0.8), lit)
		_env.ambient_light_energy = 0.5 + lit * 2.0
		_sun.light_energy = 0.15 + lit * 3.0

	if t < 7.0:
		_shot_storm(t, delta)
	elif t < 13.8:
		_shot_strike(t, delta)
	elif t < 21.0:
		if not _dawn:
			_dawn = true
			_set_storm(false)
			_storm.volume_db = -80.0
			_surf.volume_db = -10.0
		_shot_boats(t - 13.8, delta)
	elif t < LENGTH:
		_shot_beach(t - 21.0)
	else:
		_finish()


## Following the ship through the storm, rolling and pitching.
func _shot_storm(t: float, delta: float) -> void:
	_ship.position.z -= 7.0 * delta
	_rock_ship(t, 1.0)
	var at := _ship.position + Vector3(22, 7 + sin(t * 0.8), 18 - t * 1.2)
	_cam.transform = Transform3D(Basis.looking_at(_ship.position + Vector3(0, 5, -4) - at), at)


## Ahead of her: the rocks loom, she strikes, the mainmast comes down.
func _shot_strike(t: float, delta: float) -> void:
	var strike := 10.2
	if t < strike:
		var k := (t - 7.0) / (strike - 7.0)
		_ship.position = Vector3(-25, 0, lerpf(205.0, ROCKS_AT.z + 14.0, k * k))
		_rock_ship(t, 1.0)
	else:
		if not _struck:
			_struck = true
			_shake = 1.0
			_play("crack", 2.0)
			_play("cannon", -2.0, 0.5)
		var k2 := clampf((t - strike) / 1.6, 0.0, 1.0)
		_ship.rotation = Vector3(-0.12 * k2, 0, 0.38 * k2 + sin(t * 2.0) * 0.02)
		_ship.position.y = -1.2 * k2
		var mast := _ship.get_node("main_mast") as Node3D
		mast.rotation.x = lerpf(0.0, 1.25, clampf((t - strike - 0.4) / 1.4, 0.0, 1.0))
		var fore := _ship.get_node("fore_mast") as Node3D
		fore.rotation.z = lerpf(0.0, -0.5, clampf((t - strike - 0.9) / 1.6, 0.0, 1.0))
	_shake = move_toward(_shake, 0.0, delta * 0.8)
	var at := ROCKS_AT + Vector3(26, 7, -8)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.6
	_cam.transform = Transform3D(Basis.looking_at(_ship.position + Vector3(0, 5, 0) - at), at + jitter)


func _rock_ship(t: float, amount: float) -> void:
	_ship.rotation.z = sin(t * 1.3) * 0.16 * amount
	_ship.rotation.x = sin(t * 0.9 + 1.0) * 0.07 * amount
	_ship.position.y = sin(t * 1.1) * 0.8 * amount


## Dawn: the boats pull for the beach, the wreck behind them.
func _shot_boats(t: float, delta: float) -> void:
	for i in _boats.size():
		var b: Node3D = _boats[i]
		b.position.z -= (7.0 + i) * delta
		b.position.y = 0.15 + sin(t * 1.5 + i) * 0.12
		b.rotation.z = sin(t * 1.2 + i) * 0.04
	var at := Vector3(6 + t * 0.5, 2.6, 58)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(-12, 2, 115) - at), at)


## The beach: a slow dolly along the earthworks toward the silent forest.
func _shot_beach(t: float) -> void:
	for r in _men:
		r.anim_time += get_process_delta_time()
	var at := Vector3(-30 + t * 3.2, 3.2 - t * 0.08, 22 - t * 0.6)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(-12 + t * 3.0, 1.0, -40) - at), at)


func _fade_amount(t: float) -> float:
	if t < 0.8:
		return 1.0 - t / 0.8
	if t > 12.8 and t < 14.6:
		return clampf(1.0 - absf(t - 13.8) / 0.8, 0.0, 1.0)
	if t > LENGTH - 1.2:
		return clampf((t - (LENGTH - 1.2)) / 1.2, 0.0, 1.0)
	return 0.0


func _update_caption(t: float) -> void:
	var text := ""
	var a := 0.0
	for c in _captions:
		if t >= float(c[0]) and t <= float(c[1]):
			text = c[2]
			a = clampf(minf(t - float(c[0]), float(c[1]) - t) / 0.5, 0.0, 1.0)
	_caption.text = text
	_band.visible = text != ""
	_band.modulate.a = a


func _finish() -> void:
	if _done:
		return
	_done = true
	if "--intro" in OS.get_cmdline_user_args():
		print("INTRO DONE at %.1fs" % _t)
		get_tree().quit()
		return
	get_tree().change_scene_to_file(BATTLE)
