extends Node3D
## The battle. You (an officer with a musket) and a company of musketeers
## hold a field against waves of charging lizardmen. Everything is built in
## code, so the scene file is just this one node.
##
## The company is the "squad brain": it owns the line (anchor + facing) and
## hands each soldier a slot. Soldiers and lizardmen themselves stay dumb.

const PlayerScript := preload("res://scripts/player.gd")
const SoldierScript := preload("res://scripts/soldier.gd")
const LizardScript := preload("res://scripts/lizardman.gd")
const HudScript := preload("res://scripts/hud.gd")
const SpriteFactory := preload("res://scripts/sprite_factory.gd")
const SoundFactory := preload("res://scripts/sound_factory.gd")
const BatcherScript := preload("res://scripts/batcher.gd")
const ProjectilesScript := preload("res://scripts/projectiles.gd")
const Props := preload("res://scripts/props.gd")
const Rig3D := preload("res://scripts/rig3d.gd")
const Lore := preload("res://scripts/lore.gd")
const MENU := "res://scenes/menu.tscn"
const AFTERMATH := "res://scenes/aftermath.tscn"
const MAX_SOUNDS := 24

enum FireMode { ON_COMMAND, AT_WILL }
enum Order { FOLLOW, HOLD, CHARGE }

const COMPANY_SIZE := 8
const STRESS_COMPANY := 50
const STRESS_WAVES := [200]
const LINE_SPACING := 1.5 # metres between men in the line
const LINE_DISTANCE := 0.0 # you stand in the line itself, in the gap at its centre
const REALIGN_ANGLE := 40.0 # degrees you must turn before a following line wheels
const WAVES := [8, 14, 20]
const SPAWN_DISTANCE := 65.0

# ---- the prologue: a big battle that goes wrong (see _prologue_process)
const PROLOGUE_WAVES := [26, 34]
const ALLY_COMPANY := 12 # men in each of the two companies beside yours
const RETREAT_POINT := Vector3(95, 0, 14) # the cliff path at the right end of the beach
const RETREAT_WAVE := 8
const RETREAT_EVERY := 9.0
const MAX_ENEMIES := 50

var fire_mode: int = FireMode.ON_COMMAND
var order: int = Order.FOLLOW
var player
var hud
var soldiers: Array = []
var enemies: Array = []

var line_anchor := Vector3.ZERO
var line_forward := Vector3.FORWARD
var wave := 0
var waves: Array = [] # how many lizardmen arrive in each wave
var slain := 0
var _all_men: Array = [] # every soldier who took the field, fallen or not
var _unplanned := 0 # men without a place in the battle plan (they form the line)
var ambush := false
var wagon: Node3D # the baggage wagon (campaign battles)
var wagon_looted := 0.0 # share of its stores the lizards have carried off (0..0.8)
var _porters: Array = []
## After a victory: men cheer, then go through the dead lizards' things and
## tend the fallen (see soldier.gd _after_victory).
var victory := false
var victory_t := 0.0
var lizard_corpses: Array = [] # Vector3
var _claimed := {} # corpse/comrade index -> soldier
var _loot_told := false
var _reported := false
var game_state := "starting" # starting, fighting, between, won, lost
var state_timer := 5.0

var batcher # draws every unit in a few instanced batches
var projectiles # every musket ball, grenade and javelin in flight
var soldier_frames: Dictionary # sprite atlas info (cells, counts)
var lizard_frames: Dictionary
var smoke_tex: Texture2D
var sounds: Dictionary
var _active_sounds := 0

var _autotest := false
var _autotest_timer := 0.0

# Prologue state.
var prologue := false
var allies: Array = [] # the other companies' men (not yours)
var captain = null
var story_phase := "" # line -> captain_down -> retreat -> escaped
var objective := {} # {"label": String, "pos": Vector3} for the HUD marker
var _commanding := true # you give the orders (in the prologue, not at first)
var _phase_t := 0.0
var _volley_cd := 0.0
var _javelin_done := false
var _wave_t := 0.0
var _heard_captain := false
var _lines: Array = [] # [speaker, text, seconds, Callable or null]
var _line_t := 0.0


func _ready() -> void:
	_autotest = "--autotest" in OS.get_cmdline_user_args()
	Music.set_context("battle")
	prologue = Company.active and Company.prologue
	_setup_input()
	# The batcher first: everything that draws a character registers with it.
	batcher = BatcherScript.new()
	batcher.add_to_group("batcher")
	add_child(batcher)
	# Sprite atlases are built in both modes (in 3D they're far stand-ins).
	projectiles = ProjectilesScript.new()
	projectiles.battle = self
	add_child(projectiles)
	soldier_frames = batcher.add_sprite_kind("soldier", SpriteFactory.soldier_frames())
	lizard_frames = batcher.add_sprite_kind("lizard", SpriteFactory.lizard_frames())
	smoke_tex = SpriteFactory.smoke_texture()
	sounds = SoundFactory.build_all()
	_build_world()

	player = PlayerScript.new()
	player.battle = self
	player.position = Vector3(0, 0.1, 8)
	add_child(player)
	player.died.connect(_on_player_died)

	line_forward = Vector3.FORWARD
	line_anchor = Vector3(player.position.x, 0, player.position.z) + line_forward * LINE_DISTANCE
	# Campaign: your actual men (the fit ones) against the warband the scouts
	# reported. Otherwise a stand-alone battle (stress test, autotest).
	if Company.active:
		if prologue:
			waves = PROLOGUE_WAVES
		elif not Company.next_battle.is_empty():
			waves = Company.waves_for(int(Company.next_battle["enemy"])) # the warband you met on the map
		else:
			waves = Company.waves_for(Company.next_enemy_count())
		for rec in Company.fit_men():
			var s = SoldierScript.new()
			s.battle = self
			s.frames = soldier_frames
			s.record = rec
			soldiers.append(s)
	else:
		waves = STRESS_WAVES if Settings.stress else WAVES
		for i in (STRESS_COMPANY if Settings.stress else COMPANY_SIZE):
			var s = SoldierScript.new()
			s.battle = self
			s.frames = soldier_frames
			soldiers.append(s)
	_all_men = soldiers.duplicate()
	ambush = Company.active and not prologue and bool(Company.next_battle.get("ambush", false))
	if Company.active and not prologue:
		for s in soldiers:
			var pl = s.record.get("plan")
			if pl is Array and pl.size() == 2:
				s.plan_pos = Vector2(float(pl[0]), float(pl[1]))
	_reassign_slots()
	for s in soldiers:
		s.position = slot_of(s)
		if ambush:
			# Caught off guard: men all over the place, they'll form up as they can.
			s.position = player.position + Vector3(randf_range(-9, 9), -0.1, randf_range(-6, 10))
		add_child(s)
	if Company.active and not prologue:
		_build_wagon()
	if prologue:
		_setup_prologue()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.battle = self
	hud.player = player
	layer.add_child(hud)
	if prologue:
		state_timer = 11.0
		say("", "%s. The regiment's survivors hold the beach where the %s broke up, the sea at their backs." % [Lore.BEACH, Lore.SHIP], 5.5)
		say(Lore.COMMANDER, "Stay by me, Ensign, and keep your musket loaded. The guns will open first. I give the orders today.", 5.5)
	elif ambush:
		hud.show_message("AMBUSH! Form on me!", 4.0)
	elif Company.active and Company.march_note != "":
		hud.show_message(Company.march_note, 6.0)
		state_timer = maxf(state_timer, 6.0)
	else:
		hud.show_message("Form the line! They're coming...", 4.5)


