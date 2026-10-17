extends RefCounted
## The ground of a field battle (Tests > Field battle): its shape, what
## stops a man or a shot, and how it looks.
##
## Maps:
##   flat    open fields with a gentle roll, woods round the edges
##   hills   a big hill on your left, a smaller one on your right, a ridge
##           behind the enemy and a valley between
##   river   a river across the field between the armies: deep but for a
##           stone bridge on your left and a ford on your right
##   town    a village at the crossroads in the middle: houses (walls stop
##           men and shot), lanes between them, a church
##   forest  woods on both flanks and a copse in the middle (slow going)
##
## Everything is a heightmap at RES metres (bilinear between samples) plus a
## nav grid of the same cells: free, slow (water at the ford, woods) or
## blocked (deep water, houses). Regiments path round blocked cells with
## Godot's AStarGrid2D; men slide along them; shots stop in walls and hills.

const Look := preload("res://scripts/look.gd")
const Props := preload("res://scripts/props.gd")

const HALF := 150.0 # the field: x and z in [-HALF, HALF]
const OUTER := 280.0 # the terrain mesh runs on to here (scenery)
const RES := 2.0
const N := 151 # samples a side: HALF * 2 / RES + 1
const MAPS := ["flat", "hills", "river", "town", "forest"]
const MAP_NAMES := {"flat": "Open field", "hills": "Hills", "river": "River crossing", "town": "Village", "forest": "Woods"}

const FREE := 0
const SLOW := 1
const BLOCKED := 2

const WATER := -0.75 # the river's surface
const BRIDGE_X := -40.0
const BRIDGE_HALF_W := 4.0
const FORD_X := 56.0

var kind := "flat"
var heights := PackedFloat32Array() # N * N, row z, column x
var nav := PackedByteArray() # N * N cells (cell (i, j) covers sample (i, j) to (i+1, j+1))
var tops := PackedFloat32Array() # roof height over a cell (houses), or -INF-ish
var houses: Array = [] # [Rect2, height, colour]
var woods: Array = [] # [Vector2 centre, radius]
var has_water := false
var astar: AStarGrid2D = null
var _rng := RandomNumberGenerator.new()


func _init(map_kind: String) -> void:
	kind = map_kind if map_kind in MAPS else "flat"
	_rng.seed = hash("field:" + kind)
	if kind == "town":
		_lay_out_village()
	if kind == "forest":
		woods = [[Vector2(-78, 5), 34.0], [Vector2(82, -12), 30.0], [Vector2(8, -6), 16.0], [Vector2(-20, 85), 14.0], [Vector2(40, -88), 18.0]]
	elif kind in ["flat", "hills"]:
		woods = [[Vector2(-118, -40), 22.0], [Vector2(122, 30), 20.0]]
	has_water = kind == "river"
	heights.resize(N * N)
	nav.resize(N * N)
	tops.resize(N * N)
	for j in N:
		for i in N:
			var x := -HALF + i * RES
			var z := -HALF + j * RES
			heights[j * N + i] = _raw(x, z)
			tops[j * N + i] = -1000.0
	for j in N:
		for i in N:
			var c := Vector2(-HALF + (i + 0.5) * RES, -HALF + (j + 0.5) * RES)
			var v := FREE
			if has_water:
				var bed := _raw(c.x, c.y)
				if bed < WATER - 0.55 and not _on_bridge(c.x, c.y):
					v = BLOCKED
				elif bed < WATER + 0.05 and not _on_bridge(c.x, c.y):
					v = SLOW
			for w in woods:
				if c.distance_to(w[0]) < float(w[1]):
					v = maxi(v, SLOW)
			nav[j * N + i] = v
	for h in houses:
		var r: Rect2 = h[0]
		var g := r.grow(0.4)
		for j in range(_ci(g.position.y), _ci(g.end.y) + 1):
			for i in range(_ci(g.position.x), _ci(g.end.x) + 1):
				if i >= 0 and j >= 0 and i < N and j < N:
					var cc := Vector2(-HALF + (i + 0.5) * RES, -HALF + (j + 0.5) * RES)
					if g.has_point(cc):
						nav[j * N + i] = BLOCKED
						tops[j * N + i] = height(cc.x, cc.y) + float(h[1])
	if kind in ["river", "town", "forest"]:
		_build_astar()


