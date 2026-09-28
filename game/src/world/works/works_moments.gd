extends Node
## Room tracker + authored moments of the Hushed Works, rooms 1-8 (restrained, fair, never harmful).
## Ticks at 10 Hz (skips cutscenes / loading); `check(p, dt)` is public for tests; `player_override` and
## `hold` (QA: shapes stay put) like src/world/below/below_moments.gd.
##   * Tracks Krystal's room (merged table) and forwards changes to area.on_room_changed(old, new).
##   * Progress flags by place: entering the refuge sets ch2_refuge_reached; reaching the rail junction by
##     the lit rail sets ch2_true_signal (quest "Hask's Rail"). The first visit to the Tool Lockers shows the
##     taught fight's rule once (hint "hw_drudge"; Wren's locker note repeats it).
##   * Director quiet: puzzle rooms (data/horror_events.gd WORKS_PUZZLE_HOLDS) are held quiet
##     (area.director_hold) until their line flag is set; released when Krystal leaves or solves.
##   * HASK'S LAST KNOCK (rails, once per save, flag moment_hw_knock): after she has walked into the rail hall
##     and then stands still (Gentle 1.5 s / Standard 2 s / Intense 3.5 s), the rails answer three times: two
##     false knocks from the dark sealed corridors (a cold glint that lights nothing), then the true one from
##     Hask's lamp at the junction (the lantern swings and brightens; see works_signal_lamp.gd). Captions name
##     each source (Gentle: explicitly which one holds a real light); nothing depends on hearing.
##   * THE COMPANION AT THE WRONG DOOR (Hall of Closed Eyes, once per save, flags moment_hw_wrong_door /
##     moment_hw_wrong_door_folded): a cold, lightless "Lumi" (src/world/below/fake_lumi.gd) behind a grate no
##     companion could pass. Its glow lights nothing beneath it while the real lamp beside the grate does.
##     Gentle: an explicit clue line; Intense: the illusion stays perfectly still for longer before moving.
##     Approaching the grate folds it away; leaving the hall makes it vanish. The real companion only reacts.
## Each moment sets its flag FIRST, then Events.horror_event("authored:<id>") + director suppress.

signal knock_finished

const Layout := preload("res://data/works_layout.gd")
const HorrorData := preload("res://data/horror_events.gd")
const FakeLumi := preload("res://src/world/below/fake_lumi.gd")

const TICK := 0.1

var area: Node3D = null
var room: String = ""
var zone: String = ""
var player_override: Node3D = null      # tests
var fired: Array = []                   # moment ids fired this session (tests / QA)
var hold: bool = false                  # QA: the fake stays regardless of where Krystal is

## Hask's Last Knock state: "" | "armed" | "knocking" | "done"
var knock_state: String = ""
var knock_step: int = 0
var knock_sources: Array = []           # [{"pos": Vector3, "true": bool}] in the order played (tests)
var fake: Node3D = null
var fake_still_left: float = 0.0

var _t: float = 0.0
var _walked: float = 0.0
var _still: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _knock_t: float = 0.0
var _held: Dictionary = {}              # puzzle hold ids requested by this tracker
var _hold_ids: Dictionary = {}          # zone -> "puzzle:<zone>" (cached)
var _false_note_shown: Dictionary = {}


func setup(p_area: Node3D) -> void:
	area = p_area


func _ready() -> void:
	name = "Moments"


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


static func intensity() -> int:
	return clampi(int(Settings.get_value("horror_intensity")), 0, 2)


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	if Game.mode == "cutscene" or Game.mode == "loading":
		return
	var p := _player()
	if p == null:
		return
	check(p, dt)


## One evaluation step at the player's position (public for tests).
func check(p: Node3D, dt: float) -> void:
	var pos := p.global_position
	var r: String = area.room_at(pos) if area != null else ""
	if r != room:
		var old := room
		room = r
		zone = area.zone_of_room(r) if area != null and r != "" else ""
		_on_room_changed(old, r)
	_update_holds()
	_tick_knock(p, pos, dt)
	_tick_wrong_door(p, pos, dt)


