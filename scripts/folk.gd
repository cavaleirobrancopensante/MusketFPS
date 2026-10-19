extends RefCounted
## The people of the land's settlements, and talking to them.
##
## Every settlement has its own people, generated from the campaign seed and
## from the map around it: a ferryman where a river runs past, fishers on
## the coast, charcoal burners by the forest, miners in a dwarf hold. Each has
## a name, an age, a trade, two traits, something they need, and a history
## tied to real places (the nest that took a brother is a real nest on your
## map). They are the same people every visit, and they remember you:
## Company.towns[sid] = {"rep": int, "npcs": {i: state}}.
##
## A conversation is a run of exchanges. You pick what to try (greet, give,
## ask, show the musket, ask them to join...) and how: with SIGNS (always,
## and easily misread) or with WORDS (once you know the words it needs;
## clearer). Each exchange rolls: did they understand you? Then their traits,
## their need, your standing in town and the dice decide what they make of it.
## You see what they do, hear what they say (the words you know translated),
## sometimes learn a word, a rumour, a piece of their story, a task - or
## lose them. Now and then something else happens altogether.

const Tongue := preload("res://scripts/tongue.gd")
const Lore := preload("res://scripts/lore.gd")

const TRAITS := ["curious", "fearful", "proud", "greedy", "pious", "kind", "suspicious", "bold",
	"hothead", "talkative", "shy", "merry", "bitter"]
const CLASH := {"fearful": ["bold", "hothead"], "bold": ["fearful", "shy"], "shy": ["talkative", "bold"],
	"talkative": ["shy"], "kind": ["bitter"], "bitter": ["kind", "merry"], "merry": ["bitter"],
	"hothead": ["fearful"]}
const TRAIT_WORDS := {
	"curious": "curious", "fearful": "easily frightened", "proud": "proud", "greedy": "fond of money",
	"pious": "devout", "kind": "kind-hearted", "suspicious": "wary of strangers", "bold": "bold",
	"hothead": "quick to anger", "talkative": "a talker", "shy": "shy", "merry": "cheerful", "bitter": "bitter",
}
const NEEDS := ["food", "revenge", "debt", "escape", "coin", "none"]
const KIN := {"m": ["brother", "son", "wife", "daughter"], "f": ["husband", "son", "sister", "daughter"]}

const FIRST := {
	"aurest": {"m": ["Aubin", "Martel", "Lisandre", "Corvin", "Sauveur", "Remi", "Bastien", "Olivet", "Thibaut", "Aimon"],
		"f": ["Maelis", "Aurore", "Ysane", "Clemence", "Liette", "Odile", "Sabine", "Margot", "Eloane", "Berthe"]},
	"vell": {"m": ["Halvard", "Dromm", "Wendel", "Ostrik", "Kellan", "Brann", "Ulrik", "Radko", "Gestor", "Fenn"],
		"f": ["Helka", "Stina", "Wenna", "Ostra", "Kelda", "Bryn", "Ulla", "Radna", "Gerdi", "Fenna"]},
	"dwarves": {"m": ["Kazrik", "Durin", "Barak", "Thorgal", "Garin", "Mordek", "Khelgar", "Dunmar", "Grimbol", "Balin"],
		"f": ["Kazra", "Dura", "Bera", "Thora", "Gerta", "Morra", "Khelda", "Duna", "Grima", "Balda"]},
}

## What you try in a conversation: label, key concepts (to do it in words),
## and what it costs.
const ACTIONS := {
	"greet": {"label": "Greet", "words": ["hello"], "signs": "You raise an open hand and bow your head."},
	"name": {"label": "Ask their name", "words": ["who", "you"], "signs": "You touch your chest and say your name, then point at them, eyebrows raised."},
	"listen": {"label": "Let them talk", "words": ["listen"], "signs": "You sit on a step, nod, and let them talk."},
	"gift_food": {"label": "Give bread (1 ration)", "words": ["gift", "bread"], "signs": "You hold out a ration of bread with both hands."},
	"gift_coin": {"label": "Give coin (2 crowns)", "words": ["gift", "coin"], "signs": "You press two crowns into their palm."},
	"ask_lizards": {"label": "Ask about the lizards", "words": ["lizard", "where"], "signs": "You make claws of your hands, hiss, and spread your arms: where?"},
	"ask_land": {"label": "Ask about the land", "words": ["where", "town"], "signs": "You draw a little map in the dust and point at the edges, then at them."},
	"ask_work": {"label": "Ask what they need", "words": ["want", "help"], "signs": "You point at yourself, then at them, and open your hands: what can I do?"},
	"musket": {"label": "Show your musket", "words": ["weapon", "thunder"], "signs": "You unsling your musket and show them the lock, the pan, the long barrel."},
	"join": {"label": "Ask them to join you", "words": ["join", "fight"], "signs": "You point at them, then at your men by the gate, and march a few steps."},
}
const ACTION_ORDER := ["greet", "name", "listen", "gift_food", "gift_coin", "ask_lizards", "ask_land", "ask_work", "musket", "join"]

static var _cache := {} # sid -> Array of people (generated, not saved)


# ---------------------------------------------------------------- the place

static func settlement(sid: int) -> Dictionary:
	return World.gen.settlements[sid]


