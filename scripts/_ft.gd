extends SceneTree
func _initialize():
	root.get_node("Settings").slot = 99
	var C = root.get_node("Company")
	C.new_campaign()
	C.apply_battle({"won": true, "slain": 40, "officer_kills": 2, "men": {}, "prologue": true})
	var W = root.get_node("World")
	W.reset(); W.is_ready = false; W.ensure()
	var Folk = load("res://scripts/folk.gd")
	var T = load("res://scripts/tongue.gd")
	var sid := -1
	for st in W.gen.settlements:
		if st["kind"] == "town":
			sid = int(st["id"]); break
	var st = W.gen.settlements[sid]
	print("TOWN ", st["name"], " ", st["faction"], " ", Folk.surroundings(sid).keys())
	var sur = Folk.surroundings(sid)
	print(" river ", sur["river"], " coast ", sur["coast"], " forest ", sur["forest"], " nest ", sur["nest"].get("name"))
	var ppl = Folk.people(sid)
	for p in ppl.slice(0, 5):
		print(" - ", p["name"], " ", p["sex"], p["age"], " ", p["job"], " ", p["traits"], " need ", p["need"], " | ", p["story"])
	var lang = ppl[0]["lang"]
	print("WORDS hello=", T.word(lang, "hello"), " food=", T.word(lang, "food"), " lizard=", T.word(lang, "lizard"))
	var ctx = {"sur": sur}
	for p in ppl.slice(0, 3):
		Folk.met(p)
		for a in ["greet", "name", "listen", "gift_food", "ask_lizards", "ask_work", "musket", "join"]:
			var r = Folk.exchange(p, a, Folk.can_use_words(p, a), ctx)
			print("  [", a, "] ", r["you"], " -> ", r["see"], " ", T.render(lang, r["say"]), " ", r["note"], " learned ", r["learned"], " dt ", r["trust_change"], " joined ", r["joined"])
			if r["joined"]:
				Folk.recruit(p)
			if r["end"]:
				break
		print("  KNOW: ", Folk.what_you_know(p))
	print("FLUENCY ", T.fluency(lang), " ", T.level(lang), " words ", T.words_known(lang), " roster ", C.roster.size())
	quit()
