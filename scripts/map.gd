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
const Econ := preload("res://scripts/economy.gd")
const UI := preload("res://scripts/ui.gd")

const Gen := preload("res://scripts/world_gen.gd")
const SoundFactory := preload("res://scripts/sound_factory.gd")
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
var _tracks_mm: MultiMesh # the tracks you've seen (World.tracks)
var _sky := {} # storm id -> Node3D: its clouds and its rain (weather.gd)
var _bolt: Array = [] # the lightning's segments
var _bolt_t := 0.0
var _bolt_cd := 2.0
var _wx_rain := 0.0
var _wx_fog := 0.0
var _wx_heat := 0.0
var _flash: OmniLight3D
var _flash_e := 0.0
var _tracks_t := 0.0
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
		await Loading.step(f[1] - 0.08, Lang.t("Charting the roads and the march..."))
	World.ensure()
	await Loading.step(f[1], Lang.t("Drawing the land..."))
	_shader = Shader.new()
	_shader.code = MAP_SHADER
	_build_fog()
	_mat = _material(false, Color.WHITE)
	_build_env()
	_build_terrain()
	await Loading.step(f[2], Lang.t("Rivers, lakes and the sea..."))
	_build_sea()
	await Loading.step(f[3], Lang.t("Planting the forests..."))
	_build_trees()
	await Loading.step(f[4], Lang.t("Roads, bridges, villages and towns..."))
	_build_bridges()
	_build_settlements()
	_build_player()
	_build_hud()
	World.day_passed.connect(_on_day)
	World.news.connect(func(t): _push_toast(t))
	World.encounter.connect(_on_encounter)
	World.fight_near.connect(_on_fight_near)
	World.arrived.connect(_on_arrived)
	World.dusk.connect(_on_dusk)
	World.dawn.connect(func(): _push_toast("Dawn. The company breaks camp." + (" On the march again." if World.moving() else "")))
	World.event.connect(_on_event)
	World.scouts_back.connect(_on_scouts_back)
	World.revealed.connect(func(): _rebuild_fog())
	Music.set_context("camp" if World.camping else "map")
	_target = _world_pos(World.pos)
	_apply_battle_result()
	await Loading.step(f[5], Lang.t("Fog over the unknown..."))
	_update_fog(true)
	_update_camera()
	if World.pending_rest > 0.0:
		# Resting in the town you just left.
		World.waiting = true
		_rest_until = World.hours + World.pending_rest
		World.pending_rest = 0.0
	if World.pending_note != "":
		_push_toast(World.pending_note)
		World.pending_note = ""
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
	_build_resources()
	_refresh_resource_labels()
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


## The places that give what you need (world.gd RESOURCES): a small model of
## each, and its name once you've seen it.
var _res_labels := {} # resource id -> Label3D


func _build_resources() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = World.seed + 11
	for r in World.gen.resources:
		var c := _world_pos(Vector2(r["x"], r["y"]) + Vector2(0.5, 0.5))
		match String(r["kind"]):
			"saltpetre":
				_box(c + Vector3(0, 2.0, 0), Vector3(7, 4, 5), Color(0.42, 0.4, 0.38), 0.3)
				_box(c + Vector3(0.5, 1.2, 2.6), Vector3(2.6, 2.4, 0.3), Color(0.08, 0.07, 0.07), 0.3) # the cave mouth
				_box(c + Vector3(-2.0, 3.6, 1.5), Vector3(2.0, 0.4, 1.6), Color(0.92, 0.92, 0.88), 0.3)
			"sulphur":
				_box(c + Vector3(0, 0.15, 0), Vector3(5, 0.3, 4), Color(0.85, 0.78, 0.2), 0.5)
				_box(c + Vector3(0, 0.3, 0), Vector3(2.6, 0.2, 2.0), Color(0.45, 0.62, 0.55), 0.5)
				for k in 3:
					_box(c + Vector3(rng.randf_range(-2, 2), 0.6, rng.randf_range(-2, 2)), Vector3(0.8, 1.0, 0.8), Color(0.9, 0.82, 0.25), rng.randf() * TAU)
			"charcoal":
				_box(c + Vector3(0, 1.0, 0), Vector3(4, 2, 4), Color(0.15, 0.13, 0.11), 0.7) # the clamp under turf
				for k in 4:
					_box(c + Vector3(3.5, 0.3 + k * 0.45, -1.5), Vector3(3.0, 0.4, 0.4), Color(0.4, 0.27, 0.15), 0.2)
			"lead":
				for k in 4:
					_box(c + Vector3(rng.randf_range(-3, 3), 1.0, rng.randf_range(-3, 3)), Vector3(2.4, 2.0, 2.0), Color(0.36, 0.38, 0.42), rng.randf() * TAU, 0.2)
			"game":
				for k in 3:
					var a := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
					_box(c + a + Vector3(0, 1.0, 0), Vector3(1.6, 0.8, 0.6), Color(0.48, 0.34, 0.2), rng.randf() * TAU)
					_box(c + a + Vector3(0.7, 1.6, 0), Vector3(0.4, 0.8, 0.3), Color(0.45, 0.32, 0.19))
			"fish":
				_box(c + Vector3(0, 0.3, 0), Vector3(1.4, 0.5, 4.0), Color(0.4, 0.28, 0.16), 0.6) # a beached boat
				_box(c + Vector3(2.5, 1.0, 0), Vector3(0.15, 2.0, 0.15), Color(0.35, 0.25, 0.15))
				_box(c + Vector3(2.5, 1.3, 1.2), Vector3(0.05, 1.2, 2.4), Color(0.75, 0.7, 0.55)) # the net
			"farm":
				for k in 3:
					_box(c + Vector3(-3.0 + k * 3.0, 0.2, 0), Vector3(2.6, 0.4, 6.0), Color(0.82, 0.72, 0.32) if k != 1 else Color(0.5, 0.6, 0.25), 0.15)
				_box(c + Vector3(4.2, 0.9, -2.0), Vector3(1.6, 1.8, 1.4), Color(0.55, 0.42, 0.28))
				_box(c + Vector3(4.2, 2.0, -2.0), Vector3(1.8, 0.5, 1.6), Color(0.72, 0.6, 0.3))
			"spring":
				_box(c + Vector3(0, 0.12, 0), Vector3(3.2, 0.24, 3.2), Color(0.35, 0.6, 0.85), 0.8)
				for k in 5:
					var a2 := TAU * k / 5.0
					_box(c + Vector3(cos(a2) * 2.0, 0.3, sin(a2) * 2.0), Vector3(0.8, 0.6, 0.8), Color(0.55, 0.53, 0.5), a2)
		var l := Label3D.new()
		l.text = Lang.t(World.RESOURCES[r["kind"]]["name"])
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 20
		l.font = UI.display_font()
		l.outline_size = 8
		l.modulate = Color(0.75, 0.9, 1.0)
		l.no_depth_test = true
		l.position = c + Vector3(0, 6.0, 0)
		l.visible = false
		add_child(l)
		_res_labels[int(r["id"])] = l


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
	var what: String = {"village": "", "town": "", "city": "", "hold": Lang.t("  (dwarf hold)"), "nest": Lang.t("  (lizard nest)")}[kind]
	if kind == "nest" and World.nest_destroyed(int(st["id"])):
		what = Lang.t("  (burned)")
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
	_player = _figure(preload("res://scripts/colours.gd").coat(), Color(0.92, 0.92, 0.95), 1.3, true)
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
	_build_tracks()


## Tracks: a flat arrow on the ground for each one you've seen, pointing
## the way they went, in the colour of whoever made it, fading with age.
func _build_tracks() -> void:
	var am := ArrayMesh.new()
	var v := PackedVector3Array([
		Vector3(0, 0, -0.9), Vector3(0.55, 0, 0.2), Vector3(0, 0, -0.25),
		Vector3(0, 0, -0.9), Vector3(0, 0, -0.25), Vector3(-0.55, 0, 0.2),
		Vector3(0, 0, -0.25), Vector3(0.55, 0, 0.2), Vector3(0.2, 0, 0.45),
		Vector3(0, 0, -0.25), Vector3(-0.2, 0, 0.45), Vector3(-0.55, 0, 0.2)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.surface_set_material(0, mat)
	_tracks_mm = MultiMesh.new()
	_tracks_mm.transform_format = MultiMesh.TRANSFORM_3D
	_tracks_mm.use_colors = true
	_tracks_mm.mesh = am
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _tracks_mm
	add_child(inst)


static func track_colour(t: Dictionary) -> Color:
	if t["f"] == "lizards":
		return Color(0.95, 0.25, 0.18) if t["k"] == "warband" else Color(0.95, 0.55, 0.2)
	if t["k"] in ["caravan", "traders", "villagers", "labourers", "refugees"]:
		return Color(0.85, 0.8, 0.6)
	var fac: Dictionary = Lore.FACTIONS.get(t["f"], {})
	return fac.get("color", Color(0.8, 0.8, 0.85))


func _update_tracks(delta: float) -> void:
	_tracks_t -= delta
	if _tracks_t > 0.0:
		return
	_tracks_t = 0.5
	var list: Array = World.seen_tracks()
	_tracks_mm.instance_count = list.size()
	for i in list.size():
		var t: Dictionary = list[i]
		var at := _world_pos(Vector2(float(t["x"]), float(t["y"]))) + Vector3.UP * 0.5
		var yaw := atan2(-float(t["dx"]), -float(t["dy"]))
		_tracks_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 1.6), at))
		var c := track_colour(t)
		c.a = clampf(1.0 - (World.hours - float(t["h"])) / World.TRACK_LIFE, 0.0, 1.0) * 0.8 + 0.12
		_tracks_mm.set_instance_color(i, c)


# ---------------------------------------------------------------- weather

const CLOUD_UP := 26.0 # how high the cloud base rides over the ground

func _storm_node(s: Dictionary) -> Node3D:
	var n := Node3D.new()
	var clouds := Node3D.new()
	clouds.name = "clouds"
	n.add_child(clouds)
	var mat := StandardMaterial3D.new()
	var dark: bool = s["kind"] == "thunder"
	mat.albedo_color = Color(0.24, 0.25, 0.3, 0.0) if dark else Color(0.36, 0.38, 0.43, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	clouds.set_meta("mat", mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["id"]) * 7919
	# A dozen flattened puffs, for a storm 10 cells across (scaled to size).
	for k in 12:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 12
		sm.rings = 6
		var rad := rng.randf_range(5.0, 9.0)
		sm.radius = rad
		sm.height = rad * 2.0
		m.mesh = sm
		m.material_override = mat
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 11.0)
		m.position = Vector3(cos(a) * d, rng.randf_range(0.0, 4.0), sin(a) * d)
		m.scale = Vector3(1.0, rng.randf_range(0.22, 0.35), 1.0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clouds.add_child(m)
	# The rain: streaks falling from the cloud base, leaning with the wind.
	var rain := GPUParticles3D.new()
	rain.name = "rain"
	rain.amount = 700
	rain.lifetime = 0.55
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 80, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 0.5, 16)
	var wd: Vector2 = World.weather.wind
	pm.direction = Vector3(wd.x * 0.25, -1.0, wd.y * 0.25).normalized()
	pm.spread = 2.0
	pm.initial_velocity_min = 48.0
	pm.initial_velocity_max = 56.0
	pm.gravity = Vector3.ZERO
	rain.process_material = pm
	var streak := BoxMesh.new()
	streak.size = Vector3(0.07, 2.4, 0.07)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.72, 0.78, 0.9, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = smat
	rain.draw_pass_1 = streak
	n.add_child(rain)
	add_child(n)
	return n


func _build_bolt() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.95, 1.0)
	for k in 7:
		var m := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.45, 0.45, 1.0)
		m.mesh = cm
		m.material_override = mat
		m.visible = false
		add_child(m)
		_bolt.append(m)
	_flash = OmniLight3D.new()
	_flash.omni_range = 160.0
	_flash.light_color = Color(0.85, 0.9, 1.0)
	_flash.light_energy = 0.0
	add_child(_flash)


