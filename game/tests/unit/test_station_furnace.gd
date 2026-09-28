extends "res://tests/test_case.gd"
## Furnace station (MP 3 / 16, spec 3 / 9): a finite, saved queue of short jobs on the play-seconds timeline,
## an output buffer in structures[uid].data, collect exactly once (also across save/load, mid-batch), a full
## backpack keeps the rest in the buffer, dismantle refunds, and the node contract (queue_add/queue/collect).

const Furnace := preload("res://src/crafting/furnace.gd")
const Crafting := preload("res://src/crafting/crafting.gd")
const FurnaceNode := preload("res://src/building/structures/furnace.gd")
const WorkbenchNode := preload("res://src/building/structures/workbench.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")

var _uid := ""
var _crafted: Array = []
var _area: Node3D


func before_each() -> void:
	fresh_state()
	_uid = GameState.add_structure("furnace", Vector3(2, 0, 2), 0)
	_crafted = []
	if not Events.crafted.is_connected(_on_crafted):
		Events.crafted.connect(_on_crafted)
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)


func after_each() -> void:
	if Events.crafted.is_connected(_on_crafted):
		Events.crafted.disconnect(_on_crafted)
	if is_instance_valid(_area):
		_area.free()


func _on_crafted(recipe_id: String, item_id: String, count: int) -> void:
	_crafted.append([recipe_id, item_id, count])


func _t(s: float) -> void:
	GameState.stats["play_seconds"] = s


func _roundtrip() -> void:
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))


func _secs(rid: String) -> float:
	return float(ItemDB.recipe(rid)["time"])


func test_enqueue_consumes_once_and_runs_jobs_one_after_another() -> void:
	_t(100.0)
	GameState.give_item("copper_ore", 5)
	assert_true(Furnace.enqueue(_uid, "copper_bar"), Furnace.last_reason)
	assert_true(Furnace.enqueue(_uid, "copper_bar"), Furnace.last_reason)
	assert_eq(GameState.count_item("copper_ore"), 1, "2 ore per job")
	assert_false(Furnace.enqueue(_uid, "copper_bar"), "one ore left: refused")
	assert_eq(GameState.count_item("copper_ore"), 1, "nothing taken when refused")
	var q := Furnace.queue(_uid)
	var s := _secs("copper_bar")
	assert_eq(q.size(), 2)
	assert_almost(float(q[0]["start"]), 100.0)
	assert_almost(float(q[0]["end"]), 100.0 + s)
	assert_almost(float(q[1]["start"]), 100.0 + s, 0.001, "second job starts when the first ends")
	assert_almost(float(q[1]["end"]), 100.0 + 2.0 * s)
	assert_eq(GameState.count_item("copper_bar"), 0, "no bars yet")
	var p := Furnace.progress(_uid)
	assert_true(bool(p["busy"]))
	assert_true(bool(p["jobs"][0]["active"]))
	assert_false(bool(p["jobs"][1]["active"]), "second job waits")
	_t(100.0 + s * 0.5)
	assert_almost(float(Furnace.progress(_uid)["jobs"][0]["fraction"]), 0.5, 0.01)


func test_finished_jobs_settle_exactly_once_and_collect_once() -> void:
	_t(0.0)
	GameState.give_item("copper_ore", 6)
	for i in 3:
		assert_true(Furnace.enqueue(_uid, "copper_bar"))
	var s := _secs("copper_bar")
	_t(s * 2.0 + 0.1)
	assert_eq(Furnace.settle(_uid), 2, "two jobs done")
	assert_eq(Furnace.settle(_uid), 0, "settling again changes nothing")
	assert_eq(Furnace.output(_uid), {"copper_bar": 2})
	assert_eq(_crafted, [["copper_bar", "copper_bar", 1], ["copper_bar", "copper_bar", 1]], "crafted once per job")
	assert_eq(int(GameState.stats["items_crafted"]), 2)
	assert_eq(Furnace.collect(_uid), 2)
	assert_eq(GameState.count_item("copper_bar"), 2)
	assert_eq(Furnace.collect(_uid), 0, "nothing twice")
	assert_eq(GameState.count_item("copper_bar"), 2)
	_t(s * 3.0 + 1.0)
	assert_eq(Furnace.collect(_uid), 1)
	assert_eq(GameState.count_item("copper_bar"), 3)
	assert_eq(Furnace.queue(_uid), [])
	assert_eq(_crafted.size(), 3)


