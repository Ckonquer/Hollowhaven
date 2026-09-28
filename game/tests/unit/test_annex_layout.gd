extends "res://tests/test_case.gd"
## Tobin's Lost Shift (area "tobin_annex", module B10): geometry pinned numerically (no screenshots yet).
## Openings >= 1.6 x 2.4 m, rooms >= 2.4 m high, floors above KILL_Y, levels never overlap on XZ; every spawn
## stands on the floor with 2.4 m headroom in a clear capsule; zones / safe places; rays from every room
## centre hit a wall (no holes into the void); the whole route and the side trips are walkable; distinct
## silhouettes; amber lighting within the shadow budget; the checkpoint lantern; echo crystals; the Drudge's
## spawner (or its guard); build < 2.5 s and batched.

const Layout := preload("res://src/world/annex/annex_layout.gd")
const SCENE := "res://scenes/tobin_annex.tscn"
const WORLD := "res://src/world/areas_ch2/tobin_annex_world.gd"
const MASK := 1 | 32
const EXPECTED_ZONES := {"annex_entry": "ta_entry", "annex_lantern": "ta_lockers", "annex_hatch_below": "ta_sump"}

var area: Node3D = null


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _make_area() -> Node3D:
	var ps: PackedScene = load(SCENE)
	var a: Node3D = ps.instantiate()
	add_child(a)
	await wait_physics(3)
	return a


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return area.get_world_3d().direct_space_state.intersect_ray(q)


func _capsule_free(p: Vector3, radius: float = 0.35, height: float = 1.6, lift: float = 1.05) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * lift)
	q.collision_mask = MASK
	var hits := area.get_world_3d().direct_space_state.intersect_shape(q, 4)
	return hits.map(func(h: Dictionary) -> String: return String((h["collider"] as Node).get_parent().name) + "/" + String((h["collider"] as Node).name))


# --- pure layout data ----------------------------------------------------------------------------------

func test_scene_uses_the_annex_script() -> void:
	var ps: PackedScene = load(SCENE)
	var st := ps.get_state()
	var found := false
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == "script":
			found = (st.get_node_property_value(0, i) as Script).resource_path == WORLD
	assert_true(found, "scenes/tobin_annex.tscn runs %s" % WORLD)


func test_openings_rooms_and_levels() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var od: Dictionary = r.get("open", {})
		for side in od:
			var v: Variant = od[side]
			if v is String:
				continue
			for o in v:
				var w: float = float(o[1]) - float(o[0])
				assert_true(w >= 1.6, "%s %s opening width %.2f" % [id, side, w])
				assert_true(float(o[2]) >= 2.4, "%s %s opening height %.2f" % [id, side, float(o[2])])
		assert_true(float(r["h"]) >= 2.4, "%s is at least 2.4 m high" % id)
		var dx := float(r["x1"]) - float(r["x0"])
		var dz := float(r["z1"]) - float(r["z0"])
		if bool(r.get("gap", false)):
			# a doorway through a 1 m wall: as wide as its opening, as deep as the wall
			assert_true(maxf(dx, dz) >= 1.6 and minf(dx, dz) >= 0.99, "%s doorway is wide enough" % id)
		else:
			assert_true(dx >= 1.6 and dz >= 1.6, "%s is wide enough" % id)
		assert_true(float(r["y"]) > -35.0, "%s floor stays far above KILL_Y" % id)
		assert_true(Layout.ZONES.has(String(r["zone"])), "%s zone %s is a spec zone" % [id, r["zone"]])
	# No two rooms overlap on the XZ plane (the levels never stack: height_at is unique).
	var ids: Array = Layout.ROOMS.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = Layout.ROOMS[ids[i]]
			var b: Dictionary = Layout.ROOMS[ids[j]]
			var ox := minf(float(a["x1"]), float(b["x1"])) - maxf(float(a["x0"]), float(b["x0"]))
			var oz := minf(float(a["z1"]), float(b["z1"])) - maxf(float(a["z0"]), float(b["z0"]))
			assert_false(ox > 0.01 and oz > 0.01, "%s and %s do not overlap" % [ids[i], ids[j]])
	# Every opening in one room's wall leads into a "gap" doorway room of the same width.
	for id in Layout.ROOMS:
		var od: Dictionary = (Layout.ROOMS[id] as Dictionary).get("open", {})
		for side in od:
			if od[side] is String:
				continue
			for o in od[side]:
				var mid := (float(o[0]) + float(o[1])) * 0.5
				var r: Dictionary = Layout.ROOMS[id]
				var p := Vector3.ZERO
				match String(side):
					"n": p = Vector3(mid, float(r["y"]) + 0.5, float(r["z0"]) - 0.5)
					"s": p = Vector3(mid, float(r["y"]) + 0.5, float(r["z1"]) + 0.5)
					"w": p = Vector3(float(r["x0"]) - 0.5, float(r["y"]) + 0.5, mid)
					"e": p = Vector3(float(r["x1"]) + 0.5, float(r["y"]) + 0.5, mid)
				var gap := Layout.room_at(p)
				assert_true(gap != "" and bool((Layout.ROOMS[gap] as Dictionary).get("gap", false)), "%s %s opening leads into a doorway room (%s)" % [id, side, gap])


