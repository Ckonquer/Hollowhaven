extends "res://tests/test_case.gd"
## AUDIT (progression & softlocks), now a regression guard: the Ward Stone accepts the Heartseed at ANY
## quest step (ward_stone.gd only checks has_item("heartseed")), and nothing gates the mine on quest
## progress (mine_entrance.gd needs only a pickaxe). Returning the seed while an earlier surface step was
## still open used to stall the chain on "silk" (HOLD the seed the stone consumed) or "prepare" (the Ward
## Stone warning can't be read once restored): no Haven Banner, no "chapter_one_complete".
## Fix: the dungeon steps carry "skip_if_flag": "ward_restored" (data/quests.gd, QuestLog.is_skipped).

const QuestsData := preload("res://data/quests.gd")

var _saved_mode: String = ""


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode


func after_each() -> void:
	Game.mode = _saved_mode
	GameState.active = false


func _index_of(step_id: String) -> int:
	for i in QuestsData.STEPS.size():
		if String(QuestsData.STEPS[i]["id"]) == step_id:
			return i
	return -1


## Everything the dungeon sets on the way to the seed (flags/items the real nodes set).
func _run_dungeon_and_take_seed() -> void:
	GameState.set_flag("mine_opened", true)
	GameState.set_flag("entered_below", true)
	GameState.give_item("foreman_key", 1)
	GameState.set_flag("lower_gate_open", true)
	GameState.set_flag("reached_silk_hollows", true)
	GameState.set_flag("weaver_defeated", true)
	GameState.give_item("heartseed", 1)


## Control: the intended order (quest already on "silk" when the seed is taken) completes the chapter.
func test_in_order_return_completes_chapter() -> void:
	GameState.quests.from_dict({"index": _index_of("descend")})
	_run_dungeon_and_take_seed()
	GameState.quests.evaluate()
	assert_eq(GameState.quests.current_id(), "return", "in order: seed taken -> 'return' step")
	await Game.complete_chapter()
	GameState.quests.evaluate()
	assert_true(GameState.quests.is_chapter_complete(), "in order: chapter complete")
	assert_true(GameState.count_item("haven_banner") >= 1, "in order: Haven Banner granted")


## Was the bug: the same dungeon run while "prepare" is still open (only 1 meal held) never completed.
func test_heartseed_returned_before_silk_step_still_completes_chapter() -> void:
	GameState.quests.from_dict({"index": _index_of("prepare")})
	GameState.set_flag("read_ward_warning", true)
	GameState.give_item("lantern", 1)
	GameState.give_item("berry_snack", 1)          # one meal short: "prepare" stays open
	_run_dungeon_and_take_seed()
	GameState.quests.evaluate()
	assert_eq(GameState.quests.current_id(), "prepare", "precondition: still on 'prepare'")
	# The Ward Stone offers "Return the Heartseed" regardless of the quest step:
	var WardStone: Script = load("res://src/world/surface/ward_stone.gd")
	var ws: Node3D = WardStone.new()
	add_child(ws)
	assert_eq(String(ws.get_interaction(null).get("text", "")), "Return the Heartseed", "stone accepts the seed early")
	ws.queue_free()
	await Game.complete_chapter()                 # what ward_stone.interact() awaits
	assert_true(bool(GameState.get_flag("ward_restored")), "ending played, ward restored")
	# Later Krystal cooks the second meal: the chain resumes...
	GameState.give_item("berry_snack", 1)
	GameState.quests.evaluate()
	var stuck_on: String = GameState.quests.current_id()
	assert_true(stuck_on == "free_play" or stuck_on == "", "chain should reach free play, but is stuck on '%s'" % stuck_on)
	assert_true(GameState.quests.is_chapter_complete(), "'return' step must complete once the ward is restored")
	assert_true(GameState.count_item("haven_banner") >= 1, "Haven Banner reward must be granted")
	assert_true(bool(GameState.get_flag("chapter_one_complete")), "chapter_one_complete flag must be set")


## Same root cause, earlier step: if the seed was returned before "prepare" (e.g. on "lumi"), the Ward
## Stone's warning ("read_ward_warning", a "prepare" objective) can never be read afterwards, because
## ward_stone.interact() returns early with "Light kept..." once ward_restored is set.
func test_heartseed_returned_before_prepare_still_completes_chapter() -> void:
	GameState.quests.from_dict({"index": _index_of("lumi")})
	_run_dungeon_and_take_seed()
	GameState.give_item("lantern", 1)
	await Game.complete_chapter()
	assert_true(bool(GameState.get_flag("ward_restored")), "ending played, ward restored")
	# Later: Lumi is befriended, two meals are cooked, and Krystal reads the Ward Stone again.
	GameState.set_flag("ruin_cleared", true)
	GameState.befriend("lumi")
	GameState.give_item("berry_snack", 2)
	GameState.quests.evaluate()
	var WardStone: Script = load("res://src/world/surface/ward_stone.gd")
	var ws: Node3D = WardStone.new()
	add_child(ws)
	ws.interact(null)
	ws.queue_free()
	GameState.quests.evaluate()
	var stuck_on: String = GameState.quests.current_id()
	assert_true(stuck_on == "free_play" or stuck_on == "", "chain should reach free play, but is stuck on '%s' (read_ward_warning=%s)" % [stuck_on, str(GameState.get_flag("read_ward_warning"))])
	assert_true(GameState.count_item("haven_banner") >= 1, "Haven Banner reward must be granted")
