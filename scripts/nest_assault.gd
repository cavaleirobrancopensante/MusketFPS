extends Node3D
## Storming a lizard nest: the fortress, its garrison and how it fights.
##
##   the palisade  a ring of sharpened stakes lashed with bone on a bank of
##                 mud, with one gate of logs facing you; a siege (or the
##                 guns) leaves breaches in it. You can't walk through the
##                 stakes; nobody can.
##   the gate      has hit points: round shot, grenades and men hacking at
##                 it with axes and bayonets break it (musket balls barely
##                 scratch it). Down, it's a way in.
##   the garrison  some hold inside (until the gate falls or there's a way
##                 in), some throw javelins from platforms behind the stakes,
##                 and the rest sally out through the gate in waves: one
##                 at the start, another when the first is spent or the gate
##                 starts to give.
##
## Everyone who has to cross the palisade goes round by an opening (route()).
## The battle is won when every lizard is dead and no sally is left to come.

const Props := preload("res://scripts/props.gd")
const LizardScript := preload("res://scripts/lizardman.gd")

const R := 15.0 # the palisade's radius
const SEGMENTS := 40
const GATE_HP := 900.0
const STAKE := Color(0.72, 0.66, 0.52)
const MUD := Color(0.36, 0.29, 0.2)
const LOG := Color(0.33, 0.24, 0.15)

var battle
var centre := Vector3.ZERO
var gate_hp := GATE_HP
var gate_max := GATE_HP
var gate_open := false
var _gate_leaves: Array = []
var _gate_body: StaticBody3D
var _breaches: Array = [] # angles (radians from +Z) where the stakes are down
var _sallies: Array = [] # sizes still to come out
var _sally_t := 4.0
var _last_sally: Array = []
var _told_giving := false
var _opening_t := 0.0 # the gate swung open for a sally
var defenders: Array = [] # lizards holding inside
var throwers: Array = []
var _hack_t := 0.0
var stash := false
## In a field battle (field.gd): the garrison is regiments, not loose lizards.
var field = null
var defender_regs: Array = []


## Build it `dist` metres in front of `from` along `forward`, with `garrison`
## lizards; `walls` 1 = whole (fewer breaches), less after a siege.
func setup(b, from: Vector3, forward: Vector3, dist: float, garrison: int, walls: float, has_stash: bool) -> void:
	battle = b
	stash = has_stash
	centre = from + forward * dist
	centre.y = 0.0
	# The nest faces you: its gate toward where you stand.
	rotation.y = atan2(-forward.x, -forward.z) # (local +Z, the gate, back toward `from`)
	position = centre
	gate_max = GATE_HP * lerpf(0.45, 1.0, clampf(walls, 0.0, 1.0))
	gate_hp = gate_max
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("nest:%d:%d" % [garrison, int(walls * 100)])
	var breaks := int(round((1.0 - clampf(walls, 0.0, 1.0)) * 5.0))
	var free: Array = []
	for i in SEGMENTS:
		if i != 0 and i != 1 and i != SEGMENTS - 1:
			free.append(i)
	free.shuffle()
	var broken: Array = free.slice(0, breaks)
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		if i == 0:
			_build_gate(a)
		elif i in broken:
			_build_rubble(a, rng)
			_breaches.append(a)
		else:
			_build_segment(a, rng)
	_build_inside(rng)
	_place_garrison(garrison, rng)
	battle.objective = {"label": Lang.t("THE GATE"), "pos": gate_point(), "height": 3.6}


# ---------------------------------------------------------------- building

func _seg_transform(a: float) -> Transform3D:
	# Local space: +Z toward you (the gate), the ring around the centre.
	var p := Vector3(sin(a), 0, cos(a)) * R
	return Transform3D(Basis(Vector3.UP, a), p)


