extends "res://tests/test_case.gd"
## AUDIT (persistence integration, game flow): Continue with a damaged main save / only a temp file,
## and quit to title -> New Game -> Continue without state leaking between playthroughs.
## Game.load_area / goto_title use change_scene_to_file, so loads first swap in a throwaway current scene.

var _runner: Node = null
var _saved_mode: String = "boot"
var _notes: Array = []


func before_each() -> void:
	_runner = get_parent()
	_saved_mode = Game.mode
	_notes = []
	fresh_state()
	if not Events.notify.is_connected(_on_notify):
		Events.notify.connect(_on_notify)


func after_each() -> void:
	if Events.notify.is_connected(_on_notify):
		Events.notify.disconnect(_on_notify)
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur != _runner and is_instance_valid(cur):
		cur.queue_free()
	tree.current_scene = _runner
	Game.mode = _saved_mode
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game._ui_stack.clear()
	Game._transitioning = false
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	for n in tree.root.get_children():
		if n != _runner and String(n.name) in ["AuditPlaceholder", "Title", "Surface", "Below"]:
			n.queue_free()
	tree.paused = false
	Engine.time_scale = 1.0
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


func _on_notify(text: String, _kind: String) -> void:
	_notes.append({"text": text, "ui": Game.ui != null and is_instance_valid(Game.ui)})


func _placeholder() -> void:
	var tree := get_tree()
	if tree.current_scene == _runner or tree.current_scene == null:
		var ph := Node.new()
		ph.name = "AuditPlaceholder"
		tree.root.add_child(ph)
		tree.current_scene = ph


func _continue() -> bool:
	_placeholder()
	var ok: bool = await Game.continue_game()
	await wait_physics(3)
	return ok


func _path(suffix: String) -> String:
	return SaveSystem.save_dir.path_join("slot1" + suffix)


func _toast_texts() -> Array:
	var out: Array = []
	if Game.ui == null or not is_instance_valid(Game.ui):
		return out
	var t: Node = Game.ui.get("toasts")
	if t == null:
		return out
	var views: Dictionary = t.get("views")
	for id in views:
		var v: Dictionary = views[id]
		var l: Variant = v.get("label")
		if l is Label:
			out.append((l as Label).text)
		elif l is RichTextLabel:
			out.append((l as RichTextLabel).text)
	return out


func test_continue_with_a_damaged_save_restores_the_backup_and_says_so() -> void:
	GameState.give_item("wood", 5)
	assert_true(SaveSystem.save_game(), "first save")
	GameState.give_item("wood", 5)
	assert_true(SaveSystem.save_game(), "second save (first becomes the backup)")
	var f := FileAccess.open(_path(".json"), FileAccess.WRITE)
	f.store_string("{\"format\": \"hollowhaven-save\", \"version\": 1, \"state\": {tru")   # torn write
	f.close()
	GameState.reset()
	GameState.active = false
	assert_true(await _continue(), "continue works from the backup")
	assert_eq(Game.area_id, "surface", "in the world")
	assert_eq(GameState.count_item("wood"), 5, "backup state loaded")
	var told := false
	var told_with_ui := false
	for n in _notes:
		if String(n["text"]).contains("damaged"):
			told = true
			told_with_ui = told_with_ui or bool(n["ui"])
	assert_true(told, "SaveSystem announces the restore")
	await wait_seconds(0.3)
	var shown := false
	for t in _toast_texts():
		if String(t).contains("damaged"):
			shown = true
	assert_true(told_with_ui or shown, "Krystal is actually shown that her latest save was damaged and an older one was restored (notify emitted with Game.ui=%s; toasts now: %s)" % [str(told_with_ui), str(_toast_texts())])


