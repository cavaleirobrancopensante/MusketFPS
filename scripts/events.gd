extends RefCounted
## Things that happen on the road, picked by where you are.
##
## While the company marches, World rolls for an event every hour once a
## cooldown has passed (World.EVENT_CHANCE). `pick` weighs every event by
## the place: the ground underfoot, whose land it is, a river or the sea
## nearby, night. The map shows the event with its choices; `resolve` works
## out what happens and returns the text to show.
##
## To add an event: a row in TABLE (id, title, text, options) and a branch
## in `_weight` (where it can happen) and `resolve` (what each choice does).

const Gen := preload("res://scripts/world_gen.gd")
const Men := preload("res://scripts/men.gd")
const Lore := preload("res://scripts/lore.gd")
const T := Gen.T

const TABLE := {
	"wreckage": ["Wreckage on the shore",
		"Barrels and splintered crates lie in the surf. One is stencilled with the %s's mark." % Lore.SHIP,
		[["SALVAGE (3 h)", "salvage"], ["LEAVE IT", "leave"]]],
	"game": ["Game in the trees",
		"Fresh tracks, and a glimpse of something like a deer, but with too many horns.",
		[["HUNT (3 h)", "hunt"], ["HUNT YOURSELF", "self"], ["MARCH ON", "leave"]]],
	"berries": ["Bushes heavy with berries",
		"Fat purple berries the men have never seen before. They smell sweet.",
		[["EAT THEM", "eat"], ["LEAVE THEM", "leave"]]],
	"lost": ["A man is missing",
		"At the halt, a man doesn't answer his name. He was last seen at the back of the column.",
		[["SEARCH (4 h)", "search"], ["MARCH ON", "leave"]]],
	"ruins": ["Ruins of an older people",
		"Moss-covered stones, a fallen tower, carvings worn smooth. Nobody here built this.",
		[["SEARCH (2 h)", "search"], ["PASS BY", "leave"]]],
	"fever": ["Fever mist",
		"A warm white mist rises off the swamp at dusk. The men are coughing.",
		[["PRESS ON", "on"]]],
	"bog": ["The wagon sinks",
		"The wagon is up to its axles in black mud.",
		[["DIG IT OUT (5 h)", "dig"], ["LIGHTEN THE LOAD", "lighten"]]],
	"spoor": ["Lizard tracks",
		"Clawed prints, many of them, fresh. They lead off through the reeds.",
		[["FOLLOW THEM", "follow"], ["GO THE OTHER WAY", "leave"]]],
	"ambush": ["Ambush!",
		"Hissing in the undergrowth on every side. They've been waiting for you.",
		[["FORM UP!", "fight"]]],
	"farmer": ["A farmer with a cart",
		"An old man with a cart of turnips and salted meat. He stares at your muskets.",
		[["BUY 12 FOOD (5 cr)", "buy"], ["LEAVE", "leave"]]],
	"pedlar": ["A pedlar on the road",
		"A pedlar with a mule, selling everything from needles to spirits.",
		[["BUY 10 RUM (7 cr)", "rum"], ["BUY 10 FOOD (5 cr)", "food"], ["LEAVE", "leave"]]],
	"refugees": ["Refugees",
		"A family pulling a handcart, all they own on it. The lizards burned their village.",
		[["SHARE FOOD (8)", "share"], ["TURN THEM AWAY", "leave"]]],
	"deserters": ["Deserters from the war",
		"Three soldiers who've had enough of the war. For a few coins they'll tell you the lie of the land.",
		[["PAY THEM (10 cr)", "pay"], ["SEND THEM OFF", "leave"]]],
	"vantage": ["A high crag",
		"A crag rises above the land around. From the top you could see for leagues.",
		[["CLIMB IT (2 h)", "climb"], ["MARCH ON", "leave"]]],
	"fishing": ["A river full of fish",
		"The water is clear and full of fish. The men look at it hungrily.",
		[["FISH (3 h)", "fish"], ["MARCH ON", "leave"]]],
	"flood": ["The river has risen",
		"Rain upstream: the ford is a brown torrent.",
		[["WAIT (6 h)", "wait"], ["CROSS NOW", "cross"]]],
	"camp": ["An abandoned camp",
		"Cold ashes, a torn tent, bootprints going nowhere in particular.",
		[["SEARCH", "search"], ["LEAVE", "leave"]]],
	"prospectors": ["Dwarf prospectors",
		"Three dwarves with picks and a pony. They want, very much, to look at your muskets.",
		[["SHOW THEM", "show"], ["MOVE ON", "leave"]]],
}


