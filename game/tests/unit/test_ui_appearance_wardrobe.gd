extends "res://tests/test_case.gd"
## The in-game wardrobe (headless): registered in the UI root (pauses, hotkey-switchable), reachable from the
## pause menu, the Ward Stone and wardrobe / mirror furniture; edits are worn at once, persist through save
## & load and never touch equipment or items; locked pieces can't be selected and say how to earn them;
## presets and the armor toggle work from the panel; the one-time "wardrobe is ready" notice shows once at a
## safe moment; the unstuck option works (and is labelled) per area; the preview renders in its own world
## and frames Krystal; both screens fit the 1920x1080 canvas.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Wardrobe := preload("res://src/ui/panels/wardrobe_panel.gd")
const PausePanel := preload("res://src/ui/panels/pause_panel.gd")
const Preview := preload("res://src/ui/widgets/avatar_preview.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const Fixtures := preload("res://tests/unit/ch2_save_fixtures.gd")
const WardrobeStructure := "res://src/building/structures/wardrobe.gd"
const StructureFactory := "res://src/building/structure_factory.gd"
const CANVAS := Vector2(1920, 1080)

var ui: CanvasLayer
var _mode_before := ""
var _safe_before := true
var _area_before: Node = null
var _area_id_before := ""
var _ui_before: Node = null
var _player_before: Node3D = null
var _holder: Node3D
var _changed := 0


## A stand-in avatar exposing the appearance API the avatar module adds (recipe (a)/(d)).
class FakeAvatar extends Node3D:
	var appearance: Dictionary = {}
	var driven: bool = true
	var applied: int = 0

	func set_appearance(l: Dictionary) -> void:
		appearance = l
		applied += 1


func _on_changed() -> void:
	_changed += 1


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_changed = 0
	Events.appearance_changed.connect(_on_changed)
	_mode_before = Game.mode
	_safe_before = Game.in_safe_zone
	_area_before = Game.area if is_instance_valid(Game.area) else null
	_area_id_before = Game.area_id
	_ui_before = Game.ui if is_instance_valid(Game.ui) else null
	_player_before = Game.player if is_instance_valid(Game.player) else null
	Game.mode = "playing"
	Game.in_safe_zone = true
	Game.area = null
	Game.area_id = ""
	Game.player = null
	ui = UiRootScript.new()
	add_child(ui)
	_holder = Node3D.new()
	add_child(_holder)
	await wait_frames(2)


func after_each() -> void:
	if Events.appearance_changed.is_connected(_on_changed):
		Events.appearance_changed.disconnect(_on_changed)
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	Game.in_safe_zone = _safe_before
	Game.area = _area_before
	Game.area_id = _area_id_before
	Game.ui = _ui_before
	Game.player = _player_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))
	Preview._script_cache = null
	Preview._script_checked = false
	SaveSystem.delete_test_saves()


func _pause_key() -> InputEventKey:
	var ev := InputEventKey.new()
	var src: InputEventKey = InputMap.action_get_events("pause")[0]
	ev.physical_keycode = src.physical_keycode
	ev.keycode = src.keycode
	ev.pressed = true
	return ev


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _open_wardrobe(args: Dictionary = {}) -> Control:
	ui.open("wardrobe", args)
	await wait_frames(2)
	return ui.panels.get("wardrobe")


