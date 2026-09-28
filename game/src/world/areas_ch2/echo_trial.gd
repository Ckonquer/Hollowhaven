extends "res://src/world/areas_ch2/placeholder_area.gd"
## ECHO TRIAL (area "echo_trial", docs/CHAPTER_TWO_SPEC.md section 1, MP sections 8 and 15): an optional,
## REMEMBERED replay of a boss, in its own instance. Today: the Weaver Matron ("matron") - "Echo Trial:
## The Thread Above (a remembered challenge)" - offered for completed saves at the Below's pre-arena
## checkpoint (below_world.gd). A faithful copy of the Heartseed Chamber (same anchors and braziers,
## relative to the centre) with the full three-phase Matron in "trial" mode.
##
## Isolation (never undone history):
##   * the trial boss never reads or writes "weaver_defeated", never emits Events.boss_defeated, never
##     spawns a Heartseed; the braziers have no persist flags; nothing here sets a story flag;
##   * its own state: GameState.trials[<id>] = {"clears", "best_seconds"} (the trial-scoped counter);
##   * first clear: the content reward bundle rw_trial_matron_first through GameState.grant_once (the
##     Moon Moth Shawl pattern unlock flag); every later clear: modest renewable resources (REPEAT, plus a
##     small bonus every BONUS_EVERY clears) - never a story flag, no daily limit. They are NOT given inside
##     the echo (a full backpack would drop them in the arena, and every trial shares this area id): they wait
##     in the trial's record ("pending", saved) and are paid on arrival back at the origin (pay_pending);
##   * Events.trial_started(id) on arrival, Events.trial_ended(id, won) once per visit.
## Flow: begin(id, origin_area, origin_spawn) remembers the origin by making it the respawn point
## (Game.set_respawn) and travels here (Game.change_area never saves on arrival in a trial, and never
## moves the respawn into it). Leaving (the pale door on the entry pad, or automatically RETURN_DELAY s
## after a win) and defeat (Game respawns at the respawn point) both return to that checkpoint; a save
## never resumes inside a trial (Game.continue_game). The entry pad is safe and outside the engage
## radius; walking back onto it makes the Matron stand down.
##
## MORE TRIALS (module D1): the table is data/trials.gd (TRIALS; the Matron entry is unchanged). Count Velour
## ("velour", "Echo Trial: The Last Waltz", from the manor's ballroom rest candles) and the Borrowed Choir ("choir",
## "Echo Trial: The Borrowed Song", from the Hushed Works' Bell Throat) are built by their arena builders
## (src/world/trial/velour_trial.gd, choir_trial.gd: `static func build(area) -> Dictionary`), which spawn the REAL
## boss scripts in "trial" mode with fresh, isolated props (no persist flags, no story listeners). Same flow, same
## pale door, same rules. The Matron keeps her own room below (_build_room / _build_encounter), exactly as before.
## Trial-scoped ledger: GameState.trials[id] also keeps "last_seconds", "repeat_paid" (repeat clears paid) and
## "paid" ({item: total} from repeat clears), plus - between a won repeat clear and the arrival home - "pending"
## ({item: n}, merged when several wait) and "pending_clears" (how many clears it holds). The trial menu
## (src/world/trial/trial_entry.gd, and the Below's stone) shows menu_text(id): the memory text, the record
## (clears, best time) and what a clear leaves.
## THE ECHO'S GIFT (lead decision L08): init() (idempotent; Game.wire_session_systems calls it at session start and
## record_clear() calls it too) connects Events.area_loaded to pay_pending(area_id): on arrival in any non-transient
## area - the origin: leaving, falling and Continue all land there - every pending item goes through
## GameState.give_item (overflow drops at the safe origin checkpoint), moves into "paid" / "repeat_paid", and
## "pending" is erased; one toast. Same path for all three trials; the first-clear ledger grant is unchanged.

