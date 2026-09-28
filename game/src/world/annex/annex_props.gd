extends RefCounted
## Prop factories for Tobin's Lost Shift. Like src/world/below/below_props.gd: repeated shapes are batched
## through the Below builder (b: one MultiMesh per mesh/material per room, shared tint material), anything
## that moves or reads as a node (Tobin's locker door, the dropped lamp, labels) is a small node tree built
## from the shared Mat/Kit caches. Props that the player could bump into get simple box collision.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const BelowProps := preload("res://src/world/below/below_props.gd")

const LOCKER := Color("5f6d63")          # painted shift lockers, a tired green-grey
const LOCKER_ALT := Color("6b6e5f")
const LOCKER_DARK := Color("2d302c")
const CHALK := Color("e4dccb")
const SLATE := Color("2f3432")
const SCRATCH := Color("d8cbb0")
const SCUFF := Color("2a211c")
const BRASS := Color("c9a14e")
const WATER := Color(0.36, 0.52, 0.5, 0.62)
const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"

const LOCKER_W := 0.62
const LOCKER_D := 0.5
const LOCKER_H := 1.95
const NO_SHADOW := {"shadows": false}

static var _font: Font = null


static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


## A flat text label (not billboarded) for chalk and name plates. Faces +Z of `basis`.
static func label(parent: Node3D, text: String, pos: Vector3, basis: Basis, size: int = 32, color: Color = CHALK, pixel: float = 0.0035) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	l.transform = Transform3D(basis, pos)
	return l


# --- Lockers -------------------------------------------------------------------------------------------

## One batched shift locker standing on the floor at `pos` (centre of its footprint), front facing `facing`.
static func locker(b: Builder, pos: Vector3, facing: Vector3, dented: bool = false) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)     # local +Z = facing (the door side)
	var col := b.vary(b.pick([LOCKER, LOCKER_ALT]), 0.06)
	var c := pos + Vector3(0, LOCKER_H * 0.5, 0)
	b.vbox(c, Vector3(LOCKER_W - 0.03, LOCKER_H, LOCKER_D), col, basis, {"outline": true, "outline_w": 0.012})
	var front := c + facing * (LOCKER_D * 0.5 + 0.012)
	# door panel, vents, handle, number plate
	var door_basis := basis if not dented else basis * Basis(Vector3(0, 1, 0), 0.06)
	b.vbox(front, Vector3(LOCKER_W - 0.12, LOCKER_H - 0.14, 0.02), col.lightened(0.07), door_basis, NO_SHADOW)
	for i in 3:
		b.vbox(front + basis * Vector3(0, LOCKER_H * 0.36 - float(i) * 0.07, 0.012), Vector3(LOCKER_W * 0.5, 0.025, 0.01), LOCKER_DARK, basis, NO_SHADOW)
	b.vbox(front + basis * Vector3(LOCKER_W * 0.3, 0.0, 0.02), Vector3(0.04, 0.16, 0.03), Color("8d8a80"), basis, NO_SHADOW)
	b.vbox(front + basis * Vector3(0.0, LOCKER_H * 0.44, 0.015), Vector3(0.16, 0.07, 0.01), CHALK.darkened(0.15), basis, NO_SHADOW)


## A bank of lockers against a wall at x = wall_x (running along z), fronts facing `side` (+1 = +x, -1 = -x).
## Positions are centred on `z_ref` + k * LOCKER_W for every k whose locker lies in [z_min, z_max] and outside
## the `skip` spans ([[z_from, z_to], ...]) and not at z_ref itself when `leave_ref` (a node locker goes there).
## Collision: one box per contiguous run, from the wall to the locker fronts. Returns the z centres used.
static func locker_row(b: Builder, wall_x: float, side: float, z_ref: float, z_min: float, z_max: float, skip: Array, leave_ref: bool = false) -> Array:
	var used: Array = []
	var facing := Vector3(side, 0, 0)
	var x := wall_x + side * (0.25 + LOCKER_D * 0.5)
	var k_lo := int(ceilf((z_min + LOCKER_W * 0.5 - z_ref) / LOCKER_W))
	var k_hi := int(floorf((z_max - LOCKER_W * 0.5 - z_ref) / LOCKER_W))
	for k in range(k_lo, k_hi + 1):
		var z := z_ref + float(k) * LOCKER_W
		var blocked := false
		for s in skip:
			if z + LOCKER_W * 0.5 > float(s[0]) and z - LOCKER_W * 0.5 < float(s[1]):
				blocked = true
		if blocked:
			continue
		used.append(z)
		if leave_ref and k == 0:
			continue
		locker(b, Vector3(x, 0.0, z), facing, b.rng.randf() < 0.12)
	# collision runs (the node locker at z_ref is part of its run)
	used.sort()
	var run_start := -INF
	var prev := -INF
	for i in used.size() + 1:
		var z: float = used[i] if i < used.size() else INF
		if run_start == -INF:
			run_start = z
		elif z - prev > LOCKER_W * 1.5:
			var z0 := run_start - LOCKER_W * 0.5
			var z1 := prev + LOCKER_W * 0.5
			var depth := 0.25 + LOCKER_D
			b.col_box(Vector3(wall_x + side * depth * 0.5, LOCKER_H * 0.5, (z0 + z1) * 0.5), Vector3(depth, LOCKER_H, z1 - z0), "wood")
			run_start = z
		prev = z
	return used


