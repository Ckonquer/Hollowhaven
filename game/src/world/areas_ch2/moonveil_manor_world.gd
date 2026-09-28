extends "res://src/world/area_base.gd"
## Moonveil Manor interior (area "moonveil_manor"; docs/CHAPTER_TWO_SPEC.md §1, §7.3, §10; MP §9, §11 step 7,
## §13.1, §14, §15, §17). Five spaces in a row with a return loop, all data in data/manor_layout.gd:
##   Entrance Cloakroom (mm_cloakroom, SAFE, front door out)  - low, warm wood and plum wallpaper
##   Looking-Glass Hall  (mm_hall)       - long, silver-lilac, mirrors that show only true light
##   Ballroom            (mm_ballroom)   - tall, rose and gold; candle-routing puzzle; checkpoint manor_ballroom;
##                                         "The Empty Waltz" on the clockwork cloak rail
##   Count's Gallery     (mm_gallery)    - crimson arena: three ward candles, curtains, central fixture, cover
##   Conservatory Balcony(mm_balcony, SAFE) - open to the night sky; the Moonveil lantern; checkpoint
##                                         manor_balcony; shortcut gate (servants' stair / garden stair)
## Side rooms (Count's Wardrobe scraps): Powder Room (hall), Musicians' Nook (ballroom), Dressing Room (gallery).
## Built with src/world/manor/manor_builder.gd (batched MultiMeshes, per-room collision bodies), warm
## candlelit WorldEnvironment, no volumetric fog, at most 3 shadowed lights. Areas never touch the music.
##
## Boss hook (Count Velour, a later wave): if ch2_velour_defeated is false and EnemyFactory can spawn
## "count_velour", it is spawned at the arena centre on load with setup keys {arena_center, arena_radius,
## candles (ward_candle nodes), teach_candle, curtains (Marker3D), fixture (Node3D), cover (Vector3s),
## helper_points, entry, area, no_drops} and waits. MP §13.1 "teach one candle before combat": two ward
## candles burn, the teaching candle (ARENA.teach_candle) waits dark with a hint; once Krystal stands in the
## arena with it lit, the encounter starts (fight_active; the first of start_fight/begin_fight/start/activate
## is called; the area says the first bow, once per visit). Leaving the Gallery or dying pauses it (the first
## of reset_fight/stop_fight/end_fight; every ward candle burns again for a fair restart).
## Events.boss_defeated("count_velour") -> mark_velour_defeated(). Missing boss script (or a spawn that fails,
## or a Count node that vanishes without a defeat): the fallback lets the three ward candles break the
## enchantment (never a softlock); debug_mark_velour_defeated() for tests/QA. A ch2_velour_defeated flag set by
## anyone else is picked up on the next encounter tick. The boss must keep ONE node for the whole encounter.
## Ambience per zone (Layout.AMBIENCE): the house is quiet, the balcony hears the night. Echo Trial hook: after
## the Count is freed, an echo stone by the ballroom rest candles offers his trial once echo_trial.gd has one.

const Layout := preload("res://data/manor_layout.gd")
const Builder := preload("res://src/world/manor/manor_builder.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const PuzzleScript := preload("res://src/world/manor/candle_route_puzzle.gd")
const CheckpointScript := preload("res://src/world/manor/manor_checkpoint.gd")
const DoorScript := preload("res://src/world/manor/manor_door.gd")
const SealedDoor := preload("res://src/world/manor/sealed_door.gd")
const ScrapScript := preload("res://src/world/manor/velvet_scrap_pickup.gd")
const LanternScript := preload("res://src/world/manor/manor_lantern.gd")
const GateScript := preload("res://src/world/manor/shortcut_gate.gd")
const ResidentScript := preload("res://src/world/manor/count_resident.gd")
const WaltzScript := preload("res://src/world/manor/waltz_moment.gd")
const GlassScript := preload("res://src/world/manor/looking_glass.gd")
const Interactable := preload("res://src/world/manor/manor_interactable.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")

const SPAWNER_SCRIPT := "res://src/enemies/enemy_spawner.gd"
const ECHO_TRIAL_SCRIPT := "res://src/world/areas_ch2/echo_trial.gd"
const START_METHODS := ["start_fight", "begin_fight", "start", "activate"]
const STOP_METHODS := ["reset_fight", "stop_fight", "end_fight"]

# Colours (storybook, velvet, candlelit).
const GOLD := Color("d9b25a")
const CREAM := Color("f3e6d0")
const PLUM := Color("6e3a5a")
const WOOD_WARM := Color("7a4a33")
const WOOD_DARK := Color("4e2f24")
const LILAC := Color("b6aec6")
const ROSE := Color("e6b3bf")
const CRIMSON := Color("7a1f3a")
const NIGHT := Color("2a1830")
const STONE := Color("a39a8e")
const MOSS := Color("8e9a86")
const FLAME := Color("ffc562")
const MOON := Color("bcd0ff")

var placeholder := false             # the real manor (wave C) - see the integrator note in the report
var exits: Dictionary = {}           # front_door, balcony_stair, servants_up, servants_down
var bounds: Rect2 = Layout.BOUNDS
var floor_y := 0.0
var fight_active: bool = false       # Game.boss_active() reads this while the Count's encounter is on
var build_ms: float = 0.0
var builder: Builder = null
var safe_spots: Array = []           # [{center, radius}] (checkpoint circles)
var checkpoints: Dictionary = {}     # spawn id -> manor_checkpoint node
var puzzle: Node3D = null
var looking_glass: Node3D = null
var waltz: Node3D = null
var lantern: Node3D = null
var shortcut_gate: Node3D = null
var resident: Node3D = null
var gallery_door: Node3D = null
var balcony_door: Node3D = null
var tapestry: Node3D = null
var arena_candles: Array = []        # ward_candle nodes in ARENA.candle_order
var teach_candle: Node3D = null      # the arena candle Krystal lights before the Count appears
var ward_candles: Dictionary = {}    # id -> ward_candle
var curtains: Array = []             # Marker3D per curtain (group "mm_curtain")
var fixture: Node3D = null           # the Gallery's central chandelier (fixture_light inside)
var fixture_light: OmniLight3D = null
var cover_points: Array = []
var scraps: Dictionary = {}          # scrap id -> pickup node (only the ones still in the world)
var notes: Dictionary = {}           # note id -> interactable
var spawners: Array = []
var boss: Node = null
var boss_missing: bool = false
var pipkin_spot: Marker3D = null
var echo_entry: Node3D = null        # Velour's Echo Trial stone (only once echo_trial.gd offers it)
var encounter_starts: int = 0
var player_override: Node3D = null   # tests
var ambience_zone: String = ""       # zone whose ambience was last applied
var _first_bow_said := false
var _after_applied := false          # the after-the-Count state (balcony open, resident) is in place
var _fallback_told := false
var _teach_told := false
var _tick := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	area_id = Layout.AREA_ID
	_build_environment()
	builder = Builder.new(self)
	_build_cloakroom()
	_build_hall()
	_build_mirror_world()
	_build_powder()
	_build_ballroom()
	_build_nook()
	_build_gallery()
	_build_dressing()
	_build_stair()
	_build_balcony()
	_build_landing()
	builder.finish()
	_register_spawns()
	_add_zones()
	_build_nodes()
	_place_enemies()
	_place_boss()
	if velour_defeated():
		_apply_after_velour(false)
	if not Events.boss_defeated.is_connected(_on_boss_defeated):
		Events.boss_defeated.connect(_on_boss_defeated)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	if not Events.zone_entered.is_connected(_on_zone_entered):
		Events.zone_entered.connect(_on_zone_entered)
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if OS.is_debug_build() and not Debug.headless:
		print("Moonveil Manor built in %.0f ms (%d batched instances)" % [build_ms, int(builder.get("instances"))])


# =====================================================================================================
# Environment & lights
# =====================================================================================================

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("140c1a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8f6a6e")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)
	# The balcony's moonlight: the third (and last) shadow-casting light of the manor.
	var moon := SpotLight3D.new()
	moon.name = "MoonOverBalcony"
	moon.light_color = MOON
	moon.light_energy = 1.7
	moon.spot_range = 24.0
	moon.spot_angle = 42.0
	moon.shadow_enabled = true
	moon.distance_fade_enabled = true
	moon.distance_fade_begin = 40.0
	moon.distance_fade_length = 10.0
	moon.distance_fade_shadow = 30.0
	add_child(moon)
	moon.position = Vector3(3.0, 17.0, -84.0)
	moon.rotation = Vector3(deg_to_rad(-72.0), deg_to_rad(15.0), 0.0)


# =====================================================================================================
# Rooms (geometry + dressing, batched)
# =====================================================================================================

func _b() -> Builder:
	return builder


