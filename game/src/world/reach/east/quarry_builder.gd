extends RefCounted
## Builds the Ashbell Quarry district on top of the shaped Reach terrain (quarry_shape.gd): copper-red terrace
## stonework (step faces, the shelf cliff, the crown wall, rim boulders), the yard (shed, quarry log, sign,
## crates, pumpkins, lantern posts, bunting), the bell gate to the Warden's arena, the mineral winch + gangway,
## the quarry lamp, the Warden arena with its pillars and spawner, the Bellcap Sentry pocket, every renewable
## harvest node and a little scatter. Deterministic: fixed tables (data/reach_east.gd) + RNGs seeded by name.
##   var root: Node3D = QuarryBuilder.build(area)   # area: a Node3D with height_at(x, z)
## Static geometry is merged per material (a handful of draw calls); all lights are unshadowed.

const Q := preload("res://data/reach_east.gd")
const Shape := preload("res://src/world/reach/east/quarry_shape.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const RootScript := preload("res://src/world/reach/east/quarry_root.gd")
const VeinScript := preload("res://src/world/reach/east/quarry_vein.gd")
const WinchScript := preload("res://src/world/reach/east/quarry_winch.gd")
const LampScript := preload("res://src/world/reach/east/quarry_lamp.gd")
const ArenaScript := preload("res://src/world/reach/east/warden_arena.gd")
const NoteScript := preload("res://src/world/reach/east/quarry_note.gd")
const SpawnerScript := preload("res://src/world/reach/east/guarded_spawner.gd")

const DECOR_RANGE := 120.0
const SIGN_FONT := "res://assets/fonts/Fredoka-Variable.ttf"
const SMALL_RANGE := 60.0


static func build(area: Node3D) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var root: Node3D = RootScript.new()
	root.name = "AshbellQuarry"
	area.add_child(root)
	var floor_y := height(area, Q.ARENA) - float(Q.LEVELS[2])
	root.floor_y = floor_y
	root.shaped = is_shaped(area, floor_y)
	if not root.shaped:
		push_warning("Ashbell Quarry: the terrain was not shaped (shape_terrain did not run on this ground); terraces are skipped, set pieces sit on the natural ground")
	var stone := NV.Merger.new()
	var wood := NV.Merger.new()
	var metal := NV.Merger.new()
	var crystal := NV.Merger.new()
	var solid := _body(root, "QuarryStoneSolid", "stone")
	var wood_solid := _body(root, "QuarryWoodSolid", "wood")
	if root.shaped:
		_stonework(area, floor_y, stone, crystal, solid)
	_yard(root, area, floor_y, wood, metal, stone, wood_solid)
	_landmarks(area, floor_y, metal, stone, solid)
	_commit(root, stone, QV.stone_material(), "Stonework", 0.0, true)
	_commit(root, wood, QV.wood_material(), "Woodwork", DECOR_RANGE, true)
	_commit(root, metal, QV.metal_material(), "Metalwork", DECOR_RANGE, true)
	_commit(root, crystal, QV.crystal_material(), "CrystalSeams", DECOR_RANGE, false)
	root.winch = _winch(root, area)
	root.lamp = _lamp(root, area)
	root.arena = _arena(root, area)
	root.spawners[Q.WARDEN_SPAWNER] = root.arena.spawner
	root.spawners["hr_sp_bellcaps"] = _bellcaps(root, area)
	var note: Node3D = NoteScript.new()
	root.add_child(note)
	note.position = ground(area, Shape.to_world(Q.LOG_NOTE))
	note.rotation.y = yaw_to(Shape.to_world(Q.LOG_NOTE), Shape.to_world(Vector2(-10.0, 0.0))) + PI
	root.note = note
	_harvest_nodes(root, area)
	_scatter(root, area, floor_y)
	_lights(root, area, floor_y)
	root.build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return root


# --- Helpers ----------------------------------------------------------------------------------------------

static func height(area: Node, p: Vector2) -> float:
	if area != null and area.has_method("height_at"):
		return float(area.height_at(p.x, p.y))
	return 0.0


static func ground(area: Node, p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height(area, p) + lift, p.y)


## Yaw that makes -Z face `to` (same convention as data/hallowmere_layout.gd yaw_towards).
static func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length() < 0.001:
		return 0.0
	return atan2(-d.x, -d.y)


## True when the ground shows the designed terraces (apron / bench / shelf levels relative to the arena bench).
static func is_shaped(area: Node, floor_y: float) -> bool:
	var probes := [[Vector2(-22.0, 0.0), 0], [Vector2(-7.0, 9.0), 1], [Vector2(24.0, 3.0), 3], [Vector2(8.0, 12.0), 2]]
	for pr in probes:
		var w := Shape.to_world(pr[0])
		if absf(height(area, w) - (floor_y + float(Q.LEVELS[int(pr[1])]))) > 0.06:
			return false
	return true


static func _v3(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)


static func _body(root: Node3D, body_name: String, surface: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = body_name
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("surface", surface)
	root.add_child(b)
	return b


static func _box_col(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = xf
	body.add_child(cs)


static func _commit(root: Node3D, m: NV.Merger, mat: Material, node_name: String, vis_range: float, shadows: bool) -> void:
	if m.is_empty():
		return
	var mi := NV._mi(m.commit(), mat, node_name)
	if vis_range > 0.0:
		NV.set_visibility_range(mi, vis_range, shadows)
	elif not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Yaw for QV.add_lantern_post whose arm (local +X) should point along the horizontal direction d.
static func _arm_yaw(d: Vector3) -> float:
	return atan2(-d.z, d.x)


## Right-handed basis whose X runs along `along` (horizontal), Y up.
static func _basis_along(along: Vector3) -> Basis:
	var x := Vector3(along.x, 0.0, along.z).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())


# --- Stonework --------------------------------------------------------------------------------------------

## Runs of V (along a U line) not covered by ramps that touch that line, inside the flat rim.
static func _free_runs(u_line: float, v_lo: float, v_hi: float, ramp_top_u: float) -> Array:
	var runs: Array = []
	var cur_a := INF
	var v := v_lo
	var step := 0.25
	while v <= v_hi + 0.001:
		var blocked := false
		for r in Q.RAMPS:
			var ur: Array = r["u"]
			var vr: Array = r["v"]
			if absf(float(ur[1]) - ramp_top_u) < 0.01 and v >= float(vr[0]) - 0.2 and v <= float(vr[1]) + 0.2:
				blocked = true
				break
		if not blocked and Shape.to_world(Vector2(u_line, v)).distance_to(Q.CENTER) <= Q.RIM_FLAT - 0.5:
			if cur_a == INF:
				cur_a = v
		elif cur_a != INF:
			runs.append([cur_a, v - step])
			cur_a = INF
		v += step
	if cur_a != INF:
		runs.append([cur_a, v_hi])
	return runs


static func _stonework(area: Node, floor_y: float, stone: NV.Merger, crystal: NV.Merger, solid: StaticBody3D) -> void:
	var fn := QV.stone_fn(floor_y)
	var u3 := _v3(Q.AXIS_U)
	var v3 := _v3(Q.AXIS_V)
	var along_v := _basis_along(v3)
	var along_u := _basis_along(u3)
	var variant := 0
	# 1) terrace step faces (L0|L1, L1|L2), skipping the ramps
	for si in 2:
		var u_line := float(Q.STEP_U[si])
		var lo := floor_y + float(Q.LEVELS[si])
		var hi := floor_y + float(Q.LEVELS[si + 1])
		for run in _free_runs(u_line, -30.0, 30.0, u_line):
			var a := float(run[0])
			var b := float(run[1])
			var n := maxi(1, int(round((b - a) / 1.9)))
			var seg := (b - a) / float(n)
			for k in n:
				var vm := a + seg * (float(k) + 0.5)
				var c := Shape.to_world(Vector2(u_line, vm))
				var top := hi - 0.06
				var bot := lo - 0.35
				var xf := Transform3D(along_v, Vector3(c.x, (top + bot) * 0.5, c.y))
				QV.add_block(stone, xf, Vector3(seg * 1.12, top - bot, 1.5), variant, fn)
				_box_col(solid, xf, Vector3(seg, top - bot, 1.3))
				variant += 1
	# 2) ramp side faces (visual): the ramp surface against the lower terrace beside it
	for r in Q.RAMPS:
		var ur: Array = r["u"]
		var vr: Array = r["v"]
		var hr: Array = r["h"]
		for side in [float(vr[0]), float(vr[1])]:
			var n := int(ceil((float(ur[1]) - float(ur[0])) / 1.1))
			for k in n:
				var t := (float(k) + 0.5) / float(n)
				var u := lerpf(float(ur[0]), float(ur[1]), t)
				var hs := lerpf(float(hr[0]), float(hr[1]), t) - float(hr[0])
				if hs < 0.3:
					continue
				var c := Shape.to_world(Vector2(u, side))
				var top := floor_y + float(hr[0]) + hs - 0.05
				var bot := floor_y + float(hr[0]) - 0.3
				QV.add_block(stone, Transform3D(along_u, Vector3(c.x, (top + bot) * 0.5, c.y)), Vector3(1.25, top - bot, 0.9), variant, fn)
				variant += 1
	# 3) the shelf cliff (front along U_CLIFF, west side along SHELF_WEST_V): tall faces with pale crystal seams
	var l2 := floor_y + float(Q.LEVELS[2])
	var s := floor_y + float(Q.LEVELS[3])
	var cliff_top := s - 0.06
	var cliff_bot := l2 - 0.35
	var faces: Array = []
	var v_end := sqrt(maxf(29.2 * 29.2 - Q.U_CLIFF * Q.U_CLIFF, 0.0))
	var nf := int(ceil((v_end - Q.SHELF_WEST_V) / 2.2))
	for k in nf:
		var vm := Q.SHELF_WEST_V + (v_end - Q.SHELF_WEST_V) * (float(k) + 0.5) / float(nf)
		faces.append([Shape.to_world(Vector2(Q.U_CLIFF, vm)), along_v, (v_end - Q.SHELF_WEST_V) / float(nf), -u3])
	var u_end := sqrt(maxf(29.2 * 29.2 - Q.SHELF_WEST_V * Q.SHELF_WEST_V, 0.0))
	var ns := int(ceil((u_end - Q.U_CLIFF) / 2.2))
	for k in ns:
		var um := Q.U_CLIFF + (u_end - Q.U_CLIFF) * (float(k) + 0.5) / float(ns)
		faces.append([Shape.to_world(Vector2(um, Q.SHELF_WEST_V)), along_u, (u_end - Q.U_CLIFF) / float(ns), -v3])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hr_quarry_cliff")
	for f in faces:
		var c: Vector2 = f[0]
		var bs: Basis = f[1]
		var w: float = f[2]
		var out: Vector3 = f[3]
		var xf := Transform3D(bs, Vector3(c.x, (cliff_top + cliff_bot) * 0.5, c.y))
		QV.add_block(stone, xf, Vector3(w * 1.1, cliff_top - cliff_bot, 1.7), variant, fn)
		_box_col(solid, xf, Vector3(w, cliff_top - cliff_bot, 1.5))
		variant += 1
		# a pale crystal seam slanting across every other face
		if variant % 2 == 0:
			var face := Vector3(c.x, 0.0, c.y) + out * 0.82
			var y0 := l2 + rng.randf_range(0.8, 2.2)
			for j in 3:
				var p := face + bs.x * rng.randf_range(-0.6, 0.6) + Vector3(0, y0 + float(j) * 0.55, 0)
				var tilt := Basis(bs.z, rng.randf_range(0.5, 1.1)) * Basis(bs.x, rng.randf_range(-0.4, 0.4))
				var h := rng.randf_range(0.35, 0.7)
				crystal.add(NV._cyl(0.07, 0.09, h, 6), Transform3D(tilt, p), Q.COL_CRYSTAL.lerp(Q.COL_CRYSTAL_DEEP, rng.randf() * 0.5))
	# 4) crown wall on the shelf rim: the upper shelf is reached ONLY by the gangway (never from outside)
	var crown_r := 29.0
	var a_steps := 44
	for k in a_steps:
		var ang := -PI + TAU * (float(k) + 0.5) / float(a_steps)
		var uv := Vector2(cos(ang), sin(ang)) * crown_r
		if uv.x < Q.U_CLIFF - 0.6 or uv.y < Q.SHELF_WEST_V - 0.8:
			continue
		var c := Shape.to_world(uv)
		var outside := height(area, Shape.to_world(Vector2(cos(ang), sin(ang)) * 31.5))
		var rim_low := minf(height(area, Shape.to_world(Vector2(cos(ang), sin(ang)) * 30.2)), s)
		var top := maxf(s, outside) + 2.4
		var bot := rim_low - 0.6
		var tangent := u3 * -sin(ang) + v3 * cos(ang)
		var bs := _basis_along(tangent)
		var xf := Transform3D(bs, Vector3(c.x, (top + bot) * 0.5, c.y))
		var seg := TAU * crown_r / float(a_steps)
		QV.add_block(stone, xf, Vector3(seg * 1.25, top - bot, 2.1), variant, fn)
		_box_col(solid, xf, Vector3(seg * 1.02, top - bot, 1.8))
		QV.add_boulder(stone, Vector3(c.x, top - 0.2, c.y), 0.7 + 0.2 * float(k % 3), k, ang, fn, 0.6)
		variant += 1
	# 5) rim boulders around the benches (visual; the yard and the north mouth stay open)
	for k in 36:
		var ang := -PI + TAU * (float(k) + 0.5) / 36.0
		var uv := Vector2(cos(ang), sin(ang)) * 28.9
		if uv.x >= Q.U_CLIFF - 1.5 and uv.y >= Q.SHELF_WEST_V - 1.5:
			continue
		var w := Shape.to_world(uv)
		if w.distance_to(Q.ARCH) < 12.0 or w.distance_to(Q.NORTH_MOUTH) < 10.0:
			continue
		var lvl := Shape.level_at_local(uv.x * 0.98, uv.y * 0.98)
		var base := minf(floor_y + lvl, height(area, w))
		QV.add_boulder(stone, Vector3(w.x, base + 0.1, w.y), 0.8 + 0.25 * float(k % 3), 40 + k, ang, fn, 0.7)
		if k % 2 == 0:
			var w2 := Shape.to_world(uv * 1.02 + Vector2(sin(ang), -cos(ang)) * 1.1)
			QV.add_boulder(stone, Vector3(w2.x, base, w2.y), 0.55, 80 + k, ang, fn, 0.7)


# --- Yard, bell gate, lantern posts -------------------------------------------------------------------------

static func _yard(root: Node3D, area: Node, floor_y: float, wood: NV.Merger, metal: NV.Merger, stone: NV.Merger, wood_solid: StaticBody3D) -> void:
	var u3 := _v3(Q.AXIS_U)
	var v3 := _v3(Q.AXIS_V)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hr_quarry_yard")
	# tool shed: a lean-to facing the haul road
	var sc := Shape.to_world(Q.SHED)
	var sb := ground(area, sc)
	var facing := (_v3(Shape.to_world(Vector2(-12.0, 0.0))) - Vector3(sc.x, 0.0, sc.y)).normalized()
	var side := Vector3.UP.cross(facing).normalized()
	var back := -facing
	for sx in [-1.0, 1.0]:
		QV.add_rod(wood, sb + side * float(sx) * 1.5 + facing * 0.9 + Vector3(0, -0.2, 0), sb + side * float(sx) * 1.5 + facing * 0.9 + Vector3(0, 2.2, 0), 0.09, Palette.WOOD_DARK)
		QV.add_rod(wood, sb + side * float(sx) * 1.5 + back * 0.9 + Vector3(0, -0.2, 0), sb + side * float(sx) * 1.5 + back * 0.9 + Vector3(0, 1.6, 0), 0.09, Palette.WOOD_DARK)
	var roof_b := Basis(side, Vector3.UP, side.cross(Vector3.UP).normalized()) * Basis(Vector3.RIGHT, -0.3)
	QV.add_box(wood, Transform3D(roof_b, sb + Vector3(0, 2.0, 0)), Vector3(3.4, 0.12, 2.3), Color("a4553c"))
	QV.add_box(wood, Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP).normalized()), sb + back * 0.95 + Vector3(0, 0.8, 0)), Vector3(3.0, 1.6, 0.1), Palette.WOOD)
	QV.add_box(wood, Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP).normalized()), sb + Vector3(0, 0.5, 0) + back * 0.55), Vector3(2.4, 0.08, 0.6), Palette.WOOD_LIGHT)
	for k in 3:
		QV.add_rod(wood, sb + side * (-0.9 + 0.8 * float(k)) + back * 0.8 + Vector3(0, 0.55, 0), sb + side * (-0.7 + 0.8 * float(k)) + back * 0.75 + Vector3(0, 1.5, 0), 0.03, Palette.WOOD_DARK)
	_box_col(wood_solid, Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP).normalized()), sb + back * 0.4 + Vector3(0, 1.0, 0)), Vector3(3.2, 2.0, 1.3))
	for k in 3:
		QV.add_crate(wood, sb + side * (2.1 + 0.2 * float(k % 2)) + facing * (0.6 * float(k)) , rng.randf() * TAU, 0.9 + 0.1 * float(k % 2))
	_box_col(wood_solid, Transform3D(Basis(), sb + side * 2.2 + facing * 0.6 + Vector3(0, 0.3, 0)), Vector3(0.8, 0.6, 2.0))
	for k in 4:
		QV.add_pumpkin(wood, sb - side * (2.0 + 0.45 * float(k)) + facing * rng.randf_range(0.2, 0.8), 0.8 + rng.randf() * 0.5, rng.randf() * TAU)
	# sign by the yard entrance
	var sg := Shape.to_world(Q.SIGN)
	var sgb := ground(area, sg)
	var sface := (_v3(Q.ARCH) - Vector3(sg.x, 0.0, sg.y)).normalized()
	var sside := Vector3.UP.cross(sface).normalized()
	for sx in [-1.0, 1.0]:
		QV.add_rod(wood, sgb + sside * float(sx) * 0.75 + Vector3(0, -0.2, 0), sgb + sside * float(sx) * 0.75 + Vector3(0, 2.0, 0), 0.07, Palette.WOOD_DARK)
	QV.add_box(wood, Transform3D(Basis(sside, Vector3.UP, sside.cross(Vector3.UP).normalized()), sgb + Vector3(0, 1.55, 0)), Vector3(1.8, 0.6, 0.08), Palette.WOOD_LIGHT)
	QV.add_bell(metal, Transform3D(Basis(), sgb + sside * 0.95 + Vector3(0, 1.95, 0)), 0.45)
	_box_col(wood_solid, Transform3D(Basis(sside, Vector3.UP, sside.cross(Vector3.UP).normalized()), sgb + Vector3(0, 1.0, 0)), Vector3(1.8, 2.0, 0.25))
	var lbl := Label3D.new()
	lbl.name = "SignText"
	lbl.text = "Ashbell Quarry"
	lbl.font_size = 44
	lbl.pixel_size = 0.0075
	lbl.modulate = Color("5a3a2a")
	lbl.outline_size = 0
	lbl.double_sided = false
	if ResourceLoader.exists(SIGN_FONT):
		var f: Variant = load(SIGN_FONT)
		if f is Font:
			lbl.font = f
	root.add_child(lbl)
	lbl.transform = Transform3D(Basis(sside, Vector3.UP, sside.cross(Vector3.UP).normalized()).rotated(Vector3.UP, PI), sgb + Vector3(0, 1.57, 0) + sface * 0.06)
	var lbl2: Label3D = lbl.duplicate()
	lbl2.name = "SignTextBack"
	root.add_child(lbl2)
	lbl2.transform = Transform3D(Basis(sside, Vector3.UP, sside.cross(Vector3.UP).normalized()), sgb + Vector3(0, 1.57, 0) - sface * 0.06)
	# lantern posts along the haul road + bunting across it
	var glass_at: Array = []
	for lp in Q.LANTERN_POSTS:
		var w := Shape.to_world(lp)
		# the lantern arm reaches over the road (toward V = 0)
		var arm_yaw := _arm_yaw(-v3 * signf(float(lp.y)))
		var at := QV.add_lantern_post(wood, ground(area, w), arm_yaw)
		glass_at.append(at)
		_box_col(wood_solid, Transform3D(Basis(), ground(area, w) + Vector3(0, 1.1, 0)), Vector3(0.3, 2.2, 0.3))
	var bi := 0
	for pair in [[0, 1], [2, 3]]:
		var a: Vector2 = Shape.to_world(Q.LANTERN_POSTS[pair[0]])
		var b: Vector2 = Shape.to_world(Q.LANTERN_POSTS[pair[1]])
		var ya := height(area, a) + 2.35
		var yb := height(area, b) + 2.35
		var mid := Vector3((a.x + b.x) * 0.5, (ya + yb) * 0.5, (a.y + b.y) * 0.5)
		var d := Vector3(b.x - a.x, 0.0, b.y - a.y)
		var g := Props.garland(d.length(), [Q.COL_RIBBON_A, Color("f3e6c8"), Q.COL_RIBBON_B, Color("e4665c")])
		var gm := Props.instance(g, QV.cloth_material(), SMALL_RANGE + 30.0, false)
		gm.name = "Bunting%d" % bi
		bi += 1
		root.add_child(gm)
		gm.transform = Transform3D(_basis_along(d), mid)
	var glass_mesh := Props.lantern_glass()
	var gmat := QV.glow_material(Q.LAMP_GLOW, 2.2)
	var gxf: Array = []
	for at in glass_at:
		gxf.append(Transform3D(Basis.from_scale(Vector3(1.4, 1.4, 1.4)), at))
	var glass := Props.multimesh(glass_mesh, gmat, gxf, "LanternGlass", DECOR_RANGE, false)
	root.add_child(glass)
	# the Ashbell bell gate at the top of the haul road (the way into the Warden's arena)
	var gp: Array = []
	for bg in Q.BELL_GATE:
		var w := Shape.to_world(bg)
		gp.append(ground(area, w))
	for p in gp:
		var pv: Vector3 = p
		QV.add_boulder(stone, pv + Vector3(0, 0.2, 0), 0.55, 7, 0.0, Q.COL_ROCK, 0.8)
		QV.add_rod(wood, pv + Vector3(0, -0.2, 0), pv + Vector3(0, 4.1, 0), 0.16, Palette.WOOD_DARK)
		_box_col(wood_solid, Transform3D(Basis(), pv + Vector3(0, 2.0, 0)), Vector3(0.5, 4.0, 0.5))
		QV.add_ribbon(wood, pv + Vector3(0, 3.6, 0.12), 0.0, 1.1, Q.COL_RIBBON_A)
	var g0: Vector3 = gp[0]
	var g1: Vector3 = gp[1]
	var beam_y := maxf(g0.y, g1.y) + 3.9
	QV.add_rod(wood, Vector3(g0.x, beam_y, g0.z) - v3 * 0.4, Vector3(g1.x, beam_y, g1.z) + v3 * 0.4, 0.14, Palette.WOOD)
	for k in 3:
		var t := 0.25 + 0.25 * float(k)
		var bp := Vector3(lerpf(g0.x, g1.x, t), beam_y - 0.1, lerpf(g0.z, g1.z, t))
		QV.add_rod(metal, bp, bp + Vector3(0, -0.25, 0), 0.02, Q.COL_IRON)
		QV.add_bell(metal, Transform3D(Basis(Vector3.UP, 0.3 * float(k)), bp + Vector3(0, -0.25, 0)), 0.9 if k == 1 else 0.7)
	for k in 3:
		QV.add_pumpkin(wood, g0 - u3 * (0.9 + 0.3 * float(k)) + v3 * (0.4 * float(k)), 0.9 + 0.3 * float(k % 2), float(k))
		QV.add_pumpkin(wood, g1 - u3 * (0.9 + 0.3 * float(k)) - v3 * (0.4 * float(k)), 0.9 + 0.3 * float((k + 1) % 2), float(k) + 1.0)


