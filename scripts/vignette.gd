extends SubViewportContainer
## A small live 3D scene for a pop-up: what has just happened, or is about
## to. Each scene is a few seconds of staging in its own little world -
## ground and sky matching where you are on the map and the time of day,
## your men, the lizards, townsfolk, carts and fires - with a camera drifting
## slowly across it, looping until the pop-up closes.
##
##   var v = Vignette.make("ford", {})
##   popup_row.add_child(v)
##
## Scenes: road, ford, flood, fishing, wreck, game, berries, lost, ruins,
## fever, bog, spoor, ambush, farmer, pedlar, refugees, deserters, vantage,
## camp (abandoned), prospectors, warband, camp_night, camp_attack, dusk,
## scouts_back, scouts_lost, caravan, patrol, villagers, traders, burned,
## nest. Anything else falls back to the company on the road.

const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const Props := preload("res://scripts/props.gd")
const Lore := preload("res://scripts/lore.gd")
const Gen := preload("res://scripts/world_gen.gd")
const Look := preload("res://scripts/look.gd")

const SIZE := Vector2i(500, 290)

var kind := "road"
var ctx := {}
var _view: SubViewport
var _root: Node3D
var _cam: Camera3D
var _cam_from := Vector3(6, 3, 8)
var _cam_to := Vector3(-4, 3, 8)
var _look := Vector3(0, 1, 0)
var _t := 0.0
var _period := 9.0
var _actors: Array = [] # {"node", "rig", "path": [Vector3], "speed", "anim", "i", "wait", "loop", "face"}
var _flames: Array = []
var _fire_light: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _env: Environment
var _sun: DirectionalLight3D
var _ground_col := Color(0.36, 0.44, 0.22)
var _cols: Dictionary = {}
var _flats: Array = [] # [centre, size, yaw] of roads, water and floors: no grass there
var _tree_spots: Array = []
var _dead_spots: Array = []
## Set by a scene with a floor of its own (a hall, a cave): no grass.
var underfoot_bare := false


static func make(k: String, c := {}) -> Control:
	var v = load("res://scripts/vignette.gd").new()
	v.kind = k
	v.ctx = c
	return v


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = SubViewport.new()
	_view.size = SIZE
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	add_child(_view)
	_root = Node3D.new()
	_view.add_child(_root)
	var b := BatcherScript.new()
	b.add_to_group("batcher")
	_root.add_child(b)
	_rng.seed = hash(kind) + int(World.hours)
	_build_env()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 300.0
	_root.add_child(_cam)
	_cam.make_current()
	_stage()
	Look.trees(_root, _tree_spots, "mixed" if _terrain() != Gen.T.MOUNTAIN else "pine", _rng)
	Look.trees(_root, _dead_spots, "dead", _rng)
	_build_grass()
	_update_cam(0.0)


func _exit_tree() -> void:
	remove_from_group("vignette")


# ---------------------------------------------------------------- the world

func _terrain() -> int:
	if World.gen == null:
		return 2
	var c := World.cell()
	return World.gen.t(c.x, c.y)


func _time_of_day() -> String:
	if ctx.has("time"):
		return String(ctx["time"])
	var h: float = World.hours_of_day() if World.gen != null else 12.0
	if h < 5.0 or h >= 21.0:
		return "night"
	if h < 7.5 or h >= 18.0:
		return "dusk"
	return "day"


func _build_env() -> void:
	var t := _terrain()
	_cols = Look.ground_colours(t)
	_ground_col = (_cols["grass_dark"] as Color).lerp(_cols["grass_light"], 0.5)
	var tod := _time_of_day()
	var haze := Color(0.76, 0.78, 0.76)
	if t == Gen.T.SWAMP:
		haze = Color(0.66, 0.7, 0.62)
	_env = Look.environment(_root, tod, haze, 0.02 if tod == "night" else 0.01)
	_sun = _env.get_meta("sun")
	# Shadows are too dear for a little window in a pop-up.
	_sun.shadow_enabled = false
	var g := Look.ground(_root, 200.0, _cols)
	g.position.y = 0.0