# ---------------------------------------------------------------- orders

## In the prologue the captain commands until he falls.
func can_command() -> bool:
	return _commanding


func _not_yours() -> bool:
	if _commanding:
		return false
	hud.show_message("%s has the command." % Lore.COMMANDER_SHORT, 1.5)
	return true


func order_follow() -> void:
	if _not_yours():
		return
	order = Order.FOLLOW
	_snap_line_to_player()
	hud.show_message("Company — follow me!", 1.5)


## Break ranks: every man picks his own fight (see soldier.gd). With no
## enemies left they regroup on you as if following.
func order_charge() -> void:
	if _not_yours():
		return
	order = Order.CHARGE
	hud.show_message("CHARGE! At them, lads!", 1.5)


func order_hold() -> void:
	if _not_yours():
		return
	order = Order.HOLD
	_snap_line_to_player() # the line forms where you're looking, then stays
	hud.show_message("Company — halt! Hold here!", 1.5)


func toggle_fire_mode() -> void:
	if _not_yours():
		return
	if fire_mode == FireMode.ON_COMMAND:
		fire_mode = FireMode.AT_WILL
		hud.show_message("Fire at will!", 1.5)
	else:
		fire_mode = FireMode.ON_COMMAND
		hud.show_message("Hold your fire... wait for the order!", 1.5)


func order_volley() -> void:
	if _not_yours():
		return
	_volley()


func _volley() -> void:
	if loaded_count() == 0:
		hud.show_message("Nobody's loaded!", 1.0)
		return
	hud.show_message("PRESENT... FIRE!", 1.0)
	for s in soldiers:
		s.volley()


func wave_count() -> int:
	return waves.size()


## The HUD's status line.
func status_line() -> String:
	var tail := "Company %d   Loaded %d" % [soldiers.size(), loaded_count()]
	if prologue:
		var what := "RETREAT" if story_phase == "retreat" else Lore.BEACH
		return "%s   Lizardmen %d   %s" % [what, enemies.size(), tail]
	if rations_spoiled > 0 or looters() > 0:
		tail += "   Wagon: %d looters, %d rations eaten" % [looters(), rations_spoiled]
	return "Wave %d/%d   Lizardmen %d   %s" % [wave, wave_count(), enemies.size(), tail]


func is_at_will() -> bool:
	return fire_mode == FireMode.AT_WILL


func is_following() -> bool:
	return order == Order.FOLLOW


func is_holding() -> bool:
	return order == Order.HOLD


func is_charging() -> bool:
	return order == Order.CHARGE


func loaded_count() -> int:
	var n := 0
	for s in soldiers:
		if s.loaded:
			n += 1
	return n


func restart() -> void:
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().change_scene_to_file(MENU)


# ---------------------------------------------------------------- sound

## A positional sound in the world (muskets, blades, roars).
func play_sound(name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if not sounds.has(name) or _active_sounds >= MAX_SOUNDS:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds[name]
	p.position = pos
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.9, 1.1)
	p.unit_size = 6.0
	p.max_distance = 160.0
	add_child(p)
	_play_and_free(p)


