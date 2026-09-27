extends "res://tests/test_case.gd"
## The Below, flow & feel (reviewer tests):
## * a real CharacterBody3D (Krystal's capsule, 46 deg floor limit, floor snap, gravity, NO step-up
##   help) walks the whole critical path down to the lift and back up again without getting stuck
##   or falling out of the level;
## * the Nursery's silence always ends when Krystal is elsewhere (also after a respawn / lift ride,
##   which reset the tracked room);
## * the director's boss-fight hold is released on death and on victory;
## * the chamber is quiet (amb_silk) once the Weaver is gone;
## * the lift ride (THE RETURN) teleports to the landing and fires once.

const Layout := preload("res://src/world/below/below_layout.gd")
const WORLD := "res://src/world/below/below_world.gd"
const SPEED := 6.0
const GRAVITY := 20.0
const DT := 1.0 / 60.0

var area: Node3D = null
var events: Array = []
var _saved_director: Node = null
var _saved_player: Node3D = null


class FakeDirector extends Node:
	var calls: Array = []

	func suppress(seconds: float, replace: bool = false) -> void:
		calls.append(seconds)


func before_each() -> void:
	fresh_state()
	events = []
	_saved_director = Game.director
	_saved_player = Game.player
	if not Events.horror_event.is_connected(_on_horror):
		Events.horror_event.connect(_on_horror)


func after_each() -> void:
	if Events.horror_event.is_connected(_on_horror):
		Events.horror_event.disconnect(_on_horror)
	if Game.director != _saved_director and Game.director != null and is_instance_valid(Game.director):
		Game.director.queue_free()
	Game.director = _saved_director
	Game.player = _saved_player
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _on_horror(id: String, _data: Dictionary) -> void:
	events.append(id)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(3)
	return a


# --- Walking with a real character body -------------------------------------------------------------

func _walker() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Walker"
	body.collision_layer = 2
	body.collision_mask = 1 | 32
	body.floor_max_angle = deg_to_rad(46.0)
	body.floor_snap_length = 0.35
	body.max_slides = 6
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	area.add_child(body)
	return body