## The half-sunk Ashbell and the bell-cap toadstools that mark the Bellcap Sentry pocket.
static func _landmarks(area: Node, floor_y: float, metal: NV.Merger, stone: NV.Merger, solid: StaticBody3D) -> void:
	var fn := QV.stone_fn(floor_y)
	var bw := Shape.to_world(Q.ASHBELL)
	var bg := ground(area, bw)
	var tilt := Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, 0.5)
	var bronze := Q.COL_BRONZE.darkened(0.12)
	# bell body (a big flared cylinder, crown and lip), sunk ~1 m into the bench, with a dark crack
	metal.add(NV._cyl(0.95, 1.65, 2.2, 20), Transform3D(tilt, bg + tilt * Vector3(0, 0.55, 0)), bronze)
	metal.add(NV._hemi(0.95, 0.8, 18), Transform3D(tilt, bg + tilt * Vector3(0, 1.62, 0)), bronze.lightened(0.08))
	metal.add(NV._cyl(1.72, 1.72, 0.22, 20), Transform3D(tilt, bg + tilt * Vector3(0, -0.5, 0)), bronze.darkened(0.15))
	metal.add(NV._box(Vector3(0.08, 1.5, 0.05)), Transform3D(tilt * Basis(Vector3.BACK, 0.25), bg + tilt * Vector3(0.9, 0.7, 1.05)), Color("3b2a22"))
	metal.add(NV._cyl(0.2, 0.2, 0.5, 8), Transform3D(tilt, bg + tilt * Vector3(0, 2.1, 0)), bronze.darkened(0.25))
	for k in 5:
		var a := TAU * float(k) / 5.0 + 0.4
		QV.add_boulder(stone, bg + Vector3(cos(a) * 1.9, 0.05, sin(a) * 1.9), 0.45 + 0.1 * float(k % 2), 60 + k, a, fn, 0.6)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.55
	cyl.height = 2.6
	cs.shape = cyl
	cs.transform = Transform3D(tilt, bg + tilt * Vector3(0, 0.6, 0))
	solid.add_child(cs)
	# bell-cap toadstools: pale stalks under bronze bell caps
	for i in Q.BELLCAP_MARKERS.size():
		var p := ground(area, Shape.to_world(Q.BELLCAP_MARKERS[i]))
		for j in 2 + i % 2:
			var off := Vector3(0.45 * float(j) - 0.3, 0.0, 0.3 * float((i + j) % 2))
			var s := 0.9 + 0.25 * float((i + j) % 3)
			metal.add(NV._cyl(0.09 * s, 0.13 * s, 0.6 * s, 8), Transform3D(Basis(), p + off + Vector3(0, 0.28 * s, 0)), Color("efe3cf"))
			QV.add_bell(metal, Transform3D(Basis(Vector3.UP, float(j)), p + off + Vector3(0, 0.95 * s, 0)), 0.75 * s, Color("b8743a"))