static func _ci(v: float) -> int:
	return floori((v + HALF) / RES)


# ---------------------------------------------------------------- shape

## The ground's height from the map's formula (before sampling).
func _raw(x: float, z: float) -> float:
	var roll := 0.45 * sin(x * 0.031 + 1.3) * cos(z * 0.027) + 0.25 * sin(x * 0.09 + z * 0.07)
	match kind:
		"hills":
			var h := roll * 1.6
			h += _bump(x, z, -62.0, -6.0, 42.0, 16.0) # the big hill, your left
			h += _bump(x, z, -40.0, -30.0, 22.0, 5.0) # its shoulder
			h += _bump(x, z, 68.0, 30.0, 30.0, 9.0) # your right, near your line
			h += _bump(x, z, 10.0, -98.0, 70.0, 7.0) # their ridge
			h += _bump(x, z, -12.0, 96.0, 55.0, 4.0) # the rise behind you
			h -= _bump(x, z, 12.0, -10.0, 34.0, 1.8) # the valley floor
			return h
		"river":
			var zc := river_z(x)
			var d := absf(z - zc)
			var depth := 2.5
			# The ford: wide and shallow.
			var ford := 1.0 - smoothstep(6.0, 14.0, absf(x - FORD_X))
			depth = lerpf(depth, 1.05, ford)
			var half := lerpf(7.5, 11.0, ford)
			var k := 1.0 - smoothstep(half, half + 5.0, d)
			var bank := 0.35 * smoothstep(half + 5.0, half + 14.0, d)
			return roll * 0.7 + bank - depth * k
		"town":
			return roll * 0.5
		"forest":
			return roll * 1.1 + _bump(x, z, 0.0, -100.0, 60.0, 2.5)
	return roll


static func _bump(x: float, z: float, cx: float, cz: float, r: float, h: float) -> float:
	var d2 := ((x - cx) * (x - cx) + (z - cz) * (z - cz)) / (r * r)
	return h * exp(-d2 * 1.6)


## Where the river runs (its centre line).
static func river_z(x: float) -> float:
	return 6.0 * sin(x * 0.018) + 3.0 * sin(x * 0.05 + 1.0)


func _on_bridge(x: float, z: float) -> bool:
	return has_water and absf(x - BRIDGE_X) < BRIDGE_HALF_W and absf(z - river_z(BRIDGE_X)) < 17.0


## The deck: level across the water, ramps down to the banks.
func _deck(x: float, z: float) -> float:
	var d := absf(z - river_z(BRIDGE_X))
	return lerpf(0.9, 0.2, smoothstep(9.0, 17.0, d))


## Height of the ground (or the bridge deck) at x, z.
func height(x: float, z: float) -> float:
	if has_water and _on_bridge(x, z):
		return maxf(_deck(x, z), _sample(x, z))
	return _sample(x, z)


