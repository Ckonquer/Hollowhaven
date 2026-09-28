extends "res://tests/test_case.gd"
## Krystal's Sparkseed Wand (player.gd + projectile.gd, MP 5.1): with the wand selected on the hotbar, attack
## casts a readable spark: shared stamina, cooldown, finite range, line of sight, at most three in flight,
## lower sustained damage than melee. It is never picked automatically, never used to mine or chop, and the
## legacy melee auto-selection stays exactly as it was.

const PlayerScript := preload("res://src/player/player.gd")
const DummyScript := preload("res://src/player/qa_dummy.gd")
const Projectile := preload("res://src/combat/projectile.gd")
const Logic := preload("res://src/player/player_logic.gd")

var floor_body: StaticBody3D
var player: CharacterBody3D
var _saved_mode := ""


func before_each() -> void:
	fresh_state()
	Projectile.stop_all()
	_saved_mode = Game.mode
	Game.mode = "playing"
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(60, -0.5, 60)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(60, 0.05, 60)))
	await wait_physics(8)


func after_each() -> void:
	Projectile.stop_all()
	Game.mode = _saved_mode
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


func _dummy(offset: Vector3) -> Node3D:
	var d: Node3D = DummyScript.new()
	d.setup({"mode": "enemy"})
	add_child(d)
	d.global_position = Vector3(60, 0, 60) + offset
	Projectile.invalidate_targets()
	return d


func _hold_wand() -> void:
	GameState.give_item("sparkseed_wand", 1)
	var idx := -1
	for i in GameState.HOTBAR_SIZE:
		var s: Variant = GameState.inventory.get_slot(i)
		if s != null and String(s["id"]) == "sparkseed_wand":
			idx = i
	GameState.select_hotbar(idx)
	assert_eq(player.selected_wand(), "sparkseed_wand", "wand selected")


func test_attack_with_the_wand_casts_a_spark() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -6))
	player.call("_on_attack_pressed")
	assert_almost(float(player.stamina), 100.0 - 8.0, 0.01, "shared stamina: 8 per spark")
	assert_true(float(player.wand_cooldown_left()) > 0.7, "cooldown started")
	await wait_physics(45)
	assert_not_null(player.last_bolt, "a spark was fired")
	assert_eq(String(player.last_bolt.kind), "wand")
	assert_almost(float(foe.get("health").hp), 30.0 - 9.0, 0.01, "9 damage at 6 m")


func test_cooldown_limits_the_fire_rate() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -6))
	player.call("_on_attack_pressed")
	await wait_physics(30)                       # 0.5 s: cast done, cooldown not yet
	var st := float(player.stamina)
	player.call("_on_attack_pressed")
	player.call("_on_attack_pressed")
	await wait_physics(4)
	assert_almost(float(player.stamina), st, 0.5, "no second spark inside the cooldown")
	await wait_physics(60)                       # the queued click fires once the cooldown is over
	assert_almost(float(foe.get("health").hp), 30.0 - 18.0, 0.01, "exactly two sparks landed")


func test_needs_line_of_sight() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -7))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.4)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(60, 1, 60 - 3.5)
	await wait_physics(2)
	assert_null(player.call("_ranged_target", 14.0, Vector3(0, 0, -1)), "no target through the wall")
	player.call("_on_attack_pressed")
	await wait_physics(50)
	assert_almost(float(foe.get("health").hp), 30.0, 0.01, "the spark stops at the wall")


func test_finite_range() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -18))
	assert_null(player.call("_ranged_target", 14.0, Vector3(0, 0, -1)), "18 m is out of range")
	player.call("_on_attack_pressed")
	await wait_physics(90)
	assert_almost(float(foe.get("health").hp), 30.0, 0.01, "never reaches 18 m")


func test_too_tired_to_cast() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -6))
	player.stamina = 5.0
	player.call("_on_attack_pressed")
	await wait_physics(40)
	assert_almost(float(foe.get("health").hp), 30.0, 0.01, "no free sparks without stamina")
	assert_true(float(player.stamina) >= 5.0, "nothing spent")


