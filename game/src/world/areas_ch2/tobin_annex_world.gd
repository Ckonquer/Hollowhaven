extends "res://src/world/area_base.gd"
## TOBIN'S LOST SHIFT (area "tobin_annex", docs/CHAPTER_TWO_SPEC.md §1 / §7.2 / §9; MP §7, §12, §14, §17).
## An optional Chapter One annex behind a side door beside the Hollow Mine mouth: three compact spaces in a
## warm amber mine mood (src/world/annex/annex_layout.gd holds every coordinate):
##   ta_entry   Tobin's lamp room (SAFE): the side door back to the mine mouth, the Foreman's chalk "shift
##              rules" (they teach the Hollow Drudge's two tells before the fight) and the sign-in slate.
##   ta_lockers the shift lockers: the taught Hollow Drudge encounter (spawner ta_sp_drudge), Tobin's locker
##              with his personal letter, and the lantern niche (checkpoint "ta_lantern", always safe).
##   ta_sump    down a stair: Tobin's service note by the sluice (MP §17, grants rw_c1x_tobin once), echo
##              crystals (ta_crystal_1..3), a scrawled lantern mark (the early Chapter Two clue) and the
##              shortcut hatch up to the mine mouth (opens once: ta_hatch_open).
## Spawns: annex_entry, annex_lantern (checkpoint), annex_hatch_below. Zones: ta_entry, ta_lockers, ta_sump.
## Flags set here (data/optional_goals.gd): c1x_annex_entered (arrival), c1x_drudge_defeated (spawner clear),
## c1x_tobin_shift (through the rw_c1x_tobin bundle), ta_hatch_open (hatch), c1x_tobin_letter_found (letter);
## plus c1x_lantern_mark_seen (the clue) and ta_moment_echo (the once-per-save authored moment).
## Quiet, restrained horror: no director (Game.DIRECTOR_AREAS excludes this area), one authored moment.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/annex/annex_layout.gd")
const Rooms := preload("res://src/world/annex/annex_rooms.gd")
const AnnexProps := preload("res://src/world/annex/annex_props.gd")
const DoorScript := preload("res://src/world/annex/annex_door.gd")
const HatchScript := preload("res://src/world/annex/annex_hatch.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Checkpoint := preload("res://src/world/below/checkpoint_lantern.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const HorrorData := preload("res://data/horror_events.gd")

const ENEMY_FACTORY := "res://src/enemies/enemy_factory.gd"
const ENEMY_SPAWNER := "res://src/enemies/enemy_spawner.gd"
const RESOURCE_NODE := "res://src/world/common/resource_node.gd"
const BUILD_SEED := 5150

const REWARD_ID := "rw_c1x_tobin"
const FLAG_ENTERED := "c1x_annex_entered"
const FLAG_DRUDGE := "c1x_drudge_defeated"
const FLAG_NOTE := "c1x_tobin_shift"
const FLAG_HATCH := "ta_hatch_open"
const FLAG_LETTER := "c1x_tobin_letter_found"
const FLAG_MARK := "c1x_lantern_mark_seen"
const FLAG_ECHO := "ta_moment_echo"
const HINT_DRUDGE := "ta_drudge_tells"
const LORE_RULES := "lore_ch2_shift_rules"
const LORE_LETTER := "lore_ch2_tobin_letter"
const LORE_NOTE := "lore_ch2_tobin_note"
const LORE_MARK := "lore_ch2_lantern_mark"
const NOTE_THREAT_RADIUS := 12.0       # no lore reading (letter, note, mark) with something this close
const ECHO_QUIET_RADIUS := 20.0        # the authored echo never plays over a chase (MP §14: one thing at once)
const ECHO_RETRY := 2.0                # ...it waits, re-checking while Krystal is still in the sump
const VALIDATE_PROBE := 1.9            # validate_position probes down from this far above the floor
const VALIDATE_FLOOR_TOL := 0.45

## Mood (one amber mine mood; Gentle is a little brighter, like the Below).
const BG := Color("07060b")
const AMBIENT := Color("41322a")
const FOG := Color(0.62, 0.52, 0.42)
const FOG_EMIT := Color(0.024, 0.017, 0.011)

var placeholder := false               # the real annex (wave A3's stand-in is replaced)
var builder: Builder
var env: Environment
var world_env: WorldEnvironment
var checkpoint: Node3D
var drudge_spawner: Node3D = null      # null once beaten (c1x_drudge_defeated) or when the enemy is missing (guard)
var drudge_fallback := false
var door: Node3D
var hatch: Node3D
var board_spot: Node3D
var letter_spot: Node3D
var note_spot: Node3D
var mark_spot: Node3D
var dropped_lamp: Node3D
var tobin_locker: Dictionary = {}
var crystals: Dictionary = {}          # node id -> resource node
var sump_lamp: Node3D
var ambience := "amb_mine"
var build_ms := 0
var current_zone := ""

var _prev_occlusion := false
var _echo_pending := false


func _ready() -> void:
	area_id = Layout.AREA_ID
	var t0 := Time.get_ticks_msec()
	_prev_occlusion = get_viewport().use_occlusion_culling
	get_viewport().use_occlusion_culling = true      # walls, floors and ceilings carry box occluders
	_build_environment()
	builder = Builder.new(self, BUILD_SEED, Layout.ROOMS)
	var refs: Dictionary = Rooms.build(builder, self)
	builder.finish()
	sump_lamp = refs.get("sump_lamp")
	tobin_locker = refs.get("tobin_locker", {})
	_register_spawns()
	_register_zones()
	_place_checkpoint()
	_place_exits()
	_place_story()
	_place_resources()
	_place_drudge()
	_add_daylight()
	Events.zone_entered.connect(_on_zone_entered)
	Events.settings_changed.connect(_on_settings_changed)
	build_ms = Time.get_ticks_msec() - t0
	if OS.is_debug_build():
		print("TobinAnnex: built in %d ms" % build_ms)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.use_occlusion_culling = _prev_occlusion


# --- Environment ------------------------------------------------------------------------------------------

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = AMBIENT
	env.fog_light_energy = 1.0
	env.fog_sky_affect = 0.0
	env.volumetric_fog_albedo = FOG
	env.volumetric_fog_emission = FOG_EMIT
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	world_env.environment = env
	add_child(world_env)
	_apply_quality()
	_apply_darkness()


func _apply_quality() -> void:
	var q := int(Settings.get_value("quality"))
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	env.volumetric_fog_enabled = q >= 1


func darkness() -> float:
	var i := clampi(int(Settings.get_value("horror_intensity")), 0, 2)
	return float(HorrorData.INTENSITY[i]["darkness"])


func _apply_darkness() -> void:
	var d := darkness()
	env.ambient_light_energy = 1.0 / pow(d, 2.0)
	env.volumetric_fog_density = 0.011 * d
	env.fog_density = (0.004 if env.volumetric_fog_enabled else 0.011) * d
	env.tonemap_exposure = 1.08 / sqrt(d)


func _on_settings_changed(key: String) -> void:
	if key == "horror_intensity" or key == "quality":
		_apply_quality()
		_apply_darkness()


## A faint cool daylight leaking in around the side door: the way out always reads as "outside".
func _add_daylight() -> void:
	var l := OmniLight3D.new()
	l.name = "DoorDaylight"
	l.light_color = Color("d8e4ff")
	l.light_energy = 0.35
	l.omni_range = 3.2
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.6
	add_child(l)
	l.position = Layout.POINTS["door"] + Vector3(0, 1.4, -0.6)


# --- Spawns, zones, queries ------------------------------------------------------------------------------

func _register_spawns() -> void:
	var markers := Node3D.new()
	markers.name = "SpawnPoints"
	add_child(markers)
	for id in Layout.SPAWNS:
		var xf := Layout.spawn_xform(String(id))
		register_spawn(String(id), xf)
		var m := Marker3D.new()
		m.name = "Spawn_" + String(id)
		markers.add_child(m)
		m.transform = xf


## One circle per room (registration and the base-class fallbacks); the real answers come from the room
## boxes (get_zone_at / is_safe_zone below).
func _register_zones() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var rad := Vector2(float(r["x1"]) - float(r["x0"]), float(r["z1"]) - float(r["z0"])).length() * 0.5
		add_zone(String(r["zone"]), Layout.room_center(String(id)), rad, Layout.SAFE_ROOMS.has(id))
	for s in Layout.SAFE_SPOTS:
		add_zone("ta_lockers", s["center"], float(s["radius"]), true)


func get_zone_at(pos: Vector3) -> String:
	return Layout.zone_at(pos)


func get_room_at(pos: Vector3) -> String:
	return Layout.room_at(pos)


func is_safe_zone(pos: Vector3) -> bool:
	return Layout.is_safe_point(pos)


func height_at(x: float, z: float) -> float:
	return Layout.floor_at(x, z)


## A saved / recovery position, checked against the known floor. The generic area_base probe starts 3 m up,
## which in the 3 m lamp room (and under its timber frames) lands on a beam just under the ceiling; here the
## probe starts VALIDATE_PROBE above the floor (below every beam, lamp and lintel) and the answer must lie on
## the floor itself (a crate, barrel or bench top is refused, so the recovery tries an older point).
func validate_position(pos: Vector3) -> Variant:
	if Layout.room_at(pos) == "" and Layout.room_at(pos + Vector3.UP) == "":
		return null
	if not is_inside_tree():
		return null
	var fy := Layout.floor_at(pos.x, pos.z)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, fy + VALIDATE_PROBE, pos.z), Vector3(pos.x, fy - 1.0, pos.z))
	q.collision_mask = 1 | 32
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var p: Vector3 = (hit["position"] as Vector3) + Vector3.UP * 0.1
	if absf(p.y - fy) > VALIDATE_FLOOR_TOL:
		return null
	var q2 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.UP * 1.8)
	q2.collision_mask = 1 | 32
	if not space.intersect_ray(q2).is_empty():
		return null
	return p