## A sound at the listener: your own musket, your own blows.
func play_sound_ui(name: String, volume_db: float = 0.0) -> void:
	if not sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sounds[name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	add_child(p)
	_play_and_free(p)


func _play_and_free(p: Node) -> void:
	_active_sounds += 1
	p.finished.connect(func():
		_active_sounds -= 1
		p.queue_free())
	p.play()


# ---------------------------------------------------------------- formation

## Where a man should stand: his place from the battle plan (metres right of
## and ahead of the officer, turned with the line), or a slot in the line.
func slot_of(s) -> Vector3:
	if s.plan_pos != null:
		var right := line_forward.cross(Vector3.UP).normalized()
		var pp: Vector2 = s.plan_pos
		return line_anchor + right * pp.x + line_forward * pp.y
	return get_slot_position(s.slot_index)


func get_slot_position(index: int) -> Vector3:
	var n := _unplanned
	var right := line_forward.cross(Vector3.UP).normalized()
	var offset := (float(index) - (n - 1) * 0.5) * LINE_SPACING
	# Leave a gap at the centre of the line for you, the officer.
	offset += LINE_SPACING * 0.5 * (1.0 if offset >= 0.0 else -1.0)
	return line_anchor + right * offset


func _player_forward() -> Vector3:
	var f: Vector3 = -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _snap_line_to_player() -> void:
	line_forward = _player_forward()
	var p: Vector3 = player.global_position
	line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE
	_reassign_slots()


## Give slots left-to-right by where men currently stand, so nobody crosses
## through the line. Also used to "close ranks" when someone falls.
func _reassign_slots() -> void:
	var right := line_forward.cross(Vector3.UP).normalized()
	var anchor := line_anchor
	soldiers.sort_custom(func(a, b): return (a.position - anchor).dot(right) < (b.position - anchor).dot(right))
	var i := 0
	for so in soldiers:
		if so.plan_pos == null:
			so.slot_index = i
			i += 1
	_unplanned = i


# ---------------------------------------------------------------- the wagon
# The baggage wagon stands where the battle plan puts it (usually behind the
# line) and the porters drag it after the company. Lizards love loot: some
# break off to plunder it, and while they rummage they don't fight, which
# makes the wagon bait as much as a burden.

const WAGON_SPEED := 1.8
const LOOT_RATE := 0.009 # share of the wagon carried off per lizard per second
const LOOT_MAX := 0.8


func _build_wagon() -> void:
	wagon = Props.wagon()
	add_child(wagon)
	wagon.position = _wagon_target()
	if ambush:
		wagon.position = player.position + Vector3(randf_range(-4, 4), 0, randf_range(2, 6))
	for side in [-1.0, 1.0]:
		var r := Rig3D.new()
		r.kind = "soldier"
		r.gear = {"head": "cap", "torso": "shirt", "primary": "musket", "secondary": ""}
		r.pack = {"water": 0, "rations": 0, "ammo": 0}
		r.position = Vector3(side * 0.45, 0, -3.3)
		r.facing = Vector3.FORWARD
		wagon.add_child(r)
		_porters.append(r)


func _wagon_target() -> Vector3:
	var right := line_forward.cross(Vector3.UP).normalized()
	var wp: Array = Company.wagon_plan
	return line_anchor + right * float(wp[0]) + line_forward * float(wp[1])


func _update_wagon(delta: float) -> void:
	if wagon == null:
		return
	var to := _wagon_target() - wagon.position
	to.y = 0.0
	var looted_now := looters() > 0
	var moving := to.length() > 0.6 and not looted_now
	if moving:
		var step := minf(to.length(), WAGON_SPEED * delta)
		wagon.position += to.normalized() * step
		var want := atan2(-to.x, -to.z)
		wagon.rotation.y = lerp_angle(wagon.rotation.y, want, 1.0 - exp(-3.0 * delta))
	for r in _porters:
		r.anim = "block" if looted_now else ("walk" if moving else "idle")
		r.move_speed = WAGON_SPEED if moving else 0.0
		r.facing = -wagon.global_transform.basis.z


## A looter is cut down: what he was carrying goes back in the wagon.
func recover_loot(who) -> void:
	wagon_looted = maxf(0.0, wagon_looted - float(who.carried))
	who.carried = 0.0
	if wagon_looted <= 0.0005 and _loot_told:
		hud.show_message("The wagon is ours again!", 1.5)


func wagon_open() -> bool:
	return wagon != null and wagon_looted < LOOT_MAX


var _looting_now := 0
var _looting_prev := 0


func looters() -> int:
	return _looting_prev


var rations_spoiled := 0 # eaten by looters before they were cut down


## A lizard rummaging in the wagon (called every physics frame per looter).
## What he grabs stays in his arms: kill him and it comes back, except the
## food he'd already started on (a ration or two).
func loot_tick(delta: float, who) -> void:
	_looting_now += 1
	var grab := minf(LOOT_RATE * delta, LOOT_MAX - wagon_looted)
	if grab <= 0.0:
		return
	wagon_looted += grab
	who.carried += grab


## A looter eats a ration from the wagon: that one's gone, whatever happens.
func eat_ration(who) -> void:
	if rations_left() <= 0:
		return
	rations_spoiled += 1
	who.eaten += 1
	spawn_puff(who.global_position + Vector3.UP * 1.4 - who.facing * -0.5, Color(0.7, 0.6, 0.4), 0.25)
	play_sound("thud", who.global_position + Vector3.UP * 1.4, -16.0)


func rations_left() -> int:
	return (int(Company.stores.get("rations", 0)) if Company.active else 40) - rations_spoiled
	if not _loot_told:
		_loot_told = true
		hud.show_message("They're at the wagon! Lizards are looting the stores!", 2.5)


# ---------------------------------------------------------------- spatial grid
# Every physics frame the units are sorted into 4 m cells, so "who is near
# me?" only looks at neighbouring cells instead of every unit on the field.
# This is what lets the crowd scale to hundreds of units.

const CELL := 4.0

var _grid_e := {} # Vector2i -> Array of [unit, position]
var _grid_s := {}


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _rebuild_grid() -> void:
	_grid_e.clear()
	_grid_s.clear()
	for e in enemies:
		var p: Vector3 = e.global_position
		var c := _cell(p)
		if not _grid_e.has(c):
			_grid_e[c] = []
		_grid_e[c].append([e, p])
	for group in [soldiers, allies]:
		for so in group:
			var p2: Vector3 = so.global_position
			var c2 := _cell(p2)
			if not _grid_s.has(c2):
				_grid_s[c2] = []
			_grid_s[c2].append([so, p2])


func _grid_for(group: Array) -> Dictionary:
	return _grid_e if group == enemies else _grid_s


## Push away from neighbours closer than `radius` (radius <= CELL).
func separation(unit: Node3D, group: Array, radius: float) -> Vector3:
	var grid := _grid_for(group)
	var push := Vector3.ZERO
	var p := unit.global_position
	var c := _cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var bucket = grid.get(Vector2i(c.x + dx, c.y + dz))
			if bucket == null:
				continue
			for entry in bucket:
				if entry[0] == unit:
					continue
				var d: Vector3 = p - entry[1]
				d.y = 0.0
				var l := d.length()
				if l < radius and l > 0.001:
					push += d / l * (radius - l) / radius
	return push


## Every unit (both sides) in the cells around the segment a->b, as
## [unit, position] pairs. Projectiles sweep these instead of the whole field.
func units_near_segment(a: Vector3, b: Vector3) -> Array:
	var out: Array = []
	var ca := _cell(a)
	var cb := _cell(b)
	for x in range(mini(ca.x, cb.x) - 1, maxi(ca.x, cb.x) + 2):
		for z in range(mini(ca.y, cb.y) - 1, maxi(ca.y, cb.y) + 2):
			var c := Vector2i(x, z)
			var be = _grid_e.get(c)
			if be != null:
				out.append_array(be)
			var bs = _grid_s.get(c)
			if bs != null:
				out.append_array(bs)
	return out


## Nearest unit in a grid within max_dist (searches only the cells needed).
func _nearest_in(grid: Dictionary, from: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	var c := _cell(from)
	var rings := ceili(max_dist / CELL)
	for dx in range(-rings, rings + 1):
		for dz in range(-rings, rings + 1):
			var bucket = grid.get(Vector2i(c.x + dx, c.y + dz))
			if bucket == null:
				continue
			for entry in bucket:
				var d: float = from.distance_to(entry[1])
				if d < best_d:
					best_d = d
					best = entry[0]
	return best


## Nearest unit in a grid at any range: check every bucket once.
func _nearest_any(grid: Dictionary, from: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for bucket in grid.values():
		for entry in bucket:
			var d: float = from.distance_to(entry[1])
			if d < best_d:
				best_d = d
				best = entry[0]
	return best


func nearest_enemy(from: Vector3, max_dist: float) -> Node3D:
	if max_dist <= 16.0:
		return _nearest_in(_grid_e, from, max_dist)
	return _nearest_any(_grid_e, from, max_dist)


func nearest_friendly(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	if player.alive:
		best = player
		best_d = from.distance_to(player.global_position)
	# Look close first; only scan everyone if nobody is within 16 m.
	var near := _nearest_in(_grid_s, from, minf(best_d, 16.0))
	if near != null:
		return near
	if best_d <= 16.0:
		return best
	var far := _nearest_any(_grid_s, from, best_d)
	return far if far != null else best


func on_soldier_died(s) -> void:
	if s.ally:
		allies.erase(s)
		if s == captain:
			_captain_down()
		return
	soldiers.erase(s)
	_reassign_slots()
	if soldiers.size() == 0:
		hud.show_message("Your company is gone.", 2.5)
	elif s.record != null:
		hud.show_message("%s is down! Close ranks!" % s.display_name, 1.8)
	else:
		hud.show_message("Man down! Close ranks!", 1.5)


## An allied man made it off the field.
func on_ally_escaped(s) -> void:
	allies.erase(s)
	s.queue_free()


func on_out_of_ammo(s) -> void:
	if s.record != null:
		hud.show_message("%s is out of cartridges!" % s.display_name, 1.8)


## Something for a man to do after the fight: a fallen comrade to tend
## (first), or a dead lizard to search. Returns {"pos", "what"} or {}.
func victory_task(s) -> Dictionary:
	var best := {}
	var bd := INF
	for o in _all_men:
		if o.alive or _claimed.has(o):
			continue
		var d: float = s.global_position.distance_to(o.global_position)
		if d < bd:
			bd = d
			best = {"pos": o.global_position, "what": "tend", "key": o}
	if best.is_empty():
		for i in lizard_corpses.size():
			if _claimed.has(i):
				continue
			var d2: float = s.global_position.distance_to(lizard_corpses[i])
			if d2 < bd and d2 < 60.0:
				bd = d2
				best = {"pos": lizard_corpses[i], "what": "kneel", "key": i}
	if not best.is_empty():
		_claimed[best["key"]] = s
	return best


func on_enemy_died(e) -> void:
	enemies.erase(e)
	slain += 1


## Campaign: report the battle to the company (once) and offer the way out.
func _end_battle(won: bool) -> void:
	game_state = "won" if won else "lost"
	if Company.active and not _reported:
		_reported = true
		var men := {}
		for s in _all_men:
			if s.record == null:
				continue
			men[int(s.record["id"])] = {"kills": s.kills, "ammo_used": s.ammo_used,
				"status": "fit" if s.alive else s.down_status}
		Company.apply_battle({"won": won, "slain": slain, "officer_kills": player.kills, "men": men,
			"prologue": prologue, "wagon_looted": wagon_looted, "rations_spoiled": rations_spoiled,
			"enemy": "lizards"})
	hud.show_restart()


## Leave the field for the aftermath screen (campaign) or replay (otherwise).
func finish() -> void:
	if Company.active:
		get_tree().change_scene_to_file(AFTERMATH)
	else:
		restart()


# ---------------------------------------------------------------- loop

func _physics_process(_delta: float) -> void:
	# The battle node runs before its children, so units see a fresh grid.
	_rebuild_grid()
	_looting_prev = _looting_now
	_looting_now = 0
	if order != Order.HOLD and player.alive:
		var p: Vector3 = player.global_position
		var pf := _player_forward()
		if rad_to_deg(pf.angle_to(line_forward)) > REALIGN_ANGLE:
			line_forward = pf
			line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE
			_reassign_slots()
		else:
			line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE
	_update_wagon(_delta)


func _process(delta: float) -> void:
	if victory:
		victory_t += delta
	if Input.is_action_just_pressed("volley"):
		order_volley()
	if Input.is_action_just_pressed("order_follow"):
		order_follow()
	if Input.is_action_just_pressed("order_hold"):
		order_hold()
	if Input.is_action_just_pressed("order_charge"):
		order_charge()
	if Input.is_action_just_pressed("toggle_fire_mode"):
		toggle_fire_mode()

	_update_lines(delta)
	if prologue:
		_prologue_process(delta)
	match game_state:
		"starting", "between":
			state_timer -= delta
			if state_timer <= 0.0:
				_start_wave()
		"fighting":
			if prologue:
				# The story decides how this ends; waves just keep it coming.
				if enemies.is_empty() and story_phase == "line" and wave < waves.size():
					game_state = "between"
					state_timer = 5.0
			elif enemies.is_empty():
				if wave >= waves.size():
					hud.show_message("Victory! The field is ours.", 9999.0)
					victory = true
					_end_battle(true)
				else:
					game_state = "between"
					state_timer = 7.0
					hud.show_message("They falter! More are coming. Reload and dress the line.", 4.0)

	if _autotest:
		_run_autotest(delta)


func _start_wave() -> void:
	wave += 1
	game_state = "fighting"
	_phase_t = 0.0
	var count: int = waves[wave - 1]
	var right := line_forward.cross(Vector3.UP).normalized()
	var centre := line_anchor + line_forward * SPAWN_DISTANCE
	for i in count:
		var l = LizardScript.new()
		l.battle = self
		l.frames = lizard_frames
		var spread := 45.0 if Settings.stress else (40.0 if prologue else 22.0)
		var pos := centre + right * randf_range(-spread, spread) + line_forward * randf_range(0.0, spread * 0.7)
		l.position = Vector3(pos.x, 0, pos.z)
		enemies.append(l)
		add_child(l)
	if prologue:
		hud.show_message("Here they come!" if wave == 1 else "The second wave! Hold the line!", 2.5)
	elif wave == 1:
		hud.show_message("Here they come: %d lizardmen!" % count, 2.5)
	else:
		hud.show_message("Another %d coming!" % count, 2.5)
	if _autotest:
		print("wave ", wave, " start: soldiers ", soldiers.size(), " player hp ", player.hp)


# ---------------------------------------------------------------- prologue
# Wreck Beach (names in lore.gd). The regiment is entrenched on the beach
# where the ship broke up: your company in the centre behind the earthworks,
# a company either side, four guns in the embrasures, the sea at your backs.
# The Major gives the orders. The waves double as the tutorial: each beat
# shows a hint for the controls it needs (see _tutorial). In the second wave
# a javelin brings the Major down; you go to him, he hands you the company
# and dies, the left breaks, the guns are overrun, and you lead what's left
# along the beach to the cliff path and into the unknown land.

const GUN_X := [-37.0, -15.5, 15.5, 37.0]
const GUN_Z := 6.8
const WORKS_Z := 5.0 # the earthworks' crest
const GUN_RELOAD := 11.0
const ROUNDSHOT_SPEED := 170.0
const CANISTER_RANGE := 28.0

var _guns: Array = [] # {"node", "barrel", "cd", "silent"}
var _hints := {} # tutorial beats already shown


func _setup_prologue() -> void:
	_commanding = false
	story_phase = "line"
	order = Order.HOLD
	var right := line_forward.cross(Vector3.UP).normalized()
	var half := (soldiers.size() * 0.5 + 0.5) * LINE_SPACING
	var ally_half := (ALLY_COMPANY - 1) * 0.5 * LINE_SPACING
	for side in [-1.0, 1.0]:
		var centre: Vector3 = line_anchor + right * side * (half + 4.0 + ally_half)
		for i in ALLY_COMPANY:
			var s = SoldierScript.new()
			s.battle = self
			s.frames = soldier_frames
			s.ally = true
			s.ally_forward = line_forward
			s.ally_slot = centre + right * (i - (ALLY_COMPANY - 1) * 0.5) * LINE_SPACING
			s.position = s.ally_slot
			allies.append(s)
			add_child(s)
	captain = SoldierScript.new()
	captain.battle = self
	captain.frames = soldier_frames
	captain.ally = true
	captain.rig_look = "officer"
	captain.display_name = Lore.COMMANDER
	captain.ammo = 0
	captain.loaded = false
	captain.invulnerable = true
	captain.ally_forward = line_forward
	captain.ally_slot = line_anchor - line_forward * 2.6 + right * 0.8
	captain.position = captain.ally_slot
	allies.append(captain)
	add_child(captain)
	for x in GUN_X:
		var g := Props.cannon()
		g.position = Vector3(x, 0, GUN_Z)
		add_child(g)
		_guns.append({"node": g, "barrel": g.get_node("barrel"), "cd": randf_range(1.0, 4.0), "silent": false})


## The beach instead of the open field: sand, the sea behind, the wreck on
## its rocks, the earthworks, the forest ahead and the cliff path to the
## right, where the retreat goes.
func _build_beach() -> void:
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 80)
	pm.material = Props._mat(Props.SAND)
	sand.mesh = pm
	sand.position = Vector3(0, 0.01, 0)
	add_child(sand)
	var sea := Props.sea(520.0, 0.12, 0.6)
	sea.position = Vector3(0, -0.25, 300)
	add_child(sea)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var wreck := Props.ship()
	wreck.position = Vector3(-25, -1.2, 130)
	wreck.rotation = Vector3(-0.1, 0.5, 0.38)
	(wreck.get_node("main_mast") as Node3D).rotation.x = 1.25
	(wreck.get_node("fore_mast") as Node3D).rotation.z = -0.5
	add_child(wreck)
	add_child(Props.rocks(Vector3(-19, -1.5, 116), 7, 3.5, rng))
	var works := Props.earthwork(80.0, GUN_X)
	works.position = Vector3(0, 0, WORKS_Z)
	add_child(works)
	# Cliffs along the right end of the beach, with the path between them.
	for i in 14:
		var z := -60.0 + i * 7.0
		if absf(z - RETREAT_POINT.z) < 9.0:
			continue
		add_child(Props.rocks(Vector3(RETREAT_POINT.x + rng.randf_range(2, 8), 0, z), 4, 4.0, rng))
	# The forest: tall, dark, unfamiliar. Ahead of the line and past the cliffs.
	var spots: Array = []
	for i in 160:
		spots.append(Vector3(rng.randf_range(-200, 200), 0, rng.randf_range(-75, -150)))
	for i in 70:
		spots.append(Vector3(rng.randf_range(RETREAT_POINT.x + 10, RETREAT_POINT.x + 90), 0, rng.randf_range(-60, 45)))
	_forest(spots, rng)
	# The path's marker: the regiment's colour, planted where the path begins.
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = 4.5
	pole.mesh = cm
	pole.position = RETREAT_POINT + Vector3(0, 2.25, 0)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.03, 1.3, 2.0)
	fm.material = Props._mat(Color(0.7, 0.1, 0.08))
	flag.mesh = fm
	flag.position = RETREAT_POINT + Vector3(0, 3.85, 1.02)
	add_child(flag)


## Strange trees: tall bare trunks and wide teal crowns (MultiMesh: 2 draws).
func _forest(spots: Array, rng: RandomNumberGenerator) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.4
	trunk.height = 1.0
	trunk.material = Props._mat(Color(0.26, 0.2, 0.18))
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 1.0
	crown.radial_segments = 8
	crown.rings = 4
	crown.material = Props._mat(Color(0.1, 0.25, 0.22))
	var mt := MultiMesh.new()
	mt.transform_format = MultiMesh.TRANSFORM_3D
	mt.mesh = trunk
	mt.instance_count = spots.size()
	var mc := MultiMesh.new()
	mc.transform_format = MultiMesh.TRANSFORM_3D
	mc.mesh = crown
	mc.instance_count = spots.size()
	for i in spots.size():
		var p: Vector3 = spots[i]
		var h := rng.randf_range(8.0, 16.0)
		var w := rng.randf_range(2.5, 4.5)
		mt.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, h, 1)), p + Vector3(0, h * 0.5, 0)))
		mc.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(w, w * 0.45, w)), p + Vector3(0, h, 0)))
	for mm in [mt, mc]:
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		add_child(inst)


