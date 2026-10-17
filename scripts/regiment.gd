extends RefCounted
## One unit of a field battle (Tests > Field battle): a block of men, a
## troop of horse or a battery of guns that moves, faces, fires and fights
## as one, the way a Total War unit does.
##
## The regiment owns the plan; its men own their own feet and blades:
##   - `pos` is the middle of the front rank and `forward` the way it faces;
##     every man has a slot (file and rank) relative to that, on the ground
##   - orders (from you through the command view, or the enemy's general):
##       hold      stand where you are, face forward, fire at will
##       move      march along a path (round houses and deep water), in
##                 column for a long march, and form line at the end
##       attack    close with a regiment: shooters to their range, then fire;
##                 blades and horse to charging distance, then charge
##       charge    at a regiment now, every man for the nearest of them
##       follow    (your own company) form on you as you walk, like the
##                 campaign's FOLLOW
##   - morale (see field.gd for what moves it): wavering men shoot slower;
##     a routing regiment runs for its own edge of the field, and may rally
##     if nobody chases it; a shattered one (most of it dead) never comes back

var field
var id := 0
var side := 0
var kind := "musket"
var info: Dictionary = {}
var title := ""
var members: Array = []
var size0 := 0
var player_led := false # your own company: follows you, and stands while you live

var pos := Vector3.ZERO
var forward := Vector3.FORWARD
var files := 10
var spacing := 1.4
var rank_gap := 1.5
var column := false

var order := "hold"
var path: Array = []
var dest_forward := Vector3.FORWARD
var run := false
var target = null # regiment: the attack or charge order's object
var fire_target = null # regiment its shooters aim at
var fire_at_will := true
var volley_now := false
var _volley_t := 0.0
var charging := false
var braced := false # pikes: levelled and standing to receive horse
var moving := false

var morale := 70.0
var max_morale := 70.0
var state := "formed" # formed, wavering, routing, shattered, gone
var engaged_t := -99.0
var foes_close := false
var nearest_foe_reg = null
var nearest_foe_d := INF
var _rally_t := 0.0
var _shaken := {} # one-off morale blows already taken (reg id or key -> true)
var centroid := Vector3.ZERO
var ai_t := 0.0
var _charge_t := 0.0
var _hurt_acc := 0.0
var selected := false
var _arrive_t := 0.0


## "is" or "are": a regiment's name is plural ("1st Pikemen"), but not your
## company or a battery.
func verb(one: String, many: String) -> String:
	return one if player_led or kind == "gun" else many


func alive_count() -> int:
	return members.size()


func strength() -> float:
	return float(members.size()) / maxf(1.0, size0)


func is_cav() -> bool:
	return bool(info.get("cav", false))


func is_gun() -> bool:
	return kind == "gun"


func is_ranged() -> bool:
	return float(info.get("range", 0.0)) > 0.0


## Half the angle in front it can shoot into (radians): a line of muskets
## or bows wide, a battery's guns less (the trails have to be shifted).
func fire_arc() -> float:
	return 1.0 if is_gun() else acos(0.25)


func range_m() -> float:
	return float(info.get("range", 0.0))


func gone() -> bool:
	return state == "gone" or members.is_empty()


func broken() -> bool:
	return state in ["routing", "shattered", "gone"] or members.is_empty()


func engaged() -> bool:
	return field.clock - engaged_t < 1.2


# ---------------------------------------------------------------- the block

func right() -> Vector3:
	return forward.cross(Vector3.UP).normalized()


func files_now() -> int:
	return 4 if column and not is_gun() else files


## Width of the front (metres).
func width() -> float:
	return (mini(files_now(), members.size()) - 1) * spacing


func slot(i: int) -> Vector3:
	var f := files_now()
	var n := members.size()
	var rank := i / f
	var file := i % f
	var in_rank := mini(f, n - rank * f)
	var x := (file - (in_rank - 1) * 0.5) * spacing
	if player_led:
		# A gap in the middle of the line for you, as in the campaign.
		x += spacing * 0.6 * (1.0 if x >= 0.0 else -1.0)
	var gap := rank_gap if not column else maxf(rank_gap, 1.6)
	var p := pos + right() * x - forward * rank * gap
	if is_cav() or kind in ["liz_warrior", "liz_brute", "liz_skirm"]:
		# A mob or a troop doesn't stand in perfect files.
		var h := hash(i * 7919 + id * 104729)
		p += right() * (float(h % 100) / 100.0 - 0.5) * spacing * 0.35
		p += forward * (float((h / 100) % 100) / 100.0 - 0.5) * gap * 0.35
	p.y = field.terrain.height(p.x, p.z)
	return p


