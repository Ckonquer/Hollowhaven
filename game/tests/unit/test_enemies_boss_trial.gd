extends "res://tests/test_case.gd"
## Echo Trial "The Thread Above" (src/world/areas_ch2/echo_trial.gd + the Below entry): a separate,
## faithful instance of the Heartseed Chamber with the three-phase Matron in trial mode; the origin is
## remembered as the respawn point; the first clear pays the content bundle rw_trial_matron_first once,
## later clears pay modest renewable resources through the trial's own counter; a win or a loss never
## changes a story flag, never spawns a Heartseed, never emits boss_defeated. The Below offers the trial
## only on completed saves, at the arena checkpoint.
## Headless; the area scene is instantiated directly (no Game.change_area), no saves written.

const EchoTrial := preload("res://src/world/areas_ch2/echo_trial.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const TRIAL_SCENE := "res://scenes/echo_trial.tscn"
const BELOW := "res://src/world/below/below_world.gd"

const DT := 0.05

var _nodes: Array = []
var _ended: Array = []
var _defeats: Array = []
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_area_id: String = ""
var _saved_companions: Dictionary = {}


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 5000.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	_ended.clear()
	_defeats.clear()
	Settings.set_value("arachnophobia", false)
	Base.reset_attack_tokens()
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_area_id = Game.area_id
	_saved_companions = Game.companion_nodes
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}
	EchoTrial.pending_trial = ""
	Events.trial_ended.connect(_on_ended)
	Events.boss_defeated.connect(_on_defeat)


func after_each() -> void:
	Events.trial_ended.disconnect(_on_ended)
	Events.boss_defeated.disconnect(_on_defeat)
	Settings.set_value("arachnophobia", false)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	Game.area = _saved_area
	Game.player = _saved_player
	Game.area_id = _saved_area_id
	Game.companion_nodes = _saved_companions
	EchoTrial.pending_trial = ""
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _on_ended(id: String, won: bool) -> void:
	_ended.append([id, won])


func _on_defeat(id: String) -> void:
	_defeats.append(id)


func _completed_save() -> void:
	for f in ["chapter_one_complete", "weaver_defeated", "ward_restored", "lower_gate_open", "gallery_cleared"]:
		GameState.set_flag(f, true)


func _trial_area() -> Node3D:
	var a: Node3D = (load(TRIAL_SCENE) as PackedScene).instantiate()
	add_child(a)
	_nodes.append(a)
	await wait_physics(2)
	return a


func _dummy(parent: Node, pos: Vector3) -> Dummy:
	var d := Dummy.new()
	parent.add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _tick_until(b: Node, s: String, max_t: float) -> void:
	var t := 0.0
	while String(b.get("state")) != s and t < max_t:
		b.call("tick", DT)
		t += DT


## Fights the trial's Matron down quickly (a brazier scorch, then a finishing blow).
func _win(a: Node3D) -> void:
	var boss: Node = a.get("boss")
	boss.set_process(false)
	boss.set("fast_defeat", true)
	boss.set("intensity_override", 1)
	boss.set("target_override", _dummy(a, Vector3(0, 0, 3)))
	_tick_until(boss, "cling", 6.0)
	((a.get("braziers") as Array)[0] as Node).call("light")
	_tick_until(boss, "scorched", 2.0)
	boss.health.set_hp(5.0)
	boss.health.apply_damage(10.0)
	await wait_frames(2)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- The instance --------------------------------------------------------------------------------------

func test_prepare_remembers_the_origin_checkpoint() -> void:
	_completed_save()
	assert_true(EchoTrial.is_available("matron"), "offered once the Matron is beaten")
	EchoTrial.prepare("matron", "below", "cp_arena")
	assert_eq(EchoTrial.pending_trial, "matron")
	assert_eq(String(GameState.player["respawn_area"]), "below", "leaving / falling returns to the Below")
	assert_eq(String(GameState.player["respawn_spawn"]), "cp_arena", "at the arena checkpoint")
	var a: Node3D = await _trial_area()
	assert_eq(String(a.get("trial_id")), "matron", "the area hosts the prepared trial")
	assert_eq(EchoTrial.pending_trial, "", "and consumes it")
	var d: Dictionary = (a.get("exits") as Dictionary)["leave"].destination()
	assert_eq([String(d["area"]), String(d["spawn"])], ["below", "cp_arena"], "the pale door leads back to the origin")
	fresh_state()
	assert_false(EchoTrial.is_available("matron"), "not before the story fight is won")


