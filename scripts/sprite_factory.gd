extends RefCounted
## Builds placeholder "Doom-style" sprite frames in code, so the prototype
## needs no art files.
##
## Every character has three views, like Doom's rotations:
##   front - facing the camera
##   side  - facing screen-right (flipped in code when facing left)
##   back  - facing away from the camera
## and a set of animations, each a few frames. Frames are 64x64 with the feet
## on the bottom edge. They're returned as a Dictionary keyed
## "view_anim_frame" (e.g. "side_walk_2"), plus "counts" -> {anim: frames}.
##
## Swapping in real pixel art later only means filling the same Dictionary
## from PNGs instead.

const W := 64
const H := 64

const SOLDIER_ANIMS := {"idle": 1, "walk": 4, "aim": 1, "fire": 1, "reload": 2, "guard": 1, "thrust": 1}
const LIZARD_ANIMS := {"idle": 1, "walk": 4, "windup": 1, "strike": 1, "stagger": 1, "shield": 1}
const VIEWS := ["front", "side", "back"]

# Soldier palette.
const COAT := Color(0.16, 0.24, 0.55)
const COAT_DARK := Color(0.11, 0.17, 0.4)
const WHITE := Color(0.9, 0.88, 0.8)
const WHITE_DARK := Color(0.72, 0.7, 0.64)
const SKIN := Color(0.85, 0.66, 0.5)
const HAIR := Color(0.32, 0.2, 0.12)
const BLACK := Color(0.08, 0.08, 0.1)
const WOOD := Color(0.42, 0.26, 0.12)
const STEEL := Color(0.65, 0.67, 0.7)
const BRIGHT := Color(0.88, 0.9, 0.94)
const GOLD := Color(0.85, 0.68, 0.2)
const PACK := Color(0.3, 0.2, 0.12)
const ROLL := Color(0.55, 0.55, 0.5)
const FLASH := Color(1.0, 0.8, 0.3)
const FLASH_CORE := Color(1.0, 1.0, 0.85)

# Lizardman palette.
const HIDE := Color(0.3, 0.5, 0.22)
const HIDE_DARK := Color(0.18, 0.31, 0.13)
const BELLY := Color(0.62, 0.66, 0.38)
const EYE := Color(1.0, 0.85, 0.1)
const BONE := Color(0.88, 0.83, 0.7)
const CREST := Color(0.62, 0.16, 0.1)


# ---------------------------------------------------------------- public

static func soldier_frames() -> Dictionary:
	return _build(SOLDIER_ANIMS, Callable(_soldier_static_draw))


static func lizard_frames() -> Dictionary:
	return _build(LIZARD_ANIMS, Callable(_lizard_static_draw))


static func _build(anims: Dictionary, draw: Callable) -> Dictionary:
	var out := {"counts": anims}
	for view in VIEWS:
		for anim in anims:
			for i in int(anims[anim]):
				var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
				img.fill(Color(0, 0, 0, 0))
				draw.call(img, view, anim, i)
				out["%s_%s_%d" % [view, anim, i]] = ImageTexture.create_from_image(img)
	return out


static func _soldier_static_draw(img: Image, view: String, anim: String, i: int) -> void:
	var leg := _leg_phase(anim, i)
	match view:
		"front":
			_soldier_front(img, anim, i, leg)
		"side":
			_soldier_side(img, anim, i, leg)
		"back":
			_soldier_back(img, anim, i, leg)


static func _lizard_static_draw(img: Image, view: String, anim: String, i: int) -> void:
	var leg := _leg_phase(anim, i)
	match view:
		"front":
			_lizard_front(img, anim, leg)
		"side":
			_lizard_side(img, anim, leg)
		"back":
			_lizard_back(img, anim, leg)


## Walk cycle: 1 = left leg forward/up, -1 = right leg, 0 = passing.
static func _leg_phase(anim: String, i: int) -> int:
	if anim == "walk":
		return [1, 0, -1, 0][i]
	return 0


# ---------------------------------------------------------------- drawing helpers

