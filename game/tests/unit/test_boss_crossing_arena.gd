extends "res://tests/test_case.gd"
## Weaver's Crossing rematch on the REAL arena (src/world/works/deep/crossing_arena.gd inside the deep preview
## host: the railed service bridge, the pit, the ceiling anchors, the line-braziers, the service gate): the
## arena spawns crossing_matron through EnemyFactory with its boss_params(); her threads go through the
## arena's spawn_thread (one lane blocked, the other open; cut = gone for good here, burn with the lantern or
## the line-brazier); no pounce through the deck from the pit; knockback along the deck only; death and walking
## back to the gate reset arena + boss together (same boss, no second spawn); the victory commits through the
## arena's listener exactly once (rw_ch2_crossing -> ch2_crossing_cleared, way on open, gate shut; Chapter One
## flags untouched); the capped release spawns real Brood Skitters (Pale Sprouts); arachnophobia on the
## bridge; the rail from the layout reaches her setup; the service gate's bars / sound / line wait for her retreat
## (the collider, flag, reward are immediate); nothing starts while Krystal is down. Headless; the arena never
## saves here (no real player).

const Host := preload("res://src/world/works/deep/deep_preview_host.gd")
const CrossingArena := preload("res://src/world/works/deep/crossing_arena.gd")
const Boss := preload("res://src/enemies/crossing_matron.gd")
const Rules := preload("res://src/enemies/crossing/crossing_rules.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")

const DT := 0.05
const ID := "crossing_matron"
const MASK := 1 | 32

var host: Node3D = null
var dummy: CharacterBody3D = null
var _defeats: Array = []
var _caps: Array = []
var _saved := {}


class Krystal extends CharacterBody3D:
	var health: Node
	var lantern_on := false
	var knocks: Array = []

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 5000.0
		add_child(health)
		collision_layer = 2
		collision_mask = 0
		add_to_group("player")

	func knockback(dir: Vector3, force: float) -> void:
		knocks.append([dir, force])


func before_each() -> void:
	fresh_state()
	GameState.give_item("lantern", 1)
	_defeats.clear()
	_caps.clear()
	for k in ["arachnophobia", "timing_assist", "high_visibility_cues"]:
		_saved[k] = Settings.get_value(k)
		Settings.set_value(k, false)
	Events.boss_defeated.connect(_on_def)
	Events.caption.connect(_on_cap)


func after_each() -> void:
	Events.boss_defeated.disconnect(_on_def)
	Events.caption.disconnect(_on_cap)
	if host != null and is_instance_valid(host):
		host.queue_free()
	host = null
	if dummy != null and is_instance_valid(dummy):
		dummy.queue_free()
	dummy = null
	for k in _saved:
		Settings.set_value(k, _saved[k])
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _on_def(id: String) -> void:
	_defeats.append(id)


func _on_cap(t: String) -> void:
	_caps.append(t)


func _make() -> void:
	host = Host.new()
	host.set("with_environment", false)
	add_child(host)
	await wait_physics(3)
	dummy = Krystal.new()
	add_child(dummy)
	dummy.global_position = Vector3(66.0, -18.0, 0.0)
	_ctl().set("player_override", dummy)
	_arena().set("save_on_clear", false)


func _ctl() -> Node:
	return host.get("deep")


func _arena() -> Node:
	return _ctl().get("crossing")


## Krystal steps onto the bridge: the arena starts the encounter and spawns the boss.
func _engage(at: Vector3 = Vector3(76.0, -18.0, 2.0)) -> Node:
	dummy.global_position = at
	_ctl().call("check", 0.1)
	var b: Variant = _arena().get("boss")
	assert_true(b is Node and is_instance_valid(b), "the arena spawned her")
	if not (b is Node):
		return null
	(b as Node).set_process(false)
	(b as Node).set("fast_defeat", true)
	return b


func _until(b: Node, cond: Callable, max_s: float = 30.0) -> float:
	var t := 0.0
	while t < max_s:
		if bool(cond.call()):
			return t
		b.call("tick", DT)
		t += DT
	return INF if not bool(cond.call()) else t


func _to_state(b: Node, s: String, max_s: float = 30.0) -> bool:
	return _until(b, func() -> bool: return String(b.get("state")) == s, max_s) < INF


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return host.get_world_3d().direct_space_state.intersect_ray(q)


# --- Tests ---------------------------------------------------------------------------------------------------