func test_queue_is_finite_and_mastery_can_add_one() -> void:
	_t(0.0)
	GameState.give_item("copper_ore", 40)
	var cap := Furnace.capacity(_uid)
	assert_eq(cap, int(ItemDB.structure("furnace")["queue"]), "data queue size")
	for i in cap:
		assert_true(Furnace.enqueue(_uid, "copper_bar"))
	var c := Furnace.can_enqueue(_uid, "copper_bar")
	assert_false(bool(c["ok"]))
	assert_true(String(c["reason"]).contains("full"), String(c["reason"]))
	assert_eq(GameState.count_item("copper_ore"), 40 - 2 * cap)
	GameState.mastery["hearthcraft"] = int(ItemDB.mastery_tables()["rank_xp"][3])
	assert_eq(Furnace.capacity(_uid), cap + 1, "hearthcraft rank 3: one more job")
	assert_true(Furnace.enqueue(_uid, "copper_bar"))


func test_save_and_load_mid_batch_never_loses_or_duplicates() -> void:
	_t(50.0)
	GameState.give_item("copper_ore", 4)
	GameState.give_item("iron_ore", 2)
	assert_true(Furnace.enqueue(_uid, "copper_bar"))
	assert_true(Furnace.enqueue(_uid, "iron_bar"))
	assert_true(Furnace.enqueue(_uid, "copper_bar"))
	var s1 := _secs("copper_bar")
	var s2 := _secs("iron_bar")
	# Save half way through the first job, load twice: same jobs, same timing, nothing finished.
	_t(50.0 + s1 * 0.5)
	var q_before := Furnace.queue(_uid)
	_roundtrip()
	_roundtrip()
	assert_eq(Furnace.queue(_uid), q_before, "queue identical after two loads")
	assert_almost(float(Furnace.progress(_uid)["jobs"][0]["fraction"]), 0.5, 0.01, "resumes mid-batch")
	assert_eq(Furnace.output(_uid), {})
	# The first job finishes after the load; save with the bar sitting in the buffer; load; collect once.
	_t(50.0 + s1 + 0.01)
	assert_eq(Furnace.settle(_uid), 1)
	_roundtrip()
	assert_eq(Furnace.output(_uid), {"copper_bar": 1}, "buffer saved")
	assert_eq(Furnace.settle(_uid), 0, "a loaded buffer is not settled again")
	assert_eq(Furnace.collect(_uid), 1)
	_roundtrip()
	assert_eq(Furnace.collect(_uid), 0, "collected before saving: never again")
	assert_eq(GameState.count_item("copper_bar"), 1)
	# Jobs that finished while saved-but-unsettled finish exactly once after loading.
	_t(50.0 + s1 + s2 + s1 + 5.0)
	_roundtrip()
	assert_eq(Furnace.collect(_uid), 2)
	assert_eq(GameState.count_item("copper_bar"), 2)
	assert_eq(GameState.count_item("iron_bar"), 1)
	assert_eq(_crafted.size(), 3, "three jobs, three crafted events in total")


func test_time_only_advances_while_playing() -> void:
	_t(10.0)
	GameState.give_item("copper_ore", 2)
	assert_true(Furnace.enqueue(_uid, "copper_bar"))
	# A long in-game night (sleeping skips the CLOCK, not play time) does not finish it.
	GameState.skip_to_morning()
	GameState.total_minutes += 5000.0
	assert_eq(Furnace.output(_uid), {}, "clock skips don't smelt")
	# Real unpaused play does (Game._process -> GameState.advance_clock adds play_seconds).
	GameState.advance_clock(_secs("copper_bar") + 0.5)
	assert_eq(Furnace.output(_uid), {"copper_bar": 1})


