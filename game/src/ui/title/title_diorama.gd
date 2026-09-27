extends Node3D
## Title screen backdrop: a small cosy clearing at dusk built from Kit/Mat primitives. A little
## timber cottage with a lit round window, the softly glowing Ward Stone, a crackling campfire, a
## lantern post, trees and berry bushes, flowers, mushrooms, drifting fireflies and a slow camera drift.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const FIREFLIES := 44

var cam: Camera3D
var fire_light: OmniLight3D
var ward_light: OmniLight3D
var flames: Array = []
var embers: Array = []
var fireflies: MultiMeshInstance3D
var _ff_data: Array = []
var _t := 0.0
var _cam_base := Vector3(0.6, 2.05, 8.6)
var _look := Vector3(0.1, 1.35, -1.2)


func _ready() -> void:
	_environment()
	_ground()
	_cottage(Vector3(-3.3, 0, -2.6), 22.0)
	_ward_stone(Vector3(2.9, 0, -3.1))
	_campfire(Vector3(0.9, 0, 0.3))
	_trees()
	_details()
	_fireflies()
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 300.0
	add_child(cam)
	cam.position = _cam_base
	_aim()
	cam.make_current()


func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2c3169")
	sm.sky_horizon_color = Color("f29c74")
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color("2c3a2e")
	sm.ground_horizon_color = Color("d8a488")
	sm.sun_angle_max = 18.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("7a73b0")
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.fog_enabled = true
	e.fog_light_color = Color("a785a8")
	e.fog_density = 0.007
	e.fog_aerial_perspective = 0.5
	e.fog_sky_affect = 0.25
	e.ssao_enabled = true
	e.ssao_intensity = 1.2
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-11, -52, 0)
	sun.light_color = Color("ff9f62")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 140, 0)
	fill.light_color = Color("9fb4e8")
	fill.light_energy = 0.25
	add_child(fill)


func _ground() -> void:
	var g := Kit.cylinder(42.0, 42.0, 0.4, Mat.toon(Palette.GRASS, {"noise": 0.1}), 48)
	Kit.add(self, g, Vector3(0, -0.2, 0))
	# soft hills and a distant tree line
	for i in 9:
		var a := -2.6 + float(i) * 0.33
		var d := 26.0 + float(i % 3) * 4.0
		var hill := Kit.blob(7.0 + float(i % 2) * 3.0, Mat.toon(Palette.GRASS_DARK.darkened(0.1)), 11 + i, 0.15, 0.45)
		Kit.add(self, hill, Vector3(sin(a) * d, -1.0, -cos(a) * d))
	for i in 22:
		var a2 := -1.9 + float(i) * 0.18
		var d2 := 17.0 + float((i * 7) % 5) * 1.3
		var col := Palette.FOLIAGE_DARK.darkened(0.2 + float(i % 3) * 0.06)
		var tr := Kit.blob(2.2 + float(i % 3) * 0.5, Mat.toon(col, {"wind": 0.04}), 40 + i, 0.2, 1.3)
		Kit.add(self, tr, Vector3(sin(a2) * d2, 2.2, -cos(a2) * d2))
	# dirt path to the cottage
	var path_mat := Mat.toon(Palette.DIRT)
	for p in [Vector3(-0.2, 0.0, 4.0), Vector3(-1.0, 0.0, 2.6), Vector3(-1.9, 0.0, 1.2), Vector3(-2.6, 0.0, -0.2), Vector3(0.4, 0.0, 0.9)]:
		var patch := Kit.blob(1.0, path_mat, int(p.x * 10.0) + 3, 0.15, 0.05)
		Kit.add(self, patch, p + Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1.3, 1.0, 1.0))