# --- Checkpoint and exits --------------------------------------------------------------------------------

func _place_checkpoint() -> void:
	var d: Dictionary = Layout.CHECKPOINT
	checkpoint = Checkpoint.new()
	checkpoint.setup({"id": d["id"], "spawn": d["spawn"], "zone": d["zone"], "area": Layout.AREA_ID})
	checkpoint.name = "Checkpoint_" + String(d["id"])
	checkpoint.position = d["pos"]
	var sp: Vector3 = Layout.SPAWNS[String(d["spawn"])]["pos"]
	var dir := sp - checkpoint.position
	checkpoint.rotation.y = atan2(dir.x, dir.z)
	add_child(checkpoint)


func _place_exits() -> void:
	door = DoorScript.new()
	door.setup({"variant": "interior", "target_area": "surface", "target_spawn": "annex_door"})
	door.position = Layout.POINTS["door"]
	door.rotation.y = PI                    # +Z (the side Krystal stands on) faces north, into the lamp room
	add_child(door)
	var hh: Dictionary = Layout.HATCH_HOLE
	var r: Dictionary = Layout.ROOMS["sump"]
	var floor_y := float(r["y"])
	hatch = HatchScript.new()
	hatch.setup({"variant": "ceiling", "flag": FLAG_HATCH, "target_area": "surface", "target_spawn": "annex_hatch",
		"shaft_top": float(r["h"]) + Layout.SHAFT_HEIGHT})
	hatch.position = Vector3((float(hh["x0"]) + float(hh["x1"])) * 0.5, floor_y, (float(hh["z0"]) + float(hh["z1"])) * 0.5)
	add_child(hatch)


