extends "res://tests/test_case.gd"
## Mastery (MP 5.3, spec 4.7 / 9): three tracks from data/mastery.gd, first-time kinds deduped, repeats capped per
## in-game day, no xp for dismantle/rebuild, chest shuffling, loading, re-equipping or self-heals, rank-up toast,
## small effects for Stats, and a conservative legacy credit applied exactly once (recorded).

const Mastery := preload("res://src/core/mastery.gd")
const MasteryData := preload("res://data/mastery.gd")
const Crafting := preload("res://src/crafting/crafting.gd")
const Furnace := preload("res://src/crafting/furnace.gd")

var _toasts: Array = []
var _changes: Array = []
var _was_listening := false


func before_each() -> void:
	fresh_state()
	_toasts = []
	_changes = []
	_was_listening = Mastery.is_listening()
	Mastery.init()
	Events.notify.connect(_on_notify)
	Events.mastery_changed.connect(_on_changed)


func after_each() -> void:
	Events.notify.disconnect(_on_notify)
	Events.mastery_changed.disconnect(_on_changed)
	if not _was_listening:
		Mastery.shutdown()   # never leak listeners into other suites


func _on_notify(text: String, _kind: String) -> void:
	_toasts.append(text)


func _on_changed(track: String, xp: int, rank: int) -> void:
	_changes.append([track, xp, rank])


func _rule(track: String, rule: String) -> Dictionary:
	return MasteryData.XP[track][rule]


func test_first_time_kinds_are_deduped() -> void:
	var xp := int(_rule("hearthcraft", "first_recipe")["xp"])
	assert_eq(Mastery.award("hearthcraft", "first_recipe:stone_axe"), xp)
	assert_eq(Mastery.award("hearthcraft", "first_recipe:stone_axe"), 0, "same recipe twice")
	assert_eq(Mastery.award("hearthcraft", "first_recipe"), 0, "a once-per rule needs an id")
	assert_eq(Mastery.award("hearthcraft", "first_recipe:stone_pickaxe"), xp)
	assert_eq(Mastery.xp("hearthcraft"), xp * 2)
	assert_true(Mastery.has_seen("hearthcraft", "first_recipe:stone_axe"))
	assert_eq(Mastery.award("nope", "first_recipe:x"), 0)
	for rule in MasteryData.NO_XP:
		assert_eq(Mastery.award("gathering", String(rule) + ":x", 50), 0, String(rule) + " never gives xp")


func test_repeats_are_capped_per_in_game_day() -> void:
	var cap := int(_rule("gathering", "harvest")["daily_cap"])
	var total := 0
	for i in cap + 20:
		total += Mastery.award("gathering", "harvest")
	assert_eq(total, cap, "capped at %d today" % cap)
	assert_eq(Mastery.daily_used("gathering", "harvest"), cap)
	# The cap survives save / load (no reset by reloading).
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(Mastery.award("gathering", "harvest"), 0, "still capped after a load")
	GameState.total_minutes += GameState.MINUTES_PER_DAY
	assert_eq(Mastery.award("gathering", "harvest"), 1, "a new day")
	assert_eq(Mastery.xp("gathering"), cap + 1)


func test_rank_up_toasts_and_signals() -> void:
	var need := int(MasteryData.RANK_XP[1])
	var n := 0
	var i := 0
	while Mastery.xp("hearthcraft") < need and i < 100:
		n += Mastery.award("hearthcraft", "first_structure:piece_%d" % i)
		i += 1
	assert_eq(Mastery.rank("hearthcraft"), 1)
	var ups := _toasts.filter(func(t: String) -> bool: return t.contains("Hearthcraft mastery rank 1"))
	assert_eq(ups.size(), 1, "one rank-up toast")
	assert_true(String(ups[0]).contains(String(MasteryData.REWARDS["hearthcraft"][1]["text"])))
	assert_true(_changes.size() >= 1)
	assert_eq(_changes.back()[0], "hearthcraft")
	var p := Mastery.progress("hearthcraft")
	assert_eq(int(p["rank"]), 1)
	assert_eq(int(p["next_xp"]), int(MasteryData.RANK_XP[2]))
	# Rank 1 hearthcraft unlocks its decorative recipe (never a story recipe).
	assert_true(Crafting.known_recipes().has("crescent_window"))


