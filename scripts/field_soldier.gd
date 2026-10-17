extends "res://scripts/soldier.gd"
## A man of a regiment in a field battle (Tests > Field battle): musketeer,
## pikeman, bowman or crossbowman, on either side.
##
## He doesn't take orders from you directly: his regiment (regiment.gd)
## tells him where his place in the block is, whom to shoot at, when to
## charge and when to run. He still fights his own fight up close (parry,
## thrust, give ground), fires in his own time, and shoots at men of the
## regiment his officers point at, not the nearest body.
##
## side 0 is yours (in battle.soldiers if he's in your own company, else in
## battle.allies); side 1 the enemy's (in battle.enemies, red coats).

const ENEMY_COAT := Color(0.62, 0.12, 0.1)
const GEAR := {
	"musket": {"head": "shako", "torso": "coat", "primary": "musket", "secondary": "bayonet"},
	"pike": {"head": "kettle_hat", "torso": "buffcoat", "primary": "pike", "secondary": ""},
	"bow": {"head": "hood", "torso": "jack", "primary": "war_bow", "secondary": "long_knife"},
	"xbow": {"head": "kettle_hat", "torso": "jack", "primary": "crossbow", "secondary": "hatchet"},
}
const ENEMY_GEAR := {
	"musket": {"head": "tricorne", "torso": "coat", "primary": "musket", "secondary": "bayonet"},
	"pike": {"head": "kettle_hat", "torso": "coat", "primary": "pike", "secondary": ""},
	"bow": {"head": "tricorne", "torso": "coat", "primary": "war_bow", "secondary": "long_knife"},
	"xbow": {"head": "kettle_hat", "torso": "coat", "primary": "crossbow", "secondary": "hatchet"},
}

var reg = null
var side := 0
var field
var stagger_time := 0.0
var _knock := Vector3.ZERO
var windup := -1.0 # (lizards read this off their foes; men never wind up)
var in_melee_t := -99.0 # field clock of his last blow traded


## A man for a regiment of `kind` on `side`. Call before adding him.
static func make(b, f, kind: String, s: int):
	var me = load("res://scripts/field_soldier.gd").new()
	me.battle = b
	me.field = f
	me.side = s
	me.ally = true
	me.frames = b.soldier_frames
	var rec: Dictionary = Company.make_recruit()
	rec["gear"] = gear_for(f, kind, s).duplicate()
	rec["pack"] = {"water": 1, "rations": 1, "ammo": 0 if kind == "pike" else 60}
	rec["morale"] = 60
	rec["rank"] = 1 if randf() < 0.2 else 0
	me.record = rec
	if s == 1:
		me.rig_coat = f.foe_coat
	elif f._making_allied:
		me.rig_coat = f.ally_coat
		rec["gear"] = (NATION_GEAR[kind] as Dictionary).duplicate()
	return me


## A nation's soldiers (no gunpowder in this land): kettle hats over their
## coats, spears, war bows and crossbows.
const NATION_GEAR := {
	"musket": {"head": "kettle_hat", "torso": "coat", "primary": "pike", "secondary": ""},
	"pike": {"head": "kettle_hat", "torso": "coat", "primary": "pike", "secondary": ""},
	"bow": {"head": "hood", "torso": "coat", "primary": "war_bow", "secondary": "long_knife"},
	"xbow": {"head": "kettle_hat", "torso": "coat", "primary": "crossbow", "secondary": "hatchet"},
}


static func gear_for(f, kind: String, s: int) -> Dictionary:
	if s == 0:
		return GEAR[kind]
	return (NATION_GEAR if String(f.nation) != "" else ENEMY_GEAR)[kind]


## One of your own men (a campaign record: his kit, his cartridges, his
## name and his traits all come with him).
static func from_record(b, f, rec: Dictionary, s: int):
	var me = load("res://scripts/field_soldier.gd").new()
	me.battle = b
	me.field = f
	me.side = s
	me.ally = true
	me.frames = b.soldier_frames
	me.record = rec
	me.campaign = true
	return me


var campaign := false # a man of your company: his own cartridges count


func _ready() -> void:
	super._ready()
	if side == 1:
		remove_from_group("friendlies")
		add_to_group("enemies")
	think_every = 3
	hp *= 1.5 # (field battles last: a man takes two balls, not one)
	reload_time /= field.pace
	melee_rate *= field.pace
	if not pike and not campaign:
		ammo = -1 # a test battle: nobody runs dry
		loaded = true
	if pike and not campaign:
		reach = 3.4 # the long pike, not the boarding pike
		engage = reach + 1.8
	match missile:
		"ball":
			fire_range = 60.0
		"arrow":
			fire_range = 78.0
		"bolt":
			fire_range = 66.0


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var dt := _think(delta)
	if dt >= 0.0:
		if reg == null:
			_brain(dt)
		else:
			_field_brain(dt)