## What's around a settlement on the map: water, woods, hills, the nearest
## nest and the nearest other settlement.
static func surroundings(sid: int) -> Dictionary:
	var st := settlement(sid)
	var g = World.gen
	var Gen = g.get_script()
	var cx := int(st["x"])
	var cy := int(st["y"])
	var out := {"river": false, "river_dir": Vector2.RIGHT, "coast": false, "sea_dir": Vector2.DOWN,
		"forest": 0.0, "hills": 0.0, "swamp": 0.0, "mountain": 0.0}
	var river_cells: Array = []
	var sea := Vector2.ZERO
	var n := 0
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var x := cx + dx
			var y := cy + dy
			if not g.inside(x, y):
				continue
			n += 1
			var i: int = Gen.idx(x, y)
			var t: int = g.terrain[i]
			if absi(dx) <= 6 and absi(dy) <= 6 and int(g.river[i]) > 0:
				river_cells.append(Vector2(dx, dy))
			match t:
				Gen.T.SEA, Gen.T.LAKE:
					sea += Vector2(dx, dy)
					out["coast"] = true
				Gen.T.FOREST:
					out["forest"] += 1.0
				Gen.T.HILLS:
					out["hills"] += 1.0
				Gen.T.SWAMP:
					out["swamp"] += 1.0
				Gen.T.MOUNTAIN:
					out["mountain"] += 1.0
	for k in ["forest", "hills", "swamp", "mountain"]:
		out[k] = float(out[k]) / maxf(1.0, n)
	if river_cells.size() >= 3:
		out["river"] = true
		# The river's run: the spread of its cells (first principal axis).
		var mean := Vector2.ZERO
		for p in river_cells:
			mean += p
		mean /= river_cells.size()
		var sxx := 0.0
		var syy := 0.0
		var sxy := 0.0
		for p in river_cells:
			var d: Vector2 = p - mean
			sxx += d.x * d.x
			syy += d.y * d.y
			sxy += d.x * d.y
		var ang := 0.5 * atan2(2.0 * sxy, sxx - syy)
		out["river_dir"] = Vector2(cos(ang), sin(ang))
	if out["coast"] and sea.length() > 0.1:
		out["sea_dir"] = sea.normalized()
	# The nearest nest, and the nearest other settlement.
	var best_nest := {}
	var bd := INF
	var best_town := {}
	var bt := INF
	for o in g.settlements:
		if int(o["id"]) == sid:
			continue
		var d := Vector2(o["x"], o["y"]).distance_to(Vector2(cx, cy))
		if o["kind"] == "nest" and d < bd:
			bd = d
			best_nest = o
		elif o["kind"] != "nest" and d < bt:
			bt = d
			best_town = o
	out["nest"] = best_nest
	out["nest_dist"] = bd
	out["town"] = best_town
	out["town_dist"] = bt
	return out


static func compass(from: Vector2, to: Vector2) -> String:
	var d := to - from
	var a := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]


static func days_away(cells: float) -> String:
	var days := cells / 22.0
	if days < 0.6:
		return Lang.t("less than a day away")
	if days < 1.5:
		return Lang.t("a day away")
	return Lang.t("%d days away") % int(round(days))


# ---------------------------------------------------------------- the people

static func head_count(kind: String) -> int:
	return {"village": 9, "town": 14, "city": 20, "hold": 12}.get(kind, 8)


static func people(sid: int) -> Array:
	if _cache.has(sid):
		return _cache[sid]
	var st := settlement(sid)
	var sur := surroundings(sid)
	var out: Array = []
	for i in head_count(String(st["kind"])):
		out.append(_make(sid, i, st, sur))
	_cache[sid] = out
	return out


static func _make(sid: int, i: int, st: Dictionary, sur: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("folk:%d:%d:%d" % [World.seed, sid, i])
	for k in 3:
		rng.randi() # stir: neighbouring seeds start out alike
	var fac: String = st["faction"]
	var sex := "m" if rng.randf() < 0.55 else "f"
	var names: Dictionary = FIRST.get(fac, FIRST["aurest"])
	var first: String = names[sex][rng.randi() % names[sex].size()]
	var age := rng.randi_range(15, 68)
	var job := _job(rng, String(st["kind"]), fac, sur, sex)
	var traits: Array = []
	while traits.size() < 2:
		var t: String = TRAITS[rng.randi() % TRAITS.size()]
		if t in traits or traits.any(func(x): return t in CLASH.get(x, [])):
			continue
		traits.append(t)
	var need: String = NEEDS[rng.randi() % NEEDS.size()]
	if need == "revenge" and (sur["nest"] as Dictionary).is_empty():
		need = "food"
	var kin: String = KIN[sex][rng.randi() % 4]
	var p := {
		"i": i, "sid": sid, "name": first, "family": _family(rng, fac), "sex": sex, "age": age, "job": job, "traits": traits,
		"need": need, "kin": kin, "faction": fac, "lang": Tongue.lang_of(fac),
		"base": rng.randi_range(-20, 20) + (10 if "kind" in traits else 0) - (15 if "suspicious" in traits else 0),
		"recruitable": age >= 17 and age <= 46 and job not in ["priest", "clerk", "midwife", "rune-carver"],
		"debt": rng.randi_range(6, 20), "food_n": rng.randi_range(4, 10),
		"shirt": Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.55), rng.randf_range(0.35, 0.75)),
		"hat": ["", "", "cap", "tricorne"][rng.randi() % 4] if fac != "dwarves" else "cap",
		"story": _story(rng, need, kin, job, sur, sex),
	}
	return p


## A family name in the faction's style ("Marbelle", "Ostwick", "Barzul").
static func _family(rng: RandomNumberGenerator, fac: String) -> String:
	var f: Dictionary = Lore.FACTIONS.get(fac, Lore.FACTIONS["aurest"])
	var syll: Array = f["syll"]
	var end: Array = f["end"]
	return (String(syll[rng.randi() % syll.size()]) + String(end[rng.randi() % end.size()]).replace("-", "")).capitalize()


