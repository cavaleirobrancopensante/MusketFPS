extends Node3D
## Walking into a settlement, in first person.
##
## The place is built from the map: what kind it is (a village round a
## well, a palisaded town with a church, a walled city with a keep and a
## market, a dwarf hold cut into the rock), whose it is (Aurest plaster and
## red tiles, Vellish timber and dark thatch, Dwarvish stone), and what's
## around it on the map: a river there runs through the streets with a
## bridge, a coast gives a shore and jetties, forest crowds the walls, hills
## stand behind. The same seed builds the same town every visit.
##
## Its people (folk.gd) go about their work. Walk up to one and TALK; the
## conversation panel is where you greet, give, ask, show the musket or ask
## them to join, with signs or the words you've learned (tongue.gd). Your
## men wait at the gate. LEAVE takes you back to the map.

const Folk := preload("res://scripts/folk.gd")
const Tongue := preload("res://scripts/tongue.gd")
const UI := preload("res://scripts/ui.gd")
const Lore := preload("res://scripts/lore.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const Townsfolk := preload("res://scripts/townsfolk.gd")
const MAP := "res://scenes/map.tscn"

const GOLD := Color(0.95, 0.8, 0.45)
const DIM := Color(0.72, 0.74, 0.8)
const RED := Color(0.95, 0.42, 0.35)
const GREEN := Color(0.55, 0.9, 0.55)
const SPEED := 4.2
const LOOK := 0.005
const TALK_RANGE := 3.6
const JOY_R := 70.0

var sid := -1
var st: Dictionary
var sur: Dictionary
var kind := "village"
var fac := "aurest"
var lang := ""
var R := 30.0
var underground := false
var _rng := RandomNumberGenerator.new()
var _river_p := Vector3.ZERO # a point on the river line
var _river_d := Vector3.RIGHT # its direction
var _bridge := Vector3.INF
var _shore_n := Vector3.ZERO # towards the sea, if there's a coast
var _shore_d := 0.0
var _gate := Vector3.ZERO
var _obstacles: Array = [] # Rect2 (x, z) of houses etc., for the folk
var _folk: Array = [] # townsfolk nodes
var _spots := {} # job -> [Vector3]

# You.
var _me: CharacterBody3D
var _cam: Camera3D
var _pitch := 0.0
var _move := Vector2.ZERO
var _joy_i := -1
var _joy_o := Vector2.ZERO
var _joy_p := Vector2.ZERO
var _look_i := -1
var _look_last := Vector2.ZERO

# The screen.
var _ui: Control
var _pad: Control
var _info: RichTextLabel
var _talk_btn: Button
var _target = null
var _conv: PanelContainer
var _conv_head: RichTextLabel
var _conv_know: Label
var _conv_log: RichTextLabel
var _conv_scroll: ScrollContainer
var _conv_actions: GridContainer
var _conv_with = null
var _patience := 0
var _toast: Label
var _toast_t := 0.0
var _test := false
# The town menu: after your first visit you arrive to a slow camera over the
# town and a menu (market, people, rest, walk the streets).
var mode := "walk"
var _cine: Camera3D
var _cine_t := 0.0
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_btn: Button
var _leave_btn: Button


func _ready() -> void:
	_test = "--towntest" in OS.get_cmdline_user_args()
	Loading.begin(self)
	sid = Company.visiting
	if sid < 0 or sid >= World.gen.settlements.size():
		sid = 0
	st = World.gen.settlements[sid]
	kind = String(st["kind"])
	fac = String(st["faction"])
	lang = Tongue.lang_of(fac)
	underground = kind == "hold"
	R = {"village": 28.0, "town": 42.0, "city": 56.0, "hold": 34.0}.get(kind, 30.0)
	_rng.seed = hash("town:%d:%d" % [World.seed, sid])
	Music.set_context("camp" if World.is_night() else "map")
	await Loading.step(0.15, "Reading the land around %s..." % st["name"])
	sur = Folk.surroundings(sid)
	var batcher := BatcherScript.new()
	batcher.add_to_group("batcher")
	add_child(batcher)
	_build_env()
	_build_ground()
	await Loading.step(0.3, "Streets, water and walls...")
	_plan_water()
	_build_streets()
	_build_water()
	_build_walls()
	await Loading.step(0.5, "Houses and yards...")
	_build_square()
	_build_houses()
	await Loading.step(0.7, "Trees and fields...")
	_build_outside()
	await Loading.step(0.82, "The people of %s..." % st["name"])
	_build_men_at_gate()
	_build_folk()
	_build_me()
	await Loading.step(0.95, "")
	_build_ui()
	var tw := Folk.town(sid)
	var first_visit := int(tw.get("visits", 0)) == 0
	tw["visits"] = int(tw.get("visits", 0)) + 1
	# The water barrels are filled at the well.
	Company.stores["water"] = maxi(int(Company.stores["water"]), Company.WATER_CART)
	Company.stores["foul"] = false
	Company.save()
	_refresh_info()
	_set_mode("walk" if first_visit else "menu")
	_show_toast("%s. %s" % [st["name"], _arrival_line()], 5.0)
	Loading.done(self)
	if _test:
		_self_test.call_deferred()


func _arrival_line() -> String:
	var visits := int(Folk.town(sid).get("visits", 1))
	if visits <= 1:
		return "People stop and stare at your blue coats and long muskets. Nobody here speaks a word you know."
	var rep := int(Folk.town(sid)["rep"])
	if rep >= 10:
		return "A few people wave. They know you here."
	if rep <= -5:
		return "Doors close as you come in. They remember you."
	return "Some faces look familiar. You've been here before."


# ---------------------------------------------------------------- looks

## Walls, roofs and trim by people.
func _palette() -> Dictionary:
	match fac:
		"vell":
			return {"wall": Color(0.55, 0.44, 0.32), "wall2": Color(0.62, 0.55, 0.45), "roof": Color(0.3, 0.26, 0.2),
				"trim": Color(0.25, 0.18, 0.12), "street": Color(0.4, 0.34, 0.26)}
		"dwarves":
			return {"wall": Color(0.42, 0.4, 0.4), "wall2": Color(0.5, 0.47, 0.45), "roof": Color(0.3, 0.3, 0.32),
				"trim": Color(0.75, 0.55, 0.2), "street": Color(0.32, 0.31, 0.32)}
	return {"wall": Color(0.86, 0.82, 0.72), "wall2": Color(0.8, 0.72, 0.58), "roof": Color(0.66, 0.3, 0.2),
		"trim": Color(0.38, 0.26, 0.16), "street": Color(0.6, 0.54, 0.42)}


func _mat(col: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, col: Color, rot_y := 0.0, solid := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	if solid:
		_solid(size, pos, rot_y)
	return mi


func _solid(size: Vector3, pos: Vector3, rot_y := 0.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = rot_y
	add_child(sb)
	# For the folk: an axis-aligned rect that covers it.
	var hx := absf(cos(rot_y)) * size.x * 0.5 + absf(sin(rot_y)) * size.z * 0.5
	var hz := absf(sin(rot_y)) * size.x * 0.5 + absf(cos(rot_y)) * size.z * 0.5
	_obstacles.append(Rect2(pos.x - hx, pos.z - hz, hx * 2.0, hz * 2.0))


func _build_env() -> void:
	var env := Environment.new()
	var night: bool = World.is_night()
	if underground:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.025, 0.02)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.9, 0.6, 0.35)
		env.ambient_light_energy = 0.45
		env.fog_enabled = true
		env.fog_light_color = Color(0.08, 0.05, 0.03)
		env.fog_density = 0.03
	else:
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		if night:
			sm.sky_top_color = Color(0.02, 0.03, 0.07)
			sm.sky_horizon_color = Color(0.07, 0.08, 0.13)
			sm.ground_horizon_color = Color(0.05, 0.05, 0.07)
		else:
			sm.sky_top_color = Color(0.42, 0.55, 0.72)
			sm.sky_horizon_color = Color(0.8, 0.8, 0.76)
			sm.ground_horizon_color = Color(0.55, 0.56, 0.48)
		sky.sky_material = sm
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.5 if night else 0.8
		env.fog_enabled = true
		env.fog_light_color = Color(0.06, 0.07, 0.1) if night else Color(0.76, 0.77, 0.73)
		env.fog_density = 0.012 if night else 0.004
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0) if not night else Vector3(-38, -40, 0)
	sun.light_energy = 1.1 if not night else 0.4
	sun.light_color = Color.WHITE if not night else Color(0.55, 0.65, 1.0)
	if underground:
		sun.light_energy = 0.15
	add_child(sun)


