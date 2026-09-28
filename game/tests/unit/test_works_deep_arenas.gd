extends "res://tests/test_case.gd"
## Weaver's Crossing and Choir Vault arenas: the APIs the boss modules will use (anchors, line-braziers,
## landing points, temporary threads, lantern anchors, resonators with the taught symbols, the safe
## perimeter), the guarded boss hooks (no crash while crossing_matron / borrowed_choir scripts are missing,
## a spawned Choir that vanishes without a defeat falls back, fallback completion, debug/test hooks), rewards
## and flags exactly once (rw_ch2_crossing -> ch2_crossing_cleared; ch2_choir_defeated), the route onward /
## service gate, the vault exit, and the vault's calm ambience after the victory (and on later builds).

const Host := preload("res://src/world/works/deep/deep_preview_host.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const CrossingArena := preload("res://src/world/works/deep/crossing_arena.gd")
const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const MASK := 1 | 32

var host: Node3D = null
var dummy: Node3D = null
var _saved := {}


func before_each() -> void:
	fresh_state()
	GameState.give_item("lantern", 1)
	for k in ["high_visibility_cues", "timing_assist"]:
		_saved[k] = Settings.get_value(k)


func after_each() -> void:
	if host != null and is_instance_valid(host):
		host.queue_free()
	host = null
	if dummy != null and is_instance_valid(dummy):
		dummy.queue_free()
	dummy = null
	for k in _saved:
		Settings.set_value(k, _saved[k])
	await wait_frames(2)


func _make() -> Node3D:
	var h: Node3D = Host.new()
	h.set("with_environment", false)
	add_child(h)
	await wait_physics(3)
	return h


func _dummy(at: Vector3) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar lantern_on := false\nfunc teleport(xf: Transform3D) -> void:\n\tglobal_transform = xf\nfunc set_lantern(on: bool) -> void:\n\tlantern_on = on\n"
	s.reload()
	var d: Node3D = s.new()
	add_child(d)
	d.global_position = at
	return d


func _ctl() -> Node:
	return host.get("deep")


func _space() -> PhysicsDirectSpaceState3D:
	return host.get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return _space().intersect_ray(q)


func _capsule_free(feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 1.1)
	q.collision_mask = MASK
	return _space().intersect_shape(q, 4).is_empty()


# --- Weaver's Crossing ----------------------------------------------------------------------------------

func test_crossing_api_for_the_boss_module() -> void:
	host = await _make()
	var a: Node = _ctl().get("crossing")
	assert_true(a.is_in_group("hw_arena") and String(a.get_meta("arena_id")) == "crossing")
	var anchors: Array = a.call("anchor_points")
	assert_eq(anchors.size(), 5, "authored ceiling anchors")
	for p in anchors:
		var v: Vector3 = p
		assert_true(v.y > float(a.call("deck_y")) + 8.0 and v.y < float(Layout.CROSSING["ceiling_y"]), "anchor %s high over the deck, under the ceiling" % str(v))
		assert_false(_ray(v, v + Vector3.UP * 3.0).is_empty(), "anchor %s hangs from real ceiling" % str(v))
		assert_true((a.call("bridge_rect") as Rect2).has_point(Vector2(v.x, v.z)), "anchor over the bridge (line of sight to a landing)")
	var markers: Array = a.call("anchor_markers")
	assert_true(markers.size() == 5 and markers[0] is Marker3D, "anchors are Marker3D nodes")
	var braziers: Array = a.call("braziers")
	assert_eq(braziers.size(), 3, "three line-braziers")
	for i in 3:
		var b: Node3D = braziers[i]
		assert_true(b.has_method("light") and b.has_signal("lit") and b.has_method("is_lit"), "boss_brazier API")
		assert_eq(a.call("brazier_for_anchor", i), b)
		assert_eq(int(a.call("line_of_brazier", b)), i)
		assert_true(bool(a.call("is_on_bridge", b.global_position)), "brazier %d stands on the bridge" % i)
		assert_true(Vector2(b.global_position.x - (anchors[i] as Vector3).x, b.global_position.z - (anchors[i] as Vector3).z).length() < 0.5, "under anchor %d" % i)
		assert_false(bool(b.call("is_lit")), "unlit before the fight")
	var land: Array = a.call("landing_points")
	assert_true(land.size() >= 12, "plenty of valid landing points (%d)" % land.size())
	for p in land:
		var v: Vector3 = p
		assert_true(bool(a.call("is_on_bridge", v)), "landing on the deck")
		assert_true(absf(v.z) < float(Layout.CROSSING["rail"]) - 0.5, "inside the rails")
		assert_false(_ray(v + Vector3.UP, v + Vector3.DOWN).is_empty(), "solid deck under %s" % str(v))
		assert_true(_capsule_free(v), "clear landing at %s" % str(v))
	var c: Vector3 = a.call("clamp_to_bridge", Vector3(88.0, -30.0, 40.0))
	assert_true(bool(a.call("is_on_bridge", c)), "clamp lands on the deck")
	var params: Dictionary = a.call("boss_params")
	for k in ["arena_center", "arena_radius", "anchors", "braziers", "crack", "arena", "bridge", "deck_y", "landing_points"]:
		assert_true(params.has(k), "boss param %s" % k)
	# rails: nobody is knocked off the bridge (a push outward at knee and chest height hits the rail)
	for x in [74.0, 88.0, 102.0]:
		for side in [-1.0, 1.0]:
			assert_false(_ray(Vector3(x, -17.5, 0.0), Vector3(x, -17.5, side * 7.0)).is_empty(), "guardrail at knee height")
			assert_false(_ray(Vector3(x, -16.6, 0.0), Vector3(x, -16.6, side * 7.0)).is_empty(), "guardrail at chest height")


func test_crossing_boss_hook_is_guarded_and_the_test_hook_clears_it_once() -> void:
	host = await _make()
	var a: Node = _ctl().get("crossing")
	dummy = _dummy(Vector3(70.0, -18.0, 0.0))
	_ctl().set("player_override", dummy)
	_ctl().call("check", 0.1)
	assert_false(bool(a.get("active")), "not on the bridge yet")
	dummy.global_position = Vector3(76.0, -18.0, 0.0)
	_ctl().call("check", 0.1)
	assert_true(bool(a.get("active")), "stepping onto the bridge starts the encounter")
	if not CrossingArena.boss_available():
		assert_true(bool(a.get("fallback")), "boss script missing: guarded fallback, no crash")
		assert_null(a.get("boss"), "no boss node")
	assert_false(bool(GameState.get_flag("ch2_crossing_cleared")))
	assert_true(bool(_ctl().call("debug_clear_crossing")), "debug/test hook (debug build)")
	assert_true(bool(GameState.get_flag("ch2_crossing_cleared")), "flag from the reward bundle")
	assert_true(GameState.has_reward("rw_ch2_crossing"), "content bundle granted")
	var t0: float = float(GameState.ledger["rw_ch2_crossing"])
	assert_false(bool(a.get("active")))
	a.call("clear_encounter")
	Events.boss_defeated.emit("crossing_matron")
	assert_eq(float(GameState.ledger["rw_ch2_crossing"]), t0, "granted exactly once")
	assert_false(GameState.has_reward("rw_ch2_weaver_crossing"), "the Thread Veil step reward is the quest layer's, never granted here")
	assert_eq(GameState.count_item("thread_veil"), 0, "no Thread Veil from the content module")
	var exit: Node = a.get("exit_veil")
	assert_false(bool(exit.call("is_blocking")), "the route onward opens")
	assert_true(bool(a.call("route_gate_shut")), "the service gate closes the Matron's deeper route")
	for b in a.call("braziers"):
		assert_true(bool((b as Node).call("is_lit")), "braziers burn on after victory")
	_ctl().call("check", 0.1)
	assert_false(bool(a.get("active")), "never restarts once cleared")


func test_crossing_boss_defeated_event_and_fallback_braziers() -> void:
	host = await _make()
	var a: Node = _ctl().get("crossing")
	Events.boss_defeated.emit("weaver_matron")
	assert_false(bool(GameState.get_flag("ch2_crossing_cleared")), "another boss id is ignored")
	Events.boss_defeated.emit("crossing_matron")
	assert_true(bool(GameState.get_flag("ch2_crossing_cleared")), "Events.boss_defeated(crossing_matron) clears it")
	assert_true(GameState.has_reward("rw_ch2_crossing"))
	assert_false(bool(GameState.get_flag("weaver_defeated")), "Chapter One flags untouched")
	# fresh save: the line-braziers alone finish it when the boss script is missing
	host.queue_free()
	await wait_frames(2)
	fresh_state()
	GameState.give_item("lantern", 1)
	host = await _make()
	a = _ctl().get("crossing")
	a.call("start_encounter")
	if CrossingArena.boss_available():
		return
	var lines: Array = []
	a.connect("line_lit", func(i: int) -> void: lines.append(i))
	var bz: Array = a.call("braziers")
	(bz[0] as Node).call("light")
	(bz[1] as Node).call("light")
	assert_false(bool(a.get("cleared")), "two of three is not enough")
	(bz[2] as Node).call("light")
	assert_eq(lines, [0, 1, 2], "line_lit per brazier")
	assert_true(bool(a.get("cleared")), "all three line-braziers lit: the crossing clears")
	assert_true(bool(GameState.get_flag("ch2_crossing_cleared")))


func test_crossing_flag_set_by_the_boss_module_commits_once() -> void:
	host = await _make()
	var a: Node = _ctl().get("crossing")
	for i in 3:
		var b: Node = (a.call("braziers") as Array)[i]
		assert_eq(int(b.get_meta("anchor_index", -1)), i, "brazier %d names its anchor for the boss module" % i)
		assert_eq(b.get_meta("anchor", Vector3.ZERO), Layout.CROSSING["anchors"][i])
	a.call("start_encounter")
	GameState.set_flag("ch2_crossing_cleared", true)      # e.g. a spawner's quest_flag_on_clear
	assert_true(bool(a.call("is_cleared")), "the arena follows the flag")
	assert_false(bool(a.get("active")), "the fight ends")
	assert_true(GameState.has_reward("rw_ch2_crossing"), "the content bundle is committed")
	var t0: float = float(GameState.ledger["rw_ch2_crossing"])
	Events.boss_defeated.emit("crossing_matron")
	assert_eq(float(GameState.ledger["rw_ch2_crossing"]), t0, "still once")
	assert_false(bool((a.get("exit_veil") as Node).call("is_blocking")), "the route onward opens")
	assert_true(bool(a.call("route_gate_shut")), "the service gate shuts the deeper route")


func test_crossing_encounter_resets_on_death_and_leaving() -> void:
	host = await _make()
	var a: Node = _ctl().get("crossing")
	a.call("start_encounter")
	var t: Node = a.call("spawn_thread", Vector3(85.0, -18.0, -4.0), Vector3(85.0, -18.0, 4.0), 20.0, -1)
	Events.player_died.emit()
	assert_false(bool(a.get("active")), "death ends the encounter (retry from the checkpoint)")
	await wait_frames(1)
	assert_false(is_instance_valid(t) and not t.is_queued_for_deletion(), "thrown threads are cleared")
	a.call("start_encounter")
	dummy = _dummy(Vector3(64.0, -18.0, 0.0))
	a.call("check", dummy)
	assert_false(bool(a.get("active")), "retreat to the gate ends it too")


# --- Choir Vault -----------------------------------------------------------------------------------------

func test_choir_api_anchors_resonators_perimeter() -> void:
	host = await _make()
	var a: Node = _ctl().get("choir")
	assert_true(a.is_in_group("hw_arena") and String(a.get_meta("arena_id")) == "choir")
	var anchors: Array = a.call("anchor_nodes")
	assert_eq(anchors.size(), 3, "three fixed lantern anchors")
	var c: Vector3 = a.call("arena_center")
	for n in anchors:
		var an: Node3D = n
		assert_true(an.has_signal("raised") and an.has_method("raise") and an.has_method("is_raised"), "anchor API")
		var d := Vector2(an.global_position.x - c.x, an.global_position.z - c.z).length()
		assert_true(d > 4.0 and d < float(a.call("perimeter_radius")), "anchor inside the arena, off the perimeter")
		assert_true(bool(an.call("raise", null)), "the ordinary lantern raises it")
		assert_true(an.is_in_group("light_source") and float(an.get("light_radius")) > 5.0, "a raised anchor is a strong light")
		an.call("tick", 100.0)
		assert_false(bool(an.call("is_raised")), "and lowers again")
	Settings.set_value("timing_assist", true)
	assert_true(float((anchors[0] as Node).call("reveal_time")) > float((anchors[0] as Node).get("reveal_seconds")), "timing assist lengthens the reveal")
	var res: Array = a.call("resonator_nodes")
	assert_eq(res.size(), 2, "two fixed resonators")
	var sym_ids: Array = []
	for s in Layout.bell_symbols():
		sym_ids.append(String(s["id"]))
	for r in res:
		assert_eq((r as Node).call("symbol_ids"), sym_ids, "the symbol set taught on the Bellmaker's Floor")
		var plates := (r as Node).find_children("Strike_*", "", true, false)
		assert_eq(plates.size(), sym_ids.size(), "one interactable plate per symbol")
		var labels := (r as Node).find_children("Name", "Label3D", true, false)
		assert_eq(labels.size(), sym_ids.size(), "every plate names its symbol (never colour alone)")
	var pts: Array = a.call("perimeter_points", 16)
	assert_true(pts.size() >= 12, "a walkable perimeter")
	for p in pts:
		var v: Vector3 = p
		assert_true(bool(a.call("is_on_perimeter", v)), "on the safe ring")
		assert_false(_ray(v + Vector3.UP, v + Vector3.DOWN).is_empty(), "floor under %s" % str(v))
		assert_true(_capsule_free(v), "perimeter point %s is clear" % str(v))
	var params: Dictionary = a.call("boss_params")
	for k in ["arena_center", "arena_radius", "perimeter_radius", "anchors", "anchor_nodes", "resonators", "symbols", "arena"]:
		assert_true(params.has(k), "boss param %s" % k)


## The safe perimeter is a real walk all the way round: every 0.4 m along the middle of the ring there is
## floor and a capsule 1.2 m wide (radius 0.6, Krystal's is 0.32) fits - no resonator or anchor pinches it.
func test_perimeter_ring_is_walkable_all_the_way_round() -> void:
	host = await _make()
	var a: Node = _ctl().get("choir")
	var c: Vector3 = a.call("arena_center")
	var r := (float(a.call("perimeter_radius")) + float(a.call("arena_radius"))) * 0.5
	var n := int(ceilf(TAU * r / 0.4))
	var bad: Array = []
	for i in n:
		var ang := TAU * float(i) / float(n)
		var p := Vector3(c.x + cos(ang) * r, c.y, c.z + sin(ang) * r)
		if _ray(p + Vector3.UP, p + Vector3.DOWN).is_empty():
			bad.append("no floor at %.0f deg" % rad_to_deg(ang))
			continue
		var cap := CapsuleShape3D.new()
		cap.radius = 0.6
		cap.height = 1.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.25)
		q.collision_mask = MASK
		if not _space().intersect_shape(q, 1).is_empty():
			bad.append("pinched at %.0f deg" % rad_to_deg(ang))
	assert_eq(bad, [], "the perimeter ring (radius %.1f) is clear all the way round" % r)
	for rn in a.call("resonator_nodes"):
		var rp: Vector3 = (rn as Node3D).global_position
		assert_true(Vector2(rp.x - c.x, rp.z - c.z).length() < float(a.call("perimeter_radius")) - 0.5, "resonator inside the ring, off the perimeter")


