extends "res://tests/unit/test_core_base.gd"
## Story module C9 data: data/quests_ch2.gd (every step has a title, text and hint, valid {tokens},
## arachnophobia alternatives, targets that resolve to real landmark / zone ids, the MP §11 rewards),
## the five cross-area goals of data/optional_goals.gd, data/lore_ch2_story.gd, the MP §17 lines verbatim and
## the Lanternwake reward list (Game.chapter_two_rewards()).

const Quests := preload("res://data/quests_ch2.gd")
const Goals := preload("res://data/optional_goals.gd")
const StoryLore := preload("res://data/lore_ch2_story.gd")
const SourcesData := preload("res://data/sources.gd")
const WorldLayout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const EndingScreen := preload("res://src/ui/screens/ending_screen.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

## spec §7.2 Works zone ids (the Works has no landmark table of its own).
const WORKS_ZONES := ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge", "hw_lightwell",
	"hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]
const MANOR_ZONES := ["mm_cloakroom", "mm_hall", "mm_ballroom", "mm_gallery", "mm_balcony"]
## MP §17, verbatim.
const MP_ENDING_CARD := "The lanterns shine beyond the trees. The quiet below is quiet again. There are pumpkins to plant, walls to raise, and friends waiting by the fire. The road will keep. Tonight is yours."
const MP_RETURN := "Light kept. Roads found. Welcome home, Krystal."
## The Lanternwake's items (step ch2_feast give = data/sources.gd rw_ch2_feast = Game.chapter_two_rewards()).
const FEAST_TOTALS := {"candy": 6, "pumpkin": 4, "lantern_wax": 4, "sugarcap": 3, "moonpetal": 3}
## Spider-like wording (a metaphorical "thread of true light" is fine; "threads" spanning a bridge are not).
const SPIDERY := ["spider", "web", "weav", "matron", "threads", "silk", "skitter"]


func setup() -> void:
	fresh_state()


func _step(id: String) -> Dictionary:
	for s in Quests.STEPS:
		if String(s["id"]) == id:
			return s
	return {}


func _goal(id: String) -> Dictionary:
	for g in Goals.GOALS:
		if String(g["id"]) == id:
			return g
	return {}


func _spidery(text: String) -> bool:
	var l := text.to_lower()
	for w in SPIDERY:
		if l.contains(String(w)):
			return true
	return false


func test_every_step_has_title_text_hint_and_valid_tokens() -> void:
	assert_eq(Quests.STEPS.size(), 20)
	var tokens: Array = UiUtil.TOKEN_ACTIONS.keys() + ["move"]
	var rx := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for s in Quests.STEPS:
		var id := String(s["id"])
		for field in ["title", "text", "hint"]:
			assert_true(String(s.get(field, "")).length() >= 8, "%s has a %s" % [id, field])
			for m in rx.search_all(String(s.get(field, ""))):
				assert_true(tokens.has(m.get_string(1)), "%s %s token {%s}" % [id, field, m.get_string(1)])
		var oc: Dictionary = s.get("on_complete", {})
		assert_true(String(oc.get("message", "")) != "" or not (oc.get("give", {}) as Dictionary).is_empty(), id + " says what it gave")
		# Arachnophobia: anything spider-like in the normal text has a non-arachnid alternative.
		for field2 in ["title", "text", "hint"]:
			if _spidery(String(s.get(field2, ""))):
				assert_true(s.has("alt_" + field2), "%s %s is spider-like and needs alt_%s" % [id, field2, field2])
				assert_false(_spidery(String(s.get("alt_" + field2, ""))), "%s alt_%s is spider-free" % [id, field2])
		assert_false(_spidery(String(oc.get("message", ""))), id + " reward message is spider-free (it has no alt)")


func test_targets_resolve_to_real_landmark_ids() -> void:
	for s in Quests.STEPS:
		var t := String(s.get("target", ""))
		var where := "%s -> %s/%s" % [s["id"], s.get("target_area", ""), t]
		assert_ne(t, "", where + " has a target")
		match String(s.get("target_area", "")):
			"surface":
				assert_true(WorldLayout.LANDMARKS.has(t), where + " is a data/world_layout.gd landmark")
			Quests.REACH:
				assert_true(Reach.LANDMARKS.has(t), where + " is a data/hallowmere_layout.gd landmark")
			Quests.WORKS:
				assert_true(WORKS_ZONES.has(t), where + " is a Works zone (spec §7.2)")
			Quests.MANOR:
				assert_true(MANOR_ZONES.has(t), where + " is a manor zone")
			_:
				fail(where + ": unknown target area")
	# The closing beats point where the player has to go.
	assert_eq(String(_step("ch2_routes_restored")["target"]), "hr_commons")
	assert_eq(String(_step("ch2_homecoming")["target"]), "haven")
	assert_eq(String(_step("ch2_feast")["target_area"]), "surface")


func test_step_rewards_follow_mp_11() -> void:
	for id in ["ch2_orchard", "ch2_quarry", "ch2_manor"]:
		var give: Dictionary = (_step(id)["on_complete"] as Dictionary).get("give", {})
		assert_eq(int(give.get(id.trim_prefix("ch2_").replace("orchard", "garden") + "_seal", 0)), 1, id + " gives its seal")
	assert_eq(_step("ch2_lamps_linked")["on_complete"]["flags"], ["ch2_safe_light_routes"], "linked lamps: persistent safe-light routes (flag only)")
	assert_false((_step("ch2_lamps_linked")["on_complete"] as Dictionary).has("give"))
	var crossing: Dictionary = _step("ch2_weaver_crossing")["on_complete"]
	assert_eq(crossing.get("give", {}), {"thread_veil": 1}, "crossing: a thread / veil furnishing (its recipe is the crossing flag's unlock)")
	for s in Quests.STEPS:
		assert_false(((s.get("on_complete", {}) as Dictionary).get("give", {}) as Dictionary).has("heartseed"), String(s["id"]) + ": never another Heartseed")
	assert_eq(_step("ch2_routes_restored")["on_complete"]["flags"], [Story.TRIALS_FLAG], "routes restored: optional trials")
	var home: Dictionary = _step("ch2_homecoming")["on_complete"]
	assert_eq(home["give"], {"wardlight": 1})
	assert_eq(home["flags"], ["ch2_homecoming"], "home decoration pattern (Wardlight recipe) unlock")
	var feast: Dictionary = _step("ch2_feast")["on_complete"]
	assert_eq(feast["flags"], ["ch2_feast"], "the Lanternwake outfit pattern unlock")
	# Honest data: the step's give, the catalogue bundle and the ending's reward list are the same items.
	assert_deep_eq(json_norm(feast["give"]), json_norm(FEAST_TOTALS), "ch2_feast gives the festival treats and continued resources")
	assert_deep_eq(json_norm(SourcesData.REWARDS["rw_ch2_feast"]["items"]), json_norm(FEAST_TOTALS), "data/sources.gd rw_ch2_feast lists them all")
	for id2 in Story.FEAST_EXTRAS:
		assert_eq(int(feast["give"].get(id2, 0)), int(Story.FEAST_EXTRAS[id2]), "step give = FEAST_EXTRAS for " + String(id2))
		var listed := false
		for src in ItemDB.sources(String(id2)):
			listed = listed or (String(src["kind"]) == "reward" and String(src.get("reward", "")) == "rw_ch2_feast")
		assert_true(listed, String(id2) + " lists rw_ch2_feast as a source")
	# Every step reward is a real item and mirrors data/sources.gd REWARDS where that catalogue lists it.
	for s in Quests.STEPS:
		var rid := "rw_" + String(s["id"])
		var oc: Dictionary = s.get("on_complete", {})
		for it in oc.get("give", {}):
			assert_true(ItemDB.has_item(String(it)), "%s gives known item %s" % [rid, it])
		if SourcesData.REWARDS.has(rid):
			var b: Dictionary = SourcesData.REWARDS[rid]
			assert_eq(String(b["by"]), "chapter_log", rid)
			assert_deep_eq(json_norm(oc.get("give", {})), json_norm(b["items"]), rid + " items")
			var f1: Array = (oc.get("flags", []) as Array).duplicate()
			var f2: Array = (b["flags"] as Array).duplicate()
			f1.sort()
			f2.sort()
			assert_eq(f1, f2, rid + " flags")


func test_lanternwake_reward_list() -> void:
	var r: Dictionary = Game.chapter_two_rewards()
	assert_deep_eq(json_norm(r), json_norm(FEAST_TOTALS), "the ending's totals are exactly the Lanternwake list")
	assert_eq(int(r.get("candy", 0)), 6, "the final step's festival treats")
	for id in Story.FEAST_EXTRAS:
		assert_eq(int(r.get(id, 0)), int(Story.FEAST_EXTRAS[id]), "continued resource " + String(id))
	for id in r:
		assert_true(ItemDB.has_item(String(id)) and int(r[id]) > 0, "known item " + String(id))
		assert_false(ItemDB.is_quest_item(String(id)), String(id) + " is not a key item")
	assert_false(r.has("wood"), "no wood: the flow tests pass their own rewards")
	assert_false(ItemDB.pattern(Story.FEAST_PATTERN).is_empty(), "the Lanternwake outfit pattern exists")
	for p in Story.FEAST_PALETTES:
		assert_false(ItemDB.dye_palette(String(p)).is_empty(), "furnishing finish " + String(p) + " exists")


func test_cross_area_goals() -> void:
	var expect := {
		"opt_long_way_home": ["ta_hatch_open", "ch2_shortcut_manor", "ch2_refuge_shortcut"],
		"opt_harvest_table": ["ch2_table_decorated"],
		"opt_miner_came_back": ["c1x_tobin_letter_found", "ch2_hask_note_found"],
		"opt_pumpkin_face": ["ch2_pumpkin_harvested"],
		"opt_room_for_friends": [],
	}
	for id in expect:
		var g := _goal(String(id))
		assert_false(g.is_empty(), String(id))
		var flags: Array = []
		for o in g["objectives"]:
			if (o as Dictionary).has("flag"):
				flags.append(String(o["flag"]))
			for f in (o as Dictionary).get("flags", []):
				flags.append(String(f))
		assert_eq(flags, expect[id], String(id) + " objective flags")
		assert_ne(String(g.get("text", "")), "", String(id) + " text")
	assert_eq(_goal("opt_harvest_table")["objectives"][0]["counter"], Story.DISH_COUNTER)
	assert_true((_goal("opt_pumpkin_face")["objectives"][1] as Dictionary)["structure"] == "pumpkin_lantern")
	assert_eq(String(_goal("opt_room_for_friends")["objectives"][0]["type"]), "companion_home_spot")
	# The derived flags this module writes are exactly the ones those goals read.
	for lf in Story.LORE_FLAGS.values():
		assert_true(expect["opt_miner_came_back"].has(lf), String(lf))
	for af in Story.FLAG_ALIASES.values():
		assert_true(expect["opt_long_way_home"].has(af), String(af))
	# The seasonal dishes are real, cookable foods, none of them the goal's own reward (candy).
	for d in Story.SEASONAL_DISHES:
		assert_true(ItemDB.has_item(String(d)) and String(ItemDB.item(String(d)).get("cat", "")) == "food", String(d))
	assert_false(Story.SEASONAL_DISHES.has("candy"))
	# The table that completes the goal never depends on the goal's own reward: the Kitchen's festival-table choice
	# (Crafting.decorate_table) needs only a kitchen counter, whose recipe has no unlock. A plain Chapter One table
	# does not count (MP 15: choose a table decoration); the Lanternwake Table (the reward) also counts.
	assert_false(Story.TABLE_STRUCTURES.has("table"), "a plain table is not a festival table")
	assert_true(Story.TABLE_STRUCTURES.has("lanternwake_table"))
	var crafting: Script = load("res://src/crafting/crafting.gd")
	assert_false((crafting.get_script_constant_map().get("TABLE_DECOR", {}) as Dictionary).is_empty(), "the Kitchen offers table decorations")
	assert_eq(String(ItemDB.recipe("kitchen_counter").get("unlock", "x")), "", "the kitchen counter needs no unlock")
	assert_eq(String(ItemDB.station_structure("kitchen")), "kitchen_counter")
	assert_true(String(_goal("opt_harvest_table")["text"]).contains("kitchen"), "the goal text says where to dress the table")


func test_story_lore_and_mp_lines_verbatim() -> void:
	LoreDB.reload()
	for id in StoryLore.ORDER:
		assert_true(String(id).begins_with("lore_ch2_"), String(id))
		assert_true(LoreDB.has_lore(String(id)), String(id) + " through LoreDB")
		assert_false(_spidery(String(StoryLore.LORE[id]["text"])), String(id) + " spider-free")
	assert_eq(StoryLore.ORDER, [Story.LORE_ROUTES, Story.LORE_HOMECOMING, Story.LORE_LANTERNWAKE])
	assert_eq(String(StoryLore.LORE[Story.LORE_LANTERNWAKE]["text"]), MP_ENDING_CARD)
	assert_true(String(StoryLore.LORE[Story.LORE_HOMECOMING]["text"]).contains(MP_RETURN))
	assert_eq(EndingScreen.CH2_ENDING_CARD, MP_ENDING_CARD, "ending screen card (MP §17)")
	assert_eq(Game.CH2_ENDING_TEXT, MP_ENDING_CARD, "Game's stand-in line")
	assert_eq(WardStone.CH2_RETURN_LINE % "Krystal", MP_RETURN, "Ward Stone return line")
