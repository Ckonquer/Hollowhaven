extends RefCounted
## Ashbell Quarry art: shared materials and cached, merged, vertex-coloured meshes (storybook: soft, rounded,
## chunky). Pieces are appended to NodeVisuals.Merger batches so the district draws in a handful of calls.
##   var m := NodeVisuals.Merger.new(); QV.add_block(m, xf, Vector3(2, 1.4, 1.4), 3, QV.stone_fn(floor_y))
## Harvest visuals (resource_node.gd custom visuals with collider metadata): iron_vein(seed), moon_seam(seed).

const Q := preload("res://data/reach_east.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")

static var _cache: Dictionary = {}


# --- Materials ------------------------------------------------------------------------------------------

static func stone_material() -> Material:
	return NV.rock_material(0.03)


static func wood_material() -> Material:
	return NV.bark_material()


static func metal_material() -> Material:
	if not _cache.has("mat_metal"):
		_cache["mat_metal"] = Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "specular": 0.6, "rim": 0.45, "noise": 0.05}), 0.016)
	return _cache["mat_metal"]


static func crystal_material() -> Material:
	if not _cache.has("mat_crystal"):
		var m := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Q.COL_CRYSTAL, "emission_energy": 0.75, "specular": 0.8, "rim": 0.8})
		_cache["mat_crystal"] = Mat.outlined(m, 0.014)
	return _cache["mat_crystal"]


static func cloth_material() -> Material:
	if not _cache.has("mat_cloth"):
		_cache["mat_cloth"] = Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.2, "noise": 0.04})
	return _cache["mat_cloth"]


static func glow_material(color: Color = Q.LAMP_GLOW, energy: float = 2.4) -> Material:
	return Mat.glow(color, energy)


## Copper-red stone gradient: darker low, warm light on top faces; height measured from the quarry floor.
static func stone_fn(floor_y: float, base: Color = Q.COL_ROCK) -> Callable:
	return func(p: Vector3, n: Vector3) -> Color:
		var t := clampf((p.y - floor_y) / 8.0, 0.0, 1.0)
		var c := Q.COL_ROCK_DARK.lerp(base, 0.55 + t * 0.45)
		if n.y > 0.55:
			c = c.lerp(Q.COL_ROCK_LIGHT, clampf((n.y - 0.55) * 2.0, 0.0, 1.0) * 0.6)
		var s := sin(p.x * 1.7 + p.z * 1.3) * 0.5 + 0.5
		return c.lerp(c.darkened(0.12), s * 0.35)


# --- Primitive helpers ------------------------------------------------------------------------------------

static func _scaled(xf: Transform3D, size: Vector3) -> Transform3D:
	return Transform3D(xf.basis * Basis.from_scale(size), xf.origin)


## A rounded stone block of `size` (x along the basis x) centred at xf.origin.
static func add_block(m: NV.Merger, xf: Transform3D, size: Vector3, variant: int, col: Variant) -> void:
	m.add(Kit.blob_mesh(0.5, 9100 + posmod(variant, 5), 0.15, 1.0, 2), _scaled(xf, size), col)


## A soft boulder of radius r (squashed), centred at pos.
static func add_boulder(m: NV.Merger, pos: Vector3, r: float, variant: int, yaw: float, col: Variant, squash: float = 0.75) -> void:
	var b := Basis(Vector3.UP, yaw)
	m.add(NV.ublob(variant, 0.28, squash, 2), Transform3D(b * Basis.from_scale(Vector3(r, r, r)), pos), col)


## A cylinder from a to b (beams, posts, chains, braces).
static func add_rod(m: NV.Merger, a: Vector3, b: Vector3, r: float, col: Variant, seg: int = 8) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	m.add(NV._cyl(r, r, l, seg), Transform3D(Basis(x, y, z), (a + b) * 0.5), col)


static func add_box(m: NV.Merger, xf: Transform3D, size: Vector3, col: Variant) -> void:
	m.add(NV._box(Vector3.ONE), _scaled(xf, size), col)


## A festival bronze bell (hangs from its top at xf.origin), `s` = overall scale (1 = 0.6 m tall).
static func add_bell(m: NV.Merger, xf: Transform3D, s: float, col: Color = Q.COL_BRONZE) -> void:
	var b := xf.basis * Basis.from_scale(Vector3(s, s, s))
	var o := xf.origin
	m.add(NV._cyl(0.02, 0.02, 0.12, 6), Transform3D(b, o + b * Vector3(0, -0.06, 0)), col.darkened(0.3))
	m.add(NV._hemi(0.15, 0.13, 10), Transform3D(b, o + b * Vector3(0, -0.2, 0)), col.lightened(0.08))
	m.add(NV._cyl(0.15, 0.27, 0.36, 12), Transform3D(b, o + b * Vector3(0, -0.38, 0)), col)
	m.add(NV._cyl(0.3, 0.3, 0.05, 12), Transform3D(b, o + b * Vector3(0, -0.57, 0)), col.darkened(0.12))
	m.add(NV._sph(0.07, 5, 8), Transform3D(b, o + b * Vector3(0, -0.6, 0)), col.darkened(0.35))


