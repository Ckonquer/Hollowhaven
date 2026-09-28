extends "res://tests/test_case.gd"
## Lanternwake Expeditions (module D2): the three hand-authored templates are valid data (stops, groups of
## existing non-spider enemy ids within their max_group, rewards of renewable non-story items, dye / decor
## keepsakes that exist, reward types shown), and every authored place is real ground in the built Reach:
## on walkable, dry, clear ground inside the walls, outside every safe zone, clear of the Lantern Road
## arches, the arrival and the districts' own spawner pockets, with a walkable line from each stop's lantern
## to its spawn points and from the last stop to the cache. The Reach is built once for the suite.

const Data := preload("res://data/expeditions.gd")
const Ex := preload("res://src/expeditions/expeditions.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const ReachWorld := preload("res://src/world/areas_ch2/hallowmere_reach_world.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const West := preload("res://data/reach_west.gd")
const East := preload("res://data/reach_east.gd")
const Manor := preload("res://data/manor_layout.gd")

const MAX_SLOPE_DEG := 38.0
const MAX_STEP := 0.75

static var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = ReachWorld.new()
		add_child(_w)
		await wait_physics(3)
	return _w


func _space(w: Node3D) -> PhysicsDirectSpaceState3D:
	return w.get_world_3d().direct_space_state


## Ground under `p` from just above the terrain (tree canopies overhead are not ground; anything standing on
## the terrain lower than 3 m is, and the capsule checks then say whether she could stand there).
func _ground(w: Node3D, p: Vector2) -> Dictionary:
	var h := float(w.height_at(p.x, p.y))
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 3.0, p.y), Vector3(p.x, h - 6.0, p.y))
	q.collision_mask = 1 | 32
	return _space(w).intersect_ray(q)


func _clear(w: Node3D, feet: Vector3, radius: float, height: float) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, height * 0.5 + 0.15, 0))
	sq.collision_mask = 1 | 32
	return _space(w).intersect_shape(sq, 4).map(func(o: Dictionary) -> String: return String((o["collider"] as Node).name))


## Problems with standing at `p` ([] = fine).
func _spot_problems(w: Node3D, p: Vector2, radius: float) -> Array:
	var out: Array = []
	var hit := _ground(w, p)
	if hit.is_empty():
		return ["no ground"]
	var gp: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	if n.y < cos(deg_to_rad(MAX_SLOPE_DEG)):
		out.append("too steep (%.0f deg)" % rad_to_deg(acos(clampf(n.y, -1.0, 1.0))))
	if absf(gp.y - float(w.height_at(p.x, p.y))) > 0.5:
		out.append("stands on a prop (%.2f m above the terrain)" % (gp.y - float(w.height_at(p.x, p.y))))
	var blocked := _clear(w, gp, radius, 1.6)
	if not blocked.is_empty():
		out.append("blocked by %s" % str(blocked))
	if w.terrain.is_water(p.x, p.y):
		out.append("in water")
	if not w.is_inside_bounds(gp, 4.0):
		out.append("outside the walls")
	if not (w.validate_position(gp) is Vector3):
		out.append("not a valid position")
	if w.is_safe_zone(gp):
		out.append("inside a safe zone")
	return out


var _cells: Dictionary = {}   # Vector2i (1 m grid) -> ground height (NAN = not standable)


## Ground height of the 1 m cell `c` if Krystal could stand there (NAN otherwise). Cached for the suite.
func _cell(w: Node3D, c: Vector2i) -> float:
	if _cells.has(c):
		return _cells[c]
	var p := Vector2(c.x, c.y)
	var y := NAN
	var hit := _ground(w, p)
	if not hit.is_empty() and (hit["normal"] as Vector3).y >= cos(deg_to_rad(45.0)):
		var gp: Vector3 = hit["position"]
		var deep: bool = w.terrain.is_water(p.x, p.y) and float(w.terrain.water_level_at(p.x, p.y)) - gp.y > 0.6
		if not deep and _clear(w, gp, 0.3, 1.4).is_empty():
			y = gp.y
	_cells[c] = y
	return y


