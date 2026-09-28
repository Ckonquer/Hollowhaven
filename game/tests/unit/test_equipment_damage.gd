extends "res://tests/test_case.gd"
## Krystal's damage intake and support effects (spec section 9): i-frames -> reduction -> shield -> Health,
## one hit processed once, shield timing / stacking / pause, heal path x Stats.heal_mult, movement through
## Stats.move_mult (companion, cap, slow), bounded slows, knockback resist, equipment stamina costs and the
## saved base max HP.

const PlayerScript := preload("res://src/player/player.gd")
const PlayerHealth := preload("res://src/player/player_health.gd")
const Combat := preload("res://src/combat/combat.gd")
const Logic := preload("res://src/player/player_logic.gd")
const Stats := preload("res://src/core/stats.gd")
const CreaturesData := preload("res://data/creatures.gd")

var floor_body: StaticBody3D
var player: CharacterBody3D
var _saved_mode := ""
var _saved_player: Node3D = null
var _saved_nodes: Dictionary = {}
var _saved_area: Node = null
var _shield_events: Array = []
var _damaged_events: int = 0


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	_saved_player = Game.player
	_saved_nodes = Game.companion_nodes.duplicate()
	_saved_area = Game.area
	Game.area = null          # Game's zone poll must not touch a stale area while these tests set Game.player
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	_shield_events = []
	_damaged_events = 0
	await wait_physics(8)


func after_each() -> void:
	for a in ["move_forward", "sprint"]:
		Input.action_release(a)
	get_tree().paused = false
	Game.mode = _saved_mode
	Game.player = _saved_player
	Game.companion_nodes = _saved_nodes
	Game.area = _saved_area
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


func _wear(ids: Array) -> void:
	for id in ids:
		GameState.give_item(String(id), 1)
		assert_true(GameState.equip(String(id)), "equip %s" % id)


## The real player as Krystal, `id` following 3 m away at `bond` hearts.
func _with_companion(id: String, bond: int) -> Node3D:
	Game.player = player
	var c := Node3D.new()
	add_child(c)
	c.global_position = player.global_position + Vector3(3, 0, 0)
	Game.companion_nodes = {id: c}
	var rec := GameState.companion(id)
	rec["befriended"] = true
	rec["assignment"] = "follow"
	rec["bond_xp"] = int(CreaturesData.BOND_XP_PER_LEVEL[bond])
	GameState.active_companion = id
	player.refresh_stats()
	return c


func _on_shield(amount: float) -> void:
	_shield_events.append(amount)


func _on_damaged(_a: float, _s: Node) -> void:
	_damaged_events += 1


func test_player_uses_the_shielded_health() -> void:
	assert_true(player.health.get_script() == PlayerHealth, "player_health.gd")
	assert_true(player.health.has_method("add_shield"))
	assert_almost(float(player.health.apply_damage(15.0)), 15.0, 0.001, "no gear: legacy numbers exactly")


func test_iframes_are_checked_before_reduction_and_shield() -> void:
	player.add_shield(25.0, 6.0, "pebble")
	player.health.grant_iframes(1.0)
	assert_almost(float(player.health.apply_damage(20.0)), 0.0, 0.0001, "i-frames: nothing happens")
	assert_almost(player.shield_amount(), 25.0, 0.0001, "the shield was not touched")
	assert_almost(float(player.health.hp), 100.0, 0.0001)


func test_reduction_then_shield_then_health() -> void:
	_wear(["ironwood_helm", "ironwood_mail", "ironwood_boots"])
	_with_companion("pebble", 0)
	Events.player_shield_changed.connect(_on_shield)
	player.add_shield(10.0, 6.0, "pebble")
	var dealt: float = float(player.health.apply_damage(50.0, null, Vector3(0, 0, 1)))
	Events.player_shield_changed.disconnect(_on_shield)
	var lh: Dictionary = player.health.last_hit
	assert_almost(float(lh["reduction"]), 0.28, 0.0001, "armor x Pebble")
	assert_almost(float(lh["mitigated"]), 36.0, 0.001, "50 x 0.72")
	assert_almost(float(lh["absorbed"]), 10.0, 0.001, "shield absorbs AFTER mitigation")
	assert_almost(dealt, 26.0, 0.001, "the rest reaches Health")
	assert_almost(float(player.health.hp), 74.0, 0.001)
	assert_almost(float(GameState.player["hp"]), 74.0, 0.001, "synced")
	assert_almost(player.shield_amount(), 0.0, 0.0001, "shield used up")
	assert_eq(_shield_events, [10.0, 0.0], "Events.player_shield_changed: added, then broken")


