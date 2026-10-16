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

const SAVE_PATH := "user://campaign.json"
const SAVE_VERSION := 1

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
var officer := {"kills": 0, "battles": 0}
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
	officer = {"kills": 0, "battles": 0}
	last_result = {}
	results_unseen = false
	# A small company: a few men who've seen a fight, the rest green.
	for i in 8:
		var m := make_recruit()
		if i < 3:
			m["xp"] = RANK_XP[1] + randi_range(0, 60)
			m["rank"] = 1
			m["battles"] = randi_range(1, 3)
		roster.append(m)
	march_note = "Day 1. The company sets out. Scouts report lizardmen ahead."
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
	}
	next_id += 1
	return m


# ---------------------------------------------------------------- queries

static func title(m: Dictionary) -> String:
	return "%s %s" % [RANK_SHORT[int(m["rank"])], m["name"]]


static func surname_title(m: Dictionary) -> String:
	var parts: PackedStringArray = String(m["name"]).split(" ")
	return "%s %s" % [RANK_SHORT[int(m["rank"])], parts[parts.size() - 1]]


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
	var summary := {"won": won, "slain": int(result["slain"]), "fallen": [], "wounded": [],
		"promoted": [], "pay": 0, "day": day}
	battles += 1
	officer["battles"] = int(officer["battles"]) + 1
	officer["kills"] = int(officer["kills"]) + int(result["officer_kills"])
	if won:
		victories += 1

	var survivors: Array = []
	for m in roster:
		var r = men.get(int(m["id"]))
		if r == null:
			survivors.append(m) # didn't fight (wounded in camp)
			continue
		m["battles"] = int(m["battles"]) + 1
		m["kills"] = int(m["kills"]) + int(r["kills"])
		if r["status"] == "killed":
			fallen.append({"name": m["name"], "rank": RANKS[int(m["rank"])], "day": day,
				"battles": m["battles"], "kills": m["kills"]})
			summary["fallen"].append(title(m))
			continue
		var gained := XP_SURVIVE + XP_KILL * int(r["kills"]) + (XP_VICTORY if won else 0)
		m["xp"] = int(m["xp"]) + gained
		if r["status"] == "wounded":
			m["wounded_days"] = randi_range(3, 10)
			summary["wounded"].append("%s (%d days)" % [title(m), m["wounded_days"]])
		var new_rank := _rank_for(int(m["xp"]))
		if new_rank > int(m["rank"]):
			m["rank"] = new_rank
			summary["promoted"].append("%s, now %s" % [m["name"], RANKS[new_rank]])
		survivors.append(m)
	roster = survivors

	# Pay: a bounty on every lizardman slain; a beaten company loses its baggage.
	if won:
		summary["pay"] = 15 + 5 * int(result["slain"])
	else:
		summary["pay"] = -int(money * 0.25)
	money = maxi(0, money + int(summary["pay"]))
	last_result = summary
	results_unseen = true
	save()


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


## March to the next fight: days pass, wounds heal, wages fall due. Men who
## go unpaid may desert. Returns the notes for the road.
func march_on() -> String:
	var days := randi_range(2, 4)
	day += days
	var notes: PackedStringArray = ["%d days' march. Day %d." % [days, day]]
	var healed := 0
	for m in roster:
		if int(m["wounded_days"]) > 0:
			m["wounded_days"] = maxi(0, int(m["wounded_days"]) - days)
			if int(m["wounded_days"]) == 0:
				healed += 1
	if healed > 0:
		notes.append("%d wounded back in the ranks." % healed)
	while day - last_pay_day >= 7:
		last_pay_day += 7
		var wages := weekly_wages()
		if money >= wages:
			money -= wages
			notes.append("Wages paid: %d crowns." % wages)
		else:
			money = 0
			var deserters: Array = roster.filter(func(_m): return randf() < 0.25)
			for d in deserters:
				roster.erase(d)
			notes.append("No pay! %d men deserted." % deserters.size() if deserters.size() > 0
				else "No pay! The men grumble.")
	notes.append("Scouts report about %d lizardmen ahead." % next_enemy_count())
	march_note = " ".join(notes)
	save()
	return march_note


# ---------------------------------------------------------------- saving

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> void:
	var data := {
		"version": SAVE_VERSION, "day": day, "money": money, "battles": battles,
		"victories": victories, "last_pay_day": last_pay_day, "next_id": next_id,
		"roster": roster, "fallen": fallen, "officer": officer,
		"last_result": last_result, "march_note": march_note,
		"results_unseen": results_unseen,
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
	last_result = data.get("last_result", {})
	march_note = String(data.get("march_note", ""))
	results_unseen = bool(data.get("results_unseen", false))
	# JSON numbers come back as floats; ids are used as keys, keep them ints.
	for m in roster:
		m["id"] = int(m["id"])
	active = true
	return true
