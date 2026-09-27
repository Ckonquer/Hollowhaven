extends "res://tests/test_case.gd"
## Resource nodes (harvest / deplete / persist / respawn), world item pickups (persistence, partial and
## full-backpack pickup), the mine rubble seal and the Ward Stone inscriptions.

const ResourceNode := preload("res://src/world/common/resource_node.gd")
const WorldItem := preload("res://src/world/common/world_item.gd")
const MineEntrance := preload("res://src/world/surface/mine_entrance.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")

var _holder: Node3D


func before_each() -> void:
	fresh_state()
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(1)


func _node(params: Dictionary) -> Node3D:
	var n: Node3D = ResourceNode.new()
	n.setup(params)
	_holder.add_child(n)
	return n


func test_tree_needs_axe_and_hits() -> void:
	var t := _node({"node_id": "test_tree_1", "kind": "tree", "visual": "oak"})
	assert_true(t.is_in_group("harvestable"), "tree is harvestable")
	assert_false(t.is_in_group("interactable"), "trees are not E-interactables")
	assert_eq(t.get_harvest_info()["tool"], "axe")
	# No tool / wrong tool: nothing happens
	t.harvest_hit(null, "")
	t.harvest_hit(null, "stone_pickaxe")
	assert_false(t.depleted, "wrong tool does not fell a tree")
	var before := GameState.count_item("wood")
	GameState.give_item("stone_axe", 1)
	for i in 3:
		t.harvest_hit(null, "stone_axe")
	assert_false(t.depleted, "3 hits are not enough")
	t.harvest_hit(null, "stone_axe")
	assert_true(t.depleted, "4th hit fells the tree")
	var got := GameState.count_item("wood") - before
	assert_true(got >= 3 and got <= 5, "tree gives 3-5 wood (got %d)" % got)
	assert_true(GameState.is_depleted("test_tree_1"), "depletion is persistent")
	assert_eq(GameState.get_counter("trees_felled"), 1, "trees_felled counted")
	assert_false(t.is_in_group("harvestable"), "a stump is not harvestable")
	# More hits on the stump do nothing
	t.harvest_hit(null, "stone_axe")
	assert_eq(GameState.get_counter("trees_felled"), 1, "no double count")


func test_respawn_after_time_passes() -> void:
	var r := _node({"node_id": "test_rock_1", "kind": "rock"})
	GameState.give_item("stone_pickaxe", 1)
	for i in 3:
		r.harvest_hit(null, "stone_pickaxe")
	assert_true(r.depleted, "rock broken")
	assert_false(r.can_respawn_now(), "not yet respawned")
	GameState.total_minutes += 1441.0
	assert_true(r.can_respawn_now(), "respawns after a day")
	r.restore(false)
	assert_false(r.depleted, "restored")
	assert_true(r.is_in_group("harvestable"), "harvestable again")
	assert_false(GameState.is_depleted("test_rock_1"), "state agrees")


func test_depleted_node_loads_depleted() -> void:
	GameState.deplete("test_stick_7", 600.0)
	var s := _node({"node_id": "test_stick_7", "kind": "stick"})
	assert_true(s.depleted, "loads in its depleted state")
	assert_eq(s.get_interaction(null), {}, "no prompt while gone")
	var fresh := _node({"node_id": "test_stick_8", "kind": "stick"})
	assert_false(fresh.depleted, "other nodes unaffected")


func test_hand_nodes_give_items_via_interact() -> void:
	var s := _node({"node_id": "test_stick_1", "kind": "stick"})
	var st := _node({"node_id": "test_stone_1", "kind": "stone"})
	var g := _node({"node_id": "test_tuft_1", "kind": "grass"})
	assert_true(s.is_in_group("interactable"), "sticks are E-interactables")
	assert_true(bool(s.get_interaction(null)["enabled"]))
	s.interact(null)
	st.interact(null)
	g.interact(null)
	assert_eq(GameState.count_item("wood"), 1, "stick gives 1 wood")
	assert_eq(GameState.count_item("stone"), 1, "stone gives 1 stone")
	var f := GameState.count_item("fiber")
	assert_true(f >= 1 and f <= 2, "grass gives 1-2 fiber (%d)" % f)
	assert_true(s.depleted and st.depleted and g.depleted, "all picked")
	# Picking again does nothing
	s.interact(null)
	assert_eq(GameState.count_item("wood"), 1, "no double pickup")


func test_berry_bush_keeps_bush_and_regrows() -> void:
	var b := _node({"node_id": "test_bush_1", "kind": "bush"})
	b.interact(null)
	var n := GameState.count_item("berries")
	assert_true(n >= 2 and n <= 4, "2-4 berries (%d)" % n)
	assert_true(b.depleted, "picked")
	assert_true(b.is_in_group("interactable"), "a picked bush still answers the prompt")
	assert_false(bool(b.get_interaction(null)["enabled"]), "prompt says it is regrowing")
	var visual: Node3D = b.get_node("Visual")
	assert_true(visual.visible, "the bush itself stays")
	GameState.total_minutes += 721.0
	assert_true(b.can_respawn_now())


