extends "res://src/world/area_base.gd"
## THE BELOW: the authored dungeon under the Hollow Mine (Chapter One). Eleven spaces, three moods:
## Old Mine (amber, timber, rails) -> Unsettling Ruins (cold teal, carved faces, water) -> Silk Hollows
## (violet-grey, webs / pale roots). Built entirely in code from below_layout.gd.
##
## Contract (docs/ARCHITECTURE.md, Area roots): spawns mine_entry, cp_landing, cp_office, cp_shrine,
## cp_arena, lift_bottom (+ lift_chamber); zones mine/ruins/silk/boss with small safe zones at the landing
## and around lit checkpoints; director anchors (group "director_anchor"); flicker lights (group
## "flicker_light"). Progression is persistent through GameState flags: gallery_cleared,
## foreman_key_taken, lower_gate_open, cp_lit_<id>, reached_silk_hollows, weaver_defeated.
## Debug (cheats only): --below-debug-light adds a lantern-like light that follows the camera.
## Chapter Two (module B9): the reworked three-phase Matron gets the arena mouth ("entrance") so no
## trip-line or egg sac is ever put across it; once "weaver_defeated" is set, a pale echo stone beside the
## arena checkpoint offers "Echo Trial: The Thread Above (a remembered challenge)" (echo_trial.gd), which
## returns here (cp_arena) when Krystal leaves or falls. The real chamber and its flags are never touched.
## The chamber's fight hold (music, director suppression) also follows Events.boss_encounter_changed, so a
## fight the Matron starts on her own is covered too.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const RoomsMine := preload("res://src/world/below/rooms_mine.gd")
const RoomsRuins := preload("res://src/world/below/rooms_ruins.gd")
const RoomsSilk := preload("res://src/world/below/rooms_silk.gd")
const SpiderDecor := preload("res://src/world/below/spider_decor.gd")
const Checkpoint := preload("res://src/world/below/checkpoint_lantern.gd")
const Rubble := preload("res://src/world/below/rubble.gd")
const LowerGate := preload("res://src/world/below/lower_gate.gd")
const ForemanDesk := preload("res://src/world/below/foreman_desk.gd")
const Lift := preload("res://src/world/below/below_lift.gd")
const Cocoon := preload("res://src/world/below/heartseed_cocoon.gd")
const Resource_ := preload("res://src/world/below/below_resource.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const Moments := preload("res://src/world/below/below_moments.gd")
const Lore := preload("res://src/world/below/lore.gd")
const HorrorData := preload("res://data/horror_events.gd")

const ENEMY_SPAWNER := "res://src/enemies/enemy_spawner.gd"
const STALKER := "res://src/enemies/stalker.gd"
const BOSS := "res://src/enemies/weaver_boss.gd"
const BRAZIER := "res://src/enemies/boss_brazier.gd"
const ECHO_TRIAL := "res://src/world/areas_ch2/echo_trial.gd"
## The echo stone: against the antechamber's west wall, 3 m north of the arena checkpoint lantern
## (clear of the walking line between the two openings; no collision).
const ECHO_ENTRY_POS := Vector3(101.1, -10.0, -112.4)
const ARENA_ENTRANCE := Vector3(105.0, -12.0, -126.5)
const RESOURCE_NODE := "res://src/world/common/resource_node.gd"

## Per-zone mood: fog albedo / emission and ambient colour.
const MOODS := {
	"mine": {"fog": Color(0.6, 0.52, 0.44), "emit": Color(0.022, 0.016, 0.012), "ambient": Color("3a2f2c"), "density": 0.012},
	"ruins": {"fog": Color(0.45, 0.62, 0.62), "emit": Color(0.01, 0.02, 0.024), "ambient": Color("24343b"), "density": 0.014},
	"silk": {"fog": Color(0.55, 0.5, 0.64), "emit": Color(0.016, 0.012, 0.024), "ambient": Color("2c2638"), "density": 0.016},
	"boss": {"fog": Color(0.55, 0.48, 0.66), "emit": Color(0.02, 0.013, 0.028), "ambient": Color("2e2640"), "density": 0.016},
}
const AMBIENCE := {"mine": "amb_mine", "ruins": "amb_ruins", "silk": "amb_silk", "boss": "amb_boss"}

var builder: Builder
var decor: Node3D
var moments: Node
var env: Environment
var world_env: WorldEnvironment
var checkpoints: Dictionary = {}       # id -> node
var safe_areas: Array = []             # [{center: Vector3, radius: float}]
var gate: Node3D
var rubble: Node3D
var desk: Node3D
var lift_chamber: Node3D
var lift_landing: Node3D
var cocoon: Node3D
var boss: Node = null
var braziers: Array = []
var spawners: Array = []
var stalker: Node = null
var echo_entry: Node3D = null
var fight_active: bool = false
var mood_zone: String = ""

var _mood_tween: Tween
var _riding: bool = false
var _debug_light: OmniLight3D
var _after_boss_light: OmniLight3D
var _landing_warm: OmniLight3D
var _prev_occlusion: bool = false


func _ready() -> void:
	area_id = "below"
	var t0 := Time.get_ticks_msec()
	# Walls, floors and ceilings carry box occluders; enable culling while the Below is loaded.
	_prev_occlusion = get_viewport().use_occlusion_culling
	get_viewport().use_occlusion_culling = true
	_build_environment()
	builder = Builder.new(self)
	decor = SpiderDecor.new()
	decor.name = "SpiderDecor"
	add_child(decor)
	RoomsMine.build(builder, self)
	RoomsRuins.build(builder, self, decor)
	RoomsSilk.build(builder, self, decor)
	builder.finish()
	decor.build()
	_register_spawns()
	_register_zones()
	_place_checkpoints()
	_place_progression()
	_place_lore()
	_place_resources()
	_place_enemies()
	_place_boss()
	_place_echo_trial()
	_place_anchors()
	moments = Moments.new()
	moments.setup(self)
	add_child(moments)
	_set_mood("mine", true)
	Events.zone_entered.connect(_on_zone_entered)
	Events.settings_changed.connect(_on_settings_changed)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.player_respawned.connect(_on_player_respawned)
	Events.player_died.connect(_on_player_died)
	Events.boss_encounter_changed.connect(_on_boss_encounter_changed)
	if bool(GameState.get_flag("weaver_defeated")):
		_apply_after_boss_state(false)
	if Debug.is_cheat_allowed() and Debug.has_arg("below-debug-light"):
		_debug_light = OmniLight3D.new()
		_debug_light.light_color = Palette.LANTERN_GLOW
		_debug_light.light_energy = 1.0
		_debug_light.omni_range = 9.0
		_debug_light.light_volumetric_fog_energy = 0.2
		_debug_light.shadow_enabled = true
		add_child(_debug_light)
	set_process(_debug_light != null)
	if OS.is_debug_build():
		print("Below: built in %d ms" % (Time.get_ticks_msec() - t0))


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.use_occlusion_culling = _prev_occlusion


func _process(_delta: float) -> void:
	if _debug_light != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_debug_light.global_position = cam.global_position + cam.global_transform.basis * Vector3(0.4, -0.3, -0.2)


# --- Environment & mood -------------------------------------------------------------------------------

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("07060b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = MOODS["mine"]["ambient"]
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
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.02
	world_env.environment = env
	add_child(world_env)
	_apply_quality()
	_apply_darkness()


func _apply_quality() -> void:
	var q := int(Settings.get_value("quality"))
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.volumetric_fog_enabled = q >= 1
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0


func darkness() -> float:
	var i := clampi(int(Settings.get_value("horror_intensity")), 0, 2)
	return float(HorrorData.INTENSITY[i]["darkness"])


## Ambient and fog scale with the horror intensity's darkness (Gentle is brighter).
func _apply_darkness() -> void:
	var d := darkness()
	env.ambient_light_energy = 0.9 / pow(d, 2.0)
	var m: Dictionary = MOODS.get(mood_zone if mood_zone != "" else "mine")
	env.volumetric_fog_density = float(m["density"]) * d
	env.fog_density = 0.012 * d if not env.volumetric_fog_enabled else 0.004 * d
	env.tonemap_exposure = 1.05 / sqrt(d)


func _set_mood(zone: String, instant: bool = false) -> void:
	if not MOODS.has(zone) or zone == mood_zone:
		return
	mood_zone = zone
	var m: Dictionary = MOODS[zone]
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


func _on_settings_changed(key: String) -> void:
	match key:
		"horror_intensity":
			_apply_darkness()
		"quality":
			_apply_quality()
			_apply_darkness()


func _play_zone_ambience(zone: String) -> void:
	if moments != null and bool(moments.get("in_silence")):
		return
	if zone == "boss" and bool(GameState.get_flag("weaver_defeated")):
		zone = "silk"      # the chamber is quiet once the Weaver has gone
	if AMBIENCE.has(zone):
		Audio.play_ambience(String(AMBIENCE[zone]), 3.0)


## Restarts the ambience after a silence. `zone` = where Krystal is now ("" = ask Game / the mood).
func resume_ambience(zone: String = "") -> void:
	var z := zone
	if z == "":
		z = Game.zone_id if Game.zone_id != "" else mood_zone
	if fight_active:
		z = "boss"
	_play_zone_ambience(z)


func _on_zone_entered(zone: String) -> void:
	if Game.area != self and Game.area != null:
		return
	_set_mood(zone)
	if fight_active:
		return
	_play_zone_ambience(zone)


# --- Spawns, zones, anchors -----------------------------------------------------------------------------

func _register_spawns() -> void:
	for id in Layout.SPAWNS:
		register_spawn(id, Layout.spawn_xform(id))


func _register_zones() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var c := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, float(r["y"]), (float(r["z0"]) + float(r["z1"])) * 0.5)
		var rad := Vector2(float(r["x1"]) - float(r["x0"]), float(r["z1"]) - float(r["z0"])).length() * 0.5
		add_zone(String(r["zone"]), c, rad, false)
	add_safe_area(Vector3(0.0, 0.0, 0.5), 6.5, "mine")


func add_safe_area(center: Vector3, radius: float, zone: String) -> void:
	for s in safe_areas:
		if (s["center"] as Vector3).distance_to(center) < 0.1:
			return
	safe_areas.append({"center": center, "radius": radius})
	add_zone(zone, center, radius, true)


## Zone by room box (levels overlap on the XZ plane, so the base circle test isn't enough).
func get_zone_at(pos: Vector3) -> String:
	var r := Layout.room_at(pos)
	if r == "":
		r = Layout.nearest_room(pos)
	return Layout.zone_of_room(r)


func get_room_at(pos: Vector3) -> String:
	return Layout.room_at(pos)


func is_safe_zone(pos: Vector3) -> bool:
	for s in safe_areas:
		var c: Vector3 = s["center"]
		if absf(pos.y - c.y) < 3.0 and Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	return false


func validate_position(pos: Vector3) -> Variant:
	if Layout.room_at(pos) == "" and Layout.room_at(pos + Vector3.UP) == "":
		return null
	return super.validate_position(pos)


func _place_anchors() -> void:
	var holder := Node3D.new()
	holder.name = "DirectorAnchors"
	add_child(holder)
	var i := 0
	for a in Layout.ANCHORS:
		var m := Marker3D.new()
		m.name = "Anchor_%s_%s_%d" % [a[0], a[2], i]
		m.position = a[3]
		m.set_meta("room", String(a[0]))
		m.set_meta("zone", String(a[1]))
		m.set_meta("kind", String(a[2]))
		m.add_to_group("director_anchor")
		holder.add_child(m)
		i += 1


# --- Checkpoints & progression ------------------------------------------------------------------------

func _place_checkpoints() -> void:
	for id in Layout.CHECKPOINTS:
		var d: Dictionary = Layout.CHECKPOINTS[id]
		var cp: Node3D = Checkpoint.new()
		cp.setup({"id": id, "spawn": d["spawn"], "zone": d["zone"]})
		cp.name = "Checkpoint_" + id
		cp.position = d["pos"]
		cp.lit_changed.connect(_on_checkpoint_lit)
		add_child(cp)
		# face the room: rotate so the lantern arm points toward the spawn point
		var sp: Vector3 = Layout.SPAWNS[d["spawn"]]["pos"]
		var dir := sp - cp.position
		dir.y = 0.0
		if dir.length() > 0.1:
			cp.rotation.y = atan2(dir.x, dir.z)
		checkpoints[id] = cp


func _on_checkpoint_lit(id: String, lit: bool) -> void:
	if not lit or not Layout.CHECKPOINTS.has(id):
		return
	var d: Dictionary = Layout.CHECKPOINTS[id]
	add_safe_area(d["pos"], Layout.SAFE_RADIUS, String(d["zone"]))


func _place_progression() -> void:
	rubble = Rubble.new()
	rubble.setup({"size": Vector3(4.0, 3.0, 3.5), "flag": "gallery_cleared", "node_id": "below_gallery_rubble"})
	rubble.name = "GalleryRubble"
	rubble.position = Layout.RUBBLE_CENTER
	add_child(rubble)
	gate = LowerGate.new()
	gate.name = "LowerGate"
	gate.position = Layout.GATE_CENTER
	add_child(gate)
	desk = ForemanDesk.new()
	desk.name = "ForemanDesk"
	desk.position = Vector3(19.35, 0.0, -43.75)
	desk.rotation.y = PI * 0.5
	add_child(desk)
	lift_landing = Lift.new()
	lift_landing.setup({"role": "landing", "area": self})
	lift_landing.name = "LiftLanding"
	lift_landing.position = Vector3(7.9, 0.0, 0.0)
	lift_landing.rotation.y = PI * 0.5
	add_child(lift_landing)
	lift_chamber = Lift.new()
	lift_chamber.setup({"role": "chamber", "area": self})
	lift_chamber.name = "LiftChamber"
	lift_chamber.position = Vector3(116.2, -12.0, -137.5)
	lift_chamber.rotation.y = PI * 0.5
	add_child(lift_chamber)
	var climb: Node3D = Interactable.new()
	climb.setup({"text": "Climb back up to the surface", "size": Vector3(2.4, 2.4, 1.6), "offset": Vector3(0, 1.2, 0), "handler": Callable(self, "_climb_out"), "accent": true})
	climb.name = "ClimbOut"
	climb.position = Vector3(0.0, 0.0, 7.7)
	add_child(climb)


func _climb_out(_player: Node) -> void:
	if fight_active:
		return
	Audio.play_sfx("step_wood", -4.0)
	Game.change_area("surface", "mine_exit")


func _place_lore() -> void:
	var labels := {"landing_notice": "Read the notice", "ward_keeper": "Read the carving"}
	var offsets := {"landing_notice": Vector3(0, 1.7, 0.2), "miner_journal_1": Vector3(0, 0.8, 0), "ward_keeper": Vector3(0, 0.9, 0.0)}
	for id in Layout.LORE_SPOTS:
		if id == "foreman_order":
			continue    # the foreman's desk handles its own note
		var pos: Vector3 = Layout.LORE_SPOTS[id]
		var it: Node3D = Interactable.new()
		var off: Vector3 = offsets.get(id, Vector3(0, 0.35, 0))
		it.setup({"text": String(labels.get(id, "Read the page")), "size": Vector3(1.0, 1.0, 1.0), "offset": off,
			"handler": Callable(self, "_read_lore").bind(id), "accent": true, "accent_color": Color("ffe9b8")})
		it.name = "Lore_" + id
		it.position = pos
		add_child(it)
		if not offsets.has(id):
			# a loose page on the floor
			var page := Kit.box(Vector3(0.26, 0.012, 0.34), Mat.toon(Color("efe0bd"), {"emission": Color("efe0bd"), "emission_energy": 0.12}))
			it.add_child(page)
			page.position = Vector3(0, 0.02, 0)
			page.rotation.y = 0.4


func _read_lore(_player: Node, id: String) -> void:
	var l: Dictionary = Lore.get_lore(id)
	GameState.discover_lore(id)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l["title"]), String(l["text"]), 9.0)


