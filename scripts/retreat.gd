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
	for k in ["musket", "shout", "drum", "hiss", "roar", "talk1", "talk2", "talk3", "talk4", "crack", "thud", "surf"]:
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


func _man(pos: Vector3, face: Vector3, kind := "soldier", gear := {}) -> Array:
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	var r = Rig3D.new()
	r.kind = kind
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


func _build_actors() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# The rout: men running east along the sand, the lizards behind.
	for i in 10:
		var m := _man(Vector3(10 + rng.randf_range(-8, 6), 0, 18 + rng.randf_range(-6, 6)), Vector3.RIGHT)
		var fire_at := -1.0
		if i == 2:
			fire_at = 3.4
		elif i == 6:
			fire_at = 5.8
		_runners.append([m[0], m[1], rng.randf_range(4.2, 5.0), fire_at])
	for i in 9:
		var l := _man(Vector3(-14 + rng.randf_range(-10, 6), 0, 18 + rng.randf_range(-7, 7)), Vector3.RIGHT, "lizard")
		var dead := -1.0
		if i == 1:
			dead = 3.6
		elif i == 4:
			dead = 6.0
		_chasers.append([l[0], l[1], rng.randf_range(4.6, 5.2), rng.randf_range(76, 84), dead])
	# The rearguard: a kneeling rank at the foot of the path.
	for i in 6:
		var m2 := _man(Vector3(94, 0, 16 + i * 1.3), Vector3.LEFT)
		m2[1].anim = "kneel"
		_rear.append(m2)
		m2[0].visible = false
	# The beach after: the dead, and the lizards over them.
	for i in 14:
		var at := Vector3(rng.randf_range(-30, 25), 0, rng.randf_range(4, 22))
		var d := _man(at, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), "soldier" if i % 3 != 0 else "lizard")
		d[1].die()
		if i < 9:
			var l2 := _man(at + Vector3(rng.randf_range(-1.2, 1.2), 0, 1.0), (at - (at + Vector3(0, 0, 1))), "lizard")
			l2[1].anim = "eat" if i % 2 == 0 else "rummage"
			_looters.append(l2)
	# The cart in the gully.
	_cart = Props.wagon()
	_cart.position = GULLY
	_cart.rotation = Vector3(0, 0.6, 1.4)
	add_child(_cart)
	for i in 4:
		var h := _man(GULLY + Vector3(-2.0 + i * 1.3, 0, -2.5 + (i % 2) * 5.0), Vector3(0, 0, 1 if i % 2 == 0 else -1))
		_haulers.append(h)
	# The horde arriving: out of the trees, down to the works and the boats.
	for i in 30:
		var from := Vector3(rng.randf_range(-90, 60), 0, rng.randf_range(-95, -80))
		var to := Vector3(rng.randf_range(-55, 45), 0, rng.randf_range(-6, 44))
		var hl := _man(from, to - from, "lizard")
		hl[0].visible = false
		_horde.append([hl[0], hl[1], from, to, T_RUIN + rng.randf_range(-1.0, 4.0)])
	# The column going inland.
	for i in 14:
		var off := Vector3((i % 2) * 1.4 - 0.7, 0, (i / 2) * 1.8)
		var c := _man(RIDGE + Vector3(10, 0.5, 0) + off, Vector3.FORWARD, "soldier", {"head": "shako"} if i != 0 else {"primary": "none"})
		c[0].visible = false
		_column.append([c[0], c[1], off])
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
		r.anim_time += delta
	_update_caption(t)
	_fade.color.a = _fade_amount(t)
	_glass.visible = t >= T_GLASS and t < T_CART
	if t < T_REAR:
		_shot_rout(t, delta)
	elif t < T_GLASS:
		_shot_rear(t - T_REAR, delta)
	elif t < T_CART:
		_shot_glass(t - T_GLASS, delta)
	elif t < T_RUIN:
		_shot_cart(t - T_CART, delta)
	elif t < T_GO:
		_shot_ruin(t - T_RUIN, delta)
	elif t < LENGTH:
		_shot_go(t - T_GO, delta)
	else:
		_finish()


func _set_cam(at: Vector3, look: Vector3, fov := 60.0) -> void:
	_cam.fov = fov
	_cam.global_position = at
	_cam.look_at(look)


