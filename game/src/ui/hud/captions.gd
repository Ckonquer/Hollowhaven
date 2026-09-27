extends VBoxContainer
## Sound captions (Events.caption), shown only when Settings "captions" is on. Up to three soft pills
## stack above the dialog box and fade after a few seconds.

const Kit := preload("res://src/ui/ui_kit.gd")

const LIFE := 3.8
const MAX_LINES := 3

var _lines: Array = []     # [{panel, t}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)
	Events.caption.connect(show_caption)


func show_caption(text: String) -> void:
	if not bool(Settings.get_value("captions")) or text.strip_edges() == "":
		return
	for l in _lines:
		if (l["label"] as Label).text == text:
			l["t"] = 0.0
			return
	var p := PanelContainer.new()
	p.theme_type_variation = "HudDark"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var lab := Kit.label(text, "HudText", HORIZONTAL_ALIGNMENT_CENTER)
	lab.add_theme_constant_override("outline_size", 0)
	lab.add_theme_font_size_override("font_size", 24)
	p.add_child(lab)
	add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	_lines.append({"panel": p, "label": lab, "t": 0.0})
	while _lines.size() > MAX_LINES:
		var old: Dictionary = _lines.pop_front()
		(old["panel"] as Control).queue_free()


func _process(delta: float) -> void:
	for i in range(_lines.size() - 1, -1, -1):
		var l: Dictionary = _lines[i]
		l["t"] = float(l["t"]) + delta
		var p: Control = l["panel"]
		if float(l["t"]) > LIFE:
			p.modulate.a = maxf(0.0, 1.0 - (float(l["t"]) - LIFE) / 0.5)
			if float(l["t"]) > LIFE + 0.5:
				p.queue_free()
				_lines.remove_at(i)
