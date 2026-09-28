extends "res://src/ui/panels/panel_base.gd"
## Backpack: 32 slots (the first row is the hotbar), click-to-pick / click-to-place and drag-and-drop,
## right-click to split, shift-click to quick-move between hotbar and backpack, double-click to use.
## Detail card with name, description and stats (ItemDB), Use / Place buttons, a Sort button and the
## key-item pouch. The lantern shows an equipment note.

const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")
const SlotController := preload("res://src/ui/widgets/slot_controller.gd")

const SLOT := 92.0

var ctl: Control
var slots: Array = []
var detail_icon: TextureRect
var detail_name: Label
var detail_cat: Label
var detail_desc: Label
var detail_stats: VBoxContainer
var use_btn: Button
var detail_card: PanelContainer
var keys_box: HFlowContainer
var msg_l: Label
var _detail_id := ""
var _selected_slot := -1


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Backpack"
	window_min = Vector2(1480, 0)


func _build() -> void:
	ctl = SlotController.new()
	add_child(ctl)
	ctl.quick_move = _quick_move
	ctl.use_item = func(s: Control) -> void: _use_slot(s.index)
	ctl.hovered_item.connect(_show_detail)
	var cols := Kit.hbox(34)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	# --- grid column ---
	var left := Kit.vbox(8)
	cols.add_child(left)
	var hdr := Kit.hbox(10)
	left.add_child(hdr)
	hdr.add_child(section_title("Hotbar"))
	var hk := Kit.label("keys 1 - 8", "Small")
	hk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(hk)
	hdr.add_child(Kit.expander())
	var sort := Kit.button("Sort", _sort, "")
	sort.tooltip_text = "Tidy the backpack by type (the hotbar stays as it is)."
	hdr.add_child(sort)
	var hot := GridContainer.new()
	hot.columns = 8
	hot.add_theme_constant_override("h_separation", 10)
	left.add_child(hot)
	for i in GameState.HOTBAR_SIZE:
		hot.add_child(_make_slot(i, true))
	left.add_child(Kit.spacer(0, 6))
	left.add_child(section_title("Backpack"))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for i in range(GameState.HOTBAR_SIZE, GameState.INVENTORY_SIZE):
		grid.add_child(_make_slot(i, false))
	left.add_child(Kit.spacer(0, 4))
	var help := Kit.wrap_label("Click to pick up and place  ·  Drag to move  ·  Right-click: take half\nShift-click: hotbar ↔ backpack  ·  Double-click: use", "Small", 800)
	left.add_child(help)
	# --- detail column ---
	var right := Kit.vbox(14)
	right.custom_minimum_size.x = 470
	cols.add_child(right)
	detail_card = Kit.panel("Card")
	detail_card.custom_minimum_size = Vector2(470, 360)
	right.add_child(detail_card)
	var dv := Kit.vbox(8)
	detail_card.add_child(dv)
	var top := Kit.hbox(16)
	dv.add_child(top)
	detail_icon = Kit.icon_rect(null, 112)
	top.add_child(detail_icon)
	var tv := Kit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	detail_name = Kit.wrap_label("", "Subheading", 280)
	tv.add_child(detail_name)
	detail_cat = Kit.label("", "Tiny")
	detail_cat.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	tv.add_child(detail_cat)
	detail_desc = Kit.wrap_label("", "", 420)
	detail_desc.add_theme_font_size_override("font_size", 22)
	dv.add_child(detail_desc)
	detail_stats = Kit.vbox(2)
	dv.add_child(detail_stats)
	dv.add_child(Kit.expander())
	use_btn = Kit.button("Use", _on_use_pressed, "AccentButton")
	use_btn.visible = false
	dv.add_child(use_btn)
	msg_l = Kit.wrap_label("", "Small", 420)
	msg_l.visible = false
	right.add_child(msg_l)
	right.add_child(section_title("Key Items"))
	keys_box = HFlowContainer.new()
	keys_box.add_theme_constant_override("h_separation", 12)
	keys_box.add_theme_constant_override("v_separation", 8)
	keys_box.custom_minimum_size.x = 470
	right.add_child(keys_box)
	Events.inventory_changed.connect(refresh)


