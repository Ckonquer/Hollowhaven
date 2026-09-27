extends "res://src/ui/panels/panel_base.gd"
## Small menu for a befriended companion (args {"id"}): Pet / Follow me / Wait here / Go home /
## Feed favourite food. Calls Game.companion_nodes[id].command(cmd). Not full-screen: the world keeps
## living around you while it's open.

var cid := ""
var first_btn: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	cid = String(p_args.get("id", ""))
	dim_background = false
	var c := ItemDB.creature(cid)
	title = String(c.get("name", cid.capitalize()))
	window_min = Vector2(620, 0)


func reopen(p_args: Dictionary) -> void:
	if String(p_args.get("id", cid)) != cid:
		request_close()


func _build() -> void:
	var c := ItemDB.creature(cid)
	var top := Kit.hbox(20)
	body.add_child(top)
	var port := Control.new()
	port.custom_minimum_size = Vector2(136, 136)
	var tex := IconFactory.portrait(cid)
	port.draw.connect(func() -> void:
		var ctr := port.size * 0.5
		port.draw_circle(ctr, 66, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
		port.draw_texture_rect(tex, Rect2(ctr - Vector2(62, 62), Vector2(124, 124)), false)
		port.draw_arc(ctr, 63, 0.0, TAU, 64, ThemeFactory.INK, 3.0, true))
	top.add_child(port)
	var v := Kit.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(v)
	var sp := Kit.label(String(c.get("species", "")).to_upper(), "Tiny")
	sp.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	v.add_child(sp)
	v.add_child(Kit.hearts(GameState.bond_level(cid), 5, 30))
	var status := Kit.label(status_text(cid), "Small")
	v.add_child(status)
	var blurb := Kit.wrap_label(String(c.get("blurb", "")), "", 300)
	blurb.add_theme_font_size_override("font_size", 21)
	v.add_child(blurb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	var rec := GameState.companion(cid)
	var assignment := String(rec.get("assignment", "home"))
	first_btn = _cmd_button(grid, "Pet", "pet", "AccentButton")
	if assignment == "follow":
		_cmd_button(grid, "Wait here", "wait")
	else:
		_cmd_button(grid, "Follow me", "follow")
	_cmd_button(grid, "Go home", "home")
	var food := String(c.get("favorite_food", ""))
	var have := GameState.count_item(food) if food != "" else 0
	var fb := _cmd_button(grid, "Feed %s (%d)" % [ItemDB.display_name(food), have] if food != "" else "Feed", "feed")
	if food != "":
		fb.icon = IconFactory.item_icon(food, 48)
	fb.disabled = have <= 0
	fb.tooltip_text = "" if have > 0 else "You don't have any %s." % ItemDB.display_name(food)


func _cmd_button(parent: Control, text: String, cmd: String, variation: String = "") -> Button:
	var b := Kit.button(text, _command.bind(cmd), variation)
	b.custom_minimum_size = Vector2(250, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


## "Following you" / "At the Haven" / ... for a companion id.
static func status_text(id: String) -> String:
	var rec := GameState.companion(id)
	if not bool(rec.get("befriended", false)):
		return "Not yet befriended"
	match String(rec.get("assignment", "home")):
		"follow":
			return "Following you"
		"wait":
			return "Waiting where you left them"
		"home":
			return "At home in the Haven"
	return ""


func _command(cmd: String) -> void:
	var node: Variant = Game.companion_nodes.get(cid, null)
	if node is Node and is_instance_valid(node) and (node as Node).has_method("command"):
		(node as Node).command(cmd)
	else:
		# Companion node missing (e.g. placeholder module): keep state consistent at least.
		match cmd:
			"follow", "home":
				GameState.set_companion_assignment(cid, cmd)
			"wait":
				var pos: Variant = Game.player.global_position if Game.player != null and is_instance_valid(Game.player) else null
				GameState.set_companion_assignment(cid, "wait", Game.area_id, pos)
	request_close()


func default_focus() -> Control:
	return first_btn
