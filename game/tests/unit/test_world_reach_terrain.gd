extends "res://tests/test_case.gd"
## Hallowmere Reach terrain (pure, no scene): determinism, plazas, Thimblebrook, the Bellhouse stair,
## the district shaping guard and the shader mapping.

const Terrain := preload("res://src/world/reach/reach_terrain.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Districts := preload("res://src/world/reach/reach_districts.gd")
const WorldLayout := preload("res://data/world_layout.gd")

static var _t: RefCounted = null


func _terrain() -> RefCounted:
	if _t == null:
		_t = Terrain.new()
		_t.generate()
		print("    reach terrain: %.0f ms %s" % [float(_t.gen_ms), str(_t.times)])
	return _t


func test_generation_is_deterministic_and_fast() -> void:
	var t0 := Time.get_ticks_msec()
	var a: RefCounted = Terrain.new()
	a.generate()
	var ms := Time.get_ticks_msec() - t0
	var b: RefCounted = _terrain()
	for p in [Vector2(0, 0), Vector2(33.3, -44.4), Vector2(-80, 70), Vector2(72, -74), Vector2(-120, -90), Vector2(130, 100)]:
		assert_almost(float(a.height_at(p.x, p.y)), float(b.height_at(p.x, p.y)), 0.0001, "same height at %s" % p)
	assert_eq(a.h.size(), Terrain.NX * Terrain.NZ, "grid size")
	assert_true(ms < 900, "terrain generates quickly (%d ms)" % ms)


func test_heights_are_sane_and_above_kill_y() -> void:
	var t: RefCounted = _terrain()
	var lo := 1e9
	var hi := -1e9
	for v in t.h:
		assert_false(is_nan(v) or is_inf(v), "finite heights")
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("    heights %.2f .. %.2f" % [lo, hi])
	assert_true(lo > WorldLayout.KILL_Y + 20.0, "the lowest ground (%.1f) is far above KILL_Y" % lo)
	assert_true(hi < 60.0, "hills stay reasonable (%.1f)" % hi)
	# Soft boundary: the hills behind the walls are clearly higher than the plazas.
	var commons := float(t.plaza_height("commons"))
	for p in [Vector2(150, 0), Vector2(-150, 0), Vector2(0, 120), Vector2(0, -120)]:
		assert_true(float(t.height_at(p.x, p.y)) > commons + 6.0, "hills rise beyond the edge at %s" % p)


func test_plazas_are_flat() -> void:
	var t: RefCounted = _terrain()
	for id in Reach.PLAZAS:
		var pl: Array = Reach.PLAZAS[id]
		var c: Vector2 = pl[0]
		var r: float = float(pl[1]) * 0.8
		var h0: float = t.height_at(c.x, c.y)
		var worst := 0.0
		for a in 12:
			var q := c + Vector2(cos(a * TAU / 12.0), sin(a * TAU / 12.0)) * r
			if t.path_at(q.x, q.y) > 0.3 or t.stream_distance(q.x, q.y) < 6.0:
				continue
			worst = maxf(worst, absf(float(t.height_at(q.x, q.y)) - h0))
		var tol := 0.45 if id != "bellhouse" else 0.2
		assert_true(worst < tol, "plaza %s is flat (worst %.2f m)" % [id, worst])
	assert_true(float(t.plaza_height("arrival")) > float(t.plaza_height("commons")) + 1.0, "the arrival looks down into the Commons")
	assert_almost(float(t.plaza_height("outpost")), float(t.plaza_height("commons")), 0.001, "the outpost lot shares the Commons level")


func test_brook_flows_downhill_and_stays_shallow() -> void:
	var t: RefCounted = _terrain()
	var pts: PackedVector3Array = t.stream_pts
	assert_true(pts.size() > 100, "a real brook")
	for k in range(1, pts.size()):
		assert_true(pts[k].y <= pts[k - 1].y + 0.0001, "the brook never flows uphill (sample %d)" % k)
	var deepest := 0.0
	for k in range(0, pts.size(), 3):
		var p := pts[k]
		if not Reach.is_inside(Vector2(p.x, p.z), 4.0):
			continue
		deepest = maxf(deepest, float(t.water_level_at(p.x, p.z)) - float(t.height_at(p.x, p.z)))
	assert_true(deepest < 0.7, "the brook is a wade, never a swim (deepest %.2f m)" % deepest)
	# The brook keeps off the Commons, the outpost lot and the arrival.
	for id in ["commons", "outpost", "arrival", "crossroads"]:
		var c: Vector2 = Reach.PLAZAS[id][0]
		var r: float = Reach.PLAZAS[id][1]
		assert_true(float(t.stream_distance(c.x, c.y)) > r, "the brook stays out of %s" % id)
	for sp in Reach.SPAWNS:
		var p: Vector2 = Reach.SPAWNS[sp]["pos"]
		assert_false(t.is_water(p.x, p.y), "spawn %s is dry" % sp)


func test_bellhouse_stairwell() -> void:
	var t: RefCounted = _terrain()
	var B: Dictionary = Reach.BELLHOUSE
	var hb := float(t.bellhouse_level)
	var sx: float = B["stair_x"]
	assert_almost(float(t.height_at(sx, float(B["ramp_top_z"]) + 0.5)), hb, 0.05, "stair top at the forecourt")
	assert_almost(float(t.height_at(sx, float(B["gate_z"]))), hb - float(B["depth"]), 0.05, "stair bottom at the gate")
	assert_false(t.is_water(sx, float(B["gate_z"])), "the stairwell is dry")
	var p: Vector2 = B["pond"]
	assert_true(t.is_water(p.x - 8.0, p.y), "still water beside the tower")
	assert_true(float(t.water_level_at(p.x - 8.0, p.y)) - float(t.height_at(p.x - 8.0, p.y)) > 0.6, "the pond is deeper than a saved position allows")
	assert_eq(t.surface_at(72.0, -71.0), "stone", "the forecourt is paved")


func test_district_shaping_stays_inside_its_circle() -> void:
	var t: RefCounted = Terrain.new()
	t.generate_base()
	var inside := Vector2(-44, -8) + Vector2(5, 3)
	var outside := Vector2(-44, -8) + Vector2(25, 0)
	var hin: float = t.get_height(inside.x, inside.y)
	var hout: float = t.get_height(outside.x, outside.y)
	var hflat: float = t.get_height(-20.0, -8.0)
	var s := GDScript.new()
	s.source_code = "extends RefCounted\n\nstatic func shape_terrain(terrain) -> void:\n\tfor k in terrain.h.size():\n\t\tterrain.h[k] = terrain.h[k] + 3.0\n\tterrain.tint_disc(Vector2(-44, -8), 5.0, 60.0, Color(1, 0, 0), 1.0)\n\tterrain.flatten(Vector2(-20, -8), 3.0, 6.0, 50.0)\n"
	assert_eq(s.reload(), OK, "fixture compiles")
	Districts.shape_one(t, s, Districts.landmark_circle("hr_pools"))
	assert_almost(float(t.get_height(inside.x, inside.y)), hin + 3.0, 0.001, "edits inside the landmark circle are kept")
	assert_almost(float(t.get_height(outside.x, outside.y)), hout, 0.001, "edits outside the landmark circle are discarded")
	assert_almost(float(t.get_height(-20.0, -8.0)), hflat, 0.001, "shaping helpers outside the circle do nothing")
	assert_true(float(t.limit.z) < 0.0, "the shaping limit is cleared afterwards")
	var op: Array = t.tint_ops[t.tint_ops.size() - 1]
	assert_true(float(op[2]) <= 18.0, "a district tint is clamped to its circle (%.1f)" % float(op[2]))
	t.finish()
	assert_true(t.col.size() == Terrain.NX * Terrain.NZ, "finish() colours the grid after shaping")


func test_shader_mapping_matches_the_grid() -> void:
	var t: RefCounted = _terrain()
	# uv = (world - origin + 0.5) / samples must land on texel centres for every sample.
	for ij in [Vector2i(0, 0), Vector2i(160, 128), Vector2i(320, 256), Vector2i(17, 201)]:
		var x: float = t.sample_x(ij.x)
		var z: float = t.sample_z(ij.y)
		var uv := (Vector2(x, z) - Terrain.ORIGIN + Vector2(0.5, 0.5)) / Vector2(Terrain.NX, Terrain.NZ)
		assert_almost(uv.x * Terrain.NX - 0.5, float(ij.x), 0.0001, "u of sample %s" % ij)
		assert_almost(uv.y * Terrain.NZ - 0.5, float(ij.y), 0.0001, "v of sample %s" % ij)
	assert_eq(t.splat_image().get_size(), Vector2i(Terrain.NX, Terrain.NZ), "splat image size")
	assert_eq(t.height_image().get_size(), Vector2i(Terrain.NX, Terrain.NZ), "height image size")
