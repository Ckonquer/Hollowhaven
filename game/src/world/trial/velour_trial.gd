extends RefCounted
## ECHO TRIAL "The Last Waltz" - the arena builder of Count Velour's trial (data/trials.gd "velour"; MP §13.1, §15).
## A remembered copy of the Count's Gallery (data/manor_layout.gd ARENA, positions relative to its centre, so the
## memory is laid out exactly like the real room): the crimson 26 x 26 m hall, the three WARD CANDLES (the real
## src/world/manor/ward_candle.gd, all burning: the rule was taught on the night itself), the velvet curtains and
## arched windows, the central fixture, the cover (two pillars, two statues on plinths - they break his drain
## tether's line of sight) and the helper points. The south doors open onto a short corridor ending in the pale
## entry pad (safe) and the pale door. Built with the manor's own builder (batched MultiMeshes, per-room collision).
##
## The boss is the REAL src/enemies/count_velour.gd in mode "trial", with NO owning area: he wakes when Krystal walks
## into the Gallery (arena radius), stands down if she steps back onto the pad (> radius + his leave margin, which
## the pad is beyond), never reads or writes ch2_velour_defeated, never emits Events.boss_defeated, and after his
## defeat he relights every candle and says his MP §17 line himself. The candles persist nothing. Arachnophobia:
## nothing here is spider-like (bats, velvet, candles). Comfort: the only shake / flash comes from the boss (Events).
##   static func build(area: Node3D) -> Dictionary   (called by src/world/areas_ch2/echo_trial.gd _ready)
## Returns {pad, exit, exit_yaw, bounds, zone_center, zone_radius, plate, boss, candles, cover, curtains, fixture,
## helper_points, arena_center, arena_radius, entry}.
## Lead decision P58 (kept on purpose): the memory starts with all three candles lit and no teaching candle - a trial
## replays a fight she has already won (the candle rule was taught in the story), and lit candles keep phases B / C
## fair; after the win the Count's line comes first and the fade line follows 2.4 s later (data/trials.gd fade_delay).