func test_three_distinct_silhouettes() -> void:
	var e: Dictionary = Layout.ROOMS["entry"]
	var l: Dictionary = Layout.ROOMS["lockers"]
	var s: Dictionary = Layout.ROOMS["sump"]
	var ew := float(e["x1"]) - float(e["x0"])
	var ed := float(e["z1"]) - float(e["z0"])
	var lw := float(l["x1"]) - float(l["x0"])
	var ld := float(l["z1"]) - float(l["z0"])
	var sw := float(s["x1"]) - float(s["x0"])
	var sd := float(s["z1"]) - float(s["z0"])
	assert_true(absf(ew / ed - 1.0) < 0.25 and float(e["h"]) <= 3.0, "the lamp room is low and square (%.1f x %.1f x %.1f)" % [ew, ed, float(e["h"])])
	assert_true(ld / lw >= 1.5 and float(l["h"]) >= 4.5, "the lockers are long and tall (%.1f x %.1f x %.1f)" % [lw, ld, float(l["h"])])
	assert_true(sw > lw and float(s["y"]) <= float(l["y"]) - 1.5, "the sump is wide and lies lower (%.1f wide, floor %.1f)" % [sw, float(s["y"])])
	assert_true(sw * sd > ew * ed * 1.5, "the sump is the biggest open space")


func test_stair_floor_and_queries() -> void:
	assert_almost(Layout.floor_at(0.0, -24.5), 0.0, 0.001, "top landing")
	assert_almost(Layout.floor_at(0.0, -27.5), -1.0, 0.001, "half way down")
	assert_almost(Layout.floor_at(0.0, -30.5), -2.0, 0.001, "bottom landing")
	assert_almost(Layout.floor_at(3.0, -37.0), -2.0, 0.001, "sump floor")
	assert_eq(Layout.zone_at(Vector3(0, 0, -3)), "ta_entry")
	assert_eq(Layout.zone_at(Vector3(0, 0, -15)), "ta_lockers")
	assert_eq(Layout.zone_at(Vector3(-6.5, 0, -18.75)), "ta_lockers", "the lantern niche belongs to the lockers")
	assert_eq(Layout.zone_at(Vector3(0, -1, -27.5)), "ta_sump", "the stair leads into the sump")
	assert_eq(Layout.zone_at(Vector3(2, -2, -38)), "ta_sump")
	assert_ne(Layout.zone_at(Vector3(0, 0, 30)), "", "points outside fall back to the nearest room")
	for p in Layout.CRITICAL_PATH:
		assert_ne(Layout.room_at(p), "", "path point %s inside a room" % str(p))
	for path in Layout.SIDE_PATHS:
		for p in path:
			assert_ne(Layout.room_at(p), "", "side point %s inside a room" % str(p))


# --- built area ---------------------------------------------------------------------------------------------

