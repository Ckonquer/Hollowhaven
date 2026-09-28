extends RefCounted
## Crop visuals: a log-framed bed of tilled soil with three mounded rows (crop_plot), a raised Sturdy Planter
## box (sturdy_planter), and one merged mesh per crop and growth stage (0 sprout, 1 leaves, 2 bushy, 3 ripe).
## Plants are drawn with one MultiMeshInstance3D per plot (1 draw call) and sway with the toon shader's wind.
## Crops (data/structures.gd CROPS): sweetroot (legacy: 9 leafy roots), sunflax (9 slim stalks turning gold with
## blue flax flowers), roseberry (4 round bushes with rosy berries), pumpkin (1 sprawling vine with a big
## ribbed pumpkin). `plants` / `tint` come from the crop data; every stage mesh is baked once per process.

const Palette := preload("res://src/art/palette.gd")
const U := preload("res://src/building/model_util.gd")
const Batch := preload("res://src/building/batch.gd")
const Shapes := preload("res://src/building/shapes.gd")

const ROWS := [-0.55, 0.0, 0.55]
const COLS := [-0.55, 0.0, 0.55]
const SOIL_TOP := 0.18
## Soil surface of the Sturdy Planter (2 x 1 m raised box, data height 0.6).
const PLANTER_SOIL_TOP := 0.46
const PLANTER_RIM := 0.56

static var ROOT_ORANGE: Color = Color("f29a4a")     # matches the sweetroot item colour
static var SOIL: Color = Palette.DIRT_DARK.darkened(0.12)


static func plot(root: Node3D) -> Dictionary:
	var mesh := U.baked("crop_plot", func(b: Batch) -> void:
		for sz in [-1.0, 1.0]:
			b.rbox(Vector3(2.0, 0.17, 0.13), Vector3(0, 0.085, 0.935 * sz), Palette.WOOD, 0.05)
			b.rbox(Vector3(0.13, 0.17, 1.74), Vector3(0.935 * sz, 0.085, 0), Palette.WOOD.darkened(0.05), 0.05)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.cyl(0.07, 0.08, 0.26, Vector3(0.94 * sx, 0.13, 0.94 * sz), Palette.WOOD_DARK, Vector3.ZERO, 8)
				b.sphere(0.07, Vector3(0.94 * sx, 0.26, 0.94 * sz), Palette.WOOD_LIGHT, Vector3(1, 0.5, 1))
		b.rbox(Vector3(1.78, 0.12, 1.78), Vector3(0, 0.07, 0), Palette.DIRT_DARK, 0.03)
		for z in ROWS:
			b.rbox(Vector3(1.62, 0.1, 0.34), Vector3(0, 0.13, z), SOIL, 0.05)
		# tiny pebbles in the soil
		for p in [Vector3(-0.7, 0.14, -0.28), Vector3(0.62, 0.14, 0.27), Vector3(0.2, 0.14, -0.3)]:
			b.sphere(0.025, p, Palette.STONE, Vector3(1.2, 0.6, 1))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


## Sturdy Planter: a raised 2 x 1 m plank box on stout feet, soil surface at PLANTER_SOIL_TOP.
static func planter(root: Node3D) -> Dictionary:
	var mesh := U.baked("sturdy_planter", func(b: Batch) -> void:
		var wood := Palette.WOOD.darkened(0.04)
		for sz in [-1.0, 1.0]:
			b.rbox(Vector3(1.9, 0.42, 0.1), Vector3(0, 0.33, 0.43 * sz), wood, 0.03)
			b.rbox(Vector3(1.96, 0.06, 0.14), Vector3(0, PLANTER_RIM - 0.03, 0.43 * sz), Palette.WOOD_LIGHT, 0.025)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.1, 0.42, 0.8), Vector3(0.93 * sx, 0.33, 0), wood.darkened(0.05), 0.03)
			b.rbox(Vector3(0.14, 0.06, 0.94), Vector3(0.91 * sx, PLANTER_RIM - 0.03, 0), Palette.WOOD_LIGHT, 0.025)
			for sz in [-1.0, 1.0]:
				b.rbox(Vector3(0.14, 0.16, 0.14), Vector3(0.86 * sx, 0.08, 0.38 * sz), Palette.WOOD_DARK, 0.03)
		# plank seams
		for x in [-0.5, 0.0, 0.5]:
			for sz in [-1.0, 1.0]:
				b.rbox(Vector3(0.02, 0.36, 0.02), Vector3(x, 0.33, 0.482 * sz), Palette.WOOD_DARK, 0.005)
		b.rbox(Vector3(1.78, 0.08, 0.78), Vector3(0, PLANTER_SOIL_TOP - 0.04, 0), SOIL, 0.03)
		for x in [-0.6, 0.0, 0.6]:
			b.sphere(0.2, Vector3(x, PLANTER_SOIL_TOP - 0.02, 0), SOIL.lightened(0.05), Vector3(1.4, 0.18, 1.6))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


