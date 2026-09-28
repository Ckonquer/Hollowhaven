extends "res://tests/test_case.gd"
## UI pure helpers: hint tokens, toast aggregation, stack moves, clock text, bindings, map maths.

const UiUtil := preload("res://src/ui/ui_util.gd")
const QuestsData := preload("res://data/quests.gd")
const Inventory := preload("res://src/core/inventory.gd")


func before_each() -> void:
	UiUtil.allow_settings_save = false


static func _fake_label(action: String) -> String:
	return "<%s>" % action


static func _wasd(action: String) -> String:
	return {"move_forward": "W", "move_left": "A", "move_back": "S", "move_right": "D"}.get(action, "?")


static func _arrows(action: String) -> String:
	return {"move_forward": "Up", "move_left": "Left", "move_back": "Down", "move_right": "Right"}.get(action, "?")


# --- tokens ------------------------------------------------------------------------------

func test_tokens_are_replaced_with_action_labels() -> void:
	var out := UiUtil.fill_tokens("Press {interact} to read, {use} to eat, {help} for help.", Callable(self, "_fake_label"))
	assert_eq(out, "Press <interact> to read, <use_item> to eat, <help> for help.")


func test_unknown_tokens_are_left_alone_and_wrappers_apply() -> void:
	var out := UiUtil.fill_tokens("{craft} then {mystery}", Callable(self, "_fake_label"), "[b]", "[/b]")
	assert_eq(out, "[b]<craft>[/b] then {mystery}")


func test_move_token_compacts_single_letters() -> void:
	assert_eq(UiUtil.fill_tokens("Move with {move}.", Callable(self, "_wasd")), "Move with WASD.")
	assert_eq(UiUtil.fill_tokens("{move}", Callable(self, "_arrows")), "Up / Left / Down / Right")


func test_every_quest_hint_token_is_known() -> void:
	# Hints in data/quests.gd (and Game.new_game's intro hint) must not show raw {tokens} to the player.
	var texts: Array = ["Move with {move}. Hold {sprint} to sprint. Press {help} any time to see all controls."]
	for s in QuestsData.STEPS:
		texts.append(String(s.get("hint", "")))
	for t in texts:
		var out := UiUtil.fill_tokens(String(t), Callable(self, "_fake_label"))
		assert_false(out.contains("{"), "unreplaced token in hint: " + out)


## Tokens for the wardrobe and the Chapter Two build keys (D02 / D03); every token names a real, bound action, so
## onboarding's build tips switch from "Z" wording to the live {undo} / {recolor} tokens by themselves.
func test_wardrobe_and_build_tokens() -> void:
	var out := UiUtil.fill_tokens("{undo} {recolor} {variant} {wardrobe}", Callable(self, "_fake_label"))
	assert_eq(out, "<build_undo> <build_recolor> <build_variant> <wardrobe>")
	for tok in UiUtil.TOKEN_ACTIONS:
		var action := String(UiUtil.TOKEN_ACTIONS[tok])
		assert_true(Settings.DEFAULT_BINDINGS.has(action), "{%s} -> %s has a default key" % [tok, action])
		assert_true(InputMap.has_action(action), "{%s} -> %s is installed" % [tok, action])
	assert_eq(UiUtil.fill_tokens("{undo}", Callable(UiUtil, "settings_label")), Settings.action_label("build_undo"))
	var ob: Script = load("res://src/world/story_ch2/onboarding_hints.gd")
	assert_eq(String(ob.call("build_key", "build_undo", "undo")), "{undo}", "the undo tip uses the live token")
	assert_eq(String(ob.call("build_key", "build_recolor", "recolor")), "{recolor}", "the recolour tip uses the live token")


func test_real_labels_come_from_settings() -> void:
	var out := UiUtil.fill_tokens("{interact}", Callable(UiUtil, "settings_label"))
	assert_eq(out, Settings.action_label("interact"))
	assert_ne(out, "?", "interact is bound")


