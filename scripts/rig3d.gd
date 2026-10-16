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
##
## Drawing: parts are not separate meshes. Each part is a record (unit box,
## cylinder or sphere + local transform + colour) and after every update the
## rig writes all its parts into ready-made float buffers (`cache`) that the
## Batcher draws for every rig at once with three MultiMeshes.
##
## Level of detail: bodies within 12 m update every frame, to 25 m every 2nd
## frame, beyond that every 4th, off-screen every 8th; small details (faces,
## buttons, teeth) are skipped beyond DETAIL_RANGE. Past 40 m units switch to
## sprites (see unit.gd).

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
const HAIR := Color(0.28, 0.18, 0.1)
const ROLL := Color(0.55, 0.55, 0.5)
const HIDE := Color(0.3, 0.5, 0.22)
const HIDE_DARK := Color(0.18, 0.31, 0.13)
const BELLY := Color(0.62, 0.66, 0.38)
const EYE := Color(1.0, 0.85, 0.1)
const BONE := Color(0.88, 0.83, 0.7)
const CREST := Color(0.62, 0.16, 0.1)
const SHIRT := Color(0.86, 0.83, 0.74)
const BUFF := Color(0.66, 0.5, 0.3)
const LEATHER := Color(0.36, 0.24, 0.14)
const RUST := Color(0.47, 0.36, 0.28)
const BROWNED := Color(0.3, 0.31, 0.33)

## Musket geometry (musket space: grip at origin, muzzle toward -Z).
const MUZZLE := 1.05
const BUTT := 0.45
const FORESTOCK := 0.3 # where the left hand holds it
const FP_SHOULDER_DROP := Vector3(0.0, -0.22, -0.04)

const DETAIL_RANGE := 16.0 # beyond this, small details are skipped
const NEAR_RANGE := 12.0 # within this, re-posed every frame
const MID_RANGE := 25.0 # within this, every 2nd frame; beyond, every 4th

const BOX := 0
const CYL := 1
const SPHERE := 2

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
var pitch_pivot := Vector3(0.1, 1.45, 0.0) # what the upper body tilts around
var pose_rate := 14.0
var bayonet_on := true
var bayonet_in_hand := false
var ramrod_on := false
var show_head := true
var _fp_hide: Array = [] # parts right under your eye (collar, epaulettes): hidden in first person
## A soldier's kit (Company gear ids: head, torso, primary, secondary) and
## pack ({water, rations, ammo}); empty means the regulation kit, full pack.
var gear := {}
var pack := {}

# --- Smoothed state.
var _grip := Vector3(0.22, 1.12, 0.02)
var _wdir := Vector3(0, 1, 0.15).normalized()
var _hand_r := Vector3(0.3, 0.9, 0.0)
var _hand_l := Vector3(-0.3, 0.9, 0.0)
var _lean := 0.0
var _lie := 0.0 # 1 = lying on his back asleep (camp), easing back up to 0 as he gets up
var _jaw := 0.0
var _walk_phase := 0.0
var _dead := false

# --- Parts.
var body: Node3D
var spine: Node3D
var head: Node3D
var jaw: Node3D
var musket: Node3D
var bayonet: Node3D
var hand_bayonet: Node3D
var ramrod := -1 # part id
var cleaver: Node3D
var shield: Node3D
var _shield_turn := 0.9 # radians the shield faces off to the left
var _arm := {} # name -> part id
var _leg := {}
var _tail: Array = []
var _sack := -1 # a ration sack (lizards eating from the wagon)
var _kneel := 0.0 # 0 standing, 1 down on one knee (smoothed)

# --- Part records (parallel arrays, indexed by part id).
var _nodes: Array = [] # the few Node3Ds parts ride on (body, spine, head...)
var _p_node: PackedInt32Array = PackedInt32Array() # index into _nodes
var _p_local: Array = [] # Transform3D in the parent's space (scale included)
var _p_scale: Array = [] # base scale (segments stretch only their length)
var _p_shape: PackedInt32Array = PackedInt32Array()
var _p_color: Array = []
var _p_vis: Array = [] # per-part visibility (e.g. the ramrod)
var _p_detail: Array = [] # small detail, skipped far away
var _detail := true
## Ready-to-draw buffers per shape: 12 floats transform + 4 colour per part.
var cache: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _batcher = null
var _frame_skip := 0
var _acc := 0.0
var _dead_t := 0.0

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
	_walk_phase = randf() * TAU # everyone out of step
	if kind == "lizard":
		_build_lizard()
		scale = Vector3.ONE * 1.12
	else:
		_build_soldier()
	_update(0.0, true)
	_batcher = get_tree().get_first_node_in_group("batcher")
	if _batcher != null:
		_batcher.add_rig(self)
	_emit()


