extends Node3D
## Stream + Mirror Pond: water surfaces (surface_water.gdshader), lily pads, reeds, bridges and
## stepping stones at Layout.STREAM_CROSSINGS (walkable, ramp-like collision, meta surface = "wood" /
## "stone"), and one positional stream sound that follows the nearest point of the stream.
##   var w = Water.new(); w.terrain = terrain; parent.add_child(w)     (builds in _ready)

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const WATER_SHADER := preload("res://shaders/surface_water.gdshader")

var terrain: RefCounted
var stream_material: ShaderMaterial
var pond_material: ShaderMaterial
var crossings: Array = []          # [{pos: Vector3, style, axis: Vector3}]
var _stream_audio: AudioStreamPlayer3D
var build_times: Dictionary = {}
var _audio_t := 0.0


func _ready() -> void:
	name = "Water"
	stream_material = _water_material(true)
	pond_material = _water_material(false)
	var steps := [_build_stream, _build_pond, _build_lily_pads, _build_reeds, _build_crossings, _setup_audio]
	var names := ["stream", "pond", "lily", "reeds", "crossings", "audio"]
	for i in steps.size():
		var t0 := Time.get_ticks_usec()
		(steps[i] as Callable).call()
		build_times[names[i]] = float(Time.get_ticks_usec() - t0) / 1000.0


func _water_material(stream: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("shallow_color", Palette.WATER)
	m.set_shader_parameter("deep_color", Palette.WATER_DEEP)
	m.set_shader_parameter("is_stream", 1.0 if stream else 0.0)
	m.set_shader_parameter("depth_scale", 0.55 if stream else 1.0)
	m.set_shader_parameter("flow_speed", 0.5)
	m.render_priority = 1 if stream else 0
	return m


func _build_stream() -> void:
	var pts: PackedVector3Array = terrain.stream_pts
	var halves: PackedFloat32Array = terrain.stream_half
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	var rows := 0
	var last := Vector3.ZERO
	var cols := PackedColorArray()
	for k in range(0, pts.size(), 2):
		var c := pts[k]
		var pdist: float = terrain.pond_distance(c.x, c.z)
		if pdist < -3.5:
			break
		var fade := clampf((pdist + 3.5) / 4.5, 0.0, 1.0)
		c.y = lerpf(terrain.pond_level, c.y, clampf(pdist / 3.0, 0.0, 1.0)) if pdist < 3.0 else c.y
		var a := pts[maxi(k - 2, 0)]
		var b := pts[mini(k + 2, pts.size() - 1)]
		var tng := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var perp := Vector3(-tng.z, 0.0, tng.x)
		var w := halves[k] + 1.9
		if rows > 0:
			along += Vector2(c.x - last.x, c.z - last.z).length()
		last = c
		var vl := along / 4.0
		verts.append(c - perp * w)
		verts.append(c + perp * w)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(0.0, vl))
		uvs.append(Vector2(1.0, vl))
		cols.append(Color(1, 1, 1, fade))
		cols.append(Color(1, 1, 1, fade))
		if rows > 0:
			var r0 := (rows - 1) * 2
			var r1 := rows * 2
			# clockwise (seen from above) for both triangles
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
	mi.name = "Stream"
	mi.mesh = mesh
	mi.material_override = stream_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_pond() -> void:
	var c: Vector2 = terrain.pond_center
	var level: float = terrain.pond_level
	var seg := 72
	var verts := PackedVector3Array([Vector3(c.x, level, c.y)])
	var norms := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var idx := PackedInt32Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var r: float = terrain.pond_edge(a) + 2.6
		verts.append(Vector3(c.x + cos(a) * r, level, c.y + sin(a) * r))
		norms.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	for i in seg:
		var i1 := 1 + i
		var i2 := 1 + (i + 1) % seg
		# angle grows from +x toward +z, which is clockwise seen from above -> (centre, i1, i2) faces up
		idx.append_array(PackedInt32Array([0, i1, i2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Pond"
	mi.mesh = mesh
	mi.material_override = pond_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _pad_mesh() -> ArrayMesh:
	var m := NodeVisuals.Merger.new()
	var seg := 14
	var r := 0.55
	var notch := 0.45
	var center := Vector3(0, 0.02, 0)
	for i in seg:
		var a0 := notch + (TAU - notch * 2.0) * float(i) / float(seg)
		var a1 := notch + (TAU - notch * 2.0) * float(i + 1) / float(seg)
		var p0 := Vector3(cos(a0) * r, 0.02, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.02, sin(a1) * r)
		m.tri(center, p0, p1, Vector3.UP, Palette.FOLIAGE_LIGHT, Palette.FOLIAGE, Palette.FOLIAGE, false)
	return m.commit()


func _build_lily_pads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var c: Vector2 = terrain.pond_center
	var level: float = terrain.pond_level
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _pad_mesh()
	var xforms: Array = []
	var flowers: Array = []
	var tries := 0
	while xforms.size() < 26 and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var edge: float = terrain.pond_edge(a)
		var r := rng.randf_range(edge * 0.25, edge - 1.2)
		var p := Vector2(c.x + cos(a) * r, c.y + sin(a) * r)
		# cluster: keep pads in two soft groups plus a few loners
		var ok := true
		for x in xforms:
			if Vector2((x as Transform3D).origin.x, (x as Transform3D).origin.z).distance_to(p) < 1.1:
				ok = false
				break
		if not ok:
			continue
		var s := rng.randf_range(0.7, 1.25)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s)), Vector3(p.x, level, p.y))
		xforms.append(xf)
		if rng.randf() < 0.3:
			flowers.append(xf.origin + Vector3(rng.randf_range(-0.1, 0.1), 0.05, rng.randf_range(-0.1, 0.1)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LilyPads"
	mmi.multimesh = mm
	mmi.material_override = Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.2}), 0.015)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# Water-lily flowers: small pink cups.
	var fm := NodeVisuals.Merger.new()
	for i in 6:
		var a := TAU * float(i) / 6.0
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(-40.0))
		fm.add(Kit.blob_mesh(0.08, 5200 + i, 0.1, 0.35, 1), Transform3D(b, b * Vector3(0, 0.02, -0.09)), Palette.BLOSSOM.lerp(Color.WHITE, 0.3))
	fm.add(Kit.blob_mesh(0.05, 5210, 0.1, 0.7, 1), Transform3D(Basis(), Vector3(0, 0.05, 0)), Palette.FLOWER_YELLOW)
	var fmesh := fm.commit()
	var fmat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.5}), 0.01)
	for p in flowers:
		var mi := MeshInstance3D.new()
		mi.mesh = fmesh
		mi.material_override = fmat
		add_child(mi)
		mi.position = p
		NodeVisuals.set_visibility_range(mi, 90.0, false)


