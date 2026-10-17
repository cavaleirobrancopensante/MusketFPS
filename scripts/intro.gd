extends Node3D
## The opening cutscene, played in the engine. A timeline of shots, each a
## camera move and what happens in it (see _process). Names come from lore.gd.
##
##   the storm       the troopship rolling through the night
##   the strike      she runs onto uncharted rocks; the mainmast comes down
##   the guns        golden dawn: from the heeled wreck a gun is swayed out
##                   on a tackle and lowered into a boat, men hauling on deck
##   the boats       the flotilla pulls for the shore, every oar in time, the
##                   cox beating the stroke, a gun lashed amidships
##   the landing     the boats ground; men wade ashore and drag the guns up
##                   the sand on ropes, the Major waving them on
##   the works       the beach is entrenched: a line of men digging, the
##                   rampart rising, the guns in their embrasures
##   the Major       on a crate before the colours, sabre raised at the forest
##   the forest      from behind the gabions: the trees, birds bursting out of
##                   them, and drums
##
## Tap Skip to go straight to the beach.

const Props := preload("res://scripts/props.gd")
const Lore := preload("res://scripts/lore.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const SoundFactory := preload("res://scripts/sound_factory.gd")
const Look := preload("res://scripts/look.gd")
const GunCrew := preload("res://scripts/gun_crew.gd")
const UI := preload("res://scripts/ui.gd")
const BATTLE := "res://scenes/battle.tscn"

const ROCKS_AT := Vector3(-25, 0, 130) # where she strikes (seen from the beach later)
## When each shot starts (seconds).
const T_STRIKE := 7.0
const T_GUNS := 13.8
const T_BOATS := 22.6
const T_LANDING := 31.6
const T_WORKS := 40.6
const T_MAJOR := 50.0
const T_FOREST := 57.6
const LENGTH := 66.0
const SHORE_Z := 50.0 # where the sand meets the sea
const GUN_X := [-37.0, -15.5, 15.5, 37.0]

var _t := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D
var _ship: Node3D
var _sea: MeshInstance3D
var _rain: CPUParticles3D
var _beach: Node3D
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
var _snaps: Array = [] # (test renders: -- --intro-render --snaps=3,16.5,...)
var _captions := [
	[0.6, 6.2, Lang.t("Three weeks out of port, the troopship %s carries %s to the colonies.") % [Lore.SHIP, Lore.REGIMENT]],
	[7.4, 12.6, Lang.t("A storm drives her far off course, onto rocks no chart has ever shown.")],
	[14.6, 21.8, Lang.t("Dawn. Before the wreck breaks up, %s has the guns swayed out and lowered into the boats.") % Lore.COMMANDER],
	[23.0, 30.8, Lang.t("Of eight hundred souls aboard, some three hundred pull for a shore no one has ever charted.")],
	[32.0, 39.8, Lang.t("They drag the guns up through the surf by hand.")],
	[41.0, 49.4, Lang.t("By noon the beach is entrenched: a rampart of sand and wicker, four guns in its embrasures.")],
	[50.6, 57.2, Lang.t("\"Not one step back from this sand,\" the Major tells them. \"Whatever comes out of those trees.\"")],
	[58.4, 65.0, Lang.t("Then, from deep in the forest, the scouts hear drums.")],
]

# The shots' actors.
var _lower := {} # the gun being lowered from the wreck
var _boats: Array = [] # boat dictionaries (see _make_boat), with "lane" and "phase"
var _hero_boat := {}
var _landing := {} # boats on the shore, men in the surf, the haul
var _diggers: Array = [] # [rig, phase]
var _works: Node3D
var _major: Node3D
var _major_rig
var _flag: Array = [] # flag strips to wave
var _birds: Array = [] # [node, velocity]
var _drums := [58.6, 59.3, 61.0, 61.5, 62.3, 63.4, 63.9, 64.4, 64.8]


func _ready() -> void:
	Music.set_context("intro")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snaps="):
			for v in a.substr(8).split(","):
				_snaps.append(float(v))
	var batcher := BatcherScript.new()
	batcher.add_to_group("batcher")
	add_child(batcher)
	_sounds = {"thunder": SoundFactory.thunder(), "crack": SoundFactory.crack(), "cannon": SoundFactory.cannon(),
		"drum": SoundFactory.drum()}

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.name = "storm_env"
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
	# A rail along both sides of the waist, for the men to hold on to.
	for sx in [-1.0, 1.0]:
		Props._box(_ship, Vector3(0.1, 0.1, 17.0), Props.WOOD, Vector3(sx * 2.42, 3.3, 0.0))
		for k in 9:
			Props._box(_ship, Vector3(0.08, 0.95, 0.08), Props.WOOD, Vector3(sx * 2.42, 2.85, -8.0 + k * 2.0))
	_build_storm_crew()

	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 900.0
	add_child(_cam)
	_rain = _make_rain()
	_cam.add_child(_rain)

	_beach = Node3D.new()
	_beach.visible = false
	add_child(_beach)
	_build_shore()
	_build_lowering()
	_build_flotilla()
	_build_landing()
	_build_works()
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


# ---------------------------------------------------------------- actors

## A man (a Rig3D) on `parent` at `pos`. Manual men are posed by hand each
## frame (t_grip, t_hand_r...); the rest play the soldiers' animations.
func _man(parent: Node3D, pos: Vector3, face: Vector3, gear := {}, manual := false, kind := "soldier"):
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var r = Rig3D.new()
	r.kind = kind
	var g := {"head": "shako", "torso": "coat", "primary": "musket", "secondary": "bayonet"}
	if kind == "officer":
		g = Rig3D.MAJOR_GEAR.duplicate() # (the Major in his full dress)
	g.merge(gear, true)
	r.gear = g
	r.pack = {"rations": 4, "water": 1, "ammo": 10}
	r.manual = manual
	r.facing = face.normalized()
	holder.add_child(r)
	r.anim_time = randf() * 3.0
	return r


## A manual man's hands at world points (his tool slung, or held by them).
func _hands(r, right: Vector3, left: Vector3) -> void:
	var bt: Transform3D = (r.body as Node3D).global_transform
	r.t_hand_r = bt.affine_inverse() * right
	r.t_hand_l = bt.affine_inverse() * left


func _rope(parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 1.0)
	m.mesh = bm
	m.material_override = Props._mat(Color(0.62, 0.55, 0.4))
	parent.add_child(m)
	return m


## Stretch a rope between two world points.
func _rope_between(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.97 else Vector3.BACK
	m.global_transform = Transform3D(Basis.looking_at(d, up).scaled(Vector3(1, 1, l)), (a + b) * 0.5)


# ---------------------------------------------------------------- building

## The shore: sand, the land behind it, the forest, hills beyond.
func _build_shore() -> void:
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 120)
	pm.material = Props._mat(Props.SAND)
	sand.mesh = pm
	sand.position = Vector3(0, 0.0, -10)
	_beach.add_child(sand)
	var wet := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(400, 8)
	wm.material = Props._mat(Props.SAND.darkened(0.25))
	wet.mesh = wm
	wet.position = Vector3(0, 0.01, SHORE_Z - 4)
	_beach.add_child(wet)
	var cols: Dictionary = Look.ground_colours(2)
	var land := Look.ground(_beach, 400.0, cols)
	land.position = Vector3(0, 0.02, -270)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	Look.grass(_beach, Vector3(0, 0.02, -95), 30.0, 0.8, cols, [], rng, func(p: Vector3) -> bool: return p.z > -72.0)
	# The forest beyond: tall, dark, a little strange.
	var spots: Array = []
	for i in 140:
		spots.append([Vector3(rng.randf_range(-170, 170), 0, rng.randf_range(-86, -170)), rng.randf_range(1.4, 2.6)])
	Look.trees(_beach, spots, "mixed", rng)
	Look.far_hills(_beach, rng, 230.0, Color(0.32, 0.38, 0.32), 14, true)


## The storm: men at the rail holding on with both hands, legs braced,
## riding the roll with the ship (they're parented to her, posed by hand, so
## nothing in them twitches).
var _storm_crew: Array = []


func _build_storm_crew() -> void:
	var spots := [[1.6, -3.0, 1.0], [1.7, -1.4, 1.0], [-1.7, 0.8, -1.0], [-1.6, 2.6, -1.0], [1.6, 4.2, 1.0]]
	for sp in spots:
		var r = _man(_ship, Vector3(float(sp[0]), 2.35, float(sp[1])), Vector3(float(sp[2]), 0, 0),
			{"torso": "coat", "head": "shako", "primary": "none"}, true)
		r.t_hand_r = Vector3(0.24, 1.02, -0.62)
		r.t_hand_l = Vector3(-0.24, 1.02, -0.62)
		r.t_lean = 0.28
		r.pose_rate = 4.0
		_storm_crew.append(r)


## On the wreck: a derrick, its boom stepped on the deck and swung out over
## the side, a block at its head; the tackle from the block to a sling round
## the gun. The gun is hoisted off the deck, the boom swings out, and the
## men on the fall ease it down hand over hand into the launch alongside,
## two men in her steadying it in.
const BOOM_HEEL := Vector3(1.9, 2.4, 1.5) # (ship-local)
const BOOM_LEN := 6.0
const BOOM_ELEV := 0.82 # (radians above the deck)
const BOOM_IN := 2.27 # its swing when the gun is hoisted off the deck (inboard)
const BOOM_OUT := 0.17 # ...and out over the side
const HOOK := 1.6 # from the gun's sling hook down to the ground under it


func _build_lowering() -> void:
	var deck_men: Array = []
	for i in 3:
		var r = _man(_ship, BOOM_HEEL + Vector3(-1.3 - i * 0.75, -0.05, -0.4 + i * 0.25), Vector3(1, 0, 0.1),
			{"head": "" if i == 1 else "shako", "torso": "shirt", "primary": "none"}, true)
		deck_men.append(r)
	var boom := Node3D.new()
	boom.position = BOOM_HEEL
	_ship.add_child(boom)
	Props._box(boom, Vector3(0.2, 0.2, BOOM_LEN), Props.WOOD, Vector3(0, 0, -BOOM_LEN * 0.5))
	Props._box(boom, Vector3(0.34, 0.3, 0.34), Props.WOOD_DARK, Vector3(0, -0.1, -BOOM_LEN)) # the block
	var boat := _make_boat(false, 3, true)
	add_child(boat["node"])
	var gun := Props.cannon()
	add_child(gun)
	var in_boat: Array = []
	for i in 2:
		var r2 = _man(boat["node"], Vector3(0.0, 0.05, -2.2 + i * 4.4), Vector3(0, 0, 1 if i == 0 else -1), {"torso": "shirt", "head": ""}, true)
		in_boat.append(r2)
	var ropes := {}
	for k in ["tackle_a", "tackle_b", "sling_a", "sling_b", "along", "fall", "guy_a", "guy_b"]:
		ropes[k] = _rope(self)
	_lower = {"boom": boom, "boat": boat, "gun": gun, "ropes": ropes, "deck": deck_men, "hands": in_boat}
	(boat["node"] as Node3D).visible = false
	gun.visible = false
	boom.visible = false


## A ship's boat, open, with thwarts and an oar for every rower; with a gun
## lashed amidships. Returns {"node", "oars", "cox", "bow_man", "length"};
## each oar is [pivot, side, rower].
## The rowers face the stern; each sits on a thwart with his rowlock just
## aft of him, so the oar's handle is in front of his chest: at the catch
## he leans forward with his arms out toward the stern, at the finish he
## has leant back and drawn the handle in to his ribs. A launch (`big`) is
## broad and long enough to take a gun amidships, the rowers fore and aft.
func _make_boat(with_gun: bool, rows: int, big := false) -> Dictionary:
	var b := Node3D.new()
	big = big or with_gun
	var length := 9.0 if big else 5.8
	var beam := 2.5 if big else 1.7
	var hw := beam * 0.5
	var hull := Props.WOOD.darkened(0.15)
	Props._box(b, Vector3(beam, 0.12, length), hull, Vector3(0, 0.0, 0)) # bottom
	for side in [-1.0, 1.0]:
		Props._box(b, Vector3(0.08, 0.6, length), hull, Vector3(side * hw, 0.27, 0))
		Props._box(b, Vector3(0.12, 0.06, length), Props.WOOD, Vector3(side * hw, 0.6, 0)) # gunwale
	Props._box(b, Vector3(beam * 0.6, 0.6, beam * 0.7), hull, Vector3(0, 0.27, -length * 0.5 - beam * 0.2), Vector3(0, 45, 0)) # bow
	Props._box(b, Vector3(beam + 0.02, 0.6, 0.1), hull, Vector3(0, 0.27, length * 0.5)) # transom
	var oars: Array = []
	var zs: Array = []
	if big:
		# Two banks forward of the gun's place and two aft of it.
		zs = [-length * 0.5 + 1.3, -length * 0.5 + 2.4, length * 0.5 - 2.3, length * 0.5 - 1.2]
		zs = zs.slice(0, maxi(2, rows))
	else:
		for i in rows:
			zs.append(-length * 0.5 + 1.1 + i * ((length - 2.6) / maxf(rows - 1, 1)))
	for z in zs:
		Props._box(b, Vector3(beam - 0.1, 0.06, 0.26), Props.WOOD, Vector3(0, 0.34, z)) # thwart
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * hw, 0.66, z + 0.5) # the rowlock, aft of him
			b.add_child(pivot)
			var inboard := hw - 0.12
			# The oar: the handle inboard, the loom across the gunwale, the blade out.
			Props._box(pivot, Vector3(inboard + 2.6, 0.05, 0.05), Props.WOOD.lightened(0.15), Vector3(side * (2.6 - inboard) * 0.5, 0, 0))
			Props._box(pivot, Vector3(0.6, 0.02, 0.15), Props.WOOD.lightened(0.15), Vector3(side * 2.35, 0, 0))
			var rower = _man(b, Vector3(side * hw * 0.42, 0.06, z), Vector3(0, 0, 1),
				{"primary": "none", "torso": "shirt" if randf() < 0.5 else "coat", "head": "" if randf() < 0.4 else "cap"}, true)
			rower.anim = "kneel"
			oars.append([pivot, side, rower, inboard])
	if with_gun:
		var g := Props.cannon()
		g.scale = Vector3.ONE * 0.85
		g.position = Vector3(0, 0.1, 0.0)
		b.add_child(g)
	var cox = _man(b, Vector3(0, 0.06, length * 0.5 - 0.45), Vector3(0, 0, -1), {"head": "tricorne", "torso": "coat", "primary": "none"}, true)
	var bow_man = _man(b, Vector3(0, 0.06, -length * 0.5 + 0.3), Vector3(0, 0, -1), {}, false)
	bow_man.anim = "idle"
	return {"node": b, "oars": oars, "cox": cox, "bow_man": bow_man, "length": length}


