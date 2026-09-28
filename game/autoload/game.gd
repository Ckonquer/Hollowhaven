extends Node
## Game flow: title <-> areas, spawning the player/companions/UI, death & respawn, pause and
## menus (mouse capture), autosaves, the world clock and the chapter ending.
## Other systems talk to the flow through these methods; they never change scenes themselves.

const AREAS := {"surface": "res://scenes/surface.tscn", "below": "res://scenes/below.tscn"}
const TITLE_SCENE := "res://scenes/title.tscn"
const PLAYER_SCRIPT := "res://src/player/player.gd"
const UI_ROOT_SCRIPT := "res://src/ui/ui_root.gd"
const COMPANION_SPAWNER := "res://src/companions/companion_spawner.gd"
const WORLD_ITEM_SCRIPT := "res://src/world/common/world_item.gd"
const BUILDING_SYSTEM := "res://src/building/building_system.gd"
const DIRECTOR_SCRIPT := "res://src/horror/director.gd"
const TEST_AREAS := {"arena": "res://tests/preview/arena.tscn"}   # debug builds only
const FALLBACK_PLAYER := "res://tests/preview/fallback_player.gd"
const FALLBACK_UI := "res://tests/preview/fallback_ui.gd"

var mode: String = "boot"          # boot | title | playing | dead | cutscene | loading
var player: Node3D = null          # the player CharacterBody3D (src/player/player.gd)
var ui: Node = null                # gameplay UI root (src/ui/ui_root.gd), child of this autoload
var area: Node = null              # current area root (extends src/world/area_base.gd)
var area_id: String = ""
var companion_nodes: Dictionary = {}   # companion id -> node in the current area
var zone_id: String = ""
var in_safe_zone: bool = true
var director: Node = null          # horror director in the Below (src/horror/director.gd)

## Quiet surface autosave: every AUTOSAVE_SECONDS of unpaused play on the surface (bed, lantern, mine
## and manual saves restart the countdown). Retries every AUTOSAVE_RETRY s while saving isn't allowed.
const AUTOSAVE_SECONDS := 300.0
const AUTOSAVE_RETRY := 5.0

var _ui_stack: Array = []
var _transitioning := false
var _zone_timer := 0.0
var autosave_enabled: bool = true   # off in headless runs (tests drive _tick_autosave() directly)
var _autosave_t := 0.0
var _focus_lost := false            # the window lost focus and no pause menu has covered it yet
var _closing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Closing the window (title-bar X, Alt+F4, OS shutdown) goes through _on_close_requested() so the
	# journey is saved first instead of the engine quitting on the spot.
	get_tree().set_auto_accept_quit(false)
	autosave_enabled = DisplayServer.get_name() != "headless"
	Events.game_saved.connect(_on_game_saved)
	Events.area_loaded.connect(_on_area_loaded_focus_check)


func _process(delta: float) -> void:
	if mode != "playing" or get_tree().paused:
		return
	GameState.advance_clock(delta)
	if autosave_enabled:
		_tick_autosave(delta)
	_zone_timer += delta
	if _zone_timer >= 0.4 and player != null and is_instance_valid(player) and area != null:
		_zone_timer = 0.0
		var z: String = area.get_zone_at(player.global_position) if area.has_method("get_zone_at") else ""
		if z != zone_id:
			zone_id = z
			Events.zone_entered.emit(z)
		var safe: bool = area.is_safe_zone(player.global_position) if area.has_method("is_safe_zone") else false
		if safe != in_safe_zone:
			in_safe_zone = safe
			Events.safe_zone_changed.emit(safe)


func _notification(what: int) -> void:
	# Alt-tab / focus loss: pause so nothing happens while Krystal isn't looking. Focus lost while
	# the game can't pause (loading, death screen, lift ride, ending) is remembered and the pause menu
	# opens as soon as play resumes (_pause_if_focus_lost).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_lost = true
		_pause_if_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_lost = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()


## Opens the pause menu if the window lost focus and nothing has paused the game since.
func _pause_if_focus_lost() -> void:
	if not _focus_lost or mode != "playing" or _transitioning or ui == null or Debug.keep_running_unfocused:
		return
	if get_tree().paused:
		return
	open_panel("pause")
	if get_tree().paused:
		_focus_lost = false


