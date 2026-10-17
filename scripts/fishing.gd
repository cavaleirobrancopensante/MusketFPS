extends Node3D
## Fishing with a rod (FISH YOURSELF at a fishing water on the map, with a
## fishing rod in the wagon). battle.gd makes one of these for the hunt; the
## HUD's CAST button drives it (press, hold, release), and player_body.gd
## asks it where your hands go.
##
##   ready    hold CAST to wind the rod back: the longer, the further
##   charging let go: the float flies out and lands on the water
##   waiting  fish nose up to it (animal.gd's lure). Tap now and you reel in.
##   nibble   the float twitches: something's at the bait. Wait...
##   bite     the float goes under: STRIKE (tap) in that moment and it's hooked
##   hooked   hold to reel in, let go to give line. The fish runs in surges;
##            reeling against a surge pulls the line tight, and past the red
##            it snaps. Tire it, bring it to the bank, and it's yours.
##
## A snapped line may take the rod with it (ROD_BREAK_SNAP), and a rod can
## crack landing a fish (ROD_BREAK_CATCH): tools wear out (company.gd).

const CAST_MIN := 5.0
const CAST_MAX := 24.0
const CHARGE_TIME := 1.2
const NOTICE_R := 12.0 # how far a fish sees the float
const BITE_WINDOW := 0.85 # seconds the float stays under
const LINE_MAX := 32.0
const REEL_SPEED := 2.4 # m/s against nothing
const ROD_LEN := 2.5
const ROD_BREAK_SNAP := 0.15
const ROD_BREAK_CATCH := 0.02

var battle
var player
var state := "ready"
var power := 0.0 # the cast being wound up, 0..1
var tension := 0.0 # 0..1+: above 1 the line snaps
var line_out := 0.0 # metres of line to a hooked fish
var stamina := 1.0 # the hooked fish's
var reeling := false
var caught := 0

var _t := 0.0 # time in this state
var _cast_t := -1.0 # the rod's swing forward (s since release; < 0: none)
var _float_from := Vector3.ZERO
var _float_to := Vector3.ZERO
var _float_at := Vector3.ZERO
var _fish = null # the fish taking an interest / on the line
var _nibble_for := 0.0
var _surge := 0.0 # seconds of surge left
var _calm := 2.0 # seconds till the next surge
var _side := 1.0
var _fish_dir := Vector3.FORWARD
var _bank_d := 0.0
var _over := 0.0 # time spent past the red
var _bend := 0.0
var _splash_t := 0.0

var _rod: Array = [] # MeshInstance3D segments, in the rig's body
var _line: MeshInstance3D
var _im: ImmediateMesh
var _float: Node3D
var _ring: MeshInstance3D


static func make(b):
	var f = load("res://scripts/fishing.gd").new()
	f.battle = b
	f.player = b.player
	return f


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.36, 0.2)
	wood.roughness = 0.7
	var widths := [0.022, 0.017, 0.012, 0.008]
	for i in widths.size():
		var cm := CylinderMesh.new()
		cm.top_radius = widths[i] * 0.8
		cm.bottom_radius = widths[i]
		cm.height = ROD_LEN / widths.size()
		cm.radial_segments = 6
		cm.rings = 1
		cm.material = wood
		var seg := MeshInstance3D.new()
		seg.mesh = cm
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.rig.body.add_child(seg)
		_rod.append(seg)
	# The reel, a little wooden drum on the butt.
	_im = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _im
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.92, 0.92, 0.86)
	_line.material_override = lm
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.top_level = true
	add_child(_line)
	# The float: red over white cork.
	_float = Node3D.new()
	_float.top_level = true
	add_child(_float)
	for k in 2:
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.12, 0.08) if k == 0 else Color(0.95, 0.93, 0.88)
		sm.material = m
		var b := MeshInstance3D.new()
		b.mesh = sm
		b.position = Vector3(0, 0.05 if k == 0 else -0.02, 0)
		b.scale = Vector3(1, 0.8 if k == 0 else 0.7, 1)
		_float.add_child(b)
	var rm := CylinderMesh.new()
	rm.top_radius = 0.3
	rm.bottom_radius = 0.3
	rm.height = 0.005
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.9, 0.95, 1.0, 0.45)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.material = rmat
	_ring = MeshInstance3D.new()
	_ring.mesh = rm
	_ring.top_level = true
	add_child(_ring)
	_float.visible = false
	_ring.visible = false


func _exit_tree() -> void:
	for seg in _rod:
		if is_instance_valid(seg):
			seg.queue_free()


func _terrain():
	return battle.field.terrain


func _water() -> float:
	return _terrain().water_y


func _wet(p: Vector3, margin := 0.2) -> bool:
	return _terrain().height(p.x, p.z) < _water() - margin