static func _reed_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + variant
	var m := NodeVisuals.Merger.new()
	var base_c := Color("5f8f45")
	var tip_c := Color("a7c46a")
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.22)
		var root := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var hgt := rng.randf_range(0.9, 1.55)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.2)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		var tip := root + lean + Vector3(0, hgt, 0)
		var n := (Vector3.UP + Vector3(cos(a), 0, sin(a))).normalized()
		m.tri(root - side, tip, root + side, n, base_c, tip_c, base_c, true)
	for i in 3:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.12, rng.randf_range(1.1, 1.45), sin(a) * 0.12)
		m.add(NodeVisuals._cyl(0.012, 0.012, 1.3, 4), Transform3D(Basis(), Vector3(p.x, p.y * 0.5, p.z)), Color("6e8f4a"))
		m.add(NodeVisuals._cyl(0.045, 0.045, 0.2, 6), Transform3D(Basis(), p), Color("7a4f33"))
	return m.commit()


func _build_reeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5400
	var spots: Array = []
	# Pond shore
	var c: Vector2 = terrain.pond_center
	for i in 70:
		var a := rng.randf() * TAU
		var r: float = terrain.pond_edge(a) + rng.randf_range(-0.4, 1.0)
		spots.append(Vector2(c.x + cos(a) * r, c.y + sin(a) * r))
	# Stream banks
	var pts: PackedVector3Array = terrain.stream_pts
	var halves: PackedFloat32Array = terrain.stream_half
	for k in range(0, pts.size(), 5):
		if rng.randf() > 0.55:
			continue
		var a := pts[maxi(k - 2, 0)]
		var b := pts[mini(k + 2, pts.size() - 1)]
		var tng := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var off := halves[k] + rng.randf_range(0.1, 0.9)
		spots.append(Vector2(pts[k].x - tng.z * off * side, pts[k].z + tng.x * off * side))
	var mms: Array = []
	var lists: Array = [[], [], []]
	for p in spots:
		var pp: Vector2 = p
		if terrain.path_at(pp.x, pp.y) > 0.2 or not _inside(pp, 100.0):
			continue
		var near_crossing := false
		for cr in Layout.STREAM_CROSSINGS:
			if (cr as Vector2).distance_to(pp) < 4.5:
				near_crossing = true
		if near_crossing:
			continue
		var y: float = terrain.height_at(pp.x, pp.y)
		var s := rng.randf_range(0.8, 1.2)
		lists[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(pp.x, y, pp.y)))
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
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Reeds%d" % v
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 120.0
		add_child(mmi)
		mms.append(mmi)


func _inside(p: Vector2, lim: float) -> bool:
	return absf(p.x) < lim and absf(p.y) < lim


# --- Crossings -------------------------------------------------------------------------------------