static func _job(rng: RandomNumberGenerator, kind: String, fac: String, sur: Dictionary, sex: String) -> String:
	var pool: Array = ["farmer", "farmer", "baker", "weaver", "carter", "herder", "beggar", "brewer"]
	if sex == "f":
		pool += ["washerwoman", "midwife"]
	if kind != "village":
		pool += ["smith", "priest", "guard", "guard", "merchant", "innkeeper", "cooper"]
	if kind == "city":
		pool += ["clerk", "servant", "mason", "guard"]
	if sur["river"]:
		pool += ["ferryman", "miller", "ferryman"]
	if sur["coast"]:
		pool += ["fisher", "fisher", "net-mender", "boatwright"]
	if float(sur["forest"]) > 0.15:
		pool += ["woodcutter", Lang.t("charcoal burner"), "hunter"]
	if float(sur["hills"]) > 0.15:
		pool += ["shepherd", "shepherd"]
	if float(sur["swamp"]) > 0.12:
		pool += ["peat-cutter", "eel-catcher"]
	if fac == "dwarves" or float(sur["mountain"]) > 0.1:
		pool += ["miner", "miner", "stonecutter"]
	if fac == "dwarves":
		pool = ["miner", "miner", "smith", "smith", "brewer", "stonecutter", "rune-carver", "guard", "merchant"]
	return pool[rng.randi() % pool.size()]


## Their history, as pieces you learn one at a time.
static func _story(rng: RandomNumberGenerator, need: String, kin: String, job: String, sur: Dictionary, sex: String) -> Array:
	var he := "he" if sex == "m" else "she"
	var his := "his" if sex == "m" else "her"
	var out: Array = []
	var nest: Dictionary = sur["nest"]
	match need:
		"revenge":
			out.append(Lang.t("The lizards took %s %s %s.") % [his, kin, [Lang.t("last spring"), Lang.t("two winters ago"), Lang.t("this summer"), Lang.t("on the road to market")][rng.randi() % 4]])
			out.append(Lang.t("They were dragged off toward %s, the nest.") % nest["name"])
		"food":
			out.append(Lang.t("There are %d hungry mouths at home and the harvest failed.") % rng.randi_range(2, 6))
		"debt":
			out.append(Lang.t("%s owes money to %s and can't pay.") % [he.capitalize(), [Lang.t("the miller"), Lang.t("a moneylender"), Lang.t("the lord's steward"), Lang.t("the innkeeper")][rng.randi() % 4]])
		"escape":
			out.append(Lang.t("%s has never been further than a day's walk from here, and hates it.") % he.capitalize())
		"coin":
			out.append(Lang.t("%s works for next to nothing and wants better.") % he.capitalize())
		_:
			out.append(Lang.t("%s seems content enough with %s lot.") % [he.capitalize(), his])
	var flavour := {
		"ferryman": Lang.t("%s ferries people across the river for a copper a head.") % he.capitalize(),
		"fisher": Lang.t("%s goes out on the water before dawn.") % he.capitalize(),
		"charcoal burner": Lang.t("%s smells of smoke; %s kilns are out in the woods.") % [he.capitalize(), his],
		"hunter": Lang.t("%s knows the forest paths better than anyone.") % he.capitalize(),
		"guard": Lang.t("%s keeps the gate and doesn't trust you.") % he.capitalize(),
		"priest": Lang.t("%s serves the shrine and watches you closely.") % he.capitalize(),
		"miner": Lang.t("%s has dug in the deep halls since boyhood.") % he.capitalize(),
		"smith": Lang.t("%s eyes your musket's lock with a craftsman's interest.") % he.capitalize(),
	}
	if flavour.has(job):
		out.append(flavour[job])
	return out


# ---------------------------------------------------------------- what's remembered

static func town(sid: int) -> Dictionary:
	var k := str(sid)
	if not Company.towns.has(k):
		Company.towns[k] = {"rep": 0, "npcs": {}, "visits": 0}
	return Company.towns[k]


static func state(p: Dictionary) -> Dictionary:
	var npcs: Dictionary = town(int(p["sid"]))["npcs"]
	var k := str(int(p["i"]))
	if not npcs.has(k):
		npcs[k] = {"trust": int(p["base"]), "met": 0, "named": false, "facts": 0, "task": {}, "joined": false,
			"gone": false, "need_met": false, "seen_musket": false}
	return npcs[k]


## How they're known to you: "Aubin, the ferryman" or "a ferryman".
static func known_as(p: Dictionary) -> String:
	var s := state(p)
	if bool(s["named"]):
		return Lang.t("%s, the %s") % [p["name"], p["job"]]
	return "a %s" % p["job"] if String(p["job"])[0] not in "aeiou" else Lang.t("an %s") % p["job"]


static func pron(p: Dictionary) -> Array:
	return ["he", "his", "him"] if p["sex"] == "m" else ["she", "her", "her"]


## What you've learned about them so far (traits show as you see them act).
static func what_you_know(p: Dictionary) -> String:
	var s := state(p)
	var bits: PackedStringArray = []
	if int(s["met"]) == 0:
		return Lang.t("You've never spoken.")
	bits.append(Lang.t("Met %d time%s.") % [int(s["met"]), "" if int(s["met"]) == 1 else "s"])
	if int(s["met"]) >= 2 or int(s["trust"]) > 20:
		bits.append(Lang.t("Seems %s.") % Lang.t(" and ").join(PackedStringArray((p["traits"] as Array).map(func(t): return Lang.t(TRAIT_WORDS[t])))))
	var story: Array = p["story"]
	for k in mini(int(s["facts"]), story.size()):
		bits.append(String(story[k]))
	if not (s["task"] as Dictionary).is_empty() and not bool(s["task"].get("done", false)):
		bits.append(Lang.t("Asked of you: ") + task_text(p))
	return " ".join(bits)


static func task_text(p: Dictionary) -> String:
	var t: Dictionary = state(p)["task"]
	match String(t.get("kind", "")):
		"food": return Lang.t("bring %d rations for the family.") % int(t["n"])
		"debt": return Lang.t("pay the %d crowns owed.") % int(t["n"])
		"revenge":
			return Lang.t("fight the lizards and come back to tell of it.")
		"coin": return Lang.t("pay %d crowns up front.") % int(t["n"])
	return ""


