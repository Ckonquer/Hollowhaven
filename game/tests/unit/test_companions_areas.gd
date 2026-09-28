extends "res://tests/unit/test_companions_fixture.gd"
## Companion spawning per area class (spec §9): outdoor (surface, hallowmere_reach) and interior areas take the
## follower along (Mochi too), underground areas keep Mochi's refusal unless she has courage and send her to the
## doorstep of THAT area (never the surface mine threshold for the Reach), home companions stay at the Haven,
## waiting companions reappear where they were left and reunite when Krystal comes back up through the doorstep.

var defs: Dictionary = {}


func before_each() -> void:
	await super.before_each()
	defs = {}
	for id in ItemDB.creature_ids():
		defs[id] = ItemDB.creature(id)


func _rec(befriended: bool, assignment: String, wait_area: String = "", wait_pos: Variant = null) -> Dictionary:
	return {"befriended": befriended, "bond_xp": 0, "assignment": assignment, "wait_area": wait_area,
		"wait_pos": wait_pos, "last_pet_day": -1, "last_gift_day": -1, "last_fed_day": -1}


func _modes(plan: Dictionary) -> Dictionary:
	var out := {}
	for sp in plan["spawns"]:
		out[sp["id"]] = sp["mode"]
	return out


func _change_for(plan: Dictionary, id: String) -> Dictionary:
	for ch in plan["changes"]:
		if ch["id"] == id:
			return ch
	return {}


func test_area_classes() -> void:
	for a in ["surface", "arena"]:
		assert_eq(Logic.area_class(a), "haven", a)
	assert_eq(Logic.area_class("hallowmere_reach"), "outdoor")
	assert_true(Logic.is_outdoor_area("hallowmere_reach") and Logic.is_outdoor_area("surface"))
	for a in ["moonveil_manor", "echo_trial"]:
		assert_eq(Logic.area_class(a), "interior", a)
	for a in ["below", "tobin_annex", "hushed_works"]:
		assert_eq(Logic.area_class(a), "underground", a)
		assert_true(Logic.is_underground_area(a))
	assert_false(Logic.is_surface_area("hallowmere_reach"), "the Reach has no homes or wild spots")


