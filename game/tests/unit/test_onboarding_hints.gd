extends "res://tests/test_case.gd"
## Module D4: Chapter Two onboarding hints (src/world/story_ch2/onboarding_hints.gd). Every trigger arms its hint
## and the hint is emitted through Events.hint exactly once per save (also across a save / load), Settings
## "show_hints" is respected, nothing appears during cutscenes, boss encounters, Echo Trials, ordinary fights, horror
## moments, outside a safe zone in a horror-director area or while the hint card shows another tip, the calm / gap
## pacing holds, only hint_ob_* flags are ever written, and the real HUD hint card accepts the hints.

const Onboarding := preload("res://src/world/story_ch2/onboarding_hints.gd")
const HintCard := preload("res://src/ui/hud/hint_card.gd")


class StubDirector extends Node:
	var state: String = "calm"
	var held: bool = false

	func get_state() -> String:
		return state

	func is_held() -> bool:
		return held


## The two properties of ui_root / hud.gd the module reads to find the HUD hint card (ui.hud.hints).
class StubHud extends Control:
	var hints: Control = null


class StubUiWithHud extends Node:
	var hud: Control = null


var ob: Node = null
var shown: Array = []                 # [id, text] per Events.hint
var _stub_ui: Node = null
var _saved := {}
var _settings := {}
var _extra: Array = []


func before_each() -> void:
	fresh_state()
	GameState.active = true
	GameState.stats["play_seconds"] = 5000.0
	_saved = {"mode": Game.mode, "ui": Game.ui, "area_id": Game.area_id, "safe": Game.in_safe_zone,
		"director": Game.director}
	_settings = Settings.values.duplicate(true)
	Settings.values["show_hints"] = true
	Settings.values["companion_auto_attack"] = true
	Settings.values["companion_autocast"] = true
	_stub_ui = Node.new()
	_stub_ui.name = "StubUi"
	add_child(_stub_ui)
	Game.ui = _stub_ui
	Game.mode = "playing"
	Game.area_id = "surface"
	Game.in_safe_zone = true
	Game.director = null
	shown.clear()
	Events.hint.connect(_on_hint)
	ob = Onboarding.new()
	add_child(ob)
	ob.set_process(false)             # the tests drive tick() themselves


func after_each() -> void:
	if Events.hint.is_connected(_on_hint):
		Events.hint.disconnect(_on_hint)
	for id in ["count_velour", "test_boss"]:
		Events.boss_encounter_changed.emit(id, false)
	if Game.mode == "cutscene":
		Game.mode = "playing"
	Game.mode = String(_saved["mode"])
	Game.ui = _saved["ui"]
	Game.area_id = String(_saved["area_id"])
	Game.in_safe_zone = bool(_saved["safe"])
	Game.director = _saved["director"]
	Settings.values = _settings
	for n in _extra:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_extra.clear()
	if is_instance_valid(ob):
		ob.queue_free()
	if is_instance_valid(_stub_ui):
		_stub_ui.queue_free()
	GameState.active = false
	await wait_frames(2)


func _on_hint(id: String, text: String) -> void:
	shown.append([id, text])


func _ids() -> Array:
	var out: Array = []
	for s in shown:
		out.append(String(s[0]))
	return out


func _count(id: String) -> int:
	return _ids().count(id)


## Steps the module (1 s per step, like 2 real steps) until something is emitted; returns that id ("" = none).
func _run(steps: int = 200) -> String:
	for i in steps:
		var got: String = ob.tick(1.0)
		if got != "":
			return got
	return ""


## Clears every pacing timer between two scenarios in the same test.
func _fresh_pacing() -> void:
	ob.set("_gap", 0.0)
	ob.set("_calm_t", 0.0)
	ob.set("_horror_quiet", 0.0)


# --- Fire once per save -----------------------------------------------------------------------------------------

