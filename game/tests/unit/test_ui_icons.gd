extends "res://tests/test_case.gd"
## Procedural icon factory: every item has a real drawing, images are valid stickers, caching works,
## the arachnophobia swap turns silk into a thread spool, and unknown ids get the fallback.

const IconFactory := preload("res://src/ui/icon_factory.gd")
const ItemsData := preload("res://data/items.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")

var _arachno_before: Variant = false


func before_each() -> void:
	_arachno_before = Settings.get_value("arachnophobia")


func after_each() -> void:
	Settings.values["arachnophobia"] = _arachno_before


static func _alpha_stats(img: Image) -> Dictionary:
	var opaque := 0
	var total := img.get_width() * img.get_height()
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	return {"coverage": float(opaque) / float(total / 4), "corner": img.get_pixel(0, 0).a, "center": img.get_pixel(img.get_width() / 2, img.get_height() / 2).a}


func test_every_item_icon_id_has_a_drawing() -> void:
	var used := {}
	for id in ItemsData.ITEMS:
		var icon := String(ItemsData.ITEMS[id].get("icon", ""))
		used[icon] = true
		assert_true(IconFactory.has_drawing(icon), "item %s uses icon '%s' with no drawing" % [id, icon])
	for icon in IconFactory.ITEM_ICONS:
		assert_true(used.has(icon), "ITEM_ICONS lists '%s' but no item uses it" % icon)


func test_all_item_icons_render_as_stickers() -> void:
	var t0 := Time.get_ticks_msec()
	var seen := {}
	for id in ItemDB.all_item_ids():
		var icon := IconFactory.item_icon_id(String(id))
		if seen.has(icon):
			continue
		seen[icon] = true
		var img := IconFactory.render(icon, IconFactory.item_color(String(id)), 96)
		assert_eq(img.get_width(), 96, icon)
		assert_eq(img.get_height(), 96, icon)
		var st := _alpha_stats(img)
		assert_true(float(st["coverage"]) > 0.12, "%s is almost empty (%.2f)" % [icon, st["coverage"]])
		assert_true(float(st["coverage"]) < 0.93, "%s fills the whole square (%.2f)" % [icon, st["coverage"]])
		assert_true(float(st["corner"]) < 0.05, "%s: corners stay transparent" % icon)
	var ms := Time.get_ticks_msec() - t0
	assert_true(ms < 20000, "icons render in reasonable time (%d ms)" % ms)


func test_icons_are_distinct() -> void:
	var a := IconFactory.render("log", Color("b07a4f")).get_data()
	var b := IconFactory.render("stone", Color("a9a39a")).get_data()
	var c := IconFactory.render("log", Color("b07a4f")).get_data()
	assert_ne(a, b, "different drawings differ")
	assert_eq(a, c, "rendering is deterministic")


func test_textures_are_cached() -> void:
	var t1 := IconFactory.item_icon("berries")
	var t2 := IconFactory.item_icon("berries")
	assert_not_null(t1)
	assert_true(t1 == t2, "same texture instance from the cache")
	assert_true(t1 is Texture2D)
	assert_eq(t1.get_width(), 96)


func test_arachnophobia_turns_silk_into_a_spool() -> void:
	Settings.values["arachnophobia"] = false
	assert_eq(IconFactory.item_icon_id("silk"), "silk")
	var normal := IconFactory.item_icon("silk")
	Settings.values["arachnophobia"] = true
	assert_eq(IconFactory.item_icon_id("silk"), "spool")
	var alt := IconFactory.item_icon("silk")
	assert_true(normal != alt, "a different texture is shown")
	assert_ne(IconFactory.render("silk", Color.WHITE).get_data(), IconFactory.render("spool", Color.WHITE).get_data())
	assert_eq(IconFactory.item_icon_id("wood"), "log", "other items are unaffected")


func test_unknown_ids_get_a_tidy_fallback() -> void:
	assert_false(IconFactory.has_drawing("definitely_not_an_icon"))
	var img := IconFactory.render("definitely_not_an_icon", Color.WHITE)
	var st := _alpha_stats(img)
	assert_true(float(st["coverage"]) > 0.2, "fallback is visible")
	assert_eq(IconFactory.item_icon_id("no_such_item"), "unknown")
	assert_not_null(IconFactory.item_icon("no_such_item"))


func test_portraits_and_glyphs() -> void:
	for id in ItemDB.creature_ids():
		assert_true(IconFactory.has_drawing("portrait_" + String(id)), "portrait for " + String(id))
		var img := IconFactory.render("portrait_" + String(id), Color.WHITE, 128)
		assert_eq(img.get_width(), 128)
		assert_true(float(_alpha_stats(img)["center"]) > 0.9, "portrait centre is opaque")
	var g := IconFactory.glyph("switch_on", 68, 38)
	assert_eq(g.get_width(), 68)
	assert_eq(g.get_height(), 38)


## The Reach map asks for its own district stickers (map_view.gd REACH_ICONS [preferred glyph, fallback]): every
## preferred glyph has a real drawing (so the fallback item icons are no longer used), renders as a tidy sticker
## and differs from the fallback and from the other districts.
func test_reach_map_glyphs_have_drawings() -> void:
	var reach_icons: Dictionary = MapView.REACH_ICONS
	var fallback := IconFactory.render("definitely_not_an_icon", Color.WHITE).get_data()
	var seen := {}
	for id in reach_icons:
		var glyph := String(reach_icons[id][0])
		assert_true(IconFactory.has_drawing(glyph), "%s has a drawing for %s" % [glyph, id])
		assert_eq(MapView.place_icon(String(id), "hallowmere_reach"), glyph, "the Reach map uses %s for %s" % [glyph, id])
		if seen.has(glyph):
			continue
		var img := IconFactory.render(glyph, Color.WHITE, 96)
		var st := _alpha_stats(img)
		assert_true(float(st["coverage"]) > 0.12, "%s is almost empty (%.2f)" % [glyph, st["coverage"]])
		assert_true(float(st["coverage"]) < 0.93, "%s fills the whole square (%.2f)" % [glyph, st["coverage"]])
		assert_true(float(st["corner"]) < 0.05, "%s: corners stay transparent" % glyph)
		var data := img.get_data()
		assert_ne(data, fallback, "%s is not the fallback drawing" % glyph)
		for other in seen:
			assert_ne(data, seen[other], "%s differs from %s" % [glyph, other])
		seen[glyph] = data
	for g in ["map_lantern", "map_glasshouse", "map_pumpkin", "map_candle", "map_manor", "map_bell"]:
		assert_true(IconFactory.EXTRA_ICONS.has(g), g + " listed in EXTRA_ICONS")