# --- Story: notes, letter, mark ---------------------------------------------------------------------------

func _spot(id: String, pos: Vector3, size: Vector3, offset: Vector3, text_func: Callable, handler: Callable, accent: bool = true) -> Node3D:
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": size, "offset": offset, "handler": handler, "text_func": text_func, "accent": accent,
		"accent_color": Color("ffe9b8")})
	it.name = "Spot_" + id
	it.position = pos
	add_child(it)
	return it


func _place_story() -> void:
	board_spot = _spot("shift_rules", Layout.POINTS["shift_board"] + Vector3(0.25, -1.55, 0), Vector3(0.9, 1.4, 1.6), Vector3(0, 1.5, 0),
		func() -> Dictionary: return {"text": "Read the chalk board", "enabled": true}, read_shift_rules)
	letter_spot = _spot("letter", Layout.POINTS["letter"], Vector3(0.8, 1.9, 0.9), Vector3(-0.1, 1.1, 0),
		_letter_prompt, read_letter)
	note_spot = _spot("note", Layout.POINTS["note"], Vector3(1.1, 1.2, 1.4), Vector3(0.35, 0.8, 0),
		_note_prompt, read_note)
	mark_spot = _spot("mark", Layout.POINTS["mark"] + Vector3(0, -1.7, 0.4), Vector3(2.0, 2.4, 0.8), Vector3(0, 1.5, 0),
		func() -> Dictionary: return {"text": "Look at the scratched mark", "enabled": true}, read_mark)
	dropped_lamp = AnnexProps.dropped_lamp(self, Layout.POINTS["dropped_lamp"], 30.0)
	_sync_story_props()