func test_the_arena_spawns_her_through_the_factory_with_its_params() -> void:
	await _make()
	assert_true(CrossingArena.boss_available(), "crossing_matron is registered and compiles")
	assert_true(Factory.can_spawn(ID))
	var b := _engage()
	var a := _arena()
	assert_true(b.get_script() == Boss, "the Crossing Matron, not the Chapter One boss")
	assert_false(bool(a.get("fallback")), "no fallback: the real encounter")
	assert_eq(b.get("arena"), a, "she knows her arena")
	assert_true(bool(b.get("fight_started")), "setup alert: the fight starts at once")
	assert_eq(b.get("bridge"), a.call("bridge_rect"))
	assert_almost(float(b.get("deck_y")), -18.0, 0.001)
	assert_eq((b.get("anchors") as Array).size(), 5)
	assert_eq((b.get("line_anchors") as Array).size(), 3, "three line anchors over the three braziers")
	assert_eq((b.get("braziers") as Array).size(), 3)
	assert_true((b.get("landing_points") as Array).size() >= 12, "the arena's validated landing grid")
	assert_almost(float((a.call("boss_params") as Dictionary)["rail"]), float(Layout.CROSSING["rail"]), 0.001, "boss_params() hands over the rail")
	assert_almost(float(b.get("rail")), float(Layout.CROSSING["rail"]), 0.001, "she uses the layout's rail, not a recomputed one")
	assert_true(b.is_in_group("enemy"))
	assert_eq(String(b.get("state")), "intro")
	# a second step on the bridge never spawns a second boss
	_ctl().call("check", 0.1)
	assert_eq(a.get("boss"), b)


func test_threads_block_one_lane_on_the_real_bridge_and_cut_or_burn() -> void:
	await _make()
	var b := _engage(Vector3(76.0, -18.0, 2.5))
	var a := _arena()
	assert_true(_to_state(b, "cast"))
	assert_true(_to_state(b, "recover", 3.0))
	var line := int(b.get("held_line"))
	var threads: Array = a.call("threads_on_line", line)
	assert_eq(threads.size(), 2, "two threads, spawned through the arena on her line")
	await wait_physics(2)
	var bx: float = (a.call("brazier_for_anchor", line) as Node3D).global_position.x
	var lane_z := -2.5 if int(b.get("side")) < 0 else 2.5
	assert_false(_ray(Vector3(bx - 4.5, -17.5, lane_z), Vector3(bx - 1.0, -17.5, lane_z)).is_empty(), "her lane is blocked")
	assert_true(_ray(Vector3(bx - 4.5, -17.5, -lane_z), Vector3(bx + 4.5, -17.5, -lane_z)).is_empty(), "the other lane stays open")
	# cut one: it does not grow back (a thrown thread, not a doorway veil)
	var t0: Node = threads[0]
	dummy.lantern_on = false
	t0.call("interact", dummy)
	assert_eq(String(t0.get("state")), "cut", "cut with the lantern down")
	b.call("tick", Rules.THREAD_CUT_LINGER + 0.1)
	assert_eq(String(t0.get("state")), "gone", "the stubs fade")
	t0.call("tick", 120.0)
	assert_eq(String(t0.get("state")), "gone", "never regrows")
	# burn the other with the lantern raised
	var t1: Node = threads[1]
	dummy.lantern_on = true
	t1.call("interact", dummy)
	assert_eq(String(t1.get("state")), "burned", "burned with the lantern raised")
	assert_eq(int(b.call("live_threads")), 0)
	# a new cast, then her line-brazier burns them (and exposes her)
	dummy.lantern_on = false
	dummy.global_position = Vector3(76.0, -18.0, 2.5)
	assert_true(_to_state(b, "cast", 20.0))
	assert_true(_to_state(b, "recover", 3.0))
	var fresh: Array = a.call("threads_on_line", line)
	assert_true(fresh.size() >= 1)
	(a.call("brazier_for_anchor", line) as Node).call("light")
	for t in fresh:
		assert_eq(String((t as Node).get("state")), "burned", "the line-brazier burns its line's threads")
	assert_eq(int(b.get("exposures")), 1, "and exposes her")