## Problems walking from a to b ([] = fine): a breadth-first search over standable 1 m cells (steps under
## MAX_STEP) inside a box around both ends proves there is a way round trees and props.
func _walk_problems(w: Node3D, a: Vector2, b: Vector2, margin: int = 10) -> Array:
	var start := Vector2i(roundi(a.x), roundi(a.y))
	var goal := Vector2i(roundi(b.x), roundi(b.y))
	var lo := Vector2i(mini(start.x, goal.x) - margin, mini(start.y, goal.y) - margin)
	var hi := Vector2i(maxi(start.x, goal.x) + margin, maxi(start.y, goal.y) + margin)
	# The exact end points may sit a little off the grid: start / finish at the nearest standable cell.
	for c in [start, goal]:
		if is_nan(_cell(w, c)):
			return ["no standable ground at %s" % str(c)]
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == goal:
			return []
		var cy := _cell(w, cur)
		for d in dirs:
			var nx: Vector2i = cur + d
			if seen.has(nx) or nx.x < lo.x or nx.y < lo.y or nx.x > hi.x or nx.y > hi.y:
				continue
			seen[nx] = true
			var ny := _cell(w, nx)
			if is_nan(ny) or absf(ny - cy) > MAX_STEP:
				continue
			queue.append(nx)
	return ["no walkable way from %s to %s (%d cells searched)" % [str(a), str(b), seen.size()]]


func _district_spawners() -> Array:
	var out: Array = []
	for id in West.SPAWNERS:
		out.append(West.SPAWNERS[id]["pos"])
	for id in East.SPAWNERS:
		var uv: Vector2 = East.SPAWNERS[id]["at"]
		out.append(East.CENTER + East.AXIS_U * uv.x + East.AXIS_V * uv.y)
	out.append(Manor.GROUNDS["wing_pocket"])
	return out


func _arches() -> Array:
	var out: Array = [Reach.POINTS["waygate_arrival"]]
	for id in Reach.ARCHES:
		out.append(Reach.ARCHES[id]["pos"])
	return out


# --- Data ---------------------------------------------------------------------------------------------------------

func test_three_named_hand_authored_templates() -> void:
	assert_eq(Data.ORDER, ["orchard_patrol", "quarry_circuit", "manor_afterglow"])
	assert_eq(String(Data.TEMPLATES["orchard_patrol"]["name"]), "Orchard Patrol")
	assert_eq(String(Data.TEMPLATES["quarry_circuit"]["name"]), "Quarry Circuit")
	assert_eq(String(Data.TEMPLATES["manor_afterglow"]["name"]), "Manor Afterglow")
	assert_eq(Data.TEMPLATES.size(), 3, "exactly the three templates (no procedural routes)")
	var stop_ids := {}
	for id in Data.ORDER:
		var t: Dictionary = Data.TEMPLATES[id]
		var stops: Array = t["stops"]
		assert_true(stops.size() >= Data.MIN_STOPS and stops.size() <= Data.MAX_STOPS, "%s has 2-4 stops" % id)
		assert_true(Data.DIFFICULTIES.has(String(t["difficulty"])), "%s difficulty label" % id)
		assert_true(Reach.ARCHES.has(String(t["arch"])), "%s arch" % id)
		assert_true(ItemDB.unlock_flags().has(String(t["requires"])), "%s requires a known flag" % id)
		assert_true(String(t["blurb"]) != "" and String(t["minutes"]) != "" and String(t["requires_text"]) != "")
		assert_true((t["reward_types"] as Array).size() >= 2, "%s shows its reward types" % id)
		var c: Dictionary = t["cache"]
		assert_true(String(c["id"]).begins_with("exp_") and String(c["name"]) != "" and c["pos"] is Vector2, "%s cache" % id)
		for s in stops:
			var sd: Dictionary = s
			assert_true(String(sd["id"]).begins_with("exp_"), "stop id namespace")
			assert_false(stop_ids.has(sd["id"]), "stop id %s unique" % sd["id"])
			stop_ids[sd["id"]] = true
			assert_true(String(sd["name"]) != "")
			assert_true((sd["groups"] as Array).size() >= 2, "%s offers seeded variety" % sd["id"])
			var biggest := 0
			for g in sd["groups"]:
				var n := 0
				for pair in g:
					n += int(pair[1])
				assert_true(n >= 1 and n <= 4, "%s group size 1-4" % sd["id"])
				biggest = maxi(biggest, n)
			assert_true((sd["points"] as Array).size() >= biggest + 1, "%s has a spare point for its biggest group" % sd["id"])
			var pts: Array = sd["points"]
			for i in pts.size():
				var p: Vector2 = pts[i]
				assert_true(p.distance_to(sd["pos"]) <= Data.POINT_SPREAD, "%s point %s near its lantern" % [sd["id"], str(p)])
				assert_true(p.distance_to(sd["pos"]) >= 3.0, "%s point %s leaves room for the lantern" % [sd["id"], str(p)])
				for j in range(i + 1, pts.size()):
					assert_true(p.distance_to(pts[j]) >= 3.0, "%s points %s / %s spread out" % [sd["id"], str(p), str(pts[j])])
		for i in stops.size():
			for j in range(i + 1, stops.size()):
				assert_true((stops[i]["pos"] as Vector2).distance_to(stops[j]["pos"]) >= 20.0, "%s stops %d/%d apart" % [id, i, j])