## World-space bounds of every visible mesh under `n`.
func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is GeometryInstance3D and (c as GeometryInstance3D).is_visible_in_tree():
			var g := c as GeometryInstance3D
			var b := g.global_transform * g.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func _find_label(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text.contains(text):
		return true
	for c in n.get_children():
		if _find_label(c, text):
			return true
	return false


func test_wardrobe_is_a_registered_fullscreen_gameplay_panel() -> void:
	assert_true(UiRootScript.PANELS.has("wardrobe"))
	assert_true(UiRootScript.FULLSCREEN.has("wardrobe"), "pauses the world")
	assert_true(UiRootScript.GAMEPLAY_PANELS.has("wardrobe"), "hotkeys may switch away from it")
	assert_true(ui.has_panel("wardrobe"))
	assert_false(ui.has_panel("no_such_panel"))
	var w := await _open_wardrobe()
	assert_not_null(w)
	assert_true(get_tree().paused, "the wardrobe pauses")
	assert_true(Game.is_ui_open())
	assert_true(_find_label(w, "Cosmetic only"), "labelled cosmetic only")
	ui._input(_pause_key())
	await wait_frames(1)
	assert_false(ui.is_open("wardrobe"), "Esc closes it")
	assert_false(get_tree().paused)


func test_edits_are_worn_at_once_persist_and_touch_nothing_else() -> void:
	GameState.give_item("wood", 5)
	GameState.give_item("stone_axe", 1)
	var inv: Array = GameState.inventory.to_array().duplicate(true)
	var eq: Dictionary = GameState.equipment.duplicate(true)
	var w := await _open_wardrobe()
	var ed: Control = w.editor
	ed.show_category("hair")
	assert_true(ed.tiles.has("bob"), "hair styles listed")
	(ed.tiles["bob"] as Button).pressed.emit()
	assert_eq(String(GameState.appearance["hair"]), "bob", "worn at once")
	assert_eq(_changed, 1, "appearance_changed")
	assert_true(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)), "A Look of Your Own")
	assert_true((ed.tiles["bob"] as Button).button_pressed, "the chosen tile shows as selected")
	ed.show_category("outfit")
	(ed.tiles["cloud_cardigan"] as Button).pressed.emit()
	assert_eq(String(GameState.appearance["upper"]), "cloud_cardigan")
	assert_eq(String(GameState.appearance["hair"]), "bob", "outfits keep her hair")
	ed.set_channel("accent")
	(ed.tiles["mint"] as Button).pressed.emit()
	assert_eq(String(GameState.appearance["palette"]["accent"]), "mint")
	assert_false(w.undo_btn.disabled, "undo offered after a change")
	assert_eq(GameState.inventory.to_array(), inv, "backpack untouched")
	assert_eq(GameState.equipment, eq, "equipment untouched")
	ui.close("wardrobe")
	await wait_frames(1)
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(String(GameState.appearance["hair"]), "bob", "hair survives save/load")
	assert_eq(String(GameState.appearance["upper"]), "cloud_cardigan")
	assert_eq(String(GameState.appearance["palette"]["accent"]), "mint")
	assert_true(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)))


func test_locked_pieces_show_how_to_earn_and_cannot_be_selected() -> void:
	var w := await _open_wardrobe()
	var ed: Control = w.editor
	ed.set_piece_slot("upper")
	assert_true(ed.tiles.has("witch_blouse"), "locked pieces are listed in the wardrobe")
	var b: Button = ed.tiles["witch_blouse"]
	assert_true(bool(b.get_meta("locked", false)))
	assert_true(b.tooltip_text.contains("How to earn"), b.tooltip_text)
	var before: Dictionary = GameState.appearance.duplicate(true)
	b.pressed.emit()
	assert_eq(String(GameState.appearance["upper"]), String(before["upper"]), "not selected")
	assert_false(b.button_pressed, "the tile does not stay pressed")
	assert_true(String(ed.info.text).contains("Locked"), "the info line explains: %s" % ed.info.text)
	assert_eq(_changed, 0)
	assert_false(ed.choose("palette.primary", "midnight"), "dye colours are locked too")
	assert_false(ed.choose("outfit", "ribbon_witch"))
	# Owning the pattern unlocks it (the Loom calls GameState.unlock_pattern).
	GameState.unlock_pattern("pat_ribbon_witch")
	w.refresh()
	ed.set_piece_slot("upper")
	assert_false(bool((ed.tiles["witch_blouse"] as Button).get_meta("locked", true)))
	assert_true(ed.choose("upper", "witch_blouse"))
	assert_eq(String(GameState.appearance["upper"]), "witch_blouse")


func test_keyboard_switches_categories_and_turns_the_preview() -> void:
	var w := await _open_wardrobe({"category": "hair"})
	var ed: Control = w.editor
	assert_eq(String(ed.category), "hair", "args pick the category")
	ui._input(_key(KEY_E))
	assert_eq(String(ed.category), "hair_color", "E: next category")
	ui._input(_key(KEY_Q))
	ui._input(_key(KEY_Q))
	assert_eq(String(ed.category), "colours", "Q wraps around")
	assert_true(ui.is_open("wardrobe"), "E / Q never leak to the hotkeys")
	var pv: Control = w.preview
	var y0: float = pv.yaw
	ui._input(_key(KEY_COMMA))
	assert_almost(float(pv.yaw), wrapf(y0 + Preview.TURN_STEP, -PI, PI), 0.001, "< turns")
	var f: Control = w.default_focus()
	assert_true(f != null and f is Button, "a tile takes keyboard focus")