func _build_ground() -> void:
	var col := Color(0.36, 0.44, 0.22)
	if underground:
		col = Color(0.25, 0.23, 0.22)
	elif float(sur["swamp"]) > 0.2:
		col = Color(0.3, 0.33, 0.2)
	elif float(sur["hills"]) > 0.25:
		col = Color(0.44, 0.45, 0.28)
	elif float(sur["forest"]) > 0.3:
		col = Color(0.26, 0.36, 0.18)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	add_child(ground)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	mi.mesh = pm
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	nt.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, col.darkened(0.15))
	ramp.set_color(1, col.lightened(0.08))
	nt.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = nt
	m.uv1_scale = Vector3(60, 60, 1)
	mi.material_override = m
	ground.add_child(mi)
	# The edge of the walkable world.
	for k in 4:
		var a := PI * 0.5 * k
		_solid(Vector3(300, 6, 1), Vector3(cos(a), 0, sin(a)) * (R + 70.0) + Vector3(0, 3, 0), a + PI * 0.5)


# ---------------------------------------------------------------- water

## Where the river runs (from the map) and where the shore is.
func _plan_water() -> void:
	if underground:
		return
	if sur["river"]:
		var rd: Vector2 = sur["river_dir"]
		_river_d = Vector3(rd.x, 0, rd.y).normalized()
		var n := Vector3(-_river_d.z, 0, _river_d.x)
		_river_p = n * R * (0.42 if _rng.randf() < 0.5 else -0.42)
		# The bridge: where the main street (z = 0) or the cross street (x = 0) crosses it.
		if absf(_river_d.z) > 0.3:
			var t := -_river_p.z / _river_d.z
			_bridge = _river_p + _river_d * t
		else:
			var t2 := -_river_p.x / _river_d.x
			_bridge = _river_p + _river_d * t2
	if sur["coast"]:
		var sd: Vector2 = sur["sea_dir"]
		_shore_n = Vector3(sd.x, 0, sd.y).normalized()
		_shore_d = R * 0.85


func _near_water(p: Vector3, margin: float) -> bool:
	if sur["river"] and not underground:
		var rel := p - _river_p
		var off := rel - _river_d * rel.dot(_river_d)
		if off.length() < 4.5 + margin:
			return true
	if _shore_n != Vector3.ZERO and p.dot(_shore_n) > _shore_d - margin:
		return true
	return false


func _build_water() -> void:
	var water := Color(0.22, 0.38, 0.5) if not World.is_night() else Color(0.06, 0.1, 0.16)
	if sur["river"] and not underground:
		var ang := atan2(_river_d.x, _river_d.z)
		var L := 400.0
		_box(Vector3(9, 0.05, L), _river_p + Vector3(0, 0.03, 0), water, ang)
		var n := Vector3(-_river_d.z, 0, _river_d.x)
		for side in [-1.0, 1.0]:
			_box(Vector3(1.6, 0.06, L), _river_p + n * 5.1 * side + Vector3(0, 0.02, 0), Color(0.5, 0.45, 0.33), ang)
		# Blockers along the banks, with a gap at the bridge.
		var tb := (_bridge - _river_p).dot(_river_d)
		for seg in [[-L * 0.5, tb - 3.2], [tb + 3.2, L * 0.5]]:
			var a: float = seg[0]
			var b: float = seg[1]
			if b - a > 0.5:
				_solid(Vector3(9.5, 3, b - a), _river_p + _river_d * (a + b) * 0.5 + Vector3(0, 1.5, 0), ang)
		# The bridge: a deck with rails, across the river.
		var pal := _palette()
		var stone := kind == "city"
		var deck := Color(0.45, 0.43, 0.4) if stone else Color(0.42, 0.3, 0.18)
		_box(Vector3(5.6, 0.35, 12.0), _bridge + Vector3(0, 0.12, 0), deck, ang + PI * 0.5)
		for side in [-1.0, 1.0]:
			_box(Vector3(0.25, 0.9, 12.0), _bridge + _river_d * 2.8 * side + Vector3(0, 0.6, 0), pal["trim"] if not stone else deck.darkened(0.1), ang + PI * 0.5, true)
		_spots["ferryman"] = [_bridge + n * 7.5, _bridge - n * 7.5]
		_spots["miller"] = [_river_p + _river_d * 18.0 + n * 8.0]
	if _shore_n != Vector3.ZERO:
		var sang := atan2(_shore_n.x, _shore_n.z)
		var c := _shore_n * (_shore_d + 120.0)
		_box(Vector3(500, 0.05, 240), c + Vector3(0, 0.03, 0), water, sang)
		_box(Vector3(500, 0.06, 10), _shore_n * (_shore_d - 3.0) + Vector3(0, 0.02, 0), Color(0.76, 0.7, 0.5), sang)
		_solid(Vector3(500, 3, 1), _shore_n * (_shore_d + 0.5) + Vector3(0, 1.5, 0), sang)
		var side := Vector3(-_shore_n.z, 0, _shore_n.x)
		_spots["fisher"] = []
		for k in [-1.0, 1.0]:
			var base: Vector3 = _shore_n * _shore_d + side * float(k) * 12.0
			_box(Vector3(2.4, 0.3, 14), base + _shore_n * 7.0 + Vector3(0, 0.25, 0), Color(0.42, 0.3, 0.18), sang)
			# A boat tied up beside it.
			_box(Vector3(1.6, 0.5, 4.2), base + _shore_n * 9.0 + side * 2.2 + Vector3(0, 0.15, 0), Color(0.35, 0.24, 0.14), sang)
			_spots["fisher"].append(base - _shore_n * 2.5)
		_spots["net-mender"] = _spots["fisher"]
		_spots["boatwright"] = _spots["fisher"]


