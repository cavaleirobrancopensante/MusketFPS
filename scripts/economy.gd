extends RefCounted
## The land's economy: what each settlement has in its stores, and the
## people and carts that move it about (World.econ, ticked from world.gd).
##
## Raw goods are won at the sites on the map (world_gen.gd gives every
## village its fields and a pit, wood or water, a dwarf hold its mines):
## a village sends its LABOURERS out to a site; they work it for a day and
## come home with what they got. When the village has more than it needs,
## its VILLAGERS take the surplus to market in the nearest towns. Towns and
## cities REFINE it (lead from ore, powder from saltpetre, sulphur and
## charcoal, tools at the smithy, bread and smoked meat, arrows), and their
## CARAVANS carry what they have spare to the other towns; dwarf TRADERS
## bring the holds' powder, lead and tools. Everyone eats.
##
## The lizards have their own: HUNTING PARTIES bring meat (and hides) back
## to the nest, WARBANDS carry off what a raided village had stored. A nest
## with meat in it sends out bigger warbands; its plunder is yours if you
## burn it, and a party you beat drops what it carried.
##
## A settlement's stores set its market (company.gd market_offers): plenty
## is cheap, scarce is dear, none is none, and towns pay for the raw goods
## they're short of.

const RAW := ["grain", "meat", "wood", "charcoal", "ore", "saltpetre", "sulphur"]
const MADE := ["rations", "lead", "powder", "tools", "arrows"]
const NEST_GOODS := ["meat", "hides", "plunder"]
## How much of each a town wants in store (x SIZE): below it the price
## climbs, above it it falls.
const WANT := {"grain": 40, "meat": 16, "wood": 30, "charcoal": 30, "ore": 30, "saltpetre": 30, "sulphur": 10,
	"rations": 60, "lead": 24, "powder": 12, "tools": 6, "arrows": 60}
const SIZE := {"village": 0.5, "town": 1.0, "city": 2.0, "hold": 1.0, "nest": 1.0}
## What each kind of place makes: [needs, makes, kinds that do it].
const REFINE := [
	[{"ore": 6, "charcoal": 3}, {"lead": 4}, ["town", "city", "hold"]],
	[{"saltpetre": 8, "charcoal": 2, "sulphur": 1}, {"powder": 10}, ["city", "hold"]],
	[{"grain": 6, "wood": 1}, {"rations": 8}, ["village", "town", "city"]],
	[{"meat": 6, "charcoal": 1}, {"rations": 6}, ["village", "town", "city"]],
	[{"ore": 2, "charcoal": 2, "wood": 2}, {"tools": 1}, ["town", "city", "hold"]],
	[{"wood": 2}, {"arrows": 20}, ["village", "town"]],
]
const BATCHES := {"village": 1, "town": 2, "city": 4, "hold": 3}
## Rations eaten a day (grain when the rations run out).
const EAT := {"village": 1, "town": 3, "city": 6, "hold": 2}
## A starting store, as a share of WANT.
const START := 0.7
const LOT := 10 # the market sells raw goods ten at a time
## A market's base price for a lot of LOT of each raw good (crowns).
const RAW_PRICE := {"grain": 3, "meat": 3, "wood": 2, "charcoal": 3, "ore": 4, "saltpetre": 5, "sulphur": 6}
## Market items that come out of a town's "tools" store.
const TOOL_ITEMS := ["pickaxe", "shovel", "axe", "fishing_rod"]
## What a site's labourers bring home per worker-day (World.RESOURCES "daily" x this).
const LABOUR_RATE := 2.0


static func _w():
	return Engine.get_main_loop().root.get_node("World")


## A settlement's stores ({} for a burned place): {good: float}.
static func stock(sid: int) -> Dictionary:
	var W = _w()
	var k := str(sid)
	if not W.econ.has(k):
		var st: Dictionary = W.settlement(sid)
		var s := {}
		if st["kind"] == "nest":
			s = {"meat": 30.0, "hides": 6.0, "plunder": 10.0}
		else:
			var size: float = SIZE.get(String(st["kind"]), 1.0)
			for g in WANT:
				s[g] = float(WANT[g]) * size * START * randf_range(0.5, 1.2)
			if st["kind"] == "village":
				for g in ["lead", "powder", "saltpetre", "sulphur"]:
					s[g] = 0.0
			elif st["kind"] == "town":
				s["powder"] = 0.0
		W.econ[k] = s
	return W.econ[k]


