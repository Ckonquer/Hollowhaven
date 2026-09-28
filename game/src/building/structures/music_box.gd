extends "res://src/building/structure.gd"
## Music box (data interact "music"): wind it and a soft chime plays while the little star dancer on top turns
## for a while (a caption says so, for players without sound). Only processes while it is playing.

const PLAY_SECONDS := 14.0
const SPIN_SPEED := 1.6          # rad/s

var _left := 0.0


func _setup_behaviour() -> void:
	set_process(false)


func is_playing() -> bool:
	return _left > 0.0


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Let it rest" if is_playing() else "Wind the music box", "enabled": true}


func interact(_player: Node) -> void:
	if is_playing():
		_left = 0.0
		set_process(false)
		return
	_left = PLAY_SECONDS
	set_process(true)
	if is_inside_tree():
		Audio.play_3d("checkpoint_light", global_position + Vector3.UP * 0.4, -6.0)
	Events.caption.emit("A music box plays a little tune")


func _process(delta: float) -> void:
	_left -= delta
	var spinner: Variant = parts.get("spinner")
	if spinner is Node3D:
		(spinner as Node3D).rotation.y += SPIN_SPEED * delta
	if _left <= 0.0:
		_left = 0.0
		set_process(false)
