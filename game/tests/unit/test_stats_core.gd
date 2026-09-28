extends "res://tests/test_case.gd"
## Stats layer (src/core/stats.gd; spec section 5, MP 5.1 / 6.2 / 16): reduction math (pieces add, sources
## multiply, cap), companion presence, movement cap and slows, healing, stamina, gathering, food buff
## families, legacy weapon numbers, tool/wand selection rules and recompute-on-load (nothing accumulates).

const Stats := preload("res://src/core/stats.gd")
const EquipmentData := preload("res://data/equipment.gd")
const CreaturesData := preload("res://data/creatures.gd")
const MasteryData := preload("res://data/mastery.gd")

var _saved_player: Node3D = null
var _saved_nodes: Dictionary = {}
var _fake_player: Node3D = null
var _fake_comp: Node3D = null


func before_each() -> void:
	fresh_state()
	_saved_player = Game.player
	_saved_nodes = Game.companion_nodes.duplicate()


func after_each() -> void:
	Game.player = _saved_player
	Game.companion_nodes = _saved_nodes
	for c in get_children():
		c.queue_free()
	_fake_player = null
	_fake_comp = null
	await wait_frames(1)


## Makes `id` the befriended follower at `bond` hearts, standing `dist` m from a stand-in Krystal.
func _companion(id: String, bond: int, dist: float = 3.0) -> void:
	_fake_player = Node3D.new()
	add_child(_fake_player)
	_fake_comp = Node3D.new()
	add_child(_fake_comp)
	_fake_player.global_position = Vector3(40, 0, 40)
	_fake_comp.global_position = Vector3(40 + dist, 0, 40)
	Game.player = _fake_player
	Game.companion_nodes = {id: _fake_comp}
	var rec := GameState.companion(id)
	rec["befriended"] = true
	rec["assignment"] = "follow"
	rec["bond_xp"] = int(CreaturesData.BOND_XP_PER_LEVEL[bond])
	GameState.active_companion = id


func _wear(ids: Array) -> void:
	for id in ids:
		GameState.give_item(String(id), 1)
		assert_true(GameState.equip(String(id)), "equip %s (%s)" % [id, GameState.last_equip_error])


# --- Reduction -------------------------------------------------------------------------------------------

func test_armor_pieces_add_within_armor() -> void:
	assert_almost(Stats.damage_reduction(), 0.0, 0.0001, "nothing worn")
	_wear(["ironwood_helm"])
	assert_almost(Stats.armor_reduction(), 0.05, 0.0001)
	_wear(["ironwood_mail", "ironwood_boots"])
	assert_almost(Stats.armor_reduction(), 0.2, 0.0001, "ironwood set = 5 + 10 + 5")
	assert_almost(Stats.damage_reduction(), 0.2, 0.0001, "pieces ADD inside armor")
	for set_id in EquipmentData.SETS:
		var sd: Dictionary = EquipmentData.SETS[set_id]
		var sum := 0.0
		for slot in sd["pieces"]:
			sum += float(ItemDB.item(String(sd["pieces"][slot]))["reduction"])
		assert_almost(sum, float(sd["total"]), 0.0001, "%s pieces add up to the set total" % set_id)


func test_mp_example_armor_and_pebble_multiply_to_28_percent() -> void:
	assert_almost(Stats.combine(0.2, 0.1), 0.28, 0.0001, "1 - 0.8 x 0.9")
	_wear(["ironwood_helm", "ironwood_mail", "ironwood_boots"])
	_companion("pebble", 0)
	assert_eq(Stats.present_companion(), "pebble")
	assert_almost(Stats.damage_reduction(), 0.28, 0.0001, "20% armor + Pebble 10% = 28%, not 30%")
	assert_almost(Stats.mitigate(50.0), 36.0, 0.001)


