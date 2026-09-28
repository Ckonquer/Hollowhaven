extends "res://tests/test_case.gd"
## UI root integration (headless): panels open/close with pausing and the UI stack, Esc closes the
## top panel first, hotkeys switch panels, every panel builds, hints show once per id, toasts
## aggregate pickups, the tracker follows the quest, and the death / chapter overlays behave.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const PausePanel := preload("res://src/ui/panels/pause_panel.gd")
const InventoryPanel := preload("res://src/ui/panels/inventory_panel.gd")
const TitleScreen := preload("res://src/ui/title_screen.gd")
const CompanionPanel := preload("res://src/ui/panels/companion_panel.gd")
const JournalPanel := preload("res://src/ui/panels/journal_panel.gd")

var ui: CanvasLayer
var _mode_before := ""


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_mode_before = Game.mode
	Game.mode = "playing"
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func after_each() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _key(action: String) -> InputEventKey:
	var ev := InputEventKey.new()
	var evs := InputMap.action_get_events(action)
	var src: InputEventKey = evs[0]
	ev.physical_keycode = src.physical_keycode
	ev.pressed = true
	return ev


func test_open_close_pauses_and_tracks_ui_stack() -> void:
	ui.open("inventory")
	assert_true(ui.is_open("inventory"))
	assert_true(Game.is_ui_open(), "Game knows a panel is open")
	assert_true(get_tree().paused, "full-screen panel pauses the world")
	ui.close("inventory")
	await wait_frames(1)
	assert_false(ui.is_open("inventory"))
	assert_false(Game.is_ui_open())
	assert_false(get_tree().paused, "unpaused after closing")


func test_companion_menu_does_not_pause() -> void:
	ui.open("companion", {"id": "mochi"})
	assert_true(ui.is_open("companion"))
	assert_false(get_tree().paused, "the small companion menu keeps the world running")
	assert_true(Game.is_ui_open())


func test_escape_closes_top_panel_first() -> void:
	ui.open("pause")
	ui.open("settings")
	assert_eq(ui.top_panel(), "settings")
	ui._input(_key("pause"))
	assert_false(ui.is_open("settings"), "Esc closed settings")
	assert_true(ui.is_open("pause"), "pause stays open")
	assert_true(get_tree().paused)
	ui._input(_key("pause"))
	assert_false(ui.is_open("pause"))
	assert_false(get_tree().paused)
	ui._input(_key("pause"))
	assert_true(ui.is_open("pause"), "Esc with nothing open opens pause")


func test_hotkeys_toggle_and_switch_panels() -> void:
	ui._input(_key("inventory"))
	assert_true(ui.is_open("inventory"))
	ui._input(_key("craft"))
	assert_false(ui.is_open("inventory"), "switching closes the previous gameplay panel")
	assert_true(ui.is_open("crafting"))
	ui._input(_key("craft"))
	assert_false(ui.is_open("crafting"), "same key closes it")
	ui._input(_key("help"))
	assert_true(ui.is_open("controls"))
	ui.close_all()
	ui.open("pause")
	ui._input(_key("map"))
	assert_false(ui.is_open("map"), "hotkeys don't open panels over the pause menu")
	ui._input(_key("help"))
	assert_true(ui.is_open("controls"), "the help overlay stacks over the pause menu")
	assert_eq(ui.top_panel(), "controls")
	ui._input(_key("pause"))
	assert_true(ui.is_open("pause") and not ui.is_open("controls"), "Esc returns to the pause menu")
	Game.mode = "dead"
	ui.close_all()
	ui._input(_key("journal"))
	assert_false(ui.is_open("journal"), "no panels while defeated")


