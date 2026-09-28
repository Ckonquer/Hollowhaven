extends "res://tests/test_case.gd"
## Undo (exact refund, once, clearly previewed, no progress farming) and recolouring (uid, position and chest
## contents kept, only owned dyes, never automatic), plus carving a pumpkin face before placing it.

const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Tints := preload("res://src/building/tints.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _area: Node3D
var _prev_mode := ""
var _prev_palettes: Variant = null


func before_each() -> void:
	fresh_state()
	_prev_mode = Game.mode
	_prev_palettes = GameState.wardrobe.get("palettes", [])


func after_each() -> void:
	Game.mode = _prev_mode
	GameState.wardrobe["palettes"] = _prev_palettes
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null


func _make_area() -> Node3D:
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)
	return _area


func _build_mode() -> Node:
	var bm: Node = load("res://src/building/build_mode.gd").new()
	_area.add_child(bm)
	Game.mode = "playing"
	return bm


# --- Undo ------------------------------------------------------------------------------------------------------

func test_undo_is_previewed_then_refunds_exactly_once() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _build_mode()
	GameState.give_item("fence", 2)
	var built_before := GameState.get_counter("structures_built")
	bm.begin("fence")
	bm.debug_cursor = Vector3(5.5, 0, 5.5)
	bm._update(0.016)
	var uid: String = bm.try_place()
	assert_ne(uid, "")
	assert_eq(GameState.count_item("fence"), 1)
	assert_eq(GameState.get_counter("structures_built"), built_before + 1)
	assert_eq(String(bm.get_state()["undo"]), "Picket Fence", "the undo target is named")
	# First press only previews: nothing changes, the piece is highlighted.
	assert_false(bm.request_undo(), "first press previews")
	assert_true(GameState.structures.has(uid), "still there after the preview")
	assert_true(bool(bm.get_state()["undo_armed"]))
	bm._update(0.016)
	assert_eq(String(bm._highlight_uid), uid, "the piece to be undone is highlighted")
	assert_true(bm.request_undo(), "second press undoes")
	assert_false(GameState.structures.has(uid))
	assert_eq(GameState.count_item("fence"), 2, "exact refund")
	assert_eq(GameState.get_counter("structures_built"), built_before, "the build counter goes back: nothing to farm")
	assert_false(bm.request_undo(true), "nothing left to undo")
	assert_eq(GameState.count_item("fence"), 2, "never a second refund")
	bm.end()
	await wait_frames(2)


## The last piece of a stack: placing it empties the bag (the selection moves on), and undo still takes back
## exactly that piece.
func test_undo_of_the_last_piece_in_the_bag() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _build_mode()
	GameState.give_item("storage_chest", 1)
	bm.begin("storage_chest")
	bm.debug_cursor = Vector3(6.5, 0, 6.5)
	bm._update(0.016)
	var uid: String = bm.try_place()
	assert_ne(uid, "")
	assert_eq(GameState.count_item("storage_chest"), 0)
	assert_true(bm.request_undo(true), "undo right away")
	assert_false(GameState.structures.has(uid))
	assert_eq(GameState.count_item("storage_chest"), 1, "exact refund of the last one")
	bm.end()
	await wait_frames(2)


func test_undo_of_a_piece_already_taken_apart_refunds_nothing() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _build_mode()
	GameState.give_item("fence", 1)
	bm.begin("fence")
	bm.debug_cursor = Vector3(7.5, 0, 7.5)
	bm._update(0.016)
	var uid: String = bm.try_place()
	assert_true(bool(Ops.dismantle(_area, uid)["ok"]))
	assert_eq(GameState.count_item("fence"), 1, "refunded by dismantling")
	assert_false(bm.request_undo(true), "the undo list forgets pieces that are gone")
	assert_false(bool(Ops.undo_place(_area, uid, "fence")["ok"]))
	assert_eq(GameState.count_item("fence"), 1, "no double refund")
	bm.end()
	await wait_frames(2)


