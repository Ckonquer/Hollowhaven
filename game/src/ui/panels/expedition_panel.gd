extends "res://src/ui/panels/panel_base.gd"
## Lanternwake Expeditions (panel "expedition", module D2; MP §15), registered in ui_root.PANELS (full-screen) and
## opened by the Expedition Board (a UI root without it makes the board open the Optional journal instead).
## Left: the three hand-authored routes (difficulty in words AND lantern pips, never colour alone; locked ones
## greyed with the reason). Right: the chosen route BEFORE starting - blurb, difficulty, rough length, the
## stops in order, who may be met (arachnophobia-aware names), the reward TYPES and how often it was done. A dye
## keepsake is named as what she gets - "a new dye colour" (its Loom palette, unlocked directly as a gift) - never
## "a recipe" she would still have to craft.
## Bottom: "Set out" (starts a run: Expeditions.start), and while a run is going its progress line,
## "Lantern Road to <arch>" (when that arch is lit) and "Set it aside" (two presses; free - nothing she carries is lost;
## in the cache phase the confirm says that the earned cache stays closed).
## The board's second option, the Optional journal, is one button away ("Optional journal").
## No timers, no daily limits: the panel never shows a countdown or a streak.
## args: {"template": id (preselect), "source": structure id}. Rebuilt on Events.objectives_changed.

const Ex := preload("res://src/expeditions/expeditions.gd")
const Data := preload("res://data/expeditions.gd")
const Reach := preload("res://data/hallowmere_layout.gd")

const JOURNAL_PANEL := "journal"
const JOURNAL_ARGS := {"tab": "optional"}
const INTRO := "Optional routes through Hallowmere Reach, for whenever you feel like an outing. Go when you like, stop when you like: setting one aside costs nothing, and nothing here is ever needed for the story."
const CALM_NOTE := "No timers and no daily limits. Every reward can also be gathered or made at home."
const ICON_TEMPLATES := {"orchard_patrol": "pumpkin", "quarry_circuit": "iron_ore", "manor_afterglow": "lantern_wax"}

var selected: String = ""
var card_box: VBoxContainer
var detail_box: VBoxContainer
var status_l: Label
var start_btn: Button
var abandon_btn: Button
var travel_btn: Button
var journal_btn: Button
var _cards: Dictionary = {}          # template id -> Button
var _group := ButtonGroup.new()
var _confirm_abandon := false
var _sig := ""


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Lanternwake Expeditions"
	window_min = Vector2(1360, 0)
	selected = String(p_args.get("template", ""))


func _build() -> void:
	body.add_child(Kit.wrap_label(INTRO, "", 1260))
	var cols := Kit.hbox(24)
	body.add_child(cols)
	card_box = Kit.vbox(10)
	card_box.custom_minimum_size.x = 430
	cols.add_child(card_box)
	for id in Ex.template_ids():
		card_box.add_child(_make_card(String(id)))
	var page := Kit.panel("Card")
	page.custom_minimum_size = Vector2(800, 520)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(page)
	detail_box = Kit.vbox(10)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(detail_box)
	status_l = Kit.wrap_label("", "Small", 1260)
	body.add_child(status_l)
	var bottom := Kit.hbox(14)
	body.add_child(bottom)
	journal_btn = Kit.button("Optional journal", open_journal)
	journal_btn.tooltip_text = "Optional discoveries, trials and crafting ideas (Journal, Optional tab)"
	bottom.add_child(journal_btn)
	bottom.add_child(Kit.expander())
	abandon_btn = Kit.button("Set it aside", press_abandon)
	bottom.add_child(abandon_btn)
	travel_btn = Kit.button("Lantern Road", travel)
	bottom.add_child(travel_btn)
	start_btn = Kit.button("Set out", start_selected, "AccentButton")
	bottom.add_child(start_btn)
	bottom.add_child(Kit.button("Close", request_close))
	if selected == "" or Ex.template(selected).is_empty():
		selected = _default_selection()
	Events.objectives_changed.connect(_on_state_changed)
	Events.settings_changed.connect(_on_settings_changed)
	# Idempotent safety net: Game.wire_session_systems() already wires the Reach runner hook at start-up; when the
	# board stands in the Reach this also gives the area its runner right away.
	Ex.init()
	Ex.attach_to_current_area()