## The flotilla pulling for the shore: the hero boat (a gun aboard, the
## colours in the stern) and others spread behind.
func _build_flotilla() -> void:
	var lanes := [Vector3(0, 0, 0), Vector3(-9, 0, 14), Vector3(8, 0, 20), Vector3(-20, 0, 30), Vector3(18, 0, 38), Vector3(-2, 0, 46)]
	for i in lanes.size():
		var bd := _make_boat(i % 2 == 0, 4)
		var nd: Node3D = bd["node"]
		nd.visible = false
		add_child(nd)
		bd["lane"] = lanes[i]
		bd["phase"] = randf() * 0.15
		_boats.append(bd)
	_hero_boat = _boats[0]
	# The colours in the hero boat's stern.
	var pole := Node3D.new()
	pole.position = Vector3(0.55, 0.0, float(_hero_boat["length"]) * 0.5 - 0.25)
	(_hero_boat["node"] as Node3D).add_child(pole)
	Props._cyl(pole, 0.025, 0.03, 3.4, Props.WOOD, Vector3(0, 1.7, 0))
	_build_flag(pole, Vector3(0, 3.0, 0.62))


## The colours: Calder's blue with a white cross, in strips that wave.
func _build_flag(parent: Node3D, at: Vector3) -> void:
	# Your colours (colours.gd), in eight upright strips of six cells.
	var C := preload("res://scripts/colours.gd")
	var f: Dictionary = C.flag()
	for i in 8:
		var s := Node3D.new()
		s.position = at + Vector3(0, 0, 0.13 * i - 0.5)
		parent.add_child(s)
		for j in 6:
			var col := C.col_at(f, (i + 0.5) / 8.0, (j + 0.5) / 6.0)
			Props._box(s, Vector3(0.02, 0.135, 0.135), col, Vector3(0, 0.4 - (j + 0.5) * 0.1333, 0))
		_flag.append([s, i, s.position])