func _exit_tree() -> void:
	if _batcher != null:
		_batcher.remove_rig(self)


func draw_enabled() -> bool:
	return visible and is_inside_tree()


## Re-pose and redraw at once (after being hidden as a far stand-in).
func refresh() -> void:
	_frame_skip = 0
	_acc = 0.0
	if not _dead:
		_update(0.0, true)
	_emit()


# ---------------------------------------------------------------- building

# Shape specs: [shape id, scale]. Unit box = 1 m cube, unit cylinder and
# sphere = 1 m across, so the scale is simply the part's size.
static func _box_mesh(size: Vector3) -> Array:
	return [BOX, size]


static func _sphere_mesh(r: float) -> Array:
	return [SPHERE, Vector3.ONE * r * 2.0]


static func _cyl_mesh(r_top: float, r_bot: float, h: float) -> Array:
	return [CYL, Vector3(r_top + r_bot, h, r_top + r_bot)]


## Add a part riding on `parent`. Returns its id.
func _part(parent: Node3D, spec: Array, col: Color, pos: Vector3, rot_deg := Vector3.ZERO, detail := false) -> int:
	var sc: Vector3 = spec[1]
	var rot := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	var ni := _nodes.find(parent)
	if ni < 0:
		_nodes.append(parent)
		ni = _nodes.size() - 1
	_p_node.append(ni)
	_p_local.append(Transform3D(rot * Basis.from_scale(sc), pos))
	_p_scale.append(sc)
	_p_shape.append(spec[0])
	_p_color.append(col)
	_p_vis.append(true)
	_p_detail.append(detail)
	return _p_node.size() - 1


func _set_pos(id: int, pos: Vector3) -> void:
	var t: Transform3D = _p_local[id]
	t.origin = pos
	_p_local[id] = t


## A limb segment: a unit-length box along -Z, scaled and placed each frame.
func _segment(name: String, width: float, col: Color, store: Dictionary) -> void:
	store[name] = _part(body, _box_mesh(Vector3(width, width, 1.0)), col, Vector3.ZERO)