func test_fight_threads_never_regrow_and_are_freed() -> void:
	host = await _make()
	var arena: Node = _ctl().get("crossing")
	var t: Node = arena.call("spawn_thread", Vector3(84.0, -18.0, -4.0), Vector3(84.0, -18.0, 4.0), 30.0, -1)
	dummy = _dummy(Vector3(80.0, -18.0, 0.0))
	t.set("player_override", dummy)
	assert_true(bool(t.call("cut")), "a thrown thread can be cut")
	t.call("tick", 2.0)
	assert_eq(String(t.get("state")), "expired", "a cut fight thread fades instead of regrowing")
	t.call("tick", 200.0)
	assert_false(bool(t.call("is_blocking")), "and never creeps back across the deck")
	var burnt: Node = arena.call("spawn_thread", Vector3(90.0, -18.0, -4.0), Vector3(90.0, -18.0, 4.0), 30.0, 2)
	burnt.call("burn")
	var live: Node = arena.call("spawn_thread", Vector3(96.0, -18.0, -4.0), Vector3(96.0, -18.0, 4.0), 30.0, -1)
	assert_true(t.is_queued_for_deletion() and burnt.is_queued_for_deletion(), "finished fight threads are freed")
	assert_false(live.is_queued_for_deletion(), "a live one stays")