func test_full_backpack_keeps_the_rest_in_the_buffer() -> void:
	_t(0.0)
	GameState.give_item("copper_ore", 6)
	for i in 3:
		assert_true(Furnace.enqueue(_uid, "copper_bar"))
	_t(1000.0)
	var inv = GameState.inventory
	for i in inv.size:
		inv.set_slot(i, {"id": "berries", "count": 50})
	assert_eq(Furnace.collect(_uid), 0)
	assert_true(Furnace.last_reason.to_lower().contains("full"), Furnace.last_reason)
	assert_eq(Furnace.output(_uid), {"copper_bar": 3}, "nothing lost")
	assert_eq(GameState.dropped.size(), 0, "no world clutter")
	_roundtrip()
	assert_eq(Furnace.output(_uid), {"copper_bar": 3}, "overflow is saved")
	inv = GameState.inventory
	var mx := ItemDB.stack_max("copper_bar")
	inv.set_slot(5, {"id": "copper_bar", "count": mx - 1})
	assert_eq(Furnace.collect(_uid), 1, "one fits on the partial stack")
	assert_eq(Furnace.output(_uid), {"copper_bar": 2})
	inv.set_slot(6, null)
	assert_eq(Furnace.collect(_uid), 2)
	assert_eq(Furnace.output(_uid), {})
	assert_eq(GameState.count_item("copper_bar"), mx + 2)


func test_enqueue_can_use_nearby_chests_transactionally() -> void:
	_t(0.0)
	var chest := GameState.add_structure("storage_chest", Vector3(4, 0, 2), 0)
	GameState.get_storage(chest).add("iron_ore", 3)
	GameState.give_item("iron_ore", 1)
	assert_false(Furnace.enqueue(_uid, "iron_bar"), "one ore in the bag")
	assert_true(Furnace.enqueue(_uid, "iron_bar", [chest]))
	assert_eq(GameState.count_item("iron_ore"), 0)
	assert_eq(GameState.get_storage(chest).count_of("iron_ore"), 2)


func test_locked_or_wrong_recipes_are_refused() -> void:
	GameState.give_item("iron_bar", 4)
	GameState.give_item("moon_crystal", 2)
	GameState.give_item("echo_shard", 2)
	assert_false(Furnace.enqueue(_uid, "moonsteel_bar"), "locked until the winch is repaired")
	GameState.set_flag("ch2_winch_repaired", true)
	assert_true(Furnace.enqueue(_uid, "moonsteel_bar"))
	GameState.give_item("wood", 10)
	assert_false(Furnace.enqueue(_uid, "workbench"), "not a furnace recipe")
	var bench := GameState.add_structure("workbench", Vector3(6, 0, 0), 0)
	GameState.give_item("copper_ore", 2)
	assert_false(Furnace.enqueue(bench, "copper_bar"), "a workbench is no furnace")
	assert_eq(GameState.count_item("copper_ore"), 2)


func test_refund_all_returns_everything_once() -> void:
	_t(0.0)
	GameState.give_item("copper_ore", 6)
	for i in 3:
		assert_true(Furnace.enqueue(_uid, "copper_bar"))
	_t(_secs("copper_bar") + 0.1)
	var given := Furnace.refund_all(_uid, Vector3(2, 0.6, 2))
	assert_eq(given, {"copper_bar": 1, "copper_ore": 4}, "finished bar + ingredients of the unfinished jobs")
	assert_eq(GameState.count_item("copper_bar"), 1)
	assert_eq(GameState.count_item("copper_ore"), 4)
	assert_eq(Furnace.refund_all(_uid), {}, "twice gives nothing")
	assert_eq(Furnace.queue(_uid), [])


## The real dismantle (BuildOps removes the record first, then the node plays its removal): the furnace node gives
## back the finished bar and the ingredients of the unfinished jobs once, without any build_ops hook.
func test_dismantling_a_furnace_returns_what_is_inside_once() -> void:
	_t(0.0)
	GameState.give_item("copper_ore", 6)
	for i in 3:
		assert_true(Furnace.enqueue(_uid, "copper_bar"))
	var n := Factory.spawn_structure(_area, _uid)
	assert_not_null(n)
	_t(_secs("copper_bar") + 0.1)   # one job finished (not settled yet), two still waiting
	var res := Ops.dismantle(_area, _uid)
	assert_true(bool(res["ok"]), String(res.get("reason", "")))
	assert_false(GameState.structures.has(_uid))
	assert_eq(GameState.count_item("copper_bar"), 1, "the finished bar")
	assert_eq(GameState.count_item("copper_ore"), 4, "ingredients of the two unfinished jobs")
	assert_eq(GameState.count_item("furnace"), 1, "the furnace item itself (BuildOps)")
	assert_eq(_crafted.size(), 1, "the finished job counts as crafted once")
	if is_instance_valid(n):
		n.play_remove_and_free()
	assert_eq(GameState.count_item("copper_ore"), 4, "never paid twice")
	assert_eq(GameState.count_item("copper_bar"), 1)