## An armed undo only previews: taking apart the piece she points at right after (X) takes THAT piece, not
## the highlighted undo target, and disarms the undo.
func test_dismantle_while_undo_is_armed_takes_the_piece_she_points_at() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _build_mode()
	GameState.give_item("fence", 2)
	bm.begin("fence")
	bm.debug_cursor = Vector3(5.5, 0, 5.5)
	bm._update(0.016)
	var first: String = bm.try_place()
	bm.debug_cursor = Vector3(8.5, 0, 5.5)
	bm._update(0.016)
	var last: String = bm.try_place()
	assert_ne(first, "")
	assert_ne(last, "")
	assert_eq(GameState.count_item("fence"), 0, "that was the last fence in the bag")
	assert_eq(String(bm.get_state()["undo"]), "Picket Fence", "placing the last one of a stack is still undoable")
	assert_false(bm.request_undo(), "first press arms the undo of the last fence")
	assert_eq(String(bm._undo_armed), last, "the undo previews the piece placed last, not the one before")
	bm.debug_cursor = Vector3(5.5, 0, 5.5)       # now point at the first fence
	bm._update(0.016)
	assert_eq(String(bm._highlight_uid), last, "the undo target stays highlighted while armed")
	assert_eq(bm.target_uid(), first, "the piece she points at is the target")
	assert_true(bm.try_dismantle())
	assert_false(GameState.structures.has(first), "the fence she pointed at came apart")
	assert_true(GameState.structures.has(last), "the undo target is untouched")
	assert_false(bool(bm.get_state()["undo_armed"]), "taking something apart disarms the undo")
	assert_eq(GameState.count_item("fence"), 1, "one refund")
	bm.end()
	await wait_frames(2)


func test_undo_follows_the_support_rules() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _build_mode()
	GameState.give_item("wood_wall", 1)
	bm.begin("wood_wall")
	bm.rot_deg = 0
	bm.debug_cursor = Vector3(3.2, 0, 0.1)
	bm._update(0.016)
	var wall: String = bm.try_place()
	assert_ne(wall, "")
	var roof := GameState.add_structure("wood_roof", Vector3(3, 3, 1), 0)      # built on the wall afterwards
	assert_false(bm.request_undo(true), "undoing the wall would leave the roof floating")
	assert_true(GameState.structures.has(wall) and GameState.structures.has(roof), "nothing collapses")
	assert_eq(GameState.count_item("wood_wall"), 0, "no refund for a refused undo")
	bm.end()
	await wait_frames(2)


# --- Recolour --------------------------------------------------------------------------------------------------

func _vertex_colors(n: Node) -> PackedColorArray:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m is ArrayMesh and m.get_surface_count() > 0:
			var arr := m.surface_get_arrays(0)
			if arr[Mesh.ARRAY_COLOR] is PackedColorArray:
				return arr[Mesh.ARRAY_COLOR]
	return PackedColorArray()


func test_recolour_keeps_uid_position_and_chest_contents() -> void:
	_make_area()
	GameState.wardrobe["palettes"] = ["rose", "midnight"]
	var uid := GameState.add_structure("storage_chest", Vector3(2.5, 0, 2.5), 90)
	var inv: RefCounted = GameState.get_storage(uid)
	inv.add("stone", 12)
	inv.set_slot(7, {"id": "berries", "count": 4})
	var before_slots: Array = inv.to_array()
	var node := Factory.spawn_structure(_area, uid)
	var natural := _vertex_colors(node.get_node("Model"))
	assert_eq(Ops.tint_options(uid), ["", "rose", "midnight"], "natural first, then the owned dyes")
	var res := Ops.recolor(_area, uid, "rose")
	assert_true(bool(res["ok"]), String(res.get("reason", "")))
	var rec: Dictionary = GameState.structures[uid]
	assert_eq(String(rec["data"]["tint"]), "rose")
	assert_eq(rec["pos"], [2.5, 0.0, 2.5], "never moved")
	assert_almost(float(rec["rot"]), 90.0)
	assert_true(GameState.storages[uid] == inv, "the very same chest inventory")
	assert_eq(inv.to_array(), before_slots, "contents untouched")
	assert_true(Factory.find_node(_area, uid) == node, "the node is kept (uid unchanged)")
	var dyed := _vertex_colors(node.get_node("Model"))
	assert_eq(dyed.size(), natural.size())
	assert_ne(dyed, natural, "the model is recoloured")
	assert_false(bool(Ops.recolor(_area, uid, "pumpkin")["ok"]), "only dyes made at the Loom")
	assert_eq(String(Ops.recolor(_area, uid, "pumpkin")["reason"]), Ops.MSG_TINT_LOCKED)
	assert_eq(Ops.next_tint(uid), "midnight")
	assert_true(bool(Ops.recolor(_area, uid, "")["ok"]), "back to natural wood")
	assert_false((GameState.structures[uid]["data"] as Dictionary).has("tint"))
	assert_eq(_vertex_colors(node.get_node("Model")), natural, "original colours restored")
	var cairn := GameState.add_structure("pebble_cairn", Vector3(6.5, 0, 6.5), 0)
	assert_eq(String(Ops.recolor(_area, cairn, "rose")["reason"]), Ops.MSG_NO_TINT, "not every piece takes dye")


