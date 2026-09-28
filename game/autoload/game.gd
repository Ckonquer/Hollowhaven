extends Node
## Game flow: title <-> areas, spawning the player/companions/UI, death & respawn, pause and
## menus (mouse capture), autosaves, the world clock and the chapter endings.
## Other systems talk to the flow through these methods; they never change scenes themselves.
## Chapter Two (docs/CHAPTER_TWO_SPEC.md §1, §8): the new areas, per-area saving rules, per-area respawn
## memory, the Lantern Road (can_fast_travel / travel_lantern_road), companion_present() and the
## Chapter Two ending (complete_chapter_two), which never re-runs complete_chapter().

const AREAS := {
	"surface": "res://scenes/surface.tscn",
	"below": "res://scenes/below.tscn",
	"tobin_annex": "res://scenes/tobin_annex.tscn",
	"hallowmere_reach": "res://scenes/hallowmere_reach.tscn",
	"moonveil_manor": "res://scenes/moonveil_manor.tscn",
	"hushed_works": "res://scenes/hushed_works.tscn",
	"echo_trial": "res://scenes/echo_trial.tscn",
}
## Areas where Krystal may save anywhere (manual save, the quiet autosave, save-on-close) as long as
## nothing is chasing her within 20 m and no boss encounter is active.
const SAFE_SAVE_AREAS := ["surface", "hallowmere_reach"]
## Every other registered area allows saving only inside a safe zone (lanterns, checkpoints, refuges),
## except these, which keep their own rule (the Below saves at its lanterns only; trials never save).
const SAVE_REFUSALS := {
	"below": "Underground, rest at a lit lantern to save.",
	"echo_trial": "Trials aren't saved. Leave the trial to save your journey.",
}
## Outdoor areas: Continue resumes at the saved position (validated by the area), not at a spawn.
const OUTDOOR_AREAS := ["surface", "hallowmere_reach"]
## Areas whose arrival neither saves nor moves the respawn point (a trial always returns to its origin).
const TRANSIENT_AREAS := ["echo_trial"]
## Areas that get the horror director (created before companions spawn). The Hushed Works hands the
## director its own hw_* event table (data/horror_events.gd WORKS_EVENTS) through area.director_config().
const DIRECTOR_AREAS := ["below", "hushed_works"]
## Where Krystal wakes in a Chapter Two area until she has rested somewhere there (spec §1).
const AREA_DEFAULT_RESPAWN := {
	"hallowmere_reach": "commons_arch",
	"tobin_annex": "annex_entry",
	"moonveil_manor": "manor_entry",
	"hushed_works": "service_landing",
}
const THREAT_RADIUS := 20.0                 # an enemy hunting her this close blocks saving and travel
const COMPANION_PRESENT_RADIUS := 25.0      # support/passives only count this close (spec §5)
## The Lantern Road's home destination (always offered once any arch is lit).
const HAVEN_DESTINATION := {"id": "haven", "name": "The Haven (home)", "area": "surface", "spawn": "haven_respawn"}
## Chapter Two ending (spec §3.5 ledger, MP §17 ending card).
const CH2_COMPLETE_FLAG := "chapter_two_complete"
const CH2_REWARD_ID := "rw_ch2_feast"
const CH2_FEAST_REWARDS_DEFAULT := {}   # the Wardlight is the ch2_homecoming reward (data/quests_ch2.gd)
const QUESTS_CH2_DATA := "res://data/quests_ch2.gd"
const CH2_ENDING_TEXT := "The lanterns shine beyond the trees. The quiet below is quiet again. There are pumpkins to plant, walls to raise, and friends waiting by the fire. The road will keep. Tonight is yours."
const Reach := preload("res://data/hallowmere_layout.gd")
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