## Soil height plants stand on for a farm structure.
static func soil_top(structure_id: String) -> float:
	return PLANTER_SOIL_TOP if structure_id == "sturdy_planter" else SOIL_TOP


## Plant positions (local to the plot) of the legacy 3 x 3 layout.
static func plant_positions() -> Array:
	var out: Array = []
	for z in ROWS:
		for x in COLS:
			out.append(Vector3(float(x), SOIL_TOP, float(z)))
	return out


## Plants shown for a crop (data `plants`; the legacy sweetroot shows 9).
static func plants_for(crop: String) -> int:
	return clampi(int(ItemDB.crop(crop).get("plants", 9)), 1, 9)


## Plant positions for `crop` on a farm structure: the crop plot (2 x 2 m) keeps the legacy 3 x 3 grid for
## 9-plant crops, a 2 x 2 grid for 4 and the centre for 1; the Sturdy Planter (2 x 1 m) holds 6 / 2 / 1.
static func plant_layout(structure_id: String, crop: String) -> Array:
	var n := plants_for(crop)
	var y := soil_top(structure_id)
	var out: Array = []
	if structure_id == "sturdy_planter":
		if n >= 9:
			for z in [-0.2, 0.2]:
				for x in [-0.6, 0.0, 0.6]:
					out.append(Vector3(x, y, z))
		elif n >= 4:
			out = [Vector3(-0.45, y, 0.0), Vector3(0.45, y, 0.0)]
		else:
			out = [Vector3(0.0, y, 0.0)]
		return out
	if n >= 9:
		return plant_positions()
	if n >= 4:
		for z in [-0.42, 0.42]:
			for x in [-0.42, 0.42]:
				out.append(Vector3(x, y, z))
		return out
	return [Vector3(0.0, y, 0.0)]


## Scale applied to every plant of `crop` on this structure (big pumpkins shrink to fit the narrow planter).
static func plant_scale(structure_id: String, crop: String) -> float:
	if structure_id == "sturdy_planter" and plants_for(crop) < 4:
		return 0.62
	if structure_id == "sturdy_planter" and plants_for(crop) < 9:
		return 0.85
	return 1.0


static func _tint(crop: String, fallback: Color) -> Color:
	var c: Variant = ItemDB.crop(crop).get("tint", fallback)
	return c if c is Color else fallback


## Merged mesh of one plant of `crop` at a growth stage (0 sprout .. 3 ripe). The legacy sweetroot keeps its
## original cache key and shapes.
static func stage_mesh(stage: int, crop: String = "sweetroot") -> ArrayMesh:
	var st := clampi(stage, 0, 3)
	match crop:
		"sunflax":
			var tint := _tint(crop, Color("f2cf62"))
			return U.baked("crop_stage_sunflax_%d" % st, func(b: Batch) -> void: _sunflax(b, st, tint))
		"roseberry":
			var tint2 := _tint(crop, Color("e0607e"))
			return U.baked("crop_stage_roseberry_%d" % st, func(b: Batch) -> void: _roseberry(b, st, tint2))
		"pumpkin":
			var tint3 := _tint(crop, Color("f08a2e"))
			return U.baked("crop_stage_pumpkin_%d" % st, func(b: Batch) -> void: _pumpkin(b, st, tint3))
	return U.baked("crop_stage_%d" % st, func(b: Batch) -> void: _sweetroot(b, st))