func _letter_prompt() -> Dictionary:
	if bool(GameState.get_flag(FLAG_LETTER)):
		return {"text": "Read Tobin's letter again", "enabled": true}
	return {"text": "Open locker nine", "enabled": true}


func _note_prompt() -> Dictionary:
	if bool(GameState.get_flag(FLAG_NOTE)) or GameState.has_reward(REWARD_ID):
		return {"text": "Read Tobin's note again", "enabled": true}
	return {"text": "Read the note by the dropped lamp", "enabled": true}


## The lamp is gone once Krystal has taken it; Tobin's locker stands open once the letter was found.
func _sync_story_props() -> void:
	if dropped_lamp != null:
		dropped_lamp.visible = not (bool(GameState.get_flag(FLAG_NOTE)) or GameState.has_reward(REWARD_ID))
	var pivot: Variant = tobin_locker.get("door_pivot")
	if pivot is Node3D:
		(pivot as Node3D).rotation.y = deg_to_rad(-105.0) if bool(GameState.get_flag(FLAG_LETTER)) else 0.0


func _show_lore(id: String) -> void:
	var l: Dictionary = LoreDB.get_lore(id)
	GameState.discover_lore(id)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l["title"]), String(l["text"]), 9.0)


func read_shift_rules(_player: Node = null) -> void:
	_show_lore(LORE_RULES)


## False (with a gentle notice) while something threatening is close: lore text never plays over a fight
## (MP §14). The lamp room's chalk board is in the safe room and always readable.
func _quiet_enough() -> bool:
	if _threat_near(NOTE_THREAT_RADIUS):
		Events.notify.emit("Not now. Something is shuffling close behind you.", "warn")
		return false
	return true


## Tobin's personal letter (optional goal "The Miner Who Came Back": c1x_tobin_letter_found). Locker nine
## stands in the Drudge's hall, so it waits for quiet like the note.
func read_letter(_player: Node = null) -> void:
	if not _quiet_enough():
		return
	var first := not bool(GameState.get_flag(FLAG_LETTER))
	GameState.set_flag(FLAG_LETTER, true)
	if first:
		Audio.play_3d("chest_open", Layout.POINTS["letter"] + Vector3(0, 1.2, 0), -6.0)
		var pivot: Variant = tobin_locker.get("door_pivot")
		if pivot is Node3D and is_inside_tree():
			create_tween().tween_property(pivot, "rotation:y", deg_to_rad(-105.0), 0.6).set_trans(Tween.TRANS_SINE)
	_show_lore(LORE_LETTER)


## Tobin's service note: the lore, then the content bundle rw_c1x_tobin exactly once (sets c1x_tobin_shift,
## the Miner's Lamp unlock flag, and gives the lamp + echo shards). Not while something is chasing her.
func read_note(_player: Node = null) -> void:
	if not _quiet_enough():
		return
	_show_lore(LORE_NOTE)
	if grant_tobin_reward():
		Audio.play_3d("pickup", Layout.POINTS["dropped_lamp"] + Vector3.UP * 0.3, -4.0)
	_sync_story_props()


## Grants rw_c1x_tobin through the reward ledger (data/sources.gd REWARDS, by "content"). True only the
## first time. The objective flag is always consistent with the ledger afterwards.
func grant_tobin_reward() -> bool:
	var bundle: Dictionary = ItemDB.reward_bundle(REWARD_ID)
	var items: Dictionary = bundle.get("items", {}) if bundle.get("items", {}) is Dictionary else {}
	var flags: Array = []
	var bf: Variant = bundle.get("flags", [])
	if bf is Array:
		flags = (bf as Array).duplicate()
	if not flags.has(FLAG_NOTE):
		flags.append(FLAG_NOTE)
	var first := GameState.grant_once(REWARD_ID, items, flags, "You keep Tobin's lamp. It can light your home now.")
	if not first and not bool(GameState.get_flag(FLAG_NOTE)):
		GameState.set_flag(FLAG_NOTE, true)
	return first


