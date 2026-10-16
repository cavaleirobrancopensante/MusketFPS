extends RefCounted
## You: the officer's character sheet. The data lives in Company.officer (and
## is saved with the campaign); this script holds the rules.
##
## Six attributes (1-10) and nine skills (0-10). A skill can't be raised above
## the attribute that governs it. Every level gives 1 attribute point and 2
## skill points (3 with Wits 7 or more). Experience comes from battles, kills
## and victories.
##
## Everything here feeds a real mechanic; the effect functions at the bottom
## are what the rest of the game calls (player.gd, soldier.gd, company.gd,
## map.gd, world.gd, logistics_popup.gd).

const ATTRS := ["aim", "strength", "constitution", "fitness", "wits", "presence"]
const ATTR_NAMES := {"aim": "Aim", "strength": "Strength", "constitution": "Constitution",
	"fitness": "Fitness", "wits": "Wits", "presence": "Presence"}
const ATTR_HELP := {
	"aim": "Your eye: a steadier shot (spread -3% a point over 5). Governs Marksmanship.",
	"strength": "Harder blows with the bayonet (+4% a point over 5). Governs Bladework.",
	"constitution": "Toughness: +8 hit points a point over 5.",
	"fitness": "Quicker on your feet (+3% speed a point over 5). Governs Pathfinding.",
	"wits": "A quick mind: at 7 or more, an extra skill point every level. Governs Tactics, Surgery and Logistics.",
	"presence": "Men listen to you. Governs Leadership, Trade and Training.",
}
const ATTR_MAX := 10
const SKILL_MAX := 10
const LEVEL_XP := 120
const XP_BATTLE := 25
const XP_KILL := 6
const XP_VICTORY := 35

## Skill: name, governing attribute, what it does.
const SKILLS := {
	"marksmanship": {"name": "Marksmanship", "attr": "aim",
		"help": "Your own shooting: -5% spread and -3% reload time a level."},
	"bladework": {"name": "Bladework", "attr": "strength",
		"help": "Bayonet and blade: +5% damage a level, and a parry that covers 3° more either side."},
	"leadership": {"name": "Leadership", "attr": "presence",
		"help": "Your men stand steadier in battle (+2 steadiness a level), and fewer desert or mutiny (-7% a level)."},
	"tactics": {"name": "Tactics", "attr": "wits",
		"help": "Orders ripple down the line faster (-4% reaction a level); the night watch is likelier to see an attack (+3%); slipping away is likelier (+3%)."},
	"surgery": {"name": "Surgery", "attr": "wits",
		"help": "The wounded heal faster (-7% a level), and after a victory a man thought dead may pull through (4% a level)."},
	"logistics": {"name": "Logistics", "attr": "wits",
		"help": "Better packing: the wagon carries 5% more weight and space a level."},
	"pathfinding": {"name": "Pathfinding", "attr": "fitness",
		"help": "On the map: +3% march speed and +4% sight a level; scouts are 7% less likely to be lost."},
	"trade": {"name": "Trade", "attr": "presence",
		"help": "Settlements sell to you 4% cheaper and pay 5% more for loot, a level."},
	"training": {"name": "Training", "attr": "presence",
		"help": "Your men gain 8% more experience a level."},
	"tongues": {"name": "Tongues", "attr": "wits",
		"help": "Picking up the land's languages: +15% faster learning and +3% chance to be understood a level."},
}
const SKILL_ORDER := ["marksmanship", "bladework", "leadership", "tactics", "surgery", "logistics",
	"pathfinding", "trade", "training", "tongues"]

const OFFICER_GEAR := {"head": "bicorne", "torso": "officer_coat", "primary": "musket", "secondary": "bayonet"}


static func blank() -> Dictionary:
	return {
		"name": "Thomas Ashcombe", "rank": "Ensign", "kills": 0, "battles": 0, "xp": 0,
		"attr_points": 1, "skill_points": 4,
		"attrs": {"aim": 6, "strength": 5, "constitution": 5, "fitness": 6, "wits": 6, "presence": 5},
		"skills": {"marksmanship": 2, "bladework": 1, "leadership": 1, "tactics": 0, "surgery": 0,
			"logistics": 0, "pathfinding": 0, "trade": 0, "training": 0, "tongues": 1},
		"gear": OFFICER_GEAR.duplicate(),
		"pack": {"ammo": 30},
	}


## Old saves had only kills, battles and rank: fill in the rest.
static func migrate(o: Dictionary) -> Dictionary:
	var b := blank()
	for k in b:
		if not o.has(k):
			o[k] = b[k]
	for k in b["attrs"]:
		if not o["attrs"].has(k):
			o["attrs"][k] = b["attrs"][k]
	for k in b["skills"]:
		if not o["skills"].has(k):
			o["skills"][k] = 0
	for k in b["gear"]:
		if not o["gear"].has(k):
			o["gear"][k] = b["gear"][k]
	if not o["pack"].has("ammo"):
		o["pack"]["ammo"] = 30
	return o


static func o() -> Dictionary:
	return Company.officer


static func level(of: Dictionary = {}) -> int:
	var d := of if not of.is_empty() else o()
	return 1 + int(d.get("xp", 0)) / LEVEL_XP


static func attr(k: String) -> int:
	return int(o().get("attrs", {}).get(k, 5))


