extends "res://src/ui/panels/panel_base.gd"
## Crafting: station filter tabs (All / By Hand / Workbench / Campfire / Furnace / Loom / Kitchen, with "nearby"
## markers from crafting.gd stations_near), the known recipes with icons and status, and a detail card with the
## ingredients (have / need colouring, and where they come from), the station requirement and a Craft button.
## Chapter Two: special recipes (backpack upgrades, clothing patterns, dye palettes at the Loom), the furnace
## queue (Furnace tab: jobs with progress, ready output + Collect; recipes are "Add to queue"), an optional
## "Also use nearby chests" toggle (placed chests within Crafting.CHEST_RADIUS = 18 m in this area; the card lists
## what comes from where)
## and the festival table choice at the kitchen.
## args: {"station": "workbench"} preselects that station's tab (and counts it as available);
##       {"station": "furnace", "uid": furnace uid} opens on that furnace's queue; {"pos": Vector3} (tests)
##       stands in for Krystal's position when there is no player.

const Crafting := preload("res://src/crafting/crafting.gd")
const Furnace := preload("res://src/crafting/furnace.gd")

const StationOrder := ["hand", "workbench", "campfire", "furnace", "loom", "kitchen"]
const TABS := [["all", "All recipes"], ["hand", "By Hand"], ["workbench", "Workbench"], ["campfire", "Campfire"],
	["furnace", "Furnace"], ["loom", "Loom"], ["kitchen", "Kitchen"]]
const LIST_HEIGHT := 640.0
const LIST_HEIGHT_WITH_QUEUE := 330.0
const QUEUE_STATUS_W := 90.0          # furnace queue: "20 s" / "waiting" column width

var stations: Array = ["hand"]
var filter := "all"
var furnace_uid := ""
var sources: Array = []            # chest uids used when "use nearby chests" is on (stable order)
var tabs_box: HBoxContainer
var list_box: VBoxContainer
var list_scroll: ScrollContainer
var queue_box: VBoxContainer
var detail: VBoxContainer
var craft_btn: Button
var feedback_l: Label
var chest_toggle: CheckButton
var chest_info_l: Label
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
	furnace_uid = String(p_args.get("uid", "")) if st == "furnace" else ""


func reopen(p_args: Dictionary) -> void:
	args = p_args
	var st := String(p_args.get("station", ""))
	if st != "":
		filter = st
	if st == "furnace" and String(p_args.get("uid", "")) != "":
		furnace_uid = String(p_args["uid"])
	refresh()


func _build() -> void:
	tabs_box = Kit.hbox(10)
	body.add_child(tabs_box)
	var tab_group := ButtonGroup.new()
	for t in TABS:
		var b := Kit.button(String(t[1]), _set_filter.bind(String(t[0])), "TabLike")
		b.toggle_mode = true
		b.button_group = tab_group
		b.expand_icon = false
		tabs_box.add_child(b)
		_tab_buttons[String(t[0])] = b
	var cols := Kit.hbox(28)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	var left := Kit.vbox(10)
	cols.add_child(left)
	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(640, LIST_HEIGHT)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true   # arrowing through a long list keeps the focused recipe in view
	left.add_child(list_scroll)
	list_box = Kit.vbox(8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list_box)
	queue_box = Kit.vbox(8)
	queue_box.custom_minimum_size = Vector2(640, 0)
	queue_box.visible = false
	left.add_child(queue_box)
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(700, 640)
	cols.add_child(card)
	var cv := Kit.vbox(12)
	card.add_child(cv)
	detail = Kit.vbox(10)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(detail)
	var src_row := Kit.hbox(12)
	cv.add_child(src_row)
	chest_toggle = CheckButton.new()
	chest_toggle.text = "Also use nearby chests"
	chest_toggle.tooltip_text = "Take missing ingredients from your placed chests within %d m (backpack first)." % int(Crafting.CHEST_RADIUS)
	chest_toggle.button_pressed = Crafting.use_chests()
	chest_toggle.toggled.connect(_on_chest_toggle)
	Kit.hook_sounds(chest_toggle)
	src_row.add_child(chest_toggle)
	chest_info_l = Kit.label("", "Small")
	chest_info_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	src_row.add_child(chest_info_l)
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
	Events.station_queue_changed.connect(_on_station_queue_changed)