func test_never_picked_automatically_for_melee() -> void:
	GameState.give_item("sparkseed_wand", 1)
	GameState.select_hotbar(5)                   # an empty slot is selected
	assert_eq(player.selected_wand(), "")
	var foe := _dummy(Vector3(0, 0, -1.3))
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_almost(float(foe.get("health").hp), 30.0 - Logic.HAND_DAMAGE, 0.01, "bare-hands melee, not the wand")
	assert_eq(Projectile.live_count(player), 0)


func test_selected_wand_never_mines() -> void:
	_hold_wand()
	GameState.give_item("stone_axe", 1)
	var tree: Node3D = DummyScript.new()
	tree.setup({"mode": "harvest"})
	add_child(tree)
	tree.global_position = Vector3(60, 0, 60 - 1.3)
	await wait_physics(8)
	player.probe.refresh()
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq(tree.get("hits"), ["stone_axe"], "the axe chops, the wand stays quiet")
	assert_null(player.last_bolt, "no spark")
	assert_almost(float(player.wand_cooldown_left()), 0.0, 0.001)


func test_at_most_three_sparks_in_flight() -> void:
	_hold_wand()
	for i in 3:
		player.set("_wand_cd", 0.0)
		player.set("_swing_ranged", true)
		player.set("_swing_tool", "sparkseed_wand")
		player.set("_cast_dir", Vector3(0, 0, -1))
		player.call("_fire_bolt")
	assert_eq(Projectile.live_count(player), 3)
	player.set("_swing_tool", "sparkseed_wand")
	player.set("_cast_dir", Vector3(0, 0, -1))
	assert_null(player.call("_fire_bolt"), "a fourth is refused")
	assert_false(bool(player.call("_start_cast", "sparkseed_wand", Vector3.ZERO)), "and no cast starts while three fly")


## COV-007: a hit taken during the wind-up (before the spark leaves at Logic.CAST_RELEASE) still interrupts the
## cast, but the cast costs nothing: the 8 stamina come back and the wand's cooldown is cleared, so she can cast
## again at once.
func test_hit_during_the_wind_up_refunds_the_cast() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -6))
	player.call("_on_attack_pressed")
	assert_almost(float(player.stamina), 100.0 - 8.0, 0.01, "the click pays for the cast")
	await wait_physics(3)                        # 0.05 s: still winding up (the spark leaves at 0.16 s)
	assert_true(bool(player.get("_swing_ranged")), "still winding up")
	player.health.apply_damage(5.0, null, Vector3.ZERO)
	assert_false(bool(player.get("_swing_ranged")), "the hit interrupts the cast (unchanged rule)")
	assert_almost(float(player.stamina), 100.0, 0.01, "the interrupted cast's stamina is refunded")
	assert_almost(float(player.wand_cooldown_left()), 0.0, 0.001, "and its cooldown cleared")
	await wait_physics(12)                       # past the 0.16 s release of the interrupted cast
	assert_null(player.last_bolt, "no spark left the wand")
	assert_almost(float(foe.get("health").hp), 30.0, 0.01, "the foe is untouched")
	# she can cast again right away (with the old code about 0.55 s of cooldown was left here, too long to queue)
	player.call("_on_attack_pressed")
	assert_true(bool(player.get("_swing_ranged")), "a new cast starts at once")
	assert_almost(float(player.stamina), 100.0 - 8.0, 0.01, "a fresh cast pays once")
	await wait_physics(45)
	assert_not_null(player.last_bolt, "the new spark flies")
	assert_almost(float(foe.get("health").hp), 30.0 - 9.0, 0.01, "and lands")


## COV-007 guard (no free spam): a hit AFTER the spark has left refunds nothing - the stamina and the cooldown
## stay spent, and the spark still lands.
func test_hit_after_the_release_refunds_nothing() -> void:
	_hold_wand()
	var foe := _dummy(Vector3(0, 0, -6))
	player.call("_on_attack_pressed")
	await wait_physics(15)                       # 0.25 s: the spark is out (regen delay 0.6 s: no regen yet)
	assert_not_null(player.last_bolt, "the spark was released")
	player.health.apply_damage(5.0, null, Vector3.ZERO)
	assert_almost(float(player.stamina), 100.0 - 8.0, 0.01, "no refund once the spark is out")
	assert_true(float(player.wand_cooldown_left()) > 0.4, "the cooldown keeps running")
	await wait_physics(45)
	assert_almost(float(foe.get("health").hp), 30.0 - 9.0, 0.01, "the released spark lands")


