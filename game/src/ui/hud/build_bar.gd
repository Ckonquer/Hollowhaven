extends PanelContainer
## Build-mode bar (Events.build_mode_changed / build_selection_changed / build_placement_state):
## the placeable items you carry (selected one highlighted), live validity of the ghost preview and
## key hints (place, rotate, dismantle, exit) using the current bindings.
## Chapter Two:
##   * a scrolling window of WINDOW pieces centred on the selected one (in the build mode's own order, the
##     order the wheel / 1-8 cycle through), with "‹ n" / "n ›" counts for the pieces off either edge, so all
##     50+ placeables stay reachable and visible;
##   * key caps for Undo / Recolour / Face from BuildMode.key_label() ("-" = the player gave that key to another
##     action: the hint is hidden; Face only while the selected piece has faces);
##   * the build mode's get_state() fields undo (what the undo key would take back), undo_armed (a second press
##     confirms), face (the selected pumpkin face) and level (the cursor's storey), polled a few times a second
##     while building (the build mode emits no events for them).

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

const BUILD_MODE_SCRIPT := "res://src/building/build_mode.gd"
## Pieces shown at once (the rest scroll in as the selection moves).
const WINDOW := 8
const POLL_SECONDS := 0.2
const CELL := 54.0

var selected_item := ""
var valid := true
var reason := ""
var active := false
## Item ids in the build mode's order (hotbar first), and the first one shown.
var placeables: Array = []
var window_start := 0
## From the build mode's get_state().
var undo_name := ""
var undo_armed := false
var face := ""
var level := 0
## Tests (or a caller that knows it) may point the bar at a build mode node; otherwise the first node of group
## "build_mode" is used.
var build_mode_node: Node = null
var item_row: HBoxContainer
var cells_box: HBoxContainer
var more_left: Label
var more_right: Label
var name_l: Label
var state_l: Label
var detail_l: Label
var keys_box: HBoxContainer
## action -> {"box": HBoxContainer, "cap": Label, "text": Label} for the Chapter Two key hints.
var key_hints: Dictionary = {}
var _tw: Dictionary = {}
var _poll_t := 0.0
var _keys_sig := ""
var _bm_script: Script = null


func _ready() -> void:
	theme_type_variation = "HudCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := Kit.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := Kit.hbox(16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var tv := Kit.vbox(0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.custom_minimum_size.x = 300
	top.add_child(tv)
	var hdr := Kit.label("BUILD MODE", "Tiny")
	hdr.add_theme_color_override("font_color", ThemeFactory.TEAL.darkened(0.2))
	tv.add_child(hdr)
	name_l = Kit.label("", "CardTitle")
	tv.add_child(name_l)
	state_l = Kit.label("", "GoodText")
	tv.add_child(state_l)
	detail_l = Kit.label("", "Small")
	detail_l.visible = false
	tv.add_child(detail_l)
	item_row = Kit.hbox(6)
	item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(item_row)
	more_left = _more_label(HORIZONTAL_ALIGNMENT_RIGHT)
	item_row.add_child(more_left)
	cells_box = Kit.hbox(6)
	cells_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.add_child(cells_box)
	more_right = _more_label(HORIZONTAL_ALIGNMENT_LEFT)
	item_row.add_child(more_right)
	keys_box = Kit.hbox(14)
	keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(keys_box)
	_build_keys()
	visible = false
	set_process(false)
	Events.build_mode_changed.connect(set_active)
	Events.build_selection_changed.connect(_on_selection_changed)
	Events.build_placement_state.connect(_on_placement_state)
	Events.inventory_changed.connect(_on_inventory_changed)
	Events.settings_changed.connect(_on_settings_changed)


func _more_label(align: HorizontalAlignment) -> Label:
	var l := Kit.label("", "Small", align)
	l.custom_minimum_size.x = 46
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	l.add_theme_color_override("font_color", ThemeFactory.INK)
	l.visible = false
	return l


