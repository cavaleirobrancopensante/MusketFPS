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
const Officer := preload("res://scripts/officer.gd")
## Saved in the current slot's folder (see Settings.slot_dir()).
func save_path() -> String:
	return "%s/campaign.json" % Settings.slot_dir()

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
	"secondary": "Secondary weapon", "pistol": "Sidearm", "sword": "Sword"}
## The officer carries two more: a pistol and a sword (see officer.gd).
const OFFICER_SLOTS := ["head", "torso", "primary", "secondary", "pistol", "sword"]
## Item stats (all optional): steady (+steadiness), pace (+/- fraction),
## armour (fraction of melee damage turned), spread / reload (multipliers),
## misfire (chance), melee (bayonet damage).
const ITEMS := {
	"bicorne": {"name": "Officer's bicorne", "slot": "head", "steady": 0.05, "kg": 0.5, "space": 0.5, "value": 8,
		"desc": "Black felt, gold lace, a red cockade. The men can find you in the smoke."},
	"officer_coat": {"name": "Officer's coat", "slot": "torso", "steady": 0.05, "kg": 2.2, "space": 0.6, "value": 15,
		"desc": "Fine blue wool with white lapels, gold buttons and a crimson sash."},
	"shako": {"name": "Shako", "slot": "head", "steady": 0.05, "kg": 0.4, "space": 0.4, "value": 3,
		"desc": "Regulation felt shako with a brass plate. A man stands taller in it."},
	"tricorne": {"name": "Tricorne", "slot": "head", "steady": 0.03, "kg": 0.4, "space": 0.4, "value": 2,
		"desc": "An old cocked hat from the last war."},
	"cap": {"name": "Forage cap", "slot": "head", "kg": 0.2, "space": 0.2, "value": 1,
		"desc": "A soft wool cap. Keeps the sun off, nothing more."},
	"coat": {"name": "Regulation coat", "slot": "torso", "steady": 0.05, "kg": 2.0, "space": 0.6, "value": 6,
		"desc": "Blue wool coat with white crossbelts. The uniform of the line."},
	"shirt": {"name": "Linen shirt", "slot": "torso", "pace": 0.05, "kg": 0.5, "space": 0.3, "value": 1,
		"desc": "Light and cool. No protection at all."},
	"buffcoat": {"name": "Buff coat", "slot": "torso", "armour": 0.3, "pace": -0.06, "kg": 4.0, "space": 1.0, "value": 10,
		"desc": "Thick oiled leather. Turns a glancing hack, but it's heavy."},
	"musket": {"name": "Land musket", "slot": "primary", "spread": 1.0, "reload": 1.0, "misfire": 0.04, "kg": 4.5, "space": 1.0, "value": 30,
		"desc": "Smoothbore flintlock, .75 bore. Reliable."},
	"worn_musket": {"name": "Worn musket", "slot": "primary", "spread": 1.35, "reload": 1.05, "misfire": 0.12, "kg": 4.5, "space": 1.0, "value": 12,
		"desc": "Pitted barrel, tired lock. Misfires often and scatters wide."},
	"rifle": {"name": "Rifle", "slot": "primary", "spread": 0.4, "reload": 1.6, "misfire": 0.05, "kg": 4.5, "space": 1.0, "value": 50,
		"desc": "A rifled barrel: deadly accurate, slow to load."},
	"bayonet": {"name": "Socket bayonet", "slot": "secondary", "melee": 34.0, "kg": 0.4, "space": 0.2, "value": 4,
		"desc": "Fixed on the muzzle, it turns the musket into a pike."},
	"sword_bayonet": {"name": "Sword bayonet", "slot": "secondary", "melee": 42.0, "kg": 0.8, "space": 0.3, "value": 8,
		"desc": "A long, heavy blade made for the rifle."},
	# Pole arms: no gun, but reach. Pikemen hold the line in front of the muskets.
	"pike": {"name": "Boarding pike", "slot": "primary", "melee": 40.0, "reach": 2.8, "kg": 3.0, "space": 1.5, "value": 6,
		"desc": "A ship's boarding pike, nine feet of ash and iron. Keeps them at arm's length and more."},
	"spear": {"name": "Lizard spear", "slot": "primary", "melee": 32.0, "reach": 2.3, "kg": 2.0, "space": 1.2, "value": 4,
		"desc": "A crude spear with a chipped stone head. Light, and longer than it looks."},
	"cleaver": {"name": "Lizard cleaver", "slot": "secondary", "melee": 30.0, "kg": 2.5, "space": 0.6, "value": 5,
		"desc": "A heavy, crude blade. Better than clubbing with a musket butt."},
	# An officer's sidearms.
	"pistol": {"name": "Sea-service pistol", "slot": "pistol", "kg": 1.2, "space": 0.3, "value": 18,
		"desc": "A heavy flintlock pistol. One shot, close in, then a slow reload."},
	"saber": {"name": "Infantry sabre", "slot": "sword", "melee": 44.0, "kg": 1.3, "space": 0.4, "value": 14,
		"desc": "A curved, single-edged blade. Quicker than a bayonet, made for cutting."},
	"cutlass": {"name": "Ship's cutlass", "slot": "sword", "melee": 40.0, "kg": 1.4, "space": 0.4, "value": 8,
		"desc": "Short, broad and heavy. A sailor's blade."},
	# The land's own weapons: what native recruits bring (folk.gd), and what
	# markets sell. "missile" says what it shoots (and so which store refills
	# his pack: ammo = cartridges, arrows, bolts); "range" how far he'll loose.
	"hunting_bow": {"name": "Hunting bow", "slot": "primary", "missile": "arrow", "spread": 1.5, "reload": 0.42, "misfire": 0.0,
		"range": 36.0, "kg": 1.0, "space": 1.0, "value": 6,
		"desc": "A short bow of horn and wood. Quick to shoot, light arrows; it can loose over the heads of the line."},
	"war_bow": {"name": "War bow", "slot": "primary", "missile": "arrow", "spread": 1.25, "reload": 0.5, "misfire": 0.0,
		"range": 46.0, "dmg": 1.3, "kg": 1.2, "space": 1.2, "value": 14,
		"desc": "A Vellish longbow, taller than the man. Long range and a heavy shaft, if he has the arms for it."},
	"crossbow": {"name": "Crossbow", "slot": "primary", "missile": "bolt", "spread": 0.8, "reload": 1.15, "misfire": 0.01,
		"range": 40.0, "kg": 3.5, "space": 1.2, "value": 20,
		"desc": "Steel prod and a windlass. Slow to span, flat and hard-hitting: a bolt goes through a lizard's hide."},
	"dwarf_crossbow": {"name": "Dwarf crossbow", "slot": "primary", "missile": "bolt", "spread": 0.6, "reload": 1.25, "misfire": 0.01,
		"range": 44.0, "dmg": 1.25, "kg": 4.5, "space": 1.3, "value": 40,
		"desc": "Dwarf-forged: a prod like a cart spring and a lock that never slips. Worth its weight."},
	"war_spear": {"name": "Spear", "slot": "primary", "melee": 36.0, "reach": 2.5, "kg": 2.2, "space": 1.3, "value": 5,
		"desc": "Ash shaft, iron head. The village militia's weapon: cheap, long, and good in a line."},
	"hatchet": {"name": "Hatchet", "slot": "secondary", "melee": 26.0, "kg": 0.9, "space": 0.3, "value": 2,
		"desc": "A woodsman's axe. What an archer fights with when they get too close."},
	"long_knife": {"name": "Long knife", "slot": "secondary", "melee": 22.0, "kg": 0.4, "space": 0.2, "value": 2,
		"desc": "A hunting knife as long as a forearm."},
	"tunic": {"name": "Wool tunic", "slot": "torso", "pace": 0.03, "kg": 0.8, "space": 0.4, "value": 1,
		"desc": "Homespun wool, the colour of the hills."},
	"jack": {"name": "Padded jack", "slot": "torso", "armour": 0.15, "pace": -0.02, "kg": 2.5, "space": 0.8, "value": 6,
		"desc": "Layers of quilted linen. Turns a slash, if not a thrust."},
	"hood": {"name": "Hood", "slot": "head", "kg": 0.3, "space": 0.2, "value": 1,
		"desc": "A woollen hood and short cape."},
	"kettle_hat": {"name": "Kettle hat", "slot": "head", "steady": 0.04, "armour": 0.05, "kg": 1.5, "space": 0.6, "value": 7,
		"desc": "A broad-brimmed iron helmet, the town watch's hat."},
	# Goods: no use to us, but worth something to someone.
	"lizard_shield": {"name": "Lizard shield", "slot": "goods", "kg": 4.0, "space": 1.2, "value": 6,
		"desc": "Hide stretched over a wicker frame. Collectors in the towns pay for them."},
	"hide": {"name": "Scaled hide", "slot": "goods", "kg": 5.0, "space": 1.0, "value": 4,
		"desc": "Tough scaled leather. Tanners want it."},
	"charm": {"name": "Bone charm", "slot": "goods", "kg": 0.2, "space": 0.1, "value": 8,
		"desc": "Carved bone strung on sinew. The locals think they're lucky, or cursed."},
}
## Weight (kg) and space of a unit of each kind of store.
const CONSUMABLES := {"water": [3.0, 0.12], "rations": [1.0, 0.04], "ammo": [0.05, 0.003], "rum": [0.15, 0.01],
	"arrows": [0.06, 0.005], "bolts": [0.08, 0.005], "powder": [1.0, 0.02], "lead": [1.0, 0.008]}
