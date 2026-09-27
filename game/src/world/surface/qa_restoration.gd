extends Node3D
## QA-ONLY helper (never used by gameplay; debug builds via the preview stage):
##   tools/godot.sh --path game --windowed --resolution 1280x720 -- \
##     --preview=res://src/world/surface/qa_restoration.gd --preview-wait=90 --shot-dir=<abs dir> [--preview-args='{"hour":20.5}']
## Builds the surface, then plays the Ward restoration and saves screenshots along the way.
## With {"restored": true} it only shows the already-restored Haven (instant look on load).

const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")

var hour := 17.5
var restored_only := false
var _world: Node3D
var _cam: Camera3D


func setup(p: Dictionary) -> void:
	hour = float(p.get("hour", 17.5))
	restored_only = bool(p.get("restored", false))


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		return
	for c in get_parent().get_children():
		if c != self and (c is WorldEnvironment or c is DirectionalLight3D or c is MeshInstance3D):
			c.queue_free()
	GameState.new_game()
	GameState.total_minutes = hour * 60.0
	if restored_only:
		GameState.set_flag("ward_restored", true)
	_world = SurfaceWorld.new()
	add_child(_world)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.global_position = Vector3(1.5, 2.4, 6.0)
	_cam.look_at(Vector3(0, 1.6, -6), Vector3.UP)
	_cam.make_current()
	_run.call_deferred()


func _shot(dir: String, label: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("restore_%s.png" % label))
	print("QA restoration: saved ", label)


func _run() -> void:
	var dir := Debug.arg("shot-dir", "user://qa_restore")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	_cam.make_current()   # the preview stage makes its own camera current after our _ready
	await get_tree().create_timer(1.5).timeout
	if restored_only:
		await _shot(dir, "restored_a")
		_cam.global_position = Vector3(-14, 7, 16)
		_cam.look_at(Vector3(0, 1, -3), Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		await _shot(dir, "restored_b")
		get_tree().quit()
		return
	await _shot(dir, "00_before")
	GameState.set_flag("ward_restored", true)
	_world.play_restoration()
	var times := [0.8, 2.0, 3.5, 5.0, 6.5, 8.0, 9.5]
	var t := 0.0
	for i in times.size():
		await get_tree().create_timer(float(times[i]) - t).timeout
		t = float(times[i])
		await _shot(dir, "%02d_t%.1f" % [i + 1, t])
	await get_tree().create_timer(2.0).timeout
	_cam.make_current()
	await _shot(dir, "99_after")
	get_tree().quit()
