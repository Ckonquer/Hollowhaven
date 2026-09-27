extends RefCounted
## Visual builders for harvestable world props, shared by the surface and the Below.
## Meshes are merged (one mesh per material) and cached, so hundreds of props share geometry.
##   const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
##   var v: Node3D = NodeVisuals.build("oak", 3)                  # fresh Node3D, shared meshes
##   var v2: Node3D = NodeVisuals.build("rubble", 0, {"tint": Palette.MINE_ROCK, "scale": 1.4})
##
## Visual ids:
##   trees:   oak, pine, blossom, birch            (children "Top" [falls when felled] and "Stump")
##   rocks:   boulder, copper_vein, rubble, pebble, crystal
##   plants:  berry_bush (child "Berries" hides when picked), bush, grass_tuft, glowcap, stick
##   dungeon: silk (soft silk tuft) / roots (arachnophobia replacement; silk picks it automatically)
## Root metadata read by resource_node.gd:
##   "solid" ("cylinder" | "convex" | "none"), "solid_radius", "solid_height", "convex" (Shape3D),
##   "interact_radius", "interact_y", "fx_height", "stump_radius", "stump_height"
##
## Tree meshes are also exposed for decorative MultiMesh forests: tree_parts(species, variant) ->
##   {"trunk": ArrayMesh, "crown": ArrayMesh, "stump": ArrayMesh, "trunk_radius", "height", "crown_y"}
## with bark_material() / foliage_material(wind, wind_height) / crown_material(species).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const FOLIAGE_SHADER := preload("res://shaders/surface_foliage.gdshader")
const FOLIAGE_OUTLINE_SHADER := preload("res://shaders/surface_foliage_outline.gdshader")

const TREE_SPECIES := ["oak", "pine", "blossom", "birch"]
const TREE_VARIANTS := 3
const PINE_DARK := Color("3d6e4c")
const PINE_LIGHT := Color("79ab5c")
const BLOSSOM_DEEP := Color("e27f9f")
const BLOSSOM_PALE := Color("ffd9e6")
const BIRCH_BARK := Color("efe7d4")
const BIRCH_MARK := Color("4f4340")
const BIRCH_LEAF_LO := Color("7fae4c")
const BIRCH_LEAF_HI := Color("bcd46c")
const SILK_ROOT := Color("d9ccb2")

static var _cache: Dictionary = {}