## Tobin's own locker as a node: the door swings open (set_open) to show his letter. Origin = footprint
## centre on the floor, +Z = facing (door side). Returns {"root", "door_pivot", "letter"}.
static func tobin_locker(parent: Node3D, pos: Vector3, facing: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "TobinLocker"
	parent.add_child(root)
	root.transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), pos)
	var body_mat := Mat.outlined(Mat.toon(LOCKER.lightened(0.04), {"rim": 0.25, "noise": 0.12}), 0.012)
	var inner_mat := Mat.toon(LOCKER_DARK)
	var h := LOCKER_H
	# carcass: back, sides, top, bottom (open at the front)
	Kit.add(root, Kit.box(Vector3(LOCKER_W - 0.03, h, 0.03), body_mat), Vector3(0, h * 0.5, -LOCKER_D * 0.5 + 0.015))
	for sx: float in [-1.0, 1.0]:
		Kit.add(root, Kit.box(Vector3(0.03, h, LOCKER_D), body_mat), Vector3(sx * (LOCKER_W * 0.5 - 0.03), h * 0.5, 0))
	Kit.add(root, Kit.box(Vector3(LOCKER_W - 0.03, 0.03, LOCKER_D), body_mat), Vector3(0, h - 0.015, 0))
	Kit.add(root, Kit.box(Vector3(LOCKER_W - 0.03, 0.03, LOCKER_D), body_mat), Vector3(0, 0.015, 0))
	Kit.add(root, Kit.box(Vector3(LOCKER_W - 0.1, h - 0.1, 0.01), inner_mat), Vector3(0, h * 0.5, -LOCKER_D * 0.5 + 0.035))
	# a shelf, a folded scarf and the letter
	Kit.add(root, Kit.box(Vector3(LOCKER_W - 0.08, 0.025, LOCKER_D - 0.08), body_mat), Vector3(0, 1.42, 0))
	Kit.add(root, Kit.box(Vector3(0.38, 0.1, 0.28), Mat.toon(Color("a8574a"))), Vector3(0, 1.49, -0.04))
	var letter := Kit.add(root, Kit.box(Vector3(0.2, 0.012, 0.26), Mat.toon(BelowProps.PAPER, {"emission": BelowProps.PAPER, "emission_energy": 0.18})), Vector3(0.02, 1.45, 0.12), Vector3(0, 12, 0))
	# door on a hinge at the -x edge
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	root.add_child(pivot)
	pivot.position = Vector3(-LOCKER_W * 0.5 + 0.02, 0, LOCKER_D * 0.5 + 0.01)
	var door_mat := Mat.outlined(Mat.toon(LOCKER.lightened(0.1), {"rim": 0.25, "noise": 0.12}), 0.012)
	Kit.add(pivot, Kit.box(Vector3(LOCKER_W - 0.05, h - 0.06, 0.025), door_mat), Vector3(LOCKER_W * 0.5 - 0.02, h * 0.5, 0))
	var dark := Mat.toon(LOCKER_DARK)
	for i in 3:
		Kit.add(pivot, Kit.box(Vector3(LOCKER_W * 0.5, 0.025, 0.01), dark), Vector3(LOCKER_W * 0.5, h * 0.86 - float(i) * 0.07, 0.016))
	Kit.add(pivot, Kit.box(Vector3(0.04, 0.16, 0.03), Mat.toon(Color("8d8a80"))), Vector3(LOCKER_W * 0.8, h * 0.5, 0.025))
	Kit.add(pivot, Kit.box(Vector3(0.24, 0.09, 0.01), Mat.toon(BRASS, {"rim": 0.5})), Vector3(LOCKER_W * 0.5, h * 0.93, 0.016))
	var plate := label(pivot, "9  TOBIN", Vector3(LOCKER_W * 0.5, h * 0.93, 0.024), Basis.IDENTITY, 24, Color("3a2a1a"), 0.0022)
	plate.name = "NamePlate"
	# collision: the whole locker footprint (the open door never blocks the hall much)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(LOCKER_W, h, LOCKER_D + 0.5)
	cs.shape = bx
	cs.position = Vector3(0, h * 0.5, -0.25)
	body.add_child(cs)
	root.add_child(body)
	return {"root": root, "door_pivot": pivot, "letter": letter}