func test_shield_swallows_a_whole_hit_once() -> void:
	Events.player_damaged.connect(_on_damaged)
	player.add_shield(25.0, 6.0, "pebble")
	var v0: Vector3 = player.velocity
	var dealt: float = float(player.health.apply_damage(20.0, null, Vector3(1, 0, 0)))
	var again: float = float(player.health.apply_damage(20.0, null, Vector3(1, 0, 0)))
	Events.player_damaged.disconnect(_on_damaged)
	assert_almost(dealt, 0.0, 0.0001, "fully absorbed = blocked (0)")
	assert_almost(float(player.health.hp), 100.0, 0.0001, "no hp lost")
	assert_almost(player.shield_amount(), 5.0, 0.0001, "25 - 20")
	assert_almost(again, 0.0, 0.0001, "the same attack can't chew through twice (short i-frames)")
	assert_almost(player.shield_amount(), 5.0, 0.0001, "the second call processed nothing")
	assert_eq(_damaged_events, 0, "no hurt event for a shielded hit")
	assert_true(Vector2(player.velocity.x - v0.x, player.velocity.z - v0.z).length() < 0.01, "no knockback")


func test_one_melee_hit_is_processed_once() -> void:
	Events.player_damaged.connect(_on_damaged)
	var foe := Node3D.new()
	add_child(foe)
	foe.global_position = Vector3(0, 0, -1.2)
	var hits: Array = Combat.melee(foe, foe.global_position + Vector3.UP * 0.5, Vector3(0, 0, 1), 1.5, 80.0, 10.0, ["player", "player"], 0.0)
	var hits2: Array = Combat.melee(foe, foe.global_position + Vector3.UP * 0.5, Vector3(0, 0, 1), 1.5, 80.0, 10.0, ["player"], 0.0)
	Events.player_damaged.disconnect(_on_damaged)
	assert_eq(hits.size(), 1, "listed twice, hit once")
	assert_eq(hits2.size(), 0, "hurt i-frames block the follow-up")
	assert_almost(float(player.health.hp), 90.0, 0.001, "exactly one hit of 10")
	assert_eq(_damaged_events, 1)


func test_shield_timing_stacking_and_pause() -> void:
	player.add_shield(25.0, 6.0, "pebble")
	player.add_shield(10.0, 8.0, "other")
	assert_almost(player.shield_amount(), 25.0, 0.0001, "never stacks: the larger stays")
	assert_almost(float(player.health.shield_left), 8.0, 0.0001, "a smaller one only extends the time")
	player.add_shield(32.0, 2.0, "pebble")
	assert_almost(player.shield_amount(), 32.0, 0.0001, "a larger one replaces")
	player.add_shield(500.0, 1.0, "x")
	assert_almost(player.shield_amount(), PlayerHealth.MAX_SHIELD, 0.0001, "bounded")
	player.health.clear_shield()
	player.add_shield(20.0, 0.15, "pebble")
	get_tree().paused = true
	await wait_seconds(0.35)
	assert_almost(player.shield_amount(), 20.0, 0.0001, "pause suspends the shield timer")
	get_tree().paused = false
	await wait_seconds(0.35)
	assert_almost(player.shield_amount(), 0.0, 0.0001, "it fades after its time")


func test_heal_path_applies_heal_mult_once() -> void:
	_with_companion("mochi", 0)
	_wear(["kindling_charm"])
	player.health.apply_damage(50.0)
	var h: float = float(player.health.heal(10.0))
	assert_almost(h, 10.0 * 1.18, 0.001, "Mochi 8% + Kindling 10%")
	assert_almost(float(player.health.hp), 50.0 + 11.8, 0.001)
	player.set("_eat_lock", 0.0)
	GameState.give_item("berries", 1)
	var before := float(player.health.hp)
	assert_true(player.eat("berries"))
	assert_almost(float(player.health.hp) - before, float(ItemDB.item("berries")["heal"]) * 1.18, 0.001, "food heals once, scaled once")
	player.health.heal(1000.0)
	assert_almost(float(player.health.hp), 100.0, 0.001, "never above max")


