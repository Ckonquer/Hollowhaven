extends "res://src/world/area_base.gd"
## THE HUSHED WORKS (area "hushed_works"; docs/CHAPTER_TWO_SPEC.md §1, §7.4, §10; MP §10, §14): Chapter
## Two's dungeon under the Sunken Bellhouse. Works module C7 builds rooms 1-8 and the area itself; the deep
## module adds rooms 9-14 through the API below. Cold blue-grey iron and stone, sparse metallic sounds, warm
## lantern pools; every room has its own silhouette, ceiling height, materials and light temperature:
##   1 Service Landing (safe)   low, warm, one big real lantern; the Bellhouse stair back up
##   2 Tool Lockers              cold painted iron lockers, the taught Hollow Drudge fight, the service diagram
##   3 Humming Rails             tall girdered rail hall, "Hask's Last Knock", the rail junction (ch2_true_signal)
##   4 Sluice Gallery            teal gallery of pipes and shallow channels: the WATER line (two valves)
##   5 Bellmaker's Floor         very tall bronze hall of great bells: the BELL line (symbol order)
##   6 Hall of Closed Eyes       pale carved faces, a misplaced lantern, "The Companion at the Wrong Door"
##   7 Pocket Conservatory (hub, safe)  the miners' garden under real daylight: refuge record, shortcut home,
##                               workbench, the lower ward door east at (40, -18, 0) (opens with all 3 lines)
##   8 Light Well                16 m pale well: the LIGHT line (two mirrors + reset lever), outfit alcove
## Loops (spec §7.4): 3 -> 6 -> 5 -> 7, and the deep module's real lift (room 11) back to 7 (spawn refuge).
##
## Room table: data/works_layout.gd ROOMS merged with data/works_layout_deep.gd ROOMS (if present) into
## `rooms`, built with ONE Below builder (Builder.new(self, Layout.SEED, rooms)); rooms 1-8 are built first,
## then res://src/world/works/rooms_deep.gd `static func build(area, builder)` (if present; when no deep builder
## runs, a short collapsed stub closes the far side of the ward door: deep_built), then builder.finish() once. Spawns: service_landing, works_lockers, refuge (+ crossing_gate, bell_throat,
## vault_exit: registered by the deep module, otherwise safe fallbacks in the hub). Zones: all 14 hw_* ids.
## Checkpoint lanterns: src/world/below/checkpoint_lantern.gd with area "hushed_works" (flags cp_lit_hw_*),
## named "RestPoint_<spawn>", each with a small safe nook. Safe rooms: the Landing and the Refuge.
## Horror director (Game.DIRECTOR_AREAS): director_config() hands it data/horror_events.gd WORKS_EVENTS (ambush
## events only once their enemy can be built: enemy_available()); the moments controller holds it quiet in
## unsolved puzzle rooms; authored moments suppress it.
##
## ---- API for the deep module (rooms 9-14), all callable during rooms_deep.build(area, builder) ----------------
##   area.builder / area.rooms            the shared builder (never call finish()) and the merged table
##   area.place_spawn(id, pos, yaw_deg)   register_spawn + Marker3D (register crossing_gate, bell_throat, vault_exit)
##   area.add_checkpoint(id, pos, spawn_id, zone) -> Node3D   checkpoint lantern + safe nook (ids "hw_crossing"...)
##   area.add_safe_room(room_id) / area.add_safe_area(center, radius)   (the Bell Throat is safe, spec §1)
##   area.add_anchor(room_id, zone, kind, pos)   director anchors (kinds: see data/horror_events.gd WORKS_EVENTS)
##   area.add_lore_note(lore_id, pos, {text, offset, flag, page}) -> Node3D   (LoreDB ids, data/lore_ch2_works.gd)
##   area.add_spawner(params, pos) -> Node      EnemySpawner by id; null (logged) while the enemy script is missing
##   area.enemy_available(enemy_id) -> bool     (static) EnemyFactory knows it and its script file exists
##   area.add_exit(name, params, pos, yaw_deg) -> Node3D   (src/world/works/works_exit.gd, e.g. the vault exit)
##   area.add_door(name, params, pos, yaw_deg) -> Node3D   (src/world/works/works_door.gd)
##   area.lamp(pos, opts) -> Node3D           a below_lamp.gd light (flicker_light)
##   area.director_hold(id) / director_release(id) / director_suppress(seconds)
##   area.set_fight(boss_id, active)          fight_active for Game.boss_active() + a director hold
##   area.ride_lift(target_spawn)             fade + teleport (room 11's real lift -> "refuge")
##   area.register_mood(zone, {fog, emit, ambient, density}, ambience := "")
##   signal room_changed(old_room, new_room)  (10 Hz tracker)
##   area.debug_clear_encounter(spawner_id) -> bool   (debug builds / tests only: marks an encounter cleared)
## Hooks for tests / tools, set BEFORE add_child: use_deep (false = ignore the deep files),
## deep_rooms_override (Dictionary), deep_builder_override (Callable(area, builder) or an object with build()).