func test_no_pounce_from_the_pit_and_knockback_along_the_deck() -> void:
	await _make()
	var b := _engage()
	assert_true(_to_state(b, "cling", 10.0))
	dummy.global_position = Vector3(88.0, -26.0, 0.0)          # the dry pit under the bridge
	assert_false(bool(b.call("_begin_pounce", false)), "never through the deck")
	dummy.global_position = Vector3(106.0, -18.0, 8.0)         # the far ledge
	assert_false(bool(b.call("_begin_pounce", false)), "only onto the bridge")
	dummy.global_position = Vector3(82.0, -18.0, 1.5)
	assert_true(bool(b.call("_begin_pounce", false)), "a pounce at her on the deck")
	var land: Vector3 = b.call("current_landing")
	assert_false(_ray(land + Vector3.UP, land + Vector3.DOWN).is_empty(), "the landing has the deck under it")
	assert_true(_to_state(b, "rebound", 3.0), "it lands on her")
	assert_eq(dummy.knocks.size(), 1)
	var dir: Vector3 = dummy.knocks[0][0]
	assert_eq(dir.z, 0.0, "along the bridge only")
	var p := dummy.global_position
	var q := p + dir * Rules.PUSH_SAFE_DIST
	assert_false(_ray(q + Vector3.UP * 0.5, q + Vector3.DOWN * 1.0).is_empty(), "the push ends on solid deck")
	assert_true(absf(q.z) < float(Layout.CROSSING["rail"]), "the push stays between the rails")


func test_death_and_walking_back_to_the_gate_reset_arena_and_boss_together() -> void:
	await _make()
	var b := _engage()
	var a := _arena()
	assert_true(_to_state(b, "cast"))
	assert_true(_to_state(b, "recover", 3.0))
	assert_true(int(b.call("live_threads")) > 0)
	Events.player_died.emit()
	assert_false(bool(a.get("active")), "the arena stands down")
	assert_eq(String(b.get("state")), "dormant", "she stands down too")
	await wait_frames(1)
	assert_eq(int(b.call("live_threads")), 0, "no threads left behind")
	# walking back onto the bridge restarts the SAME boss cleanly
	dummy.global_position = Vector3(76.0, -18.0, 2.0)
	_ctl().call("check", 0.1)
	assert_true(bool(a.get("active")))
	assert_eq(a.get("boss"), b, "no second spawn")
	assert_eq(String(b.get("state")), "intro")
	# back to the checkpoint gate: the arena stops, she resets on her next tick
	dummy.global_position = Vector3(64.0, -18.0, 0.0)
	_ctl().call("check", 0.1)
	assert_false(bool(a.get("active")))
	b.call("tick", DT)
	assert_eq(String(b.get("state")), "dormant")
	assert_false(bool(b.get("fight_started")))


func test_victory_commits_once_through_the_arena_listener() -> void:
	GameState.set_flag("weaver_defeated", false)
	await _make()
	var b := _engage()
	var a := _arena()
	assert_true(_to_state(b, "cling", 10.0))
	(a.call("brazier_for_anchor", int(b.get("held_line"))) as Node).call("light")
	assert_true(_to_state(b, "exposed", 30.0), "the light caught her anchor; her next pounce exposes her (QA CH2-007)")
	b.get("health").call("set_hp", 5.0)
	b.get("health").call("apply_damage", 20.0, dummy, Vector3.ZERO)
	assert_eq(_defeats, [ID], "Events.boss_defeated(crossing_matron) once")
	assert_true(bool(a.get("cleared")), "the arena committed the crossing")
	assert_true(bool(GameState.get_flag("ch2_crossing_cleared")), "flag through the reward bundle")
	assert_true(GameState.has_reward("rw_ch2_crossing"))
	var t0: float = float(GameState.ledger["rw_ch2_crossing"])
	assert_false(bool((a.get("exit_veil") as Node).call("is_blocking")), "the way on opens")
	assert_true(bool(a.call("route_gate_shut")), "her deeper route closes behind the old service gate")
	assert_false(bool(GameState.get_flag("weaver_defeated")), "Chapter One untouched")
	assert_false(GameState.has_item("heartseed"))
	assert_true(bool(b.call("is_defeated")))
	# nothing commits twice: another event, another check, the flag echo
	Events.boss_defeated.emit(ID)
	_ctl().call("check", 0.1)
	GameState.set_flag("ch2_crossing_cleared", true)
	assert_eq(float(GameState.ledger["rw_ch2_crossing"]), t0, "reward exactly once")
	assert_false(bool(a.get("active")), "never restarts")
	assert_eq(int(b.get("stats")["defeat_events"]), 1)
	# a later visit (fresh boss node) never brings her back
	var again: Node = Factory.create(ID, a.call("boss_params"))
	add_child(again)
	assert_true(bool(again.call("is_gone")), "a cleared crossing keeps her away")
	assert_false(again.is_in_group("enemy"))
	again.queue_free()


func test_debug_clear_while_she_lives_withdraws_her_quietly() -> void:
	await _make()
	var b := _engage()
	assert_true(bool(_ctl().call("debug_clear_crossing")), "debug/test hook (debug build)")
	assert_true(bool(b.call("is_gone")), "she leaves with the cleared crossing")
	assert_eq(_defeats.size(), 0, "no boss_defeated of her own")
	assert_true(GameState.has_reward("rw_ch2_crossing"), "the arena's bundle, once")