var _last := {} # event id -> hours when it last happened


## Choose an event for where the company is now, or {} for none.
func pick(w) -> Dictionary:
	var ctx := _context(w)
	var total := 0.0
	var weights := {}
	for id in TABLE:
		if _last.has(id) and float(w.hours) - float(_last[id]) < 36.0:
			continue # not the same thing twice in a day and a half
		var wt := _weight(id, ctx)
		if id in ["game", "berries"] and float(w.hours) < 24.0 * 12.0:
			wt *= 3.0 # (the first fortnight: the land is full of food for whoever looks)
		if wt > 0.0:
			weights[id] = wt
			total += wt
	if total <= 0.0:
		return {}
	var r := randf() * total
	for id in weights:
		r -= weights[id]
		if r <= 0.0:
			var row: Array = TABLE[id]
			_last[id] = w.hours
			return {"id": id, "title": Lang.t(row[0]), "text": Lang.t(row[1]), "options": (row[2] as Array).map(func(o): return [Lang.t(o[0]), o[1]])}
	return {}


func _context(w) -> Dictionary:
	var c: Vector2i = w.cell()
	var g = w.gen
	var i: int = Gen.idx(c.x, c.y)
	var near_sea := false
	var near_river := false
	for dy in range(-5, 6, 2):
		for dx in range(-5, 6, 2):
			if not g.inside(c.x + dx, c.y + dy):
				continue
			var j: int = Gen.idx(c.x + dx, c.y + dy)
			if g.terrain[j] == T.SEA:
				near_sea = true
			if g.river[j] != 0 or g.terrain[j] == T.LAKE:
				near_river = true
	return {"t": g.terrain[i], "region": g.region[i], "road": g.road[i], "ford": g.river[i] == 2,
		"sea": near_sea, "river": near_river, "night": w.is_night(),
		"wreck_dist": Vector2(c).distance_to(Vector2(g.wreck)), "men": Company.roster.size()}


func _weight(id: String, x: Dictionary) -> float:
	var t: int = x["t"]
	var human: bool = x["region"] == 1 or x["region"] == 2
	var lizard: bool = x["region"] == 4
	match id:
		"wreckage":
			return 3.0 if x["sea"] and x["wreck_dist"] < 90.0 else 0.0
		"game":
			return 1.5 if t in [T.FOREST, T.PLAINS, T.HILLS] else 0.0
		"berries":
			return 1.0 if t in [T.FOREST, T.SWAMP] else 0.0
		"lost":
			return 0.7 if t in [T.FOREST, T.SWAMP] and x["men"] > 4 else 0.0
		"ruins":
			return 0.8 if t in [T.FOREST, T.HILLS, T.PLAINS] else 0.0
		"fever":
			return 1.5 if t == T.SWAMP else 0.0
		"bog":
			return 1.0 if t == T.SWAMP else 0.0
		"spoor":
			return 1.5 if lizard else 0.0
		"ambush":
			return (0.6 if x["night"] else 0.3) if lizard and t in [T.FOREST, T.SWAMP] else 0.0
		"farmer":
			return 1.5 if human and t == T.PLAINS else 0.0
		"pedlar":
			return 1.2 if human and x["road"] > 0 else 0.0
		"refugees":
			return 0.8 if human else 0.0
		"deserters":
			return 0.8 if human else 0.0
		"vantage":
			return 1.5 if t in [T.HILLS, T.MOUNTAIN] else 0.0
		"fishing":
			return 1.2 if x["river"] else 0.0
		"flood":
			return 1.5 if x["ford"] else 0.0
		"camp":
			return 0.6
		"prospectors":
			return 1.2 if x["region"] == 3 or t == T.MOUNTAIN else 0.0
	return 0.0


# ---------------------------------------------------------------- outcomes

