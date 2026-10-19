extends Control
## Main menu: continue the last campaign, start a new one or load another
## from the save slots (each slot is its own campaign in its own land), or
## run the stress test (50 musketeers against 200 lizardmen with an FPS
## counter). Built in code like the rest of the game.
const UI := preload("res://scripts/ui.gd")

const BATTLE := "res://scenes/battle.tscn"
const CAMP := "res://scenes/aftermath.tscn"
const COMPANY := "res://scenes/company.tscn"
const INTRO := "res://scenes/intro.tscn"
const MusicBar := preload("res://scripts/music_bar.gd")
const MAP := "res://scenes/map.tscn"
const Vignette := preload("res://scripts/vignette.gd")
const CREATION := "res://scenes/creation.tscn"
const FlagButton := preload("res://scripts/flag_button.gd")
const Lore := preload("res://scripts/lore.gd")

var _tp_check: CheckButton
var _slots_panel: PanelContainer
var _slots_box: VBoxContainer
var _slots_title: Label
var _mode := "new" # the slot panel is for "new" or "load"
var _armed := "" # a destructive button waiting for its second tap


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Headless test runs skip the menu:
	#   -- --autotest [--stress] [--tp]   a stand-alone battle
	#   -- --autotest --campaign          a new campaign, battle after battle
	#   -- --autotest --camp [--spotted]  attacked in the night camp
	#   -- --autotest --assault [--walls=W]  storming a nest
	#   -- --autotest --patrol [--vell|--dwarves] [--army] [--allied]  against a nation's patrol or a lord's army (or beside it)
	#   -- --contracttest, -- --siegetest  headless checks of contracts and town sieges
	var args := OS.get_cmdline_user_args()
	for a in ["--intro", "--intro-render", "--retreat-render", "--maptest", "--company", "--autotest", "--shots", "--plantest", "--loottest", "--officer", "--towntest"]:
		if a in args:
			Settings.slot = 99 # tests never touch the player's saves
	if "--retreat-render" in args:
		Company.new_campaign(_test_start())
		get_tree().change_scene_to_file.call_deferred("res://scenes/retreat.tscn")
		return
	if "--intro" in args or "--intro-render" in args:
		if "--intro" in args:
			Engine.time_scale = 4.0
		Company.new_campaign(_test_start())
		get_tree().change_scene_to_file.call_deferred(INTRO)
		return
	for a in args:
		if a.begins_with("--field"):
			# `-- --field[=map]` (a field battle, you on foot) or
			# `-- --fieldtest[=map]` (both generals are the computer).
			var map := "flat"
			if "=" in a:
				map = a.split("=")[1]
			var foe_army := "humans" if "--humans" in args else "lizards"
			var fsize := 16
			for b in args:
				if b.begins_with("--fieldsize="):
					fsize = int(b.substr(12))
			Settings.field = {"map": map, "size": fsize, "foe_army": foe_army,
				"you": {"musket": 2, "pike": 1, "bow": 1, "xbow": 0, "dragoon": 1, "lancer": 1, "gun": 1},
				"foe": {"liz_warrior": 3, "liz_skirm": 1, "liz_brute": 1, "liz_raptor": 1} if foe_army == "lizards" else {"sword": 2, "pike": 1, "longbow": 1, "xbow": 1, "knight": 1, "catapult": 1}}
			Settings.stress = false
			Settings.mixed = false
			Settings.playground = false
			Settings.siege_test = false
			Company.active = false
			Settings.slot = 99
			# Through the loading screen, as from the setup screen.
			Loading.change.call_deferred(BATTLE)
			return
	if "--siegetest" in args:
		# Headless check of a town siege: it falls, and a broken one lifts.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.new_world(1234)
		var towns: Array = World.gen.settlements.filter(func(st): return st["kind"] == "town" and st.get("faction", "") == "vell")
		for k in 2:
			var tw: Dictionary = towns[k]
			var army: Dictionary = {}
			for p in World.parties:
				if p["kind"] == "army" and p["faction"] == "aurest":
					army = p
					break
			army["x"] = float(tw["x"]) + 0.5
			army["y"] = float(tw["y"]) + 0.5
			World._begin_siege(army, tw)
			print("SIEGE of ", tw["name"], " by ", World.party_name(army), ": ", World.siege_of(int(tw["id"])).get("need"), " days")
			if k == 1:
				World.remove_party(int(army["id"])) # (beaten by a relief army)
			for d in 8:
				World._sieges_tick()
			print("SIEGE ", tw["name"], " now ", tw["faction"], " besieged ", not World.siege_of(int(tw["id"])).is_empty(), " owner ", World.places[int(tw["id"])].get("owner", "-"))
		print("SIEGE news: ", World.log.slice(-6))
		# A truce, and an army marching with you.
		World.war["next_truce"] = World.hours
		World._war_tick()
		var pa: Dictionary = {}
		var pv: Dictionary = {}
		for p in World.parties:
			if p["kind"] == "army" and p["faction"] == "aurest" and pa.is_empty():
				pa = p
			if p["kind"] == "army" and p["faction"] == "vell" and pv.is_empty():
				pv = p
		print("SIEGE truce ", World.truce(), " aurest vs vell hostile: ", World._hostile(pa, pv))
		World.war["truce_until"] = World.hours - 1.0
		World._war_tick()
		print("SIEGE truce after ", World.truce(), " hostile: ", World._hostile(pa, pv))
		World.escort(pa, 4.0)
		World.pos = Vector2(pa["x"], pa["y"]) + Vector2(12, 4)
		while World.grid.is_point_solid(Vector2i(World.pos)):
			World.pos += Vector2(1, 0)
		for k in 30:
			World._party_tick(pa, 0.5)
		print("SIEGE escort: ", World.escorting().get("id", -1) == pa["id"], " now ", snappedf(Vector2(pa["x"], pa["y"]).distance_to(World.pos), 0.1), " cells from you")
		World.hours += 24.0 * 5.0
		World._party_tick(pa, 0.5)
		print("SIEGE escort after 5 days: ", World.escorting().is_empty())
		# And the war left to itself for 40 days (nobody watching).
		World.new_world(4321)
		Company.active = false
		for k in 40 * 24:
			World.advance(1.0)
		for st in World.gen.settlements:
			var sg := World.siege_of(int(st["id"]))
			if not sg.is_empty():
				print("SIEGE (day 40) ", st["name"], " ", sg["days"], "/", sg["need"])
			if World.places[int(st["id"])].has("owner"):
				print("SIEGE (day 40) TAKEN ", st["name"], " now ", st["faction"])
		for l in World.lords:
			print("SIEGE (day 40) LORD ", World.lord_full(l), " army ", int(l["army"]), " home ", World.settlement(int(l["home"]))["name"])
		get_tree().quit()
		return
	if "--bgtest" in args:
		# Headless check of backgrounds: what each brings to a new campaign.
		for pair in [["docks", "ranks"], ["squire", "commission"], ["hill_farm", "engineer"], ["vicarage", "navy"]]:
			Company.new_campaign({"branch": "line", "childhood": pair[0], "youth": pair[1]})
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			var vets: int = Company.roster.filter(func(m): return bool(m.get("comrade", false))).size()
			print("BG ", pair, ": money ", Company.money, " men ", Company.roster.size(), " comrades ", vets, " rum ", Company.stores["rum"],
				" rations ", Company.stores["rations"], " powder ", Company.stores["powder"], " cutlass ", Company.item_count("cutlass"),
				" morale0 ", Company.roster[5]["morale"], " | ", Company.Officer.background_gives(Company.Officer.YOUTHS[pair[1]]))
		get_tree().quit()
		return
	if "--watertest" in args:
		# Headless check of water: named sources, filling, catching rain.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.new_world(4321)
		var g = World.gen
		Company.stores["water"] = 10
		Company.stores["foul"] = false
		for want in ["city", "village", "hold"]:
			for st in g.settlements:
				if st["kind"] == want:
					World.pos = Vector2(st["x"], st["y"]) + Vector2(0.5, 0.5)
					print("WATER at a ", want, ": ", World.fill_state())
					break
		for i in g.river.size():
			if g.river[i] != 0 and g.terrain[i] != 6 and i % 7 == 0:
				World.pos = Vector2(i % 512, i / 512) + Vector2(1.5, 0.5)
				if World.settlement_at(World.pos) < 0:
					print("WATER by a river: ", World.fill_state(), " -> fill ", World.fill_barrels(), " ", Company.stores["water"], " then ", World.fill_state())
					break
		World.pos = Vector2(256, 256)
		for k in 400:
			if World.water_source()["kind"] == "":
				break
			World.pos += Vector2(1.7, 0.9)
		print("WATER dry ground: ", World.fill_state())
		for on in [true, false]:
			Company.stores["water"] = 10
			Company.stores["rain_catch"] = on
			World.weather.damp = 0.0
			World.weather.caught = 0.0
			World.weather.storms = [{"id": 1, "x": World.pos.x, "y": World.pos.y, "r": 12.0, "s": 0.9, "vx": 0.0, "vy": 0.0, "kind": "storm", "age": 3.0}]
			for h in 12:
				World.weather.tick(0.25)
				World.weather.storms[0]["s"] = 0.9
			print("WATER rain 3h, catching ", on, ": water ", Company.stores["water"], " caught ", World.weather.caught, " damp ", snappedf(World.weather.damp, 0.01))
		get_tree().quit()
		return
	if "--productiontest" in args:
		# Headless check of production: smiths at the camp forge, musket drill.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		Company.money = 1000
		for k in ["ore", "charcoal", "wood", "saltpetre", "sulphur"]:
			Company.stores[k] = 40
		print("PROD no smith: ", Company.smith_missing("smith_bayonet"), " | count ", Company.craft_count("smith_bayonet"))
		var hs := Company.hire_labourer("smith", "Jean Forgeron", "aurest")
		print("PROD hired ", hs.get("name"), " money ", Company.money, " wages ", Company.weekly_wages())
		print("PROD human smith: bayonet ", Company.craft_count("smith_bayonet"), " ", Company.craft_hours("smith_bayonet"), "h; musket: ", Company.smith_missing("smith_musket"))
		var bay0 := Company.item_count("bayonet")
		print("PROD made bayonets ", Company.craft("smith_bayonet", 2), " now ", Company.item_count("bayonet") - bay0)
		Company.hire_labourer("smith", "Durin Stonehand", "dwarves")
		print("PROD dwarf smith: musket ", Company.craft_count("smith_musket"), " ", Company.craft_hours("smith_musket"), "h by ", Company.smith_for("smith_musket").get("name"), "; bayonet ", Company.craft_hours("smith_bayonet"), "h; wages ", Company.weekly_wages())
		var mk0 := Company.item_count("musket")
		print("PROD made muskets ", Company.craft("smith_musket", 1), " +", Company.item_count("musket") - mk0, " powder: ", Company.craft("smith_powder", 1), " -> ", Company.stores["powder"])
		# A native recruit given a musket.
		var m: Dictionary = Company.make_recruit()
		m["native"] = "vell"
		m["drill"] = 0.0
		m["gear"]["primary"] = "war_bow"
		Company.roster.append(m)
		var sb := Company.Men.combat_stats(m)
		print("PROD native with a bow: needs drill ", Company.needs_drill(m), " reload ", sb["reload"])
		m["gear"]["primary"] = "musket"
		var s0 := Company.Men.combat_stats(m)
		var vet: Dictionary = Company.roster[0]
		var sv := Company.Men.combat_stats(vet)
		print("PROD native with a musket: drill ", Company.drill_of(m), " reload ", s0["reload"], " spread ", s0["spread"], " misfire ", s0["misfire"], " | a veteran: reload ", sv["reload"], " spread ", sv["spread"], " misfire ", sv["misfire"])
		for d in 30:
			Company.stores["rations"] = 400
			Company.stores["water"] = Company.WATER_CART
			Company.money = 1000
			for n in Company.pass_day("clean"):
				if n.find("drill") >= 0:
					print("PROD day ", Company.day, ": ", n)
			if d in [6, 13]:
				print("PROD day ", Company.day, " drill ", Company.drill_of(m))
		var s1 := Company.Men.combat_stats(m)
		print("PROD drilled: reload ", s1["reload"], " spread ", s1["spread"], " in roster ", m in Company.roster, " wounded ", m["wounded_days"], " drill ", m.get("drill"))
		get_tree().quit()
		return
	if "--gunpowdertest" in args:
		# Headless check of teaching gunpowder: the bargain, the musketeers,
		# the markets, the goodwill draining away.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.new_world(4321)
		print("GP refusal (strangers): ", Company.teach_refusal("aurest", 0))
		Company.standing["aurest"] = 40
		print("GP refusal (friends, lord cold): ", Company.teach_refusal("aurest", 10))
		print("GP refusal (friends): '", Company.teach_refusal("aurest", 40), "' spare muskets ", Company.item_count("musket"))
		var m0 := Company.money
		print("GP paid ", Company.teach("aurest"), " money ", m0, " -> ", Company.money, " standing ", Company.standing, " muskets ", Company.item_count("musket"))
		print("GP again: ", Company.teach_refusal("aurest", 40))
		for d in 60:
			for n in Company.pass_day("clean"):
				if n.find("musket") >= 0 or n.find("guns") >= 0 or n.find("powder") >= 0:
					print("GP day ", Company.day, ": ", n)
			if d in [0, 9, 19, 30]:
				print("GP day ", Company.day, " gp ", Company.gunpowder("aurest"), " patrol ", World.party_comp({"kind": "patrol", "faction": "aurest", "size": 20}),
					" army ", World.comp_text(World.party_comp({"kind": "army", "faction": "aurest", "size": 60})), " vell ", World.party_comp({"kind": "patrol", "faction": "vell", "size": 20}))
		print("GP after 60 days: standing ", Company.standing, " enemy ", Company.is_enemy("aurest"))
		var offers: Array = Company.market_offers("town", "aurest").map(func(o): return o[3])
		print("GP aurest town sells ", offers)
		Company.standing["dwarves"] = 30
		Company.forge["taught"] = true
		print("GP dwarves: '", Company.teach_refusal("dwarves", 20), "' musket price ", Company.forge_musket_price())
		Company.teach("dwarves")
		print("GP dwarves taught: price ", Company.forge_musket_price(), " standing ", Company.standing, " traders ", World.party_comp({"kind": "traders", "faction": "dwarves", "size": 12}))
		Company.save()
		Company.load_campaign()
		print("GP reload taught ", Company.taught)
		get_tree().quit()
		return
	if "--dwarftest" in args:
		# Headless check of the dwarves: thanes, standing, the forge.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.new_world(4321)
		var holds: Array = World.gen.settlements.filter(func(s2): return s2["kind"] == "hold")
		print("DWARF holds ", holds.map(func(h): return h["name"]))
		for l in World.lords:
			if l["faction"] == "dwarves":
				print("DWARF thane ", World.lord_full(l), " home ", World.settlement(int(l["home"]))["name"], " thane_of ", World.thane_of(int(l["home"])).get("given", "?"))
		var sid := int(holds[0]["id"])
		Company.money = 2000
		Company.market_faction = "dwarves"
		print("DWARF standing ", Company.standing, " spread ", Company.Officer.spread_mult(), " misfire ", Company.Officer.misfire(), " melee ", Company.Officer.melee_mult())
		print("DWARF bore: '", Company.buy_forge_work("bore"), "' lock: '", Company.buy_forge_work("lock"), "' temper: '", Company.buy_forge_work("temper"), "'")
		print("DWARF after: spread ", Company.Officer.spread_mult(), " misfire ", Company.Officer.misfire(), " melee ", Company.Officer.melee_mult(), " standing ", Company.standing["dwarves"], " trade ", Company.forge["trade"])
		print("DWARF order as stranger: ", Company.order_muskets(sid, "X", 5))
		Company.standing["dwarves"] = 30
		print("DWARF lock now: '", Company.buy_forge_work("lock"), "' misfire ", Company.Officer.misfire())
		var spare := Company.item_count("musket")
		print("DWARF spare muskets ", spare)
		if spare == 0:
			print("DWARF order with no spare: ", Company.order_muskets(sid, "X", 5))
			Company.add_item("musket", 1)
		var m0 := Company.money
		print("DWARF order 5: '", Company.order_muskets(sid, "X", 5), "' money ", m0, " -> ", Company.money, " taught ", Company.forge["taught"], " muskets ", Company.item_count("musket"))
		print("DWARF again: ", Company.order_muskets(sid, "X", 2))
		print("DWARF collect early: ", Company.collect_muskets(sid))
		for d in 6:
			Company.pass_day("clean")
		print("DWARF collect day ", Company.day, ": ", Company.collect_muskets(sid), " muskets ", Company.item_count("musket"))
		var th := World.thane_of(sid)
		var terms := Company.contract_terms(int(th["id"]), "dwarves", World.lord_short(th))
		print("DWARF terms ", terms)
		Company.sign_contract(terms)
		print("DWARF progress ", Company.contract_progress("protect", "dwarves"), " | ", Company.contract_progress("warband", "lizards"))
		print("DWARF traders comp ", World.party_comp({"kind": "traders", "size": 8}))
		Company.save()
		Company.load_campaign()
		print("DWARF reload standing ", Company.standing, " forge ", Company.forge)
		get_tree().quit()
		return
	if "--contracttest" in args:
		# Headless check of a contract: signing, pay, progress, the end.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		var terms := Company.contract_terms(0, "aurest", Lang.t("Count Test"))
		terms["duty"] = "warbands"
		terms["need"] = 2
		Company.sign_contract(terms)
		var m0 := Company.money
		print("CONTRACT signed ", terms, " vell standing ", Company.standing["vell"])
		print("CONTRACT ", Company.contract_progress("warband", "lizards"))
		print("CONTRACT ", Company.contract_progress("patrol", "vell"), "(vell patrol: not this duty)")
		print("CONTRACT ", Company.contract_progress("hunters", "lizards"))
		for d in 22:
			for n in Company.pass_day("clean"):
				if n.find("hire") >= 0 or n.find("contract") >= 0:
					print("CONTRACT day ", Company.day, ": ", n)
		print("CONTRACT money ", m0, " -> ", Company.money, " contract now ", Company.contract, " last ", Company.last_contract.get("ended", ""))
		get_tree().quit()
		return
	if "--maptest" in args:
		# Headless check of the map: a new campaign straight after the beach.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.reset()
		get_tree().change_scene_to_file.call_deferred(MAP)
		return
	if "--loottest" in args:
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		# A wagon packed to the brim and two men down: their kit can't all fit.
		Company.stow("rations", 99999)
		var men := {}
		for m in Company.roster:
			men[int(m["id"])] = {"status": "ok", "kills": 0}
		for m in Company.roster.slice(0, 2):
			men[int(m["id"])] = {"status": "killed", "kills": 0}
		Company.apply_battle({"won": true, "slain": 30, "officer_kills": 2, "men": men, "enemy": "lizards"})
		get_tree().change_scene_to_file.call_deferred("res://scenes/loot.tscn")
		return
	if "--plantest" in args:
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred("res://scenes/battleplan.tscn")
		return
	if "--towntest" in args:
		seed(4242) # the same land every test run, to compare looks
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		World.reset()
		World.is_ready = false
		World.ensure()
		var want := "town"
		for a in args:
			if a.begins_with("--kind="):
				want = a.substr(7)
		for s in World.gen.settlements:
			if s["kind"] == want:
				Company.visiting = int(s["id"])
				break
		get_tree().change_scene_to_file.call_deferred("res://scenes/town.tscn")
		return
	if "--officer" in args:
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred("res://scenes/officer.tscn")
		return
	if "--company" in args:
		# Headless check of the Company screen after the prologue.
		Company.new_campaign(_test_start())
		Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
		get_tree().change_scene_to_file.call_deferred(COMPANY)
		return
	if "--autotest" in args or "--shots" in args:
		Settings.third_person = "--tp" in args
		Settings.stress = "--stress" in args
		Settings.mixed = "--mixed" in args
		Settings.playground = "--range" in args
		Settings.siege_test = "--siege" in args
		if Settings.siege_test:
			Settings.mixed = true
		if "--camp" in args:
			# A night camp attacked: -- --autotest --camp [--spotted]
			Company.new_campaign(_test_start())
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			for m in Company.roster:
				m["wounded_days"] = 0
			var fit := Company.fit_men()
			Company.next_battle = {"enemy": 18, "terrain": 3, "party": -1, "ambush": false, "camp": true,
				"spotted": "--spotted" in args, "night": true, "watch": [int(fit[0]["id"]), int(fit[1]["id"])]}
			if "--allied" in args:
				# ...with a lord's army camped beside you.
				Company.next_battle["allies"] = {"faction": "aurest", "comp": World.party_comp({"kind": "army", "size": 40}), "party": -1, "size": 40}
		elif "--patrol" in args:
			# A nation's patrol: -- --autotest --patrol [--vell]
			Company.new_campaign(_test_start())
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			for m in Company.roster:
				m["wounded_days"] = 0
			var fac := "vell" if "--vell" in args else ("dwarves" if "--dwarves" in args else "aurest")
			if "--taught" in args:
				Company.taught[fac] = Company.day - 30 # (-- --patrol --taught: they have muskets of their own)
			var pp := {"kind": "army" if "--army" in args else "patrol", "faction": fac, "size": 60 if "--army" in args else 20, "id": 0}
			if fac == "dwarves":
				pp = {"kind": "traders", "faction": fac, "size": 12, "id": 0} # (-- --patrol --dwarves [--allied])
			Company.next_battle = {"enemy": int(pp["size"]), "terrain": 2, "party": -1, "ambush": false, "enemy_kind": "humans",
				"faction": fac, "comp": World.party_comp(pp), "map": "flat", "party_name": Lang.t("Test patrol")}
			if "--allied" in args:
				# ...or beside one, against a warband: -- --autotest --patrol --allied
				var wb := {"kind": "warband", "faction": "lizards", "size": 34, "id": 1}
				Company.next_battle = {"enemy": 34, "terrain": 2, "party": -1, "ambush": false, "enemy_kind": "lizards",
					"faction": "lizards", "comp": World.party_comp(wb), "map": "flat", "party_name": Lang.t("Test warband"),
					"allies": {"faction": fac, "comp": World.party_comp(pp), "party": -1, "size": int(pp["size"])}}
		elif "--rearguard" in args:
			# The retreat's bayonet charge: -- --rearguard
			Company.new_campaign(_test_start())
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			for m in Company.roster:
				m["wounded_days"] = 0
			Company.next_battle = {"rearguard": true, "enemy": 18}
		elif "--assault" in args:
			# Storming a nest: -- --autotest --assault [--walls=0.5]
			Company.new_campaign(_test_start())
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			for m in Company.roster:
				m["wounded_days"] = 0
			Company.guns = 2
			var walls := 0.9
			for a in args:
				if a.begins_with("--walls="):
					walls = float(a.substr(8))
			Company.next_battle = {"enemy": 40, "terrain": 3, "party": -1, "ambush": false, "enemy_kind": "lizards",
				"assault": 0, "walls": walls, "stash": false, "nest_name": Lang.t("Test nest")}
		elif "--hunt=game" in args or "--hunt=fish" in args:
			# Hunting yourself: -- --autotest --hunt=game|fish
			Company.new_campaign(_test_start())
			Company.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
			Company.next_battle = {"hunt": "game" if "--hunt=game" in args else "fish", "res": -1}
			Company.add_item("fishing_rod", 2)
		elif "--campaign" in args:
			Company.new_campaign(_test_start())
		else:
			Company.active = false
		get_tree().change_scene_to_file.call_deferred(BATTLE)
		return

	# Behind the menu: the company's camp at night, live (vignette.gd), with
	# a band of night down the left where the menu sits.
	var bg := ColorRect.new()
	bg.color = UI.NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scene: Control = Vignette.make("menu", {"time": "night"})
	add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(UI.NIGHT, 0.96))
	grad.set_color(1, Color(UI.NIGHT, 0.0))
	grad.add_point(0.42, Color(UI.NIGHT, 0.88))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.66
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	Music.set_context("menu")

	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 72
	col.offset_top = 52
	col.offset_bottom = -36
	col.offset_right = 72 + 520
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var title := UI.heading(Lang.t("Musket FPS"), 92, UI.PIPECLAY)
	title.add_theme_constant_override("line_spacing", -18)
	col.add_child(title)
	var sub := Label.new()
	sub.text = Lang.t("The %s, cast away on the %s.") % [Lore.REGIMENT.trim_prefix("the "), Lore.LAND.trim_prefix("the ")]
	sub.add_theme_font_override("font", UI.font("fell_italic"))
	sub.add_theme_font_size_override("font_size", 25)
	sub.add_theme_color_override("font_color", UI.BRASS)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)

	var last := Settings.slot_summary(Settings.slot)
	if not last.is_empty():
		var where := Lang.t("on the beach") if bool(last.get("prologue", false)) else Lang.t("day %d") % int(last["day"])
		var cont := _button(Lang.t("Continue  ·  %s, %d men") % [where, int(last.get("men", 0))], _on_continue, true)
		col.add_child(cont)
	var new_b := _button(Lang.t("New campaign"), _open_slots.bind("new"), last.is_empty())
	col.add_child(new_b)
	col.add_child(_button(Lang.t("Load a campaign"), _open_slots.bind("load")))
	var rule := ColorRect.new()
	rule.color = Color(UI.PIPECLAY, 0.18)
	rule.custom_minimum_size = Vector2(0, 1)
	var rule_box := MarginContainer.new()
	rule_box.add_theme_constant_override("margin_top", 8)
	rule_box.add_theme_constant_override("margin_bottom", 8)
	rule_box.add_child(rule)
	col.add_child(rule_box)
	var tests := _button(Lang.t("Tests"), _open_tests)
	tests.custom_minimum_size = Vector2(0, 62)
	tests.add_theme_font_size_override("font_size", 24)
	col.add_child(tests)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	# Settings along the foot: view, graphics, music.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	col.add_child(foot)
	_tp_check = CheckButton.new() # (hidden: the code that starts a game reads it)
	_tp_check.visible = false
	add_child(_tp_check)
	_tp_check.button_pressed = Settings.third_person
	var view := Button.new()
	view.flat = true
	view.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	view.add_theme_font_size_override("font_size", 20)
	var view_label := func(): view.text = Lang.t("View: %s") % (Lang.t("third person") if _tp_check.button_pressed else Lang.t("first person"))
	view_label.call()
	view.pressed.connect(func():
		_tp_check.button_pressed = not _tp_check.button_pressed
		Settings.third_person = _tp_check.button_pressed
		Settings.save_prefs()
		view_label.call())
	foot.add_child(view)
	var gfx := Button.new()
	gfx.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	gfx.add_theme_font_size_override("font_size", 20)
	gfx.flat = true
	gfx.add_theme_color_override("font_color", UI.PIPECLAY)
	var label := func(): gfx.text = Lang.t("Graphics: %s") % Lang.t(Settings.graphics.capitalize())
	label.call()
	gfx.pressed.connect(func():
		var i := Settings.GRAPHICS.find(Settings.graphics)
		Settings.graphics = Settings.GRAPHICS[(i + 1) % Settings.GRAPHICS.size()]
		Settings.save_prefs()
		label.call())
	foot.add_child(gfx)
	# The version, small, at the very bottom (project.godot's config/version).
	var ver := Label.new()
	ver.text = Lang.t("Version %s") % String(ProjectSettings.get_setting("application/config/version", "?"))
	ver.add_theme_font_size_override("font_size", 15)
	ver.add_theme_color_override("font_color", Color(UI.SLATE, 0.8))
	ver.anchor_left = 0.5
	ver.anchor_right = 0.5
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -120
	ver.offset_right = 120
	ver.offset_top = -30
	ver.offset_bottom = -8
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)
	_build_tests()
	# The music button in the bottom-right corner, away from the menu.
	MusicBar.attach(self, get_viewport_rect().size - Vector2(84, 84))
	_build_flags()
	_build_slots()