## Lizards wading over the earthworks are slowed (unit.gd asks).
func ground_speed(pos: Vector3) -> float:
	if prologue and absf(pos.z - WORKS_Z) < 1.6 and absf(pos.x) < 40.0:
		for gx in GUN_X:
			if absf(pos.x - gx) < 1.4:
				return 1.0 # the embrasures are open
		return 0.4
	return 1.0


## The guns: round shot at range, canister when they come close. A gun with
## a lizard on it is overrun and falls silent.
func _update_guns(delta: float) -> void:
	for g in _guns:
		if g["silent"]:
			continue
		var node: Node3D = g["node"]
		var at := node.global_position
		var close := nearest_enemy(at, 3.5)
		if close != null:
			g["silent"] = true
			hud.show_message("A gun is overrun!", 1.5)
			continue
		g["cd"] = float(g["cd"]) - delta
		if float(g["cd"]) > 0.0:
			continue
		var tgt := nearest_enemy(at, 110.0)
		if tgt == null:
			continue
		var to: Vector3 = tgt.global_position - at
		if to.dot(line_forward) < to.length() * 0.6:
			continue # only what's in front of the embrasure
		g["cd"] = GUN_RELOAD * randf_range(0.9, 1.2)
		_fire_gun(g, tgt)


func _fire_gun(g: Dictionary, tgt: Node3D) -> void:
	var barrel: Node3D = g["barrel"]
	var node: Node3D = g["node"]
	var aim: Vector3 = tgt.global_position + Vector3.UP * 1.0
	var flat := aim - node.global_position
	flat.y = 0.0
	node.rotation.y = atan2(-flat.x, -flat.z)
	var muzzle: Vector3 = barrel.global_transform * Vector3(0, 0, -1.85)
	var d := muzzle.distance_to(aim)
	if d < CANISTER_RANGE:
		for i in 12:
			var v: Vector3 = projectiles.spread_dir(aim - muzzle, 0.1) * 260.0
			projectiles.fire("canister", muzzle, v, null)
	else:
		var tf := d / ROUNDSHOT_SPEED
		var v2 := (aim - muzzle).normalized() * ROUNDSHOT_SPEED + Vector3.UP * 0.5 * 9.8 * tf
		projectiles.fire("roundshot", muzzle, v2, null)
	play_sound("cannon", muzzle, 6.0)
	spawn_flash(muzzle, 3.0)
	for i in 3:
		spawn_smoke(muzzle + Vector3(randf_range(-0.6, 0.6), randf_range(0, 0.6), randf_range(-1.2, 0.2)), 2.4)
	var tw := barrel.create_tween()
	tw.tween_property(barrel, "position:z", 0.45, 0.08)
	tw.tween_property(barrel, "position:z", 0.0, 1.2)
	if player.alive:
		player.shake(clampf(0.5 - player.global_position.distance_to(muzzle) / 60.0, 0.0, 0.5))


