extends "res://tests/test_case.gd"
## Scene-level tests for the horror director node, the event runner and the silhouette:
## the director must run in a minimal scene with other modules missing, executors must fail
## gracefully, spawn anchors are validated against real physics, cancels restore everything.

const Director := preload("res://src/horror/director.gd")
const Runner := preload("res://src/horror/event_runner.gd")
const Core := preload("res://src/horror/director_core.gd")
const Silhouette := preload("res://src/horror/silhouette.gd")
const HorrorData := preload("res://data/horror_events.gd")
const AreaBase := preload("res://src/world/area_base.gd")

const FAKE_FACTORY_SRC := """extends RefCounted
static var calls: int = 0
static func spawn(enemy_id: String, parent: Node, xform: Transform3D, params: Dictionary = {}) -> Node:
	calls += 1
	var n := CharacterBody3D.new()
	n.name = "FakeEnemy"
	n.set_meta("enemy_id", enemy_id)
	n.set_meta("params", params)
	n.add_to_group("enemy")
	parent.add_child(n)
	n.global_transform = xform
	return n
"""

const FAKE_COMPANION_SRC := """extends Node3D
var companion_id: String = "lumi"
var noticed: Array = []
var reactions: Array = []
func notice_threat(pos: Vector3) -> void:
	noticed.append(pos)
func react(r: String) -> void:
	reactions.append(r)
"""

var root: Node3D
var area: Node3D
var player: Node3D
var cam: Camera3D
var anchors: Dictionary = {}
var _saved_settings: Dictionary = {}


func before_each() -> void:
	_saved_settings = {"arachnophobia": Settings.get_value("arachnophobia"),
		"horror_intensity": Settings.get_value("horror_intensity"), "reduce_flashing": Settings.get_value("reduce_flashing")}
	root = Node3D.new()
	root.name = "HorrorTestRoot"
	add_child(root)
	area = AreaBase.new()
	area.name = "TestArea"
	area.add_zone("mine", Vector3.ZERO, 60.0, false)
	area.add_zone("landing", Vector3(30, 0, 30), 4.0, true)
	root.add_child(area)
	_box(Vector3(0, -0.5, 0), Vector3(90, 1, 90))           # floor
	_box(Vector3(-1, 1.5, -6), Vector3(4, 3, 0.4))           # wall in front (x -3..1)
	_box(Vector3(6, 1.5, 12), Vector3(1.5, 3, 1.5))           # pillar behind
	player = Node3D.new()
	player.name = "FakePlayer"
	player.add_to_group("player")
	area.add_child(player)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.position = Vector3(0, 1.6, 0)
	player.add_child(cam)
	cam.make_current()
	anchors = {}
	_anchor("door_far", "doorway", Vector3(8, 0, -18))       # visible, 19.7 m
	_anchor("door_hidden", "doorway", Vector3(0, 0, -15))    # behind the wall
	_anchor("spawn_ok", "spawn", Vector3(0, 0, 15))          # behind the camera, 15 m
	_anchor("spawn_close", "spawn", Vector3(0, 0, 5))
	_anchor("ceiling", "ceiling", Vector3(0, 3.5, 2))
	_anchor("sound_behind", "sound", Vector3(5, 1, 10))
	await wait_physics(3)


func after_each() -> void:
	for k in _saved_settings:
		Settings.set_value(k, _saved_settings[k])
	if is_instance_valid(root):
		root.queue_free()
	await wait_frames(2)


# --- helpers ------------------------------------------------------------------------------------------

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	area.add_child(body)
	body.position = pos