## The language flags in the top-right corner: pressing one translates the
## whole game (remembered) and rebuilds the menu in it.
func _build_flags() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.offset_left = -3 * 106 - 28
	row.offset_right = -28
	row.offset_top = 24
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)
	for l in ["en", "pt_BR", "es"]:
		var f = FlagButton.new(l)
		f.chosen = Lang.current == l
		f.pressed.connect(func():
			if Lang.current == l:
				return
			Lang.set_language(l)
			Settings.save_prefs()
			get_tree().reload_current_scene.call_deferred())
		row.add_child(f)


## Tests: `--branch=line|pike|artillery|cavalry` and `--difficulty=...`.
static func _test_start() -> Dictionary:
	var st := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--branch="):
			st["branch"] = a.substr(9)
		elif a.begins_with("--difficulty="):
			st["difficulty"] = a.substr(13)
		elif a.begins_with("--colours="):
			# --colours=COAT,PATTERN,FIELD,CHARGE (indexes into colours.gd's lists)
			var p := a.substr(10).split(",")
			var C := preload("res://scripts/colours.gd")
			st["colours"] = {"coat": C.to_arr(C.COATS[int(p[0])][1]), "pattern": C.PATTERNS[int(p[1])],
				"field": C.to_arr(C.FLAG_COLOURS[int(p[2])]), "charge": C.to_arr(C.FLAG_COLOURS[int(p[3])])}
	return st


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 28)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	return b


