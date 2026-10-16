extends RefCounted
## Names for the story, all in one place. These are PLACEHOLDERS: change
## them here and the cutscene, the battle, the camp and the saves follow.

const NATION := "Kingdom of Calder" # who you are; not one of the land's factions
const NATION_ADJ := "Calderan"
const REGIMENT := "the 14th Calderan Foot"
const SHIP := "Steadfast" # the ship that wrecks
const LAND := "the Veiled Coast" # the unknown land (the whole map comes later)
const BEACH := "Wreck Beach" # where the prologue is fought
const COMMANDER := "Major Aldous Harrow"
const COMMANDER_SHORT := "Major Harrow"

## What the lizards carried off from the wreck: the first great objective.
const STASH := {"muskets": 60, "ammo": 3000, "cannons": 2, "rum": 200}

## The land's powers (placeholders too). Colours are their banners on the map.
const FACTIONS := {
	"aurest": {"name": "Kingdom of Aurest", "short": "Aurest", "color": Color(0.75, 0.2, 0.18),
		"syll": ["Au", "Ver", "Mar", "Lis", "Bel", "Cor", "Sau", "Tre", "Val", "Ro", "Mon", "Ser"],
		"end": ["ignac", "eaux", "ond", "elle", "ac", "ville", "mont", "tier", "ais", "on"]},
	"vell": {"name": "Vellish Marches", "short": "Vell", "color": Color(0.2, 0.42, 0.78),
		"syll": ["Hal", "Dro", "Wen", "Ost", "Kel", "Bra", "Ul", "Rad", "Gest", "Hel", "Sto", "Fen"],
		"end": ["burg", "stad", "wick", "holm", "dorf", "mark", "by", "feld", "haven", "rode"]},
	"dwarves": {"name": "Dwarves of the Greyspine", "short": "Dwarves", "color": Color(0.85, 0.65, 0.2),
		"syll": ["Kaz", "Dur", "Bar", "Thor", "Gar", "Mor", "Khel", "Dun", "Grim", "Bal"],
		"end": ["-dun", "-grat", "zul", "agar", "-khaz", "dum", "ok", "-baraz"]},
	"lizards": {"name": "The Horde", "short": "Lizards", "color": Color(0.35, 0.6, 0.2),
		"syll": ["Ssk", "Kra", "Thss", "Ghr", "Zek", "Hiss", "Vrr", "Ka"],
		"end": ["'ath", "'ksha", "'tor", "ssa", "'ruk", "'zil"]},
}
