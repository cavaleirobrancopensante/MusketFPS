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

const Colours := preload("res://scripts/colours.gd")
const COAT := Color(0.16, 0.24, 0.55) # (Calder's blue: yours is Colours.coat())
const COAT_OFFICER := Color(0.1, 0.13, 0.3)
const WHITE := Color(0.9, 0.88, 0.8)
const SKIN := Color(0.85, 0.66, 0.5)
const BLACK := Color(0.08, 0.08, 0.1)
const WOOD := Color(0.42, 0.26, 0.12)
const STEEL := Color(0.62, 0.64, 0.68)
const GOLD := Color(0.85, 0.68, 0.2)
const RED := Color(0.58, 0.1, 0.1)
const PACK := Color(0.3, 0.2, 0.12)
const TUNIC := Color(0.47, 0.4, 0.29)
const JACK := Color(0.64, 0.58, 0.44)
## The kingdoms' armour (they're a few centuries behind you): mail, and the
## knights' plate.
## The Major (the cutscene and the beach): a field officer's full dress:
## plumed bicorne, gorget at the throat, heavy gold epaulettes, sash, sabre.
const MAJOR_GEAR := {"head": "bicorne", "torso": "officer_coat", "primary": "none", "secondary": "",
	"pistol": "pistol", "sword": "saber", "plume": true, "gorget": true}
const MAIL := Color(0.46, 0.46, 0.48)
const PLATE := Color(0.7, 0.72, 0.76)
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
var full_rate := false # re-pose every frame however far (cutscenes: no level-of-detail stutter)
var t_grip := Vector3(0.22, 1.12, 0.02)
var t_dir := Vector3(0, 1, 0.15)
var t_hand_r = null # Vector3 in body space, or null = on the musket's wrist
var t_hand_l = null # Vector3, or null = on the forestock
var t_lean := 0.0
# Turning side-on (the duellist's stance: the whole body, feet and all, turns
# so the right shoulder faces the target) and twisting the upper body (the
# wind-up and follow-through of a cut). Radians, + is to your left.
var t_turn := 0.0
var t_twist := 0.0
var _turn := 0.0
var _twist := 0.0
var t_jaw := 0.0
var aim_pitch := 0.0 # manual only: upper body follows the camera's pitch
var pitch_pivot := Vector3(0.1, 1.45, 0.0) # what the upper body tilts around
var pose_rate := 14.0
var bayonet_on := true
# The officer's sidearms: "pistol" or "saber" in the right hand (the musket
# then hangs across the back), "" for the musket.
var hand_item := ""
var _pistol: Node3D
var _saber: Node3D
## What he carries in his hands: "musket", "pole" (pike, spear), "bow",
## "crossbow" or "none" (townsfolk). Bows ride in their own node (_bow) held
## in the left hand, with a string that follows the drawing hand.
var weapon := "musket"
var _bow: Node3D
var _bow_tip_up := Vector3.ZERO # bow space
var _bow_tip_dn := Vector3.ZERO
var _bow_str_a := -1
var _bow_str_b := -1
var _bow_arrow := -1
var _bow_draw := 0.0
var t_bow_draw := 0.0
var bow_on_back := false
var arrow_on := false
var _sling := false # musket or crossbow slung across the back (an archer's knife fight)
var _xbow: Node3D # an officer's spare crossbow (the weapon range)
var _heater: Node3D # a footman's shield, on the left arm
var t_bow_up := Vector3.ZERO # when set (your own body), how the bow is held
var _muzzle_z := MUZZLE
var bayonet_in_hand := false
## Anim "fix" (a cutscene drives it 0..1): musket grounded, the right hand
## draws the bayonet from the scabbard and fixes it on the muzzle.
var fix_k := 0.0
var ramrod_on := false
var show_head := true
var _fp_hide: Array = [] # parts right under your eye (collar, epaulettes): hidden in first person
## A soldier's kit (Company gear ids: head, torso, primary, secondary) and
## pack ({water, rations, ammo}); empty means the regulation kit, full pack.
var gear := {}
var pack := {}
# Townsfolk ("civilian"): their own clothes, no musket or pack.
var cloth := Color(0.5, 0.42, 0.32)
## A field battle's enemy wears another army's coat (null: the regulation blue).
var coat_override = null
## A trooper in the saddle (cavalry): legs astride, sabre or cleaver up.
var seated := false
## Seated: how far the legs turn from where the body faces (radians), so a
## rider can look about while his legs stay round the horse.
var seat_yaw := 0.0
## Mounts: the head carried lower (your own horse, seen from the saddle).
var neck_dip := 0.0
## Mounts (kind "horse" or "raptor"): saddle cloth colour.
var saddle_col := Color(0.16, 0.24, 0.55) # (set from gear: yours is your coat)
var _mlegs: Array = [] # [upper id, lower id, hoof id, attach Vector3, phase offset]
var _neck: Node3D
var _mtail: Array = []
var trousers := Color(0.32, 0.27, 0.22)
var female := false
var dwarf := false

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
	elif kind == "horse":
		_build_horse()
	elif kind == "raptor":
		_build_raptor()
	else:
		_build_soldier()
	_update(0.0, true)
	# The batcher in this rig's own world (a preview or a pop-up scene has
	# its own; while one screen gives way to another, two can exist).
	for b in get_tree().get_nodes_in_group("batcher"):
		if b.get_viewport() == get_viewport() and not b.is_queued_for_deletion():
			_batcher = b
			break
	if _batcher == null:
		_batcher = get_tree().get_first_node_in_group("batcher")
	if _batcher != null:
		_batcher.add_rig(self)
	_emit()


func _exit_tree() -> void:
	if _batcher != null:
		_batcher.remove_rig(self)


