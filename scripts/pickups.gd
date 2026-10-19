extends Node3D
## Things lying on the battlefield that you can pick up (the pickable
## overhaul): whatever a man (or a lizard) was carrying when he fell, his
## weapon and what was left of his ammunition, and the gun tools and shot
## (gun_crew.gd drops a dead crew's rammer and linstock).
##
##   drop(at, item, n)   lay something on the ground
##   drop_from(unit)     what a unit carried, when it falls (unit.gd _die)
##   nearest(p, r)       the closest thing within r metres, or {}
##   take(d)             pick it up: player.gd takes what it can use, and
##                       weapons go on the wagon (Company items)
##
## Items are Company.ITEMS ids (weapons: musket, pike, war_bow, saber...) or
## these: cartridges, arrows, bolts, javelins (ammunition), rammer, linstock
## (gun tools), roundshot, canister (a gun's round, carried one at a time).

const Props := preload("res://scripts/props.gd")
const MAX := 140 # (the oldest go when there are more)

const EXTRA_NAMES := {
	"cartridges": "Cartridges", "arrows": "Arrows", "bolts": "Bolts", "javelins": "Javelins",
	"rammer": "Rammer and sponge", "linstock": "Linstock", "roundshot": "Round shot", "canister": "Canister",
}

var battle
var items: Array = [] # {"node", "item", "n", "pos"}


static func item_name(id: String) -> String:
	if EXTRA_NAMES.has(id):
		return Lang.t(EXTRA_NAMES[id])
	return Company.item_name(id) if Company.ITEMS.has(id) else id


func drop(at: Vector3, item: String, n := 1) -> void:
	if n <= 0 or item == "" or item == "none":
		return
	var g: float = battle.ground_y(at) if battle.has_method("ground_y") else at.y
	var p := Vector3(at.x + randf_range(-0.5, 0.5), g, at.z + randf_range(-0.5, 0.5))
	var node := _mesh(item)
	node.position = p
	node.rotation.y = randf() * TAU
	add_child(node)
	items.append({"node": node, "item": item, "n": n, "pos": p})
	if items.size() > MAX:
		var old: Dictionary = items.pop_front()
		(old["node"] as Node3D).queue_free()


## What a fallen unit leaves: its weapon and its ammunition.
func drop_from(u: Node3D) -> void:
	var at := u.global_position
	if u.get("rig_kind") == "lizard":
		var v := String(u.get("variant")) if u.get("variant") != null else "warrior"
		match v:
			"skirm":
				drop(at, "javelins", randi_range(1, 3))
			"brute":
				drop(at, "cleaver", 1)
			_:
				if randf() < 0.6:
					drop(at, "cleaver", 1)
				if randf() < 0.3:
					drop(at, "lizard_shield", 1)
		return
	if u.get("rig_kind") == "gun":
		return
	var rig = u.get("rig")
	var g: Dictionary = rig.gear if rig != null and rig.get("gear") is Dictionary else {}
	var primary := String(g.get("primary", ""))
	if Company.ITEMS.has(primary):
		drop(at, primary, 1)
	if Company.ITEMS.has(String(g.get("sword", ""))):
		drop(at, String(g["sword"]), 1)
	if Company.ITEMS.has(String(g.get("pistol", ""))):
		drop(at, String(g["pistol"]), 1)
	var missile := String(u.get("missile")) if u.get("missile") != null else "ball"
	var ammo: int = int(u.get("ammo")) if u.get("ammo") != null else -1
	if ammo < 0:
		ammo = randi_range(4, 12)
	match missile:
		"ball":
			if primary != "" and not primary in ["pike", "spear", "war_spear", "lance", "none"]:
				drop(at, "cartridges", mini(ammo, 20))
		"arrow":
			drop(at, "arrows", mini(ammo, 20))
		"bolt":
			drop(at, "bolts", mini(ammo, 16))


func nearest(p: Vector3, r := 2.2) -> Dictionary:
	var best := {}
	var bd := r
	for d in items:
		var q: Vector3 = d["pos"]
		var dd := Vector2(q.x - p.x, q.z - p.z).length()
		if dd < bd:
			bd = dd
			best = d
	return best


