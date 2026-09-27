extends RefCounted
## Builds themed, live-bound widgets for settings described in settings_schema.gd.
## Each row updates Settings immediately and refreshes itself when the setting changes elsewhere.

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const Schema := preload("res://src/ui/settings_schema.gd")


## A full row: label + description on the left, control on the right.
static func build(key: String, width: float = 1100.0, compact: bool = false) -> Control:
	var r := Schema.row(key)
	if r.is_empty():
		return Kit.label("?")
	match String(r["type"]):
		"intensity":
			return intensity_picker(width)
	var h := Kit.hbox(24)
	h.custom_minimum_size.x = width
	var left := Kit.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var name_l := Kit.label(String(r["label"]))
	name_l.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	name_l.add_theme_font_size_override("font_size", 25 if not compact else 23)
	left.add_child(name_l)
	var desc := String(r.get("desc", ""))
	if desc != "":
		var dl := Kit.wrap_label(desc, "Small", 200)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if compact:
			dl.add_theme_font_size_override("font_size", 19)
		left.add_child(dl)
	var ctl := control(key)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctl)
	return h


## Just the input widget for a setting.
static func control(key: String) -> Control:
	var r := Schema.row(key)
	match String(r.get("type", "")):
		"toggle":
			return _toggle(key)
		"slider":
			return _slider(key, r)
		"option":
			return _option(key, r)
		"intensity":
			return intensity_picker(900.0)
	return Kit.label("?")


static func _toggle(key: String) -> Control:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_value(key))
	cb.text = "On" if cb.button_pressed else "Off"
	cb.custom_minimum_size = Vector2(118, 0)
	cb.toggled.connect(func(on: bool) -> void:
		Schema.apply(key, on)
		cb.text = "On" if on else "Off"
		Audio.play_ui("ui_click"))
	Kit.listen(cb, Events.settings_changed, func(k: String) -> void:
		if k == key and is_instance_valid(cb):
			var v := bool(Settings.get_value(key))
			if cb.button_pressed != v:
				cb.set_pressed_no_signal(v)
				cb.text = "On" if v else "Off")
	return cb


static func _slider(key: String, r: Dictionary) -> Control:
	var h := Kit.hbox(14)
	var s := HSlider.new()
	s.min_value = float(r["min"])
	s.max_value = float(r["max"])
	s.step = float(r["step"])
	s.custom_minimum_size = Vector2(300, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = float(Settings.get_value(key))
	var val_l := Kit.label(Schema.format_value(r, s.value), "", HORIZONTAL_ALIGNMENT_RIGHT)
	val_l.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	val_l.custom_minimum_size.x = 82
	s.value_changed.connect(func(v: float) -> void:
		var stored: Variant = Schema.apply(key, v)
		val_l.text = Schema.format_value(r, float(stored)))
	s.drag_ended.connect(func(_changed: bool) -> void:
		if r.has("test_ui"):
			Audio.play_ui(String(r["test_ui"]))
		elif r.has("test_sfx"):
			Audio.play_sfx(String(r["test_sfx"])))
	Kit.listen(s, Events.settings_changed, func(k: String) -> void:
		if k == key and is_instance_valid(s):
			var v := float(Settings.get_value(key))
			if absf(s.value - v) > 0.0001:
				s.set_value_no_signal(v)
				val_l.text = Schema.format_value(r, v))
	h.add_child(s)
	h.add_child(val_l)
	if r.has("test_ui") or r.has("test_sfx"):
		var t := Button.new()
		t.theme_type_variation = "RoundButton"
		t.icon = IconFactory.icon("ui_speaker", Color.WHITE, 48)
		t.expand_icon = true
		t.custom_minimum_size = Vector2(48, 48)
		t.tooltip_text = "Play a test sound"
		t.pressed.connect(func() -> void:
			if r.has("test_ui"):
				Audio.play_ui(String(r["test_ui"]))
			else:
				Audio.play_sfx(String(r["test_sfx"])))
		h.add_child(t)
	else:
		h.add_child(Kit.spacer(48, 0))
	return h


static func _option(key: String, r: Dictionary) -> Control:
	var ob := OptionButton.new()
	var opts: Array = r["options"]
	for i in opts.size():
		ob.add_item(String(opts[i][1]), i)
	ob.selected = Schema.option_index(r, Settings.get_value(key))
	ob.custom_minimum_size = Vector2(240, 0)
	ob.item_selected.connect(func(idx: int) -> void:
		Schema.apply(key, int(opts[idx][0]))
		Audio.play_ui("ui_click"))
	Kit.hook_sounds(ob)
	Kit.listen(ob, Events.settings_changed, func(k: String) -> void:
		if k == key and is_instance_valid(ob):
			ob.selected = Schema.option_index(r, Settings.get_value(key)))
	return ob


## Three selectable cards: Gentle / Standard / Intense with descriptions from data/horror_events.gd.
static func intensity_picker(width: float = 900.0, card_h: float = 104.0) -> Control:
	var v := Kit.vbox(10)
	v.custom_minimum_size.x = width
	var group := ButtonGroup.new()
	var buttons: Array = []
	for lvl in 3:
		var info := Schema.intensity_info(lvl)
		var b := Button.new()
		b.theme_type_variation = "TabLike"
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(width, card_h)
		b.button_pressed = int(Settings.get_value("horror_intensity")) == lvl
		var mc := Kit.margin([22, 12, 22, 12])
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Kit.full_rect(mc)
		b.add_child(mc)
		var col := Kit.vbox(2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(col)
		var top := Kit.hbox(10)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(top)
		var nl := Kit.label(String(info["name"]), "Subheading")
		nl.add_theme_font_size_override("font_size", 27)
		top.add_child(nl)
		if lvl == 1:
			var rec := Kit.label("recommended", "Tiny")
			rec.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rec.add_theme_color_override("font_color", ThemeFactory.GOOD.darkened(0.25))
			top.add_child(rec)
		var dl := Kit.wrap_label(String(info["desc"]), "Small", 200)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(dl)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				Schema.apply("horror_intensity", lvl))
		Kit.hook_sounds(b)
		buttons.append(b)
		v.add_child(b)
	Kit.listen(v, Events.settings_changed, func(k: String) -> void:
		if k == "horror_intensity" and is_instance_valid(v):
			var cur := int(Settings.get_value("horror_intensity"))
			for i in buttons.size():
				var bb: Button = buttons[i]
				if is_instance_valid(bb) and bb.button_pressed != (i == cur):
					bb.set_pressed_no_signal(i == cur))
	return v