## The beach where the boats come in: grounded boats, men wading ashore and
## two teams dragging guns up the sand on ropes, the Major on the sand.
func _build_landing() -> void:
	var root := Node3D.new()
	root.visible = false
	_beach.add_child(root)
	var boats: Array = []
	for i in 4:
		var bd := _make_boat(true, 3)
		var nd: Node3D = bd["node"]
		nd.position = Vector3(-9.0 + i * 6.0, 0.05, SHORE_Z + 3.5 + (i % 2) * 2.0)
		nd.rotation.y = randf_range(-0.15, 0.15)
		root.add_child(nd)
		for o in bd["oars"]:
			(o[0] as Node3D).rotation = Vector3(0, 0.0, 0.25 * float(o[1])) # oars tossed up
		boats.append(bd)
	# Men coming ashore through the shallows, up to the line of the works.
	var waders: Array = []
	for i in 18:
		var start := Vector3(randf_range(-12, 12), 0, SHORE_Z + randf_range(0.0, 6.0))
		var end := Vector3(start.x + randf_range(-4, 4), 0, randf_range(8.0, 20.0))
		var r = _man(root, start, end - start, {"torso": "coat" if i % 3 else "shirt"})
		r.anim = "walk"
		waders.append([r, start, end, randf_range(0.0, 3.0)])
	# Two guns on drag ropes, four men a rope, leaning into it.
	var hauls: Array = []
	for g in 2:
		var gun := Props.cannon()
		gun.rotation.y = PI # trail first up the beach
		gun.position = Vector3(-4.0 + g * 9.0, 0, SHORE_Z - 1.0)
		root.add_child(gun)
		var men: Array = []
		var ropes: Array = []
		for side in [-1.0, 1.0]:
			ropes.append(_rope(root))
			for k in 4:
				var r2 = _man(root, Vector3.ZERO, Vector3(0, 0, -1), {"torso": "shirt", "head": "" if k % 2 else "shako"})
				r2.anim = "haul"
				men.append([r2, side, k])
		hauls.append({"gun": gun, "men": men, "ropes": ropes, "x": gun.position.x})
	var major = _man(root, Vector3(-7.5, 0, 33), Vector3(0.3, 0, 1), {}, true, "officer") # (off to the side, clear of the shot)
	_landing = {"root": root, "boats": boats, "waders": waders, "hauls": hauls, "major": major}


