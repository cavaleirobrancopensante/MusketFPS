extends Node3D
## Short cutscenes inside the first battle (field_prologue.gd), played in
## the battle itself, with its own camera, letterbox and captions:
##
##   "command"   the Major is down: you kneel by him and he gives you the
##               regiment, then dies. The battle is paused while he speaks;
##               when it ends you're beside him and the command view opens.
##   "collapse"  the left gives way: the horde pours round the end of the
##               works, the left company breaks, the guns are overrun. The
##               battle runs on under the camera; at the end the fight is
##               over and the retreat (retreat.gd) begins.
##
## Speakers have voices (sound_factory.gd's talk), the sergeant shouts.

const Rig3D := preload("res://scripts/rig3d.gd")
const Lore := preload("res://scripts/lore.gd")
const UI := preload("res://scripts/ui.gd")
const SoundFactory := preload("res://scripts/sound_factory.gd")

var battle
var story
var kind := "command"
var _t := 0.0
var _len := 16.0
var _cam: Camera3D
var _caption: Label
var _band: ColorRect
var _fade: ColorRect
var _hidden: Array = [] # the battle's own screens, put away while this plays
var _kneeler: Node3D
var _krig
var _mrig # the Major, on his back in the sand
var _captions: Array = []
var _voices: Array = []
var _sounds := {}
var _done := false
var _from := Vector3.ZERO
var _cp := Vector3.ZERO # the Major


static func play(b, s, what: String):
	var n = load("res://scripts/story_scene.gd").new()
	n.battle = b
	n.story = s
	n.kind = what
	b.add_child(n)
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var all := SoundFactory.cached()
	for k in ["shout", "talk1", "talk2", "talk3", "talk4", "drum", "roar", "hiss"]:
		if all.has(k):
			_sounds[k] = all[k]
	# Put the battle's screens away (the HUD, the command view).
	for c in battle.get_children():
		if c is CanvasLayer and (c as CanvasLayer).visible:
			(c as CanvasLayer).visible = false
			_hidden.append(c)
	_cam = Camera3D.new()
	_cam.far = 500.0
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()
	_build_overlay()
	var sarge: String = battle._sergeant_name()
	if kind == "command":
		_len = 17.0
		get_tree().paused = true # (the fight holds its breath while he speaks)
		_cp = battle.captain.global_position if battle.captain != null else battle.player.global_position
		var pl: Vector3 = battle.player.global_position
		# (you come from behind him, the beach side, so the line doesn't stand
		# in the camera's way)
		var side := Vector3(0.45 * signf(pl.x - _cp.x + 0.01), 0.0, 1.0).normalized()
		_from = _cp + side * 7.0
		# You: a figure of your own, to kneel by him (the real you waits off camera).
		_kneeler = Node3D.new()
		_kneeler.position = Vector3(_from.x, battle.ground_y(_from), _from.z)
		add_child(_kneeler)
		_krig = Rig3D.new()
		_krig.kind = "officer"
		_krig.gear = Company.officer.get("gear", {}) if Company.active else {}
		_krig.full_rate = true
		_krig.process_mode = Node.PROCESS_MODE_ALWAYS
		_krig.facing = (_cp - _from).normalized()
		_kneeler.add_child(_krig)
		# The Major: a figure of his own too, lying where he fell (the real
		# one, and you, are put out of the camera's way until it ends).
		if battle.captain != null:
			battle.captain.visible = false
		battle.player.visible = false
		_redraw([battle.captain, battle.player])
		var mn := Node3D.new()
		mn.position = Vector3(_cp.x, battle.ground_y(_cp), _cp.z)
		add_child(mn)
		_mrig = Rig3D.new()
		_mrig.kind = "officer"
		_mrig.gear = Rig3D.MAJOR_GEAR.duplicate()
		_mrig.full_rate = true
		_mrig.facing = Vector3(-side.x, 0.0, -side.z)
		mn.add_child(_mrig)
		# On his back (the rig's "sleep" lie: head away from where he faces,
		# so toward you), both hands round the javelin in his chest.
		_mrig.anim = "sleep"
		_mrig.manual = true
		_mrig.t_grip = Vector3(0.45, 0.2, 0.02)
		_mrig.t_dir = Vector3(0, 1, 0)
		_mrig.t_hand_r = Vector3(0.05, 1.1, -0.3)
		_mrig.t_hand_l = Vector3(-0.05, 1.22, -0.34)
		var jav := MeshInstance3D.new()
		var jm := BoxMesh.new()
		jm.size = Vector3(0.035, 0.035, 1.3)
		var jmat := StandardMaterial3D.new()
		jmat.albedo_color = Color(0.45, 0.32, 0.18)
		jm.material = jmat
		jav.mesh = jm
		# (in his body's frame: out of the chest, leaning a little to his left)
		jav.position = Vector3(-0.04, 1.18, -0.6)
		jav.rotation = Vector3(0.18, 0.12, 0.0)
		_mrig.body.add_child(jav)
		var tip := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.05, 0.05, 0.16)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.35, 0.33, 0.3)
		tm.material = tmat
		tip.mesh = tm
		tip.position = Vector3(0, 0, -0.68)
		jav.add_child(tip) # (the bone point's binding at the end of the shaft)
		_captions = [
			[0.3, 3.0, Lang.t("%s: \"The Major's hit! Ensign, to the Major!\"") % sarge],
			[3.2, 5.6, Lang.t("You reach him through the smoke and kneel in the sand beside him.")],
			[5.8, 9.6, Lang.t("%s: \"Ensign... listen. You have the regiment. All of it: the companies, the guns.\"") % Lore.COMMANDER],
			[9.8, 14.0, Lang.t("\"Hold them on the works while you can. When it breaks, and it will, take them up the cliff path. Keep them alive.\"")],
			[14.2, 16.8, Lang.t("%s is dead. You command the regiment.") % Lore.COMMANDER_SHORT],
		]
		_voices = [[0.35, "shout", 1.05, -2.0], [1.4, "talk1", 1.0, -6.0], [5.9, "talk3", 0.8, -4.0], [7.6, "talk3", 0.78, -6.0],
			[9.9, "talk3", 0.8, -5.0], [11.8, "talk2", 0.78, -7.0], [14.3, "drum", 1.0, -10.0]]
	else:
		_len = 13.0
		# The battle goes on under the camera; you stand aside from it.
		battle.player.process_mode = Node.PROCESS_MODE_DISABLED
		_captions = [
			[0.3, 4.4, Lang.t("%s: \"Sir! The left's gone, they're round the end of the works!\"") % sarge],
			[4.6, 8.8, Lang.t("They pour over the earthworks and in among the guns. Nothing will hold them now.")],
			[9.0, 12.8, Lang.t("The left company breaks and runs. The guns are lost, and the beach with them.")],
		]
		_voices = [[0.35, "shout", 1.0, 0.0], [1.3, "talk1", 1.05, -4.0], [2.0, "roar", 0.9, -2.0], [4.0, "drum", 1.0, -4.0],
			[5.0, "roar", 0.8, 0.0], [6.4, "hiss", 0.9, -2.0], [7.2, "drum", 0.95, -3.0], [9.2, "shout", 0.9, -3.0],
			[10.0, "roar", 0.85, -1.0], [11.4, "talk2", 1.1, -6.0], [12.0, "drum", 0.9, -5.0]]


