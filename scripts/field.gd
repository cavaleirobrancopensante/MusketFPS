extends Node3D
## A field battle (Tests > Field battle): Total War on a phone, with you on
## foot in the middle of it.
##
## Two armies of regiments (regiment.gd) deploy facing each other across a
## map (field_terrain.gd). You lead your own company in first person, with
## the campaign's orders (FOLLOW, HOLD, CHARGE, AT WILL, VOLLEY), and open
## the command view (field_ui.gd) whenever you like: time slows almost to a
## stop (or stops), you see the field from above, and you give every
## regiment its orders by tapping and dragging. Release it and watch it
## play out, or go back down and fight.
##
## The enemy has a general of its own (_ai below): lizards come straight on
## with their skirmishers in front and raptor riders round the flanks; a
## human army advances its line to musket range, keeps its pikes by the
## guns and sends its horse at your flanks and guns.
##
## Morale decides it, not the last man standing: losses, a charge into the
## flank or rear, horse crashing in, a neighbour breaking all shake a
## regiment; standing near you (or near nothing nasty) steadies it. Broken
## regiments run for their own edge of the field; the battle is won when
## the other side's are all running or gone.

const Terrain := preload("res://scripts/field_terrain.gd")
const Regiment := preload("res://scripts/regiment.gd")
const FieldSoldier := preload("res://scripts/field_soldier.gd")
const FieldLizard := preload("res://scripts/field_lizard.gd")
const Rider := preload("res://scripts/rider.gd")
const GunPost := preload("res://scripts/gun_post.gd")
const Lore := preload("res://scripts/lore.gd")
const Look := preload("res://scripts/look.gd")

## Unit types. men: share of the chosen unit size; ranks deep; spacing
## between files and ranks (m); walk and run (m/s); range (m, 0 = blades);
## morale; cav: horse.
const KINDS := {
	"musket": {"name": "Musketeers", "short": "MUSKETS", "men": 1.0, "ranks": 2, "spacing": 1.25, "gap": 1.5, "walk": 2.21, "run": 3.74, "range": 60.0, "morale": 65.0},
	"pike": {"name": "Pikemen", "short": "PIKES", "men": 1.0, "ranks": 3, "spacing": 1.15, "gap": 1.3, "walk": 2.04, "run": 3.4, "range": 0.0, "morale": 75.0},
	"bow": {"name": "Bowmen", "short": "BOWS", "men": 0.8, "ranks": 2, "spacing": 1.6, "gap": 1.8, "walk": 2.38, "run": 4.08, "range": 78.0, "morale": 50.0},
	"xbow": {"name": "Crossbowmen", "short": "XBOWS", "men": 0.8, "ranks": 2, "spacing": 1.4, "gap": 1.6, "walk": 2.21, "run": 3.74, "range": 66.0, "morale": 55.0},
	"cav": {"name": "Cavalry", "short": "HORSE", "men": 0.5, "ranks": 2, "spacing": 2.4, "gap": 4.0, "walk": 2.72, "run": 6.38, "range": 0.0, "morale": 75.0, "cav": true},
	# Your own horse: dragoons fire carbines from the saddle (then charge),
	# lancers charge with the lance couched.
	"dragoon": {"name": "Dragoons", "short": "DRAGOONS", "men": 0.5, "ranks": 2, "spacing": 2.4, "gap": 4.0, "walk": 2.72, "run": 6.2, "range": 45.0, "morale": 70.0, "cav": true},
	"lancer": {"name": "Lancers", "short": "LANCERS", "men": 0.5, "ranks": 2, "spacing": 2.4, "gap": 4.0, "walk": 2.72, "run": 6.6, "range": 0.0, "morale": 78.0, "cav": true},
	# The kingdoms' (medieval) arms: footmen with sword and shield, longbows,
	# armoured knights, and catapults.
	"sword": {"name": "Men-at-arms", "short": "SWORDS", "men": 1.0, "ranks": 3, "spacing": 1.2, "gap": 1.4, "walk": 2.21, "run": 3.9, "range": 0.0, "morale": 72.0},
	"longbow": {"name": "Longbowmen", "short": "LONGBOWS", "men": 0.8, "ranks": 2, "spacing": 1.6, "gap": 1.8, "walk": 2.38, "run": 4.08, "range": 95.0, "morale": 55.0},
	"knight": {"name": "Knights", "short": "KNIGHTS", "men": 0.4, "ranks": 2, "spacing": 2.6, "gap": 4.4, "walk": 2.55, "run": 6.0, "range": 0.0, "morale": 92.0, "cav": true},
	"catapult": {"name": "Catapults", "short": "CATAPULTS", "men": 0.0, "guns": 2, "ranks": 1, "spacing": 12.0, "gap": 0.0, "walk": 0.9, "run": 1.0, "range": 210.0, "morale": 50.0, "engine": true},
	"gun": {"name": "Cannon", "short": "GUNS", "men": 0.0, "guns": 2, "ranks": 1, "spacing": 10.0, "gap": 0.0, "walk": 1.19, "run": 1.36, "range": 240.0, "morale": 55.0},
	"liz_warrior": {"name": "Lizard warriors", "short": "WARRIORS", "men": 1.25, "ranks": 3, "spacing": 1.6, "gap": 1.7, "walk": 2.55, "run": 4.25, "range": 0.0, "morale": 88.0},
	"liz_skirm": {"name": "Javelin throwers", "short": "JAVELINS", "men": 0.8, "ranks": 2, "spacing": 2.4, "gap": 2.4, "walk": 2.72, "run": 4.42, "range": 28.0, "morale": 55.0},
	"liz_brute": {"name": "Brutes", "short": "BRUTES", "men": 0.4, "ranks": 2, "spacing": 2.4, "gap": 2.6, "walk": 2.21, "run": 3.23, "range": 0.0, "morale": 100.0},
	"liz_raptor": {"name": "Raptor riders", "short": "RAPTORS", "men": 0.5, "ranks": 2, "spacing": 2.6, "gap": 4.0, "walk": 2.89, "run": 5.95, "range": 0.0, "morale": 80.0, "cav": true},
}
## Your side's arms, and the kingdoms' (both are "humans").
const OUR_KINDS := ["musket", "pike", "bow", "xbow", "dragoon", "lancer", "gun"]
const NATION_KINDS := ["sword", "pike", "longbow", "xbow", "knight", "catapult"]
const HUMAN_KINDS := ["musket", "pike", "bow", "xbow", "cav", "gun", "dragoon", "lancer", "sword", "longbow", "knight", "catapult"]
const LIZARD_KINDS := ["liz_warrior", "liz_skirm", "liz_brute", "liz_raptor"]
const ORDINAL := ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th", "11th", "12th"]

