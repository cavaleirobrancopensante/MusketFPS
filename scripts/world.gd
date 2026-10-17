extends Node
## The campaign map's state and its living world, registered as the `World`
## autoload. The map scene (map.gd) only draws this and turns taps into
## orders; everything that happens lives here, so it can be tested headless.
##
## Time is Warband-style: the clock runs only while the party moves (or
## waits), at HOURS_PER_SEC. While it runs, every party on the map moves too,
## nests send out warbands, caravans travel, patrols hunt, and each midnight
## the company eats, drinks, heals and gets paid (Company.pass_day).
##
## Sight: what the party can see is worked out on the real heightmap, from
## its eye height, with forests blocking. High ground sees further, forest
## hides you (and blinds you). Everything you have ever seen stays mapped;
## parties are only shown while you can see them.

const Gen := preload("res://scripts/world_gen.gd")
const Lore := preload("res://scripts/lore.gd")
const Men := preload("res://scripts/men.gd")
const Events := preload("res://scripts/events.gd")

const HOURS_PER_SEC := 1.2 # game hours per real second while moving
const WAIT_HOURS_PER_SEC := 4.0
const CAMP_HOURS_PER_SEC := 7.0 # the night goes by quickly when you sleep
const NIGHT_PACE := 0.7 # marching in the dark
const EVENT_CHANCE := 0.09 # per hour on the march, once the cooldown is over
const BASE_SPEED := 2.5 # cells per hour on open ground (a cell is about half a league)
const SIGHT := 16.0 # cells, on flat open ground
const CONTACT := 1.1 # cells: close enough to meet

const T := Gen.T

signal day_passed(notes: PackedStringArray)
signal news(text: String)
signal encounter(party: Dictionary) # a hostile party has caught you
signal arrived(target: Dictionary) # {"kind": "settlement"/"party"/"cell", ...}
signal dusk # 18:00 on the march: make camp, or march on in the dark?
signal dawn # 06:00: camp is struck
signal event(ev: Dictionary) # something happened on the road (see events.gd)
signal scouts_back(report: Dictionary)

var gen # world_gen.gd, built from `seed`
var seed := 0
var is_ready := false # a world is generated (or loaded)
var hours := 8.0 # since the landing; day 1, 08:00
var pos := Vector2.ZERO # the party, in cells (floats)
var path: Array = [] # Vector2i cells still to walk
var goal := {} # what we're walking to: {"kind", "id"/"cell"}
var waiting := false
var camping := false # asleep until 06:00
var night_march_day := -1 # the day you chose to march on through the night
var scouts: Array = [] # out scouting: {"ids", "names", "target": [x, y], "back": hours, "far": bool}
var _dusk_pending := false # waiting for your answer at dusk
var _event_cd := 4.0 # hours of marching before the next event may happen
var _fight_t := 0.0
var events := Events.new()
var explored := PackedByteArray() # 1 once seen
var in_sight := PackedByteArray() # 1 in sight right now
var parties: Array = []
var next_party := 1
var places := {} # settlement id -> {"raided": hours until, "known": bool}
var grid: AStarGrid2D
var log: Array = [] # recent news
var _day_water := "" # best water passed today: "clean" > "foul" > ""
var _last_sight_cell := Vector2i(-999, -999)
var _vis_list: Array = [] # cells currently marked in_sight


# ---------------------------------------------------------------- setup

func new_world(s: int) -> void:
	seed = s
	_build()
	hours = 8.0
	pos = Vector2(gen.start) + Vector2(0.5, 0.5)
	path.clear()
	goal = {}
	parties.clear()
	next_party = 1
	places.clear()
	log.clear()
	for st in gen.settlements:
		places[int(st["id"])] = {"raided": 0.0, "known": false}
	# The world doesn't wait for you: warbands are already out, caravans on the roads.
	for i in 12:
		_spawn_tick(true)
	update_sight(true)
	save()


func _build() -> void:
	if _pre_gen != null and _pre_gen.seed == seed:
		gen = _pre_gen
	else:
		gen = Gen.new()
		gen.generate(seed)
	_pre_gen = null
	var n: int = Gen.SIZE * Gen.SIZE
	explored.resize(n)
	explored.fill(0)
	in_sight.resize(n)
	in_sight.fill(0)
	_vis_list.clear()
	_last_sight_cell = Vector2i(-999, -999)
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, Gen.SIZE, Gen.SIZE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in Gen.SIZE:
		for x in Gen.SIZE:
			var sp: float = gen.speed_at(x, y)
			if sp <= 0.0:
				grid.set_point_solid(Vector2i(x, y))
			else:
				grid.set_point_weight_scale(Vector2i(x, y), 1.0 / sp)
	is_ready = true


## Forget the current world (a new campaign makes a new one on the map).
func reset() -> void:
	is_ready = false
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))


func save_path() -> String:
	return "%s/world.json" % Settings.slot_dir()


func has_save() -> bool:
	return FileAccess.file_exists(save_path())


