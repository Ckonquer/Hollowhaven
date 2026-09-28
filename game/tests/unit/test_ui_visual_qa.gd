extends "res://tests/unit/test_core_base.gd"
## Visual QA fix pass (qa/tmp/visual/VISUAL_BUGS_MERGED.md, UI-00..UI-22 and theme T4), numeric regression checks:
## the HUD hush (a chapter card, a full-screen menu / modal or the ending hold toasts, quest banners and tips, then
## release them), a stale onboarding tip dropped after the modal that made it stale, the quest banner's width, toasts
## clearing the dialogue box, the Reach map forest (washed colours, no tree touching a pin), the expedition
## "Under way" badge, the stats card's wrapping sources, ribbon titles clear of the close button, the credits
## chapter, the Chapter Two ending card, one journal size for every tab, the taller settings window, the companion
## menu above the hotbar, the face-front preview on face tabs, the title menu stepping back under panels and the
## small-window print boost.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const QuestBanner := preload("res://src/ui/hud/quest_banner.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const EndingScreen := preload("res://src/ui/screens/ending_screen.gd")
const CreditsPanel := preload("res://src/ui/panels/credits_panel.gd")
const SettingsPanel := preload("res://src/ui/panels/settings_panel.gd")
const CompanionPanel := preload("res://src/ui/panels/companion_panel.gd")
const Wardrobe := preload("res://src/ui/panels/wardrobe_panel.gd")
const Preview := preload("res://src/ui/widgets/avatar_preview.gd")
const TitleScreen := preload("res://src/ui/title_screen.gd")
const Onboarding := preload("res://src/world/story_ch2/onboarding_hints.gd")
const Ex := preload("res://src/expeditions/expeditions.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const CANVAS := Vector2(1920, 1080)
const REACH := "hallowmere_reach"
const TO_LAMPS := ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
	"ch2_found_quarry_lamp", "ch2_found_manor_lamp"]
const LONG_BANNER := "Expedition begun: Manor Afterglow. Follow the ribbon lantern to The Moonlit Lawn."

var ui: CanvasLayer
var _mode_before := ""
var _area_before := ""
var _nodes: Array = []
var _ex_listening := false


func setup() -> void:
	UiUtil.allow_settings_save = false
	_ex_listening = Ex.is_listening()
	fresh_state()
	GameState.active = true
	Settings.set_value("arachnophobia", false)
	_mode_before = Game.mode
	_area_before = Game.area_id
	Game.mode = "playing"
	Game.area_id = "surface"
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes = []
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	Game.area_id = _area_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))
	if not _ex_listening:
		Ex.shutdown()
	ThemeFactory.apply_window_scale(CANVAS.y)


func _keep(n: Node) -> Node:
	_nodes.append(n)
	return n


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			_texts(c, out)
	return out


func _drop_card() -> void:
	for c in ui.overlay_layer.get_children():
		ui.overlay_layer.remove_child(c)
		c.free()


# --- T4: the hush ------------------------------------------------------------------------------------------------

## UI-00: the chapter card holds the banner, toasts and tip, hides the gameplay HUD, and everything plays after it.
func test_chapter_card_holds_banner_toasts_and_tip_then_releases_them() -> void:
	Settings.values["show_hints"] = true
	ui.show_chapter_card("Chapter Two", "The Lanterns of Hallowmere")
	assert_eq(ui.hush_reason(), "card")
	assert_true(ui.is_hushed())
	assert_true(bool(ui.toasts.held) and bool(ui.quest_banner.held), "toasts and banner held")
	assert_true(bool(ui.hud.hints.held), "the tip card is held")
	assert_true(ui.hud.gameplay_hidden(), "the gameplay HUD steps aside for the card")
	ui.quest_banner.show_text("New goal: The Hallowmere Way")
	Events.notify.emit("An old trail glimmers north of the Moonlit Ruin.", "info")
	assert_true(ui.hud.hints.on_hint("t_vqa_card", "A tip that arrives with the card."), "the tip is accepted...")
	await wait_frames(2)
	assert_false(ui.quest_banner.panel.visible, "no banner on the chapter card")
	assert_false(ui.hud.hints.is_showing(), "...but waits in the queue")
	var e: Dictionary = ui.toasts.model.entries[ui.toasts.model.entries.size() - 1]
	var age0 := float(e["age"])
	await wait_seconds(0.35)
	assert_almost(float(e["age"]), age0, 0.0001, "a held toast does not age")
	assert_true(ui.top_layer.modulate.a < 0.05, "toasts / banner layer faded out (%.2f)" % ui.top_layer.modulate.a)
	_drop_card()
	await wait_frames(3)
	assert_eq(ui.hush_reason(), "")
	assert_false(bool(ui.toasts.held))
	assert_false(ui.hud.gameplay_hidden(), "the HUD comes back")
	assert_true(ui.quest_banner.panel.visible, "the queued banner plays after the card")
	assert_eq(ui.quest_banner.label.text, "The Hallowmere Way")
	assert_true(ui.hud.hints.is_showing(), "the queued tip shows after the card")
	await wait_seconds(0.5)
	assert_true(ui.top_layer.modulate.a > 0.9, "toasts visible again (%.2f)" % ui.top_layer.modulate.a)
	assert_true(float(e["age"]) > age0, "and their time runs again")


