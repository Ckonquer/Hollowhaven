extends Node3D
## Water of Hallowmere Reach: the Thimblebrook ribbon (flowing, surface_water.gdshader), the Sunken
## Bellhouse's still pond, the dry crossings of Reach.BROOK_CROSSINGS (a festival footbridge and stepping
## stones: walkable ramp-like collision, meta surface "wood" / "stone") and one positional brook sound that
## follows the nearest point of the brook. The brook is shallow (a wade), so it never blocks progress.
##   var w = ReachWater.new(); w.terrain = terrain; parent.add_child(w)

const Reach := preload("res://data/hallowmere_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const AudioUtil := preload("res://src/world/surface/audio_util.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const WATER_SHADER := preload("res://shaders/surface_water.gdshader")

var terrain: RefCounted
var brook_material: ShaderMaterial
var pond_material: ShaderMaterial
var crossings: Array = []          # [{id, pos: Vector3, style, axis: Vector3}]
var build_times: Dictionary = {}
var _audio: AudioStreamPlayer3D
var _audio_t := 0.0


func _ready() -> void:
	name = "Water"
	brook_material = _water_material(true, Color("74b3b0"), Color("3f7a86"))
	pond_material = _water_material(false, Color("5d8487"), Color("2c4a5c"))
	var steps := [_build_brook, _build_ponds, _build_reeds, _build_crossings, _setup_audio]
	var names := ["brook", "ponds", "reeds", "crossings", "audio"]
	for i in steps.size():
		var t0 := Time.get_ticks_usec()
		(steps[i] as Callable).call()
		build_times[names[i]] = float(Time.get_ticks_usec() - t0) / 1000.0


func _water_material(stream: bool, shallow: Color, deep: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("shallow_color", shallow)
	m.set_shader_parameter("deep_color", deep)
	m.set_shader_parameter("is_stream", 1.0 if stream else 0.0)
	m.set_shader_parameter("depth_scale", 0.55 if stream else 0.8)
	m.set_shader_parameter("flow_speed", 0.45 if stream else 0.0)
	m.render_priority = 1 if stream else 0
	return m


func _build_brook() -> void:
	var pts: PackedVector3Array = terrain.stream_pts
	var halves: PackedFloat32Array = terrain.stream_half
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var along := 0.0
	var rows := 0
	var last := Vector3.ZERO
	for k in range(0, pts.size(), 2):
		var c := pts[k]
		var a := pts[maxi(k - 2, 0)]
		var b := pts[mini(k + 2, pts.size() - 1)]
		var tng := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var perp := Vector3(-tng.z, 0.0, tng.x)
		var w := halves[k] + 1.6
		if rows > 0:
			along += Vector2(c.x - last.x, c.z - last.z).length()
		last = c
		# fade in where the brook leaves the pools' reeds
		var fade := clampf(along / 3.0, 0.0, 1.0)
		verts.append(c - perp * w)
		verts.append(c + perp * w)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(0.0, along / 3.4))
		uvs.append(Vector2(1.0, along / 3.4))
		cols.append(Color(1, 1, 1, fade))
		cols.append(Color(1, 1, 1, fade))
		if rows > 0:
			var r0 := (rows - 1) * 2
			var r1 := rows * 2
			var p0 := verts[r0]
			var p1 := verts[r0 + 1]
			var cross_y := (p1 - p0).cross(verts[r1] - p0).y
			if cross_y < 0.0:
				idx.append_array(PackedInt32Array([r0, r0 + 1, r1, r0 + 1, r1 + 1, r1]))
			else:
				idx.append_array(PackedInt32Array([r0, r1, r0 + 1, r0 + 1, r1, r1 + 1]))
		rows += 1
	if rows < 2:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Thimblebrook"
	mi.mesh = mesh
	mi.material_override = brook_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Still water: one disc per pond (a single indexed mesh, every vertex shared, so nothing is blended twice)
## reaching a little under the banks, where the rising terrain hides its edge and the water shader draws the
## depth-faded shoreline. Triangles over dry cut-outs (the Bellhouse tower base and the stairwell under it) are
## left out; their jagged edge stays inside the tower / stair walls.
const POND_OVERHANG := 0.6
const POND_RING_STEP := 0.5
const POND_SEGMENTS := 128


func _build_ponds() -> void:
	for p in terrain.ponds:
		var mesh := pond_mesh(p[0], float(p[1]), float(p[2]), pond_cutouts(p[0]))
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "StillWater"
		mi.mesh = mesh
		mi.material_override = pond_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Dry rectangles inside a pond (world XZ): the Bellhouse tower base and its stairwell, shrunk by 0.3 m so the
## water still runs under the walls' inner faces (the walls hide the cut).
static func pond_cutouts(center: Vector2) -> Array:
	var B: Dictionary = Reach.BELLHOUSE
	if center.distance_to(B["pond"]) > 0.5:
		return []
	var tower: Rect2 = B["tower"]
	var sx: float = B["stair_x"]
	var wo: float = float(B["wall_outer"]) - 0.3
	var top_z: float = B["ramp_top_z"]
	var end_z: float = B["bottom_end_z"]
	return [tower.grow(-0.3), Rect2(sx - wo, end_z - 0.5, wo * 2.0, top_z + 0.5 - (end_z - 0.5))]


## A flat polar disc at `level` (centre at the disc's centre, local), radius + POND_OVERHANG; triangles whose
## centroid falls in a cut-out rectangle (world XZ) are dropped. UV = world XZ / (2 r) + 0.5 (as before).
static func pond_mesh(center: Vector2, radius: float, level: float, cutouts: Array) -> ArrayMesh:
	var r := radius + POND_OVERHANG
	var rings := int(ceil(r / POND_RING_STEP))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.append(Vector3(center.x, level, center.y))
	uvs.append(Vector2(0.5, 0.5))
	for k in range(1, rings + 1):
		var rr := r * float(k) / float(rings)
		for s in POND_SEGMENTS:
			var a := TAU * float(s) / float(POND_SEGMENTS)
			var q := center + Vector2(cos(a), sin(a)) * rr
			verts.append(Vector3(q.x, level, q.y))
			uvs.append(Vector2((q.x - center.x) / (2.0 * r) + 0.5, (q.y - center.y) / (2.0 * r) + 0.5))
	var idx := PackedInt32Array()
	var add_tri := func(a: int, b: int, c: int) -> void:
		var ctr := (verts[a] + verts[b] + verts[c]) / 3.0
		for rc in cutouts:
			if (rc as Rect2).has_point(Vector2(ctr.x, ctr.z)):
				return
		idx.append_array(PackedInt32Array([a, b, c]))
	for s in POND_SEGMENTS:
		add_tri.call(0, 1 + (s + 1) % POND_SEGMENTS, 1 + s)
	for k in range(1, rings):
		var b0 := 1 + (k - 1) * POND_SEGMENTS
		var b1 := 1 + k * POND_SEGMENTS
		for s in POND_SEGMENTS:
			var s1 := (s + 1) % POND_SEGMENTS
			add_tri.call(b0 + s, b0 + s1, b1 + s)
			add_tri.call(b0 + s1, b1 + s1, b1 + s)
	if idx.is_empty():
		return null
	# clockwise seen from above = front face up (Godot): flip if the winding came out the other way
	var n0 := (verts[idx[1]] - verts[idx[0]]).cross(verts[idx[2]] - verts[idx[0]])
	if n0.y > 0.0:
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _reed_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6300 + variant
	var m := NodeVisuals.Merger.new()
	var base_c := Color("7a7a3e")
	var tip_c := Color("d9b865")
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.22)
		var root := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var hgt := rng.randf_range(0.9, 1.5)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.2)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		var tip := root + lean + Vector3(0, hgt, 0)
		var n := (Vector3.UP + Vector3(cos(a), 0, sin(a))).normalized()
		m.tri(root - side, tip, root + side, n, base_c, tip_c, base_c, true)
	for i in 3:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.12, rng.randf_range(1.05, 1.4), sin(a) * 0.12)
		m.add(NodeVisuals._cyl(0.012, 0.012, 1.3, 4), Transform3D(Basis(), Vector3(p.x, p.y * 0.5, p.z)), Color("7a7a42"))
		m.add(NodeVisuals._cyl(0.045, 0.045, 0.2, 6), Transform3D(Basis(), p), Color("6e4a30"))
	return m.commit()


