extends "res://tests/test_case.gd"
## Chapter Two travel round trips through the REAL Game flow (Game.load_area / change_area /
## continue_game, the real waygate / exit / arch / rest-point nodes), headless:
##   * a Chapter-One-complete journey (structures incl. a chest with contents, a bed, crops, companions,
##     inventory order, key pouch, lore, counters, flags, quest index) travels surface -> waygate ->
##     Hallowmere Reach, is saved, reloaded from disk (SaveSystem test dir), travels back through the
##     mirror gate and is saved/reloaded again: every preserved field stays identical;
##   * interiors (manor, works) and the echo trial: exits, respawn points, rest-point saves, Continue at a
##     rest point, the trial never saving and always returning to its origin;
##   * the Lantern Road: arches light once, same-area hops and trips home to the ORIGINAL Haven.
## Only fields that legitimately move with time are left out of the comparison (clock, play time, crop
## tending by Mochi, bond XP from new zones) and the player's position/area bookkeeping.
## The runner scene is protected like test_audit_lifecycle_flow: current_scene is swapped for a
## placeholder so scene changes free the placeholder/area instead of the runner.

const Reach := preload("res://data/hallowmere_layout.gd")

var _runner: Node = null
var _saved_mode: String = ""


func before_each() -> void:
	fresh_state()
	_runner = get_tree().current_scene
	_saved_mode = Game.mode
	var ph := Node.new()
	ph.name = "Ch2Placeholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph


func after_each() -> void:
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game.mode = _saved_mode
	Game._bosses.clear()
	var cs := get_tree().current_scene
	if cs != null and cs != _runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "Ch2Placeholder" or n.name == "Surface" or n.name == "HallowmereReach" or n.name == "MoonveilManor" \
				or n.name == "HushedWorks" or n.name == "EchoTrial" or n.name == "TobinAnnex":
			n.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


# --- helpers -----------------------------------------------------------------------------------------

func _playing() -> bool:
	return Game.mode == "playing" and not Game._transitioning and Game.player != null and is_instance_valid(Game.player)


func _until(cond: Callable, max_frames: int = 1500) -> bool:
	for i in max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


## Waits until Krystal is playing in `area_name` and the travel has finished: change_area() sets the
## respawn point and saves only after load_area's 0.6 s fade-in (a hung coroutine must not hang the runner).
func _arrived(area_name: String) -> bool:
	var ok: bool = await _until(func() -> bool: return _playing() and Game.area_id == area_name)
	await wait_seconds(0.8)
	await wait_frames(4)
	return ok


func _start_area(area_name: String, spawn: String) -> bool:
	Game.load_area(area_name, spawn, false)
	return await _arrived(area_name)


func _near_spawn(spawn: String, tol: float = 1.2) -> bool:
	if Game.area == null or Game.player == null:
		return false
	var xf: Transform3D = Game.area.get_spawn(spawn)
	var p: Vector3 = Game.player.global_position
	return Vector2(p.x - xf.origin.x, p.z - xf.origin.z).length() < tol


func _saved_state() -> Dictionary:
	var saved: Dictionary = SaveSystem._read_and_validate(SaveSystem._path())
	var st: Variant = saved.get("state", {})
	return st if st is Dictionary else {}


func _respawn() -> Array:
	return [String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))]