func test_trial_arena_is_a_faithful_separate_copy() -> void:
	_completed_save()
	var a: Node3D = await _trial_area()
	assert_eq(String(a.get("area_id")), "echo_trial")
	assert_true((a.spawns as Dictionary).has("trial_start"))
	var start: Vector3 = (a.spawns["trial_start"] as Transform3D).origin
	assert_eq(String(a.get_zone_at(start)), "trial")
	assert_eq(String(a.get_zone_at(Vector3.ZERO)), "trial")
	assert_true(bool(a.is_safe_zone(start)), "the entry pad is safe")
	assert_false(bool(a.is_safe_zone(Vector3.ZERO)), "the arena is not")
	var boss: Node = a.get("boss")
	assert_not_null(boss, "the Matron is here")
	assert_eq(String(boss.get("mode")), "trial")
	assert_ne(String(boss.get("state")), "gone", "even though the story fight was won")
	assert_eq((boss.get("anchors") as Array).size(), Layout.ARENA_ANCHORS.size(), "same anchors")
	var brs: Array = a.get("braziers")
	assert_eq(brs.size(), 3)
	for i in 3:
		var want: Vector3 = Layout.BRAZIERS[i] - Layout.ARENA_CENTER
		assert_true((brs[i] as Node3D).global_position.distance_to(Vector3(want.x, 0, want.z)) < 0.01, "brazier %d where it stands in the real chamber" % i)
		assert_eq(String((brs[i] as Node).get("persist_flag")), "", "trial braziers persist nothing")
	# The pad sits outside the engage radius and past the stand-down line.
	var r := float(boss.get("arena_radius"))
	assert_true(_flat(start, Vector3.ZERO) > r + 9.0, "arriving never wakes her; stepping back onto the pad stands her down")
	# Geometry: floor under every brazier / landing spot, walls all round except the corridor mouth.
	var space := a.get_world_3d().direct_space_state
	for p in [Vector3.ZERO, Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, -9), Vector3(0, 0, 9), start]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0, 1)
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "floor at %s" % str(p))
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), 0.0, 0.05, "flat floor at %s" % str(p))
	for k in 16:
		var ang := TAU * float(k) / 16.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 2, 0), Vector3(0, 2, 0) + dir * 16.0, 1)   # above the braziers
		var hit := space.intersect_ray(q)
		if dir.z > 0.95:
			continue          # straight down the corridor
		assert_false(hit.is_empty(), "walled at %d deg" % int(rad_to_deg(ang)))
		if not hit.is_empty():
			var dist := Vector2(hit["position"].x, hit["position"].z).length()
			assert_true(dist >= float(EchoTrial.ARENA_RADIUS) and dist <= 12.6, "wall just outside the floor (%.2f m at %d deg)" % [dist, int(rad_to_deg(ang))])
	for sx in [-1.0, 1.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 18), Vector3(sx * 6.0, 1, 18), 1)
		assert_false(space.intersect_ray(q).is_empty(), "corridor walled on both sides")
	var out := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 20), Vector3(0, 1, 30), 1)
	assert_false(space.intersect_ray(out).is_empty(), "the corridor ends in a wall")


# --- Rewards and isolation ------------------------------------------------------------------------------

func test_first_clear_pays_the_bundle_once_then_renewable_resources_and_no_story_flag() -> void:
	_completed_save()
	var flags_before: Dictionary = GameState.flags.duplicate(true)
	var a: Node3D = await _trial_area()
	await _win(a)
	assert_eq(String(a.get("result")), "won")
	assert_eq(_ended, [["matron", true]], "Events.trial_ended(matron, true)")
	assert_eq(_defeats, [], "no Events.boss_defeated")
	assert_eq(get_tree().get_nodes_in_group("heartseed_pickup").size(), 0, "no Heartseed")
	assert_eq(int(EchoTrial.record("matron")["clears"]), 1, "the trial's own counter")
	assert_true(GameState.has_reward("rw_trial_matron_first"), "first-clear bundle through the ledger")
	var diff: Array = []
	for k in GameState.flags:
		if not flags_before.has(k) or flags_before[k] != GameState.flags[k]:
			diff.append(k)
	for k in flags_before:
		if not GameState.flags.has(k):
			diff.append(k)
	assert_eq(diff, ["ch2_trial_matron"], "only the reward's pattern-unlock flag appears (no story flag)")
	assert_true(bool(GameState.get_flag("weaver_defeated")) and bool(GameState.get_flag("ward_restored")), "story flags untouched")
	var ledger_n := GameState.ledger.size()
	var silk := GameState.count_item("silk")
	var caps := GameState.count_item("glowcap")
	# A second visit.
	_ended.clear()
	var a2: Node3D = await _trial_area()
	await _win(a2)
	assert_eq(_ended, [["matron", true]])
	assert_eq(int(EchoTrial.record("matron")["clears"]), 2)
	assert_eq(GameState.ledger.size(), ledger_n, "the first-clear reward is never paid twice")
	assert_eq(GameState.count_item("silk"), silk + 3, "modest renewable silk")
	assert_eq(GameState.count_item("glowcap"), caps + 2, "and glowcaps")
	assert_false(GameState.has_item("heartseed"), "never a Heartseed")
	var after2: Dictionary = GameState.flags.duplicate(true)
	flags_before["ch2_trial_matron"] = true
	assert_eq(after2, flags_before, "repeat clears write no flag at all")