func _field_brain(delta: float) -> void:
	_clock += delta
	if asleep:
		_sleep(delta) # (the night camp: until the noise reaches him)
		return
	if _groggy > 0.0:
		_groggy -= delta
		velocity = Vector3.ZERO
		set_base_anim("idle")
		return
	if not loaded and ammo != 0 and missile != "":
		reload_left -= delta * (0.75 if reg.state == "wavering" else 1.0)
		_ram_sound_t -= delta
		if _ram_sound_t <= 0.0 and reload_left > 0.8 and missile != "arrow" and sprite_on == false:
			_ram_sound_t = 0.9 / pace
			battle.play_sound("ramrod" if missile == "ball" else "crank", global_position + Vector3.UP * 1.4, -16.0)
		if reload_left <= 0.0:
			loaded = true
	_reprime_left -= delta
	melee_timer -= delta
	blocking = false

	if stagger_time > 0.0:
		stagger_time -= delta
		velocity = _knock
		_knock = _knock.move_toward(Vector3.ZERO, 10.0 * delta)
		set_base_anim("block")
		_move(delta)
		return

	var routing: bool = reg.state in ["routing", "shattered"]
	var slot: Vector3 = reg.slot(slot_index)
	_seen_slot = slot
	_seen_forward = reg.forward

	# Blades: whoever is within reach gets his whole attention (a running
	# man only defends himself if he's caught).
	var threat: Node3D = null
	if reg.foes_close:
		threat = field.nearest_foe(self, engage if not routing else 1.6)
	if pike:
		hit_height = 1.8 if (threat != null or reg.moving) else 1.15
	if threat != null:
		shot_timer = -1.0
		in_melee_t = field.clock
		reg.engaged_t = field.clock
		_fight(delta, threat)
		return

	if routing:
		_run_for_it(delta)
		return

	# The charge: into the regiment he's sent at, each man for the nearest.
	if reg.charging:
		var foe: Node3D = reg.charge_foe(self)
		if foe != null:
			_charge_at(delta, foe)
			return

	# His place in the block.
	var to_slot := slot - global_position
	to_slot.y = 0.0
	var gap := to_slot.length()
	var v := Vector3.ZERO
	if gap > 0.3:
		var spd: float = reg.march_speed() * (1.35 if gap > 3.0 else 1.0)
		v = to_slot / gap * minf(spd, gap * 2.5)
	var push: Vector3 = battle.separation(self, _own(), 0.9)
	velocity = v + push * 1.6
	_move(delta)

	# Shooting at the regiment his officers point at.
	if missile != "":
		if shot_timer >= 0.0:
			shot_timer -= delta
			if shot_timer < 0.0:
				_shoot()
		elif loaded and _reprime_left <= 0.0 and gap < 1.6 and not reg.moving and reg.may_fire():
			var t: Node3D = reg.shot_at(self)
			if t != null and global_position.distance_to(t.global_position) <= fire_range:
				target = t
				shot_timer = randf_range(0.2, 1.4) + steadiness * 1.2 + (1.2 if reg.state == "wavering" else 0.0)
		if reg.volley_now and loaded and shot_timer < 0.0:
			var t2: Node3D = reg.shot_at(self)
			if t2 != null:
				target = t2
				shot_timer = 0.15 + reaction * 0.4 + randf_range(0.0, 0.3)

	if shot_timer >= 0.0 and is_valid_target(target):
		face_toward(target.global_position - global_position)
		set_base_anim("aim")
	elif gap > 0.3:
		face_toward(v)
		set_base_anim("walk")
	else:
		face_toward(reg.forward)
		if pike:
			set_base_anim("guard" if reg.braced else "idle")
		else:
			set_base_anim("idle" if loaded else "reload")


func _own() -> Array:
	return battle.enemies if side == 1 else battle.soldiers