func _player_pos() -> Variant:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player.global_position
	var p: Variant = args.get("pos", null)
	return p if p is Vector3 else null


func refresh() -> void:
	var pos: Variant = _player_pos()
	stations = UiUtil.stations_near(pos, String(args.get("station", "")))
	if furnace_uid != "" and not Furnace.is_furnace(furnace_uid):
		furnace_uid = ""
	if furnace_uid == "" and pos is Vector3 and stations.has("furnace"):
		furnace_uid = Crafting.nearest_station_uid(pos, "furnace")
	if furnace_uid != "" and not stations.has("furnace"):
		stations.append("furnace")
	_update_sources()
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		b.set_pressed_no_signal(String(id) == filter)
		if String(id) == "all":
			continue
		var near := stations.has(String(id))
		b.icon = IconFactory.glyph("dot", 20, 20, ThemeFactory.GOOD if near else Color(ThemeFactory.INK_SOFT, 0.35))
		b.tooltip_text = ("%s is nearby" if near else "Find a %s to use these recipes") % ItemDB.station_name(String(id))
	_build_list()


func _update_sources() -> void:
	sources = []
	var pos: Variant = _player_pos()
	var near: Array = Crafting.chest_sources_near(pos) if pos is Vector3 else []
	if Crafting.use_chests():
		sources = near
	if chest_info_l != null:
		if near.is_empty():
			chest_info_l.text = "(no chests within %d m)" % int(Crafting.CHEST_RADIUS)
		else:
			chest_info_l.text = "(%d chest%s nearby)" % [near.size(), "" if near.size() == 1 else "s"]


func _on_chest_toggle(on: bool) -> void:
	Crafting.set_use_chests(on)
	_update_sources()
	_refresh_status()


func _set_filter(f: String) -> void:
	filter = f
	_build_list()


func _hidden(rid: String) -> bool:
	var r := Crafting.recipe_def(rid)
	var ap := String(r.get("apply", ""))
	return ap.begins_with("backpack_") and int(GameState.inventory.size) >= ap.trim_prefix("backpack_").to_int()


func _recipes() -> Array:
	var out: Array = []
	var known := UiUtil.known_recipes()
	for st in StationOrder:
		if filter != "all" and filter != st:
			continue
		for rid in known:
			var r := ItemDB.recipe(String(rid))
			if String(r.get("station", "hand")) != st:
				continue
			out.append(String(rid))
		for rid2 in Crafting.known_special(st):
			if not _hidden(String(rid2)):
				out.append(String(rid2))
	return out


## Detaches and frees every child at once (a queue_free alone keeps them in the layout until the frame ends,
## which would briefly inflate the window's minimum size).
static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _build_list() -> void:
	_clear(list_box)
	_rows.clear()
	var ids := _recipes()
	var first_ok := ""
	for rid in ids:
		var row := _make_row(rid)
		list_box.add_child(row)
		_rows[rid] = row
		if first_ok == "" and bool(_check(rid).get("ok", false)):
			first_ok = rid
	if ids.is_empty():
		list_box.add_child(Kit.wrap_label("No recipes here yet.", "Muted", 560))
	if filter == "kitchen" and bool(GameState.get_flag("ch2_accepted")):
		list_box.add_child(_table_card())
	if not ids.has(_selected):
		_selected = first_ok if first_ok != "" else (ids[0] if not ids.is_empty() else "")
	var show_queue := filter == "furnace"
	queue_box.visible = show_queue
	list_scroll.custom_minimum_size.y = LIST_HEIGHT_WITH_QUEUE if show_queue else LIST_HEIGHT
	_refresh_status()