# --- toasts ------------------------------------------------------------------------------

func test_item_toasts_aggregate_within_window() -> void:
	var m: RefCounted = UiUtil.ToastModel.new()
	m.push_item("wood", 1)
	m.tick(0.5)
	m.push_item("wood", 1)
	m.tick(0.5)
	var e: Dictionary = m.push_item("wood", 1)
	assert_eq(m.entries.size(), 1, "one toast for repeated pickups")
	assert_eq(int(e["count"]), 3)
	assert_eq(String(e["text"]), "+3 %s" % ItemDB.display_name("wood"))
	m.push_item("stone", 2)
	assert_eq(m.entries.size(), 2, "different item -> new toast")


func test_item_toast_after_window_starts_new_entry_and_expires() -> void:
	var m: RefCounted = UiUtil.ToastModel.new()
	var first: Dictionary = m.push_item("berries", 2, 3.0)
	m.tick(m.window + 0.1)
	var second: Dictionary = m.push_item("berries", 1, 3.0)
	assert_ne(int(first["id"]), int(second["id"]), "outside the window a new toast appears")
	var gone: Array = m.tick(3.0)
	assert_true(gone.has(int(first["id"])) and gone.has(int(second["id"])), "both expire after their life")
	assert_eq(m.entries.size(), 0)


func test_text_toasts_merge_duplicates_and_cap_count() -> void:
	var m: RefCounted = UiUtil.ToastModel.new()
	m.push_text("Backpack full!", "warn")
	var e: Dictionary = m.push_text("Backpack full!", "warn")
	assert_eq(String(e["text"]), "Backpack full! (x2)")
	m.push_text("Backpack full!", "info")
	assert_eq(m.entries.size(), 2, "different kinds don't merge")
	for i in 10:
		m.push_text("note %d" % i, "info")
	assert_true(m.entries.size() <= m.max_entries, "never more than max entries")


# --- stack moves -----------------------------------------------------------------------------

func _inv(n: int) -> RefCounted:
	return Inventory.new(n)


func _total(inv: RefCounted, id: String) -> int:
	return int(inv.count_of(id))


func test_move_into_empty_slot() -> void:
	var a := _inv(4)
	a.set_slot(0, {"id": "wood", "count": 10})
	assert_true(UiUtil.move_stack(a, 0, a, 2, 10))
	assert_null(a.get_slot(0))
	assert_eq(int(a.get_slot(2)["count"]), 10)


func test_merge_respects_stack_limit() -> void:
	var a := _inv(4)
	a.set_slot(0, {"id": "wood", "count": 20})
	a.set_slot(1, {"id": "wood", "count": 90})
	assert_true(UiUtil.move_stack(a, 0, a, 1, 20))
	assert_eq(int(a.get_slot(1)["count"]), ItemDB.stack_max("wood"))
	assert_eq(int(a.get_slot(0)["count"]), 110 - ItemDB.stack_max("wood"), "remainder stays in the source")
	assert_eq(_total(a, "wood"), 110, "nothing lost")
	assert_false(UiUtil.move_stack(a, 0, a, 1, 5), "full target refuses")


func test_swap_whole_stacks_but_not_partial() -> void:
	var a := _inv(4)
	a.set_slot(0, {"id": "wood", "count": 5})
	a.set_slot(1, {"id": "stone", "count": 3})
	assert_false(UiUtil.move_stack(a, 0, a, 1, 2), "partial onto a different item is refused")
	assert_true(UiUtil.move_stack(a, 0, a, 1, 5))
	assert_eq(String(a.get_slot(0)["id"]), "stone")
	assert_eq(String(a.get_slot(1)["id"]), "wood")
	assert_false(UiUtil.move_stack(a, 1, a, 1, 5), "same slot is a no-op")


