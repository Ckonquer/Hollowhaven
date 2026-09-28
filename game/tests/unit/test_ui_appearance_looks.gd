extends "res://tests/test_case.gd"
## Look logic shared by the wardrobe and "Meet Krystal" (src/ui/panels/wardrobe_panel.gd Looks): ownership
## (starter / pattern / dye), locked choices refused with a "how to earn" line, outfits never touching hair
## or face, edits that keep unknown ids from a newer version, wearing (free, cosmetic, flag + event, never
## equipment or items), the reset to the Chapter One look, and the three named presets (save / rename /
## wear, persisted through save & load). Saves only go to user://test_saves/.

const Wardrobe := preload("res://src/ui/panels/wardrobe_panel.gd")
const Looks := Wardrobe.Looks

var _changed := 0


func _on_changed() -> void:
	_changed += 1


func before_each() -> void:
	fresh_state()
	_changed = 0
	Events.appearance_changed.connect(_on_changed)


func after_each() -> void:
	if Events.appearance_changed.is_connected(_on_changed):
		Events.appearance_changed.disconnect(_on_changed)
	SaveSystem.delete_test_saves()


func test_starter_items_are_owned_and_earnable_ones_are_not() -> void:
	var w := Looks.starter_wardrobe()
	assert_true(Looks.owned_part("explorer_jacket", w), "legacy piece")
	assert_true(Looks.owned_part("pinafore_skirt", w), "starter piece")
	assert_false(Looks.owned_part("witch_blouse", w), "earnable piece")
	assert_false(Looks.owned_part("no_such_part", w))
	assert_true(Looks.owned_swatch("rose", w))
	assert_false(Looks.owned_swatch("pumpkin", w), "dye swatch")
	assert_true(Looks.owned_outfit("strawberry_picnic", w))
	assert_false(Looks.owned_outfit("ribbon_witch", w))
	# Every starter outfit is wearable from the first minute (MP §4: never withhold all cute options).
	var starters := 0
	for id in ItemDB.appearance_table("outfits"):
		if bool(ItemDB.outfit(String(id)).get("starter", false)):
			starters += 1
			assert_true(Looks.owned_outfit(String(id), w), "starter outfit %s wearable" % id)
	assert_eq(starters, 6, "six starter looks")
	# Pattern ownership (GameState.unlock_pattern) unlocks every part of that pattern; dyes unlock swatches.
	var w2 := {"owned": ["pat_ribbon_witch", "pat_witch_hat"], "palettes": ["pumpkin"]}
	assert_true(Looks.owned_part("witch_blouse", w2))
	assert_true(Looks.owned_part("witch_dress", w2))
	assert_true(Looks.owned_part("witch_hat", w2))
	assert_true(Looks.owned_outfit("ribbon_witch", w2), "outfit needs both witch patterns")
	assert_false(Looks.owned_outfit("velvet_vampire", w2))
	assert_true(Looks.owned_swatch("pumpkin", w2))
	assert_true(Looks.owned_swatch("marigold", w2))
	assert_false(Looks.owned_swatch("midnight", w2))
	# A single part id in `owned` counts too.
	assert_true(Looks.owned_part("ribbon_bow", {"owned": ["ribbon_bow"]}))


func test_locked_choices_are_refused_and_say_how_to_earn() -> void:
	var w := Looks.starter_wardrobe()
	assert_true(Looks.can_choose("hair", "space_buns", w), "hair is always free")
	assert_true(Looks.can_choose("hair_color", "lavender", w))
	assert_true(Looks.can_choose("skin", "skin_5", w))
	assert_true(Looks.can_choose("eyes", "eye_8", w))
	assert_true(Looks.can_choose("hat", "", w), "optional slots may be empty")
	assert_false(Looks.can_choose("upper", "", w), "a top is never empty")
	assert_false(Looks.can_choose("upper", "harvest_skirt", w), "a skirt is not a top")
	assert_false(Looks.can_choose("hair", "mohawk", w), "unknown ids")
	assert_false(Looks.can_choose("upper", "witch_blouse", w))
	assert_false(Looks.can_choose("palette.primary", "midnight", w))
	assert_false(Looks.can_choose("palette.glitter", "rose", w), "unknown channel")
	assert_false(Looks.can_choose("outfit", "lanternwake_dress", w))
	var why := Looks.how_to_earn("upper", "witch_blouse", w)
	assert_true(why.begins_with("How to earn:") and why.contains("Manor"), why)
	assert_true(Looks.how_to_earn("palette.primary", "midnight", w).contains("Midnight Dye"))
	var o := Looks.how_to_earn("outfit", "velvet_vampire", w)
	assert_true(o.contains("Manor") and o.contains("velvet scraps"), "names every missing pattern: " + o)
	assert_eq(Looks.how_to_earn("hair", "bob", w), "", "nothing to earn")
	# Every earnable part and dye swatch explains itself.
	for pid in ItemDB.appearance_table("parts"):
		if not Looks.owned_part(String(pid), w):
			assert_true(Looks.how_to_earn(String(ItemDB.appearance_part(String(pid))["slot"]), String(pid), w).length() > 20, "how to earn %s" % pid)
	for sid in ItemDB.appearance_table("swatches"):
		if not Looks.owned_swatch(String(sid), w):
			assert_true(Looks.how_to_earn("palette.accent", String(sid), w).length() > 20, "how to earn %s" % sid)


