extends Node
## Haven build mode (added to the surface area by building_system.gd; group "build_mode").
##
## Enter: "build" action (B) while playing with no UI open, or begin(item_id) (the player calls this
## when a placeable hotbar item is used). While active:
##   ghost preview of the selected piece (green = valid / red = invalid) at the camera-centre ray hit
##   (max ~8 m from Krystal), snapped to the grid; LMB ("attack") places, R rotates, X dismantles the
##   piece under the cursor (full refund), mouse wheel / 1-8 pick a placeable, E / Esc / B exit.
## Input is consumed in _input() while active. Pollers must also respect it: the player's
## `build_mode_active` flag is set while active (and cleared shortly after exit so the exit key doesn't
## also trigger an interaction), and is_active() tells the camera to ignore wheel zoom.
## Emits Events.build_mode_changed / build_selection_changed / build_placement_state(valid, reason).
##
## Chapter Two:
##   storeys  the cursor's storey comes from what it hits (the top of an upper floor = upstairs); stairs,
##            upper floors and roofs pick their own storey (placement.gd requested_level)
##   undo     Z (action "build_undo" when bound): first press highlights the last piece you placed and says
##            what will be refunded, a second press within UNDO_CONFIRM_SECONDS takes it back (exact refund,
##            the build counter goes back too). Up to UNDO_DEPTH recent placements, newest first.
##   recolour P (action "build_recolor"): cycles the piece under the cursor through natural wood and the dye
##            palettes made at the Loom (data.tint; uid and contents kept). Never automatic.
##   variant  N (action "build_variant"): with a carved pumpkin selected, picks its face BEFORE placing
##            (saved as data.face; the ghost shows it); pointing at a placed pumpkin re-carves it. Only faces
##            available now are offered (pumpkin_faces.gd: the six faces, then the Lanternwake festival faces
##            once ch2_feast is set).
##   wall decor  pieces with data mount "wall" snap onto the nearest wall (placement.gd mount_snap) with their
##            back against it (the ghost turns to face away from the wall; R only matters away from walls), and
##            the ghost shows the window variant (curtain pair / centred flower box) and upstairs wall variant
##   The fallback keys (FALLBACK_KEYS) avoid every default binding (T is the companion skill, F the lantern),
##   so build mode never shadows another action.

