extends RefCounted
## The weather on the map, from the land the generator made (world_gen.gd),
## so it makes sense on every map:
##
##   wind    each map has a prevailing wind off its own sea, inland (worked
##           out once from where the sea lies). Storms ride it, a little
##           veered or backed each time.
##   storms  form out over the sea near the coast (more in winter and
##           autumn) and drift inland with the wind. They rain hardest
##           where the land rises and spend themselves crossing high
##           ground, so the far side of a ridge lies in a rain shadow.
##           Summer afternoons brew short thunderstorms over the hills.
##   fog     lies in low wet ground (swamps, lakes, river bottoms, the
##           beach) on some mornings, from the small hours to mid-morning;
##           likelier in autumn and winter and after rain. Never on the
##           hills.
##   heat    on summer days of a hot spell, through the afternoon, on open
##           ground away from the sea's breeze.
##
## What it does (World uses these): rain and fog cut how far you see; rain
## and heat slow the march; rain washes out tracks (World.tracks); a good
## soaking fills the water barrels; heat costs water. The map draws the
## storms (clouds, rain, lightning), the fog and the heat (map.gd).

const Gen := preload("res://scripts/world_gen.gd")
const T := Gen.T

var w # the World autoload
var wind := Vector2(-1, 0) # where the prevailing wind blows to (cells, unit)
var storms: Array = [] # {"id", "x", "y", "r", "s" (0..1), "vx", "vy", "kind": "storm"|"thunder", "age"}
var next_id := 1
var _coast: Array = [] # [x, y] sea cells along the coast, where storms form
var rain_hours := 0.0 # today, where you are (heavy rain)
var heat_hours := 0.0 # today, marching in the heat
var last_rain_h := -99.0 # when it last rained where you are
var state := "" # "storm", "rain", "fog", "heat" or "" where you are now
var _seed := 0
# Stage 3: what the weather does to the company.
var caught := 0.0 # rain-water caught today (days of water), for the midnight note
var _catch_acc := 0.0
var damp := 0.0 # 0 dry .. 1 soaked: the powder and the cartridges (misfires, slow loading)
var covered_until := -1.0 # the kegs under tarpaulin (a squall's COVER THE POWDER)
var site_rain := {} # work post key -> hours of rain on it today (Company._posts_day)
var _site_t := 0.0
var pending_event := "" # a weather pop-up waiting to be asked (World.advance: events.weather_event)
var _last_event := {} # event id -> hours when it last came
# Rivers (stage 2): water that has run off into each river cell, flowing
# downstream; how high that puts it; which fords are under and which banks
# are flooded (mirrored in gen.wet, for speed_at and the map).
var water := {} # river cell index -> water in it (only where there's some)
var closed := {} # ford cell index -> true while it's under water
var flooded := {} # bank cell index -> true while it's under water
var flood_version := 0 # bumps whenever closed/flooded change (the map redraws)
var _buckets := {} # Vector2i(bx, by) -> Array of river cell indices
var _flood_t := 0.0
const BUCKET := 16
const RUNOFF := 1.0 # water per hour a river cell takes from a downpour over it
const FLOW := 2.6 # cells an hour the flood moves downstream
const DRAIN := 0.02 # share an hour soaking away
const CAP := 11.0 # water at which a river is bank-full
const FORD_SHUT := 0.55 # level that closes a ford
const FORD_OPEN := 0.4 # ...and that opens it again
const BANKS := 0.75 # level that floods the banks


func _init(world) -> void:
	w = world


## Work out the wind and the coast from the land: once per map.
func setup() -> void:
	var g = w.gen
	_seed = int(w.seed)
	var sea := Vector2.ZERO
	var land := Vector2.ZERO
	var ns := 0
	var nl := 0
	_coast.clear()
	for y in range(0, Gen.SIZE, 4):
		for x in range(0, Gen.SIZE, 4):
			var tt: int = g.t(x, y)
			if tt == T.SEA:
				sea += Vector2(x, y)
				ns += 1
				# (sea within a few cells of land: the coast)
				for d in [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6)]:
					if g.inside(x + d.x, y + d.y) and g.t(x + d.x, y + d.y) != T.SEA:
						_coast.append([x, y])
						break
			elif tt != T.LAKE:
				land += Vector2(x, y)
				nl += 1
	if ns > 0 and nl > 0:
		wind = (land / nl - sea / ns).normalized()
	if _coast.is_empty():
		_coast.append([Gen.SIZE / 2, Gen.SIZE / 2])
	_buckets.clear()
	for c in g.flow_cells:
		var k := Vector2i((c % Gen.SIZE) / BUCKET, (c / Gen.SIZE) / BUCKET)
		if not _buckets.has(k):
			_buckets[k] = []
		(_buckets[k] as Array).append(c)


