extends "res://tests/test_case.gd"
## AUDIT (progression & softlocks), now a regression guard: real Game.change_area() round trip
## Below -> surface -> Below. Spec: "Death -> wake at bed/Haven or last lit dungeon lantern".
## change_area() used to reset the Below respawn to "mine_entry" on every arrival (so after a resupply
## trip deaths and "Return to last lantern" went back to the landing) and the surface respawn to the
## arrival spawn "mine_exit". Fix: Game.set_respawn remembers GameState.player["below_respawn"], which
## change_area restores; the surface respawn is the bed or "haven_respawn".
## The runner's scene is swapped for a throwaway holder so change_scene_to_file never frees the runner.

var _saved_mode: String = ""
var _runner: Node = null


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	_runner = get_tree().current_scene


func after_each() -> void:
	var cur: Node = get_tree().current_scene
	if _runner != null and is_instance_valid(_runner):
		get_tree().current_scene = _runner
	if cur != null and is_instance_valid(cur) and cur != _runner:
		cur.queue_free()
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game.player = null
	Game.area = null
	Game.area_id = ""
	Game.director = null
	Game.companion_nodes = {}
	Game.mode = _saved_mode
	get_tree().paused = false
	Audio.stop_all()
	GameState.active = false
	await wait_frames(3)


func _swap_scene_out() -> void:
	var holder := Node.new()
	holder.name = "AuditHolder"
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder


func test_lit_lantern_remembered_after_surface_trip() -> void:
	_swap_scene_out()
	GameState.set_flag("mine_opened", true)
	await Game.change_area("below", "mine_entry")
	assert_eq(Game.area_id, "below", "entered the Below")
	var cps: Variant = Game.area.get("checkpoints")
	assert_true(cps is Dictionary and (cps as Dictionary).has("shrine"), "Below has a shrine lantern")
	if not (cps is Dictionary) or not (cps as Dictionary).has("shrine"):
		return
	# Krystal gets as far as the Drowned Shrine and lights its lantern (the real node's interact()).
	(cps as Dictionary)["shrine"].interact(null)
	assert_eq(String(GameState.player["respawn_spawn"]), "cp_shrine", "lantern sets the return point")
	# She climbs out to cook more food (the landing's "Climb back up to the surface" -> change_area)...
	await Game.change_area("surface", "mine_exit")
	assert_eq(Game.area_id, "surface", "back on the surface")
	# ...and comes back down.
	await Game.change_area("below", "mine_entry")
	assert_eq(Game.area_id, "below", "back in the Below")
	assert_true(bool(GameState.get_flag("cp_lit_shrine")), "the shrine lantern is still lit")
	assert_eq(String(GameState.player["respawn_spawn"]), "cp_shrine", "death should wake her at the last lit lantern")
	var PausePanel: Script = load("res://src/ui/panels/pause_panel.gd")
	assert_eq(String(PausePanel.unstuck_spawn("below", GameState.player)), "cp_shrine", "'Return to last lantern' should go to the lit shrine lantern")


## Spec: surface deaths wake Krystal "at bed/Haven". Without a slept-in bed, one trip into the mine
## used to move the surface respawn to the mine mouth for good (game.gd change_area -> _bed_spawn_or).
func test_surface_respawn_stays_at_the_haven_after_trip() -> void:
	_swap_scene_out()
	GameState.set_flag("mine_opened", true)
	assert_eq(String(GameState.player["respawn_spawn"]), "haven_respawn", "new game: wakes at the Haven")
	await Game.change_area("below", "mine_entry")
	await Game.change_area("surface", "mine_exit")
	assert_eq(Game.area_id, "surface", "back on the surface")
	var rs := String(GameState.player["respawn_spawn"])
	assert_true(rs == "haven_respawn" or rs == "bed", "surface death should wake her at the Haven/bed, got '%s'" % rs)


## Saves from before "below_respawn" existed: on the next trip down, the deepest lit lantern is used.
func test_old_save_without_a_remembered_lantern_uses_the_deepest_lit_one() -> void:
	_swap_scene_out()
	for f in ["mine_opened", "cp_lit_landing", "cp_lit_office", "cp_lit_shrine"]:
		GameState.set_flag(f, true)
	GameState.player["below_respawn"] = ""
	GameState.player["respawn_area"] = "surface"
	GameState.player["respawn_spawn"] = "haven_respawn"
	await Game.change_area("below", "mine_entry")
	assert_eq(Game.area_id, "below", "entered the Below")
	assert_eq(String(GameState.player["respawn_spawn"]), "cp_shrine", "deepest lit lantern is the return point")
	assert_eq(String(GameState.player["below_respawn"]), "cp_shrine", "and it is remembered from now on")


## A lantern rested at later replaces the remembered one (also a shallower one: her choice).
func test_resting_at_a_lantern_updates_the_remembered_return_point() -> void:
	_swap_scene_out()
	GameState.set_flag("mine_opened", true)
	GameState.set_flag("cp_lit_shrine", true)
	GameState.player["below_respawn"] = "cp_shrine"
	await Game.change_area("below", "mine_entry")
	assert_eq(String(GameState.player["respawn_spawn"]), "cp_shrine", "remembered lantern restored")
	var cps: Variant = Game.area.get("checkpoints")
	if not (cps is Dictionary) or not (cps as Dictionary).has("landing"):
		fail("Below has a landing lantern")
		return
	(cps as Dictionary)["landing"].interact(null)
	await Game.change_area("surface", "mine_exit")
	await Game.change_area("below", "mine_entry")
	assert_eq(String(GameState.player["respawn_spawn"]), "cp_landing", "the lantern she rested at last")