## Accumulates transformed mesh surfaces into one vertex-coloured ArrayMesh.
## Colours are given in sRGB (palette values) and stored LINEAR, because shaders read COLOR raw.
class Merger:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## Source arrays per mesh resource (primitive meshes regenerate their arrays on every
	## surface_get_arrays() call, which is slow), keyed by instance id.
	static var _src: Dictionary = {}

	static func source_arrays(mesh: Mesh) -> Array:
		var key := mesh.get_instance_id()
		if _src.has(key):
			return _src[key]
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx_raw: Variant = arr[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if idx_raw is PackedInt32Array and not (idx_raw as PackedInt32Array).is_empty():
			idx = idx_raw
		else:
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var res: Array = [v, n, idx]
		_src[key] = res
		return res

	## Appends surface 0 of `mesh` transformed by `xf`. `col`: Color, or Callable(p: Vector3, n: Vector3) -> Color.
	func add(mesh: Mesh, xf: Transform3D, col: Variant) -> void:
		var src := source_arrays(mesh)
		var v: PackedVector3Array = src[0]
		var n: PackedVector3Array = src[1]
		var idx: PackedInt32Array = src[2]
		var base := verts.size()
		var tv: PackedVector3Array = xf * v
		var sc := xf.basis.get_scale()
		var tn: PackedVector3Array
		if absf(sc.x - sc.y) < 0.0001 and absf(sc.x - sc.z) < 0.0001:
			tn = Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * n
		else:
			tn = Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * n
			for i in tn.size():
				tn[i] = tn[i].normalized()
		verts.append_array(tv)
		normals.append_array(tn)
		var cs := PackedColorArray()
		cs.resize(tv.size())
		if col is Callable:
			var fn: Callable = col
			for i in tv.size():
				var c: Color = fn.call(tv[i], tn[i])
				cs[i] = c.srgb_to_linear()
		else:
			var fixed: Color = col if col is Color else Color.WHITE
			cs.fill(fixed.srgb_to_linear())
		colors.append_array(cs)
		var ii := PackedInt32Array()
		ii.resize(idx.size())
		for k in idx.size():
			ii[k] = idx[k] + base
		indices.append_array(ii)

	## Like add(), then pushes vertices radially (around the vertical axis through `center`) by noise, so
	## smooth primitives (cones, cylinders) get an organic, hand-made wobble. Position-based: no cracks.
	func add_lumpy(mesh: Mesh, xf: Transform3D, col: Variant, amount: float, center: Vector3, seed_value: int = 0) -> void:
		var start := verts.size()
		add(mesh, xf, col)
		var nz := FastNoiseLite.new()
		nz.seed = seed_value
		nz.frequency = 1.1
		for i in range(start, verts.size()):
			var p := verts[i]
			var radial := Vector3(p.x - center.x, 0.0, p.z - center.z)
			var r := radial.length()
			if r < 0.001:
				continue
			var d := nz.get_noise_3dv(p) * amount * minf(r, 1.5)
			verts[i] = p + radial / r * d - Vector3(0, absf(d) * 0.4, 0)

	## Adds one triangle (clockwise front face, Godot convention). two_sided adds the back face too.
	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color, two_sided: bool = false) -> void:
		var base := verts.size()
		verts.append_array(PackedVector3Array([a, b, c]))
		normals.append_array(PackedVector3Array([n, n, n]))
		var la := ca.srgb_to_linear()
		var lb := cb.srgb_to_linear()
		var lc := cc.srgb_to_linear()
		colors.append_array(PackedColorArray([la, lb, lc]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
		if two_sided:
			var b2 := verts.size()
			verts.append_array(PackedVector3Array([a, c, b]))
			normals.append_array(PackedVector3Array([n, n, n]))
			colors.append_array(PackedColorArray([la, lc, lb]))
			indices.append_array(PackedInt32Array([b2, b2 + 1, b2 + 2]))

	func is_empty() -> bool:
		return verts.is_empty()

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


# --- Shared unit blobs ------------------------------------------------------------------------

## A unit-radius blob from a small seed pool; scale it with sxf(). Blob noise is radius-relative, so a
## scaled unit blob looks exactly like a blob of that radius - and every tree shares the same few meshes.
static func ublob(seed_value: int, lump: float, squash: float, subdiv: int) -> ArrayMesh:
	return Kit.blob_mesh(1.0, 700 + posmod(seed_value, 8), lump, squash, subdiv)


static func sxf(r: float, pos: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(r, r, r)), pos)


# --- Public entry ---------------------------------------------------------------------------

## Builds a visual by id. seed_value picks the variant; opts: {"tint": Color, "scale": float, "arachno": bool}.
static func build(visual_id: String, seed_value: int = 0, opts: Dictionary = {}) -> Node3D:
	var root: Node3D
	match visual_id:
		"oak", "pine", "blossom", "birch":
			root = _tree(visual_id, seed_value)
		"boulder":
			root = _boulder(seed_value, opts)
		"copper_vein":
			root = _copper_vein(seed_value)
		"rubble":
			root = _rubble(seed_value, opts)
		"pebble":
			root = _pebble(seed_value, opts)
		"crystal":
			root = _crystal(seed_value)
		"berry_bush":
			root = _bush(seed_value, true)
		"bush":
			root = _bush(seed_value, false)
		"grass_tuft":
			root = _grass_tuft(seed_value)
		"glowcap":
			root = _glowcap(seed_value)
		"stick":
			root = _stick(seed_value)
		"silk", "roots":
			var arachno: bool = bool(opts.get("arachno", false)) or visual_id == "roots"
			root = _roots(seed_value) if arachno else _silk(seed_value)
		_:
			root = _boulder(seed_value, opts)
	root.name = "Visual"
	var s := float(opts.get("scale", 1.0))
	if absf(s - 1.0) > 0.001:
		root.scale = Vector3.ONE * s
	return root


# --- Shared materials -------------------------------------------------------------------------

static func bark_material() -> Material:
	var key := "mat_bark"
	if not _cache.has(key):
		_cache[key] = Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.14, "noise_scale": 1.7, "rim": 0.18}), 0.022)
	return _cache[key]


## Vertex-coloured toon material with outline (rocks, sticks, pebbles, rubble).
static func rock_material(outline: float = 0.028) -> Material:
	var key := "mat_rock|%.3f" % outline
	if not _cache.has(key):
		var base := Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.13, "noise_scale": 1.3, "rim": 0.22})
		_cache[key] = Mat.outlined(base, outline) if outline > 0.0 else base
	return _cache[key]


## Foliage shader material (+ matching swaying outline pass).
static func foliage_material(wind: float = 0.06, wind_height: float = 5.0, outline: float = 0.03, translucency: float = 0.22) -> ShaderMaterial:
	var key := "mat_fol|%.3f|%.2f|%.3f|%.2f" % [wind, wind_height, outline, translucency]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("wind_strength", wind)
	m.set_shader_parameter("wind_height", wind_height)
	m.set_shader_parameter("translucency", translucency)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = FOLIAGE_OUTLINE_SHADER
		o.set_shader_parameter("thickness", outline)
		o.set_shader_parameter("wind_strength", wind)
		o.set_shader_parameter("wind_height", wind_height)
		m.next_pass = o
	_cache[key] = m
	return m


static func crown_material(species: String) -> ShaderMaterial:
	match species:
		"pine":
			return foliage_material(0.045, 7.0, 0.035, 0.12)
		"birch":
			return foliage_material(0.075, 5.5, 0.03, 0.3)
		"blossom":
			return foliage_material(0.055, 4.5, 0.03, 0.3)
	return foliage_material(0.06, 5.0, 0.034, 0.22)


static func _cyl(top: float, bottom: float, h: float, seg: int = 10, rings: int = 1) -> CylinderMesh:
	var key := "cylm|%.3f|%.3f|%.3f|%d|%d" % [top, bottom, h, seg, rings]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = seg
		m.rings = rings
		_cache[key] = m
	return _cache[key]


static func _box(size: Vector3) -> BoxMesh:
	var key := "boxm|%s" % size
	if not _cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]


static func _sph(r: float, rings: int = 6, seg: int = 10) -> SphereMesh:
	var key := "sphm|%.3f|%d|%d" % [r, rings, seg]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.rings = rings
		m.radial_segments = seg
		_cache[key] = m
	return _cache[key]


