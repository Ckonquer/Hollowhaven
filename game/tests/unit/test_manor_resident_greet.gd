extends "res://tests/test_case.gd"
## Count Velour as a manor resident (src/world/manor/count_resident.gd): the greeting right after the win is
## said once, GREET_DELAY seconds after he appears - and that delay is pause-aware (never fires behind the
## pause menu). A resident placed on a later load (greet false) stays quiet until spoken to.

const ResidentScript := preload("res://src/world/manor/count_resident.gd")
const Layout := preload("res://data/manor_layout.gd")

var _res: Node3D = null
var _said: Array = []


func before_each() -> void:
	fresh_state()
	_said.clear()
	if not Events.say.is_connected(_on_say):
		Events.say.connect(_on_say)


func after_each() -> void:
	get_tree().paused = false
	if Events.say.is_connected(_on_say):
		Events.say.disconnect(_on_say)
	if _res != null and is_instance_valid(_res):
		_res.queue_free()
	_res = null
	await wait_frames(2)


func _on_say(speaker: String, text: String, _duration: float) -> void:
	if speaker == Layout.VELOUR_NAME:
		_said.append(text)


func _resident(greet: bool) -> Node3D:
	var r: Node3D = ResidentScript.new()
	r.call("setup", {"greet": greet})
	add_child(r)
	return r


func test_greeting_waits_while_paused() -> void:
	_res = _resident(true)
	get_tree().paused = true
	await wait_seconds(ResidentScript.GREET_DELAY + 0.5)
	assert_eq(int(_res.get("talks")), 0, "no greeting behind the pause menu")
	assert_eq(_said, [], "nothing said while paused")
	get_tree().paused = false
	await wait_seconds(ResidentScript.GREET_DELAY + 0.5)
	assert_eq(int(_res.get("talks")), 1, "greets once the game runs again")
	assert_eq(_said, [String(Layout.RESIDENT_LINES[0])], "the first resident line, once")


func test_greeting_once_when_running_and_quiet_without_greet() -> void:
	_res = _resident(true)
	await wait_seconds(ResidentScript.GREET_DELAY + 0.4)
	assert_eq(int(_res.get("talks")), 1, "greets once, shortly after appearing")
	await wait_seconds(0.5)
	assert_eq(_said.size(), 1, "and only once")
	_res.queue_free()
	await wait_frames(1)
	_said.clear()
	_res = _resident(false)
	await wait_seconds(ResidentScript.GREET_DELAY + 0.4)
	assert_eq(int(_res.get("talks")), 0, "a later load's resident waits to be spoken to")
	assert_eq(_said, [])
