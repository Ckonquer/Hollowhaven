extends "res://tests/test_case.gd"
## Hushed Works rooms 9-14: the room table (data/works_layout_deep.gd) is valid Builder data, stays in its
## box (x 40..170, floors -34..-6), starts at the hub door, has passable openings, no overlapping rooms,
## covers the critical path / side paths / spawns, and names the spec §7.2 zone ids.

const Layout := preload("res://data/works_layout_deep.gd")
const SPEC_ZONES := ["hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]
const CONTRACT_SPAWNS := ["crossing_gate", "bell_throat", "vault_exit"]


func test_room_table_is_valid_builder_data() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		for k in ["x0", "x1", "z0", "z1", "y", "h", "zone", "space", "open"]:
			assert_true(r.has(k), "%s has key %s" % [id, k])
		assert_true(float(r["x0"]) < float(r["x1"]) and float(r["z0"]) < float(r["z1"]), "%s box is ordered" % id)
		assert_true(float(r["x0"]) >= Layout.X_MIN - 0.001 and float(r["x1"]) <= Layout.X_MAX + 0.001, "%s inside x [40,170]" % id)
		assert_true(float(r["y"]) >= Layout.Y_MIN and float(r["y"]) <= Layout.Y_MAX, "%s floor inside y [-34,-6]" % id)
		assert_true(float(r["h"]) >= 2.4, "%s at least 2.4 m high" % id)
		assert_true(SPEC_ZONES.has(String(r["zone"])), "%s zone %s is a spec zone" % [id, String(r["zone"])])
		assert_true(float(r["y"]) > -40.0 + 3.0, "%s well above KILL_Y" % id)
		if r.has("slope"):
			assert_true(r["slope"] is Dictionary and (r["slope"] as Dictionary).has("axis"), "%s slope uses the shared {axis, y0, y1} format" % id)
			var ends := Layout.slope_ends(id)
			var a: Vector3 = ends[0]
			var b: Vector3 = ends[1]
			var run := Vector2(b.x - a.x, b.z - a.z).length()
			assert_true(absf(b.y - a.y) / run <= tan(deg_to_rad(32.0)), "%s slope is a gentle stair (%.1f over %.1f)" % [id, absf(b.y - a.y), run])


func test_openings_are_passable() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var open: Dictionary = r["open"]
		for side in open:
			var od: Variant = open[side]
			if od is String:
				assert_eq(String(od), "all", "%s %s" % [id, side])
				continue
			var along_x: bool = side == "n" or side == "s"
			var a0: float = float(r["x0"]) if along_x else float(r["z0"])
			var a1: float = float(r["x1"]) if along_x else float(r["z1"])
			for o in od:
				assert_true(float(o[1]) - float(o[0]) >= 1.6, "%s %s opening at least 1.6 m wide" % [id, side])
				assert_true(float(o[2]) >= 2.4, "%s %s opening at least 2.4 m tall" % [id, side])
				assert_true(float(o[0]) >= a0 and float(o[1]) <= a1, "%s %s opening lies on the wall" % [id, side])


func test_room_nine_starts_at_the_hub_door() -> void:
	var door := Layout.HUB_DOOR
	assert_eq(door, Vector3(40.0, -18.0, 0.0), "hub door centre (spec §10)")
	var first := Layout.room_at(door + Vector3(0.3, 0.2, 0.0))
	assert_eq(first, "hw_winch_way", "the first deep room begins at the door")
	var r: Dictionary = Layout.ROOMS["hw_winch_way"]
	assert_almost(float(r["x0"]), 40.0, 0.001, "room 9 starts at x 40")
	assert_almost(float(r["y"]), door.y, 0.001, "same floor as the hub door")
	assert_eq(String(r["open"]["w"]), "all", "west side open toward the hub (the hub's wall carries the door)")
	assert_true(float(r["z0"]) <= -1.6 and float(r["z1"]) >= 1.6, "corridor wider than the largest allowed hub door")
	assert_eq(Layout.zone_of_room(first), "hw_winch", "the corridor is room 9 (Threaded Winch)")
	assert_true((Layout.CRITICAL_PATH[0] as Vector3).distance_to(door) < 0.5, "critical path starts at the door")
	# Rooms 1-8 live west of x 40 (their data file, when present, must not overlap ours).
	var other := "res://data/works_layout.gd"
	if ResourceLoader.exists(other):
		var s: Script = load(other)
		var rooms: Variant = s.get_script_constant_map().get("ROOMS", {}) if s != null else {}
		if rooms is Dictionary:
			for oid in rooms:
				assert_false(Layout.ROOMS.has(oid), "room id %s is not shared with rooms 1-8" % oid)
				var o: Dictionary = rooms[oid]
				if o.has("x1"):
					assert_true(float(o["x1"]) <= 40.0 + 1.01, "rooms 1-8 room %s stays west of the door" % oid)


func test_rooms_do_not_overlap() -> void:
	var ids: Array = Layout.ROOMS.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = Layout.ROOMS[ids[i]]
			var b: Dictionary = Layout.ROOMS[ids[j]]
			var ox := minf(float(a["x1"]), float(b["x1"])) - maxf(float(a["x0"]), float(b["x0"]))
			var oz := minf(float(a["z1"]), float(b["z1"])) - maxf(float(a["z0"]), float(b["z0"]))
			var oy := minf(float(a["y"]) + float(a["h"]), float(b["y"]) + float(b["h"])) - maxf(float(a["y"]), float(b["y"]))
			assert_false(ox > 0.01 and oz > 0.01 and oy > 0.01, "rooms %s and %s overlap" % [ids[i], ids[j]])


func test_paths_and_spawns_lie_inside_rooms() -> void:
	for p in Layout.CRITICAL_PATH:
		assert_ne(Layout.room_at(p + Vector3.UP * 0.1), "", "critical point %s inside a room" % str(p))
	for path in Layout.SIDE_PATHS:
		for p in path:
			assert_ne(Layout.room_at(p + Vector3.UP * 0.1), "", "side point %s inside a room" % str(p))
	for id in CONTRACT_SPAWNS:
		assert_true(Layout.SPAWNS.has(id), "contract spawn %s is in the table" % id)
	for id in Layout.SPAWNS:
		var p: Vector3 = Layout.SPAWNS[id]["pos"]
		assert_ne(Layout.room_at(p + Vector3.UP * 0.1), "", "spawn %s inside a room" % id)
	assert_eq(Layout.zone_of_room(Layout.room_at((Layout.SPAWNS["bell_throat"]["pos"] as Vector3) + Vector3.UP * 0.1)), "hw_throat")
	assert_eq(Layout.zone_of_room(Layout.room_at((Layout.SPAWNS["vault_exit"]["pos"] as Vector3) + Vector3.UP * 0.1)), "hw_vault")
	assert_eq(Layout.zone_of_room(Layout.room_at((Layout.SPAWNS["crossing_gate"]["pos"] as Vector3) + Vector3.UP * 0.1)), "hw_winch",
		"the crossing checkpoint is BEFORE the arena")


func test_zone_ids_and_design_rooms() -> void:
	var z := Layout.zone_ids()
	z.sort()
	var want := SPEC_ZONES.duplicate()
	want.sort()
	assert_eq(z, want, "exactly the spec §7.2 zones of rooms 9-14")
	for n in [9, 10, 11, 12, 13, 14]:
		assert_true(Layout.DESIGN_ROOMS.has(n), "design room %d mapped" % n)
	assert_true(bool(Layout.ROOMS["hw_throat"].get("safe", false)), "Bell Throat is a safe room")
	for id in Layout.ROOMS:
		if id != "hw_throat":
			assert_false(bool(Layout.ROOMS[id].get("safe", false)), "%s is not safe" % id)


func test_rooms_are_distinct_places() -> void:
	# ceiling heights of the six design rooms must differ (silhouette), as must their light moods.
	var heights := {}
	for n in Layout.DESIGN_ROOMS:
		var r: Dictionary = Layout.ROOMS[Layout.DESIGN_ROOMS[n]]
		heights[float(r["h"])] = true
	assert_true(heights.size() >= 5, "at least five different ceiling heights (%d)" % heights.size())
	var moods := {}
	for zone in Layout.MOODS:
		moods[(Layout.MOODS[zone]["ambient"] as Color).to_html()] = true
	assert_eq(moods.size(), 6, "six different light temperatures")


func test_arena_data() -> void:
	var cr: Dictionary = Layout.CROSSING
	assert_eq((cr["anchors"] as Array).size(), 5, "authored ceiling anchors")
	assert_eq((cr["braziers"] as Array).size(), 3, "three line-braziers")
	var bridge: Rect2 = cr["bridge"]
	assert_true(bridge.size.y >= 8.0, "a BROAD service bridge (>= 8 m)")
	for i in 3:
		var a: Vector3 = cr["anchors"][i]
		var b: Vector3 = cr["braziers"][i]
		assert_true(Vector2(a.x - b.x, a.z - b.z).length() < 0.5, "brazier %d under its anchor" % i)
		assert_true(bridge.has_point(Vector2(b.x, b.z)), "brazier %d on the deck" % i)
	var v: Dictionary = Layout.VAULT
	assert_eq((v["anchors"] as Array).size(), 3, "three fixed lantern anchors")
	assert_eq((v["resonators"] as Array).size(), 2, "two fixed resonators")
	for a in v["anchors"]:
		var d := Vector2((a as Vector3).x - (v["center"] as Vector3).x, (a as Vector3).z - (v["center"] as Vector3).z).length()
		assert_true(d < float(v["perimeter"]) - 1.0, "anchor inside the ring, clear of the perimeter walk")
	assert_true(float(v["radius"]) >= 12.0, "a LARGE circular vault")
	var syms := Layout.bell_symbols()
	assert_true(syms.size() >= 2, "a symbol set for the resonators")
	for s in syms:
		assert_true((s as Dictionary).has("id") and (s as Dictionary).has("name") and (s as Dictionary).has("caption"), "symbol entry complete")


func test_room_at_detects_levels() -> void:
	assert_eq(Layout.room_at(Vector3(88.0, -18.0, 0.0)) in ["hw_crossing", "hw_crossing_pit"], true, "bridge level")
	assert_eq(Layout.room_at(Vector3(88.0, -26.0, 8.0)), "hw_crossing_pit", "pit floor")
	assert_eq(Layout.room_at(Vector3(157.0, -32.0, 65.0)), "hw_vault", "vault centre")
	assert_eq(Layout.room_at(Vector3(145.0, -32.0, 53.0)), "", "the vault's square corners are outside the ring")
	assert_almost(Layout.floor_y_at("hw_crossing_exit", Vector3(113.0, 0.0, 0.0)), -20.0, 0.01, "stair floor height")
	assert_eq(Layout.nearest_room(Vector3(39.0, -18.0, 0.0)), "hw_winch_way", "nearest room fallback")
