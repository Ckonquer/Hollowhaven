extends RefCounted
## Autumn plant and harvest visuals of Hallowmere Reach (cached, merged, vertex-coloured meshes sharing the
## NodeVisuals materials). Everything returns shared meshes, so hundreds of trees cost a handful of meshes.
##   tree_parts(species, variant) -> {"trunk", "crown", "stump", "trunk_radius", "height", "crown_y"}
##   tree_visual(species, variant) -> Node3D for resource_node.gd (children "Top" + "Stump", metadata)
##   species: amber (oak), copper (maple), ember (red maple), gold (birch), pine (evergreen contrast)
##   leaf_patch_mesh(v), pumpkin_mesh(v), bush_mesh(v), tuft_visual(seed), stick_visual(seed), iron_seam_visual(seed)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")

const SPECIES := ["amber", "copper", "ember", "gold", "pine"]
const TREE_NAMES := {"amber": "Amber Oak", "copper": "Copper Maple", "ember": "Ember Maple", "gold": "Golden Birch", "pine": "Pine Tree"}
## [crown low, crown high, accent patches]
const CROWNS := {
	"amber": [Color("b8621f"), Color("f2b54a"), Color("d9832c")],
	"copper": [Color("9a4224"), Color("e58a3c"), Color("f2c14e")],
	"ember": [Color("7a2427"), Color("d9543e"), Color("f08a3c")],
	"gold": [Color("b88b25"), Color("f5d862"), Color("e9a13b")],
}
const BIRCH_BARK := Color("efe7d4")
const BIRCH_MARK := Color("4f4340")
const LEAF_COLORS := [Color("e9923a"), Color("d9543e"), Color("f2c14e"), Color("b8662f"), Color("9e3a2e")]
const PUMPKINS := [Color("ee8a2a"), Color("f3e3c2"), Color("d4602a"), Color("e9a13b")]

static var _cache: Dictionary = {}