func _cottage(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw
	var wall := Mat.outlined(Mat.toon(Palette.CLOTH_CREAM), 0.02)
	var timber := Mat.outlined(Mat.toon(Palette.WOOD_DARK), 0.015)
	Kit.add(root, Kit.box(Vector3(3.3, 0.35, 2.7), Mat.outlined(Mat.toon(Palette.STONE), 0.02)), Vector3(0, 0.17, 0))
	Kit.add(root, Kit.box(Vector3(3.0, 1.9, 2.4), wall), Vector3(0, 1.3, 0))
	for x in [-1.5, 1.5]:
		for z in [-1.2, 1.2]:
			Kit.add(root, Kit.box(Vector3(0.18, 1.95, 0.18), timber), Vector3(x, 1.3, z))
	Kit.add(root, Kit.box(Vector3(3.1, 0.16, 0.16), timber), Vector3(0, 2.2, 1.22))
	Kit.add(root, Kit.box(Vector3(3.1, 0.14, 0.14), timber), Vector3(0, 0.55, 1.22))
	# gable roof (ridge runs front-to-back, gable faces the camera)
	var roof := Kit.prism(Vector3(3.8, 1.5, 3.0), Mat.outlined(Mat.toon(Palette.THATCH, {"noise": 0.14}), 0.025))
	Kit.add(root, roof, Vector3(0, 3.0, 0))
	Kit.add(root, Kit.box(Vector3(0.45, 1.1, 0.45), Mat.outlined(Mat.toon(Palette.STONE_DARK), 0.02)), Vector3(0.95, 3.3, -0.5))
	# door and a round glowing window
	Kit.add(root, Kit.box(Vector3(0.8, 1.35, 0.1), Mat.outlined(Mat.toon(Palette.WOOD), 0.015)), Vector3(0.55, 0.95, 1.22))
	Kit.add(root, Kit.sphere(0.06, Mat.toon(Color("e2b95a"))), Vector3(0.82, 0.95, 1.29))
	var win := Kit.cylinder(0.32, 0.32, 0.08, Mat.glow(Palette.LANTERN_GLOW, 2.2), 24)
	Kit.add(root, win, Vector3(-0.7, 1.45, 1.22), Vector3(90, 0, 0))
	Kit.add(root, Kit.torus(0.3, 0.4, Mat.toon(Palette.WOOD_DARK)), Vector3(-0.7, 1.45, 1.24), Vector3(90, 0, 0))
	Kit.add(root, Kit.box(Vector3(0.62, 0.05, 0.05), Mat.toon(Palette.WOOD_DARK)), Vector3(-0.7, 1.45, 1.27))
	Kit.add(root, Kit.box(Vector3(0.05, 0.62, 0.05), Mat.toon(Palette.WOOD_DARK)), Vector3(-0.7, 1.45, 1.27))
	# a little lantern hanging by the door
	var metal := Mat.toon(Color("5b4a57"))
	Kit.add(root, Kit.box(Vector3(0.05, 0.05, 0.32), metal), Vector3(1.2, 1.95, 1.36))
	Kit.add(root, Kit.box(Vector3(0.18, 0.24, 0.18), Mat.glow(Palette.LANTERN_GLOW, 2.6)), Vector3(1.2, 1.72, 1.5))
	Kit.add(root, Kit.cone(0.15, 0.1, metal, 4), Vector3(1.2, 1.88, 1.5), Vector3(0, 45, 0))
	var dl := OmniLight3D.new()
	dl.light_color = Palette.LANTERN_GLOW
	dl.light_energy = 1.1
	dl.omni_range = 3.0
	root.add_child(dl)
	dl.position = Vector3(1.2, 1.6, 1.8)
	var wl := OmniLight3D.new()
	wl.light_color = Palette.LANTERN_GLOW
	wl.light_energy = 1.4
	wl.omni_range = 3.2
	root.add_child(wl)
	wl.position = Vector3(-0.7, 1.45, 1.7)
	# flower boxes & a little fence
	Kit.add(root, Kit.box(Vector3(0.8, 0.18, 0.22), Mat.toon(Palette.WOOD)), Vector3(-0.7, 1.02, 1.36))
	for i in 4:
		Kit.add(root, Kit.sphere(0.08, Mat.toon([Palette.FLOWER_RED, Palette.FLOWER_YELLOW, Palette.BLOSSOM, Palette.FLOWER_WHITE][i])), Vector3(-0.98 + float(i) * 0.18, 1.14, 1.38))
	var fence_mat := Mat.outlined(Mat.toon(Color("e8d7b5")), 0.012)
	for i in 5:
		Kit.add(root, Kit.box(Vector3(0.1, 0.7, 0.1), fence_mat), Vector3(1.9 + float(i) * 0.42, 0.35, 1.9))
	Kit.add(root, Kit.box(Vector3(1.9, 0.08, 0.06), fence_mat), Vector3(2.75, 0.5, 1.9))
	Kit.add(root, Kit.box(Vector3(1.9, 0.08, 0.06), fence_mat), Vector3(2.75, 0.25, 1.9))


func _ward_stone(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation_degrees = Vector3(0, -18, -3)
	var stone_col := Color("9c978f")
	var stone := Kit.blob(0.72, Mat.outlined(Mat.toon(stone_col, {"noise": 0.16}), 0.025), 23, 0.26, 2.15)
	Kit.add(root, stone, Vector3(0, 1.45, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.72))
	Kit.add(root, Kit.blob(0.5, Mat.toon(Palette.MOSS), 9, 0.3, 0.42), Vector3(0.08, 2.9, 0.0))
	Kit.add(root, Kit.blob(0.25, Mat.toon(Palette.MOSS.darkened(0.1)), 19, 0.3, 0.6), Vector3(-0.45, 0.55, 0.3))
	Kit.add(root, Kit.blob(0.95, Mat.toon(Palette.STONE_DARK.darkened(0.1)), 12, 0.2, 0.3), Vector3(0, 0.05, 0))
	# dimming ward runes: a small circle of glowing marks on the front face
	var rune_mat := Mat.glow(Color("ffcf6a"), 2.6)
	for i in 7:
		var a := TAU * float(i) / 7.0
		Kit.add(root, Kit.sphere(0.045, rune_mat, 6, 8), Vector3(cos(a) * 0.3, 1.55 + sin(a) * 0.3, 0.52), Vector3.ZERO, Vector3(1, 1, 0.4))
	Kit.add(root, Kit.sphere(0.12, Mat.glow(Color("ffcf6a"), 3.4), 10, 12), Vector3(0, 1.55, 0.5), Vector3.ZERO, Vector3(1, 1, 0.5))
	ward_light = OmniLight3D.new()
	ward_light.light_color = Palette.WARD_GLOW
	ward_light.light_energy = 0.9
	ward_light.omni_range = 3.2
	root.add_child(ward_light)
	ward_light.position = Vector3(0, 1.5, 1.0)
	for i in 7:
		var a2 := TAU * float(i) / 7.0 + 0.4
		Kit.add(root, Kit.blob(0.2, Mat.outlined(Mat.toon(Palette.STONE_DARK), 0.012), 30 + i, 0.3, 0.7), Vector3(cos(a2) * 1.3, 0.1, sin(a2) * 1.3))


func _campfire(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	for i in 8:
		var a := TAU * float(i) / 8.0
		Kit.add(root, Kit.blob(0.17, Mat.outlined(Mat.toon(Palette.STONE), 0.012), 50 + i, 0.25, 0.75), Vector3(cos(a) * 0.55, 0.1, sin(a) * 0.55))
	var log_mat := Mat.outlined(Mat.toon(Palette.BARK), 0.012)
	for i in 3:
		var lg := Kit.cylinder(0.07, 0.07, 0.8, log_mat, 10)
		Kit.add(root, lg, Vector3(0, 0.14, 0), Vector3(70, float(i) * 60.0, 0))
	var outer := _flame(Color("ff6a1f"), 0.22, 3.2)
	Kit.add(root, outer, Vector3(0, 0.2, 0))
	var inner := _flame(Color("ffc23d"), 0.13, 4.0)
	Kit.add(root, inner, Vector3(0, 0.2, 0.06))
	for k in 5:
		var ember := Kit.sphere(0.025, Mat.glow(Color("ffb050"), 4.0), 4, 6)
		Kit.add(root, ember, Vector3(sin(float(k) * 2.1) * 0.25, 0.7 + float(k) * 0.18, cos(float(k) * 1.7) * 0.2))
		embers.append(ember)
	flames = [outer, inner]
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color("ffa860")
	fire_light.light_energy = 2.0
	fire_light.omni_range = 5.5
	fire_light.shadow_enabled = true
	root.add_child(fire_light)
	fire_light.position = Vector3(0, 0.8, 0)
	# a log bench to sit on
	var bench := Kit.cylinder(0.2, 0.2, 1.5, log_mat, 12)
	Kit.add(root, bench, Vector3(1.45, 0.2, 0.55), Vector3(0, 60, 90))


## Teardrop flame: a glowing ball with a cone tip (pivot at the base).
func _flame(col: Color, r: float, energy: float) -> Node3D:
	var n := Node3D.new()
	var mat := Mat.glow(col, energy)
	Kit.add(n, Kit.sphere(r, mat, 10, 14), Vector3(0, r, 0))
	Kit.add(n, Kit.cone(r * 0.96, r * 2.6, mat, 14), Vector3(0, r + r * 1.3, 0))
	return n


func _lantern_post(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var wood := Mat.outlined(Mat.toon(Palette.WOOD_DARK), 0.012)
	Kit.add(root, Kit.cylinder(0.07, 0.09, 2.2, wood, 10), Vector3(0, 1.1, 0))
	Kit.add(root, Kit.box(Vector3(0.55, 0.07, 0.07), wood), Vector3(0.24, 2.12, 0))
	Kit.add(root, Kit.box(Vector3(0.22, 0.28, 0.22), Mat.glow(Palette.LANTERN_GLOW, 2.4)), Vector3(0.44, 1.88, 0))
	Kit.add(root, Kit.cone(0.2, 0.14, Mat.toon(Color("5b4a57")), 4), Vector3(0.44, 2.08, 0), Vector3(0, 45, 0))
	var l := OmniLight3D.new()
	l.light_color = Palette.LANTERN_GLOW
	l.light_energy = 1.2
	l.omni_range = 3.5
	root.add_child(l)
	l.position = Vector3(0.44, 1.7, 0.1)


func _tree(pos: Vector3, s: float, col: Color, seed_v: int) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	Kit.add(root, Kit.cylinder(0.16 * s, 0.26 * s, 2.0 * s, Mat.outlined(Mat.toon(Palette.BARK), 0.015), 10), Vector3(0, 1.0 * s, 0))
	var fm := Mat.outlined(Mat.toon(col, {"wind": 0.06, "wind_height": 2.0}), 0.02)
	Kit.add(root, Kit.blob(1.25 * s, fm, seed_v, 0.22, 0.95), Vector3(0, 2.6 * s, 0))
	Kit.add(root, Kit.blob(0.9 * s, fm, seed_v + 1, 0.22, 0.95), Vector3(0.7 * s, 2.1 * s, 0.2 * s))
	Kit.add(root, Kit.blob(0.85 * s, fm, seed_v + 2, 0.22, 0.95), Vector3(-0.6 * s, 2.25 * s, -0.2 * s))


func _trees() -> void:
	_tree(Vector3(-6.8, 0, -4.5), 1.25, Palette.FOLIAGE, 101)
	_tree(Vector3(-8.5, 0, 0.5), 1.05, Palette.FOLIAGE_DARK, 111)
	_tree(Vector3(6.6, 0, -5.8), 1.35, Palette.FOLIAGE, 121)
	_tree(Vector3(8.2, 0, -1.2), 1.1, Palette.FOLIAGE_AUTUMN, 131)
	_tree(Vector3(-1.2, 0, -8.0), 1.4, Palette.FOLIAGE_DARK, 141)
	_tree(Vector3(4.2, 0, -9.0), 1.2, Palette.FOLIAGE_LIGHT, 151)
	_tree(Vector3(-4.5, 0, -9.5), 1.15, Palette.FOLIAGE_AUTUMN, 161)
	_tree(Vector3(10.0, 0, 3.5), 1.0, Palette.FOLIAGE_DARK, 171)
	_tree(Vector3(-10.5, 0, 4.0), 1.1, Palette.FOLIAGE, 181)


func _details() -> void:
	# berry bushes
	for p in [Vector3(-5.0, 0, 1.4), Vector3(5.2, 0, 0.6), Vector3(3.6, 0, 2.8)]:
		var bush := Kit.blob(0.62, Mat.outlined(Mat.toon(Palette.FOLIAGE, {"wind": 0.04}), 0.015), int(p.x * 3.0) + 20, 0.25, 0.8)
		Kit.add(self, bush, p + Vector3(0, 0.45, 0))
		for k in 5:
			var a := float(k) * 1.3
			Kit.add(self, Kit.sphere(0.07, Mat.toon(Palette.BERRY)), p + Vector3(cos(a) * 0.5, 0.55 + float(k % 2) * 0.2, sin(a) * 0.45 + 0.1))
	# mushrooms
	for p in [Vector3(-2.2, 0, 2.6), Vector3(-2.0, 0, 2.9), Vector3(4.6, 0, -1.4), Vector3(2.0, 0, 3.4)]:
		Kit.add(self, Kit.cylinder(0.035, 0.045, 0.16, Mat.toon(Palette.FLOWER_WHITE), 8), p + Vector3(0, 0.08, 0))
		Kit.add(self, Kit.sphere(0.1, Mat.outlined(Mat.toon(Palette.FLOWER_RED), 0.01), 8, 12), p + Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1, 0.55, 1))
	# flowers & grass tufts (MultiMesh)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.08
	sm.radial_segments = 8
	sm.rings = 4
	mm.mesh = sm
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var centers: Array = []
	for i in 18:
		var cp := Vector3(rng.randf_range(-10, 10), 0.0, rng.randf_range(-6.5, 5.5))
		if cp.distance_to(Vector3(0.9, 0, 0.3)) < 2.2 or cp.distance_to(Vector3(-1.0, 0, 2.4)) < 1.8 or (cp.x < -1.0 and cp.x > -5.6 and cp.z < -0.4 and cp.z > -4.8) or cp.distance_to(Vector3(2.9, 0, -3.1)) < 1.8:
			continue
		centers.append(cp)
	var per := 9
	var count := centers.size() * per
	mm.instance_count = count
	var cols := [Palette.FLOWER_YELLOW, Palette.FLOWER_WHITE, Palette.BLOSSOM, Palette.FLOWER_BLUE, Palette.FLOWER_PURPLE, Palette.FLOWER_RED]
	var i := 0
	for cp2 in centers:
		var pc: Color = cols[rng.randi() % cols.size()]
		for k in per:
			var p := (cp2 as Vector3) + Vector3(rng.randf_range(-0.7, 0.7), 0.08, rng.randf_range(-0.6, 0.6))
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.6, 1.0)), p))
			mm.set_instance_color(i, pc if k % 3 != 0 else Palette.FLOWER_WHITE)
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var fm := Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.2})
	mmi.material_override = fm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# stems under every flower head
	var stems := MultiMesh.new()
	stems.transform_format = MultiMesh.TRANSFORM_3D
	var cm := CylinderMesh.new()
	cm.top_radius = 0.01
	cm.bottom_radius = 0.014
	cm.height = 0.18
	cm.radial_segments = 5
	cm.rings = 1
	stems.mesh = cm
	stems.instance_count = count
	for j in count:
		var t := mm.get_instance_transform(j)
		stems.set_instance_transform(j, Transform3D(Basis.IDENTITY, t.origin - Vector3(0, 0.06, 0)))
		t.origin.y += 0.09
		mm.set_instance_transform(j, t)
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = stems
	smi.material_override = Mat.toon(Palette.FOLIAGE_DARK)
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	# grass tufts
	var tufts := MultiMesh.new()
	tufts.transform_format = MultiMesh.TRANSFORM_3D
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.06
	tm.height = 0.3
	tm.radial_segments = 4
	tm.rings = 1
	tufts.mesh = tm
	var clumps := 150
	var tuft_n := clumps * 3
	tufts.instance_count = tuft_n
	var j := 0
	for c in clumps:
		var p := Vector3(rng.randf_range(-12, 12), 0.1, rng.randf_range(-8, 6.5))
		var hide := p.distance_to(Vector3(0.9, 0.1, 0.3)) < 1.2 or (p.x < -0.6 and p.x > -4.0 and p.z > -1.0 and p.z < 5.0 and absf(p.x + 1.2 - p.z * -0.35) < 1.2)
		var sc := rng.randf_range(0.55, 1.0)
		for k in 3:
			var q := p + Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05))
			if hide:
				q.y = -1.0
			var b := Basis(Vector3.UP, rng.randf_range(0, TAU)).rotated(Vector3(1, 0, 0), rng.randf_range(-0.35, 0.35)).rotated(Vector3(0, 0, 1), rng.randf_range(-0.35, 0.35))
			tufts.set_instance_transform(j, Transform3D(b.scaled(Vector3(0.6, 1.0, 0.6) * sc), q))
			j += 1
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tufts
	tmi.material_override = Mat.toon(Palette.GRASS_DARK, {"wind": 0.05, "wind_height": 0.3})
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tmi)


