extends CharacterBody3D
## You: an officer with a musket. First-person movement, looking, the musket
## (one slow, inaccurate, devastating shot, then a long reload) and the bayonet.
##
## Melee works like Mount & Blade: press to wind up, choose where the blow
## comes from, release to strike. Holding longer charges a heavier blow.
##   OVERHEAD   - comes down from above: big damage, one target
##   LEFT/RIGHT - sweeps across from that side: wide arc, can hit two
##   THRUST     - straight bayonet lunge: longest reach, one target
## Blocking (hold) stops a lizardman's hack from the front and staggers him.

signal fired(hit: bool)
signal melee_hit(count: int)
signal blocked
signal struck_shield # your blow landed on a lizardman's shield
signal shot_hit # one of your musket balls struck a lizardman
signal friendly_fire(by_you: bool) # a ball between you and your men
signal hurt
signal died

enum Swing { NONE = -1, OVERHEAD, LEFT, RIGHT, THRUST }

const Rig3D := preload("res://scripts/rig3d.gd")
const PlayerBody := preload("res://scripts/player_body.gd")

const SPEED := 5.0
const GRAVITY := 20.0
const RELOAD_TIME := 5.5 # bite, prime, close the pan, pour, ram three times, return the rod, cock
const PISTOL_RELOAD := 5.0
const PISTOL_SPEED := 260.0
const PISTOL_SPREAD := 0.034
const PISTOL_AIM_SPREAD := 0.012
## A war bow and a crossbow (the weapon range, or if your kit has them):
## [reload seconds, launch speed, hip spread, aimed spread, projectile, damage].
## The bow nocks fast and you draw it by aiming; the crossbow is spanned
## with a windlass, slow, and shoots flat and hard.
const MISSILE := {
	"bow": [1.8, 55.0, 0.035, 0.008, "arrow", 1.3],
	"crossbow": [7.0, 72.0, 0.025, 0.004, "bolt", 1.2],
}
const DRAW_TIME := 0.55 # a pistol from the belt or a sabre from the scabbard
## How each blade swings, relative to the bayonet the swings were tuned for:
## [damage x, reach x, strike speed x, recovery speed x].
const BLADES := {"melee": [1.0, 1.0, 1.0, 1.0], "saber": [1.0, 0.85, 1.0, 1.6], "pike": [1.1, 1.45, 0.8, 0.85], "lance": [1.15, 1.4, 0.85, 0.85]}
const RANGE := 90.0
const BALL_SPEED := 340.0
const GRENADES_PER_BATTLE := 3
const THROW_TIME := 0.8 # wind back, throw, recover
const THROW_RELEASE := 0.42 # when in the throw the grenade leaves your hand
const THROW_SPEED := 13.0
const SPREAD := 0.018 # radians of random error per shot from the hip
const AIM_SPREAD := 0.005 # ...and sighting down the barrel
const LOOK_SENS := 0.005 # radians per pixel of drag
const FOV := 72.0
const AIM_FOV := 48.0 # aiming down the sights zooms in
const AIM_TIME := 0.22 # seconds to bring the musket up to your cheek

const FIX_TIME := 1.1 # draw the bayonet from its scabbard and lock it on
const UNFIX_TIME := 0.9
## Reload progress (0..1) at which the ramrod hits bottom: one clink each.
const RAM_STROKES := [0.5, 0.58, 0.66] # (fractions of the reload; see player_body.gd)
const MIN_WINDUP := 0.18 # fastest possible blow
const FULL_CHARGE := 0.8 # hold this long for a fully charged blow
const STRIKE_TIME := 0.16
const RECOVER_TIME := 0.28
const BLOCK_ARC := 70.0 # degrees either side of where you look

## Per-direction tuning. "cone" is degrees either side of where you look.
const SWINGS := {
	Swing.OVERHEAD: {"reach": 2.3, "cone": 30.0, "targets": 1, "damage": 70.0, "charge_damage": 45.0, "knock": 3.5},
	Swing.LEFT: {"reach": 2.2, "cone": 75.0, "targets": 2, "damage": 45.0, "charge_damage": 30.0, "knock": 3.0},
	Swing.RIGHT: {"reach": 2.2, "cone": 75.0, "targets": 2, "damage": 45.0, "charge_damage": 30.0, "knock": 3.0},
	Swing.THRUST: {"reach": 2.8, "cone": 18.0, "targets": 1, "damage": 60.0, "charge_damage": 45.0, "knock": 4.0},
}

var battle
var hp := 100.0
var max_hp := 100.0
var alive := true
var loaded := true
var reload_left := 0.0
var move_input := Vector2.ZERO # set by the HUD joystick, -1..1
var camera: Camera3D
var pitch := 0.0 # looking up (+) or down (-), radians

# 3D mode: your own body, and first/third-person view.
var rig = null
var third_person := false

# Melee state, read by the HUD to animate the viewmodel.
var weapon := "musket" # "musket", "melee" (bayonet fixed), "pistol" or "saber"
# The sidearms you carry (from your kit).
var has_pistol := true
var has_saber := true
var has_bow := false
var has_crossbow := false
var has_pike := false # a pike officer's: "melee" is the pike
var has_lance := false # a cavalry officer's: "melee" is the lance
## The lance couched under your arm at the gallop (COUCH): it hits whatever
## the point meets, with the horse's speed behind it.
var couched := false
var _couch_cd := 0.0
const COUCH_SPEED := 5.0 # m/s: slower than this and the lance comes up
const LANCE_TIP := 3.6 # metres ahead of you, couched
## Bow and crossbow: nocked/spanned, and how long until they are again.
var m_loaded := {"bow": true, "crossbow": true}
var m_left := {"bow": 0.0, "crossbow": 0.0}
var _crank_t := 0.0
var pistol_loaded := true
var pistol_reload_left := 0.0
var _last_pistol_p := 1.0
var switch_from := "musket"
var switch_left := 0.0
var switch_total := 1.0
var switch_target := "musket"
var swing_phase := "idle" # idle, windup, strike, recover
var swing_dir: int = Swing.NONE
var phase_time := 0.0
var strike_charge := 0.0
var blocking := false
var block_held := false

var kills := 0
# From your character sheet (officer.gd) in a campaign; plain values otherwise.
var reload_time := RELOAD_TIME
var spread_mult := 1.0
var speed_mult := 1.0
var melee_mult := 1.0
var saber_mult := 1.3
var block_arc := BLOCK_ARC
var armour := 0.0
var misfire_chance := 0.0
var ammo := -1 # cartridges in your box; -1 = no count (stand-alone battles)
var ammo_used := 0
var _reprime := 0.0
var asleep_left := 0.0 # night camp: still asleep for this long (see battle._setup_camp)
var wake_left := 0.0 # ...then getting up off the bedroll
const WAKE_TIME := 1.5
var _shot := false
var grenades := GRENADES_PER_BATTLE
var throw_left := 0.0
var _thrown := false
var _shake := 0.0
var aim_wanted := false
## The officer's spyglass (field battles): the view closes in to a circle,
## far away and steady; you look about slowly.
var spyglass := false
const SPYGLASS_FOV := 11.0
## Pointing out an order to your men: your free hand (or blade) at where
## you sent them, for a moment; you turn to face it.
var point_t := 0.0
var point_dir := Vector3.FORWARD # world direction you point
var _point_yaw := 0.0
var aim_amount := 0.0 # 0 = hip, 1 = fully sighted