static func have(sid: int, good: String) -> int:
	return int(floor(float(stock(sid).get(good, 0.0))))


static func add(sid: int, good: String, n: float) -> void:
	var s := stock(sid)
	s[good] = maxf(0.0, float(s.get(good, 0.0)) + n)


static func want(sid: int, good: String) -> float:
	var st: Dictionary = _w().settlement(sid)
	return float(WANT.get(good, 10)) * float(SIZE.get(String(st["kind"]), 1.0))


## How dear `good` is here: 0.6 (glutted) to 1.8 (none to spare).
static func price_mult(sid: int, good: String) -> float:
	var w := maxf(1.0, want(sid, good))
	var h := float(stock(sid).get(good, 0.0))
	return clampf(1.8 - 1.2 * h / w, 0.6, 1.8)


## A day in every settlement: they make what they can and eat. The
## nations' armies and patrols eat from their home's stores; an army that
## can't be fed loses men to hunger and desertion.
static func day() -> void:
	var W = _w()
	for p in W.parties:
		if not p["kind"] in ["army", "patrol"] or int(p.get("home", -1)) < 0:
			continue
		var home := int(p["home"])
		if W.settlement(home).get("faction", "") != p["faction"]:
			continue # (its home has fallen: it lives off the land)
		var need := float(p["size"]) * (0.12 if p["kind"] == "army" else 0.06)
		var s0 := stock(home)
		var got := minf(need, float(s0.get("rations", 0.0)))
		s0["rations"] = float(s0.get("rations", 0.0)) - got
		if got < need * 0.5 and int(p["size"]) > 6:
			p["size"] = int(p["size"]) - maxi(1, int(p["size"]) / 20)
	for st in W.gen.settlements:
		var sid := int(st["id"])
		var kind := String(st["kind"])
		if kind == "nest":
			if W.nest_destroyed(sid):
				continue
			add(sid, "meat", -3.0)
			continue
		if W.is_raided(sid):
			continue
		var s := stock(sid)
		# Gardens and goats: a little food however the fields are going.
		if kind == "village":
			add(sid, "grain", 2.0)
		for r in REFINE:
			if not kind in r[2]:
				continue
			var out_good: String = (r[1] as Dictionary).keys()[0]
			for b in int(BATCHES.get(kind, 1)):
				if float(s.get(out_good, 0.0)) >= want(sid, out_good) * 1.6:
					break
				var ok := true
				for g in r[0]:
					if float(s.get(g, 0.0)) < float(r[0][g]):
						ok = false
						break
				if not ok:
					break
				for g in r[0]:
					s[g] = float(s[g]) - float(r[0][g])
				for g in r[1]:
					s[g] = float(s.get(g, 0.0)) + float(r[1][g])
		var eat := float(EAT.get(kind, 1))
		var from_r := minf(eat, float(s.get("rations", 0.0)))
		s["rations"] = float(s.get("rations", 0.0)) - from_r
		s["grain"] = maxf(0.0, float(s.get("grain", 0.0)) - (eat - from_r))
		s["tools"] = float(s.get("tools", 0.0)) * 0.97 # (they wear out)
		s["arrows"] = float(s.get("arrows", 0.0)) * 0.97 # (the militia's butts and the hunters)
		# Glutted: what's far beyond need rots, rusts or is sold on downriver.
		for g in s:
			var cap := want(sid, String(g)) * 3.0
			if float(s[g]) > cap:
				s[g] = float(s[g]) - (float(s[g]) - cap) * 0.15


# ---------------------------------------------------------------- the people on the roads

