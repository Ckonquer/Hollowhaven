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

const Placement := preload("res://src/building/placement.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Models := preload("res://src/building/structure_models.gd")
const Ops := preload("res://src/building/build_ops.gd")
const U := preload("res://src/building/model_util.gd")
const Palette := preload("res://src/art/palette.gd")

const MAX_REACH := 8.0
const RAY_LENGTH := 45.0
const REVALIDATE_SECONDS := 0.2
const MSG_NOTHING := "Nothing to build yet. Craft pieces at a Workbench."

signal placed(uid: String)
signal dismantled(uid: String)

var active := false
var selected_item := ""
var rot_deg := 0
## Automated tests / the debug harness can pin the cursor to a world point instead of the camera ray.
var debug_cursor: Variant = null

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
func get_state() -> Dictionary:
	return {"active": active, "item": selected_item, "structure": _sid, "valid": _state_valid, "reason": _state_reason,
		"rotation": rot_deg, "placeables": placeables()}


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
		if not _player_in_build_area():
			Events.notify.emit(Placement.MSG_OUTSIDE + ".", "warn")
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
	_last_key = ""
	_dirty = true
	_rebuild_ghost()
	if changed or force:
		Events.build_selection_changed.emit(item_id)


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
		_set_highlight(_under_uid)
		if _under_uid != "":
			_set_state(false, "Press %s to take this apart" % Settings.action_label("build_dismantle"))
		else:
			_set_state(false, MSG_NOTHING)
		return
	var def := Placement.def_of(_sid)
	var snapped := Placement.snap_position(def, point, float(rot_deg))
	var key := "%s|%d|%.2f|%.2f" % [_sid, rot_deg, snapped.x, snapped.z]
	_revalidate_t -= delta
	if key != _last_key or _dirty or _revalidate_t <= 0.0:
		_last_key = key
		_dirty = false
		_revalidate_t = REVALIDATE_SECONDS
		_result = Placement.validate(_sid, snapped, float(rot_deg), _make_ctx())
	_target = Vector3(snapped.x, float(_result.get("y", snapped.y)), snapped.z)
	_has_target = true
	var ok := bool(_result.get("ok", false))
	var blocker := String(_result.get("blocker", ""))
	_set_highlight(blocker)
	var reason := String(_result.get("reason", ""))
	if blocker != "":
		reason += " (%s to take it apart)" % Settings.action_label("build_dismantle")
	_set_state(ok, reason)
	_show_ghost(delta)
	_update_grid()


func _make_ctx() -> Dictionary:
	var p: Node = Game.player
	var ppos: Variant = (p as Node3D).global_position if p is Node3D and is_instance_valid(p) else null
	var ctx := Ops.make_ctx(area(), ppos)
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
		return debug_cursor
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
	if not hit.is_empty():
		point = hit["position"]
		_cursor_collider = hit["collider"]
	elif dir.y < -0.02:
		point = from + dir * ((origin.y - from.y) / dir.y)
	else:
		point = origin + Vector3(dir.x, 0.0, dir.z).normalized() * 3.0
	var flat := Vector2(point.x - origin.x, point.z - origin.z)
	if flat.length() > MAX_REACH:
		flat = flat.normalized() * MAX_REACH
		point = Vector3(origin.x + flat.x, origin.y, origin.z + flat.y)
		_cursor_collider = null
		var hf := Ops.height_fn(area())
		if hf.is_valid():
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
	var ctx := {"structures": GameState.structures, "area_id": Ops.area_id_of(area()), "occupancy": _occ}
	return Placement.structure_at_point(point, ctx)


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
	return ""


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
	var res := Placement.validate(_sid, _target, float(rot_deg), _make_ctx())
	if not bool(res.get("ok", false)):
		_result = res
		_set_state(false, String(res.get("reason", "")))
		_fail_feedback()
		return ""
	var pos := Vector3(_target.x, float(res.get("y", _target.y)), _target.z)
	var uid := Ops.place_structure(area(), selected_item, pos, float(rot_deg))
	if uid == "":
		_fail_feedback()
		return ""
	_mark_dirty()
	_last_key = ""
	placed.emit(uid)
	return uid


## Dismantles the piece under the cursor (or blocking the ghost). Returns true on success.
func try_dismantle() -> bool:
	if not active:
		return false
	var uid: String = _highlight_uid if _highlight_uid != "" else _under_uid
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
	_mark_dirty()
	_last_key = ""
	dismantled.emit(uid)
	return true


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
	Models.build(_sid, _ghost_model)
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
	var want_rot := deg_to_rad(float(rot_deg))
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


func _on_cutscene(on: bool) -> void:
	if on:
		end()