func test_effects_follow_rank_rewards_from_data() -> void:
	assert_almost(Mastery.gather_power(), 0.0)
	assert_almost(Mastery.station_time_mult(), 1.0)
	GameState.mastery["gathering"] = int(MasteryData.RANK_XP[3])
	assert_almost(Mastery.gather_power(), float(MasteryData.REWARDS["gathering"][3]["gather_power"]), 0.0001, "rank 3 value replaces rank 1")
	assert_almost(Mastery.bonus_yield_chance(), float(MasteryData.REWARDS["gathering"][2]["bonus_yield_chance"]))
	GameState.mastery["hearthcraft"] = int(MasteryData.RANK_XP[5])
	assert_eq(Mastery.furnace_queue_bonus(), 1)
	assert_almost(Mastery.station_time_mult(), 0.85)
	assert_almost(Mastery.meal_buff_bonus(), 0.15)
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[5])
	assert_almost(Mastery.sprint_stamina_save(), 0.15)
	assert_true(Mastery.gather_power() + 0.1 <= Mastery.gather_bonus_cap() + 0.0001, "room for a charm under the cap")


func test_legacy_credit_is_conservative_and_applied_once() -> void:
	GameState.counters["trees_felled"] = 100
	GameState.counters["structures_built"] = 12
	GameState.counters["crops_harvested"] = 3
	GameState.stats["items_crafted"] = 40
	GameState.flags["mine_opened"] = true
	GameState.flags["chapter_one_complete"] = true
	GameState.lore = ["a", "b"]
	var preview := Mastery.legacy_credit_preview()
	assert_eq(int(preview["gathering"]), 40 + 12, "trees capped at 40 + mine")
	assert_eq(int(preview["hearthcraft"]), 12 + 6 + 20, "structures + crops + crafted (capped)")
	assert_eq(int(preview["wayfinding"]), 20 + 30)
	for t in preview:
		assert_true(int(preview[t]) <= MasteryData.LEGACY_CAP_XP)
	var added := Mastery.apply_legacy_credit()
	assert_eq(added, preview)
	assert_true(Mastery.legacy_applied())
	assert_eq(Mastery.xp("gathering"), 52)
	assert_eq(Mastery.apply_legacy_credit(), {}, "never twice")
	GameState.counters["trees_felled"] = 500
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	Events.game_loaded.emit()
	Events.area_loaded.emit("surface")
	assert_eq(Mastery.xp("gathering"), 52, "loading again changes nothing")
	var rec: Variant = GameState.mastery["legacy_credit"]
	assert_true(rec is Dictionary and bool(rec["applied"]), "recorded")
	for t in MasteryData.TRACKS:
		assert_true(Mastery.rank(String(t)) < 2, "legacy credit stays below rank 2")


func test_legacy_credit_caps_every_track() -> void:
	GameState.counters["structures_built"] = 999
	GameState.counters["crops_harvested"] = 999
	GameState.stats["items_crafted"] = 999
	GameState.lore = []
	for i in 30:
		GameState.lore.append("l%d" % i)
	GameState.flags["reached_silk_hollows"] = true
	GameState.flags["chapter_one_complete"] = true
	var preview := Mastery.legacy_credit_preview()
	for t in ["hearthcraft", "wayfinding"]:
		var most := 0
		for src in MasteryData.LEGACY_CREDIT[t]:
			most += int(src.get("cap", src.get("xp", 0)))
		assert_eq(int(preview[t]), mini(most, MasteryData.LEGACY_CAP_XP), t + " maxed out by its source caps")
		assert_true(int(preview[t]) <= MasteryData.LEGACY_CAP_XP)
		assert_true(ItemDB.mastery_rank_for_xp(int(preview[t])) < 2, t + " legacy credit below rank 2")