func _build_soldier() -> void:
	var officer := kind == "officer"
	var g := {"head": "shako", "torso": "coat", "primary": "musket", "secondary": "bayonet"}
	g.merge(gear, true)
	if officer and not gear.has("torso"):
		g["torso"] = "officer_coat"
	if officer and not gear.has("head"):
		g["head"] = "bicorne"
	var torso := String(g["torso"])
	var coat := COAT_OFFICER if officer and torso == "officer_coat" else COAT
	var cuff := RED if officer and torso == "officer_coat" else WHITE
	var belt := WHITE
	if torso == "shirt":
		coat = SHIRT
		cuff = SHIRT.darkened(0.08)
		belt = LEATHER
	elif torso == "buffcoat":
		coat = BUFF
		cuff = BUFF.darkened(0.15)
		belt = LEATHER
	spine.position = Vector3(0, _hip_y, 0)
	# Torso, coat tails (not on a bare shirt), crossbelts, pack.
	_part(spine, _box_mesh(Vector3(0.42, 0.56, 0.24)), coat, Vector3(0, 0.28, 0))
	if officer or torso != "shirt":
		_part(spine, _box_mesh(Vector3(0.4, 0.3, 0.22)), coat, Vector3(0, -0.08, 0.02))
	else:
		_part(spine, _box_mesh(Vector3(0.4, 0.12, 0.22)), coat, Vector3(0, -0.01, 0.0)) # shirt tail
	if officer:
		_part(spine, _box_mesh(Vector3(0.44, 0.04, 0.26)), RED, Vector3(0, 0.02, 0)) # sash
		_part(spine, _box_mesh(Vector3(0.17, 0.42, 0.02)), WHITE, Vector3(0, 0.32, -0.125)) # lapels
		_part(spine, _box_mesh(Vector3(0.03, 0.42, 0.025)), GOLD, Vector3(0, 0.32, -0.13), Vector3.ZERO, true) # buttons
		_fp_hide.append(_part(spine, _cyl_mesh(0.085, 0.09, 0.07), RED, Vector3(0, 0.6, 0))) # high collar
		_fp_hide.append(_part(spine, _box_mesh(Vector3(0.12, 0.03, 0.14)), GOLD, Vector3(0.22, 0.56, 0)))
		_fp_hide.append(_part(spine, _box_mesh(Vector3(0.12, 0.03, 0.14)), GOLD, Vector3(-0.22, 0.56, 0)))
	else:
		_part(spine, _box_mesh(Vector3(0.06, 0.62, 0.02)), belt, Vector3(0, 0.28, -0.125), Vector3(0, 0, 38))
		_part(spine, _box_mesh(Vector3(0.06, 0.62, 0.02)), belt, Vector3(0, 0.28, -0.125), Vector3(0, 0, -38))
		_build_pack(belt)
	# Head and hat.
	head = Node3D.new()
	head.position = Vector3(0, 0.62, 0)
	spine.add_child(head)
	_part(head, _cyl_mesh(0.06, 0.06, 0.08), SKIN, Vector3(0, -0.02, 0))
	_part(head, _sphere_mesh(0.11), SKIN, Vector3(0, 0.1, 0))
	# Face: eyes and nose, hair at the back and sideburns.
	_part(head, _box_mesh(Vector3(0.025, 0.02, 0.01)), BLACK, Vector3(0.042, 0.125, -0.104), Vector3.ZERO, true)
	_part(head, _box_mesh(Vector3(0.025, 0.02, 0.01)), BLACK, Vector3(-0.042, 0.125, -0.104), Vector3.ZERO, true)
	_part(head, _box_mesh(Vector3(0.028, 0.045, 0.035)), SKIN.darkened(0.08), Vector3(0, 0.09, -0.112), Vector3.ZERO, true)
	_part(head, _box_mesh(Vector3(0.21, 0.13, 0.09)), HAIR, Vector3(0, 0.12, 0.065))
	_part(head, _box_mesh(Vector3(0.02, 0.07, 0.05)), HAIR, Vector3(0.105, 0.08, -0.01), Vector3.ZERO, true)
	_part(head, _box_mesh(Vector3(0.02, 0.07, 0.05)), HAIR, Vector3(-0.105, 0.08, -0.01), Vector3.ZERO, true)
	if String(g["head"]) == "bicorne":
		# Bicorne worn side to side: a crescent, tallest in the middle.
		_part(head, _cyl_mesh(0.118, 0.118, 0.05), BLACK, Vector3(0, 0.19, 0))
		_part(head, _box_mesh(Vector3(0.27, 0.15, 0.05)), BLACK, Vector3(-0.115, 0.26, 0), Vector3(0, 0, 20))
		_part(head, _box_mesh(Vector3(0.27, 0.15, 0.05)), BLACK, Vector3(0.115, 0.26, 0), Vector3(0, 0, -20))
		_part(head, _box_mesh(Vector3(0.5, 0.012, 0.055)), GOLD, Vector3(0, 0.196, 0), Vector3.ZERO, true) # gold edging
		_part(head, _cyl_mesh(0.035, 0.035, 0.012), RED, Vector3(-0.07, 0.28, -0.032), Vector3(90, 0, 0)) # cockade
		_part(head, _cyl_mesh(0.016, 0.016, 0.014), GOLD, Vector3(-0.07, 0.28, -0.036), Vector3(90, 0, 0))
	else:
		_build_hat(String(g["head"]))
	# Arms (placed by IK every frame).
	_segment("r_upper", 0.11, coat, _arm)
	_segment("r_fore", 0.095, coat, _arm)
	_segment("l_upper", 0.11, coat, _arm)
	_segment("l_fore", 0.095, coat, _arm)
	_arm["r_hand"] = _part(body, _sphere_mesh(0.05), SKIN, Vector3.ZERO)
	_arm["l_hand"] = _part(body, _sphere_mesh(0.05), SKIN, Vector3.ZERO)
	_segment("r_cuff", 0.112, cuff, _arm)
	_segment("l_cuff", 0.112, cuff, _arm)
	# Legs.
	for side in ["l", "r"]:
		_segment(side + "_thigh", 0.13, WHITE, _leg)
		_segment(side + "_shin", 0.115, BLACK, _leg)
		_leg[side + "_foot"] = _part(body, _box_mesh(Vector3(0.11, 0.07, 0.24)), BLACK, Vector3.ZERO)
	_build_musket(String(g["primary"]), String(g["secondary"]))
	if not officer:
		bayonet_on = String(g["secondary"]) != ""


