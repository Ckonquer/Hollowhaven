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



# --- Map clarity (Wayfinding 2 / 4) ---------------------------------------------------------------------

func _harvest_at(area: String, kind: String, item: String, x: float, z: float) -> void:
	var was := String(Game.area_id)
	Game.area_id = area
	Events.harvested.emit(kind, item, 1, Vector3(x, 1.5, z))
	Game.area_id = was


## Harvested spots are remembered per area and kind (JSON-safe, deduped by distance, bounded, oldest forgotten),
## never for everyday kinds or areas without a painted map, and survive save / load. The map draws them from
## Wayfinding rank 2 (resource_pins_on).
func test_resource_spots_are_recorded_bounded_and_saved() -> void:
	var reach := "hallowmere_reach"
	_harvest_at(reach, "iron_vein", "iron_ore", 80.0, 20.0)
	_harvest_at(reach, "iron_vein", "stone", 80.0, 20.0)       # same node, second drop: one spot
	_harvest_at(reach, "iron_vein", "iron_ore", 83.0, 22.0)    # < SPOT_MIN_DIST: the same spot
	_harvest_at(reach, "iron_vein", "iron_ore", 88.0, 20.0)    # a second vein
	assert_eq(Mastery.known_spots(reach), [{"kind": "iron_vein", "pos": Vector2(80, 20)}, {"kind": "iron_vein", "pos": Vector2(88, 20)}])
	for k in MasteryData.SPOT_SKIP_KINDS:
		_harvest_at(reach, String(k), "stone", 10.0, 10.0)
	_harvest_at("below", "glowcap", "glowcap", 5.0, 5.0)
	_harvest_at("", "ore", "copper_ore", 5.0, 5.0)
	assert_eq(Mastery.known_spots(reach).size(), 2, "everyday kinds are never pinned")
	assert_eq(Mastery.known_spots("below"), [], "no painted map in the Below: nothing recorded")
	_harvest_at("surface", "sap_stump", "resin", -46.0, -14.0)
	assert_eq(Mastery.known_spots("surface"), [{"kind": "sap_stump", "pos": Vector2(-46, -14)}])
	# bounded: the oldest spot of a kind is forgotten first
	var cap := int(MasteryData.SPOT_MAX_PER_KIND)
	for i in cap + 6:
		_harvest_at(reach, "sugarcap_patch", "sugarcap", -60.0 + float(i) * 10.0, -8.0)
	var sugar: Array = Mastery.known_spots(reach).filter(func(s: Dictionary) -> bool: return s["kind"] == "sugarcap_patch")
	assert_eq(sugar.size(), cap, "at most %d per kind" % cap)
	assert_eq(sugar[0]["pos"], Vector2(-60.0 + 6.0 * 10.0, -8.0), "the six oldest were forgotten")
	assert_eq(sugar[cap - 1]["pos"], Vector2(-60.0 + float(cap + 5) * 10.0, -8.0))
	# save / load (JSON) keeps them; spots are not "progress" for the legacy-credit decision
	var before: Array = Mastery.known_spots(reach)
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(Mastery.known_spots(reach), before, "spots survive a save round trip")
	assert_eq(Mastery.known_spots("surface").size(), 1)
	# damaged records never raise an error
	GameState.mastery["spots"] = "broken"
	assert_eq(Mastery.known_spots(reach), [])
	GameState.mastery["spots"] = {reach: {"iron_vein": [[1, 2], "x", [null, 3], [4.0]], "moonpetal_patch": 7}}
	assert_eq(Mastery.known_spots(reach), [{"kind": "iron_vein", "pos": Vector2(1, 2)}], "bad entries skipped")
	assert_true(Mastery.record_spot(reach, "moonpetal_patch", Vector3(30, 0, 30)), "a damaged list is replaced")
	GameState.mastery["spots"] = 5
	assert_true(Mastery.record_spot(reach, "iron_vein", Vector3(1, 0, 1)))
	# rank gate for the map
	assert_false(Mastery.resource_pins_on())
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[1])
	assert_false(Mastery.resource_pins_on(), "rank 1: no pins")
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[2])
	assert_true(Mastery.resource_pins_on(), "rank 2: pins")
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[5])
	assert_true(Mastery.resource_pins_on(), "later ranks keep the pins")
	# pin icons: the node kind's main drop
	assert_eq(Mastery.spot_item("iron_vein"), "iron_ore")
	assert_eq(Mastery.spot_item("ore"), "copper_ore")
	assert_eq(Mastery.spot_item("no_such_kind"), "")
	GameState.active = false
	assert_false(Mastery.record_spot(reach, "iron_vein", Vector3(200, 0, 200)), "inactive state records nothing")
	GameState.active = true