func to_dict() -> Dictionary:
	var wl := {}
	for c in water:
		wl[str(c)] = snappedf(float(water[c]), 0.01)
	return {"storms": storms, "next_id": next_id, "rain_hours": rain_hours, "heat_hours": heat_hours,
		"last_rain_h": last_rain_h, "state": state, "water": wl, "damp": snappedf(damp, 0.01),
		"covered_until": covered_until, "site_rain": site_rain}


func from_dict(d: Dictionary) -> void:
	storms = d.get("storms", [])
	next_id = int(d.get("next_id", 1))
	rain_hours = float(d.get("rain_hours", 0.0))
	heat_hours = float(d.get("heat_hours", 0.0))
	last_rain_h = float(d.get("last_rain_h", -99.0))
	state = String(d.get("state", ""))
	damp = float(d.get("damp", 0.0))
	covered_until = float(d.get("covered_until", -1.0))
	site_rain = d.get("site_rain", {})
	water.clear()
	var wl: Dictionary = d.get("water", {})
	for k in wl:
		water[int(k)] = float(wl[k])
	_flood_status(true)


func clear() -> void:
	damp = 0.0
	site_rain.clear()
	pending_event = ""
	_last_event.clear()
	storms.clear()
	water.clear()
	closed.clear()
	flooded.clear()
	rain_hours = 0.0
	heat_hours = 0.0
	last_rain_h = -99.0
	state = ""


# ---------------------------------------------------------------- the sky

## How often a storm forms off the coast, per hour, by season.
const STORM_RATE := {"winter": 0.15, "autumn": 0.13, "spring": 0.09, "summer": 0.03}


func tick(dh: float) -> void:
	var g = w.gen
	var season: String = w.season()
	# Storms off the sea.
	if randf() < float(STORM_RATE.get(season, 0.03)) * dh:
		_spawn_storm()
	# Summer afternoons: a thunderstorm boils up over the hills.
	var hd: float = w.hours_of_day()
	if season == "summer" and hd > 13.0 and hd < 18.0 and randf() < 0.035 * dh:
		_spawn_thunder()
	for s in storms.duplicate():
		var x := float(s["x"])
		var y := float(s["y"])
		x += float(s["vx"]) * dh
		y += float(s["vy"]) * dh
		s["x"] = x
		s["y"] = y
		s["age"] = float(s["age"]) + dh
		var cx := clampi(int(x), 0, Gen.SIZE - 1)
		var cy := clampi(int(y), 0, Gen.SIZE - 1)
		var h: float = g.h(cx, cy)
		var tt: int = g.t(cx, cy)
		# Over the sea it holds together (it may even build); over land it
		# rains itself out, and high ground wrings it dry: the rain shadow.
		var spend := 0.0
		if tt == T.SEA:
			spend = -0.02 if float(s["age"]) < 6.0 else 0.01
		else:
			spend = 0.03 + maxf(0.0, h - 0.45) * 0.7
		if s["kind"] == "thunder":
			spend = maxf(spend, 0.22) # (a summer storm is short)
		s["s"] = clampf(float(s["s"]) - spend * dh, 0.0, 1.0)
		if float(s["s"]) < 0.06 or x < -30 or y < -30 or x > Gen.SIZE + 30 or y > Gen.SIZE + 30:
			storms.erase(s)
	# The slow work (rivers, tracks, the weather where you are, the work
	# sites) in quarter-hour lumps, not every frame.
	_slow_acc += dh
	if _slow_acc < SLOW_STEP:
		return
	var sdh := _slow_acc
	_slow_acc = 0.0
	_wash_tracks(sdh)
	_rivers_tick(sdh)
	_here(sdh)
	_sites_tick(sdh)


const SLOW_STEP := 0.25 # game hours
var _slow_acc := 0.0


