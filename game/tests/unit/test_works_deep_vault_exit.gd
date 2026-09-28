extends "res://tests/test_case.gd"
## CH2-017: the Choir Vault's bell-lift caption follows the in-game hour Krystal rides up into - never the "night
## air" in the morning (the QA runs rode it at 10:01 and 10:31). The lift still goes to the Reach's Bellhouse.

const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const Layout := preload("res://data/works_layout_deep.gd")


class FakeController extends Node:
	var rides: Array = []

	func travel_area(area_id: String, spawn_id: String, caption: String = "") -> void:
		rides.append([area_id, spawn_id, caption])


var _minutes_before := 0.0


func before_each() -> void:
	fresh_state()
	_minutes_before = GameState.total_minutes


func after_each() -> void:
	GameState.total_minutes = _minutes_before
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