## A round festival pumpkin sitting at pos (s = radius-ish scale, 1 = 0.35 m).
static func add_pumpkin(m: NV.Merger, pos: Vector3, s: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var body := Color("e58a3a")
	for i in 6:
		var a := TAU * float(i) / 6.0
		var off := Vector3(cos(a), 0, sin(a)) * 0.13 * s
		m.add(NV._sph(0.22 * s, 6, 10), Transform3D(b * Basis.from_scale(Vector3(1.0, 0.85, 1.0)), pos + b * off + Vector3(0, 0.2 * s, 0)), body.lerp(Color("f2a54e"), float(i % 2) * 0.35))
	m.add(NV._cyl(0.03 * s, 0.045 * s, 0.14 * s, 6), Transform3D(b * Basis(Vector3.RIGHT, 0.25), pos + Vector3(0, 0.42 * s, 0)), Color("6b5a2e"))


## A short ribbon streamer (two soft triangles) hanging from pos along -Y.
static func add_ribbon(m: NV.Merger, pos: Vector3, yaw: float, length: float, col: Color) -> void:
	var r := Basis(Vector3.UP, yaw)
	var a := pos + r * Vector3(-0.05, 0, 0)
	var b := pos + r * Vector3(0.05, 0, 0)
	var t1 := pos + r * Vector3(-0.07, -length, 0.03)
	var t2 := pos + r * Vector3(0.09, -length * 0.85, -0.02)
	var n := r * Vector3.BACK
	m.tri(a, b, t1, n, col, col, col.darkened(0.15), true)
	m.tri(b, t2, t1, n, col, col.darkened(0.1), col.darkened(0.15), true)


## A wooden lantern post with a warm glass lantern (glass drawn separately: returns the lantern centre).
static func add_lantern_post(m: NV.Merger, base: Vector3, yaw: float) -> Vector3:
	var b := Basis(Vector3.UP, yaw)
	add_rod(m, base + Vector3(0, -0.2, 0), base + Vector3(0, 2.4, 0), 0.08, Palette.WOOD_DARK)
	add_rod(m, base + Vector3(0, 2.3, 0), base + Vector3(0, 2.3, 0) + b * Vector3(0.5, 0, 0), 0.05, Palette.WOOD_DARK)
	var hook := base + Vector3(0, 2.3, 0) + b * Vector3(0.45, 0, 0)
	m.add(NV._cyl(0.02, 0.2, 0.14, 8), Transform3D(Basis(), hook + Vector3(0, -0.12, 0)), Q.COL_IRON)
	m.add(NV._cyl(0.17, 0.17, 0.05, 8), Transform3D(Basis(), hook + Vector3(0, -0.5, 0)), Q.COL_IRON)
	add_ribbon(m, base + Vector3(0, 2.2, 0.09), yaw, 0.6, Q.COL_RIBBON_A)
	return hook + Vector3(0, -0.33, 0)


static func add_crate(m: NV.Merger, pos: Vector3, yaw: float, s: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	add_box(m, Transform3D(b, pos + Vector3(0, 0.3 * s, 0)), Vector3(0.62, 0.6, 0.62) * s, Palette.WOOD)
	for k in [-1.0, 1.0]:
		add_box(m, Transform3D(b, pos + b * Vector3(0, 0.3 * s, float(k) * 0.315 * s)), Vector3(0.66, 0.1, 0.03) * s, Palette.WOOD_DARK)


# --- Harvest visuals ------------------------------------------------------------------------------------------

static func _meta(root: Node3D, convex: Shape3D, ir: float, iy: float, fxh: float) -> void:
	root.set_meta("solid", "convex")
	root.set_meta("convex", convex)
	root.set_meta("interact_radius", ir)
	root.set_meta("interact_y", iy)
	root.set_meta("fx_height", fxh)


## Iron vein: a copper-red rock with dark steel-blue nuggets and a little bronze "ore marker" bell on a stake.
static func iron_vein(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "iron|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 9300 + variant
		var rock := NV.Merger.new()
		var fn := func(p: Vector3, n: Vector3) -> Color:
			var c := Q.COL_ROCK_DARK.lerp(Q.COL_ROCK, clampf(p.y * 1.1 + 0.45, 0.0, 1.0))
			return c.lerp(Q.COL_ROCK_LIGHT, clampf((n.y - 0.6) * 2.0, 0.0, 1.0) * 0.5)
		rock.add(Kit.blob_mesh(0.9, 9310 + variant, 0.3, 0.8, 3), Transform3D(Basis(), Vector3(0, 0.42, 0)), fn)
		var ore := NV.Merger.new()
		for i in 8:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.15, 1.0), rng.randf_range(-1, 1)).normalized()
			var p := Vector3(0, 0.42, 0) + Vector3(dir.x * 0.8, dir.y * 0.62, dir.z * 0.8)
			var c := Q.COL_IRON.lerp(Color("8fa0b8"), rng.randf() * 0.5)
			ore.add(Kit.blob_mesh(rng.randf_range(0.11, 0.19), 9320 + i, 0.35, 0.75, 1), Transform3D(Basis(), p), c)
		# the bell-shaped ore marker: a stake, a tiny bell and a ribbon (quarry custom: a bell for every seam)
		var mk := NV.Merger.new()
		var sp := Vector3(0.95, 0.0, 0.35)
		add_rod(mk, sp + Vector3(0, -0.1, 0), sp + Vector3(0, 1.35, 0), 0.04, Palette.WOOD_DARK)
		add_rod(mk, sp + Vector3(0, 1.3, 0), sp + Vector3(-0.28, 1.3, 0), 0.03, Palette.WOOD_DARK)
		add_bell(mk, Transform3D(Basis(), sp + Vector3(-0.26, 1.28, 0)), 0.42)
		add_ribbon(mk, sp + Vector3(0, 1.22, 0.05), 0.3, 0.42, Q.COL_RIBBON_A if variant != 1 else Q.COL_RIBBON_B)
		var rm := rock.commit()
		_cache[key] = [rm, ore.commit(), mk.commit(), NV.convex_from_points(rm)]
	var parts: Array = _cache[key]
	var root := Node3D.new()
	root.add_child(NV._mi(parts[0], stone_material(), "Rock"))
	var glint := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Color("7f93b8"), "emission_energy": 0.25, "specular": 0.8, "rim": 0.55})
	root.add_child(NV._mi(parts[1], Mat.outlined(glint, 0.012), "Ore"))
	var marker := NV._mi(parts[2], metal_material(), "Marker")
	root.add_child(marker)
	_meta(root, parts[3], 1.25, 0.5, 0.75)
	return root