## What happens. Returns the text to show; may also start a fight
## ({"text", "fight": party}).
func resolve(w, id: String, key: String) -> Dictionary:
	var st: Dictionary = Company.stores
	match id:
		"wreckage":
			if key == "salvage":
				w.pass_hours(3.0)
				var shot := randi_range(20, 50)
				var rum := randi_range(5, 15)
				st["ammo"] = int(st["ammo"]) + shot
				st["rum"] = int(st["rum"]) + rum
				var more := ""
				if randf() < 0.4:
					Company.add_item("musket", 1)
					more = Lang.t(" and a musket, wrapped in oilcloth")
				return _done(Lang.t("Cartridges that stayed dry (%d), a keg of rum (%d tots)%s.") % [shot, rum, more])
		"game":
			if key == "hunt":
				w.pass_hours(3.0)
				var aim := _avg("aim")
				if randf() < 0.35 + 0.05 * aim:
					var food := randi_range(10, 25)
					st["rations"] = int(st["rations"]) + food
					_morale(2)
					return _done(Lang.t("A good kill: %d rations of strange, gamey meat. The men eat well tonight.") % food)
				return _done(Lang.t("Three hours in the trees and nothing to show for it."))
		"berries":
			if key == "eat":
				st["rations"] = int(st["rations"]) + 8
				if randf() < 0.35:
					var n := _sicken(randi_range(1, 3))
					return _done(Lang.t("Sweet... and then the cramps. %d men are sick.") % n)
				return _done(Lang.t("Sweet and filling: 8 rations' worth."))
		"lost":
			var m := _random_man()
			if m.is_empty():
				return _done(Lang.t("A false alarm."))
			if key == "search":
				w.pass_hours(4.0)
				if randf() < 0.75:
					_morale(2)
					return _done(Lang.t("You find %s sitting on a log with a twisted ankle. The men cheer.") % Company.title(m))
			_lose(m, Lang.t("lost on the march"))
			_morale(-6 if key == "leave" else -2)
			return _done(Lang.t("%s is never seen again.") % Company.title(m))
		"ruins":
			if key == "search":
				w.pass_hours(2.0)
				var r := randf()
				if r < 0.45:
					var coins := randi_range(15, 60)
					Company.money += coins
					return _done(Lang.t("Under a fallen lintel: a clay pot of old coins, %d crowns' worth.") % coins)
				if r < 0.7:
					var m2 := _random_man()
					if not m2.is_empty():
						m2["wounded_days"] = maxi(1, int(round(randi_range(3, 6) * Company.Officer.wound_mult())))
						return _done(Lang.t("A floor gives way. %s is hurt in the fall.") % Company.title(m2))
				w._reveal(w.pos, 35.0)
				return _done(Lang.t("Nothing of value, but from the top of the tower you can see far across the land."))
		"fever":
			var men: int = Company.roster.size()
			if bool(st["grog"]) and int(st["rum"]) >= men:
				st["rum"] = int(st["rum"]) - men
				return _done(Lang.t("Grog all round keeps the fever off (%d tots of rum).") % men)
			var n2 := _sicken(randi_range(1, 3))
			return _done(Lang.t("%d men come down with fever.") % n2)
		"bog":
			if key == "dig":
				w.pass_hours(5.0)
				return _done(Lang.t("Five hours of mud, but the wagon is out with everything on it."))
			var lost := int(st["rations"]) / 4
			st["rations"] = int(st["rations"]) - lost
			return _done(Lang.t("You throw off %d rations and the wagon comes free.") % lost)
		"spoor":
			if key == "follow":
				var p: Dictionary = w.spawn_near("warband", "lizards", w.warband_size(w.day()), 7.0)
				return _done(Lang.t("Through the reeds: a warband of %d, resting. They haven't seen you... yet.") % int(p["size"]))
		"ambush":
			var p2: Dictionary = w.spawn_near("hunters", "lizards", randi_range(5, 10), 0.6)
			return {"text": "", "fight": p2}
		"farmer":
			if key == "buy":
				if Company.money >= 5:
					Company.money -= 5
					st["rations"] = int(st["rations"]) + 12
					return _done(Lang.t("12 rations for 5 crowns. He bites the coins."))
				return _done(Lang.t("You can't afford it."))
		"pedlar":
			if key == "rum" and Company.money >= 7:
				Company.money -= 7
				st["rum"] = int(st["rum"]) + 10
				return _done(Lang.t("10 tots of something that is probably rum."))
			if key == "food" and Company.money >= 5:
				Company.money -= 5
				st["rations"] = int(st["rations"]) + 10
				return _done(Lang.t("10 rations of hard bread and sausage."))
			if key != "leave":
				return _done(Lang.t("You can't afford it."))
		"refugees":
			if key == "share":
				st["rations"] = maxi(0, int(st["rations"]) - 8)
				_morale(3)
				return _done(Lang.t("They weep and bless you. The men stand a little straighter."))
			_morale(-2)
			return _done(Lang.t("They watch you go. Some of the men don't meet their eyes."))
		"deserters":
			if key == "pay":
				if Company.money < 10:
					return _done(Lang.t("You can't afford it."))
				Company.money -= 10
				var told: Array = []
				for s2 in w.gen.settlements:
					if s2["kind"] in ["town", "city"] and not bool(w.places[int(s2["id"])]["known"]):
						told.append(s2)
				told.sort_custom(func(a, b): return Vector2(a["x"], a["y"]).distance_to(w.pos) < Vector2(b["x"], b["y"]).distance_to(w.pos))
				var names: Array = []
				for s3 in told.slice(0, 3):
					w._reveal(Vector2(s3["x"], s3["y"]), 10.0)
					names.append(s3["name"])
				return _done(Lang.t("They draw in the dirt: the roads to %s.") % (", ".join(names) if names.size() > 0 else Lang.t("places you already know")))
		"vantage":
			if key == "climb":
				w.pass_hours(2.0)
				w._reveal(w.pos, 40.0)
				return _done(Lang.t("From the top the land is laid out below you like a map."))
		"fishing":
			if key == "fish":
				w.pass_hours(3.0)
				var fish := randi_range(6, 14)
				st["rations"] = int(st["rations"]) + fish
				return _done(Lang.t("%d rations of fish, cleaned and smoked.") % fish)
		"flood":
			if key == "wait":
				w.pass_hours(6.0)
				return _done(Lang.t("By evening the water drops enough to cross."))
			st["rations"] = maxi(0, int(st["rations"]) - 6)
			if randf() < 0.15:
				var m3 := _random_man()
				if not m3.is_empty():
					_lose(m3, Lang.t("drowned at a ford"))
					return _done(Lang.t("You get across, but %s is swept away, and some of the food with him.") % Company.title(m3))
			return _done(Lang.t("A wet, cold crossing. Some of the food is ruined."))
		"camp":
			if key == "search":
				var r2 := randf()
				if r2 < 0.4:
					var f := randi_range(4, 10)
					st["rations"] = int(st["rations"]) + f
					return _done(Lang.t("A sack of meal, still dry: %d rations.") % f)
				if r2 < 0.7:
					var c2 := randi_range(5, 20)
					Company.money += c2
					return _done(Lang.t("A purse, %d crowns, left behind in a hurry.") % c2)
				_morale(-1)
				return _done(Lang.t("Behind the tent, what's left of its owner. The lizards took the rest."))
		"prospectors":
			if key == "show":
				_morale(2)
				var hold := {}
				for s4 in w.gen.settlements:
					if s4["kind"] == "hold" and (hold.is_empty() or Vector2(s4["x"], s4["y"]).distance_to(w.pos) < Vector2(hold["x"], hold["y"]).distance_to(w.pos)):
						hold = s4
				if not hold.is_empty():
					w._reveal(Vector2(hold["x"], hold["y"]), 12.0)
				return _done(Lang.t("They take a musket apart and put it back together in silence, then tell you the way to %s. The men are proud as peacocks.") % hold.get("name", Lang.t("their hold")))
	return _done("")


func _done(text: String) -> Dictionary:
	Company.save()
	return {"text": text}


func _avg(attr: String) -> float:
	var men: Array = Company.roster
	if men.is_empty():
		return 5.0
	var t := 0.0
	for m in men:
		t += Men.attr(m, attr)
	return t / men.size()


func _morale(d: int) -> void:
	for m in Company.roster:
		Men.add_morale(m, d)


func _random_man() -> Dictionary:
	var men: Array = Company.roster.filter(func(m): return not m.get("away", false))
	return men.pick_random() if men.size() > 0 else {}


func _sicken(n: int) -> int:
	var well: Array = Company.roster.filter(func(m): return int(m["sick"]) <= 0)
	well.shuffle()
	for m in well.slice(0, n):
		m["sick"] = randi_range(3, 6)
	return mini(n, well.size())


func _lose(m: Dictionary, cause: String) -> void:
	Company.fallen.append({"name": m["name"], "rank": Company.RANKS[int(m["rank"])], "day": Company.day,
		"battles": m["battles"], "kills": m["kills"], "cause": cause})
	Company.roster.erase(m)
