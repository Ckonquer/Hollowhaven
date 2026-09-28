extends "res://tests/test_case.gd"
## Equipment rules, companion combat table and mastery data (docs/CHAPTER_TWO_SPEC.md 4.6 / 4.7 / 5 / 8,
## MP 5.1 / 5.3 / 6.2 / 6.3) and their ItemDB accessors.

const EquipmentData := preload("res://data/equipment.gd")
const CompanionSkillsData := preload("res://data/companion_skills.gd")
const CreaturesData := preload("res://data/creatures.gd")
const MasteryData := preload("res://data/mastery.gd")
const RecipesData := preload("res://data/recipes.gd")
const ItemsData := preload("res://data/items.gd")


func before_each() -> void:
	fresh_state()


# --- equipment -------------------------------------------------------------------------------------------

func test_equipment_rules_and_combination_order() -> void:
	assert_eq(EquipmentData.SLOTS, ["head", "body", "boots", "charm"], "spec 8 slots")
	assert_eq(EquipmentData.REDUCTION_CAP, 0.45)
	assert_eq(EquipmentData.MOVE_CAP, 0.3)
	assert_eq(EquipmentData.BYPASS_ARMOR, [], "nothing silently bypasses armor")
	assert_almost(EquipmentData.combine_reduction([0.2, 0.1]), 0.28, 0.0001, "MP 5.1 example: 20% armor + Pebble 10% = 28%")
	assert_almost(EquipmentData.combine_reduction([0.26, 0.1]), 0.334, 0.0001, "moonsteel + Pebble")
	assert_almost(EquipmentData.combine_reduction([0.26, 0.1, 0.25, 0.2]), 0.45, 0.0001, "capped at 45%")
	assert_almost(EquipmentData.combine_reduction([]), 0.0, 0.0001)
	assert_almost(EquipmentData.combine_reduction([-1.0, 2.0]), 0.45, 0.0001, "inputs are clamped")
	var sum := 0.0
	for s in EquipmentData.PIECE_SHARE:
		sum += float(EquipmentData.PIECE_SHARE[s])
	assert_almost(sum, 1.0, 0.0001, "piece shares cover the whole set")
	var rules := ItemDB.equipment_rules()
	for k in ["slots", "armor_slots", "sets", "reduction_cap", "move_cap", "effects", "piece_share", "bypass_armor", "tiers"]:
		assert_true(rules.has(k), "equipment_rules() has " + k)
	assert_eq(ItemDB.armor_set("nope"), {})
	var e := ItemDB.equipment("ironwood_mail")
	assert_eq(e["slot"], "body")
	assert_almost(float(e["reduction"]), 0.1, 0.0001)
	assert_eq(e["effects"], {}, "defaults merged for armor")
	var c := ItemDB.equipment("swiftstep_charm")
	assert_eq(c["slot"], "charm")
	assert_almost(float(c["reduction"]), 0.0, 0.0001, "charms carry no armor unless stated")
	# movement bonuses of every source together stay inside the cap
	var lumi5 := ItemDB.companion_skill_at("lumi", 5)
	var move_total := float(lumi5["passive"]["move"]) + float(lumi5["signature"]["move"]) + float(c["effects"]["move"])
	assert_true(move_total <= EquipmentData.MOVE_CAP + 0.0001, "Lumi + Glimmerstep + Swiftstep (%.2f) within the move cap" % move_total)


# --- companions ------------------------------------------------------------------------------------------