## An integrator hook calling refund_all() before the removal and the node's own refund never pay twice.
func test_refund_all_before_removal_then_node_refund_pays_once() -> void:
	_t(0.0)
	GameState.give_item("copper_ore", 4)
	assert_true(Furnace.enqueue(_uid, "copper_bar"))
	assert_true(Furnace.enqueue(_uid, "copper_bar"))
	Factory.spawn_structure(_area, _uid)
	assert_eq(Furnace.refund_all(_uid, Vector3(2, 0.6, 2)), {"copper_ore": 4})
	assert_true(bool(Ops.dismantle(_area, _uid)["ok"]))
	assert_eq(GameState.count_item("copper_ore"), 4, "paid once")
	assert_eq(GameState.dropped.size(), 0)


func test_damaged_saved_queue_is_tolerated() -> void:
	GameState.structures[_uid]["data"] = {"queue": [{"recipe": "copper_bar", "start": 0.0, "end": 1.0}, "junk",
		{"recipe": 5}, {"recipe": "future_bar", "start": 1.0, "end": 2.0}], "output": {"copper_bar": 2.0, "iron_bar": "x"}}
	_t(10.0)
	assert_eq(Furnace.settle(_uid), 1)
	assert_eq(Furnace.output(_uid), {"copper_bar": 3})
	assert_eq(Furnace.queue(_uid), [])
	assert_eq((GameState.structures[_uid]["data"]["held_jobs"] as Array).size(), 1, "an unknown recipe is kept, not lost")


# --- Nodes ----------------------------------------------------------------------------------------------------

func _spawn(uid: String, sid: String) -> Node3D:
	var script: Script = FurnaceNode if sid == "furnace" else WorkbenchNode
	var n: Node3D = script.new()
	n.setup({"uid": uid, "id": sid})
	n.name = "S_" + uid
	var p: Variant = GameState.structures.get(uid, {}).get("pos")
	if p is Array:
		n.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_area.add_child(n)
	return n


func test_furnace_node_contract_state_and_interaction() -> void:
	_t(0.0)
	var n := _spawn(_uid, "furnace")
	assert_true(n.is_in_group("crafting_station"))
	assert_eq(String(n.station_id), "furnace")
	assert_true(Crafting.stations_near(n.global_position).has("furnace"))
	assert_eq(Crafting.nearest_station_uid(n.global_position + Vector3(1, 0, 0), "furnace"), _uid)
	assert_eq(n.current_state(), n.STATE_IDLE)
	assert_false(n.light.visible)
	var cold: Variant = n.parts.get("flame")
	if cold is Node3D:
		assert_false((cold as Node3D).visible, "a cold furnace shows no coals")
	var info: Dictionary = n.get_interaction(null)
	assert_true(info.has("text") and bool(info["enabled"]))
	assert_false(n.queue_add("copper_bar"), "no ore")
	GameState.give_item("copper_ore", 4)
	assert_true(n.queue_add("copper_bar"))
	assert_true(n.queue_add("copper_bar"))
	assert_eq(n.queue().size(), 2)
	assert_eq(n.current_state(), n.STATE_WORKING)
	assert_true(n.light.visible)
	var coals: Variant = n.parts.get("flame")
	if coals is Node3D:
		assert_true((coals as Node3D).visible, "coals glow while smelting")
	assert_true(String(n.get_interaction(null)["text"]).contains("Copper Bar"), String(n.get_interaction(null)["text"]))
	_t(_secs("copper_bar") * 2.0 + 1.0)
	n._process(0.6)   # the throttled poll settles finished jobs
	assert_eq(n.current_state(), n.STATE_READY)
	assert_true(n.sparkles.emitting, "ready bars sparkle")
	assert_true(String(n.get_interaction(null)["text"]).begins_with("Collect"))
	assert_eq(n.collect(), 2)
	assert_eq(n.current_state(), n.STATE_IDLE)
	assert_eq(GameState.count_item("copper_bar"), 2)
	n.free()


func test_furnace_interact_collects_then_opens_the_queue() -> void:
	_t(0.0)
	var n := _spawn(_uid, "furnace")
	GameState.give_item("copper_ore", 2)
	assert_true(n.queue_add("copper_bar"))
	_t(100.0)
	n.interact(null)   # Game.open_panel without a UI root is a no-op
	assert_eq(GameState.count_item("copper_bar"), 1, "collected on interact")
	assert_eq(Furnace.output(_uid), {})
	n.free()


