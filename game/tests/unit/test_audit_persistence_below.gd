extends "res://tests/test_case.gd"
## AUDIT (persistence integration, the Below): progression flags written to a real save, then
## Continue (Game.continue_game -> Game.load_area headless) must rebuild the Below to match:
## rubble, key, gate, lanterns (+ their safe zones), boss / stalker, Heartseed pickup, lift.
## Game.load_area uses change_scene_to_file, so each load first swaps in a throwaway current scene.

var _runner: Node = null
var _saved_mode: String = "boot"


func before_each() -> void:
	_runner = get_parent()
	_saved_mode = Game.mode
	fresh_state()


func after_each() -> void:
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


func _continue() -> bool:
	var tree := get_tree()
	if tree.current_scene == _runner or tree.current_scene == null:
		var ph := Node.new()
		ph.name = "AuditPlaceholder"
		tree.root.add_child(ph)
		tree.current_scene = ph
	var ok: bool = await Game.continue_game()
	await wait_physics(3)
	return ok


## Writes a save of the current GameState "at" a lantern (as checkpoint_lantern.interact does) and wipes
## the runtime state, like quitting to the desktop.
func _save_at(spawn: String) -> void:
	Game.set_respawn("below", spawn)
	GameState.player["area"] = "below"
	GameState.player["spawn"] = spawn
	assert_true(SaveSystem.save_game(), "save ok")
	GameState.reset()
	GameState.active = false


func _live(group: String) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(group):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and Game.area != null and Game.area.is_ancestor_of(n):
			out.append(n)
	return out


func test_mid_dungeon_key_taken_gate_still_locked() -> void:
	GameState.give_item("lantern", 1)
	for f in ["entered_below", "gallery_cleared", "foreman_key_taken", "cp_lit_landing", "cp_lit_office", "moment_threshold"]:
		GameState.set_flag(f, true)
	GameState.deplete("below_gallery_rubble", -1.0)
	GameState.give_item("foreman_key", 1)
	_save_at("cp_office")
	assert_true(await _continue(), "continue")
	var area: Node = Game.area
	assert_eq(Game.area_id, "below", "continued below")
	assert_true(Game.player.global_position.distance_to(area.get_spawn("cp_office").origin) < 0.5, "at the office lantern")
	assert_true(bool(area.rubble.cleared), "gallery rubble stays cleared")
	assert_false(area.rubble.is_in_group("harvestable"), "cleared rubble is not harvestable")
	assert_false(bool(area.gate.is_open), "gate still closed")
	assert_eq(String(area.gate.get_interaction(null).get("text", "")), "Unlock the gate", "the key opens it")
	assert_false(bool(area.desk._key_node.visible), "the key is not on the desk twice")
	assert_true(bool(area.checkpoints["landing"].lit) and bool(area.checkpoints["office"].lit), "lit lanterns stay lit")
	assert_false(bool(area.checkpoints["shrine"].lit), "unlit lantern stays unlit")
	assert_true(area.is_safe_zone(area.checkpoints["office"].global_position + Vector3(1, 0, 0)), "lit lantern is a safe zone again")
	assert_not_null(area.boss, "the Weaver is still waiting")
	assert_not_null(area.stalker, "the stalker still haunts the Hollows")
	assert_eq(_live("heartseed_pickup").size(), 0, "no Heartseed yet")
	assert_false(bool(area.lift_chamber.usable()), "lift still choked")
	assert_not_null(Game.director, "director running")


func test_after_the_weaver_the_below_is_calm_and_the_heartseed_waits_exactly_once() -> void:
	GameState.give_item("lantern", 1)
	for f in ["entered_below", "gallery_cleared", "foreman_key_taken", "lower_gate_open", "cp_lit_landing", "cp_lit_office",
			"cp_lit_shrine", "cp_lit_arena", "weaver_defeated", "heartseed_spawned_checked", "reached_silk_hollows"]:
		GameState.set_flag(f, true)
	GameState.give_item("foreman_key", 1)
	_save_at("cp_arena")
	assert_true(await _continue(), "continue")
	var area: Node = Game.area
	await wait_frames(2)
	assert_true(bool(area.gate.is_open), "gate open")
	assert_null(area.boss, "no boss after its defeat")
	assert_null(area.stalker, "no stalker after the Weaver retreated")
	assert_true(bool(area.lift_chamber.usable()), "lift runs")
	assert_true(bool(area.cocoon.opened), "cocoon open")
	assert_eq(_live("heartseed_pickup").size(), 1, "exactly one Heartseed pickup waits in the chamber")
	# Take it, rest at the arena lantern, quit and continue: it must not come back.
	var seeds := _live("heartseed_pickup")
	if seeds.size() > 0:
		seeds[0].interact(Game.player)
	assert_true(GameState.has_item("heartseed"), "Heartseed in the pouch")
	area.checkpoints["arena"].interact(Game.player)
	GameState.reset()
	GameState.active = false
	assert_true(await _continue(), "continue again")
	await wait_frames(2)
	assert_true(GameState.has_item("heartseed"), "still carrying it")
	assert_eq(_live("heartseed_pickup").size(), 0, "no second Heartseed")
	assert_eq(String(Game.area.cocoon._interaction().get("text", "")), "", "cocoon offers nothing")


func test_lift_ride_then_climb_out_saves_on_the_surface_and_continue_is_on_the_surface() -> void:
	GameState.give_item("lantern", 1)
	for f in ["entered_below", "gallery_cleared", "lower_gate_open", "cp_lit_arena", "weaver_defeated", "heartseed_spawned_checked"]:
		GameState.set_flag(f, true)
	GameState.give_item("heartseed", 1)
	_save_at("cp_arena")
	assert_true(await _continue(), "continue")
	await Game.area.ride_lift("lift_bottom")
	assert_eq(Game.mode, "playing", "ride over")
	assert_true(Game.player.global_position.distance_to(Game.area.get_spawn("lift_bottom").origin) < 0.5, "at the landing")
	await Game.change_area("surface", "mine_exit")
	await wait_physics(5)
	GameState.reset()
	GameState.active = false
	assert_true(await _continue(), "continue")
	assert_eq(Game.area_id, "surface", "continue on the surface")
	assert_true(GameState.has_item("heartseed"), "Heartseed carried home")
	assert_true(bool(GameState.get_flag("moment_return")), "THE RETURN remembered")
