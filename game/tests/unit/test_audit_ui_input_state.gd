extends "res://tests/test_case.gd"
## AUDIT (UI/input state machine). Each test demonstrates one suspected defect; a FAIL is the evidence.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const PlayerScript := preload("res://src/player/player.gd")

var ui: CanvasLayer
var player: CharacterBody3D = null
var floor_body: StaticBody3D = null
var _mode_before := ""
var _binds_before: Dictionary = {}


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_mode_before = Game.mode
	Game.mode = "playing"
	var b: Variant = Settings.values.get("bindings", {})
	_binds_before = (b as Dictionary).duplicate(true) if b is Dictionary else {}
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func after_each() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	if player != null and is_instance_valid(player):
		if Game.player == player:
			Game.player = null
		player.queue_free()
	player = null
	if floor_body != null and is_instance_valid(floor_body):
		floor_body.queue_free()
	floor_body = null
	await wait_frames(2)
	Settings.values["bindings"] = _binds_before
	Settings.setup_input_map()
	get_tree().paused = false
	Game.mode = _mode_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _key(action: String) -> InputEventKey:
	var ev := InputEventKey.new()
	var src: InputEventKey = InputMap.action_get_events(action)[0]
	ev.physical_keycode = src.physical_keycode
	ev.pressed = true
	return ev


func _spawn_player() -> void:
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	Game.player = player
	await wait_physics(6)


func _slot_of(id: String) -> int:
	for i in GameState.inventory.size:
		var s: Variant = GameState.inventory.get_slot(i)
		if s != null and String(s["id"]) == id:
			return i
	return -1


## REGRESSION (fixed in player.gd eat()): the player's 1 s eat lock only counts down in _physics_process,
## which is frozen while the (full-screen, pausing) backpack is open, so only ONE food could be eaten per
## visit. Menu eats (tree paused) now skip the lock and leave none behind for when the menu closes.
func test_backpack_can_eat_more_than_once_per_visit() -> void:
	await _spawn_player()
	player.health.set_hp(30.0)
	GameState.player["hp"] = 30.0
	GameState.give_item("berries", 3)
	ui.open("inventory")
	await wait_frames(2)
	assert_true(get_tree().paused, "backpack pauses the world")
	var panel: Control = ui.panels["inventory"]
	var idx := _slot_of("berries")
	assert_true(idx >= 0, "berries in the backpack")
	panel._use_slot(idx)
	await wait_frames(30)   # half a second in the menu
	panel._use_slot(idx)
	await wait_frames(2)
	print("AUDIT-EAT berries left=%d hp=%.1f msg='%s'" % [GameState.count_item("berries"), float(player.health.hp), String(panel.msg_l.text)])
	assert_eq(GameState.count_item("berries"), 1, "two berries eaten from the backpack in one visit")
	assert_almost(float(player.get("_eat_lock")), 0.0, 0.0001, "menu eats leave no sprint/dodge/jump lock for after the menu closes")


## At full health the backpack says only "Krystal can't eat that right now." (the player's real reason,
## "You're already at full health.", is a toast that sits BELOW the open menu).
func test_backpack_full_health_message_explains_why() -> void:
	await _spawn_player()
	GameState.give_item("berries", 1)
	ui.open("inventory")
	await wait_frames(2)
	var panel: Control = ui.panels["inventory"]
	panel._use_slot(_slot_of("berries"))
	await wait_frames(1)
	print("AUDIT-EAT-FULL msg='%s'" % String(panel.msg_l.text))
	assert_true(String(panel.msg_l.text).to_lower().contains("full"), "message mentions full health (got '%s')" % String(panel.msg_l.text))


## REGRESSION (fixed in crafting_panel.gd: the selection follows keyboard focus, handle_key() only crafts
## when the Craft button or a recipe row has focus): Enter on a keyboard-focused recipe row used to craft
## a different, previously selected recipe.
func test_enter_on_focused_recipe_row_does_not_craft_another_recipe() -> void:
	GameState.give_item("wood", 20)
	GameState.give_item("stone", 10)
	GameState.give_item("fiber", 10)
	ui.open("crafting")
	await wait_frames(3)
	var panel: Control = ui.panels["crafting"]
	panel._selected = "stone_axe"
	panel._refresh_status()
	var row: Button = panel._rows["stone_pickaxe"]
	row.grab_focus()
	await wait_frames(1)
	assert_true(row.has_focus(), "pickaxe row has keyboard focus")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	ui._input(ev)
	await wait_frames(1)
	print("AUDIT-CRAFT axes=%d pickaxes=%d selected=%s" % [GameState.count_item("stone_axe"), GameState.count_item("stone_pickaxe"), String(panel._selected)])
	assert_eq(GameState.count_item("stone_axe"), 0, "Enter on the focused pickaxe row must not craft the axe")


