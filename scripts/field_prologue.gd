extends Node
## The prologue as a field battle: Wreck Beach (names in lore.gd), the
## tutorial.
##
## The regiment is entrenched on the beach where the ship broke up: your
## company in the centre behind the earthworks, a company either side of it,
## a battery of two guns between each, the sea at their backs. The Major
## commands; you fight in the line (the beats teach the controls: see
## _tutorial). In the second wave a javelin brings him down. You go to him,
## and he hands you the regiment:
##
##   line          the Major's battle: two waves out of the forest
##   captain_down  go to him (the gold marker)
##   command       the regiment is yours: the command view opens, paused,
##                 with a lesson; a third wave comes, brutes and raptor
##                 riders with it. Fight it, from above or in the line.
##   collapse      after a while (or sooner if the regiment bleeds) a horde
##                 comes round the left end of the works, the left company
##                 breaks and the guns are overrun
##   retreat       lead what's left along the beach to the cliff path while
##                 the horde comes on behind
##   escaped       up the path: the battle ends, the campaign begins
##
## battle.gd keeps the story's state (story_phase, captain, objective, the
## dialogue queue) so the HUD and the autotest read it as before.

const Lore := preload("res://scripts/lore.gd")
const RETREAT_POINT := Vector3(95, 0, 14) # the cliff path at the right end of the beach
const GUN_X := [-37.0, -15.5, 15.5, 37.0] # the embrasures (field_terrain.gd's EARTHWORK_GAPS)
const LINE_Z := 8.0 # your company's front rank, just behind the crest
const GUN_Z := 6.8
const FOREST_Z := -72.0 # where they come out of the trees
const SIDE_COMPANY := 20
const COMMAND_TIME := 55.0 # how long the line holds once you have it
const PURSUIT_EVERY := 10.0

var field
var battle
var phase := "line"
var phase_t := 0.0
var wave := 0
var left_reg = null
var right_reg = null
var batteries: Array = []
var _volley_cd := 0.0
var _javelin_done := false
var _heard := false
var _pursuit_t := 0.0
var _side0 := 1 # men on your side at the start (for Lang.t("the regiment is bleeding"))
var _wave3_t := -1.0


func _init(f) -> void:
	field = f
	battle = f.battle
	name = "Prologue"


# ---------------------------------------------------------------- the muster

func spawn() -> void:
	var men: Array = Company.fit_men()
	var you = field._make_reg(0, "musket", maxi(1, men.size()), Vector3(0, 0, LINE_Z), Vector3.FORWARD, true, men)
	you.fire_at_will = false # the Major calls the volleys
	left_reg = field._make_reg(0, "musket", SIDE_COMPANY, Vector3(-26.25, 0, LINE_Z), Vector3.FORWARD, false)
	left_reg.title = Lang.t("Left company")
	right_reg = field._make_reg(0, "musket", SIDE_COMPANY, Vector3(26.25, 0, LINE_Z), Vector3.FORWARD, false)
	right_reg.title = Lang.t("Right company")
	for sx in [-1.0, 1.0]:
		# Two guns a battery, one in each embrasure either side of a company.
		var b = field._make_reg(0, "gun", 2, Vector3(sx * 26.25, 0, GUN_Z), Vector3.FORWARD, false, [], 21.5)
		b.title = Lang.t("Left battery") if sx < 0.0 else Lang.t("Right battery")
		batteries.append(b)
	for r in field.regs:
		r.order_hold()
	# You: in the gap in the middle of your company's front rank.
	var p: Vector3 = you.pos
	battle.player.position = Vector3(p.x, field.terrain.height(p.x, p.z) + 0.3, p.z)
	battle.player.rotation.y = 0.0
	# The Major, behind the line (the old company soldier: he only stands
	# and gives orders, and he can't be killed until his javelin comes).
	var c = battle.SoldierScript.new()
	c.battle = battle
	c.frames = battle.soldier_frames
	c.ally = true
	c.rig_look = "officer"
	c.display_name = Lore.COMMANDER
	c.ammo = 0
	c.loaded = false
	c.invulnerable = true
	c.ally_forward = Vector3.FORWARD
	c.ally_slot = Vector3(1.5, 0, LINE_Z + 3.4)
	c.position = c.ally_slot
	battle.captain = c
	battle.allies.append(c)
	battle.add_child(c)
	battle.line_anchor = Vector3(0, 0, LINE_Z)
	battle.line_forward = Vector3.FORWARD
	battle._commanding = false
	battle.story_phase = "line"
	battle._all_men = []
	for m in you.members:
		if m.get("record") != null:
			battle._all_men.append(m)
	_side0 = _men_on_our_side()
	phase_t = 0.0