func save() -> void:
	if not is_ready:
		return
	var plist: Array = []
	for p in parties:
		var q: Dictionary = p.duplicate()
		q["path"] = (p["path"] as Array).map(func(c): return [c.x, c.y])
		plist.append(q)
	var data := {"seed": seed, "hours": hours, "pos": [pos.x, pos.y], "parties": plist,
		"next_party": next_party, "places": places, "log": log.slice(-20),
		"explored": Marshalls.raw_to_base64(explored.compress(FileAccess.COMPRESSION_DEFLATE)),
		"goal": goal, "path": path.map(func(c): return [c.x, c.y]), "camping": camping,
		"night_march_day": night_march_day, "scouts": scouts, "event_cd": _event_cd}
	DirAccess.make_dir_recursive_absolute(Settings.slot_dir())
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func load_world() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	seed = int(data["seed"])
	_build()
	hours = float(data["hours"])
	pos = Vector2(data["pos"][0], data["pos"][1])
	parties = data.get("parties", [])
	for p in parties:
		p["id"] = int(p["id"])
		p["size"] = int(p["size"])
		p["path"] = p.get("path", []).map(func(c): return Vector2i(int(c[0]), int(c[1])))
		p["home"] = int(p["home"])
		p["target"] = int(p["target"])
	next_party = int(data.get("next_party", 1))
	places.clear()
	var pl: Dictionary = data.get("places", {})
	for k in pl:
		places[int(k)] = pl[k]
	log = data.get("log", [])
	goal = data.get("goal", {})
	path = data.get("path", []).map(func(c): return Vector2i(int(c[0]), int(c[1])))
	camping = bool(data.get("camping", false))
	night_march_day = int(data.get("night_march_day", -1))
	scouts = data.get("scouts", [])
	_event_cd = float(data.get("event_cd", 4.0))
	var raw := Marshalls.base64_to_raw(String(data["explored"]))
	var dec := raw.decompress(Gen.SIZE * Gen.SIZE, FileAccess.COMPRESSION_DEFLATE)
	if dec.size() == explored.size():
		explored = dec
	update_sight(true)
	return true


## Make sure a world exists: load it, or (a new campaign) make one.
func ensure() -> void:
	if is_ready:
		return
	if not load_world():
		new_world(_pre_gen.seed if _pre_gen != null else randi() % 1000000)


var pending_rest := 0.0 # hours to rest, asked for in a town (map.gd starts it)
var _pre_gen = null # a land generated ahead by prebuild(), used by _build()


## Generate the land in stages for the loading screen (see map.gd), before
## ensure() puts the rest of the world on it. `report(fraction, text)`.
func prebuild(report: Callable) -> void:
	if is_ready:
		return
	var s := randi() % 1000000
	if has_save():
		var data = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
		if typeof(data) == TYPE_DICTIONARY:
			s = int(data["seed"])
	var g := Gen.new()
	await g.generate_staged(s, report)
	_pre_gen = g


func cell() -> Vector2i:
	return Vector2i(int(pos.x), int(pos.y))


func day() -> int:
	return 1 + int(hours / 24.0)


func clock() -> String:
	var hh := int(hours) % 24
	return "Day %d, %02d:%02d" % [day(), hh, int(fmod(hours, 1.0) * 60.0)]


func settlement(id: int) -> Dictionary:
	return gen.settlements[id]


func is_raided(id: int) -> bool:
	return float(places[id]["raided"]) > hours


# ---------------------------------------------------------------- nests

## A lizard nest's state (kept in places[id]): how many are inside, how much
## of the palisade still stands (1 = whole), whether it's been burned, and
## how many days you've had it under siege. Filled in the first time asked.
func nest(id: int) -> Dictionary:
	var pl: Dictionary = places[id]
	if not pl.has("garrison"):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("nest:%d:%d" % [seed, id])
		var big: bool = id == gen.stash_nest
		pl["garrison"] = rng.randi_range(46, 66) + (34 if big else 0)
		pl["max_garrison"] = int(pl["garrison"])
		pl["walls"] = 1.0
		pl["destroyed"] = false
		pl["siege_days"] = 0
	return pl


func nest_destroyed(id: int) -> bool:
	return bool(places[id].get("destroyed", false))


## A day of siege before nest `id`: hunger and your fire thin the garrison,
## the guns (if you have any) and your men tear at the stakes, and at night
## they may sally out. Returns {"lost", "walls", "sortie"} (sortie: how
## many came out, 0 if none; they're taken from the garrison).
func siege_day(id: int, guns: int) -> Dictionary:
	var n := nest(id)
	n["siege_days"] = int(n["siege_days"]) + 1
	var g := int(n["garrison"])
	var lost := int(round(g * 0.07)) + 2 + guns * 2
	var walls_before := float(n["walls"])
	n["walls"] = maxf(0.0, walls_before - 0.05 - 0.14 * guns)
	g = maxi(4, g - lost)
	var sortie := 0
	# Hungry and penned in, they come out at night more often as the days go by.
	if randf() < 0.3 + 0.08 * int(n["siege_days"]) and g > 12:
		sortie = int(round(g * randf_range(0.22, 0.38)))
		g -= sortie
	n["garrison"] = g
	return {"lost": lost, "walls": walls_before - float(n["walls"]), "sortie": sortie}


## After an assault (or a sortie) is fought: `killed` of them are dead; a
## won assault burns the nest.
func nest_fought(id: int, killed: int, won_assault: bool, returned := 0) -> void:
	var n := nest(id)
	n["garrison"] = maxi(0, int(n["garrison"]) - killed + returned)
	if won_assault:
		n["destroyed"] = true
		n["garrison"] = 0
		_tell("%s burns." % settlement(id)["name"], settlement(id))


## Lift the siege (you marched away): they recover from it.
func lift_siege(id: int) -> void:
	nest(id)["siege_days"] = 0


# ---------------------------------------------------------------- orders

## March to a cell. Returns false if there is no way there.
func go_to(target: Vector2i, what := {}) -> bool:
	var from := cell()
	if grid.is_point_solid(target):
		target = _nearest_open(target)
	var p := grid.get_id_path(from, target)
	if p.is_empty():
		return false
	path = Array(p).slice(1)
	goal = what if not what.is_empty() else {"kind": "cell", "cell": [target.x, target.y]}
	waiting = false
	return true


func stop() -> void:
	path.clear()
	goal = {}


func _nearest_open(c: Vector2i) -> Vector2i:
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if gen.inside(q.x, q.y) and not grid.is_point_solid(q):
					return q
	return c


func moving() -> bool:
	return not path.is_empty()


