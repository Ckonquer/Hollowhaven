extends "res://src/ui/panels/panel_base.gd"
## Credits card (title screen): the same credits as the chapter ending, on parchment.

const EndingScreen := preload("res://src/ui/screens/ending_screen.gd")

var _close: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Credits"
	window_min = Vector2(1100, 0)


func _build() -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1020, 700)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var c := EndingScreen.build_credits(980.0, false)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(c)
	_close = Kit.button("Close", request_close, "AccentButton")
	_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_close)


func default_focus() -> Control:
	return _close