## A musket going off: the flash, the smoke, the bang.
func _shot_from(r, db := -2.0) -> void:
	var at: Vector3 = r.muzzle_global()
	var puff := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.92, 0.9, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	puff.mesh = sm
	puff.position = at
	add_child(puff)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3.ONE * 7.0, 2.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.2)
	tw.tween_property(puff, "position", at + Vector3(0.5, 1.5, 0), 2.2)
	tw.chain().tween_callback(puff.queue_free)
	_play("musket", db, randf_range(0.9, 1.1))


func _shot_rout(t: float, delta: float) -> void:
	var lead := Vector3.ZERO
	for u in _runners:
		var h: Node3D = u[0]
		var r = u[1]
		var fire_at: float = u[3]
		if fire_at > 0.0 and t >= fire_at and t < fire_at + 1.3:
			# Turn, fire, run on.
			r.facing = Vector3.LEFT
			r.move_speed = 0.0
			r.anim = "fire" if t >= fire_at + 0.35 else "aim"
			if t >= fire_at + 0.35 and not _fired.has(r):
				_fired[r] = true
				_shot_from(r)
			continue
		r.facing = Vector3.RIGHT
		r.anim = "walk"
		r.move_speed = float(u[2])
		h.position.x += float(u[2]) * delta
		lead += h.position
	lead /= maxf(1.0, _runners.size())
	for u in _chasers:
		var h2: Node3D = u[0]
		var r2 = u[1]
		var dead_at: float = u[4]
		if r2._dead:
			continue
		if dead_at > 0.0 and t >= dead_at:
			r2.die()
			_play("hiss", -8.0, randf_range(0.8, 1.0))
			continue
		r2.facing = Vector3.RIGHT
		r2.anim = "walk"
		r2.move_speed = float(u[2])
		h2.position.x += float(u[2]) * delta
	if randf() < delta * 0.6:
		_play("roar", -12.0, randf_range(0.8, 1.1))
	# Tracking alongside, low, from the sea side.
	var k := t / T_REAR
	_set_cam(Vector3(lead.x - 6.0 + 4.0 * k, 1.8, 36.0 - 4.0 * k), Vector3(lead.x - 4.0, 1.2, 16.0), 55.0)


func _shot_rear(t: float, delta: float) -> void:
	if t < delta * 1.5:
		for u in _runners:
			(u[0] as Node3D).visible = false # (gone on up the path)
		for m in _rear:
			(m[0] as Node3D).visible = true
		var k := 0
		for u in _chasers:
			if u[1]._dead:
				(u[0] as Node3D).visible = false
				continue
			(u[0] as Node3D).position = Vector3(70.0 - k * 2.5, 0, 12 + k * 2.0)
			k += 1
	for m in _rear:
		m[1].anim = "idle" if t < 1.2 else ("aim" if t < 2.4 else ("fire" if t < 3.0 else "reload"))
		if t >= 2.4 and not _fired.has(m[1]):
			_fired[m[1]] = true
			_shot_from(m[1], -6.0 if m != _rear[0] else 0.0)
	var n := 0
	for u in _chasers:
		var h: Node3D = u[0]
		var r = u[1]
		if r._dead or not h.visible:
			continue
		n += 1
		if t >= 2.5 and n <= 3:
			r.die()
			continue
		if t < 3.6:
			# Still coming, then checking at the smoke.
			var sp := float(u[2]) * clampf(1.0 - (t - 2.5) / 1.0, 0.0, 1.0)
			r.facing = Vector3.RIGHT
			r.anim = "walk"
			r.move_speed = sp
			h.position.x += sp * delta
		else:
			# They give it up and go back for the easier meat.
			r.facing = Vector3.LEFT
			r.anim = "walk"
			r.move_speed = 3.2 if t > 4.5 else 0.0
			h.position.x -= r.move_speed * delta
	if t > 3.4 and t - delta <= 3.4:
		_play("hiss", -4.0, 0.85)
		_play("roar", -6.0, 0.9)
	# From the side and above the rank, down the beach at them.
	_set_cam(Vector3(100.0 - t * 0.4, 3.6, 33.0), Vector3(80.0, 0.8, 16.0), 50.0)


func _shot_glass(t: float, delta: float) -> void:
	if t < delta * 1.5:
		for u in _chasers:
			(u[0] as Node3D).visible = false
		for m in _rear:
			(m[0] as Node3D).visible = false
	# A slow pan across the beach, through the glass.
	var k := t / (T_CART - T_GLASS)
	var look := Vector3(lerpf(-28.0, 18.0, k), 0.8, lerpf(10.0, 14.0, k))
	_set_cam(RIDGE + Vector3(0, 2.0, 0), look, 9.0)
	_cam.rotation.z = sin(t * 1.3) * 0.004 # (a hand-held glass)
	if randf() < delta * 0.5:
		_play("hiss", -18.0, randf_range(0.7, 1.0))


