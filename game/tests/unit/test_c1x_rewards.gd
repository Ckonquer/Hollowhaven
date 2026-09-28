extends "res://tests/test_case.gd"
## Module B7: rewards are paid exactly once through the ledger and the optional-goal objective flags are set by
## the right events. The Tailor's Cache (rw_c1x_tailor_cache -> c1x_tailor_cache), the meadow patch's first
## harvest (c1x_found_new_crops + rw_c1x_gardener), Bramblewatch (c1x_bramblewatch_found on entry; rw_c1x_elder ->
## c1x_elder_defeated when the Elder's spawner clears), and the renewable nodes' data-driven drops. Log rewards
## (rw_opt_*) are never granted by the module itself: the optional log pays them.

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")
const Tailor := preload("res://src/world/surface/c1x/tailor_cache.gd")
const Meadow := preload("res://src/world/surface/c1x/meadow_patch.gd")
const Stumps := preload("res://src/world/surface/c1x/sap_stumps.gd")
const Bramble := preload("res://src/world/surface/c1x/bramblewatch.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const SpawnerScript := preload("res://src/enemies/enemy_spawner.gd")

var _area: Node3D = null
var _harvests: Array = []


func before_each() -> void:
	fresh_state()
	_harvests.clear()


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	if Events.harvested.is_connected(_on_harvested):
		Events.harvested.disconnect(_on_harvested)
	await wait_frames(2)


func _on_harvested(kind: String, item: String, n: int, _pos: Vector3) -> void:
	_harvests.append([kind, item, n])


## A flat stand-in area (no terrain): big floor on layer 1.
func _flat_area() -> Node3D:
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)
	return _area


func _node_by_id(root: Node, id: String) -> Node:
	for n in root.find_children("*", "Node3D", true, false):
		var v: Variant = n.get("node_id")
		if v is String and String(v) == id:
			return n
	return null


# --- The Tailor's Cache -------------------------------------------------------------------------------------

func test_tailor_cache_opens_once_and_unlocks_the_loom() -> void:
	var area := _flat_area()
	Tailor.build(area)
	await wait_frames(1)
	var cache: Node = get_tree().get_first_node_in_group("c1x_tailor_cache")
	assert_not_null(cache, "cache built")
	if cache == null:
		return
	assert_false(bool(cache.is_open()), "closed in a new game")
	assert_eq(String(cache.get_interaction(null).get("text", "")), "Open the Tailor's Cache")
	var seeds_before := GameState.count_item("sunflax_seeds")
	cache.interact(null)
	assert_true(GameState.has_reward(L.REWARD_TAILOR), "rw_c1x_tailor_cache recorded in the ledger")
	assert_true(bool(GameState.get_flag(L.FLAG_TAILOR_CACHE)), "c1x_tailor_cache set (Loom + ribbon bow unlock)")
	var bundle: Dictionary = ItemDB.reward_bundle(L.REWARD_TAILOR)
	assert_eq(GameState.count_item("sunflax_seeds") - seeds_before, int(bundle["items"]["sunflax_seeds"]), "the bundle's items, from data")
	assert_true(bool(cache.is_open()), "open now")
	# Again (interact, open(), a rebuilt cache after a reload): never a second payment.
	cache.set("_busy", false)
	cache.interact(null)
	assert_false(bool(cache.open()), "open() pays only once")
	Tailor.build(area)
	assert_eq(GameState.count_item("sunflax_seeds") - seeds_before, int(bundle["items"]["sunflax_seeds"]), "never paid twice")
	var ledger_ids := 0
	for k in GameState.ledger:
		if String(k) == L.REWARD_TAILOR:
			ledger_ids += 1
	assert_eq(ledger_ids, 1, "one ledger entry")
	assert_true(ItemDB.recipe("loom").get("unlock", "") == L.FLAG_TAILOR_CACHE, "the Loom recipe is gated by this flag")


func test_opened_cache_stays_open_after_a_reload() -> void:
	var area := _flat_area()
	GameState.grant_once(L.REWARD_TAILOR, {}, [L.FLAG_TAILOR_CACHE])
	var c := Tailor.Cache.new()
	area.add_child(c)
	assert_true(bool(c.is_open()), "a save with the ledger entry shows an open cache")
	assert_almost(float(c.lid.rotation.x), float(Tailor.Cache.OPEN_ANGLE), 0.001, "lid open on load (no animation)")
	assert_eq(String(c.get_interaction(null).get("text", "")), "Look in the Tailor's Cache")