static func _hemi(r: float, h: float, seg: int = 14) -> SphereMesh:
	var key := "hemi|%.3f|%.3f|%d" % [r, h, seg]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = h
		m.is_hemisphere = true
		m.rings = 5
		m.radial_segments = seg
		_cache[key] = m
	return _cache[key]


static func _mi(mesh: Mesh, mat: Material, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if node_name != "":
		mi.name = node_name
	return mi


## Sets a visibility range on every GeometryInstance3D under `n` (small props fade out with distance).
static func set_visibility_range(n: Node, end_dist: float, cast_shadows: bool = true) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_end = end_dist
		g.visibility_range_end_margin = end_dist * 0.12
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # outline passes cannot dither-fade
		if not cast_shadows:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		set_visibility_range(c, end_dist, cast_shadows)


# --- Trees ------------------------------------------------------------------------------------

## Cached merged meshes for a tree species/variant (see header).
static func tree_parts(species: String, variant: int) -> Dictionary:
	variant = posmod(variant, TREE_VARIANTS)
	var key := "tree|%s|%d" % [species, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var d: Dictionary
	match species:
		"pine":
			d = _pine_parts(rng)
		"blossom":
			d = _broadleaf_parts(rng, 0.27, rng.randf_range(1.9, 2.3), 1.25, 5, BLOSSOM_DEEP, BLOSSOM_PALE, Palette.BARK_DARK, Palette.BARK)
		"birch":
			d = _birch_parts(rng)
		_:
			d = _broadleaf_parts(rng, rng.randf_range(0.36, 0.43), rng.randf_range(2.3, 2.8), 1.6, 6, Palette.FOLIAGE_DARK, Palette.FOLIAGE_LIGHT, Palette.BARK_DARK, Palette.BARK)
	d["stump"] = _stump_mesh(float(d["trunk_radius"]), species == "birch")
	_cache[key] = d
	return d


static func _broadleaf_parts(rng: RandomNumberGenerator, r0: float, trunk_h: float, crown_r: float, n_blobs: int, lo: Color, hi: Color, bark_lo: Color, bark_hi: Color) -> Dictionary:
	var tr := Merger.new()
	var th := trunk_h + crown_r * 0.6
	var bark_fn := func(p: Vector3, _n: Vector3) -> Color:
		return bark_lo.lerp(bark_hi, clampf(p.y / th, 0.0, 1.0))
	tr.add(_cyl(r0 * 0.6, r0, th, 10, 2), Transform3D(Basis(), Vector3(0, th * 0.5, 0)), bark_fn)
	for i in 4:
		var a := TAU * float(i) / 4.0 + rng.randf() * 0.6
		tr.add(ublob(i, 0.25, 0.55, 1), sxf(r0 * 0.62, Vector3(cos(a) * r0 * 0.75, 0.1, sin(a) * r0 * 0.75)), bark_lo)
	for i in 2:
		var a := rng.randf() * TAU
		var b := Basis(Vector3.UP, a) * Basis(Vector3.BACK, deg_to_rad(rng.randf_range(38.0, 55.0)))
		var start := Vector3(0, trunk_h * rng.randf_range(0.6, 0.85), 0)
		tr.add(_cyl(r0 * 0.12, r0 * 0.34, 1.3, 7), Transform3D(b, start + b * Vector3(0, 0.62, 0)), bark_hi)
	var cr := Merger.new()
	var cy := trunk_h + crown_r * 0.72
	var y0 := cy - crown_r * 1.05
	var y1 := cy + crown_r * 1.35
	var blobs: Array = [[Vector3(0, cy, 0), crown_r * 1.05, 3]]
	for i in n_blobs:
		var a := TAU * float(i) / float(n_blobs) + rng.randf_range(-0.3, 0.3)
		var rr := crown_r * rng.randf_range(0.62, 0.8)
		var off := Vector3(cos(a) * crown_r * 0.85, rng.randf_range(-0.35, 0.25) * crown_r, sin(a) * crown_r * 0.85)
		blobs.append([Vector3(0, cy, 0) + off, rr, 2])
	blobs.append([Vector3(rng.randf_range(-0.3, 0.3), cy + crown_r * 0.75, rng.randf_range(-0.3, 0.3)), crown_r * 0.72, 2])
	for bi in blobs.size():
		var b: Array = blobs[bi]
		var center: Vector3 = b[0]
		var tint := rng.randf_range(-0.05, 0.05)
		var fn := func(p: Vector3, n: Vector3) -> Color:
			var t := clampf((p.y - y0) / (y1 - y0), 0.0, 1.0)
			var c := lo.lerp(hi, t * t * 0.4 + t * 0.6)
			var inner := clampf(Vector2(p.x, p.z).length() / (crown_r * 1.6), 0.0, 1.0)
			c = c.darkened((1.0 - inner) * 0.14 * (1.0 - t))
			c = c.lerp(Palette.MEADOW_GOLD, clampf(n.y, 0.0, 1.0) * 0.1 * t)
			return c.lightened(tint) if tint > 0.0 else c.darkened(-tint)
		cr.add(ublob(rng.randi_range(1, 9999), 0.22, 0.86, int(b[2])), sxf(float(b[1]), center), fn)
	return {"trunk": tr.commit(), "crown": cr.commit(), "trunk_radius": r0, "height": y1, "crown_y": cy}


static func _pine_parts(rng: RandomNumberGenerator) -> Dictionary:
	var r0 := rng.randf_range(0.26, 0.32)
	var tr := Merger.new()
	var trunk_h := 3.2
	var bark_fn := func(p: Vector3, _n: Vector3) -> Color:
		return Palette.BARK_DARK.lerp(Palette.BARK, clampf(p.y / trunk_h, 0.0, 1.0))
	tr.add(_cyl(r0 * 0.5, r0, trunk_h, 9, 1), Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0)), bark_fn)
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf()
		tr.add(ublob(i + 3, 0.25, 0.55, 1), sxf(r0 * 0.6, Vector3(cos(a) * r0 * 0.7, 0.1, sin(a) * r0 * 0.7)), Palette.BARK_DARK)
	var cr := Merger.new()
	var tiers := rng.randi_range(4, 5)
	var base_y := 1.25
	var r := rng.randf_range(1.85, 2.15)
	var top_y := 0.0
	var y := base_y
	for i in tiers:
		var h := 2.3 - float(i) * 0.22
		var rr := r * (1.0 - float(i) / float(tiers + 0.6))
		var tb := y
		var te := y + h
		var fn := func(p: Vector3, n: Vector3) -> Color:
			var tl := clampf((p.y - tb) / (te - tb), 0.0, 1.0)
			var c := PINE_DARK.lerp(PINE_LIGHT, tl * 0.75 + float(i) * 0.06)
			if n.y < -0.5:
				c = PINE_DARK.darkened(0.25)
			return c
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05))
		cr.add_lumpy(_cyl(0.06, rr, h, 14, 3), Transform3D(b, Vector3(0, y + h * 0.5, 0)), fn, 0.22, Vector3(0, y, 0), rng.randi())
		top_y = te
		y += h * 0.52
	return {"trunk": tr.commit(), "crown": cr.commit(), "trunk_radius": r0, "height": top_y, "crown_y": base_y + (top_y - base_y) * 0.4}