## Your horse (player_horse.gd), if you have one in this battle, and
## whether you're on it. MOUNT/DISMOUNT takes a moment (mount_t counts down).
var horse = null
var mounted := false
var mount_t := 0.0
const MOUNT_TIME := 0.9
const MOUNT_REACH := 3.2
## The gun you're laying (a field gun's GunPost: your galloper, or any of
## your batteries' guns), or null; and what's in it.
var gun = null
var fishing = null # a rod in your hands (fishing.gd, fishing at the river)
var gun_shot := "roundshot"
const GUN_REACH := 5.0

var _want_fire := false
var _last_reload_p := 1.0
var _bayonet_sound_done := false
var _release_requested := false
var _hit_done := false


func _ready() -> void:
	add_to_group("friendlies")
	collision_layer = 8
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	camera.fov = FOV
	camera.near = 0.03 # so your own musket doesn't clip in first person
	camera.far = 400.0
	add_child(camera)
	camera.make_current()

	# Your own body: arms and musket in first person, the whole officer in third.
	third_person = Settings.third_person
	rig = Rig3D.new()
	rig.kind = "officer"
	if Company.active:
		_apply_sheet()
		rig.gear = _gear()
	if Settings.playground:
		# The weapon range: everything, and shot to spare.
		has_bow = true
		has_crossbow = true
		grenades = 99
		rig.gear = {"bow": "war_bow", "crossbow": "crossbow"}
	rig.manual = true
	add_child(rig)
	var ctrl := PlayerBody.new()
	ctrl.player = self
	ctrl.rig = rig
	add_child(ctrl)
	_ctrl = ctrl
	_update_camera()


## The retreat's bayonet charge (field_rearguard.gd): every officer, of
## whatever kind, goes in on foot with a musket and bayonet.
var bayonet_drill := false
var _ctrl = null

# ---------------------------------------------------------------- picking things up
# (pickups.gd: whatever the fallen carried; gun tools and rounds)

## Weapons you've picked up on this field: gear keys added to your kit.
var extra_gear := {}
## Gun tools you carry (rammer, linstock) and the round in your arms.
var tools := {}
var carry := "" # "roundshot" or "canister": a gun's round, carried to the muzzle
## Javelins picked up from fallen lizards: thrown with the JAVELIN button.
var javelins := 0
## A job at a gun that takes a moment (sponge, load, ram): [what, left, total, gun].
var work: Array = []
const WORK_TIMES := {"sponge": 2.4, "load": 1.0, "ram": 1.6, "take": 0.6}


## What the context button would do here: {"id", "label", "ok"} or {}.
## A gun whose crew is down comes first, then anything lying at your feet.
func context_action() -> Dictionary:
	if not alive or mounted or gun != null or fishing != null:
		return {}
	if not work.is_empty():
		var w: Array = work
		return {"id": "work", "label": "%s %d%%" % [_work_label(String(w[0])), int(100.0 * (1.0 - float(w[1]) / float(w[2])))], "ok": false}
	var ga := _gun_action()
	if bool(ga.get("ok", false)):
		return ga
	var pk = battle.get("pickups")
	if pk != null:
		var d: Dictionary = pk.nearest(global_position, 2.2)
		if not d.is_empty():
			var nm: String = pk.item_name(String(d["item"]))
			if int(d["n"]) > 1:
				nm += " (%d)" % int(d["n"])
			return {"id": "pick", "label": Lang.t("PICK UP: %s") % nm, "ok": true}
	return ga


## At a gun whose crew is down: what needs doing next, where you stand.
func _gun_action() -> Dictionary:
	var g = _silent_gun_near(6.0)
	if g != null:
		var c = g.crew
		var me := global_position
		if Vector2(me.x - c.box_point().x, me.z - c.box_point().z).length() < 2.0 and carry == "" and c.box_total() > 0:
			var k := gun_shot if int(c.box.get(gun_shot, 0)) > 0 else ("canister" if gun_shot == "roundshot" else "roundshot")
			return {"id": "take", "label": Lang.t("TAKE A ROUND: %s (%d)") % [Lang.t("BALL") if k == "roundshot" else Lang.t("CANISTER"), int(c.box[k])], "ok": true}
		var mo: Vector3 = c.mouth_point()
		if Vector2(me.x - mo.x, me.z - mo.z).length() < 2.4:
			if not c.solo_clean:
				return {"id": "sponge", "label": Lang.t("SPONGE OUT THE BORE") if tools.has("rammer") else Lang.t("FIND THE RAMMER"), "ok": tools.has("rammer")}
			if c.solo_charge == "":
				if carry != "":
					return {"id": "load", "label": Lang.t("LOAD THE ROUND"), "ok": true}
				return {"id": "none", "label": Lang.t("FETCH A ROUND FROM THE BOX"), "ok": false}
			if not c.solo_rammed:
				return {"id": "ram", "label": Lang.t("RAM IT HOME") if tools.has("rammer") else Lang.t("FIND THE RAMMER"), "ok": tools.has("rammer")}
	return {}


func _work_label(w: String) -> String:
	return {"sponge": Lang.t("SPONGING"), "load": Lang.t("LOADING"), "ram": Lang.t("RAMMING"), "take": Lang.t("TAKING A ROUND")}.get(w, w.to_upper())


## The context button pressed.
func do_context() -> void:
	var a := context_action()
	if a.is_empty():
		return
	var id := String(a["id"])
	if id == "pick":
		_pick_up()
		return
	if not bool(a.get("ok", false)):
		if id == "sponge" or id == "ram":
			battle.hud.show_message(Lang.t("The rammer: the crew's long pole with the sponge on one end. Look for it on the ground by the gun."), 2.5)
		elif id == "none":
			battle.hud.show_message(Lang.t("The ammunition box is behind the gun, on its left."), 2.0)
		return
	var g = _silent_gun_near(6.0)
	if g == null:
		return
	work = [id, float(WORK_TIMES[id]), float(WORK_TIMES[id]), g, global_position]
	battle.play_sound_ui("crank" if id != "take" else "thud", -12.0)


## A job at the gun runs while you stand there; walk off and it stops.
func _work_tick(delta: float) -> void:
	if work.is_empty():
		return
	var at: Vector3 = work[4]
	if global_position.distance_to(at) > 0.8 or not alive:
		work = []
		return
	work[1] = float(work[1]) - delta
	if float(work[1]) > 0.0:
		return
	var g = work[3]
	var id := String(work[0])
	work = []
	if not is_instance_valid(g):
		return
	var c = g.crew
	match id:
		"take":
			carry = c.take_round(gun_shot)
		"sponge":
			c.solo_clean = true
			battle.play_sound_ui("ramrod", -8.0)
		"load":
			c.solo_charge = carry
			carry = ""
		"ram":
			c.solo_rammed = true
			battle.play_sound_ui("ramrod", -6.0)
			battle.hud.show_hint(Lang.t("Loaded! Go behind the gun: MAN THE GUN, lay it, FIRE with the linstock."), 4.0)