## The entrenched beach: the rampart (it rises as they dig), a line of
## diggers, the guns in their embrasures with their crews, and the Major on
## a crate before the colours.
func _build_works() -> void:
	_works = Node3D.new()
	_works.visible = false
	_beach.add_child(_works)
	var rampart := Props.earthwork(80.0, GUN_X)
	rampart.name = "rampart"
	rampart.position = Vector3(0, 0, 5)
	_works.add_child(rampart)
	for x in GUN_X:
		var gc = GunCrew.make(null, Vector3(x, 0, 6.8), 0.0, 12.0)
		_works.add_child(gc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 36:
		var x := rng.randf_range(-40, 40)
		var skip := false
		for gx in GUN_X:
			if absf(x - gx) < 2.6:
				skip = true
		if absf(x + 3.0) < 4.5:
			skip = true # (clear in front of the last shot's camera)
		if skip:
			continue
		var r = _man(_works, Vector3(x, 0, rng.randf_range(6.6, 8.2)), Vector3(rng.randf_range(-0.2, 0.2), 0, -1),
			{"primary": "spade", "torso": "shirt" if i % 2 == 0 else "coat", "head": "" if i % 3 == 0 else "shako"}, true)
		_diggers.append([r, rng.randf()])
	# Men carrying stores behind the line.
	for i in 6:
		var r3 = _man(_works, Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(12, 18)), Vector3(rng.randf_range(-1, 1), 0, -0.4), {"torso": "shirt"})
		r3.anim = "walk"
	# The Major on his crate, the colours planted beside him.
	_major = Node3D.new()
	_major.position = Vector3(2.0, 0, 15.0)
	_works.add_child(_major)
	Props._box(_major, Vector3(1.3, 0.8, 1.0), Props.WOOD, Vector3(0, 0.4, 0))
	Props._box(_major, Vector3(1.0, 0.5, 0.8), Props.WOOD.darkened(0.2), Vector3(1.2, 0.25, 0.4))
	var pole := Node3D.new()
	pole.position = Vector3(-1.2, 0, 0.3)
	_major.add_child(pole)
	Props._cyl(pole, 0.035, 0.045, 4.6, Props.WOOD, Vector3(0, 2.3, 0))
	_build_flag(pole, Vector3(0, 4.0, 0.62))
	_major_rig = _man(_major, Vector3(0, 0.8, 0), Vector3(-0.1, 0, -1), {}, true, "officer")
	# Sentries on the rampart, looking out at the trees.
	for x in [-5.2, -1.2]:
		var s = _man(_works, Vector3(x, 0.72, 5.1), Vector3(0.05, 0, -1), {})
		s.anim = "idle"
	# Birds that burst out of the trees when the drums start.
	for i in 26:
		var bird := Node3D.new()
		Props._box(bird, Vector3(0.5, 0.05, 0.16), Color(0.08, 0.08, 0.09), Vector3.ZERO)
		bird.position = Vector3(randf_range(-30, 30), randf_range(10, 16), randf_range(-92, -110))
		bird.visible = false
		_beach.add_child(bird)
		_birds.append([bird, Vector3(randf_range(-3, 3), randf_range(3, 6), randf_range(2, 6))])


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	# Letterbox bars: it's a film.
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
	_band.anchor_left = 0.0
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


## Night storm, or the golden dawn after it.
func _set_storm(on: bool) -> void:
	if on:
		_env.background_color = Color(0.03, 0.04, 0.06)
		_env.ambient_light_color = Color(0.35, 0.4, 0.5)
		_env.ambient_light_energy = 0.5
		_env.fog_light_color = Color(0.05, 0.06, 0.08)
		_env.fog_density = 0.008
		_sun.light_energy = 0.15
		_sun.light_color = Color(0.6, 0.7, 0.9)
		return
	# Dawn: the shader sky, a low gold sun over the sea behind them.
	get_node("storm_env").queue_free()
	_sun.queue_free()
	_env = Look.environment(self, "dusk", Color(0.85, 0.7, 0.6), 0.004)
	_sun = _env.get_meta("sun")
	_sun.rotation_degrees = Vector3(-14, -20, 0) # rising over the sea behind them
	var mat := _sea.mesh.material as ShaderMaterial
	mat.set_shader_parameter("height", 0.14)
	mat.set_shader_parameter("speed", 0.6)
	mat.set_shader_parameter("deep", Color(0.16, 0.24, 0.3))
	mat.set_shader_parameter("crest", Color(0.85, 0.7, 0.55))
	_rain.emitting = false
	_beach.visible = true
	# The wreck where she struck, heeled over on the rocks.
	_ship.position = ROCKS_AT + Vector3(0, -1.2, 0)
	_ship.rotation = Vector3(-0.1, 0.5, 0.38)
	(_ship.get_node("main_mast") as Node3D).rotation.x = 1.25
	(_ship.get_node("fore_mast") as Node3D).rotation.z = -0.5


