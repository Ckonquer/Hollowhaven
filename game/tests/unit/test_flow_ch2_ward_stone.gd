extends "res://tests/test_case.gd"
## The Ward Stone's Chapter Two inscription (docs/CHAPTER_TWO_SPEC.md §8, MP §2.4 / §17): the legacy
## lines are untouched; after Chapter One the new inscription is read and a choice is offered (accept =
## flag ch2_accepted + reassurance + waygate hint; decline = a gentle line and the choice comes back);
## once accepted, the menu lists only the options that apply; after the Choir the homecoming sets
## ch2_homecoming and the return line is read from then on. Nothing ever auto-teleports.

const WardStone := preload("res://src/world/surface/ward_stone.gd")

var _holder: Node3D
var _said: Array = []
var _notes: Array = []
var _choices: Array = []
var _hints: Array = []


func _on_say(_speaker: String, text: String, _d: float) -> void:
	_said.append(text)


func _on_notify(text: String, _kind: String) -> void:
	_notes.append(text)


func _on_choice(choice_id: String, option: String) -> void:
	_choices.append([choice_id, option])


func _on_hint(hint_id: String, _text: String) -> void:
	_hints.append(hint_id)


func before_each() -> void:
	fresh_state()
	_said.clear()
	_notes.clear()
	_choices.clear()
	_hints.clear()
	Events.say.connect(_on_say)
	Events.notify.connect(_on_notify)
	Events.choice_made.connect(_on_choice)
	Events.hint.connect(_on_hint)
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	Events.say.disconnect(_on_say)
	Events.notify.disconnect(_on_notify)
	Events.choice_made.disconnect(_on_choice)
	Events.hint.disconnect(_on_hint)
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(2)


func _stone() -> Node3D:
	var ws: Node3D = WardStone.new()
	_holder.add_child(ws)
	return ws


## Lines are chained by a tween: collect the whole reading.
func _read_all(ws: Node3D, answer: String = "") -> void:
	ws.forced_choice = answer
	_said.clear()
	await ws.interact(null)
	var tw: Variant = ws.get("_say_tw")
	var guard := 0
	while tw is Tween and (tw as Tween).is_valid() and (tw as Tween).is_running() and guard < 200:
		(tw as Tween).custom_step(1.0)
		guard += 1


func _chapter_one_done() -> void:
	GameState.set_flag("ward_restored", true)
	GameState.set_flag("chapter_one_complete", true)


func test_legacy_restored_line_without_chapter_one_complete() -> void:
	var ws := _stone()
	GameState.set_flag("ward_restored", true)
	await _read_all(ws)
	assert_eq(_said.size(), 1, "one line")
	assert_true(String(_said[0]).begins_with("Light kept. Home kept. Thank you,"), "legacy restored line: %s" % str(_said))
	assert_eq(String(ws.get_interaction(null)["text"]), "Read the Ward Stone")


func test_invitation_without_ui_decides_nothing() -> void:
	_chapter_one_done()
	var ws := _stone()
	await _read_all(ws)
	assert_true(_said.size() >= 1 and String(_said[0]) == WardStone.CH2_AVAILABLE_LINE, "the new inscription (MP §17): %s" % str(_said))
	assert_true(bool(GameState.get_flag("read_ward_ch2")), "read flag")
	assert_false(bool(GameState.get_flag("ch2_accepted")), "no UI to answer: not accepted")
	assert_eq(_choices.size(), 0, "no choice was made")
	await _read_all(ws)
	assert_eq(String(_said[0]), WardStone.CH2_AVAILABLE_LINE, "offered again")


func test_decline_then_accept() -> void:
	_chapter_one_done()
	var ws := _stone()
	var area_before := Game.area_id
	await _read_all(ws, "stay")
	assert_false(bool(GameState.get_flag("ch2_accepted")), "declined")
	assert_true(_said.has(WardStone.CH2_DECLINE_LINE), "a gentle line: %s" % str(_said))
	assert_eq(_choices, [["ch2_lantern_road", "stay"]])
	# Esc / closing the dialog counts as "not yet".
	await _read_all(ws, "cancel")
	assert_false(bool(GameState.get_flag("ch2_accepted")), "cancel = stay")
	# The choice is offered again next time.
	await _read_all(ws, "follow")
	assert_true(bool(GameState.get_flag("ch2_accepted")), "accepted")
	assert_true(_said.has(WardStone.CH2_AVAILABLE_LINE), "the inscription is read before the choice")
	assert_true(_said.has(WardStone.CH2_REASSURANCE_LINE), "reassurance (MP §17): %s" % str(_said))
	assert_true(_said.has(WardStone.CH2_WAYGATE_LINE), "the waygate has woken")
	assert_true(_hints.filter(func(h): return not String(h).begins_with("quest_")).is_empty(), "no duplicate hint (the ch2_waygate quest step owns the how-to hint): %s" % str(_hints))
	assert_eq(_choices.back(), ["ch2_lantern_road", "follow"])
	assert_false(Game._transitioning, "accepting never starts a trip (no auto-teleport)")
	assert_eq(Game.area_id, area_before, "no travel")