func test_walk_speed_uses_move_mult_with_cap() -> void:
	Game.mode = "playing"
	_with_companion("lumi", 0)
	player.rig.snap(0.0)
	Input.action_press("move_forward")
	await wait_physics(40)
	var v: Vector3 = player.velocity
	assert_almost(Vector2(v.x, v.z).length(), Logic.WALK_SPEED * 1.08, 0.06, "Lumi +8% walk")
	GameState.add_buff("glimmerstep", 0.5, 4.0)
	player.refresh_stats()
	await wait_physics(30)
	v = player.velocity
	assert_almost(Vector2(v.x, v.z).length(), Logic.WALK_SPEED * 1.3, 0.06, "capped at +30%")
	GameState.buffs.erase("glimmerstep")
	assert_true(player.apply_slow(0.3, 1.0), "slow applied")
	await wait_physics(30)
	v = player.velocity
	assert_almost(Vector2(v.x, v.z).length(), Logic.WALK_SPEED * 1.08 * Stats.SLOW_FLOOR, 0.06, "slow bounded at the floor")
	Input.action_release("move_forward")


func test_slows_are_bounded_never_chained_and_cleansable() -> void:
	assert_true(player.apply_slow(0.2, 10.0, "mud"), "applied")
	assert_almost(GameState.buff_mult("slow"), Stats.SLOW_FLOOR, 0.0001, "never stronger than the floor")
	assert_almost(float(GameState.buffs["slow"]["remaining"]), Stats.SLOW_MAX_SECONDS, 0.0001, "never longer than the max")
	assert_false(player.apply_slow(0.7, 1.0, "mud"), "no chaining while slowed / immune")
	assert_true(player.is_slowed())
	assert_true(player.clear_slow(), "Mochi's cleanse clears it")
	assert_false(player.is_slowed())
	assert_false(player.clear_slow(), "nothing left to clear")
	assert_almost(player.move_mult(), 1.0, 0.0001, "speed back to normal at once")


func test_knockback_resist_covers_one_hit() -> void:
	player.resist_knockback(1, 5.0)
	player.knockback(Vector3(1, 0, 0), 5.0)
	player.knockback(Vector3(1, 0, 0), 5.0)
	assert_almost(player.velocity.x, 0.0, 0.001, "both pushes of the same hit are shrugged off")
	player.set("_kb_resist_used_ms", -1000000)
	player.knockback(Vector3(1, 0, 0), 5.0)
	assert_almost(player.velocity.x, 5.0, 0.001, "only one hit is resisted")


func test_equipment_scales_stamina_costs() -> void:
	_wear(["swiftstep_charm"])
	await wait_physics(4)
	player.stamina = 100.0
	player.call("_try_dodge")
	assert_almost(float(player.stamina), 100.0 - 20.0 * 0.88, 0.01, "dodge 20 x 0.88")
	player.set("_dodge_t", -1.0)
	player.set("_dodge_cd", 0.0)
	GameState.unequip("charm")
	player.stamina = 100.0
	player.call("_try_dodge")
	assert_almost(float(player.stamina), 80.0, 0.01, "legacy dodge cost without the charm")


func test_base_max_hp_is_written_back() -> void:
	player.health.apply_damage(30.0)
	player.write_to_state()
	assert_almost(float(GameState.player["max_hp"]), 100.0, 0.0001)
	assert_almost(float(player.health.max_hp), Stats.effective_max_hp(), 0.0001)
	GameState.player["hp"] = 55.0
	player.read_from_state()
	assert_almost(float(player.health.hp), 55.0, 0.0001)
	assert_almost(float(GameState.player["max_hp"]), 100.0, 0.0001, "reading never inflates the saved max")


func test_respawn_clears_the_transient_shield() -> void:
	player.add_shield(25.0, 6.0, "pebble")
	GameState.player["hp"] = 100.0
	player.read_from_state()
	assert_almost(player.shield_amount(), 0.0, 0.0001, "shields are not saved or carried over")
