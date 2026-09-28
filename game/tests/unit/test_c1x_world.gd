extends "res://tests/test_case.gd"
## Module B7 in the REAL surface world (built once, headless): every Chapter One optional addition is built by
## src/world/surface/annexes.gd, stands on the ground where data/c1x_layout.gd says, keeps its colliders off every
## legacy collider and every legacy spawn, and NOTHING legacy changes: the vegetation plan (golden hash), the
## instantiated resource nodes, terrain heights, spawns and landmark zones are exactly as before.

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")
const Layout := preload("res://data/world_layout.gd")
const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")
const Terrain := preload("res://src/world/surface/terrain.gd")
const Vegetation := preload("res://src/world/surface/vegetation.gd")
const Annexes := preload("res://src/world/surface/annexes.gd")
const AreaBase := preload("res://src/world/area_base.gd")

## Recorded from the legacy build (same values as tests/unit/test_flow_ch2_areas.gd, wave A3).
const GOLDEN_COUNTS := {"trees": 218, "rocks": 26, "ores": 7, "bushes": 20, "tufts": 40, "sticks": 46, "stones": 46}
const GOLDEN_DIGEST := "bd86320366013834cd23feefa16c4703"
const C1X_SCRIPTS := ["tailor_cache", "bramblewatch", "meadow_patch", "sap_stumps", "moth_pocket", "seasonal_decor"]

var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = SurfaceWorld.new()
		add_child(_w)
		await wait_physics(3)
	return _w


func _c1x_root() -> Node3D:
	return _w.get_node_or_null(Common.ROOT_NAME) as Node3D


## Every c1x StaticBody3D (our own colliders, to exclude from legacy overlap queries).
func _own_bodies() -> Array[RID]:
	var out: Array[RID] = []
	var root := _c1x_root()
	if root == null:
		return out
	for n in root.find_children("*", "StaticBody3D", true, false):
		out.append((n as StaticBody3D).get_rid())
	return out


func test_every_annex_script_exists_with_static_build() -> void:
	for n in C1X_SCRIPTS:
		var path := "res://src/world/surface/c1x/%s.gd" % n
		assert_true(Annexes.ANNEX_SCRIPTS.has(path), "annexes.gd loads %s" % path)
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		var s: Script = load(path)
		assert_true(s != null and s.can_instantiate(), "%s compiles" % path)
		if s != null:
			assert_true(s.has_method("build"), "%s has static build(area)" % path)