func _build_segment(a: float, rng: RandomNumberGenerator) -> void:
	var seg := Node3D.new()
	seg.transform = _seg_transform(a)
	add_child(seg)
	var w := TAU * R / SEGMENTS
	Props._box(seg, Vector3(w + 0.1, 0.7, 1.6), MUD, Vector3(0, 0.3, 0.0), Vector3(-8, 0, 0))
	for k in 5:
		var x := -w * 0.5 + (k + 0.5) * w / 5.0
		var h := rng.randf_range(2.5, 3.3)
		var st := Props._cyl(seg, 0.02, 0.13, h, STAKE.darkened(rng.randf_range(0.0, 0.25)), Vector3(x, h * 0.5 + 0.2, 0.2))
		st.rotation_degrees = Vector3(14 + rng.randf_range(-4, 4), 0, rng.randf_range(-5, 5)) # leaning outward
	Props._box(seg, Vector3(w, 0.07, 0.07), Color(0.88, 0.84, 0.72), Vector3(0, 1.4, 0.4)) # bone lashing
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 3.0, 0.9)
	cs.shape = bs
	cs.position = Vector3(0, 1.5, 0.1)
	body.add_child(cs)
	seg.add_child(body)


func _build_rubble(a: float, rng: RandomNumberGenerator) -> void:
	var seg := Node3D.new()
	seg.transform = _seg_transform(a)
	add_child(seg)
	Props._box(seg, Vector3(2.0, 0.35, 1.8), MUD, Vector3(0, 0.12, 0.2), Vector3(-6, 0, 0))
	for k in 3:
		var st := Props._cyl(seg, 0.03, 0.12, rng.randf_range(2.0, 2.8), STAKE.darkened(0.2), Vector3(rng.randf_range(-1, 1), 0.2, rng.randf_range(0.2, 1.4)))
		st.rotation_degrees = Vector3(rng.randf_range(70, 88), rng.randf_range(0, 180), 0) # thrown down


func _build_gate(a: float) -> void:
	var seg := Node3D.new()
	seg.transform = _seg_transform(a)
	add_child(seg)
	# Two posts and a lintel of logs, and the two leaves of the gate.
	for side in [-1.0, 1.0]:
		Props._cyl(seg, 0.2, 0.24, 4.0, LOG, Vector3(side * 1.35, 2.0, 0))
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 1.25, 0, 0.1)
		seg.add_child(hinge)
		for k in 3:
			Props._cyl(hinge, 0.14, 0.15, 2.9, LOG.lightened(0.05 * k), Vector3(-side * (0.22 + k * 0.38), 1.45, 0), Vector3.ZERO)
		Props._box(hinge, Vector3(1.2, 0.12, 0.12), Color(0.88, 0.84, 0.72), Vector3(-side * 0.6, 2.2, 0.15)) # bone bar
		Props._box(hinge, Vector3(1.2, 0.12, 0.12), Color(0.88, 0.84, 0.72), Vector3(-side * 0.6, 0.8, 0.15))
		_gate_leaves.append([hinge, side])
	Props._box(seg, Vector3(3.4, 0.35, 0.35), LOG, Vector3(0, 3.9, 0))
	# A skull on the lintel.
	Props._box(seg, Vector3(0.35, 0.3, 0.3), Color(0.9, 0.86, 0.74), Vector3(0, 4.25, 0.1))
	_gate_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 3.0, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 1.5, 0.1)
	_gate_body.add_child(cs)
	seg.add_child(_gate_body)


func _build_inside(rng: RandomNumberGenerator) -> void:
	# Mud mounds (their dens), totems hung with bones, a fire pit.
	for i in 7:
		var a := rng.randf() * TAU
		var d := rng.randf_range(3.0, R - 4.5)
		var r := rng.randf_range(1.6, 2.6)
		var m := Props._cyl(self, r * 0.35, r, r * 1.1, MUD.darkened(rng.randf_range(0.0, 0.2)), Vector3(sin(a) * d, r * 0.55, cos(a) * d - 1.5))
		m.name = "mound"
	for i in 4:
		var a2 := rng.randf() * TAU
		var d2 := rng.randf_range(2.0, 8.0)
		var at := Vector3(sin(a2) * d2, 0, cos(a2) * d2)
		Props._cyl(self, 0.1, 0.14, 3.6, LOG, at + Vector3(0, 1.8, 0))
		Props._box(self, Vector3(0.3, 0.28, 0.28), Color(0.9, 0.86, 0.74), at + Vector3(0, 3.7, 0))
	if stash:
		# The ship's stores: crates with her mark, powder kegs, the guns.
		for i in 6:
			Props._box(self, Vector3(1.0, 0.7, 0.7), Color(0.5, 0.36, 0.2), Vector3(-3.0 + i * 0.9, 0.35 + (i % 2) * 0.7, -4.0), Vector3(0, rng.randf_range(-10, 10), 0))
			Props._box(self, Vector3(0.5, 0.3, 0.02), Color(0.85, 0.82, 0.7), Vector3(-3.0 + i * 0.9, 0.4 + (i % 2) * 0.7, -3.64))
		for i in 4:
			Props._cyl(self, 0.3, 0.3, 0.75, Color(0.32, 0.22, 0.14), Vector3(3.0 + (i % 2) * 0.7, 0.38, -3.0 - i * 0.4))
		for i in 2:
			var g := Props.cannon()
			g.position = Vector3(-1.5 + i * 3.5, 0, -7.5)
			g.rotation.y = rng.randf_range(-0.6, 0.6)
			add_child(g)
	# Throwing platforms behind the stakes, facing you.
	for i in 5:
		var a3 := lerpf(-0.95, 0.95, i / 4.0)
		var p := Vector3(sin(a3), 0, cos(a3)) * (R - 2.2)
		Props._box(self, Vector3(1.6, 1.2, 1.6), LOG.darkened(0.1), p + Vector3(0, 0.6, 0))