func _build_cloakroom() -> void:
	var b := _b()
	b.room_shell("cloakroom", {"floor": WOOD_WARM, "wall": PLUM, "wainscot": WOOD_DARK, "trim": GOLD, "ceil": WOOD_DARK})
	# Ceiling beams.
	for z in [-2.0, -5.0, -8.0]:
		b.vbox(Vector3(0, 3.45, float(z)), Vector3(10.4, 0.28, 0.32), WOOD_DARK.darkened(0.15))
	b.rug(Vector3(0, 0, -5.2), Vector2(3.4, 6.2), Color("7a2f52"), GOLD)
	# Coat pegs along the west wall with cloaks and hats (the guests never came back for them).
	b.vbox(Vector3(-4.93, 1.95, -5.0), Vector3(0.1, 0.12, 6.4), WOOD_DARK)
	var cloak_cols := [Color("3d2a5a"), Color("b0486e"), Color("2f5a5e"), Color("7d1e3c"), Color("5a4a2e")]
	for i in 5:
		var z := -2.4 - float(i) * 1.3
		b.vcyl(Vector3(-4.75, 1.98, z), 0.03, 0.2, GOLD, Basis(Vector3.FORWARD, PI * 0.5), {"shadows": false})
		b.vtaper(Vector3(-4.62, 1.2, z), 0.36, 0.16, 1.4, cloak_cols[i])
		b.vsphere(Vector3(-4.66, 1.95, z), Vector3(0.34, 0.2, 0.3), cloak_cols[i].darkened(0.1))
	for z in [-3.05, -5.65]:
		b.vcone(Vector3(-4.6, 2.35, float(z)), 0.18, 0.45, Color("2a1830"), Basis(Vector3.FORWARD, -0.2), {"shadows": false})
		b.vcyl(Vector3(-4.62, 2.14, float(z)), 0.32, 0.03, Color("2a1830"), Basis(Vector3.FORWARD, -0.2), {"shadows": false})
	# Umbrella stand and umbrellas.
	b.vcyl(Vector3(-4.3, 0.35, -9.2), 0.22, 0.7, Color("5a3a52"))
	for k in 3:
		b.vcyl(Vector3(-4.3 + (float(k) - 1.0) * 0.08, 0.95, -9.2), 0.035, 1.1, [Color("2a1830"), Color("7d1e3c"), Color("3d2a5a")][k], Basis(Vector3.FORWARD, (float(k) - 1.0) * 0.12), {"shadows": false})
	b.col_cyl(Vector3(-4.3, 0.5, -9.2), 0.25, 1.0, "wood")
	# Velvet bench (east wall) and a side table crowded with candles.
	b.solid(Vector3(4.35, 0.25, -3.3), Vector3(0.7, 0.5, 2.2), Color("7a2f52"), "wood")
	b.vbox(Vector3(4.75, 0.8, -3.3), Vector3(0.15, 0.7, 2.2), Color("7a2f52"))
	for dz in [-1.0, 1.0]:
		b.vcyl(Vector3(4.35, 0.52, -3.3 + float(dz)), 0.1, 0.06, GOLD, Basis.IDENTITY, {"shadows": false})
	b.solid(Vector3(4.35, 0.4, -9.0), Vector3(0.8, 0.8, 0.8), WOOD_DARK, "wood")
	for k in 5:
		b.candle(Vector3(4.15 + float(k % 3) * 0.2, 0.8, -9.2 + float(k) * 0.1), 0.14 + float(k % 2) * 0.1, 0.035)
	# Crescent windows flanking the front door; sconces flanking the hall door.
	for sx in [-3.2, 3.2]:
		b.crescent_window(Vector3(float(sx), 2.3, -0.02), Vector3(0, 0, -1), 0.55, MOON, GOLD, 0.9)
	for sx in [-2.1, 2.1]:
		b.sconce(Vector3(float(sx), 1.9, -9.98), Vector3(0, 0, 1))
	# East wall sconces: above the bench and above the candle table (the servants' door sits between them).
	for sz in Layout.CLOAK_EAST_SCONCES:
		b.sconce(Vector3(4.98, 2.0, float(sz)), Vector3(-1, 0, 0))
	b.potted_plant(Vector3(-2.0, 0, -9.4), Color("8a5a3c"), Color("5f8a4f"))
	b.potted_plant(Vector3(2.0, 0, -9.4), Color("8a5a3c"), Color("5f8a4f"))
	b.lamp(Vector3(0, 3.0, -2.8), Color("ffc27a"), 1.1, 7.0)
	b.lamp(Vector3(0, 3.0, -7.6), Color("ffc27a"), 1.0, 7.0)


func _build_hall() -> void:
	var b := _b()
	b.room_shell("hall", {"floor": Color("7e5f4e"), "wall": LILAC, "wainscot": Color("6f6784"), "trim": Color("e6dcc0"), "ceil": Color("8a809e")})
	b.begin("hall")
	b.rug(Vector3(0, 0, -20.5), Vector2(1.9, 19.2), Color("35607a"), GOLD)
	# Rib arches across the vault (posts only on plain wall, between the looking-glasses).
	var pw := float(Layout.HALL_RIB_POST_W)
	for rz in Layout.HALL_RIBS:
		var z := float(rz)
		b.vbox(Vector3(0, 5.3, z), Vector3(7.2, 0.34, 0.34), Color("e6dcc0"), Basis.IDENTITY, {"shadows": false})
		for sx in [-1.0, 1.0]:
			b.vbox(Vector3(float(sx) * (3.5 - pw * 0.5), 2.8, z), Vector3(pw, 5.0, pw), Color("e6dcc0"), Basis.IDENTITY, {"shadows": false})
	# Looking-glasses in the west wall: gilt frames, silvered glass (solid to the touch).
	var glass := Mat.transparent(Color(0.8, 0.84, 0.98, 0.16), false)
	for o in Layout.ROOMS["hall"]["walls"]["w"]:
		var z0 := float(o[0])
		var z1 := float(o[1])
		var zc := (z0 + z1) * 0.5
		var top := float(o[2])
		var bot := float(o[3])
		b.col_box(Vector3(-3.75, (top + bot) * 0.5, zc), Vector3(0.5, top - bot, z1 - z0))
		b.batch(Builder.unit_box(), glass, Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.02, top - bot, z1 - z0)), Vector3(-3.52, (top + bot) * 0.5, zc)), Color.WHITE, false)
		for side in [-1.0, 1.0]:
			b.vbox(Vector3(-3.44, (top + bot) * 0.5, zc + float(side) * ((z1 - z0) * 0.5 + 0.07)), Vector3(0.14, top - bot + 0.1, 0.16), GOLD, Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(-3.44, bot - 0.05, zc), Vector3(0.18, 0.12, z1 - z0 + 0.3), GOLD, Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(-3.44, top + 0.12, zc), Vector3(0.16, 0.24, z1 - z0 + 0.3), GOLD, Basis.IDENTITY, {"shadows": false})
		b.vsphere(Vector3(-3.42, top + 0.42, zc), Vector3(0.12, 0.42, 0.42), GOLD, Basis.IDENTITY, {"shadows": false})
	# True candles in sconces on the east wall, crescent windows above.
	for c in Layout.HALL_TRUE_CANDLES:
		var cp: Vector3 = c
		b.sconce(Vector3(3.48, cp.y - 0.2, cp.z), Vector3(-1, 0, 0))
	for z in Layout.HALL_WINDOWS:
		b.crescent_window(Vector3(3.47, 4.2, float(z)), Vector3(-1, 0, 0), 0.62, MOON, GOLD, 1.0)
	# A console table of PAINTED glass flames (no light, no reflection).
	b.solid(Vector3(3.1, 0.45, -26.6), Vector3(0.7, 0.9, 1.4), Color("6f6784"), "wood")
	for c in Layout.HALL_FALSE_CANDLES:
		var fp: Vector3 = c
		b.vcyl(fp + Vector3(0, 0.1, 0), 0.04, 0.2, Color("d8cfe8"), Basis.IDENTITY, {"shadows": false})
		b.vsphere(fp + Vector3(0, 0.26, 0), Vector3(0.07, 0.12, 0.07), Color("c98fd8"), Basis.IDENTITY, {"shadows": false, "rim": 0.9})
	# The sideboard under the fourth glass with three little bat figures facing the mirror.
	b.solid(Layout.BAT_SIDEBOARD + Vector3(0, 0.42, 0), Vector3(0.55, 0.84, 1.8), Color("4a3a5e"), "wood")
	b.vbox(Layout.BAT_SIDEBOARD + Vector3(0, 0.86, 0), Vector3(0.6, 0.05, 1.9), GOLD, Basis.IDENTITY, {"shadows": false})
	for i in Layout.BAT_FIGURES.size():
		_bat_figure(b, Layout.BAT_FIGURES[i], -1.0, false)
	# A folding screen half-hiding the Powder Room door, and a velvet ribbon trailing behind it (clue).
	var sp: Vector3 = Layout.FOLDING_SCREEN
	for k in 3:
		var a := deg_to_rad(20.0 + float(k) * 35.0)
		b.solid(sp + Vector3(float(k) * 0.35 - 0.35, 0.95, float(k) * 0.28 - 0.3), Vector3(0.06, 1.9, 0.7), Color("e0c8d8"), "wood", Basis(Vector3.UP, a))
	for k in 7:
		var t := float(k) / 6.0
		var rp := Vector3(lerpf(0.6, 3.6, t), 0.012, lerpf(-17.6, -20.2, t) + sin(t * 5.0) * 0.25)
		b.vbox(rp, Vector3(0.12, 0.02, 0.5), Color("9b3b5a"), Basis(Vector3.UP, 0.6 + sin(t * 4.0) * 0.5), {"shadows": false})
	b.lamp(Vector3(0, 4.6, -14.5), Color("d8d0ff"), 0.7, 9.0)
	b.lamp(Vector3(0, 4.6, -25.5), Color("d8d0ff"), 0.7, 9.0)
	b.lamp(Vector3(2.6, 2.2, -20.0), FLAME, 0.6, 5.0)


