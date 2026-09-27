extends Node3D
## QA-ONLY helper (debug builds via the preview stage): builds the surface three times in a row in a
## real window and prints the build times (first = cold caches, later = warm mesh/shader caches).
##   tools/godot.sh --path game --windowed -- --preview=res://src/world/surface/qa_build_time.gd --preview-wait=90

const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")


func _ready() -> void:
	if Debug.is_cheat_allowed():
		_run.call_deferred()


func _run() -> void:
	GameState.new_game()
	for i in 3:
		var w: Node3D = SurfaceWorld.new()
		add_child(w)
		print("QA build %d: %.0f ms %s" % [i, float(w.build_times.get("total", -1.0)), str(w.build_times)])
		for k in 30:
			await get_tree().process_frame
		w.queue_free()
		for k in 5:
			await get_tree().process_frame
	get_tree().quit()
