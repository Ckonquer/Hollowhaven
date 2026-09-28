extends "res://tests/test_case.gd"
## Chapter Two HUD (group G2): the player shield on the health bar (Events.player_shield_changed, the bar's
## maximum from Stats.effective_max_hp), the build bar's scrolling window of pieces and its Chapter Two key hints
## (undo / recolour / face from BuildMode.key_label and get_state), and the underground look (HUD tint, day
## dial lantern) for every underground area.

const Vitals := preload("res://src/ui/hud/vitals.gd")
const BuildBar := preload("res://src/ui/hud/build_bar.gd")
const DayDial := preload("res://src/ui/hud/day_dial.gd")
const HudScript := preload("res://src/ui/hud/hud.gd")
const PlayerHealth := preload("res://src/player/player_health.gd")
const Stats := preload("res://src/core/stats.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var _saved_settings: Dictionary = {}
var _old_player: Node3D = null
var _old_area: Node = null
var _old_area_id := ""


class FakePlayer extends Node3D:
	var health: Node = null
	var stamina: float = 100.0


class FakeBuildMode extends Node:
	var state: Dictionary = {}

	func get_state() -> Dictionary:
		return state


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_saved_settings = Settings.values.duplicate(true)
	_old_player = Game.player
	_old_area = Game.area
	_old_area_id = Game.area_id
	Game.player = null
	Game.area = null


func after_each() -> void:
	Game.player = _old_player
	Game.area = _old_area
	Game.area_id = _old_area_id
	Settings.values = _saved_settings.duplicate(true)
	Settings.setup_input_map()
	await wait_frames(1)


# --- Shield on the health bar ------------------------------------------------------------------------------------

func test_shield_segment_geometry() -> void:
	var inner := Rect2(Vector2(10, 5), Vector2(200, 20))
	assert_eq(Vitals.shield_segment(inner, 50.0, 0.0, 100.0), Rect2(), "no shield, no segment")
	var r := Vitals.shield_segment(inner, 50.0, 20.0, 100.0)
	assert_almost(r.position.x, 110.0, 0.01, "starts where the health fill ends")
	assert_almost(r.size.x, 40.0, 0.01, "as wide as the shield")
	assert_almost(r.size.y, 20.0, 0.01)
	var full := Vitals.shield_segment(inner, 100.0, 20.0, 100.0)
	assert_almost(full.position.x + full.size.x, 210.0, 0.01, "never past the end of the bar")
	assert_almost(full.size.x, 40.0, 0.01, "a full-health shield still shows (over the end of the fill)")
	var huge := Vitals.shield_segment(inner, 30.0, 500.0, 100.0)
	assert_almost(huge.size.x, 200.0, 0.01, "capped at the bar")
	assert_almost(huge.position.x, 10.0, 0.01)


func test_shield_event_draws_and_clears_without_flashing() -> void:
	var v: Control = Vitals.new()
	add_child(v)
	await wait_frames(2)
	assert_almost(float(v.shield), 0.0, 0.001, "no shield at first")
	Events.player_shield_changed.emit(24.0)
	await wait_frames(1)
	assert_almost(float(v.shield), 24.0, 0.001, "the HUD hears the shield")
	await wait_seconds(0.6)
	assert_almost(float(v._shown_shield), 24.0, 0.5, "eased in (%.2f)" % float(v._shown_shield))
	# easing only moves toward the target: it never overshoots or blinks
	var last := float(v._shown_shield)
	Events.player_shield_changed.emit(0.0)
	var went_up := false
	for i in 30:
		await wait_frames(1)
		if float(v._shown_shield) > last + 0.001:
			went_up = true
		last = float(v._shown_shield)
	assert_false(went_up, "fades out smoothly")
	await wait_seconds(0.5)
	assert_eq(float(v._shown_shield), 0.0, "gone at 0")
	v.queue_free()
	await wait_frames(1)


func test_health_node_is_the_shield_source_and_effective_max_is_used() -> void:
	var p := FakePlayer.new()
	var h: Node = PlayerHealth.new()
	h.set("max_hp", 50.0)
	p.health = h
	p.add_child(h)
	add_child(p)
	await wait_frames(1)
	h.set("hp", 40.0)
	Game.player = p
	var v: Control = Vitals.new()
	add_child(v)
	await wait_frames(2)
	var want_max := maxf(50.0, Stats.effective_max_hp())
	assert_almost(float(v.max_hp), want_max, 0.001, "bar max = effective max hp when larger than the node's")
	assert_almost(float(v.hp), 40.0, 0.001)
	h.call("add_shield", 18.0, 30.0, "test")
	await wait_frames(2)
	assert_almost(float(v.shield), 18.0, 0.001, "a real shield shows")
	# a new player (area change / respawn) starts without a shield and says nothing: the HUD follows the node
	h.set("shield", 0.0)
	await wait_frames(2)
	assert_almost(float(v.shield), 0.0, 0.001, "follows the health node")
	Game.player = null
	v.queue_free()
	p.queue_free()
	await wait_frames(1)


# --- Build bar -----------------------------------------------------------------------------------------------------

func test_window_range_keeps_the_selection_visible() -> void:
	assert_eq(BuildBar.window_range(0, -1), Vector2i(0, 0))
	assert_eq(BuildBar.window_range(5, 3), Vector2i(0, 5), "few pieces: all shown")
	assert_eq(BuildBar.window_range(50, 0), Vector2i(0, 8), "start of the list")
	assert_eq(BuildBar.window_range(50, 49), Vector2i(42, 50), "end of the list")
	assert_eq(BuildBar.window_range(50, -1), Vector2i(0, 8), "nothing selected: the start")
	for sel in 50:
		var r := BuildBar.window_range(50, sel)
		assert_eq(r.y - r.x, 8, "always a full window")
		assert_true(sel >= r.x and sel < r.y, "piece %d visible in %s" % [sel, str(r)])


func _placeable_ids(n: int) -> Array:
	var out: Array = []
	for id in ItemDB.all_item_ids():
		if ItemDB.category(String(id)) == "placeable":
			out.append(String(id))
			if out.size() >= n:
				break
	return out


func _new_bar(fake: Node) -> Control:
	var bar: Control = BuildBar.new()
	bar.set("build_mode_node", fake)
	add_child(bar)
	return bar


func test_build_bar_scrolls_through_every_piece() -> void:
	var ids := _placeable_ids(14)
	assert_true(ids.size() > 8, "enough placeables to scroll (%d)" % ids.size())
	for id in ids:
		GameState.give_item(String(id), 1)
	var fake := FakeBuildMode.new()
	fake.state = {"placeables": ids.duplicate(), "undo": "", "undo_armed": false, "face": "", "level": 0}
	add_child(fake)
	var bar := _new_bar(fake)
	await wait_frames(1)
	bar.set_active(true)
	Events.build_selection_changed.emit(String(ids[ids.size() - 1]))
	await wait_frames(1)
	var shown: Array = bar.shown_items()
	assert_eq(shown.size(), 8, "a window of 8")
	assert_true(shown.has(String(ids[ids.size() - 1])), "the last piece is reachable and shown")
	assert_true(bool(bar.more_left.visible), "the earlier pieces are counted on the left")
	assert_eq(String(bar.more_left.text), "‹ %d" % (ids.size() - 8))
	assert_false(bool(bar.more_right.visible))
	Events.build_selection_changed.emit(String(ids[0]))
	await wait_frames(1)
	shown = bar.shown_items()
	assert_eq(String(shown[0]), String(ids[0]), "back at the start")
	assert_true(bool(bar.more_right.visible), "more to the right")
	# fallback without a build mode: the backpack order
	var order := BuildBar.inventory_placeables()
	for id2 in ids:
		assert_true(order.has(String(id2)), "%s in the backpack order" % id2)
	bar.set_active(false)
	bar.queue_free()
	fake.queue_free()
	await wait_frames(1)


func test_build_bar_shows_undo_recolour_face_and_storey() -> void:
	var ids := _placeable_ids(2)
	var fake := FakeBuildMode.new()
	fake.state = {"placeables": ids.duplicate(), "undo": "", "undo_armed": false, "face": "", "level": 0}
	add_child(fake)
	var bar := _new_bar(fake)
	await wait_frames(1)
	bar.set_active(true)
	await wait_frames(1)
	var hints: Dictionary = bar.key_hints
	for a in ["attack", "build_rotate", "build_dismantle", "build_undo", "build_recolor", "build_variant", "build"]:
		assert_true(hints.has(a), "hint for " + a)
	assert_eq(String((hints["build_undo"]["cap"] as Label).text), String(bar.key_label("build_undo")), "undo key cap from BuildMode.key_label")
	assert_eq(String((hints["build_recolor"]["cap"] as Label).text), String(bar.key_label("build_recolor")))
	assert_false(bool((hints["build_variant"]["box"] as Control).visible), "no face hint without a pumpkin")
	assert_false(bool(bar.detail_l.visible))
	# polled state: undo, armed undo, face, storey
	fake.state = {"placeables": ids.duplicate(), "undo": "Wooden Wall", "undo_armed": false, "face": "happy_grin", "level": 1}
	await wait_seconds(0.35)
	assert_eq(String((hints["build_undo"]["text"] as Label).text), "Undo Wooden Wall")
	assert_true(bool((hints["build_variant"]["box"] as Control).visible) == (String(bar.key_label("build_variant")) != "-"), "face hint while a pumpkin is selected")
	assert_true(String(bar.detail_l.text).contains("Face: Happy Grin"), bar.detail_l.text)
	assert_true(String(bar.detail_l.text).contains("upstairs"), bar.detail_l.text)
	fake.state["undo_armed"] = true
	await wait_seconds(0.35)
	assert_eq(String((hints["build_undo"]["text"] as Label).text), "Again to undo the Wooden Wall", "armed undo asks for the second press")
	# a build key the player gave to another action shows as "-" in build mode: the hint hides
	if not InputMap.has_action("build_recolor"):
		var k := InputEventKey.new()
		k.physical_keycode = KEY_P
		k.pressed = true
		Settings.rebind("journal", k)
		assert_eq(String(bar.key_label("build_recolor")), "-", "P now belongs to the journal")
		bar._refresh_keys(true)
		assert_false(bool((hints["build_recolor"]["box"] as Control).visible), "unbound recolour hint hidden")
	bar.set_active(false)
	bar.queue_free()
	fake.queue_free()
	await wait_frames(1)


# --- Underground look --------------------------------------------------------------------------------------------

func test_every_underground_area_gets_the_underground_look() -> void:
	var hud: Control = HudScript.new()
	add_child(hud)
	await wait_frames(1)
	var dial: Control = hud.dial
	for a in ["below", "tobin_annex", "hushed_works"]:
		hud.apply_area_look(a)
		assert_ne(Color(hud.modulate.r, hud.modulate.g, hud.modulate.b), Color.WHITE, a + ": toned-down HUD")
		Game.area_id = a
		assert_true(bool(dial.shows_lantern()), a + ": lantern instead of the sky")
	for a2 in ["surface", "hallowmere_reach", "moonveil_manor", "echo_trial"]:
		hud.apply_area_look(a2)
		assert_eq(Color(hud.modulate.r, hud.modulate.g, hud.modulate.b), Color.WHITE, a2 + ": normal HUD")
		Game.area_id = a2
		assert_false(bool(dial.shows_lantern()), a2 + ": the sky")
	hud.queue_free()
	await wait_frames(1)
