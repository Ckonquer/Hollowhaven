extends "res://src/ui/panels/panel_base.gd"
## Map, per area (MapView.map_kind):
##   surface            the painted map of Hollowhaven Woods (legacy layout; + the waygate pin in Chapter Two)
##   hallowmere_reach   the painted Reach: discovered districts only, Lantern Road arches, the waygate home
##   manor/works/annex  a simple list of the rooms found so far (you-are-here, safe rooms, the goal room)
##   below / echo_trial no map, a gentle message
## Every map marks the current objective's targets (Tracker.objective_view: the legacy step's landmark, each
## Chapter Two step target, the Haven for the Ward Stone pointer); a goal in another area points at the way
## there (the waygate, the manor door, the Bellhouse stair). Once the Reach has been visited, a toggle shows
## either outdoor map (Krystal and her friends are drawn only on the map of the area she is in).
## args: {"area": map area to show (optional; default = the area Krystal is in)}.

const MapView := preload("res://src/ui/widgets/map_view.gd")
const Tracker := preload("res://src/ui/hud/tracker.gd")
const Layout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Palette := preload("res://src/art/palette.gd")

const REACH_ID := "hallowmere_reach"

var view: Control                 # the MapView of the outdoor maps (null for room lists / no map)
var shown_area: String = ""       # area whose map is shown
var content: Control              # everything below the toggle (rebuilt by refresh)
var toggle_box: HBoxContainer
var places_grid: GridContainer    # the "Places" list of an outdoor map
var _here_area := ""              # area Krystal is in, mapped to a map area ("surface" for unknown areas)


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	_here_area = current_map_area()
	shown_area = String(p_args.get("area", _here_area))
	if MapView.map_kind(shown_area) == "surface" and shown_area != "surface":
		shown_area = "surface"
	title = map_title(shown_area)
	window_min = window_size_for(shown_area)


## The map area for where Krystal is: her area, or "surface" for unknown (debug) areas.
static func current_map_area() -> String:
	var a := Game.area_id
	if MapView.map_kind(a) == "surface":
		return "surface"
	return a


static func map_title(area_id: String) -> String:
	if area_id == "below":
		return "The Deep Places"
	var n := MapView.area_name(area_id)
	return n if n != "" else "Hollowhaven Woods"


static func window_size_for(area_id: String) -> Vector2:
	match MapView.map_kind(area_id):
		"reach":
			return Vector2(1500, 0)
		"rooms":
			return Vector2(1100, 0)
		"none":
			return Vector2(900, 0)
	return Vector2(1400, 0)


## True once both outdoor maps are worth switching between (the Reach has been visited).
static func can_toggle_outdoor() -> bool:
	return not GameState.discovered_in(REACH_ID).is_empty() or (true if GameState.get_flag("ch2_arch_commons") else false)


func _build() -> void:
	toggle_box = Kit.hbox(12)
	toggle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(toggle_box)
	content = Kit.vbox(0)
	body.add_child(content)


func refresh() -> void:
	for c in toggle_box.get_children():
		toggle_box.remove_child(c)
		c.queue_free()
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	view = null
	places_grid = null
	var outdoor := MapView.map_kind(shown_area) in ["surface", "reach"]
	toggle_box.visible = outdoor and can_toggle_outdoor()
	if toggle_box.visible:
		var group := ButtonGroup.new()
		for a in ["surface", REACH_ID]:
			var b := Kit.button(MapView.area_name(String(a)), _on_toggle.bind(String(a)), "TabLike")
			b.toggle_mode = true
			b.button_group = group
			b.custom_minimum_size = Vector2(300, 52)
			b.set_pressed_no_signal(a == shown_area)
			toggle_box.add_child(b)
	match MapView.map_kind(shown_area):
		"none":
			_build_none()
		"rooms":
			_build_rooms()
		_:
			_build_outdoor()


## Opened again while already open (ui_root.open): switch to a requested area's map, else refresh.
func reopen(p_args: Dictionary) -> void:
	args = p_args
	var want := String(p_args.get("area", shown_area))
	if MapView.map_kind(want) == "surface" and want != "surface":
		want = "surface"
	if want != shown_area:
		show_area(want)
	else:
		refresh()