func _spawn_storm() -> void:
	var c: Array = _coast[randi() % _coast.size()]
	# Out to sea from the coast, upwind.
	var at := Vector2(float(c[0]), float(c[1])) - wind * randf_range(8.0, 22.0)
	var dir := wind.rotated(randf_range(-0.45, 0.45))
	var sp := randf_range(1.6, 3.4)
	storms.append({"id": next_id, "x": at.x, "y": at.y, "r": randf_range(13.0, 28.0), "s": randf_range(0.5, 1.0),
		"vx": dir.x * sp, "vy": dir.y * sp, "kind": "storm", "age": 0.0})
	next_id += 1


func _spawn_thunder() -> void:
	var g = w.gen
	for k in 12:
		var x := randi_range(10, Gen.SIZE - 10)
		var y := randi_range(10, Gen.SIZE - 10)
		if g.t(x, y) in [T.HILLS, T.MOUNTAIN, T.PLAINS] and g.h(x, y) > 0.42:
			var dir := wind.rotated(randf_range(-0.8, 0.8))
			storms.append({"id": next_id, "x": float(x), "y": float(y), "r": randf_range(4.0, 7.0), "s": randf_range(0.7, 1.0),
				"vx": dir.x * 1.2, "vy": dir.y * 1.2, "kind": "thunder", "age": 0.0})
			next_id += 1
			return


## Rain at a point (0 dry .. 1 a downpour): every storm over it, heavier
## where the ground rises (the windward slopes).
func rain_at(p: Vector2) -> float:
	var r := 0.0
	for s in storms:
		var d := p.distance_to(Vector2(float(s["x"]), float(s["y"])))
		var rad := float(s["r"])
		if d >= rad:
			continue
		var k := 1.0 - d / rad
		r += float(s["s"]) * k * k * (3.0 - 2.0 * k) * 1.4
	if r <= 0.0:
		return 0.0
	var g = w.gen
	var cx := clampi(int(p.x), 0, Gen.SIZE - 1)
	var cy := clampi(int(p.y), 0, Gen.SIZE - 1)
	var h: float = maxf(g.h(cx, cy), Gen.SEA_LEVEL)
	var up := clampf((h - Gen.SEA_LEVEL) * 1.6, 0.0, 0.6)
	return clampf(r * (0.8 + up), 0.0, 1.0)


## Is there lightning in the storm over this point?
func thunder_at(p: Vector2) -> bool:
	for s in storms:
		if float(s["s"]) > 0.75 and p.distance_to(Vector2(float(s["x"]), float(s["y"]))) < float(s["r"]):
			return true
	return false


## A number for the day that's the same every time it's asked.
func _day_roll(salt: int) -> float:
	return float(hash(_seed * 977 + int(w.day()) * 131 + salt) % 10000) / 10000.0


## Fog at a cell (0..1): the right ground, the right hour, the right sort
## of morning.
func fog_at(c: Vector2i) -> float:
	var hd: float = w.hours_of_day()
	var time := 0.0
	if hd >= 22.0 or hd < 3.0:
		time = 0.5
	elif hd < 8.0:
		time = 1.0
	elif hd < 11.0:
		time = 1.0 - (hd - 8.0) / 3.0
	if time <= 0.0:
		return 0.0
	var season: String = w.season()
	var p: float = {"autumn": 0.3, "winter": 0.25, "spring": 0.2, "summer": 0.07}.get(season, 0.2)
	if w.hours - last_rain_h < 20.0:
		p += 0.2 # the ground steams after rain
	var roll := _day_roll(17)
	if roll >= p:
		return 0.0
	var thick := 0.55 + 0.45 * (1.0 - roll / p)
	return clampf(thick * time * ground_fog(c), 0.0, 1.0)


## How readily fog lies on this ground.
func ground_fog(c: Vector2i) -> float:
	var g = w.gen
	if not g.inside(c.x, c.y):
		return 0.0
	var tt: int = g.t(c.x, c.y)
	match tt:
		T.SWAMP:
			return 1.0
		T.LAKE:
			return 0.9
		T.BEACH:
			return 0.65 # sea fret
		T.MOUNTAIN:
			return 0.0
		T.HILLS:
			return 0.1
	var wet := 0.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := c.x + dx
			var y := c.y + dy
			if g.inside(x, y) and (g.river[Gen.idx(x, y)] != 0 or g.t(x, y) == T.LAKE):
				wet = 0.85
	var low := clampf((0.45 - g.h(c.x, c.y)) * 4.0, 0.0, 1.0)
	var base := 0.45 if tt == T.FOREST else 0.3
	return maxf(wet, base * (0.4 + 0.6 * low))