func _on_room_changed(old: String, new_room: String) -> void:
	if new_room == "refuge" or new_room == "refuge_stair":
		if not bool(GameState.get_flag("ch2_refuge_reached")):
			GameState.set_flag("ch2_refuge_reached", true)
			Events.say.emit("", "Warm air, green leaves, a shaft of real daylight. The miners' garden is real.", 5.0)
	if new_room == "lockers" and not bool(GameState.get_flag(Layout.FLAG_LOCKERS_CLEARED)):
		# The taught fight: the rule once, up front (Wren's locker note says it again in her own words).
		Events.hint.emit("hw_drudge", "An old coat raises its pick slowly and scrapes before it strikes again. Step aside, then strike while it is bent over.")
	if new_room == "junction" and not bool(GameState.get_flag("ch2_true_signal")):
		GameState.set_flag("ch2_true_signal", true)
		Events.say.emit("", "Hask's lamp still burns beside the rail, lighting the rail it stands on.", 5.0)
		Events.hint.emit("hw_true_light", "A true light lights what holds it. Glows that light nothing are not lanterns.")
	if new_room == "rails_false_n" or new_room == "rails_false_s":
		if not _false_note_shown.has(new_room):
			_false_note_shown[new_room] = true
			Events.caption.emit("[cold glass glints behind the grate - it lights nothing, not even the bars]")
	if area != null and area.has_method("on_room_changed"):
		area.on_room_changed(old, new_room)


# --- Director quiet in puzzle rooms ------------------------------------------------------------------------------

func _update_holds() -> void:
	if area == null:
		return
	if _hold_ids.is_empty():
		for z in HorrorData.WORKS_PUZZLE_HOLDS:
			_hold_ids[String(z)] = "puzzle:" + String(z)     # built once: nothing allocated per tick
	for z in HorrorData.WORKS_PUZZLE_HOLDS:
		var id: String = _hold_ids[z]
		var want: bool = zone == String(z) and not bool(GameState.get_flag(String(HorrorData.WORKS_PUZZLE_HOLDS[z])))
		if want and not _held.has(id):
			_held[id] = true
			area.director_hold(id)
		elif not want and _held.has(id):
			_held.erase(id)
			area.director_release(id)


func held_ids() -> Array:
	return _held.keys()


# --- HASK'S LAST KNOCK ----------------------------------------------------------------------------------------------

func _tick_knock(p: Node3D, pos: Vector3, dt: float) -> void:
	if knock_state == "knocking":
		_knock_t += dt
		if room != "rails" and room != "junction" and room != "rails_false_n" and room != "rails_false_s":
			_finish_knock()     # she walked away: the rails fall quiet (the flag is already set)
			return
		while knock_state == "knocking" and _knock_t >= float(knock_step) * Layout.KNOCK_GAP:
			_play_knock(knock_step)
			knock_step += 1
			if knock_step >= 3:
				_finish_knock()
		return
	if knock_state == "done" or bool(GameState.get_flag(Layout.MOMENT_KNOCK)):
		knock_state = "done"
		return
	if room != "rails":
		_has_last = false
		_walked = 0.0
		_still = 0.0
		return
	var moved := 0.0
	if _has_last:
		moved = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	_has_last = true
	_walked += moved
	var moving := moved > 0.05
	if p.has_method("is_moving"):
		moving = moving or bool(p.is_moving())
	if _walked < Layout.KNOCK_ARM_DISTANCE:
		return
	knock_state = "armed"
	if moving:
		_still = 0.0
		return
	_still += dt
	if _still >= float(Layout.KNOCK_STILL_SECONDS[intensity()]):
		start_knock()


## Starts the three answers (public for QA / tests).
func start_knock() -> void:
	if knock_state == "knocking":
		return
	GameState.set_flag(Layout.MOMENT_KNOCK, true)
	knock_state = "knocking"
	knock_step = 0
	_knock_t = 0.0
	knock_sources.clear()
	fired.append("hw_knock")
	Events.horror_event.emit("authored:hw_knock", {})
	_suppress(45.0)


