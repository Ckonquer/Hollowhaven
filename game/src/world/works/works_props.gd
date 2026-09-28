extends RefCounted
## Prop factories for the Hushed Works (rooms 1-8; the deep module may reuse them). Everything static goes
## through the Below builder (batched MultiMeshes, shared tint material); lights are below_lamp.gd nodes.
## Palette: cold blue-grey iron and painted plate, pale limestone, warm brass/bronze accents and lantern pools.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")

# --- Works palette ---------------------------------------------------------------------------------------
const IRON := Color("4b5563")
const IRON_DARK := Color("333a46")
const STEEL := Color("7d8898")
const RIVET := Color("9aa3b0")
const PLATE := Color("5d6b7c")          # painted service plate (blue-grey)
const PLATE_DARK := Color("46505e")
const BRASS := Color("c9a25a")
const BRONZE := Color("a8743e")
const COPPER_PIPE := Color("b8764a")
const STONE := Color("6f7480")
const STONE_DARK := Color("4f535d")
const STONE_PALE := Color("b9b2a3")     # the light well's limestone
const FLAG := Color("5e6168")           # floor flagstones
const TIMBER := Color("7a5a40")
const RUST := Color("8a5a3c")
const WATER := Color("5fb0b8")
const COLD_LAMP := Color("b9cbe8")
const WARM_LAMP := Color("ffc27a")
const SIGNAL_LAMP := Color("ffcf86")

const OUT := {"outline": true, "outline_w": 0.016}


static func vary(b: Builder, c: Color, amt: float = 0.06) -> Color:
	return b.vary(c, amt)


## Flagstone floor dressing on a rect: slightly raised tiles with gaps (visual only).
static func flag_floor(b: Builder, x0: float, x1: float, z0: float, z1: float, y: float, col: Color = FLAG, tile: float = 1.6) -> void:
	var nx := maxi(int((x1 - x0) / tile), 1)
	var nz := maxi(int((z1 - z0) / tile), 1)
	var tx := (x1 - x0) / float(nx)
	var tz := (z1 - z0) / float(nz)
	for i in nx:
		for k in nz:
			var c := Vector3(x0 + (float(i) + 0.5) * tx, y + 0.01, z0 + (float(k) + 0.5) * tz)
			b.vbox(c, Vector3(tx - 0.07, 0.04, tz - 0.07), b.vary(col, 0.07), Basis.IDENTITY, {"shadows": false})


## Riveted iron rib (vertical) against a wall. normal = into the room.
static func wall_rib(b: Builder, foot: Vector3, normal: Vector3, h: float, col: Color = IRON) -> void:
	var basis := Basis.looking_at(-normal, Vector3.UP)
	b.vbox(foot + Vector3.UP * h * 0.5 + normal * 0.12, Vector3(0.34, h, 0.24), b.vary(col, 0.05), basis, OUT)
	var n := int(h / 0.6)
	for i in n:
		b.vsphere(foot + Vector3.UP * (0.3 + float(i) * 0.6) + normal * 0.25, Vector3(0.06, 0.06, 0.04), RIVET, basis, {"shadows": false})


## Iron girder arch across a hall: two columns (colliding) and a cross beam. axis = hall direction.
static func girder_arch(b: Builder, at: float, a0: float, a1: float, y: float, h: float, axis: String = "x") -> void:
	var col := b.vary(IRON, 0.05)
	var post := Vector3(0.36, h, 0.36)
	var p0 := Vector3(at, y + h * 0.5, a0 + 0.3) if axis == "x" else Vector3(a0 + 0.3, y + h * 0.5, at)
	var p1 := Vector3(at, y + h * 0.5, a1 - 0.3) if axis == "x" else Vector3(a1 - 0.3, y + h * 0.5, at)
	for p in [p0, p1]:
		b.vbox(p, post, col, Basis.IDENTITY, OUT)
		b.col_box(p, post * Vector3(0.9, 1.0, 0.9))
		b.vbox(p - Vector3(0, h * 0.5 - 0.15, 0), Vector3(0.6, 0.3, 0.6), IRON_DARK)
	var span := a1 - a0 - 0.6
	var beam_c := Vector3(at, y + h - 0.25, (a0 + a1) * 0.5) if axis == "x" else Vector3((a0 + a1) * 0.5, y + h - 0.25, at)
	var beam_s := Vector3(0.3, 0.42, span) if axis == "x" else Vector3(span, 0.42, 0.3)
	b.vbox(beam_c, beam_s, col, Basis.IDENTITY, OUT)
	# knee braces
	for sgn in [-1.0, 1.0]:
		var kc := beam_c + (Vector3(0, -0.55, sgn * (span * 0.5 - 0.55)) if axis == "x" else Vector3(sgn * (span * 0.5 - 0.55), -0.55, 0))
		var kb := Basis(Vector3(1, 0, 0), sgn * 0.78) if axis == "x" else Basis(Vector3(0, 0, 1), -sgn * 0.78)
		b.vbox(kc, Vector3(0.2, 1.2, 0.2), col, kb)