var battle
var cfg: Dictionary = {}
var terrain
var regs: Array = []
var clock := 0.0
var ui = null # field_ui.gd
var env: Environment
var over := ""
var ai_sides := [1] # which sides the general below commands (both in the autotest)
var player_reg = null
var _tick_i := 0
var _morale_t := 0.0
var _ai_t := 0.0
var _deaths := {} # regiment -> deaths since the last morale tick
var _check_t := 0.0
var _broke_told := {}
var _flank_side := 1.0
var deploy_z := 62.0
var enemy_z := 62.0
var campaign := false # a fight from the campaign map (your own men; results go back)
var prologue := false # the beach: the tutorial battle (see the prologue section)
var camp := false # attacked in the night camp (or a sortie from a besieged nest)
var spotted := false # ...and the watch saw them coming
var assault := false # storming a lizard nest (nest_assault.gd)
var camp_fire := Vector3.ZERO
var fog := 0.0022 # the air's haze down among the men (the command view clears it)
## The other side's coats (a nation's colour in the campaign), and which
## nation it is ("" in the Tests' battle: the old red-coated musketeers).
var foe_coat := Color(0.62, 0.12, 0.1)
var nation := ""
## A nation fighting beside you (Company.next_battle.allies), its coats.
var ally_nation := ""
var ally_coat := Color(0.62, 0.12, 0.1)
var _making_allied := false # (while its men are made: they dress as its soldiers)
var _making_light := false # (while the artillery officer's galloper is made)
## How fast the battle goes (the setup's PACE): marching, loading and blows
## all scale with it, so there's time to fight and to command.
var pace := 0.75
## `-- --fieldtest[=map]`: both armies fight themselves and it reports.
var test_mode := false


## The settings from the setup screen (Settings.field): map, size (men per
## unit), you: {kind: count}, foe_army: "lizards"/"humans", foe: {kind: count}.
func setup(b, c: Dictionary) -> void:
	battle = b
	cfg = c
	terrain = Terrain.new(String(c.get("map", "flat")))
	pace = float(c.get("pace", 0.75))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fieldtest") or a == "--autotest":
			test_mode = true
	deploy_z = 92.0 if terrain.kind == "town" else 80.0
	campaign = bool(c.get("campaign", false))
	prologue = bool(c.get("prologue", false))
	if prologue:
		# The beach: your line just behind the works, the forest 80 m off.
		deploy_z = 8.0
		enemy_z = 72.0
		cfg["you"] = {"musket": 1}
		cfg["foe"] = {"liz_warrior": 1, "liz_skirm": 1, "liz_brute": 1, "liz_raptor": 1}
		ai_sides = [1]
		return
	if campaign:
		# Small fights start closer: a company and a warband don't need a
		# quarter of a mile between them.
		var total := Company.fit_men().size() + int(Company.next_battle.get("enemy", Company.next_enemy_count()))
		deploy_z = clampf(26.0 + total * 0.35, 38.0, 80.0)
		if terrain.kind == "town":
			deploy_z = maxf(deploy_z, 70.0)
		enemy_z = deploy_z * (0.55 if bool(c.get("ambush", false)) else 1.0)
		var nb: Dictionary = Company.next_battle
		var f := String(c.get("faction", ""))
		if Lore.FACTIONS.has(f) and Lore.FACTIONS[f].has("coat"):
			nation = f
			foe_coat = Lore.FACTIONS[f]["coat"]
		# Which far stand-ins to render (make_sprites).
		var foe := {}
		for k in nb.get("comp", {}):
			foe[k] = 1
		if foe.is_empty():
			foe = {"liz_warrior": 1, "liz_skirm": 1, "liz_brute": 1, "liz_raptor": 1}
		cfg["foe"] = foe
		var you := {"musket": 1}
		for m in Company.fit_men():
			var role := Company.role_of(m)
			you["xbow" if role == "crossbow" else role] = 1
		if Company.guns > 0:
			you["gun"] = 1
		var al: Dictionary = nb.get("allies", {})
		var af := String(al.get("faction", ""))
		if Lore.FACTIONS.has(af) and Lore.FACTIONS[af].has("coat"):
			ally_nation = af
			ally_coat = Lore.FACTIONS[af]["coat"]
			ai_sides = [0, 1] # (its general commands what you don't)
			var ak := {}
			for k in al.get("comp", {}):
				ak[k] = 1
			cfg["ally"] = ak
		cfg["you"] = you
		camp = bool(c.get("camp", false))
		spotted = camp and bool(c.get("spotted", false))
		assault = bool(c.get("assault", false))
		if assault:
			terrain.flatten(Vector2(0, NEST_Z), 21.0) # (the nest's clearing)
		if camp:
			# The fire in the middle of the field; the line forms just in
			# front of it; they come out of the dark from the far side.
			camp_fire = Vector3(0, 0, 22.0)
			deploy_z = 16.0
			enemy_z = 42.0
	else:
		enemy_z = deploy_z
	if test_mode or bool(c.get("auto", false)):
		ai_sides = [0, 1]


func build_world(parent: Node3D) -> void:
	# Greener and deeper than the campaign's fields: from up in the command
	# view everything pales, so it needs the colour.
	var cols := {"grass_dark": Color(0.13, 0.23, 0.07), "grass_light": Color(0.33, 0.44, 0.14), "dirt": Color(0.42, 0.33, 0.2), "dirt_amount": 0.22, "grass": 1.0}
	if terrain.kind == "hills":
		cols = {"grass_dark": Color(0.2, 0.27, 0.09), "grass_light": Color(0.42, 0.47, 0.2), "dirt": Color(0.45, 0.38, 0.25), "dirt_amount": 0.3, "grass": 0.8}
	elif terrain.kind == "forest":
		cols = {"grass_dark": Color(0.1, 0.19, 0.06), "grass_light": Color(0.26, 0.36, 0.12), "dirt": Color(0.32, 0.25, 0.15), "dirt_amount": 0.35, "grass": 0.7}
	elif terrain.kind == "beach":
		# Sand where the line stands; "dirt" is the green going inland.
		cols = {"grass_dark": Color(0.6, 0.53, 0.37), "grass_light": Color(0.74, 0.67, 0.49), "dirt": Color(0.16, 0.27, 0.12), "dirt_amount": 0.04, "grass": 0.0}
	terrain.build(parent, cols)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	if terrain.kind == "beach":
		battle._build_beach() # (the sea, the wreck, the works, the strange forest, the path)
		Look.far_hills(parent, rng, Terrain.OUTER - 10.0, Color(0.3, 0.42, 0.4), 18)
		return
	var h: Callable = func(p: Vector3) -> bool: return terrain.cell(p) == terrain.BLOCKED or (terrain.has_water and terrain.height(p.x, p.z) < terrain.water_y + 0.05)
	var g = Look.grass(parent, Vector3(0, 0, deploy_z - 10.0), 85.0, float(cols.get("grass", 1.0)), cols, [], rng, h)
	if g != null:
		var mm: MultiMesh = g.multimesh
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			t.origin.y = terrain.height(t.origin.x, t.origin.z)
			mm.set_instance_transform(i, t)
	Look.far_hills(parent, rng, Terrain.OUTER - 10.0, (cols["grass_dark"] as Color).lerp(Color(0.75, 0.8, 0.8), 0.35), 18)


# ---------------------------------------------------------------- sprites

const Impostor := preload("res://scripts/impostor.gd")
var sprites := {} # sprite kind -> [frames info, cell metres]