func test_area_basics_and_spawns() -> void:
	area = await _make_area()
	assert_eq(String(area.area_id), "tobin_annex")
	assert_false(bool(area.get("placeholder")), "the real annex, not the stand-in")
	for id in Layout.SPAWNS:
		assert_true(area.spawns.has(id), "spawn %s registered" % id)
		var p: Vector3 = (area.get_spawn(id) as Transform3D).origin
		var hit := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.5)
		assert_false(hit.is_empty(), "%s has ground below" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.3, "%s stands on the floor" % id)
		assert_true(_ray(p + Vector3.UP * 0.2, p + Vector3.UP * 2.4).is_empty(), "%s has 2.4 m headroom" % id)
		assert_eq(_capsule_free(p), [], "%s capsule is free" % id)
		assert_eq(area.get_zone_at(p), String(EXPECTED_ZONES[id]), "%s zone" % id)
		var vp: Variant = area.validate_position(p)
		assert_true(vp is Vector3 and absf((vp as Vector3).y - p.y) < 0.3, "%s is a valid saved position on the floor (%s)" % [id, str(vp)])
	var zone_ids: Array = (area.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
	for z in Layout.ZONES:
		assert_true(zone_ids.has(z), "zone %s registered" % z)
	assert_true(area.is_safe_zone(area.get_spawn("annex_entry").origin), "the lamp room is safe")
	assert_true(area.is_safe_zone(Vector3(3.0, 0, -6.0)), "all of the lamp room")
	assert_true(area.is_safe_zone(area.get_spawn("annex_lantern").origin), "the lantern niche is safe, lit or not")
	assert_false(area.is_safe_zone(area.get_spawn("annex_hatch_below").origin), "the sump is not safe")
	assert_false(area.is_safe_zone(Vector3(0, 0, -25)), "the stair head is not safe")
	assert_false(area.is_safe_zone(Vector3(0, 0, -15)), "the lockers are not safe")
	assert_false(area.is_safe_zone(Vector3(-6.4, -8.0, -18.75)), "safe spots respect height")
	assert_null(area.validate_position(Vector3(40, 0, 0)), "outside the annex is rejected")
	assert_almost(float(area.height_at(0.0, -27.5)), -1.0, 0.01, "height_at follows the stair")
	var has_env := false
	var has_light := false
	for c in area.get_children():
		has_env = has_env or c is WorldEnvironment
		has_light = has_light or c is Light3D
	assert_true(has_env and has_light, "environment and a direct-child light")


## Saved / recovery positions (player unstuck) always come back ON the floor: never on a timber beam or a
## lamp just under the 3 m lamp-room ceiling (the generic probe starts 3 m up), never on a crate top.
func test_validate_position_lands_on_the_floor() -> void:
	area = await _make_area()
	var paths: Array = [Layout.CRITICAL_PATH]
	paths.append_array(Layout.SIDE_PATHS)
	for path in paths:
		for p0 in path:
			var p: Vector3 = p0
			p.y = Layout.floor_at(p.x, p.z)
			var v: Variant = area.validate_position(p + Vector3.UP * 0.08)
			assert_true(v is Vector3, "open floor at %s validates" % str(p))
			if v is Vector3:
				assert_almost((v as Vector3).y, p.y, 0.3, "validated onto the floor at %s" % str(p))
	var checked := 0
	var off_floor: Array = []
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var x := float(r["x0"]) + 0.25
		while x < float(r["x1"]) - 0.2:
			var z := float(r["z0"]) + 0.25
			while z < float(r["z1"]) - 0.2:
				var fy := Layout.floor_at(x, z)
				for lift: float in [0.0, 0.3, 0.9]:
					var v: Variant = area.validate_position(Vector3(x, fy + lift, z))
					checked += 1
					if v is Vector3 and absf((v as Vector3).y - fy) > 0.5:
						off_floor.append("%s %s" % [id, str(v)])
				z += 0.5
			x += 0.5
	assert_true(checked > 1500, "a dense sample (%d)" % checked)
	assert_eq(off_floor.size(), 0, "never validated off the floor: %s" % str(off_floor.slice(0, 6)))


func test_no_escape_from_rooms() -> void:
	GameState.set_flag("ta_hatch_open", true)
	area = await _make_area()
	var centres := {"entry": Layout.room_center("entry"), "lockers": Layout.room_center("lockers"), "niche": Layout.room_center("niche"),
		"sump": Layout.room_center("sump"), "stair": Vector3(0, -1.0, -27.5)}
	for id in centres:
		var c: Vector3 = centres[id]
		for k in 16:
			var a := TAU * float(k) / 16.0
			var dir := Vector3(cos(a), 0, sin(a))
			for h: float in [0.5, 1.5]:
				var from := c + Vector3.UP * h
				if _ray(from, from + dir * 80.0).is_empty():
					fail("%s: ray %d escapes into the void at height %.1f" % [id, k, h])
	# Up and down: floors and ceilings everywhere except the hatch shaft (capped by its walls).
	for id in centres:
		var c: Vector3 = centres[id]
		assert_false(_ray(c + Vector3.UP * 1.0, c + Vector3.DOWN * 5.0).is_empty(), "%s has a floor" % id)
		assert_false(_ray(c + Vector3.UP * 1.0, c + Vector3.UP * 10.0).is_empty(), "%s has a ceiling" % id)
	var hh: Dictionary = Layout.HATCH_HOLE
	var hc := Vector3((float(hh["x0"]) + float(hh["x1"])) * 0.5, 2.0, (float(hh["z0"]) + float(hh["z1"])) * 0.5)
	# The hole itself is open (daylight falls down the shaft onto the ladder foot) and too high to jump into.
	var top := float(Layout.ROOMS["sump"]["y"]) + float(Layout.ROOMS["sump"]["h"])
	assert_true(_ray(Vector3(hc.x, -1.0, hc.z), Vector3(hc.x, top + Layout.SHAFT_HEIGHT - 0.2, hc.z)).is_empty(), "the hatch shaft is open above the ladder")
	assert_true(top - float(Layout.ROOMS["sump"]["y"]) >= 4.0, "the hole is far out of jumping reach")
	for k in 8:
		var a := TAU * float(k) / 8.0
		var from := hc + Vector3.UP * 2.0
		assert_false(_ray(from, from + Vector3(cos(a), 0, sin(a)) * 20.0).is_empty(), "the hatch shaft is walled (%d)" % k)


func test_route_and_side_trips_are_walkable() -> void:
	area = await _make_area()
	var paths: Array = [Layout.CRITICAL_PATH]
	paths.append_array(Layout.SIDE_PATHS)
	for path in paths:
		for i in range((path as Array).size() - 1):
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			var n := maxi(int(Vector2(b.x - a.x, b.z - a.z).length() / 0.4), 1)
			for s in n + 1:
				var p := a.lerp(b, float(s) / float(n))
				p.y = Layout.floor_at(p.x, p.z)
				var hit := _ray(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.8)
				if hit.is_empty() or absf(float(hit["position"].y) - p.y) > 0.3:
					fail("no floor at %s (%s)" % [str(p), "none" if hit.is_empty() else "%.2f" % float(hit["position"].y)])
					continue
				var blocked := _capsule_free(p, 0.3, 1.2, 0.95)
				if not blocked.is_empty():
					fail("blocked at %s by %s" % [str(p), str(blocked)])


func test_amber_lighting_within_budget() -> void:
	area = await _make_area()
	var shadowed := 0
	var lights := 0
	for l in area.find_children("*", "Light3D", true, false):
		var li := l as Light3D
		if not li.is_visible_in_tree():
			continue
		lights += 1
		if li.shadow_enabled:
			shadowed += 1
	assert_true(lights >= 8, "a lit annex (%d lights)" % lights)
	assert_true(shadowed <= 5, "few shadowed lights (%d)" % shadowed)
	var flick := 0
	for n in area.get_tree().get_nodes_in_group("flicker_light"):
		if area.is_ancestor_of(n):
			flick += 1
			assert_true(n.has_method("flicker"), "flicker_light has flicker()")
			var li: Variant = n.get("light")
			if li is Light3D:
				var c: Color = (li as Light3D).light_color
				assert_true(c.r > c.b + 0.35 and c.r >= c.g, "mine lamp %s is amber (%s)" % [n.name, c.to_html()])
	assert_true(flick >= 6, "mine lamps (%d)" % flick)
	# Each space has at least one lamp of its own.
	for room in ["entry", "lockers", "stair", "sump"]:
		var node: Node = area.get_node_or_null("Room_" + room)
		var has := false
		if node != null:
			for n in node.find_children("*", "Light3D", true, false):
				has = true
		assert_true(has, "%s has a lamp" % room)


func test_checkpoint_lantern() -> void:
	area = await _make_area()
	var cp: Node3D = area.checkpoint
	assert_not_null(cp, "checkpoint built")
	assert_true(cp.is_in_group("checkpoint"), "in group checkpoint")
	assert_eq(String(cp.get("checkpoint_id")), "ta_lantern")
	assert_eq(String(cp.get("area_id")), "tobin_annex", "it sets the respawn in this area")
	assert_eq(String(cp.get("spawn_id")), "annex_lantern")
	assert_eq(area.get_zone_at(cp.global_position), "ta_lockers")
	assert_eq(_capsule_free(area.get_spawn("annex_lantern").origin), [], "the lantern leaves room to stand")
	cp.set("save_enabled", false)
	cp.interact(null)
	assert_true(bool(GameState.get_flag("cp_lit_ta_lantern")), "flag cp_lit_ta_lantern")
	assert_eq(String(GameState.player.get("respawn_area", "")), "tobin_annex")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "annex_lantern")
	assert_eq(String((GameState.player.get("area_respawn", {}) as Dictionary).get("tobin_annex", "")), "annex_lantern", "remembered per area")
	assert_true(cp.is_light_active(), "a lit lantern is a light source")