## A gun nearby whose crew is down (yours or theirs): you can work it alone.
func _silent_gun_near(r: float):
	if battle.field == null:
		return null
	var best = null
	var bd := r
	for g in battle.guns_down:
		if not is_instance_valid(g) or not g.crew.silent:
			continue
		var d := global_position.distance_to(g.crew.global_position)
		if d < bd:
			bd = d
			best = g
	return best


## Pick up whatever lies closest: use what you can, and weapons go on the
## wagon after the fight.
func _pick_up() -> void:
	var pk = battle.get("pickups")
	if pk == null:
		return
	var d: Dictionary = pk.nearest(global_position, 2.2)
	if d.is_empty():
		return
	var item := String(d["item"])
	var n := int(d["n"])
	var what: String = pk.item_name(item)
	var said := ""
	match item:
		"cartridges":
			if ammo < 0:
				said = Lang.t("You've cartridges enough.")
			else:
				var room := maxi(0, 60 - ammo)
				var got := mini(n, room)
				if got <= 0:
					battle.hud.show_message(Lang.t("Your cartridge box is full."), 1.5)
					return
				ammo += got
				if not loaded and weapon == "musket" and reload_left <= 0.0:
					reload_left = reload_time
				said = Lang.t("+%d cartridges (%d in your box).") % [got, ammo]
		"arrows", "bolts":
			if Company.active:
				Company.stores[item] = int(Company.stores.get(item, 0)) + n
			said = Lang.t("%d %s into the quiver.") % [n, what.to_lower()]
		"javelins":
			javelins += n
			said = Lang.t("%d javelins: throw them with JAVELIN.") % n
		"rammer", "linstock":
			if tools.has(item):
				battle.hud.show_message(Lang.t("You already have one."), 1.2)
				return
			tools[item] = true
			said = Lang.t("You take up the %s.") % what.to_lower()
		"roundshot", "canister":
			if carry != "":
				battle.hud.show_message(Lang.t("Your arms are full."), 1.2)
				return
			carry = item
			said = Lang.t("You lift the %s.") % what.to_lower()
		_:
			said = _take_weapon(item, what)
	pk.remove(d)
	battle.play_sound_ui("thud", -14.0)
	if said != "":
		battle.hud.show_message(said, 2.2)


## A weapon off the ground: one you can use joins your kit for this fight
## (a bow, a crossbow, a sword, a pistol); every one goes on the wagon.
func _take_weapon(item: String, what: String) -> String:
	if Company.active:
		Company.add_item(item, 1)
	var slot := String(Company.ITEMS.get(item, {}).get("slot", ""))
	var spec: Dictionary = Company.ITEMS.get(item, {})
	var missile := String(spec.get("missile", ""))
	if missile == "arrow" and not has_bow:
		has_bow = true
		extra_gear["bow"] = item
		_rebuild_rig()
		return Lang.t("You take up the %s. (BOW along the bottom.)") % what.to_lower()
	if missile == "bolt" and not has_crossbow:
		has_crossbow = true
		extra_gear["crossbow"] = item
		_rebuild_rig()
		return Lang.t("You take up the %s. (CROSSBOW along the bottom.)") % what.to_lower()
	if slot == "sword" and not has_saber:
		has_saber = true
		extra_gear["sword"] = item
		_rebuild_rig()
		return Lang.t("You take up the %s. (SABRE along the bottom.)") % what.to_lower()
	if item == "pistol" and not has_pistol:
		has_pistol = true
		pistol_loaded = ammo != 0
		extra_gear["pistol"] = item
		_rebuild_rig()
		return Lang.t("You stick the pistol in your belt.")
	return Lang.t("%s: onto the wagon after the fight.") % what


## Your body again with what you've picked up (a new weapon to draw).
func _rebuild_rig() -> void:
	if rig == null or _ctrl == null:
		return
	var g: Dictionary = (_gear() if Company.active else {}).duplicate()
	g.merge(extra_gear, true)
	var old = rig
	rig = Rig3D.new()
	rig.kind = "officer"
	rig.gear = g
	rig.manual = true
	add_child(rig)
	_ctrl.rig = rig
	old.queue_free()


## Throw a javelin you picked up, along your look.
func throw_javelin() -> void:
	if not alive or javelins <= 0 or gun != null or throw_left > 0.0:
		return
	javelins -= 1
	var fwd := -camera.global_transform.basis.z
	var from := camera.global_position + fwd * 0.6
	var v := fwd * 30.0 + Vector3.UP * 2.5
	var p: Dictionary = battle.projectiles.fire("javelin", from, v, self)
	p["dmg_mult"] = 1.2
	battle.play_sound_ui("swish", -6.0)
	fired.emit(false)


func _gear() -> Dictionary:
	var g: Dictionary = Company.officer.get("gear", {}).duplicate()
	if bayonet_drill:
		g["primary"] = "musket"
		g["secondary"] = "bayonet"
	return g


## Your attributes, skills and kit (see officer.gd and the YOU screen).
func _apply_sheet() -> void:
	var O = Company.Officer
	max_hp = O.max_hp()
	hp = max_hp
	reload_time = RELOAD_TIME * O.reload_mult()
	spread_mult = O.spread_mult()
	speed_mult = O.speed_mult()
	melee_mult = O.melee_mult()
	saber_mult = O.saber_mult()
	block_arc = O.block_arc()
	armour = O.armour()
	misfire_chance = O.misfire() * 0.5 # you look after your own lock
	ammo = int(Company.officer.get("pack", {}).get("ammo", 30))
	loaded = ammo > 0
	var g: Dictionary = _gear()
	has_pistol = String(g.get("pistol", "")) != ""
	has_saber = String(g.get("sword", "")) != ""
	has_pike = String(g.get("primary", "")) in ["pike", "spear", "war_spear"]
	has_lance = String(g.get("primary", "")) == "lance"
	if has_pike or has_lance:
		weapon = "melee"
		switch_from = "melee"
		switch_target = "melee"
		loaded = false
	pistol_loaded = has_pistol and ammo > 1


## 3D mode: switch between first and third person.
func toggle_view() -> void:
	if rig != null:
		third_person = not third_person


func _process(delta: float) -> void:
	if alive:
		# Raise or lower the musket smoothly; the view zooms with it.
		var target := 1.0 if is_aiming() else 0.0
		aim_amount = move_toward(aim_amount, target, delta / AIM_TIME)
		var k := aim_amount * aim_amount * (3.0 - 2.0 * aim_amount)
		camera.fov = lerpf(FOV, AIM_FOV, k)
		if spyglass:
			camera.fov = SPYGLASS_FOV
		if point_t > 0.0:
			point_t -= delta
			if point_t > 1.0:
				rotation.y = lerp_angle(rotation.y, _point_yaw, 1.0 - exp(-10.0 * delta))
		_shake = move_toward(_shake, 0.0, delta * 1.5)
		_update_camera()