# ---------------------------------------------------------------- the timeline

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var t := _t
	for st in _snaps:
		if t - delta < st and t >= st:
			_snap.call_deferred(st)
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
	for d in _drums:
		if t - delta < d and t >= d:
			_play("drum", -4.0 + (d - 58.0) * 0.6, randf_range(0.95, 1.05))
	_wave_flags(t)

	if t < T_STRIKE:
		_shot_storm(t, delta)
	elif t < T_GUNS:
		_shot_strike(t, delta)
	elif t < T_BOATS:
		if not _dawn:
			_dawn = true
			_set_storm(false)
			_storm.volume_db = -80.0
			_surf.volume_db = -12.0
			(_lower["boat"]["node"] as Node3D).visible = true
			(_lower["gun"] as Node3D).visible = true
			(_lower["boom"] as Node3D).visible = true
			for r in _storm_crew:
				(r.get_parent() as Node3D).visible = false
		_shot_guns(t - T_GUNS, delta)
	elif t < T_LANDING:
		_shot_boats(t - T_BOATS, delta)
	elif t < T_WORKS:
		_shot_landing(t - T_LANDING, delta)
	elif t < T_MAJOR:
		_shot_works(t - T_WORKS, delta)
	elif t < T_FOREST:
		_shot_major(t - T_MAJOR, delta)
	elif t < LENGTH:
		_shot_forest(t - T_FOREST, delta)
	else:
		_finish()


func _set_cam(at: Vector3, look: Vector3, fov := 60.0) -> void:
	_cam.fov = fov
	_cam.transform = Transform3D(Basis.looking_at(look - at), at)


## Following the ship through the storm, rolling and pitching.
func _shot_storm(t: float, delta: float) -> void:
	_ship.position.z -= 7.0 * delta
	_rock_ship(t, 1.0)
	var at := _ship.position + Vector3(22, 7 + sin(t * 0.8), 18 - t * 1.2)
	_set_cam(at, _ship.position + Vector3(0, 5, -4))


## Ahead of her: the rocks loom, she strikes, the mainmast comes down.
func _shot_strike(t: float, delta: float) -> void:
	var strike := 10.2
	if t < strike:
		var k := (t - T_STRIKE) / (strike - T_STRIKE)
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
	_set_cam(at + jitter, _ship.position + Vector3(0, 5, 0))


func _rock_ship(t: float, amount: float) -> void:
	_ship.rotation.z = sin(t * 1.3) * 0.16 * amount
	_ship.rotation.x = sin(t * 0.9 + 1.0) * 0.07 * amount
	_ship.position.y = sin(t * 1.1) * 0.8 * amount


## The guns: the derrick on the wreck hoists a gun off the deck, swings it
## out over the side, and the men on the fall lower it hand over hand into
## the launch alongside, where two men take it and guide it onto its chocks.
## Low from the water, looking up.
##   0.0-1.8  hoist off the deck
##   1.8-4.0  the boom swings out
##   4.0-8.0  lowered, steadily, swaying less as it nears the boat
func _boom_tip(swing: float) -> Vector3:
	var d := Vector3(cos(BOOM_ELEV) * cos(swing), sin(BOOM_ELEV), cos(BOOM_ELEV) * sin(swing))
	return BOOM_HEEL + d * BOOM_LEN