func test_enemy_ids_exist_and_are_never_spider_like_or_bosses() -> void:
	for id in Data.ORDER:
		for s in Data.TEMPLATES[id]["stops"]:
			for g in s["groups"]:
				var counts := {}
				for pair in g:
					var eid := String(pair[0])
					counts[eid] = int(counts.get(eid, 0)) + int(pair[1])
					var e := ItemDB.enemy(eid)
					assert_false(e.is_empty(), "%s: enemy %s in data/enemies.gd" % [s["id"], eid])
					assert_true(Factory.has_enemy(eid) and Factory.can_spawn(eid), "%s: EnemyFactory can spawn %s" % [s["id"], eid])
					assert_false(bool(e.get("boss", false)) or bool(e.get("elite", false)), "%s: no bosses / elites (%s)" % [s["id"], eid])
					assert_eq(String(e.get("alt_name", "")), "", "%s: %s needs no arachnophobia swap" % [s["id"], eid])
					assert_false(bool(e.get("stalker", false)), "no stalkers")
				for eid in counts:
					var cap := int(ItemDB.enemy(String(eid)).get("max_group", 3))
					assert_true(int(counts[eid]) <= cap, "%s: %d x %s within max_group %d" % [s["id"], counts[eid], eid, cap])


func test_rewards_are_renewable_candy_and_keepsakes_never_story_items() -> void:
	for id in Data.ORDER:
		var rw: Dictionary = Data.TEMPLATES[id]["rewards"]
		assert_true((rw["base"] as Dictionary).has("candy"), "%s always gives candy" % id)
		var all_items: Dictionary = (rw["base"] as Dictionary).duplicate()
		all_items.merge(rw["picks"]["from"])
		assert_true(int(rw["picks"]["count"]) <= (rw["picks"]["from"] as Dictionary).size())
		for item in all_items:
			var r: Array = all_items[item]
			assert_true(ItemDB.has_item(String(item)), "%s: %s exists" % [id, item])
			assert_false(ItemDB.is_story_required(String(item)), "%s: %s is not a story item" % [id, item])
			assert_false(ItemDB.is_quest_item(String(item)), "%s: %s is not a key item" % [id, item])
			assert_true(ItemDB.category(String(item)) in ["resource", "food", "seed"], "%s: %s is a material/food/seed" % [id, item])
			assert_true(int(r[0]) >= 1 and int(r[1]) >= int(r[0]) and int(r[1]) <= 6, "%s: %s amount range" % [id, item])
		var chance := float(rw["keepsake_chance"])
		assert_true(chance > 0.0 and chance < 1.0, "keepsakes are occasional")
		var dyes := 0
		for k in rw["keepsakes"]:
			match String(k["kind"]):
				"dye":
					dyes += 1
					assert_false(ItemDB.dye_palette(String(k["id"])).is_empty(), "%s: dye %s exists" % [id, k["id"]])
					assert_eq(String(ItemDB.dye_palette(String(k["id"])).get("station", "")), "loom", "the dye is also mixed at the Loom")
				"decor":
					assert_eq(ItemDB.category(String(k["item"])), "placeable", "%s: decor %s is a placeable" % [id, k["item"]])
					assert_false(ItemDB.is_story_required(String(k["item"])))
					assert_true(ItemDB.sources(String(k["item"])).size() > 0, "%s: %s also has another source" % [id, k["item"]])
				_:
					fail("unknown keepsake kind %s" % k["kind"])
		assert_true(dyes >= 1, "%s offers a dye recipe" % id)