func test_tailors_cache_goal_completes_and_the_log_pays_its_own_reward() -> void:
	var area := _flat_area()
	Tailor.build(area)
	var cache: Node = get_tree().get_first_node_in_group("c1x_tailor_cache")
	cache.open()
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_tailors_cache"), "opt_tailors_cache completes on the flag")
	assert_true(GameState.has_reward("rw_opt_tailors_cache"), "the optional log paid rw_opt_tailors_cache")
	assert_eq(GameState.count_item("woven_cloth"), 2, "woven cloth from the goal reward (paid by the log, once)")
	GameState.optional_goals.evaluate()
	assert_eq(GameState.count_item("woven_cloth"), 2, "still once")


func test_content_grants_only_content_bundles() -> void:
	assert_false(Common.grant_content("rw_opt_tailors_cache"), "log rewards are never granted by the module")
	assert_false(GameState.has_reward("rw_opt_tailors_cache"), "ledger untouched")
	assert_false(Common.grant_content("rw_no_such_reward_c1x"), "unknown ids are refused")
	for rid in [L.REWARD_TAILOR, L.REWARD_ELDER, L.REWARD_GARDENER]:
		var b: Dictionary = ItemDB.reward_bundle(rid)
		assert_eq(String(b.get("by", "")), "content", "%s is a content bundle" % rid)
	assert_true(Common.grant_content(L.REWARD_ELDER), "first grant")
	assert_false(Common.grant_content(L.REWARD_ELDER), "second grant refused")


# --- A Gardener's Afternoon -------------------------------------------------------------------------------

func test_first_meadow_harvest_sets_the_flag_and_pays_the_packet_once() -> void:
	var area := _flat_area()
	Meadow.build(area)
	await wait_frames(1)
	Events.harvested.connect(_on_harvested)
	var s0: Node = _node_by_id(area, "c1x_sunflax_0")
	assert_not_null(s0, "sunflax node built")
	if s0 == null:
		return
	assert_false(bool(GameState.get_flag(L.FLAG_FOUND_NEW_CROPS)), "not found yet")
	var packet: Dictionary = ItemDB.reward_bundle(L.REWARD_GARDENER)
	var seeds0 := GameState.count_item("sunflax_seeds")
	var rose_seeds0 := GameState.count_item("roseberry_seeds")
	assert_eq(String(s0.get_interaction(null).get("text", "")), "Gather Wild Sunflax")
	s0.harvest_hit(null, "")
	assert_true(bool(GameState.get_flag(L.FLAG_FOUND_NEW_CROPS)), "c1x_found_new_crops set by the first harvest")
	assert_true(GameState.has_reward(L.REWARD_GARDENER), "rw_c1x_gardener granted")
	assert_true(GameState.count_item("sunflax") >= 2, "wild sunflax from the data drops")
	assert_true(GameState.count_item("roseberry_seeds") - rose_seeds0 >= int(packet["items"]["roseberry_seeds"]), "packet roseberry seeds")
	assert_true(GameState.count_item("sunflax_seeds") - seeds0 >= int(packet["items"]["sunflax_seeds"]), "packet sunflax seeds")
	assert_true(GameState.is_depleted("c1x_sunflax_0"), "depletion persisted under its stable id")
	assert_eq(String(s0.get_interaction(null).get("text", "")), "Wild Sunflax (regrowing)", "says it regrows")
	var kinds: Array = _harvests.map(func(h: Array) -> String: return String(h[0]))
	assert_true(kinds.has(L.SUNFLAX_KIND), "Events.harvested reports sunflax_patch (%s)" % str(kinds))
	# A second harvest (another plant, a roseberry bush) never pays the packet again.
	var ledger_size := GameState.ledger.size()
	var r0: Node = _node_by_id(area, "c1x_roseberry_0")
	r0.harvest_hit(null, "")
	assert_true(GameState.count_item("roseberries") >= 2, "roseberries from the bush")
	assert_eq(GameState.ledger.size(), ledger_size, "no further ledger entry")
	var patch: Node = get_tree().get_first_node_in_group("c1x_meadow_patch")
	assert_false(bool(patch.mark_found()), "mark_found pays only once")
	kinds = _harvests.map(func(h: Array) -> String: return String(h[0]))
	assert_true(kinds.has(L.ROSEBERRY_KIND), "Events.harvested reports roseberry_bush")
	# The gardener goal needs a home harvest too (farming module): it does not complete from this alone.
	GameState.optional_goals.evaluate()
	assert_false(GameState.optional_goals.is_done("opt_gardeners_afternoon"), "the goal also needs c1x_grew_new_crop")