func test_echo_crystals() -> void:
	area = await _make_area()
	var min_count := int((ItemDB.node_kind("crystal").get("min_count", {}) as Dictionary).get("tobin_annex", 2))
	assert_true(area.crystals.size() >= min_count, "at least %d echo crystals (%d)" % [min_count, area.crystals.size()])
	assert_true(ItemDB.node_kinds_in("tobin_annex", "ta_sump").has("crystal"), "data: crystals in the sump")
	for id in area.crystals:
		var n: Node3D = area.crystals[id]
		assert_true(String(id).begins_with("ta_crystal_"), "stable ta_ id %s" % id)
		assert_eq(String(n.get("kind")), "crystal")
		assert_eq(String(n.get("node_id")), String(id))
		assert_eq(area.get_zone_at(n.global_position), "ta_sump", "%s in the sump" % id)
		var p := n.global_position
		var hit := _ray(p + Vector3.UP * 0.2, p + Vector3.DOWN * 1.0)
		assert_true(not hit.is_empty() and absf(float(hit["position"].y) - p.y) < 0.2, "%s on the floor" % id)
		assert_true(n.is_in_group("harvestable"), "%s is harvestable" % id)


func test_drudge_encounter_or_guard() -> void:
	area = await _make_area()
	var home: Vector3 = Layout.DRUDGE["pos"]
	assert_eq(area.get_zone_at(home), "ta_lockers", "the Drudge works in the lockers")
	assert_false(area.is_safe_zone(home), "its home is not in a safe zone")
	assert_true(home.distance_to(area.get_spawn("annex_entry").origin) >= 9.0, "seen from the lamp room, not beside it")
	var spot: Dictionary = Layout.SAFE_SPOTS[0]
	assert_true(Vector2(home.x - spot["center"].x, home.z - spot["center"].z).length() > float(spot["radius"]) + 4.0, "clear of the lantern niche")
	var params: Dictionary = area.drudge_params()
	assert_eq(String(params["enemy"]), "hollow_drudge")
	assert_eq(String(params["spawner_id"]), "ta_sp_drudge")
	assert_eq(String(params["quest_flag_on_clear"]), "c1x_drudge_defeated")
	assert_eq(int(params["count"]), 1, "one Drudge: a teaching encounter")
	assert_true(float(params["respawn_minutes"]) < 0.0, "once beaten it stays beaten")
	assert_true(ItemDB.enemy("hollow_drudge").size() > 0, "data/enemies.gd knows the Drudge")
	if area.drudge_available():
		var sp: Node3D = area.drudge_spawner
		assert_not_null(sp, "the spawner is placed")
		assert_false(area.drudge_fallback)
		assert_eq(String(sp.get("spawner_id")), "ta_sp_drudge")
		assert_eq(String(sp.get("enemy_id")), "hollow_drudge")
		assert_true(bool(sp.get("ignore_safe_zones")), "already standing there when Krystal arrives")
		# Beating the wave sets the goal flag (EnemySpawner rule) and never respawns it.
		sp.call("_on_wave_cleared")
		assert_true(bool(GameState.get_flag("c1x_drudge_defeated")), "c1x_drudge_defeated")
		assert_false(bool(sp.call("wave_available")), "no second Drudge")
	else:
		assert_true(area.drudge_fallback, "guarded when the enemy is missing")
		area.on_zone("ta_lockers")
		assert_true(bool(GameState.get_flag("c1x_drudge_defeated")), "anti-softlock")