static func tree_parts(species: String, variant: int) -> Dictionary:
	variant = posmod(variant, 3)
	if species == "pine" or not CROWNS.has(species):
		return NodeVisuals.tree_parts("pine" if species == "pine" else "oak", variant)
	var key := "rtree|%s|%d" % [species, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var cols: Array = CROWNS[species]
	var d: Dictionary
	match species:
		"gold":
			d = _birch(rng, cols)
		"copper", "ember":
			d = _broadleaf(rng, rng.randf_range(0.3, 0.36), rng.randf_range(2.0, 2.4), 1.75, 7, cols, 0.8, Palette.BARK_DARK, Palette.BARK)
		_:
			d = _broadleaf(rng, rng.randf_range(0.36, 0.43), rng.randf_range(2.3, 2.8), 1.6, 6, cols, 0.9, Palette.BARK_DARK, Palette.BARK)
	d["stump"] = NodeVisuals._stump_mesh(float(d["trunk_radius"]), species == "gold")
	_cache[key] = d
	return d


static func _crown_fn(cols: Array, y0: float, y1: float, crown_r: float, seed_value: int) -> Callable:
	var lo: Color = cols[0]
	var hi: Color = cols[1]
	var acc: Color = cols[2]
	var nz := FastNoiseLite.new()
	nz.seed = seed_value
	nz.frequency = 0.9
	return func(p: Vector3, n: Vector3) -> Color:
		var t := clampf((p.y - y0) / (y1 - y0), 0.0, 1.0)
		var c := lo.lerp(hi, t * t * 0.4 + t * 0.6)
		var patch := nz.get_noise_3dv(p)
		if patch > 0.25:
			c = c.lerp(acc, clampf((patch - 0.25) * 2.5, 0.0, 0.7))
		var inner := clampf(Vector2(p.x, p.z).length() / (crown_r * 1.6), 0.0, 1.0)
		c = c.darkened((1.0 - inner) * 0.16 * (1.0 - t))
		return c.lerp(Color("fff0c8"), clampf(n.y, 0.0, 1.0) * 0.08 * t)


static func _broadleaf(rng: RandomNumberGenerator, r0: float, trunk_h: float, crown_r: float, n_blobs: int, cols: Array, squash: float, bark_lo: Color, bark_hi: Color) -> Dictionary:
	var tr := NodeVisuals.Merger.new()
	var th := trunk_h + crown_r * 0.6
	var bark_fn := func(p: Vector3, _n: Vector3) -> Color:
		return bark_lo.lerp(bark_hi, clampf(p.y / th, 0.0, 1.0))
	tr.add(NodeVisuals._cyl(r0 * 0.6, r0, th, 10, 2), Transform3D(Basis(), Vector3(0, th * 0.5, 0)), bark_fn)
	for i in 4:
		var a := TAU * float(i) / 4.0 + rng.randf() * 0.6
		tr.add(NodeVisuals.ublob(i, 0.25, 0.55, 1), NodeVisuals.sxf(r0 * 0.62, Vector3(cos(a) * r0 * 0.75, 0.1, sin(a) * r0 * 0.75)), bark_lo)
	for i in 3:
		var a := rng.randf() * TAU
		var b := Basis(Vector3.UP, a) * Basis(Vector3.BACK, deg_to_rad(rng.randf_range(38.0, 58.0)))
		var start := Vector3(0, trunk_h * rng.randf_range(0.6, 0.85), 0)
		tr.add(NodeVisuals._cyl(r0 * 0.12, r0 * 0.34, 1.3, 7), Transform3D(b, start + b * Vector3(0, 0.62, 0)), bark_hi)
	var cr := NodeVisuals.Merger.new()
	var cy := trunk_h + crown_r * 0.72
	var y0 := cy - crown_r * 1.05
	var y1 := cy + crown_r * 1.35
	var fn := _crown_fn(cols, y0, y1, crown_r, rng.randi())
	var blobs: Array = [[Vector3(0, cy, 0), crown_r * 1.05, 3]]
	for i in n_blobs:
		var a := TAU * float(i) / float(n_blobs) + rng.randf_range(-0.3, 0.3)
		var rr := crown_r * rng.randf_range(0.6, 0.8)
		var off := Vector3(cos(a) * crown_r * 0.9, rng.randf_range(-0.35, 0.2) * crown_r, sin(a) * crown_r * 0.9)
		blobs.append([Vector3(0, cy, 0) + off, rr, 2])
	blobs.append([Vector3(rng.randf_range(-0.3, 0.3), cy + crown_r * 0.72, rng.randf_range(-0.3, 0.3)), crown_r * 0.72, 2])
	for b in blobs:
		var s := float(b[1])
		var xf := Transform3D(Basis().scaled(Vector3(s, s * squash, s)), b[0])
		cr.add(NodeVisuals.ublob(rng.randi_range(1, 9999), 0.22, 0.86, int(b[2])), xf, fn)
	return {"trunk": tr.commit(), "crown": cr.commit(), "trunk_radius": r0, "height": y1, "crown_y": cy}


static func _birch(rng: RandomNumberGenerator, cols: Array) -> Dictionary:
	var r0 := rng.randf_range(0.2, 0.24)
	var trunk_h := rng.randf_range(4.2, 4.8)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var tr := NodeVisuals.Merger.new()
	var bark_fn := func(p: Vector3, _n: Vector3) -> Color:
		var m := noise.get_noise_3d(p.x * 2.0, p.y * 3.0, p.z * 2.0)
		return BIRCH_MARK if m > 0.22 and p.y > 0.3 else BIRCH_BARK.darkened(0.05 if p.y < 0.4 else 0.0)
	tr.add(NodeVisuals._cyl(r0 * 0.6, r0, trunk_h, 10, 12), Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0)), bark_fn)
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf()
		tr.add(NodeVisuals.ublob(i + 5, 0.25, 0.55, 1), NodeVisuals.sxf(r0 * 0.7, Vector3(cos(a) * r0 * 0.7, 0.08, sin(a) * r0 * 0.7)), BIRCH_BARK.darkened(0.12))
	var cr := NodeVisuals.Merger.new()
	var y0 := trunk_h - 1.5
	var y1 := trunk_h + 2.4
	var fn := _crown_fn(cols, y0, y1, 1.0, rng.randi())
	for i in 5:
		var t := float(i) / 4.0
		var cy := lerpf(trunk_h - 0.6, trunk_h + 1.6, t)
		var rr := lerpf(0.95, 0.55, t) * rng.randf_range(0.9, 1.1)
		var off := Vector3(rng.randf_range(-0.75, 0.75), 0.0, rng.randf_range(-0.75, 0.75)) * (1.0 - t * 0.5)
		cr.add(NodeVisuals.ublob(rng.randi_range(1, 9999), 0.3, 0.9, 2), NodeVisuals.sxf(rr, Vector3(0, cy, 0) + off), fn)
	return {"trunk": tr.commit(), "crown": cr.commit(), "trunk_radius": r0, "height": y1, "crown_y": trunk_h + 0.4}


static func crown_material(species: String) -> ShaderMaterial:
	match species:
		"pine":
			return NodeVisuals.crown_material("pine")
		"gold":
			return NodeVisuals.crown_material("birch")
	return NodeVisuals.crown_material("oak")


## A resource-node visual (same structure and metadata as NodeVisuals' trees).
static func tree_visual(species: String, variant: int) -> Node3D:
	var parts := tree_parts(species, variant)
	var root := Node3D.new()
	var top := Node3D.new()
	top.name = "Top"
	root.add_child(top)
	var trunk := NodeVisuals._mi(parts["trunk"], NodeVisuals.bark_material(), "Trunk")
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top.add_child(trunk)
	top.add_child(NodeVisuals._mi(parts["crown"], crown_material(species), "Crown"))
	var stump := NodeVisuals._mi(parts["stump"], NodeVisuals.bark_material(), "Stump")
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
	NodeVisuals.set_visibility_range(root, 140.0)
	return root


