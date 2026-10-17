extends RefCounted
## Scenery built from primitives, shared by the cutscene and the battle:
## the ship (whole or wrecked), longboats, cannon, earthworks, rocks, and the
## sea. Each function returns a Node3D ready to add to the scene.

const WOOD_DARK := Color(0.24, 0.16, 0.1)
const WOOD := Color(0.38, 0.26, 0.15)
const SAIL := Color(0.86, 0.83, 0.74)
const BRONZE := Color(0.42, 0.33, 0.2)
const IRON := Color(0.16, 0.16, 0.18)
const SAND := Color(0.68, 0.6, 0.42)
const EARTH := Color(0.42, 0.33, 0.22)
const WICKER := Color(0.5, 0.4, 0.24)
const ROCK := Color(0.3, 0.3, 0.32)

const SEA_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep : source_color = vec4(0.07, 0.16, 0.22, 1.0);
uniform vec4 crest : source_color = vec4(0.45, 0.55, 0.6, 1.0);
uniform float height = 0.4;
uniform float speed = 1.0;
varying float h;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * speed;
	h = sin(w.x * 0.11 + t * 1.3) * 0.6 + sin(w.z * 0.17 - t * 1.7) * 0.5 + sin((w.x + w.z) * 0.31 + t * 2.3) * 0.25;
	VERTEX.y += h * height;
}

