extends "res://tests/test_case.gd"
## The Companion Skill action (default T) with no follower in the area (player.gd, lead decision for the B4 review):
## the follower's own script answers the key; with nobody following here Krystal gets a gentle hint instead of
## silence - "No friend is following you right now." - at most once every 10 seconds.

const PlayerScript := preload("res://src/player/player.gd")

var player: CharacterBody3D
var notes: Array = []
var _saved_mode := ""
var _saved_nodes: Dictionary = {}
var _extra: Array = []


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	_saved_nodes = Game.companion_nodes
	Game.companion_nodes = {}
	notes.clear()
	Events.notify.connect(_on_notify)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.set_physics_process(false)      # no floor here: only the input path is under test
	await wait_physics(2)
	Game.mode = "playing"


func after_each() -> void:
	if Events.notify.is_connected(_on_notify):
		Events.notify.disconnect(_on_notify)
	Game.companion_nodes = _saved_nodes
	Game.mode = _saved_mode
	GameState.active_companion = ""
	for n in _extra:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_extra.clear()
	if is_instance_valid(player):
		player.queue_free()
	await wait_frames(2)


func _on_notify(text: String, _kind: String = "") -> void:
	notes.append(text)


func _hints() -> int:
	return notes.count(PlayerScript.NO_FOLLOWER_TEXT)


func _press_skill() -> void:
	var ev := InputEventAction.new()
	ev.action = "companion_skill"
	ev.pressed = true
	player._unhandled_input(ev)


## A stand-in companion node with a `mode` like src/companions/companion.gd.
func _companion(mode: String) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar mode: String = \"follow\"\n"
	s.reload()
	var n: Node3D = s.new()
	n.set("mode", mode)
	add_child(n)
	_extra.append(n)
	return n


func test_no_follower_gives_a_gentle_hint_at_most_every_ten_seconds() -> void:
	assert_true(InputMap.has_action("companion_skill"), "the rebindable action exists")
	_press_skill()
	assert_eq(_hints(), 1, "pressing T alone says why nothing happens")
	_press_skill()
	_press_skill()
	assert_eq(_hints(), 1, "never spammed")
	var ms: Dictionary = player.get("_notify_ms")
	ms["skill_no_follower"] = Time.get_ticks_msec() - 9000
	_press_skill()
	assert_eq(_hints(), 1, "still quiet after 9 s")
	ms["skill_no_follower"] = Time.get_ticks_msec() - 10100
	_press_skill()
	assert_eq(_hints(), 2, "again after 10 s")
	var up := InputEventAction.new()
	up.action = "companion_skill"
	up.pressed = false
	ms["skill_no_follower"] = -1000000
	player._unhandled_input(up)
	assert_eq(_hints(), 2, "releasing the key does nothing")


func test_a_follower_here_answers_the_key_itself() -> void:
	GameState.active_companion = "lumi"
	Game.companion_nodes = {"lumi": _companion("follow")}
	assert_true(player.has_follower_here())
	_press_skill()
	assert_eq(_hints(), 0, "the follower handles T (its own reasons if the skill can't be used)")


func test_hint_when_the_friend_is_not_following_here() -> void:
	# Mochi stays home in underground areas: she is the active companion but has no node here.
	GameState.active_companion = "mochi"
	Game.companion_nodes = {}
	assert_false(player.has_follower_here())
	_press_skill()
	assert_eq(_hints(), 1, "no follower node in this area")
	# a companion node that is waiting (or at home) does not answer T either
	(player.get("_notify_ms") as Dictionary).clear()
	GameState.active_companion = "pebble"
	Game.companion_nodes = {"pebble": _companion("wait")}
	assert_false(player.has_follower_here())
	_press_skill()
	assert_eq(_hints(), 2, "waiting friends don't use their skill")


func test_no_hint_while_menus_hold_the_input() -> void:
	Game.push_ui("test_panel")
	_press_skill()
	Game.pop_ui("test_panel")
	assert_eq(_hints(), 0, "UI focus never leaks the key into gameplay")