## Stores that refill a man's pack "ammo" by what his weapon shoots.
const SHOT_STORE := {"ball": "ammo", "arrow": "arrows", "bolt": "bolts"}
const SHOT_WORD := {"ammo": "cartridges", "arrows": "arrows", "bolts": "bolts"}
## Nobody here makes cartridges: you roll your own from powder and lead.
## A pound of powder makes CARTRIDGES_PER_POWDER; each takes a lead ball
## (BALLS_PER_LEAD to the pound).
const CARTRIDGES_PER_POWDER := 40
const BALLS_PER_LEAD := 14
const CARTRIDGE_BATCH := 40 # one evening's work: 1 lb of powder, 3 lb of lead
const WAGON_KG := 900.0 # before your Logistics skill (see wagon_kg())
const WAGON_SPACE := 60.0
## What each kind of slain enemy may leave behind: [item id, chance per body].
const LOOT_TABLE := {"lizards": [["cleaver", 0.22], ["lizard_shield", 0.12], ["hide", 0.2], ["charm", 0.1],
	["spear", 0.08], ["stolen", 0.06]],
	"humans": [["pike", 0.18], ["crossbow", 0.08], ["war_bow", 0.06], ["jack", 0.14], ["kettle_hat", 0.12],
	["purse", 0.3], ["rations", 0.2]]}
const PIKE_GEAR := {"head": "cap", "torso": "shirt", "primary": "pike", "secondary": ""}
const DEFAULT_TAGS := ["Musketeers", "Pikes", "Wagon"]
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
var stores := {"items": {}, "water": 0, "rations": 0, "ammo": 0, "rum": 0, "foul": false, "grog": true,
	"arrows": 0, "bolts": 0, "powder": 0, "lead": 0}
