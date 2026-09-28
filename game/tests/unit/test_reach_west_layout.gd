extends "res://tests/unit/test_reach_west_fixture.gd"
## Reach west districts (module C2): the data contract (data/reach_west.gd) - sites inside their landmarks,
## clear of the region's arch and the player's outpost, unique prefixed ids, the sources minimums, flags that the
## quest layer / optional log really read, footprints covering the builds. Pure data: no scene.

const Sources := preload("res://data/sources.gd")
const Enemies := preload("res://data/enemies.gd")
const QuestsCh2 := preload("res://data/quests_ch2.gd")
const Optional := preload("res://data/optional_goals.gd")


## Every authored point of a district with the room it needs around it (metres).
func _points(district: String) -> Array:
	var out: Array = []
	for e in Data.nodes_in(district):
		out.append([e["pos"], 1.0, String(e["id"])])
	for sid in Data.spawners_in(district):
		out.append([Data.SPAWNERS[sid]["pos"], float(Data.SPAWNERS[sid]["radius"]), sid])
	match district:
		Data.ORCHARD:
			for k in Data.IRRIGATION:
				if Data.IRRIGATION[k] is Vector2:
					out.append([Data.IRRIGATION[k], 1.5, "irrigation." + k])
			for k2 in Data.GARDEN:
				if Data.GARDEN[k2] is Vector2 and k2 != "bed_size":
					out.append([Data.GARDEN[k2], 1.0, "garden." + k2])
			out.append([Data.MOMENT["pos"], 1.0, "moment"])
			out.append([Data.MIMIC_POCKET["center"], float(Data.MIMIC_POCKET["radius"]) + 0.2, "mimic pocket"])
			out.append([Data.PATCH_POCKET["center"], 3.0, "patch pocket"])
			for gp in Data.ORCHARD_DECOR["giant_pumpkins"]:
				out.append([gp[0], float(gp[1]), "giant pumpkin"])
			for s in Data.ORCHARD_DECOR["scarecrows"]:
				out.append([s, 0.4, "scarecrow"])
			for run in Data.ORCHARD_DECOR["fences"]:
				out.append([run[0], 0.2, "fence"])
				out.append([run[1], 0.2, "fence"])
		Data.POOLS:
			for c in Data.CHIMES:
				out.append([c, 0.5, "chime"])
			for s2 in Data.STEPPING_STONES:
				out.append([s2, 0.5, "stone"])
			for pd in Data.POOL_DISCS:
				out.append([pd[0], float(pd[1]), "pool"])
			for bp in Data.BROOK:
				out.append([bp, Data.BROOK_WIDTH * 0.5, "brook"])
			out.append([Data.POUCH, 0.5, "pouch"])
			out.append([Data.WILLOW, 1.5, "willow"])
			out.append([Data.SPRING_STONE, 0.9, "spring"])
			out.append([Data.MOSSY_LOG, 1.6, "log"])
		Data.CANDLEYARD:
			out.append([Data.CANDLEYARD_CENTER, Data.WALL_RADIUS + 0.3, "wall"])
			for a in range(0, 360, 10):
				out.append([Data.gate_point(float(a)), 0.3, "wall ring"])
			for st in Data.LEANING_STONES:
				out.append([st[0], 0.5, "stone"])
			for rp in Data.HAT_RIBBONS:
				out.append([rp, 1.0, "ribbon"])
			for pt in [Data.SHED["pos"], Data.SHED["note"], Data.SHED["tools"], Data.SHED["barrow"], Data.PATTERN_SPOT,
					Data.NOTE_2, Data.MARKER, Data.NOOK, Data.HAT["pos"], Data.HAT["stand"], Data.BENCH["pos"], Data.CANDLE_TREE]:
				out.append([pt, 0.8, "site"])
	return out