func _on_continue() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = false
	Settings.mixed = false
	Settings.siege_test = false
	Settings.field = {}
	Settings.playground = false
	Settings.save_prefs()
	World.is_ready = false # load this slot's land fresh
	if Company.load_campaign():
		# Saved before the prologue was fought: back to the beach.
		if Company.prologue:
			Loading.change(BATTLE)
		elif Company.results_unseen or not World.has_save():
			Loading.change(CAMP)
		else:
			Loading.change(MAP) # back on the road


# ---------------------------------------------------------------- save slots

func _build_slots() -> void:
	_slots_panel = PanelContainer.new()
	_slots_panel.add_theme_stylebox_override("panel", UI.box(Color(UI.WOOL, 0.98), 24, 6, 0.3))
	_slots_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_slots_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slots_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_slots_panel.custom_minimum_size = Vector2(1000, 0)
	_slots_panel.visible = false
	add_child(_slots_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_slots_panel.add_child(v)
	_slots_title = UI.heading("", 34)
	v.add_child(_slots_title)
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 10)
	v.add_child(_slots_box)
	var back := _button(Lang.t("Back"), func(): _slots_panel.visible = false)
	back.custom_minimum_size = Vector2(200, 60)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)


func _open_slots(mode: String) -> void:
	_mode = mode
	_armed = ""
	_fill_slots()
	_slots_panel.visible = true


