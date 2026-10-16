extends RefCounted
## Generates the land from a seed: the same seed always makes the same map,
## so a save only needs the seed plus what has changed.
##
## The map is a grid of SIZE x SIZE cells (x east, y south). Each cell has a
## height (0..1, sea below SEA_LEVEL), a terrain type, and maybe a river
## (with fords and bridges) and a road (ruined, worn or good).
##
## Layout (the land's geography, roughly):
##   south and south-west: the sea; the wreck beach on the south-west coast
##   south-west coastlands: swamp and forest, the lizards' country
##   west: the Kingdom of Aurest;  east: the Vellish Marches (at war)
##   north: the Greyspine mountains, the dwarves' holds in their feet
## Rivers run from the mountains to the sea; roads join the settlements, good
## in a nation's heartland, worn on its frontier, ruined in the lizard lands.

const SIZE := 512
const SEA_LEVEL := 0.28

enum T { SEA, BEACH, PLAINS, FOREST, HILLS, MOUNTAIN, SWAMP, LAKE }
const T_NAMES := ["Sea", "Beach", "Plains", "Forest", "Hills", "Mountains", "Swamp", "Lake"]
## River: 0 none, 1 river, 2 ford, 3 bridge.  Road: 0 none, 1 ruined, 2 worn, 3 good.
const ROAD_NAMES := ["", "Ruined road", "Worn road", "Good road"]

## Travel speed by terrain (x the party's pace); 0 = impassable.
const SPEED := [0.0, 0.9, 1.0, 0.6, 0.65, 0.3, 0.4, 0.0]
const ROAD_SPEED := [0.0, 0.9, 1.25, 1.6]
const FORD_SPEED := 0.45

var seed := 1
var height := PackedFloat32Array()
var terrain := PackedByteArray()
var moist := PackedFloat32Array()
var river := PackedByteArray()
var road := PackedByteArray()
var region := PackedByteArray() # 0 none, 1 aurest, 2 vell, 3 dwarves, 4 lizards
var settlements: Array = [] # {id, name, kind, faction, x, y}
var start := Vector2i.ZERO # where the castaways come up from the beach
var wreck := Vector2i.ZERO # the beach itself
var stash_nest := -1 # settlement id of the nest that holds the ship's stores
var rivers := 0
var road_cells := 0
var _rng := RandomNumberGenerator.new()

const REGION_NAMES := ["", "aurest", "vell", "dwarves", "lizards"]


func generate(s: int) -> void:
	seed = s
	_rng.seed = s
	var n := SIZE * SIZE
	height.resize(n)
	terrain.resize(n)
	moist.resize(n)
	river.resize(n)
	road.resize(n)
	region.resize(n)
	river.fill(0)
	road.fill(0)
	_heights()
	_rivers()
	_terrain()
	_regions()
	_place_settlements()
	_roads()
	_fords()


static func idx(x: int, y: int) -> int:
	return y * SIZE + x


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE


func h(x: int, y: int) -> float:
	return height[idx(clampi(x, 0, SIZE - 1), clampi(y, 0, SIZE - 1))]


func t(x: int, y: int) -> int:
	return terrain[idx(clampi(x, 0, SIZE - 1), clampi(y, 0, SIZE - 1))]


## How fast a party moves through this cell (before its own pace).
func speed_at(x: int, y: int) -> float:
	var i := idx(x, y)
	var rd := road[i]
	var rv := river[i]
	if rv == 3:
		return ROAD_SPEED[maxi(rd, 2)]
	if rv == 2:
		return FORD_SPEED
	if rv == 1:
		return 0.0
	var base: float = SPEED[terrain[i]]
	if terrain[i] == T.MOUNTAIN and height[i] > 0.86:
		base = 0.0 # the high peaks
	if rd > 0 and base > 0.0:
		return maxf(base, ROAD_SPEED[rd])
	return base


# ---------------------------------------------------------------- height

