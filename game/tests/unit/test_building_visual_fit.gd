extends "res://tests/test_case.gd"
## Visual fit of building pieces (visual QA pass BU-00..BU-14), checked numerically:
## wall decor needs a wall panel it fits behind its cell and snaps flush onto it (and the wall stays while
## something hangs on it); window decor centres on / frames the 2 m window; no straw pokes through a roof's
## ceiling; the roof corner is built from the roof tile's own thatch (same surface along its seams, nothing
## past the eave); the stair balustrade stays inside a railing on the stairwell line; upstairs wall panels drop
## the stone footing (the ground ones keep it); carved faces have a dark rim; recolouring keeps accents.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Models := preload("res://src/building/structure_models.gd")
const Parts := preload("res://src/building/models_building.gd")
const Storey := preload("res://src/building/models_storey.gd")
const Seasonal := preload("res://src/building/models_seasonal.gd")
const Tints := preload("res://src/building/tints.gd")
const Palette := preload("res://src/art/palette.gd")

const BA := {"center": Vector2(0, 0), "radius": 30.0, "blocked": []}
const MOUNTS := ["flower_box", "curtain", "thread_veil", "pumpkin_lights", "bat_bunting", "gothic_trim"]


func before_each() -> void:
	fresh_state()


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _ctx(structs: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var c := {"structures": structs, "area_id": "surface", "build_area": BA, "height_fn": _flat}
	c.merge(extra, true)
	return c


func _rec(id: String, pos: Vector3, rot: float = 0.0, level: int = 0) -> Dictionary:
	var data := {}
	if level > 0:
		data["level"] = level
	return {"id": id, "area": "surface", "pos": [pos.x, pos.y, pos.z], "rot": rot, "data": data}


func _v(id: String, pos: Vector3, rot: float, s: Dictionary) -> Dictionary:
	return P.validate(id, pos, rot, _ctx(s))


## Every vertex of every mesh under `root`, in root space.
func _verts(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			for v in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				out.append(xf * v)
	return out


func _model(sid: String, opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	Models.build(sid, root, opts)
	return root


# --- BU-00 / BU-02: wall decor needs a wall it fits --------------------------------------------------------------

func test_wall_decor_needs_a_wall_panel_behind_its_cell() -> void:
	var s := {"w": _rec("wood_wall", Vector3(1, 0, 0), 0), "x": _rec("wood_wall", Vector3(4, 0, 1), 90)}
	for sid in MOUNTS:
		var free := _v(sid, Vector3(10.5, 0, 10.5), 0, s)
		assert_false(bool(free["ok"]), "%s is refused in open grass" % sid)
		assert_eq(String(free["reason"]), P.MSG_MOUNT, sid)
		assert_true(bool(_v(sid, Vector3(0.5, 0, 0.5), 0, s)["ok"]), "%s hangs on the wall behind it (rot 0, +Z face)" % sid)
		assert_true(bool(_v(sid, Vector3(1.5, 0, -0.5), 180, s)["ok"]), "%s hangs on the other face (rot 180)" % sid)
		assert_false(bool(_v(sid, Vector3(0.5, 0, 0.5), 180, s)["ok"]), "%s facing the wall is refused" % sid)
		assert_false(bool(_v(sid, Vector3(0.5, 0, 1.5), 0, s)["ok"]), "%s one metre off the wall is refused" % sid)
		assert_true(bool(_v(sid, Vector3(4.5, 0, 1.5), 90, s)["ok"]), "%s on a wall along Z (rot 90)" % sid)
		assert_true(bool(_v(sid, Vector3(3.5, 0, 0.5), 270, s)["ok"]), "%s on its other face (rot 270)" % sid)
		assert_false(bool(_v(sid, Vector3(2.5, 0, 0.5), 0, s)["ok"]), "%s past the end of the wall is refused" % sid)
	# Upstairs: the wall of that storey counts, not the one below.
	var up := {"w": _rec("wood_wall", Vector3(1, 0, 0), 0)}
	for i in 4:
		up["wall%d" % i] = _rec("wood_wall", [Vector3(1, 0, 4), Vector3(0, 0, 1), Vector3(0, 0, 3), Vector3(2, 0, 3)][i], 0.0 if i == 0 else 90.0)
	up["f"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	var r := P.validate("curtain", Vector3(0.5, 3, 0.5), 0, _ctx(up, {"level": 1}))
	assert_false(bool(r["ok"]), "no upstairs wall behind it yet")
	up["uw"] = _rec("wood_wall", Vector3(1, 3, 0), 0, 1)
	var r2 := P.validate("curtain", Vector3(0.5, 3, 0.5), 0, _ctx(up, {"level": 1}))
	assert_true(bool(r2["ok"]), String(r2["reason"]))


func test_wall_decor_only_goes_on_panels_it_fits() -> void:
	var s := {"win": _rec("wood_window", Vector3(1, 0, 0), 0), "door": _rec("wood_doorway", Vector3(3, 0, 0), 0),
		"cres": _rec("crescent_window", Vector3(5, 0, 0), 0), "arch": _rec("arched_window", Vector3(7, 0, 0), 0),
		"rail": _rec("wood_railing", Vector3(9, 0, 0), 0), "half": _rec("half_wall", Vector3(11, 0, 0), 0)}
	for sid in ["gothic_trim", "thread_veil"]:
		var r := _v(sid, Vector3(0.5, 0, 0.5), 0, s)
		assert_false(bool(r["ok"]), "%s never runs across a window" % sid)
		assert_eq(String(r["reason"]), P.MSG_MOUNT_PANEL % "window")
	for sid in MOUNTS:
		assert_false(bool(_v(sid, Vector3(2.5, 0, 0.5), 0, s)["ok"]), "%s never hangs in a doorway" % sid)
		assert_eq(String(_v(sid, Vector3(8.5, 0, 0.5), 0, s)["reason"]), P.MSG_MOUNT, "%s: a railing is not a wall" % sid)
		assert_false(bool(_v(sid, Vector3(10.5, 0, 0.5), 0, s)["ok"]), "%s is not made for a half wall" % sid)
	for sid in ["curtain", "flower_box"]:
		for x in [4.5, 5.5, 6.5, 7.5]:
			var ok := _v(sid, Vector3(x, 0, 0.5), 0, s)
			assert_true(bool(ok["ok"]), "%s on a window at x %.1f: %s" % [sid, x, String(ok["reason"])])
	for sid in ["pumpkin_lights", "bat_bunting"]:
		assert_true(bool(_v(sid, Vector3(4.5, 0, 0.5), 0, s)["ok"]), "%s hangs over a round window" % sid)
		assert_false(bool(_v(sid, Vector3(6.5, 0, 0.5), 0, s)["ok"]), "%s would cross the arched window's top" % sid)
	# The Chapter One window has its own box on its front face; the back face is free.
	var front := _v("flower_box", Vector3(0.5, 0, 0.5), 0, s)
	assert_eq(String(front["reason"]), P.MSG_MOUNT_OWN_BOX)
	assert_true(bool(_v("flower_box", Vector3(0.5, 0, -0.5), 180, s)["ok"]), "the inside of the old window is free")
	assert_true(bool(_v("curtain", Vector3(0.5, 0, 0.5), 0, s)["ok"]), "curtains frame the old window")
	# One centred flower box per window side.
	s["box"] = _rec("flower_box", Vector3(4.5, 0, 0.5), 0)
	var second := _v("flower_box", Vector3(5.5, 0, 0.5), 0, s)
	assert_false(bool(second["ok"]), "the window's box is already there")
	assert_eq(String(second["blocker"]), "box")
	assert_true(bool(_v("flower_box", Vector3(5.5, 0, -0.5), 180, s)["ok"]), "the other side of that window is free")
	assert_true(bool(_v("curtain", Vector3(5.5, 0, 0.5), 0, s)["ok"]), "a curtain still fits beside the box")


func test_wall_decor_snaps_flush_onto_the_nearest_wall() -> void:
	var s := {"w": _rec("wood_wall", Vector3(1, 0, 0), 0), "x": _rec("wood_wall", Vector3(4, 0, 1), 90)}
	var ctx := _ctx(s)
	var cases := [
		[Vector3(0.3, 0, 0.12), Vector3(0.5, 0, 0.5), 0],       # cursor on the wall's +Z face
		[Vector3(1.7, 0, -0.8), Vector3(1.5, 0, -0.5), 180],    # a step behind the wall
		[Vector3(4.11, 1.2, 1.6), Vector3(4.5, 1.2, 1.5), 90],  # the ray hit the face of the wall along Z
		[Vector3(3.2, 0, 0.3), Vector3(3.5, 0, 0.5), 270],      # nearer to the wall along Z than to the other
	]
	for c in cases:
		var ms := P.mount_snap(c[0], ctx)
		assert_false(ms.is_empty(), "snaps near %s" % str(c[0]))
		assert_eq(ms.get("pos"), c[1], "cell touching the wall for %s" % str(c[0]))
		assert_eq(int(ms.get("rot", -1)), int(c[2]), "turned away from the wall for %s" % str(c[0]))
		assert_true(bool(P.validate("bat_bunting", ms["pos"], float(ms["rot"]), ctx)["ok"]), "the snapped spot is valid")
	assert_true(P.mount_snap(Vector3(10, 0, 10), ctx).is_empty(), "nothing to snap to in open grass")
	# Every wall piece's model backs onto the wall face (planks MOUNT_FACE off the grid line): within 3 cm.
	for sid in MOUNTS:
		var root := _model(sid)
		var zmin := INF
		for v in _verts(root):
			zmin = minf(zmin, v.z)
		assert_true(absf(zmin - P.MOUNT_BACK) <= 0.03, "%s backs onto the wall face (back at %.3f, face at %.3f)" % [sid, zmin, P.MOUNT_BACK])
		root.free()


func test_window_decor_centres_on_and_frames_the_window() -> void:
	var s := {"cres": _rec("crescent_window", Vector3(3, 0, 0), 0), "cz": _rec("crescent_window", Vector3(0, 0, 3), 90)}
	# [cell centre, rot, window centre in world]
	var cases := [[Vector3(2.5, 0, 0.5), 0, Vector3(3, 0, 0)], [Vector3(3.5, 0, 0.5), 0, Vector3(3, 0, 0)],
		[Vector3(3.5, 0, -0.5), 180, Vector3(3, 0, 0)], [Vector3(2.5, 0, -0.5), 180, Vector3(3, 0, 0)],
		[Vector3(0.5, 0, 2.5), 90, Vector3(0, 0, 3)], [Vector3(-0.5, 0, 3.5), 270, Vector3(0, 0, 3)]]
	for c in cases:
		var res := _v("flower_box", c[0], float(c[1]), s)
		assert_true(bool(res["ok"]), String(res["reason"]))
		var md := int(res.get("mount_dir", 0))
		assert_ne(md, 0, "a window variant for %s rot %d" % [str(c[0]), int(c[1])])
		var root := _model("flower_box", {"mount_dir": md})
		root.position = c[0]
		root.rotation.y = deg_to_rad(float(c[1]))
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in _verts(root):
			var w: Vector3 = root.transform * v
			lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
		var centre := (lo + hi) * 0.5
		var along := absf(centre.x - (c[2] as Vector3).x) if (int(c[1]) % 180) == 0 else absf(centre.z - (c[2] as Vector3).z)
		assert_true(along <= 0.03, "the box centres under the window (off by %.3f m) for %s" % [along, str(c[0])])
		assert_true(lo.y >= 0.35 and hi.y <= Parts.WINDOW_Y - 0.56 + 0.02, "sill height, under the round frame: %.2f..%.2f" % [lo.y, hi.y])
		root.free()
	# The saved record gets the same variant (structure model option).
	assert_eq(P.mount_dir_of(_rec("flower_box", Vector3(2.5, 0, 0.5), 0), s), 1)
	assert_eq(P.mount_dir_of(_rec("flower_box", Vector3(3.5, 0, 0.5), 0), s), -1)
	# Curtains: the two halves of a pair are mirror images, each drape on its outer side.
	var a := _model("curtain", {"mount_dir": 1})
	var b := _model("curtain", {"mount_dir": -1})
	var ax := [INF, -INF]
	var bx := [INF, -INF]
	var drape_a := 0.0
	for v in _verts(a):
		ax = [minf(ax[0], v.x), maxf(ax[1], v.x)]
		if v.y < 1.0:
			drape_a += v.x
	for v in _verts(b):
		bx = [minf(bx[0], v.x), maxf(bx[1], v.x)]
	assert_almost(float(ax[0]), -float(bx[1]), 0.01, "mirror pair")
	assert_true(drape_a < 0.0, "window on the +x side: the drape hangs on the -x side")
	a.free()
	b.free()
	# Curtains stand clear of window frames and sills (front of the frame torus / arched sill).
	var cur := _model("curtain", {"mount_dir": 1})
	var nearest := INF
	for v in _verts(cur):
		if v.y > 0.2 and v.y < 2.3 and absf(v.x) < 0.45:
			nearest = minf(nearest, v.z + 0.5)
	cur.free()
	assert_true(nearest >= 0.19, "curtain cloth stays %.3f m off the grid line, in front of frames (0.175) and sills (0.19)" % nearest)


func test_a_wall_with_decor_on_it_stays_up() -> void:
	var wall := GameState.add_structure("wood_wall", Vector3(1, 0, 0), 0)
	var bunting := GameState.add_structure("bat_bunting", Vector3(0.5, 0, 0.5), 0)
	var chk := Ops.can_dismantle(wall)
	assert_false(bool(chk["ok"]), "the bunting hangs on it")
	assert_eq(String(chk["reason"]), Ops.MSG_DECOR_ON_WALL % "Bat Bunting")
	assert_true(bool(Ops.can_dismantle(bunting)["ok"]), "the decor itself comes down any time")
	GameState.remove_structure(bunting)
	assert_true(bool(Ops.can_dismantle(wall)["ok"]), "then the wall can go")


# --- BU-01 / BU-08: roofs ------------------------------------------------------------------------------------------

## Triangles of a baked model mesh: [[a, b, c, colour (sRGB)], ...].
func _tris(sid: String) -> Array:
	var root := _model(sid)
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols: Variant = arr[Mesh.ARRAY_COLOR]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, ix.size(), 3):
				var col: Color = (cols as PackedColorArray)[ix[t]].linear_to_srgb() if cols is PackedColorArray else Color.WHITE
				out.append([v[ix[t]], v[ix[t + 1]], v[ix[t + 2]], col])
	root.free()
	return out


## First triangle hit by a ray: {"t": distance, "col": Color} ({} = none).
func _cast(tris: Array, from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for tr in tris:
		var a: Vector3 = tr[0]
		var b: Vector3 = tr[1]
		var c: Vector3 = tr[2]
		if maxf(a.x, maxf(b.x, c.x)) < from.x - 0.001 or minf(a.x, minf(b.x, c.x)) > from.x + 0.001:
			continue
		if maxf(a.z, maxf(b.z, c.z)) < from.z - 0.001 or minf(a.z, minf(b.z, c.z)) > from.z + 0.001:
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
		if hit is Vector3:
			var t := from.distance_to(hit as Vector3)
			if t < best_t:
				best_t = t
				best = {"t": t, "col": tr[3], "p": hit}
	return best


static func _is_straw(c: Color) -> bool:
	return c.s > 0.4 and c.h * 360.0 >= 33.0 and c.h * 360.0 <= 46.0


func test_no_straw_pokes_through_a_roof_ceiling() -> void:
	for sid in ["wood_roof", "gable_roof", "roof_corner"]:
		var tris := _tris(sid)
		var straw := 0
		var rays := 0
		for i in 9:
			for j in 9:
				# (x a hair off z: a ray exactly on the corner's hip plane only tests float coincidence of the seam)
				var from := Vector3(-0.88 + 0.22 * float(i) + 0.013, -0.6, -0.88 + 0.22 * float(j))
				var hit := _cast(tris, from, Vector3.UP)
				if hit.is_empty():
					continue
				rays += 1
				if _is_straw(hit["col"]):
					straw += 1
		assert_true(rays > 60, "%s has a ceiling over its tile (%d rays hit)" % [sid, rays])
		assert_eq(straw, 0, "%s: looking up from inside, %d of %d rays see straw instead of the timber under-slab" % [sid, straw, rays])


func test_roof_corner_meets_the_roof_tiles_at_the_same_height() -> void:
	var corner := _tris("roof_corner")
	var tile := _tris("wood_roof")
	var worst := 0.0
	for k in 8:
		var s := -0.55 + 0.2 * float(k)       # clear of the hip roll (which sits on the diagonal)
		# Face A (slopes to +Z) along the seam x = -0.9, and face B (slopes to +X) along z = -0.9 vs the tile turned.
		var a := _cast(corner, Vector3(-0.9, 5, s), Vector3.DOWN)
		var ta := _cast(tile, Vector3(-0.9, 5, s), Vector3.DOWN)
		var b := _cast(corner, Vector3(s, 5, -0.9), Vector3.DOWN)
		assert_false(a.is_empty() or ta.is_empty() or b.is_empty(), "surfaces found at %.2f" % s)
		if a.is_empty() or ta.is_empty() or b.is_empty():
			continue
		worst = maxf(worst, absf(float(a["t"]) - float(ta["t"])))
		worst = maxf(worst, absf(float(b["t"]) - float(ta["t"])))
		assert_true(_is_straw(a["col"]) and _is_straw(b["col"]), "thatch on top at %.2f" % s)
	assert_true(worst <= 0.05, "corner thatch is level with the roof tile's along both seams (worst %.3f m)" % worst)
	# Nothing (hip roll included) runs past the tile's own eave fringe.
	var tile_max := -INF
	for tr in tile:
		for q in 3:
			tile_max = maxf(tile_max, (tr[q] as Vector3).z)
	var corner_max := -INF
	for tr in corner:
		for q in 3:
			corner_max = maxf(corner_max, maxf((tr[q] as Vector3).x, (tr[q] as Vector3).z))
	assert_true(corner_max <= tile_max + 0.01, "corner stays inside the eave line (%.3f vs %.3f)" % [corner_max, tile_max])


# --- BU-03 / BU-09: stairs and upstairs walls -------------------------------------------------------------------------

func test_stair_balustrade_stays_inside_a_stairwell_railing() -> void:
	var root := _model("wood_stairs")
	var widest := 0.0
	for v in _verts(root):
		if v.y > P.STAIR_RISE:
			widest = maxf(widest, absf(v.x))
	root.free()
	# A railing / wall on the stairwell's grid line (local x = 1) reaches in to 0.94 (posts 0.12 wide).
	assert_true(widest < 0.94, "above the upper floor the stairs reach x %.3f (railing posts start at 0.94)" % widest)


## [[position, colour (sRGB)], ...] of every vertex of a model built with `opts`.
func _coloured(sid: String, opts: Dictionary = {}) -> Array:
	var root := _model(sid, opts)
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var cols: Variant = arr[Mesh.ARRAY_COLOR]
			if not (cols is PackedColorArray):
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				out.append([v[i], (cols as PackedColorArray)[i].linear_to_srgb()])
	root.free()
	return out


func test_upstairs_walls_drop_the_stone_footing() -> void:
	for sid in ["wood_wall", "wood_window", "wood_doorway", "half_wall", "arched_window", "crescent_window"]:
		var ground := 0
		for pc in _coloured(sid):
			if (pc[0] as Vector3).y < 0.45 and _is_stone(pc[1]):
				ground += 1
		var up := 0
		for pc in _coloured(sid, {"level": 1}):
			if (pc[0] as Vector3).y < 0.45 and _is_stone(pc[1]):
				up += 1
		assert_true(ground > 0, "%s keeps its cobbled footing on the ground" % sid)
		assert_eq(up, 0, "%s upstairs stands on a timber sill, no footing stones" % sid)
	# The ground mesh is still the Chapter One mesh (same cache key, no options).
	var a := _model("wood_wall")
	assert_eq(((a.get_child(0) as MeshInstance3D).mesh), preload("res://src/building/model_util.gd")._cache.get("baked|wood_wall"))
	a.free()


static func _is_stone(c: Color) -> bool:
	return c.s < 0.12 and c.v > 0.45 and c.v < 0.8


# --- BU-04 / BU-10: carved faces -----------------------------------------------------------------------------------

func test_every_carving_has_a_dark_rim_behind_it() -> void:
	var faces: Array = Seasonal.PUMPKIN_FACES + Seasonal.FESTIVAL_CARVINGS
	for f in faces:
		var root := Node3D.new()
		add_child(root)
		var parts: Dictionary = Seasonal.pumpkin_lantern(root, String(f))
		var glow := parts["face"] as MeshInstance3D
		var rim := root.get_node_or_null("FaceRim") as MeshInstance3D
		assert_not_null(rim, "%s has a rim" % f)
		if rim != null:
			var gv: int = (glow.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var rv: int = (rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			assert_true(rv >= gv and rv > 0, "%s: a rim blob behind every cut (%d / %d verts)" % [f, rv, gv])
			var rc: Color = (rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0].linear_to_srgb()
			assert_true(rc.v < 0.4, "%s rim is dark (v %.2f)" % [f, rc.v])
			assert_true(rim.mesh.get_aabb().size.x > glow.mesh.get_aabb().size.x, "%s rim shows around the cut" % f)
			assert_true(rim.mesh.get_aabb().end.z < glow.mesh.get_aabb().end.z, "%s glow sits in front of its rim" % f)
		root.free()


# --- BU-06: recolouring keeps accents ----------------------------------------------------------------------------------

func _changed(sid: String, tint: String, family: String = "") -> Dictionary:
	var root := _model(sid)
	var out := {"wood": 0, "kept_changed": 0, "red": 0, "teal_changed": 0}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).mesh as ArrayMesh
		if m == null or not (m.surface_get_arrays(0)[Mesh.ARRAY_COLOR] is PackedColorArray):
			continue
		var before: PackedColorArray = m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var after: PackedColorArray = Tints.tinted_mesh(m, tint, family).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for i in before.size():
			var c0 := before[i].linear_to_srgb()
			var d := before[i] - after[i]
			var moved := maxf(absf(d.r), maxf(absf(d.g), absf(d.b))) > 0.004
			if Tints.is_kept(before[i]) and moved:
				out["kept_changed"] += 1
			if moved and absf(c0.h * 360.0 - 29.0) < 10.0:
				out["wood"] += 1
			if moved and c0.s > 0.4 and _hue_near(c0, 350.0, 8.0):
				out["red"] += 1
			if moved and c0.s > 0.4 and _hue_near(c0, 176.0, 8.0):
				out["teal_changed"] += 1
	root.free()
	return out


static func _hue_near(c: Color, hue: float, tol: float) -> bool:
	var d := absf(fposmod(c.h * 360.0 - hue, 360.0))
	return minf(d, 360.0 - d) <= tol


func test_recolouring_dyes_the_wood_and_keeps_the_accents() -> void:
	for sid in ["bookshelf", "vanity_mirror", "storage_chest", "bed", "kitchen_counter", "wardrobe"]:
		var r := _changed(sid, "midnight")
		assert_true(int(r["wood"]) > 0, "%s: its wood is dyed" % sid)
		assert_eq(int(r["kept_changed"]), 0, "%s: brass, books and patchwork keep their colours" % sid)
		assert_eq(int(r["teal_changed"]), 0, "%s: teal accents stay teal" % sid)
	assert_eq(int(_changed("bed", "midnight")["red"]), 0, "the bed's quilt stays red when its frame is dyed")
	assert_true(int(_changed("curtain", "midnight")["red"]) > 0, "curtains are dyed by their cloth")
	assert_true(int(_changed("companion_bed", "midnight", "main")["red"]) > 0, "the companion bed's cushion takes the dye")
	var t := Color("5a4a6e")
	var brass := Tints.keep(Palette.K_SCARF)
	assert_eq(Tints.dye(brass, t, {"hue": 29.0, "band": Tints.WOOD_BAND}), brass, "a kept colour never moves")
	assert_eq(Tints.dye(Palette.TEAL, t, {"hue": 29.0, "band": Tints.WOOD_BAND}), Palette.TEAL, "off-family hues never move")
	assert_ne(Tints.dye(Palette.WOOD, t, {"hue": 29.0, "band": Tints.WOOD_BAND}), Palette.WOOD, "wood moves")