# ---------------------------------------------------------------- the button

func button_label() -> String:
	match state:
		"ready":
			return Lang.t("CAST")
		"charging":
			return Lang.t("LET GO")
		"flying":
			return "..."
		"waiting", "nibble", "bite":
			return Lang.t("STRIKE")
		"hooked":
			return Lang.t("REEL") if not reeling else Lang.t("REELING")
	return Lang.t("CAST")


func press() -> void:
	if not player.alive or rods_left() <= 0:
		return
	match state:
		"ready":
			state = "charging"
			power = 0.0
			_t = 0.0
		"waiting":
			_reel_in(Lang.t("Nothing on it. You reel in."))
		"nibble":
			_lose_fish(Lang.t("Too soon! You pulled the bait away from it."), true)
		"bite":
			_hook()
		"hooked":
			reeling = true


func release() -> void:
	match state:
		"charging":
			_cast()
		"hooked":
			reeling = false


func rods_left() -> int:
	return Company.item_count("fishing_rod") if Company.active else 1


# ---------------------------------------------------------------- states

func _go(s: String) -> void:
	state = s
	_t = 0.0


func _cast() -> void:
	var fwd: Vector3 = -player.camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d := lerpf(CAST_MIN, CAST_MAX, power)
	_float_from = _tip()
	_float_to = player.global_position + fwd * d
	_float_to.y = _water()
	_cast_t = 0.0
	battle.play_sound("swish", player.global_position + Vector3.UP * 1.6, -4.0)
	_go("flying")


func _land() -> void:
	if not _wet(_float_to, 0.15):
		_float_at = _float_to
		_float_at.y = _terrain().height(_float_to.x, _float_to.z) + 0.05
		_reel_in(Lang.t("On the bank. Reel in and try again."))
		return
	_float_at = _float_to
	battle.play_sound("plop", _float_at, -6.0)
	_ripple(1.0)
	_go("waiting")


func _reel_in(msg: String) -> void:
	if msg != "":
		battle.hud.show_message(msg, 2.0)
	if _fish != null and is_instance_valid(_fish):
		_fish.lure = null
		_fish.hooked = false
	_fish = null
	tension = 0.0
	reeling = false
	battle.play_sound("reel", player.global_position + Vector3.UP * 1.2, -8.0)
	_go("ready")


func _lose_fish(msg: String, scare := false) -> void:
	if _fish != null and is_instance_valid(_fish) and _fish.alive:
		_fish.hooked = false
		_fish.lure = null
		if scare:
			_fish.scare(player.global_position)
	_fish = null
	_reel_in(msg)


func _hook() -> void:
	if _fish == null or not is_instance_valid(_fish) or not _fish.alive:
		_reel_in("")
		return
	_fish.hooked = true
	_fish.lure = null
	var to: Vector3 = _fish.global_position - player.global_position
	to.y = 0.0
	line_out = to.length()
	_fish_dir = to.normalized()
	# Where the water starts, between you and it: bring it there and it's landed.
	_bank_d = 0.0
	var k := 0.0
	while k < line_out:
		if _wet(player.global_position + _fish_dir * k, 0.3):
			break
		k += 0.4
	_bank_d = k
	stamina = 1.0
	_surge = 1.2 # it fights at once
	_calm = 0.0
	_side = 1.0 if randf() < 0.5 else -1.0
	tension = 0.4
	battle.play_sound("splash", _fish.global_position, -2.0)
	battle.hud.show_message(Lang.t("Hooked! Hold REEL; let go when it runs."), 2.4)
	_go("hooked")


func _process(delta: float) -> void:
	_t += delta
	if not player.alive:
		return
	if rods_left() <= 0 and state != "ready":
		_reel_in("")
	match state:
		"charging":
			power = minf(1.0, _t / CHARGE_TIME)
		"flying":
			_cast_t += delta
			var k := clampf(_cast_t / 0.9, 0.0, 1.0)
			_float_at = _float_from.lerp(_float_to, k) + Vector3.UP * sin(k * PI) * (2.0 + 4.0 * power)
			if k >= 1.0:
				_land()
		"waiting":
			_float_at.y = _water() + 0.02 * sin(_t * 2.2)
			_wait_tick(delta)
		"nibble":
			_nibble_for -= delta
			_float_at.y = _water() - (0.05 if fmod(_t, 0.7) < 0.12 else 0.0) + 0.02 * sin(_t * 2.2)
			if fmod(_t, 0.7) < delta:
				_ripple(0.5)
			if _fish == null or not is_instance_valid(_fish) or not _fish.alive:
				_go("waiting")
			elif _nibble_for <= 0.0:
				_go("bite")
				battle.play_sound("plop", _float_at, -2.0)
				_ripple(1.0)
		"bite":
			_float_at.y = _water() - 0.16
			if _t > BITE_WINDOW:
				_lose_fish(Lang.t("It took the bait and was gone. Strike when the float goes under."))
		"hooked":
			_fight(delta)
	if _cast_t >= 0.0 and state != "flying":
		_cast_t += delta
	_draw_gear(delta)