## Quiet autosave: every AUTOSAVE_SECONDS of unpaused play where saving is allowed (can_manual_save; bed, lantern, mine
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
var _bosses: Dictionary = {}        # boss id -> true while its encounter is active (saving/travel)
var _ch2_ending_running := false
var _travel_seq := 0                # change_area() calls; a newer trip supersedes an older one's bookkeeping


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Closing the window (title-bar X, Alt+F4, OS shutdown) goes through _on_close_requested() so the
	# journey is saved first instead of the engine quitting on the spot.
	get_tree().set_auto_accept_quit(false)
	autosave_enabled = DisplayServer.get_name() != "headless"
	Events.game_saved.connect(_on_game_saved)
	Events.area_loaded.connect(_on_area_loaded_focus_check)
	Events.boss_encounter_changed.connect(_on_boss_encounter_changed)
	Events.boss_health_changed.connect(_on_boss_health_changed)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.area_exiting.connect(_on_area_exiting_bosses)


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
			# Map discovery (spec §10): every landmark zone entered is remembered per area.
			if z != "" and GameState.has_method("discover"):
				GameState.discover(area_id, z)
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

## Saves the journey before the window closes, when a manual save would be allowed (see
## can_manual_save: the surface or the Reach with nothing chasing Krystal, or a safe zone of another
## Chapter Two area). Underground the lantern saves stand. Returns true when a save was written.
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


## Advances the quiet autosave countdown; saves when it runs out and saving is allowed (no menu open,
## not in build mode, can_manual_save()). Counts only in areas where saving can ever be allowed (not
## the Below, not a trial). Returns true when it saved.
func _tick_autosave(delta: float) -> bool:
	if mode != "playing" or not area_allows_saving(area_id) or not GameState.active:
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
	_ch2_ending_running = false   # an ending interrupted by quitting (its UI freed mid-await) never resumes
	_ui_stack.clear()
	get_tree().paused = false
	_free_gameplay_nodes()
	if ui != null:
		ui.queue_free()
		ui = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


## Starts a new journey. `look` (optional) is the appearance chosen on the creation screen
## (data/appearance.gd look dictionary); it is stored in GameState before the first save.
func new_game(look: Dictionary = {}) -> void:
	GameState.new_game()
	_apply_new_game_look(look)
	await load_area("surface", "haven_start", false)
	# Save straight away (quietly) so Continue exists from the first minute.
	if GameState.active and area_id == "surface":
		SaveSystem.save_game(true)
	Events.hint.emit("intro_move", "Move with {move}. Hold {sprint} to sprint. Press {help} any time to see all controls.")
	if ui != null and ui.has_method("show_chapter_card"):
		ui.show_chapter_card("Chapter One", "The Dimming Ward")


## Merges a creation-screen look into GameState.appearance (schema v2). Works before and after the
## core-save module lands: uses GameState.set_appearance() when it exists, else the `appearance`
## property, else does nothing.
func _apply_new_game_look(look: Dictionary) -> void:
	if look.is_empty():
		return
	if GameState.has_method("set_appearance"):
		GameState.call("set_appearance", look.duplicate(true))
	elif "appearance" in GameState:
		var cur: Variant = GameState.get("appearance")
		var merged: Dictionary = (cur as Dictionary).duplicate(true) if cur is Dictionary else {}
		for k in look:
			var v: Variant = look[k]
			merged[k] = (v as Dictionary).duplicate(true) if v is Dictionary else v
		GameState.set("appearance", merged)
	else:
		return
	Events.appearance_changed.emit()


func continue_game() -> bool:
	if not SaveSystem.load_game():
		return false
	var a: String = String(GameState.player.get("area", "surface"))
	var spawn: String = String(GameState.player.get("spawn", "haven_respawn"))
	var use_saved := true
	# A trial is never resumed (spec §1: it always returns to its origin): a save that was written inside
	# one (by some other system) continues at the respawn point, which change_area never moves into a trial.
	if TRANSIENT_AREAS.has(a):
		a = String(GameState.player.get("respawn_area", "surface"))
		spawn = String(GameState.player.get("respawn_spawn", "haven_respawn"))
		use_saved = false
		if TRANSIENT_AREAS.has(a) or not AREAS.has(a):
			a = "surface"
			spawn = "haven_respawn"
	if not AREAS.has(a):
		a = "surface"
	await load_area(a, spawn, use_saved)
	# load_game() announces a backup restore from the title, where no toast widget exists yet:
	# repeat it now that the gameplay UI is up so Krystal is actually told.
	if SaveSystem.recovered_from_backup:
		Events.notify.emit(SaveSystem.BACKUP_NOTICE, "warn")
	return true