## The far stand-ins for every kind in this battle, rendered from the rigs
## (impostor.gd). Headless, there's no renderer: the old sprites stay.
func make_sprites() -> void:
	if not Impostor.available():
		return
	var want := {}
	for k in cfg.get("you", {}):
		if int(cfg["you"][k]) > 0:
			want[_sprite_name(k, 0)] = [k, 0]
	want[_sprite_name("musket", 0)] = ["musket", 0]
	for k in cfg.get("ally", {}):
		want[_sprite_name(k, 2)] = [k, 2]
	var foe_side := 1
	for k in cfg.get("foe", {}):
		if int(cfg["foe"][k]) > 0:
			want[_sprite_name(k, foe_side)] = [k, foe_side]
	for name in want:
		var k: String = want[name][0]
		var s: int = want[name][1]
		if KINDS[k].has("guns"):
			continue
		var spec := _sprite_spec(k, s)
		var frames: Dictionary = await Impostor.render(battle, spec)
		if frames.is_empty():
			print("field: no rendered sprite for %s, keeping the drawn one" % name)
			continue
		sprites[name] = [battle.batcher.add_sprite_kind(name, frames), float(spec["cell_m"])]


func _sprite_name(kind: String, side: int) -> String:
	match kind:
		"liz_warrior", "liz_skirm":
			return "f_lizard"
		"liz_brute":
			return "f_brute"
		"liz_raptor":
			return "f_raptor"
	return "f_%s%d" % [kind, side] # (side 2: a nation fighting beside you)


func _sprite_spec(kind: String, side: int) -> Dictionary:
	var red := foe_coat
	match kind:
		"cav":
			return {"mount": "horse", "gear": {"head": ("kettle_hat" if nation != "" else "tricorne") if side == 1 else "shako", "torso": "coat", "primary": "none", "secondary": "", "sword": "saber"},
				"coat": red if side == 1 else null, "saddle": red if side == 1 else preload("res://scripts/colours.gd").coat(), "cell_m": 3.4, "anims": Impostor.RIDER_ANIMS}
		"knight":
			var kc = red if side == 1 else (ally_coat if side == 2 else Color(0.55, 0.14, 0.12))
			return {"mount": "horse", "gear": {"head": "great_helm", "torso": "plate", "primary": "lance", "secondary": "", "sword": ""},
				"coat": kc, "saddle": kc, "barding": true, "hand": "", "cell_m": 3.6, "anims": Impostor.RIDER_ANIMS}
		"lancer", "dragoon":
			return {"mount": "horse", "gear": {"head": "shako", "torso": "coat", "primary": "lance" if kind == "lancer" else "carbine",
				"secondary": "" if kind == "lancer" else "bayonet", "sword": ""}, "coat": null, "saddle": preload("res://scripts/colours.gd").coat(), "hand": "",
				"cell_m": 3.6, "anims": Impostor.RIDER_ANIMS}
		"liz_raptor":
			return {"mount": "raptor", "saddle": Color(0.5, 0.36, 0.2), "cell_m": 3.4, "anims": Impostor.RIDER_ANIMS}
		"liz_warrior", "liz_skirm":
			return {"rig": "lizard", "cell_m": 2.5, "anims": Impostor.LIZARD_ANIMS}
		"liz_brute":
			return {"rig": "lizard", "scale": 1.45, "cell_m": 3.6, "anims": Impostor.LIZARD_ANIMS}
	if side == 2:
		var g2: Dictionary = FieldSoldier.NATION_GEAR.get(kind, FieldSoldier.NATION_GEAR["pike"])
		if kind == "cav":
			return {"mount": "horse", "gear": {"head": "kettle_hat", "torso": "coat", "primary": "none", "secondary": "", "sword": "saber"},
				"coat": ally_coat, "saddle": ally_coat, "cell_m": 3.4, "anims": Impostor.RIDER_ANIMS}
		return {"rig": "soldier", "gear": g2, "coat": ally_coat, "cell_m": 3.6 if kind == "pike" else 2.4, "anims": Impostor.FOOT_ANIMS}
	var gear: Dictionary = FieldSoldier.gear_for(self, kind, side)
	return {"rig": "soldier", "gear": gear, "coat": red if side == 1 else null, "cell_m": 3.6 if kind == "pike" else 2.4, "anims": Impostor.FOOT_ANIMS}


## Give a unit its rendered stand-in (if there is one).
func _dress(u, kind: String, side: int) -> void:
	var name := _sprite_name(kind, side)
	if sprites.has(name):
		u.sprite_kind = name
		u.frames = sprites[name][0]
		u.set_meta("sprite_cell", sprites[name][1])


# ---------------------------------------------------------------- mustering

func spawn_armies() -> void:
	var size := int(cfg.get("size", 20))
	var you: Dictionary = cfg.get("you", {"musket": 1})
	var foe: Dictionary = cfg.get("foe", {"liz_warrior": 2})
	# Your own company first: musketeers, and you with them.
	var mine: Array = [["musket", true, _count("musket", size)]]
	for k in OUR_KINDS + ["cav"]:
		for i in int(you.get(k, 0)):
			mine.append([k, false, _count(k, size)])
	var theirs: Array = []
	for k in (LIZARD_KINDS if String(cfg.get("foe_army", "lizards")) == "lizards" else NATION_KINDS + ["cav", "musket", "bow", "gun"]):
		for i in int(foe.get(k, 0)):
			theirs.append([k, false, _count(k, size)])
	if theirs.is_empty():
		theirs.append(["liz_warrior", false, _count("liz_warrior", size)])
	_deploy(0, mine)
	_deploy(1, theirs)
	# You: in the gap in the middle of your company's front rank.
	var p: Vector3 = player_reg.pos
	battle.player.position = Vector3(p.x, terrain.height(p.x, p.z) + 0.3, p.z)
	battle.player.rotation.y = 0.0
	player_reg.order = "follow"


## The prologue (field_prologue.gd): the beach, the Major's battle, then yours.
const Prologue := preload("res://scripts/field_prologue.gd")
var story = null


func spawn_prologue() -> void:
	story = Prologue.new(self)
	add_child(story)
	story.spawn()