## A pipe run (cylinder) between two points with brackets. radius ~0.08-0.25.
static func pipe(b: Builder, a: Vector3, c: Vector3, r: float, col: Color = COPPER_PIPE, brackets: bool = true) -> void:
	var d := c - a
	var length := d.length()
	if length < 0.05:
		return
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(d.normalized(), up) * Basis(Vector3(1, 0, 0), PI * 0.5)
	b.vcyl((a + c) * 0.5, r, length, b.vary(col, 0.04), basis, {"segments": 10, "shadows": false})
	if brackets:
		var n := maxi(int(length / 2.2), 1)
		for i in n + 1:
			var p := a.lerp(c, float(i) / float(n))
			b.vcyl(p, r * 1.35, 0.1, IRON_DARK, basis, {"segments": 10, "shadows": false})


## A tall iron locker (visual + collision). Doors face `normal`. ajar opens the door a little.
static func locker(b: Builder, foot: Vector3, normal: Vector3, ajar: bool = false, tint: Color = PLATE) -> void:
	var basis := Basis.looking_at(-normal, Vector3.UP)
	var body := foot + Vector3.UP * 1.0
	b.vbox(body, Vector3(0.78, 2.0, 0.55), b.vary(tint, 0.06), basis, OUT)
	b.col_box(body, Vector3(0.78, 2.0, 0.55), "stone", basis)
	# vents + handle + name plate
	for i in 3:
		b.vbox(body + basis * Vector3(0, 0.62 - float(i) * 0.1, 0.285), Vector3(0.42, 0.03, 0.02), PLATE_DARK, basis, {"shadows": false})
	b.vbox(body + basis * Vector3(0.28, -0.05, 0.3), Vector3(0.04, 0.18, 0.04), BRASS, basis, {"shadows": false})
	b.vbox(body + basis * Vector3(0, 0.85, 0.285), Vector3(0.3, 0.08, 0.02), Color("e6dcc2"), basis, {"shadows": false})
	if ajar:
		var hinge := body + basis * Vector3(-0.39, 0, 0.3)
		var db := basis * Basis(Vector3.UP, -0.9)
		b.vbox(hinge + db * Vector3(0.37, 0, 0.02), Vector3(0.74, 1.94, 0.04), b.vary(tint, 0.08), db, {"shadows": false})


## Long low bench (colliding) along an axis.
static func bench(b: Builder, center: Vector3, length: float, axis: String = "x", col: Color = TIMBER) -> void:
	var size := Vector3(length, 0.1, 0.5) if axis == "x" else Vector3(0.5, 0.1, length)
	b.vbox(center + Vector3.UP * 0.45, size, b.vary(col, 0.06), Basis.IDENTITY, OUT)
	b.col_box(center + Vector3.UP * 0.25, Vector3(size.x, 0.5, size.z), "wood")
	for sgn in [-1.0, 1.0]:
		var off := Vector3(sgn * (length * 0.5 - 0.25), 0.2, 0) if axis == "x" else Vector3(0, 0.2, sgn * (length * 0.5 - 0.25))
		b.vbox(center + off, Vector3(0.1, 0.4, 0.4) if axis == "x" else Vector3(0.4, 0.4, 0.1), IRON_DARK)


