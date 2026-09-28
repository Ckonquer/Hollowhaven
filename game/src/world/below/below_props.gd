extends RefCounted
## Prop factories for The Below. Most props are batched through the builder (b); anything with a
## light or behaviour is a node. All props sit on the floor (no floating clutter) and props that the
## player could bump into get simple collision.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Lamp := preload("res://src/world/below/below_lamp.gd")
const Builder := preload("res://src/world/below/below_builder.gd")

const TIMBER := Color("7a5236")
const TIMBER_DARK := Color("5a3b27")
const PLANK := Color("8e6340")
const IRON := Color("4a4048")
const RAIL := Color("6d6268")
const ROPE := Color("c9a66b")
const PAPER := Color("efe0bd")

const OUT := {"outline": true, "outline_w": 0.018}


# --- Lights ------------------------------------------------------------------------------------

static func lamp(parent: Node3D, pos: Vector3, opts: Dictionary = {}) -> Node3D:
	var l: Node3D = Lamp.new()
	l.setup(opts)
	l.position = pos
	if opts.has("yaw"):
		l.rotation_degrees.y = float(opts["yaw"])
	parent.add_child(l)
	return l


## Small light without a mesh (glowcap pools, backlights).
static func glow_light(parent: Node3D, pos: Vector3, color: Color, energy: float, rng_: float, shadow: bool = false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng_
	o.omni_attenuation = 1.3
	o.shadow_enabled = shadow
	o.light_specular = 0.2
	o.distance_fade_enabled = true
	o.distance_fade_begin = 30.0
	o.distance_fade_length = 8.0
	o.light_volumetric_fog_energy = 0.25
	o.position = pos
	parent.add_child(o)
	return o


# --- Mine --------------------------------------------------------------------------------------

## Timber support frame across a corridor. axis "x": corridor runs along z, frame spans x0..x1 at z.
static func timber_frame(b: Builder, at: float, a0: float, a1: float, y: float, h: float, axis: String = "x", broken: bool = false) -> void:
	var post := Vector3(0.28, h - 0.2, 0.28)
	var inset := 0.2
	var p0 := Vector3(a0 + inset, y + post.y * 0.5, at) if axis == "x" else Vector3(at, y + post.y * 0.5, a0 + inset)
	var p1 := Vector3(a1 - inset, y + post.y * 0.5, at) if axis == "x" else Vector3(at, y + post.y * 0.5, a1 - inset)
	var col := b.vary(TIMBER, 0.08)
	b.vbox(p0, post, col, Basis.IDENTITY, OUT)
	b.col_box(p0, post * Vector3(0.9, 1.0, 0.9), "wood")
	if broken:
		# The far post snapped: its stump stands, the cap beam leans against that wall (never across
		# the walkway, so nothing visual hangs where Krystal walks).
		var stump_h := post.y * 0.35
		var stump := Vector3(p1.x, y + stump_h * 0.5, p1.z)
		b.vbox(stump, Vector3(post.x, stump_h, post.z), col, Basis(Vector3.UP, 0.3), OUT)
		b.col_box(stump, Vector3(post.x, stump_h, post.z) * 0.9, "wood")
		var lean_len := minf(h * 0.95, 3.2)
		var along := Vector3(0, 0, 1) if axis == "x" else Vector3(1, 0, 0)
		var lean_axis := Vector3(1, 0, 0) if axis == "x" else Vector3(0, 0, 1)
		var bb := Basis(lean_axis, 0.62 if axis == "x" else -0.62)
		var bc := p1 + along * 0.55 + Vector3(0, -post.y * 0.5 + lean_len * 0.5 * cos(0.62), 0)
		var sz := Vector3(0.24, lean_len, 0.28) if axis == "x" else Vector3(0.28, lean_len, 0.24)
		b.vbox(bc, sz, b.vary(TIMBER_DARK), bb, OUT)
		return
	b.vbox(p1, post, col, Basis.IDENTITY, OUT)
	b.col_box(p1, post * Vector3(0.9, 1.0, 0.9), "wood")
	var span := a1 - a0
	var beam := Vector3(span, 0.3, 0.34) if axis == "x" else Vector3(0.34, 0.3, span)
	var bc := Vector3((a0 + a1) * 0.5, y + h - 0.35, at) if axis == "x" else Vector3(at, y + h - 0.35, (a0 + a1) * 0.5)
	b.vbox(bc, beam, b.vary(TIMBER, 0.06), Basis.IDENTITY, OUT)
	# Knee braces
	for s in [-1.0, 1.0]:
		var corner := p0 if s < 0.0 else p1
		var toward := 1.0 if s < 0.0 else -1.0
		var off := Vector3(toward * 0.35, post.y * 0.5 - 0.5, 0) if axis == "x" else Vector3(0, post.y * 0.5 - 0.5, toward * 0.35)
		var ax := Vector3(0, 0, 1) if axis == "x" else Vector3(1, 0, 0)
		var ang := -0.78 * toward if axis == "x" else 0.78 * toward
		b.vbox(corner + off, Vector3(0.14, 0.75, 0.14), b.vary(TIMBER_DARK), Basis(ax, ang), OUT)


## Rails from a to b (floor level) with sleepers.
static func rails(b: Builder, a: Vector3, c: Vector3, gauge: float = 0.9) -> void:
	var d := c - a
	var length := d.length()
	var dir := d / length
	var side := dir.cross(Vector3.UP).normalized()
	var basis := Basis.looking_at(dir, Vector3.UP)
	var mid := (a + c) * 0.5
	for s in [-0.5, 0.5]:
		b.vbox(mid + side * gauge * s + Vector3(0, 0.1, 0), Vector3(0.07, 0.07, length), RAIL, basis, {"shadows": false})
	var n := int(length / 0.75)
	for i in n:
		var p := a + dir * (0.4 + float(i) * 0.75)
		b.vbox(p + Vector3(0, 0.04, 0), Vector3(gauge + 0.45, 0.08, 0.22), b.vary(TIMBER_DARK, 0.1), basis.rotated(Vector3.UP, b.rng.randf_range(-0.05, 0.05)), {"shadows": false})


static func crate(b: Builder, pos: Vector3, size: float = 0.8, yaw: float = 0.0, collide: bool = true) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var c := pos + Vector3(0, size * 0.5, 0)
	b.vbox(c, Vector3.ONE * size, b.vary(PLANK, 0.07), basis, OUT)
	# slats
	for s in [-1.0, 1.0]:
		b.vbox(c + basis * Vector3(0, s * size * 0.32, size * 0.5), Vector3(size * 1.02, size * 0.12, 0.04), TIMBER_DARK, basis, {"shadows": false})
		b.vbox(c + basis * Vector3(0, s * size * 0.32, -size * 0.5), Vector3(size * 1.02, size * 0.12, 0.04), TIMBER_DARK, basis, {"shadows": false})
	b.vbox(c + basis * Vector3(0, 0, size * 0.5), Vector3(size * 0.12, size * 1.0, 0.045), TIMBER_DARK, basis.rotated(basis.z, 0.78), {"shadows": false})
	if collide:
		b.col_box(c, Vector3.ONE * size, "wood", basis)


static func barrel(b: Builder, pos: Vector3, r: float = 0.36, h: float = 0.9, collide: bool = true) -> void:
	var c := pos + Vector3(0, h * 0.5, 0)
	b.vcyl(c, r, h, b.vary(PLANK, 0.06), Basis.IDENTITY, OUT)
	for y in [-0.3, 0.3]:
		b.vcyl(c + Vector3(0, h * y, 0), r * 1.04, 0.06, IRON, Basis.IDENTITY, {"shadows": false})
	b.vcyl(c + Vector3(0, h * 0.5, 0), r * 0.92, 0.02, TIMBER_DARK, Basis.IDENTITY, {"shadows": false})
	if collide:
		b.col_cyl(c, r, h, "wood")


static func sack(b: Builder, pos: Vector3, yaw: float = 0.0) -> void:
	b.vblob(pos + Vector3(0, 0.25, 0), Vector3(0.32, 0.28, 0.26), b.vary(Color("b99a6e")), 2, Basis(Vector3.UP, deg_to_rad(yaw)))
	b.vblob(pos + Vector3(0, 0.52, 0), Vector3(0.1, 0.08, 0.1), Color("a3845a"), 4)


## Mine cart (tipped = lying on its side). Collision included.
static func cart(b: Builder, pos: Vector3, yaw: float = 0.0, tipped: bool = false, ore: bool = true) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	if tipped:
		basis = basis * Basis(Vector3(0, 0, 1), deg_to_rad(95))
	var up := basis.y
	var c := pos + (Vector3(0, 0.62, 0) if not tipped else Vector3(0, 0.55, 0))
	var body_col := Color("6b5a52")
	b.vbox(c, Vector3(1.05, 0.7, 1.5), body_col, basis, OUT)
	b.vbox(c + up * 0.36, Vector3(1.12, 0.07, 1.58), IRON, basis, {"shadows": false})
	for s in [-1.0, 1.0]:
		b.vbox(c + basis * Vector3(0, 0, s * 0.76), Vector3(1.08, 0.72, 0.06), IRON, basis, {"shadows": false})
	if ore and not tipped:
		for i in 4:
			b.vblob(c + up * 0.36 + basis * Vector3(b.rng.randf_range(-0.3, 0.3), 0.02, b.rng.randf_range(-0.5, 0.5)), Vector3.ONE * 0.24, b.vary(Palette.MINE_ROCK.lerp(Palette.COPPER, 0.25)), -1, Basis.IDENTITY, {"small": true})
	var wheel_basis := basis * Basis(Vector3(0, 0, 1), PI * 0.5)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.vcyl(c + basis * Vector3(sx * 0.56, -0.42, sz * 0.48), 0.2, 0.09, IRON, wheel_basis, OUT)
	b.col_box(c + Vector3(0, -0.1, 0), Vector3(1.15, 1.0, 1.6), "wood", basis)


static func pickaxe_lean(b: Builder, pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3(1, 0, 0), -0.25)
	b.vbox(pos + basis * Vector3(0, 0.5, 0), Vector3(0.06, 1.0, 0.06), PLANK, basis, OUT)
	b.vbox(pos + basis * Vector3(0, 1.0, 0), Vector3(0.55, 0.07, 0.08), IRON, basis * Basis(Vector3(0, 0, 1), 0.12), OUT)


static func rope_coil(b: Builder, pos: Vector3) -> void:
	for i in 3:
		b.batch(_torus_mesh(), _tint(), Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.36, 0.5, 0.36)), pos + Vector3(0, 0.05 + float(i) * 0.06, 0)), ROPE)


