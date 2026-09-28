extends "res://tests/test_case.gd"
## The Lanternwake waygate (src/world/surface/waygate.gd, docs/CHAPTER_TWO_SPEC.md 7.1, MP §11 step 2):
## its four surface states follow the flags, the repair is transactional (every cost checked before
## anything is taken: missing materials -> nothing taken), it never travels by itself, and the Reach
## side always leads home.

const WaygateScript := preload("res://src/world/surface/waygate.gd")

var _holder: Node3D
var _saved_mode: String = ""


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	Game.mode = _saved_mode
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(2)


func _gate(side: String = "surface") -> Node3D:
	var g: Node3D = WaygateScript.new()
	g.setup({"side": side})
	_holder.add_child(g)
	return g


func _counts() -> Array:
	return [GameState.count_item("wood"), GameState.count_item("stone"), GameState.count_item("copper_ore")]


func test_states_follow_the_flags() -> void:
	var said: Array = []
	var cb := func(_s: String, text: String, _d: float) -> void: said.append(text)
	Events.say.connect(cb)
	var g := _gate()
	assert_true(g.is_in_group("interactable"), "interactable")
	assert_eq(String(g.state()), "cold")
	assert_eq(String(g.get_interaction(null)["text"]), "Look at the old standing stones")
	var area_before := Game.area_id
	Game.mode = "playing"      # even while playing, a cold (or dormant) gate never starts a trip
	g.interact(null)
	assert_eq(said.size(), 1, "a flavour line")
	assert_false(Game._transitioning, "no area change was started")
	assert_eq(Game.area_id, area_before, "nothing else happens")
	GameState.set_flag("ward_restored", true)
	GameState.set_flag("chapter_one_complete", true)
	assert_eq(String(g.state()), "dormant")
	assert_eq(String(g.get_interaction(null)["text"]), "Examine the dormant waygate")
	said.clear()
	g.interact(null)
	assert_true(said.size() == 1 and String(said[0]).contains("Ward Stone"), "the dormant gate points to the Ward Stone")
	assert_false(Game._transitioning, "a dormant gate never travels")
	GameState.set_flag("ch2_accepted", true)
	assert_eq(String(g.state()), "woken")
	var info: Dictionary = g.get_interaction(null)
	assert_eq(String(info["text"]), "Repair the waygate (8 Wood, 4 Stone, 2 Copper Ore)")
	assert_false(bool(info["enabled"]), "greyed out without the materials")
	assert_true(String(info.get("reason", "")).contains("8 more Wood"), "the reason lists what is missing: %s" % info.get("reason", ""))
	GameState.set_flag("ch2_waygate_repaired", true)
	assert_eq(String(g.state()), "lit")
	assert_eq(String(g.get_interaction(null)["text"]), "Travel to Hallowmere Reach")
	assert_false(g.vines.visible, "the vines are gone once repaired")
	Events.say.disconnect(cb)


func test_repair_is_transactional() -> void:
	GameState.set_flag("ward_restored", true)
	GameState.set_flag("chapter_one_complete", true)
	GameState.set_flag("ch2_accepted", true)
	var g := _gate()
	# One copper ore short: nothing may be taken.
	GameState.give_item("wood", 10)
	GameState.give_item("stone", 4)
	GameState.give_item("copper_ore", 1)
	var before: Array = GameState.inventory.to_array()
	assert_false(g.repair(), "missing copper ore -> refused")
	assert_eq(_counts(), [10, 4, 1], "nothing taken when something is missing")
	assert_eq(GameState.inventory.to_array(), before, "backpack slots untouched")
	assert_false(bool(GameState.get_flag("ch2_waygate_repaired")), "not repaired")
	g.interact(null)   # the interaction path is the same transaction
	assert_eq(_counts(), [10, 4, 1], "interact() with missing materials takes nothing either")
	# Everything there: exactly the cost is taken.
	GameState.give_item("copper_ore", 1)
	assert_true(bool(g.get_interaction(null)["enabled"]), "enabled with every material")
	assert_true(g.repair(), "repaired")
	assert_eq(_counts(), [2, 0, 0], "exactly 8 wood, 4 stone and 2 copper ore were taken")
	assert_true(bool(GameState.get_flag("ch2_waygate_repaired")), "flag ch2_waygate_repaired")
	assert_eq(String(g.state()), "lit")
	assert_false(g.repair(), "a lit gate is never repaired (charged) twice")
	assert_eq(_counts(), [2, 0, 0], "no second charge")


## Repair only after accepting Chapter Two; a gate never teleports on its own or outside "playing".
func test_no_repair_or_travel_before_its_time() -> void:
	var g := _gate()
	GameState.give_item("wood", 8)
	GameState.give_item("stone", 4)
	GameState.give_item("copper_ore", 2)
	assert_false(g.repair(), "cold gate: no repair")
	GameState.set_flag("chapter_one_complete", true)
	assert_false(g.repair(), "dormant gate (not accepted): no repair")
	assert_eq(_counts(), [8, 4, 2], "nothing taken")
	GameState.set_flag("ch2_waygate_repaired", true)
	Game.mode = "boot"
	var area_before := Game.area_id
	g.interact(null)
	assert_false(Game._transitioning, "no area change was started")
	await wait_frames(2)
	assert_eq(Game.area_id, area_before, "no travel unless the game is playing")


func test_reach_side_always_leads_home() -> void:
	var g := _gate("reach")
	assert_eq(String(g.state()), "lit", "the Reach side is always lit (fresh save, no flags)")
	assert_eq(String(g.target_area), "surface")
	assert_eq(String(g.target_spawn), "waygate")
	assert_eq(String(g.get_interaction(null)["text"]), "Return to Hollowhaven Woods")
	assert_true(bool(g.get_interaction(null)["enabled"]))
	assert_false(g.repair(), "nothing to repair on the Reach side")
