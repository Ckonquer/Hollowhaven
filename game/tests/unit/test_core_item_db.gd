extends "res://tests/unit/test_core_base.gd"
## ItemDB (autoload/item_db.gd) and the data files it serves: every cross reference is valid,
## arachnophobia names, recipe unlocks, bond levels and lookups of unknown ids.

const ItemsData := preload("res://data/items.gd")
const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const CreaturesData := preload("res://data/creatures.gd")
const EnemiesData := preload("res://data/enemies.gd")
const HorrorData := preload("res://data/horror_events.gd")
const Layout := preload("res://data/world_layout.gd")

const LAYERS := ["decor", "floor", "object", "edge", "roof"]
const SNAPS := ["cell", "floor2", "edge2", "roof2"]
const INTERACTS := ["", "storage", "sleep", "farm", "station"]
const TOOL_KINDS := ["axe", "pickaxe"]
const BEFRIEND_TYPES := ["offer_item", "free_from_boulder", "rescue"]
const EVENT_KINDS := ["sound", "wrong_sound", "glimpse", "flicker", "notice", "scratch", "silence", "spawn", "stalker_pass"]
const ZONES := ["mine", "ruins", "silk"]
const DIRECTOR_STATES := ["calm", "unease", "anticipation", "encounter", "recovery"]
const ANCHORS := ["", "sound", "doorway", "ceiling", "floor", "spawn"]


func setup() -> void:
	fresh_state()
	Settings.values["arachnophobia"] = false


# --- items ---------------------------------------------------------------------------------------------------------

func test_every_item_definition_is_complete() -> void:
	var order: Array = ItemsData.CATEGORY_ORDER
	for id in ItemsData.ITEMS:
		var d := ItemDB.item(id)
		assert_eq(d["id"], id)
		assert_true(String(d["name"]) != "" and String(d["name"]) != "?", id + " has a name")
		assert_true(String(d["desc"]) != "", id + " has a description")
		assert_true(order.has(d["cat"]), id + " category sortable")
		assert_true(int(d["stack"]) >= 1, id + " stack >= 1")
		assert_true(String(d["icon"]) != "unknown", id + " has an icon id")
		assert_true(d["color"] is Color, id + " colour")
		match String(d["cat"]):
			"tool":
				assert_true(TOOL_KINDS.has(d["tool"]), id + " tool kind")
				assert_eq(int(d["stack"]), 1, id + " tools do not stack")
				assert_true(float(d["damage"]) > 0.0 and float(d["power"]) > 0.0, id + " tool stats")
			"weapon":
				assert_eq(int(d["stack"]), 1)
				assert_true(float(d["damage"]) > 0.0, id + " weapon damage")
			"food":
				assert_true(float(d["heal"]) > 0.0, id + " food heals")
			"placeable":
				assert_false(ItemDB.structure(d["place"]).is_empty(), id + " places a real structure")
				assert_eq(ItemDB.structure(d["place"]).get("item", ""), id, id + " is refunded as itself")
			"seed":
				assert_false(ItemDB.crop(String(d.get("crop", ""))).is_empty(), id + " grows a real crop")
			"key":
				assert_true(ItemDB.is_quest_item(id), id + " quest item")
				assert_eq(int(d["stack"]), 1)
		if d.has("buff"):
			var b: Dictionary = d["buff"]
			assert_true(float(b.get("seconds", 0.0)) > 0.0, id + " buff duration")
			assert_eq(b.size(), 2, id + " buff has one effect + seconds")
		if d.has("alt_name"):
			assert_true(d.has("alt_desc"), id + " alt name comes with an alt description")
		if String(d["tool"]) != "":
			assert_eq(d["cat"], "tool", id + " only tools have a tool kind")


func test_quest_items_are_exactly_the_key_category() -> void:
	for id in ItemsData.ITEMS:
		assert_eq(ItemDB.is_quest_item(id), ItemDB.category(id) == "key", id)
	assert_false(ItemDB.is_quest_item("wood"))
	assert_false(ItemDB.is_quest_item("not_an_item"))
	assert_false(logged("unknown item"), "no warning spam for quest checks")


func test_unknown_item_lookup_is_a_safe_placeholder() -> void:
	var d := ItemDB.item("zzz_missing")
	assert_eq(d["id"], "zzz_missing")
	assert_eq(d["name"], "zzz_missing")
	assert_eq(int(d["stack"]), 99)
	assert_true(logged("unknown item 'zzz_missing'"))
	assert_false(ItemDB.has_item("zzz_missing"))
	assert_eq(ItemDB.item("wood")["name"], "Wood", "placeholder does not pollute the table")