func _anchor(anchor_name: String, kind: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = anchor_name
	m.set_meta("zone", "mine")
	m.set_meta("kind", kind)
	m.add_to_group("director_anchor")
	area.add_child(m)
	m.position = pos
	anchors[anchor_name] = m
	return m


func _director(seed_value: int = 3) -> Node:
	var d: Node = Director.new()
	d.setup({"area": area, "seed": seed_value})
	area.add_child(d)
	return d


func _runner() -> Node:
	var r: Node = Runner.new()
	area.add_child(r)
	r.setup({"seed": 5})
	return r


func _env(extra: Dictionary = {}) -> Dictionary:
	var e := {"player": player, "area": area, "companion_node": null, "intensity": 1,
		"arachnophobia": false, "reduce_flashing": false}
	e.merge(extra, true)
	return e


func _decision(event_id: String, anchor_name: String = "", count: int = 1) -> Dictionary:
	var ev: Dictionary = HorrorData.EVENTS[event_id].duplicate(true)
	var a := {}
	if anchor_name != "":
		var m: Marker3D = anchors[anchor_name]
		a = {"name": anchor_name, "kind": String(m.get_meta("kind")), "zone": "mine", "pos": m.global_position,
			"dist": m.global_position.distance_to(player.global_position), "visible": false}
	return {"event_id": event_id, "event": ev, "kind": String(ev["kind"]), "anchor": a, "count": count, "major": bool(ev["major"])}


func _fake_factory() -> GDScript:
	var gs := GDScript.new()
	gs.source_code = FAKE_FACTORY_SRC
	gs.reload()
	return gs


func _fake_companion() -> Node3D:
	var gs := GDScript.new()
	gs.source_code = FAKE_COMPANION_SRC
	gs.reload()
	var c: Node3D = gs.new()
	area.add_child(c)
	c.position = Vector3(1, 0, 1)
	return c


func _count_children_with_script(script: Script) -> int:
	var n := 0
	for c in area.get_children():
		if c.get_script() == script and not c.is_queued_for_deletion():
			n += 1
	return n


# --- director smoke --------------------------------------------------------------------------------

func test_director_without_setup_or_player_does_not_crash() -> void:
	var bare := Node.new()
	root.add_child(bare)
	var d: Node = Director.new()
	bare.add_child(d)
	player.remove_from_group("player")
	for i in 20:
		d.tick_now(1.0)
	assert_eq(d.get_state(), "calm")
	assert_eq(String(d.last_decision["reason"]), "paused", "no player -> director holds still")
	assert_true(d.debug_log.size() > 0, "log has the ready line")
	player.add_to_group("player")


func test_director_ticks_in_minimal_scene_with_modules_missing() -> void:
	var d := _director(3)
	var states := {}
	var executed := 0
	for i in 400:
		var dec: Dictionary = d.tick_now(1.0)
		states[d.get_state()] = true
		if String(dec["event_id"]) != "":
			executed += 1
	assert_true(states.has("unease") and states.has("anticipation"), "tension builds in the scene: %s" % str(states.keys()))
	assert_true(executed > 3, "the director acted (%d events)" % executed)
	var runner: Node = d.runner
	assert_true(runner.last_results.size() > 0, "runner reported results")
	for r in runner.last_results:
		assert_true(r.has("ok") and r.has("note") and String(r["note"]) != "", "every result explains itself")
	var ctx: Dictionary = d.last_context
	assert_eq(String(ctx["zone"]), "mine", "zone from the area (Game.area is not this test area)")
	var names := []
	for a in ctx["anchors"]:
		names.append(String(a["name"]))
	assert_true(names.has("door_far") and names.has("spawn_ok"), "anchors collected: %s" % str(names))
	print("  director smoke: %s" % d.core.summary())


func test_context_reads_the_world() -> void:
	var d := _director(3)
	var ctx: Dictionary = d.build_context(1.0)
	assert_false(bool(ctx["paused"]))
	assert_false(bool(ctx["in_safe_zone"]))
	var by_name := {}
	for a in ctx["anchors"]:
		by_name[String(a["name"])] = a
	assert_true(bool(by_name["door_far"]["visible"]), "open doorway in view is visible")
	assert_false(bool(by_name["door_hidden"]["visible"]), "doorway behind the wall is not visible")
	assert_false(bool(by_name["spawn_ok"]["visible"]), "anchor behind the camera is not visible")
	assert_almost(float(by_name["spawn_ok"]["dist"]), 15.0, 0.01)
	assert_eq(String(by_name["ceiling"]["kind"]), "ceiling")
	# Lingering accumulates while the player stands still, resets when they move.
	for i in 5:
		ctx = d.build_context(1.0)
	assert_true(float(ctx["lingering_seconds"]) >= 5.0, "standing still = lingering")
	player.position = Vector3(5, 0, 0)
	ctx = d.build_context(1.0)
	assert_almost(float(ctx["lingering_seconds"]), 0.0, 0.001, "moving resets lingering")
	player.position = Vector3(30, 0, 30)
	ctx = d.build_context(1.0)
	assert_true(bool(ctx["in_safe_zone"]), "safe zone from the area")


func test_visibility_test() -> void:
	var d := _director(3)
	assert_true(d.is_point_visible(Vector3(0, 1.5, -4)), "point in front is visible")
	assert_false(d.is_point_visible(Vector3(0, 1.5, 8)), "point behind is not")
	assert_false(d.is_point_visible(Vector3(0, 1.0, -12)), "point behind the wall is not")
	assert_false(d.is_point_visible(Vector3(40, 1.0, -2)), "point far outside the frame is not")


func test_threats_and_retreat_detection() -> void:
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar hunting := true\nfunc is_threatening() -> bool:\n\treturn hunting\n"
	gs.reload()
	var e: Node3D = gs.new()
	e.add_to_group("enemy")
	area.add_child(e)
	e.position = Vector3(0, 0, -10)
	var d := _director(3)
	var ctx: Dictionary = d.build_context(1.0)
	assert_eq(int(ctx["threats_nearby"]), 1, "threatening enemy within 20 m")
	player.position = Vector3(0, 0, 3)
	ctx = d.build_context(1.0)
	assert_true(bool(ctx["retreating"]), "moving away from the threat = retreating")
	e.set("hunting", false)
	ctx = d.build_context(1.0)
	assert_eq(int(ctx["threats_nearby"]), 0, "idle enemies are not threats")
	assert_eq(int(ctx["enemies_nearby"]), 1, "...but they are the room's own encounter (no ambush pile-on)")
	e.set_meta("director_spawned", true)
	ctx = d.build_context(1.0)
	assert_eq(int(ctx["enemies_nearby"]), 0, "the director's own spawns are tracked by the threat budget instead")
	e.remove_meta("director_spawned")
	e.position = Vector3(0, 0, -40)
	e.set("hunting", true)
	ctx = d.build_context(1.0)
	assert_eq(int(ctx["threats_nearby"]), 0, "threats beyond 20 m are ignored")


func test_signals_cancel_and_recover() -> void:
	var d := _director(3)
	var states: Array = []
	var cb := func(s: String) -> void: states.append(s)
	Events.horror_state_changed.connect(cb)
	var runner: Node = d.runner
	runner._schedule(30.0, func() -> void: pass)
	Events.paused_changed.emit(true)
	assert_eq(runner.pending_count(), 0, "pause cancels pending work")
	runner._schedule(30.0, func() -> void: pass)
	Events.safe_zone_changed.emit(true)
	assert_eq(runner.pending_count(), 0, "safe zone cancels pending work")
	Events.player_died.emit()
	assert_eq(d.get_state(), "recovery", "death -> recovery")
	assert_true(states.has("recovery"), "horror_state_changed emitted: %s" % str(states))
	var d2 := _director(4)
	assert_eq(d2.get_state(), "calm")
	Events.horror_event.emit("pebbles_fall", {})
	assert_eq(d2.get_state(), "calm", "our own events are not authored moments")
	Events.horror_event.emit("authored:the_imitation", {})
	assert_eq(d2.get_state(), "recovery", "authored moment -> recovery")
	assert_true("
".join(PackedStringArray(d2.debug_log)).contains("authored moment 'the_imitation'"), "logged")
	d.suppress(10.0)
	assert_true(float(d.core.suppressed_left) >= 10.0)
	Events.horror_state_changed.disconnect(cb)


func test_once_events_persist_through_game_state() -> void:
	fresh_state()
	var d := _director(3)
	assert_false(d.core.fired_once.has("wrong_mochi"), "fresh playthrough: not used yet")
	d._remember_once("wrong_mochi")
	assert_true(bool(GameState.get_flag("horror_once_wrong_mochi")), "stored as a GameState flag (saved with the game)")
	var d2 := _director(4)
	assert_true(d2.core.fired_once.has("wrong_mochi"), "a later visit to the Below remembers it")
	var ctx := {"zone": "ruins", "anchors": [{"name": "s", "kind": "sound", "zone": "ruins", "dist": 10.0, "visible": false}]}
	d2.core.zone = "ruins"
	d2.core.state = "unease"
	var why: String = d2.core._ineligible_reason("wrong_mochi", d2.core.events["wrong_mochi"], ctx, 1)
	assert_true(why.contains("once"), "rejected as once-only: " + why)
	fresh_state()


func test_area_exit_and_cutscene_stop_the_director() -> void:
	var d := _director(3)
	var runner: Node = d.runner
	runner._schedule(30.0, func() -> void: pass)
	Events.cutscene_changed.emit(true)
	assert_eq(runner.pending_count(), 0, "cutscene cancels pending work")
	Events.cutscene_changed.emit(false)
	Events.area_exiting.emit("below")
	assert_false(bool(d.enabled), "director stops when the area unloads")
	var t_before: int = int(d.core.stats["ticks"])
	await wait_seconds(1.2)
	assert_eq(int(d.core.stats["ticks"]), t_before, "no more ticks after area exit")


func test_executed_events_are_broadcast() -> void:
	var d := _director(3)
	var got: Array = []
	var cb := func(id: String, data: Dictionary) -> void: got.append([id, data])
	Events.horror_event.connect(cb)
	var dec: Dictionary = d.debug_force("silence")
	Events.horror_event.disconnect(cb)
	assert_eq(String(dec["event_id"]), "silence")
	assert_eq(got.size(), 1, "one horror_event emitted")
	if got.size() == 1:
		assert_eq(String(got[0][0]), "silence")
		assert_eq(String(got[0][1]["kind"]), "silence")
		assert_eq(String(got[0][1]["zone"]), "mine")


# --- runner --------------------------------------------------------------------------------------------

func test_runner_every_kind_fails_gracefully_when_things_are_missing() -> void:
	var r := _runner()
	# No player, no area, no companion, no anchors at all.
	var core: Core = Core.new()
	core.setup({"seed": 2})
	for id in HorrorData.EVENTS:
		var ev: Dictionary = HorrorData.EVENTS[id]
		var dec := {"event_id": id, "event": ev, "kind": String(ev["kind"]), "anchor": {}, "count": 1}
		var res: Dictionary = r.execute(dec, {})
		assert_true(res.has("ok") and res.has("note"), "%s returns a result" % id)
		assert_true(String(res["note"]) != "", "%s explains itself" % id)
		if String(ev["kind"]) in ["glimpse", "scratch", "notice"]:
			assert_false(bool(res["ok"]), "%s cannot run without its anchor/companion: %s" % [id, res["note"]])
	var bad: Dictionary = r.execute({"event_id": "x", "event": {"kind": "teleport"}, "kind": "teleport"}, {})
	assert_false(bool(bad["ok"]))
	assert_true(String(bad["note"]).contains("unknown"))
	assert_false(bool(r.execute({}, {})["ok"]), "empty decision")


func test_runner_glimpse_shows_a_silhouette_far_away() -> void:
	var r := _runner()
	var res: Dictionary = r.execute(_decision("far_glimpse", "door_far"), _env())
	assert_true(bool(res["ok"]), String(res["note"]))
	assert_eq(_count_children_with_script(Silhouette), 1, "a silhouette appeared")
	var sil: Node3D = null
	for c in area.get_children():
		if c.get_script() == Silhouette:
			sil = c
	assert_eq(String(sil.variant), "spider", "spider when arachnophobia is off")
	assert_true(sil.global_position.distance_to(player.global_position) >= 12.0, "never closer than 12 m")
	await wait_seconds(2.6)
	assert_eq(_count_children_with_script(Silhouette), 0, "it slips away and frees itself")
	# Too close doorways are refused.
	var near := _anchor("door_near", "doorway", Vector3(2, 0, -6.5))
	var res2: Dictionary = r.execute(_decision("far_glimpse", "door_near"), _env())
	assert_false(bool(res2["ok"]), "doorway at %.1fm refused" % near.global_position.distance_to(player.global_position))


func test_runner_arachnophobia_swaps_visuals_sounds_and_captions() -> void:
	var r := _runner()
	var res: Dictionary = r.execute(_decision("far_glimpse", "door_far"), _env({"arachnophobia": true}))
	assert_true(bool(res["ok"]))
	for c in area.get_children():
		if c.get_script() == Silhouette:
			assert_eq(String(c.variant), "shade", "Hollow Shade instead of a spider")
	var web: Dictionary = HorrorData.EVENTS["web_rustle"]
	assert_eq(r._sound_name(web, true), "dir_root_creak")
	assert_eq(r._caption_text(web, true), "[roots creak]")
	assert_eq(r._sound_name(web, false), "dir_web_rustle")
	var stalker: Dictionary = HorrorData.EVENTS["stalker_pass"]
	assert_eq(r._sound_name(stalker, true), "shade_drift")
	assert_eq(r._caption_text(stalker, true), "[something drifts overhead]")
	var pebbles: Dictionary = HorrorData.EVENTS["pebbles_fall"]
	assert_eq(r._sound_name(pebbles, true), "dir_pebbles", "non-spider events unchanged")
	# Stalker fallback crossing also respects the setting.
	var cross: Dictionary = r.execute(_decision("stalker_pass", "ceiling"), _env({"arachnophobia": true}))
	assert_true(bool(cross["ok"]), String(cross["note"]))
	var shades := 0
	for c in area.get_children():
		if c.get_script() == Silhouette and String(c.mode) == "cross":
			assert_eq(String(c.variant), "shade")
			assert_true(bool(c.on_ceiling))
			shades += 1
	assert_eq(shades, 1, "one silhouette crosses the ceiling")


func test_runner_notice_needs_the_companion() -> void:
	var r := _runner()
	var none: Dictionary = r.execute(_decision("lumi_notices", "door_far"), _env())
	assert_false(bool(none["ok"]), "no companion -> skipped")
	var lumi := _fake_companion()
	var res: Dictionary = r.execute(_decision("lumi_notices", "door_far"), _env({"companion_node": lumi}))
	assert_true(bool(res["ok"]), String(res["note"]))
	var noticed: Array = lumi.get("noticed")
	assert_eq(noticed.size(), 1, "Lumi was told where to look")
	if noticed.size() == 1:
		assert_true((noticed[0] as Vector3).distance_to(anchors["door_far"].global_position) < 0.01)
	lumi.set("companion_id", "pebble")
	var wrong: Dictionary = r.execute(_decision("lumi_notices", "door_far"), _env({"companion_node": lumi}))
	assert_false(bool(wrong["ok"]), "only Lumi notices")


func test_runner_scratch_drops_dust_from_the_ceiling() -> void:
	var r := _runner()
	var res: Dictionary = r.execute(_decision("scratching_above", "ceiling"), _env())
	assert_true(bool(res["ok"]), String(res["note"]))
	var dust := 0
	for c in area.get_children():
		if c is CPUParticles3D:
			dust += 1
			assert_true((c as CPUParticles3D).global_position.y > 3.0, "dust starts at the ceiling")
	assert_eq(dust, 2, "dust and a few pebbles")
	r.cancel_all("test")
	await wait_frames(2)
	var left := 0
	for c in area.get_children():
		if c is CPUParticles3D and not c.is_queued_for_deletion():
			left += 1
	assert_eq(left, 0, "cancel removes the effects")


func test_runner_flicker_dims_and_restores_lights() -> void:
	var r := _runner()
	var near := OmniLight3D.new()
	near.light_energy = 2.0
	area.add_child(near)
	near.position = Vector3(2, 2.5, 0)
	var far := OmniLight3D.new()
	far.light_energy = 2.0
	area.add_child(far)
	far.position = Vector3(0, 2.5, 35)
	var res: Dictionary = r.execute(_decision("lantern_flicker"), _env())
	assert_true(bool(res["ok"]), String(res["note"]))
	await wait_seconds(0.3)
	assert_true(near.light_energy < 2.0, "nearby light dips (%.2f)" % near.light_energy)
	assert_almost(far.light_energy, 2.0, 0.0001, "far light untouched")
	r.cancel_all("test")
	assert_almost(near.light_energy, 2.0, 0.0001, "cancel restores the light immediately")
	# Uncancelled flicker restores itself; reduce_flashing uses one gentle dip.
	r.execute(_decision("lantern_flicker"), _env({"reduce_flashing": true}))
	await wait_seconds(0.45)
	var mid := near.light_energy
	assert_true(mid < 2.0 and mid >= 2.0 * 0.5, "gentle dip stays soft (%.2f)" % mid)
	await wait_seconds(2.4)
	assert_almost(near.light_energy, 2.0, 0.0001, "light restored after the flicker")
	# flicker_light nodes take priority.
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar flickers := 0\nfunc flicker(seconds: float) -> void:\n\tflickers += 1\n"
	gs.reload()
	var fl: Node3D = gs.new()
	fl.add_to_group("flicker_light")
	area.add_child(fl)
	fl.position = Vector3(1, 2, 1)
	var res2: Dictionary = r.execute(_decision("lantern_flicker"), _env())
	assert_true(String(res2["note"]).begins_with("flicker_light"), String(res2["note"]))
	assert_eq(int(fl.get("flickers")), 1)


func test_runner_silence_ducks_ambience() -> void:
	var r := _runner()
	var res: Dictionary = r.execute(_decision("silence"), _env())
	assert_true(bool(res["ok"]), String(res["note"]))


func test_runner_spawn_validates_anchor_and_telegraphs() -> void:
	var r := _runner()
	var ff := _fake_factory()
	assert_true(ff.has_method("spawn"), "Script.has_method sees static funcs (the factory check relies on it)")
	r.enemy_factory_override = ff
	var d := _director(3)          # provides the real visibility test
	d.enabled = false
	r.visibility_fn = d.is_point_visible
	var res: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_ok", 2), _env())
	assert_true(bool(res["ok"]), String(res["note"]))
	assert_eq(r.active_threat_count(), 2, "pending ambush counts against the budget")
	assert_eq(r.pending_count(), 1, "spawn waits for the telegraph")
	await wait_seconds(1.2)
	var threats: Array = r.tracked_threats()
	assert_eq(threats.size(), 2, "two gloomlings arrive")
	for t in threats:
		assert_true((t as Node).is_in_group("director_threat"), "tagged as director threat")
		assert_true(bool((t as Node).get_meta("director_spawned", false)))
		assert_true(bool(((t as Node).get_meta("params") as Dictionary).get("alert", false)), "ambushers come alert")
		var dist := (t as Node3D).global_position.distance_to(player.global_position)
		assert_true(dist >= 9.0 and dist <= 24.0, "spawned in the distance band (%.1f)" % dist)
		assert_true((t as Node3D).global_position.y < 0.2, "on the ground")
	assert_eq(r.active_threat_count(), 2)
	# Budget: 3 max. One more fits, then nothing.
	var one: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_ok", 2), _env())
	assert_true(bool(one["ok"]))
	await wait_seconds(1.2)
	assert_eq(r.active_threat_count(), 3, "clamped to the threat budget")
	var full: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_ok", 1), _env())
	assert_false(bool(full["ok"]))
	assert_true(String(full["note"]).contains("budget"), String(full["note"]))
	# Calm + far away: director threats quietly despawn.
	var removed: int = r.despawn_far(Vector3(0, 0, -60), 30.0)
	assert_eq(removed, 3, "far, idle director threats removed")
	await wait_frames(2)
	assert_eq(r.active_threat_count(), 0)


func test_runner_spawn_rejects_bad_anchors() -> void:
	var r := _runner()
	r.enemy_factory_override = _fake_factory()
	var d := _director(3)
	d.enabled = false
	r.visibility_fn = d.is_point_visible
	var close: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_close"), _env())
	assert_false(bool(close["ok"]))
	assert_true(String(close["note"]).contains("too close"), String(close["note"]))
	_anchor("spawn_void", "spawn", Vector3(0, -10, 16))
	var void_res: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_void"), _env())
	assert_true(String(void_res["note"]).contains("no ground"), String(void_res["note"]))
	# Enclosed in a big block: no clear spot anywhere within the nudge radius.
	_box(Vector3(-8, 1.5, 14), Vector3(7, 3, 7))
	await wait_physics(2)
	_anchor("spawn_enclosed", "spawn", Vector3(-8, 0, 14))
	var enclosed: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_enclosed"), _env())
	assert_false(bool(enclosed["ok"]))
	assert_true(String(enclosed["note"]).contains("inside geometry") and String(enclosed["note"]).contains("no clear spot"), String(enclosed["note"]))
	_anchor("spawn_seen", "spawn", Vector3(6, 0, -14))
	var seen: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_seen"), _env())
	assert_true(String(seen["note"]).contains("visible"), String(seen["note"]))
	_anchor("spawn_far", "spawn", Vector3(0, 0, 35))
	var far: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_far"), _env())
	assert_true(String(far["note"]).contains("too far"), String(far["note"]))
	assert_eq(r.active_threat_count(), 0, "nothing spawned from bad anchors")


func test_runner_spawn_nudges_off_a_blocked_anchor() -> void:
	# Real dungeon case: a spawn anchor placed inside a rubble pile. The runner searches the anchor's
	# surroundings (same room, toward the player first) for a clear spot that passes every rule.
	var d := _director(3)
	d.enabled = false
	var r: Node = d.runner                                   # real visibility test + log wiring
	r.enemy_factory_override = _fake_factory()
	_anchor("spawn_pillar", "spawn", Vector3(6, 0, 12))       # inside the 1.5 m pillar
	var res: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_pillar"), _env())
	assert_true(bool(res["ok"]), String(res["note"]))
	var p: Vector3 = res["pos"]
	var off := Vector2(p.x - 6.0, p.z - 12.0).length()
	assert_true(off > 0.75 + 0.4 and off <= 2.8, "moved just clear of the pillar (%.2f m)" % off)
	assert_true(p.y < 0.2, "on the floor")
	var dist := p.distance_to(player.global_position)
	assert_true(dist >= 9.0, "still outside the minimum distance (%.1f)" % dist)
	assert_true(p.distance_to(player.global_position) < Vector3(6, 0, 12).distance_to(player.global_position), "prefers the open side facing the player")
	assert_true("\n".join(PackedStringArray(d.debug_log)).contains("using a clear spot"), "nudge logged")
	await wait_seconds(1.2)
	assert_eq(r.tracked_threats().size(), 1, "the ambusher arrives at the clear spot")
	# A prop standing on the anchor (the ground ray lands on top of it) also counts as blocked.
	_box(Vector3(-6, 0.5, 16), Vector3(1.2, 1.0, 1.2))
	await wait_physics(2)
	_anchor("spawn_crate", "spawn", Vector3(-6, 0, 16))
	var chk: Dictionary = r._validate_spawn_point(Vector3(-6, 0, 16), player)
	assert_false(bool(chk["ok"]))
	assert_true(String(chk["reason"]).begins_with("inside geometry"), String(chk["reason"]))
	var crate: Dictionary = r._find_spawn_point({"name": "spawn_crate", "pos": Vector3(-6, 0, 16)}, player, _env(), true)
	assert_true(bool(crate["ok"]), String(crate.get("reason", "")))
	assert_true((crate["pos"] as Vector3).y < 0.2, "never on top of the prop")


func test_runner_nudge_stays_in_the_anchor_room() -> void:
	var r := _runner()
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nfunc get_room_at(pos: Vector3) -> String:\n\treturn \"left\" if pos.x < 0.0 else \"right\"\n"
	gs.reload()
	var rooms: Node3D = gs.new()
	area.add_child(rooms)
	assert_true(r._same_space(rooms, Vector3(-1, 0, 0), Vector3(-2.5, 0, 0)), "same room")
	assert_false(r._same_space(rooms, Vector3(-1, 0, 0), Vector3(0.5, 0, 0)), "never through the wall into the next room")
	assert_true(r._same_space(area, Vector3(0, 0, 10), Vector3(2, 0, 10)), "zones when the area has no rooms")
	assert_false(r._same_space(area, Vector3(30, 0, 25), Vector3(30, 0, 30)), "mine vs the safe landing zone")
	assert_true(r._same_space(null, Vector3.ZERO, Vector3.ONE), "no area: anything goes")


func test_director_probe_reports_every_spawn_anchor() -> void:
	var d := _director(3)
	d.enabled = false
	_anchor("spawn_pillar", "spawn", Vector3(6, 0, 12))
	_box(Vector3(-8, 1.5, 14), Vector3(7, 3, 7))
	await wait_physics(2)
	_anchor("spawn_enclosed", "spawn", Vector3(-8, 0, 14))
	var rows: Array = d.debug_probe_anchors()
	var by := {}
	for row in rows:
		by[String(row["name"])] = row
	assert_eq(by.size(), 4, "every spawn anchor probed: %s" % str(by.keys()))
	assert_true(bool(by["spawn_ok"]["ok"]) and float(by["spawn_ok"]["nudged"]) == 0.0, "clear anchor ok")
	assert_true(bool(by["spawn_close"]["ok"]), "player distance is not part of the probe")
	assert_true(bool(by["spawn_pillar"]["ok"]) and float(by["spawn_pillar"]["nudged"]) > 0.0, "blocked anchor usable via the nudge")
	assert_false(bool(by["spawn_enclosed"]["ok"]), "enclosed anchor reported unusable")
	assert_true("\n".join(PackedStringArray(d.debug_log)).contains("probe spawn_enclosed: UNUSABLE"), "logged")


func test_runner_cancel_calls_off_a_telegraphed_ambush() -> void:
	var r := _runner()
	var ff := _fake_factory()
	r.enemy_factory_override = ff
	var res: Dictionary = r.execute(_decision("gloomling_ambush", "spawn_ok", 1), _env())
	assert_true(bool(res["ok"]))
	r.cancel_all("paused")
	await wait_seconds(1.2)
	assert_eq(r.tracked_threats().size(), 0, "cancelled before the ambush arrived")
	assert_eq(r.active_threat_count(), 0)


func test_runner_stalker_pass_prefers_the_real_stalker() -> void:
	var r := _runner()
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar passes := 0\nfunc pass_overhead() -> void:\n\tpasses += 1\n"
	gs.reload()
	var st: Node3D = gs.new()
	st.add_to_group("stalker")
	area.add_child(st)
	var res: Dictionary = r.execute(_decision("stalker_pass", "ceiling"), _env())
	assert_true(bool(res["ok"]))
	assert_eq(int(st.get("passes")), 1, "the stalker's pass_overhead() hook is used")
	assert_eq(_count_children_with_script(Silhouette), 0, "no fallback silhouette needed")


func test_runner_stalker_pass_needs_a_nearby_route_and_a_free_stalker() -> void:
	var r := _runner()
	var captions: Array = []
	var cb := func(t: String) -> void: captions.append(t)
	Events.caption.connect(cb)
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar route: Array = []\nvar busy := false\nvar passes := 0\nfunc pass_overhead() -> bool:\n\tif busy:\n\t\treturn false\n\tpasses += 1\n\treturn true\n"
	gs.reload()
	var st: Node3D = gs.new()
	st.add_to_group("stalker")
	area.add_child(st)
	# Its whole ceiling route is far away (another passage): a pass there would be out of earshot,
	# so the silhouette crosses the nearby ceiling anchor instead.
	st.position = Vector3(0, 3, -120)
	st.set("route", [Vector3(0, 3, -120), Vector3(4, 3, -110)])
	var far: Dictionary = r.execute(_decision("stalker_pass", "ceiling"), _env())
	assert_true(bool(far["ok"]), String(far["note"]))
	assert_eq(int(st.get("passes")), 0, "far stalker not used")
	assert_true(String(far["note"]).contains("silhouette"), String(far["note"]))
	# Route passes overhead nearby but the stalker is busy (mid-ambush): nothing is faked.
	r.cancel_all("test")
	await wait_seconds(0.4)
	st.set("route", [Vector3(0, 3.5, -4), Vector3(0, 3.5, 6)])
	st.set("busy", true)
	captions.clear()
	var busy: Dictionary = r.execute(_decision("stalker_pass", "ceiling"), _env())
	assert_false(bool(busy["ok"]), "busy stalker -> skipped")
	assert_true(String(busy["note"]).contains("busy"), String(busy["note"]))
	assert_eq(captions.size(), 0, "no caption for a pass that did not happen")
	assert_eq(_count_children_with_script(Silhouette), 0, "no stand-in silhouette on top of a busy stalker")
	st.set("busy", false)
	var ok: Dictionary = r.execute(_decision("stalker_pass", "ceiling"), _env())
	assert_true(bool(ok["ok"]))
	assert_eq(int(st.get("passes")), 1, "near, free stalker passes")
	Events.caption.disconnect(cb)


func test_stalker_pass_never_plays_out_of_sight_and_earshot() -> void:
	# A major "overhead" cue (sting + caption + shake) must be perceivable: in view or within 12 m.
	var d := _director(3)
	d.enabled = false
	var r: Node = d.runner                                    # real camera visibility test
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar route: Array = []\nvar passes := 0\nfunc pass_overhead() -> bool:\n\tpasses += 1\n\treturn true\n"
	gs.reload()
	var st: Node3D = gs.new()
	st.add_to_group("stalker")
	area.add_child(st)
	st.position = Vector3(0, 3.5, 20)
	st.set("route", [Vector3(0, 3.5, 20), Vector3(4, 3.5, 24)])    # ~20 m behind the camera
	_anchor("ceiling_behind", "ceiling", Vector3(0, 3.5, 25))       # 25 m behind: unseen, unheard
	var res: Dictionary = r.execute(_decision("stalker_pass", "ceiling_behind"), _env())
	assert_false(bool(res["ok"]), "nothing to see or hear -> skipped")
	assert_true(String(res["note"]).contains("out of sight"), String(res["note"]))
	assert_eq(int(st.get("passes")), 0, "hidden route: the real stalker is not asked to pass unseen")
	assert_eq(_count_children_with_script(Silhouette), 0)
	# Its route in view ahead (beyond hearing range): the real stalker is used.
	st.set("route", [Vector3(8, 3.0, -18), Vector3(10, 3.0, -22)])   # past the wall's edge, like door_far
	var seen: Dictionary = r.execute(_decision("stalker_pass", "ceiling_behind"), _env())
	assert_true(bool(seen["ok"]), String(seen["note"]))
	assert_eq(int(st.get("passes")), 1, "visible route -> real pass")


func test_glimpse_figure_stands_on_the_floor() -> void:
	var r := _runner()
	_anchor("door_raised", "doorway", Vector3(-8, 0.2, -18))
	await wait_physics(1)
	var res: Dictionary = r.execute(_decision("far_glimpse", "door_raised"), _env())
	assert_true(bool(res["ok"]), String(res["note"]))
	for c in area.get_children():
		if c.get_script() == Silhouette:
			assert_almost((c as Node3D).global_position.y, 0.0, 0.02, "feet on the floor, not floating at the anchor height")
	await wait_seconds(2.6)
	r.execute(_decision("silence"), _env())
	assert_eq(r._fx.size(), 0, "finished effects are not kept around")


func test_open_panel_holds_the_director() -> void:
	var d := _director(3)
	d.enabled = false
	var prev_area: Variant = Game.area
	Game.area = area
	Game.push_ui("horror_test_panel")
	var ctx: Dictionary = d.build_context(1.0)
	Game.pop_ui("horror_test_panel")
	var ctx2: Dictionary = d.build_context(1.0)
	Game.area = prev_area
	assert_true(bool(ctx["paused"]), "a gameplay panel (e.g. the companion menu) is open: no scares")
	assert_false(bool(ctx2["paused"]), "closed again: the director resumes")


func test_failed_execution_rolls_the_core_back() -> void:
	var d := _director(3)
	d.enabled = false
	var core: Core = d.core
	# No light anywhere near: the flicker cannot happen, so it must not cost the global cooldown.
	var dec: Dictionary = d.debug_force("lantern_flicker")
	assert_eq(String(dec["event_id"]), "lantern_flicker")
	assert_eq(int(core.stats["failed"]), 1, "failure reported to the core")
	assert_true(float(core.last_event_time) < -1.0e8, "global cooldown not started by a cue that never played")
	assert_true(core.last_fired.has("lantern_flicker"), "its own cooldown stays (no retry loop)")
	# A late failure (the ambush found no clear spot when its telegraph ended) arrives via the signal.
	var ctx := {"zone": "mine", "anchors": [{"name": "s", "kind": "spawn", "zone": "mine", "pos": Vector3(0, 0, 15), "dist": 15.0, "visible": false}]}
	var amb: Dictionary = core.force("gloomling_ambush", ctx)
	assert_eq(String(amb["event_id"]), "gloomling_ambush")
	assert_true(float(core.last_major_time) > -1.0e8)
	d.runner.event_failed.emit("gloomling_ambush", "test")
	assert_true(float(core.last_major_time) < -1.0e8, "major cooldown rolled back")
	assert_eq(int(core.stats["failed"]), 2)


# --- silhouette ----------------------------------------------------------------------------------------

func test_silhouette_faces_target_and_cancels() -> void:
	for variant in ["spider", "shade"]:
		var s: Node3D = Silhouette.new()
		s.setup({"variant": variant, "mode": "static", "target": player})
		area.add_child(s)
		s.global_position = Vector3(10, 0, 0)
		await wait_frames(2)
		var fwd := s.global_basis.z
		var to := (player.global_position - s.global_position).normalized()
		assert_true(fwd.dot(to) > 0.99, "%s faces the player" % variant)
		assert_true(s.find_children("*", "MeshInstance3D", true, false).size() > 8, "%s is built from several parts" % variant)
		s.cancel()
		await wait_seconds(0.35)
		assert_false(is_instance_valid(s) and s.is_inside_tree() and not s.is_queued_for_deletion(), "%s cancelled" % variant)


func test_silhouette_cross_moves_and_frees() -> void:
	# Offset + rotated parent: targets are global positions (regression: local/global mix-up).
	var holder := Node3D.new()
	area.add_child(holder)
	holder.position = Vector3(50, 0, 20)
	holder.rotation_degrees = Vector3(0, 30, 0)
	var s: Node3D = Silhouette.new()
	s.setup({"variant": "spider", "mode": "cross", "to": Vector3(55, 3.5, 20), "duration": 0.6, "ceiling": true})
	holder.add_child(s)
	s.global_position = Vector3(45, 3.5, 20)
	await wait_seconds(0.35)
	assert_true(is_instance_valid(s), "still crossing")
	if is_instance_valid(s):
		var gp := s.global_position
		assert_true(gp.x > 45.5 and gp.x < 55.0, "moving between the global endpoints (x=%.2f)" % gp.x)
		assert_almost(gp.z, 20.0, 0.01, "stays on the crossing line")
		assert_almost(gp.y, 3.5, 0.01, "stays at the ceiling")
		assert_true(s.global_basis.z.dot(Vector3.RIGHT) > 0.99, "head leads the way")
	await wait_seconds(0.6)
	assert_false(is_instance_valid(s) and not s.is_queued_for_deletion(), "freed after crossing")


func test_silhouette_cancel_before_a_crossing_starts() -> void:
	# Regression: cancel() in the same frame as the (deferred) crossing start used to be undone - the
	# start killed the fade-out and the figure crossed anyway (e.g. pause pressed right as it fired).
	var s: Node3D = Silhouette.new()
	s.setup({"variant": "spider", "mode": "cross", "to": Vector3(5, 3.5, 0), "duration": 2.0, "ceiling": true})
	area.add_child(s)
	s.global_position = Vector3(-5, 3.5, 0)
	s.cancel()
	await wait_seconds(0.45)
	assert_false(is_instance_valid(s) and not s.is_queued_for_deletion(), "cancelled crossing never starts")


func test_silhouette_glimpse_slips_away_in_world_space() -> void:
	var holder := Node3D.new()
	area.add_child(holder)
	holder.position = Vector3(-40, 0, 10)
	holder.rotation_degrees = Vector3(0, 90, 0)
	var s: Node3D = Silhouette.new()
	s.setup({"variant": "shade", "mode": "glimpse", "duration": 0.2, "target": player, "slip_dir": Vector3(0, 0, 1)})
	holder.add_child(s)
	s.global_position = Vector3(-40, 0, -10)
	await wait_seconds(0.4)
	assert_true(is_instance_valid(s))
	if is_instance_valid(s):
		assert_true(float(s.get("_alpha")) > 0.9, "fully visible after fading in")
		var to := (player.global_position - s.global_position).normalized()
		assert_true(s.global_basis.z.dot(to) > 0.99, "faces the player through a rotated parent")
	await wait_seconds(0.4)
	if is_instance_valid(s) and not s.is_queued_for_deletion():
		assert_true(s.global_position.z > -10.0, "slips along the given world direction (z=%.2f)" % s.global_position.z)
		assert_almost(s.global_position.x, -40.0, 0.01)
	await wait_seconds(0.6)
	assert_false(is_instance_valid(s) and not s.is_queued_for_deletion(), "freed after slipping away")
