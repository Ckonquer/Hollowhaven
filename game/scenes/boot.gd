extends Node
## First scene: hands control to Game (title screen, or the debug harness when requested).

func _ready() -> void:
	Game.boot.call_deferred()