## UI-21 / IN-09: a full-screen menu or a modal hides the toasts and the tip (nothing peeks past its edge).
func test_full_screen_menu_and_modal_hold_toasts_and_tip() -> void:
	Settings.values["show_hints"] = true
	assert_true(ui.hud.hints.on_hint("t_vqa_menu", "Press {craft} to craft."))
	Events.notify.emit("Mochi's bond grew! (2/5)", "bond")
	await wait_frames(1)
	for panel in ["journal", "inventory", "confirm"]:
		ui.open(panel, {"title": "The Ward Stone", "text": "Follow the lantern road?"} if panel == "confirm" else {})
		assert_eq(ui.hush_reason(), "panel", panel)
		await wait_seconds(0.4)
		assert_true(ui.top_layer.modulate.a < 0.05, "%s: toasts hidden" % panel)
		assert_true(ui.hud.hints.modulate.a < 0.05, "%s: tip hidden" % panel)
		ui.close(panel)
		await wait_seconds(0.5)
		assert_eq(ui.hush_reason(), "")
		assert_true(ui.top_layer.modulate.a > 0.9, "%s closed: toasts back" % panel)
		assert_true(ui.hud.hints.modulate.a > 0.9, "%s closed: tip back" % panel)
	ui.open("companion", {"id": "mochi"})
	assert_eq(ui.hush_reason(), "", "the small companion menu keeps the toasts")


## UI-02: the Ward Stone invitation tip showing when the choice card opens is gone after "Follow the lantern road".
func test_stale_onboarding_tip_is_dropped_after_the_modal() -> void:
	var ob: Node = get_tree().get_first_node_in_group(Onboarding.GROUP)
	if ob == null:
		ob = _keep(Onboarding.attach(self))
	assert_not_null(ob, "an OnboardingHints node answers the re-check")
	Settings.values["show_hints"] = true
	GameState.set_flag("chapter_one_complete", true)
	var hints: Control = ui.hud.hints
	assert_false(hints.is_obsolete("ob_ch2_invitation"), "the invitation applies before accepting")
	assert_true(hints.on_hint("ob_ch2_invitation", "The Ward Stone in your Haven has a new inscription."))
	assert_eq(hints.current_id(), "ob_ch2_invitation")
	ui.open("confirm", {"title": "The Ward Stone", "text": "A light well kept reaches farther than its keeper knows."})
	await wait_seconds(0.3)
	assert_true(bool(hints.held))
	GameState.set_flag("ch2_accepted", true)
	assert_true(hints.is_obsolete("ob_ch2_invitation"), "stale once Chapter Two is accepted")
	ui.close("confirm")
	await wait_frames(2)
	assert_ne(hints.current_id(), "ob_ch2_invitation", "the stale tip never comes back")
	# a queued one is dropped before it is shown, too (accepting may have queued its own quest tip meanwhile)
	assert_true(hints.on_hint("t_vqa_first", "A first tip."))
	GameState.set_flag("hint_ob_ch2_invitation", false)
	var before := int(hints.queued_count())
	assert_true(hints.on_hint("ob_ch2_invitation", "The Ward Stone in your Haven has a new inscription."))
	assert_eq(int(hints.queued_count()), before + 1, "queued behind the tip on screen")
	var shown: Array = []
	for i in 8:
		if int(hints.queued_count()) == 0:
			break
		hints._next()
		shown.append(hints.current_id())
	assert_eq(int(hints.queued_count()), 0)
	assert_false(shown.has("ob_ch2_invitation"), "dropped at display time (%s)" % str(shown))


