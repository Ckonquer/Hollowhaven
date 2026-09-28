extends "res://src/ui/panels/panel_base.gd"
## Pause menu: Resume, Save Game (with feedback), Settings, Controls, Wardrobe (always available: styling
## is free and cosmetic), Comfort, an "unstuck" option (Return to the Haven on the surface / Return to
## last lantern below / Return to safety in the Chapter Two areas, using Game.return_point() - in the indoor
## ones a safe point in Krystal's own room comes first, COV-001; "Leave the trial" in an Echo Trial), Quit to
## Title (confirm, offers to save when allowed) and Quit Game.
## Echo Trial (lead decision, MP section 15): the option leaves THROUGH the trial - Game.area.leave() when the
## trial offers it, else the saved respawn point (the origin checkpoint the trial was entered from) - so
## Krystal is back at the checkpoint with her progress intact, never sent to the trial's own entry pad.

## Unstuck fallbacks for areas without a remembered return point (Game.AREA_DEFAULT_RESPAWN covers the
## others): a trial always has its entry pad.
const UNSTUCK_DEFAULTS := {"echo_trial": "trial_start"}
## Areas whose pause option leaves the area for its origin instead of moving Krystal inside it.
const TRIAL_AREAS := ["echo_trial"]

var sub_l: Label
var save_btn: Button
var save_l: Label
var unstuck_btn: Button
var wardrobe_btn: Button
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
	wardrobe_btn = Kit.button("Wardrobe", func() -> void: _open("wardrobe"))
	wardrobe_btn.tooltip_text = "Change Krystal's look. Free, and cosmetic only."
	col.add_child(wardrobe_btn)
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
	# The goal of the chapter she is in (Chapter Two once accepted), arachnophobia-aware.
	var obj: Dictionary = GameState.current_objective()
	var goal := String(obj.get("title", ""))
	if goal == "":
		goal = "Free play"
	sub_l.text = "Day %d  ·  %s  ·  %s" % [GameState.day(), UiUtil.format_clock(GameState.hour()), goal]
	var can: Dictionary = Game.can_manual_save()
	save_btn.disabled = not bool(can.get("ok", false))
	save_btn.tooltip_text = String(can.get("reason", ""))
	if save_btn.disabled:
		save_l.text = String(can.get("reason", ""))
		save_l.visible = save_l.text != ""
	unstuck_btn.text = unstuck_label(Game.area_id)
	unstuck_btn.tooltip_text = unstuck_tooltip(Game.area_id)


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


## True for the legacy areas whose unstuck keeps its Chapter One wording and target ("" = debug areas).
static func _legacy_area(area_id: String) -> bool:
	return area_id == "surface" or area_id == "below" or area_id == ""


static func is_trial_area(area_id: String) -> bool:
	return TRIAL_AREAS.has(area_id)


static func unstuck_label(area_id: String) -> String:
	if area_id == "below":
		return "Return to last lantern"
	if is_trial_area(area_id):
		return "Leave the trial"
	return "Return to the Haven" if _legacy_area(area_id) else "Return to safety"


static func unstuck_tooltip(area_id: String) -> String:
	if area_id == "below":
		return "Stuck? Safely return to your last lit lantern."
	if is_trial_area(area_id):
		return "Step out of the echo, back to the checkpoint where it began. Nothing you've done is lost."
	return "Stuck? Walk home in the blink of an eye." if _legacy_area(area_id) else "Stuck? Safely return to the last safe spot here."


## Where leaving a trial goes when the trial itself can't say: the saved respawn point (the origin checkpoint
## the trial made it on entry), never a trial; else the Haven. {"area", "spawn"}. Pure; see tests.
static func trial_exit_destination(player_state: Dictionary) -> Dictionary:
	var ra := String(player_state.get("respawn_area", ""))
	var rs := String(player_state.get("respawn_spawn", ""))
	if ra == "" or rs == "" or is_trial_area(ra):
		return {"area": "surface", "spawn": "haven_respawn"}
	return {"area": ra, "spawn": rs}


