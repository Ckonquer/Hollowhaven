extends RefCounted
## The Silk Hollows: Webbed Passage (webs densify toward the chamber), the optional Nursery, the
## checkpoint antechamber and the round Heartseed Chamber (boss arena, ~22 m, high domed ceiling with
## a deep crack). Violet-grey rock, faint sickly glows. All spider dressing goes through `decor`
## (spider_decor.gd), which builds pale roots instead when arachnophobia mode is on.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")

const ROCK := Color("4d4758")
const ROCK_DARK := Color("2e2a38")
const ROCK_MID := Color("3d3848")
const GLOW := Color("b3e08b")


static func rock_cols() -> Array:
	return [ROCK, ROCK_MID, ROCK.lerp(Color("5a4f6a"), 0.4), ROCK_DARK.lightened(0.08)]


static func build(b: Builder, area: Node3D, decor: Node3D) -> void:
	_passage(b, area, decor, "webbed", 0.3, 0.6)
	_passage(b, area, decor, "junction", 0.6, 0.7)
	_passage(b, area, decor, "webbed2", 0.75, 1.0)
	_nursery(b, area, decor)
	_antechamber(b, area, decor)
	_arena(b, area, decor)


## Web placement for one straight room: upper-corner webs along both long walls, ceiling sheets,
## strands. d0 -> d1 = density at the start / end of the room (along its long axis).
static func _webs_for_room(b: Builder, decor: Node3D, id: String, d0: float, d1: float) -> void:
	var r: Dictionary = Layout.ROOMS[id]
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	var y: float = float(r["y"])
	var h: float = float(r["h"])
	var along_x := (x1 - x0) >= (z1 - z0)
	var length := (x1 - x0) if along_x else (z1 - z0)
	var steps := int(length / 2.6)
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var dens := lerpf(d0, d1, t)
		if b.rng.randf() > 0.35 + dens * 0.6:
			continue
		var a := (x0 + (x1 - x0) * t) if along_x else (z0 + (z1 - z0) * t)
		for side in [-1.0, 1.0]:
			if b.rng.randf() > 0.45 + dens * 0.5:
				continue
			var p: Vector3
			var n: Vector3
			if along_x:
				var wz := z0 + 0.5 if side < 0.0 else z1 - 0.5
				p = Vector3(a, y + h - 0.9, wz)
				n = Vector3(0, -0.7, -side).normalized()
			else:
				var wx := x0 + 0.5 if side < 0.0 else x1 - 0.5
				p = Vector3(wx, y + h - 0.9, a)
				n = Vector3(-side, -0.7, 0).normalized()
			decor.add_web(p, n, lerpf(1.6, 3.0, dens) * b.rng.randf_range(0.8, 1.15), dens, Vector2(0.5 + side * 0.18, 0.3))
		if dens > 0.55 and b.rng.randf() < dens * 0.5:
			var cp := Vector3(a, y + h - 0.25, (z0 + z1) * 0.5 + b.rng.randf_range(-1.0, 1.0)) if along_x else Vector3((x0 + x1) * 0.5 + b.rng.randf_range(-1.0, 1.0), y + h - 0.25, a)
			decor.add_sheet(cp, Vector2(3.0, 3.0) * lerpf(0.8, 1.3, dens), dens)
		if b.rng.randf() < 0.35 + dens * 0.4:
			var sp := Vector3(a + b.rng.randf_range(-0.8, 0.8), y + h - 0.3, b.rng.randf_range(z0 + 0.8, z1 - 0.8)) if along_x else Vector3(b.rng.randf_range(x0 + 0.8, x1 - 0.8), y + h - 0.3, a + b.rng.randf_range(-0.8, 0.8))
			decor.add_strand(sp, Vector3(sp.x + b.rng.randf_range(-0.3, 0.3), y + b.rng.randf_range(0.8, 3.0), sp.z + b.rng.randf_range(-0.3, 0.3)))


static func _sickly_nodules(b: Builder, p: Vector3, count: int, spread: float) -> void:
	for i in count:
		var a := b.rng.randf() * TAU
		var r := b.rng.randf_range(0.0, spread)
		var s := b.rng.randf_range(0.04, 0.11)
		b.vglow(Builder.unit_blob(i, true), Transform3D(Basis.IDENTITY.scaled_local(Vector3(s, s * 0.8, s)), p + Vector3(cos(a) * r, s * 0.4, sin(a) * r)), GLOW, 1.3)


