extends Node
## The campaign's persistent state, registered as the `Company` autoload:
## your men, your purse and the calendar. Saved to user://campaign.json after
## every battle and every march, so it survives closing the game.
##
## Every soldier is a person: a name, the traits that shape how he fights
## (reaction, pace, steadiness), experience, rank, kills, and wounds. Men who
## fall in battle are either wounded (out for some days) or killed, and the
## dead go on the roll of honour. Experience earns promotion, and every rank
## makes a man steadier, quicker and harder in the press.
##
## Every man also has his gear (hat, coat, musket, bayonet) and a pack (water,
## rations, cartridges). The company's stores ride in the baggage wagon: hand
## them out on the Company screen. On the march each man eats and drinks from
## his pack first, then from the wagon; a beaten company loses half its
## baggage, but never what the men carry. Cartridges are what a man can fire.
##
## A new campaign opens with the prologue: you are the Ensign of Captain
## Harrow's company in a battle that goes wrong. The captain falls, hands you
## the company, and you lead what's left of it out.

const Men := preload("res://scripts/men.gd")
const Lore := preload("res://scripts/lore.gd")
const SAVE_PATH := "user://campaign.json"
const SAVE_VERSION := 3

const RANKS := ["Recruit", "Musketeer", "Veteran", "Sergeant"]
const RANK_SHORT := ["Rct.", "Pvt.", "Vet.", "Sgt."]
const RANK_XP := [0, 150, 400, 800] # experience needed for each rank
const WAGES := [2, 3, 4, 6] # crowns per man per week, by rank

const START_MONEY := 120
const RECRUIT_COST := 25
const MAX_COMPANY := 12
const WOUND_CHANCE := 0.5 # a man who goes down lives, wounded, half the time
const XP_SURVIVE := 25
const XP_VICTORY := 15
const XP_KILL := 20

# ---- gear
const SLOTS := ["head", "torso", "primary", "secondary"]
const SLOT_NAMES := {"head": "Head", "torso": "Torso", "primary": "Primary weapon",
	"secondary": "Secondary weapon"}
## Item stats (all optional): steady (+steadiness), pace (+/- fraction),
## armour (fraction of melee damage turned), spread / reload (multipliers),
## misfire (chance), melee (bayonet damage).
const ITEMS := {
	"shako": {"name": "Shako", "slot": "head", "steady": 0.05,
		"desc": "Regulation felt shako with a brass plate. A man stands taller in it."},
	"tricorne": {"name": "Tricorne", "slot": "head", "steady": 0.03,
		"desc": "An old cocked hat from the last war."},
	"cap": {"name": "Forage cap", "slot": "head",
		"desc": "A soft wool cap. Keeps the sun off, nothing more."},
	"coat": {"name": "Regulation coat", "slot": "torso", "steady": 0.05,
		"desc": "Blue wool coat with white crossbelts. The uniform of the line."},
	"shirt": {"name": "Linen shirt", "slot": "torso", "pace": 0.05,
		"desc": "Light and cool. No protection at all."},
	"buffcoat": {"name": "Buff coat", "slot": "torso", "armour": 0.3, "pace": -0.06,
		"desc": "Thick oiled leather. Turns a glancing hack, but it's heavy."},
	"musket": {"name": "Land musket", "slot": "primary", "spread": 1.0, "reload": 1.0, "misfire": 0.04,
		"desc": "Smoothbore flintlock, .75 bore. Reliable."},
	"worn_musket": {"name": "Worn musket", "slot": "primary", "spread": 1.35, "reload": 1.05, "misfire": 0.12,
		"desc": "Pitted barrel, tired lock. Misfires often and scatters wide."},
	"rifle": {"name": "Rifle", "slot": "primary", "spread": 0.4, "reload": 1.6, "misfire": 0.05,
		"desc": "A rifled barrel: deadly accurate, slow to load."},
	"bayonet": {"name": "Socket bayonet", "slot": "secondary", "melee": 34.0,
		"desc": "Fixed on the muzzle, it turns the musket into a pike."},
	"sword_bayonet": {"name": "Sword bayonet", "slot": "secondary", "melee": 42.0,
		"desc": "A long, heavy blade made for the rifle."},
}
const CLUBBED_DAMAGE := 18.0 # no bayonet: he clubs with the butt
## What a man carries in his pack, and how much he can carry.
const PACK := {
	"water": {"name": "Water", "unit": "day", "max": 2},
	"rations": {"name": "Rations", "unit": "day", "max": 8},
	"ammo": {"name": "Ammunition", "unit": "shot", "max": 40},
}
const WATER_CART := 60 # the wagon's barrels
const WATER_DAY_CHANCE := 0.65 # a day on the road passes water to refill them
const FOUL_WATER_CHANCE := 0.35 # ...but it may be a muddy, foul stream
const SICK_CHANCE := 0.12 # per day of foul water without grog (less with constitution)
## Sutler prices: [amount, crowns]. Rum is measured in tots: one tot makes a
## day's foul water safe for one man, as grog.
const SUPPLY := {"rations": [20, 8], "ammo": [40, 10], "rum": [20, 10]}
const MUTINY_MORALE := 30 # company morale below this risks mutiny