## The tutorial: each beat of the battle shows the controls it needs, once.
func _tutorial() -> void:
	if story_phase == "line" and wave == 0:
		_hint("move", "MOVE: drag on the left of the screen.  LOOK: drag on the right.  Walk the earthworks while the guns are readied.", 11.0)
	if wave >= 1 and story_phase == "line":
		_hint("fire", "FIRE: tap to shoot; keep your thumb down and drag to aim.  AIM: sight down the barrel.  Reloading takes a few seconds; the Major calls the company's volleys.", 12.0)
	if not _hints.has("melee") and player.alive and nearest_enemy(player.global_position, 14.0) != null:
		_hint("melee", "BAYONET: fix it for close work. OVER, LEFT, RIGHT, THRUST strike from that side: hold to charge, release to strike.  BLOCK when one rears up glowing.", 12.0)
	if wave >= 2 and story_phase == "line":
		_hint("grenade", "GRENADE: lob one into a crowd 10 to 20 m out. Mind your own men.", 8.0)
	if story_phase == "captain_down":
		_hint("major", "Go to the Major: follow the gold marker.", 8.0)
	if story_phase == "retreat":
		_hint("orders", "You command now.  FOLLOW: the line moves with you.  HOLD: it stands where you look.  CHARGE: every man picks his fight.  VOLLEY!: every loaded musket fires.  Lead them to the cliff path.", 14.0)


