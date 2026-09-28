extends "res://tests/test_case.gd"
## Appearance catalogue (MP 4, docs/CHAPTER_TWO_SPEC.md 4.1 / 8): complete tables, LEGACY_LOOK exactly as the
## lead fixed it (and its colours really are the Chapter One avatar's), outfits with genuinely different part
## sets, consistent ownership patterns / dyes, and the safe fallback for unknown cosmetic ids.

const AppearanceData := preload("res://data/appearance.gd")
const RecipesData := preload("res://data/recipes.gd")
const UnlocksData := preload("res://data/unlocks.gd")
const SourcesData := preload("res://data/sources.gd")
const Palette := preload("res://src/art/palette.gd")
const Avatar := preload("res://src/player/krystal_avatar.gd")

const SPEC_LEGACY_LOOK := {"hair": "side_braid", "hair_color": "auburn", "skin": "skin_2", "eyes": "eye_1",
	"upper": "explorer_jacket", "lower": "explorer_trousers", "shoes": "explorer_boots", "hat": "",
	"hair_acc": "flower_clip", "back": "satchel", "palette": {"primary": "teal", "secondary": "sunflower", "accent": "plum"},
	"outfit": "cozy_explorer"}
const HAIRSTYLES := ["side_braid", "bob", "long_waves", "high_ponytail", "twin_braids", "space_buns", "braided_crown", "half_up_ribbon"]
const HAIR_COLORS := ["auburn", "chestnut", "espresso", "raven", "honey", "platinum", "strawberry", "copper", "rose", "lavender", "mint", "sky", "silver"]
const STARTER_OUTFITS := ["cozy_explorer", "strawberry_picnic", "ribboned_adventurer", "cloud_cardigan", "moonflower_dress", "mushroom_dungarees"]
const EARNABLE_OUTFITS := ["pumpkin_patch", "ribbon_witch", "velvet_vampire", "ghostlight_party", "moon_moth_shawl", "lanternwake_dress"]
const DYES := ["rose", "pumpkin", "lavender", "cream", "ember", "midnight"]


func test_tables_are_complete() -> void:
	assert_eq(AppearanceData.HAIRSTYLES.keys(), HAIRSTYLES, "the eight MP hairstyles, legacy first")
	for hc in HAIR_COLORS:
		assert_true(AppearanceData.HAIR_COLORS.has(hc), "hair colour " + hc)
	assert_true(AppearanceData.HAIR_COLORS.size() >= 12)
	for h in AppearanceData.HAIR_COLORS:
		for k in ["base", "dark", "light"]:
			assert_true(AppearanceData.HAIR_COLORS[h][k] is Color, "%s %s colour" % [h, k])
	assert_eq(AppearanceData.SKIN_TONES.keys(), ["skin_1", "skin_2", "skin_3", "skin_4", "skin_5", "skin_6"])
	assert_eq(AppearanceData.EYE_COLORS.keys(), ["eye_1", "eye_2", "eye_3", "eye_4", "eye_5", "eye_6", "eye_7", "eye_8"])
	for oid in STARTER_OUTFITS:
		assert_true(bool(AppearanceData.OUTFITS[oid]["starter"]), oid + " is a starter look")
	for oid2 in EARNABLE_OUTFITS:
		assert_false(bool(AppearanceData.OUTFITS[oid2]["starter"]), oid2 + " is earnable")
	assert_eq(AppearanceData.OUTFITS.size(), 12)
	assert_eq(AppearanceData.PRESET_SLOTS, 3)
	for sw in ["rose", "lavender", "cream", "mint", "sky", "plum", "oat", "caramel", "cocoa"]:
		assert_true(bool(AppearanceData.SWATCHES[sw]["starter"]), "palette choice %s is free" % sw)
	assert_eq(AppearanceData.DYE_PALETTES.keys(), DYES)
	assert_eq(AppearanceData.SLOTS, ["upper", "lower", "shoes", "hat", "hair_acc", "back"])


