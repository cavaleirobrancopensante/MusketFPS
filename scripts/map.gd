extends Node3D
## The campaign map: the land in 3D, under fog of war. Draws World and turns
## your taps into orders; the world itself lives in world.gd.
##
## Controls: tap the ground to march there (tap a settlement to visit it, a
## party to go after it); drag to pan; pinch or mouse wheel to zoom; CENTRE
## to follow your party again. The clock runs only while you march or WAIT.
##
## Drawing, kept cheap for phones:
##   terrain  64 chunk meshes with vertex colours (terrain, rivers, roads),
##            one shader that darkens what you've never seen and dims what
##            you can't see now (the fog texture: one texel per cell)
##   trees    one MultiMesh per chunk; settlements: one MultiMesh of boxes
##   parties  small figures with banners, shown only while in sight
const UI := preload("res://scripts/ui.gd")

const Gen := preload("res://scripts/world_gen.gd")
const Lore := preload("res://scripts/lore.gd")
const Men := preload("res://scripts/men.gd")
const LogisticsPopup := preload("res://scripts/logistics_popup.gd")
const BATTLE := "res://scenes/battle.tscn"
const CAMP := "res://scenes/aftermath.tscn"
const COMPANY_SCREEN := "res://scenes/company.tscn"
const MENU := "res://scenes/menu.tscn"
const MusicBar := preload("res://scripts/music_bar.gd")
const Vignette := preload("res://scripts/vignette.gd")
const PLAN := "res://scenes/battleplan.tscn"

const CELL := 2.0 # world units per cell
const HS := 60.0 # height scale
const CHUNK := 64
const MIN_DIST := 14.0
const MAX_DIST := 900.0
const T := Gen.T

const COLORS := {
	T.SEA: Color(0.13, 0.25, 0.36), T.BEACH: Color(0.78, 0.72, 0.52), T.PLAINS: Color(0.46, 0.56, 0.29),
	T.FOREST: Color(0.2, 0.34, 0.17), T.HILLS: Color(0.54, 0.51, 0.33), T.MOUNTAIN: Color(0.5, 0.48, 0.46),
	T.SWAMP: Color(0.3, 0.35, 0.23), T.LAKE: Color(0.22, 0.38, 0.52),
}
const RIVER_COL := Color(0.25, 0.46, 0.66)
const ROAD_COLS := [Color(0, 0, 0), Color(0.46, 0.41, 0.31), Color(0.6, 0.5, 0.36), Color(0.74, 0.64, 0.47)]

const MAP_SHADER := """
shader_type spatial;
uniform sampler2D fog : filter_linear;
uniform float world_size;
uniform bool use_tint = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 unknown_col = vec3(0.16, 0.145, 0.12);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float f = texture(fog, wpos.xz / world_size).r;
	vec3 c = use_tint ? tint.rgb : COLOR.rgb;
	float seen = smoothstep(0.12, 0.42, f);
	float vis = smoothstep(0.62, 0.92, f);
	vec3 dim = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 0.55) * 0.78;
	// Never-seen land is flat parchment, unlit, so its relief gives nothing away.
	ALBEDO = mix(dim, c, vis) * seen;
	EMISSION = unknown_col * (1.0 - seen);
	ROUGHNESS = use_tint ? 0.3 : 0.95;
}
"""

var _fog_img: Image
var _fog_tex: ImageTexture
var _shader: Shader
var _mat: ShaderMaterial # terrain, trees, buildings (vertex/instance colours)
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _target := Vector3.ZERO
var _dist := 130.0
var _follow := true
var _touches := {} # index -> position
var _press_pos := Vector2.ZERO
var _dragged := false
var _pinch_d := 0.0
var _prev_vis: Array = []

var _player: Node3D
var _path_mesh: ImmediateMesh
var _markers := {} # party id -> Node3D
var _labels := {} # settlement id -> Label3D
var _chase := {} # {"id": party id} while going after a party
var _chase_t := 0.0

# HUD
var _clock: Label
var _status: Label
var _terrain_l: Label
var _toast: Label
var _toasts: Array = []
var _toast_t := 0.0
var _wait_btn: Button
var _popup: PanelContainer
var _popup_title: Label
var _popup_text: RichTextLabel
var _popup_buttons: HBoxContainer
var _logistics
var _test := false
var _test_t := 0.0


func _ready() -> void:
	_test = "--maptest" in OS.get_cmdline_user_args()
	# Built in stages behind the loading screen (see loading.gd); the
	# fractions follow how long each stage takes.
	Loading.begin(self)
	# How long each stage takes (ms on a desktop; the phone is slower but in
	# proportion): a new or reloaded land is most of it.
	var f := Loading.plan([0 if World.is_ready else 1500, 670, 1, 140, 335, 20])
	if not World.is_ready and Loading.active:
		# The land itself, phase by phase (most of the wait on a new or loaded game).
		await World.prebuild(func(fr: float, what: String):
			await Loading.step(lerpf(f[0], f[1] - 0.08, fr), what))
		await Loading.step(f[1] - 0.08, "Charting the roads and the march...")
	World.ensure()
	await Loading.step(f[1], "Drawing the land...")
	_shader = Shader.new()
	_shader.code = MAP_SHADER
	_build_fog()
	_mat = _material(false, Color.WHITE)
	_build_env()
	_build_terrain()
	await Loading.step(f[2], "Rivers, lakes and the sea...")
	_build_sea()
	await Loading.step(f[3], "Planting the forests...")
	_build_trees()
	await Loading.step(f[4], "Roads, bridges, villages and towns...")
	_build_bridges()
	_build_settlements()
	_build_player()
	_build_hud()
	World.day_passed.connect(_on_day)
	World.news.connect(func(t): _push_toast(t))
	World.encounter.connect(_on_encounter)
	World.arrived.connect(_on_arrived)
	World.dusk.connect(_on_dusk)
	World.dawn.connect(func(): _push_toast("Dawn. The company breaks camp." + (" On the march again." if World.moving() else "")))
	World.event.connect(_on_event)
	World.scouts_back.connect(_on_scouts_back)
	World.revealed.connect(func(): _rebuild_fog())
	Music.set_context("camp" if World.camping else "map")
	_target = _world_pos(World.pos)
	_apply_battle_result()
	await Loading.step(f[5], "Fog over the unknown...")
	_update_fog(true)
	_update_camera()
	if World.pending_rest > 0.0:
		# Resting in the town you just left.
		World.waiting = true
		_rest_until = World.hours + World.pending_rest
		World.pending_rest = 0.0
	Loading.done(self)


func _exit_tree() -> void:
	World.save()


