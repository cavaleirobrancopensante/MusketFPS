extends Node3D
## Every flying thing in the battle: musket balls, grenades, and later
## javelins, arrows and round shot.
##
## Not physics bodies: each projectile is a small record (position, velocity,
## age) stepped every physics tick with gravity and air drag. Each step it
## sweeps the line it just travelled against the units near that line (via the
## battle's spatial grid) and hits the first one in its path, friend or foe.
## That keeps hundreds of projectiles cheap on a phone.
##
## Kinds are a table: add a new weapon by adding a row (and, if it needs one,
## a look). `shield_stops` lets a raised lizard shield catch it.

const KINDS := {
	"ball": {"gravity": 9.8, "drag": 0.35, "life": 2.5, "damage": 100.0, "player_damage": 55.0,
		"shield_stops": false, "tracer": true},
	"grenade": {"gravity": 9.8, "drag": 0.05, "life": 10.0, "fuse": 2.6, "bounce": 0.35,
		"blast_radius": 5.0, "kill_radius": 2.2},
	# Ready for the lizard skirmishers: a heavy, slow, arcing throw.
	"javelin": {"gravity": 9.8, "drag": 0.05, "life": 5.0, "damage": 70.0, "player_damage": 35.0,
		"shield_stops": true, "tracer": false},
}

const TRACER_COLOR := Color(1.0, 0.92, 0.7)

var battle
var stats := {"balls": 0, "hit_enemy": 0, "hit_friend": 0, "ground": 0}
var _list: Array = [] # Dictionaries: kind, pos, vel, shooter, age, + per-kind state
var _tracers: MultiMesh
var _grenade_mesh: SphereMesh
var _grenade_mat: StandardMaterial3D


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var box := BoxMesh.new()
	box.material = mat
	_tracers = MultiMesh.new()
	_tracers.transform_format = MultiMesh.TRANSFORM_3D
	_tracers.use_colors = true
	_tracers.mesh = box
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _tracers
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-600, -20, -600), Vector3(1200, 80, 1200))
	add_child(mmi)
	_grenade_mesh = SphereMesh.new()
	_grenade_mesh.radius = 0.06
	_grenade_mesh.height = 0.12
	_grenade_mesh.radial_segments = 8
	_grenade_mesh.rings = 4
	_grenade_mat = StandardMaterial3D.new()
	_grenade_mat.albedo_color = Color(0.12, 0.12, 0.13)
	_grenade_mat.metallic = 0.4


# ---------------------------------------------------------------- spawning

## Fire a projectile. `shooter` is never hit by its own shot and gets the
## credit (and on_projectile_hit()) when it lands.
func fire(kind: String, from: Vector3, velocity: Vector3, shooter: Node3D) -> Dictionary:
	var p := {"kind": kind, "pos": from, "prev": from, "vel": velocity, "shooter": shooter, "age": 0.0}
	if kind == "grenade":
		var mi := MeshInstance3D.new()
		mi.mesh = _grenade_mesh
		mi.material_override = _grenade_mat
		mi.position = from
		add_child(mi)
		p["node"] = mi
		p["fuse"] = float(KINDS[kind]["fuse"])
		p["spark"] = 0.0
	if kind == "ball":
		stats["balls"] += 1
	_list.append(p)
	return p


## Aim helper: a direction toward `target_pos` with random spread (radians).
static func spread_dir(dir: Vector3, spread: float) -> Vector3:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(d).normalized()
	# Uniform within a cone, so misses scatter naturally.
	var r := spread * sqrt(randf())
	var a := randf() * TAU
	return (d + side * cos(a) * r + up * sin(a) * r).normalized()


# ---------------------------------------------------------------- stepping

func _physics_process(delta: float) -> void:
	var alive_list: Array = []
	for p in _list:
		if _step(p, delta):
			alive_list.append(p)
	_list = alive_list
	_draw_tracers()


## Advance one projectile; returns false when it's spent.
func _step(p: Dictionary, delta: float) -> bool:
	var k: Dictionary = KINDS[p["kind"]]
	var vel: Vector3 = p["vel"]
	vel.y -= float(k["gravity"]) * delta
	vel *= maxf(0.0, 1.0 - float(k["drag"]) * delta)
	var prev: Vector3 = p["pos"]
	var pos := prev + vel * delta
	p["prev"] = prev
	p["age"] = float(p["age"]) + delta

	if p["kind"] == "grenade":
		return _step_grenade(p, k, prev, pos, vel, delta)

	p["vel"] = vel
	p["pos"] = pos
	var hit := _sweep(prev, pos, p["shooter"], 0.0)
	if not hit.is_empty():
		_impact_unit(p, k, hit["unit"], prev.lerp(pos, float(hit["t"])))
		return false
	if pos.y <= 0.02:
		stats["ground"] += 1
		battle.spawn_puff(Vector3(pos.x, 0.05, pos.z), Color(0.45, 0.38, 0.28), 0.35)
		return false
	return float(p["age"]) < float(k["life"])


