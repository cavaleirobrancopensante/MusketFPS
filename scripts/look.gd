extends RefCounted
## How the outdoors looks: the sky, the ground, grass, trees, bushes, rocks,
## far hills and the light, shared by battles, towns and the pop-up scenes.
## Everything is built in code and drawn in a few instanced batches, so it
## stays cheap on a phone however much of it there is.
##
## Quality (Settings.graphics):
##   low     grass only near you, no shadows
##   medium  full grass, soft blob shadows under everyone (batcher.gd)
##   high    real sun shadows from men, trees and buildings, a little bloom
##
##   var env := Look.environment(parent, "day", ground_colour)
##   Look.ground(parent, size, colours)
##   Look.grass(parent, centre, radius, colours, avoid)
##   Look.trees(parent, rng, count, rmin, rmax, kind)

const SKY_SHADER := """
shader_type sky;
uniform vec3 top : source_color = vec3(0.32, 0.48, 0.72);
uniform vec3 horizon : source_color = vec3(0.78, 0.82, 0.84);
uniform vec3 ground : source_color = vec3(0.42, 0.44, 0.38);
uniform vec3 sun_col : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 cloud_col : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.66, 0.74);
uniform float cloudiness = 0.5;
uniform float night = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = mix(horizon, top, pow(clamp(h, 0.0, 1.0), 0.55));
	c = mix(c, ground, smoothstep(0.0, -0.08, h));
	// The sun: a bright disc and a wide glow.
	float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
	c += sun_col * (pow(s, 900.0) * 6.0 + pow(s, 12.0) * 0.35) * (1.0 - night);
	// Clouds on a dome: soft fbm, lit on the sun side.
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.18) * 1.6;
		float n = fbm(uv + vec2(3.1, 1.7));
		float cover = smoothstep(1.0 - cloudiness * 0.75 - 0.15, 1.0 - cloudiness * 0.75 + 0.25, n);
		float lit = clamp(fbm(uv * 1.7 + LIGHT0_DIRECTION.xz * 0.6) * 1.3 - 0.15, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_col, lit) * (1.0 - night * 0.85);
		c = mix(c, cc, cover * smoothstep(0.0, 0.12, h) * 0.92);
	}
	// Stars at night.
	if (night > 0.5 && h > 0.0) {
		float st = step(0.9975, hash(floor(d.xz / (h + 0.3) * 240.0)));
		c += vec3(st) * night * smoothstep(0.0, 0.2, h);
	}
	COLOR = c;
}
"""

## The ground: two scales of colour variation, bare patches, and fine grain,
## in world space so it never stretches.
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 grass_dark : source_color = vec3(0.22, 0.32, 0.13);
uniform vec3 grass_light : source_color = vec3(0.42, 0.5, 0.22);
uniform vec3 dirt : source_color = vec3(0.42, 0.34, 0.22);
uniform float dirt_amount = 0.3;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	float big = texture(noise_tex, p * 0.008).r;
	float mid = texture(noise_tex, p * 0.045 + 0.37).r;
	float fine = texture(noise_tex, p * 0.6 + 0.71).r;
	vec3 g = mix(grass_dark, grass_light, smoothstep(0.25, 0.75, big * 0.6 + mid * 0.4));
	float bare = smoothstep(1.0 - dirt_amount * 0.55, 1.08 - dirt_amount * 0.55, mid * 0.7 + big * 0.45);
	vec3 c = mix(g, dirt, bare);
	c *= 0.86 + 0.26 * fine;
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

## Grass clumps: three crossed blades, darker at the root, swaying in the
## wind, shrinking away with distance so the far field costs nothing.
const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform vec3 root_col : source_color = vec3(0.16, 0.24, 0.08);
uniform vec3 tip_col : source_color = vec3(0.55, 0.62, 0.28);
uniform float fade_far = 55.0;
varying float tip;