## Iron grate (vertical bars + frame), colliding. Spans a0..a1 along `axis` at `at`, from y to y + h.
static func grate(b: Builder, at: float, a0: float, a1: float, y: float, h: float, axis: String = "x", spacing: float = 0.22) -> void:
	var n := int((a1 - a0) / spacing)
	for i in n + 1:
		var s := a0 + float(i) * (a1 - a0) / float(maxi(n, 1))
		var p := Vector3(s, y + h * 0.5, at) if axis == "x" else Vector3(at, y + h * 0.5, s)
		b.vcyl(p, 0.035, h, IRON_DARK, Basis.IDENTITY, {"segments": 6, "shadows": false})
	for yy in [y + 0.1, y + h * 0.55, y + h - 0.08]:
		var c := Vector3((a0 + a1) * 0.5, yy, at) if axis == "x" else Vector3(at, yy, (a0 + a1) * 0.5)
		b.vbox(c, Vector3(a1 - a0, 0.08, 0.1) if axis == "x" else Vector3(0.1, 0.08, a1 - a0), IRON, Basis.IDENTITY, OUT)
	var cc := Vector3((a0 + a1) * 0.5, y + h * 0.5, at) if axis == "x" else Vector3(at, y + h * 0.5, (a0 + a1) * 0.5)
	b.col_box(cc, Vector3(a1 - a0, h, 0.14) if axis == "x" else Vector3(0.14, h, a1 - a0))


## Iron cage lamp shade over a light (visual only; the light is placed separately).
static func cage_shade(b: Builder, pos: Vector3, col: Color = IRON_DARK) -> void:
	b.vcone(pos + Vector3.UP * 0.12, 0.34, 0.26, col)
	b.vcyl(pos + Vector3.UP * 0.6, 0.015, 1.0, col, Basis.IDENTITY, {"segments": 5, "shadows": false})


## Stack of crates / barrels / sacks against a wall (all colliding where solid).
static func supplies(b: Builder, pos: Vector3, yaw: float) -> void:
	Props.crate(b, pos, 0.85, yaw)
	Props.crate(b, pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.95, 0, 0.05), 0.75, yaw + 9.0)
	Props.crate(b, pos + Vector3(0.1, 0.85, 0.0), 0.62, yaw - 14.0, false)
	Props.sack(b, pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(-0.8, 0, 0.35), yaw)


## A service sign plate on a wall with a big simple symbol. normal = into the room. symbol: water | bell |
## light | refuge | up. Readable without colour: each symbol is a distinct silhouette.
static func symbol_sign(b: Builder, pos: Vector3, normal: Vector3, symbol: String, glow: Color = Color.WHITE, size: float = 0.9) -> void:
	var basis := Basis.looking_at(-normal, Vector3.UP)
	b.vbox(pos, Vector3(size, size, 0.06), b.vary(PLATE_DARK, 0.04), basis, OUT)
	var face := pos + normal * 0.045
	var ink := Color("efe6cf") if glow == Color.WHITE else glow
	var s := size
	match symbol:
		"water":   # a drop: sphere + cone
			b.vsphere(face + Vector3(0, -0.08, 0) * s, Vector3(0.36, 0.36, 0.05) * s, ink, basis, {"shadows": false})
			b.vcone(face + Vector3(0, 0.14, 0) * s, 0.15 * s, 0.34 * s, ink, Basis.IDENTITY, {"shadows": false})
		"bell":
			b.vcone(face + Vector3(0, 0.02, 0) * s, 0.22 * s, 0.42 * s, ink, Basis.IDENTITY, {"shadows": false})
			b.vsphere(face + Vector3(0, -0.24, 0) * s, Vector3(0.1, 0.1, 0.05) * s, ink, basis, {"shadows": false})
		"light":   # a sun: disc + rays
			b.vsphere(face, Vector3(0.24, 0.24, 0.05) * s, ink, basis, {"shadows": false})
			for i in 8:
				var a := TAU * float(i) / 8.0
				var rb := basis * Basis(Vector3(0, 0, 1), a)
				b.vbox(face + rb * Vector3(0, 0.3 * s, 0), Vector3(0.05, 0.14, 0.02) * s, ink, rb, {"shadows": false})
		"refuge":  # a sprout: stem + two leaves
			b.vbox(face + Vector3(0, -0.1, 0) * s, Vector3(0.05, 0.4, 0.02) * s, ink, basis, {"shadows": false})
			for sgn in [-1.0, 1.0]:
				var lb := basis * Basis(Vector3(0, 0, 1), sgn * 0.7)
				b.vsphere(face + basis * Vector3(sgn * 0.12, 0.1, 0) * s, Vector3(0.16, 0.08, 0.03) * s, ink, lb, {"shadows": false})
		"up":      # an arrow
			b.vbox(face + Vector3(0, -0.08, 0) * s, Vector3(0.08, 0.36, 0.02) * s, ink, basis, {"shadows": false})
			for sgn in [-1.0, 1.0]:
				var ab := basis * Basis(Vector3(0, 0, 1), sgn * 0.75)
				b.vbox(face + basis * Vector3(sgn * 0.09, 0.14, 0) * s, Vector3(0.07, 0.26, 0.02) * s, ink, ab, {"shadows": false})