## Toggle aiming down the sights (musket only). The wish is remembered, so
## the musket comes back up by itself after each reload.
func toggle_aim() -> void:
	if is_gun() and switch_left <= 0.0:
		aim_wanted = not aim_wanted


## Actually sighting right now: wanted, loaded, a gun in hand.
func is_aiming() -> bool:
	return alive and aim_wanted and is_gun() and switch_left <= 0.0 and is_loaded() \
		and throw_left <= 0.0


## A firearm in hand (musket or pistol), or a blade (bayonet or sabre).
func is_gun() -> bool:
	return weapon in ["musket", "pistol", "bow", "crossbow"]


func is_melee() -> bool:
	return weapon == "melee" or weapon == "saber"


## The weapon in hand is loaded (for the HUD's FIRE button).
func is_loaded() -> bool:
	if MISSILE.has(weapon):
		return bool(m_loaded[weapon])
	return pistol_loaded if weapon == "pistol" else loaded


## 0..1 through reloading the weapon in hand (1 when ready).
func reload_progress_of(w: String) -> float:
	if MISSILE.has(w):
		if bool(m_loaded[w]):
			return 1.0
		return 1.0 - float(m_left[w]) / float(MISSILE[w][0])
	if w == "pistol":
		return pistol_reload_progress()
	return reload_progress()


## The weapons you can take up, in the order of the buttons along the bottom.
func weapons() -> Array:
	var out := ["musket", "melee"]
	if has_pike or has_lance:
		out = ["melee"] # (a pike or a lance, and no musket)
	elif mounted:
		out = ["musket"] # (no bayonet work from the saddle)
	if has_pistol:
		out.append("pistol")
	if has_saber:
		out.append("saber")
	if has_bow:
		out.append("bow")
	if has_crossbow:
		out.append("crossbow")
	return out


## Throw a grenade: musket in your left hand, wind back, lob it in an arc.
func throw_grenade() -> void:
	if not alive or grenades <= 0 or throw_left > 0.0 or switch_left > 0.0 or swing_phase != "idle" \
			or asleep_left > 0.0 or wake_left > 0.0:
		return
	grenades -= 1
	throw_left = THROW_TIME
	_thrown = false
	blocking = false


func is_throwing() -> bool:
	return throw_left > 0.0


## 0..1 through the throw.
func throw_progress() -> float:
	return 1.0 - throw_left / THROW_TIME


## A blast nearby rattles your view (0..1).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _update_throw(delta: float) -> void:
	if throw_left <= 0.0:
		return
	throw_left -= delta
	if not _thrown and throw_progress() >= THROW_RELEASE / THROW_TIME:
		_thrown = true
		# Out of the right hand, along where you look, lofted into an arc.
		var fwd := -camera.global_transform.basis.z
		var right := global_transform.basis.x
		var from := global_position + Vector3.UP * 1.75 + right * 0.25 + _flat_forward() * 0.3
		var vel := fwd * THROW_SPEED + Vector3.UP * 3.5 + Vector3(velocity.x, 0.0, velocity.z) * 0.5
		battle.projectiles.fire("grenade", from, vel, self)
		battle.play_sound_ui("swish", -4.0)
	if throw_left < 0.0:
		throw_left = 0.0


func _update_camera() -> void:
	var lift := saddle_lift()
	if gun != null and not spyglass:
		# At the gun: down behind the breech, sighting along the barrel (or
		# standing back from it in third person).
		var gs: float = 0.74 if gun.light else 1.0
		if third_person:
			camera.position = Vector3(0.9, 2.2, 2.6) + Basis(Vector3.RIGHT, pitch) * Vector3(0, 0.3, 1.2)
		else:
			camera.position = Vector3(0.0, 1.32 * gs + 0.4, -0.4 * gs)
		camera.rotation = Vector3(pitch, 0, 0)
		if _shake > 0.0:
			var sh := _shake * _shake
			camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.06 * sh
		return
	if third_person and rig != null and not spyglass:
		# Over the right shoulder; the orbit follows your pitch. Aiming pulls
		# the camera in tight over the shoulder (the HUD keeps a small sight).
		# On horseback it stands further back, to take in the horse.
		var k := aim_amount * aim_amount * (3.0 - 2.0 * aim_amount)
		var pivot := Vector3(lerpf(0.45, 0.72, k), lerpf(1.65, 1.74, k) + lift, 0.0)
		var back := lerpf(2.6, 1.6, k) + 1.6 * lift / HORSE_SADDLE
		var offset := Basis(Vector3.RIGHT, pitch) * Vector3(0.0, lerpf(0.2, 0.06, k), back)
		var pos := pivot + offset
		pos.y = maxf(pos.y, 0.35)
		camera.position = pos
	else:
		# Eye at the head; your own torso is hidden in first person, and the
		# arms rise from below the screen, so nothing of you blocks the view.
		camera.position = Vector3(0, 1.64 + lift, 0.02)
		# Looking down at yourself, the eye leans out over your chest so you
		# see your coat, belt and boots rather than the inside of your collar.
		var down := clampf((-pitch - 0.25) / 0.8, 0.0, 1.0)
		camera.position += Vector3(0, -0.04, -0.17) * down
	camera.rotation = Vector3(pitch, 0, 0)
	if asleep_left > 0.0 or wake_left > 0.0:
		# On your back by the fire, looking at the stars, then up on your feet.
		var up := 0.0 if asleep_left > 0.0 else 1.0 - wake_left / WAKE_TIME
		up = up * up * (3.0 - 2.0 * up)
		camera.position.y = lerpf(0.32, camera.position.y, up)
		camera.rotation.x = lerpf(1.25, pitch, up)
	if _shake > 0.0:
		var s := _shake * _shake
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.06 * s
		camera.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03 * s


# ---------------------------------------------------------------- the horse

const HORSE_SADDLE := 0.8

## How high the saddle lifts you right now (easing up and down as you mount
## and dismount), with the horse's stride in it.
func saddle_lift() -> float:
	if horse == null:
		return 0.0
	var k := 1.0 - mount_t / MOUNT_TIME if mounted else mount_t / MOUNT_TIME
	k = k * k * (3.0 - 2.0 * k)
	return (HORSE_SADDLE + (horse.bob() if mounted else 0.0)) * k


func can_mount() -> bool:
	return alive and horse != null and not horse.dead and not mounted and mount_t <= 0.0 and gun == null \
		and global_position.distance_to(horse.global_position) < MOUNT_REACH


func can_dismount() -> bool:
	return alive and mounted and mount_t <= 0.0 and horse != null and horse.speed < 2.5