## The wardrobe hotkey (O by default, lead decision D02) opens and closes the wardrobe; it never collides with the
## wardrobe's own keys (Q / E switch categories) and typing a preset name never closes the panel.
func test_wardrobe_hotkey_opens_and_closes_it() -> void:
	assert_eq(String(UiRootScript.HOTKEYS.get("wardrobe", "")), "wardrobe")
	var code: int = (InputMap.action_get_events("wardrobe")[0] as InputEventKey).physical_keycode
	assert_false(code == KEY_Q or code == KEY_E, "the hotkey is not a category key")
	ui._input(_key(code))
	await wait_frames(2)
	assert_true(ui.is_open("wardrobe"), "the hotkey opens the wardrobe")
	assert_true(get_tree().paused, "full-screen: the world pauses")
	var w: Control = ui.panels.get("wardrobe")
	var cat := String(w.editor.category)
	ui._input(_key(KEY_E))
	assert_ne(String(w.editor.category), cat, "E still switches category")
	assert_true(ui.is_open("wardrobe"))
	(w._preset_rows[0]["save"] as Button).pressed.emit()
	(w._preset_rows[0]["rename"] as Button).pressed.emit()
	assert_true(w.is_capturing_input(), "renaming a preset")
	ui._input(_key(code))
	assert_true(ui.is_open("wardrobe"), "typing the hotkey's letter into a name never closes the wardrobe")
	w._on_rename_input(_key(KEY_ESCAPE), 0)
	assert_false(w.is_capturing_input())
	ui._input(_key(code))
	await wait_frames(1)
	assert_false(ui.is_open("wardrobe"), "the hotkey closes it again")
	assert_false(get_tree().paused)


func test_presets_from_the_panel() -> void:
	var w := await _open_wardrobe()
	var rows: Array = w._preset_rows
	assert_eq(rows.size(), 3, "three preset slots")
	assert_true((rows[0]["wear"] as Button).disabled, "empty slot: nothing to wear")
	assert_true((rows[1]["save"] as Button).disabled, "fill the first empty slot first")
	(rows[0]["save"] as Button).pressed.emit()
	assert_eq(Wardrobe.Looks.presets().size(), 1)
	assert_eq(String((rows[0]["name"] as Label).text), "Cozy Explorer  ·  Side Braid")
	# Rename through the inline field: typing is captured (no hotkeys), Enter commits.
	(rows[0]["rename"] as Button).pressed.emit()
	assert_true(w.is_capturing_input(), "typing a name is captured")
	var edit: LineEdit = rows[0]["edit"]
	assert_true(edit.visible)
	edit.text = "Sunday best"
	edit.text_submitted.emit(edit.text)
	assert_false(w.is_capturing_input())
	assert_eq(String(Wardrobe.Looks.presets()[0]["name"]), "Sunday best")
	# Esc cancels a rename.
	(rows[0]["rename"] as Button).pressed.emit()
	edit.text = "Nope"
	w._on_rename_input(_key(KEY_ESCAPE), 0)
	assert_false(w.is_capturing_input())
	assert_eq(String(Wardrobe.Looks.presets()[0]["name"]), "Sunday best", "cancelled")
	# Change the look, then wear the preset back.
	w.editor.choose("hair", "high_ponytail")
	assert_eq(String(GameState.appearance["hair"]), "high_ponytail")
	(rows[0]["wear"] as Button).pressed.emit()
	assert_eq(String(GameState.appearance["hair"]), "side_braid", "preset worn")
	assert_eq(String(w.editor.look["hair"]), "side_braid", "the editor follows")