func test_new_journey_records_empty_credit_on_first_area_load() -> void:
	Events.area_loaded.emit("surface")
	assert_true(Mastery.legacy_applied(), "recorded at once")
	assert_eq(Mastery.xp("gathering"), 0)
	GameState.counters["trees_felled"] = 30   # earned in play from now on
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	Events.game_loaded.emit()
	assert_eq(Mastery.xp("gathering"), 0, "play counters are never credited again as legacy")


func test_v1_style_state_gets_credit_on_load() -> void:
	var d := GameState.to_dict()
	d.erase("mastery")
	(d["counters"] as Dictionary)["trees_felled"] = 5
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_false(Mastery.legacy_applied())
	Events.game_loaded.emit()
	assert_eq(Mastery.xp("gathering"), 10)
	assert_true(Mastery.legacy_applied())


func test_listeners_award_play_but_not_exploits() -> void:
	# Crafting: first craft = first_recipe, the next ones = capped "craft".
	GameState.give_item("berries", 12)
	assert_true(Crafting.craft("berry_snack", ["hand"]))
	assert_eq(Mastery.xp("hearthcraft"), int(_rule("hearthcraft", "first_recipe")["xp"]))
	assert_true(Crafting.craft("berry_snack", ["hand"]))
	assert_eq(Mastery.xp("hearthcraft"), int(_rule("hearthcraft", "first_recipe")["xp"]) + 1)
	# Placing, dismantling and re-placing the same piece: only the first placement counts.
	var before := Mastery.xp("hearthcraft")
	for i in 3:
		var uid := GameState.add_structure("stool", Vector3(i, 0, 0), 0)
		Events.structure_placed.emit(uid, "stool")
		GameState.remove_structure(uid)
		Events.structure_removed.emit(uid, "stool")
	assert_eq(Mastery.xp("hearthcraft"), before + int(_rule("hearthcraft", "first_structure")["xp"]))
	# Shuffling items between a chest and the backpack, re-equipping, healing, loading: nothing.
	var snap := GameState.mastery.duplicate(true)
	var chest := GameState.add_structure("storage_chest", Vector3(5, 0, 0), 0)
	var inv = GameState.get_storage(chest)
	GameState.give_item("stone", 10)
	for i in 5:
		GameState.inventory.transfer_slot_to(inv, 1)
		inv.transfer_slot_to(GameState.inventory, 0)
	Events.player_healed.emit(20.0)
	Events.equipment_changed.emit("head", "padded_hood")
	Events.equipment_changed.emit("head", "")
	Events.appearance_changed.emit()
	assert_eq(GameState.mastery, snap, "no xp from chests, equipping, restyling or heals")
	# Gathering: one node dropping two item kinds in one frame counts as ONE harvest.
	Events.harvested.emit("tree", "wood", 3, Vector3(1, 0, 1))
	Events.harvested.emit("tree", "fiber", 1, Vector3(1, 0, 1))
	assert_eq(Mastery.daily_used("gathering", "harvest"), 1)
	assert_true(Mastery.has_seen("gathering", "first_node_kind:tree"))
	assert_true(Mastery.has_seen("gathering", "first_material:wood") and Mastery.has_seen("gathering", "first_material:fiber"))
	# Wayfinding: landmarks, lore, arches, shortcuts and encounters (each distinct once).
	GameState.discover("surface", "haven")
	GameState.discover("surface", "haven")
	GameState.discover_lore("note_1")
	Events.arch_lit.emit("commons")
	Events.arch_lit.emit("commons")
	GameState.set_flag("ch2_shortcut_quarry", true)
	GameState.set_flag("weaver_defeated", true)
	Events.boss_defeated.emit("weaver_matron")
	var w := MasteryData.XP["wayfinding"]
	var expect := int(w["landmark"]["xp"]) + int(w["lore"]["xp"]) + int(w["arch"]["xp"]) + int(w["shortcut"]["xp"]) + int(w["encounter"]["xp"])
	assert_eq(Mastery.xp("wayfinding"), expect, "each distinct thing once (the Matron's flag and signal are one encounter)")
	# Crop harvests (capped), first use of a workshop station.
	Events.crop_harvested.emit("p1", "sweetroot", 2)
	assert_eq(Mastery.daily_used("hearthcraft", "crop_harvest"), int(_rule("hearthcraft", "crop_harvest")["xp"]))
	GameState.give_item("sunflax", 3)
	GameState.give_item("fiber", 2)
	assert_true(Crafting.craft("woven_cloth", ["hand", "loom"]))
	assert_true(Mastery.has_seen("hearthcraft", "first_station_use:loom"))


