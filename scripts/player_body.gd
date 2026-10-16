extends Node
## 3D mode only: drives your own officer's body (a Rig3D in manual mode) from
## the player's state, so the same body works in first person (you see your
## arms and musket) and third person (you see yourself).
##
## Poses are in body space (facing -Z, feet at 0); the rig tilts the upper
## body with the camera pitch so the musket points where you look. Reload and
## bayonet animations walk the right hand along timed waypoints, the same
## timings the 2D viewmodel uses.

const Rig3D := preload("res://scripts/rig3d.gd")

# [grip position, musket direction]
const READY := [Vector3(0.19, 1.34, -0.46), Vector3(-0.04, 0.05, -1)]
## Sighting: stock at the cheek, barrel straight down your line of sight, so
## the front sight sits just under the crosshair. Grip x 0 = centred on the eye.
const AIM := [Vector3(0.0, 1.52, -0.42), Vector3(0, 0.07, -1)]
const EYE := Vector3(0, 1.64, 0.02) # matches the first-person camera
const UPRIGHT := [Vector3(0.02, 0.98, -0.56), Vector3(0, 1, -0.25)]
const MELEE_IDLE := [Vector3(0.16, 1.28, -0.3), Vector3(0, 0.28, -1)]
const BLOCK := [Vector3(0.32, 1.52, -0.42), Vector3(-1, 0.1, -0.05)]
# Swing directions: 0 overhead, 1 from left, 2 from right, 3 thrust.
const WINDUP := {
	0: [Vector3(0.12, 1.68, -0.42), Vector3(0, 0.75, -0.65)],
	1: [Vector3(-0.28, 1.5, -0.4), Vector3(-0.7, 0.3, -0.65)],
	2: [Vector3(0.38, 1.5, -0.32), Vector3(0.75, 0.3, -0.6)],
	3: [Vector3(0.18, 1.3, 0.05), Vector3(0, 0.08, -1)],
}
const STRIKE := {
	0: [Vector3(0.08, 1.2, -0.42), Vector3(0, -0.45, -1)],
	1: [Vector3(0.32, 1.3, -0.3), Vector3(0.75, -0.05, -0.65)],
	2: [Vector3(-0.26, 1.3, -0.35), Vector3(-0.75, -0.05, -0.65)],
	3: [Vector3(0.1, 1.42, -0.62), Vector3(0, 0.02, -1)],
}

## The musket reload, step by step (fractions of the whole):
## bite the cartridge (M, at your mouth), prime the pan and shut it (L, the
## lock, musket held low across you), stand it up and pour (C), ram three
## times (D-E), return the rod (B), bring it up and cock the hammer (L).
const RELOAD_PATH := [[0.0, "A"], [0.06, "A"], [0.11, "M"], [0.16, "M"], [0.21, "L"], [0.27, "L"],
	[0.31, "B"], [0.35, "C"], [0.41, "C"], [0.46, "D"], [0.50, "E"], [0.54, "D"], [0.58, "E"],
	[0.62, "D"], [0.66, "E"], [0.71, "D"], [0.79, "B"], [0.86, "A"], [0.90, "L"], [0.95, "L"], [1.0, "A"]]
## Musket held low across the body to prime the pan.
const PRIME := [Vector3(0.1, 1.05, -0.42), Vector3(-0.3, 0.22, -1)]

