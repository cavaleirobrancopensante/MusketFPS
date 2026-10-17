extends Node3D
## A kingdom's catapult and the three men who work it (gun_post.gd holds it
## in a battery as it does a gun; this has the same few functions a GunCrew
## has, so the battery lays and fires it the same way).
##
##   two at the windlass   wind the arm down against its ropes, turn by turn
##   the loader            brings a stone from the pile and sets it in the cup
##
## Laid on a point, it lobs the stone high: it comes down on the far side of
## a wall or a line, crushes whoever it lands among (battle.crush), and
## doesn't care what's in between. Slow to wind, and wild.

const Rig3D := preload("res://scripts/rig3d.gd")
const Props := preload("res://scripts/props.gd")

const MUZZLE_Z := 2.75 # arm space: the cup (gun_post.gd reads it)
const COCKED := 0.25 # the arm's angle wound down
const THROWN := -2.05 # ...and flung up and over
const TRAVERSE := 0.35 # rad/s: they heave the whole frame round
const PILE_AT := Vector3(1.9, 0, 1.4)

var battle
var gun: Node3D
var barrel: Node3D # the arm (named so for gun_post.gd)
var reload := 20.0
var t := 1.0 # 0..1 through winding and loading; 1 = ready
var silent := false
var coat_col = null
var want_yaw := 0.0
var light := false # (unused: GunCrew's)
var manned := false # (unused)
var elev := 0.0 # (unused)
var _crew := {}
var _stone: MeshInstance3D


static func make(b, at: Vector3, yaw: float, reload_s := 20.0) -> Node3D:
	var c = load("res://scripts/catapult_crew.gd").new()
	c.battle = b
	c.reload = reload_s
	c.position = at
	c.rotation.y = yaw
	c.want_yaw = yaw
	return c


func _ready() -> void:
	gun = Props.catapult()
	add_child(gun)
	barrel = gun.get_node("arm")
	barrel.rotation.x = COCKED
	# The stone in the cup, and a pile of them beside.
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.44)
	_stone = MeshInstance3D.new()
	_stone.mesh = sm
	_stone.material_override = mat
	_stone.position = Vector3(0, 0.25, 0)
	barrel.get_node("cup").add_child(_stone)
	for i in 5:
		var p := MeshInstance3D.new()
		p.mesh = sm
		p.material_override = mat
		p.position = PILE_AT + Vector3(randf_range(-0.35, 0.35), 0.2 + (0.3 if i > 2 else 0.0), randf_range(-0.35, 0.35))
		add_child(p)
	for role in ["winch_l", "winch_r", "loader"]:
		var holder := Node3D.new()
		add_child(holder)
		var r = Rig3D.new()
		r.kind = "soldier"
		r.manual = true
		r.gear = {"head": "kettle_hat", "torso": "coat", "primary": "none", "secondary": ""}
		r.pack = {"rations": 0, "water": 0, "ammo": 0}
		r.coat_override = coat_col
		holder.add_child(r)
		holder.position = _post(role)
		_crew[role] = {"holder": holder, "rig": r}


func _post(role: String) -> Vector3:
	match role:
		"winch_l": return Vector3(-0.95, 0, 1.55)
		"winch_r": return Vector3(0.95, 0, 1.55)
		"loader": return Vector3(1.3, 0, 0.9)
	return Vector3.ZERO


func ready() -> bool:
	return not silent and t >= 1.0


func progress() -> float:
	return t


func lay_on(p: Vector3) -> void:
	var flat := p - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		want_yaw = atan2(-flat.x, -flat.z)


func _process(delta: float) -> void:
	if silent:
		return
	if t < 1.0:
		t = minf(1.0, t + delta / reload)
	var d := angle_difference(rotation.y, want_yaw)
	rotation.y += clampf(d, -TRAVERSE * delta, TRAVERSE * delta)
	# Wound down turn by turn after a throw; the stone goes in at the end.
	if t < 1.0:
		barrel.rotation.x = lerpf(THROWN, COCKED, smoothstep(0.04, 0.78, t))
	_stone.visible = t > 0.9
	_drill(delta)