## area_loaded is emitted just before load_area's fade-in; check once the UI root has reset its
## panels for the new area (deferred), so the pause menu is not closed again straight away.
func _on_area_loaded_focus_check(_area_id: String) -> void:
	if _focus_lost:
		_pause_if_focus_lost.call_deferred()


# --- Saving on close & autosave --------------------------------------------------------------------

## Saves the journey before the window closes, when a manual save would be allowed (on the surface,
## nothing chasing Krystal). Underground the lantern saves stand. Returns true when a save was written.
func save_before_close() -> bool:
	if not GameState.active or mode != "playing":
		return false
	if not bool(can_manual_save().get("ok", false)):
		return false
	return SaveSystem.save_game(true)


## The OS asked the window to close: save what can be saved, keep the settings, then always quit
## (a refused save never keeps the window open).
func _on_close_requested() -> void:
	if _closing:
		return
	_closing = true
	save_before_close()
	Settings.save()
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	get_tree().quit()


## Advances the surface autosave countdown; saves quietly when it runs out and saving is allowed
## (no menu open, not in build mode, nothing chasing Krystal). Returns true when it saved.
func _tick_autosave(delta: float) -> bool:
	if mode != "playing" or area_id != "surface" or not GameState.active:
		return false
	_autosave_t += delta
	if _autosave_t < AUTOSAVE_SECONDS:
		return false
	var building := false
	if player != null and is_instance_valid(player):
		var bm: Variant = player.get("build_mode_active")
		building = bm is bool and bm
	if _transitioning or is_ui_open() or building or not bool(can_manual_save().get("ok", false)):
		_autosave_t = AUTOSAVE_SECONDS - AUTOSAVE_RETRY
		return false
	_autosave_t = 0.0
	return SaveSystem.save_game(true)


func _on_game_saved(ok: bool) -> void:
	if ok:
		_autosave_t = 0.0


# --- Title / new game / continue ---------------------------------------------------

func boot() -> void:
	if Debug.handle_boot():
		return
	goto_title()


func goto_title() -> void:
	if area_id != "":
		Events.area_exiting.emit(area_id)
	area_id = ""
	mode = "title"
	GameState.active = false
	_ui_stack.clear()
	get_tree().paused = false
	_free_gameplay_nodes()
	if ui != null:
		ui.queue_free()
		ui = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


func new_game() -> void:
	GameState.new_game()
	await load_area("surface", "haven_start", false)
	# Save straight away (quietly) so Continue exists from the first minute.
	if GameState.active and area_id == "surface":
		SaveSystem.save_game(true)
	Events.hint.emit("intro_move", "Move with {move}. Hold {sprint} to sprint. Press {help} any time to see all controls.")
	if ui != null and ui.has_method("show_chapter_card"):
		ui.show_chapter_card("Chapter One", "The Dimming Ward")


func continue_game() -> bool:
	if not SaveSystem.load_game():
		return false
	var a: String = String(GameState.player.get("area", "surface"))
	if not AREAS.has(a):
		a = "surface"
	await load_area(a, String(GameState.player.get("spawn", "haven_respawn")), true)
	# load_game() announces a backup restore from the title, where no toast widget exists yet:
	# repeat it now that the gameplay UI is up so Krystal is actually told.
	if SaveSystem.recovered_from_backup:
		Events.notify.emit(SaveSystem.BACKUP_NOTICE, "warn")
	return true


# --- Areas -------------------------------------------------------------------------------

