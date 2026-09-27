extends RefCounted
## Surface decor meshes (cached, merged, vertex-coloured) for vegetation and landmarks:
## mushrooms, fallen logs, brambles, fences, lantern posts, garlands, standing stones, arches...
## All return ArrayMesh (use with NodeVisuals.rock_material() / bark_material() / foliage_material()).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")

static var _cache: Dictionary = {}


## Red-capped storybook mushrooms with cream spots (1-3 per cluster).
static func mushroom_cluster(variant: int) -> ArrayMesh:
	var key := "mush|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100 + variant
	var m := NodeVisuals.Merger.new()
	var n := 1 + variant % 3
	for i in n:
		var a := rng.randf() * TAU
		var r := 0.0 if i == 0 else rng.randf_range(0.12, 0.22)
		var h := rng.randf_range(0.14, 0.26) * (1.3 if i == 0 else 0.85)
		var cr := rng.randf_range(0.09, 0.14) * (1.3 if i == 0 else 0.85)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		m.add(NodeVisuals._cyl(cr * 0.35, cr * 0.45, h, 7), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)), Color("f3ead6"))
		var cap_c: Color = Palette.FLOWER_RED if variant % 4 != 3 else Color("d98b4e")
		m.add(NodeVisuals._hemi(cr, cr * 0.95, 12), Transform3D(Basis(), p + Vector3(0, h - 0.01, 0)), cap_c)
		for s in 4:
			var sa := rng.randf() * TAU
			var sp := p + Vector3(cos(sa) * cr * 0.55, h + cr * 0.62, sin(sa) * cr * 0.55)
			m.add(NodeVisuals._sph(cr * 0.16, 3, 6), Transform3D(Basis().scaled(Vector3(1, 0.5, 1)), sp), Color("fff4e0"))
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## A mossy fallen log lying along X (length ~3.2 m).
static func fallen_log(variant: int) -> ArrayMesh:
	var key := "log|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8200 + variant
	var m := NodeVisuals.Merger.new()
	var length := rng.randf_range(2.8, 3.6)
	var r := rng.randf_range(0.28, 0.36)
	var along := Basis(Vector3.BACK, deg_to_rad(90.0))
	var bark := func(p: Vector3, n: Vector3) -> Color:
		var c := Palette.BARK.lerp(Palette.BARK_DARK, 0.3)
		if n.y > 0.55:
			c = c.lerp(Palette.MOSS, 0.75)
		return c
	m.add(NodeVisuals._cyl(r * 0.9, r, length, 10, 3), Transform3D(along, Vector3(0, r * 0.85, 0)), bark)
	m.add(NodeVisuals._cyl(r * 0.8, r * 0.8, 0.03, 10), Transform3D(along, Vector3(-length * 0.5 - 0.005, r * 0.85, 0)), Palette.WOOD_LIGHT)
	m.add(NodeVisuals._cyl(r * 0.72, r * 0.72, 0.03, 10), Transform3D(along, Vector3(length * 0.5 + 0.005, r * 0.85, 0)), Palette.WOOD_LIGHT)
	var b := Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, deg_to_rad(55.0))
	m.add(NodeVisuals._cyl(0.05, r * 0.3, 0.9, 6), Transform3D(b, Vector3(0.4, r * 1.3, 0.2)), Palette.BARK)
	for i in 3:
		m.add(Kit.blob_mesh(0.18, 8210 + i, 0.3, 0.5, 1), Transform3D(Basis(), Vector3(rng.randf_range(-1.2, 1.2), r * 1.7, rng.randf_range(-0.1, 0.1))), Palette.MOSS)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## Tangled bramble bush with thorns (Thornthicket).
static func bramble(variant: int) -> ArrayMesh:
	var key := "bramble|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8300 + variant
	var m := NodeVisuals.Merger.new()
	var leaf_lo := Color("3f5f35")
	var leaf_hi := Color("6e8a45")
	var fn := func(p: Vector3, _n: Vector3) -> Color:
		return leaf_lo.lerp(leaf_hi, clampf(p.y / 1.3, 0.0, 1.0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + rng.randf()
		m.add(Kit.blob_mesh(rng.randf_range(0.45, 0.65), 8310 + i + variant * 5, 0.4, 0.8, 1), Transform3D(Basis(), Vector3(cos(a) * 0.5, 0.45, sin(a) * 0.5)), fn)
	for i in 10:
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.4, 1.1)
		var bb := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt)
		var seg_len := rng.randf_range(0.8, 1.4)
		m.add(NodeVisuals._cyl(0.02, 0.045, seg_len, 5), Transform3D(bb, Vector3(0, 0.3, 0) + bb * Vector3(0, seg_len * 0.5, 0)), Color("6a3f4a"))
		for t in 3:
			var tp := Vector3(0, 0.3, 0) + bb * Vector3(0, seg_len * (0.3 + t * 0.25), 0)
			var tb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, deg_to_rad(90.0))
			m.add(NodeVisuals._cyl(0.0, 0.02, 0.09, 4), Transform3D(tb, tp + tb * Vector3(0, 0.04, 0)), Color("c9b58a"))
	for i in 5:
		m.add(NodeVisuals._sph(0.05, 3, 6), Transform3D(Basis(), Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.5, 0.95), rng.randf_range(-0.6, 0.6))), Color("5a2f5f"))
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## One picket fence segment 2 m long along X (posts + rails + pickets), base at y=0.
static func fence_segment() -> ArrayMesh:
	if _cache.has("fence"):
		return _cache["fence"]
	var m := NodeVisuals.Merger.new()
	var wood := Palette.CLOTH_CREAM.darkened(0.05)
	for i in 2:
		var x := -1.0 + float(i) * 2.0
		m.add(NodeVisuals._box(Vector3(0.12, 0.95, 0.12)), Transform3D(Basis(), Vector3(x, 0.47, 0)), Palette.WOOD)
		m.add(NodeVisuals._cyl(0.0, 0.085, 0.12, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(x, 1.0, 0)), Palette.WOOD)
	for y in [0.3, 0.65]:
		m.add(NodeVisuals._box(Vector3(2.0, 0.07, 0.05)), Transform3D(Basis(), Vector3(0, float(y), -0.06)), Palette.WOOD_DARK)
	for i in 7:
		var x := -0.78 + float(i) * 0.26
		var h := 0.78 + (0.04 if i % 2 == 0 else 0.0)
		m.add(NodeVisuals._box(Vector3(0.12, h, 0.035)), Transform3D(Basis(), Vector3(x, h * 0.5, -0.1)), wood)
		m.add(NodeVisuals._cyl(0.0, 0.085, 0.1, 4), Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1, 1, 0.3)), Vector3(x, h + 0.05, -0.1)), wood)
	var mesh := m.commit()
	_cache["fence"] = mesh
	return mesh


