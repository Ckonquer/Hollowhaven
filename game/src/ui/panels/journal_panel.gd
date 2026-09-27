extends "res://src/ui/panels/panel_base.gd"
## Journal: Goals (current step with story text, objectives and destination; completed goals and
## chapter progress), Lore (discovered notes, text looked up via src/world/below/lore.gd if present)
## and Friends (companion portraits, blurbs, bond hearts, favourite food, where they are).

const QuestsData := preload("res://data/quests.gd")

var tabs: TabContainer
var goals_box: HBoxContainer
var lore_list: VBoxContainer
var lore_page: VBoxContainer
var friends_box: HBoxContainer
var _lore_sel := ""


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Journal"
	window_min = Vector2(1520, 0)


func _build() -> void:
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1440, 700)
	body.add_child(tabs)
	goals_box = Kit.hbox(30)
	goals_box.name = "Goals"
	tabs.add_child(goals_box)
	var lore := Kit.hbox(24)
	lore.name = "Lore"
	tabs.add_child(lore)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, 600)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lore.add_child(sc)
	lore_list = Kit.vbox(8)
	lore_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lore_list)
	var page := Kit.panel("Card")
	page.custom_minimum_size = Vector2(900, 600)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore.add_child(page)
	var psc := ScrollContainer.new()
	psc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(psc)
	lore_page = Kit.vbox(12)
	lore_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	psc.add_child(lore_page)
	friends_box = Kit.hbox(24)
	friends_box.name = "Friends"
	friends_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_child(friends_box)
	var tab := String(args.get("tab", ""))
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i).to_lower() == tab:
			tabs.current_tab = i
	Events.objectives_changed.connect(_build_goals)


func refresh() -> void:
	_build_goals()
	_build_lore()
	_build_friends()