func _update_weather(delta: float) -> void:
	var wx = World.weather
	if wx == null:
		return
	if _bolt.is_empty():
		_build_bolt()
	var fade := clampf((_dist - 25.0) / 70.0, 0.0, 1.0) # (zoomed right in, you're under the cloud)
	var alive := {}
	var strike: Dictionary = {}
	for s in wx.storms:
		var id := int(s["id"])
		alive[id] = true
		var n: Node3D = _sky.get(id, null)
		if n == null:
			n = _storm_node(s)
			_sky[id] = n
		var at := Vector2(float(s["x"]), float(s["y"]))
		var ground := _world_pos(at)
		var base_y := maxf(ground.y, Gen.SEA_LEVEL * HS) + CLOUD_UP
		n.position = n.position.lerp(Vector3(at.x * CELL, base_y, at.y * CELL), 1.0 if n.position == Vector3.ZERO else 1.0 - exp(-3.0 * delta))
		var size := float(s["r"]) * CELL / 11.0
		var clouds := n.get_node("clouds") as Node3D
		clouds.scale = Vector3(size, 1.0, size)
		var str_s := float(s["s"])
		var mat: StandardMaterial3D = clouds.get_meta("mat")
		mat.albedo_color.a = clampf(str_s * 0.8, 0.0, 0.62) * fade
		var rain := n.get_node("rain") as GPUParticles3D
		(rain.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(size * 9.0, 0.5, size * 9.0)
		rain.amount_ratio = clampf(str_s, 0.0, 1.0)
		rain.emitting = str_s > 0.15 and _dist < 520.0
		if str_s > 0.75 and strike.is_empty() and Vector2(_target.x, _target.z).distance_to(Vector2(at.x * CELL, at.y * CELL)) < _dist * 1.6 + 60.0:
			strike = s
	for id in _sky.keys():
		if not alive.has(id):
			(_sky[id] as Node3D).queue_free()
			_sky.erase(id)
	# Lightning, now and then, from the strongest storm in view.
	_bolt_t -= delta
	if _bolt_t <= 0.0:
		for b in _bolt:
			(b as MeshInstance3D).visible = false
	_flash_e = maxf(0.0, _flash_e - delta * 14.0)
	_flash.light_energy = _flash_e
	if not strike.is_empty():
		_bolt_cd -= delta
		if _bolt_cd <= 0.0:
			_bolt_cd = randf_range(2.5, 8.0)
			_lightning(strike)


func _lightning(s: Dictionary) -> void:
	var r := float(s["r"]) * 0.6
	var at := Vector2(float(s["x"]), float(s["y"])) + Vector2(randf_range(-r, r), randf_range(-r, r))
	var ground := _world_pos(at)
	var top := Vector3(ground.x, maxf(ground.y, Gen.SEA_LEVEL * HS) + CLOUD_UP, ground.z)
	var pts: Array = [top]
	for k in range(1, _bolt.size()):
		var f := float(k) / _bolt.size()
		pts.append(top.lerp(ground, f) + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)))
	pts.append(ground)
	for k in _bolt.size():
		var m: MeshInstance3D = _bolt[k]
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		m.transform = Transform3D(Basis.looking_at(b - a, Vector3.RIGHT).scaled(Vector3(1, 1, len)), mid)
		m.visible = true
	_bolt_t = 0.13
	_flash.position = top
	_flash_e = 7.0
	# The thunder, after the flash (further off, later and fainter).
	var d := Vector2(_target.x, _target.z).distance_to(Vector2(ground.x, ground.z))
	var snd: Dictionary = SoundFactory.cached()
	if snd.has("thunder"):
		var p := AudioStreamPlayer.new()
		p.stream = snd["thunder"]
		p.volume_db = clampf(-4.0 - d / 25.0, -30.0, -4.0)
		p.pitch_scale = randf_range(0.8, 1.05)
		add_child(p)
		p.finished.connect(p.queue_free)
		get_tree().create_timer(clampf(d / 120.0, 0.2, 3.0)).timeout.connect(p.play)


## A party on the map: a little group of figures and a banner.
func _figure(body: Color, banner: Color, scale_f: float, yours := false) -> Node3D:
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
	if yours:
		# Your own colours, as you made them.
		var C := preload("res://scripts/colours.gd")
		fmat.albedo_color = Color.WHITE
		fmat.albedo_texture = C.flag_texture(C.flag(), 30, 20)
		fmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
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
	var fac: Dictionary = Lore.FACTIONS.get(p["faction"], {"color": preload("res://scripts/colours.gd").flag()["field"]}) # ("ours": your work party)
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
	# The day's feast, in its liturgical colour (tap the panel for the calendar).
	_feast_l = _label("", 16, Color.WHITE)
	tv.add_child(_feast_l)
	top.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_open_calendar())
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
	_toast.position.y = 200
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size = Vector2(760, 0)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_toast)

	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.position = Vector2(-170, 12)
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	for spec in [[Lang.t("YOU"), func():
				get_tree().set_meta("officer_back", "res://scenes/map.tscn")
				_go("res://scenes/officer.tscn")],
			[Lang.t("COMPANY"), _go.bind(COMPANY_SCREEN)], [Lang.t("PLAN"), _go.bind(PLAN)], [Lang.t("WAGON"), func(): _logistics.open()], [Lang.t("CRAFT"), _open_craft], [Lang.t("SCOUTS"), _open_scouts], [Lang.t("LORDS"), _show_lords],
			[Lang.t("CAMP"), _go.bind(CAMP)], [Lang.t("MENU"), _go.bind(MENU)]]:
		right.add_child(_button(spec[0], spec[1]))
	var br := HBoxContainer.new()
	br.anchor_left = 1.0
	br.anchor_right = 1.0
	br.anchor_top = 1.0
	br.anchor_bottom = 1.0
	br.position = Vector2(-540, -76)
	br.add_theme_constant_override("separation", 8)
	root.add_child(br)
	_speed_btn = _button("▶ ×1", func():
		World.time_speed = {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}.get(World.time_speed, 1.0)
		_speed_btn.text = "▶ ×%d" % int(World.time_speed))
	br.add_child(_speed_btn)
	_wait_btn = _button(Lang.t("WAIT"), _on_wait)
	br.add_child(_wait_btn)
	br.add_child(_button(Lang.t("CENTRE"), func(): _follow = true))
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
	MusicBar.attach(root, Vector2(12, 200))


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


## A tent and a fire at every site where you've left a work party.
var _tents := {} # resource id -> Node3D


func _refresh_resource_labels() -> void:
	for rid in _tents.keys():
		if not Company.posts.has(str(rid)):
			_tents[rid].queue_free()
			_tents.erase(rid)
	for key in Company.posts:
		var rid := int(key)
		if _tents.has(rid):
			continue
		var r := World.resource(rid)
		if r.is_empty():
			continue
		var n := Node3D.new()
		n.position = _world_pos(Vector2(r["x"], r["y"]) + Vector2(0.5, 0.5)) + Vector3(-4.5, 0, 3.5)
		add_child(n)
		var canvas := StandardMaterial3D.new()
		canvas.albedo_color = Color(0.86, 0.82, 0.7)
		var pm := PrismMesh.new()
		pm.size = Vector3(3.2, 2.2, 3.6)
		pm.material = canvas
		var tent := MeshInstance3D.new()
		tent.mesh = pm
		tent.position = Vector3(0, 1.1, 0)
		n.add_child(tent)
		var fire := StandardMaterial3D.new()
		fire.albedo_color = Color(1.0, 0.55, 0.15)
		fire.emission_enabled = true
		fire.emission = Color(1.0, 0.5, 0.1)
		fire.emission_energy_multiplier = 2.0
		var fm := BoxMesh.new()
		fm.size = Vector3(0.7, 0.5, 0.7)
		fm.material = fire
		var f := MeshInstance3D.new()
		f.mesh = fm
		f.position = Vector3(2.6, 0.25, 0.4)
		n.add_child(f)
		var flag := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.5, 1.0)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_texture = preload("res://scripts/colours.gd").flag_texture(preload("res://scripts/colours.gd").flag())
		fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		qm.material = fmat
		flag.mesh = qm
		flag.position = Vector3(-0.9, 3.6, 0)
		n.add_child(flag)
		var pole := BoxMesh.new()
		pole.size = Vector3(0.1, 3.8, 0.1)
		var pl := MeshInstance3D.new()
		pl.mesh = pole
		pl.position = Vector3(-1.7, 1.9, 0)
		n.add_child(pl)
		_tents[rid] = n


## Put a panel in the middle of the screen once it knows its size.
func _center(c: Control) -> void:
	c.reset_size()
	await get_tree().process_frame
	c.reset_size()
	c.position = (get_viewport().get_visible_rect().size - c.size) * 0.5


# ---------------------------------------------------------------- the calendar

const Calendar := preload("res://scripts/calendar.gd")
var _feast_l: Label
var _feast_day := -1
var _speed_btn: Button
var _cal_panel: PanelContainer
var _cal_box: VBoxContainer