## The status of a recipe for this panel: furnace recipes ask the furnace queue, everything else Crafting.check.
func _check(rid: String) -> Dictionary:
	if Crafting.kind(rid) == "timed":
		if furnace_uid == "":
			var c := Crafting._check(rid, stations, sources, "", true)
			if bool(c["ok"]):
				return {"ok": false, "reason": "Needs a Furnace nearby.", "missing": {}}
			return c
		return Furnace.can_enqueue(furnace_uid, rid, sources)
	return Crafting.check(rid, stations, sources)


func _row_icon(rid: String, size: int = 96) -> Texture2D:
	var r := Crafting.recipe_def(rid)
	match Crafting.kind(rid):
		"apply":
			return IconFactory.icon("chest" if String(r.get("apply", "")) == "chest_40" else "ui_bag", Color.WHITE, size)
		"pattern":
			return IconFactory.icon("ribbon", Color("f28bb0"), size)
		"dye":
			var c: Variant = ItemDB.dye_palette(String(r.get("dye", ""))).get("tint", Color.WHITE)
			return IconFactory.icon("cloth", c if c is Color else Color.WHITE, size)
	return IconFactory.item_icon(String(r.get("result", "")), size)


func _make_row(rid: String) -> Button:
	var r := Crafting.recipe_def(rid)
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
	h.add_child(Kit.icon_rect(_row_icon(rid), 68))
	var v := Kit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var count := int(r.get("count", 1))
	var nm := Kit.label(Crafting.display_name(rid) + ("  x%d" % count if count > 1 else ""))
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


func _is_owned(rid: String) -> bool:
	var r := Crafting.recipe_def(rid)
	match Crafting.kind(rid):
		"pattern":
			return Crafting.owns_pattern(String(r.get("pattern", "")))
		"dye":
			return Crafting.owns_palette(String(r.get("dye", "")))
	return false


func _refresh_status() -> void:
	if not is_inside_tree():
		return
	for rid in _rows:
		var b: Button = _rows[rid]
		if not is_instance_valid(b):
			continue
		var chk: Dictionary = _check(String(rid))
		var st := b.find_child("Status", true, false) as TextureRect
		if st != null:
			if bool(chk.get("ok", false)):
				st.texture = IconFactory.icon("ui_check", Color.WHITE, 48)
			elif _is_owned(String(rid)):
				st.texture = IconFactory.icon("ui_star", Color.WHITE, 48)
			elif not stations.has(String(Crafting.recipe_def(String(rid)).get("station", "hand"))):
				st.texture = IconFactory.icon("ui_lock", Color.WHITE, 48)
			else:
				st.texture = null
		b.set_pressed_no_signal(String(rid) == _selected)
		b.modulate = Color.WHITE if bool(chk.get("ok", false)) else Color(1, 1, 1, 0.78)
	_show_detail()
	_refresh_queue()


func _kind_label(rid: String) -> String:
	match Crafting.kind(rid):
		"apply":
			return "UPGRADE"
		"pattern":
			return "CLOTHING PATTERN"
		"dye":
			return "DYE PALETTE"
		"timed":
			return "SMELTING"
	return UiUtil.category_name(ItemDB.category(String(Crafting.recipe_def(rid).get("result", "")))).to_upper()


func _action_text(rid: String) -> String:
	match Crafting.kind(rid):
		"timed":
			return "Add to queue"
		"apply":
			return "Upgrade"
		"pattern":
			return "Sew pattern"
		"dye":
			return "Mix dye"
	return "Craft"