func _build_reeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6400
	var spots: Array = []
	var pts: PackedVector3Array = terrain.stream_pts
	var halves: PackedFloat32Array = terrain.stream_half
	for k in range(0, pts.size(), 4):
		if rng.randf() > 0.6:
			continue
		var a := pts[maxi(k - 2, 0)]
		var b := pts[mini(k + 2, pts.size() - 1)]
		var tng := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var off := halves[k] + rng.randf_range(0.1, 0.9)
		spots.append(Vector2(pts[k].x - tng.z * off * side, pts[k].z + tng.x * off * side))
	for p in terrain.ponds:
		var c: Vector2 = p[0]
		var pr: float = p[1]
		for i in 46:
			var a := rng.randf() * TAU
			var q := c + Vector2(cos(a), sin(a)) * (pr + rng.randf_range(-1.2, 0.4))
			spots.append(q)
	var lists: Array = [[], [], []]
	var sx: float = Reach.BELLHOUSE["stair_x"]
	for p in spots:
		var pp: Vector2 = p
		if terrain.path_at(pp.x, pp.y) > 0.2 or not Reach.is_inside(pp, 2.0):
			continue
		if absf(pp.x - sx) < 4.0 and pp.y > -93.0 and pp.y < -76.0:
			continue
		var near_crossing := false
		for cr in Reach.BROOK_CROSSINGS:
			if (cr["pos"] as Vector2).distance_to(pp) < 4.5:
				near_crossing = true
		if near_crossing:
			continue
		var s := rng.randf_range(0.8, 1.2)
		lists[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(pp.x, terrain.height_at(pp.x, pp.y), pp.y)))
	var mat := NodeVisuals.foliage_material(0.06, 1.5, 0.0, 0.35)
	for v in 3:
		var arr: Array = lists[v]
		if arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _reed_mesh(v)
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Reeds%d" % v
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.visibility_range_end = 110.0
		add_child(inst)