func _on_toggle(area_id: String) -> void:
	show_area.call_deferred(area_id)   # never free the pressed button inside its own signal


## Switches the shown outdoor map (the toggle).
func show_area(area_id: String) -> void:
	if area_id == shown_area:
		return
	shown_area = area_id
	set_title(map_title(area_id))
	window_min = window_size_for(area_id)
	window.custom_minimum_size = window_min
	refresh()


# --- Where the objective points on the shown map ------------------------------------------------------------

## Map marks and card lines for the objective on `map_area`: {"title", "marks": [ids to pulse],
## "lines": [[icon id, text]], "view": objective view}. A target in another area is marked at the way there.
static func goal_marks(map_area: String) -> Dictionary:
	var vw := Tracker.objective_view()
	var out := {"title": "", "marks": [], "lines": [], "view": vw}
	var kind := String(vw["kind"])
	if kind == "hidden" or kind == "done":
		out["title"] = "Free play"
		return out
	out["title"] = String(vw["title"])
	var marks: Array = out["marks"]
	var lines: Array = out["lines"]
	var elsewhere := {}          # area -> [names] of targets in other areas (one line per area)
	for t in Tracker.pending_targets(vw):
		var id := String(t["id"])
		var area := String(t["area"])
		var name := String(t["name"])
		if area == map_area:
			if not marks.has(id):
				marks.append(id)
			lines.append(["ui_star", "Head to %s" % name if name != "" else "Marked on the map"])
			continue
		if not elsewhere.has(area):
			elsewhere[area] = []
		(elsewhere[area] as Array).append(name)
	for area in elsewhere:
		var names: Array = elsewhere[area]
		var via := way_to(String(area), map_area)
		if via != "" and not marks.has(via):
			marks.append(via)
		var an := MapView.area_name(String(area))
		if names.size() == 1 and String(names[0]) != "":
			lines.append(["ui_star", "Head to %s, in %s" % [String(names[0]), an]])
		else:
			lines.append(["ui_star", "Head to %s (%d places)" % [an, names.size()] if names.size() > 1 else "Head to %s" % an])
		var how := way_text(String(area), map_area)
		if how != "":
			lines.append(["ui_info", how])
	return out


## The place on `map_area`'s map that leads toward `target_area` ("" = none drawn there).
static func way_to(target_area: String, map_area: String) -> String:
	if map_area == "surface":
		if target_area == REACH_ID or target_area == "moonveil_manor" or target_area == "hushed_works":
			return MapView.WAYGATE_ID if MapView.surface_waygate_visible() else ""
		if target_area == "tobin_annex" or target_area == "below":
			return "mine_mouth"
	elif map_area == REACH_ID:
		if target_area == "surface" or target_area == "tobin_annex" or target_area == "below":
			return MapView.REACH_WAYGATE
		var e: Array = MapView.ENTRANCES.get(target_area, [])
		if e.size() == 2 and String(e[0]) == REACH_ID:
			return String(e[1])
	return ""


static func way_text(target_area: String, map_area: String) -> String:
	if map_area == "surface" and target_area in [REACH_ID, "moonveil_manor", "hushed_works"]:
		return "Through the Lanternwake waygate, north of the Moonlit Ruin."
	if map_area == REACH_ID and target_area == "surface":
		return "Back through the waygate, or the Lantern Road from any lit arch."
	if map_area == REACH_ID and target_area == "moonveil_manor":
		return "Through the manor door."
	if map_area == REACH_ID and target_area == "hushed_works":
		return "Down the stair at the Sunken Bellhouse."
	return ""


# --- Outdoor maps -------------------------------------------------------------------------------------------

