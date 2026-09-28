extends "res://tests/unit/test_core_base.gd"
## Story module C9 screens: the ending screen builds both variants, the Chapter One ending and credits are
## exactly what they were (pinned text, "For Krystal" between two hearts, "from Ali" with its heart), the
## Chapter Two variant carries the MP §17 ending card verbatim, keeps the dedication, ends on "Chapter Two
## complete" + free play; the chapter card picks its autumn style for Chapter Two titles.

const EndingScreen := preload("res://src/ui/screens/ending_screen.gd")
const ChapterCard := preload("res://src/ui/screens/chapter_card.gd")

const MP_ENDING_CARD := "The lanterns shine beyond the trees. The quiet below is quiet again. There are pumpkins to plant, walls to raise, and friends waiting by the fire. The road will keep. Tonight is yours."
const CH1_THANKS := "The Ward Stone shines again. The Heartseed is home, and your friends are safe.\nSomething still stirs in the deep... but tonight, the lights are on."


func setup() -> void:
	fresh_state()


## Every Label / Button text under `n`, depth first (the order the screen shows them).
func _texts(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


## The row (HBoxContainer) holding a label with `text`, and how many icons it has.
func _row_icons(root: Node, text: String) -> int:
	for row in root.find_children("*", "HBoxContainer", true, false):
		for c in row.get_children():
			if c is Label and (c as Label).text == text:
				var n := 0
				for c2 in row.get_children():
					if c2 is TextureRect and (c2 as TextureRect).texture != null:
						n += 1
				return n
	return -1


func _credit_lines(chapter_two: bool) -> Array:
	var lines: Array = ["Hollowhaven", "Chapter One: The Dimming Ward"]
	if chapter_two:
		lines.append("Chapter Two: The Lanterns of Hallowmere")
	lines.append_array(["For Krystal", "from Ali", "Friends"])
	for id in ItemDB.creature_ids():
		var c := ItemDB.creature(id)
		lines.append("%s the %s" % [String(c.get("name", id)), String(c.get("species", ""))])
	lines.append_array(["Built with", "Godot Engine (MIT)", "Fonts: Fredoka and Nunito (SIL OFL)",
		"All art, music and sound are original and generated for this game.", "Thank you for playing"])
	return lines


func test_chapter_one_ending_and_credits_are_unchanged() -> void:
	var es: Control = EndingScreen.new()
	add_child(es)
	assert_eq(String(es.get("variant")), "chapter_one", "the default is the Chapter One ending")
	var expected: Array = ["Chapter One Complete", "The Dimming Ward", CH1_THANKS]
	expected.append_array(_credit_lines(false))
	expected.append_array(["Continue exploring your Haven", "Build, farm, decorate, and spend time with Mochi, Pebble and Lumi.",
		"  Continue  ", "Press any key to skip"])
	assert_eq(_texts(es), expected, "Chapter One ending text, in order")
	assert_eq(_row_icons(es, "For Krystal"), 2, "For Krystal between two hearts")
	assert_eq(_row_icons(es, "from Ali"), 1, "from Ali with its heart")
	assert_eq(_row_icons(es, "The Dimming Ward"), 2, "two leaves, no pumpkins")
	es.queue_free()
	# The title screen's credits panel (light backdrop) too.
	var c: VBoxContainer = EndingScreen.build_credits(980.0, false)
	assert_eq(_texts(c), _credit_lines(false))
	assert_eq(_row_icons(c, "For Krystal"), 2)
	assert_eq(_row_icons(c, "from Ali"), 1)
	c.free()


func test_chapter_two_ending_variant() -> void:
	var es: Control = EndingScreen.new()
	es.setup({"variant": "chapter_two", "recap": ["the Lanternwake festival outfit", "a Wardlight for your home"]})
	add_child(es)
	assert_true(es.is_chapter_two())
	var t := _texts(es)
	var expected: Array = ["Chapter Two Complete", "The Lanterns of Hallowmere", MP_ENDING_CARD]
	expected.append_array(_credit_lines(true))
	expected.append_array(["Chapter Two complete", EndingScreen.CH2_FINAL_SUB,
		"Waiting for you: the Lanternwake festival outfit and a Wardlight for your home.", "  Continue exploring  ",
		"Press any key to skip"])
	assert_eq(t, expected, "Chapter Two ending text, in order")
	assert_eq(_row_icons(es, "For Krystal"), 2, "the dedication keeps both hearts")
	assert_eq(_row_icons(es, "from Ali"), 1, "from Ali keeps its heart")
	assert_eq(_row_icons(es, "The Lanterns of Hallowmere"), 4, "autumn leaves and two carved pumpkins")
	# It runs to the end and hands back to free play.
	var state := {"done": false}
	var runner := func() -> void:
		await es.play()
		state["done"] = true
	runner.call()
	await wait_frames(2)
	assert_false(bool(state["done"]))
	es.call("_show_final")
	assert_true((es.get("final_box") as Control).visible, "Chapter Two complete + Continue")
	es.call("_finish")
	for i in 30:
		if bool(state["done"]):
			break
		await wait_seconds(0.1)
	assert_true(bool(state["done"]), "Continue finishes")


func test_chapter_two_recap_comes_from_the_save() -> void:
	var es: Control = EndingScreen.new()
	es.setup({"variant": "chapter_two"})
	add_child(es)
	assert_eq(es.get("recap"), [], "nothing claimed before anything was granted")
	es.queue_free()
	GameState.grant_once("rw_ch2_feast", {"candy": 6}, ["ch2_feast"])
	preload("res://src/world/story_ch2/story_ch2.gd").sync_feast_unlocks()
	var es2: Control = EndingScreen.new()
	es2.setup({"variant": "chapter_two"})
	add_child(es2)
	var r: Array = es2.get("recap")
	assert_true(r.has("the Lanternwake festival outfit"))
	assert_true(r.has("festival treats and supplies"))
	assert_eq(EndingScreen.recap_text(["a", "b", "c"]), "Waiting for you: a, b and c.")
	assert_eq(EndingScreen.recap_text(["a"]), "Waiting for you: a.")
	assert_eq(EndingScreen.recap_text([]), "")
	es2.queue_free()


func test_chapter_card_styles() -> void:
	assert_eq(ChapterCard.style_for("Chapter Two", ""), "autumn")
	assert_eq(ChapterCard.style_for("Chapter Two Complete", ""), "autumn")
	assert_eq(ChapterCard.style_for("Chapter One", ""), "leaf")
	assert_eq(ChapterCard.style_for("Chapter One", "autumn"), "autumn", "an explicit style wins")
	for pair in [["Chapter One", "The Dimming Ward", 2], ["Chapter Two", "The Lanterns of Hallowmere", 4]]:
		var card: Control = ChapterCard.new()
		card.setup(String(pair[0]), String(pair[1]), 0.05)
		add_child(card)
		assert_eq(_texts(card), [String(pair[0]), String(pair[1])])
		assert_eq(_row_icons(card, String(pair[1])), int(pair[2]), "%s ornaments" % pair[0])
		card.queue_free()