## Can the task be finished now? (You have the food or the coin, or you've
## won a fight against the lizards since it was set.)
static func task_ready(p: Dictionary) -> bool:
	var t: Dictionary = state(p)["task"]
	if t.is_empty() or bool(t.get("done", false)):
		return false
	match String(t["kind"]):
		"food": return int(Company.stores["rations"]) >= int(t["n"])
		"debt", "coin": return Company.money >= int(t["n"])
		"revenge": return Company.victories > int(t.get("mark", 0))
	return false


static func can_use_words(p: Dictionary, action: String) -> bool:
	var lang: String = p["lang"]
	for c in ACTIONS[action]["words"]:
		if not Tongue.knows(lang, String(c)):
			return false
	return true


# ---------------------------------------------------------------- an exchange

## Try `action` on person `p`, with words or signs. Returns
## {"you": what you did, "see": what they do, "say": [concepts], "note":
##  what came of it, "learned": [words], "end": true if they leave,
##  "joined": true, "tone": "warm"/"cold"/"afraid"/"angry"/"puzzled"/"amused"}.
static func exchange(p: Dictionary, action: String, words: bool, ctx: Dictionary) -> Dictionary:
	var s := state(p)
	var lang: String = p["lang"]
	var tr: Array = p["traits"]
	var pr := pron(p)
	var he: String = pr[0]
	var He := he.capitalize()
	var his: String = pr[1]
	var him: String = pr[2]
	var nm: String = p["name"] if bool(s["named"]) else Lang.t("The %s") % p["job"]
	var tw := town(int(p["sid"]))
	var r := {"you": "", "see": "", "say": [], "note": "", "learned": [], "end": false, "joined": false, "tone": "puzzled"}
	var spec: Dictionary = ACTIONS[action]
	if words:
		var said: PackedStringArray = []
		for c in spec["words"]:
			said.append(Tongue.word(lang, String(c)))
		r["you"] = Lang.t("You say “%s”.") % " ".join(said)
	else:
		r["you"] = Lang.t(String(spec["signs"]))

	# Costs.
	if action == "gift_food":
		if int(Company.stores["rations"]) < 1:
			r["note"] = Lang.t("There's no bread left in the wagon.")
			return r
		Company.stores["rations"] = int(Company.stores["rations"]) - 1
	elif action == "gift_coin":
		if Company.money < 2:
			r["note"] = Lang.t("You haven't two crowns to give.")
			return r
		Company.money -= 2

	# Did they understand you?
	var flu := Tongue.fluency(lang) / 100.0
	var p_get := 0.42 + 0.35 * flu + 0.03 * Company.Officer.skill("tongues")
	if words:
		p_get += 0.35
	if "curious" in tr:
		p_get += 0.1
	if "suspicious" in tr:
		p_get -= 0.08
	if action in ["gift_food", "gift_coin", "musket"]:
		p_get += 0.25 # a thing in your hand needs few words
	p_get = clampf(p_get, 0.12, 0.97)
	var understood := randf() < p_get
	var roll := randi_range(1, 20) # their mood today, luck, everything else
	var trust := int(s["trust"]) + int(tw["rep"])
	var dt := 0 # change in their trust

	Tongue.grow(lang, 0.25)
	if not understood:
		var mis := _misread(action, p, roll)
		r["see"] = String(mis[0]).format({"nm": nm, "he": he, "He": He, "his": his, "His": his.capitalize(), "him": him})
		r["say"] = mis[1]
		dt = int(mis[2])
		r["tone"] = mis[3]
		r["note"] = Lang.t("They didn't understand you.")
	else:
		var res := _understood(action, p, s, roll, trust, words, ctx)
		r.merge(res, true)
		dt = int(res.get("dt", 0))
		r["see"] = String(r["see"]).format({"nm": nm, "he": he, "He": He, "his": his, "His": his.capitalize(), "him": him})
		r["note"] = String(r["note"]).format({"nm": nm, "he": he, "He": He, "his": his, "His": his.capitalize(), "him": him})

	# Something else happens, now and then.
	if randf() < 0.1 and not bool(r.get("end", false)) and not bool(r.get("joined", false)):
		var ev := _surprise(p, s, roll)
		if not ev.is_empty():
			r["see"] = String(r["see"]) + " " + (String(ev[0]).format({"nm": nm, "he": he, "He": He, "his": his, "His": his.capitalize(), "him": him}))
			dt += int(ev[1])
			if ev.size() > 2:
				r["say"] = (r["say"] as Array) + (ev[2] as Array)

	s["trust"] = clampi(int(s["trust"]) + dt, -100, 100)
	r["trust_change"] = dt
	# Listening to them: you may pick up a word they used.
	var chance := 0.22 + (0.2 if "talkative" in tr else 0.0) + (0.15 if "kind" in tr else 0.0) + (0.25 if action in ["listen", "name"] else 0.0)
	var heard := Tongue.listen(lang, r["say"], chance)
	if heard != "":
		(r["learned"] as Array).append(heard)
	if int(s["trust"]) <= -45 and not bool(r["end"]):
		r["end"] = true
		r["see"] = String(r["see"]) + " " + (Lang.t("%s turns away and won't look at you again.") % nm)
		tw["rep"] = int(tw["rep"]) - 2
	return r