## Lizards out of the forest: one wave of the Major's battle, or the one you
## fight, or the horde.
func _wave(n: int) -> void:
	wave = n
	battle.wave = mini(n, 2) # (the autotest reads it; it charges at 3)
	match n:
		1:
			_lizards("liz_warrior", 12, Vector3(-22, 0, FOREST_Z))
			_lizards("liz_warrior", 12, Vector3(20, 0, FOREST_Z - 6.0))
			_lizards("liz_skirm", 6, Vector3(0, 0, FOREST_Z + 12.0))
			battle.hud.show_message(Lang.t("Here they come!"), 2.5)
		2:
			_lizards("liz_warrior", 14, Vector3(-30, 0, FOREST_Z))
			_lizards("liz_warrior", 14, Vector3(8, 0, FOREST_Z - 4.0))
			_lizards("liz_skirm", 10, Vector3(-10, 0, FOREST_Z + 14.0))
			battle.hud.show_message(Lang.t("The second wave! Hold the line!"), 2.5)
		3:
			_lizards("liz_warrior", 16, Vector3(-28, 0, FOREST_Z))
			_lizards("liz_brute", 5, Vector3(4, 0, FOREST_Z - 4.0))
			_lizards("liz_warrior", 16, Vector3(30, 0, FOREST_Z))
			_lizards("liz_raptor", 8, Vector3(70, 0, FOREST_Z + 6.0))
			field.alert(null, Lang.t("Brutes in the centre, raptor riders on the right!"), true)


func _lizards(kind: String, n: int, at: Vector3):
	var r = field._make_reg(1, kind, n, at, Vector3.BACK, false)
	if field.ui != null:
		field.ui.add_banner(r)
	return r


func _men_on_our_side() -> int:
	var n := 0
	for r in field.regs:
		if r.side == 0 and r.kind != "gun" and not r.broken():
			n += r.members.size()
	return n


# ---------------------------------------------------------------- the story

func _process(delta: float) -> void:
	if battle == null or battle.hud == null or get_tree().paused:
		return
	phase_t += delta
	_volley_cd -= delta
	_tutorial()
	match phase:
		"line":
			_line(delta)
		"captain_down":
			_captain_down_tick()
		"command":
			if _wave3_t >= 0.0:
				_wave3_t -= delta
				if _wave3_t < 0.0:
					_wave(3)
			var bleeding := _men_on_our_side() < _side0 * 0.5
			if phase_t > COMMAND_TIME or (phase_t > 25.0 and bleeding):
				_collapse()
		"collapse":
			if phase_t > 9.0:
				_begin_retreat()
		"retreat":
			battle.objective = {"label": Lang.t("THE CLIFF PATH"), "pos": RETREAT_POINT, "height": 5.4}
			_pursuit_t -= delta
			if _pursuit_t <= 0.0:
				_pursuit_t = PURSUIT_EVERY
				_pursuit(8)
			var pl = battle.player
			if pl.alive and pl.global_position.distance_to(RETREAT_POINT) < 8.0:
				_set_phase("escaped")
				battle.objective = {}
				battle.hud.show_message(Lang.t("Up the cliff path and into the fog. They don't follow."), 9999.0)
				field.over = "won"
				battle.victory = true
				battle._end_battle(true)


func _set_phase(p: String) -> void:
	phase = p
	phase_t = 0.0
	battle.story_phase = p


