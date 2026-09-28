extends "res://src/ui/panels/panel_base.gd"
## Journal, five tabs (tab titles = child node names; args.tab picks one, "goals" is an alias of "story"):
##   Story     the current objective (Tracker.objective_view: legacy step / Ward Stone pointer / Chapter Two
##             step(s), the three lamps together) with its story text, objectives, destination and tip; a
##             right column with the progress and completed steps of Chapter One and (once available)
##             Chapter Two, the current chapter first.
##   Optional  the optional goals (data/optional_goals.gd through GameState.optional_goals), visible ones only,
##             grouped Chapter One / Chapter Two, with progress rows; the legacy free_play goals included.
##   Friends   companion cards (portrait, bond hearts, blurb, favourite food, where they are).
##   Lore      discovered notes of both chapters through LoreDB (arachnophobia-aware), grouped by chapter.
##   Mastery   the three mastery tracks: rank, XP to the next rank, every rank reward (reached ticked).
## Rebuilt on Events.objectives_changed / mastery_changed / lore_discovered, but only when the shown content
## actually changed (signatures), so the 1 s quest poll never rebuilds an unchanged page.

const QuestsData := preload("res://data/quests.gd")
const ChapterData := preload("res://data/quests_ch2.gd")
const Tracker := preload("res://src/ui/hud/tracker.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const HintCard := preload("res://src/ui/hud/hint_card.gd")

const TAB_ALIASES := {"goals": "story", "optional goals": "optional", "masteries": "mastery"}
const CH1_TITLE := "Chapter One"
const CH1_SUBTITLE := "The Dimming Ward"
const CH2_TITLE := "Chapter Two"
const CH2_SUBTITLE := "The Lanterns of Hallowmere"
const TRACK_ICONS := {"gathering": "axe", "hearthcraft": "workbench", "wayfinding": "lantern"}
const MASTERY_NOTE := "Masteries grow with ordinary play: gathering, crafting and exploring. No rank is ever needed for the story."

var tabs: TabContainer
var goals_box: HBoxContainer      # the Story tab
var optional_box: HBoxContainer
var lore_list: VBoxContainer
var lore_page: VBoxContainer
var friends_box: HBoxContainer
var mastery_box: VBoxContainer
var _lore_sel := ""
var _story_sig := ""
var _optional_sig := ""
var _mastery_sig := ""


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Journal"
	window_min = Vector2(1520, 0)


func _build() -> void:
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1440, 700)
	body.add_child(tabs)
	goals_box = Kit.hbox(30)
	goals_box.name = "Story"
	tabs.add_child(goals_box)
	optional_box = Kit.hbox(24)
	optional_box.name = "Optional"
	tabs.add_child(optional_box)
	friends_box = Kit.hbox(24)
	friends_box.name = "Friends"
	friends_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_child(friends_box)
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
	mastery_box = Kit.vbox(14)
	mastery_box.name = "Mastery"
	tabs.add_child(mastery_box)
	select_tab(String(args.get("tab", "")))
	Events.objectives_changed.connect(_on_objectives_changed)
	Events.mastery_changed.connect(_on_mastery_changed)
	Events.lore_discovered.connect(_on_lore_discovered)


## Selects a tab by its (lowercase) title or alias; unknown names keep the current tab. Returns success.
func select_tab(tab_name: String) -> bool:
	var want := tab_name.to_lower()
	want = String(TAB_ALIASES.get(want, want))
	if want == "":
		return false
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i).to_lower() == want:
			tabs.current_tab = i
			return true
	return false


## Opened again while already open (ui_root.open): honour a requested tab, then refresh.
func reopen(p_args: Dictionary) -> void:
	args = p_args
	select_tab(String(p_args.get("tab", "")))
	refresh()


## Lowercase titles of the tabs in order (tests).
func tab_names() -> Array:
	var out: Array = []
	for i in tabs.get_tab_count():
		out.append(tabs.get_tab_title(i).to_lower())
	return out


func refresh() -> void:
	_story_sig = ""
	_optional_sig = ""
	_mastery_sig = ""
	_build_goals()
	_build_optional()
	_build_lore()
	_build_friends()
	_build_mastery()


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


func _on_objectives_changed() -> void:
	_build_goals()
	_build_optional()


func _on_mastery_changed(_track: String, _xp: int, _rank: int) -> void:
	_build_mastery()