func _place_resources() -> void:
	var holder := Node3D.new()
	holder.name = "Resources"
	add_child(holder)
	# Shared world harvestables (same look/feedback as the surface) when available, else our own.
	var shared := _load_script(RESOURCE_NODE)
	for r in Layout.RESOURCES:
		var n: Node3D
		if shared != null:
			n = shared.new()
			n.setup({"node_id": r["id"], "kind": r["kind"], "glow_light": String(r["kind"]) != "silk", "seed": int(hash(String(r["id"])) % 7)})
		else:
			n = Resource_.new()
			n.setup({"id": r["id"], "kind": r["kind"]})
		n.name = String(r["id"])
		n.position = r["pos"]
		holder.add_child(n)


# --- Enemies & boss (other modules; skipped gracefully when missing) -----------------------------------

static func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		push_warning("Below: script failed to load: " + path)
		return null
	return s


func _spawn_node(path: String, params: Dictionary, pos: Vector3, node_name: String) -> Node:
	var s := _load_script(path)
	if s == null:
		return null
	var n: Node = s.new()
	if n.has_method("setup"):
		n.setup(params)
	n.name = node_name
	if n is Node3D:
		(n as Node3D).position = pos
	add_child(n)
	return n


func _place_enemies() -> void:
	var g := _spawn_node(ENEMY_SPAWNER, {"enemy": "gloomling", "count": 2, "radius": 3.0, "respawn_minutes": -1.0, "spawner_id": "gallery_gloom"}, Vector3(-0.5, 0.0, -44.0), "Spawner_gallery")
	if g != null:
		spawners.append(g)
	# Between the south pillars; radius kept small so no spawn point lands in the wall or a pillar.
	var h := _spawn_node(ENEMY_SPAWNER, {"enemy": "gloomling", "count": 2, "radius": 1.2, "respawn_minutes": 720.0, "spawner_id": "hall_gloom"}, Vector3(33.5, -6.0, -64.5), "Spawner_hall")
	if h != null:
		spawners.append(h)
	# The stalker is the Weaver itself: once it has retreated into the deep crack it stops haunting
	# the passages (a calm way home, and free play afterwards).
	if bool(GameState.get_flag("weaver_defeated")):
		return
	var route: Array = []
	for p in Layout.STALKER_ROUTE:
		route.append(p)
	var amb: Array = []
	for p in Layout.STALKER_AMBUSH:
		amb.append(p)
	stalker = _spawn_node(STALKER, {"route": route, "ambush_points": amb, "zone": "silk"}, Layout.STALKER_ROUTE[0], "Stalker")


