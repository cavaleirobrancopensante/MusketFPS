extends "res://scripts/lizardman.gd"
## A lizard of a warband regiment in a field battle (Tests > Field battle).
##
##   warrior    shield and cleaver; comes on in a loose mob and hacks
##   skirmisher no shield; stops at throwing range and hurls javelins, and
##              only fights hand to hand when caught
##   brute      half again as big, slow, hard to kill; his blows knock men
##              flat and send them reeling
##
## Out of reach of a fight he keeps his place in the mob (regiment.gd); in
## reach, or when his regiment charges, he fights like any lizardman.

var reg = null
var field
var side := 1
var variant := "warrior"
var dmg_mult := 1.0
var in_melee_t := -99.0
var _throw_t := 0.0


static func make(b, f, v: String):
	var me = load("res://scripts/field_lizard.gd").new()
	me.battle = b
	me.field = f
	me.variant = v
	me.frames = b.lizard_frames
	return me


func _ready() -> void:
	super._ready()
	looter = false
	think_every = 3
	match variant:
		"skirm":
			speed = randf_range(4.6, 5.4)
			hp = 100.0
			_throw_t = randf_range(0.5, 3.0)
		"brute":
			speed = randf_range(3.3, 3.8)
			hp = 440.0
			dmg_mult = 2.2
			hit_radius = 0.65
			hit_height = 2.9
			rig.scale = Vector3.ONE * 1.12 * 1.45
			_sprite_h = float(get_meta("sprite_cell", 1.95 * 1.45))
		_:
			hp = 160.0
	speed *= field.pace


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var dt := _think(delta)
	if dt < 0.0:
		return
	if reg == null:
		_brain(dt)
	else:
		_field_brain(dt)


func _field_brain(delta: float) -> void:
	if reg.state in ["routing", "shattered"]:
		var close: Node3D = field.nearest_foe(self, 1.8)
		if close == null or stagger_time > 0.0:
			_cancel_windup()
			shield_up = 0.0
			_flee(delta)
			return
	# In a fight, or charging: the old lizard brain (it picks the nearest man).
	var foe: Node3D = null
	if reg.foes_close:
		foe = field.nearest_foe(self, 7.0 if variant != "skirm" else 4.0)
	if foe != null or reg.charging or stagger_time > 0.0 or windup >= 0.0 or shield_up > 0.0:
		if reg.charging and foe == null:
			var cf: Node3D = reg.charge_foe(self)
			if cf != null:
				target = cf
				retarget_timer = 0.6
		if foe != null:
			in_melee_t = field.clock
			reg.engaged_t = field.clock
		_brain(delta)
		return
	# Skirmishers: stand off and throw.
	if variant == "skirm" and reg.may_fire():
		var t: Node3D = reg.shot_at(self)
		if t != null:
			var to_t := t.global_position - global_position
			to_t.y = 0.0
			if to_t.length() < 30.0 and not reg.moving:
				_throw_t -= delta
				face_toward(to_t)
				velocity = battle.separation(self, battle.enemies, 1.4) * 1.5
				set_base_anim("idle")
				_move(delta)
				if _throw_t <= 0.0:
					_throw_t = randf_range(3.2, 4.6)
					_throw(t)
				return
	# Keep his place in the mob.
	var slot: Vector3 = reg.slot(slot_index)
	var to_slot := slot - global_position
	to_slot.y = 0.0
	var gap := to_slot.length()
	var v := Vector3.ZERO
	if gap > 0.5:
		var spd: float = reg.march_speed() * (1.35 if gap > 3.0 else 1.0)
		v = to_slot / gap * minf(spd, gap * 2.5)
		face_toward(v)
		set_base_anim("walk")
	else:
		face_toward(reg.forward)
		set_base_anim("idle")
	velocity = v + battle.separation(self, battle.enemies, 1.2) * 1.8
	_move(delta)


var slot_index := 0


func _throw(t: Node3D) -> void:
	reg.fired()
	var from := global_position + Vector3.UP * 1.9
	var aim := t.global_position + Vector3.UP * 1.1
	var tv = t.get("velocity")
	if tv != null:
		aim += (tv as Vector3) * (from.distance_to(aim) / 20.0)
	var NestScript = load("res://scripts/nest_assault.gd")
	var v: Vector3 = NestScript.throw_velocity(from, aim, 22.0)
	battle.projectiles.fire("javelin", from, battle.projectiles.spread_dir(v, 0.045) * v.length(), self)
	play_oneshot("strike", 0.3)
	battle.play_sound("swish", from, -8.0)


func _flee(delta: float) -> void:
	var to: Vector3 = reg.flee_point(self) - global_position
	to.y = 0.0
	if to.length() < 4.0 or field.off_field(global_position):
		field.unit_fled(self)
		return
	velocity = to.normalized() * speed * 1.05 + battle.separation(self, battle.enemies, 1.0)
	face_toward(to)
	set_base_anim("walk")
	_move(delta)


func _move(_delta: float) -> void:
	_moving = true
	var d := Vector3(velocity.x, 0, velocity.z)
	_move_f = field.terrain.speed_factor(global_position, d.normalized() if d.length_squared() > 0.01 else Vector3.ZERO)


## A hack: heavier from a brute, and a brute's blow sends a man reeling.
func _strike(dist: float) -> void:
	windup = -1.0
	attack_timer = ATTACK_COOLDOWN * (1.4 if variant == "brute" else 1.0) * cooldown_mult / field.pace
	set_tint(Color.WHITE)
	play_oneshot("strike", 0.3)
	_punch(Vector3(1.12, 0.92, 1.0), 0.3)
	if is_valid_target(target) and dist <= ATTACK_RANGE * (1.3 if variant == "brute" else 1.0) + 0.4 and randf() < 0.75:
		target.take_damage(ATTACK_DAMAGE * dmg_mult, self)
		if variant == "brute" and target.has_method("stagger") and target != battle.player:
			var push := (target.global_position - global_position) * Vector3(1, 0, 1)
			target.stagger(push.normalized() * 4.0, 0.6)
	else:
		battle.play_sound("swish", global_position + Vector3.UP * 1.4, -6.0)


func take_damage(amount: float, from: Node3D = null) -> void:
	var was := alive
	super.take_damage(amount, from)
	if was and alive and reg != null:
		reg.hurt(amount)


func _on_died() -> void:
	_cancel_windup()
	remove_from_group("enemies")
	if last_hit_by != null and is_instance_valid(last_hit_by) and "kills" in last_hit_by:
		last_hit_by.kills += 1
	battle.play_sound("death", global_position + Vector3.UP * 1.4, -6.0)
	field.unit_died(self)