# --- Furniture & clutter ---------------------------------------------------------------------------------

## A plank bench along `axis` ("x" or "z"), `length` long, seat 0.45 m high. Collision included.
static func bench(b: Builder, pos: Vector3, length: float, axis: String = "z") -> void:
	var size := Vector3(0.38, 0.07, length) if axis == "z" else Vector3(length, 0.07, 0.38)
	b.vbox(pos + Vector3(0, 0.44, 0), size, b.vary(BelowProps.PLANK, 0.06), Basis.IDENTITY, BelowProps.OUT)
	for s: float in [-1.0, 1.0]:
		var off := Vector3(0, 0.2, s * (length * 0.5 - 0.15)) if axis == "z" else Vector3(s * (length * 0.5 - 0.15), 0.2, 0)
		b.vbox(pos + off, Vector3(0.3, 0.4, 0.07) if axis == "z" else Vector3(0.07, 0.4, 0.3), BelowProps.TIMBER_DARK, Basis.IDENTITY, NO_SHADOW)
	b.col_box(pos + Vector3(0, 0.24, 0), Vector3(size.x, 0.48, size.z), "wood")


## A slate chalk board on a wall (centre `pos`, facing `facing`) with a chalk heading and lines of chalk.
static func chalk_board(b: Builder, parent: Node3D, pos: Vector3, facing: Vector3, heading: String, w: float = 1.5, h: float = 1.0) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	b.vbox(pos, Vector3(w + 0.1, h + 0.1, 0.05), BelowProps.TIMBER, basis, BelowProps.OUT)
	b.vbox(pos + facing * 0.03, Vector3(w, h, 0.02), SLATE, basis, NO_SHADOW)
	for i in 6:
		var lw := w * (0.55 + 0.35 * float((i * 37) % 5) / 4.0)
		b.vbox(pos + facing * 0.045 + basis * Vector3(-w * 0.5 + 0.1 + lw * 0.5, h * 0.18 - float(i) * 0.12, 0), Vector3(lw, 0.018, 0.005), CHALK.darkened(0.1), basis, NO_SHADOW)
	label(parent, heading, pos + facing * 0.05 + basis * Vector3(0, h * 0.36, 0), basis, 40, CHALK, 0.004)


## Dark scuffs on the floor (a pick dragged across the stone): short streaks along an arc around `center`.
static func scuffs(b: Builder, center: Vector3, radius: float, count: int, y: float) -> void:
	for i in count:
		var a := b.rng.randf() * TAU
		var r := b.rng.randf_range(radius * 0.4, radius)
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var basis := Basis(Vector3.UP, a + PI * 0.5 + b.rng.randf_range(-0.3, 0.3))
		b.vbox(Vector3(p.x, y + 0.012, p.z), Vector3(0.06, 0.012, b.rng.randf_range(0.6, 1.2)), SCUFF, basis, NO_SHADOW)


## Lamp rack on a wall: a shelf with hooks; `lamps` small dark-glass lanterns hang from it, one hook is empty.
static func lamp_rack(b: Builder, pos: Vector3, facing: Vector3, hooks: int = 4, empty_hook: int = 2) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	var w := 0.42 * float(hooks)
	b.vbox(pos, Vector3(w, 0.08, 0.2), BelowProps.TIMBER, basis, BelowProps.OUT)
	for i in hooks:
		var p := pos + basis * Vector3(-w * 0.5 + 0.21 + float(i) * 0.42, -0.08, 0.06)
		b.vbox(p, Vector3(0.02, 0.1, 0.02), BelowProps.IRON, basis, NO_SHADOW)
		if i == empty_hook:
			continue
		b.vcyl(p + Vector3(0, -0.22, 0), 0.07, 0.2, Color("3d3a3a"), Basis.IDENTITY, NO_SHADOW)
		b.vcone(p + Vector3(0, -0.08, 0), 0.08, 0.08, BelowProps.IRON, Basis.IDENTITY, NO_SHADOW)
		b.vglow(Builder.unit_sphere(), Transform3D(Basis.IDENTITY.scaled_local(Vector3.ONE * 0.1), p + Vector3(0, -0.22, 0)), Color("8a5a2a"), 0.6)