## A finished Chapter One journey, built with GameState calls, plus Chapter Two accepted and the waygate
## repaired (so the real gate can be used).
func _build_chapter_one_state() -> void:
	fresh_state()
	GameState.active = true
	for f in ["read_ward_intro", "read_ward_warning", "ruin_cleared", "mine_opened", "mine_comfort_seen",
			"entered_below", "foreman_key_taken", "lower_gate_open", "reached_silk_hollows", "weaver_defeated",
			"ward_restored", "chapter_one_complete", "cp_lit_landing", "cp_lit_office", "moment_threshold"]:
		GameState.set_flag(f, true)
	GameState.quests.from_dict({"index": 15})
	for it in [["wood", 23], ["stone", 11], ["copper_sword", 1], ["lantern", 1], ["berries", 6],
			["sweetroot_seeds", 4], ["stone_axe", 1], ["crop_plot", 2]]:
		GameState.give_item(String(it[0]), int(it[1]))
	GameState.give_item("foreman_key", 1)
	GameState.select_hotbar(2)
	var chest := GameState.add_structure("storage_chest", Vector3(6.5, 0.0, 4.5), 90.0)
	GameState.get_storage(chest).add("fiber", 9)
	GameState.get_storage(chest).add("shiny_pebble", 2)
	var bed := GameState.add_structure("bed", Vector3(-6.5, 0.0, 3.5), 0.0)
	GameState.structures[bed]["data"] = {"respawn": true}
	GameState.add_structure("workbench", Vector3(8.5, 0.0, -2.5), 180.0)
	GameState.add_structure("haven_banner", Vector3(3.5, 0.0, 9.5), 0.0)
	var plot := GameState.add_structure("crop_plot", Vector3(-9.0, 0.0, -4.0), 0.0)
	GameState.crops[plot] = {"crop": "sweetroot", "planted_at": GameState.total_minutes - 120.0, "tended_minutes": 15.0}
	for c in ["mochi", "pebble", "lumi"]:
		GameState.befriend(c)
	GameState.add_bond("mochi", 30)
	GameState.add_bond("pebble", 12)
	GameState.set_companion_assignment("mochi", "home")
	GameState.set_companion_assignment("pebble", "home")
	GameState.set_companion_assignment("lumi", "follow")
	GameState.discover_lore("landing_notice")
	GameState.discover_lore("ward_keeper")
	GameState.add_counter("trees_felled", 14)
	GameState.add_counter("crops_planted", 3)
	GameState.deplete("tree_3", -1.0)
	GameState.total_minutes = 480.0 + 1440.0 * 6.0 + 600.0
	GameState.set_flag("ch2_accepted", true)
	GameState.set_flag("ch2_waygate_repaired", true)


## Everything that must survive travel and save/load, JSON-normalised.
func _snapshot() -> Dictionary:
	var d: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	if not (d is Dictionary):
		return {}
	var s: Dictionary = d
	s.erase("total_minutes")
	var stats: Variant = s.get("stats")
	if stats is Dictionary:
		(stats as Dictionary).erase("play_seconds")
	var p: Variant = s.get("player")
	if p is Dictionary:
		for k in ["pos", "yaw", "area", "spawn", "respawn_area", "respawn_spawn", "area_respawn"]:
			(p as Dictionary).erase(k)
	var flags: Variant = s.get("flags")
	if flags is Dictionary:
		for k in (flags as Dictionary).keys():
			if String(k).begins_with("hint_"):
				(flags as Dictionary).erase(k)
	var crops: Variant = s.get("crops")
	if crops is Dictionary:
		for uid in crops:
			if crops[uid] is Dictionary:
				(crops[uid] as Dictionary).erase("tended_minutes")
	var comps: Variant = s.get("companions")
	if comps is Dictionary:
		for id in comps:
			if comps[id] is Dictionary:
				(comps[id] as Dictionary).erase("bond_xp")
				(comps[id] as Dictionary).erase("zones")
	return s


func _assert_same(now: Dictionary, before: Dictionary, what: String) -> void:
	var bad: Array = []
	for k in before:
		if not now.has(k) or JSON.stringify(now[k]) != JSON.stringify(before[k]):
			bad.append(k)
	for k in now:
		if not before.has(k):
			bad.append(k)
	assert_eq(bad, [], "%s: preserved state differs in %s" % [what, str(bad)])
	for k in bad:
		print("    DIFF %s\n      before %s\n      now    %s" % [k, JSON.stringify(before.get(k)), JSON.stringify(now.get(k))])


# --- the Chapter One home survives the trip ---------------------------------------------------------------