# --- Areas -------------------------------------------------------------------------------

## Loads an area scene and places the player. use_saved_position: outdoor areas only (OUTDOOR_AREAS);
## the saved position is validated (ground below, inside the world) and falls back to the spawn point.
func load_area(target_area: String, spawn_id: String, use_saved_position: bool = false) -> void:
	if _transitioning:
		return
	_transitioning = true
	_autosave_t = 0.0
	_bosses.clear()       # a freshly loaded area never starts inside a boss encounter
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
	var use_saved := use_saved_position and OUTDOOR_AREAS.has(target_area)
	var had_spawn: bool = area.get("spawns") is Dictionary and area.spawns.has(spawn_id)
	var xform := _spawn_transform(spawn_id, use_saved)
	if player.has_method("read_from_state"):
		player.read_from_state()
	player.teleport(xform)
	GameState.player["spawn"] = spawn_id
	# Where she now stands IN THIS AREA: a save before the player has touched the ground must never keep
	# a position from the area she just left (two outdoor areas share similar coordinates).
	GameState.player["pos"] = [xform.origin.x, xform.origin.y, xform.origin.z]
	GameState.player["yaw"] = xform.basis.get_euler().y
	# Area systems: building (surface) and the horror director (below).
	# BuildMode is added after the player on purpose so its _input() runs first.
	if target_area == "surface" or target_area == "hallowmere_reach" or (target_area == "arena" and Debug.is_cheat_allowed()):
		var bs: Script = _safe_load(BUILDING_SYSTEM)
		if bs != null and bs.has_method("attach"):
			bs.attach(area)
		# Structures (e.g. the bed) register their spawns deferred: re-place the player if the
		# requested spawn only exists now.
		await get_tree().process_frame
		if not use_saved and not had_spawn and area.get("spawns") is Dictionary and area.spawns.has(spawn_id):
			var late: Transform3D = area.get_spawn(spawn_id)
			player.teleport(late)
			GameState.player["pos"] = [late.origin.x, late.origin.y, late.origin.z]
	director = null
	if DIRECTOR_AREAS.has(target_area):
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


## Travel between areas (mine entrance / exit, waygate, doors, the Lantern Road). Autosaves after
## arriving - except in a trial (TRANSIENT_AREAS), which also keeps the respawn at the trial's origin.
func change_area(target_area: String, spawn_id: String) -> void:
	if _transitioning:
		return
	if player != null and is_instance_valid(player) and player.has_method("write_to_state"):
		player.write_to_state()
	_travel_seq += 1
	var seq := _travel_seq
	await load_area(target_area, spawn_id, false)
	# Another trip started during the fade-in (load_area hands control back before it ends): that trip
	# owns the respawn point and the save now.
	if seq != _travel_seq or (area_id != target_area and AREAS.has(target_area)):
		return
	var arrived: String = area_id if area_id != "" else target_area   # an unknown id became "surface"
	if TRANSIENT_AREAS.has(arrived):
		return
	# spawn_id is only where she arrives (the mine mouth / the landing / the waygate). Her return point
	# stays the bed or the Haven on the surface, the last lantern she rested at in the Below, and the
	# last arch / checkpoint she used in a Chapter Two area.
	set_respawn(arrived, return_point(arrived, spawn_id))
	SaveSystem.save_game()


## Where Krystal wakes after being defeated in `target_area`, having arrived at `arrival_spawn`.
func return_point(target_area: String, arrival_spawn: String) -> String:
	match target_area:
		"surface":
			return _bed_spawn_or("haven_respawn")
		"below":
			return _below_return_point(arrival_spawn)
	return _area_return_point(target_area, arrival_spawn)