void vertex() {
	tip = VERTEX.y;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(w - CAMERA_POSITION_WORLD);
	float k = 1.0 - smoothstep(fade_far * 0.6, fade_far, dist);
	VERTEX *= k;
	float sway = sin(TIME * 1.7 + w.x * 0.35 + w.z * 0.27) * 0.12 + sin(TIME * 3.1 + w.z * 0.9) * 0.04;
	VERTEX.x += sway * tip * tip;
	VERTEX.z += sway * 0.6 * tip * tip;
}

void fragment() {
	ALBEDO = mix(root_col, tip_col, clamp(tip * 1.6, 0.0, 1.0)) * COLOR.rgb;
	ROUGHNESS = 0.9;
}
"""

## Foliage (tree crowns, bushes): instance colour, a gentle sway at the top.
const LEAF_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform float sway = 0.05;
varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y + 0.5, 0.0);
	VERTEX.x += sin(TIME * 1.1 + w.x * 0.2 + w.z * 0.13) * sway * h;
}

void fragment() {
	// A touch darker underneath and inside, lighter on top.
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = tint * (0.72 + 0.4 * up);
	ROUGHNESS = 0.9;
}
"""

static var _noise_tex: NoiseTexture2D
static var _grass_mesh: ArrayMesh


static func quality() -> String:
	return Settings.graphics


static func shadows() -> bool:
	return quality() == "high"


static func noise_texture() -> NoiseTexture2D:
	if _noise_tex == null:
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 256
		_noise_tex.height = 256
		_noise_tex.seamless = true
		var n := FastNoiseLite.new()
		n.frequency = 0.02
		n.fractal_octaves = 4
		_noise_tex.noise = n
	return _noise_tex


# ---------------------------------------------------------------- sky and light

## Sky, fog and the sun for a time of day ("day", "dusk", "night"). Adds a
## WorldEnvironment and a DirectionalLight3D to `parent`; returns the
## environment (the sun is its meta "sun").
static func environment(parent: Node, tod := "day", haze := Color(0.78, 0.8, 0.8), fog := 0.006) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sm.shader = sh
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	var sun := DirectionalLight3D.new()
	match tod:
		"night":
			sm.set_shader_parameter("top", Color(0.02, 0.03, 0.08))
			sm.set_shader_parameter("horizon", Color(0.07, 0.09, 0.15))
			sm.set_shader_parameter("ground", Color(0.03, 0.03, 0.05))
			sm.set_shader_parameter("night", 1.0)
			sm.set_shader_parameter("cloud_shade", Color(0.05, 0.06, 0.09))
			sm.set_shader_parameter("cloud_col", Color(0.15, 0.17, 0.22))
			sun.rotation_degrees = Vector3(-38, -40, 0)
			sun.light_color = Color(0.55, 0.65, 1.0)
			sun.light_energy = 0.45
			env.ambient_light_energy = 0.5
			env.fog_light_color = Color(0.05, 0.06, 0.1)
			fog = maxf(fog, 0.018)
		"dusk":
			sm.set_shader_parameter("top", Color(0.22, 0.28, 0.5))
			sm.set_shader_parameter("horizon", Color(1.0, 0.62, 0.38))
			sm.set_shader_parameter("ground", Color(0.4, 0.32, 0.28))
			sm.set_shader_parameter("sun_col", Color(1.0, 0.6, 0.3))
			sm.set_shader_parameter("cloud_col", Color(1.0, 0.72, 0.55))
			sm.set_shader_parameter("cloud_shade", Color(0.45, 0.35, 0.45))
			sun.rotation_degrees = Vector3(-12, 62, 0)
			sun.light_color = Color(1.0, 0.7, 0.45)
			sun.light_energy = 1.25
			env.ambient_light_energy = 0.55
			env.fog_light_color = Color(0.85, 0.6, 0.45)
		_:
			sm.set_shader_parameter("horizon", haze.lerp(Color(0.8, 0.84, 0.86), 0.5))
			sun.rotation_degrees = Vector3(-42, 38, 0)
			sun.light_color = Color(1.0, 0.96, 0.88)
			sun.light_energy = 1.15
			env.ambient_light_energy = 0.7
			env.fog_light_color = haze
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_density = fog
	env.fog_sky_affect = 0.25
	# Low mist that thins with height: depth to the distance without hiding the sky.
	env.fog_height = 6.0
	env.fog_height_density = fog * 0.7
	if quality() == "high" and RenderingServer.get_rendering_device() != null:
		# (Bloom only on the phone's renderer: the compatibility one overdoes it.)
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	sun.shadow_enabled = shadows()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	env.set_meta("sun", sun)
	return env