func test_outfits_change_clothes_and_colours_never_hair_or_face() -> void:
	var l := ItemDB.legacy_look()
	l["hair"] = "bob"
	l["skin"] = "skin_4"
	l["eyes"] = "eye_3"
	var o := Looks.with_outfit(l, "mushroom_dungarees")
	assert_eq(String(o["hair"]), "bob")
	assert_eq(String(o["hair_color"]), "auburn")
	assert_eq(String(o["skin"]), "skin_4")
	assert_eq(String(o["eyes"]), "eye_3")
	assert_eq(String(o["lower"]), "dungarees")
	assert_eq(String(o["hat"]), "mushroom_beret")
	assert_eq(String(o["hair_acc"]), "", "empty optional slot")
	assert_eq(String(o["palette"]["primary"]), "moss")
	assert_eq(String(o["outfit"]), "mushroom_dungarees")
	assert_eq(String(l["lower"]), "explorer_trousers", "the input look is not modified")
	var c := Looks.with_choice(l, "palette.accent", "rose")
	assert_eq(String(c["palette"]["accent"]), "rose")
	assert_eq(String(l["palette"]["accent"]), "plum", "palette copied, not shared")
	assert_eq(ItemDB.sanitize_look(o)["missing"], [], "outfit looks are valid looks")


func test_edits_keep_unknown_ids_from_a_newer_version() -> void:
	var raw := ItemDB.legacy_look()
	raw["upper"] = "future_top"
	raw["palette"]["accent"] = "future_teal"
	raw["sparkle"] = {"level": 3}
	var shown: Dictionary = ItemDB.sanitize_look(raw)["look"]
	assert_eq(String(shown["upper"]), "explorer_jacket", "shown as the safe default")
	var edited := Looks.with_choice(shown, "hair", "bob")
	var merged := Looks.merge_edit(raw, shown, edited)
	assert_eq(String(merged["hair"]), "bob", "the edit is written")
	assert_eq(String(merged["upper"]), "future_top", "untouched unknown id kept")
	assert_eq(String(merged["palette"]["accent"]), "future_teal", "untouched unknown colour kept")
	assert_eq(merged["sparkle"], {"level": 3}, "unknown key kept")
	var edited2 := Looks.with_choice(shown, "upper", "puff_blouse")
	assert_eq(String(Looks.merge_edit(raw, shown, edited2)["upper"]), "puff_blouse", "a changed slot is written")
	# Through GameState: wearing a change keeps the rest of the saved data.
	GameState.appearance = raw.duplicate(true)
	assert_true(Looks.missing_ids().size() >= 2, "missing ids reported: %s" % str(Looks.missing_ids()))
	assert_true(Looks.wear(Looks.with_choice(Looks.current_look(), "eyes", "eye_6")))
	assert_eq(String(GameState.appearance["eyes"]), "eye_6")
	assert_eq(String(GameState.appearance["upper"]), "future_top")
	assert_eq(GameState.appearance["sparkle"], {"level": 3})