static func _birch_parts(rng: RandomNumberGenerator) -> Dictionary:
	var r0 := rng.randf_range(0.2, 0.24)
	var trunk_h := rng.randf_range(4.2, 4.8)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var tr := Merger.new()
	var bark_fn := func(p: Vector3, _n: Vector3) -> Color:
		var m := noise.get_noise_3d(p.x * 2.0, p.y * 3.0, p.z * 2.0)
		return BIRCH_MARK if m > 0.22 and p.y > 0.3 else BIRCH_BARK.darkened(0.05 if p.y < 0.4 else 0.0)
	tr.add(_cyl(r0 * 0.6, r0, trunk_h, 10, 12), Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0)), bark_fn)
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf()
		tr.add(ublob(i + 5, 0.25, 0.55, 1), sxf(r0 * 0.7, Vector3(cos(a) * r0 * 0.7, 0.08, sin(a) * r0 * 0.7)), BIRCH_BARK.darkened(0.12))
	var cr := Merger.new()
	var y0 := trunk_h - 1.5
	var y1 := trunk_h + 2.4
	var n_blobs := 5
	for i in n_blobs:
		var t := float(i) / float(n_blobs - 1)
		var cy := lerpf(trunk_h - 0.6, trunk_h + 1.6, t)
		var rr := lerpf(0.95, 0.55, t) * rng.randf_range(0.9, 1.1)
		var off := Vector3(rng.randf_range(-0.75, 0.75), 0.0, rng.randf_range(-0.75, 0.75)) * (1.0 - t * 0.5)
		var fn := func(p: Vector3, n: Vector3) -> Color:
			var tt := clampf((p.y - y0) / (y1 - y0), 0.0, 1.0)
			return BIRCH_LEAF_LO.lerp(BIRCH_LEAF_HI, tt * 0.8 + clampf(n.y, 0.0, 1.0) * 0.15)
		cr.add(ublob(rng.randi_range(1, 9999), 0.3, 0.9, 2), sxf(rr, Vector3(0, cy, 0) + off), fn)
	return {"trunk": tr.commit(), "crown": cr.commit(), "trunk_radius": r0, "height": y1, "crown_y": trunk_h + 0.4}


static func _stump_mesh(r0: float, birch: bool) -> ArrayMesh:
	var m := Merger.new()
	var bark: Color = BIRCH_BARK if birch else Palette.BARK
	m.add(_cyl(r0 * 0.92, r0 * 1.02, 0.5, 10), Transform3D(Basis(), Vector3(0, 0.25, 0)), bark)
	m.add(_cyl(r0 * 0.9, r0 * 0.9, 0.04, 10), Transform3D(Basis(), Vector3(0, 0.51, 0)), Palette.WOOD_LIGHT)
	m.add(_cyl(r0 * 0.45, r0 * 0.45, 0.02, 10), Transform3D(Basis(), Vector3(0, 0.535, 0)), Palette.WOOD)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		m.add(ublob(i, 0.25, 0.55, 1), sxf(r0 * 0.62, Vector3(cos(a) * r0 * 0.75, 0.1, sin(a) * r0 * 0.75)), Palette.BARK_DARK)
	return m.commit()