## REGRESSION (fixed in settings_panel.gd / ui_util.gd is_bindable): while "Press a key..." was showing, ANY
## mouse press became the binding: clicking elsewhere to back out bound Left Mouse, and scrolling the
## Controls list bound the wheel. Now the wheel scrolls and a left click away from the box cancels.
func test_click_or_scroll_while_capturing_does_not_silently_bind_the_mouse() -> void:
	ui.open("settings", {"tab": "controls"})
	await wait_frames(2)
	var panel: Control = ui.panels["settings"]
	var sc: ScrollContainer = panel.tabs.get_child(1)
	print("AUDIT-REBIND controls list needs %.0f px, visible %.0f px" % [(sc.get_child(0) as Control).get_combined_minimum_size().y, sc.size.y])
	panel._begin_capture("jump")
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	panel._input(lmb)
	print("AUDIT-REBIND jump -> %s" % Settings.action_label("jump"))
	assert_false(Settings.actions_using(lmb).has("jump"), "a stray click bound Jump to Left Mouse")
	panel._begin_capture("map")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	panel._input(wheel)
	print("AUDIT-REBIND map -> %s" % Settings.action_label("map"))
	assert_false(Settings.actions_using(wheel).has("map"), "scrolling bound Map to the wheel")


## REGRESSION (fixed in ui_root.gd _fade_busy()): Esc during a fade-out that isn't a transition (bed sleep,
## "Return to the Haven") opened the pause menu while the screen was still < 50% dark; the fade rect is
## drawn ABOVE the panel layer, so the menu then sat invisible under a black screen.
func test_escape_during_a_sleep_fade_does_not_open_a_hidden_pause_menu() -> void:
	ui.fade_out(0.9)                  # what bed.gd does right after "Sleep until morning"
	await wait_seconds(0.2)
	ui._input(_key("pause"))
	var opened: bool = ui.is_open("pause")
	await wait_seconds(0.9)
	var hidden_under_fade: bool = opened and ui.fade_rect.color.a > 0.99 and ui.fade_rect.get_index() > ui.panel_layer.get_index()
	print("AUDIT-FADE pause_opened=%s fade_a=%.2f fade_idx=%d panels_idx=%d" % [str(opened), ui.fade_rect.color.a, ui.fade_rect.get_index(), ui.panel_layer.get_index()])
	assert_false(hidden_under_fade, "pause menu opened mid-fade and is now hidden under the black fade")
	await ui.fade_in(0.0)


## Alt-tab auto-pause only reacts to the FOCUS_OUT notification while mode == "playing". Losing focus
## during an area load / respawn / lift ride (mode loading/dead/cutscene) is never re-checked, so the game
## comes back running unattended (e.g. in the Below with the horror director and Gloomlings active).
func test_focus_lost_during_a_load_still_pauses_once_play_resumes() -> void:
	var keep: bool = Debug.keep_running_unfocused
	var prev_ui: Node = Game.ui
	Debug.keep_running_unfocused = false
	Game.ui = ui
	Game.mode = "loading"
	Game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)   # player alt-tabs during the fade
	Game.mode = "playing"                                     # load_area() finishes
	Events.area_loaded.emit("surface")
	await wait_frames(3)
	var paused_now: bool = ui.is_open("pause")
	Debug.keep_running_unfocused = keep
	Game.ui = prev_ui
	assert_true(paused_now, "window lost focus during the load but the game resumed unpaused")


## REGRESSION (fixed in companion_panel.gd): the companion menu does not pause the world but blocks all of
## Krystal's input (no move / dodge), and nothing closed it when she was hurt, so an enemy could keep
## hitting a frozen Krystal. It now closes on Events.player_damaged.
func test_companion_menu_closes_when_krystal_is_hurt() -> void:
	await _spawn_player()
	ui.open("companion", {"id": "lumi"})
	await wait_frames(2)
	assert_false(get_tree().paused, "world keeps running")
	assert_false(Game.gameplay_input_allowed(), "Krystal can't move or dodge while it's open")
	player.health.apply_damage(12.0, null, Vector3.ZERO)
	await wait_frames(3)
	print("AUDIT-COMPANION hp=%.1f menu_open=%s" % [float(player.health.hp), str(ui.is_open("companion"))])
	assert_false(ui.is_open("companion"), "companion menu stays open (Krystal frozen) while she takes damage")