# ---------------------------------------------------------------- streets and walls

func _streets() -> Array:
	# [direction, width]: the main street east-west, a cross street in towns.
	var out := [[Vector3.RIGHT, 6.0]]
	if kind != "village":
		out.append([Vector3.BACK, 5.0])
	return out


func _build_streets() -> void:
	var col: Color = _palette()["street"]
	for s in _streets():
		var d: Vector3 = s[0]
		var w: float = s[1]
		var ang := atan2(d.x, d.z)
		_box(Vector3(w, 0.04, (R + 18.0) * 2.0), Vector3(0, 0.02, 0), col, ang)
	var sq := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var r: float = {"village": 7.0, "town": 11.0, "city": 15.0, "hold": 10.0}.get(kind, 8.0)
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.05
	sq.mesh = cm
	sq.material_override = _mat(col.lightened(0.05))
	sq.position = Vector3(0, 0.025, 0)
	add_child(sq)


## The gaps in the wall: where streets (and the river) go out.
func _gap_angles() -> Array:
	var g := [0.0, PI]
	if kind != "village":
		g += [PI * 0.5, PI * 1.5]
	return g


func _build_walls() -> void:
	var pal := _palette()
	var gaps := _gap_angles()
	var n := int(TAU * R / 2.0)
	if underground:
		# The hold: a hall cut into the rock, a dark roof overhead.
		for k in 28:
			var a := TAU * k / 28.0
			_box(Vector3(9, 14, 3), Vector3(cos(a), 0, sin(a)) * (R + 4.0) + Vector3(0, 7, 0), Color(0.22, 0.2, 0.2), -a + PI * 0.5, true)
		var roof := _box(Vector3((R + 10.0) * 2.0, 1.0, (R + 10.0) * 2.0), Vector3(0, 12.0, 0), Color(0.12, 0.11, 0.11))
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in 6:
			for j in 2:
				var px := -R * 0.7 + i * R * 0.28
				var pz := -8.0 if j == 0 else 8.0
				var pil := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.9
				cyl.bottom_radius = 1.1
				cyl.height = 12.0
				pil.mesh = cyl
				pil.material_override = _mat(Color(0.36, 0.33, 0.32))
				pil.position = Vector3(px, 6, pz)
				add_child(pil)
				_solid(Vector3(1.8, 12, 1.8), Vector3(px, 6, pz))
		# Forge-glow lamps.
		for k2 in 6:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 2.0
			l.omni_range = 16.0
			l.position = Vector3(-R * 0.6 + k2 * R * 0.24, 5.0, 0)
			add_child(l)
		_gate = Vector3(R + 2.0, 0, 0)
		return
	for k in n:
		var a := TAU * (k + 0.5) / n
		var skip := false
		for g in gaps:
			if absf(angle_difference(a, g)) < 5.0 / R:
				skip = true
		var p := Vector3(cos(a), 0, sin(a)) * R
		if _near_water(p, 1.0) and not _near_water(p, -3.0):
			pass
		if _near_water(p, 0.0):
			skip = true
		if skip:
			continue
		match kind:
			"village":
				if k % 2 == 0:
					_box(Vector3(0.15, 1.1, 0.15), p + Vector3(0, 0.55, 0), pal["trim"])
				_box(Vector3(2.1, 0.12, 0.08), p + Vector3(0, 0.8, 0), pal["trim"], -a + PI * 0.5, true)
			"town":
				_box(Vector3(2.05, 3.2, 0.35), p + Vector3(0, 1.6, 0), Color(0.42, 0.32, 0.2), -a + PI * 0.5, true)
			"city":
				_box(Vector3(2.05, 5.0, 1.2), p + Vector3(0, 2.5, 0), Color(0.62, 0.6, 0.55), -a + PI * 0.5, true)
	if kind == "city":
		for k3 in 8:
			var a3 := TAU * k3 / 8.0 + 0.39
			var tp := Vector3(cos(a3), 0, sin(a3)) * R
			if not _near_water(tp, 2.0):
				_box(Vector3(4, 8, 4), tp + Vector3(0, 4, 0), Color(0.58, 0.56, 0.52), 0.0, true)
	# Gate posts at each street.
	for g in gaps:
		var gp := Vector3(cos(g), 0, sin(g)) * R
		var side := Vector3(-sin(g), 0, cos(g))
		var h: float = {"village": 1.8, "town": 4.0, "city": 7.0}.get(kind, 2.0)
		for s in [-1.0, 1.0]:
			_box(Vector3(1.0, h, 1.0), gp + side * 4.2 * s + Vector3(0, h * 0.5, 0), Color(0.5, 0.48, 0.44) if kind == "city" else pal["trim"], 0.0, true)
	_gate = Vector3(R + 2.0, 0, 0)
	_spots["guard"] = []
	for g2 in gaps:
		_spots["guard"].append(Vector3(cos(g2), 0, sin(g2)) * (R - 3.0) + Vector3(-sin(g2), 0, cos(g2)) * 3.0)


# ---------------------------------------------------------------- buildings