const Brazier := preload("res://src/enemies/boss_brazier.gd")
const BelowLayout := preload("res://src/world/below/below_layout.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const CameraBlock := preload("res://src/camera/camera_block.gd")
const TrialsData := preload("res://data/trials.gd")
const BOSS_SCRIPT := "res://src/enemies/weaver_boss.gd"

const TRIAL_MATRON := "matron"
const TRIALS := TrialsData.TRIALS
const ARENA_RADIUS := 11.0
const WALL_RADIUS := 11.8
const WALL_SEGMENTS := 32
const WALL_HEIGHT := 9.0
const CEILING_Y := 12.0
const CORRIDOR_HALF := 2.5
## The corridor runs 5.2 m past the pad's spawn to the end wall, so the follow camera has its full arm behind
## Krystal on arrival (visual QA IN-00: it used to wedge between the pale door and the end wall).
const CORRIDOR_END := 28.0
const PAD_Z := 22.0
## The pale door stands flush against the end wall (its posts are 0.25 m deep): no gap to park the camera in.
const EXIT_INSET := 0.14
## Camera-only box over the pale door (local to the door node): the arm stops in front of the door.
const DOOR_BLOCK_CENTER := Vector3(0.0, 1.6, 0.0)
const DOOR_BLOCK_SIZE := Vector3(2.0, 3.2, 0.3)
## The title plate and record line (billboards at camera height) fade out while the camera is close, so it never
## flies through giant letters on the way into the arena (IN-01). Label3D visibility range, fading itself.
const PLATE_FADE_BEGIN := 4.5
const PLATE_FADE_MARGIN := 1.5
## The plates never run into the corridor walls: the text is scaled down to fit this width (metres).
const MATRON_PLATE_WIDTH := CORRIDOR_HALF * 2.0 - 0.6
const RETURN_DELAY := 6.0

## Which trial the next load of this area hosts (set by begin(); consumed in _ready()).
static var pending_trial: String = ""
## True once init() wired the echo's gift payer (Events.area_loaded -> pay_pending).
static var _gift_wired: bool = false

var trial_id: String = TRIAL_MATRON
var boss: Node = null
var braziers: Array = []
var result: String = ""          # "" | "won" | "lost" | "left"
var fighting := false
var elapsed: float = 0.0
var last_clear: Dictionary = {}
var arena: Dictionary = {}           # what the trial's arena builder returned (non-Matron trials; tests read it)
var record_label: Label3D = null     # the trial's record under the title plate

var _return_t: float = -1.0
var _ended := false
var _fade_t: float = -1.0


# --- Static API (used by below_world.gd and tests) ------------------------------------------------------

static func trial_info(id: String) -> Dictionary:
	return TRIALS.get(id, {})


## A trial is offered once its story fight is won (e.g. "weaver_defeated" for the Matron).
static func is_available(id: String) -> bool:
	var t := trial_info(id)
	return not t.is_empty() and bool(GameState.get_flag(String(t.get("requires_flag", ""))))


static func entry_text(id: String) -> String:
	var t := trial_info(id)
	if t.is_empty():
		return ""
	var title := String(t.get("alt_title", t["title"])) if bool(Settings.get_value("arachnophobia")) else String(t["title"])
	return "%s (%s)" % [title, String(t.get("subtitle", "a remembered challenge"))]


## Remembers the origin (it becomes the respawn point) and which trial to host. Does not travel.
static func prepare(id: String, origin_area: String, origin_spawn: String) -> void:
	pending_trial = id
	if origin_area != "" and origin_spawn != "":
		Game.set_respawn(origin_area, origin_spawn)


## Enters the trial from its origin checkpoint.
static func begin(id: String, origin_area: String, origin_spawn: String) -> void:
	prepare(id, origin_area, origin_spawn)
	Game.change_area("echo_trial", "trial_start")


static func record(id: String) -> Dictionary:
	var r: Variant = GameState.trials.get(id)
	return (r as Dictionary) if r is Dictionary else {"clears": 0, "best_seconds": 0.0}


## Wires the echo's gift payer (Events.area_loaded -> pay_pending). Idempotent; cheap (no node, no per-frame work).
static func init() -> void:
	_gift_wired = true
	if not Events.area_loaded.is_connected(pay_pending):
		Events.area_loaded.connect(pay_pending)


## Disconnects the payer (tests; the next session wiring or record_clear() connects it again).
static func shutdown() -> void:
	_gift_wired = false
	if Events.area_loaded.is_connected(pay_pending):
		Events.area_loaded.disconnect(pay_pending)


static func is_listening() -> bool:
	return _gift_wired and Events.area_loaded.is_connected(pay_pending)


## Where the trial's origin is, for the toast ("the ballroom candles"; data/trials.gd origin_name).
static func origin_name(id: String) -> String:
	var n := String(trial_info(id).get("origin_name", ""))
	return n if n != "" else "the echo stone"


## What waits for Krystal back at the origin: {item: n} summed over every trial ({} when nothing waits).
static func pending_gifts() -> Dictionary:
	var out: Dictionary = {}
	for id in GameState.trials:
		var r: Variant = GameState.trials[id]
		if not (r is Dictionary) or not ((r as Dictionary).get("pending") is Dictionary):
			continue
		var pend: Dictionary = (r as Dictionary)["pending"]
		for k in pend:
			if int(pend[k]) > 0:
				out[String(k)] = int(out.get(String(k), 0)) + int(pend[k])
	return out


## Pays every echo's gift waiting in GameState.trials[*]["pending"] on arrival in `area_id` (Events.area_loaded).
## Never inside a trial (Game.TRANSIENT_AREAS): leaving, falling and Continue all land at the origin, which pays.
## The trial's ledger is written first ("paid" / "repeat_paid" grow, "pending" is erased, so a re-entrant call never
## pays twice), then each item goes through GameState.give_item; whatever does not fit drops at the safe origin
## checkpoint as a persistent pickup of THIS area. One toast for everything paid. Returns {item: n} paid.
static func pay_pending(area_id: String) -> Dictionary:
	var total: Dictionary = {}
	if area_id == "" or Game.TRANSIENT_AREAS.has(area_id):
		return total
	for id in GameState.trials.keys():
		var r: Variant = GameState.trials[id]
		if not (r is Dictionary) or not (r as Dictionary).has("pending"):
			continue
		var rec: Dictionary = (r as Dictionary).duplicate(true)
		var pend: Dictionary = rec["pending"] if rec["pending"] is Dictionary else {}
		var n_clears := maxi(int(rec.get("pending_clears", 1)), 1)
		rec.erase("pending")
		rec.erase("pending_clears")
		var paid: Dictionary = (rec.get("paid") as Dictionary).duplicate() if rec.get("paid") is Dictionary else {}
		var give: Dictionary = {}
		for k in pend:
			var n := int(pend[k])
			if n <= 0 or not ItemDB.has_item(String(k)):
				continue
			give[String(k)] = n
			paid[String(k)] = int(paid.get(String(k), 0)) + n
		rec["paid"] = paid
		rec["repeat_paid"] = int(rec.get("repeat_paid", 0)) + n_clears
		GameState.trials[id] = rec
		if give.is_empty():
			continue
		var drop: Variant = _gift_drop_pos(area_id)
		for k in give:
			GameState.give_item(String(k), int(give[k]), drop)
			total[k] = int(total.get(k, 0)) + int(give[k])
	if not total.is_empty():
		var parts: Array = []
		for k in total:
			parts.append("%s x%d" % [ItemDB.display_name(String(k)), int(total[k])])
		Events.notify.emit("The echo's gift: " + ", ".join(parts), "item")
	return total


## The safe origin checkpoint in the area just loaded (the respawn spawn, which a trial sets to its origin), else
## null (GameState.give_item then drops at Krystal's feet, where she arrived).
static func _gift_drop_pos(area_id: String) -> Variant:
	var a: Node = Game.area
	if a == null or not is_instance_valid(a) or Game.area_id != area_id:
		return null
	if String(GameState.player.get("respawn_area", "")) != area_id:
		return null
	var rs := String(GameState.player.get("respawn_spawn", ""))
	var sp: Variant = a.get("spawns")
	if rs == "" or not (sp is Dictionary) or not (sp as Dictionary).has(rs) or not a.has_method("get_spawn"):
		return null
	var xf: Variant = a.call("get_spawn", rs)
	return (xf as Transform3D).origin if xf is Transform3D else null


## The first-clear content bundle of a trial: data/sources.gd REWARDS (ItemDB) when catalogued there, else the
## trial table's own copy (data/trials.gd FIRST_REWARDS). {} when the trial has none.
static func first_bundle(id: String) -> Dictionary:
	var rid := String(trial_info(id).get("first_reward", ""))
	if rid == "":
		return {}
	var b: Dictionary = ItemDB.reward_bundle(rid)
	if b.is_empty():
		b = TrialsData.FIRST_REWARDS.get(rid, {})
	return b


## True once the trial's first-clear reward is in the ledger.
static func first_clear_paid(id: String) -> bool:
	var rid := String(trial_info(id).get("first_reward", ""))
	return rid != "" and GameState.has_reward(rid)


## Display name of the trial's first-clear pattern (the catalogue's, else the table's fallback name).
static func pattern_name(id: String) -> String:
	var t := trial_info(id)
	var p: Dictionary = ItemDB.pattern(String(t.get("pattern", "")))
	return String(p.get("name", t.get("pattern_name", "")))


## Records a clear in the trial's own state and pays its reward: the first clear grants the content
## bundle (once, through the reward ledger); later clears earn modest renewable resources, which WAIT in the
## trial's record ("pending", merged with any gift still waiting) and are paid on arrival back at the origin
## (pay_pending moves them into the trial's own ledger: repeat_paid, paid). Nothing is given or dropped here.
## Returns {"first": bool, "clears": int, "best_seconds": float, "items": {id: n}, "pending": bool}
## ("items": what this clear earned; "pending": true when it waits for the trip home).
static func record_clear(id: String, seconds: float) -> Dictionary:
	var t := trial_info(id)
	var r := record(id).duplicate(true)
	var clears := int(r.get("clears", 0)) + 1
	r["clears"] = clears
	var best := float(r.get("best_seconds", 0.0))
	if seconds > 0.0 and (best <= 0.0 or seconds < best):
		best = seconds
	r["best_seconds"] = best
	r["last_seconds"] = maxf(seconds, 0.0)
	GameState.trials[id] = r
	var out := {"first": false, "clears": clears, "best_seconds": best, "items": {}, "pending": false}
	var rid := String(t.get("first_reward", ""))
	if rid != "" and not GameState.has_reward(rid):
		var bundle := first_bundle(id)
		var items: Dictionary = bundle.get("items", {})
		var flags: Array = bundle.get("flags", [])
		# The Loom line only when the pattern really is in the catalogue (else just the remembered clear).
		var msg := String(t.get("first_message", ""))
		if String(t.get("pattern", "")) != "" and ItemDB.pattern(String(t["pattern"])).is_empty():
			msg = "The echo remembers you."
		if GameState.grant_once(rid, items, flags, msg):
			out["first"] = true
			out["items"] = items.duplicate()
			return out
	var give := TrialsData.repeat_items(id, clears)
	var given: Dictionary = {}
	for k in give:
		if ItemDB.has_item(String(k)) and int(give[k]) > 0:
			given[String(k)] = int(give[k])
	out["items"] = given
	if given.is_empty():
		# Nothing to carry home: the repeat clear is settled at once (the trial-scoped ledger still counts it).
		r["repeat_paid"] = int(r.get("repeat_paid", 0)) + 1
		GameState.trials[id] = r
		return out
	# The echo's gift waits in the trial's record until she is back at the origin (pay_pending).
	var pend: Dictionary = (r.get("pending") as Dictionary).duplicate() if r.get("pending") is Dictionary else {}
	for k in given:
		pend[k] = int(pend.get(k, 0)) + int(given[k])
	r["pending"] = pend
	r["pending_clears"] = int(r.get("pending_clears", 0)) + 1
	GameState.trials[id] = r
	out["pending"] = true
	init()
	Events.notify.emit("The echo's gift waits for you back at %s." % origin_name(id), "item")
	return out


## "Cleared 3 times - best time 2:31" / "Not cleared yet." (the trial's own record).
static func record_line(id: String) -> String:
	var r := record(id)
	var clears := int(r.get("clears", 0))
	if clears <= 0:
		return "Not cleared yet."
	return "Cleared %d %s - best time %s" % [clears, "time" if clears == 1 else "times",
		TrialsData.format_time(float(r.get("best_seconds", 0.0)))]


## What the next clear leaves: the first-clear pattern, else the modest renewable resources of a repeat.
static func reward_line(id: String) -> String:
	var t := trial_info(id)
	if not first_clear_paid(id) and String(t.get("first_reward", "")) != "":
		# Only promise the pattern when the catalogue really has it (data/appearance.gd).
		if ItemDB.pattern(String(t.get("pattern", ""))).is_empty():
			return "First clear: the echo will remember you."
		return "First clear: the %s pattern, to sew at the Loom." % pattern_name(id)
	var parts: Array = []
	for k in t.get("repeat", {}):
		if ItemDB.has_item(String(k)):
			parts.append("%s x%d" % [ItemDB.display_name(String(k)), int(t["repeat"][k])])
	var every := int(t.get("bonus_every", 0))
	var line := "Each clear leaves a little: " + ", ".join(parts) + "."
	if every > 0 and not (t.get("bonus", {}) as Dictionary).is_empty():
		var bonus: Array = []
		for k in t["bonus"]:
			if ItemDB.has_item(String(k)):
				bonus.append(ItemDB.display_name(String(k)))
		line += " Every %s clear adds %s." % [_ordinal(every), " and ".join(bonus)]
	return line


static func _ordinal(n: int) -> String:
	match n:
		2:
			return "second"
		3:
			return "third"
		4:
			return "fourth"
	return "%dth" % n


## The trial menu: {"title", "body", "record", "reward"} (the entry stone shows it in a confirm dialog).
static func menu_text(id: String) -> Dictionary:
	var t := trial_info(id)
	if t.is_empty():
		return {}
	var memory := String(t.get("memory", ""))
	if memory.contains("%s"):
		memory = memory % ItemDB.enemy_display_name(String(t.get("boss", "")))
	var rec := record_line(id)
	var rew := reward_line(id)
	return {"title": entry_text(id), "body": "%s\n\n%s\n%s" % [memory, rec, rew], "record": rec, "reward": rew}


# --- Area ---------------------------------------------------------------------------------------------------

func _ready() -> void:
	area_id = "echo_trial"
	placeholder = false
	ambience = "amb_silk"
	if pending_trial != "" and TRIALS.has(pending_trial):
		trial_id = pending_trial
	pending_trial = ""
	if trial_id != TRIAL_MATRON:
		ambience = String(trial_info(trial_id).get("ambience", ambience))
		if _build_from_builder():
			_connect_flow()
			return
	bounds = Rect2(-WALL_RADIUS, -WALL_RADIUS, WALL_RADIUS * 2.0, CORRIDOR_END + WALL_RADIUS)
	build_environment({"bg": Color("0b0a12"), "ambient": Color("6d6590"), "ambient_energy": 0.42,
		"lamps": [[Vector3(0, 3.2, PAD_Z + 0.5), Color("ffe2a8"), 0.9, 7.0], [Vector3(0, 9.0, 0), Color("b6a4f0"), 0.5, 20.0]]})
	_build_room()
	place_spawn("trial_start", Vector3(0, floor_y, PAD_Z + 0.8), 0.0)
	add_zone("trial", Vector3(0, floor_y, 5.0), 22.0, false)
	add_safe_spot(Vector3(0, floor_y, PAD_Z + 0.8), 2.8)
	var door := add_exit("leave", {"text": String(trial_info(trial_id).get("exit_text", "Leave the echo (back to the chamber door)")), "use_respawn": true, "style": "stair"},
		Vector3(0, floor_y, CORRIDOR_END - EXIT_INSET), PI)
	door.set_meta("trial_exit", true)
	CameraBlock.add_box(door, DOOR_BLOCK_CENTER, DOOR_BLOCK_SIZE)
	var plate := add_label(entry_text(trial_id).replace(" (", "\n("), Vector3(0, 3.3, PAD_Z - 1.2), 40)
	plate.modulate = Color(0.85, 0.8, 1.0, 0.85)
	fade_near_camera(plate)
	fit_width(plate, MATRON_PLATE_WIDTH)
	_add_record_label(Vector3(0, 2.55, PAD_Z - 1.2))
	fit_width(record_label, MATRON_PLATE_WIDTH)
	_build_encounter()
	_connect_flow()


func _connect_flow() -> void:
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	if not Events.area_exiting.is_connected(_on_area_exiting):
		Events.area_exiting.connect(_on_area_exiting)


## Velour / Choir (data/trials.gd "builder"): the builder builds the environment, the arena, its props and the
## real boss in trial mode, and returns {"pad": Vector3, "exit": Vector3, "exit_yaw": float, "bounds": Rect2,
## "zone_center": Vector3, "zone_radius": float, "plate": Vector3, "boss": Node or null, ...props}. The area adds
## the shared parts: the trial_start spawn on the safe pad, the "trial" zone, the pale door, the title plate.
## False when the builder is missing / broken (the Matron room then stands in, without an encounter: a quiet
## memory whose pale door still leads home - never a softlock).
func _build_from_builder() -> bool:
	var path := String(trial_info(trial_id).get("builder", ""))
	if path == "" or not ResourceLoader.exists(path):
		return false
	var s: Variant = load(path)
	if not (s is Script) or not (s as Script).can_instantiate():
		push_warning("EchoTrial: arena builder failed to load: " + path)
		return false
	var got: Variant = (s as Script).call("build", self)
	if not (got is Dictionary) or not (got as Dictionary).has("pad"):
		push_warning("EchoTrial: arena builder returned no layout: " + path)
		return false
	arena = got
	var pad: Vector3 = arena["pad"]
	bounds = arena.get("bounds", Rect2())
	place_spawn("trial_start", pad, 0.0)
	add_zone("trial", arena.get("zone_center", Vector3.ZERO), float(arena.get("zone_radius", 30.0)), false)
	add_safe_spot(pad, 2.8)
	var door := add_exit("leave", {"text": String(trial_info(trial_id).get("exit_text", "Leave the echo")), "use_respawn": true, "style": "stair"},
		arena.get("exit", pad + Vector3(0, 0, 2.5)), float(arena.get("exit_yaw", PI)))
	door.set_meta("trial_exit", true)
	CameraBlock.add_box(door, DOOR_BLOCK_CENTER, DOOR_BLOCK_SIZE)
	var plate_pos: Vector3 = arena.get("plate", pad + Vector3(0, 3.3, -2.0))
	var plate := add_label(entry_text(trial_id).replace(" (", "\n("), plate_pos, 40)
	plate.modulate = Color(0.85, 0.8, 1.0, 0.85)
	fade_near_camera(plate)
	var plate_w := float(arena.get("plate_width", MATRON_PLATE_WIDTH))
	fit_width(plate, plate_w)
	_add_record_label(plate_pos + Vector3(0, -0.75, 0))
	fit_width(record_label, plate_w)
	var b: Variant = arena.get("boss")
	if b is Node and is_instance_valid(b):
		boss = b
		_wire_boss()
	return true


## The trial's own record under the title plate (clears, best time).
func _add_record_label(pos: Vector3) -> void:
	record_label = add_label(record_line(trial_id), pos, 26)
	record_label.modulate = Color(0.85, 0.8, 1.0, 0.7)
	fade_near_camera(record_label)


## A plate that hangs at camera height fades itself out while the camera is within ~PLATE_FADE_BEGIN m of it.
static func fade_near_camera(l: Label3D) -> void:
	l.visibility_range_begin = PLATE_FADE_BEGIN
	l.visibility_range_begin_margin = PLATE_FADE_MARGIN
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Width (metres) of a Label3D's longest line (measured with its font, like the renderer lays it out).
static func label_width(l: Label3D) -> float:
	var f: Font = l.font
	if f == null and ThemeDB.get_project_theme() != null:
		f = ThemeDB.get_project_theme().get_font("font", "Label3D")
	if f == null:
		f = ThemeDB.fallback_font
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
	return (w + float(l.outline_size)) * l.pixel_size


## Scales a billboard plate's text down (pixel size, so the glyphs stay crisp) until it fits `max_width` metres:
## a plate wider than its corridor pokes through the walls and reads clipped ("o Trial: The Last W").
static func fit_width(l: Label3D, max_width: float) -> void:
	var w := label_width(l)
	if w > max_width and w > 0.0:
		l.pixel_size *= max_width / w


func _wire_boss() -> void:
	if boss.has_signal("defeated") and not boss.is_connected("defeated", _on_boss_defeated):
		boss.connect("defeated", _on_boss_defeated)
	if boss.has_signal("state_changed") and not boss.is_connected("state_changed", _on_boss_state):
		boss.connect("state_changed", _on_boss_state)


func get_zone_at(_pos: Vector3) -> String:
	return "trial"


func _process(delta: float) -> void:
	if fighting and result == "":
		elapsed += delta
	if _fade_t >= 0.0:
		_fade_t -= delta
		if _fade_t < 0.0:
			Events.say.emit("", String(trial_info(trial_id).get("fade", "The echo fades.")), 5.0)
	if _return_t >= 0.0:
		_return_t -= delta
		if _return_t < 0.0:
			leave()


func on_player_spawned(player: Node3D) -> void:
	super.on_player_spawned(player)
	Events.trial_started.emit(trial_id)
	Events.say.emit("Echo Trial", String(trial_info(trial_id).get("intro", "A memory. Nothing here can change what really happened. Leave through the pale door whenever you like.")), 7.0)
	Events.hint.emit("echo_trial", "Echo Trials are remembered challenges: your journey, flags and Heartseed are never touched. Clear it for a reward.")


# --- Encounter ----------------------------------------------------------------------------------------------

func _build_encounter() -> void:
	if trial_id != TRIAL_MATRON:
		return
	var c := BelowLayout.ARENA_CENTER
	var holder := Node3D.new()
	holder.name = "Braziers"
	add_child(holder)
	for i in BelowLayout.BRAZIERS.size():
		var b: Node3D = Brazier.new()
		b.setup({"id": "trial_brazier_%d" % i})
		b.name = "Brazier_%d" % i
		var bp: Vector3 = BelowLayout.BRAZIERS[i]
		b.position = Vector3(bp.x - c.x, floor_y, bp.z - c.z)
		holder.add_child(b)
		braziers.append(b)
	var anchors: Array = []
	for a in BelowLayout.ARENA_ANCHORS:
		var av: Vector3 = a
		anchors.append(Vector3(av.x - c.x, av.y - c.y + floor_y, av.z - c.z))
	_build_anchor_knots(anchors)
	if not ResourceLoader.exists(BOSS_SCRIPT):
		return
	var s: Script = load(BOSS_SCRIPT)
	if s == null or not s.can_instantiate():
		push_warning("EchoTrial: boss script failed to load")
		return
	boss = s.new()
	boss.setup({"arena_center": Vector3(0, floor_y, 0), "arena_radius": ARENA_RADIUS, "anchors": anchors,
		"braziers": braziers, "mode": "trial", "entrance": Vector3(0, floor_y, ARENA_RADIUS),
		"crack": Vector3(0, CEILING_Y, 0)})
	boss.name = "EchoMatron"
	add_child(boss)
	if boss.has_signal("defeated"):
		boss.connect("defeated", _on_boss_defeated)
	if boss.has_signal("state_changed"):
		boss.connect("state_changed", _on_boss_state)


func _on_boss_state(_s: String) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var started := bool(boss.get("fight_started"))
	if started and not fighting and result == "":
		fighting = true
	elif not started and fighting and result == "":
		fighting = false        # stood down (she stepped back onto the pad); the clock pauses


func _on_boss_defeated() -> void:
	if result != "":
		return
	result = "won"
	fighting = false
	last_clear = record_clear(trial_id, elapsed)
	_end(true)
	if record_label != null and is_instance_valid(record_label):
		record_label.text = record_line(trial_id)
	# The Matron's line comes at once (as it always has); Velour / Choir let the boss's own farewell (the Count's
	# line, the Choir's chimes) play first.
	var delay := float(trial_info(trial_id).get("fade_delay", 0.0))
	if delay <= 0.0:
		Events.say.emit("", String(trial_info(trial_id).get("fade", "The echo fades. The chamber is only a memory again.")), 5.0)
	else:
		_fade_t = delay
	_return_t = RETURN_DELAY


func _on_player_died() -> void:
	if Game.area != null and Game.area != self:
		return
	if result != "":
		return
	result = "lost"
	fighting = false
	_end(false)


func _on_area_exiting(_id: String) -> void:
	if Game.area != null and Game.area != self:
		return
	if result == "":
		result = "left"
		fighting = false
		_end(false)


func _end(won: bool) -> void:
	if _ended:
		return
	_ended = true
	Events.trial_ended.emit(trial_id, won)


## Back to the trial's origin (the respawn point set by begin()).
func leave() -> void:
	_return_t = -1.0
	if Game.area != self:
		return
	if Game.mode != "playing":
		_return_t = 1.0          # e.g. a menu is open: try again in a moment
		return
	var e: Variant = exits.get("leave")
	if e is Node and is_instance_valid(e) and (e as Node).has_method("destination"):
		var d: Dictionary = (e as Node).destination()
		Game.change_area(String(d["area"]), String(d["spawn"]))


# --- Room ------------------------------------------------------------------------------------------------------

func _build_room() -> void:
	var floor_mat := Mat.toon(Color("2b2638"), {"noise": 0.16, "noise_scale": 1.3, "rim": 0.1})
	var wall_mat := Mat.outlined(Mat.toon(Color("3a3350"), {"noise": 0.2, "noise_scale": 0.9, "rim": 0.2}), 0.02)
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	# Floor: the round chamber + the corridor to the entry pad (one slab each).
	_box_collider(body, Vector3(0, floor_y - 1.0, 0), Vector3(WALL_RADIUS * 2.0 + 1.0, 2.0, WALL_RADIUS * 2.0 + 1.0))
	_box_collider(body, Vector3(0, floor_y - 1.0, (WALL_RADIUS + CORRIDOR_END) * 0.5), Vector3(CORRIDOR_HALF * 2.0 + 1.0, 2.0, CORRIDOR_END - WALL_RADIUS + 1.0))
	var disc := Kit.cylinder(WALL_RADIUS, WALL_RADIUS, 0.2, floor_mat, 48)
	Kit.add(self, disc, Vector3(0, floor_y - 0.1, 0))
	var corridor := Kit.box(Vector3(CORRIDOR_HALF * 2.0, 0.2, CORRIDOR_END - WALL_RADIUS + 0.6), floor_mat)
	Kit.add(self, corridor, Vector3(0, floor_y - 0.1, (WALL_RADIUS + CORRIDOR_END) * 0.5))
	# Round wall with a gap for the corridor (south, +z).
	var seg_len := TAU * WALL_RADIUS / float(WALL_SEGMENTS) + 0.25
	for k in WALL_SEGMENTS:
		var a := TAU * (float(k) + 0.5) / float(WALL_SEGMENTS)
		var p := Vector3(cos(a) * (WALL_RADIUS + 0.4), floor_y + WALL_HEIGHT * 0.5, sin(a) * (WALL_RADIUS + 0.4))
		if p.z > 0.0 and absf(p.x) < CORRIDOR_HALF + seg_len * 0.5:
			continue
		var yaw := -a + PI * 0.5
		_box_collider(body, p, Vector3(seg_len, WALL_HEIGHT, 0.8), yaw)
		var wm := Kit.box(Vector3(seg_len, WALL_HEIGHT, 0.8), wall_mat)
		Kit.add(self, wm, p, Vector3(0, rad_to_deg(yaw), 0))
	# Corridor walls + end wall.
	var clen := CORRIDOR_END - WALL_RADIUS + 1.0
	for sx in [-1.0, 1.0]:
		var p := Vector3(float(sx) * (CORRIDOR_HALF + 0.4), floor_y + 2.0, (WALL_RADIUS + CORRIDOR_END) * 0.5)
		_box_collider(body, p, Vector3(0.8, 4.0, clen))
		Kit.add(self, Kit.box(Vector3(0.8, 4.0, clen), wall_mat), p)
	# Fillers where the round wall meets the corridor (no gap to step off the floor).
	for sx in [-1.0, 1.0]:
		var p := Vector3(float(sx) * (CORRIDOR_HALF + 1.7), floor_y + 2.0, WALL_RADIUS + 0.2)
		_box_collider(body, p, Vector3(2.6, 4.0, 1.4))
		Kit.add(self, Kit.box(Vector3(2.6, 4.0, 1.4), wall_mat), p)
	var endp := Vector3(0, floor_y + 2.0, CORRIDOR_END + 0.4)
	_box_collider(body, endp, Vector3(CORRIDOR_HALF * 2.0 + 1.6, 4.0, 0.8))
	Kit.add(self, Kit.box(Vector3(CORRIDOR_HALF * 2.0 + 1.6, 4.0, 0.8), wall_mat), endp)
	# Ceiling (visual): a dark vault.
	var ceil := Kit.cylinder(WALL_RADIUS + 0.8, WALL_RADIUS + 0.8, 0.4, Mat.toon(Color("1b1826"), {"rim": 0.0}), 48)
	Kit.add(self, ceil, Vector3(0, floor_y + CEILING_Y, 0))
	ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A pale ring where the cocoon lay in the real chamber (the memory's centre; no Heartseed here).
	var ring := Kit.torus(0.8, 0.95, Mat.glow(Color("c9b8ff"), 0.6))
	Kit.add(self, ring, Vector3(0, floor_y + 0.03, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drifting pale motes: this is a memory.
	var motes := CPUParticles3D.new()
	motes.name = "EchoMotes"
	var mm := SphereMesh.new()
	mm.radius = 0.03
	mm.height = 0.06
	mm.radial_segments = 6
	mm.rings = 3
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.85, 0.8, 1.0, 0.7)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.material = pm
	motes.mesh = mm
	motes.amount = 48
	motes.lifetime = 6.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(WALL_RADIUS * 0.8, 3.0, WALL_RADIUS * 0.8)
	motes.direction = Vector3.UP
	motes.spread = 30.0
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.2
	motes.gravity = Vector3(0, 0.05, 0)
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.position = Vector3(0, floor_y + 3.5, 0)
	add_child(motes)


## A short stone stalactite down to each ceiling anchor (where the Matron can hang).
func _build_anchor_knots(anchors: Array) -> void:
	var m := Mat.outlined(Mat.toon(Color("2f2a40"), {"noise": 0.2, "rim": 0.15}), 0.015)
	for a in anchors:
		var av: Vector3 = a
		var h := maxf(floor_y + CEILING_Y - av.y, 0.4)
		var st := Kit.cylinder(0.45, 0.12, h, m, 8)
		Kit.add(self, st, Vector3(av.x, av.y + h * 0.5, av.z))
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box_collider(body: StaticBody3D, pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	cs.rotation.y = yaw
	body.add_child(cs)