static func _passage(b: Builder, area: Node3D, decor: Node3D, id: String, d0: float, d1: float) -> void:
	var n := b.begin(id)
	var r: Dictionary = Layout.ROOMS[id]
	var cols := rock_cols()
	b.shell(id, ROCK_MID, ROCK_DARK, ROCK_DARK)
	b.dress_room_rock(id, cols, {"size": 1.45, "spacing": 1.5, "protrude": 0.3})
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	var y: float = float(r["y"])
	var h: float = float(r["h"])
	b.ceiling_lumps(x0, x1, z0, z1, y + h, [ROCK_DARK, ROCK_MID], int((x1 - x0) * (z1 - z0) / 12.0), 1.4)
	b.pebbles(x0 + 0.4, x1 - 0.4, z0 + 0.4, z1 - 0.4, y, cols, int((x1 - x0) * (z1 - z0) / 4.0), 0.14)
	_webs_for_room(b, decor, id, d0, d1)
	# Sickly glows at the wall foot (light the path faintly)
	var along_x := (x1 - x0) >= (z1 - z0)
	var length := (x1 - x0) if along_x else (z1 - z0)
	var k := 0
	var t := 3.0
	while t < length - 1.0:
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := Vector3(x0 + t, y, (z0 + 0.6) if side < 0.0 else (z1 - 0.6)) if along_x else Vector3((x0 + 0.6) if side < 0.0 else (x1 - 0.6), y, z0 + t)
		_sickly_nodules(b, p, 7, 0.45)
		if k % 2 == 0:
			Props.glow_light(n, p + Vector3(0, 0.5, 0), GLOW, 0.45, 3.4)
		t += 5.5
		k += 1
	match id:
		"webbed":
			# Faint glow near where the first shape clings, so it reads from the entrance.
			Props.glow_light(n, Vector3(96.5, -5.2, -84.2), Color("c9d9a8"), 0.7, 6.0)
			decor.add_egg_sac(Vector3(98.9, -10.0, -88.6), 0.45)
		"junction":
			decor.add_cocoon(Vector3(102.3, -3.1, -90.5), 2.4, 0.42)
			decor.add_cocoon(Vector3(108.6, -3.1, -83.0), 2.0, 0.38)
			decor.add_egg_sac(Vector3(109.2, -10.0, -81.2), 0.55)
			Props.glow_light(n, Vector3(105.0, -6.5, -86.0), Color("8a7fa8"), 0.5, 9.0)
		"webbed2":
			decor.add_cocoon(Vector3(102.5, -3.1, -97.5), 2.6, 0.45)
			decor.add_cocoon(Vector3(107.6, -3.1, -104.0), 2.2, 0.4)
			decor.add_cocoon(Vector3(102.8, -3.1, -108.4), 1.8, 0.35)
			decor.add_egg_sac(Vector3(107.8, -10.0, -94.0), 0.5)
			decor.add_egg_sac(Vector3(102.3, -10.0, -103.0), 0.4)
			Props.glow_light(n, Vector3(105.0, -6.5, -101.0), Color("8a7fa8"), 0.45, 9.0)


static func _nursery(b: Builder, area: Node3D, decor: Node3D) -> void:
	var nw := b.begin("nursery_way")
	var cols := rock_cols()
	b.shell("nursery_way", ROCK_MID, ROCK_DARK, ROCK_DARK)
	b.dress_room_rock("nursery_way", cols, {"size": 0.9})
	decor.add_web(Vector3(104.75, -7.3, -78.0), Vector3(0, 0, 1), 2.6, 0.5, Vector2(0.5, 0.2))
	var _u := nw
	var n := b.begin("nursery")
	b.shell("nursery", ROCK_MID, ROCK_DARK, ROCK_DARK)
	b.dress_room_rock("nursery", cols, {"size": 1.3, "protrude": 0.3})
	b.ceiling_lumps(97.5, 112.5, -75.5, -64.5, -5.0, [ROCK_DARK, ROCK_MID], 16, 1.2)
	b.pebbles(97.5, 112.5, -75.5, -64.5, -10.0, cols, 50, 0.14)
	# Clutches of egg sacs (root knots in arachnophobia mode) around the walls; the centre stays open.
	var sacs := [Vector3(98.3, -10, -70.5), Vector3(99.5, -10, -66.0), Vector3(102.0, -10, -65.0), Vector3(108.5, -10, -65.2),
		Vector3(111.8, -10, -67.5), Vector3(112.0, -10, -73.8), Vector3(109.8, -10, -75.0), Vector3(100.2, -10, -75.1)]
	for i in sacs.size():
		var sp: Vector3 = sacs[i]
		decor.add_egg_sac(sp, 0.45 + float(i % 3) * 0.12)
		_sickly_nodules(b, sp, 5, 0.9)
	for c in [Vector3(101.0, -5.1, -69.0), Vector3(107.5, -5.1, -70.5), Vector3(104.0, -5.1, -66.5)]:
		decor.add_cocoon(c, 1.4, 0.35)
	for i in 6:
		var wp := Vector3(b.rng.randf_range(98.0, 112.0), -5.8, -75.2 if i % 2 == 0 else -64.8)
		decor.add_web(wp, Vector3(0, -0.6, 1.0 if i % 2 == 0 else -1.0), b.rng.randf_range(1.8, 2.6), 0.8)
	decor.add_sheet(Vector3(105.0, -5.2, -70.0), Vector2(4.0, 4.0), 0.9)
	Props.glow_light(n, Vector3(100.0, -8.5, -68.0), GLOW, 0.5, 6.0)
	Props.glow_light(n, Vector3(110.5, -8.5, -71.5), GLOW, 0.45, 6.0)


