extends "res://tests/unit/test_core_base.gd"
## QA virtual input (src/qa/qa_input.gd) without sockets: command parsing, key / mouse injection through
## Input.parse_input_event into the InputMap actions, camera turning and zoom in QA no-capture mode, UI clicks,
## partial / multiple lines in one packet, and bad input answered with errors (never a crash).
## Every test releases what it pressed and restores Game.mode / Game._ui_stack.

const QAInput := preload("res://src/qa/qa_input.gd")
const CameraRig := preload("res://src/camera/camera_rig.gd")

var qi: Node = null
var _mode_backup: String = ""
var _stack_backup: Array = []
var _extra: Array = []          # nodes to free after the test
var _events: Array = []         # raw events seen by the root window


func setup() -> void:
	_mode_backup = Game.mode
	_stack_backup = Game._ui_stack.duplicate()
	qi = QAInput.new()
	add_child(qi)
	_events = []
	listen(get_tree().root.window_input, func(ev: InputEvent) -> void: _events.append(ev))


func teardown() -> void:
	if qi != null and is_instance_valid(qi):
		qi.release_all()
		Input.flush_buffered_events()
		qi.queue_free()
	qi = null
	for n in _extra:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_extra = []
	Game.mode = _mode_backup
	Game._ui_stack = _stack_backup.duplicate()
	await wait_frames(1)


## Runs everything queued and delivers the injected events now (the engine would at the next frame start).
func _run() -> void:
	qi.pump()
	Input.flush_buffered_events()


func _client() -> Dictionary:
	return {"buf": PackedByteArray(), "out": PackedByteArray(), "open": true}


func _replies(client: Dictionary) -> Array:
	var out: Array = []
	for line in (client["out"] as PackedByteArray).get_string_from_utf8().split("\n", false):
		out.append(JSON.parse_string(line))
	return out


func _send(line: String) -> Dictionary:
	var before: int = qi.sink.size()
	qi.submit_line(line)
	_run()
	assert_eq(qi.sink.size(), before + 1, "one reply for " + line)
	return qi.sink.back() if qi.sink.size() > before else {}


func _play_mode() -> void:
	Game.mode = "playing"
	Game._ui_stack = []


func _rig() -> CameraRig:
	var rig: CameraRig = CameraRig.new()
	add_child(rig)
	_extra.append(rig)
	qi.rig_override = rig
	return rig


# --- keys -------------------------------------------------------------------------------------------------------

func test_keys_press_and_release_their_actions() -> void:
	var cases := [["W", "move_forward"], ["w", "move_forward"], ["A", "move_left"], ["S", "move_back"], ["D", "move_right"],
		["SPACE", "jump"], ["SHIFT", "sprint"], ["CTRL", "dodge"], ["E", "interact"], ["ESCAPE", "pause"], ["ESC", "pause"],
		["TAB", "inventory"], ["F1", "help"], ["1", "hotbar_1"], ["8", "hotbar_8"], ["Q", "use_item"], ["F", "lantern"]]
	for c in cases:
		var key_name: String = c[0]
		var action: String = c[1]
		assert_false(Input.is_action_pressed(action), "%s not pressed before" % action)
		var r := _send(JSON.stringify({"k": key_name, "down": true}))
		assert_eq(r.get("ok"), true, "down %s: %s" % [key_name, str(r)])
		assert_true(Input.is_action_pressed(action), "%s pressed after key %s down" % [action, key_name])
		r = _send(JSON.stringify({"k": key_name, "down": false}))
		assert_eq(r.get("ok"), true, "up %s" % key_name)
		assert_false(Input.is_action_pressed(action), "%s released after key %s up" % [action, key_name])


