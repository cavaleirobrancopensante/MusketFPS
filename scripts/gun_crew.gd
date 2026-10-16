extends Node3D
## A field gun and the four men who work it, the way a Napoleonic crew
## served a piece:
##
##   the sponger-rammer  on the right of the muzzle: swabs the bore after
##                       each shot (no spark left for the next cartridge),
##                       then rams the new charge home
##   the loader          on the left: fetches a cartridge (powder bag and
##                       shot) from the ammunition box behind the gun and
##                       puts it in the muzzle
##   the gunner          at the trail: lays the gun, kneeling to sight along
##                       the barrel and shifting the trail with a handspike
##   the firer           with the linstock: when the gun is laid, the crew
##                       steps clear and he touches the match to the vent
##
## The drill takes about `reload` seconds. The gun only fires once it is
## loaded and laid; `ready()` says so. Lizards on top of the gun cut the crew
## down and silence it (overrun()).
##
## The crew are drawn rigs moved by this script, not soldiers with their own
## minds: they keep to their posts and their drill.

const Rig3D := preload("res://scripts/rig3d.gd")
const Props := preload("res://scripts/props.gd")

const MUZZLE_Z := -1.85 # barrel space
const VENT := Vector3(0, 0.2, 0.42) # barrel space: where the match goes
const BOX_AT := Vector3(-1.9, 0, 4.2) # the ammunition box, behind and left
## The drill, as fractions of the reload: [phase, start, end].
const DRILL := [["sponge", 0.04, 0.3], ["fetch", 0.04, 0.42], ["load", 0.42, 0.52], ["ram", 0.52, 0.7],
	["lay", 0.7, 0.92], ["clear", 0.9, 1.0]]

var battle
var gun: Node3D
var barrel: Node3D
var reload := 12.0
var t := 1.0 # 0..1 through the drill; 1 = loaded and laid
var silent := false
var want_yaw := 0.0 # where the gunner is laying the gun (world yaw)
var _crew := {} # role -> {"holder", "rig"}
var _cartridge := -1
var _flash: OmniLight3D


static func make(b, at: Vector3, yaw: float, reload_s := 12.0) -> Node3D:
	var c = load("res://scripts/gun_crew.gd").new()
	c.battle = b
	c.reload = reload_s
	c.position = at
	c.rotation.y = yaw
	c.want_yaw = yaw
	return c


func _ready() -> void:
	gun = Props.cannon()
	add_child(gun)
	barrel = gun.get_node("barrel")
	# The ammunition box.
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.5, 0.6)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.22, 0.13)
	box.material_override = mat
	box.position = BOX_AT + Vector3(0, 0.25, 0)
	add_child(box)
	for role in ["rammer", "loader", "gunner", "firer"]:
		var holder := Node3D.new()
		add_child(holder)
		var r = Rig3D.new()
		r.kind = "soldier"
		r.manual = true
		r.gear = {"head": "shako", "torso": "coat", "secondary": "",
			"primary": {"rammer": "rammer", "firer": "linstock"}.get(role, "none")}
		r.pack = {"rations": 0, "water": 0, "ammo": 0}
		holder.add_child(r)
		_crew[role] = {"holder": holder, "rig": r}
	holder_at("rammer", _post("rammer"))
	holder_at("loader", _post("loader"))
	holder_at("gunner", _post("gunner"))
	holder_at("firer", _post("firer"))
	_add_cartridge.call_deferred()


## The loader's cartridge: a powder bag with the shot strapped to it.
func _add_cartridge() -> void:
	var r = _crew["loader"]["rig"]
	_cartridge = r._part(r.hand_bayonet, [Rig3D.CYL, Vector3(0.16, 0.26, 0.16)], Color(0.82, 0.78, 0.66), Vector3(0, 0, -0.08), Vector3(90, 0, 0))
	r._part(r.hand_bayonet, [Rig3D.SPHERE, Vector3.ONE * 0.13], Color(0.15, 0.15, 0.16), Vector3(0, 0, -0.25))


func holder_at(role: String, p: Vector3) -> void:
	(_crew[role]["holder"] as Node3D).position = p


## Where each man stands between tasks (gun space: the gun faces -Z).
func _post(role: String) -> Vector3:
	match role:
		"rammer": return Vector3(0.75, 0, -1.6)
		"loader": return Vector3(-0.75, 0, -1.6)
		"gunner": return Vector3(0.0, 0, 3.2)
		"firer": return Vector3(1.1, 0, 0.6)
	return Vector3.ZERO


func ready() -> bool:
	return not silent and t >= 1.0


## 0..1 through loading (for a HUD).
func progress() -> float:
	return t