# --- Set pieces ----------------------------------------------------------------------------------------------

static func _winch(root: Node3D, area: Node) -> Node3D:
	var wd: Dictionary = Q.WINCH
	var dv: Array = wd["deck_v"]
	var du: Array = wd["deck_u"]
	var gu := float(wd["gangway_u"])
	var shelf_y := height(area, Shape.to_world(Vector2(float(du[1]) + 1.2, (float(dv[0]) + float(dv[1])) * 0.5)))
	var deck_y := shelf_y + 0.06
	var hinge2 := Shape.to_world(Vector2(gu, float(dv[0])))
	var slope := float(wd["slope_deg"])
	var dir := -_v3(Q.AXIS_V)
	# find the foot level: the L2 bench under the gangway's far end
	var run_guess := 13.4
	var foot2 := Shape.to_world(Vector2(gu, float(dv[0]) - run_guess))
	var foot_y := height(area, foot2) + 0.04
	var rise := maxf(deck_y - foot_y, 0.5)
	var length := rise / sin(deg_to_rad(slope))
	var st := Shape.to_world(Q.WINCH["station"])
	var w: Node3D = WinchScript.new()
	w.setup({"hinge": Vector3(hinge2.x, deck_y, hinge2.y), "dir": dir, "length": length, "width": float(wd["gangway_width"]),
		"slope_deg": slope, "raised_deg": float(wd["raised_deg"]),
		"deck_min": Vector2(float(du[0]), float(dv[0])), "deck_max": Vector2(float(du[1]), float(dv[1])), "deck_y": deck_y,
		"crane": ground(area, Shape.to_world(Q.WINCH["crane"])), "frame": func(uv: Vector2) -> Vector2: return Shape.to_world(uv)})
	w.position = ground(area, st)
	root.add_child(w)
	return w