const Placement := preload("res://src/building/placement.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Models := preload("res://src/building/structure_models.gd")
const Ops := preload("res://src/building/build_ops.gd")
const U := preload("res://src/building/model_util.gd")
const Palette := preload("res://src/art/palette.gd")

const Tints := preload("res://src/building/tints.gd")
const Faces := preload("res://src/building/pumpkin_faces.gd")

const MAX_REACH := 8.0
const RAY_LENGTH := 45.0
const REVALIDATE_SECONDS := 0.2
const MSG_NOTHING := "Nothing to build yet. Craft pieces at a Workbench."
const UNDO_DEPTH := 10
const UNDO_CONFIRM_SECONDS := 4.0
const UPSTAIRS_NORMAL_Y := 0.7        # only the TOP of an upper-storey piece selects the upper storey
## Keys used until Settings binds the Chapter Two build actions (rebindable once the actions exist).
const FALLBACK_KEYS := {"build_undo": KEY_Z, "build_recolor": KEY_P, "build_variant": KEY_N}

signal placed(uid: String)
signal dismantled(uid: String)
signal undone(uid: String)
signal recolored(uid: String, tint: String)

var active := false
var selected_item := ""
var rot_deg := 0
## Automated tests / the debug harness can pin the cursor to a world point instead of the camera ray
## (and say which storey it points at).
var debug_cursor: Variant = null
var debug_level := 0

var _sid := ""
var _ghost: Node3D
var _ghost_model: Node3D
var _ghost_valid := true
var _ghost_shown := false
var _grid: MeshInstance3D
var _grid_key := ""
var _target := Vector3.ZERO
var _has_target := false
var _result: Dictionary = {}
var _last_key := ""
var _revalidate_t := 0.0
var _dirty := true
var _occ: Dictionary = {}
var _occ_dirty := true
var _state_valid := true
var _state_reason := "<unset>"
var _highlight_uid := ""
var _under_uid := ""
var _cursor_collider: Object = null
var _wiggle: Tween
var _pending_item := ""
var _pending_until_ms := 0
var _cursor_level := 0
var _undo: Array = []                 # [{"uid", "item", "name"}], oldest first
var _undo_armed := ""
var _undo_armed_until_ms := 0
var _face_index := 0
var _height_fn: Callable
var _place_rot := 0                   # rotation the target was validated with (wall decor turns to its wall)
var _ghost_opts_key := ""             # model options the ghost was built with (mount dir / storey)
var _snap_ctx: Dictionary = {}        # wall-decor snapping context (placement.gd mount_snap)


## Contract helper: spawn a saved structure (used when loading).
static func spawn_structure(area: Node, uid: String) -> Node3D:
	return Factory.spawn_structure(area, uid)


func _ready() -> void:
	add_to_group("build_mode")
	Events.ui_stack_changed.connect(_on_ui_stack_changed)
	Events.paused_changed.connect(_on_paused_changed)
	Events.area_exiting.connect(_on_area_exiting)
	Events.player_died.connect(end)
	Events.cutscene_changed.connect(_on_cutscene)
	Events.inventory_changed.connect(_on_inventory_changed)
	Events.structure_placed.connect(_mark_dirty.unbind(2))
	Events.structure_removed.connect(_mark_dirty.unbind(2))


func _exit_tree() -> void:
	if active:
		active = false
		_set_player_flag(false)
		Events.build_mode_changed.emit(false)


func is_active() -> bool:
	return active


func area() -> Node:
	return get_parent()


## Snapshot for UIs that open mid-way (build bar): {active, item, structure, valid, reason, rotation, placeables}.
## Chapter Two keys: level (cursor storey), face (selected pumpkin face or ""), undo (name of the piece the
## undo key would take back, "" = nothing), undo_armed (a second press confirms).
func get_state() -> Dictionary:
	_prune_undo()
	return {"active": active, "item": selected_item, "structure": _sid, "valid": _state_valid, "reason": _state_reason,
		"rotation": rot_deg, "placeables": placeables(), "level": _cursor_level, "face": selected_face(),
		"undo": String(_undo.back()["name"]) if not _undo.is_empty() else "", "undo_armed": _undo_is_armed()}


# --- Enter / exit ----------------------------------------------------------------------------------

func can_start() -> bool:
	return is_inside_tree() and Game.mode == "playing" and not Game.is_ui_open() and not get_tree().paused \
		and _player_input_enabled()


## False while the player's own input is switched off (sleeping in the bed, scripted moments): building
## must not start (or continue) behind a fade.
func _player_input_enabled() -> bool:
	var p: Node = Game.player
	if p == null or not is_instance_valid(p):
		return true
	var ie: Variant = p.get("input_enabled")
	return not (ie is bool) or bool(ie)


## Enters build mode (or switches the selection when already active).
func begin(item_id: String = "") -> void:
	if not active:
		if not can_start():
			# e.g. the inventory's "Place" button calls begin() while its panel is still closing:
			# remember the request for a moment and start as soon as the UI is gone.
			if is_inside_tree() and (Game.mode == "playing" or Game.mode == "loading"):
				_pending_item = item_id if item_id != "" else "<default>"
				_pending_until_ms = Time.get_ticks_msec() + 1500
			return
		_pending_item = ""
		active = true
		rot_deg = _facing_rot()
		_last_key = ""
		_dirty = true
		_occ_dirty = true
		_state_reason = "<unset>"
		_set_player_flag(true)
		Events.build_mode_changed.emit(true)
		Audio.play_ui("ui_open")
		# {attack}/{build} are standard HUD tokens; the build-only keys are filled in here.
		Events.hint.emit("build_controls", "Place with {attack}. %s rotates, %s takes a piece apart (full refund). Mouse wheel or 1-8 picks a piece. {build} or Esc to finish." % [
			Settings.action_label("build_rotate"), Settings.action_label("build_dismantle")])
		Events.hint.emit("build_controls_ch2", "%s undoes your last piece (press twice). %s recolours the piece you point at with dyes from the Loom. Stairs lead up to upper floors, held up by walls or porch posts." % [
			key_label("build_undo"), key_label("build_recolor")])
		if not _player_in_build_area():
			Events.notify.emit(Placement.outside_reason(Ops.build_area_for(Ops.area_id_of(area()))) + ".", "warn")
	var pick: String = item_id if Ops.structure_for_item(item_id) != "" and GameState.has_item(item_id) else ""
	if pick == "":
		pick = _default_selection()
	_select(pick, true)


func end() -> void:
	if not active:
		return
	active = false
	_clear_ghost()
	_set_highlight("")
	_has_target = false
	Events.build_mode_changed.emit(false)
	Audio.play_ui("ui_close")
	if is_inside_tree():
		get_tree().create_timer(0.15).timeout.connect(_on_release_timeout)
	else:
		_set_player_flag(false)


func _on_release_timeout() -> void:
	if not active:
		_set_player_flag(false)


func _set_player_flag(on: bool) -> void:
	var p: Node = Game.player
	if p != null and is_instance_valid(p) and "build_mode_active" in p:
		p.set("build_mode_active", on)


# --- Input ---------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	if not active:
		if event.is_action_pressed("build") and can_start():
			begin("")
			get_viewport().set_input_as_handled()
		return
	if Game.mode != "playing" or get_tree().paused or Game.is_ui_open():
		return
	var handled := true
	if event.is_action_pressed("build") or event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		end()
	elif event.is_action_pressed("attack"):
		try_place()
	elif event.is_action_pressed("build_rotate"):
		rotate_step()
	elif event.is_action_pressed("build_dismantle"):
		try_dismantle()
	elif _pressed(event, "build_undo"):
		request_undo()
	elif _pressed(event, "build_recolor"):
		recolor_under_cursor()
	elif _pressed(event, "build_variant") and _variant_applies():
		cycle_variant()
	elif event.is_action_pressed("zoom_in"):
		cycle(-1)
	elif event.is_action_pressed("zoom_out"):
		cycle(1)
	else:
		handled = false
		for i in 8:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				select_number(i)
				handled = true
				break
		if not handled and (event.is_action("attack") or event.is_action("zoom_in") or event.is_action("zoom_out")):
			handled = true      # swallow releases too, so nothing else reacts to build clicks
	if handled:
		get_viewport().set_input_as_handled()


## True for the Chapter Two build actions: the bound action when Settings has it, else FALLBACK_KEYS. A
## fallback key the player has bound to another action (e.g. the journal rebound to N) belongs to that action:
## build mode never swallows it.
func _pressed(event: InputEvent, action: String) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		var want: int = int(FALLBACK_KEYS.get(action, KEY_NONE))
		if want == KEY_NONE or not (k.physical_keycode == want or (k.physical_keycode == KEY_NONE and k.keycode == want)):
			return false
		return not _key_bound_elsewhere(k)
	return false


## Is this key bound to some other action in the player's (possibly rebound) controls? Only runs on a key
## press that matches a fallback key.
static func _key_bound_elsewhere(k: InputEventKey) -> bool:
	if Settings.has_method("actions_using"):
		return not (Settings.actions_using(k) as Array).is_empty()
	return false


static func key_label(action: String) -> String:
	if InputMap.has_action(action):
		return Settings.action_label(action)
	var k := InputEventKey.new()
	k.physical_keycode = int(FALLBACK_KEYS.get(action, KEY_NONE)) as Key
	if _key_bound_elsewhere(k):
		return "-"      # the player gave this key to another action (bind the build action to use it)
	return OS.get_keycode_string(int(FALLBACK_KEYS.get(action, KEY_NONE)))


# --- Selection ----------------------------------------------------------------------------------------------

## Placeable item ids the player owns, hotbar slots first.
func placeables() -> Array:
	var out: Array = []
	for s in GameState.inventory.slots:
		if s != null:
			var id := String(s["id"])
			if not out.has(id) and Ops.structure_for_item(id) != "":
				out.append(id)
	return out


func _default_selection() -> String:
	var sel: Variant = GameState.selected_slot()
	if sel is Dictionary and Ops.structure_for_item(String(sel["id"])) != "":
		return String(sel["id"])
	var list := placeables()
	return String(list[0]) if not list.is_empty() else ""


func _select(item_id: String, force: bool = false) -> void:
	if item_id == selected_item and not force:
		return
	var changed := item_id != selected_item
	selected_item = item_id
	_sid = Ops.structure_for_item(item_id)
	if changed:
		_face_index = 0
	_last_key = ""
	_dirty = true
	if changed:
		_result = {}
	_rebuild_ghost()
	if changed or force:
		Events.build_selection_changed.emit(item_id)
		if active and not _faces().is_empty():
			Events.hint.emit("build_pumpkin_face", "%s picks the carved face before you place it. Interact with a placed pumpkin to carve it a new one." % key_label("build_variant"))
			var festival := Faces.unlocked_festival()
			if not festival.is_empty():
				var names: Array = festival.map(func(f: Variant) -> String: return String(f).capitalize())
				Events.hint.emit("build_pumpkin_festival_faces", "The Lanternwake taught you festival carvings: %s. %s cycles through them." % [" and ".join(PackedStringArray(names)), key_label("build_variant")])


func cycle(dir: int) -> void:
	var list := placeables()
	if list.is_empty():
		_select("")
		return
	var i := list.find(selected_item)
	i = posmod(i + dir, list.size()) if i >= 0 else 0
	_select(String(list[i]))
	Audio.play_ui("ui_hover")


func select_number(i: int) -> void:
	var slot: Variant = GameState.inventory.get_slot(i)
	if slot is Dictionary and Ops.structure_for_item(String(slot["id"])) != "":
		GameState.select_hotbar(i)
		_select(String(slot["id"]))
	else:
		var list := placeables()
		if i < list.size():
			_select(String(list[i]))
	Audio.play_ui("ui_hover")


func rotate_step() -> void:
	rot_deg = (rot_deg + 90) % 360
	_last_key = ""
	Audio.play_ui("ui_click")


func _on_inventory_changed() -> void:
	if not active:
		return
	if selected_item != "" and GameState.has_item(selected_item):
		return
	var list := placeables()
	_select(String(list[0]) if not list.is_empty() else "")


# --- Per-frame preview ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active:
		return
	if Game.mode != "playing" or not _player_input_enabled():
		end()
		return
	_update(delta)


func _update(delta: float) -> void:
	var point: Variant = _cursor()
	if point == null:
		_has_target = false
		_hide_ghost()
		_set_highlight("")
		return
	_under_uid = _structure_under_cursor(point)
	if _sid == "":
		_has_target = false
		_hide_ghost()
		_set_highlight(_undo_armed if _undo_is_armed() else _under_uid)
		if _under_uid != "":
			_set_state(false, "Press %s to take this apart" % Settings.action_label("build_dismantle"))
		else:
			_set_state(false, MSG_NOTHING)
		return
	var def := Placement.def_of(_sid)
	var rot := rot_deg
	var snapped := Placement.snap_position(def, point, float(rot_deg))
	if Placement.is_wall_mount(def):
		_snap_ctx["structures"] = GameState.structures      # reused every frame (no per-frame allocation)
		_snap_ctx["area_id"] = Ops.area_id_of(area())
		_snap_ctx["occupancy"] = _occ
		_snap_ctx["level"] = _cursor_level
		var ms := Placement.mount_snap(point, _snap_ctx)
		if not ms.is_empty():
			rot = int(ms["rot"])
			snapped = ms["pos"]
	var key := "%s|%d|%.2f|%.2f|%d" % [_sid, rot, snapped.x, snapped.z, _cursor_level]
	_revalidate_t -= delta
	if key != _last_key or _dirty or _revalidate_t <= 0.0:
		_last_key = key
		_dirty = false
		_revalidate_t = REVALIDATE_SECONDS
		_result = Placement.validate(_sid, snapped, float(rot), _make_ctx())
		_sync_ghost_opts(def)
	_place_rot = rot
	_target = Vector3(snapped.x, float(_result.get("y", snapped.y)), snapped.z)
	_has_target = true
	var ok := bool(_result.get("ok", false))
	var blocker := String(_result.get("blocker", ""))
	_set_highlight(_undo_armed if _undo_is_armed() else blocker)
	var reason := String(_result.get("reason", ""))
	if blocker != "":
		reason += " (%s to take it apart)" % Settings.action_label("build_dismantle")
	_set_state(ok, reason)
	_show_ghost(delta)
	_update_grid()


func _make_ctx() -> Dictionary:
	var p: Node = Game.player
	var ppos: Variant = (p as Node3D).global_position if p is Node3D and is_instance_valid(p) else null
	var ctx := Ops.make_ctx(area(), ppos, _cursor_level)
	ctx["physics_fn"] = _physics_check
	return ctx


func _set_state(valid: bool, reason: String) -> void:
	if _ghost != null and valid != _ghost_valid:
		_ghost_valid = valid
		_apply_ghost_look(_ghost, valid)
	if valid == _state_valid and reason == _state_reason:
		return
	_state_valid = valid
	_state_reason = reason
	Events.build_placement_state.emit(valid, reason)


func _mark_dirty() -> void:
	_dirty = true
	_occ_dirty = true


# --- Cursor ---------------------------------------------------------------------------------------------------

func _camera() -> Camera3D:
	var p: Node = Game.player
	if p != null and is_instance_valid(p) and p.has_method("get_camera"):
		var c: Variant = p.get_camera()
		if c is Camera3D:
			return c
	if is_inside_tree():
		return get_viewport().get_camera_3d()
	return null


## World point the player is aiming at (clamped to MAX_REACH from Krystal), or null.
func _cursor() -> Variant:
	_cursor_collider = null
	if debug_cursor is Vector3:
		_cursor_level = debug_level
		return debug_cursor
	_cursor_level = 0
	var cam := _camera()
	if cam == null or not cam.is_inside_tree():
		return null
	var p: Node = Game.player
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var origin: Vector3 = (p as Node3D).global_position if p is Node3D and is_instance_valid(p) else from
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH, 1 | 32)
	if p is CollisionObject3D:
		q.exclude = [(p as CollisionObject3D).get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var point: Vector3
	# Upstairs, aim on the upper floor's plane: a ray that misses the floor (past its edge) or dips to the
	# ground far below still points at the spot next to the floor, where the next tile or railing goes.
	var upstairs := _is_upstairs(origin)
	if not hit.is_empty():
		point = hit["position"]
		_cursor_collider = hit["collider"]
		_cursor_level = _level_of_hit(_cursor_collider, hit.get("normal", Vector3.UP))
	if upstairs and (hit.is_empty() or point.y < origin.y - 0.6) and dir.y < -0.02:
		point = from + dir * ((origin.y - from.y) / dir.y)
		_cursor_collider = null
		_cursor_level = 1
	elif hit.is_empty():
		if dir.y < -0.02:
			point = from + dir * ((origin.y - from.y) / dir.y)
		else:
			point = origin + Vector3(dir.x, 0.0, dir.z).normalized() * 3.0
		if upstairs:
			_cursor_level = 1
	var flat := Vector2(point.x - origin.x, point.z - origin.z)
	if flat.length() > MAX_REACH:
		flat = flat.normalized() * MAX_REACH
		point = Vector3(origin.x + flat.x, origin.y, origin.z + flat.y)
		_cursor_collider = null
		_cursor_level = 1 if upstairs else 0
		var hf := Ops.height_fn(area())
		if hf.is_valid() and not upstairs:
			point.y = float(hf.call(point.x, point.z))
	return point


func _structure_under_cursor(point: Vector3) -> String:
	var n: Variant = _cursor_collider
	while n is Node and is_instance_valid(n):
		if (n as Node).has_meta("structure_uid"):
			var u := String((n as Node).get_meta("structure_uid"))
			if GameState.structures.has(u):
				return u
			break
		n = (n as Node).get_parent()
	if _occ_dirty:
		_occ = Placement.build_occupancy(GameState.structures, Ops.area_id_of(area()))
		_occ_dirty = false
	var ctx := {"structures": GameState.structures, "area_id": Ops.area_id_of(area()), "occupancy": _occ, "level": _cursor_level}
	return Placement.structure_at_point(point, ctx)


## True when Krystal stands on an upper storey (well above the ground under her).
func _is_upstairs(feet: Vector3) -> bool:
	if not _height_fn.is_valid():
		_height_fn = Ops.height_fn(area())     # cached: no per-frame Callable
		if not _height_fn.is_valid():
			return false
	return feet.y - float(_height_fn.call(feet.x, feet.z)) > Placement.UPSTAIRS_CLEARANCE


## Storey the cursor points at: the top surface of a piece that stands upstairs (an upper floor tile, a
## table up there...) selects that storey; walls, undersides and the ground are the ground storey.
static func _level_of_hit(collider: Object, normal: Variant) -> int:
	if not (normal is Vector3) or (normal as Vector3).y < UPSTAIRS_NORMAL_Y:
		return 0
	var n: Variant = collider
	while n is Node and is_instance_valid(n):
		if (n as Node).has_meta("structure_uid"):
			var rec: Variant = GameState.structures.get(String((n as Node).get_meta("structure_uid")))
			return Placement.level_of(rec) if rec is Dictionary else 0
		n = (n as Node).get_parent()
	return 0


func _player_in_build_area() -> bool:
	var p: Node = Game.player
	if not (p is Node3D) or not is_instance_valid(p):
		return true
	return Placement.in_build_area((p as Node3D).global_position, Ops.build_area_for(Ops.area_id_of(area())))


## Rotation (0/90/180/270) that turns a piece's front toward the camera.
func _facing_rot() -> int:
	var cam := _camera()
	if cam == null:
		return 0
	var fwd := -cam.global_basis.z
	var d := Vector2(-fwd.x, -fwd.z)
	if d.length() < 0.01:
		return 0
	return posmod(int(roundf(rad_to_deg(atan2(d.x, d.y)) / 90.0)) * 90, 360)


# --- Live physics checks (called by Placement.validate through ctx.physics_fn) ---------------------------------

func _physics_check(structure_id: String, pos: Vector3, rot: int) -> String:
	var a := area()
	if not (a is Node3D) or not (a as Node3D).is_inside_tree():
		return ""
	var def := Placement.def_of(structure_id)
	var fp := Placement.footprint(def, pos, float(rot))
	var rect: Rect2 = fp["rect"]
	var centre := Vector3(rect.get_center().x, pos.y, rect.get_center().y)
	var h := clampf(float(def.get("height", 1.0)), 0.15, 3.0)
	var space := (a as Node3D).get_world_3d().direct_space_state
	if bool(def.get("solid", false)):
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _box(Vector3(maxf(rect.size.x - 0.06, 0.1), h, maxf(rect.size.y - 0.06, 0.1)))
		q.transform = Transform3D(Basis.IDENTITY, centre + Vector3.UP * (h * 0.5))
		q.collision_mask = 2 | 4
		for r in space.intersect_shape(q, 8):
			var c: Variant = r.get("collider")
			if c is Node and (c as Node).is_in_group("player"):
				return "You're standing in the way"
			if c is Node and (c as Node).is_in_group("companion"):
				var cid: Variant = (c as Node).get("companion_id")
				var nm: String = String(ItemDB.creature(String(cid)).get("name", "Your friend")) if cid != null else "Your friend"
				return "%s is in the way" % nm
	if Placement.snap_kind(def) != "roof2":
		var lift := 0.45
		var hh := maxf(h - lift, 0.3)
		var q2 := PhysicsShapeQueryParameters3D.new()
		q2.shape = _box(Vector3(maxf(rect.size.x - 0.14, 0.1), hh, maxf(rect.size.y - 0.14, 0.1)))
		q2.transform = Transform3D(Basis.IDENTITY, centre + Vector3.UP * (lift + hh * 0.5))
		q2.collision_mask = 1
		if not space.intersect_shape(q2, 1).is_empty():
			return "Something is in the way"
		# Gatherables (sticks, stones, tall grass around the expanded Haven) have no world collider: ask
		# Krystal to pick them up first instead of building over them.
		var q3 := PhysicsShapeQueryParameters3D.new()
		q3.shape = q2.shape
		q3.transform = Transform3D(Basis.IDENTITY, centre + Vector3.UP * (hh * 0.5))
		q3.collision_mask = 16
		for r in space.intersect_shape(q3, 8):
			var owner: Node = _harvestable_owner(r.get("collider"))
			if owner != null:
				var info: Variant = owner.call("get_harvest_info") if owner.has_method("get_harvest_info") else {}
				var nm2: String = String((info as Dictionary).get("name", "")) if info is Dictionary else ""
				return ("Gather the %s first" % nm2) if nm2 != "" else "Gather what's growing here first"
	return ""


static func _harvestable_owner(c: Variant) -> Node:
	var n: Variant = c
	while n is Node and is_instance_valid(n):
		if (n as Node).is_in_group("harvestable"):
			return n
		if (n as Node).has_meta("structure_uid"):
			return null
		n = (n as Node).get_parent()
	return null


static func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


# --- Actions ------------------------------------------------------------------------------------------------------

## Places the selected piece at the current target. Returns the new uid or "".
func try_place() -> String:
	if not active or _sid == "" or not _has_target:
		_fail_feedback()
		return ""
	var res := Placement.validate(_sid, _target, float(_place_rot), _make_ctx())
	if not bool(res.get("ok", false)):
		_result = res
		_set_state(false, String(res.get("reason", "")))
		_fail_feedback()
		return ""
	var pos := Vector3(_target.x, float(res.get("y", _target.y)), _target.z)
	var data := {}
	if selected_face() != "":
		data["face"] = selected_face()
	# Remember the item first: placing the LAST one empties the stack, and the inventory listener switches the
	# selection before place_structure returns (the undo entry must still name what was placed).
	var item := selected_item
	var uid := Ops.place_structure(area(), item, pos, float(_place_rot), int(res.get("level", 0)), data)
	if uid == "":
		_fail_feedback()
		return ""
	_push_undo(uid, item)
	_mark_dirty()
	_last_key = ""
	placed.emit(uid)
	return uid


## Dismantles the piece under the cursor (or blocking the ghost). Returns true on success.
func try_dismantle() -> bool:
	if not active:
		return false
	# The piece she points at (or the one blocking the ghost), never the one an armed undo is highlighting.
	var uid: String = target_uid()
	if uid == "" or not GameState.structures.has(uid):
		Audio.play_ui("build_invalid")
		Events.notify.emit("Point at something you built to take it apart.", "info")
		return false
	var res := Ops.dismantle(area(), uid)
	if not bool(res.get("ok", false)):
		Audio.play_ui("build_invalid")
		Events.notify.emit(String(res.get("reason", "")), "warn")
		return false
	_set_highlight("")
	_under_uid = ""
	_undo_armed = ""
	_mark_dirty()
	_last_key = ""
	dismantled.emit(uid)
	return true


# --- Undo (Chapter Two) --------------------------------------------------------------------------------------

func _push_undo(uid: String, item_id: String) -> void:
	var sid := Ops.structure_for_item(item_id)
	_undo.append({"uid": uid, "item": item_id, "name": ItemDB.structure_display_name(sid) if sid != "" else item_id})
	while _undo.size() > UNDO_DEPTH:
		_undo.pop_front()
	_undo_armed = ""


## Drops entries whose piece is gone (dismantled, undone) or was replaced.
func _prune_undo() -> void:
	var i := _undo.size() - 1
	while i >= 0:
		var e: Dictionary = _undo[i]
		var rec: Variant = GameState.structures.get(String(e["uid"]))
		if not (rec is Dictionary) or String((rec as Dictionary).get("id", "")) != Ops.structure_for_item(String(e["item"])):
			_undo.remove_at(i)
		i -= 1


func _undo_is_armed() -> bool:
	return _undo_armed != "" and Time.get_ticks_msec() <= _undo_armed_until_ms and GameState.structures.has(_undo_armed)


## Undo key: the first press previews (highlights the last placed piece and says what comes back), a second
## press within UNDO_CONFIRM_SECONDS undoes it. `confirm` = undo right away (tests, UI buttons).
## Returns true when a piece was taken back.
func request_undo(confirm: bool = false) -> bool:
	_prune_undo()
	if _undo.is_empty():
		_undo_armed = ""
		Audio.play_ui("build_invalid")
		Events.notify.emit(Ops.MSG_NOTHING_TO_UNDO, "info")
		return false
	var e: Dictionary = _undo.back()
	var uid := String(e["uid"])
	if not confirm and not (_undo_is_armed() and _undo_armed == uid):
		_undo_armed = uid
		_undo_armed_until_ms = Time.get_ticks_msec() + int(UNDO_CONFIRM_SECONDS * 1000.0)
		_set_highlight(uid)
		Audio.play_ui("ui_hover")
		Events.notify.emit("Press %s again to undo the %s (it goes back into your bag)." % [key_label("build_undo"), String(e["name"])], "info")
		return false
	_undo_armed = ""
	var res := Ops.undo_place(area(), uid, String(e["item"]))
	if not bool(res.get("ok", false)):
		Audio.play_ui("build_invalid")
		Events.notify.emit(String(res.get("reason", Ops.MSG_NOTHING_TO_UNDO)), "warn")
		return false
	_undo.pop_back()
	_set_highlight("")
	_under_uid = ""
	_mark_dirty()
	_last_key = ""
	Events.notify.emit("Undone: %s." % String(e["name"]), "info")
	undone.emit(uid)
	return true


# --- Recolour and pumpkin faces (Chapter Two) ----------------------------------------------------------------

## The piece a dismantle, recolour or re-carve applies to: the highlighted one (the ghost's blocker, or the
## piece under the cursor), else the one under the cursor; never the piece an armed undo is previewing.
func target_uid() -> String:
	var previewing_undo := _undo_is_armed() and _highlight_uid == _undo_armed
	if _highlight_uid != "" and not previewing_undo and GameState.structures.has(_highlight_uid):
		return _highlight_uid
	return _under_uid if GameState.structures.has(_under_uid) else ""


## Cycles the piece under the cursor to its next tint (natural, then each dye palette made at the Loom).
func recolor_under_cursor() -> bool:
	var uid := target_uid()
	if uid == "":
		Events.notify.emit("Point at a piece you built to recolour it.", "info")
		return false
	var opts := Ops.tint_options(uid)
	if opts.is_empty():
		Audio.play_ui("build_invalid")
		Events.notify.emit(Ops.MSG_NO_TINT, "info")
		return false
	if opts.size() < 2:
		Events.notify.emit("Make a dye at the Loom to recolour your home.", "info")
		return false
	var tint := Ops.next_tint(uid)
	var res := Ops.recolor(area(), uid, tint)
	if not bool(res.get("ok", false)):
		Events.notify.emit(String(res.get("reason", "")), "warn")
		return false
	Audio.play_ui("ui_click")
	var rec: Dictionary = GameState.structures.get(uid, {})
	Events.notify.emit("%s: %s" % [ItemDB.structure_display_name(String(rec.get("id", ""))), Tints.display_name(tint)], "info")
	recolored.emit(uid, tint)
	return true


## Face ids the selected piece can be carved with now ([] when it has none): its own faces, then the
## unlocked festival faces (locked ones are never offered).
func _faces() -> Array:
	return Faces.unlocked_faces(Placement.def_of(_sid)) if _sid != "" else []


## The face the selected pumpkin will be carved with ("" when the selection has no faces).
func selected_face() -> String:
	var f := _faces()
	return String(f[posmod(_face_index, f.size())]) if not f.is_empty() else ""


func _variant_applies() -> bool:
	if not _faces().is_empty():
		return true
	var uid := target_uid()
	if uid == "":
		return false
	var faces: Variant = Placement.def_of(String(GameState.structures[uid].get("id", ""))).get("faces", [])
	return faces is Array and not (faces as Array).is_empty()


## Next face for the selected pumpkin (before placing), or re-carves the pumpkin under the cursor.
func cycle_variant() -> void:
	var f := _faces()
	if not f.is_empty():
		_face_index = posmod(_face_index + 1, f.size())
		_rebuild_ghost()
		Audio.play_ui("ui_click")
		Events.notify.emit("Face: %s" % selected_face().capitalize(), "info")
		return
	var n := Factory.find_node(area(), target_uid())
	if n != null and n.has_method("set_face") and n.has_method("next_face"):
		n.set_face(n.next_face())


func _fail_feedback() -> void:
	Audio.play_ui("build_invalid")
	if _ghost_model == null or not _ghost_model.is_inside_tree():
		return
	if _wiggle != null and _wiggle.is_valid():
		_wiggle.kill()
	_ghost_model.position = Vector3.ZERO
	_wiggle = create_tween()
	for x in [0.07, -0.06, 0.04, -0.02, 0.0]:
		_wiggle.tween_property(_ghost_model, "position:x", float(x), 0.045)


# --- Ghost, highlight & grid ------------------------------------------------------------------------------------------

func _rebuild_ghost() -> void:
	_clear_ghost()
	if _sid == "" or not active:
		return
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	add_child(_ghost)
	_ghost_model = Node3D.new()
	_ghost_model.name = "Model"
	_ghost.add_child(_ghost_model)
	var opts := _ghost_opts()
	_ghost_opts_key = "%d|%d" % [int(opts.get("mount_dir", 0)), int(opts.get("level", 0))]
	Models.build(_sid, _ghost_model, opts)
	var def := Placement.def_of(_sid)
	var snap := Placement.snap_kind(def)
	if snap != "roof2":
		var fp := Placement.footprint(def, Vector3.ZERO, 0.0)
		var rect: Rect2 = fp["rect"]
		var plate := MeshInstance3D.new()
		plate.mesh = _plate_mesh(rect.size)
		plate.position = Vector3(0, 0.025, 0)
		_ghost.add_child(plate)
		if snap == "cell":
			# a little arrow showing which way the piece faces
			var arrow := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.28, 0.2, 0.02)
			arrow.mesh = pm
			arrow.rotation_degrees = Vector3(-90, 0, 0)
			arrow.position = Vector3(0, 0.03, rect.size.y * 0.5 + 0.18)
			_ghost.add_child(arrow)
	_ghost_valid = _state_valid
	_apply_ghost_look(_ghost, _ghost_valid)
	_ghost.visible = false
	_ghost_shown = false