func _sample(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / RES, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / RES, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func at(p: Vector3) -> float:
	return height(p.x, p.z)


## What a shot or a line of sight runs into: the ground, or a roof.
func solid_y(p: Vector3) -> float:
	var g := height(p.x, p.z)
	if houses.is_empty():
		return g
	var i := _ci(p.x)
	var j := _ci(p.z)
	if i < 0 or j < 0 or i >= N or j >= N:
		return g
	return maxf(g, tops[j * N + i])


func cell(p: Vector3) -> int:
	var i := _ci(p.x)
	var j := _ci(p.z)
	if i < 0 or j < 0 or i >= N - 1 or j >= N - 1:
		return BLOCKED
	return nav[j * N + i]


func blocked(p: Vector3) -> bool:
	return cell(p) == BLOCKED


## How fast a man goes here, heading `dir` (flat, unit): slow in the ford and
## in woods, slower uphill, a little quicker down.
func speed_factor(p: Vector3, dir: Vector3) -> float:
	var f := 1.0
	var c := cell(p)
	if c == SLOW:
		f = 0.5 if has_water and height(p.x, p.z) < WATER else 0.68
	var ahead := height(p.x + dir.x * 1.5, p.z + dir.z * 1.5) - height(p.x, p.z)
	var slope := ahead / 1.5
	if slope > 0.0:
		f *= maxf(0.45, 1.0 - slope * 1.6)
	else:
		f *= minf(1.15, 1.0 - slope * 0.4)
	return f


## Move from `p` by `dv`, sliding along anything in the way; returns the new
## position on the ground.
func step(p: Vector3, dv: Vector3) -> Vector3:
	var n := Vector3(p.x + dv.x, 0.0, p.z + dv.z)
	if blocked(n):
		var nx := Vector3(p.x + dv.x, 0.0, p.z)
		var nz := Vector3(p.x, 0.0, p.z + dv.z)
		if not blocked(nx):
			n = nx
		elif not blocked(nz):
			n = nz
		elif blocked(Vector3(p.x, 0.0, p.z)):
			n = Vector3(p.x + dv.x, 0.0, p.z + dv.z) # already inside: let him out
		else:
			n = Vector3(p.x, 0.0, p.z)
	n.x = clampf(n.x, -HALF + 1.0, HALF - 1.0)
	n.z = clampf(n.z, -HALF + 1.0, HALF - 1.0)
	n.y = height(n.x, n.z)
	return n


## Is there a clear line from a to b (both above the ground)? Samples every
## couple of metres against hills and houses.
func clear_line(a: Vector3, b: Vector3) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 2.5)
	for s in range(1, steps):
		var t := float(s) / steps
		var p := a.lerp(b, t)
		if p.y < solid_y(p) + 0.15:
			return false
	return true


## Is a nearest free spot to p (searching outward), on the ground.
func free_spot(p: Vector3) -> Vector3:
	if not blocked(p):
		return Vector3(p.x, height(p.x, p.z), p.z)
	for r in range(1, 12):
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a), 0, sin(a)) * r * RES
			if not blocked(q):
				return Vector3(q.x, height(q.x, q.z), q.z)
	return p


# ---------------------------------------------------------------- paths

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, N - 1, N - 1)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for j in N - 1:
		for i in N - 1:
			var v := nav[j * N + i]
			if v == BLOCKED:
				astar.set_point_solid(Vector2i(i, j), true)
			elif v == SLOW:
				astar.set_point_weight_scale(Vector2i(i, j), 1.8)