## The scrawled lantern mark: the early clue to Chapter Two (the Lanternwake road lies north).
func read_mark(_player: Node = null) -> void:
	if not _quiet_enough():
		return
	GameState.set_flag(FLAG_MARK, true)
	_show_lore(LORE_MARK)


func _threat_near(radius: float) -> bool:
	var tree := get_tree()
	var p: Node3D = Game.player if Game.player != null and is_instance_valid(Game.player) else null
	if tree == null or p == null or not p.is_inside_tree():
		return false
	for e in tree.get_nodes_in_group("enemy"):
		if e is Node3D and e.has_method("is_threatening") and bool(e.is_threatening()) and (e as Node3D).global_position.distance_to(p.global_position) < radius:
			return true
	return false


# --- Echo materials ---------------------------------------------------------------------------------------

func _place_resources() -> void:
	var holder := Node3D.new()
	holder.name = "Resources"
	add_child(holder)
	var s := _load_script(RESOURCE_NODE)
	if s == null:
		return
	for r in Layout.RESOURCES:
		var n: Node3D = s.new()
		n.setup({"node_id": r["id"], "kind": r["kind"], "glow_light": true, "seed": int(hash(String(r["id"])) % 7), "yaw": float(hash(String(r["id"])) % 360)})
		n.name = String(r["id"])
		n.position = r["pos"]
		holder.add_child(n)
		crystals[String(r["id"])] = n


# --- The Hollow Drudge (taught encounter) ---------------------------------------------------------------

static func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		push_warning("TobinAnnex: script failed to load: " + path)
		return null
	return s


## True when EnemyFactory can build the Hollow Drudge (its script arrives from the enemies module).
static func drudge_available() -> bool:
	var f := _load_script(ENEMY_FACTORY)
	if f == null or not ResourceLoader.exists(ENEMY_SPAWNER):
		return false
	var id := String(Layout.DRUDGE["enemy"])
	if _script_has(f, "can_spawn"):
		return bool(f.call("can_spawn", id))       # registered, exists and compiles
	if not bool(f.call("has_enemy", id)):
		return false
	var scripts: Variant = f.get_script_constant_map().get("SCRIPTS", {})
	return scripts is Dictionary and ResourceLoader.exists(String((scripts as Dictionary).get(id, "")))