static func _antechamber(b: Builder, area: Node3D, decor: Node3D) -> void:
	var n := b.begin("antechamber")
	var cols := rock_cols()
	b.shell("antechamber", ROCK_MID, ROCK_DARK, ROCK_DARK)
	b.dress_room_rock("antechamber", cols, {"size": 1.1})
	b.ceiling_lumps(100.5, 109.5, -117.5, -110.5, -5.0, [ROCK_DARK, ROCK_MID], 8, 1.0)
	b.pebbles(100.5, 109.5, -117.5, -110.5, -10.0, cols, 30, 0.14)
	# The miners' last camp: a bedroll, a crate, the page caught near the arena mouth
	Props.crate(b, Vector3(109.2, -10.0, -113.0), 0.7, 18.0)
	b.vbox(Vector3(108.6, -9.95, -116.4), Vector3(0.8, 0.1, 1.8), Color("7a5a5a"), Basis(Vector3.UP, 0.2), {})
	decor.add_web(Vector3(100.6, -5.8, -117.5), Vector3(0.6, -0.6, 0.5), 2.2, 0.7)
	decor.add_web(Vector3(109.4, -5.8, -117.5), Vector3(-0.6, -0.6, 0.5), 2.0, 0.7)
	decor.add_strand(Vector3(106.5, -5.0, -117.0), Vector3(106.8, -8.0, -117.2))
	_sickly_nodules(b, Vector3(101.0, -10.0, -111.0), 6, 0.5)
	# A small breather before the chamber: a few glowcaps keep it readable even before the lantern is lit
	Props.glowcaps(b, n, Vector3(100.8, -10.0, -112.4), 6, 0.35, 0.6, 3.2)
	Props.glowcaps(b, n, Vector3(109.2, -10.0, -117.2), 5, 0.3, 0.5, 3.0)
	# Ramp down into the chamber
	b.begin("arena_way")
	b.floor_rect(102.5, 107.5, -119.0, -118.0, -10.0, ROCK_MID)
	b.ramp(Vector3(105.0, -10.0, -119.0), Vector3(105.0, -12.0, -125.0), 5.0, ROCK_MID)
	b.floor_rect(102.5, 107.5, -127.0, -125.0, -12.0, ROCK_MID)
	b.ceiling_rect(102.5, 107.5, -127.0, -118.0, -5.0, ROCK_DARK)
	b.solid(Vector3(102.0, -8.25, -122.5), Vector3(1.0, 8.5, 9.0), ROCK_DARK)
	b.solid(Vector3(108.0, -8.25, -122.5), Vector3(1.0, 8.5, 9.0), ROCK_DARK)
	for side in [-1.0, 1.0]:
		var wx := 102.5 if side < 0.0 else 107.5
		b.rock_wall(Vector3(wx, -10.0, -118.0), Vector3(wx, -10.0, -121.0), Vector3(-side, 0, 0), 5.0, cols, {"size": 1.0})
		b.rock_wall(Vector3(wx, -11.0, -121.0), Vector3(wx, -11.0, -124.0), Vector3(-side, 0, 0), 5.5, cols, {"size": 1.0})
		b.rock_wall(Vector3(wx, -12.0, -124.0), Vector3(wx, -12.0, -127.0), Vector3(-side, 0, 0), 6.5, cols, {"size": 1.1})
	decor.add_web(Vector3(105.0, -6.0, -121.5), Vector3(0, -0.3, 1.0), 3.0, 0.8, Vector2(0.5, 0.25))
	var _u := n