## Up close: as the line soldier, but he keeps to his regiment's ground
## unless it's charging.
func _fight(delta: float, e: Node3D) -> void:
	var to_e := e.global_position - global_position
	to_e.y = 0.0
	var d := to_e.length()
	var dir := to_e / maxf(d, 0.01)
	face_toward(dir)
	var w = e.get("windup")
	var st = e.get("stagger_time")
	var he_rears: bool = e.get("target") == self and w != null and float(w) >= 0.0
	var he_reels: bool = st != null and float(st) > 0.0
	var v := Vector3.ZERO
	if he_rears:
		blocking = true
		set_base_anim("block")
		v = -dir * BACKPEDAL * pace
	else:
		set_base_anim("guard")
		if melee_timer <= 0.0 and d <= reach + (0.4 if he_reels else 0.0):
			_thrust(e)
			if pike and e.has_method("pike_hit"):
				e.pike_hit(self, reg.braced)
		elif he_reels or reg.charging:
			if d > reach * 0.8:
				v = dir * 2.4 * pace
		elif d < (reach * 0.7 if pike else 1.3):
			v = -dir * 1.0 * pace
	if not reg.charging:
		var from_slot := global_position + v * delta - _seen_slot
		from_slot.y = 0.0
		if from_slot.length() > LEASH + 1.0 and v.dot(from_slot) > 0.0:
			v = Vector3.ZERO
	velocity = v + battle.separation(self, _own(), 0.9) * 1.4
	_move(delta)


func _charge_at(delta: float, foe: Node3D) -> void:
	var to_f := foe.global_position - global_position
	to_f.y = 0.0
	var d := to_f.length()
	# A loaded man may fire into them just before they meet.
	if missile == "ball" and loaded and d > 6.0 and d < 18.0 and shot_timer < 0.0 and randf() < delta * 0.6:
		target = foe
		shot_timer = randf_range(0.2, 0.5)
	if shot_timer >= 0.0:
		shot_timer -= delta
		face_toward(to_f)
		set_base_anim("aim")
		velocity = Vector3.ZERO
		if shot_timer < 0.0:
			_shoot()
		return
	var way := to_f
	if battle.nest != null:
		# Round by the gate or a gap in the stakes.
		way = battle.nest.route(global_position, foe.global_position) - global_position
		way.y = 0.0
		if way.length() < 0.4:
			way = Vector3.ZERO
	velocity = way.normalized() * reg.run_speed() + battle.separation(self, _own(), 1.0) * 1.8
	face_toward(to_f)
	set_base_anim("guard" if d < 6.0 else "walk")
	_move(delta)


## Running away: for his side's edge of the field, and gone when he's off it.
func _run_for_it(delta: float) -> void:
	var to: Vector3 = reg.flee_point(self) - global_position
	to.y = 0.0
	if to.length() < 4.0 or field.off_field(global_position):
		field.unit_fled(self)
		return
	velocity = to.normalized() * reg.run_speed() * 1.1 + battle.separation(self, _own(), 0.9)
	face_toward(to)
	set_base_anim("walk")
	_move(delta)


## The step that moves him: over the ground, round houses and deep water.
func _move(_delta: float) -> void:
	_moving = true
	_move_f = field.terrain.speed_factor(global_position, Vector3(velocity.x, 0, velocity.z).normalized() if velocity.length_squared() > 0.01 else Vector3.ZERO)


func _shoot() -> void:
	if not is_valid_target(target):
		shot_timer = -1.0
		return
	if missile == "ball" and rig != null:
		# Over a hill or a roof? Hold fire.
		var from := global_position + Vector3.UP * 1.5
		if not field.terrain.clear_line(from, target.global_position + Vector3.UP * 1.2):
			shot_timer = -1.0
			return
	reg.fired()
	super._shoot()


# ---------------------------------------------------------------- blows from you

## Your blade (or a lizard's) arriving: he may catch it on his musket.
func receive_blow(damage: float, from: Node3D, heavy: bool) -> String:
	if not alive:
		return "hit"
	var to_from := from.global_position - global_position
	to_from.y = 0.0
	if not heavy and facing.dot(to_from.normalized()) > 0.3 and randf() < 0.18 + 0.25 * steadiness:
		battle.play_sound("clang", global_position + Vector3.UP * 1.3, -3.0)
		return "blocked"
	take_damage(damage, from)
	return "hit"


func stagger(push: Vector3, seconds: float) -> void:
	if not alive:
		return
	stagger_time = maxf(stagger_time, seconds * 0.7)
	_knock = push * 0.7
	shot_timer = -1.0


func take_damage(amount: float, from: Node3D = null) -> void:
	var was := alive
	super.take_damage(amount, from)
	if was and alive and reg != null:
		reg.hurt(amount)


func _on_died() -> void:
	down_status = "wounded" if randf() < 0.5 else "killed"
	remove_from_group("friendlies")
	remove_from_group("enemies")
	battle.play_sound("grunt", global_position + Vector3.UP * 1.5, -6.0)
	field.unit_died(self)
