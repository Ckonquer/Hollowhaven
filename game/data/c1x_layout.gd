extends RefCounted
## Chapter One optional additions to Hollowhaven Woods (module B7; MP 7, 12, 16; docs/CHAPTER_TWO_SPEC.md 7.1).
## Every position (metres, x east, z south, the Haven at the origin) and every persistent id the annex scripts
## in src/world/surface/c1x/ use. Nothing here touches legacy generation: the sites were chosen AROUND the
## legacy vegetation plan (Vegetation.plan) and are checked by tests/unit/test_c1x_sites.gd:
##   * on dry, walkable ground inside the boundary, off the dirt paths (path weight 0 under every footprint),
##   * more than 18 m from the Haven (existing saves may have structures near it), never on a legacy landmark
##     centre, spawn hint or stream crossing,
##   * no legacy vegetation node (resource or decor) within a footprint + 2 m,
##   * every id new and prefixed "c1x_"; enemy spawner ids "c1x_sp_<name>" (spec 2).
## Ids of harvestable nodes are persistent (GameState.depleted): never rename or reorder them.

const PREFIX := "c1x_"

## --- Rewards and flags (data/sources.gd REWARDS "content" bundles; data/optional_goals.gd table) ----------------
const REWARD_TAILOR := "rw_c1x_tailor_cache"      # sets c1x_tailor_cache (Loom + ribbon bow pattern unlock)
const REWARD_ELDER := "rw_c1x_elder"              # sets c1x_elder_defeated (sturdy planter + leaf cape unlock)
const REWARD_GARDENER := "rw_c1x_gardener"        # starter packet on the first harvest at the meadow patch
const FLAG_TAILOR_CACHE := "c1x_tailor_cache"
const FLAG_ELDER_DEFEATED := "c1x_elder_defeated"
const FLAG_BRAMBLEWATCH_FOUND := "c1x_bramblewatch_found"
const FLAG_FOUND_NEW_CROPS := "c1x_found_new_crops"

## --- The Tailor's Cache (opt_tailors_cache) ------------------------------------------------------------------
## A small ribbon-tied cache at the north roots of the Old Oak, 6.5 m from its trunk, away from both paths.
## Four ribbons on low, crooked branches lead to it from the Old Oak path (the environmental clue).
const TAILOR_CACHE := {"id": "c1x_cache_0", "pos": Vector2(-31.5, -26.0), "yaw_deg": 20.0, "radius": 0.8}
const TAILOR_RIBBONS := [
	{"id": "c1x_ribbon_0", "pos": Vector2(-21.5, -17.6), "yaw_deg": 200.0, "color": "rose"},
	{"id": "c1x_ribbon_1", "pos": Vector2(-25.6, -21.4), "yaw_deg": 150.0, "color": "cream"},
	{"id": "c1x_ribbon_2", "pos": Vector2(-27.4, -24.6), "yaw_deg": 120.0, "color": "rose"},
	{"id": "c1x_ribbon_3", "pos": Vector2(-29.6, -27.6), "yaw_deg": 80.0, "color": "lavender"},
]
const RIBBON_RADIUS := 0.35

## --- Renewable resin: sap stumps (data/sources.gd NODES "sap_stump") ----------------------------------------
## Five tappable stumps over the woods (never inside the Haven build area): west woods, Bramblewatch,
## north woods, south-west woods, east woods.
const SAP_KIND := "sap_stump"
const SAP_STUMPS := [
	{"id": "c1x_resin_0", "pos": Vector2(-46.0, -14.0), "yaw_deg": 35.0},
	{"id": "c1x_resin_1", "pos": Vector2(-86.0, -52.0), "yaw_deg": 160.0},
	{"id": "c1x_resin_2", "pos": Vector2(-27.5, -43.0), "yaw_deg": 250.0},
	{"id": "c1x_resin_3", "pos": Vector2(-36.0, 28.0), "yaw_deg": 300.0},
	{"id": "c1x_resin_4", "pos": Vector2(58.5, 24.0), "yaw_deg": 95.0},
]
const SAP_RADIUS := 0.8

## --- A Gardener's Afternoon: the Sunny Meadow wild patch (NODES "sunflax_patch" / "roseberry_bush") ----------
const SUNFLAX_KIND := "sunflax_patch"
const ROSEBERRY_KIND := "roseberry_bush"
const SUNFLAX := [
	{"id": "c1x_sunflax_0", "pos": Vector2(-17.4, 63.4), "yaw_deg": 10.0},
	{"id": "c1x_sunflax_1", "pos": Vector2(-15.8, 62.6), "yaw_deg": 80.0},
	{"id": "c1x_sunflax_2", "pos": Vector2(-14.5, 64.2), "yaw_deg": 150.0},
	{"id": "c1x_sunflax_3", "pos": Vector2(-16.3, 65.4), "yaw_deg": 220.0},
	{"id": "c1x_sunflax_4", "pos": Vector2(-17.9, 65.1), "yaw_deg": 300.0},
]
const ROSEBERRY := [
	{"id": "c1x_roseberry_0", "pos": Vector2(-3.3, 69.3), "yaw_deg": 20.0},
	{"id": "c1x_roseberry_1", "pos": Vector2(-0.8, 69.4), "yaw_deg": 140.0},
	{"id": "c1x_roseberry_2", "pos": Vector2(-2.0, 71.5), "yaw_deg": 260.0},
]
const PLANT_RADIUS := 0.6