func draw_enabled() -> bool:
	return is_inside_tree() and is_visible_in_tree()


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
	weapon = _weapon_of(String(g["primary"]))
	if kind == "civilian":
		weapon = "none"
	var coat := Colours.officer_coat() if officer and torso == "officer_coat" else Colours.coat()
	var cuff := RED if officer and torso == "officer_coat" else WHITE
	if coat_override != null and torso in ["coat", "buffcoat"]:
		coat = coat_override
		torso = "coat"
	var belt := WHITE
	var civ := kind == "civilian"
	if civ:
		coat = cloth
		cuff = cloth.darkened(0.12)
		belt = LEATHER
		torso = "tunic"
	elif torso == "shirt":
		coat = SHIRT
		cuff = SHIRT.darkened(0.08)
		belt = LEATHER
	elif torso == "buffcoat":
		coat = BUFF
		cuff = BUFF.darkened(0.15)
		belt = LEATHER
	elif torso == "tunic":
		coat = TUNIC
		cuff = TUNIC.darkened(0.12)
		belt = LEATHER
	elif torso == "jack":
		coat = JACK
		cuff = JACK.darkened(0.12)
		belt = LEATHER
	var tabard = null # (mail and plate: a surcoat in his lord's colours over it)
	if torso in ["mail", "plate"]:
		tabard = coat_override if coat_override != null else Color(0.5, 0.15, 0.12)
		coat = MAIL if torso == "mail" else PLATE
		cuff = coat.darkened(0.15)
		belt = LEATHER
	spine.position = Vector3(0, _hip_y, 0)
	# Torso, coat tails (not on a bare shirt), crossbelts, pack.
	_part(spine, _box_mesh(Vector3(0.42, 0.56, 0.24)), coat, Vector3(0, 0.28, 0))
	if civ and female:
		# A long skirt from the waist to the shins.
		_part(spine, _box_mesh(Vector3(0.44, 0.62, 0.3)), cloth.darkened(0.2), Vector3(0, -0.28, 0.0))
	elif civ or torso == "tunic":
		_part(spine, _box_mesh(Vector3(0.42, 0.2, 0.25)), coat, Vector3(0, -0.04, 0.0)) # tunic skirt
		_part(spine, _box_mesh(Vector3(0.44, 0.05, 0.27)), LEATHER, Vector3(0, 0.06, 0)) # belt
	elif officer or torso != "shirt":
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
		if g.get("gorget", false):
			# A field officer: a gilt gorget at the throat, heavy epaulettes
			# with bullion fringes, gold lace down the lapels.
			_fp_hide.append(_part(spine, _box_mesh(Vector3(0.14, 0.07, 0.02)), GOLD.lightened(0.15), Vector3(0, 0.5, -0.13), Vector3(0, 0, 0)))
			for sx in [-1.0, 1.0]:
				_fp_hide.append(_part(spine, _box_mesh(Vector3(0.15, 0.05, 0.17)), GOLD, Vector3(sx * 0.23, 0.585, 0)))
				_fp_hide.append(_part(spine, _box_mesh(Vector3(0.025, 0.09, 0.17)), GOLD.darkened(0.1), Vector3(sx * 0.305, 0.53, 0)))
				_part(spine, _box_mesh(Vector3(0.015, 0.4, 0.02)), GOLD, Vector3(sx * 0.07, 0.3, -0.132), Vector3.ZERO, true)
	elif civ:
		pass
	elif tabard != null:
		# The surcoat, front and back, belted; a plate gorget for a knight.
		_part(spine, _box_mesh(Vector3(0.36, 0.62, 0.02)), tabard, Vector3(0, 0.22, -0.125))
		_part(spine, _box_mesh(Vector3(0.36, 0.62, 0.02)), tabard, Vector3(0, 0.22, 0.125))
		_part(spine, _box_mesh(Vector3(0.44, 0.05, 0.27)), LEATHER, Vector3(0, 0.04, 0))
		if torso == "plate":
			_fp_hide.append(_part(spine, _cyl_mesh(0.12, 0.14, 0.08), PLATE, Vector3(0, 0.6, 0)))
			_part(spine, _box_mesh(Vector3(0.16, 0.08, 0.2)), PLATE, Vector3(0.24, 0.52, 0)) # pauldrons
			_part(spine, _box_mesh(Vector3(0.16, 0.08, 0.2)), PLATE, Vector3(-0.24, 0.52, 0))
	elif torso in ["tunic", "jack"]:
		# Native kit: no crossbelts; a padded jack shows its quilting.
		if torso == "jack":
			for qy in [0.12, 0.26, 0.4]:
				_part(spine, _box_mesh(Vector3(0.43, 0.015, 0.245)), JACK.darkened(0.18), Vector3(0, qy, 0), Vector3.ZERO, true)
			_part(spine, _box_mesh(Vector3(0.44, 0.05, 0.25)), LEATHER, Vector3(0, 0.02, 0)) # belt
		_build_pack(belt)
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
	if civ and female:
		_part(head, _box_mesh(Vector3(0.22, 0.3, 0.1)), HAIR, Vector3(0, 0.02, 0.08)) # long hair
	if dwarf:
		_part(head, _box_mesh(Vector3(0.2, 0.26, 0.1)), HAIR.lightened(0.15), Vector3(0, -0.04, -0.1)) # beard
	if String(g["head"]) == "bicorne":
		# Bicorne worn side to side: a crescent, tallest in the middle.
		_part(head, _cyl_mesh(0.118, 0.118, 0.05), BLACK, Vector3(0, 0.19, 0))
		_part(head, _box_mesh(Vector3(0.27, 0.15, 0.05)), BLACK, Vector3(-0.115, 0.26, 0), Vector3(0, 0, 20))
		_part(head, _box_mesh(Vector3(0.27, 0.15, 0.05)), BLACK, Vector3(0.115, 0.26, 0), Vector3(0, 0, -20))
		_part(head, _box_mesh(Vector3(0.5, 0.012, 0.055)), GOLD, Vector3(0, 0.196, 0), Vector3.ZERO, true) # gold edging
		_part(head, _cyl_mesh(0.035, 0.035, 0.012), RED, Vector3(-0.07, 0.28, -0.032), Vector3(90, 0, 0)) # cockade
		_part(head, _cyl_mesh(0.016, 0.016, 0.014), GOLD, Vector3(-0.07, 0.28, -0.036), Vector3(90, 0, 0))
		if g.get("plume", false):
			# A white plume standing up from the cockade, a red tip.
			_part(head, _box_mesh(Vector3(0.04, 0.2, 0.05)), Color(0.95, 0.94, 0.9), Vector3(-0.07, 0.4, -0.02), Vector3(0, 0, 8))
			_part(head, _box_mesh(Vector3(0.042, 0.06, 0.052)), RED, Vector3(-0.055, 0.51, -0.02), Vector3(0, 0, 8))
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
		var native := torso in ["tunic", "jack", "mail"]
		if torso == "plate":
			_segment(side + "_thigh", 0.14, PLATE, _leg)
			_segment(side + "_shin", 0.125, PLATE.darkened(0.1), _leg)
		else:
			_segment(side + "_thigh", 0.13, trousers if civ or native else WHITE, _leg)
			_segment(side + "_shin", 0.115, trousers.darkened(0.25) if civ or native else BLACK, _leg) # (natives: leg wraps)
		_leg[side + "_foot"] = _part(body, _box_mesh(Vector3(0.11, 0.07, 0.24)), BLACK, Vector3.ZERO)
	_build_musket("none" if civ else String(g["primary"]), String(g["secondary"]))
	if String(g["secondary"]) == "heater_shield":
		# A heater shield, painted in his lord's colours with a pale stripe.
		_heater = Node3D.new()
		body.add_child(_heater)
		var paint: Color = coat_override if coat_override != null else Color(0.5, 0.15, 0.12)
		_part(_heater, _box_mesh(Vector3(0.48, 0.5, 0.04)), paint, Vector3(0, 0.08, 0))
		_part(_heater, _box_mesh(Vector3(0.34, 0.2, 0.04)), paint, Vector3(0, -0.24, 0), Vector3(0, 0, 0))
		_part(_heater, _box_mesh(Vector3(0.16, 0.16, 0.04)), paint, Vector3(0, -0.36, 0), Vector3(0, 0, 45))
		_part(_heater, _box_mesh(Vector3(0.1, 0.72, 0.045)), Color(0.88, 0.84, 0.72), Vector3(0, -0.04, -0.002), Vector3.ZERO, true)
		_part(_heater, _box_mesh(Vector3(0.5, 0.03, 0.05)), STEEL.darkened(0.2), Vector3(0, 0.33, 0), Vector3.ZERO, true)
	if officer:
		if String(g.get("bow", "")) != "":
			_build_bow(_bow_owner(), String(g["bow"]))
		if String(g.get("crossbow", "")) != "":
			_xbow = Node3D.new()
			body.add_child(_xbow)
			_build_crossbow(_xbow, String(g["crossbow"]))
		if String(g.get("pistol", "pistol")) != "":
			_build_pistol()
		if String(g.get("sword", "saber")) != "":
			_build_saber(String(g.get("sword", "saber")))
	elif String(g.get("sword", "")) != "":
		_build_saber(String(g["sword"])) # a trooper's sabre
	if civ:
		bayonet_on = false
	elif not officer:
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
		"hood":
			_part(head, _box_mesh(Vector3(0.25, 0.24, 0.26)), TUNIC.darkened(0.2), Vector3(0, 0.13, 0.03))
			_part(spine, _box_mesh(Vector3(0.48, 0.1, 0.3)), TUNIC.darkened(0.2), Vector3(0, 0.56, 0.01)) # short cape
		"great_helm":
			# A knight's great helm: a flat-topped steel pot, a slit to see by.
			_part(head, _cyl_mesh(0.135, 0.135, 0.3), PLATE, Vector3(0, 0.12, 0))
			_part(head, _box_mesh(Vector3(0.2, 0.022, 0.02)), BLACK, Vector3(0, 0.15, -0.134), Vector3.ZERO, true)
			_part(head, _box_mesh(Vector3(0.02, 0.18, 0.02)), PLATE.darkened(0.2), Vector3(0, 0.07, -0.136), Vector3.ZERO, true)
			_part(head, _cyl_mesh(0.137, 0.137, 0.02), GOLD, Vector3(0, 0.27, 0), Vector3.ZERO, true)
		"nasal_helm":
			# A footman's conical helm with a nasal, a mail coif under it.
			_part(head, _cyl_mesh(0.06, 0.12, 0.14), STEEL.darkened(0.1), Vector3(0, 0.26, 0))
			_part(head, _box_mesh(Vector3(0.025, 0.12, 0.02)), STEEL.darkened(0.1), Vector3(0, 0.15, -0.12))
			_part(head, _box_mesh(Vector3(0.25, 0.16, 0.24)), MAIL, Vector3(0, 0.06, 0.02))
		"kettle_hat":
			_part(head, _cyl_mesh(0.1, 0.115, 0.11), STEEL.darkened(0.15), Vector3(0, 0.24, 0))
			_part(head, _cyl_mesh(0.2, 0.2, 0.014), STEEL.darkened(0.1), Vector3(0, 0.19, 0)) # the broad brim
		"cap":
			_part(head, _cyl_mesh(0.125, 0.115, 0.075), Colours.coat(), Vector3(0, 0.215, 0.01))
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
	if weapon == "bow":
		# A quiver over the right shoulder, fletchings showing while there are arrows.
		_part(spine, _cyl_mesh(0.06, 0.05, 0.5), LEATHER, Vector3(0.13, 0.38, 0.17), Vector3(-12, 0, -22))
		if ammo > 0:
			_part(spine, _box_mesh(Vector3(0.07, 0.06, 0.07)), Color(0.85, 0.82, 0.75), Vector3(0.235, 0.64, 0.115), Vector3(-12, 0, -22))
	elif weapon == "crossbow":
		_part(spine, _box_mesh(Vector3(0.1, 0.24, 0.09)), LEATHER, Vector3(0.24, -0.08, 0.04)) # bolt case
	elif ammo > 0:
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
	if primary == "none":
		# Townsfolk: empty hands.
		bayonet = Node3D.new()
		musket.add_child(bayonet)
		hand_bayonet = Node3D.new()
		body.add_child(hand_bayonet)
		hand_bayonet.visible = false
		ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
		_p_vis[ramrod] = false
		return
	if primary in ["hunting_bow", "war_bow", "crossbow", "dwarf_crossbow"]:
		_build_missile_weapon(primary, secondary)
		return
	if primary in ["rammer", "linstock", "spade"]:
		# A gun crew's tools: the rammer (a sponge at one end), or the
		# linstock with its smouldering match.
		if primary == "spade":
			_part(musket, _cyl_mesh(0.018, 0.018, 1.05), Color(0.5, 0.38, 0.22), Vector3(0, 0, -0.42), Vector3(90, 0, 0))
			_part(musket, _box_mesh(Vector3(0.12, 0.03, 0.06)), Color(0.45, 0.32, 0.18), Vector3(0, 0, 0.1)) # the T-grip
			_part(musket, _box_mesh(Vector3(0.2, 0.02, 0.26)), STEEL.darkened(0.25), Vector3(0, 0, -1.04)) # the blade
		elif primary == "rammer":
			_part(musket, _cyl_mesh(0.02, 0.02, 2.6), Color(0.5, 0.38, 0.22), Vector3(0, 0, -0.5), Vector3(90, 0, 0))
			_part(musket, _cyl_mesh(0.075, 0.075, 0.26), Color(0.25, 0.23, 0.2), Vector3(0, 0, -1.83), Vector3(90, 0, 0))
		else:
			_part(musket, _cyl_mesh(0.018, 0.022, 1.3), Color(0.45, 0.32, 0.18), Vector3(0, 0, -0.35), Vector3(90, 0, 0))
			_part(musket, _box_mesh(Vector3(0.03, 0.03, 0.08)), Color(1.0, 0.45, 0.12), Vector3(0, 0.0, -1.03))
		bayonet = Node3D.new()
		musket.add_child(bayonet)
		hand_bayonet = Node3D.new()
		body.add_child(hand_bayonet)
		hand_bayonet.visible = false
		ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
		_p_vis[ramrod] = false
		return
	if primary == "arming_sword":
		# A straight sword: grip and cross at the hand, the blade forward.
		_part(musket, _box_mesh(Vector3(0.03, 0.03, 0.16)), LEATHER, Vector3(0, 0, 0.04))
		_part(musket, _box_mesh(Vector3(0.2, 0.025, 0.03)), STEEL.darkened(0.2), Vector3(0, 0, -0.05))
		_part(musket, _box_mesh(Vector3(0.045, 0.012, 0.78)), STEEL, Vector3(0, 0, -0.44))
		bayonet = Node3D.new()
		musket.add_child(bayonet)
		hand_bayonet = Node3D.new()
		body.add_child(hand_bayonet)
		hand_bayonet.visible = false
		ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
		_p_vis[ramrod] = false
		return
	if primary in ["pike", "spear", "war_spear", "lance"]:
		# A pole arm: an ash shaft, butt behind the right hand, head far forward.
		var long: float = {"pike": 3.0, "spear": 2.2, "war_spear": 2.5, "lance": 3.3}[primary]
		if primary == "lance":
			# A pennon below the head: red over white.
			_part(musket, _box_mesh(Vector3(0.006, 0.09, 0.26)), Color(0.75, 0.12, 0.1), Vector3(0, 0.05, -long + 0.62), Vector3.ZERO, true)
			_part(musket, _box_mesh(Vector3(0.006, 0.07, 0.2)), Color(0.92, 0.9, 0.85), Vector3(0, -0.02, -long + 0.6), Vector3.ZERO, true)
		_part(musket, _cyl_mesh(0.022, 0.026, long), Color(0.55, 0.42, 0.26), Vector3(0, 0, -long * 0.5 + 0.45), Vector3(90, 0, 0))
		var head := Color(0.45, 0.42, 0.38) if primary == "spear" else STEEL
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


