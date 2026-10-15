extends RefCounted
## Builds placeholder "Doom-style" sprite textures in code, so the prototype
## needs no art files. Swap these for real pixel art later: any PNG with the
## figure standing on the bottom edge will work the same way.


static func _px(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


static func soldier_texture() -> ImageTexture:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var coat := Color(0.16, 0.24, 0.55)
	var white := Color(0.9, 0.88, 0.8)
	var skin := Color(0.85, 0.66, 0.5)
	var black := Color(0.08, 0.08, 0.1)
	var wood := Color(0.42, 0.26, 0.12)
	var steel := Color(0.65, 0.67, 0.7)
	var gold := Color(0.85, 0.68, 0.2)
	# shako
	_px(img, 11, 2, 10, 9, black)
	_px(img, 10, 10, 12, 2, black)
	_px(img, 14, 4, 4, 3, gold)
	# face
	_px(img, 12, 12, 8, 7, skin)
	# coat and arms
	_px(img, 9, 19, 14, 21, coat)
	_px(img, 7, 20, 3, 15, coat)
	_px(img, 22, 20, 3, 15, coat)
	# white crossbelts
	for i in 13:
		_px(img, 9 + i, 20 + i, 2, 2, white)
		_px(img, 21 - i, 20 + i, 2, 2, white)
	# hands
	_px(img, 7, 35, 3, 3, skin)
	_px(img, 22, 35, 3, 3, skin)
	# trousers and boots
	_px(img, 10, 40, 5, 16, white)
	_px(img, 17, 40, 5, 16, white)
	_px(img, 10, 56, 5, 8, black)
	_px(img, 17, 56, 5, 8, black)
	# musket held upright at the shoulder
	_px(img, 25, 4, 2, 18, steel)
	_px(img, 25, 22, 3, 24, wood)
	return ImageTexture.create_from_image(img)


static func lizard_texture() -> ImageTexture:
	var img := Image.create(48, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hide := Color(0.3, 0.5, 0.22)
	var belly := Color(0.62, 0.66, 0.38)
	var dark := Color(0.16, 0.28, 0.12)
	var eye := Color(1.0, 0.85, 0.1)
	var bone := Color(0.88, 0.83, 0.7)
	var crest := Color(0.62, 0.16, 0.1)
	var wood := Color(0.4, 0.25, 0.12)
	var steel := Color(0.6, 0.6, 0.6)
	# tail sweeping out to one side
	_px(img, 30, 44, 10, 5, dark)
	_px(img, 38, 47, 7, 4, dark)
	# thick legs and clawed feet
	_px(img, 15, 42, 7, 14, hide)
	_px(img, 26, 42, 7, 14, hide)
	_px(img, 13, 56, 10, 5, dark)
	_px(img, 25, 56, 10, 5, dark)
	# hunched torso
	_px(img, 13, 20, 22, 24, hide)
	_px(img, 17, 24, 14, 18, belly)
	# long arms with claws
	_px(img, 7, 22, 6, 17, hide)
	_px(img, 35, 22, 6, 17, hide)
	_px(img, 6, 39, 2, 5, bone)
	_px(img, 10, 39, 2, 5, bone)
	# head, low and forward, with jaws open
	_px(img, 15, 7, 18, 13, hide)
	_px(img, 16, 16, 16, 7, dark)
	for t in 6:
		_px(img, 17 + t * 2, 16, 1, 3, bone)
	_px(img, 17, 10, 4, 3, eye)
	_px(img, 27, 10, 4, 3, eye)
	# crest spikes
	for s in 5:
		_px(img, 15 + s * 4, 2 + (s % 2) * 2, 2, 6, crest)
	# crude cleaver in the right hand
	_px(img, 41, 26, 2, 16, wood)
	_px(img, 39, 16, 8, 11, steel)
	return ImageTexture.create_from_image(img)


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
