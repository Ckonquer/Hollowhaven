extends "res://tests/unit/test_core_base.gd"
## QA virtual input over a real socket: the server binds 127.0.0.1 only, answers newline-delimited JSON sent by a
## TCP client (several commands per packet), injects the keys, and releases everything held when the client
## goes away. Also the second-monitor flags (Debug.parse_user_args / qa_input_port / _setup_qa_mode), the
## no-capture mouse mode, --qa-mute and the additive QA telemetry fields.

const QAInput := preload("res://src/qa/qa_input.gd")
const QATelemetry := preload("res://src/qa/qa_telemetry.gd")

var qi: Node = null
var _peers: Array = []
var _debug_backup: Dictionary = {}


func setup() -> void:
	_debug_backup = {"args": Debug.args.duplicate(), "qa_no_capture": Debug.qa_no_capture, "qa_input": Debug.qa_input}


func teardown() -> void:
	for p in _peers:
		(p as StreamPeerTCP).disconnect_from_host()
	_peers = []
	if qi != null and is_instance_valid(qi):
		qi.release_all()
		Input.flush_buffered_events()
		qi.queue_free()
	qi = null
	if Debug.qa_input != null and is_instance_valid(Debug.qa_input) and Debug.qa_input != _debug_backup["qa_input"]:
		Debug.qa_input.queue_free()
	Debug.args = _debug_backup["args"]
	Debug.qa_no_capture = _debug_backup["qa_no_capture"]
	Debug.qa_input = _debug_backup["qa_input"]
	await wait_frames(1)


func _server() -> Node:
	qi = QAInput.new()
	add_child(qi)
	assert_eq(qi.start(0), OK, "listen on a free port")
	assert_true(qi.port > 0, "port assigned")
	return qi


## Connects a client and waits (bounded) until the server has accepted it.
func _connect(port: int) -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	_peers.append(peer)
	assert_eq(peer.connect_to_host("127.0.0.1", port), OK)
	for i in 240:
		await wait_frames(1)
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and int(qi.status()["clients"]) > 0:
			break
	assert_eq(peer.get_status(), StreamPeerTCP.STATUS_CONNECTED, "client connected")
	return peer


## Reads reply lines until `n` arrived (bounded wait).
func _read_lines(peer: StreamPeerTCP, n: int) -> Array:
	var text := ""
	for i in 240:
		await wait_frames(1)
		peer.poll()
		var avail := peer.get_available_bytes()
		if avail > 0:
			var res: Array = peer.get_partial_data(avail)
			text += (res[1] as PackedByteArray).get_string_from_utf8()
		if text.count("\n") >= n:
			break
	var out: Array = []
	for line in text.split("\n", false):
		out.append(JSON.parse_string(line))
	return out


func _free_port() -> int:
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	var p := probe.get_local_port()
	probe.stop()
	return p


# --- TCP --------------------------------------------------------------------------------------------------------

func test_tcp_round_trip_injects_keys_in_order() -> void:
	_server()
	assert_eq(QAInput.BIND_ADDRESS, "127.0.0.1")
	var peer: StreamPeerTCP = await _connect(qi.port)
	# Three commands in ONE packet, the last one split over a second packet.
	peer.put_data('{"ping": true, "id": 1}\n{"k": "W", "down": true, "id": 2}\n{"k": "SPA'.to_utf8_buffer())
	var first: Array = await _read_lines(peer, 2)
	assert_eq(first.size(), 2, "two complete lines answered: %s" % str(first))
	if first.size() == 2:
		assert_eq(first[0].get("pong"), true)
		assert_eq(first[1].get("ok"), true)
		assert_eq(first[1].get("id"), 2.0)
	assert_true(Input.is_action_pressed("move_forward"), "W held through the socket")
	peer.put_data('CE", "down": true, "id": 3}\n'.to_utf8_buffer())
	var second: Array = await _read_lines(peer, 1)
	assert_eq(second.size(), 1)
	if second.size() == 1:
		assert_eq(second[0].get("id"), 3.0, "the split line was reassembled")
	assert_true(Input.is_action_pressed("jump"), "SPACE held")
	peer.put_data('{"oops"\n{"release_all": true, "id": 4}\n'.to_utf8_buffer())
	var third: Array = await _read_lines(peer, 2)
	assert_eq(third.size(), 2)
	if third.size() == 2:
		assert_eq(third[0].get("ok"), false, "bad json answered with an error")
		assert_eq(third[1].get("released"), 2.0)
	assert_false(Input.is_action_pressed("move_forward") or Input.is_action_pressed("jump"), "released")