func remove(d: Dictionary) -> void:
	items.erase(d)
	if is_instance_valid(d["node"]):
		(d["node"] as Node3D).queue_free()


# ---------------------------------------------------------------- looks

func _mesh(item: String) -> Node3D:
	var n := Node3D.new()
	var wood := Props.WOOD
	var iron := Color(0.5, 0.5, 0.52)
	match item:
		"musket", "worn_musket", "rifle", "carbine":
			Props._box(n, Vector3(0.08, 0.06, 1.5), wood, Vector3(0, 0.05, 0))
			Props._box(n, Vector3(0.03, 0.03, 0.9), iron, Vector3(0, 0.09, -0.35))
		"pike", "spear", "war_spear", "lance":
			Props._box(n, Vector3(0.05, 0.05, 3.0 if item == "pike" else 2.2), wood, Vector3(0, 0.04, 0))
			Props._box(n, Vector3(0.07, 0.03, 0.3), iron, Vector3(0, 0.05, -1.55 if item == "pike" else -1.15))
		"javelins":
			for k in 2:
				Props._box(n, Vector3(0.035, 0.035, 1.5), wood, Vector3(k * 0.12, 0.03, k * 0.1))
		"war_bow", "hunting_bow":
			Props._box(n, Vector3(0.05, 0.03, 1.5), Color(0.45, 0.3, 0.15), Vector3(0, 0.03, 0))
		"crossbow", "dwarf_crossbow":
			Props._box(n, Vector3(0.1, 0.08, 0.8), wood, Vector3(0, 0.05, 0))
			Props._box(n, Vector3(0.7, 0.04, 0.05), iron, Vector3(0, 0.08, -0.35))
		"saber", "cutlass", "arming_sword", "cleaver":
			Props._box(n, Vector3(0.05, 0.02, 0.85), iron.lightened(0.2), Vector3(0, 0.03, 0))
			Props._box(n, Vector3(0.2, 0.04, 0.05), Color(0.6, 0.5, 0.2), Vector3(0, 0.04, 0.38))
		"pistol":
			Props._box(n, Vector3(0.06, 0.06, 0.4), wood, Vector3(0, 0.04, 0))
		"lizard_shield", "heater_shield":
			Props._box(n, Vector3(0.6, 0.05, 0.75), Color(0.4, 0.32, 0.2), Vector3(0, 0.03, 0))
		"cartridges":
			Props._box(n, Vector3(0.28, 0.12, 0.2), Color(0.12, 0.1, 0.08), Vector3(0, 0.06, 0))
			Props._box(n, Vector3(0.3, 0.03, 0.22), Color(0.85, 0.82, 0.7), Vector3(0, 0.13, 0))
		"arrows", "bolts":
			for k in 4:
				Props._box(n, Vector3(0.02, 0.02, 0.8 if item == "arrows" else 0.45), wood, Vector3(k * 0.05 - 0.08, 0.02, 0))
		"rammer":
			Props._box(n, Vector3(0.05, 0.05, 2.4), wood, Vector3(0, 0.04, 0))
			Props._box(n, Vector3(0.14, 0.14, 0.3), Color(0.15, 0.13, 0.1), Vector3(0, 0.07, -1.2))
		"linstock":
			Props._box(n, Vector3(0.04, 0.04, 1.2), wood, Vector3(0, 0.03, 0))
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.5, 0.2)
			glow.omni_range = 1.2
			glow.light_energy = 0.6
			glow.position = Vector3(0, 0.15, -0.6)
			n.add_child(glow)
		"roundshot":
			Props._box(n, Vector3(0.18, 0.18, 0.18), Color(0.12, 0.12, 0.13), Vector3(0, 0.09, 0))
		"canister":
			Props._box(n, Vector3(0.2, 0.26, 0.2), Color(0.5, 0.5, 0.48), Vector3(0, 0.13, 0))
		_:
			Props._box(n, Vector3(0.3, 0.1, 0.3), Color(0.4, 0.33, 0.24), Vector3(0, 0.05, 0))
	return n
