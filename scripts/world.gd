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
const SAVE_PATH := "user://world.json"

const HOURS_PER_SEC := 1.2 # game hours per real second while moving
const WAIT_HOURS_PER_SEC := 4.0
const BASE_SPEED := 2.5 # cells per hour on open ground (a cell is about half a league)
const SIGHT := 16.0 # cells, on flat open ground
const CONTACT := 1.1 # cells: close enough to meet

const T := Gen.T

signal day_passed(notes: PackedStringArray)
signal news(text: String)
signal encounter(party: Dictionary) # a hostile party has caught you
signal arrived(target: Dictionary) # {"kind": "settlement"/"party"/"cell", ...}

var gen # world_gen.gd, built from `seed`
var seed := 0
var is_ready := false # a world is generated (or loaded)
var hours := 8.0 # since the landing; day 1, 08:00
var pos := Vector2.ZERO # the party, in cells (floats)
var path: Array = [] # Vector2i cells still to walk
var goal := {} # what we're walking to: {"kind", "id"/"cell"}
var waiting := false
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
	for i in 8:
		_spawn_tick(true)
	update_sight(true)
	save()


func _build() -> void:
	gen = Gen.new()
	gen.generate(seed)
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
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


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
		"goal": goal, "path": path.map(func(c): return [c.x, c.y])}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func load_world() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
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
		new_world(randi() % 1000000)


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
	return clampf(pace, 0.5, 1.3)


func speed_here() -> float:
	var c := cell()
	return gen.speed_at(c.x, c.y)


# ---------------------------------------------------------------- time

## Advance the world by `dt` real seconds (called by the map each frame).
## Time only runs while the party moves or waits.
func tick(dt: float) -> void:
	if not is_ready:
		return
	if moving():
		advance(dt * HOURS_PER_SEC)
	elif waiting:
		advance(dt * WAIT_HOURS_PER_SEC)


## Run the world `dh` game hours forward, in small steps.
func advance(dh: float) -> void:
	while dh > 0.0:
		var step := minf(dh, 0.25)
		dh -= step
		var day_before := day()
		hours += step
		_walk(step)
		_note_water()
		for p in parties.duplicate():
			_party_tick(p, step)
		_fights()
		if day() != day_before:
			_midnight()
		if _check_contact():
			return # stop the clock: something needs you


func _walk(dh: float) -> void:
	var left := BASE_SPEED * party_pace() * dh
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
	if path.is_empty() and not goal.is_empty():
		var g := goal
		goal = {}
		if g["kind"] == "settlement":
			_day_water = "clean"
			places[int(g["id"])]["known"] = true
		arrived.emit(g)


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
	_day_water = ""
	_spawn_tick(false)
	day_passed.emit(notes)
	save()


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
	return r


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
}


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
				if _count("warband", "", id) < 3 and (initial or randf() < 0.5):
					_new_party("warband", "lizards", 8 + randi_range(0, 6) + day() / 3, st)
			"city":
				if _count("patrol", st["faction"]) < 4 and (initial or randf() < 0.3):
					_new_party("patrol", st["faction"], randi_range(14, 26), st)
				if _count("caravan") < 10 and (initial or randf() < 0.3):
					_new_party("caravan", st["faction"], randi_range(6, 12), st)
			"town":
				if _count("caravan") < 10 and randf() < (0.1 if initial else 0.2):
					_new_party("caravan", st["faction"], randi_range(5, 10), st)
			"village":
				if _count("villagers") < 10 and randf() < (0.08 if initial else 0.12) and not is_raided(id):
					_new_party("villagers", st["faction"], randi_range(3, 6), st)
			"hold":
				if _count("traders") < 3 and (initial or randf() < 0.25):
					_new_party("traders", "dwarves", randi_range(6, 10), st)


func _party_tick(p: Dictionary, dh: float) -> void:
	if float(p["wait"]) > 0.0:
		p["wait"] = float(p["wait"]) - dh
		return
	var me := Vector2(float(p["x"]), float(p["y"]))
	var kind: String = p["kind"]
	# Hunters: lizards come for you (or anyone) when they see you; patrols
	# go after lizards.
	if kind == "warband" or kind == "patrol":
		var prey := _prey_for(p, me)
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
	if p["kind"] == "warband" and Company.active:
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
		if p["kind"] == "warband" and gen.t(nxt.x, nxt.y) in [T.SWAMP, T.FOREST]:
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


## A hostile party close enough to catch you stops the clock.
func _check_contact() -> bool:
	if not Company.active:
		return false
	for p in parties:
		if p["faction"] == "lizards" and pos.distance_to(Vector2(p["x"], p["y"])) < CONTACT:
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