## Loads an area scene and places the player. use_saved_position: surface only; the saved position
## is validated (ground below, inside the world) and falls back to the spawn point otherwise.
func load_area(target_area: String, spawn_id: String, use_saved_position: bool = false) -> void:
	if _transitioning:
		return
	_transitioning = true
	_autosave_t = 0.0
	var prev_mode := mode
	mode = "loading"
	if ui != null and ui.has_method("fade_out"):
		await ui.fade_out(0.45)
	if area_id != "":
		Events.area_exiting.emit(area_id)
	get_tree().paused = false
	_ui_stack.clear()
	Events.ui_stack_changed.emit(0)
	_free_gameplay_nodes()
	var scene_path: String = AREAS.get(target_area, "")
	if scene_path == "" and Debug.is_cheat_allowed():
		scene_path = TEST_AREAS.get(target_area, "")
	if scene_path == "":
		scene_path = AREAS["surface"]
		target_area = "surface"
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Game: cannot load area %s (%s)" % [target_area, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	area = get_tree().current_scene
	area_id = target_area
	zone_id = ""
	GameState.player["area"] = target_area
	if ui == null:
		ui = _safe_new(UI_ROOT_SCRIPT, FALLBACK_UI)
		add_child(ui)
	# Player
	player = _safe_new(PLAYER_SCRIPT, FALLBACK_PLAYER)
	area.add_child(player)
	var use_saved := use_saved_position and target_area == "surface"
	var had_spawn: bool = area.get("spawns") is Dictionary and area.spawns.has(spawn_id)
	var xform := _spawn_transform(spawn_id, use_saved)
	if player.has_method("read_from_state"):
		player.read_from_state()
	player.teleport(xform)
	GameState.player["spawn"] = spawn_id
	# Area systems: building (surface) and the horror director (below).
	# BuildMode is added after the player on purpose so its _input() runs first.
	if target_area == "surface" or (target_area == "arena" and Debug.is_cheat_allowed()):
		var bs: Script = _safe_load(BUILDING_SYSTEM)
		if bs != null and bs.has_method("attach"):
			bs.attach(area)
		# Structures (e.g. the bed) register their spawns deferred: re-place the player if the
		# requested spawn only exists now.
		await get_tree().process_frame
		if not use_saved and not had_spawn and area.get("spawns") is Dictionary and area.spawns.has(spawn_id):
			player.teleport(area.get_spawn(spawn_id))
	director = null
	if target_area == "below":
		var ds: Script = _safe_load(DIRECTOR_SCRIPT)
		if ds != null:
			director = ds.new()
			director.name = "HorrorDirector"
			if director.has_method("setup"):
				director.setup({"area": area, "seed": int(Debug.arg("seed", "0")) if Debug.has_arg("seed") else randi()})
			area.add_child(director)
	# Companions and persistent dropped items
	var spawner: Script = _safe_load(COMPANION_SPAWNER)
	if spawner != null and spawner.has_method("spawn_for_area"):
		companion_nodes = spawner.spawn_for_area(area, target_area, player)
	for d in GameState.dropped_in_area(target_area):
		spawn_dropped_item(String(d["uid"]))
	if area.has_method("on_player_spawned"):
		area.on_player_spawned(player)
	mode = "playing"
	_update_mouse()
	Events.area_loaded.emit(target_area)
	GameState.request_quest_eval()
	_transitioning = false
	if ui != null and ui.has_method("fade_in"):
		await ui.fade_in(0.6)
	if prev_mode == "title":
		pass
	_pause_if_focus_lost()


