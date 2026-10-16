extends RefCounted
## The land's languages, and how much of them your company has picked up.
##
## You are castaways: nobody here speaks Calderan. Each people has its own
## tongue, generated from the campaign's seed (so every campaign the words are
## new): Aurest is soft and flowing, Vellish clipped and hard, Dwarvish all
## stops and gutturals. The lizards don't talk to you at all.
##
## What you know lives in Company.tongues[lang] = {"fluency": 0..100,
## "words": {concept: true}}. A word is learned by hearing it in context (a
## man pointing at the bread as he says it) - the conversation does that, see
## folk.gd. Fluency grows with every exchange and every new word, faster with
## your Tongues skill, and decides how often you're understood.
##
## Their speech is shown word by word: words you know appear in English (in
## gold), the rest as you hear them. A first conversation is mostly noise; by
## the tenth visit to a town you follow most of it.

## Things people talk about. A line is an Array of these.
const CONCEPTS := [
	"hello", "goodbye", "yes", "no", "not", "you", "i", "we", "they", "friend", "stranger",
	"food", "bread", "water", "drink", "coin", "work", "trade", "gift", "thanks", "sorry",
	"good", "bad", "danger", "lizard", "fight", "kill", "taken", "fear", "help", "join",
	"go", "come", "stay", "home", "family", "brother", "sister", "son", "daughter", "wife", "husband",
	"god", "pray", "weapon", "thunder", "fire", "where", "who", "why", "name", "many", "few",
	"village", "town", "road", "river", "sea", "forest", "mountain", "nest", "lord", "soldier",
	"sick", "hungry", "debt", "free", "far", "near", "day", "night", "boat", "fish", "farm",
	"want", "have", "give", "know", "see", "maybe", "tomorrow", "brave", "strange", "listen",
]

## How each people's words sound.
const PHON := {
	"aurest": {"on": ["", "b", "d", "l", "m", "n", "r", "s", "t", "v", "ch", "f", "j", "p"],
		"v": ["a", "e", "i", "o", "ou", "ai", "eu", "ie"], "coda": ["", "", "", "n", "r", "s", "l"], "syl": [1, 2, 2, 3]},
	"vell": {"on": ["b", "d", "g", "h", "k", "r", "s", "st", "t", "v", "w", "br", "dr", "kr", "sk"],
		"v": ["a", "e", "i", "o", "u", "aa", "ei", "ö"], "coda": ["", "k", "n", "r", "t", "rd", "nd", "st", "ck"], "syl": [1, 1, 2, 2]},
	"dwarves": {"on": ["b", "d", "g", "k", "kh", "z", "th", "gr", "dr", "m", "r"],
		"v": ["a", "u", "o", "ü", "aa", "i"], "coda": ["k", "z", "r", "m", "n", "g", "rk", "d"], "syl": [1, 2, 2]},
}
const LANG_NAMES := {"aurest": "Aurestine", "vell": "Vellish", "dwarves": "Dwarvish"}


## The tongue spoken in a faction's lands ("" for the lizards).
static func lang_of(faction: String) -> String:
	return faction if PHON.has(faction) else ""


## Their word for a concept: the same all campaign, new every campaign.
static func word(lang: String, concept: String) -> String:
	var spec: Dictionary = PHON.get(lang, PHON["aurest"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([World.seed, lang, concept])
	var syl: Array = spec["syl"]
	var n: int = syl[rng.randi() % syl.size()]
	if concept in ["yes", "no", "i", "you", "we", "not"]:
		n = 1 # the little words are short in every language
	var w := ""
	for k in n:
		w += String(spec["on"][rng.randi() % spec["on"].size()])
		w += String(spec["v"][rng.randi() % spec["v"].size()])
		if k == n - 1 or rng.randf() < 0.3:
			w += String(spec["coda"][rng.randi() % spec["coda"].size()])
	if w.length() < 2:
		w += String(spec["v"][rng.randi() % spec["v"].size()])
	return w


static func _rec(lang: String) -> Dictionary:
	if not Company.tongues.has(lang):
		Company.tongues[lang] = {"fluency": 0.0, "words": {}}
	return Company.tongues[lang]


static func knows(lang: String, concept: String) -> bool:
	return lang != "" and _rec(lang)["words"].has(concept)


static func words_known(lang: String) -> int:
	return _rec(lang)["words"].size() if lang != "" else 0


## 0..100.
static func fluency(lang: String) -> float:
	return float(_rec(lang)["fluency"]) if lang != "" else 0.0


## Learn a word. Returns true if it was new.
static func learn(lang: String, concept: String) -> bool:
	if lang == "" or knows(lang, concept):
		return false
	_rec(lang)["words"][concept] = true
	grow(lang, 0.6)
	return true


## Practice: every exchange, understood or not, teaches a little. Slower as
## you get better; faster with your Tongues skill.
static func grow(lang: String, amount: float) -> void:
	if lang == "":
		return
	var r := _rec(lang)
	var f := float(r["fluency"])
	var rate := (1.0 + 0.15 * Company.Officer.skill("tongues")) * (1.0 - f / 125.0)
	r["fluency"] = minf(100.0, f + amount * rate)


static func level(lang: String) -> String:
	var f := fluency(lang)
	if f < 10.0:
		return "signs only"
	if f < 30.0:
		return "a few words"
	if f < 55.0:
		return "broken speech"
	if f < 80.0:
		return "halting talk"
	return "fluent"


## Their line as you hear it: known words in English, the rest as sounds.
static func render(lang: String, line: Array) -> String:
	var bits: PackedStringArray = []
	for c in line:
		var concept := String(c)
		if knows(lang, concept):
			bits.append("[color=#f2cc73]%s[/color]" % concept)
		else:
			bits.append("[color=#9aa3b5][i]%s[/i][/color]" % word(lang, concept))
	var s := " ".join(bits)
	return "“" + s + "”" if not bits.is_empty() else ""


## How much of a line you followed, 0..1.
static func grasp(lang: String, line: Array) -> float:
	if line.is_empty():
		return 1.0
	var k := 0
	for c in line:
		if knows(lang, String(c)):
			k += 1
	return float(k) / line.size()


## Hearing a line: you may pick up one of its unknown words (when they point
## or repeat it). `chance` 0..1. Returns the concept learned, or "".
static func listen(lang: String, line: Array, chance: float) -> String:
	grow(lang, 0.2)
	var unknown: Array = []
	for c in line:
		if not knows(lang, String(c)):
			unknown.append(String(c))
	if unknown.is_empty() or randf() >= chance:
		return ""
	var c: String = unknown.pick_random()
	learn(lang, c)
	return c