func test_tint_survives_saving_and_respawning() -> void:
	_make_area()
	GameState.wardrobe["palettes"] = ["pumpkin"]
	var uid := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	assert_true(bool(Ops.recolor(null, uid, "pumpkin")["ok"]))
	var back: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(back)
	assert_eq(Tints.tint_of(GameState.structures[uid]), "pumpkin")
	var node := Factory.spawn_structure(_area, uid)
	var shown := _vertex_colors(node.get_node("Model"))
	var plain := Node3D.new()
	add_child(plain)
	preload("res://src/building/structure_models.gd").build("wood_wall", plain)
	assert_ne(shown, _vertex_colors(plain), "a saved tint is applied on load")
	plain.free()


func test_nothing_is_recoloured_automatically() -> void:
	_make_area()
	GameState.wardrobe["palettes"] = ["rose"]
	var uid := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	Factory.spawn_structure(_area, uid)
	assert_false((GameState.structures[uid]["data"] as Dictionary).has("tint"), "owning a dye changes nothing by itself")


# --- Pumpkin faces -----------------------------------------------------------------------------------------------

func test_pumpkin_face_is_chosen_before_placing_and_can_be_recarved() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _build_mode()
	GameState.give_item("pumpkin_lantern", 1)
	bm.begin("pumpkin_lantern")
	assert_eq(String(bm.get_state()["face"]), "friendly", "the first face by default")
	bm.cycle_variant()
	bm.cycle_variant()
	assert_eq(bm.selected_face(), "toothy")
	bm.debug_cursor = Vector3(6.5, 0, 6.5)
	bm._update(0.016)
	var uid: String = bm.try_place()
	assert_ne(uid, "")
	assert_eq(String(GameState.structures[uid]["data"]["face"]), "toothy", "saved in data.face")
	var n := Factory.find_node(_area, uid)
	assert_eq(String(n.face()), "toothy")
	assert_true(n.is_in_group("light_source"), "a real little light")
	var old_mesh: Mesh = (n.parts["face"] as MeshInstance3D).mesh
	assert_true(String(n.get_interaction(null)["text"]).contains("Cat"), "offers the next face")
	n.interact(null)
	assert_eq(String(GameState.structures[uid]["data"]["face"]), "cat")
	assert_ne((n.parts["face"] as MeshInstance3D).mesh, old_mesh, "re-carved")
	bm.end()
	await wait_frames(2)


# --- Keys ----------------------------------------------------------------------------------------------------------

## The Chapter Two build keys never shadow another action: every fallback key is free in Settings' default
## bindings (T is the companion skill, F the lantern), and a real key press reaches its build action.
func test_build_keys_never_shadow_other_actions() -> void:
	var fallback: Dictionary = load("res://src/building/build_mode.gd").FALLBACK_KEYS
	var used := {}
	for other in Settings.DEFAULT_BINDINGS:
		for b in Settings.DEFAULT_BINDINGS[other]:
			used[String(b)] = String(other)
	for action in fallback:
		var code := "key:%d" % int(fallback[action])
		assert_false(used.has(code), "%s's key is free (bound to %s)" % [action, String(used.get(code, ""))])
	_make_area()
	var bm := _build_mode()
	for action in fallback:
		if InputMap.has_action(action):
			continue     # Settings binds it: the binding decides
		var ev := InputEventKey.new()
		ev.physical_keycode = int(fallback[action]) as Key
		ev.pressed = true
		assert_true(bm._pressed(ev, action), action + " answers its key")
		var t := InputEventKey.new()
		t.physical_keycode = KEY_T
		t.pressed = true
		assert_false(bm._pressed(t, action), action + " leaves the companion skill key alone")


## A fallback key the player rebinds to another action (e.g. the journal on N) belongs to that action: build
## mode no longer swallows it, and its hints stop naming it.
func test_rebound_keys_are_left_to_their_new_action() -> void:
	var bm_script: Script = load("res://src/building/build_mode.gd")
	var fallback: Dictionary = bm_script.FALLBACK_KEYS
	var saved: Variant = Settings.values.get("bindings", {})
	_make_area()
	var bm := _build_mode()
	for action in fallback:
		if InputMap.has_action(action):
			continue
		# Default controls plus the journal moved onto this key (in memory only; nothing is saved).
		Settings.values["bindings"] = {"journal": ["key:%d" % int(fallback[action])]}
		var ev := InputEventKey.new()
		ev.physical_keycode = int(fallback[action]) as Key
		ev.pressed = true
		assert_false(bm._pressed(ev, action), action + ": the key now opens the journal")
		assert_eq(String(bm_script.key_label(action)), "-", action + ": hints don't promise a key it no longer has")
		Settings.values["bindings"] = {}
		assert_true(bm._pressed(ev, action), action + " gets its key back once the journal moves off it")
		assert_ne(String(bm_script.key_label(action)), "-")
	Settings.values["bindings"] = saved