func _shot_cart(t: float, delta: float) -> void:
	# Righting it, then hauling it up out of the gully.
	var up := smoothstep(0.8, 2.6, t)
	_cart.rotation = Vector3(0, 0.6, lerpf(1.4, 0.0, up))
	_cart.position = GULLY + Vector3(0, 0.0 if up < 1.0 else 0.0, 0)
	if t > 2.8:
		_cart.position = GULLY + Vector3(-0.0, 0, -(t - 2.8) * 1.2)
	if t > 2.6 and t - delta <= 2.6:
		_play("thud", -4.0, 0.8)
		_play("shout", -10.0, 1.1)
	for i in _haulers.size():
		var h = _haulers[i]
		var r = h[1]
		if t < 2.8:
			r.anim = "haul"
			r.facing = (_cart.global_position - (h[0] as Node3D).global_position) * Vector3(1, 0, 1)
		else:
			r.anim = "walk"
			r.move_speed = 1.2
			r.facing = Vector3.FORWARD
			(h[0] as Node3D).position.z -= 1.2 * delta
	_set_cam(GULLY + Vector3(9.0, 3.5, 6.0 - t * 0.4), _cart.global_position + Vector3(0, 0.8, 0), 50.0)


func _shot_ruin(t: float, delta: float) -> void:
	if t < delta * 1.5:
		_cart.visible = false
		for h in _haulers:
			(h[0] as Node3D).visible = false
	var abs_t := T_RUIN + t
	for u in _horde:
		var h: Node3D = u[0]
		var r = u[1]
		var start: float = u[4]
		if abs_t < start:
			continue
		h.visible = true
		var from: Vector3 = u[2]
		var to: Vector3 = u[3]
		var k := clampf((abs_t - start) / 6.0, 0.0, 1.0)
		h.position = from.lerp(to, k)
		r.facing = to - from
		r.anim = "walk" if k < 1.0 else "rummage"
		r.move_speed = 4.0 if k < 1.0 else 0.0
	# The works come down, the boats are broken up.
	for i in _works.size():
		var w: Node3D = _works[i]
		var at := 3.0 + i * 0.45
		if t > at:
			var k2 := clampf((t - at) / 1.2, 0.0, 1.0)
			w.rotation.x = lerpf(0.0, 0.9 if i % 2 == 0 else -0.7, k2)
			w.position.y = lerpf(0.0, -0.5, k2)
	for i in _boats.size():
		var b: Node3D = _boats[i]
		var at2 := 4.0 + i * 0.8
		if t > at2:
			var k3 := clampf((t - at2) / 1.0, 0.0, 1.0)
			b.rotation.z = lerpf(0.0, 1.2 * (1 if i % 2 == 0 else -1), k3)
			b.scale = Vector3(1, lerpf(1.0, 0.4, k3), lerpf(1.0, 0.7, k3))
			if t - delta <= at2:
				_play("crack", -10.0, randf_range(0.7, 0.9))
	if fmod(t, 1.4) < delta:
		_play("drum", -8.0, randf_range(0.95, 1.05))
	# Low over the beach, the works and the boats, the horde pouring past.
	_set_cam(Vector3(44.0 - t * 1.2, 7.0, 38.0), Vector3(-4.0, 0.0, 10.0), 50.0)


func _shot_go(t: float, delta: float) -> void:
	if t < delta * 1.5:
		for u in _horde:
			(u[0] as Node3D).visible = false
		for c in _column:
			(c[0] as Node3D).visible = true
		_col_cart.visible = true
	# Inland, away from the sea, into the evening: they march off from us.
	var ahead := Vector3(0, 0, -1.3 * t)
	for c in _column:
		var h: Node3D = c[0]
		var r = c[1]
		h.position = RIDGE + Vector3(14, 0.6, -2) + (c[2] as Vector3) + ahead
		r.facing = Vector3.FORWARD
		r.anim = "walk"
		r.move_speed = 1.3
	_col_cart.position = RIDGE + Vector3(14, 0.6, 12) + ahead
	_col_cart.rotation.y = 0.0
	_set_cam(RIDGE + Vector3(26.0, 7.0, 20.0 - t * 0.8), RIDGE + Vector3(14, 1.0, 2) + ahead, 50.0)


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