func march_speed() -> float:
	var s: float = float(info["run"] if run else info["walk"]) * field.pace
	if state == "wavering":
		s *= 0.85
	return s


func run_speed() -> float:
	return float(info["run"]) * field.pace


func may_fire() -> bool:
	return (fire_at_will or volley_now) and not charging and not broken() and fire_target != null and not fire_target.broken()


## Whom a man shoots at: a man of the target regiment, picked by his own
## place in the line, so the fire spreads along theirs.
func shot_at(u) -> Node3D:
	if fire_target == null or fire_target.members.is_empty():
		return null
	var n: int = fire_target.members.size()
	var k := (int(u.slot_index) * 7 + int(field.clock * 0.25)) % n
	var t = fire_target.members[k]
	if is_instance_valid(t) and t.alive:
		return t
	return null


## In a charge: the nearest man of the regiment we're charging (or of
## anyone, when that's gone).
func charge_foe(u) -> Node3D:
	if target != null and not target.members.is_empty():
		var best: Node3D = null
		var bd := INF
		var p: Vector3 = u.global_position
		# Only look at a handful: every 3rd man and the ones nearest our slot.
		var step := maxi(1, target.members.size() / 10)
		var off := int(u.slot_index) % step
		for i in range(off, target.members.size(), step):
			var m = target.members[i]
			if not is_instance_valid(m) or not m.alive:
				continue
			var d := p.distance_squared_to(m.global_position)
			if d < bd:
				bd = d
				best = m
		return best
	return field.nearest_foe(u, 40.0)


## Where its men run when it breaks: straight back to their own edge.
func flee_point(u) -> Vector3:
	if side == 0 and field.story != null:
		return field.story.flee_point(u) # (the beach: the cliff path, not the sea)
	var p: Vector3 = u.global_position
	var z: float = field.terrain.HALF + 10.0 if side == 0 else -field.terrain.HALF - 10.0
	return Vector3(p.x * 0.8, 0, z)


# ---------------------------------------------------------------- orders

func order_hold() -> void:
	order = "hold"
	path = []
	target = null
	charging = false
	run = false


var order_t := 0.0 # field clock when the order was given


func order_move(to: Vector3, face: Vector3, at_run := false) -> void:
	order_t = field.clock
	order = "move"
	charging = false
	target = null
	run = at_run
	dest_forward = face.normalized() if face.length_squared() > 0.01 else forward
	path = field.terrain.path(pos, to)
	_arrive_t = 0.0


var last_shot_t := -99.0


## One of its men (or guns) loosed a shot.
func fired() -> void:
	last_shot_t = field.clock


func order_attack(r) -> void:
	order_t = field.clock
	last_shot_t = field.clock
	order = "attack"
	target = r
	fire_target = r
	charging = false
	run = false
	path = []


func order_charge(r) -> void:
	if r == null:
		r = nearest_foe_reg
	if r == null:
		return
	if is_cav() and side == 1 and r.side == 0 and target != r:
		field.alert(r, "Their %s are charging %s!" % [String(info["name"]).to_lower(), r.title if not r.player_led else "your company"], true)
	order = "charge"
	target = r
	charging = true
	_charge_t = 0.0
	for m in members:
		if m.has_method("new_charge"):
			m.new_charge()


func order_fallback() -> void:
	var back := pos - forward * 40.0
	back.x = clampf(back.x, -field.terrain.HALF + 10.0, field.terrain.HALF - 10.0)
	back.z = clampf(back.z, -field.terrain.HALF + 10.0, field.terrain.HALF - 10.0)
	order_move(back, forward, true)


func order_volley() -> void:
	volley_now = true
	_volley_t = 1.2


# ---------------------------------------------------------------- the tick