func test_split_and_cross_inventory_moves_conserve_items() -> void:
	var bag := _inv(8)
	var chest := _inv(5)
	bag.set_slot(3, {"id": "berries", "count": 7})
	var half := UiUtil.split_half(7)
	assert_eq(half, 4)
	assert_true(UiUtil.move_stack(bag, 3, chest, 0, half))
	assert_eq(_total(bag, "berries") + _total(chest, "berries"), 7)
	assert_eq(_total(chest, "berries"), 4)
	assert_eq(UiUtil.split_half(1), 1)
	assert_eq(UiUtil.split_half(2), 1)


func test_quick_move_between_hotbar_and_backpack() -> void:
	var a := _inv(16)
	a.set_slot(0, {"id": "wood", "count": 30})
	a.set_slot(10, {"id": "wood", "count": 95})
	var moved := UiUtil.quick_move_within(a, 0, 8)
	assert_eq(moved, 30)
	assert_null(a.get_slot(0), "hotbar slot emptied")
	assert_eq(int(a.get_slot(10)["count"]), ItemDB.stack_max("wood"), "existing stack filled first")
	assert_eq(_total(a, "wood"), 125)
	var back := UiUtil.quick_move_within(a, 10, 8)
	assert_eq(back, ItemDB.stack_max("wood"), "backpack -> hotbar")
	assert_true(a.get_slot(0) != null)


# --- clock & bindings ---------------------------------------------------------------------------

func test_clock_formatting_and_phases() -> void:
	assert_eq(UiUtil.format_clock(8.0), "08:00")
	assert_eq(UiUtil.format_clock(13.5), "13:30")
	assert_eq(UiUtil.format_clock(24.25), "00:15")
	assert_eq(UiUtil.day_phase(6.0), "Dawn")
	assert_eq(UiUtil.day_phase(9.0), "Morning")
	assert_eq(UiUtil.day_phase(14.0), "Afternoon")
	assert_eq(UiUtil.day_phase(19.0), "Evening")
	assert_eq(UiUtil.day_phase(23.0), "Night")
	assert_eq(UiUtil.day_phase(2.0), "Night")


static func _codes(action: String) -> Array:
	return {"jump": ["key:32"], "interact": ["key:69"], "map": ["key:77", "key:32"]}.get(action, [])


func test_binding_conflicts() -> void:
	var c := UiUtil.find_conflicts("jump", "key:32", ["jump", "interact", "map"], Callable(self, "_codes"))
	assert_eq(c, ["map"])
	assert_eq(UiUtil.find_conflicts("interact", "key:69", ["jump", "interact", "map"], Callable(self, "_codes")), [])


