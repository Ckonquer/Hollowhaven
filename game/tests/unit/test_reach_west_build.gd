extends "res://tests/unit/test_reach_west_fixture.gd"
## Reach west districts (module C2): building on a flat and on a sloped host - build time, deterministic ids,
## renewable harvest nodes, lights budget, content following area.height_at.


func test_districts_build_fast_and_register_their_content() -> void:
	var h: Node3D = await flat_host()
	var t0 := Time.get_ticks_msec()
	var d := await build_all(h)
	var total := Time.get_ticks_msec() - t0
	var o: Node3D = d["orchard"]
	var p: Node3D = d["pools"]
	var c: Node3D = d["candleyard"]
	assert_not_null(o, "orchard built")
	assert_not_null(p, "pools built")
	assert_not_null(c, "candleyard built")
	print("  reach_west build ms: orchard %d, pools %d, candleyard %d (total incl. 2 physics frames %d)" % [o.build_ms, p.build_ms, c.build_ms, total])
	assert_true(o.build_ms < 450, "orchard builds quickly (%d ms)" % o.build_ms)
	assert_true(p.build_ms < 300, "pools build quickly (%d ms)" % p.build_ms)
	assert_true(c.build_ms < 450, "candleyard builds quickly (%d ms)" % c.build_ms)
	assert_true(o.build_ms + p.build_ms + c.build_ms < 1000, "all three districts well under the 1.5 s load budget")
	# The district roots stay at the origin (content is placed in world coordinates).
	for root in [o, p, c]:
		assert_eq((root as Node3D).transform, Transform3D.IDENTITY, "%s at the origin" % root.name)
	# Building twice on the same area is a no-op.
	assert_eq(Orchard.build_district(h), o, "build_district is idempotent")
	# Every harvest node of the data exists once, with its stable id, on the ground.
	var all_nodes: Dictionary = {}
	for root in [o, p, c]:
		for id in root.nodes:
			assert_false(all_nodes.has(id), "node %s built once" % id)
			all_nodes[id] = root.nodes[id]
	assert_eq(all_nodes.size(), Data.NODES.size(), "every harvest node built")
	for e in Data.NODES:
		var n: Node3D = all_nodes.get(String(e["id"]))
		assert_not_null(n, "node %s" % e["id"])
		if n == null:
			continue
		assert_eq(String(n.get("node_id")), String(e["id"]), "stable node id")
		assert_eq(String(n.get("kind")), String(e["kind"]), "node %s kind" % e["id"])
		var pos: Vector2 = e["pos"]
		assert_almost(n.global_position.x, pos.x, 0.01, "node %s x" % e["id"])
		assert_almost(n.global_position.y, height(h, pos), 0.01, "node %s on the ground" % e["id"])