## A flintlock pistol: barrel along -Z from the hand, grip angled down.
static func _weapon_of(primary: String) -> String:
	if primary in ["hunting_bow", "war_bow"]:
		return "bow"
	if primary in ["crossbow", "dwarf_crossbow"]:
		return "crossbow"
	if primary in ["pike", "spear", "war_spear", "lance", "rammer", "linstock", "spade", "arming_sword"]:
		return "pole"
	if primary == "none":
		return "none"
	return "musket"


## Bows and crossbows, and the knife or hatchet an archer fights with up close
## (in hand_bayonet, so the melee poses can show it).
func _build_missile_weapon(primary: String, secondary: String) -> void:
	bayonet = Node3D.new()
	musket.add_child(bayonet)
	hand_bayonet = Node3D.new()
	body.add_child(hand_bayonet)
	if secondary == "hatchet":
		_part(hand_bayonet, _box_mesh(Vector3(0.03, 0.03, 0.42)), WOOD, Vector3(0, 0, -0.15))
		_part(hand_bayonet, _box_mesh(Vector3(0.015, 0.12, 0.09)), STEEL, Vector3(0, 0.05, -0.33))
	else:
		_part(hand_bayonet, _box_mesh(Vector3(0.025, 0.03, 0.1)), LEATHER, Vector3(0, 0, 0.0))
		_part(hand_bayonet, _box_mesh(Vector3(0.01, 0.035, 0.3)), STEEL, Vector3(0, 0, -0.2))
	hand_bayonet.visible = false
	ramrod = _part(body, _box_mesh(Vector3(0.012, 0.012, 1.0)), STEEL, Vector3.ZERO)
	_p_vis[ramrod] = false
	if weapon == "crossbow":
		_muzzle_z = 0.62
		_build_crossbow(musket, primary)
		return
	_build_bow(body, primary)


func _bow_owner() -> Node3D:
	return body