signal room_changed(old_room: String, new_room: String)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const Checkpoint := preload("res://src/world/below/checkpoint_lantern.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const HorrorData := preload("res://data/horror_events.gd")
const Layout := preload("res://data/works_layout.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Geo := preload("res://src/world/works/works_geo.gd")
const WP := preload("res://src/world/works/works_props.gd")
const RoomsService := preload("res://src/world/works/rooms_service.gd")
const RoomsRails := preload("res://src/world/works/rooms_rails.gd")
const RoomsHub := preload("res://src/world/works/rooms_hub.gd")
const RoomsLines := preload("res://src/world/works/rooms_lines.gd")
const Moments := preload("res://src/world/works/works_moments.gd")
const Door := preload("res://src/world/works/works_door.gd")
const WorksExit := preload("res://src/world/works/works_exit.gd")
const SignalLamp := preload("res://src/world/works/works_signal_lamp.gd")
const Sluice := preload("res://src/world/works/works_sluice.gd")
const Bells := preload("res://src/world/works/works_bells.gd")
const LightWell := preload("res://src/world/works/works_lightwell.gd")
const Workbench := preload("res://src/world/works/works_workbench.gd")

const DEEP_LAYOUT := "res://data/works_layout_deep.gd"
const DEEP_ROOMS := "res://src/world/works/rooms_deep.gd"
const ENEMY_SPAWNER := "res://src/enemies/enemy_spawner.gd"
const ENEMY_FACTORY := "res://src/enemies/enemy_factory.gd"
const RESOURCE_NODE := "res://src/world/common/resource_node.gd"

## Per-zone mood: fog albedo / emission, ambient colour, fog density (scaled by the horror darkness).
const MOODS := {
	"hw_landing": {"fog": Color(0.62, 0.55, 0.46), "emit": Color(0.02, 0.016, 0.012), "ambient": Color("3a332c"), "density": 0.010},
	"hw_lockers": {"fog": Color(0.45, 0.52, 0.62), "emit": Color(0.012, 0.016, 0.024), "ambient": Color("28303e"), "density": 0.012},
	"hw_rails": {"fog": Color(0.42, 0.48, 0.6), "emit": Color(0.01, 0.014, 0.022), "ambient": Color("222a38"), "density": 0.016},
	"hw_sluice": {"fog": Color(0.4, 0.58, 0.56), "emit": Color(0.01, 0.02, 0.02), "ambient": Color("1f3234"), "density": 0.016},
	"hw_bells": {"fog": Color(0.6, 0.5, 0.4), "emit": Color(0.022, 0.015, 0.01), "ambient": Color("33291f"), "density": 0.012},
	"hw_eyes": {"fog": Color(0.52, 0.5, 0.6), "emit": Color(0.016, 0.014, 0.022), "ambient": Color("2a2834"), "density": 0.014},
	"hw_refuge": {"fog": Color(0.66, 0.62, 0.5), "emit": Color(0.024, 0.022, 0.014), "ambient": Color("3f3b2c"), "density": 0.008},
	"hw_lightwell": {"fog": Color(0.66, 0.64, 0.58), "emit": Color(0.022, 0.022, 0.018), "ambient": Color("383631"), "density": 0.010},
	"hw_winch": {"fog": Color(0.5, 0.48, 0.56), "emit": Color(0.014, 0.012, 0.02), "ambient": Color("2a2632"), "density": 0.015},
	"hw_crossing": {"fog": Color(0.52, 0.46, 0.62), "emit": Color(0.016, 0.012, 0.024), "ambient": Color("2c2638"), "density": 0.016},
	"hw_wrong_landing": {"fog": Color(0.44, 0.46, 0.56), "emit": Color(0.012, 0.012, 0.018), "ambient": Color("24262f"), "density": 0.016},
	"hw_porch": {"fog": Color(0.58, 0.5, 0.44), "emit": Color(0.02, 0.014, 0.012), "ambient": Color("2e2822"), "density": 0.014},
	"hw_throat": {"fog": Color(0.6, 0.52, 0.42), "emit": Color(0.02, 0.016, 0.012), "ambient": Color("342c24"), "density": 0.011},
	"hw_vault": {"fog": Color(0.5, 0.42, 0.6), "emit": Color(0.018, 0.012, 0.026), "ambient": Color("2c2438"), "density": 0.016},
}
## Ambience loop per zone (existing loops only; the metallic flavour comes from the director's cues).
const AMBIENCE := {"hw_landing": "amb_mine", "hw_lockers": "amb_mine", "hw_rails": "amb_mine", "hw_sluice": "amb_stream",
	"hw_bells": "amb_ruins", "hw_eyes": "amb_ruins", "hw_refuge": "amb_stream", "hw_lightwell": "amb_ruins",
	"hw_winch": "amb_silk", "hw_crossing": "amb_silk", "hw_wrong_landing": "amb_ruins", "hw_porch": "amb_ruins",
	"hw_throat": "amb_ruins", "hw_vault": "amb_boss"}
## The three conduits into the lower ward door: flag -> [colour, [from, to] segments along the hub walls].
const CONDUITS := {
	"ch2_line_water": [Color("8fd8f0"), [[Vector3(30.8, -14.8, -12.55), Vector3(39.45, -14.8, -12.55)], [Vector3(39.45, -14.8, -12.55), Vector3(39.45, -14.8, -2.2)]]],
	"ch2_line_bell": [Color("f0b060"), [[Vector3(22.6, -14.8, 12.55), Vector3(39.45, -14.8, 12.55)], [Vector3(39.45, -14.8, 12.55), Vector3(39.45, -14.8, 2.2)]]],
	"ch2_line_light": [Color("ffe8a0"), [[Vector3(36.6, -14.4, 12.45), Vector3(36.6, -14.4, 3.0)], [Vector3(36.6, -14.4, 3.0), Vector3(39.45, -14.4, 1.8)]]],
}
const WARD_FLAGS := ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]

# --- Test / tool hooks (before add_child) --------------------------------------------------------------------------
var use_deep: bool = true
var deep_rooms_override: Variant = null
var deep_builder_override: Variant = null
var director_override: Node = null     # tests: a director stand-in (else Game.director)

# --- State ---------------------------------------------------------------------------------------------------------
var placeholder := false                # the real Works (wave A3's stand-in is replaced); flow tests read it
var rooms: Dictionary = {}
var room_conflicts: Array = []
var deep_present: bool = false          # the deep module contributed rooms or a builder
var deep_built: bool = false            # the deep module's builder actually ran (else the collapsed stub is built)
var builder: Builder
var moments: Node
var env: Environment
var world_env: WorldEnvironment
var checkpoints: Dictionary = {}        # id -> checkpoint lantern
var safe_areas: Array = []              # [{center: Vector3, radius: float}]
var safe_rooms: Dictionary = {}         # room id -> true
var spawners: Dictionary = {}           # spawner id -> node
var skipped_spawners: Array = []        # spawner ids whose enemy script is not available yet
var resource_nodes: Dictionary = {}
var doors: Dictionary = {}
var exits: Dictionary = {}
var lore_notes: Dictionary = {}
var anchors: Array = []
var signal_lamp: Node3D = null
var false_glints: Array = []
var sluice: Node3D = null
var bells: Node3D = null
var lightwell: Node3D = null
var eyes_lantern: Node3D = null
var fight_active: bool = false
var fights: Dictionary = {}
var mood_zone: String = ""
var build_times: Dictionary = {}
var deep_spawn_fallbacks: Array = []    # deep spawn ids that got the hub fallback

var _moods: Dictionary = {}
var _ambience: Dictionary = {}
var _mood_tween: Tween
var _prev_occlusion: bool = false
var _holds: Dictionary = {}             # director hold ids requested through this area
var _director_seen: Node = null
var _hold_t: float = 0.0
var _conduit_nodes: Dictionary = {}     # flag -> [MeshInstance3D]
var _riding: bool = false
var _t0: int = 0


func _ready() -> void:
	area_id = Layout.AREA_ID
	_t0 = Time.get_ticks_msec()
	var vp := get_viewport()
	if vp != null:
		_prev_occlusion = vp.use_occlusion_culling
		vp.use_occlusion_culling = true
	_moods = MOODS.duplicate(true)
	_ambience = AMBIENCE.duplicate()
	_merge_rooms()
	for id in Layout.SAFE_ROOMS:
		safe_rooms[String(id)] = true
	_build_environment()
	builder = Builder.new(self, Layout.SEED, rooms)
	RoomsService.build(builder, self)
	RoomsRails.build(builder, self)
	RoomsHub.build(builder, self)
	RoomsLines.build(builder, self)
	_mark("rooms 1-8")
	_register_spawns()
	_place_checkpoints()
	_place_exits()
	_place_doors()
	_mark("doors")
	_place_rails()
	_place_eyes()
	_place_puzzles()
	_mark("puzzles")
	_place_hub()
	_place_lore()
	_mark("hub+lore")
	_place_resources()
	_mark("resources")
	_place_enemies()
	_place_anchors()
	_mark("nodes 1-8")
	_register_zones()          # before the deep rooms: they only add zones the area does not list yet
	deep_built = _build_deep()
	if not deep_built:
		_build_deep_stub()     # no deep builder ran (missing / broken file): never open the ward door onto the void
	_mark("deep")
	builder.finish()
	_mark("finish")
	_ensure_deep_spawns()
	moments = Moments.new()
	moments.setup(self)
	add_child(moments)
	_set_mood("hw_landing", true)
	Events.zone_entered.connect(_on_zone_entered)
	Events.settings_changed.connect(_on_settings_changed)
	Events.player_respawned.connect(_on_player_respawned)
	Events.flag_set.connect(_on_flag_set)
	build_times["total"] = Time.get_ticks_msec() - _t0
	if OS.is_debug_build():
		print("Hushed Works: built in %d ms %s" % [int(build_times["total"]), str(build_times)])


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.use_occlusion_culling = _prev_occlusion


func _mark(label: String) -> void:
	build_times[label] = Time.get_ticks_msec() - _t0


func _process(delta: float) -> void:
	_hold_t += delta
	if _hold_t < 0.5:
		return
	var dt := _hold_t
	_hold_t = 0.0
	_sync_director_holds(dt)


# --- Room table ------------------------------------------------------------------------------------------------------

func _merge_rooms() -> void:
	var deep: Dictionary = {}
	if deep_rooms_override is Dictionary:
		deep = deep_rooms_override
	elif use_deep:
		deep = Geo.load_rooms(DEEP_LAYOUT)
	var m := Geo.merge_rooms(Layout.ROOMS, deep)
	rooms = m["rooms"]
	room_conflicts = m["conflicts"]
	deep_present = not deep.is_empty()
	for id in room_conflicts:
		push_warning("Hushed Works: deep room id '%s' clashes with rooms 1-8; the rooms 1-8 entry is kept" % id)


func room_at(pos: Vector3) -> String:
	return Geo.room_at(rooms, pos)


func get_room_at(pos: Vector3) -> String:
	return Geo.room_at(rooms, pos)


func zone_of_room(room_id: String) -> String:
	return Geo.zone_of_room(rooms, room_id)


func get_zone_at(pos: Vector3) -> String:
	var r := room_at(pos)
	if r == "":
		r = Geo.nearest_room(rooms, pos)
	return zone_of_room(r)


func is_safe_zone(pos: Vector3) -> bool:
	if safe_rooms.has(room_at(pos)):
		return true
	for s in safe_areas:
		var c: Vector3 = s["center"]
		if absf(pos.y - c.y) < 3.0 and Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	return false


## Saved / respawn positions: inside a room, on solid ground found close below, with standing room above.
func validate_position(pos: Vector3) -> Variant:
	if not is_inside_tree():
		return null
	if room_at(pos) == "" and room_at(pos + Vector3.UP) == "":
		return null
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.2, pos + Vector3.DOWN * 3.0)
	q.collision_mask = 1 | 32
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var p: Vector3 = hit["position"] + Vector3.UP * 0.1
	var q2 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.UP * 1.8)
	q2.collision_mask = 1 | 32
	if not space.intersect_ray(q2).is_empty():
		return null
	return p