func _material(tinted: bool, col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("fog", _fog_tex)
	m.set_shader_parameter("world_size", Gen.SIZE * CELL)
	m.set_shader_parameter("use_tint", tinted)
	m.set_shader_parameter("tint", col)
	return m


func _world_pos(cell: Vector2) -> Vector3:
	var x := clampi(int(cell.x), 0, Gen.SIZE - 1)
	var y := clampi(int(cell.y), 0, Gen.SIZE - 1)
	return Vector3(cell.x * CELL, maxf(World.gen.h(x, y), Gen.SEA_LEVEL) * HS, cell.y * CELL)


# ---------------------------------------------------------------- building

func _build_fog() -> void:
	_fog_img = Image.create(Gen.SIZE, Gen.SIZE, false, Image.FORMAT_R8)
	var data := PackedByteArray()
	data.resize(Gen.SIZE * Gen.SIZE)
	for i in data.size():
		data[i] = 128 if World.explored[i] == 1 else 0
	_fog_img.set_data(Gen.SIZE, Gen.SIZE, false, Image.FORMAT_R8, data)
	_fog_tex = ImageTexture.create_from_image(_fog_img)


func _build_env() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.08, 0.08, 0.09)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.75, 0.75, 0.8)
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 3000.0
	add_child(_cam)


## The ground: one mesh per CHUNK x CHUNK cells, coloured by terrain, with
## rivers and roads painted in.
func _build_terrain() -> void:
	var g = World.gen
	var n: int = Gen.SIZE
	var cols := PackedColorArray()
	cols.resize(n * n)
	for y in n:
		for x in n:
			var i := y * n + x
			var tt: int = g.terrain[i]
			var c: Color = COLORS[tt]
			var hh: float = g.height[i]
			if tt == T.MOUNTAIN and hh > 0.84:
				c = c.lerp(Color(0.92, 0.92, 0.95), clampf((hh - 0.84) * 8.0, 0.0, 1.0)) # snow
			elif tt == T.PLAINS or tt == T.HILLS:
				c = c.lerp(COLORS[T.HILLS], clampf((hh - 0.5) * 3.0, 0.0, 0.6))
			var jitter := float(((x * 73856093) ^ (y * 19349663)) & 255) / 255.0
			c = c * (0.94 + 0.12 * jitter)
			if g.river[i] == 1 or g.river[i] == 2:
				c = RIVER_COL.lerp(Color(0.5, 0.62, 0.7), 0.5 if g.river[i] == 2 else 0.0)
			if g.road[i] > 0:
				c = c.lerp(ROAD_COLS[g.road[i]], [0.0, 0.5, 0.7, 0.85][g.road[i]])
			c.a = 1.0
			cols[i] = c
	for cy in range(0, n, CHUNK):
		for cx in range(0, n, CHUNK):
			_chunk(cx, cy, cols)


func _chunk(cx: int, cy: int, cols: PackedColorArray) -> void:
	var g = World.gen
	var w := mini(CHUNK + 1, Gen.SIZE - cx)
	var hgt := mini(CHUNK + 1, Gen.SIZE - cy)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(w * hgt)
	norms.resize(w * hgt)
	vcols.resize(w * hgt)
	for j in hgt:
		for i in w:
			var x := cx + i
			var y := cy + j
			var hh: float = g.h(x, y)
			verts[j * w + i] = Vector3(x * CELL, hh * HS, y * CELL)
			var dx: float = (g.h(x + 1, y) - g.h(x - 1, y)) * HS
			var dz: float = (g.h(x, y + 1) - g.h(x, y - 1)) * HS
			norms[j * w + i] = Vector3(-dx, 2.0 * CELL, -dz).normalized()
			vcols[j * w + i] = cols[y * Gen.SIZE + x]
	for j in hgt - 1:
		for i in w - 1:
			var a := j * w + i
			idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = vcols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	var size := Gen.SIZE * CELL
	plane.size = Vector2(size * 3.0, size * 3.0)
	plane.material = _material(true, Color(0.14, 0.27, 0.4))
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(size * 0.5, Gen.SEA_LEVEL * HS - 0.4, size * 0.5)
	add_child(mi)


## Trees on forest (thick), swamp (sparse, dark) and a few on the plains.
func _build_trees() -> void:
	var g = World.gen
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 0
	cone.material = _mat
	var rng := RandomNumberGenerator.new()
	rng.seed = World.seed
	for cy in range(0, Gen.SIZE, CHUNK):
		for cx in range(0, Gen.SIZE, CHUNK):
			var xf: Array = []
			var cl: Array = []
			for y in range(cy, cy + CHUNK):
				for x in range(cx, cx + CHUNK):
					var i: int = Gen.idx(x, y)
					var tt: int = g.terrain[i]
					var p := 0.0
					if tt == T.FOREST:
						p = 0.55
					elif tt == T.SWAMP:
						p = 0.12
					elif tt == T.PLAINS or tt == T.HILLS:
						p = 0.015
					if g.river[i] != 0 or g.road[i] != 0 or rng.randf() >= p:
						continue
					var s := rng.randf_range(0.9, 1.6)
					var pos := Vector3((x + rng.randf()) * CELL, g.height[i] * HS + s * 1.4, (y + rng.randf()) * CELL)
					xf.append(Transform3D(Basis().scaled(Vector3(s, s * 3.0, s)), pos))
					var base := Color(0.12, 0.27, 0.13) if tt != T.SWAMP else Color(0.22, 0.25, 0.15)
					cl.append(base * rng.randf_range(0.8, 1.2))
			if xf.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = cone
			mm.instance_count = xf.size()
			for k in xf.size():
				mm.set_instance_transform(k, xf[k])
				mm.set_instance_color(k, cl[k])
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(inst)


## Boxes for buildings, walls, bridges: all in one MultiMesh.
var _box_xf: Array = []
var _box_col: Array = []


