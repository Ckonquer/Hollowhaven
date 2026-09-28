extends "res://tests/unit/test_reach_west_fixture.gd"
## Reach west districts on the REAL region terrain (module C1's src/world/reach/reach_terrain.gd +
## reach_districts.gd, built in parallel): our shape_terrain() edits stay inside our landmark circles and level
## our sites; our content stands on the terrain collider and stays connected. Skips (with a note) while the
## region scripts are missing.

const TERRAIN := "res://src/world/reach/reach_terrain.gd"
const LOADER := "res://src/world/reach/reach_districts.gd"
const MINE := ["orchard", "pools", "candleyard"]


class TerrainHost extends "res://src/world/areas_ch2/placeholder_area.gd":
	var terrain: RefCounted = null

	func height_at(x: float, z: float) -> float:
		return float(terrain.height_at(x, z))


func _region_ready() -> bool:
	for p in [TERRAIN, LOADER]:
		if not ResourceLoader.exists(p):
			print("  SKIP reach_west_region: %s not present yet (region module in progress)" % p)
			return false
	return true


func _terrain(shaped: bool) -> RefCounted:
	var ts: Script = load(TERRAIN)
	var ds: Script = load(LOADER)
	var t: RefCounted = ts.new()
	t.generate_base()
	if shaped:
		var entries: Array = []
		for e in ds.call("default_entries"):
			if MINE.has(String(e["id"])):
				entries.append(e)
		var loaded: Array = ds.call("load_all", entries)
		assert_eq(loaded.size(), 3, "the region loader finds our three districts")
		ds.call("shape_all", t, loaded)
		var fps: Array = ds.call("footprints", loaded)
		assert_eq(fps.size(), Data.ORCHARD_FOOTPRINTS.size() + Data.POOLS_FOOTPRINTS.size() + Data.CANDLEYARD_FOOTPRINTS.size(), "our footprints reach the region")
	t.finish()
	return t


func _spread(t: RefCounted, c: Vector2, r: float) -> float:
	var lo := INF
	var hi := -INF
	var n := int(ceil(r))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var p := c + Vector2(dx, dz)
			if p.distance_to(c) > r:
				continue
			var y := float(t.height_at(p.x, p.y))
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return hi - lo


func test_shaping_stays_inside_our_circles_and_levels_our_sites() -> void:
	if not _region_ready():
		return
	fresh_state()
	var t0: RefCounted = _terrain(false)
	var t1: RefCounted = _terrain(true)
	var changed_inside := 0
	var changed_outside := 0
	for z in range(-100, 80, 2):
		for x in range(-138, -10, 2):
			var p := Vector2(x, z)
			var dy := absf(float(t1.height_at(p.x, p.y)) - float(t0.height_at(p.x, p.y)))
			var inside := false
			for id in [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]:
				inside = inside or p.distance_to(Data.center_of(id)) <= Data.radius_of(id) + 1.5
			if dy > 0.001:
				if inside:
					changed_inside += 1
				else:
					changed_outside += 1
	assert_true(changed_inside > 50, "our districts shaped their ground (%d samples)" % changed_inside)
	assert_eq(changed_outside, 0, "nothing changed outside our landmark circles")
	assert_true(_spread(t1, Data.GARDEN["bed"], 4.0) < 0.06, "the festival garden is level (%.3f m)" % _spread(t1, Data.GARDEN["bed"], 4.0))
	assert_true(_spread(t1, Data.MIMIC_POCKET["center"], 5.0) < 0.06, "the mimic pocket is level")
	for pd in Data.POOL_DISCS:
		assert_true(_spread(t1, pd[0], float(pd[1])) <= _spread(t0, pd[0], float(pd[1])) + 0.001, "pool %s is no bumpier than before" % str(pd[0]))
	for i in 2:
		assert_true(_spread(t1, Data.POOL_DISCS[i][0], float(Data.POOL_DISCS[i][1])) < 0.06, "pool %d lies level" % i)
	for site in [[Data.SHED["pos"], 1.9], [Data.MARKER, 1.0], [Data.BENCH["pos"], 1.1], [Data.CANDLE_TREE, 1.4]]:
		assert_true(_spread(t1, site[0], float(site[1])) < 0.08, "a level pad at %s (%.3f m)" % [str(site[0]), _spread(t1, site[0], float(site[1]))])
	# The region's own orchard arch plaza keeps its level (it is protected after the districts run).
	assert_almost(float(t1.height_at(Data.ORCHARD_ARCH.x, Data.ORCHARD_ARCH.y)), float(t0.height_at(Data.ORCHARD_ARCH.x, Data.ORCHARD_ARCH.y)), 0.001, "the arch plaza is untouched")