static func skill(k: String) -> int:
	if not Company.active:
		return 0
	return int(o().get("skills", {}).get(k, 0))


static func cap(k: String) -> int:
	return mini(SKILL_MAX, attr(String(SKILLS[k]["attr"])))


static func can_raise_attr(k: String) -> bool:
	return int(o()["attr_points"]) > 0 and attr(k) < ATTR_MAX


static func can_raise_skill(k: String) -> bool:
	return int(o()["skill_points"]) > 0 and skill(k) < cap(k)


static func raise_attr(k: String) -> bool:
	if not can_raise_attr(k):
		return false
	o()["attrs"][k] = attr(k) + 1
	o()["attr_points"] = int(o()["attr_points"]) - 1
	return true


static func raise_skill(k: String) -> bool:
	if not can_raise_skill(k):
		return false
	o()["skills"][k] = skill(k) + 1
	o()["skill_points"] = int(o()["skill_points"]) - 1
	return true


## Add experience; returns how many levels were gained (points are added).
static func gain_xp(n: int) -> int:
	var before := level()
	o()["xp"] = int(o().get("xp", 0)) + n
	var up := level() - before
	if up > 0:
		o()["attr_points"] = int(o()["attr_points"]) + up
		o()["skill_points"] = int(o()["skill_points"]) + up * (3 if attr("wits") >= 7 else 2)
	return up


# ---------------------------------------------------------------- your own body (player.gd)

static func gear_stats() -> Dictionary:
	return Company.gear_stats({"gear": o().get("gear", OFFICER_GEAR)})


static func max_hp() -> float:
	return 100.0 + 8.0 * (attr("constitution") - 5)


static func spread_mult() -> float:
	var g := gear_stats()
	return maxf(0.2, (1.0 - 0.03 * (attr("aim") - 5)) * (1.0 - 0.05 * skill("marksmanship")) * float(g["spread"]))


static func reload_mult() -> float:
	return maxf(0.4, (1.0 - 0.03 * skill("marksmanship")) * float(gear_stats()["reload"]))


static func melee_mult() -> float:
	var g := gear_stats()
	# Your swings are balanced for a socket bayonet (34): a sword bayonet hits harder, a bare musket butt less.
	var weapon := float(g["melee"]) / 34.0
	return (1.0 + 0.04 * (attr("strength") - 5)) * (1.0 + 0.05 * skill("bladework")) * weapon


static func block_arc() -> float:
	return 70.0 + 3.0 * skill("bladework")


static func speed_mult() -> float:
	return maxf(0.6, 1.0 + 0.03 * (attr("fitness") - 5) + float(gear_stats()["pace"]))


static func armour() -> float:
	return float(gear_stats()["armour"])


static func misfire() -> float:
	return float(gear_stats()["misfire"])


# ---------------------------------------------------------------- the company and the march

static func men_steady() -> float:
	return 0.02 * skill("leadership")


static func desert_mult() -> float:
	return maxf(0.2, 1.0 - 0.07 * skill("leadership"))


static func reaction_mult() -> float:
	return maxf(0.5, 1.0 - 0.04 * skill("tactics"))


static func watch_bonus() -> float:
	return 0.03 * skill("tactics")


static func slip_bonus() -> float:
	return 0.03 * skill("tactics")


static func wound_mult() -> float:
	return maxf(0.3, 1.0 - 0.07 * skill("surgery"))


static func save_chance() -> float:
	return 0.04 * skill("surgery")


static func wagon_mult() -> float:
	return 1.0 + 0.05 * skill("logistics")


static func march_mult() -> float:
	return 1.0 + 0.03 * skill("pathfinding")


static func sight_mult() -> float:
	return 1.0 + 0.04 * skill("pathfinding")


static func scout_risk_mult() -> float:
	return maxf(0.3, 1.0 - 0.07 * skill("pathfinding"))


static func buy_mult() -> float:
	return maxf(0.5, 1.0 - 0.04 * skill("trade"))


static func sell_mult() -> float:
	return 1.0 + 0.05 * skill("trade")


static func xp_mult() -> float:
	return 1.0 + 0.08 * skill("training")


## What the skill does for you right now, in a few words.
static func skill_now(k: String) -> String:
	var s := skill(k)
	match k:
		"marksmanship": return "spread -%d%%, reload -%d%%" % [5 * s, 3 * s]
		"bladework": return "+%d%% damage, parry ±%d°" % [5 * s, int(block_arc())]
		"leadership": return "+%d steadiness, desertion -%d%%" % [2 * s, 7 * s]
		"tactics": return "reaction -%d%%, watch +%d%%, slip +%d%%" % [4 * s, 3 * s, 3 * s]
		"surgery": return "healing -%d%% days, %d%% saved" % [7 * s, 4 * s]
		"logistics": return "wagon %d kg, %.0f space" % [int(Company.wagon_kg()), Company.wagon_space()]
		"pathfinding": return "march +%d%%, sight +%d%%, scouts lost -%d%%" % [3 * s, 4 * s, 7 * s]
		"trade": return "buy -%d%%, sell +%d%%" % [4 * s, 5 * s]
		"training": return "men's xp +%d%%" % [8 * s]
		"tongues": return "learning +%d%%, understood +%d%%" % [15 * s, 3 * s]
	return ""
