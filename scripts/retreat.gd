extends Node3D
## The cutscene after the first battle (the prologue's lost fight), before
## the aftermath screen. A timeline of shots, like intro.gd:
##
##   the rout        what's left of the company runs along the sand for the
##                   cliff path, men turning to fire at the lizards behind
##   the rearguard   at the foot of the path a handful kneel and give them a
##                   last volley; the lizards stop, hiss, and turn back
##   the glass       from the ridge, through the Major's spyglass: the beach,
##                   the lizards stripping the dead, and worse
##   the cart        in the gully, the ammunition cart, overturned but whole:
##                   righted and hauled up
##   nothing left    more and more of them out of the trees, tearing down the
##                   works, breaking up the boats
##   we must go      the column turns inland, into the evening
##
## Everyone who speaks has a voice (sound_factory.gd's talk), the sergeant
## shouts his orders. Tap Skip for the aftermath.

const Props := preload("res://scripts/props.gd")
const Lore := preload("res://scripts/lore.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const SoundFactory := preload("res://scripts/sound_factory.gd")
const Look := preload("res://scripts/look.gd")
const UI := preload("res://scripts/ui.gd")
const AFTERMATH := "res://scenes/aftermath.tscn"

const T_REAR := 9.0
const T_GLASS := 17.0
const T_CART := 29.0
const T_RUIN := 36.5
const T_GO := 46.0
const LENGTH := 54.0
const SHORE_Z := 50.0
const RIDGE := Vector3(132, 14, 8) # the top of the cliff path, where they look back from
const GULLY := Vector3(118, 0, 34)

var _t := 0.0
var _cam: Camera3D
var _caption: Label
var _band: ColorRect
var _fade: ColorRect
var _glass: Control
var _sounds := {}
var _done := false
var _snaps: Array = []
var _rigs: Array = [] # every rig, to advance their animations
var _sarge := "Sergeant"

# The shots' actors.
var _runners: Array = [] # [holder, rig, speed, fire_at]
var _chasers: Array = [] # [holder, rig, speed, stop_x, dead_at]
var _rear: Array = [] # the kneeling rank
var _looters: Array = []
var _boats: Array = []
var _works: Array = [] # earthwork pieces to tear down
var _horde: Array = [] # [holder, rig, from, to, start]
var _cart: Node3D
var _haulers: Array = []
var _column: Array = [] # [holder, rig, offset]
var _col_cart: Node3D
var _fired := {}
var _captions: Array = []
var _voices: Array = [] # [time, sound, pitch, db]
var _fire_light: OmniLight3D
var _birds: Array = [] # [node, angle, radius, height, speed]
var _dust: Dictionary = {} # holder -> CPUParticles3D (sand kicked up by running feet)
var _javelin: Node3D
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_fov := 55.0
var _cam_cut := true # the next camera move snaps (a cut), not glides
var _shake := 0.0
var _shot_name := ""
var _sergeant: Array = []
var _colour: Node3D # the colours carried in the column
var _splinters: Array = []
var _feast: Array = [] # the lizards' fire and its smoke (lit once the beach is theirs)


func _ready() -> void:
	Music.set_context("intro")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snaps="):
			for v in a.substr(8).split(","):
				_snaps.append(float(v))
	var batcher := BatcherScript.new()
	batcher.add_to_group("batcher")
	add_child(batcher)
	var all := SoundFactory.cached()
	for k in ["musket", "shout", "drum", "hiss", "roar", "talk1", "talk2", "talk3", "talk4", "crack", "thud", "surf", "grunt"]:
		if all.has(k):
			_sounds[k] = all[k]
	if Company.active and not Company.roster.is_empty():
		var sg: Array = Company.roster.filter(func(m): return int(m["rank"]) >= 3)
		if not sg.is_empty():
			_sarge = Company.title(sg[0])
	var me := String(Company.officer.get("name", "")) if Company.active else ""
	_captions = [
		[0.6, 4.4, Lang.t("The line is broken. What is left of the company runs along the sand for the cliff path.")],
		[4.8, 8.6, Lang.t("Some turn to fire at what's behind them. Not many.")],
		[9.4, 12.6, Lang.t("%s: \"Here! Form on me! Make ready... Present...\"") % _sarge],
		[12.8, 16.6, Lang.t("The lizards stop at the volley, hiss, and go back down the beach. There is easier meat there.")],
		[17.4, 22.6, Lang.t("From the ridge, through the Major's glass, the beach.")],
		[22.8, 28.6, Lang.t("They strip the dead of everything. Then they begin to eat them.")],
		[29.4, 35.8, Lang.t("In the gully below, the ammunition cart, overturned but whole. They right it and haul it up.")],
		[37.0, 41.4, Lang.t("All afternoon more of them come out of the trees.")],
		[41.6, 45.6, Lang.t("They tear down the works, smash the guns' carriages. They break up even the boats.")],
		[46.6, 50.4, Lang.t("%s: \"There is nothing for us here, sir.\"") % _sarge],
		[50.6, 53.6, Lang.t("\"Then we go inland,\" %s. \"Every man who can walk.\"") % (Lang.t("you say") if me == "" else Lang.t("says %s") % me)],
	]
	_voices = [[9.5, "shout", 1.0, -4.0], [10.5, "talk3", 0.95, -6.0], [11.4, "shout", 0.92, -2.0],
		[46.7, "talk3", 0.95, -6.0], [48.4, "talk1", 0.95, -7.0], [50.7, "talk2", 1.05, -6.0], [52.2, "talk4", 1.0, -8.0]]

	var env := Look.environment(self, "dusk", Color(0.85, 0.7, 0.6), 0.004)
	var sun: DirectionalLight3D = env.get_meta("sun")
	sun.rotation_degrees = Vector3(-18, 120, 0) # low, over the land: late afternoon
	var sea := Props.sea(900.0, 0.18, 0.6)
	sea.position = Vector3(0, -0.3, 300)
	var mat := sea.mesh.material as ShaderMaterial
	mat.set_shader_parameter("deep", Color(0.16, 0.24, 0.3))
	mat.set_shader_parameter("crest", Color(0.85, 0.7, 0.55))
	add_child(sea)
	_cam = Camera3D.new()
	_cam.far = 900.0
	add_child(_cam)
	_cam.make_current()
	_build_land()
	_build_actors()
	_build_overlay()
	_loop("surf", -14.0)
	_set_shot("rout")


func _loop(name: String, db: float) -> void:
	if not _sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[name]
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.play)
	p.play()