var prologue := false # the opening battle is still to be fought
## The ship's stores the lizards carried off (muskets, cartridges, guns,
## rum): recovering them is the first great objective. Empty once recovered.
var stash := {}
## Field guns the company has (the ship's, once recovered from the stash):
## each goes into battle with its crew (gun_crew.gd).
var guns := 0
## How the nations see you: below HOSTILE_AT their patrols hunt you. Attack
## a nation's men and it falls; the other side (they're at war) warms a
## little.
var standing := {"aurest": 0, "vell": 0}
const HOSTILE_AT := -25
const AT_WAR := {"aurest": "vell", "vell": "aurest"}


## Service under a lord (see the contracts section): {} or {"lord", "faction",
## "lord_name", "from", "until" (days), "pay" (a week), "duty", "need",
## "done", "paid_day"}.
var contract := {}


func is_enemy(faction: String) -> bool:
	return int(standing.get(faction, 0)) <= HOSTILE_AT


func change_standing(faction: String, by: int) -> void:
	if not standing.has(faction):
		return
	standing[faction] = clampi(int(standing[faction]) + by, -100, 100)


func standing_word(faction: String) -> String:
	var s := int(standing.get(faction, 0))
	if s <= HOSTILE_AT:
		return "hostile"
	if s < 0:
		return "wary"
	if s < 20:
		return "neutral"
	return "friendly"
## A fight the map has started: {"enemy": int, "terrain": int, "party": id}.
var next_battle := {}
## The battle plan: tags (groups) the player has made; each man has m["tag"]
## and maybe m["plan"] = [x, y]: metres right of the officer and forward
## toward the enemy. The wagon has its own place (usually at the rear).
var tags: Array = DEFAULT_TAGS.duplicate()
var wagon_plan := [0.0, -12.0]
## What was left on the field after the last battle: [{"id", "n"}], to pick
## through on the loot screen.
var loot: Array = []
var tongues := {} # lang -> {"fluency", "words"} (see tongue.gd)
var towns := {} # settlement id (string) -> {"rep", "npcs", "visits"} (see folk.gd)
var visiting := -1 # the settlement you've walked into (town.tscn)
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
	officer = Officer.blank()
	last_result = {}
	results_unseen = false
	# Captain Harrow's company at full strength, before the battle: a sergeant,
	# some veterans, mostly musketeers, a few green recruits. All in uniform.
	stores = {"items": {}, "water": WATER_CART, "rations": 0, "ammo": 0, "rum": 0, "foul": false, "grog": true,
		"arrows": 0, "bolts": 0, "powder": 0, "lead": 0}
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
		m["tag"] = "Musketeers"
		if i >= PROLOGUE_MEN - 3:
			# Three of the ship's sailors with boarding pikes.
			m["gear"] = PIKE_GEAR.duplicate()
			m["pack"]["ammo"] = 0
			m["tag"] = "Pikes"
		roster.append(m)
	tags = DEFAULT_TAGS.duplicate()
	wagon_plan = [0.0, -12.0]
	loot = []
	tongues = {}
	towns = {}
	visiting = -1
	ensure_wagon_crew()
	prologue = true
	stash = {}
	guns = 0
	standing = {"aurest": 0, "vell": 0}
	contract = {}
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
		"tag": "Musketeers",
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


## Which store his pack's "ammo" comes from: "ammo" (cartridges), "arrows",
## "bolts", or "" for a pole arm.
static func shot_key(m: Dictionary) -> String:
	var id := String(m.get("gear", {}).get("primary", "musket"))
	var it: Dictionary = ITEMS.get(id, {})
	if it.has("reach"):
		return ""
	return String(SHOT_STORE.get(String(it.get("missile", "ball")), "ammo"))


## What he is in a fight, by his weapon: "musket", "bow", "crossbow", "pike".
static func role_of(m: Dictionary) -> String:
	var id := String(m.get("gear", {}).get("primary", "musket"))
	var it: Dictionary = ITEMS.get(id, {})
	if it.has("reach"):
		return "pike"
	match String(it.get("missile", "ball")):
		"arrow": return "bow"
		"bolt": return "crossbow"
	return "musket"


## The word for what's in his pack: "cartridges", "arrows", "bolts".
static func shot_word(m: Dictionary) -> String:
	return String(SHOT_WORD.get(shot_key(m), "shot"))


## Everything his gear does for him, in one place (see ITEMS).
static func gear_stats(m: Dictionary) -> Dictionary:
	var st := {"steady": 0.0, "pace": 0.0, "armour": 0.0, "spread": 1.0, "reload": 1.0,
		"misfire": 0.04, "melee": CLUBBED_DAMAGE, "bayonet": false, "gun": true, "reach": 0.0,
		"missile": "ball", "range": 40.0, "dmg": 1.0}
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
			st["missile"] = String(it.get("missile", "ball"))
			st["range"] = float(it.get("range", 40.0))
			st["dmg"] = float(it.get("dmg", 1.0))
		if it.has("melee"):
			st["melee"] = maxf(float(st["melee"]), float(it["melee"]))
			st["bayonet"] = true
		if it.has("reach"):
			st["gun"] = false # a pole arm instead of a musket
			st["reach"] = float(it["reach"])
			st["missile"] = ""
	return st


## Morale of the whole company (the average man).
func company_morale() -> int:
	if roster.is_empty():
		return 0
	var t := 0
	for m in roster:
		t += int(m["morale"])
	return t / roster.size()