## The party's own pace: the men's fitness, slowed by the wounded and sick.
func party_pace() -> float:
	var men: Array = Company.roster
	if men.is_empty():
		return 1.0
	var fit := 0.0
	var slow := 0
	for m in men:
		fit += Men.attr(m, "fitness")
		if int(m["wounded_days"]) > 0 or int(m["sick"]) > 0:
			slow += 1
	fit /= men.size()
	var pace := 0.85 + 0.03 * (fit - 5.0)
	pace *= 1.0 - 0.25 * float(slow) / men.size() # carrying the wounded
	pace *= Company.Officer.march_mult() # your Pathfinding
	return clampf(pace, 0.5, 1.45)


func speed_here() -> float:
	var c := cell()
	return gen.speed_at(c.x, c.y)


# ---------------------------------------------------------------- time

## Advance the world by `dt` real seconds (called by the map each frame).
## Time only runs while the party moves or waits.
func tick(dt: float) -> void:
	if not is_ready or _dusk_pending:
		return
	if camping:
		advance(dt * CAMP_HOURS_PER_SEC)
	elif moving():
		advance(dt * HOURS_PER_SEC)
	elif waiting:
		advance(dt * WAIT_HOURS_PER_SEC)


## Time spent standing still (hunting, digging, climbing): the world moves
## on, the company doesn't.
func pass_hours(h: float) -> void:
	var keep := path.duplicate()
	var keep_goal := goal.duplicate()
	path.clear()
	goal = {}
	advance(h)
	path = keep
	goal = keep_goal


## A party appearing near the company (events), `dist` cells away.
func spawn_near(kind: String, faction: String, size: int, dist: float) -> Dictionary:
	var a := randf() * TAU
	var at := pos + Vector2(cos(a), sin(a)) * dist
	var c := Vector2i(clampi(int(at.x), 0, Gen.SIZE - 1), clampi(int(at.y), 0, Gen.SIZE - 1))
	if grid.is_point_solid(c):
		c = _nearest_open(c)
	var home := -1
	var best := INF
	for st in gen.settlements:
		var ok: bool = (st["kind"] == "nest") if faction == "lizards" else (st["faction"] == faction)
		var d := pos.distance_to(Vector2(st["x"], st["y"]))
		if ok and d < best:
			best = d
			home = int(st["id"])
	var p := _new_party(kind, faction, size, {"x": c.x, "y": c.y, "id": home})
	p["wait"] = 1.0
	return p


## Dusk answers.
func make_camp() -> void:
	_dusk_pending = false
	camping = true
	waiting = false


func march_through_night() -> void:
	_dusk_pending = false
	night_march_day = day()
	for m in Company.roster:
		Men.add_morale(m, -2) # tired, stumbling men


func is_night() -> bool:
	var hd := hours_of_day()
	return hd >= 18.0 or hd < 6.0


func _wake() -> void:
	camping = false
	if Company.active:
		for m in Company.roster:
			if int(m["hunger"]) == 0 and int(m["thirst"]) == 0:
				Men.add_morale(m, 1) # a night's sleep
	dawn.emit()


## Run the world `dh` game hours forward, in small steps.
func advance(dh: float) -> void:
	while dh > 0.0:
		var step := minf(dh, 0.25)
		dh -= step
		var day_before := day()
		var hd_before := hours_of_day()
		hours += step
		if camping:
			if hd_before < 6.0 and hours_of_day() >= 6.0:
				_wake()
		else:
			_walk(step)
		_note_water()
		_scouts_tick()
		if moving() and not camping:
			_event_cd -= step
			if _event_cd <= 0.0 and randf() < EVENT_CHANCE * step:
				var ev: Dictionary = events.pick(self)
				if not ev.is_empty():
					_event_cd = randf_range(5.0, 10.0)
					event.emit(ev)
					return
		for p in parties.duplicate():
			_party_tick(p, step)
		_fight_t -= step
		if _fight_t <= 0.0:
			_fight_t = 0.5
			_fights()
		if day() != day_before:
			_midnight()
		if _check_contact():
			return # stop the clock: something needs you
		# Dusk on the march: stop and ask.
		if moving() and not camping and hd_before < 18.0 and hours_of_day() >= 18.0 and night_march_day != day():
			_dusk_pending = true
			dusk.emit()
			return


func _walk(dh: float) -> void:
	var left := BASE_SPEED * party_pace() * dh * (NIGHT_PACE if is_night() else 1.0)
	while left > 0.0 and not path.is_empty():
		var nxt: Vector2i = path[0]
		var target := Vector2(nxt) + Vector2(0.5, 0.5)
		var sp: float = maxf(gen.speed_at(nxt.x, nxt.y), 0.1)
		var d := pos.distance_to(target)
		var can := left * sp
		if can >= d:
			pos = target
			left -= d / sp
			path.pop_front()
		else:
			pos += (target - pos) / d * can
			left = 0.0
	update_sight()
	# Walking into any settlement (inside its fence or walls, not just its
	# centre) is arriving there, whether or not you were heading for it.
	var inside := settlement_at(pos)
	if inside >= 0 and inside != _inside:
		_inside = inside
		goal = {}
		path.clear()
		_day_water = "clean"
		places[inside]["known"] = true
		arrived.emit({"kind": "settlement", "id": inside})
		return
	if inside < 0:
		_inside = -1
	if path.is_empty() and not goal.is_empty():
		var g := goal
		goal = {}
		if g["kind"] == "settlement":
			_day_water = "clean"
			places[int(g["id"])]["known"] = true
			_inside = int(g["id"])
		arrived.emit(g)


## How far a settlement's ground reaches, in cells (matches the models on the map).
const SETTLEMENT_REACH := {"village": 3.5, "town": 4.5, "city": 7.0, "hold": 3.5, "nest": 4.0}
var _inside := -1 # the settlement you're standing in (so it triggers once per visit)


