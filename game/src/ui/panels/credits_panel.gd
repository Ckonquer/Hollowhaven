extends "res://src/ui/panels/panel_base.gd"
## Credits card (title screen): the same credits as the chapter ending, on parchment.
## setup({"chapter": 1 | 2}) (optional): the chapters listed. Without it the save on this computer decides (like the
## title footer): once it has reached Chapter Two, "Chapter Two: The Lanterns of Hallowmere" is listed too (visual
## QA UI-04: the title credits used to name Chapter One only).

const EndingScreen := preload("res://src/ui/screens/ending_screen.gd")

var chapter := 0
var _close: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Credits"
	window_min = Vector2(1100, 0)
	chapter = int(p_args.get("chapter", 0))


## The chapter the credits list up to for a save's data (SaveSystem.peek() or its "meta"): 2 once the save is in
## Chapter Two, else 1. Pure.
static func credits_chapter(save_data: Dictionary) -> int:
	var meta: Variant = save_data.get("meta", save_data)
	if not (meta is Dictionary):
		return 1
	return 2 if float((meta as Dictionary).get("chapter", 1)) >= 2.0 else 1


func _build() -> void:
	if chapter <= 0:
		chapter = credits_chapter(SaveSystem.peek())
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1020, 700)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var c := EndingScreen.build_credits(980.0, false, chapter)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(c)
	_close = Kit.button("Close", request_close, "AccentButton")
	_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_close)


func default_focus() -> Control:
	return _close