## UI-09: nothing pops over the ending; it all waits for "Continue exploring".
func test_ending_holds_toasts() -> void:
	ui.show_chapter_two_ending()
	await wait_frames(2)
	assert_eq(ui.hush_reason(), "ending")
	Events.notify.emit("New song for your music box: Wood, Wool & Windows", "info")
	await wait_seconds(0.3)
	assert_true(ui.top_layer.modulate.a < 0.05, "no toast over the ending")
	var es: Control = ui._ending
	es.call("_finish")
	await wait_seconds(1.3)
	assert_eq(ui.hush_reason(), "", "released after Continue")


# --- Quest banner and toasts -------------------------------------------------------------------------------------

## UI-07: a long quest line becomes a short title + a small detail line, and the card stays clear of the tracker.
func test_quest_banner_is_narrow_and_clear_of_the_tracker() -> void:
	assert_eq(QuestBanner.split_text(LONG_BANNER), ["EXPEDITION BEGUN", "Manor Afterglow", "Follow the ribbon lantern to The Moonlit Lawn."])
	assert_eq(QuestBanner.split_text("New goal: A Timid Friend"), ["NEW GOAL", "A Timid Friend", ""])
	assert_eq(QuestBanner.split_text("The lanterns are linked."), ["HOLLOWHAVEN", "The lanterns are linked.", ""])
	var vp: Vector2 = ui.root.size
	for line in [LONG_BANNER, "The festival map marks three lamps: the orchard to the west, the quarry to the east, the manor to the north."]:
		var old: Variant = ui.quest_banner._tween
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		ui.quest_banner._queue.clear()
		ui.quest_banner._busy = false
		ui.quest_banner.show_text(line)
		await wait_frames(2)
		var p: Control = ui.quest_banner.panel
		assert_true(p.visible)
		assert_true(p.size.x <= QuestBanner.MAX_LABEL_W + 220.0, "banner %.0f px wide for '%s'" % [p.size.x, line])
		assert_true(p.position.x + p.size.x <= vp.x - 470.0, "clear of the goal tracker column (ends at %.0f)" % (p.position.x + p.size.x))
	assert_true(ui.quest_banner.detail.visible or ui.quest_banner.label.autowrap_mode != TextServer.AUTOWRAP_OFF)


## IN-09: toasts climb above the dialogue box (and its speaker tab) while a line shows, and settle back after.
func test_toasts_clear_the_dialogue_box() -> void:
	Events.say.emit("Echo Trial", "A memory of the Count's Gallery on the night of the invitation. Nothing here can change what really happened.", 30.0)
	Events.notify.emit("Wayfinding mastery rank 1! Sprinting costs 5% less stamina.", "success")
	Events.notify.emit("New song for your music box: Berry Tea Afternoon", "info")
	await wait_seconds(0.8)
	var d: Control = ui.hud.dialog
	assert_true(d.is_showing())
	var dr := d.get_global_rect()
	var tab: Control = d.speaker_tab
	var top := dr.position.y - tab.size.y * 0.55
	assert_true(ui.toast_bottom_margin() > float(UiRootScript.TOAST_MARGINS[3]), "the column moved up")
	assert_true(ui.toasts.views.size() >= 2)
	for id in ui.toasts.views:
		var pr: Rect2 = (ui.toasts.views[id]["panel"] as Control).get_global_rect()
		assert_true(pr.end.y <= top + 0.5, "toast bottom %.0f above the dialogue top %.0f" % [pr.end.y, top])
	d.call("_hide")
	await wait_seconds(0.8)
	assert_almost(ui.toast_bottom_margin(), float(UiRootScript.TOAST_MARGINS[3]), 0.01, "back to its corner")


# --- Reach map ---------------------------------------------------------------------------------------------------

func _accept(extra_flags: Array = []) -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	GameState.set_flag("ch2_accepted")
	for f in extra_flags:
		GameState.set_flag(String(f))
	GameState.chapter2.evaluate()


