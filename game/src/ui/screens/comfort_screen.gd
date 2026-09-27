extends "res://src/ui/panels/panel_base.gd"
## Comfort & accessibility screen, shown on New Game and before the mine (and from the pause menu).
## Explains horror intensity (descriptions from data/horror_events.gd INTENSITY), arachnophobia mode
## (what it replaces), reduce camera shake, reduce flashing, captions and audio volumes. Every change
## applies live; closing saves Settings and marks comfort_confirmed. Emits `confirmed` when closed.

signal confirmed

const Rows := preload("res://src/ui/widgets/setting_rows.gd")
const Schema := preload("res://src/ui/settings_schema.gd")

var first_time := false
var accepted := false                  # true when closed with the Begin / Done button
var _confirmed_emitted := false


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	first_time = bool(p_args.get("first_time", false))
	title = "Before You Begin" if first_time else "Comfort & Accessibility"
	window_min = Vector2(1560, 0)


func _build() -> void:
	var intro := "Hollowhaven is mostly a cozy place. Deep below the old mine, though, things are meant to feel a little frightening. Choose what's comfortable for you. You can change any of this later from the pause menu."
	var il := Kit.wrap_label(intro, "", 1400, HORIZONTAL_ALIGNMENT_CENTER)
	il.add_theme_font_size_override("font_size", 25)
	il.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(il)
	var cols := Kit.hbox(44)
	body.add_child(cols)
	# Left: intensity
	var left := Kit.vbox(12)
	left.custom_minimum_size.x = 700
	cols.add_child(left)
	left.add_child(section_title("Horror intensity"))
	var hint := Kit.wrap_label("How frightening the deep places are. The surface is always gentle.", "Small", 680)
	left.add_child(hint)
	left.add_child(Rows.intensity_picker(700.0, 112.0))
	left.add_child(Kit.spacer(0, 6))
	left.add_child(section_title("Volume"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)
	for key in ["master_volume", "music_volume", "ambience_volume", "sfx_volume", "ui_volume"]:
		var r: Dictionary = Schema.row(key)
		var nl := Kit.label(String(r.get("label", key)))
		nl.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		nl.custom_minimum_size.x = 190
		grid.add_child(nl)
		grid.add_child(Rows.control(key))
	# Right: comfort toggles
	var right := Kit.vbox(12)
	right.custom_minimum_size.x = 720
	cols.add_child(right)
	right.add_child(section_title("Comfort"))
	for key in ["arachnophobia", "reduce_shake", "reduce_flashing", "captions"]:
		right.add_child(Rows.build(key, 720.0, true))
	body.add_child(Kit.spacer(0, 4))
	var bottom := Kit.hbox(20)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(bottom)
	var note := Kit.label("Tip: open Comfort any time from the pause menu (%s)." % Settings.action_label("pause"), "Small")
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(note)
	bottom.add_child(Kit.spacer(30, 0))
	var go := Kit.button("Begin the journey" if first_time else "Done", func() -> void:
		accepted = true
		request_close(), "AccentButton")
	go.add_theme_font_size_override("font_size", 30)
	go.name = "Confirm"
	bottom.add_child(go)


func default_focus() -> Control:
	return find_child("Confirm", true, false) as Control


func on_close() -> void:
	Settings.set_value("comfort_confirmed", true)
	UiUtil.save_settings()
	if not _confirmed_emitted:
		_confirmed_emitted = true
		confirmed.emit()