func _build_hat(hat: String) -> void:
	match hat:
		"shako":
			_part(head, _cyl_mesh(0.115, 0.105, 0.22), BLACK, Vector3(0, 0.28, 0))
			_part(head, _box_mesh(Vector3(0.2, 0.02, 0.08)), BLACK, Vector3(0, 0.18, -0.12))
			_part(head, _box_mesh(Vector3(0.06, 0.06, 0.02)), GOLD, Vector3(0, 0.3, -0.115), Vector3.ZERO, true)
		"tricorne":
			# Crown, and a brim turned up on three sides into a triangle.
			_part(head, _cyl_mesh(0.1, 0.112, 0.09), BLACK, Vector3(0, 0.22, 0))
			for i in 3:
				var a := deg_to_rad(120.0 * i)
				var at := Vector3(sin(a), 0, -cos(a)) * -0.1
				_part(head, _box_mesh(Vector3(0.27, 0.08, 0.025)), BLACK, at + Vector3(0, 0.22, 0),
					Vector3(25, rad_to_deg(-a), 0))
		"cap":
			_part(head, _cyl_mesh(0.125, 0.115, 0.075), COAT, Vector3(0, 0.215, 0.01))
			_part(head, _cyl_mesh(0.117, 0.117, 0.025), RED, Vector3(0, 0.19, 0.0))
			_part(head, _box_mesh(Vector3(0.16, 0.015, 0.07)), BLACK, Vector3(0, 0.185, -0.12), Vector3(-12, 0, 0))
		_:
			# Bare-headed: hair on top.
			_part(head, _box_mesh(Vector3(0.2, 0.06, 0.2)), HAIR, Vector3(0, 0.19, 0.01))


## Haversack and blanket roll on his back (flat when his rations are gone),
## a canteen at the left hip if he has water, a cartridge box if he has shot.
func _build_pack(strap: Color) -> void:
	var rations := int(pack.get("rations", 8))
	var water := int(pack.get("water", 1))
	var ammo := int(pack.get("ammo", 20))
	var depth := 0.14 if rations > 2 else 0.07
	_part(spine, _box_mesh(Vector3(0.36, 0.34, depth)), PACK, Vector3(0, 0.3, 0.12 + depth * 0.5))
	_part(spine, _box_mesh(Vector3(0.42, 0.09, 0.1)), ROLL, Vector3(0, 0.51, 0.12 + depth * 0.5))
	if water > 0:
		_part(spine, _cyl_mesh(0.07, 0.07, 0.05), Color(0.35, 0.42, 0.5), Vector3(-0.24, -0.06, 0.02), Vector3(0, 0, 90))
	if ammo > 0:
		_part(spine, _box_mesh(Vector3(0.16, 0.11, 0.06)), BLACK, Vector3(0.14, 0.0, 0.15))
		_part(spine, _box_mesh(Vector3(0.05, 0.04, 0.01)), strap, Vector3(0.14, 0.01, 0.185), Vector3.ZERO, true)