# The pistol: held out at the ready, arm straight to aim, muzzle up to load.
const P_READY := [Vector3(0.21, 1.36, -0.5), Vector3(-0.05, 0.14, -1)]
const P_AIM := [Vector3(0.1, 1.47, -0.74), Vector3(-0.04, 0.04, -1)]
const P_LOAD := [Vector3(0.1, 1.12, -0.32), Vector3(-0.05, 1, -0.25)]
const P_HOLSTER := Vector3(0.12, 1.02, -0.17)
# The sabre: guard, a high parry, and one-handed cuts from each side.
const S_IDLE := [Vector3(0.27, 1.3, -0.44), Vector3(0.12, 0.9, -0.55)]
const S_BLOCK := [Vector3(0.22, 1.58, -0.4), Vector3(-1, 0.28, -0.1)]
const S_HILT := Vector3(-0.25, 1.02, -0.06)
const S_WINDUP := {
	0: [Vector3(0.16, 1.82, -0.05), Vector3(0, 0.55, 0.8)],
	1: [Vector3(-0.32, 1.55, -0.22), Vector3(-0.9, 0.45, 0.25)],
	2: [Vector3(0.5, 1.58, -0.12), Vector3(0.9, 0.5, 0.2)],
	3: [Vector3(0.22, 1.3, 0.02), Vector3(0, 0.05, -1)],
}
const S_STRIKE := {
	0: [Vector3(0.1, 1.15, -0.55), Vector3(0, -0.55, -1)],
	1: [Vector3(0.4, 1.28, -0.38), Vector3(0.9, -0.1, -0.45)],
	2: [Vector3(-0.32, 1.28, -0.42), Vector3(-0.9, -0.1, -0.45)],
	3: [Vector3(0.12, 1.4, -0.72), Vector3(0, 0, -1)],
}
const FIX_PATH := [[0.0, "A"], [0.1, "A"], [0.3, "H"], [0.55, "F"], [0.72, "E"], [0.85, "E"], [1.0, "A"]]
const UNFIX_PATH := [[0.0, "A"], [0.2, "E"], [0.4, "F"], [0.7, "H"], [1.0, "A"]]

var player
var rig


func _process(delta: float) -> void:
	if not player.alive:
		return
	var f: Vector3 = -player.global_transform.basis.z
	f.y = 0.0
	rig.facing = f.normalized()
	var v: Vector3 = player.velocity
	rig.move_speed = Vector2(v.x, v.z).length()
	rig.anim_time += delta
	# The upper body tilts around your eye, so the barrel stays on the
	# crosshair whatever the pitch.
	rig.aim_pitch = player.pitch
	rig.pitch_pivot = EYE
	rig.show_head = player.third_person
	_pose()


func _apply_pose(pose: Array, rate: float) -> void:
	rig.t_grip = pose[0]
	rig.t_dir = pose[1]
	rig.pose_rate = rate