## Chapter Two areas: arriving at a lit Lantern Road arch makes it the return point; otherwise the
## remembered one (area_respawn), else the area default (AREA_DEFAULT_RESPAWN), else the arrival spawn.
## Only spawns the loaded area actually registers are used.
func _area_return_point(target_area: String, arrival_spawn: String) -> String:
	var spawns: Dictionary = {}
	if area != null and is_instance_valid(area) and area.get("spawns") is Dictionary:
		spawns = area.get("spawns")
	if target_area == Reach.AREA_ID:
		var arch := Reach.arch_for_spawn(arrival_spawn)
		if arch != "" and bool(GameState.get_flag(Reach.arch_flag(arch))) and spawns.has(arrival_spawn):
			return arrival_spawn
	var last := area_respawn_of(target_area)
	if last != "" and spawns.has(last):
		return last
	var def := String(AREA_DEFAULT_RESPAWN.get(target_area, ""))
	if def != "" and spawns.has(def):
		return def
	return arrival_spawn


## The remembered return point of an area ("" if none). The Below keeps its legacy key below_respawn
## (old saves); Chapter Two areas use GameState.player["area_respawn"][area].
func area_respawn_of(target_area: String) -> String:
	if target_area == "below":
		return String(GameState.player.get("below_respawn", ""))
	var ar: Variant = GameState.player.get("area_respawn")
	if ar is Dictionary and (ar as Dictionary).has(target_area):
		return String((ar as Dictionary)[target_area])
	return ""


## The Below return point on (re-)entering: the lantern last used (GameState.player["below_respawn"]),
## or for saves made before that was remembered, the deepest lit lantern (area.checkpoints lists them
## from the entrance inwards). Falls back to `default_spawn`.
func _below_return_point(default_spawn: String) -> String:
	if area == null or not (area.get("spawns") is Dictionary):
		return default_spawn
	var spawns: Dictionary = area.get("spawns")
	var last: String = area_respawn_of("below")
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


## Sets where Krystal wakes after being defeated (bed, checkpoint lanterns, arches, mine entry...).
## Each area's last point is also remembered (the Below in "below_respawn", Chapter Two areas in
## "area_respawn") so a trip elsewhere doesn't forget it: change_area restores it on the way back.
## The surface needs no memory (always the bed or the Haven), and trials never move the respawn (a
## defeat or Continue always leaves a trial for its origin): a call for a trial area is ignored.
func set_respawn(target_area: String, spawn_id: String) -> void:
	if TRANSIENT_AREAS.has(target_area):
		return
	GameState.player["respawn_area"] = target_area
	GameState.player["respawn_spawn"] = spawn_id
	if target_area == "below":
		GameState.player["below_respawn"] = spawn_id
	elif target_area != "surface" and not TRANSIENT_AREAS.has(target_area) and AREAS.has(target_area):
		var ar: Variant = GameState.player.get("area_respawn")
		if not (ar is Dictionary):
			ar = {}
		(ar as Dictionary)[target_area] = spawn_id
		GameState.player["area_respawn"] = ar


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
	# Debug.mouse_mode_for() keeps the OS cursor visible in QA no-capture runs (--qa-no-focus).
	Input.mouse_mode = Debug.mouse_mode_for(want_captured)


func set_cutscene(active: bool) -> void:
	mode = "cutscene" if active else "playing"
	_update_mouse()
	Events.cutscene_changed.emit(active)
	if not active:
		_pause_if_focus_lost()


# --- Saving rules ------------------------------------------------------------------------------

## Manual saving (also the quiet autosave and save-on-close) is allowed in SAFE_SAVE_AREAS (the surface,
## Hallowmere Reach) and, in the other Chapter Two areas, while Krystal stands in a safe zone - always
## only when no enemy is hunting her within 20 m and no boss encounter is active. Underground, progress
## is saved at checkpoint lanterns; trials are never saved.
func can_manual_save() -> Dictionary:
	if mode != "playing" and mode != "loading":
		return {"ok": false, "reason": "You can't save right now."}
	if not SAFE_SAVE_AREAS.has(area_id):
		if not area_allows_saving(area_id):
			return {"ok": false, "reason": String(SAVE_REFUSALS.get(area_id, SAVE_REFUSALS["below"]))}
		if not player_in_safe_zone():
			return {"ok": false, "reason": "Rest somewhere safe, like a lit lantern, to save here."}
	if boss_active():
		return {"ok": false, "reason": "You can't save during a boss fight."}
	if _threat_near(THREAT_RADIUS):
		return {"ok": false, "reason": "You can't save while something is chasing you."}
	return {"ok": true, "reason": ""}