## The sluice gate set into a wall at `pos` (floor, wall face), the gate facing `facing` (into the room).
static func sluice_gate(b: Builder, parent: Node3D, pos: Vector3, facing: Vector3, width: float = 2.4) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	var side := basis.x
	for s: float in [-1.0, 1.0]:
		var pp := pos + side * (s * (width * 0.5 + 0.12)) + facing * 0.12
		b.vbox(pp + Vector3(0, 1.6, 0), Vector3(0.3, 3.2, 0.3), b.vary(BelowProps.TIMBER, 0.05), basis, BelowProps.OUT)
		b.col_box(pp + Vector3(0, 1.6, 0), Vector3(0.3, 3.2, 0.3), "wood", basis)
	b.vbox(pos + facing * 0.12 + Vector3(0, 3.1, 0), Vector3(width + 0.6, 0.3, 0.34), BelowProps.TIMBER, basis, BelowProps.OUT)
	# the gate itself: vertical planks, raised a hand's width so water runs out under it
	for i in 6:
		var x := -width * 0.5 + width / 6.0 * (float(i) + 0.5)
		b.vbox(pos + facing * 0.06 + side * x + Vector3(0, 1.35, 0), Vector3(width / 6.0 - 0.02, 2.3, 0.1), b.vary(BelowProps.PLANK.darkened(0.25), 0.08), basis, NO_SHADOW)
	for y: float in [0.55, 1.4, 2.2]:
		b.vbox(pos + facing * 0.12 + Vector3(0, y, 0), Vector3(width + 0.05, 0.08, 0.03), BelowProps.IRON, basis, NO_SHADOW)
	# the wheel and its spindle
	var wheel_c := pos + facing * 0.34 + Vector3(0, 2.75, 0)
	b.batch(_torus(), BelowProps.tint(), Transform3D((basis * Basis(Vector3(1, 0, 0), PI * 0.5)).scaled_local(Vector3(0.42, 0.4, 0.42)), wheel_c), BelowProps.IRON)
	for i in 3:
		b.vbox(wheel_c, Vector3(0.78, 0.04, 0.04), BelowProps.IRON, basis * Basis(Vector3(0, 0, 1), float(i) * PI / 3.0), NO_SHADOW)
	b.vcyl(pos + facing * 0.22 + Vector3(0, 2.75, 0), 0.04, 0.3, BelowProps.IRON, basis * Basis(Vector3(1, 0, 0), PI * 0.5), NO_SHADOW)
	# water spilling out under the gate (a thin sheen)
	var spill := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, 0.6)
	spill.mesh = pm
	spill.material_override = Mat.transparent(Color(0.62, 0.78, 0.76, 0.5), true)
	spill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(spill)
	spill.transform = Transform3D(basis * Basis(Vector3(1, 0, 0), -0.55), pos + facing * 0.3 + Vector3(0, 0.14, 0))


static func _torus() -> Mesh:
	return BelowProps.torus_mesh()


## A ladder against a wall: rails from `foot` up to `top_y`, rungs every 0.34 m, facing `facing`.
static func ladder(b: Builder, foot: Vector3, top_y: float, facing: Vector3) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	var h := top_y - foot.y
	for s: float in [-0.28, 0.28]:
		b.vbox(foot + basis * Vector3(s, 0, 0) + Vector3(0, h * 0.5, 0), Vector3(0.08, h, 0.08), BelowProps.TIMBER, basis, BelowProps.OUT)
	var n := int(h / 0.34)
	for i in n:
		b.vbox(foot + Vector3(0, 0.3 + float(i) * 0.34, 0), Vector3(0.56, 0.05, 0.06), BelowProps.PLANK, basis, NO_SHADOW)