func _build_crossings() -> void:
	for i in Layout.STREAM_CROSSINGS.size():
		var cp: Vector2 = Layout.STREAM_CROSSINGS[i]
		var info: Dictionary = terrain.nearest_stream_point(cp.x, cp.y)
		if info.is_empty():
			continue
		var style: String = SL.CROSSING_STYLE[i] if i < SL.CROSSING_STYLE.size() else "bridge"
		var center: Vector3 = info["pos"]
		var tng: Vector3 = info["tangent"]
		var axis := Vector3(-tng.z, 0.0, tng.x).normalized()   # across the stream
		var half: float = info["half"]
		crossings.append({"pos": center, "style": style, "axis": axis})
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
	var count := 6
	var rng := RandomNumberGenerator.new()
	rng.seed = 5600 + index
	var mat := NodeVisuals.rock_material()
	var profile: Array = []            # [u along the axis, walk height] through the stone tops
	var ua := -span - 1.0
	var pa := center + axis * ua
	profile.append([ua, terrain.height_at(pa.x, pa.z) - 0.04])
	for s in count:
		var u := lerpf(-span, span, float(s) / float(count - 1))
		var jitter := Vector3(-axis.z, 0, axis.x) * rng.randf_range(-0.25, 0.25)
		var p := center + axis * u + jitter
		var ground: float = terrain.height_at(p.x, p.z)
		var top := maxf(center.y + 0.2, ground + 0.12)
		profile.append([u, top])
		var mesh := NodeVisuals.boulder_mesh(s % 3, Palette.STONE.lightened(0.05), 0.6)
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
	# Collision: one smooth walkway through the stone tops (ramp-like, like the bridges). A cylinder per
	# stone left 0.15-0.3 m vertical lips on the main path to the mine that companions (no step-up)
	# could not climb.
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
	var arch := 0.5
	var width := 2.1
	var side := Vector3(-axis.z, 0.0, axis.x)
	var yaw := atan2(axis.x, axis.z)
	center.y = 0.0          # heights below are absolute (deck_y), so the centre only gives x/z
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
	# Beams underneath and rails with posts
	for sgn in [-1.0, 1.0]:
		var sdir: Vector3 = side * float(sgn) * (width * 0.5 - 0.1)
		for p in 7:
			var u := lerpf(-span + 0.2, span - 0.2, float(p) / 6.0)
			var y: float = deck_y.call(u)
			var pos: Vector3 = center + axis * u + sdir
			m.add(NodeVisuals._cyl(0.06, 0.07, 1.0, 7), Transform3D(Basis(), Vector3(pos.x, y + 0.45, pos.z)), Palette.WOOD_DARK)
			m.add(Kit.blob_mesh(0.08, 5700 + p, 0.1, 1.0, 1), Transform3D(Basis(), Vector3(pos.x, y + 0.97, pos.z)), Palette.WOOD)
		for p in 6:
			var u0 := lerpf(-span + 0.2, span - 0.2, float(p) / 6.0)
			var u1 := lerpf(-span + 0.2, span - 0.2, float(p + 1) / 6.0)
			var y0: float = float(deck_y.call(u0)) + 0.9
			var y1: float = float(deck_y.call(u1)) + 0.9
			var p0: Vector3 = center + axis * u0 + sdir + Vector3(0, y0, 0)
			var p1: Vector3 = center + axis * u1 + sdir + Vector3(0, y1, 0)
			var dir := p1 - p0
			var rb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(dir.y, Vector2(dir.x, dir.z).length())) * Basis(Vector3.RIGHT, deg_to_rad(90.0))
			m.add(NodeVisuals._cyl(0.045, 0.045, dir.length(), 6), Transform3D(rb, (p0 + p1) * 0.5), Palette.WOOD_LIGHT)
		# long side beam under the planks
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
	mi.material_override = Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.12, "noise_scale": 2.0, "rim": 0.25}), 0.02)
	root.add_child(mi)
	# Collision: sloped deck segments (walkable ramps) + rails so nobody slips off the sides.
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
		var seg_len := dir.length()
		var bb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(dir.y, Vector2(dir.x, dir.z).length()))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.3, seg_len + 0.08)
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

static func find_audio(sound_name: String) -> AudioStream:
	for d in ["ambience", "sfx"]:
		for ext in ["ogg", "wav"]:
			for suffix in ["", "_1"]:
				var p := "res://assets/audio/%s/%s%s.%s" % [d, sound_name, suffix, ext]
				if ResourceLoader.exists(p):
					return load(p)
	return null


func _setup_audio() -> void:
	var s := find_audio("amb_stream")
	if s == null:
		return
	s = s.duplicate()
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * float((s as AudioStreamWAV).mix_rate))
	_stream_audio = AudioStreamPlayer3D.new()
	_stream_audio.name = "StreamSound"
	_stream_audio.stream = s
	_stream_audio.bus = "Ambience"
	_stream_audio.unit_size = 5.0
	_stream_audio.max_distance = 32.0
	_stream_audio.volume_db = -4.0
	add_child(_stream_audio)
	_stream_audio.play()


func _process(delta: float) -> void:
	if _stream_audio == null:
		set_process(false)
		return
	_audio_t += delta
	if _audio_t < 0.25:
		return
	_audio_t = 0.0
	var cam := get_viewport().get_camera_3d()
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
	var pd: float = Vector2(p.x, p.z).distance_to(terrain.pond_center)
	if pd * pd < bd:
		best = Vector3(terrain.pond_center.x, terrain.pond_level, terrain.pond_center.y)
	_stream_audio.global_position = best + Vector3(0, 0.3, 0)