static func _lamp(root: Node3D, area: Node) -> Node3D:
	var lw := Shape.to_world(Q.LAMP)
	var l: Node3D = LampScript.new()
	l.position = ground(area, lw)
	var to := Q.ARENA - lw
	l.rotation.y = atan2(to.x, to.y)
	root.add_child(l)
	return l


static func _arena(root: Node3D, area: Node) -> Node3D:
	var a: Node3D = ArenaScript.new()
	var c := ground(area, Q.ARENA)
	var offs: Array = []
	for p in Q.PILLARS:
		var w := Shape.to_world(p)
		offs.append(Vector3(w.x - c.x, height(area, w) - c.y, w.y - c.z))
	a.setup({"radius": Q.ARENA_RADIUS, "pillars": offs})
	a.position = c
	root.add_child(a)
	return a


static func _bellcaps(root: Node3D, area: Node) -> Node3D:
	var sd: Dictionary = Q.SPAWNERS["hr_sp_bellcaps"]
	var sp: Node3D = SpawnerScript.new()
	sp.name = "hr_sp_bellcaps"
	sp.setup({"enemy": sd["enemy"], "count": sd["count"], "radius": sd["radius"], "respawn_minutes": sd["respawn_minutes"],
		"spawner_id": "hr_sp_bellcaps", "wander_radius": float(sd.get("wander", 3.0))})
	sp.position = ground(area, Shape.to_world(sd["at"]))
	root.add_child(sp)
	return sp