func test_our_content_on_the_region_terrain_is_grounded_and_connected() -> void:
	if not _region_ready():
		return
	fresh_state()
	var t: RefCounted = _terrain(true)
	var h: Node3D = TerrainHost.new()
	h.terrain = t
	h.area_id = Data.AREA_ID
	t.build_collision(h)
	add_child(h)
	_hosts.append(h)
	await wait_physics(1)
	var t_build := Time.get_ticks_msec()
	var d := await build_all(h)
	print("  reach_west on the region terrain: built in %d ms (incl. 2 physics frames)" % (Time.get_ticks_msec() - t_build))
	# Rays ignore our own solids (a sap stump's collider sits over its node), so they measure the terrain itself.
	var ours: Array = []
	for key0 in ["orchard", "pools", "candleyard"]:
		for b in (d[key0] as Node).find_children("*", "CollisionObject3D", true, false):
			ours.append((b as CollisionObject3D).get_rid())
	for key in ["orchard", "pools", "candleyard"]:
		var root: Node3D = d[key]
		for id in root.nodes:
			var n: Node3D = root.nodes[id]
			var g: Variant = ground_hit(h, Vector2(n.global_position.x, n.global_position.z), ours)
			assert_not_null(g, "%s has terrain under it" % id)
			if g != null:
				assert_almost(n.global_position.y, (g as Vector3).y, 0.08, "%s stands on the terrain collider" % id)
	var starts := {"orchard": Data.ORCHARD_ENTRY, "pools": Data.POOLS_ENTRIES[0], "candleyard": Data.CANDLEYARD_ENTRIES[0]}
	var lm := {"orchard": Data.ORCHARD, "pools": Data.POOLS, "candleyard": Data.CANDLEYARD}
	for key2 in starts:
		var c := Data.center_of(lm[key2])
		var r := Data.radius_of(lm[key2]) + 3.0
		var grid := walkable_cells(h, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), starts[key2])
		for it in interactables_under(d[key2]):
			var gp: Vector3 = (it as Node3D).global_position
			assert_true(reachable(grid, Vector2(gp.x, gp.z), 2.1), "%s: %s reachable on the real terrain" % [key2, it.name])
		var droot: Node3D = d[key2]
		for id2 in droot.nodes:
			var np: Vector3 = (droot.nodes[id2] as Node3D).global_position
			assert_true(reachable(grid, Vector2(np.x, np.z), 1.9), "%s: harvest node %s reachable on the real terrain" % [key2, id2])


func test_the_real_reach_builds_our_districts() -> void:
	if not _region_ready():
		return
	fresh_state()
	var ps: Variant = load("res://scenes/hallowmere_reach.tscn")
	if not (ps is PackedScene):
		print("  SKIP reach_west_region: no Reach scene")
		return
	var a: Node3D = (ps as PackedScene).instantiate()
	if a.get("districts_built") == null:
		print("  SKIP reach_west_region: the Reach scene is still the wave A placeholder")
		a.free()
		return
	var t0 := Time.get_ticks_msec()
	add_child(a)
	_hosts.append(a)
	var ms := Time.get_ticks_msec() - t0
	await wait_physics(2)
	var built: Array = a.get("districts_built")
	for id in MINE:
		assert_true(built.has(id), "the region built district %s" % id)
	var ours := 0
	for n in ["District_Orchard", "District_Pools", "District_Candleyard"]:
		var root: Node3D = a.get_node_or_null(n)
		assert_not_null(root, "%s under the Reach root" % n)
		if root != null:
			ours += int(root.get("build_ms"))
			assert_true(int(root.get("build_ms")) < 250, "%s builds in %d ms inside the real region" % [n, int(root.get("build_ms"))])
	print("  reach_west inside the real Reach: our districts %d ms of a %d ms area build" % [ours, ms])
	var ids: Array = a.resource_ids() if a.has_method("resource_ids") else []
	for e in Data.NODES:
		if not ids.is_empty():
			assert_true(ids.has(String(e["id"])), "%s registered with the region" % e["id"])
	for e2 in Data.NODES:
		assert_true(ids.is_empty() or ids.count(String(e2["id"])) == 1, "%s unique across the region's resource ids" % e2["id"])
	# Zones: our content never changes the landmark zones.
	for id2 in [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]:
		var c := Data.center_of(id2)
		assert_eq(a.get_zone_at(Vector3(c.x, 0, c.y)), id2, "zone at %s" % id2)
		assert_false(a.is_safe_zone(Vector3(c.x, 0, c.y)), "%s is not a safe zone" % id2)
	# The mimic pocket and the spawners are never inside a safe spot of the region.
	for sid in Data.SPAWNERS:
		var sp: Vector2 = Data.SPAWNERS[sid]["pos"]
		assert_false(a.is_safe_zone(Vector3(sp.x, 0, sp.y)), "%s not in a safe zone (it would never spawn)" % sid)