## A crossbow on `n` (held like a musket: a stock along -Z, the steel prod
## across the front, the string spanned back to the nut).
func _build_crossbow(n: Node3D, primary: String) -> void:
	var dw := primary == "dwarf_crossbow"
	var wood := Color(0.3, 0.2, 0.12) if dw else WOOD
	_part(n, _box_mesh(Vector3(0.05, 0.08, 0.8)), wood, Vector3(0, -0.02, -0.18)) # stock
	_part(n, _box_mesh(Vector3(0.03, 0.03, 0.06)), STEEL, Vector3(0, 0.03, -0.18), Vector3.ZERO, true) # nut
	for sgn in [-1.0, 1.0]:
		_part(n, _box_mesh(Vector3(0.34, 0.03, 0.03)), STEEL if dw else STEEL.darkened(0.2), Vector3(0.16 * sgn, 0.0, -0.56), Vector3(0, -14.0 * sgn, 0))
	var sa := _part(n, _box_mesh(Vector3(0.008, 0.008, 1.0)), Color(0.8, 0.78, 0.7), Vector3.ZERO, Vector3.ZERO, true)
	var sb := _part(n, _box_mesh(Vector3(0.008, 0.008, 1.0)), Color(0.8, 0.78, 0.7), Vector3.ZERO, Vector3.ZERO, true)
	_place_segment(sa, Vector3(0.32, 0.0, -0.48), Vector3(0, 0.03, -0.18))
	_place_segment(sb, Vector3(-0.32, 0.0, -0.48), Vector3(0, 0.03, -0.18))
	_part(n, _box_mesh(Vector3(0.12, 0.012, 0.012)), STEEL, Vector3(0, -0.02, -0.62), Vector3.ZERO, true) # stirrup


## A bow in its own node under `parent`: two limbs bending back toward the
## archer from the grip; the string and the arrow are placed every frame.
func _build_bow(parent: Node3D, primary: String) -> void:
	_bow = Node3D.new()
	parent.add_child(_bow)
	var war := primary == "war_bow"
	var limb := 0.8 if war else 0.55
	var col := Color(0.5, 0.36, 0.2) if war else Color(0.38, 0.27, 0.16)
	_part(_bow, _box_mesh(Vector3(0.035, 0.12, 0.04)), LEATHER, Vector3.ZERO) # grip
	var bend := 38.0
	for up in [true, false]:
		var n := Node3D.new()
		_bow.add_child(n)
		n.position = Vector3(0, 0.05 if up else -0.05, 0)
		n.basis = Basis(Vector3.RIGHT, PI * 0.5) if up else Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -PI * 0.5)
		_arc(n, 0.0, limb, 6, bend, 0.045, 0.022, 0.026, col)
		# Where the tip ends up, in bow space (same walk as _arc).
		var pos := Vector3.ZERO
		for i in 6:
			var th := deg_to_rad(bend * (i + 0.5) / 6)
			pos += Vector3(0, sin(th), -cos(th)) * limb / 6
		var tip := n.transform * pos
		if up:
			_bow_tip_up = tip
		else:
			_bow_tip_dn = tip
	_bow_str_a = _part(body, _box_mesh(Vector3(0.008, 0.008, 1.0)), Color(0.85, 0.83, 0.75), Vector3.ZERO, Vector3.ZERO, true)
	_bow_str_b = _part(body, _box_mesh(Vector3(0.008, 0.008, 1.0)), Color(0.85, 0.83, 0.75), Vector3.ZERO, Vector3.ZERO, true)
	_bow_arrow = _part(body, _box_mesh(Vector3(0.016, 0.016, 1.0)), Color(0.4, 0.3, 0.18), Vector3.ZERO)


## A basis whose Y is `y` and whose Z points as near `z` as it can.
static func _basis_yz(y: Vector3, z: Vector3) -> Basis:
	var yy := y.normalized()
	var xx := yy.cross(z).normalized()
	var zz := xx.cross(yy).normalized()
	return Basis(xx, yy, zz)


## The bow in the left hand (or on his back), its string pulled to the right
## hand by how far it's drawn, and an arrow on the string when there is one.
func _update_bow(k: float) -> void:
	_bow_draw = lerpf(_bow_draw, t_bow_draw, k)
	var st := spine.transform
	var on_back := bow_on_back or (weapon != "bow" and hand_item != "bow")
	if on_back:
		_bow.transform = Transform3D(_basis_yz(st.basis * Vector3(-0.45, 1.0, 0.0), st.basis * Vector3(0, 0, -1)), st * Vector3(0.0, 0.3, 0.24))
	else:
		var up := Vector3(0.12, 1.0, 0.0) if anim in ["aim", "fire"] else Vector3(0.0, 1.0, 0.3)
		if t_bow_up != Vector3.ZERO:
			up = t_bow_up
		var back := Vector3(0, 0, 1)
		if aim_pitch != 0.0:
			var pb := Basis(Basis(Vector3.UP, -_turn) * Vector3.RIGHT, aim_pitch)
			up = pb * up
			back = pb * back
		_bow.transform = Transform3D(_basis_yz(up, back), _hand_l)
	var a := _bow.transform * _bow_tip_up
	var b := _bow.transform * _bow_tip_dn
	var rest := (a + b) * 0.5 + _bow.transform.basis.z * 0.02
	var nock := rest.lerp(_hand_r, _bow_draw) if not on_back else rest
	_place_segment(_bow_str_a, a, nock)
	_place_segment(_bow_str_b, nock, b)
	_p_vis[_bow_arrow] = arrow_on and not on_back
	if arrow_on and not on_back:
		var through := _bow.transform.origin - nock
		var fwd := through.normalized() if through.length() > 0.15 else Vector3(0, 0, -1)
		var tail := nock if _bow_draw > 0.3 else _hand_r
		_place_segment(_bow_arrow, tail, tail + fwd * 0.75)


func _build_pistol() -> void:
	_pistol = Node3D.new()
	body.add_child(_pistol)
	_part(_pistol, _box_mesh(Vector3(0.035, 0.11, 0.06)), WOOD.darkened(0.2), Vector3(0, -0.04, 0.03), Vector3(-18, 0, 0)) # grip
	_part(_pistol, _box_mesh(Vector3(0.038, 0.04, 0.16)), WOOD.darkened(0.2), Vector3(0, 0.015, -0.06)) # stock
	_part(_pistol, _cyl_mesh(0.011, 0.012, 0.24), STEEL, Vector3(0, 0.03, -0.17), Vector3(90, 0, 0)) # barrel
	_part(_pistol, _box_mesh(Vector3(0.012, 0.035, 0.05)), STEEL, Vector3(0.022, 0.03, -0.01), Vector3.ZERO, true) # lock
	_part(_pistol, _box_mesh(Vector3(0.018, 0.02, 0.025)), GOLD, Vector3(0, -0.09, 0.05), Vector3.ZERO, true) # butt cap
	_part(_pistol, _box_mesh(Vector3(0.005, 0.016, 0.012)), GOLD, Vector3(0, 0.05, -0.28)) # front sight blade
	_part(_pistol, _box_mesh(Vector3(0.026, 0.012, 0.01)), BLACK, Vector3(0, 0.047, -0.04)) # rear notch


