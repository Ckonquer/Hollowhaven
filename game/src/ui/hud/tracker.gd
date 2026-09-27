extends PanelContainer
## Objective tracker: current quest step title + objectives with progress, updated on
## Events.objectives_changed. Shows where to head (target landmark) on the surface.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var header: Label
var title_l: Label
var obj_box: VBoxContainer
var where_l: Label
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
	header = Kit.label("CURRENT GOAL", "Tiny")
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
	Events.area_loaded.connect(func(_a: String) -> void: refresh())
	Events.settings_changed.connect(func(k: String) -> void:
		if k == "bindings" or k == "arachnophobia":
			_last_sig = ""
			refresh())
	refresh()


func refresh() -> void:
	var q: RefCounted = GameState.quests
	var step: Dictionary = q.current_step()
	if step.is_empty() or not GameState.active:
		visible = false
		return
	visible = true
	var status: Array = q.objective_status()
	var target_id := String(step.get("target", ""))
	var here := _player_at(target_id)
	var sig := "%s|%s|%s|%s" % [String(step.get("id", "")), str(status), Game.area_id, here]
	if sig == _last_sig:
		return
	_last_sig = sig
	header.text = "OPTIONAL GOALS" if bool(step.get("optional", false)) else "CURRENT GOAL"
	title_l.text = String(q.step_string(step, "title"))
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
	var place := UiUtil.landmark_name(target_id)
	if place != "" and Game.area_id == "surface" and not here:
		where_l.text = "Head to %s   ·   %s Map" % [place, Settings.action_label("map")]
		where_l.visible = true
	else:
		where_l.visible = false


## True when Krystal is already inside the target landmark (no need to say "Head to ...").
func _player_at(target_id: String) -> bool:
	if target_id == "" or Game.area_id != "surface" or Game.player == null or not is_instance_valid(Game.player):
		return false
	var lm: Dictionary = UiUtil.Layout.LANDMARKS.get(target_id, {})
	if lm.is_empty() or not (Game.player is Node3D):
		return false
	var p: Vector3 = (Game.player as Node3D).global_position
	return Vector2(p.x, p.z).distance_to(lm["pos"]) < float(lm["radius"])


func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.0
		if visible:
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
