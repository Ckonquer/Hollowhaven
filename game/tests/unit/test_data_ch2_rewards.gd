extends "res://tests/test_case.gd"
## Reward-ledger consistency between the data catalogue (data/sources.gd REWARDS) and the Chapter Two quest layer /
## optional log (data/quests_ch2.gd, data/optional_goals.gd), plus robustness of the ItemDB accessors that read
## saved state (appearance, mastery). Save safety (MP 2): a reward is paid once, one activity never pays the same
## item twice through two ledger ids, and damaged saved values never raise a script error.

const SourcesData := preload("res://data/sources.gd")
const ItemsData := preload("res://data/items.gd")
const AppearanceData := preload("res://data/appearance.gd")
const UnlocksData := preload("res://data/unlocks.gd")
const TrialsData := preload("res://data/trials.gd")
const EchoTrial := preload("res://src/world/areas_ch2/echo_trial.gd")
const Crafting := preload("res://src/crafting/crafting.gd")
const QUESTS_CH2 := "res://data/quests_ch2.gd"
const OPTIONAL_GOALS := "res://data/optional_goals.gd"
## Timed-buff keys of docs/CHAPTER_TWO_SPEC.md section 9 (GameState.add_buff keys consumed by Stats).
const SPEC_BUFF_KEYS := ["stamina_regen", "glimmerstep", "sprint_saver", "slow", "slow_resist", "ward_calm"]

var _mastery_before: Variant = null


func before_each() -> void:
	fresh_state()
	_mastery_before = GameState.get("mastery")


func after_each() -> void:
	if _mastery_before is Dictionary:
		GameState.set("mastery", (_mastery_before as Dictionary).duplicate(true))


# --- helpers ---------------------------------------------------------------------------------------------------

func _const(path: String, const_name: String) -> Array:
	assert_true(ResourceLoader.exists(path), path + " exists")
	if not ResourceLoader.exists(path):
		return []
	var s: Variant = load(path)
	if not (s is Script):
		fail(path + " loads as a script")
		return []
	var v: Variant = (s as Script).get_script_constant_map().get(const_name, [])
	return v if v is Array else []


## [{"rid", "by", "reward", "objective_flags"}] for every quest-layer step and optional goal.
func _log_entries() -> Array:
	var out: Array = []
	for st in _const(QUESTS_CH2, "STEPS"):
		out.append({"rid": "rw_" + String(st["id"]), "by": "chapter_log", "reward": st.get("on_complete", {}), "objective_flags": _objective_flags(st)})
	for g in _const(OPTIONAL_GOALS, "GOALS"):
		out.append({"rid": "rw_" + String(g["id"]), "by": "optional_log", "reward": g.get("reward", {}), "objective_flags": _objective_flags(g)})
	return out


func _objective_flags(entry: Dictionary) -> Array:
	var flags: Array = []
	for o in entry.get("objectives", []):
		if (o as Dictionary).has("flag"):
			flags.append(String(o["flag"]))
		for f in (o as Dictionary).get("flags", []):
			flags.append(String(f))
	return flags