func _fireflies() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = FIREFLIES
	fireflies = MultiMeshInstance3D.new()
	fireflies.multimesh = mm
	fireflies.material_override = Mat.glow(Color("fff1a0"), 5.0)
	fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fireflies)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in FIREFLIES:
		_ff_data.append([Vector3(rng.randf_range(-7, 7), rng.randf_range(0.4, 2.8), rng.randf_range(-6, 4)), rng.randf_range(0, TAU), rng.randf_range(0.4, 1.0)])


func _aim() -> void:
	var dir := _look - cam.global_position
	if dir.length() > 0.001 and absf(dir.normalized().dot(Vector3.UP)) < 0.99:
		cam.look_at(_look, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	# camera drift
	var sway := sin(_t * 0.07) * 0.9
	cam.position = _cam_base + Vector3(sway, sin(_t * 0.11) * 0.12, cos(_t * 0.05) * 0.35)
	_aim()
	# fire flicker
	if fire_light != null:
		fire_light.light_energy = 1.8 + sin(_t * 9.0) * 0.18 + sin(_t * 23.0) * 0.1
		for i in flames.size():
			var f: Node3D = flames[i]
			var k := 1.0 + sin(_t * (11.0 + float(i) * 4.0)) * 0.07
			f.scale = Vector3(k, 1.0 + sin(_t * (7.0 + float(i) * 3.0)) * 0.12, k)
		for j in embers.size():
			var em: Node3D = embers[j]
			var ph := fmod(_t * 0.45 + float(j) * 0.21, 1.0)
			em.position = Vector3(sin(float(j) * 2.1 + _t) * 0.2 * ph, 0.45 + ph * 1.4, cos(float(j) * 1.7 + _t * 0.8) * 0.15 * ph)
			em.scale = Vector3.ONE * (1.0 - ph)
	if ward_light != null:
		ward_light.light_energy = 0.9 + sin(_t * 1.3) * 0.25
	# fireflies
	var mm := fireflies.multimesh
	for i in FIREFLIES:
		var d: Array = _ff_data[i]
		var base: Vector3 = d[0]
		var ph: float = d[1]
		var sp: float = d[2]
		var p := base + Vector3(sin(_t * 0.3 * sp + ph) * 0.8, sin(_t * 0.5 * sp + ph * 2.0) * 0.35, cos(_t * 0.25 * sp + ph) * 0.8)
		var tw := clampf(sin(_t * 1.6 * sp + ph * 3.0) * 0.7 + 0.5, 0.0, 1.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(tw, 0.01)), p))