static func _tree(species: String, seed_value: int) -> Node3D:
	var parts := tree_parts(species, seed_value)
	var root := Node3D.new()
	var top := Node3D.new()
	top.name = "Top"
	root.add_child(top)
	var trunk := _mi(parts["trunk"], bark_material(), "Trunk")
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # the crown's shadow reads; saves draws
	top.add_child(trunk)
	top.add_child(_mi(parts["crown"], crown_material(species), "Crown"))
	var stump := _mi(parts["stump"], bark_material(), "Stump")
	stump.visible = false
	root.add_child(stump)
	var r0 := float(parts["trunk_radius"])
	root.set_meta("solid", "cylinder")
	root.set_meta("solid_radius", r0 + 0.06)
	root.set_meta("solid_height", 3.2)
	root.set_meta("stump_radius", r0 + 0.04)
	root.set_meta("stump_height", 0.55)
	root.set_meta("interact_radius", r0 + 0.5)
	root.set_meta("interact_y", 1.2)
	root.set_meta("fx_height", float(parts["crown_y"]))
	root.set_meta("height", float(parts["height"]))
	set_visibility_range(root, 150.0)
	return root


# --- Rocks --------------------------------------------------------------------------------------

static func _rock_color_fn(base: Color, moss: float, dark: Color) -> Callable:
	return func(p: Vector3, n: Vector3) -> Color:
		var c := dark.lerp(base, clampf(p.y * 1.2 + 0.55, 0.0, 1.0))
		if moss > 0.0 and n.y > 0.55:
			c = c.lerp(Palette.MOSS, clampf((n.y - 0.55) * 3.0, 0.0, 1.0) * moss)
		return c


static func _convex_for(mesh: Mesh, key: String) -> Shape3D:
	var k := "convex|" + key
	if not _cache.has(k):
		_cache[k] = convex_from_points(mesh)
	return _cache[k]


## Fast convex collider from a mesh's vertices (the physics engine builds the hull; no simplification pass).
static func convex_from_points(mesh: Mesh, max_points: int = 160) -> ConvexPolygonShape3D:
	var pts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	var step := maxi(1, int(ceil(float(pts.size()) / float(max_points))))
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var lo_i := PackedInt32Array([0, 0, 0])
	var hi_i := PackedInt32Array([0, 0, 0])
	for i in pts.size():
		var p := pts[i]
		for a in 3:
			if p[a] < lo[a]:
				lo[a] = p[a]
				lo_i[a] = i
			if p[a] > hi[a]:
				hi[a] = p[a]
				hi_i[a] = i
		if i % step == 0:
			out.append(p)
	for a in 3:
		out.append(pts[lo_i[a]])
		out.append(pts[hi_i[a]])
	var sh := ConvexPolygonShape3D.new()
	sh.points = out
	return sh


static func boulder_mesh(variant: int, tint: Color = Palette.STONE, moss: float = 0.8) -> ArrayMesh:
	var key := "boulder|%d|%s|%.2f" % [variant, tint.to_html(), moss]
	if _cache.has(key):
		return _cache[key]
	var m := Merger.new()
	var dark := tint.darkened(0.3)
	m.add(Kit.blob_mesh(1.0, 300 + variant * 17, 0.3, 0.72, 3), Transform3D(Basis(), Vector3(0, 0.45, 0)), _rock_color_fn(tint, moss, dark))
	if variant % 2 == 0:
		m.add(Kit.blob_mesh(0.45, 320 + variant, 0.3, 0.7, 2), Transform3D(Basis(), Vector3(0.85, 0.15, 0.3)), _rock_color_fn(tint, moss, dark))
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


static func _boulder(seed_value: int, opts: Dictionary) -> Node3D:
	var variant := posmod(seed_value, 3)
	var tint: Color = opts.get("tint", Palette.STONE)
	var moss: float = float(opts.get("moss", 0.8))
	var mesh := boulder_mesh(variant, tint, moss)
	var root := Node3D.new()
	root.add_child(_mi(mesh, rock_material(), "Rock"))
	root.set_meta("solid", "convex")
	root.set_meta("convex", _convex_for(mesh, "boulder|%d|%s|%.2f" % [variant, tint.to_html(), moss]))
	root.set_meta("interact_radius", 1.35)
	root.set_meta("interact_y", 0.6)
	root.set_meta("fx_height", 0.8)
	return root


static func _copper_vein(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "copper|%d" % variant
	var root := Node3D.new()
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 700 + variant
		var rock := Merger.new()
		rock.add(Kit.blob_mesh(0.85, 400 + variant, 0.32, 0.85, 3), Transform3D(Basis(), Vector3(0, 0.42, 0)), _rock_color_fn(Palette.STONE_DARK, 0.3, Palette.STONE_DARK.darkened(0.35)))
		var nug := Merger.new()
		for i in 7:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1.0), rng.randf_range(-1, 1)).normalized()
			var p := Vector3(0, 0.42, 0) + Vector3(dir.x * 0.78, dir.y * 0.66, dir.z * 0.78)
			var c := Palette.COPPER.lerp(Color("ffcf8a"), rng.randf() * 0.4)
			nug.add(Kit.blob_mesh(rng.randf_range(0.1, 0.17), 410 + i, 0.35, 0.8, 1), Transform3D(Basis(), p), c)
		var rm := rock.commit()
		_cache[key] = [rm, nug.commit(), convex_from_points(rm)]
	var parts: Array = _cache[key]
	root.add_child(_mi(parts[0], rock_material(), "Rock"))
	var glint := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Palette.COPPER, "emission_energy": 0.45, "specular": 0.7, "rim": 0.6})
	root.add_child(_mi(parts[1], Mat.outlined(glint, 0.012), "Ore"))
	root.set_meta("solid", "convex")
	root.set_meta("convex", parts[2])
	root.set_meta("interact_radius", 1.2)
	root.set_meta("interact_y", 0.5)
	root.set_meta("fx_height", 0.7)
	return root


