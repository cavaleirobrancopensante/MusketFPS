extends Node
## Far stand-in sprites rendered from the 3D rigs themselves, at the start of
## a battle, so every kind of unit (pikemen with their pikes, red coats,
## horse and rider, raptors, brutes) has a sprite that looks like it.
##
## For each kind, one off-screen render: a grid of rigs (front, side and
## back views down the rows, every animation frame along the columns), each
## posed and tilted back a little toward an orthographic camera, as if seen
## from somewhat above (the command view looks down; first person looks
## level, and a mild tilt reads well from both). The picture is cut into
## 64 px cells and handed to the Batcher like the hand-drawn sprites.
##
## Without a renderer (headless tests) it returns nothing and the units keep
## the hand-drawn soldier and lizard sprites.

const Rig3D := preload("res://scripts/rig3d.gd")
const BatcherScript := preload("res://scripts/batcher.gd")

const CELL_PX := 128 # rendered size of a cell (shrunk to 64 for the atlas)
const TILT := deg_to_rad(24.0)
const FOOT_ANIMS := {"idle": 1, "walk": 4, "aim": 1, "fire": 1, "reload": 2, "guard": 1, "thrust": 1, "block": 1}
const LIZARD_ANIMS := {"idle": 1, "walk": 4, "windup": 1, "strike": 1, "stagger": 1, "shield": 1}
const RIDER_ANIMS := {"idle": 1, "walk": 4, "charge": 4, "windup": 1, "strike": 1}
const VIEWS := ["front", "side", "back"]


static func available() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name() != ""


## spec: {rig: "soldier"/"lizard", gear: {}, coat: Color or null, mount: ""/"horse"/"raptor",
##        scale: float, cell_m: float (world size of a cell), anims: {...}}
## Returns frames for Batcher.add_sprite_kind ({"counts", "view_anim_i": Texture2D}), or {}.
static func render(host: Node, spec: Dictionary) -> Dictionary:
	if not available():
		return {}
	var anims: Dictionary = spec["anims"]
	var frames: Array = [] # [anim, i]
	for a in anims:
		for i in int(anims[a]):
			frames.append([a, i])
	var cols := frames.size()
	var rows := VIEWS.size()
	var cell_m: float = spec["cell_m"]
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * CELL_PX, rows * CELL_PX)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var b = BatcherScript.new()
	b.add_to_group("batcher")
	vp.add_child(b)
	b._blob_mm = null # (no shade blobs under them)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * cell_m
	cam.position = Vector3(cols * cell_m * 0.5, rows * cell_m * 0.5, 50.0)
	cam.near = 1.0
	cam.far = 100.0
	vp.add_child(cam)
	cam.current = true
	var rigs: Array = []
	for row in rows:
		var view: String = VIEWS[row]
		var facing: Vector3 = {"front": Vector3.BACK, "side": Vector3.RIGHT, "back": Vector3.FORWARD}[view]
		for col in cols:
			var holder := Node3D.new()
			# Row 0 at the top of the picture.
			holder.position = Vector3((col + 0.5) * cell_m, (rows - 1 - row) * cell_m + cell_m * 0.04, 0)
			holder.rotation.x = -TILT # leaning back toward the camera: seen from above
			vp.add_child(holder)
			var r: Node3D = _make_rig(spec)
			holder.add_child(r)
			r.set_process(false)
			var rider = (r.get_meta("rider") if r.has_meta("rider") else null)
			if rider != null:
				rider.set_process(false)
			var a: String = frames[col][0]
			var i: int = frames[col][1]
			_pose(r, a, i, int(anims[a]), facing, spec)
			rigs.append(r)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var out := {"counts": anims}
	for row in rows:
		for col in cols:
			var cell := img.get_region(Rect2i(col * CELL_PX, row * CELL_PX, CELL_PX, CELL_PX))
			cell.resize(64, 64, Image.INTERPOLATE_BILINEAR) # (the sprite shader cuts at half alpha)
			out["%s_%s_%d" % [VIEWS[row], frames[col][0], frames[col][1]]] = ImageTexture.create_from_image(cell)
	return out


static func _make_rig(spec: Dictionary):
	var mount: String = spec.get("mount", "")
	var r = Rig3D.new()
	if mount != "":
		r.kind = mount
		r.gear = {"saddle_col": spec.get("saddle", Color(0.16, 0.24, 0.55))}
		var rider = Rig3D.new()
		rider.seated = true
		if mount == "horse":
			rider.kind = "soldier"
			rider.gear = spec.get("gear", {})
			rider.pack = {"rations": 0, "water": 0, "ammo": 0}
			rider.hand_item = "saber"
			rider.coat_override = spec.get("coat", null)
			rider.position = Rig3D.SADDLE_HORSE
		else:
			rider.kind = "lizard"
			rider.position = Rig3D.SADDLE_RAPTOR + Vector3(0, -0.08, 0)
		r.set_meta("rider", rider)
		r.ready.connect(func(): r.body.add_child(rider), CONNECT_ONE_SHOT)
	else:
		r.kind = spec["rig"]
		r.gear = spec.get("gear", {})
		r.pack = spec.get("pack", {"rations": 2, "water": 1, "ammo": 20})
		r.coat_override = spec.get("coat", null)
	r.scale = Vector3.ONE * float(spec.get("scale", 1.0))
	return r


static func _pose(r, a: String, i: int, n: int, facing: Vector3, spec: Dictionary) -> void:
	var rider = (r.get_meta("rider") if r.has_meta("rider") else null)
	var walk := a in ["walk", "charge"]
	r.facing = facing
	r.anim = a if rider == null else "walk"
	r.anim_time = 0.05 + 0.3 * i
	r.move_speed = (3.0 if a == "walk" else 9.0) if walk else 0.0
	r._walk_phase = TAU * float(i) / maxf(1.0, n) + 0.3
	if spec.get("mount", "") == "" and spec["rig"] == "lizard":
		r.scale = Vector3.ONE * 1.12 * float(spec.get("scale", 1.0))
	r._update(0.0, true)
	r._emit()
	if rider != null:
		rider.facing = facing
		rider.anim = a if spec.get("mount", "") == "horse" else {"charge": "walk", "windup": "windup", "strike": "strike"}.get(a, "idle")
		rider.anim_time = r.anim_time
		rider._update(0.0, true)
		rider._emit()