## Footsteps: the builder tags every floor collider with its surface; this is only the fallback.
func surface_at(_pos: Vector3) -> String:
	return "stone"


func add_safe_room(room_id: String) -> void:
	safe_rooms[room_id] = true


func add_safe_area(center: Vector3, radius: float) -> void:
	for s in safe_areas:
		if (s["center"] as Vector3).distance_to(center) < 0.1:
			return
	safe_areas.append({"center": center, "radius": radius})


func _register_zones() -> void:
	var have: Dictionary = {}
	for id in rooms:
		var r: Dictionary = rooms[id]
		var z := String(r.get("zone", ""))
		if z == "":
			continue
		var c := Geo.room_center(r)
		var rad := Vector2(float(r["x1"]) - float(r["x0"]), float(r["z1"]) - float(r["z0"])).length() * 0.5
		add_zone(z, c, rad, safe_rooms.has(String(id)))
		have[z] = true
	for z in Layout.ZONES:
		if not have.has(z):
			var c: Vector3 = Layout.DEEP_ZONE_FALLBACK_CENTRES.get(z, Vector3(60.0, -18.0, 0.0))
			add_zone(String(z), c, 4.0, false)


# --- Spawns ------------------------------------------------------------------------------------------------------------

func place_spawn(id: String, pos: Vector3, yaw_deg: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos + Vector3(0.0, 0.05, 0.0))
	register_spawn(id, xf)
	var holder := get_node_or_null("SpawnPoints")
	if holder == null:
		holder = Node3D.new()
		holder.name = "SpawnPoints"
		add_child(holder)
	var m: Marker3D = holder.get_node_or_null("Spawn_" + id)
	if m == null:
		m = Marker3D.new()
		m.name = "Spawn_" + id
		holder.add_child(m)
	m.transform = xf


func _register_spawns() -> void:
	for id in Layout.SPAWNS:
		var s: Dictionary = Layout.SPAWNS[id]
		place_spawn(String(id), s["pos"], float(s["yaw"]))


## The deep module registers crossing_gate / bell_throat / vault_exit; without it they wait in the hub.
func _ensure_deep_spawns() -> void:
	for id in Layout.DEEP_SPAWN_FALLBACKS:
		if spawns.has(id):
			continue
		var s: Dictionary = Layout.DEEP_SPAWN_FALLBACKS[id]
		place_spawn(String(id), s["pos"], float(s["yaw"]))
		deep_spawn_fallbacks.append(String(id))