func test_reduction_cap_is_45_percent() -> void:
	assert_almost(Stats.combine(0.26, 0.1, 0.3), EquipmentData.REDUCTION_CAP, 0.0001, "capped")
	assert_almost(Stats.combine(0.9, 0.9, 0.9, 0.9), 0.45, 0.0001)
	assert_almost(Stats.combine(0.26, 0.1), 0.334, 0.0001, "best real combination stays under the cap")
	_wear(["moonsteel_helm", "moonsteel_mail", "moonsteel_boots"])
	_companion("pebble", 5)
	assert_almost(Stats.damage_reduction(), 0.334, 0.0001, "moonsteel + Pebble (bond perks never raise the passive)")
	assert_true(Stats.damage_reduction() <= EquipmentData.REDUCTION_CAP)


func test_companion_support_needs_presence() -> void:
	_wear(["ironwood_helm", "ironwood_mail", "ironwood_boots"])
	_companion("pebble", 3, 30.0)
	assert_eq(Stats.present_companion(), "", "30 m away: not present")
	assert_almost(Stats.damage_reduction(), 0.2, 0.0001, "no Pebble bonus from afar")
	_fake_comp.global_position = _fake_player.global_position + Vector3(10, 0, 0)
	assert_almost(Stats.damage_reduction(), 0.28, 0.0001, "within 25 m")
	GameState.active_companion = ""
	assert_almost(Stats.damage_reduction(), 0.2, 0.0001, "not the active follower: no support")


# --- Movement ---------------------------------------------------------------------------------------------

func test_move_bonus_sources_and_cap() -> void:
	assert_almost(Stats.move_mult(), 1.0, 0.0001, "legacy: no bonus")
	_companion("lumi", 0)
	assert_almost(Stats.move_mult(), 1.08, 0.0001, "Lumi +8%")
	GameState.companion("lumi")["bond_xp"] = int(CreaturesData.BOND_XP_PER_LEVEL[2])
	assert_almost(Stats.move_mult(), 1.10, 0.0001, "2 hearts: +10%")
	GameState.add_buff("glimmerstep", 0.12, 4.0)
	assert_almost(Stats.move_mult(), 1.22, 0.0001, "Glimmerstep adds 12%")
	_wear(["swiftstep_charm"])
	assert_almost(Stats.move_mult(), 1.26, 0.0001, "Swiftstep adds 4%")
	GameState.add_buff("glimmerstep", 0.5, 4.0)
	assert_almost(Stats.move_mult(), 1.0 + EquipmentData.MOVE_CAP, 0.0001, "capped at +30%")


func test_slow_is_bounded_and_resisted() -> void:
	GameState.add_buff("slow", 0.8, 2.0)
	assert_almost(Stats.slow_mult(), 0.8, 0.0001)
	GameState.add_buff("slow", 0.1, 2.0)
	assert_almost(Stats.slow_mult(), Stats.SLOW_FLOOR, 0.0001, "never slower than the floor")
	GameState.add_buff("slow", 0.8, 2.0)
	GameState.add_buff("slow_resist", 0.5, 90.0)
	assert_almost(Stats.slow_mult(), 0.9, 0.0001, "Moonpetal tea halves the slow")
	_companion("lumi", 0)
	assert_almost(Stats.move_mult(), 1.08 * 0.9, 0.0001, "bonus and slow combine")


# --- Healing, stamina, gathering -------------------------------------------------------------------------------

func test_heal_mult_from_mochi_and_charm() -> void:
	assert_almost(Stats.heal_mult(), 1.0, 0.0001)
	_companion("mochi", 0)
	assert_almost(Stats.heal_mult(), 1.08, 0.0001, "Mochi +8%")
	GameState.companion("mochi")["bond_xp"] = int(CreaturesData.BOND_XP_PER_LEVEL[2])
	assert_almost(Stats.heal_mult(), 1.10, 0.0001, "2 hearts: +10%")
	_wear(["kindling_charm"])
	assert_almost(Stats.heal_mult(), 1.20, 0.0001, "Kindling Charm adds 10%")
	assert_true(Stats.heal_mult() <= 1.0 + float(EquipmentData.EFFECTS["heal_received"]["cap"]) + 0.0001)