const REGULAR_GEAR := {"head": "shako", "torso": "coat", "primary": "musket", "secondary": "bayonet"}
const RECRUIT_GEAR := {"head": "cap", "torso": "shirt", "primary": "worn_musket", "secondary": ""}

# ---- the prologue
const PROLOGUE_MEN := 18
const CAPTAIN := Lore.COMMANDER

const FIRST_NAMES := ["John", "Thomas", "William", "James", "Patrick", "Michael",
	"Henry", "George", "Samuel", "Daniel", "Owen", "Robert", "Hugh", "Edward",
	"Francis", "Joseph", "Peter", "Martin", "Luke", "Simon", "Andrew", "Matthew",
	"Brian", "Declan", "Tomás", "João", "Rui", "Nuno"]
const LAST_NAMES := ["Byrne", "Walsh", "Kelly", "Murphy", "Doyle", "Carter",
	"Fletcher", "Hale", "Barrow", "Mason", "Thatcher", "Cooper", "Reid", "Fraser",
	"Gunn", "Shaw", "Pike", "Hollis", "Crane", "Ashby", "Drummond", "Kerr",
	"Lowry", "Nolan", "Quinn", "Sharpe", "Tanner", "Wren", "Coelho", "Barros",
	"Teixeira", "Moura"]

var active := false # a campaign is running (battles report back here)
var day := 1
var money := 0
var battles := 0
var victories := 0
var last_pay_day := 1
var next_id := 1
var roster: Array = [] # living men
var fallen: Array = [] # the roll of honour
var officer := {"kills": 0, "battles": 0, "rank": "Ensign"}
## The baggage wagon: spare gear by item id, water (and whether it's foul),
## rations, cartridges, rum, and whether the water is served as grog.
var stores := {"items": {}, "water": 0, "rations": 0, "ammo": 0, "rum": 0, "foul": false, "grog": true}
var prologue := false # the opening battle is still to be fought
## The ship's stores the lizards carried off (muskets, cartridges, guns,
## rum): recovering them is the first great objective. Empty once recovered.
var stash := {}
## A fight the map has started: {"enemy": int, "terrain": int, "party": id}.
var next_battle := {}
var last_result := {} # what the aftermath screen shows
var march_note := "" # what happened on the road, shown when the battle opens
var results_unseen := false # the aftermath screen hasn't shown last_result yet


# ---------------------------------------------------------------- new game

func new_campaign() -> void:
	active = true
	day = 1
	money = START_MONEY
	battles = 0
	victories = 0
	last_pay_day = 1
	next_id = 1
	roster.clear()
	fallen.clear()
	officer = {"kills": 0, "battles": 0, "rank": "Ensign"}
	last_result = {}
	results_unseen = false
	# Captain Harrow's company at full strength, before the battle: a sergeant,
	# some veterans, mostly musketeers, a few green recruits. All in uniform.
	stores = {"items": {}, "water": WATER_CART, "rations": 0, "ammo": 0, "rum": 0, "foul": false, "grog": true}
	for i in PROLOGUE_MEN:
		var m := make_recruit()
		var rank := 3 if i == 0 else (2 if i < 4 else (1 if i < 13 else 0))
		m["rank"] = rank
		m["xp"] = RANK_XP[rank] + randi_range(0, 60)
		Men.auto_spend(m, (Men.level(m) - 1) * Men.POINTS_PER_LEVEL)
		m["morale"] = 70
		m["battles"] = rank * 2 + randi_range(0, 2)
		m["gear"] = REGULAR_GEAR.duplicate()
		m["pack"] = {"water": 1, "rations": 8, "ammo": 24}
		roster.append(m)
	prologue = true
	stash = {}
	next_battle = {}
	march_note = ""
	save()