## Model options for the ghost: the pumpkin face, and what the validation says about the spot (the window
## variant of wall decor, the upstairs variant of wall panels), so the ghost looks like the piece will.
func _ghost_opts() -> Dictionary:
	var o := {}
	if selected_face() != "":
		o["face"] = selected_face()
	var md := int(_result.get("mount_dir", 0))
	if md != 0:
		o["mount_dir"] = md
	var lv := int(_result.get("level", 0))
	if lv >= 1:
		o["level"] = lv
	return o


## Rebuilds the ghost when the model options it depends on change (rare: moving onto a window / upstairs).
func _sync_ghost_opts(def: Dictionary) -> void:
	if not Placement.is_wall_mount(def) and Placement.snap_kind(def) != "edge2":
		return
	var k := "%d|%d" % [int(_result.get("mount_dir", 0)), int(_result.get("level", 0))]
	if k == _ghost_opts_key:
		return
	if _ghost != null:
		var shown := _ghost_shown
		var at := _ghost.position
		var rot_y := _ghost.rotation.y
		_rebuild_ghost()
		if shown and _ghost != null:
			_ghost.position = at
			_ghost.rotation.y = rot_y
			_ghost.visible = true
			_ghost_shown = true


static func _plate_mesh(size: Vector2) -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(size.x, 0.03, size.y)
	return b


