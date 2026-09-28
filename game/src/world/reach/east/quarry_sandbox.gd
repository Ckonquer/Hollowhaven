extends "res://src/world/area_base.gd"
## Stand-alone host for Ashbell Quarry (tests, previews): a small Reach-like heightfield around hr_quarry with
## the same district calls the real Reach makes (reach_districts.gd: shape_terrain inside the landmark circle,
## then build(area)), so the quarry can be checked before / independently of the full region.
##   var s = load("res://src/world/reach/east/quarry_sandbox.gd").new()
##   s.setup({"base": "flat" | "slope" | "bumpy", "mesh": false})   # before add_child
##   add_child(s)   -> s.terrain, s.quarry (district root), s.shape_ms, s.build_ms
## Preview (debug builds): tools/godot.sh --path game --windowed --resolution 1600x900 -- \
##   --preview=res://src/world/reach/east/quarry_sandbox.gd --preview-args='{"mesh": true, "center": true}' \
##   --preview-dist=58 --preview-height=30 --shot-dir=<abs dir>

const Q := preload("res://data/reach_east.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const District := preload("res://src/world/reach/districts/quarry.gd")
const Mat := preload("res://src/art/mat.gd")


## A small heightfield with the Reach terrain's shaping API (h / NX / NZ / ORIGIN / limit, tint_disc,
## add_stone_disc, mark_path, height_at with the same cell diagonal as the Jolt collider, like reach_terrain.gd).
class SandboxTerrain extends RefCounted:
	const NX := 101
	const NZ := 101
	const ORIGIN := Vector2(36.0, -32.0)
	var h := PackedFloat32Array()
	var limit := Vector3(0.0, 0.0, -1.0)
	var tints: Array = []
	var stone_discs: Array = []
	var roads: Array = []

	func _init(base: String = "flat") -> void:
		h.resize(NX * NZ)
		for j in NZ:
			for i in NX:
				var x := ORIGIN.x + float(i)
				var z := ORIGIN.y + float(j)
				var v := 0.0
				match base:
					"slope":
						v = 0.045 * (x - 86.0) - 0.03 * (z - 18.0)
					"bumpy":
						v = 0.8 * sin(x * 0.21) * cos(z * 0.17) + 0.02 * (x - 86.0)
				h[j * NX + i] = v

	func height_at(x: float, z: float) -> float:
		var fx := clampf(x - ORIGIN.x, 0.0, float(NX - 1) - 0.0001)
		var fz := clampf(z - ORIGIN.y, 0.0, float(NZ - 1) - 0.0001)
		var i := int(fx)
		var j := int(fz)
		var tx := fx - float(i)
		var tz := fz - float(j)
		var k := j * NX + i
		var h00 := h[k]
		var h10 := h[k + 1]
		var h01 := h[k + NX]
		var h11 := h[k + NX + 1]
		# the (i+1, j)-(i, j+1) diagonal: how the Jolt height field splits its cells (same as reach_terrain.gd)
		if tx + tz <= 1.0:
			return h00 + (h10 - h00) * tx + (h01 - h00) * tz
		return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

	func tint_disc(center: Vector2, r0: float, r1: float, color: Color, amount: float) -> void:
		tints.append([center, r0, r1, color, amount])

	func add_stone_disc(center: Vector2, radius: float) -> void:
		stone_discs.append([center, radius])

	func mark_path(points: Array, half_width: float, strength: float = 1.0) -> void:
		roads.append([points, half_width, strength])

	func build_collision(parent: Node3D) -> StaticBody3D:
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", "grass")
		var cs := CollisionShape3D.new()
		var shape := HeightMapShape3D.new()
		shape.map_width = NX
		shape.map_depth = NZ
		shape.map_data = h
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		body.position = Vector3(ORIGIN.x + float(NX - 1) * 0.5, 0.0, ORIGIN.y + float(NZ - 1) * 0.5)
		return body

	func color_at(x: float, z: float) -> Color:
		var c := Color("a39c50")
		for t in tints:
			var d := Vector2(x, z).distance_to(t[0])
			var w := 1.0 - smoothstep(float(t[1]), float(t[2]), d)
			c = c.lerp(t[3], w * float(t[4]))
		return c

	func build_mesh(parent: Node3D) -> MeshInstance3D:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in NZ - 1:
			for i in NX - 1:
				var p00 := Vector3(ORIGIN.x + i, h[j * NX + i], ORIGIN.y + j)
				var p10 := Vector3(ORIGIN.x + i + 1, h[j * NX + i + 1], ORIGIN.y + j)
				var p01 := Vector3(ORIGIN.x + i, h[(j + 1) * NX + i], ORIGIN.y + j + 1)
				var p11 := Vector3(ORIGIN.x + i + 1, h[(j + 1) * NX + i + 1], ORIGIN.y + j + 1)
				for tri in [[p00, p10, p01], [p10, p11, p01]]:
					for v in tri:
						st.set_color(color_at(v.x, v.z).srgb_to_linear())
						st.add_vertex(v)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "TerrainMesh"
		mi.mesh = st.commit()
		mi.material_override = Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.08})
		parent.add_child(mi)
		return mi


var base := "flat"
var with_mesh := false
var center_origin := false
var terrain: SandboxTerrain = null
var quarry: Node3D = null
var shape_ms := 0.0
var build_ms := 0.0


func setup(p: Dictionary) -> void:
	base = String(p.get("base", base))
	with_mesh = bool(p.get("mesh", with_mesh))
	center_origin = bool(p.get("center", center_origin))


func _ready() -> void:
	area_id = Reach.AREA_ID
	name = "QuarrySandbox"
	if center_origin:
		position = Vector3(-Q.CENTER.x, 0.0, -Q.CENTER.y)
	terrain = SandboxTerrain.new(base)
	var t0 := Time.get_ticks_usec()
	var lm: Dictionary = Reach.LANDMARKS[Q.LANDMARK]
	var c: Vector2 = lm["pos"]
	terrain.limit = Vector3(c.x, c.y, float(lm["radius"]))
	District.shape_terrain(terrain)
	terrain.limit = Vector3(0.0, 0.0, -1.0)
	shape_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	terrain.build_collision(self)
	if with_mesh:
		terrain.build_mesh(self)
		_environment()
	add_zone(Q.LANDMARK, Vector3(c.x, height_at(c.x, c.y), c.y), float(lm["radius"]), false)
	var sp: Dictionary = Reach.SPAWNS["quarry_arch"]
	var spos: Vector2 = sp["pos"]
	register_spawn("quarry_arch", Transform3D(Basis(Vector3.UP, Reach.yaw_towards(spos, sp["look"])), Vector3(spos.x, height_at(spos.x, spos.y) + 0.08, spos.y)))
	var t1 := Time.get_ticks_usec()
	District.build(self)
	build_ms = float(Time.get_ticks_usec() - t1) / 1000.0
	quarry = District.district_root(self)


func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


func surface_at(pos: Vector3) -> String:
	return "stone" if Vector2(pos.x, pos.z).distance_to(Q.CENTER) < 28.0 else "grass"


func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("7a5a6e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9a38a")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffc98a")
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-40.0, 140.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