func _pose() -> void:
	rig.t_hand_r = null
	rig.t_hand_l = null
	rig.ramrod_on = false
	rig.bayonet_in_hand = false
	rig.t_lean = 0.0
	rig.hand_item = player.weapon if player.weapon in ["pistol", "saber"] else ""

	if player.is_throwing():
		# Musket dropped to the left hand; the right hand winds back over the
		# shoulder and whips forward, releasing the grenade.
		var tp: float = player.throw_progress()
		rig.bayonet_on = player.weapon == "melee"
		_apply_pose([READY[0] + Vector3(-0.12, -0.2, 0.08), READY[1] + Vector3(0, 0.3, 0)], 14.0)
		var back := Vector3(0.38, 1.78, 0.28)
		var out := Vector3(0.22, 1.55, -0.65)
		var rest: Vector3 = (READY[0] as Vector3) + Vector3(-0.12, -0.2, 0.08)
		if tp < 0.5:
			rig.t_hand_r = rest.lerp(back, smoothstep(0.0, 0.5, tp))
		elif tp < 0.7:
			rig.t_hand_r = back.lerp(out, smoothstep(0.5, 0.62, tp))
		else:
			rig.t_hand_r = out.lerp(rest, smoothstep(0.7, 1.0, tp))
		rig.pose_rate = 30.0
		return

	if player.is_switching() and (player.switch_target in ["pistol", "saber"] or player.switch_from in ["pistol", "saber"]):
		_draw_pose(player.switch_progress())
		return

	if player.is_switching():
		var sp: float = player.switch_progress()
		var fixing: bool = player.switch_target == "melee"
		if sp > 0.1 and sp < 0.86:
			_apply_pose(UPRIGHT, 9.0)
		else:
			var musket_end := (sp <= 0.1) == fixing
			_apply_pose(READY if musket_end else MELEE_IDLE, 9.0)
		rig.t_hand_r = _follow(FIX_PATH if fixing else UNFIX_PATH, sp)
		var state := ""
		if fixing:
			state = "off" if sp < 0.3 else ("hand" if sp < 0.72 else "on")
		else:
			state = "on" if sp < 0.2 else ("hand" if sp < 0.7 else "off")
		rig.bayonet_on = state == "on"
		rig.bayonet_in_hand = state == "hand"
		return

	if player.weapon == "musket":
		rig.bayonet_on = false
		if player.loaded:
			var a: float = player.aim_amount
			if a > 0.0:
				var k := a * a * (3.0 - 2.0 * a)
				_apply_pose([READY[0].lerp(AIM[0], k), READY[1].lerp(AIM[1], k)], 40.0)
				if k > 0.5:
					# Left hand cupped under the forestock, close to the lock,
					# so the barrel and front sight stay clear.
					var d: Vector3 = (AIM[1] as Vector3).normalized()
					rig.t_hand_l = AIM[0] + d * 0.2 + Vector3(0, -0.065, 0)
			else:
				_apply_pose(READY, 14.0)
			return
		var rp: float = player.reload_progress()
		if rp < 0.04:
			# Recoil kick right after the shot.
			_apply_pose([READY[0] + Vector3(0, 0.04, 0.1), READY[1] + Vector3(0, 0.15, 0)], 30.0)
		elif rp < 0.29:
			_apply_pose(PRIME, 8.0)
		elif rp < 0.84:
			_apply_pose(UPRIGHT, 8.0)
		else:
			_apply_pose(READY, 8.0)
		rig.t_hand_r = _follow(RELOAD_PATH, rp)
		rig.ramrod_on = rp > 0.42 and rp < 0.78
		return

	if player.weapon == "pistol":
		_pistol_pose()
		return
	if player.weapon == "saber":
		_saber_pose()
		return

	rig.bayonet_on = true
	var dir: int = player.swing_dir
	match player.swing_phase:
		"windup":
			_apply_pose(WINDUP[dir if dir >= 0 else 3], 11.0)
		"strike":
			_apply_pose(STRIKE[dir], 40.0)
			rig.t_lean = 0.12
		"recover":
			_apply_pose(STRIKE[dir] if player.phase_time < 0.06 else MELEE_IDLE, 12.0)
		_:
			_apply_pose(BLOCK if player.blocking else MELEE_IDLE, 20.0 if player.blocking else 14.0)


## Drawing or putting away a sidearm: the hand goes to the sash or the
## scabbard (or over the shoulder for the musket), and comes back with the
## new weapon. The item swaps hands at the halfway point.
func _draw_pose(sp: float) -> void:
	var from: String = player.switch_from
	var to: String = player.switch_target
	var first := sp < 0.5
	var item := from if first else to
	rig.hand_item = item if item in ["pistol", "saber"] else ""
	rig.bayonet_on = item == "melee"
	var stash := func(w: String) -> Vector3:
		match w:
			"pistol": return P_HOLSTER
			"saber": return S_HILT
		return Vector3(0.22, 1.5, 0.12) # over the shoulder for the musket
	var ready := func(w: String) -> Array:
		match w:
			"pistol": return P_READY
			"saber": return S_IDLE
			"melee": return MELEE_IDLE
		return READY
	var k: float = smoothstep(0.0, 0.5, sp) if first else smoothstep(0.5, 1.0, sp)
	if first:
		var r: Array = ready.call(from)
		var pos: Vector3 = (r[0] as Vector3).lerp(stash.call(from), k)
		_apply_pose([pos, (r[1] as Vector3).lerp(Vector3(0, -1, 0.2), k * 0.8)], 30.0)
	else:
		var r2: Array = ready.call(to)
		var pos2: Vector3 = (stash.call(to) as Vector3).lerp(r2[0], k)
		_apply_pose([pos2, Vector3(0, 1, 0.2).lerp(r2[1], k)], 30.0)
	rig.t_hand_r = null
	if rig.hand_item == "":
		# Musket coming off (or going over) the shoulder: both hands on it.
		rig.t_hand_l = null