## The Church's calendar: today and the weeks ahead, each day with its
## celebration in its colour (feasts of the I and II class picked out).
func _open_calendar() -> void:
	if _cal_panel == null:
		_cal_panel = _panel(Color(UI.WOOL, 0.98))
		_cal_panel.custom_minimum_size = Vector2(760, 0)
		_popup.get_parent().add_child(_cal_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_cal_panel.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		var t := _label(Lang.t("THE CALENDAR"), 26, Color(0.95, 0.8, 0.45))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		top.add_child(_button(Lang.t("CLOSE"), func(): _cal_panel.visible = false))
		var sc := UI.scroll()
		sc.custom_minimum_size = Vector2(740, 500)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		_cal_box = VBoxContainer.new()
		_cal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cal_box.add_theme_constant_override("separation", 4)
		sc.add_child(_cal_box)
	for c in _cal_box.get_children():
		c.queue_free()
	var today: int = World.day() - 1
	for k in 28:
		var gd := today + k
		var c: Dictionary = Calendar.of_day(gd)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_cal_box.add_child(row)
		var sw := ColorRect.new()
		sw.color = Calendar.cloth(String(c["color"]))
		sw.custom_minimum_size = Vector2(14, 40)
		row.add_child(sw)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var big: bool = c["cls"] in ["I", "II"]
		col.add_child(_label(("▸ " if k == 0 else "") + Calendar.short_date_text(gd), 15, Color(0.75, 0.8, 0.88) if k > 0 else Color(0.95, 0.8, 0.45)))
		var name_l := _label(Calendar.label(c) + "   (" + Calendar.class_name_of(c) + ")", 19 if big else 16, Color(1, 0.92, 0.7) if c["cls"] == "I" else Color.WHITE)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(name_l)
		var comms: Array = c.get("comms", [])
		if not comms.is_empty():
			var cl := _label(Lang.t("Comm. of %s") % ", ".join(comms.map(func(n): return Lang.t(String(n)))), 13, Color(0.7, 0.72, 0.8))
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(cl)
	_cal_box.add_child(_label(Lang.t("On a feast of the I class the men keep the day: their spirits rise. On Sundays a little. Rest on Sundays and feasts (don't march): the men are glad of it and the wounded mend. In Lent many keep the fast, and the food goes further."), 14, Color(0.72, 0.74, 0.8)))
	var sn := World.season()
	_cal_box.add_child(_label(Lang.t("The season: %s. %s") % [Lang.t(sn.capitalize()), Lang.t({"winter": "Little to hunt or harvest, cold nights: the men sicken more easily.", "spring": "The fish are running; the fields are sown.", "summer": "Long days; game is plentiful.", "autumn": "The harvest is in: fields and hunting give the most."}[sn])], 14, Color(0.85, 0.85, 0.7)))
	World.stop()
	_cal_panel.visible = true
	_center(_cal_panel)


func _go(scene: String) -> void:
	World.stop()
	World.save()
	Company.save()
	Loading.change(scene)


func _update_hud() -> void:
	var state := Lang.t("   (paused)")
	if World.camping:
		state = Lang.t("   (in camp, sleeping)")
	elif World.moving() or World.waiting:
		state = "" if not World.is_night() else Lang.t("   (night march)") if World.moving() else ""
	_clock.text = World.clock() + state
	var fd: int = World.day()
	if fd != _feast_day:
		_feast_day = fd
		var c: Dictionary = World.feast()
		_feast_l.text = Calendar.dial_line(c) + ("  ·  " + Calendar.class_name_of(c) if c["cls"] in ["I", "II"] else "") \
			+ "  ·  " + Lang.t(World.season().capitalize())
		var ink: Color = Calendar.cloth(String(c["color"]))
		if String(c["color"]) == "white":
			ink = Color(0.96, 0.9, 0.7) # (white vestments: shown as cream on the dark panel)
		elif String(c["color"]) == "black":
			ink = Color(0.7, 0.7, 0.72)
		_feast_l.add_theme_color_override("font_color", ink)
	var fit := Company.fit_men().size()
	var cm := Company.company_morale()
	_status.text = Lang.t("%d crowns · %d/%d men fit · morale %d (%s)\nfood %.1f days · water %.1f days%s") % [
		Company.money, fit, Company.roster.size(), cm, Men.morale_word(cm),
		Company.days_left("rations"), Company.days_left("water"), Lang.t(" · water foul") if bool(Company.stores["foul"]) else ""]
	if Company.arrears > 0:
		_status.text += Lang.t(" · pay owed %d") % Company.arrears
	var sh := World.stash_hint()
	if sh != "":
		_status.text += "\n" + sh
	var c := World.cell()
	var i: int = Gen.idx(c.x, c.y)
	var g = World.gen
	var what: String = Lang.t(Gen.T_NAMES[g.terrain[i]])
	if g.road[i] > 0:
		what = Lang.t(Gen.ROAD_NAMES[g.road[i]]) + Lang.t(" through ") + what.to_lower()
	if g.river[i] == 2:
		what = Lang.t("Ford")
	elif g.river[i] == 3:
		what = Lang.t("Bridge")
	var eta := ""
	if World.moving():
		eta = Lang.t(" · %d cells to go") % World.path.size()
	var scouting := ""
	if not World.scouts.is_empty():
		var out := 0
		for sc in World.scouts:
			out += (sc["ids"] as Array).size()
		scouting = Lang.t("\n%d scout%s out") % [out, "" if out == 1 else "s"]
	var wxw: String = World.weather.words() if World.weather != null else ""
	if wxw != "":
		what += " · " + wxw
	_terrain_l.text = Lang.t("%s · pace ×%.2f · sight %d%s%s") % [what, g.speed_at(c.x, c.y) * World.party_pace() * World.weather.pace_mult(),
		int(World.sight_radius()), eta, scouting]
	_wait_btn.text = Lang.t("STOP") if World.waiting else Lang.t("WAIT")


func _push_toast(t: String) -> void:
	_toasts.append(t)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	Music.set_context("camp" if World.camping else "map")
	if not _popup.visible and not _logistics.visible and (_scout_panel == null or not _scout_panel.visible) \
			and (_craft_panel == null or not _craft_panel.visible):
		World.tick(delta)
	if _rest_until > 0.0 and World.hours >= _rest_until:
		World.waiting = false
		_rest_until = -1.0
		if _siege_id >= 0:
			_siege_day_done()
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
	_update_tracks(delta)
	_update_weather(delta)
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
		var seen := World.can_see(p) or World.is_trailed(p)
		if not seen and not _markers.has(id):
			continue
		var n := _marker_for(p)
		n.visible = seen
		if seen:
			n.position = _world_pos(Vector2(p["x"], p["y"]))
			var lab := n.get_node("label") as Label3D
			lab.text = World.party_label(p)
			lab.modulate = Color(1, 0.6, 0.5) if World.hostile_to_us(p) else (Color(1.0, 0.88, 0.6) if p["kind"] == "army" else Color(0.9, 0.9, 1.0))
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
	# The weather where you are: rain greys the day, fog lies in the low
	# ground, the heat yellows it.
	var wx = World.weather
	if wx == null:
		return
	var rain: float = wx.rain_at(World.pos)
	var fog: float = wx.fog_at(World.cell())
	var heat: float = wx.heat_at(World.cell())
	_wx_rain = lerpf(_wx_rain, rain, 0.05)
	_wx_fog = lerpf(_wx_fog, fog, 0.05)
	_wx_heat = lerpf(_wx_heat, heat, 0.05)
	_sun.light_energy *= 1.0 - 0.55 * _wx_rain
	_sun.light_color = _sun.light_color.lerp(Color(1.0, 0.86, 0.62), 0.6 * _wx_heat)
	_env.ambient_light_energy *= 1.0 - 0.3 * _wx_rain
	_env.ambient_light_color = _env.ambient_light_color.lerp(Color(0.95, 0.85, 0.65), 0.4 * _wx_heat)
	var haze := maxf(_wx_fog, _wx_heat * 0.25)
	_env.fog_enabled = haze > 0.02
	if _env.fog_enabled:
		_env.fog_light_color = Color(0.72, 0.74, 0.76).lerp(Color(0.85, 0.78, 0.62), _wx_heat).darkened(0.6 * (1.0 - day_f))
		# (thinner as you zoom out, or the whole land goes grey)
		_env.fog_density = (0.0002 + 0.0004 * _wx_heat) * clampf(140.0 / _dist, 0.15, 1.0)
		_env.fog_sky_affect = 0.0
		# Fog lies in the hollows: thick below the ground you stand on.
		var gy := _world_pos(World.pos).y
		_env.fog_height = gy + 3.0
		_env.fog_height_density = 0.18 * _wx_fog


func _update_labels() -> void:
	if _tents.size() != Company.posts.size():
		_refresh_resource_labels()
	for rid in _res_labels:
		var r := World.resource(rid)
		var seen: bool = World.explored[Gen.idx(int(r["x"]), int(r["y"]))] == 1
		var rl: Label3D = _res_labels[rid]
		rl.visible = seen and _dist < 240.0
		if rl.visible:
			var wait := World.harvest_wait(rid)
			rl.text = Lang.t(World.RESOURCES[r["kind"]]["name"]) + (Lang.t("  (worked out: %d days)") % ceili(wait / 24.0) if wait > 0.0 else "")
			var post: Dictionary = Company.posts.get(str(rid), {})
			if not post.is_empty():
				rl.text += Lang.t("  ·  %d at work") % Company.post_size(post)
	for id in _labels:
		var l: Label3D = _labels[id]
		var st: Dictionary = World.settlement(id)
		var known := bool(World.places[id]["known"])
		var far: float = {"village": 260.0, "town": 520.0, "city": 9999.0, "hold": 9999.0, "nest": 520.0}[st["kind"]]
		l.visible = known and _dist < far
		if known and not World.siege_of(id).is_empty():
			l.text = String(st["name"]) + Lang.t("  (besieged)")
		elif known and World.is_raided(id):
			l.text = String(st["name"]) + Lang.t("  (raided)")
		elif known and st["kind"] in ["village", "town", "city"]:
			l.text = String(st["name"])


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
		_push_toast(Lang.t("You break camp and march in the dark."))
		World.night_march_day = World.day()
	var tap := Vector2(cell) + Vector2(0.5, 0.5)
	for p in World.parties:
		if World.can_see(p) and tap.distance_to(Vector2(p["x"], p["y"])) < 3.0:
			_chase = {"id": int(p["id"])}
			_chase_t = 0.8
			World.go_to(Vector2i(int(p["x"]), int(p["y"])), {"kind": "party", "id": int(p["id"])})
			_follow = true
			return
	# Tracks under your finger: read them (and march on to where you tapped).
	var tk := {}
	var tkd := 1.6
	for t in World.seen_tracks():
		var dd := tap.distance_to(Vector2(float(t["x"]), float(t["y"])))
		if dd < tkd:
			tkd = dd
			tk = t
	if not tk.is_empty():
		_push_toast(World.read_track(tk))
	for st in World.gen.settlements:
		var reach: float = World.SETTLEMENT_REACH.get(st["kind"], 3.5) + 1.0
		var seen: bool = bool(World.places[int(st["id"])]["known"]) or World.explored[Gen.idx(int(st["x"]), int(st["y"]))] == 1
		if seen and tap.distance_to(Vector2(st["x"], st["y"])) < reach:
			World.go_to(Vector2i(st["x"], st["y"]), {"kind": "settlement", "id": int(st["id"])})
			_follow = true
			return
	for r in World.gen.resources:
		if World.explored[Gen.idx(int(r["x"]), int(r["y"]))] == 1 and tap.distance_to(Vector2(r["x"], r["y"]) + Vector2(0.5, 0.5)) < 3.0:
			World.go_to(Vector2i(int(r["x"]), int(r["y"])), {"kind": "resource", "id": int(r["id"])})
			_follow = true
			return
	if not World.go_to(cell):
		_push_toast(Lang.t("No way there."))
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
	if Company.pay_plea_pending:
		_pay_plea()
	# A contract run its course: the lord settles his opinion of you.
	var lc: Dictionary = Company.last_contract
	if not lc.is_empty():
		World.change_relation(World.lord(int(lc["lord"])), 15 if lc.get("ended", "") == "done" else -15)
		Company.last_contract = {}


func _on_arrived(g: Dictionary) -> void:
	match String(g["kind"]):
		"settlement":
			_visit(World.settlement(int(g["id"])))
		"resource":
			_visit_resource(int(g["id"]))
		"party":
			var p := World.party_by_id(int(g["id"]))
			_chase = {}
			if not p.is_empty() and p["faction"] != "lizards" and p["kind"] != "detachment":
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


## At a resource site: what it gives, and who works it. SET TO WORK: the
## hands you choose (labourers first, then soldiers) work it for some hours
## with the wagon's tools (the hours pass). LEAVE THEM HERE: they stay as a
## work party, working every day till you come back to COLLECT or RECALL
## them. Or hunt or fish yourself.
var _work_panel: PanelContainer
var _work_box: VBoxContainer
var _work_id := -1
var _work_sel: Array = [] # ids of the people chosen to work
var _work_sel_set := false
var _work_pick_open := false


var _work_cards: Array = [] # [button, person id, text]: the boxes under the slider
var _work_count_l: Label
var _work_cap := 0
var _work_dragging := false
var _knobs := {}


## While the slider moves: tick the boxes, without rebuilding the panel.
func _work_refresh_cards() -> void:
	for c in _work_cards:
		var b: Button = c[0]
		var on: bool = int(c[1]) in _work_sel
		b.text = ("✔ " if on else "") + String(c[2])
		b.modulate = Color(1, 1, 1) if on else (Color(0.62, 0.62, 0.66) if _work_sel.size() < _work_cap else Color(0.45, 0.45, 0.5))
	if _work_count_l != null:
		_work_count_l.text = Lang.t("WHO WORKS:  %d") % _work_sel.size()


## The slider's knob: a brass disc.
func _slider_knob(hi: bool) -> ImageTexture:
	if _knobs.has(hi):
		return _knobs[hi]
	var n := 40
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col := Color(0.95, 0.8, 0.45) if not hi else Color(1.0, 0.9, 0.6)
			if d > n * 0.5 - 1.0:
				col.a = clampf(n * 0.5 - d, 0.0, 1.0)
			if d < n * 0.5 - 5.0:
				col = col.darkened(0.15)
			img.set_pixel(x, y, col)
	_knobs[hi] = ImageTexture.create_from_image(img)
	return _knobs[hi]


## The stepper: the first `n` hands (labourers first, then soldiers).
func _work_set_count(n: int) -> void:
	var kind := String(World.resource(_work_id).get("kind", ""))
	_work_sel = Company.ranked(Company.hands_for_work(), kind).slice(0, n).map(func(m): return int(m["id"]))
	_work_sel_set = true


func _visit_resource(id: int) -> void:
	var r := World.resource(id)
	if r.is_empty():
		return
	var spec: Dictionary = World.RESOURCES[r["kind"]]
	if String(spec["store"]) == "water":
		_visit_spring(id, spec)
		return
	if _work_id != id:
		_work_sel = []
		_work_sel_set = false
	_work_id = id
	if _work_panel == null:
		_work_panel = _panel(Color(UI.WOOL, 0.98))
		_work_panel.custom_minimum_size = Vector2(940, 0)
		_popup.get_parent().add_child(_work_panel)
		var sc := UI.scroll()
		sc.custom_minimum_size = Vector2(920, 560)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_work_panel.add_child(sc)
		_work_box = VBoxContainer.new()
		_work_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_work_box.add_theme_constant_override("separation", 10)
		sc.add_child(_work_box)
	World.stop()
	World.waiting = false
	_fill_work()
	_work_panel.visible = true
	_center(_work_panel)


func _close_work() -> void:
	if _work_panel != null:
		_work_panel.visible = false


func _visit_spring(id: int, spec: Dictionary) -> void:
	var text := Lang.t(String(spec["text"])) + "\n\n" + Lang.t("Tools needed: none, only the barrels.")
	var buttons: Array = []
	if World.harvest_wait(id) <= 0.0:
		buttons.append([Lang.t("FILL THE CART"), func():
			var got := World.gather(id)
			_popup_close()
			if got.is_empty():
				return
			_push_toast(Lang.t("The water cart is full of clean water."))
			World.waiting = true
			_rest_until = World.hours + float(got["hours"])])
	buttons.append([Lang.t("LEAVE"), _popup_close])
	_popup_open(Lang.t(String(spec["name"])), text, buttons)


func _fill_work() -> void:
	var id := _work_id
	var r := World.resource(id)
	var kind := String(r["kind"])
	var spec: Dictionary = World.RESOURCES[kind]
	for c in _work_box.get_children():
		_work_box.remove_child(c)
		c.queue_free()
	var gold := Color(0.95, 0.8, 0.45)
	var dim := Color(0.75, 0.8, 0.88)
	var top := HBoxContainer.new()
	_work_box.add_child(top)
	var t := _label(Lang.t(String(spec["name"])).to_upper(), 28, gold)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	# CONFIRM: set the chosen to work (the same as CONFIRM below).
	var confirm := _button(Lang.t("CONFIRM"), func(): pass)
	confirm.add_theme_color_override("font_color", gold)
	top.add_child(confirm)
	top.add_child(_button(Lang.t("LEAVE"), _close_work))
	var d := _label(Lang.t(String(spec["text"])), 16, dim)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_work_box.add_child(d)
	var owner := int(r.get("owner", -1))
	if owner >= 0:
		var ost := World.settlement(owner)
		var ol := _label(Lang.t("The people of %s work it, and take what they get to market. Its stores: %s.") % [ost["name"],
			preload("res://scripts/economy.gd").stock_line(owner)], 15, dim)
		ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_work_box.add_child(ol)
	var need: Array = spec.get("tools", [])
	var store_name := Company.item_label(String(spec.get("post_store", spec["store"]))).to_lower()
	var wrap := func(l: Label) -> Label:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return l
	# The tools: what the work needs, and what you have.
	var tcard := _panel(Color(0.15, 0.2, 0.33))
	_work_box.add_child(tcard)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tcard.add_child(tv)
	tv.add_child(_label(Lang.t("TOOLS"), 18, gold))
	if need.is_empty():
		tv.add_child(wrap.call(_label(Lang.t("Needed: none. (The men hunt with their muskets.)") if kind == "game" else Lang.t("Needed: none."), 16, Color.WHITE)))
	else:
		var opts: Array = need.map(func(tid): return Company.item_name(String(tid)).to_lower())
		tv.add_child(wrap.call(_label(Lang.t("Needed: one for each person working: %s.") % Lang.t(" or ").join(opts), 16, Color.WHITE)))
		var have: Array = []
		var total := 0
		for tid in need:
			var n := Company.item_count(String(tid))
			total += n
			have.append("%s %d" % [Company.item_name(String(tid)), n])
		var hl := _label(Lang.t("In the wagon: %s  ·  room for %d to work") % ["  ·  ".join(have), total], 16, Color.WHITE if total > 0 else Color(1, 0.55, 0.45))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(hl)
		var pst: Dictionary = Company.posts.get(str(id), {})
		if not pst.is_empty() and not (pst["tools"] as Dictionary).is_empty():
			var with_them: Array = []
			for tid2 in pst["tools"]:
				with_them.append("%s %d" % [Company.item_name(String(tid2)), int(pst["tools"][tid2])])
			tv.add_child(_label(Lang.t("With your work party here: %s") % "  ·  ".join(with_them), 15, dim))
		tv.add_child(wrap.call(_label(Lang.t("Nobody can do this work without one, and any tool may break. Markets sell them.") + (Lang.t(" You can CRAFT a fishing rod from hardwood.") if "fishing_rod" in need else ""), 14, dim)))
	# The work party here, if you left one.
	var post: Dictionary = Company.posts.get(str(id), {})
	if not post.is_empty():
		var made: Array = []
		for k in post["stock"]:
			if int(post["stock"][k]) > 0:
				made.append("%d %s" % [int(post["stock"][k]), Company.item_label(String(k)).to_lower()])
		var tl: Array = []
		for tid in post["tools"]:
			tl.append("%d %s" % [int(post["tools"][tid]), Company.item_name(String(tid)).to_lower()])
		var card := _panel(Color(0.15, 0.2, 0.33))
		_work_box.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(_label(Lang.t("YOUR WORK PARTY HERE"), 20, gold))
		cv.add_child(wrap.call(_label(Lang.t("%d soldiers and %d labourers, here since day %d.  Tools: %s.  Made so far: %s.") % [post["men"].size(), post["workers"].size(), int(post["since"]),
			", ".join(tl) if not tl.is_empty() else Lang.t("none"), ", ".join(made) if not made.is_empty() else Lang.t("nothing yet")], 16, Color.WHITE)))
		# Who's there: tap one to bring him back with you.
		var who := HFlowContainer.new()
		who.add_theme_constant_override("h_separation", 6)
		who.add_theme_constant_override("v_separation", 6)
		cv.add_child(who)
		for m in post["workers"] + post["men"]:
			var mid := int(m["id"])
			var nm: String = String(m["name"]) if m.has("trade") else Company.title(m)
			var rb := _button(Lang.t("%s  ↩") % nm, func(): Company.recall_one(id, mid); _fill_work())
			rb.add_theme_font_size_override("font_size", 15)
			rb.custom_minimum_size = Vector2(0, 44)
			who.add_child(rb)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		cv.add_child(row)
		row.add_child(_button(Lang.t("COLLECT"), func():
			var got := Company.collect_post(id)
			_push_toast(_got_text(got) if not got.is_empty() else Lang.t("Nothing to collect yet (or no room in the wagon)."))
			_fill_work()))
		row.add_child(_button(Lang.t("RECALL THEM"), func():
			var got := Company.recall_post(id)
			_push_toast(Lang.t("The work party packs up and falls in with the wagon.") + ("  " + _got_text(got) if not got.is_empty() else ""))
			_fill_work()))
	# Who works: everyone you choose, one by one (labourers, and which
	# soldiers), or a number with the stepper (the best at it first: strong
	# backs, and a labourer at his own trade).
	var avail: Array = Company.ranked(Company.hands_for_work(), kind)
	var ids: Array = avail.map(func(m): return int(m["id"]))
	# As many can work as there are tools for it.
	var tool_cap := mini(avail.size(), 12) # (with no tools needed, a dozen is all the work wants)
	if not need.is_empty():
		tool_cap = 0
		for tid in need:
			tool_cap += Company.item_count(String(tid))
	if _work_sel.is_empty() and not _work_sel_set:
		_work_sel = ids.slice(0, mini(ids.size(), tool_cap))
		_work_sel_set = true
	_work_sel = _work_sel.filter(func(x): return x in ids)
	var chosen: Array = avail.filter(func(m): return int(m["id"]) in _work_sel)
	var nsel := chosen.size()
	var nl := Company.workers.size()
	# Who works: tap people to send them (and again to take them off). The
	# best at this work are at the top; there's a place for each tool.
	var cap := mini(avail.size(), tool_cap)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_work_box.add_child(head)
	_work_count_l = _label(Lang.t("WHO WORKS:  %d") % nsel, 20, gold)
	head.add_child(_work_count_l)
	var capt := Lang.t("tap people below to send them  ·  a place for each of the %d tools") % tool_cap if not need.is_empty() \
		else Lang.t("tap people below to send them  ·  no tools needed, up to a dozen")
	var cl := _label(capt, 15, dim)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(cl)
	# A slider like a volume bar: slide it up and the best are chosen, one
	# after another (the boxes below tick as it goes).
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	_work_box.add_child(srow)
	srow.add_child(_label("0", 16, dim))
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = maxi(1, cap)
	sl.step = 1
	sl.value = nsel
	sl.editable = cap > 0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 48)
	sl.add_theme_icon_override("grabber", _slider_knob(false))
	sl.add_theme_icon_override("grabber_highlight", _slider_knob(true))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.1, 0.12, 0.2)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	track.set_corner_radius_all(6)
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.66, 0.3)
	fill.content_margin_top = 10
	fill.content_margin_bottom = 10
	fill.set_corner_radius_all(6)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.value_changed.connect(func(v: float):
		_work_set_count(int(v))
		_work_refresh_cards()
		if not _work_dragging:
			_fill_work.call_deferred()) # (a tap on the bar: settle at once)
	sl.drag_started.connect(func(): _work_dragging = true)
	sl.drag_ended.connect(func(_changed: bool):
		_work_dragging = false
		_fill_work.call_deferred())
	srow.add_child(sl)
	srow.add_child(_label("%d" % cap, 16, dim))
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 10)
	_work_box.add_child(quick)
	var best_b := _button(Lang.t("THE BEST %d") % cap, func(): _work_set_count(cap); _fill_work())
	best_b.disabled = cap <= 0
	quick.add_child(best_b)
	quick.add_child(_button(Lang.t("NOBODY"), func(): _work_sel = []; _work_sel_set = true; _fill_work()))
	if nl > 0:
		quick.add_child(_button(Lang.t("LABOURERS ONLY"), func():
			_work_sel = Company.ranked(Company.workers.filter(func(w): return not w.get("away", false)), kind).slice(0, cap).map(func(w): return int(w["id"]))
			_work_sel_set = true
			_fill_work()))
	_work_box.add_child(_label(Lang.t("Best at it first (★: strength and stamina, more for a labourer at his own trade)."), 14, dim))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_work_box.add_child(grid)
	_work_cards = []
	_work_cap = cap
	var shown: Array = avail if _work_pick_open else avail.slice(0, 12)
	# (anyone already chosen stays in view)
	for m in avail:
		if int(m["id"]) in _work_sel and not m in shown:
			shown.append(m)
	for m in shown:
		var mid := int(m["id"])
		var on := mid in _work_sel
		var txt := ""
		var score := "★%d" % int(round(Company.aptitude(m, kind)))
		if Company.workers.has(m):
			txt = "%s\n%s  %s" % [m["name"], Company.trade_name(String(m["trade"])).to_lower(), score]
		else:
			txt = "%s\n%s  %s" % [Company.title(m), Lang.t(String(m.get("tag", "Musketeers"))), score]
		var tb := _button(("✔ " if on else "") + txt, func():
			if mid in _work_sel:
				_work_sel.erase(mid)
			elif _work_sel.size() < cap:
				_work_sel.append(mid)
			else:
				_push_toast(Lang.t("No more tools for this work: take someone off first."))
			_work_sel_set = true
			_fill_work())
		tb.custom_minimum_size = Vector2(205, 62)
		tb.add_theme_font_size_override("font_size", 15)
		tb.modulate = Color(1, 1, 1) if on else (Color(0.62, 0.62, 0.66) if _work_sel.size() < cap else Color(0.45, 0.45, 0.5))
		grid.add_child(tb)
		_work_cards.append([tb, mid, txt])
	if avail.size() > 12:
		_work_box.add_child(_button(Lang.t("SHOW FEWER") if _work_pick_open else Lang.t("SHOW EVERYONE (%d)") % avail.size(), func(): _work_pick_open = not _work_pick_open; _fill_work()))
	var est := World.work_estimate(id, chosen)
	var info := ""
	var wait := World.harvest_wait(id)
	if wait > 0.0:
		info = Lang.t("You've worked it out for now: it gives again in %d days. A work party left here still brings in a little every day.") % ceili(wait / 24.0)
	elif nsel > 0:
		info = Lang.t("%d hours' work for about %d to %d %s.") % [int(spec["hours"]), int(est["lo"]), int(est["hi"]), Company.item_label(String(spec["store"])).to_lower()]
	if not need.is_empty() and tool_cap == 0:
		info = Lang.t("No tools for this work in the wagon: nobody can do it bare-handed. Buy them in a market.")
	elif nsel > 0 and not need.is_empty() and int(est["bare"]) > 0:
		info += "  " + Lang.t("%d of them have no tool and would stand idle.") % int(est["bare"])
	if nsel > 0:
		info += "\n" + Lang.t("Left here as a work party: about %.1f %s a day (they feed themselves).") % [float(spec.get("daily", 0.3)) * float(est["eff"]), store_name]
	if info != "":
		_work_box.add_child(wrap.call(_label(info, 17, Color.WHITE)))
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 10)
	row2.add_theme_constant_override("v_separation", 10)
	_work_box.add_child(row2)
	var bw := _button(Lang.t("CONFIRM"), func():
		var got := World.gather(id, chosen)
		_close_work()
		if got.is_empty():
			return
		var msg := Lang.t("They set to work: %d %s by the end of it.") % [int(got["n"]), Company.item_label(String(got["store"])).to_lower()]
		var bn := Company.broke_note(got["broke"])
		if bn != "":
			msg += "  " + bn
		_push_toast(msg)
		World.waiting = true
		_rest_until = World.hours + float(got["hours"]))
	bw.disabled = wait > 0.0 or nsel <= 0 or float(est["eff"]) <= 0.0
	row2.add_child(bw)
	bw.add_theme_color_override("font_color", gold)
	confirm.disabled = bw.disabled
	confirm.pressed.connect(func(): bw.pressed.emit())
	var bp := _button(Lang.t("POST A WORK PARTY"), func():
		var n := Company.post_party(id, chosen)
		_work_sel = []
		_work_sel_set = false
		_push_toast(Lang.t("%d stay behind to work the %s. Come back to collect what they make.") % [n, Lang.t(String(spec["name"])).to_lower()])
		_refresh_resource_labels()
		_fill_work())
	bp.disabled = nsel <= 0 or float(est["eff"]) <= 0.0
	row2.add_child(bp)
	if kind in ["game", "fish"]:
		# Or go after it yourself.
		var has_rod := Company.item_count("fishing_rod") > 0
		var hb := _button(Lang.t("HUNT YOURSELF") if kind == "game" else (Lang.t("FISH YOURSELF") if has_rod else Lang.t("FISH YOURSELF (no rod)")), func():
			_close_work()
			Company.next_battle = {"hunt": kind, "res": id}
			Company.results_unseen = false
			Company.save()
			World.save()
			_go(BATTLE))
		hb.disabled = wait > 0.0 or (kind == "fish" and not has_rod)
		row2.add_child(hb)
	row2.add_child(_button(Lang.t("CRAFT"), func(): _close_work(); _open_craft()))
	row2.add_child(_button(Lang.t("LEAVE"), _close_work))