func _show_detail() -> void:
	_clear(detail)
	if _selected == "":
		detail.add_child(Kit.wrap_label("Choose a recipe on the left.", "Muted", 600))
		craft_btn.disabled = true
		craft_btn.text = "Craft"
		return
	var r := Crafting.recipe_def(_selected)
	var k := Crafting.kind(_selected)
	var result := String(r.get("result", ""))
	var count := int(r.get("count", 1))
	var top := Kit.hbox(18)
	detail.add_child(top)
	top.add_child(Kit.icon_rect(_row_icon(_selected, 128), 120))
	var tv := Kit.vbox(2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var nl := Kit.wrap_label(Crafting.display_name(_selected), "Heading", 400)
	nl.add_theme_font_size_override("font_size", 36)
	tv.add_child(nl)
	var cat := Kit.label(_kind_label(_selected) + ("   ·   MAKES %d" % count if count > 1 and result != "" else ""), "Tiny")
	cat.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	tv.add_child(cat)
	match k:
		"item", "timed":
			tv.add_child(Kit.label("You have %d" % GameState.count_item(result), "Small"))
		"apply":
			tv.add_child(Kit.label("Backpack: %d slots" % int(GameState.inventory.size), "Small"))
		_:
			tv.add_child(Kit.label("Owned" if _is_owned(_selected) else "Not yet made", "Small"))
	var text := ItemDB.display_desc(result) if result != "" else ""
	var fx := Crafting.effect_text(_selected)
	if fx != "":
		text = fx if text == "" else text + " " + fx
	var desc := Kit.wrap_label(text, "", 640)
	desc.add_theme_font_size_override("font_size", 22)
	detail.add_child(desc)
	detail.add_child(section_title("Ingredients"))
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		var need := int(ings[id])
		var have := Crafting.count_available(String(id), sources)
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
	var from := _where_from_text(_selected)
	if from != "":
		detail.add_child(Kit.wrap_label(from, "Small", 640))
	var st := String(r.get("station", "hand"))
	var near := stations.has(st)
	var sl: Label
	if st == "hand":
		sl = Kit.label("Crafted by hand, anywhere.", "Small")
	else:
		sl = Kit.label(("Needs a %s  ·  nearby" if near else "Needs a %s  ·  not nearby") % ItemDB.station_name(st), "GoodText" if near else "BadText")
	detail.add_child(Kit.spacer(0, 4))
	detail.add_child(sl)
	var chk: Dictionary = _check(_selected)
	craft_btn.text = _action_text(_selected)
	craft_btn.disabled = not bool(chk.get("ok", false))
	craft_btn.tooltip_text = String(chk.get("reason", ""))


## "Taken from: your backpack (2 Wood) · Chest 1 (4 Wood)" when chests contribute ("" otherwise).
func _where_from_text(rid: String) -> String:
	if sources.is_empty():
		return ""
	var pl := Crafting.plan(rid, sources)
	var chests: Array = pl.get("chests", [])
	if chests.is_empty():
		return "Everything comes from your backpack."
	var bits: PackedStringArray = []
	var bag: Dictionary = pl.get("backpack", {})
	if not bag.is_empty():
		bits.append("your backpack (%s)" % Crafting.describe_items(bag))
	for c in chests:
		bits.append("%s (%s)" % [Crafting.chest_label(sources.find(String(c["uid"]))), Crafting.describe_items(c["items"])])
	return "Taken from: " + "  ·  ".join(bits)


# --- Furnace queue -----------------------------------------------------------------------------------------

func _on_station_queue_changed(uid: String) -> void:
	if uid == furnace_uid and is_inside_tree():
		_refresh_status()


func _refresh_queue() -> void:
	if queue_box == null or not queue_box.visible:
		return
	_clear(queue_box)
	var head := Kit.hbox(10)
	queue_box.add_child(head)
	head.add_child(section_title("Furnace queue"))
	if furnace_uid == "":
		queue_box.add_child(Kit.wrap_label("Stand near a placed Furnace to smelt. (Build one at a Workbench.)", "Muted", 620))
		return
	var p := Furnace.progress(furnace_uid)
	var jobs: Array = p["jobs"]
	head.add_child(Kit.expander())
	head.add_child(Kit.label("%d / %d" % [jobs.size(), int(p["capacity"])], "Small"))
	if jobs.is_empty():
		queue_box.add_child(Kit.wrap_label("Nothing smelting. Pick a recipe and press Add to queue.", "Muted", 620))
	for j in jobs:
		var row := Kit.hbox(10)
		row.add_child(Kit.icon_rect(IconFactory.item_icon(String(j["result"])), 36))
		var nm := Kit.label(ItemDB.display_name(String(j["result"])), "Small")
		nm.custom_minimum_size = Vector2(170, 0)
		row.add_child(nm)
		var pb := ProgressBar.new()
		pb.min_value = 0.0
		pb.max_value = 1.0
		pb.step = 0.001
		pb.value = float(j["fraction"])
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(260, 18)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pb)
		# a fixed-width status column, so every bar in the queue is the same length (visual QA UI-13)
		var st := Kit.label("%d s" % int(ceilf(float(j["remaining"]))) if bool(j["active"]) else "waiting", "Small", HORIZONTAL_ALIGNMENT_RIGHT)
		st.custom_minimum_size = Vector2(QUEUE_STATUS_W, 0)
		row.add_child(st)
		queue_box.add_child(row)
	var out: Dictionary = p["output"]
	var ready := Kit.hbox(12)
	queue_box.add_child(ready)
	var rl := Kit.label(("Ready: " + Crafting.describe_items(out)) if not out.is_empty() else "Nothing ready yet.", "GoodText" if not out.is_empty() else "Small")
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ready.add_child(rl)
	var cb := Kit.button("Collect", _collect)
	cb.disabled = out.is_empty()
	ready.add_child(cb)
	queue_box.add_child(Kit.label("Bars keep smelting while you play (menus pause it).", "Tiny"))