func test_every_panel_builds_and_closes() -> void:
	GameState.give_item("wood", 5)
	GameState.give_item("berries", 3)
	GameState.give_item("foreman_key", 1)
	GameState.befriend("mochi")
	GameState.discover_lore("test_note")
	var args := {"storage": {"uid": "s_test"}, "companion": {"id": "mochi"}, "confirm": {"title": "T", "text": "x"}}
	# Chapter Two panels opened by furniture are registered too, and build without args (the Expedition Board's
	# panel and the Music Box's, whose window is 780 wide).
	for n in ["expedition", "music_box"]:
		assert_true(UiRootScript.PANELS.has(n), "%s is a registered panel" % n)
	for name in UiRootScript.PANELS:
		if name == "comfort":
			continue
		ui.open(String(name), args.get(name, {}))
		await wait_frames(2)
		assert_true(ui.is_open(String(name)), "%s opened" % name)
		var p: Control = ui.panels[name]
		assert_true(p.window != null and p.window.size.x > 100.0, "%s has a laid-out window" % name)
		var vp: Vector2 = ui.root.size
		assert_true(p.window.size.x <= vp.x + 1.0 and p.window.size.y <= vp.y + 1.0, "%s fits on screen (%s in %s)" % [name, p.window.size, vp])
		assert_eq(get_tree().paused, UiRootScript.FULLSCREEN.has(name), "%s pauses the world only when full-screen" % name)
		if name == "music_box":
			assert_true(p.window.size.x >= 779.0, "music box window is 780 wide (%s)" % p.window.size)
		ui.close(String(name))
		await wait_frames(1)
		assert_false(ui.is_open(String(name)))
	assert_false(get_tree().paused)


func test_hints_show_once_and_respect_setting() -> void:
	var hints: Control = ui.hud.hints
	var old_hints: Variant = Settings.get_value("show_hints")
	Settings.values["show_hints"] = true
	assert_true(hints.on_hint("t_chop", "Press {attack} to chop."), "first time shows")
	assert_true(bool(GameState.get_flag("hint_t_chop")), "remembered in GameState flags")
	assert_false(hints.on_hint("t_chop", "Press {attack} to chop."), "never repeats")
	# persists through a save round trip
	var d := GameState.to_dict()
	GameState.from_dict(d)
	assert_false(hints.on_hint("t_chop", "again"), "still remembered after loading")
	Settings.values["show_hints"] = false
	assert_false(hints.on_hint("t_new", "Hidden"), "disabled hints are not shown")
	assert_false(bool(GameState.get_flag("hint_t_new")), "and not marked as seen")
	Settings.values["show_hints"] = old_hints
	var txt := String(hints.format_hint("Press {interact}", Callable(UiUtil, "settings_label")))
	assert_true(txt.contains(Settings.action_label("interact")), txt)
	assert_false(txt.contains("{interact}"))


func test_pickups_aggregate_into_one_toast() -> void:
	var toasts: Control = ui.toasts
	GameState.give_item("wood", 1)
	GameState.give_item("wood", 1)
	GameState.give_item("wood", 2)
	assert_eq(toasts.model.entries.size(), 1)
	assert_eq(int(toasts.model.entries[0]["count"]), 4)
	assert_eq(toasts.views.size(), 1, "one toast on screen")
	GameState.give_item("foreman_key", 1)
	var mentions := 0
	for e in toasts.model.entries:
		assert_ne(String(e["key"]), "item:foreman_key", "key items never show as '+1' pickups")
		if String(e["text"]).contains(ItemDB.display_name("foreman_key")):
			mentions += 1
			assert_eq(String(e["item"]), "foreman_key", "key item toast carries its icon")
	assert_eq(mentions, 1, "exactly one toast for the key item (notify is merged)")


func test_tracker_follows_the_quest() -> void:
	var tr: Control = ui.hud.tracker
	await wait_frames(1)
	assert_true(tr.visible)
	assert_eq(tr.title_l.text, String(GameState.quests.current_step()["title"]))
	GameState.set_flag("read_ward_intro", true)
	GameState.quests.evaluate()
	await wait_frames(1)
	assert_eq(tr.title_l.text, String(GameState.quests.current_step()["title"]), "updates on objectives_changed")


func test_death_overlay_ends_on_black() -> void:
	var t0 := Time.get_ticks_msec()
	await ui.show_death()
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	assert_true(secs > 1.8 and secs < 4.0, "about 2.5 s (%.2f)" % secs)
	assert_almost(ui.fade_rect.color.a, 1.0, 0.01, "respawn happens under black")
	await ui.fade_in(0.1)
	assert_almost(ui.fade_rect.color.a, 0.0, 0.01)


func test_chapter_card_appears_and_leaves() -> void:
	ui.show_chapter_card("Chapter One", "The Dimming Ward")
	await wait_frames(1)
	assert_eq(ui.overlay_layer.get_child_count(), 1)
	var card: Node = ui.overlay_layer.get_child(0)
	card.hold = 0.0
	await card.finished
	await wait_frames(1)
	assert_eq(ui.overlay_layer.get_child_count(), 0, "card frees itself")