func _box(pos: Vector3, size: Vector3, col: Color, yaw := 0.0, tilt := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	_box_xf.append(Transform3D(b * Basis().scaled(size), pos))
	_box_col.append(col)


func _build_bridges() -> void:
	var g = World.gen
	for i in g.river.size():
		if g.river[i] == 3:
			var x: int = i % Gen.SIZE
			var y: int = i / Gen.SIZE
			_box(Vector3((x + 0.5) * CELL, g.height[i] * HS + 0.6, (y + 0.5) * CELL), Vector3(2.4, 0.4, 2.4), Color(0.5, 0.42, 0.32))


func _build_settlements() -> void:
	var g = World.gen
	var rng := RandomNumberGenerator.new()
	rng.seed = World.seed + 7
	for st in g.settlements:
		var c := _world_pos(Vector2(st["x"], st["y"]) + Vector2(0.5, 0.5))
		var fac: Dictionary = Lore.FACTIONS[st["faction"]]
		var banner: Color = fac["color"]
		match st["kind"]:
			"village":
				_houses(c, rng.randi_range(4, 6), 4.0, rng, Color(0.62, 0.5, 0.36), Color(0.45, 0.28, 0.18))
				for k in 3:
					_box(c + Vector3(rng.randf_range(-7, 7), 0.05, rng.randf_range(-7, 7)), Vector3(4, 0.1, 3), Color(0.72, 0.64, 0.3), rng.randf() * TAU)
			"town":
				_houses(c, 10, 6.0, rng, Color(0.66, 0.58, 0.46), Color(0.5, 0.25, 0.18))
				_ring(c, 8.5, 10, Vector3(5.0, 2.0, 0.6), Color(0.45, 0.36, 0.24)) # palisade
				_box(c + Vector3(0, 3.0, 0), Vector3(1.6, 6.0, 1.6), Color(0.7, 0.68, 0.62)) # church tower
			"city":
				_houses(c, 22, 10.0, rng, Color(0.72, 0.68, 0.6), Color(0.48, 0.22, 0.16))
				_ring(c, 13.0, 14, Vector3(6.0, 3.6, 1.2), Color(0.62, 0.6, 0.56)) # stone walls
				_box(c + Vector3(0, 4.0, 0), Vector3(5.0, 8.0, 5.0), Color(0.66, 0.64, 0.6)) # keep
				for k in 4:
					var a := TAU * k / 4.0 + 0.4
					_box(c + Vector3(cos(a) * 13.0, 3.0, sin(a) * 13.0), Vector3(2.4, 6.0, 2.4), Color(0.6, 0.58, 0.54))
			"hold":
				_box(c + Vector3(0, 3.0, 0), Vector3(9.0, 6.0, 5.0), Color(0.36, 0.34, 0.33))
				_box(c + Vector3(0, 1.6, 2.6), Vector3(3.0, 3.2, 0.3), Color(0.95, 0.6, 0.2)) # the glowing gate
				_box(c + Vector3(-5.5, 5.0, 0), Vector3(2.4, 10.0, 2.4), Color(0.4, 0.38, 0.36))
				_box(c + Vector3(5.5, 5.0, 0), Vector3(2.4, 10.0, 2.4), Color(0.4, 0.38, 0.36))
			"nest":
				_box(c + Vector3(0, 1.2, 0), Vector3(10.0, 2.4, 8.0), Color(0.3, 0.24, 0.16), 0.3)
				_box(c + Vector3(0, 2.6, 0), Vector3(6.0, 2.0, 5.0), Color(0.26, 0.2, 0.14), 0.9)
				for k in 10:
					var a2 := TAU * k / 10.0
					_box(c + Vector3(cos(a2) * 7.0, 2.0, sin(a2) * 6.0), Vector3(0.35, 4.0, 0.35), Color(0.85, 0.8, 0.68), a2, 0.3)
		# A banner in the faction's colour.
		_box(c + Vector3(1.5, 4.5 if st["kind"] != "city" else 10.5, 1.5), Vector3(0.15, 3.0, 0.15), Color(0.3, 0.25, 0.2))
		_box(c + Vector3(2.3, 5.4 if st["kind"] != "city" else 11.4, 1.5), Vector3(1.6, 1.0, 0.08), banner)
		_label_for(st, c)
	var cube := BoxMesh.new()
	cube.material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cube
	mm.instance_count = _box_xf.size()
	for k in _box_xf.size():
		mm.set_instance_transform(k, _box_xf[k])
		mm.set_instance_color(k, _box_col[k])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	add_child(inst)


func _houses(c: Vector3, n: int, spread: float, rng: RandomNumberGenerator, wall: Color, roof: Color) -> void:
	for k in n:
		var p := c + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.8, 1.3)
		_box(p + Vector3(0, 0.8 * s, 0), Vector3(2.2, 1.6, 1.6) * s, wall, yaw)
		_box(p + Vector3(0, 1.85 * s, 0), Vector3(2.4, 0.5, 1.8) * s, roof, yaw)


func _ring(c: Vector3, r: float, n: int, seg: Vector3, col: Color) -> void:
	for k in n:
		var a := TAU * (k + 0.5) / n
		_box(c + Vector3(cos(a) * r, seg.y * 0.5, sin(a) * r), seg, col, -a + PI * 0.5)


func _label_for(st: Dictionary, c: Vector3) -> void:
	var l := Label3D.new()
	var kind: String = st["kind"]
	var what: String = {"village": "", "town": "", "city": "", "hold": "  (dwarf hold)", "nest": "  (lizard nest)"}[kind]
	l.text = String(st["name"]) + what
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = {"city": 34, "town": 28, "village": 22, "hold": 28, "nest": 26}[kind]
	l.font = UI.display_font()
	l.outline_size = 8
	l.modulate = Color(1, 0.95, 0.85) if kind != "nest" else Color(0.75, 1.0, 0.6)
	l.no_depth_test = true
	l.position = c + Vector3(0, 9.0 if kind != "city" else 16.0, 0)
	l.visible = false
	add_child(l)
	_labels[int(st["id"])] = l


func _build_player() -> void:
	_player = _figure(Color(0.16, 0.24, 0.55), Color(0.92, 0.92, 0.95), 1.3)
	add_child(_player)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.9
	tm.outer_radius = 2.3
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.95, 0.8, 0.4)
	tm.material = rm
	ring.mesh = tm
	_player.add_child(ring)
	_path_mesh = ImmediateMesh.new()
	var pm := MeshInstance3D.new()
	pm.mesh = _path_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.95, 0.8, 0.4)
	pm.material_override = lm
	add_child(pm)


## A party on the map: a little group of figures and a banner.
func _figure(body: Color, banner: Color, scale_f: float) -> Node3D:
	var n := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = body
	for k in 3:
		var b := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.35
		bm.height = 1.6
		bm.material = m
		b.mesh = bm
		b.position = Vector3(cos(k * 2.1) * 0.7, 0.8, sin(k * 2.1) * 0.7)
		n.add_child(b)
	var pole := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, 3.2, 0.1)
	pole.mesh = pm
	pole.position = Vector3(0, 1.6, 0)
	n.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.2, 0.8, 0.06)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = banner
	fm.material = fmat
	flag.mesh = fm
	flag.position = Vector3(0.65, 2.8, 0)
	n.add_child(flag)
	n.scale = Vector3.ONE * scale_f
	return n