# ---------------------------------------------------------------- trading on the road

var _trade_panel: PanelContainer
var _trade_box: VBoxContainer
var _trade_with := {}


## A caravan, traders or villagers met on the road: buy from what they
## carry, sell them your raw goods (economy.gd).
func _open_party_trade(p: Dictionary) -> void:
	_trade_with = p
	if _trade_panel == null:
		_trade_panel = _panel(Color(UI.WOOL, 0.98))
		_trade_panel.custom_minimum_size = Vector2(760, 0)
		_popup.get_parent().add_child(_trade_panel)
		var sc := UI.scroll()
		sc.custom_minimum_size = Vector2(740, 520)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_trade_panel.add_child(sc)
		_trade_box = VBoxContainer.new()
		_trade_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_trade_box.add_theme_constant_override("separation", 8)
		sc.add_child(_trade_box)
	World.stop()
	_fill_party_trade()
	_trade_panel.visible = true
	_center(_trade_panel)


func _fill_party_trade() -> void:
	var p := _trade_with
	for c in _trade_box.get_children():
		_trade_box.remove_child(c)
		c.queue_free()
	var gold := Color(0.95, 0.8, 0.45)
	var top := HBoxContainer.new()
	_trade_box.add_child(top)
	var t := _label(World.party_name(p).split(" (")[0].to_upper(), 24, gold)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(t)
	top.add_child(_button(Lang.t("DONE"), func(): _trade_panel.visible = false))
	_trade_box.add_child(_label(Lang.t("%d crowns") % Company.money, 17, Color.WHITE))
	var offers := Econ.road_offers(p)
	_trade_box.add_child(_label(Lang.t("THEY SELL") if not offers.is_empty() else Lang.t("They've nothing to sell."), 18, gold))
	for o in offers:
		var cr := Company.price(int(o[2]))
		var b := _button(Lang.t("%d %s  ·  %d cr   (they have %d)") % [int(o[1]), Econ.good_name(String(o[0])), cr, int(p["cargo"][o[0]])], func():
			var why := Econ.buy_from_party(p, o)
			_push_toast(why if why != "" else Lang.t("Bought."))
			_fill_party_trade())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = Company.money < cr
		_trade_box.add_child(b)
	var sells: Array = []
	for g in Company.MATERIALS:
		if Econ.road_sell_price(g) > 0 and int(Company.stores.get(g, 0)) >= Econ.LOT:
			sells.append(g)
	if not sells.is_empty():
		_trade_box.add_child(_label(Lang.t("THEY'LL BUY"), 18, gold))
		for g in sells:
			var b2 := _button(Lang.t("Sell %d lb of %s  ·  %d cr   (have %d)") % [Econ.LOT, Econ.good_name(g), Econ.road_sell_price(g), int(Company.stores.get(g, 0))], func():
				var got := Econ.sell_to_party(p, g)
				_push_toast(Lang.t("Sold for %d crowns.") % got)
				_fill_party_trade())
			b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_trade_box.add_child(b2)