## True for areas where saving can be allowed at all (SAFE_SAVE_AREAS anywhere, other registered areas in
## a safe zone). The Below (lanterns only), trials and unregistered (debug) areas are never saved freely.
func area_allows_saving(a: String) -> bool:
	if SAFE_SAVE_AREAS.has(a):
		return true
	return AREAS.has(a) and not SAVE_REFUSALS.has(a)


## Is Krystal standing in a safe zone of the current area (checked live, not the 0.4 s poll)?
func player_in_safe_zone() -> bool:
	if player != null and is_instance_valid(player) and player.is_inside_tree() and area != null and is_instance_valid(area) and area.has_method("is_safe_zone"):
		return bool(area.is_safe_zone(player.global_position))
	return in_safe_zone


## Any enemy actively hunting Krystal within `radius` metres?
func _threat_near(radius: float) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and e.has_method("is_threatening") and e.is_threatening() and (e as Node3D).global_position.distance_to(player.global_position) < radius:
			return true
	return false


# --- Boss encounters (saving & travel gate) --------------------------------------------------------------

## True while a boss encounter is under way: Events.boss_encounter_changed (Chapter Two bosses/elites),
## the legacy boss bar (Events.boss_health_changed, hp < 0 = hidden) or the area's own fight_active.
func boss_active() -> bool:
	if not _bosses.is_empty():
		return true
	if area != null and is_instance_valid(area):
		var f: Variant = area.get("fight_active")
		if f is bool and f:
			return true
	return false


func _on_boss_encounter_changed(boss_id: String, active: bool) -> void:
	if active:
		_bosses[boss_id] = true
	else:
		_bosses.erase(boss_id)


func _on_boss_health_changed(boss_id: String, hp: float, _max_hp: float) -> void:
	if hp < 0.0:
		_bosses.erase(boss_id)
	else:
		_bosses[boss_id] = true


func _on_boss_defeated(boss_id: String) -> void:
	_bosses.erase(boss_id)


func _on_area_exiting_bosses(_area_id: String) -> void:
	_bosses.clear()


# --- Lantern Road (fast travel, MP §9) --------------------------------------------------------------------

## Whether the Lantern Road (arches, the Ward Stone option) may be used right now: {"ok", "reason"}.
## Never during a cutscene / loading, a boss encounter, or while something hunts her within 20 m.
func can_fast_travel() -> Dictionary:
	if mode != "playing" or _transitioning:
		return {"ok": false, "reason": "You can't travel right now."}
	if boss_active():
		return {"ok": false, "reason": "Not while a great foe is near."}
	if _threat_near(THREAT_RADIUS):
		return {"ok": false, "reason": "You can't travel while something is chasing you."}
	return {"ok": true, "reason": ""}


## Travel list: the Haven first (once any arch is lit), then every lit arch in Reach.ARCH_ORDER.
## Each entry: {"id", "name", "area", "spawn"}. Empty when no arch is lit yet.
func lantern_road_destinations() -> Array:
	var out: Array = []
	for id in Reach.ARCH_ORDER:
		if bool(GameState.get_flag(Reach.arch_flag(String(id)))):
			var a: Dictionary = Reach.ARCHES[id]
			out.append({"id": String(id), "name": String(a["name"]), "area": Reach.AREA_ID, "spawn": String(a["spawn"])})
	if not out.is_empty():
		out.push_front(HAVEN_DESTINATION.duplicate())
	return out