## Item dictionaries equal regardless of int / float counts (JSON-safe comparison).
func _same_items(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or int(a[k]) != int(b[k]):
			return false
	return true


func _sorted(a: Variant) -> Array:
	var out: Array = (a as Array).duplicate() if a is Array else []
	out.sort()
	return out


# --- reward ledger consistency ---------------------------------------------------------------------------------

func test_mirrored_bundles_match_the_quest_layer_and_optional_log_exactly() -> void:
	var entries := _log_entries()
	assert_true(entries.size() >= 30, "read the quest layer and the optional goals (%d)" % entries.size())
	var log_ids := {}
	var mirrored := 0
	for e in entries:
		var rid := String(e["rid"])
		log_ids[rid] = String(e["by"])
		var rw: Dictionary = e["reward"]
		var give: Dictionary = rw.get("give", {})
		var bundle := ItemDB.reward_bundle(rid)
		var pays: bool = not give.is_empty() or not (rw.get("flags", []) as Array).is_empty() or not (rw.get("patterns", []) as Array).is_empty()
		if not pays:
			continue
		assert_false(bundle.is_empty(), rid + " is visible through ItemDB.reward_bundle")
		assert_true(_same_items(give, bundle.get("items", {})), "%s items: log %s vs catalogue %s" % [rid, str(give), str(bundle.get("items", {}))])
		assert_eq(_sorted(bundle.get("flags", [])), _sorted(rw.get("flags", [])), rid + " flags match")
		assert_eq(_sorted(bundle.get("patterns", [])), _sorted(rw.get("patterns", [])), rid + " patterns match")
		assert_eq(String(bundle.get("by", "")), String(e["by"]), rid + " is granted by the " + String(e["by"]))
		if SourcesData.REWARDS.has(rid):
			mirrored += 1
	assert_true(mirrored >= 8, "the catalogue mirrors the story and optional rewards (%d)" % mirrored)
	# every bundle of this catalogue that claims a log as its granter really is one of its rewards, and content /
	# legacy bundles never reuse a log id (they would silently race the log's own grant)
	for rid2 in SourcesData.REWARDS:
		var by := String(SourcesData.REWARDS[rid2].get("by", ""))
		if by == "chapter_log" or by == "optional_log":
			assert_eq(String(log_ids.get(rid2, "")), by, "%s mirrors a real %s reward (id = rw_ + its step / goal id)" % [rid2, by])
		else:
			assert_false(log_ids.has(rid2), "%s (%s) never reuses a quest-layer / optional-log reward id" % [rid2, by])


func test_one_activity_never_pays_the_same_item_twice() -> void:
	for e in _log_entries():
		var give: Dictionary = (e["reward"] as Dictionary).get("give", {})
		for bid in SourcesData.REWARDS:
			var b: Dictionary = SourcesData.REWARDS[bid]
			if String(b.get("by", "")) != "content" or bid == e["rid"]:
				continue
			var same_activity := false
			for f in b["flags"]:
				same_activity = same_activity or (e["objective_flags"] as Array).has(String(f))
			if not same_activity:
				continue
			for id in give:
				assert_false((b["items"] as Dictionary).has(id), "%s gives '%s' again: content bundle %s already gives it for the same activity" % [e["rid"], id, bid])
	# key items (seals, keys, scraps) are paid by exactly one bundle: a second path would duplicate a quest object
	var payers := {}
	for rid in ItemDB.all_reward_ids():
		for it in ItemDB.reward_bundle(String(rid))["items"]:
			if ItemDB.is_quest_item(String(it)):
				if not payers.has(it):
					payers[it] = []
				payers[it].append(rid)
	for it2 in payers:
		assert_eq((payers[it2] as Array).size(), 1, "%s is paid by exactly one reward (%s)" % [it2, str(payers[it2])])
	for seal in ["garden_seal", "quarry_seal", "manor_seal"]:
		assert_true(payers.has(seal), seal + " is a guaranteed reward")


## A constant of a content module's data script (null when the file or constant is missing).
func _script_const(path: String, const_name: String) -> Variant:
	assert_true(ResourceLoader.exists(path), path + " exists")
	if not ResourceLoader.exists(path):
		return null
	var s: Variant = load(path)
	return (s as Script).get_script_constant_map().get(const_name, null) if s is Script else null


## The content modules' own reward ids resolve to "content" bundles here, and the fallbacks those modules keep for
## a missing bundle pay exactly the same (so an older or newer build never changes what a save receives).
func test_content_modules_find_their_bundles() -> void:
	var cases := [
		["res://data/reach_west.gd", "REWARD_CHIMES", "CHIME_REWARD_FALLBACK", "rw_hr_chime_trail"],
		["res://data/works_layout_deep.gd", "THROAT_SUPPLIES_ID", "THROAT_SUPPLIES_FALLBACK", "rw_hw_throat_supplies"],
		["res://data/works_layout.gd", "ALCOVE_REWARD_ID", "", "rw_hw_lightwell_alcove"],
	]
	for c in cases:
		var rid: Variant = _script_const(String(c[0]), String(c[1]))
		assert_eq(String(rid), String(c[3]), "%s %s" % [c[0], c[1]])
		var b := ItemDB.reward_bundle(String(c[3]))
		assert_true(SourcesData.REWARDS.has(String(c[3])), String(c[3]) + " is catalogued in data/sources.gd REWARDS")
		assert_eq(String(b.get("by", "")), "content", String(c[3]) + " is granted by its content module")
		assert_false((b.get("items", {}) as Dictionary).is_empty(), String(c[3]) + " pays something")
		for it in b.get("items", {}):
			assert_false(ItemDB.is_quest_item(String(it)), "%s: %s is an ordinary item, never a key item" % [c[3], it])
		if String(c[2]) != "":
			var fb: Variant = _script_const(String(c[0]), String(c[2]))
			assert_true(fb is Dictionary, "%s %s" % [c[0], c[2]])
			if fb is Dictionary:
				assert_true(_same_items((fb as Dictionary).get("items", {}), b.get("items", {})), String(c[3]) + " fallback items = the bundle")
				assert_eq(_sorted((fb as Dictionary).get("flags", [])), _sorted(b.get("flags", [])), String(c[3]) + " fallback flags = the bundle")
	# The Light Well keepsake is decor only (MP 13 row 8, "outfit/decor alcove"): no pattern, so every pattern keeps
	# its one unique source.
	assert_eq(ItemDB.reward_bundle("rw_hw_lightwell_alcove").get("patterns", []), [], "the keepsake grants no pattern")
	for it2 in ItemDB.reward_bundle("rw_hw_lightwell_alcove")["items"]:
		assert_eq(String(ItemDB.item(String(it2)).get("cat", "")), "placeable", "keepsake %s is a decoration" % it2)


## Echo Trial first clears (MP 15: "First clears guarantee unique cosmetic patterns"; lead decision L09): every
## trial's content bundle is catalogued in data/sources.gd REWARDS as an exact mirror of data/trials.gd
## FIRST_REWARDS, sets only its own pattern-unlock flag (declared in data/unlocks.gd), and that flag is the ONLY way
## to its pattern: the pattern is in the catalogue (no "not yet" fallback), sewn by one Loom recipe gated by the
## flag, no other bundle sets the flag or grants the pattern, no other recipe sews it.
func test_echo_trial_first_clears_unlock_unique_patterns() -> void:
	var pats := {}
	for id in TrialsData.ids():
		var t := TrialsData.trial(String(id))
		var rid := String(t["first_reward"])
		var flag := "ch2_trial_" + String(id)
		var pid := String(t["pattern"])
		assert_true(SourcesData.REWARDS.has(rid), rid + " is catalogued in data/sources.gd REWARDS")
		assert_eq(SourcesData.REWARDS.get(rid, {}), TrialsData.FIRST_REWARDS.get(rid, {}), rid + " mirrors data/trials.gd FIRST_REWARDS exactly")
		assert_eq(ItemDB.reward_bundle(rid).get("flags", []), [flag], rid + " sets only " + flag)
		assert_eq(EchoTrial.first_bundle(String(id)), SourcesData.REWARDS.get(rid, {}), id + ": the trial pays the catalogued bundle")
		assert_true(UnlocksData.UNLOCK_FLAGS.has(flag), flag + " is declared in data/unlocks.gd")
		assert_true(ItemDB.unlock_setter(flag).begins_with("echo trial module"), flag + " is set by the echo trial module")
		var pat := ItemDB.pattern(pid)
		assert_false(pat.is_empty(), "%s: pattern %s is in data/appearance.gd" % [id, pid])
		assert_false(pats.has(pid), pid + " belongs to one trial only")
		pats[pid] = true
		assert_eq(String(pat.get("name", "")), String(t["pattern_name"]), pid + ": the name the trial promises")
		assert_eq(String(pat.get("flag", "")), flag, pid + " is unlocked by this trial's flag")
		var r := ItemDB.recipe(String(pat.get("recipe", "")))
		assert_eq(String(r.get("pattern", "")), pid, pid + " has its Loom recipe")
		assert_eq(String(r.get("station", "")), "loom", pid + " is sewn at the Loom")
		assert_eq(String(r.get("unlock", "")), flag, pid + " recipe is gated by the trial flag")
		for other in ItemDB.all_reward_ids():
			if String(other) == rid:
				continue
			var ob := ItemDB.reward_bundle(String(other))
			assert_false((ob.get("flags", []) as Array).has(flag), "%s never sets %s" % [other, flag])
			assert_false((ob.get("patterns", []) as Array).has(pid), "%s never grants %s" % [other, pid])
		for rec in ItemDB.every_recipe_id():
			if String(rec) != String(pat["recipe"]):
				assert_ne(String(ItemDB.recipe(String(rec)).get("pattern", "")), pid, "%s never sews %s" % [rec, pid])
	assert_eq(pats.keys(), ["pat_moon_moth", "pat_echo_masquerade", "pat_echo_chime"])


## Save safety (no migration): a save that cleared the Count's echo before the pattern existed only has the flag;
## that flag alone shows the Loom recipe. A fresh first clear goes through the same path: flag -> recipe -> sewn
## once -> the wardrobe owns the pattern (both parts).
func test_a_cleared_trial_flag_is_enough_to_sew_its_pattern() -> void:
	assert_false(ItemDB.recipe_known("pattern_echo_masquerade"), "locked before the first clear")
	assert_false(Crafting.known_special("loom").has("pattern_echo_chime"))
	GameState.set_flag("ch2_trial_velour", true)          # an older save: the flag, no pattern ownership
	assert_true(ItemDB.recipe_known("pattern_echo_masquerade"), "the existing flag unlocks the recipe")
	assert_true(Crafting.known_special("loom").has("pattern_echo_masquerade"))
	GameState.give_item("woven_cloth", 6)
	GameState.give_item("lantern_wax", 2)
	GameState.give_item("echo_shard", 2)
	assert_true(Crafting.craft("pattern_echo_masquerade", ["hand", "loom"]), Crafting.last_reason)
	assert_true((GameState.wardrobe["owned"] as Array).has("pat_echo_masquerade"))
	assert_false(Crafting.craft("pattern_echo_masquerade", ["hand", "loom"]), "sewn once")
	assert_eq(GameState.count_item("woven_cloth"), 3, "cloth used once")
	assert_eq(GameState.count_item("lantern_wax"), 0)
	# the Choir: a real first clear sets the flag through the catalogued bundle
	for f in ["chapter_one_complete", "ch2_choir_defeated"]:
		GameState.set_flag(f, true)
	assert_true(bool(EchoTrial.record_clear("choir", 200.0)["first"]), "first clear pays the bundle")
	assert_true(bool(GameState.get_flag("ch2_trial_choir")))
	assert_true(ItemDB.recipe_known("pattern_echo_chime"))
	assert_true(Crafting.craft("pattern_echo_chime", ["hand", "loom"]), Crafting.last_reason)
	assert_true((GameState.wardrobe["owned"] as Array).has("pat_echo_chime"))
	assert_eq(GameState.count_item("echo_shard"), 0)


func test_legacy_descriptions_are_never_ledger_rewards() -> void:
	for rid in SourcesData.REWARDS:
		var b: Dictionary = SourcesData.REWARDS[rid]
		if String(rid).begins_with("legacy_"):
			assert_eq(String(b.get("by", "")), "legacy", rid + " is marked legacy (documentation only)")
		else:
			assert_true(String(rid).begins_with("rw_"), rid + " uses the rw_ ledger namespace (spec section 2)")
			assert_ne(String(b.get("by", "")), "legacy", rid + " is a real ledger reward")
	assert_eq(ItemDB.reward_bundle("definitely_not_a_reward"), {})
	var ids := ItemDB.all_reward_ids()
	for rid2 in ids:
		assert_eq(ids.count(rid2), 1, String(rid2) + " listed once")


# --- robustness against damaged saved values ------------------------------------------------------------------

func test_sanitize_look_survives_damaged_save_values() -> void:
	var junk := {"hair": null, "hair_color": 3.0, "skin": ["skin_2"], "eyes": {"id": "eye_1"}, "upper": 12,
		"lower": null, "shoes": "wellies", "hat": null, "hair_acc": 1.5, "back": "", "palette": {"primary": null,
		"secondary": 7, "accent": "rose"}, "outfit": null}
	var before := junk.duplicate(true)
	var res := ItemDB.sanitize_look(junk)
	assert_eq(junk, before, "the saved data is never modified")
	var look: Dictionary = res["look"]
	var legacy := ItemDB.legacy_look()
	for key in ["hair", "hair_color", "skin", "eyes", "upper", "lower", "hair_acc"]:
		assert_eq(look[key], legacy[key], key + " falls back to the legacy value")
	assert_eq(look["shoes"], "wellies", "valid ids are kept")
	assert_eq(look["hat"], "", "null in an optional slot = nothing worn")
	assert_eq(look["back"], "")
	assert_eq(look["palette"]["primary"], "teal")
	assert_eq(look["palette"]["secondary"], "sunflower")
	assert_eq(look["palette"]["accent"], "rose")
	assert_eq(look["outfit"], "")
	var missing: Array = res["missing"]
	for key2 in ["hair", "hair_color", "skin", "eyes", "upper", "lower", "hair_acc", "palette.primary", "palette.secondary"]:
		var found := false
		for m in missing:
			found = found or String(m).begins_with(key2 + "=")
		assert_true(found, key2 + " is reported as missing")
	assert_false(str(missing).contains("hat="), "an empty optional slot is not an error")
	var not_dict := ItemDB.sanitize_look({"palette": "teal"})
	assert_eq(not_dict["look"]["palette"], legacy["palette"])
	assert_true(str(not_dict["missing"]).contains("palette="), "a palette that is not a dictionary is reported")
	var nothing := ItemDB.sanitize_look(null)
	assert_eq(nothing["look"], legacy, "no look at all shows the legacy look")
	assert_eq(nothing["missing"].size(), 1, "and reports it")


func test_mastery_rank_reads_json_floats_and_ignores_damaged_values() -> void:
	GameState.set("mastery", {"gathering": 120.0, "hearthcraft": null, "wayfinding": {"xp": 999}})
	assert_eq(ItemDB.mastery_rank("gathering"), ItemDB.mastery_rank_for_xp(120), "a JSON float counts like an int")
	assert_eq(ItemDB.mastery_rank("hearthcraft"), 0, "null xp is rank 0, no error")
	assert_eq(ItemDB.mastery_rank("wayfinding"), 0, "a damaged xp value is rank 0, no error")
	assert_eq(ItemDB.mastery_rank("nope"), 0)
	assert_false(ItemDB.recipe_known("crescent_window"), "damaged mastery never unlocks a gated recipe")
	GameState.set("mastery", {"hearthcraft": 40.0})
	assert_true(ItemDB.recipe_known("crescent_window"), "rank 1 from a loaded (float) value unlocks the rank-1 recipe")
	assert_false(ItemDB.recipe_known("gothic_trim"), "rank 2 recipe still locked")
	assert_eq(ItemDB.mastery_rank_for_xp(JSON.parse_string("600")), 5, "JSON number argument")


func test_companion_perks_never_change_the_base_table() -> void:
	var base_heal := float(ItemDB.companion_skill("mochi")["signature"]["heal"])
	var top := ItemDB.companion_skill_at("mochi", 5)
	assert_eq(float(top["signature"]["heal"]), 22.0)
	assert_eq(float(ItemDB.companion_skill("mochi")["signature"]["heal"]), base_heal, "the data table is untouched")
	assert_eq(float(ItemDB.companion_skill_at("mochi", 0)["signature"]["heal"]), 18.0)
	assert_eq(ItemDB.companion_skill_at("nobody", 5), {})


# --- cross-module contracts -------------------------------------------------------------------------------------

func test_legacy_look_matches_the_core_save_default() -> void:
	var consts: Dictionary = (GameState.get_script() as Script).get_script_constant_map()
	if consts.has("LEGACY_LOOK_IDS"):
		assert_eq(consts["LEGACY_LOOK_IDS"], AppearanceData.LEGACY_LOOK, "GameState's migration default = data/appearance.gd LEGACY_LOOK")
	assert_eq(ItemDB.sanitize_look(AppearanceData.LEGACY_LOOK)["missing"], [], "the legacy look is fully valid")


func test_food_buffs_use_the_spec_timed_buff_keys() -> void:
	for id in ItemsData.ITEMS:
		var d: Dictionary = ItemsData.ITEMS[id]
		var b: Variant = d.get("buff", null)
		if not (b is Dictionary):
			continue
		for k in b:
			if String(k) != "seconds":
				assert_true(SPEC_BUFF_KEYS.has(String(k)), "%s buff key %s is a spec section 9 timed buff" % [id, k])
		assert_false(d.has("buff") and (b as Dictionary).has("family"), id + " family lives beside the buff, never inside it (legacy eat() adds every buff key)")
	assert_eq(float(ItemsData.ITEMS["moonpetal_tea"]["buff"]["slow_resist"]), 0.5, "moonpetal tea: slow resistance")
	for fam in ItemsData.BUFF_FAMILIES:
		assert_true(SPEC_BUFF_KEYS.has(String(ItemsData.BUFF_FAMILIES[fam]["effect"])), fam + " family effect is a spec buff key")