func make_recruit() -> Dictionary:
	var m := {
		"id": next_id,
		"name": "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()],
		"reaction": randf_range(0.15, 1.1),
		"pace": randf_range(0.85, 1.15),
		"steadiness": randf_range(0.0, 0.85),
		"xp": 0,
		"rank": 0,
		"kills": 0,
		"battles": 0,
		"wounded_days": 0,
		"attrs": Men.new_attrs(),
		"points": 0, # unspent attribute points
		"morale": 55,
		"health": 100, # falls with hunger, thirst and sickness; 0 and he dies
		"thirst": 0, # days without water
		"hunger": 0, # days without food
		"sick": 0, # days of sickness left
		"gear": RECRUIT_GEAR.duplicate(),
		"pack": {"water": 1, "rations": 2, "ammo": 0},
	}
	next_id += 1
	return m


# ---------------------------------------------------------------- queries

static func title(m: Dictionary) -> String:
	return "%s %s" % [RANK_SHORT[int(m["rank"])], m["name"]]


static func surname_title(m: Dictionary) -> String:
	var parts: PackedStringArray = String(m["name"]).split(" ")
	return "%s %s" % [RANK_SHORT[int(m["rank"])], parts[parts.size() - 1]]


static func item_name(id: String) -> String:
	return String(ITEMS[id]["name"]) if ITEMS.has(id) else "None"


## Everything his gear does for him, in one place (see ITEMS).
static func gear_stats(m: Dictionary) -> Dictionary:
	var st := {"steady": 0.0, "pace": 0.0, "armour": 0.0, "spread": 1.0, "reload": 1.0,
		"misfire": 0.04, "melee": CLUBBED_DAMAGE, "bayonet": false}
	var gear: Dictionary = m.get("gear", REGULAR_GEAR)
	for slot in SLOTS:
		var id := String(gear.get(slot, ""))
		if not ITEMS.has(id):
			continue
		var it: Dictionary = ITEMS[id]
		st["steady"] += float(it.get("steady", 0.0))
		st["pace"] += float(it.get("pace", 0.0))
		st["armour"] += float(it.get("armour", 0.0))
		if it.has("spread"):
			st["spread"] = float(it["spread"])
			st["reload"] = float(it["reload"])
			st["misfire"] = float(it["misfire"])
		if it.has("melee"):
			st["melee"] = float(it["melee"])
			st["bayonet"] = true
	return st


## Morale of the whole company (the average man).
func company_morale() -> int:
	if roster.is_empty():
		return 0
	var t := 0
	for m in roster:
		t += int(m["morale"])
	return t / roster.size()


func fit_men() -> Array:
	return roster.filter(func(m): return int(m["wounded_days"]) <= 0)


func weekly_wages() -> int:
	var total := 0
	for m in roster:
		total += WAGES[int(m["rank"])]
	return total


## The warband you'll face next: grows as the company makes a name for itself.
func next_enemy_count() -> int:
	return clampi(8 + battles * 2 + randi_range(0, 3), 8, 40)


## Split a warband into the groups that arrive one after another.
static func waves_for(count: int) -> Array:
	if count <= 12:
		return [count]
	var first := int(count * 0.6)
	return [first, count - first]


# ---------------------------------------------------------------- after battle