## Hanging chain (visual) from a ceiling point down `length` metres.
static func chain(b: Builder, top: Vector3, length: float, col: Color = IRON_DARK) -> void:
	b.vcyl(top - Vector3.UP * length * 0.5, 0.02, length, col, Basis.IDENTITY, {"segments": 5, "shadows": false})


## Warm floor glow spot (flat unshaded decal) under a real lamp: sells "this light lights the floor".
static func glow_pool(b: Builder, pos: Vector3, radius: float, col: Color = WARM_LAMP) -> void:
	b.batch(Builder.unit_cyl(16), Mat.transparent(Color(col.r, col.g, col.b, 0.13), true), Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 2.0, 0.01, radius * 2.0)), pos + Vector3.UP * 0.03), Color.WHITE, false)


## Carved relief face (pale stone, eyes shut) on a wall. facing = into the room. ~2 m tall at scale 1.
## hook: add an iron hook with a dark, unlit lantern hanging under the chin (the Hall of Closed Eyes).
static func face_relief(b: Builder, pos: Vector3, facing: Vector3, s: float = 1.0, hook: bool = true) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	var stone := Color("a8a3a8")
	var dark := Color("5a5560")
	b.vblob(pos, Vector3(0.9, 1.15, 0.32) * s, b.vary(stone, 0.04), 3, basis)
	b.vbox(pos + basis * Vector3(0, 0.36 * s, 0.24 * s), Vector3(1.2, 0.14, 0.18) * s, stone, basis)
	b.batch(Props._prism_mesh(), Builder.tint_mat(), Transform3D(basis * Basis(Vector3(1, 0, 0), -0.2).scaled_local(Vector3(0.26, 0.58, 0.28) * s), pos + basis * Vector3(0, 0.02, 0.28 * s)), stone)
	for sx in [-1.0, 1.0]:
		b.vbox(pos + basis * Vector3(sx * 0.29 * s, 0.19 * s, 0.29 * s), Vector3(0.34, 0.045, 0.06) * s, dark, basis * Basis(Vector3(0, 0, 1), sx * 0.14), {"shadows": false})
		b.vbox(pos + basis * Vector3(sx * 0.29 * s, 0.16 * s, 0.28 * s), Vector3(0.28, 0.03, 0.05) * s, dark.darkened(0.2), basis, {"shadows": false})
	b.vbox(pos + basis * Vector3(0, -0.4 * s, 0.25 * s), Vector3(0.4, 0.05, 0.07) * s, dark, basis, {"shadows": false})
	if hook:
		var hp := pos + basis * Vector3(0, -0.8 * s, 0.35)
		b.vbox(hp, Vector3(0.05, 0.05, 0.4), IRON_DARK, basis, {"shadows": false})
		b.vcyl(hp + basis * Vector3(0, -0.28, 0.18), 0.1, 0.3, IRON_DARK, Basis.IDENTITY, {"segments": 8})
		b.vcone(hp + basis * Vector3(0, -0.08, 0.18), 0.11, 0.12, IRON_DARK)


# --- Wall texture and lived-in dressing (VISUAL_BUGS IN-15: the first rooms read flat next to Chapter One's
# plank-lined Below). All visual, batched, no collision; `skip` = [[from, to], ...] spans (in the coordinate
# that varies along the wall) left bare for doorways.

static var _tapers: Dictionary = {}