static func _sweetroot(b: Batch, stage: int) -> void:
	match stage:
		0:
			b.cyl(0.012, 0.016, 0.08, Vector3(0, 0.04, 0), Palette.FOLIAGE, Vector3.ZERO, 6)
			b.sphere(0.5, Vector3(-0.035, 0.085, 0), Palette.FOLIAGE_LIGHT, Vector3(0.07, 0.018, 0.04), Vector3(0, 0, 25))
			b.sphere(0.5, Vector3(0.035, 0.085, 0), Palette.FOLIAGE_LIGHT, Vector3(0.07, 0.018, 0.04), Vector3(0, 0, -25))
		1:
			_fronds(b, 4, 0.17, Palette.FOLIAGE_LIGHT, 0.0)
		2:
			b.sphere(0.045, Vector3(0, 0.0, 0), ROOT_ORANGE.darkened(0.1), Vector3(1, 0.6, 1))
			_fronds(b, 6, 0.24, Palette.FOLIAGE, 0.3)
			_fronds(b, 3, 0.17, Palette.FOLIAGE_LIGHT, 1.1)
		_:
			b.sphere(0.1, Vector3(0, 0.01, 0), ROOT_ORANGE, Vector3(1, 0.85, 1))
			b.sphere(0.035, Vector3(0.06, 0.02, 0.05), ROOT_ORANGE.lightened(0.1))
			for k in 3:
				var a := TAU * float(k) / 3.0
				b.cyl(0.003, 0.003, 0.03, Vector3(cos(a) * 0.08, 0.03, sin(a) * 0.08), ROOT_ORANGE.darkened(0.25), Vector3(0, 0, 90), 4)
			_fronds(b, 7, 0.3, Palette.FOLIAGE, 0.2)
			_fronds(b, 4, 0.22, Palette.FOLIAGE_LIGHT, 0.9)


## Feathery upright leaves arranged in a rosette, each blade leaning outward and facing out.
static func _fronds(b: Batch, count: int, height: float, color: Color, phase: float) -> void:
	for i in count:
		var a := TAU * float(i) / float(count) + phase
		var tilt := deg_to_rad(22.0 + 10.0 * float(i % 2))
		var dir := Vector3(cos(a), 0, sin(a))
		var up := (dir * sin(tilt) + Vector3.UP * cos(tilt)).normalized()
		var side := Vector3(-sin(a), 0, cos(a))
		var face := side.cross(up).normalized()
		var blade := Basis(side * 0.07, up * height, face * 0.028)
		var centre := up * height * 0.5 + dir * 0.02
		var col: Color = color if i % 3 != 0 else color.darkened(0.08)
		b.add(Shapes.prim_sphere(0.5, 5, 8), Transform3D(blade, centre), col)
		var stem := Basis(side, up, face)
		b.add(Shapes.prim_cylinder(0.006, 0.009, height * 0.5, 4), Transform3D(stem, up * height * 0.25), color.darkened(0.2))


# --- Sunflax: slim stalks that turn gold, tipped with seed heads and little blue flax flowers ----------------

static func _sunflax(b: Batch, stage: int, tint: Color) -> void:
	var counts := [2, 4, 6, 7]
	var heights := [0.08, 0.2, 0.34, 0.46]
	var n: int = counts[stage]
	var h: float = heights[stage]
	var green := Palette.FOLIAGE_LIGHT
	var stalk_col: Color = green if stage < 2 else (green.lerp(tint, 0.35) if stage == 2 else tint.darkened(0.12))
	for i in n:
		var a := TAU * float(i) / float(n) + 0.4 * float(i % 2)
		var dir := Vector3(cos(a), 0, sin(a))
		var tilt := deg_to_rad(5.0 + 4.0 * float(i % 3))
		var hh: float = h * (0.86 + 0.07 * float((i * 5) % 3))
		var root := dir * (0.015 + 0.02 * float(i % 2))
		var top := _stalk(b, root, dir, tilt, hh, 0.006 if stage < 2 else 0.008, stalk_col)
		if stage == 0:
			_leaf(b, top, dir, 0.045, green.lightened(0.05))
			continue
		if i % 2 == 0:
			_leaf(b, root + (top - root) * 0.45, dir, 0.06 + 0.02 * float(stage), green.darkened(0.04))
		if stage == 2:
			b.add(Shapes.prim_sphere(0.018, 2, 4), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.5, 1)), top), green.darkened(0.1))
		elif stage == 3:
			if i % 3 == 1:
				_flax_flower(b, top)
			else:
				b.add(Shapes.prim_sphere(0.022, 2, 4), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.6, 1)), top), tint.lightened(0.18))