func test_drop_table_ranges() -> void:
	var n := _node({"node_id": "", "kind": "ore"})
	for i in 30:
		var d: Dictionary = n.roll_drops()
		assert_true(int(d.get("copper_ore", 0)) >= 2 and int(d.get("copper_ore", 0)) <= 3, "copper 2-3")
		assert_eq(int(d.get("stone", 0)), 1, "plus one stone")
	var bush := _node({"node_id": "", "kind": "bush"})
	var seeds := 0
	for i in 400:
		seeds += int(bush.roll_drops().get("sweetroot_seeds", 0))
	assert_true(seeds > 50 and seeds < 160, "~25%% seed chance (%d / 400)" % seeds)


func test_world_item_persistence_and_pickup() -> void:
	var it: Node3D = WorldItem.spawn("berries", 5, Vector3(1, 0, 1), true, _holder)
	assert_not_null(it, "spawned")
	assert_eq(GameState.dropped.size(), 1, "recorded in GameState.dropped")
	var uid := String(it.uid)
	assert_eq(GameState.get_dropped(uid)["count"], 5)
	# spawn_from_state returns the existing node rather than duplicating it
	assert_eq(WorldItem.spawn_from_state(_holder, uid), it, "no duplicate node")
	assert_true(it.is_in_group("interactable") and it.is_in_group("pickup"))
	assert_eq(it.collect(null), 5, "picked up all five")
	assert_eq(GameState.count_item("berries"), 5)
	assert_eq(GameState.dropped.size(), 0, "removed from the dropped list")
	assert_true(it.is_collected())


func test_world_item_full_backpack_and_partial() -> void:
	# Fill every slot with wood except room for 3 berries in one partial stack.
	for i in GameState.INVENTORY_SIZE - 1:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})
	GameState.inventory.set_slot(GameState.INVENTORY_SIZE - 1, {"id": "berries", "count": 47})
	var it: Node3D = WorldItem.spawn("berries", 5, Vector3.ZERO, true, _holder)
	var uid := String(it.uid)
	assert_eq(it.collect(null), 3, "only 3 fit")
	assert_eq(int(GameState.get_dropped(uid).get("count", 0)), 2, "2 remain on the ground (persisted)")
	assert_eq(it.collect(null), 0, "backpack full: nothing more")
	assert_false(bool(it.get_interaction(null)["enabled"]), "prompt explains the backpack is full")
	# Recreate from state (e.g. after loading): the remaining count survives.
	_holder.remove_child(it)
	it.queue_free()
	await wait_frames(1)
	var again: Node3D = WorldItem.spawn_from_state(_holder, uid)
	assert_not_null(again, "respawned from state")
	assert_eq(int(again.count), 2)
	assert_null(WorldItem.spawn_from_state(_holder, "nope"), "unknown uid -> null")


func test_overflow_drop_round_trip_through_save() -> void:
	var uid := GameState.add_dropped("stone", 4, "surface", Vector3(3, 0, 3))
	assert_true(SaveSystem.save_game(), "saved")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "loaded")
	var d := GameState.get_dropped(uid)
	assert_eq(int(d.get("count", 0)), 4, "dropped item persisted")
	var node: Node3D = WorldItem.spawn_from_state(_holder, uid)
	assert_not_null(node)
	assert_eq(String(node.item_id), "stone")


func test_quest_items_always_fit() -> void:
	for i in GameState.INVENTORY_SIZE:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})
	var it: Node3D = WorldItem.spawn("heartseed", 1, Vector3.ZERO, true, _holder)
	assert_eq(it.collect(null), 1, "quest item goes to the key pouch")
	assert_true(GameState.has_item("heartseed"))


func test_mine_rubble_opens_and_persists() -> void:
	var m: Node3D = MineEntrance.new()
	_holder.add_child(m)
	assert_false(m.opened, "sealed at first")
	assert_eq(m.get_interaction(null), {}, "no enter prompt while sealed")
	GameState.give_item("stone_pickaxe", 1)
	for i in 3:
		m.rubble.harvest_hit(null, "stone_pickaxe")
	assert_false(GameState.get_flag("mine_opened"), "3 hits keep it sealed")
	m.rubble.harvest_hit(null, "stone_pickaxe")
	assert_true(bool(GameState.get_flag("mine_opened")), "4th hit opens it")
	assert_true(m.opened)
	assert_eq(String(m.get_interaction(null).get("text", "")), "Enter the Hollow Mine")
	GameState.total_minutes += 100000.0
	assert_true(GameState.is_depleted("mine_rubble"), "the rubble never grows back")
	assert_true(SaveSystem.save_game())
	GameState.reset()
	assert_true(SaveSystem.load_game())
	var m2: Node3D = MineEntrance.new()
	_holder.add_child(m2)
	assert_true(m2.opened, "open after loading")
	assert_true(m2.rubble.depleted, "rubble stays cleared after loading")