func _build_square() -> void:
	var pal := _palette()
	match kind:
		"village", "hold":
			# The well.
			var wl := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.1
			cm.height = 0.9
			wl.mesh = cm
			wl.material_override = _mat(Color(0.5, 0.48, 0.45))
			wl.position = Vector3(0, 0.45, 0)
			add_child(wl)
			_solid(Vector3(2.2, 1, 2.2), Vector3(0, 0.5, 0))
			for s in [-1.0, 1.0]:
				_box(Vector3(0.15, 2.2, 0.15), Vector3(0.9 * s, 1.1, 0), pal["trim"])
			_box(Vector3(2.4, 0.15, 1.2), Vector3(0, 2.2, 0), pal["roof"])
			if underground:
				_box(Vector3(3, 1.2, 2), Vector3(-6, 0.6, 5), Color(0.2, 0.18, 0.17), 0.0, true) # anvil block
				var forge := OmniLight3D.new()
				forge.light_color = Color(1.0, 0.45, 0.15)
				forge.light_energy = 3.0
				forge.omni_range = 10.0
				forge.position = Vector3(-6, 1.5, 6)
				add_child(forge)
				_box(Vector3(2, 0.6, 1.5), Vector3(-6, 0.9, 7.5), Color(1.0, 0.45, 0.1)) # coals
				_spots["smith"] = [Vector3(-6, 0, 3)]
		"town", "city":
			# Market stalls round the square, and the church (or the keep).
			_spots["merchant"] = []
			var r := 11.0 if kind == "town" else 15.0
			for k in (4 if kind == "town" else 7):
				var a := TAU * (k + 0.5) / (4 if kind == "town" else 7) + 0.2
				var p := Vector3(cos(a), 0, sin(a)) * (r - 3.0)
				if absf(p.z) < 4.0 or absf(p.x) < 4.0:
					continue
				_box(Vector3(3, 0.9, 1.5), p + Vector3(0, 0.45, 0), pal["trim"], -a, true)
				_box(Vector3(3.4, 0.1, 2.0), p + Vector3(0, 2.2, 0), Color.from_hsv(_rng.randf(), 0.5, 0.75), -a)
				for s in [-1.0, 1.0]:
					_box(Vector3(0.1, 2.2, 0.1), p + Vector3(-sin(a), 0, cos(a)) * 1.5 * s + Vector3(0, 1.1, 0), pal["trim"])
				_spots["merchant"].append(p * 0.8)
			_spots["baker"] = _spots["merchant"]
			_spots["innkeeper"] = _spots["merchant"]
			# The church on one corner of the square.
			var cp := Vector3(r + 6.0, 0, -r - 6.0)
			_box(Vector3(9, 6, 14), cp + Vector3(0, 3, 0), pal["wall"], 0.0, true)
			_prism(Vector3(9.6, 3.5, 14.6), cp + Vector3(0, 7.75, 0), pal["roof"], 0.0)
			_box(Vector3(3.2, 13, 3.2), cp + Vector3(0, 6.5, 8.0), pal["wall2"], 0.0, true)
			_prism(Vector3(3.6, 3, 3.6), cp + Vector3(0, 14.5, 8.0), pal["roof"], 0.0)
			_spots["priest"] = [cp + Vector3(-6, 0, 2)]
			if kind == "city":
				var kp := Vector3(-r - 9.0, 0, r + 9.0)
				_box(Vector3(14, 12, 14), kp + Vector3(0, 6, 0), Color(0.6, 0.58, 0.54), 0.0, true)
				for k2 in 4:
					var a2 := PI * 0.5 * k2 + PI * 0.25
					_box(Vector3(3, 15, 3), kp + Vector3(cos(a2), 0, sin(a2)) * 9.0 + Vector3(0, 7.5, 0), Color(0.56, 0.54, 0.5), 0.0, true)
				_spots["clerk"] = [kp + Vector3(8, 0, -6)]
				_spots["servant"] = _spots["clerk"]
			# A smithy just off the square.
			var sp := Vector3(-r - 4.0, 0, -r - 3.0)
			_box(Vector3(5, 3.2, 5), sp + Vector3(0, 1.6, 0), pal["wall2"], 0.0, true)
			_box(Vector3(1.0, 0.8, 0.6), sp + Vector3(3.6, 0.4, 0), Color(0.2, 0.2, 0.22), 0.0, true)
			_spots["smith"] = [sp + Vector3(4.2, 0, 1.5)]


func _prism(size: Vector3, pos: Vector3, col: Color, rot_y: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)


func _build_houses() -> void:
	var pal := _palette()
	var sq: float = {"village": 9.0, "town": 13.0, "city": 17.0, "hold": 12.0}.get(kind, 9.0)
	var doors: Array = []
	var rows := [8.5] if kind != "city" else [8.5, 18.0]
	if kind == "village":
		rows = [8.0]
	for s in _streets():
		var d: Vector3 = s[0]
		var side := Vector3(-d.z, 0, d.x)
		for off in rows:
			for sgn in [-1.0, 1.0]:
				var t := -R + 5.0
				while t < R - 5.0:
					var w := _rng.randf_range(5.0, 8.0)
					var dep := _rng.randf_range(5.0, 7.0)
					var c: Vector3 = d * (t + w * 0.5) + side * float(sgn) * (float(off) + dep * 0.5 - 1.5)
					t += w + _rng.randf_range(1.5, 4.5)
					if c.length() < sq + 4.0 or c.length() > R - 4.0:
						continue
					if _near_water(c, 3.5):
						continue
					if kind != "village" and (absf(c.x) < 5.5 or absf(c.z) < 5.5):
						continue # keep the other street clear
					if _rng.randf() < (0.2 if kind == "village" else 0.12):
						continue # a yard, a garden
					var ang := atan2(d.x, d.z)
					var h := _rng.randf_range(2.8, 4.2) * (1.6 if kind == "city" and _rng.randf() < 0.4 else 1.0)
					var col: Color = pal["wall"] if _rng.randf() < 0.6 else pal["wall2"]
					if underground:
						h = _rng.randf_range(4.0, 7.0)
					var house := Vector3(w, h, dep)
					_box(house, c + Vector3(0, h * 0.5, 0), col, ang, true)
					if not underground:
						_prism(Vector3(dep + 0.6, 2.0, w + 0.4), c + Vector3(0, h + 1.0, 0), pal["roof"], ang + PI * 0.5)
					# Door and a window on the street side.
					var face: Vector3 = c - side * float(sgn) * (dep * 0.5 + 0.02)
					var dc := Color(0.16, 0.1, 0.06) if not underground else Color(1.0, 0.55, 0.2)
					_box(Vector3(1.2, 2.0, 0.08), face + Vector3(0, 1.0, 0), dc, ang + PI * 0.5)
					if not underground:
						_box(Vector3(0.9, 0.8, 0.08), face + d * 2.0 + Vector3(0, 1.8, 0), Color(0.15, 0.17, 0.22), ang + PI * 0.5)
					doors.append(face - side * float(sgn) * 1.5)
	# Villages: cottages scattered round the green as well.
	if kind == "village":
		var tries := 0
		var placed := 0
		while placed < 8 and tries < 60:
			tries += 1
			var a := _rng.randf() * TAU
			var rr := _rng.randf_range(sq + 4.0, R - 5.0)
			var c2 := Vector3(cos(a), 0, sin(a)) * rr
			if _near_water(c2, 4.0) or absf(c2.z) < 6.5:
				continue
			var clash := false
			for o in _obstacles:
				if (o as Rect2).grow(3.0).has_point(Vector2(c2.x, c2.z)):
					clash = true
			if clash:
				continue
			var w2 := _rng.randf_range(4.5, 6.5)
			var d2 := _rng.randf_range(4.0, 5.5)
			var h2 := _rng.randf_range(2.6, 3.4)
			var ang2 := -a + PI * 0.5
			_box(Vector3(w2, h2, d2), c2 + Vector3(0, h2 * 0.5, 0), pal["wall"] if _rng.randf() < 0.5 else pal["wall2"], ang2, true)
			_prism(Vector3(d2 + 0.6, 1.8, w2 + 0.4), c2 + Vector3(0, h2 + 0.9, 0), pal["roof"], ang2 + PI * 0.5)
			var toward := -c2.normalized()
			_box(Vector3(1.1, 1.9, 0.08), c2 + toward * (d2 * 0.5 + 0.03) + Vector3(0, 0.95, 0), Color(0.16, 0.1, 0.06), ang2)
			doors.append(c2 + toward * (d2 * 0.5 + 1.5))
			placed += 1
	_spots["door"] = doors