void fragment() {
	ALBEDO = mix(deep.rgb, crest.rgb, clamp(h * 0.35 + 0.35, 0.0, 1.0));
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
}
"""


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


static func _box(parent: Node3D, size: Vector3, c: Color, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(c)
	mi.mesh = b
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, c: Color, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 10
	cm.material = _mat(c)
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## A wave-animated sea plane. `height` and `speed` set the weather.
static func sea(size: float, height: float, speed: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var sh := Shader.new()
	sh.code = SEA_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("height", height)
	mat.set_shader_parameter("speed", speed)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A three-masted troopship, bow toward -Z. Children named "main_mast" and
## "fore_mast" so a cutscene can bring them down.
static func ship() -> Node3D:
	var s := Node3D.new()
	# Hull: a long box, a tapered bow, a raised stern castle, a dark wale.
	_box(s, Vector3(5.0, 3.2, 26.0), WOOD_DARK, Vector3(0, 0.6, 1.0))
	_box(s, Vector3(3.6, 3.0, 5.0), WOOD_DARK, Vector3(0, 0.8, -13.5), Vector3(0, 0, 0))
	_box(s, Vector3(2.0, 2.4, 4.0), WOOD_DARK, Vector3(0, 1.2, -16.5))
	_box(s, Vector3(5.1, 0.35, 26.2), Color(0.12, 0.1, 0.08), Vector3(0, 1.4, 1.0))
	_box(s, Vector3(5.1, 0.25, 26.2), Color(0.6, 0.5, 0.2), Vector3(0, 0.9, 1.0)) # yellow gunport band
	_box(s, Vector3(4.8, 0.2, 25.0), WOOD, Vector3(0, 2.25, 1.0)) # deck
	_box(s, Vector3(5.0, 2.4, 6.0), WOOD_DARK, Vector3(0, 3.3, 11.0)) # stern castle
	_box(s, Vector3(0.25, 0.25, 7.0), WOOD, Vector3(0, 2.6, -19.0), Vector3(-18, 0, 0)) # bowsprit
	var masts := {"fore_mast": -7.5, "main_mast": 1.5, "mizzen_mast": 8.5}
	for name in masts:
		var m := Node3D.new()
		m.name = name
		m.position = Vector3(0, 2.3, masts[name])
		s.add_child(m)
		var h := 16.0 if name == "main_mast" else 13.0
		_cyl(m, 0.18, 0.28, h, WOOD, Vector3(0, h * 0.5, 0))
		for k in 2:
			var y := h * (0.45 + 0.35 * k)
			var w := 9.0 - k * 2.5
			_box(m, Vector3(w, 0.18, 0.18), WOOD, Vector3(0, y, 0))
			_box(m, Vector3(w * 0.92, h * 0.28, 0.08), SAIL, Vector3(0, y - h * 0.15, 0.15))
	return s


## A ship's boat with a handful of men and oars.
static func longboat() -> Node3D:
	var b := Node3D.new()
	_box(b, Vector3(1.6, 0.6, 5.0), WOOD, Vector3(0, 0.2, 0))
	_box(b, Vector3(1.0, 0.6, 1.2), WOOD, Vector3(0, 0.2, -2.8), Vector3(0, 45, 0))
	for i in 4:
		var z := -1.6 + i * 1.0
		_box(b, Vector3(0.36, 0.7, 0.3), Color(0.16, 0.24, 0.55), Vector3(0.0, 0.85, z))
		_box(b, Vector3(0.22, 0.22, 0.22), Color(0.85, 0.66, 0.5), Vector3(0.0, 1.3, z))
		_box(b, Vector3(3.6, 0.06, 0.06), WOOD, Vector3(0, 0.6, z), Vector3(0, 0, 8))
	return b


## A field gun on its carriage, barrel toward -Z. The barrel node is named
## "barrel" (for recoil); its muzzle is at local (0, 0.95, -1.9).
static func cannon() -> Node3D:
	var g := Node3D.new()
	_box(g, Vector3(0.7, 0.35, 2.2), WOOD, Vector3(0, 0.55, 0.5)) # carriage
	_box(g, Vector3(0.4, 0.2, 1.8), WOOD, Vector3(0, 0.35, 1.7), Vector3(-12, 0, 0)) # trail
	for side in [-1.0, 1.0]:
		_cyl(g, 0.55, 0.55, 0.12, WOOD_DARK, Vector3(side * 0.48, 0.55, -0.1), Vector3(0, 0, 90))
		_cyl(g, 0.12, 0.12, 0.16, IRON, Vector3(side * 0.48, 0.55, -0.1), Vector3(0, 0, 90))
	var barrel := Node3D.new()
	barrel.name = "barrel"
	barrel.position = Vector3(0, 0.95, 0.0)
	g.add_child(barrel)
	_cyl(barrel, 0.13, 0.2, 2.4, BRONZE, Vector3(0, 0, -0.6), Vector3(90, 0, 0))
	_cyl(barrel, 0.16, 0.16, 0.12, BRONZE.darkened(0.2), Vector3(0, 0, -1.78), Vector3(90, 0, 0))
	_box(barrel, Vector3(0.14, 0.14, 0.2), BRONZE, Vector3(0, 0, 0.66))
	return g


## A kingdom's catapult (a mangonel): a heavy frame on four wheels, a
## throwing arm on an axle between two uprights ("arm", turning about X:
## back and down when wound, flung up and forward to throw), a sling cup at
## its end ("cup"), and a windlass at the back.
static func catapult() -> Node3D:
	var g := Node3D.new()
	for side in [-1.0, 1.0]:
		_box(g, Vector3(0.18, 0.22, 3.2), WOOD_DARK, Vector3(side * 0.7, 0.45, 0.2)) # the sills
		_box(g, Vector3(0.16, 1.5, 0.18), WOOD, Vector3(side * 0.6, 1.25, -0.4)) # the uprights
		_box(g, Vector3(0.1, 1.5, 0.12), WOOD, Vector3(side * 0.6, 1.1, 0.1), Vector3(-35, 0, 0)) # braces
		for z in [-0.9, 1.3]:
			_cyl(g, 0.34, 0.34, 0.1, WOOD_DARK, Vector3(side * 0.82, 0.34, z), Vector3(0, 0, 90))
	_box(g, Vector3(1.5, 0.16, 0.18), WOOD, Vector3(0, 0.45, -1.3))
	_box(g, Vector3(1.5, 0.16, 0.18), WOOD, Vector3(0, 0.45, 1.7))
	_box(g, Vector3(1.4, 0.14, 0.16), WOOD, Vector3(0, 1.9, -0.4)) # the stop beam the arm strikes
	_cyl(g, 0.12, 0.12, 1.3, WOOD_DARK, Vector3(0, 0.75, 1.5), Vector3(0, 0, 90)) # the windlass
	var arm := Node3D.new()
	arm.name = "arm"
	arm.position = Vector3(0, 0.95, -0.2)
	g.add_child(arm)
	_cyl(arm, 0.08, 0.08, 1.4, IRON, Vector3.ZERO, Vector3(0, 0, 90)) # the axle
	_box(arm, Vector3(0.16, 0.16, 3.0), WOOD, Vector3(0, 0, 1.3)) # the arm, pointing back
	var cup := Node3D.new()
	cup.name = "cup"
	cup.position = Vector3(0, 0.12, 2.75)
	arm.add_child(cup)
	_box(cup, Vector3(0.5, 0.12, 0.5), WOOD_DARK, Vector3.ZERO)
	return g


## A sand-and-earth rampart `length` metres long along X, with a row of
## wicker gabions on top and gaps (embrasures) at `gaps` (x positions).
static func earthwork(length: float, gaps: Array) -> Node3D:
	var e := Node3D.new()
	var seg := 2.0
	var n := int(length / seg)
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * seg
		var in_gap := false
		for gx in gaps:
			if absf(x - float(gx)) < 1.4:
				in_gap = true
		var h := 0.4 if in_gap else 0.8
		# Front slope, crest, back slope.
		_box(e, Vector3(seg + 0.05, h, 1.6), EARTH.lerp(SAND, 0.3), Vector3(x, h * 0.4, -0.6), Vector3(-28, 0, 0))
		_box(e, Vector3(seg + 0.05, h, 1.0), EARTH, Vector3(x, h * 0.5, 0.2))
		if not in_gap and i % 2 == 0:
			_cyl(e, 0.4, 0.4, 0.55, WICKER, Vector3(x, h + 0.25, 0.25))
	return e


## A cluster of rocks around `at`.
static func rocks(at: Vector3, count: int, size: float, rng: RandomNumberGenerator) -> Node3D:
	var r := Node3D.new()
	r.position = at
	for i in count:
		var s := size * rng.randf_range(0.5, 1.2)
		_box(r, Vector3(s, s * rng.randf_range(0.6, 1.4), s * rng.randf_range(0.7, 1.3)),
			ROCK.lerp(Color(0.2, 0.2, 0.22), rng.randf()),
			Vector3(rng.randf_range(-size, size), s * 0.3, rng.randf_range(-size, size)),
			Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 90), rng.randf_range(-20, 20)))
	return r


## The company's baggage wagon: a bed on four wheels under a canvas tilt,
## with shafts in front for the porters. Faces -Z.
static func wagon() -> Node3D:
	var w := Node3D.new()
	_box(w, Vector3(1.5, 0.45, 3.0), WOOD, Vector3(0, 0.85, 0)) # bed
	_box(w, Vector3(1.55, 0.08, 3.05), WOOD_DARK, Vector3(0, 1.1, 0))
	for z in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			_cyl(w, 0.45, 0.45, 0.1, WOOD_DARK, Vector3(side * 0.8, 0.45, z), Vector3(0, 0, 90))
	# The canvas tilt over hoops, and crates sticking out the back.
	var tilt := _cyl(w, 0.85, 0.85, 2.8, SAIL.darkened(0.08), Vector3(0, 1.25, 0), Vector3(90, 0, 0))
	tilt.scale = Vector3(1.0, 1.0, 0.75)
	_box(w, Vector3(1.5, 0.2, 2.8), SAIL.darkened(0.08), Vector3(0, 1.2, 0))
	_box(w, Vector3(0.6, 0.5, 0.5), WOOD, Vector3(-0.35, 1.35, 1.45), Vector3(0, 12, 0))
	_box(w, Vector3(0.5, 0.45, 0.45), Color(0.4, 0.3, 0.2), Vector3(0.38, 1.3, 1.5), Vector3(0, -8, 0))
	for side in [-1.0, 1.0]:
		_box(w, Vector3(0.08, 0.08, 2.0), WOOD, Vector3(side * 0.45, 0.75, -2.4), Vector3(-6, 0, 0)) # shafts
	return w
