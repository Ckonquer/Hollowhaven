extends "res://src/ui/panels/panel_base.gd"
## Backpack: GameState.inventory.size slots (the first row is the hotbar; 32 -> 40 -> 48 with upgrades),
## click-to-pick / click-to-place and drag-and-drop, right-click to split, shift-click to quick-move between
## hotbar and backpack, double-click to use. Detail card with name, description and stats (ItemDB), Use /
## Place / Equip buttons, a Sort button and the key-item pouch. The lantern shows an equipment note.
## Chapter Two (equipment module): an "Equipped" column with the four equipment slots (head / body / boots /
## charm) and a readable stats card (Stats.stat_rows: damage, protection %, speed %, healing, stamina,
## gathering, lantern, with their sources, plus the active companion's support).
##   * equip: drag a piece onto its slot, click the slot while carrying it, double-click it or press Equip
##   * take off: click / right-click the worn piece, or Take off; a full backpack refuses (nothing is lost)
## Everything goes through GameState.equip / unequip (transactional). Opening or using this menu never
## changes the selected hotbar slot and never touches the lantern.

const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")
const SlotController := preload("res://src/ui/widgets/slot_controller.gd")
const Stats := preload("res://src/core/stats.gd")

const SLOT := 92.0
const EQUIP_SLOT := 84.0
const EQUIP_SLOTS := ["head", "body", "boots", "charm"]
const EQUIP_NAMES := {"head": "Head", "body": "Body", "boots": "Boots", "charm": "Charm"}
const EQUIP_PLACEHOLDERS := {"head": "hood", "body": "vest", "boots": "armor_boots", "charm": "charm_leaf"}
const DETAIL_W := 440.0
const MID_W := 372.0

var ctl: Control
var slots: Array = []
var equip_slots: Dictionary = {}       # slot name -> ItemSlot
var detail_icon: TextureRect
var detail_name: Label
var detail_cat: Label
var detail_desc: Label
var detail_stats: VBoxContainer
var use_btn: Button
var detail_card: PanelContainer
var keys_box: HFlowContainer
var msg_l: Label
var stats_box: VBoxContainer
var companion_box: VBoxContainer
var _grid: GridContainer
var _detail_id := ""
var _detail_equip := ""                 # equipment slot shown in the detail card ("" = a backpack item)
var _selected_slot := -1


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Backpack"
	window_min = Vector2(1640, 0)


func _build() -> void:
	ctl = SlotController.new()
	add_child(ctl)
	ctl.quick_move = _quick_move
	ctl.use_item = func(s: Control) -> void: _use_slot(s.index)
	ctl.hovered_item.connect(_show_detail)
	var cols := Kit.hbox(30)
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
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	left.add_child(_grid)
	_grow_grid()
	left.add_child(Kit.spacer(0, 4))
	var help := Kit.wrap_label("Click to pick up and place  ·  Drag to move  ·  Right-click: take half\nShift-click: hotbar ↔ backpack  ·  Double-click: use or wear", "Small", 800)
	left.add_child(help)
	# --- equipment & stats column ---
	var mid := Kit.vbox(10)
	mid.custom_minimum_size.x = MID_W
	cols.add_child(mid)
	mid.add_child(section_title("Equipped"))
	var eq_row := Kit.hbox(8)
	mid.add_child(eq_row)
	for slot_name in EQUIP_SLOTS:
		eq_row.add_child(_make_equip_slot(String(slot_name)))
	var eq_help := Kit.wrap_label("Drag armor or a charm onto its slot. Click a worn piece to take it off. Clothes you pick in the wardrobe are separate: armor never changes your look unless you want it to.", "Small", MID_W)
	mid.add_child(eq_help)
	mid.add_child(section_title("Stats"))
	var card := Kit.panel("Card")
	card.custom_minimum_size.x = MID_W
	mid.add_child(card)
	var cv := Kit.vbox(6)
	card.add_child(cv)
	stats_box = Kit.vbox(4)
	cv.add_child(stats_box)
	companion_box = Kit.vbox(2)
	cv.add_child(companion_box)
	# --- detail column ---
	var right := Kit.vbox(14)
	right.custom_minimum_size.x = DETAIL_W
	cols.add_child(right)
	detail_card = Kit.panel("Card")
	detail_card.custom_minimum_size = Vector2(DETAIL_W, 360)
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
	detail_name = Kit.wrap_label("", "Subheading", 260)
	tv.add_child(detail_name)
	detail_cat = Kit.label("", "Tiny")
	detail_cat.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	tv.add_child(detail_cat)
	detail_desc = Kit.wrap_label("", "", DETAIL_W - 50.0)
	detail_desc.add_theme_font_size_override("font_size", 22)
	dv.add_child(detail_desc)
	detail_stats = Kit.vbox(2)
	dv.add_child(detail_stats)
	dv.add_child(Kit.expander())
	use_btn = Kit.button("Use", _on_use_pressed, "AccentButton")
	use_btn.visible = false
	dv.add_child(use_btn)
	msg_l = Kit.wrap_label("", "Small", DETAIL_W - 50.0)
	msg_l.visible = false
	right.add_child(msg_l)
	right.add_child(section_title("Key Items"))
	keys_box = HFlowContainer.new()
	keys_box.add_theme_constant_override("h_separation", 12)
	keys_box.add_theme_constant_override("v_separation", 8)
	keys_box.custom_minimum_size.x = DETAIL_W
	right.add_child(keys_box)
	Events.inventory_changed.connect(refresh)
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.capacity_changed.connect(_on_capacity_changed)
	Events.stats_changed.connect(_refresh_stats)


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
	# connected after the controller's own handler: a drag released over an equipment slot wears the piece
	s.released_slot.connect(_on_slot_released)
	return s