static func _arena(b: Builder, area: Node3D, decor: Node3D) -> void:
	var n := b.begin("arena")
	var c := Layout.ARENA_CENTER
	var rad := Layout.ARENA_RADIUS
	var cols := rock_cols()
	# Floor: one round collider, a disc and cracked slabs
	b.col_cyl(c + Vector3(0, -0.5, 0), rad + 0.6, 1.0)
	b.vcyl(c + Vector3(0, -0.5, 0), rad + 0.6, 1.0, ROCK_MID, Basis.IDENTITY, {"segments": 40})
	for i in 26:
		var a := b.rng.randf() * TAU
		var rr := b.rng.randf_range(2.5, rad - 0.8)
		var p := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		b.vbox(p + Vector3(0, 0.015, 0), Vector3(b.rng.randf_range(1.0, 2.2), 0.05, b.rng.randf_range(0.8, 1.8)), b.vary(ROCK, 0.08), Basis(Vector3.UP, b.rng.randf() * TAU), {"shadows": false})
	b.pebbles(c.x - rad, c.x + rad, c.z - rad, c.z + rad, c.y, cols, 60, 0.16)
	# Ring wall (skip the south entrance and the east lift recess)
	var segs := 28
	var wall_h := 14.0
	var open: Array = []
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var mid := c + dir * (rad + 0.6)
		open.append((dir.z > 0.5 and absf(mid.x - c.x) < 3.4) or (dir.x > 0.9 and absf(mid.z - c.z) < 1.9))
	for i in segs:
		if bool(open[i]):
			continue
		var a := TAU * float(i) / float(segs)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var mid := c + dir * (rad + 0.6)
		var basis := Basis.looking_at(-dir, Vector3.UP)
		b.solid(mid + Vector3(0, wall_h * 0.5, 0), Vector3(2.9, wall_h, 1.2), ROCK_DARK, "stone", basis)
		var chord_a := c + Vector3(cos(a - PI / float(segs)), 0, sin(a - PI / float(segs))) * rad
		var chord_b := c + Vector3(cos(a + PI / float(segs)), 0, sin(a + PI / float(segs))) * rad
		var opts := {"size": 1.5, "spacing": 1.6, "protrude": 0.25}
		# Next to the entrance and the lift recess: smaller rocks that stop at the opening's edge, so no
		# boulder bulges into the doorway or fills the lift cage (they have no collision; it looked blocked).
		var prev_open := bool(open[(i - 1 + segs) % segs])
		var next_open := bool(open[(i + 1) % segs])
		if prev_open or next_open:
			var chord_len := chord_a.distance_to(chord_b)
			var skip: Array = []
			if prev_open:
				skip.append([0.0, 0.6, 99.0])
			if next_open:
				skip.append([chord_len - 0.6, chord_len, 99.0])
			opts = {"size": 0.7, "spacing": 0.9, "protrude": 0.2, "skip": skip}
		b.rock_wall(chord_a, chord_b, -dir, 7.5, cols, opts)
	# Rock jambs flanking the entrance seal the corners between the ring and the ramp walls
	for sx in [-1.0, 1.0]:
		var jc := Vector3(c.x + sx * 3.5, -6.0, -127.0)
		b.solid(jc, Vector3(2.0, 12.0, 3.0), ROCK_DARK)
		b.vblob(jc + Vector3(-sx * 0.5, -4.5, 0.0), Vector3(1.4, 2.4, 1.9), ROCK_MID)
		b.vblob(jc + Vector3(-sx * 0.4, -1.0, 0.3), Vector3(1.3, 2.0, 1.7), ROCK)
	# Domed ceiling of huge lumps with a deep crack running north
	var rings := [[-4.2, rad + 0.4, 16, 3.2], [-1.6, rad - 2.2, 13, 3.0], [0.6, rad - 5.4, 9, 2.8], [1.8, 2.4, 4, 2.4]]
	for ring in rings:
		var ry: float = float(ring[0])
		var rr: float = float(ring[1])
		var count: int = int(ring[2])
		var size: float = float(ring[3])
		for k in count:
			var a := TAU * (float(k) + b.rng.randf_range(-0.2, 0.2)) / float(count)
			var dir := Vector3(cos(a), 0, sin(a))
			# the crack: a gap in the upper rings toward the north (-z)
			if ry > -3.0 and dir.dot(Vector3(0, 0, -1)) > 0.93:
				continue
			var p := c + dir * rr
			p.y = ry + b.rng.randf_range(-0.4, 0.4)
			var s := size * b.rng.randf_range(0.85, 1.2)
			b.vblob(p, Vector3(s * 1.2, s * 0.9, s * 1.2), b.vary(b.pick([ROCK_DARK, ROCK_MID]), 0.06))
	# Crack: jagged edges and a black void, with a faint violet glow deep inside
	for k in 7:
		var t := float(k) / 6.0
		var p := c + Vector3(b.rng.randf_range(-1.6, 1.6), 0.0, -2.0 - t * 8.0)
		p.y = -1.2 + t * 2.2
		b.vblob(p + Vector3(-1.4, 0, 0), Vector3(0.8, 1.2, 1.1), ROCK_DARK, -1)
		b.vblob(p + Vector3(1.4, 0, 0), Vector3(0.8, 1.2, 1.1), ROCK_DARK, -1)
	b.vbox(c + Vector3(0, 13.8, -6.0), Vector3(4.0, 0.5, 12.0), Color(0.01, 0.01, 0.015), Basis.IDENTITY, {"shadows": false})
	Props.glow_light(n, c + Vector3(0, 13.0, -6.5), Color("7b5ea8"), 0.9, 6.0)
	# Anchor points: silk bundles (root knots) where the boss clings
	for ap in Layout.ARENA_ANCHORS:
		var apv: Vector3 = ap
		decor.add_sheet(apv + Vector3(0, 0.2, 0), Vector2(2.6, 2.6), 1.0)
		decor.add_cocoon(apv + Vector3(0.5, 0.5, 0.3), 1.1, 0.3)
		# Guy lines up into the dome so the bundle hangs from the rock instead of floating in the air
		# (hanging roots in arachnophobia mode).
		for k in 4:
			var ga := TAU * float(k) / 4.0 + 0.4
			var top := apv + Vector3(cos(ga) * 1.1, 3.4 + 0.25 * float(k), sin(ga) * 1.1)
			decor.add_strand(top, apv + Vector3(cos(ga) * 0.9, 0.2, sin(ga) * 0.9))
	# Webs all around the walls, strands to the floor
	for k in 12:
		var a := TAU * float(k) / 12.0 + 0.13
		var dir := Vector3(cos(a), 0, sin(a))
		if dir.z > 0.6:
			continue
		decor.add_web(c + dir * (rad - 0.6) + Vector3(0, b.rng.randf_range(2.5, 5.5), 0), -dir + Vector3(0, -0.2, 0), b.rng.randf_range(2.4, 3.4), 0.9)
		if k % 2 == 0:
			var top := c + dir * (rad - 2.5) + Vector3(0, 9.5, 0)
			decor.add_strand(top, c + dir * (rad - 3.2) + Vector3(0, 0.05, 0))
	for k in 5:
		var a := TAU * float(k) / 5.0 + 0.5
		decor.add_egg_sac(c + Vector3(cos(a), 0, sin(a)) * (rad - 1.2), 0.5)
		_sickly_nodules(b, c + Vector3(cos(a + 0.3), 0, sin(a + 0.3)) * (rad - 1.0), 6, 0.6)
	# Dim violet fill so the space reads before any brazier is lit
	Props.glow_light(n, c + Vector3(0, 8.0, 0), Color("6f6390"), 0.55, 18.0)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.8
		Props.glow_light(n, c + Vector3(cos(a), 0, sin(a)) * (rad - 1.5) + Vector3(0, 0.6, 0), GLOW, 0.4, 4.0)
	# Lift recess (east)
	b.begin("lift_recess")
	var lr: Dictionary = Layout.ROOMS["lift_recess"]
	var lx0: float = float(lr["x0"])
	var lx1: float = float(lr["x1"])
	var lz0: float = float(lr["z0"])
	var lz1: float = float(lr["z1"])
	b.floor_rect(lx0, lx1, lz0, lz1, -12.0, ROCK_MID)
	b.solid(Vector3((lx0 + lx1) * 0.5, -8.0, lz0 - 0.5), Vector3(lx1 - lx0 + 1.0, 8.0, 1.0), ROCK_DARK)
	b.solid(Vector3((lx0 + lx1) * 0.5, -8.0, lz1 + 0.5), Vector3(lx1 - lx0 + 1.0, 8.0, 1.0), ROCK_DARK)
	b.solid(Vector3(lx1 + 0.5, -8.0, (lz0 + lz1) * 0.5), Vector3(1.0, 8.0, lz1 - lz0 + 2.0), ROCK_DARK)
	b.solid(Vector3((lx0 + lx1) * 0.5 + 0.8, -7.5, (lz0 + lz1) * 0.5), Vector3(lx1 - lx0 - 1.6, 1.0, lz1 - lz0), ROCK_DARK)
	Props.timber_frame(b, lx0 + 0.2, lz0, lz1, -12.0, 3.4, "z")