func test_round_trip_to_the_reach_and_back_preserves_everything() -> void:
	_build_chapter_one_state()
	GameState.request_quest_eval()
	await wait_frames(4)
	assert_true(await _start_area("surface", "waygate"), "surface loaded at the waygate")
	await wait_frames(4)
	var before := _snapshot()
	var inv_before: Array = GameState.inventory.to_array()
	var gate: Node = Game.area.get_node_or_null("Waygate")
	assert_not_null(gate, "the waygate stands on the surface")
	if gate == null:
		return
	assert_eq(String(gate.get_interaction(Game.player)["text"]), "Travel to Hallowmere Reach")
	gate.interact(Game.player)
	assert_true(await _arrived("hallowmere_reach"), "the waygate took her to the Reach")
	assert_true(_near_spawn("waygate_arrival"), "arrived at waygate_arrival")
	var arr: Transform3D = Game.area.get_spawn("waygate_arrival")
	var sp: Variant = _saved_state().get("player", {}).get("pos")
	assert_true(sp is Array and (sp as Array).size() == 3 and Vector2(float(sp[0]) - arr.origin.x, float(sp[2]) - arr.origin.z).length() < 2.0,
		"the arrival save holds a Reach position, never the one from the Woods: %s" % str(sp))
	assert_eq(_respawn(), ["hallowmere_reach", "commons_arch"], "Reach respawn defaults to the Commons arch")
	assert_eq(String(_saved_state().get("player", {}).get("area", "")), "hallowmere_reach", "change_area saved on arrival")
	assert_true(Game.companion_nodes.has("lumi"), "the follower came along")
	_assert_same(_snapshot(), before, "in the Reach")
	assert_eq(GameState.inventory.to_array(), inv_before, "inventory slots in the same order")
	# Reload from disk and Continue: the Reach again, at the saved spot (outdoor area).
	SaveSystem.save_game(true)
	fresh_state()
	assert_eq(GameState.structures.size(), 0, "state really cleared before the reload")
	Game.continue_game()
	assert_true(await _arrived("hallowmere_reach"), "Continue resumes in the Reach")
	assert_true(_near_spawn("waygate_arrival", 2.0), "at the saved position")
	_assert_same(_snapshot(), before, "after reloading in the Reach")
	assert_eq(GameState.inventory.to_array(), inv_before, "inventory order after reload")
	# Home through the mirror gate.
	var mirror: Node = Game.area.get("waygate")
	assert_not_null(mirror, "the mirror gate")
	if mirror == null:
		return
	mirror.interact(Game.player)
	assert_true(await _arrived("surface"), "back in Hollowhaven Woods")
	assert_true(_near_spawn("waygate"), "arrived beside the waygate")
	assert_eq(_respawn(), ["surface", "bed"], "the surface return point is still her bed")
	assert_eq(Game.area_respawn_of("hallowmere_reach"), "commons_arch", "the Reach return point is remembered")
	_assert_same(_snapshot(), before, "back home")
	for uid in GameState.structures:
		assert_true(Game.area.find_children("*", "", true, false).any(func(n: Node) -> bool: return n.get("uid") == uid), "structure %s spawned again" % uid)
	SaveSystem.save_game(true)
	fresh_state()
	assert_true(SaveSystem.load_game(), "reload at home")
	_assert_same(_snapshot(), before, "saved at home and reloaded")
	assert_eq(GameState.inventory.to_array(), inv_before, "inventory order at home")


# --- interiors, rest points and the echo trial -------------------------------------------------------------

func test_interiors_rest_points_and_the_trial() -> void:
	_build_chapter_one_state()
	assert_true(await _start_area("hallowmere_reach", "waygate_arrival"), "Reach loaded")
	# Manor: in through the door, out through the front door.
	var door: Node = (Game.area.get("exits") as Dictionary).get("manor_door")
	door.interact(Game.player)
	assert_true(await _arrived("moonveil_manor"), "into the manor")
	assert_true(_near_spawn("manor_entry"), "at manor_entry")
	assert_eq(_respawn(), ["moonveil_manor", "manor_entry"], "manor default respawn")
	assert_true(bool(Game.can_manual_save()["ok"]), "the Cloakroom is safe: saving allowed")
	var out: Node = (Game.area.get("exits") as Dictionary).get("front_door")
	out.interact(Game.player)
	assert_true(await _arrived("hallowmere_reach"), "back outside")
	assert_true(_near_spawn("manor_door"), "outside the manor door")
	# The Bellhouse stair is sealed until the lanterns are linked.
	var stair: Node = (Game.area.get("exits") as Dictionary).get("bellhouse_stair")
	assert_false(bool(stair.get_interaction(Game.player)["enabled"]), "sealed before ch2_lamps_linked")
	stair.interact(Game.player)
	await wait_frames(4)
	assert_eq(Game.area_id, "hallowmere_reach", "a sealed stair goes nowhere")
	GameState.set_flag("ch2_lamps_linked", true)
	stair.interact(Game.player)
	assert_true(await _arrived("hushed_works"), "down into the Works")
	assert_true(_near_spawn("service_landing"), "at the service landing")
	assert_eq(_respawn(), ["hushed_works", "service_landing"])
	assert_true(Game.director == null, "no horror director in the placeholder Works (hook: DIRECTOR_AREAS)")
	# Rest at the lockers: respawn + save + Continue there.
	var rest: Node = Game.area.get_node_or_null("RestPoint_works_lockers")
	assert_not_null(rest, "rest point")
	if rest == null:
		return
	rest.interact(null)
	assert_eq(_respawn(), ["hushed_works", "works_lockers"], "resting sets the return point")
	assert_eq(Game.area_respawn_of("hushed_works"), "works_lockers")
	assert_eq(String(_saved_state().get("player", {}).get("spawn", "")), "works_lockers", "saved at the rest point")
	fresh_state()
	Game.continue_game()
	assert_true(await _arrived("hushed_works"), "Continue in the Works")
	assert_true(_near_spawn("works_lockers"), "resumes at the rest point (not a saved position)")
	# The echo trial: never saved, always back to its origin.
	var saved_area := String(_saved_state().get("player", {}).get("area", ""))
	Game.change_area("echo_trial", "trial_start")
	assert_true(await _arrived("echo_trial"), "in the trial")
	assert_eq(String(_saved_state().get("player", {}).get("area", "")), saved_area, "entering a trial doesn't save")
	assert_eq(_respawn(), ["hushed_works", "works_lockers"], "the trial keeps the origin as the respawn")
	assert_false(bool(Game.can_manual_save()["ok"]), "no saving in a trial")
	var leave: Node = (Game.area.get("exits") as Dictionary).get("leave")
	leave.interact(Game.player)
	assert_true(await _arrived("hushed_works"), "leaving returns to the origin area")
	assert_true(_near_spawn("works_lockers"), "at the origin checkpoint")
	# A save written inside a trial (by some other system) never resumes in the trial: Continue goes back
	# to the origin (the respawn point), not to trial_start.
	Game.change_area("echo_trial", "trial_start")
	assert_true(await _arrived("echo_trial"), "in the trial again")
	assert_true(SaveSystem.save_game(true), "forced save inside the trial")
	assert_eq(String(_saved_state().get("player", {}).get("area", "")), "echo_trial")
	fresh_state()
	Game.continue_game()
	assert_true(await _arrived("hushed_works"), "Continue leaves the trial for its origin area")
	assert_true(_near_spawn("works_lockers"), "at the origin checkpoint after Continue")
	# Back to the Reach: the Reach remembers nothing yet -> the Commons arch.
	Game.change_area("hallowmere_reach", "bellhouse_stair")
	assert_true(await _arrived("hallowmere_reach"), "up the stair")
	assert_eq(_respawn(), ["hallowmere_reach", "commons_arch"])