func test_a_hint_fires_once_per_save_even_across_a_reload() -> void:
	Events.item_added.emit("copper_ore", 2)
	assert_true(ob.armed_ids().has("ob_furnace"), "picking up copper ore arms the furnace hint")
	assert_eq(_run(), "ob_furnace", "emitted once the moment is calm")
	assert_true(bool(GameState.get_flag("hint_ob_furnace")), "remembered in the save like every hint (hint_<id>)")
	var text := String(shown[0][1])
	assert_true(text.contains("Furnace"), "the furnace text")
	# Same trigger again: never armed, never shown.
	Events.item_added.emit("iron_ore", 1)
	_fresh_pacing()
	assert_false(ob.armed_ids().has("ob_furnace"), "not armed again")
	assert_eq(_run(40), "", "nothing more")
	# Save, reset, load: still remembered.
	assert_true(SaveSystem.save_game(true), "saved")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "loaded")
	GameState.active = true
	GameState.stats["play_seconds"] = 5000.0
	Events.item_added.emit("copper_ore", 1)
	_fresh_pacing()
	assert_eq(_run(40), "", "a reloaded save never repeats it")
	assert_eq(_count("ob_furnace"), 1, "shown exactly once")


## [setup method ("" = none), trigger method, expected hint id, area Krystal is in]
const TRIGGER_CASES := [
	["", "_t_invitation", "ob_ch2_invitation", "surface"],
	["", "_t_reach", "ob_reach_home", "hallowmere_reach"],
	["", "_t_arch", "ob_lantern_road", "hallowmere_reach"],
	["_s_weaver", "_t_below", "ob_echo_trial", "below"],
	["_s_mochi", "_t_attack", "ob_companion_skill", "surface"],
	["", "_t_armor", "ob_equipment", "surface"],
	["", "_t_wand", "ob_wand", "surface"],
	["", "_t_overflow", "ob_storage", "surface"],
	["", "_t_ore", "ob_furnace", "surface"],
	["", "_t_loom", "ob_loom", "surface"],
	["", "_t_dye", "ob_recolour", "surface"],
	["", "_t_stairs", "ob_stairs", "surface"],
	["", "_t_three_pieces", "ob_undo", "surface"],
	["", "_t_pumpkin_seeds", "ob_crops", "surface"],
	["", "_t_restyle", "ob_wardrobe", "surface"],
	["_s_pebble_skill_known", "_t_skill_used", "ob_companion_menu", "surface"],
	["", "_t_mastery", "ob_mastery", "surface"],
	["_s_chest", "_t_craft", "ob_chest_crafting", "surface"],
	["", "_t_choir", "ob_expedition_board", "surface"],
	["", "_t_surface", "ob_optional", "surface"],
]


func _s_weaver() -> void:
	GameState.set_flag("weaver_defeated", true)


func _s_mochi() -> void:
	GameState.befriend("mochi")


func _s_pebble_skill_known() -> void:
	GameState.befriend("pebble")
	GameState.set_flag("hint_ob_companion_skill", true)


func _s_chest() -> void:
	GameState.add_structure("storage_chest", Vector3(2, 0, 2), 0.0, "surface")


func _t_invitation() -> void:
	GameState.set_flag("ward_restored", true)
	GameState.set_flag("chapter_one_complete", true)
	Events.area_loaded.emit("surface")


func _t_reach() -> void:
	Events.area_loaded.emit("hallowmere_reach")


func _t_arch() -> void:
	Events.arch_lit.emit("commons")


func _t_below() -> void:
	Events.area_loaded.emit("below")


func _t_attack() -> void:
	Events.companion_attacked.emit("mochi", null)


func _t_armor() -> void:
	Events.item_added.emit("padded_hood", 1)


func _t_wand() -> void:
	Events.item_added.emit("sparkseed_wand", 1)


func _t_overflow() -> void:
	Events.item_overflow_dropped.emit("wood", 3, Vector3.ZERO)


func _t_ore() -> void:
	Events.item_added.emit("iron_ore", 1)


func _t_loom() -> void:
	Events.structure_placed.emit("s_test_loom", "loom")


func _t_dye() -> void:
	Events.crafted.emit("dye:rose", "", 0)


func _t_stairs() -> void:
	Events.structure_placed.emit("s_test_stairs", "wood_stairs")


func _t_three_pieces() -> void:
	for i in 3:
		Events.structure_placed.emit("s_test_%d" % i, "wood_floor")