const Layout := preload("res://data/manor_layout.gd")
const Builder := preload("res://src/world/manor/manor_builder.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Fx := preload("res://src/world/trial/trial_fx.gd")

const BOSS_ID := "count_velour"
const ROOM := "echo_gallery"
const HALF := 13.0                 # the Gallery is 26 x 26 m (data/manor_layout.gd ROOMS.gallery)
const HEIGHT := 9.0
const WALL_T := 0.5
const DOOR_HALF := 1.6             # the Gallery doors are 3.2 m wide (GALLERY_DOOR)
const DOOR_H := 3.6
const CORRIDOR_END := 25.0
const CORRIDOR_H := 4.0
const PAD_Z := 21.8
const EXIT_Z := CORRIDOR_END - 0.6

const GOLD := Color("d9b25a")
const CRIMSON := Color("7a1f3a")
const NIGHT := Color("2a1830")
const FLOOR := Color("3a2638")
const CEIL := Color("2e1a2c")
const STONE_PALE := Color("b9aab8")
const MARBLE := Color("e6dcc0")


## A point of the real Gallery, relative to the arena centre (the memory's origin).
static func rel(p: Vector3) -> Vector3:
	var c: Vector3 = Layout.ARENA["center"]
	return Vector3(p.x - c.x, p.y - c.y, p.z - c.z)


static func arena_radius() -> float:
	return float(Layout.ARENA["radius"])


## Where the fight is entered from (the doors side), relative.
static func entry_point() -> Vector3:
	var c: Vector3 = Layout.ARENA["center"]
	return Vector3(0.0, 0.0, float(Layout.ARENA["entry_z"]) - c.z)


static func build(area: Node3D) -> Dictionary:
	area.call("build_environment", {"bg": Color("140a14"), "ambient": Color("7a5a78"), "ambient_energy": 0.5,
		"lamps": [[Vector3(0, 3.2, PAD_Z), Color("ffe2a8"), 0.9, 7.0]]})
	var b := Builder.new(area)
	b.begin(ROOM)
	_shell(b)
	_decor(b, area)
	var cover := _cover(b)
	var fixture := _fixture(b, area)
	var curtains := _curtains(b, area)
	b.finish()
	var candles := _candles(area)
	Fx.motes(area, Vector3(0, 3.5, 0), Vector3(10.0, 3.0, 10.0))
	Fx.pad_ring(area, Vector3(0, 0, PAD_Z), 2.4)
	var helpers: Array = []
	for hp in Layout.ARENA["helper_points"]:
		helpers.append(rel(hp))
	var out := {"pad": Vector3(0, 0, PAD_Z), "exit": Vector3(0, 0, EXIT_Z), "exit_yaw": PI,
		"bounds": Rect2(-HALF - 0.5, -HALF - 0.5, (HALF + 0.5) * 2.0, CORRIDOR_END + HALF + 1.0),
		"zone_center": Vector3(0, 0, 5.0), "zone_radius": 26.0, "plate": Vector3(0, 3.1, PAD_Z - 1.4),
		"candles": candles, "cover": cover, "curtains": curtains, "fixture": fixture, "helper_points": helpers,
		"arena_center": Vector3.ZERO, "arena_radius": arena_radius(), "entry": entry_point(), "boss": null}
	out["boss"] = _spawn_boss(area, out)
	return out


## The real boss in trial mode (null when his script is missing: a quiet memory, the pale door still leads home).
static func _spawn_boss(area: Node3D, a: Dictionary) -> Node:
	if not Factory.can_spawn(BOSS_ID):
		return null
	var boss: Node = Factory.spawn(BOSS_ID, area, Transform3D(Basis.IDENTITY, Vector3.ZERO), {
		"arena_center": Vector3.ZERO, "arena_radius": arena_radius(), "candles": (a["candles"] as Array).duplicate(),
		"teach_candle": null, "curtains": (a["curtains"] as Array).duplicate(), "fixture": a["fixture"],
		"cover": (a["cover"] as Array).duplicate(), "helper_points": (a["helper_points"] as Array).duplicate(),
		"entry": a["entry"], "mode": "trial", "no_drops": true})
	if boss != null:
		boss.name = "EchoVelour"
	return boss


# --- Room ---------------------------------------------------------------------------------------------------

static func _shell(b: Builder) -> void:
	var h := HALF
	# Floor (the Gallery) + the corridor floor, ceiling.
	b.floor_rect(-h, h, -h, h, 0.0, FLOOR, "stone")
	b.floor_rect(-DOOR_HALF, DOOR_HALF, h, CORRIDOR_END, 0.0, FLOOR.lightened(0.05), "stone")
	b.ceiling_rect(-h, h, -h, h, HEIGHT, CEIL)
	# Walls outside the box: north, west, east whole; south with the doorway (and a lintel over it).
	var t := WALL_T
	b.solid(Vector3(0, HEIGHT * 0.5, -h - t * 0.5), Vector3(h * 2.0 + t * 2.0, HEIGHT, t), CRIMSON)
	b.solid(Vector3(-h - t * 0.5, HEIGHT * 0.5, 0), Vector3(t, HEIGHT, h * 2.0), CRIMSON)
	b.solid(Vector3(h + t * 0.5, HEIGHT * 0.5, 0), Vector3(t, HEIGHT, h * 2.0), CRIMSON)
	var side_w := h - DOOR_HALF + t
	for sx in [-1.0, 1.0]:
		b.solid(Vector3(float(sx) * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5, h + t * 0.5), Vector3(side_w, HEIGHT, t), CRIMSON)
	b.solid(Vector3(0, DOOR_H + (HEIGHT - DOOR_H) * 0.5, h + t * 0.5), Vector3(DOOR_HALF * 2.0, HEIGHT - DOOR_H, t), CRIMSON)
	# Wainscot + crown trim on the inner faces (visual).
	for side in [[Vector3(0, 0.45, -h + 0.02), Vector3(h * 2.0, 0.9, 0.04)], [Vector3(-h + 0.02, 0.45, 0), Vector3(0.04, 0.9, h * 2.0)],
			[Vector3(h - 0.02, 0.45, 0), Vector3(0.04, 0.9, h * 2.0)]]:
		b.vbox(side[0], side[1], NIGHT, Basis.IDENTITY, {"shadows": false})
		b.vbox((side[0] as Vector3) + Vector3(0, HEIGHT - 0.7, 0), Vector3((side[1] as Vector3).x, 0.18, (side[1] as Vector3).z), GOLD, Basis.IDENTITY, {"shadows": false})
	# The corridor: walls, a low ceiling, the end wall behind the pale door.
	var clen := CORRIDOR_END - h + t
	for sx in [-1.0, 1.0]:
		b.solid(Vector3(float(sx) * (DOOR_HALF + t * 0.5), CORRIDOR_H * 0.5, (h + CORRIDOR_END) * 0.5 + t * 0.5), Vector3(t, CORRIDOR_H, clen), NIGHT)
	b.solid(Vector3(0, CORRIDOR_H * 0.5, CORRIDOR_END + t * 0.5), Vector3(DOOR_HALF * 2.0 + t * 2.0, CORRIDOR_H, t), NIGHT)
	b.solid(Vector3(0, CORRIDOR_H + 0.25, (h + CORRIDOR_END) * 0.5 + t * 0.5), Vector3(DOOR_HALF * 2.0 + t * 2.0, 0.5, clen), CEIL)
	# The doors themselves stand open (gilt leaves folded back against the wall).
	for sx in [-1.0, 1.0]:
		b.vbox(Vector3(float(sx) * (DOOR_HALF + 0.2), DOOR_H * 0.5, h - 0.8), Vector3(0.08, DOOR_H, 1.5), Color("4e2f24"), Basis.IDENTITY, {"shadows": false})


static func _decor(b: Builder, _area: Node3D) -> void:
	# The round rug, the gilt ring, the dome ring (as in the Gallery).
	b.round_rug(Vector3.ZERO, 11.2, Color("5e1a33"), GOLD)
	b.vring(Vector3(0, 0.05, 0), 6.0, 0.4, GOLD.darkened(0.15))
	b.vring(Vector3(0, 8.7, 0), 6.5, 1.2, GOLD.darkened(0.2))
	# Portraits along the south wall and a crescent window over the (sealed) balcony doors.
	for x in [-8.0, 8.0]:
		b.portrait(Vector3(float(x), 3.6, HALF - 0.02), Vector3(0, 0, -1), Vector2(1.8, 2.2), GOLD, Color("3a1a30"), Color("7d1e3c"), "landscape")
	b.crescent_window(Vector3(0, 6.2, -HALF + 0.02), Vector3(0, 0, 1), 1.2, Color("b89cff"), GOLD, 1.0)
	b.vbox(Vector3(0, 1.8, -HALF + 0.05), Vector3(3.2, 3.6, 0.06), Color("b89cff").darkened(0.45), Basis.IDENTITY, {"shadows": false})
	# The tapestry on the east wall (closed in the memory: the fight holds the house).
	b.vbox(Vector3(HALF - 0.06, 1.6, rel(Layout.ARENA["tapestry"]["pos"]).z), Vector3(0.06, 3.0, 2.2), Color("5e2d56"), Basis.IDENTITY, {"shadows": false})
	# Sconces between the windows, pale lamps (the Gallery's pink / lilac light).
	b.lamp(Vector3(-8.0, 5.0, 0.0), Color("ff8fa8"), 0.8, 11.0)
	b.lamp(Vector3(8.0, 5.0, 0.0), Color("b89cff"), 0.8, 11.0)
	for z in [-10.0, 10.0]:
		b.sconce(Vector3(-HALF + 0.02, 2.4, float(z)), Vector3(1, 0, 0), GOLD)
		b.sconce(Vector3(HALF - 0.02, 2.4, float(z)), Vector3(-1, 0, 0), GOLD)
	# A corridor lantern-glow on the pad side.
	b.candle(Vector3(DOOR_HALF - 0.3, 1.1, PAD_Z - 2.5), 0.22, 0.04)
	b.vbox(Vector3(DOOR_HALF - 0.3, 0.55, PAD_Z - 2.5), Vector3(0.3, 1.1, 0.3), NIGHT)


## The four cover pieces of the Gallery: two tall pillars and two statues on plinths (all solid).
static func _cover(b: Builder) -> Array:
	var out: Array = []
	var cover: Array = Layout.ARENA["cover"]
	for i in cover.size():
		var cp := rel(cover[i])
		cp.y = 0.0
		out.append(cp)
		if i < 2:
			b.column(cp, 0.55, HEIGHT - 0.1, STONE_PALE, GOLD)
		else:
			b.solid(cp + Vector3(0, 0.7, 0), Vector3(1.3, 1.4, 1.3), STONE_PALE, "stone")
			b.vtaper(cp + Vector3(0, 2.0, 0), 0.5, 0.3, 1.2, MARBLE)
			b.vsphere(cp + Vector3(0, 2.85, 0), Vector3(0.5, 0.55, 0.5), MARBLE)
			b.col_cyl(cp + Vector3(0, 2.1, 0), 0.5, 1.6, "stone")
	return out


## The central fixture (a chandelier; the one shadowed light of the memory).
static func _fixture(b: Builder, area: Node3D) -> Node3D:
	var fp := rel(Layout.ARENA["fixture"])
	var fixture := Node3D.new()
	fixture.name = "EchoFixture"
	area.add_child(fixture)
	fixture.position = fp
	b.chandelier(fp, 2.1, GOLD, HEIGHT, 3)
	var l := OmniLight3D.new()
	l.name = "FixtureLight"
	l.light_color = Color("ffcf94")
	l.light_energy = 2.2
	l.omni_range = 18.0
	l.omni_attenuation = 1.1
	l.shadow_enabled = true
	l.shadow_bias = 0.06
	l.position = Vector3(0, -0.8, 0)
	fixture.add_child(l)
	return fixture


## Velvet curtains over the west windows and the east portraits (a Marker3D per curtain, as the boss expects).
static func _curtains(b: Builder, area: Node3D) -> Array:
	var out: Array = []
	var list: Array = Layout.ARENA["curtains"]
	for i in list.size():
		var cd: Array = list[i]
		var cp := rel(cd[0])
		var inward := Vector3(1, 0, 0) if cp.x < 0.0 else Vector3(-1, 0, 0)
		if cp.x < 0.0:
			b.arched_window(Vector3(-HALF + 0.03, 1.2, cp.z), inward, 2.2, 5.4, Color("b89cff"), GOLD, 0.7)
		else:
			b.portrait(Vector3(HALF - 0.1, 3.6, cp.z), inward, Vector2(2.0, 2.6), GOLD, Color("3a1a30"), Color("1a0f1e"), "host")
		b.curtain(Vector3(cp.x, 7.2, cp.z), inward, 3.2, 6.6, Color("8a1f45"), GOLD, 0.75)
		var m := Marker3D.new()
		m.name = "EchoCurtain%d" % i
		m.set_meta("yaw_deg", float(cd[1]))
		area.add_child(m)
		m.position = Vector3(cp.x, 3.6, cp.z)
		out.append(m)
	return out


## The three ward candles, burning (fresh nodes: no persist flag, no story listener).
static func _candles(area: Node3D) -> Array:
	var out: Array = []
	for cid in Layout.ARENA["candle_order"]:
		var wc: Node3D = WardCandle.new()
		wc.setup({"id": "echo_" + String(cid), "kind": "ward", "lit": true, "pool_radius": 3.2, "height": 1.55,
			"prompt": "Light the ward candle"})
		wc.name = "EchoCandle_" + String(cid)
		area.add_child(wc)
		var p := rel(Layout.ARENA["candles"][cid])
		wc.position = Vector3(p.x, 0.0, p.z)
		out.append(wc)
	return out