func test_wearing_is_free_cosmetic_and_marks_the_optional_goal() -> void:
	GameState.give_item("wood", 7)
	var inv_before: Array = GameState.inventory.to_array().duplicate(true)
	var eq_before: Dictionary = GameState.equipment.duplicate(true)
	var hp_before := float(GameState.player["hp"])
	assert_false(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)))
	assert_false(Looks.wear(Looks.current_look()), "no change, nothing written")
	assert_eq(_changed, 0)
	assert_false(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)), "an unchanged look is not a choice")
	var l := Looks.with_outfit(Looks.current_look(), "strawberry_picnic")
	assert_true(Looks.wear(l))
	assert_eq(_changed, 1, "Events.appearance_changed once")
	assert_eq(String(GameState.appearance["lower"]), "pinafore_skirt")
	assert_true(bool(GameState.get_flag(Wardrobe.LOOK_FLAG)), "A Look of Your Own")
	assert_eq(GameState.inventory.to_array(), inv_before, "the backpack is untouched")
	assert_eq(GameState.equipment, eq_before, "equipment untouched")
	assert_almost(float(GameState.player["hp"]), hp_before)
	# The optional log latches the goal from the flag.
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_look_of_your_own"), "goal completes from the flag")
	# Reset to the Chapter One look.
	assert_true(Looks.reset_to_legacy())
	assert_true(Looks.same_look(GameState.appearance, ItemDB.legacy_look()))
	assert_false(Looks.reset_to_legacy(), "already the legacy look")


func test_same_look_is_deep_and_order_free() -> void:
	var a := {"hair": "bob", "palette": {"primary": "rose", "accent": "plum"}}
	var b := {"palette": {"accent": "plum", "primary": "rose"}, "hair": "bob"}
	assert_true(Looks.same_look(a, b))
	b["palette"]["accent"] = "mint"
	assert_false(Looks.same_look(a, b))
	assert_true(Looks.same_look({"n": 1}, {"n": 1.0}), "JSON numbers")
	assert_false(Looks.same_look({"hair": "bob"}, {"hair": "bob", "x": ""}))


func test_presets_save_rename_wear_and_persist() -> void:
	assert_eq(ItemDB.preset_slots(), 3)
	assert_eq(Looks.presets().size(), 0)
	assert_false(Looks.save_preset(1), "a new preset fills the first empty slot")
	assert_true(Looks.save_preset(0))
	assert_eq(String(Looks.presets()[0]["name"]), "Cozy Explorer  ·  Side Braid", "descriptive default name")
	Looks.wear(Looks.with_choice(Looks.with_outfit(Looks.current_look(), "strawberry_picnic"), "hair", "twin_braids"))
	assert_true(Looks.save_preset(1, "  Picnic day  "))
	assert_eq(String(Looks.presets()[1]["name"]), "Picnic day", "trimmed")
	assert_true(Looks.save_preset(2, "", ItemDB.legacy_look()))
	assert_false(Looks.save_preset(3), "only three slots")
	assert_false(Looks.save_preset(-1))
	assert_eq(Looks.presets().size(), 3)
	# Rename (never empty, bounded length).
	assert_true(Looks.rename_preset(0, "Sunday best"))
	assert_eq(String(Looks.presets()[0]["name"]), "Sunday best")
	assert_false(Looks.rename_preset(0, "   "), "empty names are refused")
	assert_false(Looks.rename_preset(5, "x"))
	assert_true(Looks.rename_preset(2, "x".repeat(80)))
	assert_eq(String(Looks.presets()[2]["name"]).length(), Wardrobe.PRESET_NAME_MAX)
	# Overwriting keeps a name the player gave; an automatic name follows the new look.
	assert_true(Looks.save_preset(0))
	assert_eq(String(Looks.presets()[0]["name"]), "Sunday best")
	# Wear preset 0 (the picnic look now), then preset 1.
	Looks.reset_to_legacy()
	assert_true(Looks.apply_preset(0))
	assert_eq(String(GameState.appearance["lower"]), "pinafore_skirt")
	assert_eq(String(GameState.appearance["hair"]), "twin_braids")
	assert_false(Looks.apply_preset(7))
	# Persist through save / load.
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(Looks.presets().size(), 3)
	assert_eq(String(Looks.presets()[0]["name"]), "Sunday best")
	assert_eq(String(Looks.presets()[1]["name"]), "Picnic day")
	assert_eq(String(GameState.appearance["hair"]), "twin_braids")