## Heat at a cell (0..1): summer, a hot spell, the afternoon, open ground
## away from the sea.
func heat_at(c: Vector2i) -> float:
	var season: String = w.season()
	var p: float = {"summer": 0.55, "spring": 0.1}.get(season, 0.0)
	if p <= 0.0 or _day_roll(41) >= p:
		return 0.0
	var hd: float = w.hours_of_day()
	if hd < 10.0 or hd > 18.5:
		return 0.0
	var time := clampf(minf((hd - 10.0) / 2.5, (18.5 - hd) / 2.5), 0.0, 1.0)
	var g = w.gen
	if not g.inside(c.x, c.y):
		return 0.0
	var ground: float = {T.PLAINS: 1.0, T.HILLS: 0.85, T.BEACH: 0.5, T.SWAMP: 0.7, T.FOREST: 0.45, T.MOUNTAIN: 0.2}.get(g.t(c.x, c.y), 0.5)
	if rain_at(Vector2(c) + Vector2(0.5, 0.5)) > 0.1:
		return 0.0
	return clampf(time * ground * (0.7 + 0.3 * (1.0 - _day_roll(43))), 0.0, 1.0)


# ---------------------------------------------------------------- rivers

## Rain that falls into the rivers runs downhill along them: a storm in the
## hills is a flood at the ford a day later, further down.
func _rivers_tick(dh: float) -> void:
	var g = w.gen
	# The rain under each storm into the river cells beneath it (more off
	# steep high ground: it runs off rather than soaking in).
	for s in storms:
		var cx := float(s["x"])
		var cy := float(s["y"])
		var r := float(s["r"])
		for by in range(int((cy - r) / BUCKET), int((cy + r) / BUCKET) + 1):
			for bx in range(int((cx - r) / BUCKET), int((cx + r) / BUCKET) + 1):
				var list = _buckets.get(Vector2i(bx, by), null)
				if list == null:
					continue
				for c in list:
					var p := Vector2(float(c % Gen.SIZE) + 0.5, float(c / Gen.SIZE) + 0.5)
					if p.distance_to(Vector2(cx, cy)) >= r:
						continue
					var rn := rain_at(p)
					if rn > 0.05:
						var steep := 1.0 + clampf((g.height[c] - 0.4) * 4.0, 0.0, 1.5)
						water[c] = float(water.get(c, 0.0)) + rn * RUNOFF * steep * dh
	# Downstream: each cell passes on a share of what it holds (into the
	# sea at the mouth), and some soaks away.
	if not water.is_empty():
		var move := clampf(FLOW * dh, 0.0, 0.9)
		var keep := 1.0 - DRAIN * dh
		var nw := {}
		for c in water:
			var v: float = float(water[c]) * keep
			var nx: int = g.flow_next[c]
			nw[c] = float(nw.get(c, 0.0)) + v * (1.0 - move)
			if nx >= 0:
				nw[nx] = float(nw.get(nx, 0.0)) + v * move
		water = {}
		for c in nw:
			if float(nw[c]) > 0.02:
				water[c] = nw[c]
	_flood_t -= dh
	if _flood_t <= 0.0:
		_flood_t = 1.0
		_flood_status(false)


## How high a river cell is running: 0 normal, 1 bank-full, more in flood.
func level(c: int) -> float:
	return float(water.get(c, 0.0)) / CAP