## The sites a settlement works.
static func sites_of(sid: int) -> Array:
	return _w().gen.resources.filter(func(r): return int(r.get("owner", -1)) == sid and r["kind"] != "spring")


## Each day: villages (and towns and holds with sites of their own) send
## out their labourers; villages with a surplus send it to market.
static func spawn(st: Dictionary, initial: bool) -> void:
	var W = _w()
	var sid := int(st["id"])
	var kind := String(st["kind"])
	if not kind in ["village", "town", "hold"] or W.is_raided(sid):
		return
	var sites := sites_of(sid)
	var cap := 1 if kind == "village" else 2
	if not sites.is_empty() and W._count("labourers", "", sid) < cap and (initial or randf() < 0.7):
		var r: Dictionary = sites.pick_random()
		var p: Dictionary = W._new_party("labourers", String(st["faction"]), randi_range(3, 6), st)
		p["site"] = int(r["id"])
		p["stage"] = "out"
		p["cargo"] = {}
		p["path"] = W._route(Vector2(p["x"], p["y"]), Vector2(r["x"], r["y"]) + Vector2(0.5, 0.5))
	if kind == "village" and W._count("villagers", "", sid) < 1 and surplus_size(sid, RAW + ["arrows"]) >= 10 \
			and (initial or randf() < 0.5):
		var v: Dictionary = W._new_party("villagers", String(st["faction"]), randi_range(3, 6), st)
		v["cargo"] = take_surplus(sid, RAW + ["arrows"], 50)


static func surplus_size(sid: int, goods: Array) -> int:
	var n := 0.0
	for g in goods:
		n += maxf(0.0, float(stock(sid).get(g, 0.0)) - want(sid, g) * 0.6)
	return int(n)


## Load what this place has spare of `goods` (up to `cap` in all).
static func take_surplus(sid: int, goods: Array, cap: int) -> Dictionary:
	var out := {}
	var left := float(cap)
	for g in goods:
		var spare := floorf(float(stock(sid).get(g, 0.0)) - want(sid, g) * 0.6)
		if spare <= 0.0 or left <= 0.0:
			continue
		var k := minf(spare, left)
		add(sid, g, -k)
		out[g] = k
		left -= k
	return out


static func unload(sid: int, p: Dictionary) -> void:
	var c: Dictionary = p.get("cargo", {})
	for g in c:
		add(sid, String(g), float(c[g]))
	p["cargo"] = {}


## What a caravan or traders take from a town for the next one: what it
## made, and what it has too much of.
static func load_caravan(sid: int, p: Dictionary) -> void:
	var c: Dictionary = p.get("cargo", {})
	var got := take_surplus(sid, MADE + RAW, 60)
	for g in got:
		c[g] = float(c.get(g, 0.0)) + float(got[g])
	p["cargo"] = c


## A labour party's day: out to the site, a day's work there, home with it.
static func labourers_errand(p: Dictionary, me: Vector2) -> void:
	var W = _w()
	var home: Dictionary = W.settlement(int(p["home"]))
	var r: Dictionary = W.resource(int(p.get("site", -1)))
	match String(p.get("stage", "out")):
		"out":
			if r.is_empty():
				p["stage"] = "home"
			else:
				p["stage"] = "work"
				p["wait"] = randf_range(8.0, 14.0)
				var spec: Dictionary = W.RESOURCES.get(String(r["kind"]), {})
				var store := String(spec.get("store", "grain"))
				var n: float = float(spec.get("daily", 0.4)) * float(p["size"]) * LABOUR_RATE * randf_range(0.7, 1.3) * W.season_yield(String(r["kind"]))
				var c: Dictionary = p["cargo"]
				c[store] = float(c.get(store, 0.0)) + n
				for k in spec.get("also", {}):
					c[k] = float(c.get(k, 0.0)) + n
		"work":
			p["stage"] = "home"
			p["path"] = W._route(me, Vector2(home["x"], home["y"]) + Vector2(0.5, 0.5))
		"home":
			if me.distance_to(Vector2(home["x"], home["y"]) + Vector2(0.5, 0.5)) < 2.5:
				unload(int(p["home"]), p)
				W.parties.erase(p)
			else:
				p["path"] = W._route(me, Vector2(home["x"], home["y"]) + Vector2(0.5, 0.5))
				if (p["path"] as Array).is_empty():
					W.parties.erase(p)