func _fill_slots() -> void:
	_slots_title.text = Lang.t("Choose a slot for the new campaign") if _mode == "new" else Lang.t("Load a campaign")
	for c in _slots_box.get_children():
		c.queue_free()
	for i in range(1, Settings.SLOTS + 1):
		var info := Settings.slot_summary(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_slots_box.add_child(row)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if info.is_empty():
			l.text = Lang.t("Slot %d   ·   empty") % i
			l.add_theme_color_override("font_color", UI.SLATE)
		else:
			var where := Lang.t("on the beach") if info["prologue"] else Lang.t("day %d") % int(info["day"])
			l.text = Lang.t("Slot %d   ·   %s, %d men, %d crowns%s\nsaved %s") % [i, where, int(info["men"]),
				int(info["money"]), (Lang.t("  ·  land %s") % info["seed"]) if info["seed"] != "" else "", info["when"]]
		row.add_child(l)
		var main := ""
		if _mode == "new":
			main = Lang.t("Start here") if info.is_empty() else (Lang.t("Tap again to overwrite") if _armed == "new%d" % i else Lang.t("Overwrite"))
		else:
			main = Lang.t("Load")
		var b := _button(main, _on_slot.bind(i))
		b.custom_minimum_size = Vector2(250, 60)
		b.add_theme_font_size_override("font_size", 20)
		b.disabled = _mode == "load" and info.is_empty()
		row.add_child(b)
		if not info.is_empty():
			var d := _button(Lang.t("Tap again") if _armed == "del%d" % i else "Delete", _on_delete.bind(i))
			d.custom_minimum_size = Vector2(140, 60)
			d.add_theme_font_size_override("font_size", 18)
			row.add_child(d)


func _on_slot(i: int) -> void:
	var used := not Settings.slot_summary(i).is_empty()
	if _mode == "new":
		# Don't wipe a campaign with one stray tap.
		if used and _armed != "new%d" % i:
			_armed = "new%d" % i
			_fill_slots()
			return
		Settings.use_slot(i)
		Settings.third_person = _tp_check.button_pressed
		Settings.stress = false
		Settings.mixed = false
		Settings.siege_test = false
		Settings.field = {}
		Settings.playground = false
		Settings.save_prefs()
		# Who you are, first (creation.gd starts the campaign in this slot).
		Loading.change(CREATION)
	else:
		Settings.use_slot(i)
		_on_continue()


func _on_delete(i: int) -> void:
	if _armed != "del%d" % i:
		_armed = "del%d" % i
		_fill_slots()
		return
	Settings.delete_slot(i)
	_armed = ""
	_fill_slots()


# ---------------------------------------------------------------- tests

var _tests_panel: PanelContainer


## Tests: fights outside the campaign, to try things out.
func _build_tests() -> void:
	_tests_panel = PanelContainer.new()
	_tests_panel.add_theme_stylebox_override("panel", UI.box(Color(UI.WOOL, 0.98), 24, 6, 0.3))
	_tests_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_tests_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tests_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tests_panel.custom_minimum_size = Vector2(760, 0)
	_tests_panel.visible = false
	add_child(_tests_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_tests_panel.add_child(v)
	v.add_child(UI.heading(Lang.t("Tests"), 34))
	for t in [
		[Lang.t("Weapon range"), Lang.t("You alone with every weapon: musket, bayonet, pistol, sabre, bow, crossbow and grenades. Send targets or charging lizards when you like. You can't die."), _on_playground],
		[Lang.t("Field battle"), Lang.t("Total War on foot: pick the ground and both armies (muskets, pikes, bows, crossbows, cavalry, cannon; lizards or a rival army), lead your company and command the rest from above."), _on_field],
		[Lang.t("Skirmish"), Lang.t("A mixed company of muskets, spears, bows and crossbows against three waves."), _on_skirmish],
		[Lang.t("Nest assault"), Lang.t("The mixed company and two guns against a lizard nest: break the gate, beat off the sallies, storm it."), _on_siege_test],
		[Lang.t("Stress test"), Lang.t("50 musketeers against 200 lizardmen, with a frame counter, to see what your phone can take."), _on_stress],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		v.add_child(row)
		var b := _button(t[0], t[2])
		b.custom_minimum_size = Vector2(230, 66)
		b.add_theme_font_size_override("font_size", 24)
		row.add_child(b)
		var l := Label.new()
		l.text = t[1]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", UI.SLATE.lightened(0.25))
		row.add_child(l)
	var back := _button(Lang.t("Back"), func(): _tests_panel.visible = false)
	back.custom_minimum_size = Vector2(200, 60)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)


func _open_tests() -> void:
	_tests_panel.visible = true


func _on_playground() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = false
	Settings.mixed = false
	Settings.siege_test = false
	Settings.field = {}
	Settings.playground = true
	Company.active = false
	Loading.change(BATTLE)


func _on_siege_test() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = false
	Settings.playground = false
	Settings.mixed = true
	Settings.siege_test = true
	Settings.field = {}
	Company.active = false
	Loading.change(BATTLE)


func _on_field() -> void:
	Settings.third_person = _tp_check.button_pressed
	get_tree().change_scene_to_file("res://scenes/field_setup.tscn")


func _on_skirmish() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.stress = false
	Settings.playground = false
	Settings.mixed = true
	Settings.siege_test = false
	Settings.field = {}
	Company.active = false
	Loading.change(BATTLE)


func _on_stress() -> void:
	Settings.third_person = _tp_check.button_pressed
	Settings.mixed = false
	Settings.siege_test = false
	Settings.field = {}
	Settings.playground = false
	Settings.stress = true
	Company.active = false
	Loading.change(BATTLE)