func _make_slot(i: int, hotbar: bool) -> Control:
	var s := ItemSlot.new(SLOT)
	s.index = i
	s.inv = GameState.inventory
	s.hotbar_row = hotbar
	s.key_number = i + 1 if hotbar else 0
	slots.append(s)
	ctl.register(s)
	s.pressed_slot.connect(func(sl: Control, button: int, _sh: bool, _d: bool) -> void:
		if button == MOUSE_BUTTON_LEFT and sl.stack != null:
			_selected_slot = sl.index
			_show_detail(String(sl.stack["id"])))
	return s


func refresh() -> void:
	for s in slots:
		var c: Control = s
		c.set_stack(GameState.inventory.get_slot(c.index))
		var sel: bool = c.index == GameState.hotbar_index
		if c.selected != sel:
			c.selected = sel
			c.queue_redraw()
	# key pouch
	for k in keys_box.get_children():
		k.queue_free()
	if GameState.key_items.is_empty():
		keys_box.add_child(Kit.wrap_label("Nothing yet. Special treasures you find are kept safe here.", "Small", 460))
	else:
		for id in GameState.key_items:
			var chip := Kit.panel("Card")
			chip.tooltip_text = ItemDB.display_desc(String(id))
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			var h := Kit.hbox(8)
			chip.add_child(h)
			h.add_child(Kit.icon_rect(IconFactory.item_icon(String(id)), 44))
			var nl := Kit.label(ItemDB.display_name(String(id)))
			nl.add_theme_font_override("font", ThemeFactory.font("body_bold"))
			nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(nl)
			keys_box.add_child(chip)
	if _detail_id == "" or GameState.count_item(_detail_id) <= 0:
		var first := ""
		var cur: Variant = GameState.inventory.get_slot(GameState.hotbar_index)
		if cur != null:
			first = String(cur["id"])
		else:
			for s2 in GameState.inventory.slots:
				if s2 != null:
					first = String(s2["id"])
					break
		_show_detail(first)
	else:
		_show_detail(_detail_id)


func _show_detail(item_id: String) -> void:
	_detail_id = item_id
	for c in detail_stats.get_children():
		c.queue_free()
	if item_id == "" or not ItemDB.has_item(item_id):
		detail_icon.texture = IconFactory.icon("ui_bag", Color.WHITE, 128)
		detail_name.text = "Your backpack"
		detail_cat.text = "%d FREE SLOTS" % GameState.inventory.free_slots()
		detail_desc.text = "Things you gather appear here. The top row is your hotbar: press 1 - 8 to hold an item."
		use_btn.visible = false
		return
	detail_icon.texture = IconFactory.item_icon(item_id, 128)
	detail_name.text = ItemDB.display_name(item_id)
	detail_cat.text = UiUtil.category_name(ItemDB.category(item_id)).to_upper() + "   ·   x%d" % GameState.count_item(item_id)
	detail_desc.text = ItemDB.display_desc(item_id)
	for line in UiUtil.item_stat_lines(item_id):
		var h := Kit.hbox(8)
		h.add_child(Kit.icon_rect(IconFactory.glyph("diamond", 18, 18, ThemeFactory.ACCENT), 14))
		var l := Kit.wrap_label(String(line), "Small", 380)
		l.add_theme_color_override("font_color", ThemeFactory.INK)
		h.add_child(l)
		detail_stats.add_child(h)
	var action := use_action(item_id)
	use_btn.visible = action != ""
	use_btn.text = action


## Label for the Use button for an item ("" = none). Pure; see tests.
static func use_action(item_id: String) -> String:
	match ItemDB.category(item_id):
		"food":
			return "Eat"
		"placeable":
			return "Place in the Haven"
	return ""


func _on_use_pressed() -> void:
	if _detail_id == "":
		return
	var idx := -1
	if _selected_slot >= 0:
		var st: Variant = GameState.inventory.get_slot(_selected_slot)
		if st != null and String(st["id"]) == _detail_id:
			idx = _selected_slot
	if idx < 0:
		for i in GameState.inventory.size:
			var st2: Variant = GameState.inventory.get_slot(i)
			if st2 != null and String(st2["id"]) == _detail_id:
				idx = i
				break
	if idx >= 0:
		_use_slot(idx)