func test_choice_labels_are_the_spec_wording() -> void:
	assert_eq(String(WardStone.CHOICE_FOLLOW[1]), "Follow the lantern road")
	assert_eq(String(WardStone.CHOICE_STAY[1]), "Stay a little longer")
	assert_eq(WardStone.CH2_AVAILABLE_LINE, "A light well kept reaches farther than its keeper knows. There are lanterns beyond these woods. Tonight, one has answered.")
	assert_eq(WardStone.CH2_REASSURANCE_LINE, "Your hearth is safe. No road you follow shall unmake it.")
	assert_eq(WardStone.CH2_RETURN_LINE % "Krystal", "Light kept. Roads found. Welcome home, Krystal.")


func test_menu_lists_only_what_applies() -> void:
	_chapter_one_done()
	GameState.set_flag("ch2_accepted", true)
	var ws := _stone()
	var ids := func() -> Array: return (ws.menu_options() as Array).map(func(o: Array) -> String: return String(o[0]))
	assert_eq(ids.call(), ["read", "look", "close"], "fresh Chapter Two")
	GameState.set_flag("ch2_arch_commons", true)
	assert_eq(ids.call(), ["read", "look", "road", "close"], "Lantern Road once an arch is lit")
	GameState.set_flag("ch2_homecoming", true)
	assert_eq(ids.call(), ["read", "look", "road", "celebrate", "close"], "celebrate after the homecoming")
	GameState.set_flag("chapter_two_complete", true)
	assert_eq(ids.call(), ["read", "look", "road", "close"], "no second celebration")


func test_menu_read_and_look() -> void:
	_chapter_one_done()
	GameState.set_flag("ch2_accepted", true)
	var ws := _stone()
	await _read_all(ws, "read")
	assert_true(_said.size() >= 2 and String(_said[0]).begins_with("Light kept. Home kept. Thank you,"), "thanks: %s" % str(_said))
	assert_true(_said.has(WardStone.CH2_REASSURANCE_LINE), "reassurance")
	assert_true(_said.has(WardStone.CH2_WAYGATE_LINE), "waygate reminder while broken")
	GameState.set_flag("ch2_waygate_repaired", true)
	await _read_all(ws, "read")
	assert_false(_said.has(WardStone.CH2_WAYGATE_LINE), "no reminder once repaired")
	# No UI answer -> the default is reading.
	await _read_all(ws)
	assert_true(_said.has(WardStone.CH2_REASSURANCE_LINE), "reading is the default")
	_notes.clear()
	await _read_all(ws, "look")
	assert_eq(_notes.size(), 1, "no wardrobe panel yet -> a toast")
	await _read_all(ws, "close")
	assert_eq(_said.size(), 0, "close does nothing")


func test_homecoming_and_return_line() -> void:
	_chapter_one_done()
	GameState.set_flag("ch2_accepted", true)
	GameState.set_flag("ch2_waygate_repaired", true)
	GameState.set_flag("ch2_choir_defeated", true)
	var ws := _stone()
	await _read_all(ws, "read")
	assert_true(bool(GameState.get_flag("ch2_homecoming")), "speaking to the stone after the Choir = the homecoming")
	assert_eq(_said, [WardStone.CH2_RETURN_LINE % GameState.player_name], "the return line (MP §17)")
	assert_eq(ws.forced_choice, "read", "the homecoming reading asked nothing")
	ws.forced_choice = ""
	await _read_all(ws, "read")
	assert_eq(_said, [WardStone.CH2_RETURN_LINE % GameState.player_name], "the return line from then on")
	GameState.set_flag("chapter_two_complete", true)
	await _read_all(ws, "read")
	assert_eq(_said, [WardStone.CH2_RETURN_LINE % GameState.player_name], "after Chapter Two too")


## The heartseed branch and the legacy warning still work (and keep their arachnophobia wording);
## none of the new lines mention anything spider-like in either setting.
func test_legacy_branches_and_arachnophobia() -> void:
	var saved: bool = bool(Settings.get_value("arachnophobia"))
	var ws := _stone()
	GameState.give_item("heartseed", 1)
	assert_eq(String(ws.get_interaction(null)["text"]), "Return the Heartseed")
	GameState.take_item("heartseed", 1)
	for arachno in [false, true]:
		Settings.set_value("arachnophobia", arachno)
		for line in [WardStone.CH2_AVAILABLE_LINE, WardStone.CH2_REASSURANCE_LINE, WardStone.CH2_RETURN_LINE,
				WardStone.CH2_DECLINE_LINE, WardStone.CH2_WAYGATE_LINE]:
			var l := String(line).to_lower()
			assert_false(l.contains("spider") or l.contains("weav") or l.contains("web"), "nothing spider-like: %s" % line)
	Settings.set_value("arachnophobia", saved)
