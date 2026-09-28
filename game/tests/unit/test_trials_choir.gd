extends "res://tests/unit/test_trials_harness.gd"
## Echo Trial "The Borrowed Song" (the Borrowed Choir; data/trials.gd "choir", src/world/trial/choir_trial.gd,
## module D1): a remembered copy of the Choir Vault (radius 12.4, safe perimeter walk from 10.4) with the REAL boss
## script in trial mode, fresh lantern anchors and resonators carrying the Bellmaker's symbols, the readable order in
## the corridor; the pad is beyond the stand-down line; a win pays the first-clear bundle once, then bounded
## renewable resources; a win or loss never changes a story flag or emits boss_defeated (even on an unfinished
## save, where the story Choir would set ch2_choir_defeated itself); arachnophobia: nothing spider-like.

const VaultLayout := preload("res://data/works_layout_deep.gd")
const ChoirTrial := preload("res://src/world/trial/choir_trial.gd")
const ChoirBoss := preload("res://src/enemies/borrowed_choir.gd")


func test_the_real_choir_spawns_in_trial_mode_in_a_faithful_vault() -> void:
	completed_save()
	var a := await trial_area("choir")
	assert_eq(String(a.get("trial_id")), "choir")
	var boss: Node = a.get("boss")
	assert_not_null(boss, "the Borrowed Choir is here")
	if boss == null:
		return
	assert_true(String(boss.get_script().resource_path).ends_with("borrowed_choir.gd"), "the real boss script")
	assert_eq(String(boss.get("mode")), "trial")
	assert_false(bool(boss.call("is_story")))
	assert_false(bool(boss.call("is_gone")), "it sings although ch2_choir_defeated is set (a memory)")
	assert_false(bool(boss.get("fight_started")), "waiting until Krystal steps inside the perimeter")
	assert_null(boss.get("arena"), "no story arena: nothing listens to set the story flag")
	var ar: Dictionary = a.get("arena")
	assert_almost(float(boss.get("arena_radius")), float(VaultLayout.VAULT["radius"]), 0.001)
	assert_almost(float(boss.get("perimeter_radius")), float(VaultLayout.VAULT["perimeter"]), 0.001)
	assert_eq((ar["anchors"] as Array).size(), 3, "three fixed lantern anchors")
	assert_eq((ar["resonators"] as Array).size(), 2, "two fixed resonators")
	assert_eq((boss.get("anchor_nodes") as Array).size(), 3, "the boss plays with the anchors")
	assert_eq((boss.get("resonator_nodes") as Array).size(), 2, "and the resonators")
	var taught: Array = []
	for s in VaultLayout.bell_symbols():
		taught.append(String(s["id"]))
	assert_eq(boss.call("taught_sequence"), taught, "the Bellmaker's order")
	# Faithful: same distances from the centre as in the real vault (turned half round).
	var c: Vector3 = VaultLayout.VAULT["center"]
	for i in 3:
		var real: Vector3 = VaultLayout.VAULT["anchors"][i]
		var mem: Vector3 = (ar["anchors"][i] as Node3D).global_position
		assert_almost(Vector2(mem.x, mem.z).length(), Vector2(real.x - c.x, real.z - c.z).length(), 0.01, "anchor %d radius" % i)
		assert_almost(mem.x, -(real.x - c.x), 0.01)
		assert_almost(mem.z, -(real.z - c.z), 0.01)
	for i in 2:
		var real2: Vector3 = VaultLayout.VAULT["resonators"][i]
		var mem2: Vector3 = (ar["resonators"][i] as Node3D).global_position
		assert_almost(Vector2(mem2.x, mem2.z).length(), Vector2(real2.x - c.x, real2.z - c.z).length(), 0.01, "resonator %d radius" % i)
	# The order is readable in the corridor, with names (never colour alone).
	var board: Node3D = ar["order_board"]
	assert_not_null(board)
	var txt: Array = label_texts(board)
	for s in VaultLayout.bell_symbols():
		assert_true(txt.has(String(s.get("name", ""))), "the order names %s" % s["id"])
	assert_true(board.find_children("*", "", true, false).any(func(n: Node) -> bool: return n.is_in_group("interactable")), "and can be read")
	# Pad, door, safety.
	var start: Vector3 = (a.spawns["trial_start"] as Transform3D).origin
	assert_true(bool(a.is_safe_zone(start)), "the entry pad is safe")
	assert_false(bool(a.is_safe_zone(Vector3.ZERO)))
	var leave_line := float(boss.get("arena_radius")) + float(ChoirBoss.LEAVE_MARGIN)
	for k in 12:
		var p := start + Vector3(cos(TAU * k / 12.0), 0, sin(TAU * k / 12.0)) * 2.8
		assert_true(Vector2(p.x, p.z).length() > leave_line, "every point of the pad is past its stand-down line")
	assert_true(Vector2(start.x, start.z).length() > float(boss.get("perimeter_radius")), "arriving never wakes it")
	assert_not_null((a.get("exits") as Dictionary).get("leave"), "the pale door")
	# Geometry: floor across the vault and the perimeter walk, the ring wall round it except the corridor mouth.
	var space := a.get_world_3d().direct_space_state
	for p in [Vector3.ZERO, Vector3(11.4, 0, 0), Vector3(-11.4, 0, 0), Vector3(0, 0, -11.4), Vector3(0, 0, 12.0), start]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0, 1))
		assert_false(hit.is_empty(), "floor at %s" % str(p))
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), 0.0, 0.05, "flat floor at %s" % str(p))
	for k in 24:
		var dir := Vector3(cos(TAU * k / 24.0), 0, sin(TAU * k / 24.0))
		if dir.z > 0.95:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 6.0, 0), Vector3(0, 6.0, 0) + dir * 20.0, 1))
		assert_false(hit.is_empty(), "walled toward %s" % str(dir))
		if not hit.is_empty():
			var dist := Vector2(hit["position"].x, hit["position"].z).length()
			assert_true(dist >= 12.3 and dist <= 13.6, "the ring wall stands just outside the walk (%.2f m)" % dist)
	for sx in [-1.0, 1.0]:
		assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 18), Vector3(sx * 6.0, 1, 18), 1)).is_empty(), "corridor walled")
	assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 20), Vector3(0, 1, 30), 1)).is_empty(), "the corridor ends in a wall")
	# The perimeter walk is clear all the way round (1 m wide at least), apart from nothing.
	for k in 36:
		var ang := TAU * k / 36.0
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.4
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, Vector3(cos(ang) * 11.4, 1.05, sin(ang) * 11.4))
		q.collision_mask = 1
		assert_true(space.intersect_shape(q, 4).is_empty(), "the perimeter walk is walkable at %d deg" % int(rad_to_deg(ang)))