func _play(name: String, db: float, pitch := 1.0) -> void:
	if not _sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0 if top else -64
		bar.offset_bottom = 64 if top else 0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	_band = ColorRect.new()
	_band.color = Color(0, 0, 0, 0.0)
	_band.anchor_right = 1.0
	_band.anchor_top = 1.0
	_band.anchor_bottom = 1.0
	_band.offset_top = -160
	_band.offset_bottom = -66
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_band)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.offset_left = 80
	_caption.offset_right = -80
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_override("font", UI.font("fell_italic"))
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_band.add_child(_caption)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	var skip := Button.new()
	skip.text = Lang.t("Skip  ▸")
	skip.add_theme_font_size_override("font_size", 22)
	skip.position = Vector2(20, 76)
	skip.size = Vector2(150, 56)
	skip.pressed.connect(_finish)
	root.add_child(skip)


func _process(delta: float) -> void:
	if _done:
		return
	var prev := _t
	_t += delta
	for v in _voices:
		if prev < float(v[0]) and _t >= float(v[0]):
			_play(String(v[1]), float(v[3]), float(v[2]))
	var text := ""
	var a := 0.0
	for c in _captions:
		if _t >= float(c[0]) and _t <= float(c[1]):
			text = c[2]
			a = clampf(minf(_t - float(c[0]), float(c[1]) - _t) / 0.4, 0.0, 1.0)
	_caption.text = text
	_band.visible = text != ""
	_band.modulate.a = a
	_fade.color.a = clampf(1.0 - _t / 0.4, 0.0, 1.0) + clampf((_t - (_len - 0.6)) / 0.6, 0.0, 1.0)
	if kind == "command":
		_command_shot(delta)
	else:
		_collapse_shot()
	if _t >= _len:
		_finish()