func test_armor_toggle_undo_and_reset() -> void:
	var w := await _open_wardrobe()
	var t: CheckButton = w.armor_btn
	assert_false(t.button_pressed)
	t.button_pressed = true
	assert_true(bool(GameState.wardrobe["show_armor"]), "show equipped armor")
	assert_eq(_changed, 1, "the avatar is told")
	w.editor.choose("hair", "bob")
	w.editor.choose("eyes", "eye_4")
	w._undo()
	assert_true(Wardrobe.Looks.same_look(GameState.appearance, ItemDB.legacy_look()), "undo = the look she came in with")
	assert_true(w.undo_btn.disabled)
	w.editor.choose("hair", "bob")
	w._reset_legacy()
	assert_eq(String(GameState.appearance["hair"]), "side_braid", "Chapter One look")
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_true(bool(GameState.wardrobe["show_armor"]), "the toggle persists")


func test_unknown_ids_are_reported_and_kept() -> void:
	GameState.appearance["upper"] = "future_top"
	var w := await _open_wardrobe()
	assert_true(w.missing_l.visible, "missing styles are reported")
	assert_true(String(w.missing_l.text).contains("(Top)"), "the missing option is named: " + w.missing_l.text)
	assert_eq(Wardrobe.Looks.missing_names(["upper=a", "palette.accent=b", "upper=c", "sparkle=d"]), "Top, Accent colour, Sparkle")
	assert_eq(String(w.editor.look["upper"]), "explorer_jacket", "shown as the safe default")
	w.editor.choose("hair", "bob")
	assert_eq(String(GameState.appearance["upper"]), "future_top", "the saved id survives an edit")
	assert_eq(String(GameState.appearance["hair"]), "bob")


func test_pause_menu_opens_the_wardrobe() -> void:
	ui.open("pause")
	await wait_frames(2)
	var p: Control = ui.panels["pause"]
	assert_not_null(p.wardrobe_btn, "Wardrobe entry in the pause menu")
	p.wardrobe_btn.pressed.emit()
	await wait_frames(2)
	assert_eq(ui.top_panel(), "wardrobe", "opens over the pause menu")
	ui._input(_pause_key())
	await wait_frames(1)
	assert_eq(ui.top_panel(), "pause", "Esc returns to the pause menu")
	assert_true(get_tree().paused)


func test_ward_stone_and_furniture_open_the_wardrobe() -> void:
	Game.ui = ui
	var ws: Node3D = WardStone.new()
	_holder.add_child(ws)
	await ws.choose("look")
	assert_true(ui.is_open("wardrobe"), "Ward Stone 'Change your look'")
	ui.close_all()
	await wait_frames(1)
	# Furniture: the placed piece (through the structure factory, as the Haven spawns it).
	var factory: Script = load(StructureFactory)
	for sid in ["wardrobe", "vanity_mirror"]:
		var sc: Script = factory.call("script_for", sid)
		assert_eq(sc.resource_path, WardrobeStructure, "%s uses the wardrobe script" % sid)
		var n: Node3D = factory.call("create", sid, "")
		_holder.add_child(n)
		assert_eq(n.get_interaction(null), {"text": "Change your look", "enabled": true}, sid)
		assert_true(n.is_in_group("interactable"), sid + " is interactable")
		n.interact(null)
		assert_true(ui.is_open("wardrobe"), sid + " opens the wardrobe")
		ui.close_all()
		await wait_frames(1)


func test_notice_shows_once_at_a_safe_moment() -> void:
	assert_false(ui.wardrobe_notice_enabled, "off in headless runs (driven by hand here)")
	assert_true(ui.wardrobe_notice_pending(), "an older save that never saw it")
	# Not while a menu is open.
	ui.open("inventory")
	for i in 30:
		assert_false(ui.tick_wardrobe_notice(0.25))
	ui.close("inventory")
	await wait_frames(1)
	# Not before a few quiet seconds.
	assert_false(ui.tick_wardrobe_notice(0.25))
	var shown := false
	var ticks := 1
	while not shown and ticks < 40:
		shown = ui.tick_wardrobe_notice(0.25)
		ticks += 1
	assert_true(shown, "shown at a safe moment")
	assert_true(ticks * 0.25 >= UiRootScript.WARDROBE_NOTICE_SAFE_SECONDS, "after %.2f s of quiet play" % (ticks * 0.25))
	await wait_frames(1)
	assert_true(ui.is_open("confirm"), "a dismissible card")
	var card: Control = ui.panels["confirm"]
	assert_eq(String(card.get("text")), "Your wardrobe is ready. You can change your look without starting over.")
	assert_true(bool(GameState.wardrobe["notice_shown"]), "marked shown")
	card._choose("open")
	await wait_frames(2)
	assert_true(ui.is_open("wardrobe"), "its button opens the wardrobe")
	assert_false(ui.is_open("confirm"))
	ui.close_all()
	await wait_frames(1)
	for i in 40:
		assert_false(ui.tick_wardrobe_notice(0.25), "never again")
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	GameState.active = true
	assert_false(ui.wardrobe_notice_pending(), "remembered in the save")