## Spawn id used by the unstuck option (pure logic, see tests). Surface: the bed or the Haven. Below: the
## last lantern (else the mine entry). Other areas: the remembered return point of that area
## (player_state.area_respawn), else the respawn point when it is in that area, else `defaults[area]`
## ("" when nothing is known: the caller then asks Game / the area).
static func unstuck_spawn(area_id: String, player_state: Dictionary, defaults: Dictionary = {}) -> String:
	var ra := String(player_state.get("respawn_area", "surface"))
	var rs := String(player_state.get("respawn_spawn", ""))
	if area_id == "below":
		return rs if (ra == "below" and rs != "") else "mine_entry"
	if _legacy_area(area_id):
		if ra == "surface" and (rs == "bed" or rs.begins_with("haven")):
			return rs
		return "haven_respawn"
	var ar: Variant = player_state.get("area_respawn")
	if ar is Dictionary and String((ar as Dictionary).get(area_id, "")) != "":
		return String((ar as Dictionary)[area_id])
	if ra == area_id and rs != "":
		return rs
	return String(defaults.get(area_id, ""))


## Where "unstuck" takes Krystal in the current area: the surface keeps its legacy rule; every other area
## asks Game.return_point() (the Below's last lantern, a lit arch / checkpoint in Chapter Two areas) and
## only uses a spawn the loaded area really registers. COV-001: in an indoor Chapter Two area a safe point in
## the room she stands in comes first (nearby_target), so she is never carried out of a safe room (the Works
## refuge, the manor cloakroom) to a rest point far away. A defeat still wakes her at the return point.
static func unstuck_target() -> String:
	var a := Game.area_id
	if a == "surface" or a == "":
		return unstuck_spawn(a, GameState.player)
	var defaults: Dictionary = UNSTUCK_DEFAULTS.duplicate()
	defaults.merge(Game.AREA_DEFAULT_RESPAWN)
	var fallback := unstuck_spawn(a, GameState.player, defaults)
	var target := fallback
	if Game.has_method("return_point"):
		target = String(Game.return_point(a, fallback))
	var spawns: Variant = Game.area.get("spawns") if Game.area != null and is_instance_valid(Game.area) else null
	if spawns is Dictionary and not (spawns as Dictionary).is_empty() and not (spawns as Dictionary).has(target):
		if (spawns as Dictionary).has(fallback):
			target = fallback
		else:
			for id in (spawns as Dictionary):
				target = String(id)
				break
	var near := nearby_target(a, target)
	return near if near != "" else target


## Areas whose "Return to safety" looks for a safe point in Krystal's room first: the indoor Chapter Two areas.
## Not the legacy surface / Below, not a trial, and not an outdoor area (the lit arches are the Reach's safe
## points, and Continue resumes there at the saved spot, not at a spawn).
static func uses_nearby_rule(area_id: String) -> bool:
	return not _legacy_area(area_id) and not is_trial_area(area_id) and not Game.OUTDOOR_AREAS.has(area_id)


## The spawns "Return to safety" may pick nearby in area node `a`, registered ones only, no duplicates: every
## checkpoint's spawn (a lantern / candle, lit or not: each keeps a safe nook where she wakes), `arrival` (where
## she came in or last rested this visit, GameState.player.spawn, where Continue resumes) and `area_default`
## (the area's own entrance, Game.AREA_DEFAULT_RESPAWN). Pure over the area node; see tests.
static func nearby_candidates(a: Node, arrival: String, area_default: String) -> Array:
	var out: Array = []
	if a == null or not is_instance_valid(a) or not (a.get("spawns") is Dictionary):
		return out
	var spawns: Dictionary = a.get("spawns")
	var ids: Array = Game.checkpoint_spawns(a).keys()
	ids.append(arrival)
	ids.append(area_default)
	for id in ids:
		var s := String(id)
		if s != "" and spawns.has(s) and not out.has(s):
			out.append(s)
	return out