func _t_pumpkin_seeds() -> void:
	Events.item_added.emit("pumpkin_seeds", 2)


func _t_restyle() -> void:
	Events.appearance_changed.emit()


func _t_skill_used() -> void:
	Events.companion_skill_used.emit("pebble", "stoneheart")


func _t_mastery() -> void:
	Events.mastery_changed.emit("gathering", 60, 1)


func _t_craft() -> void:
	Events.crafted.emit("stool", "stool", 1)


func _t_choir() -> void:
	GameState.set_flag("ch2_choir_defeated", true)


func _t_surface() -> void:
	Events.area_loaded.emit("surface")


func test_every_trigger_arms_its_own_hint_and_fires_once() -> void:
	var covered: Array = []
	for c in TRIGGER_CASES:
		fresh_state()
		GameState.active = true
		GameState.stats["play_seconds"] = 5000.0
		ob.call("_reset_session")
		Game.area_id = String(c[3])
		shown.clear()
		if String(c[0]) != "":
			call(String(c[0]))
		ob.call("_reset_session")        # only the trigger under test may arm something
		var want := String(c[2])
		call(String(c[1]))
		assert_true(ob.armed_ids().has(want), "%s is armed by its trigger (armed: %s)" % [want, str(ob.armed_ids())])
		var got := _run()
		assert_eq(got, want, "the first hint shown for %s" % String(c[1]))
		# The same trigger again never shows it twice.
		call(String(c[1]))
		_fresh_pacing()
		for i in 150:
			ob.tick(1.0)
		assert_eq(_count(want), 1, "%s shown exactly once" % want)
		covered.append(want)
	for id in Onboarding.HINTS:
		assert_true(covered.has(id), "the trigger table covers %s" % id)


func test_the_skill_hint_leads_to_the_menu_hint_later() -> void:
	GameState.befriend("lumi")
	ob.call("_reset_session")
	Events.companion_skill_ready.emit("lumi")
	assert_eq(_run(), "ob_companion_skill")
	assert_true(ob.armed_ids().has("ob_companion_menu"), "the friend's menu comes next")
	assert_eq(_run(40), "", "not straight away (gap and delay)")
	assert_eq(_run(200), "ob_companion_menu", "a little later")


func test_companion_hints_wait_for_a_follower() -> void:
	ob.arm("ob_companion_skill")
	assert_eq(_run(60), "", "nobody follows: it waits")
	assert_true(ob.armed_ids().has("ob_companion_skill"), "still armed")
	GameState.befriend("mochi")
	assert_eq(_run(), "ob_companion_skill", "shown once a friend follows")


func test_redundant_hints_are_dropped_without_being_marked() -> void:
	GameState.set_flag("hint_furnace_queue", true)   # she already used a furnace
	Events.item_added.emit("copper_ore", 1)
	assert_eq(_run(40), "", "nothing to say")
	assert_false(ob.armed_ids().has("ob_furnace"), "dropped")
	assert_false(bool(GameState.get_flag("hint_ob_furnace")), "not marked as shown")
	GameState.set_flag("chapter_one_complete", true)
	GameState.set_flag("ch2_accepted", true)
	ob.arm("ob_ch2_invitation")
	_fresh_pacing()
	assert_eq(_run(40), "", "the invitation was already accepted")
	# Build mode's own first-entry tip (build_mode.gd "build_controls_ch2") already named the undo key.
	GameState.set_flag("hint_build_controls_ch2", true)
	_fresh_pacing()
	for i in 3:
		Events.structure_placed.emit("s_redundant_%d" % i, "wood_floor")
	assert_true(ob.armed_ids().has("ob_undo"), "armed by three placements")
	assert_eq(_run(40), "", "the undo tip would only repeat build mode's tip")
	assert_false(ob.armed_ids().has("ob_undo"), "dropped")
	assert_false(bool(GameState.get_flag("hint_ob_undo")), "not marked either")


func test_area_bound_hints_wait_for_their_area() -> void:
	GameState.set_flag("weaver_defeated", true)
	ob.arm("ob_echo_trial")
	Game.area_id = "surface"
	assert_eq(_run(40), "", "the echo trial hint is about the Below")
	Game.area_id = "below"
	assert_eq(_run(), "ob_echo_trial", "shown there")