## The campaign's battle: your fit men split by what they carry (muskets,
## pikes and spears, bows, crossbows) into regiments, the musketeers being
## your own company; the ship's guns if you have them back; the wagon and
## its crew behind; and the warband as it was reported.
func spawn_campaign() -> void:
	var nb: Dictionary = Company.next_battle
	var groups := {"musket": [], "pike": [], "bow": [], "xbow": [], "dragoon": [], "lancer": []}
	var porters: Array = []
	for m in Company.fit_men():
		if String(m.get("tag", "")) == "Wagon" and not camp: # (in camp the wagon is parked)
			porters.append(m)
			continue
		var role := Company.role_of(m)
		groups["xbow" if role == "crossbow" else role].append(m)
	var lead := "musket"
	if (groups["musket"] as Array).is_empty():
		for k in groups:
			if (groups[k] as Array).size() > (groups[lead] as Array).size():
				lead = k
	# Your horse ride together (each man as what he is: a dragoon or a
	# lancer) if either troop is too small to be a regiment of its own.
	var dg: Array = groups["dragoon"]
	var lg: Array = groups["lancer"]
	if not dg.is_empty() and not lg.is_empty() and (dg.size() < 4 or lg.size() < 4):
		var into := "dragoon" if dg.size() >= lg.size() else "lancer"
		groups[into] = dg + lg
		groups["lancer" if into == "dragoon" else "dragoon"] = []
	# A handful of one kind isn't a regiment: they stand with the company.
	for k in groups:
		if k in ["dragoon", "lancer"]:
			continue # (horse don't stand in a line of foot)
		if k != lead and (groups[k] as Array).size() < 4:
			(groups[lead] as Array).append_array(groups[k])
			groups[k] = []
	var mine: Array = []
	for k in ["musket", "pike", "bow", "xbow", "dragoon", "lancer"]:
		var list: Array = groups[k]
		var first := true
		for chunk in _chunks(list, 30):
			mine.append([k, k == lead and first, chunk.size(), chunk])
			first = false
	if mine.is_empty():
		mine.append(["musket", true, 1, []])
	if Company.guns > 0:
		mine.append(["gun", false, Company.guns])
	# A nation's men fighting beside you: in the same line, theirs to lead
	# until you give them an order.
	var al: Dictionary = nb.get("allies", {})
	if ally_nation != "":
		var acap := {"sword": 24, "pike": 24, "xbow": 14, "longbow": 14, "bow": 14, "knight": 8, "cav": 10, "catapult": 2}
		for k in ["sword", "pike", "xbow", "longbow", "bow", "knight", "cav", "catapult"]:
			var n := int(al.get("comp", {}).get(k, 0))
			while n > 0:
				var take := mini(n, int(acap[k]))
				if n - take > 0 and n - take < 4:
					take = n
				mine.append([k, false, take, [], true])
				n -= take
	var comp: Dictionary = nb.get("comp", {})
	if assault:
		comp = {"none": 0} # (the garrison is the nest's: _build_nest)
	elif comp.is_empty():
		comp = World.party_comp({"kind": "warband", "size": int(nb.get("enemy", Company.next_enemy_count())), "id": 0})
	if not assault:
		# The difficulty: more of them (or fewer).
		var more := Company.Officer.diff("enemy")
		if absf(more - 1.0) > 0.01:
			var scaled := {}
			for k in comp:
				scaled[k] = maxi(1 if int(comp[k]) > 0 else 0, int(round(int(comp[k]) * more)))
			comp = scaled
	var theirs: Array = []
	var cap := {"liz_warrior": 24, "liz_skirm": 14, "liz_brute": 6, "liz_raptor": 10, "pike": 24, "xbow": 14, "bow": 14, "cav": 10,
		"sword": 24, "longbow": 14, "knight": 8, "catapult": 2}
	for k in World.COMP_ORDER:
		var n := int(comp.get(k, 0))
		while n > 0:
			var take := mini(n, int(cap[k]))
			if n - take > 0 and n - take < 4:
				take = n # (no straggling little mob)
			theirs.append([k, false, take])
			n -= take
	_deploy(0, mine)
	_name_households(nb)
	if camp and not spotted:
		_in_the_camp(theirs)
	elif not theirs.is_empty():
		_deploy(1, theirs)
	_name_enemy_household(nb)
	var p: Vector3 = player_reg.pos
	battle.player.position = Vector3(p.x, terrain.height(p.x, p.z) + 0.3, p.z)
	battle.player.rotation.y = 0.0
	player_reg.order = "follow"
	if camp:
		_make_camp(nb)
	if assault:
		_build_nest(nb)
	# The wagon behind the line, its crew hauling and guarding it.
	battle.line_anchor = Vector3(p.x, 0, p.z)
	battle.line_forward = Vector3.FORWARD
	battle._build_wagon()
	var crew := 0
	for rec in porters:
		var s = battle.SoldierScript.new()
		s.battle = battle
		s.frames = battle.soldier_frames
		s.record = rec
		s.porter = crew
		crew += 1
		s.position = battle.porter_spot(s.porter)
		battle.soldiers.append(s)
		battle.add_child(s)
	if battle.wagon != null:
		battle.wagon.position = terrain.free_spot(battle.wagon.position)
	# Some lizards would rather rob the wagon than fight.
	for e in battle.enemies:
		if e is FieldLizard and e.variant == "warrior":
			e.looter = randf() < 0.3
	battle._all_men = []
	for r in regs:
		if r.side == 0:
			for m in r.members:
				if m.get("record") != null:
					battle._all_men.append(m)
	for s in battle.soldiers:
		if s.porter >= 0:
			battle._all_men.append(s)


# ---------------------------------------------------------------- the night camp
# Attacked where you sleep (map.gd decides whether the watch saw them). The
# men lie on their bedrolls in rings round the fire, the wagon parked to one
# side, the watch out at the edge. Seen in time: the alarm gets everyone up,
# they form on their regiments' ground in front of the fire, and the
# lizards come out of the dark. Not seen: the warband is already among the
# bedrolls, and each man wakes when the noise (or a blade) reaches him.

func _make_camp(nb: Dictionary) -> void:
	camp_fire.y = terrain.height(camp_fire.x, camp_fire.z)
	battle._build_campfire(camp_fire)
	var watch_ids: Array = nb.get("watch", [])
	var sleepers: Array = []
	var watch: Array = []
	for r in regs:
		if r.side != 0 or r.is_gun() or r.is_cav():
			continue # (the horse are picketed: they stand to by their mounts)
		for m in r.members:
			var rec = m.get("record")
			if rec != null and int(rec["id"]) in watch_ids:
				watch.append(m)
			else:
				sleepers.append(m)
	var n := sleepers.size()
	for i in n:
		# Rings of twenty round the fire, leaving the south (yours) open.
		var ring := i / 20
		var k := i % 20
		var in_ring := mini(20, n - ring * 20)
		var a := lerpf(-PI * 0.78, PI * 0.78, (k + 0.5) / maxf(1.0, in_ring))
		var dir := Vector3(sin(a), 0, -cos(a))
		var rad := 3.3 + ring * 3.0 + (0.9 if k % 2 == 1 else 0.0) + randf_range(-0.2, 0.2)
		var s = sleepers[i]
		s.position = terrain.free_spot(camp_fire + dir * rad)
		s.facing = -dir # feet to the fire
		s.asleep = true
		# The alarm gets men up fast; unwarned, some sleep on through the first screams.
		s.wake_in = randf_range(0.3, 2.0) if spotted else randf_range(2.0, 8.0) * (1.25 - 0.5 * float(s.steadiness))
		battle._bedroll(s.position, dir, i)
	# The watch: out at the edge of the firelight, looking out.
	for k in watch.size():
		watch[k].position = terrain.free_spot(camp_fire + Vector3(-3.0 + 6.0 * k, 0, -9.5))
		watch[k].facing = Vector3.FORWARD
	# You: on your bedroll on the near side of the fire.
	var me: Vector3 = terrain.free_spot(camp_fire + Vector3(0, 0, 3.4))
	battle.player.position = me + Vector3.UP * 0.1
	battle._bedroll(me, Vector3.BACK, 99)
	battle.player.asleep_left = 0.4 if spotted else 1.6