## Men who can fight: not wounded, and not away scouting.
func fit_men() -> Array:
	return roster.filter(func(m): return int(m["wounded_days"]) <= 0 and not m.get("away", false))


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
	var summary := {"enemy": String(result.get("enemy", "lizards")), "allies_left": int(result.get("allies_left", 0)), "won": won, "slain": int(result["slain"]), "fallen": [], "wounded": [],
		"promoted": [], "levelled": [], "pay": 0, "day": day, "prologue": was_prologue, "lost_gear": 0}
	if not was_prologue:
		battles += 1
	officer["battles"] = int(officer["battles"]) + 1
	officer["kills"] = int(officer["kills"]) + int(result["officer_kills"])
	var opack: Dictionary = officer.get("pack", {})
	opack["ammo"] = maxi(0, int(opack.get("ammo", 0)) - int(result.get("officer_ammo", 0)))
	var oxp := Officer.XP_BATTLE + Officer.XP_KILL * int(result["officer_kills"]) + (Officer.XP_VICTORY if won else 0)
	var oup := Officer.gain_xp(oxp)
	summary["officer_xp"] = oxp
	if oup > 0:
		summary["officer_level"] = Officer.level()
	if won:
		victories += 1
	# A won field is yours to strip: the fallen's gear and what the enemy
	# left go on the loot pile (see the loot screen).
	var recover := won and not was_prologue
	loot = []

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
		if r["status"] == "killed" and won and not was_prologue and randf() < Officer.save_chance():
			# Your surgery: he was breathing after all.
			r["status"] = "wounded"
			summary.get_or_add("saved", []).append(title(m))
		if r["status"] == "killed":
			fallen.append({"name": m["name"], "rank": RANKS[int(m["rank"])], "day": day,
				"battles": m["battles"], "kills": m["kills"]})
			summary["fallen"].append(title(m))
			if recover:
				# His comrades carry his kit back to the wagon.
				var back := recover_kit(m)
				if back[0] != "":
					summary.get_or_add("kit_home", []).append("%s: %s" % [title(m), back[0]])
				summary["kit_left"] = int(summary.get("kit_left", 0)) + int(back[1])
			continue
		var gained := int(round((XP_SURVIVE + XP_KILL * int(r["kills"]) + (XP_VICTORY if won else 0)) * Officer.xp_mult()))
		var old_level := Men.level(m)
		m["xp"] = int(m["xp"]) + gained
		var levels := Men.level(m) - old_level
		if levels > 0:
			m["points"] = int(m["points"]) + levels * Men.POINTS_PER_LEVEL
			summary["levelled"].append("%s, level %d (+%d points)" % [title(m), Men.level(m), levels * Men.POINTS_PER_LEVEL])
		# A win lifts a man; a defeat, or a rout, weighs on him.
		Men.add_morale(m, -10 if was_prologue else (10 if won else -15))
		# The wagon crew: running shames a man, standing to it makes him proud.
		match String(r.get("conduct", "")):
			"fled":
				Men.add_morale(m, -6)
				summary.get_or_add("conduct", []).append("%s ran from the wagon" % title(m))
			"stood":
				Men.add_morale(m, 3)
				summary.get_or_add("conduct", []).append("%s held the wagon" % title(m))
			"fought":
				Men.add_morale(m, 6)
				summary.get_or_add("conduct", []).append("%s fought for the wagon" % title(m))
		if r["status"] == "wounded":
			m["wounded_days"] = maxi(1, int(round(randi_range(3, 10) * Officer.wound_mult())))
			summary["wounded"].append("%s (%d days)" % [title(m), m["wounded_days"]])
		var new_rank := _rank_for(int(m["xp"]))
		if new_rank > int(m["rank"]):
			m["rank"] = new_rank
			summary["promoted"].append("%s, now %s" % [m["name"], RANKS[new_rank]])
		survivors.append(m)
	roster = survivors

	# Food the looters ate before they were cut down is gone.
	var spoiled := mini(int(result.get("rations_spoiled", 0)), int(stores["rations"]))
	if spoiled > 0 and not was_prologue:
		stores["rations"] = int(stores["rations"]) - spoiled
		summary["rations_spoiled"] = spoiled
	# Looters still alive at the end (a lost fight) carried off their share.
	var looted := clampf(float(result.get("wagon_looted", 0.0)), 0.0, 0.8)
	if looted > 0.01 and not was_prologue:
		summary["wagon_looted"] = int(looted * 100)
		for k in ["rations", "ammo", "rum", "arrows", "bolts", "powder", "lead"]:
			stores[k] = int(int(stores.get(k, 0)) * (1.0 - looted))
		var its: Dictionary = stores["items"]
		for id in its.keys():
			its[id] = int(round(int(its[id]) * (1.0 - looted)))
			if int(its[id]) <= 0:
				its.erase(id)

	if was_prologue:
		_after_prologue(summary)
	elif won:
		# Pay: a bounty on every lizardman slain (nobody pays for men: what
		# they carried is the reward).
		summary["pay"] = 15 + 5 * int(result["slain"]) if String(result.get("enemy", "lizards")) == "lizards" else 0
		_loot_from(String(result.get("enemy", "lizards")), int(result["slain"]))
		if int(result.get("assault", -1)) >= 0:
			# A burned nest: what they'd hoarded from a dozen raids.
			summary["nest_burned"] = String(result.get("nest_name", "the nest"))
			summary["pay"] = int(summary["pay"]) + 60
			for i in randi_range(4, 8):
				_add_loot(["rations", "rum", "crowns", "charm", "hide", "lizard_shield"].pick_random(), randi_range(3, 12))
			if bool(result.get("stash", false)) and not stash.is_empty():
				summary["stash"] = recover_stash()
		# Arrows and bolts can be picked up again: about half are whole.
		for k in ["arrows", "bolts"]:
			var spent := int(result.get(k + "_spent", 0))
			var whole := int(round(spent * randf_range(0.4, 0.6)))
			if whole > 0:
				_add_loot(k, whole, true)
		summary["loot"] = loot.size()
	else:
		# A beaten company loses a quarter of its purse and half its baggage;
		# what the men carry on their backs is all that's sure.
		summary["pay"] = -int(money * 0.25)
		for k in ["water", "rations", "ammo", "arrows", "bolts", "powder", "lead"]:
			stores[k] = int(stores.get(k, 0)) / 2
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
		"water": 30, "rations": 20, "ammo": 50, "rum": 4, "foul": false, "grog": true,
		"arrows": 0, "bolts": 0, "powder": 1, "lead": 6}
	summary["pay"] = 0


