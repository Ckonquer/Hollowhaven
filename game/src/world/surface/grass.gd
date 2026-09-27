extends MultiMeshInstance3D
## Camera-following GPU grass patch (see shaders/surface_grass.gdshader). Density follows
## Settings "quality" (0 low, 1 medium, 2 high) and the terrain's grass mask.
##   var g = Grass.new(); g.terrain = terrain; parent.add_child(g)

const Palette := preload("res://src/art/palette.gd")
const GRASS_SHADER := preload("res://shaders/surface_grass.gdshader")

const PERIOD := 8.0                          # jitter pattern repeats every 8 m; node snaps to it
const QUALITY := [                           # [spacing, radius, fade_start, fade_end]
	[0.9, 26.0, 16.0, 24.0],
	[0.62, 32.0, 21.0, 30.0],
	[0.46, 38.0, 26.0, 36.0],
]

var terrain: RefCounted
var grass_material: ShaderMaterial
var _quality := -1
var _snap := Vector2(1e9, 1e9)


func _ready() -> void:
	name = "Grass"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass_material = ShaderMaterial.new()
	grass_material.shader = GRASS_SHADER
	grass_material.set_shader_parameter("height_tex", ImageTexture.create_from_image(terrain.height_image()))
	grass_material.set_shader_parameter("mask_tex", ImageTexture.create_from_image(terrain.grass_image()))
	grass_material.set_shader_parameter("color_tex", ImageTexture.create_from_image(terrain.color_image()))
	grass_material.set_shader_parameter("tip_warm", Color("e2d27c"))
	material_override = grass_material
	_apply_quality()
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func _on_settings_changed(key: String) -> void:
	if key == "quality":
		_apply_quality()


static func clump_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for b in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.02, 0.2)
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var hgt := rng.randf_range(0.6, 1.0)
		var lean := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.08, 0.25)
		var side := Vector3(-sin(a), 0.0, cos(a)) * rng.randf_range(0.035, 0.055)
		var mid := root + lean * 0.35 + Vector3(0, hgt * 0.5, 0)
		var tip := root + lean + Vector3(0, hgt, 0)
		# two quads-worth: root->mid (4 verts as 2 tris) and mid->tip (1 tri)
		var tri: Array = [
			[root - side, 0.0], [mid - side * 0.75, 0.5], [root + side, 0.0],
			[root + side, 0.0], [mid - side * 0.75, 0.5], [mid + side * 0.75, 0.5],
			[mid - side * 0.75, 0.5], [tip, 1.0], [mid + side * 0.75, 0.5],
		]
		for t in tri:
			verts.append(t[0])
			uvs.append(Vector2(0.5, float(t[1])))
			norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_quality() -> void:
	var q := clampi(int(Settings.get_value("quality")), 0, 2)
	if q == _quality:
		return
	_quality = q
	var cfg: Array = QUALITY[q]
	var spacing: float = cfg[0]
	var radius: float = cfg[1]
	grass_material.set_shader_parameter("fade_start", float(cfg[2]))
	grass_material.set_shader_parameter("fade_end", float(cfg[3]))
	# Per-period jitter pattern (identical in every 8 m tile so snapping never moves blades).
	var per := maxi(1, int(round(PERIOD / spacing)))
	var cell := PERIOD / float(per)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090
	var pattern := PackedVector2Array()
	for j in per:
		for i in per:
			pattern.append(Vector2((float(i) + rng.randf_range(0.1, 0.9)) * cell, (float(j) + rng.randf_range(0.1, 0.9)) * cell))
	var tiles := int(ceil(radius * 2.0 / PERIOD))
	var count := tiles * tiles * pattern.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = clump_mesh()
	mm.instance_count = count
	var buf := PackedFloat32Array()
	buf.resize(count * 12)
	var o := -float(tiles) * PERIOD * 0.5
	var n := 0
	for ty in tiles:
		for tx in tiles:
			var bx := o + float(tx) * PERIOD
			var bz := o + float(ty) * PERIOD
			for p in pattern:
				var b := n * 12
				buf[b] = 1.0
				buf[b + 3] = bx + p.x
				buf[b + 5] = 1.0
				buf[b + 10] = 1.0
				buf[b + 11] = bz + p.y
				n += 1
	mm.buffer = buf
	multimesh = mm
	var ext := float(tiles) * PERIOD * 0.5 + 2.0
	custom_aabb = AABB(Vector3(-ext, -60.0, -ext), Vector3(ext * 2.0, 160.0, ext * 2.0))
	_snap = Vector2(1e9, 1e9)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var c := cam.global_position
		var sx := floorf(c.x / PERIOD) * PERIOD
		var sz := floorf(c.z / PERIOD) * PERIOD
		if sx != _snap.x or sz != _snap.y:
			_snap = Vector2(sx, sz)
			global_position = Vector3(sx, 0.0, sz)
	var p: Node = Game.player
	if p != null and is_instance_valid(p) and p is Node3D:
		grass_material.set_shader_parameter("player_pos", (p as Node3D).global_position)