## The field battle map for a fight here: a town or village close by, a
## river through the cell, woods, hills, or open ground.
func battle_map_here() -> String:
	var c := cell()
	var sid := settlement_at(pos)
	if sid < 0:
		for d in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			sid = settlement_at(pos + d)
			if sid >= 0:
				break
	if sid >= 0 and String(settlement(sid)["kind"]) in ["village", "town", "city"]:
		return "town"
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if gen.inside(c.x + dx, c.y + dy) and gen.river[Gen.idx(c.x + dx, c.y + dy)] != 0:
				return "river"
	match gen.t(c.x, c.y):
		T.FOREST, T.SWAMP:
			return "forest"
		T.HILLS, T.MOUNTAIN:
			return "hills"
	return "flat"


func settlement_at(p: Vector2) -> int:
	for st in gen.settlements:
		var r: float = SETTLEMENT_REACH.get(st["kind"], 3.5)
		if p.distance_to(Vector2(st["x"], st["y"]) + Vector2(0.5, 0.5)) <= r:
			return int(st["id"])
	return -1


## Rivers and lakes give clean water (unless you drink it in a swamp);
## swamp water is foul. The best water of the day fills the barrels.
func _note_water() -> void:
	if _day_water == "clean":
		return
	var c := cell()
	var here_swamp: bool = gen.t(c.x, c.y) == T.SWAMP
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var x := c.x + dx
			var y := c.y + dy
			if not gen.inside(x, y):
				continue
			var i: int = Gen.idx(x, y)
			if gen.river[i] != 0 or gen.terrain[i] == T.LAKE:
				_day_water = "foul" if here_swamp else "clean"
				if _day_water == "clean":
					return
			elif gen.terrain[i] == T.SWAMP:
				_day_water = "foul"


func _midnight() -> void:
	var notes: PackedStringArray = Company.pass_day(_day_water) if Company.active else PackedStringArray()
	# Nests not under siege fill up again, and mend their stakes.
	for st in gen.settlements:
		if st["kind"] == "nest" and not nest_destroyed(int(st["id"])):
			var n := nest(int(st["id"]))
			if int(n["siege_days"]) == 0:
				n["garrison"] = mini(int(n["max_garrison"]), int(n["garrison"]) + 3)
				n["walls"] = minf(1.0, float(n["walls"]) + 0.05)
	_day_water = ""
	_spawn_tick(false)
	day_passed.emit(notes)
	save()


# ---------------------------------------------------------------- trade

## The settlement you're at, if anyone there will sell to you: a known,
## unburned village, town, city or hold within a couple of cells. {} if
## you're out in the wilds (nobody to buy from).
func market_here() -> Dictionary:
	if not is_ready:
		return {}
	for st in gen.settlements:
		if st["kind"] == "nest" or is_raided(int(st["id"])):
			continue
		if pos.distance_to(Vector2(st["x"], st["y"]) + Vector2(0.5, 0.5)) < 2.5:
			return st
	return {}


# ---------------------------------------------------------------- scouts

const SCOUT_NEAR := 25.0
const SCOUT_FAR := 50.0


## Men who could go: fit, not already out; the fittest first, sergeants last.
func scout_candidates() -> Array:
	var men: Array = Company.fit_men().filter(func(m): return int(m["rank"]) < 3)
	men.sort_custom(func(a, b): return Men.attr(a, "fitness") > Men.attr(b, "fitness"))
	return men


## Send one man (near) or two (far) in a direction. They come back to the
## company wherever it is, with what they found, unless they don't.
func send_scouts(dir: Vector2, far: bool) -> Dictionary:
	var men := scout_candidates()
	var n := 2 if far else 1
	if men.size() < n + 2:
		return {}
	var dist := SCOUT_FAR if far else SCOUT_NEAR
	var tgt := pos + dir.normalized() * dist
	tgt = Vector2(clampf(tgt.x, 2, Gen.SIZE - 3), clampf(tgt.y, 2, Gen.SIZE - 3))
	# They ride as far as the land goes: back off from the sea.
	while tgt.distance_to(pos) > 4.0 and gen.t(int(tgt.x), int(tgt.y)) in [T.SEA, T.LAKE]:
		tgt = tgt.move_toward(pos, 2.0)
	var ids: Array = []
	var names: Array = []
	for m in men.slice(0, n):
		m["away"] = true
		ids.append(int(m["id"]))
		names.append(Company.surname_title(m))
	var out := {"ids": ids, "names": names, "target": [tgt.x, tgt.y], "far": far,
		"back": hours + dist * 2.0 / (BASE_SPEED * 0.9) + 3.0}
	scouts.append(out)
	Company.save()
	return out


func _scouts_tick() -> void:
	for sc in scouts.duplicate():
		if hours >= float(sc["back"]):
			scouts.erase(sc)
			scouts_back.emit(_scout_report(sc))