func test_layout_is_deterministic_across_builds() -> void:
	var sig: Array = []
	for run in 2:
		var h: Node3D = await flat_host()
		var d := await build_all(h)
		var parts: Array = []
		for key in ["orchard", "pools", "candleyard"]:
			var root: Node3D = d[key]
			for n in root.find_children("*", "", true, false):
				# auto-generated names ("@MeshInstance3D@123") differ per run: use the class + the named ancestor path
				var s := "%s/%s" % [String(root.get_path_to(n.get_parent())).split("@")[0], n.get_class() if String(n.name).begins_with("@") else String(n.name)]
				if n is Node3D:
					var gp := (n as Node3D).global_position
					s += "|%.2f,%.2f,%.2f" % [gp.x, gp.y, gp.z]
				if n is MultiMeshInstance3D:
					s += "|mm%d" % (n as MultiMeshInstance3D).multimesh.instance_count
				parts.append(s)
		parts.sort()
		sig.append("\n".join(parts))
		for hh in _hosts:
			hh.queue_free()
		_hosts.clear()
		await wait_frames(2)
	assert_eq(sig[0].length() > 1000, true, "a real layout was captured")
	if sig[0] != sig[1]:
		var a: PackedStringArray = String(sig[0]).split("
")
		var b: PackedStringArray = String(sig[1]).split("
")
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				fail("first difference: %s <> %s" % [a[i], b[i]])
				break
	assert_true(sig[0] == sig[1], "two builds produce the same node tree, names and positions")


func test_harvest_nodes_are_renewable() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var seen_kinds := {}
	for key in ["orchard", "pools", "candleyard"]:
		var root: Node3D = d[key]
		for id in root.nodes:
			var n: Node3D = root.nodes[id]
			var kind := String(n.get("kind"))
			var src: Dictionary = ItemDB.node_kind(kind)
			assert_false(src.is_empty(), "%s: kind %s is a data/sources.gd node kind" % [id, kind])
			assert_true(float(n.get("respawn_minutes")) > 0.0, "%s respawns" % id)
			assert_true(n.is_in_group("harvestable"), "%s harvestable" % id)
			assert_true(n.is_in_group("interactable"), "%s (hand) is an interactable" % id)
			var info: Dictionary = n.get_interaction(null)
			assert_true(bool(info.get("enabled", false)), "%s offers a prompt (%s)" % [id, info.get("text", "")])
			if seen_kinds.has(kind):
				continue
			seen_kinds[kind] = true
			# Harvest one of each kind: items arrive, the node depletes with a respawn time, then comes back.
			var drop_item := String((src["drops"] as Array)[0]["item"])
			var before := GameState.count_item(drop_item)
			n.harvest_hit(null, "")
			assert_true(GameState.count_item(drop_item) > before, "%s gives %s" % [id, drop_item])
			assert_true(GameState.is_depleted(id), "%s depleted after harvest" % id)
			assert_true(float(GameState.depleted.get(id, -1.0)) > 0.0, "%s has a respawn time (renewable)" % id)
			GameState.total_minutes += float(src["respawn_minutes"]) + 1.0
			assert_false(GameState.is_depleted(id), "%s regrows after its respawn time" % id)
	for k in Data.NODE_TOKENS:
		assert_true(seen_kinds.has(k), "kind %s placed" % k)


func test_lights_are_few_and_unshadowed() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var total := 0
	for key in ["orchard", "pools", "candleyard"]:
		for l in (d[key] as Node).find_children("*", "Light3D", true, false):
			total += 1
			assert_false((l as Light3D).shadow_enabled, "%s casts no shadow (shadowed-light budget stays with the region)" % l.name)
	assert_true(total <= 8, "at most 8 lights in the three districts (%d)" % total)


func test_content_follows_a_sloped_ground() -> void:
	var h: Node3D = await slope_host()
	var d := await build_all(h)
	for key in ["orchard", "pools", "candleyard"]:
		var root: Node3D = d[key]
		for id in root.nodes:
			var n: Node3D = root.nodes[id]
			var hy := height(h, Vector2(n.global_position.x, n.global_position.z))
			assert_almost(n.global_position.y, hy, 0.02, "%s stands on the sloped ground" % id)
	# Interactables sit on the ground too (their stand spots are on the collider).
	for key2 in ["orchard", "pools", "candleyard"]:
		for it in interactables_under(d[key2]):
			var gp: Vector3 = (it as Node3D).global_position
			var g: Variant = ground_hit(h, Vector2(gp.x, gp.z))
			assert_not_null(g, "%s has ground under it" % it.name)
	# The spawners, when present, stand on the ground.
	B.availability_override = {"patchwalker": true, "hollow_drudge": true}
	var h2: Node3D = await slope_host()
	var d2 := await build_all(h2)
	for sid in ["hr_sp_orchard_patchwalkers"]:
		var sp: Node3D = (d2["orchard"] as Node).spawners[sid]
		assert_not_null(sp, "spawner %s built when its enemy exists" % sid)
		if sp != null:
			var pos: Vector2 = Data.SPAWNERS[sid]["pos"]
			assert_almost(sp.global_position.y, height(h2, pos) + 0.05, 0.02, "%s on the ground" % sid)


func test_script_load_cost_is_small() -> void:
	# Compiling our district scripts and everything they preload (as the region's loader does on first load).
	var total := 0
	for path in ["res://src/world/reach/districts/orchard.gd", "res://src/world/reach/districts/pools.gd",
			"res://src/world/reach/districts/candleyard.gd"]:
		var t0 := Time.get_ticks_usec()
		var s: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var us := Time.get_ticks_usec() - t0
		total += us
		assert_true(s is Script and (s as Script).can_instantiate(), "%s compiles" % path)
	print("  reach_west scripts compile (uncached, deep): %.1f ms" % (float(total) / 1000.0))
	assert_true(total < 400000, "compiling our scripts stays small (%.0f ms)" % (float(total) / 1000.0))


func test_sap_stumps_stay_standing_when_tapped() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var stumps := 0
	for key in ["orchard", "candleyard"]:
		var root: Node3D = d[key]
		var decor := 0
		for mm in root.find_children("SapStumps_*", "MultiMeshInstance3D", false, false):
			decor += (mm as MultiMeshInstance3D).multimesh.instance_count
		var mine := 0
		for e in Data.nodes_in(Data.ORCHARD if key == "orchard" else Data.CANDLEYARD):
			if String(e["kind"]) != "sap_stump":
				continue
			mine += 1
			stumps += 1
			var id := String(e["id"])
			var n: Node3D = root.nodes[id]
			var pos: Vector2 = e["pos"]
			assert_eq(String(n.get_interaction(null).get("text", "")).begins_with("Tap"), true, "%s: 'Tap' prompt (%s)" % [id, n.get_interaction(null).get("text", "")])
			assert_false(capsule_clear(h, pos), "%s: the stump is solid" % id)
			var before := GameState.count_item("resin")
			n.harvest_hit(null, "")
			assert_true(GameState.count_item("resin") > before, "%s gives resin" % id)
			assert_true(GameState.is_depleted(id), "%s: the pail is empty until the sap gathers again" % id)
			assert_false(capsule_clear(h, pos), "%s: the tapped stump still stands (only the resin hides)" % id)
			assert_true(capsule_clear(h, pos + Vector2(0, 1.3)), "%s: room to stand beside it" % id)
		assert_eq(decor, mine, "%s: one stump decor per sap stump node" % key)
	assert_true(stumps >= int(ItemDB.node_kind("sap_stump")["min_count"]["hallowmere_reach"]), "the Reach's guaranteed sap stumps")
	# Wild sunflax: hand-picked golden stalks, back after its respawn time.
	var sf: Node3D = (d["orchard"] as Node3D).nodes["hr_sunflax_0"]
	assert_eq(String(sf.get("kind")), "sunflax_patch")
	var b2 := GameState.count_item("sunflax")
	sf.harvest_hit(null, "")
	assert_true(GameState.count_item("sunflax") > b2, "sunflax picked")
	GameState.total_minutes += float(ItemDB.node_kind("sunflax_patch")["respawn_minutes"]) + 1.0
	assert_false(GameState.is_depleted("hr_sunflax_0"), "and it grows back")