func _play(name: String, db: float, pitch := 1.0) -> void:
	if not _sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[name]
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- the place

func _build_land() -> void:
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 120)
	pm.material = Props._mat(Props.SAND)
	sand.mesh = pm
	sand.position = Vector3(0, 0.0, -10)
	add_child(sand)
	var wet := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(400, 8)
	wm.material = Props._mat(Props.SAND.darkened(0.25))
	wet.mesh = wm
	wet.position = Vector3(0, 0.01, SHORE_Z - 4)
	add_child(wet)
	var cols: Dictionary = Look.ground_colours(2)
	var land := Look.ground(self, 400.0, cols)
	land.position = Vector3(0, 0.02, -270)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var spots: Array = []
	for i in 120:
		spots.append([Vector3(rng.randf_range(-170, 100), 0, rng.randf_range(-86, -170)), rng.randf_range(1.4, 2.6)])
	Look.trees(self, spots, "mixed", rng)
	Look.far_hills(self, rng, 230.0, Color(0.32, 0.38, 0.32), 14, true)
	# The headland to the east: the cliff, and the path up its landward side.
	var rock := Color(0.42, 0.4, 0.36)
	Props._box(self, Vector3(60, 28, 140), rock, Vector3(160, 0, -10))
	Props._box(self, Vector3(40, 30, 60), rock.darkened(0.1), Vector3(150, 0, 40), Vector3(0, 0, 8))
	Props._box(self, Vector3(70, 1.0, 140), Color(0.36, 0.44, 0.24), Vector3(165, 14.2, -10))
	# The path: a ramp up from the sand.
	Props._box(self, Vector3(40, 1.2, 10), Props.SAND.darkened(0.15), Vector3(112, 6.5, 8), Vector3(0, 0, 20))
	add_child(Props.rocks(Vector3(100, 0, 20), 6, 2.0, rng))
	add_child(Props.rocks(GULLY + Vector3(-4, 0, 4), 5, 1.6, rng))
	# The wreck on her rocks, out to sea.
	var ship := Props.ship()
	ship.position = Vector3(-25, -1.2, 130)
	ship.rotation = Vector3(-0.1, 0.5, 0.38)
	(ship.get_node("main_mast") as Node3D).rotation.x = 1.25
	add_child(ship)
	# The works, the guns abandoned in them, the boats drawn up on the sand.
	for k in 8:
		var seg := Props.earthwork(10.0, [])
		seg.position = Vector3(-40 + k * 10.0, 0, 0)
		add_child(seg)
		_works.append(seg)
	for gx in [-37.0, -15.5, 15.5, 37.0]:
		var g := Props.cannon()
		g.position = Vector3(gx, 0, 1.5)
		g.rotation.y = randf_range(-0.4, 0.4)
		add_child(g)
		_works.append(g)
	for k in 6:
		var b := Node3D.new()
		Props._box(b, Vector3(1.6, 0.6, 5.0), Props.WOOD, Vector3(0, 0.2, 0))
		Props._box(b, Vector3(1.0, 0.6, 1.2), Props.WOOD, Vector3(0, 0.2, -2.8), Vector3(0, 45, 0))
		for z in [-1.0, 0.0, 1.0]:
			Props._box(b, Vector3(1.5, 0.08, 0.3), Props.WOOD_DARK, Vector3(0, 0.45, z))
		b.position = Vector3(-50 + k * 16.0 + randf_range(-3, 3), 0.1, SHORE_Z - 8 + randf_range(-2, 2))
		b.rotation.y = randf_range(-0.5, 0.5) + PI * 0.5
		add_child(b)
		_boats.append(b)
	# A fire where they feast.
	var fire := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.4, 0.6, 1.4)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.5, 0.15)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.1)
	fmat.emission_energy_multiplier = 3.0
	fm.material = fmat
	fire.mesh = fm
	fire.position = Vector3(-4, 0.3, 12)
	add_child(fire)
	_feast.append(fire)
	var smoke := CPUParticles3D.new()
	smoke.amount = 40
	smoke.lifetime = 5.0
	smoke.direction = Vector3(0.2, 1, 0)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 2.5
	smoke.gravity = Vector3.ZERO
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.3, 0.3, 0.3, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	smoke.mesh = sm
	smoke.position = fire.position + Vector3.UP
	add_child(smoke)
	_feast.append(smoke)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.omni_range = 9.0
	_fire_light.light_energy = 2.0
	_fire_light.position = fire.position + Vector3(0, 1.2, 0)
	add_child(_fire_light)
	_feast.append(_fire_light)
	# Carrion birds wheeling over the beach.
	for b in 7:
		var bird := Node3D.new()
		Props._box(bird, Vector3(0.9, 0.05, 0.25), Color(0.08, 0.07, 0.07), Vector3.ZERO)
		Props._box(bird, Vector3(0.12, 0.08, 0.4), Color(0.08, 0.07, 0.07), Vector3(0, 0, 0.05))
		add_child(bird)
		_birds.append([bird, randf() * TAU, randf_range(7.0, 16.0), randf_range(12.0, 20.0), randf_range(0.25, 0.45)])