## What the scouts found, and whether they came back at all.
func _scout_report(sc: Dictionary) -> Dictionary:
	var tgt := Vector2(sc["target"][0], sc["target"][1])
	var tc := Vector2i(int(tgt.x), int(tgt.y))
	var risk := 0.06 + (0.06 if sc["far"] else 0.0)
	if gen.region[Gen.idx(tc.x, tc.y)] == 4:
		risk += 0.14 # the lizards' country
	for p in parties:
		if p["faction"] == "lizards" and tgt.distance_to(Vector2(p["x"], p["y"])) < 14.0:
			risk += 0.12
			break
	var men: Array = Company.roster.filter(func(m): return int(m["id"]) in sc["ids"])
	var fit := 5.0
	for m in men:
		fit = Men.attr(m, "fitness")
	risk = clampf((risk - 0.02 * (fit - 5.0)) * Company.Officer.scout_risk_mult(), 0.02, 0.6)
	var report := {"names": sc["names"], "lost": [], "found": [], "parties": [], "terrain": ""}
	for m in men:
		m.erase("away")
	if randf() < risk:
		# Lost: killed, or one comes back wounded with half a story.
		for m in men:
			if randf() < 0.7 or men.size() == 1:
				Company.fallen.append({"name": m["name"], "rank": Company.RANKS[int(m["rank"])], "day": Company.day,
					"battles": m["battles"], "kills": m["kills"], "cause": "lost scouting"})
				Company.roster.erase(m)
				report["lost"].append(Company.title(m))
			else:
				m["wounded_days"] = maxi(1, int(round(randi_range(3, 7) * Company.Officer.wound_mult())))
		if report["lost"].size() == men.size():
			Company.save()
			return report
	# What they saw: a wide circle round where they went, and the way there.
	_reveal(tgt, 24.0 if sc["far"] else 18.0)
	var steps := int(pos.distance_to(tgt) / 6.0)
	for k in steps:
		_reveal(pos.lerp(tgt, float(k) / maxf(1, steps)), 6.0)
	for st in gen.settlements:
		if tgt.distance_to(Vector2(st["x"], st["y"])) < 24.0:
			places[int(st["id"])]["known"] = true
			report["found"].append("%s (%s%s)" % [st["name"], st["kind"], ", raided" if is_raided(int(st["id"])) else ""])
	for p in parties:
		if tgt.distance_to(Vector2(p["x"], p["y"])) < 24.0:
			report["parties"].append(party_label(p, 1)) # (scouts at a distance: a rough count)
	var counts := {}
	for dy in range(-12, 13, 3):
		for dx in range(-12, 13, 3):
			if gen.inside(tc.x + dx, tc.y + dy):
				var tt: int = gen.t(tc.x + dx, tc.y + dy)
				counts[tt] = counts.get(tt, 0) + 1
	var most := -1
	for k in counts:
		if most < 0 or counts[k] > counts[most]:
			most = k
	report["terrain"] = Gen.T_NAMES[most].to_lower() if most >= 0 else ""
	Company.save()
	return report


## Mark land as explored (scouts, a climb to a high point).
func _reveal(center: Vector2, r: float) -> void:
	var ri := int(r)
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var x := int(center.x) + dx
			var y := int(center.y) + dy
			if gen.inside(x, y):
				explored[Gen.idx(x, y)] = 1
	for st in gen.settlements:
		if center.distance_to(Vector2(st["x"], st["y"])) < r:
			places[int(st["id"])]["known"] = true
	revealed.emit()


signal revealed # explored land changed outside normal sight


# ---------------------------------------------------------------- sight

## Which cells the party can see from here. Eye height from the terrain,
## forests block, high ground sees further.
func sight_radius() -> float:
	var c := cell()
	var tt: int = gen.t(c.x, c.y)
	var r := SIGHT
	if tt == T.HILLS:
		r += 8.0
	elif tt == T.MOUNTAIN:
		r += 14.0
	elif tt == T.FOREST or tt == T.SWAMP:
		r -= 6.0
	if hours_of_day() < 5.0 or hours_of_day() > 21.0:
		r *= 0.6 # night
	return r * Company.Officer.sight_mult()


func hours_of_day() -> float:
	return fmod(hours, 24.0)


func update_sight(force := false) -> void:
	var c := cell()
	if c == _last_sight_cell and not force:
		return
	_last_sight_cell = c
	for i in _vis_list:
		in_sight[i] = 0
	_vis_list.clear()
	var r := sight_radius()
	var ri := int(ceil(r))
	var eye: float = gen.h(c.x, c.y) + 0.02
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var x := c.x + dx
			var y := c.y + dy
			if not gen.inside(x, y):
				continue
			if _line_of_sight(c, Vector2i(x, y), eye):
				var i: int = Gen.idx(x, y)
				in_sight[i] = 1
				explored[i] = 1
				_vis_list.append(i)
	for st in gen.settlements:
		if in_sight[Gen.idx(st["x"], st["y"])] == 1:
			places[int(st["id"])]["known"] = true


## Walk the ray from the eye to the cell: anything rising above the line of
## sight (hills, forest canopy) hides what's behind it.
func _line_of_sight(a: Vector2i, b: Vector2i, eye: float) -> bool:
	var d := Vector2(b - a)
	var len := d.length()
	if len < 1.5:
		return true
	var target: float = gen.h(b.x, b.y) + 0.004
	var steps := int(len)
	for k in range(1, steps):
		var f := float(k) / len
		var x := a.x + int(round(d.x * f))
		var y := a.y + int(round(d.y * f))
		var i: int = Gen.idx(x, y)
		var ground: float = gen.height[i]
		if gen.terrain[i] == T.FOREST and k > 1:
			ground += 0.012 # the canopy
		if ground > lerpf(eye, target, f):
			return false
	return true


func can_see(p: Dictionary) -> bool:
	return in_sight[Gen.idx(int(p["x"]), int(p["y"]))] == 1


# ---------------------------------------------------------------- parties

const KINDS := {
	"warband": {"speed": 1.0, "name": "Lizard warband", "hostile": true},
	"patrol": {"speed": 0.9, "name": "Patrol", "hostile": false},
	"caravan": {"speed": 0.75, "name": "Caravan", "hostile": false},
	"villagers": {"speed": 0.7, "name": "Villagers", "hostile": false},
	"traders": {"speed": 0.8, "name": "Dwarf traders", "hostile": false},
	"hunters": {"speed": 1.05, "name": "Lizard hunting party", "hostile": true},
	"refugees": {"speed": 0.6, "name": "Refugees", "hostile": false},
	"deserters": {"speed": 0.85, "name": "Deserters", "hostile": false},
}


# ---------------------------------------------------------------- what you can tell about a party