## Grass over the scene once it's staged, kept off roads, water and floors.
func _build_grass() -> void:
	if underfoot_bare:
		return
	var reject := func(p: Vector3) -> bool:
		for f in _flats:
			var c: Vector3 = f[0]
			var sz: Vector3 = f[1]
			var q := (p - c).rotated(Vector3.UP, -float(f[2]))
			if absf(q.x) < sz.x * 0.5 + 0.3 and absf(q.z) < sz.z * 0.5 + 0.3:
				return true
		return false
	var grng := RandomNumberGenerator.new()
	grng.seed = _rng.randi()
	Look.grass(_root, Vector3.ZERO, 34.0, float(_cols.get("grass", 1.0)) * (0.12 if kind == "menu" else 0.3), _cols, [], grng, reject)


func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(size: Vector3, pos: Vector3, c: Color, rot_y := 0.0, rot_x := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = Vector3(rot_x, rot_y, 0)
	_root.add_child(mi)
	if size.y <= 0.1 and pos.y < 0.2:
		_flats.append([pos, size, rot_y])
	return mi


func _cyl(r1: float, r2: float, h: float, pos: Vector3, c: Color, segs := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r2
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position = pos
	_root.add_child(mi)
	return mi


## Trees are gathered and drawn together (Look.trees) once the scene is staged.
func _tree(pos: Vector3, s := 1.0, dead := false) -> void:
	(_dead_spots if dead else _tree_spots).append([pos, s * 0.8])


func _trees(n: int, rmin: float, rmax: float, centre := Vector3.ZERO, dead := false) -> void:
	for i in n:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(rmin, rmax)
		_tree(centre + Vector3(cos(a) * d, 0, sin(a) * d), _rng.randf_range(0.8, 1.5), dead)


func _water(pos: Vector3, size: Vector2, rot := 0.0, muddy := false) -> void:
	_box(Vector3(size.x, 0.05, size.y), pos + Vector3(0, 0.03, 0), Color(0.42, 0.33, 0.2) if muddy else Color(0.24, 0.38, 0.5), rot)


func _fire(at: Vector3) -> void:
	for i in 7:
		var a := TAU * i / 7.0
		_box(Vector3(0.2, 0.12, 0.16), at + Vector3(cos(a) * 0.5, 0.06, sin(a) * 0.5), Color(0.4, 0.4, 0.38), a)
	for k in 3:
		var fl := _cyl(0.0, 0.2 - 0.05 * k, 0.7 - 0.15 * k, at + Vector3(0, 0.4 - 0.05 * k, 0), [Color(1.0, 0.45, 0.1), Color(1.0, 0.7, 0.2), Color(1.0, 0.92, 0.55)][k], 6)
		fl.material_override = _mat([Color(1.0, 0.45, 0.1), Color(1.0, 0.7, 0.2), Color(1.0, 0.92, 0.55)][k], true)
		_flames.append(fl)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.62, 0.3)
	_fire_light.light_energy = 2.6
	_fire_light.omni_range = 12.0
	_fire_light.position = at + Vector3(0, 0.9, 0)
	_root.add_child(_fire_light)


func _cart(at: Vector3, rot := 0.0, load_col := Color(0.6, 0.5, 0.3)) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation.y = rot
	_root.add_child(n)
	var bed := _box(Vector3(1.4, 0.3, 2.2), Vector3(0, 0.7, 0), Color(0.4, 0.28, 0.16))
	bed.reparent(n, false)
	var ld := _box(Vector3(1.2, 0.5, 1.6), Vector3(0, 1.1, 0.1), load_col)
	ld.reparent(n, false)
	for s in [-1.0, 1.0]:
		var w := _cyl(0.4, 0.4, 0.1, Vector3(0.75 * s, 0.4, 0), Color(0.3, 0.2, 0.1), 10)
		w.rotation.z = PI * 0.5
		w.reparent(n, false)
	var shaft := _box(Vector3(0.08, 0.08, 1.8), Vector3(0, 0.55, -1.9), Color(0.4, 0.28, 0.16))
	shaft.reparent(n, false)
	return n


## A four-legged animal from boxes: a mule, a deer (with too many horns), a pony.
func _beast(at: Vector3, rot: float, col: Color, horns := 0, s := 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.rotation.y = rot
	n.scale = Vector3.ONE * s
	_root.add_child(n)
	var parts := [[Vector3(0.45, 0.45, 1.2), Vector3(0, 1.0, 0)], [Vector3(0.25, 0.3, 0.45), Vector3(0, 1.35, -0.75)],
		[Vector3(0.12, 0.8, 0.12), Vector3(-0.15, 0.4, -0.45)], [Vector3(0.12, 0.8, 0.12), Vector3(0.15, 0.4, -0.45)],
		[Vector3(0.12, 0.8, 0.12), Vector3(-0.15, 0.4, 0.45)], [Vector3(0.12, 0.8, 0.12), Vector3(0.15, 0.4, 0.45)]]
	for p in parts:
		var b := _box(p[0], p[1], col)
		b.reparent(n, false)
	for h in horns:
		var hb := _box(Vector3(0.04, 0.4, 0.04), Vector3(-0.15 + 0.3 * float(h) / maxf(1.0, horns - 1), 1.65, -0.8), Color(0.85, 0.8, 0.68))
		hb.rotation.z = -0.5 + float(h) / maxf(1.0, horns - 1)
		hb.reparent(n, false)
	return n


# ---------------------------------------------------------------- actors

func _rig(k: String, at: Vector3, face: Vector3, setup := {}) -> Dictionary:
	var holder := Node3D.new()
	holder.position = at
	_root.add_child(holder)
	var r = Rig3D.new()
	r.kind = k
	if setup.has("gear"):
		r.gear = setup["gear"]
	if setup.has("pack"):
		r.pack = setup["pack"]
	if k == "civilian":
		r.cloth = setup.get("cloth", Color.from_hsv(_rng.randf(), 0.4, 0.6))
		r.trousers = Color(0.3, 0.26, 0.2)
		r.female = bool(setup.get("female", false))
		r.dwarf = bool(setup.get("dwarf", false))
		r.gear = {"head": setup.get("hat", ""), "torso": "tunic"}
	holder.add_child(r)
	if bool(setup.get("dwarf", false)):
		r.scale = Vector3(1.12, 0.8, 1.12)
	r.facing = face.normalized()
	r.anim = String(setup.get("anim", "idle"))
	var a := {"node": holder, "rig": r, "path": setup.get("path", []), "speed": float(setup.get("speed", 1.4)),
		"anim": String(setup.get("anim", "idle")), "i": 0, "wait": float(setup.get("delay", 0.0)),
		"loop": bool(setup.get("loop", true)), "face": face.normalized(), "start": at}
	_actors.append(a)
	return a


func _soldier(at: Vector3, face: Vector3, setup := {}) -> Dictionary:
	var men: Array = Company.roster if Company.active else []
	var rec = men[_rng.randi() % men.size()] if not men.is_empty() else null
	if rec != null and not setup.has("gear"):
		setup["gear"] = rec["gear"]
		setup["pack"] = rec["pack"]
	return _rig("soldier", at, face, setup)


## A column of your men walking from `a` to `b` (both out of shot) and round
## again: spread along the whole way from the start, so the shot is never empty.
func _column(n: int, a: Vector3, b: Vector3, speed := 1.4, _spacing := 1.6) -> void:
	var d := (b - a).normalized()
	var length := a.distance_to(b)
	for i in n:
		var side := Vector3(-d.z, 0, d.x) * (0.5 if i % 2 == 0 else -0.5)
		var at := a + d * (length * (i + 0.5) / n) + side
		_soldier(at, d, {"path": [a + side, b + side], "speed": speed, "anim": "walk"})


func _lizards(n: int, from: Vector3, to: Vector3, spread := 6.0, speed := 2.2) -> void:
	var d := (to - from).normalized()
	var side := Vector3(-d.z, 0, d.x)
	for i in n:
		var o := side * _rng.randf_range(-spread, spread) - d * _rng.randf_range(0.0, spread)
		_rig("lizard", from + o, d, {"path": [from + o, to + o], "speed": speed * _rng.randf_range(0.85, 1.15), "anim": "walk"})


func _process(delta: float) -> void:
	_t += delta
	for a in _actors:
		var node: Node3D = a["node"]
		var r = a["rig"]
		r.anim_time += delta
		var path: Array = a["path"]
		if a["wait"] > 0.0 or path.size() < 2:
			a["wait"] = float(a["wait"]) - delta
			r.move_speed = 0.0
			r.anim = String(a.get("idle_anim", a["anim"] if path.size() < 2 else "idle"))
			continue
		var target: Vector3 = path[(int(a["i"]) + 1) % path.size()]
		var to := target - node.position
		to.y = 0.0
		var step := float(a["speed"]) * delta
		if to.length() <= step:
			node.position = target
			a["i"] = int(a["i"]) + 1
			if int(a["i"]) >= path.size() - 1:
				if bool(a["loop"]):
					a["i"] = 0
					node.position = path[0]
				else:
					a["path"] = []
					a["anim"] = String(a.get("end_anim", "idle"))
		else:
			node.position += to.normalized() * step
			r.facing = to.normalized()
		r.move_speed = float(a["speed"])
		r.anim = String(a["anim"])
	if _fire_light != null:
		_fire_light.light_energy = 2.6 + 0.5 * sin(_t * 13.0) + 0.3 * sin(_t * 7.3)
		for k in _flames.size():
			var g := 1.0 + 0.18 * sin(_t * (11.0 + 4.0 * k))
			(_flames[k] as Node3D).scale = Vector3(1.0 / sqrt(g), g, 1.0 / sqrt(g))
	_update_cam(delta)


func _update_cam(_delta: float) -> void:
	# Drift across and back, eased at each end.
	var u := 0.5 - 0.5 * cos(TAU * _t / _period)
	_cam.position = _cam_from.lerp(_cam_to, u)
	_cam.look_at(_look)


# ---------------------------------------------------------------- the scenes

func _stage() -> void:
	match kind:
		"ford", "flood":
			var flood := kind == "flood"
			_water(Vector3(0, 0, 0), Vector2(60, 9), 0.0, flood)
			_trees(14, 14, 40)
			if flood:
				# Brown water too fast to cross; the men wait on the bank.
				for i in 6:
					_soldier(Vector3(-4 + i * 1.6, 0, 6.5 + (i % 2)), Vector3.BACK * -1, {"anim": "idle"})
				_cam_from = Vector3(-8, 3, 14)
				_cam_to = Vector3(6, 3.5, 13)
				_look = Vector3(0, 0.5, 0)
			else:
				_column(8, Vector3(-2, 0, 16), Vector3(2, 0, -18), 1.2)
				_cam_from = Vector3(9, 3, 4)
				_cam_to = Vector3(8, 4, -4)
				_look = Vector3(0, 0.8, 0)
		"fishing":
			_water(Vector3(0, 0, -3), Vector2(60, 8))
			_trees(10, 14, 40)
			for i in 4:
				_soldier(Vector3(-4 + i * 2.5, 0, 1.5), Vector3.FORWARD, {"anim": "kneel" if i % 2 == 0 else "idle"})
			_cam_from = Vector3(-6, 2.5, 8)
			_cam_to = Vector3(5, 2.8, 8)
			_look = Vector3(0, 0.6, -1)
		"wreck":
			var sea := Props.sea(160.0, 0.35, 1.0)
			sea.position = Vector3(0, -0.2, -70)
			_root.add_child(sea)
			for i in 7:
				_box(Vector3(0.9, 0.7, 0.9), Vector3(_rng.randf_range(-6, 6), 0.3, _rng.randf_range(-6, -1)), Color(0.42, 0.3, 0.18), _rng.randf() * TAU)
			for i in 3:
				_cyl(0.45, 0.45, 1.0, Vector3(_rng.randf_range(-5, 5), 0.5, _rng.randf_range(-5, -2)), Color(0.38, 0.27, 0.16), 10)
			_column(7, Vector3(-18, 0, 3), Vector3(18, 0, 1), 1.1)
			_cam_from = Vector3(-4, 3, 10)
			_cam_to = Vector3(5, 3.5, 9)
			_look = Vector3(0, 0.5, -3)
		"game":
			_trees(40, 4, 40)
			_beast(Vector3(2.5, 0, -5), -0.9, Color(0.45, 0.35, 0.25), 5)
			for i in 3:
				_soldier(Vector3(-4.5 + i * 1.4, 0, 4), Vector3(0.4, 0, -1), {"anim": "aim" if i == 1 else "idle"})
			_cam_from = Vector3(-5, 2, 9)
			_cam_to = Vector3(4, 2.4, 8)
			_look = Vector3(0, 1, -3)
		"berries":
			_trees(20, 8, 40)
			for i in 8:
				var bp := Vector3(_rng.randf_range(-6, 6), 0.5, _rng.randf_range(-5, 2))
				_cyl(0.7, 0.8, 1.0, bp, Color(0.18, 0.35, 0.16), 7)
				_box(Vector3(0.2, 0.2, 0.2), bp + Vector3(0.3, 0.45, 0.3), Color(0.45, 0.15, 0.45))
			for i in 4:
				_soldier(Vector3(-4 + i * 2.5, 0, 3), Vector3.FORWARD, {"anim": "kneel"})
			_cam_from = Vector3(-6, 2.6, 9)
			_cam_to = Vector3(5, 3, 9)
			_look = Vector3(0, 0.6, 0)
		"lost", "road":
			_box(Vector3(4, 0.04, 80), Vector3(0, 0.02, 0), (_cols["dirt"] as Color).lightened(0.12))
			_trees(18, 8, 40)
			_column(10, Vector3(0, 0, 22), Vector3(0, 0, -26), 1.4)
			if kind == "lost":
				_soldier(Vector3(1.5, 0, 6), Vector3.BACK, {"anim": "idle"})
			_cam_from = Vector3(7, 3, 8)
			_cam_to = Vector3(6, 3.5, -4)
			_look = Vector3(0, 1, 0)
		"ruins":
			for i in 9:
				_box(Vector3(_rng.randf_range(1, 2.5), _rng.randf_range(0.6, 3.5), _rng.randf_range(1, 2)), Vector3(_rng.randf_range(-7, 7), 0.8, _rng.randf_range(-7, 0)), Color(0.5, 0.52, 0.45), _rng.randf() * TAU)
			_cyl(1.6, 1.8, 7.0, Vector3(4, 3.5, -6), Color(0.5, 0.52, 0.46), 8)
			var fallen := _cyl(1.5, 1.6, 6.0, Vector3(0, 1.0, -8), Color(0.48, 0.5, 0.44), 8)
			fallen.rotation.z = PI * 0.5
			_trees(14, 12, 40)
			for i in 3:
				_soldier(Vector3(-3 + i * 2.5, 0, 3), Vector3.FORWARD, {"anim": "idle"})
			_cam_from = Vector3(-8, 3, 10)
			_cam_to = Vector3(6, 4, 10)
			_look = Vector3(0, 1.5, -4)
		"fever", "bog", "spoor":
			_env.fog_density = 0.05 if kind == "fever" else 0.02
			_env.fog_light_color = Color(0.75, 0.78, 0.72)
			for i in 30:
				_box(Vector3(0.06, _rng.randf_range(0.8, 1.6), 0.06), Vector3(_rng.randf_range(-12, 12), 0.5, _rng.randf_range(-12, 4)), Color(0.45, 0.48, 0.28))
			_trees(10, 6, 30, Vector3.ZERO, true)
			if kind == "bog":
				_water(Vector3(0, 0, 0), Vector2(9, 7), 0.3, true)
				var w := Props.wagon()
				w.position = Vector3(0, -0.45, 0)
				w.rotation = Vector3(0.12, 0.3, 0.05)
				_root.add_child(w)
				for i in 4:
					_soldier(Vector3(-1.5 + i, 0, 2.3), Vector3.FORWARD, {"anim": "haul"})
			elif kind == "spoor":
				for i in 3:
					_soldier(Vector3(-2 + i * 2, 0, 1), Vector3.FORWARD, {"anim": "kneel" if i != 1 else "idle"})
			else:
				_column(7, Vector3(-16, 0, 3), Vector3(16, 0, -3), 0.9)
			_cam_from = Vector3(-6, 2.6, 9)
			_cam_to = Vector3(5, 3, 8)
			_look = Vector3(0, 0.6, 0)
		"ambush", "warband":
			_trees(26 if kind == "ambush" else 12, 9, 40)
			_lizards(9 if kind == "ambush" else 12, Vector3(0, 0, -17), Vector3(0, 0, -1), 8.0, 1.6)
			for i in 5:
				_soldier(Vector3(-3 + i * 1.5, 0, 6), Vector3.FORWARD, {"anim": "aim" if i % 2 == 0 else "idle"})
			_cam_from = Vector3(-4, 2.2, 11)
			_cam_to = Vector3(4, 2.6, 10)
			_look = Vector3(0, 1, -8)
		"farmer", "pedlar", "refugees":
			_box(Vector3(4, 0.04, 80), Vector3(0, 0.02, 0), (_cols["dirt"] as Color).lightened(0.12))
			_trees(14, 9, 40)
			if kind == "pedlar":
				_beast(Vector3(0.8, 0, -1.5), 0.0, Color(0.42, 0.36, 0.3), 0, 0.85)
				_rig("civilian", Vector3(-0.5, 0, -1.0), Vector3.BACK, {"anim": "talk", "hat": "tricorne"})
			else:
				_cart(Vector3(0.5, 0, -2), 0.0, Color(0.55, 0.45, 0.3) if kind == "farmer" else Color(0.5, 0.42, 0.38))
				_rig("civilian", Vector3(-0.6, 0, -0.2), Vector3.BACK, {"anim": "talk", "hat": "cap"})
				if kind == "refugees":
					_rig("civilian", Vector3(1.6, 0, 0.0), Vector3.BACK, {"anim": "idle", "female": true})
					var child = _rig("civilian", Vector3(2.4, 0, 0.4), Vector3.BACK, {"anim": "idle"})
					child["rig"].scale = Vector3.ONE * 0.6
			for i in 3:
				_soldier(Vector3(-1.5 + i * 1.4, 0, 3.0), Vector3.FORWARD, {"anim": "idle"})
			_cam_from = Vector3(-5, 2.2, 7)
			_cam_to = Vector3(4, 2.5, 6)
			_look = Vector3(0, 1.1, -0.5)
		"deserters", "patrol":
			_box(Vector3(4, 0.04, 80), Vector3(0, 0.02, 0), (_cols["dirt"] as Color).lightened(0.12))
			_trees(14, 9, 40)
			var fac := String(ctx.get("faction", "vell"))
			var col: Color = Lore.FACTIONS.get(fac, Lore.FACTIONS["vell"])["color"]
			var n := 3 if kind == "deserters" else 7
			for i in n:
				var r = _rig("civilian", Vector3(-2 + i * 1.2, 0, -2 - (i % 2)), Vector3.BACK,
					{"anim": "idle" if kind == "deserters" else "walk", "cloth": col.darkened(0.2), "hat": "tricorne",
					"path": [] if kind == "deserters" else [Vector3(-2 + i * 1.2, 0, -14), Vector3(-2 + i * 1.2, 0, 6)], "speed": 1.2})
			if kind == "deserters":
				for i in 3:
					_soldier(Vector3(-1.5 + i * 1.4, 0, 3.0), Vector3.FORWARD, {"anim": "idle"})
			_cam_from = Vector3(-6, 2.3, 8)
			_cam_to = Vector3(5, 2.6, 7)
			_look = Vector3(0, 1.1, -1)
		"vantage":
			var crag := _cyl(4.0, 9.0, 14.0, Vector3(0, 7, -6), Color(0.45, 0.44, 0.42), 7)
			crag.rotation.y = 0.3
			_soldier(Vector3(0, 14.0, -6), Vector3.LEFT, {"anim": "point"})
			_trees(20, 12, 50)
			_column(5, Vector3(-20, 0, 10), Vector3(14, 0, 4), 1.0)
			_cam_from = Vector3(-22, 8, 32)
			_cam_to = Vector3(16, 10, 30)
			_look = Vector3(0, 7, -6)
		"camp":
			# Abandoned: a torn tent, cold ashes, nobody.
			_box(Vector3(3, 1.6, 3), Vector3(0, 0.8, -3), Color(0.7, 0.66, 0.55), 0.4, 0.3)
			for i in 6:
				_box(Vector3(0.22, 0.12, 0.18), Vector3(cos(i) * 0.6 + 2, 0.06, sin(i) * 0.6), Color(0.35, 0.35, 0.33))
			_box(Vector3(1.0, 0.05, 1.0), Vector3(2, 0.03, 0), Color(0.15, 0.14, 0.13))
			_trees(18, 8, 40)
			for i in 3:
				_soldier(Vector3(-2 + i * 1.8, 0, 3), Vector3.FORWARD, {"anim": "kneel" if i == 1 else "idle"})
			_cam_from = Vector3(-6, 2.6, 8)
			_cam_to = Vector3(5, 3, 8)
			_look = Vector3(0, 0.8, -1)
		"prospectors", "traders":
			_box(Vector3(4, 0.04, 80), Vector3(0, 0.02, 0), (_cols["dirt"] as Color).lightened(0.12))
			_trees(10, 9, 40)
			_beast(Vector3(1.5, 0, -1.5), 0.0, Color(0.36, 0.3, 0.24), 0, 0.75)
			for i in 3:
				_rig("civilian", Vector3(-1.5 + i * 1.1, 0, -0.5), Vector3.BACK, {"anim": "talk" if i == 1 else "idle", "dwarf": true,
					"cloth": Color(0.4, 0.3, 0.2).lerp(Color(0.5, 0.4, 0.3), i * 0.3)})
			for i in 3:
				_soldier(Vector3(-1.5 + i * 1.4, 0, 3.0), Vector3.FORWARD, {"anim": "idle"})
			_cam_from = Vector3(-5, 2.0, 7)
			_cam_to = Vector3(4, 2.3, 6)
			_look = Vector3(0, 1.0, -0.5)
		"caravan", "villagers":
			_box(Vector3(4, 0.04, 80), Vector3(0, 0.02, 0), (_cols["dirt"] as Color).lightened(0.12))
			_trees(14, 9, 40)
			var carts := 2 if kind == "caravan" else 1
			for i in carts:
				_cart(Vector3(0.5, 0, -2 - i * 5), 0.0)
			for i in (4 if kind == "caravan" else 5):
				_rig("civilian", Vector3(-1.2 + (i % 2) * 2.6, 0, -1 - i * 2), Vector3.BACK,
					{"anim": "walk", "female": kind == "villagers" and i % 2 == 0,
					"path": [Vector3(-1.2 + (i % 2) * 2.6, 0, -16 - i * 2), Vector3(-1.2 + (i % 2) * 2.6, 0, 8 - i * 2)], "speed": 1.0})
			_cam_from = Vector3(7, 2.6, 6)
			_cam_to = Vector3(6, 3, -4)
			_look = Vector3(0, 1, -2)
		"menu":
			# The main menu's backdrop: the company's camp on a strange shore
			# at night. The fire sits right of centre, clear of the menu.
			_fire(Vector3.ZERO)
			var w3 := Props.wagon()
			w3.position = Vector3(4.6, 0, -3.4)
			w3.rotation.y = 0.9
			_root.add_child(w3)
			# The colours, planted by the wagon: Calder's blue with a white cross.
			_cyl(0.03, 0.035, 3.2, Vector3(2.6, 1.6, -4.4), Color(0.45, 0.32, 0.18))
			_box(Vector3(1.1, 0.75, 0.02), Vector3(3.17, 2.75, -4.4), Color(0.13, 0.2, 0.45))
			_box(Vector3(1.1, 0.11, 0.025), Vector3(3.17, 2.75, -4.4), Color(0.9, 0.88, 0.8))
			_box(Vector3(0.11, 0.75, 0.025), Vector3(2.95, 2.75, -4.4), Color(0.9, 0.88, 0.8))
			# The sentry, musket shouldered, looking out into the dark.
			_soldier(Vector3(-1.4, 0, -2.2), Vector3(-0.5, 0, -1), {"anim": "idle"})
			# Two awake by the fire, the rest asleep on their blankets.
			_soldier(Vector3(1.5, 0, -0.9), Vector3(-1, 0, 0.5), {"anim": "kneel"})
			_soldier(Vector3(-0.3, 0, 1.7), Vector3(0.15, 0, -1), {"anim": "idle"})
			for i in 6:
				var a := lerpf(-0.2, PI * 0.9, (i + 0.5) / 6.0)
				var d := Vector3(cos(a), 0, -sin(a))
				_soldier(d * (3.4 + (i % 2) * 1.1), -d, {"anim": "sleep"})
				_box(Vector3(0.78, 0.07, 1.95), d * (3.4 + (i % 2) * 1.1) + d * 0.85 + Vector3(0, 0.035, 0), Color(0.36, 0.3, 0.22), atan2(d.x, d.z))
			_trees(26, 12, 45)
			_cam_from = Vector3(-6.5, 2.6, 7.5)
			_cam_to = Vector3(-4.0, 2.9, 8.6)
			_look = Vector3(-2.6, 1.1, -1.5)
			_period = 70.0
		"camp_night", "dusk", "camp_attack":
			_fire(Vector3.ZERO)
			var w2 := Props.wagon()
			w2.position = Vector3(5, 0, -2)
			w2.rotation.y = 0.5
			_root.add_child(w2)
			for i in 9:
				var a := lerpf(-PI * 0.8, PI * 0.8, (i + 0.5) / 9.0)
				var d := Vector3(sin(a), 0, -cos(a))
				var asleep := kind != "dusk"
				var r2 = _soldier(d * (3.2 + (i % 2) * 1.2), -d, {"anim": "sleep" if asleep else ("idle" if i % 3 else "kneel")})
				_box(Vector3(0.78, 0.07, 1.95), d * (3.2 + (i % 2) * 1.2) + d * 0.85 + Vector3(0, 0.035, 0), Color(0.36, 0.3, 0.22), atan2(d.x, d.z))
			_trees(16, 10, 40)
			if kind == "camp_attack":
				_lizards(7, Vector3(0, 0, -24), Vector3(0, 0, -2), 7.0, 2.2)
			_cam_from = Vector3(-7, 3, 8)
			_cam_to = Vector3(6, 3.5, 8)
			_look = Vector3(0, 0.6, -1)
		"scouts_back", "scouts_lost":
			_box(Vector3(3, 0.04, 80), Vector3(0, 0.02, 0), (_cols["dirt"] as Color).lightened(0.12))
			_trees(14, 8, 40)
			if kind == "scouts_back":
				for i in int(ctx.get("n", 2)):
					_soldier(Vector3(i * 1.2, 0, -9 - i * 2), Vector3.BACK, {"anim": "walk", "path": [Vector3(i * 1.2, 0, -26 - i * 2), Vector3(i * 1.2, 0, 3)], "speed": 2.6, "loop": true})
				for i in 3:
					_soldier(Vector3(-1.5 + i * 1.4, 0, 6.0), Vector3.FORWARD, {"anim": "idle"})
			else:
				# An empty road, and a hat lying in it.
				_box(Vector3(0.3, 0.12, 0.3), Vector3(0.4, 0.06, -3), Color(0.08, 0.08, 0.1))
				_soldier(Vector3(-0.5, 0, 4), Vector3.FORWARD, {"anim": "idle"})
			_cam_from = Vector3(5, 2.4, 9)
			_cam_to = Vector3(3, 3, -2)
			_look = Vector3(0, 1, -6)
		"burned":
			for i in 6:
				var hp := Vector3(_rng.randf_range(-10, 10), 0, _rng.randf_range(-12, -2))
				_box(Vector3(4, _rng.randf_range(0.4, 1.4), 3), hp + Vector3(0, 0.4, 0), Color(0.14, 0.12, 0.11), _rng.randf() * TAU)
				for k in 3:
					_box(Vector3(0.15, _rng.randf_range(1, 2.6), 0.15), hp + Vector3(_rng.randf_range(-1.5, 1.5), 1.0, _rng.randf_range(-1, 1)), Color(0.1, 0.09, 0.08), 0.0, _rng.randf_range(-0.4, 0.4))
			_env.fog_density = 0.03
			_env.fog_light_color = Color(0.45, 0.43, 0.42)
			for i in 3:
				_soldier(Vector3(-2 + i * 1.8, 0, 4), Vector3.FORWARD, {"anim": "idle"})
			_cam_from = Vector3(-7, 3, 10)
			_cam_to = Vector3(6, 3.5, 9)
			_look = Vector3(0, 0.8, -6)
		"nest":
			_box(Vector3(14, 3, 10), Vector3(0, 1.5, -14), Color(0.3, 0.24, 0.16), 0.3)
			_box(Vector3(8, 2.5, 6), Vector3(0, 3.6, -14), Color(0.26, 0.2, 0.14), 0.9)
			for k in 14:
				var a2 := TAU * k / 14.0
				_box(Vector3(0.35, 4.0, 0.35), Vector3(cos(a2) * 10.0, 2.0, sin(a2) * 8.0 - 14), Color(0.85, 0.8, 0.68), a2, 0.3)
			for i in 8:
				var p := Vector3(_rng.randf_range(-10, 10), 0, _rng.randf_range(-20, -6))
				_rig("lizard", p, Vector3(_rng.randf_range(-1, 1), 0, 1), {"anim": "idle",
					"path": [p, p + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-3, 3))], "speed": 1.0})
			_trees(10, 22, 50, Vector3(0, 0, -14), true)
			_cam_from = Vector3(-10, 4, 8)
			_cam_to = Vector3(8, 5, 8)
			_look = Vector3(0, 2, -12)
		_:
			kind = "road"
			_stage()
