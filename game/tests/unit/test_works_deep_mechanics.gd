extends "res://tests/test_case.gd"
## Hushed Works rooms 9-14 mechanics: threads (cut / burn / regrow / expiry, lantern rule, arachnophobia
## swap), Scratching Above the Winch (intensity variants, reading hold, never harmful), the Wrong Landing
## (false lift = short recoverable detour, real lift = loop B to the refuge, the lighting tell), the
## Borrowed Porch (no-light lamp vs anchored flame, reveal flag, Intense fragment, harmless retreat),
## Bell Throat (supplies once, return/continue choice, notes, practice reveal) and save/load of it all.

const Host := preload("res://src/world/works/deep/deep_preview_host.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const ThreadScript := preload("res://src/world/works/deep/deep_thread.gd")
const MASK := 1 | 32

var host: Node3D = null
var dummy: Node3D = null
var _saved := {}


func before_each() -> void:
	fresh_state()
	for k in ["arachnophobia", "horror_intensity", "timing_assist", "high_visibility_cues"]:
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
	d.name = "DummyKrystal"
	add_child(d)
	d.global_position = at
	return d


func _ctl() -> Node:
	return host.get("deep")


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return host.get_world_3d().direct_space_state.intersect_ray(q)


# --- Threads ---------------------------------------------------------------------------------------------

func test_threads_cut_regrow_and_never_close_on_her() -> void:
	host = await _make()
	var t: Node = _ctl().call("thread", "hw_thread_winch_exit")
	dummy = _dummy(Vector3(52.0, -18.0, 2.0))
	t.set("player_override", dummy)
	assert_true(bool(t.call("is_blocking")), "whole at first")
	assert_false(_ray(Vector3(60.6, -17.0, 0.0), Vector3(62.6, -17.0, 0.0)).is_empty(), "blocks the door")
	var gi: Dictionary = t.call("get_interaction", dummy)
	assert_true(String(gi["text"]).begins_with("Cut"), "lantern down: cut")
	t.call("interact", dummy)
	assert_eq(String(t.get("state")), "cut")
	await wait_physics(2)
	assert_true(_ray(Vector3(60.6, -17.0, 0.0), Vector3(62.6, -17.0, 0.0)).is_empty(), "the door is open while cut")
	var regrow := ThreadScript.regrow_seconds()
	t.call("tick", regrow - 1.0)
	assert_eq(String(t.get("state")), "cut", "not yet")
	dummy.global_position = Vector3(61.6, -18.0, 0.3)     # standing in the doorway
	t.call("tick", 5.0)
	assert_eq(String(t.get("state")), "cut", "never regrows on top of her")
	dummy.global_position = Vector3(52.0, -18.0, 2.0)
	t.call("tick", 0.2)
	assert_eq(String(t.get("state")), "whole", "regrows once she stepped away")
	await wait_physics(2)
	assert_false(_ray(Vector3(60.6, -17.0, 0.0), Vector3(62.6, -17.0, 0.0)).is_empty(), "blocks again")
	assert_false(bool(GameState.get_flag("hw_thread_winch_exit_burned")), "cutting is temporary")


func test_threads_burn_for_good_with_the_lantern_raised() -> void:
	host = await _make()
	var t: Node = _ctl().call("thread", "hw_thread_winch_exit")
	dummy = _dummy(Vector3(59.0, -18.0, 0.0))
	dummy.set("lantern_on", true)
	var gi: Dictionary = t.call("get_interaction", dummy)
	assert_true(String(gi["text"]).begins_with("Burn"), "lantern raised: burn")
	t.call("interact", dummy)
	assert_eq(String(t.get("state")), "burned")
	assert_true(bool(GameState.get_flag("hw_thread_winch_exit_burned")), "burned state persists")
	t.call("tick", 999.0)
	assert_eq(String(t.get("state")), "burned", "never regrows")
	assert_true((t.call("get_interaction", dummy) as Dictionary).is_empty(), "no prompt left")
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	assert_eq(String((_ctl().call("thread", "hw_thread_winch_exit") as Node).get("state")), "burned", "stays burned on the next load")
	assert_eq(String((_ctl().call("thread", "hw_thread_nook") as Node).get("state")), "whole", "the other veil is untouched")


func test_timing_assist_and_teaching_text() -> void:
	Settings.set_value("timing_assist", false)
	var normal := ThreadScript.regrow_seconds()
	Settings.set_value("timing_assist", true)
	assert_true(ThreadScript.regrow_seconds() > normal * 2.0, "timing assist keeps cut threads open much longer")
	host = await _make()
	var nook: Node = _ctl().call("thread", "hw_thread_nook")
	var txt := String((nook.call("get_interaction", null) as Dictionary)["text"])
	assert_true(txt.contains("grow back") or txt.contains("drifts back"), "the teaching veil spells the rule out: " + txt)
	assert_true(txt.contains("lantern"), "and names the lantern")


func test_arena_threads_expire_and_lines_burn_them() -> void:
	host = await _make()
	var arena: Node = _ctl().get("crossing")
	var t: Node = arena.call("spawn_thread", Vector3(80.0, -18.0, -4.0), Vector3(80.0, -18.0, 4.0), 5.0, 0)
	assert_true(bool(t.call("is_blocking")), "a thrown thread blocks")
	assert_almost(float(t.get("width")), 8.0, 0.01, "spans the thrown line")
	t.call("tick", 5.5)
	assert_eq(String(t.get("state")), "expired", "temporary threads expire")
	assert_false(bool(t.call("is_blocking")))
	var t2: Node = arena.call("spawn_thread", Vector3(90.0, -18.0, -4.0), Vector3(90.0, -18.0, 4.0), 30.0, 1)
	assert_eq((arena.call("threads_on_line", 1) as Array).size(), 1)
	(arena.call("brazier_for_anchor", 1) as Node).call("light")
	assert_eq(String(t2.get("state")), "burned", "the line-brazier burns its line's threads")
	assert_true((arena.call("lit_lines") as Array).has(1))


func test_arachnophobia_swaps_threads_and_the_winch_shape() -> void:
	Settings.set_value("arachnophobia", false)
	host = await _make()
	var t: Node = _ctl().call("thread", "hw_thread_nook")
	assert_true(_has_group_child(t, "hw_thread_web"), "web variant")
	assert_false(_has_group_child(t, "hw_thread_veil"))
	var web_text := String((t.call("get_interaction", null) as Dictionary)["text"])
	Settings.set_value("arachnophobia", true)
	await wait_frames(2)
	assert_true(_has_group_child(t, "hw_thread_veil"), "pale veil variant after the switch")
	assert_false(_has_group_child(t, "hw_thread_web"), "no web left")
	var veil_text := String((t.call("get_interaction", null) as Dictionary)["text"])
	assert_ne(web_text, veil_text, "different name and text")
	assert_false(veil_text.to_lower().contains("thread"), "no 'threads' in the veil text")
	assert_eq(String(t.call("display_name")), "pale veil")
	# the winch moment's passing shape is the shade, never a spider, in this mode
	dummy = _dummy(Vector3(50.0, -18.0, 2.0))
	_ctl().set("player_override", dummy)
	var w: Node = _ctl().get("winch")
	w.call("check", dummy, 0.1, true)
	w.call("check", dummy, 20.0, true)
	var shape: Variant = w.get("shape")
	assert_true(shape is Node3D and is_instance_valid(shape), "a shape crosses")
	if shape is Node3D:
		assert_eq(String((shape as Node).get("variant")), "shade", "non-arachnid variant")


func _has_group_child(n: Node, group: String) -> bool:
	for c in n.get_children():
		if c.is_in_group(group) and not c.is_queued_for_deletion():
			return true
	return false


# --- Scratching Above the Winch ---------------------------------------------------------------------------

func _run_moment(intensity: int) -> Array:
	Settings.set_value("horror_intensity", intensity)
	host = await _make()
	dummy = _dummy(Vector3(46.0, -18.0, 2.0))
	_ctl().set("player_override", dummy)
	var w: Node = _ctl().get("winch")
	w.call("check", dummy, 0.1, true)
	assert_eq(String(w.get("phase")), "idle", "not before the trigger line")
	dummy.global_position = Vector3(50.0, -18.0, 2.0)
	w.call("check", dummy, 0.1, true)
	assert_eq(String(w.get("phase")), "dust", "dust first (anticipation)")
	assert_true(bool(GameState.get_flag("moment_hw_winch")), "flag set first")
	for i in 400:
		w.call("check", dummy, 0.1, true)
		if String(w.get("phase")) == "done":
			break
	return w.get("fired")


func test_winch_moment_gentle_is_one_pass() -> void:
	var fired := await _run_moment(0)
	assert_eq(fired.count("pass"), 1, "Gentle: one pass")
	assert_false(fired.has("approach"), "Gentle: no approach")
	assert_true(fired.has("done"))


func test_winch_moment_intense_waits_longer_and_approaches() -> void:
	var fired := await _run_moment(2)
	assert_eq(fired.count("pass"), 2, "two passes")
	assert_true(fired.has("approach"), "Intense: a clearly marked approach")
	var anticipation_gentle: float = float(Layout.WINCH_TIMING[0]["anticipation"])
	assert_true(float(Layout.WINCH_TIMING[2]["anticipation"]) > anticipation_gentle, "longer anticipation")


func test_winch_moment_waits_while_reading_and_never_repeats() -> void:
	host = await _make()
	dummy = _dummy(Vector3(50.0, -18.0, 2.0))
	_ctl().set("player_override", dummy)
	var w: Node = _ctl().get("winch")
	w.call("note_read")
	w.call("check", dummy, 0.1, true)
	assert_eq(String(w.get("phase")), "idle", "never starts while she reads")
	for i in 70:
		w.call("check", dummy, 0.1, true)
	assert_eq(String(w.get("phase")), "dust", "starts after the reading hold")
	w.call("note_read")
	for i in 50:
		w.call("check", dummy, 0.1, true)
	assert_eq(String(w.get("phase")), "dust", "no pass begins while she reads")
	# once per save: a new build never replays it
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	_ctl().set("player_override", dummy)
	var w2: Node = _ctl().get("winch")
	w2.call("check", dummy, 0.1, true)
	assert_eq(String(w2.get("phase")), "done", "moment_hw_winch keeps it from replaying")


# --- The Wrong Landing -------------------------------------------------------------------------------------

func test_false_lift_is_a_short_recoverable_detour() -> void:
	host = await _make()
	dummy = _dummy(Vector3(133.0, -22.0, -8.0))
	_ctl().set("player_override", dummy)
	var fl: Node = _ctl().call("lift", "hw_lift_false")
	fl.call("interact", dummy)
	await wait_frames(1)
	assert_eq(String(_ctl().get("last_ride")), "hw_wrong_siding", "the false lift jams in the siding")
	assert_true(dummy.global_position.distance_to(host.get_spawn("hw_wrong_siding").origin) < 0.1, "she is in the siding")
	assert_true(bool(GameState.get_flag("hw_false_lift_ridden")))
	assert_eq(Layout.zone_of_room(Layout.room_at(dummy.global_position + Vector3.UP * 0.1)), "hw_wrong_landing", "still on the same level")
	# the walk back: every step has floor and room (the geometry suite probes it with capsules too)
	var back: Array = Layout.SIDE_PATHS[3]
	var length := 0.0
	for i in back.size() - 1:
		length += (back[i] as Vector3).distance_to(back[i + 1])
	assert_true(length < 25.0, "a SHORT detour (%.1f m)" % length)
	for p in back:
		assert_false(_ray((p as Vector3) + Vector3.UP, (p as Vector3) + Vector3.DOWN).is_empty(), "floor at %s" % str(p))
	assert_eq(Layout.room_at((back[back.size() - 1] as Vector3) + Vector3.UP * 0.1), "hw_wrong_landing", "back on the landing")


func test_real_lift_is_loop_b_to_the_refuge() -> void:
	host = await _make()
	dummy = _dummy(Vector3(123.0, -22.0, -8.0))
	_ctl().set("player_override", dummy)
	(_ctl().call("lift", "hw_lift_real") as Node).call("interact", dummy)
	await wait_frames(1)
	assert_eq(String(_ctl().get("last_ride")), "refuge", "returns to the hub")
	assert_true(dummy.global_position.distance_to(host.get_spawn("refuge").origin) < 0.1)
	assert_true(bool(GameState.get_flag("hw_loop_b_lift")))


func test_wrong_landing_lighting_tell() -> void:
	host = await _make()
	var real: Node = _ctl().call("lift", "hw_lift_real")
	var fake: Node = _ctl().call("lift", "hw_lift_false")
	assert_true(bool(real.call("lamp_lights_plate")), "the real lamp lights its landing plate")
	assert_false(bool(fake.call("lamp_lights_plate")), "the false lamp lights nothing")
	assert_true(_count_lights(real) >= 1, "real: a Light3D")
	assert_eq(_count_lights(fake), 0, "false: no Light3D at all")
	assert_true(real.is_in_group("light_source") and not fake.is_in_group("light_source"), "light_source only for the real one")
	var labels_real := real.find_children("*", "Label3D", true, false)
	var labels_fake := fake.find_children("*", "Label3D", true, false)
	assert_true(labels_real.size() == 1 and labels_fake.size() == 1, "both carry a sign")
	if labels_real.size() == 1 and labels_fake.size() == 1:
		assert_true((labels_fake[0] as Label3D).scale.x < 0.0 and (labels_real[0] as Label3D).scale.x > 0.0, "the false sign reads backwards (second cue)")
	Settings.set_value("high_visibility_cues", true)
	await wait_frames(1)
	var hv: Node = real.get_node_or_null("HvRing")
	assert_true(hv != null and (hv as Node3D).visible, "high visibility marks the real plate")
	var hv2: Node = fake.get_node_or_null("HvRing")
	assert_true(hv2 == null or not (hv2 as Node3D).visible, "never the false one")


func test_winch_cage_brings_her_back_down() -> void:
	host = await _make()
	var cage: Node = _ctl().call("lift", "hw_winch_cage")
	assert_not_null(cage, "room 9 has the winch cage")
	dummy = _dummy(Vector3(58.0, -18.0, -5.0))
	_ctl().set("player_override", dummy)
	assert_false(bool(cage.call("usable")), "chained until a lift up has been ridden")
	assert_false(bool((cage.call("get_interaction", dummy) as Dictionary)["enabled"]), "locked text")
	cage.call("interact", dummy)
	await wait_frames(1)
	assert_eq(String(_ctl().get("last_ride")), "", "a chained cage goes nowhere")
	assert_eq(String(_ctl().call("ride_winch_cage", "landing")), "", "not even from code")
	# loop B up: the Wrong Landing's real lift frees it
	dummy.global_position = Vector3(123.0, -22.0, -8.0)
	(_ctl().call("lift", "hw_lift_real") as Node).call("interact", dummy)
	await wait_frames(1)
	assert_eq(String(_ctl().get("last_ride")), "refuge")
	assert_true(bool(cage.call("usable")), "free after the ride up")
	assert_true(bool(cage.call("lamp_lights_plate")), "a real lift: its lamp lights its plate (the Wrong Landing rule)")
	assert_eq((_ctl().call("winch_cage_destinations") as Array).size(), 1, "only the Wrong Landing before the Bell Throat is known")
	cage.call("interact", dummy)
	await wait_frames(1)
	assert_eq(String(_ctl().get("last_ride")), "hw_lift_landing", "down to the Wrong Landing")
	assert_true(dummy.global_position.distance_to(host.get_spawn("hw_lift_landing").origin) < 0.1)
	assert_eq(String(_ctl().call("ride_winch_cage", "throat")), "", "the Bell Throat only once she has been there")
	GameState.set_flag("hw_throat_seen", true)
	assert_eq(String(_ctl().call("ride_winch_cage", "throat")), "throat")
	await wait_frames(1)
	assert_true(dummy.global_position.distance_to(host.get_spawn("bell_throat").origin) < 0.1, "straight back to the Bell Throat")
	# the Bell Throat's return ride frees it too (fresh save)
	host.queue_free()
	await wait_frames(2)
	fresh_state()
	host = await _make()
	_ctl().set("player_override", dummy)
	assert_false(bool(_ctl().call("winch_cage_free")))
	(_ctl().get("throat") as Node).call("choose", "return")
	await wait_frames(1)
	assert_true(bool(_ctl().call("winch_cage_free")), "returning from the Bell Throat frees the cage")
	assert_true(bool((_ctl().call("lift", "hw_winch_cage") as Node).call("usable")))


func _count_lights(n: Node) -> int:
	return n.find_children("*", "Light3D", true, false).size()


# --- The Borrowed Porch ----------------------------------------------------------------------------------

func test_porch_lamp_casts_no_light_and_the_flame_reveals_the_stair() -> void:
	host = await _make()
	var porch: Node = _ctl().get("porch")
	assert_false(bool(porch.call("porch_lamp_casts_light")), "the 'warm' lamp and windows cast no light")
	assert_true(bool(porch.call("flame_casts_light")), "the anchored flame is a real light")
	assert_false((porch.get("porch_lamp") as Node).is_in_group("light_source"))
	var before := GameState.flags.duplicate()
	porch.call("knock")
	porch.call("look_at_lamp")
	assert_eq(GameState.flags, before, "knocking / looking changes nothing (harmless)")
	assert_false(_ray(Vector3(137.5, -21.0, 33.5), Vector3(140.5, -21.0, 33.5)).is_empty(), "the painted hedge hides the stair")
	var flame_it: Node = (porch.get("flame") as Node).get_node("FlameInteract")
	flame_it.call("interact", null)
	assert_true(bool(GameState.get_flag("ch2_false_home_revealed")), "recognising it reveals the true stair")
	assert_false(bool(porch.call("reveal")), "once")
	await wait_physics(2)
	assert_true(_ray(Vector3(137.5, -21.0, 33.5), Vector3(140.5, -21.0, 33.5)).is_empty(), "the stair is open")
	assert_true(GameState.structures.is_empty(), "the real Haven is never touched")
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	assert_true(bool((_ctl().get("porch") as Node).get("is_revealed")), "revealed on reload")


func test_porch_intensity_variants() -> void:
	Settings.set_value("horror_intensity", 0)
	host = await _make()
	dummy = _dummy(Vector3(129.0, -22.0, 20.0))
	_ctl().set("player_override", dummy)
	_ctl().call("check", 0.1)
	var porch: Node = _ctl().get("porch")
	assert_false(bool(GameState.get_flag("moment_hw_porch")), "not yet (far from the facade)")
	dummy.global_position = Vector3(123.0, -22.0, 26.0)
	_ctl().call("check", 0.1)
	assert_true(bool(GameState.get_flag("moment_hw_porch")), "first approach")
	assert_false(bool(porch.get("fragment_played")), "Gentle: explanation, no music fragment")
	# Intense (fresh save): a brief familiar fragment, then silence, released when she leaves
	host.queue_free()
	await wait_frames(2)
	fresh_state()
	Settings.set_value("horror_intensity", 2)
	host = await _make()
	_ctl().set("player_override", dummy)
	var got: Array = []
	var cb := func(ctx: String) -> void: got.append(ctx)
	Events.music_context_changed.connect(cb)
	dummy.global_position = Vector3(129.0, -22.0, 20.0)
	_ctl().call("check", 0.1)
	dummy.global_position = Vector3(123.0, -22.0, 26.0)
	_ctl().call("check", 0.1)
	porch = _ctl().get("porch")
	assert_true(bool(porch.get("fragment_played")), "Intense: the fragment plays")
	porch.call("end_fragment")
	assert_true(got.has("silence"), "then silence")
	dummy.global_position = Vector3(129.0, -22.0, 0.0)
	_ctl().call("check", 0.1)
	assert_true(got.has(""), "silence released on leaving the porch")
	Events.music_context_changed.disconnect(cb)


# --- Bell Throat -------------------------------------------------------------------------------------------

func test_throat_supplies_once() -> void:
	host = await _make()
	var throat: Node = _ctl().get("throat")
	var bundle: Dictionary = throat.call("supplies_bundle")
	var items: Dictionary = bundle["items"]
	assert_false(items.is_empty(), "there are supplies")
	var heals := 0
	for id in items:
		if float(ItemDB.item(String(id)).get("heal", 0.0)) > 0.0:
			heals += int(items[id])
	assert_true(heals >= 2, "guaranteed healing food")
	var first_id: String = String(items.keys()[0])
	var before := GameState.count_item(first_id)
	assert_true(bool(throat.call("take_supplies")), "first time")
	assert_eq(GameState.count_item(first_id), before + int(items[first_id]), "items given")
	assert_false(bool(throat.call("take_supplies")), "only once")
	assert_eq(GameState.count_item(first_id), before + int(items[first_id]), "not twice")
	assert_true(GameState.has_reward(Layout.THROAT_SUPPLIES_ID), "reward ledger")
	var crate_it: Node = (throat.get("crate") as Node).get_node("CrateInteract")
	assert_false(bool((crate_it.call("get_interaction", null) as Dictionary)["enabled"]), "the crate is empty now")


func test_throat_return_and_continue_choice() -> void:
	host = await _make()
	var throat: Node = _ctl().get("throat")
	dummy = _dummy(Vector3(157.0, -28.0, 38.0))
	_ctl().set("player_override", dummy)
	assert_eq(String(throat.call("choose", "continue")), "continue")
	assert_true(dummy.global_position.distance_to(Vector3(157.0, -28.0, 38.0)) < 0.01, "continue: she stays")
	assert_eq(String(throat.call("choose", "return")), "return")
	await wait_frames(1)
	assert_eq(String(_ctl().get("last_ride")), "refuge", "return: the lift to the refuge")
	assert_true(dummy.global_position.distance_to(host.get_spawn("refuge").origin) < 0.1)
	# the one-time automatic offer near the vault stair (no UI in tests -> continue)
	fresh_state()
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	_ctl().set("player_override", dummy)
	dummy.global_position = Vector3(157.0, -28.0, 42.0)
	_ctl().call("check", 0.1)
	assert_true(bool(GameState.get_flag("hw_throat_choice_seen")), "offered once near the stair")
	assert_eq(String((_ctl().get("throat") as Node).get("last_choice")), "continue")


func test_throat_notes_and_before_the_choir() -> void:
	host = await _make()
	var throat: Node = _ctl().get("throat")
	var said: Array = []
	var cb := func(_s: String, text: String, _d: float) -> void: said.append(text)
	Events.say.connect(cb)
	var l: Dictionary = throat.call("read", Layout.LORE_BEFORE_CHOIR)
	var l2: Dictionary = throat.call("read", Layout.LORE_THROAT_NOTE)
	Events.say.disconnect(cb)
	assert_true(String(l.get("text", "")) != "" and String(l2.get("text", "")) != "", "both notes have text")
	assert_eq(said.size(), 2, "shown as dialog")
	var lore := load("res://src/core/lore_db.gd")
	if not bool(lore.call("has_lore", Layout.LORE_BEFORE_CHOIR)):
		assert_eq(String(l["text"]), "It has learned a welcome. It has not learned a home.", "MP §17 verbatim (fallback)")
	else:
		assert_true(GameState.lore.has(Layout.LORE_BEFORE_CHOIR), "discovered through LoreDB")


func test_throat_order_board_repeats_the_taught_order() -> void:
	host = await _make()
	var throat: Node = _ctl().get("throat")
	var board: Node = throat.get_node("OrderBoard")
	var syms: Array = Layout.bell_symbols()
	var shown := board.find_children("Symbol_*", "", false, false)
	assert_eq(shown.size(), syms.size(), "one large symbol per taught bell")
	for i in syms.size():
		var s: Dictionary = syms[i]
		var node: Node3D = board.get_node("Symbol_" + String(s["id"]))
		assert_not_null(node.get_node_or_null("Name"), "%s is named, never colour alone" % String(s["id"]))
		if i > 0:
			var prev: Node3D = board.get_node("Symbol_" + String((syms[i - 1] as Dictionary)["id"]))
			assert_true(node.position.x > prev.position.x, "left to right in the taught order")
	var said: Array = []
	var cb := func(_s: String, text: String, _d: float) -> void: said.append(text)
	Events.say.connect(cb)
	var t := String(throat.call("read_order"))
	Events.say.disconnect(cb)
	assert_eq(said.size(), 1, "shown as dialog (sound muted playable)")
	var at := -1
	for s in syms:
		var p := t.find(String((s as Dictionary)["name"]))
		assert_true(p > at, "%s named in order" % String((s as Dictionary)["name"]))
		at = p
	var res: Node = (_ctl().get("choir") as Node).call("resonator_nodes")[0]
	var ids: Array = []
	for s in syms:
		ids.append(String((s as Dictionary)["id"]))
	assert_eq(res.get("sequence"), ids, "the vault's resonators answer to exactly this order by default")


func test_practice_reveal_teaches_the_exposure_rule() -> void:
	host = await _make()
	var pr: Node = (_ctl().get("throat") as Node).get("practice")
	var g: int = int(pr.get("genuine"))
	assert_eq(String(pr.call("pick", g)), "not_revealed", "raise the lantern first")
	assert_false(bool(pr.call("reveal")), "no lantern owned yet: the anchor needs one")
	GameState.give_item("lantern", 1)
	assert_true(GameState.has_item("lantern"), "the ordinary lantern")
	assert_true(bool(pr.call("reveal")), "raising the ordinary lantern at the anchor")
	var lights: Array = pr.get("plate_lights")
	for i in lights.size():
		assert_eq((lights[i] as OmniLight3D).visible, i == g, "only the genuine form lights the ground (%d)" % i)
	assert_eq(String(pr.call("pick", (g + 1) % 3)), "wrong", "a false form: gentle explanation")
	assert_false(bool(GameState.get_flag("hw_choir_practice_done")))
	assert_eq(String(pr.call("pick", g)), "correct")
	assert_true(bool(GameState.get_flag("hw_choir_practice_done")))
	var anchor: Node = pr.get("anchor")
	anchor.call("tick", 60.0)
	assert_false(bool(anchor.call("is_raised")), "the anchor lowers again")
	assert_false((lights[g] as OmniLight3D).visible, "and the reveal ends")


# --- Save / load ---------------------------------------------------------------------------------------------

func test_state_survives_save_and_load() -> void:
	host = await _make()
	var ctl := _ctl()
	(ctl.call("thread", "hw_thread_winch_exit") as Node).call("burn")
	(ctl.get("porch") as Node).call("reveal")
	(ctl.get("throat") as Node).call("take_supplies")
	(ctl.get("crossing") as Node).call("clear_encounter")
	(ctl.get("choir") as Node).call("clear_encounter")
	var cp: Node = ctl.call("checkpoint", "hw_bell_throat")
	cp.set("save_enabled", false)
	cp.call("interact", null)
	ctl.call("switch_winch_lamps")
	assert_true(SaveSystem.save_game(), "saved")
	GameState.reset()
	GameState.active = false
	assert_true(SaveSystem.load_game(), "loaded")
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	ctl = _ctl()
	assert_eq(String((ctl.call("thread", "hw_thread_winch_exit") as Node).get("state")), "gone", "the trail is gone after the crossing")
	assert_true(bool((ctl.get("porch") as Node).get("is_revealed")), "porch revealed")
	assert_true(bool((ctl.get("throat") as Node).call("supplies_taken")), "supplies taken")
	assert_false(bool((ctl.get("throat") as Node).call("take_supplies")), "still only once after loading")
	assert_true(bool((ctl.get("crossing") as Node).call("is_cleared")), "crossing cleared")
	assert_true(bool((ctl.get("choir") as Node).call("exit_open")), "vault exit open")
	assert_true(bool((ctl.call("checkpoint", "hw_bell_throat") as Node).get("lit")), "checkpoint lit")
	assert_true(bool(ctl.call("winch_lamps_on")), "work lamps remembered")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "bell_throat", "respawn at the Bell Throat")