func test_the_release_spawns_real_brood_skitters_that_scatter_on_exposure() -> void:
	await _make()
	var b := _engage(Vector3(76.0, -18.0, 2.0))
	b.set("exposures", 2)
	b.set("phase", 3)
	b.set("side", Rules.side_for(2))
	assert_true(_to_state(b, "cling", 10.0))
	b.set("_step", 1)
	b.set("_state_len", 0.0)
	b.call("tick", DT)
	assert_eq(String(b.get("state")), "release")
	var rel: Node = b.call("release_node")
	var sacs: Array = rel.get("sacs")
	assert_eq(sacs.size(), 2, "Standard: two sacs")
	rel.call("tick", float(Rules.SAC_WARN[1]) + 0.2, dummy, true)
	var minions: Array = rel.get("minions")
	assert_eq(minions.size(), 2, "two minions")
	for m in minions:
		assert_true(String((m as Node).get("enemy_id")) == "brood_skitter", "real Brood Skitters")
		assert_true((m as Node).get_meta("matron_minion", false), "marked as hers")
		assert_false(bool((m as Node).get("drops_enabled")), "no drops")
	assert_false(bool(b.call("_begin_pounce", true)), "no pounce while they live")
	# her line-brazier flares: exposure - the brood scatters (no kills, no drops)
	(_arena().call("brazier_for_anchor", int(b.get("held_line"))) as Node).call("light")
	assert_eq(int(b.call("minions_alive")), 0, "they scatter on the exposure")


func test_arachnophobia_on_the_bridge() -> void:
	Settings.set_value("arachnophobia", true)
	var hints: Array = []
	var hcb := func(id: String, text: String) -> void:
		if id.begins_with("boss_crossing"):
			hints.append(text)
	Events.hint.connect(hcb)
	await _make()
	var b := _engage(Vector3(76.0, -18.0, 2.5))
	var a := _arena()
	assert_true(bool(b.call("uses_shade")), "the Hollow Mother")
	assert_eq(int((b.call("anchor_marks") as Node).call("seal_count")), 5, "she floats between stone seals")
	assert_true(_caps.has("[a hollow wail rolls over the service bridge]"), "alt intro caption")
	assert_true(_to_state(b, "cast"))
	assert_true(_to_state(b, "recover", 3.0))
	for t in a.call("threads_on_line", int(b.get("held_line"))):
		assert_true((t as Node).find_children("Veil", "", false, false).size() == 1, "a pale veil, not silk")
		assert_true(((t as Node).get_node("Veil") as Node).is_in_group("hw_thread_veil"))
	assert_true(_caps.has("[pale roots lash across the bridge]"))
	for c in _caps:
		var s := String(c).to_lower()
		assert_false(s.contains("silk") or s.contains("web") or s.contains("spider") or s.contains("egg"), "caption '%s'" % s)
	assert_eq(ItemDB.enemy_display_name(ID), "The Hollow Mother")
	# a pounce and a glance: their hints too
	dummy.global_position = Vector3(82.0, -18.0, 1.5)
	assert_true(_to_state(b, "pounce_tele", 20.0))
	b.call("on_hit_blocked", dummy, Vector3.RIGHT)
	Events.hint.disconnect(hcb)
	assert_true(hints.size() >= 3, "intro, roots, ring and glance hints were shown (%d)" % hints.size())
	for h in hints:
		var t := String(h).to_lower()
		for bad in ["silk", "web", "thread", "spider", "egg", "brood", "rattle", "matron"]:
			assert_false(t.contains(bad), "hint '%s' avoids '%s'" % [t, bad])