func test_a_chapter_one_save_gets_the_notice_and_keeps_her_classic_look() -> void:
	GameState.give_item("wood", 3)
	var v1: Dictionary = Fixtures.v1_file()
	var path := SaveSystem.save_dir.path_join("slot1.json")
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	GameState.reset()
	assert_true(SaveSystem.load_game(), "the v1 save loads")
	GameState.active = true
	assert_true(Wardrobe.Looks.same_look(GameState.appearance, ItemDB.legacy_look()), "auburn side braid explorer")
	assert_eq(Wardrobe.Looks.missing_ids(), [], "nothing unknown")
	assert_true(ui.wardrobe_notice_pending(), "a Chapter One save is told about the wardrobe")
	var w := await _open_wardrobe()
	assert_false(w.missing_l.visible)
	assert_true(Wardrobe.Looks.same_look(w.editor.look, ItemDB.legacy_look()), "the editor starts from her classic look")
	assert_eq(GameState.count_item("wood"), 3, "the backpack came through")


func test_notice_can_be_dismissed_and_is_skipped_when_already_seen() -> void:
	GameState.wardrobe["notice_shown"] = true
	for i in 40:
		assert_false(ui.tick_wardrobe_notice(0.25), "already shown")
	GameState.wardrobe["notice_shown"] = false
	Game.in_safe_zone = false   # not safe to save here and not in a safe zone: wait
	for i in 40:
		assert_false(ui.tick_wardrobe_notice(0.25), "waits for a safe moment")
	Game.in_safe_zone = true
	var res := {"pick": ""}
	var run := func() -> void:
		res["pick"] = await ui.show_wardrobe_notice()
	run.call()
	await wait_frames(1)
	ui._input(_pause_key())
	await wait_frames(2)
	assert_eq(String(res["pick"]), "cancel", "Esc dismisses")
	assert_false(ui.is_open("wardrobe"))
	assert_false(get_tree().paused)
	assert_true(bool(GameState.wardrobe["notice_shown"]))


## CH2-009: a Chapter One save whose player finds the wardrobe herself (Esc > Wardrobe) before the card is due,
## restyles and saves a preset has been told about it: the card is no longer pending, never appears, the save
## remembers it, and onboarding's ob_wardrobe tip still arms from the same flag.
func test_using_the_wardrobe_first_retires_the_notice() -> void:
	assert_true(ui.wardrobe_notice_pending(), "an older save that never saw it")
	ui.open("pause")
	await wait_frames(2)
	(ui.panels["pause"] as Control).get("wardrobe_btn").pressed.emit()
	await wait_frames(2)
	assert_eq(ui.top_panel(), "wardrobe", "Esc > Wardrobe")
	var w: Control = ui.panels["wardrobe"]
	w.editor.choose("hair", "bob")
	(w._preset_rows[0]["save"] as Button).pressed.emit()
	assert_eq(Wardrobe.Looks.presets().size(), 1, "a preset saved")
	ui.close_all()
	await wait_frames(2)
	assert_true(bool(GameState.wardrobe["notice_shown"]), "using the wardrobe counts as being told about it")
	assert_false(ui.wardrobe_notice_pending(), "the card is no longer due")
	for i in 40:
		assert_false(ui.tick_wardrobe_notice(0.25), "the card never appears")
	assert_false(ui.is_open("confirm"))
	var ob: Node = load("res://src/world/story_ch2/onboarding_hints.gd").new()
	add_child(ob)
	var hints_before: Variant = Settings.values.get("show_hints", true)
	Settings.values["show_hints"] = true
	ob.call("tick", 0.5)
	assert_true((ob.call("armed_ids") as Array).has("ob_wardrobe"), "the ob_wardrobe tip still arms from the same flag")
	Settings.values["show_hints"] = hints_before
	ob.queue_free()
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	GameState.active = true
	assert_false(ui.wardrobe_notice_pending(), "remembered in the save")