func test_meadow_nodes_regrow_from_data_respawn_time() -> void:
	var area := _flat_area()
	Meadow.build(area)
	await wait_frames(1)
	var s1: Node = _node_by_id(area, "c1x_sunflax_1")
	s1.harvest_hit(null, "")
	assert_true(bool(s1.get("depleted")), "picked")
	GameState.total_minutes += float(ItemDB.node_kind(L.SUNFLAX_KIND)["respawn_minutes"]) + 1.0
	assert_true(bool(s1.can_respawn_now()), "renewable: it can regrow after the data respawn time")
	s1.restore(false)
	assert_false(bool(s1.get("depleted")), "regrown")
	assert_true(s1.is_in_group("harvestable"), "harvestable again")


# --- Sap stumps ----------------------------------------------------------------------------------------------

func test_sap_stump_taps_resin_from_data_and_stays_solid() -> void:
	var area := _flat_area()
	Stumps.build(area)
	await wait_frames(1)
	Events.harvested.connect(_on_harvested)
	var def: Dictionary = ItemDB.node_kind(L.SAP_KIND)
	for s in L.SAP_STUMPS:
		var n: Node = _node_by_id(area, String(s["id"]))
		assert_not_null(n, "stump %s" % s["id"])
	var st: Node = _node_by_id(area, "c1x_resin_0")
	assert_eq(String(st.get_harvest_info()["tool"]), String(def["tool"]), "tool from data")
	assert_eq(int(st.get("hits")), int(def["hits"]), "hits from data")
	assert_eq(String(st.get_interaction(null).get("text", "")), "%s %s" % [def["verb"], def["name"]], "prompt from data")
	var resin0 := GameState.count_item("resin")
	for i in int(def["hits"]):
		st.harvest_hit(null, "")
	var got := GameState.count_item("resin") - resin0
	assert_true(got >= int(def["drops"][0]["min"]) and got <= int(def["drops"][0]["max"]), "resin %d within the data range" % got)
	assert_true(GameState.is_depleted("c1x_resin_0"), "depleted under its id")
	assert_eq(String(st.get_interaction(null).get("text", "")), "Sap Stump (the sap is still gathering)")
	var solid := st.get_node_or_null("Solid") as StaticBody3D
	assert_not_null(solid, "the stump is solid")
	if solid != null:
		assert_eq(solid.collision_layer, 1, "the emptied stump still blocks (it is a stump)")
	var kinds: Array = _harvests.map(func(h: Array) -> String: return String(h[0]))
	assert_true(kinds.has(L.SAP_KIND), "Events.harvested reports sap_stump")
	await wait_seconds(0.4)        # the resin shrinks away over 0.2 s
	var resin_mesh := (st.get_node("Visual") as Node3D).get_node_or_null("Berries") as Node3D
	assert_not_null(resin_mesh, "the resin is the node's harvestable part")
	if resin_mesh != null:
		assert_false(resin_mesh.visible, "the resin disappears until it refills")
	var stump_mesh := (st.get_node("Visual") as Node3D).get_node_or_null("Stump") as Node3D
	assert_true(stump_mesh != null and stump_mesh.visible, "the stump itself stays")


## The c1x nodes keep their DATA kind everywhere (harvest info too: Mochi's berry/grass forage filter must never
## send her to a sap stump) and run the unmodified resource_node harvest, gathering-mastery bonus yield included.
func test_c1x_nodes_keep_their_data_kind_and_the_gathering_bonus() -> void:
	var area := _flat_area()
	Stumps.build(area)
	Meadow.build(area)
	await wait_frames(1)
	for pair in [["c1x_resin_0", L.SAP_KIND], ["c1x_sunflax_0", L.SUNFLAX_KIND], ["c1x_roseberry_0", L.ROSEBERRY_KIND]]:
		var n: Node = _node_by_id(area, String(pair[0]))
		assert_eq(String(n.get_harvest_info()["kind"]), String(pair[1]), "%s: harvest info names the data kind" % pair[0])
		assert_eq(String(n.get("kind")), String(pair[1]), "%s: kind" % pair[0])
		assert_eq(String(n.get("base_kind")), "bush", "%s behaves like a bush (only the harvestable part hides)" % pair[0])
	const MasteryData := preload("res://data/mastery.gd")
	var st: Node = _node_by_id(area, "c1x_resin_0")
	var max_drop := int(ItemDB.node_kind(L.SAP_KIND)["drops"][0]["max"])
	var over := 0
	seed(11)
	for i in 120:
		GameState.mastery["gathering"] = int(MasteryData.RANK_XP[5])   # (a mastery listener may award xp)
		var b := GameState.count_item("resin")
		st.harvest_hit(null, "")
		if GameState.count_item("resin") - b > max_drop:
			over += 1
		st.restore(false)
	assert_true(over > 0 and over < 40, "the gathering bonus yield applies to c1x nodes (%d bonus harvests of 120)" % over)


