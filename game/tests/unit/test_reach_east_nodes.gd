extends "res://tests/test_case.gd"
## Ashbell Quarry set pieces and harvest nodes (src/world/reach/east/*): iron veins mine with ANY pickaxe (stone
## slower than copper), Moon Crystal seams refuse pickaxes below Ironwood (nothing taken, nothing given) and
## give moon crystal with one, every node is renewable and persists its depletion; the mineral winch repair is
## transactional (partial materials -> nothing taken) and persistent (ch2_winch_repaired lowers the gangway on
## every later load); the quarry lamp is found on approach and lights only after the Warden AND the winch, sets
## ch2_quarry_lamp_lit exactly once, never grants a reward itself, and the Chapter Two quest layer then pays
## rw_ch2_quarry once; the quarry log records its lore once; state survives a real save/load.

const Q := preload("res://data/reach_east.gd")
const Shape := preload("res://src/world/reach/east/quarry_shape.gd")
const Builder := preload("res://src/world/reach/east/quarry_builder.gd")
const WinchScript := preload("res://src/world/reach/east/quarry_winch.gd")
const LampScript := preload("res://src/world/reach/east/quarry_lamp.gd")
const NoteScript := preload("res://src/world/reach/east/quarry_note.gd")

var _holder: Node3D


func before_each() -> void:
	fresh_state()
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(2)


func _entry(table: String, index: int = 0) -> Dictionary:
	for e in Builder.node_plan():
		if String(e["table"]) == table:
			if index == 0:
				return e
			index -= 1
	return {}


func _node(table: String, index: int = 0) -> Node3D:
	var n: Node3D = Builder.make_node(_entry(table, index))
	_holder.add_child(n)
	return n


func _hits_to_deplete(n: Node3D, tool_id: String, max_hits: int = 20) -> int:
	for i in max_hits:
		n.harvest_hit(null, tool_id)
		if bool(n.depleted):
			return i + 1
	return -1


func test_iron_with_any_pickaxe_slower_with_stone() -> void:
	var kinds: Array = []
	var cb := func(kind: String, _item: String, _n: int, _p: Vector3) -> void: kinds.append(kind)
	Events.harvested.connect(cb)
	GameState.give_item("stone_pickaxe", 1)
	var a := _node("iron", 0)
	assert_eq(String(a.get_harvest_info()["tool"]), "pickaxe", "a pickaxe node")
	assert_true(bool(a.get_interaction(null).get("enabled", false)), "the stone pickaxe can mine it")
	var stone_hits := _hits_to_deplete(a, "stone_pickaxe")
	assert_eq(stone_hits, 6, "stone pickaxe: 6 hits")
	assert_true(GameState.count_item("iron_ore") >= 2, "iron ore gathered")
	assert_true(GameState.is_depleted(String(a.node_id)), "depletion persisted by node id")
	assert_true(kinds.has("iron_vein"), "Events.harvested reports the iron_vein kind (%s)" % str(kinds))
	var b := _node("iron", 1)
	GameState.give_item("copper_pickaxe", 1)
	assert_eq(_hits_to_deplete(b, "copper_pickaxe"), 4, "copper pickaxe: faster (4 hits)")
	# renewable: comes back after its respawn time
	GameState.total_minutes += float(ItemDB.node_kind("iron_vein")["respawn_minutes"]) + 1.0
	assert_false(GameState.is_depleted(String(a.node_id)), "the vein grows back")
	Events.harvested.disconnect(cb)