func set_active(on: bool) -> void:
	active = on
	set_process(on)
	if on:
		visible = true
		_poll_t = 0.0
		_poll_state()
		_refresh()
		modulate.a = 0.0
		var tw := Kit.retween(self, _tw, "fade")
		tw.tween_property(self, "modulate:a", 1.0, 0.2)
	else:
		var tw2 := Kit.retween(self, _tw, "fade")
		tw2.tween_property(self, "modulate:a", 0.0, 0.2)
		tw2.tween_callback(_hide_if_inactive)


func _hide_if_inactive() -> void:
	if not active:
		visible = false


func _on_selection_changed(item_id: String) -> void:
	selected_item = item_id
	_poll_state()
	_refresh()


func _on_placement_state(ok: bool, why: String) -> void:
	valid = ok
	reason = why
	_refresh_state()


func _on_inventory_changed() -> void:
	if active:
		_refresh()


func _on_settings_changed(key: String) -> void:
	if key == "bindings" and active:
		_refresh_keys()


func _process(delta: float) -> void:
	if not active:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL_SECONDS
	var before_list := placeables.duplicate()
	var before_face := face
	_poll_state()
	if placeables != before_list or face != before_face:
		_refresh()
	else:
		_refresh_keys()


# --- Build mode state -------------------------------------------------------------------------------------------

func _build_mode() -> Node:
	if build_mode_node != null and is_instance_valid(build_mode_node):
		return build_mode_node
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("build_mode")


## Reads the build mode's snapshot (placeables order, undo, face, level). Without a build mode (HUD demos,
## tests driving the events alone) the inventory order stands in and the Chapter Two fields are cleared.
func _poll_state() -> void:
	var bm := _build_mode()
	var st: Dictionary = {}
	if bm != null and bm.has_method("get_state"):
		var r: Variant = bm.call("get_state")
		if r is Dictionary:
			st = r
	if st.is_empty():
		placeables = inventory_placeables()
		undo_name = ""
		undo_armed = false
		face = ""
		level = 0
		return
	var pl: Variant = st.get("placeables", [])
	placeables = (pl as Array).duplicate() if pl is Array else inventory_placeables()
	undo_name = String(st.get("undo", ""))
	undo_armed = bool(st.get("undo_armed", false)) and undo_name != ""
	face = String(st.get("face", ""))
	level = int(st.get("level", 0))


## Placeable item ids in the backpack, slot order (hotbar first), each once: the build mode's order.
static func inventory_placeables() -> Array:
	var out: Array = []
	for s in GameState.inventory.slots:
		if s is Dictionary:
			var id := String((s as Dictionary).get("id", ""))
			if id != "" and not out.has(id) and ItemDB.category(id) == "placeable":
				out.append(id)
	return out


## [first, end) of the pieces shown: every piece when they fit, otherwise `size` pieces with the selected one
## in the middle (clamped at both ends, so the window never shows blanks). Pure; see tests.
static func window_range(count: int, selected_index: int, size: int = WINDOW) -> Vector2i:
	if count <= 0:
		return Vector2i(0, 0)
	if size <= 0 or count <= size:
		return Vector2i(0, count)
	var sel := clampi(selected_index, 0, count - 1) if selected_index >= 0 else 0
	var start := clampi(sel - int(size * 0.5), 0, count - size)
	return Vector2i(start, start + size)


## The key label for a build action as build mode reads it ("-" = unbound: the key belongs to another action).
func key_label(action: String) -> String:
	if _bm_script == null and ResourceLoader.exists(BUILD_MODE_SCRIPT):
		var s: Variant = load(BUILD_MODE_SCRIPT)
		if s is Script:
			_bm_script = s
	if _bm_script != null and _bm_script.has_method("key_label"):
		return String(_bm_script.call("key_label", action))
	return Settings.action_label(action) if InputMap.has_action(action) else "-"


# --- Views ----------------------------------------------------------------------------------------------------

func _refresh() -> void:
	for c in cells_box.get_children():
		c.queue_free()
	var totals: Dictionary = GameState.inventory.totals()
	var sel_i := placeables.find(selected_item)
	var rng := window_range(placeables.size(), sel_i)
	window_start = rng.x
	for i in range(rng.x, rng.y):
		var id := String(placeables[i])
		cells_box.add_child(_cell(id, int(totals.get(id, 0)), id == selected_item))
	var left := rng.x
	var right := placeables.size() - rng.y
	more_left.visible = left > 0
	more_left.text = "‹ %d" % left
	more_right.visible = right > 0
	more_right.text = "%d ›" % right
	name_l.text = ItemDB.display_name(selected_item) if selected_item != "" else "Choose something to place"
	_refresh_keys(true)
	_refresh_state()


