extends "res://tests/test_case.gd"
## Module D4: the onboarding hint texts and the player update note. Every {token} resolves through the HUD's token
## system to a real key, nothing is left unformatted, the table and its priority list agree, texts stay short and
## arachnophobia-neutral, and the keys the player docs name are the keys the game really binds (pass 2: the wardrobe
## key O and the rebindable build keys Z / P / N, D02 / D03), and the places / features the note names exist.

const Onboarding := preload("res://src/world/story_ch2/onboarding_hints.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const HintCard := preload("res://src/ui/hud/hint_card.gd")
const BuildMode := preload("res://src/building/build_mode.gd")
const Waygate := preload("res://src/world/surface/waygate.gd")
const TrialsData := preload("res://data/trials.gd")
const ExpeditionData := preload("res://data/expeditions.gd")

const MAX_LEN := 240
const SPIDER_WORDS := ["spider", "web", "silk", "weaver", "brood", "skitter", "arachn", "leg"]
const NOTE := "docs/player/Chapter Two - What's New.txt"
const HOW_TO := "docs/player/How to Play.txt"

var ob: Node = null
var _settings := {}


func before_each() -> void:
	fresh_state()
	_settings = Settings.values.duplicate(true)
	ob = Onboarding.new()
	add_child(ob)
	ob.set_process(false)


func after_each() -> void:
	Settings.values = _settings
	if is_instance_valid(ob):
		ob.queue_free()
	await wait_frames(1)


## Every text as it can be emitted (the companion hint in all four settings combinations).
func _all_texts() -> Array:
	var out: Array = []
	for id in Onboarding.HINTS:
		if id == "ob_companion_skill":
			for a in [true, false]:
				for c in [true, false]:
					out.append([id, Onboarding.companion_skill_text(a, c)])
		else:
			out.append([id, String(ob.hint_text(id))])
	return out


## Tokens ("{name}") in a text.
func _tokens(text: String) -> Array:
	var out: Array = []
	var i := text.find("{")
	while i >= 0:
		var j := text.find("}", i)
		if j < 0:
			out.append(text.substr(i))
			break
		out.append(text.substr(i + 1, j - i - 1))
		i = text.find("{", j)
	return out


func test_every_token_resolves_to_a_bound_key() -> void:
	for pair in _all_texts():
		var id := String(pair[0])
		var text := String(pair[1])
		assert_true(text.strip_edges() != "", "%s has text" % id)
		for t in _tokens(text):
			var tok := String(t)
			assert_true(tok == "move" or UiUtil.TOKEN_ACTIONS.has(tok), "%s: {%s} is a known HUD token" % [id, tok])
			if UiUtil.TOKEN_ACTIONS.has(tok):
				var action := String(UiUtil.TOKEN_ACTIONS[tok])
				assert_true(InputMap.has_action(action), "%s: {%s} -> action %s exists" % [id, tok, action])
				var label := Settings.action_label(action)
				assert_true(label != "?" and label != "-" and label != "", "%s: {%s} has a key (%s)" % [id, tok, label])
		var filled := UiUtil.fill_tokens(text, Callable(UiUtil, "settings_label"))
		assert_false(filled.contains("{") or filled.contains("}"), "%s: no raw token left: %s" % [id, filled])
		var shown := HintCard.format_hint(text, Callable(UiUtil, "settings_label"))
		assert_false(shown.contains("{"), "%s: the hint card's formatting leaves no token" % id)


func test_texts_are_complete_short_and_gentle() -> void:
	for pair in _all_texts():
		var id := String(pair[0])
		var text := String(pair[1])
		assert_false(text.contains("%s") or text.contains("%d"), "%s: fully formatted" % id)
		assert_true(text.length() <= MAX_LEN, "%s: short enough for the hint card (%d chars)" % [id, text.length()])
		var low := text.to_lower()
		for w in SPIDER_WORDS:
			assert_false(low.contains(String(w)), "%s: arachnophobia-neutral (found '%s')" % [id, w])


func test_the_table_and_its_priority_list_agree() -> void:
	assert_eq(Onboarding.ORDER.size(), Onboarding.HINTS.size(), "one priority entry per hint")
	for id in Onboarding.HINTS:
		assert_eq(Onboarding.ORDER.count(id), 1, "%s listed exactly once" % id)
		assert_true(String(id).begins_with("ob_"), "%s namespaced (flag hint_ob_*)" % id)
		var w := String((Onboarding.HINTS[id] as Dictionary).get("where", ""))
		assert_true(Onboarding.WHERE_KEYWORDS.has(w) or Game.AREAS.has(w), "%s: 'where' is a keyword or a real area (%s)" % [id, w])
	for id in Onboarding.ITEM_TRIGGERS:
		assert_true(ItemDB.has_item(String(id)), "trigger item %s exists" % id)
	for id in Onboarding.STRUCTURE_TRIGGERS:
		assert_false(ItemDB.structure(String(id)).is_empty(), "trigger structure %s exists" % id)


func test_build_keys_come_from_build_mode_or_a_token() -> void:
	for pair in [["build_undo", "undo", KEY_Z], ["build_recolor", "recolor", KEY_P]]:
		var got := Onboarding.build_key(String(pair[0]), String(pair[1]))
		if UiUtil.TOKEN_ACTIONS.has(String(pair[1])) and InputMap.has_action(String(pair[0])):
			assert_eq(got, "{%s}" % String(pair[1]), "a HUD token once the integrator adds it")
		else:
			assert_eq(got, String(BuildMode.key_label(String(pair[0]))), "the key build mode listens to")
			assert_eq(int(BuildMode.FALLBACK_KEYS[String(pair[0])]), int(pair[2]), "default build key")
	assert_true(String(ob.hint_text("ob_recolour")).contains(Onboarding.build_key("build_recolor", "recolor")), "recolour text names its key")
	assert_true(String(ob.hint_text("ob_undo")).contains(Onboarding.build_key("build_undo", "undo")), "undo text names its key")


func test_companion_text_follows_the_companion_settings() -> void:
	assert_true(Onboarding.companion_skill_text(true, true).contains("They use it when it helps"), "autocast on")
	assert_true(Onboarding.companion_skill_text(true, false).contains("Press {skill} to use it"), "autocast off")
	assert_true(Onboarding.companion_skill_text(false, true).begins_with("Friends now support you"), "auto attack off")
	Settings.values["companion_autocast"] = false
	assert_true(String(ob.hint_text("ob_companion_skill")).contains("Press {skill} to use it"), "reads the live setting")


# --- Player docs: the keys and places they name are the real ones -------------------------------------------------

func _read_repo_file(rel: String) -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _primary_key(action: String) -> int:
	var list: Array = Settings.DEFAULT_BINDINGS[action]
	var s := String(list[0])
	return s.substr(4).to_int() if s.begins_with("key:") else -1


func test_update_note_exists_is_short_and_says_continue() -> void:
	var note := _read_repo_file(NOTE)
	assert_true(note != "", "the update note exists: " + NOTE)
	if note == "":
		return
	var lines := note.split("\n").size()
	assert_true(lines <= 130, "one to two pages (%d lines)" % lines)
	assert_true(note.contains("Continue"), "tells her to press Continue")
	assert_true(note.contains("New Game"), "and not New Game")
	assert_true(note.contains("For Krystal, from Ali") or note.contains("from Ali"), "keeps the dedication")
	for w in ["spider", "Weaver"]:
		assert_false(note.contains(String(w)), "the note stays arachnophobia-neutral (%s)" % w)


func test_docs_name_the_real_default_keys() -> void:
	# Every key the player docs name for a Chapter Two control is the game's real default binding.
	assert_eq(_primary_key("companion_skill"), KEY_T, "companion skill = T")
	assert_eq(_primary_key("companion_command"), KEY_G, "companion follow / wait = G")
	assert_eq(_primary_key("interact"), KEY_E, "interact = E")
	assert_eq(_primary_key("build"), KEY_B, "build = B")
	assert_eq(_primary_key("build_rotate"), KEY_R, "rotate = R")
	assert_eq(_primary_key("build_dismantle"), KEY_X, "take down = X")
	assert_eq(_primary_key("journal"), KEY_J, "journal = J")
	assert_eq(_primary_key("pause"), KEY_ESCAPE, "pause = Esc")
	assert_eq(int(BuildMode.FALLBACK_KEYS["build_undo"]), KEY_Z, "undo = Z")
	assert_eq(int(BuildMode.FALLBACK_KEYS["build_recolor"]), KEY_P, "recolour = P")
	assert_eq(int(BuildMode.FALLBACK_KEYS["build_variant"]), KEY_N, "pumpkin face = N")
	# Pass 2 (D02 / D03): the wardrobe key O and the three build keys are real, rebindable Settings actions.
	for pair in [["wardrobe", KEY_O], ["build_undo", KEY_Z], ["build_recolor", KEY_P], ["build_variant", KEY_N]]:
		var action := String(pair[0])
		assert_true(Settings.DEFAULT_BINDINGS.has(action), "Settings binds %s (the docs name its key)" % action)
		if Settings.DEFAULT_BINDINGS.has(action):
			assert_eq(_primary_key(action), int(pair[1]), "%s default key" % action)
		assert_true(_rebindable(action), "%s can be changed in Settings > Controls (the docs say so)" % action)
	var note := _read_repo_file(NOTE)
	var how := _read_repo_file(HOW_TO)
	assert_true(note != "" and how != "", "both player docs exist")
	if note != "":
		assert_true(note.contains("press T (companion skill)"), "the note: T for the companion skill")
		assert_true(note.contains("Press E on a friend") and note.contains("G still asks them"), "the note: E menu, G follow / wait")
		assert_true(note.contains("Z takes back") and note.contains("P recolours") and note.contains("N picks"), "the note: build keys")
		assert_true(note.contains("can be changed in Settings > Controls"), "the note: the build keys are rebindable")
		assert_false(note.contains("can't be changed"), "the note no longer says the build keys are fixed")
		assert_true(note.contains("press O (the Wardrobe key)"), "the note: O opens the wardrobe")
		assert_true(note.contains("8 wood") and note.contains("4 stone") and note.contains("2 copper ore"), "the note: waygate cost")
	if how != "":
		assert_true(how.contains("Companion skill . T"), "How to Play lists T")
		assert_true(how.contains("Z undo") and how.contains("P recolour") and how.contains("N pumpkin face"), "How to Play lists the build keys")
		assert_true(how.contains("Wardrobe ................. O"), "How to Play lists the wardrobe key O")
	# The waygate cost the note quotes is the real one.
	assert_eq(str(Waygate.REPAIR_COST), str([["wood", 8], ["stone", 4], ["copper_ore", 2]]), "waygate repair cost")


func _rebindable(action: String) -> bool:
	for row in Settings.REBINDABLE:
		if row is Array and not (row as Array).is_empty() and String((row as Array)[0]) == action:
			return true
	return false


## Pass 2 (P49): the places and features the update note names are the ones the game has - an echo stone at every
## trial's origin, the three expedition routes by name, the Expedition Board and the Music Box.
func test_update_note_names_what_the_game_has() -> void:
	var note := _read_repo_file(NOTE)
	if note == "":
		assert_true(false, "the update note exists")
		return
	var place_words := {"below": "Heartseed Chamber", "moonveil_manor": "manor ballroom", "hushed_works": "Bell Throat"}
	for id in TrialsData.ORDER:
		var origin: Dictionary = TrialsData.trial(String(id)).get("origin", {})
		var area := String(origin.get("area", ""))
		assert_true(place_words.has(area), "trial %s: the note has words for its origin (%s)" % [id, area])
		if place_words.has(area):
			assert_true(note.contains(String(place_words[area])), "the note names the %s echo stone (%s)" % [id, place_words[area]])
	for tid in ExpeditionData.TEMPLATES:
		var t: Dictionary = ExpeditionData.TEMPLATES[tid]
		assert_true(note.contains(String(t.get("name", "?"))), "the note names the route %s" % String(t.get("name", tid)))
	assert_eq(ExpeditionData.TEMPLATES.size(), 3, "three hand-made routes (the note and the hint say three)")
	for sid in ["expedition_board", "music_box"]:
		var st: Dictionary = ItemDB.structure(sid)
		assert_false(st.is_empty(), "%s exists" % sid)
		assert_true(note.contains(String(st.get("name", "?"))), "the note names the %s" % String(st.get("name", sid)))
		assert_eq(String(ItemDB.recipe(sid).get("station", "")), "workbench", "%s is a Workbench recipe (as the note says)" % sid)
	assert_true(String(ob.hint_text("ob_expedition_board")).contains("three hand-made routes"), "the board hint names the routes")