func test_moon_crystal_needs_ironwood() -> void:
	var n := _node("moon_crystal", 0)
	GameState.give_item("stone_pickaxe", 1)
	GameState.give_item("copper_pickaxe", 1)
	var info: Dictionary = n.get_harvest_info()
	assert_eq(int(info["min_tier"]), 3, "min tier from data")
	assert_true(bool(info.get("tier_blocked", false)), "blocked with copper at best")
	assert_true(String(info.get("reason", "")).contains("Ironwood"), "the reason names the pickaxe: " + String(info.get("reason", "")))
	var it: Dictionary = n.get_interaction(null)
	assert_false(bool(it.get("enabled", true)), "greyed prompt")
	for tool_id in ["stone_pickaxe", "copper_pickaxe"]:
		for i in 12:
			n.harvest_hit(null, tool_id)
		assert_false(bool(n.depleted), "%s never mines Moon Crystal" % tool_id)
	assert_eq(GameState.count_item("moon_crystal"), 0, "nothing given")
	GameState.give_item("ironwood_pickaxe", 1)
	assert_false(bool(n.get_harvest_info().get("tier_blocked", false)), "not blocked with Ironwood")
	assert_eq(_hits_to_deplete(n, "ironwood_pickaxe"), 3, "Ironwood: 3 hits (5 at power 2)")
	assert_true(GameState.count_item("moon_crystal") >= 1, "moon crystal gathered")
	var m := _node("moon_crystal", 1)
	GameState.give_item("moonsteel_pickaxe", 1)
	assert_eq(_hits_to_deplete(m, "moonsteel_pickaxe"), 2, "Moonsteel: 2 hits")
	assert_true(float(m.respawn_minutes) > 0.0, "renewable")


func test_other_nodes_use_their_catalogue_numbers() -> void:
	GameState.give_item("stone_pickaxe", 1)
	var c := _node("copper", 0)
	assert_eq(_hits_to_deplete(c, "stone_pickaxe"), int(ItemDB.node_kind("ore")["hits"]), "copper vein hits")
	assert_true(GameState.count_item("copper_ore") >= 2, "copper ore")
	var r := _node("rock", 0)
	assert_eq(_hits_to_deplete(r, "stone_pickaxe"), int(ItemDB.node_kind("rock")["hits"]), "boulder hits")
	var s := _node("stone", 0)
	assert_eq(String(s.tool), "hand", "stones are picked by hand")
	s.interact(null)
	assert_true(bool(s.depleted), "picked up")
	for e in Builder.node_plan():
		var n: Node3D = Builder.make_node(e)
		assert_true(float(n.respawn_minutes) > 0.0, "renewable: " + String(e["id"]))
		assert_eq(String(n.node_id), String(e["id"]), "stable id")
		var v: Variant = n.params.get("visual")
		if v is Node:
			(v as Node).free()
		n.free()


func _winch() -> Node3D:
	var w: Node3D = WinchScript.new()
	var hinge := Vector3(10.0, 5.0, 0.0)
	w.setup({"hinge": hinge, "dir": Vector3(0, 0, 1), "length": 12.0, "width": 2.4, "slope_deg": 19.0, "raised_deg": 12.0,
		"deck_min": Vector2(8.5, -2.5), "deck_max": Vector2(12.0, 0.0), "deck_y": 5.0, "crane": Vector3(12.5, 5.0, -1.5),
		"frame": func(uv: Vector2) -> Vector2: return uv})
	w.position = Vector3(6.0, 0.0, 12.0)
	_holder.add_child(w)
	return w


func _counts() -> Array:
	return [GameState.count_item("wood"), GameState.count_item("stone"), GameState.count_item("iron_ore")]