## A little bat figure (the Looking-Glass Hall lesson). facing: -1 = faces -X (toward the mirror).
func _bat_figure(b: Builder, p: Vector3, facing: float, flat: bool) -> void:
	var body_c := Color("2e2240")
	var yaw := PI * 0.5 if facing < 0.0 else -PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	if flat:
		var dim := Color(0.09, 0.06, 0.12)
		b.vflat(Builder.unit_taper(0.4), Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.24, 0.26, 0.24)), p + Vector3(0, 0.13, 0)), dim)
		b.vflat(Builder.unit_sphere(10), Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.14, 0.13, 0.14)), p + Vector3(0, 0.3, 0)), dim)
		for s in [-1.0, 1.0]:
			b.vflat(Builder.unit_sphere(10), Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.05, 0.1, 0.05)), p + Vector3(0, 0.38, float(s) * 0.05)), dim)
		return
	b.vtaper(p + Vector3(0, 0.13, 0), 0.12, 0.05, 0.26, body_c, basis, {"shadows": false})
	b.vsphere(p + Vector3(0, 0.3, 0), Vector3(0.14, 0.13, 0.14), body_c, basis, {"shadows": false})
	for s in [-1.0, 1.0]:
		b.vcone(p + Vector3(0, 0.4, float(s) * 0.05), 0.03, 0.09, body_c, basis, {"shadows": false})
		b.vsphere(p + Vector3(0, 0.18, float(s) * 0.11), Vector3(0.05, 0.16, 0.1), body_c.lightened(0.1), basis, {"shadows": false})


## The mirror world behind the west wall: a dim, unshaded copy of the hall where only TRUE light shows.
func _build_mirror_world() -> void:
	var b := _b()
	b.begin("mirror_world")
	var mw: Dictionary = Layout.MIRROR_WORLD
	var x0 := float(mw["x0"])
	var x1 := float(mw["x1"])
	var z0 := float(mw["z0"])
	var z1 := float(mw["z1"])
	var box := Builder.unit_box()
	var dim_floor := Color(0.11, 0.08, 0.12)
	var dim_wall := Color(0.15, 0.13, 0.19)
	b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(x1 - x0, 0.2, z1 - z0)), Vector3((x0 + x1) * 0.5, -0.1, (z0 + z1) * 0.5)), dim_floor)
	b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(x1 - x0, 0.2, z1 - z0)), Vector3((x0 + x1) * 0.5, 5.6, (z0 + z1) * 0.5)), Color(0.06, 0.05, 0.08))
	b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.3, 5.6, z1 - z0)), Vector3(x0 + 0.15, 2.8, (z0 + z1) * 0.5)), dim_wall)
	for z in [z0 - 0.15, z1 + 0.15]:
		b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(x1 - x0, 5.6, 0.3)), Vector3((x0 + x1) * 0.5, 2.8, float(z))), dim_wall)
	# Reflected runner carpet, wainscot and rib arches (dim).
	var rx := 2.0 * Layout.MIRROR_X
	b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(1.9, 0.03, 19.2)), Vector3(rx, 0.015, -20.5)), Color(0.08, 0.14, 0.18))
	b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.08, 0.85, z1 - z0)), Vector3(x0 + 0.34, 0.43, (z0 + z1) * 0.5)), Color(0.1, 0.09, 0.14))
	for rz in Layout.HALL_RIBS:
		b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(x1 - x0, 0.3, 0.3)), Vector3((x0 + x1) * 0.5, 5.3, float(rz))), Color(0.18, 0.17, 0.2))
	# TRUE lights show: the east-wall candles and the moonlit crescent windows.
	for c in Layout.HALL_TRUE_CANDLES:
		var cp: Vector3 = GlassScript.mirrored(c)
		b.glow_sphere(cp + Vector3(0, 0.06, 0), Vector3(0.08, 0.15, 0.08), FLAME, 3.0)
		b.glow_sphere(cp + Vector3(0, 0.06, 0), Vector3(0.36, 0.36, 0.36), Color(0.5, 0.33, 0.14), 0.6)
	for z in Layout.HALL_WINDOWS:
		var wp: Vector3 = GlassScript.mirrored(Vector3(3.47, 4.2, float(z)))
		b.glow_disc(wp, 0.62, Color(0.45, 0.52, 0.75), 0.8, Basis(Vector3.FORWARD, PI * 0.5))
	# The three little bats, facing out of the glass: dark shapes (the collar glint is a node).
	for i in Layout.BAT_FIGURES.size():
		_bat_figure(b, GlassScript.mirrored(Layout.BAT_FIGURES[i]), 1.0, true)
	b.vflat(box, Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.55, 0.84, 1.8)), GlassScript.mirrored(Layout.BAT_SIDEBOARD) + Vector3(0, 0.42, 0)), Color(0.1, 0.08, 0.13))
	# Through the reflected Powder Room door: warm candle-light and a crimson glint (Count's Wardrobe clue).
	b.glow_box(Vector3(x0 + 0.33, 1.35, -20.2), Vector3(0.04, 2.6, 2.0), Color(0.55, 0.36, 0.2), 0.7)
	b.glow_sphere(Vector3(x0 + 0.45, 0.95, -19.6), Vector3(0.14, 0.1, 0.14), Color("ff5f8a"), 2.2)


func _build_powder() -> void:
	var b := _b()
	b.room_shell("powder", {"floor": Color("7e5f4e"), "wall": Color("e0a3b5"), "wainscot": Color("a85a78"), "trim": CREAM, "ceil": Color("d8a0b0")})
	# Vanity with a round mirror, candles and the first velvet scrap.
	b.solid(Vector3(8.55, 0.44, -19.4), Vector3(0.8, 0.88, 1.8), Color("f0d6e2"), "wood")
	b.vbox(Vector3(8.55, 0.9, -19.4), Vector3(0.86, 0.05, 1.86), GOLD, Basis.IDENTITY, {"shadows": false})
	b.vcyl(Vector3(8.95, 1.75, -19.4), 0.55, 0.06, GOLD, Basis(Vector3.FORWARD, PI * 0.5), {"shadows": false})
	b.glow_disc(Vector3(8.9, 1.75, -19.4), 0.48, Color(0.75, 0.72, 0.85), 0.35, Basis(Vector3.FORWARD, PI * 0.5))
	for dz in [-0.7, 0.7]:
		b.candle(Vector3(8.6, 0.92, -19.4 + float(dz)), 0.22, 0.04)
	b.vcyl(Vector3(7.4, 0.25, -21.4), 0.28, 0.5, Color("7a2f52"))
	b.col_cyl(Vector3(7.4, 0.25, -21.4), 0.3, 0.5, "wood")
	b.rug(Vector3(6.6, 0, -20.2), Vector2(2.6, 3.6), Color("f0c8d6"), Color("a85a78"))
	# The ribbon continues from the hall to the vanity.
	for k in 4:
		var t := float(k) / 3.0
		b.vbox(Vector3(lerpf(4.3, 7.6, t), 0.03, -20.2 + sin(t * 4.0) * 0.3), Vector3(0.12, 0.02, 0.5), Color("9b3b5a"), Basis(Vector3.UP, 1.2 + t), {"shadows": false})
	b.lamp(Vector3(7.8, 2.4, -19.8), Color("ffb89a"), 0.8, 4.5)