## Which fords are under and which banks are flooded, from the levels.
func _flood_status(quiet: bool) -> void:
	var g = w.gen
	var now_closed := {}
	var now_flooded := {}
	for c in water:
		var lv := level(c)
		if g.river[c] == 2 and (lv >= FORD_SHUT or (closed.has(c) and lv >= FORD_OPEN)):
			now_closed[c] = true
		if lv >= BANKS and g.river[c] != 0:
			# The river spills over its banks: the low ground beside it, and
			# further when it's well over.
			var reach := 1 if lv < 1.2 else 2
			var cx: int = c % Gen.SIZE
			var cy: int = c / Gen.SIZE
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var x := cx + dx
					var y := cy + dy
					if not g.inside(x, y):
						continue
					var i: int = Gen.idx(x, y)
					if g.river[i] != 0 or g.terrain[i] in [T.SEA, T.LAKE, T.MOUNTAIN, T.HILLS]:
						continue
					if g.height[i] > g.height[c] + 0.025 * reach:
						continue # (higher ground stays dry)
					now_flooded[i] = true
	if now_closed == closed and now_flooded == flooded:
		return
	var shut: Array = []
	var opened: Array = []
	for c in now_closed:
		if not closed.has(c):
			shut.append(c)
	for c in closed:
		if not now_closed.has(c):
			opened.append(c)
	var spilled := 0
	for c in now_flooded:
		if not flooded.has(c):
			spilled += 1
	for c in flooded:
		if not now_flooded.has(c):
			g.wet[c] = 0
			w.flood_cell_changed(c)
	for c in opened:
		g.wet[c] = 0
		w.flood_cell_changed(c)
	for c in now_flooded:
		if g.wet[c] != 1:
			g.wet[c] = 1
			w.flood_cell_changed(c)
	for c in now_closed:
		if g.wet[c] != 2:
			g.wet[c] = 2
			w.flood_cell_changed(c)
	closed = now_closed
	flooded = now_flooded
	flood_version += 1
	if quiet:
		return
	# News of what you can see.
	for c in shut:
		var at := {"x": c % Gen.SIZE, "y": c / Gen.SIZE}
		w._tell(Lang.t("The river is up: the ford is under brown water. Nobody crosses there until it falls."), at)
	for c in opened:
		var at2 := {"x": c % Gen.SIZE, "y": c / Gen.SIZE}
		w._tell(Lang.t("The river has gone down: the ford can be crossed again."), at2)
	if spilled > 6:
		var any: int = now_flooded.keys()[0]
		var near := -1
		var best := 9999.0
		for c in now_flooded:
			var d: float = w.pos.distance_to(Vector2(c % Gen.SIZE, c / Gen.SIZE))
			if d < best:
				best = d
				near = c
		if near < 0:
			near = any
		w._tell(Lang.t("The river has burst its banks: the low ground beside it is under water."), {"x": near % Gen.SIZE, "y": near / Gen.SIZE})


## Is this ford under water?
func ford_closed(c: Vector2i) -> bool:
	return closed.has(Gen.idx(c.x, c.y))


# ---------------------------------------------------------------- effects

## Rain washes the tracks out where it falls.
func _wash_tracks(dh: float) -> void:
	if storms.is_empty() or w.tracks.is_empty():
		return
	var keep: Array = []
	for t in w.tracks:
		var p := Vector2(float(t["x"]), float(t["y"]))
		var near := false
		for s in storms:
			if absf(p.x - float(s["x"])) < float(s["r"]) and absf(p.y - float(s["y"])) < float(s["r"]):
				near = true
				break
		if near:
			var r := rain_at(p)
			if r > 0.25 and randf() < r * dh * 1.5:
				continue
		keep.append(t)
	w.tracks = keep


## Where you are: what it's doing, and the day's tallies.
func _here(dh: float) -> void:
	var c: Vector2i = w.cell()
	var r := rain_at(w.pos)
	var f := fog_at(c)
	var ht := heat_at(c)
	if r > 0.15:
		last_rain_h = w.hours
	if r > 0.4:
		rain_hours += dh
	if ht > 0.4 and w.moving():
		heat_hours += dh
	# The powder: rain soaks it (less under canvas, in camp or covered), dry
	# air and sun dry it out again.
	if r > 0.15:
		var shelter := 0.35 if (w.camping or w.hours < covered_until) else 1.0
		# Catching rain (Company.stores.rain_catch): sailcloth spread and the
		# cover opened to funnel it into the barrels. Clean water, but the
		# rain gets at the powder too.
		var catch: bool = Company.active and bool(Company.stores.get("rain_catch", true))
		if catch:
			if not w.camping:
				shelter *= 1.4 # (on the march the sheets drip onto the powder; in camp they're rigged clear of the wagon)
			var room := float(Company.WATER_CART - int(Company.stores.get("water", 0)))
			var got := minf(room, r * dh * 8.0)
			if got > 0.0:
				_catch_acc += got
				var whole := int(_catch_acc)
				if whole > 0:
					_catch_acc -= whole
					Company.stores["water"] = int(Company.stores["water"]) + whole
					caught += whole
					if int(Company.stores["water"]) >= Company.WATER_CART / 2:
						Company.stores["foul"] = false # (fresh rain over what was there)
		damp = minf(1.0, damp + r * dh * 0.3 * shelter)
	else:
		damp = maxf(0.0, damp - dh * (0.04 + 0.12 * ht))
	# Lightning near the camp at night.
	if w.camping and r > 0.55 and thunder_at(w.pos) and randf() < 0.06 * dh:
		_ask("lightning")
	var now := ""
	if r > 0.55 and thunder_at(w.pos):
		now = "storm"
	elif r > 0.15:
		now = "rain"
	elif f > 0.35:
		now = "fog"
	elif ht > 0.45:
		now = "heat"
	if now != state:
		var was := state
		state = now
		var text := ""
		match now:
			"storm":
				text = Lang.t("A storm breaks over you: thunder, and rain in sheets. Keep the powder dry.")
			"rain":
				text = Lang.t("Rain, blowing in on the wind.") if was != "storm" else Lang.t("The thunder rolls on inland. Still raining.")
			"fog":
				text = Lang.t("Fog lies in the low ground. You can hardly see the wagon from the head of the column.")
			"heat":
				text = Lang.t("The heat comes up off the ground. The men drink and drink.")
			"":
				text = Lang.t("The rain stops.") if was in ["rain", "storm"] else (Lang.t("The fog lifts.") if was == "fog" else Lang.t("The heat goes out of the day."))
		if text != "":
			w.log.append("%s  %s" % [w.clock(), text])
			w.news.emit(text)
		# On the march, the weather can ask you something (events.gd).
		if w.moving() and not w.camping:
			match now:
				"storm":
					_ask("squall")
				"fog":
					if f > 0.55:
						_ask("fog")
				"heat":
					if ht > 0.6:
						_ask("heatwave")