# --- Environment & mood ----------------------------------------------------------------------------------------------

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("06070b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = MOODS["hw_landing"]["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_energy = 1.0
	env.fog_sky_affect = 0.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.0
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
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0


func darkness() -> float:
	var i := clampi(int(Settings.get_value("horror_intensity")), 0, 2)
	return float(HorrorData.INTENSITY[i]["darkness"])


func _apply_darkness() -> void:
	var d := darkness()
	env.ambient_light_energy = 0.95 / pow(d, 2.0)
	var m: Dictionary = _moods.get(mood_zone if mood_zone != "" else "hw_landing", MOODS["hw_landing"])
	env.volumetric_fog_density = float(m["density"]) * d
	env.fog_density = 0.012 * d if not env.volumetric_fog_enabled else 0.004 * d
	env.tonemap_exposure = 1.05 / sqrt(d)


func _set_mood(zone: String, instant: bool = false) -> void:
	if not _moods.has(zone) or zone == mood_zone:
		return
	mood_zone = zone
	var m: Dictionary = _moods[zone]
	var d := darkness()
	if _mood_tween != null and _mood_tween.is_valid():
		_mood_tween.kill()
	if instant or not is_inside_tree():
		env.volumetric_fog_albedo = m["fog"]
		env.volumetric_fog_emission = m["emit"]
		env.ambient_light_color = m["ambient"]
		env.fog_light_color = m["ambient"]
		env.volumetric_fog_density = float(m["density"]) * d
		return
	_mood_tween = create_tween().set_parallel(true)
	_mood_tween.tween_property(env, "volumetric_fog_albedo", m["fog"], 3.0)
	_mood_tween.tween_property(env, "volumetric_fog_emission", m["emit"], 3.0)
	_mood_tween.tween_property(env, "ambient_light_color", m["ambient"], 3.0)
	_mood_tween.tween_property(env, "fog_light_color", m["ambient"], 3.0)
	_mood_tween.tween_property(env, "volumetric_fog_density", float(m["density"]) * d, 3.0)


## Deep module: its own mood / ambience for a zone (overrides the defaults above).
func register_mood(zone: String, mood: Dictionary, ambience: String = "") -> void:
	var base: Dictionary = (_moods.get(zone, MOODS["hw_rails"]) as Dictionary).duplicate()
	base.merge(mood, true)
	_moods[zone] = base
	if ambience != "":
		_ambience[zone] = ambience


func _play_zone_ambience(zone: String) -> void:
	if _ambience.has(zone) and Audio.has_method("play_ambience"):
		Audio.play_ambience(String(_ambience[zone]), 3.0)


func _on_zone_entered(zone: String) -> void:
	if Game.area != self and Game.area != null:
		return
	_set_mood(zone)
	_play_zone_ambience(zone)


func _on_settings_changed(key: String) -> void:
	match key:
		"horror_intensity":
			_apply_darkness()
		"quality":
			_apply_quality()
			_apply_darkness()


func _on_player_respawned() -> void:
	if moments != null:
		moments.set("room", "")
	if Game.player != null and is_instance_valid(Game.player) and Game.area == self:
		var z := get_zone_at(Game.player.global_position)
		_set_mood(z, true)
		_play_zone_ambience(z)


func on_player_spawned(player: Node3D) -> void:
	# The stair down only exists once the service gate was opened with the Foreman's Key (Reach side); a
	# save that somehow arrives without that flag must not stall the quest step behind her.
	if not bool(GameState.get_flag("ch2_service_gate_open")):
		GameState.set_flag("ch2_service_gate_open", true)
	var z := get_zone_at(player.global_position)
	_set_mood(z, true)
	_play_zone_ambience(z)
	if moments != null:
		moments.set("room", "")
	Events.hint.emit("hw_real_light", "Real lanterns light the ground around them. Down here, trust the lights that do.")


## Called by the moments tracker whenever Krystal's room changes.
func on_room_changed(old_room: String, new_room: String) -> void:
	room_changed.emit(old_room, new_room)


# --- Director (Game.director; created by Game for DIRECTOR_AREAS) ---------------------------------------------------------

## The director's event table: WORKS_EVENTS, minus ambush ("spawn") events whose enemy cannot be built yet
## (e.g. hw_wisp_drift before borrowed_wisp is registered): such an event would telegraph a hiss and a caption,
## spawn nothing, roll its pacing back and soon try again. It joins by itself once the enemy exists.
func director_config() -> Dictionary:
	var events: Dictionary = {}
	for id in HorrorData.WORKS_EVENTS:
		var ev: Dictionary = HorrorData.WORKS_EVENTS[id]
		if String(ev.get("kind", "")) == "spawn" and not enemy_available(String(ev.get("enemy", ""))):
			continue
		events[id] = ev
	return {"events": events}


func _director() -> Node:
	if director_override != null and is_instance_valid(director_override):
		return director_override
	var d: Variant = Game.director
	if d is Node and is_instance_valid(d) and (Game.area == self or is_ancestor_of(d)):
		return d
	return null


func director_hold(hold_id: String) -> void:
	_holds[hold_id] = true
	var d := _director()
	if d != null:
		if d.has_method("hold"):
			d.hold(hold_id)
		elif d.has_method("suppress"):
			d.suppress(10.0)


func director_release(hold_id: String) -> void:
	_holds.erase(hold_id)
	var d := _director()
	if d != null and d.has_method("release"):
		d.release(hold_id)


func director_suppress(seconds: float) -> void:
	var d := _director()
	if d != null and d.has_method("suppress"):
		d.suppress(seconds)


func held_ids() -> Array:
	return _holds.keys()


## Re-applies the holds to a director created after they were requested; directors without hold() get a
## rolling suppress(10) every few seconds instead.
func _sync_director_holds(dt: float) -> void:
	var d := _director()
	if d == null:
		_director_seen = null
		return
	if d != _director_seen:
		_director_seen = d
		if d.has_method("hold"):
			for id in _holds:
				d.hold(String(id))
	if not _holds.is_empty() and not d.has_method("hold") and d.has_method("suppress"):
		d.suppress(10.0)


## Deep module: boss fights (Game.boss_active reads fight_active) with a director hold while one is on.
func set_fight(boss_id: String, active: bool) -> void:
	if active:
		fights[boss_id] = true
		director_hold("boss:" + boss_id)
	else:
		fights.erase(boss_id)
		director_release("boss:" + boss_id)
		director_suppress(20.0)
	fight_active = not fights.is_empty()


# --- Checkpoints, exits, doors ------------------------------------------------------------------------------------------

func add_checkpoint(id: String, pos: Vector3, spawn_id: String, zone: String) -> Node3D:
	var cp: Node3D = Checkpoint.new()
	cp.setup({"id": id, "spawn": spawn_id, "zone": zone, "area": area_id})
	cp.name = "RestPoint_" + spawn_id
	cp.position = pos
	if spawns.has(spawn_id):
		var sp: Vector3 = (spawns[spawn_id] as Transform3D).origin
		var dir := sp - pos
		dir.y = 0.0
		if dir.length() > 0.1:
			cp.rotation.y = atan2(dir.x, dir.z)
	add_child(cp)
	checkpoints[id] = cp
	add_safe_area(pos, Layout.CHECKPOINT_SAFE_RADIUS)
	return cp


func _place_checkpoints() -> void:
	for id in Layout.CHECKPOINTS:
		var d: Dictionary = Layout.CHECKPOINTS[id]
		add_checkpoint(String(id), d["pos"], String(d["spawn"]), String(d["zone"]))


func add_exit(exit_name: String, params: Dictionary, pos: Vector3, yaw_deg: float) -> Node3D:
	var e: Node3D = WorksExit.new()
	e.setup(params)
	e.name = "Exit_" + exit_name
	e.position = pos
	e.rotation.y = deg_to_rad(yaw_deg)
	add_child(e)
	exits[exit_name] = e
	return e


func _place_exits() -> void:
	for id in Layout.EXITS:
		var d: Dictionary = Layout.EXITS[id]
		var p: Vector3 = d["pos"]
		var r := room_at(p + Vector3.UP * 0.5)
		if r != "":
			p.y = Geo.floor_y_at(rooms[r], p.x, p.z)
		add_exit(String(id), d, p, float(d["yaw"]))


func add_door(door_name: String, params: Dictionary, pos: Vector3, yaw_deg: float) -> Node3D:
	var d: Node3D = Door.new()
	d.setup(params)
	d.name = "Door_" + door_name
	d.position = pos
	d.rotation.y = deg_to_rad(yaw_deg)
	add_child(d)
	doors[door_name] = d
	return d


func _place_doors() -> void:
	add_door("refuge_grate", {"size": Vector3(3.5, 3.4, 0.25), "flags": ["ch2_refuge_shortcut"], "style": "grate",
		"name": "The drainage stair", "closed_text": "Barred from this side. The wheel beside it lifts the bars."},
		Vector3(21.25, -18.0, -13.35), 0.0)
	add_door("eyes_route", {"size": Vector3(3.0, 3.2, 0.6), "flags": [Layout.FLAG_EYES_ROUTE], "style": "face"},
		Vector3(-20.35, -13.0, 27.5), 90.0)
	add_door("alcove_shutter", {"size": Vector3(4.0, 3.2, 0.2), "flags": ["ch2_line_light"], "style": "shutter",
		"name": "A brass shutter", "closed_text": "It is waiting for light, not a key."},
		Vector3(32.0, -20.0, 34.3), 0.0)
	add_door("ward_gate", {"size": Vector3(Layout.HUB_EAST_DOOR_SPAN[1] - Layout.HUB_EAST_DOOR_SPAN[0], Layout.HUB_EAST_DOOR_HEIGHT, 0.4),
		"flags": WARD_FLAGS, "style": "ward", "name": "The lower ward door"},
		Vector3(Layout.HUB_EAST_DOOR.x - 0.05, Layout.HUB_EAST_DOOR.y, Layout.HUB_EAST_DOOR.z), -90.0)


# --- Room 3: the true signal and the false glints -------------------------------------------------------------------------

func _place_rails() -> void:
	signal_lamp = SignalLamp.new()
	signal_lamp.name = "HaskSignalLamp"
	signal_lamp.position = Layout.SIGNAL_LAMP
	add_child(signal_lamp)
	var glint_mat := Mat.glow(Color("cfe0ff"), 1.4)
	for i in Layout.KNOCK_FALSE.size():
		var p: Vector3 = Layout.KNOCK_FALSE[i]
		var g := Kit.sphere(0.06, glint_mat, 6, 8)
		g.name = "FalseGlint_%d" % i
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		g.position = p + Vector3.UP * 0.7
		false_glints.append(g)


## The cold glint at the end of a false corridor flashes three times (it lights nothing at all).
func blink_false_signal(i: int) -> void:
	if i < 0 or i >= false_glints.size():
		return
	var g: Node3D = false_glints[i]
	if not g.is_inside_tree():
		return
	var tw := create_tween()
	for k in 3:
		tw.tween_property(g, "scale", Vector3.ONE * 2.4, 0.12)
		tw.tween_property(g, "scale", Vector3.ONE, 0.25)


# --- Room 6: the misplaced lantern ---------------------------------------------------------------------------------------

func _place_eyes() -> void:
	eyes_lantern = Node3D.new()
	eyes_lantern.name = "MisplacedLantern"
	add_child(eyes_lantern)
	var iron := Mat.outlined(Mat.toon(Color("333a46"), {"rim": 0.4}), 0.012)
	var body := Node3D.new()
	body.name = "Body"
	eyes_lantern.add_child(body)
	Kit.add(body, Kit.cylinder(0.13, 0.15, 0.05, iron, 10), Vector3.ZERO)
	Kit.add(body, Kit.cone(0.15, 0.12, iron, 10), Vector3(0, 0.36, 0))
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		Kit.add(body, Kit.box(Vector3(0.025, 0.3, 0.025), iron), Vector3(cos(a) * 0.11, 0.17, sin(a) * 0.11))
	Kit.add(body, Kit.cylinder(0.1, 0.1, 0.28, Mat.transparent(Color(1.0, 0.85, 0.6, 0.3), true), 10), Vector3(0, 0.17, 0))
	var flame := Kit.add(body, Kit.sphere(0.05, Mat.glow(Palette.LANTERN_GLOW, 3.0), 6, 8), Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1.0, 1.5, 1.0))
	flame.name = "Flame"
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = Palette.LANTERN_GLOW
	l.light_energy = 1.3
	l.omni_range = 6.0
	l.shadow_enabled = false
	body.add_child(l)
	l.position = Vector3(0, 0.2, 0)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.2, 1.2, 1.2), "offset": Vector3(0, 0.5, 0),
		"text_func": _eyes_lantern_text, "handler": Callable(self, "_hang_eyes_lantern"), "accent": true})
	it.name = "Hang"
	eyes_lantern.add_child(it)
	# the empty hook: an iron arm out of the lintel above the great face (the doorway it opens)
	var arm := Kit.add(self, Kit.box(Vector3(0.9, 0.07, 0.07), iron), Layout.EYES_LANTERN_HOOK + Vector3(-0.4, 0.66, 0.0))
	arm.name = "EyesHook"
	Kit.add(self, Kit.torus(0.04, 0.08, iron), Layout.EYES_LANTERN_HOOK + Vector3(0.0, 0.6, 0.0), Vector3(90, 90, 0))
	_apply_eyes_lantern(bool(GameState.get_flag(Layout.FLAG_EYES_ROUTE)), false)


