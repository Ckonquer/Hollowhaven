extends Node3D
## "WorksDeep": the runtime controller of Hushed Works rooms 9-14, created by rooms_deep.gd build() as a
## child of the Works area. Holds the interactive nodes (threads, lifts, checkpoints, arenas, porch,
## throat, the winch moment), tracks Krystal's room at 10 Hz (pure box lookups, no group scans), fires
## the authored moments, drives the arena triggers, keeps the director quiet in the porch, and performs
## lift rides inside the Works (fade + teleport) and the vault exit (Game.change_area).
## Tests set `player_override` (a Node3D standing in for Krystal) and call check(dt) / the public hooks.
##
## Public hooks (also used by tests):
##   ride(spawn, caption := "", line := "")        fade, teleport to an area spawn (companions follow)
##   travel_area(area_id, spawn, caption := "")     leaves the Works (vault exit lift)
##   take_false_lift() / take_real_lift()            the Wrong Landing lifts
##   take_winch_cage() / ride_winch_cage(option)     room 9's cage back down (after a ride up: free_winch_cage())
##   room_of(pos) -> String                          deep room id at a position ("" outside rooms 9-14)
##   leave_room()                                    run the current room's exit rules (respawn / rides do)
##   thread(id), lift(id), checkpoint(id)            node lookups; crossing / choir / porch / throat / winch
##   debug_clear_crossing() / debug_clear_choir()   debug builds only (tests): mark the encounters cleared

signal rode(spawn_id: String)
signal travelled(area_id: String, spawn_id: String)
signal room_changed(old_room: String, new_room: String)

const Layout := preload("res://data/works_layout_deep.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")

const TICK := 0.1
const PORCH_SUPPRESS_EVERY := 4.0
const THREAD_HINT_RADIUS := 5.0

var area: Node3D = null
var player_override: Node3D = null
var room: String = ""
var threads: Dictionary = {}
var lifts: Dictionary = {}
var checkpoints: Dictionary = {}
var crossing: Node3D = null
var choir: Node3D = null
var porch: Node3D = null
var throat: Node3D = null
var winch: Node3D = null
var winch_lamps: Array = []
var build_ms: float = 0.0
var build_times: Dictionary = {}     # stage -> ms since build() started (QA)
var last_ride: String = ""
var last_travel: Array = []
var enabled: bool = true

var _t: float = 0.0
var _riding: bool = false
var _porch_suppress_t: float = 0.0
var _silence_active: bool = false
var _hint_threads_shown: bool = false


func setup(p_area: Node3D) -> void:
	area = p_area


func _ready() -> void:
	add_to_group("hw_deep")
	Events.player_respawned.connect(_on_player_respawned)
	Events.area_exiting.connect(_on_area_exiting)


func player() -> Node3D:
	return Art.player_or(player_override)


func room_of(pos: Vector3) -> String:
	return Layout.room_at(pos)


func thread(id: String) -> Node3D:
	return threads.get(id, null)


func lift(id: String) -> Node3D:
	return lifts.get(id, null)


func checkpoint(id: String) -> Node3D:
	return checkpoints.get(id, null)


# --- Tick ---------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	if player_override == null and (Game.mode == "cutscene" or Game.mode == "loading"):
		return
	check(dt)


## One controller step (10 Hz). Public for tests.
func check(dt: float = TICK) -> void:
	if not enabled or _riding:
		return
	var p := player()
	if p == null:
		return
	var pos := p.global_position
	var r := Layout.room_at(pos)
	if r != room:
		var old := room
		room = r
		_on_room_changed(old, r)
	if r == "":
		return
	var zone := Layout.zone_of_room(r)
	if winch != null:
		winch.call("check", p, dt, zone == "hw_winch")
	match zone:
		"hw_winch":
			_thread_hint(pos)
		"hw_crossing":
			if crossing != null:
				crossing.call("check", p)
		"hw_porch":
			_porch_tick(p, dt)
		"hw_throat":
			if throat != null:
				throat.call("check", p)
		"hw_vault":
			if choir != null:
				choir.call("check", p)


func _on_room_changed(old_room: String, new_room: String) -> void:
	var oz := Layout.zone_of_room(old_room)
	var nz := Layout.zone_of_room(new_room)
	if oz == "hw_porch" and nz != "hw_porch":
		Art.director_release(area, "hw_porch")
		_porch_suppress_t = 0.0
		if _silence_active:
			_silence_active = false
			if porch != null:
				porch.call("end_fragment")
			Events.music_context_changed.emit("")
	if oz == "hw_crossing" and nz != "hw_crossing" and crossing != null:
		crossing.call("stop_encounter", "left")
	if oz == "hw_vault" and nz != "hw_vault" and choir != null:
		choir.call("stop_encounter", "left")
	if nz == "hw_throat" and oz != "hw_throat" and not bool(GameState.get_flag("hw_throat_seen")):
		GameState.set_flag("hw_throat_seen", true)
		Art.say("A warm, quiet place under the bells. Rest by the lantern; the bell-rope lift climbs back to the refuge.", 6.0)
	room_changed.emit(old_room, new_room)