## --- Bramblewatch (opt_bramblewatch): Thornthicket outskirts, west / north-west of thicket_bramblings ----------
## Two small zone circles with ONE new zone id (never containing a landmark centre); entering either sets
## c1x_bramblewatch_found. The Brambleback group waits north-west of the thicket, the Knotted Elder's arena lies
## west of it at the foot of the western hills, both more than 24 m from the legacy thicket_bramblings spawner.
const BRAMBLEWATCH_ZONE := "c1x_bramblewatch"
const BRAMBLEWATCH_ZONES := [[Vector2(-86.0, -34.0), 13.0], [Vector2(-75.0, -67.0), 10.0]]
const BRAMBLEBACK_SPAWNER := {"id": "c1x_sp_bramblebacks", "enemy": "brambleback", "pos": Vector2(-75.0, -67.0),
	"count": 3, "radius": 4.0, "respawn_minutes": 720.0, "wander_radius": 4.0}
## The Elder never respawns (its drops are one-time, data/sources.gd); its reward is paid once through the ledger.
const ELDER_SPAWNER := {"id": "c1x_sp_knotted_elder", "enemy": "knotted_elder", "pos": Vector2(-86.0, -34.0),
	"count": 1, "radius": 1.0, "respawn_minutes": -1.0, "wander_radius": 3.0}
## Open arena (no walls): temporary roots rise on some of these slots (tangential root walls around the
## arena). At most max_raised of them at once, at least min_open slots always stay open, a slot is never raised
## on Krystal or a companion, the natural gap between neighbouring slots is > 3 m, and every root can be cut.
const ELDER_ARENA := {"centre": Vector2(-86.0, -34.0), "radius": 10.0, "root_length": 3.8, "root_height": 1.5,
	"root_depth": 0.7, "root_hits": 2, "telegraph": 1.6, "duration": 6.0, "first_after": 8.0, "interval": 14.0,
	"max_raised": 5, "min_open": 3}
## Slots around the arena centre: angle (radians, 0 = east, PI/2 = south) and distance.
const ROOT_SLOTS := [
	{"angle": 0.0, "r": 9.5}, {"angle": 0.785, "r": 10.0}, {"angle": 1.571, "r": 10.0}, {"angle": 2.356, "r": 9.0},
	{"angle": 3.142, "r": 10.0}, {"angle": 3.927, "r": 10.0}, {"angle": 4.712, "r": 11.0}, {"angle": 5.378, "r": 10.0},
]
## "Something big and knotted guards a sticky old tree": an old resin-dripping tree at the arena's western edge.
const STICKY_TREE := {"id": "c1x_sticky_tree_0", "pos": Vector2(-97.0, -26.5), "yaw_deg": 40.0, "radius": 1.4}
## Old thorn-wrapped watch posts on the pocket's edges (two toward the thicket, one south of the arena).
const WATCH_POSTS := [
	{"id": "c1x_post_0", "pos": Vector2(-74.5, -39.5), "yaw_deg": 250.0},
	{"id": "c1x_post_1", "pos": Vector2(-73.3, -45.0), "yaw_deg": 290.0},
	{"id": "c1x_post_2", "pos": Vector2(-81.5, -21.0), "yaw_deg": 330.0},
]
const POST_RADIUS := 0.4

## --- Lantern Moth dusk pocket (east shore of Mirror Pond; the far side from both paths) -----------------------
const MOTH_SPAWNER := {"id": "c1x_sp_moths", "enemy": "lantern_moth", "pos": Vector2(63.0, 53.0),
	"count": 2, "radius": 3.5, "respawn_minutes": 720.0, "wander_radius": 3.0}
## In-game hours when the pocket is awake: from dusk to just before dawn (wraps midnight).
const MOTH_HOURS := {"from": 18.0, "to": 5.5}
## Pale night-blooming "moonbells" the moths gather around (decor; they glow softly while the pocket is awake).
const MOTH_BLOOMS := [Vector2(61.2, 51.4), Vector2(64.6, 51.6), Vector2(62.4, 55.2), Vector2(65.2, 54.6)]
const BLOOM_RADIUS := 0.3