## result = {"won": bool, "slain": int, "officer_kills": int,
##           "men": {id: {"kills": int, "status": "fit"|"wounded"|"killed"}}}
func apply_battle(result: Dictionary) -> void:
	var won: bool = result["won"]
	var men: Dictionary = result["men"]
	var was_prologue := bool(result.get("prologue", false))
	var summary := {"won": won, "slain": int(result["slain"]), "fallen": [], "wounded": [],
		"promoted": [], "levelled": [], "pay": 0, "day": day, "prologue": was_prologue, "lost_gear": 0}
	if not was_prologue:
		battles += 1
	officer["battles"] = int(officer["battles"]) + 1
	officer["kills"] = int(officer["kills"]) + int(result["officer_kills"])
	if won:
		victories += 1
	# A won field is yours to strip: the fallen's gear goes back to the wagon.
	var recover := won and not was_prologue

	var survivors: Array = []
	for m in roster:
		var r = men.get(int(m["id"]))
		if r == null:
			survivors.append(m) # didn't fight (wounded in camp)
			continue
		m["battles"] = int(m["battles"]) + 1
		m["kills"] = int(m["kills"]) + int(r["kills"])
		var pack: Dictionary = m["pack"]
		pack["ammo"] = maxi(0, int(pack["ammo"]) - int(r.get("ammo_used", 0)))
		if r["status"] == "killed":
			fallen.append({"name": m["name"], "rank": RANKS[int(m["rank"])], "day": day,
				"battles": m["battles"], "kills": m["kills"]})
			summary["fallen"].append(title(m))
			if recover:
				_strip_to_stores(m)
			continue
		var gained := XP_SURVIVE + XP_KILL * int(r["kills"]) + (XP_VICTORY if won else 0)
		var old_level := Men.level(m)
		m["xp"] = int(m["xp"]) + gained
		var levels := Men.level(m) - old_level
		if levels > 0:
			m["points"] = int(m["points"]) + levels * Men.POINTS_PER_LEVEL
			summary["levelled"].append("%s, level %d (+%d points)" % [title(m), Men.level(m), levels * Men.POINTS_PER_LEVEL])
		# A win lifts a man; a defeat, or a rout, weighs on him.
		Men.add_morale(m, -10 if was_prologue else (10 if won else -15))
		if r["status"] == "wounded":
			m["wounded_days"] = randi_range(3, 10)
			summary["wounded"].append("%s (%d days)" % [title(m), m["wounded_days"]])
		var new_rank := _rank_for(int(m["xp"]))
		if new_rank > int(m["rank"]):
			m["rank"] = new_rank
			summary["promoted"].append("%s, now %s" % [m["name"], RANKS[new_rank]])
		survivors.append(m)
	roster = survivors

	if was_prologue:
		_after_prologue(summary)
	elif won:
		# Pay: a bounty on every lizardman slain.
		summary["pay"] = 15 + 5 * int(result["slain"])
	else:
		# A beaten company loses a quarter of its purse and half its baggage;
		# what the men carry on their backs is all that's sure.
		summary["pay"] = -int(money * 0.25)
		for k in ["water", "rations", "ammo"]:
			stores[k] = int(stores[k]) / 2
		var items: Dictionary = stores["items"]
		for id in items.keys():
			var lost := int(ceil(int(items[id]) * 0.5))
			summary["lost_gear"] += lost
			items[id] = int(items[id]) - lost
	money = maxi(0, money + int(summary["pay"]))
	last_result = summary
	results_unseen = true
	save()


## The rout from the beach: men drop things, morale is low, the wagon holds
## next to nothing (the lizards have the ship's stores), and you are the
## company's captain now.
func _after_prologue(summary: Dictionary) -> void:
	prologue = false
	officer["rank"] = "Captain"
	stash = Lore.STASH.duplicate()
	for m in roster:
		m["morale"] = randi_range(26, 40) # castaways, beaten, in a strange land
	summary["captain"] = CAPTAIN
	var dropped := 0
	for m in roster:
		var gear: Dictionary = m["gear"]
		if randf() < 0.35 and gear["head"] != "":
			gear["head"] = ""
			dropped += 1
		if randf() < 0.2 and gear["secondary"] != "":
			gear["secondary"] = ""
			dropped += 1
		var pack: Dictionary = m["pack"]
		if randf() < 0.3:
			pack["rations"] = randi_range(1, 4) # a haversack torn away in the press
	summary["lost_gear"] = dropped
	money = 40 # the regiment's pay chest, what's left of it
	stores = {"items": {"rifle": 1, "sword_bayonet": 1, "musket": 1, "bayonet": 1},
		"water": 30, "rations": 20, "ammo": 50, "rum": 4, "foul": false, "grog": true}
	summary["pay"] = 0


func _strip_to_stores(m: Dictionary) -> void:
	var gear: Dictionary = m.get("gear", {})
	for slot in SLOTS:
		var id := String(gear.get(slot, ""))
		if ITEMS.has(id):
			add_item(id, 1)
	var pack: Dictionary = m.get("pack", {})
	for k in ["rations", "ammo"]:
		stores[k] = int(stores[k]) + int(pack.get(k, 0))