## Opens the travel list (ui.confirm) and travels to the chosen destination. Awaitable.
func travel_lantern_road() -> void:
	var ft := can_fast_travel()
	if not bool(ft["ok"]):
		Events.notify.emit(String(ft["reason"]), "warn")
		return
	var dests := lantern_road_destinations()
	if dests.is_empty():
		Events.notify.emit("No lantern arch is lit yet.", "info")
		return
	var buttons: Array = []
	for d in dests:
		if _is_current_destination(d):
			continue
		buttons.append([String(d["id"]), String(d["name"]), "AccentButton" if buttons.is_empty() else ""])
	if buttons.is_empty():
		Events.notify.emit("You are already there.", "info")
		return
	buttons.append(["cancel", "Stay here", ""])
	if ui == null or not is_instance_valid(ui) or not ui.has_method("confirm"):
		return
	var pick: String = await ui.confirm("The Lantern Road", "The lanterns remember every road they light. Where to?", buttons)
	if pick == "" or pick == "cancel":
		return
	await lantern_road_travel(pick)


## Travels to one Lantern Road destination id ("haven" or an arch id) without any menu. Same area: a
## short fade, Krystal and her follower are moved; another area: change_area (autosave, respawn rules).
## Returns false if the destination is unknown/unlit or travel isn't allowed now.
func lantern_road_travel(dest_id: String) -> bool:
	var dest: Dictionary = {}
	for d in lantern_road_destinations():
		if String(d["id"]) == dest_id:
			dest = d
	if dest.is_empty():
		return false
	var ft := can_fast_travel()
	if not bool(ft["ok"]):
		Events.notify.emit(String(ft["reason"]), "warn")
		return false
	var target_area := String(dest["area"])
	var spawn := String(dest["spawn"])
	if target_area == area_id:
		await _travel_within_area(spawn)
		if target_area != "surface":
			set_respawn(target_area, spawn)
	else:
		await change_area(target_area, spawn)
	return true


func _is_current_destination(d: Dictionary) -> bool:
	if String(d["area"]) != area_id or area == null or not is_instance_valid(area) or player == null or not is_instance_valid(player):
		return false
	# Anywhere inside the Haven (e.g. at the Ward Stone, ~9 m from haven_respawn) she is already home.
	if String(d["id"]) == String(HAVEN_DESTINATION["id"]) and area.has_method("get_zone_at") \
			and String(area.get_zone_at(player.global_position)) == "haven":
		return true
	if not (area.get("spawns") is Dictionary) or not (area.get("spawns") as Dictionary).has(String(d["spawn"])):
		return false
	var xf: Transform3D = area.get_spawn(String(d["spawn"]))
	return xf.origin.distance_to(player.global_position) < 8.0


## Same-area Lantern Road hop: fade, move Krystal (and her follower: teleport_near only moves followers).
func _travel_within_area(spawn: String) -> void:
	set_cutscene(true)
	if ui != null and is_instance_valid(ui) and ui.has_method("fade_out"):
		await ui.fade_out(0.35)
	if player != null and is_instance_valid(player) and area != null and is_instance_valid(area):
		var xf: Transform3D = area.get_spawn(spawn)
		player.teleport(xf)
		for id in companion_nodes:
			var c: Variant = companion_nodes[id]
			if c is Node and is_instance_valid(c) and (c as Node).has_method("teleport_near"):
				(c as Node).teleport_near(xf.origin)
	await get_tree().create_timer(0.15).timeout
	if ui != null and is_instance_valid(ui) and ui.has_method("fade_in"):
		await ui.fade_in(0.5)
	set_cutscene(false)


# --- Companions ---------------------------------------------------------------------------------------------

## True when `companion_id` is Krystal's follower, spawned in this area and within 25 m of her
## (companion passives and support only count then, docs/CHAPTER_TWO_SPEC.md §5).
func companion_present(companion_id: String) -> bool:
	if companion_id == "" or GameState.active_companion != companion_id:
		return false
	var c: Variant = companion_nodes.get(companion_id)
	if not (c is Node3D) or not is_instance_valid(c) or not (c as Node3D).is_inside_tree():
		return false
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	return (c as Node3D).global_position.distance_to(player.global_position) <= COMPANION_PRESENT_RADIUS


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