## Wooden lantern post (the glass is a separate glow mesh placed at LANTERN_Y).
const LANTERN_Y := 1.95
static func lantern_post() -> ArrayMesh:
	if _cache.has("lpost"):
		return _cache["lpost"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._cyl(0.07, 0.09, 2.2, 8), Transform3D(Basis(), Vector3(0, 1.1, 0)), Palette.WOOD_DARK)
	m.add(Kit.blob_mesh(0.2, 8400, 0.3, 0.4, 1), Transform3D(Basis(), Vector3(0, 0.05, 0)), Palette.STONE)
	m.add(NodeVisuals._box(Vector3(0.5, 0.07, 0.07)), Transform3D(Basis(), Vector3(0.2, 2.15, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._cyl(0.012, 0.012, 0.15, 4), Transform3D(Basis(), Vector3(0.38, 2.05, 0)), Palette.STONE_DARK)
	m.add(NodeVisuals._cyl(0.02, 0.15, 0.1, 8), Transform3D(Basis(), Vector3(0.38, 1.95 + 0.14, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._cyl(0.12, 0.13, 0.04, 8), Transform3D(Basis(), Vector3(0.38, 1.95 - 0.14, 0)), Palette.WOOD_DARK)
	var mesh := m.commit()
	_cache["lpost"] = mesh
	return mesh


static func lantern_glass() -> Mesh:
	if not _cache.has("lglass"):
		var c := CylinderMesh.new()
		c.top_radius = 0.1
		c.bottom_radius = 0.11
		c.height = 0.22
		c.radial_segments = 8
		_cache["lglass"] = c
	return _cache["lglass"]


## A soft stone block (used for the stone ring, ruins and the campfire ring).
static func stone_block(variant: int, size: Vector3, tint: Color = Palette.STONE, moss: float = 0.6) -> ArrayMesh:
	var key := "sblock|%d|%s|%s|%.2f" % [variant, size, tint.to_html(), moss]
	if _cache.has(key):
		return _cache[key]
	var m := NodeVisuals.Merger.new()
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var c := tint.darkened(0.25).lerp(tint, clampf(p.y / maxf(size.y, 0.1) + 0.4, 0.0, 1.0))
		if n.y > 0.6 and moss > 0.0:
			c = c.lerp(Palette.MOSS, moss * clampf((n.y - 0.6) * 3.0, 0.0, 1.0))
		return c
	var blob := Kit.blob_mesh(0.5, 8500 + variant, 0.18, 1.0, 2)
	m.add(blob, Transform3D(Basis().scaled(size), Vector3(0, size.y * 0.5, 0)), fn)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## Small bunting garland (triangular flags) spanning `length` along X with a gentle sag.
static func garland(length: float, colors: Array) -> ArrayMesh:
	var key := "garland|%.2f|%s" % [length, str(colors)]
	if _cache.has(key):
		return _cache[key]
	var m := NodeVisuals.Merger.new()
	var n := maxi(3, int(length / 0.45))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var x := lerpf(-length * 0.5, length * 0.5, t)
		var sag := -sin(t * PI) * 0.35
		var c: Color = colors[i % colors.size()]
		var a := Vector3(x - 0.14, sag, 0)
		var b := Vector3(x + 0.14, sag, 0)
		var tip := Vector3(x, sag - 0.3, 0)
		m.tri(a, b, tip, Vector3.BACK, c, c, c.darkened(0.1), true)
	for i in 12:
		var t0 := float(i) / 12.0
		var t1 := float(i + 1) / 12.0
		var p0 := Vector3(lerpf(-length * 0.5, length * 0.5, t0), -sin(t0 * PI) * 0.35 + 0.01, 0)
		var p1 := Vector3(lerpf(-length * 0.5, length * 0.5, t1), -sin(t1 * PI) * 0.35 + 0.01, 0)
		var dir := p1 - p0
		var bb := Basis(Vector3.BACK, atan2(dir.y, dir.x) - PI * 0.5)
		m.add(NodeVisuals._cyl(0.012, 0.012, dir.length(), 4), Transform3D(bb, (p0 + p1) * 0.5), Palette.WOOD_DARK)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## Helper: MeshInstance3D with material; optional visibility range.
static func instance(mesh: Mesh, material: Material, vis_range: float = 0.0, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	if vis_range > 0.0:
		mi.visibility_range_end = vis_range
		mi.visibility_range_end_margin = vis_range * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # outline passes cannot dither-fade
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Builds one MultiMeshInstance3D from transforms.
static func multimesh(mesh: Mesh, material: Material, xforms: Array, node_name: String, vis_range: float = 0.0, shadows: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	if vis_range > 0.0:
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_end_margin = vis_range * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # outline passes cannot dither-fade
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
