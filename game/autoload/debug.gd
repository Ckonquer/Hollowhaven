extends Node
## Development & QA harness driven ONLY by command-line user args (after "--").
## Nothing here is reachable from normal play. Cheats/shortcuts additionally require a debug build
## (OS.is_debug_build()), so the shipped release build cannot skip progression.
##
## Always available (harmless observation tools):
##   --shots=<dir> --shot-times=2,5.5 [--quit-at=8]    save viewport PNGs at those play-seconds
##   --log-state=<file> [--log-interval=1.0]          JSON lines: area, pos, hp, step, fps ...
##   --perf-log=<file>                                JSON lines per second: fps, frame ms, draw calls, memory
##   --save-dir=<dir>                                 use a dedicated (test) save folder
##   --seed=<int>                                     seed the global RNG (director uses its own seeded RNG)
##   --max-seconds=<n>                                hard watchdog quit
##   --no-focus-pause                                 don't auto-pause when the window loses focus
##   --windowed                                       ignore the fullscreen setting
##   --qa-telemetry=<file> [--qa-interval=0.1]        rich JSON-lines telemetry for the QA bot (src/qa/qa_telemetry.gd)
## Debug builds only (editor binary):
##   --area=surface|below [--spawn=<id>]              start a new game directly in an area
##   --load-save                                      continue from the save directly
##   --cams="x,y,z,yaw,pitch;..." --shot-dir=<dir>    free camera screenshots at poses, then quit
##   --hour=<0-24>  --flags=a,b  --give=item:n,item:n  --befriend=mochi,lumi:follow  --settings=key=val,key=val
##   --spawn-enemy=brambling:2,gloomling:1            spawn enemies near the player after the area loads
## NOTE: to get a real window size pass the user arg too:  ... --resolution 1600x900 -- --windowed ...
##   --preview=<res://script.gd> [--shot-dir=<dir>]   preview stage: spin a node built from a script

var args: Dictionary = {}
var headless: bool = false
var keep_running_unfocused: bool = false
var _t := 0.0
var _shot_times: Array = []
var _shot_dir := ""
var _quit_at := -1.0
var _log_file: FileAccess
var _log_interval := 1.0
var _log_t := 0.0
var _perf_file: FileAccess
var _perf_t := 0.0
var _max_seconds := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	headless = DisplayServer.get_name() == "headless"
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var eq := s.find("=")
			if eq > 0:
				args[s.substr(2, eq - 2)] = s.substr(eq + 1)
			else:
				args[s.substr(2)] = "true"
	keep_running_unfocused = args.has("no-focus-pause") or headless or args.has("cams") or args.has("shots")
	if args.has("save-dir"):
		SaveSystem.set_save_dir(String(args["save-dir"]))
	if args.has("seed"):
		seed(int(args["seed"]))
	if args.has("shots"):
		_shot_dir = String(args["shots"])
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		for t in String(args.get("shot-times", "3")).split(","):
			_shot_times.append(float(t))
	if args.has("quit-at"):
		_quit_at = float(args["quit-at"])
	if args.has("max-seconds"):
		_max_seconds = float(args["max-seconds"])
	if args.has("log-state"):
		_log_file = FileAccess.open(String(args["log-state"]), FileAccess.WRITE)
		_log_interval = float(args.get("log-interval", "1.0"))
	if args.has("perf-log"):
		_perf_file = FileAccess.open(String(args["perf-log"]), FileAccess.WRITE)
	if args.has("qa-telemetry"):
		var qa: Node = load("res://src/qa/qa_telemetry.gd").new()
		qa.name = "QATelemetry"
		qa.setup(String(args["qa-telemetry"]), float(args.get("qa-interval", "0.1")))
		add_child(qa)
	if is_cheat_allowed() and args.has("settings"):
		for kv in String(args["settings"]).split(","):
			var p := kv.split("=")
			if p.size() == 2:
				var cur = Settings.get_value(p[0])
				var v: Variant = p[1]
				if cur is bool: v = p[1] == "true"
				elif cur is int: v = int(p[1])
				elif cur is float: v = float(p[1])
				Settings.set_value(p[0], v)


func is_cheat_allowed() -> bool:
	return OS.is_debug_build()


func has_arg(name: String) -> bool:
	return args.has(name)


func arg(name: String, default: String = "") -> String:
	return String(args.get(name, default))


