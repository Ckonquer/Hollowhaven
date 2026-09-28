extends "res://tests/test_case.gd"
## AUDIT VERIFY (companions). Each test asserts the INTENDED behaviour. Headless only, manual ticks,
## no saves written. REGRESSION (fixed): lift ride vs. a companion told to WAIT. below_world.gd
## ride_lift calls teleport_near on every companion node; companion.teleport_near now only moves the
## follower, so a waiting companion stays at its spot (both directions) and the follower still rides.

const CompanionScript := preload("res://src/companions/companion.gd")
const WORLD := "res://src/world/below/below_world.gd"

var area: Node3D = null
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_mode: String = ""
var _saved_area_id: String = ""
var _saved_companions: Dictionary = {}


func before_each() -> void:
	fresh_state()
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_mode = Game.mode
	_saved_area_id = Game.area_id
	_saved_companions = Game.companion_nodes
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	Game.area = _saved_area
	Game.player = _saved_player
	Game.mode = _saved_mode
	Game.area_id = _saved_area_id
	Game.companion_nodes = _saved_companions
	await wait_frames(2)


func _setup_below(player_spawn: String) -> Node3D:
	GameState.set_flag("weaver_defeated", true)
	area = load(WORLD).new()
	add_child(area)
	await wait_physics(3)
	Game.area_id = "below"
	var gd := GDScript.new()
	gd.source_code = "extends Node3D\nfunc teleport(xf: Transform3D) -> void:\n\tglobal_transform = xf\n"
	assert_eq(gd.reload(), OK)
	var probe: Node3D = Node3D.new()
	probe.set_script(gd)
	area.add_child(probe)
	probe.global_position = area.get_spawn(player_spawn).origin
	Game.player = probe
	return probe


func _pebble(mode: String, pos: Vector3) -> Node3D:
	GameState.companion("pebble")["befriended"] = true
	if mode == "wait":
		GameState.set_companion_assignment("pebble", "wait", "below", pos)
	else:
		GameState.set_companion_assignment("pebble", "follow")
	var c: Node3D = CompanionScript.new()
	c.setup({"id": "pebble", "mode": mode, "home": Vector3.ZERO, "wild": Vector3.ZERO, "wait": pos})
	area.add_child(c)
	c.global_position = pos + Vector3.UP * 0.05
	Game.companion_nodes = {"pebble": c}
	await wait_physics(2)
	return c


## Up: waiting in the Heartseed Chamber, Krystal rides up. What does she see at the landing?
func test_lift_up_waiting_companion_visible_behaviour() -> void:
	var probe := await _setup_below("lift_chamber")
	var wait_spot := Vector3(99.0, -12.0, -141.0)
	var c := await _pebble("wait", wait_spot)
	await area.call("ride_lift", "lift_bottom")
	var d0 := c.global_position.distance_to(probe.global_position)
	var w0 := c.global_position.distance_to(wait_spot)
	var t := 0.0
	var moved := 0.0
	var last := c.global_position
	while t < 3.0:
		await wait_physics(1)
		t += get_physics_process_delta_time()
		moved += c.global_position.distance_to(last)
		last = c.global_position
	var d1 := c.global_position.distance_to(probe.global_position)
	print("    after the ride: %.1f m from Krystal, %.0f m from its wait spot; 3 s later %.1f m from Krystal, walked %.1f m, mode %s, still %.0f m from the spot" % [
		d0, w0, d1, moved, String(c.get("mode")), c.global_position.distance_to(wait_spot)])
	assert_true(w0 < 5.0, "a waiting companion is not carried up with Krystal (was put %.1f m from her, %.0f m from its spot)" % [d0, w0])
	var saved: Variant = GameState.companion("pebble").get("wait_pos")
	assert_true(saved is Array, "saved wait spot is untouched by the ride")


## Down: waiting at the Mine Landing, Krystal rides down to the chamber.
func test_lift_down_leaves_a_companion_waiting_at_the_landing() -> void:
	var probe := await _setup_below("lift_bottom")
	var spot: Vector3 = probe.global_position + Vector3(-1.5, 0.0, 1.5)
	var c := await _pebble("wait", spot)
	var spot_now := c.global_position
	await area.call("ride_lift", "lift_chamber")
	var dist := c.global_position.distance_to(spot_now)
	print("    landing wait -> after the ride down: %.0f m from its spot, %.1f m from Krystal" % [dist, c.global_position.distance_to(probe.global_position)])
	assert_true(dist < 5.0, "a companion waiting at the landing stays there when Krystal rides down (moved %.0f m)" % dist)


## Regression guard for the fix: the FOLLOWER still rides along.
func test_lift_still_carries_the_follower() -> void:
	var probe := await _setup_below("lift_chamber")
	var c := await _pebble("follow", probe.global_position + Vector3(1.0, 0.0, 1.0))
	await area.call("ride_lift", "lift_bottom")
	var d := c.global_position.distance_to(probe.global_position)
	assert_true(d < 6.0, "the follower arrives beside Krystal (%.1f m)" % d)