## A nest feeds its warriors: the meat in it makes the next warband bigger.
static func nest_feed(sid: int) -> int:
	var m := float(stock(sid).get("meat", 0.0))
	if m < 8.0:
		return -3 # (hungry: fewer go out)
	var extra := mini(8, int(m / 12.0))
	add(sid, "meat", -extra * 12.0)
	return extra


## Lizards hunting: a leg's kill (meat, a hide now and then).
static func hunt_leg(p: Dictionary) -> void:
	var c: Dictionary = p.get("cargo", {})
	c["meat"] = float(c.get("meat", 0.0)) + float(p["size"]) * randf_range(1.5, 4.0)
	if randf() < 0.5:
		c["hides"] = float(c.get("hides", 0.0)) + 1.0
	p["cargo"] = c


## A warband raids a village: it carries off half of what's in the stores.
static func plunder(p: Dictionary, sid: int) -> void:
	var c: Dictionary = p.get("cargo", {})
	var s := stock(sid)
	var worth := 0.0
	for g in s:
		var k := floorf(float(s[g]) * 0.5)
		if k <= 0.0:
			continue
		s[g] = float(s[g]) - k
		if g in ["grain", "meat", "rations"]:
			c["meat"] = float(c.get("meat", 0.0)) + k * 0.5 # (they eat it, or carry it off)
		worth += k * 0.15
	c["plunder"] = float(c.get("plunder", 0.0)) + worth
	p["cargo"] = c


## The cargo of a party you've beaten (or a burned nest's stores), as loot
## for the loot screen: [[id, n]].
static func as_loot(c: Dictionary) -> Array:
	var out: Array = []
	for g in c:
		var n := int(floor(float(c[g])))
		if n <= 0:
			continue
		match String(g):
			"plunder":
				out.append(["crowns", n])
			"hides":
				out.append(["hide", n])
			"tools":
				for i in n:
					out.append([TOOL_ITEMS.pick_random(), 1])
			_:
				out.append([String(g), n])
	return out


## "ore and charcoal" — what a party is carrying, for its label.
static func cargo_words(c: Dictionary) -> String:
	var bits: Array = []
	var keys := c.keys()
	keys.sort_custom(func(a, b): return float(c[a]) > float(c[b]))
	for g in keys.slice(0, 2):
		if float(c[g]) >= 1.0:
			bits.append(good_name(String(g)))
	return Lang.t(" and ").join(bits)


static func good_name(g: String) -> String:
	match g:
		"grain": return Lang.t("grain")
		"meat": return Lang.t("meat")
		"wood": return Lang.t("timber")
		"charcoal": return Lang.t("charcoal")
		"ore": return Lang.t("ore")
		"saltpetre": return Lang.t("saltpetre")
		"sulphur": return Lang.t("sulphur")
		"rations": return Lang.t("food")
		"lead": return Lang.t("lead")
		"powder": return Lang.t("powder")
		"tools": return Lang.t("tools")
		"arrows": return Lang.t("arrows")
		"hides": return Lang.t("hides")
		"plunder": return Lang.t("plunder")
	return g


## The stores, in a line ("grain 34 · ore 12 · ...").
static func stock_line(sid: int) -> String:
	var bits: Array = []
	var s := stock(sid)
	var seen := {}
	for g in RAW + MADE + NEST_GOODS:
		if seen.has(g):
			continue
		seen[g] = true
		if s.has(g) and float(s[g]) >= 1.0:
			bits.append("%s %d" % [good_name(g), int(s[g])])
	return "  ·  ".join(bits) if not bits.is_empty() else Lang.t("empty")


# ---------------------------------------------------------------- the market

## The store a market offer comes out of ("" if it doesn't).
static func good_of(item: String) -> String:
	if item in TOOL_ITEMS:
		return "tools"
	if item in ["rations", "lead", "powder", "arrows"] + RAW:
		return item
	return ""


