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
##     small bonus every BONUS_EVERY clears) - never a story flag, no daily limit;
##   * Events.trial_started(id) on arrival, Events.trial_ended(id, won) once per visit.
## Flow: begin(id, origin_area, origin_spawn) remembers the origin by making it the respawn point
## (Game.set_respawn) and travels here (Game.change_area never saves on arrival in a trial, and never
## moves the respawn into it). Leaving (the pale door on the entry pad, or automatically RETURN_DELAY s
## after a win) and defeat (Game respawns at the respawn point) both return to that checkpoint; a save
## never resumes inside a trial (Game.continue_game). The entry pad is safe and outside the engage
## radius; walking back onto it makes the Matron stand down.
## Other trials (Velour, Choir) can be added to TRIALS with their own builder later.

const Brazier := preload("res://src/enemies/boss_brazier.gd")
const BelowLayout := preload("res://src/world/below/below_layout.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const BOSS_SCRIPT := "res://src/enemies/weaver_boss.gd"

const TRIAL_MATRON := "matron"
const TRIALS := {
	"matron": {
		"title": "Echo Trial: The Thread Above", "alt_title": "Echo Trial: The Hollow Above",
		"subtitle": "a remembered challenge", "boss": "weaver_matron", "requires_flag": "weaver_defeated",
		"first_reward": "rw_trial_matron_first",
		"first_message": "The echo remembers you. The Moon Moth Shawl pattern can now be sewn at the Loom.",
		"repeat": {"silk": 3, "glowcap": 2}, "bonus_every": 3, "bonus": {"echo_shard": 1},
		"origin": {"area": "below", "spawn": "cp_arena"},
	},
}
const ARENA_RADIUS := 11.0
const WALL_RADIUS := 11.8
const WALL_SEGMENTS := 32
const WALL_HEIGHT := 9.0
const CEILING_Y := 12.0
const CORRIDOR_HALF := 2.5
const CORRIDOR_END := 25.0
const PAD_Z := 22.0
const RETURN_DELAY := 6.0

## Which trial the next load of this area hosts (set by begin(); consumed in _ready()).
static var pending_trial: String = ""

var trial_id: String = TRIAL_MATRON
var boss: Node = null
var braziers: Array = []
var result: String = ""          # "" | "won" | "lost" | "left"
var fighting := false
var elapsed: float = 0.0
var last_clear: Dictionary = {}

var _return_t: float = -1.0
var _ended := false


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


## Records a clear in the trial's own state and pays its reward: the first clear grants the content
## bundle (once, through the reward ledger); later clears give modest renewable resources.
## Returns {"first": bool, "clears": int, "best_seconds": float, "items": {id: n}}.
static func record_clear(id: String, seconds: float) -> Dictionary:
	var t := trial_info(id)
	var r := record(id).duplicate(true)
	var clears := int(r.get("clears", 0)) + 1
	r["clears"] = clears
	var best := float(r.get("best_seconds", 0.0))
	if seconds > 0.0 and (best <= 0.0 or seconds < best):
		best = seconds
	r["best_seconds"] = best
	GameState.trials[id] = r
	var out := {"first": false, "clears": clears, "best_seconds": best, "items": {}}
	var rid := String(t.get("first_reward", ""))
	if rid != "" and not GameState.has_reward(rid):
		var bundle: Dictionary = ItemDB.reward_bundle(rid)
		var items: Dictionary = bundle.get("items", {})
		var flags: Array = bundle.get("flags", [])
		if GameState.grant_once(rid, items, flags, String(t.get("first_message", ""))):
			out["first"] = true
			out["items"] = items.duplicate()
			return out
	var give: Dictionary = (t.get("repeat", {}) as Dictionary).duplicate()
	var every := int(t.get("bonus_every", 0))
	if every > 0 and clears % every == 0:
		var bonus: Dictionary = t.get("bonus", {})
		for k in bonus:
			give[k] = int(give.get(k, 0)) + int(bonus[k])
	var given: Dictionary = {}
	for k in give:
		if ItemDB.has_item(String(k)) and int(give[k]) > 0:
			GameState.give_item(String(k), int(give[k]))
			given[String(k)] = int(give[k])
	out["items"] = given
	if not given.is_empty():
		var parts: Array = []
		for k in given:
			parts.append("%s x%d" % [ItemDB.display_name(String(k)), int(given[k])])
		Events.notify.emit("The echo leaves something behind: " + ", ".join(parts), "item")
	return out


# --- Area ---------------------------------------------------------------------------------------------------

func _ready() -> void:
	area_id = "echo_trial"
	placeholder = false
	ambience = "amb_silk"
	if pending_trial != "" and TRIALS.has(pending_trial):
		trial_id = pending_trial
	pending_trial = ""
	bounds = Rect2(-WALL_RADIUS, -WALL_RADIUS, WALL_RADIUS * 2.0, CORRIDOR_END + WALL_RADIUS)
	build_environment({"bg": Color("0b0a12"), "ambient": Color("6d6590"), "ambient_energy": 0.42,
		"lamps": [[Vector3(0, 3.2, PAD_Z + 0.5), Color("ffe2a8"), 0.9, 7.0], [Vector3(0, 9.0, 0), Color("b6a4f0"), 0.5, 20.0]]})
	_build_room()
	place_spawn("trial_start", Vector3(0, floor_y, PAD_Z + 0.8), 0.0)
	add_zone("trial", Vector3(0, floor_y, 5.0), 22.0, false)
	add_safe_spot(Vector3(0, floor_y, PAD_Z + 0.8), 2.8)
	var door := add_exit("leave", {"text": "Leave the echo (back to the chamber door)", "use_respawn": true, "style": "stair"},
		Vector3(0, floor_y, CORRIDOR_END - 0.6), PI)
	door.set_meta("trial_exit", true)
	var plate := add_label(entry_text(trial_id).replace(" (", "\n("), Vector3(0, 3.3, PAD_Z - 1.2), 40)
	plate.modulate = Color(0.85, 0.8, 1.0, 0.85)
	_build_encounter()
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	if not Events.area_exiting.is_connected(_on_area_exiting):
		Events.area_exiting.connect(_on_area_exiting)


func get_zone_at(_pos: Vector3) -> String:
	return "trial"


func _process(delta: float) -> void:
	if fighting and result == "":
		elapsed += delta
	if _return_t >= 0.0:
		_return_t -= delta
		if _return_t < 0.0:
			leave()


func on_player_spawned(player: Node3D) -> void:
	super.on_player_spawned(player)
	Events.trial_started.emit(trial_id)
	Events.say.emit("Echo Trial", "A memory of the Heartseed Chamber. Nothing here can change what really happened - the true chamber stays at peace. Leave through the pale door whenever you like.", 7.0)
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
	Events.say.emit("", "The echo fades. The chamber is only a memory again.", 5.0)
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