static func _rank_for(xp: int) -> int:
	var r := 0
	for i in RANK_XP.size():
		if xp >= RANK_XP[i]:
			r = i
	return r


# ---------------------------------------------------------------- camp actions

func can_hire() -> bool:
	return money >= RECRUIT_COST and roster.size() < MAX_COMPANY


func hire_recruit() -> Dictionary:
	if not can_hire():
		return {}
	money -= RECRUIT_COST
	var m := make_recruit()
	roster.append(m)
	save()
	return m


# ---------------------------------------------------------------- gear and stores

func add_item(id: String, n: int) -> void:
	var items: Dictionary = stores["items"]
	items[id] = int(items.get(id, 0)) + n
	if int(items[id]) <= 0:
		items.erase(id)


func item_count(id: String) -> int:
	return int(stores["items"].get(id, 0))


## Spare items in the wagon that fit `slot`, as [id, count] pairs.
func stored_for(slot: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id]["slot"] == slot and item_count(id) > 0:
			out.append([id, item_count(id)])
	return out


## Give a man an item from the wagon (or "" to take his off). What he had
## goes back into the wagon. A man always keeps a musket.
func equip(m: Dictionary, slot: String, id: String) -> bool:
	if id != "" and item_count(id) <= 0:
		return false
	if id == "" and (slot == "primary" or slot == "torso"):
		return false # a man always keeps his musket and his shirt
	var gear: Dictionary = m["gear"]
	var old := String(gear.get(slot, ""))
	if old == id:
		return false
	if id != "":
		add_item(id, -1)
	if old != "":
		add_item(old, 1)
	gear[slot] = id
	save()
	return true


## Move up to `amount` of water, rations or cartridges between the wagon
## (amount > 0: to the man) and his pack (< 0: back to the wagon).
func pack_move(m: Dictionary, key: String, amount: int) -> int:
	var pack: Dictionary = m["pack"]
	var have := int(pack[key])
	var cap := int(PACK[key]["max"])
	var n := 0
	if amount > 0:
		n = mini(amount, mini(int(stores[key]), cap - have))
	else:
		n = -mini(-amount, have)
	pack[key] = have + n
	stores[key] = int(stores[key]) - n
	return n


## Hand out the wagon's water, rations and cartridges evenly: one at a time
## round the company until every pack is full or the wagon is empty.
## ISSUE TO ALL: water, rations and cartridges shared out evenly.
func resupply_all() -> void:
	for key in PACK:
		share_evenly(key)


func can_buy(key: String) -> bool:
	return money >= int(SUPPLY[key][1])


func buy(key: String) -> void:
	if not can_buy(key):
		return
	money -= int(SUPPLY[key][1])
	stores[key] = int(stores[key]) + int(SUPPLY[key][0])
	save()