## A dead man's kit and pack go back to the wagon, to arm the next man
## (a native recruit, say). Whatever won't fit stays on the loot pile, marked
## as ours, so you can choose what to throw out of the wagon to make room
## (the loot screen). Returns [what was stowed, how many things were left].
func recover_kit(m: Dictionary) -> Array:
	var got: Array = []
	var left := 0
	var gear: Dictionary = m.get("gear", {})
	for slot in SLOTS:
		var id := String(gear.get(slot, ""))
		if not ITEMS.has(id):
			continue
		if stow(id, 1) == 1:
			got.append(item_name(id).to_lower())
		else:
			_add_loot(id, 1, true)
			left += 1
		gear[slot] = ""
	var pack: Dictionary = m.get("pack", {})
	var sk := shot_key(m)
	for k in ["water", "rations", "ammo"]:
		var n := int(pack.get(k, 0))
		if n <= 0:
			continue
		var store: String = k if k != "ammo" else (sk if sk != "" else "ammo")
		var k_in := stow(store, n)
		if k_in > 0:
			got.append(("water for %d day%s" % [k_in, "" if k_in == 1 else "s"]) if k == "water" else "%d %s" % [k_in, "rations" if k == "rations" else String(SHOT_WORD.get(store, "shot"))])
		if k_in < n:
			_add_loot(store, n - k_in, true)
			left += 1
		pack[k] = 0
	return [", ".join(got), left]


## What the slain left behind: their weapons, hides and charms, and now and
## then something they had stolen.
func _loot_from(enemy: String, slain: int) -> void:
	for i in slain:
		for row in LOOT_TABLE.get(enemy, []):
			if randf() >= float(row[1]):
				continue
			if row[0] == "purse":
				_add_loot("crowns", randi_range(2, 9))
			elif row[0] == "stolen":
				match randi() % 4:
					0: _add_loot("rations", randi_range(4, 10))
					1: _add_loot("rum", randi_range(3, 6))
					2: _add_loot("ammo", randi_range(10, 30))
					_: _add_loot("crowns", randi_range(2, 10))
			else:
				_add_loot(String(row[0]), 1)


## The ship's stores, taken back: the guns join the company, the rest goes
## into the wagon (and what won't fit waits on the loot pile, marked ours).
## Returns a line for the aftermath.
func recover_stash() -> String:
	var s := stash
	guns += int(s.get("cannons", 0))
	var got: PackedStringArray = []
	for pair in [["musket", int(s.get("muskets", 0))], ["ammo", int(s.get("ammo", 0))], ["rum", int(s.get("rum", 0))]]:
		var id: String = pair[0]
		var n: int = pair[1]
		if n <= 0:
			continue
		var k := stow(id, n)
		if k < n:
			_add_loot(id, n - k, true)
		got.append("%d %s" % [n, {"musket": "muskets", "ammo": "cartridges", "rum": "tots of rum"}[id]])
	got.append("%d guns" % int(s.get("cannons", 0)))
	stash = {}
	return ", ".join(got)


## `ours`: the kit of our own dead, kept apart from the enemy's leavings and
## shown first on the loot screen.
func _add_loot(id: String, n: int, ours := false) -> void:
	for l in loot:
		if l["id"] == id and bool(l.get("ours", false)) == ours:
			l["n"] = int(l["n"]) + n
			return
	var e := {"id": id, "n": n}
	if ours:
		e["ours"] = true
		loot.insert(0, e)
	else:
		loot.append(e)


## How much of our own dead's kit is still on the pile.
func ours_left() -> int:
	var n := 0
	for l in loot:
		if bool(l.get("ours", false)):
			n += int(l["n"])
	return n


func _strip_to_stores(m: Dictionary) -> void:
	var gear: Dictionary = m.get("gear", {})
	for slot in SLOTS:
		var id := String(gear.get(slot, ""))
		if ITEMS.has(id):
			add_item(id, 1)
	var pack: Dictionary = m.get("pack", {})
	stores["rations"] = int(stores["rations"]) + int(pack.get("rations", 0))
	var sk := shot_key(m)
	stores[sk if sk != "" else "ammo"] = int(stores.get(sk if sk != "" else "ammo", 0)) + int(pack.get("ammo", 0))


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
	var before := shot_key(m)
	if id != "":
		add_item(id, -1)
	if old != "":
		add_item(old, 1)
	gear[slot] = id
	if slot == "primary" and shot_key(m) != before:
		# A different weapon shoots different things: his pouch goes back to the wagon.
		var pk: Dictionary = m["pack"]
		var back := before if before != "" else "ammo"
		stores[back] = int(stores.get(back, 0)) + int(pk.get("ammo", 0))
		pk["ammo"] = 0
	save()
	return true


## Move up to `amount` of water, rations or cartridges between the wagon
## (amount > 0: to the man) and his pack (< 0: back to the wagon).
func pack_move(m: Dictionary, key: String, amount: int) -> int:
	var pack: Dictionary = m["pack"]
	var have := int(pack[key])
	var cap := int(PACK[key]["max"])
	var store := key
	if key == "ammo":
		store = shot_key(m)
		if store == "":
			# A pikeman has nothing to shoot: anything in his pouch goes back.
			stores["ammo"] = int(stores["ammo"]) + have
			pack[key] = 0
			return -have
	var n := 0
	if amount > 0:
		n = mini(amount, mini(int(stores.get(store, 0)), cap - have))
	else:
		n = -mini(-amount, have)
	pack[key] = have + n
	stores[store] = int(stores.get(store, 0)) - n
	return n