func _build_outdoor() -> void:
	var reach := shown_area == REACH_ID
	var cols := Kit.hbox(30)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(cols)
	var goal := goal_marks(shown_area)
	view = MapView.new()
	view.map_area = shown_area
	view.target_ids = goal["marks"]
	view.show_player = shown_area == _here_area
	view.custom_minimum_size = Vector2(1000, 800) if reach else Vector2(800, 800)
	cols.add_child(view)
	var side := Kit.vbox(10 if reach else 12)
	side.custom_minimum_size.x = 460
	cols.add_child(side)
	side.add_child(section_title("Where to?"))
	side.add_child(_goal_card(goal))
	side.add_child(Kit.spacer(0, 4))
	side.add_child(section_title("Legend"))
	if reach:
		var lg := GridContainer.new()
		lg.columns = 2
		lg.add_theme_constant_override("h_separation", 14)
		lg.add_theme_constant_override("v_separation", 4)
		side.add_child(lg)
		lg.add_child(_legend_row(_arrow_icon(), "You"))
		lg.add_child(_legend_row(IconFactory.icon("ui_star", Color.WHITE, 48), "Your goal"))
		lg.add_child(_legend_row(IconFactory.portrait("mochi"), "Your friends"))
		lg.add_child(_legend_ctrl(_arch_swatch(true), "Lit lantern arch"))
		lg.add_child(_legend_ctrl(_arch_swatch(false), "Unlit arch"))
		lg.add_child(_legend_ctrl(_unknown_swatch(), "Not found yet"))
	else:
		side.add_child(_legend_row(_arrow_icon(), "You (pointing where you look)"))
		side.add_child(_legend_row(IconFactory.icon("ui_star", Color.WHITE, 48), "Your current goal"))
		side.add_child(_legend_row(IconFactory.portrait("mochi"), "Your friends"))
		side.add_child(_legend_row(IconFactory.glyph("diamond", 40, 40, Palette.WOOD), "Bridges and stepping stones"))
	side.add_child(Kit.spacer(0, 4))
	side.add_child(section_title("Places"))
	var grid := GridContainer.new()
	places_grid = grid
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	side.add_child(grid)
	for id in place_ids(shown_area):
		var h2 := Kit.hbox(6)
		h2.add_child(Kit.icon_rect(IconFactory.icon(MapView.place_icon(String(id), shown_area), Color.WHITE, 48), 32))
		var l := Kit.label(MapView.place_name(String(id), shown_area), "Small")
		l.add_theme_color_override("font_color", ThemeFactory.INK)
		h2.add_child(l)
		grid.add_child(h2)
	if reach:
		var total := Reach.LANDMARKS.size()
		var found := place_ids(REACH_ID).size()
		side.add_child(Kit.label("%d of %d places found" % [found, total] if found < total else "Every place found!", "Muted"))


## Landmark ids listed under "Places" (the Reach lists discovered ones only, in layout order).
static func place_ids(area_id: String) -> Array:
	var out: Array = []
	if area_id == REACH_ID:
		for id in Reach.LANDMARKS:
			if GameState.is_discovered(REACH_ID, String(id)):
				out.append(String(id))
		return out
	for id in Layout.LANDMARKS:
		out.append(String(id))
	return out


func _goal_card(goal: Dictionary) -> Control:
	var goal_card := Kit.panel("Card")
	var gv := Kit.vbox(4)
	goal_card.add_child(gv)
	gv.add_child(Kit.wrap_label(String(goal["title"]), "CardTitle", 400))
	var lines: Array = goal["lines"]
	if lines.is_empty():
		gv.add_child(Kit.wrap_label("This goal doesn't need a map. Follow your journal.", "Small", 400))
		return goal_card
	var marked := false
	for ln in lines:
		var h := Kit.hbox(8)
		h.add_child(Kit.icon_rect(IconFactory.icon(String(ln[0]), Color.WHITE, 48), 28))
		var l := Kit.wrap_label(String(ln[1]), "Muted", 360)
		h.add_child(l)
		gv.add_child(h)
	for m in goal["marks"]:
		marked = marked or m != ""
	if marked:
		gv.add_child(Kit.wrap_label("It's circled on the map.", "Small", 400))
	return goal_card


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


func _legend_ctrl(icon: Control, text: String) -> HBoxContainer:
	var h := Kit.hbox(10)
	h.add_child(icon)
	var l := Kit.label(text, "Small")
	l.add_theme_color_override("font_color", ThemeFactory.INK)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


func _arch_swatch(lit: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(34, 34)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: MapView.draw_arch_pin(c, c.size * 0.5 + Vector2(0, 2), 1.0, lit))
	return c


