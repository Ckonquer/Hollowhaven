extends "res://tests/test_case.gd"
## New Game flow with "Meet Krystal" (MP §4): overwrite warning -> comfort screen -> creation screen ->
## Game.new_game(look). Backing out of the creation screen (Back, Esc) returns to the comfort screen and
## from there to the title WITHOUT touching the old save (byte-identical, no new files) and without
## creating one; Confirm hands the chosen look to Game.new_game; the new journey marks "A Look of Your
## Own" and skips the older-save wardrobe notice. The creation screen offers starter items only and fits
## the 1920x1080 canvas. Saves only go to user://test_saves/.

const TitleScreen := preload("res://src/ui/title_screen.gd")
const CreationScreen := preload("res://src/ui/screens/creation_screen.gd")
const Wardrobe := preload("res://src/ui/panels/wardrobe_panel.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const CANVAS := Vector2(1920, 1080)

var title: Node
var _launched: Array = []


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	SaveSystem.delete_test_saves()
	_launched = []
	title = TitleScreen.new()
	title.launch_override = _on_launch
	add_child(title)
	await wait_frames(2)


func after_each() -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
	await wait_frames(2)
	SaveSystem.replace_future_allowed = false
	SaveSystem.blocked_by_future = false
	SaveSystem.delete_test_saves()


func _on_launch(look: Dictionary) -> void:
	_launched.append(look)


## Every file (and the backup folder's files) in the test save folder, with sizes.
func _listing() -> Array:
	var out: Array = []
	for dir_path in [SaveSystem.save_dir, SaveSystem.save_dir.path_join(SaveSystem.UPGRADE_BACKUP_DIR)]:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		for f in DirAccess.get_files_at(dir_path):
			out.append("%s/%s:%d" % [dir_path.get_file(), f, FileAccess.get_file_as_bytes(dir_path.path_join(f)).size()])
	out.sort()
	return out


## Accepts the comfort screen the way its Begin button does.
func _accept_comfort() -> void:
	var c: Control = title._panel
	assert_true(c != null and c.has_signal("confirmed"), "comfort screen showing")
	if c == null:
		return
	c.set("accepted", true)
	c.request_close()
	await wait_frames(2)


func _creation() -> Control:
	var p: Control = title._panel
	return p if (p != null and p.has_signal("finished")) else null


func test_back_out_of_creation_keeps_the_old_save_byte_identical() -> void:
	assert_true(SaveSystem.save_dir.contains("test"), "tests use the test save folder")
	GameState.appearance["hair"] = "bob"
	assert_true(SaveSystem.save_game(true), "an old save exists")
	var path := SaveSystem.save_dir.path_join("slot1.json")
	var bytes_before := FileAccess.get_file_as_bytes(path)
	var files_before := _listing()
	var state := {"returned": false}
	var run := func() -> void:
		await title._on_new_game()
		state["returned"] = true
	run.call()
	await wait_frames(2)
	title._panel._choose("new")      # "Start fresh"
	await wait_frames(2)
	await _accept_comfort()
	var cs := _creation()
	assert_not_null(cs, "Meet Krystal follows the comfort screen")
	if cs == null:
		return
	assert_true(cs.choose("hair", "space_buns"))
	assert_true(cs.choose("outfit", "strawberry_picnic"))
	# Back -> the comfort screen again (draft kept), Esc there -> the title.
	cs.back_btn.pressed.emit()
	await wait_frames(2)
	var c2: Control = title._panel
	assert_true(c2 != null and c2.has_signal("confirmed"), "Back returns to the comfort screen")
	assert_false(bool(state["returned"]))
	await _accept_comfort()
	var cs2 := _creation()
	assert_not_null(cs2, "creation again")
	if cs2 != null:
		assert_eq(String(cs2.look["hair"]), "space_buns", "the draft look is kept while going back")
		title._close_panel()          # Esc on Meet Krystal
		await wait_frames(2)
	var c3: Control = title._panel
	assert_true(c3 != null and c3.has_signal("confirmed"), "Esc on the creation screen also goes back one step")
	title._close_panel()              # Esc on the comfort screen
	await wait_frames(3)
	assert_true(bool(state["returned"]), "flow finished on the title")
	assert_false(bool(title._busy), "title still usable")
	assert_eq(_launched.size(), 0, "no game started")
	assert_ne(Game.mode, "loading")
	assert_false(SaveSystem.replace_future_allowed)
	assert_eq(FileAccess.get_file_as_bytes(path), bytes_before, "old save byte-identical")
	assert_eq(_listing(), files_before, "no file created, moved or removed")
	assert_eq(String(GameState.appearance["hair"]), "bob", "nothing applied to the loaded state")


func test_back_out_without_a_save_creates_none() -> void:
	assert_false(SaveSystem.has_save())
	var run := func() -> void:
		await title._on_new_game()
	run.call()
	await wait_frames(2)
	await _accept_comfort()
	var cs := _creation()
	assert_not_null(cs, "no overwrite warning without a save")
	if cs == null:
		return
	cs.choose("eyes", "eye_4")
	title._close_panel()
	await wait_frames(2)
	title._close_panel()
	await wait_frames(3)
	assert_false(SaveSystem.has_save(), "no save created")
	assert_eq(_listing(), [], "nothing written")
	assert_eq(_launched.size(), 0)


func test_confirm_hands_the_look_to_new_game() -> void:
	var run := func() -> void:
		await title._on_new_game()
	run.call()
	await wait_frames(2)
	await _accept_comfort()
	var cs := _creation()
	assert_not_null(cs)
	if cs == null:
		return
	assert_true(cs.choose("hair", "high_ponytail"))
	assert_true(cs.choose("hair_color", "lavender"))
	assert_true(cs.choose("skin", "skin_5"))
	assert_true(cs.choose("eyes", "eye_6"))
	assert_true(cs.choose("outfit", "cloud_cardigan"))
	assert_true(cs.choose("hat", "sun_hat"))
	assert_true(cs.choose("palette.accent", "berry"))
	assert_false(cs.choose("upper", "witch_blouse"), "earnable pieces are not offered at creation")
	cs.confirm_btn.pressed.emit()
	await wait_frames(2)
	assert_true(bool(title._busy), "starting")
	var guard := 0
	while _launched.is_empty() and guard < 200:
		await wait_frames(1)
		guard += 1
	assert_eq(_launched.size(), 1, "handed over once, after the fade")
	if _launched.is_empty():
		return
	var look: Dictionary = _launched[0]
	assert_eq(String(look["hair"]), "high_ponytail")
	assert_eq(String(look["hair_color"]), "lavender")
	assert_eq(String(look["skin"]), "skin_5")
	assert_eq(String(look["eyes"]), "eye_6")
	assert_eq(String(look["upper"]), "cloud_cardigan")
	assert_eq(String(look["lower"]), "cloud_culottes")
	assert_eq(String(look["hat"]), "sun_hat")
	assert_eq(String(look["palette"]["accent"]), "berry")
	assert_eq(ItemDB.sanitize_look(look)["missing"], [], "a complete, valid look")


func test_reset_returns_to_the_classic_look() -> void:
	var cs: Control = CreationScreen.new()
	cs.setup({"look": {"hair": "bob", "eyes": "eye_3"}})
	title._open_panel(cs)
	await wait_frames(2)
	assert_eq(String(cs.look["hair"]), "bob", "starts from the given draft")
	assert_eq(String(cs.look["upper"]), "explorer_jacket", "missing keys are the classic look")
	cs.reset_btn.pressed.emit()
	assert_true(Wardrobe.Looks.same_look(cs.look, ItemDB.legacy_look()), "Reset to default")
	assert_true(Wardrobe.Looks.same_look(cs.editor.look, ItemDB.legacy_look()), "editor follows")


func test_creation_offers_starter_items_only_and_fits_the_canvas() -> void:
	GameState.unlock_pattern("pat_ribbon_witch")   # whatever the last journey owned, a new one starts fresh
	var cs: Control = CreationScreen.new()
	cs.setup({})
	title._open_panel(cs)
	await wait_frames(3)
	var ed: Control = cs.editor
	for cat in ed.categories():
		ed.show_category(String(cat))
		var keys: Array = [ed.grid_key()]
		if String(cat) == "pieces":
			keys = ["upper", "lower", "shoes", "hat", "hair_acc", "back"]
		elif String(cat) == "colours":
			keys = ["palette.primary", "palette.secondary", "palette.accent"]
		for k in keys:
			if String(k).begins_with("palette."):
				ed.set_channel(String(k).substr(8))
			elif String(cat) == "pieces":
				ed.set_piece_slot(String(k))
			assert_true(ed.tiles.size() > 0, "%s has options" % k)
			for id in ed.tiles:
				assert_false(bool((ed.tiles[id] as Button).get_meta("locked", false)), "no locked %s=%s at creation" % [k, id])
	ed.show_category("hair")
	assert_eq(ed.tiles.size(), 8, "eight hairstyles")
	ed.show_category("hair_color")
	assert_true(ed.tiles.size() >= 12, "at least twelve hair colours")
	ed.show_category("skin")
	assert_eq(ed.tiles.size(), 6)
	ed.show_category("eyes")
	assert_eq(ed.tiles.size(), 8)
	ed.show_category("outfit")
	assert_eq(ed.tiles.size(), 6, "six starter looks")
	assert_false(ed.tiles.has("ribbon_witch"))
	await wait_frames(1)
	var ms: Vector2 = cs.window.get_combined_minimum_size()
	print("AUDIT-LAYOUT creation min=", ms)
	assert_true(ms.x <= CANVAS.x and ms.y <= CANVAS.y, "Meet Krystal fits 1920x1080 (%s)" % ms)
	var wy := roundf((CANVAS.y - ms.y) * 0.5)
	if wy < 30.0 and CANVAS.y > ms.y + 30.0:
		wy = 30.0
	assert_true(wy + (cs.window.get("ribbon") as Control).position.y >= 0.0, "title ribbon on screen")
	var pv: Control = cs.preview
	assert_true(pv.viewport.own_world_3d, "preview in its own world")
	assert_eq(String(cs.default_focus().name), "Confirm", "Enter confirms")


func test_keys_on_the_title_switch_categories() -> void:
	var cs: Control = CreationScreen.new()
	cs.setup({})
	title._open_panel(cs)
	await wait_frames(2)
	assert_eq(String(cs.editor.category), "outfit")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	assert_true(cs.handle_key(ev))
	assert_eq(String(cs.editor.category), "pieces")
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_PERIOD
	ev2.pressed = true
	var y0: float = cs.preview.yaw
	assert_true(cs.handle_key(ev2), "> turns the preview")
	assert_ne(float(cs.preview.yaw), y0)


func test_new_journey_marks_the_look_chosen_and_skips_the_notice() -> void:
	var look := ItemDB.legacy_look()
	look["hair"] = "braided_crown"
	CreationScreen.arm_new_journey_marks()
	# Exactly what Game.new_game(look) does before it loads the Haven: reset, then apply the look.
	GameState.new_game()
	Game._apply_new_game_look(look)
	assert_eq(String(GameState.appearance["hair"]), "braided_crown", "the look is in the new journey")
	assert_true(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)), "A Look of Your Own")
	assert_true(bool(GameState.wardrobe["notice_shown"]), "no 'wardrobe is ready' notice for a new journey")
	# One-shot: a later look change doesn't run it again (a reset journey keeps its defaults).
	GameState.new_game()
	Events.appearance_changed.emit()
	assert_false(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)))
	assert_false(bool(GameState.wardrobe["notice_shown"]))