## Throw at a world point (a high lob that comes down on it, give or take).
func fire_at(aim: Vector3, _canister_range := 0.0) -> bool:
	if not ready():
		return false
	var from: Vector3 = gun.global_transform * Vector3(0, 3.6, -0.3)
	var flat := aim - from
	flat.y = 0.0
	var d := flat.length() * randf_range(0.9, 1.1)
	var dir := flat.normalized()
	dir = Basis(Vector3.UP, randf_range(-0.05, 0.05)) * dir
	# 45 degrees, a little more speed for the drop from the arm's height.
	var sp := sqrt(9.8 * maxf(d, 8.0)) * 1.0
	var v := dir * sp * 0.7071 + Vector3.UP * sp * 0.7071
	battle.projectiles.fire("stone", from, v, null)
	battle.play_sound("thud", from, 2.0)
	battle.play_sound("swish", from, 0.0)
	var tw := barrel.create_tween()
	tw.tween_property(barrel, "rotation:x", THROWN, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t = 0.0
	_stone.visible = false
	return true


func overrun() -> void:
	if silent:
		return
	silent = true
	for role in _crew:
		_crew[role]["rig"].die()


func _drill(delta: float) -> void:
	var winding := t > 0.04 and t < 0.78
	for role in ["winch_l", "winch_r"]:
		var r = _crew[role]["rig"]
		var h: Node3D = _crew[role]["holder"]
		# Facing in, at the windlass.
		var fw: Vector3 = (to_global(Vector3(0, 0, 1.5)) - h.global_position) * Vector3(1, 0, 1)
		r.facing = fw.normalized() if fw.length() > 0.01 else global_transform.basis.z
		r.anim_time += delta
		var crank: Vector3 = to_global(Vector3(-0.68 if role == "winch_l" else 0.68, 0.75, 1.5))
		if winding:
			var a: float = float(r.anim_time) * 4.0 + (PI if role == "winch_r" else 0.0)
			crank += global_transform.basis * Vector3(0, cos(a) * 0.18, sin(a) * 0.18)
		var bt: Transform3D = (r.body as Node3D).global_transform
		r.t_hand_r = bt.affine_inverse() * crank
		r.t_hand_l = bt.affine_inverse() * (crank + global_transform.basis * Vector3(0, -0.05, 0.05))
		r.t_lean = 0.35 if winding else 0.1
		r.pose_rate = 12.0
	var lr = _crew["loader"]["rig"]
	var lh: Node3D = _crew["loader"]["holder"]
	var cup: Vector3 = barrel.get_node("cup").global_position
	var goal := _post("loader")
	if t > 0.72 and t < 0.92:
		goal = to_local(cup) + Vector3(0.7, 0, 0)
		goal.y = 0.0
	elif t > 0.55 and t <= 0.72:
		goal = PILE_AT + Vector3(-0.5, 0, 0)
	var to := goal - lh.position
	to.y = 0.0
	var step := 1.8 * delta
	if to.length() > step:
		lh.position += to.normalized() * step
		lr.move_speed = 1.8
		lr.facing = (global_transform.basis * to.normalized())
	else:
		lh.position = goal
		lr.move_speed = 0.0
		lr.facing = -global_transform.basis.z
	lr.anim_time += delta
	var bt2: Transform3D = (lr.body as Node3D).global_transform
	if t > 0.72 and t < 0.92:
		lr.t_hand_r = bt2.affine_inverse() * (cup + Vector3(0.12, 0.2, 0))
		lr.t_hand_l = bt2.affine_inverse() * (cup + Vector3(-0.12, 0.2, 0))
	else:
		lr.t_hand_r = Vector3(0.27, 0.86, -0.02)
		lr.t_hand_l = Vector3(-0.27, 0.86, -0.02)
	lr.t_grip = Vector3(0.3, 0.6, 0.05)
	lr.t_dir = Vector3(0, 1, 0)
	lr.pose_rate = 10.0