func _marker_for(p: Dictionary) -> Node3D:
	var id := int(p["id"])
	if _markers.has(id):
		return _markers[id]
	var fac: Dictionary = Lore.FACTIONS[p["faction"]]
	var body := Color(0.3, 0.5, 0.2) if p["faction"] == "lizards" else Color(0.45, 0.4, 0.34)
	var n := _figure(body, fac["color"], 0.9 + minf(float(p["size"]) / 25.0, 1.0))
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = 22
	l.outline_size = 8
	l.no_depth_test = true
	l.position = Vector3(0, 4.5, 0)
	l.modulate = Color(1, 0.6, 0.5) if p["faction"] == "lizards" else Color(0.9, 0.9, 1.0)
	l.name = "label"
	n.add_child(l)
	add_child(n)
	_markers[id] = n
	return n


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var top := _panel(Color(UI.NIGHT, 0.8))
	top.position = Vector2(12, 12)
	root.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	_clock = _label("", 22, Color(0.95, 0.8, 0.45))
	tv.add_child(_clock)
	_status = _label("", 17, Color.WHITE)
	tv.add_child(_status)
	var bottom := _panel(Color(UI.NIGHT, 0.8))
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.position = Vector2(12, -70)
	root.add_child(bottom)
	_terrain_l = _label("", 17, Color.WHITE)
	bottom.add_child(_terrain_l)
	_toast = _label("", 22, Color(1, 0.93, 0.75))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 96
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_toast)

	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.position = Vector2(-170, 12)
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	for spec in [["YOU", func():
				get_tree().set_meta("officer_back", "res://scenes/map.tscn")
				_go("res://scenes/officer.tscn")],
			["COMPANY", _go.bind(COMPANY_SCREEN)], ["PLAN", _go.bind(PLAN)], ["WAGON", func(): _logistics.open()], ["SCOUTS", _open_scouts],
			["CAMP", _go.bind(CAMP)], ["MENU", _go.bind(MENU)]]:
		right.add_child(_button(spec[0], spec[1]))
	var br := HBoxContainer.new()
	br.anchor_left = 1.0
	br.anchor_right = 1.0
	br.anchor_top = 1.0
	br.anchor_bottom = 1.0
	br.position = Vector2(-430, -76)
	br.add_theme_constant_override("separation", 8)
	root.add_child(br)
	_wait_btn = _button("WAIT", _on_wait)
	br.add_child(_wait_btn)
	br.add_child(_button("CENTRE", func(): _follow = true))
	br.add_child(_button("−", func(): _zoom(1.35)))
	br.add_child(_button("+", func(): _zoom(1.0 / 1.35)))

	_popup = _panel(Color(UI.WOOL, 0.97))
	_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_popup.custom_minimum_size = Vector2(620, 0)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_popup.visible = false
	root.add_child(_popup)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	_popup.add_child(pv)
	_popup_title = _label("", 26, Color(0.95, 0.8, 0.45))
	pv.add_child(_popup_title)
	# A little live scene of what's happening (vignette.gd) beside the text.
	_popup_row = HBoxContainer.new()
	_popup_row.add_theme_constant_override("separation", 14)
	pv.add_child(_popup_row)
	_popup_scene = Control.new()
	_popup_row.add_child(_popup_scene)
	_popup_text = RichTextLabel.new()
	_popup_text.bbcode_enabled = true
	_popup_text.fit_content = true
	_popup_text.scroll_active = false
	_popup_text.custom_minimum_size = Vector2(580, 0)
	_popup_text.add_theme_font_size_override("normal_font_size", 19)
	_popup_row.add_child(_popup_text)
	_popup_buttons = HBoxContainer.new()
	_popup_buttons.add_theme_constant_override("separation", 10)
	pv.add_child(_popup_buttons)
	_logistics = LogisticsPopup.new()
	root.add_child(_logistics)
	MusicBar.attach(root, Vector2(12, 140))


func _panel(col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(col, 12))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	UI.dress(l, size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 54)
	b.add_theme_font_size_override("font_size", 19)
	# (the theme's wool tabs)
	b.pressed.connect(cb)
	return b


## Put a panel in the middle of the screen once it knows its size.
func _center(c: Control) -> void:
	c.reset_size()
	await get_tree().process_frame
	c.reset_size()
	c.position = (get_viewport().get_visible_rect().size - c.size) * 0.5


func _go(scene: String) -> void:
	World.stop()
	World.save()
	Company.save()
	Loading.change(scene)


func _update_hud() -> void:
	var state := "   (paused)"
	if World.camping:
		state = "   (in camp, sleeping)"
	elif World.moving() or World.waiting:
		state = "" if not World.is_night() else "   (night march)" if World.moving() else ""
	_clock.text = World.clock() + state
	var fit := Company.fit_men().size()
	var cm := Company.company_morale()
	_status.text = "%d crowns · %d/%d men fit · morale %d (%s)\nfood %.1f days · water %.1f days%s" % [
		Company.money, fit, Company.roster.size(), cm, Men.morale_word(cm),
		Company.days_left("rations"), Company.days_left("water"), " · water foul" if bool(Company.stores["foul"]) else ""]
	var c := World.cell()
	var i: int = Gen.idx(c.x, c.y)
	var g = World.gen
	var what: String = Gen.T_NAMES[g.terrain[i]]
	if g.road[i] > 0:
		what = Gen.ROAD_NAMES[g.road[i]] + " through " + what.to_lower()
	if g.river[i] == 2:
		what = "Ford"
	elif g.river[i] == 3:
		what = "Bridge"
	var eta := ""
	if World.moving():
		eta = " · %d cells to go" % World.path.size()
	var scouting := ""
	if not World.scouts.is_empty():
		var out := 0
		for sc in World.scouts:
			out += (sc["ids"] as Array).size()
		scouting = "\n%d scout%s out" % [out, "" if out == 1 else "s"]
	_terrain_l.text = "%s · pace ×%.2f · sight %d%s%s" % [what, g.speed_at(c.x, c.y) * World.party_pace(),
		int(World.sight_radius()), eta, scouting]
	_wait_btn.text = "STOP" if World.waiting else "WAIT"


func _push_toast(t: String) -> void:
	_toasts.append(t)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	Music.set_context("camp" if World.camping else "map")
	if not _popup.visible and not _logistics.visible and (_scout_panel == null or not _scout_panel.visible):
		World.tick(delta)
	if _rest_until > 0.0 and World.hours >= _rest_until:
		World.waiting = false
		_rest_until = -1.0
	if not _chase.is_empty() and World.moving():
		_chase_t -= delta
		if _chase_t <= 0.0:
			_chase_t = 0.8
			var p := World.party_by_id(int(_chase["id"]))
			if p.is_empty():
				_chase = {}
			else:
				World.go_to(Vector2i(int(p["x"]), int(p["y"])), {"kind": "party", "id": int(p["id"])})
	_update_fog()
	_update_parties()
	_update_player()
	_update_light()
	_update_labels()
	if _follow:
		_target = _target.lerp(_world_pos(World.pos), 1.0 - exp(-6.0 * delta))
	_update_camera()
	_update_hud()
	_toast_t -= delta
	if _toast_t <= 0.0:
		if _toasts.is_empty():
			_toast.text = ""
		else:
			_toast.text = _toasts.pop_front()
			_toast_t = 3.5
	if _test:
		_run_test(delta)


## Explored land changed outside sight (scouts, a climb): redraw it all.
func _rebuild_fog() -> void:
	var data := _fog_img.get_data()
	for i in data.size():
		if World.explored[i] == 1 and data[i] < 128:
			data[i] = 128
	_fog_img.set_data(Gen.SIZE, Gen.SIZE, false, Image.FORMAT_R8, data)
	_fog_tex.update(_fog_img)


func _update_fog(force := false) -> void:
	var now: Array = World._vis_list
	if not force and now == _prev_vis:
		return
	var data := _fog_img.get_data()
	for i in _prev_vis:
		data[i] = 128
	for i in now:
		data[i] = 255
	_prev_vis = now.duplicate()
	_fog_img.set_data(Gen.SIZE, Gen.SIZE, false, Image.FORMAT_R8, data)
	_fog_tex.update(_fog_img)


func _update_parties() -> void:
	var alive := {}
	for p in World.parties:
		var id := int(p["id"])
		alive[id] = true
		var seen := World.can_see(p)
		if not seen and not _markers.has(id):
			continue
		var n := _marker_for(p)
		n.visible = seen
		if seen:
			n.position = _world_pos(Vector2(p["x"], p["y"]))
			(n.get_node("label") as Label3D).text = World.party_name(p)
	for id in _markers.keys():
		if not alive.has(id):
			_markers[id].queue_free()
			_markers.erase(id)