static var _cache: Dictionary = {}


static func _torus_mesh() -> Mesh:
	if not _cache.has("torus"):
		var t := TorusMesh.new()
		t.inner_radius = 0.72
		t.outer_radius = 1.0
		t.rings = 16
		t.ring_segments = 8
		_cache["torus"] = t
	return _cache["torus"]


static func _tint() -> Material:
	return Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.10, "rim": 0.22})


## Public wrappers for other prop modules (Tobin's annex, R75): the shared, cached torus mesh and the
## vertex-colour tint material batches use. Same objects as the private helpers - no behaviour change.
static func torus_mesh() -> Mesh:
	return _torus_mesh()


static func tint() -> Material:
	return _tint()


## A small plank table.
static func table(b: Builder, pos: Vector3, yaw: float = 0.0, w: float = 1.4, d: float = 0.8) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	b.vbox(pos + Vector3(0, 0.8, 0), Vector3(w, 0.08, d), b.vary(PLANK), basis, OUT)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.vbox(pos + basis * Vector3(sx * (w * 0.5 - 0.08), 0.38, sz * (d * 0.5 - 0.08)), Vector3(0.08, 0.76, 0.08), TIMBER_DARK, basis, OUT)
	b.col_box(pos + Vector3(0, 0.42, 0), Vector3(w, 0.84, d), "wood", basis)