func _man(pos: Vector3, face: Vector3, kind := "soldier", gear := {}) -> Array:
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	var r = Rig3D.new()
	r.kind = kind
	r.full_rate = true # (a film: every body re-posed every frame, no stutter)
	if kind == "soldier":
		var g := {"head": "shako", "torso": "coat", "primary": "musket", "secondary": "bayonet"}
		g.merge(gear, true)
		r.gear = g
		r.pack = {"rations": 2, "water": 1, "ammo": 6}
	r.facing = face.normalized()
	holder.add_child(r)
	r.anim_time = randf() * 3.0
	_rigs.append(r)
	return [holder, r]


func _show(list: Array, on: bool) -> void:
	for a in list:
		(a[0] as Node3D).visible = on
		a[1].visible = on # (a hidden rig skips its work altogether)


## Sand kicked up behind someone running.
func _kick_dust(holder: Node3D) -> void:
	var d := CPUParticles3D.new()
	d.amount = 5
	d.lifetime = 0.7
	d.local_coords = false
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	d.emission_sphere_radius = 0.25
	d.direction = Vector3(0, 1, 0)
	d.spread = 50.0
	d.initial_velocity_min = 0.6
	d.initial_velocity_max = 1.4
	d.gravity = Vector3(0, -1.5, 0)
	d.scale_amount_min = 0.6
	d.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.4))
	d.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(Props.SAND.darkened(0.02), 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	d.mesh = sm
	d.position = Vector3(0, 0.1, 0)
	holder.add_child(d)
	_dust[holder] = d


func _build_actors() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# The rout: a ragged knot of men running east along the sand.
	for i in 12:
		var m := _man(Vector3(8 + rng.randf_range(-9, 7), 0, 17 + rng.randf_range(-5, 5)), Vector3.RIGHT)
		var fire_at := -1.0
		if i == 2:
			fire_at = 3.2
		elif i == 7:
			fire_at = 5.6
		# [holder, rig, speed, fire_at, stride phase, killed_at]
		_runners.append([m[0], m[1], rng.randf_range(4.4, 4.9), fire_at, rng.randf() * TAU, 2.9 if i == 10 else -1.0])
		_kick_dust(m[0])
	for i in 10:
		var l := _man(Vector3(-16 + rng.randf_range(-10, 6), 0, 17 + rng.randf_range(-7, 7)), Vector3.RIGHT, "lizard")
		var dead := -1.0
		if i == 1:
			dead = 3.55
		elif i == 4:
			dead = 5.95
		# [holder, rig, speed, -, dead_at]
		_chasers.append([l[0], l[1], rng.randf_range(4.7, 5.2), 0.0, dead])
		_kick_dust(l[0])
	# A javelin, thrown at the slowest man.
	_javelin = Node3D.new()
	Props._box(_javelin, Vector3(0.04, 0.04, 1.6), Props.WOOD, Vector3.ZERO)
	Props._box(_javelin, Vector3(0.07, 0.07, 0.2), Color(0.5, 0.5, 0.48), Vector3(0, 0, -0.85))
	_javelin.visible = false
	add_child(_javelin)
	# The rearguard: a line across the foot of the path, and the sergeant.
	for i in 7:
		var m2 := _man(Vector3(94, 0, 15 + i * 1.15), Vector3.LEFT)
		_rear.append(m2)
	_sergeant = _man(Vector3(95.5, 0, 13.2), Vector3.LEFT, "soldier", {"primary": "pike", "secondary": ""})
	_show(_rear, false)
	_show([_sergeant], false)
	# The beach after: the dead, and the lizards over them.
	for i in 14:
		var at := Vector3(rng.randf_range(-30, 25), 0, rng.randf_range(4, 22))
		var d := _man(at, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), "soldier" if i % 3 != 0 else "lizard")
		d[1].die()
		_looters.append(d)
		if i < 9:
			var l2 := _man(at + Vector3(rng.randf_range(-1.2, 1.2), 0, 1.0), Vector3(0, 0, -1), "lizard")
			l2[1].anim = "eat" if i % 2 == 0 else "rummage"
			_looters.append(l2)
	_show(_looters, false)
	# The cart in the gully.
	_cart = Props.wagon()
	_cart.position = GULLY
	_cart.rotation = Vector3(0, 0.6, 1.4)
	_cart.visible = false
	add_child(_cart)
	for i in 4:
		var h := _man(GULLY + Vector3(-2.0 + i * 1.3, 0, -2.5 + (i % 2) * 5.0), Vector3(0, 0, 1 if i % 2 == 0 else -1))
		_haulers.append(h)
	_show(_haulers, false)
	# The horde arriving: out of the trees, down to the works and the boats.
	for i in 30:
		var from := Vector3(rng.randf_range(-90, 60), 0, rng.randf_range(-95, -80))
		var to := Vector3(rng.randf_range(-55, 45), 0, rng.randf_range(-6, 44))
		var hl := _man(from, to - from, "lizard")
		_horde.append([hl[0], hl[1], from, to, T_RUIN + rng.randf_range(-1.0, 4.0)])
	_show(_horde, false)
	# The column going inland, the colours at its head.
	for i in 14:
		var off := Vector3((i % 2) * 1.4 - 0.7, 0, (i / 2) * 1.8)
		var c := _man(RIDGE + Vector3(10, 0.5, 0) + off, Vector3.FORWARD, "soldier", {"head": "shako"} if i != 1 else {"primary": "none"})
		_column.append([c[0], c[1], off])
	_show(_column, false)
	_colour = Node3D.new()
	Props._box(_colour, Vector3(0.06, 2.6, 0.06), Props.WOOD_DARK, Vector3(0, 1.3, 0))
	var flag := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 0.75)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_texture = preload("res://scripts/colours.gd").flag_texture(preload("res://scripts/colours.gd").flag())
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = fmat
	flag.mesh = qm
	flag.position = Vector3(0, 2.25, 0.58)
	flag.rotation.y = PI * 0.5
	_colour.add_child(flag)
	_colour.visible = false
	add_child(_colour)
	_col_cart = Props.wagon()
	_col_cart.visible = false
	add_child(_col_cart)