func _build_ballroom() -> void:
	var b := _b()
	b.room_shell("ballroom", {"floor": Color("8a5a44"), "wall": Color("ecd3cf"), "wainscot": Color("b0677f"), "trim": GOLD, "ceil": Color("f0dccf")})
	b.begin("ballroom")
	# Checkerboard dance floor (rose / cream).
	for ix in 13:
		for iz in 14:
			var c := ROSE if (ix + iz) % 2 == 0 else CREAM
			b.vbox(Vector3(-6.0 + float(ix), 0.012, -47.0 + float(iz)), Vector3(0.98, 0.024, 0.98), c, Basis.IDENTITY, {"shadows": false})
	b.vbox(Vector3(0, 0.01, -40.5), Vector3(13.6, 0.02, 14.6), GOLD, Basis.IDENTITY, {"shadows": false})
	# Coffered ceiling.
	for i in 4:
		b.vbox(Vector3(0, 7.8, -34.0 - float(i) * 4.6), Vector3(22.0, 0.4, 0.3), GOLD.darkened(0.1), Basis.IDENTITY, {"shadows": false})
	for sx in [-7.0, 0.0, 7.0]:
		b.vbox(Vector3(float(sx), 7.8, -41.0), Vector3(0.3, 0.4, 20.0), GOLD.darkened(0.1), Basis.IDENTITY, {"shadows": false})
	# Stage (north-west) with steps, a big curtain and the Musicians' Nook behind a side curtain.
	var st: Dictionary = Layout.STAGE
	var top := float(st["top"])
	b.solid(Vector3((float(st["x0"]) + float(st["x1"])) * 0.5, top * 0.5, (float(st["z0"]) + float(st["z1"])) * 0.5),
		Vector3(float(st["x1"]) - float(st["x0"]), top, float(st["z1"]) - float(st["z0"])), Color("6a3a2e"), "wood")
	b.vbox(Vector3((float(st["x0"]) + float(st["x1"])) * 0.5, top - 0.03, float(st["z1"]) - 0.06), Vector3(float(st["x1"]) - float(st["x0"]), 0.08, 0.14), GOLD, Basis.IDENTITY, {"shadows": false})
	var steps: Dictionary = st["steps"]
	var sx_mid := (float(steps["x0"]) + float(steps["x1"])) * 0.5
	b.stairs(Vector3(sx_mid, top, float(steps["z_top"])), Vector3(sx_mid, 0.0, float(steps["z_bottom"])), float(steps["x1"]) - float(steps["x0"]), 0.2, Color("7a4a38"), GOLD, "wood")
	b.curtain(Vector3(-8.75, 5.4, -50.95), Vector3(0, 0, 1), 4.2, 4.6, Color("8a1f45"), GOLD, 0.55)
	b.curtain(Vector3(-10.95, 3.6, -48.1), Vector3(1, 0, 0), 2.6, 2.9, Color("8a1f45"), GOLD, 0.95)
	# Rose petals up the steps to the side curtain (clue for the second scrap).
	for k in 14:
		var t := float(k) / 13.0
		var pp := Vector3(lerpf(-5.8, -10.6, t), 0.0, lerpf(-43.2, -48.2, t) + sin(t * 7.0) * 0.35)
		pp.y = Layout.floor_y("ballroom", pp.x, pp.z) + 0.02
		if pp.z < -44.6 and pp.z > -46.0:
			pp.y = lerpf(0.0, top, clampf((-44.6 - pp.z) / 1.4, 0.0, 1.0)) + 0.03
		b.vsphere(pp, Vector3(0.09, 0.02, 0.06), Color("e05a7a"), Basis(Vector3.UP, t * 5.0), {"shadows": false, "segments": 6})
	# Tall arched windows (west) with curtains; crescent windows high on the east wall.
	for z in [-34.5, -40.5]:
		b.arched_window(Vector3(-10.95, 1.0, float(z)), Vector3(1, 0, 0), 2.0, 4.6, MOON, GOLD, 0.8)
		b.curtain(Vector3(-10.95, 6.0, float(z)), Vector3(1, 0, 0), 2.8, 5.2, Color("b0486e"), GOLD, 0.8)
	for z in [-34.0, -48.5]:
		b.crescent_window(Vector3(10.97, 6.5, float(z)), Vector3(-1, 0, 0), 0.7, MOON, GOLD, 1.0)
	# Gold pilasters and candle sconces around the room.
	for z in [-32.5, -37.0, -44.0, -49.5]:
		b.pilaster(Vector3(10.98, 0, float(z)), Vector3(-1, 0, 0), 7.6, CREAM, GOLD)
	for x in [-8.0, -4.0, 4.0, 8.0]:
		b.pilaster(Vector3(float(x), 0, -30.98), Vector3(0, 0, -1), 7.6, CREAM, GOLD)
		b.sconce(Vector3(float(x) + 1.0, 2.4, -31.0), Vector3(0, 0, -1))
	for z in [-37.3, -43.5]:
		b.sconce(Vector3(-11.0, 2.4, float(z)), Vector3(1, 0, 0))
	# The chandelier (shadow caster 1 of 3) and soft rose fill.
	b.chandelier(Vector3(0, 6.3, -41.0), 1.5, GOLD, 8.0, 2)
	var chand := b.lamp(Vector3(0, 5.7, -41.0), Color("ffcf9a"), 2.3, 17.0, true)
	chand.name = "ChandelierLight"
	b.lamp(Vector3(-6.0, 4.0, -41.0), Color("ffb8c0"), 0.7, 9.0)
	b.lamp(Vector3(6.0, 4.0, -41.0), Color("ffb8c0"), 0.7, 9.0)
	# Musicians' chairs on the stage.
	for x in [-10.2, -7.4]:
		b.vbox(Vector3(float(x), top + 0.24, -47.4), Vector3(0.5, 0.06, 0.5), Color("7a2f52"), Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(float(x), top + 0.55, -47.63), Vector3(0.5, 0.6, 0.06), GOLD.darkened(0.2), Basis.IDENTITY, {"shadows": false})


func _build_nook() -> void:
	var b := _b()
	b.room_shell("nook", {"floor": Color("6a3a2e"), "wall": Color("2f5a5e"), "wainscot": Color("1f3a3e"), "trim": GOLD, "ceil": Color("24464a")})
	var y := float(Layout.ROOMS["nook"]["y"])
	# Music stands (the scrap rests on the far one), a little harp, a stool.
	for p in [Vector3(-15.2, y, -48.0), Vector3(-13.6, y, -49.6)]:
		var sp: Vector3 = p
		b.vcyl(sp + Vector3(0, 0.55, 0), 0.025, 1.1, GOLD, Basis.IDENTITY, {"shadows": false})
		b.vcyl(sp + Vector3(0, 0.02, 0), 0.22, 0.04, GOLD, Basis.IDENTITY, {"shadows": false})
		b.vbox(sp + Vector3(0, 1.1, 0), Vector3(0.5, 0.04, 0.34), GOLD, Basis(Vector3.RIGHT, -0.25), {"shadows": false})
		b.col_cyl(sp + Vector3(0, 0.55, 0), 0.2, 1.1, "wood")
	var hp := Vector3(-15.6, y, -46.4)
	b.vbox(hp + Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.4), GOLD.darkened(0.2))
	b.vbox(hp + Vector3(0, 0.9, 0.12), Vector3(0.1, 1.6, 0.1), GOLD, Basis(Vector3.RIGHT, 0.12))
	b.vring(hp + Vector3(0, 1.0, -0.05), 0.55, 0.4, GOLD, Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, 0.4))
	b.col_box(hp + Vector3(0, 0.8, 0), Vector3(0.6, 1.6, 0.5), "wood")
	b.vcyl(Vector3(-12.6, y + 0.25, -46.3), 0.22, 0.5, Color("8a1f45"))
	b.candle(Vector3(-16.2, y + 1.0, -49.9), 0.2, 0.04)
	b.vbox(Vector3(-16.2, y + 0.5, -49.9), Vector3(0.3, 1.0, 0.3), Color("24464a"))
	b.lamp(Vector3(-14.2, y + 2.2, -48.0), Color("ffc89a"), 0.8, 5.0)