func test_items_in_category() -> void:
	var tools := ItemDB.items_in_category("tool")
	tools.sort()
	assert_eq(tools, ["stone_axe", "stone_pickaxe"])
	assert_eq(ItemDB.items_in_category("nonsense"), [])


# --- recipes -------------------------------------------------------------------------------------------------------

func test_every_recipe_reference_is_valid() -> void:
	for rid in RecipesData.RECIPES:
		var r: Dictionary = RecipesData.RECIPES[rid]
		assert_true(ItemDB.has_item(r["result"]), rid + " result exists")
		assert_true(int(r["count"]) >= 1, rid + " produces something")
		assert_true(RecipesData.STATIONS.has(r["station"]), rid + " station exists")
		assert_true(r["unlock"] is String, rid + " unlock is a flag name")
		var ings: Dictionary = r["ingredients"]
		assert_false(ings.is_empty(), rid + " has ingredients")
		assert_false(ings.has(r["result"]), rid + " does not consume its own result")
		var slots_needed := 0
		for ing in ings:
			assert_true(ItemDB.has_item(ing), "%s ingredient %s exists" % [rid, ing])
			assert_true(int(ings[ing]) > 0, "%s ingredient count" % rid)
			assert_false(ItemDB.is_quest_item(ing), "%s never consumes a quest item" % rid)
			slots_needed += ceili(float(ings[ing]) / float(ItemDB.stack_max(ing)))
		assert_true(slots_needed <= GameState.INVENTORY_SIZE, rid + " ingredients fit in a backpack")
		assert_true(int(r["count"]) <= ItemDB.stack_max(r["result"]), rid + " output fits one stack")


func test_recipe_known_respects_unlock_flags() -> void:
	assert_true(ItemDB.recipe_known("stone_axe"))
	assert_false(ItemDB.recipe_known("heartbloom_lamp"), "locked until the ward is restored")
	GameState.set_flag("ward_restored")
	assert_true(ItemDB.recipe_known("heartbloom_lamp"))
	GameState.set_flag("ward_restored", false)
	assert_false(ItemDB.recipe_known("heartbloom_lamp"))
	assert_false(ItemDB.recipe_known("no_such_recipe"))
	assert_eq(ItemDB.recipe("no_such_recipe"), {})


func test_unlock_flags_are_reachable_through_the_quest_chain() -> void:
	var quest_flags := {}
	for s in QuestsData.STEPS:
		for o in s["objectives"]:
			if o["type"] == "flag":
				quest_flags[o["flag"]] = true
		for f in s.get("on_complete", {}).get("flags", []):
			quest_flags[f] = true
	for rid in RecipesData.RECIPES:
		var flag: String = RecipesData.RECIPES[rid]["unlock"]
		assert_true(flag == "" or quest_flags.has(flag), "%s unlock flag %s is part of the chapter" % [rid, flag])


func test_station_names() -> void:
	assert_eq(ItemDB.station_name("hand"), "By Hand")
	assert_eq(ItemDB.station_name("workbench"), "Workbench")
	assert_eq(ItemDB.station_name("forge"), "Forge", "unknown stations get a readable fallback")


# --- structures & crops -----------------------------------------------------------------------------------------------

func test_every_structure_reference_is_valid() -> void:
	for sid in StructuresData.STRUCTURES:
		var s: Dictionary = StructuresData.STRUCTURES[sid]
		assert_true(ItemDB.has_item(s["item"]), sid + " refund item exists")
		assert_eq(ItemDB.item(s["item"]).get("place", ""), sid, sid + " item places this structure")
		assert_true(String(s["name"]) != "", sid + " name")
		assert_true(LAYERS.has(s["layer"]), sid + " layer")
		assert_true(SNAPS.has(s["snap"]), sid + " snap")
		var size: Vector2i = s["size"]
		assert_true(size.x >= 1 and size.y >= 1, sid + " footprint")
		assert_true(float(s["height"]) > 0.0, sid + " height")
		assert_true(s["solid"] is bool, sid + " solid flag")
		assert_true(INTERACTS.has(s["interact"]), sid + " interact kind")
		if s["interact"] == "station":
			assert_true(RecipesData.STATIONS.has(s.get("station", "")), sid + " provides a real station")
		if s["interact"] == "storage":
			assert_true(int(s.get("slots", 0)) > 0, sid + " storage slots")
		if s.has("light"):
			assert_true(s["light"]["color"] is Color and float(s["light"]["range"]) > 0.0, sid + " light")
	for id in ItemDB.items_in_category("placeable"):
		assert_false(ItemDB.structure(ItemDB.item(id)["place"]).is_empty(), id + " has a structure")


