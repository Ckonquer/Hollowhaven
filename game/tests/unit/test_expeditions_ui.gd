extends "res://tests/test_case.gd"
## Lanternwake Expeditions board + panel (module D2), instanced directly (the panel is not registered in the UI
## root yet): the board opens the expedition panel when the UI offers it and keeps the Optional journal as its
## second option (and as the fallback); the panel lists the three routes, shows difficulty (words + pips),
## route, who may be met and reward types BEFORE starting, refuses closed routes, starts a run, offers the
## Lantern Road to a lit arch, sets a run aside in two presses (free) and shows the last outing.

const Ex := preload("res://src/expeditions/expeditions.gd")
const Data := preload("res://data/expeditions.gd")
const PanelScript := preload("res://src/ui/panels/expedition_panel.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const Journal := preload("res://src/ui/panels/journal_panel.gd")

const UNLOCKS := ["ch2_orchard_restored", "ch2_quarry_restored", "ch2_manor_restored"]


class FakeUi extends Node:
	var offer := true
	var opened: Array = []

	func has_panel(n: String) -> bool:
		return offer and n == "expedition"

	func open(n: String, a: Dictionary = {}) -> void:
		opened.append([n, a])


var _panel: Control
var _area: Node3D
var _saved_ui: Node
var _was_listening := false
var _arachno: Variant = false


func before_each() -> void:
	fresh_state()
	_was_listening = Ex.is_listening()
	_saved_ui = Game.ui
	_arachno = Settings.values.get("arachnophobia", false)


func after_each() -> void:
	Game.ui = _saved_ui
	Settings.values["arachnophobia"] = _arachno
	if not _was_listening:
		Ex.shutdown()
	if is_instance_valid(_panel):
		_panel.queue_free()
	if is_instance_valid(_area):
		_area.queue_free()
	await wait_frames(2)


func _open(args: Dictionary = {}) -> Control:
	_panel = PanelScript.new()
	_panel.setup(args)
	add_child(_panel)
	await wait_frames(1)
	return _panel


func _unlock_all() -> void:
	for f in UNLOCKS:
		GameState.flags[f] = true


func _board() -> Node:
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	return Factory.spawn_structure(_area, GameState.add_structure("expedition_board", Vector3(1, 0, 0.5), 0))


# --- Board ---------------------------------------------------------------------------------------------------------

func test_the_board_opens_expeditions_and_keeps_the_optional_journal() -> void:
	var b := _board()
	var jargs: Dictionary = b.panel_args()
	var tab := String(jargs["tab"])
	assert_eq(String(Journal.TAB_ALIASES.get(tab, tab)), "optional", "the second option is the journal's Optional tab")
	var ui := FakeUi.new()
	add_child(ui)
	Game.ui = ui
	assert_eq(b.target_panel(), "expedition")
	b.interact(null)
	assert_eq(ui.opened.size(), 1)
	assert_eq(String(ui.opened[0][0]), "expedition", "the board opens the expedition list")
	ui.offer = false
	assert_eq(b.target_panel(), "journal", "without the panel registered it falls back to the journal")
	b.interact(null)
	assert_eq(String(ui.opened[1][0]), "journal")
	assert_eq(String((ui.opened[1][1] as Dictionary)["tab"]), "optional")
	assert_true(bool(b.get_interaction(null)["enabled"]))
	_unlock_all()
	assert_true(Ex.start("orchard_patrol", 4))
	assert_true(String(b.get_interaction(null)["text"]).contains("under way"))
	assert_eq(String(b.expedition_args()["template"]), "orchard_patrol", "the board opens on the running route")
	ui.queue_free()


# --- Panel ---------------------------------------------------------------------------------------------------------

func test_panel_lists_the_three_routes_and_refuses_closed_ones() -> void:
	var p := await _open()
	assert_eq(p.card_ids(), Data.ORDER)
	assert_true(p.start_btn.disabled, "a closed route cannot be started")
	assert_true(p.detail_text().contains(String(Data.TEMPLATES[p.selected]["requires_text"])), "says why it is closed")
	assert_false(p.start_selected())
	assert_false(Ex.is_active())


func test_panel_shows_difficulty_route_foes_and_reward_types_before_starting() -> void:
	_unlock_all()
	var p := await _open()
	for id in Data.ORDER:
		p.select(id)
		var t: Dictionary = Data.TEMPLATES[id]
		var txt: String = p.detail_text()
		assert_true(txt.contains(String(t["name"])))
		var diff: Dictionary = Data.DIFFICULTIES[String(t["difficulty"])]
		assert_true(txt.contains(String(diff["name"])), "%s difficulty in words" % id)
		assert_true(txt.contains("of 3"), "and as lantern pips with a count")
		for s in t["stops"]:
			assert_true(txt.contains(String(s["name"])), "route lists %s" % s["name"])
		assert_true(txt.contains(String(t["cache"]["name"])))
		for r in t["reward_types"]:
			assert_true(txt.contains(String(r)), "reward type shown: %s" % r)
		for e in Ex.enemy_types(id):
			assert_true(txt.contains(ItemDB.enemy_display_name(String(e))), "%s may be met" % e)
		assert_false(p.start_btn.disabled)
	assert_true(p.status_text().contains("No expedition"))


func test_panel_starts_travels_and_sets_aside_in_two_presses() -> void:
	_unlock_all()
	GameState.give_item("candy", 3)
	var p := await _open({"template": "quarry_circuit"})
	assert_eq(p.selected, "quarry_circuit", "args preselect a route")
	assert_true(p.start_selected())
	assert_true(Ex.is_active())
	assert_false(p.start_btn.visible, "one run at a time")
	assert_true(p.abandon_btn.visible)
	assert_true(p.status_text().contains("Quarry Circuit"))
	assert_false(p.travel_btn.visible, "the quarry arch is not lit yet")
	GameState.flags["ch2_arch_quarry"] = true
	p.refresh()
	assert_true(p.travel_btn.visible)
	assert_eq(p.travel_arch(), "quarry")
	assert_true(p.travel_btn.text.contains("Ashbell Quarry"))
	var inv := str(GameState.inventory.to_array())
	assert_false(p.press_abandon(), "the first press only asks")
	assert_true(Ex.is_active())
	assert_true(p.abandon_btn.text.contains("nothing is lost"))
	assert_true(p.press_abandon())
	assert_false(Ex.is_active())
	assert_eq(str(GameState.inventory.to_array()), inv, "setting it aside is free")
	assert_true(p.start_btn.visible)


## Setting a run aside while its cache waits forfeits that cache: the confirm and the toast say so (never
## "nothing is lost" there), and the run still ends without taking anything she carries.
func test_setting_aside_at_the_cache_says_the_cache_stays_closed() -> void:
	_unlock_all()
	var p := await _open({"template": "orchard_patrol"})
	assert_true(p.start_selected())
	for i in Ex.stop_count("orchard_patrol"):
		var a := Ex.active()
		var s: Dictionary = Ex.current_plan()["stops"][int(a["stop"])]
		for e in s["enemies"]:
			assert_true(Ex.record_defeat("orchard_patrol", int(a["run"]), int(a["stop"]), String(e)))
	assert_true(Ex.in_cache_phase())
	var toasts: Array = []
	var rec := func(t: String, _k: String) -> void: toasts.append(t)
	Events.notify.connect(rec)
	var inv := str(GameState.inventory.to_array())
	assert_false(p.press_abandon(), "the first press only asks")
	assert_true(p.abandon_btn.text.contains("cache stays closed"), "honest about the waiting cache")
	assert_false(p.abandon_btn.text.contains("nothing is lost"))
	assert_true(p.press_abandon())
	Events.notify.disconnect(rec)
	assert_false(Ex.is_active())
	assert_eq(Ex.completions("orchard_patrol"), 0, "no reward without opening the cache")
	assert_eq(str(GameState.inventory.to_array()), inv, "nothing she carries is taken")
	assert_true(toasts.any(func(t: String) -> bool: return t.contains("cache stays closed")), "the toast says so too")
	# Mid-route (no cache earned yet) the ordinary wording stays.
	assert_true(p.start_selected())
	assert_false(p.press_abandon())
	assert_true(p.abandon_btn.text.contains("nothing is lost"))


func test_panel_shows_the_last_outing_and_follows_state_changes() -> void:
	_unlock_all()
	var p := await _open()
	assert_true(Ex.start("orchard_patrol", 8))
	assert_true(p.status_text().contains("Under way"), "Events.objectives_changed refreshes the panel")
	for i in Ex.stop_count("orchard_patrol"):
		var a := Ex.active()
		var s: Dictionary = Ex.current_plan()["stops"][int(a["stop"])]
		for e in s["enemies"]:
			Ex.record_defeat("orchard_patrol", int(a["run"]), int(a["stop"]), String(e))
	assert_true(p.status_text().contains("open the harvest crate"))
	assert_false(Ex.complete().is_empty())
	assert_true(p.status_text().contains("Last outing"))
	assert_true(p.status_text().contains(ItemDB.display_name("candy")))
	p.select("orchard_patrol")
	assert_true(p.detail_text().contains("Completed 1 time"))


func test_panel_rebuilds_names_when_arachnophobia_changes() -> void:
	_unlock_all()
	var p := await _open()
	Settings.values["arachnophobia"] = true
	Events.settings_changed.emit("arachnophobia")
	for e in Ex.enemy_types(p.selected):
		assert_true(p.detail_text().contains(ItemDB.enemy_display_name(String(e))))
	assert_false(p.detail_text().to_lower().contains("spider"))
	assert_eq(PanelScript.JOURNAL_ARGS["tab"], "optional")