## Walks `body` through `path` (floor points) with move_and_slide. Returns "" or what went wrong.
func _walk(body: CharacterBody3D, path: Array) -> String:
	body.global_position = (path[0] as Vector3) + Vector3.UP * 0.05
	body.velocity = Vector3.ZERO
	var vy := 0.0
	var i := 1
	var best_left := INF
	var since_progress := 0
	var steps := 0
	while i < path.size():
		var target: Vector3 = path[i]
		var p := body.global_position
		var flat := Vector3(target.x - p.x, 0.0, target.z - p.z)
		if flat.length() < 0.3:
			i += 1
			best_left = INF
			since_progress = 0
			continue
		# Never more than ~1.2 m below the path line (fell through / off something).
		var prev: Vector3 = path[i - 1]
		var seg := target - prev
		var t := 0.0
		if seg.length_squared() > 0.001:
			t = clampf((p - prev).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var expect_y: float = prev.y + seg.y * t
		if p.y < expect_y - 1.2:
			return "fell at %s (expected floor y %.2f) on the way to point %d" % [str(p.snapped(Vector3.ONE * 0.1)), expect_y, i]
		var hv := flat.normalized() * minf(SPEED, flat.length() / DT)
		vy = 0.0 if body.is_on_floor() else vy - GRAVITY * DT
		body.velocity = Vector3(hv.x, vy, hv.z)
		body.move_and_slide()
		steps += 1
		if flat.length() < best_left - 0.05:
			best_left = flat.length()
			since_progress = 0
		else:
			since_progress += 1
		if since_progress > 180:
			return "stuck at %s on the way to point %d %s" % [str(p.snapped(Vector3.ONE * 0.1)), i, str(target)]
		if steps > 40000:
			return "took too long"
	return ""


func test_krystal_can_walk_the_critical_path_down_and_back() -> void:
	GameState.set_flag("gallery_cleared", true)
	GameState.set_flag("lower_gate_open", true)
	area = await _make_area()
	var body := _walker()
	await wait_physics(2)
	assert_eq(_walk(body, Layout.CRITICAL_PATH), "", "walk down to the lift")
	var p := body.global_position
	var last: Vector3 = Layout.CRITICAL_PATH.back()
	assert_true(p.distance_to(last) < 0.6, "arrived at the lift (%s)" % str(p))
	var lift_xf: Transform3D = area.get_spawn("lift_chamber")
	var lift_it: Vector3 = lift_xf.origin
	assert_true(Vector2(p.x - lift_it.x, p.z - lift_it.z).length() < 3.0, "the lift is right there")
	var back := Layout.CRITICAL_PATH.duplicate()
	back.reverse()
	assert_eq(_walk(body, back), "", "walk back up to the landing")
	assert_eq(Layout.room_at(body.global_position + Vector3.UP * 0.5), "landing", "back at the landing")


func test_walker_is_stopped_by_the_closed_gate() -> void:
	# Sanity check of the walker itself: with the gate still locked it must report being stuck.
	GameState.set_flag("gallery_cleared", true)
	area = await _make_area()
	var body := _walker()
	await wait_physics(2)
	var res := _walk(body, Layout.CRITICAL_PATH.slice(0, 10))
	assert_true(res.begins_with("stuck"), "the locked gate stops Krystal (%s)" % res)
	assert_true(body.global_position.z > Layout.GATE_CENTER.z, "stopped on the near side of the gate")


func test_side_spaces_are_walkable_both_ways() -> void:
	GameState.set_flag("gallery_cleared", true)
	GameState.set_flag("lower_gate_open", true)
	area = await _make_area()
	var body := _walker()
	await wait_physics(2)
	var k := 0
	for path in Layout.SIDE_PATHS:
		assert_eq(_walk(body, path), "", "side path %d out" % k)
		var back: Array = (path as Array).duplicate()
		back.reverse()
		assert_eq(_walk(body, back), "", "side path %d back" % k)
		k += 1


# --- Silence, fight hold, ambience -------------------------------------------------------------------

func test_nursery_silence_ends_after_a_respawn_elsewhere() -> void:
	area = await _make_area()
	var m: Node = area.moments
	var probe := Node3D.new()
	area.add_child(probe)
	m.player_override = probe
	probe.global_position = Vector3(104.75, -10.0, -70.0)
	m.check(probe, 0.1)
	assert_true(m.in_silence, "silence in the nursery")
	# Krystal is carried back to a lantern (death / lift): the tracked room is reset to "".
	area._on_player_respawned()
	probe.global_position = area.get_spawn("cp_arena").origin
	m.check(probe, 0.1)
	assert_false(m.in_silence, "the silence ends away from the nursery even after a room reset")
	if Audio.has_sound("amb_silk"):
		assert_eq(Audio.current_ambience(), "amb_silk", "the Silk Hollows ambience is back")
	# ...and the director is no longer held quiet every few seconds.
	var fake := FakeDirector.new()
	add_child(fake)
	Game.director = fake
	m.check(probe, 5.0)
	assert_eq(fake.calls.size(), 0, "no more silence suppression once outside")


func test_fight_hold_is_released_on_death_and_on_victory() -> void:
	area = await _make_area()
	var fake := FakeDirector.new()
	add_child(fake)
	Game.director = fake
	area.fight_active = true
	area._on_player_died()
	assert_false(area.fight_active, "fight ends when Krystal is defeated")
	assert_true(fake.calls.size() > 0 and float(fake.calls.back()) < 600.0, "death replaces the 9999 s fight hold (%s)" % str(fake.calls))
	fake.calls.clear()
	area.fight_active = true
	Events.boss_defeated.emit("weaver_matron")
	assert_false(area.fight_active, "fight over after the victory")
	assert_true(bool(GameState.get_flag("weaver_defeated")), "defeat recorded")
	assert_null(area.stalker, "the stalker (the Weaver itself) no longer haunts the way home")
	assert_true(fake.calls.size() > 0 and float(fake.calls.back()) < 600.0, "victory replaces the fight hold (%s)" % str(fake.calls))
	# Afterwards the chamber (boss zone) plays the calm silk ambience, not the boss loop.
	if Audio.has_sound("amb_silk"):
		area._play_zone_ambience("boss")
		assert_eq(Audio.current_ambience(), "amb_silk", "quiet chamber after the Weaver")


func test_lift_ride_is_the_return_and_fires_once() -> void:
	GameState.set_flag("weaver_defeated", true)
	area = await _make_area()
	assert_null(area.stalker, "no stalker after the Weaver is defeated")
	var stalkers := 0
	for s in area.get_tree().get_nodes_in_group("stalker"):
		if area.is_ancestor_of(s):
			stalkers += 1
	assert_eq(stalkers, 0, "no stalker node in the level")
	var gd := GDScript.new()
	gd.source_code = "extends Node3D\nfunc teleport(xf: Transform3D) -> void:\n\tglobal_transform = xf\n"
	assert_eq(gd.reload(), OK, "probe script")
	var probe: Node3D = Node3D.new()
	probe.set_script(gd)
	area.add_child(probe)
	probe.global_position = area.get_spawn("lift_chamber").origin
	Game.player = probe
	area.lift_chamber.interact(null)
	assert_true(area._riding, "riding")
	area.lift_chamber.interact(null)     # a second press while riding does nothing
	var t := 0.0
	while area._riding and t < 8.0:
		await wait_seconds(0.25)
		t += 0.25
	assert_false(area._riding, "ride finished")
	assert_true(probe.global_position.distance_to(area.get_spawn("lift_bottom").origin) < 0.2, "arrived at the landing")
	assert_true(bool(GameState.get_flag("moment_return")), "THE RETURN flagged")
	assert_eq(events.count("authored:return"), 1, "return fired once")
	assert_true(area.is_safe_zone(probe.global_position), "the lift arrives in the safe landing")
	# Riding up again (e.g. after going back down) does not repeat the moment.
	await area.ride_lift("lift_bottom")
	assert_eq(events.count("authored:return"), 1, "no second return moment")
	assert_false(area._riding, "second ride finished")
