extends "res://src/ui/panels/panel_base.gd"
## Controls overlay (F1): every current binding, grouped into Moving / Doing / Menus / Building, as key caps.

const GROUPS := [
	["Moving", [["move", "Move"], ["look", "Look around"], ["jump", "Jump"], ["sprint", "Sprint (hold)"], ["dodge", "Dodge roll"], ["zoom", "Zoom camera"]]],
	["Doing", [["attack", "Attack / gather"], ["interact", "Interact / pick up"], ["use_item", "Use / eat held item"], ["lantern", "Raise lantern"], ["companion_command", "Companion: follow / wait"], ["companion_skill", "Companion skill"], ["hotbar", "Choose hotbar slot"]]],
	["Menus", [["inventory", "Backpack"], ["craft", "Crafting"], ["wardrobe", "Wardrobe"], ["journal", "Journal"], ["map", "Map"], ["pause", "Pause"], ["help", "This help"], ["screenshot", "Screenshot"]]],
	["Building", [["build", "Build mode"], ["build_rotate", "Rotate piece"], ["build_dismantle", "Dismantle piece"], ["build_undo", "Undo last piece"], ["build_recolor", "Recolour piece"], ["build_variant", "Pumpkin face"]]],
]
## Screen columns, as GROUPS indices top to bottom (every group exactly once): Building sits under Moving so the
## three columns stay close in height and the window fits the 1080p canvas.
const COLUMNS := [[0, 3], [1], [2]]
## Settings.REBINDABLE covers most rows, not all (Esc, F1, F12, R, X and the hotbar keep their keys): "most", like
## docs/player/How to Play.txt.
const TIP := "Tip: most of these keys can be changed in Settings > Controls."

var _rebind: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Controls"
	window_min = Vector2(1560, 0)


func _build() -> void:
	var cols := Kit.hbox(36)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	for col in COLUMNS:
		var v := Kit.vbox(10)
		v.custom_minimum_size.x = 470
		cols.add_child(v)
		for gi in col:
			var g: Array = GROUPS[int(gi)]
			if v.get_child_count() > 0:
				v.add_child(Kit.spacer(0, 8))
			v.add_child(section_title(String(g[0])))
			for item in g[1]:
				v.add_child(_row(String(item[0]), String(item[1])))
	var bottom := Kit.hbox(16)
	body.add_child(bottom)
	var tip := Kit.label(TIP, "Small")
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