# --- Harvest nodes ----------------------------------------------------------------------------------------

## The ordered node table: [{id, table, pos: Vector2 (world XZ), local: Vector2 (U, V), source_kind, min_tier}]
## (pure; tests). source_kind = the data/sources.gd NODES kind, also the resource_node.gd kind.
static func node_plan() -> Array:
	var out: Array = []
	for table in Q.NODE_ORDER:
		var t: Array = Q.NODE_TABLES[table]
		var pts: Array = t[0]
		for i in pts.size():
			out.append({"id": String(t[1]) % i, "table": String(table), "pos": Shape.to_world(pts[i]), "local": pts[i],
				"source_kind": String(t[2]), "min_tier": int(t[3])})
	return out


static func _harvest_nodes(root: Node3D, area: Node) -> void:
	var holder := Node3D.new()
	holder.name = "HarvestNodes"
	root.add_child(holder)
	for e in node_plan():
		var n := make_node(e)
		var w: Vector2 = e["pos"]
		n.position = ground(area, w)
		holder.add_child(n)
		root.nodes[String(e["id"])] = n
		# the region keeps a table of district harvest ids (reach_world.gd district_nodes / resource_ids())
		if "district_nodes" in area and area.get("district_nodes") is Dictionary:
			(area.get("district_nodes") as Dictionary)[String(e["id"])] = n


