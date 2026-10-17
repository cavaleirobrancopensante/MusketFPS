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
	# A .75 ball goes through a man and on into the next: up to three bodies,
	# losing speed and punch with each (see "pass_keep").
	"ball": {"gravity": 9.8, "drag": 0.35, "life": 2.5, "damage": 100.0, "player_damage": 55.0,
		"shield_stops": false, "tracer": true, "pierce": 2, "pass_keep": 0.65},
	"pistol": {"gravity": 9.8, "drag": 0.6, "life": 1.6, "damage": 80.0, "player_damage": 40.0,
		"shield_stops": false, "tracer": true, "pierce": 1, "pass_keep": 0.55},
	"grenade": {"gravity": 9.8, "drag": 0.05, "life": 10.0, "fuse": 2.6, "bounce": 0.35,
		"blast_radius": 5.0, "kill_radius": 2.2},
	# Field guns: a solid iron ball that ploughs through ranks and bounces on,
	# and canister (a tin of musket balls) for close work.
	"roundshot": {"gravity": 9.8, "drag": 0.02, "life": 4.0, "damage": 220.0, "player_damage": 120.0,
		"shield_stops": false, "tracer": false, "pierce": 4, "bounce": 0.45},
	"canister": {"gravity": 9.8, "drag": 0.5, "life": 1.2, "damage": 90.0, "player_damage": 45.0,
		"shield_stops": false, "tracer": true},
	# Native archers and crossbowmen. Arrows are drawn as shafts in flight and
	# stay stuck in the ground a while; a raised shield catches them.
	"arrow": {"gravity": 9.8, "drag": 0.02, "life": 6.0, "damage": 45.0, "player_damage": 22.0,
		"shield_stops": true, "tracer": false, "shaft": 0.75},
	"bolt": {"gravity": 9.8, "drag": 0.04, "life": 4.0, "damage": 85.0, "player_damage": 36.0,
		"shield_stops": true, "tracer": false, "shaft": 0.4},
	# Ready for the lizard skirmishers: a heavy, slow, arcing throw.
	"javelin": {"gravity": 9.8, "drag": 0.05, "life": 5.0, "damage": 70.0, "player_damage": 35.0,
		"shield_stops": true, "tracer": false},
}

const TRACER_COLOR := Color(1.0, 0.92, 0.7)
const SHAFT_COLOR := Color(0.36, 0.26, 0.15)
const FLETCH_COLOR := Color(0.85, 0.82, 0.75)
const STUCK_TIME := 15.0
const STUCK_MAX := 400

var battle
var stats := {"balls": 0, "hit_enemy": 0, "hit_friend": 0, "ground": 0}
var _list: Array = [] # Dictionaries: kind, pos, vel, shooter, age, + per-kind state
var _tracers: MultiMesh
var _grenade_mesh: SphereMesh
var _grenade_mat: StandardMaterial3D
var _javelin_mesh: BoxMesh
var _shot_mesh: SphereMesh
var _stuck: Array = [] # [position, direction, length, age]: arrows standing in the ground


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
	_javelin_mesh = BoxMesh.new()
	_javelin_mesh.size = Vector3(0.035, 0.035, 1.7)
	var jm := StandardMaterial3D.new()
	jm.albedo_color = Color(0.45, 0.32, 0.18)
	_javelin_mesh.material = jm
	_shot_mesh = SphereMesh.new()
	_shot_mesh.radius = 0.09
	_shot_mesh.height = 0.18
	_shot_mesh.radial_segments = 8
	_shot_mesh.rings = 4
	_shot_mesh.material = _grenade_mat


# ---------------------------------------------------------------- spawning

