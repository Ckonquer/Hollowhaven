extends "res://tests/unit/test_core_base.gd"
## QuestLog (src/core/quest_log.gd) against data/quests.gd: every step completable from state,
## cascades, counter baselines, rewards exactly once (also across save/load), from_dict repair.

const Layout := preload("res://data/world_layout.gd")
## Hint tokens documented in data/quests.gd and the Settings action each one is shown with.
const HINT_TOKENS := {"interact": "interact", "attack": "attack", "inventory": "inventory", "craft": "craft",
	"build": "build", "sprint": "sprint", "jump": "jump", "dodge": "dodge", "lantern": "lantern",
	"journal": "journal", "map": "map", "use": "use_item"}
const OBJECTIVE_TYPES := ["flag", "item", "item_any", "placed", "befriended", "counter"]


func setup() -> void:
	fresh_state()


func _q() -> RefCounted:
	return GameState.quests


func _step_index(id: String) -> int:
	for i in QuestsData.STEPS.size():
		if QuestsData.STEPS[i]["id"] == id:
			return i
	return -1


## Satisfies every objective of `step` with the least possible state change.
func _satisfy(step: Dictionary) -> void:
	for o in step["objectives"]:
		match String(o["type"]):
			"flag":
				GameState.set_flag(o["flag"], true)
			"item":
				var need: int = int(o.get("count", 1)) - GameState.count_item(o["item"])
				if need > 0:
					GameState.give_item(o["item"], need)
			"item_any":
				var have := 0
				for it in o["items"]:
					have += GameState.count_item(it)
				if have < int(o.get("count", 1)):
					GameState.give_item(o["items"][0], int(o.get("count", 1)) - have)
			"placed":
				for i in range(GameState.count_structures(o["structure"]), int(o.get("count", 1))):
					GameState.add_structure(o["structure"], Vector3(2 * i, 0, 4), 0.0)
			"befriended":
				GameState.befriend(o["creature"])
			"counter":
				GameState.add_counter(o["counter"], int(o.get("count", 1)))


## Completes steps generically until `stop_id` is the current step.
func _advance_to(stop_id: String) -> void:
	var guard := 0
	while _q().current_id() != stop_id and guard < 40:
		guard += 1
		_satisfy(_q().current_step())
		_q().evaluate()
	assert_eq(_q().current_id(), stop_id, "advanced to %s" % stop_id)


# --- the whole chain -------------------------------------------------------------------------------------------

func test_every_step_completes_in_order_and_rewards_once() -> void:
	var done_sig := record(Events.quest_step_completed, 1)
	var steps: Array = QuestsData.STEPS
	for i in steps.size():
		var step: Dictionary = steps[i]
		assert_eq(_q().current_id(), step["id"], "step %d is current" % i)
		assert_false(_q().step_done(step), "%s is not already satisfied by earlier steps" % step["id"])
		_satisfy(step)
		assert_true(_q().step_done(step), "%s satisfiable from state" % step["id"])
		_q().evaluate()
		assert_true(_q().is_completed(step["id"]), "%s completed" % step["id"])
		if step["id"] == "return":
			assert_eq(_q().current_id(), "free_play", "the chapter ends in free play")
			assert_true(_q().is_chapter_complete())
			assert_eq(GameState.count_item("haven_banner"), 1, "banner granted once")
			assert_eq(GameState.count_item("sweetroot_seeds"), 3, "Mochi's seeds granted once (+3)")
			assert_eq(GameState.count_item("copper_ore"), 2, "Pebble's copper granted once (+2)")
			assert_eq(GameState.get_flag("chapter_one_complete"), true)
	assert_eq(_q().index, steps.size(), "past the last step")
	assert_eq(_q().current_id(), "")
	assert_eq(done_sig.size(), steps.size(), "each step completed exactly once")
	# re-evaluating (directly and through the deferred signal path) never re-grants
	for k in 5:
		_q().evaluate()
	GameState.request_quest_eval()
	await wait_frames(3)
	assert_eq(GameState.count_item("haven_banner"), 1)
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)
	# neither does a save/load cycle
	assert_true(SaveSystem.save_game())
	GameState.reset()
	assert_true(SaveSystem.load_game())
	_q().evaluate()
	await wait_frames(3)
	assert_eq(GameState.count_item("haven_banner"), 1)
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)
	assert_eq(GameState.count_item("copper_ore"), 2)
	assert_eq(done_sig.size(), steps.size(), "no step completed again after load")