## One harvest node for a node_plan() entry (not yet in the tree). Numbers come from data/sources.gd NODES
## (resource_node.gd reads the data kinds itself; the legacy kinds ore / rock / stone get the same catalogue
## numbers passed explicitly so the quarry's nodes always match the data file).
static func make_node(e: Dictionary) -> Node3D:
	var id := String(e["id"])
	var sk := String(e["source_kind"])
	var src: Dictionary = ItemDB.node_kind(sk)
	var seed_value := int(hash(id)) & 0xffff
	var p := {"node_id": id, "kind": sk, "min_tier": int(e["min_tier"]), "seed": seed_value, "yaw": float(seed_value % 360)}
	if not src.is_empty():
		p["tool"] = String(src.get("tool", "pickaxe"))
		p["hits"] = int(src.get("hits", 3))
		p["drops"] = (src.get("drops", []) as Array).duplicate(true)
		p["respawn_minutes"] = float(src.get("respawn_minutes", 1440.0))
		p["min_tier"] = maxi(int(e["min_tier"]), int(src.get("min_tier", 0)))
		p["name"] = String(src.get("name", ""))
	match String(e["table"]):
		"iron":
			p["visual"] = QV.iron_vein(seed_value)
			p["fx"] = "chips"
		"moon_crystal":
			p["visual"] = QV.moon_seam(seed_value)
			p["fx"] = "crystal"
		"rock":
			p["visual"] = NV.build("boulder", seed_value, {"tint": Q.COL_ROCK, "moss": 0.1})
		"stone":
			p["visual"] = NV.build("pebble", seed_value, {"tint": Q.COL_ROCK_LIGHT})
	var n: Node3D = VeinScript.new()
	n.setup(p)
	n.name = id
	return n


