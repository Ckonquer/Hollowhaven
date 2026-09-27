extends "res://src/ui/panels/panel_base.gd"
## Map: the painted map of Hollowhaven Woods (surface only) with a side legend showing where the
## current goal leads. Underground it gently explains that the map can't help down there.

const MapView := preload("res://src/ui/widgets/map_view.gd")
const Layout := preload("res://data/world_layout.gd")
const Palette := preload("res://src/art/palette.gd")

var view: Control


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Hollowhaven Woods" if Game.area_id != "below" else "The Deep Places"
	window_min = Vector2(1400, 0) if Game.area_id != "below" else Vector2(900, 0)


func _build() -> void:
	if Game.area_id == "below":
		_build_below()
		return
	var cols := Kit.hbox(30)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	view = MapView.new()
	view.custom_minimum_size = Vector2(800, 800)
	cols.add_child(view)
	var side := Kit.vbox(12)
	side.custom_minimum_size.x = 460
	cols.add_child(side)
	var step: Dictionary = GameState.quests.current_step()
	var target := String(step.get("target", ""))
	view.target_id = target
	side.add_child(section_title("Where to?"))
	var goal_card := Kit.panel("Card")
	side.add_child(goal_card)
	var gv := Kit.vbox(4)
	goal_card.add_child(gv)
	gv.add_child(Kit.label(String(GameState.quests.step_string(step, "title")) if not step.is_empty() else "Free play", "CardTitle"))
	var place := UiUtil.landmark_name(target)
	if place != "":
		var h := Kit.hbox(8)
		h.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 48), 28))
		h.add_child(Kit.label("Head to %s" % place, "Muted"))
		gv.add_child(h)
		gv.add_child(Kit.wrap_label("It's circled on the map.", "Small", 400))
	else:
		gv.add_child(Kit.wrap_label("This goal doesn't need a map. Follow your journal.", "Small", 400))
	side.add_child(Kit.spacer(0, 4))
	side.add_child(section_title("Legend"))
	side.add_child(_legend_row(_arrow_icon(), "You (pointing where you look)"))
	side.add_child(_legend_row(IconFactory.icon("ui_star", Color.WHITE, 48), "Your current goal"))
	side.add_child(_legend_row(IconFactory.portrait("mochi"), "Your friends"))
	side.add_child(_legend_row(IconFactory.glyph("diamond", 40, 40, Palette.WOOD), "Bridges and stepping stones"))
	side.add_child(Kit.spacer(0, 4))
	side.add_child(section_title("Places"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	side.add_child(grid)
	for id in Layout.LANDMARKS:
		var h2 := Kit.hbox(6)
		h2.add_child(Kit.icon_rect(IconFactory.icon(String(MapView.ICONS.get(id, "unknown")), Color.WHITE, 48), 32))
		var l := Kit.label(String(Layout.LANDMARKS[id]["name"]), "Small")
		l.add_theme_color_override("font_color", ThemeFactory.INK)
		h2.add_child(l)
		grid.add_child(h2)


func _arrow_icon() -> Texture2D:
	return IconFactory.glyph("arrow_right", 40, 40, Palette.K_JACKET)


func _legend_row(tex: Texture2D, text: String) -> HBoxContainer:
	var h := Kit.hbox(10)
	h.add_child(Kit.icon_rect(tex, 34))
	var l := Kit.label(text, "Small")
	l.add_theme_color_override("font_color", ThemeFactory.INK)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


func _build_below() -> void:
	var v := Kit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(v)
	var ic := Kit.icon_rect(IconFactory.item_icon("lantern", 128), 150)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t := Kit.label("The map can't help you down here.", "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(t)
	var s := Kit.wrap_label("These tunnels were never drawn on any map. Trust your lantern, follow the lit paths, and remember the way back up.", "", 760, HORIZONTAL_ALIGNMENT_CENTER)
	s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	s.add_theme_font_size_override("font_size", 25)
	v.add_child(s)
	var step: Dictionary = GameState.quests.current_step()
	if not step.is_empty():
		var g := Kit.label("Current goal: %s" % String(GameState.quests.step_string(step, "title")), "Muted", HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(g)