# ---------------------------------------------------------------- ground

## A big ground plane with the ground shader. `cols`: grass_dark,
## grass_light, dirt (Colors) and dirt_amount (0..1).
static func ground(parent: Node, size: float, cols: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	sm.shader = sh
	sm.set_shader_parameter("noise_tex", noise_texture())
	for k in ["grass_dark", "grass_light", "dirt"]:
		if cols.has(k):
			sm.set_shader_parameter(k, cols[k])
	sm.set_shader_parameter("dirt_amount", float(cols.get("dirt_amount", 0.3)))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Ground colours for a map terrain (world_gen T values).
static func ground_colours(t: int) -> Dictionary:
	var Gen = load("res://scripts/world_gen.gd")
	match t:
		Gen.T.FOREST:
			return {"grass_dark": Color(0.14, 0.24, 0.09), "grass_light": Color(0.3, 0.4, 0.16), "dirt": Color(0.3, 0.24, 0.15), "dirt_amount": 0.45, "grass": 0.7}
		Gen.T.HILLS:
			return {"grass_dark": Color(0.3, 0.34, 0.16), "grass_light": Color(0.52, 0.52, 0.28), "dirt": Color(0.48, 0.42, 0.3), "dirt_amount": 0.4, "grass": 0.8}
		Gen.T.SWAMP:
			return {"grass_dark": Color(0.18, 0.22, 0.12), "grass_light": Color(0.32, 0.34, 0.18), "dirt": Color(0.22, 0.2, 0.14), "dirt_amount": 0.6, "grass": 1.0}
		Gen.T.BEACH:
			return {"grass_dark": Color(0.6, 0.55, 0.38), "grass_light": Color(0.78, 0.72, 0.52), "dirt": Color(0.66, 0.6, 0.44), "dirt_amount": 0.2, "grass": 0.15}
		Gen.T.MOUNTAIN:
			return {"grass_dark": Color(0.36, 0.36, 0.33), "grass_light": Color(0.5, 0.5, 0.45), "dirt": Color(0.42, 0.4, 0.37), "dirt_amount": 0.5, "grass": 0.25}
	return {"grass_dark": Color(0.2, 0.32, 0.11), "grass_light": Color(0.44, 0.52, 0.22), "dirt": Color(0.44, 0.36, 0.23), "dirt_amount": 0.25, "grass": 1.0}


# ---------------------------------------------------------------- grass

static func _grass_clump() -> ArrayMesh:
	if _grass_mesh != null:
		return _grass_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 4:
		var a := PI * k / 4.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.028
		for b in 3:
			# A few thin blades per plane, leaning apart, of different heights.
			var off := dir * rng.randf_range(-0.12, 0.12)
			var lean := dir * rng.randf_range(-0.1, 0.1) + Vector3(-dir.z, 0, dir.x) * rng.randf_range(-0.05, 0.05)
			var h := rng.randf_range(0.18, 0.34)
			var n := Vector3(-dir.z, 0.3, dir.x).normalized()
			st.set_normal(n)
			st.set_color(Color.WHITE)
			st.add_vertex(off - side)
			st.add_vertex(off + side)
			st.add_vertex(off + lean + Vector3(0, h, 0))
	_grass_mesh = st.commit()
	return _grass_mesh


## Grass clumps scattered over a disc, skipping `avoid` (Rect2s in x/z: streets,
## houses, water). Count scales with quality and `density` (0..1).
static func grass(parent: Node, centre: Vector3, radius: float, density: float, cols: Dictionary, avoid: Array = [], rng: RandomNumberGenerator = null, reject: Callable = Callable()) -> MultiMeshInstance3D:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 7
	var count := int({"low": 3000, "medium": 9000, "high": 15000}.get(quality(), 9000) * clampf(density, 0.0, 1.5))
	if count <= 0:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _grass_clump()
	var xs: Array = []
	var tries := 0
	while xs.size() < count and tries < count * 3:
		tries += 1
		# Denser near the middle, where the eye is.
		var r := radius * sqrt(rng.randf()) * (0.4 + 0.6 * rng.randf())
		var a := rng.randf() * TAU
		var p := centre + Vector3(cos(a) * r, 0, sin(a) * r)
		var bad := false
		for o in avoid:
			if (o as Rect2).has_point(Vector2(p.x, p.z)):
				bad = true
				break
		if not bad and reject.is_valid() and reject.call(p):
			bad = true
		if not bad:
			xs.append(p)
	mm.instance_count = xs.size()
	var light: Color = cols.get("grass_light", Color(0.44, 0.52, 0.22))
	for i in xs.size():
		var s := rng.randf_range(0.7, 1.4)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		mm.set_instance_transform(i, Transform3D(b, xs[i]))
		var v := rng.randf_range(0.8, 1.15)
		mm.set_instance_color(i, Color(v, v * rng.randf_range(0.95, 1.05), v * 0.95))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	sm.shader = sh
	sm.set_shader_parameter("root_col", (cols.get("grass_dark", Color(0.2, 0.3, 0.1)) as Color).darkened(0.25))
	sm.set_shader_parameter("tip_col", light.lightened(0.28))
	sm.set_shader_parameter("fade_far", {"low": 28.0, "medium": 50.0, "high": 70.0}.get(quality(), 50.0))
	inst.material_override = sm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst


# ---------------------------------------------------------------- trees, bushes, rocks

static func _leaf_mat(sway: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	sm.shader = sh
	sm.set_shader_parameter("sway", sway)
	return sm


static func _batch(parent: Node, mesh: Mesh, mat: Material, xs: Array, shadows_on := true) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i][0])
		mm.set_instance_color(i, xs[i][1])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows_on and shadows() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