## Unseen, the warband is already in among the bedrolls: its mobs all round
## the fire, every one making for the nearest men.
func _in_the_camp(theirs: Array) -> void:
	var c := camp_fire
	for i in theirs.size():
		var e: Array = theirs[i]
		var a := TAU * (float(i) + randf_range(0.0, 0.6)) / maxf(1.0, theirs.size()) + 0.4
		var d := randf_range(11.0, 17.0) if e[0] != "liz_raptor" else 30.0
		var at := c + Vector3(sin(a) * d, 0, -cos(a) * d)
		var fwd := (c - at).normalized()
		_make_reg(1, e[0], int(e[2]), at, fwd, false)


# ---------------------------------------------------------------- storming a nest
# The nest (nest_assault.gd) stands in the far half of the field, its gate
# toward you; your army deploys to storm it. Its garrison: throwers on the
# platforms behind the stakes, and mobs holding inside (behind the stakes
# nobody can shoot them), loosed when the gate falls or you're at a gap. The
# rest sally out of the gate in waves. The guns batter the gate when there's
# nothing else to shoot; men at the gate hack at it.

const NestScript := preload("res://scripts/nest_assault.gd")
const NEST_Z := -26.0


func _build_nest(nb: Dictionary) -> void:
	var nest = NestScript.new()
	nest.field = self
	battle.add_child(nest)
	battle.nest = nest
	var from := Vector3(0, 0, deploy_z)
	nest.setup(battle, from, Vector3.FORWARD, deploy_z - NEST_Z, maxi(8, int(nb.get("enemy", 40))),
		float(nb.get("walls", 1.0)), bool(nb.get("stash", false)))
	nest.position.y = terrain.height(0.0, NEST_Z)
	wall_nest()
	if test_mode:
		var tr: Array = []
		for r in nest.defender_regs:
			tr.append(Lang.t("%s %d at %s") % [r.kind, r.members.size(), r.pos.round()])
		print("NEST centre ", nest.centre.round(), " gate ", nest.gate_point().round(), " openings ", nest.openings().size(), " garrison ", tr, " sallies ", nest._sallies)


## The palisade in the paths: its ring blocked but for the breaches (and the
## gate once it's down). Again whenever the gate falls.
func wall_nest() -> void:
	var nest = battle.nest
	terrain.ring_wall(nest.centre, nest.R, nest.openings())


## The garrison holding inside (nest_assault.gd asks): `mob` lizards and
## `throwers` on the platforms.
func garrison(nest, mob: int, throwers: int) -> void:
	var c: Vector3 = nest.centre
	var toward: Vector3 = nest.gate_point() - c
	toward.y = 0.0
	toward = toward.normalized()
	var right := toward.cross(Vector3.UP)
	if throwers > 0:
		var t = _make_reg(1, "liz_skirm", throwers, c + toward * (nest.R - 3.0), toward, false)
		t.title = Lang.t("Throwers on the stakes")
		t.hold_fast = true
		nest.defender_regs.append(t)
	var brutes := mob / 14 if mob >= 28 else 0
	if brutes > 0:
		var b = _make_reg(1, "liz_brute", brutes, c - toward * 5.0, toward, false)
		b.hold_fast = true
		b.covered = true
		nest.defender_regs.append(b)
		mob -= brutes
	var chunks := ceili(mob / 20.0)
	for i in chunks:
		var n := mob / chunks + (1 if i < mob % chunks else 0)
		var x := (float(i) - (chunks - 1) * 0.5) * 8.0
		var r = _make_reg(1, "liz_warrior", n, c + right * x + toward * 1.5, toward, false)
		r.title = Lang.t("The nest's %s") % ["warriors", Lang.t("second mob"), Lang.t("third mob")][mini(i, 2)]
		r.hold_fast = true
		r.covered = true
		nest.defender_regs.append(r)


## A sally out of the gate: `n` lizards in mobs of up to 24. Returns the men.
func sally(nest, n: int) -> Array:
	var out: Array = []
	var gp: Vector3 = nest.gate_point()
	var outward: Vector3 = gp - nest.centre
	outward.y = 0.0
	outward = outward.normalized()
	var right := outward.cross(Vector3.UP)
	var chunks := ceili(n / 24.0)
	for i in chunks:
		var k := n / chunks + (1 if i < n % chunks else 0)
		var at := gp + outward * (6.0 + i * 6.0) + right * (float(i % 2) * 2.0 - 1.0) * 3.0 * float(mini(i, 1))
		var r = _make_reg(1, "liz_warrior", k, at, outward, false)
		r.title = Lang.t("Sally from the gate")
		if ui != null:
			ui.add_banner(r)
		out.append_array(r.members)
	return out


## The gate is down or the way is open: the garrison comes out to fight.
func release(regs_in: Array) -> void:
	for r in regs_in:
		if r.hold_fast or r.covered:
			r.hold_fast = false
			r.covered = false


static func _chunks(list: Array, size: int) -> Array:
	var out: Array = []
	if list.is_empty():
		return out
	var n := ceili(float(list.size()) / size)
	var each := ceili(float(list.size()) / n)
	for i in n:
		out.append(list.slice(i * each, mini(list.size(), (i + 1) * each)))
	return out


func _count(kind: String, size: int) -> int:
	var info: Dictionary = KINDS[kind]
	if info.has("guns"):
		return int(info["guns"])
	return maxi(4, int(round(size * float(info["men"]))))


