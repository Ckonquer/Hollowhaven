extends "res://tests/test_case.gd"
## Tools on resource nodes (src/world/common/resource_node.gd): stone tools keep the legacy hit counts exactly,
## better tools need fewer hits (power), gather bonuses (charm + mastery) reduce effort, min_tier gating
## (Moon Crystal needs an Ironwood pick), data kinds from data/sources.gd, prompts and the player's choice.

const ResourceNode := preload("res://src/world/common/resource_node.gd")
const Logic := preload("res://src/player/player_logic.gd")
const MasteryData := preload("res://data/mastery.gd")
const PlayerScript := preload("res://src/player/player.gd")
const Stats := preload("res://src/core/stats.gd")

var _holder: Node3D


func before_each() -> void:
	fresh_state()
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	for a in ["move_forward"]:
		Input.action_release(a)
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


func _node(params: Dictionary) -> Node3D:
	var n: Node3D = ResourceNode.new()
	n.setup(params)
	_holder.add_child(n)
	return n


## Hits `tool_id` needs to deplete a fresh node of `kind` (counted by actually hitting it).
func _count_hits(kind: String, tool_id: String, extra: Dictionary = {}) -> int:
	var p := {"node_id": "", "kind": kind}
	p.merge(extra, true)
	var n := _node(p)
	var hits := 0
	while not n.depleted and hits < 40:
		n.harvest_hit(null, tool_id)
		hits += 1
	var out := hits if n.depleted else -1
	n.queue_free()
	return out


func test_stone_tools_keep_legacy_hit_counts() -> void:
	GameState.give_item("stone_axe", 1)
	GameState.give_item("stone_pickaxe", 1)
	assert_eq(_count_hits("tree", "stone_axe"), 4, "tree: 4 hits")
	assert_eq(_count_hits("rock", "stone_pickaxe"), 3, "rock: 3 hits")
	assert_eq(_count_hits("ore", "stone_pickaxe"), 4, "copper vein: 4 hits")
	assert_eq(_count_hits("crystal", "stone_pickaxe"), 3, "echo crystal: 3 hits")
	assert_eq(_count_hits("rubble", "stone_pickaxe"), 4, "rubble: 4 hits")
	for kind in ["tree", "rock", "ore", "crystal", "rubble"]:
		var n := _node({"node_id": "", "kind": kind})
		assert_eq(int(n.required_tier), 0, "%s has no tier gate" % kind)
		assert_eq(String(n.base_kind), kind, "legacy kinds are their own base")
		n.queue_free()


func test_better_tools_need_fewer_hits() -> void:
	assert_eq(_count_hits("tree", "copper_axe"), 3, "copper axe (1.5)")
	assert_eq(_count_hits("tree", "ironwood_axe"), 2, "ironwood axe (2.0)")
	assert_eq(_count_hits("tree", "moonsteel_axe"), 2, "moonsteel axe (2.5)")
	assert_eq(_count_hits("rock", "copper_pickaxe"), 2)
	assert_eq(_count_hits("ore", "moonsteel_pickaxe"), 2)
	var n := _node({"node_id": "", "kind": "ore"})
	assert_eq(n.hits_needed("stone_pickaxe"), 4)
	assert_eq(n.hits_needed("copper_pickaxe"), 3)
	assert_eq(n.hits_needed("stone_axe"), -1, "wrong tool")


func test_gather_bonus_reduces_effort() -> void:
	assert_eq(_count_hits("iron_vein", "stone_pickaxe"), 6, "iron vein with the old stone pick: 6 hits")
	GameState.give_item("gatherers_charm", 1)
	assert_true(GameState.equip("gatherers_charm"))
	GameState.mastery["gathering"] = int(MasteryData.RANK_XP[3])
	assert_almost(Stats.harvest_power("stone_pickaxe"), 1.2, 0.0001)
	assert_eq(_count_hits("iron_vein", "stone_pickaxe"), 5, "charm 10% + mastery 10%: one hit less")
	assert_eq(_count_hits("tree", "stone_axe"), 4, "small nodes keep their count (effort, not magic)")


func test_moon_crystal_needs_an_ironwood_pick() -> void:
	var n := _node({"node_id": "test_mc_1", "kind": "moon_crystal_vein"})
	assert_eq(int(n.required_tier), 3, "tier from data/sources.gd")
	assert_eq(String(n.tool), "pickaxe")
	assert_eq(int(n.get_harvest_info()["min_tier"]), 3, "exposed to the probe")
	GameState.give_item("copper_pickaxe", 1)
	for i in 10:
		n.harvest_hit(null, "copper_pickaxe")
	assert_false(n.depleted, "a copper pick only wobbles it")
	assert_almost(float(n.get_harvest_info()["progress"]), 0.0, 0.0001, "no progress at all")
	var it: Dictionary = n.get_interaction(null)
	assert_false(bool(it["enabled"]), "prompt disabled")
	assert_true(String(it["text"]).contains("Ironwood Pickaxe"), String(it["text"]))
	GameState.give_item("ironwood_pickaxe", 1)
	assert_true(bool(n.get_interaction(null)["enabled"]))
	var before := GameState.count_item("moon_crystal")
	n.interact(null)
	n.interact(null)
	assert_false(n.depleted, "2 hits of power 2 < 5")
	n.interact(null)
	assert_true(n.depleted, "3rd ironwood hit breaks the seam")
	assert_true(GameState.count_item("moon_crystal") > before, "moon crystal gathered")
	assert_true(GameState.is_depleted("test_mc_1"), "persistent depletion")