func test_new_journeys_hear_about_the_wardrobe_later() -> void:
	GameState.stats["play_seconds"] = 20.0
	GameState.wardrobe["notice_shown"] = true      # styled on the creation screen
	assert_eq(_run(30), "", "not in the first minutes")
	assert_true(ob.armed_ids().has("ob_wardrobe"), "but armed")
	GameState.stats["play_seconds"] = float(Onboarding.WARDROBE_MIN_PLAY) + 1.0
	assert_eq(_run(), "ob_wardrobe", "after a few minutes of play")


# --- Settings -----------------------------------------------------------------------------------------------------

func test_show_hints_off_means_nothing_is_armed_or_shown() -> void:
	Settings.set_value("show_hints", false)
	Events.item_added.emit("padded_vest", 1)
	assert_false(ob.armed_ids().has("ob_equipment"), "not armed with hints off")
	assert_eq(_run(60), "", "nothing shown")
	assert_false(bool(GameState.get_flag("hint_ob_equipment")), "not marked: it can still come later")
	Settings.set_value("show_hints", true)
	Events.item_added.emit("padded_vest", 1)
	assert_eq(_run(), "ob_equipment", "shown once hints are back on")


func test_turning_hints_off_drops_armed_hints() -> void:
	Events.item_added.emit("sparkseed_wand", 1)
	assert_true(ob.armed_ids().has("ob_wand"), "armed")
	Settings.set_value("show_hints", false)
	assert_true(ob.armed_ids().is_empty(), "dropped at once")
	assert_eq(ob.suppression_reason(), "hints_off")
	Settings.set_value("show_hints", true)
	assert_eq(_run(40), "", "not resurrected")


# --- Never during cutscenes, bosses or horror -------------------------------------------------------------------

func test_suppressed_during_a_cutscene() -> void:
	Game.set_cutscene(true)
	Events.item_added.emit("iron_ore", 1)
	assert_eq(ob.suppression_reason(), "cutscene")
	assert_eq(_run(60), "", "never during a cutscene")
	Game.set_cutscene(false)
	assert_eq(_run(), "ob_furnace", "after it")


func test_suppressed_while_the_game_is_not_playing() -> void:
	Events.item_added.emit("iron_ore", 1)
	for m in ["loading", "dead"]:
		Game.mode = m
		assert_eq(ob.suppression_reason(), "not_playing", m)
		assert_eq(_run(20), "", "never while " + m)
	Game.mode = "playing"
	assert_eq(_run(), "ob_furnace")


func test_suppressed_during_a_boss_encounter() -> void:
	Events.boss_encounter_changed.emit("count_velour", true)
	Events.item_added.emit("padded_boots", 1)
	assert_eq(ob.suppression_reason(), "boss")
	assert_eq(_run(80), "", "never during a boss fight")
	Events.boss_encounter_changed.emit("count_velour", false)
	assert_eq(_run(), "ob_equipment", "after the fight")


func test_suppressed_after_a_horror_moment() -> void:
	Events.item_added.emit("pumpkin_seeds", 1)
	Events.horror_event.emit("authored:test_moment", {})
	assert_eq(ob.suppression_reason(), "horror")
	var got := ""
	for i in int(Onboarding.HORROR_QUIET) - 1:
		got = ob.tick(1.0)
		if got != "":
			break
	assert_eq(got, "", "quiet for a while after a horror moment")
	assert_eq(_run(), "ob_crops", "then the hint")