## A sabre: a hilt with a brass guard and a long blade along -Z, and a
## scabbard on the left hip it rests in when not drawn.
func _build_saber(id: String) -> void:
	_saber = Node3D.new()
	body.add_child(_saber)
	var long := 0.78 if id != "cutlass" else 0.62
	_part(_saber, _box_mesh(Vector3(0.03, 0.03, 0.12)), Color(0.15, 0.1, 0.06), Vector3(0, 0, 0.05)) # grip
	_part(_saber, _box_mesh(Vector3(0.09, 0.02, 0.02)), GOLD, Vector3(0, 0, -0.02)) # cross-guard
	_part(_saber, _box_mesh(Vector3(0.012, 0.06, 0.13)), GOLD, Vector3(0, -0.03, 0.04), Vector3(20, 0, 0), true) # knuckle bow
	# The blade: twelve short pieces along a true arc, curving back toward
	# the spine (+Y) and narrowing to the point.
	_arc(_saber, -0.03, long, 12, 16.0, 0.038, 0.012, 0.008, Color(0.86, 0.88, 0.92))
	# The scabbard, hanging from the sash at the left hip, curved the same way
	# so the sheathed blade lies inside it.
	var scab := Node3D.new()
	spine.add_child(scab)
	scab.transform = Transform3D(_look_basis(SABER_SHEATH_DIR), SABER_SHEATH_AT)
	_arc(scab, -0.02, long + 0.03, 8, 16.0, 0.052, 0.034, 0.026, LEATHER.darkened(0.25))
	_part(scab, _box_mesh(Vector3(0.03, 0.058, 0.05)), GOLD, Vector3(0, 0, -0.04), Vector3.ZERO, true) # throat


const SABER_SHEATH_DIR := Vector3(-0.12, -0.72, 0.68) # spine space (slung well back, clear of the legs)
const SABER_SHEATH_AT := Vector3(-0.25, 0.1, -0.02)


## A curved strip made of `n` short boxes along an arc in the YZ plane of
## `parent`: starting at z0, running `length` along -Z and bending `total_deg`
## toward +Y, `w0` wide at the start and `w1` at the end (the width is the
## blade's depth, along Y), `t` thick.
func _arc(parent: Node3D, z0: float, length: float, n: int, total_deg: float, w0: float, w1: float, t: float, col: Color) -> void:
	var seg := length / n
	var pos := Vector3(0, 0, z0)
	for i in n:
		var th := deg_to_rad(total_deg * (i + 0.5) / n)
		var d := Vector3(0, sin(th), -cos(th))
		var c := pos + d * seg * 0.5
		var w := lerpf(w0, w1, float(i) / maxf(1.0, n - 1))
		_part(parent, _box_mesh(Vector3(t, w, seg * 1.12)), col, c, Vector3(rad_to_deg(th), 0, 0))
		pos += d * seg


func pistol_muzzle_global() -> Vector3:
	if _pistol == null:
		return muzzle_global()
	return _pistol.global_transform * Vector3(0, 0.03, -0.3)


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
	if not visible or (seated and not is_visible_in_tree()):
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
			if full_rate:
				pass
			elif not cam.is_position_in_frustum(global_position + Vector3.UP):
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
		# The parent's heading, from its forward axis laid flat: on a rolling,
		# pitching deck the Euler yaw jumps about; this doesn't.
		var pf := -p.global_transform.basis.z
		parent_yaw = atan2(-pf.x, -pf.z) if Vector2(pf.x, pf.z).length_squared() > 0.0001 else p.global_rotation.y
	var kt := 1.0 if snap else 1.0 - exp(-9.0 * delta)
	_turn = lerpf(_turn, t_turn, kt)
	body.rotation.y = lerp_angle(body.rotation.y, want - parent_yaw + _turn, 1.0 if snap else 1.0 - exp(-10.0 * delta))

	if not manual:
		_npc_pose()
	var k := 1.0 if snap else 1.0 - exp(-pose_rate * delta)
	var kh := 1.0 if snap else 1.0 - exp(-pose_rate * 1.6 * delta)
	_lean = lerpf(_lean, t_lean, k)
	_jaw = lerpf(_jaw, t_jaw, k)
	_twist = lerpf(_twist, t_twist, k)
	spine.rotation = Vector3(-_lean, _twist, 0.0)
	if head != null and kind != "lizard":
		head.rotation.y = -_turn - _twist # the eyes stay on the target
	# First person: your head (and the collar and epaulettes right under your
	# eye) are hidden; the rest of you is there when you look down.
	if head != null:
		head.visible = show_head
	for id in _fp_hide:
		_p_vis[id] = show_head

	if kind == "horse" or kind == "raptor":
		_update_mount(delta)
		return
	if kind == "lizard":
		_update_lizard(delta, kh)
	else:
		_update_soldier(delta, k, kh)
	if seated:
		_seated_legs()
	else:
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
	# Pitch about the axis across your line of sight, wherever the body is turned.
	var pitch := Basis(Basis(Vector3.UP, -_turn) * Vector3.RIGHT, aim_pitch)
	var pivot := pitch_pivot
	if aim_pitch != 0.0:
		grip = pivot + pitch * (grip - pivot)
		wdir = pitch * wdir
	var st := spine.transform
	if hand_item != "" or _sling:
		# Musket slung across the back, muzzle up over the left shoulder.
		musket.transform = Transform3D(_look_basis(st.basis * Vector3(-0.32, 1.0, 0.1)), st * Vector3(0.16, 0.12, 0.2))
		bayonet.visible = false
	else:
		musket.transform = Transform3D(_look_basis(wdir), grip)
		bayonet.visible = bayonet_on

	var r_target: Vector3 = grip if t_hand_r == null else _pitched(t_hand_r, pitch, pivot)
	var l_target: Vector3 = grip + wdir * FORESTOCK if t_hand_l == null else _pitched(t_hand_l, pitch, pivot)
	if (hand_item != "" or _sling) and t_hand_l == null:
		l_target = Vector3(-0.27, 0.9, -0.04) # hanging at your side
	if _heater != null and t_hand_l == null:
		l_target = Vector3(-0.26, 1.08, -0.3) # the shield up in front of him
	_hand_r = _hand_r.lerp(r_target, kh)
	_hand_l = _hand_l.lerp(l_target, kh)
	# First person: anchor the shoulders lower and a touch forward, so the
	# upper arms rise from below the screen edge instead of beside the lens.
	# Looking down at your own chest, the shoulders go back where they belong.
	var fp_drop := Vector3.ZERO if show_head else FP_SHOULDER_DROP * clampf(1.0 + aim_pitch * 1.6, 0.0, 1.0)
	_place_arm("r", spine.transform * _shoulder_r + fp_drop, _hand_r, Vector3(1.0, -1.0, 0.4))
	_place_arm("l", spine.transform * _shoulder_l + fp_drop, _hand_l, Vector3(-1.0, -1.0, 0.4))
	# Sidearms: in the hand when drawn, otherwise in the sash and the scabbard.
	if _pistol != null:
		if hand_item == "pistol":
			_pistol.transform = Transform3D(_look_basis(wdir), _hand_r)
		else:
			_pistol.transform = Transform3D(_look_basis(st.basis * Vector3(0.5, -1.0, -0.15)), st * Vector3(0.12, 0.1, -0.16))
	if _saber != null:
		if hand_item == "saber":
			_saber.transform = Transform3D(_look_basis(wdir), _hand_r)
		else:
			_saber.transform = st * Transform3D(_look_basis(SABER_SHEATH_DIR), SABER_SHEATH_AT)

	if _heater != null:
		_heater.transform = Transform3D(_look_basis(Vector3(0.25, 0, -1).normalized()), _hand_l + Vector3(-0.04, -0.05, -0.06))
	if _bow != null:
		_update_bow(k)
	if _xbow != null:
		if hand_item == "crossbow":
			_xbow.transform = Transform3D(_look_basis(wdir), grip)
		else:
			# Slung at the back, nose down.
			_xbow.transform = Transform3D(_look_basis(st.basis * Vector3(0.25, -1.0, 0.15)), st * Vector3(-0.12, 0.25, 0.24))
	hand_bayonet.visible = bayonet_in_hand
	if bayonet_in_hand:
		var hdir := wdir if weapon in ["musket", "pole"] else (_hand_r - spine.transform * _shoulder_r).normalized().lerp(Vector3(0, 0.3, -1).normalized(), 0.5)
		hand_bayonet.transform = Transform3D(_look_basis(hdir), _hand_r)
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
	if kind == "horse" or kind == "raptor":
		return
	if seated and kind != "lizard":
		_rider_pose()
		return
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
	if kind == "civilian":
		# Hands free: swinging at the sides, or talking with them.
		t_grip = Vector3(0.3, 0.6, 0.05)
		t_dir = Vector3(0, 1, 0)
		var mv := clampf(move_speed / 3.0, 0.0, 1.0)
		t_hand_r = Vector3(0.27, 0.86, -0.02 + 0.16 * swing * mv)
		t_hand_l = Vector3(-0.27, 0.86, -0.02 - 0.16 * swing * mv)
		match anim:
			"talk":
				var w := sin(anim_time * 4.0)
				t_hand_r = Vector3(0.22, 1.12 + 0.08 * w, -0.32)
				t_hand_l = Vector3(-0.2, 1.0 - 0.05 * w, -0.25)
			"point":
				t_hand_r = Vector3(0.3, 1.45, -0.6)
			"work":
				var k := absf(sin(anim_time * 3.0))
				t_hand_r = Vector3(0.12, 0.95 - 0.25 * k, -0.45)
				t_hand_l = Vector3(-0.12, 0.95 - 0.25 * k, -0.45)
				t_lean = 0.35
			"fear":
				t_hand_r = Vector3(0.15, 1.5, -0.25)
				t_hand_l = Vector3(-0.15, 1.5, -0.25)
				t_lean = -0.15
		return
	_sling = false
	bayonet_in_hand = false
	t_bow_draw = 0.0
	bow_on_back = false
	arrow_on = false
	if weapon == "bow":
		_bow_pose(swing)
		return
	if weapon == "crossbow" and _xbow_pose(swing):
		return
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
		"fix":
			t_grip = Vector3(0.06, 0.52, -0.3)
			t_dir = Vector3(0, 1, -0.1)
			var muz := t_grip + t_dir.normalized() * MUZZLE
			t_hand_l = t_grip + t_dir.normalized() * 0.72
			var sheath := Vector3(-0.2, 0.92, 0.12) # (the scabbard on the left hip)
			if fix_k < 0.3:
				t_hand_r = Vector3(0.28, 0.95, -0.05).lerp(sheath, fix_k / 0.3)
			elif fix_k < 0.72:
				bayonet_in_hand = true
				var k2 := (fix_k - 0.3) / 0.42
				t_hand_r = sheath.lerp(muz + Vector3(0, 0.14, 0), k2) + Vector3(0, sin(k2 * PI) * 0.12, 0)
			else:
				# Socket on, a twist to lock it, the hand away.
				t_hand_r = muz + Vector3(0.04 * sin(fix_k * 40.0), 0.06 - 0.1 * (fix_k - 0.72), 0)
			pose_rate = 14.0
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


