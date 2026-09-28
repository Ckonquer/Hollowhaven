extends PanelContainer
## Objective tracker (HUD, top right): the combined current objective, updated on Events.objectives_changed,
## step starts, area loads, settings changes and a 1 s poll (rebuilt only when its signature changes).
##   * Chapter One in progress  -> the legacy quest step (data/quests.gd), exactly as before.
##   * Chapter One complete, Chapter Two not accepted -> a gentle pointer: "The Ward Stone has something new
##     to say" (never the legacy "OPTIONAL GOALS" free-play card: those goals live in the journal).
##   * Chapter Two accepted -> its current step; the three lamp branches (group "lamps") are shown TOGETHER,
##     done lamps ticked, in any order.
##   * Chapter Two finished -> one pending optional goal as a signpost ("SOMETHING TO DO"), else hidden.
## Shows where to head ("Head to X") for the target landmark / room of the area Krystal is in, or which
## area the goal is in. All text goes through step_string / alt labels (arachnophobia).
## objective_view() and where_text() are static and shared with the journal and the map panel.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const ChapterData := preload("res://data/quests_ch2.gd")

const HEADER_GOAL := "CURRENT GOAL"
const HEADER_OPTIONAL := "OPTIONAL GOALS"        # legacy free_play step only (Chapter One saves)
const HEADER_POINTER := "WHEN YOU'RE READY"
const HEADER_SIGNPOST := "SOMETHING TO DO"
const POINTER_TITLE := "The Ward Stone has something new to say"
const POINTER_TITLE_READ := "The lantern road will keep"
const POINTER_TEXT := "Chapter One is complete and the Haven is safe. The Ward Stone's runes have begun to glow in a new pattern. Read it whenever you like: nothing changes until you choose to follow the lantern road."
const POINTER_WHERE := "At the Ward Stone in Krystal's Haven"
const POINTER_WHERE_READ := "Read the Ward Stone again whenever you're ready"
const POINTER_READ_FLAG := "read_ward_ch2"
const SEP := "   ·   "

var header: Label
var title_l: Label
var obj_box: VBoxContainer
var where_l: Label
var view_kind: String = ""        # kind of the objective shown (see objective_view)
var _rows: Array = []
var _last_step := ""
var _last_sig := ""
var _tw: Dictionary = {}
var _check_t := 1.0


func _ready() -> void:
	theme_type_variation = "HudCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 440
	var v := Kit.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var hdr := Kit.hbox(8)
	hdr.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 48), 26))
	header = Kit.label(HEADER_GOAL, "Tiny")
	header.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
	hdr.add_child(header)
	v.add_child(hdr)
	title_l = Kit.wrap_label("", "CardTitle", 390)
	v.add_child(title_l)
	obj_box = Kit.vbox(4)
	v.add_child(obj_box)
	where_l = Kit.label("", "Small")
	where_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where_l.custom_minimum_size.x = 390
	v.add_child(where_l)
	Events.objectives_changed.connect(refresh)
	Events.quest_step_started.connect(_on_step_started)
	Events.chapter2_step_started.connect(_on_step_started)
	Events.optional_goal_completed.connect(_on_optional_done)
	Events.area_loaded.connect(func(_a: String) -> void: refresh())
	Events.settings_changed.connect(func(k: String) -> void:
		if k == "bindings" or k == "arachnophobia":
			_last_sig = ""
			refresh())
	refresh()


# --- View model (static: shared with journal_panel.gd and map_panel.gd) ------------------------------------

## What the objective card should say right now:
## {"kind": "legacy" | "pointer" | "chapter2" | "signpost" | "done" | "hidden", "header", "title", "text", "hint",
##  "rows": [{label, done, progress, target, step?}], "parts": [{id, title, text, done, rows, target, area}],
##  "step_id", "group", "optional": bool, "targets": [{id, area, done, step, name}]}.
## "parts" has one entry per step shown (the whole group for the lamps); "targets" are the places the map
## marks (the legacy step's landmark; each Chapter Two step's target + target_area; the Haven for the pointer).
## Built on GameState.current_objective() (spec §8); does not check GameState.active (callers do).
static func objective_view() -> Dictionary:
	var v := {"kind": "hidden", "header": "", "title": "", "text": "", "hint": "", "rows": [], "parts": [],
		"step_id": "", "group": "", "optional": false, "targets": []}
	var obj: Dictionary = GameState.current_objective()
	if String(obj.get("source", "")) == "chapter2" and not (obj.get("steps", []) as Array).is_empty():
		return _chapter2_view(v, obj["steps"])
	var log: RefCounted = GameState.chapter2
	if log.is_available():
		if not log.is_active():
			return _pointer_view(v)
		return _signpost_view(v)
	return _legacy_view(v, obj)