func _place_boss() -> void:
	var defeated := bool(GameState.get_flag("weaver_defeated"))
	var ceiling: Array = []
	for a in Layout.ARENA_ANCHORS:
		ceiling.append(a)
	var boss_script := _load_script(BOSS)
	cocoon = Cocoon.new()
	cocoon.setup({"ceiling": ceiling.slice(0, 4), "fallback": boss_script == null and not defeated})
	cocoon.name = "HeartseedCocoon"
	cocoon.position = Layout.ARENA_CENTER
	add_child(cocoon)
	if boss_script == null and not defeated:
		push_warning("Below: weaver_boss.gd unavailable - the Heartseed can be freed by hand (fallback).")
	for i in Layout.BRAZIERS.size():
		var bz := _spawn_node(BRAZIER, {"id": "brazier_%d" % i, "anchor": Layout.ARENA_ANCHORS[i], "anchor_index": i}, Layout.BRAZIERS[i], "Brazier_%d" % i)
		if bz != null:
			braziers.append(bz)
	if defeated:
		# The boss is gone for good; if the Heartseed was left behind, the boss module's own rule
		# re-creates exactly one pickup (group "heartseed_pickup"). Our cocoon only covers a missing boss.
		if boss_script != null and _script_has(boss_script, "ensure_heartseed") and _script_has(boss_script, "should_spawn_heartseed"):
			cocoon.safety_net = false
			if bool(boss_script.call("should_spawn_heartseed")):
				boss_script.call("ensure_heartseed", self, Layout.ARENA_CENTER)
		return
	if boss_script == null:
		return
	boss = boss_script.new()
	if boss.has_method("setup"):
		boss.setup({"arena_center": Layout.ARENA_CENTER, "anchors": ceiling, "braziers": braziers, "entrance": ARENA_ENTRANCE})
	boss.name = "WeaverBoss"
	if boss is Node3D:
		(boss as Node3D).position = Layout.ARENA_CENTER
	add_child(boss)