func _on_lore_discovered(_id: String) -> void:
	if is_inside_tree():
		_build_lore()


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- Story -------------------------------------------------------------------------------------------------

func _build_goals() -> void:
	if not is_inside_tree():
		return
	var vw := Tracker.objective_view()
	var sig := "%s|%s|%s|%s|%s" % [str(vw), str(GameState.quests.completed), str(GameState.chapter2.done), Game.area_id,
		Settings.action_label("map")]
	if sig == _story_sig:
		return
	_story_sig = sig
	_clear(goals_box)
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(820, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	goals_box.add_child(card)
	var csc := ScrollContainer.new()
	csc.custom_minimum_size = Vector2(770, 610)
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(csc)
	var v := Kit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csc.add_child(v)
	_current_card(v, vw)
	# right column: chapter progress + completed steps (current chapter first)
	var rsc := ScrollContainer.new()
	rsc.custom_minimum_size = Vector2(520, 660)
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	goals_box.add_child(rsc)
	var right := Kit.vbox(12)
	right.custom_minimum_size.x = 500
	rsc.add_child(right)
	if GameState.chapter2.is_available():
		_chapter_two_section(right)
		right.add_child(Kit.spacer(0, 10))
	_chapter_one_section(right)


func _current_card(v: VBoxContainer, vw: Dictionary) -> void:
	var kind := String(vw["kind"])
	if kind == "hidden" or kind == "done" or kind == "signpost":
		var finished: bool = GameState.chapter2.is_finished()
		v.add_child(Kit.label("The Lanternwake is complete!" if finished else "Every goal is complete!", "Heading"))
		var t := "Every lantern is lit and the Haven is yours. Build, farm, dress up and spend time with your friends. Optional goals and old roads are waiting whenever you like." if finished \
			else "The Haven is yours to enjoy. Build, farm and spend time with your friends."
		v.add_child(Kit.wrap_label(t, "", 760))
		if kind == "signpost":
			v.add_child(Kit.spacer(0, 6))
			v.add_child(Kit.label("Something to do: %s" % String(vw["title"]), "Muted"))
		return
	var hdr := Kit.label(String(vw["header"]), "Tiny")
	hdr.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
	v.add_child(hdr)
	v.add_child(Kit.wrap_label(String(vw["title"]), "Heading", 760))
	var tl := Kit.wrap_label(String(vw["text"]), "", 760)   # alt_text in arachnophobia mode
	tl.add_theme_font_size_override("font_size", 25)
	v.add_child(tl)
	v.add_child(Kit.spacer(0, 6))
	var parts: Array = vw["parts"]
	if String(vw["group"]) != "":
		for p in parts:
			var ph := Kit.hbox(10)
			var pd := bool(p["done"])
			ph.add_child(Kit.icon_rect(IconFactory.icon("ui_check" if pd else "ui_star", Color.WHITE, 48), 30))
			var pt := Kit.label(String(p["title"]), "Subheading")
			if pd:
				pt.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
			ph.add_child(pt)
			var place := MapView.place_name(String(p["target"]), String(p["area"]))
			if place != "":
				var pl := Kit.label("·  " + place, "Muted")
				ph.add_child(pl)
			v.add_child(ph)
			if not pd:
				var st := Kit.wrap_label(String(p["text"]), "Small", 720)
				v.add_child(st)
			for row in p["rows"]:
				v.add_child(_objective_row(row, 520))
			v.add_child(Kit.spacer(0, 4))
	else:
		for row in vw["rows"]:
			v.add_child(_objective_row(row, 560))
	var where := journal_where(vw, Game.area_id)
	if where != "":
		v.add_child(Kit.spacer(0, 6))
		var wh := Kit.hbox(10)
		wh.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 48), 30))
		wh.add_child(Kit.wrap_label(where, "Muted", 700))
		v.add_child(wh)
	var hint := String(vw["hint"])
	if hint != "":
		v.add_child(Kit.spacer(0, 6))
		var hr := Kit.rich("[color=#%s]Tip:[/color] %s" % [ThemeFactory.ACCENT.darkened(0.2).to_html(false), HintCard.format_hint(hint, Callable(UiUtil, "settings_label"))], 760)
		hr.add_theme_font_size_override("normal_font_size", 22)
		hr.add_theme_font_size_override("bold_font_size", 22)
		v.add_child(hr)