func test_reach_takes_mochi_along_and_never_sends_her_to_the_mine() -> void:
	var th := Vector3(50, 0, -66)
	var recs := {"mochi": _rec(true, "follow"), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("hallowmere_reach", recs, "mochi", "waygate_arrival", defs, true, th)
	var m := _modes(plan)
	assert_eq(m, {"mochi": "follow"}, "only the follower: Mochi comes along (home friends stay at the Haven)")
	assert_true(plan["changes"].is_empty(), "no one is sent anywhere (least of all to the mine threshold)")
	# Interiors behave the same.
	for a in ["moonveil_manor", "echo_trial"]:
		var p2 := Logic.plan_spawns(a, recs, "mochi", "manor_entry", defs, true, th)
		assert_eq(_modes(p2), {"mochi": "follow"}, a)
		assert_true(p2["changes"].is_empty(), a)


func test_waiting_in_the_reach_stays_there() -> void:
	var recs := {"mochi": _rec(true, "home"), "pebble": _rec(true, "follow"),
		"lumi": _rec(true, "wait", "hallowmere_reach", [10.0, 0.0, 40.0])}
	var plan := Logic.plan_spawns("hallowmere_reach", recs, "pebble", "commons_arch", defs, true, null)
	var m := _modes(plan)
	assert_eq(m.get("lumi"), "wait", "Lumi is still where Krystal left her")
	assert_eq(m.get("pebble"), "follow")
	assert_false(m.has("mochi"), "at home in the Haven")
	# ...and back on the surface a companion waiting in the Reach found its way home.
	var plan2 := Logic.plan_spawns("surface", recs, "pebble", "waygate", defs, true, null)
	assert_eq(_change_for(plan2, "lumi").get("assignment"), "home")


func test_underground_doorsteps() -> void:
	var th := Vector3(50, 0, -66)
	var recs := {"mochi": _rec(true, "follow"), "pebble": _rec(true, "home"), "lumi": _rec(true, "home")}
	# Tobin's annex opens at the mine mouth: the timid Mochi waits at the same outside threshold.
	var annex := Logic.plan_spawns("tobin_annex", recs, "mochi", "annex_entry", defs, true, th)
	assert_true(annex["spawns"].is_empty())
	assert_eq(_change_for(annex, "mochi").get("wait_area"), "surface")
	assert_eq(_change_for(annex, "mochi").get("wait_pos"), th)
	# The Hushed Works are entered from the Reach: she waits at the Bellhouse stair there.
	var works := Logic.plan_spawns("hushed_works", recs, "mochi", "service_landing", defs, true, th)
	var ch := _change_for(works, "mochi")
	assert_eq(ch.get("assignment"), "wait")
	assert_eq(ch.get("wait_area"), "hallowmere_reach", "never the surface")
	var wp: Variant = ch.get("wait_pos")
	assert_true(wp is Vector3 and Vector2((wp as Vector3).x - 72.0, (wp as Vector3).z + 72.0).length() < 0.01, "at the Bellhouse stair: %s" % str(wp))
	# A registered position of that stair wins over the layout point.
	var works2 := Logic.plan_spawns("hushed_works", recs, "mochi", "service_landing", defs, true, th, {"bellhouse_stair": Vector3(70, 3, -71)})
	assert_eq(_change_for(works2, "mochi").get("wait_pos"), Vector3(70, 3, -71))
	# Down through the refuge shortcut hatch instead: she waits at THAT hatch, where Krystal left her (not 90 m
	# away at the Bellhouse).
	var works3 := Logic.plan_spawns("hushed_works", recs, "mochi", "refuge", defs, true, th)
	var ch3 := _change_for(works3, "mochi")
	assert_eq(ch3.get("wait_area"), "hallowmere_reach")
	var wp3: Variant = ch3.get("wait_pos")
	assert_true(wp3 is Vector3 and Vector2((wp3 as Vector3).x - 20.0, (wp3 as Vector3).z - 4.0).length() < 0.01, "at the refuge exit: %s" % str(wp3))
	var works4 := Logic.plan_spawns("hushed_works", recs, "mochi", "refuge", defs, true, th, {"refuge_exit": Vector3(21, 2, 5)})
	assert_eq(_change_for(works4, "mochi").get("wait_pos"), Vector3(21, 2, 5), "its registered position wins")
	assert_eq(Logic.doorstep_spawns_in("hallowmere_reach"), ["bellhouse_stair", "refuge_exit"])
	assert_eq(Logic.doorstep_spawns_in("surface"), [], "the mine threshold is not a Reach-style doorstep")
	# Brave companions (and Mochi with courage) simply follow.
	var brave := defs.duplicate(true)
	brave["mochi"]["enters_below"] = true
	for a in ["below", "tobin_annex", "hushed_works"]:
		assert_eq(_modes(Logic.plan_spawns(a, recs, "mochi", "x", brave, true, th)), {"mochi": "follow"}, a)
	recs["mochi"]["assignment"] = "home"
	recs["lumi"]["assignment"] = "follow"
	assert_eq(_modes(Logic.plan_spawns("hushed_works", recs, "lumi", "service_landing", defs, true, th)), {"lumi": "follow"})


func test_reunite_at_doorsteps() -> void:
	var th := Vector3(50, 0, -66)
	# Back up through Tobin's side door: Mochi at the threshold rejoins.
	var recs := {"mochi": _rec(true, "wait", "surface", [50.5, 0.0, -65.5]), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "", "annex_door", defs, true, th)
	assert_eq(_modes(plan)["mochi"], "reunite")
	# Back up the Bellhouse stair: Mochi waiting there rejoins.
	var recs2 := {"mochi": _rec(true, "wait", "hallowmere_reach", [72.0, 0.0, -72.0]), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	var p2 := Logic.plan_spawns("hallowmere_reach", recs2, "", "bellhouse_stair", defs, true, null)
	assert_eq(_modes(p2).get("mochi"), "reunite", "bounces over at the stair")
	assert_eq(_change_for(p2, "mochi").get("assignment"), "follow")
	# Arriving anywhere else in the Reach: she keeps waiting at the stair.
	assert_eq(_modes(Logic.plan_spawns("hallowmere_reach", recs2, "", "commons_arch", defs, true, null)).get("mochi"), "wait")
	# Waiting at the refuge exit (Krystal went down the shortcut hatch): back up that way, she rejoins.
	var recs4 := {"mochi": _rec(true, "wait", "hallowmere_reach", [20.2, 0.0, 4.1]), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	assert_eq(_modes(Logic.plan_spawns("hallowmere_reach", recs4, "", "refuge_exit", defs, true, null)).get("mochi"), "reunite")
	assert_eq(_modes(Logic.plan_spawns("hallowmere_reach", recs4, "", "bellhouse_stair", defs, true, null)).get("mochi"), "wait",
		"the other door is too far from where she waits")
	# Someone else follows: Mochi heads home to the Haven.
	recs2["pebble"]["assignment"] = "follow"
	var p3 := Logic.plan_spawns("hallowmere_reach", recs2, "pebble", "bellhouse_stair", defs, true, null)
	assert_false(_modes(p3).has("mochi"))
	assert_eq(_change_for(p3, "mochi").get("assignment"), "home")


func test_spawner_in_the_reach() -> void:
	var area: Node3D = AreaBase.new()
	add_child(area)
	nodes.append(area)
	area.register_spawn("bellhouse_stair", Transform3D(Basis.IDENTITY, Vector3(0, 0.05, -14)))
	_befriend("mochi", "follow")
	_befriend("pebble", "home")
	player.global_position = Vector3(0, 0.05, 6)
	var out: Dictionary = Spawner.spawn_for_area(area, "hallowmere_reach", player)
	for id in out:
		nodes.append(out[id])
		Game.companion_nodes[id] = out[id]
	assert_eq(out.keys(), ["mochi"], "Mochi comes along; Pebble stays home")
	assert_eq(GameState.active_companion, "mochi", "and keeps following")
	var m: Node3D = out["mochi"]
	assert_true(m.global_position.distance_to(player.global_position) < 4.0, "beside Krystal")
	assert_eq(m.get("threshold_pos"), Vector3(0, 0.05, -14), "the Bellhouse stair is this area's threshold")
	# Walking to the stair before it is revealed: nothing happens.
	Game.area_id = "hallowmere_reach"
	player.global_position = Vector3(0, 0.05, -8)
	await wait_physics(4)
	assert_ne(m.get_state(), "refuse", "no refusal while the stair is still hidden")
	player.global_position = Vector3(0, 0.05, 20)
	await wait_physics(4)
	GameState.set_flag("ch2_lamps_linked", true)
	player.global_position = Vector3(0, 0.05, -8)
	await wait_physics(4)
	assert_eq(m.get_state(), "refuse", "the timid Mochi stops at the revealed stair")
	assert_true(_said_contains("stair"), "with its own line: %s" % str(said))
	# Sent home from the Reach: it poofs off to the Haven (nobody lives out here).
	m.call("_clear_override")
	m.set("_last_command_ms", -100000)
	m.command("home")
	assert_eq(m.get_state(), "leaving")