static func _rubble(seed_value: int, opts: Dictionary) -> Node3D:
	var tint: Color = opts.get("tint", Palette.STONE)
	var variant := posmod(seed_value, 2)
	var key := "rubble|%d|%s" % [variant, tint.to_html()]
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + variant
		var m := Merger.new()
		var dark := tint.darkened(0.35)
		var stones: Array = [[Vector3(0, 0.45, 0), 0.75], [Vector3(-0.7, 0.25, 0.2), 0.5], [Vector3(0.75, 0.28, -0.1), 0.55],
			[Vector3(0.1, 0.25, 0.65), 0.45], [Vector3(-0.2, 0.3, -0.6), 0.5], [Vector3(0.35, 0.95, 0.1), 0.42],
			[Vector3(-0.4, 0.85, -0.1), 0.38], [Vector3(1.15, 0.15, 0.45), 0.3], [Vector3(-1.1, 0.14, -0.4), 0.28]]
		for i in stones.size():
			var s: Array = stones[i]
			m.add(Kit.blob_mesh(float(s[1]), 930 + i + variant * 11, 0.35, 0.8, 2), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), s[0]), _rock_color_fn(tint, 0.25, dark))
		# a couple of old planks poking out
		for i in 2:
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(55.0, 75.0)))
			m.add(_box(Vector3(0.18, 1.4, 0.06)), Transform3D(b, Vector3(rng.randf_range(-0.6, 0.6), 0.55, rng.randf_range(-0.4, 0.4))), Palette.WOOD_DARK)
		var mesh := m.commit()
		_cache[key] = [mesh, convex_from_points(mesh)]
	var parts: Array = _cache[key]
	var root := Node3D.new()
	root.add_child(_mi(parts[0], rock_material(), "Rubble"))
	root.set_meta("solid", "convex")
	root.set_meta("convex", parts[1])
	root.set_meta("interact_radius", 1.6)
	root.set_meta("interact_y", 0.6)
	root.set_meta("fx_height", 0.8)
	return root