## MOUNT / DISMOUNT / CALL HORSE. Dismounting at speed reins the horse in
## first, then you get down; too far from your horse, you whistle for it.
func toggle_mount() -> void:
	if mounted:
		if can_dismount():
			_get_down()
		else:
			want_down = not want_down # (press again to ride on)
	elif can_mount():
		mounted = true
		horse.player = self
		horse.call_to(null)
		global_position = Vector3(horse.global_position.x, global_position.y, horse.global_position.z)
		rotation.y = horse.yaw
		mount_t = MOUNT_TIME
		aim_wanted = false
		if weapon == "melee" and not has_pike and not has_lance:
			weapon = "saber" if has_saber else "musket"
			switch_target = weapon
		battle.play_sound_ui("swish", -10.0)
	elif horse != null and not horse.dead and alive and gun == null:
		horse.call_to(self)
		battle.hud.show_message(Lang.t("You whistle for your horse."), 1.5)


var want_down := false # reining in to get down


func can_couch() -> bool:
	return mounted and has_lance and weapon == "melee" and switch_left <= 0.0 and swing_phase == "idle" \
		and horse != null and horse.speed >= COUCH_SPEED and _couch_cd <= 0.0


## COUCH: lower the lance for the charge (or raise it again).
func toggle_couch() -> void:
	if couched:
		couched = false
	elif can_couch():
		couched = true
		blocking = false
		battle.play_sound_ui("swish", -12.0)


## Couched: the first foe the point meets takes the charge.
func _couch_tick(delta: float) -> void:
	_couch_cd = maxf(0.0, _couch_cd - delta)
	if not couched:
		return
	if not mounted or horse == null or horse.speed < COUCH_SPEED * 0.8 or weapon != "melee" or swing_phase != "idle":
		couched = false
		return
	var fwd := _flat_forward()
	var from := global_position
	for e in battle.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector3 = e.global_position - from
		to.y = 0.0
		var d := to.length()
		if d > LANCE_TIP or d < 0.5:
			continue
		if rad_to_deg(fwd.angle_to(to)) > 14.0:
			continue
		var dmg: float = (30.0 + 10.0 * horse.speed) * melee_mult * Company.Officer.mounted_blow_mult()
		var r: String = e.receive_blow(dmg, self, true)
		if r == "hit" and e.has_method("stagger"):
			e.stagger(fwd * 7.0, 1.0)
		battle.play_sound_ui("stab", 0.0)
		shake(0.6)
		horse.speed *= 0.8 # the shock of it
		couched = false
		_couch_cd = 1.2 # (bring it back down again)
		melee_hit.emit(1)
		return


## Off the horse, to its left side; it stands where it is.
func _get_down() -> void:
	mounted = false
	couched = false
	want_down = false
	horse.player = null
	horse.speed = 0.0
	var left: Vector3 = horse.forward().cross(Vector3.UP) * -1.3
	global_position += left
	mount_t = MOUNT_TIME
	battle.play_sound_ui("swish", -10.0)


## The horse killed under you: you're thrown.
func _horse_down() -> void:
	_get_down()
	mount_t = MOUNT_TIME * 0.5
	hp = maxf(1.0, hp - 8.0)
	shake(1.0)
	battle.hud.show_message(Lang.t("Your horse is down! You're thrown clear."), 2.5)


# ---------------------------------------------------------------- the gun

## Where the gunner kneels: behind the trail of `g`.
static func trail_point(g) -> Vector3:
	var back := 3.25 * (0.74 if g.light else 1.0)
	return g.crew.global_transform * Vector3(0, 0, back)


## A gun of yours, close enough to take over (nobody else at it).
func nearest_gun():
	if battle.field == null:
		return null
	var best = null
	var bd := GUN_REACH
	var cands: Array = battle.guns_down.duplicate()
	for r in battle.field.regs:
		if r.kind == "gun":
			cands.append_array(r.members)
	for g in cands:
		if not is_instance_valid(g) or g.manned or g.engine != "gun":
			continue
		# Your own gun with its crew, or any gun whose crew is down (yours
		# or one taken from them).
		var live: bool = int(g.side) == 0 and g.alive and not g.crew.silent
		if not live and not g.crew.silent:
			continue
		var d := minf(global_position.distance_to(trail_point(g)), global_position.distance_to(g.crew.global_position) + 0.5)
		if d < bd:
			bd = d
			best = g
	return best


func can_man_gun() -> bool:
	return alive and gun == null and not mounted and mount_t <= 0.0 and nearest_gun() != null


## MAN THE GUN / LEAVE THE GUN.
func toggle_gun() -> void:
	if gun != null:
		_leave_gun()
		return
	var g = nearest_gun()
	if g == null or not alive or mounted:
		return
	gun = g
	g.manned = true
	g.crew.manned = true
	g.crew.elev = g.crew.barrel.rotation.x
	rotation.y = g.crew.rotation.y
	pitch = 0.04
	aim_wanted = false
	spyglass = false
	battle.play_sound_ui("crank", -14.0)


func _leave_gun() -> void:
	var was = gun
	if gun != null and is_instance_valid(gun):
		gun.manned = false
		gun.crew.manned = false
	gun = null
	if was != null and battle.hud != null and alive:
		battle._hint("gun_back", Lang.t("To lay the gun again, walk back to its trail (behind it): MAN THE GUN shows on the left."), 7.0)


## At the trail: the gun turns (slowly) to where you look and the barrel
## rises and falls with your look; you stay at your post.
func _lay_gun() -> void:
	if not is_instance_valid(gun) or (not gun.alive and not gun.crew.silent):
		_leave_gun()
		return
	var tp: Vector3 = trail_point(gun)
	global_position = Vector3(tp.x, global_position.y, tp.z)
	gun.crew.want_yaw = rotation.y
	gun.crew.elev = clampf(pitch, -0.03, 0.5) # (never down into the works in front)


func toggle_shot() -> void:
	gun_shot = "canister" if gun_shot == "roundshot" else "roundshot"
	battle.play_sound_ui("crack", -18.0)


## Give the word: the crew stand clear and the match goes to the vent.
func _fire_gun() -> void:
	if gun.crew.silent:
		if not gun.crew.ready():
			battle.hud.show_message(Lang.t("It isn't loaded: sponge, load a round and ram it home at the muzzle first."), 2.0)
			return
		if not tools.has("linstock"):
			battle.hud.show_message(Lang.t("You need the linstock (the burning match) to fire it. Look on the ground by the gun."), 2.0)
			return
	elif not gun.crew.ready():
		battle.hud.show_message(Lang.t("Still loading!") if gun.crew.box_total() > 0 else Lang.t("The ammunition box is empty!"), 0.8)
		return
	if gun.crew.fire_laid(gun_shot, Company.Officer.gun_scatter_mult(), self):
		if gun.reg != null and is_instance_valid(gun.reg):
			gun.reg.fired()
		_shake = maxf(_shake, 0.7)
		fired.emit(false)


## 0..1: the gun's crew through their drill.
func gun_progress() -> float:
	return gun.crew.progress() if gun != null else 1.0