## One day on the road. Every man drinks and eats from his pack first, then
## from the wagon. Foul water makes men sick unless it's served as grog (a
## tot of rum each). Going without costs morale at once, then attributes and
## health (see men.gd); men who eat while their comrades starve breed
## resentment. Fed men heal and recover. Returns the day's notes.
## `water`: "random" (the old march), or what the map found today:
## "clean", "foul", or "" (a dry day).
func _road_day(water := "random") -> Dictionary:
	var day_notes := {"thirsty": 0, "hungry": 0, "sick": 0, "died": [], "unfair": false, "grog": 0, "dry": 0}
	# Water on the road today? Refill the barrels (and maybe they're foul).
	if water == "random":
		water = ("foul" if randf() < FOUL_WATER_CHANCE else "clean") if randf() < WATER_DAY_CHANCE else ""
	if water != "":
		stores["water"] = maxi(int(stores["water"]), WATER_CART)
		stores["foul"] = water == "foul"
	else:
		day_notes["dry"] = 1
	var ate: Array = []
	var starved: Array = []
	for m in roster:
		var pack: Dictionary = m["pack"]
		var drank := _take(pack, "water")
		var fed := _take(pack, "rations")
		if drank and bool(stores["foul"]):
			if bool(stores["grog"]) and int(stores["rum"]) > 0:
				stores["rum"] = int(stores["rum"]) - 1
				day_notes["grog"] += 1
				Men.add_morale(m, 1) # the men love their grog
			elif int(m["sick"]) <= 0 and randf() < SICK_CHANCE - 0.012 * (int(m["attrs"]["constitution"]) - Men.ATTR_BASE):
				m["sick"] = randi_range(3, 6)
				day_notes["sick"] += 1
		m["thirst"] = 0 if drank else int(m["thirst"]) + 1
		m["hunger"] = 0 if fed else int(m["hunger"]) + 1
		if not drank:
			day_notes["thirsty"] += 1
			Men.add_morale(m, -12)
		if not fed:
			day_notes["hungry"] += 1
			Men.add_morale(m, -8)
			starved.append(m)
		else:
			ate.append(m)
		# Health: thirst kills in days, hunger more slowly, sickness wears.
		var con := int(m["attrs"]["constitution"])
		var harm := 0
		if int(m["thirst"]) >= 2:
			harm += 20 * (int(m["thirst"]) - 1)
		if int(m["hunger"]) >= 4:
			harm += 8 * (int(m["hunger"]) - 3)
		if int(m["sick"]) > 0:
			harm += 6
			Men.add_morale(m, -4)
			m["sick"] = maxi(0, int(m["sick"]) - (2 if randf() < (con - 3) * 0.08 else 1))
		if harm > 0:
			m["health"] = int(m["health"]) - maxi(1, harm - (con - Men.ATTR_BASE) * 2)
		if drank and fed:
			if int(m["sick"]) <= 0:
				m["health"] = mini(100, int(m["health"]) + 5 + con)
			if int(m["morale"]) < 65:
				Men.add_morale(m, 2)
			# Wounds heal only on a full belly; a strong constitution heals faster.
			if int(m["wounded_days"]) > 0:
				var heal := 1 + (1 if randf() < (con - Men.ATTR_BASE) * 0.12 else 0)
				m["wounded_days"] = maxi(0, int(m["wounded_days"]) - heal)
	# Some ate while others went without: the hungry watch, and remember.
	if ate.size() > 0 and starved.size() > 0:
		day_notes["unfair"] = true
		for m in starved:
			Men.add_morale(m, -6)
	# Uneven packs: a man with far less than his mates feels cheated.
	var avg := 0.0
	for m in roster:
		avg += int(m["pack"]["rations"])
	avg /= maxf(1.0, roster.size())
	for m in roster:
		if int(m["pack"]["rations"]) + 3 <= avg:
			Men.add_morale(m, -2)
	for m in roster.duplicate():
		if int(m["health"]) <= 0:
			var cause := "thirst" if int(m["thirst"]) >= 2 else ("sickness" if int(m["sick"]) > 0 else "hunger")
			fallen.append({"name": m["name"], "rank": RANKS[int(m["rank"])], "day": day,
				"battles": m["battles"], "kills": m["kills"], "cause": cause})
			day_notes["died"].append("%s (%s)" % [title(m), cause])
			roster.erase(m)
	return day_notes


func _take(pack: Dictionary, key: String) -> bool:
	if int(pack[key]) > 0:
		pack[key] = int(pack[key]) - 1
		return true
	if int(stores[key]) > 0:
		stores[key] = int(stores[key]) - 1
		return true
	return false


## Days the wagon (and the packs) can feed and water the company.
func days_left(key: String) -> float:
	if roster.is_empty():
		return 0.0
	var total := int(stores[key])
	for m in roster:
		total += int(m["pack"][key])
	return float(total) / roster.size()


## Share the wagon's `key` out so every pack ends up as even as possible.
func share_evenly(key: String) -> void:
	# Pool what the men carry with the wagon, then deal it back out.
	var pool := int(stores[key])
	for m in roster:
		pool += int(m["pack"][key])
		m["pack"][key] = 0
	stores[key] = pool
	var cap := int(PACK[key]["max"])
	var men: Array = roster.duplicate()
	if men.is_empty():
		return
	var each := mini(cap, int(stores[key]) / men.size())
	for m in men:
		m["pack"][key] = each
		stores[key] = int(stores[key]) - each
	# The remainder, one each, while it lasts.
	for m in men:
		if int(stores[key]) <= 0:
			break
		if int(m["pack"][key]) < cap:
			m["pack"][key] = int(m["pack"][key]) + 1
			stores[key] = int(stores[key]) - 1
	save()