func test_crossing_cleared_elsewhere_commits_the_bundle_on_load() -> void:
	GameState.set_flag("ch2_crossing_cleared", true)      # e.g. the boss module set it while the Works wasn't built
	assert_false(GameState.has_reward("rw_ch2_crossing"))
	host = await _make()
	var a: Node = _ctl().get("crossing")
	assert_true(bool(a.call("is_cleared")))
	assert_true(GameState.has_reward("rw_ch2_crossing"), "the content bundle's ledger entry is committed")
	var t0: float = float(GameState.ledger["rw_ch2_crossing"])
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	assert_eq(float(GameState.ledger["rw_ch2_crossing"]), t0, "still exactly once on the next build")
	assert_false(bool(((_ctl().get("crossing") as Node).get("exit_veil") as Node).call("is_blocking")), "the route onward is open")


func test_resonator_sequence_without_timing_or_pitch() -> void:
	host = await _make()
	var r: Node = (_ctl().get("choir") as Node).call("resonator_nodes")[0]
	var ids: Array = r.call("symbol_ids")
	var caps: Array = []
	var cb := func(t: String) -> void: caps.append(t)
	Events.caption.connect(cb)
	r.call("set_sequence", [ids[1], ids[0]])
	assert_eq(String(r.call("strike", ids[0])), "wrong", "wrong plate restarts gently")
	assert_eq(int(r.get("progress")), 0)
	assert_eq(String(r.call("strike", ids[1])), "progress")
	var got_done := [false]
	r.connect("activated", func(_id: String) -> void: got_done[0] = true)
	assert_eq(String(r.call("strike", ids[0])), "done")
	assert_true(bool(r.call("is_active")) and bool(got_done[0]), "activated")
	assert_eq(String(r.call("strike", ids[0])), "idle", "stays active")
	Events.caption.disconnect(cb)
	assert_true(caps.size() >= 3, "every strike is captioned (sound muted playable)")
	Settings.set_value("timing_assist", true)
	assert_eq(r.call("window_seconds"), INF, "timing assist removes any window")
	r.call("reset")
	assert_false(bool(r.call("is_active")))