const COMP_NAMES := {"liz_warrior": ["warrior", "warriors"], "liz_skirm": ["javelin thrower", "javelin throwers"],
	"liz_brute": ["brute", "brutes"], "liz_raptor": ["raptor rider", "raptor riders"],
	"pike": ["spearman", "spearmen"], "bow": ["archer", "archers"], "xbow": ["crossbowman", "crossbowmen"], "cav": ["horseman", "horsemen"]}
const COMP_ORDER := ["liz_warrior", "liz_skirm", "liz_brute", "liz_raptor", "pike", "xbow", "bow", "cav"]


## What a lizard party is made of (field.gd kinds -> numbers), worked out
## from its size and who it is, so it's the same every time you look.
## Warbands: mostly warriors, a quarter javelin throwers, brutes once it's
## big, raptor riders once it's bigger. Hunting parties: throwers and riders.
static func party_comp(p: Dictionary) -> Dictionary:
	var n := int(p["size"])
	var out := {}
	if p["kind"] == "hunters":
		var r := 1 if n >= 6 else 0
		var j := int(round((n - r) * 0.6))
		out = {"liz_skirm": j, "liz_raptor": r, "liz_warrior": n - r - j}
	elif p["kind"] == "warband":
		var brutes := n / 14
		var raptors := maxi(0, (n - 12) / 6)
		var jav := int(round(n * 0.25))
		var war := maxi(0, n - brutes - raptors - jav)
		out = {"liz_warrior": war, "liz_skirm": jav, "liz_brute": brutes, "liz_raptor": raptors}
	elif p["kind"] == "patrol":
		# A nation's soldiers (nobody here has gunpowder): spearmen, with
		# crossbows and archers, and a few horse once it's a proper column.
		var horse := n / 6 if n >= 12 else 0
		var xb := int(round(n * 0.25))
		var bows := int(round(n * 0.15))
		out = {"pike": n - horse - xb - bows, "xbow": xb, "bow": bows, "cav": horse}
	elif p["kind"] == "deserters":
		var bw := int(round(n * 0.35))
		out = {"pike": n - bw, "bow": bw}
	elif p["kind"] == "caravan":
		var g := maxi(2, n / 2) # (the guards; the rest are drovers)
		var xg := g / 3
		out = {"pike": g - xg, "xbow": xg}
	else:
		return {}
	for k in out.keys():
		if int(out[k]) <= 0:
			out.erase(k)
	return out


static func comp_text(comp: Dictionary, sep := ", ") -> String:
	var parts: PackedStringArray = []
	for k in COMP_ORDER:
		var c := int(comp.get(k, 0))
		if c > 0:
			parts.append("%d %s" % [c, COMP_NAMES[k][0 if c == 1 else 1]])
	return sep.join(parts)


## How much you can make out about a party `d` cells away (-1: from where
## you are now). Your Tactics reads a host; your Pathfinding gives you the
## eyes to see it from further off.
##   0  too far: something's there, no more ("?")
##   1  a rough count (the better your Tactics, the closer the guess)
##   2  the count
##   3  close, and with Tactics 3 or more: what they are
func intel_level(p: Dictionary, d := -1.0) -> int:
	if d < 0.0:
		d = pos.distance_to(Vector2(p["x"], p["y"]))
	var t := Company.Officer.skill("tactics")
	var s := sight_radius()
	if t >= 3 and d <= 1.0 + 0.35 * t:
		return 3
	if d <= s * 0.25 + 0.3 * t:
		return 2
	if d <= s * 0.6:
		return 1
	return 0


## A rough count that holds the real one: wider with less Tactics, and the
## same guess every time you look.
func rough_count(p: Dictionary) -> String:
	var n := int(p["size"])
	var e := clampf(0.55 - 0.045 * Company.Officer.skill("tactics"), 0.12, 0.55)
	var u := float(hash(int(p["id"]) * 7919) % 100) / 100.0
	var lo := maxi(1, int(floor(n * (1.0 - e * u))))
	var hi := maxi(lo + 1, int(ceil(n * (1.0 + e * (1.0 - u)))))
	return "%d–%d" % [lo, hi]


## The party's name with what you can tell about its numbers.
func party_label(p: Dictionary, level := -1) -> String:
	if level < 0:
		level = intel_level(p)
	var base := party_name(p).split(" (")[0]
	match level:
		0:
			return "%s (?)" % base
		1:
			return "%s (about %s)" % [base, rough_count(p)]
		2:
			return "%s (%d)" % [base, int(p["size"])]
	var comp := party_comp(p)
	if comp.is_empty():
		return "%s (%d)" % [base, int(p["size"])]
	return "%s (%d)\n%s" % [base, int(p["size"]), comp_text(comp, " · ")]


func party_name(p: Dictionary) -> String:
	var k: Dictionary = KINDS[p["kind"]]
	var base: String = k["name"]
	if p["kind"] == "patrol":
		base = "%s patrol" % Lore.FACTIONS[p["faction"]]["short"]
	elif p["kind"] == "caravan" or p["kind"] == "villagers":
		base = "%s %s" % [Lore.FACTIONS[p["faction"]]["short"], String(k["name"]).to_lower()]
	return "%s (%d)" % [base, int(p["size"])]


func _new_party(kind: String, faction: String, size: int, at: Dictionary) -> Dictionary:
	var p := {"id": next_party, "kind": kind, "faction": faction, "size": size,
		"x": float(at["x"]) + 0.5, "y": float(at["y"]) + 0.5, "home": int(at.get("id", -1)),
		"target": -1, "path": [], "wait": 0.0, "chase": 0.0}
	next_party += 1
	parties.append(p)
	return p


func _count(kind: String, faction := "", home := -1) -> int:
	var n := 0
	for p in parties:
		if p["kind"] == kind and (faction == "" or p["faction"] == faction) and (home < 0 or int(p["home"]) == home):
			n += 1
	return n