func test_companion_table_holds_the_master_prompt_numbers() -> void:
	for cid in CreaturesData.CREATURES:
		assert_false(ItemDB.companion_skill(cid).is_empty(), cid + " has combat and support numbers")
	assert_eq(CompanionSkillsData.MOVE_BUFF_CAP, 0.3)
	assert_eq(CompanionSkillsData.REDUCTION_CAP, 0.45)
	assert_eq(CompanionSkillsData.REDUCTION_CAP, EquipmentData.REDUCTION_CAP, "one cap everywhere")
	assert_eq(CompanionSkillsData.MOVE_BUFF_CAP, EquipmentData.MOVE_CAP)
	assert_eq(CompanionSkillsData.PERK_LEVELS, [2, 3, 5])
	var mochi := ItemDB.companion_skill("mochi")
	assert_almost(float(mochi["passive"]["heal_received"]), 0.08, 0.0001)
	assert_eq([mochi["basic"]["kind"], float(mochi["basic"]["damage"]), float(mochi["basic"]["interval"])], ["projectile", 4.0, 2.4])
	assert_eq([mochi["signature"]["id"], float(mochi["signature"]["heal"]), float(mochi["signature"]["duration"]), float(mochi["signature"]["cooldown"])], ["bloomguard", 18.0, 6.0, 25.0])
	var pebble := ItemDB.companion_skill("pebble")
	assert_almost(float(pebble["passive"]["damage_reduction"]), 0.1, 0.0001)
	assert_eq([pebble["basic"]["kind"], float(pebble["basic"]["damage"]), float(pebble["basic"]["interval"])], ["melee", 8.0, 2.4])
	assert_eq([pebble["signature"]["id"], float(pebble["signature"]["shield"]), float(pebble["signature"]["duration"]), float(pebble["signature"]["cooldown"])], ["stoneheart", 25.0, 6.0, 26.0])
	assert_false(bool(pebble["signature"]["stagger_bosses"]), "never stun-locks a boss")
	var lumi := ItemDB.companion_skill("lumi")
	assert_almost(float(lumi["passive"]["move"]), 0.08, 0.0001)
	assert_eq([lumi["basic"]["kind"], float(lumi["basic"]["damage"]), float(lumi["basic"]["interval"])], ["projectile", 6.0, 2.2])
	assert_eq([lumi["signature"]["id"], float(lumi["signature"]["move"]), float(lumi["signature"]["duration"]), float(lumi["signature"]["cooldown"])], ["glimmerstep", 0.12, 4.0, 24.0])
	var pip := ItemDB.companion_skill("pipkin")
	assert_true(bool(pip["optional"]), "Pipkin is optional bonus data")
	assert_eq([float(pip["basic"]["damage"]), pip["signature"]["id"], float(pip["signature"]["cooldown"])], [5.0, "moon_mote", 25.0])
	for cid2 in CompanionSkillsData.SKILLS:
		var s: Dictionary = CompanionSkillsData.SKILLS[cid2]
		assert_true(bool(s["basic"]["requires_los"]), cid2 + " attacks need line of sight")
		assert_true(String(s["signature"]["name"]) != "" and String(s["passive_text"]) != "", cid2 + " texts for the Friends panel")
		for lvl in s["perks"]:
			assert_true(CompanionSkillsData.PERK_LEVELS.has(lvl), "%s perk level %d" % [cid2, lvl])
			assert_true(String(s["perks"][lvl]["text"]) != "", "%s perk %d text" % [cid2, lvl])
	assert_eq(ItemDB.companion_skill("nobody"), {})


func test_bond_perks_resolve_by_level() -> void:
	var m0 := ItemDB.companion_skill_at("mochi", 0)
	assert_eq(float(m0["signature"]["heal"]), 18.0)
	assert_eq(m0["perks_active"], [])
	assert_false(bool(m0["ribbon"]))
	var m2 := ItemDB.companion_skill_at("mochi", 2)
	assert_almost(float(m2["passive"]["heal_received"]), 0.1, 0.0001, "two hearts: 10% healing")
	var m3 := ItemDB.companion_skill_at("mochi", 3)
	assert_eq(int(m3["signature"]["cleanse_slow"]), 1, "three hearts: clears one slow")
	assert_eq(m3["perks_active"], [2, 3])
	var m5 := ItemDB.companion_skill_at("mochi", 5)
	assert_eq(float(m5["signature"]["heal"]), 22.0, "five hearts: Bloomguard heals 22")
	assert_true(bool(m5["ribbon"]))
	assert_true(float(ItemDB.companion_skill_at("pebble", 2)["signature"]["shield"]) > 25.0, "modest shield increase at two hearts")
	assert_eq(int(ItemDB.companion_skill_at("pebble", 3)["signature"]["resist_knockback"]), 1)
	assert_eq(float(ItemDB.companion_skill_at("pebble", 5)["signature"]["shield"]), 32.0)
	assert_almost(float(ItemDB.companion_skill_at("lumi", 2)["passive"]["move"]), 0.1, 0.0001)
	assert_true(float(ItemDB.companion_skill_at("lumi", 3)["signature"]["sprint_stamina_save"]) > 0.0)
	assert_eq(float(ItemDB.companion_skill_at("lumi", 5)["signature"]["duration"]), 6.0)
	# resolving never mutates the shared table
	assert_eq(float(CompanionSkillsData.SKILLS["mochi"]["signature"]["heal"]), 18.0)
	assert_almost(float(CompanionSkillsData.SKILLS["lumi"]["passive"]["move"]), 0.08, 0.0001)
	assert_eq(ItemDB.companion_skill_at("nobody", 5), {})
	var rules := ItemDB.companion_rules()
	assert_eq(rules["modes"], ["assist", "close"])
	assert_eq(float(rules["presence_range"]), 25.0)
	for t in [1, 2, 3, 4]:
		assert_true(float(rules["gear_tier_damage"][t]) >= 1.0 and float(rules["gear_tier_damage"][t]) <= 1.5, "modest gear-tier bonus")


# --- mastery ---------------------------------------------------------------------------------------------

