extends "res://tests/unit/test_core_base.gd"
## 2.0.3 HUD clutter (qa/tmp/bot/chain/native_202_visible/s1/shots/s1_016_festival_map.png): the pop-up messages
## (toasts) stacked up the right-hand side over the tall "Current Goal" card and under the festival-map banner. Now the
## toast column stops under the day dial, the goal card (at its live height) and a quest banner wide enough to reach
## it (ui_root.toast_top_limit), and the toasts that don't fit the room left wait their turn in order, hidden, with
## their time paused (toasts.gd fit_views). Checked in the canvas of 1920x1080, 1366x768 and 1280x720 windows
## (canvas_items stretch: the same 1920x1080 canvas, with the small-print boost below 800 px), with and without the
## dialogue box up (the tightest case: the column climbs over it, IN-09).

const UiRootScript := preload("res://src/ui/ui_root.gd")
const ToastsScript := preload("res://src/ui/hud/toasts.gd")
const QuestBannerScript := preload("res://src/ui/hud/quest_banner.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const SIZES := [Vector2i(1920, 1080), Vector2i(1366, 768), Vector2i(1280, 720)]
const LAMP_FLAGS := ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map"]
const ARCH_LIT := "Lantern arch lit: Lanternwake Commons. The Lantern Road can bring you here."
const POUCH := "A stallkeeper's seed pouch was left for whoever lit the arch."
const BOARD_LINE := "Lanternwake: a lamp at every gate, a sweet upon every table, a place kept for every friend who finds the road."
const FESTIVAL_MAP := "The festival map marks three lamps: the orchard to the west, the quarry to the east, the manor to the north."

var ui: CanvasLayer
var _mode_before := ""
var _area_before := ""
var _win_before := Vector2i.ZERO
var _nodes: Array = []


func setup() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	GameState.active = true
	Settings.set_value("arachnophobia", false)
	_mode_before = Game.mode
	_area_before = Game.area_id
	_win_before = get_tree().root.size
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
	get_tree().root.size = _win_before
	ThemeFactory.apply_window_scale(1080.0)
	get_tree().paused = false
	Game.mode = _mode_before
	Game.area_id = _area_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _keep(n: Node) -> Node:
	_nodes.append(n)
	return n


## The window size (the canvas follows it through the project's canvas_items / expand stretch) and the small-print
## boost the UI root applies to it in a windowed game.
func _set_window(s: Vector2i) -> void:
	get_tree().root.size = s
	ThemeFactory.apply_window_scale(float(s.y))
	await wait_frames(3)


## Chapter Two just after the festival map: the lamp card, "Three Roads, Three Lamps", 8 rows, in the Reach.
func _lamp_card() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	for f in LAMP_FLAGS:
		GameState.set_flag(String(f))
	GameState.chapter2.evaluate()
	Game.area_id = "hallowmere_reach"


func _refresh_tracker() -> void:
	var tr: Control = ui.hud.tracker
	tr.set("_last_sig", "")
	tr.refresh()


## Drops every toast and banner line (the state setup above announces its own).
func _clear_chatter() -> void:
	var t: Control = ui.toasts
	t.model.entries.clear()
	t.views.clear()
	for c in t.get_children():
		t.remove_child(c)
		c.queue_free()
	var qb: Control = ui.quest_banner
	var old: Variant = qb.get("_tween")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	(qb.get("_queue") as Array).clear()
	qb.set("_busy", false)
	qb.panel.visible = false


## The arch lit at the Commons: its message, the stallkeeper's pouch and the three seed pickups (as in the shot).
func _festival_moment() -> void:
	var t: Control = ui.toasts
	t._on_notify(ARCH_LIT, "success")
	t._on_item_added("pumpkin_seeds", 3)
	t._on_item_added("sunflax_seeds", 2)
	t._on_item_added("roseberry_seeds", 2)
	t._on_notify(POUCH, "info")


## Every toast on screen stays inside the canvas and clear of the goal card, the day dial, the quest banner, the
## hotbar and (while a line shows) the dialogue box with its speaker tab. Returns how many are on screen.
func _assert_clear(tag: String) -> int:
	var vs: Vector2 = ui.root.size
	# the hotbar's slot row (above it floats its centred item-name label for a moment after a pick, never this far right)
	var slot_row: Control = (ui.hud.hotbar as Control).get_child(1)
	var blockers := {"day dial": (ui.hud.dial as Control).get_global_rect(), "hotbar": slot_row.get_global_rect()}
	var tr: Control = ui.hud.tracker
	if tr.is_visible_in_tree():
		blockers["goal card"] = tr.get_global_rect()
	var qb: Rect2 = ui.quest_banner.resting_rect()
	if qb.size.y > 0.0:
		blockers["quest banner"] = qb
	var d: Control = ui.hud.dialog
	if d.is_showing():
		var tab: Control = d.speaker_tab
		blockers["dialogue box"] = d.get_global_rect().grow_side(SIDE_TOP, tab.size.y * 0.55)
	var n := 0
	for id in ui.toasts.views:
		var v: Dictionary = ui.toasts.views[id]
		var p: Control = v["panel"]
		if not p.is_visible_in_tree():
			continue
		n += 1
		var r := p.get_global_rect()
		var text := (v["label"] as Label).text
		assert_true(r.position.y >= 0.0 and r.end.y <= vs.y, "%s: '%s' inside the canvas %s (%s)" % [tag, text, str(vs), str(r)])
		for k in blockers:
			var b: Rect2 = blockers[k]
			assert_false(r.intersects(b), "%s: '%s' %s overlaps the %s %s" % [tag, text, str(r), k, str(b)])
	assert_eq(n + int(ui.toasts.waiting_count()), ui.toasts.model.entries.size(), "%s: every toast shows or waits" % tag)
	return n


## Sum of the toast cards' heights (with the column's spacing): what the column would need to show them all at once.
func _stack_height() -> float:
	var t: Control = ui.toasts
	var h := 0.0
	for e in t.model.entries:
		var p: Control = t.views[int(e["id"])]["panel"]
		h += p.get_combined_minimum_size().y
	return h + float(t.get_theme_constant("separation")) * float(maxi(0, t.model.entries.size() - 1))


## The shot's moment at three window sizes: with the board's line up only what fits under the tall lamp card shows
## (the rest wait, none lost); once the line ends the rest come in, and with the festival-map banner too nothing
## covers the card, the banner, the dial or the dialogue box.
func test_toasts_never_cover_the_goal_card_at_three_window_sizes() -> void:
	_lamp_card()
	for s in SIZES:
		var tag := "%dx%d" % [s.x, s.y]
		await _set_window(s)
		_refresh_tracker()
		await wait_frames(3)
		_clear_chatter()
		assert_eq(ui.root.size, Vector2(1920, 1080), "%s: the 16:9 canvas" % tag)
		var rows: Array = ui.hud.tracker.shown_rows()
		assert_true(rows.size() >= 8, "%s: the tall lamp card (%d rows)" % [tag, rows.size()])
		Events.say.emit("Festival Board", BOARD_LINE, 30.0)
		await wait_seconds(0.5)
		_festival_moment()
		await wait_seconds(0.5)
		var room := float(ui.toast_room())
		var need := _stack_height()
		assert_true(need > room, "%s: the five toasts (%.0f px) need more than the room under the card (%.0f px)" % [tag, need, room])
		var shown := _assert_clear(tag + " + dialogue")
		assert_true(ui.toasts.waiting_count() >= 1, "%s: the rest wait for room" % tag)
		print("    %s: card ends at %.0f, room %.0f px with the dialogue box up: %d on screen, %d waiting" % [tag,
			(ui.hud.tracker as Control).get_global_rect().end.y, room, shown, int(ui.toasts.waiting_count())])
		ui.hud.dialog.call("_hide")
		await wait_seconds(0.8)
		var shown2 := _assert_clear(tag + " after the line")
		assert_true(shown2 > shown and shown2 >= 3, "%s: more come in once the line is gone (%d -> %d)" % [tag, shown, shown2])
		ui.quest_banner.show_text(FESTIVAL_MAP)
		await wait_seconds(0.6)
		assert_true(ui.quest_banner.panel.visible)
		_assert_clear(tag + " + banner")
		_clear_chatter()


## A quest banner that reaches into the column's width keeps the toasts under it (no goal card here: nothing else
## would stop them); a short banner in the middle does not.
func test_toasts_stay_under_a_wide_quest_banner() -> void:
	await _set_window(Vector2i(1920, 1080))
	GameState.active = false
	ui.hud.tracker.refresh()
	assert_false(ui.hud.tracker.visible, "no goal card")
	_clear_chatter()
	var gap := float(UiRootScript.TOAST_CLEAR_GAP)
	var dial_end := (ui.hud.dial as Control).get_global_rect().end.y
	assert_almost(ui.toast_top_limit(), dial_end + gap, 0.5, "just under the day dial")
	ui.quest_banner.show_text("New goal: A Timid Friend")
	await wait_seconds(0.6)
	assert_true(ui.quest_banner.resting_rect().end.x < ui.root.size.x - 34.0 - ToastsScript.MAX_CARD_W, "a short banner stays in the middle")
	assert_almost(ui.toast_top_limit(), dial_end + gap, 0.5, "...and does not push the toasts down")
	_clear_chatter()
	ui.quest_banner.show_text(FESTIVAL_MAP)
	Events.say.emit("Festival Board", BOARD_LINE, 30.0)
	await wait_seconds(0.6)
	var qb: Rect2 = ui.quest_banner.resting_rect()
	assert_true(qb.size.y > 0.0)
	assert_almost(ui.toast_top_limit(), maxf(dial_end, qb.end.y) + gap, 0.5, "under the wide banner")
	# three-line toasts: the banner card is only as tall as its two lines (test_a_wrapped_banner_is_as_tall_as_its_lines),
	# so it takes taller toasts than two-line ones to need more than the room under it
	for i in 5:
		ui.toasts._on_notify("A long enough message number %d to wrap onto a second line in the toast column, and then a little more so it needs a third." % i, "info")
	await wait_seconds(0.4)
	assert_true(_stack_height() > ui.toast_room(), "more than fits under the banner (%.0f > %.0f px)" % [_stack_height(), ui.toast_room()])
	assert_true(_assert_clear("wide banner + dialogue") >= 1)


## A wrapped banner line gets a card as tall as its lines. Its label's wrapped height used to be measured at the
## label's current width (the last, shorter line's, or 0 before the first banner), so the festival-map card came out
## ~250 px tall with its two lines at the top (qa/tmp/bot/chain/native_202_visible/s1/shots/s1_016_festival_map.png)
## and as the first banner of a session ~2400 px: over the middle of the screen, and pushing the toasts' top limit
## (resting_rect) down to its cap.
func test_a_wrapped_banner_is_as_tall_as_its_lines() -> void:
	var holder: Control = _keep(Control.new())
	holder.theme = ThemeFactory.get_theme()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var qb: Control = QuestBannerScript.new()
	holder.add_child(qb)
	await wait_frames(2)
	for line in [FESTIVAL_MAP, "New goal: A Timid Friend", FESTIVAL_MAP, "The lanterns are linked. A stair has opened at the Sunken Bellhouse."]:
		qb.show_text(line)
		await wait_frames(3)
		var p: Control = qb.panel
		assert_true(p.visible, "'%s' shows" % line)
		var content := p.get_combined_minimum_size().y
		assert_almost(p.size.y, content, 0.5, "'%s': a %.0f px card for %.0f px of content" % [line, p.size.y, content])
		assert_true(p.size.y < 200.0, "'%s': at most two lines of title under the kind (%.0f px)" % [line, p.size.y])
		assert_eq(qb.resting_rect().size, p.size, "the toasts keep clear of the card as drawn")
		var tw: Variant = qb.get("_tween")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		(qb.get("_queue") as Array).clear()
		qb.set("_busy", false)
		p.visible = false


## The limit follows the card's live height, drops to the day dial without a card, and never goes lower than
## TOAST_TOP_CAP of the canvas (a card taller than any real one still leaves room for a few toasts).
func test_top_limit_follows_the_goal_cards_live_height() -> void:
	await _set_window(Vector2i(1920, 1080))
	var gap := float(UiRootScript.TOAST_CLEAR_GAP)
	var tr: Control = ui.hud.tracker
	_refresh_tracker()
	await wait_frames(3)
	assert_true(tr.visible, "the first goal shows")
	var short_end := tr.get_global_rect().end.y
	assert_almost(ui.toast_top_limit(), short_end + gap, 0.5, "under the first goal's card")
	_lamp_card()
	_refresh_tracker()
	await wait_frames(3)
	var tall_end := tr.get_global_rect().end.y
	assert_true(tall_end > short_end + 100.0, "the lamp card is much taller (%.0f -> %.0f)" % [short_end, tall_end])
	assert_almost(ui.toast_top_limit(), tall_end + gap, 0.5, "the limit follows it")
	await wait_seconds(0.25)
	assert_almost(float(ui.toasts.room), ui.toast_room(), 0.5, "the column got the new room")
	tr.custom_minimum_size.y = 1400.0
	await wait_frames(3)
	assert_almost(ui.toast_top_limit(), ui.root.size.y * UiRootScript.TOAST_TOP_CAP, 0.5, "capped")
	assert_true(ui.toast_room() >= 250.0, "room for a few toasts (%.0f px)" % ui.toast_room())
	tr.custom_minimum_size.y = 0.0


## Toasts that don't fit wait in order (a smaller one never jumps the queue) with their time paused, and come in as
## the ones above them go.
func test_waiting_toasts_keep_their_order_and_their_time() -> void:
	var holder: Control = _keep(Control.new())
	holder.theme = ThemeFactory.get_theme()
	add_child(holder)
	var t: Control = ToastsScript.new()
	holder.add_child(t)
	await wait_frames(1)
	t.set_room(0.0)
	t._on_notify(ARCH_LIT, "success")
	t._on_notify("A short one.", "info")
	t._on_notify(POUCH + " And a little more to wrap.", "info")
	await wait_frames(2)
	assert_eq(t.model.entries.size(), 3)
	assert_eq(t.waiting_count(), 3, "no room: all three wait")
	var ids: Array = []
	for e in t.model.entries:
		ids.append(int(e["id"]))
	var p0: Control = t.views[ids[0]]["panel"]
	var p1: Control = t.views[ids[1]]["panel"]
	var p2: Control = t.views[ids[2]]["panel"]
	var h0 := p0.get_combined_minimum_size().y
	var h1 := p1.get_combined_minimum_size().y
	assert_true(h0 > h1 + 10.0, "the arch message wraps (%.0f px) and the short one does not (%.0f px)" % [h0, h1])
	await wait_seconds(0.3)
	for e in t.model.entries:
		assert_almost(float(e["age"]), 0.0, 0.0001, "a waiting toast does not age")
	t.set_room(h1 + 1.0)
	await wait_frames(2)
	assert_false(p0.visible or p1.visible or p2.visible, "the short one does not jump ahead of the first")
	t.set_room(h0 + 1.0)
	await wait_frames(2)
	assert_true(p0.visible, "the first fits now")
	assert_false(p1.visible or p2.visible)
	assert_eq(t.waiting_count(), 2)
	await wait_seconds(0.3)
	assert_true(float(t.model.entries[0]["age"]) > 0.2, "the toast on screen ages")
	assert_almost(float(t.model.entries[1]["age"]), 0.0, 0.0001, "the ones waiting keep their whole time")
	t.model.entries[0]["age"] = float(t.model.entries[0]["life"])
	await wait_frames(2)
	assert_false(t.views.has(ids[0]), "the first has gone")
	assert_false(p1.visible, "the next waits while the first fades out in its place")
	await wait_seconds(0.6)
	assert_true(p1.visible, "then the next one in line shows")
	assert_false(p2.visible)
	t.set_room(INF)
	await wait_frames(2)
	assert_true(p1.visible and p2.visible)
	assert_eq(t.waiting_count(), 0, "room for all: none waits")