## Flood fill on the REAL Reach: a cell is walkable when a player capsule fits on the ground there and the ground
## never steps more than max_step to its neighbour (the region's own road probe uses 0.45 m). `radius` = capsule.
func _walk_cells(h: Node3D, bounds: Rect2, start: Vector2, radius: float, tall: float, cell: float = 0.8, max_step: float = 0.45) -> Dictionary:
	var free := {}
	var seen := {}
	var origin := bounds.position
	var nx := int(ceil(bounds.size.x / cell))
	var nz := int(ceil(bounds.size.y / cell))
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = tall
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = MASK
	var space := h.get_world_3d().direct_space_state
	var s := Vector2i(int((start.x - origin.x) / cell), int((start.y - origin.y) / cell))
	var queue: Array = [s]
	seen[s] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var p := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell
		var y := height(h, p)
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, y + 0.2 + tall * 0.5, p.y))
		if not space.intersect_shape(sq, 1).is_empty():
			continue
		free[c] = true
		for dxy in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dxy
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or seen.has(n):
				continue
			var q := origin + (Vector2(n) + Vector2(0.5, 0.5)) * cell
			if absf(height(h, q) - y) > max_step:
				continue          # a step / cliff: not walkable this way (may still be reached from another side)
			seen[n] = true
			queue.append(n)
	return {"free": free, "origin": origin, "cell": cell}


## The region's own route probe skips district interiors ("the district modules test their own ground"), so this
## checks our content inside the REAL Reach: terrain + the region's vegetation, set pieces, road lights and story
## dressing + all districts. From each entry every interactable and harvest node is reachable on foot, and the
## required orchard content (levers, seed box, lamp, the mimic pocket) lies on a 1.6 m wide, 2.4 m tall route.
func test_the_real_reach_keeps_our_content_reachable() -> void:
	if not _region_ready():
		return
	fresh_state()
	var ps: Variant = load("res://scenes/hallowmere_reach.tscn")
	if not (ps is PackedScene):
		print("  SKIP reach_west_region: no Reach scene")
		return
	var a: Node3D = (ps as PackedScene).instantiate()
	if a.get("districts_built") == null:
		print("  SKIP reach_west_region: the Reach scene is still the wave A placeholder")
		a.free()
		return
	add_child(a)
	_hosts.append(a)
	await wait_physics(2)
	var arrive: Vector3 = (a.get_spawn("orchard_arch") as Transform3D).origin
	assert_true(Vector2(arrive.x, arrive.z).distance_to(Data.ORCHARD_ENTRY) < 1.0, "the region's orchard_arch spawn is our orchard entry")
	var starts := {"orchard": Vector2(arrive.x, arrive.z), "pools": Data.POOLS_ENTRIES[0], "candleyard": Data.CANDLEYARD_ENTRIES[0]}
	var lm := {"orchard": Data.ORCHARD, "pools": Data.POOLS, "candleyard": Data.CANDLEYARD}
	var roots := {"orchard": a.get_node_or_null("District_Orchard"), "pools": a.get_node_or_null("District_Pools"),
		"candleyard": a.get_node_or_null("District_Candleyard")}
	for key in starts:
		var root: Node3D = roots[key]
		assert_not_null(root, "%s built inside the real Reach" % key)
		if root == null:
			continue
		var c := Data.center_of(lm[key])
		var r := Data.radius_of(lm[key]) + 4.0
		var bounds := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		var grid := _walk_cells(a, bounds, starts[key], CAPSULE_RADIUS, CAPSULE_HEIGHT)
		assert_true((grid["free"] as Dictionary).size() > 800, "%s: a real walkable area in the Reach (%d cells)" % [key, (grid["free"] as Dictionary).size()])
		for it in interactables_under(root):
			var gp: Vector3 = (it as Node3D).global_position
			assert_true(reachable(grid, Vector2(gp.x, gp.z), 2.1), "%s: %s reachable on foot in the real Reach" % [key, it.name])
		for id in root.nodes:
			var np: Vector3 = (root.nodes[id] as Node3D).global_position
			assert_true(reachable(grid, Vector2(np.x, np.z), 1.9), "%s: harvest node %s reachable in the real Reach" % [key, id])
		if key == "orchard":
			var wide := _walk_cells(a, bounds, starts[key], 0.8, 2.4)
			for k2 in ["lever_junction", "lever_gate", "festival_seed", "garden_lamp"]:
				var it2: Node3D = root.interactables[k2]
				assert_true(reachable(wide, Vector2(it2.global_position.x, it2.global_position.z), 2.4), "%s on a wide route in the real Reach" % k2)
			for dm in root.mimic_pocket.dormant:
				var rp: Vector3 = (dm["root"] as Node3D).global_position
				assert_true(reachable(wide, Vector2(rp.x, rp.z), 2.6), "the dormant mimics on a wide route in the real Reach")
		if key == "candleyard":
			assert_true(reachable(grid, Data.HAT["stand"], 0.8), "the hat stand is reachable in the real Reach (no jumping)")
		if key == "pools":
			for ch in Data.CHIMES:
				assert_true(reachable(grid, ch, Data.CHIME_REACH - 0.3), "chime %s can be walked up to in the real Reach" % str(ch))
			assert_true(reachable(grid, Data.POUCH, 1.8), "the pouch can be reached in the real Reach")