func test_legacy_look_equals_spec_section_8() -> void:
	assert_eq(AppearanceData.LEGACY_LOOK, SPEC_LEGACY_LOOK)
	var copy := ItemDB.legacy_look()
	assert_eq(copy, SPEC_LEGACY_LOOK)
	copy["palette"]["primary"] = "rose"
	copy["hair"] = "bob"
	assert_eq(AppearanceData.LEGACY_LOOK, SPEC_LEGACY_LOOK, "legacy_look() hands out a deep copy")
	var o: Dictionary = AppearanceData.OUTFITS["cozy_explorer"]
	for slot in AppearanceData.SLOTS:
		assert_eq(String(o["parts"][slot]), String(SPEC_LEGACY_LOOK[slot]), "Cozy Explorer %s = the legacy look" % slot)
	assert_eq(o["palette"], SPEC_LEGACY_LOOK["palette"])


func test_legacy_look_reproduces_the_chapter_one_avatar() -> void:
	var lk: Dictionary = AppearanceData.LEGACY_LOOK
	assert_eq(AppearanceData.SKIN_TONES[lk["skin"]]["base"], Palette.K_SKIN, "skin_2 = K_SKIN f0c6a0")
	assert_eq(AppearanceData.SKIN_TONES[lk["skin"]]["blush"], Avatar.BLUSH)
	var hair: Dictionary = AppearanceData.HAIR_COLORS[lk["hair_color"]]
	assert_eq(hair["base"], Palette.K_HAIR, "auburn = K_HAIR 7a3b2e")
	assert_eq(hair["dark"], Avatar.HAIR_DARK)
	assert_eq(hair["light"], Avatar.HAIR_LIGHT)
	assert_eq(AppearanceData.EYE_COLORS[lk["eyes"]]["iris"], Avatar.EYE_WARM, "eye_1 = the current iris colour")
	assert_eq(AppearanceData.EYE_COLORS[lk["eyes"]]["dark"], Avatar.EYE_DARK)
	var pal: Dictionary = lk["palette"]
	assert_eq(AppearanceData.SWATCHES[pal["primary"]]["color"], Palette.K_JACKET, "teal = K_JACKET")
	assert_eq(AppearanceData.SWATCHES[pal["secondary"]]["color"], Palette.K_SCARF, "sunflower = K_SCARF")
	assert_eq(AppearanceData.SWATCHES[pal["accent"]]["color"], Palette.K_PANTS, "plum = K_PANTS")
	var jacket: Dictionary = AppearanceData.PARTS["explorer_jacket"]
	assert_eq(jacket["channels"], {"jacket": "primary", "scarf": "secondary"})
	assert_eq(jacket["fixed"]["shirt"], Palette.K_SHIRT)
	assert_eq(jacket["fixed"]["buttons"], Avatar.BRASS)
	assert_eq(AppearanceData.PARTS["explorer_trousers"]["channels"], {"trousers": "accent"})
	var boots: Dictionary = AppearanceData.PARTS["explorer_boots"]["fixed"]
	assert_eq(boots["boots"], Palette.K_BOOTS)
	assert_eq(boots["cuff"], Avatar.BOOT_LIGHT)
	assert_eq(boots["sole"], Avatar.LEATHER)
	assert_eq(AppearanceData.PARTS["satchel"]["fixed"]["bag"], Palette.K_BAG)
	assert_eq(AppearanceData.PARTS["flower_clip"]["fixed"]["petals"], Palette.FLOWER_WHITE)
	assert_eq(AppearanceData.PARTS["flower_clip"]["fixed"]["centre"], Palette.FLOWER_YELLOW)
	assert_eq(AppearanceData.SWATCHES["cream"]["color"], Palette.K_SHIRT)
	assert_eq(AppearanceData.SWATCHES["leather"]["color"], Palette.K_BOOTS)
	assert_eq(AppearanceData.SWATCHES["satchel"]["color"], Palette.K_BAG)
	for table in [AppearanceData.HAIRSTYLES, AppearanceData.HAIR_COLORS, AppearanceData.SKIN_TONES, AppearanceData.EYE_COLORS]:
		var legacy_count := 0
		for k in table:
			if bool(table[k].get("legacy", false)):
				legacy_count += 1
		assert_eq(legacy_count, 1, "exactly one legacy entry per table")