func _build_musket(primary := "musket", secondary := "bayonet") -> void:
	musket = Node3D.new()
	body.add_child(musket)
	var wood := WOOD
	var barrel := STEEL
	if primary == "worn_musket":
		wood = WOOD.darkened(0.3)
		barrel = RUST
	elif primary == "rifle":
		wood = Color(0.3, 0.16, 0.08)
		barrel = BROWNED
	if primary == "pike" or primary == "spear":
		# A pole arm: an ash shaft, butt behind the right hand, head far forward.
		var long := 3.0 if primary == "pike" else 2.2
		_part(musket, _cyl_mesh(0.022, 0.026, long), Color(0.55, 0.42, 0.26), Vector3(0, 0, -long * 0.5 + 0.45), Vector3(90, 0, 0))
		var head := STEEL if primary == "pike" else Color(0.45, 0.42, 0.38)
		_part(musket, _cyl_mesh(0.0, 0.035, 0.28), head, Vector3(0, 0, -long + 0.31), Vector3(-90, 0, 0))
		bayonet = Node3D.new()
		musket.add_child(bayonet)
		hand_bayonet = Node3D.new()
		body.add_child(hand_bayonet)
		hand_bayonet.visible = false
		ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
		_p_vis[ramrod] = false
		return
	_part(musket, _box_mesh(Vector3(0.045, 0.11, 0.5)), wood, Vector3(0, -0.025, 0.2)) # stock
	_part(musket, _box_mesh(Vector3(0.04, 0.05, 0.75)), wood, Vector3(0, -0.01, -0.36)) # forestock
	_part(musket, _cyl_mesh(0.013, 0.013, MUZZLE), barrel, Vector3(0, 0.018, -MUZZLE * 0.5), Vector3(90, 0, 0))
	if primary == "rifle":
		_part(musket, _box_mesh(Vector3(0.048, 0.05, 0.1)), GOLD, Vector3(0, -0.02, 0.3), Vector3.ZERO, true) # patchbox
	_part(musket, _box_mesh(Vector3(0.02, 0.05, 0.08)), STEEL, Vector3(0.028, 0.01, -0.02), Vector3.ZERO, true) # lock
	_part(musket, _box_mesh(Vector3(0.007, 0.022, 0.02)), BLACK, Vector3(0, 0.038, -MUZZLE + 0.04), Vector3.ZERO, true) # front sight
	_part(musket, _box_mesh(Vector3(0.03, 0.012, 0.012)), BLACK, Vector3(0, 0.034, -0.08), Vector3.ZERO, true) # rear notch
	var blade := 0.62 if secondary == "sword_bayonet" else 0.42
	bayonet = Node3D.new()
	bayonet.position = Vector3(0, 0.018, -MUZZLE)
	musket.add_child(bayonet)
	_build_bayonet(bayonet, blade)
	hand_bayonet = Node3D.new()
	body.add_child(hand_bayonet)
	_build_bayonet(hand_bayonet, blade)
	hand_bayonet.visible = false
	ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
	_p_vis[ramrod] = false


func _build_bayonet(parent: Node3D, blade := 0.42) -> void:
	_part(parent, _cyl_mesh(0.018, 0.018, 0.08), STEEL, Vector3(0, -0.02, 0.0), Vector3(90, 0, 0))
	_part(parent, _box_mesh(Vector3(0.012, 0.03, blade)), Color(0.82, 0.84, 0.88), Vector3(0, -0.02, -0.02 - blade * 0.5))


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
	_part(head, _box_mesh(Vector3(0.06, 0.04, 0.04)), EYE, Vector3(0.1, 0.16, -0.2), Vector3.ZERO, true)
	_part(head, _box_mesh(Vector3(0.06, 0.04, 0.04)), EYE, Vector3(-0.1, 0.16, -0.2), Vector3.ZERO, true)
	for i in 4:
		_part(head, _box_mesh(Vector3(0.04, 0.12, 0.06)), CREST, Vector3(0, 0.24, 0.05 - i * 0.09), Vector3(-25, 0, 0))
	jaw = Node3D.new()
	jaw.position = Vector3(0, 0.0, -0.08)
	head.add_child(jaw)
	_part(jaw, _box_mesh(Vector3(0.18, 0.06, 0.4)), HIDE_DARK, Vector3(0, -0.03, -0.2))
	for i in 4:
		_part(jaw, _box_mesh(Vector3(0.14, 0.03, 0.015)), BONE, Vector3(0, 0.01, -0.12 - i * 0.08), Vector3.ZERO, true)
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
	# Round shield on the left arm.
	shield = Node3D.new()
	body.add_child(shield)
	_part(shield, _cyl_mesh(0.32, 0.32, 0.03), STEEL, Vector3(0, 0, 0.012), Vector3(90, 0, 0))
	_part(shield, _cyl_mesh(0.3, 0.3, 0.045), WOOD, Vector3.ZERO, Vector3(90, 0, 0))
	_part(shield, _sphere_mesh(0.07), STEEL, Vector3(0, 0, -0.025))
	_sack = _part(body, _box_mesh(Vector3(0.2, 0.16, 0.14)), Color(0.72, 0.6, 0.4), Vector3.ZERO)
	_p_vis[_sack] = false
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
	if not visible:
		return
	if _dead:
		# Keep drawing while the body falls, then the cache stays as it is.
		_dead_t += delta
		if _dead_t < 0.8:
			_emit()
		return
	# Level of detail: how often to re-pose this body.
	var interval := 1
	if not manual:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var d := cam.global_position.distance_to(global_position)
			_detail = d < DETAIL_RANGE
			if not cam.is_position_in_frustum(global_position + Vector3.UP):
				interval = 8
			elif d > MID_RANGE:
				interval = 4
			elif d > NEAR_RANGE:
				interval = 2
	_acc += delta
	_frame_skip += 1
	if _frame_skip < interval:
		return
	_frame_skip = 0
	_update(_acc, false)
	_acc = 0.0
	_emit()