## Moon Crystal seam: pale blue-white prisms growing from a rose-grey shelf rock.
static func moon_seam(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "moon|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 9400 + variant
		var base := NV.Merger.new()
		var bfn := func(p: Vector3, _n: Vector3) -> Color:
			return Q.COL_SHELF.darkened(0.35).lerp(Q.COL_SHELF, clampf(p.y * 1.4 + 0.4, 0.0, 1.0))
		base.add(Kit.blob_mesh(0.7, 9410 + variant, 0.3, 0.55, 2), Transform3D(Basis(), Vector3(0, 0.12, 0)), bfn)
		var cr := NV.Merger.new()
		for i in 7:
			var h := rng.randf_range(0.55, 1.2) * (1.45 if i == 0 else 1.0)
			var r := rng.randf_range(0.09, 0.16) * (1.35 if i == 0 else 1.0)
			var tilt := 0.0 if i == 0 else rng.randf_range(0.25, 0.75)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
			var c := Q.COL_CRYSTAL.lerp(Color("ffffff"), rng.randf() * 0.4)
			var fn := func(p: Vector3, _n: Vector3) -> Color:
				return Q.COL_CRYSTAL_DEEP.lerp(c, clampf(p.y / 1.3 + 0.2, 0.0, 1.0))
			cr.add(NV._cyl(r, r, h, 6), Transform3D(b, b * Vector3(0, h * 0.5, 0) + Vector3(0, 0.12, 0)), fn)
			cr.add(NV._cyl(0.0, r, r * 1.9, 6), Transform3D(b, b * Vector3(0, h + r * 0.95, 0) + Vector3(0, 0.12, 0)), c.lightened(0.2))
		var cm := cr.commit()
		_cache[key] = [base.commit(), cm, NV.convex_from_points(cm)]
	var parts: Array = _cache[key]
	var root := Node3D.new()
	root.add_child(NV._mi(parts[0], stone_material(), "Base"))
	root.add_child(NV._mi(parts[1], crystal_material(), "Crystal"))
	_meta(root, parts[2], 1.1, 0.6, 0.9)
	return root
