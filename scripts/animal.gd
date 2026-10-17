extends Node3D
## Game for the hunt (battle.gd's hunt, from a hunting ground or fishing
## water on the map): a deer, or a fish in the river.
##
## Deer graze and wander in small herds. Something coming close (you on
## foot under 20 m, on a horse under 30), or a shot within 70 m, and they
## bolt, away from you, for a good while. Fish swim slow in the river and
## dart off when a ball strikes the water near them.
##
## They live in battle.enemies so the shots, blades and blasts that find
## the enemy find them too (the same few things: alive, hit_radius,
## hit_height, take_shot, take_damage, receive_blow, stagger).

const Rig3D := preload("res://scripts/rig3d.gd")

var battle
var kind := "deer" # or "fish"
var alive := true
var hp := 70.0
var hit_radius := 0.6
var hit_height := 1.5
var rig_kind := "animal"
var velocity := Vector3.ZERO
var meat := 0 # lb it gives
var rig
var _mesh: Node3D
var _yaw := 0.0
var _speed := 0.0
var _want := Vector3.ZERO
var _calm_t := 0.0 # > 0: still bolting
var _pick_t := 0.0
var _home := Vector3.ZERO
var last_hit_by: Node3D = null
var lure = null # a float in the water this fish has noticed (fishing.gd): it swims to it
var hooked := false # on the line: fishing.gd moves it
var kills := 0


static func make(b, k: String, at: Vector3):
	var a = load("res://scripts/animal.gd").new()
	a.battle = b
	a.kind = k
	a.position = at
	a._home = at
	return a


func _ready() -> void:
	_yaw = randf() * TAU
	if kind == "deer":
		meat = randi_range(30, 45)
		hp = 70.0
		hit_radius = 0.55
		hit_height = 1.5
		rig = Rig3D.new()
		rig.kind = "horse"
		rig.gear = {"deer": true}
		rig.scale = Vector3.ONE * 0.72
		add_child(rig)
	else:
		meat = randi_range(3, 6)
		hp = 15.0
		hit_radius = 0.4
		hit_height = 0.35
		_mesh = Node3D.new()
		add_child(_mesh)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.64, 0.62)
		mat.metallic = 0.4
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.14, 0.55)
		var b := MeshInstance3D.new()
		b.mesh = bm
		b.material_override = mat
		_mesh.add_child(b)
		var tm := BoxMesh.new()
		tm.size = Vector3(0.03, 0.16, 0.14)
		var t := MeshInstance3D.new()
		t.mesh = tm
		t.material_override = mat
		t.position = Vector3(0, 0, 0.33)
		_mesh.add_child(t)
		var fm := BoxMesh.new()
		fm.size = Vector3(0.025, 0.14, 0.16)
		var fin := MeshInstance3D.new()
		fin.mesh = fm
		fin.material_override = mat
		fin.position = Vector3(0, 0.12, 0.02)
		_mesh.add_child(fin)
		# A ripple ring round it on the surface.
		var rm := CylinderMesh.new()
		rm.top_radius = 0.45
		rm.bottom_radius = 0.45
		rm.height = 0.01
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.85, 0.9, 0.95, 0.35)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.material = rmat
		var ring := MeshInstance3D.new()
		ring.mesh = rm
		ring.position = Vector3(0, 0.21, 0)
		_mesh.add_child(ring)
		_mesh.position.y = 0.15


func _physics_process(delta: float) -> void:
	if not alive or hooked:
		return
	var pl = battle.player
	var to_pl: Vector3 = pl.global_position - global_position
	to_pl.y = 0.0
	if kind == "deer":
		var near := 30.0 if pl.mounted else 20.0
		if pl.alive and to_pl.length() < near:
			scare(pl.global_position)
	_calm_t -= delta
	_pick_t -= delta
	var top := 0.0
	if _calm_t > 0.0:
		top = 9.5 if kind == "deer" else 3.5
	else:
		top = 1.0 if kind == "deer" else 0.6
		if lure != null:
			var tl: Vector3 = lure - global_position
			tl.y = 0.0
			_want = tl.normalized() if tl.length() > 0.45 else Vector3.ZERO
			top = 0.7
			_pick_t = 1.0
		elif _pick_t <= 0.0:
			_pick_t = randf_range(3.0, 8.0)
			if kind == "deer" and randf() < 0.45:
				_want = Vector3.ZERO # stand and graze
			else:
				_want = _wander_dir()
	if _want.length_squared() > 0.001:
		var wy := atan2(-_want.x, -_want.z)
		_yaw += clampf(angle_difference(_yaw, wy), -3.0 * delta, 3.0 * delta)
		_speed = move_toward(_speed, top, (6.0 if _calm_t > 0.0 else 1.5) * delta)
	else:
		_speed = move_toward(_speed, 0.0, 3.0 * delta)
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	velocity = fwd * _speed
	var np := global_position + velocity * delta
	var terr = battle.field.terrain
	if kind == "fish":
		# Stay in the deep water.
		if terr.height(np.x, np.z) > terr.water_y - 0.7:
			_want = -fwd
			_yaw += PI * 0.5
			np = global_position
		np.y = terr.water_y - 0.2 # (just under: the back and the fin show)
	else:
		if absf(np.x) > 140.0 or absf(np.z) > 140.0 or (terr.has_water and terr.height(np.x, np.z) < terr.water_y + 0.1):
			_want = -fwd
			np = global_position
		np.y = terr.height(np.x, np.z)
	global_position = np
	rotation.y = _yaw
	if rig != null:
		rig.facing = fwd
		rig.move_speed = _speed * 1.3
		rig.anim = "walk"
		rig.anim_time += delta
		# Grazing: the head down while standing.
		rig.neck_dip = 0.0 if _speed > 0.3 or _calm_t > 0.0 else 0.9


func _wander_dir() -> Vector3:
	var a := randf() * TAU
	var d := Vector3(cos(a), 0, sin(a))
	# Drift back toward home if strayed.
	var back := _home - global_position
	back.y = 0.0
	if back.length() > 35.0:
		d = (d + back.normalized() * 1.5).normalized()
	return d


## Something frightening at `from`: run, away from it.
func scare(from: Vector3) -> void:
	if not alive:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf() - 0.5, 0, randf() - 0.5)
	_want = (away.normalized() + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))).normalized()
	_calm_t = randf_range(7.0, 11.0) if kind == "deer" else 2.5
	_pick_t = _calm_t
	lure = null


func take_shot(amount: float, from: Node3D = null) -> void:
	take_damage(amount, from)


func take_damage(amount: float, from: Node3D = null) -> void:
	if not alive:
		return
	last_hit_by = from
	hp -= amount
	if hp <= 0.0:
		_die()
	else:
		scare(from.global_position if from != null and is_instance_valid(from) else global_position + Vector3.FORWARD)


func receive_blow(damage: float, from: Node3D, _heavy: bool) -> String:
	take_damage(damage, from)
	return "hit"


func stagger(_push: Vector3, _s: float) -> void:
	pass


func _die() -> void:
	alive = false
	velocity = Vector3.ZERO
	battle.enemies.erase(self)
	battle.on_game_down(self)
	if rig != null:
		rig._dead = true
		var tw := create_tween().set_parallel(true)
		tw.tween_property(rig.body, "rotation:z", 1.45, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(rig.body, "position:y", -0.45, 0.6)
	elif _mesh != null:
		# Belly up, floating.
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(_mesh, "rotation:z", PI, 0.5)
		tw2.tween_property(self, "position:y", battle.field.terrain.water_y - 0.05, 1.2)