## Loads a script, returning null (with an error) instead of crashing if it is missing or broken.
func _safe_load(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		push_error("Game: script failed to load: " + path)
		return null
	return s


## Instantiates a script with a fallback (keeps development builds playable while modules change).
func _safe_new(path: String, fallback: String) -> Node:
	var s := _safe_load(path)
	if s == null:
		s = _safe_load(fallback)
	if s == null:
		push_error("Game: neither %s nor its fallback could be loaded" % path)
		return Node3D.new() if fallback.contains("player") else CanvasLayer.new()
	return s.new()


func _spawn_transform(spawn_id: String, use_saved: bool) -> Transform3D:
	var fallback: Transform3D = area.get_spawn(spawn_id) if area.has_method("get_spawn") else Transform3D.IDENTITY
	if use_saved:
		var p = GameState.player.get("pos")
		if p is Array and p.size() == 3:
			var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
			if area.has_method("validate_position"):
				var ok: Variant = area.validate_position(pos)
				if ok is Vector3:
					var t := Transform3D(Basis(Vector3.UP, float(GameState.player.get("yaw", 0.0))), ok)
					return t
	return fallback


## Travel between areas (mine entrance / exit). Autosaves after arriving.
func change_area(target_area: String, spawn_id: String) -> void:
	if _transitioning:
		return
	if player != null and is_instance_valid(player) and player.has_method("write_to_state"):
		player.write_to_state()
	await load_area(target_area, spawn_id, false)
	# spawn_id is only where she arrives (the mine mouth / the landing). Her return point stays the
	# bed or the Haven on the surface, and the last lantern she rested at in the Below.
	var rs: String = spawn_id
	if target_area == "surface":
		rs = _bed_spawn_or("haven_respawn")
	elif target_area == "below":
		rs = _below_return_point(spawn_id)
	set_respawn(target_area, rs)
	SaveSystem.save_game()


## The Below return point on (re-)entering: the lantern last used (GameState.player["below_respawn"]),
## or for saves made before that was remembered, the deepest lit lantern (area.checkpoints lists them
## from the entrance inwards). Falls back to `default_spawn`.
func _below_return_point(default_spawn: String) -> String:
	if area == null or not (area.get("spawns") is Dictionary):
		return default_spawn
	var spawns: Dictionary = area.get("spawns")
	var last: String = String(GameState.player.get("below_respawn", ""))
	if last != "":
		return last if spawns.has(last) else default_spawn
	var best: String = default_spawn
	var cps: Variant = area.get("checkpoints")
	if cps is Dictionary:
		for id in cps:
			var cp: Variant = cps[id]
			if not (cp is Node) or not is_instance_valid(cp):
				continue
			var lit: Variant = cp.get("lit")
			var sp: Variant = cp.get("spawn_id")
			if lit is bool and lit and sp is String and spawns.has(sp):
				best = String(sp)
	return best


func _bed_spawn_or(default_spawn: String) -> String:
	for uid in GameState.structures:
		var st: Dictionary = GameState.structures[uid]
		var data = st.get("data", {})
		if String(st.get("id", "")) == "bed" and data is Dictionary and bool(data.get("respawn", false)):
			return "bed"
	return default_spawn


## Sets where Krystal wakes after being defeated (bed, checkpoint lanterns, mine entry...).
func set_respawn(target_area: String, spawn_id: String) -> void:
	GameState.player["respawn_area"] = target_area
	GameState.player["respawn_spawn"] = spawn_id
	if target_area == "below":
		# Remembered separately so a trip to the surface (whose respawn is the bed/Haven) doesn't
		# forget the lantern: change_area restores it when she comes back down.
		GameState.player["below_respawn"] = spawn_id


func _free_gameplay_nodes() -> void:
	director = null
	player = null
	companion_nodes = {}
	area = null


# --- Dropped items -------------------------------------------------------------------------

func spawn_dropped_item(uid: String) -> void:
	var d := GameState.get_dropped(uid)
	if d.is_empty() or area == null or String(d["area"]) != area_id:
		return
	var s: Script = _safe_load(WORLD_ITEM_SCRIPT)
	if s != null and s.has_method("spawn_from_state"):
		s.spawn_from_state(area, uid)


# --- Death & respawn ------------------------------------------------------------------------

func on_player_died() -> void:
	if mode != "playing":
		return
	mode = "dead"
	GameState.stats["deaths"] = int(GameState.stats.get("deaths", 0)) + 1
	Events.player_died.emit()
	if ui != null and ui.has_method("show_death"):
		await ui.show_death()
	else:
		await get_tree().create_timer(2.0).timeout
	await respawn_player()


func respawn_player() -> void:
	var ra: String = String(GameState.player.get("respawn_area", "surface"))
	var rs: String = String(GameState.player.get("respawn_spawn", "haven_respawn"))
	GameState.player["hp"] = float(GameState.player.get("max_hp", 100.0))
	GameState.player["stamina"] = float(GameState.player.get("max_stamina", 100.0))
	if ra != area_id:
		mode = "playing"
		await load_area(ra, rs, false)
	else:
		if ui != null and ui.has_method("fade_out"):
			await ui.fade_out(0.3)
		if player != null and is_instance_valid(player):
			if player.has_method("read_from_state"):
				player.read_from_state()
			player.teleport(area.get_spawn(rs))
		for id in companion_nodes:
			var c = companion_nodes[id]
			if is_instance_valid(c) and c.has_method("on_player_respawned"):
				c.on_player_respawned()
		mode = "playing"
		_update_mouse()
		if ui != null and ui.has_method("fade_in"):
			await ui.fade_in(0.6)
	Events.player_respawned.emit()
	Events.notify.emit("Krystal wakes up, a little shaken but safe.", "info")
	_pause_if_focus_lost()


# --- Menus, pause & mouse --------------------------------------------------------------------

## Opens a UI panel by name via the UI root: inventory, crafting, storage, journal, map, pause,
## settings, controls, companion. Panels that should freeze the world call set_paused(true).
func open_panel(panel: String, args: Dictionary = {}) -> void:
	if ui != null and ui.has_method("open"):
		ui.open(panel, args)


func close_panel(panel: String) -> void:
	if ui != null and ui.has_method("close"):
		ui.close(panel)


## UI panels register themselves while open so gameplay input stops and the cursor is shown.
func push_ui(panel: String) -> void:
	if not _ui_stack.has(panel):
		_ui_stack.append(panel)
	_update_mouse()
	Events.ui_stack_changed.emit(_ui_stack.size())


func pop_ui(panel: String) -> void:
	_ui_stack.erase(panel)
	_update_mouse()
	Events.ui_stack_changed.emit(_ui_stack.size())


func is_ui_open() -> bool:
	return not _ui_stack.is_empty()


func set_paused(p: bool) -> void:
	if get_tree().paused == p:
		return
	get_tree().paused = p
	Events.paused_changed.emit(p)


## True when the player character should respond to gameplay input.
func gameplay_input_allowed() -> bool:
	return mode == "playing" and _ui_stack.is_empty() and not _transitioning and not get_tree().paused


func _update_mouse() -> void:
	if Debug.headless:
		return
	var want_captured := mode == "playing" and _ui_stack.is_empty()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want_captured else Input.MOUSE_MODE_VISIBLE


func set_cutscene(active: bool) -> void:
	mode = "cutscene" if active else "playing"
	_update_mouse()
	Events.cutscene_changed.emit(active)
	if not active:
		_pause_if_focus_lost()


# --- Saving rules ------------------------------------------------------------------------------

## Manual saving is allowed on the surface when no enemy is actively hunting Krystal.
## Underground, progress is saved at checkpoint lanterns.
func can_manual_save() -> Dictionary:
	if mode != "playing" and mode != "loading":
		return {"ok": false, "reason": "You can't save right now."}
	if area_id != "surface":
		return {"ok": false, "reason": "Underground, rest at a lit lantern to save."}
	if player != null and is_instance_valid(player):
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.has_method("is_threatening") and e.is_threatening() and e.global_position.distance_to(player.global_position) < 20.0:
				return {"ok": false, "reason": "You can't save while something is chasing you."}
	return {"ok": true, "reason": ""}


# --- Chapter ending ---------------------------------------------------------------------------------

## Called by the Ward Stone when Krystal returns the Heartseed.
func complete_chapter() -> void:
	if GameState.get_flag("ward_restored"):
		return
	GameState.take_item("heartseed", 1)
	set_cutscene(true)
	GameState.set_flag("ward_restored", true)
	if area != null and area.has_method("play_restoration"):
		await area.play_restoration()
	for id in companion_nodes:
		var c = companion_nodes[id]
		if is_instance_valid(c) and c.has_method("react"):
			c.react("celebrate")
	Events.chapter_completed.emit()
	if ui != null and ui.has_method("show_ending"):
		await ui.show_ending()
	set_cutscene(false)
	GameState.request_quest_eval()
	await get_tree().create_timer(0.5).timeout
	SaveSystem.save_game()


func quit_to_title() -> void:
	goto_title()


func quit_game() -> void:
	Settings.save()
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await get_tree().process_frame
	get_tree().quit()