static func _pebble(seed_value: int, opts: Dictionary) -> Node3D:
	var variant := posmod(seed_value, 3)
	var tint: Color = opts.get("tint", Palette.STONE)
	var key := "pebble|%d|%s" % [variant, tint.to_html()]
	if not _cache.has(key):
		var m := Merger.new()
		m.add(Kit.blob_mesh(0.2, 600 + variant, 0.25, 0.62, 2), Transform3D(Basis(), Vector3(0, 0.1, 0)), _rock_color_fn(tint.lightened(0.08), 0.0, tint.darkened(0.2)))
		m.add(Kit.blob_mesh(0.11, 610 + variant, 0.3, 0.6, 1), Transform3D(Basis(), Vector3(0.22, 0.05, 0.08)), _rock_color_fn(tint, 0.0, tint.darkened(0.25)))
		_cache[key] = m.commit()
	var root := Node3D.new()
	root.add_child(_mi(_cache[key], rock_material(0.018), "Pebble"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.55)
	root.set_meta("interact_y", 0.25)
	root.set_meta("fx_height", 0.2)
	set_visibility_range(root, 70.0, false)
	return root


static func _crystal(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 2)
	var key := "crystal|%d" % variant
	var col := Color("b9a3f0")
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1200 + variant
		var m := Merger.new()
		var base := Merger.new()
		base.add(Kit.blob_mesh(0.55, 1210 + variant, 0.3, 0.55, 2), Transform3D(Basis(), Vector3(0, 0.15, 0)), _rock_color_fn(Palette.SILK_ROCK, 0.0, Palette.SILK_ROCK_DARK))
		for i in 6:
			var h := rng.randf_range(0.6, 1.3) * (1.4 if i == 0 else 1.0)
			var r := rng.randf_range(0.1, 0.17) * (1.4 if i == 0 else 1.0)
			var tilt := 0.0 if i == 0 else rng.randf_range(0.3, 0.7)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
			var c := col.lerp(Color("e6dcff"), rng.randf() * 0.5)
			var fn := func(p: Vector3, _n: Vector3) -> Color:
				return c.darkened(0.25).lerp(c.lightened(0.2), clampf(p.y / 1.4, 0.0, 1.0))
			m.add(_cyl(r, r, h, 6), Transform3D(b, b * Vector3(0, h * 0.5, 0) + Vector3(0, 0.1, 0)), fn)
			m.add(_cyl(0.0, r, r * 1.8, 6), Transform3D(b, b * Vector3(0, h + r * 0.9, 0) + Vector3(0, 0.1, 0)), c.lightened(0.25))
		var mesh := m.commit()
		_cache[key] = [mesh, base.commit(), convex_from_points(mesh)]
	var parts: Array = _cache[key]
	var root := Node3D.new()
	root.add_child(_mi(parts[1], rock_material(), "Base"))
	var cm := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": col, "emission_energy": 0.9, "specular": 0.8, "rim": 0.8})
	root.add_child(_mi(parts[0], Mat.outlined(cm, 0.015), "Crystal"))
	root.set_meta("solid", "convex")
	root.set_meta("convex", parts[2])
	root.set_meta("interact_radius", 1.0)
	root.set_meta("interact_y", 0.6)
	root.set_meta("fx_height", 0.8)
	return root


# --- Plants ---------------------------------------------------------------------------------------

static func bush_mesh(variant: int, lo: Color = Palette.FOLIAGE_DARK, hi: Color = Palette.FOLIAGE) -> ArrayMesh:
	var key := "bushm|%d|%s|%s" % [variant, lo.to_html(), hi.to_html()]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1500 + variant
	var m := Merger.new()
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var t := clampf(p.y / 1.3, 0.0, 1.0)
		return lo.lerp(hi, t).lerp(Palette.MEADOW_GOLD, clampf(n.y, 0.0, 1.0) * 0.08)
	m.add(Kit.blob_mesh(0.72, 1510 + variant, 0.25, 0.8, 2), Transform3D(Basis(), Vector3(0, 0.55, 0)), fn)
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf() * 0.8
		m.add(Kit.blob_mesh(rng.randf_range(0.45, 0.55), 1520 + i + variant * 3, 0.25, 0.85, 2), Transform3D(Basis(), Vector3(cos(a) * 0.55, 0.4, sin(a) * 0.55)), fn)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


static func _bush(seed_value: int, berries: bool) -> Node3D:
	var variant := posmod(seed_value, 3)
	var root := Node3D.new()
	root.add_child(_mi(bush_mesh(variant, Palette.FOLIAGE_DARK.darkened(0.05), Palette.FOLIAGE), foliage_material(0.03, 1.4, 0.022, 0.18), "Leaves"))
	if berries:
		var key := "berries|%d" % variant
		if not _cache.has(key):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1600 + variant
			var m := Merger.new()
			var centers: Array = [[Vector3(0, 0.55, 0), 0.72]]
			for i in 3:
				var a := TAU * float(i) / 3.0 + 0.3
				centers.append([Vector3(cos(a) * 0.55, 0.4, sin(a) * 0.55), 0.5])
			for i in 18:
				var c: Array = centers[i % centers.size()]
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
				var p: Vector3 = c[0] + Vector3(dir.x, dir.y * 0.85, dir.z) * float(c[1]) * 1.12
				var berry_fn := func(_q: Vector3, n: Vector3) -> Color:
					return Palette.BERRY.lerp(Color("ff9aa8"), clampf(n.y, 0.0, 1.0) * 0.45)
				m.add(_sph(0.085, 5, 8), Transform3D(Basis(), p), berry_fn)
			_cache[key] = m.commit()
		var bm := Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.55, "specular": 0.6})
		root.add_child(_mi(_cache[key], Mat.outlined(bm, 0.012), "Berries"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 1.05)
	root.set_meta("interact_y", 0.55)
	root.set_meta("fx_height", 0.8)
	set_visibility_range(root, 110.0)
	return root


static func grass_tuft_mesh(variant: int) -> ArrayMesh:
	var key := "tuft|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1700 + variant
	var m := Merger.new()
	var base_c := Palette.GRASS_DARK
	var tip_c := Color("d9d47a")
	for i in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.2)
		var root_p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := rng.randf_range(0.55, 0.95)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.35)
		var side := Vector3(-sin(a), 0, cos(a)) * rng.randf_range(0.045, 0.07)
		var mid := root_p + lean * 0.4 + Vector3(0, h * 0.55, 0)
		var tip := root_p + lean + Vector3(0, h, 0)
		var n := (Vector3.UP + Vector3(cos(a), 0, sin(a)) * 0.6).normalized()
		var cm := base_c.lerp(tip_c, 0.5)
		m.tri(root_p - side, mid - side * 0.7, root_p + side, n, base_c, cm, base_c, true)
		m.tri(root_p + side, mid - side * 0.7, mid + side * 0.7, n, base_c, cm, cm, true)
		m.tri(mid - side * 0.7, tip, mid + side * 0.7, n, cm, tip_c, cm, true)
	# seed heads on a few blades make the harvestable tuft read differently from lawn grass
	for i in 4:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.18, rng.randf_range(0.8, 1.0), sin(a) * 0.18)
		m.add(_sph(0.045, 4, 6), Transform3D(Basis().scaled(Vector3(1, 1.8, 1)), p), Color("e8cf86"))
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


