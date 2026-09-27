extends Control
## Gentle defeat screen: the world dims to a deep plum, a kind line appears, then the UI root fades to
## black so the respawn happens unseen. play() is awaitable (~2.5 s).

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var bg: ColorRect
var box: VBoxContainer


func _ready() -> void:
	Kit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	bg = ColorRect.new()
	bg.color = Color(0.13, 0.07, 0.12, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(bg))
	box = Kit.vbox(12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(box))
	var who := GameState.player_name if GameState.player_name != "" else "Krystal"
	var t := Kit.label("%s was overwhelmed..." % who, "Display", HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_size_override("font_size", 64)
	box.add_child(t)
	var s := Kit.label("She'll wake somewhere safe. Nothing is lost.", "HudText", HORIZONTAL_ALIGNMENT_CENTER)
	s.add_theme_font_size_override("font_size", 28)
	box.add_child(s)
	box.modulate.a = 0.0


## Dims and shows the message (~1.9 s). The UI root then fades to black and frees this screen.
func play() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bg, "color:a", 0.72, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.8).set_delay(0.35)
	await tw.finished
	await get_tree().create_timer(0.75).timeout