func test_disconnect_releases_held_input() -> void:
	_server()
	var peer: StreamPeerTCP = await _connect(qi.port)
	peer.put_data('{"k": "D", "down": true}\n{"mb": "left", "down": true}\n'.to_utf8_buffer())
	await _read_lines(peer, 2)
	assert_true(Input.is_action_pressed("move_right") and Input.is_action_pressed("attack"), "held")
	peer.disconnect_from_host()
	for i in 240:
		await wait_frames(1)
		if int(qi.status()["clients"]) == 0 and not Input.is_action_pressed("move_right"):
			break
	await wait_frames(2)
	assert_eq(int(qi.status()["clients"]), 0, "client dropped")
	assert_false(Input.is_action_pressed("move_right"), "a vanished bot never leaves a key down")
	assert_false(Input.is_action_pressed("attack"), "nor a mouse button")


func test_server_binds_only_loopback() -> void:
	_server()
	var lan := ""
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.contains(".") and not s.begins_with("127.") and not s.begins_with("169.254."):
			lan = s
			break
	if lan == "":
		print("test_server_binds_only_loopback: no non-loopback IPv4 address on this machine; loopback checks only")
	else:
		var peer := StreamPeerTCP.new()
		_peers.append(peer)
		peer.connect_to_host(lan, qi.port)
		for i in 120:
			await wait_frames(1)
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
				break
		assert_ne(peer.get_status(), StreamPeerTCP.STATUS_CONNECTED, "no connection via %s" % lan)
		await wait_frames(2)
		assert_eq(int(qi.status()["clients"]), 0, "nothing accepted from %s" % lan)
	var ok_peer: StreamPeerTCP = await _connect(qi.port)
	assert_eq(ok_peer.get_status(), StreamPeerTCP.STATUS_CONNECTED, "127.0.0.1 works")


# --- flags ------------------------------------------------------------------------------------------------------

func test_user_args_parse() -> void:
	var a: Dictionary = Debug.parse_user_args(PackedStringArray(["--qa-input-port=5123", "--qa-no-focus",
		"--qa-window=1920,0,1920,1080", "--settings-file=C:/qa/run/qa_settings.cfg", "--qa-mute", "stray", "-x"]))
	assert_deep_eq(a, {"qa-input-port": "5123", "qa-no-focus": "true", "qa-window": "1920,0,1920,1080",
		"settings-file": "C:/qa/run/qa_settings.cfg", "qa-mute": "true"})
	assert_eq(Debug.qa_input_port(a), 5123)
	for bad in ["0", "65536", "-4", "abc", "", "12.5"]:
		assert_eq(Debug.qa_input_port({"qa-input-port": bad}), -1, "invalid port '%s'" % bad)
	assert_eq(Debug.qa_input_port({}), -1, "absent")
	assert_eq(Settings.qa_window_rect(PackedStringArray(["--qa-window=1920,0,1920,1080"])), Rect2i(1920, 0, 1920, 1080))
	assert_eq(Settings.qa_window_rect(PackedStringArray(["--qa-window=-1920, 0, 1280, 720"])), Rect2i(-1920, 0, 1280, 720),
		"negative desktop coordinates and spaces")
	for bad in ["--qa-window=1,2,3", "--qa-window=a,b,c,d", "--qa-window=0,0,10,10", "--qa-screen=99", "--qa-screen=x"]:
		assert_eq(Settings.qa_window_rect(PackedStringArray([bad])), Rect2i(), "ignored: " + bad)
	assert_eq(Settings.qa_window_rect(PackedStringArray(["--windowed"])), Rect2i(), "no QA placement")
	assert_eq(Settings.qa_window_rect(PackedStringArray(["--qa-screen=99", "--qa-window=10,20,800,600"])), Rect2i(10, 20, 800, 600),
		"--qa-window wins")