## Review fix: the use key follows the attack button's gate - no spark mid-bite.
func test_use_key_casts_but_never_while_eating() -> void:
	_hold_wand()
	player.set("_eat_lock", 0.8)
	player.call("_use_item")
	assert_almost(float(player.stamina), 100.0, 0.01, "no spark while eating")
	assert_almost(float(player.wand_cooldown_left()), 0.0, 0.001)
	player.set("_eat_lock", 0.0)
	player.call("_use_item")
	assert_almost(float(player.stamina), 100.0 - 8.0, 0.01, "the use key casts once the bite is over")
	assert_true(float(player.wand_cooldown_left()) > 0.7, "cooldown started")


## Integration (B9 Matron trial): boss floor hazards (egg sacs / seed pods, trip lines: meta "boss_hazard") rank
## Logic.WAND_HAZARD_SCORE_MULT times farther for the auto-aim, so the wand prefers the stunned boss behind them;
## on their own they are still a target.
func test_wand_prefers_the_boss_over_floor_hazards() -> void:
	_hold_wand()
	var boss := _dummy(Vector3(0, 0, -9))
	var sac := _dummy(Vector3(1.2, 0, -4))
	sac.set_meta("boss_hazard", true)
	await wait_physics(2)
	var aim := Vector3(0, 0, -1)
	assert_eq(player.call("_ranged_target", 14.0, aim), boss, "the boss 9 m away beats a hazard 4 m away")
	sac.set_meta("boss_hazard", false)
	assert_eq(player.call("_ranged_target", 14.0, aim), sac, "control: without the meta the closer target wins")
	sac.set_meta("boss_hazard", true)
	var near_sac := _dummy(Vector3(-0.3, 0, -1.8))
	near_sac.set_meta("boss_hazard", true)
	assert_eq(player.call("_ranged_target", 14.0, aim), near_sac, "a hazard right at her feet still wins (a soft preference)")
	near_sac.free()
	boss.remove_from_group("enemy")
	assert_eq(player.call("_ranged_target", 14.0, aim), sac, "alone, a hazard is still a target")
	boss.add_to_group("enemy")
	Projectile.invalidate_targets()
	player.call("_on_attack_pressed")
	await wait_physics(50)
	assert_almost(float(boss.get("health").hp), 30.0 - 9.0, 0.01, "the spark flies to the boss")
	assert_almost(float(sac.get("health").hp), 30.0, 0.01, "and leaves the hazard alone")


## Review fix (B3): a selected wand shows in Krystal's hand (built on first use) and a cast plays the wand pose
## instead of the bare-hands swing; selecting something else puts it away.
func test_holding_the_wand_shows_it_in_her_hand() -> void:
	var av: Node3D = player.avatar
	assert_eq(String(av.call("held_tool")), "", "nothing held on a fresh save")
	assert_false((av.get("_tools") as Dictionary).has("wand"), "no wand model until one is held")
	_hold_wand()
	assert_eq(String(av.call("held_tool")), "wand", "selecting the wand puts it in her hand")
	var w: Node3D = (av.get("_tools") as Dictionary)["wand"]
	await wait_frames(2)
	assert_true(w.visible, "wand shown between casts")
	var foe := _dummy(Vector3(0, 0, -6))
	player.call("_on_attack_pressed")
	await wait_physics(4)
	await wait_frames(1)
	assert_eq(String(av.get("swing_kind")), "wand", "the cast plays the wand pose")
	assert_true(float(av.get("swing_t")) >= 0.0)
	assert_true(w.visible, "the wand is in her hand while casting")
	await wait_physics(45)
	assert_almost(float(foe.get("health").hp), 30.0 - 9.0, 0.01)
	assert_true(w.visible, "still held after the cast")
	GameState.select_hotbar(5)                   # an empty slot
	assert_eq(String(av.call("held_tool")), "")
	await wait_frames(2)
	assert_false(w.visible, "put away when another slot is selected")