func test_annexes_are_built_on_the_ground_where_the_layout_says() -> void:
	var w: Node3D = await _world()
	var root := _c1x_root()
	assert_not_null(root, "the c1x container exists")
	if root == null:
		return
	for sub in ["TailorCache", "SapStumps", "MeadowPatch", "Bramblewatch", "MothPocket", "SeasonalDecor"]:
		assert_not_null(root.get_node_or_null(sub), "annex %s built" % sub)
	# Persistent harvestables: right id, kind data, position and ground contact.
	var expected: Array = []
	for f in L.footprints():
		if bool(f.get("persistent", false)):
			expected.append(f)
	assert_eq(expected.size(), L.SAP_STUMPS.size() + L.SUNFLAX.size() + L.ROSEBERRY.size(), "every renewable node")
	var found := {}
	for n in get_tree().get_nodes_in_group("resource_node"):
		if String(n.get("node_id")).begins_with(L.PREFIX):
			found[String(n.get("node_id"))] = n
	for f in expected:
		var id := String(f["id"])
		assert_true(found.has(id), "resource node %s exists" % id)
		if not found.has(id):
			continue
		var n: Node3D = found[id]
		var p: Vector2 = f["pos"]
		assert_almost(Vector2(n.global_position.x, n.global_position.z).distance_to(p), 0.0, 0.01, "%s at its layout point" % id)
		assert_almost(n.global_position.y, float(w.height_at(p.x, p.y)), 0.12, "%s sits on the ground" % id)
		assert_true(n.is_in_group("harvestable"), "%s is harvestable" % id)
		assert_eq(String(n.get("event_kind")), String(f["kind"]), "%s reports its data kind" % id)
		var info: Dictionary = n.get_harvest_info()
		assert_eq(String(info.get("tool", "")), String(ItemDB.node_kind(String(f["kind"]))["tool"]), "%s tool from data" % id)
	var cache := get_tree().get_first_node_in_group("c1x_tailor_cache") as Node3D
	assert_not_null(cache, "the Tailor's Cache exists")
	if cache != null:
		var cp: Vector2 = L.TAILOR_CACHE["pos"]
		assert_almost(Vector2(cache.global_position.x, cache.global_position.z).distance_to(cp), 0.0, 0.01, "cache at its point")
		assert_true(cache.is_in_group("interactable"), "the cache is interactable")
	var trail := root.get_node("TailorCache")
	for r in L.TAILOR_RIBBONS:
		assert_not_null(trail.get_node_or_null(String(r["id"])), "ribbon %s on its branch" % r["id"])
	var arena := get_tree().get_first_node_in_group("c1x_elder_arena") as Node3D
	assert_not_null(arena, "the Elder's arena exists")
	if arena != null:
		assert_eq((arena.get("walls") as Array).size(), L.ROOT_SLOTS.size(), "one root wall per slot")
		assert_eq(int(arena.raised_count()), 0, "no roots stand without a fight")
		for i in (arena.get("walls") as Array).size():
			var wall: Node3D = arena.walls[i]
			var ends: Array = wall.world_ends()
			var want: Array = L.root_slot_ends(i)
			for k in 2:
				var e3: Vector3 = ends[k]
				var e2: Vector2 = want[k]
				assert_almost(Vector2(e3.x, e3.z).distance_to(e2), 0.0, 0.05, "root slot %d end %d follows the arena tangent" % [i, k])
	assert_not_null(get_tree().get_first_node_in_group("c1x_moth_pocket"), "the moth pocket exists")
	assert_not_null(get_tree().get_first_node_in_group("c1x_seasonal_decor"), "the seasonal decor node exists")
	assert_not_null(root.find_child(String(L.STICKY_TREE["id"]), true, false), "the sticky old tree stands")


func test_spawners_only_for_available_enemies() -> void:
	await _world()
	var root := _c1x_root()
	for s in L.spawners():
		var node := root.find_child("Spawner_" + String(s["id"]), true, false) if root != null else null
		if Common.enemy_available(String(s["enemy"])):
			assert_not_null(node, "%s is placed (%s available)" % [s["id"], s["enemy"]])
			if node != null:
				assert_eq(String(node.get("spawner_id")), String(s["id"]), "spawner id %s" % s["id"])
				assert_eq(String(node.get("enemy_id")), String(s["enemy"]), "spawner %s enemy" % s["id"])
				var p: Vector2 = s["pos"]
				assert_almost(Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z).distance_to(p), 0.0, 0.01, "%s position" % s["id"])
		else:
			assert_null(node, "%s is skipped while %s is not available (no crash)" % [s["id"], s["enemy"]])
	# A missing enemy id never crashes and never builds a spawner.
	var holder := Node3D.new()
	add_child(holder)
	assert_null(Common.make_spawner(holder, null, {"id": "c1x_sp_test", "enemy": "no_such_enemy_c1x"}), "unknown enemy -> no spawner")
	assert_false(Common.enemy_available("no_such_enemy_c1x"), "unknown enemy is unavailable")
	holder.queue_free()