# --- Scatter and lights -------------------------------------------------------------------------------------

static func _scatter(root: Node3D, area: Node, floor_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hr_quarry_scatter")
	var chips: Array = []
	var leaves: Array = []
	var tries := 0
	while (chips.size() < 110 or leaves.size() < 50) and tries < 900:
		tries += 1
		var uv := Vector2(rng.randf_range(-27.0, 27.0), rng.randf_range(-27.0, 27.0))
		var w := Shape.to_world(uv)
		if w.distance_to(Q.CENTER) > 26.5 or w.distance_to(Q.ARCH) < 9.0:
			continue
		var h := height(area, w)
		if absf(h - (floor_y + Shape.level_at_local(uv.x, uv.y))) > 0.04 or not Shape.ramp_at_local(uv.x, uv.y).is_empty():
			continue
		var yaw := rng.randf() * TAU
		if chips.size() < 110:
			var s := rng.randf_range(0.12, 0.3)
			chips.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.6, s)), Vector3(w.x, h + s * 0.15, w.y)))
		elif uv.x < 0.0:
			var s2 := rng.randf_range(0.14, 0.24)
			leaves.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s2, 0.08, s2 * 0.7)), Vector3(w.x, h + 0.02, w.y)))
	var cm := NV.Merger.new()
	cm.add(NV.ublob(3, 0.35, 1.0, 1), Transform3D(), Q.COL_ROCK.lightened(0.05))
	root.add_child(Props.multimesh(cm.commit(), QV.stone_material(), chips, "Chips", SMALL_RANGE, false))
	var lm := NV.Merger.new()
	lm.add(NV.ublob(5, 0.2, 1.0, 1), Transform3D(), Color("d9793a"))
	root.add_child(Props.multimesh(lm.commit(), QV.cloth_material(), leaves, "Leaves", SMALL_RANGE, false))