## COV-006 (QA bot, lamp_orders_ch1_optional COV2-003): the furnace's prompt and toast used the singular for counts
## above 1 ("Collect 3 Copper Bar", "Collected 3 Copper Bar."). Crafting.describe_items now names counts through
## ItemDB.display_count: "Collect 3 Copper Bars" / "Collected 3 Copper Bars."; one bar stays "1 Copper Bar".
func test_furnace_prompt_and_toast_use_the_plural_for_several_bars() -> void:
	var toasts: Array = []
	var on_notify := func(text: String, _kind: String) -> void: toasts.append(text)
	Events.notify.connect(on_notify)
	_t(0.0)
	var n := _spawn(_uid, "furnace")
	GameState.give_item("copper_ore", 6)
	for i in 3:
		assert_true(n.queue_add("copper_bar"), Furnace.last_reason)
	_t(_secs("copper_bar") * 2.0 + 1.0)
	n._process(0.6)
	assert_eq(String(n.get_interaction(null)["text"]), "Collect 2 Copper Bars", "two bars ready")
	_t(_secs("copper_bar") * 3.0 + 1.0)
	n._process(0.6)
	assert_eq(String(n.get_interaction(null)["text"]), "Collect 3 Copper Bars", "three bars ready")
	n.interact(null)   # Game.open_panel without a UI root is a no-op
	assert_eq(GameState.count_item("copper_bar"), 3)
	assert_true(toasts.has("Collected 3 Copper Bars."), str(toasts))
	# One bar reads in the singular.
	GameState.give_item("copper_ore", 2)
	assert_true(n.queue_add("copper_bar"), Furnace.last_reason)
	_t(_secs("copper_bar") * 5.0 + 1.0)
	n._process(0.6)
	assert_eq(String(n.get_interaction(null)["text"]), "Collect 1 Copper Bar")
	n.interact(null)
	assert_true(toasts.has("Collected 1 Copper Bar."), str(toasts))
	Events.notify.disconnect(on_notify)
	n.free()


func test_loom_and_kitchen_use_the_workbench_station_script() -> void:
	for sid in ["loom", "kitchen_counter", "workbench"]:
		var uid := GameState.add_structure(sid, Vector3(8, 0, 0), 0)
		var n := _spawn(uid, sid)
		assert_true(n.is_in_group("crafting_station"), sid)
		assert_eq(String(n.station_id), String(ItemDB.structure(sid)["station"]), sid + " station id from data")
		assert_true(Crafting.stations_near(Vector3(8, 0, 0)).has(String(n.station_id)))
		var info: Dictionary = n.get_interaction(null)
		assert_true(info.has("text") and bool(info["enabled"]), sid)
		n.free()


func test_furnace_node_budget_and_colliders() -> void:
	var n := _spawn(_uid, "furnace")
	var meshes := n.get_node("Model").find_children("*", "GeometryInstance3D", true, false).size()
	assert_true(meshes <= 8, "furnace model mesh count %d" % meshes)
	var light := n.get_node_or_null("Light") as OmniLight3D
	assert_not_null(light)
	assert_false(light.shadow_enabled, "no shadowed lights")
	var interact_found := false
	for c in n.get_children():
		if c is CollisionObject3D:
			assert_eq((c as CollisionObject3D).collision_mask, 0)
			if (c as CollisionObject3D).collision_layer == 16:
				interact_found = true
	assert_true(interact_found, "interaction collider")
	n.free()


## "Copper, Not Just Courage" (data/optional_goals.gd): a placed furnace + a first armor piece complete it through
## the real optional log (the goal reads state; nothing extra to set).
func test_copper_courage_goal_completes_from_furnace_and_armor() -> void:
	GameState.add_structure("workbench", Vector3(5, 0, 0), 0)   # makes the goal visible
	GameState.optional_goals.evaluate()
	assert_false(GameState.optional_goals.is_done("opt_copper_courage"))
	GameState.give_item("woven_cloth", 1)
	GameState.give_item("fiber", 3)
	assert_true(Crafting.craft("padded_hood", ["hand", "loom"]))
	assert_true(GameState.equip("padded_hood"), GameState.last_equip_error)
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_copper_courage"), "furnace (placed in before_each) + armor")