## Trees at the given points ([Vector3, scale] pairs): `kind` "pine",
## "broadleaf", "dead" or "mixed". Pines are three stacked tiers; broadleaf
## trees a trunk and a cluster of round crowns, each a slightly different green.
static func trees(parent: Node, spots: Array, kind := "mixed", rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 11
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.35
	trunk.bottom_radius = 0.5
	trunk.height = 1.0
	trunk.radial_segments = 6
	var tier := CylinderMesh.new()
	tier.top_radius = 0.0
	tier.bottom_radius = 0.5
	tier.height = 1.0
	tier.radial_segments = 9
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 10
	blob.rings = 6
	var trunks: Array = []
	var tiers: Array = []
	var blobs: Array = []
	var bark := StandardMaterial3D.new()
	bark.vertex_color_use_as_albedo = true
	bark.roughness = 0.95
	for sp in spots:
		var p: Vector3 = sp[0]
		var s: float = sp[1]
		var k := kind
		if kind == "mixed":
			k = "pine" if rng.randf() < 0.55 else "broadleaf"
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var bark_col := Color(0.3, 0.21, 0.13).lerp(Color(0.38, 0.3, 0.22), rng.randf())
		match k:
			"pine":
				trunks.append([Transform3D(yaw.scaled(Vector3(0.32 * s, 2.2 * s, 0.32 * s)), p + Vector3(0, 1.1 * s, 0)), bark_col])
				var g := Color(0.1, 0.24, 0.13).lerp(Color(0.17, 0.33, 0.17), rng.randf())
				for t in 3:
					var w := (2.0 - t * 0.5) * s
					var h := (2.6 - t * 0.4) * s
					tiers.append([Transform3D(yaw.scaled(Vector3(w * 2.0, h, w * 2.0)), p + Vector3(0, (2.0 + t * 1.45) * s + h * 0.5, 0)), g.lightened(0.04 * t)])
			"broadleaf":
				trunks.append([Transform3D(yaw.scaled(Vector3(0.38 * s, 3.0 * s, 0.38 * s)), p + Vector3(0, 1.5 * s, 0)), bark_col])
				var g2 := Color(0.2, 0.34, 0.12).lerp(Color(0.34, 0.44, 0.16), rng.randf())
				for b in 4:
					var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.6), rng.randf_range(-1.0, 1.0)) * s
					var r := rng.randf_range(1.7, 2.5) * s
					blobs.append([Transform3D(Basis().scaled(Vector3(r, r * 0.8, r)), p + Vector3(0, 3.8 * s, 0) + off), g2.lightened(rng.randf_range(-0.05, 0.08))])
			"dead":
				trunks.append([Transform3D(yaw.rotated(Vector3.RIGHT, rng.randf_range(-0.15, 0.15)).scaled(Vector3(0.28 * s, 3.4 * s, 0.28 * s)), p + Vector3(0, 1.7 * s, 0)), Color(0.3, 0.27, 0.22)])
	_batch(parent, trunk, bark, trunks)
	_batch(parent, tier, _leaf_mat(0.04), tiers)
	_batch(parent, blob, _leaf_mat(0.06), blobs)