# ---------------------------------------------------------------- called by the HUD

func add_look(drag: Vector2) -> void:
	if not alive:
		return
	# Finer turning while aiming, for steady shots.
	var sens := LOOK_SENS * lerpf(1.0, 0.55, aim_amount) * (0.75 if gun != null else 1.0)
	if spyglass:
		sens *= SPYGLASS_FOV / FOV
	rotation.y -= drag.x * sens
	pitch = clampf(pitch - drag.y * sens, -1.2, 1.2)


## Put the spyglass to your eye, or take it down.
func toggle_spyglass() -> void:
	if not alive:
		return
	spyglass = not spyglass
	if spyglass:
		aim_wanted = false
	battle.play_sound_ui("swish", -14.0)


## Point at a spot in the world (an order to your men): turn to it and hold
## out your hand (or blade) for a moment.
func point_at(p: Vector3) -> void:
	if not alive:
		return
	var to := p - (global_position + Vector3.UP * 1.5)
	point_dir = to.normalized()
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.5:
		_point_yaw = atan2(-to.x, -to.z)
	point_t = 1.6
	spyglass = false


## The way you point, in your own body's space (for the arms).
func point_body_dir() -> Vector3:
	return global_transform.basis.inverse() * point_dir


func request_fire() -> void:
	if asleep_left > 0.0 or wake_left > 0.0 or fishing != null:
		return
	if spyglass:
		spyglass = false # (lower it first)
		return
	_want_fire = true


func toggle_weapon() -> void:
	switch_to("melee" if weapon == "musket" else "musket")


## Take up another weapon: fix or unfix the bayonet, draw the pistol from
## your belt or the sabre from its scabbard (the musket goes over your
## shoulder), or put them away and take up the musket again.
func switch_to(w: String) -> void:
	if not alive or switch_left > 0.0 or swing_phase != "idle" or throw_left > 0.0 or w == weapon:
		return
	if not w in weapons():
		return
	aim_wanted = false
	switch_from = weapon
	switch_target = w
	if (weapon == "musket" and w == "melee") or (weapon == "melee" and w == "musket"):
		switch_total = FIX_TIME if w == "melee" else UNFIX_TIME
	elif w == "melee":
		switch_total = DRAW_TIME + FIX_TIME * 0.8 # musket off the shoulder, then the bayonet
	else:
		switch_total = DRAW_TIME + (0.25 if weapon in ["pistol", "saber", "bow", "crossbow"] else 0.0)
	switch_left = switch_total
	_bayonet_sound_done = false


func is_switching() -> bool:
	return switch_left > 0.0


## Start winding up a blow. Returns false if you can't swing right now.
func begin_swing() -> bool:
	if not alive or not is_melee() or switch_left > 0.0 or swing_phase != "idle" or throw_left > 0.0:
		return false
	swing_phase = "windup"
	phase_time = 0.0
	swing_dir = Swing.NONE
	_release_requested = false
	blocking = false
	return true


## Where the blow comes from; can change freely until you release.
func set_swing_dir(dir: int) -> void:
	if swing_phase == "windup":
		swing_dir = dir


func release_swing() -> void:
	if swing_phase == "windup":
		_release_requested = true


func set_block(held: bool) -> void:
	block_held = held


## 0..1 how charged the current wind-up is.
func charge() -> float:
	if swing_phase == "windup":
		return clampf((phase_time - MIN_WINDUP) / (FULL_CHARGE - MIN_WINDUP), 0.0, 1.0)
	if swing_phase == "strike":
		return strike_charge
	return 0.0


## 0 while just fired, 1 when loaded.
func reload_progress() -> float:
	if loaded:
		return 1.0
	return 1.0 - reload_left / reload_time


## The blade in hand: [damage x, reach x, strike speed x, recovery speed x].
func blade() -> Array:
	if weapon == "melee" and has_pike:
		return BLADES["pike"]
	if weapon == "melee" and has_lance:
		return BLADES["lance"]
	return BLADES.get(weapon, [1.0, 1.0, 1.0, 1.0])


## How long the cut itself and the recovery take with the blade in hand.
func strike_time() -> float:
	return STRIKE_TIME / float(blade()[2])


func recover_time() -> float:
	return RECOVER_TIME / float(blade()[3])


## 0..1 through reloading the pistol.
func pistol_reload_progress() -> float:
	if pistol_loaded:
		return 1.0
	return 1.0 - pistol_reload_left / (PISTOL_RELOAD * reload_time / RELOAD_TIME)


## 0..1 through fixing or unfixing the bayonet (1 when not switching).
func switch_progress() -> float:
	if switch_left <= 0.0:
		return 1.0
	return 1.0 - switch_left / switch_total


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if alive:
		_keyboard_controls()

		var input := move_input
		if rig != null and not third_person:
			# Lying down your own arms and musket would fill the screen: show
			# them once you're half up.
			rig.visible = asleep_left <= 0.0 and wake_left < WAKE_TIME * 0.5
		if asleep_left > 0.0:
			asleep_left -= delta
			if asleep_left <= 0.0:
				wake_left = WAKE_TIME
			input = Vector2.ZERO
		elif wake_left > 0.0:
			wake_left = maxf(0.0, wake_left - delta)
			input = Vector2.ZERO
		var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if kb != Vector2.ZERO:
			input = kb
		var speed := SPEED * speed_mult * lerpf(1.0, 0.5, aim_amount)
		if blocking:
			speed *= 0.5
		elif swing_phase != "idle":
			speed *= 0.7
		var dir := global_transform.basis * Vector3(input.x, 0.0, input.y)
		dir.y = 0.0
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if mount_t > 0.0:
			mount_t = maxf(0.0, mount_t - delta)
			velocity.x = 0.0
			velocity.z = 0.0
		elif mounted and horse != null:
			if want_down:
				input = Vector2.ZERO # (reining in)
				if can_dismount():
					want_down = false
					_get_down()
			var hv: Vector3 = horse.drive(input, global_transform.basis, delta)
			velocity.x = hv.x
			velocity.z = hv.z
		if gun != null:
			velocity.x = 0.0
			velocity.z = 0.0
			_lay_gun()

		_work_tick(delta)
		_update_switch(delta)
		_update_swing(delta)
		_couch_tick(delta)
		blocking = block_held and is_melee() and swing_phase == "idle" and switch_left <= 0.0

		_update_throw(delta)
		if _want_fire:
			_want_fire = false
			if gun != null:
				_fire_gun()
			elif weapon == "musket" and switch_left <= 0.0 and throw_left <= 0.0:
				_fire()
			elif weapon == "pistol" and switch_left <= 0.0 and throw_left <= 0.0:
				_fire_pistol()
			elif MISSILE.has(weapon) and switch_left <= 0.0 and throw_left <= 0.0:
				_loose()

		_reprime = maxf(0.0, _reprime - delta)
		# You need both hands on the musket to reload it (and a cartridge).
		var steady: bool = not mounted or horse == null or horse.speed < 3.0 # (no loading at the trot)
		if not loaded and weapon == "musket" and switch_left <= 0.0 and ammo != 0 and steady:
			reload_left -= delta
			var p := reload_progress()
			for stroke in RAM_STROKES:
				if _last_reload_p < stroke and p >= stroke:
					battle.play_sound_ui("ramrod", -8.0)
			if _last_reload_p < 0.94 and p >= 0.94:
				battle.play_sound_ui("crack", -20.0) # the hammer clicks back
			_last_reload_p = p
			if reload_left <= 0.0:
				loaded = true
				_last_reload_p = 1.0
		# The pistol loads the same way, only while it's in your hand.
		if not pistol_loaded and weapon == "pistol" and switch_left <= 0.0 and ammo != 0 and steady:
			pistol_reload_left -= delta
			var pp := pistol_reload_progress()
			if _last_pistol_p < 0.55 and pp >= 0.55:
				battle.play_sound_ui("ramrod", -12.0)
			if _last_pistol_p < 0.92 and pp >= 0.92:
				battle.play_sound_ui("crack", -20.0)
			_last_pistol_p = pp
			if pistol_reload_left <= 0.0:
				pistol_loaded = true
				_last_pistol_p = 1.0
		# Bow and crossbow: nock an arrow, or wind the crossbow back.
		if MISSILE.has(weapon) and not bool(m_loaded[weapon]) and switch_left <= 0.0:
			m_left[weapon] = float(m_left[weapon]) - delta
			if weapon == "crossbow":
				_crank_t -= delta
				if _crank_t <= 0.0 and float(m_left[weapon]) > 0.6:
					_crank_t = 0.55
					battle.play_sound_ui("crank", -12.0)
			if float(m_left[weapon]) <= 0.0:
				m_loaded[weapon] = true
				if weapon == "crossbow":
					battle.play_sound_ui("crack", -18.0) # the bolt clicks into place
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