func test_choir_boss_hook_guard_fallback_and_exit() -> void:
	host = await _make()
	var a: Node = _ctl().get("choir")
	assert_false(bool(a.call("exit_open")), "exit barred before victory")
	var gate_ray := [Vector3(157.0, -31.0, 76.8), Vector3(157.0, -31.0, 79.5)]
	assert_false(_ray(gate_ray[0], gate_ray[1]).is_empty(), "portcullis down")
	dummy = _dummy(Vector3(157.0, -30.0, 48.0))
	_ctl().set("player_override", dummy)
	_ctl().call("check", 0.1)
	assert_false(bool(a.get("active")), "not on the stair")
	dummy.global_position = Vector3(157.0, -32.0, 60.0)
	_ctl().call("check", 0.1)
	assert_true(bool(a.get("active")), "walking into the vault starts the encounter")
	if ChoirArena.boss_available():
		# borrowed_choir is registered now: simulate its script failing after the spawn (node gone, no
		# defeat) so the guarded fallback stays covered instead of silently passing.
		var b: Variant = a.get("boss")
		assert_true(b is Node and is_instance_valid(b), "a registered Choir is spawned")
		assert_false(bool(a.get("fallback")), "no fallback while the Choir is there")
		if b is Node and is_instance_valid(b):
			for r in a.call("resonator_nodes"):
				(r as Node).set("enabled", false)      # e.g. left in Phase A (plates idle) by the vanished boss
			(b as Node).free()
		_ctl().call("check", 0.1)
		assert_true(bool(a.get("active")), "the encounter goes on without its boss")
	assert_true(bool(a.get("fallback")), "boss missing or vanished: guarded fallback")
	assert_null(a.get("boss"), "no boss node kept")
	for r in a.call("resonator_nodes"):
		assert_true(bool((r as Node).get("enabled")), "the fallback's resonators are usable")
	for an in a.call("anchor_nodes"):
		(an as Node).call("raise", null)
	assert_false(bool(a.get("cleared")), "anchors alone are not enough")
	for r in a.call("resonator_nodes"):
		for sid in (r as Node).get("sequence"):
			(r as Node).call("strike", String(sid))
	assert_true(bool(a.get("cleared")), "anchors raised + resonators woken")
	assert_true(bool(GameState.get_flag("ch2_choir_defeated")), "ch2_choir_defeated")
	await wait_physics(3)
	assert_true(bool(a.call("exit_open")), "the exit opens")
	assert_true(_ray(gate_ray[0], gate_ray[1]).is_empty(), "portcullis raised")
	var lift: Node = a.get("exit_lift")
	lift.call("interact", dummy)
	assert_eq(_ctl().get("last_travel"), ["hallowmere_reach", "bellhouse_stair"], "the bell-lift rises to the Reach's Bellhouse")