## Adds backpack slots up to GameState.inventory.size (capacity only ever grows; slots are never removed,
## the slot controller keeps references to them).
func _grow_grid() -> void:
	for i in range(GameState.HOTBAR_SIZE + _grid.get_child_count(), GameState.inventory.size):
		_grid.add_child(_make_slot(i, false))


func _make_equip_slot(slot_name: String) -> Control:
	var box := Kit.vbox(2)
	var s := ItemSlot.new(EQUIP_SLOT)
	s.index = -1
	s.inv = null
	s.placeholder_icon = String(EQUIP_PLACEHOLDERS.get(slot_name, ""))
	s.set_meta("equip_slot", slot_name)
	s.pressed_slot.connect(_on_equip_pressed.bind(slot_name))
	s.hovered.connect(func(_s: Control) -> void: _show_equipped(slot_name))
	box.add_child(s)
	var l := Kit.label(String(EQUIP_NAMES[slot_name]), "Tiny")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = EQUIP_SLOT
	box.add_child(l)
	equip_slots[slot_name] = s
	return box


func refresh() -> void:
	if _grid != null and slots.size() < GameState.inventory.size:
		_grow_grid()
	for s in slots:
		var c: Control = s
		c.set_stack(GameState.inventory.get_slot(c.index))
		var sel: bool = c.index == GameState.hotbar_index
		if c.selected != sel:
			c.selected = sel
			c.queue_redraw()
	for slot_name in equip_slots:
		var es: Control = equip_slots[slot_name]
		var id := GameState.equipped(String(slot_name))
		es.set_stack({"id": id, "count": 1} if id != "" and ItemDB.has_item(id) else null)
		es.tooltip_text = ItemDB.display_name(id) if id != "" and ItemDB.has_item(id) else "%s: nothing worn" % String(EQUIP_NAMES[slot_name])
	# key pouch
	for k in keys_box.get_children():
		k.queue_free()
	if GameState.key_items.is_empty():
		keys_box.add_child(Kit.wrap_label("Nothing yet. Special treasures you find are kept safe here.", "Small", DETAIL_W - 10.0))
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
	_refresh_stats()
	if _detail_equip != "":
		_show_equipped(_detail_equip)
	elif _detail_id == "" or GameState.count_item(_detail_id) <= 0:
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