## The notice never lands on a chapter card, death or ending screen (anything in the overlay layer, e.g. the
## Chapter Two card shown 2.2 s after the Ward Stone choice): it waits for 3 s of quiet play after it.
func test_notice_waits_for_cards_and_overlays() -> void:
	ui.show_chapter_card("Chapter Two", "The Lanterns of Hallowmere")
	assert_false(ui.wardrobe_notice_safe_now(), "not over a chapter card")
	for i in 40:
		assert_false(ui.tick_wardrobe_notice(0.25), "waits while the card shows")
	var card: Node = ui.overlay_layer.get_child(0)
	ui.overlay_layer.remove_child(card)
	card.free()
	assert_true(ui.wardrobe_notice_safe_now(), "safe once the card is gone")
	var shown := false
	var ticks := 0
	while not shown and ticks < 40:
		shown = ui.tick_wardrobe_notice(0.25)
		ticks += 1
	assert_true(shown and ticks * 0.25 >= UiRootScript.WARDROBE_NOTICE_SAFE_SECONDS, "then after 3 s of quiet play")
	await wait_frames(1)
	ui.close_all()
	await wait_frames(1)


## A gameplay hotkey pressed in the wardrobe opened over the pause menu switches panels; Esc walks back
## through the pause menu and the world never stays paused (no softlock).
func test_hotkeys_from_the_wardrobe_over_the_pause_menu_never_stick() -> void:
	ui.open("pause")
	await wait_frames(1)
	ui.open("wardrobe")
	await wait_frames(1)
	var inv := InputEventKey.new()
	var src: InputEventKey = InputMap.action_get_events("inventory")[0]
	inv.physical_keycode = src.physical_keycode
	inv.keycode = src.keycode
	inv.pressed = true
	ui._input(inv)
	await wait_frames(2)
	assert_eq(ui.order, ["pause", "inventory"], "switched away from the wardrobe")
	ui._input(_pause_key())
	await wait_frames(2)
	assert_eq(ui.order, ["pause"])
	assert_true(get_tree().paused)
	ui._input(_pause_key())
	await wait_frames(2)
	assert_true(ui.order.is_empty())
	assert_false(get_tree().paused, "unpaused")
	assert_false(Game.is_ui_open())