func test_record_clear_tracks_best_time_and_a_small_bonus() -> void:
	_completed_save()
	var r1 := EchoTrial.record_clear("matron", 150.0)
	assert_true(bool(r1["first"]))
	assert_almost(float(r1["best_seconds"]), 150.0, 0.001)
	var r2 := EchoTrial.record_clear("matron", 120.0)
	assert_false(bool(r2["first"]))
	assert_almost(float(r2["best_seconds"]), 120.0, 0.001, "a faster clear is the new best")
	assert_eq(r2["items"], {"silk": 3, "glowcap": 2})
	var r3 := EchoTrial.record_clear("matron", 200.0)
	assert_almost(float(r3["best_seconds"]), 120.0, 0.001, "a slower clear keeps the best")
	assert_eq(int((r3["items"] as Dictionary).get("echo_shard", 0)), 1, "every third clear adds a small bonus")
	var round_trip: Dictionary = GameState.to_dict()
	GameState.from_dict(round_trip)
	assert_eq(int(EchoTrial.record("matron")["clears"]), 3, "the trial record survives a save round trip")


func test_a_loss_ends_the_trial_and_changes_nothing() -> void:
	_completed_save()
	var flags_before: Dictionary = GameState.flags.duplicate(true)
	var trials_before: Dictionary = GameState.trials.duplicate(true)
	var a: Node3D = await _trial_area()
	var boss: Node = a.get("boss")
	boss.set_process(false)
	boss.set("target_override", _dummy(a, Vector3(0, 0, 3)))
	_tick_until(boss, "cling", 6.0)
	assert_true(bool(a.get("fighting")), "the fight (and its clock) started")
	Events.player_died.emit()
	Events.player_died.emit()
	assert_eq(_ended, [["matron", false]], "ended once, as a loss")
	assert_eq(String(a.get("result")), "lost")
	assert_eq(String(boss.get("state")), "dormant", "the echo resets")
	assert_eq(GameState.flags, flags_before, "no flag changed")
	assert_eq(GameState.trials, trials_before, "no clear recorded")
	assert_false(GameState.has_reward("rw_trial_matron_first"))


# --- The Below entry ----------------------------------------------------------------------------------------

func test_the_below_offers_the_echo_only_after_victory_at_the_arena_checkpoint() -> void:
	var below: Node3D = load(BELOW).new()
	add_child(below)
	_nodes.append(below)
	await wait_physics(2)
	assert_null(below.get("echo_entry"), "no echo before the Matron is beaten")
	below.call("_on_boss_defeated", "count_velour")
	assert_false(bool(GameState.get_flag("weaver_defeated")), "another boss id never marks this chamber as won")
	below.queue_free()
	await wait_frames(2)
	_completed_save()
	var b2: Node3D = load(BELOW).new()
	add_child(b2)
	_nodes.append(b2)
	await wait_physics(2)
	assert_null(b2.get("boss"), "the story boss never returns")
	var entry: Node3D = b2.get("echo_entry")
	assert_not_null(entry, "the echo stone is there")
	if entry == null:
		return
	assert_eq(String(entry.get_interaction(null)["text"]), "Echo Trial: The Thread Above (a remembered challenge)")
	Settings.set_value("arachnophobia", true)
	assert_eq(String(entry.get_interaction(null)["text"]), "Echo Trial: The Hollow Above (a remembered challenge)", "arachnophobia wording")
	Settings.set_value("arachnophobia", false)
	var p := entry.global_position
	assert_eq(Layout.room_at(p + Vector3.UP * 0.5), "antechamber", "in the antechamber before the arena")
	var cp: Vector3 = Layout.CHECKPOINTS["arena"]["pos"]
	assert_true(p.distance_to(cp) <= 4.0, "beside the arena checkpoint lantern (%.1f m)" % p.distance_to(cp))
	assert_true(p.x < 102.0, "clear of the walking line between the antechamber's openings")
	assert_true(entry.is_in_group("interactable"))
	var solid := false
	for c in entry.find_children("*", "StaticBody3D", true, false):
		solid = solid or ((c as StaticBody3D).collision_layer & 1) != 0
	assert_false(solid, "it blocks nobody (no collision)")