func test_choir_boss_defeated_event_and_test_hook() -> void:
	host = await _make()
	var a: Node = _ctl().get("choir")
	Events.boss_defeated.emit("count_velour")
	assert_false(bool(GameState.get_flag("ch2_choir_defeated")), "other bosses ignored")
	Events.boss_defeated.emit("borrowed_choir")
	assert_true(bool(GameState.get_flag("ch2_choir_defeated")), "Events.boss_defeated(borrowed_choir) commits the flag")
	assert_true(bool(a.get("cleared")))
	var t := GameState.flags.duplicate()
	assert_true(bool(_ctl().call("debug_clear_choir")), "debug/test hook is idempotent")
	assert_eq(GameState.flags, t, "nothing granted twice")
	assert_false(bool(GameState.get_flag("chapter_two_complete")), "the chapter end belongs to Game.complete_chapter_two()")


func test_choir_victory_makes_the_vault_safe() -> void:
	host = await _make()
	var a: Node = _ctl().get("choir")
	var c: Vector3 = a.call("arena_center")
	var exit_pos: Vector3 = Layout.SPAWNS["vault_exit"]["pos"]
	assert_false(host.is_safe_zone(c), "the vault is not safe before the victory")
	assert_false(host.is_safe_zone(exit_pos))
	Events.boss_defeated.emit("borrowed_choir")
	assert_true(host.is_safe_zone(c), "after the victory the quiet vault is safe")
	assert_true(host.is_safe_zone(c + Vector3(float(a.call("perimeter_radius")) + 0.5, 0.0, 0.0)), "the perimeter too")
	assert_true(host.is_safe_zone(exit_pos), "and the exit alcove")
	assert_false(host.is_safe_zone(Vector3(88.0, -18.0, 0.0)), "nothing else changes")
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	assert_true(host.is_safe_zone(c), "still safe after reloading a won save")