## Hand out the wagon's water, rations and cartridges evenly: one at a time
## round the company until every pack is full or the wagon is empty.
## ISSUE TO ALL: water, rations and cartridges shared out evenly.
func resupply_all() -> void:
	for key in PACK:
		share_evenly(key)


# ---------------------------------------------------------------- the wagon's load

## [kg, space] of `n` of something (an item id or a store like "rations").
static func load_of(id: String, n: int) -> Array:
	if CONSUMABLES.has(id):
		return [CONSUMABLES[id][0] * n, CONSUMABLES[id][1] * n]
	if ITEMS.has(id):
		return [float(ITEMS[id].get("kg", 1.0)) * n, float(ITEMS[id].get("space", 0.5)) * n]
	return [0.0, 0.0] # crowns


## What the wagon is carrying: [kg, space].
func wagon_load() -> Array:
	var kg := 0.0
	var sp := 0.0
	for k in CONSUMABLES:
		var l := load_of(k, int(stores.get(k, 0)))
		kg += l[0]
		sp += l[1]
	for id in stores["items"]:
		var l2 := load_of(id, int(stores["items"][id]))
		kg += l2[0]
		sp += l2[1]
	return [kg, sp]


## How many of `id` still fit in the wagon.
func room_for(id: String) -> int:
	var l := load_of(id, 1)
	if l[0] <= 0.0 and l[1] <= 0.0:
		return 999999
	var w := wagon_load()
	var by_kg := int(floor((wagon_kg() - w[0]) / maxf(l[0], 0.0001)))
	var by_sp := int(floor((wagon_space() - w[1]) / maxf(l[1], 0.0001)))
	return maxi(0, mini(by_kg, by_sp))


## Put up to `n` of something into the wagon (as far as it fits). Returns how many.
func stow(id: String, n: int) -> int:
	if id == "crowns":
		money += n
		return n
	var k := mini(n, room_for(id))
	if k <= 0:
		return 0
	if CONSUMABLES.has(id):
		stores[id] = int(stores[id]) + k
	else:
		add_item(id, k)
	return k


## Take up to `n` from the loot pile into the wagon.
func take_loot(index: int, n: int) -> int:
	if index < 0 or index >= loot.size():
		return 0
	var l: Dictionary = loot[index]
	var k := stow(String(l["id"]), mini(n, int(l["n"])))
	l["n"] = int(l["n"]) - k
	if int(l["n"]) <= 0:
		loot.remove_at(index)
	return k


## Put something from the wagon back on the pile (to make room).
func drop_to_loot(id: String, n: int) -> int:
	var have := int(stores.get(id, 0)) if CONSUMABLES.has(id) else item_count(id)
	var k := mini(n, have)
	if k <= 0:
		return 0
	if CONSUMABLES.has(id):
		stores[id] = int(stores[id]) - k
	else:
		add_item(id, -k)
	_add_loot(id, k)
	return k


static func item_label(id: String) -> String:
	match id:
		"water": return "Water (days)"
		"rations": return "Rations"
		"ammo": return "Cartridges"
		"rum": return "Rum (tots)"
		"arrows": return "Arrows"
		"bolts": return "Crossbow bolts"
		"powder": return "Powder (lb)"
		"lead": return "Lead (lb)"
		"crowns": return "Crowns"
	return item_name(id)


## Trade goods in the wagon and what a settlement of this kind pays for them.
func goods_value(kind: String) -> int:
	var f: float = {"village": 0.6, "town": 1.0, "city": 1.2, "hold": 1.1}.get(kind, 0.0)
	var total := 0.0
	for id in stores["items"]:
		if ITEMS.has(id) and (ITEMS[id]["slot"] == "goods" or id in ["cleaver", "spear"]):
			total += float(ITEMS[id].get("value", 0)) * int(stores["items"][id]) * f
	return int(total * Officer.sell_mult())


## What the wagon can carry: better with your Logistics.
func wagon_kg() -> float:
	return WAGON_KG * Officer.wagon_mult()


func wagon_space() -> float:
	return WAGON_SPACE * Officer.wagon_mult()


## A settlement's price for something, after your Trade.
func price(base: int) -> int:
	return maxi(1, int(round(base * Officer.buy_mult())))


func sell_goods(kind: String) -> int:
	var v := goods_value(kind)
	if v <= 0:
		return 0
	for id in stores["items"].keys():
		if ITEMS.has(id) and (ITEMS[id]["slot"] == "goods" or id in ["cleaver", "spear"]):
			stores["items"].erase(id)
	money += v
	save()
	return v


## The mixed order of battle (the plan's MIXED preset): muskets in a line
## through you, spears and pikes two paces in front of them, crossbows on the
## wings of the line, bows in a rank behind (they shoot over it). Sets each
## man's m["plan"].
static func mixed_places(men: Array) -> void:
	var by := {"musket": [], "pike": [], "bow": [], "crossbow": []}
	for m in men:
		by[role_of(m)].append(m)
	var line: Array = []
	var guns: Array = by["musket"]
	var xb: Array = by["crossbow"]
	# Crossbows split to the two ends of the musket line.
	for i in xb.size():
		if i % 2 == 0:
			line.push_front(xb[i])
		else:
			line.append(xb[i])
	var mid := (line.size() + 1) / 2
	for g in guns:
		line.insert(mid, g)
	_row(line, 0.0, 1.5, true)
	_row(by["pike"], 2.6, 1.4, true) # (a gap in front of you, so you can see)
	_row(by["bow"], -2.8, 1.6, false)


static func _row(men: Array, y: float, gap: float, officer_gap: bool) -> void:
	var n := men.size()
	for i in n:
		var x := (i - (n - 1) * 0.5) * gap
		if officer_gap:
			x += gap * 0.5 * (1.0 if x >= 0.0 else -1.0)
		men[i]["plan"] = [x, y]


# ---------------------------------------------------------------- markets and cartridges