## A thin stalk from `root` leaning toward `dir` by `tilt`; returns the top point.
static func _stalk(b: Batch, root: Vector3, dir: Vector3, tilt: float, h: float, r: float, col: Color) -> Vector3:
	var axis := Vector3.UP.cross(dir)
	var basis := Basis(axis.normalized(), tilt) if axis.length() > 0.001 else Basis.IDENTITY
	var up := basis * Vector3.UP
	b.add(Shapes.prim_cylinder(r * 0.7, r, h, 4), Transform3D(basis, root + up * h * 0.5), col)
	return root + up * h


## A narrow leaf blade pointing outward/up from `at`.
static func _leaf(b: Batch, at: Vector3, dir: Vector3, length: float, col: Color) -> void:
	var up := (dir * 0.8 + Vector3.UP * 0.6).normalized()
	var side := Vector3.UP.cross(dir).normalized()
	var face := side.cross(up).normalized()
	b.add(Shapes.prim_sphere(0.5, 2, 4), Transform3D(Basis(side * 0.022, up * length, face * 0.01), at + up * length * 0.45), col)


static func _flax_flower(b: Batch, at: Vector3) -> void:
	for k in 3:
		var a := TAU * float(k) / 3.0
		b.add(Shapes.prim_sphere(0.013, 2, 4), Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 0.5, 1.4)), at + Vector3(cos(a), 0.1, sin(a)) * 0.016), Palette.FLOWER_BLUE)
	b.add(Shapes.prim_sphere(0.008, 2, 4), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.006, 0)), Palette.FLOWER_YELLOW)


# --- Roseberry: a round little bush, green berries that blush rosy when ripe -----------------------------------

static func _roseberry(b: Batch, stage: int, tint: Color) -> void:
	var leaf := Palette.FOLIAGE
	if stage == 0:
		b.cyl(0.01, 0.013, 0.07, Vector3(0, 0.035, 0), Palette.BARK, Vector3.ZERO, 5)
		b.add(Shapes.prim_sphere(0.5, 4, 6), Transform3D(Basis.IDENTITY.scaled(Vector3(0.06, 0.02, 0.05)).rotated(Vector3.FORWARD, 0.4), Vector3(-0.03, 0.075, 0)), Palette.FOLIAGE_LIGHT)
		b.add(Shapes.prim_sphere(0.5, 4, 6), Transform3D(Basis.IDENTITY.scaled(Vector3(0.06, 0.02, 0.05)).rotated(Vector3.FORWARD, -0.4), Vector3(0.03, 0.075, 0)), Palette.FOLIAGE_LIGHT)
		return
	var radius: float = [0.0, 0.14, 0.24, 0.3][stage]
	var clumps: int = [0, 4, 6, 7][stage]
	b.cyl(0.018, 0.026, radius * 0.6, Vector3(0, radius * 0.3, 0), Palette.BARK, Vector3.ZERO, 6)
	# leafy clumps around a dome
	for i in clumps:
		var a := TAU * float(i) / float(clumps) + 0.3
		var ring := radius * 0.55
		var p := Vector3(cos(a) * ring, radius * (0.55 + 0.12 * float(i % 2)), sin(a) * ring)
		var col: Color = leaf if i % 3 != 0 else Palette.FOLIAGE_LIGHT
		b.add(Shapes.prim_sphere(radius * 0.5, 5, 8), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.8, 1)), p), col)
	b.add(Shapes.prim_sphere(radius * 0.55, 5, 8), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.85, 1)), Vector3(0, radius * 0.95, 0)), Palette.FOLIAGE_LIGHT)
	if stage < 2:
		return
	var berries := 6 if stage == 2 else 11
	var bcol: Color = Palette.FOLIAGE_LIGHT.lightened(0.15) if stage == 2 else tint
	for k in berries:
		var a2 := TAU * float(k) / float(berries) + 0.17 * float(k % 3)
		var yb := radius * (0.45 + 0.5 * float((k * 7) % 5) / 4.0)
		var rr := radius * (0.95 - 0.35 * absf(yb / radius - 0.7))
		var pos := Vector3(cos(a2) * rr, yb, sin(a2) * rr)
		b.add(Shapes.prim_sphere(0.024 if stage == 3 else 0.017, 3, 6), Transform3D(Basis.IDENTITY, pos), bcol if k % 4 != 0 or stage == 2 else tint.darkened(0.12))


# --- Pumpkin: seed leaves, a sprawling vine, a yellow flower and finally a big ribbed pumpkin ------------------