func test_pure_panel_helpers() -> void:
	assert_eq(PausePanel.unstuck_spawn("surface", {"respawn_area": "surface", "respawn_spawn": "bed"}), "bed")
	assert_eq(PausePanel.unstuck_spawn("surface", {"respawn_area": "surface", "respawn_spawn": "mine_exit"}), "haven_respawn")
	assert_eq(PausePanel.unstuck_spawn("surface", {"respawn_area": "below", "respawn_spawn": "lantern_2"}), "haven_respawn")
	assert_eq(PausePanel.unstuck_spawn("below", {"respawn_area": "below", "respawn_spawn": "lantern_2"}), "lantern_2")
	assert_eq(PausePanel.unstuck_spawn("below", {"respawn_area": "surface", "respawn_spawn": "bed"}), "mine_entry")
	assert_eq(InventoryPanel.use_action("berries"), "Eat")
	assert_eq(InventoryPanel.use_action("workbench"), "Place in the Haven")
	assert_eq(InventoryPanel.use_action("stone"), "")
	assert_eq(TitleScreen.continue_text({"meta": {"day": 4, "step_title": "A Timid Friend", "play_seconds": 1500.0}}), "Day 4  ·  A Timid Friend  ·  25 min played")
	assert_eq(TitleScreen.continue_text({}), "")
	assert_eq(CompanionPanel.status_text("lumi"), "Not yet befriended")
	for id in ItemDB.creature_ids():
		assert_true(JournalPanel.unmet_hint(String(id)).length() > 10)


func test_full_screen_layers_cover_the_screen() -> void:
	# The damage vignette / screen flash and the quest banner layer must span the whole canvas
	# (a zero-sized layer silently hides every flash and pushes the banner off-screen).
	await wait_frames(1)
	var vp: Vector2 = ui.root.size
	assert_true(vp.x > 100.0, "root laid out")
	var fx: Control = ui.hud.fx
	assert_true(fx.size.distance_to(vp) < 1.0, "screen fx covers the screen (%s vs %s)" % [fx.size, vp])
	assert_true((fx.vignette as Control).size.distance_to(vp) < 1.0, "vignette covers the screen (%s)" % (fx.vignette as Control).size)
	assert_true((fx.flash as Control).size.distance_to(vp) < 1.0, "flash covers the screen (%s)" % (fx.flash as Control).size)
	var qb: Control = ui.quest_banner
	assert_true(qb.size.distance_to(vp) < 1.0, "quest banner layer covers the screen (%s)" % qb.size)
	qb.show_text("New goal: A Timid Friend")
	await wait_frames(2)
	var p: Control = qb.panel
	assert_true(p.position.x > 0.0 and p.position.x + p.size.x < vp.x, "banner centred on screen (x=%.0f w=%.0f)" % [p.position.x, p.size.x])
	assert_almost(p.position.x + p.size.x * 0.5, vp.x * 0.5, 2.0, "banner centred")
	# a screen flash really shows (softly capped) and fades
	Events.screen_flash.emit(Color(1, 1, 1, 1), 0.4)
	await wait_seconds(0.08)
	var a: float = (fx.flash as ColorRect).color.a
	assert_true(a > 0.05 and a <= fx.MAX_FLASH_ALPHA + 0.001, "flash visible but capped (%.2f)" % a)


func test_quest_banner_waits_for_menus_and_toasts_stay_under_them() -> void:
	assert_true(ui.top_layer.get_index() < ui.panel_layer.get_index(), "toasts/banner are drawn under menus")
	ui.open("inventory")
	ui.quest_banner.show_text("New goal: A Timid Friend")
	await wait_frames(2)
	assert_false(ui.quest_banner.panel.visible, "no banner hidden behind an open menu")
	ui.close("inventory")
	await wait_frames(3)
	assert_true(ui.quest_banner.panel.visible, "queued banner plays once the menu closes")
	assert_eq(ui.quest_banner.label.text, "A Timid Friend")