func _line(_delta: float) -> void:
	if wave == 0 and phase_t > 12.0:
		_wave(1)
		phase_t = 0.0
	elif wave == 1 and (phase_t > 45.0 or (phase_t > 12.0 and _all_down())):
		_wave(2)
		phase_t = 0.0
	elif wave == 2 and not _javelin_done:
		var c = battle.captain
		var close: Node3D = battle.nearest_enemy(c.global_position, 30.0)
		if close != null or phase_t > 18.0:
			_javelin_done = true
			battle._throw_at_captain(close)
	# The Major's fire discipline: a volley when most are loaded and they're
	# close enough to hit.
	var you = field.player_reg
	if you != null and not you.broken() and _volley_cd <= 0.0 and you.nearest_foe_reg != null and you.nearest_foe_d < 45.0:
		var loaded := 0
		for m in you.members:
			if m.get("loaded") == true:
				loaded += 1
		if loaded >= ceili(you.members.size() * 0.6):
			_volley_cd = 4.0
			you.fire_target = you.nearest_foe_reg
			you.order_volley()
			battle.hud.show_message(Lang.t("Harrow: Present... FIRE!"), 1.2)


func _all_down() -> bool:
	for r in field.regs:
		if r.side == 1 and not r.broken():
			return false
	return true


## battle.gd: the javelin found him.
func captain_down() -> void:
	_set_phase("captain_down")
	battle.hud.show_message(Lang.t("%s is down!") % Lore.COMMANDER_SHORT, 3.0)
	battle.say(battle._sergeant_name(), Lang.t("The Major's hit! Ensign, to the Major!"), 4.0)


func _captain_down_tick() -> void:
	var c = battle.captain
	if c == null or _heard:
		return
	battle.objective = {"label": Lang.t("THE MAJOR"), "pos": c.global_position}
	var pl = battle.player
	if pl.alive and pl.global_position.distance_to(c.global_position) < 2.6:
		_heard = true
		battle.objective = {}
		battle._lines.clear()
		battle._line_t = 0.0
		battle.say(Lore.COMMANDER, Lang.t("Ensign... listen. You have the regiment. All of it: the companies, the guns."), 4.5)
		battle.say(Lore.COMMANDER, Lang.t("Hold them on the works while you can. When it breaks, and it will, take them up the cliff path. Keep them alive."), 6.0, _begin_command)
		battle.say("", Lang.t("%s is dead. You command the regiment.") % Lore.COMMANDER_SHORT, 3.5)
	elif phase_t > 22.0:
		_heard = true
		battle.objective = {}
		battle.say(battle._sergeant_name(), Lang.t("He's gone, sir! The Major's dead. You have the regiment. Orders, sir!"), 4.5, _begin_command)


## The regiment is yours: up into the command view, paused, with a lesson.
func _begin_command() -> void:
	_set_phase("command")
	battle._commanding = true
	field.player_reg.fire_at_will = true
	_wave3_t = 5.0
	battle.hud.show_message(Lang.t("You command the regiment!"), 3.0)
	if field.ui != null and battle.player.alive and not field.test_mode:
		field.ui.lesson = [
			Lang.t("YOU HAVE THE REGIMENT"),
			Lang.t("Your companies and the guns are on the cards along the bottom. Tap a card, or the regiment on the field, to select it (ALL takes every one)."),
			Lang.t("Then tap the ground to march there, drag along the ground to form a line there, or tap an enemy to attack it."),
			Lang.t("Up here time runs slow (PAUSE stops it). TO YOUR MEN takes you back down; COMMAND at the top brings you up again."),
			Lang.t("In first person the cards are along the top: select one and tap the world to send it."),
		]
		field.ui.open(true)
		var right: Vector3 = field.player_reg.pos
		field.ui.focus = Vector3(right.x, 0, right.z - 30.0)
		field.ui.dist = 120.0