func _objective_row(d: Dictionary, width: float) -> HBoxContainer:
	var h := Kit.hbox(12)
	var done := bool(d["done"])
	h.add_child(Kit.icon_rect(IconFactory.icon("ui_check", Color.WHITE, 48) if done else IconFactory.glyph("radio_off", 38, 38), 34))
	var l := Kit.wrap_label(String(d["label"]), "", width)
	l.add_theme_font_size_override("font_size", 24)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if done:
		l.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
	h.add_child(l)
	if int(d["target"]) > 1:
		h.add_child(Kit.label("%d / %d" % [int(d["progress"]), int(d["target"])], "GoodText" if done else "Small"))
	return h


## The journal's "where to" sentence for a view ("" = none). Legacy wording is unchanged.
static func journal_where(vw: Dictionary, area_id: String) -> String:
	var key := Settings.action_label("map")
	match String(vw.get("kind", "")):
		"legacy":
			var lt := Tracker.pending_targets(vw)
			if lt.is_empty() or String(lt[0]["name"]) == "":
				return ""
			return "Head to %s. It's marked on your map (%s)." % [String(lt[0]["name"]), key]
		"pointer":
			return "The Ward Stone stands in the middle of Krystal's Haven."
		"chapter2":
			var pt := Tracker.pending_targets(vw)
			if pt.is_empty():
				return ""
			if pt.size() > 1:
				return "Each one is marked on your map of %s (%s)." % [MapView.area_name(String(pt[0]["area"])), key]
			var t: Dictionary = pt[0]
			var name := String(t["name"])
			var area := String(t["area"])
			var kind := MapView.map_kind(area)
			if name == "":
				return "It's somewhere in %s." % MapView.area_name(area) if MapView.area_name(area) != "" else ""
			if area == area_id:
				if kind == "rooms":
					return "Head to %s. Your map lists the rooms you've found (%s)." % [name, key]
				return "Head to %s. It's marked on your map (%s)." % [name, key]
			if kind == "surface" or kind == "reach":
				return "Head to %s, in %s. It's marked on your map (%s)." % [name, MapView.area_name(area), key]
			return "Head to %s, in %s." % [name, MapView.area_name(area)]
	return ""


func _chapter_one_section(right: VBoxContainer) -> void:
	var q: RefCounted = GameState.quests
	right.add_child(Kit.label(CH1_TITLE, "Subheading"))
	right.add_child(Kit.label(CH1_SUBTITLE, "Muted"))
	var main_total := 0
	var main_done := 0
	for s in QuestsData.STEPS:
		if bool(s.get("optional", false)):
			continue
		main_total += 1
		if q.is_completed(String(s["id"])):
			main_done += 1
	right.add_child(_progress_bar(main_done, main_total))
	right.add_child(Kit.label("%d of %d goals complete" % [main_done, main_total], "Small"))
	right.add_child(Kit.spacer(0, 6))
	right.add_child(section_title("Completed"))
	var list := Kit.vbox(6)
	right.add_child(list)
	var any := false
	for s2 in QuestsData.STEPS:
		if q.is_completed(String(s2["id"])):
			any = true
			list.add_child(_done_row(String(q.step_string(s2, "title"))))
	if not any:
		list.add_child(Kit.wrap_label("Your story is just beginning.", "Muted", 480))


func _chapter_two_section(right: VBoxContainer) -> void:
	var log: RefCounted = GameState.chapter2
	right.add_child(Kit.label(CH2_TITLE, "Subheading"))
	right.add_child(Kit.label(CH2_SUBTITLE, "Muted"))
	if not log.is_active():
		right.add_child(Kit.wrap_label("Not begun yet. The Ward Stone has something new to say.", "Small", 480))
		return
	var total: int = ChapterData.STEPS.size()
	var done := 0
	for s in ChapterData.STEPS:
		if log.is_done(String(s["id"])):
			done += 1
	right.add_child(_progress_bar(done, total))
	right.add_child(Kit.label("%d of %d goals complete" % [done, total], "Small"))
	right.add_child(Kit.spacer(0, 6))
	right.add_child(section_title("Completed"))
	var list := Kit.vbox(6)
	right.add_child(list)
	var any := false
	for s2 in ChapterData.STEPS:
		if log.is_done(String(s2["id"])):
			any = true
			list.add_child(_done_row(String(log.step_string(s2, "title"))))
	if not any:
		list.add_child(Kit.wrap_label("A new road is just beginning.", "Muted", 480))


func _progress_bar(value: int, total: int) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maxi(total, 1)
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(480, 22)
	return pb