## Called by Game.boot(). Returns true if the harness took over the boot flow.
func handle_boot() -> bool:
	if not is_cheat_allowed():
		return false
	if args.has("preview"):
		get_tree().change_scene_to_file("res://tests/preview/preview_stage.tscn")
		return true
	if args.has("area"):
		_boot_area.call_deferred()
		return true
	if args.has("load-save"):
		Game.continue_game.call_deferred()
		return true
	return false


func _boot_area() -> void:
	GameState.new_game()
	Settings.set_value("comfort_confirmed", true)
	if args.has("hour"):
		GameState.total_minutes = float(args["hour"]) * 60.0
	for f in arg("flags").split(",", false):
		GameState.set_flag(f, true)
	for g in arg("give").split(",", false):
		var p := g.split(":")
		GameState.give_item(p[0], int(p[1]) if p.size() > 1 else 1)
	# --befriend=mochi,lumi:follow  (":follow" makes that one the active follower)
	for entry in arg("befriend").split(",", false):
		var parts := String(entry).split(":")
		var c: String = parts[0]
		GameState.companion(c)["befriended"] = true
		GameState.companion(c)["assignment"] = "home"
		if parts.size() > 1 and parts[1] == "follow":
			GameState.set_companion_assignment(c, "follow")
	await Game.load_area(arg("area", "surface"), arg("spawn", "haven_start"), false)
	if args.has("spawn-enemy") and ResourceLoader.exists("res://src/enemies/enemy_factory.gd"):
		var ef: Script = load("res://src/enemies/enemy_factory.gd")
		if ef != null and ef.has_method("debug_spawn_from_args"):
			ef.debug_spawn_from_args()
	if args.has("cams"):
		_run_cams()


func _run_cams() -> void:
	var dir := arg("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 800.0
	get_tree().current_scene.add_child(cam)
	cam.make_current()
	if Game.player and Game.player.has_method("set_input_enabled"):
		Game.player.set_input_enabled(false)
	var poses := arg("cams").split(";", false)
	for i in poses.size():
		var v := poses[i].split(",")
		if v.size() < 5:
			continue
		cam.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		cam.rotation_degrees = Vector3(float(v[4]), float(v[3]), 0.0)
		cam.make_current()
		for k in 20:
			await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("cam_%02d.png" % i))
		print("Debug: saved cam shot %d" % i)
	get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	if not _shot_times.is_empty() and _t >= float(_shot_times[0]):
		var st := float(_shot_times.pop_front())
		save_screenshot(_shot_dir.path_join("shot_%06.1f.png" % st))
	if _quit_at > 0.0 and _t >= _quit_at:
		_quit_at = -1.0
		get_tree().quit()
	if _max_seconds > 0.0 and _t >= _max_seconds:
		print("Debug: watchdog quit after %.0f s" % _max_seconds)
		get_tree().quit(3)
	if _log_file != null:
		_log_t += delta
		if _log_t >= _log_interval:
			_log_t = 0.0
			_log_file.store_line(JSON.stringify(state_snapshot()))
			_log_file.flush()
	if _perf_file != null:
		_perf_t += delta
		if _perf_t >= 1.0:
			_perf_t = 0.0
			_perf_file.store_line(JSON.stringify({
				"t": snappedf(_t, 0.01), "area": Game.area_id, "zone": Game.zone_id,
				"fps": Engine.get_frames_per_second(),
				"frame_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
				"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
				"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			}))
			_perf_file.flush()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		var dir := "user://screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		var dt := Time.get_datetime_string_from_system().replace(":", "-")
		save_screenshot(dir.path_join("hollowhaven_%s.png" % dt))
		Events.notify.emit("Screenshot saved.", "info")


func save_screenshot(path: String) -> void:
	if headless:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Debug: screenshot ", path)


## Compact state for telemetry logs and QA evidence.
func state_snapshot() -> Dictionary:
	var d := {"t": snappedf(_t, 0.01), "mode": Game.mode, "area": Game.area_id, "zone": Game.zone_id,
		"step": GameState.quests.current_id(), "day": GameState.day(), "hour": snappedf(GameState.hour(), 0.01),
		"fps": Engine.get_frames_per_second(), "ui_open": Game.is_ui_open(), "paused": get_tree().paused}
	if Game.player != null and is_instance_valid(Game.player):
		var p: Vector3 = Game.player.global_position
		d["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
		d["hp"] = GameState.player.get("hp")
	d["inv"] = GameState.inventory.totals()
	d["keys"] = GameState.key_items.duplicate()
	d["companions"] = {}
	for id in GameState.companions:
		d["companions"][id] = GameState.companions[id]["assignment"]
	return d