func _place_garrison(garrison: int, rng: RandomNumberGenerator) -> void:
	var inside := mini(int(ceil(garrison * 0.45)), 60)
	var out := mini(garrison - inside, 90)
	if out > 0:
		var first := int(ceil(out * 0.45))
		_sallies = [first, out - first]
	if field != null:
		var t := mini(8, inside / 4)
		field.garrison(self, inside - t, t)
		return
	var n_throw := mini(5, inside / 4)
	for i in inside:
		var l = LizardScript.new()
		l.battle = battle
		l.frames = battle.lizard_frames
		l.garrison = true
		var p: Vector3
		if i < n_throw:
			var a := lerpf(-0.95, 0.95, i / 4.0)
			p = Vector3(sin(a), 0, cos(a)) * (R - 2.2) + Vector3(0, 1.2, 0)
			l.thrower = true
			throwers.append(l)
		else:
			var a2 := rng.randf() * TAU
			var d := rng.randf_range(2.0, R - 3.0)
			p = Vector3(sin(a2) * d, 0, cos(a2) * d)
		l.hold_at = to_global(p)
		l.position = l.hold_at
		battle.enemies.append(l)
		battle.add_child(l)
		defenders.append(l)


# ---------------------------------------------------------------- the fight

func _process(delta: float) -> void:
	if battle == null:
		return
	# Men at the gate hack at it (you too).
	_hack_t -= delta
	if not gate_open and _hack_t <= 0.0:
		_hack_t = 0.5
		var g := gate_point()
		var n := 0
		for s in battle.soldiers + (battle.allies if field != null else []):
			if is_instance_valid(s) and s.alive and s.global_position.distance_to(g) < 3.4:
				n += 1
		if battle.player.alive and battle.player.global_position.distance_to(g) < 3.0:
			n += 2
		if n > 0:
			damage_gate(9.0 * 0.5 * n)
			if randf() < 0.5:
				battle.play_sound("thud", g + Vector3.UP, -6.0)
	# Sallies out of the gate.
	if not _sallies.is_empty():
		_sally_t -= delta
		var spent := _last_sally.filter(func(l): return is_instance_valid(l) and l.alive).size() <= maxi(2, _last_sally.size() / 4)
		if (_sally_t <= 0.0 and spent) or (_sally_t <= -10.0 and gate_hp < gate_max * 0.5):
			_sally(int(_sallies.pop_front()))
			_sally_t = 12.0
	if _opening_t > 0.0:
		_opening_t -= delta
	_animate_gate(delta)
	# Once the gate is down, or yours are at the stakes, the defenders come.
	if field != null and not defender_regs.is_empty() and (gate_open or _friend_near()):
		field.release(defender_regs)
		if field.test_mode:
			print("NEST garrison loosed at ", int(field.clock), " gate open ", gate_open)
		defender_regs = []
	if gate_open or _friend_near():
		for d in defenders:
			if is_instance_valid(d):
				d.garrison = false
	# The gate's down: the throwers jump off their platforms to fight.
	if gate_open and not throwers.is_empty():
		for l in throwers:
			if is_instance_valid(l) and l.thrower:
				l.thrower = false
				l.position.y = 0.0
		throwers = []