# --- The authored places in the built Reach ------------------------------------------------------------------------

func test_stop_lanterns_spawn_points_and_caches_stand_on_walkable_ground() -> void:
	var w: Node3D = await _world()
	for id in Data.ORDER:
		var t: Dictionary = Data.TEMPLATES[id]
		for s in t["stops"]:
			var pr := _spot_problems(w, s["pos"], 0.5)
			assert_true(pr.is_empty(), "%s lantern %s: %s" % [s["id"], str(s["pos"]), str(pr)])
			for p in s["points"]:
				var pp := _spot_problems(w, p, 0.55)
				assert_true(pp.is_empty(), "%s point %s: %s" % [s["id"], str(p), str(pp)])
		var cpr := _spot_problems(w, t["cache"]["pos"], 0.6)
		assert_true(cpr.is_empty(), "%s cache %s: %s" % [id, str(t["cache"]["pos"]), str(cpr)])


func test_spawn_points_keep_clear_of_arches_safe_ground_and_district_pockets() -> void:
	var w: Node3D = await _world()
	var arches := _arches()
	var pockets := _district_spawners()
	for id in Data.ORDER:
		for s in Data.TEMPLATES[id]["stops"]:
			var all: Array = (s["points"] as Array).duplicate()
			all.append(s["pos"])
			for p in all:
				for a in arches:
					assert_true((p as Vector2).distance_to(a) >= Data.ARCH_CLEARANCE, "%s %s is %.1f m from arch %s" % [s["id"], str(p), (p as Vector2).distance_to(a), str(a)])
				for k in pockets:
					assert_true((p as Vector2).distance_to(k) >= Data.SPAWNER_CLEARANCE, "%s %s is %.1f m from pocket %s" % [s["id"], str(p), (p as Vector2).distance_to(k), str(k)])
				# Not merely outside the safe circle: a group waking here can't reach one in a few steps.
				var hit := _ground(w, p)
				if not hit.is_empty():
					for dv in [Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 6), Vector3(0, 0, -6)]:
						assert_false(w.is_safe_zone((hit["position"] as Vector3) + dv), "%s %s is 6 m from safe ground" % [s["id"], str(p)])


func test_every_spawn_point_and_the_cache_can_be_walked_to() -> void:
	var w: Node3D = await _world()
	for id in Data.ORDER:
		var t: Dictionary = Data.TEMPLATES[id]
		var stops: Array = t["stops"]
		for s in stops:
			for p in s["points"]:
				var pr := _walk_problems(w, s["pos"], p)
				assert_true(pr.is_empty(), "%s lantern -> %s: %s" % [s["id"], str(p), str(pr)])
		var last: Vector2 = stops[stops.size() - 1]["pos"]
		var cpr := _walk_problems(w, last, t["cache"]["pos"])
		assert_true(cpr.is_empty(), "%s last stop -> cache: %s" % [id, str(cpr)])