## Fire a projectile. `shooter` is never hit by its own shot and gets the
## credit (and on_projectile_hit()) when it lands. `only` (scripted shots)
## makes it pass through everyone but that one unit.
func fire(kind: String, from: Vector3, velocity: Vector3, shooter: Node3D, only: Node3D = null) -> Dictionary:
	var p := {"kind": kind, "pos": from, "prev": from, "vel": velocity, "shooter": shooter, "age": 0.0}
	if only != null:
		p["only"] = only
	if kind == "javelin" or kind == "roundshot":
		var mj := MeshInstance3D.new()
		mj.mesh = _javelin_mesh if kind == "javelin" else _shot_mesh
		mj.position = from
		add_child(mj)
		p["node"] = mj
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
	if not _stuck.is_empty():
		for s in _stuck:
			s[3] = float(s[3]) + delta
		while not _stuck.is_empty() and float(_stuck[0][3]) > STUCK_TIME:
			_stuck.pop_front()
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
	if p.has("node"):
		var nd: Node3D = p["node"]
		nd.position = pos
		if vel.length_squared() > 0.01:
			nd.basis = Basis.looking_at(vel.normalized(), Vector3.UP if absf(vel.normalized().y) < 0.97 else Vector3.BACK)
	if battle.nest != null and battle.nest.hit_structure(prev, pos, String(p["kind"])):
		_spent(p, false)
		return false
	var done: Array = p.get("hit_list", [])
	var hit := _sweep_only(prev, pos, p["only"]) if p.has("only") else _sweep(prev, pos, p["shooter"], 0.0, done)
	if not hit.is_empty():
		_impact_unit(p, k, hit["unit"], prev.lerp(pos, float(hit["t"])))
		# Round shot ploughs on through the ranks behind.
		if int(k.get("pierce", 0)) > done.size() and hit["unit"] != battle.player:
			done.append(hit["unit"])
			p["hit_list"] = done
			var keep := float(k.get("pass_keep", 0.8))
			p["vel"] = vel * keep
			p["dmg_mult"] = float(p.get("dmg_mult", 1.0)) * keep
			return true
		_spent(p, false)
		return false
	var gy: float = battle.ground_y(pos)
	var wall: bool = battle.field != null and gy > battle.field.terrain.height(pos.x, pos.z) + 0.4
	if pos.y <= gy + 0.02 and k.has("bounce") and vel.length() > 30.0 and not wall:
		# A ball that grazes the ground skips on, lower and slower.
		battle.spawn_puff(Vector3(pos.x, gy + 0.05, pos.z), Color(0.6, 0.52, 0.38), 0.8)
		p["pos"] = Vector3(pos.x, gy + 0.03, pos.z)
		p["vel"] = Vector3(vel.x * 0.75, absf(vel.y) * float(k["bounce"]), vel.z * 0.75)
		return float(p["age"]) < float(k["life"])
	if pos.y <= gy + 0.02:
		stats["ground"] += 1
		if k.has("shaft") and not wall:
			# It sticks where it fell, at the angle it came down.
			var l := float(k["shaft"])
			_stuck.append([Vector3(pos.x, gy, pos.z) - vel.normalized() * l * 0.35, vel.normalized(), l, 0.0])
			if _stuck.size() > STUCK_MAX:
				_stuck.pop_front()
			return false
		battle.spawn_puff(Vector3(pos.x, (prev.y if wall else gy) + 0.05, pos.z), Color(0.45, 0.38, 0.28) if not wall else Color(0.7, 0.66, 0.58), 0.35)
		_spent(p, not wall)
		return false
	if float(p["age"]) >= float(k["life"]):
		_spent(p, false)
		return false
	return true


## Done flying. A javelin that lands stays stuck in the ground a while.
func _spent(p: Dictionary, grounded: bool) -> void:
	if not p.has("node"):
		return
	var nd: Node3D = p["node"]
	if grounded:
		nd.position = Vector3(nd.position.x, battle.ground_y(nd.position) + 0.5, nd.position.z)
		var tw := nd.create_tween()
		tw.tween_interval(12.0)
		tw.tween_callback(nd.queue_free)
	else:
		nd.queue_free()


