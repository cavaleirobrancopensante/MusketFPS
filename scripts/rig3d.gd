extends Node3D
## A low-poly 3D character built from primitive meshes (boxes, cylinders,
## spheres) and animated procedurally: no model files, no animation files.
##
## kinds: "soldier" (your musketeers), "officer" (you), "lizard".
##
## How it moves:
##   - The weapon (musket or cleaver hand) is posed in body space, eased
##     toward a target pose every frame.
##   - Arms are solved with two-bone IK from the shoulders to hand targets,
##     so hands always stay on the musket whatever it does.
##   - Legs use a simple walk cycle driven by movement speed.
## Units set `anim`, `anim_time`, `facing`, `move_speed` and `tint`; the rig
## turns those into a pose (_npc_pose). The player's own body sets `manual`
## and writes the pose targets directly (see player_body.gd).
##
## Body space: the character faces -Z, +X is its right, feet at y = 0.

const COAT := Color(0.16, 0.24, 0.55)
const COAT_OFFICER := Color(0.1, 0.13, 0.3)
const WHITE := Color(0.9, 0.88, 0.8)
const SKIN := Color(0.85, 0.66, 0.5)
const BLACK := Color(0.08, 0.08, 0.1)
const WOOD := Color(0.42, 0.26, 0.12)
const STEEL := Color(0.62, 0.64, 0.68)
const GOLD := Color(0.85, 0.68, 0.2)
const RED := Color(0.58, 0.1, 0.1)
const PACK := Color(0.3, 0.2, 0.12)
const ROLL := Color(0.55, 0.55, 0.5)
const HIDE := Color(0.3, 0.5, 0.22)
const HIDE_DARK := Color(0.18, 0.31, 0.13)
const BELLY := Color(0.62, 0.66, 0.38)
const EYE := Color(1.0, 0.85, 0.1)
const BONE := Color(0.88, 0.83, 0.7)
const CREST := Color(0.62, 0.16, 0.1)

## Musket geometry (musket space: grip at origin, muzzle toward -Z).
const MUZZLE := 1.05
const BUTT := 0.45
const FORESTOCK := 0.3 # where the left hand holds it

static var _materials := {}
static var _meshes := {}

var kind := "soldier"
var facing := Vector3.FORWARD
var anim := "idle"
var anim_time := 0.0
var move_speed := 0.0
var tint := Color.WHITE

# --- Pose targets (written by _npc_pose, or by the player when manual).
var manual := false
var t_grip := Vector3(0.22, 1.12, 0.02)
var t_dir := Vector3(0, 1, 0.15)
var t_hand_r = null # Vector3 in body space, or null = on the musket's wrist
var t_hand_l = null # Vector3, or null = on the forestock
var t_lean := 0.0
var t_jaw := 0.0
var aim_pitch := 0.0 # manual only: upper body follows the camera's pitch
var pose_rate := 14.0
var bayonet_on := true
var bayonet_in_hand := false
var ramrod_on := false
var show_head := true

# --- Smoothed state.
var _grip := Vector3(0.22, 1.12, 0.02)
var _wdir := Vector3(0, 1, 0.15).normalized()
var _hand_r := Vector3(0.3, 0.9, 0.0)
var _hand_l := Vector3(-0.3, 0.9, 0.0)
var _lean := 0.0
var _jaw := 0.0
var _walk_phase := 0.0
var _dead := false
var _last_tint := Color.WHITE

# --- Parts.
var body: Node3D
var spine: Node3D
var head: Node3D
var jaw: Node3D
var musket: Node3D
var bayonet: Node3D
var hand_bayonet: Node3D
var ramrod: MeshInstance3D
var cleaver: Node3D
var _arm := {} # name -> MeshInstance3D
var _leg := {}
var _tail: Array = []
var _all_meshes: Array = []
var _fp_hide: Array = [] # hidden in first person
var _overlay: StandardMaterial3D

var _shoulder_r := Vector3(0.23, 0.5, 0.0) # spine space
var _shoulder_l := Vector3(-0.23, 0.5, 0.0)
var _upper_len := 0.33
var _fore_len := 0.31
var _hip_y := 0.92
var _hip_x := 0.11


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	spine = Node3D.new()
	body.add_child(spine)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if kind == "lizard":
		_build_lizard()
		scale = Vector3.ONE * 1.12
	else:
		_build_soldier()
	_update(0.0, true)