## What a settlement sells: [store or item id, how many, crowns before your
## Trade, label]. Food everywhere; rum in towns; arrows where people hunt;
## bolts, lead and the town watch's kit in towns; and gunpowder only from the
## dwarves, who blast their mines with it and sell it dear.
static func market_offers(kind: String, fac: String) -> Array:
	var out: Array = []
	var food: Array = {"village": [10, 5], "town": [20, 9], "city": [20, 8], "hold": [20, 10]}.get(kind, [10, 6])
	out.append(["rations", food[0], food[1], "%d rations" % food[0]])
	if kind != "village":
		out.append(["rum", 10, 6, "10 tots of rum"])
	if kind != "hold":
		out.append(["arrows", 20, 3 if fac == "vell" else 4, "20 arrows"])
	if kind != "village":
		out.append(["bolts", 10, 5 if fac == "dwarves" else 6, "10 crossbow bolts"])
		out.append(["lead", 5, 6, "5 lb of lead"])
	if kind == "hold" or fac == "dwarves":
		out.append(["powder", 1, 24, "1 lb of blasting powder"])
		out.append(["dwarf_crossbow", 1, 70, "a dwarf crossbow"])
	elif kind in ["town", "city"]:
		out.append(["crossbow", 1, 34, "a crossbow"])
		out.append(["jack", 1, 10, "a padded jack"])
		out.append(["kettle_hat", 1, 11, "a kettle hat"])
	if fac == "vell" and kind != "village":
		out.append(["war_bow", 1, 22, "a war bow"])
	elif kind != "hold":
		out.append(["hunting_bow", 1, 9, "a hunting bow"])
	if kind != "hold":
		out.append(["war_spear", 1, 7, "a spear"])
	return out


## Buy one lot of an offer. Returns "" or why not.
func buy_offer(offer: Array) -> String:
	var id := String(offer[0])
	var n := int(offer[1])
	var cr := price(int(offer[2]))
	if money < cr:
		return "Not enough crowns."
	if room_for(id) < n:
		return "The wagon is full."
	money -= cr
	stow(id, n)
	save()
	return ""


## How many batches of cartridges the wagon's powder and lead make.
func cartridge_batches() -> int:
	var lead_per := int(ceil(float(CARTRIDGE_BATCH) / BALLS_PER_LEAD))
	return mini(int(stores.get("powder", 0)) * CARTRIDGES_PER_POWDER / CARTRIDGE_BATCH, int(stores.get("lead", 0)) / lead_per)


## Roll cartridges: melt lead into balls, measure powder into paper tubes.
## Returns how many were made.
func make_cartridges(batches := 1) -> int:
	var b := mini(batches, cartridge_batches())
	if b <= 0:
		return 0
	stores["powder"] = int(stores["powder"]) - b * CARTRIDGE_BATCH / CARTRIDGES_PER_POWDER
	stores["lead"] = int(stores["lead"]) - b * int(ceil(float(CARTRIDGE_BATCH) / BALLS_PER_LEAD))
	stores["ammo"] = int(stores["ammo"]) + b * CARTRIDGE_BATCH
	save()
	return b * CARTRIDGE_BATCH


## Two men to haul the wagon if nobody has been given the job: the two
## greenest musketeers.
func ensure_wagon_crew() -> void:
	if not tags.has("Wagon"):
		tags.append("Wagon")
	if roster.any(func(m): return m.get("tag", "") == "Wagon"):
		return
	var green: Array = roster.filter(func(m): return m.get("tag", "") == "Musketeers")
	green.sort_custom(func(a, b): return int(a["xp"]) < int(b["xp"]))
	for m in green.slice(0, 2):
		m["tag"] = "Wagon"


func can_buy(key: String) -> bool:
	return money >= int(SUPPLY[key][1])


func buy(key: String) -> void:
	if not can_buy(key) or room_for(key) < int(SUPPLY[key][0]):
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
	loot = [] # marching on leaves whatever you didn't take where it lay
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
			var back := recover_kit(m)
			var where := ""
			if int(back[1]) > 0:
				where = "; no room in the wagon for all his kit: CAMP, then LOOT THE FIELD"
			elif back[0] != "":
				where = "; his kit is in the wagon"
			day_notes["died"].append("%s (%s)%s" % [title(m), cause, where])
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
	if key == "ammo":
		# Each kind of shot goes to the men whose weapon fires it; pikemen
		# hand theirs in.
		for m in roster:
			if shot_key(m) == "":
				stores["ammo"] = int(stores["ammo"]) + int(m["pack"]["ammo"])
				m["pack"]["ammo"] = 0
		for store in SHOT_WORD:
			_share(key, store, roster.filter(func(mm): return shot_key(mm) == store))
	else:
		_share(key, key, roster.duplicate())
	save()


## Pool what `men` carry of pack `key` with the wagon's `store`, then deal it back out.
func _share(key: String, store: String, men: Array) -> void:
	var pool := int(stores.get(store, 0))
	for m in men:
		pool += int(m["pack"][key])
		m["pack"][key] = 0
	stores[store] = pool
	var cap := int(PACK[key]["max"])
	if men.is_empty():
		return
	var each := mini(cap, int(stores[store]) / men.size())
	for m in men:
		m["pack"][key] = each
		stores[store] = int(stores[store]) - each
	# The remainder, one each, while it lasts.
	for m in men:
		if int(stores[store]) <= 0:
			break
		if int(m["pack"][key]) < cap:
			m["pack"][key] = int(m["pack"][key]) + 1
			stores[store] = int(stores[store]) - 1


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
	notes.append_array(_contract_day())
	var gone: Array = roster.filter(func(m): return int(m["morale"]) < 12 and randf() < 0.12 * Officer.desert_mult())
	for g in gone:
		roster.erase(g)
	if gone.size() > 0:
		notes.append("%d deserted in the night." % gone.size())
	var cm := company_morale()
	if roster.size() > 0 and cm < MUTINY_MORALE and randf() < (MUTINY_MORALE - cm) * 0.015 * Officer.desert_mult():
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
	var gone: Array = roster.filter(func(m): return int(m["morale"]) < 12 and randf() < 0.3 * Officer.desert_mult())
	for g in gone:
		roster.erase(g)
	if gone.size() > 0:
		notes.append("%d deserted in the night." % gone.size())
	var cm := company_morale()
	if roster.size() > 0 and cm < MUTINY_MORALE and randf() < (MUTINY_MORALE - cm) * 0.05 * Officer.desert_mult():
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
	return FileAccess.file_exists(save_path())