## Misunderstandings: [what they do, what they say, trust change, tone].
static func _misread(action: String, p: Dictionary, roll: int) -> Array:
	var tr: Array = p["traits"]
	var opts: Array = []
	match action:
		"greet":
			opts = [[Lang.t("{nm} squints, then copies your bow, too deep, as if mocking."), ["what", "stranger"], 0, "puzzled"],
				[Lang.t("{nm} takes your raised hand for a warding sign and makes one back, quickly."), ["go", "strange"], -4, "afraid"],
				[Lang.t("{nm} laughs. It seems you've waved the way children wave goodbye."), ["goodbye", "stranger"], 2, "amused"]]
		"name":
			opts = [[Lang.t("{nm} repeats your name back, wrongly, and points at your coat instead."), ["you", "soldier"], 1, "puzzled"],
				[Lang.t("{nm} thinks you're asking for money and pats empty pockets."), ["no", "coin"], -1, "puzzled"]]
		"listen":
			opts = [[Lang.t("{nm} talks a long while. You catch nothing, and {he} can tell."), ["you", "not", "know"], -1, "cold"],
				[Lang.t("{nm} seems pleased just to be listened to, though you follow none of it."), ["i", "home", "family", "work"], 3, "warm"]]
		"gift_food", "gift_coin":
			opts = [[Lang.t("{nm} thinks you want to sell it and shakes {his} head firmly."), ["no", "trade"], -1, "puzzled"],
				[Lang.t("{nm} takes it, unsure, as if it might be a trick."), ["why", "gift"], 2, "puzzled"],
				[Lang.t("{nm} is insulted: here, gifts from strangers are for beggars."), ["no", "i", "not"], -6, "angry"] if "proud" in tr else [Lang.t("{nm} accepts it with a puzzled half-smile."), ["thanks", "strange"], 3, "warm"]]
		"ask_lizards":
			opts = [[Lang.t("Your hissing frightens {nm}, who backs off making a sign against evil."), ["no", "go", "danger"], -6, "afraid"],
				[Lang.t("{nm} laughs at your claws, thinking it's a children's game."), ["strange", "you"], 2, "amused"],
				[Lang.t("{nm} points at the river, then the sky. You can't tell what about."), ["river", "god"], 0, "puzzled"]]
		"ask_land":
			opts = [[Lang.t("{nm} looks at your dust-map, rubs it out with a foot, and draws something else."), ["no", "road"], 0, "puzzled"],
				[Lang.t("{nm} thinks you want to buy land and calls for the steward."), ["lord", "come"], -3, "cold"]]
		"ask_work":
			opts = [[Lang.t("{nm} thinks you're begging and offers you a crust."), ["food", "you", "hungry"], 1, "puzzled"],
				[Lang.t("{nm} thinks you want to be hired and laughs at the idea of a stranger working here."), ["no", "work", "stranger"], -1, "amused"]]
		"musket":
			if "fearful" in tr:
				opts = [[Lang.t("{nm} cries out at the sight of the weapon and runs. Heads turn all along the street."), ["danger", "weapon", "help"], -15, "afraid"]]
			else:
				opts = [[Lang.t("{nm} thinks you're threatening {him} and steps back, hand on a knife."), ["no", "weapon", "go"], -8, "angry"],
					[Lang.t("{nm} takes the musket for a strange walking staff and isn't impressed."), ["strange"], 0, "puzzled"]]
		"join":
			opts = [[Lang.t("{nm} thinks you're asking the way to the gate and points it out helpfully."), ["go", "road"], 0, "puzzled"],
				[Lang.t("{nm} thinks you're ordering {him} about and bristles."), ["no", "i", "not"], -5, "angry"]]
	return opts[(roll + opts.size()) % opts.size()] if not opts.is_empty() else [Lang.t("{nm} just stares."), [], 0, "puzzled"]