## Every day (and at the start): nests send warbands, towns send caravans,
## lords send patrols, villages send people to market.
func _spawn_tick(initial: bool) -> void:
	for st in gen.settlements:
		var id := int(st["id"])
		match st["kind"]:
			"nest":
				if nest_destroyed(id) or int(nest(id)["siege_days"]) > 0:
					continue # burned, or penned in by your siege
				if _count("warband", "", id) < 2 and (initial or randf() < 0.5):
					_new_party("warband", "lizards", 8 + randi_range(0, 6) + day() / 3, st)
				# Small hunting parties range far and wide.
				for k in (2 if initial else 1):
					if _count("hunters", "", id) < 2 and (initial or randf() < 0.6):
						_new_party("hunters", "lizards", randi_range(4, 7), st)
			"city":
				if _count("patrol", st["faction"]) < 6 and (initial or randf() < 0.35):
					_new_party("patrol", st["faction"], randi_range(14, 26), st)
				if _count("caravan") < 14 and (initial or randf() < 0.35):
					_new_party("caravan", st["faction"], randi_range(6, 12), st)
				if _count("deserters") < 4 and randf() < (0.3 if initial else 0.15):
					_new_party("deserters", st["faction"], randi_range(3, 8), st)
			"town":
				if _count("caravan") < 14 and randf() < (0.15 if initial else 0.25):
					_new_party("caravan", st["faction"], randi_range(5, 10), st)
			"village":
				if is_raided(id):
					# The burned-out leave for the nearest town.
					if _count("refugees") < 6 and randf() < 0.4:
						_new_party("refugees", st["faction"], randi_range(5, 14), st)
				elif _count("villagers") < 16 and randf() < (0.12 if initial else 0.18):
					_new_party("villagers", st["faction"], randi_range(3, 6), st)
			"hold":
				if _count("traders") < 4 and (initial or randf() < 0.3):
					_new_party("traders", "dwarves", randi_range(6, 10), st)


func _party_tick(p: Dictionary, dh: float) -> void:
	if can_see(p):
		p["seen_at"] = hours # you knew they were there (no ambush)
	if float(p["wait"]) > 0.0:
		p["wait"] = float(p["wait"]) - dh
		return
	var me := Vector2(float(p["x"]), float(p["y"]))
	var kind: String = p["kind"]
	# Hunters: lizards come for you (or anyone) when they see you; patrols
	# go after lizards.
	if kind == "warband" or kind == "patrol" or kind == "hunters":
		# Look around every half hour (cheaper than every step).
		p["look"] = float(p.get("look", 0.0)) - dh
		var prey := {}
		if float(p["look"]) <= 0.0:
			p["look"] = 0.5
			prey = _prey_for(p, me)
			p["prey"] = not prey.is_empty()
		if not prey.is_empty():
			if float(p["chase"]) <= 0.0 or (p["path"] as Array).is_empty():
				p["chase"] = 1.5
				p["path"] = _route(me, Vector2(prey["x"], prey["y"]))
			p["chase"] = float(p["chase"]) - dh
	if (p["path"] as Array).is_empty():
		_next_errand(p, me)
	_move_party(p, dh)


## Who this party would hunt, if it can see them.
func _prey_for(p: Dictionary, me: Vector2) -> Dictionary:
	var sight := 8.0
	if Company.active and hostile_to_us(p):
		var to_us := me.distance_to(pos)
		var hidden := 0.6 if gen.t(cell().x, cell().y) in [T.FOREST, T.SWAMP] else 1.0
		if to_us < sight * hidden:
			return {"x": pos.x, "y": pos.y, "player": true}
	for o in parties:
		if o == p or not _hostile(p, o):
			continue
		if me.distance_to(Vector2(o["x"], o["y"])) < sight:
			return o
	return {}


func _hostile(a: Dictionary, b: Dictionary) -> bool:
	if a["faction"] == "lizards" or b["faction"] == "lizards":
		return a["faction"] != b["faction"]
	# Aurest and Vell are at war: their patrols fight each other.
	return a["kind"] == "patrol" and b["kind"] == "patrol" and a["faction"] != b["faction"]