func _shot_guns(t: float, delta: float) -> void:
	var boom: Node3D = _lower["boom"]
	var swing := lerpf(BOOM_IN, BOOM_OUT, smoothstep(1.8, 4.0, t))
	var tip_l := _boom_tip(swing)
	boom.transform = Transform3D(Basis.looking_at(tip_l - BOOM_HEEL, Vector3.UP), BOOM_HEEL)
	var xf := _ship.global_transform
	var tip: Vector3 = xf * tip_l
	var yaw := atan2(-(xf.basis.z).x, -(xf.basis.z).z) + PI # the ship's heading, laid flat
	# The launch lies alongside under the boom's outboard reach.
	var out_tip: Vector3 = xf * _boom_tip(BOOM_OUT)
	var boat: Node3D = _lower["boat"]["node"]
	boat.position = Vector3(out_tip.x, 0.08 + sin(t * 1.4) * 0.08, out_tip.z)
	boat.rotation = Vector3(sin(t * 1.1) * 0.02, yaw, sin(t * 1.3) * 0.03)
	var seat := boat.global_transform * Vector3(0, 0.12, 0)
	# Where the gun sat on the deck: under the boom's inboard reach.
	var in_tip: Vector3 = xf * _boom_tip(BOOM_IN)
	var deck_y := (xf * Vector3((xf.affine_inverse() * in_tip).x, 2.35, (xf.affine_inverse() * in_tip).z)).y
	var lifted := in_tip.y - (deck_y + 1.3) - HOOK # rope out when it's clear of the deck
	var drop: float
	if t < 1.8:
		drop = lerpf(in_tip.y - deck_y - HOOK, lifted, smoothstep(0.0, 1.8, t))
	elif t < 4.0:
		drop = lifted
	else:
		drop = lerpf(lifted, tip.y - seat.y - HOOK, smoothstep(4.0, 8.0, t))
	var hook := tip - Vector3(0, drop, 0)
	var gun: Node3D = _lower["gun"]
	# It swings a little on the tackle, less once the boat men have it.
	var free := 1.0 - smoothstep(6.5, 8.0, t)
	var sway := Vector3(sin(t * 1.6), 0, cos(t * 1.2)) * 0.12 * free
	gun.global_position = hook - Vector3(0, HOOK, 0) + sway
	gun.rotation = Vector3(sin(t * 1.3) * 0.05 * free, yaw + sin(t * 0.7) * 0.12 * free, sin(t * 1.1) * 0.04 * free)
	var g := gun.global_transform
	var rp: Dictionary = _lower["ropes"]
	var hook_at := gun.global_position + Vector3(0, HOOK, 0)
	# The tackle (two parts from the block to the hook), the sling round the
	# barrel, the fall from the block back along the boom to the heel and
	# down to the men on deck.
	var side := (xf.basis * Vector3(1, 0, 0)).normalized() * 0.07
	_rope_between(rp["tackle_a"], tip + side, hook_at + side)
	_rope_between(rp["tackle_b"], tip - side, hook_at - side)
	_rope_between(rp["sling_a"], hook_at, g * Vector3(0, 0.95, -1.0))
	_rope_between(rp["sling_b"], hook_at, g * Vector3(0, 0.95, 0.55))
	var heel: Vector3 = xf * (BOOM_HEEL + Vector3(0, 0.25, 0))
	_rope_between(rp["along"], tip + Vector3(0, 0.15, 0), heel)
	var deck_men: Array = _lower["deck"]
	var lead: Node3D = deck_men[deck_men.size() - 1]
	_rope_between(rp["fall"], heel, lead.global_position + Vector3(0, 1.0, 0))
	# The guys that swing the boom, from its head to the ship's side.
	_rope_between(rp["guy_a"], tip, xf * Vector3(2.4, 3.3, -3.5))
	_rope_between(rp["guy_b"], tip, xf * Vector3(2.4, 3.3, 6.5))
	# The men on the fall: hand over hand, leaning back against the weight.
	for i in deck_men.size():
		var r = deck_men[i]
		var u := t * 1.4 + i * 0.35
		var reach := 0.5 + 0.5 * sin(u * TAU * 0.5)
		r.t_hand_r = Vector3(0.05, 1.05 + 0.12 * reach, -0.45 - 0.15 * reach)
		r.t_hand_l = Vector3(-0.05, 0.98 - 0.08 * reach, -0.25 + 0.1 * reach)
		r.t_lean = -0.22
		r.pose_rate = 8.0
		r.anim_time += delta
	# The men in the boat: arms up to the gun as it comes within reach.
	for r2 in _lower["hands"]:
		var near: float = clampf(1.0 - (gun.global_position.y - (r2.global_position.y + 0.3)) / 2.5, 0.0, 1.0)
		var gp: Vector3 = gun.global_transform * Vector3(0, 0.95, 0)
		var to: Vector3 = (gp - r2.global_position) * Vector3(1, 0, 1)
		if to.length_squared() > 0.01:
			r2.facing = to.normalized()
		if near > 0.05:
			var rest_r: Vector3 = r2.global_transform * Vector3(0.28, 0.9, -0.1)
			var rest_l: Vector3 = r2.global_transform * Vector3(-0.28, 0.9, -0.1)
			_hands(r2, rest_r.lerp(gp + Vector3(0.15, 0, 0), near), rest_l.lerp(gp - Vector3(0.15, 0, 0), near))
		else:
			r2.t_hand_r = Vector3(0.25, 0.92, -0.2)
			r2.t_hand_l = Vector3(-0.25, 0.92, -0.2)
		r2.anim_time += delta
	# The launch's rowers sit easy, oars tossed upright.
	for o in _lower["boat"]["oars"]:
		var pv: Node3D = o[0]
		pv.rotation = Vector3(0, 0.0, 1.25 * float(o[1]))
		var rw = o[2]
		rw.t_hand_r = Vector3(0.12, 0.85, -0.3)
		rw.t_hand_l = Vector3(-0.12, 0.8, -0.3)
		rw.t_lean = 0.1
	# Low on the water off the bow quarter, looking up at the hull, the boom
	# and the gun coming down; a slow drift.
	# Out from the launch, away from the hull, a little toward the bow.
	var outward := (boat.global_position - xf.origin) * Vector3(1, 0, 1)
	outward = outward.normalized()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var at: Vector3 = boat.global_position + outward * (10.5 - t * 0.15) + fwd * 4.5
	at.y = 1.9
	var look := tip.lerp(seat, 0.55)
	_set_cam(at, look + Vector3(0, -0.4, 0), 44.0)


## Rowing: every boat pulls in time to its cox's beat; oars dip, sweep and
## feather; rowers lean back into the stroke. The camera runs alongside the
## hero boat at the waterline, the others and the wreck behind.
func _shot_boats(t: float, delta: float) -> void:
	var base := Vector3(-6.0, 0.0, 100.0 - t * 3.6)
	for i in _boats.size():
		var bd: Dictionary = _boats[i]
		var nd: Node3D = bd["node"]
		nd.visible = true
		var lane: Vector3 = bd["lane"]
		nd.position = base + lane + Vector3(0, 0.12 + sin(t * 1.5 + i) * 0.1, 0)
		nd.rotation = Vector3(sin(t * 1.1 + i) * 0.025, 0.0, sin(t * 1.3 + i) * 0.04)
		_row(bd, t, delta)
	var hero: Node3D = _hero_boat["node"]
	var at := hero.global_position + Vector3(5.2, 1.1, 1.5 - t * 0.3)
	_set_cam(at, hero.global_position + Vector3(-1.0, 1.1, -2.0 + t * 0.12), 58.0)