func test_every_site_lies_inside_its_landmark() -> void:
	for district in [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]:
		var c := Data.center_of(district)
		var r := Data.radius_of(district)
		assert_eq(c, (Reach.LANDMARKS[district]["pos"] as Vector2), "%s centre from hallowmere_layout" % district)
		for p in _points(district):
			var d := (p[0] as Vector2).distance_to(c) + float(p[1])
			assert_true(d <= r + 0.05, "%s: %s at %s (+%.1f m) stays inside the %.0f m landmark (%.2f)" % [district, p[2], str(p[0]), float(p[1]), r, d])
	# The three districts never overlap each other.
	var ids := [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var dd := Data.center_of(ids[i]).distance_to(Data.center_of(ids[j]))
			assert_true(dd > Data.radius_of(ids[i]) + Data.radius_of(ids[j]), "%s and %s are separate" % [ids[i], ids[j]])


func test_the_region_arch_and_the_players_outpost_stay_clear() -> void:
	assert_eq(Data.ORCHARD_ARCH, (Reach.ARCHES["orchard"]["pos"] as Vector2), "orchard arch point from hallowmere_layout")
	for p in _points(Data.ORCHARD):
		var d := (p[0] as Vector2).distance_to(Data.ORCHARD_ARCH) - float(p[1])
		assert_true(d >= Data.ARCH_CLEARANCE, "%s keeps %.0f m from the region's orchard arch (%.1f)" % [p[2], Data.ARCH_CLEARANCE, d])
	# The arch's safe circle never contains a spawner (a safe spawner never spawns, the pocket would soft-lock).
	for sid in Data.SPAWNERS:
		var sp: Vector2 = Data.SPAWNERS[sid]["pos"]
		for a in Reach.ARCHES:
			assert_true(sp.distance_to(Reach.ARCHES[a]["pos"]) > Reach.ARCH_SAFE_RADIUS + float(Data.SPAWNERS[sid]["radius"]) + 5.0, "%s away from arch %s" % [sid, a])
		for l in Reach.LANDMARKS:
			if bool(Reach.LANDMARKS[l]["safe"]):
				assert_true(sp.distance_to(Reach.LANDMARKS[l]["pos"]) > float(Reach.LANDMARKS[l]["radius"]) + 5.0, "%s outside safe %s" % [sid, l])
	for district in [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]:
		for p2 in _points(district):
			assert_true((p2[0] as Vector2).distance_to(Data.OUTPOST_CENTER) > Data.OUTPOST_CLEARANCE, "%s far from the player's outpost build area" % p2[2])
	assert_eq(Data.OUTPOST_CENTER, (Reach.OUTPOST_BUILD_AREA["center"] as Vector2), "outpost centre from hallowmere_layout")


func test_ids_are_unique_prefixed_and_new() -> void:
	var seen := {}
	var counters := {}
	for e in Data.NODES:
		var id := String(e["id"])
		assert_false(seen.has(id), "node id %s is unique" % id)
		seen[id] = true
		var kind := String(e["kind"])
		var token: String = Data.NODE_TOKENS.get(kind, "?")
		assert_true(id.begins_with("hr_" + token + "_"), "%s follows hr_<kind>_<n> (spec §2)" % id)
		var n := int(id.get_slice("_", 2))
		assert_eq(n, int(counters.get(token, 0)), "%s numbered in order" % id)
		counters[token] = n + 1
		assert_false(id.begins_with("tree_") or id.begins_with("below_") or id.begins_with("c1x_"), "%s is not a legacy / Chapter One id" % id)
	for sid in Data.SPAWNERS:
		assert_true(String(sid).begins_with("hr_sp_"), "spawner %s uses hr_sp_ (spec §2)" % sid)
		assert_false(seen.has(sid), "spawner id differs from node ids")
		assert_true(Data.SPAWNER_ORDER.has(sid), "spawner %s listed in SPAWNER_ORDER" % sid)
	assert_eq(Data.SPAWNER_ORDER.size(), Data.SPAWNERS.size())
	for legacy in ["ruin_bramblings", "thicket_bramblings", "quarry_bramblings", "gallery_gloom", "hall_gloom"]:
		assert_false(Data.SPAWNERS.has(legacy), "never a legacy spawner id")
	assert_true(Data.SPAWNERS.has("hr_sp_orchard_mimics") and Data.SPAWNERS.has("hr_sp_orchard_patchwalkers"), "spec spawner ids")
	assert_eq(String(Data.SPAWNERS["hr_sp_orchard_mimics"]["enemy"]), "pumpkin_mimic")
	assert_true(float(Data.SPAWNERS["hr_sp_orchard_mimics"]["respawn_minutes"]) < 0.0, "the taught (story) mimic group stays cleared")
	for sid2 in ["hr_sp_orchard_patchwalkers", "hr_sp_candleyard_drudges", "hr_sp_candleyard_patchwalkers"]:
		assert_true(float(Data.SPAWNERS[sid2]["respawn_minutes"]) > 0.0, "%s is a repeatable optional loop" % sid2)
	for sid3 in Data.SPAWNERS:
		assert_true(Enemies.ENEMIES.has(String(Data.SPAWNERS[sid3]["enemy"])), "%s enemy id exists in data/enemies.gd" % sid3)
		assert_true(String(sid3).begins_with("hr_sp_orchard") == (String(Data.SPAWNERS[sid3]["district"]) == Data.ORCHARD), "%s district" % sid3)


func test_node_counts_meet_the_sources_minimums() -> void:
	var counts := {}
	for e in Data.NODES:
		counts[e["kind"]] = int(counts.get(e["kind"], 0)) + 1
		var where: Dictionary = Sources.NODES[e["kind"]]["where"]
		assert_true((where.get(Data.AREA_ID, []) as Array).has(String(e["district"])), "%s: kind %s belongs to %s (data/sources.gd)" % [e["id"], e["kind"], e["district"]])
	# Every kind data/sources.gd puts in our districts (sap stumps: only the orchard + Candleyard in the Reach; sunflax:
	# the Commons + orchard, and the Commons module places none, so the orchard alone meets the Reach minimum).
	for kind in ["pumpkin_vine", "sugarcap_patch", "moonpetal_patch", "sap_stump", "sunflax_patch"]:
		var need := int(Sources.NODES[kind]["min_count"][Data.AREA_ID])
		assert_true(int(counts.get(kind, 0)) >= need, "%s: %d >= min_count %d" % [kind, int(counts.get(kind, 0)), need])
	# Roseberries are shared with no other Reach module (orchard hedges + Candleyard edges).
	assert_true(int(counts.get("roseberry_bush", 0)) >= int(Sources.NODES["roseberry_bush"]["min_count"][Data.AREA_ID]), "roseberry minimum")
	assert_eq(String(Sources.NODES["pumpkin_vine"]["access_flag"]), "", "wild pumpkins need no gate")


func test_wild_pumpkins_never_sit_in_a_combat_pocket() -> void:
	var margin := 5.0     # aggro room (pumpkin mimic aggro 6 m is measured from the dormant spots inside the ring)
	for e in Data.nodes_in(Data.ORCHARD):
		var p: Vector2 = e["pos"]
		assert_true(p.distance_to(Data.MIMIC_POCKET["center"]) > float(Data.MIMIC_POCKET["radius"]) + margin, "%s outside the mimic patch" % e["id"])
		assert_true(p.distance_to(Data.PATCH_POCKET["center"]) > float(Data.PATCH_POCKET["radius"]) + margin, "%s outside the Patchwalker field" % e["id"])
	assert_true(Data.MIMIC_POCKET["center"].distance_to(Data.PATCH_POCKET["center"]) > float(Data.MIMIC_POCKET["radius"]) + float(Data.PATCH_POCKET["radius"]) + 6.0, "the two orchard pockets are separate")
	assert_true(Data.MIMIC_POCKET["center"].distance_to(Data.GARDEN["lamp"]) > 20.0, "the garden lamp is not inside the fight")


func test_flags_and_rewards_match_the_quest_layer_and_optional_log() -> void:
	var q_script: Script = load("res://data/quests_ch2.gd")
	var q_src := q_script.source_code
	for f in [Data.FLAG_FOUND_LAMP, Data.FLAG_LAMP_LIT]:
		assert_true(q_src.contains(f), "%s is read by data/quests_ch2.gd" % f)
	var orchard_step: Dictionary = {}
	for st in QuestsCh2.STEPS:
		if String(st["id"]) == "ch2_orchard":
			orchard_step = st
	assert_eq(String(orchard_step["objectives"][0]["flag"]), Data.FLAG_LAMP_LIT, "the orchard step completes on the lamp flag only")
	var goals := {}
	for g in Optional.GOALS:
		goals[String(g["id"])] = g
	var gk: Dictionary = goals["opt_groundskeeper"]
	var flags_seen: Array = []
	for o in gk["objectives"]:
		if o.has("flags"):
			flags_seen.append_array(o["flags"])
		if o.has("flag"):
			flags_seen.append(o["flag"])
	for f2 in [Data.FLAG_NOTE_1, Data.FLAG_NOTE_2, Data.FLAG_LIGHT_PLACED]:
		assert_true(flags_seen.has(f2), "%s is an objective of opt_groundskeeper" % f2)
	assert_eq(String(goals["opt_hat_too_large"]["objectives"][0]["flag"]), Data.FLAG_HAT)
	# The only content bundle this module grants.
	var b: Dictionary = Sources.REWARDS[Data.REWARD_PATTERN]
	assert_eq(String(b["by"]), "content", "rw_ch2_candleyard_pattern is a content bundle")
	assert_true(String(b["who"]).contains("Candleyard"), "it belongs to the Candleyard")
	# The quest-layer / optional-log rewards are never ours to grant.
	for rid in ["rw_ch2_orchard", "rw_opt_groundskeeper", "rw_opt_hat_too_large"]:
		assert_ne(String(ItemDB.reward_bundle(rid).get("by", "")), "content", "%s is paid by a log" % rid)
	# Our own new flags use the namespaces of spec §2.
	for f3 in [Data.FLAG_IRRIGATED, Data.FLAG_MIMICS_CLEARED, Data.FLAG_JUNCTION_GARDEN, Data.FLAG_GATE_OPEN, Data.FLAG_SEED_PLANTED,
			Data.FLAG_GARDEN_NOTE, Data.FLAG_MOMENT_SEEN, Data.FLAG_MOMENT_TURNED, Data.FLAG_MOMENT_TWITCH, Data.FLAG_CHIMES_FOUND,
			Data.FLAG_CHIMES_DONE, Data.FLAG_BENCH_RESTED]:
		assert_true(f3.begins_with("ch2_") or f3.begins_with("hr_"), "%s is namespaced" % f3)
	assert_true(Data.REWARD_CHIMES.begins_with("rw_"), "the chime reward id uses the ledger namespace")
	# The chime pouch fallback only gives ordinary renewable things (never a key item or a seal).
	for it in Data.CHIME_REWARD_FALLBACK["items"]:
		assert_true(ItemDB.has_item(String(it)), "%s exists" % it)
		assert_false(ItemDB.is_quest_item(String(it)), "%s is not a quest item" % it)


func test_footprints_cover_every_build() -> void:
	for district in [Data.ORCHARD, Data.POOLS, Data.CANDLEYARD]:
		var fps: Array = Data.footprints_for(district)
		assert_true(fps.size() >= 1, "%s has footprints" % district)
		for f in fps:
			assert_true(f[0] is Vector2 and float(f[1]) > 0.0, "footprint shape")
			assert_true((f[0] as Vector2).distance_to(Data.center_of(district)) <= Data.radius_of(district) + 1.0, "%s footprint centre inside the landmark" % district)
		for p in _points(district):
			var inside := false
			for f2 in fps:
				if (p[0] as Vector2).distance_to(f2[0]) <= float(f2[1]):
					inside = true
			assert_true(inside, "%s: %s at %s is covered by a footprint (vegetation stays clear)" % [district, p[2], str(p[0])])
	assert_eq(Orchard.footprints(), Data.ORCHARD_FOOTPRINTS)
	assert_eq(Pools.footprints(), Data.POOLS_FOOTPRINTS)
	assert_eq(Candleyard.footprints(), Data.CANDLEYARD_FOOTPRINTS)
	# footprints() hands out copies (the region may edit its list).
	var f3: Array = Orchard.footprints()
	f3.clear()
	assert_true(Orchard.footprints().size() > 0, "footprints() returns a copy")


func test_candleyard_wall_has_wide_gates_toward_the_roads() -> void:
	var gate_w := 2.0 * Data.WALL_RADIUS * sin(deg_to_rad(Data.WALL_GATE_HALF_DEG))
	assert_true(gate_w >= 1.6 + 2.0, "gates are wide (%.1f m)" % gate_w)
	for e in Data.CANDLEYARD_ENTRIES:
		var best := INF
		for g in Data.WALL_GATES:
			best = minf(best, (e as Vector2).distance_to(Data.gate_point(float(g))))
		assert_true(best < 3.0, "entry %s arrives at a gate (%.1f m)" % [str(e), best])
	# The region's roads end at our entries.
	var reach_script: Script = load("res://data/hallowmere_layout.gd")
	var roads: Dictionary = reach_script.get_script_constant_map().get("PATHS", {})
	if not roads.is_empty():
		var ends: Array = []
		for r in roads:
			var pts: Array = roads[r]
			ends.append(pts[0])
			ends.append(pts[pts.size() - 1])
		for e2 in Data.CANDLEYARD_ENTRIES + Data.POOLS_ENTRIES:
			var near := false
			for en in ends:
				near = near or (e2 as Vector2).distance_to(en) < 2.5
			assert_true(near, "a region road reaches entry %s" % str(e2))
	# The activities sit inside the wall; the bench sits just outside the east gate.
	for p in [Data.SHED["pos"], Data.NOTE_2, Data.MARKER, Data.NOOK, Data.HAT["pos"], Data.PATTERN_SPOT]:
		assert_true((p as Vector2).distance_to(Data.CANDLEYARD_CENTER) < Data.WALL_RADIUS - 1.5, "%s inside the wall" % str(p))
	assert_true(Data.BENCH["pos"].distance_to(Data.CANDLEYARD_CENTER) > Data.WALL_RADIUS, "the bench is at the edge, outside the wall")
	assert_true(Data.in_wall_gate(Data.WALL_GATES[0]) and not Data.in_wall_gate(Data.WALL_GATES[0] + 20.0), "gate test")


func test_chime_trail_needs_no_precision() -> void:
	for i in range(Data.CHIMES.size() - 1):
		assert_true((Data.CHIMES[i] as Vector2).distance_to(Data.CHIMES[i + 1]) <= 12.0, "chime %d -> %d is a short hop" % [i, i + 1])
	assert_true((Data.CHIMES[Data.CHIMES.size() - 1] as Vector2).distance_to(Data.POUCH) <= 6.0, "the last chime is close to the pouch")
	for c in Data.CHIMES + [Data.POUCH]:
		for pd in Data.POOL_DISCS:
			assert_true((c as Vector2).distance_to(pd[0]) > float(pd[1]) + 0.6, "%s stands on dry ground" % str(c))
	assert_true(Data.CHIME_REACH >= 2.0, "a generous ring distance")
	assert_true((Data.POOLS_ENTRIES[0] as Vector2).distance_to(Data.CHIMES[0]) < 4.0, "the first glinting chime greets her at the entry")