func test_mastery_tables_are_consistent_and_exploit_resistant() -> void:
	assert_eq(MasteryData.TRACKS, ["gathering", "hearthcraft", "wayfinding"])
	assert_eq(MasteryData.RANK_XP.size(), MasteryData.MAX_RANK + 1)
	assert_eq(MasteryData.MAX_RANK, 5)
	assert_eq(int(MasteryData.RANK_XP[0]), 0)
	for i in range(1, MasteryData.RANK_XP.size()):
		assert_true(int(MasteryData.RANK_XP[i]) > int(MasteryData.RANK_XP[i - 1]), "rank thresholds increase")
	for track in MasteryData.TRACKS:
		var rules: Dictionary = MasteryData.XP[track]
		assert_false(rules.is_empty(), track + " xp rules")
		for rule in rules:
			var r: Dictionary = rules[rule]
			assert_true(int(r["xp"]) > 0, "%s.%s xp" % [track, rule])
			assert_true(r.has("once_per") != r.has("daily_cap"), "%s.%s is either once-per-id or daily-capped" % [track, rule])
			if r.has("daily_cap"):
				assert_true(int(r["daily_cap"]) >= int(r["xp"]) and int(r["daily_cap"]) <= 40, "%s.%s modest daily cap" % [track, rule])
		for rank in range(1, MasteryData.MAX_RANK + 1):
			assert_false(ItemDB.mastery_reward(track, rank).is_empty(), "%s rank %d reward" % [track, rank])
			assert_true(String(ItemDB.mastery_reward(track, rank).get("text", "")) != "", "%s rank %d visible text" % [track, rank])
		var credit_max := 0
		for src in MasteryData.LEGACY_CREDIT[track]:
			credit_max += int(src.get("cap", src.get("xp", 0)))
		assert_true(credit_max <= MasteryData.LEGACY_CAP_XP, track + " legacy credit is capped")
	assert_true(MasteryData.LEGACY_CAP_XP < int(MasteryData.RANK_XP[2]), "legacy credit stays conservative (below rank 2)")
	for bad in ["dismantle", "rebuild_same_structure", "move_items_between_chests", "load_save", "equip_or_unequip"]:
		assert_true(MasteryData.NO_XP.has(bad), "no xp for " + bad)
	assert_eq(MasteryData.XP["hearthcraft"]["first_structure"]["once_per"], "structure", "re-placing a structure never repeats xp")
	# mastery-gated recipes and hearthcraft rewards describe the same thing
	var gated := {}
	for rid in RecipesData.RECIPES:
		var rec: Dictionary = RecipesData.RECIPES[rid]
		if rec.has("mastery"):
			gated[rid] = int(rec["mastery"]["hearthcraft"])
	var rewarded := {}
	for rank2 in MasteryData.REWARDS["hearthcraft"]:
		for rr in MasteryData.REWARDS["hearthcraft"][rank2].get("recipes", []):
			rewarded[rr] = int(rank2)
	assert_eq(gated, rewarded, "recipe mastery gates match the hearthcraft rank rewards")
	# combined non-combat bonuses stay modest
	var best_gather := 0.0
	for rank3 in MasteryData.REWARDS["gathering"]:
		best_gather = maxf(best_gather, float(MasteryData.REWARDS["gathering"][rank3].get("gather_power", 0.0)))
	var charm := float(ItemsData.ITEMS["gatherers_charm"]["effects"]["gather"])
	assert_true(best_gather + charm <= MasteryData.GATHER_BONUS_CAP, "mastery + charm within the gather cap")


func test_mastery_rank_accessors() -> void:
	assert_eq(ItemDB.mastery_rank_for_xp(0), 0)
	assert_eq(ItemDB.mastery_rank_for_xp(39), 0)
	assert_eq(ItemDB.mastery_rank_for_xp(40), 1)
	assert_eq(ItemDB.mastery_rank_for_xp(600), 5)
	assert_eq(ItemDB.mastery_rank_for_xp(99999), 5)
	assert_eq(ItemDB.mastery_rank_for_xp(-5), 0)
	assert_eq(ItemDB.mastery_tracks(), MasteryData.TRACKS)
	assert_false(ItemDB.mastery_xp_rules("wayfinding").is_empty())
	assert_eq(ItemDB.mastery_reward("nope", 1), {})
	var t := ItemDB.mastery_tables()
	for k in ["tracks", "rank_xp", "max_rank", "xp", "rewards", "no_xp", "legacy_credit", "legacy_cap_xp", "gather_bonus_cap", "yield_chance_cap"]:
		assert_true(t.has(k), "mastery_tables() has " + k)
	# mastery-gated recipes: unknown at rank 0, known once the rank is reached (when GameState has mastery yet)
	assert_false(ItemDB.recipe_known("gothic_trim"), "rank 0: the ornate trim is not known")
	assert_true(ItemDB.recipe_known("wood_stairs"), "ungated recipes are unaffected")
	if "mastery" in GameState:
		var saved: Variant = GameState.get("mastery")
		var m: Dictionary = (saved as Dictionary).duplicate(true) if saved is Dictionary else {}
		m["hearthcraft"] = int(MasteryData.RANK_XP[2])
		GameState.set("mastery", m)
		assert_eq(ItemDB.mastery_rank("hearthcraft"), 2)
		assert_true(ItemDB.recipe_known("gothic_trim"), "rank 2 unlocks the trim")
		assert_true(ItemDB.recipe_known("crescent_window"))
		GameState.set("mastery", saved)
	else:
		assert_eq(ItemDB.mastery_rank("hearthcraft"), 0, "no mastery state yet -> rank 0")