## A preview host with the Works area's register_mood(zone, mood, ambience) API, recording what it is given.
func _make_mood_host() -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends \"res://src/world/works/deep/deep_preview_host.gd\"\nvar mood_zone: String = \"\"\nvar amb_by_zone: Dictionary = {}\nvar mood_by_zone: Dictionary = {}\nfunc register_mood(zone: String, mood: Dictionary, ambience: String = \"\") -> void:\n\tmood_by_zone[zone] = mood\n\tif ambience != \"\":\n\t\tamb_by_zone[zone] = ambience\n"
	s.reload()
	var h: Node3D = s.new()
	h.set("with_environment", false)
	add_child(h)
	await wait_physics(3)
	return h


func test_choir_victory_calms_the_vault_ambience() -> void:
	host = await _make_mood_host()
	var amb: Dictionary = host.get("amb_by_zone")
	assert_eq(String(amb.get("hw_vault", "")), String(Layout.AMBIENCE["hw_vault"]), "the Choir's loop before the victory")
	assert_eq(ChoirArena.vault_ambience(), String(Layout.AMBIENCE["hw_vault"]))
	assert_eq(String(amb.get("hw_throat", "")), String(Layout.AMBIENCE["hw_throat"]), "other zones keep theirs")
	Events.boss_defeated.emit("borrowed_choir")
	amb = host.get("amb_by_zone")
	assert_eq(String(amb.get("hw_vault", "")), ChoirArena.CALM_AMBIENCE, "the victory re-registers a calm vault")
	assert_ne(ChoirArena.CALM_AMBIENCE, "amb_boss", "calm is not the boss loop")
	assert_eq(host.get("mood_by_zone")["hw_vault"], Layout.MOODS["hw_vault"], "the light mood is unchanged")
	assert_eq(String(amb.get("hw_crossing", "")), String(Layout.AMBIENCE["hw_crossing"]), "nothing else changes")
	# a later build of the won save registers the calm loop from the start
	host.queue_free()
	await wait_frames(2)
	host = await _make_mood_host()
	amb = host.get("amb_by_zone")
	assert_eq(String(amb.get("hw_vault", "")), ChoirArena.CALM_AMBIENCE, "still calm on the next build")
	assert_eq(ChoirArena.vault_ambience(), ChoirArena.CALM_AMBIENCE)


