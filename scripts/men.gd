extends RefCounted
## Rules for a soldier's record (the Dictionaries in Company.roster): his
## four attributes and their points, levels, morale, health, hunger, thirst
## and sickness, and what all of that does to him in battle.
##
## Attributes (1-15, a man starts around 5):
##   aim          how well he shoots (the spread of his shots)
##   strength     how hard he hits with the bayonet, and how well he parries
##   constitution his hit points, how fast wounds and sickness heal, and how
##                long he holds out against hunger, thirst and foul water
##   fitness      his pace (in battle and on the march) and how quickly he
##                strikes again in melee
## Every LEVEL_XP of experience is a level, worth POINTS_PER_LEVEL points to
## spend on the Company screen.
##
## Morale (0-100) is a state, not a stat: food, water, pay, grog, victories,
## defeats and fair shares move it. It makes him steadier or shakier, and at
## the bottom men desert or mutiny.
##
## Going without: a day without water costs morale at once; from the second
## day it saps his attributes and then his health, faster each day. Hunger
## does the same, more slowly. Health at 0 and he dies.

const ATTRS := ["aim", "strength", "constitution", "fitness"]
const ATTR_NAMES := {"aim": "Aim", "strength": "Strength", "constitution": "Constitution", "fitness": "Fitness"}
const ATTR_HELP := {
	"aim": "Accuracy with the musket",
	"strength": "Bayonet damage and parrying",
	"constitution": "Hit points, healing, resisting hunger and sickness",
	"fitness": "Pace on the march and in battle, quicker in melee",
}
const ATTR_BASE := 5
const ATTR_MAX := 15
const LEVEL_XP := 100
const POINTS_PER_LEVEL := 1

const MORALE_START := 60
const MORALE_WORDS := [[80, "Eager"], [60, "Content"], [40, "Grumbling"], [20, "Sullen"], [0, "Mutinous"]]


static func new_attrs() -> Dictionary:
	var a := {}
	for k in ATTRS:
		a[k] = randi_range(3, 7)
	return a


static func level(m: Dictionary) -> int:
	return 1 + int(m["xp"]) / LEVEL_XP


## Spend `n` points at random (for men who come with experience).
static func auto_spend(m: Dictionary, n: int) -> void:
	var a: Dictionary = m["attrs"]
	for i in n:
		var k: String = ATTRS.pick_random()
		if int(a[k]) < ATTR_MAX:
			a[k] = int(a[k]) + 1


static func spend(m: Dictionary, attr: String) -> bool:
	var a: Dictionary = m["attrs"]
	if int(m["points"]) <= 0 or int(a[attr]) >= ATTR_MAX:
		return false
	a[attr] = int(a[attr]) + 1
	m["points"] = int(m["points"]) - 1
	return true


## Points lost to thirst, hunger and sickness (applies to every attribute).
static func penalty(m: Dictionary) -> int:
	var p := maxi(0, int(m["thirst"]) - 1) * 2 + maxi(0, int(m["hunger"]) - 2)
	if int(m["sick"]) > 0:
		p += 2
	return p


static func attr(m: Dictionary, k: String) -> int:
	return maxi(1, int(m["attrs"][k]) - penalty(m))


static func max_hp(m: Dictionary) -> float:
	return 100.0 + 8.0 * (attr(m, "constitution") - ATTR_BASE)


static func morale_word(v: int) -> String:
	for w in MORALE_WORDS:
		if v >= int(w[0]):
			return Lang.t(w[1])
	return Lang.t("Mutinous")


static func add_morale(m: Dictionary, d: int) -> void:
	m["morale"] = clampi(int(m["morale"]) + d, 0, 100)


## Everything that shapes him in battle, from his kit, attributes, morale and
## condition. Soldier.gd reads this; the Company screen shows it.
static func combat_stats(m: Dictionary) -> Dictionary:
	var st: Dictionary = Company.gear_stats(m)
	var aim := attr(m, "aim")
	var stren := attr(m, "strength")
	var fit := attr(m, "fitness")
	st["spread"] = float(st["spread"]) * clampf(1.3 - 0.06 * aim, 0.35, 1.6)
	st["melee"] = float(st["melee"]) + 3.0 * (stren - ATTR_BASE)
	st["parry"] = 0.04 * (stren - ATTR_BASE)
	st["melee_rate"] = clampf(1.0 + 0.04 * (fit - ATTR_BASE), 0.7, 1.4)
	st["pace"] = float(st["pace"]) + 0.03 * (fit - ATTR_BASE)
	st["steady"] = float(st["steady"]) + (int(m["morale"]) - 50) / 250.0
	st["max_hp"] = max_hp(m)
	st["hp"] = max_hp(m) * clampf(float(m["health"]) / 100.0, 0.2, 1.0)
	# A native still learning the musket (Company.drill_of): slow, wild, jumpy.
	var raw := 1.0 - Company.drill_of(m)
	if raw > 0.0:
		st["reload"] = float(st["reload"]) * (1.0 + 0.9 * raw)
		st["spread"] = float(st["spread"]) * (1.0 + 0.7 * raw)
		st["misfire"] = float(st["misfire"]) + 0.08 * raw
		st["steady"] = float(st["steady"]) - 0.25 * raw
	return st


## A short list of what's wrong with him.
static func conditions(m: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if int(m["wounded_days"]) > 0:
		out.append(Lang.t("wounded %dd") % int(m["wounded_days"]))
	if int(m["sick"]) > 0:
		out.append(Lang.t("sick %dd") % int(m["sick"]))
	if int(m["thirst"]) > 0:
		out.append(Lang.t("thirsty %dd") % int(m["thirst"]))
	if int(m["hunger"]) > 0:
		out.append(Lang.t("hungry %dd") % int(m["hunger"]))
	if int(m["health"]) < 100:
		out.append(Lang.t("health %d") % int(m["health"]))
	return out


## Older saves: give a man everything this file expects.
static func migrate(m: Dictionary) -> void:
	if not m.has("attrs"):
		m["attrs"] = new_attrs()
		auto_spend(m, (level(m) - 1) * POINTS_PER_LEVEL)
	for k in ATTRS:
		m["attrs"][k] = int(m["attrs"][k])
	m["points"] = int(m.get("points", 0))
	m["morale"] = int(m.get("morale", MORALE_START))
	m["health"] = int(m.get("health", 100))
	m["thirst"] = int(m.get("thirst", 0))
	m["hunger"] = int(m.get("hunger", m.get("hungry", 0)))
	m["sick"] = int(m.get("sick", 0))
	m.erase("hungry")
	if String(m.get("native", "")) != "" and not m.has("drill"):
		m["drill"] = 1.0 # (a save from before the musket drill: he's learned it)
	if not m.has("tag"):
		m["tag"] = "Pikes" if String(m.get("gear", {}).get("primary", "")) in ["pike", "spear"] else "Musketeers"