func _unknown_swatch() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(34, 34)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var ctr := c.size * 0.5
		c.draw_circle(ctr, 13.0, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
		c.draw_arc(ctr, 13.0, 0.0, TAU, 20, ThemeFactory.ACCENT.darkened(0.2), 2.5, true)
		var f := ThemeFactory.font("heading")
		c.draw_string(f, ctr + Vector2(-5, 7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ThemeFactory.INK))
	return c


# --- Interiors: a room list ------------------------------------------------------------------------------

## Rooms of `area_id` that belong on the list: [{id, name, safe, here, goal}] for discovered rooms (plus the
## room Krystal stands in, which the zone poll is about to discover), in route order.
static func room_rows(area_id: String, zone: String, goal_ids: Array) -> Array:
	var out: Array = []
	for r in MapView.rooms(area_id):
		var id := String(r["id"])
		var here := zone == id
		if not (GameState.is_discovered(area_id, id) or here):
			continue
		out.append({"id": id, "name": MapView.place_name(id, area_id), "safe": bool(r.get("safe", false)),
			"here": here, "goal": goal_ids.has(id)})
	return out


func _build_rooms() -> void:
	var cols := Kit.hbox(30)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(cols)
	var goal := goal_marks(shown_area)
	var zone := Game.zone_id if shown_area == _here_area else ""
	var rows := room_rows(shown_area, zone, goal["marks"])
	var left := Kit.panel("Card")
	left.custom_minimum_size = Vector2(560, 0)
	cols.add_child(left)
	var lv := Kit.vbox(8)
	left.add_child(lv)
	lv.add_child(section_title("Rooms you've found"))
	var total := MapView.rooms(shown_area).size()
	if rows.is_empty():
		lv.add_child(Kit.wrap_label("Nothing written down yet. Rooms appear here as you find them.", "Muted", 500))
	for r in rows:
		var h := Kit.hbox(10)
		var ic := "ui_star" if bool(r["goal"]) else ("ui_check" if not bool(r["here"]) else "ui_hint")
		h.add_child(Kit.icon_rect(IconFactory.icon(ic, Color.WHITE, 48), 30))
		var l := Kit.label(String(r["name"]), "Subheading" if bool(r["here"]) else "")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if bool(r["safe"]):
			var s := Kit.label("safe", "Tiny")
			s.add_theme_color_override("font_color", ThemeFactory.GOOD.darkened(0.25))
			h.add_child(s)
		if bool(r["here"]):
			var y := Kit.label("you are here", "Tiny")
			y.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
			h.add_child(y)
		lv.add_child(h)
	lv.add_child(Kit.spacer(0, 6))
	lv.add_child(Kit.label("%d of %d rooms found" % [rows.size(), total], "Muted"))
	var side := Kit.vbox(12)
	side.custom_minimum_size.x = 420
	cols.add_child(side)
	side.add_child(section_title("Where to?"))
	side.add_child(_goal_card(goal))
	side.add_child(Kit.wrap_label("No painted map reaches in here, so your journal keeps a list of the rooms instead. Safe rooms are marked.", "Small", 400))


# --- No map -----------------------------------------------------------------------------------------------

func _build_none() -> void:
	var v := Kit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(v)
	var ic := Kit.icon_rect(IconFactory.item_icon("lantern", 128), 150)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var trial := shown_area == "echo_trial"
	var t := Kit.label("Echoes don't keep maps." if trial else "The map can't help you down here.", "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(t)
	var msg := "This is a memory of a fight, not a place. When you leave, you'll be right back where you started." if trial \
		else "These tunnels were never drawn on any map. Trust your lantern, follow the lit paths, and remember the way back up."
	var s := Kit.wrap_label(msg, "", 760, HORIZONTAL_ALIGNMENT_CENTER)
	s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	s.add_theme_font_size_override("font_size", 25)
	v.add_child(s)
	var vw := Tracker.objective_view()
	var kind := String(vw["kind"])
	if kind != "hidden" and kind != "done" and String(vw["title"]) != "":
		var g := Kit.label("Current goal: %s" % String(vw["title"]), "Muted", HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(g)