## An archer: bow in the left hand, the right hand nocks, draws and looses;
## a knife or hatchet in the right hand up close, the bow kept in the left.
func _bow_pose(swing: float) -> void:
	t_grip = Vector3(0.2, 0.7, 0.1) # (the empty musket node: out of the way)
	t_dir = Vector3(0, 1, 0)
	var mv := clampf(move_speed / 4.0, 0.0, 1.0)
	t_hand_l = Vector3(-0.27, 0.92, -0.08 - 0.12 * swing * mv)
	t_hand_r = Vector3(0.27, 0.86, -0.02 + 0.14 * swing * mv)
	arrow_on = false
	match anim:
		"aim":
			# Bow arm straight out, string drawn to the cheek.
			t_hand_l = Vector3(-0.04, 1.47, -0.66)
			t_hand_r = Vector3(0.05, 1.53, -0.06)
			t_bow_draw = 1.0
			arrow_on = true
			pose_rate = 9.0
		"fire":
			# Loosed: the string snaps forward, the drawing hand flies back.
			t_hand_l = Vector3(-0.04, 1.47, -0.66)
			t_hand_r = Vector3(0.16, 1.52, 0.06)
			pose_rate = 30.0
		"reload":
			# Bow down, reach back to the quiver, bring an arrow to the string.
			t_hand_l = Vector3(-0.18, 1.15, -0.45)
			var ph := fmod(anim_time * 1.1, 1.0)
			if ph < 0.45:
				t_hand_r = Vector3(0.2, 1.62, 0.2)
			else:
				t_hand_r = Vector3(-0.08, 1.17, -0.38)
				arrow_on = true
			pose_rate = 10.0
		"guard", "thrust", "block":
			bayonet_in_hand = true
			t_hand_l = Vector3(-0.3, 1.0, -0.15)
			match anim:
				"guard": t_hand_r = Vector3(0.24, 1.12, -0.38)
				"thrust":
					t_hand_r = Vector3(0.12, 1.3, -0.68)
					t_lean = 0.25
					pose_rate = 30.0
				"block":
					t_hand_r = Vector3(0.12, 1.55, -0.35)
					pose_rate = 22.0
		"cheer":
			var b := sin(anim_time * 6.0)
			t_hand_l = Vector3(-0.08, 2.0 + 0.08 * b, -0.08)
			t_hand_r = Vector3(0.28, 1.0, 0.0)
			t_lean = -0.12
		"haul", "kneel", "tend", "sleep":
			bow_on_back = true
			match anim:
				"haul":
					t_hand_r = Vector3(0.12, 0.78, -0.4)
					t_hand_l = Vector3(-0.05, 0.8, -0.45)
					t_lean = 0.22
				"kneel":
					t_hand_l = Vector3(-0.12, 0.18 + 0.08 * sin(anim_time * 5.0), -0.55)
					t_hand_r = Vector3(0.2, 0.3, -0.4)
					t_lean = 0.45
				"tend":
					var w := sin(anim_time * 3.5)
					t_hand_r = Vector3(0.1, 0.22 + 0.06 * w, -0.55)
					t_hand_l = Vector3(-0.12, 0.22 - 0.06 * w, -0.5)
					t_lean = 0.55
				"sleep":
					t_hand_r = Vector3(0.1, 1.05, -0.16)
					t_hand_l = Vector3(-0.1, 1.12, -0.16)


## A crossbowman: aims like a musketeer, spans head-down with the windlass,
## and fights with a knife (crossbow slung). Returns true when it set the pose.
func _xbow_pose(_swing: float) -> bool:
	match anim:
		"reload":
			# Nose down, foot in the stirrup, winding the windlass at the butt.
			t_grip = Vector3(0.08, 0.95, -0.12)
			t_dir = Vector3(0, -1, -0.35)
			t_hand_l = t_grip + t_dir.normalized() * 0.3
			var a := anim_time * 7.0
			t_hand_r = Vector3(0.2 + 0.06 * cos(a), 1.05 + 0.06 * sin(a), -0.02)
			t_lean = 0.2
			return true
		"guard", "thrust", "block":
			_sling = true
			bayonet_in_hand = true
			t_hand_l = Vector3(-0.3, 1.0, -0.15)
			match anim:
				"guard": t_hand_r = Vector3(0.24, 1.12, -0.38)
				"thrust":
					t_hand_r = Vector3(0.12, 1.3, -0.68)
					t_lean = 0.25
					pose_rate = 30.0
				"block":
					t_hand_r = Vector3(0.12, 1.55, -0.35)
					pose_rate = 22.0
			return true
	return false


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
	if _bow != null:
		return _bow.global_transform * Vector3(0, 0.02, -0.08)
	if musket == null:
		return global_position + Vector3.UP * 1.4
	return musket.global_transform * Vector3(0, 0.018, -_muzzle_z)


func die() -> void:
	_dead = true
	tint = Color(0.55, 0.55, 0.55)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body, "rotation:x", PI * 0.47, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(body, "position:y", 0.12, 0.6)


# ---------------------------------------------------------------- mounts and riders
# Cavalry (field battles): a horse or a riding raptor is its own rig (kind
# "horse" / "raptor"), and the trooper is a second rig sitting on its body
# node (`seated`), so he turns, bobs and falls with it.