# ---------------------------------------------------------------- overlay

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_glass = _GlassMask.new()
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.visible = false
	root.add_child(_glass)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0 if top else -64
		bar.offset_bottom = 64 if top else 0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	_band = ColorRect.new()
	_band.color = Color(0, 0, 0, 0.0)
	_band.anchor_right = 1.0
	_band.anchor_top = 1.0
	_band.anchor_bottom = 1.0
	_band.offset_top = -160
	_band.offset_bottom = -66
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_band)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.offset_left = 80
	_caption.offset_right = -80
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_override("font", UI.font("fell_italic"))
	_caption.add_theme_font_size_override("font_size", 32)
	_caption.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_band.add_child(_caption)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	var skip := Button.new()
	skip.text = Lang.t("Skip  ▸")
	skip.add_theme_font_size_override("font_size", 22)
	skip.position = Vector2(20, 76)
	skip.size = Vector2(150, 56)
	skip.pressed.connect(_finish)
	root.add_child(skip)


## The view through a spyglass: black all round a bright circle.
class _GlassMask extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var w := size.length()
		draw_arc(c, r + w * 0.5, 0.0, TAU, 96, Color.BLACK, w)
		draw_arc(c, r, 0.0, TAU, 96, Color(0.2, 0.16, 0.1), 6.0)