# --- Echo Trial entry (completed saves only) ------------------------------------------------------------

func _place_echo_trial() -> void:
	if not bool(GameState.get_flag("weaver_defeated")):
		return
	var s := _load_script(ECHO_TRIAL)
	if s == null:
		return
	var it: Node3D = Interactable.new()
	it.setup({"text": "Echo Trial", "size": Vector3(1.3, 1.8, 1.3), "offset": Vector3(0, 0.9, 0),
		"handler": Callable(self, "_enter_echo_trial"), "text_func": Callable(self, "_echo_trial_prompt"),
		"accent": true, "accent_color": Color("cbb8ff")})
	it.name = "EchoTrialEntry"
	it.position = ECHO_ENTRY_POS
	add_child(it)
	_build_echo_stone(it)
	echo_entry = it


func _echo_trial_prompt() -> Dictionary:
	var s := _load_script(ECHO_TRIAL)
	if s == null or not bool(GameState.get_flag("weaver_defeated")):
		return {}
	return {"text": String(s.call("entry_text", "matron")), "enabled": true}


## The trial menu, then travels: the same menu as the other echo stones (echo_trial.gd menu_text("matron"): the
## memory - not undone history -, the trial's record (clears, best time) and what a clear leaves); the arena
## checkpoint becomes the return point (leaving or falling in the trial brings Krystal back here).
func _enter_echo_trial(_player: Node) -> void:
	if fight_active or _riding or Game.mode != "playing":
		return
	var s := _load_script(ECHO_TRIAL)
	if s == null:
		return
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("confirm"):
		var m: Dictionary = s.call("menu_text", "matron")
		var c: String = await Game.ui.confirm(String(m.get("title", s.call("entry_text", "matron"))), String(m.get("body", "")),
			[["enter", "Enter the echo", "AccentButton"], ["cancel", "Not now", ""]])
		if c != "enter" or not is_instance_valid(self) or Game.mode != "playing":
			return
	s.call("begin", "matron", "below", "cp_arena")