## Every new game draws its own land. The broad plan (a coast where you
## wash up, lizard swamps behind it, two nations at war across the middle,
## a mountain range with the dwarves beyond) is kept so the story works,
## but where each of those lies is shuffled: the whole layout is turned and
## mirrored at random (8 ways), and its proportions are drawn per seed:
## how far the sea reaches in, how wide the west coast is, where the range
## starts, whether a second range or an inland ridge rises, where the
## border between the nations runs and who holds which side.
var lay := {} # this land's layout parameters


func _layout() -> void:
	lay = {
		"swap": _rng.randf() < 0.5, "flip_x": _rng.randf() < 0.5, "flip_y": _rng.randf() < 0.5,
		"shore": _rng.randf_range(0.76, 0.87), "west": _rng.randf_range(0.03, 0.12),
		"west_bay": _rng.randf_range(0.04, 0.16), "north": _rng.randf_range(0.28, 0.42),
		"spur": _rng.randf() < 0.65, "spur_x": _rng.randf_range(0.7, 0.85),
		"ridge": _rng.randf() < 0.45, "ridge_a": _rng.randf_range(-0.6, 0.6), "ridge_c": _rng.randf_range(0.4, 0.6),
		"border": _rng.randf_range(0.42, 0.6), "aurest_west": _rng.randf() < 0.5,
		"lizard_w": _rng.randf_range(0.4, 0.55), "lizard_n": _rng.randf_range(0.52, 0.64),
		"rivers": _rng.randi_range(12, 20),
	}


## Map cell -> where it lies in the layout plan (0..1, "north" is small y).
func canon(x: float, y: float) -> Vector2:
	var fx := x / SIZE
	var fy := y / SIZE
	if lay["swap"]:
		var tmp := fx
		fx = fy
		fy = tmp
	if lay["flip_x"]:
		fx = 1.0 - fx
	if lay["flip_y"]:
		fy = 1.0 - fy
	return Vector2(fx, fy)