const BAY := Color(0.38, 0.23, 0.13)
const BAY_DARK := Color(0.2, 0.12, 0.07)
const RAPTOR := Color(0.33, 0.4, 0.2)
const RAPTOR_DARK := Color(0.2, 0.25, 0.12)
const RAPTOR_STRIPE := Color(0.5, 0.36, 0.16)
## Where the rider's rig stands on the mount's body (his hips on the saddle).
const SADDLE_HORSE := Vector3(0, 0.8, 0.05)
const SADDLE_RAPTOR := Vector3(0, 0.74, 0.1)


func _build_horse() -> void:
	saddle_col = gear.get("saddle_col", saddle_col)
	var deer: bool = gear.get("deer", false)
	var coat := BAY.lerp(Color(0.22, 0.16, 0.12), randf() * 0.6)
	if randf() < 0.15:
		coat = Color(0.62, 0.6, 0.56) # a grey
	if deer:
		coat = Color(0.58, 0.4, 0.22).lerp(Color(0.45, 0.32, 0.2), randf() * 0.5)
	var dark := coat.darkened(0.45)
	_part(body, _box_mesh(Vector3(0.56, 0.62, 1.55)), coat, Vector3(0, 1.3, 0.0)) # barrel
	_part(body, _box_mesh(Vector3(0.5, 0.6, 0.5)), coat, Vector3(0, 1.36, -0.72)) # chest
	_part(body, _box_mesh(Vector3(0.54, 0.56, 0.5)), coat, Vector3(0, 1.36, 0.66)) # quarters
	if gear.get("barding", false):
		# A knight's horse: a caparison in his colours down to the knees.
		_part(body, _box_mesh(Vector3(0.66, 0.62, 1.7)), saddle_col, Vector3(0, 1.22, 0.02))
		_part(body, _box_mesh(Vector3(0.56, 0.5, 0.5)), saddle_col, Vector3(0, 1.28, -0.74))
		_part(body, _box_mesh(Vector3(0.68, 0.06, 1.72)), GOLD, Vector3(0, 0.92, 0.02), Vector3.ZERO, true)
	if deer:
		# A deer: no saddle; a pale rump and belly.
		_part(body, _box_mesh(Vector3(0.5, 0.4, 0.2)), Color(0.92, 0.88, 0.8), Vector3(0, 1.38, 0.9))
		_part(body, _box_mesh(Vector3(0.4, 0.12, 1.2)), Color(0.85, 0.78, 0.66), Vector3(0, 1.0, 0.0))
	else:
		# Saddle, cloth, girth.
		_part(body, _box_mesh(Vector3(0.66, 0.06, 0.78)), saddle_col, Vector3(0, 1.63, 0.06))
		_part(body, _box_mesh(Vector3(0.68, 0.035, 0.8)), GOLD, Vector3(0, 1.6, 0.06), Vector3.ZERO, true)
		_part(body, _box_mesh(Vector3(0.4, 0.12, 0.56)), LEATHER, Vector3(0, 1.7, 0.04))
		_part(body, _box_mesh(Vector3(0.6, 0.08, 0.1)), LEATHER, Vector3(0, 1.3, -0.1), Vector3.ZERO, true)
	# Neck and head on their own node (it nods as he goes).
	_neck = Node3D.new()
	_neck.position = Vector3(0, 1.5, -0.86)
	body.add_child(_neck)
	_part(_neck, _box_mesh(Vector3(0.3, 0.42, 0.85)), coat, Vector3(0, 0.3, -0.18), Vector3(55, 0, 0))
	_part(_neck, _box_mesh(Vector3(0.08, 0.2, 0.8)), dark, Vector3(0, 0.46, 0.0), Vector3(55, 0, 0)) # mane
	_part(_neck, _box_mesh(Vector3(0.24, 0.26, 0.62)), coat, Vector3(0, 0.62, -0.62), Vector3(-25, 0, 0)) # head
	_part(_neck, _box_mesh(Vector3(0.18, 0.18, 0.22)), dark, Vector3(0, 0.5, -0.9), Vector3(-25, 0, 0)) # muzzle
	_part(_neck, _box_mesh(Vector3(0.05, 0.12, 0.05)), coat, Vector3(0.08, 0.86, -0.42), Vector3(-10, 0, 0)) # ears
	_part(_neck, _box_mesh(Vector3(0.05, 0.12, 0.05)), coat, Vector3(-0.08, 0.86, -0.42), Vector3(-10, 0, 0))
	_part(_neck, _box_mesh(Vector3(0.26, 0.03, 0.03)), BLACK, Vector3(0, 0.6, -0.78), Vector3.ZERO, true) # bridle
	_part(_neck, _box_mesh(Vector3(0.04, 0.04, 0.04)), BLACK, Vector3(0.12, 0.72, -0.56), Vector3.ZERO, true) # eye
	_part(_neck, _box_mesh(Vector3(0.04, 0.04, 0.04)), BLACK, Vector3(-0.12, 0.72, -0.56), Vector3.ZERO, true)
	if deer:
		# Antlers: two beams back and up, a few tines.
		for sx in [-1.0, 1.0]:
			_part(_neck, _box_mesh(Vector3(0.035, 0.035, 0.5)), Color(0.82, 0.76, 0.62), Vector3(sx * 0.12, 1.0, -0.36), Vector3(-55, sx * 20, 0))
			_part(_neck, _box_mesh(Vector3(0.03, 0.03, 0.22)), Color(0.82, 0.76, 0.62), Vector3(sx * 0.15, 1.05, -0.5), Vector3(-80, 0, 0))
			_part(_neck, _box_mesh(Vector3(0.03, 0.03, 0.22)), Color(0.82, 0.76, 0.62), Vector3(sx * 0.18, 1.2, -0.3), Vector3(-80, 0, 0))
	for i in 3:
		_mtail.append(_part(body, _box_mesh(Vector3(0.12 - i * 0.02, 0.12, 1.0)), dark, Vector3.ZERO))
	# Legs: forearm/cannon in front, gaskin/cannon behind; trot pairs.
	var legs := [[Vector3(0.17, 1.12, -0.7), 0.0], [Vector3(-0.17, 1.12, -0.7), PI], [Vector3(0.17, 1.15, 0.68), PI], [Vector3(-0.17, 1.15, 0.68), 0.0]]
	for l in legs:
		var up := _part(body, _box_mesh(Vector3(0.15, 0.15, 1.0)), coat, Vector3.ZERO)
		var lo := _part(body, _box_mesh(Vector3(0.09, 0.09, 1.0)), dark if randf() < 0.5 else coat.darkened(0.15), Vector3.ZERO)
		var hoof := _part(body, _box_mesh(Vector3(0.13, 0.08, 0.15)), BLACK, Vector3.ZERO)
		_mlegs.append([up, lo, hoof, l[0], l[1]])