func _sweep_only(a: Vector3, b: Vector3, u: Node3D) -> Dictionary:
	if u == null or not is_instance_valid(u) or not u.alive:
		return {}
	var t := _cylinder_hit(a, b, u.global_position, float(u.hit_radius), float(u.hit_height))
	return {} if t < 0.0 else {"unit": u, "t": t}


func _step_grenade(p: Dictionary, k: Dictionary, prev: Vector3, pos: Vector3, vel: Vector3, delta: float) -> bool:
	# Bounce and roll on the ground.
	var gy: float = battle.ground_y(pos)
	if pos.y <= gy + 0.06:
		pos.y = gy + 0.06
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
func _sweep(a: Vector3, b: Vector3, shooter: Node3D, extra: float, exclude: Array = []) -> Dictionary:
	var best_t := 2.0
	var best: Node3D = null
	for entry in battle.units_near_segment(a, b):
		var u: Node3D = entry[0]
		if u == shooter or not u.alive or u in exclude:
			continue
		if shooter != null and is_instance_valid(shooter) and shooter.get("rig_kind") == "lizard" and u.get("rig_kind") == "lizard":
			continue # (their javelins fly over their own)
		var t := _cylinder_hit(a, b, entry[1], float(u.hit_radius) + extra, float(u.hit_height))
		if t >= 0.0 and t < best_t:
			best_t = t
			best = u
	var pl: Node3D = battle.player
	if pl != shooter and pl.alive and not pl in exclude:
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
	if shooter != null and is_instance_valid(shooter) and shooter.is_in_group("enemies") == u.is_in_group("enemies") and u.get("rig_kind") != "lizard":
		stats["own_side"] = int(stats.get("own_side", 0)) + 1 # (friendly fire, you included)
	var dmg := float(k["damage"])
	if u == battle.player:
		dmg = float(k.get("player_damage", dmg))
	dmg *= float(p.get("dmg_mult", 1.0))
	# Where it struck: the head and the chest kill, an arm or a leg wounds
	# (and a wounded leg slows a man, a wounded arm slows his loading and
	# his blows). Round shot takes whatever it hits.
	if p["kind"] != "roundshot":
		var zone := hit_zone(u, at)
		var table: Dictionary = PLAYER_ZONES if u == battle.player else ZONES
		dmg *= float(table.get(zone, 1.0))
		if u != battle.player and u.alive and u.has_method("wound"):
			u.wound(zone)
	u.take_shot(dmg, shooter)
	battle.spawn_puff(at, Color(0.5, 0.08, 0.06), 0.3)
	if shooter != null and is_instance_valid(shooter) and shooter.has_method("on_projectile_hit"):
		shooter.on_projectile_hit(u)


## Damage by where it struck (see hit_zone). A ball in the head or the chest
## kills even a big man; one in an arm or a leg rarely does on its own.
const ZONES := {"head": 3.0, "chest": 1.7, "arm": 0.45, "leg": 0.55, "horse": 0.8}
const PLAYER_ZONES := {"head": 1.6, "chest": 1.05, "arm": 0.6, "leg": 0.7, "horse": 1.0}


## Which part of a body a shot entering at `at` struck: by height up the
## body (head, chest, legs), and toward the sides at chest height, an arm.
## Mounted men: the rider above the saddle, the horse below.
static func hit_zone(u: Node3D, at: Vector3) -> String:
	var base := u.global_position
	var h_total: float = float(u.get("hit_height")) if u.get("hit_height") != null else 1.8
	var r: float = float(u.get("hit_radius")) if u.get("hit_radius") != null else 0.35
	var h := clampf((at.y - base.y) / maxf(h_total, 0.1), 0.0, 1.0)
	if u.get("mount") != null:
		if h > 0.88:
			return "head"
		return "chest" if h > 0.62 else "horse"
	if h > 0.84:
		return "head"
	if h < 0.47:
		return "leg"
	var f = u.get("facing")
	var facing: Vector3 = f if f != null else -u.global_transform.basis.z
	facing.y = 0.0
	var side := facing.normalized().cross(Vector3.UP)
	var off := at - base
	off.y = 0.0
	if absf(off.dot(side)) > r * 0.7:
		return "arm"
	return "chest"