func test_overlapping_fades_never_leave_a_caller_waiting() -> void:
	# e.g. the bed fades out, then Krystal is defeated and the death screen fades too: the first
	# caller must still resume (Game.load_area awaiting a killed tween would softlock the game).
	var state := {"first_done": false}
	var first := func() -> void:
		await ui.fade_out(0.6)
		state["first_done"] = true
	first.call()
	await wait_frames(2)
	await ui.fade_in(0.1)
	await wait_frames(2)
	assert_true(bool(state["first_done"]), "the interrupted fade_out returned")
	assert_almost(ui.fade_rect.color.a, 0.0, 0.01, "the newer fade wins")
	assert_eq(ui.fade_rect.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks pass again after fading in")
	await ui.fade_out(0.0)
	assert_almost(ui.fade_rect.color.a, 1.0, 0.01, "instant fade")
	await ui.fade_in(0.0)
	assert_almost(ui.fade_rect.color.a, 0.0, 0.01)


func test_confirm_returns_the_chosen_button() -> void:
	var state := {"choice": "<none>"}
	var run := func() -> void:
		state["choice"] = await ui.confirm("Quit?", "Sure?", [["save", "Save", "AccentButton"], ["quit", "Quit", ""]])
	run.call()
	await wait_frames(2)
	assert_true(ui.is_open("confirm"), "confirm card shown")
	assert_true(get_tree().paused, "confirm pauses like a menu")
	ui.panels["confirm"]._choose("quit")
	await wait_frames(2)
	assert_eq(String(state["choice"]), "quit", "confirm() returns the chosen id")
	assert_false(ui.is_open("confirm"), "card closed after choosing")
	# Esc / close button -> "cancel"
	state["choice"] = "<none>"
	run.call()
	await wait_frames(2)
	ui._input(_key("pause"))
	await wait_frames(2)
	assert_eq(String(state["choice"]), "cancel", "dismissing the card answers cancel")
	assert_false(get_tree().paused)


func test_ending_is_awaitable_and_skippable() -> void:
	var state := {"done": false}
	var run := func() -> void:
		await ui.show_ending()
		state["done"] = true
	run.call()
	await wait_frames(2)
	var e: Control = ui._ending
	assert_not_null(e, "ending overlay shown")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SPACE
	k.pressed = true
	e._input(k)
	assert_true(int(e._phase) < 3, "not skippable in the first seconds")
	await wait_seconds(4.2)
	e._input(k)
	assert_eq(int(e._phase), 3, "any key skips to 'Continue exploring your Haven'")
	assert_false(bool(state["done"]), "still waiting for the player")
	e._finish()
	await wait_seconds(1.0)
	assert_true(bool(state["done"]), "show_ending returns after Continue")
	assert_null(ui._ending)


## Presses and releases a key through the real input pipeline (ui_root._input, then the GUI).
func _push_key(code: int) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)


## Keyboard crafting: the selection follows the focused recipe row, so Enter on a row the player arrowed
## to crafts THAT recipe, never the one selected before (Enter used to craft the old selection).
func test_crafting_enter_crafts_the_recipe_row_with_keyboard_focus() -> void:
	GameState.give_item("wood", 20)
	GameState.give_item("stone", 10)
	GameState.give_item("fiber", 10)
	ui.open("crafting", {"station": "hand"})
	await wait_frames(3)
	var panel: Control = ui.panels["crafting"]
	assert_eq(String(panel._selected), "stone_axe", "first craftable recipe selected at open")
	var axe_row: Button = panel._rows["stone_axe"]
	var pick_row: Button = panel._rows["stone_pickaxe"]
	axe_row.grab_focus()
	await wait_frames(1)
	_push_key(KEY_DOWN)
	await wait_frames(1)
	assert_true(pick_row.has_focus(), "Down moves to the next recipe")
	assert_eq(String(panel._selected), "stone_pickaxe", "the selection follows keyboard focus")
	_push_key(KEY_ENTER)
	await wait_frames(2)
	assert_eq(GameState.count_item("stone_pickaxe"), 1, "Enter crafted the focused recipe")
	assert_eq(GameState.count_item("stone_axe"), 0, "and not the recipe selected before")
	assert_true(pick_row.has_focus(), "focus stays on the recipe after crafting")


## Enter on a focused station tab switches to that tab (the panel no longer swallows it to craft).
func test_crafting_enter_on_a_station_tab_switches_tab() -> void:
	GameState.give_item("wood", 20)
	GameState.give_item("stone", 10)
	GameState.give_item("fiber", 10)
	ui.open("crafting", {"station": "hand"})
	await wait_frames(3)
	var panel: Control = ui.panels["crafting"]
	var tab: Button = panel._tab_buttons["workbench"]
	tab.grab_focus()
	await wait_frames(1)
	_push_key(KEY_ENTER)
	await wait_frames(2)
	assert_eq(String(panel.filter), "workbench", "Enter on a station tab switches to it")
	assert_eq(GameState.count_item("stone_axe"), 0, "and crafts nothing")