func test_parts_are_consistent() -> void:
	var meshes := {}
	var starters_per_slot := {}
	for pid in AppearanceData.PARTS:
		var p: Dictionary = AppearanceData.PARTS[pid]
		assert_true(AppearanceData.SLOTS.has(p["slot"]), pid + " slot")
		assert_true(String(p["name"]) != "", pid + " name")
		assert_false(meshes.has(p["mesh"]), pid + " has its own mesh builder")
		meshes[p["mesh"]] = true
		assert_true(p["skirt"] is bool and p["hides_hair"] is bool and p["starter"] is bool, pid + " flags")
		if bool(p["starter"]):
			assert_eq(String(p["pattern"]), "", pid + " starter parts need no pattern")
			starters_per_slot[p["slot"]] = int(starters_per_slot.get(p["slot"], 0)) + 1
		else:
			var pat := ItemDB.pattern(String(p["pattern"]))
			assert_false(pat.is_empty(), pid + " pattern exists")
			assert_true((pat.get("parts", []) as Array).has(pid), pid + " is granted by its pattern")
		for part_key in p["channels"]:
			assert_true(AppearanceData.PALETTE_CHANNELS.has(p["channels"][part_key]), "%s channel %s" % [pid, part_key])
		for fixed_key in p["fixed"]:
			assert_true(p["fixed"][fixed_key] is Color, "%s fixed %s colour" % [pid, fixed_key])
		if p["slot"] == "lower":
			assert_true(String(p.get("style", "")) != "", pid + " lower garment style")
		if bool(p["skirt"]):
			assert_eq(String(p["slot"]), "lower", pid + " only lower garments sway as skirts")
	for slot in AppearanceData.SLOTS:
		assert_true(int(starters_per_slot.get(slot, 0)) >= 2, "attractive free choices for " + slot)
	assert_eq(ItemDB.parts_for_slot("lower").size(), 12)
	assert_true(ItemDB.parts_for_slot("hat").has("witch_hat"))


func test_outfits_are_distinct_complete_looks() -> void:
	var ids: Array = AppearanceData.OUTFITS.keys()
	var starter_styles := {}
	var earnable_capes := 0
	var skirts := 0
	for oid in ids:
		var o: Dictionary = AppearanceData.OUTFITS[oid]
		var needs: Array = o["unlock"].get("patterns", [])
		assert_eq(String(o["unlock"]["kind"]), "starter" if bool(o["starter"]) else "pattern", oid + " unlock kind")
		assert_true(AppearanceData.HAIRSTYLES.has(o["hair"]) and AppearanceData.HAIR_COLORS.has(o["hair_color"]), oid + " preview hair")
		assert_true(String(o["desc"]) != "")
		for slot in AppearanceData.SLOTS:
			assert_true((o["parts"] as Dictionary).has(slot), "%s has a %s entry" % [oid, slot])
			var pid := String(o["parts"][slot])
			if pid == "":
				assert_true(AppearanceData.OPTIONAL_SLOTS.has(slot), "%s leaves only optional slots empty" % oid)
				continue
			var p := ItemDB.appearance_part(pid)
			assert_eq(String(p.get("slot", "")), slot, "%s %s part %s fits the slot" % [oid, slot, pid])
			if bool(o["starter"]):
				assert_true(bool(p["starter"]), "%s: starter looks use only free parts (%s)" % [oid, pid])
			elif not bool(p["starter"]):
				assert_true(needs.has(p["pattern"]), "%s lists the pattern that owns %s" % [oid, pid])
			if bool(p.get("cape", false)) and not bool(o["starter"]):
				earnable_capes += 1
			if bool(p["skirt"]):
				skirts += 1
		for ch in AppearanceData.PALETTE_CHANNELS:
			assert_true(bool(AppearanceData.SWATCHES[o["palette"][ch]]["starter"]), "%s palette uses free swatches" % oid)
		if bool(o["starter"]):
			starter_styles[ItemDB.appearance_part(String(o["parts"]["lower"]))["style"]] = true
	for style in ["trousers", "pinafore", "pleated_skirt", "dress", "dungarees"]:
		assert_true(starter_styles.has(style), "a starter look with " + style)
	assert_true(earnable_capes >= 2, "earnable capes / shawls")
	assert_true(skirts >= 8, "plenty of skirts and dresses")
	# genuinely different silhouettes: every pair differs in at least three garment slots
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = AppearanceData.OUTFITS[ids[i]]["parts"]
			var b: Dictionary = AppearanceData.OUTFITS[ids[j]]["parts"]
			var diff := 0
			for slot2 in AppearanceData.SLOTS:
				if a[slot2] != b[slot2]:
					diff += 1
			assert_true(diff >= 3, "%s and %s are more than recolours (%d slots differ)" % [ids[i], ids[j], diff])
			assert_ne(a["lower"], b["lower"], "%s and %s have different lower garments" % [ids[i], ids[j]])