func test_stamina_cost_multipliers() -> void:
	for a in ["", "sprint", "dodge", "swing", "wand"]:
		assert_almost(Stats.stamina_cost_mult(a), 1.0, 0.0001, "legacy cost for %s" % a)
	_wear(["swiftstep_charm"])
	assert_almost(Stats.stamina_cost_mult("dodge"), 0.88, 0.0001, "Swiftstep -12%")
	assert_almost(Stats.stamina_cost_mult("sprint"), 0.88, 0.0001)
	GameState.add_buff("sprint_saver", 0.5, 4.0)
	assert_almost(Stats.stamina_cost_mult("sprint"), 0.44, 0.0001, "Lumi's sprint saver halves sprint costs only")
	assert_almost(Stats.stamina_cost_mult("dodge"), 0.88, 0.0001)
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[5])
	assert_almost(Stats.stamina_cost_mult("sprint"), (1.0 - 0.25) * 0.5, 0.0001, "charm + mastery capped at 25%")


func test_gather_bonus_charm_mastery_and_cap() -> void:
	assert_almost(Stats.gather_bonus(), 0.0, 0.0001)
	_wear(["gatherers_charm"])
	assert_almost(Stats.gather_bonus(), 0.1, 0.0001, "Gatherer's Charm")
	GameState.mastery["gathering"] = int(MasteryData.RANK_XP[1])
	assert_almost(Stats.gather_bonus(), 0.15, 0.0001, "+ rank 1 (5%)")
	GameState.mastery["gathering"] = int(MasteryData.RANK_XP[5])
	assert_almost(Stats.gather_bonus(), 0.2, 0.0001, "rank values are totals (10%), not added per rank")
	assert_almost(Stats.harvest_power("stone_pickaxe"), 1.2, 0.0001)
	assert_almost(Stats.bonus_yield_chance(), 0.1, 0.0001)
	assert_true(Stats.gather_bonus() <= MasteryData.GATHER_BONUS_CAP)


# --- Food families ------------------------------------------------------------------------------------------

func test_food_buff_family_replaces_or_refreshes_never_stacks() -> void:
	var r: Dictionary = Stats.apply_food_buff("hearty_stew")
	assert_eq(String(r["result"]), "new")
	assert_almost(GameState.buff_mult("stamina_regen"), 1.6, 0.0001, "legacy stew value")
	assert_almost(float(GameState.buffs["stamina_regen"]["remaining"]), 120.0, 0.001)
	assert_eq(String(GameState.buffs["stamina_regen"].get("family", "")), "stamina", "family recorded")
	GameState.buffs["stamina_regen"]["remaining"] = 10.0
	r = Stats.apply_food_buff("roseberry_tart")
	assert_eq(String(r["result"]), "refreshed", "a weaker food of the family only refreshes")
	assert_almost(GameState.buff_mult("stamina_regen"), 1.6, 0.0001, "the stronger value stays")
	assert_almost(float(GameState.buffs["stamina_regen"]["remaining"]), 60.0, 0.001, "time refreshed up to the tart's 60 s")
	r = Stats.apply_food_buff("roseberry_tart")
	assert_almost(float(GameState.buffs["stamina_regen"]["remaining"]), 60.0, 0.001, "eating again never stacks time")
	GameState.buffs.erase("stamina_regen")
	Stats.apply_food_buff("roseberry_tart")
	r = Stats.apply_food_buff("lanternwake_platter")
	assert_eq(String(r["result"]), "replaced", "a stronger food replaces")
	assert_almost(GameState.buff_mult("stamina_regen"), 1.5, 0.0001)
	assert_almost(float(GameState.buffs["stamina_regen"]["remaining"]), 150.0, 0.001)
	assert_eq(GameState.buffs.size(), 1, "one buff per family")
	# "steady": a LOWER slow_resist is stronger
	GameState.add_buff("slow_resist", 0.7, 20.0)
	r = Stats.apply_food_buff("moonpetal_tea")
	assert_eq(String(r["result"]), "replaced")
	assert_almost(GameState.buff_mult("slow_resist"), 0.5, 0.0001)
	assert_eq(String(Stats.apply_food_buff("berries")["result"]), "none", "foods without a buff change nothing")