func test_a_fall_on_the_bridge_never_restarts_her_on_the_death_screen() -> void:
	await _make()
	var b := _engage()
	var a := _arena()
	assert_true(_to_state(b, "cling", 10.0))
	var enc: Array = []
	var ecb := func(id: String, on: bool) -> void:
		if id == ID:
			enc.append(on)
	Events.boss_encounter_changed.connect(ecb)
	var horror: Array = []
	var hcb := func(id: String, _d: Dictionary) -> void:
		if id == "authored:hw_crossing":
			horror.append(id)
	Events.horror_event.connect(hcb)
	# Krystal falls on the bridge: both stand down...
	dummy.health.hp = 0.0
	dummy.health.dead = true
	Events.player_died.emit()
	assert_eq(String(b.get("state")), "dormant")
	# ...and while she lies there the controller keeps checking - neither the arena nor the boss comes back on
	for i in 5:
		_ctl().call("check", 0.1)
	assert_false(bool(a.get("active")), "the arena stays down while she lies on the bridge")
	assert_eq(horror.size(), 0, "no authored horror event on the death screen")
	for i in 10:
		b.call("tick", 0.1)
	assert_false(bool(b.get("fight_started")), "no encounter, bar, captions or music on the death screen")
	# she wakes at the checkpoint gate: nothing starts from there, the arena stands down on its next check
	dummy.health.reset()
	dummy.global_position = Vector3(64.2, -18.0, 0.9)
	b.call("tick", 0.5)
	assert_false(bool(b.get("fight_started")), "never from the gate")
	_ctl().call("check", 0.1)
	assert_false(bool(a.get("active")))
	# back onto the bridge: the same boss starts cleanly
	dummy.global_position = Vector3(76.0, -18.0, 2.0)
	_ctl().call("check", 0.1)
	assert_true(bool(b.get("fight_started")))
	assert_eq(a.get("boss"), b, "no second spawn")
	Events.boss_encounter_changed.disconnect(ecb)
	Events.horror_event.disconnect(hcb)
	assert_eq(enc, [false, true], "one clean stand-down, one clean restart - no flicker")
	assert_eq(horror.size(), 1, "the authored moment again only for the real restart")


## The real player: nothing starts while Game.mode is not "playing" (death screen, respawn); a test stand-in is
## never gated by Game.mode, only by its health.
func test_the_arena_waits_while_the_real_player_is_not_playing() -> void:
	await _make()
	var a := _arena()
	dummy.global_position = Vector3(76.0, -18.0, 2.0)
	var saved_player: Node3D = Game.player
	var saved_mode := Game.mode
	Game.player = dummy
	Game.mode = "dead"
	var down := bool(a.call("player_down", dummy))
	a.call("check", dummy)
	var started := bool(a.get("active"))
	Game.mode = "playing"
	var up := not bool(a.call("player_down", dummy))
	Game.player = saved_player
	Game.mode = saved_mode
	assert_true(down, "the real player is down while Game.mode is not playing")
	assert_false(started, "no encounter from the death screen")
	assert_true(up, "back to playing: the arena works again")
	assert_false(bool(a.call("player_down", dummy)), "a stand-in with living health is never down")


## The victory is committed at once (flag, reward, the gate's collider); the gate's bars, its sound, the shake and
## the "retreats behind the old service gate" line wait for her retreat (retreat_seconds() - 0.8 s).
func test_the_service_gate_waits_for_her_retreat() -> void:
	await _make()
	var b := _engage()
	var a := _arena()
	b.set("fast_defeat", false)                 # the real retreat presentation
	var says: Array = []
	var scb := func(_s: String, t: String, _d: float) -> void:
		if t.contains("retreats behind the old service gate"):
			says.append(t)
	Events.say.connect(scb)
	assert_true(_to_state(b, "cling", 10.0))
	(a.call("brazier_for_anchor", int(b.get("held_line"))) as Node).call("light")
	assert_true(_to_state(b, "exposed", 30.0), "the light caught her anchor; her next pounce exposes her (QA CH2-007)")
	b.get("health").call("set_hp", 5.0)
	var retreat := float(b.call("retreat_seconds"))
	b.get("health").call("apply_damage", 20.0, dummy, Vector3.ZERO)
	assert_true(bool(a.get("cleared")), "committed at once")
	assert_true(bool(GameState.get_flag("ch2_crossing_cleared")), "flag at once")
	assert_true(GameState.has_reward("rw_ch2_crossing"), "reward at once")
	assert_true(bool(a.call("route_gate_shut")), "the route counts as shut")
	var gate: Node3D = a.get("route_gate")
	var bars: Node3D = gate.get_node("Bars")
	var shape := gate.get_node("GateBody").get_child(0) as CollisionShape3D
	await wait_physics(2)
	assert_false(shape.disabled, "the gate's collider closes the route at once")
	assert_true(retreat - 0.8 > 1.0, "a real retreat plays (%.2f s)" % retreat)
	assert_true(bars.position.y > 2.0, "the bars wait while she retreats")
	assert_false(_caps.has("[an old service gate grinds shut over the deeper route]"), "no gate caption yet")
	assert_eq(says.size(), 0, "no line yet")
	await wait_seconds(retreat - 0.8 + 1.0)
	assert_almost(bars.position.y, 0.0, 0.01, "the bars dropped as she slipped through")
	assert_true(_caps.has("[an old service gate grinds shut over the deeper route]"), "the gate caption")
	assert_eq(says.size(), 1, "her retreat line once")
	assert_true(bool(b.call("is_gone")), "she is gone behind it")
	Events.say.disconnect(scb)
