extends "res://src/ui/panels/panel_base.gd"
## Crafting: station filter tabs (All / By Hand / Workbench / Campfire, with "nearby" markers from
## crafting.gd stations_near), the known recipes with icons and status, and a detail card with the
## ingredients (have / need colouring), the station requirement and a Craft button with feedback.
## args: {"station": "workbench"} preselects that station's tab (and counts it as available).

const StationOrder := ["hand", "workbench", "campfire"]

var stations: Array = ["hand"]
var filter := "all"
var tabs_box: HBoxContainer
var list_box: VBoxContainer
var detail: VBoxContainer
var craft_btn: Button
var feedback_l: Label
var _selected := ""
var _rows: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _group := ButtonGroup.new()
var _tw2: Dictionary = {}


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Crafting"
	window_min = Vector2(1500, 0)
	var st := String(p_args.get("station", ""))
	if st != "":
		filter = st


func reopen(p_args: Dictionary) -> void:
	var st := String(p_args.get("station", ""))
	if st != "":
		filter = st
	refresh()


func _build() -> void:
	tabs_box = Kit.hbox(10)
	body.add_child(tabs_box)
	var tab_group := ButtonGroup.new()
	for t in [["all", "All recipes"], ["hand", "By Hand"], ["workbench", "Workbench"], ["campfire", "Campfire"]]:
		var b := Kit.button(String(t[1]), _set_filter.bind(String(t[0])), "TabLike")
		b.toggle_mode = true
		b.button_group = tab_group
		b.expand_icon = false
		tabs_box.add_child(b)
		_tab_buttons[String(t[0])] = b
	var cols := Kit.hbox(28)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 640)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true   # arrowing through a long list keeps the focused recipe in view
	cols.add_child(sc)
	list_box = Kit.vbox(8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(700, 640)
	cols.add_child(card)
	var cv := Kit.vbox(12)
	card.add_child(cv)
	detail = Kit.vbox(10)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(detail)
	var bottom := Kit.hbox(18)
	cv.add_child(bottom)
	craft_btn = Kit.button("Craft", _craft, "AccentButton")
	craft_btn.custom_minimum_size = Vector2(240, 64)
	craft_btn.add_theme_font_size_override("font_size", 30)
	bottom.add_child(craft_btn)
	feedback_l = Kit.wrap_label("", "Small", 380)
	feedback_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	feedback_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(feedback_l)
	Events.inventory_changed.connect(_refresh_status)


func refresh() -> void:
	var pos: Variant = null
	if Game.player != null and is_instance_valid(Game.player):
		pos = Game.player.global_position
	stations = UiUtil.stations_near(pos, String(args.get("station", "")))
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		b.set_pressed_no_signal(String(id) == filter)
		if String(id) == "all":
			continue
		var near := stations.has(String(id))
		b.icon = IconFactory.glyph("dot", 20, 20, ThemeFactory.GOOD if near else Color(ThemeFactory.INK_SOFT, 0.35))
		b.tooltip_text = ("%s is nearby" if near else "Find a %s to use these recipes") % ItemDB.station_name(String(id))
	_build_list()


func _set_filter(f: String) -> void:
	filter = f
	_build_list()


func _recipes() -> Array:
	var out: Array = []
	var known := UiUtil.known_recipes()
	for st in StationOrder:
		for rid in known:
			var r := ItemDB.recipe(String(rid))
			if String(r.get("station", "hand")) != st:
				continue
			if filter != "all" and filter != st:
				continue
			out.append(String(rid))
	return out


func _build_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	_rows.clear()
	var ids := _recipes()
	var first_ok := ""
	for rid in ids:
		var row := _make_row(rid)
		list_box.add_child(row)
		_rows[rid] = row
		if first_ok == "" and bool(UiUtil.craft_check(rid, stations).get("ok", false)):
			first_ok = rid
	if ids.is_empty():
		list_box.add_child(Kit.wrap_label("No recipes here yet.", "Muted", 560))
	if not ids.has(_selected):
		_selected = first_ok if first_ok != "" else (ids[0] if not ids.is_empty() else "")
	_refresh_status()


func _make_row(rid: String) -> Button:
	var r := ItemDB.recipe(rid)
	var result := String(r["result"])
	var b := Button.new()
	b.theme_type_variation = "TabLike"
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(610, 84)
	b.pressed.connect(func() -> void:
		_selected = rid
		_refresh_status())
	# Keyboard browsing: the selection follows focus, so Enter crafts the recipe the player arrowed to.
	b.focus_entered.connect(func() -> void:
		if _selected != rid:
			_selected = rid
			_refresh_status())
	Kit.hook_sounds(b)
	var mc := Kit.margin([12, 6, 16, 6])
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(Kit.full_rect(mc))
	var h := Kit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(h)
	h.add_child(Kit.icon_rect(IconFactory.item_icon(result), 68))
	var v := Kit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var nm := Kit.label(ItemDB.display_name(result) + ("  x%d" % int(r.get("count", 1)) if int(r.get("count", 1)) > 1 else ""))
	nm.add_theme_font_override("font", ThemeFactory.font("heading"))
	nm.add_theme_font_size_override("font_size", 26)
	v.add_child(nm)
	var sub := Kit.label(_ingredient_summary(r), "Small")
	sub.name = "Sub"
	v.add_child(sub)
	var st := Kit.icon_rect(null, 34)
	st.name = "Status"
	h.add_child(st)
	return b


static func _ingredient_summary(r: Dictionary) -> String:
	var parts: Array = []
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		parts.append("%d %s" % [int(ings[id]), ItemDB.display_name(String(id))])
	return ", ".join(PackedStringArray(parts))


func _refresh_status() -> void:
	if not is_inside_tree():
		return
	for rid in _rows:
		var b: Button = _rows[rid]
		if not is_instance_valid(b):
			continue
		var chk: Dictionary = UiUtil.craft_check(String(rid), stations)
		var st := b.find_child("Status", true, false) as TextureRect
		if st != null:
			if bool(chk.get("ok", false)):
				st.texture = IconFactory.icon("ui_check", Color.WHITE, 48)
			elif not stations.has(String(ItemDB.recipe(String(rid)).get("station", "hand"))):
				st.texture = IconFactory.icon("ui_lock", Color.WHITE, 48)
			else:
				st.texture = null
		b.set_pressed_no_signal(String(rid) == _selected)
		b.modulate = Color.WHITE if bool(chk.get("ok", false)) else Color(1, 1, 1, 0.78)
	_show_detail()


func _show_detail() -> void:
	for c in detail.get_children():
		c.queue_free()
	if _selected == "":
		detail.add_child(Kit.wrap_label("Choose a recipe on the left.", "Muted", 600))
		craft_btn.disabled = true
		return
	var r := ItemDB.recipe(_selected)
	var result := String(r["result"])
	var top := Kit.hbox(18)
	detail.add_child(top)
	top.add_child(Kit.icon_rect(IconFactory.item_icon(result, 128), 120))
	var tv := Kit.vbox(2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var nl := Kit.wrap_label(ItemDB.display_name(result), "Heading", 400)
	nl.add_theme_font_size_override("font_size", 36)
	tv.add_child(nl)
	var cat := Kit.label(UiUtil.category_name(ItemDB.category(result)).to_upper() + ("   ·   MAKES %d" % int(r.get("count", 1)) if int(r.get("count", 1)) > 1 else ""), "Tiny")
	cat.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	tv.add_child(cat)
	tv.add_child(Kit.label("You have %d" % GameState.count_item(result), "Small"))
	var desc := Kit.wrap_label(ItemDB.display_desc(result), "", 640)
	desc.add_theme_font_size_override("font_size", 22)
	detail.add_child(desc)
	detail.add_child(section_title("Ingredients"))
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		var need := int(ings[id])
		var have := GameState.count_item(String(id))
		var h := Kit.hbox(12)
		h.add_child(Kit.icon_rect(IconFactory.item_icon(String(id)), 48))
		var n := Kit.label(ItemDB.display_name(String(id)))
		n.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(n)
		var cnt := Kit.label("%d / %d" % [have, need], "GoodText" if have >= need else "BadText")
		cnt.add_theme_font_size_override("font_size", 24)
		cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cnt)
		detail.add_child(h)
	var st := String(r.get("station", "hand"))
	var near := stations.has(st)
	var sl: Label
	if st == "hand":
		sl = Kit.label("Crafted by hand, anywhere.", "Small")
	else:
		sl = Kit.label(("Needs a %s  ·  nearby" if near else "Needs a %s  ·  not nearby") % ItemDB.station_name(st), "GoodText" if near else "BadText")
	detail.add_child(Kit.spacer(0, 4))
	detail.add_child(sl)
	var chk: Dictionary = UiUtil.craft_check(_selected, stations)
	craft_btn.disabled = not bool(chk.get("ok", false))
	craft_btn.tooltip_text = String(chk.get("reason", ""))


func _craft() -> void:
	if _selected == "":
		return
	var ok := UiUtil.craft(_selected, stations)
	var result := String(ItemDB.recipe(_selected).get("result", ""))
	if ok:
		Audio.play_ui("ui_craft")
		feedback_l.text = "Made %s!" % ItemDB.display_name(result)
		feedback_l.theme_type_variation = "GoodText"
		var tw := Kit.retween(craft_btn, _tw2, "pop")
		craft_btn.pivot_offset = craft_btn.size * 0.5
		craft_btn.scale = Vector2(1.08, 1.08)
		tw.tween_property(craft_btn, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		Audio.play_ui("ui_error")
		feedback_l.text = String(UiUtil.craft_check(_selected, stations).get("reason", "You can't make that right now."))
		feedback_l.theme_type_variation = "BadText"
	_refresh_status()


## The Craft button when something can be made, otherwise the selected (or first) recipe row, otherwise
## the station tab, so the arrow keys can always reach the list.
func default_focus() -> Control:
	if not craft_btn.disabled:
		return craft_btn
	var row: Variant = _rows.get(_selected, null)
	if row is Control and is_instance_valid(row) and not (row as Control).is_queued_for_deletion():
		return row
	for rid in _rows:
		var r: Variant = _rows[rid]
		if r is Control and is_instance_valid(r) and not (r as Control).is_queued_for_deletion():
			return r
	return _tab_buttons.get(filter, null)


## Enter crafts the selected recipe while the Craft button or a recipe row has focus (or nothing in this
## panel does). On any other focused control (the station tabs) Enter is left to the GUI (ui_accept).
func handle_key(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed and ((event as InputEventKey).keycode == KEY_ENTER or (event as InputEventKey).keycode == KEY_KP_ENTER):
		var fo: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if fo != null and fo != craft_btn and is_ancestor_of(fo) and not _rows.values().has(fo):
			return false
		if not craft_btn.disabled:
			_craft()
			return true
	return false