func _process(delta: float) -> void:
	if silent:
		return
	if t < 1.0:
		t = minf(1.0, t + delta / reload)
	# The gunner lays the gun while it's being loaded and after.
	if t > 0.6:
		rotation.y = lerp_angle(rotation.y, want_yaw, 1.0 - exp(-2.5 * delta))
	_drill(delta)


## Fire if loaded and laid: `aim` is the world point the gunner laid it on.
## Returns true if it fired.
func fire_at(aim: Vector3, canister_range := 28.0) -> bool:
	if not ready():
		return false
	var muzzle: Vector3 = barrel.global_transform * Vector3(0, 0, MUZZLE_Z)
	var d := muzzle.distance_to(aim)
	if d < canister_range:
		for i in 12:
			var v: Vector3 = battle.projectiles.spread_dir(aim - muzzle, 0.1) * 260.0
			battle.projectiles.fire("canister", muzzle, v, null)
	else:
		var speed := 170.0
		var tf := d / speed
		var v2 := (aim - muzzle).normalized() * speed + Vector3.UP * 0.5 * 9.8 * tf
		battle.projectiles.fire("roundshot", muzzle, v2, null)
	battle.play_sound("cannon", muzzle, 6.0)
	battle.spawn_flash(muzzle, 3.0)
	for i in 3:
		battle.spawn_smoke(muzzle + Vector3(randf_range(-0.6, 0.6), randf_range(0, 0.6), randf_range(-1.2, 0.2)), 2.4)
	battle.spawn_flash(barrel.global_transform * VENT, 0.6)
	var tw := barrel.create_tween()
	tw.tween_property(barrel, "position:z", 0.45, 0.08)
	tw.tween_property(barrel, "position:z", 0.0, 1.2)
	t = 0.0
	return true


## Lay the gun toward a world point (the gunner turns the trail).
func lay_on(p: Vector3) -> void:
	var flat := p - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		want_yaw = atan2(-flat.x, -flat.z)


## Lizards on the gun: the crew is cut down and the gun falls silent.
func overrun() -> void:
	if silent:
		return
	silent = true
	for role in _crew:
		var r = _crew[role]["rig"]
		r.die()


# ---------------------------------------------------------------- the drill

func _phase(name: String) -> float:
	for d in DRILL:
		if d[0] == name:
			return clampf((t - float(d[1])) / (float(d[2]) - float(d[1])), -1.0, 2.0)
	return -1.0


func _in(name: String) -> bool:
	var p := _phase(name)
	return p >= 0.0 and p <= 1.0


func _drill(delta: float) -> void:
	var fwd := -global_transform.basis.z # the way the gun points
	var mouth: Vector3 = barrel.global_transform * Vector3(0, 0, MUZZLE_Z)
	var bore := (barrel.global_transform.basis * Vector3(0, 0, -1)).normalized() # out of the muzzle
	var vent: Vector3 = barrel.global_transform * VENT

	# The rammer: sponge in and out after a shot, then ram the charge home.
	var rr = _crew["rammer"]["rig"]
	var depth := 0.0
	if _in("sponge"):
		depth = 0.4 + 0.9 * absf(sin(_phase("sponge") * PI * 3.0))
	elif _in("ram"):
		var rp := _phase("ram")
		depth = 1.6 * smoothstep(0.0, 0.7, rp) * (1.0 - smoothstep(0.8, 1.0, rp))
	var busy := depth > 0.0
	var pole_dir := -bore # into the bore
	var grip: Vector3 = mouth - pole_dir * (1.75 - depth)
	if busy:
		var side := bore.cross(Vector3.UP).normalized()
		_walk("rammer", to_local(grip - side * 0.5 - pole_dir * 0.35), delta)
		_face("rammer", pole_dir)
		_hands("rammer", grip, pole_dir, grip + pole_dir * 0.55)
		rr.anim = "idle"
	else:
		_walk("rammer", _post("rammer"), delta)
		_face("rammer", -fwd.cross(Vector3.UP))
		# Rammer upright beside him, sponge end up.
		_hands("rammer", _rig_world("rammer", Vector3(0.25, 0.9, -0.1)), Vector3(0, 1, 0.05), _rig_world("rammer", Vector3(0.22, 1.35, -0.12)))

	# The loader: to the box, back with a cartridge, into the muzzle.
	var lr = _crew["loader"]["rig"]
	var carrying := false
	if _in("fetch"):
		var fp := _phase("fetch")
		var at_box := BOX_AT + Vector3(0.55, 0, 0)
		var target := at_box if fp < 0.5 else _post("loader")
		_walk("loader", target, delta, 2.6)
		carrying = fp > 0.5
		_face("loader", _crew["loader"]["holder"].global_position.direction_to(to_global(target)) if _dist("loader", target) > 0.3 else fwd)
		lr.anim = "kneel" if fp > 0.4 and fp < 0.5 else "idle"
		_free_hands("loader", carrying)
	elif _in("load"):
		_walk("loader", _post("loader"), delta)
		_face("loader", fwd.cross(Vector3.UP))
		carrying = _phase("load") < 0.7
		var hand: Vector3 = mouth + bore * lerpf(0.35, -0.05, _phase("load"))
		lr.t_hand_r = _to_body("loader", hand)
		lr.t_hand_l = _to_body("loader", hand + Vector3(0, -0.08, 0))
		lr.anim = "idle"
	else:
		_walk("loader", _post("loader"), delta)
		_face("loader", fwd.cross(Vector3.UP))
		_free_hands("loader", false)
		lr.anim = "idle"
	lr.bayonet_in_hand = carrying

	# The gunner: kneels at the trail and sights along the barrel; shifts the trail.
	var gr = _crew["gunner"]["rig"]
	_walk("gunner", _post("gunner"), delta)
	_face("gunner", fwd)
	if t > 0.6 and t < 1.0 or t >= 1.0:
		gr.anim = "kneel"
		var trail: Vector3 = to_global(Vector3(0, 0.45, 2.55))
		gr.t_hand_r = _to_body("gunner", trail + global_transform.basis.x * 0.12)
		gr.t_hand_l = _to_body("gunner", trail - global_transform.basis.x * 0.12)
		gr.t_lean = 0.35
	else:
		gr.anim = "idle"
		gr.t_lean = 0.0
		_free_hands("gunner", false)

	# The firer: linstock held up and away; touches the vent when it's time.
	var fr = _crew["firer"]["rig"]
	_walk("firer", _post("firer"), delta)
	_face("firer", fwd)
	if t >= 1.0:
		# Ready: the match held just off the vent.
		var off := vent + global_transform.basis.x * 0.25 + Vector3(0, 0.25, 0)
		var dir := (vent - off).normalized()
		_hands("firer", off - dir * 1.0, dir, off - dir * 0.6)
	else:
		_hands("firer", _rig_world("firer", Vector3(0.25, 1.0, -0.2)), Vector3(0.1, 1, -0.4), _rig_world("firer", Vector3(0.2, 1.3, -0.3)))