## One stroke cycle for a boat's oars and rowers. The drive (blade in the
## water, the rower leaning back and drawing the handle to his ribs) takes
## a little under half the cycle; the recovery (blade feathered just clear
## of the water, the rower swinging forward with his arms out) the rest.
func _row(bd: Dictionary, t: float, delta: float) -> void:
	var period := 2.4
	var u := fmod(t / period + float(bd.get("phase", 0.0)), 1.0)
	var sweep := 0.0 # + toward the stern (the catch), - toward the bow (the finish)
	var dip := 0.0
	var lean := 0.0
	if u < 0.42:
		var d := smoothstep(0.0, 0.42, u)
		sweep = lerpf(0.5, -0.38, d)
		dip = 0.16 * sin(d * PI) + 0.04
		lean = lerpf(0.42, -0.2, d)
	else:
		var r := smoothstep(0.42, 1.0, u)
		sweep = lerpf(-0.38, 0.5, r)
		dip = -0.08 # (feathered, clear of the water)
		lean = lerpf(-0.2, 0.42, r)
	for o in bd["oars"]:
		var pivot: Node3D = o[0]
		var side: float = o[1]
		var inboard: float = o[3] if o.size() > 3 else 0.72
		pivot.rotation = Vector3(0.0, sweep * side, -dip * side)
		var rower = o[2]
		# Both hands on the handle, a hand's breadth apart.
		var handle: Vector3 = pivot.global_transform * Vector3(-side * (inboard - 0.08), 0.0, 0.0)
		var along: Vector3 = (pivot.global_transform.basis * Vector3(side, 0, 0)).normalized()
		_hands(rower, handle - along * 0.04, handle - along * 0.26)
		rower.t_lean = lean
		rower.pose_rate = 12.0
		rower.anim = "kneel"
		rower.anim_time += delta
	# The cox in the stern, calling the stroke with a sweep of his arm.
	var cox = bd["cox"]
	var beat := sin(u * TAU)
	cox.t_hand_r = Vector3(0.28, 1.3 + 0.22 * maxf(0.0, beat), -0.32)
	cox.t_hand_l = Vector3(-0.25, 0.95, 0.0)
	cox.anim_time += delta


## The landing: the boats grounded in the shallows, men wading ashore and
## up the sand; two guns dragged up the beach on ropes; the Major on the
## sand waving them on. The camera on the beach looking back out to sea.
func _shot_landing(t: float, delta: float) -> void:
	var root: Node3D = _landing["root"]
	root.visible = true
	for bd in _boats:
		(bd["node"] as Node3D).visible = false
	for w in _landing["waders"]:
		var r = w[0]
		var k := clampf((t - float(w[3])) / 9.0, 0.0, 1.0)
		var p: Vector3 = (w[1] as Vector3).lerp(w[2], k)
		(r.get_parent() as Node3D).position = p
		r.anim = "walk" if k > 0.0 and k < 1.0 else "idle"
		r.move_speed = 1.8 if r.anim == "walk" else 0.0
		r.facing = ((w[2] as Vector3) - (w[1] as Vector3)).normalized()
	for h in _landing["hauls"]:
		var gun: Node3D = h["gun"]
		var surge := 0.5 + 0.5 * sin(t * 2.6) # heave... and heave
		var z: float = SHORE_Z - 1.0 - t * 1.6 - 0.3 * surge
		gun.position = Vector3(float(h["x"]), 0, z)
		var hitch := gun.global_transform * Vector3(0, 0.45, 2.6) # the trail's end
		for m in h["men"]:
			var r2 = m[0]
			var side: float = m[1]
			var k2: int = m[2]
			var p2 := hitch + Vector3(side * (0.7 + k2 * 0.18), 0, -2.0 - k2 * 1.25)
			p2.y = 0.0
			(r2.get_parent() as Node3D).position = p2
			r2.facing = Vector3(side * 0.08, 0, -1)
			r2.move_speed = 1.6
			r2.anim = "haul"
		var ropes: Array = h["ropes"]
		for i in 2:
			var side2 := -1.0 if i == 0 else 1.0
			_rope_between(ropes[i], hitch, hitch + Vector3(side2 * 1.4, 0.9, -7.3))
	# The Major, sabre out, pointing up the beach.
	var mj = _landing["major"]
	mj.hand_item = "saber"
	mj.t_grip = Vector3(0.38, 1.85, -0.5)
	mj.t_dir = Vector3(0.1, 0.55, -1)
	mj.t_hand_l = Vector3(-0.25, 1.0, 0.0)
	mj.facing = Vector3(0.35, 0, -1)
	mj.anim_time += delta
	var at := Vector3(14.0 - t * 0.6, 1.7, 22.0 + t * 0.4)
	_set_cam(at, Vector3(0.0, 1.0, SHORE_Z - 6.0 - t * 1.2), 55.0)


## The works: a crane shot rising over the line of diggers and the rampart
## growing, the guns in the embrasures, the Major on his crate.
func _shot_works(t: float, delta: float) -> void:
	(_landing["root"] as Node3D).visible = false
	_works.visible = true
	var rampart: Node3D = _works.get_node("rampart")
	rampart.scale = Vector3(1.0, lerpf(0.35, 1.0, smoothstep(0.0, 9.0, t)), 1.0)
	_dig(delta)
	_pose_major(t, false)
	var k := smoothstep(0.0, 9.4, t)
	var at := Vector3(-22.0 + t * 2.2, lerpf(1.8, 7.5, k), lerpf(13.0, 19.0, k))
	_set_cam(at, Vector3(-8.0 + t * 1.8, 0.9, 1.0), 56.0)