func test_mine_state_self_heals() -> void:
	GameState.set_flag("mine_opened", true)
	var m: Node3D = MineEntrance.new()
	_holder.add_child(m)
	assert_true(GameState.is_depleted("mine_rubble"), "flag implies the rubble is gone")
	assert_true(m.rubble.depleted)


func test_harvest_feedback_is_not_toasted_twice() -> void:
	# The HUD turns Events.item_added into the "+2 Stone" pop; the node must not add its own notify.
	var added: Array = []
	var notes: Array = []
	var on_added := func(id: String, n: int) -> void: added.append([id, n])
	var on_note := func(text: String, _kind: String) -> void: notes.append(text)
	Events.item_added.connect(on_added)
	Events.notify.connect(on_note)
	var s := _node({"node_id": "test_stone_dup", "kind": "stone"})
	s.interact(null)
	var it: Node3D = WorldItem.spawn("wood", 2, Vector3.ZERO, true, _holder)
	it.collect(null)
	Events.item_added.disconnect(on_added)
	Events.notify.disconnect(on_note)
	assert_eq(added.size(), 2, "item_added for the stone and the wood pickup")
	for t in notes:
		assert_false(String(t).begins_with("+"), "no duplicate '+n item' notify (%s)" % t)


func test_fx_bursts_clean_themselves_up() -> void:
	var Fx: GDScript = load("res://src/world/common/fx.gd")
	Fx.burst(_holder, Vector3.ZERO, "chips", 1.0)
	Fx.burst(_holder, Vector3.ZERO, "dust", 0.5)
	var count := func() -> int:
		var n := 0
		for c in _holder.get_children():
			if c is CPUParticles3D:
				n += 1
		return n
	assert_eq(count.call(), 2, "two bursts spawned")
	await wait_seconds(2.4)       # dust lives 1.1 s; the safety timer frees at lifetime + 1 s
	assert_eq(count.call(), 0, "one-shot bursts free themselves")
	# A burst whose parent disappears first must not leave anything behind (area change mid-burst).
	var tmp := Node3D.new()
	_holder.add_child(tmp)
	Fx.burst(tmp, Vector3.ZERO, "leaves", 1.0)
	tmp.free()
	await wait_seconds(0.2)
	assert_true(true, "freeing the parent mid-burst is safe")


func test_ward_stone_rereading_replaces_queued_lines() -> void:
	var ws: Node3D = WardStone.new()
	_holder.add_child(ws)
	ws.interact(null)                      # intro: 2 lines, the 2nd queued on a tween
	var first: Tween = ws.get("_say_tw")
	assert_true(first != null and first.is_valid(), "second intro line is queued")
	ws.interact(null)                      # read again straight away
	assert_false(first.is_valid(), "the old queued line is dropped, not interleaved with the new reading")


func test_ward_stone_restored_glow_is_brighter() -> void:
	var ws: Node3D = WardStone.new()
	_holder.add_child(ws)
	ws.set_restored(0.0)
	var dim: Color = (ws.get("rune_material") as StandardMaterial3D).albedo_color
	var dim_heart: Color = (ws.get("heart_material") as StandardMaterial3D).albedo_color
	ws.set_restored(1.0)
	var lit: Color = (ws.get("rune_material") as StandardMaterial3D).albedo_color
	var lit_heart: Color = (ws.get("heart_material") as StandardMaterial3D).albedo_color
	# Unshaded materials ignore emission: the glow must come from an HDR albedo above 1.0.
	assert_true(lit.r > 1.2 and lit.get_luminance() > dim.get_luminance() * 1.3, "restored runes glow (%s vs %s)" % [lit, dim])
	assert_true(lit_heart.get_luminance() > dim_heart.get_luminance() * 1.5, "restored heart glows")


func test_ward_stone_inscriptions() -> void:
	var said: Array = []
	var cb := func(speaker: String, text: String, _d: float) -> void:
		said.append([speaker, text])
	Events.say.connect(cb)
	var ws: Node3D = WardStone.new()
	_holder.add_child(ws)
	assert_true(ws.is_in_group("interactable"))
	assert_eq(String(ws.get_interaction(null)["text"]), "Read the Ward Stone")
	ws.interact(null)
	assert_true(bool(GameState.get_flag("read_ward_intro")), "intro read")
	assert_true(said.size() >= 1 and String(said[0][1]).contains("Light kept, home kept"), "intro inscription said")
	ws.interact(null)
	assert_false(bool(GameState.get_flag("read_ward_warning")), "no warning before Lumi / prepare")
	GameState.befriend("lumi")
	ws.interact(null)
	assert_true(bool(GameState.get_flag("read_ward_warning")), "warning read once Lumi is a friend")
	GameState.give_item("heartseed", 1)
	assert_eq(String(ws.get_interaction(null)["text"]), "Return the Heartseed")
	GameState.take_item("heartseed", 1)
	GameState.set_flag("ward_restored", true)
	said.clear()
	ws.interact(null)
	assert_true(said.size() == 1 and String(said[0][1]).begins_with("Light kept. Home kept. Thank you,"), "restored line")
	Events.say.disconnect(cb)