func test_bindable_events() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	k.pressed = true
	assert_true(UiUtil.is_bindable(k))
	assert_eq(UiUtil.event_code(k), "key:%d" % KEY_K)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	assert_false(UiUtil.is_bindable(esc), "Escape cancels, never binds")
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_J
	echo.pressed = true
	echo.echo = true
	assert_false(UiUtil.is_bindable(echo))
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.pressed = true
	assert_true(UiUtil.is_bindable(mb))
	assert_eq(UiUtil.event_code(mb), "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	# The wheel scrolls menus and zooms the camera: never a binding.
	for wb in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var w := InputEventMouseButton.new()
		w.button_index = wb
		w.pressed = true
		assert_false(UiUtil.is_bindable(w), "wheel button %d is not bindable" % int(wb))


func test_default_bindings_have_no_conflicts() -> void:
	var actions: Array = Settings.DEFAULT_BINDINGS.keys()
	for a in actions:
		for code in Settings.DEFAULT_BINDINGS[a]:
			var clashes := UiUtil.find_conflicts(String(a), String(code), actions, Callable(self, "_default_codes"))
			assert_eq(clashes.size(), 0, "%s shares %s with %s" % [a, code, str(clashes)])


static func _default_codes(action: String) -> Array:
	return Settings.DEFAULT_BINDINGS.get(action, [])


# --- items, lore, map ----------------------------------------------------------------------------

func test_item_stat_lines_come_from_item_db() -> void:
	var berries := UiUtil.item_stat_lines("berries")
	assert_true(berries.has("Restores %d health" % int(ItemDB.item("berries")["heal"])), str(berries))
	var axe := UiUtil.item_stat_lines("stone_axe")
	assert_true(axe.has("Damage %d" % int(ItemDB.item("stone_axe")["damage"])), str(axe))
	var joined := " ".join(PackedStringArray(axe))
	assert_true(joined.contains("Axe"), "tool kind shown")
	assert_eq(UiUtil.item_stat_lines("no_such_item").size(), 0)
	assert_eq(UiUtil.category_name("placeable"), "Buildable")


## Chapter Two: food buff lines (Moonpetal Tea's slow_resist), gear lines on request (the crafting card) and
## never the same gear line twice - also for the item slot / backpack card, which still append
## equipment_stat_lines themselves to the default lines.
func test_item_stat_lines_cover_food_buffs_and_gear() -> void:
	var tea := UiUtil.item_stat_lines("moonpetal_tea")
	var buff: Dictionary = ItemDB.item("moonpetal_tea").get("buff", {})
	if buff.has("slow_resist"):
		var pct := int(round((1.0 - float(buff["slow_resist"])) * 100.0))
		var found := false
		for l in tea:
			if String(l).contains("%d%%" % pct) and String(l).contains("slow"):
				found = true
		assert_true(found, "slow_resist line: %s" % str(tea))
	assert_eq(UiUtil._duration(90.0), "1 min 30 s")
	assert_eq(UiUtil._duration(120.0), "2 min")
	assert_eq(UiUtil._duration(45.0), "45 s")
	const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")
	var any_gear := false
	for id in ItemDB.all_item_ids():
		var gear: Array = ItemSlot.equipment_stat_lines(String(id))
		var base := UiUtil.item_stat_lines(String(id))
		for g in gear:
			assert_false(base.has(g), "%s: default lines leave gear lines to the slot tooltip (%s)" % [id, g])
		var full := UiUtil.item_stat_lines(String(id), true)
		for g2 in gear:
			assert_true(full.has(g2), "%s: with_gear includes %s" % [id, g2])
			any_gear = true
		var seen := {}
		for l2 in full:
			assert_false(seen.has(l2), "%s: '%s' printed once" % [id, l2])
			seen[l2] = true
		# what the item slot tooltip shows today: default lines + its own gear lines, each once
		var slot_lines := base.duplicate()
		slot_lines.append_array(gear)
		var seen2 := {}
		for l3 in slot_lines:
			assert_false(seen2.has(l3), "%s tooltip: '%s' printed once" % [id, l3])
			seen2[l3] = true
	assert_true(any_gear, "some item has gear lines")
	assert_eq(UiUtil.item_stat_lines("berries", true), UiUtil.item_stat_lines("berries"), "no gear lines for food")
	assert_eq(UiUtil.gear_stat_lines("no_such_item"), [])


## Chapter Two lore reads through LoreDB (every chapter's notes, arachnophobia-aware).
func test_lore_entry_reads_chapter_two_notes_through_lore_db() -> void:
	const LoreDB := preload("res://src/core/lore_db.gd")
	var ch2 := ""
	for id in LoreDB.ids():
		if String(id).begins_with("lore_ch2_"):
			ch2 = String(id)
			break
	if ch2 == "":
		return   # no Chapter Two lore files in this build: the fallback test covers lore_entry
	var want: Dictionary = LoreDB.get_lore(ch2)
	var e := UiUtil.lore_entry(ch2)
	if String(want["title"]).strip_edges() != "":
		assert_eq(String(e["title"]), String(want["title"]), "title of " + ch2)
	if String(want["text"]).strip_edges() != "":
		assert_eq(String(e["text"]), String(want["text"]), "text of " + ch2)
	var faded := UiUtil.lore_entry("lore_ch2_zz_missing")
	assert_eq(String(faded["text"]), "The page is too faded to read.", "unknown ids keep the faded page")


## One shared list decides the underground HUD look (spec section 9 area classes).
func test_underground_areas_share_one_list() -> void:
	for a in ["below", "tobin_annex", "hushed_works"]:
		assert_true(UiUtil.is_underground_area(a), a)
		assert_ne(UiUtil.hud_tint(a), Color.WHITE, a + " is tinted")
	for a2 in ["surface", "hallowmere_reach", "moonveil_manor", "echo_trial", "arena", ""]:
		assert_false(UiUtil.is_underground_area(a2), a2)
		assert_eq(UiUtil.hud_tint(a2), Color.WHITE, a2 + " untinted")
	const Combat := preload("res://src/combat/combat.gd")
	for a3 in Combat.INTENSITY_SCALED_AREAS:
		assert_true(UiUtil.is_underground_area(String(a3)), "combat's underground list agrees: " + String(a3))


func test_lore_entry_always_returns_readable_text() -> void:
	var e := UiUtil.lore_entry("miners_last_note_zz_unknown")
	assert_true(String(e["title"]) != "", "has a title")
	assert_true(String(e["text"]) != "", "has text")


func test_lore_entry_reads_the_lore_module_and_respects_arachnophobia() -> void:
	const LORE_PATH := "res://src/world/below/lore.gd"
	if not ResourceLoader.exists(LORE_PATH):
		return   # lore module not present in this build: the fallback test above covers it
	var lore: Script = load(LORE_PATH)
	var want: Dictionary = lore.call("get_lore", "foreman_order")
	var e := UiUtil.lore_entry("foreman_order")
	assert_eq(String(e["title"]), String(want["title"]), "journal shows the real lore title")
	assert_eq(String(e["text"]), String(want["text"]))
	var old: Variant = Settings.get_value("arachnophobia")
	Settings.values["arachnophobia"] = true
	var alt := UiUtil.lore_entry("hollows_page")
	Settings.values["arachnophobia"] = false
	var normal := UiUtil.lore_entry("hollows_page")
	Settings.values["arachnophobia"] = old
	assert_false(String(alt["title"]).to_lower().contains("silk"), "arachnophobia title avoids silk: %s" % alt["title"])
	assert_ne(String(alt["text"]), String(normal["text"]), "arachnophobia text differs")


func test_map_projection_round_trip_and_north_up() -> void:
	var r := Rect2(100, 50, 800, 800)
	var p := UiUtil.world_to_map(Vector2(0, 0), r, 110.0)
	assert_almost(p.x, 500.0, 0.01)
	assert_almost(p.y, 450.0, 0.01)
	var north := UiUtil.world_to_map(Vector2(0, -100), r, 110.0)
	assert_true(north.y < p.y, "north (-z) is up on the map")
	var back := UiUtil.map_to_world(UiUtil.world_to_map(Vector2(37.5, -12.0), r, 110.0), r, 110.0)
	assert_almost(back.x, 37.5, 0.01)
	assert_almost(back.y, -12.0, 0.01)
	assert_almost(UiUtil.map_heading(Vector3(0, 0, -1)), -PI * 0.5, 0.001, "facing north points up")
	assert_almost(UiUtil.map_heading(Vector3(1, 0, 0)), 0.0, 0.001, "facing east points right")


func test_craft_check_reports_missing_ingredients() -> void:
	fresh_state()
	var chk := UiUtil.craft_check("stone_axe", ["hand"])
	assert_false(bool(chk.get("ok", true)), "can't craft with an empty bag")
	GameState.give_item("wood", 3)
	GameState.give_item("stone", 2)
	GameState.give_item("fiber", 2)
	assert_true(bool(UiUtil.craft_check("stone_axe", ["hand"]).get("ok", false)), "exact ingredients are enough")
	assert_false(bool(UiUtil.craft_check("copper_sword", ["hand"]).get("ok", true)), "workbench recipe needs the station")