## The diggers: drive the spade in, lever the sand up, throw it onto the
## rampart, again.
func _dig(delta: float) -> void:
	for d in _diggers:
		var r = d[0]
		r.anim_time += delta
		var u := fmod(float(r.anim_time) * 0.75 + float(d[1]), 1.0)
		var grip: Vector3
		var dir: Vector3
		var lean := 0.0
		if u < 0.35:
			var a := smoothstep(0.0, 0.35, u)
			grip = Vector3(0.16, 1.05, -0.3).lerp(Vector3(0.12, 0.72, -0.42), a)
			dir = Vector3(0, -0.6, -0.8).lerp(Vector3(0, -0.88, -0.48), a)
			lean = lerpf(0.25, 0.55, a)
		elif u < 0.62:
			var b := smoothstep(0.35, 0.62, u)
			grip = Vector3(0.12, 0.72, -0.42).lerp(Vector3(0.1, 1.2, -0.18), b)
			dir = Vector3(0, -0.88, -0.48).lerp(Vector3(0, 0.12, -1), b)
			lean = lerpf(0.55, 0.15, b)
		elif u < 0.78:
			var c := smoothstep(0.62, 0.78, u)
			grip = Vector3(0.1, 1.2, -0.18).lerp(Vector3(0.08, 1.38, -0.4), c)
			dir = Vector3(0, 0.12, -1).lerp(Vector3(0, 0.55, -0.85), c)
			lean = 0.05
		else:
			var e := smoothstep(0.78, 1.0, u)
			grip = Vector3(0.08, 1.38, -0.4).lerp(Vector3(0.16, 1.05, -0.3), e)
			dir = Vector3(0, 0.55, -0.85).lerp(Vector3(0, -0.6, -0.8), e)
			lean = lerpf(0.05, 0.25, e)
		r.t_grip = grip
		r.t_dir = dir
		r.t_hand_r = null
		r.t_hand_l = grip + dir.normalized() * 0.5
		r.t_lean = lean
		r.pose_rate = 10.0


## The Major on his crate: sabre raised toward the forest (or held at the
## carry, surveying the works).
func _pose_major(t: float, raised: bool) -> void:
	var r = _major_rig
	r.hand_item = "saber"
	r.anim_time += get_process_delta_time()
	if raised:
		var k := smoothstep(0.6, 2.2, t)
		r.t_grip = Vector3(0.3, 1.32, -0.3).lerp(Vector3(0.42, 1.95, -0.48), k)
		r.t_dir = Vector3(0.1, 0.9, -0.4).lerp(Vector3(0.05, 0.42, -1), k)
		r.t_hand_l = Vector3(-0.22, 1.0, 0.02)
		r.t_lean = -0.05
	else:
		r.t_grip = Vector3(0.3, 1.0, -0.15)
		r.t_dir = Vector3(0.05, 1, 0.1)
		r.t_hand_l = Vector3(-0.22, 1.0, 0.02)
	r.pose_rate = 6.0
	r.facing = Vector3(sin(t * 0.3) * 0.25, 0, -1)


## The Major: low and close, the colours flying behind him; he raises his
## sabre at the forest. A slow push in.
func _shot_major(t: float, delta: float) -> void:
	_dig(delta)
	_pose_major(t, true)
	var head: Vector3 = _major.global_position + Vector3(0, 2.5, 0)
	var at := _major.global_position + Vector3(-2.4 + t * 0.12, 1.0, -3.6 + t * 0.2)
	_set_cam(at, head + Vector3(0.2, -0.1, 0), lerpf(50.0, 38.0, t / 7.6))


## From behind the gabions: the silent forest. Then birds burst out of the
## trees, and the drums begin.
func _shot_forest(t: float, delta: float) -> void:
	_dig(delta)
	_pose_major(t + 8.0, true)
	if t > 1.0:
		for b in _birds:
			var bird: Node3D = b[0]
			bird.visible = true
			var v: Vector3 = b[1]
			bird.position += v * delta
			bird.rotation.z = sin(t * 18.0 + v.x) * 0.5
			b[1] = v + Vector3(0, -0.3, 0.2) * delta
	var at := Vector3(-3.0, 1.9, 8.4 - t * 0.15)
	_set_cam(at, Vector3(-1.0 + t * 0.2, 2.5 + t * 0.4, -100.0), 44.0)


func _wave_flags(t: float) -> void:
	for f in _flag:
		var s: Node3D = f[0]
		var i: int = f[1]
		var home: Vector3 = f[2]
		s.position = home + Vector3(sin(t * 5.0 - i * 0.8) * (0.04 + i * 0.022), 0, 0)
		s.rotation.y = cos(t * 5.0 - i * 0.8) * 0.3


func _fade_amount(t: float) -> float:
	if t < 0.8:
		return 1.0 - t / 0.8
	if t > 12.8 and t < 14.8:
		return clampf(1.0 - absf(t - T_GUNS) / 0.9, 0.0, 1.0)
	# Short dips to black between the dawn shots.
	for cut in [T_BOATS, T_LANDING, T_WORKS, T_MAJOR, T_FOREST]:
		if absf(t - cut) < 0.35:
			return clampf(1.0 - absf(t - cut) / 0.35, 0.0, 1.0) * 0.85
	if t > LENGTH - 1.6:
		return clampf((t - (LENGTH - 1.6)) / 1.6, 0.0, 1.0)
	return 0.0


func _update_caption(t: float) -> void:
	var text := ""
	var a := 0.0
	for c in _captions:
		if t >= float(c[0]) and t <= float(c[1]):
			text = c[2]
			a = clampf(minf(t - float(c[0]), float(c[1]) - t) / 0.6, 0.0, 1.0)
	_caption.text = text
	_band.visible = text != ""
	_band.modulate.a = a


func _snap(st: float) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://i_%04.1f.png" % st)


func _finish() -> void:
	if _done:
		return
	_done = true
	if "--intro" in OS.get_cmdline_user_args() or not _snaps.is_empty():
		print("INTRO DONE at %.1fs" % _t)
		get_tree().quit()
		return
	Loading.change(BATTLE)