# --- Crossings -------------------------------------------------------------------------------------

func _build_crossings() -> void:
	for i in Reach.BROOK_CROSSINGS.size():
		var cdef: Dictionary = Reach.BROOK_CROSSINGS[i]
		var cp: Vector2 = cdef["pos"]
		var info: Dictionary = terrain.nearest_stream_point(cp.x, cp.y)
		if info.is_empty():
			continue
		var style := String(cdef.get("style", "bridge"))
		var center: Vector3 = info["pos"]
		var tng: Vector3 = info["tangent"]
		var axis := Vector3(-tng.z, 0.0, tng.x).normalized()   # across the brook
		var half: float = info["half"]
		crossings.append({"id": String(cdef.get("id", "crossing_%d" % i)), "pos": center, "style": style, "axis": axis})
		if style == "stones":
			_build_stepping_stones(center, axis, half, i)
		else:
			_build_bridge(center, axis, half, i)


func _build_stepping_stones(center: Vector3, axis: Vector3, half: float, index: int) -> void:
	var root := Node3D.new()
	root.name = "SteppingStones%d" % index
	add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	root.add_child(body)
	var span := half + 1.2
	var count := 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 6600 + index
	var mat := NodeVisuals.rock_material()
	var profile: Array = []
	var ua := -span - 1.0
	var pa := center + axis * ua
	profile.append([ua, terrain.height_at(pa.x, pa.z) - 0.04])
	for s in count:
		var u := lerpf(-span, span, float(s) / float(count - 1))
		var jitter := Vector3(-axis.z, 0, axis.x) * rng.randf_range(-0.2, 0.2)
		var p := center + axis * u + jitter
		var ground: float = terrain.height_at(p.x, p.z)
		var top := maxf(center.y + 0.2, ground + 0.12)
		profile.append([u, top])
		var mesh := NodeVisuals.boulder_mesh(s % 3, Color("c2b6a6"), 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		root.add_child(mi)
		var sc := rng.randf_range(0.5, 0.62)
		var hgt := top - (ground - 0.4)
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, maxf(hgt / 1.2, 0.4), sc)), Vector3(p.x, ground - 0.4, p.z))
	var ub := span + 1.0
	var pb := center + axis * ub
	profile.append([ub, terrain.height_at(pb.x, pb.z) - 0.04])
	var yaw := atan2(axis.x, axis.z)
	var flat_c := Vector3(center.x, 0.0, center.z)
	for k in profile.size() - 1:
		var p0: Vector3 = flat_c + axis * float(profile[k][0]) + Vector3(0, float(profile[k][1]), 0)
		var p1: Vector3 = flat_c + axis * float(profile[k + 1][0]) + Vector3(0, float(profile[k + 1][1]), 0)
		var dir := p1 - p0
		var bb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(dir.y, Vector2(dir.x, dir.z).length()))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 0.3, dir.length() + 0.08)
		cs.shape = box
		cs.transform = Transform3D(bb, (p0 + p1) * 0.5 - bb.y * 0.15)
		body.add_child(cs)