func test_a_preset_never_puts_on_something_she_does_not_own() -> void:
	var l := ItemDB.legacy_look()
	l["hair"] = "braided_crown"
	l["upper"] = "witch_blouse"          # earnable, not owned
	l["palette"]["primary"] = "midnight" # dye, not owned
	l["back"] = "future_wings"           # unknown to this version
	GameState.wardrobe["presets"] = [{"name": "Dream", "look": l.duplicate(true)}]
	assert_true(Looks.apply_preset(0))
	assert_eq(String(GameState.appearance["hair"]), "braided_crown", "free choices applied")
	assert_eq(String(GameState.appearance["upper"]), "explorer_jacket", "locked piece skipped")
	assert_eq(String(GameState.appearance["palette"]["primary"]), "teal", "locked colour skipped")
	assert_eq(String(GameState.appearance["back"]), "satchel", "unknown id skipped")
	assert_eq(String(Looks.presets()[0]["look"]["upper"]), "witch_blouse", "the preset itself is unchanged")
	GameState.unlock_pattern("pat_ribbon_witch")
	Looks.apply_preset(0)
	assert_eq(String(GameState.appearance["upper"]), "witch_blouse", "worn once the pattern is owned")

## Everything spider-like needs the arachnophobia wording: the Moon Moth pattern comes from the Matron echo
## trial, and with arachnophobia on its "how to earn" line names the Hollow Mother instead (tile tooltips and
## the info line read it at the time they are shown).
func test_how_to_earn_honours_arachnophobia() -> void:
	var prev: Variant = Settings.get_value("arachnophobia")
	var w := Looks.starter_wardrobe()
	Settings.set_value("arachnophobia", false)
	var plain := Looks.how_to_earn("back", "moth_shawl", w)
	Settings.set_value("arachnophobia", true)
	var alt := Looks.how_to_earn("back", "moth_shawl", w)
	var alt_outfit := Looks.how_to_earn("outfit", "moon_moth_shawl", w)
	var others: Array = []
	for pid in ItemDB.appearance_table("parts"):
		if not Looks.owned_part(String(pid), w):
			others.append(Looks.how_to_earn(String(ItemDB.appearance_part(String(pid))["slot"]), String(pid), w))
	Settings.set_value("arachnophobia", prev)
	assert_true(plain.contains("Matron"), "the plain wording names the Matron: " + plain)
	assert_true(alt.contains("Hollow Mother") and not alt.contains("Matron"), "arachnophobia wording: " + alt)
	assert_true(alt_outfit.contains("Hollow Mother") and not alt_outfit.contains("Matron"), alt_outfit)
	for t in others:
		for word in ["Matron", "Weaver", "spider", "Spider", "web"]:
			assert_false(String(t).contains(word), "no '%s' with arachnophobia on: %s" % [word, t])


## The Echo Trial patterns (lead decision L09): locked pieces name the trial that earns them (the same line with
## arachnophobia on: nothing spider-like in them), and owning the pattern (a Loom recipe after the first clear)
## makes both of its pieces choosable; they are free to wear.
func test_echo_trial_pieces_say_how_to_earn_and_are_worn_once_owned() -> void:
	var prev: Variant = Settings.get_value("arachnophobia")
	var w := Looks.starter_wardrobe()
	var cases := [["hair_acc", "masquerade_mask", "Count Velour"], ["back", "opera_cloak", "Count Velour"],
		["hair_acc", "chime_ribbons", "Borrowed Choir"], ["back", "chorister_capelet", "Borrowed Choir"]]
	for mode in [false, true]:
		Settings.set_value("arachnophobia", mode)
		for c in cases:
			assert_false(Looks.can_choose(String(c[0]), String(c[1]), w), "%s is locked at first" % c[1])
			var why := Looks.how_to_earn(String(c[0]), String(c[1]), w)
			assert_true(why.begins_with("How to earn:") and why.contains(String(c[2])) and why.contains("Loom"), why)
	Settings.set_value("arachnophobia", prev)
	var owned := {"owned": ["pat_echo_masquerade"]}
	assert_true(Looks.can_choose("hair_acc", "masquerade_mask", owned))
	assert_true(Looks.can_choose("back", "opera_cloak", owned))
	assert_false(Looks.can_choose("back", "chorister_capelet", owned), "each trial owns its own pattern")
	GameState.unlock_pattern("pat_echo_chime")
	var inv_before: Array = GameState.inventory.to_array().duplicate(true)
	var l := Looks.with_choice(Looks.with_choice(Looks.current_look(), "hair_acc", "chime_ribbons"), "back", "chorister_capelet")
	assert_true(Looks.wear(l), "worn")
	assert_eq(String(GameState.appearance["hair_acc"]), "chime_ribbons")
	assert_eq(String(GameState.appearance["back"]), "chorister_capelet")
	assert_eq(GameState.inventory.to_array(), inv_before, "wearing costs nothing")
	assert_eq(ItemDB.sanitize_look(GameState.appearance)["missing"], [], "a valid look")