## Batched truncated cone (bottom radius, top radius, height) centred at `center` (cached unit meshes).
static func taper(b: Builder, center: Vector3, bottom_r: float, top_r: float, height: float, col: Color, basis: Basis = Basis.IDENTITY, shadows: bool = true) -> void:
	var ratio := snappedf(clampf(top_r / maxf(bottom_r, 0.001), 0.0, 4.0), 0.05)
	var key := "%.2f" % ratio
	if not _tapers.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.5 * ratio
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = 12
		m.rings = 1
		_tapers[key] = m
	b.batch(_tapers[key], Builder.tint_mat(), Transform3D(basis.scaled_local(Vector3(bottom_r * 2.0, height, bottom_r * 2.0)), center), col, shadows)


## True when `a` falls inside one of the skip spans (with a margin).
static func _skipped(a: float, skip: Array, margin: float = 0.1) -> bool:
	for s in skip:
		if a > float(s[0]) - margin and a < float(s[1]) + margin:
			return true
	return false


## Vertical tongue-and-groove boards on the lower part of a wall (height h from the floor y), with a cap rail.
## p0 -> p1 runs along the wall's inner face; inward = into the room.
static func plank_wainscot(b: Builder, p0: Vector3, p1: Vector3, inward: Vector3, y: float, h: float, col: Color = TIMBER, skip: Array = []) -> void:
	var along := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	var length := along.length()
	if length < 0.3:
		return
	var dir := along / length
	var face := Basis.looking_at(-inward, Vector3.UP)
	var w := 0.2
	var n := int(length / w)
	for i in n:
		var p := p0 + dir * ((float(i) + 0.5) * length / float(n))
		if _skipped(p.x if absf(dir.x) > 0.5 else p.z, skip):
			continue
		var hh := h - (0.04 if i % 3 == 1 else 0.0)
		b.vbox(Vector3(p.x, y + hh * 0.5, p.z) + inward * 0.03, Vector3(length / float(n) - 0.025, hh, 0.04), b.vary(col.darkened(0.06 if i % 2 == 0 else 0.0), 0.05), face, {"shadows": false})
	var t := 0.0
	while t < length:
		var t1 := minf(length, t + 2.0)
		var mid := p0 + dir * ((t + t1) * 0.5)
		if not _skipped(mid.x if absf(dir.x) > 0.5 else mid.z, skip, 0.6):
			b.vbox(Vector3(mid.x, y + h + 0.03, mid.z) + inward * 0.06, Vector3(t1 - t, 0.07, 0.1), col.darkened(0.25), face, {"shadows": false})
		t = t1


## Riveted plate seams on an iron wall: horizontal seams at the given heights (above y) and vertical seams
## every `pitch` metres, rivet heads along both. p0 -> p1 runs along the wall's inner face.
static func plate_seams(b: Builder, p0: Vector3, p1: Vector3, inward: Vector3, y: float, rows: Array, top: float, pitch: float = 2.4, col: Color = PLATE_DARK, skip: Array = []) -> void:
	var along := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	var length := along.length()
	if length < 0.5:
		return
	var dir := along / length
	var face := Basis.looking_at(-inward, Vector3.UP)
	for ry in rows:
		var t := 0.0
		while t < length - 0.05:
			var t1 := minf(length, t + 1.2)
			var mid := p0 + dir * ((t + t1) * 0.5)
			if not _skipped(mid.x if absf(dir.x) > 0.5 else mid.z, skip, 0.2) or float(ry) > 3.6:
				b.vbox(Vector3(mid.x, y + float(ry), mid.z) + inward * 0.02, Vector3(t1 - t, 0.06, 0.03), col, face, {"shadows": false})
				var r := t + 0.3
				while r < t1:
					var rp := p0 + dir * r
					b.vsphere(Vector3(rp.x, y + float(ry) + 0.1, rp.z) + inward * 0.03, Vector3(0.05, 0.05, 0.03), RIVET, face, {"shadows": false})
					r += 0.6
			t = t1
	var v := pitch * 0.5
	while v < length:
		var p := p0 + dir * v
		if not _skipped(p.x if absf(dir.x) > 0.5 else p.z, skip, 0.3):
			b.vbox(Vector3(p.x, y + top * 0.5, p.z) + inward * 0.02, Vector3(0.05, top, 0.03), col, face, {"shadows": false})
		v += pitch