## Fit a market's offers to its stores: dearer when short, cheaper when
## glutted, gone when there's none. Raw goods it has plenty of are for sale
## too.
static func adjust_offers(sid: int, offers: Array) -> Array:
	var out: Array = []
	for o in offers:
		var g := good_of(String(o[0]))
		if g == "":
			out.append(o)
			continue
		var need := 1 if g == "tools" else int(o[1])
		if have(sid, g) < need:
			continue
		var q: Array = o.duplicate()
		q[2] = maxi(1, int(round(int(o[2]) * price_mult(sid, g))))
		out.append(q)
	for g in RAW:
		if have(sid, g) >= LOT * 2 and float(stock(sid)[g]) > want(sid, g) * 0.8:
			out.append([g, LOT, maxi(1, int(round(RAW_PRICE[g] * price_mult(sid, g)))), Lang.t("%d lb of %s") % [LOT, good_name(g)]])
	return out


## Bought: it comes out of their stores.
static func bought(sid: int, item: String, n: int) -> void:
	var g := good_of(item)
	if g != "":
		add(sid, g, -float(1 if g == "tools" else n))


## What they'll pay for a lot of your `good` (0: they won't buy it).
static func sell_price(sid: int, good: String) -> int:
	if not RAW_PRICE.has(good) and not good in ["lead", "powder"]:
		return 0
	var base := float(RAW_PRICE.get(good, 8 if good == "lead" else 20))
	var m := price_mult(sid, good)
	return maxi(1, int(round(base * m * 0.7 * Company.Officer.sell_mult()))) # (your Trade gets you more)


# ---------------------------------------------------------------- trading on the road

## What a party carrying goods will sell you: [good, lot, crowns]. Traders
## on the road ask a little more than a market (they've carried it).
const ROAD_LOT := {"rations": 10, "lead": 5, "powder": 1, "arrows": 20, "tools": 1, "hides": 1}
const ROAD_PRICE := {"rations": 6, "lead": 7, "powder": 26, "arrows": 4, "tools": 7, "hides": 4}


static func road_offers(p: Dictionary) -> Array:
	var out: Array = []
	var c: Dictionary = p.get("cargo", {})
	for g in c:
		var lot: int = int(ROAD_LOT.get(g, LOT))
		if float(c[g]) < lot or g == "plunder":
			continue
		var base: int = int(ROAD_PRICE.get(g, RAW_PRICE.get(g, 3)))
		out.append([String(g), lot, int(round(base * 1.15))])
	return out


## Buy a lot from a party's cargo: into the wagon (a tool as one of the
## tool items). Returns "" or why not.
static func buy_from_party(p: Dictionary, offer: Array) -> String:
	var g := String(offer[0])
	var n := int(offer[1])
	var cr: int = Company.price(int(offer[2]))
	if Company.money < cr:
		return Lang.t("Not enough crowns.")
	var id := g
	if g == "tools":
		id = TOOL_ITEMS.pick_random()
	elif g == "hides":
		id = "hide"
	if Company.room_for(id) < n:
		return Lang.t("The wagon is full.")
	Company.money -= cr
	Company.stow(id, n)
	p["cargo"][g] = float(p["cargo"][g]) - n
	Company.save()
	return ""


## What a party will pay for a lot of your raw goods (they trade them on).
static func road_sell_price(good: String) -> int:
	if not RAW_PRICE.has(good):
		return 0
	return maxi(1, int(round(RAW_PRICE[good] * 0.6 * Company.Officer.sell_mult())))


static func sell_to_party(p: Dictionary, good: String) -> int:
	var cr := road_sell_price(good)
	if cr <= 0 or int(Company.stores.get(good, 0)) < LOT:
		return 0
	Company.stores[good] = int(Company.stores[good]) - LOT
	var c: Dictionary = p.get("cargo", {})
	c[good] = float(c.get(good, 0.0)) + LOT
	p["cargo"] = c
	Company.money += cr
	Company.save()
	return cr