func _apply_ghost_look(n: Node, valid: bool) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.material_override = U.ghost_mat(valid)
		g.material_overlay = null
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is Label3D:
		(n as Label3D).modulate = Color(0.7, 1.0, 0.75, 0.55) if valid else Color(1.0, 0.6, 0.6, 0.55)
		(n as Label3D).outline_modulate = Color(0, 0, 0, 0)
	for c in n.get_children():
		_apply_ghost_look(c, valid)


func _show_ghost(delta: float) -> void:
	if _ghost == null:
		return
	var want_rot := deg_to_rad(float(_place_rot))
	if not _ghost_shown or _ghost.position.distance_to(_target) > 3.0:
		_ghost.position = _target
		_ghost.rotation.y = want_rot
	else:
		var k := 1.0 - exp(-22.0 * delta)
		_ghost.position = _ghost.position.lerp(_target, k)
		_ghost.rotation.y = lerp_angle(_ghost.rotation.y, want_rot, k)
	_ghost.visible = true
	_ghost_shown = true


func _hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false
	_ghost_shown = false
	if _grid != null:
		_grid.visible = false


func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_model = null
	_ghost_shown = false
	if _grid != null and is_instance_valid(_grid):
		_grid.queue_free()
	_grid = null
	_grid_key = ""