func _update_player() -> void:
	_player.position = _world_pos(World.pos)
	_path_mesh.clear_surfaces()
	if World.path.size() < 1:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_path_mesh.surface_add_vertex(_player.position + Vector3.UP * 0.6)
	for k in range(0, World.path.size(), 2):
		var c: Vector2i = World.path[k]
		_path_mesh.surface_add_vertex(_world_pos(Vector2(c) + Vector2(0.5, 0.5)) + Vector3.UP * 0.6)
	var last: Vector2i = World.path[World.path.size() - 1]
	_path_mesh.surface_add_vertex(_world_pos(Vector2(last) + Vector2(0.5, 0.5)) + Vector3.UP * 0.6)
	_path_mesh.surface_end()


## The sun follows the clock: dawn, noon, dusk and a dim blue night.
func _update_light() -> void:
	var hd := World.hours_of_day()
	var day_f := clampf(sin((hd - 6.0) / 12.0 * PI), 0.0, 1.0)
	_sun.rotation_degrees = Vector3(-10.0 - 60.0 * day_f, 30.0 + (hd - 12.0) * 6.0, 0)
	_sun.light_energy = 0.45 + 0.75 * day_f
	_sun.light_color = Color(0.7, 0.75, 1.0).lerp(Color(1, 1, 0.96), day_f)
	_env.ambient_light_color = Color(0.5, 0.55, 0.75).lerp(Color(0.8, 0.8, 0.82), day_f)
	_env.ambient_light_energy = 0.5 + 0.2 * day_f


func _update_labels() -> void:
	for id in _labels:
		var l: Label3D = _labels[id]
		var st: Dictionary = World.settlement(id)
		var known := bool(World.places[id]["known"])
		var far: float = {"village": 260.0, "town": 520.0, "city": 9999.0, "hold": 9999.0, "nest": 520.0}[st["kind"]]
		l.visible = known and _dist < far
		if known and World.is_raided(id):
			l.text = String(st["name"]) + "  (raided)"


func _update_camera() -> void:
	var k := clampf((_dist - MIN_DIST) / (MAX_DIST - MIN_DIST), 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(42.0, 72.0, sqrt(k)))
	var eye := _target + Vector3(0, sin(pitch), cos(pitch)) * _dist
	_cam.transform = Transform3D(Basis.looking_at(_target - eye), eye)