func test_reward_overflow_is_dropped_not_lost() -> void:
	_advance_to("mochi")
	fill_backpack("stone")
	GameState.befriend("mochi")
	_q().evaluate()
	assert_eq(_q().current_id(), "pebble")
	var seeds := 0
	for d in GameState.dropped:
		if d["item"] == "sweetroot_seeds":
			seeds += int(d["count"])
	assert_eq(seeds, 3, "reward with a full backpack becomes a persistent drop")


# --- cascades & baselines ----------------------------------------------------------------------------------

func test_cascade_when_objectives_already_satisfied() -> void:
	var started := record(Events.quest_step_started, 1)
	GameState.set_flag("read_ward_intro")
	GameState.give_item("wood", 3)
	GameState.give_item("stone", 2)
	GameState.give_item("fiber", 2)
	GameState.give_item("stone_axe", 1)
	GameState.add_counter("trees_felled", 5)
	_q().evaluate()
	assert_eq(_q().current_id(), "chop", "wake, gather_basics and craft_axe completed in one evaluation")
	assert_eq(_q().completed, ["wake", "gather_basics", "craft_axe"])
	assert_eq(started, [["gather_basics"], ["craft_axe"], ["chop"]])
	# the counter objective only counts trees felled since the step began
	assert_eq(_q().baselines["chop"]["trees_felled"], 5)
	var st: Array = _q().objective_status()
	assert_eq(st[0]["progress"], 0)
	assert_eq(st[0]["target"], 2)
	GameState.add_counter("trees_felled")
	GameState.give_item("wood", 7)
	_q().evaluate()
	assert_eq(_q().current_id(), "chop", "1 of 2 trees")
	GameState.add_counter("trees_felled")
	_q().evaluate()
	assert_eq(_q().current_id(), "workbench")


func test_cascade_through_reward_steps_grants_each_once() -> void:
	_advance_to("workbench")
	GameState.befriend("mochi")
	GameState.give_item("stone_pickaxe", 1)
	GameState.befriend("pebble")
	GameState.add_structure("workbench", Vector3(3, 0, 3), 0.0)
	_q().evaluate()
	assert_eq(_q().current_id(), "home", "workbench, mochi and pebble in one go")
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)
	assert_eq(GameState.count_item("copper_ore"), 2)


func test_counter_since_start_false_counts_earlier_progress() -> void:
	GameState.add_counter("crops_planted", 1)   # planted before reaching the step
	_advance_to("home")
	GameState.add_structure("bed", Vector3(0, 0, 3), 0.0)
	GameState.add_structure("crop_plot", Vector3(3, 0, 3), 0.0)
	_q().evaluate()
	assert_eq(_q().current_id(), "lumi", "since_start=false uses the total counter")


func test_baseline_recorded_when_step_starts() -> void:
	_advance_to("craft_axe")
	GameState.add_counter("trees_felled", 3)
	GameState.give_item("stone_axe", 1)
	_q().evaluate()
	assert_eq(_q().current_id(), "chop")
	assert_eq(_q().baselines.get("chop", {}).get("trees_felled", -1), 3)
	GameState.add_counter("trees_felled", 1)
	assert_eq(_q().objective_status()[0]["progress"], 1)
	assert_false(_q().objective_status()[0]["done"])


func test_objective_status_clamps_progress() -> void:
	_advance_to("gather_basics")
	GameState.give_item("wood", 50)
	var st: Array = _q().objective_status()
	assert_eq(st.size(), 3)
	assert_eq(st[0], {"label": "Collect Wood (sticks)", "done": true, "progress": 3, "target": 3})
	assert_eq(st[1]["done"], false)
	assert_eq(st[1]["progress"], 0)


func test_item_objectives_count_the_key_pouch() -> void:
	_advance_to("old_mine")
	GameState.give_item("foreman_key", 1)
	_q().evaluate()
	assert_eq(_q().current_id(), "deeper")


func test_step_without_objectives_never_completes_and_unknown_type_is_safe() -> void:
	assert_false(_q().step_done({"id": "x", "objectives": []}))
	var st: Array = _q().objective_status({"id": "y", "objectives": [{"type": "mystery", "label": "?"}]})
	assert_eq(st.size(), 1)
	assert_false(st[0]["done"])
	assert_true(logged("unknown objective type"))


# --- signal-driven evaluation & safety-net poll ------------------------------------------------------------

func test_signals_trigger_deferred_evaluation() -> void:
	GameState.set_flag("read_ward_intro")   # Events.flag_set -> request_quest_eval
	assert_eq(_q().current_id(), "wake", "evaluation is deferred")
	await wait_frames(3)
	assert_eq(_q().current_id(), "gather_basics")
	GameState.give_item("wood", 3)
	GameState.give_item("stone", 2)
	GameState.give_item("fiber", 2)
	await wait_frames(3)
	assert_eq(_q().current_id(), "craft_axe")