## Standing in the vault at the moment of victory: the calm loop plays at once (the area only replays a zone's
## ambience when she enters it).
func test_choir_victory_in_the_vault_plays_the_calm_loop_now() -> void:
	host = await _make_mood_host()
	var a: Node = _ctl().get("choir")
	a.set("save_on_clear", false)
	host.set("mood_zone", "hw_vault")
	Audio.play_ambience(String(Layout.AMBIENCE["hw_vault"]), 0.0)
	var saved_area: Node = Game.area
	Game.area = host
	a.call("clear_encounter")
	var now := Audio.current_ambience()
	Game.area = saved_area
	Audio.stop_ambience(0.0)
	assert_eq(now, ChoirArena.CALM_AMBIENCE, "the vault's ambience crossfades to calm right away")
	assert_true(bool(GameState.get_flag("ch2_choir_defeated")))


func test_high_visibility_markers() -> void:
	Settings.set_value("high_visibility_cues", false)
	host = await _make()
	var an: Node = (_ctl().get("choir") as Node).call("anchor_nodes")[0]
	var hv: Node3D = an.get_node("HvRing")
	assert_false(hv.visible, "off by default")
	Settings.set_value("high_visibility_cues", true)
	await wait_frames(1)
	assert_true(hv.visible, "bold ring when high visibility cues are on")
	var r: Node = (_ctl().get("choir") as Node).call("resonator_nodes")[0]
	assert_true((r.get_node("Hv") as Node3D).visible, "resonators too")