func test_patterns_and_dye_palettes() -> void:
	for pat_id in AppearanceData.PATTERNS:
		var pat: Dictionary = AppearanceData.PATTERNS[pat_id]
		assert_false((pat["parts"] as Array).is_empty())
		for pid in pat["parts"]:
			assert_eq(String(ItemDB.appearance_part(pid).get("pattern", "")), pat_id, "%s grants %s" % [pat_id, pid])
		var rid := String(pat["recipe"])
		if rid != "":
			assert_eq(String(RecipesData.SPECIAL_RECIPES[rid]["pattern"]), pat_id, pat_id + " recipe")
			assert_true(UnlocksData.UNLOCK_FLAGS.has(String(pat["flag"])), pat_id + " unlock flag declared")
		else:
			var rw := String(pat["reward"])
			assert_true((ItemDB.reward_bundle(rw).get("patterns", []) as Array).has(pat_id), pat_id + " granted by its reward")
		assert_true(String(pat["source"]).length() > 10, pat_id + " tells the player where it comes from")
	for dye in AppearanceData.DYE_PALETTES:
		var d: Dictionary = AppearanceData.DYE_PALETTES[dye]
		assert_true(d["tint"] is Color)
		assert_eq(String(d["station"]), "loom")
		assert_false((d["cost"] as Dictionary).is_empty(), dye + " has an unlock cost")
		for ing in d["cost"]:
			assert_true(ItemDB.has_item(ing) and not ItemDB.is_quest_item(ing), "%s cost %s" % [dye, ing])
		for sw in d["swatches"]:
			assert_eq(String(AppearanceData.SWATCHES[sw].get("dye", "")), dye, "%s unlocks %s" % [dye, sw])
	for sw2 in AppearanceData.SWATCHES:
		var s: Dictionary = AppearanceData.SWATCHES[sw2]
		assert_true(s["color"] is Color)
		if not bool(s["starter"]):
			assert_true(AppearanceData.DYE_PALETTES.has(String(s["dye"])), sw2 + " belongs to a dye palette")
	assert_eq(ItemDB.dye_palette("rose")["cost"], {"roseberries": 4})
	assert_eq(ItemDB.dye_palette("ember")["cost"], {"resin": 2, "berries": 3}, "MP 16: ember = resin + berry")
	assert_eq(ItemDB.dye_palette("midnight")["cost"], {"moonpetal": 2, "echo_shard": 1}, "MP 16: midnight = moonpetal + echo shard")
	assert_eq(ItemDB.dye_palette("nope"), {})