func _done_row(text: String) -> HBoxContainer:
	var h2 := Kit.hbox(10)
	h2.add_child(Kit.icon_rect(IconFactory.icon("ui_check", Color.WHITE, 48), 26))
	h2.add_child(Kit.label(text))
	return h2


# --- Optional ---------------------------------------------------------------------------------------------

## Visible optional goals of a chapter, pending first then done (each in data order):
## [{id, title, text, done, legacy, rows}] with arachnophobia-aware text.
static func optional_entries(chapter: int) -> Array:
	var og: RefCounted = GameState.optional_goals
	var pending: Array = []
	var done: Array = []
	for g in og.visible_goals():
		if int(g.get("chapter", 1)) != chapter:
			continue
		var id := String(g["id"])
		var e := {"id": id, "title": String(og.step_string(g, "title")), "text": String(og.step_string(g, "text")),
			"done": og.is_done(id), "legacy": bool(g.get("legacy", false)), "rows": og.objective_status(g)}
		if e["done"]:
			done.append(e)
		else:
			pending.append(e)
	pending.append_array(done)
	return pending


func _build_optional() -> void:
	if not is_inside_tree():
		return
	var ch1 := optional_entries(1)
	var ch2 := optional_entries(2)
	var sig := str(ch1) + "|" + str(ch2)
	if sig == _optional_sig:
		return
	_optional_sig = sig
	_clear(optional_box)
	optional_box.add_child(_optional_column(CH1_TITLE, "Around the Haven and the woods", ch1))
	if not ch2.is_empty():
		optional_box.add_child(_optional_column(CH2_TITLE, "Hallowmere and the festival", ch2))
	else:
		var col := Kit.vbox(10)
		col.custom_minimum_size = Vector2(690, 0)
		col.add_child(Kit.label(CH2_TITLE if GameState.chapter2.is_available() else "Later", "Subheading"))
		col.add_child(Kit.wrap_label("More optional goals will appear as your journey continues. None of them are ever required.", "Muted", 660))
		optional_box.add_child(col)