func test_setup_qa_mode_starts_the_server_and_no_capture() -> void:
	var port := _free_port()
	Debug.args = {"qa-no-focus": "true", "qa-input-port": str(port)}
	Debug.qa_input = null
	Debug._setup_qa_mode()
	assert_true(Debug.qa_no_capture, "--qa-no-focus -> no capture")
	assert_not_null(Debug.qa_input, "--qa-input-port -> QAInput node")
	if Debug.qa_input != null:
		assert_eq(Debug.qa_input.get_parent(), Debug, "child of Debug")
		assert_eq(Debug.qa_input.process_mode, Node.PROCESS_MODE_ALWAYS, "runs while paused")
		assert_true(Debug.qa_input.call("is_listening"), "listening")
		assert_eq(int(Debug.qa_input.get("port")), port)
	# Without the flags nothing starts.
	var started: Node = Debug.qa_input
	Debug.args = {"qa-input-port": "not-a-port"}
	Debug.qa_input = null
	Debug._setup_qa_mode()
	assert_false(Debug.qa_no_capture, "no flag, normal capture")
	assert_null(Debug.qa_input, "invalid port: no server")
	Debug.qa_input = started


func test_no_capture_keeps_the_os_cursor_visible() -> void:
	Debug.qa_no_capture = false
	assert_eq(Debug.mouse_mode_for(true), Input.MOUSE_MODE_CAPTURED, "normal play captures the mouse")
	assert_eq(Debug.mouse_mode_for(false), Input.MOUSE_MODE_VISIBLE, "menus show it")
	Debug.qa_no_capture = true
	assert_eq(Debug.mouse_mode_for(true), Input.MOUSE_MODE_VISIBLE, "QA no-capture: never captured")
	assert_eq(Debug.mouse_mode_for(false), Input.MOUSE_MODE_VISIBLE)
	# Game._update_mouse() must take its mode from there (the only capture site besides the title's VISIBLE).
	var src: String = (load("res://autoload/game.gd") as GDScript).source_code
	var i := src.find("func _update_mouse()")
	var body := src.substr(i, src.find("\nfunc ", i + 5) - i)
	assert_true(body.contains("Debug.mouse_mode_for(want_captured)"), "Game._update_mouse uses Debug.mouse_mode_for")
	assert_false(body.contains("MOUSE_MODE_CAPTURED"), "no direct capture left in _update_mouse")


func test_qa_mute_silences_master_without_touching_settings() -> void:
	var master := AudioServer.get_bus_index("Master")
	var before_fx := AudioServer.get_bus_effect_count(master)
	var vol: Variant = Settings.get_value("master_volume")
	assert_true(Debug.qa_mute_audio())
	assert_true(Debug.qa_mute_audio(), "idempotent")
	assert_eq(AudioServer.get_bus_effect_count(master), before_fx + 1, "one mute effect")
	var fx := AudioServer.get_bus_effect(master, before_fx)
	assert_true(fx is AudioEffectAmplify and (fx as AudioEffectAmplify).volume_db <= -80.0, "-80 dB on Master")
	assert_eq(Settings.get_value("master_volume"), vol, "the setting (and so the saved file) is unchanged")
	AudioServer.remove_bus_effect(master, before_fx)


func test_telemetry_reports_window_focus_and_virtual_input() -> void:
	_server()
	Debug.qa_input = qi
	var tele: Node = QATelemetry.new()
	add_child(tele)
	var d: Dictionary = tele._snapshot()
	tele.queue_free()
	for k in ["window", "window_pos", "window_focused", "mouse_mode", "qa_input"]:
		assert_true(d.has(k), "telemetry has " + k)
	assert_eq(int((d.get("qa_input", {}) as Dictionary).get("port", 0)), qi.port)
	assert_true(JSON.stringify(d) != "", "serialisable")