func _build_gallery() -> void:
	var b := _b()
	b.room_shell("gallery", {"floor": Color("3a2638"), "wall": CRIMSON, "wainscot": NIGHT, "trim": GOLD, "ceil": Color("2e1a2c")})
	b.begin("gallery")
	var c: Vector3 = Layout.ARENA["center"]
	b.round_rug(c, 11.2, Color("5e1a33"), GOLD)
	b.vring(c + Vector3(0, 0.05, 0), 6.0, 0.4, GOLD.darkened(0.15))
	# Dome ring and the central fixture (shadow caster 2 of 3).
	b.vring(Vector3(c.x, 8.7, c.z), 6.5, 1.2, GOLD.darkened(0.2))
	fixture = Node3D.new()
	fixture.name = "GalleryFixture"
	fixture.add_to_group("mm_gallery_fixture")
	add_child(fixture)
	fixture.position = Layout.ARENA["fixture"]
	b.chandelier(Layout.ARENA["fixture"], 2.1, GOLD, 9.0, 3)
	fixture_light = OmniLight3D.new()
	fixture_light.name = "FixtureLight"
	fixture_light.light_color = Color("ffcf94")
	fixture_light.light_energy = 2.4
	fixture_light.omni_range = 18.0
	fixture_light.omni_attenuation = 1.1
	fixture_light.shadow_enabled = true
	fixture_light.shadow_bias = 0.06
	fixture_light.distance_fade_enabled = true
	fixture_light.distance_fade_begin = 34.0
	fixture_light.distance_fade_length = 10.0
	fixture_light.distance_fade_shadow = 24.0
	fixture_light.position = Vector3(0, -0.8, 0)
	fixture.add_child(fixture_light)
	# West windows with velvet curtains (Marker3D per curtain for the boss module).
	for i in (Layout.ARENA["curtains"] as Array).size():
		var cd: Array = Layout.ARENA["curtains"][i]
		var cp: Vector3 = cd[0]
		var inward := Vector3(1, 0, 0) if cp.x < 0.0 else Vector3(-1, 0, 0)
		if cp.x < 0.0:
			b.arched_window(Vector3(-12.97, 1.2, cp.z), inward, 2.2, 5.4, Color("b89cff"), GOLD, 0.7)
		else:
			b.portrait(Vector3(12.9, 3.6, cp.z), inward, Vector2(2.0, 2.6), GOLD, Color("3a1a30"), Color("1a0f1e"), "host")
		b.curtain(Vector3(cp.x, 7.2, cp.z), inward, 3.2, 6.6, Color("8a1f45"), GOLD, 0.75)
		var m := Marker3D.new()
		m.name = "Curtain%d" % i
		m.add_to_group("mm_curtain")
		m.set_meta("yaw_deg", float(cd[1]))
		add_child(m)
		m.position = Vector3(cp.x, 3.6, cp.z)
		curtains.append(m)
	# The Count's portrait pointing at the tapestry, and paper bats fluttering toward it (third scrap clue).
	b.portrait(Vector3(12.9, 3.4, -60.2), Vector3(-1, 0, 0), Vector2(1.6, 2.2), GOLD, Color("3a1a30"), Color("1a0f1e"), "host")
	b.vbox(Vector3(12.8, 2.6, -61.6), Vector3(0.08, 0.1, 0.9), Color("f6efe6"), Basis(Vector3.RIGHT, -0.35), {"shadows": false})
	for k in 6:
		var t := float(k) / 5.0
		var bp := Vector3(12.93, lerpf(3.2, 3.0, t) + sin(t * 6.0) * 0.25, lerpf(-61.4, -63.6, t))
		b.vsphere(bp, Vector3(0.03, 0.12, 0.26), Color("1a0f1e"), Basis(Vector3.RIGHT, sin(t * 5.0) * 0.4), {"shadows": false, "segments": 6})
	# Crescent window over the balcony doors, portraits along the south wall.
	b.crescent_window(Vector3(0, 6.2, -77.48), Vector3(0, 0, 1), 1.2, Color("b89cff"), GOLD, 1.0)
	for x in [-8.0, 8.0]:
		b.portrait(Vector3(float(x), 3.6, -51.52), Vector3(0, 0, -1), Vector2(1.8, 2.2), GOLD, Color("3a1a30"), Color("7d1e3c"), "landscape")
	# Cover: two tall pillars and two statues on plinths (break the Count's line of sight).
	var cover: Array = Layout.ARENA["cover"]
	for i in cover.size():
		var cp: Vector3 = cover[i]
		cover_points.append(cp)
		if i < 2:
			b.column(cp, 0.55, 8.9, Color("b9aab8"), GOLD)
		else:
			b.solid(cp + Vector3(0, 0.7, 0), Vector3(1.3, 1.4, 1.3), Color("b9aab8"), "stone")
			b.vtaper(cp + Vector3(0, 2.0, 0), 0.5, 0.3, 1.2, Color("e6dcc0"))
			b.vsphere(cp + Vector3(0, 2.85, 0), Vector3(0.5, 0.55, 0.5), Color("e6dcc0"))
			b.col_cyl(cp + Vector3(0, 2.1, 0), 0.5, 1.6, "stone")
	# A writing desk in the north-west corner (the Count's diary).
	var dp: Vector3 = Layout.COUNT_DIARY
	b.solid(dp + Vector3(0, 0.42, 0), Vector3(1.5, 0.84, 0.8), Color("4a2a3a"), "wood")
	b.vbox(dp + Vector3(0.2, 0.9, 0), Vector3(0.4, 0.06, 0.3), CREAM, Basis(Vector3.UP, 0.3), {"shadows": false})
	b.candle(dp + Vector3(-0.5, 0.86, -0.2), 0.22, 0.04)
	b.lamp(Vector3(-8.0, 5.0, -64.5), Color("ff8fa8"), 0.8, 11.0)
	b.lamp(Vector3(8.0, 5.0, -64.5), Color("b89cff"), 0.8, 11.0)


func _build_dressing() -> void:
	var b := _b()
	b.room_shell("dressing", {"floor": Color("5a3a2e"), "wall": Color("5e2d56"), "wainscot": NIGHT, "trim": GOLD, "ceil": Color("3e1d38")})
	# A towering wardrobe, a hat stand, a tall mirror and the chair where the third scrap was forgotten.
	b.solid(Vector3(19.0, 1.3, -64.5), Vector3(0.9, 2.6, 2.2), Color("4a2a3a"), "wood")
	for dz in [-0.5, 0.5]:
		b.vbox(Vector3(18.53, 1.3, -64.5 + float(dz)), Vector3(0.04, 2.2, 0.9), Color("6a3a52"), Basis.IDENTITY, {"shadows": false})
		b.vsphere(Vector3(18.5, 1.3, -64.5 + float(dz) * 0.2), Vector3(0.06, 0.06, 0.06), GOLD, Basis.IDENTITY, {"shadows": false})
	b.vcone(Vector3(19.0, 2.85, -64.5), 0.8, 0.5, GOLD.darkened(0.2), Basis.IDENTITY, {"shadows": false})
	b.vcyl(Vector3(14.3, 0.9, -66.9), 0.04, 1.8, GOLD)
	b.vcone(Vector3(14.3, 1.95, -66.9), 0.2, 0.4, Color("2a1830"), Basis.IDENTITY, {"shadows": false})
	b.col_cyl(Vector3(14.3, 0.9, -66.9), 0.15, 1.8, "wood")
	b.vbox(Vector3(16.2, 1.3, -61.55), Vector3(1.0, 2.2, 0.08), GOLD)
	b.glow_box(Vector3(16.2, 1.3, -61.6), Vector3(0.84, 2.0, 0.02), Color(0.72, 0.7, 0.85), 0.3)
	b.solid(Vector3(18.0, 0.3, -66.2), Vector3(0.7, 0.6, 0.7), Color("7a2f52"), "wood")
	b.vbox(Vector3(18.3, 0.9, -66.2), Vector3(0.1, 0.8, 0.7), Color("7a2f52"))
	b.candle(Vector3(15.0, 1.0, -67.1), 0.22, 0.04)
	b.vbox(Vector3(15.0, 0.5, -67.1), Vector3(0.36, 1.0, 0.36), NIGHT)
	b.col_box(Vector3(15.0, 0.5, -67.1), Vector3(0.36, 1.0, 0.36), "wood")
	b.lamp(Vector3(16.5, 2.6, -64.5), Color("ffb0c8"), 0.8, 5.5)


func _build_stair() -> void:
	var b := _b()
	b.room_shell("stair", {"floor": STONE, "wall": Color("6a5a6e"), "wainscot": Color("4a3a4e"), "trim": GOLD, "ceil": Color("4a3a4e")})
	var r: Dictionary = Layout.ROOMS["stair"]
	var a: Vector3 = r["ramp"]["from"]
	var e: Vector3 = r["ramp"]["to"]
	b.stairs(e, a, 4.0, 0.2, STONE, Color("d6c8b8"), "stone")
	b.floor_rect(-2.0, 2.0, -83.0, e.z, e.y, STONE, "stone")
	for sx in [-1.8, 1.8]:
		b.vbox(Vector3(float(sx), 1.9, -80.2), Vector3(0.06, 0.06, 5.2), GOLD, Basis(Vector3.RIGHT, -0.36), {"shadows": false})
	b.sconce(Vector3(-1.98, 2.6, -80.5), Vector3(1, 0, 0))
	b.lamp(Vector3(0, 3.6, -80.5), FLAME, 0.8, 6.0)