## --- Seasonal decor (Settings "seasonal_decor"): a few pumpkins and ribbons along the dirt paths only ----------
## [pos, yaw_deg (faces the path), pumpkin count]. Never in the Haven build area (checked again at runtime
## against BUILD_AREA and its Chapter Two "extra" regions), never on a path.
const SEASONAL_PUMPKINS := [
	[Vector2(-34.8, 12.9), -164.0, 2], [Vector2(-4.0, -37.7), -77.0, 1], [Vector2(33.6, -40.3), -129.0, 2],
	[Vector2(37.7, -5.8), -166.0, 2], [Vector2(49.8, -13.4), 9.0, 1], [Vector2(41.5, 31.6), -39.0, 2],
	[Vector2(-6.2, 35.8), 75.0, 1], [Vector2(19.0, 66.8), -172.0, 2], [Vector2(32.1, 61.1), -144.0, 1],
]
const SEASONAL_RIBBONS := [
	[Vector2(-48.4, 9.4), -2.0], [Vector2(-12.2, -49.1), 105.0], [Vector2(37.6, -53.8), 53.0],
	[Vector2(6.4, 60.9), -17.0], [Vector2(-9.7, 48.7), 74.0], [Vector2(-47.5, -28.8), 135.0],
]
const SEASONAL_RADIUS := 0.6
## Seasonal pieces keep at least this far from any buildable region (legacy circle or Chapter Two extras).
const SEASONAL_BUILD_MARGIN := 4.0


## Midpoint of a root slot (world XZ).
static func root_slot_mid(i: int) -> Vector2:
	var s: Dictionary = ROOT_SLOTS[i]
	var a := float(s["angle"])
	var c: Vector2 = ELDER_ARENA["centre"]
	return c + Vector2(cos(a), sin(a)) * float(s["r"])


## The two ends of a root slot's wall (it runs along the arena's tangent).
static func root_slot_ends(i: int) -> Array:
	var a := float(ROOT_SLOTS[i]["angle"])
	var tng := Vector2(-sin(a), cos(a))
	var mid := root_slot_mid(i)
	var half := float(ELDER_ARENA["root_length"]) * 0.5
	return [mid - tng * half, mid + tng * half]


## True while the Lantern Moth pocket is awake (dusk and night; the window wraps midnight).
static func is_moth_time(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	var from := float(MOTH_HOURS["from"])
	var to := float(MOTH_HOURS["to"])
	if from <= to:
		return h >= from and h < to
	return h >= from or h < to


## Every placed piece: [{"id", "pos": Vector2, "radius": float, "kind"}]. "persistent" pieces are harvestable
## nodes whose id is saved in GameState.depleted. Used by the site tests and by grass clearings.
static func footprints() -> Array:
	var out: Array = []
	out.append({"id": TAILOR_CACHE["id"], "pos": TAILOR_CACHE["pos"], "radius": TAILOR_CACHE["radius"], "kind": "cache"})
	for r in TAILOR_RIBBONS:
		out.append({"id": r["id"], "pos": r["pos"], "radius": RIBBON_RADIUS, "kind": "ribbon"})
	for s in SAP_STUMPS:
		out.append({"id": s["id"], "pos": s["pos"], "radius": SAP_RADIUS, "kind": SAP_KIND, "persistent": true})
	for s in SUNFLAX:
		out.append({"id": s["id"], "pos": s["pos"], "radius": PLANT_RADIUS, "kind": SUNFLAX_KIND, "persistent": true})
	for s in ROSEBERRY:
		out.append({"id": s["id"], "pos": s["pos"], "radius": PLANT_RADIUS, "kind": ROSEBERRY_KIND, "persistent": true})
	out.append({"id": STICKY_TREE["id"], "pos": STICKY_TREE["pos"], "radius": STICKY_TREE["radius"], "kind": "sticky_tree"})
	for p in WATCH_POSTS:
		out.append({"id": p["id"], "pos": p["pos"], "radius": POST_RADIUS, "kind": "post"})
	for i in MOTH_BLOOMS.size():
		out.append({"id": "c1x_bloom_%d" % i, "pos": MOTH_BLOOMS[i], "radius": BLOOM_RADIUS, "kind": "bloom"})
	return out


## Spawners placed by the annexes: [{id, enemy, pos, ...}].
static func spawners() -> Array:
	return [BRAMBLEBACK_SPAWNER, ELDER_SPAWNER, MOTH_SPAWNER]


## Seasonal pieces as footprints (not persistent).
static func seasonal_footprints() -> Array:
	var out: Array = []
	for i in SEASONAL_PUMPKINS.size():
		out.append({"id": "c1x_pumpkin_%d" % i, "pos": SEASONAL_PUMPKINS[i][0], "radius": SEASONAL_RADIUS, "kind": "pumpkin"})
	for i in SEASONAL_RIBBONS.size():
		out.append({"id": "c1x_path_ribbon_%d" % i, "pos": SEASONAL_RIBBONS[i][0], "radius": SEASONAL_RADIUS, "kind": "path_ribbon"})
	return out


## Every id this module introduces (nodes, spawners, zone).
static func all_ids() -> Array:
	var out: Array = []
	for f in footprints():
		out.append(String(f["id"]))
	for f in seasonal_footprints():
		out.append(String(f["id"]))
	for s in spawners():
		out.append(String(s["id"]))
	out.append(BRAMBLEWATCH_ZONE)
	return out
