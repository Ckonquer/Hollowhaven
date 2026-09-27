extends "res://src/world/area_base.gd"
## Debug-only test arena (--area=arena). Stable geometry for testing movement, camera, combat and
## companions while the real areas are under construction: flat ground, slopes, stairs (with ramp
## collision), a doorway, a wall corner, a ledge and a pit. Spawns: haven_start, arena_center, and the
## companion ids so companion/enemy modules can be tested here.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")


func _ready() -> void:
	area_id = "arena"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Palette.SKY_TOP
	sm.sky_horizon_color = Palette.SKY_HORIZON
	sm.ground_horizon_color = Palette.SKY_HORIZON
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Palette.AMBIENT_DAY
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Palette.SUN_DAY
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	_block(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Palette.GRASS)
	# Slope ramp (20 deg) and steep slope (50 deg)
	_ramp(Vector3(10, 0, -10), 8.0, 20.0, Palette.DIRT)
	_ramp(Vector3(18, 0, -10), 6.0, 50.0, Palette.STONE)
	# Stairs: visual steps + ramp collision
	for i in 8:
		var step := Kit.box(Vector3(2, 0.25, 0.4), Palette.WOOD)
		add_child(step)
		step.position = Vector3(-10, 0.125 + i * 0.25, -8 - i * 0.4)
	_ramp_collider(Vector3(-10, 0, -8.2), Vector3(2, 0.1, 3.4), atan2(2.0, 3.2))
	_block(Vector3(-10, 1.0, -12.2), Vector3(3, 2, 2), Palette.WOOD_DARK)
	# Wall with doorway and a corner
	_block(Vector3(0, 1.5, -18), Vector3(4, 3, 0.4), Palette.STONE)
	_block(Vector3(5, 1.5, -18), Vector3(4, 3, 0.4), Palette.STONE)
	_block(Vector3(2.5, 2.7, -18), Vector3(1.2, 0.6, 0.4), Palette.STONE)
	_block(Vector3(7, 1.5, -15), Vector3(0.4, 3, 6), Palette.STONE)
	# Ledge and a pit (fall recovery)
	_block(Vector3(-18, 1.5, 6), Vector3(6, 3, 6), Palette.STONE_DARK)
	var marker := Kit.box(Vector3(1, 0.1, 1), Palette.FLOWER_RED)
	add_child(marker)
	marker.position = Vector3(20, 0.05, 20)
	register_spawn("haven_start", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 6)))
	register_spawn("haven_respawn", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 6)))
	register_spawn("arena_center", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	for id in ["mochi", "pebble", "lumi"]:
		register_spawn("companion_wild_" + id, Transform3D(Basis.IDENTITY, Vector3(-4 + ["mochi", "pebble", "lumi"].find(id) * 4, 0.1, -4)))
		register_spawn("companion_home_" + id, Transform3D(Basis.IDENTITY, Vector3(-4 + ["mochi", "pebble", "lumi"].find(id) * 4, 0.1, 12)))
	register_spawn("mine_threshold", Transform3D(Basis.IDENTITY, Vector3(12, 0.1, 12)))
	add_zone("haven", Vector3(0, 0, 8), 6.0, true)
	add_zone("arena", Vector3.ZERO, 60.0, false)


func height_at(_x: float, _z: float) -> float:
	return 0.0


func _block(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := Kit.box(size, color)
	add_child(mi)
	mi.position = pos
	var sh := BoxShape3D.new()
	sh.size = size
	Kit.static_collider(self, sh, pos, 1)


func _ramp(pos: Vector3, length: float, angle_deg: float, color: Color) -> void:
	var h := tan(deg_to_rad(angle_deg)) * length
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = pos
	pivot.rotation.x = deg_to_rad(angle_deg)
	var mi := Kit.box(Vector3(3, 0.2, length / cos(deg_to_rad(angle_deg))), color)
	pivot.add_child(mi)
	mi.position = Vector3(0, 0, -length / cos(deg_to_rad(angle_deg)) * 0.5)
	var sh := BoxShape3D.new()
	sh.size = Vector3(3, 0.2, length / cos(deg_to_rad(angle_deg)))
	var body := Kit.static_collider(pivot, sh, mi.position, 1)
	body.name = "Ramp%d" % int(angle_deg)
	var _unused := h


func _ramp_collider(pos: Vector3, size: Vector3, angle: float) -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = pos
	pivot.rotation.x = angle
	var sh := BoxShape3D.new()
	sh.size = size
	Kit.static_collider(pivot, sh, Vector3(0, 0, -size.z * 0.5), 1)