static func _pumpkin(b: Batch, stage: int, tint: Color) -> void:
	var leaf := Palette.FOLIAGE
	if stage == 0:
		b.cyl(0.012, 0.016, 0.07, Vector3(0, 0.035, 0), Palette.FOLIAGE_DARK, Vector3.ZERO, 5)
		for s in [-1.0, 1.0]:
			b.add(Shapes.prim_sphere(0.5, 4, 7), Transform3D(Basis.IDENTITY.scaled(Vector3(0.1, 0.022, 0.07)).rotated(Vector3.FORWARD, 0.3 * s), Vector3(0.05 * s, 0.075, 0)), Palette.FOLIAGE_LIGHT)
		return
	var spread: float = [0.0, 0.35, 0.6, 0.72][stage]
	# vine: a few low segments curling around the centre
	var pts: Array = []
	for k in 5:
		var a := -0.6 + 1.5 * float(k)
		pts.append(Vector3(cos(a) * spread * (0.35 + 0.15 * float(k)), 0.03, sin(a) * spread * (0.35 + 0.15 * float(k))))
	var prev := Vector3(0, 0.03, 0)
	for p in pts:
		var seg: Vector3 = (p as Vector3) - prev
		if seg.length() > 0.01:
			var up := seg.normalized()
			var side := up.cross(Vector3.UP)
			if side.length() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized()
			var face := side.cross(up).normalized()
			b.add(Shapes.prim_cylinder(0.012, 0.014, seg.length(), 5), Transform3D(Basis(side, up, face), prev + seg * 0.5), Palette.FOLIAGE_DARK)
		prev = p
	# big round leaves along the vine
	var leaves: int = [0, 4, 6, 7][stage]
	for i in leaves:
		var p2: Vector3 = pts[i % pts.size()]
		var a3 := TAU * float(i) / float(leaves) + 0.5
		var off := Vector3(cos(a3), 0, sin(a3)) * 0.08
		var size := 0.14 + 0.03 * float(stage) + 0.02 * float(i % 2)
		var col: Color = leaf if i % 3 != 0 else Palette.FOLIAGE_LIGHT
		b.add(Shapes.prim_sphere(0.5, 5, 8), Transform3D(Basis.IDENTITY.scaled(Vector3(size * 1.3, size * 0.35, size * 1.2)).rotated(Vector3.UP, a3), p2 + off + Vector3(0, 0.07 + 0.02 * float(i % 2), 0)), col)
	if stage == 1:
		b.add(Shapes.prim_torus(0.012, 0.03, 8, 4), Transform3D(Basis.IDENTITY, (pts[4] as Vector3) + Vector3(0, 0.05, 0)), Palette.FOLIAGE_LIGHT)
		return
	if stage == 2:
		# yellow blossom + a small green pumpkin
		var fp: Vector3 = (pts[3] as Vector3) + Vector3(0, 0.1, 0)
		b.add(Shapes.prim_cylinder(0.045, 0.01, 0.07, 6), Transform3D(Basis.IDENTITY, fp), Palette.FLOWER_YELLOW)
		_pumpkin_body(b, Vector3(0, 0.0, 0.05), 0.1, Palette.FOLIAGE_LIGHT.darkened(0.05), 6)
		return
	# ripe: a big ribbed pumpkin in the middle
	_pumpkin_body(b, Vector3(0, 0.0, 0.0), 0.24, tint, 8)
	b.cyl(0.025, 0.035, 0.12, Vector3(0.0, 0.43, 0.0), Palette.FOLIAGE_DARK.darkened(0.2), Vector3(0, 0, 12), 6)


## A ribbed pumpkin standing on the soil (base at y = pos.y), `r` = its radius.
static func _pumpkin_body(b: Batch, pos: Vector3, r: float, col: Color, ribs: int) -> void:
	var h := r * 0.82
	for k in ribs:
		var a := TAU * float(k) / float(ribs)
		var c: Color = col if k % 2 == 0 else col.darkened(0.08)
		b.add(Shapes.prim_sphere(r * 0.55, 7, 10), Transform3D(Basis.IDENTITY.scaled(Vector3(0.75, 1.5, 1.0)).rotated(Vector3.UP, -a), pos + Vector3(cos(a) * r * 0.45, h, sin(a) * r * 0.45)), c)
	b.add(Shapes.prim_sphere(r * 0.5, 6, 10), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.9, 1)), pos + Vector3(0, h * 1.05, 0)), col.lightened(0.05))


static func plant_material() -> Material:
	return U.vc_mat({"wind": 0.035, "wind_height": 0.3, "wind_speed": 1.7})