static func _legacy_view(v: Dictionary, obj: Dictionary) -> Dictionary:
	var steps: Array = obj.get("steps", [])
	if steps.is_empty():
		return v
	var q: RefCounted = GameState.quests
	var step: Dictionary = steps[0]
	var optional := bool(step.get("optional", false))
	v["kind"] = "legacy"
	v["header"] = HEADER_OPTIONAL if optional else HEADER_GOAL
	v["title"] = String(q.step_string(step, "title"))
	v["text"] = String(q.step_string(step, "text"))
	v["hint"] = String(q.step_string(step, "hint"))
	v["rows"] = obj.get("status", [])
	v["step_id"] = String(step.get("id", ""))
	v["optional"] = optional
	var target := String(step.get("target", ""))
	v["parts"] = [{"id": v["step_id"], "title": v["title"], "text": v["text"], "done": false, "rows": v["rows"],
		"target": target, "area": "surface" if target != "" else ""}]
	if target != "":
		v["targets"] = [{"id": target, "area": "surface", "done": false, "step": v["step_id"],
			"name": MapView.place_name(target, "surface")}]
	return v


static func _pointer_view(v: Dictionary) -> Dictionary:
	var read := true if GameState.get_flag(POINTER_READ_FLAG) else false
	v["kind"] = "pointer"
	v["header"] = HEADER_POINTER
	v["title"] = POINTER_TITLE_READ if read else POINTER_TITLE
	v["text"] = POINTER_TEXT
	v["step_id"] = String(ChapterData.STEPS[0]["id"])
	v["targets"] = [{"id": "haven", "area": "surface", "done": false, "step": v["step_id"],
		"name": MapView.place_name("haven", "surface")}]
	v["parts"] = [{"id": v["step_id"], "title": v["title"], "text": v["text"], "done": false, "rows": [],
		"target": "haven", "area": "surface"}]
	return v


static func _chapter2_view(v: Dictionary, cur: Array) -> Dictionary:
	var log: RefCounted = GameState.chapter2
	var first: Dictionary = cur[0]
	var group := String(first.get("group", ""))
	var steps: Array = cur
	if group != "":
		steps = []
		for s in ChapterData.STEPS:
			if String(s.get("group", "")) == group:
				steps.append(s)
	v["kind"] = "chapter2"
	v["header"] = HEADER_GOAL
	v["title"] = String(log.display_title(cur))
	v["step_id"] = String(first["id"])
	v["group"] = group
	if group != "" and ChapterData.GROUPS.has(group):
		v["text"] = String(ChapterData.GROUPS[group].get("text", ""))
	else:
		v["text"] = String(log.step_string(first, "text"))
		v["hint"] = String(log.step_string(first, "hint"))
	var rows: Array = []
	var parts: Array = []
	var targets: Array = []
	for s in steps:
		var sid := String(s["id"])
		var done: bool = log.is_done(sid)
		var srows: Array = []
		for st in log.objective_status(s):
			var d: Dictionary = st
			if done:
				d["done"] = true
				d["progress"] = d["target"]
			d["step"] = sid
			srows.append(d)
		rows.append_array(srows)
		var target := String(s.get("target", ""))
		var area := String(s.get("target_area", ""))
		if area == "" and target != "":
			area = MapView.area_of(target)
		parts.append({"id": sid, "title": String(log.step_string(s, "title")), "text": String(log.step_string(s, "text")),
			"done": done, "rows": srows, "target": target, "area": area})
		if target != "":
			targets.append({"id": target, "area": area, "done": done, "step": sid, "name": MapView.place_name(target, area)})
	v["rows"] = rows
	v["parts"] = parts
	v["targets"] = targets
	return v


## After Chapter Two: one pending optional goal (Chapter Two ones first) as a signpost; "done" when none.
static func _signpost_view(v: Dictionary) -> Dictionary:
	var og: RefCounted = GameState.optional_goals
	var pick: Dictionary = {}
	for g in og.pending_goals():
		if int(g.get("chapter", 1)) == 2:
			pick = g
			break
		if pick.is_empty():
			pick = g
	if pick.is_empty():
		v["kind"] = "done"
		return v
	v["kind"] = "signpost"
	v["header"] = HEADER_SIGNPOST
	v["title"] = String(og.step_string(pick, "title"))
	v["text"] = String(og.step_string(pick, "text"))
	v["rows"] = og.objective_status(pick)
	v["step_id"] = String(pick["id"])
	v["optional"] = true
	v["parts"] = [{"id": v["step_id"], "title": v["title"], "text": v["text"], "done": false, "rows": v["rows"],
		"target": "", "area": ""}]
	return v


## Targets of a view that are not done yet.
static func pending_targets(view: Dictionary) -> Array:
	var out: Array = []
	for t in view.get("targets", []):
		if not bool(t.get("done", false)) and String(t.get("id", "")) != "":
			out.append(t)
	return out


## True when Krystal already stands at a target: inside an outdoor landmark's radius, or in the room zone.
static func is_at(t: Dictionary, area_id: String, player_pos: Variant, zone: String = "") -> bool:
	if String(t.get("area", "")) != area_id:
		return false
	var disc := MapView.place_disc(String(t.get("id", "")), area_id)
	if not disc.is_empty():
		if not (player_pos is Vector3):
			return false
		var p: Vector3 = player_pos
		return Vector2(p.x, p.z).distance_to(disc["pos"]) < float(disc["radius"])
	return zone != "" and zone == String(t.get("id", ""))