## The scrawled lantern mark (Chapter Two clue): a lantern outline scratched into the wall at `pos`
## (centre of the drawing on the wall face), three little flames under it, an arrow pointing up ("north,
## past the woods") and Tobin's scratched words. Faces `facing`.
static func lantern_mark(b: Builder, parent: Node3D, pos: Vector3, facing: Vector3) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	var o := pos + facing * 0.012
	var t := 0.035
	var strokes: Array = [
		# [centre (local x, y), length, angle (deg, 0 = horizontal)]
		[Vector2(0.0, -0.3), 0.42, 0.0],          # base
		[Vector2(-0.24, 0.0), 0.62, 82.0],         # left side (tapering)
		[Vector2(0.24, 0.0), 0.62, 98.0],          # right side
		[Vector2(0.0, 0.3), 0.52, 0.0],            # top rim
		[Vector2(-0.12, 0.42), 0.26, 45.0],        # roof
		[Vector2(0.12, 0.42), 0.26, -45.0],
		[Vector2(-0.08, 0.6), 0.2, 70.0],          # handle loop
		[Vector2(0.08, 0.6), 0.2, 110.0],
		[Vector2(-0.05, 0.02), 0.16, 60.0],        # the flame inside
		[Vector2(0.05, 0.02), 0.16, 120.0],
		[Vector2(-0.42, 0.05), 0.18, 20.0],        # rays
		[Vector2(0.42, 0.05), 0.18, -20.0],
		[Vector2(-0.4, 0.3), 0.16, -30.0],
		[Vector2(0.4, 0.3), 0.16, 30.0],
		[Vector2(0.72, 0.1), 0.62, 90.0],          # the arrow, pointing up
		[Vector2(0.66, 0.36), 0.16, -50.0],
		[Vector2(0.78, 0.36), 0.16, 50.0],
	]
	for f in 3:
		var fx := -0.22 + float(f) * 0.22
		strokes.append([Vector2(fx - 0.025, -0.52), 0.12, 65.0])
		strokes.append([Vector2(fx + 0.025, -0.52), 0.12, 115.0])
	for s in strokes:
		var c: Vector2 = s[0]
		var rot := Basis(Vector3(0, 0, 1), deg_to_rad(float(s[2])))
		b.vbox(o + basis * Vector3(c.x, c.y, 0), Vector3(float(s[1]), t, 0.01), SCRATCH, basis * rot, NO_SHADOW)
	label(parent, "where the lanterns wake", o + basis * Vector3(0.1, -0.78, 0.004), basis, 30, SCRATCH, 0.0036)


## The lantern Tobin dropped: an old brass miner's lamp lying on its side (node, hidden once taken).
static func dropped_lamp(parent: Node3D, pos: Vector3, yaw_deg: float = 30.0) -> Node3D:
	var root := Node3D.new()
	root.name = "DroppedLamp"
	parent.add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	var tilt := Node3D.new()
	root.add_child(tilt)
	tilt.position = Vector3(0, 0.13, 0)
	tilt.rotation_degrees = Vector3(0, 0, 84)
	var brass := Mat.outlined(Mat.toon(BRASS, {"rim": 0.5, "specular": 0.4}), 0.012)
	var iron := Mat.outlined(Mat.toon(BelowProps.IRON, {"rim": 0.4}), 0.012)
	Kit.add(tilt, Kit.cylinder(0.12, 0.14, 0.05, brass, 12), Vector3(0, -0.14, 0))
	Kit.add(tilt, Kit.cylinder(0.1, 0.1, 0.24, Mat.transparent(Color(0.9, 0.8, 0.6, 0.3), true), 12), Vector3(0, 0.0, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		Kit.add(tilt, Kit.box(Vector3(0.025, 0.26, 0.025), brass), Vector3(cos(a) * 0.1, 0.0, sin(a) * 0.1))
	Kit.add(tilt, Kit.cone(0.13, 0.12, brass, 12), Vector3(0, 0.18, 0))
	Kit.add(tilt, Kit.torus(0.02, 0.05, iron), Vector3(0, 0.27, 0), Vector3(90, 0, 0))
	# a little spill of old soot on the stone
	Kit.add(root, Kit.cylinder(0.3, 0.3, 0.01, Mat.toon(SCUFF), 14), Vector3(0.1, 0.006, 0.05))
	return root


## Shallow running water: a flat transparent sheet over the channel floor (visual only).
static func water_sheet(parent: Node3D, x0: float, x1: float, z0: float, z1: float, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "ChannelWater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	mi.mesh = pm
	mi.material_override = Mat.transparent(WATER, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	return mi