func _pistol_pose() -> void:
	if player.pistol_loaded:
		var a: float = player.aim_amount
		var k := a * a * (3.0 - 2.0 * a)
		_apply_pose([(P_READY[0] as Vector3).lerp(P_AIM[0], k), (P_READY[1] as Vector3).lerp(P_AIM[1], k)], 30.0)
		return
	var rp: float = player.pistol_reload_progress()
	if rp < 0.06:
		_apply_pose([P_READY[0] + Vector3(0, 0.08, 0.08), P_READY[1] + Vector3(0, 0.6, 0)], 30.0)
		return
	if rp > 0.88:
		_apply_pose(P_READY, 10.0)
		# Thumb back the hammer.
		rig.t_hand_l = (P_READY[0] as Vector3) + Vector3(0.02, 0.05, 0.02)
		return
	_apply_pose(P_LOAD, 9.0)
	var muzzle: Vector3 = (P_LOAD[0] as Vector3) + (P_LOAD[1] as Vector3).normalized() * 0.3
	if rp < 0.3:
		rig.t_hand_l = Vector3(0.0, 1.46, -0.3) # biting the cartridge
	elif rp < 0.45:
		rig.t_hand_l = muzzle + Vector3(0, 0.05, 0) # pouring
	else:
		var ram := absf(sin((rp - 0.45) * 30.0))
		rig.t_hand_l = muzzle + Vector3(0, 0.03 + 0.12 * ram, 0)


func _saber_pose() -> void:
	var dir: int = player.swing_dir
	match player.swing_phase:
		"windup":
			_apply_pose(S_WINDUP[dir if dir >= 0 else 3], 12.0)
		"strike":
			_apply_pose(S_STRIKE[dir], 46.0)
			rig.t_lean = 0.14
		"recover":
			_apply_pose(S_STRIKE[dir] if player.phase_time < 0.05 else S_IDLE, 14.0)
		_:
			_apply_pose(S_BLOCK if player.blocking else S_IDLE, 22.0 if player.blocking else 14.0)


## Right-hand waypoints relative to the current target pose.
func _waypoints() -> Dictionary:
	var grip: Vector3 = rig.t_grip
	var d: Vector3 = (rig.t_dir as Vector3).normalized()
	var muzzle: Vector3 = grip + d * Rig3D.MUZZLE
	return {
		"A": grip,
		"B": grip + Vector3(0.07, 0.1, -0.02),
		"C": muzzle + Vector3(0.03, 0.08, 0.0),
		"D": muzzle + d * 0.34,
		"E": muzzle + d * 0.06,
		"F": muzzle + d * 0.32 + Vector3(0.04, 0, 0),
		"H": Vector3(0.28, 0.95, 0.05),
		"M": Vector3(0.03, 1.56, -0.17), # at your mouth: biting the cartridge
		"L": grip + d * 0.02 + Vector3(0.05, 0.05, 0.0), # at the lock: the pan, the hammer
	}


func _follow(path: Array, t: float) -> Vector3:
	var pts := _waypoints()
	for i in range(1, path.size()):
		var t1: float = path[i][0]
		if t <= t1 or i == path.size() - 1:
			var t0: float = path[i - 1][0]
			var a: Vector3 = pts[path[i - 1][1]]
			var b: Vector3 = pts[path[i][1]]
			var k := clampf((t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
			return a.lerp(b, k * k * (3.0 - 2.0 * k))
	return pts["A"]