## Bushes and rocks scattered at the given points ([Vector3, scale] pairs).
static func bushes(parent: Node, spots: Array, rng: RandomNumberGenerator, rocks_share := 0.35) -> void:
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 8
	blob.rings = 5
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 6
	rock.rings = 3
	var bs: Array = []
	var rs: Array = []
	for sp in spots:
		var p: Vector3 = sp[0]
		var s: float = sp[1]
		if rng.randf() < rocks_share:
			var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
			rs.append([Transform3D(b.scaled(Vector3(s * 1.3, s * 0.7, s)), p + Vector3(0, s * 0.18, 0)), Color(0.42, 0.42, 0.4).lerp(Color(0.52, 0.5, 0.46), rng.randf())])
		else:
			for k in 3:
				var o := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)) * s
				var r := s * rng.randf_range(0.7, 1.1)
				bs.append([Transform3D(Basis().scaled(Vector3(r, r * 0.75, r)), p + o + Vector3(0, r * 0.3, 0)), Color(0.17, 0.3, 0.12).lerp(Color(0.3, 0.4, 0.15), rng.randf())])
	var rmat := StandardMaterial3D.new()
	rmat.vertex_color_use_as_albedo = true
	rmat.roughness = 1.0
	_batch(parent, blob, _leaf_mat(0.03), bs, false)
	_batch(parent, rock, rmat, rs, false)


## Low hills on the horizon all round, so the land doesn't end in a flat
## line. They sit in the fog, out of reach.
static func far_hills(parent: Node, rng: RandomNumberGenerator, near: float, col: Color, count := 14, mountains := false) -> void:
	var cone := SphereMesh.new()
	cone.radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 10
	cone.rings = 5
	var xs: Array = []
	for i in count:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / count
		var d := near + rng.randf_range(20.0, 90.0)
		var w := rng.randf_range(60.0, 130.0)
		var h := rng.randf_range(14.0, 30.0) * (2.5 if mountains else 1.0)
		xs.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h * 2.0, w * 0.7)), Vector3(cos(a) * d, -h * 0.35, sin(a) * d)), col.lerp(Color(0.5, 0.55, 0.5), rng.randf() * 0.3)])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	_batch(parent, cone, m, xs, false)