## Pick where to go next (and wait a while on arrival).
func _next_errand(p: Dictionary, me: Vector2) -> void:
	var home := settlement(int(p["home"])) if int(p["home"]) >= 0 else {}
	if p["target"] >= 0 and me.distance_to(Vector2(settlement(int(p["target"]))["x"], settlement(int(p["target"]))["y"])) < 2.0:
		var tgt := settlement(int(p["target"]))
		p["target"] = -1
		if p["kind"] == "warband" and tgt["kind"] == "village":
			places[int(tgt["id"])]["raided"] = hours + 96.0
			p["wait"] = 6.0
			_tell("%s is raided by lizards!" % tgt["name"], tgt)
			return
		if p["kind"] in ["villagers", "caravan", "traders"] and tgt["id"] == p["home"]:
			parties.erase(p) # home again
			return
		p["wait"] = randf_range(6.0, 14.0)
		return
	var choices: Array = []
	match p["kind"]:
		"warband":
			# Raid a village within reach, or prowl around the nest.
			for st in gen.settlements:
				if st["kind"] == "village" and not is_raided(int(st["id"])) \
						and Vector2(st["x"], st["y"]).distance_to(Vector2(home["x"], home["y"])) < 110:
					choices.append(st)
			if choices.is_empty() or randf() < 0.5:
				var roam := Vector2(home["x"], home["y"]) + Vector2(randf_range(-45, 45), randf_range(-45, 45))
				p["path"] = _route(me, roam)
				return
		"hunters":
			# Hunting parties wander far from the nest, anywhere they like.
			var far := Vector2(home["x"], home["y"]) + Vector2(randf_range(-110, 110), randf_range(-110, 110))
			p["path"] = _route(me, far)
			if (p["path"] as Array).is_empty():
				p["wait"] = 6.0
			return
		"deserters":
			var drift := me + Vector2(randf_range(-40, 40), randf_range(-40, 40))
			p["path"] = _route(me, drift)
			if (p["path"] as Array).is_empty() or randf() < 0.1:
				parties.erase(p) # they scatter
			return
		"refugees":
			choices = gen.settlements.filter(func(s): return s["kind"] in ["town", "city"] and s["faction"] == p["faction"])
			choices.sort_custom(func(a, b): return Vector2(a["x"], a["y"]).distance_squared_to(me) < Vector2(b["x"], b["y"]).distance_squared_to(me))
			choices = choices.slice(0, 1)
		"patrol":
			choices = gen.settlements.filter(func(s): return s["faction"] == p["faction"] and s["id"] != p["target"])
		"caravan":
			choices = gen.settlements.filter(func(s): return s["kind"] in ["town", "city", "hold"] and s["id"] != p["home"])
		"villagers", "traders":
			if p["target"] == -1 and me.distance_to(Vector2(home["x"], home["y"])) < 2.0:
				choices = gen.settlements.filter(func(s): return s["kind"] in ["town", "city"])
				choices.sort_custom(func(a, b): return Vector2(a["x"], a["y"]).distance_squared_to(me) < Vector2(b["x"], b["y"]).distance_squared_to(me))
				choices = choices.slice(0, 2)
			else:
				choices = [home]
	if choices.is_empty():
		p["wait"] = 12.0
		return
	var dest: Dictionary = choices.pick_random()
	p["target"] = int(dest["id"])
	p["path"] = _route(me, Vector2(dest["x"], dest["y"]))
	if (p["path"] as Array).is_empty():
		p["wait"] = 24.0


func _route(from: Vector2, to: Vector2) -> Array:
	var a := Vector2i(int(from.x), int(from.y))
	var b := Vector2i(clampi(int(to.x), 0, Gen.SIZE - 1), clampi(int(to.y), 0, Gen.SIZE - 1))
	if grid.is_point_solid(b):
		b = _nearest_open(b)
	if grid.is_point_solid(a):
		return []
	return Array(grid.get_id_path(a, b)).slice(1)


func _move_party(p: Dictionary, dh: float) -> void:
	var path_p: Array = p["path"]
	var k: Dictionary = KINDS[p["kind"]]
	var left := float(k["speed"]) * dh
	var me := Vector2(float(p["x"]), float(p["y"]))
	while left > 0.0 and not path_p.is_empty():
		var nxt: Vector2i = path_p[0]
		var target := Vector2(nxt) + Vector2(0.5, 0.5)
		var sp: float = gen.speed_at(nxt.x, nxt.y)
		if p["faction"] == "lizards" and gen.t(nxt.x, nxt.y) in [T.SWAMP, T.FOREST]:
			sp = maxf(sp, 0.85) # at home in the swamp and the trees
		sp = maxf(sp, 0.1)
		var d := me.distance_to(target)
		if left * sp >= d:
			me = target
			left -= d / sp
			path_p.pop_front()
		else:
			me += (target - me) / d * left * sp
			left = 0.0
	p["x"] = me.x
	p["y"] = me.y


## Parties that meet: lizards against anyone, Aurest against Vell. The
## stronger side usually wins; the loser is destroyed.
func _fights() -> void:
	for a in parties.duplicate():
		if not a in parties:
			continue
		for b in parties.duplicate():
			if a == b or not b in parties or not _hostile(a, b):
				continue
			if Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"])) > CONTACT:
				continue
			var sa := float(a["size"]) * (1.2 if a["kind"] == "patrol" else 1.0) * randf_range(0.6, 1.4)
			var sb := float(b["size"]) * (1.2 if b["kind"] == "patrol" else 1.0) * randf_range(0.6, 1.4)
			var win: Dictionary = a if sa >= sb else b
			var lose: Dictionary = b if win == a else a
			win["size"] = maxi(2, int(win["size"]) - int(float(lose["size"]) * 0.5))
			win["path"] = []
			parties.erase(lose)
			_tell("%s destroyed %s." % [party_name(win).split(" (")[0], party_name(lose).split(" (")[0].to_lower()],
				{"x": win["x"], "y": win["y"]})


## Is this party out to get you? Lizards always; a nation's patrols once
## you've made enemies of that nation (Company.standing).
func hostile_to_us(p: Dictionary) -> bool:
	if p["faction"] == "lizards":
		return true
	return p["kind"] == "patrol" and Company.is_enemy(String(p["faction"]))


## A hostile party close enough to catch you stops the clock.
func _check_contact() -> bool:
	if not Company.active:
		return false
	for p in parties:
		if hostile_to_us(p) and pos.distance_to(Vector2(p["x"], p["y"])) < CONTACT:
			path.clear()
			goal = {}
			waiting = false
			encounter.emit(p)
			return true
	return false


func party_by_id(id: int) -> Dictionary:
	for p in parties:
		if int(p["id"]) == id:
			return p
	return {}


func remove_party(id: int) -> void:
	var p := party_by_id(id)
	if not p.is_empty():
		parties.erase(p)


func _tell(text: String, where: Dictionary) -> void:
	# You only hear of what you see (or what happens to places you know).
	var c := Vector2i(int(where.get("x", -1)), int(where.get("y", -1)))
	var seen: bool = gen.inside(c.x, c.y) and in_sight[Gen.idx(c.x, c.y)] == 1
	if where.has("id") and places.has(int(where["id"])) and bool(places[int(where["id"])]["known"]):
		seen = true
	if seen:
		log.append("%s  %s" % [clock(), text])
		news.emit(text)