func test_drudge_spawns_in_the_lockers() -> void:
	area = await _make_area()
	if not area.drudge_available():
		print("    (hollow_drudge not available: spawn check skipped)")
		return
	var stand_in := Node3D.new()
	area.add_child(stand_in)
	stand_in.global_position = area.get_spawn("annex_entry").origin
	var sp: Node3D = area.drudge_spawner
	sp.set("player_override", stand_in)
	sp.call("update_spawner")
	var alive: Array = sp.get("alive")
	assert_eq(alive.size(), 1, "one Drudge spawned while Krystal stands in the safe lamp room")
	if alive.size() == 1:
		var e: Node3D = alive[0]
		assert_true(e.is_in_group("enemy"), "an enemy")
		assert_eq(area.get_zone_at(e.global_position), "ta_lockers", "in the lockers")
		assert_true(e.global_position.distance_to(Layout.DRUDGE["pos"]) < 2.0, "at its home")
	sp.call("despawn_all")
	await wait_frames(2)


## Once c1x_drudge_defeated is set (by the spawner's clear or by the guard) a rebuild never brings a live Drudge
## back: the empty coat lies where it worked, no spawner, no hint.
func test_beaten_drudge_stays_beaten() -> void:
	GameState.set_flag("c1x_drudge_defeated", true)
	area = await _make_area()
	assert_null(area.drudge_spawner, "no spawner once it is dealt with")
	assert_not_null(area.get_node_or_null("SlumpedCoat"), "the empty coat lies still")
	var n := 0
	for e in area.get_tree().get_nodes_in_group("enemy"):
		if area.is_ancestor_of(e):
			n += 1
	assert_eq(n, 0, "nothing hostile in the annex")
	var hints: Array = []
	var cb := func(id: String, _t: String) -> void: hints.append(id)
	Events.hint.connect(cb)
	area.on_zone("ta_lockers")
	Events.hint.disconnect(cb)
	assert_eq(hints.size(), 0, "no Drudge hint")