func _got_text(got: Dictionary) -> String:
	var bits: Array = []
	for k in got:
		bits.append("%d %s" % [int(got[k]), Company.item_label(String(k)).to_lower()])
	return Lang.t("Into the wagon: %s.") % ", ".join(bits)


# ---------------------------------------------------------------- craft

var _craft_panel: PanelContainer
var _craft_list: VBoxContainer
var _craft_head: Label


## CRAFT: what the company can make from what it carries, in camp. Making
## takes hours (they pass at once on the map; the stores change now).
func _open_craft() -> void:
	if _craft_panel == null:
		_craft_panel = _panel(Color(UI.WOOL, 0.98))
		_craft_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_craft_panel.custom_minimum_size = Vector2(900, 560)
		_craft_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_craft_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_popup.get_parent().add_child(_craft_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		_craft_panel.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		var t := _label(Lang.t("CRAFT"), 28, Color(0.95, 0.8, 0.45))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		top.add_child(_button(Lang.t("CLOSE"), func(): _craft_panel.visible = false))
		_craft_head = _label("", 16, Color(0.8, 0.84, 0.9))
		_craft_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(_craft_head)
		var sc := UI.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		_craft_list = VBoxContainer.new()
		_craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_craft_list.add_theme_constant_override("separation", 10)
		sc.add_child(_craft_list)
	World.stop()
	_fill_craft()
	_craft_panel.visible = true
	_center(_craft_panel)


func _fill_craft() -> void:
	var st: Dictionary = Company.stores
	var have: Array = []
	for k in Company.MATERIALS + ["powder", "lead"]:
		have.append("%s %d" % [Company.item_label(k), int(st.get(k, 0))])
	if int(st.get("wood_shot", 0)) > 0:
		have.append(Lang.t("cartridges %d (%d%% wooden)") % [int(st.get("ammo", 0)), int(Company.wood_share() * 100.0)])
	_craft_head.text = Lang.t("In the wagon: ") + "  ·  ".join(have) + "\n" + Lang.t("Gather materials at the caves, springs, woods and hunting grounds on the map (their names show when you're close).")
	for c in _craft_list.get_children():
		c.queue_free()
	for id in Company.RECIPES:
		var r: Dictionary = Company.RECIPES[id]
		if r.get("mend", false) and Company.craft_count(id) <= 0:
			continue # (nothing broken of that kind)
		var card := _panel(Color(0.15, 0.2, 0.33))
		_craft_list.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		card.add_child(h)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(_label(Lang.t(String(r["name"])), 21, Color(0.95, 0.8, 0.45)))
		var needs: Array = []
		for k in r["needs"]:
			needs.append("%d %s" % [int(r["needs"][k]), Company.item_label(k)])
		var makes: Array = []
		for k in r["makes"]:
			if k == "wood_shot":
				continue
			makes.append("%d %s" % [int(r["makes"][k]), Company.item_label(k)])
		var l := _label(Lang.t("%s  →  %s   ·   %.0f hours") % [" + ".join(needs), ", ".join(makes), Company.craft_hours(id)], 16, Color.WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(l)
		var d := _label(Lang.t(String(r["text"])), 14, Color(0.7, 0.75, 0.85))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		var n := Company.craft_count(id)
		for want in [1, n]:
			if want == n and (n <= 1):
				continue
			var b := _button(Lang.t("MAKE ×%d") % maxi(1, want), _do_craft.bind(id, maxi(1, want)))
			b.disabled = n < 1
			b.custom_minimum_size = Vector2(130, 56)
			h.add_child(b)


func _do_craft(id: String, n: int) -> void:
	var made := Company.craft(id, n)
	if made <= 0:
		return
	var hrs := Company.craft_hours(id) * made
	var what: Array = []
	for k in Company.RECIPES[id]["makes"]:
		if k == "wood_shot":
			continue
		what.append("%d %s" % [made * int(Company.RECIPES[id]["makes"][k]), Company.item_label(k).to_lower()])
	_push_toast(Lang.t("The men work at it for %d hours: %s.") % [int(hrs), ", ".join(what)])
	_craft_panel.visible = false
	World.waiting = true
	_rest_until = World.hours + hrs


## The first pay day missed in the wilds: the men come to you, hats in
## their hands; the sergeant speaks for them.
func _pay_plea() -> void:
	var sg: Array = Company.roster.filter(func(m): return int(m["rank"]) >= 3)
	var sarge: String = Company.title(sg[0]) if not sg.is_empty() else Lang.t("The sergeant")
	var text := Lang.t("At the evening halt a knot of men comes to your fire, hats in their hands. Nobody wants to speak first.\n\n\"Begging your pardon, sir. It's pay day, and there's none. We know there's none to be had out here.\"\n\n%s steps forward. \"They'll wait, sir. We all will. A man can't eat gold, not in this place. But find us people, sir: a town, a village, anything with a roof on it. Once there's something to spend it on, the lads will want what they're owed, every week of it.\"\n\n[color=#9aa3b8]Until you find a village or a town, missed pay is only owed (it adds up). After that, a missed week angers them; when there's money, they're paid everything owed.[/color]") % sarge
	_scene("camp")
	_popup_open(Lang.t("Hats in their hands"), text, [
		[Lang.t("\"YOU'LL HAVE EVERY CROWN.\""), func(): Company.answer_plea(true); _popup_close()],
		[Lang.t("\"WE'LL SEE.\""), func(): Company.answer_plea(false); _popup_close()]])


## Arriving at a settlement: what it is, and what you can do there.
func _visit(st: Dictionary) -> void:
	if st["kind"] != "nest":
		var news := Company.found_civilization()
		if news != "":
			_push_toast(news)
		# Word of the ship's stores, the first time you come to a place.
		var tk := str(int(st["id"]))
		if not Company.towns.has(tk) and randf() < 0.6:
			Company.last_rumour = World.stash_clue("town")
	var fac: Dictionary = Lore.FACTIONS[st["faction"]]
	var kind: String = st["kind"]
	var title := Lang.t("%s, %s of %s") % [st["name"], {"village": Lang.t("a village"), "town": Lang.t("a town"), "city": Lang.t("a city"),
		"hold": Lang.t("a hold"), "nest": Lang.t("a nest")}[kind], fac["short"]]
	var text := ""
	var buttons: Array = []
	var id := int(st["id"])
	Company.market_faction = String(st["faction"])
	if kind == "nest":
		_visit_nest(st)
		return
	elif kind in ["village", "town", "city"] and Company.is_enemy(String(st["faction"])):
		# You're the enemy here.
		text = (Lang.t("The gates are shut against you, and there are crossbows on the walls. %s has no welcome for you.") if kind != "village" \
			else Lang.t("The villagers see your red coats coming and bar their doors; someone runs for the soldiers of %s.")) % fac["name"]
		buttons.append([Lang.t("LEAVE"), _popup_close])
		_scene("patrol", {"faction": st["faction"]})
	elif not World.siege_of(id).is_empty() and kind in ["town", "city"]:
		_visit_besieged(st)
		return
	elif World.is_raided(id):
		text = Lang.t("Burned. Raiders have been here; the people who are left have nothing to sell.")
		buttons.append([Lang.t("LEAVE"), _popup_close])
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
				text = Lang.t("A farming village. They eye your red coats and muskets warily, but they'll sell food.")
			"town":
				text = Lang.t("A market town. Food and drink for sale, and talk of the war with %s.") % ("Vell" if st["faction"] == "aurest" else "Aurest")
			"city":
				text = Lang.t("A walled city of %s. Everything that can be bought is for sale here, except powder: nobody here has heard of it.") % fac["name"]
			"hold":
				text = Lang.t("A dwarf hold cut into the mountain. The dwarves look at your muskets with great interest.")
		text += Lang.t("\n\nWater barrels refilled. Recruiting locals comes soon.")
		var prices := {"village": [10, 5], "town": [20, 9], "city": [20, 8], "hold": [20, 10]}
		var pr: Array = [prices[kind][0], Company.price(prices[kind][1])]
		buttons.append([Lang.t("FOOD +%d (%d cr)") % [pr[0], pr[1]], func():
			if Company.room_for("rations") < int(pr[0]):
				_push_toast(Lang.t("The wagon is full."))
			elif Company.money >= int(pr[1]):
				Company.money -= int(pr[1])
				Company.stores["rations"] = int(Company.stores["rations"]) + int(pr[0])
				Company.save()
				_push_toast(Lang.t("Bought %d rations.") % int(pr[0]))])
		if kind != "village":
			var rum_cr := Company.price(6)
			buttons.append([Lang.t("RUM +10 (%d cr)") % rum_cr, func():
				if Company.room_for("rum") < 10:
					_push_toast(Lang.t("The wagon is full."))
				elif Company.money >= rum_cr:
					Company.money -= rum_cr
					Company.stores["rum"] = int(Company.stores["rum"]) + 10
					Company.save()
					_push_toast(Lang.t("Bought 10 tots of rum."))])
		var gv := Company.goods_value(kind)
		if gv > 0:
			buttons.append([Lang.t("SELL LOOT (%d cr)") % gv, func():
				var got := Company.sell_goods(kind)
				_push_toast(Lang.t("Sold the loot for %d crowns.") % got)
				_popup_close()])
		buttons.append([Lang.t("REST A DAY"), func():
			_popup_close()
			World.waiting = true
			_rest_until = World.hours + 24.0])
		buttons.append([Lang.t("LEAVE"), _popup_close])
		Company.stores["water"] = maxi(int(Company.stores["water"]), Company.WATER_CART)
		Company.stores["foul"] = false
	_popup_open(title, text, buttons)


var _rest_until := -1.0
var _siege_id := -1 # the nest you're besieging (a day's siege is running)


## Before a lizard nest: what you can see of it, and what you can do. Burn
## it by storming it, or besiege it first (a day at a time): hunger and your
## guns thin them and break the stakes, but at night they may sally out.
func _visit_nest(st: Dictionary) -> void:
	var id := int(st["id"])
	var title := Lang.t("%s, a lizard nest") % st["name"]
	var buttons: Array = []
	if World.nest_destroyed(id):
		_scene("burned")
		_popup_open(title, Lang.t("Burned-out mounds and toppled stakes. Nothing moves here now."), [[Lang.t("LEAVE"), _popup_close]])
		return
	var n := World.nest(id)
	var g := int(n["garrison"])
	var walls := float(n["walls"])
	var text := Lang.t("Mounds of packed mud behind a ring of sharpened stakes lashed with bone, one gate of logs. ")
	text += Lang.t("You count about [b]%d[/b] of them, ") % (int(round(g / 5.0)) * 5)
	if walls > 0.85:
		text += Lang.t("behind a palisade that stands whole.")
	elif walls > 0.5:
		text += Lang.t("behind a palisade starting to sag.")
	elif walls > 0.2:
		text += Lang.t("behind a broken palisade: there are gaps you could get through.")
	else:
		text += Lang.t("behind what's left of the stakes: it's wide open.")
	var days := int(n["siege_days"])
	if days > 0:
		text += Lang.t("\n\nDay %d of the siege. They're hungry, and they're fewer.") % days
	# Their larder (economy.gd): fed, they send out bigger warbands; their
	# hunting parties feed it.
	var meat := Econ.have(id, "meat")
	text += "\n\n" + (Lang.t("Carcasses hang on racks between the mounds: they're well fed, and their warbands will be big.") if meat >= 40 \
		else (Lang.t("A few carcasses on the racks. Kill their hunting parties and they'll go hungry.") if meat >= 8 \
		else Lang.t("The racks are bare: they're hungry, and their warbands are smaller for it.")))
	if Econ.have(id, "plunder") > 0:
		text += Lang.t(" There's plunder piled by the mounds (%d crowns' worth or so): it's yours if you burn the place.") % Econ.have(id, "plunder")
	if id == World.gen.stash_nest and not Company.stash.is_empty():
		text += Lang.t("\n\n[color=#f0c060]Through the stakes you can see crates with the %s's mark, the ship's guns, powder kegs. Your stores are here.[/color]") % Lore.SHIP
	var fit := Company.fit_men().size()
	text += Lang.t("\n\nYou have %d fit men%s.") % [fit, Lang.t(" and %d guns") % Company.guns if Company.guns > 0 else Lang.t(", and no guns to batter the gate")]
	text += Lang.t("\n\n[color=#9aa3b8]ASSAULT: storm it now: break the gate (guns, grenades, axes) while the garrison sallies out at you.\nBESIEGE: camp before it for a day. Hunger thins them%s, but at night they may come out at you.[/color]") % (Lang.t(" and your guns batter the stakes") if Company.guns > 0 else "")
	buttons.append([Lang.t("PLAN"), _plan_assault.bind(st)])
	buttons.append([Lang.t("ASSAULT"), _assault.bind(st)])
	buttons.append([Lang.t("BESIEGE A DAY"), _besiege.bind(st)])
	buttons.append([Lang.t("LEAVE"), func():
		if int(World.nest(id)["siege_days"]) > 0:
			World.lift_siege(id)
			_push_toast(Lang.t("You lift the siege."))
		_popup_close()])
	_scene("nest")
	_popup_open(title, text, buttons)


func _set_assault(st: Dictionary) -> void:
	var id := int(st["id"])
	var n := World.nest(id)
	Company.next_battle = {"enemy": int(n["garrison"]), "terrain": World.gen.t(int(st["x"]), int(st["y"])), "party": -1,
		"ambush": false, "enemy_kind": "lizards", "assault": id, "walls": float(n["walls"]),
		"stash": id == World.gen.stash_nest and not Company.stash.is_empty(), "nest_name": String(st["name"])}
	var esc := _escort_allies("lizards")
	if not esc.is_empty():
		Company.next_battle["allies"] = esc
	Company.results_unseen = false


func _assault(st: Dictionary) -> void:
	_popup_close()
	if _test:
		print("  MAPTEST: assault on ", st["name"], " (counted as won)")
		World.nest_fought(int(st["id"]), int(World.nest(int(st["id"]))["garrison"]), true)
		return
	_set_assault(st)
	_go(BATTLE)


func _plan_assault(st: Dictionary) -> void:
	_popup_close()
	_set_assault(st)
	Company.next_battle["planning"] = true
	_go(PLAN)


## A day's siege: time passes (food, water) and at its end _siege_day_done().
func _besiege(st: Dictionary) -> void:
	_popup_close()
	_siege_id = int(st["id"])
	World.waiting = true
	_rest_until = World.hours + 24.0
	_push_toast(Lang.t("You dig in before %s.") % st["name"])


func _siege_day_done() -> void:
	var id := _siege_id
	_siege_id = -1
	var st := World.settlement(id)
	var r := World.siege_day(id, Company.guns)
	var text := Lang.t("A day before %s. Hunger%s cost them about %d.") % [st["name"], Lang.t(" and your guns") if Company.guns > 0 else "", int(r["lost"])]
	if float(r["walls"]) > 0.06:
		text += Lang.t(" The stakes are coming down.")
	if int(r["sortie"]) > 0:
		# They come out in the night: fought like a camp attack, the watch up and ready.
		var size := int(r["sortie"])
		Company.next_battle = {"enemy": size, "terrain": World.gen.t(int(st["x"]), int(st["y"])), "party": -1, "ambush": false,
			"enemy_kind": "lizards", "camp": true, "spotted": true, "night": true, "watch": [], "sortie": id}
		Company.results_unseen = false
		text += Lang.t("\n\n[b]In the night they sally out at your lines: %d of them![/b]") % size
		_scene("camp_attack", {"time": "night"})
		_popup_open(Lang.t("A sortie!"), text, [[Lang.t("STAND TO!"), func():
			_popup_close()
			if _test:
				World.nest_fought(id, size, false)
				print("  MAPTEST: sortie of ", size, " (counted as won)")
				return
			_go(BATTLE)]])
		return
	_scene("nest")
	_popup_open(Lang.t("The siege"), text, [[Lang.t("GO ON"), func(): _visit_nest(st)]])


## Meeting a party that isn't hostile.
func _meet(p: Dictionary) -> void:
	var text := ""
	match String(p["kind"]):
		"caravan":
			text = Lang.t("Merchants with mules and carts, on the road between the towns.")
		"patrol":
			text = Lang.t("Soldiers of %s. They watch you closely: strangers in red coats, armed with something they've never seen.") % Lore.FACTIONS[p["faction"]]["name"]
		"villagers":
			text = Lang.t("Country folk on their way to market. They tell you the lizards have been raiding to the south.")
		"labourers":
			var hs := World.settlement(int(p["home"]))
			var site := World.resource(int(p.get("site", -1)))
			text = Lang.t("People of %s with picks, axes and baskets, going to work the %s, or coming home from it.") % [hs.get("name", "?"),
				Lang.t(String(World.RESOURCES.get(String(site.get("kind", "")), {}).get("name", "fields"))).to_lower()]
		"traders":
			text = Lang.t("Dwarf traders with pack ponies loaded with iron. They ask, very politely, how your guns work.")
		"army":
			var l := World.lord_of(p)
			if not l.is_empty():
				text = Lang.t("The army of %s: a long column of spears and crossbows, his household riding at its head under his banner. He reins in to look you over: the strangers with the fire-sticks.") % World.lord_full(l)
				text += Lang.t("\n\n[color=#9aa3b8]%s is %s to you.[/color]") % [World.lord_short(l), World.relation_word(int(l["relation"]))]
				if int(l["relation"]) >= 15:
					text += Lang.t(" He greets you by name, and asks what you've seen of the lizards.")
				var c: Dictionary = Company.contract
				if not c.is_empty() and int(c["lord"]) == int(l["id"]):
					text += Lang.t("\n\n[color=#c9a14a]You serve him until day %d: %s (%d of %d). %d crowns a week.[/color]") % [
						int(c["until"]), Lang.t(Company.DUTIES[c["duty"]][0]), int(c["done"]), int(c["need"]), int(c["pay"])]
			else:
				text = Lang.t("An army of %s on the march.") % Lore.FACTIONS[p["faction"]]["name"]
	var buttons: Array = []
	var kind := String(p["kind"])
	if kind in ["caravan", "traders", "villagers", "labourers"]:
		var cw := Econ.cargo_words(p.get("cargo", {}))
		text += ("\n\n" + Lang.t("They're carrying %s.") % cw) if cw != "" else ("\n\n" + Lang.t("They're carrying nothing to speak of."))
		buttons.append([Lang.t("TRADE"), func(): _popup_close(); _open_party_trade(p)])
	if kind == "deserters":
		text = Lang.t("Ragged men in odd bits of %s kit, who ran from the war and live off the road now. Nobody would miss them.") % Lore.FACTIONS[p["faction"]]["short"]
	if kind in ["patrol", "caravan", "deserters", "army"]:
		var lvl := World.intel_level(p, 0.0)
		text += Lang.t("\n\n%s of them") % ("%d" % int(p["size"]) if lvl >= 2 else World.rough_count(p))
		if lvl >= 3:
			text += ": %s" % World.comp_text(World.party_comp(p))
		text += "."
		var f := String(p["faction"])
		if kind != "deserters":
			text += Lang.t("\n\n[color=#9aa3b8]%s thinks of you: %s.[/color]") % [Lore.FACTIONS[f]["name"], Lang.t(Company.standing_word(f))]
			text += Lang.t("\n[color=#f08060]Attack them and %s will remember it: %s.[/color]") % [Lore.FACTIONS[f]["short"],
				Lang.t("their patrols will hunt you") if Company.standing.get(f, 0) - _ATTACK_COST[kind] <= Company.HOSTILE_AT else Lang.t("they'll trust you less")]
		if kind == "army" and _may_hire(p):
			buttons.append([Lang.t("OFFER YOUR SERVICE"), _offer_service.bind(p)])
		if kind == "army" and _may_march_with(p):
			buttons.append([Lang.t("MARCH WITH US"), func():
				_popup_close()
				World.escort(p, 4.0)
				_push_toast(Lang.t("%s's army will march with you for four days.") % World.lord_short(World.lord_of(p)))])
		buttons.append([Lang.t("ATTACK"), _attack_party.bind(p)])
	buttons.append([Lang.t("LEAVE"), _popup_close])
	_scene({"caravan": "caravan", "patrol": "patrol", "villagers": "villagers", "labourers": "villagers", "traders": "traders",
		"deserters": "deserters", "army": "patrol"}.get(kind, "road"), {"faction": p.get("faction", "vell")})
	_popup_open(World.party_label(p, mini(World.intel_level(p, 0.0), 2)), text, buttons)


## What attacking a nation's men costs you with it (and what its enemy
## thinks of that).
const _ATTACK_COST := {"patrol": 40, "caravan": 30, "deserters": 0, "army": 50}


## Will this lord march with you? A friend, or your employer, with nobody
## else already marching with you.
func _may_march_with(p: Dictionary) -> bool:
	var l := World.lord_of(p)
	if l.is_empty() or not World.escorting().is_empty() or float(p.get("escort_until", 0.0)) > World.hours:
		return false
	var hired: bool = not Company.contract.is_empty() and int(Company.contract["lord"]) == int(l["id"])
	return hired or int(l["relation"]) >= 30


## The army marching with you, as the allies for a battle here ({} if none,
## or if it's too far off, or it's the enemy's own nation).
func _escort_allies(enemy_faction: String) -> Dictionary:
	var e := World.escorting()
	if e.is_empty() or String(e["faction"]) == enemy_faction:
		return {}
	if Vector2(e["x"], e["y"]).distance_to(World.pos) > 4.0:
		return {}
	return {"faction": String(e["faction"]), "comp": World.party_comp(e), "party": int(e["id"]),
		"size": int(e["size"]), "lord": int(e.get("lord", -1))}


## Will this lord take you on? Not if you already serve someone, if he or
## his nation think ill of you.
func _may_hire(p: Dictionary) -> bool:
	var l := World.lord_of(p)
	return not l.is_empty() and Company.contract.is_empty() and int(l["relation"]) >= 0 \
		and int(Company.standing.get(String(p["faction"]), 0)) >= 0


func _offer_service(p: Dictionary) -> void:
	_popup_close()
	var l := World.lord_of(p)
	var terms := Company.contract_terms(int(l["id"]), String(p["faction"]), World.lord_short(l))
	var text := Lang.t("%s looks over your men, and the muskets longer still.\n\n\"Three weeks. %d crowns a week while you serve, paid every seventh day. %s, and there's a bonus in it.\"") % [
		World.lord_full(l), int(terms["pay"]), Lang.t(Company.DUTIES[terms["duty"]][0])]
	text += Lang.t("\n\n[color=#9aa3b8]Duty: %s (%d). %s will hear of it and like you less.[/color]") % [
		Lang.t(Company.DUTIES[terms["duty"]][2]), int(terms["need"]), Lore.FACTIONS[Company.AT_WAR[p["faction"]]]["name"]]
	_scene("patrol", {"faction": p["faction"]})
	_popup_open(Lang.t("Terms from %s") % World.lord_short(l), text, [[Lang.t("ACCEPT"), func():
			_popup_close()
			Company.sign_contract(terms)
			World.change_relation(l, 5)
			Company.save()
			_push_toast(Lang.t("You serve %s until day %d.") % [World.lord_short(l), int(terms["until"])])],
		[Lang.t("DECLINE"), _popup_close]])


func _attack_party(p: Dictionary) -> void:
	var kind := String(p["kind"])
	var f := String(p["faction"])
	var note := ""
	if not Company.contract.is_empty() and String(Company.contract["faction"]) == f:
		World.change_relation(World.lord(int(Company.contract["lord"])), -40)
		note = Company.break_contract()
	var e := World.escorting()
	if not e.is_empty() and String(e["faction"]) == f:
		e["escort_until"] = World.hours # (he won't march with you now)
	if int(_ATTACK_COST.get(kind, 0)) > 0:
		var was := Company.is_enemy(f)
		Company.change_standing(f, -int(_ATTACK_COST[kind]))
		Company.change_standing(String(Company.AT_WAR.get(f, "")), 10)
		if Company.is_enemy(f) and not was:
			note = Lang.t("%s will not forget this: its patrols will hunt you now.") % Lore.FACTIONS[f]["name"]
	if kind == "army":
		var l := World.lord_of(p)
		World.change_relation(l, -60)
		if not l.is_empty() and note == "":
			note = Lang.t("%s has sworn to see you hanged.") % World.lord_short(l)
	_fight(p, false)
	if note != "" and not Company.next_battle.is_empty():
		Company.next_battle["standing_note"] = note


## 18:00 on the march.
func _on_dusk() -> void:
	_scene("dusk", {"time": "dusk"})
	_popup_open("Dusk", Lang.t("The light is going. Make camp and sleep until dawn, or march on through the night: slower, half blind, and the men won't thank you."),
		[[Lang.t("MAKE CAMP"), func():
			_popup_close()
			World.make_camp()], [Lang.t("MARCH ON IN THE DARK"), func():
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
	if key == "self":
		# Go after it yourself, musket in hand (the hunt: battle.gd).
		Company.next_battle = {"hunt": "game", "res": -1}
		Company.results_unseen = false
		_go(BATTLE)
		return
	var r: Dictionary = World.events.resolve(World, ev["id"], key)
	if r.has("fight"):
		World.stop()
		_on_encounter(r["fight"])
		return
	if String(r["text"]) != "":
		_scene(_event_scene(String(ev["id"])))
		_popup_open(ev["title"], r["text"], [[Lang.t("CARRY ON"), _popup_close]], false)


## Scouts: pick a direction and how far.
var _scout_panel: PanelContainer
var _scout_info: Label
var _scout_days := 1
var _scout_sel: Array = [] # ids chosen to go
var _scout_people: HFlowContainer
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
	var title := _label(Lang.t("SEND SCOUTS"), 26, Color(0.95, 0.8, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := _button("✕", _close_scouts)
	x.custom_minimum_size = Vector2(58, 58)
	head.add_child(x)
	_scout_info = _label("", 16, Color.WHITE)
	_scout_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scout_info.custom_minimum_size = Vector2(560, 0)
	v.add_child(_scout_info)
	# How long they're gone: the longer, the further they go and the more they see.
	var range_row := HBoxContainer.new()
	range_row.add_theme_constant_override("separation", 10)
	v.add_child(range_row)
	range_row.add_child(_label(Lang.t("Days out:"), 19, Color(0.95, 0.8, 0.45)))
	var minus := _button("-", func(): _scout_days = maxi(1, _scout_days - 1); _refresh_scouts())
	minus.custom_minimum_size = Vector2(64, 54)
	range_row.add_child(minus)
	var dl := _label("1", 26, Color.WHITE)
	dl.name = "days"
	dl.custom_minimum_size = Vector2(44, 0)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_row.add_child(dl)
	var plus := _button("+", func(): _scout_days = mini(World.SCOUT_MAX_DAYS, _scout_days + 1); _refresh_scouts())
	plus.custom_minimum_size = Vector2(64, 54)
	range_row.add_child(plus)
	# Who goes: the best scouts first; tap to choose.
	v.add_child(_label(Lang.t("Who goes (best scouts first: fitness, stamina, a good eye; hunters and natives know the land):"), 15, Color(0.72, 0.74, 0.8)))
	var psc := UI.scroll()
	psc.custom_minimum_size = Vector2(620, 104)
	psc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(psc)
	_scout_people = HFlowContainer.new()
	_scout_people.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scout_people.add_theme_constant_override("h_separation", 6)
	_scout_people.add_theme_constant_override("v_separation", 6)
	psc.add_child(_scout_people)
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
			var mid := _label(Lang.t("PICK A\nDIRECTION"), 14, Color(0.72, 0.74, 0.8))
			mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(mid)
		else:
			grid.add_child(_button(d[0], _send_scouts.bind(d[1])))
	var cancel := _button(Lang.t("CANCEL: KEEP THEM HERE"), _close_scouts)
	cancel.custom_minimum_size.y = 58
	v.add_child(cancel)
	_scout_panel.visible = false
	_scout_shade.visible = false


func _refresh_scouts() -> void:
	var cands := World.scout_candidates()
	var ids: Array = cands.map(func(m): return int(m["id"]))
	_scout_sel = _scout_sel.filter(func(x): return x in ids)
	if _scout_sel.is_empty() and not cands.is_empty():
		_scout_sel = [int(cands[0]["id"])]
	(_scout_panel.find_child("days", true, false) as Label).text = "%d" % _scout_days
	for c in _scout_people.get_children():
		_scout_people.remove_child(c)
		c.queue_free()
	for m in cands.slice(0, 16):
		var mid := int(m["id"])
		var on := mid in _scout_sel
		var nm: String = String(m["name"]) if Company.workers.has(m) else Company.surname_title(m)
		var b := _button(("✔ " if on else "") + "%s  ★%d" % [nm, int(round(Company.aptitude(m, "scout")))], func():
			if mid in _scout_sel:
				_scout_sel.erase(mid)
			else:
				_scout_sel.append(mid)
			_refresh_scouts())
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(0, 46)
		b.modulate = Color.WHITE if on else Color(0.62, 0.62, 0.66)
		_scout_people.add_child(b)
	var chosen: Array = cands.filter(func(m): return int(m["id"]) in _scout_sel)
	var best := 0.0
	for m in chosen:
		best = maxf(best, Company.aptitude(m, "scout"))
	var need := World.scout_supplies(chosen.size(), _scout_days)
	var risk := World.scout_risk(_scout_days, chosen.size(), best)
	var t := Lang.t("The longer they're out, the further they go and the more they see; more of them see more, and are safer.\n")
	t += Lang.t("%d going for %d days: about %d leagues out. They take %d rations and %d days' water (you have %d and %d). Risk: %s.") % [
		chosen.size(), _scout_days, int(World.SCOUT_PER_DAY * _scout_days * 0.5), int(need["rations"]), int(need["water"]),
		int(Company.stores.get("rations", 0)), int(Company.stores.get("water", 0)),
		Lang.t("low") if risk < 0.1 else (Lang.t("some") if risk < 0.2 else (Lang.t("high") if risk < 0.35 else Lang.t("very high")))]
	for sc in World.scouts:
		t += Lang.t("\nOut now: %s, back around day %d.") % [", ".join(sc["names"]), 1 + int(float(sc["back"]) / 24.0)]
	_scout_info.text = t


func _send_scouts(dir: Vector2) -> void:
	var cands := World.scout_candidates()
	var chosen: Array = cands.filter(func(m): return int(m["id"]) in _scout_sel)
	var sc := World.send_scouts(dir, _scout_days, chosen)
	if sc.has("error"):
		_push_toast(String(sc["error"]))
		return
	_close_scouts()
	_scout_sel = []
	_push_toast(Lang.t("%s set out.") % ", ".join(sc["names"]))


func _on_scouts_back(r: Dictionary) -> void:
	var t := ""
	var names: Array = r["names"]
	if r["lost"].size() == names.size():
		t = Lang.t("%s never came back. You wait as long as you dare.") % ", ".join(names)
		_scene("scouts_lost")
		_popup_open(Lang.t("The scouts are lost"), t, [[Lang.t("CARRY ON"), _popup_close]], false)
		return
	if r["lost"].size() > 0:
		t += Lang.t("Only one comes back, wounded. %s did not.\n\n") % ", ".join(r["lost"])
	else:
		t += Lang.t("%s report:\n\n") % ", ".join(names)
	if r["terrain"] != "":
		t += Lang.t("Mostly %s out there.\n") % r["terrain"]
	t += (Lang.t("They found: ") + ", ".join(r["found"]) + ".\n") if r["found"].size() > 0 else Lang.t("No towns or villages.\n")
	t += (Lang.t("They saw: ") + ", ".join(r["parties"]) + ".") if r["parties"].size() > 0 else Lang.t("Nobody on the move.")
	_scene("scouts_back", {"n": names.size() - (r["lost"] as Array).size()})
	_popup_open(Lang.t("The scouts are back"), t, [[Lang.t("CARRY ON"), _popup_close]], false)


## A town under siege: the gates are shut. Attack the besiegers (with the
## garrison sallying beside you), or, if you're on the besiegers' side, lend
## them your guns and men to shorten it.
func _visit_besieged(st: Dictionary) -> void:
	var id := int(st["id"])
	var sg := World.siege_of(id)
	var army: Dictionary = sg["army"]
	var l := World.lord_of(army)
	var def := String(st["faction"])
	var att := String(army.get("faction", ""))
	var lvl := World.intel_level(army, 0.0)
	var text := Lang.t("%s is under siege: %s's army (%s) sits before the walls, day %d of the siege. The gates are shut.\n\nThe town will hold %d more days at most.") % [
		st["name"], World.lord_full(l) if not l.is_empty() else Lang.t("an army"), "%d" % int(army["size"]) if lvl >= 2 else World.rough_count(army),
		int(sg["days"]), maxi(1, int(sg["need"]) - int(sg["days"]))]
	var buttons: Array = []
	if not Company.is_enemy(def):
		text += Lang.t("\n\n[color=#9aa3b8]ATTACK THE BESIEGERS: the garrison sallies to fight beside you. %s will be grateful; %s won't.[/color]") % [Lore.FACTIONS[def]["short"], Lore.FACTIONS[att]["short"]]
		buttons.append([Lang.t("ATTACK THE BESIEGERS"), _relieve_town.bind(st, army)])
	if not Company.is_enemy(att) and (l.is_empty() or int(l["relation"]) >= 0):
		text += Lang.t("\n[color=#9aa3b8]HELP THE SIEGE: your men dig in beside his%s. It costs you with %s.[/color]") % [
			Lang.t(" and your guns batter the walls (it falls in a day)") if Company.guns > 0 else "", Lore.FACTIONS[def]["short"]]
		buttons.append([Lang.t("HELP THE SIEGE"), func():
			_popup_close()
			World.help_siege(id, 99 if Company.guns > 0 else 2)
			Company.change_standing(def, -20)
			Company.change_standing(att, 10)
			World.change_relation(l, 15)
			_push_toast(Lang.t("You dig in beside %s's men.") % (World.lord_short(l) if not l.is_empty() else Lang.t("the besiegers")))])
	buttons.append([Lang.t("LEAVE"), _popup_close])
	_scene("patrol", {"faction": att})
	_popup_open(Lang.t("%s, besieged") % st["name"], text, buttons)


func _relieve_town(st: Dictionary, army: Dictionary) -> void:
	_popup_close()
	var def := String(st["faction"])
	Company.change_standing(def, 15)
	Company.change_standing(String(army["faction"]), -25)
	World.change_relation(World.lord_of(army), -30)
	if not Company.contract.is_empty() and String(Company.contract["faction"]) == String(army["faction"]):
		World.change_relation(World.lord(int(Company.contract["lord"])), -40)
		_push_toast(Company.break_contract())
	_set_battle(army, false)
	var g := 20 if st["kind"] == "town" else 32
	Company.next_battle["allies"] = {"faction": def, "comp": World.party_comp({"kind": "patrol", "size": g}), "party": -1, "size": g, "lord": -1}
	_go(BATTLE)


## The nations and their lords: where you stand with each, and what you
## know of their armies.
func _show_lords() -> void:
	var t := ""
	for f in ["aurest", "vell"]:
		t += Lang.t("[b]%s[/b]: %s to you.\n") % [Lore.FACTIONS[f]["name"], Lang.t(Company.standing_word(f))]
		for l in World.lords:
			if l["faction"] != f:
				continue
			var state := ""
			var p := World.party_by_id(int(l["army"]))
			if p.is_empty():
				state = Lang.t("raising a new army")
			elif World.can_see(p):
				state = Lang.t("his army in sight: %s") % World.party_label(p, mini(World.intel_level(p), 2)).split("\n")[0]
			else:
				state = Lang.t("his army in the field")
			t += "   %s: %s; %s.\n" % [World.lord_full(l), World.relation_word(int(l["relation"])), state]
		t += "\n"
	if World.truce():
		t += Lang.t("[color=#9aa3b8]A truce holds between them until day %d.[/color]\n\n") % (1 + int(float(World.war["truce_until"]) / 24.0))
	var e := World.escorting()
	if not e.is_empty():
		t += Lang.t("[color=#c9a14a]%s marches with you until day %d.[/color]\n") % [World.party_name(e).split(" (")[0], 1 + int(float(e["escort_until"]) / 24.0)]
	var c: Dictionary = Company.contract
	if not c.is_empty():
		t += Lang.t("[color=#c9a14a]In the service of %s until day %d: %s (%d of %d). %d crowns a week.[/color]\n\n") % [
			c["lord_name"], int(c["until"]), Lang.t(Company.DUTIES[c["duty"]][0]), int(c["done"]), int(c["need"]), int(c["pay"])]
	else:
		t += Lang.t("[color=#9aa3b8]Meet a lord's army and you can offer him your service.[/color]\n")
	t += Lang.t("[color=#9aa3b8]Aurest and Vell are at war. Help a nation's men and it warms to you; attack them and it turns on you, and its patrols and armies hunt you.[/color]")
	_scene("patrol", {"faction": "aurest"})
	_popup_open(Lang.t("The lords of the land"), t, [[Lang.t("CLOSE"), _popup_close]], false)


## A nation's patrol is about to fight close by (a warband, or the other
## nation's men): join them, and their regiments fight beside yours (theirs
## to lead until you give them an order), or stay out of it.
func _on_fight_near(friend: Dictionary, foe: Dictionary) -> void:
	if friend["kind"] in World.CIVILIANS:
		_civilians_attacked(friend, foe)
		return
	var ff := String(friend["faction"])
	var fname: String = Lore.FACTIONS[ff]["name"]
	var foe_humans: bool = foe["faction"] != "lizards"
	var lvl_f := World.intel_level(friend)
	var lvl_e := World.intel_level(foe)
	var n_f := "%d" % int(friend["size"]) if lvl_f >= 2 else World.rough_count(friend)
	var n_e := "%d" % int(foe["size"]) if lvl_e >= 2 else World.rough_count(foe)
	var fl := World.lord_of(friend)
	if not fl.is_empty():
		fname = "%s (%s)" % [fname, World.lord_full(fl)]
	var text := Lang.t("Ahead of you %s men of %s are about to fight %s %s.") % [n_f, fname, n_e,
		(Lang.t("men of %s") % Lore.FACTIONS[foe["faction"]]["name"]) if foe_humans else Lang.t("lizards of a warband")]
	if lvl_e >= 3:
		text += Lang.t("\n\n[color=#c9a14a]The enemy: %s.[/color]") % World.comp_text(World.party_comp(foe))
	text += Lang.t("\n\nJoin them and their regiments fight beside yours: you can command them from the command view, and they follow their own officers until you do. %s would remember the help.") % Lore.FACTIONS[ff]["short"]
	if foe_humans:
		text += Lang.t("\n[color=#f08060]%s would remember it too.[/color]") % Lore.FACTIONS[foe["faction"]]["short"]
	var buttons: Array = [[Lang.t("JOIN %s") % String(Lore.FACTIONS[ff]["short"]).to_upper(), _join_fight.bind(friend, foe)],
		[Lang.t("STAY OUT"), _popup_close]]
	_scene("patrol", {"faction": ff})
	_popup_open(Lang.t("A fight ahead!"), text, buttons)
	if _test:
		print("  MAPTEST: a fight near: %s against %s (stayed out)" % [World.party_name(friend), World.party_name(foe)])
		_popup_close()


## Lizards falling on people on the road near you: go to their aid (a
## battle against the lizards, the caravan's guards on your side), or not.
func _civilians_attacked(friend: Dictionary, foe: Dictionary) -> void:
	var ours: bool = friend["kind"] == "detachment"
	var who := Lang.t("your own work party") if ours else World.party_name(friend).split(" (")[0]
	var n_e := "%d" % int(foe["size"]) if World.intel_level(foe) >= 2 else World.rough_count(foe)
	var text := Lang.t("Ahead of you %s lizards are falling on %s!") % [n_e, who]
	if ours:
		text += Lang.t("\n\nThey can't hold them off alone.")
	else:
		var ff := String(friend["faction"])
		text += Lang.t("\n\nGo to their aid and %s will remember it.") % Lore.FACTIONS.get(ff, {"short": "?"})["short"]
		if not Company.contract.is_empty() and String(Company.contract["duty"]) == "protect" and String(Company.contract["faction"]) == ff:
			text += Lang.t("\n[color=#c9a14a]It's what %s pays you for.[/color]") % Company.contract["lord_name"]
	var buttons: Array = [[Lang.t("TO THEIR AID!"), func():
			_popup_close()
			_set_battle(foe, false)
			Company.next_battle["helped"] = {"kind": String(friend["kind"]), "faction": String(friend["faction"]), "party": int(friend["id"])}
			if friend["kind"] in ["caravan", "traders"]:
				# The caravan's guards fight beside you.
				var guards := World.party_comp(friend)
				if not guards.is_empty():
					Company.next_battle["allies"] = {"faction": String(friend["faction"]), "comp": guards, "party": int(friend["id"]),
						"size": int(friend["size"]), "lord": -1}
			_go(BATTLE)],
		[Lang.t("LEAVE THEM"), _popup_close]]
	_scene("villagers" if not friend["kind"] in ["caravan", "traders"] else "caravan", {"faction": friend.get("faction", "aurest")})
	_popup_open(Lang.t("They need help!"), text, buttons)
	if _test:
		print("  MAPTEST: lizards on %s (left them)" % who)
		_popup_close()


func _join_fight(friend: Dictionary, foe: Dictionary) -> void:
	_popup_close()
	var ff := String(friend["faction"])
	Company.change_standing(ff, 15)
	World.change_relation(World.lord_of(friend), 15)
	if foe["faction"] != "lizards":
		Company.change_standing(String(foe["faction"]), -25)
		World.change_relation(World.lord_of(foe), -30)
		if not Company.contract.is_empty() and String(Company.contract["faction"]) == String(foe["faction"]):
			World.change_relation(World.lord(int(Company.contract["lord"])), -40)
			_push_toast(Company.break_contract())
	_set_battle(foe, false)
	Company.next_battle["allies"] = {"faction": ff, "comp": World.party_comp(friend), "party": int(friend["id"]),
		"size": int(friend["size"]), "lord": int(friend.get("lord", -1))}
	_go(BATTLE)


## A hostile party (a lizard warband, or a patrol of a nation you've made an
## enemy of) has caught you.
func _on_encounter(p: Dictionary) -> void:
	if World.camping:
		_camp_attacked(p)
		return
	var c := World.cell()
	var cover: bool = World.gen.t(c.x, c.y) in [T.FOREST, T.SWAMP]
	var chance := clampf(0.3 + (0.25 if cover else 0.0) + (World.party_pace() - 0.85) + Company.Officer.slip_bonus(), 0.1, 0.85)
	var where := Lang.t("in the trees") if cover else Lang.t("in the open")
	# Seen coming, there's time to form up as planned; out of nowhere, there isn't.
	var ambush := World.hours - float(p.get("seen_at", -99.0)) > 1.5
	var lvl := World.intel_level(p, 0.0)
	var count := "%d" % int(p["size"]) if lvl >= 2 else World.rough_count(p)
	var humans: bool = p["faction"] != "lizards"
	var who := Lang.t("Soldiers of %s have") % Lore.FACTIONS[p["faction"]]["name"] if humans else Lang.t("They've")
	if not World.lord_of(p).is_empty():
		who = Lang.t("The army of %s has") % World.lord_full(World.lord_of(p))
	var text := Lang.t("%s caught up with you %s. %s of them against %d fit men.") % [who, where, count, Company.fit_men().size()]
	if lvl >= 3:
		text += Lang.t("\n\n[color=#c9a14a]You make them out: %s.[/color]") % World.comp_text(World.party_comp(p))
	elif Company.Officer.skill("tactics") < 3:
		text += Lang.t("\n\n[color=#9aa3b8](With more Tactics you'd read what they are, not just how many.)[/color]")
	if ambush:
		text += Lang.t("\n\n[color=#f08060]AMBUSH! No time to form up: the men will be scattered.[/color]")
	else:
		text += Lang.t("\n\nYou saw them coming: there's time to form up (PLAN to change the formation).")
	text += Lang.t("\n\nSlip away? About %d%% chance; fail and you fight anyway, caught off guard.") % int(chance * 100)
	var buttons: Array = []
	if not ambush:
		buttons.append([Lang.t("PLAN"), _plan_fight.bind(p)])
	buttons.append([Lang.t("FIGHT"), _fight.bind(p, ambush)])
	buttons.append([Lang.t("SLIP AWAY"), _slip.bind(p, chance)])
	_scene("ambush" if ambush else ("patrol" if humans else "warband"), {"faction": p.get("faction", "vell")})
	_popup_open("%s!" % World.party_label(p, mini(World.intel_level(p, 0.0), 2)), text, buttons)


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
		"enemy_kind": "lizards" if p["faction"] == "lizards" else "humans", "faction": String(p["faction"]),
		"comp": World.party_comp(p), "camp": true, "spotted": spotted, "night": true, "watch": ids}
	var esc := _escort_allies(String(p["faction"]))
	if not esc.is_empty():
		Company.next_battle["allies"] = esc
	Company.results_unseen = false
	var text := ""
	var buttons: Array = []
	if spotted:
		text = Lang.t("Night, by the fire. %s on watch hear something in the dark, then see the eyes catch the firelight, and raise the alarm. The men are throwing off their blankets and reaching for their muskets.\n\n%d of them against %d fit men.") % [
			Lang.t(" and ").join(names), int(p["size"]), fit.size()]
		text += Lang.t("\n\nAbandon the camp and slip away in the dark? About %d%% chance; fail and you fight anyway, worse placed.") % int(100 * (0.35 + Company.Officer.slip_bonus()))
		buttons.append([Lang.t("STAND TO!"), _camp_fight.bind(p)])
		buttons.append([Lang.t("SLIP AWAY"), _slip.bind(p, 0.35 + Company.Officer.slip_bonus())])
		_scene("camp_attack", {"time": "night"})
		_popup_open(Lang.t("The watch has seen them!"), text, buttons)
	else:
		text = Lang.t("Night. %s on watch never saw them come. You wake to screaming: they're already in among the bedrolls, %d of them, and your men are still asleep.") % [
			Lang.t(" and ").join(names), int(p["size"])]
		buttons.append([Lang.t("UP! TO ARMS!"), _camp_fight.bind(p)])
		_scene("camp_attack", {"time": "night"})
		_popup_open(Lang.t("They're in the camp!"), text, buttons)


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
	var humans: bool = p["faction"] != "lizards"
	var esc := _escort_allies(String(p["faction"]))
	Company.next_battle = {"enemy": int(p["size"]), "terrain": World.gen.t(c.x, c.y), "party": int(p["id"]),
		"ambush": ambush, "enemy_kind": "humans" if humans else "lizards", "faction": String(p["faction"]),
		"map": World.battle_map_here(), "comp": World.party_comp(p), "lord": int(p.get("lord", -1)),
		"party_name": World.party_name(p).split(" (")[0]}
	if not esc.is_empty():
		Company.next_battle["allies"] = esc
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
		_push_toast(Lang.t("You slip away from them."))
	else:
		_push_toast(Lang.t("They're too quick!"))
		_fight(p, true)


## Back from a battle the map started: a won fight destroys the warband; a
## lost one leaves it, and you fall back.
func _apply_battle_result() -> void:
	if Company.next_battle.is_empty():
		return
	var id := int(Company.next_battle["party"])
	var r: Dictionary = Company.last_result
	var nb: Dictionary = Company.next_battle
	if int(nb.get("assault", -1)) >= 0 or int(nb.get("sortie", -1)) >= 0:
		var nid := int(nb.get("assault", nb.get("sortie", -1)))
		var won := bool(r.get("won", false))
		var assault := int(nb.get("assault", -1)) >= 0
		if assault:
			World.nest_fought(nid, int(r.get("slain", 0)), won)
			if won:
				var cp := Company.contract_progress("nest", "lizards")
				if cp != "":
					_push_toast(cp)
			_push_toast(Lang.t("%s burns!") % World.settlement(nid)["name"] if won else Lang.t("The assault is thrown back."))
		else:
			# A sortie: the dead are gone; if they won, the rest go back in.
			World.nest_fought(nid, 0, false, 0 if won else maxi(0, int(nb["enemy"]) - int(r.get("slain", 0))))
			_push_toast(Lang.t("The sortie is beaten off.") if won else Lang.t("They drive you from your lines."))
			if not won:
				World.lift_siege(nid)
		if not won:
			var s := World.settlement(nid)
			World.pos += (World.pos - Vector2(s["x"], s["y"])).normalized() * 5.0
		Company.next_battle = {}
		Company.save()
		World.save()
		return
	var p := World.party_by_id(id)
	if bool(r.get("won", false)) and not p.is_empty():
		var cp2 := Company.contract_progress(String(p["kind"]), String(p["faction"]))
		if cp2 != "":
			_push_toast(cp2)
	if nb.has("standing_note"):
		_push_toast(String(nb["standing_note"]))
	var al: Dictionary = nb.get("allies", {})
	if not al.is_empty():
		var fp := World.party_by_id(int(al["party"]))
		if not fp.is_empty():
			var left := int(r.get("allies_left", 0))
			if left <= 1:
				World.remove_party(int(al["party"]))
			else:
				fp["size"] = left
		if bool(r.get("won", false)):
			Company.change_standing(String(al["faction"]), 10)
			var al_lord := World.lord(int(al.get("lord", -1)))
			World.change_relation(al_lord, 15)
			if not al_lord.is_empty():
				_push_toast(Lang.t("%s will remember you stood with him.") % World.lord_short(al_lord))
			else:
				_push_toast(Lang.t("%s will remember you stood with them.") % Lore.FACTIONS[al["faction"]]["name"])
	var helped: Dictionary = nb.get("helped", {})
	if not helped.is_empty() and bool(r.get("won", false)):
		var hf := String(helped["faction"])
		if hf in ["aurest", "vell", "dwarves"]:
			Company.change_standing(hf, 8)
			var cp3 := Company.contract_progress("protect", hf)
			if cp3 != "":
				_push_toast(cp3)
		_push_toast(Lang.t("You saved them. They won't forget it."))
	if bool(r.get("won", false)):
		World.remove_party(id)
		_push_toast(Lang.t("The warband is destroyed.") if String(nb.get("enemy_kind", "lizards")) == "lizards" else Lang.t("They're beaten: the survivors scatter."))
	elif not p.is_empty():
		var away := (World.pos - Vector2(p["x"], p["y"])).normalized()
		World.pos += away * 5.0
		p["wait"] = 6.0
		_push_toast(Lang.t("You fall back, leaving the field to them."))
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
		var besiege: Button = null
		for b in _popup_buttons.get_children():
			if b is Button and b.text == "BESIEGE A DAY":
				besiege = b
		if besiege != null:
			# At the nest: sit down before it for a day, then go.
			if int(get_meta("sieged", 0)) == 0:
				set_meta("sieged", 1)
				print("MAPTEST: besieging ", _popup_title.text)
				besiege.emit_signal("pressed")
			else:
				print("MAPTEST: leaving the siege; nest now ", World.nest(int(World.gen.stash_nest)))
				last.emit_signal("pressed")
				for l in World.lords:
					var ap := World.party_by_id(int(l["army"]))
					print("  LORD ", World.lord_full(l), " army ", World.party_name(ap) if not ap.is_empty() else "none (back at %d)" % int(l["back_at"]), " at ", [int(ap.get("x", 0)), int(ap.get("y", 0))])
				var raided := 0
				for id in World.places:
					if World.is_raided(int(id)):
						raided += 1
				print("  raided places now: ", raided, "; news: ", World.log.slice(-6))
				for st2 in World.gen.settlements:
					var sg2 := World.siege_of(int(st2["id"]))
					if not sg2.is_empty():
						print("  SIEGE ", st2["name"], " ", sg2["days"], "/", sg2["need"])
					if World.places[int(st2["id"])].has("owner"):
						print("  TAKEN ", st2["name"], " now ", st2["faction"])
				print("MAPTEST END at the nest ", World.clock())
				get_tree().quit()
			return
		if _popup_title.text.ends_with("!") and n > 1:
			print("  (would fight; slipping away for the test)")
			_popup_buttons.get_child(n - 1).emit_signal("pressed") # slip away
		elif last.text == Lang.t("LEAVE") and n > 2:
			_popup_buttons.get_child(0).emit_signal("pressed") # buy food once
			last.emit_signal("pressed")
		else:
			_popup_buttons.get_child(0).emit_signal("pressed") # camp / the first choice / carry on
		return
	if int(get_meta("scouted", 0)) == 0 and _test_t > 1.0:
		set_meta("scouted", 1)
		var sc := World.send_scouts(Vector2(1, -1), 2, World.scout_candidates().slice(0, 2))
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
			1, 2, 3, 4, 5, 6, 7, 8:
				var nest: Dictionary = World.settlement(World.gen.stash_nest)
				print("MAPTEST: ", World.clock(), " at ", World.cell(), " -> stash nest ", nest["name"])
				World.go_to(Vector2i(nest["x"], nest["y"]), {"kind": "settlement", "id": int(nest["id"])})
			_:
				var kinds := {}
				for pp in World.parties:
					kinds[pp["kind"]] = kinds.get(pp["kind"], 0) + 1
				print("  parties: ", kinds, " stores ", Company.stores)
				print("MAPTEST END ", World.clock(), " men ", Company.roster.size(), " parties ", World.parties.size(),
					Lang.t(" explored "), Array(World.explored).count(1), Lang.t(" fps "), Engine.get_frames_per_second())
				get_tree().quit()