func _hint(id: String, text: String, seconds: float) -> void:
	if _hints.has(id):
		return
	_hints[id] = true
	hud.show_hint(text, seconds)


## Queue a line of dialogue (shown as a subtitle); `then` runs when it ends.
func say(speaker: String, text: String, seconds: float, then = null) -> void:
	_lines.append([speaker, text, seconds, then])


func _update_lines(delta: float) -> void:
	if _line_t > 0.0:
		_line_t -= delta
		if _line_t > 0.0:
			return
		var done: Array = _lines.pop_front()
		if done[3] != null:
			(done[3] as Callable).call()
	if not _lines.is_empty() and _line_t <= 0.0:
		var l: Array = _lines[0]
		_line_t = float(l[2])
		hud.show_story(l[0], l[1], l[2])


func _prologue_process(delta: float) -> void:
	_phase_t += delta
	_volley_cd -= delta
	_tutorial()
	if story_phase in ["line", "captain_down"]:
		_update_guns(delta)
	match story_phase:
		"line":
			# The Major's fire discipline: volley when most are loaded and the
			# enemy is close enough to hit.
			var near := nearest_enemy(line_anchor, 42.0)
			if near != null and _volley_cd <= 0.0 and loaded_count() >= ceili(soldiers.size() * 0.6):
				_volley_cd = 3.5
				hud.show_message("Harrow: Present... FIRE!", 1.2)
				_volley()
			if wave == 1 and game_state == "fighting" and _phase_t > 40.0:
				_start_wave() # the second wave won't wait for the first to die
			if wave == 2 and not _javelin_done:
				var close := nearest_enemy(captain.global_position, 30.0)
				if close != null or _phase_t > 16.0:
					_throw_at_captain(close)
		"captain_down":
			if captain != null and not _heard_captain:
				objective = {"label": "THE MAJOR", "pos": captain.global_position}
			if not _heard_captain and player.alive:
				var d: float = player.global_position.distance_to(captain.global_position)
				if d < 2.6:
					_heard_captain = true
					objective = {}
					_lines.clear()
					_line_t = 0.0
					say(Lore.COMMANDER, "Ensign... the left's gone. The beach is lost.", 4.0)
					say(Lore.COMMANDER, "The company is yours, Captain. Take them up the cliff path, inland. Keep them alive.", 5.5,
						func(): _commanding = true)
					say(Lore.COMMANDER, "Find the stores... they'll have taken the stores...", 4.0)
					say("", "%s is dead. You command the company." % Lore.COMMANDER_SHORT, 3.5, _begin_retreat)
				elif _phase_t > 22.0:
					_heard_captain = true
					objective = {}
					say(_sergeant_name(), "He's gone, sir! The Major's dead! You're in command. Get us out of here!",
						4.5, _begin_retreat)
		"retreat":
			objective = {"label": "THE CLIFF PATH", "pos": RETREAT_POINT, "height": 5.4}
			_wave_t -= delta
			if _wave_t <= 0.0:
				_wave_t = RETREAT_EVERY
				_spawn_pursuit(RETREAT_WAVE)
			if player.alive and player.global_position.distance_to(RETREAT_POINT) < 8.0:
				story_phase = "escaped"
				objective = {}
				hud.show_message("Up the cliff path and into the fog. They don't follow.", 9999.0)
				_end_battle(true)


## A lizard skirmisher's javelin, aimed to land on the Major. It flies over
## the line (it can only strike him) and he goes down.
func _throw_at_captain(thrower: Node3D) -> void:
	_javelin_done = true
	var from: Vector3
	if thrower != null:
		from = thrower.global_position + Vector3.UP * 1.9
	else:
		from = captain.global_position + line_forward * 32.0 + Vector3.UP * 1.6
	var to: Vector3 = captain.global_position + Vector3.UP * 1.3
	var flight := clampf(from.distance_to(to) / 17.0, 0.9, 2.2)
	var v := (to - from) / flight + Vector3.UP * 0.5 * 9.8 * flight
	captain.invulnerable = false
	captain.hp = 1.0
	projectiles.fire("javelin", from, v, thrower, captain)
	# Should the javelin somehow miss, he falls all the same.
	get_tree().create_timer(flight + 0.3).timeout.connect(func():
		if captain.alive:
			captain.take_shot(999.0, thrower))


func _captain_down() -> void:
	story_phase = "captain_down"
	_phase_t = 0.0
	hud.show_message("%s is down!" % Lore.COMMANDER_SHORT, 3.0)
	say(_sergeant_name(), "The Major's hit! Ensign, to the Major!", 4.0)
	# The company on the left breaks and runs for the path.
	var right := line_forward.cross(Vector3.UP).normalized()
	for s in allies:
		if s.alive and (s.global_position - line_anchor).dot(right) < 0.0:
			s.routing = true
			s.rout_to = RETREAT_POINT + Vector3(20, 0, randf_range(-3, 3))
	get_tree().create_timer(3.5).timeout.connect(func():
		if story_phase == "captain_down":
			hud.show_message("The left is breaking! They're over the earthworks!", 3.0)
			_spawn_flank(6))


func _begin_retreat() -> void:
	story_phase = "retreat"
	_commanding = true
	order = Order.FOLLOW
	_snap_line_to_player()
	_wave_t = 2.0
	for g in _guns:
		g["silent"] = true
	hud.show_message("Leave the guns! Along the beach to the cliff path!", 4.0)
	# The right-hand company goes too.
	for s in allies:
		if s.alive and not s.routing:
			s.routing = true
			s.rout_to = RETREAT_POINT + Vector3(20, 0, randf_range(-3, 3))
	# The horde pours over the works on the left.
	_spawn_pursuit(10)