## Lay out one side's regiments: the infantry in a line (shooters on the
## ends, blades between the muskets), guns out in front, horse on the
## wings, skirmishers ahead of lizards. A line too wide for the field goes
## in two.
## Entries: [kind, yours (bool), men, (records: the campaign's men)].
func _deploy(side: int, list: Array) -> void:
	var fwd := Vector3.FORWARD if side == 0 else Vector3.BACK
	var z := deploy_z if side == 0 else -enemy_z
	var right := fwd.cross(Vector3.UP)
	var inf: Array = []
	var guns: Array = []
	var cav: Array = []
	var skirm: Array = []
	for e in list:
		var k: String = e[0]
		if KINDS[k].has("guns"):
			guns.append(e)
		elif bool(KINDS[k].get("cav", false)):
			cav.append(e)
		elif k == "liz_skirm":
			skirm.append(e)
		else:
			inf.append(e)
	# Shooters to the ends, the rest alternating out from the middle.
	var shoot: Array = inf.filter(func(e): return e[0] in ["bow", "xbow"])
	var core: Array = inf.filter(func(e): return not e[0] in ["bow", "xbow"])
	var line: Array = []
	for i in core.size():
		if i % 2 == 0:
			line.append(core[i])
		else:
			line.push_front(core[i])
	for i in shoot.size():
		if i % 2 == 0:
			line.push_front(shoot[i])
		else:
			line.append(shoot[i])
	# Your company stays in the middle of your line.
	var rows: Array = [line]
	var widths := func(arr: Array) -> float:
		var w := 0.0
		for e in arr:
			w += _width_n(e[0], int(e[2])) + 8.0
		return w
	if widths.call(line) > 230.0:
		var half := line.size() / 2
		rows = [line.slice(0, half), line.slice(half)]
	var line_ends := 0.0
	for ri in rows.size():
		var row: Array = rows[ri]
		var total: float = widths.call(row) - 8.0
		var x := -total * 0.5
		line_ends = maxf(line_ends, total * 0.5)
		for e in row:
			var w := _width_n(e[0], int(e[2]))
			var at := Vector3(0, 0, z) + right * (x + w * 0.5) + fwd * (-ri * 28.0)
			_make_reg(side, e[0], int(e[2]), at, fwd, bool(e[1]), e[3] if e.size() > 3 else [], 0.0, e.size() > 4 and bool(e[4]))
			x += w + 8.0
	for i in guns.size():
		var gx := (float(i) - (guns.size() - 1) * 0.5) * 34.0
		_make_reg(side, guns[i][0], int(guns[i][2]), Vector3(0, 0, z) + right * gx + fwd * (14.0 if guns[i][0] == "gun" else -10.0), fwd, false)
	for i in skirm.size():
		var sx := (float(i) - (skirm.size() - 1) * 0.5) * 36.0
		_make_reg(side, "liz_skirm", int(skirm[i][2]), Vector3(0, 0, z) + right * sx + fwd * 18.0, fwd, false)
	for i in cav.size():
		var sgn := -1.0 if i % 2 == 0 else 1.0
		var cw := _width_n(cav[i][0], int(cav[i][2]))
		var wing := line_ends + 14.0 + cw * 0.5 + (i / 2) * (cw + 10.0)
		wing = minf(wing, Terrain.HALF - 12.0)
		_make_reg(side, cav[i][0], int(cav[i][2]), Vector3(0, 0, z) + right * sgn * wing - fwd * 4.0, fwd, false, cav[i][3] if cav[i].size() > 3 else [], 0.0, cav[i].size() > 4 and bool(cav[i][4]))


func _width_n(kind: String, n: int) -> float:
	var info: Dictionary = KINDS[kind]
	var files := ceili(float(n) / int(info["ranks"]))
	return maxf(4.0, (files - 1) * float(info["spacing"]))


func _make_reg(side: int, kind: String, n: int, at: Vector3, fwd: Vector3, yours: bool, recs: Array = [], spacing := 0.0, allied := false):
	var r = Regiment.new()
	r.field = self
	r.id = regs.size()
	r.side = side
	r.kind = kind
	r.info = KINDS[kind]
	r.files = ceili(float(n) / int(r.info["ranks"]))
	r.spacing = spacing if spacing > 0.0 else float(r.info["spacing"])
	r.rank_gap = float(r.info["gap"])
	r.max_morale = float(r.info["morale"])
	r.morale = r.max_morale
	r.forward = fwd
	r.dest_forward = fwd
	r.player_led = yours
	r.allied = allied
	at = terrain.free_spot(at)
	r.pos = at
	var same := regs.filter(func(x): return x.side == side and x.kind == kind).size()
	r.title = Lang.t("Your company") if yours else "%s %s" % [Lang.t(ORDINAL[mini(same, ORDINAL.size() - 1)]), Lang.t(r.info["name"])]
	if allied:
		r.title = "%s %s" % [Lore.FACTIONS[ally_nation]["short"], Lang.t({"pike": "spearmen", "bow": "archers", "xbow": "crossbowmen", "cav": "horse"}.get(kind, String(r.info["name"]).to_lower()))]
	_making_allied = allied
	regs.append(r)
	_deaths[r] = 0
	if yours:
		player_reg = r
	for i in n:
		var u = _make_unit(side, kind) if i >= recs.size() else (Rider.from_record(battle, self, recs[i], side, Company.role_of(recs[i])) if bool(KINDS[kind].get("cav", false)) else FieldSoldier.from_record(battle, self, recs[i], side))
		if not r.info.has("guns"):
			_dress(u, kind, 2 if allied else side)
		u.reg = r
		u.slot_index = i
		r.members.append(u)
	r.size0 = r.members.size()
	_making_allied = false
	if side == 1 and (campaign or prologue):
		# The difficulty: tougher and braver enemies.
		var tough := Company.Officer.diff("tough")
		r.max_morale *= tough
		r.morale = r.max_morale
		for u in r.members:
			if u.get("hp") != null:
				u.hp *= tough
	for u in r.members:
		var sp: Vector3 = terrain.free_spot(r.slot(u.slot_index))
		u.position = sp
		if r.info.has("guns"):
			u.crew.position = sp
			u.crew.rotation.y = atan2(-fwd.x, -fwd.z)
			u.crew.want_yaw = u.crew.rotation.y
		u.facing = fwd
		if side == 1:
			battle.enemies.append(u)
		elif yours:
			battle.soldiers.append(u)
		else:
			battle.allies.append(u)
		battle.add_child(u)
	r.centroid = r.pos
	return r


func _make_unit(side: int, kind: String):
	match kind:
		"musket", "pike", "bow", "xbow":
			return FieldSoldier.make(battle, self, kind, side)
		"cav":
			return Rider.make(battle, self, side, "horse")
		"liz_raptor":
			return Rider.make(battle, self, side, "raptor")
		"gun":
			return GunPost.make(battle, self, side, Vector3.ZERO, 0.0 if side == 0 else PI)
		"catapult":
			return GunPost.make(battle, self, side, Vector3.ZERO, 0.0 if side == 0 else PI, "catapult")
		"knight", "lancer", "dragoon":
			return Rider.make(battle, self, side, "horse", kind)
		"sword", "longbow":
			return FieldSoldier.make(battle, self, kind, side)
		"liz_warrior":
			return FieldLizard.make(battle, self, "warrior")
		"liz_skirm":
			return FieldLizard.make(battle, self, "skirm")
		"liz_brute":
			return FieldLizard.make(battle, self, "brute")
	return FieldSoldier.make(battle, self, "musket", side)


# ---------------------------------------------------------------- queries for the men

func side_of(u) -> int:
	var s = u.get("side")
	if s != null:
		return int(s)
	return 1 if u.is_in_group("enemies") else 0


## The nearest living foe of `u` within `r` metres (you count, for the enemy).
func nearest_foe(u, r: float) -> Node3D:
	var p: Vector3 = u.global_position
	if side_of(u) == 0:
		return battle.nearest_enemy(p, r)
	var best: Node3D = null
	if r <= 16.0:
		best = battle._nearest_in(battle._grid_s, p, r)
	else:
		best = battle._nearest_any(battle._grid_s, p, r)
	var pl = battle.player
	if pl.alive:
		var dp: float = p.distance_to(pl.global_position)
		if dp <= r and (best == null or dp < p.distance_to(best.global_position)):
			best = pl
	return best


func off_field(p: Vector3) -> bool:
	return absf(p.x) > Terrain.HALF - 2.0 or absf(p.z) > Terrain.HALF - 2.0


func unit_died(u) -> void:
	_drop(u)
	if side_of(u) == 1:
		battle.slain += 1
	if u.reg != null:
		_deaths[u.reg] = int(_deaths.get(u.reg, 0)) + 1


