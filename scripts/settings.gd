extends Node
## Global settings, registered as the `Settings` autoload in project.godot.
## The main menu writes these; the battle reads them. Also which save slot
## is in use (each slot is a folder with its own campaign and world).

const SLOTS := 4
const PREFS := "user://settings.json"

## Start battles in third person (over the shoulder) instead of first.
var third_person := false

## Stress test: 50 musketeers against one wave of 200 lizardmen, with an FPS
## counter, to see what your phone can handle.
var stress := false

## A skirmish with a mixed company (muskets, spears, bows, crossbows) outside
## the campaign, from the main menu.
var mixed := false

## The weapon range: you alone with every weapon (musket, bayonet, pistol,
## sabre, bow, crossbow, grenades), lizards sent on demand, no dying.
var playground := false

## The save slot in use (1..SLOTS); remembered for CONTINUE.
var slot := 1

## Graphics quality (see look.gd): "low" (no grass far out, no real shadows),
## "medium" (grass, soft blob shadows under everyone) or "high" (real sun
## shadows from men, trees and houses, a little bloom).
var graphics := "medium"
const GRAPHICS := ["low", "medium", "high"]


func _ready() -> void:
	# The game's look for every screen (see ui.gd).
	get_tree().root.theme = preload("res://scripts/ui.gd").theme()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PREFS)) if FileAccess.file_exists(PREFS) else null
	if typeof(data) == TYPE_DICTIONARY:
		slot = clampi(int(data.get("slot", 1)), 1, SLOTS)
		third_person = bool(data.get("third_person", false))
		graphics = String(data.get("graphics", "medium"))
		if not graphics in GRAPHICS:
			graphics = "medium"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gfxq="):
			graphics = a.substr(7)
	_migrate_old_save()


func slot_dir(s := -1) -> String:
	return "user://slot%d" % (slot if s < 0 else s)


func use_slot(s: int) -> void:
	slot = s
	DirAccess.make_dir_recursive_absolute(slot_dir())
	save_prefs()


func save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"slot": slot, "third_person": third_person, "graphics": graphics}))


## Saves from before slots existed move into slot 1.
func _migrate_old_save() -> void:
	for name in ["campaign.json", "world.json"]:
		var old: String = "user://" + name
		if FileAccess.file_exists(old) and not FileAccess.file_exists(slot_dir(1) + "/" + name):
			DirAccess.make_dir_recursive_absolute(slot_dir(1))
			DirAccess.rename_absolute(ProjectSettings.globalize_path(old),
				ProjectSettings.globalize_path(slot_dir(1) + "/" + name))


## A one-line summary of a slot for the menu, or "" if it's empty.
func slot_summary(s: int) -> Dictionary:
	var path := slot_dir(s) + "/campaign.json"
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var when := Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path)).replace("T", " ").substr(0, 16)
	var men: Array = data.get("roster", [])
	var seed := ""
	var wpath := slot_dir(s) + "/world.json"
	if FileAccess.file_exists(wpath):
		var w = JSON.parse_string(FileAccess.get_file_as_string(wpath))
		if typeof(w) == TYPE_DICTIONARY:
			seed = str(int(w.get("seed", 0)))
	return {"day": int(data.get("day", 1)), "men": men.size(), "money": int(data.get("money", 0)),
		"battles": int(data.get("battles", 0)), "prologue": bool(data.get("prologue", false)),
		"when": when, "seed": seed}


func delete_slot(s: int) -> void:
	for name in ["campaign.json", "world.json"]:
		var p: String = slot_dir(s) + "/" + name
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