## Paper sheet(s) lying on a surface (lore spots get an emissive accent through the interactable).
static func papers(b: Builder, pos: Vector3, yaw: float = 0.0) -> void:
	b.vbox(pos + Vector3(0, 0.005, 0), Vector3(0.24, 0.01, 0.32), PAPER, Basis(Vector3.UP, deg_to_rad(yaw)), {"shadows": false})
	b.vbox(pos + Vector3(0.05, 0.012, 0.03), Vector3(0.24, 0.01, 0.32), PAPER.darkened(0.08), Basis(Vector3.UP, deg_to_rad(yaw + 17.0)), {"shadows": false})


## Glowcap cluster (decor). Emissive caps; optional small light for path lighting.
static func glowcaps(b: Builder, parent: Node3D, pos: Vector3, count: int = 5, spread: float = 0.35, light_energy: float = 0.0, light_range: float = 2.6, color: Color = Palette.GLOWCAP) -> void:
	for i in count:
		var a := b.rng.randf() * TAU
		var r := b.rng.randf_range(0.0, spread)
		var p := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := b.rng.randf_range(0.08, 0.26)
		var cap := b.rng.randf_range(0.05, 0.12) * (1.0 + h)
		var tilt := Basis(Vector3(cos(a + 1.3), 0, sin(a + 1.3)), b.rng.randf_range(-0.25, 0.25))
		b.vcyl(p + tilt * Vector3(0, h * 0.5, 0), 0.018 + cap * 0.18, h, Color("d9e8dc"), tilt, {"shadows": false})
		b.vglow(_sphere_mesh(), Transform3D(tilt.scaled_local(Vector3(cap * 2.0, cap * 1.1, cap * 2.0)), p + tilt * Vector3(0, h, 0)), color, 1.6)
	if light_energy > 0.0:
		glow_light(parent, pos + Vector3(0, 0.45, 0), color, light_energy, light_range)