## Queueing a furnace job gives nothing (a job refunded by dismantling never pays); the finished job gives the
## first-recipe and first-station xp through the Events.crafted listener.
func test_furnace_xp_only_when_a_job_finishes() -> void:
	var uid := GameState.add_structure("furnace", Vector3(2, 0, 2), 0)
	GameState.stats["play_seconds"] = 0.0
	GameState.give_item("copper_ore", 4)
	assert_true(Furnace.enqueue(uid, "copper_bar"))
	assert_eq(Mastery.xp("hearthcraft"), 0, "queueing gives no xp")
	assert_false(Mastery.has_seen("hearthcraft", "first_station_use:furnace"))
	GameState.stats["play_seconds"] = 999.0
	assert_eq(Furnace.settle(uid), 1)
	assert_true(Mastery.has_seen("hearthcraft", "first_station_use:furnace"))
	assert_true(Mastery.has_seen("hearthcraft", "first_recipe:copper_bar"))
	var after := Mastery.xp("hearthcraft")
	assert_eq(after, int(_rule("hearthcraft", "first_recipe")["xp"]) + int(_rule("hearthcraft", "first_station_use")["xp"]))
	# Queue and dismantle-refund a second job: no xp at all.
	assert_true(Furnace.enqueue(uid, "copper_bar"))
	Furnace.refund_all(uid)
	assert_eq(Mastery.xp("hearthcraft"), after)


func test_inactive_state_awards_nothing() -> void:
	GameState.active = false
	assert_eq(Mastery.award("gathering", "first_node_kind:rock"), 0)
	assert_eq(Mastery.apply_legacy_credit(), {})
	GameState.active = true


func test_xp_is_bounded_by_max_rank() -> void:
	GameState.mastery["gathering"] = Mastery.max_xp() - 1
	assert_eq(Mastery.award("gathering", "first_node_kind:rock"), 1)
	assert_eq(Mastery.rank("gathering"), MasteryData.MAX_RANK)
	assert_eq(Mastery.award("gathering", "first_node_kind:tree"), 0)
	assert_almost(float(Mastery.progress("gathering")["fraction"]), 1.0)


## A record that already has mastery progress but no recorded credit (impossible in normal play: a new journey
## records its credit decision on the first area load) is never credited: loading leaves it exactly as saved.
func test_record_with_progress_is_left_exactly_as_loaded() -> void:
	GameState.counters["trees_felled"] = 4
	GameState.mastery["gathering"] = 12
	GameState.mastery["seen"]["gathering"] = ["oak_tree"]
	var before := JSON.stringify(GameState.to_dict()["mastery"])
	assert_true(SaveSystem.save_game(true))
	assert_true(SaveSystem.load_game())
	Events.area_loaded.emit("surface")
	assert_eq(JSON.stringify(GameState.to_dict()["mastery"]), before, "mastery unchanged by loading")
	assert_eq(Mastery.xp("gathering"), 12)
	assert_false(Mastery.legacy_applied())