## How uneven the rations are: [the least a man carries, the most].
func ration_spread() -> Array:
	var lo := 999
	var hi := 0
	for m in roster:
		lo = mini(lo, int(m["pack"]["rations"]))
		hi = maxi(hi, int(m["pack"]["rations"]))
	return [lo if roster.size() > 0 else 0, hi]


## Average fitness sets the pace of the march.
func march_days() -> int:
	var days := randi_range(2, 4)
	if roster.is_empty():
		return days
	var fit := 0.0
	for m in roster:
		fit += Men.attr(m, "fitness")
	fit /= roster.size()
	if fit >= 7.0:
		days -= 1
	elif fit <= 3.5:
		days += 1
	return maxi(2, days)


## A day passing on the campaign map (the map's clock calls this at
## midnight). `water` is what the party passed today: "clean", "foul" or "".
## Returns notes worth showing the player.
func pass_day(water: String) -> PackedStringArray:
	day += 1
	var notes: PackedStringArray = []
	var dn := _road_day(water)
	if int(dn["thirsty"]) > 0:
		notes.append("%d men went thirsty." % int(dn["thirsty"]))
	if int(dn["hungry"]) > 0:
		notes.append("%d men went hungry." % int(dn["hungry"]))
	if int(dn["sick"]) > 0:
		notes.append("%d fell sick from foul water." % int(dn["sick"]))
	if bool(dn["unfair"]):
		notes.append("Some ate while others starved; there is muttering in the ranks.")
	if dn["died"].size() > 0:
		notes.append("Died: %s." % ", ".join(dn["died"]))
	if day - last_pay_day >= 7 and roster.size() > 0:
		last_pay_day += 7
		var wages := weekly_wages()
		if money >= wages:
			money -= wages
			notes.append("Wages paid: %d crowns." % wages)
			for m in roster:
				Men.add_morale(m, 3)
		else:
			money = 0
			notes.append("No pay! The men are angry.")
			for m in roster:
				Men.add_morale(m, -20)
	var gone: Array = roster.filter(func(m): return int(m["morale"]) < 12 and randf() < 0.12)
	for g in gone:
		roster.erase(g)
	if gone.size() > 0:
		notes.append("%d deserted in the night." % gone.size())
	var cm := company_morale()
	if roster.size() > 0 and cm < MUTINY_MORALE and randf() < (MUTINY_MORALE - cm) * 0.015:
		notes.append(_mutiny())
	save()
	return notes


## March to the next fight: days pass on the road (see _road_day), wages
## fall due, and a company with low morale may desert or mutiny.
func march_on() -> String:
	var days := march_days()
	day += days
	var notes: PackedStringArray = ["%d days' march. Day %d." % [days, day]]
	var totals := {"thirsty": 0, "hungry": 0, "sick": 0, "grog": 0, "dry": 0, "foul": 0}
	var died: Array = []
	var unfair := false
	for i in days:
		var dn := _road_day()
		if bool(stores["foul"]):
			totals["foul"] += 1
		for k in ["thirsty", "hungry", "sick"]:
			totals[k] = maxi(int(totals[k]), int(dn[k]))
		totals["grog"] += int(dn["grog"])
		totals["dry"] += int(dn["dry"])
		died.append_array(dn["died"])
		unfair = unfair or bool(dn["unfair"])
	if totals["dry"] > 0:
		notes.append("%s without water on the road." % ("A day" if totals["dry"] == 1 else "%d days" % totals["dry"]))
	if totals["foul"] > 0:
		notes.append("Foul water for %s.%s" % ["a day" if totals["foul"] == 1 else "%d days" % totals["foul"],
			(" %d tots of rum went into the grog." % totals["grog"]) if totals["grog"] > 0 else " No grog!"])
	if totals["sick"] > 0:
		notes.append("%d fell sick." % totals["sick"])
	if totals["thirsty"] > 0:
		notes.append("%d went thirsty." % totals["thirsty"])
	if totals["hungry"] > 0:
		notes.append("%d went hungry." % totals["hungry"])
	if unfair:
		notes.append("Some ate while others starved; there is muttering in the ranks.")
	if died.size() > 0:
		notes.append("Died on the road: %s." % ", ".join(died))

	while day - last_pay_day >= 7 and roster.size() > 0:
		last_pay_day += 7
		var wages := weekly_wages()
		if money >= wages:
			money -= wages
			notes.append("Wages paid: %d crowns." % wages)
			for m in roster:
				Men.add_morale(m, 3)
		else:
			money = 0
			notes.append("No pay! The men are angry.")
			for m in roster:
				Men.add_morale(m, -20)

	# Desertion and mutiny.
	var gone: Array = roster.filter(func(m): return int(m["morale"]) < 12 and randf() < 0.3)
	for g in gone:
		roster.erase(g)
	if gone.size() > 0:
		notes.append("%d deserted in the night." % gone.size())
	var cm := company_morale()
	if roster.size() > 0 and cm < MUTINY_MORALE and randf() < (MUTINY_MORALE - cm) * 0.05:
		notes.append(_mutiny())

	# Camp: the barrels are refilled from whatever water there is.
	stores["water"] = maxi(int(stores["water"]), WATER_CART)
	stores["foul"] = randf() < FOUL_WATER_CHANCE
	if bool(stores["foul"]):
		notes.append("The only water here is a muddy stream: the barrels are foul.")
	notes.append("Scouts report about %d lizardmen ahead." % next_enemy_count())
	march_note = " ".join(notes)
	save()
	return march_note