func _build_balcony() -> void:
	var b := _b()
	b.room_shell("balcony", {"floor": MOSS, "wall": Color("5a4a5e"), "wainscot": Color("4a3a4e"), "trim": Color("d6c8b8"), "ceil": Color("4a3a4e")})
	b.begin("balcony")
	var y := float(Layout.ROOMS["balcony"]["y"])
	# Paving variation.
	for ix in 8:
		for iz in 6:
			if (ix * 7 + iz * 3) % 4 == 0:
				b.vbox(Vector3(-7.0 + float(ix) * 2.0, y + 0.01, -95.5 + float(iz) * 2.0), Vector3(1.9, 0.02, 1.9), STONE, Basis.IDENTITY, {"shadows": false})
	# Glass canopy: iron ribs from the house wall out over the south half (above head height). The middle
	# rib hangs from the cross beam, so the walk from the glass doors to the lantern stays open.
	for i in 5:
		var x := -7.2 + float(i) * 3.6
		b.vbox(Vector3(x, y + 4.9, -86.75), Vector3(0.1, 0.1, 6.7), Color("35283a"), Basis(Vector3.RIGHT, -0.28), {"shadows": false})
		if i == 2:
			continue
		b.vcyl(Vector3(x, y + 1.97, -90.0), 0.07, 3.94, Color("35283a"))
		b.col_cyl(Vector3(x, y + 1.97, -90.0), 0.1, 3.94, "stone")
	b.vbox(Vector3(0, y + 3.94, -90.0), Vector3(14.6, 0.1, 0.1), Color("35283a"), Basis.IDENTITY, {"shadows": false})
	b.batch(Builder.unit_box(), Mat.transparent(Color(0.8, 0.9, 1.0, 0.12), true), Transform3D(Basis(Vector3.RIGHT, -0.28).scaled_local(Vector3(15.0, 0.02, 6.4)), Vector3(0, y + 4.95, -86.6)), Color.WHITE, false)
	# Urns, ferns and pumpkins along the balustrade.
	for p in [Vector3(-8.5, y, -96.5), Vector3(8.5, y, -96.5), Vector3(-8.5, y, -84.3)]:
		b.potted_plant(p, Color("b9aab8"), Color("5f8a4f"), 1.3)
	for p in [Vector3(-6.0, y, -96.3), Vector3(-5.3, y, -96.5), Vector3(6.2, y, -96.4)]:
		b.pumpkin(p, 0.3)
	# The night beyond: soft hills, a few trees, the moon and stars (no collision, far away).
	var sky_y := y - 8.0
	for k in 9:
		var a := -0.9 + float(k) * 0.22
		var d := 48.0 + float(k % 3) * 9.0
		var hp := Vector3(sin(a) * d, sky_y, -90.0 - cos(a) * d)
		b.vsphere(hp, Vector3(22.0, 9.0 + float(k % 2) * 4.0, 16.0), Color("241a36").lightened(float(k % 3) * 0.05), Basis.IDENTITY, {"shadows": false})
	for k in 14:
		var a2 := -1.1 + float(k) * 0.17
		var d2 := 30.0 + float((k * 5) % 7) * 2.0
		var tp := Vector3(sin(a2) * d2, sky_y + 5.0, -90.0 - cos(a2) * d2)
		b.vcone(tp + Vector3(0, 3.0, 0), 2.2, 6.0, Color("2e2040"), Basis.IDENTITY, {"shadows": false, "segments": 8})
		b.vsphere(tp + Vector3(0, 5.2, 0), Vector3(2.4, 2.0, 2.4), Color("c8703a").darkened(0.45), Basis.IDENTITY, {"shadows": false, "segments": 8})
	b.glow_sphere(Vector3(-18.0, 34.0, -150.0), Vector3(9.0, 9.0, 9.0), Color("f2ecd8"), 1.6)
	b.glow_sphere(Vector3(-15.5, 35.5, -146.0), Vector3(8.2, 8.2, 8.2), Color("140c1a"), 0.0)
	for k in 40:
		var sa := float(k) * 2.39
		var sp := Vector3(cos(sa) * (40.0 + float(k % 7) * 9.0), 22.0 + float((k * 13) % 17) * 2.2, -120.0 - sin(sa) * 30.0 - float(k % 5) * 8.0)
		b.glow_sphere(sp, Vector3(0.25, 0.25, 0.25), Color("f4f0ff"), 2.0)
	# House wall above the doors: a crescent window and a candle each side.
	b.crescent_window(Vector3(0, y + 4.6, -83.52), Vector3(0, 0, -1), 0.8, Color("ffd9a0"), GOLD, 1.2)
	for sx in [-3.2, 3.2]:
		b.sconce(Vector3(float(sx), y + 2.2, -83.52), Vector3(0, 0, -1))
	# A ribbon tangled round the north balustrade (the Pipkin rescue spot, later wave): loops over the cap and
	# two tails hanging down the inner face.
	var pk: Vector3 = Layout.PIPKIN_SPOT
	for k in 5:
		b.vbox(pk + Vector3(float(k) * 0.12 - 0.24, 0.03 + sin(float(k)) * 0.015, 0.0), Vector3(0.1, 0.035, 0.74), Color("e8862f"), Basis(Vector3.UP, (float(k) - 2.0) * 0.18), {"shadows": false})
	for t in [[-0.14, 0.34, 0.2], [0.1, 0.46, -0.25]]:
		b.vbox(pk + Vector3(float(t[0]), -float(t[1]) * 0.5, 0.37), Vector3(0.07, float(t[1]), 0.025), Color("e8862f"), Basis(Vector3.FORWARD, float(t[2])), {"shadows": false})
	b.lamp(Vector3(-4.0, y + 2.4, -86.0), FLAME, 0.6, 6.0)


func _build_landing() -> void:
	var b := _b()
	b.room_shell("landing", {"floor": MOSS, "wall": Color("5a4a5e"), "wainscot": Color("4a3a4e"), "trim": Color("d6c8b8")})
	var y := float(Layout.ROOMS["landing"]["y"])
	b.potted_plant(Vector3(13.0, y, -87.0), Color("b9aab8"), Color("5f8a4f"), 1.0)
	b.sconce(Vector3(12.8, y + 2.0, -91.48), Vector3(0, 0, 1))


# =====================================================================================================
# Spawns, zones, queries
# =====================================================================================================

func _register_spawns() -> void:
	var holder := Node3D.new()
	holder.name = "SpawnPoints"
	add_child(holder)
	for id in Layout.SPAWNS:
		var xf := Layout.spawn_xform(String(id))
		xf.origin.y += 0.08
		register_spawn(String(id), xf)
		var m := Marker3D.new()
		m.name = "Spawn_" + String(id)
		holder.add_child(m)
		m.transform = xf


func _add_zones() -> void:
	var main := {"mm_cloakroom": "cloakroom", "mm_hall": "hall", "mm_ballroom": "ballroom", "mm_gallery": "gallery", "mm_balcony": "balcony"}
	for zid in Layout.ZONE_ORDER:
		var rid := String(main[zid])
		var r: Dictionary = Layout.ROOMS[rid]
		var rect := Layout.room_rect(rid)
		var c := rect.get_center()
		add_zone(String(zid), Vector3(c.x, float(r["y"]), c.y), rect.size.length() * 0.5, bool(r["safe"]))


func room_at(pos: Vector3) -> String:
	return Layout.room_at(pos)


## Zone of the room containing pos (side rooms belong to their parent space), else the nearest room's.
func get_zone_at(pos: Vector3) -> String:
	var rid := Layout.room_at(pos)
	if rid != "":
		return Layout.zone_of(rid)
	var best := ""
	var best_d := INF
	for id in Layout.ROOM_ORDER:
		var d := Layout.room_rect(String(id)).get_center().distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best = String(id)
	return Layout.zone_of(best)


func is_safe_zone(pos: Vector3) -> bool:
	var rid := Layout.room_at(pos)
	if rid != "" and bool(Layout.ROOMS[rid].get("safe", false)):
		return true
	for s in safe_spots:
		var c: Vector3 = s["center"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	return false


func height_at(x: float, z: float) -> float:
	var rid := Layout.room_at(Vector3(x, 0.0, z))
	if rid == "":
		return floor_y
	return Layout.floor_y(rid, x, z)


func surface_at(pos: Vector3) -> String:
	var rid := Layout.room_at(pos)
	if rid == "":
		return "wood"
	return String(Layout.ROOMS[rid].get("surface", "wood"))


func is_inside_bounds(pos: Vector3, margin: float = 0.0) -> bool:
	return bounds.grow(-margin).has_point(Vector2(pos.x, pos.z))


func validate_position(pos: Vector3) -> Variant:
	if not is_inside_bounds(pos, 0.5):
		return null
	return super.validate_position(pos)


func on_player_spawned(player: Node3D) -> void:
	# Safety net: anyone standing inside has certainly found the manor's lamp.
	if not bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)):
		GameState.set_flag(Layout.FLAG_FOUND_LAMP, true)
		GameState.request_quest_eval()
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		apply_zone_ambience(get_zone_at(player.global_position))
	else:
		apply_zone_ambience("mm_cloakroom")


func _on_zone_entered(zone: String) -> void:
	if Game.area != null and is_instance_valid(Game.area) and Game.area != self:
		return
	if Layout.AMBIENCE.has(zone):
		apply_zone_ambience(zone)


## The house is quiet; the open balcony hears the night (Layout.AMBIENCE). Existing loops only.
func apply_zone_ambience(zone: String) -> void:
	if not Layout.AMBIENCE.has(zone):
		return
	ambience_zone = zone
	var amb := String(Layout.AMBIENCE[zone])
	if not Audio.has_method("play_ambience"):
		return
	if amb == "" or not Audio.has_sound(amb):
		Audio.play_ambience("", 3.0)
	else:
		Audio.play_ambience(amb, 3.0)


# =====================================================================================================
# Interactive nodes
# =====================================================================================================