## More of the horde, close on your heels and through the broken left.
func _spawn_pursuit(count: int) -> void:
	var p: Vector3 = player.global_position
	for i in count:
		if i % 3 == 2:
			_spawn_lizard(Vector3(p.x - randf_range(35.0, 45.0), 0, p.z + randf_range(-15.0, 10.0)))
		else:
			# The enemy came from the forest (-Z); the pursuit comes from there too.
			_spawn_lizard(Vector3(p.x + randf_range(-30.0, 30.0), 0, p.z - randf_range(38.0, 50.0)))


## Lizardmen pouring round the left end of your line.
func _spawn_flank(count: int) -> void:
	var right := line_forward.cross(Vector3.UP).normalized()
	var left_end := line_anchor - right * ((soldiers.size() * 0.5 + 0.5) * LINE_SPACING + 6.0)
	for i in count:
		_spawn_lizard(left_end - right * randf_range(4.0, 16.0) + line_forward * randf_range(4.0, 22.0))


func _spawn_lizard(pos: Vector3) -> void:
	if enemies.size() >= MAX_ENEMIES:
		return
	var l = LizardScript.new()
	l.battle = self
	l.frames = lizard_frames
	l.position = Vector3(pos.x, 0, pos.z)
	enemies.append(l)
	add_child(l)


func _sergeant_name() -> String:
	var best = null
	for s in soldiers:
		if s.record != null and (best == null or int(s.record["xp"]) > int(best.record["xp"])):
			best = s
	return best.display_name if best != null else "A sergeant"


func _on_player_died() -> void:
	if _autotest:
		print("  player fell: phase %s, %.0f m from the path" % [story_phase, player.global_position.distance_to(RETREAT_POINT)])
	objective = {}
	if Company.active:
		hud.show_message("You fall. Your men carry you from the field.", 9999.0)
	else:
		hud.show_message("You have fallen.", 9999.0)
	_end_battle(false)


## Headless smoke test: `godot --headless -- --autotest` fires volleys and the
## player's musket on a timer so every code path runs without a human.
var _at_swing_t := 0.0
var _at_dir := 0
var _at_stats := {"swings": 0, "hits": 0, "blocks": 0, "shielded": 0, "grenades": 0}


func _run_autotest(delta: float) -> void:
	if _at_stats["swings"] == 0 and not player.melee_hit.is_connected(_at_on_hit):
		player.melee_hit.connect(_at_on_hit)
		player.blocked.connect(func(): _at_stats["blocks"] += 1)
		player.struck_shield.connect(func(): _at_stats["shielded"] += 1)
	_autotest_timer += delta
	if _autotest_timer > 1.5:
		_autotest_timer = 0.0
		order_volley()
		player.request_fire()
		if wave == 2 and not is_at_will():
			toggle_fire_mode()
		if wave == 3 and not is_charging():
			order_charge()

	# Grenade: lob one into a pack 12-20 m out (aim slightly up for range).
	var pack := nearest_enemy(player.global_position, 20.0)
	if pack != null and player.grenades > 0 and not player.is_throwing() \
			and pack.global_position.distance_to(player.global_position) > 12.0:
		var tp: Vector3 = pack.global_position - player.global_position
		player.rotation.y = atan2(-tp.x, -tp.z)
		player.pitch = 0.15
		player.throw_grenade()
		_at_stats["grenades"] += 1

	# Prologue: walk to the fallen captain, then lead the retreat.
	player.move_input = Vector2.ZERO
	var goal = null
	if story_phase == "captain_down" and not _heard_captain and captain != null:
		goal = captain.global_position
	elif story_phase == "retreat":
		goal = RETREAT_POINT
	if goal != null and player.alive and nearest_enemy(player.global_position, 3.0) == null:
		var tg: Vector3 = goal - player.global_position
		player.rotation.y = atan2(-tg.x, -tg.z)
		player.move_input = Vector2(0, -1)

	# Melee: face the nearest lizardman, bayonet when close, cycle all four blows.
	var near := nearest_enemy(player.global_position, 6.0)
	if near != null and player.alive:
		var to: Vector3 = near.global_position - player.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		if player.weapon == "musket":
			player.toggle_weapon()
		elif player.swing_phase == "idle":
			# Block if he's rearing up, otherwise attack.
			var rearing: bool = near.get("windup") >= 0.15
			player.set_block(rearing)
			if not rearing and player.begin_swing():
				_at_swing_t = 0.0
				_at_dir = (_at_dir + 1) % 4
				player.set_swing_dir(_at_dir)
				_at_stats["swings"] += 1
		elif player.swing_phase == "windup":
			_at_swing_t += delta
			if _at_swing_t > 0.35:
				player.release_swing()
	elif player.weapon == "melee" and player.swing_phase == "idle":
		player.set_block(false)
		player.toggle_weapon()

	if prologue and int(_autotest_timer * 0) == 0 and Engine.get_physics_frames() % 600 == 0:
		print("  t=%ds phase %s wave %d men %d allies %d enemies %d hp %d" % [
			Engine.get_physics_frames() / 60, story_phase, wave, soldiers.size(), allies.size(), enemies.size(), int(player.hp)])
	if game_state == "won" or game_state == "lost":
		print("AUTOTEST END: ", game_state, " wave ", wave, " soldiers ", soldiers.size(), " melee ", _at_stats)
		print("  shots: ", projectiles.stats, " slain ", slain, " wagon looted ", snappedf(wagon_looted, 0.01), " spoiled ", rations_spoiled)
		if Company.active and Company.battles < 4:
			# Campaign test: show the result, hire, march on, fight again.
			var r: Dictionary = Company.last_result
			print("  day %d money %d men %d fit %d | slain %d pay %d | fallen %s | wounded %s | promoted %s" % [
				Company.day, Company.money, Company.roster.size(), Company.fit_men().size(),
				r["slain"], r["pay"], r["fallen"], r["wounded"], r["promoted"]])
			while Company.can_hire() and Company.roster.size() < 8:
				Company.hire_recruit()
			while Company.can_buy("ammo") and int(Company.stores["ammo"]) < 100:
				Company.buy("ammo")
			while Company.can_buy("rations") and int(Company.stores["rations"]) < 40:
				Company.buy("rations")
			Company.resupply_all()
			# Every other battle the wagon goes out in front as bait.
			Company.wagon_plan = [0.0, 14.0] if Company.battles % 2 == 1 else [0.0, -12.0]
			print("  stores: ", Company.stores, " money ", Company.money)
			print("  march: ", Company.march_on())
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
			return
		get_tree().quit()


func _at_on_hit(count: int) -> void:
	_at_stats["hits"] += count


# ---------------------------------------------------------------- effects

func spawn_smoke(pos: Vector3, size_mult: float) -> void:
	var puff := Sprite3D.new()
	puff.texture = smoke_tex
	puff.pixel_size = 0.02 * size_mult
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.modulate = Color(0.78, 0.78, 0.76, 0.75)
	puff.position = pos
	add_child(puff)
	var tw := puff.create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3.ONE * 3.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(puff, "modulate:a", 0.0, 3.0).set_ease(Tween.EASE_IN)
	tw.tween_property(puff, "position:y", pos.y + 1.2, 3.0)
	tw.chain().tween_callback(puff.queue_free)