static func _grass_tuft(seed_value: int) -> Node3D:
	var root := Node3D.new()
	var mat := foliage_material(0.07, 0.9, 0.0, 0.35)
	root.add_child(_mi(grass_tuft_mesh(posmod(seed_value, 3)), mat, "Blades"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.6)
	root.set_meta("interact_y", 0.4)
	root.set_meta("fx_height", 0.5)
	set_visibility_range(root, 75.0, false)
	return root


static func _glowcap(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "glowcap|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1800 + variant
		var stems := Merger.new()
		var caps := Merger.new()
		var n := rng.randi_range(3, 5)
		for i in n:
			var a := TAU * float(i) / float(n) + rng.randf() * 0.6
			var r := 0.0 if i == 0 else rng.randf_range(0.15, 0.3)
			var h := rng.randf_range(0.18, 0.38) * (1.3 if i == 0 else 1.0)
			var cr := rng.randf_range(0.1, 0.16) * (1.3 if i == 0 else 1.0)
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			var tilt := Basis(Vector3(sin(a), 0, -cos(a)).normalized(), rng.randf_range(0.0, 0.25)) if r > 0.0 else Basis()
			stems.add(_cyl(cr * 0.28, cr * 0.4, h, 7), Transform3D(tilt, p + tilt * Vector3(0, h * 0.5, 0)), Color("eef3e2"))
			caps.add(_hemi(cr, cr * 0.9, 10), Transform3D(tilt, p + tilt * Vector3(0, h - 0.01, 0)), Palette.GLOWCAP.lerp(Color("d8fff0"), rng.randf() * 0.4))
		_cache[key] = [stems.commit(), caps.commit()]
	var parts: Array = _cache[key]
	var root := Node3D.new()
	root.add_child(_mi(parts[0], Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Color("bfe8d8"), "emission_energy": 0.25}), 0.012), "Stems"))
	var capm := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Palette.GLOWCAP, "emission_energy": 1.7, "rim": 0.6})
	root.add_child(_mi(parts[1], Mat.outlined(capm, 0.012), "Caps"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.6)
	root.set_meta("interact_y", 0.25)
	root.set_meta("fx_height", 0.3)
	set_visibility_range(root, 60.0, false)
	return root


static func _stick(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "stick|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1900 + variant
		var m := Merger.new()
		var length := rng.randf_range(0.8, 1.0)
		var along := Basis(Vector3.BACK, deg_to_rad(90.0))    # cylinder Y -> X axis
		var bark_fn := func(p: Vector3, n: Vector3) -> Color:
			return Palette.BARK.lerp(Palette.WOOD, clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 0.6)
		m.add(_cyl(0.05, 0.065, length, 7), Transform3D(along, Vector3(0, 0.065, 0)), bark_fn)
		m.add(_cyl(0.058, 0.058, 0.02, 7), Transform3D(along, Vector3(length * 0.5 + 0.005, 0.065, 0)), Palette.WOOD_LIGHT)
		var tb := Basis(Vector3.UP, deg_to_rad(40.0)) * along
		m.add(_cyl(0.022, 0.035, 0.38, 6), Transform3D(tb, Vector3(0.12, 0.07, -0.12)), bark_fn)
		m.add(Kit.blob_mesh(0.07, 1950 + variant, 0.2, 0.35, 1), Transform3D(Basis(), Vector3(0.28, 0.09, -0.26)), Palette.FOLIAGE_LIGHT)
		m.add(Kit.blob_mesh(0.06, 1960 + variant, 0.2, 0.35, 1), Transform3D(Basis(), Vector3(-0.3, 0.1, 0.08)), Palette.FOLIAGE)
		_cache[key] = m.commit()
	var root := Node3D.new()
	root.add_child(_mi(_cache[key], rock_material(0.016), "Stick"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.6)
	root.set_meta("interact_y", 0.25)
	root.set_meta("fx_height", 0.2)
	set_visibility_range(root, 70.0, false)
	return root


static func _silk(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 2)
	var key := "silk|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2000 + variant
		var m := Merger.new()
		var fn := func(p: Vector3, n: Vector3) -> Color:
			return Palette.SILK_WEB.darkened(0.12).lerp(Color.WHITE, clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 0.7)
		for i in 6:
			var p := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.15, 0.55), rng.randf_range(-0.3, 0.3))
			m.add(Kit.blob_mesh(rng.randf_range(0.14, 0.26), 2010 + i, 0.4, 0.8, 1), Transform3D(Basis(), p), fn)
		for i in 5:
			var a := rng.randf() * TAU
			var b := Basis(Vector3(cos(a), 0, sin(a)), rng.randf_range(0.2, 0.7))
			m.add(_cyl(0.008, 0.012, 0.9, 4), Transform3D(b, b * Vector3(0, 0.45, 0)), Color("f4f1fa"))
		_cache[key] = m.commit()
	var root := Node3D.new()
	var mat := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Palette.SILK_WEB, "emission_energy": 0.25, "rim": 0.9})
	root.add_child(_mi(_cache[key], mat, "Silk"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.7)
	root.set_meta("interact_y", 0.4)
	root.set_meta("fx_height", 0.4)
	set_visibility_range(root, 60.0, false)
	return root


static func _roots(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 2)
	var key := "roots|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2100 + variant
		var m := Merger.new()
		for i in 7:
			var a := rng.randf() * TAU
			var tilt := rng.randf_range(0.5, 1.2)
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt)
			var seg_len := rng.randf_range(0.5, 0.9)
			m.add(_cyl(0.02, 0.055, seg_len, 6), Transform3D(b, Vector3(0, 0.15, 0) + b * Vector3(0, seg_len * 0.5, 0)), SILK_ROOT.darkened(rng.randf() * 0.15))
		for i in 4:
			m.add(Kit.blob_mesh(rng.randf_range(0.08, 0.14), 2110 + i, 0.35, 0.8, 1), Transform3D(Basis(), Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.1, 0.4), rng.randf_range(-0.2, 0.2))), SILK_ROOT.darkened(0.1))
		_cache[key] = m.commit()
	var root := Node3D.new()
	root.add_child(_mi(_cache[key], rock_material(0.012), "Roots"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.7)
	root.set_meta("interact_y", 0.4)
	root.set_meta("fx_height", 0.4)
	set_visibility_range(root, 60.0, false)
	return root