func test_poll_catches_state_changed_without_signals() -> void:
	_advance_to("mochi")
	await wait_frames(2)   # flush evaluations queued by _advance_to
	GameState._quest_poll = 0.0
	GameState._process(1.0)
	GameState._process(1.0)
	assert_false(GameState._eval_pending, "an unfinished step never queues evaluations (no per-second HUD churn)")
	GameState._quest_poll = 0.0
	GameState.companion("mochi")["befriended"] = true   # like Debug --befriend: no signal
	assert_false(GameState._eval_pending, "no signal, so nothing queued an evaluation")
	GameState._process(0.5)
	assert_false(GameState._eval_pending, "the poll runs once per second")
	GameState._process(0.5)   # the once-per-second safety net
	assert_true(GameState._eval_pending, "poll noticed the satisfied step")
	await wait_frames(3)
	assert_eq(_q().current_id(), "pebble")
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)


func test_placing_a_structure_requests_evaluation() -> void:
	_advance_to("workbench")
	GameState.add_structure("workbench", Vector3(3, 0, 3), 0.0)
	await wait_frames(3)
	assert_eq(_q().current_id(), "mochi")


# --- persistence & repair ---------------------------------------------------------------------------------------

func test_reload_does_not_regrant_rewards() -> void:
	_advance_to("pebble")
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)
	assert_true(SaveSystem.save_game())
	for k in 3:
		GameState.reset()
		assert_true(SaveSystem.load_game())
		_q().evaluate()
		await wait_frames(2)
	assert_eq(_q().current_id(), "pebble")
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)
	assert_true(_q().is_completed("mochi"))


func test_inconsistent_save_with_current_step_already_completed() -> void:
	# e.g. saved between marking a step completed and advancing: no second reward
	_advance_to("mochi")
	var d := GameState.to_dict()
	d["quests"]["completed"].append("mochi")
	d["companions"]["mochi"]["befriended"] = true
	GameState.from_dict(json_norm(d))
	_q().evaluate()
	assert_eq(_q().current_id(), "pebble", "advances")
	assert_eq(GameState.count_item("sweetroot_seeds"), 0, "but the reward is not granted twice")


func test_satisfied_step_completes_once_after_load() -> void:
	_advance_to("mochi")
	var d := GameState.to_dict()
	d["companions"]["mochi"]["befriended"] = true
	d["companions"]["mochi"]["assignment"] = "follow"
	GameState.from_dict(json_norm(d))
	await wait_frames(3)   # from_dict schedules an evaluation
	_q().evaluate()
	assert_eq(_q().current_id(), "pebble")
	assert_eq(GameState.count_item("sweetroot_seeds"), 3)


func test_from_dict_repairs_completed_list() -> void:
	var q: RefCounted = QuestLog.new()
	q.from_dict({"index": 5})
	var ids := []
	for i in 5:
		ids.append(QuestsData.STEPS[i]["id"])
	assert_eq(q.completed, ids, "every step before the index is completed")
	assert_eq(q.current_id(), QuestsData.STEPS[5]["id"])
	assert_true(q.baselines.has(q.current_id()), "baseline created for the current step")


func test_from_dict_clamps_and_tolerates_garbage() -> void:
	var q: RefCounted = QuestLog.new()
	q.from_dict({"index": 999})
	assert_eq(q.index, QuestsData.STEPS.size())
	assert_eq(q.current_id(), "")
	assert_eq(q.completed.size(), QuestsData.STEPS.size())
	assert_true(q.is_chapter_complete())
	q.from_dict({"index": -4, "completed": "junk", "baselines": 3})
	assert_eq(q.index, 0)
	assert_eq(q.completed, [])
	assert_eq(q.current_id(), "wake")
	q.from_dict({"index": "two", "completed": [7, null, "wake", "wake"], "baselines": {"chop": "x", "gather_basics": {"n": "y"}}})
	assert_eq(q.index, 0)
	assert_eq(q.completed, ["wake"], "non-strings dropped, duplicates removed")
	assert_eq(q.baselines.get("gather_basics"), {}, "non-numeric baseline values dropped")
	assert_false(q.baselines.has("chop"))