static func _sphere_mesh() -> Mesh:
	if not _cache.has("sph"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.rings = 6
		m.radial_segments = 10
		_cache["sph"] = m
	return _cache["sph"]


## Hanging "sign" board with painted stripes.
static func sign_board(b: Builder, pos: Vector3, yaw: float, w: float = 1.2, h: float = 0.6, col: Color = PLANK) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	b.vbox(pos, Vector3(w, h, 0.06), b.vary(col, 0.05), basis, OUT)
	b.vbox(pos + basis * Vector3(0, h * 0.12, 0.035), Vector3(w * 0.7, h * 0.12, 0.01), Color("e8dcc0"), basis, {"shadows": false})
	b.vbox(pos + basis * Vector3(-w * 0.08, -h * 0.15, 0.035), Vector3(w * 0.5, h * 0.08, 0.01), Color("e8dcc0"), basis, {"shadows": false})


# --- Ruins -----------------------------------------------------------------------------------------

static func pillar(b: Builder, pos: Vector3, r: float, h: float, broken: bool = false) -> void:
	var stone := Palette.RUIN_STONE
	var dark := Palette.RUIN_STONE_DARK
	b.vbox(pos + Vector3(0, 0.2, 0), Vector3(r * 2.7, 0.4, r * 2.7), b.vary(dark, 0.05))
	b.vcyl(pos + Vector3(0, 0.55, 0), r * 1.2, 0.3, b.vary(stone, 0.05), Basis.IDENTITY, {"segments": 16})
	var shaft_h := h - 1.1 if not broken else h * 0.45
	b.vcyl(pos + Vector3(0, 0.7 + shaft_h * 0.5, 0), r, shaft_h, b.vary(stone, 0.06), Basis.IDENTITY, {"segments": 16})
	# carved rings
	for i in 3:
		b.vcyl(pos + Vector3(0, 0.7 + shaft_h * (0.25 + 0.25 * float(i)), 0), r * 1.04, 0.1, dark, Basis.IDENTITY, {"segments": 16, "shadows": false})
	if not broken:
		b.vcyl(pos + Vector3(0, h - 0.35, 0), r * 1.25, 0.3, b.vary(stone, 0.05), Basis.IDENTITY, {"segments": 16})
		b.vbox(pos + Vector3(0, h - 0.1, 0), Vector3(r * 2.9, 0.3, r * 2.9), b.vary(dark, 0.05))
		b.col_cyl(pos + Vector3(0, h * 0.5, 0), r * 1.05, h)
	else:
		b.col_cyl(pos + Vector3(0, (shaft_h + 0.7) * 0.5, 0), r * 1.05, shaft_h + 0.7)
		# fallen drum pieces
		for i in 2:
			var p := pos + Vector3(b.rng.randf_range(0.8, 1.6), r * 0.9, b.rng.randf_range(-1.2, 1.2))
			var bb := Basis(Vector3(0, 0, 1), PI * 0.5).rotated(Vector3.UP, b.rng.randf() * TAU)
			b.vcyl(p, r * 0.95, 1.0, b.vary(stone), bb, {"segments": 16})
			b.col_box(p, Vector3(r * 1.9, 1.0, r * 1.9), "stone", bb)


## Carved relief face on a wall. facing = outward normal of the wall face (into the room).
## scale 1 = ~2 m tall face. eyes: "closed" | "open" (faint glow) | "hollow".
static func carved_face(b: Builder, pos: Vector3, facing: Vector3, scale: float = 1.0, eyes: String = "closed", glow_color: Color = Palette.RUIN_LIGHT) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)   # local +Z = facing
	var stone := Palette.RUIN_STONE.lightened(0.05)
	var dark := Palette.RUIN_STONE_DARK
	var s := scale
	var o := pos
	# face plate (flattened blob), brow, nose, cheeks, lips
	b.vblob(o, Vector3(0.95, 1.2, 0.35) * s, b.vary(stone, 0.04), 3, basis)
	b.vbox(o + basis * Vector3(0, 0.38 * s, 0.26 * s), Vector3(1.3, 0.16, 0.2) * s, stone, basis)
	b.batch(_prism_mesh(), _tint(), Transform3D(basis * Basis(Vector3(1, 0, 0), -0.2).scaled_local(Vector3(0.28, 0.62, 0.3) * s), o + basis * Vector3(0, 0.02, 0.3 * s)), stone)
	for sx in [-1.0, 1.0]:
		b.vblob(o + basis * Vector3(sx * 0.46 * s, -0.12 * s, 0.2 * s), Vector3(0.24, 0.2, 0.14) * s, stone.darkened(0.03), 1, basis)
		match eyes:
			"closed":
				b.vbox(o + basis * Vector3(sx * 0.3 * s, 0.2 * s, 0.3 * s), Vector3(0.36, 0.05, 0.06) * s, dark, basis * Basis(Vector3(0, 0, 1), sx * 0.12), {"shadows": false})
				b.vbox(o + basis * Vector3(sx * 0.3 * s, 0.17 * s, 0.29 * s), Vector3(0.3, 0.035, 0.05) * s, dark.darkened(0.2), basis, {"shadows": false})
			"open":
				b.vsphere(o + basis * Vector3(sx * 0.3 * s, 0.2 * s, 0.24 * s), Vector3(0.22, 0.14, 0.12) * s, dark.darkened(0.4), basis)
				b.vglow(_sphere_mesh(), Transform3D(basis.scaled_local(Vector3(0.07, 0.07, 0.05) * s), o + basis * Vector3(sx * 0.3 * s, 0.2 * s, 0.3 * s)), glow_color, 1.4)
			"hollow":
				b.vsphere(o + basis * Vector3(sx * 0.3 * s, 0.2 * s, 0.26 * s), Vector3(0.24, 0.16, 0.1) * s, Color(0.03, 0.04, 0.05), basis)
	b.vbox(o + basis * Vector3(0, -0.42 * s, 0.26 * s), Vector3(0.42, 0.06, 0.08) * s, dark, basis, {"shadows": false})
	b.vbox(o + basis * Vector3(0, -0.5 * s, 0.24 * s), Vector3(0.3, 0.05, 0.08) * s, stone, basis, {"shadows": false})