## The whole route can be walked: the route's Lantern Road arch spawn -> every stop in order -> the cache.
func test_each_route_can_be_walked_from_its_arch() -> void:
	var w: Node3D = await _world()
	for id in Data.ORDER:
		var t: Dictionary = Data.TEMPLATES[id]
		var spawn := String(Reach.ARCHES[String(t["arch"])]["spawn"])
		var prev: Vector2 = Reach.SPAWNS[spawn]["pos"]
		var legs: Array = []
		for s in t["stops"]:
			legs.append(s["pos"])
		legs.append(t["cache"]["pos"])
		for p in legs:
			var pr := _walk_problems(w, prev, p, 14)
			assert_true(pr.is_empty(), "%s leg %s -> %s: %s" % [id, str(prev), str(p), str(pr)])
			prev = p


## The real hook: a Reach load gives the area its runner, whose groups stand on the real terrain at the
## authored points of every stop of every route.
func test_the_reach_gets_a_runner_and_groups_stand_on_its_ground() -> void:
	var w: Node3D = await _world()
	var saved_area: Node = Game.area
	var saved_id: String = Game.area_id
	var was := Ex.is_listening()
	Game.area = w
	Game.area_id = Data.AREA_ID
	for f in ["ch2_orchard_restored", "ch2_quarry_restored", "ch2_manor_restored"]:
		GameState.flags[f] = true
	Ex.init()
	Events.area_loaded.emit(Data.AREA_ID)
	assert_null(w.get_node_or_null("Expeditions"), "no run going: a Reach load adds no runner node")
	# A run begun at home (not in the Reach) is picked up when she arrives: the load listener attaches the runner.
	Game.area_id = "surface"
	assert_true(Ex.start(Data.ORDER[0], 99))
	assert_null(w.get_node_or_null("Expeditions"), "started elsewhere: nothing added to the Reach yet")
	Game.area_id = Data.AREA_ID
	Events.area_loaded.emit(Data.AREA_ID)
	var runner: Node3D = w.get_node_or_null("Expeditions")
	assert_not_null(runner, "Events.area_loaded with a run going -> the Reach has its runner")
	if runner != null:
		runner.set_process(false)
		runner.use_camera = false
		var probe := Node3D.new()
		w.add_child(probe)
		runner.player_override = probe
		for id in Data.ORDER:
			if not Ex.is_active():
				assert_true(Ex.start(id, 99))
			assert_eq(String(Ex.active()["template"]), id)
			for i in Ex.stop_count(id):
				runner.update_runner()
				var c: Vector2 = Ex.current_plan()["stops"][i]["pos"]
				probe.global_position = Vector3(c.x, float(w.height_at(c.x, c.y)), c.y + 18.0)
				assert_false(w.is_safe_zone(probe.global_position))
				runner.update_runner()
				assert_eq(runner.alive.size(), int(Ex.current_plan()["stops"][i]["needed"]), "%s stop %d appears" % [id, i])
				for e in runner.alive.duplicate():
					var ep: Vector3 = (e as Node3D).global_position
					assert_almost(ep.y, float(w.height_at(ep.x, ep.z)), 0.6, "%s stop %d: %s on the ground" % [id, i, e.name])
					(e as Node).set_physics_process(false)
					e.get("health").apply_damage(99999.0)
			runner.update_runner()
			assert_true(Ex.in_cache_phase(), "%s walked" % id)
			assert_not_null(runner.cache)
			assert_false(runner.open_cache().is_empty(), "%s pays at the cache" % id)
		runner.update_runner()
		probe.queue_free()
		runner.queue_free()
	for n in get_tree().get_nodes_in_group("world_item"):
		n.queue_free()
	Game.area = saved_area
	Game.area_id = saved_id
	if not was:
		Ex.shutdown()
	await wait_frames(2)


func test_zz_free_the_reach() -> void:
	if _w != null and is_instance_valid(_w):
		_w.free()
	_w = null
