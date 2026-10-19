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


func to_dict() -> Dictionary:
	return {"storms": storms, "next_id": next_id, "rain_hours": rain_hours, "heat_hours": heat_hours,
		"last_rain_h": last_rain_h, "state": state}


func from_dict(d: Dictionary) -> void:
	storms = d.get("storms", [])
	next_id = int(d.get("next_id", 1))
	rain_hours = float(d.get("rain_hours", 0.0))
	heat_hours = float(d.get("heat_hours", 0.0))
	last_rain_h = float(d.get("last_rain_h", -99.0))
	state = String(d.get("state", ""))


func clear() -> void:
	storms.clear()
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
	_wash_tracks(dh)
	_here(dh)


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