## The Major down; you come through the smoke and kneel; he speaks; he dies.
func _command_shot(delta: float) -> void:
	_krig.anim_time += delta
	# (beside him, at his shoulder)
	var sd := (_from - _cp).normalized()
	var to := _cp + sd * 1.2 + sd.cross(Vector3.UP) * 1.0
	var walk := clampf((_t - 2.6) / 2.6, 0.0, 1.0)
	var at := _from.lerp(to, walk)
	_kneeler.position = Vector3(at.x, battle.ground_y(at), at.z)
	var aim := _cp + sd * 1.2 - at
	aim.y = 0.0
	if aim.length() > 0.05:
		_krig.facing = aim.normalized()
	if walk < 1.0 and _t > 2.6:
		_krig.anim = "walk"
		_krig.move_speed = 2.6
	elif _t > 2.6:
		_krig.anim = "tend"
		_krig.move_speed = 0.0
	else:
		_krig.anim = "idle"
	if _mrig != null:
		# (his hands tighten on the shaft as he speaks)
		var g := 0.03 * sin(_t * 2.2) if _t > 5.8 and _t < 14.0 else 0.0
		_mrig.t_hand_r = Vector3(0.05, 1.1 + g, -0.3)
		_mrig.t_hand_l = Vector3(-0.05, 1.22 - g, -0.34)
	var side := (_from - _cp).normalized()
	var across := side.cross(Vector3.UP)
	if _t < 2.6:
		# The Major on the sand, the fight going on beyond him.
		var k := _t / 2.6
		_cam_to(_cp + side * (3.4 - 0.6 * k) + across * 2.2 + Vector3(0, 1.5 + 0.3 * k, 0), _cp + Vector3(0, 0.3, 0), 46.0)
	elif _t < 5.8:
		# You, coming to him.
		_cam_to(_cp + side * 4.0 + across * 4.5 + Vector3(0, 1.8, 0), _kneeler.position.lerp(_cp, 0.5) + Vector3(0, 0.7, 0), 48.0)
	elif _t < 14.2:
		# Close, from his other side: you kneeling over him, slowly circling.
		var a := 0.35 + (_t - 5.8) * 0.07
		var off := (-across * cos(a) + side * sin(a)) * 3.0
		_cam_to(_cp + side * 0.9 + off + Vector3(0, 1.45, 0), _cp + side * 0.9 + Vector3(0, 0.4, 0), 42.0)
	else:
		# Up and away: the smoke, the line still firing.
		var k2 := (_t - 14.2) / 2.8
		_cam_to(_cp + side * (3.0 + 5.0 * k2) + across * 1.5 + Vector3(0, 2.2 + 6.5 * k2, 0), _cp + Vector3(0, 0.3, -7.0 * k2), 46.0)


## The left goes: over the end of the works, the company routing, then the
## horde in among the guns.
func _collapse_shot() -> void:
	# (the camera follows the horde)
	var h := Vector3(-55.0, 0.0, -6.0)
	var n := 0
	var sum := Vector3.ZERO
	for r in story.horde:
		if is_instance_valid(r) and not r.gone():
			sum += r.centroid
			n += 1
	if n > 0:
		h = sum / n
	h.y = 0.0
	var lc := Vector3(-34.0, 0.0, 8.0) # (the left end of the works, by the left guns)
	if _t < 4.6:
		# High, behind the line: them coming round the end of the works.
		var k := _t / 4.6
		_cam_to(h + Vector3(24.0 - 4.0 * k, 11.0 - 2.0 * k, 26.0), h + Vector3(4.0, 0.0, 2.0), 50.0)
	elif _t < 9.0:
		# Down by the left company as it goes.
		var k2 := (_t - 4.6) / 4.4
		_cam_to(lc + Vector3(9.0 - 3.0 * k2, 2.6, 11.0), h.lerp(lc, 0.35 + 0.3 * k2) + Vector3(0, 1.0, 0), 52.0)
	else:
		# Up over the lost guns.
		var k3 := (_t - 9.0) / 4.0
		_cam_to(Vector3(-24.0 + 6.0 * k3, 6.0 + 8.0 * k3, 26.0 + 6.0 * k3), Vector3(-38.0, 0.0, 4.0).lerp(h, 0.4), 54.0)


func _cam_to(at: Vector3, look: Vector3, fov: float) -> void:
	_cam.global_position = at
	_cam.look_at(look)
	_cam.fov = fov


## The tree is paused, so a body's batched drawing wouldn't notice it being
## hidden (or shown): redraw it now.
func _redraw(who: Array) -> void:
	for u in who:
		if u != null and is_instance_valid(u) and u.get("rig") != null:
			u.rig._emit()


func _finish() -> void:
	if _done:
		return
	_done = true
	for c in _hidden:
		if is_instance_valid(c):
			(c as CanvasLayer).visible = true
	if kind == "command":
		# You're beside him now; the battle goes on, and the regiment is yours.
		var at: Vector3 = _kneeler.global_position
		battle.player.global_position = Vector3(at.x, battle.ground_y(at) + 0.3, at.z)
		battle.player.visible = true
		if battle.captain != null:
			battle.captain.visible = true
		_redraw([battle.captain, battle.player])
		get_tree().paused = false
		battle.player.camera.make_current()
		queue_free()
		story.after_command_scene()
	else:
		battle.player.process_mode = Node.PROCESS_MODE_INHERIT
		battle.player.camera.make_current()
		queue_free()
		story.after_collapse_scene()