func test_continue_with_only_a_complete_temp_file() -> void:
	GameState.give_item("stone", 3)
	assert_true(SaveSystem.save_game(), "save")
	# Crash right after writing the very first save's temp file: only slot1.tmp exists.
	assert_eq(DirAccess.rename_absolute(_path(".json"), _path(".tmp")), OK, "simulate")
	if FileAccess.file_exists(_path(".bak.json")):
		DirAccess.remove_absolute(_path(".bak.json"))
	GameState.reset()
	GameState.active = false
	assert_true(SaveSystem.has_save(), "title shows Continue")
	assert_true(await _continue(), "continue from the temp file")
	assert_eq(GameState.count_item("stone"), 3, "temp state loaded")
	assert_true(FileAccess.file_exists(_path(".json")), "temp promoted to the main save")
	assert_false(FileAccess.file_exists(_path(".tmp")), "no temp left behind")


func test_quit_to_title_then_new_game_then_continue_does_not_leak_state() -> void:
	# Playthrough A: a friend, a structure, some items, down in the mine (autosaved on arrival).
	GameState.give_item("lantern", 1)
	GameState.give_item("wood", 12)
	GameState.companion("lumi")["befriended"] = true
	GameState.set_companion_assignment("lumi", "follow")
	GameState.add_structure("storage_chest", Vector3(6, 0, 6), 0.0)
	GameState.set_flag("ruin_cleared", true)
	_placeholder()
	await Game.load_area("surface", "haven_start", false)
	await Game.change_area("below", "mine_entry")
	await wait_physics(3)
	assert_eq(Game.area_id, "below", "A is below")
	assert_not_null(Game.director, "director running in A")
	assert_true(Game.companion_nodes.has("lumi"), "Lumi below in A")
	# Quit to title.
	Game.goto_title()
	await wait_frames(4)
	# New Game saves B straight away (Continue must exist from minute one), so keep A's save to put
	# back before the final Continue.
	var save_a: String = FileAccess.get_file_as_string(_path(".json"))
	assert_true(save_a != "", "A was saved on arriving below")
	assert_eq(Game.mode, "title", "on the title")
	assert_null(Game.director, "director reference dropped")
	assert_true(Game.companion_nodes.is_empty(), "companion registry cleared")
	assert_null(Game.ui, "gameplay UI gone")
	assert_false(GameState.active, "no playthrough active")
	# New Game (B).
	await Game.new_game()
	await wait_physics(3)
	assert_eq(Game.area_id, "surface", "B starts on the surface")
	assert_null(Game.director, "no director on the surface")
	assert_eq(GameState.count_item("wood"), 0, "no wood from A")
	assert_eq(GameState.active_companion, "", "no follower from A")
	assert_false(GameState.is_befriended("lumi"), "Lumi is a stranger again")
	assert_true(GameState.structures.is_empty(), "no structures from A")
	assert_false(bool(GameState.get_flag("ruin_cleared")), "no flags from A")
	assert_eq(String(GameState.player["respawn_area"]), "surface", "respawn reset")
	var lumi: Node = Game.companion_nodes.get("lumi")
	if lumi != null:
		assert_eq(String(lumi.mode), "wild", "Lumi is wild in B")
	assert_eq(get_tree().get_nodes_in_group("structure").size(), 0, "no structure nodes from A")
	assert_true(Game.in_safe_zone == Game.area.is_safe_zone(Game.player.global_position), "safe-zone state matches where Krystal stands")
	assert_true(SaveSystem.has_save(), "New Game saved B at once")
	# Continue A (its save put back in place of B's).
	Game.goto_title()
	await wait_frames(4)
	var f := FileAccess.open(_path(".json"), FileAccess.WRITE)
	f.store_string(save_a)
	f.close()
	GameState.reset()
	assert_true(await _continue(), "continue A")
	assert_eq(Game.area_id, "below", "A resumes below")
	assert_eq(GameState.count_item("wood"), 12, "A's wood")
	assert_true(Game.companion_nodes.has("lumi"), "A's Lumi is back beside Krystal")
	assert_not_null(Game.director, "director again")