func test_key_events_carry_physical_keycode_modifiers_and_text() -> void:
	_send('{"k": "SHIFT", "down": true}')
	_events = []
	_send('{"k": "W", "down": true}')
	var keys: Array = _events.filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	assert_eq(keys.size(), 1, "one key event reached the window")
	if keys.size() == 1:
		var k: InputEventKey = keys[0]
		assert_eq(int(k.physical_keycode), int(KEY_W), "physical keycode (Settings binds physical keys)")
		assert_eq(int(k.keycode), int(KEY_W), "keycode")
		assert_true(k.pressed, "pressed")
		assert_true(k.shift_pressed, "SHIFT is held")
		assert_eq(k.unicode, 87, "shifted W types 'W'")
	assert_true(Input.is_action_pressed("move_forward") and Input.is_action_pressed("sprint"), "sprinting forward")
	_send('{"k": "W", "down": false}')
	_send('{"k": "SHIFT", "down": false}')
	_events = []
	_send('{"k": "E", "down": true}')
	var e: InputEventKey = _events.filter(func(ev: InputEvent) -> bool: return ev is InputEventKey)[0]
	assert_false(e.shift_pressed, "no stale SHIFT")
	assert_eq(e.unicode, 101, "plain e")


func test_repeated_down_is_an_echo_and_release_all_lets_go() -> void:
	_send('{"k": "W", "down": true}')
	_events = []
	_send('{"k": "W", "down": true}')
	var k: InputEventKey = _events.filter(func(ev: InputEvent) -> bool: return ev is InputEventKey)[0]
	assert_true(k.echo, "second down = auto-repeat")
	_send('{"k": "SPACE", "down": true}')
	_send('{"mb": "left", "down": true}')
	assert_true(Input.is_action_pressed("move_forward") and Input.is_action_pressed("jump") and Input.is_action_pressed("attack"))
	var r := _send('{"release_all": true}')
	assert_eq(r.get("released"), 3.0, "W, SPACE and the left button")
	for a in ["move_forward", "jump", "attack"]:
		assert_false(Input.is_action_pressed(a), a + " released")


# --- mouse buttons ---------------------------------------------------------------------------------------------------

func test_mouse_buttons_trigger_attack_and_use_item() -> void:
	for c in [["left", "attack"], ["right", "use_item"]]:
		var r := _send(JSON.stringify({"mb": c[0], "down": true}))
		assert_eq(r.get("ok"), true, str(r))
		assert_true(Input.is_action_pressed(c[1]), "%s pressed by %s button" % [c[1], c[0]])
		_send(JSON.stringify({"mb": c[0], "down": false}))
		assert_false(Input.is_action_pressed(c[1]), "%s released" % c[1])


func test_button_press_happens_at_the_window_centre_during_play() -> void:
	_play_mode()
	_events = []
	_send('{"mb": "left", "down": true}')
	var mbs: Array = _events.filter(func(ev: InputEvent) -> bool: return ev is InputEventMouseButton)
	assert_eq(mbs.size(), 1)
	if mbs.size() == 1:
		assert_eq((mbs[0] as InputEventMouseButton).position, qi.window_center(), "a captured cursor sits in the centre")
		assert_eq(int((mbs[0] as InputEventMouseButton).button_mask), int(MOUSE_BUTTON_MASK_LEFT), "mask")
	_send('{"mb": "left", "down": false}')


# --- camera look & zoom -----------------------------------------------------------------------------------------------

func test_relative_motion_turns_the_camera_rig_like_a_mouse() -> void:
	_play_mode()
	var rig := _rig()
	await wait_frames(1)
	var sens: float = float(rig.get("_sens"))
	var base: float = float(CameraRig.BASE_SENS)
	var y0: float = rig.yaw
	var local: Vector2 = qi.local_delta(Vector2(2.0, 0.0))
	assert_true(local.x > 0.0, "positive local delta")
	var r := _send('{"mm": [2, 0]}')
	assert_eq(r.get("turned"), true, str(r))
	assert_almost(rig.yaw, wrapf(y0 - local.x * base * sens, -PI, PI), 0.0001, "yaw = rotate_by(viewport-local delta)")
	assert_true(angle_difference(y0, rig.yaw) < 0.0, "moving right turns right (yaw decreases)")
	var p0: float = rig.pitch
	var local_y: Vector2 = qi.local_delta(Vector2(0.0, 2.0))
	_send('{"mm": [0, 2]}')
	assert_almost(rig.pitch, clampf(p0 - local_y.y * base * sens, CameraRig.PITCH_MIN, CameraRig.PITCH_MAX), 0.0001, "moving down looks down")