## Can a column walk straight from a to b? (Every metre or so.)
func straight(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(1, int(d / 1.5))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		if blocked(p):
			return false
	return true


## Waypoints from a to b round anything blocked (the last is b, or the free
## spot nearest it).
func path(a: Vector3, b: Vector3) -> Array:
	b = free_spot(b)
	if astar == null or straight(a, b):
		return [b]
	var fa := free_spot(a)
	var ia := Vector2i(clampi(_ci(fa.x), 0, N - 2), clampi(_ci(fa.z), 0, N - 2))
	var ib := Vector2i(clampi(_ci(b.x), 0, N - 2), clampi(_ci(b.z), 0, N - 2))
	var ids: Array[Vector2i] = astar.get_id_path(ia, ib, true)
	if ids.is_empty():
		return [b]
	var pts: Array = []
	for id in ids:
		var x := -HALF + (id.x + 0.5) * RES
		var z := -HALF + (id.y + 0.5) * RES
		pts.append(Vector3(x, height(x, z), z))
	pts[pts.size() - 1] = b
	# Pull the string tight: skip every point we can walk past in a line.
	var out: Array = []
	var from := a
	var k := 0
	while k < pts.size():
		var far := k
		for m in range(pts.size() - 1, k, -1):
			if straight(from, pts[m]):
				far = m
				break
		out.append(pts[far])
		from = pts[far]
		k = far + 1
	return out


# ---------------------------------------------------------------- the village

func _lay_out_village() -> void:
	# Two lanes crossing at the middle (along x and along z), cottages along
	# them in short rows, a church on the far-left corner of the crossroads.
	var lane := 4.5
	houses.append([Rect2(-26, -30, 11, 17), 7.0, Color(0.72, 0.7, 0.64)]) # the church
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# Along the x lane (facing it), then along the z lane.
			var t := 9.0
			while t < 58.0:
				var w := _rng.randf_range(6.0, 8.5)
				var d := _rng.randf_range(5.5, 7.0)
				var cx: float = sx * (t + w * 0.5)
				var cz: float = sz * (lane + 1.5 + d * 0.5)
				t += w + _rng.randf_range(2.5, 6.0)
				if _rng.randf() < 0.2:
					continue
				_add_house(Vector2(cx, cz), Vector2(w, d))
			t = 12.0
			while t < 50.0:
				var w2 := _rng.randf_range(6.0, 8.0)
				var d2 := _rng.randf_range(5.5, 7.0)
				var cz2: float = sz * (t + w2 * 0.5)
				var cx2: float = sx * (lane + 1.5 + d2 * 0.5)
				t += w2 + _rng.randf_range(2.5, 6.0)
				if _rng.randf() < 0.25:
					continue
				_add_house(Vector2(cx2, cz2), Vector2(d2, w2))
	# A few farms further out.
	for k in 7:
		var c := Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-45, 45))
		if absf(c.x) < 22.0 and absf(c.y) < 22.0:
			continue
		if absf(c.x) < 8.0 or absf(c.y) < 8.0:
			continue
		_add_house(c, Vector2(_rng.randf_range(6, 9), _rng.randf_range(5, 7)))


func _add_house(c: Vector2, size: Vector2) -> void:
	var r := Rect2(c - size * 0.5, size)
	for h in houses:
		if (h[0] as Rect2).grow(2.0).intersects(r):
			return
	var col := Color(0.78, 0.72, 0.6) if _rng.randf() < 0.55 else Color(0.62, 0.55, 0.45)
	houses.append([r, _rng.randf_range(3.0, 4.2), col])


# ---------------------------------------------------------------- building it

const FIELD_GROUND := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 grass_dark : source_color = vec3(0.22, 0.32, 0.13);
uniform vec3 grass_light : source_color = vec3(0.42, 0.5, 0.22);
uniform vec3 dirt : source_color = vec3(0.42, 0.34, 0.22);
uniform vec3 mud : source_color = vec3(0.3, 0.25, 0.18);
uniform float dirt_amount = 0.3;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
varying vec4 vcol;
varying float wup;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
	wup = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = texture(noise_tex, p * 0.008).r;
	float mid = texture(noise_tex, p * 0.045 + 0.37).r;
	float fine = texture(noise_tex, p * 0.6 + 0.71).r;
	vec3 g = mix(grass_dark, grass_light, smoothstep(0.25, 0.75, big * 0.6 + mid * 0.4));
	float bare = smoothstep(1.0 - dirt_amount * 0.55, 1.08 - dirt_amount * 0.55, mid * 0.7 + big * 0.45);
	vec3 c = mix(g, dirt, max(bare, vcol.r));
	c = mix(c, mud, vcol.b);
	c *= 0.86 + 0.26 * fine;
	c *= vcol.g;
	// Slopes: barer and darker, so the lie of the land reads from above.
	float slope = clamp((1.0 - wup) * 6.0, 0.0, 1.0);
	c = mix(c, dirt * 0.8, slope * 0.35);
	c *= 1.0 - slope * 0.18;
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""