func test_suppressed_while_the_director_builds_up_or_holds() -> void:
	var d := StubDirector.new()
	add_child(d)
	_extra.append(d)
	Game.director = d
	Game.area_id = "below"
	Events.item_added.emit("copper_ore", 1)
	for st in ["anticipation", "encounter"]:
		d.state = st
		assert_eq(ob.suppression_reason(), "horror", st)
		assert_eq(_run(20), "", "never while the director is in " + st)
	d.state = "calm"
	d.held = true
	assert_eq(ob.suppression_reason(), "horror", "held by an authored scene")
	d.held = false
	Events.horror_state_changed.emit("encounter")
	assert_eq(ob.suppression_reason(), "horror", "the state signal counts too")
	Events.horror_state_changed.emit("calm")
	Game.in_safe_zone = false
	assert_eq(ob.suppression_reason(), "unsafe", "horror areas: only in a safe zone")
	assert_eq(_run(20), "", "nothing outside the safe zone")
	Game.in_safe_zone = true
	assert_eq(_run(), "ob_furnace", "at a lantern / the landing")
	# The director freed with its area (Game.director not cleared yet): no error, just no director.
	d.free()
	assert_eq(ob.suppression_reason(), "", "a freed director is ignored")


func test_suppressed_during_an_ordinary_fight() -> void:
	Events.item_added.emit("copper_ore", 1)
	Events.combat_state_changed.emit(true)          # the music director's threat monitor: a fight is on
	assert_eq(ob.suppression_reason(), "combat")
	assert_eq(_run(40), "", "never in the middle of a fight")
	Events.combat_state_changed.emit(false)
	assert_eq(_run(), "ob_furnace", "once the fight is over")
	# The director clears its threat without a signal on leaving an area or on death: never stuck "in combat".
	Events.combat_state_changed.emit(true)
	ob.call("_on_area_exiting", "surface")
	assert_true(ob.suppression_reason() != "combat", "leaving the area ends it")
	Events.combat_state_changed.emit(true)
	ob.call("_on_player_died")
	assert_true(ob.suppression_reason() != "combat", "so does a death")
	Events.combat_state_changed.emit(false)         # leave the music director as it was


func test_suppressed_inside_an_echo_trial() -> void:
	Events.item_added.emit("sparkseed_wand", 1)
	Game.area_id = "echo_trial"
	assert_eq(ob.suppression_reason(), "trial")
	assert_eq(_run(60), "", "never inside a remembered boss fight (nothing is written there)")
	assert_false(bool(GameState.get_flag("hint_ob_wand")), "no flag written in the trial")
	Game.area_id = "below"
	assert_eq(_run(), "ob_wand", "back at the checkpoint lantern")


func test_waits_while_the_hint_card_shows_another_tip() -> void:
	var card: Control = HintCard.new()
	var hud := StubHud.new()
	hud.add_child(card)
	hud.hints = card
	var ui := StubUiWithHud.new()
	ui.add_child(hud)
	ui.hud = hud
	add_child(ui)
	_extra.append(ui)
	Game.ui = ui
	await wait_frames(1)
	Events.hint.emit("test_other_tip", "Another system's tip.")
	assert_true(card.is_showing(), "another tip is up")
	Events.item_added.emit("copper_ore", 1)
	assert_eq(ob.suppression_reason(), "card")
	assert_eq(_run(40), "", "never stacked behind another tip")
	card.call("_process", 20.0)                     # that tip's reading time runs out
	assert_false(card.is_showing(), "the card is free")
	assert_eq(_run(), "ob_furnace", "then the onboarding tip")
	assert_true(card.is_showing(), "on the card")


func test_writes_nothing_but_its_own_hint_flags() -> void:
	# No hint card listens here (stub UI), so the module marks the hints itself: still only hint_ob_<id>.
	GameState.befriend("mochi")
	var before: Dictionary = GameState.flags.duplicate(true)
	for id in ["ob_equipment", "ob_wand", "ob_furnace", "ob_companion_skill"]:
		assert_true(ob.arm(id), "armed " + id)
	var got: Array = []
	for i in 400:
		var e: String = ob.tick(1.0)
		if e != "":
			got.append(e)
	assert_eq(got.size(), 5, "four hints and the friend's menu that follows the skill hint: %s" % str(got))
	for k in GameState.flags:
		if not before.has(k) or str(before[k]) != str(GameState.flags[k]):
			assert_true(String(k).begins_with("hint_ob_"), "only its own hint flags change (%s)" % k)
	for k in before:
		assert_true(GameState.flags.has(k), "nothing removed (%s)" % k)