func test_motion_does_not_turn_the_camera_in_menus_or_when_input_is_off() -> void:
	var rig := _rig()
	await wait_frames(1)
	Game.mode = "playing"
	Game._ui_stack = ["inventory"]
	var y0: float = rig.yaw
	var start: Vector2 = qi.pointer()
	var r := _send('{"mm": [1, 0]}')
	assert_eq(r.get("turned"), false, "menu open: pointer moves instead")
	assert_eq(rig.yaw, y0, "no turn with a menu open")
	assert_eq(qi.pointer(), qi._clamp_to_window(start + Vector2(1, 0)), "the virtual pointer moved right")
	Game._ui_stack = []
	rig.input_enabled = false
	_send('{"mm": [1, 0]}')
	assert_eq(rig.yaw, y0, "rig input disabled")
	rig.input_enabled = true
	Game.mode = "cutscene"
	_send('{"mm": [1, 0]}')
	assert_eq(rig.yaw, y0, "cutscene: the mouse would not be captured")


func test_wheel_zooms_the_camera_during_play() -> void:
	_play_mode()
	var rig := _rig()
	await wait_frames(1)
	var z0: float = rig.zoom_target
	var r := _send('{"mb": "wheel_down", "down": true}')
	assert_eq(r.get("ok"), true)
	assert_almost(rig.zoom_target, minf(z0 + float(CameraRig.ZOOM_STEP), CameraRig.ZOOM_MAX), 0.0001, "wheel down zooms out")
	_send('{"mb": "wheel_down", "down": false}')
	assert_almost(rig.zoom_target, minf(z0 + float(CameraRig.ZOOM_STEP), CameraRig.ZOOM_MAX), 0.0001, "a wheel 'up' event adds no notch")
	_send('{"mb": "wheel_up", "down": true}')
	assert_almost(rig.zoom_target, z0, 0.0001, "wheel up zooms back in")
	assert_false(Input.is_action_pressed("zoom_in") or Input.is_action_pressed("zoom_out"), "a notch is press + release")


# --- UI clicks --------------------------------------------------------------------------------------------------------

func test_click_presses_a_button_at_window_coordinates() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_extra.append(layer)
	var btn := Button.new()
	btn.text = "QA Test Button"
	btn.position = Vector2(200, 200)
	btn.size = Vector2(300, 100)
	layer.add_child(btn)
	var other := Button.new()
	other.position = Vector2(900, 900)
	other.size = Vector2(200, 80)
	layer.add_child(other)
	var pressed: Array = record(btn.pressed, 0)
	var other_pressed: Array = record(other.pressed, 0)
	await wait_frames(2)
	# Window pixels exactly as qa_telemetry reports button rects (viewport final transform).
	var xf := get_viewport().get_final_transform()
	var r := btn.get_global_rect()
	var c: Vector2 = xf * (r.position + r.size * 0.5)
	qi.submit({"click": [c.x, c.y], "id": 7})
	await wait_frames(6)
	assert_eq(pressed.size(), 1, "the button under the click was pressed once")
	assert_eq(other_pressed.size(), 0, "no other button")
	var reply: Dictionary = qi.sink.back() if not qi.sink.is_empty() else {}
	assert_eq(reply.get("ok"), true, str(reply))
	assert_eq(reply.get("id"), 7, "id echoed")
	assert_false(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "button released after the click")


# --- lines, packets and bad input --------------------------------------------------------------------------------------

func test_partial_and_multiple_lines_in_one_packet() -> void:
	var c := _client()
	qi.feed(c, '{"k": "W", '.to_utf8_buffer())
	qi.pump()
	assert_eq(_replies(c).size(), 0, "half a line does nothing")
	qi.feed(c, '"down": true, "id": 1}\n{"ping": true, "id": 2}\r\n\n{"k": "W", "down": false, "id": 3}\n{"status": true, "i'.to_utf8_buffer())
	_run()
	var rep := _replies(c)
	assert_eq(rep.size(), 3, "three complete lines -> three replies: %s" % str(rep))
	if rep.size() == 3:
		assert_eq([rep[0].get("id"), rep[1].get("id"), rep[2].get("id")], [1.0, 2.0, 3.0], "in order")
		assert_eq(rep[1].get("pong"), true)
		for x in rep:
			assert_eq(x.get("ok"), true, str(x))
	assert_false(Input.is_action_pressed("move_forward"), "W went down and up")
	qi.feed(c, 'd": 4}\n'.to_utf8_buffer())
	_run()
	rep = _replies(c)
	assert_eq(rep.size(), 4, "the split status line completed")
	if rep.size() == 4:
		assert_eq(rep[3].get("id"), 4.0)
		assert_true(rep[3].has("held_keys"), "status reply")