func _step_grenade(p: Dictionary, k: Dictionary, prev: Vector3, pos: Vector3, vel: Vector3, delta: float) -> bool:
	# Bounce and roll on the ground.
	if pos.y <= 0.06:
		pos.y = 0.06
		if vel.y < -1.0:
			vel.y = -vel.y * float(k["bounce"])
			vel.x *= 0.6
			vel.z *= 0.6
			battle.play_sound("thud", pos, -12.0)
		else:
			vel.y = 0.0
			vel.x *= maxf(0.0, 1.0 - 3.0 * delta) # rolling friction
			vel.z *= maxf(0.0, 1.0 - 3.0 * delta)
	p["vel"] = vel
	p["pos"] = pos
	var node: MeshInstance3D = p["node"]
	node.position = pos
	node.rotation += Vector3(vel.z, 0, -vel.x) * delta * 8.0
	# A spitting fuse.
	p["spark"] = float(p["spark"]) - delta
	if float(p["spark"]) <= 0.0:
		p["spark"] = 0.12
		battle.spawn_flash(pos + Vector3.UP * 0.08, 0.5)
	p["fuse"] = float(p["fuse"]) - delta
	if float(p["fuse"]) <= 0.0:
		node.queue_free()
		battle.explode(pos, float(k["blast_radius"]), float(k["kill_radius"]), p["shooter"])
		return false
	return true


# ---------------------------------------------------------------- hits

## The first unit (or the player) whose body the segment a->b passes through.
## Bodies are upright cylinders. `extra` widens them (for line-of-fire checks).
## Returns {} or {"unit": Node3D, "t": 0..1 along the segment}.
func _sweep(a: Vector3, b: Vector3, shooter: Node3D, extra: float) -> Dictionary:
	var best_t := 2.0
	var best: Node3D = null
	for entry in battle.units_near_segment(a, b):
		var u: Node3D = entry[0]
		if u == shooter or not u.alive:
			continue
		var t := _cylinder_hit(a, b, entry[1], float(u.hit_radius) + extra, float(u.hit_height))
		if t >= 0.0 and t < best_t:
			best_t = t
			best = u
	var pl: Node3D = battle.player
	if pl != shooter and pl.alive:
		var tp := _cylinder_hit(a, b, pl.global_position, 0.35 + extra, 1.8)
		if tp >= 0.0 and tp < best_t:
			best_t = tp
			best = pl
	if best == null:
		return {}
	return {"unit": best, "t": best_t}


## Where (0..1) segment a->b first comes within `r` of an upright cylinder
## standing at `base` with height `h`, or -1.
static func _cylinder_hit(a: Vector3, b: Vector3, base: Vector3, r: float, h: float) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(base.x - a.x, base.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.000001 else clampf(ac.dot(ab) / len2, 0.0, 1.0)
	var closest := Vector2(a.x, a.z) + ab * t
	if closest.distance_to(Vector2(base.x, base.z)) > r:
		return -1.0
	var y := lerpf(a.y, b.y, t)
	if y < base.y or y > base.y + h:
		return -1.0
	# Step back to roughly where it entered the body.
	var back := 0.0 if len2 < 0.000001 else r / sqrt(len2)
	return maxf(0.0, t - back)


func _impact_unit(p: Dictionary, k: Dictionary, u: Node3D, at: Vector3) -> void:
	var shooter = p["shooter"]
	if bool(k.get("shield_stops", false)) and u.has_method("catch_projectile") and u.catch_projectile(at):
		battle.play_sound("clang", at, -4.0)
		return
	if u.get("rig_kind") == "lizard":
		stats["hit_enemy"] += 1
	else:
		stats["hit_friend"] += 1
	var dmg := float(k["damage"])
	if u == battle.player:
		dmg = float(k.get("player_damage", dmg))
	u.take_shot(dmg, shooter)
	battle.spawn_puff(at, Color(0.5, 0.08, 0.06), 0.3)
	if shooter != null and is_instance_valid(shooter) and shooter.has_method("on_projectile_hit"):
		shooter.on_projectile_hit(u)


## Line of fire: would a shot from `from` to `to` pass close to a comrade of
## `shooter` before reaching it? (Soldiers check this before pulling the trigger.)
func line_blocked(from: Vector3, to: Vector3, shooter: Node3D) -> bool:
	var hit := _sweep(from, to, shooter, 0.35)
	if hit.is_empty():
		return false
	var u: Node3D = hit["unit"]
	return u == battle.player or u.is_in_group("friendlies")


# ---------------------------------------------------------------- drawing

## Musket balls are too small and fast to see; a short bright streak along
## their path shows where each shot went.
func _draw_tracers() -> void:
	var buf := PackedFloat32Array()
	for p in _list:
		var k: Dictionary = KINDS[p["kind"]]
		if not bool(k.get("tracer", false)):
			continue
		var a: Vector3 = p["prev"]
		var b: Vector3 = p["pos"]
		var d := b - a
		var l := d.length()
		if l < 0.01:
			continue
		# Streak length: the last tick's travel, capped.
		var length := minf(l * 0.6, 3.5)
		var basis := Basis.looking_at(d / l, Vector3.UP if absf(d.y / l) < 0.97 else Vector3.BACK)
		basis = basis * Basis.from_scale(Vector3(0.012, 0.012, length))
		var o := b - d / l * length * 0.5
		var c := TRACER_COLOR
		buf.append_array([basis.x.x, basis.y.x, basis.z.x, o.x, basis.x.y, basis.y.y, basis.z.y, o.y,
			basis.x.z, basis.y.z, basis.z.z, o.z, c.r, c.g, c.b, 1.0])
	var n := buf.size() / 16
	if _tracers.instance_count < n:
		_tracers.instance_count = maxi(64, nearest_po2(n))
	buf.resize(_tracers.instance_count * 16)
	_tracers.buffer = buf
	_tracers.visible_instance_count = n