## A paper notice pinned to a wall: sheet, a few ink lines, a brass pin. normal = into the room.
static func notice(b: Builder, pos: Vector3, normal: Vector3, w: float = 0.42, h: float = 0.56, tilt: float = 0.0) -> void:
	var face := Basis.looking_at(-normal, Vector3.UP) * Basis(Vector3(0, 0, 1), tilt)
	b.vbox(pos + normal * 0.012, Vector3(w, h, 0.012), b.vary(Color("e9dfc6"), 0.04), face, {"shadows": false})
	b.vbox(pos + normal * 0.02 + face * Vector3(0, h * 0.34, 0), Vector3(w * 0.7, 0.045, 0.01), Color("5a4a44"), face, {"shadows": false})
	for i in 3:
		b.vbox(pos + normal * 0.02 + face * Vector3(-w * 0.08, h * (0.12 - float(i) * 0.14), 0), Vector3(w * (0.72 - float(i % 2) * 0.18), 0.02, 0.01), Color("7a6a60"), face, {"shadows": false})
	b.vsphere(pos + normal * 0.03 + face * Vector3(0, h * 0.44, 0), Vector3(0.05, 0.05, 0.03), BRASS, face, {"shadows": false})


## A miner's work jacket hanging from a wall hook (shoulders, body, two sleeves, pocket) with an optional
## hard hat on the hook above. normal = into the room.
static func work_jacket(b: Builder, hook: Vector3, normal: Vector3, col: Color, hat: bool = true) -> void:
	var face := Basis.looking_at(-normal, Vector3.UP)
	var o := {"shadows": false}
	b.vbox(hook + normal * 0.08, Vector3(0.05, 0.05, 0.16), IRON_DARK, face, o)
	var flat := face * Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.55))
	taper(b, hook + normal * 0.15 + Vector3.DOWN * 0.55, 0.3, 0.22, 0.85, col, flat)
	b.vsphere(hook + normal * 0.14 + Vector3.DOWN * 0.12, Vector3(0.5, 0.18, 0.26), col.darkened(0.06), face)
	for s in [-1.0, 1.0]:
		taper(b, hook + normal * 0.2 + face * Vector3(s * 0.25, -0.45, 0), 0.07, 0.09, 0.7, col.darkened(0.08), face * Basis(Vector3(0, 0, 1), s * 0.08))
	b.vbox(hook + normal * 0.27 + face * Vector3(0.1, -0.62, 0), Vector3(0.14, 0.12, 0.02), col.darkened(0.25), face, o)
	b.vbox(hook + normal * 0.26 + face * Vector3(0, -0.5, 0), Vector3(0.5, 0.05, 0.02), Color("e8c860"), face, o)
	if hat:
		b.vsphere(hook + normal * 0.16 + Vector3.UP * 0.2, Vector3(0.34, 0.2, 0.34), Color("e0a83a"), Basis.IDENTITY)
		b.vcyl(hook + normal * 0.16 + Vector3.UP * 0.12, 0.23, 0.03, Color("c8902e"), Basis.IDENTITY, o)


## A plank shelf on two iron brackets with tins, jars and a folded cloth. normal = into the room.
static func wall_shelf(b: Builder, pos: Vector3, normal: Vector3, length: float = 1.6) -> void:
	var face := Basis.looking_at(-normal, Vector3.UP)
	var o := {"shadows": false}
	b.vbox(pos + normal * 0.16, Vector3(length, 0.05, 0.3), b.vary(TIMBER, 0.05), face, OUT)
	for s in [-1.0, 1.0]:
		b.vbox(pos + normal * 0.12 + face * Vector3(s * (length * 0.5 - 0.15), -0.12, 0), Vector3(0.04, 0.22, 0.22), IRON_DARK, face, o)
	var cols := [Color("b8764a"), Color("5f8a9a"), Color("c9a25a"), Color("8a5a3c"), Color("7d8898")]
	var n := int(length / 0.3)
	for i in n:
		var x := -length * 0.5 + 0.18 + float(i) * (length - 0.36) / float(maxi(n - 1, 1))
		var hh := 0.14 + float((i * 5) % 3) * 0.05
		b.vcyl(pos + normal * 0.16 + face * Vector3(x, 0.025 + hh * 0.5, 0), 0.06 + float(i % 2) * 0.015, hh, cols[i % cols.size()], Basis.IDENTITY, {"shadows": false, "segments": 10})