func _eyes_lantern_text() -> Dictionary:
	if bool(GameState.get_flag(Layout.FLAG_EYES_ROUTE)):
		return {}
	return {"text": "Hang the fallen lantern back on its hook", "enabled": true}


func _hang_eyes_lantern(_player: Node = null) -> void:
	if bool(GameState.get_flag(Layout.FLAG_EYES_ROUTE)):
		return
	GameState.set_flag(Layout.FLAG_EYES_ROUTE, true)
	_apply_eyes_lantern(true, true)
	Events.caption.emit("[stone grinds: the great face lowers its chin, and a doorway opens beneath its lamp]")


func _apply_eyes_lantern(hung: bool, animate: bool) -> void:
	var body: Node3D = eyes_lantern.get_node("Body")
	var light: OmniLight3D = body.get_node("Light")
	var flame: Node3D = body.get_node("Flame")
	light.visible = hung
	flame.visible = hung
	var it := eyes_lantern.get_node_or_null("Hang")
	if hung:
		if it != null and it.has_method("disable_interaction"):
			it.disable_interaction()
		var target := Layout.EYES_LANTERN_HOOK
		if animate and eyes_lantern.is_inside_tree():
			var tw := create_tween().set_parallel(true)
			tw.tween_property(eyes_lantern, "position", target, 1.0).set_trans(Tween.TRANS_SINE)
			tw.tween_property(body, "rotation", Vector3.ZERO, 1.0)
		else:
			eyes_lantern.position = target
			body.rotation = Vector3.ZERO
	else:
		eyes_lantern.position = Layout.EYES_LANTERN_FLOOR
		body.rotation = Vector3(0.0, 0.5, 1.35)     # lying on its side
		body.position = Vector3(0, 0.14, 0)