func test_every_crop_reference_is_valid() -> void:
	for cid in StructuresData.CROPS:
		var c: Dictionary = StructuresData.CROPS[cid]
		assert_true(ItemDB.has_item(c["seed"]), cid + " seed exists")
		assert_eq(ItemDB.category(c["seed"]), "seed")
		assert_eq(ItemDB.item(c["seed"]).get("crop", ""), cid, cid + " seed grows this crop")
		assert_true(float(c["grow_minutes"]) > 0.0)
		assert_true(int(c["stages"]) >= 2)
		for it in c["yield"]:
			assert_true(ItemDB.has_item(it), "%s yield %s exists" % [cid, it])
			var mm: Array = c["yield"][it]
			assert_true(int(mm[0]) >= 1 and int(mm[0]) <= int(mm[1]), "%s yield range" % cid)
		assert_true(c["yield"].has(c["seed"]), cid + " returns seeds so farming is sustainable")


# --- creatures ----------------------------------------------------------------------------------------------------------

func test_every_creature_reference_is_valid() -> void:
	var th: Array = CreaturesData.BOND_XP_PER_LEVEL
	assert_eq(int(th[0]), 0)
	for i in range(1, th.size()):
		assert_true(int(th[i]) > int(th[i - 1]), "bond thresholds strictly increase")
	for cid in CreaturesData.CREATURES:
		var c: Dictionary = CreaturesData.CREATURES[cid]
		assert_true(String(c["name"]) != "", cid + " name")
		assert_true(ItemDB.has_item(c["favorite_food"]), cid + " favourite food exists")
		var bf: Dictionary = c["befriend"]
		assert_true(BEFRIEND_TYPES.has(bf["type"]), cid + " befriend type")
		if bf["type"] == "offer_item":
			assert_true(ItemDB.has_item(bf["item"]) and int(bf["count"]) > 0, cid + " offer item")
		if bf["type"] == "rescue":
			assert_true(String(bf.get("flag", "")) != "", cid + " rescue flag")
		assert_true(c["enters_below"] is bool)
		assert_true(float(c["move_speed"]) > 0.0 and float(c["follow_distance"]) > 0.0)
		var lines: Dictionary = CreaturesData.LINES.get(cid, {})
		for ctx in ["befriend", "pet", "follow", "wait", "home", "celebrate", "idle"]:
			assert_false(lines.get(ctx, []).is_empty(), "%s has '%s' lines" % [cid, ctx])
		for sp in ["companion_wild_" + cid, "companion_home_" + cid]:
			assert_true(Layout.SPAWN_HINTS.has(sp), "layout has spawn hint " + sp)
	assert_false(bool(CreaturesData.CREATURES["mochi"]["enters_below"]), "Mochi waits at the mine threshold")
	assert_true(Layout.SPAWN_HINTS.has("mine_threshold"))


func test_creature_lines_fill_the_player_name() -> void:
	for i in 12:
		var l := ItemDB.creature_line("mochi", "follow")
		assert_false(l.contains("{name}"))
		assert_true(l in ["Mochi hops after you.", "Mochi bounces along behind Krystal."], "line: " + l)
	assert_eq(ItemDB.creature_line("mochi", "no_context"), "")
	assert_eq(ItemDB.creature_line("nobody", "pet"), "")


func test_bond_level_for_xp() -> void:
	var th: Array = CreaturesData.BOND_XP_PER_LEVEL
	for lvl in th.size():
		assert_eq(ItemDB.bond_level_for_xp(int(th[lvl])), lvl)
	assert_eq(ItemDB.bond_level_for_xp(-10), 0)
	assert_eq(ItemDB.bond_level_for_xp(9), 0)
	assert_eq(ItemDB.bond_level_for_xp(100000), th.size() - 1)


# --- enemies & horror data ------------------------------------------------------------------------------------------------

func test_every_enemy_reference_is_valid() -> void:
	for eid in EnemiesData.ENEMIES:
		var e: Dictionary = EnemiesData.ENEMIES[eid]
		assert_true(float(e["hp"]) > 0.0 and float(e["damage"]) > 0.0, eid + " stats")
		assert_true(float(e["telegraph"]) >= 0.5, eid + " attacks are readable (telegraph >= 0.5 s)")
		assert_true(float(e["recover"]) > 0.0, eid + " has a recovery window")
		assert_true(e["area"] in ["surface", "below"], eid + " area")
		for drop in e.get("drops", []):
			assert_true(ItemDB.has_item(drop["item"]), "%s drop %s exists" % [eid, drop["item"]])
			assert_true(int(drop["min"]) >= 0 and int(drop["min"]) <= int(drop["max"]), eid + " drop range")
			assert_true(float(drop["chance"]) > 0.0 and float(drop["chance"]) <= 1.0, eid + " drop chance")
			assert_false(ItemDB.is_quest_item(drop["item"]), eid + " never drops quest items randomly")
	for spider in ["weaver", "weaver_matron"]:
		assert_true(String(EnemiesData.ENEMIES[spider]["alt_name"]) != "", spider + " has an arachnophobia name")
		assert_true(EnemiesData.ENEMIES[spider].has("alt_sound"), spider + " has arachnophobia sounds")