## Chapter Two ending ("The Lanternwake", MP §11 step 20, §17). Called by whoever runs the final beat
## (the chapter-two quest layer / the Ward Stone "Celebrate" option) with the reward items
## {item_id: count}. Order matters (spec §3.5, MP §11 step 17): the rewards are COMMITTED first through
## the reward ledger (GameState.grant_once("rw_ch2_feast", ...), exactly once), chapter_two_complete is
## set and the game is saved; only then the presentation plays (companions celebrate,
## Events.chapter2_completed, the ending), and free play resumes in the same save. A second call (or a
## call after reloading) grants nothing and shows nothing. Never calls complete_chapter().
## Returns true when this call completed the chapter.
func complete_chapter_two(rewards: Dictionary = {}) -> bool:
	if _ch2_ending_running:
		return false
	var was_complete := bool(GameState.get_flag(CH2_COMPLETE_FLAG))
	var granted := _grant_chapter_two_rewards(rewards)
	if not was_complete:
		GameState.set_flag(CH2_COMPLETE_FLAG, true)
	if was_complete and not granted:
		return false
	SaveSystem.save_game(true)
	if was_complete:
		return false
	_ch2_ending_running = true
	var was_playing := mode == "playing"
	if was_playing:
		set_cutscene(true)
	# --- Presentation only from here on (story module C9): everything above is committed and saved. ---
	var story: Script = _safe_load("res://src/world/story_ch2/story_ch2.gd")
	# The ledger entry's wardrobe / furnishing unlocks: normally already applied inside grant_once (the story
	# tracker listens to Events.reward_granted), so this is a no-op; without the tracker it applies them here.
	if story != null and bool(story.call("sync_feast_unlocks")):
		SaveSystem.save_game(true)
	for id in companion_nodes:
		var c: Variant = companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("react"):
			(c as Node).react("celebrate")
	Events.chapter2_completed.emit()
	if was_playing:
		# A small skippable celebration in the current area (festival lights outside the build area, a
		# validated camera shot or the player's own), then the ending card, credits and free play.
		var cel: Node = story.call("start_celebration") if story != null else null
		if cel != null and is_instance_valid(cel) and cel.has_method("play"):
			await cel.play()
		await _show_chapter_two_ending()
		if cel != null and is_instance_valid(cel) and cel.has_method("finish"):
			cel.finish()
	else:
		_show_chapter_two_card()   # scripted / headless runs: nothing blocks
	if story != null:
		story.call("after_ending")   # journal note + the lasting festival dressing in this area
	if was_playing and mode == "cutscene":
		set_cutscene(false)
	GameState.request_quest_eval()
	_ch2_ending_running = false
	return true


## The final Chapter Two step's on_complete ({"give": {item: n}, "flags": [...]}) from data/quests_ch2.gd
## (its FINAL_STEP), or {} when that data doesn't exist. The quest layer grants the same step through
## grant_once("rw_" + FINAL_STEP) = CH2_REWARD_ID, so both paths must grant the identical set.
func _feast_step_rewards() -> Dictionary:
	if not ResourceLoader.exists(QUESTS_CH2_DATA):
		return {}
	var s: Variant = load(QUESTS_CH2_DATA)
	if not (s is Script) or not (s as Script).can_instantiate():
		return {}
	var consts: Dictionary = (s as Script).get_script_constant_map()
	var final_id := String(consts.get("FINAL_STEP", "ch2_feast"))
	var steps: Variant = consts.get("STEPS", [])
	if steps is Array:
		for st in steps:
			if st is Dictionary and String((st as Dictionary).get("id", "")) == final_id:
				var oc: Variant = (st as Dictionary).get("on_complete", {})
				return (oc as Dictionary).duplicate(true) if oc is Dictionary else {}
	return {}