## Golden guard: building the annexes never changes the legacy vegetation plan or its instantiated nodes.
func test_legacy_vegetation_plan_unchanged_with_annexes_built() -> void:
	var w: Node3D = await _world()
	assert_not_null(_c1x_root(), "the annexes were built in this world")
	var plan: Dictionary = w.vegetation.plan_data
	var counts := {}
	var parts: PackedStringArray = []
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		counts[k] = (plan[k] as Array).size()
		for e in plan[k]:
			var p: Vector3 = e["pos"]
			parts.append("%s:%.1f,%.1f" % [e["id"], p.x, p.z])
	assert_eq(counts, GOLDEN_COUNTS, "legacy resource node counts")
	assert_eq("|".join(parts).md5_text(), GOLDEN_DIGEST, "legacy resource node ids and positions")
	# The instantiated legacy nodes are all there, unmoved, and no c1x id leaked into the legacy map.
	var total := 0
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		for e in plan[k]:
			var id := String(e["id"])
			var n: Variant = w.vegetation.resource_nodes.get(id)
			assert_true(n is Node3D and is_instance_valid(n), "legacy node %s still exists" % id)
			if n is Node3D:
				var p: Vector3 = e["pos"]
				assert_true(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z).distance_to(Vector2(p.x, p.z)) < 0.01, "legacy node %s unmoved" % id)
			total += 1
	assert_eq(w.vegetation.resource_nodes.size(), total, "the legacy node map holds only legacy ids")
	# Terrain heights are untouched (no heightfield edits): identical to a fresh generation.
	var fresh: RefCounted = Terrain.new()
	fresh.generate()
	assert_eq(w.terrain.h, fresh.h, "terrain heights identical to a fresh legacy generation")
	# A fresh plan from the fresh terrain is still the golden one.
	var p2: Dictionary = Vegetation.plan(fresh)
	var parts2: PackedStringArray = []
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		for e in p2[k]:
			var p: Vector3 = e["pos"]
			parts2.append("%s:%.1f,%.1f" % [e["id"], p.x, p.z])
	assert_eq("|".join(parts2).md5_text(), GOLDEN_DIGEST, "a fresh plan is still the golden legacy plan")


func test_legacy_spawns_and_zones_unchanged() -> void:
	var w: Node3D = await _world()
	for id in Layout.SPAWN_HINTS:
		var h: Vector2 = Layout.SPAWN_HINTS[id]
		var o: Vector3 = (w.spawns[id] as Transform3D).origin
		assert_almost(Vector2(o.x, o.z).distance_to(h), 0.0, 0.001, "legacy spawn %s unmoved" % id)
	for id in Layout.LANDMARKS:
		var p: Vector2 = Layout.LANDMARKS[id]["pos"]
		assert_eq(w.get_zone_at(Vector3(p.x, 0, p.y)), String(id), "zone at landmark %s unchanged" % id)
	assert_false(w.is_safe_zone(Vector3(-12, 2, -66)), "the ruin stays unsafe")
	assert_true(w.is_safe_zone(Vector3(3, 0, 3)), "the Haven stays safe")
	# The new zone: a pocket zone, never safe, at both circles.
	for z in L.BRAMBLEWATCH_ZONES:
		var c: Vector2 = z[0]
		assert_eq(w.get_zone_at(Vector3(c.x, 0, c.y)), L.BRAMBLEWATCH_ZONE, "Bramblewatch zone at %s" % c)
		assert_false(w.is_safe_zone(Vector3(c.x, 0, c.y)), "Bramblewatch is not safe")
	for s in L.spawners():
		var p: Vector2 = s["pos"]
		assert_false(w.is_safe_zone(Vector3(p.x, 0, p.y)), "spawner %s is not in a safe zone (it can spawn)" % s["id"])


## Our colliders never overlap a legacy collider, and every legacy spawn capsule stays clear.
func test_c1x_colliders_keep_off_legacy_colliders_and_spawns() -> void:
	var w: Node3D = await _world()
	var space := w.get_world_3d().direct_space_state
	var own := _own_bodies()
	assert_true(own.size() >= 10, "c1x colliders found (%d)" % own.size())
	var root := _c1x_root()
	var checked := 0
	for n in root.find_children("*", "StaticBody3D", true, false):
		var body := n as StaticBody3D
		if body.collision_layer == 0:
			continue          # inactive root walls
		for cs in body.get_children():
			if not (cs is CollisionShape3D) or (cs as CollisionShape3D).shape == null:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = (cs as CollisionShape3D).shape
			q.transform = (cs as CollisionShape3D).global_transform
			q.collision_mask = 1 | 32
			q.exclude = own
			for h in space.intersect_shape(q, 8):
				var col: Object = h.get("collider")
				var cname := String((col as Node).name) if col is Node else "?"
				assert_true(cname.begins_with("TerrainBody"), "%s/%s overlaps legacy collider %s" % [body.get_parent().name, body.name, cname])
			checked += 1
	assert_true(checked >= 10, "c1x collision shapes checked (%d)" % checked)
	for id in w.spawns:
		var p: Vector3 = (w.spawns[id] as Transform3D).origin
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.6
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = cap
		sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0))
		sq.collision_mask = 1 | 32
		var own_hits := 0
		for h in space.intersect_shape(sq, 8):
			if own.has((h.get("collider") as CollisionObject3D).get_rid()):
				own_hits += 1
		assert_eq(own_hits, 0, "no c1x collider on spawn %s" % id)


