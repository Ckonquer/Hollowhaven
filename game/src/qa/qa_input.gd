extends Node
## QA virtual input for the second-monitor QA mode (tools/qa --second-monitor / --virtual-input).
## Created by Debug ONLY for the command-line user arg --qa-input-port=<port> (debug and release builds: it grants
## no cheats - every command is something a keyboard or mouse could do). Listens on 127.0.0.1:<port> and never on
## any other interface, reads newline-delimited JSON commands and injects them with Input.parse_input_event, so a
## bot can play in an unfocused window on another monitor while the owner keeps the real keyboard and mouse.
## Injected events bypass the OS input layer (no SendInput, no window focus, no OS cursor) but then take exactly
## the path real input takes: Input action state (InputMap), _input, GUI, _unhandled_input.
##
## Commands (one JSON object per line; an optional "id" is echoed in the reply):
##   {"k": "W", "down": true}         key down/up by name: W, SPACE, SHIFT, CTRL, E, ESCAPE (or ESC), TAB, F1, 1..8
##                                    or any Godot key name. Sets keycode AND physical_keycode (Settings binds
##                                    physical keys "key:<code>"), shift/ctrl/alt state and unicode for text input.
##   {"mb": "left", "down": true, "x": 800, "y": 450}
##                                    mouse button left|right|middle|wheel_up|wheel_down (a wheel "down" is one
##                                    notch: press + release). x/y (window pixels) are optional: the pointer moves
##                                    there first. Without them the press happens at the pointer - or at the window
##                                    centre while the game would have the mouse captured, like a captured cursor.
##   {"mm": [dx, dy]}                 relative mouse motion. While the game would capture the mouse (playing, no
##                                    menu open) the camera turns exactly as with a real mouse: CameraRig.rotate_by()
##                                    gets the same viewport-local delta its _input() would read (the rig reads
##                                    motion only in captured mode, which QA no-capture runs never enter). In menus it
##                                    moves the virtual pointer (hover, drags).
##   {"move": [x, y]}                 absolute pointer move in window pixels (hover)
##   {"click": [x, y], "button": "left"}   UI click: move + press, hold 2 frames, release
##   {"shot": "C:/abs/file.png"}      save the current viewport image (the game's own frame, never the desktop)
##   {"release_all": true}            release every key / button held through this server
##   {"ping": true}  {"status": true}
## Replies: one JSON line per command, in command order: {"ok": true, ...} or {"ok": false, "error": "..."}.
## Several commands may share one packet and a line may be split across packets. Nothing blocks the main thread
## (non-blocking sockets, bounded work per frame). When the last client disconnects every held input is released,
## so a crashed bot never leaves Krystal running.

const BIND_ADDRESS := "127.0.0.1"
const MAX_CLIENTS := 4
const MAX_LINE_BYTES := 65536
const MAX_OUT_BYTES := 1048576
const MAX_COMMANDS_PER_FRAME := 256
const CLICK_HOLD_FRAMES := 2
const MAX_DELTA := 100000.0
const MOUSE_BUTTONS := {"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP, "wheel_down": MOUSE_BUTTON_WHEEL_DOWN, "wheel_left": MOUSE_BUTTON_WHEEL_LEFT,
	"wheel_right": MOUSE_BUTTON_WHEEL_RIGHT}
const WHEEL_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
## Extra key names accepted besides Godot's own (OS.find_keycode_from_string, case-insensitive).
const KEY_ALIASES := {"ESC": "Escape", "CONTROL": "Ctrl", "LCTRL": "Ctrl", "RCTRL": "Ctrl", "LSHIFT": "Shift",
	"RSHIFT": "Shift", "LALT": "Alt", "RALT": "Alt", "RETURN": "Enter", "SPACEBAR": "Space", "DEL": "Delete",
	"PGUP": "PageUp", "PGDN": "PageDown", "BACK": "Backspace"}
const MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
const COMMANDS := "k, mb, mm, move, click, shot, release_all, ping, status"

var port: int = 0
var rig_override: Node = null       # tests: the camera rig to turn instead of Game.player.rig
var sink: Array = []                # replies to commands submitted without a client (tests / in-process use)

var _server: TCPServer = null
var _clients: Array = []            # {"peer": StreamPeerTCP, "buf": PackedByteArray, "out": PackedByteArray, "open": bool}
var _queue: Array = []              # {"client", "id", "steps": Array (Callable | int frames to wait), "result", ["error"], ["silent"]}
var _wait_frames: int = 0
var _held_keys: Dictionary = {}     # keycode -> true
var _held_buttons: Dictionary = {}  # mouse button index -> true
var _pointer := Vector2(-1.0, -1.0) # virtual pointer in window pixels (< 0 = window centre)
var _pending_wheel: int = 0         # injected wheel notches that may still reach _input() this frame
var _commands: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	stop()


## Starts the TCP server on 127.0.0.1:<p_port> (0 = any free port; see `port` afterwards).
func start(p_port: int) -> Error:
	stop()
	if p_port < 0 or p_port > 65535:
		return ERR_INVALID_PARAMETER
	var server := TCPServer.new()
	var err := server.listen(p_port, BIND_ADDRESS)
	if err != OK:
		push_warning("QAInput: cannot listen on %s:%d (%s)" % [BIND_ADDRESS, p_port, error_string(err)])
		return err
	_server = server
	port = server.get_local_port()
	print("QAInput: listening on %s:%d" % [BIND_ADDRESS, port])
	return OK


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func stop() -> void:
	for c in _clients:
		(c as Dictionary)["open"] = false
		var peer: StreamPeerTCP = c["peer"]
		peer.disconnect_from_host()
	_clients.clear()
	if _server != null:
		_server.stop()
		_server = null
	release_all()


func _process(_delta: float) -> void:
	# Wheel notches injected last frame were delivered (or consumed by someone else) when the engine flushed
	# the input buffer at the start of this frame.
	_pending_wheel = 0
	_poll_network()
	pump()
	_flush_outgoing()


# --- Network ------------------------------------------------------------------------------------------------------