## Echo Trial first-clear patterns (MP 15 "unique cosmetic patterns"; lead decision L09): Moonlit Masquerade (Count
## Velour) and Chime Chorister (Borrowed Choir), each a hair accessory + a cape, sewn at the Loom once the trial's
## first-clear flag is set. The mask is a hair ornament (hair_acc), never a hat or face covering.
func test_echo_trial_patterns() -> void:
	var want := {
		"pat_echo_masquerade": {"name": "Moonlit Masquerade", "parts": ["masquerade_mask", "opera_cloak"],
			"recipe": "pattern_echo_masquerade", "flag": "ch2_trial_velour", "cost": {"woven_cloth": 3, "lantern_wax": 2},
			"meshes": ["acc_masquerade_mask", "back_opera_cloak"], "trial": "Count Velour"},
		"pat_echo_chime": {"name": "Chime Chorister", "parts": ["chime_ribbons", "chorister_capelet"],
			"recipe": "pattern_echo_chime", "flag": "ch2_trial_choir", "cost": {"woven_cloth": 3, "echo_shard": 2},
			"meshes": ["acc_chime_ribbons", "back_chorister_capelet"], "trial": "Borrowed Choir"},
	}
	for pat_id in want:
		var w: Dictionary = want[pat_id]
		var pat := ItemDB.pattern(String(pat_id))
		assert_eq(String(pat.get("name", "")), String(w["name"]), pat_id + " name")
		assert_eq(pat.get("parts", []), w["parts"], pat_id + " parts")
		assert_eq(String(pat.get("recipe", "")), String(w["recipe"]), pat_id + " recipe")
		assert_eq(String(pat.get("flag", "")), String(w["flag"]), pat_id + " flag")
		assert_eq(String(pat.get("source", "")), "First clear of the %s echo trial; sew it at the Loom." % w["trial"], pat_id + " source")
		assert_eq(RecipesData.SPECIAL_RECIPES.get(String(w["recipe"]), {}), {"result": "", "count": 0, "station": "loom",
			"ingredients": w["cost"], "unlock": w["flag"], "pattern": pat_id}, pat_id + " Loom recipe")
		assert_true(UnlocksData.UNLOCK_FLAGS.has(String(w["flag"])), String(w["flag"]) + " declared in data/unlocks.gd")
		var slots: Array = []
		for i in (w["parts"] as Array).size():
			var pid := String(w["parts"][i])
			var p := ItemDB.appearance_part(pid)
			slots.append(String(p.get("slot", "")))
			assert_eq(String(p.get("mesh", "")), String(w["meshes"][i]), pid + " mesh builder id")
			assert_false(bool(p.get("starter", true)), pid + " is earned")
			assert_eq(String(p.get("pattern", "")), pat_id, pid + " is owned through its pattern")
			assert_false((p.get("channels", {}) as Dictionary).is_empty(), pid + " follows the palette")
			assert_false(bool(p.get("hides_hair", true)) or bool(p.get("skirt", true)), pid + " flags")
			if String(p.get("slot", "")) == "back":
				assert_true(bool(p.get("cape", false)), pid + " is a cape (hides the jacket back patch)")
		assert_eq(slots, ["hair_acc", "back"], pat_id + ": a hair accessory and a cape")
	assert_true(ItemDB.parts_for_slot("hair_acc").has("masquerade_mask"), "the mask is a hair accessory")
	assert_false(ItemDB.parts_for_slot("hat").has("masquerade_mask"))


## Integration pass 3 palette decisions (R3-26..R3-30; visual review AV-10, AV-13, AV-14, AV-15). Only the presets and
## part channels change: a saved look stores swatch ids, so it keeps its own colours.
func test_pass3_preset_palettes_and_channels() -> void:
	var gl: Dictionary = AppearanceData.OUTFITS["ghostlight_party"]
	assert_eq(String(gl["hair_color"]), "lavender", "R3-26: Ghostlight Party suggests lavender hair")
	assert_eq(gl["palette"], {"primary": "sky", "secondary": "snow", "accent": "lavender"}, "R3-26: sky cloth, snow trim")
	var pp: Dictionary = AppearanceData.OUTFITS["pumpkin_patch"]
	assert_eq(String(pp["hair_color"]), "espresso", "R3-27: Pumpkin Patch suggests espresso hair")
	assert_eq(pp["palette"], {"primary": "caramel", "secondary": "cream", "accent": "moss"}, "R3-27: pumpkin-and-vine palette")
	assert_eq(AppearanceData.PARTS["harvest_skirt"]["channels"], {"skirt": "accent"}, "the harvest skirt follows the moss accent")
	assert_eq(AppearanceData.PARTS["leaf_clip"]["channels"], {}, "the leaf clip keeps its fixed orange")
	assert_eq(AppearanceData.PARTS["mushroom_beret"]["channels"], {"beret": "accent"}, "R3-28: the beret is a toadstool (accent)")
	var md: Dictionary = AppearanceData.OUTFITS["mushroom_dungarees"]
	assert_eq(String(md["palette"]["accent"]), "berry", "berry red toadstool in the Mushroom Dungarees preset")
	assert_ne(md["palette"]["accent"], md["palette"]["primary"], "the beret no longer matches the dungarees")
	var cap: Dictionary = AppearanceData.PARTS["chorister_capelet"]["channels"]
	assert_eq(cap, {"capelet": "secondary", "collar": "accent"}, "R3-30: capelet secondary, collar accent")
	assert_eq(String(cap.values()[0]), "secondary", "the wardrobe tile (first channel) shows the capelet colour")
	# the reviewed looks read clearly: the suggested hair never blends into the main cloth (the avatar's own contrast
	# metric, accessory_builder.gd _close) and no preset is a pale blob (near-white hair on near-white cloth)
	for oid in AppearanceData.OUTFITS:
		var o: Dictionary = AppearanceData.OUTFITS[oid]
		var hair: Color = AppearanceData.HAIR_COLORS[o["hair_color"]]["base"]
		var cloth := ItemDB.swatch_color(String(o["palette"]["primary"]))
		var d := absf(hair.r - cloth.r) + absf(hair.g - cloth.g) + absf(hair.b - cloth.b)
		assert_true(d >= 0.18, "%s: %s hair stands out from the %s cloth (%.2f)" % [oid, o["hair_color"], o["palette"]["primary"], d])
		assert_false(hair.get_luminance() > 0.8 and cloth.get_luminance() > 0.8, "%s is not an all-white figure" % oid)