func test_unstuck_labels_and_targets_per_area() -> void:
	assert_eq(PausePanel.unstuck_label("surface"), "Return to the Haven")
	assert_eq(PausePanel.unstuck_label("below"), "Return to last lantern")
	for a in ["hallowmere_reach", "tobin_annex", "moonveil_manor", "hushed_works"]:
		assert_eq(PausePanel.unstuck_label(a), "Return to safety", a)
	# Lead decision R17 (docs/ch2/INTEGRATION_WAVE_BC.md, MP section 15): inside an Echo Trial the option leaves the
	# trial, back to the checkpoint where it began (the behaviour itself is covered in test_ui_root).
	assert_eq(PausePanel.unstuck_label("echo_trial"), "Leave the trial", "echo_trial")
	# Pure helper: legacy rules unchanged, Chapter Two areas use their own memory.
	assert_eq(PausePanel.unstuck_spawn("surface", {"respawn_area": "surface", "respawn_spawn": "bed"}), "bed")
	assert_eq(PausePanel.unstuck_spawn("below", {"respawn_area": "surface", "respawn_spawn": "bed"}), "mine_entry")
	var ps := {"respawn_area": "surface", "respawn_spawn": "haven_respawn", "area_respawn": {"hallowmere_reach": "orchard_arch"}}
	assert_eq(PausePanel.unstuck_spawn("hallowmere_reach", ps), "orchard_arch", "remembered arch")
	assert_eq(PausePanel.unstuck_spawn("moonveil_manor", {"respawn_area": "moonveil_manor", "respawn_spawn": "manor_ballroom"}), "manor_ballroom")
	assert_eq(PausePanel.unstuck_spawn("hushed_works", {}, Game.AREA_DEFAULT_RESPAWN), "service_landing")
	assert_eq(PausePanel.unstuck_spawn("echo_trial", {}, PausePanel.UNSTUCK_DEFAULTS), "trial_start")
	# Live: Game.return_point() with the area's registered spawns.
	var area: Node3D = AreaBase.new()
	area.area_id = "hallowmere_reach"
	for s in ["commons_arch", "orchard_arch", "reach_respawn"]:
		area.register_spawn(s, Transform3D(Basis.IDENTITY, Vector3(1, 0, 1)))
	_holder.add_child(area)
	Game.area = area
	Game.area_id = "hallowmere_reach"
	GameState.player["area_respawn"] = {"hallowmere_reach": "orchard_arch"}
	assert_eq(PausePanel.unstuck_target(), "orchard_arch", "last safe spot in the Reach")
	GameState.player["area_respawn"] = {}
	assert_eq(PausePanel.unstuck_target(), "commons_arch", "area default")
	GameState.player["area_respawn"] = {"hallowmere_reach": "gone_spawn"}
	var t := PausePanel.unstuck_target()
	assert_true(area.spawns.has(t), "only registered spawns (%s)" % t)
	ui.open("pause")
	await wait_frames(2)
	assert_eq(String((ui.panels["pause"] as Control).unstuck_btn.text), "Return to safety")
	ui.close_all()
	await wait_frames(1)
	var trial: Node3D = AreaBase.new()
	trial.area_id = "echo_trial"
	trial.register_spawn("trial_start", Transform3D.IDENTITY)
	_holder.add_child(trial)
	Game.area = trial
	Game.area_id = "echo_trial"
	assert_eq(PausePanel.unstuck_target(), "trial_start", "a trial returns to its pad")


func test_preview_renders_in_its_own_world_and_frames_krystal() -> void:
	var w := await _open_wardrobe()
	var pv: Control = w.preview
	assert_true(pv.viewport.own_world_3d, "own World3D: never the live area")
	assert_true(pv.viewport.transparent_bg)
	assert_eq(pv.viewport.render_target_update_mode, SubViewport.UPDATE_WHEN_VISIBLE)
	assert_true(pv.mode in ["live", "rebuild", "legacy"], "an avatar is shown (%s)" % pv.mode)
	assert_eq(pv.note.visible, pv.mode == "legacy", "a clear note only while the avatar can't show looks")
	if pv.avatar != null:
		assert_true(pv.avatar.get_viewport() == pv.viewport, "the avatar lives in the preview viewport")
	await wait_frames(2)
	var vs: Vector2 = Vector2(pv.viewport.size)
	assert_true(vs.x >= 380.0 and vs.y >= 520.0, "viewport follows the widget (%s)" % vs)
	var cam: Camera3D = pv.camera
	assert_true(cam.current)
	for p in [Vector3(0, 0.02, 0), Vector3(0, 1.72, 0), Vector3(0.42, 0.9, 0), Vector3(-0.42, 0.9, 0), Vector3(0, 1.3, 0.35)]:
		assert_true(cam.is_position_in_frustum(p), "Krystal's %s is in frame" % str(p))
	assert_false(cam.is_position_in_frustum(Vector3(0, 2.6, 0)), "framed snugly, not tiny")
	# The real avatar's bounds stay in frame while the turntable turns, and she fills most of the height.
	if pv.avatar != null and pv.mode != "none":
		pv.auto_spin = false
		for yaw in [0.0, PI / 2.0, PI, -PI / 2.0]:
			pv.pivot.rotation.y = yaw
			var box := _bounds(pv.avatar)
			assert_true(box.size.y > 1.2 and box.size.y < 2.3, "a Krystal-sized model (%s)" % str(box))
			var top := 1e9
			var bottom := -1e9
			for i in 8:
				var c: Vector3 = box.get_endpoint(i)
				assert_true(cam.is_position_in_frustum(c), "corner %s in frame at yaw %.2f" % [str(c), yaw])
				var sp: Vector2 = cam.unproject_position(c)
				top = minf(top, sp.y)
				bottom = maxf(bottom, sp.y)
			var frac := (bottom - top) / vs.y
			print("AUDIT-PREVIEW yaw=%.2f bounds=%s fills=%.2f viewport=%s" % [yaw, str(box), frac, str(vs)])
			assert_true(frac > 0.5 and frac < 0.99, "she fills %.0f%% of the preview height" % (frac * 100.0))
	ui.close("wardrobe")
	await wait_seconds(0.3)
	assert_false(is_instance_valid(pv), "the preview (and its viewport) is freed with the panel")