func _play_knock(step: int) -> void:
	var gentle := intensity() == 0
	if step < 2:
		var src: Vector3 = Layout.KNOCK_FALSE[step]
		knock_sources.append({"pos": src, "true": false})
		Audio.play_3d("mine_hit", src, -6.0, 0.02, 40.0)
		if area != null and area.has_method("blink_false_signal"):
			area.blink_false_signal(step)
		var side := "north" if step == 0 else "south"
		if gentle:
			Events.caption.emit("[three knocks answer from the dark, sealed corridor to the %s - nothing there holds a light]" % side)
		else:
			Events.caption.emit("[three knocks answer from the dark corridor to the %s]" % side)
	else:
		knock_sources.append({"pos": Layout.KNOCK_TRUE, "true": true})
		Audio.play_3d("mine_hit", Layout.KNOCK_TRUE, -3.0, 0.02, 40.0)
		var lamp: Node = area.get("signal_lamp") if area != null else null
		if lamp != null and is_instance_valid(lamp) and lamp.has_method("knock_pulse"):
			lamp.knock_pulse()
		if gentle:
			Events.caption.emit("[three knocks answer from the junction ahead, where a real lantern hangs beside the rail and swings]")
		else:
			Events.caption.emit("[three knocks answer from the junction, and the lantern there swings]")


func _finish_knock() -> void:
	if knock_state == "done":
		return
	knock_state = "done"
	var gentle := intensity() == 0
	Events.hint.emit("hw_knock_rule", "Follow the knock that has a real lantern beside it: true light lights the rail it stands on.")
	if gentle:
		Events.say.emit("", "Two knocks came from the dark. One came from Hask's lantern. Follow the light that lights the floor.", 6.0)
	knock_finished.emit()


# --- THE COMPANION AT THE WRONG DOOR ------------------------------------------------------------------------------

func _tick_wrong_door(p: Node3D, pos: Vector3, dt: float) -> void:
	if fake != null and is_instance_valid(fake):
		if bool(fake.get("folding")):
			return
		if fake_still_left > 0.0:
			fake_still_left -= dt
			if fake_still_left <= 0.0:
				fake.set("active", true)
				fake.set("_next_chime", 0.4)
		var d2 := Vector2(pos.x - fake.global_position.x, pos.z - fake.global_position.z).length()
		if d2 < Layout.FAKE_FOLD_DISTANCE:
			fold_fake()
		elif room != "eyes" and room != "eyes_route" and not hold:
			fake.vanish()
			fake = null
		elif fake_still_left <= 0.0 and fake.has_method("stare_at"):
			fake.stare_at(pos)
		return
	if room == "eyes" and pos.z >= Layout.WRONG_DOOR_TRIGGER_Z and not bool(GameState.get_flag(Layout.MOMENT_WRONG_DOOR)):
		start_wrong_door(p)


func start_wrong_door(p: Node3D) -> void:
	GameState.set_flag(Layout.MOMENT_WRONG_DOOR, true)
	fake = FakeLumi.new()
	fake.name = "WrongDoorLumi"
	fake.position = Layout.FAKE_LUMI_POS
	area.add_child(fake)
	# Perfectly still at first (no jerks, no chime); Intense waits longest before it moves.
	fake.set("active", false)
	fake_still_left = float(Layout.FAKE_STILL_SECONDS[intensity()])
	fake.stare_at(p.global_position)
	fired.append("hw_wrong_door")
	if intensity() == 0:
		Events.say.emit("", "Lumi...? No. Lumi could never fit behind those bars, and its glow doesn't touch the floor beneath it.", 6.5)
		Events.hint.emit("hw_wrong_door", "Real light always lights the floor. This glow lights nothing.")
	else:
		Events.caption.emit("[something small and pale waits behind the grate]")
	var comp := _companion()
	if comp != null:
		get_tree().create_timer(1.4).timeout.connect(_companion_reacts)
	Events.horror_event.emit("authored:hw_wrong_door", {})
	_suppress(60.0)


func fold_fake() -> void:
	if fake == null or not is_instance_valid(fake):
		return
	var itab: Dictionary = HorrorData.INTENSITY[intensity()]
	fake.fold(float(itab["stinger_db"]) + 2.0, not bool(Settings.get_value("reduce_flashing")))
	fake = null
	GameState.set_flag(Layout.MOMENT_WRONG_DOOR_FOLDED, true)


func _companion() -> Node:
	var id := GameState.active_companion
	if id == "":
		return null
	var c: Variant = Game.companion_nodes.get(id)
	if c is Node and is_instance_valid(c):
		return c
	return null


func _companion_reacts() -> void:
	var c := _companion()
	if c == null:
		return
	if c.has_method("react"):
		c.react("scared")
	if String(c.get("companion_id")) == "lumi":
		Events.caption.emit("[Lumi whimpers and presses close]")


func _suppress(seconds: float) -> void:
	if area != null and area.has_method("director_suppress"):
		area.director_suppress(seconds)