# --- Ground cover ----------------------------------------------------------------------------------

## A little drift of fallen leaves (flat, ~1 m across) in amber, copper, red and gold.
static func leaf_patch_mesh(variant: int) -> ArrayMesh:
	var key := "leaves|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + variant
	var m := NodeVisuals.Merger.new()
	for i in 16:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.55
		var c := Vector3(cos(a) * r, 0.015 + float(i) * 0.002, sin(a) * r)
		var yaw := rng.randf() * TAU
		var fwd := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-fwd.z, 0, fwd.x)
		var ln := rng.randf_range(0.07, 0.11)
		var wd := ln * 0.55
		var col: Color = LEAF_COLORS[rng.randi() % LEAF_COLORS.size()]
		var tip := c + fwd * ln
		var tail := c - fwd * ln
		m.tri(tail, c - side * wd + Vector3(0, 0.01, 0), tip, Vector3.UP, col.darkened(0.1), col, col.lightened(0.05), true)
		m.tri(tail, tip, c + side * wd + Vector3(0, 0.01, 0), Vector3.UP, col.darkened(0.1), col.lightened(0.05), col, true)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## Round storybook pumpkin (ribbed blob ring + stem). variant: 0 orange, 1 cream, 2 deep orange, 3 gold.
static func pumpkin_mesh(variant: int) -> ArrayMesh:
	variant = posmod(variant, PUMPKINS.size())
	var key := "pumpkin|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NodeVisuals.Merger.new()
	var base: Color = PUMPKINS[variant]
	var fn := func(p: Vector3, n: Vector3) -> Color:
		return base.darkened(0.18).lerp(base.lightened(0.08), clampf(n.y * 0.5 + 0.5, 0.0, 1.0))
	for i in 8:
		var a := TAU * float(i) / 8.0
		var b := Basis(Vector3.UP, -a)
		m.add(NodeVisuals._sph(0.26, 6, 10), Transform3D(b * Basis.from_scale(Vector3(0.62, 0.78, 1.0)), b * Vector3(0.0, 0.26, 0.14)), fn)
	m.add(NodeVisuals._sph(0.24, 6, 10), Transform3D(Basis().scaled(Vector3(1.0, 0.95, 1.0)), Vector3(0, 0.27, 0)), base.darkened(0.1))
	var stem_b := Basis(Vector3.BACK, 0.25)
	m.add(NodeVisuals._cyl(0.025, 0.045, 0.16, 6), Transform3D(stem_b, Vector3(0.01, 0.52, 0)), Color("6b5a2c"))
	m.add(Kit.blob_mesh(0.06, 7790 + variant, 0.3, 0.4, 1), Transform3D(Basis(), Vector3(0.07, 0.5, 0.03)), Color("6f8a3a"))
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


static func bush_mesh(variant: int) -> ArrayMesh:
	match posmod(variant, 3):
		0:
			return NodeVisuals.bush_mesh(0, Color("8a3a2a"), Color("d9683c"))
		1:
			return NodeVisuals.bush_mesh(1, Color("8e6a24"), Color("e0b64a"))
	return NodeVisuals.bush_mesh(2, Color("5e2f45"), Color("b0485a"))