func test_footer_and_continue_line_follow_the_chapter() -> void:
	assert_true(TitleScreen.footer_text({}).begins_with("Chapter One  ·  The Dimming Ward  ·  v"))
	assert_true(TitleScreen.footer_text({"meta": {"chapter": 2}}).begins_with("Chapter Two  ·  The Lanterns of Hallowmere"))
	assert_true(TitleScreen.footer_text({"meta": {"chapter": 2.0}}).begins_with("Chapter Two"), "JSON floats")
	# Chapter Two steps resolve live (arachnophobia wording); unknown ids keep the saved title.
	var steps: Array = GameState.chapter2.steps()
	assert_true(not steps.is_empty(), "chapter two steps exist")
	var plain := ""
	for s in steps:
		if String((s as Dictionary).get("group", "")) == "":
			plain = String(s["id"])
			break
	var expect := String(GameState.chapter2.step_string(GameState.chapter2.step_by_id(plain), "title"))
	assert_eq(TitleScreen.continue_text({"meta": {"day": 3, "chapter": 2, "step": plain, "step_title": "old"}}), "Day 3  ·  " + expect)
	assert_eq(TitleScreen.continue_text({"meta": {"day": 3, "chapter": 2, "step": "nope", "step_title": "Saved Title"}}), "Day 3  ·  Saved Title")
	assert_eq(TitleScreen.continue_text({"meta": {"day": 4, "step_title": "A Timid Friend", "play_seconds": 1500.0}}), "Day 4  ·  A Timid Friend  ·  25 min played", "legacy line unchanged")