## They understood. Returns parts of the result (and "dt").
static func _understood(action: String, p: Dictionary, s: Dictionary, roll: int, trust: int, words: bool, ctx: Dictionary) -> Dictionary:
	var tr: Array = p["traits"]
	var need: String = p["need"]
	var r := {"see": "", "say": [], "note": "", "dt": 0, "tone": "warm"}
	var good := roll + trust / 10 + (3 if words else 0)
	match action:
		"greet":
			if int(s["met"]) > 0:
				r["see"] = Lang.t("{nm} recognises you and nods.") if trust < 30 else Lang.t("{nm}'s face lights up: the stranger is back.")
				r["say"] = ["hello", "friend"] if trust >= 30 else ["hello", "stranger"]
				r["dt"] = 2 if trust < 30 else 4
			elif "suspicious" in tr and good < 12:
				r["see"] = Lang.t("{nm} nods stiffly and keeps a hand on {his} belt.")
				r["say"] = ["stranger", "what", "want"]
				r["dt"] = 1
				r["tone"] = "cold"
			elif "shy" in tr:
				r["see"] = Lang.t("{nm} colours, ducks {his} head and murmurs something.")
				r["say"] = ["hello"]
				r["dt"] = 3
			else:
				r["see"] = [Lang.t("{nm} returns the bow and touches {his} heart."), Lang.t("{nm} grins and says something loud and friendly."), Lang.t("{nm} nods, wary but polite.")][roll % 3]
				r["say"] = ["hello", "stranger"]
				r["dt"] = 4 if "merry" in tr or "kind" in tr else 2
		"name":
			s["named"] = true
			r["see"] = Lang.t("“%s,” {he} says, touching {his} chest, and tries your name with a frown.") % p["name"]
			r["say"] = ["i", "name", "you", "name"]
			r["note"] = Lang.t("You learn %s's name.") % p["name"]
			r["dt"] = 3
		"listen":
			var story: Array = p["story"]
			r["dt"] = 2 + (2 if "talkative" in tr else 0)
			if int(s["facts"]) < story.size() and (trust >= 0 or "talkative" in tr):
				r["see"] = Lang.t("{nm} talks, half to you and half to {him}elf. You follow some of it.")
				r["note"] = Lang.t("You learn: ") + String(story[int(s["facts"])])
				s["facts"] = int(s["facts"]) + 1
			else:
				r["see"] = [Lang.t("{nm} talks about the weather, the price of bread, a neighbour's goat."), Lang.t("{nm} tells a long story, laughing at the end of it."), Lang.t("{nm} complains, at length, about the lord's men.")][roll % 3]
			r["say"] = _ramble(need, p)
		"gift_food":
			if need == "food":
				r["see"] = Lang.t("{nm} takes the bread with both hands and holds it to {his} chest. For a moment {he} can't speak.")
				r["say"] = ["thanks", "family", "food", "thanks"]
				r["dt"] = 18
				s["need_met"] = true
			elif "proud" in tr and roll < 8:
				r["see"] = Lang.t("{nm} takes it, but stiffly: {he} is no beggar.")
				r["say"] = ["i", "not", "hungry"]
				r["dt"] = -2
				r["tone"] = "cold"
			else:
				r["see"] = Lang.t("{nm} takes the bread and tears off a corner at once.")
				r["say"] = ["thanks", "bread", "good"]
				r["dt"] = 7
		"gift_coin":
			if "greedy" in tr or need in ["debt", "coin"]:
				r["see"] = Lang.t("{nm} bites the coin, turns it over, and smiles properly for the first time.")
				r["say"] = ["coin", "good", "thanks", "friend"]
				r["dt"] = 12
			elif "proud" in tr:
				r["see"] = Lang.t("{nm} pushes the coins back into your hand.")
				r["say"] = ["no", "i", "not", "coin"]
				r["dt"] = -3
				r["tone"] = "cold"
				Company.money += 2
			else:
				r["see"] = Lang.t("{nm} pockets the coins with a nod.")
				r["say"] = ["thanks"]
				r["dt"] = 6
		"ask_lizards":
			var sur: Dictionary = ctx["sur"]
			var nest: Dictionary = sur["nest"]
			if nest.is_empty() or (trust < -10 and not "talkative" in tr):
				r["see"] = Lang.t("{nm} shakes {his} head and won't talk of them.")
				r["say"] = ["no", "lizard", "danger"]
				r["tone"] = "afraid"
			else:
				var here := settlement(int(p["sid"]))
				var dir := compass(Vector2(here["x"], here["y"]), Vector2(nest["x"], nest["y"]))
				r["see"] = Lang.t("{nm} spits, then points %s: the lizards' nest, %s.") % [dir, days_away(float(sur["nest_dist"]))]
				r["say"] = ["lizard", "nest", "far" if float(sur["nest_dist"]) > 20 else "near", "danger", "kill"]
				r["note"] = Lang.t("Marked on your map: %s, a lizard nest.") % nest["name"]
				r["reveal"] = int(nest["id"])
				r["dt"] = 3
				if need == "revenge":
					r["see"] = String(r["see"]) + Lang.t(" {His} voice breaks as {he} says it. They took {his} %s.") % p["kin"]
					r["say"] = ["lizard", "taken", p["kin"], "nest", "kill"]
					r["dt"] = 8
					s["facts"] = maxi(int(s["facts"]), 1)
		"ask_land":
			var sur2: Dictionary = ctx["sur"]
			var other: Dictionary = sur2["town"]
			if other.is_empty():
				r["see"] = Lang.t("{nm} shrugs.")
			else:
				var here2 := settlement(int(p["sid"]))
				r["see"] = Lang.t("{nm} draws in the dust: a road %s to %s, %s.") % [compass(Vector2(here2["x"], here2["y"]), Vector2(other["x"], other["y"])), other["name"], days_away(float(sur2["town_dist"]))]
				r["say"] = ["road", "go", String(other["kind"]) if String(other["kind"]) in ["village", "town"] else "town", "far" if float(sur2["town_dist"]) > 20 else "near"]
				r["note"] = Lang.t("Marked on your map: %s.") % other["name"]
				r["reveal"] = int(other["id"])
				r["dt"] = 2
		"ask_work":
			if bool(s["need_met"]):
				r["see"] = Lang.t("{nm} shakes {his} head: you've done enough already.")
				r["say"] = ["no", "thanks", "friend"]
			elif need == "none" or trust < 0:
				r["see"] = Lang.t("{nm} has nothing to ask of a stranger.") if trust < 0 else Lang.t("{nm} thinks, and can't think of anything.")
				r["say"] = ["no", "not", "want"]
			else:
				var task := {"kind": need if need in ["food", "debt", "revenge", "coin"] else "coin"}
				match String(task["kind"]):
					"food":
						task["n"] = int(p["food_n"])
						r["see"] = Lang.t("{nm} mimes eating, then holds up %d fingers and points at the houses: the family.") % int(p["food_n"])
						r["say"] = ["family", "hungry", "food", "help"]
					"debt":
						task["n"] = int(p["debt"])
						r["see"] = Lang.t("{nm} counts on {his} fingers, %d, and nods toward a big house: a debt.") % int(p["debt"])
						r["say"] = ["i", "debt", "coin", "help"]
					"revenge":
						task["mark"] = Company.victories
						r["see"] = Lang.t("{nm} makes your lizard claws, then a fist, then points at your musket. Kill them.")
						r["say"] = ["lizard", "kill", "you", "fight", p["kin"]]
					"coin":
						task["n"] = 8 + int(p["age"]) % 7
						r["see"] = Lang.t("{nm} rubs finger and thumb together and looks at your purse: pay first.") if need == "coin" else Lang.t("{nm} looks at the road out of town for a long time, then at your purse.")
						r["say"] = ["coin", "give", "i", "go"]
				s["task"] = task
				r["note"] = Lang.t("Asked of you: ") + task_text(p)
				r["dt"] = 2
		"musket":
			var first_time := not bool(s["seen_musket"])
			s["seen_musket"] = true
			if "fearful" in tr and roll < 14:
				r["see"] = Lang.t("{nm} goes white and backs away from the thing.")
				r["say"] = ["no", "weapon", "danger"]
				r["dt"] = -6
				r["tone"] = "afraid"
			elif "pious" in tr and roll < 10:
				r["see"] = Lang.t("{nm} makes a holy sign over it. Thunder that men carry is not natural.")
				r["say"] = ["god", "no", "thunder", "bad"]
				r["dt"] = -4
				r["tone"] = "cold"
			elif "bold" in tr or "curious" in tr or "hothead" in tr or p["job"] in ["smith", "hunter", "guard"]:
				r["see"] = Lang.t("{nm} runs a finger along the barrel, works the lock, and looks at you differently.") if first_time else Lang.t("{nm} asks, with gestures, to hold it again.")
				r["say"] = ["weapon", "thunder", "good", "kill", "lizard"]
				r["dt"] = 9 if first_time else 3
			else:
				r["see"] = Lang.t("{nm} looks at it politely, not knowing what it is.")
				r["say"] = ["weapon", "strange"]
				r["dt"] = 1
		"join":
			return _ask_join(p, s, roll, trust, words)
	return r