func test_a_win_pays_the_first_clear_once_then_bounded_repeats_and_no_story_flag() -> void:
	completed_save()
	var before: Dictionary = GameState.flags.duplicate(true)
	var stories := story_flags()
	var a := await trial_area("choir")
	await win_choir(a)
	assert_eq(String(a.get("result")), "won", "the Choir fell (%s)" % String((a.get("boss") as Node).get("state")))
	assert_eq(ended, [["choir", true]], "Events.trial_ended(choir, true) once")
	assert_eq(defeats, [], "no Events.boss_defeated")
	assert_eq(int(EchoTrial.record("choir")["clears"]), 1)
	assert_true(GameState.has_reward("rw_trial_choir_first"), "first-clear bundle through the ledger")
	assert_eq(flag_diff(before), ["ch2_trial_choir"], "only the reward's pattern-unlock flag appears")
	assert_eq(story_flags(), stories, "story flags untouched")
	var ledger_n := GameState.ledger.size()
	var shards := GameState.count_item("echo_shard")
	var ore := GameState.count_item("iron_ore")
	var crystal := GameState.count_item("moon_crystal")
	for visit in [2, 3]:
		ended.clear()
		var a2 := await trial_area("choir")
		await win_choir(a2)
		assert_eq(ended, [["choir", true]], "visit %d won" % visit)
	var rec := EchoTrial.record("choir")
	assert_eq(int(rec["clears"]), 3)
	assert_eq(GameState.ledger.size(), ledger_n, "the first-clear bundle never pays twice")
	# Both repeat gifts wait (merged) for the trip home (lead decision L08); the arrival at the Bell Throat pays them.
	assert_eq(GameState.count_item("echo_shard"), shards, "nothing is given inside the echo")
	assert_eq(rec.get("pending", {}), {"echo_shard": 4, "iron_ore": 4, "moon_crystal": 1}, "two waiting gifts merge")
	assert_eq(EchoTrial.pay_pending("hushed_works"), {"echo_shard": 4, "iron_ore": 4, "moon_crystal": 1}, "paid on arrival")
	rec = EchoTrial.record("choir")
	assert_eq(GameState.count_item("echo_shard"), shards + 4, "2 echo shards per repeat")
	assert_eq(GameState.count_item("iron_ore"), ore + 4, "2 iron ore per repeat")
	assert_eq(GameState.count_item("moon_crystal"), crystal + 1, "the third clear adds one moon crystal")
	assert_eq(int(rec["repeat_paid"]), 2)
	assert_eq(rec["paid"], {"echo_shard": 4, "iron_ore": 4, "moon_crystal": 1}, "the trial ledger adds up")
	before["ch2_trial_choir"] = true
	assert_eq(GameState.flags, before, "repeat clears write no flag")
	assert_eq(defeats, [])