## Every few frames (field.gd staggers them): close the ranks, move the
## block, pick targets, keep up the charge.
func tick(dt: float) -> void:
	# The dead and the fled leave the ranks; the man at the back steps up.
	var i := 0
	while i < members.size():
		var m = members[i]
		if not is_instance_valid(m) or not m.alive or m.get_meta("fled", false):
			var last = members.pop_back()
			if i < members.size():
				members[i] = last
				if is_instance_valid(last):
					last.slot_index = i
			continue
		i += 1
	if members.is_empty():
		state = "gone"
		return
	var c := Vector3.ZERO
	for m in members:
		c += m.global_position
	centroid = c / members.size()
	if _volley_t > 0.0:
		_volley_t -= dt
		if _volley_t <= 0.0:
			volley_now = false
	if broken():
		charging = false
		moving = false
		pos = centroid
		return
	braced = kind == "pike" and not moving and not charging
	match order:
		"follow":
			_follow(dt)
		"move":
			_march(dt)
		"attack":
			_attack(dt)
		"charge":
			_charge(dt)
		_:
			moving = false
	_pick_fire_target()


func _follow(_dt: float) -> void:
	var p: Node3D = field.battle.player
	if not p.alive:
		order = "hold"
		return
	var f: Vector3 = field.battle._player_forward()
	if rad_to_deg(f.angle_to(forward)) > 40.0:
		forward = f
	var want := Vector3(p.global_position.x, 0, p.global_position.z)
	moving = pos.distance_to(want) > 1.0
	pos = want
	column = false


func _cohesion() -> float:
	# How far the men are from their slots (a sample of them).
	var n := mini(members.size(), 8)
	var s := 0.0
	for k in n:
		var m = members[(k * 5) % members.size()]
		var sl := slot(m.slot_index)
		s += Vector2(m.global_position.x - sl.x, m.global_position.z - sl.z).length()
	return s / maxf(1.0, n)


func _march(dt: float) -> void:
	if path.is_empty():
		_arrive(dt)
		return
	var to: Vector3 = path[0] - pos
	to.y = 0.0
	var d := to.length()
	var total := d
	for k in range(1, path.size()):
		total += (path[k] as Vector3).distance_to(path[k - 1])
	# Column for a long march or a narrow way; line again near the end.
	if not is_gun() and not is_cav() and files > 6:
		if total > 35.0 or path.size() > 1:
			column = true
		elif total < 14.0:
			column = false
	if d < 0.6:
		path.pop_front()
		return
	moving = true
	var dir := to / d
	# Wheel toward the way we're going (a line wheels slowly).
	var turn := 0.9 if not column else 2.5
	if is_cav():
		turn = 1.6
	var ang := forward.signed_angle_to(dir, Vector3.UP)
	if path.size() == 1 and d < 12.0 and not column:
		ang = forward.signed_angle_to(dest_forward, Vector3.UP) # face the way you'll stand
	forward = (Basis(Vector3.UP, clampf(ang, -turn * dt, turn * dt)) * forward).normalized()
	var spd: float = march_speed() * field.terrain.speed_factor(pos, dir)
	var coh := _cohesion()
	if coh > 3.5:
		spd *= clampf(1.0 - (coh - 3.5) / 6.0, 0.2, 1.0)
	pos += dir * minf(d, spd * dt)
	pos.y = field.terrain.height(pos.x, pos.z)


func _arrive(dt: float) -> void:
	column = false
	var ang := forward.signed_angle_to(dest_forward, Vector3.UP)
	forward = (Basis(Vector3.UP, clampf(ang, -1.2 * dt, 1.2 * dt)) * forward).normalized()
	moving = absf(ang) > 0.05
	if not moving:
		order = "hold"
		run = false


func _attack(dt: float) -> void:
	if target == null or target.broken():
		order_hold()
		return
	var tc: Vector3 = target.centroid
	var to := tc - pos
	to.y = 0.0
	var d := to.length()
	if is_ranged() and not is_cav():
		var want := range_m() * (0.8 if not is_gun() else 0.95)
		# In range but nobody's been able to fire (houses or a hill in the
		# way): close in until they can.
		if field.clock - last_shot_t > 9.0 and field.clock - order_t > 9.0:
			want = maxf(12.0, d - 15.0)
		fire_target = target
		if d > want:
			# Close to range: re-path now and then.
			if path.is_empty() or randf() < dt * 0.3:
				path = field.terrain.path(pos, tc - to / maxf(d, 0.01) * want * 0.95)
				dest_forward = to / maxf(d, 0.01)
			_march(dt)
		else:
			path = []
			moving = false
			column = false
			var ang := forward.signed_angle_to(to / maxf(d, 0.01), Vector3.UP)
			forward = (Basis(Vector3.UP, clampf(ang, -0.9 * dt, 0.9 * dt)) * forward).normalized()
		return
	# Blades and horse: close, then charge.
	var charge_at := 30.0 if is_cav() else 22.0
	if d < charge_at:
		order_charge(target)
		return
	if path.is_empty() or randf() < dt * 0.5:
		path = field.terrain.path(pos, tc)
		dest_forward = to / maxf(d, 0.01)
	run = d > 60.0 and is_cav()
	_march(dt)