## A weather pop-up, once in a while for each kind (World.advance asks it).
func _ask(id: String) -> void:
	if w.hours - float(_last_event.get(id, -999.0)) < 30.0:
		return
	_last_event[id] = w.hours
	pending_event = id


## Rain on your work parties: the hours of it today, by post.
func _sites_tick(dh: float) -> void:
	_site_t += dh
	if _site_t < 1.0 or storms.is_empty() or not Company.active:
		_site_t = minf(_site_t, 1.0)
		return
	_site_t -= 1.0
	for key in Company.posts:
		var r: Dictionary = w.resource(int(key))
		if r.is_empty():
			continue
		var rn := rain_at(Vector2(float(r["x"]), float(r["y"])) + Vector2(0.5, 0.5))
		if rn > 0.2:
			site_rain[str(key)] = float(site_rain.get(str(key), 0.0)) + rn


## How much work a site gets done today for the rain on it (and the catch
## after rain is better). Takes the day's tally away.
func site_work(key: String, kind: String) -> float:
	var h := float(site_rain.get(key, 0.0))
	site_rain.erase(key)
	if kind == "fish":
		return 1.0 + minf(0.3, h * 0.03) # (fish bite after rain)
	if kind in ["charcoal", "saltpetre", "sulphur", "farm"]:
		return maxf(0.2, 1.0 - h * 0.08) # (a pit, a bed, a field: rain stops it)
	return maxf(0.5, 1.0 - h * 0.04)


## The weather where a battle is fought, for battle.gd: rain, fog, heat, a
## storm overhead, and how damp the company's powder is.
func battle_weather() -> Dictionary:
	var c: Vector2i = w.cell()
	var r := rain_at(w.pos)
	return {"rain": r, "fog": fog_at(c), "heat": heat_at(c), "storm": r > 0.55 and thunder_at(w.pos),
		"damp": clampf(maxf(damp, r * 0.6), 0.0, 1.0)}


## The day ends: hand the tallies to the march (World._midnight).
func end_day() -> Dictionary:
	var out := {"rain": rain_hours, "heat": heat_hours}
	rain_hours = 0.0
	heat_hours = 0.0
	return out


## How far you see, as a share of what you would.
func sight_mult() -> float:
	var r := rain_at(w.pos)
	var f := fog_at(w.cell())
	return (1.0 - 0.45 * r) * (1.0 - 0.75 * f)


## The march's pace, as a share.
func pace_mult() -> float:
	return (1.0 - 0.3 * rain_at(w.pos)) * (1.0 - 0.15 * heat_at(w.cell()))


## A word or two for the HUD.
func words() -> String:
	match state:
		"storm":
			return Lang.t("Storm")
		"rain":
			return Lang.t("Rain")
		"fog":
			return Lang.t("Fog")
		"heat":
			return Lang.t("Heat")
	return ""