func _poll_network() -> void:
	if _server != null:
		while _server.is_connection_available():
			var peer: StreamPeerTCP = _server.take_connection()
			if peer == null:
				break
			if _clients.size() >= MAX_CLIENTS:
				peer.put_partial_data((JSON.stringify({"ok": false, "error": "too many clients"}) + "\n").to_utf8_buffer())
				peer.disconnect_from_host()
				continue
			peer.set_no_delay(true)
			_clients.append({"peer": peer, "buf": PackedByteArray(), "out": PackedByteArray(), "open": true})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop_client(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var res: Array = peer.get_partial_data(mini(n, MAX_LINE_BYTES))
			if int(res[0]) == OK:
				feed(c, res[1])


func _flush_outgoing() -> void:
	for c in _clients.duplicate():
		var out: PackedByteArray = c["out"]
		if out.is_empty():
			continue
		if out.size() > MAX_OUT_BYTES:
			_drop_client(c)      # the client stopped reading its replies
			continue
		var peer: StreamPeerTCP = c["peer"]
		var res: Array = peer.put_partial_data(out)
		if int(res[0]) == OK:
			c["out"] = out.slice(int(res[1]))
		else:
			_drop_client(c)


func _drop_client(c: Dictionary) -> void:
	c["open"] = false
	var peer: StreamPeerTCP = c["peer"]
	peer.disconnect_from_host()
	_clients.erase(c)
	if _clients.is_empty():
		# Commands already received still run in order; then nothing stays held down.
		_queue.append({"client": null, "id": null, "steps": [_op_release_all], "result": {}, "silent": true})


# --- Parsing ------------------------------------------------------------------------------------------------------

## Appends received bytes to the client's buffer and submits every complete line (lines may arrive split
## across packets, several lines may share one packet).
func feed(client: Dictionary, data: PackedByteArray) -> void:
	var buf: PackedByteArray = client.get("buf", PackedByteArray())
	buf.append_array(data)
	var nl := buf.find(10)
	while nl >= 0:
		var line := buf.slice(0, nl).get_string_from_utf8()
		buf = buf.slice(nl + 1)
		submit_line(line, client)
		nl = buf.find(10)
	if buf.size() > MAX_LINE_BYTES:
		buf = PackedByteArray()
		_enqueue_error(client, null, "line too long (max %d bytes)" % MAX_LINE_BYTES)
	client["buf"] = buf


## Parses one JSON line. Bad input is answered with an error reply (in order) and never raises.
func submit_line(line: String, client: Variant = null) -> void:
	var text := line.strip_edges()
	if text == "":
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_enqueue_error(client, null, "bad json: %s" % json.get_error_message())
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		_enqueue_error(client, null, "expected a JSON object")
		return
	submit(data, client)


## Queues one command; its reply is sent when it has run (pump()).
func submit(cmd: Dictionary, client: Variant = null) -> void:
	var item := {"client": client, "id": cmd.get("id"), "steps": [], "result": {}}
	var steps: Array = []
	var err := _build_steps(cmd, steps)
	if err != "":
		item["error"] = err
	else:
		item["steps"] = steps
	_queue.append(item)


func _enqueue_error(client: Variant, id: Variant, msg: String) -> void:
	_queue.append({"client": client, "id": id, "steps": [], "result": {}, "error": msg})


func _build_steps(cmd: Dictionary, steps: Array) -> String:
	if cmd.has("k"):
		var code := keycode_for(str(cmd["k"]))
		if code == KEY_NONE:
			return "unknown key '%s'" % str(cmd["k"])
		var down: Variant = _bool_arg(cmd.get("down"))
		if down == null:
			return "'down' must be true or false"
		steps.append(_op_key.bind(code, bool(down)))
	elif cmd.has("mb"):
		var b := int(MOUSE_BUTTONS.get(str(cmd["mb"]).to_lower(), 0))
		if b == 0:
			return "unknown mouse button '%s' (left, right, middle, wheel_up, wheel_down)" % str(cmd["mb"])
		var down: Variant = _bool_arg(cmd.get("down"))
		if down == null:
			return "'down' must be true or false"
		var at: Variant = null
		if cmd.has("x") or cmd.has("y"):
			at = _vec_arg([cmd.get("x"), cmd.get("y")])
			if at == null:
				return "'x' and 'y' must both be numbers"
			steps.append(_op_move_to.bind(at))
		steps.append(_op_button.bind(b, bool(down), at))
	elif cmd.has("mm"):
		var rel: Variant = _vec_arg(cmd["mm"])
		if rel == null:
			return "'mm' must be [dx, dy]"
		steps.append(_op_motion.bind(rel))
	elif cmd.has("move"):
		var to: Variant = _vec_arg(cmd["move"])
		if to == null:
			return "'move' must be [x, y]"
		steps.append(_op_move_to.bind(to))
	elif cmd.has("click"):
		var at: Variant = _vec_arg(cmd["click"])
		if at == null:
			return "'click' must be [x, y]"
		var b := int(MOUSE_BUTTONS.get(str(cmd.get("button", "left")).to_lower(), 0))
		if b == 0 or WHEEL_BUTTONS.has(b):
			return "'button' must be left, right or middle"
		steps.append(_op_move_to.bind(at))
		steps.append(_op_button.bind(b, true, at))
		steps.append(CLICK_HOLD_FRAMES)
		steps.append(_op_button.bind(b, false, at))
	elif cmd.has("shot"):
		var path := str(cmd["shot"]).strip_edges()
		if not path.is_absolute_path() or path.begins_with("res://") or path.get_extension().to_lower() != "png":
			return "'shot' must be an absolute .png path"
		steps.append(_op_shot.bind(path))
	elif cmd.has("release_all"):
		steps.append(_op_release_all)
	elif cmd.has("ping"):
		steps.append(func() -> Dictionary: return {"pong": true, "frame": Engine.get_process_frames()})
	elif cmd.has("status"):
		steps.append(func() -> Dictionary: return status())
	else:
		return "unknown command (expected one of: %s)" % COMMANDS
	return ""


## Keycode for a key name (W, SPACE, SHIFT, CTRL, ESC/ESCAPE, TAB, F1, 1..8, any Godot key name);
## KEY_NONE for unknown names and combinations ("Shift+W": send the keys one by one).
static func keycode_for(key_name: String) -> int:
	var n := key_name.strip_edges()
	if n == "" or n.contains("+"):
		return KEY_NONE
	var up := n.to_upper()
	if KEY_ALIASES.has(up):
		n = String(KEY_ALIASES[up])
	if n.length() == 1:
		var c := n.to_upper().unicode_at(0)
		if (c >= KEY_A and c <= KEY_Z) or (c >= KEY_0 and c <= KEY_9):
			return c
	return int(OS.find_keycode_from_string(n)) & KEY_CODE_MASK


static func _bool_arg(v: Variant) -> Variant:
	if v is bool:
		return v
	if (v is int or v is float) and (float(v) == 0.0 or float(v) == 1.0):
		return float(v) == 1.0
	return null


static func _vec_arg(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() != 2:
		return null
	var a: Array = v
	if not ((a[0] is int or a[0] is float) and (a[1] is int or a[1] is float)):
		return null
	var x := float(a[0])
	var y := float(a[1])
	if not is_finite(x) or not is_finite(y):
		return null
	return Vector2(clampf(x, -MAX_DELTA, MAX_DELTA), clampf(y, -MAX_DELTA, MAX_DELTA))


# --- Running commands ---------------------------------------------------------------------------------------------

## Runs queued commands in order until one has to wait for a later frame (a click holds its button for
## CLICK_HOLD_FRAMES). At most MAX_COMMANDS_PER_FRAME per frame, so a flood can never stall the game.
func pump() -> void:
	if _wait_frames > 0:
		_wait_frames -= 1
		if _wait_frames > 0:
			return
	var budget := MAX_COMMANDS_PER_FRAME
	while not _queue.is_empty() and budget > 0:
		var item: Dictionary = _queue[0]
		var steps: Array = item["steps"]
		while not steps.is_empty():
			var s: Variant = steps.pop_front()
			if s is int:
				_wait_frames = maxi(int(s), 1)
				return
			var r: Variant = (s as Callable).call()
			if r is Dictionary:
				if (r as Dictionary).has("error"):
					item["error"] = r["error"]
					steps.clear()
					break
				(item["result"] as Dictionary).merge(r, true)
		_queue.pop_front()
		budget -= 1
		_commands += 1
		if not bool(item.get("silent", false)):
			_finish(item)


func _finish(item: Dictionary) -> void:
	var reply := {}
	if item.has("error"):
		reply = {"ok": false, "error": String(item["error"])}
	else:
		reply = {"ok": true}
		reply.merge(item["result"], true)
	if item["id"] != null:
		reply["id"] = item["id"]
	_reply(item["client"], reply)


func _reply(client: Variant, reply: Dictionary) -> void:
	if client is Dictionary:
		var c: Dictionary = client
		if not bool(c.get("open", true)):
			return
		var out: PackedByteArray = c.get("out", PackedByteArray())
		out.append_array((JSON.stringify(reply) + "\n").to_utf8_buffer())
		c["out"] = out
	else:
		sink.append(reply)


func _op_key(code: int, down: bool) -> Dictionary:
	var was_held := _held_keys.has(code)
	if down:
		_held_keys[code] = true
	else:
		_held_keys.erase(code)
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.key_label = code as Key
	ev.pressed = down
	ev.echo = down and was_held      # a repeated "down" behaves like keyboard auto-repeat
	if MODIFIER_KEYS.has(code):
		ev.location = KEY_LOCATION_LEFT
	_apply_modifiers(ev)
	if down and not ev.ctrl_pressed and not ev.alt_pressed:
		ev.unicode = _unicode_for(code, ev.shift_pressed)
	Input.parse_input_event(ev)
	return {}


static func _unicode_for(code: int, shift: bool) -> int:
	if code >= KEY_A and code <= KEY_Z:
		return code if shift else code + 32
	if code >= KEY_0 and code <= KEY_9 and not shift:
		return code
	if code == KEY_SPACE:
		return 32
	return 0


func _apply_modifiers(ev: InputEventWithModifiers) -> void:
	ev.shift_pressed = _held_keys.has(KEY_SHIFT)
	ev.ctrl_pressed = _held_keys.has(KEY_CTRL)
	ev.alt_pressed = _held_keys.has(KEY_ALT)
	ev.meta_pressed = _held_keys.has(KEY_META)


func _op_button(button: int, down: bool, at: Variant) -> Dictionary:
	var pos: Vector2 = at if at is Vector2 else event_position()
	if WHEEL_BUTTONS.has(button):
		if not down:
			return {}     # a wheel notch is sent as press + release on "down"
		if _look_active():
			_pending_wheel += 1
		_parse_button(button, true, pos)
		_parse_button(button, false, pos)
		return {}
	if down:
		_held_buttons[button] = true
	else:
		_held_buttons.erase(button)
	_parse_button(button, down, pos)
	return {}


func _parse_button(button: int, down: bool, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button as MouseButton
	ev.pressed = down
	ev.position = pos
	ev.global_position = pos
	ev.factor = 1.0
	ev.button_mask = _button_mask()
	_apply_modifiers(ev)
	Input.parse_input_event(ev)


func _button_mask() -> MouseButtonMask:
	var m := 0
	for b in _held_buttons:
		m |= 1 << (int(b) - 1)
	return m as MouseButtonMask


func _op_motion(rel: Vector2) -> Dictionary:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var look := not captured and _look_active()
	var pos: Vector2
	if captured or look:
		pos = window_center()
		_pointer = Vector2(-1.0, -1.0)     # a captured cursor sits in the centre; menus open with it there
	else:
		pos = _clamp_to_window(pointer() + rel)
		_pointer = pos
	_parse_motion(pos, rel)
	var turned := false
	if look:
		# The rig only reads motion while the OS mouse is captured; QA no-capture runs never capture it, so the
		# delta goes to the same rotate_by() its _input() calls, in the same viewport-local units.
		var rig := camera_rig()
		if rig != null and bool(rig.get("input_enabled")) and not get_tree().paused:
			rig.call("rotate_by", local_delta(rel))
			turned = true
	return {"turned": turned}


func _op_move_to(to: Vector2) -> Dictionary:
	var old := pointer()
	_pointer = _clamp_to_window(to)
	# A captured cursor never moves; an absolute move must not turn the camera there.
	var rel := Vector2.ZERO if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else _pointer - old
	_parse_motion(_pointer, rel)
	return {"pos": [roundi(_pointer.x), roundi(_pointer.y)]}


func _parse_motion(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.screen_relative = rel
	ev.velocity = rel * 60.0
	ev.screen_velocity = rel * 60.0
	ev.button_mask = _button_mask()
	_apply_modifiers(ev)
	Input.parse_input_event(ev)


func _op_shot(path: String) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"error": "no screenshot in a headless run"}
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return {"error": "viewport image unavailable"}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		return {"error": "save_png failed: %s" % error_string(err)}
	return {"path": path, "size": [img.get_width(), img.get_height()]}


func _op_release_all() -> Dictionary:
	return {"released": release_all()}


## Releases every key and mouse button held through this server; returns how many.
func release_all() -> int:
	var n := 0
	for code in _held_keys.keys():
		_op_key(int(code), false)
		n += 1
	for b in _held_buttons.keys():
		_op_button(int(b), false, null)
		n += 1
	return n


# --- Mouse look (camera) & wheel zoom ----------------------------------------------------------------------------

## True while the game would have the mouse captured (Game._update_mouse: playing and no menu open).
func _look_active() -> bool:
	return Game.mode == "playing" and not Game.is_ui_open()


func camera_rig() -> Node:
	if rig_override != null and is_instance_valid(rig_override):
		return rig_override
	var pv: Variant = Game.player
	if is_instance_valid(pv):
		var r: Variant = (pv as Object).get("rig")
		if is_instance_valid(r) and r is Node and (r as Node).has_method("rotate_by"):
			return r
	return null


## A window-pixel delta in the root viewport's local (canvas) units - what Viewport.push_input hands to _input().
func local_delta(rel: Vector2) -> Vector2:
	return get_viewport().get_final_transform().affine_inverse().basis_xform(rel)


## Injected wheel notches in play turn into camera zoom like the rig's own _input() (which needs a captured
## mouse). Reached only if nothing handled the event first (build mode cycles its selection instead).
func _input(event: InputEvent) -> void:
	if _pending_wheel <= 0 or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or not (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		return
	_pending_wheel -= 1
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not _look_active() or get_tree().paused:
		return
	var rig := camera_rig()
	if rig == null or not bool(rig.get("input_enabled")) or not rig.has_method("zoom_by"):
		return
	var f: float = mb.factor
	var steps: float = clampf(f, 0.2, 4.0) if f > 0.0 else 1.0
	var step: float = 0.55
	var consts: Dictionary = rig.get_script().get_script_constant_map() if rig.get_script() != null else {}
	if consts.has("ZOOM_STEP"):
		step = float(consts["ZOOM_STEP"])
	if mb.is_action_pressed("zoom_in"):
		rig.call("zoom_by", -step * steps)
	elif mb.is_action_pressed("zoom_out"):
		rig.call("zoom_by", step * steps)


# --- Pointer ---------------------------------------------------------------------------------------------------------

func window_center() -> Vector2:
	var vp := get_viewport()
	return vp.get_final_transform() * (vp.get_visible_rect().size * 0.5)


func pointer() -> Vector2:
	return _pointer if _pointer.x >= 0.0 else window_center()


## Where a button press without coordinates happens: the window centre while the mouse is (or would be)
## captured, else the virtual pointer.
func event_position() -> Vector2:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _look_active():
		return window_center()
	return pointer()


func _clamp_to_window(p: Vector2) -> Vector2:
	var size := Vector2(DisplayServer.window_get_size())
	if size.x <= 0.0 or size.y <= 0.0:
		var vp := get_viewport()
		size = vp.get_final_transform().basis_xform(vp.get_visible_rect().size)
	return Vector2(clampf(p.x, 0.0, maxf(size.x - 1.0, 0.0)), clampf(p.y, 0.0, maxf(size.y - 1.0, 0.0)))


## Read-only state for replies and QA telemetry.
func status() -> Dictionary:
	var keys: Array = []
	for code in _held_keys:
		keys.append(OS.get_keycode_string(int(code)))
	var buttons: Array = []
	for b in _held_buttons:
		buttons.append(int(b))
	var p := pointer()
	return {"port": port, "listening": is_listening(), "clients": _clients.size(), "look": _look_active(),
		"pointer": [roundi(p.x), roundi(p.y)], "held_keys": keys, "held_buttons": buttons, "queued": _queue.size(),
		"commands": _commands, "mouse_mode": int(Input.mouse_mode), "debug_build": OS.is_debug_build(),
		"window_no_focus": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS),
		"project_no_focus": bool(ProjectSettings.get_setting("display/window/size/no_focus", false))}