## Harvestable tall grass (fiber) with straw-gold autumn blades and seed heads.
static func tuft_visual(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "tuft|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7800 + variant
		var m := NodeVisuals.Merger.new()
		var base_c := Color("8a7a3a")
		var tip_c := Color("f0cf7a")
		for i in 16:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 0.2)
			var root_p := Vector3(cos(a) * r, 0.0, sin(a) * r)
			var hgt := rng.randf_range(0.55, 0.95)
			var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.35)
			var side := Vector3(-sin(a), 0, cos(a)) * rng.randf_range(0.045, 0.07)
			var mid := root_p + lean * 0.4 + Vector3(0, hgt * 0.55, 0)
			var tip := root_p + lean + Vector3(0, hgt, 0)
			var n := (Vector3.UP + Vector3(cos(a), 0, sin(a)) * 0.6).normalized()
			var cm := base_c.lerp(tip_c, 0.5)
			m.tri(root_p - side, mid - side * 0.7, root_p + side, n, base_c, cm, base_c, true)
			m.tri(root_p + side, mid - side * 0.7, mid + side * 0.7, n, base_c, cm, cm, true)
			m.tri(mid - side * 0.7, tip, mid + side * 0.7, n, cm, tip_c, cm, true)
		for i in 5:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a) * 0.18, rng.randf_range(0.8, 1.0), sin(a) * 0.18)
			m.add(NodeVisuals._sph(0.045, 4, 6), Transform3D(Basis().scaled(Vector3(1, 1.8, 1)), p), Color("d98f4a"))
		_cache[key] = m.commit()
	var root := Node3D.new()
	root.add_child(NodeVisuals._mi(_cache[key], NodeVisuals.foliage_material(0.07, 0.9, 0.0, 0.35), "Blades"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.6)
	root.set_meta("interact_y", 0.4)
	root.set_meta("fx_height", 0.5)
	NodeVisuals.set_visibility_range(root, 75.0, false)
	return root


## A fallen stick with a few autumn leaves still on it.
static func stick_visual(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 3)
	var key := "stick|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7900 + variant
		var m := NodeVisuals.Merger.new()
		var length := rng.randf_range(0.8, 1.0)
		var along := Basis(Vector3.BACK, deg_to_rad(90.0))
		var bark_fn := func(_p: Vector3, n: Vector3) -> Color:
			return Palette.BARK.lerp(Palette.WOOD, clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 0.6)
		m.add(NodeVisuals._cyl(0.05, 0.065, length, 7), Transform3D(along, Vector3(0, 0.065, 0)), bark_fn)
		m.add(NodeVisuals._cyl(0.058, 0.058, 0.02, 7), Transform3D(along, Vector3(length * 0.5 + 0.005, 0.065, 0)), Palette.WOOD_LIGHT)
		var tb := Basis(Vector3.UP, deg_to_rad(40.0)) * along
		m.add(NodeVisuals._cyl(0.022, 0.035, 0.38, 6), Transform3D(tb, Vector3(0.12, 0.07, -0.12)), bark_fn)
		m.add(Kit.blob_mesh(0.07, 7950 + variant, 0.2, 0.35, 1), Transform3D(Basis(), Vector3(0.28, 0.09, -0.26)), LEAF_COLORS[variant])
		m.add(Kit.blob_mesh(0.06, 7960 + variant, 0.2, 0.35, 1), Transform3D(Basis(), Vector3(-0.3, 0.1, 0.08)), LEAF_COLORS[variant + 1])
		_cache[key] = m.commit()
	var root := Node3D.new()
	root.add_child(NodeVisuals._mi(_cache[key], NodeVisuals.rock_material(0.016), "Stick"))
	root.set_meta("solid", "none")
	root.set_meta("interact_radius", 0.6)
	root.set_meta("interact_y", 0.25)
	root.set_meta("fx_height", 0.2)
	NodeVisuals.set_visibility_range(root, 70.0, false)
	return root


## An iron seam: a dark rust-streaked rock with grey-blue iron nubs (the Conservatory practice seam).
static func iron_seam_visual(seed_value: int) -> Node3D:
	var variant := posmod(seed_value, 2)
	var key := "iron|%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 8000 + variant
		var rock := NodeVisuals.Merger.new()
		var dark := Color("5d5552")
		var rock_fn := func(p: Vector3, n: Vector3) -> Color:
			var c := dark.darkened(0.2).lerp(Color("8a7f78"), clampf(p.y * 1.1 + 0.4, 0.0, 1.0))
			if n.y < 0.3:
				c = c.lerp(Color("9a5a3a"), 0.25)
			return c
		rock.add(Kit.blob_mesh(0.9, 8010 + variant, 0.3, 0.8, 3), Transform3D(Basis(), Vector3(0, 0.45, 0)), rock_fn)
		var nug := NodeVisuals.Merger.new()
		for i in 8:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1.0), rng.randf_range(-1, 1)).normalized()
			var p := Vector3(0, 0.45, 0) + Vector3(dir.x * 0.82, dir.y * 0.66, dir.z * 0.82)
			nug.add(Kit.blob_mesh(rng.randf_range(0.1, 0.16), 8020 + i, 0.35, 0.8, 1), Transform3D(Basis(), p), Color("7f8aa0").lerp(Color("c9d2e2"), rng.randf() * 0.4))
		var rm := rock.commit()
		_cache[key] = [rm, nug.commit(), NodeVisuals.convex_from_points(rm)]
	var parts: Array = _cache[key]
	var root := Node3D.new()
	root.add_child(NodeVisuals._mi(parts[0], NodeVisuals.rock_material(), "Rock"))
	var glint := Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Color("aab8d8"), "emission_energy": 0.25, "specular": 0.8, "rim": 0.6})
	root.add_child(NodeVisuals._mi(parts[1], Mat.outlined(glint, 0.012), "Ore"))
	root.set_meta("solid", "convex")
	root.set_meta("convex", parts[2])
	root.set_meta("interact_radius", 1.25)
	root.set_meta("interact_y", 0.5)
	root.set_meta("fx_height", 0.7)
	return root