func _build_echo_stone(parent: Node3D) -> void:
	var stone := Mat.outlined(Mat.toon(Color("6a6282"), {"rim": 0.35, "noise": 0.18}), 0.014)
	var body := Kit.blob(0.42, stone, 13, 0.18, 1.9, 2)
	Kit.add(parent, body, Vector3(0, 0.62, 0))
	var band := Kit.torus(0.43, 0.48, Mat.glow(Color("cbb8ff"), 1.2))
	Kit.add(parent, band, Vector3(0, 0.72, 0), Vector3.ZERO, Vector3(1, 1.8, 1))
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := Kit.torus(0.6, 0.68, Mat.glow(Color("a998e6"), 0.6))
	Kit.add(parent, ring, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.2, 1))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _script_has(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if String(m["name"]) == method:
			return true
	return false


func boss_alive() -> bool:
	return boss != null and is_instance_valid(boss) and not bool(GameState.get_flag("weaver_defeated"))


## Called by the moments controller whenever the player's room changes.
func on_room_changed(old: String, new_room: String) -> void:
	var in_arena := new_room == "arena" or new_room == "lift_recess"
	if in_arena and boss_alive() and not fight_active:
		_start_fight()
	elif not in_arena and fight_active and new_room != "arena_way":
		_stop_fight_music()


func _start_fight() -> void:
	fight_active = true
	for m in ["start_fight", "begin_fight", "start", "activate"]:
		if boss.has_method(m):
			boss.call(m)
			break
	Audio.request_music("boss_matron", "music_boss", 1.5)
	Audio.play_ambience("amb_boss", 2.0)
	Events.horror_event.emit("authored:boss", {})
	if Game.director != null and is_instance_valid(Game.director) and Game.director.has_method("suppress"):
		Game.director.suppress(9999.0)


func _stop_fight_music() -> void:
	fight_active = false
	Audio.release_music("boss_matron", 3.0)
	_director_suppress(20.0)
	resume_ambience()


## Replaces the director's boss-fight hold (suppress(9999)) with a normal quiet period.
func _director_suppress(seconds: float) -> void:
	if Game.area != self and Game.area != null:
		return
	if Game.director != null and is_instance_valid(Game.director) and Game.director.has_method("suppress"):
		Game.director.suppress(seconds)


func _on_boss_defeated(boss_id: String) -> void:
	if Game.area != self and Game.area != null:
		return
	if boss_id != "weaver_matron":
		return            # another boss (or a trial) never marks this chamber as won
	GameState.set_flag("weaver_defeated", true)
	var was_fighting := fight_active
	if fight_active:
		fight_active = false
		Audio.release_music("boss_matron", 5.0)
	Audio.play_ambience("amb_silk", 4.0)
	_apply_after_boss_state(true)
	if stalker != null and is_instance_valid(stalker):
		stalker.queue_free()          # the Weaver has gone into the crack: no more ambushes on the way home
	stalker = null
	if was_fighting:
		_director_suppress(240.0)     # a calm walk home after the climax (ends the 9999 s fight hold)


## Module B9: the reworked Matron can wake on her own before the room tracker sees Krystal in the arena
## (she steps within its engage radius on the entrance ramp, or lights a brazier from the edge): the
## chamber then takes the same fight hold as on entering (music, boss ambience, the random director
## suppressed for the whole encounter - MP section 14). When the encounter stands down because she walked
## out, the hold is released to a normal quiet period. A fall (_on_player_died) and the victory
## (_on_boss_defeated) keep their own, longer recovery holds.
func _on_boss_encounter_changed(boss_id: String, active: bool) -> void:
	if boss_id != "weaver_matron" or (Game.area != self and Game.area != null) or not boss_alive():
		return
	if active:
		if not fight_active:
			_start_fight()
		return
	if not fight_active or Game.mode == "dead":
		return
	var st: Variant = boss.get("state")
	if st is String and String(st) in ["defeat", "gone"]:
		return
	_stop_fight_music()


func _on_player_died() -> void:
	if fight_active:
		fight_active = false
		Audio.release_music("boss_matron", 1.5)
		_director_suppress(30.0)      # the fight hold must not outlive the fight (death recovery)


func _on_player_respawned() -> void:
	if moments != null:
		moments.set("room", "")
	if Game.player != null and is_instance_valid(Game.player):
		var z := get_zone_at(Game.player.global_position)
		_set_mood(z, true)
		_play_zone_ambience(z)


## After the Weaver: warm light in the chamber and at the landing, the lift runs, the cocoon is open.
func _apply_after_boss_state(animate: bool) -> void:
	if _after_boss_light == null:
		_after_boss_light = OmniLight3D.new()
		_after_boss_light.name = "AfterBossLight"
		_after_boss_light.light_color = Color("ffcf9a")
		_after_boss_light.omni_range = 16.0
		_after_boss_light.light_volumetric_fog_energy = 0.5
		_after_boss_light.distance_fade_enabled = true
		_after_boss_light.distance_fade_begin = 40.0
		_after_boss_light.distance_fade_length = 10.0
		add_child(_after_boss_light)
		_after_boss_light.position = Layout.ARENA_CENTER + Vector3(0, 6.0, 0)
	if _landing_warm == null:
		_landing_warm = OmniLight3D.new()
		_landing_warm.name = "LandingWarmth"
		_landing_warm.light_color = Color("ffd9a0")
		_landing_warm.omni_range = 10.0
		_landing_warm.light_volumetric_fog_energy = 0.5
		add_child(_landing_warm)
		_landing_warm.position = Vector3(1.0, 3.2, 3.0)
	for l in get_tree().get_nodes_in_group("below_shaft_light"):
		if l is SpotLight3D and is_ancestor_of(l):
			(l as SpotLight3D).light_energy = 3.2
	if animate:
		_after_boss_light.light_energy = 0.0
		_landing_warm.light_energy = 1.1
		var tw := create_tween()
		tw.tween_property(_after_boss_light, "light_energy", 1.3, 4.0).set_trans(Tween.TRANS_SINE)
	else:
		_after_boss_light.light_energy = 1.3
		_landing_warm.light_energy = 1.1


# --- The lift & THE RETURN ---------------------------------------------------------------------------

## Rides the lift to another spawn: fade, lift_move, teleport (companions follow), fade back in.
func ride_lift(target_spawn: String) -> void:
	if _riding or not spawns.has(target_spawn):
		return
	_riding = true
	var going_up := target_spawn == "lift_bottom"
	var was_playing := Game.mode == "playing"
	if was_playing:
		Game.set_cutscene(true)
	Audio.play_sfx("lift_move", -2.0, 0.0)
	Events.caption.emit("[the old lift groans and begins to rise]" if going_up else "[the old lift creaks downward]")
	if Game.ui != null and Game.ui.has_method("fade_out"):
		await Game.ui.fade_out(0.9)
	else:
		await get_tree().create_timer(0.9).timeout
	await get_tree().create_timer(2.0).timeout
	var p := Game.player
	var xf := get_spawn(target_spawn)
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
	if going_up and not GameState.get_flag("moment_return"):
		GameState.set_flag("moment_return", true)
		Events.horror_event.emit("authored:return", {})
	if Game.ui != null and Game.ui.has_method("fade_in"):
		await Game.ui.fade_in(1.2)
	if going_up:
		Events.say.emit("", "Warm air drifts down from the surface. The way home is open.", 4.5)
	if was_playing and Game.mode == "cutscene":
		Game.set_cutscene(false)
	_riding = false


# --- Player arrival ---------------------------------------------------------------------------------------

func on_player_spawned(player: Node3D) -> void:
	GameState.set_flag("entered_below", true)
	if bool(GameState.get_flag("weaver_defeated")):
		GameState.set_flag("heartseed_spawned_checked", true)
	Audio.release_music("", 2.0)     # the music director picks the Below's music (or silence)
	var z := get_zone_at(player.global_position)
	_set_mood(z, true)
	_play_zone_ambience(z)
	if moments != null:
		moments.set("room", Layout.room_at(player.global_position))
	Events.hint.emit("below_lantern", "It's dark down here. Press {lantern} to raise your lantern.")
	if Debug.is_cheat_allowed() and Debug.has_arg("below-moment"):
		_debug_moment.call_deferred(Debug.arg("below-moment"), player)


## QA only (cheats): fire an authored moment immediately for screenshots.
func _debug_moment(id: String, player: Node3D) -> void:
	if not Debug.is_cheat_allowed() or moments == null:
		return
	moments.hold = true
	match id:
		"crossing":
			moments.fire_crossing()
		"imitation":
			moments.start_imitation(player)
		"silk":
			moments.start_silk_intro()
		"return":
			GameState.set_flag("weaver_defeated", true)
			ride_lift("lift_bottom")