static func _px(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, W, H))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < W and y < H and (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				img.set_pixel(x, y, c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color, th: int = 1) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for s in steps + 1:
		var t := 0.0 if steps == 0 else float(s) / steps
		var x := roundi(lerpf(x0, x1, t))
		var y := roundi(lerpf(y0, y1, t))
		_px(img, x, y, th, th, c)


## Round wooden shield with an iron rim and boss.
static func _shield(img: Image, cx: int, cy: int, r: int) -> void:
	_disc(img, cx, cy, r, STEEL)
	_disc(img, cx, cy, r - 1, WOOD)
	_px(img, cx - r + 2, cy - 1, 2 * r - 3, 1, Color(0.32, 0.2, 0.09)) # plank seam
	_disc(img, cx, cy, maxi(1, r / 4), BRIGHT)


## A shield seen edge-on (side view): a tall thin oval.
static func _shield_edge(img: Image, x: int, y: int, h: int) -> void:
	_px(img, x, y + 2, 3, h - 4, WOOD)
	_px(img, x + 1, y, 1, h, STEEL)


static func _flash(img: Image, x: int, y: int) -> void:
	_disc(img, x, y, 5, FLASH)
	_disc(img, x, y, 2, FLASH_CORE)


# ---------------------------------------------------------------- soldier

## Legs seen from front or back. A lifted foot is drawn shorter.
static func _soldier_legs_fb(img: Image, x0: int, leg: int) -> void:
	var l_lift := 3 if leg == 1 else 0
	var r_lift := 3 if leg == -1 else 0
	_px(img, x0 + 10, 40, 5, 16 - l_lift, WHITE)
	_px(img, x0 + 10, 56 - l_lift, 5, 8, BLACK)
	_px(img, x0 + 17, 40, 5, 16 - r_lift, WHITE)
	_px(img, x0 + 17, 56 - r_lift, 5, 8, BLACK)


static func _soldier_front(img: Image, anim: String, i: int, leg: int) -> void:
	var x0 := 16
	_soldier_legs_fb(img, x0, leg)
	if anim == "reload":
		# Butt grounded between the feet, muzzle at the chin.
		_px(img, x0 + 15, 26, 3, 38, WOOD)
	# Coat and crossbelts.
	_px(img, x0 + 9, 19, 14, 21, COAT)
	for k in 13:
		_px(img, x0 + 9 + k, 20 + k, 2, 2, WHITE)
		_px(img, x0 + 21 - k, 20 + k, 2, 2, WHITE)
	# Head.
	_px(img, x0 + 11, 2, 10, 9, BLACK)
	_px(img, x0 + 10, 10, 12, 2, BLACK)
	_px(img, x0 + 14, 4, 4, 3, GOLD)
	_px(img, x0 + 12, 12, 8, 7, SKIN)
	_px(img, x0 + 13, 14, 2, 1, BLACK)
	_px(img, x0 + 17, 14, 2, 1, BLACK)

	match anim:
		"idle", "walk":
			var swing := leg * 2
			_px(img, x0 + 7, 20 + swing, 3, 15, COAT)
			_px(img, x0 + 22, 20 - swing, 3, 15, COAT)
			_px(img, x0 + 7, 35 + swing, 3, 3, SKIN)
			_px(img, x0 + 22, 35 - swing, 3, 3, SKIN)
			# Musket shouldered upright.
			_px(img, x0 + 25, 4 - swing, 2, 18, STEEL)
			_px(img, x0 + 25, 22 - swing, 3, 24, WOOD)
		"aim", "fire":
			# Levelled at the viewer: arms across the chest, cheek on the stock.
			_px(img, x0 + 8, 18, 16, 4, COAT)
			_px(img, x0 + 13, 18, 6, 4, SKIN)
			_px(img, x0 + 19, 14, 5, 8, WOOD)
			_disc(img, x0 + 17, 16, 2, BLACK) # muzzle pointing at you
			_px(img, x0 + 17, 16, 1, 1, Color(0.25, 0.25, 0.28))
			if anim == "fire":
				_flash(img, x0 + 17, 16)
		"reload":
			var hand_y := 2 if i == 0 else 9
			_px(img, x0 + 15, 14, 2, 12, STEEL) # barrel
			_line(img, x0 + 16, hand_y + 2, x0 + 16, 14, BRIGHT) # ramrod
			_px(img, x0 + 18, hand_y + 2, 4, 21 - hand_y, COAT) # raised right arm
			_px(img, x0 + 15, hand_y, 4, 3, SKIN)
			_px(img, x0 + 7, 20, 3, 6, COAT)
			_px(img, x0 + 9, 24, 7, 3, COAT) # left arm to the barrel
			_px(img, x0 + 13, 23, 4, 4, SKIN)
		"guard":
			_line(img, x0 + 24, 44, x0 + 8, 16, WOOD, 3)
			_line(img, x0 + 8, 16, x0 + 3, 6, BRIGHT, 2)
			_px(img, x0 + 21, 38, 4, 4, SKIN)
			_px(img, x0 + 12, 25, 4, 4, SKIN)
			_px(img, x0 + 22, 22, 3, 16, COAT)
			_px(img, x0 + 7, 20, 3, 8, COAT)
		"thrust":
			# Lunging at the viewer: arms out, bayonet point coming at you.
			_px(img, x0 + 10, 22, 12, 6, COAT)
			_px(img, x0 + 13, 26, 6, 4, SKIN)
			_px(img, x0 + 14, 27, 5, 9, WOOD)
			_disc(img, x0 + 16, 30, 3, STEEL)
			_disc(img, x0 + 16, 30, 1, BRIGHT)


static func _soldier_side(img: Image, anim: String, i: int, leg: int) -> void:
	var lean := 2 if anim == "thrust" else 0
	# Legs: the far leg darker, stride by walk phase.
	var stride := leg * 4
	_px(img, 28 - stride, 40, 4, 16, WHITE_DARK)
	_px(img, 28 - stride, 56, 6, 8, BLACK)
	_px(img, 29 + stride, 40, 4, 16, WHITE)
	_px(img, 29 + stride, 56, 6, 8, BLACK)
	if anim == "reload":
		_px(img, 38, 26, 2, 38, WOOD) # butt grounded in front
	# Pack and blanket roll on the back.
	_px(img, 22 + lean, 20, 5, 15, PACK)
	_px(img, 22 + lean, 17, 9, 3, ROLL)
	# Coat with tails.
	_px(img, 27 + lean, 19, 10, 22, COAT)
	_px(img, 27 + lean, 40, 3, 5, COAT_DARK)
	_line(img, 35 + lean, 20, 28 + lean, 33, WHITE, 2)
	# Head in profile.
	_px(img, 30 + lean, 12, 7, 7, SKIN)
	_px(img, 37 + lean, 15, 1, 2, SKIN) # nose
	_px(img, 29 + lean, 12, 2, 5, HAIR)
	_px(img, 34 + lean, 14, 1, 1, BLACK) # eye
	_px(img, 29 + lean, 2, 8, 9, BLACK)
	_px(img, 34 + lean, 10, 5, 2, BLACK) # peak
	_px(img, 34 + lean, 4, 2, 3, GOLD)

	match anim:
		"idle", "walk":
			var swing := leg * 2
			_px(img, 37, 4, 2, 17, STEEL)
			_px(img, 37, 21, 2, 25, WOOD)
			_px(img, 33 + swing, 20, 4, 12, COAT_DARK)
			_px(img, 35 + swing, 31, 3, 3, SKIN)
		"aim", "fire":
			_px(img, 30, 16, 14, 2, WOOD)
			_px(img, 44, 16, 16, 2, STEEL)
			_px(img, 33, 18, 9, 4, COAT_DARK)
			_px(img, 40, 17, 3, 3, SKIN)
			_px(img, 31, 18, 3, 3, SKIN)
			if anim == "fire":
				_disc(img, 57, 12, 3, ROLL)
				_flash(img, 61, 16)
		"reload":
			var hand_y := 2 if i == 0 else 9
			_px(img, 38, 14, 2, 12, STEEL)
			_line(img, 39, hand_y + 2, 39, 14, BRIGHT)
			_px(img, 34, hand_y + 2, 4, 21 - hand_y, COAT_DARK)
			_px(img, 36, hand_y, 4, 3, SKIN)
			_px(img, 37, 25, 4, 3, SKIN)
		"guard":
			_line(img, 31, 42, 50, 22, WOOD, 3)
			_line(img, 50, 22, 57, 15, BRIGHT, 2)
			_px(img, 33, 22, 4, 14, COAT_DARK)
			_px(img, 33, 37, 4, 3, SKIN)
			_px(img, 42, 30, 3, 3, SKIN)
		"thrust":
			_px(img, 30, 25, 16, 3, WOOD)
			_px(img, 46, 25, 10, 2, STEEL)
			_px(img, 56, 25, 8, 1, BRIGHT)
			_px(img, 34 + lean, 22, 12, 4, COAT_DARK)
			_px(img, 45, 23, 3, 4, SKIN)


static func _soldier_back(img: Image, anim: String, i: int, leg: int) -> void:
	var x0 := 16
	_soldier_legs_fb(img, x0, -leg)
	if anim == "fire":
		_flash(img, x0 + 19, 9) # muzzle flash beyond the head
	# Coat with tails and crossbelts.
	_px(img, x0 + 9, 19, 14, 23, COAT)
	for k in 13:
		_px(img, x0 + 9 + k, 20 + k, 2, 2, WHITE)
		_px(img, x0 + 21 - k, 20 + k, 2, 2, WHITE)
	# Pack and blanket roll.
	_px(img, x0 + 10, 21, 12, 14, PACK)
	_px(img, x0 + 9, 18, 14, 3, ROLL)
	_px(img, x0 + 10, 27, 12, 1, BLACK)
	# Back of the head.
	_px(img, x0 + 12, 12, 8, 4, HAIR)
	_px(img, x0 + 13, 16, 6, 3, SKIN)
	_px(img, x0 + 11, 2, 10, 10, BLACK)

	match anim:
		"idle", "walk":
			var swing := leg * 2
			_px(img, x0 + 7, 20 - swing, 3, 15, COAT)
			_px(img, x0 + 22, 20 + swing, 3, 15, COAT)
			_px(img, x0 + 7, 35 - swing, 3, 3, SKIN)
			_px(img, x0 + 22, 35 + swing, 3, 3, SKIN)
			_px(img, x0 + 24, 4, 2, 18, STEEL)
			_px(img, x0 + 24, 22, 3, 24, WOOD)
		"aim", "fire":
			_px(img, x0 + 22, 17, 7, 4, COAT) # right elbow raised
			_px(img, x0 + 4, 18, 6, 4, COAT)
			_px(img, x0 + 19, 14, 4, 5, WOOD)
		"reload":
			var hand_y := 2 if i == 0 else 9
			_line(img, x0 + 18, hand_y + 2, x0 + 18, 14, BRIGHT)
			_px(img, x0 + 17, 14, 2, 4, STEEL)
			_px(img, x0 + 19, hand_y + 2, 4, 21 - hand_y, COAT)
			_px(img, x0 + 17, hand_y, 4, 3, SKIN)
			_px(img, x0 + 7, 20, 3, 8, COAT)
		"guard":
			_line(img, x0 + 25, 42, x0 + 17, 28, WOOD, 3)
			_px(img, x0 + 22, 22, 3, 14, COAT)
			_px(img, x0 + 7, 20, 3, 8, COAT)
		"thrust":
			_px(img, x0 + 22, 22, 5, 4, COAT)
			_px(img, x0 + 21, 26, 5, 4, WOOD)
			_px(img, x0 + 6, 21, 4, 4, COAT)


# ---------------------------------------------------------------- lizardman

static func _lizard_legs_fb(img: Image, x0: int, leg: int) -> void:
	var l_lift := 3 if leg == 1 else 0
	var r_lift := 3 if leg == -1 else 0
	_px(img, x0 + 15, 42, 7, 14 - l_lift, HIDE)
	_px(img, x0 + 13, 56 - l_lift, 10, 5, HIDE_DARK)
	_px(img, x0 + 26, 42, 7, 14 - r_lift, HIDE)
	_px(img, x0 + 25, 56 - r_lift, 10, 5, HIDE_DARK)


static func _lizard_head_front(img: Image, x0: int, dy: int, open: int) -> void:
	_px(img, x0 + 15, 7 + dy, 18, 13, HIDE)
	_px(img, x0 + 16, 16 + dy, 16, 7 + open, HIDE_DARK)
	for t in 6:
		_px(img, x0 + 17 + t * 2, 16 + dy, 1, 3, BONE)
	_px(img, x0 + 17, 10 + dy, 4, 3, EYE)
	_px(img, x0 + 27, 10 + dy, 4, 3, EYE)
	for s in 5:
		_px(img, x0 + 15 + s * 4, 2 + dy + (s % 2) * 2, 2, 6, CREST)


static func _cleaver(img: Image, hx: int, hy: int, bx: int, by: int, bw: int, bh: int) -> void:
	_px(img, hx, hy, 2, 10, WOOD)
	_px(img, bx, by, bw, bh, STEEL)
	_px(img, bx, by, bw, 1, BRIGHT)


static func _lizard_front(img: Image, anim: String, leg: int) -> void:
	var x0 := 8
	var dy := -3 if anim == "stagger" else 0
	# Tail out to one side.
	_px(img, x0 + 30, 44, 10, 5, HIDE_DARK)
	_px(img, x0 + 38, 47, 7, 4, HIDE_DARK)
	_lizard_legs_fb(img, x0, leg)
	_px(img, x0 + 13, 20 + dy, 22, 24 - dy, HIDE)
	_px(img, x0 + 17, 24 + dy, 14, 18, BELLY)
	match anim:
		"idle", "walk":
			var swing := leg * 2
			_px(img, x0 + 7, 22 + swing, 6, 17, HIDE)
			_px(img, x0 + 35, 22 - swing, 6, 17, HIDE)
			_px(img, x0 + 6, 39 + swing, 2, 5, BONE)
			_px(img, x0 + 10, 39 + swing, 2, 5, BONE)
			_cleaver(img, x0 + 41, 28 - swing, x0 + 39, 18 - swing, 8, 11)
			_lizard_head_front(img, x0, 0, 0)
		"windup":
			# Both arms up, cleaver raised over the head, jaws wide.
			_px(img, x0 + 7, 6, 6, 18, HIDE)
			_px(img, x0 + 35, 6, 6, 18, HIDE)
			_px(img, x0 + 6, 2, 2, 5, BONE)
			_px(img, x0 + 10, 2, 2, 5, BONE)
			_cleaver(img, x0 + 38, 0, x0 + 40, 0, 8, 7)
			_lizard_head_front(img, x0, 0, 3)
		"strike":
			_px(img, x0 + 10, 28, 12, 6, HIDE)
			_px(img, x0 + 26, 30, 12, 6, HIDE)
			_cleaver(img, x0 + 23, 32, x0 + 19, 38, 10, 7)
			_lizard_head_front(img, x0, 2, 2)
		"stagger":
			_px(img, x0 + 3, 14, 6, 15, HIDE)
			_px(img, x0 + 39, 14, 6, 15, HIDE)
			_cleaver(img, x0 + 44, 6, x0 + 42, 0, 8, 7)
			_lizard_head_front(img, x0, dy, 4)
			_shield(img, x0 + 5, 20, 7)
		"shield":
			# Shield brought up across the chest, cleaver held back ready.
			_px(img, x0 + 35, 20, 6, 14, HIDE)
			_cleaver(img, x0 + 41, 24, x0 + 39, 14, 8, 11)
			_lizard_head_front(img, x0, 0, 1)
			_shield(img, x0 + 20, 27, 11)
	if anim in ["idle", "walk"]:
		_shield(img, x0 + 9, 32 + leg * 2, 7)
	elif anim == "windup":
		_shield(img, x0 + 9, 9, 6)
	elif anim == "strike":
		_shield(img, x0 + 10, 33, 7)


static func _lizard_side(img: Image, anim: String, leg: int) -> void:
	var stride := leg * 4
	var head_dy := -3 if anim == "stagger" else (2 if anim == "strike" else 0)
	# Long tail streaming behind.
	_px(img, 4, 42, 10, 3, HIDE_DARK)
	_px(img, 12, 40, 14, 5, HIDE_DARK)
	# Digitigrade legs, far leg darker.
	for pass_i in 2:
		var far := pass_i == 0
		var sx := 27 - stride if far else 29 + stride
		var col := HIDE_DARK if far else HIDE
		_px(img, sx, 38, 6, 9, col)
		_px(img, sx + 3, 46, 4, 10, col)
		_px(img, sx + 1, 56, 9, 5, HIDE_DARK)
	# Hunched body.
	_px(img, 24, 22, 17, 19, HIDE)
	_px(img, 34, 26, 6, 12, BELLY)
	for s in 5:
		_px(img, 25 + s * 3, 18 + (s % 2), 2, 4, CREST)
	# Head thrust forward.
	_px(img, 38, 14 + head_dy, 12, 10, HIDE)
	_px(img, 48, 17 + head_dy, 9, 6, HIDE)
	_px(img, 44, 22 + head_dy, 13, 3 + (2 if anim == "windup" else 0), HIDE_DARK)
	for t in 5:
		_px(img, 46 + t * 2, 22 + head_dy, 1, 2, BONE)
	_px(img, 45, 16 + head_dy, 3, 2, EYE)
	_px(img, 39, 11 + head_dy, 2, 4, CREST)
	match anim:
		"idle", "walk":
			_px(img, 36 + leg, 27, 4, 13, HIDE_DARK)
			_px(img, 39 + leg, 40, 3, 3, BONE)
			_cleaver(img, 41 + leg, 32, 42 + leg, 38, 7, 8)
		"windup":
			_px(img, 31, 8, 5, 19, HIDE_DARK)
			_cleaver(img, 31, 0, 25, 0, 9, 7)
		"strike":
			_px(img, 38, 30, 14, 4, HIDE_DARK)
			_cleaver(img, 52, 28, 52, 33, 7, 9)
		"stagger":
			_px(img, 30, 14, 4, 14, HIDE_DARK)
			_cleaver(img, 28, 6, 24, 2, 8, 6)
		"shield":
			_px(img, 34, 24, 4, 12, HIDE_DARK)
			_cleaver(img, 30, 28, 24, 30, 7, 8)
			_shield_edge(img, 50, 12, 26) # raised in front of the snout
	if anim != "shield":
		_shield_edge(img, 41, 25, 16) # on the far arm


static func _lizard_back(img: Image, anim: String, leg: int) -> void:
	var x0 := 8
	_lizard_legs_fb(img, x0, -leg)
	_px(img, x0 + 13, 20, 22, 24, HIDE_DARK)
	for s in 7:
		_px(img, x0 + 23, 18 + s * 4, 2, 3, CREST)
	# Head from behind, crest spikes.
	_px(img, x0 + 15, 8, 18, 13, HIDE_DARK)
	for s in 5:
		_px(img, x0 + 15 + s * 4, 3 + (s % 2) * 2, 2, 6, CREST)
	match anim:
		"idle", "walk":
			var swing := leg * 2
			_px(img, x0 + 7, 22 - swing, 6, 17, HIDE)
			_px(img, x0 + 35, 22 + swing, 6, 17, HIDE)
			_cleaver(img, x0 + 6, 28 + swing, x0 + 1, 18 + swing, 8, 11)
		"windup", "stagger":
			_px(img, x0 + 7, 6, 6, 18, HIDE)
			_px(img, x0 + 35, 6, 6, 18, HIDE)
			_cleaver(img, x0 + 8, 0, x0 + 0, 0, 8, 7)
		"strike", "shield":
			_px(img, x0 + 9, 22, 5, 7, HIDE)
			_px(img, x0 + 34, 22, 5, 7, HIDE)
	if anim == "shield":
		_px(img, x0 + 12, 16, 24, 3, WOOD) # shield rim showing over the shoulders
	else:
		_shield(img, x0 + 40, 32, 7) # back of the shield on his other arm
	# Thick tail hanging toward the viewer, drawn last (closest).
	_px(img, x0 + 19, 40, 10, 10, HIDE)
	_px(img, x0 + 21, 50, 6, 8, HIDE)
	_px(img, x0 + 22, 58, 4, 4, HIDE_DARK)


# ---------------------------------------------------------------- effects

static func smoke_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