# --- Puzzles (rooms 4, 5, 8) -----------------------------------------------------------------------------------------------

func _place_puzzles() -> void:
	sluice = Sluice.new()
	add_child(sluice)
	bells = Bells.new()
	add_child(bells)
	lightwell = LightWell.new()
	add_child(lightwell)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.4, 1.2, 1.2), "offset": Vector3(0, 0.6, 0),
		"text_func": _trunk_text, "handler": Callable(self, "_open_trunk"), "accent": true})
	it.name = "KeepsakeTrunk"
	it.position = Layout.LIGHTWELL["trunk"]
	add_child(it)
	var wood := Mat.outlined(Mat.toon(Color("8e5f3a")), 0.016)
	var brass := Mat.outlined(Mat.toon(Color("c9a25a"), {"rim": 0.4}), 0.012)
	Kit.add(it, Kit.box(Vector3(1.1, 0.55, 0.62), wood), Vector3(0, 0.28, 0))
	Kit.add(it, Kit.box(Vector3(1.14, 0.18, 0.66), wood), Vector3(0, 0.62, 0))
	for sx in [-0.4, 0.4]:
		Kit.add(it, Kit.box(Vector3(0.06, 0.74, 0.68), brass), Vector3(sx, 0.36, 0))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.1, 0.7, 0.62)
	cs.shape = sh
	cs.position = Vector3(0, 0.35, 0)
	body.add_child(cs)
	it.add_child(body)
	_sync_alcove_patterns()


## Keeps an already committed keepsake consistent (its wardrobe patterns owned); never pays anything new.
func _sync_alcove_patterns() -> void:
	if not GameState.has_reward(Layout.ALCOVE_REWARD_ID):
		return
	var pats: Variant = ItemDB.reward_bundle(Layout.ALCOVE_REWARD_ID).get("patterns", [])
	if pats is Array:
		for p in pats:
			GameState.unlock_pattern(String(p))


func _trunk_text() -> Dictionary:
	if GameState.has_reward(Layout.ALCOVE_REWARD_ID):
		return {"text": "The keepsake trunk", "enabled": false, "reason": "Empty now: its keepsake is yours."}
	return {"text": "Open the keepsake trunk", "enabled": true}


## The Light Well alcove's keepsake: the data/sources.gd REWARDS bundle rw_hw_lightwell_alcove (by "content",
## requested from the integrator: items + "patterns") through the ledger, exactly once. Until that bundle exists
## the trunk only records it was found and stays openable, so the bundle is still paid (once) when it lands.
func _open_trunk(_player: Node = null) -> bool:
	GameState.set_flag(Layout.ALCOVE_FOUND_FLAG, true)
	var bundle: Dictionary = ItemDB.reward_bundle(Layout.ALCOVE_REWARD_ID)
	if bundle.is_empty():
		Events.say.emit("", "Festival ribbons and bunting, packed away by the miners for a brighter day.", 5.0)
		return false
	var ok := GameState.grant_once(Layout.ALCOVE_REWARD_ID, bundle.get("items", {}), bundle.get("flags", []),
		"A keepsake from the miners' festival trunk.")
	if ok:
		for p in bundle.get("patterns", []):
			GameState.unlock_pattern(String(p))
		Audio.play_ui("ui_quest", -4.0)
	return ok


# --- Room 7: the refuge ---------------------------------------------------------------------------------------------------

func _place_hub() -> void:
	# The Foreman's refuge record on a lectern.
	var rec: Node3D = Interactable.new()
	rec.setup({"text": "Read the refuge record", "size": Vector3(1.2, 1.4, 1.2), "offset": Vector3(0, 0.9, 0),
		"handler": Callable(self, "_read_refuge_record"), "accent": true, "accent_color": Color("ffe9b8")})
	rec.name = "RefugeRecord"
	rec.position = Layout.REFUGE_RECORD
	rec.rotation.y = PI * 0.5
	add_child(rec)
	var wood := Mat.outlined(Mat.toon(Color("7a5a40")), 0.016)
	Kit.add(rec, Kit.box(Vector3(0.5, 1.0, 0.4), wood), Vector3(0, 0.5, 0))
	Kit.add(rec, Kit.box(Vector3(0.8, 0.08, 0.6), wood), Vector3(0, 1.08, 0), Vector3(-18, 0, 0))
	Kit.add(rec, Kit.box(Vector3(0.62, 0.04, 0.44), Mat.toon(Color("efe0bd"))), Vector3(0, 1.14, 0.02), Vector3(-18, 0, 0))
	_solid_box(rec, Vector3(0.6, 1.1, 0.5), Vector3(0, 0.55, 0))
	# The wheel that unbars the drainage stair (the shortcut home).
	var lever: Node3D = Interactable.new()
	lever.setup({"text": "", "size": Vector3(1.3, 1.6, 1.3), "offset": Vector3(0, 0.9, 0),
		"text_func": _shortcut_text, "handler": Callable(self, "_open_shortcut"), "accent": true})
	lever.name = "ShortcutWheel"
	lever.position = Layout.SHORTCUT_LEVER
	add_child(lever)
	var iron := Mat.outlined(Mat.toon(Color("333a46"), {"rim": 0.35}), 0.014)
	var brass := Mat.outlined(Mat.toon(Color("c9a25a"), {"rim": 0.45}), 0.014)
	Kit.add(lever, Kit.box(Vector3(0.3, 1.2, 0.3), iron), Vector3(0, 0.6, 0))
	var wheel := Kit.add(lever, Kit.torus(0.3, 0.4, brass), Vector3(0, 1.25, 0.2), Vector3(90, 0, 0))
	wheel.name = "Wheel"
	_solid_box(lever, Vector3(0.4, 1.4, 0.4), Vector3(0, 0.7, 0))
	# The miners' workbench (crafting station "workbench": preparation between excursions).
	var bench: Node3D = Workbench.new()
	bench.name = "MinersWorkbench"
	bench.position = Layout.WORKBENCH
	bench.rotation.y = -PI * 0.5
	add_child(bench)
	_build_conduits()