func test_suppressed_while_a_menu_is_open_and_without_a_ui() -> void:
	Events.item_added.emit("copper_ore", 1)
	Game.push_ui("test_menu")
	assert_eq(ob.suppression_reason(), "busy")
	assert_eq(_run(20), "", "never over a menu")
	Game.pop_ui("test_menu")
	Game.ui = null
	assert_eq(ob.suppression_reason(), "no_ui")
	assert_eq(_run(20), "", "never without the gameplay UI")
	Game.ui = _stub_ui
	assert_eq(_run(), "ob_furnace")


# --- Pacing and session -------------------------------------------------------------------------------------------

func test_calm_seconds_and_gap_between_hints() -> void:
	ob.arm("ob_wand")
	ob.arm("ob_equipment")
	assert_eq(ob.tick(1.0), "", "not before CALM_SECONDS")
	var first := _run(10)
	assert_eq(first, "ob_equipment", "priority order: equipment before wand")
	var waited := 0
	var second := ""
	for i in 100:
		second = ob.tick(1.0)
		waited += 1
		if second != "":
			break
	assert_eq(second, "ob_wand", "then the next one")
	assert_true(float(waited) >= Onboarding.MIN_GAP, "at least MIN_GAP seconds apart (%d s)" % waited)


func test_title_screen_clears_the_session() -> void:
	ob.arm("ob_wand")
	Game.mode = "title"
	assert_eq(ob.tick(1.0), "")
	assert_true(ob.armed_ids().is_empty(), "nothing carries over to another journey")
	Game.mode = "playing"
	ob.arm("ob_wand")
	Events.game_loaded.emit()
	assert_true(ob.armed_ids().is_empty(), "loading a save starts clean")


func test_attach_creates_one_instance() -> void:
	var parent := Node.new()
	add_child(parent)
	_extra.append(parent)
	var a: Node = Onboarding.attach(parent)
	var b: Node = Onboarding.attach(parent)
	assert_not_null(a, "created")
	assert_true(a == b, "idempotent")
	assert_eq(parent.get_child_count(), 1, "one child")
	assert_true(a.is_in_group(Onboarding.GROUP), "grouped")
	assert_eq(a.process_mode, Node.PROCESS_MODE_PAUSABLE, "timers stop while paused")
	assert_false(bool(a.get("auto_tick")), "headless: never steps by itself (other suites see no hints)")
	assert_false(a.is_processing(), "not processing in headless runs")
	a.queue_free()
	var c: Node = Onboarding.attach(parent)
	assert_true(c != a and c != null, "a node on its way out is replaced (the runner re-wires between suites)")
	await wait_frames(1)
	assert_eq(parent.get_child_count(), 1, "still one")
	assert_true(Onboarding.attach(parent) == c, "found again (by group, whatever its name)")


func test_attach_under_the_game_autoload_like_the_hook() -> void:
	var existed := false
	for c in Game.get_children():
		if c.is_in_group(Onboarding.GROUP) and not c.is_queued_for_deletion():
			existed = true
	var n: Node = Onboarding.attach(Game)
	assert_not_null(n, "attached")
	assert_true(n.get_parent() == Game, "a child of Game (session-wide)")
	assert_true(Onboarding.attach(Game) == n, "the hook can run again safely")
	assert_eq(n.process_mode, Node.PROCESS_MODE_PAUSABLE, "pauses with the game even under the ALWAYS autoload")
	if not existed:
		n.queue_free()      # leave Game as this suite found it
		await wait_frames(1)


# --- With the real HUD hint card ----------------------------------------------------------------------------------

func test_the_real_hint_card_shows_and_remembers_it() -> void:
	var card: Control = HintCard.new()
	add_child(card)
	_extra.append(card)
	await wait_frames(1)
	Events.item_added.emit("sparkseed_wand", 1)
	assert_eq(_run(), "ob_wand")
	assert_true(card.is_showing() or card.queued_count() > 0, "the card took it")
	assert_true(bool(GameState.get_flag("hint_ob_wand")), "the card's own once-per-save flag")
	assert_true(String(card.text_l.text).contains("Left Mouse"), "{attack} became the key label: " + String(card.text_l.text))
	assert_false(String(card.text_l.text).contains("{"), "no raw token left")
