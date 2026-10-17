extends Node
## The game's languages, registered as the `Lang` autoload: English (the
## source), Brazilian Portuguese and Spanish. The flags on the main menu
## pick one (remembered in Settings).
##
## Every piece of text the player reads goes through Lang.t() where it's
## written in the code: the English text is the key, and the tables in
## data/i18n/<lang>.json give the translation (missing ones stay English).
## A formatted string is translated before it's formatted, so the table
## holds the template: Lang.t("%d men went hungry.") % n. Proper names
## (people, places, the nations) aren't translated.
##
## tools/i18n.py finds the text in the scripts (and wraps new text in
## Lang.t), and lists what each table is missing.

const LANGS := ["en", "pt_BR", "es"]
const NAMES := {"en": "English", "pt_BR": "Português (Brasil)", "es": "Español"}

var current := "en"
var _table := {}


func _ready() -> void:
	var l := Settings.language
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			l = a.trim_prefix("--lang=") # (for testing: the setting itself is unchanged)
	set_language(l)


func set_language(l: String) -> void:
	current = l if l in LANGS else "en"
	_table = {}
	if current != "en":
		var path := "res://data/i18n/%s.json" % current
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(d) == TYPE_DICTIONARY:
				_table = d
	TranslationServer.set_locale(current)
	Settings.language = current


## The text in the current language (the English if there's no translation).
func t(s: String) -> String:
	if _table.is_empty():
		return s
	return String(_table.get(s, s))