static func _prism_mesh() -> Mesh:
	if not _cache.has("prism"):
		var m := PrismMesh.new()
		m.size = Vector3.ONE
		_cache["prism"] = m
	return _cache["prism"]


## Dressed stone-block wall facing along a line (visual only; collision is the room shell).
static func block_wall(b: Builder, p0: Vector3, p1: Vector3, inward: Vector3, h: float, skip: Array = [], moss: float = 0.12) -> void:
	var line := p1 - p0
	var length := line.length()
	var dir := line / length
	var basis := Basis.looking_at(-inward, Vector3.UP)
	var course := 0.62
	var rows := int(ceilf(h / course))
	for row in rows:
		var y := float(row) * course
		var offset := 0.0 if row % 2 == 0 else 0.55
		var t := -offset
		while t < length:
			var w := b.rng.randf_range(0.9, 1.4)
			var a := maxf(t, 0.0)
			var e := minf(t + w, length)
			t += w
			if e - a < 0.15:
				continue
			var mid := (a + e) * 0.5
			var skipped := false
			for s in skip:
				if e > float(s[0]) and a < float(s[1]) and y < float(s[2]):
					skipped = true
			if skipped:
				continue
			var hh := minf(course, h - y)
			if hh < 0.1:
				continue
			var protr := b.rng.randf_range(0.03, 0.1)
			var c := p0 + dir * mid + Vector3.UP * (y + hh * 0.5) + inward * protr * 0.5
			var col := b.vary(Palette.RUIN_STONE if b.rng.randf() > 0.3 else Palette.RUIN_STONE.lerp(Palette.RUIN_STONE_DARK, 0.4), 0.06)
			if b.rng.randf() < moss and y < 2.0:
				col = col.lerp(Palette.RUIN_MOSS, 0.55)
			b.vbox(c, Vector3(e - a - 0.05, hh - 0.05, protr + 0.1), col, basis, {"shadows": false})