func _sally(n: int) -> void:
	if n <= 0:
		return
	_opening_t = 4.0
	if field != null:
		_last_sally = field.sally(self, n)
		if battle.hud != null:
			battle.hud.show_message(Lang.t("The gate swings open: they're coming out!"), 2.0)
		battle.play_sound("roar", gate_point() + Vector3.UP * 2.0, 4.0)
		return
	var out := gate_point() + (gate_point() - centre).normalized() * 2.5
	var right := (gate_point() - centre).normalized().cross(Vector3.UP)
	_last_sally = []
	for i in n:
		var l = LizardScript.new()
		l.battle = battle
		l.frames = battle.lizard_frames
		l.position = out + right * randf_range(-4.0, 4.0) + (gate_point() - centre).normalized() * randf_range(0.0, 6.0)
		battle.enemies.append(l)
		battle.add_child(l)
		_last_sally.append(l)
	battle.hud.show_message(Lang.t("The gate swings open: they're coming out!"), 2.0)
	battle.play_sound("roar", out + Vector3.UP * 2.0, 4.0)


func pending_sallies() -> int:
	return _sallies.size()


func damage_gate(amount: float) -> void:
	if gate_open:
		return
	gate_hp -= amount
	if not _told_giving and gate_hp < gate_max * 0.5:
		_told_giving = true
		if battle.hud != null:
			battle.hud.show_message(Lang.t("The gate is giving!"), 1.6)
	if gate_hp <= 0.0:
		gate_open = true
		_gate_body.queue_free()
		if field != null:
			field.wall_nest() # (the way in is open)
			if field.test_mode:
				print("NEST gate down at ", int(field.clock))
		battle.play_sound("crack", gate_point() + Vector3.UP, 6.0)
		battle.play_sound("boom", gate_point(), -2.0)
		for i in 4:
			battle.spawn_smoke(gate_point() + Vector3(randf_range(-1.5, 1.5), randf_range(0.2, 2.0), randf_range(-1, 1)), 2.0)
		if battle.hud != null:
			battle.hud.show_message(Lang.t("The gate is down! Into the nest!"), 2.5)
		battle.objective = {"label": Lang.t("STORM THE NEST"), "pos": centre, "height": 3.0}


func _animate_gate(delta: float) -> void:
	for lf in _gate_leaves:
		var hinge: Node3D = lf[0]
		var side: float = lf[1]
		if gate_open:
			# Smashed off its hinges: fallen flat outward.
			hinge.rotation.x = move_toward(hinge.rotation.x, 1.45, delta * 2.5)
			hinge.rotation.y = move_toward(hinge.rotation.y, side * 0.3, delta)
		else:
			var want := side * 1.2 if _opening_t > 0.6 else 0.0
			hinge.rotation.y = move_toward(hinge.rotation.y, want, delta * 1.8)
			# Shudders under the blows.
			hinge.rotation.x = 0.03 * sin(Time.get_ticks_msec() * 0.03) * (1.0 - gate_hp / gate_max)


func is_open() -> bool:
	return gate_open or not _breaches.is_empty()


func openings() -> Array:
	return _openings()


func _friend_near() -> bool:
	if battle.player.alive and _near(battle.player.global_position):
		return true
	for s in battle.soldiers:
		if s.alive and _near(s.global_position):
			return true
	return false


func _near(p: Vector3) -> bool:
	return Vector2(p.x - centre.x, p.z - centre.z).length() < R + 4.0 and (_breaches.size() > 0 or inside(p))


func inside(p: Vector3) -> bool:
	return Vector2(p.x - centre.x, p.z - centre.z).length() < R


func gate_point() -> Vector3:
	return to_global(Vector3(0, 0, R))


## The ways through the palisade: the gate (when it's down) and any breaches.
func _openings() -> Array:
	var out: Array = []
	if gate_open:
		out.append(gate_point())
	for a in _breaches:
		out.append(to_global(Vector3(sin(a), 0, cos(a)) * R))
	return out