func _solid_box(parent: Node3D, size: Vector3, offset: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = offset
	body.add_child(cs)
	parent.add_child(body)


func _read_refuge_record(_player: Node = null) -> void:
	_show_lore("lore_ch2_refuge_record")
	GameState.set_flag("ch2_refuge_reached", true)
	GameState.set_flag("ch2_refuge_record", true)


func _shortcut_text() -> Dictionary:
	if bool(GameState.get_flag("ch2_refuge_shortcut")):
		return {}
	return {"text": "Turn the wheel to unbar the drainage stair", "enabled": true}


func _open_shortcut(_player: Node = null) -> void:
	if bool(GameState.get_flag("ch2_refuge_shortcut")):
		return
	GameState.set_flag("ch2_refuge_reached", true)
	GameState.set_flag("ch2_refuge_shortcut", true)
	var lever := get_node_or_null("ShortcutWheel")
	if lever != null:
		var w := lever.get_node_or_null("Wheel")
		if w is Node3D:
			create_tween().tween_property(w, "rotation:z", (w as Node3D).rotation.z + TAU, 1.4).set_trans(Tween.TRANS_SINE)
	Events.caption.emit("[chains rattle as the bars lift from the drainage stair]")
	Events.notify.emit("The drainage stair is open: a way home, any time.", "success")


func _build_conduits() -> void:
	for f in CONDUITS:
		var def: Array = CONDUITS[f]
		var m := Mat.glow(def[0], 1.8)
		var list: Array = []
		for seg in def[1]:
			var a: Vector3 = seg[0]
			var c: Vector3 = seg[1]
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.09, 0.09, 1.0)
			mi.mesh = bm
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var d := c - a
			mi.transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP).scaled_local(Vector3(1, 1, d.length())), (a + c) * 0.5)
			list.append(mi)
		_conduit_nodes[f] = list
	_refresh_conduits()


func _refresh_conduits() -> void:
	for f in _conduit_nodes:
		var on := bool(GameState.get_flag(String(f)))
		for mi in _conduit_nodes[f]:
			(mi as Node3D).visible = on


func _on_flag_set(flag: String, _v: Variant) -> void:
	if _conduit_nodes.has(flag):
		_refresh_conduits()


# --- Lore ------------------------------------------------------------------------------------------------------------------

func add_lore_note(lore_id: String, pos: Vector3, opts: Dictionary = {}) -> Node3D:
	var it: Node3D = Interactable.new()
	it.setup({"text": String(opts.get("text", "Read the note")), "size": opts.get("size", Vector3(1.0, 1.2, 1.0)),
		"offset": opts.get("offset", Vector3(0, 0.9, 0)), "accent": true, "accent_color": Color("ffe9b8"),
		"handler": Callable(self, "_read_lore_note").bind(lore_id, String(opts.get("flag", "")))})
	it.name = "Lore_" + lore_id
	it.position = pos
	add_child(it)
	if bool(opts.get("page", false)):
		var page := Kit.box(Vector3(0.26, 0.012, 0.34), Mat.toon(Color("efe0bd"), {"emission": Color("efe0bd"), "emission_energy": 0.12}))
		it.add_child(page)
		page.position = Vector3(0, 0.02, 0)
		page.rotation.y = 0.4
	lore_notes[lore_id] = it
	return it


func _read_lore_note(_player: Node, lore_id: String, flag: String) -> void:
	_show_lore(lore_id)
	if flag != "":
		GameState.set_flag(flag, true)


func _show_lore(lore_id: String) -> void:
	var l: Dictionary = LoreDB.get_lore(lore_id)
	GameState.discover_lore(lore_id)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l.get("title", "")), String(l.get("text", "")), 9.0)


func _place_lore() -> void:
	for id in Layout.LORE_SPOTS:
		var d: Dictionary = Layout.LORE_SPOTS[id]
		var off: Vector3 = d["offset"]
		add_lore_note(String(id), d["pos"], {"text": d["text"], "offset": off, "flag": d["flag"], "page": off.y < 0.7})


# --- Resources, enemies, anchors -----------------------------------------------------------------------------------------

static func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		push_warning("Hushed Works: script failed to load: " + path)
		return null
	return s