## With nothing craftable the keyboard still lands in the recipe list and can browse it.
func test_crafting_keyboard_reaches_the_list_when_nothing_is_craftable() -> void:
	ui.open("crafting", {"station": "hand"})
	await wait_frames(3)
	var panel: Control = ui.panels["crafting"]
	assert_true(panel.craft_btn.disabled, "nothing can be crafted")
	var rows: Array = (panel._rows as Dictionary).values()
	var fo := get_viewport().gui_get_focus_owner()
	assert_true(fo != null and rows.has(fo), "a recipe row has focus when the panel opens")
	_push_key(KEY_DOWN)
	await wait_frames(1)
	var fo2 := get_viewport().gui_get_focus_owner()
	assert_true(fo2 != null and fo2 != fo and rows.has(fo2), "Down moves through the recipes")
	assert_true(fo2 != null and panel._rows.get(String(panel._selected)) == fo2, "the detail card follows the focused recipe")


## Menus never open while a fade runs: the bed's sleep, a fall recovery and "Return to the Haven" fade
## with mode still "playing", and the fade is drawn above the panels (a menu would sit hidden under it).
func test_menus_stay_shut_during_any_fade() -> void:
	ui.fade_out(0.6)
	await wait_seconds(0.1)
	assert_true(ui.fade_rect.color.a < 0.5, "early in the fade (a=%.2f)" % ui.fade_rect.color.a)
	ui._input(_key("pause"))
	assert_false(ui.is_open("pause"), "Esc early in a fade opens nothing")
	ui._input(_key("inventory"))
	assert_false(ui.is_open("inventory"), "a menu hotkey early in a fade opens nothing")
	await ui.fade_in(0.0)
	ui._input(_key("pause"))
	assert_true(ui.is_open("pause"), "Esc works again once the fade is over")
	ui.close_all()
	# Closing is still allowed mid-fade.
	ui.open("inventory")
	ui.fade_out(0.6)
	await wait_seconds(0.1)
	ui._input(_key("inventory"))
	assert_false(ui.is_open("inventory"), "a menu's own hotkey still closes it during a fade")
	await ui.fade_in(0.0)


## The companion menu doesn't pause the world but holds Krystal still, so it closes when she is hurt.
func test_companion_menu_closes_when_krystal_is_hurt() -> void:
	GameState.befriend("lumi")
	ui.open("companion", {"id": "lumi"})
	await wait_frames(2)
	assert_true(ui.is_open("companion"), "menu open")
	Events.player_damaged.emit(8.0, null)
	await wait_frames(1)
	assert_false(ui.is_open("companion"), "a hit closes the companion menu")
	assert_false(Game.is_ui_open(), "and gives Krystal her controls back")


## Chapter Two ending (MP section 17): awaitable, the "chapter_two" EndingScreen variant, and while it shows it
## blocks input, the UI hotkeys and the wardrobe notice exactly like the Chapter One ending.
func test_chapter_two_ending_is_awaitable_and_blocks_like_the_first() -> void:
	var state := {"done": false, "second": false}
	var run := func() -> void:
		await ui.show_chapter_two_ending()
		state["done"] = true
	run.call()
	await wait_frames(2)
	var e: Control = ui._ending
	assert_not_null(e, "ending overlay shown")
	if e == null:
		return
	assert_true(bool(e.call("is_chapter_two")), "the Chapter Two variant")
	assert_eq(e.get_parent(), ui.overlay_layer, "on the overlay layer")
	assert_true(bool(ui.hud.is_cinematic()), "gameplay HUD hidden")
	ui._input(_key("pause"))
	assert_false(ui.is_open("pause"), "Esc opens nothing during the ending")
	ui._input(_key("inventory"))
	assert_false(ui.is_open("inventory"), "UI hotkeys are blocked during the ending")
	GameState.wardrobe["notice_shown"] = false
	assert_false(ui.wardrobe_notice_safe_now(), "no wardrobe notice over the ending")
	assert_false(ui.tick_wardrobe_notice(5.0), "the notice waits")
	# A second call (e.g. a repeated trigger) waits for the same ending instead of stacking another.
	var run2 := func() -> void:
		await ui.show_chapter_two_ending()
		state["second"] = true
	run2.call()
	await wait_frames(2)
	assert_eq(ui._ending, e, "still the one ending")
	assert_eq(ui.overlay_layer.get_child_count(), 1, "one overlay")
	e.call("_finish")
	await wait_seconds(1.0)
	assert_true(bool(state["done"]), "show_chapter_two_ending returns after Continue")
	assert_true(bool(state["second"]), "the waiting second call returns too")
	assert_null(ui._ending)
	assert_false(bool(ui.hud.is_cinematic()), "HUD back for free play")