## A small coloured puff: dirt where a ball strikes the ground, blood on a hit.
func spawn_puff(pos: Vector3, color: Color, size: float) -> void:
	var puff := Sprite3D.new()
	puff.texture = smoke_tex
	puff.pixel_size = 0.02 * size
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.modulate = Color(color.r, color.g, color.b, 0.9)
	puff.position = pos
	add_child(puff)
	var tw := puff.create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3.ONE * 2.2, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(puff, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(puff.queue_free)


## A grenade going off: everyone near it is hurt (friend or foe), closer
## means worse; lizardmen are thrown back, and the blast shakes your view.
func explode(pos: Vector3, radius: float, kill_radius: float, shooter: Node3D) -> void:
	play_sound("boom", pos, 4.0)
	spawn_flash(pos + Vector3.UP * 0.4, 9.0)
	for i in 5:
		var off := Vector3(randf_range(-1, 1), randf_range(0.1, 1.0), randf_range(-1, 1)) * 1.2
		spawn_smoke(pos + off, randf_range(1.6, 2.6))
	spawn_puff(pos + Vector3.UP * 0.3, Color(0.35, 0.28, 0.2), 3.0)
	var victims: Array = []
	victims.append_array(enemies)
	victims.append_array(soldiers)
	victims.append_array(allies)
	if player.alive:
		victims.append(player)
	for u in victims:
		var to: Vector3 = u.global_position - pos
		to.y = 0.0
		var d := to.length()
		if d > radius:
			continue
		# Full damage inside the kill radius, falling off to the edge.
		var dmg := 120.0 if d <= kill_radius else lerpf(70.0, 15.0, (d - kill_radius) / (radius - kill_radius))
		if u == player:
			dmg *= 0.6
		u.take_shot(dmg, shooter)
		if u.alive and u.has_method("stagger"):
			u.stagger(to.normalized() * lerpf(7.0, 2.0, d / radius), 0.9)
	if player.alive:
		var pd: float = player.global_position.distance_to(pos)
		player.shake(clampf(1.2 - pd / 25.0, 0.0, 1.0))


func spawn_flash(pos: Vector3, size: float = 1.0) -> void:
	var f := Sprite3D.new()
	f.texture = smoke_tex
	f.pixel_size = 0.012 * size
	f.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	f.modulate = Color(1.0, 0.75, 0.3, 1.0)
	f.position = pos
	add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.1)
	tw.tween_callback(f.queue_free)


# ---------------------------------------------------------------- setup

func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("fire", KEY_SPACE)
	_add_key("volley", KEY_F)
	_add_key("switch_weapon", KEY_Q)
	_add_key("block", KEY_E)
	_add_key("toggle_view", KEY_V)
	_add_key("grenade", KEY_G)
	_add_key("aim", KEY_Z)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	if not InputMap.action_has_event("aim", rmb):
		InputMap.action_add_event("aim", rmb)
	_add_key("swing_up", KEY_UP)
	_add_key("swing_left", KEY_LEFT)
	_add_key("swing_right", KEY_RIGHT)
	_add_key("swing_down", KEY_DOWN)
	_add_key("order_follow", KEY_1)
	_add_key("order_charge", KEY_4)
	_add_key("order_hold", KEY_2)
	_add_key("toggle_fire_mode", KEY_3)


func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.8, 0.8, 0.76)
	sky_mat.ground_horizon_color = Color(0.55, 0.56, 0.48)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.25)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.76, 0.77, 0.73)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false # shadows are expensive on phones
	add_child(sun)

	# Ground: flat field with a noise texture so movement reads.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	add_child(ground)
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	ground.add_child(col)
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise
	var ramp := Gradient.new()
	# The ground matches where on the map the fight is (see _terrain_look).
	var look := _terrain_look()
	ramp.set_color(0, look["dark"])
	ramp.set_color(1, look["light"])
	env.fog_density = look["fog"]
	noise_tex.color_ramp = ramp
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_texture = noise_tex
	ground_mat.uv1_scale = Vector3(40, 40, 1)
	mesh.material_override = ground_mat
	ground.add_child(mesh)

	if prologue:
		env.fog_density = 0.009
		env.fog_light_color = Color(0.78, 0.8, 0.78)
		_build_beach()
	else:
		_scatter_trees()


## Ground colours, fog and trees for the map terrain the battle is fought on.
func _terrain_look() -> Dictionary:
	var tt := -1
	if Company.active and not Company.next_battle.is_empty():
		tt = int(Company.next_battle.get("terrain", -1))
	match tt:
		3: # forest: trees close all round
			return {"dark": Color(0.18, 0.28, 0.12), "light": Color(0.32, 0.4, 0.2), "fog": 0.009, "trees": 260, "near": 48.0}
		4: # hills
			return {"dark": Color(0.33, 0.35, 0.2), "light": Color(0.5, 0.48, 0.3), "fog": 0.005, "trees": 50, "near": 90.0}
		6: # swamp: dark mud, mist, dead trees
			return {"dark": Color(0.2, 0.22, 0.14), "light": Color(0.32, 0.33, 0.2), "fog": 0.014, "trees": 140, "near": 55.0}
		1: # beach
			return {"dark": Color(0.6, 0.54, 0.38), "light": Color(0.75, 0.68, 0.5), "fog": 0.006, "trees": 30, "near": 110.0}
	return {"dark": Color(0.24, 0.34, 0.15), "light": Color(0.42, 0.47, 0.24), "fog": 0.006, "trees": 90, "near": 95.0}


## Pines around the edges of the field, drawn with MultiMesh (2 draw calls total).
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1725
	var look := _terrain_look()
	var count: int = look["trees"]
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.25
	trunk.height = 2.0
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.13)
	trunk.material = trunk_mat
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.8
	crown.height = 5.0
	crown.radial_segments = 8
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.13, 0.27, 0.15)
	crown.material = crown_mat

	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk
	trunks.instance_count = count
	var crowns := MultiMesh.new()
	crowns.transform_format = MultiMesh.TRANSFORM_3D
	crowns.mesh = crown
	crowns.instance_count = count
	for i in count:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(float(look["near"]), 190.0)
		var s := rng.randf_range(0.8, 1.6)
		var pos := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var basis := Basis().scaled(Vector3(s, s, s))
		trunks.set_instance_transform(i, Transform3D(basis, pos + Vector3(0, 1.0 * s, 0)))
		crowns.set_instance_transform(i, Transform3D(basis, pos + Vector3(0, 4.2 * s, 0)))
	var t_inst := MultiMeshInstance3D.new()
	t_inst.multimesh = trunks
	add_child(t_inst)
	var c_inst := MultiMeshInstance3D.new()
	c_inst.multimesh = crowns
	add_child(c_inst)