func _optional_column(heading: String, sub: String, entries: Array) -> Control:
	var col := Kit.vbox(8)
	col.custom_minimum_size = Vector2(690, 0)
	var hh := Kit.hbox(12)
	hh.add_child(Kit.label(heading, "Subheading"))
	var n_done := 0
	for e in entries:
		if bool(e["done"]):
			n_done += 1
	var cnt := Kit.label("%d of %d done" % [n_done, entries.size()], "Small")
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(cnt)
	col.add_child(hh)
	col.add_child(Kit.label(sub, "Muted"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(690, 580)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var list := Kit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if entries.is_empty():
		list.add_child(Kit.wrap_label("Nothing here yet.", "Muted", 640))
	for e in entries:
		list.add_child(_goal_card(e))
	return col


func _goal_card(e: Dictionary) -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	card.add_child(v)
	var done := bool(e["done"])
	var h := Kit.hbox(10)
	h.add_child(Kit.icon_rect(IconFactory.icon("ui_check" if done else "ui_star", Color.WHITE, 48), 30))
	var t := Kit.label(String(e["title"]), "CardTitle")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var tag := Kit.label("Done" if done else "Optional", "GoodText" if done else "Tiny")
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	v.add_child(h)
	if not done:
		v.add_child(Kit.wrap_label(String(e["text"]), "Small", 620))
	for row in e["rows"]:
		var r: Dictionary = row
		var rh := Kit.hbox(10)
		var rd := bool(r["done"])
		rh.add_child(Kit.icon_rect(IconFactory.icon("ui_check", Color.WHITE, 48) if rd else IconFactory.glyph("radio_off", 38, 38), 26))
		var rl := Kit.wrap_label(String(r["label"]), "Small", 480)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if rd:
			rl.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
		rh.add_child(rl)
		if int(r["target"]) > 1:
			rh.add_child(Kit.label("%d / %d" % [int(r["progress"]), int(r["target"])], "GoodText" if rd else "Small"))
		v.add_child(rh)
	if bool(e["legacy"]):
		var lg := Kit.label("From Chapter One's free play", "Tiny")
		lg.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
		v.add_child(lg)
	return card


# --- Lore --------------------------------------------------------------------------------------------------

## Title and text of a note (LoreDB covers legacy + Chapter Two, arachnophobia-aware; unknown ids fall back
## to the legacy lookup's placeholder).
static func lore_entry(id: String) -> Dictionary:
	var e: Dictionary = LoreDB.get_lore(id)
	if String(e.get("title", "")).strip_edges() == "":
		return UiUtil.lore_entry(id)
	return e


## Discovered lore ids in journal order: LoreDB order (legacy first, then each Chapter Two file), then any
## discovered id no lore file knows (kept, shown with the placeholder); Chapter One notes before Chapter Two ones
## (stable), so each chapter heading appears once.
static func lore_ids() -> Array:
	var out: Array = []
	for id in LoreDB.ids():
		if GameState.lore.has(id):
			out.append(String(id))
	for id in GameState.lore:
		if not out.has(String(id)):
			out.append(String(id))
	var ch1: Array = []
	var ch2: Array = []
	for id in out:
		if lore_chapter(String(id)) == 2:
			ch2.append(id)
		else:
			ch1.append(id)
	return ch1 + ch2


## Chapter a note is filed under (LoreDB.chapter_of: by its source file, so Tobin's annex notes - Chapter One
## optional content - sit under Chapter One although their ids start with lore_ch2_).
static func lore_chapter(id: String) -> int:
	return LoreDB.chapter_of(id)


func _build_lore() -> void:
	_clear(lore_list)
	var ids := lore_ids()
	if ids.is_empty():
		lore_list.add_child(Kit.wrap_label("No pages yet.", "Muted", 400))
		_show_lore("")
		return
	if not ids.has(_lore_sel):
		_lore_sel = ""
	var both := false
	for id in ids:
		if lore_chapter(String(id)) == 2:
			both = true
	var group := ButtonGroup.new()
	var last_ch := 0
	for id in ids:
		var ch := lore_chapter(String(id))
		if both and ch != last_ch:
			last_ch = ch
			var gl := Kit.label(CH1_TITLE if ch == 1 else CH2_TITLE, "Tiny")
			gl.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
			lore_list.add_child(gl)
		var entry := lore_entry(String(id))
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
	_clear(lore_page)
	if id == "":
		lore_page.add_child(Kit.label("Notes & Inscriptions", "Heading"))
		lore_page.add_child(Kit.wrap_label("Old notes, carvings and stories you discover will be copied here, so you can read them again by lantern light.", "", 820))
		return
	var e := lore_entry(id)
	lore_page.add_child(Kit.wrap_label(String(e["title"]), "Heading", 820))
	var t := Kit.wrap_label(String(e["text"]), "", 820)
	t.add_theme_font_size_override("font_size", 25)
	lore_page.add_child(t)


# --- Friends -----------------------------------------------------------------------------------------------

func _build_friends() -> void:
	_clear(friends_box)
	var ids: Array = ItemDB.creature_ids()
	var w := friend_card_width(ids.size())
	for id in ids:
		friends_box.add_child(_friend_card(String(id), w))


## Card width for n friends: 440 for up to three, narrower so a fourth friend still fits the 1440 tab.
static func friend_card_width(n: int) -> float:
	if n <= 3:
		return 440.0
	return floorf((1440.0 - 24.0 * float(n - 1)) / float(n))


func _friend_card(id: String, w: float = 440.0) -> Control:
	var c := ItemDB.creature(id)
	var met := GameState.is_befriended(id)
	var inner := w - 50.0
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(w, 600)
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
		v.add_child(Kit.wrap_label(String(c.get("blurb", "")), "", inner, HORIZONTAL_ALIGNMENT_CENTER))
		var food := String(c.get("favorite_food", ""))
		if food != "":
			var fh := Kit.hbox(8)
			fh.alignment = BoxContainer.ALIGNMENT_CENTER
			fh.add_child(Kit.icon_rect(IconFactory.item_icon(food), 40))
			fh.add_child(Kit.label("Loves %s" % ItemDB.display_name(food), "Small"))
			v.add_child(fh)
		v.add_child(Kit.label(preload("res://src/ui/panels/companion_panel.gd").status_text(id), "Muted", HORIZONTAL_ALIGNMENT_CENTER))
	else:
		v.add_child(Kit.wrap_label(unmet_hint(id), "Muted", inner, HORIZONTAL_ALIGNMENT_CENTER))
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


# --- Mastery -----------------------------------------------------------------------------------------------

## Display data of one mastery track: {"track", "name", "desc", "xp", "rank", "max_rank", "floor_xp",
## "next_xp" (-1 at max rank), "rewards": [{"rank", "text", "reached", "next"}]}. Numbers from data/mastery.gd
## through ItemDB; a damaged saved value reads as 0.
static func mastery_info(track: String) -> Dictionary:
	var tables: Dictionary = ItemDB.mastery_tables()
	var rank_xp: Array = tables["rank_xp"]
	var max_rank := int(tables["max_rank"])
	var raw: Variant = GameState.mastery.get(track, 0) if GameState.mastery is Dictionary else 0
	var xp := 0
	if raw is int or (raw is float and is_finite(raw)):
		xp = maxi(int(raw), 0)
	var rank: int = ItemDB.mastery_rank_for_xp(xp)
	var names: Dictionary = ItemDB.mastery_track_info(track)
	var rewards: Array = []
	for r in range(1, max_rank + 1):
		var rw: Dictionary = ItemDB.mastery_reward(track, r)
		rewards.append({"rank": r, "text": String(rw.get("text", "")), "reached": r <= rank, "next": r == rank + 1})
	return {"track": track, "name": String(names["name"]), "desc": String(names["desc"]),
		"xp": xp, "rank": rank, "max_rank": max_rank, "floor_xp": int(rank_xp[mini(rank, rank_xp.size() - 1)]),
		"next_xp": int(rank_xp[rank + 1]) if rank < max_rank and rank + 1 < rank_xp.size() else -1, "rewards": rewards}


func _build_mastery() -> void:
	if not is_inside_tree():
		return
	var infos: Array = []
	for track in ItemDB.mastery_tracks():
		infos.append(mastery_info(String(track)))
	var sig := str(infos)
	if sig == _mastery_sig:
		return
	_mastery_sig = sig
	_clear(mastery_box)
	var row := Kit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	mastery_box.add_child(row)
	for info in infos:
		row.add_child(_mastery_card(info))
	var note := Kit.wrap_label(MASTERY_NOTE, "Muted", 1300, HORIZONTAL_ALIGNMENT_CENTER)
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mastery_box.add_child(note)


func _mastery_card(info: Dictionary) -> Control:
	var card := Kit.panel("Card")
	card.custom_minimum_size = Vector2(450, 600)
	var v := Kit.vbox(8)
	card.add_child(v)
	var head := Kit.hbox(12)
	head.add_child(Kit.icon_rect(IconFactory.icon(String(TRACK_ICONS.get(info["track"], "lantern")), Color.WHITE, 96), 56))
	var hv := Kit.vbox(0)
	hv.add_child(Kit.label(String(info["name"]), "Heading"))
	var rank := int(info["rank"])
	var max_rank := int(info["max_rank"])
	hv.add_child(Kit.label("Rank %d of %d" % [rank, max_rank], "Small"))
	head.add_child(hv)
	v.add_child(head)
	v.add_child(Kit.wrap_label(String(info["desc"]), "Small", 390))
	var stars := Kit.hbox(4)
	for i in max_rank:
		var s := Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 48), 30)
		if i >= rank:
			s.modulate = Color(0.45, 0.4, 0.45, 0.45)
		stars.add_child(s)
	v.add_child(stars)
	var next_xp := int(info["next_xp"])
	if next_xp > 0:
		var pb := ProgressBar.new()
		pb.min_value = int(info["floor_xp"])
		pb.max_value = next_xp
		pb.value = int(info["xp"])
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(390, 20)
		v.add_child(pb)
		v.add_child(Kit.label("%d / %d XP to rank %d" % [int(info["xp"]), next_xp, rank + 1], "Small"))
	else:
		v.add_child(Kit.label("Mastered! Every reward is yours.", "GoodText"))
	v.add_child(Kit.spacer(0, 4))
	v.add_child(Kit.label("REWARDS", "Tiny"))
	for rw in info["rewards"]:
		var rh := Kit.hbox(8)
		var reached := bool(rw["reached"])
		var nxt := bool(rw["next"])
		var ic := "ui_check" if reached else ("ui_star" if nxt else "ui_lock")
		rh.add_child(Kit.icon_rect(IconFactory.icon(ic, Color.WHITE, 48), 24))
		var l := Kit.wrap_label("Rank %d: %s" % [int(rw["rank"]), String(rw["text"])], "Small", 350)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if nxt:
			l.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.25))
		elif not reached:
			l.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
		rh.add_child(l)
		v.add_child(rh)
	return card