func _make_card(id: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "TabLike"
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(430, 96)
	b.pressed.connect(select.bind(id))
	b.focus_entered.connect(func() -> void:
		if selected != id:
			select(id))
	Kit.hook_sounds(b)
	var mc := Kit.margin([12, 6, 12, 6])
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(Kit.full_rect(mc))
	var h := Kit.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(h)
	h.add_child(Kit.icon_rect(IconFactory.item_icon(String(ICON_TEMPLATES.get(id, "lantern")), 64), 60))
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var name_l := Kit.label("", "CardTitle")
	name_l.name = "Name"
	v.add_child(name_l)
	var row := Kit.hbox(6)
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	b.set_meta("name_label", name_l)
	b.set_meta("row", row)
	_cards[id] = b
	return b


func _default_selection() -> String:
	var a := Ex.active()
	if not a.is_empty():
		return String(a["template"])
	for id in Ex.template_ids():
		if Ex.is_unlocked(String(id)):
			return String(id)
	return String(Ex.template_ids()[0])


## Shows a route's details (tests and the cards).
func select(id: String) -> void:
	if Ex.template(id).is_empty():
		return
	selected = id
	_confirm_abandon = false
	_sig = ""
	refresh()


func refresh() -> void:
	if detail_box == null:
		return
	var a := Ex.active()
	var sig := "%s|%s|%s|%d|%s|%s" % [selected, str(a), str(Ex.last_result()), Ex.completions(selected), str(_confirm_abandon), travel_arch()]
	for id in Ex.template_ids():
		sig += "|%s%s" % [str(Ex.is_unlocked(String(id))), str(Ex.completions(String(id)))]
	if sig == _sig:
		return
	_sig = sig
	for id in _cards:
		_fill_card(String(id))
	_fill_detail()
	_fill_status()
	_fill_buttons()


func _fill_card(id: String) -> void:
	var b: Button = _cards[id]
	var pv := Ex.preview(id)
	(b.get_meta("name_label") as Label).text = String(pv["name"])
	var row: HBoxContainer = b.get_meta("row")
	for c in row.get_children():
		c.queue_free()
	for i in 3:
		var pip := Kit.icon_rect(IconFactory.item_icon("lantern", 32), 24)
		pip.modulate = Color.WHITE if i < int(pv["pips"]) else Color(1, 1, 1, 0.22)
		row.add_child(pip)
	var sub := "%s  ·  %d stops" % [String(pv["difficulty_name"]), (pv["stops"] as Array).size()]
	if not bool(pv["unlocked"]):
		sub = "Not yet open"
	elif String(Ex.active().get("template", "")) == id:
		sub += "  ·  under way"
	row.add_child(Kit.label(sub, "Small"))
	b.modulate = Color.WHITE if bool(pv["unlocked"]) else Color(1, 1, 1, 0.6)
	b.set_pressed_no_signal(id == selected)


func _fill_detail() -> void:
	for c in detail_box.get_children():
		detail_box.remove_child(c)
		c.queue_free()
	var pv := Ex.preview(selected)
	if pv.is_empty():
		return
	detail_box.add_child(Kit.label(String(pv["name"]), "Subheading"))
	detail_box.add_child(Kit.wrap_label(String(pv["blurb"]), "", 740))
	var diff := Kit.hbox(8)
	diff.add_child(Kit.label("Difficulty:", "CardTitle"))
	for i in 3:
		var pip := Kit.icon_rect(IconFactory.item_icon("lantern", 32), 26)
		pip.modulate = Color.WHITE if i < int(pv["pips"]) else Color(1, 1, 1, 0.22)
		diff.add_child(pip)
	diff.add_child(Kit.label("%s (%d of 3)" % [String(pv["difficulty_name"]), int(pv["pips"])]))
	detail_box.add_child(diff)
	detail_box.add_child(Kit.wrap_label(String(pv["difficulty_text"]), "Small", 740))
	var route: Array = (pv["stops"] as Array).duplicate()
	route.append(String(pv["cache"]))
	detail_box.add_child(Kit.wrap_label("Route (%d stops, about %s minutes): %s" % [(pv["stops"] as Array).size(), String(pv["minutes"]),
		"  >  ".join(route)], "", 740))
	detail_box.add_child(Kit.wrap_label("You may meet: " + ", ".join(pv["enemies"]), "", 740))
	detail_box.add_child(Kit.label("Rewards:", "CardTitle"))
	for r in pv["reward_types"]:
		detail_box.add_child(Kit.wrap_label("  -  " + String(r), "", 740))
	var done := int(pv["completed"])
	var foot := "Not walked yet: the first completion always brings a keepsake." if done == 0 else "Completed %d time%s." % [done, "" if done == 1 else "s"]
	if not bool(pv["unlocked"]):
		foot = String(pv["reason"])
	detail_box.add_child(Kit.wrap_label(foot, "Small", 740))
	detail_box.add_child(Kit.wrap_label(CALM_NOTE, "Small", 740))


func _fill_status() -> void:
	var line := Ex.summary_line()
	if line != "":
		status_l.text = "Under way: %s. Follow the ribbon lantern in Hallowmere Reach." % line
		return
	var last := Ex.last_result()
	if not last.is_empty():
		var parts: Array = []
		var items: Variant = last.get("items", {})
		if items is Dictionary:
			for id in items:
				parts.append("%s x%d" % [ItemDB.display_name(String(id)), int(items[id])])
		var k: Variant = last.get("keepsake", {})
		if k is Dictionary:
			# same words as the completion toast: "a new dye colour (Pumpkin)" / "Pumpkin Lights x2"
			var ks := Ex.keepsake_text(k as Dictionary)
			if ks != "":
				parts.append(ks)
		status_l.text = "Last outing: %s brought home %s." % [String(Ex.template(String(last.get("template", ""))).get("name", "an expedition")),
			", ".join(parts) if not parts.is_empty() else "a good walk"]
		return
	status_l.text = "No expedition under way."


func _fill_buttons() -> void:
	var a := Ex.active()
	var running := not a.is_empty()
	start_btn.visible = not running
	start_btn.disabled = not Ex.is_unlocked(selected)
	start_btn.tooltip_text = Ex.lock_reason(selected)
	abandon_btn.visible = running
	# Honest in the cache phase: setting the run aside there leaves the earned cache closed.
	var confirm_key := "abandon_confirm_cache" if Ex.in_cache_phase() else "abandon_confirm"
	abandon_btn.text = String(Data.TEXT[confirm_key]) if _confirm_abandon else "Set it aside"
	var arch := travel_arch()
	travel_btn.visible = running and arch != ""
	if arch != "":
		travel_btn.text = "Lantern Road to %s" % String(Reach.ARCHES[arch]["name"])


## The lit Lantern Road arch nearest the running route's start ("" when none / not lit / no run).
func travel_arch() -> String:
	var a := Ex.active()
	if a.is_empty():
		return ""
	var arch := String(Ex.template(String(a["template"])).get("arch", ""))
	if arch == "" or not Reach.ARCHES.has(arch) or not bool(GameState.get_flag(Reach.arch_flag(arch))):
		return ""
	return arch


# --- Actions --------------------------------------------------------------------------------------------------

## "Set out": starts the selected route. False when locked or another run is going.
func start_selected() -> bool:
	var ok := Ex.start(selected)
	if not ok and Ex.is_active():
		Events.notify.emit("Finish or set aside the current expedition first.", "info")
	elif not ok:
		Events.notify.emit(Ex.lock_reason(selected), "info")
	_sig = ""
	refresh()
	return ok


## "Set it aside": the first press asks, the second sets the run aside (free). True when it was set aside.
func press_abandon() -> bool:
	if not Ex.is_active():
		return false
	if not _confirm_abandon:
		_confirm_abandon = true
		_sig = ""
		refresh()
		return false
	_confirm_abandon = false
	var ok := Ex.abandon()
	_sig = ""
	refresh()
	return ok


## Closes the board and walks the Lantern Road to the route's arch (same rules as any Lantern Road trip).
func travel() -> void:
	var arch := travel_arch()
	if arch == "":
		return
	request_close()
	Game.lantern_road_travel.call_deferred(arch)


## The board's second option: the journal's Optional tab.
func open_journal() -> void:
	if ui_root != null and ui_root.has_method("open"):
		var r: Node = ui_root
		request_close()
		r.call("open", JOURNAL_PANEL, JOURNAL_ARGS.duplicate())
	else:
		Game.open_panel(JOURNAL_PANEL, JOURNAL_ARGS.duplicate())


# --- Queries (tests) ------------------------------------------------------------------------------------------

func card_ids() -> Array:
	return _cards.keys()


## Every text currently shown in the detail page, one line per label.
func detail_text() -> String:
	var out: Array = []
	for n in detail_box.find_children("*", "Label", true, false):
		if not (n as Node).is_queued_for_deletion():
			out.append((n as Label).text)
	return "\n".join(out)


func status_text() -> String:
	return status_l.text


func _on_state_changed() -> void:
	refresh()


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia":
		_sig = ""
		refresh()


func reopen(p_args: Dictionary) -> void:
	args = p_args
	var want := String(p_args.get("template", ""))
	if want != "" and not Ex.template(want).is_empty():
		selected = want
	_sig = ""
	refresh()


func default_focus() -> Control:
	if start_btn != null and start_btn.visible and not start_btn.disabled:
		return start_btn
	return _cards.get(selected, null)
