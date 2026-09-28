extends "res://tests/test_case.gd"
## 2.0.3 (the gift build): the in-game words a FIRST-TIME player sees - a journey begun with New Game, never a save
## carried over from Chapter One v1 - never read like update notes for a returning player.
##  * onboarding hints and friend / kitchen texts: no "now help", "still asks", "as before", "did before" ...
##  * the wardrobe's reset button is her "Classic look", not her "Chapter One look" (a new journey's Chapter One look is
##    whatever she chose on "Meet Krystal");
##  * the legacy goal "A Heartbloom for Home", listed from a new journey's first minute, no longer says "The restored
##    Ward taught you the Heartbloom Lamp" (true only for a v1 save in free play);
##  * the F1 overlay says "most" keys can be changed (Esc, F1, F12, R, X and the hotbar can't);
##  * the one-time "Your wardrobe is ready" card (v1 saves) can't reach a New Game journey: "Meet Krystal" always
##    hands over a complete look, and Game.new_game(look) marks the card as not needed (test_flow_ch2_newgame).
## Pure checks: no scene, nothing written outside user://test_saves/.

const Onboarding := preload("res://src/world/story_ch2/onboarding_hints.gd")
const Workbench := preload("res://src/building/structures/workbench.gd")
const WardrobePanel := preload("res://src/ui/panels/wardrobe_panel.gd")
const ControlsPanel := preload("res://src/ui/panels/controls_panel.gd")
const CreationScreen := preload("res://src/ui/screens/creation_screen.gd")
const UiRoot := preload("res://src/ui/ui_root.gd")

## Phrases that only make sense to someone who played an earlier version (lower case).
const UPDATE_WORDS := ["now help", "now support", "still asks", "as before", "did before", "old recipes",
	"can become bars now", "what's new", "new version", "this version", "welcome back", "since you last",
	"chapter one save", "update"]


func before_each() -> void:
	fresh_state()


func _clean(what: String, text: String) -> void:
	var low := text.to_lower()
	assert_true(text.strip_edges() != "", "%s has text" % what)
	for w in UPDATE_WORDS:
		assert_false(low.contains(String(w)), "%s reads as an update note ('%s'): %s" % [what, w, text])


func test_onboarding_hints_are_not_update_notes() -> void:
	for id in Onboarding.HINTS:
		if id == "ob_companion_skill":
			for a in [true, false]:
				for c in [true, false]:
					_clean("ob_companion_skill(%s, %s)" % [a, c], Onboarding.companion_skill_text(a, c))
		else:
			_clean(id, String(Onboarding.HINTS[id]["text"]))   # (ob_recolour / ob_undo: "%s" is a key label)
	assert_true(Onboarding.companion_skill_text(true, true).begins_with("Your friends help in fights"), "no 'now'")
	assert_true(String(Onboarding.HINTS["ob_companion_menu"]["text"]).contains("{companion} asks them to follow or wait"),
		"the menu hint teaches G (no 'still')")


func test_friend_and_kitchen_texts_are_not_update_notes() -> void:
	for cid in ["mochi", "pebble", "lumi"]:
		_clean("%s passive" % cid, String(ItemDB.companion_skill(cid).get("passive_text", "")))
	assert_true(String(ItemDB.companion_skill("mochi").get("passive_text", "")).contains("Also forages for you."), "Mochi forages")
	assert_true(String(ItemDB.companion_skill("pebble").get("passive_text", "")).contains("Also helps you mine."), "Pebble helps mine")
	# What those lines promise is what the friends do (data/creatures.gd abilities).
	assert_eq(String(ItemDB.creature("mochi").get("ability", "")), "forager", "Mochi is the forager")
	assert_eq(String(ItemDB.creature("pebble").get("ability", "")), "miner", "Pebble is the miner")
	_clean("kitchen station hint", String(Workbench.STATION_HINTS["kitchen"][1]))
	_clean("Kitchen Counter description", String(ItemDB.item("kitchen_counter").get("desc", "")))
	assert_eq(String(ItemDB.recipe("kitchen_counter").get("unlock", "?")), "", "the Kitchen Counter can be built in Chapter One too")