## A man who ran off the edge of the field: gone from the battle.
func unit_fled(u) -> void:
	if u.get_meta("fled", false):
		return
	u.set_meta("fled", true)
	u.alive = false
	_drop(u)
	u.remove_from_group("enemies")
	u.remove_from_group("friendlies")
	if (campaign or prologue) and side_of(u) == 0 and u.get("record") != null:
		# One of your own men, off the field: he comes back after the battle.
		u.down_status = "fit"
		u.visible = false
		u.set_physics_process(false)
		u.set_process(false)
		u.position.y -= 200.0
		return
	u.queue_free()


func _drop(u) -> void:
	battle.enemies.erase(u)
	battle.soldiers.erase(u)
	battle.allies.erase(u)


# ---------------------------------------------------------------- the loop

func _physics_process(delta: float) -> void:
	if battle == null or regs.is_empty():
		return
	clock += delta
	# Regiments think in turn: a few each physics frame.
	var n := regs.size()
	var per := maxi(1, ceili(n / 5.0))
	for k in per:
		var r = regs[_tick_i % n]
		_tick_i += 1
		if not r.gone():
			r.tick(_reg_dt(r))
	_morale_t += delta
	if _morale_t >= 0.5:
		_morale(_morale_t)
		_morale_t = 0.0
	_ai_t += delta
	if _ai_t >= 1.0:
		_ai_t = 0.0
		for s in ai_sides:
			_ai(s)
	_fire_guns()
	_check_t += delta
	if _check_t > 1.0:
		_check_t = 0.0
		_check_end()


var _last_tick := {}


func _reg_dt(r) -> float:
	var last: float = _last_tick.get(r, clock - 0.1)
	_last_tick[r] = clock
	return clampf(clock - last, 0.0, 0.5)


func _morale(dt: float) -> void:
	# Who's near whom (regiment centres), once for everyone.
	for r in regs:
		if r.gone():
			continue
		r.nearest_foe_d = INF
		r.nearest_foe_reg = null
		for o in regs:
			if o.side == r.side or o.gone():
				continue
			var d: float = r.centroid.distance_to(o.centroid) - (o.width() + r.width()) * 0.35
			if d < r.nearest_foe_d:
				r.nearest_foe_d = d
				r.nearest_foe_reg = o
		r.foes_close = r.nearest_foe_d < 32.0
	for r in regs:
		if r.gone():
			continue
		var losses := int(_deaths.get(r, 0))
		_deaths[r] = 0
		# In a melee it's losing (more of them than us near), it gives.
		if r.engaged():
			var them := 0
			for o in regs:
				if o.side != r.side and not o.broken() and o.centroid.distance_to(r.centroid) < 25.0:
					them += o.members.size() * (2 if o.is_cav() or o.kind == "liz_brute" else 1)
			var ratio := float(them) / maxf(1.0, r.members.size())
			if ratio > 1.2:
				r.morale -= (ratio - 1.0) * 2.5 * dt
			_flank_check(r)
		r.morale_tick(dt, losses)


## Attacked from the side or the back: a heavy blow to its nerve, once per
## attacker.
func _flank_check(r) -> void:
	if r.square:
		return # (a square has no flank or rear)
	for o in regs:
		if o.side == r.side or o.broken() or not o.engaged():
			continue
		var to: Vector3 = o.centroid - r.centroid
		to.y = 0.0
		if to.length() > 22.0:
			continue
		var dot: float = to.normalized().dot(r.forward)
		if dot < -0.35:
			if r.shock("rear%d" % o.id, 25.0):
				alert(r, Lang.t("%s %s attacked from behind!") % [r.title, r.verb("is", "are")], r.side == 0)
		elif dot < 0.35 and not r.is_cav():
			r.shock("flank%d" % o.id, 14.0)


func on_regiment_broke(r, was: String) -> void:
	if _broke_told.has(r):
		return
	_broke_told[r] = true
	if was in ["routing", "shattered"]:
		return
	alert(r, Lang.t("%s %s and %s!") % [r.title, r.verb("breaks", "break"), r.verb("runs", "run")], r.side == 0)
	# Friends nearby see it go.
	for o in regs:
		if o != r and o.side == r.side and not o.broken() and o.centroid.distance_to(r.centroid) < 45.0:
			o.shock("broke%d" % r.id, 10.0)


func alert(r, text: String, important: bool) -> void:
	# The big message in the middle only for what matters to you.
	if battle.hud != null and (important or r == null or r.side == 0 or r.broken()):
		battle.hud.show_message(text, 2.2)
	if ui != null:
		ui.alert(r, text, important)


func cav_regroup(r) -> void:
	r.set_meta("regroup", clock)


## Batteries: each gun lays on a man of its target regiment and fires when
## loaded, laid and with a clear line.
func _fire_guns() -> void:
	var nest = battle.nest
	for r in regs:
		if not r.is_gun() or r.broken():
			continue
		if nest != null and r.side == 0 and not nest.gate_open and (r.fire_target == null or r.fire_target.broken() or nest.inside(r.fire_target.centroid)):
			# Nothing to shoot that isn't behind the stakes: batter the gate.
			var gp: Vector3 = nest.gate_point() + Vector3.UP * 1.2
			if r.fire_at_will and gp.distance_to(r.centroid) < r.range_m():
				for g in r.members:
					if g.alive and not g.crew.silent and not g.manned:
						g.try_fire(gp)
			continue
		if not r.may_fire():
			continue
		for g in r.members:
			if not g.alive or g.crew.silent or g.manned:
				continue
			var t: Node3D = r.shot_at(g)
			if t == null:
				continue
			var aim := t.global_position + Vector3.UP * 0.9
			var tv = t.get("velocity")
			if tv != null:
				aim += (tv as Vector3) * (g.global_position.distance_to(aim) / 170.0)
			g.try_fire(aim)


# ---------------------------------------------------------------- the enemy's general

func _ai(side: int) -> void:
	for r in regs:
		if r.side != side or r.broken() or r.gone():
			continue
		if side == 0 and not test_mode and (r.player_led or (not r.allied and not bool(cfg.get("auto", false)))):
			continue # (yours are yours to command)
		if r.hold_fast:
			continue # (a nest's garrison, behind its stakes)
		# Foot with horse bearing down on it forms square, and opens out again
		# once they've gone.
		if r.can_square() and not r.engaged():
			var horse := _horse_near(r, 40.0 if not r.square else 60.0)
			if horse and not r.square:
				r.form_square(true)
				continue
			elif r.square and not horse:
				r.form_square(false)
			elif r.square:
				continue
		if r.order == "charge" and r.target != null and not r.target.broken():
			continue
		if r.order == "move" and not r.path.is_empty() and clock - r.order_t < 35.0:
			continue
		var best = _pick_target(r)
		if best == null:
			if r.order != "hold":
				r.order_hold()
			continue
		if r.is_cav():
			_ai_cav(r, best)
			continue
		if r.is_gun():
			r.fire_target = best if best.centroid.distance_to(r.centroid) < r.range_m() else r.fire_target
			continue
		# Humans hold their ground a while first; lizards just come.
		if r.kind in HUMAN_KINDS and clock < 8.0 and r.nearest_foe_d > 80.0:
			continue
		if r.order != "attack" or r.target != best:
			r.order_attack(best)