## The "where to" line of the tracker ("" = hide it) for Krystal in `area_id` at `player_pos` (Vector3 or null).
static func where_text(view: Dictionary, area_id: String, player_pos: Variant, zone: String = "") -> String:
	var key := Settings.action_label("map")
	var map_suffix := SEP + "%s Map" % key
	match String(view.get("kind", "")):
		"legacy":
			var lt := pending_targets(view)
			if lt.is_empty() or area_id != "surface":
				return ""
			var t: Dictionary = lt[0]
			if String(t["name"]) == "" or is_at(t, area_id, player_pos, zone):
				return ""
			return "Head to %s" % String(t["name"]) + map_suffix
		"pointer":
			if GameState.get_flag(POINTER_READ_FLAG):
				return POINTER_WHERE_READ
			var s := POINTER_WHERE
			var home: Dictionary = (view["targets"] as Array)[0]
			if area_id == "surface" and not is_at(home, area_id, player_pos, zone):
				s += map_suffix
			return s
		"chapter2":
			var pt := pending_targets(view)
			if pt.is_empty():
				return ""
			if pt.size() > 1:
				var all_here := true
				for t in pt:
					if String(t["area"]) != area_id:
						all_here = false
				if all_here and MapView.map_kind(area_id) != "none":
					return "Each is marked on your map" + map_suffix
				return "In %s" % MapView.area_name(String(pt[0]["area"]))
			var t1: Dictionary = pt[0]
			var name := String(t1["name"])
			var area := String(t1["area"])
			if area == area_id:
				if is_at(t1, area_id, player_pos, zone) or name == "":
					return ""
				return "Head to %s" % name + (map_suffix if MapView.map_kind(area_id) != "none" else "")
			if name == "":
				return "In %s" % MapView.area_name(area) if MapView.area_name(area) != "" else ""
			return "Head to %s, in %s" % [name, MapView.area_name(area)]
	return ""


# --- Node -------------------------------------------------------------------------------------------------

func refresh() -> void:
	if not GameState.active:
		visible = false
		view_kind = ""
		return
	var view := objective_view()
	view_kind = String(view["kind"])
	if view_kind == "hidden" or view_kind == "done":
		visible = false
		return
	visible = true
	var ppos: Variant = null
	if Game.player != null and is_instance_valid(Game.player) and Game.player is Node3D:
		ppos = (Game.player as Node3D).global_position
	var where := where_text(view, Game.area_id, ppos, Game.zone_id)
	var status: Array = view["rows"]
	var sig := "%s|%s|%s|%s|%s|%s" % [view_kind, String(view["step_id"]), String(view["header"]), String(view["title"]), str(status), where]
	if sig == _last_sig:
		return
	_last_sig = sig
	header.text = String(view["header"])
	title_l.text = String(view["title"])
	while _rows.size() < status.size():
		_rows.append(_make_row())
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var box: HBoxContainer = row["box"]
		if i >= status.size():
			box.visible = false
			continue
		box.visible = true
		var st: Dictionary = status[i]
		var done := bool(st["done"])
		row["done"] = done
		var icon: TextureRect = row["icon"]
		icon.texture = IconFactory.icon("ui_check", Color.WHITE, 48) if done else IconFactory.glyph("radio_off", 38, 38)
		var lab: Label = row["label"]
		lab.text = String(st["label"])
		lab.add_theme_color_override("font_color", ThemeFactory.INK_SOFT if done else ThemeFactory.INK)
		var prog: Label = row["progress"]
		var target := int(st["target"])
		prog.visible = target > 1
		prog.text = "%d/%d" % [int(st["progress"]), target]
		prog.add_theme_color_override("font_color", ThemeFactory.GOOD.darkened(0.2) if done else ThemeFactory.INK_SOFT)
	where_l.text = where
	where_l.visible = where != ""


## Visible objective rows (tests / QA): [{label, done}] in display order.
func shown_rows() -> Array:
	var out: Array = []
	for row in _rows:
		var box: HBoxContainer = row["box"]
		if box.visible:
			out.append({"label": (row["label"] as Label).text, "done": bool(row.get("done", false))})
	return out


func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.0
		if visible or GameState.active:
			refresh()


func _make_row() -> Dictionary:
	var box := Kit.hbox(8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Kit.icon_rect(null, 26)
	box.add_child(icon)
	var lab := Kit.wrap_label("", "", 300)
	lab.add_theme_font_size_override("font_size", 22)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lab)
	var prog := Kit.label("", "Small", HORIZONTAL_ALIGNMENT_RIGHT)
	prog.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	box.add_child(prog)
	obj_box.add_child(box)
	return {"box": box, "icon": icon, "label": lab, "progress": prog}


func _on_step_started(step_id: String) -> void:
	if step_id == _last_step:
		return
	_last_step = step_id
	_last_sig = ""
	refresh()
	var tw := Kit.retween(self, _tw, "glow")
	modulate = Color(1.25, 1.18, 1.0, 1.0)
	tw.tween_property(self, "modulate", Color.WHITE, 1.2).set_ease(Tween.EASE_OUT)


func _on_optional_done(_id: String) -> void:
	refresh()