## Stone floor tiles with slight gaps.
static func tile_floor(b: Builder, x0: float, x1: float, z0: float, z1: float, y: float, tile: float = 1.9, holes: Array = []) -> void:
	var nx := int(ceilf((x1 - x0) / tile))
	var nz := int(ceilf((z1 - z0) / tile))
	for ix in nx:
		for iz in nz:
			var a0 := x0 + float(ix) * tile
			var a1 := minf(a0 + tile, x1)
			var c0 := z0 + float(iz) * tile
			var c1 := minf(c0 + tile, z1)
			var cx := (a0 + a1) * 0.5
			var cz := (c0 + c1) * 0.5
			var skip := false
			for hole in holes:
				if cx > float(hole[0]) and cx < float(hole[1]) and cz > float(hole[2]) and cz < float(hole[3]):
					skip = true
			if skip:
				continue
			var col := b.vary(Palette.RUIN_STONE.lerp(Palette.RUIN_STONE_DARK, b.rng.randf_range(0.15, 0.5)), 0.05)
			if b.rng.randf() < 0.06:
				col = col.lerp(Palette.RUIN_MOSS, 0.4)
			b.vbox(Vector3(cx, y + 0.02 - b.rng.randf_range(0.0, 0.025), cz), Vector3(a1 - a0 - 0.06, 0.08, c1 - c0 - 0.06), col, Basis.IDENTITY, {"shadows": false})


## Pile of rubble blobs (collision optional as one box).
static func rubble_pile(b: Builder, center: Vector3, radius: float, height: float, colors: Array, count: int = 10, collide: bool = true) -> void:
	for i in count:
		var a := b.rng.randf() * TAU
		var r := b.rng.randf_range(0.0, radius * 0.8)
		var s := b.rng.randf_range(0.35, 0.75) * (1.0 - r / (radius * 1.4))
		var hh := height * (1.0 - r / radius) * b.rng.randf_range(0.5, 0.9)
		var p := center + Vector3(cos(a) * r, maxf(hh - s * 0.6, s * 0.3), sin(a) * r)
		b.vblob(p, Vector3(s * 1.2, s, s * 1.1), b.vary(b.pick(colors), 0.07), -1, Basis(Vector3.UP, b.rng.randf() * TAU))
	if collide:
		b.col_box(center + Vector3(0, height * 0.35, 0), Vector3(radius * 1.2, height * 0.7, radius * 1.2))