func test_wardrobe_reset_is_the_classic_look_not_chapter_one() -> void:
	assert_eq(WardrobePanel.RESET_LABEL, "Classic look")
	assert_false(WardrobePanel.RESET_LABEL.contains("Chapter One") or WardrobePanel.RESET_TOOLTIP.contains("Chapter One"),
		"a new journey's Chapter One look is the one she chose at creation")
	assert_false(WardrobePanel.RESET_TOOLTIP.contains("original"), "not 'her original' look either")
	assert_true(WardrobePanel.RESET_TOOLTIP.contains("classic look"), "the creation screen's reset uses the same words")
	# The button really resets to the classic look (ItemDB.legacy_look: auburn side braid, explorer outfit).
	var legacy: Dictionary = ItemDB.legacy_look()
	assert_eq(String(legacy.get("hair", "")), "side_braid", "the classic look's side braid")
	assert_eq(String(legacy.get("upper", "")), "explorer_jacket", "and her explorer outfit")


func _visible_ids() -> Array:
	var out: Array = []
	for g in GameState.optional_goals.visible_goals():
		out.append(String(g["id"]))
	return out


## Journal > Optional lists "A Heartbloom for Home" from a new journey's first minute, long before the Ward is restored:
## its text may promise the lamp, but must not say the Ward already taught it (the v1 free-play wording).
func test_heartbloom_goal_does_not_claim_the_ward_is_restored() -> void:
	assert_true(_visible_ids().has("opt_legacy_heartbloom"), "listed for a new journey")
	assert_false(bool(GameState.get_flag("ward_restored")), "precondition: a new journey")
	var g: Dictionary = GameState.optional_goals.goal("opt_legacy_heartbloom")
	var text := String(GameState.optional_goals.step_string(g, "text"))
	assert_false(text.contains("taught you") or text.begins_with("The restored Ward"), "no past-tense restoration: " + text)
	assert_true(text.contains("once its light is restored"), "a promise for later: " + text)
	_clean("A Heartbloom for Home", text)
	assert_eq(String(ItemDB.recipe("heartbloom_lamp").get("unlock", "")), "ward_restored", "the lamp is learned when the Ward is restored")


func test_f1_overlay_says_most_keys_can_be_changed() -> void:
	assert_true(ControlsPanel.TIP.contains("most") and ControlsPanel.TIP.contains("Settings > Controls"), ControlsPanel.TIP)
	var rebindable: Array = []
	for row in Settings.REBINDABLE:
		rebindable.append(String(row[0]))
	var fixed: Array = []
	for g in ControlsPanel.GROUPS:
		for item in g[1]:
			var a := String(item[0])
			if a in ["move", "look", "zoom", "hotbar"]:
				continue
			if not rebindable.has(a):
				fixed.append(a)
	assert_true(not fixed.is_empty(), "some listed keys can't be changed, so 'everything' would be wrong: %s" % str(fixed))
	assert_true(rebindable.has("wardrobe") and rebindable.has("companion_skill"), "and most can")


## The first link of "New Game never shows the v1 wardrobe card": whatever path the title takes, "Meet Krystal" holds a
## complete look (it starts from the classic look), and only Confirm hands it on (test_ui_appearance_flow checks the
## hand-over; test_flow_ch2_newgame checks Game.new_game(look) marks the card as not needed and saves that).
func test_meet_krystal_always_has_a_complete_look() -> void:
	for args in [{}, {"look": {}}, {"look": {"hair": "bob"}}]:
		var cs: Control = CreationScreen.new()
		cs.setup(args)
		assert_false((cs.look as Dictionary).is_empty(), "a look to hand over (%s)" % str(args))
		assert_eq(ItemDB.sanitize_look(cs.look)["missing"], [], "complete and valid (%s)" % str(args))
		cs.free()
	# The v1 card's condition: a journey whose wardrobe was never marked. A New Game journey is marked at creation.
	GameState.wardrobe["notice_shown"] = true
	var ui: Object = UiRoot.new()
	assert_false(bool(ui.call("wardrobe_notice_pending")), "no 'Your wardrobe is ready' card for a styled journey")
	ui.free()