func test_preview_uses_the_avatar_appearance_api_when_present() -> void:
	Preview._script_cache = FakeAvatar
	Preview._script_checked = true
	var pv: Control = Preview.new()
	var look := ItemDB.legacy_look()
	look["hair"] = "bob"
	pv.setup({"look": look, "size": Vector2(300, 400)})
	add_child(pv)
	await wait_frames(1)
	assert_eq(String(pv.mode), "live")
	assert_false(pv.note.visible, "no placeholder note")
	var av: Node3D = pv.avatar
	assert_false(bool(av.get("driven")), "a non-driven avatar")
	assert_eq(String(av.get("appearance")["hair"]), "bob", "look given before it was built")
	look["hair"] = "space_buns"
	pv.set_look(look)
	assert_eq(String(av.get("appearance")["hair"]), "space_buns", "updated in place")
	assert_eq(int(av.get("applied")), 1)
	var y0: float = pv.yaw
	pv.turn(PI / 2.0)
	assert_almost(pv.pivot.rotation.y, wrapf(y0 + PI / 2.0, -PI, PI), 0.001, "turned a quarter")
	pv.queue_free()
	await wait_frames(1)


## The real avatar (krystal_avatar.gd apply_look / apply_armor): the preview is "live", shows what is chosen
## at once, shows equipped armor only when "Show equipped armor" is on (the preview is non-driven and never reads
## GameState itself), and does not clip the lantern on (the preview is about her look).
func test_preview_shows_choices_and_armor_on_the_real_avatar() -> void:
	GameState.give_item("padded_vest", 1)
	assert_true(GameState.equip("padded_vest"), "armor equipped")
	var w := await _open_wardrobe()
	var pv: Control = w.preview
	var av: Node3D = pv.avatar
	assert_not_null(av)
	if av == null:
		return
	assert_true(av.has_method("apply_look") and av.has_method("apply_armor"), "the avatar module's preview API")
	assert_eq(String(pv.mode), "live", "looks are shown, no placeholder")
	assert_false(pv.note.visible)
	assert_false(bool(av.get("driven")), "a non-driven preview avatar")
	assert_false(bool(av.get("lantern_owned")), "no lantern clipped on in the preview")
	assert_true(Wardrobe.Looks.same_look(av.call("current_look"), Wardrobe.Looks.current_look()), "starts in her current look")
	w.editor.choose("hair", "space_buns")
	w.editor.choose("outfit", "strawberry_picnic")
	var shown: Dictionary = av.call("current_look")
	assert_eq(String(shown["hair"]), "space_buns", "the preview follows the editor")
	assert_eq(String(shown["lower"]), "pinafore_skirt")
	assert_eq(String(av.call("_armor_id", "body")), "", "armor hidden by default")
	w.armor_btn.button_pressed = true
	assert_eq(String(av.call("_armor_id", "body")), "padded_vest", "Show equipped armor reaches the preview")
	w.armor_btn.button_pressed = false
	assert_eq(String(av.call("_armor_id", "body")), "", "and hides it again")
	assert_eq(String(GameState.equipped("body")), "padded_vest", "styling never unequips anything")


func test_wardrobe_fits_the_canvas() -> void:
	var w := await _open_wardrobe()
	await wait_frames(1)
	var ms: Vector2 = w.window.get_combined_minimum_size()
	print("AUDIT-LAYOUT wardrobe min=", ms)
	assert_true(ms.x <= CANVAS.x and ms.y <= CANVAS.y, "wardrobe fits 1920x1080 (%s)" % ms)
	var wy := roundf((CANVAS.y - ms.y) * 0.5)
	if wy < 30.0 and CANVAS.y > ms.y + 30.0:
		wy = 30.0
	var rib: Control = w.window.get("ribbon")
	assert_true(wy + rib.position.y >= 0.0, "title ribbon on screen")