func _node(script: Script, params: Dictionary, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var n: Node3D = script.new()
	if n.has_method("setup"):
		n.setup(params)
	add_child(n)
	n.position = pos
	n.rotation.y = deg_to_rad(yaw_deg)
	return n


func _build_nodes() -> void:
	# Exits.
	exits["front_door"] = _node(DoorScript, {"text": "Step back outside", "target_area": Layout.REACH_ID, "target_spawn": "manor_door",
		"style": "inner"}, Layout.FRONT_DOOR["pos"], float(Layout.FRONT_DOOR["yaw_deg"]))
	exits["front_door"].name = "Exit_front_door"
	exits["servants_up"] = _node(DoorScript, {"text": "Take the servants' stair up to the balcony", "target_area": Layout.AREA_ID,
		"target_spawn": "manor_balcony", "style": "servants", "requires_flag": Layout.FLAG_SHORTCUT,
		"locked_text": "Bolted from the other side."}, Layout.SERVANTS_DOOR_CLOAK["pos"], float(Layout.SERVANTS_DOOR_CLOAK["yaw_deg"]))
	exits["servants_up"].name = "Exit_servants_up"
	exits["servants_down"] = _node(DoorScript, {"text": "Take the servants' stair down to the Cloakroom", "target_area": Layout.AREA_ID,
		"target_spawn": "manor_entry", "style": "servants", "requires_flag": Layout.FLAG_SHORTCUT,
		"locked_text": "Bolted."}, Layout.SERVANTS_DOOR_LANDING["pos"], float(Layout.SERVANTS_DOOR_LANDING["yaw_deg"]))
	exits["servants_down"].name = "Exit_servants_down"
	exits["balcony_stair"] = _node(DoorScript, {"text": "Take the garden stair down to the grounds", "target_area": Layout.REACH_ID,
		"target_spawn": "manor_door", "style": "stair", "requires_flag": Layout.FLAG_SHORTCUT,
		"locked_text": "The gate is bolted."}, Layout.GARDEN_STAIR["pos"], float(Layout.GARDEN_STAIR["yaw_deg"]))
	exits["balcony_stair"].name = "Exit_balcony_stair"
	# Checkpoints (rest candles) + their safe circles.
	for sid in Layout.CHECKPOINTS:
		var cp: Dictionary = Layout.CHECKPOINTS[sid]
		checkpoints[String(sid)] = _node(CheckpointScript, {"area": area_id, "spawn": String(cp["spawn"])}, cp["pos"])
		safe_spots.append({"center": cp["pos"], "radius": float(cp["safe_r"])})
	# Looking-Glass Hall, Ballroom puzzle, the Empty Waltz.
	looking_glass = _node(GlassScript, {}, Vector3.ZERO)
	puzzle = _node(PuzzleScript, {"layout": Layout.PUZZLE}, Vector3.ZERO)
	puzzle.connect("solved_now", _on_puzzle_solved)
	waltz = _node(WaltzScript, {}, Vector3.ZERO)
	ward_candles["hearth"] = puzzle.get("source_candle")
	ward_candles["practice"] = looking_glass.get("practice_candle")
	ward_candles["rail"] = waltz.get("rail_candle")
	# Sealed ways: Gallery doors (puzzle), Balcony glass doors (the Count), Dressing-room tapestry (fight).
	var gd: Dictionary = Layout.GALLERY_DOOR
	gallery_door = _node(SealedDoor, {"id": "gallery", "style": "gallery", "width": float(gd["width"]), "height": float(gd["height"]),
		"flag": String(gd["flag"]), "closed_text": "A crescent lock holds the doors. Guide the ward-light to it."}, gd["pos"])
	var bd: Dictionary = Layout.BALCONY_DOOR
	balcony_door = _node(SealedDoor, {"id": "balcony", "style": "glass", "width": float(bd["width"]), "height": float(bd["height"]),
		"flag": String(bd["flag"]), "closed_text": "A violet enchantment holds the glass doors shut."}, bd["pos"])
	var tp: Dictionary = Layout.ARENA["tapestry"]
	tapestry = _node(SealedDoor, {"id": "tapestry", "style": "tapestry", "width": float(tp["width"]), "height": 2.8, "open": true,
		"closed_text": "The tapestry won't budge while the Count holds court."}, tp["pos"], -90.0)
	# Arena ward candles. With the Count present two burn and the teaching candle waits dark (MP §13.1);
	# without his script all three wait (the fallback); after his defeat all three burn calmly.
	var defeated := velour_defeated()
	var boss_known := Factory.can_spawn(Layout.BOSS_ID)
	var teach_id := String(Layout.ARENA["teach_candle"])
	for cid in Layout.ARENA["candle_order"]:
		var start_lit := defeated or (boss_known and String(cid) != teach_id)
		var wc: Node3D = _node(WardCandle, {"id": String(cid), "kind": "ward", "lit": start_lit, "pool_radius": 3.2, "height": 1.55,
			"prompt": "Light the ward candle"}, Layout.ARENA["candles"][cid])
		wc.name = "WardCandle_" + String(cid)
		wc.connect("lit", _on_arena_candle_lit)
		arena_candles.append(wc)
		ward_candles[String(cid)] = wc
		if String(cid) == teach_id:
			teach_candle = wc
	# The Count's Wardrobe.
	for s in Layout.SCRAPS:
		if bool(GameState.get_flag(String(s["flag"]))):
			continue
		var sc: Node3D = _node(ScrapScript, {"id": String(s["id"]), "flag": String(s["flag"]), "item": Layout.SCRAP_ITEM}, s["pos"], 20.0)
		scraps[String(s["id"])] = sc
	# Balcony: lantern, shortcut gate, plaque, Pipkin marker.
	lantern = _node(LanternScript, {"lit_flag": Layout.FLAG_LAMP_LIT, "ready_flag": Layout.FLAG_VELOUR_DEFEATED}, Layout.LANTERN)
	shortcut_gate = _node(GateScript, {"width": float(Layout.SHORTCUT_GATE["width"])}, Layout.SHORTCUT_GATE["pos"], -90.0)
	pipkin_spot = Marker3D.new()
	pipkin_spot.name = "PipkinSpot"
	pipkin_spot.add_to_group("pipkin_spot")
	pipkin_spot.set_meta("area", area_id)
	add_child(pipkin_spot)
	pipkin_spot.position = Layout.PIPKIN_SPOT
	# Readable notes.
	_note("guest_list", "lore_ch2_manor_guest_list", "Read the guest book", Layout.GUEST_BOOK, "lectern")
	_note("count_diary", "lore_ch2_manor_count_diary", "Read the open diary", Layout.COUNT_DIARY + Vector3(0.2, 0.0, 0.55), "none")
	_note("tailor_note", "lore_ch2_manor_tailor_note", "Read the tailoring note", Layout.TAILOR_NOTE, "stand")
	_note("lantern_plaque", "lore_ch2_manor_lantern_plaque", "Read the plaque", Layout.BALCONY_PLAQUE, "stand")
	_place_echo_trial()


func _note(id: String, lore_id: String, text: String, pos: Vector3, style: String) -> void:
	var n: Node3D = Interactable.new()
	n.setup({"id": id, "text": text, "radius": 0.7, "offset": Vector3(0, 1.0, 0), "handler": _read_lore.bind(lore_id)})
	n.name = "Note_" + id
	add_child(n)
	n.position = pos
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	var paper := Mat.toon(Color("f7ecd6"))
	match style:
		"lectern":
			var wood := Mat.toon(Color("4e2f24"))
			Kit.add(n, Kit.cylinder(0.12, 0.2, 1.0, wood, 8), Vector3(0, 0.5, 0))
			Kit.add(n, Kit.box(Vector3(0.6, 0.06, 0.45), wood), Vector3(0, 1.05, 0), Vector3(-25, 0, 0))
			Kit.add(n, Kit.box(Vector3(0.5, 0.04, 0.36), paper), Vector3(0, 1.1, 0.01), Vector3(-25, 0, 0))
			Kit.static_collider(n, _cyl(0.2, 1.0), Vector3(0, 0.5, 0), 1).name = "SolidBody"
		"stand":
			Kit.add(n, Kit.cylinder(0.04, 0.07, 1.0, gold, 8), Vector3(0, 0.5, 0))
			Kit.add(n, Kit.box(Vector3(0.36, 0.26, 0.03), paper), Vector3(0, 1.08, 0), Vector3(-30, 0, 0))
			Kit.static_collider(n, _cyl(0.08, 1.0), Vector3(0, 0.5, 0), 1).name = "SolidBody"
	notes[id] = n


static func _cyl(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


func _read_lore(lore_id: String) -> void:
	var l := LoreDB.get_lore(lore_id)
	GameState.discover_lore(lore_id)
	Events.say.emit(String(l.get("title", "")), String(l.get("text", "")), 11.0)


func _on_puzzle_solved() -> void:
	if gallery_door != null:
		gallery_door.call("set_open", true, true)
	Events.camera_shake.emit(0.08, 0.4)


# --- Echo Trial hook (spec §1: Velour's trial starts from the ballroom rest candles) ------------------------

## The echo trial script, only when it offers Layout.ECHO_TRIAL_ID (a later wave adds it); else null.
func _echo_trial_script() -> Script:
	if not ResourceLoader.exists(ECHO_TRIAL_SCRIPT):
		return null
	var s: Variant = load(ECHO_TRIAL_SCRIPT)
	if not (s is Script) or not (s as Script).can_instantiate():
		return null
	var info: Variant = (s as Script).call("trial_info", Layout.ECHO_TRIAL_ID)
	if not (info is Dictionary) or (info as Dictionary).is_empty():
		return null
	return s


func echo_trial_available() -> bool:
	return velour_defeated() and _echo_trial_script() != null


## Places the echo stone beside the ballroom rest candles once the Count is freed and the trial exists.
func _place_echo_trial() -> void:
	if echo_entry != null and is_instance_valid(echo_entry):
		return
	if not echo_trial_available():
		return
	var n: Node3D = Interactable.new()
	n.setup({"id": "echo_trial", "text": "Echo Trial", "radius": 0.8, "offset": Vector3(0, 0.9, 0),
		"text_func": Callable(self, "_echo_trial_prompt"), "handler": Callable(self, "_enter_echo_trial")})
	n.name = "EchoTrialEntry"
	add_child(n)
	n.position = Layout.ECHO_ENTRY
	var stone := Mat.outlined(Mat.toon(Color("6a6282"), {"rim": 0.35, "noise": 0.18}), 0.014)
	Kit.add(n, Kit.blob(0.38, stone, 17, 0.16, 1.9, 2), Vector3(0, 0.58, 0))
	var band := Kit.torus(0.39, 0.44, Mat.glow(Color("cbb8ff"), 1.2))
	Kit.add(n, band, Vector3(0, 0.7, 0), Vector3.ZERO, Vector3(1, 1.8, 1))
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.static_collider(n, _cyl(0.4, 1.3), Vector3(0, 0.65, 0), 1).name = "SolidBody"
	echo_entry = n


func _echo_trial_prompt() -> Dictionary:
	var s := _echo_trial_script()
	if s == null or not velour_defeated():
		return {}
	return {"text": String(s.call("entry_text", Layout.ECHO_TRIAL_ID)), "enabled": true}


## Explains that it is a memory, then travels; the ballroom rest candles become the return point.
func _enter_echo_trial() -> void:
	if fight_active or Game.mode != "playing":
		return
	var s := _echo_trial_script()
	if s == null:
		return
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("confirm"):
		var c: String = await Game.ui.confirm(String(s.call("entry_text", Layout.ECHO_TRIAL_ID)),
			"An echo of your evening with %s, remembered by the house. It is a memory, not undone history: the Count stays a (mostly) gracious host, and nothing on your journey changes. Leave by the pale door at any time, or fall, and you wake here by the candles." % ItemDB.enemy_display_name(Layout.BOSS_ID),
			[["enter", "Enter the echo", "AccentButton"], ["cancel", "Not now", ""]])
		if c != "enter" or not is_instance_valid(self) or Game.mode != "playing":
			return
	s.call("begin", Layout.ECHO_TRIAL_ID, area_id, "manor_ballroom")


# =====================================================================================================
# Enemies and the Count
# =====================================================================================================

func _place_enemies() -> void:
	for s in Layout.SPAWNERS:
		if not Factory.can_spawn(String(s["enemy"])):
			continue          # the enemy script arrives in a later wave (spec §10): nothing to spawn yet
		if not ResourceLoader.exists(SPAWNER_SCRIPT):
			continue
		var sp: Node3D = load(SPAWNER_SCRIPT).new()
		sp.setup({"enemy": String(s["enemy"]), "count": int(s["count"]), "radius": float(s["radius"]),
			"respawn_minutes": float(s["respawn_minutes"]), "spawner_id": String(s["id"])})
		sp.name = "Spawner_" + String(s["id"])
		add_child(sp)
		sp.position = s["pos"]
		spawners.append(sp)


func velour_defeated() -> bool:
	return bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED))