func _build_outside() -> void:
	if underground:
		return
	# Trees, as many as the map has forest here.
	var count := int(20 + 260 * float(sur["forest"]))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.25
	trunk.height = 2.0
	trunk.material = _mat(Color(0.32, 0.22, 0.13))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.8
	crown.height = 5.0
	crown.radial_segments = 8
	crown.material = _mat(Color(0.13, 0.27, 0.15))
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.mesh = trunk
	var cmm := MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.mesh = crown
	var xs: Array = []
	for i in count * 3:
		if xs.size() >= count:
			break
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(R + 6.0, R + 65.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if _near_water(p, 2.0) or absf(p.z) < 5.0:
			continue
		xs.append([p, _rng.randf_range(0.8, 1.5)])
	tm.instance_count = xs.size()
	cmm.instance_count = xs.size()
	for i in xs.size():
		var p: Vector3 = xs[i][0]
		var s: float = xs[i][1]
		var b := Basis().scaled(Vector3(s, s, s))
		tm.set_instance_transform(i, Transform3D(b, p + Vector3(0, s, 0)))
		cmm.set_instance_transform(i, Transform3D(b, p + Vector3(0, 4.2 * s, 0)))
	for mm in [tm, cmm]:
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		add_child(inst)
	# Fields outside a village.
	if kind == "village":
		for k in 5:
			var a2 := _rng.randf() * TAU
			var p2 := Vector3(cos(a2), 0, sin(a2)) * (R + _rng.randf_range(8.0, 25.0))
			if not _near_water(p2, 6.0):
				_box(Vector3(14, 0.06, 10), p2 + Vector3(0, 0.03, 0), Color(0.72, 0.64, 0.3), a2)
	# Hills or mountains standing behind, if the map has them here.
	var high := float(sur["hills"]) + float(sur["mountain"]) * 2.0
	if high > 0.1:
		for k3 in int(4 + high * 14):
			var a3 := _rng.randf() * TAU
			var hill := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			var big := _rng.randf_range(30.0, 60.0) * (1.6 if float(sur["mountain"]) > 0.1 else 1.0)
			cone.top_radius = big * 0.15
			cone.bottom_radius = big
			cone.height = big * (0.6 if float(sur["mountain"]) > 0.1 else 0.35)
			hill.mesh = cone
			hill.material_override = _mat(Color(0.42, 0.44, 0.3) if float(sur["mountain"]) < 0.1 else Color(0.5, 0.5, 0.52))
			hill.position = Vector3(cos(a3), 0, sin(a3)) * _rng.randf_range(160.0, 230.0) + Vector3(0, cone.height * 0.5, 0)
			add_child(hill)
	if World.is_night():
		# Lanterns along the main street.
		for k4 in 6:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.7, 0.4)
			l.light_energy = 1.6
			l.omni_range = 9.0
			l.position = Vector3(-R * 0.75 + k4 * R * 0.3, 2.6, 3.4 * (1 if k4 % 2 == 0 else -1))
			add_child(l)


# ---------------------------------------------------------------- people

func _build_men_at_gate() -> void:
	# A few of your men wait just outside the gate (the ones you point at).
	var men: Array = Company.fit_men().slice(0, 4)
	for i in men.size():
		var r = Rig3D.new()
		r.kind = "soldier"
		r.gear = men[i]["gear"]
		r.pack = men[i]["pack"]
		var holder := Node3D.new()
		holder.position = _gate + Vector3(3.0 + (i % 2) * 1.2, 0, -2.0 + i * 1.3)
		add_child(holder)
		holder.add_child(r)
		r.facing = Vector3.LEFT
		r.anim = "idle"


func _build_folk() -> void:
	var night: bool = World.is_night()
	for p in Folk.people(sid):
		var s := Folk.state(p)
		if bool(s["joined"]) or bool(s["gone"]):
			continue
		if night and p["job"] not in ["guard", "innkeeper", "priest", "fisher"] and _rng.randf() < 0.6:
			continue # abed
		var tf = Townsfolk.new()
		tf.person = p
		var spots: Array = _spots.get(p["job"], [])
		if spots.is_empty():
			spots = _spots.get("door", [])
		var home: Vector3 = spots[int(p["i"]) % spots.size()] if not spots.is_empty() else Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
		tf.home = home
		tf.roam = 2.0 if p["job"] == "guard" else 5.0
		tf.obstacles = _obstacles
		tf.position = home + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2))
		add_child(tf)
		_folk.append(tf)


func _build_me() -> void:
	_me = CharacterBody3D.new()
	_me.collision_layer = 8
	_me.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	_me.add_child(cs)
	_me.position = _gate + Vector3(-4.0, 0.05, 0)
	_me.rotation.y = PI * 0.5 # looking west, into the town
	add_child(_me)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.64, 0)
	_cam.fov = 72.0
	_cam.near = 0.05
	_cam.far = 400.0
	_me.add_child(_cam)
	_cam.make_current()


# ---------------------------------------------------------------- moving about

func _physics_process(delta: float) -> void:
	if _me == null:
		return
	var input := _move
	var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if InputMap.has_action("move_left") else Vector2.ZERO
	if kb != Vector2.ZERO:
		input = kb
	if _conv != null and _conv.visible:
		input = Vector2.ZERO
	var dir := _me.global_transform.basis * Vector3(input.x, 0, input.y)
	dir.y = 0.0
	_me.velocity = dir * SPEED
	_me.move_and_slide()
	_me.position.y = 0.05
	_cam.rotation.x = _pitch


func _process(delta: float) -> void:
	if _me == null:
		return
	if _joy_i != -1:
		var v := (_joy_p - _joy_o) / JOY_R
		_move = v.limit_length(1.0)
	else:
		_move = Vector2.ZERO
	_toast_t -= delta
	if _toast != null:
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if mode == "menu":
		_update_cine(delta)
		return
	if _conv != null and _conv.visible:
		if _conv_with != null:
			# Turn to look at them while you talk.
			var to: Vector3 = _conv_with.global_position - _me.global_position
			var want := atan2(-to.x, -to.z)
			_me.rotation.y = lerp_angle(_me.rotation.y, want, minf(1.0, delta * 4.0))
			_pitch = lerpf(_pitch, -0.12, minf(1.0, delta * 3.0))
		return
	_find_target()
	if _pad != null:
		_pad.queue_redraw()


func _find_target() -> void:
	var best = null
	var bd := TALK_RANGE
	var fwd := -_me.global_transform.basis.z
	for tf in _folk:
		if not tf.visible or tf.leaving:
			continue
		var to: Vector3 = tf.global_position - _me.global_position
		to.y = 0.0
		var d := to.length()
		if d < bd and fwd.dot(to.normalized()) > 0.45:
			bd = d
			best = tf
	if best != _target:
		if _target != null and is_instance_valid(_target):
			_target.show_label("")
		_target = best
		if _target != null:
			_target.show_label(Folk.known_as(_target.person))
	_talk_btn.visible = _target != null
	if _target != null:
		_talk_btn.text = "TALK TO %s" % Folk.known_as(_target.person).to_upper()