# --- Bramblewatch -----------------------------------------------------------------------------------------

func test_bramblewatch_found_flag_is_set_once() -> void:
	var area := _flat_area()
	Bramble.build(area)
	await wait_frames(1)
	var watch: Node = get_tree().get_first_node_in_group("c1x_bramblewatch")
	assert_not_null(watch, "the watch node exists")
	assert_true(bool(watch.mark_found()), "first arrival")
	assert_true(bool(GameState.get_flag(L.FLAG_BRAMBLEWATCH_FOUND)), "c1x_bramblewatch_found")
	assert_false(bool(watch.mark_found()), "only once")
	var zone_ids: Array = (area.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
	assert_eq(zone_ids.count(L.BRAMBLEWATCH_ZONE), L.BRAMBLEWATCH_ZONES.size(), "the pocket's zone circles")


func test_elder_defeat_pays_rw_c1x_elder_once() -> void:
	var area := _flat_area()
	var arena := Bramble.Arena.new()
	area.add_child(arena)
	arena.global_position = Vector3(10, 0, 10)
	arena.build_slots(area)
	var sp: Node3D = SpawnerScript.new()
	sp.setup({"enemy": "brambling", "count": 1, "radius": 1.0, "respawn_minutes": -1.0, "spawner_id": String(L.ELDER_SPAWNER["id"])})
	area.add_child(sp)
	sp.set_process(false)
	arena.attach_spawner(sp)
	assert_eq(sp.get_meta("c1x_arena"), arena, "the Elder can reach its arena through the spawner")
	var resin0 := GameState.count_item("resin")
	sp._on_wave_cleared()      # the Elder's spawner clears (the Elder was defeated)
	assert_true(GameState.has_reward(L.REWARD_ELDER), "rw_c1x_elder granted")
	assert_true(bool(GameState.get_flag(L.FLAG_ELDER_DEFEATED)), "c1x_elder_defeated (sturdy planter + leaf cape unlock)")
	var bundle: Dictionary = ItemDB.reward_bundle(L.REWARD_ELDER)
	assert_eq(GameState.count_item("resin") - resin0, int(bundle["items"]["resin"]), "resin from the bundle")
	# The Elder script may also pay it (it does, on its own defeat) and the kill event arrives too: still once.
	Events.enemy_killed.emit("knotted_elder", Vector3(10, 0, 10))
	GameState.grant_once(L.REWARD_ELDER, bundle["items"], bundle["flags"])
	arena.repair_reward()
	assert_eq(GameState.count_item("resin") - resin0, int(bundle["items"]["resin"]), "never paid twice")
	GameState.set_flag("ruin_cleared", true)
	GameState.set_flag(L.FLAG_BRAMBLEWATCH_FOUND, true)
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_bramblewatch"), "opt_bramblewatch completes with both flags")
	assert_eq(GameState.count_item("sturdy_planter"), 1, "the goal's own reward, paid by the optional log")


func test_elder_reward_is_repaired_for_a_cleared_spawner() -> void:
	var area := _flat_area()
	GameState.set_flag("spawner_cleared_" + String(L.ELDER_SPAWNER["id"]), true)
	var arena := Bramble.Arena.new()
	area.add_child(arena)
	arena.repair_reward()
	assert_true(GameState.has_reward(L.REWARD_ELDER), "a save that cleared the spawner before the reward gets it on load")
	assert_true(bool(GameState.get_flag(L.FLAG_ELDER_DEFEATED)), "flag set")


func test_far_away_kills_of_other_enemies_pay_nothing() -> void:
	var area := _flat_area()
	var arena := Bramble.Arena.new()
	area.add_child(arena)
	Events.enemy_killed.emit("brambling", Vector3.ZERO)
	Events.enemy_killed.emit("knotted_elder", Vector3(500, 0, 500))
	assert_false(GameState.has_reward(L.REWARD_ELDER), "only the Elder at Bramblewatch pays")