func boss_alive() -> bool:
	return boss != null and is_instance_valid(boss) and not velour_defeated()


func _place_boss() -> void:
	if velour_defeated():
		return
	if not Factory.can_spawn(Layout.BOSS_ID):
		boss_missing = true
		return
	var c: Vector3 = Layout.ARENA["center"]
	boss = Factory.spawn(Layout.BOSS_ID, self, Transform3D(Basis.IDENTITY, c), {
		"arena_center": c, "arena_radius": float(Layout.ARENA["radius"]), "candles": arena_candles.duplicate(),
		"teach_candle": teach_candle, "curtains": curtains.duplicate(), "fixture": fixture, "cover": cover_points.duplicate(),
		"helper_points": (Layout.ARENA["helper_points"] as Array).duplicate(), "entry": Vector3(0, 0, float(Layout.ARENA["entry_z"])),
		"area": self, "no_drops": true})
	if boss == null:
		_enter_fallback()
	else:
		boss.name = "CountVelour"


## No Count to fight - his script is missing, failed to spawn, or his node vanished without a defeat (a
## later-wave bug): the three ward candles wait dark and lighting all of them breaks the enchantment, so
## the Gallery (and the balcony behind it) can never lock.
func _enter_fallback() -> void:
	boss_missing = true
	boss = null
	fight_active = false
	for wc in arena_candles:
		wc.call("restore", false)


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.2:
		return
	_tick = 0.0
	if Game.mode == "loading" or Game.mode == "cutscene":
		return
	update_encounter()


## Starts / pauses the Gallery encounter from where Krystal stands (5 Hz; tests call it directly).
func update_encounter() -> void:
	if velour_defeated():
		# Committed by someone other than mark_velour_defeated (e.g. a boss that sets the flag itself through
		# enemy_base "defeat_flag" instead of emitting Events.boss_defeated): open the house all the same.
		if not _after_applied:
			fight_active = false
			boss_missing = false
			_apply_after_velour(true)
		return
	var p := _player()
	if p == null:
		return
	var pos := p.global_position
	var in_arena := Layout.room_at(pos) == "gallery" and pos.z < float(Layout.ARENA["entry_z"])
	if in_arena and not fight_active:
		_start_encounter()
	elif fight_active and Layout.room_at(pos) != "gallery" and Layout.room_at(pos) != "dressing":
		_pause_encounter()


## True when the teaching candle burns (MP §13.1: one candle is lit by Krystal before the Count appears).
func teach_candle_lit() -> bool:
	return teach_candle == null or not is_instance_valid(teach_candle) or bool(teach_candle.call("is_lit"))


func _start_encounter() -> void:
	if not boss_missing and not boss_alive():
		# The Count was spawned but his node is gone and nobody committed a defeat (e.g. his script freed
		# itself on a bad setup): reloading would repeat it, so fall back to the candles instead.
		_enter_fallback()
	if boss_missing:
		if not _fallback_told:
			_fallback_told = true
			Events.say.emit("", "The Gallery is hushed. Its three ward candles have gone cold. Light them, and the house might remember itself.", 7.0)
		return
	if not teach_candle_lit():
		if not _teach_told:
			_teach_told = true
			Events.caption.emit("[one ward candle has gone cold; the other two burn low and patient]")
			Events.hint.emit("mm_ward_candle", "A ward candle has gone out. Light it with {interact}: its warm pool is safe ground, whatever the evening brings.")
		return
	fight_active = true
	encounter_starts += 1
	if tapestry != null:
		tapestry.call("set_open", false, true)
	if not _first_bow_said:
		_first_bow_said = true
		Events.say.emit(Layout.VELOUR_NAME, Layout.VELOUR_FIRST_BOW, 5.5)
	for m in START_METHODS:
		if boss.has_method(m):
			boss.call(m)
			break


func _pause_encounter() -> void:
	fight_active = false
	if tapestry != null:
		tapestry.call("set_open", true, true)
	if boss_alive():
		for m in STOP_METHODS:
			if boss.has_method(m):
				boss.call(m)
				break
	# A fair restart: every ward candle burns again (she has already learned to light them).
	for wc in arena_candles:
		wc.call("restore", true)


func _on_player_died() -> void:
	if fight_active:
		_pause_encounter()


## With the Count: lighting the teaching candle while standing in the arena begins the encounter.
## Fallback when the boss script is missing: the three ward candles break the enchantment.
func _on_arena_candle_lit(c: Node3D) -> void:
	if velour_defeated():
		return
	if not boss_missing:
		if c == teach_candle and not fight_active:
			update_encounter()
		return
	for wc in arena_candles:
		if not bool(wc.call("is_lit")):
			return
	mark_velour_defeated("candles")


func _on_boss_defeated(boss_id: String) -> void:
	if boss_id != Layout.BOSS_ID:
		return
	if Game.area != null and is_instance_valid(Game.area) and Game.area != self:
		return
	mark_velour_defeated("boss")


## Commits the Count's defeat (flag FIRST), then opens the balcony, calms the gallery and shows the
## resident. Returns false if it was already done. source: "boss" | "candles" | "debug".
func mark_velour_defeated(source: String = "boss") -> bool:
	if velour_defeated():
		return false
	GameState.set_flag(Layout.FLAG_VELOUR_DEFEATED, true)
	fight_active = false
	boss_missing = false
	_apply_after_velour(true)
	if source != "boss":
		Events.notify.emit("The Count's enchantment is broken.", "success")
	GameState.request_quest_eval()
	return true


## Debug / test hook (never reachable in a release build): marks the Count's encounter as cleared.
func debug_mark_velour_defeated() -> bool:
	if not Debug.is_cheat_allowed():
		return false
	return mark_velour_defeated("debug")


func _apply_after_velour(live: bool) -> void:
	_after_applied = true
	if balcony_door != null:
		balcony_door.call("set_open", true, live)
	if tapestry != null:
		tapestry.call("set_open", true, live)
	for wc in arena_candles:
		wc.call("restore", true)
	if lantern != null:
		lantern.call("refresh")
	if resident == null or not is_instance_valid(resident):
		resident = _node(ResidentScript, {"greet": live}, Layout.ARENA["resident"], 20.0)
	_place_echo_trial()
	if live:
		Events.caption.emit("[the violet shimmer on the glass doors fades away]")
		Events.screen_flash.emit(Color(1.0, 0.8, 0.9, 0.15), 0.8)