func _thread_hint(pos: Vector3) -> void:
	if _hint_threads_shown:
		return
	for id in threads:
		var t: Node3D = threads[id]
		if t == null or not is_instance_valid(t) or not bool(t.call("is_whole")):
			continue
		if t.global_position.distance_to(pos) < THREAD_HINT_RADIUS:
			_hint_threads_shown = true
			var a := Art.arachno()
			Events.hint.emit("hw_threads", ("A pale veil blocks the way. Press {interact} to part it - it drifts back. Raise your lantern ({lantern}) first to burn it for good." if a
				else "Fresh threads block the way. Press {interact} to cut them - they grow back. Raise your lantern ({lantern}) first to burn them for good."))
			return


func _porch_tick(p: Node3D, dt: float) -> void:
	_porch_suppress_t -= dt
	if _porch_suppress_t <= 0.0:
		_porch_suppress_t = PORCH_SUPPRESS_EVERY
		Art.director_hold(area, "hw_porch")
	if porch == null:
		return
	var f: Vector3 = Layout.PORCH["facade"]
	if not bool(GameState.get_flag("moment_hw_porch")) and Vector2(p.global_position.x - f.x, p.global_position.z - f.z).length() < float(Layout.PORCH["fragment_radius"]):
		porch.call("on_first_approach")
		if bool(porch.get("fragment_played")):
			_silence_active = true


func _suppress(seconds: float) -> void:
	Art.director_suppress(area, seconds)


## A teleport (respawn, lift ride) leaves the current room without walking out of it: run its exit rules
## (porch director hold + silence, arena fights) before forgetting it, so nothing stays held.
func leave_room() -> void:
	if room != "":
		var old := room
		room = ""
		_on_room_changed(old, "")


func _on_player_respawned() -> void:
	leave_room()


func _on_area_exiting(_area_id: String) -> void:
	if _silence_active:
		_silence_active = false
		Events.music_context_changed.emit("")


# --- Travel --------------------------------------------------------------------------------------------------

## Lift ride inside the Works: fade out, teleport Krystal (and followers) to `spawn_id`, fade in.
## Without a live game (tests) it teleports the override player immediately.
func ride(spawn_id: String, caption: String = "", line: String = "") -> void:
	if _riding or area == null:
		return
	var sp: Variant = area.get("spawns")
	if not (sp is Dictionary) or not (sp as Dictionary).has(spawn_id):
		push_warning("WorksDeep: no spawn '%s' to ride to" % spawn_id)
		return
	_riding = true
	last_ride = spawn_id
	Audio.play_sfx("lift_move", -2.0, 0.0)
	Art.caption(caption)
	var p := player()
	var live := player_override == null and p != null and p == Game.player and Game.mode == "playing"
	if live:
		Game.set_cutscene(true)
		if Game.ui != null and Game.ui.has_method("fade_out"):
			await Game.ui.fade_out(0.7)
		await get_tree().create_timer(0.9).timeout
	var xf: Transform3D = area.call("get_spawn", spawn_id)
	if p != null and is_instance_valid(p):
		if p.has_method("teleport"):
			p.call("teleport", xf)
		else:
			p.global_transform = xf
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("teleport_near"):
			(c as Node).call("teleport_near", xf.origin)
	leave_room()
	if live:
		if Game.ui != null and Game.ui.has_method("fade_in"):
			await Game.ui.fade_in(0.9)
		if Game.mode == "cutscene":
			Game.set_cutscene(false)
	if line != "":
		Art.say(line, 5.0)
	_riding = false
	rode.emit(spawn_id)


## Leaves the Works (vault exit lift). Tests record the trip instead of loading a scene.
func travel_area(area_id: String, spawn_id: String, caption: String = "") -> void:
	last_travel = [area_id, spawn_id]
	Art.caption(caption)
	travelled.emit(area_id, spawn_id)
	if player_override != null or Game.player == null or not is_instance_valid(Game.player):
		return
	Audio.play_sfx("lift_move", -2.0, 0.0)
	Game.change_area(area_id, spawn_id)