# --- Weapons & tools ---------------------------------------------------------------------------------------------

func test_legacy_weapon_numbers() -> void:
	assert_almost(Stats.melee_damage(""), 5.0, 0.0001, "hands")
	assert_almost(Stats.melee_damage("stone_axe"), 9.0, 0.0001)
	assert_almost(Stats.melee_damage("stone_pickaxe"), 9.0, 0.0001)
	assert_almost(Stats.melee_damage("copper_sword"), 18.0, 0.0001)
	assert_almost(Stats.melee_damage("ironwood_sword"), 25.0, 0.0001)
	assert_almost(Stats.melee_damage("moonsteel_sword"), 34.0, 0.0001)
	assert_almost(Stats.melee_reach(""), 1.8, 0.0001)
	assert_almost(Stats.melee_reach("copper_sword"), 2.5, 0.0001)
	assert_almost(Stats.melee_reach("stone_axe"), 2.2, 0.0001)


func test_harvesting_tools_never_out_damage_swords() -> void:
	var copper := Stats.melee_damage("copper_sword")
	for id in ItemDB.items_in_category("tool"):
		assert_true(Stats.melee_damage(String(id)) < copper, "%s (%.0f) stays below the Copper Sword" % [id, Stats.melee_damage(String(id))])
	GameState.give_item("moonsteel_axe", 1)
	GameState.give_item("copper_sword", 1)
	assert_eq(Stats.best_melee_weapon(), "copper_sword", "a better axe never replaces the sword in combat")


func test_best_tool_highest_power_and_tier_gate() -> void:
	assert_eq(Stats.best_tool("pickaxe"), "")
	GameState.give_item("stone_pickaxe", 1)
	GameState.give_item("copper_pickaxe", 1)
	assert_eq(Stats.best_tool("pickaxe"), "copper_pickaxe")
	assert_eq(Stats.best_tool("pickaxe", 3), "", "no Ironwood pick yet")
	GameState.give_item("ironwood_pickaxe", 1)
	assert_eq(Stats.best_tool("pickaxe"), "ironwood_pickaxe")
	assert_eq(Stats.best_tool("pickaxe", 3), "ironwood_pickaxe")
	assert_eq(Stats.best_tool("axe"), "", "no axe")
	assert_eq(Stats.best_tool("hand"), "")
	assert_eq(Stats.best_tool("pickaxe"), GameState.best_tool("pickaxe"), "agrees with the legacy picker")


func test_wand_is_never_the_melee_pick() -> void:
	GameState.give_item("sparkseed_wand", 1)
	assert_eq(Stats.best_melee_weapon(), "", "a wand alone means bare hands in melee")
	assert_eq(GameState.best_weapon(), "")
	GameState.give_item("stone_axe", 1)
	assert_eq(Stats.best_melee_weapon(), "stone_axe")
	assert_eq(Stats.best_tool("axe"), "stone_axe", "never mines or chops with the wand")
	assert_eq(Stats.best_wand(), "sparkseed_wand")


func test_wand_sustained_damage_below_same_tier_melee() -> void:
	for wid in ItemDB.items_in_category("wand"):
		var tier: int = ItemDB.item_tier(String(wid))
		for sid in ItemDB.items_in_category("weapon"):
			if ItemDB.item_tier(String(sid)) == tier:
				assert_true(Stats.wand_dps(String(wid)) < Stats.melee_dps(String(sid)),
					"%s %.1f dps < %s %.1f dps" % [wid, Stats.wand_dps(String(wid)), sid, Stats.melee_dps(String(sid))])
		var w: Dictionary = Stats.wand_stats(String(wid))
		assert_true(float(w["range"]) > 0.0 and float(w["range"]) <= 20.0, "finite range")
		assert_true(float(w["stamina"]) > 0.0, "shares stamina")
		assert_true(float(w["cooldown"]) > 0.0, "has a cooldown")
	assert_almost(Stats.wand_dps("sparkseed_wand"), 9.0 / 0.8, 0.001)
	assert_almost(Stats.melee_dps("copper_sword"), 36.0, 0.001)