func test_winch_repair_is_transactional_and_persistent() -> void:
	var w := _winch()
	assert_false(bool(w.is_repaired()), "broken at first")
	assert_false(bool(w.gangway_enabled()), "the gangway is hoisted (not walkable)")
	var info: Dictionary = w.get_interaction(null)
	assert_eq(String(info["text"]), "Repair the mineral winch (6 Wood, 6 Stone, 4 Iron Ore)", "the exact cost is shown")
	assert_false(bool(info["enabled"]), "greyed without materials")
	assert_true(String(info.get("reason", "")).contains("4 more Iron Ore"), "reason lists what is missing: " + String(info.get("reason", "")))
	for c in Q.WINCH_COST:
		assert_true(String(c[0]) in ["wood", "stone", "iron_ore"], "familiar materials only (no bars)")
	GameState.give_item("wood", 6)
	GameState.give_item("stone", 6)
	GameState.give_item("iron_ore", 3)
	assert_false(bool(w.repair()), "one iron ore short")
	assert_eq(_counts(), [6, 6, 3], "nothing was taken")
	assert_false(bool(GameState.get_flag(Q.FLAG_WINCH)), "no flag")
	GameState.give_item("iron_ore", 2)
	assert_true(bool(w.get_interaction(null)["enabled"]), "enabled with everything")
	assert_true(bool(w.repair()), "repaired")
	assert_eq(_counts(), [0, 0, 1], "exactly the cost was taken")
	assert_true(bool(GameState.get_flag(Q.FLAG_WINCH)), "ch2_winch_repaired")
	assert_true(bool(w.gangway_enabled()), "the gangway is walkable")
	assert_false(bool(w.repair()), "a second repair does nothing")
	assert_eq(_counts(), [0, 0, 1], "and takes nothing")
	assert_true(w.get_interaction(null).is_empty(), "no prompt while the gangway is lowering")
	# a later load: a fresh winch starts lowered (no animation) and says so
	var w2 := _winch()
	assert_true(bool(w2.gangway_enabled()), "persistent: lowered on load")
	assert_eq(String(w2.get_interaction(null).get("text", "")), Q.TEXT["winch_look"], "repaired prompt")


func test_winch_lowers_when_the_flag_arrives_from_elsewhere() -> void:
	var w := _winch()
	var cue := w.get_node("Cue") as Node3D
	assert_false(cue.visible, "no bold cue by default")
	Settings.set_value("high_visibility_cues", true)
	assert_true(cue.visible, "high-visibility cue over the broken winch")
	GameState.set_flag(Q.FLAG_WINCH, true)
	assert_true(bool(w.gangway_enabled()), "reacts to the flag (e.g. a loaded save)")
	assert_false(cue.visible, "cue gone once repaired")
	Settings.set_value("high_visibility_cues", false)


func _lamp() -> Node3D:
	var l: Node3D = LampScript.new()
	_holder.add_child(l)
	l.position = Vector3(100.0, 0.0, 100.0)
	return l


func test_lamp_conditions_and_flags() -> void:
	var said: Array = []
	var cb := func(_s: String, text: String, _d: float) -> void: said.append(text)
	Events.say.connect(cb)
	var l := _lamp()
	var granted: Array = []
	var gcb := func(id: String) -> void: granted.append(id)
	Events.reward_granted.connect(gcb)
	assert_eq(String(l.state()), "dormant", "dormant")
	var info: Dictionary = l.get_interaction(null)
	assert_false(bool(info["enabled"]), "can't light yet")
	assert_eq(String(info["reason"]), Q.TEXT["lamp_need_warden"], "first: calm the Warden")
	assert_false(bool(l.light()), "light() refuses")
	assert_false(bool(GameState.get_flag(Q.FLAG_LAMP_LIT)), "not lit")
	# found on approach, once
	assert_false(bool(l.check_approach(Vector3(100.0 + Q.LAMP_FIND_RADIUS + 1.0, 0.0, 100.0))), "too far")
	assert_false(bool(GameState.get_flag(Q.FLAG_LAMP_FOUND)), "not found yet")
	assert_true(bool(l.check_approach(Vector3(100.0 + Q.LAMP_FIND_RADIUS - 1.0, 0.0, 100.0))), "found when close")
	assert_true(bool(GameState.get_flag(Q.FLAG_LAMP_FOUND)), "ch2_found_quarry_lamp")
	assert_false(bool(l.check_approach(Vector3(100.0, 0.0, 100.0))), "found only once")
	assert_true(said.has(Q.TEXT["lamp_found"]), "a line tells her what she found")
	GameState.set_flag(Q.FLAG_WINCH, true)
	assert_eq(String(l.get_interaction(null)["reason"]), Q.TEXT["lamp_need_warden"], "the winch alone is not enough")
	GameState.set_flag(Q.FLAG_WINCH, false)
	GameState.set_flag(Q.FLAG_WARDEN, true)
	assert_eq(String(l.get_interaction(null)["reason"]), Q.TEXT["lamp_need_winch"], "then the winch")
	assert_false(bool(l.light()), "still refused")
	GameState.set_flag(Q.FLAG_WINCH, true)
	assert_eq(String(l.state()), "ready", "ready")
	assert_true(bool(l.get_interaction(null)["enabled"]), "enabled")
	l.interact(null)
	assert_true(bool(GameState.get_flag(Q.FLAG_LAMP_LIT)), "ch2_quarry_lamp_lit")
	assert_eq(String(l.state()), "lit", "lit")
	assert_false(bool(l.light()), "lit once")
	assert_true(said.has(Q.TEXT["lamp_lit"]), "the lamp line")
	assert_eq(granted.size(), 0, "the lamp itself grants nothing (the quest layer pays rw_ch2_quarry)")
	# a rebuilt lamp (later load) shows lit at once
	var l2 := _lamp()
	assert_eq(String(l2.state()), "lit", "persistent")
	Events.say.disconnect(cb)
	Events.reward_granted.disconnect(gcb)