## The Wrong Landing's false lift: a short, harmless detour into the service siding.
func take_false_lift() -> void:
	GameState.set_flag("hw_false_lift_ridden", true)
	var gentle := Art.intensity() == 0
	ride("hw_wrong_siding", "[the cage drops a foot, lurches sideways along a track and jams]",
		("That lift's lamp never lit its landing plate. It only rolled into a siding - the landing is a short walk back." if gentle
		else "The cage jammed in a siding. A short walk leads back to the landing."))


## The real lift: Loop B back to the Pocket Conservatory (hub, spawn refuge). It also frees room 9's
## winch cage, so the way back down is one room from the hub door.
func take_real_lift() -> void:
	var first := not bool(GameState.get_flag("hw_loop_b_lift"))
	GameState.set_flag("hw_loop_b_lift", true)
	free_winch_cage()
	ride(Layout.REFUGE_SPAWN, "[the old lift groans and climbs; somewhere above, a winch brake clanks free]",
		"The Pocket Conservatory. The winch cage by the ward door will take you back down." if first else "")


## Any ride UP from the deep rooms releases the winch cage's brake (persistent).
func free_winch_cage() -> void:
	GameState.set_flag(String(Layout.WINCH_CAGE["flag"]), true)


func winch_cage_free() -> bool:
	return bool(GameState.get_flag(String(Layout.WINCH_CAGE["flag"])))


## Where the winch cage can go: [[option id, label, spawn id], ...] (the Bell Throat once she has been there).
func winch_cage_destinations() -> Array:
	var d: Dictionary = Layout.WINCH_CAGE
	var out: Array = [["landing", "Down to the Wrong Landing", String(d["landing_spawn"])]]
	if bool(GameState.get_flag(String(d["throat_seen_flag"]))):
		out.append(["throat", "Down to the Bell Throat", String(d["throat_spawn"])])
	return out


## Room 9's winch cage (loop B the other way). With two destinations she picks one (Game.ui.confirm);
## without a UI (tests) it goes to the first. Returns the option taken ("" = none / stayed).
func take_winch_cage() -> String:
	if not winch_cage_free() or _riding:
		return ""
	var dests := winch_cage_destinations()
	var pick := String(dests[0][0])
	if dests.size() > 1 and player_override == null and Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("confirm"):
		var buttons: Array = []
		for d in dests:
			buttons.append([String(d[0]), String(d[1]), "AccentButton" if String(d[0]) == "throat" else ""])
		buttons.append(["stay", "Stay here", ""])
		var c: Variant = await Game.ui.confirm("The winch cage", "The drum is free. Where should the cage go?", buttons)
		pick = String(c)
	return ride_winch_cage(pick)


## Rides the winch cage to one of winch_cage_destinations() by option id. "" if that isn't possible.
func ride_winch_cage(option: String) -> String:
	if not winch_cage_free():
		return ""
	for d in winch_cage_destinations():
		if String(d[0]) == option:
			ride(String(d[2]), "[the winch drum turns; the cage sinks into the dark shaft]")
			return option
	return ""


func _on_lift(l: Node) -> void:
	match String(l.get("lift_id")):
		"hw_lift_real":
			take_real_lift()
		"hw_lift_false":
			take_false_lift()
		"hw_winch_cage":
			take_winch_cage()


# --- Winch work lamps -------------------------------------------------------------------------------------

func winch_lamps_on() -> bool:
	return bool(GameState.get_flag("hw_winch_lamps"))


func switch_winch_lamps() -> void:
	var on := not winch_lamps_on()
	GameState.set_flag("hw_winch_lamps", on)
	apply_winch_lamps()
	Art.sfx3d("gate_unlock", Layout.WINCH["switch"], -6.0)
	Art.caption("[a heavy switch clunks; the work lamps hum %s]" % ("awake" if on else "down"))
	if winch != null:
		winch.call("note_read")


func apply_winch_lamps() -> void:
	var on := winch_lamps_on()
	for l in winch_lamps:
		if l != null and is_instance_valid(l):
			(l as Node).set("dim_mult", 1.0 if on else 0.18)


# --- Debug / test hooks ----------------------------------------------------------------------------------------

func debug_clear_crossing() -> bool:
	return crossing != null and bool(crossing.call("debug_mark_cleared"))


func debug_clear_choir() -> bool:
	return choir != null and bool(choir.call("debug_mark_cleared"))


## Every persistent id this module owns (determinism tests): thread ids, checkpoint ids, lift ids.
func persistent_ids() -> Array:
	var out: Array = []
	for d in [threads, checkpoints, lifts]:
		var keys: Array = (d as Dictionary).keys()
		keys.sort()
		out.append_array(keys)
	return out