func test_from_dict_restores_json_types() -> void:
	var q: RefCounted = QuestLog.new()
	q.from_dict(json_norm({"index": 3, "completed": ["wake", "gather_basics", "craft_axe"], "baselines": {"chop": {"trees_felled": 4}}}))
	assert_eq(typeof(q.index), TYPE_INT)
	assert_eq(q.index, 3)
	assert_eq(typeof(q.baselines["chop"]["trees_felled"]), TYPE_INT)
	var again: RefCounted = QuestLog.new()
	again.from_dict(json_norm(q.to_dict()))
	assert_deep_eq(again.to_dict(), q.to_dict(), "quests")


# --- arachnophobia-aware step text -----------------------------------------------------------------------------

func test_step_string_honours_arachnophobia_alternatives() -> void:
	var step := {"id": "x", "title": "The Silk Hollows", "alt_title": "The Pale Hollows", "text": "Webs.", "hint": "Listen."}
	Settings.set_value("arachnophobia", false)
	assert_eq(_q().step_string(step, "title"), "The Silk Hollows")
	assert_eq(_q().step_string(step, "text"), "Webs.")
	Settings.set_value("arachnophobia", true)
	assert_eq(_q().step_string(step, "title"), "The Pale Hollows")
	assert_eq(_q().step_string(step, "text"), "Webs.", "no alt: the normal text")
	assert_eq(_q().step_string(step, "missing"), "")
	var silk: Dictionary = _q().step_by_id("silk")
	assert_eq(_q().step_string(silk, "text"), String(silk["alt_text"]), "the real Silk Hollows step uses its alt text")
	assert_false(_q().step_string(silk, "text").to_lower().contains("web"))


func test_goal_toasts_use_the_step_title() -> void:
	var notes := record(Events.notify, 2)
	GameState.set_flag("read_ward_intro")
	_q().evaluate()
	assert_true(notes.has(["Goal complete: A Dim Haven", "quest"]), str(notes))
	assert_true(notes.has(["New goal: Gather Supplies", "quest"]), str(notes))


# --- data integrity --------------------------------------------------------------------------------------------------

func test_quest_data_is_consistent() -> void:
	var steps: Array = QuestsData.STEPS
	var seen := {}
	assert_eq(steps[0]["id"], "wake")
	assert_eq(steps[steps.size() - 1]["id"], "free_play", "free play is the final step")
	assert_true(_step_index("return") >= 0, "is_chapter_complete() relies on the 'return' step")
	assert_eq(_step_index("return"), steps.size() - 2, "'return' is the last story step")
	for s in steps:
		var id: String = s["id"]
		assert_false(seen.has(id), "duplicate step id " + id)
		seen[id] = true
		assert_true(String(s.get("title", "")) != "", id + " has a title")
		assert_true(String(s.get("text", "")) != "", id + " has text")
		var target: String = s.get("target", "")
		assert_true(target == "" or Layout.LANDMARKS.has(target), id + " target landmark exists: " + target)
		var objs: Array = s.get("objectives", [])
		assert_false(objs.is_empty(), id + " has objectives")
		for o in objs:
			var t: String = o.get("type", "")
			assert_true(OBJECTIVE_TYPES.has(t), "%s: known objective type %s" % [id, t])
			assert_true(String(o.get("label", "")) != "", id + " objective has a label")
			match t:
				"flag":
					assert_true(String(o.get("flag", "")) != "", id + " flag name")
				"item":
					assert_true(ItemDB.has_item(o["item"]), "%s: item %s exists" % [id, o["item"]])
				"item_any":
					for it in o["items"]:
						assert_true(ItemDB.has_item(it), "%s: item %s exists" % [id, it])
				"placed":
					assert_false(ItemDB.structure(o["structure"]).is_empty(), "%s: structure %s exists" % [id, o["structure"]])
				"befriended":
					assert_false(ItemDB.creature(o["creature"]).is_empty(), "%s: creature %s exists" % [id, o["creature"]])
				"counter":
					assert_true(String(o.get("counter", "")) != "", id + " counter name")
		var give: Dictionary = s.get("on_complete", {}).get("give", {})
		for it in give:
			assert_true(ItemDB.has_item(it), "%s: reward %s exists" % [id, it])
			assert_true(int(give[it]) > 0)


func test_hint_tokens_are_documented_and_bound() -> void:
	var rx := RegEx.new()
	rx.compile("\\{([a-z_]+)\\}")
	for s in QuestsData.STEPS:
		for m in rx.search_all(String(s.get("hint", ""))):
			var tok := m.get_string(1)
			assert_true(HINT_TOKENS.has(tok), "%s hint token {%s} is documented" % [s["id"], tok])
			if HINT_TOKENS.has(tok):
				assert_true(Settings.DEFAULT_BINDINGS.has(HINT_TOKENS[tok]), "{%s} maps to a bound action" % tok)