## Height out past the field (scenery): the map's shape, easing into a
## gentle swell.
func _outer(x: float, z: float) -> float:
	var e := maxf(absf(x), absf(z))
	var inside := 1.0 - smoothstep(HALF - 6.0, HALF + 30.0, e)
	var h := _raw(clampf(x, -HALF, HALF), clampf(z, -HALF, HALF))
	var swell := 2.0 + 3.0 * sin(x * 0.02) * cos(z * 0.017) + 4.0 * smoothstep(HALF, OUTER, e)
	return lerpf(swell, h, inside)


func build(parent: Node3D, cols: Dictionary) -> void:
	var step := 4.0
	var n := int(OUTER * 2.0 / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vs := PackedVector3Array()
	var cs := PackedColorArray()
	vs.resize(n * n)
	cs.resize(n * n)
	for j in n:
		for i in n:
			var x := -OUTER + i * step
			var z := -OUTER + j * step
			var y := height(x, z) if absf(x) <= HALF and absf(z) <= HALF else _outer(x, z)
			vs[j * n + i] = Vector3(x, y, z)
			# r: bare earth (lanes, banks), g: shade, b: mud (river bed).
			var dirt := 0.0
			var mud := 0.0
			var shade := 1.0
			if has_water:
				var d := absf(z - river_z(x))
				mud = 1.0 - smoothstep(9.0, 13.0, d)
				dirt = (1.0 - smoothstep(11.0, 16.0, d)) * 0.7
			if kind == "town" and (absf(x) < 4.0 or absf(z) < 4.0) and absf(x) < 70.0 and absf(z) < 70.0:
				dirt = 0.85
			for w in woods:
				if Vector2(x, z).distance_to(w[0]) < float(w[1]):
					shade = 0.78
					dirt = maxf(dirt, 0.35)
			cs[j * n + i] = Color(dirt, shade, mud)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			for idx in [a, a + 1, a + n, a + 1, a + n + 1, a + n]:
				st.set_color(cs[idx])
				st.add_vertex(vs[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FIELD_GROUND
	sm.shader = sh
	sm.set_shader_parameter("noise_tex", Look.noise_texture())
	for k in ["grass_dark", "grass_light", "dirt"]:
		if cols.has(k):
			sm.set_shader_parameter(k, cols[k])
	sm.set_shader_parameter("dirt_amount", float(cols.get("dirt_amount", 0.3)))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	# Walking on it: a height map for you; the edge of the field is a wall.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	parent.add_child(body)
	var hs := HeightMapShape3D.new()
	hs.map_width = N
	hs.map_depth = N
	hs.map_data = heights
	var csh := CollisionShape3D.new()
	csh.shape = hs
	csh.scale = Vector3(RES, 1.0, RES)
	body.add_child(csh)
	for k in 4:
		var wb := CollisionShape3D.new()
		var ws := WorldBoundaryShape3D.new()
		var nrm: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][k]
		ws.plane = Plane(nrm, -HALF + 1.0)
		wb.shape = ws
		body.add_child(wb)

	if has_water:
		_build_river(parent, body)
	if not houses.is_empty():
		_build_village(parent, body)
	_build_trees(parent)


func _build_river(parent: Node3D, body: StaticBody3D) -> void:
	var sea := Props.sea(OUTER * 2.0, 0.04, 0.5)
	sea.position = Vector3(0, WATER, 0)
	var mat := sea.mesh.surface_get_material(0) as ShaderMaterial
	if mat == null:
		mat = (sea.mesh as PlaneMesh).material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("deep", Color(0.12, 0.22, 0.24, 1.0))
		mat.set_shader_parameter("crest", Color(0.36, 0.48, 0.5, 1.0))
	parent.add_child(sea)
	# The bridge: a stone deck on three piers, low parapets.
	var zc := river_z(BRIDGE_X)
	var stone := Color(0.55, 0.53, 0.48)
	var bridge := Node3D.new()
	bridge.position = Vector3(BRIDGE_X, 0, zc)
	parent.add_child(bridge)
	Props._box(bridge, Vector3(BRIDGE_HALF_W * 2.0, 0.5, 20.0), stone, Vector3(0, 0.65, 0))
	for k in 2:
		var sgn := -1.0 if k == 0 else 1.0
		Props._box(bridge, Vector3(BRIDGE_HALF_W * 2.0, 0.4, 8.0), stone.darkened(0.08), Vector3(0, 0.45, sgn * 13.0), Vector3(sgn * 6.0, 0, 0))
		Props._box(bridge, Vector3(0.45, 0.8, 20.0), stone.lightened(0.05), Vector3(sgn * (BRIDGE_HALF_W - 0.2), 1.2, 0))
	for z in [-6.0, 0.0, 6.0]:
		Props._box(bridge, Vector3(BRIDGE_HALF_W * 2.0 - 0.6, 3.0, 1.6), stone.darkened(0.15), Vector3(0, -1.0, z))
	var deck := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(BRIDGE_HALF_W * 2.0, 0.5, 20.0)
	deck.shape = bs
	deck.position = Vector3(BRIDGE_X, 0.65, zc)
	body.add_child(deck)
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var ramp := CollisionShape3D.new()
		var rs := BoxShape3D.new()
		rs.size = Vector3(BRIDGE_HALF_W * 2.0, 0.4, 8.0)
		ramp.shape = rs
		ramp.position = Vector3(BRIDGE_X, 0.45, zc + sg * 13.0)
		ramp.rotation_degrees = Vector3(sg * 6.0, 0, 0)
		body.add_child(ramp)
	# Reeds along the banks.
	var reeds: Array = []
	for k in 160:
		var x := _rng.randf_range(-HALF, HALF)
		if absf(x - BRIDGE_X) < 7.0 or absf(x - FORD_X) < 12.0:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var z2 := river_z(x) + side * _rng.randf_range(8.0, 10.5)
		reeds.append([Vector3(x, height(x, z2), z2), _rng.randf_range(0.4, 0.8)])
	Look.bushes(parent, reeds, _rng, 0.15)


func _build_village(parent: Node3D, body: StaticBody3D) -> void:
	var roof_cols := [Color(0.45, 0.24, 0.16), Color(0.36, 0.3, 0.22), Color(0.5, 0.42, 0.26)]
	var mats := {}
	for h in houses:
		var r: Rect2 = h[0]
		var ht: float = h[1]
		var col: Color = h[2]
		var c := r.get_center()
		var g := height(c.x, c.y)
		var long_x := r.size.x >= r.size.y
		_mesh_box(parent, Vector3(r.size.x, ht + 0.6, r.size.y), Vector3(c.x, g + ht * 0.5 - 0.3, c.y), col, mats)
		# A pitched roof along the long side.
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var span := r.size.y if long_x else r.size.x
		var length := r.size.x if long_x else r.size.y
		pm.size = Vector3(span + 0.7, 2.2 if ht < 5.0 else 3.5, length + 0.5)
		roof.mesh = pm
		roof.material_override = _mat(roof_cols[houses.find(h) % roof_cols.size()], mats)
		roof.position = Vector3(c.x, g + ht + pm.size.y * 0.5, c.y)
		roof.rotation.y = PI * 0.5 if long_x else 0.0
		parent.add_child(roof)
		if ht >= 5.0:
			# The church tower.
			_mesh_box(parent, Vector3(4.0, 13.0, 4.0), Vector3(c.x, g + 6.5, r.end.y - 2.0), col.darkened(0.05), mats)
			var spire := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 2.6
			cm.height = 5.0
			cm.radial_segments = 4
			spire.mesh = cm
			spire.material_override = _mat(roof_cols[0], mats)
			spire.position = Vector3(c.x, g + 15.5, r.end.y - 2.0)
			spire.rotation.y = PI * 0.25
			parent.add_child(spire)
		else:
			# Door and windows on both long sides.
			for sgn in [-1.0, 1.0]:
				var face: Vector3 = Vector3(c.x, g, c.y) + (Vector3(0, 0, r.size.y * 0.5 + 0.03) if long_x else Vector3(r.size.x * 0.5 + 0.03, 0, 0)) * sgn
				var along := Vector3.RIGHT if long_x else Vector3.BACK
				var flat := Vector3(1.0, 0, 0.06) if long_x else Vector3(0.06, 0, 1.0)
				_mesh_box(parent, flat * Vector3(1.1, 0, 1.1) + Vector3(0, 1.9, 0) + (Vector3(0, 0, 0.0)), face + Vector3(0, 0.95, 0), Color(0.18, 0.11, 0.06), mats)
				_mesh_box(parent, flat * Vector3(0.9, 0, 0.9) + Vector3(0, 0.8, 0), face + along * 2.2 + Vector3(0, 1.9, 0), Color(0.14, 0.15, 0.2), mats)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(r.size.x, ht + 2.0, r.size.y)
		cs.shape = bs
		cs.position = Vector3(c.x, g + ht * 0.5, c.y)
		body.add_child(cs)
	# Low stone walls round the gardens.
	for k in 26:
		var x := _rng.randf_range(-62, 62)
		var z := _rng.randf_range(-50, 50)
		if absf(x) < 6.0 or absf(z) < 6.0:
			continue
		var p := Vector3(x, 0, z)
		if blocked(p):
			continue
		var len := _rng.randf_range(6, 14)
		var along_x := _rng.randf() < 0.5
		_mesh_box(parent, Vector3(len if along_x else 0.5, 0.8, 0.5 if along_x else len), Vector3(x, height(x, z) + 0.3, z), Color(0.5, 0.48, 0.43), mats)


func _mat(c: Color, cache: Dictionary) -> StandardMaterial3D:
	if not cache.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		cache[c] = m
	return cache[c]


func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, cache: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c, cache)
	mi.position = pos
	parent.add_child(mi)


func _build_trees(parent: Node3D) -> void:
	var spots: Array = []
	# Inside the woods, close together.
	for w in woods:
		var c: Vector2 = w[0]
		var r: float = w[1]
		var count := int(r * r * 0.07)
		for k in count:
			var a := _rng.randf() * TAU
			var d := r * sqrt(_rng.randf()) * 0.95
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			spots.append([Vector3(x, height(x, z) - 0.1, z), _rng.randf_range(0.8, 1.4)])
	# A belt of trees round the outside of the field.
	for k in 260:
		var a2 := _rng.randf() * TAU
		var d2 := _rng.randf_range(HALF + 6.0, OUTER - 20.0)
		var x2 := cos(a2) * d2
		var z2 := sin(a2) * d2
		spots.append([Vector3(x2, _outer(x2, z2) - 0.1, z2), _rng.randf_range(0.9, 1.6)])
	Look.trees(parent, spots, "mixed", _rng)
	var bush: Array = []
	for k in 140:
		var x3 := _rng.randf_range(-HALF, HALF)
		var z3 := _rng.randf_range(-HALF, HALF)
		var p := Vector3(x3, 0, z3)
		if cell(p) != FREE or absf(z3) > 40.0 and absf(z3) < 95.0 and absf(x3) < 90.0:
			continue # (keep the deployment fields clear)
		bush.append([Vector3(x3, height(x3, z3), z3), _rng.randf_range(0.5, 1.2)])
	Look.bushes(parent, bush, _rng)
