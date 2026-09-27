extends Node
## PLACEHOLDER title screen (replaced by the UI agent).

func _ready() -> void:
	var c := CanvasLayer.new(); add_child(c)
	var v := VBoxContainer.new(); v.position = Vector2(80, 300); c.add_child(v)
	var l := Label.new(); l.text = "Hollowhaven - For Krystal"; l.add_theme_font_size_override("font_size", 48); v.add_child(l)
	var b := Button.new(); b.text = "New Game"; b.pressed.connect(func(): Game.new_game()); v.add_child(b)
	var b2 := Button.new(); b2.text = "Continue"; b2.disabled = not SaveSystem.has_save(); b2.pressed.connect(func(): Game.continue_game()); v.add_child(b2)
	var b3 := Button.new(); b3.text = "Quit"; b3.pressed.connect(func(): Game.quit_game()); v.add_child(b3)