## Where to walk next to get from `from` to `to`: straight there, or round
## by the nearest opening if the stakes are in the way (to the gate if
## there's none, to hack at it or wait behind it).
func route(from: Vector3, to: Vector3) -> Vector3:
	var fi := inside(from)
	if fi == inside(to):
		return to
	var best := Vector3.INF
	var bd := INF
	for op in _openings():
		var d: float = from.distance_to(op) + op.distance_to(to)
		if d < bd:
			bd = d
			best = op
	var g := gate_point()
	var outward := (g - centre).normalized()
	if best == Vector3.INF:
		# No way in: to the gate (outside to batter it; inside to wait).
		return g + outward * (1.6 if not fi else -1.8)
	var dir := (best - centre)
	dir.y = 0.0
	dir = dir.normalized()
	var near := best + dir * (1.8 if not fi else -1.8)
	var far := best - dir * (1.8 if not fi else -1.8)
	if Vector2(from.x - best.x, from.z - best.z).length() < 1.6:
		return far # in the opening: through
	return near


## A defender holding inside: walk to his post and wait, facing the gate;
## the throwers hurl javelins over the stakes. Returns true while holding.
func hold(l, delta: float) -> bool:
	if not l.garrison and not l.thrower:
		return false
	if l.thrower:
		var foe = battle.nearest_friendly(l.global_position)
		if foe == null:
			return true
		var to: Vector3 = foe.global_position - l.global_position
		to.y = 0.0
		if to.length() < 5.0:
			# Someone's on him: down off the platform to fight.
			l.thrower = false
			l.position.y = 0.0
			return false
		l.face_toward(to)
		l.set_base_anim("idle")
		l.velocity = Vector3.ZERO
		l.throw_t -= delta
		if l.throw_t <= 0.0 and to.length() < 34.0:
			l.throw_t = randf_range(3.5, 5.5)
			var from: Vector3 = l.global_position + Vector3.UP * 1.9
			var aim: Vector3 = foe.global_position + Vector3.UP * 1.1
			var v := throw_velocity(from, aim, 22.0)
			battle.projectiles.fire("javelin", from, battle.projectiles.spread_dir(v, 0.05) * v.length(), l)
			l.play_oneshot("strike", 0.3)
			battle.play_sound("swish", from, -6.0)
		return true
	var to_post: Vector3 = l.hold_at - l.global_position
	to_post.y = 0.0
	if to_post.length() > 0.6:
		l.velocity = to_post.normalized() * 2.0
		l.face_toward(to_post)
		l.set_base_anim("walk")
		l._move(delta)
	else:
		l.velocity = Vector3.ZERO
		l.face_toward(gate_point() - l.global_position)
		l.set_base_anim("idle")
	return true


## Launch velocity for a thrown javelin: the low arc that lands on `to`.
static func throw_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var g := 9.8
	var d := Vector2(to.x - from.x, to.z - from.z)
	var dh := maxf(d.length(), 0.5)
	var dy := to.y - from.y
	var dir := Vector3(d.x, 0, d.y) / dh
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * dh * dh + 2.0 * dy * v2)
	var ang := PI * 0.25 if disc < 0.0 else atan((v2 - sqrt(disc)) / (g * dh))
	return (dir * cos(ang) + Vector3.UP * sin(ang)) * speed


## A projectile from a to b: does it hit the gate? Round shot smashes it,
## a musket ball barely marks it. Returns true if it stopped there.
func hit_structure(a: Vector3, b: Vector3, kind: String) -> bool:
	if gate_open:
		return false
	var g := gate_point()
	var outward := (g - centre).normalized()
	# The gate is a plane across the opening: where does the shot cross it?
	var da := (a - g).dot(outward)
	var db := (b - g).dot(outward)
	if da * db > 0.0:
		return false
	var t := da / (da - db)
	var p := a.lerp(b, t)
	var side := outward.cross(Vector3.UP).normalized()
	if absf((p - g).dot(side)) > 1.4 or p.y > 3.1 or p.y < 0.0:
		return false
	if kind == "javelin":
		return false
	var dmg: float = {"roundshot": 150.0, "canister": 6.0, "ball": 3.0, "pistol": 2.0, "arrow": 0.5, "bolt": 1.5, "javelin": 0.0}.get(kind, 1.0)
	damage_gate(dmg)
	battle.spawn_puff(p, Color(0.45, 0.35, 0.22), 0.8 if kind == "roundshot" else 0.3)
	return true


## A grenade going off by the gate.
func blast(pos: Vector3, radius: float) -> void:
	if gate_open:
		return
	var d := pos.distance_to(gate_point() + Vector3.UP * 0.5)
	if d < radius:
		damage_gate(lerpf(180.0, 40.0, d / radius))


## Victory needs every lizard dead and no sally left inside.
func done() -> bool:
	return _sallies.is_empty()