func _use_slot(i: int) -> void:
	var st: Variant = GameState.inventory.get_slot(i)
	if st == null:
		return
	var id := String(st["id"])
	match ItemDB.category(id):
		"food":
			_eat(id)
		"placeable":
			_place(id)
		"seed":
			_say("Put the seeds on your hotbar, then press %s on a Crop Plot to plant them." % Settings.action_label("interact"), false)
		"tool", "weapon":
			_say("Tools and weapons are used automatically when you need them.", false)
		_:
			_say("That can't be used on its own, but it's handy for crafting.", false)


func _eat(id: String) -> void:
	var pl: Node = Game.player
	# Prefer the player's own eating logic (src/player/player.gd eat(id) -> bool; it gives its own feedback).
	if pl != null and is_instance_valid(pl) and pl.has_method("eat"):
		# The player's own "not hungry" toast sits under this menu, so explain it here.
		var hv0: Variant = pl.get("health")
		var buff0: Variant = ItemDB.item(id).get("buff", null)
		var has_buff: bool = buff0 is Dictionary and not (buff0 as Dictionary).is_empty()
		if hv0 is Node and float((hv0 as Node).get("hp")) >= float((hv0 as Node).get("max_hp")) - 0.01 and not has_buff:
			_say("Krystal is already at full health. Save it for when she's hurt.", false)
			Audio.play_ui("ui_error", -4.0)
			return
		var ok: Variant = pl.call("eat", id)
		if ok is bool and not ok:
			_say("Krystal can't eat that right now.", false)
			Audio.play_ui("ui_error", -4.0)
		else:
			# the player's own toast sits under the menu, so confirm it here too
			_say("Yum! Krystal enjoyed the %s." % ItemDB.display_name(id), true)
		return
	var heal := float(ItemDB.item(id).get("heal", 0.0))
	var h: Node = null
	if pl != null and is_instance_valid(pl):
		var hv: Variant = pl.get("health")
		if hv is Node:
			h = hv
	var buff: Variant = ItemDB.item(id).get("buff", null)
	if h != null and float(h.get("hp")) >= float(h.get("max_hp")) - 0.01 and not (buff is Dictionary):
		_say("Krystal is already at full health. Save it for when she's hurt.", false)
		Audio.play_ui("ui_error", -4.0)
		return
	if not GameState.take_item(id, 1):
		return
	if h != null and h.has_method("heal"):
		h.heal(heal)
		GameState.player["hp"] = float(h.get("hp"))
	else:
		GameState.player["hp"] = minf(float(GameState.player.get("hp", 100.0)) + heal, float(GameState.player.get("max_hp", 100.0)))
	if buff is Dictionary and (buff as Dictionary).has("stamina_regen"):
		GameState.add_buff("stamina_regen", float(buff["stamina_regen"]), float(buff.get("seconds", 60.0)))
	Events.item_consumed.emit(id)
	Events.player_healed.emit(heal)
	Audio.play_sfx("eat")
	_say("Yum! %s restored %d health." % [ItemDB.display_name(id), int(heal)], true)


func _place(id: String) -> void:
	if Game.area_id != "surface":
		_say("You can only build at the Haven, on the surface.", false)
		return
	for n in get_tree().get_nodes_in_group("build_mode"):
		if n.has_method("begin"):
			request_close()
			n.begin(id)
			return
	_say("Press %s near the Haven to start building." % Settings.action_label("build"), false)


func _quick_move(s: Control) -> void:
	UiUtil.quick_move_within(GameState.inventory, s.index, GameState.HOTBAR_SIZE)


func _sort() -> void:
	ctl.cancel()
	GameState.inventory.sort_items(true)
	Audio.play_ui("ui_click")


func _say(text: String, good: bool) -> void:
	msg_l.text = text
	msg_l.theme_type_variation = "GoodText" if good else "Small"
	msg_l.visible = true


func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed("pause") and ctl.is_holding():
		ctl.cancel()
		return true
	for i in GameState.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			GameState.select_hotbar(i)
			refresh()
			return true
	return false


func on_close() -> void:
	ctl.cancel()