# ---------------------------------------------------------------- the screen

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	# The touch pad underneath everything: left half moves, right half looks.
	_pad = Control.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.gui_input.connect(_on_pad)
	_pad.draw.connect(_draw_pad)
	_ui.add_child(_pad)
	var info_panel := _panel(Color(0.06, 0.07, 0.11, 0.8))
	info_panel.position = Vector2(14, 14)
	info_panel.custom_minimum_size = Vector2(430, 0)
	_ui.add_child(info_panel)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.custom_minimum_size = Vector2(410, 0)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_font_size_override("normal_font_size", 17)
	_info.add_theme_font_size_override("bold_font_size", 17)
	info_panel.add_child(_info)
	var leave := _button("LEAVE", _on_leave)
	leave.anchor_left = 1.0
	leave.anchor_right = 1.0
	leave.position = Vector2(-170, 14)
	leave.custom_minimum_size = Vector2(150, UI.MIN_TOUCH)
	_ui.add_child(leave)
	_leave_btn = leave
	_menu_btn = _button("TOWN MENU", func(): _set_mode("menu"))
	_menu_btn.anchor_left = 1.0
	_menu_btn.anchor_right = 1.0
	_menu_btn.position = Vector2(-370, 14)
	_menu_btn.custom_minimum_size = Vector2(190, UI.MIN_TOUCH)
	_ui.add_child(_menu_btn)
	_talk_btn = _button("TALK", _on_talk)
	_talk_btn.anchor_left = 0.5
	_talk_btn.anchor_right = 0.5
	_talk_btn.anchor_top = 1.0
	_talk_btn.anchor_bottom = 1.0
	_talk_btn.custom_minimum_size = Vector2(420, 70)
	_talk_btn.position = Vector2(-210, -100)
	_talk_btn.add_theme_font_size_override("font_size", 22)
	_talk_btn.visible = false
	_ui.add_child(_talk_btn)
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.position = Vector2(-380, 150)
	_toast.custom_minimum_size = Vector2(760, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_toast)
	_build_conv()
	_build_menu()
	_cine = Camera3D.new()
	_cine.fov = 55.0
	_cine.far = 500.0
	add_child(_cine)


func _panel(col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 12)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _show_toast(t: String, secs := 3.0) -> void:
	if _toast == null:
		return
	_toast.text = t
	_toast_t = secs


func _refresh_info() -> void:
	var fname: String = Lore.FACTIONS[fac]["name"]
	var t := "[b][color=#%s]%s[/color][/b]  ·  a %s of the %s\n" % [GOLD.to_html(false), st["name"], kind if kind != "hold" else "dwarf hold", fname]
	if lang != "":
		t += "%s: [b]%s[/b], %d words" % [Tongue.LANG_NAMES[lang], Tongue.level(lang), Tongue.words_known(lang)]
	var rep := int(Folk.town(sid)["rep"])
	t += "\nStanding here: %s" % ("[color=#8fe08f]liked[/color]" if rep >= 10 else ("[color=#f08060]resented[/color]" if rep <= -5 else "a stranger"))
	_info.text = t


