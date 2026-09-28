extends "res://tests/test_case.gd"
## Count Velour as a manor resident (src/world/manor/count_resident.gd): the greeting right after the win is
## said once, GREET_DELAY seconds after he appears - and that delay is pause-aware (never fires behind the
## pause menu). A resident placed on a later load (greet false) stays quiet until spoken to.
## The manor area (moonveil_manor_world.gd) places him after a live win only once the Count's dispersal has played
## (RESIDENT_DELAY = count_velour DEFEAT_PRESENT): one resident even if the win is applied twice, nothing if the area
## is freed first, and at once (quiet) on a load.

const ResidentScript := preload("res://src/world/manor/count_resident.gd")
const Layout := preload("res://data/manor_layout.gd")
const SCENE := "res://scenes/moonveil_manor.tscn"
const ManorWorld := preload("res://src/world/areas_ch2/moonveil_manor_world.gd")
const Velour := preload("res://src/enemies/count_velour.gd")

var _res: Node3D = null
var _said: Array = []
var _area: Node3D = null


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
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	GameState.active = false
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


func _load_manor() -> Node3D:
	GameState.active = true
	var ps: PackedScene = load(SCENE)
	var a: Node3D = ps.instantiate()
	add_child(a)
	await wait_physics(2)
	return a


func _residents(a: Node) -> int:
	return a.find_children("CountVelourResident", "", true, false).size()


func test_area_waits_for_the_dispersal_and_places_one_resident() -> void:
	assert_almost(ManorWorld.RESIDENT_DELAY, Velour.DEFEAT_PRESENT, 0.0001, "the delay is the Count's dispersal")
	_area = await _load_manor()
	assert_true(bool(_area.call("mark_velour_defeated", "boss")), "a live win")
	assert_true(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)), "the flag is immediate")
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "the doors are immediate")
	assert_null(_area.get("resident"), "no resident while the enchantment disperses")
	_area.call("_apply_after_velour", true)            # a second live apply (e.g. a foreign flag tick) never doubles him
	var delay: float = ManorWorld.RESIDENT_DELAY
	await wait_seconds(delay * 0.5)
	assert_eq(_residents(_area), 0, "still dispersing")
	await wait_seconds(delay * 0.5 + 0.3)
	assert_not_null(_area.get("resident"), "the freed Count appears after the dispersal")
	assert_eq(_residents(_area), 1, "exactly one resident")
	assert_true(bool((_area.get("resident") as Node).get("greet")), "a live win greets")
	await wait_seconds(ResidentScript.GREET_DELAY + 0.4)
	assert_eq(_said.filter(func(t: String) -> bool: return t == Layout.VELOUR_AFTER).size(), 1, "his first line, once")


func test_area_freed_before_the_delay_places_nothing_and_a_load_is_instant() -> void:
	_area = await _load_manor()
	_area.call("mark_velour_defeated", "boss")
	_area.queue_free()                                  # she left before the dispersal finished
	_area = null
	await wait_seconds(ManorWorld.RESIDENT_DELAY + 0.4)
	assert_eq(_residents(self), 0, "no resident created for a freed area")
	assert_eq(_said, [], "and no greeting")
	_area = await _load_manor()                         # the next visit: the flag is in the save
	assert_not_null(_area.get("resident"), "on load he is there at once")
	assert_false(bool((_area.get("resident") as Node).get("greet")), "and quiet until spoken to")
	await wait_seconds(ResidentScript.GREET_DELAY + 0.4)
	assert_eq(_said, [], "no greeting on a load")