func test_quest_layer_pays_the_quarry_step_once() -> void:
	for f in ["chapter_one_complete", "ward_restored", "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons",
			"ch2_read_festival_map", "ch2_found_orchard_lamp", "ch2_found_manor_lamp"]:
		GameState.set_flag(f, true)
	var l := _lamp()
	l.check_approach(l.position)
	GameState.set_flag(Q.FLAG_WARDEN, true)
	GameState.set_flag(Q.FLAG_WINCH, true)
	assert_true(bool(l.light()), "lit")
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_quarry"), "The Quarry's Pulse completes")
	assert_eq(GameState.count_item("quarry_seal"), 1, "one Quarry Seal")
	assert_true(bool(GameState.get_flag("ch2_quarry_restored")), "Ironwood knowledge flag")
	assert_true(GameState.has_reward("rw_ch2_quarry"), "paid through the ledger")
	l.interact(null)
	assert_false(bool(l.light()), "no second lighting")
	GameState.chapter2.evaluate()
	assert_eq(GameState.count_item("quarry_seal"), 1, "still one seal")


func test_quarry_log_records_lore_once() -> void:
	var said: Array = []
	var cb := func(title: String, _t: String, _d: float) -> void: said.append(title)
	Events.say.connect(cb)
	var n: Node3D = NoteScript.new()
	_holder.add_child(n)
	assert_eq(String(n.get_interaction(null)["text"]), Q.TEXT["log_read"], "prompt")
	assert_true(bool(n.read()), "new lore entry")
	assert_true(GameState.lore.has(Q.LORE_LOG), "lore_ch2_quarry_log discovered")
	assert_false(bool(n.read()), "recorded once")
	assert_eq(said.size(), 2, "readable every time")
	Events.say.disconnect(cb)


func test_state_survives_save_and_load() -> void:
	GameState.give_item("stone_pickaxe", 1)
	var n := _node("iron", 2)
	_hits_to_deplete(n, "stone_pickaxe")
	var id := String(n.node_id)
	GameState.set_flag(Q.FLAG_WINCH, true)
	GameState.set_flag(Q.FLAG_WARDEN, true)
	GameState.set_flag(Q.FLAG_LAMP_FOUND, true)
	GameState.set_flag(Q.FLAG_LAMP_LIT, true)
	GameState.discover_lore(Q.LORE_LOG)
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_false(bool(GameState.get_flag(Q.FLAG_WINCH)), "fresh state")
	assert_true(SaveSystem.load_game(), "loaded")
	for f in [Q.FLAG_WINCH, Q.FLAG_WARDEN, Q.FLAG_LAMP_FOUND, Q.FLAG_LAMP_LIT]:
		assert_true(bool(GameState.get_flag(f)), "flag survives: " + f)
	assert_true(GameState.is_depleted(id), "a mined vein stays mined after loading")
	assert_true(GameState.lore.has(Q.LORE_LOG), "lore survives")
	var w := _winch()
	assert_true(bool(w.gangway_enabled()), "the winch loads repaired")
	var l := _lamp()
	assert_eq(String(l.state()), "lit", "the lamp loads lit")
	var n2 := _node("iron", 2)
	assert_true(bool(n2.depleted), "the vein node shows depleted on load")
