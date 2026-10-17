extends RefCounted
## Your regiment's colours: the coat your men wear and the flag they carry,
## chosen on the new-campaign screen (creation.gd) and kept with the
## campaign (Company.colours). Everything that draws your men or your flag
## asks here: the men's rigs (rig3d.gd), the officer's coat, the saddle
## cloths, the colours in the cutscene and on the menu's camp, the map
## marker.
##
## A flag is a field colour, a pattern and a second colour (the charge):
## plain, cross (offset to the hoist, the old Calderan way), centre cross,
## saltire, quarters, upright stripes, bands, border.

const COATS := [
	["Calder blue", Color(0.16, 0.24, 0.55)], ["Scarlet", Color(0.62, 0.12, 0.1)], ["Rifle green", Color(0.15, 0.32, 0.18)],
	["Grey", Color(0.43, 0.45, 0.48)], ["White", Color(0.84, 0.83, 0.78)], ["Buff", Color(0.7, 0.6, 0.38)],
	["Black", Color(0.12, 0.12, 0.13)], ["Brown", Color(0.38, 0.25, 0.15)], ["Purple", Color(0.33, 0.15, 0.4)],
]
const FLAG_COLOURS := [
	Color(0.13, 0.2, 0.45), Color(0.9, 0.88, 0.8), Color(0.66, 0.1, 0.1), Color(0.85, 0.66, 0.15),
	Color(0.12, 0.38, 0.18), Color(0.1, 0.1, 0.11), Color(0.42, 0.62, 0.84), Color(0.38, 0.16, 0.46),
]
const PATTERNS := ["cross", "centre_cross", "saltire", "quarters", "stripes", "bands", "border", "plain"]
const PATTERN_NAMES := {"cross": "Cross", "centre_cross": "Centre cross", "saltire": "Saltire", "quarters": "Quarters",
	"stripes": "Stripes", "bands": "Bands", "border": "Border", "plain": "Plain"}

const DEFAULT := {"coat": [0.16, 0.24, 0.55], "field": [0.13, 0.2, 0.45], "charge": [0.9, 0.88, 0.8], "pattern": "cross"}


static func _c(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func to_arr(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]


static func _cur() -> Dictionary:
	var d = Company.colours if Company.colours is Dictionary else {}
	return d if not d.is_empty() else DEFAULT


## The coat your men wear.
static func coat() -> Color:
	return _c(_cur().get("coat"), COATS[0][1])


## Your own coat: the same colour, darker and finer.
static func officer_coat() -> Color:
	var c := coat()
	return c.darkened(0.42) if c.get_luminance() > 0.12 else c.lightened(0.08)


## {"field": Color, "charge": Color, "pattern": String}
static func flag() -> Dictionary:
	var d := _cur()
	return {"field": _c(d.get("field"), FLAG_COLOURS[0]), "charge": _c(d.get("charge"), FLAG_COLOURS[1]),
		"pattern": String(d.get("pattern", "cross"))}


## The flag's colour at (u, v): u across from the hoist (0) to the fly (1),
## v from the top (0) to the bottom (1).
static func col_at(f: Dictionary, u: float, v: float) -> Color:
	var a: Color = f["field"]
	var b: Color = f["charge"]
	match String(f["pattern"]):
		"cross":
			return b if absf(u - 0.36) < 0.08 or absf(v - 0.5) < 0.1 else a
		"centre_cross":
			return b if absf(u - 0.5) < 0.09 or absf(v - 0.5) < 0.12 else a
		"saltire":
			var d1 := absf(v - u * 1.0)
			var d2 := absf(v - (1.0 - u))
			return b if d1 < 0.11 or d2 < 0.11 else a
		"quarters":
			return a if (u < 0.5) == (v < 0.5) else b
		"stripes":
			return b if u > 0.333 and u < 0.667 else a
		"bands":
			return b if v > 0.333 and v < 0.667 else a
		"border":
			return b if u < 0.09 or u > 0.91 or v < 0.13 or v > 0.87 else a
	return a


## The flag as a small texture (for the screens and the map).
static func flag_texture(f: Dictionary, w := 60, h := 40) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, col_at(f, (x + 0.5) / w, (y + 0.5) / h))
	return ImageTexture.create_from_image(img)