static func _script_has(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if String(m["name"]) == method:
			return true
	return false


func _place_resources() -> void:
	var holder := Node3D.new()
	holder.name = "Resources"
	add_child(holder)
	var shared := _load_script(RESOURCE_NODE)
	if shared == null:
		return
	for r in Layout.RESOURCES:
		var n: Node3D = shared.new()
		n.setup({"node_id": r["id"], "kind": r["kind"], "glow_light": String(r["kind"]) == "glowcap", "seed": int(hash(String(r["id"])) % 7)})
		n.name = String(r["id"])
		n.position = r["pos"]
		holder.add_child(n)
		resource_nodes[String(r["id"])] = n


## True when EnemyFactory knows this enemy AND its script file exists (has_enemy + script_path). Deliberately
## no compile here (EnemyFactory.can_spawn would compile every enemy script during the build, ~100 ms cold
## each); a script that exists but fails to compile is parse_all's to catch. Spawners and the director's
## ambush events use it.
static func enemy_available(enemy_id: String) -> bool:
	var factory := _load_script(ENEMY_FACTORY)
	if factory == null or enemy_id == "" or not _script_has(factory, "has_enemy"):
		return false
	if not bool(factory.call("has_enemy", enemy_id)):
		return false
	if _script_has(factory, "script_path"):
		var path := String(factory.call("script_path", enemy_id))
		return path != "" and ResourceLoader.exists(path)
	return true


## Places an enemy spawner by enemy id (EnemySpawner + EnemyFactory). Returns null (and records the id in
## skipped_spawners) while that enemy's script is not available - the room stays completable. "Available"
## means registered AND its script file exists (enemy_available): a registered id whose script has not landed
## yet would otherwise leave a spawner retrying (and warning) every half second in range.
func add_spawner(params: Dictionary, pos: Vector3) -> Node:
	var sid := String(params.get("spawner_id", ""))
	var enemy_id := String(params.get("enemy", ""))
	var s: Script = _load_script(ENEMY_SPAWNER) if enemy_available(enemy_id) else null
	if s == null:
		skipped_spawners.append(sid)
		return null
	var sp: Node = s.new()
	if sp.has_method("setup"):
		sp.setup(params)
	sp.name = "Spawner_" + sid
	if sp is Node3D:
		(sp as Node3D).position = pos
	add_child(sp)
	spawners[sid] = sp
	return sp


func _place_enemies() -> void:
	for id in Layout.SPAWNERS:
		var d: Dictionary = (Layout.SPAWNERS[id] as Dictionary).duplicate()
		d["spawner_id"] = String(id)
		var p: Vector3 = d["pos"]
		d.erase("pos")
		add_spawner(d, p)


## Debug builds / tests: marks a room encounter cleared (the spawner's clear flag and its quest flag) and
## removes its living enemies, so a missing or broken enemy never blocks a test run.
func debug_clear_encounter(spawner_id: String) -> bool:
	if not Debug.is_cheat_allowed():
		return false
	var params: Dictionary = Layout.SPAWNERS.get(spawner_id, {})
	var sp: Variant = spawners.get(spawner_id)
	if sp is Node and is_instance_valid(sp):
		if (sp as Node).has_method("despawn_all"):
			sp.despawn_all()
		var qf: Variant = (sp as Node).get("quest_flag_on_clear")
		if qf is String and String(qf) != "":
			GameState.set_flag(String(qf), true)
	GameState.set_flag("spawner_cleared_" + spawner_id, true)
	if String(params.get("quest_flag_on_clear", "")) != "":
		GameState.set_flag(String(params["quest_flag_on_clear"]), true)
	return true


func add_anchor(room_id: String, zone: String, kind: String, pos: Vector3) -> Marker3D:
	var holder := get_node_or_null("DirectorAnchors")
	if holder == null:
		holder = Node3D.new()
		holder.name = "DirectorAnchors"
		add_child(holder)
	var m := Marker3D.new()
	m.name = "Anchor_%s_%s_%d" % [room_id, kind, anchors.size()]
	m.position = pos
	m.set_meta("room", room_id)
	m.set_meta("zone", zone)
	m.set_meta("kind", kind)
	m.add_to_group("director_anchor")
	holder.add_child(m)
	anchors.append(m)
	return m


func _place_anchors() -> void:
	for a in Layout.ANCHORS:
		add_anchor(String(a[0]), String(a[1]), String(a[2]), a[3])


func lamp(pos: Vector3, opts: Dictionary = {}) -> Node3D:
	return Props.lamp(self, pos, opts)


# --- Rooms 9-14 (deep module) ----------------------------------------------------------------------------------------------

## Runs the deep module's builder. Returns true when one ran (a table without a working builder returns false).
func _build_deep() -> bool:
	var src: Variant = null
	if deep_builder_override != null:
		src = deep_builder_override
	elif use_deep and ResourceLoader.exists(DEEP_ROOMS):
		src = _load_script(DEEP_ROOMS)
	if src == null:
		return false
	deep_present = true
	if src is Callable:
		if not (src as Callable).is_valid():
			return false
		(src as Callable).call(self, builder)
		return true
	if src is Script:
		if _script_has(src as Script, "build"):
			(src as Script).call("build", self, builder)
			return true
		return false
	if src is Object and (src as Object).has_method("build"):
		(src as Object).call("build", self, builder)
		return true
	return false


## Without the deep rooms, the lower ward door opens onto a short collapsed service tunnel (never the void).
func _build_deep_stub() -> void:
	var b := builder
	b.begin("deep_stub")
	var y := Layout.HUB_EAST_DOOR.y
	var z0: float = Layout.HUB_EAST_DOOR_SPAN[0]
	var z1: float = Layout.HUB_EAST_DOOR_SPAN[1]
	var wall := Color("4f5866")
	b.floor_rect(40.0, 45.0, z0, z1, y, Color("454a52"))
	b.ceiling_rect(40.0, 45.0, z0, z1, y + Layout.HUB_EAST_DOOR_HEIGHT, Color("2a2f38"))
	b.solid(Vector3(43.0, y + 1.7, z0 - 0.5), Vector3(4.0, 3.4, 1.0), wall)
	b.solid(Vector3(43.0, y + 1.7, z1 + 0.5), Vector3(4.0, 3.4, 1.0), wall)
	b.solid(Vector3(45.5, y + 1.7, (z0 + z1) * 0.5), Vector3(1.0, 3.4, z1 - z0 + 2.0), wall)
	Props.rubble_pile(b, Vector3(44.2, y, 0.0), 1.2, 1.6, [WP.STONE, WP.STONE_DARK], 9, true)


# --- Loop B: the real lift back to the refuge (deep module calls this) ---------------------------------------------------------

func ride_lift(target_spawn: String) -> void:
	if _riding or not spawns.has(target_spawn):
		return
	_riding = true
	var was_playing := Game.mode == "playing"
	if was_playing:
		Game.set_cutscene(true)
	Audio.play_sfx("lift_move", -2.0, 0.0)
	Events.caption.emit("[the old service lift creaks and climbs]")
	if Game.ui != null and Game.ui.has_method("fade_out"):
		await Game.ui.fade_out(0.9)
	else:
		await get_tree().create_timer(0.9).timeout
	await get_tree().create_timer(1.5).timeout
	var xf := get_spawn(target_spawn)
	var p := Game.player
	if p != null and is_instance_valid(p):
		p.teleport(xf)
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and c.has_method("teleport_near"):
			c.teleport_near(xf.origin)
	if moments != null:
		moments.set("room", "")
	var z := get_zone_at(xf.origin)
	_set_mood(z, true)
	_play_zone_ambience(z)
	if Game.ui != null and Game.ui.has_method("fade_in"):
		await Game.ui.fade_in(1.0)
	if was_playing and Game.mode == "cutscene":
		Game.set_cutscene(false)
	_riding = false