# ---------------------------------------------------------------- building

static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		_materials[key] = m
	return _materials[key]


static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func _sphere_mesh(r: float) -> SphereMesh:
	var key := "s%s" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


static func _cyl_mesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var key := "c%s_%s_%s" % [r_top, r_bot, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = 8
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


func _part(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_all_meshes.append(mi)
	return mi


## A limb segment: a unit-length box along -Z, scaled and placed each frame.
func _segment(name: String, width: float, col: Color, store: Dictionary) -> void:
	var mi := _part(body, _box_mesh(Vector3(width, width, 1.0)), col, Vector3.ZERO)
	store[name] = mi


func _build_soldier() -> void:
	var officer := kind == "officer"
	var coat := COAT_OFFICER if officer else COAT
	spine.position = Vector3(0, _hip_y, 0)
	# Torso, coat tails, crossbelts, pack.
	_part(spine, _box_mesh(Vector3(0.42, 0.56, 0.24)), coat, Vector3(0, 0.28, 0))
	_part(spine, _box_mesh(Vector3(0.4, 0.3, 0.22)), coat, Vector3(0, -0.08, 0.02))
	if officer:
		_part(spine, _box_mesh(Vector3(0.44, 0.04, 0.26)), RED, Vector3(0, 0.02, 0)) # sash
		_fp_hide.append(_part(spine, _box_mesh(Vector3(0.12, 0.03, 0.14)), GOLD, Vector3(0.22, 0.56, 0)))
		_fp_hide.append(_part(spine, _box_mesh(Vector3(0.12, 0.03, 0.14)), GOLD, Vector3(-0.22, 0.56, 0)))
	else:
		_part(spine, _box_mesh(Vector3(0.06, 0.62, 0.02)), WHITE, Vector3(0, 0.28, -0.125), Vector3(0, 0, 38))
		_part(spine, _box_mesh(Vector3(0.06, 0.62, 0.02)), WHITE, Vector3(0, 0.28, -0.125), Vector3(0, 0, -38))
		_part(spine, _box_mesh(Vector3(0.36, 0.34, 0.14)), PACK, Vector3(0, 0.3, 0.19))
		_part(spine, _box_mesh(Vector3(0.42, 0.09, 0.1)), ROLL, Vector3(0, 0.51, 0.19))
	# Head and hat.
	head = Node3D.new()
	head.position = Vector3(0, 0.62, 0)
	spine.add_child(head)
	_part(head, _cyl_mesh(0.06, 0.06, 0.08), SKIN, Vector3(0, -0.02, 0))
	_part(head, _sphere_mesh(0.11), SKIN, Vector3(0, 0.1, 0))
	if officer:
		_part(head, _box_mesh(Vector3(0.42, 0.12, 0.1)), BLACK, Vector3(0, 0.22, 0)) # bicorne
		_part(head, _box_mesh(Vector3(0.05, 0.05, 0.02)), GOLD, Vector3(0.0, 0.25, -0.05))
	else:
		_part(head, _cyl_mesh(0.115, 0.105, 0.22), BLACK, Vector3(0, 0.28, 0)) # shako
		_part(head, _box_mesh(Vector3(0.2, 0.02, 0.08)), BLACK, Vector3(0, 0.18, -0.12))
		_part(head, _box_mesh(Vector3(0.06, 0.06, 0.02)), GOLD, Vector3(0, 0.3, -0.115))
	# Arms (placed by IK every frame).
	_segment("r_upper", 0.11, coat, _arm)
	_segment("r_fore", 0.095, coat, _arm)
	_segment("l_upper", 0.11, coat, _arm)
	_segment("l_fore", 0.095, coat, _arm)
	_arm["r_hand"] = _part(body, _sphere_mesh(0.05), SKIN, Vector3.ZERO)
	_arm["l_hand"] = _part(body, _sphere_mesh(0.05), SKIN, Vector3.ZERO)
	_segment("r_cuff", 0.112, RED if officer else WHITE, _arm)
	_segment("l_cuff", 0.112, RED if officer else WHITE, _arm)
	# Legs.
	for side in ["l", "r"]:
		_segment(side + "_thigh", 0.13, WHITE, _leg)
		_segment(side + "_shin", 0.115, BLACK, _leg)
		_leg[side + "_foot"] = _part(body, _box_mesh(Vector3(0.11, 0.07, 0.24)), BLACK, Vector3.ZERO)
	_build_musket()


func _build_musket() -> void:
	musket = Node3D.new()
	body.add_child(musket)
	_part(musket, _box_mesh(Vector3(0.045, 0.11, 0.5)), WOOD, Vector3(0, -0.025, 0.2)) # stock
	_part(musket, _box_mesh(Vector3(0.04, 0.05, 0.75)), WOOD, Vector3(0, -0.01, -0.36)) # forestock
	_part(musket, _cyl_mesh(0.013, 0.013, MUZZLE), STEEL, Vector3(0, 0.018, -MUZZLE * 0.5), Vector3(90, 0, 0))
	_part(musket, _box_mesh(Vector3(0.02, 0.05, 0.08)), STEEL, Vector3(0.028, 0.01, -0.02)) # lock
	bayonet = Node3D.new()
	bayonet.position = Vector3(0, 0.018, -MUZZLE)
	musket.add_child(bayonet)
	_build_bayonet(bayonet)
	hand_bayonet = Node3D.new()
	body.add_child(hand_bayonet)
	_build_bayonet(hand_bayonet)
	hand_bayonet.visible = false
	ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
	ramrod.visible = false


func _build_bayonet(parent: Node3D) -> void:
	_part(parent, _cyl_mesh(0.018, 0.018, 0.08), STEEL, Vector3(0, -0.02, 0.0), Vector3(90, 0, 0))
	_part(parent, _box_mesh(Vector3(0.012, 0.03, 0.42)), Color(0.82, 0.84, 0.88), Vector3(0, -0.02, -0.23))


func _build_lizard() -> void:
	_hip_y = 0.72
	_hip_x = 0.17
	_upper_len = 0.36
	_fore_len = 0.36
	_shoulder_r = Vector3(0.3, 0.55, -0.04)
	_shoulder_l = Vector3(-0.3, 0.55, -0.04)
	spine.position = Vector3(0, _hip_y, 0)
	_part(spine, _box_mesh(Vector3(0.5, 0.66, 0.36)), HIDE, Vector3(0, 0.3, 0))
	_part(spine, _box_mesh(Vector3(0.34, 0.5, 0.06)), BELLY, Vector3(0, 0.28, -0.19))
	for i in 5:
		_part(spine, _box_mesh(Vector3(0.05, 0.1, 0.08)), CREST, Vector3(0, 0.1 + i * 0.13, 0.2), Vector3(-30, 0, 0))
	# Head jutting forward from the top of the torso.
	head = Node3D.new()
	head.position = Vector3(0, 0.66, -0.12)
	spine.add_child(head)
	_part(head, _box_mesh(Vector3(0.28, 0.24, 0.34)), HIDE, Vector3(0, 0.08, -0.08))
	_part(head, _box_mesh(Vector3(0.2, 0.12, 0.28)), HIDE, Vector3(0, 0.08, -0.36)) # snout
	_part(head, _box_mesh(Vector3(0.06, 0.04, 0.04)), EYE, Vector3(0.1, 0.16, -0.2))
	_part(head, _box_mesh(Vector3(0.06, 0.04, 0.04)), EYE, Vector3(-0.1, 0.16, -0.2))
	for i in 4:
		_part(head, _box_mesh(Vector3(0.04, 0.12, 0.06)), CREST, Vector3(0, 0.24, 0.05 - i * 0.09), Vector3(-25, 0, 0))
	jaw = Node3D.new()
	jaw.position = Vector3(0, 0.0, -0.08)
	head.add_child(jaw)
	_part(jaw, _box_mesh(Vector3(0.18, 0.06, 0.4)), HIDE_DARK, Vector3(0, -0.03, -0.2))
	for i in 4:
		_part(jaw, _box_mesh(Vector3(0.14, 0.03, 0.015)), BONE, Vector3(0, 0.01, -0.12 - i * 0.08))
	# Tail: four segments trailing behind the hips.
	for i in 4:
		var w := 0.2 - i * 0.04
		_tail.append(_part(body, _box_mesh(Vector3(w, w, 1.0)), HIDE_DARK, Vector3.ZERO))
	# Arms with claws; cleaver in the right hand.
	_segment("r_upper", 0.12, HIDE, _arm)
	_segment("r_fore", 0.1, HIDE, _arm)
	_segment("l_upper", 0.12, HIDE, _arm)
	_segment("l_fore", 0.1, HIDE, _arm)
	_arm["r_hand"] = _part(body, _sphere_mesh(0.06), HIDE_DARK, Vector3.ZERO)
	_arm["l_hand"] = _part(body, _box_mesh(Vector3(0.12, 0.06, 0.12)), BONE, Vector3.ZERO)
	cleaver = Node3D.new()
	body.add_child(cleaver)
	_part(cleaver, _box_mesh(Vector3(0.035, 0.035, 0.32)), WOOD, Vector3(0, 0, -0.12))
	_part(cleaver, _box_mesh(Vector3(0.02, 0.2, 0.26)), STEEL, Vector3(0, 0.1, -0.36))
	# Digitigrade legs: thigh, shin, long foot.
	for side in ["l", "r"]:
		_segment(side + "_thigh", 0.16, HIDE, _leg)
		_segment(side + "_shin", 0.12, HIDE, _leg)
		_leg[side + "_foot"] = _part(body, _box_mesh(Vector3(0.14, 0.07, 0.3)), HIDE_DARK, Vector3.ZERO)


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if _dead:
		return
	_update(delta, false)


func _update(delta: float, snap: bool) -> void:
	# Turn the body to face where the unit wants to look.
	var want := atan2(-facing.x, -facing.z)
	var parent_yaw := 0.0
	var p := get_parent() as Node3D
	if p != null:
		parent_yaw = p.global_rotation.y
	body.rotation.y = lerp_angle(body.rotation.y, want - parent_yaw, 1.0 if snap else 1.0 - exp(-10.0 * delta))

	if not manual:
		_npc_pose()
	var k := 1.0 if snap else 1.0 - exp(-pose_rate * delta)
	var kh := 1.0 if snap else 1.0 - exp(-pose_rate * 1.6 * delta)
	_lean = lerpf(_lean, t_lean, k)
	_jaw = lerpf(_jaw, t_jaw, k)
	spine.rotation.x = -_lean
	if head != null:
		head.visible = show_head
	# First person: hide what would sit right on the lens (epaulettes).
	for mi in _fp_hide:
		mi.visible = show_head

	if kind == "lizard":
		_update_lizard(delta, kh)
	else:
		_update_soldier(delta, k, kh)
	_update_legs(delta)
	_apply_tint()


func _update_soldier(_delta: float, k: float, kh: float) -> void:
	_grip = _grip.lerp(t_grip, k)
	_wdir = _wdir.slerp(t_dir.normalized(), k).normalized()
	var grip := _grip
	var wdir := _wdir
	var pitch := Basis(Vector3.RIGHT, aim_pitch)
	var pivot := Vector3(0.1, 1.45, 0.0)
	if aim_pitch != 0.0:
		grip = pivot + pitch * (grip - pivot)
		wdir = pitch * wdir
	musket.transform = Transform3D(_look_basis(wdir), grip)
	bayonet.visible = bayonet_on

	var r_target: Vector3 = grip if t_hand_r == null else _pitched(t_hand_r, pitch, pivot)
	var l_target: Vector3 = grip + wdir * FORESTOCK if t_hand_l == null else _pitched(t_hand_l, pitch, pivot)
	_hand_r = _hand_r.lerp(r_target, kh)
	_hand_l = _hand_l.lerp(l_target, kh)
	_place_arm("r", spine.transform * _shoulder_r, _hand_r, Vector3(1.0, -1.0, 0.4))
	_place_arm("l", spine.transform * _shoulder_l, _hand_l, Vector3(-1.0, -1.0, 0.4))

	hand_bayonet.visible = bayonet_in_hand
	if bayonet_in_hand:
		hand_bayonet.transform = Transform3D(_look_basis(wdir), _hand_r)
	ramrod.visible = ramrod_on
	if ramrod_on:
		var muzzle := grip + wdir * MUZZLE
		if (_hand_r - muzzle).dot(wdir) > 0.02:
			_place_segment(ramrod, _hand_r, muzzle)
		else:
			ramrod.visible = false


func _pitched(v: Vector3, pitch: Basis, pivot: Vector3) -> Vector3:
	if aim_pitch == 0.0:
		return v
	return pivot + pitch * (v - pivot)


func _update_lizard(delta: float, kh: float) -> void:
	_hand_r = _hand_r.lerp(t_hand_r if t_hand_r != null else Vector3(0.36, 0.9, -0.3), kh)
	_hand_l = _hand_l.lerp(t_hand_l if t_hand_l != null else Vector3(-0.36, 0.95, -0.25), kh)
	var er := _place_arm("r", spine.transform * _shoulder_r, _hand_r, Vector3(1.0, -0.6, 0.6))
	_place_arm("l", spine.transform * _shoulder_l, _hand_l, Vector3(-1.0, -0.6, 0.6))
	# Cleaver continues the line of the forearm.
	var fdir := (_hand_r - er).normalized()
	cleaver.transform = Transform3D(_look_basis(fdir), _hand_r)
	jaw.rotation.x = _jaw * 0.6
	# Tail: hangs back from the hips and sways as he runs.
	var base := Vector3(0, _hip_y + 0.05, 0.18)
	var sway := sin(anim_time * 9.0) * clampf(move_speed / 4.0, 0.15, 1.0)
	var dir := Vector3(0, -0.35, 1).normalized()
	for i in _tail.size():
		var seg_dir := Basis(Vector3.UP, sway * 0.25 * (i + 1)) * dir
		var end := base + seg_dir * 0.32
		_place_segment(_tail[i], base, end)
		base = end
		dir = (dir + Vector3(0, -0.12, 0)).normalized()


func _update_legs(delta: float) -> void:
	var walking := move_speed > 0.4 and not anim in ["windup", "strike"]
	if walking:
		_walk_phase += delta * (4.0 + move_speed * 1.6)
	else:
		_walk_phase = lerpf(_walk_phase, roundf(_walk_phase / PI) * PI, 1.0 - exp(-8.0 * delta))
	var amp := clampf(move_speed / 4.0, 0.0, 1.0) * 0.55
	for side in ["l", "r"]:
		var sgn := 1.0 if side == "l" else -1.0
		var swing := sin(_walk_phase) * amp * sgn
		var lift := maxf(0.0, cos(_walk_phase) * sgn) * amp * 1.3
		var hip := Vector3(_hip_x * (-1.0 if side == "l" else 1.0), _hip_y, 0.0)
		if kind == "lizard":
			# Digitigrade: thigh forward-down, shin back-down, long flat foot.
			var rot := Basis(Vector3.RIGHT, swing)
			var thigh_dir := rot * Vector3(0, -0.72, -0.69).normalized()
			var knee := hip + thigh_dir * 0.42
			var shin_dir := rot * Basis(Vector3.RIGHT, -lift) * Vector3(0, -0.8, 0.6).normalized()
			var ankle := knee + shin_dir * 0.45
			ankle.y = maxf(ankle.y, 0.04 + lift * 0.2)
			_place_segment(_leg[side + "_thigh"], hip, knee)
			_place_segment(_leg[side + "_shin"], knee, ankle)
			_leg[side + "_foot"].transform = Transform3D(Basis(), ankle + Vector3(0, -0.01, -0.12))
		else:
			var thigh_dir := Basis(Vector3.RIGHT, swing) * Vector3.DOWN
			var knee := hip + thigh_dir * 0.44
			var shin_dir := Basis(Vector3.RIGHT, swing - lift) * Vector3.DOWN
			var ankle := knee + shin_dir * 0.44
			_place_segment(_leg[side + "_thigh"], hip, knee)
			_place_segment(_leg[side + "_shin"], knee, ankle)
			_leg[side + "_foot"].transform = Transform3D(Basis(), ankle + Vector3(0, -0.0, -0.05))
	# A little bob in the stride.
	spine.position.y = _hip_y + absf(cos(_walk_phase)) * amp * 0.06


## Poses for the AI-driven units, from the same animation names the 2D
## sprites use.
func _npc_pose() -> void:
	pose_rate = 14.0
	ramrod_on = false
	t_hand_r = null
	t_hand_l = null
	t_jaw = 0.0
	var swing := sin(_walk_phase)
	if kind == "lizard":
		t_lean = 0.5
		match anim:
			"walk":
				t_lean = 0.62
				t_hand_r = Vector3(0.38, 0.85, -0.3 + 0.22 * swing)
				t_hand_l = Vector3(-0.38, 0.9, -0.3 - 0.22 * swing)
				t_jaw = 0.25
			"windup":
				t_lean = 0.2
				t_hand_r = Vector3(0.3, 1.9, 0.15)
				t_hand_l = Vector3(-0.38, 1.7, -0.1)
				t_jaw = 1.0
				pose_rate = 10.0
			"strike":
				t_lean = 0.8
				t_hand_r = Vector3(0.08, 0.85, -0.8)
				t_hand_l = Vector3(-0.3, 0.95, -0.5)
				t_jaw = 0.5
				pose_rate = 30.0
			"stagger":
				t_lean = 0.05
				t_hand_r = Vector3(0.6, 1.5, 0.2)
				t_hand_l = Vector3(-0.6, 1.5, 0.2)
				t_jaw = 0.8
		return

	t_lean = 0.0
	match anim:
		"idle", "walk":
			t_grip = Vector3(0.22, 1.12, 0.02)
			t_dir = Vector3(0, 1, 0.15)
			t_hand_l = Vector3(-0.28, 0.86, -0.04 - 0.15 * swing * clampf(move_speed / 4.0, 0.0, 1.0))
		"aim":
			t_grip = Vector3(0.12, 1.43, -0.32)
			t_dir = Vector3(0, 0.02, -1)
		"fire":
			t_grip = Vector3(0.12, 1.45, -0.22 if anim_time < 0.1 else -0.32)
			t_dir = Vector3(0, 0.1 if anim_time < 0.1 else 0.02, -1)
			pose_rate = 30.0
		"reload":
			t_grip = Vector3(0.06, 0.48, -0.3)
			t_dir = Vector3(0, 1, -0.1)
			var muzzle := t_grip + t_dir.normalized() * MUZZLE
			t_hand_l = t_grip + t_dir.normalized() * 0.72
			t_hand_r = muzzle + Vector3(0, 0.08 + 0.32 * absf(sin(anim_time * 5.0)), 0)
			ramrod_on = true
		"guard":
			t_grip = Vector3(0.18, 1.05, -0.25)
			t_dir = Vector3(0, 0.33, -1)
		"thrust":
			t_grip = Vector3(0.1, 1.2, -0.6)
			t_dir = Vector3(0, 0.05, -1)
			t_lean = 0.25
			pose_rate = 30.0


# ---------------------------------------------------------------- geometry

static func _look_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.97 else Vector3.BACK
	return Basis.looking_at(dir, up)


## Stretch a unit-length segment mesh from a to b.
func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var basis := _look_basis(d) * Basis.from_scale(Vector3(1, 1, l))
	mi.transform = Transform3D(basis, (a + b) * 0.5)


## Two-bone IK: shoulder -> elbow -> hand. The elbow bends toward `pole`.
## Out of reach, the arm stretches a little rather than letting go.
func _place_arm(side: String, shoulder: Vector3, hand: Vector3, pole: Vector3) -> Vector3:
	var l1 := _upper_len
	var l2 := _fore_len
	var to := hand - shoulder
	var d := to.length()
	var stretch := clampf(d / (l1 + l2 - 0.001), 1.0, 1.35)
	l1 *= stretch
	l2 *= stretch
	d = clampf(d, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var axis := to.normalized()
	var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole_dir := (pole - axis * pole.dot(axis)).normalized()
	var elbow := shoulder + axis * a + pole_dir * h
	var hand_pos := shoulder + axis * d
	_place_segment(_arm[side + "_upper"], shoulder, elbow)
	_place_segment(_arm[side + "_fore"], elbow, hand_pos)
	_arm[side + "_hand"].position = hand_pos
	var cuff_key := side + "_cuff"
	if _arm.has(cuff_key):
		var fd := (hand_pos - elbow).normalized()
		_place_segment(_arm[cuff_key], hand_pos - fd * 0.1, hand_pos - fd * 0.035)
	return elbow


# ---------------------------------------------------------------- look & death

func _apply_tint() -> void:
	if tint == _last_tint:
		return
	_last_tint = tint
	var use := not tint.is_equal_approx(Color.WHITE)
	if use:
		_overlay.albedo_color = Color(tint.r, tint.g * 0.6, tint.b * 0.4, 0.5)
	for mi in _all_meshes:
		mi.material_overlay = _overlay if use else null


## Muzzle position in world space (for smoke and flashes).
func muzzle_global() -> Vector3:
	if musket == null:
		return global_position + Vector3.UP * 1.4
	return musket.global_transform * Vector3(0, 0.018, -MUZZLE)


func die() -> void:
	_dead = true
	tint = Color(0.55, 0.55, 0.55)
	_apply_tint()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body, "rotation:x", PI * 0.47, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(body, "position:y", 0.12, 0.6)