func test_pools_water_is_marked_shallow_in_the_region_terrain() -> void:
	if not _region_ready():
		return
	fresh_state()
	var t: RefCounted = _terrain(true)
	if not t.has_method("is_water"):
		return
	for pd in Data.POOL_DISCS:
		var c: Vector2 = pd[0]
		assert_true(bool(t.is_water(c.x, c.y)), "pool %s is water for footsteps / grass" % str(c))
		var depth := float(t.water_level_at(c.x, c.y)) - float(t.height_at(c.x, c.y))
		assert_true(depth > 0.0 and depth < 0.2, "ankle-deep (%.2f m): no swimming, saved positions stay valid" % depth)
	var mid: Vector2 = Data.BROOK[3]
	assert_true(bool(t.is_water(mid.x, mid.y)), "the little brook is water")
	for c2 in Data.CHIMES + [Data.POUCH]:
		assert_false(bool(t.is_water((c2 as Vector2).x, (c2 as Vector2).y)), "%s stays dry" % str(c2))


## No cliffs: inside our circles the steepest 1 m step after shaping is never worse than before (+5 cm), and
## never above 0.45 m where the ground was gentle - so the region's roads still meet our gates.
func test_shaping_never_makes_steps() -> void:
	if not _region_ready():
		return
	fresh_state()
	var t0: RefCounted = _terrain(false)
	var t1: RefCounted = _terrain(true)
	for id in [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]:
		var c := Data.center_of(id)
		var r := int(Data.radius_of(id)) + 1
		var worst := 0.0
		var where := Vector2.ZERO
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2(dx, dz)
				if p.distance_to(c) > float(r):
					continue
				for n in [Vector2(1, 0), Vector2(0, 1)]:
					var q: Vector2 = p + n
					var s0 := absf(float(t0.height_at(q.x, q.y)) - float(t0.height_at(p.x, p.y)))
					var s1 := absf(float(t1.height_at(q.x, q.y)) - float(t1.height_at(p.x, p.y)))
					var excess := s1 - maxf(s0 + 0.05, 0.45)
					if excess > worst:
						worst = excess
						where = p
		assert_true(worst <= 0.0, "%s: shaping made a %.2f m step near %s" % [id, worst + 0.45, str(where)])
	# The region roads' ends at our entries keep their height.
	for e in Data.CANDLEYARD_ENTRIES + Data.POOLS_ENTRIES + [Vector2(-76.0, 8.0), Vector2(-58.0, 16.0)]:
		var ev: Vector2 = e
		assert_almost(float(t1.height_at(ev.x, ev.y)), float(t0.height_at(ev.x, ev.y)), 0.1, "road end %s untouched" % str(ev))