## A little festival footbridge: arched plank deck, rails wrapped in ribbon, two lantern posts.
func _build_bridge(center: Vector3, axis: Vector3, half: float, index: int) -> void:
	var root := Node3D.new()
	root.name = "Bridge%d" % index
	add_child(root)
	var span := half + 2.6
	var a_end := center - axis * span
	var b_end := center + axis * span
	var ya: float = terrain.height_at(a_end.x, a_end.z)
	var yb: float = terrain.height_at(b_end.x, b_end.z)
	var base_y := maxf(ya, yb) + 0.02
	var arch := 0.45
	var width := 2.2
	var side := Vector3(-axis.z, 0.0, axis.x)
	var yaw := atan2(axis.x, axis.z)
	center.y = 0.0
	var m := NodeVisuals.Merger.new()
	var planks := int(ceil(span * 2.0 / 0.36))
	var deck_y := func(u: float) -> float:
		var t := (u + span) / (2.0 * span)
		return base_y + arch * sin(PI * t)
	for p in planks:
		var u := lerpf(-span, span, (float(p) + 0.5) / float(planks))
		var y: float = deck_y.call(u)
		var slope: float = (float(deck_y.call(u + 0.1)) - float(deck_y.call(u - 0.1))) / 0.2
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan(slope))
		var pos := center + axis * u
		var shade := Palette.WOOD if p % 3 != 0 else Palette.WOOD_LIGHT
		m.add(NodeVisuals._box(Vector3(width, 0.1, 0.32)), Transform3D(b, Vector3(pos.x, y - 0.05, pos.z)), shade)
	var ribbon := [Props.CLOTH["pumpkin"], Props.CLOTH["plum"], Props.CLOTH["cream"]]
	for sgn in [-1.0, 1.0]:
		var sdir: Vector3 = side * float(sgn) * (width * 0.5 - 0.1)
		for p in 7:
			var u := lerpf(-span + 0.2, span - 0.2, float(p) / 6.0)
			var y: float = deck_y.call(u)
			var pos: Vector3 = center + axis * u + sdir
			m.add(NodeVisuals._cyl(0.06, 0.07, 1.0, 7), Transform3D(Basis(), Vector3(pos.x, y + 0.45, pos.z)), Palette.WOOD_DARK)
			m.add(Kit.blob_mesh(0.09, 6700 + p, 0.1, 0.9, 1), Transform3D(Basis(), Vector3(pos.x, y + 0.97, pos.z)), ribbon[p % 3])
		for p in 6:
			var u0 := lerpf(-span + 0.2, span - 0.2, float(p) / 6.0)
			var u1 := lerpf(-span + 0.2, span - 0.2, float(p + 1) / 6.0)
			var p0: Vector3 = center + axis * u0 + sdir + Vector3(0, float(deck_y.call(u0)) + 0.9, 0)
			var p1: Vector3 = center + axis * u1 + sdir + Vector3(0, float(deck_y.call(u1)) + 0.9, 0)
			Props.wire(m, PackedVector3Array([p0, p1]), 0.045, Palette.WOOD_LIGHT)
		for p in 4:
			var u0 := lerpf(-span, span, float(p) / 4.0)
			var u1 := lerpf(-span, span, float(p + 1) / 4.0)
			var p0: Vector3 = center + axis * u0 + sdir + Vector3(0, float(deck_y.call(u0)) - 0.16, 0)
			var p1: Vector3 = center + axis * u1 + sdir + Vector3(0, float(deck_y.call(u1)) - 0.16, 0)
			var dir := p1 - p0
			var bb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(dir.y, Vector2(dir.x, dir.z).length()))
			m.add(NodeVisuals._box(Vector3(0.14, 0.18, dir.length() + 0.05)), Transform3D(bb, (p0 + p1) * 0.5), Palette.WOOD_DARK)
	var mi := MeshInstance3D.new()
	mi.name = "BridgeMesh"
	mi.mesh = m.commit()
	mi.material_override = Props.wood_mat()
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "BridgeBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	root.add_child(body)
	var segs := 8
	for sgi in segs:
		var u0 := lerpf(-span - 0.6, span + 0.6, float(sgi) / float(segs))
		var u1 := lerpf(-span - 0.6, span + 0.6, float(sgi + 1) / float(segs))
		var y0: float = deck_y.call(clampf(u0, -span, span))
		var y1: float = deck_y.call(clampf(u1, -span, span))
		if sgi == 0:
			y0 = ya - 0.05
		if sgi == segs - 1:
			y1 = yb - 0.05
		var p0: Vector3 = center + axis * u0 + Vector3(0, y0, 0)
		var p1: Vector3 = center + axis * u1 + Vector3(0, y1, 0)
		var dir := p1 - p0
		var bb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(dir.y, Vector2(dir.x, dir.z).length()))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.3, dir.length() + 0.08)
		cs.shape = box
		cs.transform = Transform3D(bb, (p0 + p1) * 0.5 - bb.y * 0.15)
		body.add_child(cs)
	for sgn in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.2, 1.4, span * 2.0 - 0.6)
		cs.shape = box
		var rp: Vector3 = center + side * float(sgn) * (width * 0.5 - 0.05)
		rp.y = base_y + arch * 0.6 + 0.55
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), rp)
		body.add_child(cs)


# --- Audio -------------------------------------------------------------------------------------------

func _setup_audio() -> void:
	_audio = AudioUtil.make_loop("amb_stream", "Ambience", -6.0, 26.0)
	if _audio == null:
		return
	_audio.name = "BrookSound"
	_audio.unit_size = 5.0
	add_child(_audio)


func _process(delta: float) -> void:
	if _audio == null:
		set_process(false)
		return
	_audio_t += delta
	if _audio_t < 0.3:
		return
	_audio_t = 0.0
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var p := cam.global_position
	var best := Vector3.ZERO
	var bd := 1e9
	var pts: PackedVector3Array = terrain.stream_pts
	for k in range(0, pts.size(), 3):
		var d := Vector2(pts[k].x - p.x, pts[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = pts[k]
	_audio.global_position = best + Vector3(0, 0.3, 0)