## The angriest men take what they can carry from the wagon and go.
func _mutiny() -> String:
	var men: Array = roster.duplicate()
	men.sort_custom(func(a, b): return int(a["morale"]) < int(b["morale"]))
	var n := maxi(1, men.size() / 3)
	var leaving := men.slice(0, n)
	for m in leaving:
		roster.erase(m)
	var share := 0.3
	for k in ["rations", "ammo", "rum"]:
		stores[k] = int(int(stores[k]) * (1.0 - share))
	var took := int(money * 0.25)
	money -= took
	# The ones who stayed are shaken, but the worst are gone.
	for m in roster:
		Men.add_morale(m, 10)
	return "MUTINY! %d men broke into the wagon and left with food, powder and %d crowns." % [n, took]


# ---------------------------------------------------------------- saving

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> void:
	var data := {
		"version": SAVE_VERSION, "day": day, "money": money, "battles": battles,
		"victories": victories, "last_pay_day": last_pay_day, "next_id": next_id,
		"roster": roster, "fallen": fallen, "officer": officer,
		"last_result": last_result, "march_note": march_note,
		"results_unseen": results_unseen, "stores": stores, "prologue": prologue, "stash": stash, "next_battle": next_battle,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))


func load_campaign() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	day = int(data.get("day", 1))
	money = int(data.get("money", 0))
	battles = int(data.get("battles", 0))
	victories = int(data.get("victories", 0))
	last_pay_day = int(data.get("last_pay_day", 1))
	next_id = int(data.get("next_id", 1))
	roster = data.get("roster", [])
	fallen = data.get("fallen", [])
	officer = data.get("officer", {"kills": 0, "battles": 0})
	if not officer.has("rank"):
		officer["rank"] = "Captain"
	prologue = bool(data.get("prologue", false))
	stash = data.get("stash", {})
	next_battle = data.get("next_battle", {})
	stores = data.get("stores", {"items": {"musket": 1, "bayonet": 1}, "water": WATER_CART, "rations": 40, "ammo": 120})
	last_result = data.get("last_result", {})
	march_note = String(data.get("march_note", ""))
	results_unseen = bool(data.get("results_unseen", false))
	# JSON numbers come back as floats; ids are used as keys, keep them ints.
	# Older saves had no gear: everyone gets a regular's kit.
	for m in roster:
		m["id"] = int(m["id"])
		if not m.has("gear"):
			m["gear"] = REGULAR_GEAR.duplicate()
		if not m.has("pack"):
			m["pack"] = {"water": 1, "rations": 6, "ammo": 24}
		for k in m["pack"]:
			m["pack"][k] = int(m["pack"][k])
		Men.migrate(m)
	stores["rum"] = int(stores.get("rum", 0))
	stores["foul"] = bool(stores.get("foul", false))
	stores["grog"] = bool(stores.get("grog", true))
	var items: Dictionary = stores["items"]
	for id in items:
		items[id] = int(items[id])
	for k in ["water", "rations", "ammo"]:
		stores[k] = int(stores[k])
	active = true
	return true
