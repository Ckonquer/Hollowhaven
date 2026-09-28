extends "res://tests/test_case.gd"
## CH2-017: the Choir Vault's bell-lift caption follows the in-game hour Krystal rides up into - never the "night
## air" in the morning (the QA runs rode it at 10:01 and 10:31). The lift still goes to the Reach's Bellhouse.
## COV-001: after the Choir (respawn vault_exit), the refuge hatch onto the lit refuge lantern and "Return to safety"
## in a safe room both use the nearby safe point, not the vault exit 160 m below.

const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const PausePanel := preload("res://src/ui/panels/pause_panel.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"


class FakeController extends Node:
	var rides: Array = []

	func travel_area(area_id: String, spawn_id: String, caption: String = "") -> void:
		rides.append([area_id, spawn_id, caption])


var _minutes_before := 0.0
var _game_before: Array = []


func before_each() -> void:
	fresh_state()
	_minutes_before = GameState.total_minutes
	_game_before = [Game.area, Game.area_id, Game.player, Game.in_safe_zone]


func after_each() -> void:
	GameState.total_minutes = _minutes_before
	Game.area = _game_before[0]
	Game.area_id = String(_game_before[1])
	Game.player = _game_before[2]
	Game.in_safe_zone = bool(_game_before[3])
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


func _ride_at(arena: Node, ctl: FakeController, hour: float) -> String:
	GameState.total_minutes = 2.0 * 1440.0 + hour * 60.0        # day 3 at `hour`
	arena.call("_on_exit_lift", null)
	var last: Array = ctl.rides.back() if not ctl.rides.is_empty() else ["", "", ""]
	return String(last[2])


func test_the_exit_caption_matches_the_time_of_day() -> void:
	var ctl := FakeController.new()
	add_child(ctl)
	var arena: Node3D = ChoirArena.new()
	arena.set("save_on_clear", false)
	arena.call("setup", {"controller": ctl})
	add_child(arena)
	arena.set("cleared", true)
	var morning := _ride_at(arena, ctl, 10.0 + 31.0 / 60.0)          # the QA ride (full1: 10:31)
	assert_false(GameState.is_night(), "10:31 is daytime")
	assert_false(morning.contains("night"), "no night air in the morning: %s" % morning)
	assert_eq(morning, "[the bell-lift climbs toward the morning air]")
	assert_eq(_ride_at(arena, ctl, 10.0 + 1.0 / 60.0), morning, "run6: 10:01")
	var noon := _ride_at(arena, ctl, 13.5)
	assert_false(noon.contains("night"), "midday: %s" % noon)
	var evening := _ride_at(arena, ctl, 18.5)
	assert_false(evening.contains("night"), "before 20:00 it is still evening: %s" % evening)
	for h in [21.0, 23.9, 0.5, 5.5]:
		assert_eq(_ride_at(arena, ctl, float(h)), "[the bell-lift climbs toward the night air]", "night at %.1f h" % float(h))
		assert_true(GameState.is_night(), "%.1f h counts as night" % float(h))
	for r in ctl.rides:
		assert_eq([String(r[0]), String(r[1])], [String(Layout.VAULT_EXIT_TARGET["area"]), String(Layout.VAULT_EXIT_TARGET["spawn"])],
			"the lift still rises to the Reach's Bellhouse")
	# the caption always agrees with the game clock the music and sky read
	for step in 48:
		var hh := float(step) * 0.5
		var cap := _ride_at(arena, ctl, hh)
		assert_eq(cap.contains("night"), GameState.is_night(), "%.1f h: %s" % [hh, cap])


## COV-001 in the REAL Works: after the Choir she wakes beside the vault exit (choir_arena.gd), 160 m below the
## refuge. (1) Coming back in by the refuge hatch onto the lit refuge lantern makes the refuge the return point (a
## defeat / fall wakes her there, where Continue resumes too). (2) "Return to safety" inside the refuge, the Bell
## Throat or the landing uses that room's own safe point; from a room without one (the rails) the remembered
## point is kept, and the unstuck option never moves the defeat respawn.
func test_after_the_choir_the_refuge_is_the_safe_point_near_the_refuge() -> void:
	GameState.set_flag("cp_lit_hw_refuge", true)        # she lit the refuge lantern on the way down
	var area: Node3D = load(WORLD).new()
	add_child(area)
	await wait_physics(3)
	if area.get_node_or_null("WorksDeep") == null:
		print("  SKIP: the Works area script does not build rooms 9-14")
		return
	Game.area = area
	Game.area_id = "hushed_works"
	Game.player = null
	var choir: Node = (area.get_node("WorksDeep") as Node).get("choir")
	choir.set("save_on_clear", false)
	choir.call("start_encounter")
	Events.boss_defeated.emit("borrowed_choir")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "vault_exit", "the Choir leaves her beside the exit lift")
	var vault: Vector3 = (area.get_spawn("vault_exit") as Transform3D).origin
	var refuge: Vector3 = (area.get_spawn("refuge") as Transform3D).origin
	assert_true(vault.distance_to(refuge) > 150.0, "the vault exit is far below the refuge (%.1f m)" % vault.distance_to(refuge))
	# (2) She walks back up to the refuge (the last spot she arrived at / rested: the Bell Throat).
	GameState.player["spawn"] = "bell_throat"
	var cases := [
		[Vector3(30.0, -18.0, 4.0), "refuge", "the refuge (safe room): its lantern"],
		[Vector3(157.0, -28.0, 38.0), "bell_throat", "the Bell Throat (safe): its lantern"],
		[Vector3(-70.0, -6.0, 2.0), "service_landing", "the Service Landing (safe): its lantern"],
		[Vector3(-17.0, -11.0, 0.0), "vault_exit", "the Humming Rails (no safe point): the remembered one"],
		[Vector3(157.0, -32.0, 64.0), "vault_exit", "the won vault: its exit"],
	]
	for c in cases:
		var at: Vector3 = c[0]
		GameState.player["pos"] = [at.x, at.y, at.z]
		var t := PausePanel.unstuck_target()
		assert_eq(t, String(c[1]), "%s (got %s)" % [String(c[2]), t])
	GameState.player["pos"] = [30.0, -18.0, 4.0]
	var t2 := PausePanel.unstuck_target()
	assert_true((area.get_spawn(t2) as Transform3D).origin.distance_to(Vector3(30.0, -18.0, 4.0)) < 15.0, "a few steps inside the refuge")
	assert_eq(String(GameState.player["respawn_spawn"]), "vault_exit", "the unstuck option never moves the defeat respawn")
	# (1) Next visit: down the refuge hatch onto the lit refuge lantern (what change_area does on arrival).
	Game.set_respawn("hushed_works", Game.return_point("hushed_works", "refuge"))
	assert_eq([String(GameState.player["respawn_area"]), String(GameState.player["respawn_spawn"])], ["hushed_works", "refuge"],
		"a defeat / fall right after the hatch wakes her at the refuge lantern")
	assert_eq(Game.area_respawn_of("hushed_works"), "refuge")