# ---------------------------------------------------------------- the timeline

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var t := _t
	for st in _snaps:
		if t - delta < st and t >= st:
			_snap.call_deferred(st)
	for v in _voices:
		if t - delta < float(v[0]) and t >= float(v[0]):
			_play(String(v[1]), float(v[3]), float(v[2]))
	for r in _rigs:
		if r.visible:
			r.anim_time += delta
	_update_caption(t)
	_fade.color.a = _fade_amount(t)
	_glass.visible = t >= T_GLASS and t < T_CART
	_ambient(t, delta)
	if t < T_REAR:
		_shot_rout(t, delta)
	elif t < T_GLASS:
		_set_shot("rear")
		_shot_rear(t - T_REAR, delta)
	elif t < T_CART:
		_set_shot("glass")
		_shot_glass(t - T_GLASS, delta)
	elif t < T_RUIN:
		_set_shot("cart")
		_shot_cart(t - T_CART, delta)
	elif t < T_GO:
		_set_shot("ruin")
		_shot_ruin(t - T_RUIN, delta)
	elif t < LENGTH:
		_set_shot("go")
		_shot_go(t - T_GO, delta)
	else:
		_finish()
		return
	_apply_cam(delta)


## A cut: who's on stage changes, and the camera jumps rather than glides.
func _set_shot(name: String) -> void:
	if name == _shot_name:
		return
	_shot_name = name
	_cam_cut = true
	_show(_runners, name == "rout")
	_show(_chasers, name in ["rout", "rear"])
	_show(_rear, name == "rear")
	_show([_sergeant], name == "rear")
	_show(_looters, name in ["glass", "ruin"])
	_show(_haulers, name == "cart")
	_cart.visible = name == "cart"
	_show(_horde, false)
	_show(_column, name == "go")
	_colour.visible = name == "go"
	_col_cart.visible = name == "go"
	_javelin.visible = false
	for b in _birds:
		(b[0] as Node3D).visible = name in ["glass", "ruin"]
	for n in _feast:
		n.visible = name in ["glass", "ruin", "cart"]
	if name == "rear":
		# The pursuers who are left, closing on the path.
		var k := 0
		for u in _chasers:
			if u[1]._dead:
				_show([u], false)
				continue
			(u[0] as Node3D).position = Vector3(66.0 - k * 2.2, 0, 13 + (k % 4) * 2.2)
			k += 1


## The things that go on whatever the shot: the fire, the birds.
func _ambient(t: float, delta: float) -> void:
	_fire_light.light_energy = 1.6 + 0.6 * sin(t * 13.0) * sin(t * 7.3)
	for b in _birds:
		var n: Node3D = b[0]
		if not n.visible:
			continue
		b[1] = float(b[1]) + float(b[4]) * delta
		var a: float = b[1]
		n.position = Vector3(-4 + cos(a) * float(b[2]), float(b[3]) + sin(a * 2.3) * 0.8, 12 + sin(a) * float(b[2]))
		n.rotation = Vector3(0, -a, sin(t * 3.0 + a) * 0.4) # (banking, the wings tilting)
	_shake = move_toward(_shake, 0.0, delta * 2.5)


## The camera glides toward where the shot wants it (never jumps, except at
## a cut), with a little hand-held drift and the shake of a volley.
func _set_cam(at: Vector3, look: Vector3, fov := 60.0) -> void:
	if _cam_cut:
		_cam_pos = at
		_cam_look = look
		_cam_fov = fov
	_cam_target = [at, look, fov]


var _cam_target: Array = [Vector3.ZERO, Vector3.FORWARD, 55.0]


func _apply_cam(delta: float) -> void:
	var k := 1.0 if _cam_cut else 1.0 - exp(-5.0 * delta)
	_cam_cut = false
	_cam_pos = _cam_pos.lerp(_cam_target[0], k)
	_cam_look = _cam_look.lerp(_cam_target[1], k)
	_cam_fov = lerpf(_cam_fov, float(_cam_target[2]), k)
	var drift := Vector3(sin(_t * 0.7) * 0.06 + sin(_t * 1.9) * 0.025, sin(_t * 0.9) * 0.04, 0.0)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.12 * _shake * _shake
	_cam.fov = _cam_fov
	_cam.global_position = _cam_pos + drift + sh
	_cam.look_at(_cam_look + drift * 0.5)