# --- the Lantern Road -----------------------------------------------------------------------------------------

func test_lantern_road_travel() -> void:
	_build_chapter_one_state()
	assert_true(await _start_area("hallowmere_reach", "waygate_arrival"), "Reach loaded")
	var arches: Dictionary = Game.area.get("arches")
	arches["commons"].interact(Game.player)
	arches["quarry"].interact(Game.player)
	assert_true(bool(GameState.get_flag("ch2_arch_commons")) and bool(GameState.get_flag("ch2_arch_quarry")), "two arches lit")
	assert_eq(_respawn(), ["hallowmere_reach", "quarry_arch"], "the arch lit last")
	# Same-area hop.
	assert_true(await Game.lantern_road_travel("commons"), "hop to the Commons")
	assert_true(_near_spawn("commons_arch"), "at the Commons arch")
	assert_eq(Game.area_id, "hallowmere_reach")
	assert_eq(Game.mode, "playing", "control handed back")
	assert_eq(_respawn(), ["hallowmere_reach", "commons_arch"], "travelled-to arch is the return point")
	# Home to the ORIGINAL Haven.
	Game.lantern_road_travel("haven")
	assert_true(await _arrived("surface"), "the Lantern Road leads home")
	assert_true(_near_spawn("haven_respawn"), "at the Haven")
	assert_eq(_respawn(), ["surface", "bed"])
	# At home (even at the Ward Stone, ~9 m from haven_respawn) the Haven is not offered as a destination.
	assert_true(Game._is_current_destination(Game.HAVEN_DESTINATION), "already home")
	var stone_front := Vector3(0.0, Game.area.height_at(0.0, -3.5) + 0.1, -3.5)
	Game.player.teleport(Transform3D(Basis(), stone_front))
	assert_true(Game._is_current_destination(Game.HAVEN_DESTINATION), "at the Ward Stone the Haven is where she is")
	assert_false(Game._is_current_destination(Game.lantern_road_destinations()[1]), "a Reach arch is still a destination")
	assert_eq(GameState.structures.size(), 5, "the house is untouched")
	# And back out to a lit arch in the Reach.
	Game.lantern_road_travel("quarry")
	assert_true(await _arrived("hallowmere_reach"), "back to the Reach")
	assert_true(_near_spawn("quarry_arch"), "at the quarry arch")
	assert_eq(_respawn(), ["hallowmere_reach", "quarry_arch"], "arriving at a lit arch makes it the return point")
	assert_false(await Game.lantern_road_travel("orchard"), "unlit arches are not destinations")