## Write every visible part into the per-shape buffers the Batcher draws.
func _emit() -> void:
	for c in cache:
		c.clear()
	# World transform and visibility of each carrier node, once per update.
	var globals: Array = []
	var vis: Array = []
	for n in _nodes:
		globals.append((n as Node3D).global_transform)
		vis.append((n as Node3D).is_visible_in_tree())
	var tinted := not tint.is_equal_approx(Color.WHITE)
	var overlay := Color(tint.r, tint.g * 0.6, tint.b * 0.4)
	var detail := _detail
	for i in _p_node.size():
		var ni: int = _p_node[i]
		if not vis[ni] or not _p_vis[i] or (not detail and _p_detail[i]):
			continue
		var t: Transform3D = globals[ni] * _p_local[i]
		var col: Color = _p_color[i]
		if tinted:
			col = col.lerp(overlay, 0.5)
		var b := t.basis
		var o := t.origin
		var buf: PackedFloat32Array = cache[_p_shape[i]]
		buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
			b.x.z, b.y.z, b.z.z, o.z, col.r, col.g, col.b, 1.0])


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
	# First person: your head (and the collar and epaulettes right under your
	# eye) are hidden; the rest of you is there when you look down.
	if head != null:
		head.visible = show_head
	for id in _fp_hide:
		_p_vis[id] = show_head

	if kind == "lizard":
		_update_lizard(delta, kh)
	else:
		_update_soldier(delta, k, kh)
	_update_legs(delta)
	# Asleep on his bedroll: the whole body tips back about the feet to lie
	# flat (head away from where he faces), then rolls up again when he wakes.
	var want_lie := 1.0 if anim == "sleep" else 0.0
	if snap:
		_lie = want_lie
	else:
		_lie = move_toward(_lie, want_lie, delta * (6.0 if want_lie > _lie else 1.5))
	if _lie > 0.0 or body.rotation.x != 0.0:
		var e := _lie * _lie * (3.0 - 2.0 * _lie)
		body.rotation.x = PI * 0.5 * e
		body.position.y = 0.11 * e


