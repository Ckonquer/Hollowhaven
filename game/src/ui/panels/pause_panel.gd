extends "res://src/ui/panels/panel_base.gd"
## Pause menu: Resume, Save Game (with feedback), Settings, Controls, Comfort, an "unstuck" option
## (Return to the Haven on the surface / Return to last lantern below), Quit to Title (confirm, offers
## to save when allowed) and Quit Game.

var sub_l: Label
var save_btn: Button
var save_l: Label
var unstuck_btn: Button
var _resume: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Paused"
	window_min = Vector2(640, 0)


func _build() -> void:
	sub_l = Kit.label("", "Muted", HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(sub_l)
	body.add_child(Kit.spacer(0, 4))
	var col := Kit.vbox(12)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size.x = 470
	body.add_child(col)
	_resume = Kit.button("Resume", request_close, "AccentButton")
	col.add_child(_resume)
	save_btn = Kit.button("Save Game", _save, "", IconFactory.icon("ui_save", Color.WHITE, 48))
	col.add_child(save_btn)
	save_l = Kit.wrap_label("", "Small", 460, HORIZONTAL_ALIGNMENT_CENTER)
	save_l.visible = false
	col.add_child(save_l)
	var two := Kit.hbox(12)
	col.add_child(two)
	var sb := Kit.button("Settings", func() -> void: _open("settings"))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(sb)
	var cb := Kit.button("Controls", func() -> void: _open("controls"))
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(cb)
	col.add_child(Kit.button("Comfort & Accessibility", func() -> void: _open("comfort")))
	unstuck_btn = Kit.button("Return to the Haven", _unstuck)
	col.add_child(unstuck_btn)
	col.add_child(Kit.separator())
	var two2 := Kit.hbox(12)
	col.add_child(two2)
	var qt := Kit.button("Quit to Title", _quit_title, "GhostButton")
	qt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qt.add_theme_font_size_override("font_size", 23)
	two2.add_child(qt)
	var qg := Kit.button("Quit Game", _quit_game, "GhostButton")
	qg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qg.add_theme_font_size_override("font_size", 23)
	two2.add_child(qg)


func refresh() -> void:
	var step: Dictionary = GameState.quests.current_step()
	var goal := String(GameState.quests.step_string(step, "title")) if not step.is_empty() else "Free play"
	sub_l.text = "Day %d  ·  %s  ·  %s" % [GameState.day(), UiUtil.format_clock(GameState.hour()), goal]
	var can: Dictionary = Game.can_manual_save()
	save_btn.disabled = not bool(can.get("ok", false))
	save_btn.tooltip_text = String(can.get("reason", ""))
	if save_btn.disabled:
		save_l.text = String(can.get("reason", ""))
		save_l.visible = save_l.text != ""
	unstuck_btn.text = "Return to last lantern" if Game.area_id == "below" else "Return to the Haven"
	unstuck_btn.tooltip_text = "Stuck? Safely return to your last lit lantern." if Game.area_id == "below" else "Stuck? Walk home in the blink of an eye."


func default_focus() -> Control:
	return _resume


func _open(panel: String) -> void:
	if ui_root != null:
		ui_root.open(panel)


func _save() -> void:
	var can: Dictionary = Game.can_manual_save()
	save_l.visible = true
	if not bool(can.get("ok", false)):
		save_l.text = String(can.get("reason", "You can't save right now."))
		save_l.theme_type_variation = "BadText"
		Audio.play_ui("ui_error")
		return
	var ok := SaveSystem.save_game()
	if ok:
		save_l.text = "Saved! Your journey is safe."
		save_l.theme_type_variation = "GoodText"   # the save toast plays the chime
	else:
		save_l.text = "Couldn't save: %s" % SaveSystem.last_error
		save_l.theme_type_variation = "BadText"
		Audio.play_ui("ui_error")


## Spawn id used by the unstuck option (pure logic, see tests).
static func unstuck_spawn(area_id: String, player_state: Dictionary) -> String:
	var ra := String(player_state.get("respawn_area", "surface"))
	var rs := String(player_state.get("respawn_spawn", ""))
	if area_id == "below":
		return rs if (ra == "below" and rs != "") else "mine_entry"
	if ra == "surface" and (rs == "bed" or rs.begins_with("haven")):
		return rs
	return "haven_respawn"


func _unstuck() -> void:
	if ui_root == null:
		return
	var below := Game.area_id == "below"
	var choice: String = await ui_root.confirm("Return to the last lantern?" if below else "Return to the Haven?",
		"Krystal will be carried safely back to the last lantern you lit." if below else "Krystal will be carried safely back home to the Haven.",
		[["go", "Take me there", "AccentButton"], ["cancel", "Stay here", ""]])
	if choice != "go":
		return
	var spawn := unstuck_spawn(Game.area_id, GameState.player)
	if ui_root.has_method("teleport_player"):
		ui_root.teleport_player(spawn)


func _quit_title() -> void:
	if ui_root == null:
		Game.quit_to_title()
		return
	var can: Dictionary = Game.can_manual_save()
	var choice: String
	if bool(can.get("ok", false)):
		choice = await ui_root.confirm("Return to the title?", "Would you like to save your journey first?",
			[["save", "Save & Quit", "AccentButton"], ["quit", "Quit without saving", ""], ["cancel", "Cancel", "GhostButton"]])
	else:
		choice = await ui_root.confirm("Return to the title?", "%s Anything since your last save will be lost." % String(can.get("reason", "")),
			[["quit", "Quit to Title", "AccentButton"], ["cancel", "Stay", ""]])
	if choice == "save" and not _save_for_quit():
		return
	if choice == "save" or choice == "quit":
		Game.quit_to_title()


func _quit_game() -> void:
	if ui_root == null:
		Game.quit_game()
		return
	var can: Dictionary = Game.can_manual_save()
	var choice: String
	if bool(can.get("ok", false)):
		choice = await ui_root.confirm("Quit Hollowhaven?", "Would you like to save your journey first?",
			[["save", "Save & Quit", "AccentButton"], ["quit", "Quit without saving", ""], ["cancel", "Cancel", "GhostButton"]])
	else:
		choice = await ui_root.confirm("Quit Hollowhaven?", "%s Anything since your last save will be lost." % String(can.get("reason", "")),
			[["quit", "Quit", "AccentButton"], ["cancel", "Stay", ""]])
	if choice == "save" and not _save_for_quit():
		return
	if choice == "save" or choice == "quit":
		Game.quit_game()


## Saves before quitting. On failure Krystal stays in the game with a clear message (quitting would
## silently lose progress, and the failure toast would vanish with the gameplay UI).
func _save_for_quit() -> bool:
	if SaveSystem.save_game():
		return true
	save_l.visible = true
	save_l.text = "Couldn't save, so we didn't quit: %s" % SaveSystem.last_error
	save_l.theme_type_variation = "BadText"
	Audio.play_ui("ui_error")
	return false