## A musket going off: flash, smoke, bang.
func _shot_from(r, db := -2.0, big := false) -> void:
	var at: Vector3 = r.muzzle_global()
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.omni_range = 6.0
	flash.light_energy = 4.0
	flash.position = at
	add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.12)
	ft.tween_callback(flash.queue_free)
	for k in (3 if big else 2):
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		sm.radial_segments = 10
		sm.rings = 5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.93, 0.92, 0.88, 0.32 - k * 0.07)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = mat
		puff.mesh = sm
		var fwd: Vector3 = r.facing.normalized()
		puff.position = at + fwd * (0.3 + k * 0.5)
		add_child(puff)
		var life := randf_range(2.6, 3.6) + k * 0.6
		var tw := create_tween().set_parallel(true)
		tw.tween_property(puff, "scale", Vector3.ONE * (4.5 + k * 2.0), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(mat, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
		tw.tween_property(puff, "position", puff.position + fwd * (1.2 + k) + Vector3(0.6, 1.2 + k * 0.4, 0.3), life).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(puff.queue_free)
	_play("musket", db, randf_range(0.9, 1.1))


## A ball striking the sand by someone (or the sand where they fall).
func _sand_puff(at: Vector3, size := 1.0) -> void:
	var puff := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25 * size
	sm.height = 0.3 * size
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(Props.SAND.lightened(0.15), 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	puff.mesh = sm
	puff.position = at + Vector3(0, 0.15, 0)
	add_child(puff)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3(4, 2.5, 4), 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.2)
	tw.chain().tween_callback(puff.queue_free)


func _fall(u: Array) -> void:
	if u[1]._dead:
		return
	u[1].die()
	var d = _dust.get(u[0])
	if d != null:
		d.emitting = false
	_sand_puff((u[0] as Node3D).global_position, 1.3)


## The rout: they run along the sand for the path, the lizards gaining.
## Two turn and fire; a javelin brings one man down; the camera tracks
## alongside, low, from the sea side.
func _shot_rout(t: float, delta: float) -> void:
	for u in _runners:
		var h: Node3D = u[0]
		var r = u[1]
		if r._dead:
			continue
		var fire_at: float = u[3]
		if float(u[5]) > 0.0 and t >= float(u[5]):
			# The javelin finds him: down, and left behind.
			_fall(u)
			_play("grunt", -6.0, 0.9)
			continue
		if fire_at > 0.0 and t >= fire_at and t < fire_at + 1.25:
			# Turn, fire, run on.
			r.facing = r.facing.lerp(Vector3.LEFT, 1.0 - exp(-12.0 * delta)).normalized()
			r.move_speed = move_toward(r.move_speed, 0.0, 14.0 * delta)
			r.anim = "fire" if t >= fire_at + 0.4 else "aim"
			(_dust[h] as CPUParticles3D).emitting = false
			if t >= fire_at + 0.4 and not _fired.has(r):
				_fired[r] = true
				_shot_from(r)
			h.position.x += r.move_speed * delta
			continue
		# Running: each at his own pace, which wavers with his stride.
		var sp := float(u[2]) * (1.0 + 0.06 * sin(t * 2.3 + float(u[4])))
		if fire_at > 0.0 and t > fire_at + 1.25:
			sp *= 1.12 # (catching up)
		r.facing = r.facing.lerp(Vector3.RIGHT, 1.0 - exp(-8.0 * delta)).normalized()
		r.anim = "walk"
		r.move_speed = sp
		(_dust[h] as CPUParticles3D).emitting = true
		h.position.x += sp * delta
		h.position.z += sin(t * 1.3 + float(u[4])) * 0.25 * delta # (weaving)
	for u in _chasers:
		var h2: Node3D = u[0]
		var r2 = u[1]
		if r2._dead:
			continue
		if float(u[4]) > 0.0 and t >= float(u[4]):
			_fall(u)
			_play("hiss", -8.0, randf_range(0.8, 1.0))
			continue
		r2.facing = Vector3.RIGHT
		r2.anim = "walk"
		r2.move_speed = float(u[2])
		h2.position.x += float(u[2]) * delta
	# The javelin: from the leading lizard to the slow man.
	if t >= 2.2 and t < 2.9:
		var thrower: Node3D = _chasers[0][0]
		var victim: Node3D = _runners[10][0]
		var k := (t - 2.2) / 0.7
		var a := thrower.global_position + Vector3(0, 1.8, 0)
		var b := victim.global_position + Vector3(0, 1.1, 0)
		var at := a.lerp(b, k) + Vector3.UP * sin(k * PI) * 2.0
		_javelin.visible = true
		_javelin.look_at_from_position(at, at + (b - a).normalized() + Vector3.UP * cos(k * PI) * 0.6)
	elif t >= 2.9 and _javelin.visible:
		# Stuck in the sand by him.
		var victim2: Node3D = _runners[10][0]
		_javelin.look_at_from_position(victim2.global_position + Vector3(-0.6, 0.6, 0.3), victim2.global_position + Vector3(0.4, -0.6, 0.3))
	if fmod(t, 2.2) < delta:
		_play("roar", -12.0, randf_range(0.8, 1.1))
	# The camera: alongside the knot of men, from the sea side, sliding
	# forward with them and drifting closer as the pursuit gains.
	# (a little ahead of the men, looking back past them at what's coming)
	var lead := 8.0 + 4.6 * t
	var k2 := smoothstep(0.0, T_REAR, t)
	_set_cam(Vector3(lead + 7.0 - 3.0 * k2, 1.7 + 0.5 * k2, 31.0 - 5.0 * k2), Vector3(lead - 6.0, 1.0, 16.0), lerpf(54.0, 48.0, k2))


## The rearguard: the sergeant forms them across the foot of the path; the
## pursuit comes on; the volley; the smoke; the lizards stop, hiss, and go.
func _shot_rear(t: float, delta: float) -> void:
	var sg = _sergeant[1]
	sg.anim = "idle"
	sg.facing = Vector3.LEFT if t < 1.0 or t > 3.0 else Vector3(-0.3, 0, -1)
	for m in _rear:
		var r = m[1]
		r.facing = Vector3.LEFT
		r.anim = "idle" if t < 1.3 else ("aim" if t < 2.45 else ("fire" if t < 3.0 else "reload"))
		if t >= 2.45 and not _fired.has(r):
			_fired[r] = true
			_shot_from(r, -12.0 if m != _rear[3] else 2.0, true)
	if t >= 2.45 and t - delta < 2.45:
		_shake = 1.0
		_play("musket", 2.0, 0.85)
	var n := 0
	for u in _chasers:
		var h: Node3D = u[0]
		var r2 = u[1]
		if r2._dead or not h.visible:
			continue
		n += 1
		if t >= 2.55 and n <= 3:
			_fall(u)
			continue
		if t < 3.4:
			# Still coming, then checking at the smoke.
			var sp := float(u[2]) * (1.0 - smoothstep(2.5, 3.4, t))
			r2.facing = Vector3.RIGHT
			r2.anim = "walk"
			r2.move_speed = sp
			h.position.x += sp * delta
		elif t < 4.6:
			r2.anim = "idle"
			r2.move_speed = 0.0
			r2.facing = r2.facing.lerp(Vector3.LEFT, 1.0 - exp(-3.0 * delta)).normalized()
		else:
			# They give it up and go back for the easier meat.
			r2.facing = Vector3.LEFT
			r2.anim = "walk"
			r2.move_speed = minf(3.4, (t - 4.6) * 3.0)
			h.position.x -= r2.move_speed * delta
	if t > 3.6 and t - delta <= 3.6:
		_play("hiss", -4.0, 0.85)
		_play("roar", -6.0, 0.9)
	# From the sea side and a little above the line, the pursuit beyond it;
	# a slow push in.
	var k := smoothstep(0.0, T_GLASS - T_REAR, t)
	_set_cam(Vector3(101.0 - 3.0 * k, 3.4 - 0.6 * k, 34.0 - 4.0 * k), Vector3(80.0 - 4.0 * k, 0.9, 16.0), 48.0)


## Through the glass: a slow, unsteady sweep across the beach.
func _shot_glass(t: float, _delta: float) -> void:
	var k := smoothstep(0.0, T_CART - T_GLASS, t)
	var look := Vector3(lerpf(-28.0, 18.0, k), 0.6, lerpf(10.0, 14.0, k)) + Vector3(sin(t * 1.1) * 0.25, sin(t * 1.7) * 0.12, 0)
	# (the glass is held by hand, and its focus breathes)
	_set_cam(RIDGE + Vector3(0, 2.0, 0), look, 9.0 + sin(t * 0.8) * 0.4)
	if fmod(t, 3.1) < get_process_delta_time():
		_play("hiss", -18.0, randf_range(0.7, 1.0))


## The cart: four of them heave it upright, it lands in a puff of dust, and
## they haul it up out of the gully on its ropes.
func _shot_cart(t: float, delta: float) -> void:
	var up := smoothstep(0.8, 2.4, t)
	_cart.rotation = Vector3(0, 0.6, lerpf(1.4, 0.0, up * up))
	var moving := t > 2.9
	if t > 2.4 and t - delta <= 2.4:
		_play("thud", -2.0, 0.8)
		_play("shout", -10.0, 1.1)
		_sand_puff(GULLY, 2.0)
		_sand_puff(GULLY + Vector3(1.0, 0, 0.6), 1.6)
	if moving:
		_cart.position = GULLY + Vector3(0, 0, -(t - 2.9) * 1.1)
	for i in _haulers.size():
		var h = _haulers[i]
		var r = h[1]
		if not moving:
			r.anim = "haul"
			r.facing = (_cart.global_position - (h[0] as Node3D).global_position) * Vector3(1, 0, 1)
		else:
			r.anim = "walk"
			r.move_speed = 1.1
			r.facing = Vector3.FORWARD
			(h[0] as Node3D).position.z -= 1.1 * delta
	var k := smoothstep(0.0, T_RUIN - T_CART, t)
	_set_cam(GULLY + Vector3(9.0 - 2.0 * k, 3.2 + 0.8 * k, 6.0 - 3.0 * k), _cart.global_position + Vector3(0, 0.9, 0), 48.0)


## The horde: out of the trees, over the works, onto the boats. The works
## slump, the boats are smashed (splinters fly), the drums go on.
func _shot_ruin(t: float, delta: float) -> void:
	var abs_t := T_RUIN + t
	for u in _horde:
		var h: Node3D = u[0]
		var r = u[1]
		var start: float = u[4]
		if abs_t < start:
			continue
		if not h.visible:
			_show([u], true)
		var from: Vector3 = u[2]
		var to: Vector3 = u[3]
		var k := clampf((abs_t - start) / 6.0, 0.0, 1.0)
		h.position = from.lerp(to, smoothstep(0.0, 1.0, k))
		r.facing = to - from
		if k < 1.0:
			r.anim = "walk"
			r.move_speed = 4.0
		else:
			r.move_speed = 0.0
			r.anim = "strike" if fmod(abs_t + float(u[4]), 1.4) < 0.5 else "rummage"
	for i in _works.size():
		var w: Node3D = _works[i]
		var at := 3.0 + i * 0.45
		if t > at:
			var k2 := smoothstep(0.0, 1.0, (t - at) / 1.2)
			w.rotation.x = lerpf(0.0, 0.9 if i % 2 == 0 else -0.7, k2)
			w.position.y = lerpf(0.0, -0.5, k2)
			if t - delta <= at:
				_sand_puff(w.global_position + Vector3(0, 0, 0.5), 2.5)
	for i in _boats.size():
		var b: Node3D = _boats[i]
		var at2 := 4.0 + i * 0.8
		if t > at2:
			var k3 := smoothstep(0.0, 1.0, (t - at2) / 1.0)
			b.rotation.z = lerpf(0.0, 1.2 * (1 if i % 2 == 0 else -1), k3)
			b.scale = Vector3(1, lerpf(1.0, 0.4, k3), lerpf(1.0, 0.7, k3))
			if t - delta <= at2:
				_play("crack", -10.0, randf_range(0.7, 0.9))
				_splinter(b.global_position + Vector3(0, 0.6, 0))
	if fmod(t, 1.4) < delta:
		_play("drum", -8.0, randf_range(0.95, 1.05))
	# Low over the beach, sliding along the ruined works.
	var k4 := smoothstep(0.0, T_GO - T_RUIN, t)
	_set_cam(Vector3(44.0 - 12.0 * k4, 7.0 - 1.5 * k4, 38.0), Vector3(-4.0 + 4.0 * k4, 0.0, 10.0), 50.0)


## Planks flying off a boat as it's smashed.
func _splinter(at: Vector3) -> void:
	for k in 6:
		var p := Props._box(self, Vector3(0.12, 0.05, randf_range(0.5, 1.2)), Props.WOOD, at)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1))
		var land := at + Vector3(dir.x * 2.5, -at.y + 0.05, dir.z * 2.5)
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(v: float):
			p.position = at.lerp(land, v) + Vector3.UP * sin(v * PI) * dir.y * 1.5
			p.rotation = Vector3(v * 7.0, v * 4.0, 0.0), 0.0, 1.0, 0.9)