func _set_highlight(uid: String) -> void:
	if uid == _highlight_uid:
		return
	var old: Node3D = Factory.find_node(area(), _highlight_uid) if _highlight_uid != "" else null
	if old != null and old.has_method("set_highlight"):
		old.set_highlight(false)
	_highlight_uid = uid
	var n: Node3D = Factory.find_node(area(), uid) if uid != "" else null
	if n != null and n.has_method("set_highlight"):
		n.set_highlight(true)


## Soft grid lines around the target so the snapping is readable.
func _update_grid() -> void:
	var def := Placement.def_of(_sid)
	var snap := Placement.snap_kind(def)
	var step: float = 1.0 if snap == "cell" else 2.0
	var base_y: float = _target.y - (Placement.WALL_HEIGHT if snap == "roof2" else 0.0)
	var cx := floorf(_target.x / step) * step
	var cz := floorf(_target.z / step) * step
	var key := "%.1f|%.1f|%.1f|%.2f" % [step, cx, cz, base_y]
	if _grid == null:
		_grid = MeshInstance3D.new()
		_grid.name = "Grid"
		_grid.mesh = ImmediateMesh.new()
		_grid.material_override = _grid_mat()
		_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_grid)
	_grid.visible = true
	if key == _grid_key:
		return
	_grid_key = key
	var im := _grid.mesh as ImmediateMesh
	im.clear_surfaces()
	var extent: float = 4.0 if step < 1.5 else 6.0
	var y := base_y + 0.035
	var centre := Vector2(_target.x, _target.z)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := int(extent / step)
	for i in range(-n, n + 2):
		var gx := cx + float(i) * step
		var gz := cz + float(i) * step
		var t := -extent
		while t < extent + 0.001:
			for seg in [[Vector2(gx, cz + t), Vector2(gx, cz + t + 0.5)], [Vector2(cx + t, gz), Vector2(cx + t + 0.5, gz)]]:
				for pt in seg:
					var d := (pt as Vector2).distance_to(centre) / extent
					var al := clampf(1.0 - d, 0.0, 1.0)
					im.surface_set_color(Color(1.0, 0.98, 0.9, 0.33 * al * al))
					im.surface_add_vertex(Vector3((pt as Vector2).x, y, (pt as Vector2).y))
			t += 0.5
	im.surface_end()


static func _grid_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true          # stay readable over tall grass (faint, and only around the cursor)
	m.render_priority = 2
	return m


# --- Event handlers -----------------------------------------------------------------------------------------------

func _on_ui_stack_changed(open_count: int) -> void:
	if active and open_count > 0:
		end()
	elif not active and open_count == 0 and _pending_item != "":
		_retry_pending.call_deferred()


func _on_paused_changed(paused: bool) -> void:
	if not paused and not active and _pending_item != "":
		_retry_pending.call_deferred()


func _retry_pending() -> void:
	if _pending_item == "" or active:
		return
	if Time.get_ticks_msec() > _pending_until_ms:
		_pending_item = ""
		return
	if not can_start():
		return
	var it := _pending_item
	_pending_item = ""
	begin("" if it == "<default>" else it)


func _on_area_exiting(_area_id: String) -> void:
	end()
	_undo.clear()
	_undo_armed = ""


func _on_cutscene(on: bool) -> void:
	if on:
		end()