func _build_raptor() -> void:
	saddle_col = gear.get("saddle_col", saddle_col)
	var hide := RAPTOR.lerp(Color(0.4, 0.36, 0.18), randf() * 0.5)
	_part(body, _box_mesh(Vector3(0.52, 0.58, 1.3)), hide, Vector3(0, 1.35, 0.0), Vector3(-6, 0, 0))
	_part(body, _box_mesh(Vector3(0.4, 0.3, 0.9)), BELLY, Vector3(0, 1.1, -0.05), Vector3(-6, 0, 0))
	for i in 4:
		_part(body, _box_mesh(Vector3(0.54, 0.05, 0.12)), RAPTOR_STRIPE, Vector3(0, 1.62, -0.4 + i * 0.28), Vector3(-6, 0, 0), true)
	_part(body, _box_mesh(Vector3(0.6, 0.06, 0.62)), saddle_col, Vector3(0, 1.66, 0.12))
	_part(body, _box_mesh(Vector3(0.4, 0.12, 0.46)), BONE.darkened(0.3), Vector3(0, 1.73, 0.12))
	_neck = Node3D.new()
	_neck.position = Vector3(0, 1.5, -0.62)
	body.add_child(_neck)
	_part(_neck, _box_mesh(Vector3(0.24, 0.26, 0.7)), hide, Vector3(0, 0.22, -0.2), Vector3(45, 0, 0))
	_part(_neck, _box_mesh(Vector3(0.28, 0.26, 0.5)), hide, Vector3(0, 0.5, -0.5), Vector3(-8, 0, 0)) # head
	_part(_neck, _box_mesh(Vector3(0.2, 0.08, 0.42)), RAPTOR_DARK, Vector3(0, 0.36, -0.62), Vector3(-4, 0, 0)) # jaw
	for i in 4:
		_part(_neck, _box_mesh(Vector3(0.16, 0.025, 0.02)), BONE, Vector3(0, 0.42, -0.5 - i * 0.08), Vector3.ZERO, true)
	_part(_neck, _box_mesh(Vector3(0.05, 0.05, 0.05)), EYE, Vector3(0.13, 0.58, -0.56), Vector3.ZERO, true)
	_part(_neck, _box_mesh(Vector3(0.05, 0.05, 0.05)), EYE, Vector3(-0.13, 0.58, -0.56), Vector3.ZERO, true)
	for i in 3:
		_part(_neck, _box_mesh(Vector3(0.04, 0.16, 0.06)), CREST, Vector3(0, 0.7, -0.4 + i * 0.12), Vector3(-30, 0, 0))
	# Little clawed arms.
	_part(body, _box_mesh(Vector3(0.07, 0.07, 0.34)), hide, Vector3(0.22, 1.2, -0.6), Vector3(40, 0, 0))
	_part(body, _box_mesh(Vector3(0.07, 0.07, 0.34)), hide, Vector3(-0.22, 1.2, -0.6), Vector3(40, 0, 0))
	for i in 5:
		var w := 0.3 - i * 0.05
		_mtail.append(_part(body, _box_mesh(Vector3(w, w, 1.0)), hide.darkened(0.1 * (i % 2)), Vector3.ZERO))
	# Two big running legs: thigh, shin, a long foot with a sickle claw.
	for side in [1.0, -1.0]:
		var thigh := _part(body, _box_mesh(Vector3(0.24, 0.24, 1.0)), hide, Vector3.ZERO)
		var shin := _part(body, _box_mesh(Vector3(0.13, 0.13, 1.0)), RAPTOR_DARK, Vector3.ZERO)
		var foot := _part(body, _box_mesh(Vector3(0.16, 0.08, 0.36)), RAPTOR_DARK, Vector3.ZERO)
		_mlegs.append([thigh, shin, foot, Vector3(side * 0.24, 1.22, 0.18), 0.0 if side > 0.0 else PI])


func _update_mount(delta: float) -> void:
	var raptor := kind == "raptor"
	var spd := move_speed
	var gallop := spd > 6.5
	_walk_phase += delta * (2.4 + spd * (0.75 if not raptor else 1.0))
	var amp := clampf(spd / 7.0, 0.0, 1.0)
	body.position.y = absf(sin(_walk_phase)) * amp * 0.09 - (0.05 if anim == "rear" else 0.0)
	body.rotation.x = 0.0 if anim != "rear" else -0.35
	if _neck != null:
		_neck.rotation.x = sin(_walk_phase * 2.0) * amp * 0.08 + (0.25 if gallop else 0.0) + neck_dip
	# Tail.
	var base := Vector3(0, 1.55, 0.92) if not raptor else Vector3(0, 1.4, 0.62)
	var dir := Vector3(0, -0.8, 0.5).normalized() if not raptor else Vector3(0, -0.1, 1).normalized()
	var sway := sin(anim_time * 7.0 + _walk_phase) * (0.15 + amp * 0.3)
	for i in _mtail.size():
		var seg_dir := Basis(Vector3.UP, sway * 0.2 * (i + 1)) * dir
		var end := base + seg_dir * (0.3 if not raptor else 0.38)
		_place_segment(_mtail[i], base, end)
		base = end
		if not raptor:
			dir = (dir + Vector3(0, -0.3, 0)).normalized()
		else:
			dir = (dir + Vector3(0, -0.06, 0)).normalized()
	for l in _mlegs:
		var top: Vector3 = l[3]
		var off: float = l[4]
		if gallop and not raptor:
			off = 0.0 if top.z < 0.0 else PI # front pair together, back pair together
			off += 0.4 if top.x > 0.0 else 0.0
		var ph := _walk_phase + off
		var swing := sin(ph) * amp * (0.5 if not raptor else 0.7)
		var lift := maxf(0.0, cos(ph)) * amp
		if raptor:
			var rot := Basis(Vector3.RIGHT, swing)
			var knee := top + rot * Vector3(0, -0.62, -0.42).normalized() * 0.55
			var ank := knee + rot * Basis(Vector3.RIGHT, -lift * 0.9) * Vector3(0, -0.78, 0.62).normalized() * 0.62
			ank.y = maxf(ank.y, 0.06 + lift * 0.25)
			_place_segment(l[0], top, knee)
			_place_segment(l[1], knee, ank)
			_set_pos(l[2], ank + Vector3(0, -0.02, -0.16))
		else:
			var knee2 := top + Basis(Vector3.RIGHT, swing) * Vector3.DOWN * 0.55
			var bend := lift * (1.2 if top.z < 0.0 else -0.9)
			var hoof := knee2 + Basis(Vector3.RIGHT, swing + bend) * Vector3.DOWN * 0.55
			hoof.y = maxf(hoof.y, 0.04)
			_place_segment(l[0], top, knee2)
			_place_segment(l[1], knee2, hoof)
			_set_pos(l[2], hoof + Vector3(0, 0.0, -0.02))


## In the saddle: knees forward and out round the barrel, feet in the irons.
func _seated_legs() -> void:
	var liz := kind == "lizard"
	spine.position.y = _hip_y
	for side in ["l", "r"]:
		var sx := (_hip_x if not liz else 0.2) * (-1.0 if side == "l" else 1.0)
		var sb := Basis(Vector3.UP, seat_yaw)
		var hip := sb * Vector3(sx, _hip_y, 0.0)
		var knee := sb * Vector3(sx * 2.4, _hip_y - 0.18, -0.36)
		var ankle := sb * Vector3(sx * 2.5, _hip_y - 0.62, -0.18)
		_place_segment(_leg[side + "_thigh"], hip, knee)
		_place_segment(_leg[side + "_shin"], knee, ankle)
		_set_pos(_leg[side + "_foot"], ankle + sb * Vector3(0, -0.02, -0.06))


## A trooper's sabre: sloped at the shoulder walking, levelled in the
## charge, raised and brought down in a cut. Left hand on the reins.
func _rider_pose() -> void:
	t_lean = 0.0
	t_hand_l = Vector3(-0.1, 0.98, -0.36)
	match anim:
		"charge":
			t_grip = Vector3(0.28, 1.32, -0.42)
			t_dir = Vector3(0, 0.08, -1)
			t_lean = 0.3
		"windup":
			t_grip = Vector3(0.36, 1.85, 0.08)
			t_dir = Vector3(0.2, 0.7, 0.8)
			t_lean = -0.1
			pose_rate = 12.0
		"strike":
			t_grip = Vector3(0.42, 0.95, -0.6)
			t_dir = Vector3(0.1, -0.7, -0.9)
			t_lean = 0.35
			pose_rate = 30.0
		"block":
			t_grip = Vector3(0.3, 1.6, -0.35)
			t_dir = Vector3(-1, 0.3, -0.2)
		"aim":
			# A dragoon's carbine at his shoulder.
			t_grip = Vector3(0.1, 1.46, -0.38)
			t_dir = Vector3(0, 0.04, -1)
			t_hand_l = Vector3(-0.02, 1.47, -0.75)
		_:
			t_grip = Vector3(0.26, 1.12, -0.12)
			t_dir = Vector3(0.05, 1, 0.35)