func save() -> void:
	var data := {
		"version": SAVE_VERSION, "day": day, "money": money, "battles": battles,
		"victories": victories, "last_pay_day": last_pay_day, "next_id": next_id,
		"roster": roster, "fallen": fallen, "officer": officer,
		"last_result": last_result, "march_note": march_note,
		"results_unseen": results_unseen, "stores": stores, "prologue": prologue, "stash": stash, "next_battle": next_battle, "guns": guns, "standing": standing, "contract": contract,
		"tags": tags, "wagon_plan": wagon_plan, "loot": loot, "tongues": tongues, "towns": towns, "visiting": visiting,
	}
	DirAccess.make_dir_recursive_absolute(Settings.slot_dir())
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))


func load_campaign() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(save_path(), FileAccess.READ)
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
	Officer.migrate(officer)
	prologue = bool(data.get("prologue", false))
	stash = data.get("stash", {})
	guns = int(data.get("guns", 0))
	standing = data.get("standing", {"aurest": 0, "vell": 0})
	contract = data.get("contract", {})
	next_battle = data.get("next_battle", {})
	tags = data.get("tags", DEFAULT_TAGS.duplicate())
	wagon_plan = data.get("wagon_plan", [0.0, -12.0])
	loot = data.get("loot", [])
	tongues = data.get("tongues", {})
	towns = data.get("towns", {})
	visiting = int(data.get("visiting", -1))
	for l in loot:
		l["n"] = int(l["n"])
	ensure_wagon_crew()
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
	for k in ["water", "rations", "ammo", "arrows", "bolts", "powder", "lead"]:
		stores[k] = int(stores.get(k, 0))
	active = true
	return true


# ---------------------------------------------------------------- contracts
# A lord hires the company for a few weeks: pay every week, and one duty
# (hunt down lizard warbands in his lands, or beat the other nation's men in
# the field). Done, it earns a bonus and his favour; left undone at the end,
# he thinks less of you. Turn on his nation's men and the contract is torn up.

const CONTRACT_DAYS := 21
const DUTIES := {
	"warbands": ["Hunt down the lizard warbands that raid his lands", 2, "lizard bands destroyed"],
	"enemy": ["Beat the enemy's men in the field (a patrol or an army)", 1, "enemy forces beaten"],
}


## What a lord would offer you (the terms; nothing is signed yet).
func contract_terms(lord_id: int, faction: String, lord_name: String) -> Dictionary:
	var pay := 20 + 3 * fit_men().size() + 10 * guns
	var duty: String = ["warbands", "enemy"].pick_random()
	return {"lord": lord_id, "faction": faction, "lord_name": lord_name, "from": day, "until": day + CONTRACT_DAYS,
		"pay": pay, "duty": duty, "need": int(DUTIES[duty][1]), "done": 0, "paid_day": day}


func sign_contract(c: Dictionary) -> void:
	contract = c.duplicate()
	change_standing(String(AT_WAR.get(String(c["faction"]), "")), -10) # (the other side hears of it)


## A battle won: does it count toward the duty? `kind`: the party's kind,
## `faction` its faction. Returns a line for the map, or "".
func contract_progress(kind: String, faction: String) -> String:
	if contract.is_empty():
		return ""
	var counts := false
	match String(contract["duty"]):
		"warbands":
			counts = faction == "lizards" and kind in ["warband", "hunters", "nest"]
		"enemy":
			counts = faction == String(AT_WAR.get(String(contract["faction"]), "")) and kind in ["patrol", "army"]
	if not counts or int(contract["done"]) >= int(contract["need"]):
		return ""
	contract["done"] = int(contract["done"]) + 1
	if int(contract["done"]) >= int(contract["need"]):
		var bonus := 60 + 2 * int(contract["pay"])
		money += bonus
		change_standing(String(contract["faction"]), 10)
		return "Duty done for %s: a bonus of %d crowns." % [contract["lord_name"], bonus]
	return "%s: %d of %d %s." % [contract["lord_name"], int(contract["done"]), int(contract["need"]), DUTIES[contract["duty"]][2]]


## You turned on your employer's men: the contract is torn up.
func break_contract() -> String:
	if contract.is_empty():
		return ""
	var n := String(contract["lord_name"])
	contract = {}
	return "Your contract with %s is torn up." % n


## Each midnight: the week's pay, and the end of the contract.
func _contract_day() -> PackedStringArray:
	var notes: PackedStringArray = []
	if contract.is_empty():
		return notes
	if day - int(contract["paid_day"]) >= 7:
		contract["paid_day"] = int(contract["paid_day"]) + 7
		money += int(contract["pay"])
		notes.append("%s pays your hire: %d crowns." % [contract["lord_name"], int(contract["pay"])])
	if day >= int(contract["until"]):
		var done := int(contract["done"]) >= int(contract["need"])
		notes.append("Your contract with %s has run its course%s." % [contract["lord_name"], "" if done else ", the duty undone: he is not pleased"])
		contract["ended"] = "done" if done else "undone"
		last_contract = contract
		contract = {}
	return notes


## The contract that just ended (the map settles the lord's opinion).
var last_contract := {}