## Krystal can walk up to every piece: most of a ring around it is free, dry, walkable ground.
func test_every_site_can_be_reached_on_foot() -> void:
	var w: Node3D = await _world()
	var space := w.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	for f in L.footprints():
		var c: Vector2 = f["pos"]
		var ok := 0
		for a in 8:
			var q := c + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * (float(f["radius"]) + 0.9)
			if w.terrain.is_water(q.x, q.y):
				continue
			var g: Variant = w.validate_position(Vector3(q.x, float(w.height_at(q.x, q.y)) + 0.5, q.y))
			if not (g is Vector3):
				continue
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = cap
			sq.transform = Transform3D(Basis.IDENTITY, (g as Vector3) + Vector3(0, 0.95, 0))
			sq.collision_mask = 1 | 32
			if space.intersect_shape(sq, 1).is_empty():
				ok += 1
		assert_true(ok >= 5, "%s has free standing ground around it (%d/8)" % [f["id"], ok])


func test_grass_is_cleared_under_the_small_footprints() -> void:
	var w: Node3D = await _world()
	var fresh: RefCounted = Terrain.new()
	fresh.generate()
	var before: PackedByteArray = fresh.grass
	var after: PackedByteArray = w.terrain.grass
	var pts: Array = [L.TAILOR_CACHE["pos"], L.STICKY_TREE["pos"]]
	for s in L.SAP_STUMPS:
		pts.append(s["pos"])
	for p in pts:
		var pv: Vector2 = p
		var i := int(roundf(pv.x + Terrain.HALF))
		var j := int(roundf(pv.y + Terrain.HALF))
		var k := (j * Terrain.N + i) * 4
		assert_true(int(after[k]) <= int(before[k]) / 2 + 1, "grass thinned under %s (%d -> %d)" % [pv, before[k], after[k]])


func test_bramblewatch_zone_entry_sets_the_found_flag() -> void:
	await _world()
	GameState.flags.erase(L.FLAG_BRAMBLEWATCH_FOUND)
	Events.zone_entered.emit("glade")
	assert_false(bool(GameState.get_flag(L.FLAG_BRAMBLEWATCH_FOUND)), "another zone does nothing")
	Events.zone_entered.emit(L.BRAMBLEWATCH_ZONE)
	assert_true(bool(GameState.get_flag(L.FLAG_BRAMBLEWATCH_FOUND)), "reaching Bramblewatch sets c1x_bramblewatch_found")


## The c1x annexes add little to the surface build (a fraction of the 1 s target).
func test_annex_build_is_cheap() -> void:
	var w: Node3D = await _world()
	assert_true(float(w.build_times.get("total", 99999.0)) < 4000.0, "surface still builds in time")
	var area: Node3D = AreaBase.new()
	area.area_id = "surface"
	add_child(area)
	var t0 := Time.get_ticks_usec()
	for n in C1X_SCRIPTS:
		var s: Script = load("res://src/world/surface/c1x/%s.gd" % n)
		s.call("build", area)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("    c1x annexes build in %.1f ms (flat test area)" % ms)
	assert_true(ms < 250.0, "c1x annexes build quickly (%.1f ms)" % ms)
	var nodes := area.find_children("*", "Node", true, false).size()
	print("    c1x node count: %d" % nodes)
	assert_true(nodes < 400, "bounded node count (%d)" % nodes)
	area.queue_free()
	await wait_frames(2)


func test_zz_cleanup() -> void:
	if _w != null and is_instance_valid(_w):
		_w.queue_free()
		_w = null
	await wait_frames(8)