func test_bad_input_is_answered_with_errors_and_never_crashes() -> void:
	var c := _client()
	var lines := ['{not json', '[1, 2]', '"text"', '{"k": "NOPE", "down": true}', '{"k": "W"}', '{"k": "Shift+W", "down": true}',
		'{"mb": "banana", "down": true}', '{"mb": "left", "down": true, "x": 5}', '{"mm": [1]}', '{"mm": ["a", 2]}',
		'{"click": [1, 2], "button": "wheel_up"}', '{"shot": "relative.png"}', '{"shot": "C:/x/y.jpg"}', '{"what": 1}',
		'{"ping": true}']
	qi.feed(c, ("\n".join(lines) + "\n").to_utf8_buffer())
	_run()
	var rep := _replies(c)
	assert_eq(rep.size(), lines.size(), "one reply per line")
	for i in mini(rep.size(), lines.size() - 1):
		assert_eq(rep[i].get("ok"), false, "error for %s: %s" % [lines[i], str(rep[i])])
		assert_true(String(rep[i].get("error", "")) != "", "error text for " + lines[i])
	if rep.size() == lines.size():
		assert_eq(rep.back().get("ok"), true, "the server still works afterwards")
	# Oversized line without a newline, and bytes that are not UTF-8.
	var c2 := _client()
	var big := PackedByteArray()
	big.resize(QAInput.MAX_LINE_BYTES + 10)
	big.fill(65)
	qi.feed(c2, big)
	expect_error("nicode")        # the engine logs the invalid UTF-8; the command is just rejected
	qi.feed(c2, PackedByteArray([0xff, 0xfe, 0x7b, 10]))
	qi.feed(c2, '{"ping": true}\n'.to_utf8_buffer())
	_run()
	var rep2 := _replies(c2)
	assert_eq(rep2.size(), 3, str(rep2))
	if rep2.size() == 3:
		assert_true(String(rep2[0].get("error", "")).contains("too long"), str(rep2[0]))
		assert_eq(rep2[1].get("ok"), false, "garbage bytes rejected")
		assert_eq(rep2[2].get("ok"), true, "still alive")
	assert_eq((c2["buf"] as PackedByteArray).size(), 0, "buffer cleared")


func test_shot_is_refused_headless_and_path_is_validated() -> void:
	var r := _send('{"shot": "user://test_saves/qa_shot.png"}')
	assert_eq(r.get("ok"), false, "headless has no viewport image")
	assert_true(String(r.get("error", "")).contains("headless"), str(r))
	assert_false(FileAccess.file_exists("user://test_saves/qa_shot.png"))


func test_key_names() -> void:
	assert_eq(QAInput.keycode_for("W"), int(KEY_W))
	assert_eq(QAInput.keycode_for("space"), int(KEY_SPACE))
	assert_eq(QAInput.keycode_for("ESC"), int(KEY_ESCAPE))
	assert_eq(QAInput.keycode_for("Escape"), int(KEY_ESCAPE))
	assert_eq(QAInput.keycode_for("CTRL"), int(KEY_CTRL))
	assert_eq(QAInput.keycode_for("F1"), int(KEY_F1))
	assert_eq(QAInput.keycode_for("7"), int(KEY_7))
	assert_eq(QAInput.keycode_for("ENTER"), int(KEY_ENTER))
	assert_eq(QAInput.keycode_for("LEFT"), int(KEY_LEFT))
	assert_eq(QAInput.keycode_for(""), int(KEY_NONE))
	assert_eq(QAInput.keycode_for("Shift+W"), int(KEY_NONE), "combinations are refused")
	assert_eq(QAInput.keycode_for("NotAKey"), int(KEY_NONE))