## Cache hints: a "?" for each optional cache whose district is discovered, until the owner module's flag is
## set; positions come from the owner's layout constants. The map shows them from Wayfinding rank 4.
func test_cache_hints_follow_discovery_and_owner_flags() -> void:
	var C1x: Script = load("res://data/c1x_layout.gd")
	var West: Script = load("res://data/reach_west.gd")
	var c1x: Dictionary = C1x.get_script_constant_map()
	var west: Dictionary = West.get_script_constant_map()
	assert_eq(Mastery.cache_hints("surface"), [], "nothing before the Old Oak is found")
	GameState.discover("surface", "old_oak")
	assert_eq(Mastery.cache_hints("surface"), [{"id": "tailor_cache", "pos": c1x["TAILOR_CACHE"]["pos"], "district": "old_oak"}])
	GameState.set_flag("c1x_tailor_cache")
	assert_eq(Mastery.cache_hints("surface"), [], "found: the hint is gone")
	var reach := "hallowmere_reach"
	assert_eq(Mastery.cache_hints(reach), [])
	GameState.discover(reach, "hr_candleyard")
	var ids: Array = []
	for h in Mastery.cache_hints(reach):
		ids.append(h["id"])
	assert_eq(ids, ["witch_hat", "candleyard_pattern"], "only the discovered district's caches")
	assert_eq(Mastery.cache_hints(reach)[0]["pos"], west["HAT"]["pos"])
	assert_eq(Mastery.cache_hints(reach)[1]["pos"], west["PATTERN_SPOT"])
	GameState.discover(reach, "hr_pools")
	GameState.set_flag("ch2_witch_hat_found")
	ids = []
	for h in Mastery.cache_hints(reach):
		ids.append(h["id"])
	assert_eq(ids, ["festival_pouch", "candleyard_pattern"])
	assert_eq(Mastery.cache_hints(reach)[0]["pos"], west["POUCH"])
	GameState.set_flag("hr_chime_trail_done")
	GameState.set_flag("ch2_candleyard_pattern")
	assert_eq(Mastery.cache_hints(reach), [], "every cache found")
	# rank gate for the map
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[3])
	assert_false(Mastery.cache_hints_on(), "rank 3: no hints")
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[4])
	assert_true(Mastery.cache_hints_on(), "rank 4: hints")


## Every cache hint resolves to a position inside its district, and its flag is one the owner module really
## sets (a flag constant of the layout file, or a flag of a reward bundle that file names).
func test_cache_hint_data_matches_the_owner_layouts() -> void:
	var surface_lm: Dictionary = preload("res://data/world_layout.gd").LANDMARKS
	var reach_lm: Dictionary = preload("res://data/hallowmere_layout.gd").LANDMARKS
	for h in MasteryData.MAP_CACHE_HINTS:
		var id := String(h["id"])
		var pos: Variant = Mastery.cache_hint_pos(h)
		assert_true(pos is Vector2, id + " has a layout position")
		var lms: Dictionary = surface_lm if String(h["area"]) == "surface" else reach_lm
		assert_true(lms.has(h["district"]), id + " district is a landmark of its area")
		if pos is Vector2 and lms.has(h["district"]):
			var lm: Dictionary = lms[h["district"]]
			assert_true((pos as Vector2).distance_to(lm["pos"]) <= float(lm["radius"]), id + " lies inside its district")
		var consts: Dictionary = (load(String(h["layout"])) as Script).get_script_constant_map()
		var flags: Array = []
		for k in consts:
			var v: Variant = consts[k]
			if v is String:
				flags.append(v)
				if String(v).begins_with("rw_"):
					flags.append_array(ItemDB.reward_bundle(String(v)).get("flags", []))
			elif v is Dictionary and (v as Dictionary).get("flags") is Array:
				flags.append_array((v as Dictionary)["flags"])
		assert_true(flags.has(h["flag"]), "%s: flag %s is set by the owner module" % [id, h["flag"]])
	assert_true(Mastery.cache_hint_pos({"layout": "res://data/no_such_layout.gd", "const": "X"}) == null, "missing layout: no hint")