class FakeTrial extends Node3D:
	var left := 0
	var paused_when_left := true

	func leave() -> void:
		left += 1
		paused_when_left = get_tree().paused


## Pause menu inside an Echo Trial (lead decision, MP section 15): the option reads "Leave the trial" and leaves
## THROUGH the trial (its leave(), else the saved origin), never to the trial's own entry pad.
func test_pause_leaves_an_echo_trial_through_the_trial() -> void:
	assert_eq(PausePanel.unstuck_label("echo_trial"), "Leave the trial")
	assert_true(PausePanel.unstuck_tooltip("echo_trial").contains("checkpoint"), "tooltip says where it goes")
	for a in ["hallowmere_reach", "tobin_annex", "moonveil_manor", "hushed_works"]:
		assert_eq(PausePanel.unstuck_label(a), "Return to safety", a)
	assert_eq(PausePanel.unstuck_label("surface"), "Return to the Haven", "other areas unchanged")
	assert_eq(PausePanel.unstuck_label("below"), "Return to last lantern")
	assert_eq(PausePanel.trial_exit_destination({"respawn_area": "moonveil_manor", "respawn_spawn": "manor_ballroom"}),
		{"area": "moonveil_manor", "spawn": "manor_ballroom"}, "the origin checkpoint")
	assert_eq(PausePanel.trial_exit_destination({"respawn_area": "echo_trial", "respawn_spawn": "trial_start"}),
		{"area": "surface", "spawn": "haven_respawn"}, "never back into a trial")
	assert_eq(PausePanel.trial_exit_destination({}), {"area": "surface", "spawn": "haven_respawn"})
	var trial := FakeTrial.new()
	add_child(trial)
	var old_area: Node = Game.area
	var old_id := Game.area_id
	Game.area = trial
	Game.area_id = "echo_trial"
	ui.open("pause")
	await wait_frames(2)
	var pp: Control = ui.panels["pause"]
	assert_eq(String(pp.unstuck_btn.text), "Leave the trial")
	pp.call("_unstuck")
	await wait_frames(2)
	assert_true(ui.is_open("confirm"), "asks first")
	ui.panels["confirm"]._choose("cancel")
	await wait_frames(2)
	assert_eq(trial.left, 0, "Stay keeps her in the trial")
	assert_true(ui.is_open("pause"), "back on the pause menu")
	pp.call("_unstuck")
	await wait_frames(2)
	ui.panels["confirm"]._choose("go")
	await wait_frames(3)
	assert_eq(trial.left, 1, "left through the trial's own exit")
	assert_false(trial.paused_when_left, "menus closed (world unpaused) before leaving")
	assert_false(ui.is_open("pause"), "pause menu closed")
	Game.area = old_area
	Game.area_id = old_id
	trial.queue_free()
	await wait_frames(1)


## The Expedition Board's panel is full-screen (pauses); the Music Box's never pauses (a paused tree would silence
## its song preview), holds Krystal like the companion menu, and the gameplay hotkeys may switch away from both.
func test_expedition_and_music_box_panels_are_registered() -> void:
	assert_true(ui.has_panel("expedition"), "the board finds its panel")
	assert_true(ui.has_panel("music_box"), "the music box finds its panel")
	assert_true(UiRootScript.FULLSCREEN.has("expedition"), "expeditions pause the world")
	assert_false(UiRootScript.FULLSCREEN.has("music_box"), "the music box never pauses")
	for n in ["expedition", "music_box"]:
		assert_true(UiRootScript.GAMEPLAY_PANELS.has(n), "hotkeys may switch away from %s" % n)
	ui.open("expedition")
	await wait_frames(2)
	assert_true(ui.is_open("expedition"))
	assert_true(get_tree().paused, "the expedition panel pauses")
	ui._input(_key("map"))
	assert_false(ui.is_open("expedition"), "a hotkey switches away from it")
	assert_true(ui.is_open("map"))
	ui.close_all()
	await wait_frames(1)
	ui.open("music_box")
	await wait_frames(2)
	assert_true(ui.is_open("music_box"))
	assert_false(get_tree().paused, "the music box keeps the world (and its preview) running")
	assert_true(Game.is_ui_open(), "Krystal is held still while it is open")
	ui._input(_key("inventory"))
	assert_false(ui.is_open("music_box"), "a hotkey switches away from it")
	assert_true(ui.is_open("inventory"))
	ui.close_all()
	await wait_frames(1)
	assert_false(get_tree().paused)
	assert_false(Game.is_ui_open())