func _on_pad(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			if t.position.x < _pad.size.x * 0.45 and _joy_i == -1:
				_joy_i = t.index
				_joy_o = t.position
				_joy_p = t.position
			elif _look_i == -1:
				_look_i = t.index
				_look_last = t.position
		else:
			if t.index == _joy_i:
				_joy_i = -1
			if t.index == _look_i:
				_look_i = -1
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _joy_i:
			_joy_p = d.position
		elif d.index == _look_i:
			var rel := d.position - _look_last
			_look_last = d.position
			if _conv == null or not _conv.visible:
				_me.rotation.y -= rel.x * LOOK
				_pitch = clampf(_pitch - rel.y * LOOK, -1.1, 1.1)


func _draw_pad() -> void:
	if _joy_i != -1:
		_pad.draw_circle(_joy_o, JOY_R, Color(1, 1, 1, 0.12))
		_pad.draw_circle(_joy_o + (_joy_p - _joy_o).limit_length(JOY_R), 28, Color(1, 1, 1, 0.35))
	else:
		_pad.draw_arc(Vector2(150, _pad.size.y - 150), JOY_R, 0, TAU, 32, Color(1, 1, 1, 0.15), 2.0)


func _on_leave() -> void:
	Company.visiting = -1
	Company.save()
	Loading.change(MAP)


# ---------------------------------------------------------------- the town menu

func _set_mode(m: String) -> void:
	mode = m
	var menu := m == "menu"
	_menu.visible = menu and not _conv.visible
	_pad.visible = not menu
	_menu_btn.visible = not menu
	_talk_btn.visible = false
	if _target != null and is_instance_valid(_target):
		_target.show_label("")
	_target = null
	if menu:
		_cine.make_current()
		_fill_menu()
	else:
		_cam.make_current()


func _build_menu() -> void:
	_menu = _panel(Color(0.07, 0.08, 0.13, 0.9))
	_menu.position = Vector2(14, 120)
	_menu.custom_minimum_size = Vector2(430, 0)
	_menu.visible = false
	_ui.add_child(_menu)
	var sc := UI.scroll()
	sc.custom_minimum_size = Vector2(410, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(sc)
	_menu_box = VBoxContainer.new()
	_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_box.add_theme_constant_override("separation", 8)
	sc.add_child(_menu_box)


func _fill_menu(people := false) -> void:
	for c in _menu_box.get_children():
		c.queue_free()
	if people:
		_menu_box.add_child(_label("THE PEOPLE OF %s" % String(st["name"]).to_upper(), 20, GOLD))
		var met: Array = []
		var new: Array = []
		for tf in _folk:
			if not tf.visible or tf.leaving:
				continue
			(met if int(Folk.state(tf.person)["met"]) > 0 else new).append(tf)
		for tf in met:
			var s := Folk.state(tf.person)
			var b := _button("%s  ·  %s" % [Folk.known_as(tf.person).capitalize(), _mood_plain(int(s["trust"]))], _talk_from_menu.bind(tf))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if Folk.task_ready(tf.person):
				b.add_theme_color_override("font_color", GOLD)
			_menu_box.add_child(b)
		if not new.is_empty():
			_menu_box.add_child(_button("Someone you haven't met (%d)" % new.size(), _talk_from_menu.bind(new.pick_random())))
		if met.is_empty() and new.is_empty():
			_menu_box.add_child(_label("Nobody is about.", 17, DIM))
		_menu_box.add_child(_button("BACK", func(): _fill_menu()))
		return
	_menu_box.add_child(_label(String(st["name"]).to_upper(), 24, GOLD))
	_menu_box.add_child(_label("%d crowns  ·  food %d  ·  rum %d" % [Company.money, int(Company.stores["rations"]), int(Company.stores["rum"])], 16, DIM))
	_menu_box.add_child(_button("TALK TO SOMEONE", func(): _fill_menu(true)))
	var prices := {"village": [10, 5], "town": [20, 9], "city": [20, 8], "hold": [20, 10]}
	var pr: Array = [prices[kind][0], Company.price(prices[kind][1])]
	_menu_box.add_child(_button("BUY FOOD: %d rations for %d crowns" % [pr[0], pr[1]], func():
		if Company.room_for("rations") < int(pr[0]):
			_show_toast("The wagon is full.")
		elif Company.money >= int(pr[1]):
			Company.money -= int(pr[1])
			Company.stores["rations"] = int(Company.stores["rations"]) + int(pr[0])
			Company.save()
			_show_toast("Bought %d rations." % int(pr[0]))
		else:
			_show_toast("Not enough crowns.")
		_fill_menu()))
	if kind != "village":
		var rum_cr := Company.price(6)
		_menu_box.add_child(_button("BUY RUM: 10 tots for %d crowns" % rum_cr, func():
			if Company.room_for("rum") < 10:
				_show_toast("The wagon is full.")
			elif Company.money >= rum_cr:
				Company.money -= rum_cr
				Company.stores["rum"] = int(Company.stores["rum"]) + 10
				Company.save()
				_show_toast("Bought 10 tots of rum.")
			_fill_menu()))
	var gv := Company.goods_value(kind)
	if gv > 0:
		_menu_box.add_child(_button("SELL LOOT for %d crowns" % gv, func():
			var got := Company.sell_goods(kind)
			_show_toast("Sold the loot for %d crowns." % got)
			_fill_menu()))
	_menu_box.add_child(_button("WALK THE STREETS", func(): _set_mode("walk")))
	_menu_box.add_child(_button("REST HERE A DAY", func():
		World.pending_rest = 24.0
		_on_leave()))
	_menu_box.add_child(_button("LEAVE", _on_leave))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _mood_plain(trust: int) -> String:
	if trust <= -40:
		return "hostile"
	if trust <= -10:
		return "cold"
	if trust < 10:
		return "wary"
	if trust < 30:
		return "warming"
	if trust < 60:
		return "friendly"
	return "a friend"


func _talk_from_menu(tf) -> void:
	_menu.visible = false
	_target = tf
	_on_talk()


## Where "you" stand when talking from the menu: a step in front of them.
## Picked once per conversation, in the open (not inside a house).
var _spot_for = null
var _spot := Vector3.ZERO


func _you_spot(tf) -> Vector3:
	if _spot_for == tf:
		return _spot
	var base: Vector3 = tf.global_position
	var toward_c := -base
	toward_c.y = 0.0
	var start := atan2(toward_c.x, toward_c.z) if toward_c.length() > 0.1 else 0.0
	var best := base + Vector3(sin(start), 0, cos(start)) * 2.4
	for k in 12:
		# Try the side toward the square first, then swing round.
		var a := start + (k / 2 + 1) * 0.52 * (1.0 if k % 2 == 0 else -1.0) if k > 0 else start
		var d := Vector3(sin(a), 0, cos(a))
		var clear := true
		for step in [0.8, 1.6, 2.4, 3.2]:
			var q: Vector3 = base + d * float(step)
			for o in _obstacles:
				if (o as Rect2).grow(0.4).has_point(Vector2(q.x, q.z)):
					clear = false
					break
			if not clear:
				break
		if clear:
			best = base + d * 2.4
			break
	_spot_for = tf
	_spot = best
	return best


## The camera over the town: a slow circle over the roofs, and close in on
## whoever you're talking to.
func _update_cine(delta: float) -> void:
	_cine_t += delta
	if _conv.visible and _conv_with != null and is_instance_valid(_conv_with):
		var face: Vector3 = _conv_with.global_position + Vector3(0, 1.45 if not _conv_with.rig.dwarf else 1.15, 0)
		var me := _you_spot(_conv_with)
		var side := (face - me).cross(Vector3.UP).normalized()
		var want := me + Vector3(0, 1.65, 0) + side * 0.9 - (face - me).normalized() * 0.4
		_cine.global_position = _cine.global_position.lerp(want, minf(1.0, delta * 2.5))
		_cine.look_at(face.lerp(me + Vector3(0, 1.5, 0), 0.25))
		_conv_with.face(me)
		return
	var a := _cine_t * 0.05
	var r := R * (0.62 if not underground else 0.5)
	var h := (R * 0.32 + 3.0 * sin(_cine_t * 0.13)) if not underground else 7.0
	var want2 := Vector3(cos(a) * r, h, sin(a) * r)
	_cine.global_position = _cine.global_position.lerp(want2, minf(1.0, delta * 1.5)) if _cine_t > 0.2 else want2
	_cine.look_at(Vector3(sin(_cine_t * 0.07) * 4.0, 1.5, cos(_cine_t * 0.05) * 4.0))


# ---------------------------------------------------------------- talking

func _build_conv() -> void:
	_conv = _panel(Color(0.07, 0.08, 0.13, 0.96))
	_conv.anchor_left = 0.42
	_conv.anchor_right = 1.0
	_conv.anchor_bottom = 1.0
	_conv.offset_left = 0
	_conv.offset_top = 10
	_conv.offset_right = -10
	_conv.offset_bottom = -10
	_conv.visible = false
	_ui.add_child(_conv)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_conv.add_child(v)
	_conv_head = RichTextLabel.new()
	_conv_head.bbcode_enabled = true
	_conv_head.fit_content = true
	_conv_head.scroll_active = false
	_conv_head.add_theme_font_size_override("normal_font_size", 20)
	_conv_head.add_theme_font_size_override("bold_font_size", 20)
	v.add_child(_conv_head)
	_conv_know = Label.new()
	_conv_know.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conv_know.add_theme_font_size_override("font_size", 14)
	_conv_know.add_theme_color_override("font_color", DIM)
	v.add_child(_conv_know)
	_conv_scroll = UI.scroll()
	_conv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_conv_scroll)
	_conv_log = RichTextLabel.new()
	_conv_log.bbcode_enabled = true
	_conv_log.fit_content = true
	_conv_log.scroll_active = false
	_conv_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conv_log.add_theme_font_size_override("normal_font_size", 16)
	_conv_log.add_theme_font_size_override("bold_font_size", 16)
	_conv_log.add_theme_font_size_override("italics_font_size", 16)
	_conv_scroll.add_child(_conv_log)
	_conv_actions = GridContainer.new()
	_conv_actions.columns = 3
	_conv_actions.add_theme_constant_override("h_separation", 6)
	_conv_actions.add_theme_constant_override("v_separation", 6)
	v.add_child(_conv_actions)


func _on_talk() -> void:
	if _target == null:
		return
	_conv_with = _target
	_conv_with.talking = true
	_conv_with.mood = ""
	_conv_with.face(_me.global_position if mode == "walk" else _you_spot(_conv_with))
	_target.show_label("")
	_talk_btn.visible = false
	var p: Dictionary = _conv_with.person
	var s := Folk.state(p)
	Folk.met(p)
	var tr: Array = p["traits"]
	_patience = 5 + (3 if "talkative" in tr else 0) - (2 if "shy" in tr else 0) + (2 if int(s["trust"]) > 30 else 0)
	_conv_log.text = ""
	if int(s["met"]) <= 1:
		_log("[color=#%s]%s eyes your coat and your musket. %s[/color]" % [DIM.to_html(false), _nm(p).capitalize(),
			"Nobody here has seen anyone like you." if int(Folk.town(sid).get("visits", 1)) <= 1 else "Word of the strangers has gone round."])
	else:
		_log("[color=#%s]%s knows you.[/color]" % [DIM.to_html(false), _nm(p).capitalize()])
	_conv.visible = true
	_fill_conv()


func _nm(p: Dictionary) -> String:
	return String(p["name"]) if bool(Folk.state(p)["named"]) else "the %s" % p["job"]


func _mood_word(trust: int) -> String:
	if trust <= -40:
		return "[color=#f08060]hostile[/color]"
	if trust <= -10:
		return "[color=#f0a070]cold[/color]"
	if trust < 10:
		return "wary"
	if trust < 30:
		return "[color=#d8e090]warming to you[/color]"
	if trust < 60:
		return "[color=#8fe08f]friendly[/color]"
	return "[color=#8fe08f]a friend[/color]"


func _fill_conv() -> void:
	var p: Dictionary = _conv_with.person
	var s := Folk.state(p)
	_conv_head.text = "[b]%s[/b]  ·  %s  ·  %s" % [Folk.known_as(p).capitalize(), "%d, %s" % [int(p["age"]), "man" if p["sex"] == "m" else "woman"], _mood_word(int(s["trust"]))]
	_conv_know.text = Folk.what_you_know(p) + ("   ·   Patience: %s" % "●".repeat(maxi(0, _patience)))
	for c in _conv_actions.get_children():
		c.queue_free()
	if Folk.task_ready(p):
		var fin := _button("DO WHAT WAS ASKED", _on_finish_task)
		fin.add_theme_color_override("font_color", GOLD)
		_conv_actions.add_child(fin)
	for a in Folk.ACTION_ORDER:
		var spec: Dictionary = Folk.ACTIONS[a]
		var words := Folk.can_use_words(p, a)
		var b := _button("%s\n%s" % [spec["label"], "in words" if words else "with signs"], _on_action.bind(a))
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if words:
			b.add_theme_color_override("font_color", GOLD)
		if a == "join" and not bool(p["recruitable"]) and int(s["met"]) > 2:
			b.disabled = true
		_conv_actions.add_child(b)
	var end := _button("Goodbye", _end_conv)
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end.custom_minimum_size = Vector2(0, 62)
	_conv_actions.add_child(end)


func _log(t: String) -> void:
	_conv_log.append_text(t + "\n\n")
	await get_tree().process_frame
	_conv_scroll.scroll_vertical = int(_conv_scroll.get_v_scroll_bar().max_value)


func _on_action(a: String) -> void:
	if _conv_with == null:
		return
	var p: Dictionary = _conv_with.person
	var words := Folk.can_use_words(p, a)
	var r := Folk.exchange(p, a, words, {"sur": sur})
	_patience -= 1
	var t := "[color=#%s]%s[/color]\n%s" % [DIM.to_html(false), r["you"], r["see"]]
	var said := Tongue.render(lang, r["say"])
	if said != "":
		t += "\n" + said
	if String(r["note"]) != "":
		t += "\n[color=#%s]%s[/color]" % [GOLD.to_html(false) if not String(r["note"]).begins_with("They didn't") else RED.to_html(false), r["note"]]
	var learned: Array = r["learned"]
	for w in learned:
		t += "\n[color=#8fe08f]You learn a word: [b]%s[/b] means “%s”.[/color]" % [Tongue.word(lang, w), w]
	_log(t)
	_conv_with.mood = {"warm": "talk", "amused": "talk", "afraid": "fear", "angry": "point", "cold": "", "puzzled": "talk"}.get(r["tone"], "talk")
	if r.has("reveal"):
		var o: Dictionary = World.gen.settlements[int(r["reveal"])]
		World._reveal(Vector2(o["x"], o["y"]), 4.0)
	if bool(r["joined"]):
		var m := Folk.recruit(p)
		_log("[color=#8fe08f][b]%s joins your company[/b] (with a spear; the Natives tag).[/color]" % m["name"])
		_conv_with.walk_off(_gate + Vector3(4, 0, 2))
		_finish_conv()
		return
	if bool(r["end"]):
		_conv_with.walk_off(_conv_with.home + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12)))
		Folk.state(p)["gone"] = int(Folk.state(p)["trust"]) <= -60
		_finish_conv()
		return
	if _patience <= 0:
		_log("[color=#%s]%s has work to do, and goes back to it.[/color]" % [DIM.to_html(false), _nm(p).capitalize()])
		_finish_conv()
		return
	Company.save()
	_refresh_info()
	_fill_conv()


