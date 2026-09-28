extends "res://tests/test_case.gd"
## R111: the district notes' fallback copies in data/reach_west.gd are identical to the region's lore texts
## (data/lore_ch2_reach.gd, read through LoreDB), and the Groundskeeper's second note sends her to the side of the
## Candleyard where the empty candle dish really is (south-west of the centre).

const LoreData := preload("res://data/lore_ch2_reach.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const West := preload("res://data/reach_west.gd")


func test_fallback_copies_match_the_lore_file() -> void:
	LoreDB.reload()
	assert_true(West.LORE_FALLBACK.size() >= 3, "garden note and both groundskeeper notes have fallbacks")
	for id in West.LORE_FALLBACK:
		assert_true(LoreData.LORE.has(id), "%s is written in the lore file" % id)
		if not LoreData.LORE.has(id):
			continue
		var fb: Dictionary = West.LORE_FALLBACK[id]
		var lore: Dictionary = LoreData.LORE[id]
		assert_eq(String(fb["title"]), String(lore["title"]), "%s: same title in both copies" % id)
		assert_eq(String(fb["text"]), String(lore["text"]), "%s: same text in both copies" % id)
		assert_eq(String(LoreDB.get_lore(String(id))["text"]), String(lore["text"]), "%s: LoreDB shows that text" % id)


func test_second_note_points_to_the_dish() -> void:
	var text := String(LoreData.LORE[West.LORE_GROUNDSKEEPER_2]["text"])
	assert_true(text.contains("The empty dish by the south-west wall."), "the note names the south-west wall: " + text)
	assert_false(text.contains("by the west wall"), "no longer the west wall")
	# atan2(z, x) in degrees: 90 = south, 180 = west (the data/reach_west.gd WALL_GATES convention)
	var d: Vector2 = West.MARKER - West.CANDLEYARD_CENTER
	var deg := rad_to_deg(atan2(d.y, d.x))
	assert_true(deg > 112.5 and deg < 157.5, "the empty dish lies south-west of the Candleyard centre (%.0f deg)" % deg)
	assert_true(d.length() < float(West.WALL_RADIUS), "and inside the memory wall (%.1f m)" % d.length())