## The line goes: a horde round the left end of the works, the left company
## breaks, the guns are overrun.
func _collapse() -> void:
	_set_phase("collapse")
	_lizards("liz_warrior", 22, Vector3(-75, 0, -12))
	_lizards("liz_warrior", 18, Vector3(-62, 0, -30))
	_lizards("liz_raptor", 8, Vector3(-90, 0, 0))
	if left_reg != null and not left_reg.broken():
		left_reg.morale = 0.0
		left_reg._set_state("routing")
	field.alert(left_reg, Lang.t("The left is turned! They're over the earthworks!"), true)
	battle.say(battle._sergeant_name(), Lang.t("Sir! The left's gone, they're round the end of the works!"), 4.0)


## Off the beach: every company that still stands for the cliff path, the
## guns left where they are.
func _begin_retreat() -> void:
	_set_phase("retreat")
	_pursuit_t = 3.0
	battle.say(battle._sergeant_name(), Lang.t("The line's gone, sir. The cliff path, it's the only way off the beach!"), 4.5)
	battle.hud.show_message(Lang.t("Leave the guns! Along the beach to the cliff path!"), 4.0)
	for b in batteries:
		b.fire_at_will = false
		for g in b.members:
			if is_instance_valid(g) and g.crew != null:
				g.crew.silent = true
	for r in field.regs:
		if r.side != 0 or r.broken() or r.kind == "gun":
			continue
		if r == field.player_reg:
			r.order_hold()
			r.order = "follow"
		else:
			r.order_move(RETREAT_POINT + Vector3(-6.0 * float(r.id % 3), 0, 0), Vector3.RIGHT, true)
	_pursuit(10)


## More of the horde, close behind you and round the broken left.
func _pursuit(n: int) -> void:
	var p: Vector3 = battle.player.global_position
	var at := Vector3(clampf(p.x + randf_range(-20.0, 10.0), -140.0, 140.0), 0, clampf(p.z - randf_range(40.0, 50.0), -140.0, 20.0))
	var r = _lizards("liz_warrior", n, at)
	r.order_attack(field.player_reg if field.player_reg != null and not field.player_reg.gone() else r.nearest_foe_reg)


## Where a broken company of ours runs: the cliff path.
func flee_point(_u) -> Vector3:
	return RETREAT_POINT + Vector3(6.0, 0, 0)


## You fell: the story ends there.
func player_down() -> void:
	battle.objective = {}
	battle.hud.show_message(Lang.t("You fall. Your men carry you from the beach."), 9999.0)
	field.over = "lost"
	battle._end_battle(false)


# ---------------------------------------------------------------- the lessons

## Each beat shows the controls it needs, once.
func _tutorial() -> void:
	var b = battle
	if phase == "line" and wave == 0:
		b._hint("move", Lang.t("MOVE: drag on the left of the screen.  LOOK: drag on the right.  Walk the earthworks while the guns are readied."), 11.0)
	if wave >= 1 and phase == "line":
		b._hint("fire", Lang.t("FIRE: tap to shoot; keep your thumb down and drag to aim.  AIM: sight down the barrel.  Reloading takes a few seconds; the Major calls the company's volleys."), 12.0)
	if not b._hints.has("melee") and b.player.alive and b.nearest_enemy(b.player.global_position, 14.0) != null:
		b._hint("melee", Lang.t("BAYONET: fix it for close work. OVER, LEFT, RIGHT, THRUST strike from that side: hold to charge, release to strike.  BLOCK when one rears up glowing."), 12.0)
	if wave >= 2 and phase == "line":
		b._hint("grenade", Lang.t("GRENADE: lob one into a crowd 10 to 20 m out. Mind your own men."), 8.0)
	if phase == "captain_down":
		b._hint("major", Lang.t("Go to the Major: follow the gold marker."), 8.0)
	if phase == "command" and phase_t > 1.0:
		b._hint("orders", Lang.t("Your company: FOLLOW, HOLD, CHARGE, AT WILL and VOLLEY!  The rest: COMMAND (top) for the view from above, or tap a card along the top and then the world."), 14.0)
	if phase == "retreat":
		b._hint("retreat", Lang.t("Lead them to the cliff path: your company follows you. The others are already running for it."), 10.0)
