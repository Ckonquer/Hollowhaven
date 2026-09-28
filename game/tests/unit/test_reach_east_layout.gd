extends "res://tests/test_case.gd"
## Ashbell Quarry layout and ground (data/reach_east.gd, src/world/reach/east/quarry_shape.gd, the district
## interface src/world/reach/districts/quarry.gd): the frame matches the Reach layout, node ids are unique,
## prefixed, renewable and at least the data/sources.gd min counts, every site is inside the landmark circle and
## clear of the region's arch, the terraces/ramps/shelf levels are what the design says, the upper shelf is
## joined to the rest ONLY by cliffs (the gangway is the one way up), and the terrain pass works on the real
## terrain layouts (surface Terrain N/HALF, Reach terrain NX/NZ/HALF_X/HALF_Z through reach_districts.gd).

const Q := preload("res://data/reach_east.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Sources := preload("res://data/sources.gd")
const Shape := preload("res://src/world/reach/east/quarry_shape.gd")
const Builder := preload("res://src/world/reach/east/quarry_builder.gd")
const District := preload("res://src/world/reach/districts/quarry.gd")
const SurfaceTerrain := preload("res://src/world/surface/terrain.gd")

const REACH_TERRAIN := "res://src/world/reach/reach_terrain.gd"
const REACH_DISTRICTS := "res://src/world/reach/reach_districts.gd"


func before_each() -> void:
	fresh_state()


func test_frame_matches_the_reach_layout() -> void:
	var lm: Dictionary = Reach.LANDMARKS["hr_quarry"]
	assert_eq(lm["pos"], Q.CENTER, "centre")
	assert_almost(float(lm["radius"]), Q.RADIUS, 0.001, "radius")
	var u: Vector2 = (Reach.POINTS["moon_crystal_shelf"] - Q.CENTER).normalized()
	assert_almost(u.x, Q.AXIS_U.x, 0.0005, "AXIS_U.x")
	assert_almost(u.y, Q.AXIS_U.y, 0.0005, "AXIS_U.y")
	assert_almost(Q.AXIS_U.dot(Q.AXIS_V), 0.0, 0.0005, "axes perpendicular")
	assert_almost(Q.AXIS_V.length(), 1.0, 0.0005, "AXIS_V unit")
	assert_eq(Q.ARENA, Reach.POINTS["warden_arena"], "arena centre = layout point")
	assert_eq(Q.ARCH, Reach.POINTS["quarry_arch"], "arch = layout point")
	var crane := Shape.to_world(Q.WINCH["crane"])
	assert_true(crane.distance_to(Reach.POINTS["winch"]) < 2.0, "the winch crane stands on the layout winch point (%s)" % crane)
	var road: Array = Reach.PATHS["quarry_bellhouse"]
	assert_eq(road[road.size() - 1], Q.NORTH_MOUTH, "the north mouth is where the Bellhouse road ends")
	var a := Shape.to_local(Q.ARENA.x, Q.ARENA.y)
	assert_true(Shape.to_world(a).distance_to(Q.ARENA) < 0.001, "to_world(to_local) round trip")
	assert_true(Vector2(8.938, -0.319).distance_to(a) < 0.01, "arena spawner local position matches")
	assert_eq(District.footprints(), [[Q.CENTER, Q.RADIUS]], "footprint = the landmark circle")


## The entry script keeps its own compile light (the builder is requested on a loader thread from footprints())
## and build() gets the builder either from that request or from a plain load.
func test_district_entry_and_builder_warm_up() -> void:
	var names: Array = (District as Script).get_script_method_list().map(func(d: Dictionary) -> String: return String(d["name"]))
	for m in ["footprints", "shape_terrain", "build"]:
		assert_true(names.has(m), "spec §10 interface: " + m)
	var src := FileAccess.get_file_as_string("res://src/world/reach/districts/quarry.gd")
	assert_false(src.contains("preload(\"res://src/world/reach/east/quarry_builder.gd\")"), "the entry script does not preload the builder")
	# nothing requested: a plain (cached) load
	District._requested = false
	assert_eq(District.builder_script(), Builder, "builder without a request")
	# a pending threaded request is picked up once (the builder is cached here, so it completes at once)
	assert_eq(ResourceLoader.load_threaded_request(District.BUILDER_PATH, "", false), OK, "threaded request accepted")
	District._requested = true
	assert_eq(District.builder_script(), Builder, "builder from the threaded request")
	assert_false(bool(District._requested), "the request is consumed")
	assert_eq(District.builder_script(), Builder, "later calls load normally")
	# warm_up() never re-requests a loaded builder
	District.warm_up()
	assert_false(bool(District._requested), "cached builder: no request")
	# the quarry's enemy ids come from its spawner table; warmed requests are always collected
	assert_eq(District.enemy_ids(), ["quarry_warden", "bellcap_sentry"], "enemy ids from data/reach_east.gd SPAWNERS")
	District.collect_enemy_scripts()
	assert_true((District._enemy_requests as Array).is_empty(), "no enemy request left pending")


func test_node_ids_unique_prefixed_renewable_and_counted() -> void:
	var plan := Builder.node_plan()
	var seen := {}
	var per_kind := {}
	for e in plan:
		var id := String(e["id"])
		assert_true(id.begins_with("hr_"), "Reach prefix: " + id)
		assert_false(seen.has(id), "unique: " + id)
		seen[id] = true
		var sk := String(e["source_kind"])
		per_kind[sk] = int(per_kind.get(sk, 0)) + 1
		var nd: Dictionary = Sources.NODES[sk]
		assert_true(float(nd["respawn_minutes"]) > 0.0, "renewable: " + id)
		assert_true((nd["where"] as Dictionary).has("hallowmere_reach") and (nd["where"]["hallowmere_reach"] as Array).has("hr_quarry"), "sources.gd places %s in hr_quarry" % sk)
	for sk in ["iron_vein", "moon_crystal_vein", "ore", "rock", "stone"]:
		var need := int((Sources.NODES[sk]["min_count"] as Dictionary).get("hallowmere_reach", 0))
		assert_true(int(per_kind.get(sk, 0)) >= need, "%s: %d >= min_count %d" % [sk, int(per_kind.get(sk, 0)), need])
	assert_eq(int(Sources.NODES["iron_vein"]["min_tier"]), 1, "iron: any pickaxe")
	assert_eq(int(Sources.NODES["moon_crystal_vein"]["min_tier"]), 3, "moon crystal: Ironwood or better")
	assert_eq(String(Sources.NODES["moon_crystal_vein"]["access_flag"]), Q.FLAG_WINCH, "the shelf opens with the winch flag")
	assert_true(Builder.node_plan() == plan, "node plan is deterministic")
	# The flag the lamp sets and the winch flag are the catalogue's own names.
	assert_true(ItemDB.unlock_flags().has(Q.FLAG_WINCH), "ch2_winch_repaired is a data/unlocks.gd flag")


func test_sites_inside_the_circle_clear_of_the_arch_and_each_other() -> void:
	var plan := Builder.node_plan()
	var pts: Array = []
	for e in plan:
		var w: Vector2 = e["pos"]
		var l: Vector2 = e["local"]
		var id := String(e["id"])
		assert_true(w.distance_to(Q.CENTER) <= Q.RIM_FLAT - 1.4, "inside the quarry: %s at r=%.1f" % [id, w.distance_to(Q.CENTER)])
		assert_true(w.distance_to(Q.ARCH) >= Q.ARCH_CLEAR, "clear of the region's arch: " + id)
		assert_true(Shape.ramp_at_local(l.x, l.y).is_empty(), "not on a ramp: " + id)
		for su in [float(Q.STEP_U[0]), float(Q.STEP_U[1])]:
			assert_true(absf(l.x - su) >= 1.4, "clear of the terrace step at U=%.1f: %s" % [su, id])
		var on_shelf := Shape.is_shelf(w.x, w.y)
		if on_shelf:
			assert_true(l.x - Q.U_CLIFF >= 1.4, "clear of the shelf lip: " + id)
		else:
			assert_true(absf(l.x - Q.U_CLIFF) >= 1.4 or l.y < Q.SHELF_WEST_V - 1.4, "clear of the cliff foot: " + id)
		if String(e["table"]) == "moon_crystal":
			assert_true(on_shelf, "moon crystal on the upper shelf: " + id)
			assert_true(absf(l.y - Q.SHELF_WEST_V) >= 1.4, "clear of the shelf's west cliff: " + id)
		else:
			assert_false(on_shelf, "lower-quarry node not on the shelf: " + id)
		pts.append([id, w])
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d: float = (pts[i][1] as Vector2).distance_to(pts[j][1])
			assert_true(d >= 2.0, "nodes %s and %s are %.2f m apart" % [pts[i][0], pts[j][0], d])
	# set pieces
	var pieces := {"winch_station": Q.WINCH["station"], "lamp": Q.LAMP, "log": Q.LOG_NOTE, "shed": Q.SHED, "sign": Q.SIGN,
		"crane": Q.WINCH["crane"]}
	for k in pieces:
		var w := Shape.to_world(pieces[k])
		assert_true(w.distance_to(Q.CENTER) <= Q.RIM_FLAT - 1.0, "%s inside the quarry" % k)
		assert_true(w.distance_to(Q.ARCH) >= Q.ARCH_CLEAR, "%s clear of the arch" % k)
		for p in pts:
			assert_true((p[1] as Vector2).distance_to(w) >= 2.2, "%s clear of node %s" % [k, p[0]])
	var ashbell := Shape.to_world(Q.ASHBELL)
	assert_eq(Shape.terrace_at_local(Q.ASHBELL.x, Q.ASHBELL.y), 2, "the Ashbell sits on the L2 bench")
	assert_true(ashbell.distance_to(Q.ARENA) >= Q.ARENA_RADIUS + 2.0, "the Ashbell stays out of the open arena")
	for p in pts:
		assert_true((p[1] as Vector2).distance_to(ashbell) >= 3.0, "the Ashbell is clear of node %s" % p[0])
	assert_true(Shape.is_shelf(Shape.to_world(Q.LAMP).x, Shape.to_world(Q.LAMP).y), "the lamp is on the upper shelf")
	assert_true(Shape.is_shelf(Shape.to_world(Q.WINCH["crane"]).x, Shape.to_world(Q.WINCH["crane"]).y), "the crane is on the shelf")
	var st := Shape.to_world(Q.WINCH["station"])
	assert_false(Shape.is_shelf(st.x, st.y), "the winch drum is reachable below")
	# pillars: >= 2, inside the open arena floor, apart
	assert_true(Q.PILLARS.size() >= 2, "at least two pillars")
	for i in Q.PILLARS.size():
		var pw := Shape.to_world(Q.PILLARS[i])
		assert_true(pw.distance_to(Q.ARENA) <= Q.ARENA_RADIUS - 2.0, "pillar %d inside the arena" % i)
		assert_eq(Shape.terrace_at_local(float(Q.PILLARS[i].x), float(Q.PILLARS[i].y)), 2, "pillar %d on the arena bench" % i)
		for j in range(i + 1, Q.PILLARS.size()):
			assert_true(pw.distance_to(Shape.to_world(Q.PILLARS[j])) >= 6.0, "pillars %d/%d spaced" % [i, j])
	# the arena floor is one flat bench, clear of the cliff
	for k in 36:
		var a := TAU * float(k) / 36.0
		var p := Q.ARENA + Vector2(cos(a), sin(a)) * Q.ARENA_RADIUS
		var l := Shape.to_local(p.x, p.y)
		assert_eq(Shape.terrace_at_local(l.x, l.y), 2, "arena rim point %d on L2" % k)
		assert_true(Shape.ramp_at_local(l.x, l.y).is_empty(), "arena rim point %d not on a ramp" % k)
	for sid in Q.SPAWNERS:
		var sw := Shape.to_world(Q.SPAWNERS[sid]["at"])
		assert_true(sw.distance_to(Q.CENTER) < Q.RIM_FLAT - 2.0, "%s inside" % sid)
		assert_true(String(sid).begins_with("hr_sp_"), "spawner id prefix")
	var bd: Dictionary = Q.SPAWNERS["hr_sp_bellcaps"]
	var bell := Shape.to_world(bd["at"])
	assert_true(bell.distance_to(Q.ARENA) >= 18.0, "the Bellcap pocket is apart from the Warden arena")
	# No Bellcap (spawn radius + wander) can notice Krystal anywhere on the arena floor (data aggro_radius): the
	# Warden stays a one-on-one lesson.
	var aggro := float(ItemDB.enemy(String(bd["enemy"])).get("aggro_radius", 9.0))
	var closest := bell.distance_to(Q.ARENA) - float(bd["radius"]) - float(bd["wander"])
	assert_true(closest - aggro >= Q.ARENA_RADIUS, "Bellcaps can't aggro from the arena floor (closest %.1f m, aggro %.1f m)" % [closest, aggro])
	var bl := Vector2(bd["at"])
	assert_true(Shape.ramp_at_local(bl.x, bl.y).is_empty(), "the pocket centre is not on a ramp")
	var lvl := Shape.terrace_at_local(bl.x, bl.y)
	for k in 12:
		var a := TAU * float(k) / 12.0
		var e := bl + Vector2(cos(a), sin(a)) * float(bd["radius"])
		assert_true(Shape.level_at_local(e.x, e.y) - float(Q.LEVELS[lvl]) <= 1.6, "pocket spawn ring point %d within the spawner's step limit" % k)
		assert_true(Shape.to_world(e).distance_to(Q.CENTER) <= Q.RIM_FLAT - 0.5, "pocket spawn ring point %d inside the quarry" % k)
	for m in Q.BELLCAP_MARKERS:
		var mv := Vector2(m)
		assert_true(Shape.ramp_at_local(mv.x, mv.y).is_empty() and Shape.to_world(mv).distance_to(Q.CENTER) <= Q.RIM_FLAT - 1.0, "toadstool marker %s placed on a bench" % mv)
		assert_true(mv.distance_to(bl) <= 6.0, "toadstool marker %s marks the pocket" % mv)


func test_levels_ramps_and_weights() -> void:
	assert_almost(Shape.level_at_local(-22.0, 0.0), 0.0, 0.0001, "apron")
	assert_almost(Shape.level_at_local(-8.0, 9.0), 1.4, 0.0001, "L1")
	assert_almost(Shape.level_at_local(8.0, 12.0), 2.8, 0.0001, "L2")
	assert_almost(Shape.level_at_local(24.0, 3.0), 7.4, 0.0001, "shelf")
	assert_almost(Shape.level_at_local(24.0, -12.0), 2.8, 0.0001, "north-west of the shelf stays L2 (north mouth)")
	for r in Q.RAMPS:
		var ur: Array = r["u"]
		var vr: Array = r["v"]
		var vm := (float(vr[0]) + float(vr[1])) * 0.5
		assert_almost(Shape.level_at_local(float(ur[0]) - 0.01, vm), float(r["h"][0]), 0.0001, "%s joins its lower terrace" % r["id"])
		assert_almost(Shape.level_at_local(float(ur[1]) + 0.01, vm), float(r["h"][1]), 0.0001, "%s joins its upper terrace" % r["id"])
		var rise := float(r["h"][1]) - float(r["h"][0])
		var run := float(ur[1]) - float(ur[0])
		assert_true(rad_to_deg(atan(rise / run)) <= 16.0, "%s is a gentle ramp" % r["id"])
		assert_true(float(vr[1]) - float(vr[0]) >= 3.5, "%s is wide" % r["id"])
	assert_almost(Shape.weight_at(Q.CENTER.x, Q.CENTER.y), 1.0, 0.0001, "full weight inside")
	assert_almost(Shape.weight_at(Q.ARCH.x, Q.ARCH.y), 0.0, 0.0001, "natural ground at the arch")
	assert_almost(Shape.weight_at(Q.NORTH_MOUTH.x, Q.NORTH_MOUTH.y), 0.0, 0.0001, "natural ground at the Bellhouse road")
	assert_almost(Shape.weight_at(Q.CENTER.x + 29.9, Q.CENTER.y), 0.0, 0.0001, "nothing is shaped at the circle's edge")
	assert_almost(Shape.shaped_height(0.0, 0.0, 3.3, 1.0), 3.3, 0.0001, "outside: unchanged")


## The shelf touches the rest of the quarry only through >= 4 m cliffs (the gangway is the one way up), and the
## arch / north-mouth blends never soften the shelf's edges.
func test_shelf_is_only_reachable_by_the_gangway_in_the_design() -> void:
	var step := 0.5
	var bad := 0
	var checked := 0
	var x := Q.CENTER.x - 30.0
	while x <= Q.CENTER.x + 30.0:
		var z := Q.CENTER.y - 30.0
		while z <= Q.CENTER.y + 30.0:
			if Shape.is_shelf(x, z):
				if Shape.weight_at(x, z) < 0.9999:
					bad += 1
				for d in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
					var nx: float = x + d.x
					var nz: float = z + d.y
					if Shape.is_shelf(nx, nz) or Vector2(nx, nz).distance_to(Q.CENTER) > Q.RIM_FLAT:
						continue
					checked += 1
					var hs := Shape.shaped_height(x, z, 0.0, 0.0)
					var hn := Shape.shaped_height(nx, nz, 0.0, 0.0)
					if hs - hn < 4.0:
						bad += 1
			z += step
		x += step
	assert_true(checked > 50, "the shelf has cliff edges (%d)" % checked)
	assert_eq(bad, 0, "shelf edge samples that are not a >= 4 m cliff")


func test_terrain_pass_on_the_surface_terrain_layout() -> void:
	var t: RefCounted = SurfaceTerrain.new()
	t.h.resize(SurfaceTerrain.N * SurfaceTerrain.N)
	t.h.fill(0.5)
	var g := Shape.detect_grid(t)
	assert_eq(String(g.get("array", "")), "h", "height array found")
	assert_almost(float(g.get("x0", 0.0)), -128.0, 0.001, "origin from HALF")
	var rep := Shape.apply(t)
	assert_true(bool(rep["ok"]), "shaped: %s" % rep)
	assert_almost(float(rep["floor"]), 0.5, 0.001, "floor = the natural ground at the arch")
	var arena_h: float = t.height_at(Q.ARENA.x, Q.ARENA.y)
	assert_almost(arena_h, 0.5 + 2.8, 0.001, "arena bench")
	var sh := Shape.to_world(Vector2(24.0, 3.0))
	assert_almost(float(t.height_at(sh.x, sh.y)), 0.5 + 7.4, 0.001, "upper shelf")
	assert_almost(float(t.height_at(Q.CENTER.x + 35.0, Q.CENTER.y)), 0.5, 0.0001, "outside the circle untouched")
	assert_almost(float(t.height_at(Q.ARCH.x, Q.ARCH.y)), 0.5, 0.0001, "the arch keeps its ground")
	# deterministic
	var t2: RefCounted = SurfaceTerrain.new()
	t2.h.resize(SurfaceTerrain.N * SurfaceTerrain.N)
	t2.h.fill(0.5)
	Shape.apply(t2)
	assert_true(t.h == t2.h, "the same input gives the same ground")


## Through the region's own loader + terrain (when present): edits stay in the circle, the floor meets the
## quarry arch plaza, and the colour / stone / road helpers are used.
func test_terrain_pass_through_the_reach_loader() -> void:
	if not ResourceLoader.exists(REACH_TERRAIN) or not ResourceLoader.exists(REACH_DISTRICTS):
		print("  (reach terrain not present yet - skipped)")
		return
	var ts: Script = load(REACH_TERRAIN)
	var ds: Script = load(REACH_DISTRICTS)
	if ts == null or not ts.can_instantiate() or ds == null or not ds.can_instantiate():
		print("  (reach terrain does not compile right now - skipped)")
		return
	var t: RefCounted = ts.new()
	t.generate_base()
	var before: PackedFloat32Array = t.h.duplicate()
	var qs: Script = load("res://src/world/reach/districts/quarry.gd")
	ds.call("shape_one", t, qs, Vector3(Q.CENTER.x, Q.CENTER.y, Q.RADIUS))
	var rep := District.shape_report()
	assert_true(bool(rep.get("ok", false)), "the quarry read the Reach terrain: %s" % rep)
	var floor_y := float(t.plaza_height("quarry_arch"))
	assert_almost(float(rep.get("floor", -99.0)), floor_y, 0.001, "floor = the quarry arch plaza height")
	assert_almost(float(t.height_at(Q.ARENA.x, Q.ARENA.y)), floor_y + 2.8, 0.001, "arena bench on the Reach terrain")
	var sh := Shape.to_world(Vector2(24.0, 3.0))
	assert_almost(float(t.height_at(sh.x, sh.y)), floor_y + 7.4, 0.001, "shelf on the Reach terrain")
	var outside_changed := 0
	for k in before.size():
		if before[k] != t.h[k]:
			var x := float(k % int(t.NX)) - float(t.HALF_X)
			var z := float(k / int(t.NX)) - float(t.HALF_Z)
			if Vector2(x, z).distance_to(Q.CENTER) > Q.RADIUS:
				outside_changed += 1
	assert_eq(outside_changed, 0, "no sample outside the landmark circle changed")
	assert_true((t.tint_ops as Array).size() >= Q.TINTS.size(), "copper-red ground tints recorded")
	var stone_ok := false
	for s in t.stone_discs:
		if (s[0] as Vector2).distance_to(Q.CENTER) < 0.1:
			stone_ok = true
	assert_true(stone_ok, "stone footsteps in the quarry")