func _zoom(f: float) -> void:
	_dist = clampf(_dist * f, MIN_DIST, MAX_DIST)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _popup.visible or _logistics.visible or (_scout_panel != null and _scout_panel.visible):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.0 / 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.15)
	elif event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 1:
				_press_pos = t.position
				_dragged = false
			elif _touches.size() == 2:
				_pinch_d = _pinch_distance()
				_dragged = true
		else:
			_touches.erase(t.index)
			if _touches.is_empty() and not _dragged:
				_tap(t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var nd := _pinch_distance()
			if _pinch_d > 1.0 and nd > 1.0:
				_zoom(_pinch_d / nd)
			_pinch_d = nd
		else:
			if d.position.distance_to(_press_pos) > 14.0:
				_dragged = true
			if _dragged:
				_pan(d.relative)
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_zoom(1.0 / 1.3)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom(1.3)
			KEY_SPACE:
				_on_wait()


func _pinch_distance() -> float:
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0


func _pan(rel: Vector2) -> void:
	_follow = false
	var per_px := 2.0 * _dist * tan(deg_to_rad(_cam.fov * 0.5)) / get_viewport().get_visible_rect().size.y
	_target -= Vector3(rel.x, 0, rel.y) * per_px
	var size := Gen.SIZE * CELL
	_target.x = clampf(_target.x, 0, size)
	_target.z = clampf(_target.z, 0, size)


## Tap: what's there? A party you can see, a place you know, or just ground.
func _tap(screen: Vector2) -> void:
	var cell := _pick(screen)
	if cell.x < 0:
		return
	_chase = {}
	if World.camping:
		World.camping = false
		_push_toast("You break camp and march in the dark.")
		World.night_march_day = World.day()
	var tap := Vector2(cell) + Vector2(0.5, 0.5)
	for p in World.parties:
		if World.can_see(p) and tap.distance_to(Vector2(p["x"], p["y"])) < 3.0:
			_chase = {"id": int(p["id"])}
			_chase_t = 0.8
			World.go_to(Vector2i(int(p["x"]), int(p["y"])), {"kind": "party", "id": int(p["id"])})
			_follow = true
			return
	for st in World.gen.settlements:
		var reach: float = World.SETTLEMENT_REACH.get(st["kind"], 3.5) + 1.0
		var seen: bool = bool(World.places[int(st["id"])]["known"]) or World.explored[Gen.idx(int(st["x"]), int(st["y"]))] == 1
		if seen and tap.distance_to(Vector2(st["x"], st["y"])) < reach:
			World.go_to(Vector2i(st["x"], st["y"]), {"kind": "settlement", "id": int(st["id"])})
			_follow = true
			return
	if not World.go_to(cell):
		_push_toast("No way there.")
	_follow = true


## The cell under a screen point: march along the camera ray until it
## dips below the ground.
func _pick(screen: Vector2) -> Vector2i:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	var t := 0.0
	var g = World.gen
	while t < 4000.0:
		var p := from + dir * t
		var cx := int(p.x / CELL)
		var cy := int(p.z / CELL)
		if cx < 0 or cy < 0 or cx >= Gen.SIZE or cy >= Gen.SIZE:
			if p.y < 0.0:
				return Vector2i(-1, -1)
			t += 2.0
			continue
		var ground: float = maxf(g.h(cx, cy), Gen.SEA_LEVEL) * HS
		if p.y <= ground:
			return Vector2i(cx, cy)
		t += clampf((p.y - ground) * 0.5, 0.4, 20.0)
	return Vector2i(-1, -1)


func _on_wait() -> void:
	World.waiting = not World.waiting
	if World.waiting:
		World.stop()


# ---------------------------------------------------------------- events

func _on_day(notes: PackedStringArray) -> void:
	for n in notes:
		_push_toast(n)


func _on_arrived(g: Dictionary) -> void:
	match String(g["kind"]):
		"settlement":
			_visit(World.settlement(int(g["id"])))
		"party":
			var p := World.party_by_id(int(g["id"]))
			_chase = {}
			if not p.is_empty() and p["faction"] != "lizards":
				_meet(p)


## A popup with choices. The clock stops while it's open; `halt` also
## cancels the march (arrivals, encounters), otherwise the march resumes.
var _popup_row: HBoxContainer
var _popup_scene: Control
var _next_scene := "" # the vignette for the next pop-up (set just before _popup_open)
var _next_scene_ctx := {}


## Show a little scene of `kind` in the next pop-up.
func _scene(kind: String, c := {}) -> void:
	_next_scene = kind
	_next_scene_ctx = c


func _popup_open(title: String, text: String, buttons: Array, halt := true) -> void:
	for ch in _popup_scene.get_children():
		ch.queue_free()
	if _next_scene != "" and not _test:
		_popup_scene.add_child(Vignette.make(_next_scene, _next_scene_ctx))
		_popup_scene.custom_minimum_size = Vector2(Vignette.SIZE)
		_popup_scene.visible = true
		_popup_text.custom_minimum_size = Vector2(440, 0)
	else:
		_popup_scene.visible = false
		_popup_text.custom_minimum_size = Vector2(580, 0)
	_next_scene = ""
	_next_scene_ctx = {}
	if halt:
		World.stop()
	World.waiting = false
	_popup_title.text = title
	_popup_text.text = text
	for c in _popup_buttons.get_children():
		_popup_buttons.remove_child(c) # gone now, not at the end of the frame
		c.queue_free()
	for b in buttons:
		var btn := _button(b[0], b[1])
		btn.custom_minimum_size = Vector2(150, 58)
		_popup_buttons.add_child(btn)
	_popup.visible = true
	_center(_popup)


func _popup_close() -> void:
	_popup.visible = false
	for ch in _popup_scene.get_children():
		ch.queue_free()


## Arriving at a settlement: what it is, and what you can do there.
func _visit(st: Dictionary) -> void:
	var fac: Dictionary = Lore.FACTIONS[st["faction"]]
	var kind: String = st["kind"]
	var title := "%s, %s of %s" % [st["name"], {"village": "a village", "town": "a town", "city": "a city",
		"hold": "a hold", "nest": "a nest"}[kind], fac["short"]]
	var text := ""
	var buttons: Array = []
	var id := int(st["id"])
	if kind == "nest":
		title = "%s, a lizard nest" % st["name"]
		text = "Mounds of packed mud, a ring of bone stakes, and hundreds of them."
		if id == World.gen.stash_nest:
			text += "\n\n[color=#f0c060]Through the stakes you can see crates with the %s's mark, the ship's guns, powder kegs. Your stores are here.[/color] You will need a far bigger force to take them back." % Lore.SHIP
		buttons.append(["LEAVE", _popup_close])
		_scene("nest")
	elif World.is_raided(id):
		text = "Burned. The lizards have been here; the people who are left have nothing to sell."
		buttons.append(["LEAVE", _popup_close])
		_scene("burned")
	elif not _test:
		# Into the town itself: on foot the first time, its menu after that.
		World.stop()
		Company.visiting = id
		_go("res://scenes/town.tscn")
		return
	else:
		match kind:
			"village":
				text = "A farming village. They eye your red coats and muskets warily, but they'll sell food."
			"town":
				text = "A market town. Food and drink for sale, and talk of the war with %s." % ("Vell" if st["faction"] == "aurest" else "Aurest")
			"city":
				text = "A walled city of %s. Everything that can be bought is for sale here, except powder: nobody here has heard of it." % fac["name"]
			"hold":
				text = "A dwarf hold cut into the mountain. The dwarves look at your muskets with great interest."
		text += "\n\nWater barrels refilled. Recruiting locals comes soon."
		var prices := {"village": [10, 5], "town": [20, 9], "city": [20, 8], "hold": [20, 10]}
		var pr: Array = [prices[kind][0], Company.price(prices[kind][1])]
		buttons.append(["FOOD +%d (%d cr)" % [pr[0], pr[1]], func():
			if Company.room_for("rations") < int(pr[0]):
				_push_toast("The wagon is full.")
			elif Company.money >= int(pr[1]):
				Company.money -= int(pr[1])
				Company.stores["rations"] = int(Company.stores["rations"]) + int(pr[0])
				Company.save()
				_push_toast("Bought %d rations." % int(pr[0]))])
		if kind != "village":
			var rum_cr := Company.price(6)
			buttons.append(["RUM +10 (%d cr)" % rum_cr, func():
				if Company.room_for("rum") < 10:
					_push_toast("The wagon is full.")
				elif Company.money >= rum_cr:
					Company.money -= rum_cr
					Company.stores["rum"] = int(Company.stores["rum"]) + 10
					Company.save()
					_push_toast("Bought 10 tots of rum.")])
		var gv := Company.goods_value(kind)
		if gv > 0:
			buttons.append(["SELL LOOT (%d cr)" % gv, func():
				var got := Company.sell_goods(kind)
				_push_toast("Sold the loot for %d crowns." % got)
				_popup_close()])
		buttons.append(["REST A DAY", func():
			_popup_close()
			World.waiting = true
			_rest_until = World.hours + 24.0])
		buttons.append(["LEAVE", _popup_close])
		Company.stores["water"] = maxi(int(Company.stores["water"]), Company.WATER_CART)
		Company.stores["foul"] = false
	_popup_open(title, text, buttons)


var _rest_until := -1.0


## Meeting a party that isn't hostile.
func _meet(p: Dictionary) -> void:
	var text := ""
	match String(p["kind"]):
		"caravan":
			text = "Merchants with mules and carts. They'll trade once you have something they want."
		"patrol":
			text = "Soldiers of %s. They watch you closely: strangers in red coats, armed with something they've never seen." % Lore.FACTIONS[p["faction"]]["name"]
		"villagers":
			text = "Country folk on their way to market. They tell you the lizards have been raiding to the south."
		"traders":
			text = "Dwarf traders with pack ponies loaded with iron. They ask, very politely, how your guns work."
	_scene({"caravan": "caravan", "patrol": "patrol", "villagers": "villagers", "traders": "traders",
		"deserters": "deserters"}.get(String(p["kind"]), "road"), {"faction": p.get("faction", "vell")})
	_popup_open(World.party_name(p), text, [["LEAVE", _popup_close]])


## 18:00 on the march.
func _on_dusk() -> void:
	_scene("dusk", {"time": "dusk"})
	_popup_open("Dusk", "The light is going. Make camp and sleep until dawn, or march on through the night: slower, half blind, and the men won't thank you.",
		[["MAKE CAMP", func():
			_popup_close()
			World.make_camp()], ["MARCH ON IN THE DARK", func():
			_popup_close()
			World.march_through_night()]], false)


## Something on the road (events.gd): show it with its choices.
func _on_event(ev: Dictionary) -> void:
	var buttons: Array = []
	for o in ev["options"]:
		buttons.append([o[0], _event_choice.bind(ev, o[1])])
	_scene(_event_scene(String(ev["id"])))
	_popup_open(ev["title"], ev["text"], buttons, false)


## The little scene for an event on the road.
static func _event_scene(id: String) -> String:
	return {"wreckage": "wreck"}.get(id, id)


func _event_choice(ev: Dictionary, key: String) -> void:
	_popup_close()
	var r: Dictionary = World.events.resolve(World, ev["id"], key)
	if r.has("fight"):
		World.stop()
		_on_encounter(r["fight"])
		return
	if String(r["text"]) != "":
		_scene(_event_scene(String(ev["id"])))
		_popup_open(ev["title"], r["text"], [["CARRY ON", _popup_close]], false)


## Scouts: pick a direction and how far.
var _scout_panel: PanelContainer
var _scout_info: Label
var _scout_far := false
var _scout_shade: ColorRect # dims the map; tapping it closes the panel


func _open_scouts() -> void:
	if _scout_panel == null:
		_build_scout_panel()
	_refresh_scouts()
	_scout_shade.visible = true
	_scout_panel.visible = true
	_center(_scout_panel)


func _close_scouts() -> void:
	_scout_panel.visible = false
	_scout_shade.visible = false


func _build_scout_panel() -> void:
	_scout_shade = ColorRect.new()
	_scout_shade.color = Color(0, 0, 0, 0.45)
	_scout_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scout_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_scout_shade.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			_close_scouts())
	_popup.get_parent().add_child(_scout_shade)
	_scout_panel = _panel(Color(UI.WOOL, 0.97))
	_scout_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scout_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scout_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_popup.get_parent().add_child(_scout_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_scout_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("SEND SCOUTS", 26, Color(0.95, 0.8, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := _button("✕", _close_scouts)
	x.custom_minimum_size = Vector2(58, 58)
	head.add_child(x)
	_scout_info = _label("", 18, Color.WHITE)
	_scout_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scout_info.custom_minimum_size = Vector2(560, 0)
	v.add_child(_scout_info)
	var range_row := HBoxContainer.new()
	range_row.add_theme_constant_override("separation", 10)
	v.add_child(range_row)
	var near := _button("NEAR: 1 man, a day", func():
		_scout_far = false
		_refresh_scouts())
	var far := _button("FAR: 2 men, two days", func():
		_scout_far = true
		_refresh_scouts())
	near.name = "near"
	far.name = "far"
	range_row.add_child(near)
	range_row.add_child(far)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var dirs := [["NW", Vector2(-1, -1)], ["N", Vector2(0, -1)], ["NE", Vector2(1, -1)],
		["W", Vector2(-1, 0)], ["", Vector2.ZERO], ["E", Vector2(1, 0)],
		["SW", Vector2(-1, 1)], ["S", Vector2(0, 1)], ["SE", Vector2(1, 1)]]
	for d in dirs:
		if d[0] == "":
			var mid := _label("PICK A\nDIRECTION", 14, Color(0.72, 0.74, 0.8))
			mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(mid)
		else:
			grid.add_child(_button(d[0], _send_scouts.bind(d[1])))
	var cancel := _button("CANCEL: KEEP THEM HERE", _close_scouts)
	cancel.custom_minimum_size.y = 58
	v.add_child(cancel)
	_scout_panel.visible = false
	_scout_shade.visible = false


func _refresh_scouts() -> void:
	var cands := World.scout_candidates()
	var n := 2 if _scout_far else 1
	var t := "Scouts ride out, look around, and come back to the company wherever it is, with word of what they found: towns, roads, warbands. Some never come back, more often in the lizards' country.\n\n"
	if cands.size() < n + 2:
		t += "Not enough fit men to spare."
	else:
		var names: Array = cands.slice(0, n).map(func(m): return Company.surname_title(m))
		t += "Going: %s." % ", ".join(names)
	for sc in World.scouts:
		t += "\nOut now: %s, back around day %d." % [", ".join(sc["names"]), 1 + int(float(sc["back"]) / 24.0)]
	_scout_info.text = t
	(_scout_panel.find_child("near", true, false) as Button).modulate = Color(1, 0.85, 0.4) if not _scout_far else Color.WHITE
	(_scout_panel.find_child("far", true, false) as Button).modulate = Color(1, 0.85, 0.4) if _scout_far else Color.WHITE


func _send_scouts(dir: Vector2) -> void:
	var sc := World.send_scouts(dir, _scout_far)
	_close_scouts()
	if sc.is_empty():
		_push_toast("Not enough fit men to spare.")
	else:
		_push_toast("%s set out." % ", ".join(sc["names"]))


func _on_scouts_back(r: Dictionary) -> void:
	var t := ""
	var names: Array = r["names"]
	if r["lost"].size() == names.size():
		t = "%s never came back. You wait as long as you dare." % ", ".join(names)
		_scene("scouts_lost")
		_popup_open("The scouts are lost", t, [["CARRY ON", _popup_close]], false)
		return
	if r["lost"].size() > 0:
		t += "Only one comes back, wounded. %s did not.\n\n" % ", ".join(r["lost"])
	else:
		t += "%s report:\n\n" % ", ".join(names)
	if r["terrain"] != "":
		t += "Mostly %s out there.\n" % r["terrain"]
	t += ("They found: " + ", ".join(r["found"]) + ".\n") if r["found"].size() > 0 else "No towns or villages.\n"
	t += ("They saw: " + ", ".join(r["parties"]) + ".") if r["parties"].size() > 0 else "Nobody on the move."
	_scene("scouts_back", {"n": names.size() - (r["lost"] as Array).size()})
	_popup_open("The scouts are back", t, [["CARRY ON", _popup_close]], false)


## A lizard warband has caught you.
func _on_encounter(p: Dictionary) -> void:
	if World.camping:
		_camp_attacked(p)
		return
	var c := World.cell()
	var cover: bool = World.gen.t(c.x, c.y) in [T.FOREST, T.SWAMP]
	var chance := clampf(0.3 + (0.25 if cover else 0.0) + (World.party_pace() - 0.85) + Company.Officer.slip_bonus(), 0.1, 0.85)
	var where := "in the trees" if cover else "in the open"
	# Seen coming, there's time to form up as planned; out of nowhere, there isn't.
	var ambush := World.hours - float(p.get("seen_at", -99.0)) > 1.5
	var text := "They've caught up with you %s. %d of them against %d fit men." % [where, int(p["size"]), Company.fit_men().size()]
	if ambush:
		text += "\n\n[color=#f08060]AMBUSH! No time to form up: the men will be scattered.[/color]"
	else:
		text += "\n\nYou saw them coming: there's time to form up (PLAN to change the formation)."
	text += "\n\nSlip away? About %d%% chance; fail and you fight anyway, caught off guard." % int(chance * 100)
	var buttons: Array = []
	if not ambush:
		buttons.append(["PLAN", _plan_fight.bind(p)])
	buttons.append(["FIGHT", _fight.bind(p, ambush)])
	buttons.append(["SLIP AWAY", _slip.bind(p, chance)])
	_scene("ambush" if ambush else "warband")
	_popup_open("%s!" % World.party_name(p), text, buttons)


## Attacked in the night camp. Two men stand watch; whether they see the
## lizards coming depends on their eyes (aim), how alert they are (not
## hungry, sick or worn out), the cover the lizards creep through, and luck.
## Seen: the alarm gets everyone up in time. Not seen: you wake with the
## lizards already among the bedrolls.
func _camp_attacked(p: Dictionary) -> void:
	World.camping = false
	var c := World.cell()
	var t: int = World.gen.t(c.x, c.y)
	var fit: Array = Company.fit_men()
	fit.shuffle()
	var watch: Array = fit.slice(0, mini(2, fit.size()))
	var see := 0.0
	for m in watch:
		var eye := 0.32 + 0.06 * (Men.attr(m, "aim") - 5) + 0.02 * (Men.attr(m, "fitness") - 5)
		if int(m.get("hunger", 0)) > 0 or int(m.get("thirst", 0)) > 0 or int(m.get("sick", 0)) > 0:
			eye -= 0.1
		see = 1.0 - (1.0 - see) * (1.0 - clampf(eye, 0.05, 0.85))
	if t in [T.FOREST, T.SWAMP]:
		see -= 0.2 # they creep right up through the trees
	elif t in [T.HILLS, T.PLAINS, T.BEACH]:
		see += 0.08
	see = clampf(see + Company.Officer.watch_bonus(), 0.1, 0.92) # your Tactics: a better-kept watch
	var spotted := randf() < see
	var names: Array = watch.map(func(m): return Company.title(m))
	var ids: Array = watch.map(func(m): return int(m["id"]))
	Company.next_battle = {"enemy": int(p["size"]), "terrain": t, "party": int(p["id"]), "ambush": false,
		"enemy_kind": "lizards", "camp": true, "spotted": spotted, "night": true, "watch": ids}
	Company.results_unseen = false
	var text := ""
	var buttons: Array = []
	if spotted:
		text = "Night, by the fire. %s on watch hear something in the dark, then see the eyes catch the firelight, and raise the alarm. The men are throwing off their blankets and reaching for their muskets.\n\n%d of them against %d fit men." % [
			" and ".join(names), int(p["size"]), fit.size()]
		text += "\n\nAbandon the camp and slip away in the dark? About %d%% chance; fail and you fight anyway, worse placed." % int(100 * (0.35 + Company.Officer.slip_bonus()))
		buttons.append(["STAND TO!", _camp_fight.bind(p)])
		buttons.append(["SLIP AWAY", _slip.bind(p, 0.35 + Company.Officer.slip_bonus())])
		_scene("camp_attack", {"time": "night"})
		_popup_open("The watch has seen them!", text, buttons)
	else:
		text = "Night. %s on watch never saw them come. You wake to screaming: they're already in among the bedrolls, %d of them, and your men are still asleep." % [
			" and ".join(names), int(p["size"])]
		buttons.append(["UP! TO ARMS!", _camp_fight.bind(p)])
		_scene("camp_attack", {"time": "night"})
		_popup_open("They're in the camp!", text, buttons)


func _camp_fight(p: Dictionary) -> void:
	_popup_close()
	if _test:
		print("  MAPTEST: camp attacked by ", World.party_name(p), " (counted as won)", " spotted" if Company.next_battle.get("spotted") else " asleep")
		World.remove_party(int(p["id"]))
		return
	_go(BATTLE)


## Look over the battle plan before this fight: the plan screen's FIGHT! button starts it.
func _plan_fight(p: Dictionary) -> void:
	_set_battle(p, false)
	Company.next_battle["planning"] = true
	_go(PLAN)


func _set_battle(p: Dictionary, ambush: bool) -> void:
	var c := World.cell()
	Company.next_battle = {"enemy": int(p["size"]), "terrain": World.gen.t(c.x, c.y), "party": int(p["id"]),
		"ambush": ambush, "enemy_kind": "lizards"}
	Company.results_unseen = false


func _fight(p: Dictionary, ambush := false) -> void:
	if _test:
		print("  MAPTEST: battle against ", World.party_name(p), " (counted as won)", " ambush" if ambush else "")
		_popup_close()
		World.remove_party(int(p["id"]))
		return
	_set_battle(p, ambush)
	_go(BATTLE)


func _slip(p: Dictionary, chance: float) -> void:
	_popup_close()
	if randf() < chance:
		# Away, and they lose you for a few hours.
		var away := (World.pos - Vector2(p["x"], p["y"])).normalized()
		World.pos += away * 3.0
		p["wait"] = 4.0
		p["path"] = []
		_push_toast("You slip away from them.")
	else:
		_push_toast("They're too quick!")
		_fight(p, true)


## Back from a battle the map started: a won fight destroys the warband; a
## lost one leaves it, and you fall back.
func _apply_battle_result() -> void:
	if Company.next_battle.is_empty():
		return
	var id := int(Company.next_battle["party"])
	var r: Dictionary = Company.last_result
	var p := World.party_by_id(id)
	if bool(r.get("won", false)):
		World.remove_party(id)
		_push_toast("The warband is destroyed.")
	elif not p.is_empty():
		var away := (World.pos - Vector2(p["x"], p["y"])).normalized()
		World.pos += away * 5.0
		p["wait"] = 6.0
		_push_toast("You fall back, leaving the field to them.")
	Company.next_battle = {}
	Company.save()
	World.save()


# ---------------------------------------------------------------- headless test

## `-- --maptest`: march to the nearest village, buy food, rest, then walk
## into the lizard lands and report what happens.
func _run_test(delta: float) -> void:
	_test_t += delta
	if _test_t < 0.2:
		return
	if _popup.visible:
		print("  POPUP: ", _popup_title.text, "  |  ", _popup_text.text.substr(0, 90).replace("\n", " "))
		var n := _popup_buttons.get_child_count()
		var last: Button = _popup_buttons.get_child(n - 1)
		if _popup_title.text.ends_with("!") and n > 1:
			print("  (would fight; slipping away for the test)")
			_popup_buttons.get_child(n - 1).emit_signal("pressed") # slip away
		elif last.text == "LEAVE" and n > 2:
			_popup_buttons.get_child(0).emit_signal("pressed") # buy food once
			last.emit_signal("pressed")
		else:
			_popup_buttons.get_child(0).emit_signal("pressed") # camp / the first choice / carry on
		return
	if int(get_meta("scouted", 0)) == 0 and _test_t > 1.0:
		set_meta("scouted", 1)
		var sc := World.send_scouts(Vector2(1, -1), true)
		print("MAPTEST: scouts out: ", sc.get("names", []))
	if not World.moving() and not World.waiting:
		var stage := int(get_meta("stage", 0))
		set_meta("stage", stage + 1)
		match stage:
			0:
				var best = null
				for st in World.gen.settlements:
					if st["kind"] == "village" and st["faction"] != "dwarves":
						if best == null or Vector2(st["x"], st["y"]).distance_to(World.pos) < Vector2(best["x"], best["y"]).distance_to(World.pos):
							best = st
				print("MAPTEST: march to ", best["name"], " ok ", World.go_to(Vector2i(best["x"], best["y"]), {"kind": "settlement", "id": int(best["id"])}))
			1, 2, 3:
				var nest: Dictionary = World.settlement(World.gen.stash_nest)
				print("MAPTEST: ", World.clock(), " at ", World.cell(), " -> stash nest ", nest["name"])
				World.go_to(Vector2i(nest["x"], nest["y"]), {"kind": "settlement", "id": int(nest["id"])})
			_:
				var kinds := {}
				for pp in World.parties:
					kinds[pp["kind"]] = kinds.get(pp["kind"], 0) + 1
				print("  parties: ", kinds, " stores ", Company.stores)
				print("MAPTEST END ", World.clock(), " men ", Company.roster.size(), " parties ", World.parties.size(),
					" explored ", Array(World.explored).count(1), " fps ", Engine.get_frames_per_second())
				get_tree().quit()