static func _ramble(need: String, p: Dictionary) -> Array:
	var bits: Array = ["i", "work", "day", "many", "home"]
	match need:
		"food": bits = ["family", "hungry", "food", "few", "farm", "bad"]
		"revenge": bits = ["lizard", "taken", p["kin"], "nest", "night", "fear"]
		"debt": bits = ["i", "debt", "lord", "coin", "not", "have"]
		"escape": bits = ["i", "want", "go", "far", "road", "sea"]
		"coin": bits = ["work", "many", "coin", "few", "bad"]
	return bits


static func _ask_join(p: Dictionary, s: Dictionary, roll: int, trust: int, words: bool) -> Dictionary:
	var tr: Array = p["traits"]
	var need: String = p["need"]
	var r := {"see": "", "say": [], "note": "", "dt": 0, "tone": "warm"}
	if not bool(p["recruitable"]):
		r["see"] = Lang.t("{nm} laughs: too old, or too needed here, to march off with strangers.") if int(p["age"]) > 46 or p["job"] in ["priest", "clerk", "midwife", "rune-carver"] else Lang.t("{nm} is too young; {his} mother would kill {him}.")
		r["say"] = ["no", "i", "stay", "home"]
		return r
	# Why they might come: trust above all; a need you've met; a reason of
	# their own (revenge, wanting out); boldness. Why not: fear, family, a
	# need still unmet, a town that thinks badly of you.
	var score := trust + roll * 2 - 70
	if bool(s["need_met"]):
		score += 35
	elif need in ["food", "debt"]:
		score -= 15
	if need == "revenge":
		score += 15
	if need == "escape":
		score += 20
	if "bold" in tr or "hothead" in tr:
		score += 12
	if "fearful" in tr or "shy" in tr:
		score -= 15
	if bool(s["seen_musket"]):
		score += 5
	if words:
		score += 5
	# What their lords think of you counts too.
	var town_f := String(World.gen.settlements[int(p["sid"])].get("faction", ""))
	if Company.standing.has(town_f):
		score += clampi(int(Company.standing[town_f]) / 2, -20, 15)
	if score >= 0:
		r["see"] = [Lang.t("{nm} looks at your men, at the musket, at the road. Then {he} nods once."), Lang.t("{nm} says something to a neighbour, fetches {his} weapon from the doorway and comes to stand by you."), Lang.t("{nm} clasps your forearm, soldier-fashion.")][roll % 3]
		r["say"] = ["yes", "i", "go", "fight", "we"]
		r["joined"] = true
		r["dt"] = 10
		r["tone"] = "warm"
	elif score > -25:
		var why := Lang.t("the family") if need == "food" else (Lang.t("the debt") if need == "debt" else Lang.t("you're a stranger"))
		r["see"] = Lang.t("{nm} hesitates and shakes {his} head, glancing back at the houses. Not yet: ") + why + "."
		r["say"] = ["no", "not", "tomorrow", "maybe"] if need != "food" else ["no", "family", "hungry"]
		r["note"] = Lang.t("Not yet. Earn more trust, or help with what {he} needs.")
		r["dt"] = -1
		r["tone"] = "cold"
	else:
		r["see"] = Lang.t("{nm} laughs in your face. Follow a stranger to die among the lizards?")
		r["say"] = ["no", "you", "stranger", "go"]
		r["dt"] = -4
		r["tone"] = "angry"
	return r


## Something else that happens in a conversation: [text, trust change, words].
static func _surprise(p: Dictionary, s: Dictionary, roll: int) -> Array:
	var opts := [
		[Lang.t("A child runs up, stares at your coat, and is dragged away by {his} mother."), 1, ["son", "stranger"]],
		[Lang.t("A dog barks at you; {nm} shouts at it and apologises with a shrug."), 2, ["sorry"]],
		[Lang.t("Someone calls from a window. {nm} calls back, laughing, and points at you."), 1, ["stranger", "come", "see"]],
		[Lang.t("A guard strolls past and looks you over. {nm} goes quiet until he's gone."), -2, ["soldier", "lord"]],
		[Lang.t("{nm} offers you a drink from a skin. It's sour and strong."), 4, ["drink", "good"]],
		[Lang.t("{nm} points at the sky and says a word: rain coming."), 1, ["night", "water"]],
	]
	return opts[roll % opts.size()]


# ---------------------------------------------------------------- results

## A conversation began.
static func met(p: Dictionary) -> void:
	var s := state(p)
	s["met"] = int(s["met"]) + 1