## Wardrobe hotkey (lead decision D02): action "wardrobe", O by default and rebindable; the same rules as the
## pause menu's Wardrobe button - full-screen, pauses, and only opens in ordinary play.
func test_wardrobe_hotkey_follows_the_pause_menu_rules() -> void:
	assert_eq(String(UiRootScript.HOTKEYS.get("wardrobe", "")), "wardrobe", "the wardrobe action opens the wardrobe panel")
	assert_true(InputMap.has_action("wardrobe"), "the action is installed")
	ui._input(_key("wardrobe"))
	assert_true(ui.is_open("wardrobe"), "the key opens the wardrobe")
	assert_true(get_tree().paused, "and pauses like the pause-menu Wardrobe")
	ui._input(_key("wardrobe"))
	await wait_frames(1)
	assert_false(ui.is_open("wardrobe"), "the same key closes it")
	assert_false(get_tree().paused)
	ui._input(_key("inventory"))
	ui._input(_key("wardrobe"))
	assert_false(ui.is_open("inventory"), "switching closes the backpack")
	assert_true(ui.is_open("wardrobe"), "and opens the wardrobe")
	ui._input(_key("journal"))
	assert_false(ui.is_open("wardrobe"), "other hotkeys switch away from it")
	assert_true(ui.is_open("journal"))
	ui.close_all()
	ui.open("pause")
	ui._input(_key("wardrobe"))
	assert_false(ui.is_open("wardrobe"), "not over the pause menu (it has its own Wardrobe button)")
	ui.close_all()
	await ui.fade_out(0.0)
	ui._input(_key("wardrobe"))
	assert_false(ui.is_open("wardrobe"), "never during a fade")
	await ui.fade_in(0.0)
	for m in ["cutscene", "dead", "loading"]:
		Game.mode = String(m)
		ui._input(_key("wardrobe"))
		assert_false(ui.is_open("wardrobe"), "only in ordinary play (not while %s)" % m)
	Game.mode = "playing"
	ui._input(_key("wardrobe"))
	assert_true(ui.is_open("wardrobe"), "back in play it opens again")


## The F1 overlay lists every UI hotkey and every build-mode key, each group shown exactly once.
func test_controls_overlay_lists_the_hotkeys_and_build_keys() -> void:
	var CP: Script = load("res://src/ui/panels/controls_panel.gd")
	var listed := {}
	for g in CP.GROUPS:
		for item in g[1]:
			listed[String(item[0])] = String(g[0])
	for action in UiRootScript.HOTKEYS:
		assert_true(listed.has(String(action)), "hotkey %s is listed" % action)
	assert_eq(String(listed.get("wardrobe", "")), "Menus", "the wardrobe key sits with the menus")
	for action in ["build", "build_rotate", "build_dismantle", "build_undo", "build_recolor", "build_variant"]:
		assert_eq(String(listed.get(action, "")), "Building", "%s is listed with the building keys" % action)
	var seen: Array = []
	for col in CP.COLUMNS:
		for gi in col:
			assert_false(seen.has(int(gi)), "group %d shown once" % int(gi))
			seen.append(int(gi))
	assert_eq(seen.size(), (CP.GROUPS as Array).size(), "every group has a column")
	ui._input(_key("help"))
	await wait_frames(2)
	var p: Control = ui.panels.get("controls")
	assert_not_null(p, "overlay open")
	if p != null:
		assert_true(_has_label_text(p, "Wardrobe") and _has_label_text(p, "Undo last piece") and _has_label_text(p, "Pumpkin face"), "rows built")
		assert_true(_has_label_text(p, Settings.action_label("build_undo")), "the undo key cap shows its key")


func _has_label_text(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _has_label_text(c, text):
			return true
	return false