## Line of fire: would a shot from `from` to `to` pass close to a comrade of
## `shooter` before reaching it? (Soldiers check this before pulling the trigger.)
func line_blocked(from: Vector3, to: Vector3, shooter: Node3D) -> bool:
	return blocked_by(from, to, shooter) != ""


## Who of the shooter's own side stands in the line of fire from `from` to
## `to`: "" (nobody), "friend", or "player" (you). The corridor widens with
## the distance like a smoothbore's cone, and you get a wider berth still.
## Only the stretch up to the target counts: past it (a melee) a miss may
## still find a friend.
func blocked_by(from: Vector3, to: Vector3, shooter: Node3D) -> String:
	var enemy_side: bool = shooter != null and is_instance_valid(shooter) and shooter.is_in_group("enemies")
	var length := maxf(from.distance_to(to), 0.01)
	var dir := (to - from) / length
	if not enemy_side:
		var pl: Node3D = battle.player
		if pl != shooter and pl.alive:
			var pp: Vector3 = pl.global_position
			var al := clampf((pp - from).dot(dir), 0.0, length)
			if _cylinder_hit(from, to, pp, 0.8 + 0.04 * al, 1.9) >= 0.0:
				return "player"
	for entry in battle.units_near_segment(from, to):
		var u: Node3D = entry[0]
		if u == shooter or not is_instance_valid(u) or not u.alive:
			continue
		if u.is_in_group("enemies") != enemy_side:
			continue
		var p: Vector3 = entry[1]
		var along := clampf((p - from).dot(dir), 0.0, length)
		if _cylinder_hit(from, to, p, float(u.hit_radius) + 0.1 + 0.035 * along, float(u.hit_height)) >= 0.0:
			return "friend"
	return ""


# ---------------------------------------------------------------- drawing

## An arrow or bolt: a dark shaft, pale fletching at the back.
func _shaft(buf: PackedFloat32Array, tip: Vector3, dir: Vector3, length: float) -> void:
	var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.97 else Vector3.BACK)
	var shaft := b * Basis.from_scale(Vector3(0.018, 0.018, length))
	var o := tip - dir * length * 0.5
	buf.append_array([shaft.x.x, shaft.y.x, shaft.z.x, o.x, shaft.x.y, shaft.y.y, shaft.z.y, o.y,
		shaft.x.z, shaft.y.z, shaft.z.z, o.z, SHAFT_COLOR.r, SHAFT_COLOR.g, SHAFT_COLOR.b, 1.0])
	var fl := b * Basis.from_scale(Vector3(0.05, 0.05, length * 0.18))
	var o2 := tip - dir * length * 0.88
	buf.append_array([fl.x.x, fl.y.x, fl.z.x, o2.x, fl.x.y, fl.y.y, fl.z.y, o2.y,
		fl.x.z, fl.y.z, fl.z.z, o2.z, FLETCH_COLOR.r, FLETCH_COLOR.g, FLETCH_COLOR.b, 1.0])


## Musket balls are too small and fast to see; a short bright streak along
## their path shows where each shot went.
func _draw_tracers() -> void:
	var buf := PackedFloat32Array()
	for p in _list:
		var k: Dictionary = KINDS[p["kind"]]
		if k.has("shaft"):
			var v: Vector3 = p["vel"]
			if v.length_squared() > 0.01:
				_shaft(buf, p["pos"], v.normalized(), float(k["shaft"]))
			continue
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
	for s in _stuck:
		_shaft(buf, s[0], s[1], s[2])
	var n := buf.size() / 16
	if _tracers.instance_count < n:
		_tracers.instance_count = maxi(64, nearest_po2(n))
	buf.resize(_tracers.instance_count * 16)
	_tracers.buffer = buf
	_tracers.visible_instance_count = n
