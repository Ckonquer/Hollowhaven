extends "res://tests/test_case.gd"
## Tobin's Lost Shift (module B10): flags, rewards, lore, the door / hatch travel rules and the authored echo.
##   * arrival sets c1x_annex_entered; Tobin's service note (MP §17 verbatim) grants rw_c1x_tobin exactly once
##     (c1x_tobin_shift + the Miner's Lamp + echo shards from data/sources.gd), also across a save/load, and
##     never while something is chasing her; the letter sets c1x_tobin_letter_found; the lantern mark is the
##     early Chapter Two clue; the chalk rules teach the Drudge's two tells;
##   * the hatch opens once (ta_hatch_open), both ends agree, and each end travels to its spec spawn;
##   * the surface side door is jammed until mine_opened, then leads to annex_entry (comfort screen once);
##   * all four objective flags complete opt_tobins_shift through the optional log (which pays its own reward);
##   * a real round trip through Game.change_area: annex -> hatch -> surface annex_hatch -> side door -> annex.

const Layout := preload("res://src/world/annex/annex_layout.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const DoorScript := preload("res://src/world/annex/annex_door.gd")
const HatchScript := preload("res://src/world/annex/annex_hatch.gd")
const WORLD := "res://src/world/areas_ch2/tobin_annex_world.gd"
const MP_TOBIN_NOTE := "I dropped the lantern when the passage answered me. Hask found me at the sluice. Tell whoever comes after us: the garden below is real."

var area: Node3D = null
var _holder: Node3D = null
var _saved_mode := ""
var _saved_player: Node3D = null


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	_saved_player = Game.player
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	Game.mode = _saved_mode
	Game.player = _saved_player
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(2)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(2)
	return a


# --- lore ------------------------------------------------------------------------------------------------

func test_lore_is_reachable_through_lore_db() -> void:
	LoreDB.reload()
	var ids: Array = LoreDB.ids()
	for id in ["lore_ch2_shift_rules", "lore_ch2_tobin_letter", "lore_ch2_tobin_note", "lore_ch2_lantern_mark"]:
		assert_true(LoreDB.has_lore(id), "LoreDB knows %s" % id)
		assert_true(ids.has(id), "%s is listed for the journal" % id)
		var l: Dictionary = LoreDB.get_lore(id)
		assert_true(String(l["title"]) != "" and String(l["text"]) != "", "%s has a title and a text" % id)
	assert_eq(String(LoreDB.get_lore("lore_ch2_tobin_note")["text"]), MP_TOBIN_NOTE, "Tobin's note is MP §17 verbatim")
	assert_true(ids.find("landing_notice") < ids.find("lore_ch2_tobin_note"), "legacy notes first")
	var rules := String(LoreDB.get_lore("lore_ch2_shift_rules")["text"])
	assert_true(rules.contains("lifts its pick high") and rules.contains("drags the pick"), "the chalk rules teach both tells")
	var mark := String(LoreDB.get_lore("lore_ch2_lantern_mark")["text"])
	assert_true(mark.contains("north") and mark.contains("lanterns wake"), "the mark points at the Lanternwake road")


# --- arrival, note, letter, mark ---------------------------------------------------------------------------

func test_arrival_sets_the_entered_flag() -> void:
	area = await _make_area()
	var p := Node3D.new()
	_holder.add_child(p)
	p.global_position = area.get_spawn("annex_entry").origin
	assert_false(bool(GameState.get_flag("c1x_annex_entered")))
	area.on_player_spawned(p)
	assert_true(bool(GameState.get_flag("c1x_annex_entered")), "c1x_annex_entered")
	assert_eq(String(area.current_zone), "ta_entry")


func test_service_note_grants_rw_c1x_tobin_once() -> void:
	area = await _make_area()
	var bundle: Dictionary = ItemDB.reward_bundle("rw_c1x_tobin")
	assert_eq(String(bundle.get("by", "")), "content", "a content bundle this module grants")
	assert_true((bundle.get("flags", []) as Array).has("c1x_tobin_shift"), "it sets c1x_tobin_shift")
	var items: Dictionary = bundle.get("items", {})
	assert_true(items.has("miner_lamp") and items.has("echo_shard"), "the Miner's Lamp and echo shards")
	var before := {}
	for id in items:
		before[id] = GameState.count_item(String(id))
	assert_true(area.dropped_lamp.visible, "Tobin's lamp lies by the sluice")
	assert_eq(String(area.note_spot.get_interaction(null)["text"]), "Read the note by the dropped lamp")
	var said: Array = []
	var cb := func(speaker: String, text: String, _d: float) -> void: said.append([speaker, text])
	Events.say.connect(cb)
	area.read_note(null)
	Events.say.disconnect(cb)
	assert_eq(said.size(), 1, "the note is read aloud")
	if said.size() == 1:
		assert_eq(String(said[0][0]), "Tobin's Service Note")
		assert_eq(String(said[0][1]), MP_TOBIN_NOTE)
	assert_true(GameState.lore.has("lore_ch2_tobin_note"), "journal entry")
	assert_true(bool(GameState.get_flag("c1x_tobin_shift")), "c1x_tobin_shift (Miner's Lamp unlock)")
	assert_true(GameState.has_reward("rw_c1x_tobin"), "recorded in the reward ledger")
	for id in items:
		assert_eq(GameState.count_item(String(id)) - int(before[id]), int(items[id]), "%s given once" % id)
	assert_false(area.dropped_lamp.visible, "Krystal took the lamp")
	assert_eq(String(area.note_spot.get_interaction(null)["text"]), "Read Tobin's note again")
	# Reading again (and again) never pays twice.
	area.read_note(null)
	area.read_note(null)
	for id in items:
		assert_eq(GameState.count_item(String(id)) - int(before[id]), int(items[id]), "%s still given once" % id)


func test_reward_stays_once_across_save_and_load() -> void:
	area = await _make_area()
	GameState.active = true
	area.read_note(null)
	var lamps := GameState.count_item("miner_lamp")
	var shards := GameState.count_item("echo_shard")
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_false(GameState.has_reward("rw_c1x_tobin"), "a fresh state forgets it")
	assert_true(SaveSystem.load_game(), "loaded")
	assert_true(GameState.has_reward("rw_c1x_tobin"), "the ledger survives the save")
	area.queue_free()
	await wait_frames(2)
	area = await _make_area()
	assert_false(area.dropped_lamp.visible, "the lamp stays taken after loading")
	area.read_note(null)
	assert_eq(GameState.count_item("miner_lamp"), lamps, "no second lamp after loading")
	assert_eq(GameState.count_item("echo_shard"), shards, "no second shard bundle after loading")
	GameState.active = false


func test_note_waits_while_something_chases_her() -> void:
	area = await _make_area()
	var p := Node3D.new()
	_holder.add_child(p)
	p.global_position = Layout.POINTS["note"]
	Game.player = p
	var chaser: Node3D = Node3D.new()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nfunc is_threatening() -> bool:\n\treturn true\n"
	s.reload()
	chaser.set_script(s)
	chaser.add_to_group("enemy")
	_holder.add_child(chaser)
	chaser.global_position = p.global_position + Vector3(4, 0, 0)
	area.read_note(null)
	assert_false(GameState.has_reward("rw_c1x_tobin"), "no reward while chased")
	assert_false(GameState.lore.has("lore_ch2_tobin_note"), "no reading while chased")
	# Tobin's letter (in the Drudge's own hall) and the mark wait for quiet too.
	area.read_letter(null)
	area.read_mark(null)
	assert_false(bool(GameState.get_flag("c1x_tobin_letter_found")) or GameState.lore.has("lore_ch2_tobin_letter"), "no letter while chased")
	assert_false(bool(GameState.get_flag("c1x_lantern_mark_seen")), "no mark while chased")
	chaser.global_position = p.global_position + Vector3(30, 0, 0)
	area.read_note(null)
	assert_true(GameState.has_reward("rw_c1x_tobin"), "read once it is quiet")
	area.read_letter(null)
	assert_true(bool(GameState.get_flag("c1x_tobin_letter_found")), "the letter once it is quiet")


func test_letter_and_mark_and_rules() -> void:
	area = await _make_area()
	assert_eq(String(area.letter_spot.get_interaction(null)["text"]), "Open locker nine")
	area.read_letter(null)
	assert_true(bool(GameState.get_flag("c1x_tobin_letter_found")), "c1x_tobin_letter_found")
	assert_true(GameState.lore.has("lore_ch2_tobin_letter"))
	assert_eq(String(area.letter_spot.get_interaction(null)["text"]), "Read Tobin's letter again")
	area.read_mark(null)
	assert_true(bool(GameState.get_flag("c1x_lantern_mark_seen")), "the clue is remembered")
	assert_true(GameState.lore.has("lore_ch2_lantern_mark"))
	area.read_shift_rules(null)
	assert_true(GameState.lore.has("lore_ch2_shift_rules"))
	assert_false(GameState.has_reward("rw_c1x_tobin"), "only the service note pays the bundle")
	# Positions: every story spot is where the layout says, in the right zone, reachable (interactable).
	assert_eq(area.get_zone_at(area.letter_spot.global_position), "ta_lockers")
	assert_eq(area.get_zone_at(area.note_spot.global_position), "ta_sump")
	assert_eq(area.get_zone_at(area.mark_spot.global_position + Vector3.UP), "ta_sump")
	assert_eq(area.get_zone_at(area.board_spot.global_position), "ta_entry")
	for n in [area.letter_spot, area.note_spot, area.mark_spot, area.board_spot]:
		assert_true((n as Node).is_in_group("interactable"), "%s is interactable" % (n as Node).name)
	# A new build after the letter shows Tobin's locker standing open.
	area.queue_free()
	await wait_frames(2)
	area = await _make_area()
	var pivot: Node3D = area.tobin_locker["door_pivot"]
	assert_true(absf(pivot.rotation.y) > 1.0, "Tobin's locker stays open")


func test_drudge_hint_teaches_before_the_fight() -> void:
	area = await _make_area()
	var hints: Array = []
	var cb := func(id: String, text: String) -> void: hints.append([id, text])
	Events.hint.connect(cb)
	area.on_zone("ta_entry")
	area.on_zone("ta_lockers")
	Events.hint.disconnect(cb)
	if area.drudge_fallback:
		assert_eq(hints.size(), 0, "no Drudge, no hint")
		return
	assert_eq(hints.size(), 1, "one hint on reaching the lockers")
	if hints.size() == 1:
		assert_eq(String(hints[0][0]), "ta_drudge_tells")
		var t := String(hints[0][1])
		assert_true(t.contains("pick high") and t.contains("drags the pick"), "both tells named: " + t)
	GameState.set_flag("c1x_drudge_defeated", true)
	hints.clear()
	Events.hint.connect(cb)
	area.on_zone("ta_entry")
	area.on_zone("ta_lockers")
	Events.hint.disconnect(cb)
	assert_eq(hints.size(), 0, "no hint once it is beaten")


# --- the authored echo --------------------------------------------------------------------------------------

func test_echo_moment_once_per_save() -> void:
	var old_intensity: Variant = Settings.get_value("horror_intensity")
	Settings.set_value("horror_intensity", 0)
	area = await _make_area()
	var events: Array = []
	var captions: Array = []
	var ecb := func(id: String, _d: Dictionary) -> void: events.append(id)
	var ccb := func(t: String) -> void: captions.append(t)
	Events.horror_event.connect(ecb)
	Events.caption.connect(ccb)
	area.on_zone("ta_sump")
	await wait_seconds(1.1)
	area.on_zone("ta_lockers")
	area.on_zone("ta_sump")
	await wait_seconds(1.1)
	Events.horror_event.disconnect(ecb)
	Events.caption.disconnect(ccb)
	Settings.set_value("horror_intensity", old_intensity)
	assert_true(bool(GameState.get_flag("ta_moment_echo")), "flag ta_moment_echo")
	assert_eq(events, ["authored:ta_echo"], "one authored moment (the music quiets for it)")
	assert_eq(captions.size(), 1, "one caption")
	if captions.size() == 1:
		assert_true(String(captions[0]).contains("Only an echo"), "Gentle says plainly it is an echo")
	assert_false(bool(GameState.get_flag("c1x_drudge_defeated")) and not area.drudge_fallback, "the echo never touches the encounter")


## The echo never plays over a chase (MP §14: one thing at once): it waits, then plays once it is quiet while
## Krystal is still in the sump.
func test_echo_waits_for_quiet() -> void:
	var old_intensity: Variant = Settings.get_value("horror_intensity")
	Settings.set_value("horror_intensity", 0)
	area = await _make_area()
	var p := Node3D.new()
	_holder.add_child(p)
	p.global_position = Layout.POINTS["echo"] + Vector3(3.0, -0.8, 0.0)
	Game.player = p
	var chaser := Node3D.new()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nfunc is_threatening() -> bool:\n\treturn true\n"
	s.reload()
	chaser.set_script(s)
	chaser.add_to_group("enemy")
	_holder.add_child(chaser)
	chaser.global_position = p.global_position + Vector3(0, 0, 6)
	var events: Array = []
	var ecb := func(id: String, _d: Dictionary) -> void: events.append(id)
	Events.horror_event.connect(ecb)
	area.on_zone("ta_sump")
	assert_eq(events.size(), 0, "no echo while chased")
	assert_false(bool(GameState.get_flag("ta_moment_echo")), "the moment is not used up")
	await wait_seconds(2.3)
	assert_eq(events.size(), 0, "still waiting while the chase goes on")
	chaser.global_position = p.global_position + Vector3(0, 0, 60)
	await wait_seconds(2.3)
	Events.horror_event.disconnect(ecb)
	Settings.set_value("horror_intensity", old_intensity)
	assert_eq(events, ["authored:ta_echo"], "played once it is quiet")
	assert_true(bool(GameState.get_flag("ta_moment_echo")))


# --- door and hatch ---------------------------------------------------------------------------------------------

func test_hatch_opens_once_and_leads_up() -> void:
	area = await _make_area()
	var h: Node3D = area.hatch
	assert_true(h.is_in_group("area_exit") and h.is_in_group("interactable"))
	assert_eq(String(h.get("target_area")), "surface")
	assert_eq(String(h.get("target_spawn")), "annex_hatch")
	assert_eq(String(h.get_interaction(null)["text"]), "Slide back the rusted bolt")
	var opened := [0]
	h.opened.connect(func() -> void: opened[0] += 1)
	var trips: Array = []
	h.travelled.connect(func(a: String, s: String) -> void: trips.append([a, s]))
	h.set("travel_enabled", false)
	h.interact(null)
	assert_true(bool(GameState.get_flag("ta_hatch_open")), "ta_hatch_open")
	assert_eq(opened[0], 1, "opened once")
	assert_eq(trips.size(), 0, "unbolting is not a trip")
	assert_false(bool(h.open_hatch()), "it only opens once")
	assert_eq(opened[0], 1)
	assert_eq(String(h.get_interaction(null)["text"]), "Climb up to the mine mouth")
	h.interact(null)
	assert_eq(trips, [["surface", "annex_hatch"]], "leads up to the surface spawn annex_hatch")
	# Rebuilt later: it is already open.
	area.queue_free()
	await wait_frames(2)
	area = await _make_area()
	assert_true(bool(area.hatch.get("is_open")), "stays open")


func test_surface_hatch_follows_the_flag() -> void:
	var h: Node3D = HatchScript.new()
	h.setup({"variant": "ground"})
	_holder.add_child(h)
	assert_eq(String(h.get("target_area")), "tobin_annex")
	assert_eq(String(h.get("target_spawn")), "annex_hatch_below")
	var info: Dictionary = h.get_interaction(null)
	assert_false(bool(info["enabled"]), "bolted from below at first")
	assert_eq(String(info.get("reason", "")), "Bolted fast from below.")
	var trips: Array = []
	h.travelled.connect(func(a: String, s: String) -> void: trips.append([a, s]))
	h.set("travel_enabled", false)
	h.interact(null)
	assert_eq(trips.size(), 0, "no trip while bolted")
	GameState.set_flag("ta_hatch_open", true)
	assert_true(bool(h.get("is_open")), "both ends agree at once")
	assert_eq(String(h.get_interaction(null)["text"]), "Climb down the hatch")
	h.interact(null)
	assert_eq(trips, [["tobin_annex", "annex_hatch_below"]], "the shortcut works both ways once open")


func test_side_doors() -> void:
	var d: Node3D = DoorScript.new()
	d.setup({"variant": "surface", "target_area": "tobin_annex", "target_spawn": "annex_entry", "requires_flag": "mine_opened"})
	_holder.add_child(d)
	assert_true(d.is_in_group("area_exit"))
	var info: Dictionary = d.get_interaction(null)
	assert_false(bool(info["enabled"]), "jammed until the mine mouth is cleared")
	assert_true(String(info.get("reason", "")).contains("rockfall"))
	var trips: Array = []
	d.travelled.connect(func(a: String, s: String) -> void: trips.append([a, s]))
	d.set("travel_enabled", false)
	await d.interact(null)
	assert_eq(trips.size(), 0, "no trip while jammed")
	GameState.set_flag("mine_opened", true)
	assert_eq(String(d.get_interaction(null)["text"]), "Go through Tobin's side door")
	assert_false(bool(GameState.get_flag("mine_comfort_seen")))
	# The no-UI path (a gameplay UI left behind by an earlier suite would open the real comfort screen and wait).
	var saved_ui: Node = Game.ui
	Game.ui = null
	await d.interact(null)
	Game.ui = saved_ui
	assert_eq(trips, [["tobin_annex", "annex_entry"]], "leads to annex_entry")
	assert_true(bool(GameState.get_flag("mine_comfort_seen")), "the comfort screen counts as seen (fails open without a UI)")
	var inside: Node3D = DoorScript.new()
	inside.setup({"variant": "interior"})
	_holder.add_child(inside)
	assert_eq(String(inside.get("target_area")), "surface")
	assert_eq(String(inside.get("target_spawn")), "annex_door")
	assert_true(bool(inside.get_interaction(null)["enabled"]), "the way out is always open")
	assert_eq(String(inside.get_interaction(null)["text"]), "Back out to the mine mouth")


# --- the optional goals ----------------------------------------------------------------------------------------

func test_objective_flags_complete_opt_tobins_shift() -> void:
	GameState.set_flag("mine_opened", true)
	area = await _make_area()
	var olog: RefCounted = GameState.optional_goals
	var g: Dictionary = olog.goal("opt_tobins_shift")
	assert_false(g.is_empty(), "the goal exists")
	var want: Array = []
	for o in g.get("objectives", []):
		want.append(String(o.get("flag", "")))
	assert_eq(want, ["c1x_annex_entered", "c1x_drudge_defeated", "c1x_tobin_shift", "ta_hatch_open"], "the goal reads exactly these flags")
	var p := Node3D.new()
	_holder.add_child(p)
	area.on_player_spawned(p)
	if area.drudge_spawner != null:
		area.drudge_spawner.call("_on_wave_cleared")
	else:
		area.on_zone("ta_lockers")
	area.read_note(null)
	olog.evaluate()
	assert_false(olog.is_done("opt_tobins_shift"), "not before the hatch")
	area.hatch.call("open_hatch")
	olog.evaluate()
	assert_true(olog.is_done("opt_tobins_shift"), "all four objectives done")
	assert_true(GameState.has_reward("rw_opt_tobins_shift"), "the optional log pays its own goal reward")
	assert_eq(GameState.count_item("miner_lamp"), 1, "the goal never pays a second lamp for the same activity")
	# The Miner Who Came Back: the annex half is the letter.
	GameState.set_flag("chapter_one_complete", true)
	GameState.set_flag("ch2_accepted", true)
	GameState.set_flag("ch2_hask_note_found", true)
	olog.evaluate()
	assert_false(olog.is_done("opt_miner_came_back"), "Tobin's letter still missing")
	area.read_letter(null)
	olog.evaluate()
	assert_true(olog.is_done("opt_miner_came_back"), "letter + Hask's note")


# --- a real round trip through Game ----------------------------------------------------------------------------

var _runner: Node = null


func _playing() -> bool:
	return Game.mode == "playing" and not Game._transitioning and Game.player != null and is_instance_valid(Game.player)


func _arrived(area_name: String) -> bool:
	var ok := false
	for i in 1500:
		if _playing() and Game.area_id == area_name:
			ok = true
			break
		await get_tree().process_frame
	await wait_seconds(0.8)
	await wait_frames(4)
	return ok


func _near(spawn: String, tol: float = 1.2) -> bool:
	if Game.area == null or Game.player == null:
		return false
	var xf: Transform3D = Game.area.get_spawn(spawn)
	var p: Vector3 = Game.player.global_position
	return Vector2(p.x - xf.origin.x, p.z - xf.origin.z).length() < tol


func _find(group: String, script_path: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		var s: Variant = (n as Node).get_script()
		if s is Script and (s as Script).resource_path == script_path and Game.area != null and (Game.area as Node).is_ancestor_of(n):
			return n
	return null


func test_zz_real_round_trip() -> void:
	_runner = get_tree().current_scene
	var ph := Node.new()
	ph.name = "AnnexPlaceholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	for f in ["mine_opened", "mine_comfort_seen", "entered_below"]:
		GameState.set_flag(f, true)
	GameState.active = true
	Game.load_area("tobin_annex", "annex_entry", false)
	assert_true(await _arrived("tobin_annex"), "arrived in the annex")
	assert_true(_near("annex_entry"), "at annex_entry")
	assert_true(bool(GameState.get_flag("c1x_annex_entered")), "arrival flag")
	# Unbolt the hatch and climb up: the surface, beside the mine mouth.
	var h: Node = _find("area_exit", "res://src/world/annex/annex_hatch.gd")
	assert_not_null(h, "the hatch")
	if h != null:
		h.call("open_hatch")
		h.call("interact", null)
		assert_true(await _arrived("surface"), "climbed out onto the surface")
		assert_true(_near("annex_hatch"), "at annex_hatch")
		assert_eq(String(GameState.player.get("respawn_area", "")), "surface", "the surface return point stays home")
		# Through Tobin's side door, back into the annex.
		var d: Node = _find("area_exit", "res://src/world/annex/annex_door.gd")
		assert_not_null(d, "the side door on the mine cliff")
		if d != null:
			assert_true(bool(d.get_interaction(null)["enabled"]), "open once the mine mouth is cleared")
			d.call("interact", null)
			assert_true(await _arrived("tobin_annex"), "back in the annex")
			assert_true(_near("annex_entry"), "at annex_entry again")
			assert_eq(String(GameState.player.get("respawn_area", "")), "tobin_annex")
			assert_eq(String(GameState.player.get("respawn_spawn", "")), "annex_entry", "default return point")
	# Tidy up like test_flow_ch2_roundtrip.
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game.area = null
	Game.player = null
	_saved_player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game._bosses.clear()
	var cs := get_tree().current_scene
	if cs != null and cs != _runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "AnnexPlaceholder" or n.name == "Surface" or n.name == "TobinAnnex":
			n.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)