func _collect() -> void:
	if furnace_uid == "":
		return
	var n := Furnace.collect(furnace_uid)
	if n > 0:
		feedback_l.text = "Collected %d." % n
		feedback_l.theme_type_variation = "GoodText"
	else:
		Audio.play_ui("ui_error")
		feedback_l.text = Furnace.last_reason
		feedback_l.theme_type_variation = "BadText"
	_refresh_status()


# --- Festival table (kitchen) ------------------------------------------------------------------------------

func _table_card() -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(8)
	card.add_child(v)
	v.add_child(section_title("Festival table"))
	var cur := Crafting.table_decor()
	v.add_child(Kit.wrap_label("Dressed with %s." % String(Crafting.TABLE_DECOR[cur]).to_lower() if cur != "" else "Choose how to dress the table for the Lanternwake.", "Small", 560))
	var h := Kit.hbox(8)
	v.add_child(h)
	for id in Crafting.TABLE_DECOR_ORDER:
		var b := Kit.button(String(id).capitalize(), _decorate.bind(String(id)))
		b.toggle_mode = true
		b.set_pressed_no_signal(String(id) == cur)
		b.tooltip_text = String(Crafting.TABLE_DECOR[id])
		h.add_child(b)
	return card


func _decorate(choice: String) -> void:
	Crafting.decorate_table(choice)
	_build_list()


# --- Crafting ------------------------------------------------------------------------------------------------

func _craft() -> void:
	if _selected == "":
		return
	var rid := _selected
	var timed := Crafting.kind(rid) == "timed"
	var ok := false
	var reason := ""
	if timed:
		ok = furnace_uid != "" and Furnace.enqueue(furnace_uid, rid, sources)
		reason = Furnace.last_reason if furnace_uid != "" else "Needs a Furnace nearby."
	else:
		ok = Crafting.craft(rid, stations, sources)
		reason = Crafting.last_reason
	if ok:
		Audio.play_ui("ui_craft")
		feedback_l.text = ("Queued %s." if timed else "Made %s!") % Crafting.display_name(rid)
		feedback_l.theme_type_variation = "GoodText"
		var tw := Kit.retween(craft_btn, _tw2, "pop")
		craft_btn.pivot_offset = craft_btn.size * 0.5
		craft_btn.scale = Vector2(1.08, 1.08)
		tw.tween_property(craft_btn, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		Audio.play_ui("ui_error")
		feedback_l.text = reason if reason != "" else String(_check(rid).get("reason", "You can't make that right now."))
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