## Rebuilds the stats card (Stats.stat_rows + companion lines). A handful of labels; only on changes.
func _refresh_stats() -> void:
	if stats_box == null:
		return
	for c in stats_box.get_children():
		c.queue_free()
	for c in companion_box.get_children():
		c.queue_free()
	for row in Stats.stat_rows():
		var r: Dictionary = row
		var h := Kit.hbox(8)
		var lab := Kit.label(String(r["label"]))
		lab.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		lab.custom_minimum_size.x = 130
		h.add_child(lab)
		var val := Kit.label(String(r["value"]))
		val.custom_minimum_size.x = 76
		h.add_child(val)
		var det := Kit.label(String(r.get("detail", "")), "Small")
		det.clip_text = true
		det.custom_minimum_size.x = 120
		det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		det.tooltip_text = String(r.get("detail", ""))
		det.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(det)
		h.set_meta("stat_id", String(r["id"]))
		stats_box.add_child(h)
	for line in Stats.companion_lines():
		companion_box.add_child(Kit.wrap_label(String(line), "Small", MID_W - 40.0))


func _show_detail(item_id: String) -> void:
	_detail_id = item_id
	_detail_equip = ""
	for c in detail_stats.get_children():
		c.queue_free()
	if item_id == "" or not ItemDB.has_item(item_id):
		detail_icon.texture = IconFactory.icon("ui_bag", Color.WHITE, 128)
		detail_name.text = "Your backpack"
		detail_cat.text = "%d FREE SLOTS" % GameState.inventory.free_slots()
		detail_desc.text = "Things you gather appear here. The top row is your hotbar: press 1 - 8 to hold an item."
		use_btn.visible = false
		return
	_fill_detail(item_id, "   ·   x%d" % GameState.count_item(item_id))
	var action := use_action(item_id)
	use_btn.visible = action != ""
	use_btn.text = action


## Detail card for a worn piece (hovered or clicked equipment slot).
func _show_equipped(slot_name: String) -> void:
	var id := GameState.equipped(slot_name)
	if id == "" or not ItemDB.has_item(id):
		_detail_equip = ""
		for c in detail_stats.get_children():
			c.queue_free()
		detail_icon.texture = IconFactory.icon(String(EQUIP_PLACEHOLDERS.get(slot_name, "ui_bag")), Color.WHITE, 128)
		detail_name.text = "%s slot" % String(EQUIP_NAMES.get(slot_name, slot_name))
		detail_cat.text = "NOTHING WORN"
		detail_desc.text = "Charms go in the charm slot; hoods, vests and boots go where you'd expect. Drag one here from the backpack." if slot_name == "charm" else "Drag a matching armor piece here from the backpack."
		use_btn.visible = false
		return
	_detail_id = id
	_detail_equip = slot_name
	for c in detail_stats.get_children():
		c.queue_free()
	_fill_detail(id, "   ·   WORN")
	use_btn.visible = true
	use_btn.text = "Take off"


func _fill_detail(item_id: String, suffix: String) -> void:
	detail_icon.texture = IconFactory.item_icon(item_id, 128)
	detail_name.text = ItemDB.display_name(item_id)
	detail_cat.text = UiUtil.category_name(ItemDB.category(item_id)).to_upper() + suffix
	detail_desc.text = ItemDB.display_desc(item_id)
	var lines: Array = UiUtil.item_stat_lines(item_id)
	lines.append_array(ItemSlot.equipment_stat_lines(item_id))
	for line in lines:
		var h := Kit.hbox(8)
		h.add_child(Kit.icon_rect(IconFactory.glyph("diamond", 18, 18, ThemeFactory.ACCENT), 14))
		var l := Kit.wrap_label(String(line), "Small", DETAIL_W - 90.0)
		l.add_theme_color_override("font_color", ThemeFactory.INK)
		h.add_child(l)
		detail_stats.add_child(h)


## Label for the Use button for an item ("" = none). Pure; see tests.
static func use_action(item_id: String) -> String:
	match ItemDB.category(item_id):
		"food":
			return "Eat"
		"placeable":
			return "Place in the Haven"
		"armor", "charm":
			return "Equip"
	return ""