## The lantern niche is a refuge, not a vantage point: its safe circle never reaches the hall floor.
func test_niche_safe_spot_stays_in_the_niche() -> void:
	var spot: Dictionary = Layout.SAFE_SPOTS[0]
	var c: Vector3 = spot["center"]
	var hall_x0 := float(Layout.ROOMS["lockers"]["x0"])
	assert_true(c.x + float(spot["radius"]) <= hall_x0 + 0.001, "the circle ends at the hall's wall line")
	assert_true(Layout.is_safe_point(Layout.SPAWNS["annex_lantern"]["pos"]), "annex_lantern is safe")
	assert_true(Layout.is_safe_point(Layout.CHECKPOINT["pos"]), "beside the lantern is safe")
	assert_true(Layout.is_safe_point(Vector3(-5.0, 0.0, -18.75)), "the niche doorway is safe")
	for z: float in [-20.5, -18.75, -17.0]:
		assert_false(Layout.is_safe_point(Vector3(hall_x0 + 0.3, 0.0, z)), "the hall floor at z %.2f is not safe" % z)


## Every interactable and echo crystal can really be used: the player's own interaction probe (reach 2.6 m,
## facing, line of sight through walls/props) focuses it from a free standing spot on the floor.
func test_story_spots_crystals_and_exits_are_usable() -> void:
	area = await _make_area()
	var Probe: Script = load("res://src/player/interaction_probe.gd")
	var stand := Node3D.new()
	area.add_child(stand)
	var probe: Node = Probe.new()
	probe.set("player", stand)
	area.add_child(probe)
	await wait_physics(1)
	var cases: Array = [
		["board", area.board_spot, Vector3(-2.4, 0.0, -3.6)],
		["door", area.door, Vector3(0.0, 0.0, -1.9)],
		["letter", area.letter_spot, Vector3(2.9, 0.0, -19.6)],
		["checkpoint", area.checkpoint, Vector3(-5.9, 0.0, -18.75)],
		["note", area.note_spot, Vector3(4.7, -2.0, -34.6)],
		["mark", area.mark_spot, Vector3(-0.8, -2.0, -40.3)],
		["hatch", area.hatch, Vector3(4.6, -2.0, -39.6)],
		["ta_crystal_1", area.crystals.get("ta_crystal_1"), Vector3(-3.2, -2.0, -34.4)],
		["ta_crystal_2", area.crystals.get("ta_crystal_2"), Vector3(-4.6, -2.0, -39.0)],
		["ta_crystal_3", area.crystals.get("ta_crystal_3"), Vector3(-2.3, -2.0, -39.5)],
	]
	for c in cases:
		var target: Node3D = c[1]
		var p: Vector3 = c[2]
		assert_not_null(target, "%s exists" % c[0])
		if target == null:
			continue
		assert_eq(_capsule_free(p), [], "%s: room to stand at %s" % [c[0], str(p)])
		var hit := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.0)
		assert_true(not hit.is_empty() and absf(float(hit["position"].y) - p.y) < 0.2, "%s: floor under %s" % [c[0], str(p)])
		var to := target.global_position - p
		stand.global_transform = Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), p)
		probe.call("refresh")
		var focus: Variant = probe.get("focus")
		assert_true(focus == target, "%s is focused from %s (got %s)" % [c[0], str(p), str(focus.name) if focus is Node else "nothing"])
	probe.queue_free()
	stand.queue_free()