## Fish about notice the float, and one comes to it.
func _wait_tick(delta: float) -> void:
	if player.global_position.distance_to(_float_at) > LINE_MAX:
		_reel_in("")
		return
	if _fish == null:
		for e in battle.enemies:
			if e.get("rig_kind") != "animal" or e.kind != "fish" or not e.alive or e.hooked:
				continue
			if e.global_position.distance_to(_float_at) < NOTICE_R and e._calm_t <= 0.0 and randf() < 0.45 * delta:
				_fish = e
				e.lure = _float_at
				break
	elif not is_instance_valid(_fish) or not _fish.alive or _fish.lure == null:
		_fish = null # (it lost interest, or was scared off)
	elif _fish.global_position.distance_to(_float_at) < 0.8:
		_nibble_for = randf_range(1.2, 3.6)
		_go("nibble")


## The fight: the fish runs in surges and rests between; reeling gains
## line, giving lets it take line. Reel through a surge and the tension
## climbs past what the line can bear.
func _fight(delta: float) -> void:
	if _fish == null or not is_instance_valid(_fish) or not _fish.alive:
		_reel_in("")
		return
	if _surge > 0.0:
		_surge -= delta
		if _surge <= 0.0:
			_calm = randf_range(1.4, 3.2) * lerpf(1.6, 1.0, stamina)
	else:
		_calm -= delta
		if _calm <= 0.0:
			_surge = randf_range(0.6, 1.5) * lerpf(0.5, 1.0, stamina)
			_side = -_side if randf() < 0.6 else _side
			battle.play_sound("splash", _fish.global_position, -4.0)
	var pull := (1.0 if _surge > 0.0 else 0.28) * lerpf(0.35, 1.0, stamina)
	var target := 0.0
	if reeling:
		target = 0.22 + pull * 0.92
		line_out -= REEL_SPEED * (1.0 - pull * 0.85) * delta
		if fmod(_t, 0.3) < delta:
			battle.play_sound("reel", player.global_position + Vector3.UP * 1.2, -10.0)
	else:
		target = pull * 0.4
		line_out += pull * 2.6 * delta
	tension = move_toward(tension, target, 2.6 * delta)
	stamina = maxf(0.0, stamina - (0.03 + tension * 0.07) * delta)
	if tension >= 1.0:
		_over += delta
		if _over > 0.12:
			_snap()
			return
	else:
		_over = 0.0
	# It swims across as well as away.
	_fish_dir = _fish_dir.rotated(Vector3.UP, _side * pull * 0.22 * delta)
	var at: Vector3 = player.global_position + _fish_dir * line_out
	if not _wet(at, 0.25) and line_out > _bank_d + 1.0:
		# The far shallows: it can't run further that way.
		line_out -= pull * 2.6 * delta
		_side = -_side
		at = player.global_position + _fish_dir * line_out
	at.y = _water() - 0.12
	_fish.global_position = at
	_fish.rotation.y = atan2(_fish_dir.x, _fish_dir.z) + _side * 0.6
	_float_at = at + Vector3.UP * 0.05
	_splash_t -= delta
	if _surge > 0.0 and _splash_t <= 0.0:
		_splash_t = 0.25
		_ripple(0.8)
	if line_out > LINE_MAX:
		_lose_fish(Lang.t("It ran out all your line and broke away."))
		return
	if line_out <= maxf(_bank_d + 0.3, 1.5):
		_landed()


func _snap() -> void:
	var msg := Lang.t("SNAP! The line parted and the fish is gone. Let go when it runs.")
	if Company.active and randf() < ROD_BREAK_SNAP:
		Company.add_item("fishing_rod", -1)
		msg = Lang.t("CRACK! The rod broke with the line.") + " " + (Lang.t("You take another from the wagon.") if rods_left() > 0 else Lang.t("That was your last rod."))
	_lose_fish(msg)
	battle.play_sound("crack", player.global_position + Vector3.UP * 1.5, -8.0)


