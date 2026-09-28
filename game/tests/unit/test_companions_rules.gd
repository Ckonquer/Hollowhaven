extends "res://tests/test_case.gd"
## Pure companion combat rules (companion_logic.gd, no scene): basic-attack target choice, autocast conditions,
## the cooldown timeline clamp, heal-over-time slices, the next perk, courage.

const Logic := preload("res://src/companions/companion_logic.gd")
const SkillsData := preload("res://data/companion_skills.gd")

const ME := Vector3(0, 0, 0)
const KRYSTAL := Vector3(0, 0, 2)


func _c(pos: Vector3, engaged: bool = true, valid: bool = true, attacking: bool = false) -> Dictionary:
	return {"pos": pos, "engaged": engaged, "valid": valid, "attacking": attacking}


func _opts(extra: Dictionary = {}) -> Dictionary:
	var o := {"range": 9.0, "max_dy": 3.0, "engage_radius": 12.0, "close": false, "close_radius": 4.0, "melee": false}
	o.merge(extra, true)
	return o


func test_target_never_peaceful_invalid_or_out_of_reach() -> void:
	var cands := [
		_c(Vector3(0, 0, -3), false),              # peaceful (not fighting Krystal)
		_c(Vector3(1, 0, -3), true, false),        # invulnerable / refusing / dummy
		_c(Vector3(0, 5, -2)),                     # far above (ceiling)
		_c(Vector3(0, 0, 20)),                     # beyond the engage radius from Krystal
		_c(Vector3(-2, 0, -11)),                   # within engage radius of Krystal? no: 13 m
	]
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts()), -1, "nothing valid")
	cands.append(_c(Vector3(2, 0, -2)))
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts()), 5, "the one real fight")


func test_target_prefers_the_one_attacking_krystal() -> void:
	var cands := [_c(Vector3(0, 0, 4)), _c(Vector3(3, 0, 5), true, true, true)]
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts()), 1, "the enemy striking at her first")
	cands[1]["attacking"] = false
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts()), 0, "else the nearest to her")


func test_projectile_range_and_melee_walks() -> void:
	var cands := [_c(Vector3(0, 0, 11))]        # 9 m from Krystal, 11 m from the pet
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts()), -1, "a projectile needs it within its range")
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts({"melee": true, "range": 1.8, "max_dy": 1.6})), 0, "a melee pet walks there")


func test_stay_close_only_answers_enemies_at_krystals_side() -> void:
	var cands := [_c(Vector3(0, 0, 8))]         # 6 m from Krystal
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts({"close": true})), -1)
	cands.append(_c(Vector3(1, 0, 3.5)))
	assert_eq(Logic.pick_attack_target(ME, KRYSTAL, cands, _opts({"close": true})), 1)


func test_autocast_conditions() -> void:
	var bloom: Dictionary = SkillsData.SKILLS["mochi"]["signature"]
	assert_false(Logic.should_autocast(bloom, {"hp_ratio": 0.9, "missing_hp": 10.0}), "a scratch")
	assert_false(Logic.should_autocast(bloom, {"hp_ratio": 0.55, "missing_hp": 10.0}), "would mostly overheal")
	assert_true(Logic.should_autocast(bloom, {"hp_ratio": 0.5, "missing_hp": 50.0}), "meaningfully hurt")
	assert_false(Logic.should_autocast(bloom, {"hp_ratio": 0.5, "missing_hp": 50.0, "hot_active": true}), "already healing")
	var stone: Dictionary = SkillsData.SKILLS["pebble"]["signature"]
	assert_false(Logic.should_autocast(stone, {"threats_near": 0, "attacking_near": true}), "nothing near")
	assert_true(Logic.should_autocast(stone, {"threats_near": 1, "attacking_near": true}), "a strike is coming")
	assert_false(Logic.should_autocast(stone, {"threats_near": 1, "attacking_near": true, "shield_active": true}), "already shielded")
	assert_true(Logic.should_autocast(stone, {"threats_near": 2, "hp_ratio": 0.4}), "low and surrounded")
	var glim: Dictionary = SkillsData.SKILLS["lumi"]["signature"]
	assert_false(Logic.should_autocast(glim, {"threats_near": 0, "shadow_near": true}))
	assert_true(Logic.should_autocast(glim, {"threats_near": 1, "shadow_near": true}), "a shadow to expose")
	assert_true(Logic.should_autocast(glim, {"threats_near": 1, "hp_ratio": 0.3}), "a burst to get away")
	assert_false(Logic.should_autocast(glim, {"threats_near": 1, "hp_ratio": 0.9}))


func test_cooldown_timeline_is_clamped() -> void:
	assert_almost(Logic.cooldown_remaining(125.0, 100.0, 25.0), 25.0)
	assert_almost(Logic.cooldown_remaining(125.0, 110.0, 25.0), 15.0)
	assert_almost(Logic.cooldown_remaining(125.0, 130.0, 25.0), 0.0, 0.001, "ready")
	assert_almost(Logic.cooldown_remaining(9000.0, 100.0, 25.0), 25.0, 0.001, "a damaged / rewound save never locks it longer")


func test_heal_over_time_slices_add_up() -> void:
	var total := 0.0
	var prev := 0.0
	for t in [0.5, 0.7, 2.0, 3.3, 5.9, 6.0, 7.0]:
		total += Logic.hot_amount(18.0, 6.0, prev, float(t))
		prev = float(t)
	assert_almost(total, 18.0, 0.0001, "any tick pattern adds up to exactly the total")
	assert_almost(Logic.hot_amount(18.0, 6.0, 0.0, 3.0), 9.0)


func test_next_perk_and_courage() -> void:
	var perks: Dictionary = SkillsData.SKILLS["mochi"]["perks"]
	assert_eq(int(Logic.next_perk(perks, SkillsData.PERK_LEVELS, 0)["level"]), 2)
	assert_eq(int(Logic.next_perk(perks, SkillsData.PERK_LEVELS, 2)["level"]), 3)
	assert_true(String(Logic.next_perk(perks, SkillsData.PERK_LEVELS, 2, true)["text"]).contains("root"), "arachnophobia text")
	assert_false(String(Logic.next_perk(perks, SkillsData.PERK_LEVELS, 2, true)["text"]).contains("web"))
	assert_true(Logic.next_perk(perks, SkillsData.PERK_LEVELS, 5).is_empty())
	assert_false(Logic.dares_underground({"enters_below": false}, false), "timid Mochi")
	assert_true(Logic.dares_underground({"enters_below": false}, true), "Mochi with courage")
	assert_true(Logic.dares_underground({"enters_below": true}, false), "Pebble and Lumi")