static func _lights(root: Node3D, area: Node, floor_y: float) -> void:
	var specs: Array = []
	# warm: two lantern posts and the bell gate
	specs.append([ground(area, Shape.to_world(Q.LANTERN_POSTS[1])) + Vector3(0, 2.1, 0), Q.LAMP_GLOW, 1.1, 7.5])
	specs.append([ground(area, Shape.to_world(Q.LANTERN_POSTS[2])) + Vector3(0, 2.1, 0), Q.LAMP_GLOW, 1.1, 7.5])
	# cool: the pale crystal seams on the shelf and in the cliff
	specs.append([ground(area, Shape.to_world(Vector2(25.0, 1.0))) + Vector3(0, 1.4, 0), Q.COL_CRYSTAL, 0.9, 8.0])
	specs.append([ground(area, Shape.to_world(Vector2(23.2, 11.5))) + Vector3(0, 1.4, 0), Q.COL_CRYSTAL, 0.8, 7.0])
	specs.append([Vector3(Shape.to_world(Vector2(18.2, 8.0)).x, floor_y + float(Q.LEVELS[2]) + 2.2, Shape.to_world(Vector2(18.2, 8.0)).y), Q.COL_CRYSTAL_DEEP, 0.6, 6.5])
	var i := 0
	for s in specs:
		var o := OmniLight3D.new()
		o.name = "QuarryLight%d" % i
		o.position = s[0]
		o.light_color = s[1]
		o.light_energy = float(s[2])
		o.omni_range = float(s[3])
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 70.0
		o.distance_fade_length = 15.0
		root.add_child(o)
		i += 1