## Inland: the column turns its back on the sea and marches into the
## evening, the colours at its head, the cart behind; the camera rises.
func _shot_go(t: float, delta: float) -> void:
	var ahead := Vector3(0, 0, -1.3 * t)
	for c in _column:
		var h: Node3D = c[0]
		var r = c[1]
		h.position = RIDGE + Vector3(14, 0.6, -2) + (c[2] as Vector3) + ahead
		r.facing = Vector3.FORWARD
		r.anim = "walk"
		r.move_speed = 1.3
	# The colour-bearer is the second man: the colours over his shoulder.
	var cb: Node3D = _column[1][0]
	_colour.global_position = cb.global_position + Vector3(0.3, 0.6, 0.0)
	_colour.rotation = Vector3(0.18 + sin(_t * 2.6) * 0.03, 0, sin(_t * 1.3) * 0.04)
	_col_cart.position = RIDGE + Vector3(14, 0.6, 12) + ahead
	var k := smoothstep(0.0, LENGTH - T_GO, t)
	_set_cam(RIDGE + Vector3(26.0 - 6.0 * k, 5.0 + 5.0 * k, 20.0 - 6.0 * k), RIDGE + Vector3(14, 1.0, 2) + ahead * 1.1, 50.0)


func _fade_amount(t: float) -> float:
	if t < 0.8:
		return 1.0 - t / 0.8
	for cut in [T_REAR, T_GLASS, T_CART, T_RUIN, T_GO]:
		if absf(t - cut) < 0.35:
			return clampf(1.0 - absf(t - cut) / 0.35, 0.0, 1.0) * 0.9
	if t > LENGTH - 1.6:
		return clampf((t - (LENGTH - 1.6)) / 1.6, 0.0, 1.0)
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


func _snap(st: float) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://r_%04.1f.png" % st)


func _finish() -> void:
	if _done:
		return
	_done = true
	if not _snaps.is_empty():
		print("RETREAT DONE at %.1fs" % _t)
		get_tree().quit()
		return
	Loading.change(AFTERMATH)