func test_companion_gear_tier_mult_is_stable() -> void:
	assert_eq(Stats.best_weapon_tier(), 1)
	GameState.give_item("copper_sword", 1)
	assert_eq(Stats.best_weapon_tier(), 2)
	GameState.give_item("moonsteel_axe", 1)
	assert_eq(Stats.best_weapon_tier(), 2, "tools don't count")
	assert_almost(Stats.companion_damage_mult(), 1.1, 0.0001)


# --- Recompute on load ------------------------------------------------------------------------------------------

func test_stats_recompute_on_load_without_accumulating() -> void:
	_wear(["ironwood_helm", "ironwood_mail", "ironwood_boots", "swiftstep_charm"])
	GameState.add_buff("stamina_regen", 1.6, 100.0)
	var red := Stats.damage_reduction()
	var mv := Stats.move_mult()
	var sc := Stats.stamina_cost_mult("dodge")
	var inv_before := _inv_sig()
	assert_true(SaveSystem.save_game(true), "saved")
	for i in 2:
		GameState.reset()
		assert_true(SaveSystem.load_game(), "loaded %d" % i)
		assert_almost(Stats.damage_reduction(), red, 0.0001, "reduction after load %d" % i)
		assert_almost(Stats.move_mult(), mv, 0.0001, "move after load %d" % i)
		assert_almost(Stats.stamina_cost_mult("dodge"), sc, 0.0001)
		assert_eq(GameState.equipped("body"), "ironwood_mail")
		assert_eq(GameState.equipped("charm"), "swiftstep_charm")
		assert_eq(_inv_sig(), inv_before, "backpack unchanged by loading")
		assert_almost(float(GameState.player["max_hp"]), 100.0, 0.0001, "the saved max stays the base 100")
		assert_almost(GameState.buff_mult("stamina_regen"), 1.6, 0.0001, "buffs are not re-applied")
		assert_eq(GameState.buffs.size(), 1)
		assert_true(SaveSystem.save_game(true), "saved again %d" % i)
	assert_almost(Stats.effective_max_hp(), 100.0, 0.0001)


func _inv_sig() -> String:
	var parts: PackedStringArray = []
	for i in GameState.inventory.size:
		var st: Variant = GameState.inventory.get_slot(i)
		parts.append("-" if st == null else "%s:%d" % [String(st["id"]), int(st["count"])])
	return ",".join(parts)


# --- Readable rows -------------------------------------------------------------------------------------------------

func _row(id: String) -> Dictionary:
	for r in Stats.stat_rows():
		if String(r["id"]) == id:
			return r
	return {}


func test_stat_rows_show_numbers_and_sources() -> void:
	assert_eq(String(_row("damage")["value"]), "5", "bare hands")
	assert_eq(String(_row("protection")["value"]), "0%")
	assert_true(_row("wand").is_empty(), "no wand row without a wand")
	GameState.give_item("copper_sword", 1)
	GameState.give_item("sparkseed_wand", 1)
	_wear(["ironwood_helm", "ironwood_mail", "ironwood_boots", "swiftstep_charm"])
	_companion("pebble", 2)
	assert_eq(String(_row("damage")["value"]), "18")
	assert_true(String(_row("damage")["detail"]).contains("Copper Sword"))
	assert_eq(String(_row("wand")["value"]), "9")
	assert_eq(String(_row("protection")["value"]), "28%")
	assert_true(String(_row("protection")["detail"]).contains("Armor 20%"), String(_row("protection")["detail"]))
	assert_true(String(_row("protection")["detail"]).contains("Pebble 10%"), String(_row("protection")["detail"]))
	assert_eq(String(_row("speed")["value"]), "+4%")
	assert_true(String(_row("speed")["detail"]).contains("Swiftstep"))
	assert_eq(String(_row("stamina")["value"]), "-12%")
	var lines: Array = Stats.companion_lines()
	assert_true(String(lines[0]).contains("Pebble") and String(lines[0]).contains("with you"), str(lines))
	assert_true(" ".join(PackedStringArray(lines)).contains("10% less damage"), str(lines))
