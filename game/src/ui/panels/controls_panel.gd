extends "res://src/ui/panels/panel_base.gd"
## Controls overlay (F1): every current binding, grouped into Moving / Doing / Menus, as key caps.

const GROUPS := [
	["Moving", [["move", "Move"], ["look", "Look around"], ["jump", "Jump"], ["sprint", "Sprint (hold)"], ["dodge", "Dodge roll"], ["zoom", "Zoom camera"]]],
	["Doing", [["attack", "Attack / gather"], ["interact", "Interact / pick up"], ["use_item", "Use / eat held item"], ["lantern", "Raise lantern"], ["companion_command", "Companion: follow / wait"], ["companion_skill", "Companion skill"], ["hotbar", "Choose hotbar slot"]]],
	["Menus", [["inventory", "Backpack"], ["craft", "Crafting"], ["build", "Build mode"], ["build_rotate", "Rotate (building)"], ["build_dismantle", "Dismantle (building)"], ["journal", "Journal"], ["map", "Map"], ["pause", "Pause"], ["help", "This help"], ["screenshot", "Screenshot"]]],
]

var _rebind: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Controls"
	window_min = Vector2(1560, 0)


func _build() -> void:
	var cols := Kit.hbox(36)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	for g in GROUPS:
		var v := Kit.vbox(10)
		v.custom_minimum_size.x = 470
		cols.add_child(v)
		v.add_child(section_title(String(g[0])))
		for item in g[1]:
			v.add_child(_row(String(item[0]), String(item[1])))
	var bottom := Kit.hbox(16)
	body.add_child(bottom)
	var tip := Kit.label("Tip: everything here can be changed in Settings.", "Small")
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(tip)
	bottom.add_child(Kit.expander())
	_rebind = Kit.button("Change key bindings", _open_rebind)
	bottom.add_child(_rebind)
	bottom.add_child(Kit.button("Close", request_close, "AccentButton"))


func _row(action: String, label: String) -> Control:
	var h := Kit.hbox(12)
	var l := Kit.label(label)
	l.custom_minimum_size.x = 250
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", 22)
	h.add_child(l)
	var caps := Kit.hbox(6)
	caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(caps)
	match action:
		"move":
			for a in ["move_forward", "move_left", "move_back", "move_right"]:
				caps.add_child(Kit.key_cap(Settings.action_label(a)))
		"look":
			caps.add_child(Kit.key_cap("Mouse"))
		"zoom":
			caps.add_child(Kit.key_cap("Mouse Wheel"))
		"hotbar":
			caps.add_child(Kit.key_cap("%s - %s" % [Settings.action_label("hotbar_1"), Settings.action_label("hotbar_8")]))
		_:
			caps.add_child(Kit.action_caps(action, 2))
	return h


func _open_rebind() -> void:
	if ui_root != null:
		var r: Node = ui_root
		request_close()
		r.open("settings", {"tab": "controls"})


func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed("help"):
		request_close()
		return true
	return false


func default_focus() -> Control:
	return _rebind