func _update_soldier(_delta: float, k: float, kh: float) -> void:
	_grip = _grip.lerp(t_grip, k)
	_wdir = _wdir.lerp(t_dir.normalized(), k).normalized()
	var grip := _grip
	var wdir := _wdir
	var pitch := Basis(Vector3.RIGHT, aim_pitch)
	var pivot := pitch_pivot
	if aim_pitch != 0.0:
		grip = pivot + pitch * (grip - pivot)
		wdir = pitch * wdir
	musket.transform = Transform3D(_look_basis(wdir), grip)
	bayonet.visible = bayonet_on

	var r_target: Vector3 = grip if t_hand_r == null else _pitched(t_hand_r, pitch, pivot)
	var l_target: Vector3 = grip + wdir * FORESTOCK if t_hand_l == null else _pitched(t_hand_l, pitch, pivot)
	_hand_r = _hand_r.lerp(r_target, kh)
	_hand_l = _hand_l.lerp(l_target, kh)
	# First person: anchor the shoulders lower and a touch forward, so the
	# upper arms rise from below the screen edge instead of beside the lens.
	# Looking down at your own chest, the shoulders go back where they belong.
	var fp_drop := Vector3.ZERO if show_head else FP_SHOULDER_DROP * clampf(1.0 + aim_pitch * 1.6, 0.0, 1.0)
	_place_arm("r", spine.transform * _shoulder_r + fp_drop, _hand_r, Vector3(1.0, -1.0, 0.4))
	_place_arm("l", spine.transform * _shoulder_l + fp_drop, _hand_l, Vector3(-1.0, -1.0, 0.4))

	hand_bayonet.visible = bayonet_in_hand
	if bayonet_in_hand:
		hand_bayonet.transform = Transform3D(_look_basis(wdir), _hand_r)
	_p_vis[ramrod] = ramrod_on
	if ramrod_on:
		var muzzle := grip + wdir * MUZZLE
		if (_hand_r - muzzle).dot(wdir) > 0.02:
			_place_segment(ramrod, _hand_r, muzzle)
		else:
			_p_vis[ramrod] = false


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
	_p_vis[_sack] = anim == "eat"
	if anim == "eat":
		_set_pos(_sack, _hand_l + Vector3(0.06, 0.02, -0.05))
	# Shield faces off to the side normally, square to the front when raised.
	var turn_target := 0.15 if anim == "shield" else 0.95
	_shield_turn = lerpf(_shield_turn, turn_target, 1.0 - exp(-12.0 * delta))
	var sdir := Basis(Vector3.UP, _shield_turn) * Vector3.FORWARD
	shield.transform = Transform3D(_look_basis(sdir), _hand_l + sdir * 0.06)
	if anim == "rummage" or anim == "eat":
		# Both claws busy with the loot: cleaver thrust through the belt at
		# his right hip, shield slung on his back.
		var st := spine.transform
		cleaver.transform = Transform3D(_look_basis(st.basis * Vector3(0.15, -1.0, 0.25)), st * Vector3(0.3, 0.08, 0.05))
		var back := st.basis * Vector3(0, 0.15, 1.0)
		shield.transform = Transform3D(_look_basis(back), st * Vector3(0, 0.36, 0.3))
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
	var want_kneel := 1.0 if (kind != "lizard" and anim in ["kneel", "tend"]) else 0.0
	_kneel = move_toward(_kneel, want_kneel, delta * 3.0)
	if _kneel > 0.01:
		_kneel_legs()
		return
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
			_set_pos(_leg[side + "_foot"], ankle + Vector3(0, -0.01, -0.12))
		else:
			var thigh_dir := Basis(Vector3.RIGHT, swing) * Vector3.DOWN
			var knee := hip + thigh_dir * 0.44
			var shin_dir := Basis(Vector3.RIGHT, swing - lift) * Vector3.DOWN
			var ankle := knee + shin_dir * 0.44
			_place_segment(_leg[side + "_thigh"], hip, knee)
			_place_segment(_leg[side + "_shin"], knee, ankle)
			_set_pos(_leg[side + "_foot"], ankle + Vector3(0, -0.0, -0.05))
	# A little bob in the stride.
	spine.position.y = _hip_y + absf(cos(_walk_phase)) * amp * 0.06