## The Lanternwake reward items {item_id: count} (the final step's "give" plus the Lanternwake's continued
## resources, story module C9: src/world/story_ch2/story_ch2.gd FEAST_EXTRAS; the Wardlight itself comes
## earlier, with ch2_homecoming). Only ids ItemDB knows. CH2_FEAST_REWARDS_DEFAULT when there is no data.
## The ending commits them with the final step's flags under the one ledger entry rw_ch2_feast.
func chapter_two_rewards() -> Dictionary:
	var src: Variant = CH2_FEAST_REWARDS_DEFAULT
	var oc := _feast_step_rewards()
	if oc.has("give"):
		src = oc["give"]
	var out := {}
	if src is Dictionary:
		for id in src:
			if ItemDB.has_item(String(id)):
				out[String(id)] = int(src[id])
	var story: Script = _safe_load("res://src/world/story_ch2/story_ch2.gd")
	var extras: Variant = story.call("feast_extras") if story != null else {}
	if extras is Dictionary:
		for id in extras:
			if ItemDB.has_item(String(id)):
				out[String(id)] = maxi(int(out.get(String(id), 0)), int(extras[id]))
	return out


## Grants the Chapter Two rewards exactly once: `rewards` merged (max per item) with the final step's
## on_complete give, flags = chapter_two_complete + the final step's flags (e.g. ch2_feast, a recipe
## unlock). Uses the reward ledger (GameState.grant_once) when the core-save module provides it; without
## it chapter_two_complete itself is the ledger entry (set first, then the items are given).
## Returns true when the rewards were granted by this call.
func _grant_chapter_two_rewards(rewards: Dictionary) -> bool:
	var oc := _feast_step_rewards()
	var items := {}
	var give: Variant = oc.get("give", {})
	if give is Dictionary:
		for id in give:
			items[String(id)] = int(give[id])
	for id in rewards:
		items[String(id)] = maxi(int(items.get(String(id), 0)), int(rewards[id]))
	var flag_list: Array = [CH2_COMPLETE_FLAG]
	var extra_flags: Variant = oc.get("flags", [])
	if extra_flags is Array:
		for f in extra_flags:
			if not flag_list.has(String(f)):
				flag_list.append(String(f))
	if GameState.has_method("grant_once"):
		return bool(GameState.call("grant_once", CH2_REWARD_ID, items, flag_list,
			"Chapter Two complete. The Lanternwake's gifts are yours."))
	if bool(GameState.get_flag(CH2_COMPLETE_FLAG)):
		return false
	for f in flag_list:
		GameState.set_flag(String(f), true)
	for id in items:
		GameState.give_item(String(id), int(items[id]))
	return true


## The Chapter Two ending presentation: a dedicated UI ending if the UI offers one (show_chapter_two_ending()
## or show_ending(variant)), else the Chapter Two variant of the ending screen on the UI root's overlay layer
## (the same layer the Chapter One ending uses), else the chapter card plus the MP §17 ending line.
## Awaitable: returns when the player continues into free play.
func _show_chapter_two_ending() -> void:
	if ui == null or not is_instance_valid(ui):
		return
	if ui.has_method("show_chapter_two_ending"):
		await ui.show_chapter_two_ending()
	elif ui.has_method("show_ending") and ui.get_method_argument_count("show_ending") >= 1:
		await ui.show_ending("chapter_two")
	elif ui.get("overlay_layer") is Control and _safe_load("res://src/ui/screens/ending_screen.gd") != null:
		if ui.has_method("close_all"):
			ui.close_all()
		var es: Control = _safe_load("res://src/ui/screens/ending_screen.gd").new()
		es.call("setup", {"variant": "chapter_two"})
		(ui.get("overlay_layer") as Control).add_child(es)
		await es.play()
	else:
		_show_chapter_two_card()


## Non-blocking stand-in (no ending UI, or a scripted / headless completion): the card and the ending line.
func _show_chapter_two_card() -> void:
	if ui != null and is_instance_valid(ui) and ui.has_method("show_chapter_card"):
		ui.show_chapter_card("Chapter Two Complete", "The Lanterns of Hallowmere")
		Events.say.emit("", CH2_ENDING_TEXT, 9.0)


func quit_to_title() -> void:
	goto_title()


func quit_game() -> void:
	Settings.save()
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await get_tree().process_frame
	get_tree().quit()