static func _script_has(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if String(m["name"]) == method:
			return true
	return false


## EnemySpawner parameters of the teaching encounter: one Drudge, never respawns once beaten.
static func drudge_params() -> Dictionary:
	var d: Dictionary = Layout.DRUDGE
	return {"enemy": d["enemy"], "count": int(d["count"]), "radius": float(d["radius"]), "respawn_minutes": float(d["respawn_minutes"]),
		"spawner_id": d["spawner_id"], "quest_flag_on_clear": d["flag"], "wander_radius": 3.0, "min_player_distance": 6.0,
		"clear_message": "The empty coat folds to the floor and lies still."}


func _place_drudge() -> void:
	var home: Vector3 = Layout.DRUDGE["pos"]
	if bool(GameState.get_flag(FLAG_DRUDGE)):
		# Dealt with (the spawner's clear, or the guard below in a build without the enemy): the empty coat
		# lies still where it worked. The world always agrees with the goal flag, whichever path set it, so a
		# save whose flag came from the guard never meets a fresh Drudge once the enemy exists.
		_build_slumped_coat(home)
		return
	if not drudge_available():
		# Guard (spec §10): the enemy arrives from another module. Until then an inert coat slumps where it
		# works and walking past it counts (anti-softlock, like the surface ruin group).
		drudge_fallback = true
		_build_slumped_coat(home)
		return
	var s := _load_script(ENEMY_SPAWNER)
	drudge_spawner = s.new()
	drudge_spawner.setup(drudge_params())
	# Already standing in the lockers when Krystal arrives: first seen from the safe lamp room.
	drudge_spawner.set("ignore_safe_zones", true)
	drudge_spawner.name = "Spawner_" + String(Layout.DRUDGE["spawner_id"])
	drudge_spawner.position = home
	add_child(drudge_spawner)


func _build_slumped_coat(home: Vector3) -> void:
	var root := Node3D.new()
	root.name = "SlumpedCoat"
	add_child(root)
	root.position = home
	var coat := Mat.outlined(Mat.toon(Color("4a4440"), {"noise": 0.18}), 0.016)
	Kit.add(root, Kit.blob(0.45, coat, 7, 0.3, 0.55), Vector3(0, 0.22, 0))
	Kit.add(root, Kit.blob(0.2, Mat.toon(Color("7f7666"), {"noise": 0.3}), 3, 0.35, 0.8), Vector3(0.2, 0.42, 0.1))
	Kit.add(root, Kit.box(Vector3(0.06, 0.9, 0.06), Mat.toon(Palette.WOOD_DARK)), Vector3(-0.4, 0.2, 0.25), Vector3(0, 30, 70))


func drudge_hint_text() -> String:
	var name_ := ItemDB.enemy_display_name(String(Layout.DRUDGE["enemy"]))
	if name_ == "" or name_ == String(Layout.DRUDGE["enemy"]):
		name_ = "Hollow Drudge"
	return "%s: when it lifts its pick high, step aside. When it drags the pick along the floor, step out of its line or roll through. Strike while it recovers." % name_


# --- Zones, arrival and the authored moment ---------------------------------------------------------------

func _on_zone_entered(zone: String) -> void:
	if Game.area != self:
		return
	on_zone(zone)


## Zone change hook (Game's 0.4 s zone poll; tests call it directly).
func on_zone(zone: String) -> void:
	if zone == current_zone:
		return
	current_zone = zone
	match zone:
		"ta_lockers":
			_enter_lockers()
		"ta_sump":
			_enter_sump()


func _enter_lockers() -> void:
	if drudge_fallback:
		if not bool(GameState.get_flag(FLAG_DRUDGE)):
			push_warning("TobinAnnex: hollow_drudge is not available; its encounter counts as dealt with.")
			GameState.set_flag(FLAG_DRUDGE, true)
		return
	if not bool(GameState.get_flag(FLAG_DRUDGE)):
		Events.hint.emit(HINT_DRUDGE, drudge_hint_text())


## "The passage answered me": the first time Krystal reaches the sump, her own footsteps come back from the
## dark end of the channel a beat too late. Once per save, never damaging, captioned; Gentle says plainly
## that it is only an echo, Intense waits longer. The music director quiets for it (authored event).
func _enter_sump() -> void:
	if bool(GameState.get_flag(FLAG_ECHO)) or _echo_pending:
		return
	if _threat_near(ECHO_QUIET_RADIUS):
		# Never layered on a chase (the Drudge may follow her down): wait, re-checking while she stays here.
		# At most one pending retry at a time; it lapses when she leaves the sump (re-entering re-arms it).
		_echo_pending = true
		if is_inside_tree():
			create_tween().tween_callback(_retry_echo).set_delay(ECHO_RETRY)
		return
	GameState.set_flag(FLAG_ECHO, true)
	var i := clampi(int(Settings.get_value("horror_intensity")), 0, 2)
	var delays := [0.9, 1.5, 2.6]
	# pos: a following companion (Mochi) looks toward the dark end of the channel, not at a random point ahead.
	Events.horror_event.emit("authored:ta_echo", {"pos": Layout.POINTS["echo"]})
	if is_inside_tree():
		create_tween().tween_callback(_echo_answer.bind(i)).set_delay(float(delays[i]))


func _retry_echo() -> void:
	_echo_pending = false
	if current_zone == "ta_sump":
		_enter_sump()


func _echo_answer(intensity: int) -> void:
	var p: Vector3 = Layout.POINTS["echo"]
	if Audio.has_sound("dir_footsteps"):
		Audio.play_3d("dir_footsteps", p, -10.0 if intensity == 0 else -7.0)
	if intensity == 0:
		Events.caption.emit("[your footsteps echo back along the channel. Only an echo.]")
	else:
		Events.caption.emit("[footsteps answer from the dark end of the channel... a beat too late]")
		if sump_lamp != null and is_instance_valid(sump_lamp) and sump_lamp.has_method("flicker"):
			sump_lamp.flicker(0.8 + 0.5 * float(intensity))    # the lamp honours reduce_flashing itself


func on_player_spawned(player: Node3D) -> void:
	GameState.set_flag(FLAG_ENTERED, true)
	if ambience != "" and Audio.has_sound(ambience):
		Audio.play_ambience(ambience, 3.0)
	current_zone = ""
	if player != null and is_instance_valid(player):
		on_zone(get_zone_at(player.global_position))