func _landed() -> void:
	var f = _fish
	_fish = null
	f.hooked = false
	f.alive = false
	battle.enemies.erase(f)
	battle.on_game_down(f)
	caught += 1
	# Flapping on the bank at your feet, then into the creel.
	var at: Vector3 = player.global_position + _fish_dir * 1.2
	at.y = _terrain().height(at.x, at.z) + 0.1
	var tw: Tween = f.create_tween()
	tw.tween_property(f, "global_position", at, 0.4)
	tw.tween_property(f, "rotation:z", PI * 0.5, 0.2)
	tw.tween_interval(1.4)
	tw.tween_callback(f.queue_free)
	battle.play_sound("splash", at, -6.0)
	var msg := ""
	if Company.active and randf() < ROD_BREAK_CATCH:
		Company.add_item("fishing_rod", -1)
		msg = Lang.t("The rod cracked landing it.")
	tension = 0.0
	reeling = false
	if msg != "":
		battle.hud.show_message(msg, 2.0)
	_go("ready")


func _ripple(size: float) -> void:
	_ring.visible = true
	_ring.global_position = Vector3(_float_at.x, _water() + 0.01, _float_at.z)
	_ring.scale = Vector3.ONE * 0.3 * size
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_ring, "scale", Vector3.ONE * 2.2 * size, 0.9)
	tw.tween_property(_ring, "transparency", 1.0, 0.9).from(0.0)


# ---------------------------------------------------------------- the rod and line

## Where your hands go on the rod (player_body.gd, body space).
func pose(rig) -> void:
	rig.hand_item = "rod"
	var r := Vector3(0.24, 0.98, -0.22)
	var l := Vector3(0.15, 1.12, -0.5)
	match state:
		"charging":
			var k := smoothstep(0.0, 1.0, power)
			r = r.lerp(Vector3(0.3, 1.42, 0.02), k)
			l = l.lerp(Vector3(0.24, 1.62, -0.12), k)
		"hooked":
			r = Vector3(0.22, 1.02, -0.18)
			l = Vector3(0.12, 1.36, -0.42)
			if reeling:
				var a := _t * 14.0
				r += Vector3(0, sin(a) * 0.035, cos(a) * 0.035)
	if _cast_t >= 0.0 and _cast_t < 0.35:
		# The snap forward.
		var k2 := smoothstep(0.0, 0.35, _cast_t)
		r = Vector3(0.3, 1.42, 0.02).lerp(Vector3(0.22, 1.08, -0.38), k2)
		l = Vector3(0.24, 1.62, -0.12).lerp(Vector3(0.14, 1.18, -0.66), k2)
	rig.t_hand_r = r
	rig.t_hand_l = l
	rig.pose_rate = 18.0


## The rod tip in the world.
func _tip() -> Vector3:
	if _rod.is_empty():
		return player.global_position + Vector3.UP * 2.0
	var last: MeshInstance3D = _rod[_rod.size() - 1]
	return last.global_transform * Vector3(0, ROD_LEN / _rod.size() * 0.5, 0)


func _draw_gear(delta: float) -> void:
	var rig = player.rig
	var hr: Vector3 = rig._hand_r
	var hl: Vector3 = rig._hand_l
	var dir := (hl - hr).normalized()
	if dir.length_squared() < 0.5:
		dir = Vector3(0, 0.4, -1).normalized()
	# The rod bends toward the line, more with the strain.
	var want_bend := tension * 0.9 if state == "hooked" else (0.15 if state in ["nibble", "bite"] else 0.05)
	_bend = move_toward(_bend, want_bend, 3.0 * delta)
	var to_float_local: Vector3 = rig.body.global_transform.affine_inverse() * _float_at - hr
	var pull_dir := to_float_local.normalized() if state != "ready" and state != "charging" else Vector3(0, -1, 0)
	var p := hr - dir * 0.3
	var d := dir
	var seg_len := ROD_LEN / _rod.size()
	for i in _rod.size():
		var seg: MeshInstance3D = _rod[i]
		d = d.lerp(pull_dir, _bend * 0.22 * (i + 1) / _rod.size()).normalized()
		var mid := p + d * seg_len * 0.5
		seg.transform = Transform3D(_basis_y(d), mid)
		p += d * seg_len
	var tip := _tip()
	_im.clear_surfaces()
	if state in ["ready", "charging"]:
		_float.visible = false
		# A short dangle from the tip.
		_im.surface_begin(Mesh.PRIMITIVE_LINES)
		_im.surface_add_vertex(tip)
		_im.surface_add_vertex(tip + Vector3.DOWN * 0.5)
		_im.surface_end()
		return
	_float.visible = state != "hooked"
	_float.global_position = _float_at
	var end := _float_at
	var sag := 0.0 if state == "hooked" else 0.18 * tip.distance_to(end) * (1.0 - tension)
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var prev := tip
	for i in range(1, 13):
		var k := i / 12.0
		var q := tip.lerp(end, k) + Vector3.DOWN * sag * sin(k * PI) * (0.4 if state == "flying" else 1.0)
		_im.surface_add_vertex(prev)
		_im.surface_add_vertex(q)
		prev = q
	_im.surface_end()


static func _basis_y(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
