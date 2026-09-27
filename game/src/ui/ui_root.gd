extends CanvasLayer
## PLACEHOLDER UI root (replaced by the UI agent). Minimal fade + no-op panels.

var fade: ColorRect

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	fade = ColorRect.new(); fade.color = Color(0.05, 0.04, 0.06, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT); fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

func fade_out(t: float) -> void:
	var tw := create_tween(); tw.tween_property(fade, "color:a", 1.0, t); await tw.finished

func fade_in(t: float) -> void:
	var tw := create_tween(); tw.tween_property(fade, "color:a", 0.0, t); await tw.finished

func open(_panel: String, _args: Dictionary = {}) -> void: pass
func close(_panel: String) -> void: pass
func show_death() -> void: await get_tree().create_timer(1.5).timeout
func show_ending() -> void: await get_tree().create_timer(1.0).timeout