## Down on the right knee: left foot planted ahead, right shin flat behind.
func _kneel_legs() -> void:
	var k := _kneel
	var hy := lerpf(_hip_y, 0.52, k)
	spine.position.y = hy
	for side in ["l", "r"]:
		var sx := _hip_x * (-1.0 if side == "l" else 1.0)
		var hip := Vector3(sx, hy, 0.0)
		var stand_knee := Vector3(sx, _hip_y - 0.44, 0.0)
		var stand_ankle := Vector3(sx, _hip_y - 0.88, 0.0)
		var knee: Vector3
		var ankle: Vector3
		if side == "l":
			knee = stand_knee.lerp(Vector3(sx, 0.5, -0.42), k)
			ankle = stand_ankle.lerp(Vector3(sx, 0.06, -0.36), k)
		else:
			knee = stand_knee.lerp(Vector3(sx, 0.07, 0.08), k)
			ankle = stand_ankle.lerp(Vector3(sx, 0.08, 0.5), k)
		_place_segment(_leg[side + "_thigh"], hip, knee)
		_place_segment(_leg[side + "_shin"], knee, ankle)
		_set_pos(_leg[side + "_foot"], ankle + Vector3(0, -0.0, -0.05))


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
			"rummage":
				# Bent into the wagon bed, both claws digging through the stores.
				t_lean = 0.85
				var r := sin(anim_time * 7.0)
				t_hand_r = Vector3(0.22, 0.95 + 0.14 * r, -0.8 - 0.1 * r)
				t_hand_l = Vector3(-0.22, 0.95 - 0.14 * r, -0.8 + 0.1 * r)
				t_jaw = 0.25
				pose_rate = 16.0
			"eat":
				# A sack held up to the snout, tearing at it.
				t_lean = 0.25
				t_hand_l = Vector3(-0.06, 1.42, -0.62)
				t_hand_r = Vector3(0.12, 1.36 + 0.06 * sin(anim_time * 9.0), -0.58)
				t_jaw = 0.5 + 0.5 * sin(anim_time * 14.0)
				pose_rate = 14.0
			"shield":
				# Hunched behind the shield, cleaver drawn back.
				t_lean = 0.35
				t_hand_l = Vector3(-0.08, 1.22, -0.5)
				t_hand_r = Vector3(0.42, 1.05, 0.08)
				t_jaw = 0.3
				pose_rate = 18.0
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
		"haul":
			# Musket slung on his back, both hands on a shaft, leaning into it.
			t_grip = Vector3(0.12, 1.15, 0.24)
			t_dir = Vector3(0.35, 1, 0.12)
			t_hand_r = Vector3(0.12, 0.78, -0.4)
			t_hand_l = Vector3(-0.05, 0.8, -0.45)
			t_lean = 0.22
		"cheer":
			# Musket held high over his head, shaken at the sky.
			var b := sin(anim_time * 6.0)
			t_grip = Vector3(0.2, 1.95 + 0.08 * b, -0.05)
			t_dir = Vector3(-0.2, 1, 0.05)
			t_hand_l = Vector3(-0.05, 2.05 + 0.08 * b, -0.02)
			t_lean = -0.12
			pose_rate = 12.0
		"kneel":
			# Down on one knee going through a dead lizard's things: musket
			# grounded at his right side, left hand searching.
			t_grip = Vector3(0.32, 0.45, -0.05)
			t_dir = Vector3(0, 1, 0.05)
			t_hand_l = Vector3(-0.12, 0.18 + 0.08 * sin(anim_time * 5.0), -0.55 + 0.06 * cos(anim_time * 3.0))
			t_lean = 0.45
			pose_rate = 10.0
		"tend":
			# Kneeling by a fallen comrade, musket laid down, both hands
			# binding a wound.
			t_grip = Vector3(0.5, 0.06, -0.1)
			t_dir = Vector3(0, 0, -1)
			var w := sin(anim_time * 3.5)
			t_hand_r = Vector3(0.1, 0.22 + 0.06 * w, -0.55)
			t_hand_l = Vector3(-0.12, 0.22 - 0.06 * w, -0.5)
			t_lean = 0.55
			pose_rate = 9.0
		"sleep":
			# On his back, hands folded on his chest, musket laid on the
			# ground beside him within reach.
			t_grip = Vector3(0.4, 0.2, 0.02)
			t_dir = Vector3(0, 1, 0)
			t_hand_r = Vector3(0.1, 1.05, -0.16)
			t_hand_l = Vector3(-0.1, 1.12, -0.16)
			pose_rate = 8.0
		"block":
			# Musket held crosswise high, catching the blow on the stock.
			t_grip = Vector3(0.32, 1.48, -0.34)
			t_dir = Vector3(-1, 0.15, -0.1)
			t_lean = -0.08
			pose_rate = 22.0


# ---------------------------------------------------------------- geometry

static func _look_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.97 else Vector3.BACK
	return Basis.looking_at(dir, up)


## Stretch a segment part (a box along -Z) from a to b.
func _place_segment(id: int, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var sc: Vector3 = _p_scale[id]
	var basis := _look_basis(d) * Basis.from_scale(Vector3(sc.x, sc.y, l))
	_p_local[id] = Transform3D(basis, (a + b) * 0.5)


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
	_set_pos(_arm[side + "_hand"], hand_pos)
	var cuff_key := side + "_cuff"
	if _arm.has(cuff_key):
		var fd := (hand_pos - elbow).normalized()
		_place_segment(_arm[cuff_key], hand_pos - fd * 0.1, hand_pos - fd * 0.035)
	return elbow


# ---------------------------------------------------------------- look & death

## Muzzle position in world space (for smoke and flashes).
func muzzle_global() -> Vector3:
	if musket == null:
		return global_position + Vector3.UP * 1.4
	return musket.global_transform * Vector3(0, 0.018, -MUZZLE)


func die() -> void:
	_dead = true
	tint = Color(0.55, 0.55, 0.55)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body, "rotation:x", PI * 0.47, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(body, "position:y", 0.12, 0.6)