## PC testing: Space fires / winds up, arrow keys pick the blow, Q switches, E blocks.
func _keyboard_controls() -> void:
	if Input.is_action_just_pressed("switch_weapon"):
		toggle_weapon()
	if Input.is_action_just_pressed("grenade"):
		throw_grenade()
	if Input.is_action_just_pressed("aim"):
		toggle_aim()
	if Input.is_action_just_pressed("toggle_view"):
		toggle_view()
	if Input.is_action_just_pressed("mount"):
		toggle_mount()
	if Input.is_action_just_pressed("block"):
		block_held = true
	if Input.is_action_just_released("block"):
		block_held = false
	if fishing != null:
		if Input.is_action_just_pressed("fire"):
			fishing.press()
		if Input.is_action_just_released("fire"):
			fishing.release()
		return
	if is_gun():
		if Input.is_action_just_pressed("fire"):
			_want_fire = true
		return
	if Input.is_action_just_pressed("fire"):
		begin_swing()
	if swing_phase == "windup":
		if Input.is_action_pressed("swing_up"):
			swing_dir = Swing.OVERHEAD
		elif Input.is_action_pressed("swing_left"):
			swing_dir = Swing.LEFT
		elif Input.is_action_pressed("swing_right"):
			swing_dir = Swing.RIGHT
		elif Input.is_action_pressed("swing_down"):
			swing_dir = Swing.THRUST
	if Input.is_action_just_released("fire"):
		release_swing()


func _update_switch(delta: float) -> void:
	if switch_left <= 0.0:
		return
	switch_left -= delta
	# Time the scrape-and-click so the click lands as the bayonet locks on.
	var click_at := 0.46 if switch_target == "melee" else 0.05
	if switch_target in ["saber", "pistol", "bow", "crossbow"]:
		click_at = 0.5
	if not _bayonet_sound_done and switch_progress() >= click_at:
		_bayonet_sound_done = true
		if switch_target == "saber":
			battle.play_sound_ui("swish", -8.0) # the blade rasps out
		elif switch_target == "pistol":
			battle.play_sound_ui("crack", -22.0) # the hammer pulled back
		elif switch_target in ["bow", "crossbow"]:
			battle.play_sound_ui("swish", -14.0) # off your back
		else:
			battle.play_sound_ui("bayonet", -6.0)
	if switch_left <= 0.0:
		switch_left = 0.0
		weapon = switch_target


func _update_swing(delta: float) -> void:
	match swing_phase:
		"windup":
			phase_time += delta
			if _release_requested and phase_time >= MIN_WINDUP:
				strike_charge = charge()
				if swing_dir == Swing.NONE:
					swing_dir = Swing.THRUST # a quick tap is a thrust
				swing_phase = "strike"
				phase_time = 0.0
				_hit_done = false
		"strike":
			phase_time += delta
			var quick: float = blade()[2]
			if not _hit_done and phase_time >= STRIKE_TIME * 0.5 / quick:
				_hit_done = true
				_apply_melee()
			if phase_time >= STRIKE_TIME / quick:
				swing_phase = "recover"
				phase_time = 0.0
		"recover":
			phase_time += delta
			if phase_time >= recover_time():
				swing_phase = "idle"
				phase_time = 0.0
				swing_dir = Swing.NONE


func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _apply_melee() -> void:
	var data: Dictionary = SWINGS[swing_dir]
	var bl: Array = blade()
	var reach: float = float(data["reach"]) * float(bl[1])
	if mounted:
		reach += 0.9 # (from the saddle you reach down and out)
	var cone: float = data["cone"]
	var fwd := _flat_forward()
	var candidates := []
	for e in battle.enemies:
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach or d < 0.01:
			continue
		if rad_to_deg(fwd.angle_to(to)) > cone:
			continue
		candidates.append([d, e])
	candidates.sort_custom(func(a, b): return a[0] < b[0])

	var damage: float = (data["damage"] + data["charge_damage"] * strike_charge) * float(bl[0])
	if weapon == "saber":
		# A sabre is made for cutting: the slashes bite, the thrust less so.
		damage *= saber_mult * (0.75 if swing_dir == Swing.THRUST else 1.0)
	else:
		damage *= melee_mult
	if mounted and horse != null:
		# The horse's speed is in the blow.
		damage *= (1.0 + horse.speed / 12.0) * Company.Officer.mounted_blow_mult()
	var knock: float = data["knock"] * (1.0 + strike_charge * 0.5)
	var right := global_transform.basis.x
	var count := 0
	var shielded := 0
	for c in candidates:
		if count >= int(data["targets"]):
			break
		var e = c[1]
		var push: Vector3 = (e.global_position - global_position) * Vector3(1, 0, 1)
		push = push.normalized()
		# Side blows also shove sideways, in the direction of the sweep.
		if swing_dir == Swing.LEFT:
			push = (push + right * 0.6).normalized()
		elif swing_dir == Swing.RIGHT:
			push = (push - right * 0.6).normalized()
		# A charged blow (70%+) smashes through a raised shield.
		var result: String = e.receive_blow(damage, self, strike_charge >= 0.7)
		if result == "blocked":
			shielded += 1
			continue
		if result == "hit":
			e.stagger(push * knock, 0.35 + 0.25 * strike_charge)
		count += 1
	if count > 0:
		battle.play_sound_ui("stab", -2.0)
	elif shielded == 0:
		battle.play_sound_ui("swish", -6.0)
	if shielded > 0:
		struck_shield.emit()
	melee_hit.emit(count)


