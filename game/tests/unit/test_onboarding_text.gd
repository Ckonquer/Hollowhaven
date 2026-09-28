extends "res://tests/test_case.gd"
## Module D4: the onboarding hint texts and the player doc. Every {token} resolves through the HUD's token
## system to a real key, nothing is left unformatted, the table and its priority list agree, texts stay short and
## arachnophobia-neutral, and the keys the player doc names are the keys the game really binds (pass 2: the wardrobe
## key O and the rebindable build keys Z / P / N, D02 / D03), and the menus / options / features it names exist.
## 2.0.3 (the gift build, a first-time player): the returning-player update note "Chapter Two - What's New.txt" is
## gone; "How to Play.txt" is the one player doc (written for New Game) and its checks moved here.

const Onboarding := preload("res://src/world/story_ch2/onboarding_hints.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const HintCard := preload("res://src/ui/hud/hint_card.gd")
const BuildMode := preload("res://src/building/build_mode.gd")
const Waygate := preload("res://src/world/surface/waygate.gd")
const TrialsData := preload("res://data/trials.gd")
const ExpeditionData := preload("res://data/expeditions.gd")

const MAX_LEN := 240
const SPIDER_WORDS := ["spider", "web", "silk", "weaver", "brood", "skitter", "arachn", "leg"]
const HOW_TO := "docs/player/How to Play.txt"
## The 2.x returning-player update note: no longer shipped, and removed from docs/player/ (2.0.3).
const OLD_NOTE := "docs/player/Chapter Two - What's New.txt"
const MAX_DOC_COLUMNS := 100       # reads well in Notepad without wrapping
const MAX_DOC_LINES := 170
## Wording that only makes sense to someone who played an earlier version (lower case).
const RETURNING_PLAYER_WORDS := ["what's new", "not new game", "pre_v2_backup", "already played", "update note",
	"older version", "new version", "this version", "welcome back", "since you last", "still there", "used to"]
const PausePanel := preload("res://src/ui/panels/pause_panel.gd")
const Schema := preload("res://src/ui/settings_schema.gd")
const Tracker := preload("res://src/ui/hud/tracker.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")
const HorrorData := preload("res://data/horror_events.gd")

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
	assert_true(Onboarding.companion_skill_text(false, true).begins_with("Your friends support you"), "auto attack off")
	assert_true(Onboarding.companion_skill_text(true, true).begins_with("Your friends help in fights"), "auto attack on")
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


func _read_res(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


## The doc with every run of whitespace (line breaks and indents included) collapsed to one space, so a phrase the
## doc wraps over two lines still matches.
func _flat(text: String) -> String:
	var re := RegEx.create_from_string("\\s+")
	return re.sub(text, " ", true)


func _re_escape(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		out += ("\\" + c) if "\\.+*?()[]{}|^$/".contains(c) else c
	return out


## True when the doc lists `label` with dot leaders and then `key` ("Jump ....... Space").
func _lists(doc: String, label: String, key: String) -> bool:
	return RegEx.create_from_string(_re_escape(label) + " \\.{2,} " + _re_escape(key)).search(doc) != null


## [label in How to Play's CONTROLS table, the key text it gives, action, the default bindings that text describes]
const DOC_CONTROLS := [
	["Move", "W A S D (or arrows)", "move_forward", ["key:%d" % KEY_W, "key:%d" % KEY_UP]],
	["Jump", "Space", "jump", ["key:%d" % KEY_SPACE]],
	["Sprint", "Shift (hold)", "sprint", ["key:%d" % KEY_SHIFT]],
	["Dodge roll", "Ctrl (or V)", "dodge", ["key:%d" % KEY_CTRL, "key:%d" % KEY_V]],
	["Camera zoom", "Mouse wheel", "zoom_in", ["mouse:%d" % MOUSE_BUTTON_WHEEL_UP]],
	["Attack / chop / mine", "Left mouse", "attack", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	["Eat / use item", "Right mouse (or Q)", "use_item", ["mouse:%d" % MOUSE_BUTTON_RIGHT, "key:%d" % KEY_Q]],
	["Interact / pick up", "E", "interact", ["key:%d" % KEY_E]],
	["Raise lantern", "F", "lantern", ["key:%d" % KEY_F]],
	["Backpack", "Tab (or I)", "inventory", ["key:%d" % KEY_TAB, "key:%d" % KEY_I]],
	["Crafting", "C", "craft", ["key:%d" % KEY_C]],
	["Build mode", "B", "build", ["key:%d" % KEY_B]],
	["Wardrobe", "O", "wardrobe", ["key:%d" % KEY_O]],
	["Journal", "J", "journal", ["key:%d" % KEY_J]],
	["Map", "M", "map", ["key:%d" % KEY_M]],
	["Companion follow / wait", "G", "companion_command", ["key:%d" % KEY_G]],
	["Companion skill", "T", "companion_skill", ["key:%d" % KEY_T]],
	["Talk to a friend", "E", "interact", ["key:%d" % KEY_E]],
	["Hotbar slot", "1 - 8", "hotbar_1", ["key:%d" % KEY_1]],
	["Pause menu", "Esc", "pause", ["key:%d" % KEY_ESCAPE]],
	["All controls", "F1", "help", ["key:%d" % KEY_F1]],
	["Screenshot", "F12", "screenshot", ["key:%d" % KEY_F12]],
]
## Build mode rows: [key text, what the doc says it does, action, default key].
const DOC_BUILD_KEYS := [
	["R", "rotate", "build_rotate", KEY_R],
	["X", "take a piece down", "build_dismantle", KEY_X],
	["Z", "undo your last piece (press twice)", "build_undo", KEY_Z],
	["P", "recolour a piece with dyes from the Loom", "build_recolor", KEY_P],
	["N", "choose a carved pumpkin's face", "build_variant", KEY_N],
]


## 2.0.3: the one player doc is for someone who has never played - New Game first, Continue later - and nothing in
## it speaks to a returning player. Short, plain ASCII, <= MAX_DOC_COLUMNS wide for Notepad.
func test_how_to_play_is_written_for_a_first_time_player() -> void:
	var how := _read_repo_file(HOW_TO)
	assert_true(how != "", "the player doc exists: " + HOW_TO)
	if how == "":
		return
	var lines := how.split("\n")
	assert_true(lines.size() <= MAX_DOC_LINES, "a short read (%d lines)" % lines.size())
	for i in lines.size():
		var l := String(lines[i]).trim_suffix("\r")
		assert_true(l.length() <= MAX_DOC_COLUMNS, "line %d fits Notepad (%d columns)" % [i + 1, l.length()])
	var odd := -1
	for i in how.length():
		var c := how.unicode_at(i)
		if c > 126 or (c < 32 and c != 10 and c != 13):
			odd = i
			break
	assert_eq(odd, -1, "plain ASCII text (no tabs, no fancy quotes or arrows)")
	var new_game := how.find("\"New Game\"")
	assert_true(new_game >= 0, "tells her to choose New Game")
	assert_true(new_game < how.find("\"Continue\""), "New Game first; Continue is what appears afterwards")
	var low := how.to_lower()
	for w in RETURNING_PLAYER_WORDS:
		assert_false(low.contains(String(w)), "nothing for a returning player ('%s')" % w)
	assert_true(how.contains("for Krystal"), "keeps the dedication")
	assert_false(how.contains("Weaver"), "no boss names (spoiler-light, arachnophobia-neutral)")
	# "spider" appears only where the Arachnophobia mode option is explained.
	var a := how.find("Arachnophobia mode:")
	var b := how.find("\n  -", a)
	assert_true(a >= 0 and b > a, "the Arachnophobia mode option is explained")
	var at := low.find("spider")
	while at >= 0:
		assert_true(at > a and at < b, "'spider' only inside the Arachnophobia mode explanation (at %d)" % at)
		at = low.find("spider", at + 1)
	var old := ProjectSettings.globalize_path("res://").path_join("..").path_join(OLD_NOTE).simplify_path()
	assert_false(FileAccess.file_exists(old), "the returning-player update note is gone from docs/player/")


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
	var how := _read_repo_file(HOW_TO)
	assert_true(how != "", "the player doc exists")
	if how != "":
		var flat := _flat(how)
		# Every row of the CONTROLS table names the game's real default binding(s).
		for row in DOC_CONTROLS:
			var act := String(row[2])
			assert_true(_lists(how, String(row[0]), String(row[1])), "How to Play lists %s ..... %s" % [row[0], row[1]])
			assert_true(Settings.DEFAULT_BINDINGS.has(act), "%s is a real action" % act)
			if Settings.DEFAULT_BINDINGS.has(act):
				var binds: Array = Settings.DEFAULT_BINDINGS[act]
				for i in (row[3] as Array).size():
					assert_true(i < binds.size() and String(binds[i]) == String(row[3][i]), "%s default binding %d is %s (%s)" % [act, i, row[3][i], str(binds)])
		assert_eq(String(Settings.DEFAULT_BINDINGS["hotbar_8"][0]), "key:%d" % KEY_8, "hotbar slots run 1 - 8")
		for row in DOC_BUILD_KEYS:
			assert_true(_lists(how, String(row[0]), String(row[1])), "How to Play's build keys: %s ... %s" % [row[0], row[1]])
			assert_eq(_primary_key(String(row[2])), int(row[3]), "%s default key" % row[2])
		assert_true(_lists(how, "Left mouse", "place a piece") and _primary_key("attack") == -1, "build mode places with the attack button")
		assert_true(flat.contains("most keys can be changed in Settings > Controls"), "How to Play: most keys are rebindable")
		assert_false(how.contains("can't be changed"), "never says the build keys are fixed")
		assert_true(flat.contains("press T") and flat.contains("Press E on a friend") and flat.contains("G asks it to wait"),
			"FRIENDS: T for the skill, E for the menu, G to wait / follow")
		assert_true(flat.contains("Press O (or Pause > Wardrobe)"), "THE WARDROBE: O opens it")
	# The waygate cost 2.0.x players were told (the quest hint names the same three materials) is the real one.
	assert_eq(str(Waygate.REPAIR_COST), str([["wood", 8], ["stone", 4], ["copper_ore", 2]]), "waygate repair cost")


func _rebindable(action: String) -> bool:
	for row in Settings.REBINDABLE:
		if row is Array and not (row as Array).is_empty() and String((row as Array)[0]) == action:
			return true
	return false


## The menus, buttons, options and places How to Play names are the ones the game has (2.0.3; it replaces the
## pass-2 P49 check of the update note, which named the echo stones, routes, Expedition Board and Music Box).
func test_how_to_play_names_what_the_game_has() -> void:
	var how := _read_repo_file(HOW_TO)
	if how == "":
		assert_true(false, "the player doc exists")
		return
	var flat := _flat(how)
	# Title -> "Before You Begin" -> "Meet Krystal": the buttons a first-time player clicks through, then Continue.
	var src := {
		"res://src/ui/title_screen.gd": ["_menu_button(\"New Game\"", "_menu_button(\"Continue\"", "_menu_button(\"Settings\""],
		"res://src/ui/screens/comfort_screen.gd": ["\"Before You Begin\"", "\"Begin the journey\"", "\"Comfort & Accessibility\""],
		"res://src/ui/screens/creation_screen.gd": ["title = \"Meet Krystal\"", "Kit.button(\"Confirm\""],
		"res://src/ui/panels/pause_panel.gd": ["\"Save Game\"", "Kit.button(\"Wardrobe\"", "\"Comfort & Accessibility\"",
			"\"Quit to Title\"", "\"Quit Game\"", "\"Save & Quit\""],
		"res://src/ui/panels/settings_panel.gd": ["\"Show tips again\""],
		"res://src/ui/panels/wardrobe_panel.gd": ["\"Show equipped armor\"", "section_title(\"Saved looks\")"],
		"res://src/ui/panels/crafting_panel.gd": ["\"Also use nearby chests\""],
		"res://src/ui/panels/inventory_panel.gd": ["section_title(\"Equipped\")"],
		"res://src/ui/panels/journal_panel.gd": ["name = \"Optional\""],
		"res://src/world/surface/mine_entrance.gd": ["show_comfort"],
		"res://autoload/debug.gd": ["\"user://screenshots\""],
	}
	for path in src:
		var text := _read_res(String(path))
		assert_true(text != "", "%s readable" % path)
		for needle in src[path]:
			assert_true(text.contains(String(needle)), "%s has %s" % [path, needle])
	for label in ["\"New Game\"", "\"Continue\"", "\"Before You Begin\"", "\"Begin the journey\"", "\"Meet Krystal\"",
			"\"Confirm\"", "Save Game", "Pause > Wardrobe", "Comfort & Accessibility", "\"Quit to Title\"", "\"Quit Game\"",
			"\"Save & Quit\"", "\"Show tips again\"", "\"Show equipped armor\"", "Three \"Saved looks\"", "\"Also use nearby chests\"",
			"Equipped column", "Journal > Optional", "down into the old mine"]:
		assert_true(flat.contains(String(label)), "How to Play names %s" % label)
	assert_eq(ItemDB.preset_slots(), 3, "three saved-look slots")
	# Getting unstuck: the pause menu's option in every kind of place.
	for area in ["surface", "below", "hallowmere_reach", "echo_trial"]:
		assert_true(flat.contains("\"%s\"" % PausePanel.unstuck_label(area)), "How to Play names \"%s\"" % PausePanel.unstuck_label(area))
	# Chapter Two begins at the Ward Stone: the goal card's words and the two choices.
	assert_true(flat.contains("\"%s\"" % Tracker.POINTER_TITLE), "the goal card's pointer: %s" % Tracker.POINTER_TITLE)
	assert_true(flat.contains("\"%s\"" % String(WardStone.CHOICE_FOLLOW[1])) and flat.contains("\"%s\"" % String(WardStone.CHOICE_STAY[1])),
		"the Ward Stone's two choices")
	assert_true(flat.contains("The Lanterns of Hallowmere"), "Chapter Two's name")
	# Settings: the tabs and every option the doc names, on the tab it names.
	for t in Schema.TABS:
		assert_true(flat.contains("Settings > " + String(t[1])), "How to Play names Settings > %s" % t[1])
	var rows := {"video": ["quality", "render_scale", "max_fps", "fullscreen"],
		"gameplay": ["show_hints", "companion_auto_attack", "companion_autocast", "seasonal_decor"],
		"comfort": ["horror_intensity", "arachnophobia", "reduce_shake", "reduce_flashing", "captions", "high_visibility_cues", "timing_assist"]}
	for tab in rows:
		for key in rows[tab]:
			var r: Dictionary = Schema.row(String(key))
			assert_eq(String(r.get("tab", "")), String(tab), "%s is on the %s tab" % [key, tab])
			assert_true(flat.contains(String(r.get("label", "?"))), "How to Play names %s" % r.get("label", key))
	assert_false(bool(Settings.DEFAULTS["seasonal_decor"]), "Seasonal decorations starts off (as the doc says)")
	for level in [0, 1, 2]:
		assert_true(flat.contains(String(HorrorData.INTENSITY[level]["name"])), "horror intensity %s" % HorrorData.INTENSITY[level]["name"])
	assert_true(String(HorrorData.INTENSITY[0]["desc"]).contains("no ambushes") and flat.contains("no ambushes"), "Gentle: no ambushes")
	# Places and things.
	for sid in ["workbench", "crop_plot", "wardrobe", "vanity_mirror"]:
		assert_true(flat.contains(String(ItemDB.structure(sid).get("name", "?"))), "How to Play names the %s" % sid)
	for sid in ["wardrobe", "vanity_mirror"]:
		assert_eq(String(ItemDB.recipe(sid).get("station", "")), "workbench", "%s is built at the Workbench (as the doc says)" % sid)
	assert_true(String(ItemDB.structure("loom").get("name", "")).begins_with("Loom"), "the Loom")
	assert_true(flat.contains("echo stone"), "echo stones")
	for id in TrialsData.ORDER:
		var t2: Dictionary = TrialsData.trial(String(id))
		assert_true(String((t2.get("origin", {}) as Dictionary).get("area", "")) != "", "trial %s has an echo stone somewhere" % id)
		assert_true(String(t2.get("requires_flag", "")) != "", "trial %s opens once its fight is won" % id)
	# Saving and where saves live.
	assert_true(Game.AUTOSAVE_SECONDS <= 600.0, "the quiet autosave: every few minutes")
	assert_true(Game.SAFE_SAVE_AREAS.has("surface") and Game.SAFE_SAVE_AREAS.has("hallowmere_reach"), "the woods and the Reach save freely")
	assert_true(Game.SAVE_REFUSALS.has("below"), "below the old mine it is the lanterns")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "res://project.godot readable")
	assert_true(bool(cfg.get_value("application", "config/use_custom_user_dir", false)), "user:// is %APPDATA%\\<name>")
	assert_eq(String(cfg.get_value("application", "config/custom_user_dir_name", "")), "Hollowhaven", "... named Hollowhaven")
	assert_eq(SaveSystem.DEFAULT_DIR, "user://saves", "saves in user://saves")
	assert_true(how.contains("%APPDATA%\\Hollowhaven\\saves") and how.contains("%APPDATA%\\Hollowhaven\\screenshots"), "the doc's paths")
	# The onboarding hints still introduce the post-story Workbench recipes (the doc only says "a few new things").
	assert_eq(ExpeditionData.TEMPLATES.size(), 3, "three hand-made routes (the hint says three)")
	for sid in ["expedition_board", "music_box"]:
		assert_false(ItemDB.structure(sid).is_empty(), "%s exists" % sid)
		assert_eq(String(ItemDB.recipe(sid).get("station", "")), "workbench", "%s is a Workbench recipe" % sid)
	assert_true(String(ob.hint_text("ob_expedition_board")).contains("three hand-made routes"), "the board hint names the routes")