func handle_key(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_Q or k == KEY_PAGEUP:
			tabs.current_tab = posmod(tabs.current_tab - 1, tabs.get_tab_count())
			Audio.play_ui("ui_click")
			return true
		if k == KEY_PAGEDOWN or k == KEY_E:
			tabs.current_tab = posmod(tabs.current_tab + 1, tabs.get_tab_count())
			Audio.play_ui("ui_click")
			return true
	return false


# --- Goals -------------------------------------------------------------------------------------

func _build_goals() -> void:
	if not is_inside_tree():
		return
	for c in goals_box.get_children():
		c.queue_free()
	var q: RefCounted = GameState.quests
	var step: Dictionary = q.current_step()
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(820, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	goals_box.add_child(card)
	var v := Kit.vbox(10)
	card.add_child(v)
	if step.is_empty():
		v.add_child(Kit.label("Every goal is complete!", "Heading"))
		v.add_child(Kit.wrap_label("The Haven is yours to enjoy. Build, farm and spend time with your friends.", "", 760))
	else:
		var hdr := Kit.label("OPTIONAL GOALS" if bool(step.get("optional", false)) else "CURRENT GOAL", "Tiny")
		hdr.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
		v.add_child(hdr)
		v.add_child(Kit.label(String(q.step_string(step, "title")), "Heading"))
		var text := String(q.step_string(step, "text"))   # alt_text in arachnophobia mode
		var tl := Kit.wrap_label(text, "", 760)
		tl.add_theme_font_size_override("font_size", 25)
		v.add_child(tl)
		v.add_child(Kit.spacer(0, 6))
		for st in q.objective_status():
			var d: Dictionary = st
			var h := Kit.hbox(12)
			var done := bool(d["done"])
			h.add_child(Kit.icon_rect(IconFactory.icon("ui_check", Color.WHITE, 48) if done else IconFactory.glyph("radio_off", 38, 38), 34))
			var l := Kit.wrap_label(String(d["label"]), "", 560)
			l.add_theme_font_size_override("font_size", 24)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if done:
				l.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
			h.add_child(l)
			if int(d["target"]) > 1:
				h.add_child(Kit.label("%d / %d" % [int(d["progress"]), int(d["target"])], "GoodText" if done else "Small"))
			v.add_child(h)
		var place := UiUtil.landmark_name(String(step.get("target", "")))
		if place != "":
			v.add_child(Kit.spacer(0, 6))
			var ph := Kit.hbox(10)
			ph.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 48), 30))
			ph.add_child(Kit.label("Head to %s. It's marked on your map (%s)." % [place, Settings.action_label("map")], "Muted"))
			v.add_child(ph)
		var hint := String(q.step_string(step, "hint"))
		if hint != "":
			v.add_child(Kit.spacer(0, 6))
			var hr := Kit.rich("[color=#%s]Tip:[/color] %s" % [ThemeFactory.ACCENT.darkened(0.2).to_html(false), preload("res://src/ui/hud/hint_card.gd").format_hint(hint, Callable(UiUtil, "settings_label"))], 760)
			hr.add_theme_font_size_override("normal_font_size", 22)
			hr.add_theme_font_size_override("bold_font_size", 22)
			v.add_child(hr)
	# right column: chapter progress + completed list
	var right := Kit.vbox(12)
	right.custom_minimum_size.x = 520
	goals_box.add_child(right)
	right.add_child(Kit.label("Chapter One", "Subheading"))
	var sub := Kit.label("The Dimming Ward", "Muted")
	right.add_child(sub)
	var main_total := 0
	var main_done := 0
	for s in QuestsData.STEPS:
		if bool(s.get("optional", false)):
			continue
		main_total += 1
		if q.is_completed(String(s["id"])):
			main_done += 1
	var pb := ProgressBar.new()
	pb.max_value = main_total
	pb.value = main_done
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(500, 22)
	right.add_child(pb)
	right.add_child(Kit.label("%d of %d goals complete" % [main_done, main_total], "Small"))
	right.add_child(Kit.spacer(0, 6))
	right.add_child(section_title("Completed"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 380)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	var list := Kit.vbox(6)
	sc.add_child(list)
	var any := false
	for s2 in QuestsData.STEPS:
		if q.is_completed(String(s2["id"])):
			any = true
			var h2 := Kit.hbox(10)
			h2.add_child(Kit.icon_rect(IconFactory.icon("ui_check", Color.WHITE, 48), 26))
			h2.add_child(Kit.label(String(q.step_string(s2, "title"))))
			list.add_child(h2)
	if not any:
		list.add_child(Kit.wrap_label("Your story is just beginning.", "Muted", 480))


# --- Lore --------------------------------------------------------------------------------------

func _build_lore() -> void:
	for c in lore_list.get_children():
		c.queue_free()
	if GameState.lore.is_empty():
		lore_list.add_child(Kit.wrap_label("No pages yet.", "Muted", 400))
		_show_lore("")
		return
	var group := ButtonGroup.new()
	for id in GameState.lore:
		var entry := UiUtil.lore_entry(String(id))
		var b := Kit.button(String(entry["title"]), _show_lore.bind(String(id)), "TabLike")
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(410, 60)
		b.icon = IconFactory.icon("ui_quest", Color.WHITE, 48)
		b.expand_icon = false
		lore_list.add_child(b)
		if _lore_sel == "" or _lore_sel == String(id):
			_lore_sel = String(id)
			b.set_pressed_no_signal(true)
	_show_lore(_lore_sel)


func _show_lore(id: String) -> void:
	_lore_sel = id
	for c in lore_page.get_children():
		c.queue_free()
	if id == "":
		lore_page.add_child(Kit.label("Notes & Inscriptions", "Heading"))
		lore_page.add_child(Kit.wrap_label("Old notes, carvings and stories you discover will be copied here, so you can read them again by lantern light.", "", 820))
		return
	var e := UiUtil.lore_entry(id)
	lore_page.add_child(Kit.wrap_label(String(e["title"]), "Heading", 820))
	var t := Kit.wrap_label(String(e["text"]), "", 820)
	t.add_theme_font_size_override("font_size", 25)
	lore_page.add_child(t)


# --- Friends -----------------------------------------------------------------------------------

func _build_friends() -> void:
	for c in friends_box.get_children():
		c.queue_free()
	for id in ItemDB.creature_ids():
		friends_box.add_child(_friend_card(String(id)))


func _friend_card(id: String) -> Control:
	var c := ItemDB.creature(id)
	var met := GameState.is_befriended(id)
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(440, 600)
	var v := Kit.vbox(8)
	card.add_child(v)
	var port := Control.new()
	port.custom_minimum_size = Vector2(170, 170)
	port.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tex := IconFactory.portrait(id)
	port.draw.connect(func() -> void:
		var ctr := port.size * 0.5
		port.draw_circle(ctr, 82, ThemeFactory.PAPER_DARK, true, -1.0, true)
		port.draw_texture_rect(tex, Rect2(ctr - Vector2(78, 78), Vector2(156, 156)), false, Color.WHITE if met else Color(0.25, 0.2, 0.25, 0.85))
		port.draw_arc(ctr, 79, 0.0, TAU, 64, ThemeFactory.INK, 3.0, true))
	v.add_child(port)
	var name_l := Kit.label(String(c.get("name", id)) if met else "???", "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(name_l)
	var sp := Kit.label(String(c.get("species", "")).to_upper() if met else "NOT YET MET", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	sp.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	v.add_child(sp)
	if met:
		var hb := Kit.hearts(GameState.bond_level(id), 5, 32)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(hb)
		v.add_child(Kit.wrap_label(String(c.get("blurb", "")), "", 390, HORIZONTAL_ALIGNMENT_CENTER))
		var food := String(c.get("favorite_food", ""))
		if food != "":
			var fh := Kit.hbox(8)
			fh.alignment = BoxContainer.ALIGNMENT_CENTER
			fh.add_child(Kit.icon_rect(IconFactory.item_icon(food), 40))
			fh.add_child(Kit.label("Loves %s" % ItemDB.display_name(food), "Small"))
			v.add_child(fh)
		v.add_child(Kit.label(preload("res://src/ui/panels/companion_panel.gd").status_text(id), "Muted", HORIZONTAL_ALIGNMENT_CENTER))
	else:
		v.add_child(Kit.wrap_label(unmet_hint(id), "Muted", 390, HORIZONTAL_ALIGNMENT_CENTER))
	return card


static func unmet_hint(id: String) -> String:
	match id:
		"mochi":
			return "Something small keeps squeaking in the Berry Glade to the west."
		"pebble":
			return "A boulder at the quarry, across the stream, grumbles to itself."
		"lumi":
			return "At night, a little light flickers in the Moonlit Ruin to the north."
	return "Someone is waiting to be found."