func test_sanitize_look_keeps_a_safe_visible_default() -> void:
	var ok := ItemDB.sanitize_look(AppearanceData.LEGACY_LOOK)
	assert_eq(ok["look"], SPEC_LEGACY_LOOK)
	assert_eq(ok["missing"], [])
	var look := ItemDB.legacy_look()
	look["hair"] = "future_curls"
	look["upper"] = "moonflower_dress"          # a lower part in the upper slot
	look["hat"] = ""
	look["back"] = "jetpack_2099"
	look["palette"]["accent"] = "neon"
	look["lower"] = "dungarees"
	var before := look.duplicate(true)
	var res := ItemDB.sanitize_look(look)
	assert_eq(look, before, "the caller's look (the saved data) is never modified")
	var fixed: Dictionary = res["look"]
	assert_eq(fixed["hair"], "side_braid")
	assert_eq(fixed["upper"], "explorer_jacket")
	assert_eq(fixed["back"], "satchel")
	assert_eq(fixed["palette"]["accent"], "plum")
	assert_eq(fixed["lower"], "dungarees", "valid choices are kept")
	assert_eq(fixed["hat"], "", "an empty optional slot is valid")
	for m in ["hair=future_curls", "upper=moonflower_dress", "back=jetpack_2099", "palette.accent=neon"]:
		assert_true((res["missing"] as Array).has(m), "reports " + m)
	var junk := ItemDB.sanitize_look("not a look")
	assert_eq(junk["look"], SPEC_LEGACY_LOOK, "garbage falls back to the legacy look")
	var partial := ItemDB.sanitize_look({"hair": "bob", "shoes": "wellies"})
	assert_eq(partial["look"]["hair"], "bob")
	assert_eq(partial["look"]["shoes"], "wellies")
	assert_eq(partial["look"]["upper"], "explorer_jacket", "missing keys take the legacy value")
	assert_eq(partial["missing"], [])


func test_itemdb_appearance_accessors() -> void:
	for t in ["hairstyles", "hair_colors", "skin_tones", "eye_colors", "parts", "outfits", "swatches", "dye_palettes", "patterns"]:
		assert_false(ItemDB.appearance_table(t).is_empty(), t)
	assert_eq(ItemDB.appearance_table("nope"), {})
	assert_eq(ItemDB.swatch_color("teal"), Palette.K_JACKET)
	assert_eq(ItemDB.swatch_color("unknown_swatch"), Color.WHITE)
	assert_eq(ItemDB.preset_slots(), 3)
	assert_eq(String(ItemDB.outfit("ribbon_witch")["parts"]["hat"]), "witch_hat")
	assert_eq(ItemDB.outfit("nope"), {})
	assert_eq(ItemDB.appearance_part("nope"), {})