# ---------------------------------------------------------------- helpers

func _rig(role: String):
	return _crew[role]["rig"]


func _dist(role: String, local_p: Vector3) -> float:
	return (_crew[role]["holder"] as Node3D).position.distance_to(local_p)


func _walk(role: String, local_p: Vector3, delta: float, speed := 1.6) -> void:
	var h: Node3D = _crew[role]["holder"]
	var to := local_p - h.position
	to.y = 0.0
	var step := speed * delta
	var r = _rig(role)
	if to.length() <= step:
		h.position = Vector3(local_p.x, 0, local_p.z)
		r.move_speed = 0.0
	else:
		h.position += to.normalized() * step
		r.move_speed = speed
	r.anim_time += delta


func _face(role: String, world_dir: Vector3) -> void:
	world_dir.y = 0.0
	if world_dir.length_squared() > 0.001:
		_rig(role).facing = world_dir.normalized()


## A point in the man's body space -> world (to place his tool by his side).
func _rig_world(role: String, body_p: Vector3) -> Vector3:
	return (_rig(role).body as Node3D).global_transform * body_p


func _to_body(role: String, world_p: Vector3) -> Vector3:
	return (_rig(role).body as Node3D).global_transform.affine_inverse() * world_p


## Both hands on his tool: right hand (the grip) at `grip` with the tool
## pointing `dir` (world), left hand at `left`.
func _hands(role: String, grip: Vector3, dir: Vector3, left: Vector3) -> void:
	var r = _rig(role)
	var bt: Transform3D = (r.body as Node3D).global_transform
	r.t_grip = bt.affine_inverse() * grip
	r.t_dir = (bt.basis.inverse() * dir).normalized()
	r.t_hand_r = null
	r.t_hand_l = bt.affine_inverse() * left
	r.pose_rate = 12.0


func _free_hands(role: String, carrying: bool) -> void:
	var r = _rig(role)
	var mv := clampf(float(r.move_speed) / 2.5, 0.0, 1.0)
	var sw := sin(float(r.anim_time) * 7.0) * mv
	if carrying:
		r.t_hand_r = Vector3(0.12, 1.05, -0.32)
		r.t_hand_l = Vector3(-0.1, 1.0, -0.3)
	else:
		r.t_hand_r = Vector3(0.27, 0.86, -0.02 + 0.16 * sw)
		r.t_hand_l = Vector3(-0.27, 0.86, -0.02 - 0.16 * sw)
	r.t_grip = Vector3(0.3, 0.6, 0.05)
	r.t_dir = Vector3(0, 1, 0)
	r.pose_rate = 12.0