func test_horror_data_is_consistent() -> void:
	for k in [0, 1, 2]:
		assert_true(HorrorData.INTENSITY.has(k), "intensity %d" % k)
	assert_eq(HorrorData.INTENSITY.size(), int(Settings.RANGES["horror_intensity"][1]) + 1, "settings range matches the data")
	assert_false(bool(HorrorData.INTENSITY[0]["allow_major"]), "Gentle has no major scares")
	for ev_id in HorrorData.EVENTS:
		var ev: Dictionary = HorrorData.EVENTS[ev_id]
		assert_true(EVENT_KINDS.has(ev["kind"]), ev_id + " kind")
		for z in ev["zones"]:
			assert_true(ZONES.has(z), ev_id + " zone " + z)
		for st in ev["states"]:
			assert_true(DIRECTOR_STATES.has(st), ev_id + " state " + st)
		assert_true(ANCHORS.has(ev["anchor"]), ev_id + " anchor")
		assert_true(float(ev["weight"]) > 0.0 and float(ev["cooldown"]) > 0.0, ev_id + " weight/cooldown")
		assert_true(HorrorData.INTENSITY.has(int(ev["min_intensity"])), ev_id + " min intensity")
		if ev["kind"] == "spawn":
			assert_false(ItemDB.enemy(ev["enemy"]).is_empty(), ev_id + " spawns a real enemy")
		if bool(ev.get("spider", false)):
			assert_true(ev.has("alt_sound"), ev_id + " spider event has an arachnophobia sound")


# --- arachnophobia -------------------------------------------------------------------------------------------------------

func test_display_names_follow_arachnophobia() -> void:
	assert_eq(ItemDB.display_name("silk"), "Weaver Silk")
	assert_true(ItemDB.display_desc("silk").contains("Silk Hollows"))
	assert_eq(ItemDB.enemy_display_name("weaver"), "The Weaver")
	assert_eq(ItemDB.enemy_display_name("weaver_matron"), "The Weaver Matron")
	Settings.set_value("arachnophobia", true)
	assert_eq(ItemDB.display_name("silk"), "Pale Thread")
	assert_false(ItemDB.display_desc("silk").to_lower().contains("silk"), "no spider words in the alt text")
	assert_eq(ItemDB.enemy_display_name("weaver"), "The Hollow Shade")
	assert_eq(ItemDB.enemy_display_name("weaver_matron"), "The Hollow Mother")
	assert_eq(ItemDB.enemy_display_name("brambling"), "Brambling", "empty alt name keeps the normal name")
	assert_eq(ItemDB.display_name("wood"), "Wood", "items without an alt are unchanged")
	assert_eq(ItemDB.enemy_display_name("unknown_enemy"), "unknown_enemy")
	Settings.set_value("arachnophobia", false)
	assert_eq(ItemDB.display_name("silk"), "Weaver Silk")


func test_no_spider_words_leak_into_alt_texts() -> void:
	Settings.set_value("arachnophobia", true)
	for id in ItemsData.ITEMS:
		var txt := (ItemDB.display_name(id) + " " + ItemDB.display_desc(id)).to_lower()
		for w in ["spider", "weaver", "web", "silk"]:
			assert_false(txt.contains(w), "%s shows '%s' with arachnophobia on" % [id, w])


## Item texts are shown next to the live key label (UiUtil stat lines, e.g. "Press <lantern key> to raise
## it"), so a hard-coded key in a description contradicts rebinding (the Lantern once said "Press F").
func test_item_descriptions_do_not_hard_code_keys() -> void:
	var rx := RegEx.new()
	rx.compile("\b(WASD|[Pp]ress [A-Z0-9])\b")
	for id in ItemsData.ITEMS:
		for field in ["desc", "alt_desc"]:
			var d := String((ItemsData.ITEMS[id] as Dictionary).get(field, ""))
			assert_null(rx.search(d), "%s %s hard-codes a key: %s" % [id, field, d])
