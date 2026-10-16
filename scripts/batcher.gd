extends Node3D
## Draws every character on the field in a handful of instanced batches, so
## the cost of drawing barely grows with the size of the battle.
##
## 3D: every body part is a unit box, cylinder or sphere stretched by its
## transform and tinted by a per-instance colour, so ALL bodies in the battle
## are three MultiMeshes (three draw calls). Each Rig3D keeps a ready-made
## float buffer of its parts; we just concatenate them.
##
## 2D (and far-away stand-ins in 3D): every sprite frame of a kind lives in
## one atlas texture, and each unit is one instance of a quad that a shader
## turns to face the camera and points at the right frame. One draw call per
## kind (soldiers, lizardmen).
##
## Runs late (process_priority) so units and rigs have already updated.

const SHAPE_BOX := 0
const SHAPE_CYL := 1
const SHAPE_SPHERE := 2
const FLOATS_3D := 16 # 12 transform + 4 colour
const FLOATS_SPRITE := 20 # 12 transform + 4 colour + 4 custom

const SPRITE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;
uniform sampler2D atlas : source_color, filter_nearest;
uniform vec2 cell_size;
varying vec4 tint;

void vertex() {
	// INSTANCE_CUSTOM: atlas cell x, cell y, flip, lying (corpse).
	vec2 q = VERTEX.xy;
	vec2 luv = vec2(q.x + 0.5, 0.5 - q.y);
	if (INSTANCE_CUSTOM.z > 0.5) { luv.x = 1.0 - luv.x; }
	UV = (INSTANCE_CUSTOM.xy + luv) * cell_size;
	vec3 world;
	if (INSTANCE_CUSTOM.w > 0.5) {
		// Corpse: use the full transform (laid flat on the ground).
		world = (MODEL_MATRIX * vec4(q.x, q.y + 0.5, 0.0, 1.0)).xyz;
	} else {
		// Standing: billboard around the vertical axis, feet on the ground.
		vec3 origin = MODEL_MATRIX[3].xyz;
		float w = length(MODEL_MATRIX[0].xyz);
		float h = length(MODEL_MATRIX[1].xyz);
		vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
		world = origin + right * q.x * w + vec3(0.0, 1.0, 0.0) * (q.y + 0.5) * h;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < 0.5) { discard; }
	ALBEDO = c.rgb * tint.rgb;
}
"""

var _mm3d: Array = [] # MultiMesh per shape
var _rigs: Array = []
var _sprite_mm := {} # kind -> MultiMesh
var _sprite_units := {} # kind -> Array of units
var _atlas := {} # kind -> {"cells": {key: Vector2i}, "counts": ...}


func _ready() -> void:
	process_priority = 1000
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var box := BoxMesh.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 10
	sph.rings = 6
	for mesh in [box, cyl, sph]:
		mesh.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		_mm3d.append(mm)
		_add_instance(mm)


func _add_instance(mm: MultiMesh) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The battle covers the whole field; skip per-frame bounds work.
	mmi.custom_aabb = AABB(Vector3(-600, -20, -600), Vector3(1200, 60, 1200))
	add_child(mmi)


# ---------------------------------------------------------------- 3D rigs

func add_rig(r) -> void:
	_rigs.append(r)


func remove_rig(r) -> void:
	_rigs.erase(r)


# ---------------------------------------------------------------- sprites

## Pack a kind's sprite frames into one atlas and set up its batch.
## Returns the frame lookup: {"cells": {key: Vector2i}, "counts": {...}}.
func add_sprite_kind(kind: String, frames: Dictionary) -> Dictionary:
	var keys: Array = []
	for k in frames:
		if k != "counts":
			keys.append(k)
	keys.sort()
	var cols := 16
	var rows := ceili(float(keys.size()) / cols)
	var cell_px := 64
	var img := Image.create(cols * cell_px, rows * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cells := {}
	for i in keys.size():
		var cell := Vector2i(i % cols, i / cols)
		cells[keys[i]] = cell
		var fimg: Image = (frames[keys[i]] as Texture2D).get_image()
		img.blit_rect(fimg, Rect2i(0, 0, cell_px, cell_px), cell * cell_px)
	var shader := Shader.new()
	shader.code = SPRITE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("cell_size", Vector2(1.0 / cols, 1.0 / rows))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	_sprite_mm[kind] = mm
	_sprite_units[kind] = []
	_add_instance(mm)
	# Lookup table: view -> anim -> [cells per frame], so picking a frame each
	# tick is two dictionary reads instead of building a text key.
	var lookup := {}
	var counts: Dictionary = frames["counts"]
	for view in ["front", "side", "back"]:
		var per_anim := {}
		for anim in counts:
			var arr: Array = []
			for i in int(counts[anim]):
				arr.append(cells["%s_%s_%d" % [view, anim, i]])
			per_anim[anim] = arr
		# Animations without their own frames (a soldier's block) use guard.
		if not per_anim.has("block"):
			per_anim["block"] = per_anim["guard"] if per_anim.has("guard") else per_anim["idle"]
		lookup[view] = per_anim
	var info := {"cells": cells, "counts": counts, "lookup": lookup}
	_atlas[kind] = info
	return info


func add_sprite(kind: String, unit) -> void:
	_sprite_units[kind].append(unit)


func remove_sprite(kind: String, unit) -> void:
	if _sprite_units.has(kind):
		_sprite_units[kind].erase(unit)


# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	# 3D parts: concatenate each visible rig's ready-made buffers per shape.
	for shape in 3:
		var buf := PackedFloat32Array()
		for r in _rigs:
			if r.draw_enabled():
				buf.append_array(r.cache[shape])
		_upload(_mm3d[shape], buf, FLOATS_3D)

	# Sprites: one instance per unit that is currently drawn as a sprite.
	for kind in _sprite_mm:
		var sbuf := PackedFloat32Array()
		for u in _sprite_units[kind]:
			if u.sprite_on:
				u.write_sprite(sbuf)
		_upload(_sprite_mm[kind], sbuf, FLOATS_SPRITE)


## Resize in steps (resizing a MultiMesh clears it) and hand over the buffer.
func _upload(mm: MultiMesh, buf: PackedFloat32Array, stride: int) -> void:
	var n := buf.size() / stride
	if mm.instance_count < n:
		mm.instance_count = maxi(64, nearest_po2(n))
	buf.resize(mm.instance_count * stride)
	mm.buffer = buf
	mm.visible_instance_count = n