func _charge(dt: float) -> void:
	_charge_t += dt
	moving = true
	column = false
	if target == null or target.broken():
		charging = false
		# Charged home and they broke: halt where we are (horse may pursue).
		pos = centroid
		order_hold()
		return
	var to: Vector3 = target.centroid - centroid
	to.y = 0.0
	if to.length() > 0.1:
		forward = to.normalized()
	pos = centroid + forward * 2.0
	# Horse that has charged home and is stuck in: out, wheel, and again.
	if is_cav() and _charge_t > 7.0 and engaged():
		var back := centroid - forward * 35.0
		order_move(back, forward, true)
		field.cav_regroup(self)
		return
	if _charge_t > 25.0 and not engaged() and to.length() > 45.0:
		order_attack(target) # they slipped away: close again in order


## Shooters pick the regiment to aim at: the attack target if in range,
## otherwise the nearest in range in front of them.
func _pick_fire_target() -> void:
	if not is_ranged():
		fire_target = null
		return
	if target != null and not target.broken() and order == "attack" and target.centroid.distance_to(centroid) < range_m() * 1.05:
		fire_target = target
		return
	if fire_target != null and (fire_target.broken() or fire_target.centroid.distance_to(centroid) > range_m() * 1.1):
		fire_target = null
	if fire_target == null:
		var best = null
		var bd := range_m()
		for r in field.regs:
			if r.side == side or r.broken():
				continue
			var to: Vector3 = r.centroid - centroid
			to.y = 0.0
			var d := to.length()
			if d < bd and (to.normalized().dot(forward) > cos(fire_arc()) or d < 20.0):
				bd = d
				best = r
		fire_target = best


# ---------------------------------------------------------------- morale

## A man hurt or killed: a little of the regiment's nerve goes with him.
func hurt(_amount: float) -> void:
	_hurt_acc += 1.0


## A one-off blow to its nerve from something (a charge into its flank,
## a neighbour breaking): counted once per cause.
func shock(by, amount: float) -> void:
	var key = by.get_instance_id() if by is Object else by
	if _shaken.has(key):
		return
	_shaken[key] = true
	morale -= amount


## Morale over the last half second (field.gd calls it).
func morale_tick(dt: float, losses: int) -> void:
	if state in ["shattered", "gone"]:
		return
	# Losing half the regiment costs about 30 points of nerve.
	var loss_hit := 100.0 / maxf(8.0, size0) * 0.6
	morale = maxf(0.0, morale - losses * loss_hit)
	_hurt_acc = 0.0
	if strength() < 0.25:
		_set_state("shattered")
		return
	var calm := not engaged() and nearest_foe_d > 30.0
	if state == "routing":
		if calm and nearest_foe_d > 40.0:
			morale += 4.0 * dt
			_rally_t += dt
			if _rally_t > 6.0 and morale > max_morale * 0.45 and strength() > 0.4 and not (side == 0 and field.story != null):
				_set_state("formed")
				field._broke_told.erase(self)
				_shaken.clear()
				field.alert(self, "%s %s!" % [title, verb("rallies", "rally")], false)
		else:
			_rally_t = 0.0
		return
	if calm:
		morale = minf(max_morale, morale + 1.2 * dt)
	# Near you (your own side), men stand.
	if side == 0 and field.battle.player.alive and field.battle.player.global_position.distance_to(centroid) < 25.0:
		morale = minf(max_morale, morale + 2.5 * dt)
	if player_led and field.battle.player.alive:
		morale = maxf(morale, 16.0) # they won't leave you
	if morale < 12.0:
		_set_state("routing")
	elif morale < max_morale * 0.4:
		if state == "formed":
			_set_state("wavering")
	elif state == "wavering" and morale > max_morale * 0.5:
		_set_state("formed")


func _set_state(s: String) -> void:
	if s == state:
		return
	var was := state
	state = s
	if s in ["routing", "shattered"]:
		charging = false
		order = "hold"
		path = []
		_rally_t = 0.0
		field.on_regiment_broke(self, was)
	elif s == "wavering":
		field.alert(self, "%s %s wavering!" % [title, verb("is", "are")], side == 0)