## UI-01: fewer, washed-out trees in groves, and no tree disc touches a pin, sticker, name or expedition stop.
func test_reach_forest_is_quiet_and_clear_of_every_pin() -> void:
	_accept(TO_LAMPS)
	GameState.discover(REACH, "hr_commons")
	GameState.discover(REACH, "hr_bellhouse")
	GameState.flags["ch2_orchard_restored"] = true
	assert_true(Ex.start("orchard_patrol", 6), "an expedition under way puts its stops on the map")
	var raw := [Color("d9822b"), Color("b8452f"), Color("e8b33a")]
	var cols: Array = MapView.reach_tree_colors()
	for i in raw.size():
		var c: Color = cols[i]
		assert_true(c.s <= (raw[i] as Color).s - 0.15, "tree colour %d washed toward the paper (s %.2f -> %.2f)" % [i, (raw[i] as Color).s, c.s])
	for sz in [Vector2(1000, 800), Vector2(640, 520)]:
		var v: Control = _keep(MapView.new())
		v.map_area = REACH
		add_child(v)
		v.size = sz
		v.target_ids = ["hr_orchard", "hr_quarry", "hr_manor_grounds", "exp_op_meadow"]
		await wait_frames(2)
		assert_true(v._reach_trees.size() <= MapView.REACH_TREE_COUNT)
		var discs: Array = v.reach_tree_discs()
		assert_true(discs.size() >= 25, "still a forest (%d trees at %s)" % [discs.size(), str(sz)])
		var blocks: Array = v.reach_pin_rects()
		assert_true(blocks.size() >= 8, "pins, stickers, names and stops are all kept clear")
		var worst := 1e9
		for t in discs:
			var c2: Vector2 = t[0]
			var tr: float = t[1]
			for b in blocks:
				var br: Rect2 = b
				var q := Vector2(clampf(c2.x, br.position.x, br.end.x), clampf(c2.y, br.position.y, br.end.y))
				worst = minf(worst, q.distance_to(c2) - tr)
		assert_true(worst >= MapView.REACH_TREE_GAP - 0.01, "closest tree edge %.1f px from a pin (want >= %.1f)" % [worst, MapView.REACH_TREE_GAP])
		assert_true(v.expedition_marks.size() >= 2)
		assert_true(v.frames_drawn > 0, "the map drew")
	assert_true(Ex.abandon())


# --- Panels ------------------------------------------------------------------------------------------------------

## UI-06: "Under way" is a badge beside the route name, never appended to the one-line subtitle.
func test_expedition_card_shows_under_way_as_a_badge() -> void:
	for f in ["ch2_choir_defeated", "ch2_orchard_restored", "ch2_quarry_restored", "ch2_manor_restored"]:
		GameState.flags[f] = true
	assert_true(Ex.start("orchard_patrol", 4))
	ui.open("expedition", {"template": "orchard_patrol"})
	await wait_frames(3)
	var p: Control = ui.panels["expedition"]
	for id in p._cards:
		var b: Button = p._cards[id]
		var badge: Control = b.get_meta("badge")
		assert_eq(badge.visible, String(id) == "orchard_patrol", "badge only on the running route (%s)" % id)
		for t in _texts(b.get_meta("row")):
			assert_false(String(t).contains("under way"), "subtitle stays short (%s)" % t)
		assert_true(b.get_combined_minimum_size().x <= 430.5, "%s card keeps its width (%.0f)" % [id, b.get_combined_minimum_size().x])
	assert_true(Ex.abandon())


