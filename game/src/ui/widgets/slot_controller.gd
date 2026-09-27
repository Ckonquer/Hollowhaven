extends Control
## Shared pointer rules for inventory-like grids (backpack, hotbar row, chests):
##   left press on a stack          -> pick it up (it follows the cursor)
##   left press while carrying      -> place / merge / swap
##   release over another slot      -> drop there (drag and drop)
##   right press on a stack         -> pick up half (split)
##   right press while carrying     -> place one item
##   shift + left press             -> quick-move (panel callback)
##   double click                   -> use (panel callback)
## Items are never removed while carried: the carried stack is a reference to its source slot, and
## every placement is a single UiUtil.move_stack() transaction, so nothing can be lost or duplicated.

signal changed
signal hovered_item(item_id: String)

const UiUtil := preload("res://src/ui/ui_util.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var slots: Array = []
var held: Dictionary = {}              # {"inv", "i", "count", "id", "slot"}
var quick_move: Callable = Callable()  # func(slot: Control) -> void
var use_item: Callable = Callable()    # func(slot: Control) -> void
var _origin: Control = null


func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	size = Vector2(90, 90)
	visible = false


func register(slot: Control) -> void:
	slots.append(slot)
	slot.pressed_slot.connect(_on_pressed)
	slot.released_slot.connect(_on_released)
	slot.hovered.connect(func(s: Control) -> void:
		if s.stack != null:
			hovered_item.emit(String(s.stack["id"]))
		_update_hints())
	slot.unhovered.connect(func(_s: Control) -> void: _update_hints())


func is_holding() -> bool:
	return not held.is_empty()


func cancel() -> void:
	if held.is_empty():
		return
	held = {}
	_origin = null
	_sync()


func _valid_held() -> bool:
	if held.is_empty():
		return false
	var s: Variant = (held["inv"] as RefCounted).get_slot(int(held["i"]))
	if s == null or String(s["id"]) != String(held["id"]):
		held = {}
		return false
	if int(s["count"]) < int(held["count"]):
		held["count"] = int(s["count"])
	return true


func _on_pressed(slot: Control, button: int, shift: bool, double: bool) -> void:
	_valid_held()
	if double and button == MOUSE_BUTTON_LEFT and slot.stack != null:
		cancel()
		if use_item.is_valid():
			use_item.call(slot)
		return
	if shift and button == MOUSE_BUTTON_LEFT:
		cancel()
		if slot.stack != null and quick_move.is_valid():
			quick_move.call(slot)
			Audio.play_ui("ui_click")
		return
	if button == MOUSE_BUTTON_LEFT:
		if held.is_empty():
			if slot.stack != null:
				_pick(slot, int(slot.stack["count"]))
		else:
			place(slot, int(held["count"]))
	elif button == MOUSE_BUTTON_RIGHT:
		if held.is_empty():
			if slot.stack != null:
				_pick(slot, UiUtil.split_half(int(slot.stack["count"])))
		else:
			place(slot, 1)


func _on_released(_slot: Control, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or held.is_empty() or _origin == null:
		return
	var target := slot_under_mouse()
	if target != null and target != _origin:
		place(target, int(held["count"]))
	_origin = null


func _pick(slot: Control, count: int) -> void:
	held = {"inv": slot.inv, "i": slot.index, "count": count, "id": String(slot.stack["id"]), "slot": slot}
	_origin = slot
	Audio.play_ui("ui_click", -4.0)
	_sync()


## Places `count` of the carried stack into `target`. Returns true on success.
func place(target: Control, count: int) -> bool:
	if not _valid_held():
		_sync()
		return false
	var src: RefCounted = held["inv"]
	var si := int(held["i"])
	if src == target.inv and si == target.index:
		# dropping back onto its own slot just puts it down
		cancel()
		return true
	var before: Variant = src.get_slot(si)
	var before_count := int(before["count"]) if before != null else 0
	var ok := UiUtil.move_stack(src, si, target.inv, target.index, count)
	if not ok:
		Audio.play_ui("ui_error", -4.0)
		return false
	Audio.play_ui("ui_click")
	var after: Variant = src.get_slot(si)
	var moved := before_count - (int(after["count"]) if after != null and String(after["id"]) == String(held["id"]) else 0)
	var left := int(held["count"]) - maxi(moved, 0)
	if after == null or String(after["id"]) != String(held["id"]) or left <= 0:
		held = {}
		_origin = null
	else:
		held["count"] = mini(left, int(after["count"]))
	_sync()
	return true


func slot_under_mouse() -> Control:
	for s in slots:
		var c: Control = s
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(c.get_global_mouse_position()):
			return c
	return null


func _sync() -> void:
	for s in slots:
		var c: Control = s
		var dim: bool = not held.is_empty() and c.inv == held["inv"] and c.index == int(held["i"])
		if c.dimmed != dim:
			c.dimmed = dim
			c.queue_redraw()
	visible = not held.is_empty()
	_update_hints()
	queue_redraw()
	changed.emit()


func _update_hints() -> void:
	var target: Control = slot_under_mouse() if not held.is_empty() else null
	for s in slots:
		var c: Control = s
		var hint: bool = target != null and c == target
		if c.drop_hint != hint:
			c.drop_hint = hint
			c.queue_redraw()


func _process(_delta: float) -> void:
	if held.is_empty():
		return
	global_position = get_global_mouse_position() - size * 0.35


func _draw() -> void:
	if held.is_empty():
		return
	var tex := IconFactory.item_icon(String(held["id"]))
	draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.95))
	var n := int(held["count"])
	if n > 1:
		var f := ThemeFactory.font("body_bold")
		var pos := Vector2(0, size.y - 6)
		draw_string_outline(f, pos, str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 24, 7, Color(ThemeFactory.INK, 0.95))
		draw_string(f, pos, str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 24, ThemeFactory.CREAM)