func _on_finish_task() -> void:
	var p: Dictionary = _conv_with.person
	var t := Folk.finish_task(p)
	if t != "":
		_log("[color=#8fe08f]%s[/color]" % t)
	Company.save()
	_fill_conv()


func _finish_conv() -> void:
	Company.save()
	_refresh_info()
	for c in _conv_actions.get_children():
		c.queue_free()
	var end := _button("Walk on", _end_conv)
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conv_actions.add_child(end)


func _end_conv() -> void:
	if _conv_with != null and is_instance_valid(_conv_with) and not _conv_with.leaving:
		_conv_with.talking = false
	_conv_with = null
	_conv.visible = false
	_target = null
	Company.save()
	_refresh_info()
	if mode == "menu":
		_menu.visible = true
		_fill_menu()


# ---------------------------------------------------------------- pictures

func _shot(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://town_%s.png" % name)


func _shots() -> void:
	await _shot("gate")
	var over := Camera3D.new()
	add_child(over)
	over.position = Vector3(R * 0.9, R * 0.75, R * 0.9)
	over.look_at(Vector3.ZERO)
	over.make_current()
	await _shot("above")
	_cam.make_current()
	# Walk up to someone and talk.
	var tf = _folk[0]
	_me.position = tf.position + Vector3(0, 0, 2.2)
	_me.rotation.y = 0.0
	_pitch = -0.15
	await get_tree().create_timer(0.3).timeout
	_target = tf
	_on_talk()
	for a in ["greet", "name", "gift_food", "ask_lizards"]:
		_on_action(a)
	await _shot("talk")
	_end_conv()
	_set_mode("menu")
	await get_tree().create_timer(1.5).timeout
	await _shot("menu")
	_fill_menu(true)
	await _shot("people")
	_talk_from_menu(_folk[1])
	for a in ["greet", "listen", "musket"]:
		_on_action(a)
	await get_tree().create_timer(1.2).timeout
	await _shot("menutalk")
	get_tree().quit()


# ---------------------------------------------------------------- headless check

## `-- --towntest`: walk up to people, talk to a few, check the books.
func _self_test() -> void:
	if "--townshot" in OS.get_cmdline_user_args():
		await _shots()
		return
	print("TOWNTEST %s (%s, %s) river %s coast %s forest %.2f folk %d houses %d spots %s" % [st["name"], kind, fac,
		sur["river"], sur["coast"], float(sur["forest"]), _folk.size(), _spots.get("door", []).size(), _spots.keys()])
	var talked := 0
	for tf in _folk.slice(0, 4):
		_target = tf
		_on_talk()
		for a in ["greet", "name", "listen", "gift_food", "ask_lizards", "ask_work", "musket", "join"]:
			if not _conv.visible or _conv_with == null or _conv_with.leaving:
				break
			_on_action(a)
		print("  talked to %s: trust %d, joined %s" % [Folk.known_as(tf.person), int(Folk.state(tf.person)["trust"]), Folk.state(tf.person)["joined"]])
		_end_conv()
		talked += 1
	print("TOWNTEST %s: %s, %d words; roster %d" % [lang, Tongue.level(lang), Tongue.words_known(lang), Company.roster.size()])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