func _fire() -> void:
	if not loaded and ammo == 0:
		battle.hud.show_message(Lang.t("Your cartridge box is empty!"), 1.2)
		return
	if not loaded or _reprime > 0.0:
		return
	if randf() < misfire_chance + battle.wx_misfire * (0.4 if Company.Officer.forged("lock") else 1.0):
		# A flash in the pan: prime it again.
		_reprime = 1.2
		battle.play_sound_ui("crack", -10.0)
		battle.hud.show_message(Lang.t("Misfire!"), 1.0)
		return
	loaded = false
	reload_left = reload_time * battle.wx_reload
	if ammo > 0:
		ammo -= 1
		ammo_used += 1
	_last_reload_p = 0.0
	battle.play_sound_ui("musket", 0.0)

	# The ball leaves along your line of sight (so it goes where the crosshair
	# is), starting level with you so in third person it can't hit the men
	# behind you. It flies, drops, and hits whatever is first in its path.
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var to_me := global_position + Vector3.UP * 1.5 - from
	from += fwd * maxf(0.4, to_me.dot(fwd))
	var spread := lerpf(SPREAD, AIM_SPREAD, aim_amount) * spread_mult
	fwd = battle.projectiles.spread_dir(fwd, spread)
	battle.projectiles.fire("ball", from, fwd * BALL_SPEED, self)
	var hit := false

	var right := camera.global_transform.basis.x
	if rig != null:
		var muzzle: Vector3 = rig.muzzle_global()
		battle.spawn_smoke(muzzle + fwd * 1.2, 0.9, fwd)
		battle.spawn_flash(muzzle + fwd * 0.1)
	else:
		battle.spawn_smoke(from + fwd * 2.5 + right * 0.4 - Vector3.UP * 0.3, 0.8)
		battle.spawn_flash(from + fwd * 1.2 + right * 0.3 - Vector3.UP * 0.25)
	fired.emit(hit)


## The pistol: one quick shot, short-ranged and wild, then a slow reload.
func _fire_pistol() -> void:
	if not pistol_loaded and ammo == 0:
		battle.hud.show_message(Lang.t("Your cartridge box is empty!"), 1.2)
		return
	if not pistol_loaded:
		return
	if randf() < misfire_chance * 1.5:
		battle.play_sound_ui("crack", -10.0)
		battle.hud.show_message(Lang.t("The pistol misfires!"), 1.0)
		return
	pistol_loaded = false
	pistol_reload_left = PISTOL_RELOAD * reload_time / RELOAD_TIME
	_last_pistol_p = 0.0
	if ammo > 0:
		ammo -= 1
		ammo_used += 1
	battle.play_sound_ui("musket", -3.0)
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var to_me := global_position + Vector3.UP * 1.5 - from
	from += fwd * maxf(0.4, to_me.dot(fwd))
	fwd = battle.projectiles.spread_dir(fwd, lerpf(PISTOL_SPREAD, PISTOL_AIM_SPREAD, aim_amount) * spread_mult)
	battle.projectiles.fire("pistol", from, fwd * PISTOL_SPEED, self)
	if rig != null:
		var muzzle: Vector3 = rig.pistol_muzzle_global()
		battle.spawn_smoke(muzzle + fwd * 0.6, 0.5)
		battle.spawn_flash(muzzle + fwd * 0.05, 0.7)
	_shake = maxf(_shake, 0.25)
	fired.emit(false)


## Loose an arrow or a bolt along your line of sight. A drawn bow (aiming)
## is steady; a quick loose from the hip scatters.
func _loose() -> void:
	if not bool(m_loaded[weapon]):
		return
	var spec: Array = MISSILE[weapon]
	m_loaded[weapon] = false
	m_left[weapon] = float(spec[0])
	_crank_t = 0.4
	battle.play_sound_ui("bow" if weapon == "bow" else "crossbow", -2.0)
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var to_me := global_position + Vector3.UP * 1.5 - from
	from += fwd * maxf(0.4, to_me.dot(fwd))
	fwd = battle.projectiles.spread_dir(fwd, lerpf(float(spec[2]), float(spec[3]), aim_amount) * spread_mult)
	var p: Dictionary = battle.projectiles.fire(String(spec[4]), from, fwd * float(spec[1]), self)
	p["dmg_mult"] = float(spec[5])
	battle.missile_spent(String(spec[4]))
	fired.emit(false)


## Called by the projectile system when one of your balls hits someone.
func on_projectile_hit(u: Node3D) -> void:
	var kind = u.get("rig_kind")
	if kind == "lizard":
		shot_hit.emit()
	elif kind == "soldier":
		friendly_fire.emit(true)


## A ball or a blast: can't be parried.
func take_shot(amount: float, from: Node3D = null) -> void:
	_shot = true
	take_damage(amount, from)
	_shot = false
	if from != null and is_instance_valid(from) and from != self and from.is_in_group("friendlies"):
		friendly_fire.emit(false)


func take_damage(amount: float, from: Node3D = null) -> void:
	if not alive:
		return
	if asleep_left > 0.0:
		asleep_left = 0.01 # that wakes you
	if blocking and not _shot and from != null and is_instance_valid(from):
		var to := from.global_position - global_position
		to.y = 0.0
		if rad_to_deg(_flat_forward().angle_to(to)) <= block_arc:
			# Parried: no damage, and the attacker reels back.
			if from.has_method("stagger"):
				from.stagger(to.normalized() * 2.5, 0.5)
			if has_pike and weapon == "melee" and from.has_method("take_damage"):
				# Braced: he ran onto the point.
				from.take_damage(38.0 * melee_mult, self)
				battle.play_sound_ui("stab", -4.0)
			battle.play_sound_ui("clang", -3.0)
			blocked.emit()
			return
	if mounted and horse != null and not horse.dead and randf() < (0.35 if _shot else 0.45):
		# It's the horse that's hit.
		battle.play_sound_ui("grunt", -8.0)
		if horse.hurt(amount * Company.Officer.diff("hurt")):
			_horse_down()
		return
	if not _shot:
		amount *= 1.0 - armour # your coat turns some of a hack
	amount *= Company.Officer.diff("hurt") # (the difficulty)
	hp -= amount
	battle.play_sound_ui("stab", -4.0)
	battle.play_sound_ui("grunt", -6.0)
	hurt.emit()
	if hp <= 0.0:
		hp = 0.0
		alive = false
		var tw := create_tween().set_parallel(true)
		tw.tween_property(camera, "position:y", 0.3, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(camera, "rotation:z", 0.6, 0.8)
		died.emit()
