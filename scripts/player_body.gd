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

const RELOAD_PATH := [[0.0, "A"], [0.08, "A"], [0.16, "B"], [0.24, "B"], [0.32, "C"],
	[0.38, "D"], [0.46, "E"], [0.52, "D"], [0.58, "E"], [0.64, "D"], [0.70, "E"],
	[0.76, "D"], [0.84, "B"], [0.92, "A"], [1.0, "A"]]
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
	rig.aim_pitch = player.pitch * 0.9
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
			_apply_pose(READY, 14.0)
			return
		var rp: float = player.reload_progress()
		if rp < 0.04:
			# Recoil kick right after the shot.
			_apply_pose([READY[0] + Vector3(0, 0.04, 0.1), READY[1] + Vector3(0, 0.15, 0)], 30.0)
		elif rp < 0.9:
			_apply_pose(UPRIGHT, 8.0)
		else:
			_apply_pose(READY, 8.0)
		rig.t_hand_r = _follow(RELOAD_PATH, rp)
		rig.ramrod_on = rp > 0.34 and rp < 0.77
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