## Finish a task they set (pay or deliver).
static func finish_task(p: Dictionary) -> String:
	var s := state(p)
	var t: Dictionary = s["task"]
	if not task_ready(p):
		return ""
	match String(t["kind"]):
		"food": Company.stores["rations"] = int(Company.stores["rations"]) - int(t["n"])
		"debt", "coin": Company.money -= int(t["n"])
	t["done"] = true
	s["need_met"] = true
	s["trust"] = mini(100, int(s["trust"]) + 30)
	town(int(p["sid"]))["rep"] = int(town(int(p["sid"]))["rep"]) + 3
	var pr := pron(p)
	match String(t["kind"]):
		"food": return Lang.t("You bring the rations. The family comes out to see. %s won't forget it.") % p["name"]
		"debt": return Lang.t("You pay the debt. %s watches the money change hands as if it were a miracle.") % p["name"]
		"revenge": return Lang.t("You tell of the fight, with your hands and the few words you have. %s listens, and grips your arm.") % p["name"]
		"coin": return Lang.t("You pay. %s weighs the coins and nods: a bargain.") % p["name"]
	return ""


## What a recruit brings from home, by trade and people: hunters and
## herders come with bows, the town watch with crossbows (the Vellish with
## war bows), smiths and miners with a spear and a padded jack, and most
## others with a spear. Returns {"gear", "ammo", "tag"}.
static func native_kit(p: Dictionary) -> Dictionary:
	var job := String(p.get("job", "farmer"))
	var fac := String(p.get("faction", "aurest"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("kit:%s:%s:%s" % [p.get("name", ""), p.get("family", ""), job])
	var head := String(p.get("hat", ""))
	if not head in ["cap", "tricorne", "hood", "kettle_hat"]:
		head = "hood" if rng.randf() < 0.4 else ""
	var g := {"head": head, "torso": "tunic", "primary": "war_spear", "secondary": ""}
	var role := "spear"
	if job in ["hunter", "shepherd", "woodcutter", Lang.t("charcoal burner"), "eel-catcher", "herder"]:
		role = "bow"
	elif job == "guard":
		role = "bow" if fac == "vell" else "crossbow"
	elif fac == "dwarves" and job in ["smith", "miner", "stonecutter"] and rng.randf() < 0.5:
		role = "crossbow"
	elif rng.randf() < (0.35 if fac == "vell" else 0.2):
		role = "bow"
	if fac == "dwarves" and role == "bow":
		role = "crossbow" # dwarves don't hold with bows
	match role:
		"bow":
			g["primary"] = "war_bow" if fac == "vell" and (job in ["hunter", "guard", "woodcutter"] or rng.randf() < 0.3) else "hunting_bow"
			g["secondary"] = "hatchet" if job in ["woodcutter", Lang.t("charcoal burner")] or rng.randf() < 0.4 else "long_knife"
		"crossbow":
			g["primary"] = "dwarf_crossbow" if fac == "dwarves" else "crossbow"
			g["secondary"] = "long_knife"
	if job in ["guard", "smith", "miner", "stonecutter", "mason"]:
		g["torso"] = "jack"
		if fac == "dwarves":
			g["head"] = "dwarf_helm"
		elif job == "guard":
			g["head"] = "kettle_hat"
	var ammo: int = {"bow": 24, "crossbow": 16}.get(role, 0)
	var tag: String = {"bow": "Bows", "crossbow": "Crossbows"}.get(role, "Spears")
	return {"gear": g, "ammo": ammo, "tag": tag}


## Hands for hire: the trades this place's people follow (a woodcutter
## where there are woods, miners in the hills, fishers by water...), and how
## many will come this week (it fills again every 7 days).
static func labour_trades(kind: String, fac: String, sur: Dictionary) -> Array:
	var out: Array = ["farmer"]
	if float(sur.get("forest", 0.0)) > 0.1 or fac == "vell":
		out += ["woodcutter", "hunter"]
	if fac == "dwarves" or float(sur.get("mountain", 0.0)) > 0.05 or float(sur.get("hills", 0.0)) > 0.15:
		out.append("miner")
	if bool(sur.get("river", false)) or bool(sur.get("coast", false)):
		out.append("fisher")
	if fac == "dwarves":
		out = ["miner", "miner", "woodcutter"]
	if not "hunter" in out and kind == "village":
		out.append("hunter")
	var uniq: Array = []
	for t in out:
		if not t in uniq:
			uniq.append(t)
	return uniq


static func labour_left(sid: int, kind: String) -> int:
	var t := town(sid)
	var week := Company.day / 7
	if int(t.get("labour_week", -1)) != week:
		t["labour_week"] = week
		t["labour_left"] = {"village": 3, "town": 5, "city": 7, "hold": 4}.get(kind, 3)
	return int(t["labour_left"])


## Hire one: a labourer with a name of this people. Returns the record or {}.
static func hire_labourer(sid: int, kind: String, fac: String, trade: String) -> Dictionary:
	if labour_left(sid, kind) <= 0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sex := "m" if rng.randf() < 0.6 else "f"
	var names: Dictionary = FIRST.get(fac, FIRST["aurest"])
	var nm := "%s %s" % [names[sex][rng.randi() % names[sex].size()], _family(rng, fac)]
	var w: Dictionary = Company.hire_labourer(trade, nm, fac)
	if not w.is_empty():
		town(sid)["labour_left"] = labour_left(sid, kind) - 1
		Company.save()
	return w


## They join the company: a real man (or woman) on the roll, with the
## weapon they brought from home (see native_kit).
static func recruit(p: Dictionary) -> Dictionary:
	var s := state(p)
	s["joined"] = true
	var m: Dictionary = Company.make_recruit()
	m["name"] = "%s %s" % [p["name"], p["family"]]
	var kit := native_kit(p)
	m["gear"] = kit["gear"]
	m["pack"] = {"water": 1, "rations": 2, "ammo": int(kit["ammo"])}
	m["native"] = p["faction"]
	m["drill"] = 0.0 # (he's never held a musket: see Company.drill_of)
	m["tongue"] = p["lang"]
	m["morale"] = 60
	var tag := String(kit["tag"])
	if not tag in Company.tags:
		Company.tags.append(tag)
	m["tag"] = tag
	Company.roster.append(m)
	town(int(p["sid"]))["rep"] = int(town(int(p["sid"]))["rep"]) + 1
	Company.save()
	return m
