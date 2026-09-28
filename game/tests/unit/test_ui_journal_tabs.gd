extends "res://tests/unit/test_core_base.gd"
## B11 journal (src/ui/panels/journal_panel.gd) with a rich mid-Chapter-Two state: the five tabs (Story,
## Optional, Friends, Lore, Mastery) build through the real UI root, show both chapters' progress, the lamps
## together, visible optional goals only (grouped by chapter, legacy free-play goals included, progress rows),
## lore of both chapters (LoreDB + unknown ids kept), the three mastery tracks, arachnophobia text, no rebuild
## when nothing changed, and a window that fits the 1920x1080 canvas.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const JournalPanel := preload("res://src/ui/panels/journal_panel.gd")
const Tracker := preload("res://src/ui/hud/tracker.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const CANVAS := Vector2(1920, 1080)
const CH2_NOTE := "lore_ch2_test_unknown_note"

var ui: CanvasLayer
var _mode_before := ""
var _area_before := ""


func setup() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	GameState.active = true
	Settings.set_value("arachnophobia", false)
	_mode_before = Game.mode
	_area_before = Game.area_id
	Game.mode = "playing"
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func teardown() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	Game.area_id = _area_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


## Mid Chapter Two: Chapter One complete, the orchard lamp lit (quarry + manor pending), two Reach districts
## discovered, optional goals in several states, lore of both chapters, mastery at three different ranks.
func _rich_state() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	for f in ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map",
			"ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp", "ch2_garden_lamp_lit"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	GameState.befriend("mochi")
	GameState.set_flag("c1x_tailor_cache")
	GameState.set_flag("ch2_velvet_scrap_1")
	GameState.optional_goals.evaluate()
	GameState.discover("hallowmere_reach", "hr_commons")
	GameState.discover("hallowmere_reach", "hr_orchard")
	var legacy_ids: Array = LoreDB.ids()
	GameState.discover_lore(String(legacy_ids[0]))
	GameState.discover_lore(CH2_NOTE)
	GameState.mastery["gathering"] = 120      # rank 2
	GameState.mastery["hearthcraft"] = 0      # rank 0
	GameState.mastery["wayfinding"] = 999     # max rank


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			_texts(c, out)
	return out


func _has_text(n: Node, needle: String) -> bool:
	for t in _texts(n):
		if String(t).contains(needle):
			return true
	return false


func _open_journal(args: Dictionary = {}) -> Control:
	ui.open("journal", args)
	await wait_frames(2)
	return ui.panels.get("journal")


# --- tabs ------------------------------------------------------------------------------------------------

func test_five_tabs_and_selection_by_name() -> void:
	var j: Control = await _open_journal()
	assert_eq(j.tab_names(), ["story", "optional", "friends", "lore", "mastery"])
	assert_eq(j.tabs.current_tab, 0)
	ui.close("journal")
	await wait_frames(2)
	j = await _open_journal({"tab": "mastery"})
	assert_eq(j.tabs.get_tab_title(j.tabs.current_tab).to_lower(), "mastery")
	assert_true(j.select_tab("goals"), "the Chapter One tab name still works")
	assert_eq(j.tabs.current_tab, 0)
	assert_false(j.select_tab("nonsense"))
	# Q / E cycle through all five
	var ev := InputEventKey.new()
	ev.keycode = KEY_Q
	ev.pressed = true
	assert_true(j.handle_key(ev))
	assert_eq(j.tabs.current_tab, 4)


func test_story_tab_new_game_is_the_chapter_one_journal() -> void:
	var j: Control = await _open_journal()
	var story: Control = j.goals_box
	assert_true(_has_text(story, String(GameState.quests.current_step()["title"])))
	assert_true(_has_text(story, "Chapter One"))
	assert_true(_has_text(story, "The Dimming Ward"))
	assert_false(_has_text(story, "Chapter Two"), "no Chapter Two spoiler before Chapter One completes")
	assert_true(_has_text(story, "Your story is just beginning."))


func test_story_tab_pointer_after_chapter_one() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	var j: Control = await _open_journal()
	var story: Control = j.goals_box
	assert_true(_has_text(story, Tracker.POINTER_TITLE))
	assert_false(_has_text(story, "OPTIONAL GOALS"), "the free-play card never shows over Chapter Two")
	assert_true(_has_text(story, "Not begun yet"), "Chapter Two section waits for the choice")
	assert_true(_has_text(story, "Bring Back the Light"), "Chapter One completed list")


func test_story_tab_rich_state_both_chapters_and_the_lamps() -> void:
	_rich_state()
	var j: Control = await _open_journal()
	var story: Control = j.goals_box
	assert_true(_has_text(story, "Three Roads, Three Lamps"))
	for t in ["Pumpkins With Opinions", "The Quarry's Pulse", "A Most Peculiar Invitation"]:
		assert_true(_has_text(story, t), "lamp branch %s shown" % t)
	for l in ["Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"]:
		assert_true(_has_text(story, l))
	assert_true(_has_text(story, "Pumpkintide Orchard"), "each branch names its district")
	assert_true(_has_text(story, "Chapter Two"))
	assert_true(_has_text(story, "The Lanterns of Hallowmere"))
	assert_true(_has_text(story, "The Hallowmere Way"), "completed Chapter Two steps listed")
	assert_true(_has_text(story, "Chapter One"))
	var done := 0
	for s in preload("res://data/quests_ch2.gd").STEPS:
		if GameState.chapter2.is_done(String(s["id"])):
			done += 1
	assert_true(_has_text(story, "%d of 20 goals complete" % done))
	# the right column lists the current chapter first
	var right_texts := _texts(story)
	assert_true(right_texts.find("Chapter Two") < right_texts.find("Chapter One"), "current chapter first")


func test_story_tab_single_step_with_tip_and_where() -> void:
	_rich_state()
	for f in ["ch2_quarry_lamp_lit", "ch2_manor_lamp_lit"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	Game.area_id = "surface"
	var vw := Tracker.objective_view()
	assert_eq(String(vw["step_id"]), "ch2_prepare")
	var key := Settings.action_label("map")
	assert_eq(JournalPanel.journal_where(vw, "surface"), "Head to Ward-Keeper's Conservatory, in Hallowmere Reach. It's marked on your map (%s)." % key)
	assert_eq(JournalPanel.journal_where(vw, "hallowmere_reach"), "Head to Ward-Keeper's Conservatory. It's marked on your map (%s)." % key)
	var j: Control = await _open_journal()
	assert_true(_has_text(j.goals_box, "Made for the Journey"))
	assert_true(_has_text(j.goals_box, "Tip:"), "the step hint shows as a tip")


func test_optional_tab_groups_visible_goals_with_progress() -> void:
	_rich_state()
	var j: Control = await _open_journal({"tab": "optional"})
	var opt: Control = j.optional_box
	assert_true(_has_text(opt, "Chapter One"))
	assert_true(_has_text(opt, "Chapter Two"))
	assert_true(_has_text(opt, "The Tailor's Cache"))
	assert_true(_has_text(opt, "Brave Little Steps"), "visible once Mochi is a friend")
	assert_false(_has_text(opt, "Bramblewatch"), "hidden until the ruin is cleared")
	assert_true(_has_text(opt, "Best of Friends"), "legacy free-play goal")
	assert_true(_has_text(opt, "A Heartbloom for Home"), "legacy free-play goal")
	assert_true(_has_text(opt, JournalPanel.LEGACY_TAG), "the legacy goals carry their small note")
	assert_eq(JournalPanel.LEGACY_TAG, "A goal for the long run")
	assert_false(_has_text(opt, "free play"), "no wording a first-time player cannot place")
	assert_true(_has_text(opt, "The Count's Wardrobe"))
	assert_true(_has_text(opt, "1 / 3"), "velvet scraps progress row")
	assert_true(_has_text(opt, "Done"), "a finished goal is marked")
	# pure entries: visible only, chapter split, pending before done
	var ch1: Array = JournalPanel.optional_entries(1)
	var ids1: Array = []
	for e in ch1:
		ids1.append(String(e["id"]))
	assert_false(ids1.has("opt_bramblewatch"))
	assert_true(ids1.has("opt_legacy_bond") and ids1.has("opt_legacy_heartbloom"))
	assert_eq(String(ch1[ch1.size() - 1]["id"]), "opt_tailors_cache", "done goals sink to the end")
	for e2 in JournalPanel.optional_entries(2):
		assert_eq(int(GameState.optional_goals.goal(String(e2["id"]))["chapter"]), 2)


func test_optional_tab_before_chapter_two_has_no_chapter_two_goals() -> void:
	var j: Control = await _open_journal({"tab": "optional"})
	assert_eq(JournalPanel.optional_entries(2).size(), 0)
	assert_false(_has_text(j.optional_box, "The Count's Wardrobe"))
	assert_true(_has_text(j.optional_box, "A Look of Your Own"))


func test_lore_tab_both_chapters() -> void:
	_rich_state()
	var ids: Array = JournalPanel.lore_ids()
	assert_eq(ids.size(), 2)
	assert_eq(String(ids[1]), CH2_NOTE, "unknown ids are kept, after the known ones")
	assert_eq(JournalPanel.lore_chapter(CH2_NOTE), 2)
	var legacy_title := String(LoreDB.get_lore(String(ids[0]))["title"])
	assert_ne(legacy_title, "")
	var j: Control = await _open_journal({"tab": "lore"})
	assert_true(_has_text(j.lore_list, legacy_title))
	assert_true(_has_text(j.lore_list, "Chapter Two"), "grouped by chapter once both have notes")
	assert_true(_has_text(j.lore_page, legacy_title), "first note opens")
	j._show_lore(CH2_NOTE)
	assert_true(_has_text(j.lore_page, "too faded"), "unknown note shows the placeholder, never an error")
	# a new note while open refreshes the list
	for id in LoreDB.ids():
		if not GameState.lore.has(id):
			GameState.discover_lore(String(id))
			await wait_frames(1)
			assert_true(_has_text(j.lore_list, String(LoreDB.get_lore(String(id))["title"])))
			break


func test_lore_tab_real_chapter_two_note() -> void:
	# A note from a real Chapter Two lore file (spec §10) through LoreDB: named, grouped under Chapter Two.
	var ch2_id := ""
	for id in LoreDB.ids():
		if LoreDB.chapter_of(String(id)) == 2:
			ch2_id = String(id)
			break
	if ch2_id == "":
		print("B11: no Chapter Two lore file present yet - real-note check skipped")
		return
	var e: Dictionary = LoreDB.get_lore(ch2_id)
	assert_ne(String(e["title"]), "")
	assert_eq(JournalPanel.lore_entry(ch2_id), e, "the journal shows LoreDB's entry")
	GameState.discover_lore("hollows_page")
	GameState.discover_lore(ch2_id)
	assert_eq(JournalPanel.lore_ids(), ["hollows_page", ch2_id], "legacy notes first, then Chapter Two")
	var j: Control = await _open_journal({"tab": "lore"})
	var texts := _texts(j.lore_list)
	assert_true(texts.has(String(e["title"])))
	assert_true(texts.find("Chapter Two") >= 0 and texts.find("Chapter Two") < texts.find(String(e["title"])), "under its chapter heading")
	j._show_lore(ch2_id)
	assert_true(_has_text(j.lore_page, String(e["text"]).substr(0, 24)))


## Tobin's annex notes are Chapter One optional content: filed under Chapter One by their source file
## (data/lore_ch2_annex.gd), although their saved ids keep the lore_ch2_ prefix. Other Chapter Two files stay
## Chapter Two; ids no file knows fall back to the prefix.
func test_annex_notes_are_filed_under_chapter_one() -> void:
	var Annex: Script = load("res://data/lore_ch2_annex.gd")
	var annex_ids: Array = Annex.get_script_constant_map().get("ORDER", [])
	assert_false(annex_ids.is_empty(), "the annex declares its notes")
	for id in annex_ids:
		assert_true(String(id).begins_with("lore_ch2_"), "ids unchanged: " + String(id))
		assert_eq(LoreDB.chapter_of(String(id)), 1, String(id) + " is Chapter One content")
		assert_eq(JournalPanel.lore_chapter(String(id)), 1)
	assert_eq(LoreDB.chapter_of("hollows_page"), 1, "legacy note")
	assert_eq(LoreDB.chapter_of(CH2_NOTE), 2, "unknown lore_ch2_ id: by prefix")
	assert_eq(LoreDB.chapter_of("some_old_note"), 1, "unknown id without the prefix")
	var ch2_id := ""
	for id in LoreDB.ids():
		if not annex_ids.has(id) and String(id).begins_with("lore_ch2_"):
			ch2_id = String(id)
			assert_eq(LoreDB.chapter_of(ch2_id), 2, ch2_id + " (a Chapter Two file) is Chapter Two")
	if ch2_id == "":
		print("B11: no Chapter Two lore file besides the annex yet - grouping check skipped")
		return
	# the journal: annex note under Chapter One (after the legacy note), the Chapter Two note under Chapter Two
	var annex_id := String(annex_ids[0])
	GameState.discover_lore(ch2_id)
	GameState.discover_lore(annex_id)
	GameState.discover_lore("hollows_page")
	assert_eq(JournalPanel.lore_ids(), ["hollows_page", annex_id, ch2_id], "Chapter One notes first")
	var j: Control = await _open_journal({"tab": "lore"})
	var texts := _texts(j.lore_list)
	var annex_title := String(LoreDB.get_lore(annex_id)["title"])
	var ch2_title := String(LoreDB.get_lore(ch2_id)["title"])
	var h1 := texts.find("Chapter One")
	var h2 := texts.find("Chapter Two")
	assert_true(h1 >= 0 and h2 > h1, "both headings, Chapter One first")
	assert_eq(texts.count("Chapter One"), 1, "one heading per chapter")
	assert_true(texts.find(annex_title) > h1 and texts.find(annex_title) < h2, "the annex note sits under Chapter One")
	assert_true(texts.find(ch2_title) > h2, "the Chapter Two note sits under Chapter Two")


func test_reopen_selects_the_requested_tab() -> void:
	var j: Control = await _open_journal()
	assert_eq(j.tabs.current_tab, 0)
	ui.open("journal", {"tab": "optional"})      # already open -> reopen(args)
	await wait_frames(1)
	assert_eq(ui.panels.get("journal"), j, "same panel")
	assert_eq(j.tab_names()[j.tabs.current_tab], "optional")


func test_lore_titles_follow_arachnophobia() -> void:
	GameState.discover_lore("hollows_page")
	var j: Control = await _open_journal({"tab": "lore"})
	assert_true(_has_text(j.lore_list, "A Page Caught in the Silk"))
	Settings.set_value("arachnophobia", true)   # ui_root refreshes the open journal
	await wait_frames(2)
	assert_eq(String(JournalPanel.lore_entry("hollows_page")["title"]), "A Page Caught in the Roots")
	assert_true(_has_text(j.lore_list, "A Page Caught in the Roots"))
	assert_false(_has_text(j.lore_list, "A Page Caught in the Silk"))
	assert_false(_has_text(j.lore_page, "threads"), "alt text on the page")


func test_mastery_tab_three_tracks() -> void:
	_rich_state()
	var g: Dictionary = JournalPanel.mastery_info("gathering")
	assert_eq(int(g["rank"]), 2)
	assert_eq(int(g["floor_xp"]), 110)
	assert_eq(int(g["next_xp"]), 220)
	assert_eq(String(g["name"]), "Gathering")
	assert_eq(g["rewards"].size(), 5)
	assert_true(bool(g["rewards"][1]["reached"]) and bool(g["rewards"][2]["next"]))
	var w: Dictionary = JournalPanel.mastery_info("wayfinding")
	assert_eq(int(w["rank"]), 5)
	assert_eq(int(w["next_xp"]), -1)
	GameState.mastery["hearthcraft"] = "broken"
	assert_eq(int(JournalPanel.mastery_info("hearthcraft")["xp"]), 0, "a damaged value reads as 0")
	GameState.mastery["hearthcraft"] = 0
	var j: Control = await _open_journal({"tab": "mastery"})
	var m: Control = j.mastery_box
	for t in ["Gathering", "Hearthcraft", "Wayfinding", "Rank 2 of 5", "Rank 0 of 5", "Mastered! Every reward is yours.",
			"120 / 220 XP to rank 3", JournalPanel.MASTERY_NOTE]:
		assert_true(_has_text(m, t), "mastery shows '%s'" % t)
	assert_true(_has_text(m, String(ItemDB.mastery_reward("gathering", 3)["text"])), "next reward listed")
	# live update on Events.mastery_changed
	GameState.mastery["hearthcraft"] = 45
	Events.mastery_changed.emit("hearthcraft", 45, 1)
	await wait_frames(1)
	assert_true(_has_text(m, "Rank 1 of 5"))


func test_friends_tab_and_card_width() -> void:
	var j: Control = await _open_journal({"tab": "friends"})
	assert_eq(j.friends_box.get_child_count(), ItemDB.creature_ids().size())
	assert_eq(JournalPanel.friend_card_width(3), 440.0)
	var w4: float = JournalPanel.friend_card_width(4)
	assert_true(w4 * 4.0 + 24.0 * 3.0 <= 1440.0, "a fourth friend still fits (%.0f)" % w4)


func test_story_not_rebuilt_when_nothing_changed() -> void:
	_rich_state()
	var j: Control = await _open_journal()
	var first: Node = j.goals_box.get_child(0)
	Events.objectives_changed.emit()
	await wait_frames(1)
	assert_true(is_instance_valid(first) and not first.is_queued_for_deletion(), "unchanged -> same nodes")
	GameState.set_flag("ch2_quarry_lamp_lit")
	GameState.chapter2.evaluate()
	await wait_frames(1)
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion() or first.get_parent() != j.goals_box, "changed -> rebuilt")


func test_story_arachnophobia_refresh() -> void:
	_rich_state()
	for f in ["ch2_quarry_lamp_lit", "ch2_manor_lamp_lit", "ch2_read_preparations", "ch2_lamps_linked", "ch2_service_gate_open",
			"ch2_true_signal", "ch2_refuge_reached", "ch2_refuge_shortcut", "ch2_refuge_record", "ch2_line_water",
			"ch2_line_bell", "ch2_line_light"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	var j: Control = await _open_journal()
	assert_true(_has_text(j.goals_box, "Weaver's Crossing"))
	Settings.set_value("arachnophobia", true)   # ui_root refreshes open panels
	await wait_frames(2)
	assert_true(_has_text(j.goals_box, "The Hollow Crossing"))
	assert_false(_has_text(j.goals_box, "Weaver's Crossing"))


func test_journal_fits_the_canvas_with_rich_state() -> void:
	_rich_state()
	for tab in ["story", "optional", "friends", "lore", "mastery"]:
		var j: Control = await _open_journal({"tab": tab})
		await wait_frames(2)
		var ms: Vector2 = j.window.get_combined_minimum_size()
		print("B11-LAYOUT journal/%s %s" % [tab, ms])
		assert_true(ms.x <= CANVAS.x and ms.y <= CANVAS.y, "journal %s fits (%s)" % [tab, ms])
		ui.close("journal")
		await wait_frames(2)
