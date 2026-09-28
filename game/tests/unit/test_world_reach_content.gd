extends "res://tests/test_case.gd"
## Hallowmere Reach content logic on a built region: the festival map board (ch2_read_festival_map), the
## festival mirror (wardrobe panel), the lamp-linking pedestal (ch2_lamps_linked, road lights, ceremony),
## the Sunken Bellhouse states (sealed / revealed / service gate with and without the Foreman's Key, never
## consumed, never granted), the refuge hatch, the preparations note and workshop ledger, the practice seam,
## the lore file, high-visibility markers, save/load of the region's flags, and the district loader with
## missing and fake districts.

const ReachWorld := preload("res://src/world/areas_ch2/hallowmere_reach_world.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const LoreData := preload("res://data/lore_ch2_reach.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Bellhouse := preload("res://src/world/reach/bellhouse.gd")
const Descent := preload("res://src/world/reach/bellhouse_descent.gd")
const Conservatory := preload("res://src/world/reach/conservatory.gd")
const Vegetation := preload("res://src/world/reach/reach_vegetation.gd")

const LAMP_FLAGS := ["ch2_garden_lamp_lit", "ch2_quarry_lamp_lit", "ch2_manor_lamp_lit"]
const REGION_FLAGS := ["ch2_read_festival_map", "ch2_lamps_linked", "ch2_service_gate_open", "ch2_read_preparations",
	"ch2_refuge_shortcut", "foreman_key_taken", "lower_gate_open", "ch2_orchard_restored"]

static var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = ReachWorld.new()
		add_child(_w)
		await wait_physics(2)
	return _w


func _clear_flags() -> void:
	for f in LAMP_FLAGS + REGION_FLAGS:
		GameState.flags.erase(f)


class UiStub:
	extends Node
	var opened: Array = []

	func open(panel: String, args: Dictionary = {}) -> void:
		opened.append([panel, args])


func test_festival_board_reads_the_map() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	var board: Node = w.commons.board
	assert_eq(String(board.get_interaction(null)["text"]), "Read the festival map")
	board.interact(null)
	assert_true(bool(GameState.get_flag("ch2_read_festival_map")), "reading sets ch2_read_festival_map")
	assert_true(GameState.lore.has("lore_ch2_festival_board"), "the board's words are in the journal")
	assert_eq(String(board.get_interaction(null)["text"]), "Read the festival board", "later readings keep working")
	board.interact(null)
	assert_true(bool(GameState.get_flag("ch2_read_festival_map")))
	assert_eq(Reach.MAP_ROUTES["flag"], "ch2_read_festival_map", "the map reveal is keyed to the same flag")
	for lm in ["hr_orchard", "hr_quarry", "hr_manor_grounds"]:
		for road in Reach.MAP_ROUTES["branches"][lm]:
			assert_true(Reach.PATHS.has(road), "branch road %s exists" % road)


func test_festival_mirror_opens_the_wardrobe() -> void:
	var w: Node3D = await _world()
	var prev: Node = Game.ui
	var stub := UiStub.new()
	add_child(stub)
	Game.ui = stub
	var mirror: Node = w.commons.mirror
	assert_eq(String(mirror.get_interaction(null)["text"]), "Change your look")
	mirror.interact(null)
	Game.ui = prev
	assert_eq(stub.opened.size(), 1, "one panel opened")
	if stub.opened.size() > 0:
		assert_eq(String(stub.opened[0][0]), "wardrobe", "the wardrobe panel")
	stub.queue_free()


func test_pedestal_links_only_with_three_lamps() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	w.road_lights.set_lit_instant(false)
	w.bellhouse.apply_state()
	var p: Node = w.conservatory.pedestal
	assert_eq(String(p.get_interaction(null)["text"]), "Inspect the linking pedestal (0/3 lamps)")
	assert_false(p.link_lanterns(false), "nothing to link yet")
	p.interact(null)
	assert_false(bool(GameState.get_flag("ch2_lamps_linked")), "inspecting never links")
	GameState.set_flag("ch2_garden_lamp_lit", true)
	GameState.set_flag("ch2_manor_lamp_lit", true)
	assert_eq(String(p.get_interaction(null)["text"]), "Inspect the linking pedestal (2/3 lamps)")
	assert_eq(p.lamps_lit(), ["garden", "manor"], "each lamp is shown independently, in any order")
	assert_false(p.link_lanterns(false), "two lamps are not enough")
	GameState.set_flag("ch2_quarry_lamp_lit", true)
	assert_eq(String(p.get_interaction(null)["text"]), "Link the lanterns")
	var inv_before: Array = GameState.inventory.to_array()
	var keys_before: Dictionary = GameState.key_items.duplicate()
	assert_true(p.link_lanterns(false), "all three lamps: linked")
	assert_true(bool(GameState.get_flag("ch2_lamps_linked")), "flag ch2_lamps_linked")
	assert_eq(GameState.inventory.to_array(), inv_before, "nothing consumed or granted (backpack)")
	assert_eq(GameState.key_items, keys_before, "nothing consumed or granted (key pouch)")
	assert_eq(int(w.road_lights.lit_count()), (w.road_lights.posts as Array).size(), "every road light is lit")
	assert_true((w.road_lights.posts as Array).size() >= 16, "lights line the roads (%d)" % (w.road_lights.posts as Array).size())
	assert_true(bool(w.bellhouse.revealed), "the Bellhouse stair is revealed")
	assert_false(p.link_lanterns(false), "linking happens once")
	assert_eq(String(p.get_interaction(null)["text"]), "Look at the linked lanterns")


func test_link_ceremony_commits_first_then_lights_the_roads() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	w.road_lights.set_lit_instant(false)
	w.bellhouse.apply_state()
	for f in LAMP_FLAGS:
		GameState.set_flag(f, true)
	var p: Node = w.conservatory.pedestal
	var t0 := Time.get_ticks_msec()
	assert_true(p.link_lanterns(true), "ceremony starts")
	assert_true(bool(GameState.get_flag("ch2_lamps_linked")), "the flag is committed before any animation")
	assert_eq(p.get_interaction(null), {}, "no prompt during the ceremony")
	await wait_frames(20)
	var mid := int(w.road_lights.lit_count())
	assert_true(mid < (w.road_lights.posts as Array).size(), "the lights come on along the roads, not all at once (%d)" % mid)
	for i in 200:
		if not bool(w.road_lights.animating):
			break
		await wait_seconds(0.1)
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	assert_false(bool(w.road_lights.animating), "the ceremony ends")
	assert_true(secs < 14.0, "short and readable (%.1f s)" % secs)
	assert_eq(int(w.road_lights.lit_count()), (w.road_lights.posts as Array).size(), "every road light lit afterwards")
	await wait_seconds(2.2)
	assert_eq(w.road_lights.find_children("LinkMote*", "", true, false).size(), 0, "the motes are cleaned up")
	assert_false(String(p.get_interaction(null).get("text", "")) == "", "the pedestal answers again")


func test_bellhouse_sealed_revealed_and_the_service_gate() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	GameState.key_items.erase("foreman_key")
	w.bellhouse.apply_state()
	var bh: Node = w.bellhouse
	var descent: Node = w.exits["bellhouse_stair"]
	var gate: Node3D = bh.gate
	assert_true(descent == bh.descent, "exits.bellhouse_stair is the stair's way down")
	# Sealed.
	var it: Dictionary = descent.get_interaction(null)
	assert_false(bool(it["enabled"]), "sealed before the lanterns are linked")
	assert_eq(String(it["reason"]), Descent.SEALED_TEXT)
	assert_eq(int(bh._lid_body.collision_layer), 1, "the slabs are solid")
	assert_false(gate.visible, "the gate is hidden under the slabs")
	assert_false(gate.is_in_group("interactable"), "and not interactable")
	assert_true(bool(bh.seal.is_active()), "the sealed stair explains itself")
	assert_false(bool(bh.seal.get_interaction(null)["enabled"]))
	# Revealed, no key (the Foreman's Key is never granted here).
	GameState.set_flag("ch2_lamps_linked", true)
	assert_true(bool(bh.revealed), "revealed as soon as the flag is set")
	assert_eq(int(bh._lid_body.collision_layer), 0, "the slabs are gone")
	assert_true(gate.visible and gate.is_in_group("interactable"), "the service gate can be tried")
	assert_false(bool(bh.seal.is_active()), "no sealed prompt any more")
	it = descent.get_interaction(null)
	assert_false(bool(it["enabled"]), "no key: can't go down")
	assert_eq(String(it["reason"]), Bellhouse.LOCKED_TEXT, "the locked text points to the Foreman's Key")
	gate.interact(null)
	descent.interact(null)
	assert_false(bool(GameState.get_flag("ch2_service_gate_open")), "a locked gate stays shut")
	assert_eq(GameState.count_item("foreman_key"), 0, "the key is never granted")
	# An inconsistent old save (the key was taken in Chapter One but is missing): a gentle message.
	GameState.set_flag("foreman_key_taken", true)
	bh.apply_state()
	assert_eq(String(bh.locked_text()), Bellhouse.LOST_KEY_TEXT, "gentle message for a lost key")
	assert_eq(String(gate.get("locked_text")), Bellhouse.LOST_KEY_TEXT, "the gate says it too")
	assert_eq(GameState.count_item("foreman_key"), 0, "still not granted")
	# With the key: unlock, never consumed.
	GameState.give_item("foreman_key", 1)
	assert_eq(String(bh.locked_text()), Bellhouse.LOCKED_TEXT)
	assert_eq(String(descent.get_interaction(null)["text"]), "Unlock the service gate and go down")
	gate.interact(null)
	assert_true(bool(GameState.get_flag("ch2_service_gate_open")), "the key opens the service gate (flag)")
	assert_eq(GameState.count_item("foreman_key"), 1, "the key stays in the pouch")
	await wait_seconds(0.2)
	it = descent.get_interaction(null)
	assert_true(bool(it["enabled"]), "the way down is open")
	assert_eq(String(it["text"]), "Go down to the service landing")
	assert_eq(String(descent.get("target_area")), "hushed_works")
	assert_eq(String(descent.get("target_spawn")), "service_landing")
	var ib: StaticBody3D = descent.get_node("Interact")
	assert_eq(int(ib.collision_layer), 16, "reachable once the gate is open")
	# Loading a save with the gate open: open at once.
	var gate2: Node3D = load("res://src/world/below/lower_gate.gd").new()
	gate2.setup({"flag": "ch2_service_gate_open", "key": "foreman_key"})
	add_child(gate2)
	assert_true(bool(gate2.get("is_open")), "a reloaded gate is open")
	gate2.queue_free()


func test_descent_unlocks_with_the_key_in_one_go() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	GameState.key_items.erase("foreman_key")
	GameState.give_item("foreman_key", 1)
	GameState.set_flag("ch2_lamps_linked", true)
	var descent: Node = w.exits["bellhouse_stair"]
	var mode := Game.mode
	Game.mode = "cutscene"          # never actually travel in this unit test
	descent.interact(null)
	Game.mode = mode
	assert_true(bool(GameState.get_flag("ch2_service_gate_open")), "the key unlocked the gate on the way down")
	assert_eq(GameState.count_item("foreman_key"), 1, "and stayed in the pouch")


## The gate reads its flag only when built: a flag recorded elsewhere while the region is loaded (a repair or
## debug hook) opens the leaves too, and the gate's own unlock still swings open (never snapped shut/open).
func test_service_gate_follows_its_flag_without_losing_the_swing() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	GameState.key_items.erase("foreman_key")
	GameState.set_flag("ch2_lamps_linked", true)
	var bh: Node3D = Bellhouse.new()
	bh.terrain = w.terrain
	add_child(bh)
	var gate: Node3D = bh.gate
	assert_false(bool(gate.get("is_open")), "a fresh gate starts shut")
	GameState.set_flag("ch2_service_gate_open", true)
	await wait_frames(2)
	assert_true(bool(gate.get("is_open")), "the leaves open when the flag is recorded elsewhere")
	assert_false(gate.is_in_group("interactable"), "an open gate is no longer a prompt")
	assert_eq(int((bh.descent.get_node("Interact") as StaticBody3D).collision_layer), 16, "the way down answers")
	bh.queue_free()
	await wait_frames(2)
	GameState.flags.erase("ch2_service_gate_open")
	GameState.give_item("foreman_key", 1)
	var bh2: Node3D = Bellhouse.new()
	bh2.terrain = w.terrain
	add_child(bh2)
	var gate2: Node3D = bh2.gate
	gate2.interact(null)
	await wait_frames(3)
	assert_true(bool(GameState.get_flag("ch2_service_gate_open")), "the key opened it")
	assert_true(bool(gate2.get("animating")) and not bool(gate2.get("is_open")), "and the leaves still swing open (not snapped)")
	assert_eq(GameState.count_item("foreman_key"), 1, "the key stays in the pouch")
	bh2.queue_free()
	await wait_frames(2)
	_clear_flags()
	w.bellhouse.apply_state()


func test_refuge_hatch() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	var h: Node = w.exits["refuge_hatch"]
	var it: Dictionary = h.get_interaction(null)
	assert_false(bool(it["enabled"]), "bolted from below until the refuge shortcut opens")
	GameState.set_flag("ch2_refuge_shortcut", true)
	it = h.get_interaction(null)
	assert_true(bool(it["enabled"]), "open after ch2_refuge_shortcut")
	assert_eq(String(it["text"]), "Climb down to the refuge")
	assert_eq(String(h.get("target_area")), "hushed_works")
	assert_eq(String(h.get("target_spawn")), "refuge")
	var sp: Vector3 = (w.spawns["refuge_exit"] as Transform3D).origin
	assert_true(Vector2(sp.x, sp.z).distance_to(Vector2(h.global_position.x, h.global_position.z)) < 6.0, "refuge_exit is beside the hatch")


func test_preparations_note_and_workshop_ledger() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	var c: Node = w.conservatory
	assert_eq(String(c.lectern.get_interaction(null)["text"]), "Read the preparation notes")
	c.lectern.interact(null)
	assert_true(bool(GameState.get_flag("ch2_read_preparations")), "reading sets ch2_read_preparations")
	assert_true(GameState.lore.has("lore_ch2_preparations"))
	var prep := String(LoreData.LORE["lore_ch2_preparations"]["text"])
	assert_false(prep.contains("must"), "the note recommends, never demands")
	var blank := Conservatory.ledger_text()
	assert_true(blank.contains("still blank"), "unrestored lamps leave blank pages")
	GameState.set_flag("ch2_orchard_restored", true)
	var t := Conservatory.ledger_text()
	assert_true(t.contains("The garden lamp taught"), "a restored lamp's recipes are listed: %s" % t)
	c.plaque.interact(null)
	assert_true(GameState.lore.has("lore_ch2_conservatory"), "the Ward-Keeper's words")
	c.true_light.interact(null)
	assert_true(GameState.lore.has("lore_ch2_true_light"), "the true-light plaque")


func test_practice_seam_is_a_renewable_iron_vein() -> void:
	var w: Node3D = await _world()
	var seam: Node = w.conservatory.practice_seam
	GameState.depleted.erase(Reach.PRACTICE_SEAM_ID)
	assert_eq(String(seam.get("node_id")), "hr_practice_seam")
	assert_eq(String(seam.get("tool")), "pickaxe")
	var drops: Array = seam.get("drops")
	assert_eq(String(drops[0]["item"]), "iron_ore", "iron ore")
	assert_true(float(seam.get("respawn_minutes")) > 0.0, "renewable")
	assert_eq(String(seam.get("kind")), "iron_vein", "the catalogue's iron vein kind (same numbers as the quarry's veins)")
	assert_true(int(seam.get("required_tier")) <= 1, "a stone pickaxe is enough (never demands an upgrade)")
	var kinds: Array = []
	var on_harvest := func(k: String, _item: String, _n: int, _p: Vector3) -> void: kinds.append(k)
	Events.harvested.connect(on_harvest)
	var before := GameState.count_item("iron_ore")
	for i in int(seam.get("hits")):
		seam.harvest_hit(null, "stone_pickaxe")
		await wait_seconds(0.02)
	Events.harvested.disconnect(on_harvest)
	assert_true(GameState.count_item("iron_ore") >= before + 2, "a stone pickaxe mines it")
	assert_true(kinds.has("iron_vein") and not kinds.has("ore"), "the harvest reports iron, not a copper vein (%s)" % str(kinds))
	assert_true(GameState.is_depleted("hr_practice_seam"), "depletion is saved under its stable id")
	GameState.depleted.erase(Reach.PRACTICE_SEAM_ID)


func test_high_visibility_markers_follow_the_setting() -> void:
	var w: Node3D = await _world()
	var prev: Variant = Settings.get_value("high_visibility_cues")
	Settings.set_value("high_visibility_cues", true)
	await wait_frames(2)
	var board: Node = w.commons.board
	var m: Node3D = board.get_node_or_null("HiVisMarker")
	assert_not_null(m, "a bold marker over the festival board")
	if m != null:
		assert_true(m.visible, "visible with high-visibility cues on")
	# Wayfinding markers: unlit arches and the waygate home; the Bellhouse stair only once it is revealed.
	_clear_flags()
	for id in Reach.ARCH_ORDER:
		GameState.flags.erase(Reach.arch_flag(String(id)))
	w.markers.refresh()
	var mk: Node = w.markers
	for id in Reach.ARCH_ORDER:
		var am: Node3D = mk.marker("arch_" + String(id))
		assert_not_null(am, "a marker for the %s arch" % id)
		if am != null:
			assert_true(am.visible, "the unlit %s arch is marked" % id)
	assert_true((mk.marker("waygate") as Node3D).visible, "the way home is marked")
	assert_false((mk.marker("bellhouse_stair") as Node3D).visible, "no marker over the sealed stair")
	assert_false((mk.marker("refuge_hatch") as Node3D).visible, "no marker over the bolted hatch")
	assert_true(mk.is_processing(), "markers bob while shown")
	GameState.set_flag(Reach.arch_flag("commons"), true)
	GameState.set_flag("ch2_lamps_linked", true)
	assert_false((mk.marker("arch_commons") as Node3D).visible, "a lit arch needs no marker")
	assert_true((mk.marker("bellhouse_stair") as Node3D).visible, "the revealed stair is marked")
	var sm: Node3D = mk.marker("bellhouse_stair")
	var stair_top := Vector2(float(Reach.BELLHOUSE["stair_x"]), float(Reach.BELLHOUSE["ramp_top_z"]))
	assert_true(Vector2(sm.global_position.x, sm.global_position.z).distance_to(stair_top) < 0.5, "the stair marker stands over the stair top")
	assert_true(sm.global_position.y > w.height_at(stair_top.x, stair_top.y + 1.5) + 1.8, "above head height")
	assert_true((mk.marker("service_gate") as Node3D).visible, "the shut service gate at the stair bottom is marked")
	assert_false((mk.marker("bellhouse_descent") as Node3D).visible, "the way down waits for the gate")
	GameState.set_flag("ch2_service_gate_open", true)
	assert_false((mk.marker("service_gate") as Node3D).visible, "an open gate needs no marker")
	var dm: Node3D = mk.marker("bellhouse_descent")
	assert_true(dm.visible, "the way down is marked once the gate is open")
	var pass_top := float(w.bellhouse.bottom) + 2.9
	assert_true(dm.global_position.y + 0.96 * 1.0 + 0.13 < pass_top, "the way-down marker fits under the passage ceiling")
	Settings.set_value("high_visibility_cues", false)
	await wait_frames(2)
	if m != null:
		assert_false(m.visible, "hidden again when the setting is off")
	for e in mk.entries:
		assert_false((e["marker"] as Node3D).visible, "%s hidden when the setting is off" % e["id"])
	assert_false(mk.is_processing(), "no processing while every marker is hidden")
	Settings.set_value("high_visibility_cues", prev)
	GameState.flags.erase(Reach.arch_flag("commons"))
	GameState.flags.erase("ch2_lamps_linked")
	GameState.flags.erase("ch2_service_gate_open")
	w.bellhouse.apply_state()
	w.conservatory.pedestal.refresh()
	w.road_lights.set_lit_instant(false)


func test_lore_file_and_mp17_lines() -> void:
	LoreDB.reload()
	for id in LoreData.ORDER:
		assert_true(LoreData.LORE.has(id), "%s has text" % id)
		assert_true(LoreDB.has_lore(String(id)), "%s is found by LoreDB" % id)
		assert_true(String(LoreDB.get_lore(String(id))["text"]).length() > 20, "%s is written" % id)
	assert_eq(String(LoreData.LORE["lore_ch2_festival_board"]["text"]), "Lanternwake: a lamp at every gate, a sweet upon every table, a place for every traveler.")
	assert_eq(String(LoreData.LORE["lore_ch2_conservatory"]["text"]), "We did not build the lanterns to drive out every dark. We built them so a traveler could always find a kindness.")
	assert_eq(String(LoreData.LORE["lore_ch2_garden_note"]["text"]), "Plant the round ones for supper. Carve the crooked ones for company. Do not feed the one that feeds itself.")
	assert_eq(String(LoreData.LORE["lore_ch2_manor_invitation"]["text"]), "To the bearer of a proper light: you are expected. The house has practiced being welcoming.")
	for id in ["lore_ch2_groundskeeper_1", "lore_ch2_groundskeeper_2", "lore_ch2_quarry_log", "lore_ch2_bellhouse", "lore_ch2_preparations", "lore_ch2_true_light"]:
		assert_true(LoreData.ORDER.has(id), "%s listed" % id)


func test_road_lights_also_follow_the_committed_safe_routes() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	GameState.flags.erase("ch2_safe_light_routes")
	w.road_lights.set_lit_instant(false)
	assert_true((w.road_lights.posts as Array).size() >= 12, "lamp posts line the four roads (%d)" % (w.road_lights.posts as Array).size())
	assert_eq(int(w.road_lights.lit_count()), 0, "dark before linking")
	GameState.set_flag("ch2_safe_light_routes", true)     # the quest layer's step reward flag
	await wait_frames(2)
	assert_eq(int(w.road_lights.lit_count()), (w.road_lights.posts as Array).size(), "the committed safe routes keep every post lit")
	GameState.flags.erase("ch2_safe_light_routes")
	w.road_lights.set_lit_instant(false)


func test_story_dressing_is_built_once_behind_the_fade() -> void:
	var w: Node3D = await _world()
	var path := String(w.story_dressing_path)
	if not ResourceLoader.exists(path):
		print("    (story module absent: the region builds without its dressing)")
		assert_null(w.story_dressing)
		return
	assert_not_null(w.story_dressing, "the region builds the story dressing itself")
	var s: Script = load(path)
	var node_name := String(s.get_script_constant_map().get("NODE_NAME", ""))
	assert_eq(String(w.story_dressing.name), node_name)
	assert_true(w.story_dressing.get_parent() == w, "a child of the region")
	var again: Variant = s.call("build", w)
	assert_true(again == w.story_dressing, "building again returns the same root (the tracker never adds a second)")
	var count := 0
	for c in w.get_children():
		if String(c.name) == node_name:
			count += 1
	assert_eq(count, 1, "exactly one dressing root")
	# The first build of a run also compiles the story module's scripts (~130-210 ms measured when this suite runs
	# alone); the dressing itself is a few ms warm. Bound the cold figure, not the compiler.
	var dress_ms := float(w.build_times.get("story_dressing", 999.0))
	print("    story dressing: %.1f ms (incl. first-time script compilation when cold)" % dress_ms)
	assert_true(dress_ms < 400.0, "the dressing stays cheap behind the fade (%.1f ms)" % dress_ms)


func test_y_region_state_survives_save_and_load() -> void:
	var w: Node3D = await _world()
	_clear_flags()
	for f in LAMP_FLAGS:
		GameState.set_flag(f, true)
	w.conservatory.pedestal.link_lanterns(false)
	GameState.set_flag("ch2_service_gate_open", true)     # what unlocking the service gate records
	w.commons.read_festival_map()
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_false(bool(GameState.get_flag("ch2_lamps_linked")), "cleared before loading")
	assert_true(SaveSystem.load_game(), "loaded")
	for f in ["ch2_lamps_linked", "ch2_service_gate_open", "ch2_read_festival_map"]:
		assert_true(bool(GameState.get_flag(f)), "%s survives save/load" % f)
	# A freshly built region shows the loaded state at once.
	_w.queue_free()
	_w = null
	await wait_frames(4)
	var w2: Node3D = ReachWorld.new()       # built on the loaded state (no fresh_state here)
	add_child(w2)
	_w = w2
	await wait_physics(2)
	assert_true(bool(w2.bellhouse.revealed), "the stair is open on load")
	assert_eq(int(w2.bellhouse._lid_body.collision_layer), 0, "no slabs on load")
	assert_true(bool(w2.bellhouse.gate.get("is_open")), "the service gate is open on load")
	assert_eq(int(w2.road_lights.lit_count()), (w2.road_lights.posts as Array).size(), "road lights lit on load")
	assert_eq(String(w2.conservatory.pedestal.get_interaction(null)["text"]), "Look at the linked lanterns")
	assert_eq(String(w2.commons.board.get_interaction(null)["text"]), "Read the festival board")


func test_z_district_loader_with_missing_and_fake_districts() -> void:
	if _w != null and is_instance_valid(_w):
		_w.queue_free()
		_w = null
		await wait_frames(4)
	fresh_state()
	var dir := SaveSystem.save_dir.path_join("reach_district_fixture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join("fake_district.gd")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends RefCounted\n\nstatic func footprints() -> Array:\n\treturn [[Vector2(-44, -8), 7.0]]\n\n" +
		"static func shape_terrain(terrain) -> void:\n\tterrain.raise(Vector2(-44, -8), 6.0, 2.0)\n\tterrain.raise(Vector2(-10, -8), 6.0, 5.0)\n\n" +
		"static func build(area: Node3D) -> void:\n\tarea.set_meta(\"fake_district_built\", true)\n" +
		"\tarea.add_resource({\"node_id\": \"hr_fakerock_0\", \"kind\": \"rock\"}, area.ground(Vector2(-40, -2)))\n")
	f.close()
	var probe: RefCounted = load("res://src/world/reach/reach_terrain.gd").new()
	probe.generate()
	var h_out := float(probe.height_at(-10.0, -8.0))
	var w: Node3D = ReachWorld.new()
	w.district_entries = [{"id": "missing", "path": "res://src/world/reach/districts/does_not_exist.gd", "landmark": "hr_orchard"},
		{"id": "fake", "path": path, "landmark": "hr_pools"}]
	w.story_dressing_path = "res://src/world/story_ch2/does_not_exist.gd"
	add_child(w)
	await wait_physics(2)
	assert_eq(w.districts.size(), 1, "the missing district is skipped, the fake one loads")
	assert_eq(w.districts_built, ["fake"], "build(area) ran after the base region")
	assert_true(bool(w.get_meta("fake_district_built", false)), "the district's build saw the area")
	assert_true(w.district_nodes.has("hr_fakerock_0"), "districts add resource nodes through the area")
	assert_almost(float(w.height_at(-10.0, -8.0)), h_out, 0.001, "shaping outside the district's circle is discarded")
	assert_true(float(w.height_at(-44.0, -8.0)) > float(probe.height_at(-44.0, -8.0)) + 1.5, "shaping inside its circle is kept")
	for d in w.vegetation.plan_data["trees"] + w.vegetation.plan_data["rocks"] + w.vegetation.plan_data["sticks"] + w.vegetation.plan_data["stones"] + w.vegetation.plan_data["fibers"]:
		var p: Vector3 = d["pos"]
		assert_true(Vector2(p.x, p.z).distance_to(Vector2(-44, -8)) > 7.0, "%s keeps off the district footprint" % d["id"])
	# The base region is complete without the missing district.
	for id in Reach.SPAWNS:
		assert_true((w.spawns as Dictionary).has(id), "spawn %s still registered" % id)
	assert_null(w.story_dressing, "a missing story dressing script is skipped")
	assert_true((w.exits as Dictionary).has("manor_door"), "a manor door exists without the manor district")
	assert_eq(String(w.exits["manor_door"].get("target_area")), "moonveil_manor")
	w.queue_free()
	await wait_frames(4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