func test_data_kinds_take_numbers_from_sources() -> void:
	var iron := _node({"node_id": "", "kind": "iron_vein"})
	assert_eq(String(iron.base_kind), "ore")
	assert_eq(int(iron.hits), 6)
	assert_eq(String(iron.display_name), "Iron Vein")
	assert_true(iron.tool_can_harvest("stone_pickaxe"), "reachable with the old stone pick (MP 16)")
	var stump := _node({"node_id": "", "kind": "sap_stump"})
	assert_eq(String(stump.tool), "hand")
	assert_true(String(stump.get_interaction(null)["text"]).begins_with("Tap"), "verb from data")
	var before := GameState.count_item("resin")
	stump.interact(null)
	assert_true(GameState.count_item("resin") > before, "tapping gives resin")
	var bush := _node({"node_id": "", "kind": "roseberry_bush"})
	assert_eq(String(bush.base_kind), "bush")
	bush.interact(null)
	assert_true(bush.depleted)
	assert_true(String(bush.get_interaction(null).get("text", "")).contains("regrowing"), "bush behaviour kept")
	var unknown := _node({"node_id": "", "kind": "no_such_kind"})
	assert_eq(String(unknown.kind), "rock", "unknown kinds still fall back to rock")


func test_bonus_yield_only_draws_when_mastered() -> void:
	seed(7)
	var plain := 0
	for i in 60:
		GameState.mastery["gathering"] = 0      # (a mastery listener may award xp for harvesting)
		var n := _node({"node_id": "", "kind": "stone"})
		var b := GameState.count_item("stone")
		n.interact(null)
		plain += GameState.count_item("stone") - b
		n.queue_free()
	assert_eq(plain, 60, "no mastery: exactly the legacy one stone each")
	GameState.mastery["gathering"] = int(MasteryData.RANK_XP[5])
	seed(7)
	var mastered := 0
	for i in 200:
		GameState.mastery["gathering"] = int(MasteryData.RANK_XP[5])
		var n := _node({"node_id": "", "kind": "stone"})
		var b := GameState.count_item("stone")
		n.interact(null)
		mastered += GameState.count_item("stone") - b
		n.queue_free()
	assert_true(mastered > 200 and mastered < 200 + 60, "rank 5: about 10%% extra (%d)" % mastered)


func test_prompt_names_the_needed_tier() -> void:
	var h := {"tool": "pickaxe", "name": "Moon Crystal Seam", "min_tier": 3}
	var p: Dictionary = Logic.build_prompt({}, h, "copper_pickaxe")
	assert_eq(String(p["text"]), "Needs an Ironwood Pickaxe")
	assert_false(bool(p["enabled"]))
	p = Logic.build_prompt({}, h, "ironwood_pickaxe")
	assert_eq(String(p["text"]), "Mine Moon Crystal Seam")
	assert_true(bool(p["enabled"]))
	p = Logic.build_prompt({}, h, "")
	assert_eq(String(p["text"]), "Needs a Pickaxe", "no pickaxe at all: the legacy text")
	p = Logic.build_prompt({}, {"tool": "axe", "name": "Oak Tree"}, "stone_axe")
	assert_eq(String(p["text"]), "Chop Oak Tree", "legacy prompt unchanged")
	assert_eq(Logic.tier_tool_article_name("axe", 4), "a Moonsteel Axe")
	assert_eq(Logic.tier_tool_article_name("pickaxe", 1), "a Pickaxe")


## A harvestable that records hits and asks for a tier.
class TierNode extends Node3D:
	var hits: Array = []

	func _ready() -> void:
		add_to_group("harvestable")
		var body := StaticBody3D.new()
		body.collision_layer = 16
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4
		cyl.height = 1.6
		cs.shape = cyl
		cs.position = Vector3(0, 0.8, 0)
		body.add_child(cs)
		add_child(body)

	func get_harvest_info() -> Dictionary:
		return {"tool": "pickaxe", "name": "Moon Crystal Seam", "min_tier": 3}

	func harvest_hit(_p: Node, tool_item_id: String) -> void:
		hits.append(tool_item_id)


func test_player_swings_only_a_tool_that_meets_the_tier() -> void:
	var saved_mode := Game.mode
	Game.mode = "playing"
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(-30, -0.5, -30)
	var player: CharacterBody3D = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(-30, 0.05, -30)))
	var seam := TierNode.new()
	add_child(seam)
	seam.global_position = Vector3(-30, 0, -31.3)
	GameState.give_item("copper_pickaxe", 1)
	await wait_physics(8)
	player.probe.refresh()
	assert_eq(String(player.get_prompt().get("text", "")), "Needs an Ironwood Pickaxe")
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq(seam.hits.size(), 0, "a copper pick is not used on Moon Crystal")
	GameState.give_item("ironwood_pickaxe", 1)
	player.probe.refresh()
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq(seam.hits, ["ironwood_pickaxe"], "the ironwood pick is swung, once")
	Game.mode = saved_mode