## UI-03: the stats card's source column wraps (at most two lines, ellipsis after) instead of slicing words.
func test_stats_sources_wrap_inside_the_card() -> void:
	ui.open("inventory")
	await wait_frames(3)
	var p: Control = ui.panels["inventory"]
	assert_true(p.window.get_combined_minimum_size().x <= CANVAS.x - 24.0, "the backpack still fits the canvas")
	var rows: Array = p.stats_box.get_children()
	assert_true(rows.size() >= 6)
	for row in rows:
		var det: Label = (row as Control).get_child(2)
		assert_false(det.clip_text, "no hard clip")
		assert_eq(det.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
		assert_eq(det.max_lines_visible, 2)
		assert_eq(det.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
		assert_true((row as Control).size.x <= p.stats_box.size.x + 0.5, "row inside the card")
	# "Lumi · Swiftstep Charm" (the longest real source) fits the column in two lines
	var det0: Label = (rows[0] as Control).get_child(2)
	var f := det0.get_theme_font("font")
	var fs := det0.get_theme_font_size("font_size")
	var w := f.get_string_size("Lumi · Swiftstep Charm", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	assert_true(w <= det0.size.x * 2.0, "two lines are enough (%.0f px text in a %.0f px column)" % [w, det0.size.x])


## UI-10: a long title ribbon keeps at least 40 px from the round close button.
func test_long_ribbon_titles_keep_clear_of_the_close_button() -> void:
	for t in ["Echo Trial: The Last Waltz (a remembered challenge)", "Echo Trial: The Hollow Above (a remembered challenge)", "OK?"]:
		ui.open("confirm", {"title": t, "text": "An echo of your evening with Count Velour."})
		await wait_frames(3)
		var d: Control = ui.panels["confirm"]
		var rb: Control = d.window.ribbon
		var gap: float = (d.close_btn as Control).get_global_rect().position.x - rb.get_global_rect().end.x
		assert_true(gap >= 40.0, "'%s': %.0f px between the ribbon and the close button" % [t, gap])
		assert_true(d.window.size.x <= CANVAS.x - 24.0, "and the card fits the canvas")
		ui.close("confirm")
		await wait_frames(2)


## UI-04: the title credits list Chapter Two once the save has reached it.
func test_credits_follow_the_saves_chapter() -> void:
	assert_eq(CreditsPanel.credits_chapter({}), 1)
	assert_eq(CreditsPanel.credits_chapter({"meta": {"chapter": 1}}), 1)
	assert_eq(CreditsPanel.credits_chapter({"meta": {"chapter": 2}}), 2)
	for ch in [1, 2]:
		var p: Control = _keep(CreditsPanel.new())
		p.setup({"chapter": ch})
		add_child(p)
		await wait_frames(1)
		assert_eq(_texts(p).has("Chapter Two: The Lanterns of Hallowmere"), ch == 2, "chapter %d credits" % ch)
		assert_true(_texts(p).has("Chapter One: The Dimming Ward"))


## UI-09 / UI-15: the Chapter Two card sits on a deeper warm dim with a bold, outlined paragraph; its closing card is
## capitalised like the opening one. Chapter One stays exactly as it was.
func test_chapter_two_ending_card_reads_clearly() -> void:
	assert_eq(EndingScreen.CH2_FINAL, EndingScreen.CH2_TITLE, "\"Chapter Two Complete\" on both cards")
	assert_true(EndingScreen.CH2_DIM_TITLE >= 0.55 and EndingScreen.CH1_DIM_TITLE == 0.42)
	var two: Control = _keep(EndingScreen.new())
	two.setup({"variant": "chapter_two", "recap": []})
	add_child(two)
	var one: Control = _keep(EndingScreen.new())
	add_child(one)
	await wait_frames(1)
	assert_not_null(two.card_shade, "a warm vignette under the Chapter Two text")
	assert_null(one.card_shade, "none on the Chapter One ending")
	assert_true(two.thanks.get_theme_constant("outline_size") >= 8, "thicker outline on the Chapter Two paragraph")
	assert_false(one.thanks.has_theme_constant_override("outline_size"), "Chapter One paragraph unchanged")


## UI-14 / UI-20: the journal keeps one size on every tab; settings use most of the screen and still fit.
func test_journal_size_is_steady_and_settings_are_tall() -> void:
	ui.open("journal")
	await wait_frames(3)
	var j: Control = ui.panels["journal"]
	var sizes: Array = []
	for i in j.tabs.get_tab_count():
		j.tabs.current_tab = i
		await wait_frames(2)
		sizes.append(j.window.size)
	for s in sizes:
		assert_eq(s, sizes[0], "journal window %s on every tab (%s)" % [str(sizes[0]), str(sizes)])
	ui.close("journal")
	ui.open("settings")
	await wait_frames(3)
	var st: Control = ui.panels["settings"]
	assert_true(SettingsPanel.TABS_H >= 780.0)
	assert_true(st.window.size.y >= 900.0 and st.window.size.y <= CANVAS.y - 24.0, "settings window %.0f px tall" % st.window.size.y)
	assert_true(st.window.position.y >= 30.0, "room for its ribbon")


## UI-12: the companion menu sits above the hotbar and marks the chosen fight mode like a selected tab.
func test_companion_menu_sits_above_the_hotbar() -> void:
	for cid in ["mochi", "lumi"]:
		ui.open("companion", {"id": cid})
		await wait_frames(3)
		var p: Control = ui.panels["companion"]
		var wr: Rect2 = p.window.get_global_rect()
		var hb: Rect2 = ui.hud.hotbar.get_global_rect()
		assert_true(wr.end.y <= hb.position.y, "%s menu ends at %.0f, hotbar starts at %.0f" % [cid, wr.end.y, hb.position.y])
		assert_true(wr.position.y >= 24.0, "the title ribbon stays on screen (%.0f)" % wr.position.y)
		assert_eq(p._assist_btn.theme_type_variation, &"TabLike")
		assert_eq(p._close_btn.theme_type_variation, &"TabLike")
		ui.close("companion")
		await wait_frames(2)


## UI-05 / UI-18: option tiles wrap long names instead of cutting them; the back-slot tab no longer reads "Back".
func test_wardrobe_tiles_wrap_and_back_tab_is_renamed() -> void:
	var labels: Array = []
	for s in Wardrobe.LookEditor.PIECE_SLOTS:
		labels.append(String(s[1]))
	assert_false(labels.has("Back"))
	assert_true(labels.has("Bags & Capes"))
	ui.open("wardrobe", {"category": "pieces"})
	await wait_frames(3)
	var w: Control = ui.panels["wardrobe"]
	assert_true(w.window.get_combined_minimum_size().x <= CANVAS.x - 24.0, "the wardrobe fits the canvas")
	for id in w.editor.tiles:
		var b: Button = w.editor.tiles[id]
		assert_eq(b.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "%s wraps" % id)
		assert_false(b.clip_text)


## UI-08: face tabs turn Krystal to the front, keep her there and frame her face; leaving them frames her whole.
func test_face_tabs_turn_the_preview_to_the_front() -> void:
	ui.open("wardrobe", {"category": "eyes"})
	await wait_frames(3)
	var w: Control = ui.panels["wardrobe"]
	var pv: Control = w.preview
	assert_true(bool(pv.face_mode), "Eyes opens in face mode")
	pv.yaw = PI
	pv.pivot.rotation.y = PI
	pv.face_front()
	await wait_seconds(0.8)
	assert_almost(wrapf(float(pv.yaw) - Preview.FACE_YAW, -PI, PI), 0.0, 0.03, "turned to the front")
	var y1 := float(pv.yaw)
	await wait_seconds(0.5)
	assert_almost(float(pv.yaw), y1, 0.0001, "and held there (no spin on a face tab)")
	assert_true(pv.camera.global_position.distance_to(Preview.CAM_FACE_POS) < 0.05, "camera in on her face")
	w.editor.show_category("outfit")
	await wait_seconds(0.6)
	assert_false(bool(pv.face_mode))
	assert_true(pv.camera.global_position.distance_to(Preview.CAM_POS) < 0.05, "whole figure again")


## UI-16 / UI-17: the title logo and menu fade out under a panel and return after it; the footer sits on a pill.
func test_title_menu_steps_back_under_panels() -> void:
	var title: Node = _keep(TitleScreen.new())
	add_child(title)
	await wait_seconds(2.4)
	assert_true(title.footer_pill is PanelContainer, "footer on a pill")
	assert_true(title.footer_l.get_parent() == title.footer_pill)
	title._on_credits()
	await wait_seconds(0.4)
	assert_true(title.logo_box.modulate.a < 0.05 and title.menu.modulate.a < 0.05, "logo and menu hidden under the panel")
	title._close_panel()
	await wait_seconds(0.5)
	assert_true(title.logo_box.modulate.a > 0.95 and title.menu.modulate.a > 0.95, "and back after it")


## UI-22: in a window shorter than 800 px the small print steps up 2 px (and back at 1080p).
func test_small_windows_get_larger_small_print() -> void:
	var t := ThemeFactory.get_theme()
	ThemeFactory.apply_window_scale(1080.0)
	assert_eq(t.get_font_size(&"font_size", &"Small"), ThemeFactory.FS_SMALL)
	assert_true(ThemeFactory.apply_window_scale(720.0))
	assert_eq(t.get_font_size(&"font_size", &"Small"), ThemeFactory.FS_SMALL + ThemeFactory.SMALL_BOOST)
	assert_eq(t.get_font_size(&"font_size", &"Tiny"), ThemeFactory.FS_TINY + ThemeFactory.SMALL_BOOST)
	assert_false(ThemeFactory.apply_window_scale(700.0), "idempotent")
	assert_true(ThemeFactory.apply_window_scale(1080.0))
	assert_eq(t.get_font_size(&"font_size", &"Small"), ThemeFactory.FS_SMALL, "1080p unchanged")
	assert_eq(t.get_color(&"font_color", &"Small"), ThemeFactory.INK_SOFT)