## COV-001: the candidate nearest to `pos` in the zone Krystal stands in, "" when her zone has none. When she
## stands in a safe zone (`safe`) whose zone has no candidate, the nearest candidate that itself stands in a safe
## zone, if it is closer than `max_dist` (the remembered point); else "". Pure over the area node; see tests.
static func nearby_spawn(a: Node, candidates: Array, pos: Vector3, safe: bool, max_dist: float = INF) -> String:
	if a == null or not is_instance_valid(a) or not (a.get("spawns") is Dictionary) or not a.has_method("get_zone_at"):
		return ""
	var spawns: Dictionary = a.get("spawns")
	var zone := String(a.get_zone_at(pos))
	var best := ""
	var best_d := INF
	if zone != "":
		for id in candidates:
			var o: Vector3 = (spawns[id] as Transform3D).origin
			var d := o.distance_to(pos)
			if String(a.get_zone_at(o)) == zone and d < best_d:
				best = String(id)
				best_d = d
	if best != "" or not safe or not a.has_method("is_safe_zone"):
		return best
	best_d = max_dist
	for id in candidates:
		var o: Vector3 = (spawns[id] as Transform3D).origin
		var d := o.distance_to(pos)
		if d < best_d and bool(a.is_safe_zone(o)):
			best = String(id)
			best_d = d
	return best


## The nearby safe point for the live game ("" = none; the caller keeps `remembered`): Krystal's position (the
## player node, else the saved one) in the loaded area, which must be area `area_id` and use the nearby rule.
static func nearby_target(area_id: String, remembered: String) -> String:
	if not uses_nearby_rule(area_id) or not is_instance_valid(Game.area):
		return ""
	var a: Node = Game.area
	var pos: Variant = null
	if is_instance_valid(Game.player) and Game.player.is_inside_tree():
		pos = Game.player.global_position
	else:
		var saved: Variant = GameState.player.get("pos")
		if saved is Array and (saved as Array).size() == 3:
			pos = Vector3(float(saved[0]), float(saved[1]), float(saved[2]))
	if not (pos is Vector3) or not (a.get("spawns") is Dictionary):
		return ""
	var here: Vector3 = pos
	var safe: bool = Game.in_safe_zone
	if a.has_method("is_safe_zone"):
		safe = bool(a.is_safe_zone(here))       # what Game.player_in_safe_zone() answers for the live player
	var cands := nearby_candidates(a, String(GameState.player.get("spawn", "")), String(Game.AREA_DEFAULT_RESPAWN.get(area_id, "")))
	var spawns: Dictionary = a.get("spawns")
	var max_dist := INF
	if spawns.has(remembered):
		max_dist = (spawns[remembered] as Transform3D).origin.distance_to(here)
	return nearby_spawn(a, cands, here, safe, max_dist)


func _unstuck() -> void:
	if ui_root == null:
		return
	var a := Game.area_id
	if is_trial_area(a):
		var pick: String = await ui_root.confirm("Leave the trial?", "Krystal will step out of the echo and back to the checkpoint where it began. Nothing she has done is lost.",
			[["go", "Leave the trial", "AccentButton"], ["cancel", "Stay", ""]])
		if pick == "go":
			leave_trial()
		return
	var below := a == "below"
	var legacy := _legacy_area(a)
	var head := "Return to the last lantern?" if below else ("Return to the Haven?" if legacy else "Return to safety?")
	var text := "Krystal will be carried safely back to the last lantern you lit." if below else \
		("Krystal will be carried safely back home to the Haven." if legacy else "Krystal will be carried safely back to the last safe spot here.")
	var choice: String = await ui_root.confirm(head, text, [["go", "Take me there", "AccentButton"], ["cancel", "Stay here", ""]])
	if choice != "go":
		return
	var spawn := unstuck_target()
	if ui_root.has_method("teleport_player"):
		ui_root.teleport_player(spawn)


## Leaves the trial for its origin checkpoint: closes the menus (unpausing), then the trial's own leave() (its
## exit door's destination: the respawn point set on entry) or, without one, Game.change_area to the saved
## respawn point. Progress is untouched (Game.change_area autosaves on arrival at the origin).
func leave_trial() -> void:
	if ui_root != null and ui_root.has_method("close_all"):
		ui_root.close_all()
	var ar: Node = Game.area
	if ar != null and is_instance_valid(ar) and ar.has_method("leave"):
		ar.call("leave")
		return
	var d := trial_exit_destination(GameState.player)
	Game.change_area(String(d["area"]), String(d["spawn"]))


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
