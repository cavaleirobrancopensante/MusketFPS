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


func _ready() -> void:
	_autotest = "--autotest" in OS.get_cmdline_user_args()
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
	_reassign_slots()
	for s in soldiers:
		s.position = get_slot_position(s.slot_index)
		add_child(s)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.battle = self
	hud.player = player
	layer.add_child(hud)
	if Company.active and Company.march_note != "":
		hud.show_message(Company.march_note, 6.0)
		state_timer = maxf(state_timer, 6.0)
	else:
		hud.show_message("Form the line! They're coming...", 4.5)


# ---------------------------------------------------------------- orders

func order_follow() -> void:
	order = Order.FOLLOW
	_snap_line_to_player()
	hud.show_message("Company — follow me!", 1.5)


## Break ranks: every man picks his own fight (see soldier.gd). With no
## enemies left they regroup on you as if following.
func order_charge() -> void:
	order = Order.CHARGE
	hud.show_message("CHARGE! At them, lads!", 1.5)


func order_hold() -> void:
	order = Order.HOLD
	_snap_line_to_player() # the line forms where you're looking, then stays
	hud.show_message("Company — halt! Hold here!", 1.5)


func toggle_fire_mode() -> void:
	if fire_mode == FireMode.ON_COMMAND:
		fire_mode = FireMode.AT_WILL
		hud.show_message("Fire at will!", 1.5)
	else:
		fire_mode = FireMode.ON_COMMAND
		hud.show_message("Hold your fire... wait for the order!", 1.5)


func order_volley() -> void:
	if loaded_count() == 0:
		hud.show_message("Nobody's loaded!", 1.0)
		return
	hud.show_message("PRESENT... FIRE!", 1.0)
	for s in soldiers:
		s.volley()


func wave_count() -> int:
	return waves.size()


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

func get_slot_position(index: int) -> Vector3:
	var n := soldiers.size()
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
	for i in soldiers.size():
		soldiers[i].slot_index = i


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
	for so in soldiers:
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
	soldiers.erase(s)
	_reassign_slots()
	if soldiers.size() == 0:
		hud.show_message("Your company is gone.", 2.5)
	elif s.record != null:
		hud.show_message("%s is down! Close ranks!" % s.display_name, 1.8)
	else:
		hud.show_message("Man down! Close ranks!", 1.5)


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
			men[int(s.record["id"])] = {"kills": s.kills,
				"status": "fit" if s.alive else s.down_status}
		Company.apply_battle({"won": won, "slain": slain, "officer_kills": player.kills, "men": men})
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
	if order != Order.HOLD and player.alive:
		var p: Vector3 = player.global_position
		var pf := _player_forward()
		if rad_to_deg(pf.angle_to(line_forward)) > REALIGN_ANGLE:
			line_forward = pf
			line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE
			_reassign_slots()
		else:
			line_anchor = Vector3(p.x, 0, p.z) + line_forward * LINE_DISTANCE


func _process(delta: float) -> void:
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

	match game_state:
		"starting", "between":
			state_timer -= delta
			if state_timer <= 0.0:
				_start_wave()
		"fighting":
			if enemies.is_empty():
				if wave >= waves.size():
					hud.show_message("Victory! The field is ours.", 9999.0)
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
	var count: int = waves[wave - 1]
	var right := line_forward.cross(Vector3.UP).normalized()
	var centre := line_anchor + line_forward * SPAWN_DISTANCE
	for i in count:
		var l = LizardScript.new()
		l.battle = self
		l.frames = lizard_frames
		var spread := 45.0 if Settings.stress else 22.0
		var pos := centre + right * randf_range(-spread, spread) + line_forward * randf_range(0.0, spread * 0.7)
		l.position = Vector3(pos.x, 0, pos.z)
		enemies.append(l)
		add_child(l)
	if wave == 1:
		hud.show_message("Here they come: %d lizardmen!" % count, 2.5)
	else:
		hud.show_message("Another %d coming!" % count, 2.5)
	if _autotest:
		print("wave ", wave, " start: soldiers ", soldiers.size(), " player hp ", player.hp)


func _on_player_died() -> void:
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

	if game_state == "won" or game_state == "lost":
		print("AUTOTEST END: ", game_state, " wave ", wave, " soldiers ", soldiers.size(), " melee ", _at_stats)
		print("  shots: ", projectiles.stats, " slain ", slain)
		if Company.active and Company.battles < 4:
			# Campaign test: show the result, hire, march on, fight again.
			var r: Dictionary = Company.last_result
			print("  day %d money %d men %d fit %d | slain %d pay %d | fallen %s | wounded %s | promoted %s" % [
				Company.day, Company.money, Company.roster.size(), Company.fit_men().size(),
				r["slain"], r["pay"], r["fallen"], r["wounded"], r["promoted"]])
			while Company.can_hire() and Company.roster.size() < 8:
				Company.hire_recruit()
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
	ramp.set_color(0, Color(0.24, 0.34, 0.15))
	ramp.set_color(1, Color(0.42, 0.47, 0.24))
	noise_tex.color_ramp = ramp
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_texture = noise_tex
	ground_mat.uv1_scale = Vector3(40, 40, 1)
	mesh.material_override = ground_mat
	ground.add_child(mesh)

	_scatter_trees()


## Pines around the edges of the field, drawn with MultiMesh (2 draw calls total).
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1725
	var count := 90
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
		var dist := rng.randf_range(95.0, 190.0)
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