func _cell(id: String, count: int, sel: bool) -> Control:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", ThemeFactory.box(ThemeFactory.PAPER_LIGHT if sel else Color(ThemeFactory.PAPER_DARK, 0.7), 12, 3 if sel else 1, ThemeFactory.ACCENT if sel else ThemeFactory.BORDER, 4))
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.set_meta("item_id", id)
	var ov := Control.new()
	ov.custom_minimum_size = Vector2(CELL, CELL)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(Kit.icon_rect(IconFactory.item_icon(id), CELL))
	var cnt := Kit.label(str(count), "HudSmall", HORIZONTAL_ALIGNMENT_RIGHT)
	cnt.position = Vector2(0, 30)
	cnt.size = Vector2(52, 24)
	ov.add_child(cnt)
	cell.add_child(ov)
	return cell


## Item ids of the cells currently shown (tests).
func shown_items() -> Array:
	var out: Array = []
	for c in cells_box.get_children():
		if not c.is_queued_for_deletion() and c.has_meta("item_id"):
			out.append(String(c.get_meta("item_id")))
	return out


## Key hints: Place / Rotate / Dismantle / Undo / Recolour / Face / Exit (built once, updated in place).
func _build_keys() -> void:
	for pair in [["attack", "Place"], ["build_rotate", "Rotate"], ["build_dismantle", "Dismantle"], ["build_undo", "Undo"],
			["build_recolor", "Recolour"], ["build_variant", "Face"], ["build", "Exit"]]:
		var h := Kit.hbox(6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := Kit.key_cap("")
		h.add_child(cap)
		var l := Kit.label(String(pair[1]), "Small")
		l.add_theme_color_override("font_color", ThemeFactory.INK)
		h.add_child(l)
		keys_box.add_child(h)
		key_hints[String(pair[0])] = {"box": h, "cap": cap.get_child(0), "text": l, "base": String(pair[1])}


func _refresh_keys(force: bool = false) -> void:
	var labels := {}
	for action in key_hints:
		var a := String(action)
		labels[a] = key_label(a) if a in ["build_undo", "build_recolor", "build_variant"] else Settings.action_label(a)
	var sig := "%s|%s|%s|%s|%d" % [str(labels), undo_name, str(undo_armed), face, level]
	if sig == _keys_sig and not force:
		return
	_keys_sig = sig
	for action in key_hints:
		var a := String(action)
		var e: Dictionary = key_hints[a]
		var key := String(labels[a])
		var box: Control = e["box"]
		(e["cap"] as Label).text = key
		var text_l: Label = e["text"]
		var show := key != "-" and key != ""
		text_l.text = String(e["base"])
		text_l.remove_theme_color_override("font_color")
		text_l.add_theme_color_override("font_color", ThemeFactory.INK)
		box.modulate.a = 1.0
		match a:
			"build_undo":
				if undo_armed:
					text_l.text = "Again to undo the %s" % undo_name
					text_l.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.25))
				elif undo_name != "":
					text_l.text = "Undo %s" % undo_name
				else:
					box.modulate.a = 0.5     # nothing placed yet this visit: shown, but quiet
			"build_variant":
				show = show and face != ""
		box.visible = show
	var parts: Array = []
	if level > 0:
		parts.append("Building upstairs")
	if face != "":
		parts.append("Face: %s" % face.replace("_", " ").capitalize())
	detail_l.text = "  ·  ".join(PackedStringArray(parts))
	detail_l.visible = not parts.is_empty()


func _refresh_state() -> void:
	if selected_item == "":
		state_l.text = "Pick a buildable item from your hotbar"
		state_l.theme_type_variation = "Small"
		return
	if valid:
		state_l.text = "Ready to place"
		state_l.theme_type_variation = "GoodText"
	else:
		state_l.text = reason if reason != "" else "Can't place here"
		state_l.theme_type_variation = "BadText"