## The annex reuses below_builder.gd through its layout-agnostic constructor; the Below keeps its own table.
func test_below_builder_stays_layout_agnostic() -> void:
	const Builder := preload("res://src/world/below/below_builder.gd")
	const BelowLayout := preload("res://src/world/below/below_layout.gd")
	var host := Node3D.new()
	add_child(host)
	var legacy: RefCounted = Builder.new(host)
	assert_eq(legacy.get("rooms"), BelowLayout.ROOMS, "default = the Below's rooms")
	var mine: RefCounted = Builder.new(host, 5150, Layout.ROOMS)
	assert_eq(mine.get("rooms"), Layout.ROOMS, "the annex passes its own rooms")
	var hash_before := JSON.stringify(BelowLayout.ROOMS).hash()
	area = await _make_area()
	assert_eq(JSON.stringify(BelowLayout.ROOMS).hash(), hash_before, "building the annex never touches the Below layout")
	for z in Layout.ZONES:
		assert_true(String(z).begins_with("ta_"), "zone %s is namespaced (never a Below zone string)" % z)
	host.queue_free()


func test_build_is_fast_and_batched() -> void:
	var t0 := Time.get_ticks_msec()
	area = await _make_area()
	var ms := Time.get_ticks_msec() - t0
	print("    annex build %d ms (area reports %d ms)" % [ms, int(area.build_ms)])
	assert_true(ms < 2500, "area builds quickly (%d ms)" % ms)
	var mm := 0
	var mmi := 0
	for n in area.find_children("*", "MultiMeshInstance3D", true, false):
		mm += (n as MultiMeshInstance3D).multimesh.instance_count
		mmi += 1
	print("    %d batched instances in %d multimeshes" % [mm, mmi])
	assert_true(mm > 400, "dressing is batched (%d instances)" % mm)
	assert_true(mmi < 120, "few draw batches (%d)" % mmi)
	var meshes := area.find_children("*", "MeshInstance3D", true, false).size()
	assert_true(meshes < 400, "bounded plain meshes (%d)" % meshes)