func test_a_loss_changes_nothing_and_the_echo_resets() -> void:
	completed_save()
	var before: Dictionary = GameState.flags.duplicate(true)
	var trials_before: Dictionary = GameState.trials.duplicate(true)
	var ledger_before: Dictionary = GameState.ledger.duplicate(true)
	var a := await trial_area("choir")
	var boss := control(a, Vector3(0, 0, -9))
	boss.call("start_fight")
	tick(boss, 4.0)
	assert_true(bool(a.get("fighting")), "the fight (and its clock) started")
	Events.player_died.emit()
	Events.player_died.emit()
	assert_eq(ended, [["choir", false]], "ended once, as a loss")
	assert_eq(String(a.get("result")), "lost")
	assert_eq(String(boss.get("state")), "dormant", "the echo resets")
	assert_false(bool(boss.get("fight_started")))
	for r in (a.get("arena") as Dictionary)["resonators"]:
		assert_true(bool((r as Node).get("enabled")), "resonators usable again")
	assert_eq(GameState.flags, before, "no flag changed")
	assert_eq(GameState.trials, trials_before, "no clear recorded")
	assert_eq(GameState.ledger, ledger_before, "no reward")


## Walking back to the safe pad stands the Choir down (to the start of the phase reached; neither a win nor a loss)
## and the trial's clock pauses; stepping inside the perimeter walk again wakes it.
func test_the_pad_stands_it_down_and_pauses_the_clock() -> void:
	completed_save()
	var a := await trial_area("choir")
	var boss := control(a, Vector3(0, 0, -9))
	var d: Node3D = boss.get("target_override")
	boss.call("start_fight")
	tick(boss, 2.0)
	assert_true(bool(a.get("fighting")), "the fight is on")
	await wait_frames(3)
	assert_true(float(a.get("elapsed")) > 0.0, "the clock runs while the fight is on")
	d.global_position = (a.spawns["trial_start"] as Transform3D).origin
	tick(boss, 4.0)
	assert_eq(String(boss.get("state")), "dormant", "it stands down while she waits on the pad")
	assert_false(bool(a.get("fighting")), "the clock stops")
	var t := float(a.get("elapsed"))
	await wait_frames(4)
	assert_almost(float(a.get("elapsed")), t, 0.00001, "and stays stopped")
	assert_eq(String(a.get("result")), "", "neither a win nor a loss")
	assert_eq(ended, [], "the echo goes on")
	d.global_position = Vector3(0, 0, -9)
	tick(boss, 0.5)
	assert_true(bool(boss.get("fight_started")), "it wakes when she steps inside the perimeter walk")
	assert_true(bool(a.get("fighting")), "the clock runs again")


## The story Choir sets ch2_choir_defeated ITSELF when no arena listens; the trial Choir never does, even on a save
## whose Choir was never beaten (never a fake victory over a story flag).
func test_a_trial_win_never_writes_the_story_flag_even_on_an_unfinished_save() -> void:
	GameState.give_item("lantern", 1)
	assert_false(EchoTrial.is_available("choir"), "not offered before the Choir is beaten")
	var a := await trial_area("choir")
	await win_choir(a)
	assert_eq(String(a.get("result")), "won")
	assert_false(bool(GameState.get_flag("ch2_choir_defeated")), "ch2_choir_defeated never written by a trial")
	assert_eq(defeats, [], "no Events.boss_defeated")
	# A story flag set elsewhere never dismisses the trial Choir either (the memory is its own).
	var a2 := await trial_area("choir")
	var boss: Node = a2.get("boss")
	GameState.set_flag("ch2_choir_defeated", true)
	Events.boss_defeated.emit("borrowed_choir")
	assert_false(bool(boss.call("is_gone")), "the trial Choir ignores story events")
	GameState.flags.erase("ch2_choir_defeated")


func test_arachnophobia_nothing_spider_like() -> void:
	completed_save()
	Settings.set_value("arachnophobia", true)
	var a := await trial_area("choir")
	a.call("on_player_spawned", dummy(a, Vector3(0, 0, 21.8)))
	var boss := control(a, Vector3(0, 0, -9))
	boss.call("start_fight")
	tick(boss, 10.0)
	var texts: Array = label_texts(a)
	for s in said:
		texts.append(String(s[1]))
	texts.append_array(captions)
	var m := EchoTrial.menu_text("choir")
	texts.append(String(m["title"]))
	texts.append(String(m["body"]))
	for t in texts:
		assert_eq(has_spider_word(String(t)), "", "no spider-like wording: " + String(t))
	assert_true(texts.size() > 4)