## Enemy horse (unbroken) within `d` metres of this regiment?
func _horse_near(r, d: float) -> bool:
	for o in regs:
		if o.side != r.side and o.is_cav() and not o.broken() and o.centroid.distance_to(r.centroid) < d:
			return true
	return false


func _pick_target(r):
	var best = null
	var bs := INF
	for o in regs:
		if o.side == r.side or o.broken():
			continue
		var d: float = o.centroid.distance_to(r.centroid)
		var s := d
		if r.is_cav():
			if o.is_ranged() or o.is_gun():
				s -= 60.0
			if o.kind == "pike":
				s += 120.0
			if o.engaged():
				s -= 30.0 # into the back of a melee
			if o.square:
				s += 150.0 # (horse won't ride at a square)
		elif r.kind == "pike" and o.is_cav() and d < 70.0:
			s -= 50.0
		var nest = battle.nest
		if nest != null and r.side == 0 and not nest.defender_regs.is_empty() and nest.inside(o.centroid):
			s += -30.0 if o.covered else 300.0 # (a garrison holding: in by the gate or a gap)
		if s < bs:
			bs = s
			best = o
	return best


func _ai_cav(r, t) -> void:
	var since: float = clock - float(r.get_meta("regroup", -99.0))
	if since < 6.0:
		return
	var d: float = t.centroid.distance_to(r.centroid)
	if d > 70.0 and not r.has_meta("flanked"):
		# Round the flank: to a point beside the target, then in.
		r.set_meta("flanked", true)
		var side_dir: Vector3 = t.forward.cross(Vector3.UP).normalized() * _flank_side
		_flank_side = -_flank_side
		var p: Vector3 = t.centroid + side_dir * 50.0 - t.forward * 10.0
		p.x = clampf(p.x, -Terrain.HALF + 12.0, Terrain.HALF - 12.0)
		p.z = clampf(p.z, -Terrain.HALF + 12.0, Terrain.HALF - 12.0)
		r.order_move(p, (t.centroid - p).normalized(), true)
		return
	if r.order != "attack" or r.target != t:
		r.order_attack(t)


# ---------------------------------------------------------------- your orders (the HUD buttons)

## FOLLOW / HOLD / CHARGE / AT WILL / VOLLEY act on your own company.
func player_order(what: String) -> void:
	var r = player_reg
	if r == null or r.gone():
		return
	match what:
		"follow":
			r.order_hold()
			r.order = "follow"
			battle.hud.show_message(Lang.t("Company — follow me!"), 1.5)
		"hold":
			r.order_hold()
			r.pos = Vector3(battle.player.global_position.x, 0, battle.player.global_position.z)
			r.forward = battle._player_forward()
			battle.hud.show_message(Lang.t("Company — halt! Hold here!"), 1.5)
		"charge":
			r.order_charge(r.nearest_foe_reg)
			battle.hud.show_message(Lang.t("CHARGE! At them, lads!"), 1.5)
		"fire":
			r.fire_at_will = not r.fire_at_will
			battle.hud.show_message(Lang.t("Fire at will!") if r.fire_at_will else Lang.t("Hold your fire... wait for the order!"), 1.5)
		"volley":
			r.fire_target = r.fire_target if r.fire_target != null else r.nearest_foe_reg
			r.order_volley()
			battle.hud.show_message(Lang.t("PRESENT... FIRE!"), 1.0)


func on_player_down() -> void:
	if story != null:
		story.player_down()
		return
	if player_reg != null:
		player_reg.player_led = false
		if player_reg.order == "follow":
			player_reg.order_hold()
	alert(player_reg, Lang.t("You are down! Command from above."), true)
	if ui != null:
		ui.open(true)


# ---------------------------------------------------------------- the end

var _report_t := 0.0


func _check_end() -> void:
	if test_mode:
		_report_t += 1.0
		if int(_report_t) % 10 == 0 or over != "" or _report_t < 4.0:
			var parts: PackedStringArray = []
			for r in regs:
				parts.append("%s%d:%s/%d %s %d%%m %s" % ["Y" if r.side == 0 else "T", r.id, r.kind, r.members.size(), r.state.substr(0, 4) if not r.square else Lang.t("SQUA"), int(r.morale), r.order.substr(0, 4)])
			print("FIELD t%d fps%d %s | %s" % [int(clock), Engine.get_frames_per_second(), status_line(), " ".join(parts)])
		if over != "" and _report_t > 3.0:
			print("FIELD END ", over, " at ", int(clock), " shots ", battle.projectiles.stats)
			get_tree().quit()
		if clock > (600.0 if prologue else 300.0):
			print("FIELD END timeout")
			get_tree().quit()
	if over != "" or prologue:
		return
	var mine := regs.filter(func(r): return r.side == 0 and not r.broken())
	var theirs := regs.filter(func(r): return r.side == 1 and not r.broken())
	if theirs.is_empty() and (battle.nest == null or battle.nest.done()):
		over = "won"
		battle.hud.show_message(Lang.t("VICTORY! The field is ours.") if campaign else Lang.t("VICTORY! Their army is running."), 9999.0)
		_finish(true)
	elif mine.is_empty():
		over = "lost"
		battle.hud.show_message(Lang.t("DEFEAT. The company is broken and scattered.") if campaign else Lang.t("DEFEAT. Your army is broken."), 9999.0)
		_finish(false)


## The end: in the campaign, the battle is reported to the company (men,
## kills, the wagon, pay) and CONTINUE goes on to the aftermath.
func _finish(won: bool) -> void:
	if Company.active:
		battle.victory = won
		battle._end_battle(won)
	else:
		battle.game_state = "won" if won else "lost"
		battle.hud.show_restart()


## A lord's horse is his household: named for him (his army's, or the one
## you fight beside).
func _name_households(nb: Dictionary) -> void:
	var al := World.lord(int(nb.get("allies", {}).get("lord", -1)))
	if not al.is_empty():
		for r in regs:
			if r.allied and r.kind == "cav":
				r.title = Lang.t("%s's household") % World.lord_short(al)
				break


func _name_enemy_household(nb: Dictionary) -> void:
	var l := World.lord(int(nb.get("lord", -1)))
	if l.is_empty():
		return
	for r in regs:
		if r.side == 1 and r.kind == "cav":
			r.title = Lang.t("%s's household") % World.lord_short(l)
			break


## How many of the nation's men who fought beside you are still standing.
func allies_left() -> int:
	var n := 0
	for r in regs:
		if r.allied:
			n += r.members.size()
	return n


func status_line() -> String:
	var a := 0
	var b := 0
	var ra := 0
	var rb := 0
	for r in regs:
		if r.side == 0:
			a += r.members.size()
			if not r.broken():
				ra += 1
		else:
			b += r.members.size()
			if not r.broken():
				rb += 1
	var where: String = Lang.t(Terrain.MAP_NAMES.get(terrain.kind, ""))
	if prologue:
		where = Lang.t("RETREAT") if story != null and story.phase == "retreat" else Lore.BEACH
	return Lang.t("%s   Yours %d (%d units)   Theirs %d (%d units)") % [where, a, ra, b, rb]