func _on_use_pressed() -> void:
	if _detail_equip != "":
		unequip_slot(_detail_equip)
		return
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
		"wand":
			_say("Put the wand on your hotbar and select it: %s then casts a spark. Your usual weapon and tools still work as before." % Settings.action_label("attack"), false)
		"armor", "charm":
			equip_from_backpack(i)
		_:
			_say("That can't be used on its own, but it's handy for crafting.", false)


# --- Equipment -----------------------------------------------------------------------------------------------

## Wears the piece in backpack slot `i` (GameState.equip, transactional: whatever was worn goes back into
## that same slot when it empties). True on success; the reason is shown otherwise.
func equip_from_backpack(i: int) -> bool:
	var st: Variant = GameState.inventory.get_slot(i)
	if not (st is Dictionary):
		return false
	var id := String(st["id"])
	if GameState.equip_slot_for(id) == "":
		_say("%s can't be worn." % ItemDB.display_name(id), false)
		Audio.play_ui("ui_error", -4.0)
		return false
	if GameState.equip(id, i):
		_say("Now wearing: %s." % ItemDB.display_name(id), true)
		Audio.play_ui("ui_click")
		_detail_equip = ""
		refresh()
		return true
	_say(GameState.last_equip_error if GameState.last_equip_error != "" else "That can't be worn right now.", false)
	Audio.play_ui("ui_error", -4.0)
	return false


## Takes off whatever is worn in `slot_name` (GameState.unequip; refused with a message when the backpack is
## full - the piece stays worn, never lost). True on success.
func unequip_slot(slot_name: String) -> bool:
	var id := GameState.equipped(slot_name)
	if id == "":
		return false
	if GameState.unequip(slot_name):
		_say("Took off: %s. It's back in your backpack." % ItemDB.display_name(id), true)
		Audio.play_ui("ui_click")
		_detail_equip = ""
		refresh()
		return true
	_say(GameState.last_equip_error if GameState.last_equip_error != "" else "You can't take that off right now.", false)
	Audio.play_ui("ui_error", -4.0)
	return false


## Wears the stack the slot controller is carrying in `slot_name` (click or drag onto an equipment slot).
func equip_held(slot_name: String) -> bool:
	if ctl == null or not ctl.is_holding():
		return false
	var held: Dictionary = ctl.held
	if held.get("inv") != GameState.inventory:
		ctl.cancel()
		return false
	var id := String(held.get("id", ""))
	var from := int(held.get("i", -1))
	var want := GameState.equip_slot_for(id)
	if want == "":
		_say("%s can't be worn." % ItemDB.display_name(id), false)
		Audio.play_ui("ui_error", -4.0)
		return false
	if want != slot_name:
		_say("That goes in the %s slot." % String(EQUIP_NAMES.get(want, want)), false)
		Audio.play_ui("ui_error", -4.0)
		return false
	ctl.cancel()
	return equip_from_backpack(from)


func _on_equip_pressed(_sl: Control, button: int, _shift: bool, _double: bool, slot_name: String) -> void:
	if ctl.is_holding():
		if button == MOUSE_BUTTON_LEFT:
			equip_held(slot_name)
		return
	_show_equipped(slot_name)
	if GameState.equipped(slot_name) != "" and (button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT):
		unequip_slot(slot_name)


func _on_slot_released(_slot: Control, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or ctl == null or not ctl.is_holding():
		return
	var es := equip_slot_under_mouse()
	if es != null:
		equip_held(String(es.get_meta("equip_slot")))


func equip_slot_under_mouse() -> Control:
	for slot_name in equip_slots:
		var c: Control = equip_slots[slot_name]
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(c.get_global_mouse_position()):
			return c
	return null


func _on_equipment_changed(_slot: String, _item_id: String) -> void:
	refresh()


func _on_capacity_changed(kind: String, _size: int) -> void:
	if kind == "backpack":
		refresh()


# --- Eat / place ----------------------------------------------------------------------------------------------

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
		GameState.player["hp"] = minf(float(GameState.player.get("hp", 100.0)) + heal * Stats.heal_mult(), float(GameState.player.get("max_hp", 100.0)))
	if buff is Dictionary:
		Stats.apply_food_buff(id)
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
