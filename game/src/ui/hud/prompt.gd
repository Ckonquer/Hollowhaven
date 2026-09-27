extends PanelContainer
## Interaction prompt "[E] Pick up Wood" from Game.player.get_prompt(). Greyed (with the reason) when
## the interaction is not currently possible.

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var cap_box: HBoxContainer
var text_l: Label
var _sig := ""
var _tw: Dictionary = {}
var _want := false


func _ready() -> void:
	theme_type_variation = "Pill"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := Kit.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	cap_box = Kit.hbox(0)
	cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cap_box)
	text_l = Kit.label("", "HudText")
	text_l.add_theme_font_size_override("font_size", 25)
	text_l.add_theme_constant_override("outline_size", 0)
	text_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(text_l)
	modulate.a = 0.0
	visible = false


## p: {"text", "action" (default "interact"), "enabled" (default true), "reason"} or {} to hide.
func set_prompt(p: Dictionary) -> void:
	var text := String(p.get("text", ""))
	if text == "":
		_show(false)
		return
	var action := String(p.get("action", "interact"))
	var enabled := bool(p.get("enabled", true))
	var reason := String(p.get("reason", ""))
	var sig := "%s|%s|%s|%s|%s" % [text, action, enabled, reason, Settings.action_label(action)]
	if sig != _sig:
		_sig = sig
		for c in cap_box.get_children():
			c.queue_free()
		var cap := Kit.key_cap(Settings.action_label(action))
		cap.modulate.a = 1.0 if enabled else 0.55
		cap_box.add_child(cap)
		text_l.text = text if (enabled or reason == "") else "%s  (%s)" % [text, reason]
		text_l.add_theme_color_override("font_color", ThemeFactory.CREAM if enabled else Color(ThemeFactory.CREAM, 0.55))
	_show(true)


func _show(on: bool) -> void:
	if on == _want:
		return
	_want = on
	var tw := Kit.retween(self, _tw, "fade")
	if on:
		visible = true
		tw.tween_property(self, "modulate:a", 1.0, 0.12)
	else:
		tw.tween_property(self, "modulate:a", 0.0, 0.15)
		tw.tween_callback(func() -> void:
			if not _want:
				visible = false)