func _heights() -> void:
	_layout()
	var base := FastNoiseLite.new()
	base.seed = seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.006
	base.fractal_octaves = 5
	var ridge := FastNoiseLite.new()
	ridge.seed = seed + 1
	ridge.frequency = 0.012
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	var coast := FastNoiseLite.new()
	coast.seed = seed + 2
	coast.frequency = 0.01
	var wet := FastNoiseLite.new()
	wet.seed = seed + 3
	wet.frequency = 0.008
	wet.fractal_octaves = 3
	var north_at: float = lay["north"]
	var shore_at: float = lay["shore"]
	for y in SIZE:
		for x in SIZE:
			var c := canon(x, y)
			var fx := c.x
			var fy := c.y
			var v := 0.5 + 0.32 * base.get_noise_2d(x, y)
			# The great range across the north, maybe a spur down one side,
			# maybe a lower ridge across the middle.
			var north := smoothstep(north_at, north_at - 0.3, fy)
			if lay["spur"]:
				north += 0.6 * smoothstep(lay["spur_x"], lay["spur_x"] + 0.2, fx) * smoothstep(0.7, 0.3, fy)
			if lay["ridge"]:
				var d := absf(fy - (lay["ridge_c"] + lay["ridge_a"] * (fx - 0.5)))
				north += 0.45 * smoothstep(0.06, 0.0, d) * smoothstep(0.15, 0.3, fx) * smoothstep(0.95, 0.8, fx)
			north = clampf(north, 0.0, 1.0)
			var r := clampf(ridge.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			v += r * r * 0.45 * north + 0.08 * north
			# The coast: sea along the "south", curving up the "west".
			var shore := shore_at + 0.06 * coast.get_noise_1d(fx * SIZE) + float(lay["west_bay"]) * smoothstep(0.35, 0.0, fx)
			var west: float = lay["west"] + 0.05 * coast.get_noise_1d(fy * SIZE + 900.0)
			var land := minf(smoothstep(shore + 0.04, shore - 0.05, fy), smoothstep(west - 0.03, west + 0.06, fx))
			land = minf(land, smoothstep(0.995, 0.96, fy))
			v = lerpf(0.12, v, land)
			var i := idx(x, y)
			height[i] = clampf(v, 0.0, 1.0)
			# Wet lowlands behind the landing coast: the lizards' swamps.
			moist[i] = 0.5 + 0.5 * wet.get_noise_2d(x, y) + 0.25 * smoothstep(0.45, 0.85, fy) * smoothstep(0.6, 0.15, fx)


# ---------------------------------------------------------------- rivers

## Rivers start high in the hills and run downhill to the sea. Water's way
## down is found once for the whole map with a "priority flood" from the
## sea: every cell learns which neighbour leads to the sea without ever
## climbing, and where it must fill a hollow first, that hollow is a lake.
func _rivers() -> void:
	var n := SIZE * SIZE
	var filled := height.duplicate()
	var down := PackedInt32Array()
	down.resize(n)
	down.fill(-1)
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var buckets: Array = []
	var nb := 2048
	buckets.resize(nb)
	for i in nb:
		buckets[i] = [] # plain Arrays: packed arrays inside an Array are copies
	for i in n:
		var x := i % SIZE
		var y := i / SIZE
		if height[i] < SEA_LEVEL or x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1:
			seen[i] = 1
			buckets[int(clampf(height[i], 0.0, 0.9999) * nb)].append(i)
	var offs := [1, -1, SIZE, -SIZE]
	for b in nb:
		var k := 0
		var bucket: Array = buckets[b]
		while k < bucket.size():
			var c: int = bucket[k]
			k += 1
			var cx := c % SIZE
			for o in offs:
				var nx := cx + (1 if o == 1 else (-1 if o == -1 else 0))
				if nx < 0 or nx >= SIZE:
					continue
				var q: int = c + o
				if q < 0 or q >= n or seen[q] == 1:
					continue
				seen[q] = 1
				down[q] = c
				filled[q] = maxf(height[q], filled[c] + 0.00002) # flats drain toward the outlet
				var qb := maxi(b, int(clampf(filled[q], 0.0, 0.9999) * nb))
				buckets[qb].append(q)
		buckets[b] = []

	var tries := 0
	while rivers < int(lay["rivers"]) and tries < 900:
		tries += 1
		var x := _rng.randi_range(20, SIZE - 20)
		var y := _rng.randi_range(20, SIZE - 20)
		var i := idx(x, y)
		if height[i] < 0.56 or height[i] > 0.8 or river[i] != 0 or _near_water(x, y, 10):
			continue
		var path: Array = []
		var c := i
		while c >= 0 and height[c] >= SEA_LEVEL and path.size() < 2000:
			path.append(c)
			if river[c] != 0 and path.size() > 1:
				break # joins a bigger river
			c = down[c]
		if path.size() < 45:
			continue
		rivers += 1
		var since_lake := 999
		for p in path:
			since_lake += 1
			# One lake per real hollow (deep enough, not up in the mountains).
			if filled[p] - height[p] > 0.04 and height[p] < 0.6 and since_lake > 60:
				_lake_at(p, filled[p] - 0.025, filled)
				since_lake = 0
			elif terrain[p] != T.LAKE:
				river[p] = 1
				height[p] = maxf(SEA_LEVEL + 0.004, height[p] - 0.01) # the valley it cuts


## A lake in the hollow at cell `c`: a rough, roundish pool, bigger where
## the hollow is deeper.
func _lake_at(c: int, level: float, filled: PackedFloat32Array) -> void:
	var cx := c % SIZE
	var cy := c / SIZE
	var depth := filled[c] - height[c]
	var r := clampf(depth * 90.0, 2.5, 7.0)
	var wob := _rng.randf() * TAU
	var ri := int(ceil(r * 1.3))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := cx + dx
			var y := cy + dy
			if not inside(x, y):
				continue
			var a := atan2(dy, dx)
			var edge := r * (0.8 + 0.25 * sin(a * 3.0 + wob) + 0.15 * sin(a * 5.0 - wob))
			if Vector2(dx, dy).length() > edge:
				continue
			var i := idx(x, y)
			if height[i] < SEA_LEVEL or height[i] > level + 0.03:
				continue
			terrain[i] = T.LAKE
			moist[i] = 1.0
			river[i] = 0
			height[i] = minf(height[i], level)


func _lake(cx: int, cy: int, r: int) -> void:
	var lh := h(cx, cy)
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if inside(x, y) and Vector2(x - cx, y - cy).length() <= r + 0.3:
				var i := idx(x, y)
				terrain[i] = T.LAKE
				height[i] = minf(height[i], lh)
				river[i] = 0
				moist[i] = 1.0


# ---------------------------------------------------------------- terrain

func _terrain() -> void:
	for y in SIZE:
		for x in SIZE:
			var i := idx(x, y)
			if terrain[i] == T.LAKE and moist[i] >= 1.0:
				continue
			var v := height[i]
			var m := moist[i]
			var tt := T.PLAINS
			if v < SEA_LEVEL:
				tt = T.SEA
			elif v < SEA_LEVEL + 0.018:
				tt = T.BEACH if m < 0.75 else T.SWAMP
			elif v > 0.72:
				tt = T.MOUNTAIN
			elif v > 0.6:
				tt = T.HILLS if m < 0.7 else T.FOREST
			elif m > 0.66 and v < 0.46:
				tt = T.SWAMP
			elif m > 0.56:
				tt = T.FOREST
			terrain[i] = tt


func _regions() -> void:
	var west_nation := 1 if lay["aurest_west"] else 2
	var east_nation := 3 - west_nation
	for y in SIZE:
		for x in SIZE:
			var i := idx(x, y)
			var c := canon(x, y)
			var r := 0
			if terrain[i] == T.SEA:
				r = 0
			elif c.y < float(lay["north"]) - 0.08 or (terrain[i] == T.MOUNTAIN and c.y < 0.5):
				r = 3
			elif c.x < float(lay["lizard_w"]) and c.y > float(lay["lizard_n"]) - 0.15 * (0.5 - c.x):
				r = 4
			elif c.x < float(lay["border"]) + 0.06 * sin(c.y * 9.0):
				r = west_nation
			else:
				r = east_nation
			region[i] = r


# ---------------------------------------------------------------- settlements

func _place_settlements() -> void:
	# The wreck: the south-west coast, where land meets sea.
	wreck = _landing()
	start = _inland_of(wreck, 6)
	var plan := [
		["aurest", "city", 2, 70], ["aurest", "town", 5, 40], ["aurest", "village", 16, 16],
		["vell", "city", 2, 70], ["vell", "town", 5, 40], ["vell", "village", 16, 16],
		["dwarves", "hold", 3, 50], ["dwarves", "village", 4, 18],
		["lizards", "nest", 5, 34],
	]
	for p in plan:
		var fac: String = p[0]
		var reg := REGION_NAMES.find(fac)
		for k in int(p[2]):
			var spot := _site(reg, String(p[1]), int(p[3]))
			if spot.x < 0:
				continue
			settlements.append({"id": settlements.size(), "name": _name(fac), "kind": p[1], "faction": fac,
				"x": spot.x, "y": spot.y})
	# The nest nearest the wreck holds the ship's stores.
	var best := INF
	for s in settlements:
		if s["kind"] == "nest":
			var d := Vector2(s["x"] - wreck.x, s["y"] - wreck.y).length()
			if d < best:
				best = d
				stash_nest = s["id"]


## Where the ship broke up: the stretch of shore nearest the far corner of
## the lizard coast (in the layout plan, the south-west).
func _landing() -> Vector2i:
	var best := Vector2i(SIZE / 2, SIZE / 2)
	var best_d := INF
	var aim := Vector2(0.2, 0.86)
	for y in range(2, SIZE - 2, 2):
		for x in range(2, SIZE - 2, 2):
			var i := idx(x, y)
			if terrain[i] in [T.SEA, T.LAKE, T.MOUNTAIN] or river[i] != 0:
				continue
			if terrain[idx(x + 2, y)] != T.SEA and terrain[idx(x - 2, y)] != T.SEA \
					and terrain[idx(x, y + 2)] != T.SEA and terrain[idx(x, y - 2)] != T.SEA:
				continue
			var d := canon(x, y).distance_to(aim)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


func _find(ok: Callable, fallback: Vector2i) -> Vector2i:
	for tries in 4000:
		var x := _rng.randi_range(5, SIZE - 5)
		var y := _rng.randi_range(5, SIZE - 5)
		if ok.call(x, y):
			return Vector2i(x, y)
	return fallback


func _inland_of(p: Vector2i, steps: int) -> Vector2i:
	var c := p
	for i in steps:
		var best := c
		for d in [Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var q: Vector2i = c + d
			if inside(q.x, q.y) and terrain[idx(q.x, q.y)] not in [T.SEA, T.LAKE] and river[idx(q.x, q.y)] == 0 \
					and h(q.x, q.y) > h(best.x, best.y):
				best = q
		c = best
	return c


## A good place for a settlement of this kind in this region, away from the
## others. Villages like rivers and plains, holds like the mountains' feet,
## nests like swamp and forest.
func _site(reg: int, kind: String, spacing: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for tries in 260:
		var x := _rng.randi_range(12, SIZE - 12)
		var y := _rng.randi_range(12, SIZE - 12)
		var i := idx(x, y)
		if region[i] != reg or river[i] != 0:
			continue
		var tt := terrain[i]
		var score := _rng.randf()
		match kind:
			"hold":
				if tt != T.MOUNTAIN and tt != T.HILLS:
					continue
				score += 1.0 - absf(height[i] - 0.72) * 6.0
			"nest":
				if tt not in [T.SWAMP, T.FOREST, T.PLAINS]:
					continue
				score += 1.0 if tt == T.SWAMP else 0.5
			_:
				if tt not in [T.PLAINS, T.FOREST, T.HILLS]:
					continue
				if tt == T.PLAINS:
					score += 0.8
				if _near_water(x, y, 6):
					score += 1.0
		var crowded := false
		for s in settlements:
			if Vector2(s["x"] - x, s["y"] - y).length() < spacing:
				crowded = true
				break
		if crowded:
			continue
		if Vector2(x - wreck.x, y - wreck.y).length() < 40:
			continue
		if score > best_score:
			best_score = score
			best = Vector2i(x, y)
	return best


func _near_water(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1, 2):
		for dx in range(-r, r + 1, 2):
			if inside(x + dx, y + dy):
				var i := idx(x + dx, y + dy)
				if river[i] != 0 or terrain[i] == T.LAKE:
					return true
	return false


func _name(fac: String) -> String:
	var f: Dictionary = preload("res://scripts/lore.gd").FACTIONS[fac]
	for tries in 20:
		var n := String(f["syll"][_rng.randi() % f["syll"].size()]) + String(f["end"][_rng.randi() % f["end"].size()])
		if settlements.all(func(s): return s["name"] != n):
			return n
	return "%s %d" % [f["short"], settlements.size()]


# ---------------------------------------------------------------- roads

## A grid for laying roads: cheap on plains and existing roads, dear across
## forest, swamp, hills and rivers; never over sea or peaks.
func _road_grid() -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, SIZE, SIZE)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for y in SIZE:
		for x in SIZE:
			var i := idx(x, y)
			var tt := terrain[i]
			if tt == T.SEA or tt == T.LAKE or (tt == T.MOUNTAIN and height[i] > 0.8):
				g.set_point_solid(Vector2i(x, y))
				continue
			var w: float = {T.PLAINS: 1.0, T.BEACH: 1.4, T.FOREST: 2.6, T.HILLS: 2.4, T.MOUNTAIN: 6.0, T.SWAMP: 4.0}.get(tt, 1.0)
			if river[i] != 0:
				w += 9.0
			g.set_point_weight_scale(Vector2i(x, y), w)
	return g


func _roads() -> void:
	var g := _road_grid()
	var by_fac := {}
	for s in settlements:
		if not by_fac.has(s["faction"]):
			by_fac[s["faction"]] = []
		by_fac[s["faction"]].append(s)
	var links: Array = [] # [a, b, condition]
	for fac in ["aurest", "vell"]:
		var list: Array = by_fac.get(fac, [])
		var big := list.filter(func(s): return s["kind"] != "village")
		var cities := list.filter(func(s): return s["kind"] == "city")
		for i in range(1, cities.size()):
			links.append([cities[0], cities[i], 3])
		for s in big:
			var near := _nearest(s, big, 2)
			for o in near:
				links.append([s, o, 3])
		for s in list.filter(func(s): return s["kind"] == "village"):
			var near2 := _nearest(s, big, 1)
			for o in near2:
				links.append([s, o, 2])
	# Across the frontier: a few worn roads (the war goes back and forth on them).
	var a_big: Array = by_fac.get("aurest", []).filter(func(s): return s["kind"] != "village")
	var v_big: Array = by_fac.get("vell", []).filter(func(s): return s["kind"] != "village")
	for s in a_big.slice(0, 3):
		for o in _nearest(s, v_big, 1):
			links.append([s, o, 2])
	# Dwarf holds trade down to the nearest human towns.
	var humans: Array = a_big + v_big
	for s in by_fac.get("dwarves", []):
		for o in _nearest(s, humans if s["kind"] == "hold" else by_fac.get("dwarves", []), 1):
			if o != s:
				links.append([s, o, 2])
	# Old roads into the lizard lands, from before the horde: ruined.
	var wreck_s := {"x": start.x, "y": start.y}
	for o in _nearest(wreck_s, humans, 2):
		links.append([wreck_s, o, 1])
	for s in by_fac.get("lizards", []):
		for o in _nearest(s, humans, 1):
			links.append([s, o, 1])
	for l in links:
		var path := g.get_id_path(Vector2i(l[0]["x"], l[0]["y"]), Vector2i(l[1]["x"], l[1]["y"]))
		var cond: int = l[2]
		for p in path:
			var i := idx(p.x, p.y)
			# Even a good road decays where the lizards roam.
			var c := mini(cond, 1) if region[i] == 4 else cond
			if road[i] == 0:
				road_cells += 1
			road[i] = maxi(road[i], c)
			if river[i] == 1 or river[i] == 3:
				river[i] = 3 if road[i] >= 2 else 2 # a bridge, or a ford for a poor road
			g.set_point_weight_scale(p, 0.5) # later roads share this one


func _nearest(s: Dictionary, list: Array, n: int) -> Array:
	var sorted := list.filter(func(o): return o != s)
	sorted.sort_custom(func(a, b):
		return Vector2(a["x"] - s["x"], a["y"] - s["y"]).length_squared() < Vector2(b["x"] - s["x"], b["y"] - s["y"]).length_squared())
	return sorted.slice(0, n)


## Fords: shallow places along every river, where the land is low and flat.
func _fords() -> void:
	var since := 0
	for i in river.size():
		if river[i] != 1:
			continue
		since += 1
		if since > 22 and terrain[i] in [T.PLAINS, T.FOREST, T.BEACH] and _rng.randf() < 0.15:
			river[i] = 2
			since = 0
