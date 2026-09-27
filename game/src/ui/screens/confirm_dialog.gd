extends "res://src/ui/panels/panel_base.gd"
## Small confirmation card. setup({"title", "text", "buttons": [[id, label, variation], ...]}).
## Emits `chosen(id)` ("cancel" when closed with Esc / the close button).

signal chosen(choice: String)

var text := ""
var buttons: Array = []
var _first_btn: Button
var _answered := false


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = String(p_args.get("title", "Are you sure?"))
	text = String(p_args.get("text", ""))
	buttons = p_args.get("buttons", [["ok", "OK", "AccentButton"], ["cancel", "Cancel", ""]])
	window_min = Vector2(760, 0)


func _build() -> void:
	var l := Kit.wrap_label(text, "", 640, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_size_override("font_size", 26)
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(l)
	body.add_child(Kit.spacer(0, 10))
	var row := Kit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	for b in buttons:
		var id := String(b[0])
		var btn := Kit.button(String(b[1]), _choose.bind(id), String(b[2]) if b.size() > 2 else "")
		row.add_child(btn)
		if _first_btn == null:
			_first_btn = btn


func _choose(id: String) -> void:
	if _answered:
		return
	_answered = true
	chosen.emit(id)
	request_close()


func default_focus() -> Control:
	return _first_btn


func on_close() -> void:
	if not _answered:
		_answered = true
		chosen.emit("cancel")
