extends Control
## Painted storybook map, drawn with _draw. Two outdoor layouts:
##   "surface"           Hollowhaven Woods from data/world_layout.gd: soft terrain regions, the forest border,
##                       the winding stream with its crossings, Mirror Pond, little trees, dashed footpaths and
##                       landmark stickers (legacy drawing, unchanged). Once Chapter Two is accepted the
##                       Lanternwake waygate gets a pin north of the Moonlit Ruin.
##   "hallowmere_reach"  Hallowmere Reach from data/hallowmere_layout.gd: only DISCOVERED landmarks
##                       (GameState.discovered) are drawn, plus the Lantern Road arches (lit ones glow; unlit ones
##                       show once their district is discovered) and the waygate home. Once the Commons festival
##                       board is read (layout MAP_ROUTES flag) its roads are drawn and the branch districts not
##                       found yet get "?" pins.
## Both draw friends, the player's arrow (from the camera yaw) and pulsing rings on every objective target
## (`target_ids`, landmark or point ids; an undiscovered target gets a "?" pin instead of its sticker). After
## "The Long Way Home" (flag ch2_map_pins_upgraded) the objective pins get a gold ring and a star badge.
## Mastery map clarity (src/core/mastery.gd, data/mastery.gd), both outdoor maps, read in prepare():
##   Wayfinding 2  small paper pins with the material's icon where Krystal gathered special materials
##                 (Mastery.known_spots; same-kind spots closer than PIN_MERGE_M share one pin)
##   Wayfinding 4  a soft, steady "?" (no pulse) at unfound optional caches in discovered districts (Mastery.cache_hints)
## The woods map also names Bramblewatch (data/c1x_layout.gd BRAMBLEWATCH_ZONES[0]) once its zone is discovered.
## A Lanternwake Expedition under way (src/expeditions/expeditions.gd, safe-loaded) puts its route on the Reach
## map, read in prepare(): numbered paper pins for its stops, a candy pin for its cache (done stops faded and
## ticked) and a steady ring on the current one; "exp_*" ids resolve through Expeditions.place_disc() so the
## tracker / map panel can target them. Nothing is drawn while no run is going (lead decision P35).
## Reach map readability (visual QA UI-01): the autumn forest is a quiet backdrop, not confetti - fewer, smaller
## trees (REACH_TREE_COUNT, REACH_TREE_R) in muted paper-washed colours (reach_tree_colors) drawn UNDER the roads
## and footpaths, and no tree disc touches a pin, sticker or name (reach_tree_discs: cleared per control size
## against reach_pin_rects). The expedition route is a dashed ribbon line from stop to stop to the cache, and its
## pins are drawn larger (EXP_MAP_K) with a soft gold halo while still to do.
## The static helpers below (map kinds, area / place names, room lists) are shared with the tracker, the
## journal and the map panel so every screen names places the same way.

const Layout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const Palette := preload("res://src/art/palette.gd")
const Mastery := preload("res://src/core/mastery.gd")

const REACH_ID := "hallowmere_reach"

const H := 118.0
const REGIONS := {
	"haven": [Color("c7e39a"), 1.25],
	"glade": [Color("a9d37d"), 1.0],
	"quarry": [Color("d9d2c3"), 1.0],
	"ruin": [Color("c9c3dc"), 1.0],
	"mine_mouth": [Color("a8927e"), 1.3],
	"meadow": [Color("eadf8f"), 1.1],
	"old_oak": [Color("7fae57"), 1.2],
	"thicket": [Color("6f9a4f"), 1.1],
}
const ICONS := {"haven": "map_house", "glade": "map_glade", "quarry": "map_quarry", "ruin": "map_ruin",
	"mine_mouth": "map_mine", "pond": "map_pond", "meadow": "map_flower", "old_oak": "map_oak", "thicket": "map_thorn"}
const PATHS := [["haven", "glade"], ["haven", "meadow"], ["haven", "old_oak"], ["old_oak", "thicket"], ["old_oak", "ruin"],
	["haven", "@1", "quarry"], ["haven", "@0", "mine_mouth"], ["haven", "@2", "pond"]]

## Surface Chapter Two pin (shown once `ch2_accepted` is set; lit after `ch2_waygate_repaired`).
const WAYGATE_ID := "waygate"
const WAYGATE_NAME := "Lanternwake Waygate"

## --- Hallowmere Reach --------------------------------------------------------------------------------
## Shown world extent (metres): the playable half extents plus a small margin.
const REACH_HALF := Vector2(Reach.HALF_X + 8.0, Reach.HALF_Z + 8.0)
const REACH_REGIONS := {
	"hr_commons": [Color("f2d27c"), 1.0],
	"hr_conservatory": [Color("bfe0a0"), 1.1],
	"hr_orchard": [Color("eaa75e"), 1.0],
	"hr_pools": [Color("a9d3d6"), 1.1],
	"hr_candleyard": [Color("bdb3cc"), 1.0],
	"hr_quarry": [Color("d8ccb8"), 1.0],
	"hr_manor_grounds": [Color("bb9bb8"), 1.0],
	"hr_bellhouse": [Color("aea296"), 1.2],
}
## Sticker per Reach landmark: [preferred map glyph, fallback drawing that exists today].
const REACH_ICONS := {
	"hr_commons": ["map_lantern", "string_lights"],
	"hr_conservatory": ["map_glasshouse", "planter"],
	"hr_orchard": ["map_pumpkin", "pumpkin"],
	"hr_pools": ["map_pond", "map_pond"],
	"hr_candleyard": ["map_candle", "ghost_lantern"],
	"hr_quarry": ["map_quarry", "map_quarry"],
	"hr_manor_grounds": ["map_manor", "crescent_window"],
	"hr_bellhouse": ["map_bell", "chime"],
}
## Footpaths (landmark ids or Reach POINTS ids); drawn once both end landmarks are discovered.
const REACH_PATHS := [["mirror_waygate", "commons_arch", "hr_commons"], ["hr_commons", "conservatory_arch", "hr_conservatory"],
	["hr_commons", "orchard_arch", "hr_orchard"], ["hr_commons", "quarry_arch", "hr_quarry"],
	["hr_conservatory", "manor_arch", "hr_manor_grounds"], ["hr_orchard", "hr_pools"], ["hr_conservatory", "hr_pools"],
	["hr_pools", "hr_candleyard"], ["hr_orchard", "hr_candleyard"], ["hr_quarry", "hr_bellhouse"],
	["hr_manor_grounds", "hr_bellhouse"]]
## The festival road (layout MAP_ROUTES / PATHS id) that replaces each of the first REACH_PATHS footpaths once
## the board has been read (so a known road is never drawn twice, as a road and as a straight dashed line).
const REACH_PATH_ROADS := ["arrival_road", "main_road", "west_road", "east_road", "north_road"]
## Point id that stands for "the waygate home" on the Reach map.
const REACH_WAYGATE := "mirror_waygate"
const REACH_WAYGATE_NAME := "Waygate home"
## The Reach layout file; MAP_ROUTES / PATHS (Wave C additions) are read through its constant map so a layout
## without them just shows no festival roads (never a parse error).
const REACH_LAYOUT_PATH := "res://data/hallowmere_layout.gd"
## Flag set by "The Long Way Home" reward ("Your map pins are fancier, too"): gold objective pins.
const PINS_UPGRADE_FLAG := "ch2_map_pins_upgraded"

## --- Mastery map clarity and Chapter One additions on the woods map ----------------------------------------
## Resource pins (Wayfinding 2): same-kind spots closer than this (metres) are drawn as one pin.
const PIN_MERGE_M := 9.0
const PIN_R := 11.0               # pin disc radius (px)
const PIN_ICON := 20.0            # material icon size inside a pin (px)
const HINT_R := 13.0              # cache hint disc radius (px)
## Bramblewatch (Chapter One optional area, module B7): named once its zone is discovered. Read through the
## layout's constant map (a missing layout just shows nothing).
const C1X_LAYOUT_PATH := "res://data/c1x_layout.gd"
## Lanternwake Expeditions (safe-loaded: a missing or broken module draws and resolves nothing).
const EXPEDITIONS_PATH := "res://src/expeditions/expeditions.gd"
const EXP_PREFIX := "exp_"
const EXP_PIN_R := 12.0           # expedition pin disc radius (px)
const EXP_RING_R := 19.0          # steady ring around the current stop / cache (px)
const EXP_MAP_K := 1.3            # expedition pins on the map itself (the legend swatch keeps its own size)
const BRAMBLEWATCH_NAME := "Bramblewatch"
const BRAMBLEWATCH_ZONE_DEFAULT := "c1x_bramblewatch"
const BRAMBLEWATCH_LABEL_SIZE := 20

## --- Areas and rooms ------------------------------------------------------------------------------------
const AREA_NAMES := {
	"surface": "Hollowhaven Woods",
	"below": "The Deep Places",
	"hallowmere_reach": "Hallowmere Reach",
	"moonveil_manor": "Moonveil Manor",
	"hushed_works": "The Hushed Works",
	"tobin_annex": "Tobin's Annex",
	"echo_trial": "Echo Trial",
}
## Interior rooms in route order (zone ids of docs/CHAPTER_TWO_SPEC.md §7.2-7.4); "safe" = safe room.
## "alt_name" is used in arachnophobia mode.
const ROOMS := {
	"moonveil_manor": [
		{"id": "mm_cloakroom", "name": "Entrance Cloakroom", "safe": true},
		{"id": "mm_hall", "name": "Looking-Glass Hall"},
		{"id": "mm_ballroom", "name": "Ballroom"},
		{"id": "mm_gallery", "name": "Count's Gallery"},
		{"id": "mm_balcony", "name": "Conservatory Balcony", "safe": true}],
	"hushed_works": [
		{"id": "hw_landing", "name": "Service Landing", "safe": true},
		{"id": "hw_lockers", "name": "Tool Lockers"},
		{"id": "hw_rails", "name": "Humming Rails"},
		{"id": "hw_sluice", "name": "Sluice Gallery"},
		{"id": "hw_bells", "name": "Bellmaker's Floor"},
		{"id": "hw_eyes", "name": "Hall of Closed Eyes"},
		{"id": "hw_refuge", "name": "Pocket Conservatory", "safe": true},
		{"id": "hw_lightwell", "name": "Light Well"},
		{"id": "hw_winch", "name": "Threaded Winch", "alt_name": "Rooted Winch"},
		{"id": "hw_crossing", "name": "Weaver's Crossing", "alt_name": "The Hollow Crossing"},
		{"id": "hw_wrong_landing", "name": "The Wrong Landing"},
		{"id": "hw_porch", "name": "The Borrowed Porch"},
		{"id": "hw_throat", "name": "Bell Throat", "safe": true},
		{"id": "hw_vault", "name": "Choir Vault"}],
	"tobin_annex": [
		{"id": "ta_entry", "name": "Side-Door Landing", "safe": true},
		{"id": "ta_lockers", "name": "Shift Lockers"},
		{"id": "ta_sump", "name": "The Old Sump"}],
}
## How to get into an interior from the outdoor map it hangs off: [outdoor area, landmark id].
const ENTRANCES := {
	"moonveil_manor": [REACH_ID, "hr_manor_grounds"],
	"hushed_works": [REACH_ID, "hr_bellhouse"],
	"tobin_annex": ["surface", "mine_mouth"],
	"below": ["surface", "mine_mouth"],
}

## Which layout this view draws: "surface" or "hallowmere_reach".
var map_area: String = "surface"
## Landmark / point ids to mark as objective targets (all of them pulse). Assign a new array to change them.
var target_ids: Array = []:
	set(v):
		target_ids = v
		_targets_dirty = true
## Legacy single target (kept for callers of the Chapter One map); merged with target_ids.
var target_id: String = "":
	set(v):
		target_id = v
		_targets_dirty = true
## Draw Krystal and the friends (only on the map of the area she is in).
var show_player: bool = true
var _t := 0.0
var _trees: Array = []
var _stream: PackedVector2Array
var _prepared := ""
var _reach_trees: Array = []      # fixed candidate trees [pos, radius, colour index]
var _visible_trees: Array = []    # the candidates outside discovered clearings (rebuilt in prepare())
var _tree_discs: Array = []       # [[map Vector2, px radius, colour index]] actually drawn (reach_tree_discs)
var _tree_discs_size := Vector2(-1, -1)
var _tree_discs_dirty := true
var _discovered: Array = []       # discovered Reach landmark ids (read in prepare())
var _label_at: Dictionary = {}     # Reach landmark id -> name baseline centre (see reach_label_at)
var _label_size := Vector2(-1, -1)
var _targets_dirty := true
var _target_ids_all: Array = []   # all_targets(), cached for _draw
var _target_world := PackedVector2Array()   # their world positions on this map (ids not on it skipped)
var _arches: Array = []           # [arch id, lit] shown on the Reach map (read in prepare())
var _route_ids: Array = []        # ids of the festival roads drawn (layout PATHS ids)
var _routes_world: Array = []     # festival roads once the festival map is read ([PackedVector2Array], metres)
var _routes_map: Array = []       # the same in map pixels, cached per control size
var _routes_size := Vector2(-1, -1)
var _branch_hints: Array = []     # undiscovered branch districts the festival map marks ("?" pins)
var _star := PackedVector2Array()  # upgraded-pin star, built once (drawn through draw_set_transform)
var _star_outline := PackedVector2Array()
## "The Long Way Home" reward: objective pins get a gold ring and star (read in prepare()).
var pins_upgraded := false
## Mastery pins on this map (read in prepare()): [[world Vector2, kind, item id, spots merged]] / cache hint points.
var resource_pins: Array = []
var cache_hint_points: Array = []
## Bramblewatch on the woods map once discovered (world Vector2), else null (read in prepare()).
var bramblewatch_at: Variant = null
## The running expedition's pins on the Reach map (Expeditions.map_marks, read in prepare(); [] elsewhere / no run).
var expedition_marks: Array = []
var _bramble_label := Vector2.ZERO
var _bramble_size := Vector2(-1, -1)
var frames_drawn := 0             # _draw calls (tests: the drawing code really ran)
static var _reach_tree_cols: Array = []   # reach_tree_colors(), built once


# --- Static helpers (shared by tracker / journal / map panel) -------------------------------------------

## "surface" (painted woods), "reach" (painted Reach), "rooms" (room list) or "none" (no map).
## Unknown areas (debug arenas) keep the legacy behaviour: the woods map.
static func map_kind(area_id: String) -> String:
	match area_id:
		REACH_ID:
			return "reach"
		"moonveil_manor", "hushed_works", "tobin_annex":
			return "rooms"
		"below", "echo_trial":
			return "none"
	return "surface"


static func area_name(area_id: String) -> String:
	return String(AREA_NAMES.get(area_id, ""))


## Rooms of an interior area ([] for outdoor areas).
static func rooms(area_id: String) -> Array:
	return ROOMS.get(area_id, [])


## The area a landmark / room id belongs to ("" when unknown). Legacy targets are surface landmarks.
static func area_of(place_id: String) -> String:
	if place_id == "":
		return ""
	if place_id.begins_with(EXP_PREFIX):
		return REACH_ID if _expeditions() != null else ""
	if Layout.LANDMARKS.has(place_id) or place_id == WAYGATE_ID:
		return "surface"
	if Reach.LANDMARKS.has(place_id) or Reach.POINTS.has(place_id):
		return REACH_ID
	for a in ROOMS:
		for r in ROOMS[a]:
			if String(r["id"]) == place_id:
				return String(a)
	return ""


## Display name of a landmark / room ("" when unknown); arachnophobia-aware for rooms with an alt name.
static func place_name(place_id: String, area_id: String = "") -> String:
	if place_id == "":
		return ""
	if area_id == "":
		area_id = area_of(place_id)
	match map_kind(area_id):
		"surface":
			if place_id == WAYGATE_ID:
				return WAYGATE_NAME
			return String(Layout.LANDMARKS.get(place_id, {}).get("name", ""))
		"reach":
			if Reach.LANDMARKS.has(place_id):
				return String(Reach.LANDMARKS[place_id]["name"])
			if place_id == REACH_WAYGATE or place_id == "waygate_arrival":
				return REACH_WAYGATE_NAME
			if place_id.begins_with(EXP_PREFIX):
				return String(expedition_disc(place_id).get("name", ""))
			return ""
		"rooms":
			for r in rooms(area_id):
				if String(r["id"]) == place_id:
					if r.has("alt_name") and bool(Settings.get_value("arachnophobia")):
						return String(r["alt_name"])
					return String(r["name"])
	return ""


## {"pos": Vector2, "radius": float} of an outdoor landmark / point ({} for rooms and unknown ids). A running
## expedition's "exp_*" stop / cache ids resolve on the Reach map (Expeditions.place_disc; {} without a run).
static func place_disc(place_id: String, area_id: String = "") -> Dictionary:
	if area_id == "":
		area_id = area_of(place_id)
	if place_id.begins_with(EXP_PREFIX):
		return expedition_disc(place_id) if map_kind(area_id) == "reach" else {}
	match map_kind(area_id):
		"surface":
			if Layout.LANDMARKS.has(place_id):
				return {"pos": Layout.LANDMARKS[place_id]["pos"], "radius": float(Layout.LANDMARKS[place_id]["radius"])}
			if place_id == WAYGATE_ID and Layout.CH2_POINTS.has("waygate"):
				return {"pos": Layout.CH2_POINTS["waygate"], "radius": 6.0}
		"reach":
			if Reach.LANDMARKS.has(place_id):
				return {"pos": Reach.LANDMARKS[place_id]["pos"], "radius": float(Reach.LANDMARKS[place_id]["radius"])}
			if place_id == "waygate_arrival":
				return {"pos": Reach.POINTS["waygate_arrival"], "radius": Reach.ARRIVAL_SAFE_RADIUS}
			if Reach.POINTS.has(place_id):
				return {"pos": Reach.POINTS[place_id], "radius": Reach.ARCH_SAFE_RADIUS}
	return {}


## True when a map landmark counts as discovered for drawing. Surface landmarks are always known (legacy);
## Reach landmarks and interior rooms need GameState.discover().
static func is_known(place_id: String, area_id: String) -> bool:
	match map_kind(area_id):
		"surface":
			return true
		"reach", "rooms":
			return GameState.is_discovered(area_id, place_id)
	return false


## Lantern Road arch ids that belong on the Reach map: lit ones, and unlit ones whose district is discovered.
static func visible_arches() -> Array:
	var out: Array = []
	for id in Reach.ARCH_ORDER:
		if arch_lit(String(id)) or GameState.is_discovered(REACH_ID, String(Reach.ARCHES[id]["landmark"])):
			out.append(String(id))
	return out


static func arch_lit(arch_id: String) -> bool:
	return true if GameState.get_flag(Reach.arch_flag(arch_id)) else false


## The waygate pin exists on the woods map once Chapter Two is accepted.
static func surface_waygate_visible() -> bool:
	return true if GameState.get_flag("ch2_accepted") else false


static func surface_waygate_lit() -> bool:
	return true if GameState.get_flag("ch2_waygate_repaired") else false


static func map_pins_upgraded() -> bool:
	return true if GameState.get_flag(PINS_UPGRADE_FLAG) else false


## The expeditions script, safe-loaded (null when missing or broken).
static func _expeditions() -> Script:
	if not ResourceLoader.exists(EXPEDITIONS_PATH):
		return null
	var s: Variant = load(EXPEDITIONS_PATH)
	if not (s is Script) or not (s as Script).can_instantiate():
		return null
	return s


## Expeditions.place_disc(id) for an "exp_*" id of the running route ({"pos", "radius", "name"}; {} otherwise).
static func expedition_disc(place_id: String) -> Dictionary:
	var ex := _expeditions()
	if ex == null or not ex.has_method("place_disc"):
		return {}
	var d: Variant = ex.call("place_disc", place_id)
	return d if d is Dictionary else {}


## Expeditions.current_target(): {"id", "name", "pos", "area", "kind"} of the running route's next place ({} without
## a run or without the module).
static func expedition_target() -> Dictionary:
	var ex := _expeditions()
	if ex == null or not ex.has_method("current_target"):
		return {}
	var t: Variant = ex.call("current_target")
	return t if t is Dictionary else {}


## Expeditions.map_marks(area_id): the running route's stops + cache for that map ([] elsewhere or without a run).
static func expedition_pins(area_id: String) -> Array:
	var ex := _expeditions()
	if ex == null or not ex.has_method("map_marks"):
		return []
	var m: Variant = ex.call("map_marks", area_id)
	return m if m is Array else []


## Draws one expedition pin on any CanvasItem (map and legend): a paper disc in the ribbon colour with the stop
## number (the cache: a candy icon); a done stop is faded with a tick; `current` adds a steady ring. `k` scales it.
static func draw_expedition_pin(ci: CanvasItem, c: Vector2, k: float, mark: Dictionary) -> void:
	var done := bool(mark.get("done", false))
	var cache := String(mark.get("kind", "")) == "cache"
	var a := 0.55 if done else 1.0
	var ribbon := ThemeFactory.ACCENT.darkened(0.15)
	if bool(mark.get("current", false)):
		ci.draw_arc(c, EXP_RING_R * k, 0.0, TAU, 32, Color(ThemeFactory.GOLD, 0.95), 3.5 * k, true)
	ci.draw_circle(c + Vector2(1.0, 1.5) * k, EXP_PIN_R * k, Color(0.2, 0.1, 0.1, 0.22 * a), true, -1.0, true)
	ci.draw_circle(c, EXP_PIN_R * k, Color(ThemeFactory.PAPER_LIGHT, a), true, -1.0, true)
	ci.draw_arc(c, EXP_PIN_R * k, 0.0, TAU, 24, Color(ThemeFactory.GOLD.darkened(0.2) if cache else ribbon, a), 2.4 * k, true)
	if done:
		var ck := IconFactory.icon("ui_check", Color.WHITE, 48)
		var cs := EXP_PIN_R * 1.5 * k
		ci.draw_texture_rect(ck, Rect2(c - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false, Color(1, 1, 1, 0.8))
	elif cache:
		var tex := IconFactory.item_icon("candy", 48)
		var sz := PIN_ICON * k
		if tex != null:
			ci.draw_texture_rect(tex, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)
	else:
		var f := ThemeFactory.font("heading")
		var fs := int(round(17.0 * k))
		var txt := str(int(mark.get("n", 0)))
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, c + Vector2(-tw * 0.5, 6.0 * k), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ThemeFactory.INK)


## A constant of data/hallowmere_layout.gd by name (`fallback` when the layout has no such constant).
static func _reach_const(const_name: String, fallback: Variant) -> Variant:
	return _layout_const(REACH_LAYOUT_PATH, const_name, fallback)


## A constant of a layout data file by name (`fallback` when the file or the constant is missing).
static func _layout_const(path: String, const_name: String, fallback: Variant) -> Variant:
	if not ResourceLoader.exists(path):
		return fallback
	var s := load(path) as Script
	if s == null:
		return fallback
	return s.get_script_constant_map().get(const_name, fallback)


## Where "Bramblewatch" is written on the woods map (its first zone circle, data/c1x_layout.gd), or null while
## its zone is undiscovered (or the layout is missing).
static func bramblewatch_pos() -> Variant:
	var zone := String(_layout_const(C1X_LAYOUT_PATH, "BRAMBLEWATCH_ZONE", BRAMBLEWATCH_ZONE_DEFAULT))
	if not GameState.is_discovered("surface", zone):
		return null
	var zones: Variant = _layout_const(C1X_LAYOUT_PATH, "BRAMBLEWATCH_ZONES", [])
	if not (zones is Array) or (zones as Array).is_empty() or not ((zones as Array)[0] is Array):
		return null
	var first: Array = (zones as Array)[0]
	if first.is_empty() or not (first[0] is Vector2):
		return null
	return first[0]


## Recorded resource spots merged for drawing: [[world Vector2, kind, item id, count]]; a spot joins the first
## pin of its kind closer than PIN_MERGE_M (so a pocket of veins is one pin, never a pile of identical marks).
static func merged_pins(spots: Array) -> Array:
	var out: Array = []
	for sp in spots:
		var kind := String(sp["kind"])
		var p: Vector2 = sp["pos"]
		var joined := false
		for o in out:
			if String(o[1]) == kind and (o[0] as Vector2).distance_to(p) < PIN_MERGE_M:
				o[3] = int(o[3]) + 1
				joined = true
				break
		if not joined:
			out.append([p, kind, Mastery.spot_item(kind), 1])
	return out


## The outdoor map whose mastery data a map area shows ("surface" for the woods and debug areas).
static func data_area(area_id: String) -> String:
	return REACH_ID if area_id == REACH_ID else "surface"


## Draws a resource pin (paper disc + material icon) on any CanvasItem (map and legend). `k` scales it.
static func draw_spot_pin(ci: CanvasItem, c: Vector2, k: float, tex: Texture2D) -> void:
	ci.draw_circle(c + Vector2(1.0, 1.5) * k, PIN_R * k, Color(0.2, 0.1, 0.1, 0.22), true, -1.0, true)
	ci.draw_circle(c, PIN_R * k, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
	ci.draw_arc(c, PIN_R * k, 0.0, TAU, 20, ThemeFactory.INK_SOFT, 1.6, true)
	if tex != null:
		var sz := PIN_ICON * k
		ci.draw_texture_rect(tex, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)


## Draws a soft, steady cache hint "?" (smaller and paler than the undiscovered-district pin; never pulses).
static func draw_hint_pin(ci: CanvasItem, c: Vector2, k: float) -> void:
	var f := ThemeFactory.font("heading")
	ci.draw_circle(c, HINT_R * k, Color(ThemeFactory.PAPER_LIGHT, 0.82), true, -1.0, true)
	ci.draw_arc(c, HINT_R * k, 0.0, TAU, 24, Color(ThemeFactory.GOLD.darkened(0.2), 0.85), 2.0 * k, true)
	var fs := int(round(19.0 * k))
	var tw := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, c + Vector2(-tw * 0.5, 7.0 * k), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ThemeFactory.INK_SOFT, 0.9))


## True once the Commons festival board has been read (MAP_ROUTES "flag", ch2_read_festival_map).
static func festival_map_read() -> bool:
	var mr: Variant = _reach_const("MAP_ROUTES", {})
	if not (mr is Dictionary) or String((mr as Dictionary).get("flag", "")) == "":
		return false
	return true if GameState.get_flag(String(mr["flag"])) else false


## Ids of the roads the festival map reveals that the layout can draw (MAP_ROUTES "roads" with a PATHS
## centreline); [] until the board is read. Step 4 ("The festival map marks three sleeping lamps") relies on it.
static func festival_road_ids() -> Array:
	var out: Array = []
	if not festival_map_read():
		return out
	var mr: Dictionary = _reach_const("MAP_ROUTES", {})
	var paths: Variant = _reach_const("PATHS", {})
	if not (paths is Dictionary):
		return out
	for rid in mr.get("roads", []):
		var pts: Variant = (paths as Dictionary).get(rid)
		if pts is Array and (pts as Array).size() >= 2:
			out.append(String(rid))
	return out


## The same roads as world polylines (Catmull-Rom through the layout centrelines), in festival_road_ids() order.
static func festival_roads() -> Array:
	var out: Array = []
	var paths: Variant = _reach_const("PATHS", {})
	for rid in festival_road_ids():
		out.append(_spline((paths as Dictionary)[rid], 4))
	return out


## Branch districts the festival map marks that are not discovered yet: they get a "?" pin (no name, no sticker).
static func festival_hints() -> Array:
	var out: Array = []
	if not festival_map_read():
		return out
	var br: Variant = (_reach_const("MAP_ROUTES", {}) as Dictionary).get("branches", {})
	if br is Dictionary:
		for id in br:
			if Reach.LANDMARKS.has(id) and not GameState.is_discovered(REACH_ID, String(id)):
				out.append(String(id))
	return out


## Sticker icon id of a landmark on its map (the preferred glyph when it has a drawing, else the fallback).
static func place_icon(place_id: String, area_id: String) -> String:
	if map_kind(area_id) == "reach":
		var pair: Array = REACH_ICONS.get(place_id, ["unknown", "unknown"])
		return String(pair[0]) if IconFactory.has_drawing(String(pair[0])) else String(pair[1])
	return String(ICONS.get(place_id, "unknown"))


## Draws a little Lantern Road arch pin on any CanvasItem (map and legend). `k` scales it.
static func draw_arch_pin(ci: CanvasItem, c: Vector2, k: float, lit: bool) -> void:
	if lit:
		ci.draw_circle(c + Vector2(0, -4) * k, 15.0 * k, Color(ThemeFactory.GOLD, 0.35), true, -1.0, true)
	var col := ThemeFactory.GOLD.darkened(0.15) if lit else Color("9a9087")
	var w := 4.0 * k
	ci.draw_line(c + Vector2(-8, 8) * k, c + Vector2(-8, -3) * k, ThemeFactory.INK, w + 3.0, true)
	ci.draw_line(c + Vector2(8, 8) * k, c + Vector2(8, -3) * k, ThemeFactory.INK, w + 3.0, true)
	ci.draw_arc(c + Vector2(0, -3) * k, 8.0 * k, PI, TAU, 12, ThemeFactory.INK, w + 3.0, true)
	ci.draw_line(c + Vector2(-8, 8) * k, c + Vector2(-8, -3) * k, col, w, true)
	ci.draw_line(c + Vector2(8, 8) * k, c + Vector2(8, -3) * k, col, w, true)
	ci.draw_arc(c + Vector2(0, -3) * k, 8.0 * k, PI, TAU, 12, col, w, true)
	ci.draw_circle(c + Vector2(0, -3) * k, 3.2 * k, ThemeFactory.CREAM if lit else Color("6e6660"), true, -1.0, true)


# --- Node -------------------------------------------------------------------------------------------------

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	prepare()


## (Re)reads the layout data for `map_area`; call after changing it (the panel sets it before adding).
func prepare() -> void:
	pins_upgraded = map_pins_upgraded()
	if pins_upgraded and _star.is_empty():
		for i in 10:
			var a := -PI * 0.5 + TAU * float(i) / 10.0
			_star.append(Vector2(cos(a), sin(a)) * (9.0 if i % 2 == 0 else 4.0))
		_star_outline = _star.duplicate()
		_star_outline.append(_star[0])
	# (the pins first: the Reach forest keeps clear of them)
	_prepare_mastery()
	expedition_marks = expedition_pins(REACH_ID) if map_area == REACH_ID else []
	if map_area == REACH_ID:
		_prepare_reach()
	elif _prepared != "surface":
		_prepare_surface()
	_prepared = map_area if map_area == REACH_ID else "surface"
	_targets_dirty = true
	_tree_discs_dirty = true


## Mastery pins / hints and the Bramblewatch name for this map (never per frame).
func _prepare_mastery() -> void:
	var area := data_area(map_area)
	resource_pins = merged_pins(Mastery.known_spots(area)) if Mastery.resource_pins_on() else []
	cache_hint_points = []
	if Mastery.cache_hints_on():
		for h in Mastery.cache_hints(area):
			cache_hint_points.append(h["pos"])
	bramblewatch_at = bramblewatch_pos() if area == "surface" else null
	_bramble_size = Vector2(-1, -1)


## Resolves the objective targets to world points on this map once (not every frame).
func _cache_targets() -> void:
	_targets_dirty = false
	_tree_discs_dirty = true
	_target_ids_all = all_targets()
	_target_world = PackedVector2Array()
	for tid in _target_ids_all:
		var p: Variant = target_pos(String(tid))
		if p != null:
			_target_world.append(p)


func _prepare_surface() -> void:
	_stream = _spline(Layout.STREAM_POINTS, 10)
	_trees = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240517
	var tries := 0
	while _trees.size() < 150 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(-106, 106), rng.randf_range(-106, 106))
		if _near_stream(p, 9.0) or _in_landmark(p, 0.85):
			continue
		_trees.append([p, rng.randf_range(3.2, 5.2), rng.randi() % 3])


## Trees are a FIXED seeded set (so they never move); the ones inside discovered clearings are hidden, so
## undiscovered districts leave no tell-tale clearing on the map.
func _prepare_reach() -> void:
	if _reach_trees.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261031
		var tries := 0
		# small groves (a few trees round a seeded centre) read as woodland; an even scatter read as confetti
		var grove := Vector2.ZERO
		var in_grove := 0
		while _reach_trees.size() < REACH_TREE_COUNT and tries < 4000:
			tries += 1
			if in_grove <= 0:
				grove = Vector2(rng.randf_range(-Reach.HALF_X + 10.0, Reach.HALF_X - 10.0), rng.randf_range(-Reach.HALF_Z + 10.0, Reach.HALF_Z - 10.0))
				in_grove = rng.randi_range(REACH_GROVE_TREES.x, REACH_GROVE_TREES.y)
			in_grove -= 1
			var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * REACH_GROVE_R
			var p := Vector2(clampf(grove.x + off.x, -Reach.HALF_X + 6.0, Reach.HALF_X - 6.0), clampf(grove.y + off.y, -Reach.HALF_Z + 6.0, Reach.HALF_Z - 6.0))
			var near_point := false
			for pid in Reach.POINTS:
				if p.distance_to(Reach.POINTS[pid]) < 9.0:
					near_point = true
					break
			if near_point:
				continue
			_reach_trees.append([p, rng.randf_range(REACH_TREE_R.x, REACH_TREE_R.y), rng.randi() % 4])
	_discovered = GameState.discovered_in(REACH_ID)
	_arches = []
	for aid in visible_arches():
		_arches.append([aid, arch_lit(String(aid))])
	_route_ids = festival_road_ids()
	_routes_world = festival_roads()
	_routes_size = Vector2(-1, -1)
	_routes_map = []
	_branch_hints = festival_hints()
	_visible_trees = []
	for t in _reach_trees:
		var inside := false
		var tp: Vector2 = t[0]
		for id in _discovered:
			var lm: Dictionary = Reach.LANDMARKS.get(id, {})
			if not lm.is_empty() and tp.distance_to(lm["pos"]) < float(lm["radius"]) * 0.9 + 4.0:
				inside = true
				break
		# known festival roads cut through the forest (unknown roads leave no gap, like undiscovered clearings)
		if not inside and not _routes_world.is_empty():
			inside = _near_any_route(tp, float(t[1]) * 0.9 + ROUTE_CLEAR)
		if not inside:
			_visible_trees.append(t)


## True when `p` (metres) lies within `d` of a known festival road.
func _near_any_route(p: Vector2, d: float) -> bool:
	for line in _routes_world:
		var pts: PackedVector2Array = line
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < d:
				return true
	return false


## Festival roads in map pixels (rebuilt only when the control's size changes; no per-frame allocation).
func _cache_routes() -> void:
	_routes_size = size
	_routes_map = []
	for line in _routes_world:
		var pts := PackedVector2Array()
		for p in (line as PackedVector2Array):
			pts.append(to_map(p))
		_routes_map.append(pts)


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()


func half_extent() -> Vector2:
	return REACH_HALF if map_area == REACH_ID else Vector2(H, H)


## The drawable map rectangle: the largest rect with the layout's aspect inside the control less a 16 px
## margin, centred (so metres map to the same pixel count on both axes). A square layout gives exactly the
## legacy rect (the control's inner square grown by -16).
func map_rect() -> Rect2:
	var he := half_extent()
	var aspect := he.x / he.y
	var avail := size - Vector2(32.0, 32.0)
	var w := avail.x
	var h := avail.x / aspect
	if h > avail.y:
		h = avail.y
		w = h * aspect
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func to_map(w: Vector2) -> Vector2:
	if map_area != REACH_ID:
		return UiUtil.world_to_map(w, map_rect(), H)
	var r := map_rect()
	var u := (w.x + REACH_HALF.x) / (REACH_HALF.x * 2.0)
	var v := (w.y + REACH_HALF.y) / (REACH_HALF.y * 2.0)
	return r.position + Vector2(u * r.size.x, v * r.size.y)


## Every objective target id (target_ids plus the legacy target_id), without duplicates.
func all_targets() -> Array:
	var out: Array = target_ids.duplicate()
	if target_id != "" and not out.has(target_id):
		out.append(target_id)
	return out


## World position of a target id on this map (null when it isn't on this map).
func target_pos(id: String) -> Variant:
	var d := place_disc(id, map_area if map_area == REACH_ID else "surface")
	if d.is_empty():
		return null
	return d["pos"]


func _draw() -> void:
	frames_drawn += 1
	if _prepared != (map_area if map_area == REACH_ID else "surface"):
		prepare()
	if _targets_dirty:
		_cache_targets()
	if map_area == REACH_ID:
		_draw_reach()
	else:
		_draw_surface()


# --- Hollowhaven Woods (legacy drawing) -------------------------------------------------------------------

func _draw_surface() -> void:
	var side := minf(size.x, size.y)
	var outer := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var r := map_rect()
	var scale := r.size.x / (H * 2.0)
	draw_style_box(ThemeFactory.box(Color("efdcb4"), 24, 3, ThemeFactory.BORDER_DARK, 0, 8, Vector2(0, 4), Color(0.2, 0.1, 0.1, 0.25)), outer)
	draw_style_box(ThemeFactory.box(Color("bcd98d"), 18), r)
	# soft terrain regions
	for id in REGIONS:
		var lm: Dictionary = Layout.LANDMARKS.get(id, {})
		if lm.is_empty():
			continue
		var c := to_map(lm["pos"])
		var rad := float(lm["radius"]) * float(REGIONS[id][1]) * scale
		_soft_disc(c, rad, REGIONS[id][0])
	# rocky cliffs around the mine
	if Layout.LANDMARKS.has("mine_mouth"):
		var mm: Vector2 = Layout.LANDMARKS["mine_mouth"]["pos"]
		for k in 7:
			var off := Vector2(cos(float(k) * 0.9 - 2.4), sin(float(k) * 0.9 - 2.4)) * (12.0 + float(k % 3) * 3.0)
			var cc := to_map(mm + off)
			draw_circle(cc, (5.0 + float(k % 3)) * scale, Color("8f7d6a"), true, -1.0, true)
	# footpaths
	for path in PATHS:
		var pts := PackedVector2Array()
		for node in path:
			pts.append(to_map(_path_point(String(node))))
		for i in pts.size() - 1:
			draw_dashed_line(pts[i], pts[i + 1], Color(Palette.DIRT_DARK, 0.75), 3.0, 9.0, true, true)
	# stream
	var sp := PackedVector2Array()
	for p in _stream:
		sp.append(to_map(p))
	var sw := maxf(Layout.STREAM_WIDTH * scale * 1.5, 8.0)
	draw_polyline(sp, Palette.WATER_DEEP, sw + 5.0, true)
	draw_polyline(sp, Palette.WATER, sw, true)
	draw_polyline(sp, Color(1, 1, 1, 0.45), maxf(sw * 0.22, 1.5), true)
	# pond
	if Layout.LANDMARKS.has("pond"):
		var pond: Vector2 = Layout.LANDMARKS["pond"]["pos"]
		var pc := to_map(pond)
		var pr := float(Layout.LANDMARKS["pond"]["radius"]) * scale * 0.95
		_ellipse(pc, Vector2(pr * 1.2, pr * 0.9), Palette.WATER, Palette.WATER_DEEP)
		_ellipse(pc + Vector2(-pr * 0.2, -pr * 0.15), Vector2(pr * 0.5, pr * 0.3), Color(1, 1, 1, 0.3), Color(0, 0, 0, 0))
	# crossings
	for cr in Layout.STREAM_CROSSINGS:
		var cp := to_map(cr)
		var dir := _stream_dir(cr)
		var n := Vector2(-dir.y, dir.x)
		var a := cp - n * (sw * 0.95)
		var b := cp + n * (sw * 0.95)
		draw_line(a, b, ThemeFactory.INK, 9.0, true)
		draw_line(a, b, Palette.WOOD, 6.0, true)
	# trees
	var tree_cols := [Palette.FOLIAGE, Palette.FOLIAGE_DARK, Palette.FOLIAGE_LIGHT.darkened(0.08)]
	for t in _trees:
		var tp := to_map(t[0])
		var tr := float(t[1]) * scale * 0.9
		draw_circle(tp + Vector2(1.5, 2.0), tr, Color(0.2, 0.3, 0.15, 0.25), true, -1.0, true)
		draw_circle(tp, tr, tree_cols[int(t[2])], true, -1.0, true)
		draw_arc(tp, tr, 0.0, TAU, 12, Color(0.22, 0.35, 0.2, 0.7), 1.2, true)
	_forest_frame(r, Color("5f8a45"))
	_draw_mastery_pins(r)
	# objective pulse (under the sticker)
	for tw in _target_world:
		_pulse(to_map(tw))
	_draw_friends(r)
	# landmarks
	var f := ThemeFactory.font("heading")
	for id in Layout.LANDMARKS:
		var lm: Dictionary = Layout.LANDMARKS[id]
		var c := to_map(lm["pos"])
		var isz := 58.0 if id == "haven" else 50.0
		var icon_id := String(ICONS.get(id, "unknown"))
		draw_texture_rect(IconFactory.icon(icon_id, Color.WHITE, 96), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)
		var name := String(lm["name"])
		var fs := 22 if id != "haven" else 24
		_name_label(f, name, Vector2(c.x, c.y + isz * 0.5 + 18.0), fs, r)
	# Chapter Two: the Lanternwake waygate (north of the Moonlit Ruin) once the road is accepted
	if surface_waygate_visible() and Layout.CH2_POINTS.has("waygate"):
		var wc := to_map(Layout.CH2_POINTS["waygate"])
		draw_arch_pin(self, wc, 1.35, surface_waygate_lit())
		_name_label(f, WAYGATE_NAME, Vector2(wc.x, wc.y - 24.0), 20, r)
	# Chapter One additions: Bramblewatch, once found
	if bramblewatch_at is Vector2:
		var bc := to_map(bramblewatch_at)
		draw_circle(bc, 7.0, Palette.FOLIAGE_DARK.darkened(0.15), true, -1.0, true)
		draw_arc(bc, 7.0, 0.0, TAU, 16, ThemeFactory.INK, 2.0, true)
		draw_circle(bc + Vector2(-2.0, -2.0), 2.0, Palette.FLOWER_RED, true, -1.0, true)
		_name_label(f, BRAMBLEWATCH_NAME, bramblewatch_label_at(), BRAMBLEWATCH_LABEL_SIZE, r)
	_draw_player(r)
	_compass(r, f)


# --- Hallowmere Reach ----------------------------------------------------------------------------------

func _draw_reach() -> void:
	var r := map_rect()
	var outer := r.grow(16.0)
	var scale := r.size.x / (REACH_HALF.x * 2.0)
	draw_style_box(ThemeFactory.box(Color("efdcb4"), 24, 3, ThemeFactory.BORDER_DARK, 0, 8, Vector2(0, 4), Color(0.2, 0.1, 0.1, 0.25)), outer)
	draw_style_box(ThemeFactory.box(REACH_PAPER, 18), r)
	# discovered districts
	for id in _discovered:
		var lm: Dictionary = Reach.LANDMARKS.get(id, {})
		if lm.is_empty():
			continue
		var reg: Array = REACH_REGIONS.get(id, [Color("e6d6a2"), 1.0])
		_soft_disc(to_map(lm["pos"]), float(lm["radius"]) * float(reg[1]) * scale, reg[0])
	# the autumn forest: a quiet backdrop under every road, path and pin (UI-01)
	var tree_cols := reach_tree_colors()
	var shade := Color(0.3, 0.18, 0.1, 0.12)
	var rim := Color(0.45, 0.3, 0.18, 0.38)
	for t in reach_tree_discs():
		var tp: Vector2 = t[0]
		var tr: float = t[1]
		draw_circle(tp + Vector2(1.0, 1.5), tr, shade, true, -1.0, true)
		draw_circle(tp, tr, tree_cols[int(t[2])], true, -1.0, true)
		draw_arc(tp, tr, 0.0, TAU, 12, rim, 1.0, true)
	# the festival roads (once the Commons board has been read)
	if not _routes_world.is_empty():
		if _routes_size != size:
			_cache_routes()
		var rw := maxf(ROUTE_WIDTH_M * scale, 6.0)
		for line in _routes_map:
			draw_polyline(line, Palette.DIRT_DARK, rw + 4.0, true)
			draw_polyline(line, Palette.DIRT, rw, true)
	# footpaths between known places (the ones a drawn festival road replaces are skipped)
	for path_i in REACH_PATHS.size():
		var path: Array = REACH_PATHS[path_i]
		if not footpath_shown(path_i):
			continue
		var pts := PackedVector2Array()
		for node in path:
			pts.append(to_map(_reach_point(String(node))))
		for i in pts.size() - 1:
			draw_dashed_line(pts[i], pts[i + 1], Color(Palette.DIRT_DARK, 0.75), 3.0, 9.0, true, true)
	_forest_frame(r, Color("a35f32"))
	_draw_mastery_pins(r)
	var f := ThemeFactory.font("heading")
	for tw in _target_world:
		_pulse(to_map(tw))
	# the waygate home and the Lantern Road arches
	var wg := to_map(Reach.POINTS[REACH_WAYGATE])
	draw_arch_pin(self, wg, WAYGATE_PIN_K, true)
	_name_label(f, REACH_WAYGATE_NAME, Vector2(wg.x, wg.y - 24.0), 20, r)
	for a in _arches:
		draw_arch_pin(self, to_map(Reach.ARCHES[a[0]]["pos"]), 1.0, bool(a[1]))
	_draw_friends(r)
	# discovered landmark stickers; undiscovered objective targets get a "?" pin
	for id in Reach.LANDMARKS:
		var lm: Dictionary = Reach.LANDMARKS[id]
		var c := to_map(lm["pos"])
		if not _discovered.has(id):
			if _target_ids_all.has(id) or _branch_hints.has(id):
				_unknown_pin(c, f)
			continue
		var isz := reach_sticker_size(String(id))
		draw_texture_rect(IconFactory.icon(place_icon(String(id), REACH_ID), Color.WHITE, 96), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)
		# names are placed clear of every sticker / arch / other name (reach_label_at)
		_name_label(f, String(lm["name"]), reach_label_at(String(id)), REACH_LABEL_SIZE, r)
	_draw_expedition(r)
	_draw_player(r)
	_compass(r, f)


## The running expedition's route (read in prepare(); nothing without a run), over the stickers so it stays
## readable, under Krystal's arrow; each pin only inside the map rectangle.
func _draw_expedition(r: Rect2) -> void:
	var ribbon := ThemeFactory.ACCENT.darkened(0.15)
	var prev := Vector2.ZERO
	var have_prev := false
	for m in expedition_marks:
		var c := to_map((m as Dictionary).get("pos", Vector2.ZERO))
		if have_prev:
			var walked := bool((m as Dictionary).get("done", false))
			draw_dashed_line(prev, c, Color(ThemeFactory.PAPER_LIGHT, 0.55 if walked else 0.85), 6.5, 12.0, true, true)
			draw_dashed_line(prev, c, Color(ribbon, 0.35 if walked else 0.9), 3.0, 12.0, true, true)
		prev = c
		have_prev = true
	for m2 in expedition_marks:
		var c2 := to_map((m2 as Dictionary).get("pos", Vector2.ZERO))
		if not r.grow(-EXP_PIN_R * EXP_MAP_K).has_point(c2):
			continue
		if not bool((m2 as Dictionary).get("done", false)):
			draw_circle(c2, (EXP_PIN_R + 5.0) * EXP_MAP_K, Color(ThemeFactory.GOLD, 0.4), true, -1.0, true)
		draw_expedition_pin(self, c2, EXP_MAP_K, m2)


## Muted autumn tree colours for the Reach map: orange, red, yellow and green washed REACH_TREE_WASH toward the
## map's paper, so they sit behind the pins instead of competing with them (UI-01).
static func reach_tree_colors() -> Array:
	if _reach_tree_cols.is_empty():
		for c in [Color("d9822b"), Color("b8452f"), Color("e8b33a"), Palette.FOLIAGE_DARK]:
			_reach_tree_cols.append((c as Color).lerp(REACH_PAPER, REACH_TREE_WASH))
	return _reach_tree_cols


## The Reach trees as drawn at the current size ([[map Vector2, px radius, colour index]]): the visible candidates
## minus every disc that would touch a pin, sticker, arch or name (reach_pin_rects). Cached per size / targets.
func reach_tree_discs() -> Array:
	if not _tree_discs_dirty and _tree_discs_size == size:
		return _tree_discs
	if _targets_dirty:
		_cache_targets()
	_tree_discs_dirty = false
	_tree_discs_size = size
	_tree_discs = []
	var r := map_rect()
	var scale := r.size.x / (REACH_HALF.x * 2.0)
	var blocks := reach_pin_rects()
	for t in _visible_trees:
		var c := to_map(t[0])
		var tr := float(t[1]) * scale * REACH_TREE_DRAW_K
		var free := true
		for b in blocks:
			var br: Rect2 = b
			var q := Vector2(clampf(c.x, br.position.x, br.end.x), clampf(c.y, br.position.y, br.end.y))
			if q.distance_to(c) < tr + REACH_TREE_GAP:
				free = false
				break
		if free:
			_tree_discs.append([c, tr, int(t[2])])
	return _tree_discs


## Screen boxes the forest keeps clear of: discovered stickers and their names, the arches shown, the waygate and
## its name, "?" pins (objective targets and festival-map branches not found yet), expedition pins (with their
## halo), the mastery resource pins and cache hints.
func reach_pin_rects() -> Array:
	var out: Array = []
	for b in reach_boxes(false):
		out.append((b as Dictionary)["rect"])
	for id in Reach.LANDMARKS:
		if not _discovered.has(id) and (_target_ids_all.has(id) or _branch_hints.has(id)):
			out.append(_disc_rect(to_map(Reach.LANDMARKS[id]["pos"]), UNKNOWN_PIN_R))
	for m in expedition_marks:
		out.append(_disc_rect(to_map((m as Dictionary).get("pos", Vector2.ZERO)), (EXP_PIN_R + 5.0) * EXP_MAP_K))
	for pin in resource_pins:
		out.append(_disc_rect(to_map(pin[0]), PIN_R))
	for hp in cache_hint_points:
		out.append(_disc_rect(to_map(hp), HINT_R))
	return out


static func _disc_rect(c: Vector2, rad: float) -> Rect2:
	return Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0)


const REACH_LABEL_SIZE := 21
const REACH_TREE_COUNT := 150     # seeded candidate trees, in groves (was an even scatter of 190: confetti)
const REACH_TREE_R := Vector2(2.8, 4.4)   # tree radius range in metres (was 3.4-5.6)
const REACH_GROVE_TREES := Vector2i(4, 9)  # trees per grove
const REACH_GROVE_R := 15.0       # grove radius (metres)
const REACH_TREE_DRAW_K := 0.9    # drawn disc radius = radius * map scale * this
const REACH_TREE_WASH := 0.45     # how far the tree colours are washed toward the paper
const REACH_TREE_GAP := 4.0       # px kept between a tree disc and any pin / sticker / name box
const REACH_PAPER := Color("d9c98f")
const UNKNOWN_PIN_R := 17.0       # "?" pin radius (px)
const ROUTE_WIDTH_M := 3.4        # drawn festival road width (metres, about the real road)
const ROUTE_CLEAR := 1.5          # trees whose disc comes this close to a known road are left out (metres)
const REACH_LABEL_GAP := 8.0
const REACH_LABEL_SHIFT := 56.0
const ARCH_PIN_HALF := 13.0      # half extent of an arch pin at k = 1 (glow included)
const WAYGATE_PIN_K := 1.35


static func reach_sticker_size(id: String) -> float:
	return 54.0 if id == "hr_commons" else 48.0


func _sticker_rect(id: String) -> Rect2:
	var c := to_map(Reach.LANDMARKS[id]["pos"])
	var isz := reach_sticker_size(id)
	return Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz))


func _pin_rect(c: Vector2, k: float) -> Rect2:
	var half := Vector2(ARCH_PIN_HALF, ARCH_PIN_HALF + 4.0) * k
	return Rect2(c - half, half * 2.0)


## Baseline centre of a Reach landmark's name: the first candidate (above the sticker, below it, then
## shifted sideways) whose ink box clears every other sticker, every arch pin, the waygate and the names placed
## before it. Computed against ALL landmarks and arches, so a name never moves when something is discovered.
## Cached per control size (no per-frame work).
func reach_label_at(id: String) -> Vector2:
	if _label_size != size or _label_at.is_empty():
		_place_reach_labels()
	return _label_at.get(id, Vector2.ZERO)


func _place_reach_labels() -> void:
	_label_size = size
	_label_at = {}
	var r := map_rect()
	var f := ThemeFactory.font("heading")
	var blocks: Array = []   # [owner id, Rect2]
	for id in Reach.LANDMARKS:
		blocks.append([String(id), _sticker_rect(String(id))])
	for aid in Reach.ARCH_ORDER:
		blocks.append(["arch:" + String(aid), _pin_rect(to_map(Reach.ARCHES[aid]["pos"]), 1.0)])
	var wg := to_map(Reach.POINTS[REACH_WAYGATE])
	blocks.append([REACH_WAYGATE, _pin_rect(wg, WAYGATE_PIN_K)])
	blocks.append([REACH_WAYGATE, _label_rect(f, REACH_WAYGATE_NAME, Vector2(wg.x, wg.y - 24.0), 20, r)])
	for id in Reach.LANDMARKS:
		var sid := String(id)
		var name := String(Reach.LANDMARKS[id]["name"])
		var c := to_map(Reach.LANDMARKS[id]["pos"])
		var half := reach_sticker_size(sid) * 0.5
		var above := Vector2(c.x, c.y - half - REACH_LABEL_GAP)
		var below := Vector2(c.x, c.y + half + 20.0)
		var sh := Vector2(REACH_LABEL_SHIFT, 0.0)
		var pick := above
		for cand in [above, below, above + sh, above - sh, below + sh, below - sh]:
			var lr := _label_rect(f, name, cand, REACH_LABEL_SIZE, r)
			var free := true
			for b in blocks:
				if String(b[0]) != sid and lr.intersects(b[1]):
					free = false
					break
			if free:
				pick = cand
				break
		_label_at[sid] = pick
		blocks.append([sid, _label_rect(f, name, pick, REACH_LABEL_SIZE, r)])


## Screen boxes of everything static on the Reach map at the current size (tests check overlaps):
## [{"id", "kind": "sticker" | "label" | "arch" | "waygate", "rect": Rect2}]. `all` = as if every landmark were
## discovered and every arch visible.
func reach_boxes(all: bool = false) -> Array:
	var out: Array = []
	var r := map_rect()
	var f := ThemeFactory.font("heading")
	for id in Reach.LANDMARKS:
		if not all and not GameState.is_discovered(REACH_ID, String(id)):
			continue
		out.append({"id": id, "kind": "sticker", "rect": _sticker_rect(String(id))})
		out.append({"id": id, "kind": "label", "rect": _label_rect(f, String(Reach.LANDMARKS[id]["name"]),
			reach_label_at(String(id)), REACH_LABEL_SIZE, r)})
	for aid in (Reach.ARCH_ORDER if all else visible_arches()):
		out.append({"id": aid, "kind": "arch", "rect": _pin_rect(to_map(Reach.ARCHES[aid]["pos"]), 1.0)})
	var wg := to_map(Reach.POINTS[REACH_WAYGATE])
	out.append({"id": REACH_WAYGATE, "kind": "waygate", "rect": _pin_rect(wg, WAYGATE_PIN_K)})
	out.append({"id": REACH_WAYGATE, "kind": "label", "rect": _label_rect(f, REACH_WAYGATE_NAME, Vector2(wg.x, wg.y - 24.0), 20, r)})
	return out


## Where _name_label puts a name (baseline `at`, centred, clamped inside the map): its ink box.
func _label_rect(f: Font, name: String, at: Vector2, fs: int, r: Rect2) -> Rect2:
	var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := clampf(at.x - tw * 0.5, r.position.x + 20.0, r.end.x - tw - 20.0)
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	return Rect2(Vector2(x, at.y - asc), Vector2(tw, asc + desc))


## True when REACH_PATHS[i] is drawn as a dashed footpath: both ends discovered and no festival road drawn in
## its place.
func footpath_shown(i: int) -> bool:
	if i < REACH_PATH_ROADS.size() and _route_ids.has(REACH_PATH_ROADS[i]):
		return false
	return _reach_path_known(REACH_PATHS[i])


func _reach_path_known(path: Array) -> bool:
	for node in path:
		var id := String(node)
		if Reach.LANDMARKS.has(id) and not _discovered.has(id):
			return false
	return true


func _reach_point(id: String) -> Vector2:
	if Reach.LANDMARKS.has(id):
		return Reach.LANDMARKS[id]["pos"]
	return Reach.POINTS.get(id, Vector2.ZERO)


func _unknown_pin(c: Vector2, f: Font) -> void:
	draw_circle(c + Vector2(1.5, 2.5), UNKNOWN_PIN_R, Color(0.2, 0.1, 0.1, 0.25), true, -1.0, true)
	draw_circle(c, UNKNOWN_PIN_R, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
	draw_arc(c, UNKNOWN_PIN_R, 0.0, TAU, 24, ThemeFactory.ACCENT.darkened(0.2), 3.0, true)
	var tw := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(f, c + Vector2(-tw * 0.5, 9.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ThemeFactory.INK)


# --- Mastery pins and the Bramblewatch name ------------------------------------------------------------------

## Resource pins (under every sticker and name) and cache hints, each only inside the map rectangle.
func _draw_mastery_pins(r: Rect2) -> void:
	for pin in resource_pins:
		var c := to_map(pin[0])
		if r.grow(-PIN_R).has_point(c):
			var item := String(pin[2])
			draw_spot_pin(self, c, 1.0, IconFactory.item_icon(item, 48) if item != "" else null)
	for hp in cache_hint_points:
		var hc := to_map(hp)
		if r.grow(-HINT_R).has_point(hc):
			draw_hint_pin(self, hc, 1.0)


## Screen boxes of the woods map's stickers, names and the waygate pin (+ its name when shown): [[id, Rect2]].
func surface_blocks() -> Array:
	var out: Array = []
	var r := map_rect()
	var f := ThemeFactory.font("heading")
	for id in Layout.LANDMARKS:
		var c := to_map(Layout.LANDMARKS[id]["pos"])
		var isz := 58.0 if id == "haven" else 50.0
		out.append([String(id), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz))])
		out.append([String(id), _label_rect(f, String(Layout.LANDMARKS[id]["name"]), Vector2(c.x, c.y + isz * 0.5 + 18.0),
			22 if id != "haven" else 24, r)])
	if surface_waygate_visible() and Layout.CH2_POINTS.has("waygate"):
		var wc := to_map(Layout.CH2_POINTS["waygate"])
		out.append([WAYGATE_ID, _pin_rect(wc, 1.35)])
		out.append([WAYGATE_ID, _label_rect(f, WAYGATE_NAME, Vector2(wc.x, wc.y - 24.0), 20, r)])
	return out


## Baseline centre of the Bramblewatch name: the first candidate (above its marker, below, beside, then shifted)
## whose ink box stays inside the map and clears its marker, every sticker, name and the waygate. Cached per
## control size.
func bramblewatch_label_at() -> Vector2:
	if _bramble_size == size:
		return _bramble_label
	_bramble_size = size
	_bramble_label = Vector2.ZERO
	if not (bramblewatch_at is Vector2):
		return _bramble_label
	var r := map_rect()
	var f := ThemeFactory.font("heading")
	var c := to_map(bramblewatch_at)
	var tw := f.get_string_size(BRAMBLEWATCH_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, BRAMBLEWATCH_LABEL_SIZE).x
	var above := Vector2(c.x, c.y - 14.0)
	var below := Vector2(c.x, c.y + 28.0)
	var side := tw * 0.5 + 14.0
	var cands := [above, below, below + Vector2(0, 8), below + Vector2(0, 16), Vector2(c.x - side, c.y + 7.0),
		Vector2(c.x + side, c.y + 7.0), above - Vector2(side, 0), above + Vector2(side, 0), below - Vector2(side, 0),
		below + Vector2(side, 0), above - Vector2(0, 16), below + Vector2(side, 16), below - Vector2(side, 16)]
	var blocks := surface_blocks()
	var marker := bramblewatch_marker_rect()
	_bramble_label = above
	for cand in cands:
		var lr := _label_rect(f, BRAMBLEWATCH_NAME, cand, BRAMBLEWATCH_LABEL_SIZE, r)
		var free := r.grow(-12.0).encloses(lr) and not lr.intersects(marker)
		if free:
			for b in blocks:
				if lr.intersects(b[1]):
					free = false
					break
		if free:
			_bramble_label = cand
			break
	return _bramble_label


## Screen box of the little Bramblewatch marker (empty while it is not shown).
func bramblewatch_marker_rect() -> Rect2:
	if not (bramblewatch_at is Vector2):
		return Rect2()
	return Rect2(to_map(bramblewatch_at) - Vector2(9, 9), Vector2(18, 18))


## Ink box of the Bramblewatch name (tests: overlap checks).
func bramblewatch_label_rect() -> Rect2:
	if not (bramblewatch_at is Vector2):
		return Rect2()
	return _label_rect(ThemeFactory.font("heading"), BRAMBLEWATCH_NAME, bramblewatch_label_at(), BRAMBLEWATCH_LABEL_SIZE, map_rect())


# --- Shared drawing ------------------------------------------------------------------------------------

func _pulse(tc: Vector2) -> void:
	for k in 2:
		var ph := fmod(_t * 0.7 + float(k) * 0.5, 1.0)
		var rr := 26.0 + ph * 34.0
		draw_arc(tc, rr, 0.0, TAU, 48, Color(ThemeFactory.ACCENT, 0.85 * (1.0 - ph)), 4.0, true)
	if pins_upgraded and not _star.is_empty():
		# "The Long Way Home": a steady gold ring and a little star badge (no flashing, just a slow glint)
		draw_arc(tc, 30.0, 0.0, TAU, 48, ThemeFactory.GOLD.darkened(0.1), 3.0, true)
		var glint := 0.85 + 0.15 * sin(_t * 1.6)
		draw_set_transform(tc + Vector2(26.0, -26.0))
		draw_circle(Vector2.ZERO, 12.0, Color(ThemeFactory.PAPER_LIGHT, 0.95), true, -1.0, true)
		draw_colored_polygon(_star, Color(ThemeFactory.GOLD, glint))
		draw_polyline(_star_outline, ThemeFactory.INK, 1.6, true)
		draw_set_transform(Vector2.ZERO)


func _name_label(f: Font, name: String, at: Vector2, fs: int, r: Rect2) -> void:
	var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lp := Vector2(at.x - tw * 0.5, at.y)
	lp.x = clampf(lp.x, r.position.x + 20.0, r.end.x - tw - 20.0)
	draw_string_outline(f, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color("f7ecd6"))
	draw_string(f, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ThemeFactory.INK)


func _forest_frame(r: Rect2, col: Color) -> void:
	var frame := ThemeFactory.box(Color(0, 0, 0, 0), 18, 16, col)
	frame.draw_center = false
	draw_style_box(frame, r)
	var perim := r.grow(-16.0)
	var step := 26.0
	var x := perim.position.x
	while x <= perim.end.x:
		draw_circle(Vector2(x, perim.position.y), 10.0, col, true, -1.0, true)
		draw_circle(Vector2(x, perim.end.y), 10.0, col, true, -1.0, true)
		x += step
	var y := perim.position.y
	while y <= perim.end.y:
		draw_circle(Vector2(perim.position.x, y), 10.0, col, true, -1.0, true)
		draw_circle(Vector2(perim.end.x, y), 10.0, col, true, -1.0, true)
		y += step


func _draw_friends(r: Rect2) -> void:
	if not show_player:
		return
	for cid in Game.companion_nodes:
		var cn: Variant = Game.companion_nodes[cid]
		if cn is Node3D and is_instance_valid(cn):
			var p3: Vector3 = (cn as Node3D).global_position
			var cpos := _clamp_in(to_map(Vector2(p3.x, p3.z)), r)
			draw_circle(cpos, 13.0, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
			draw_texture_rect(IconFactory.portrait(String(cid)), Rect2(cpos - Vector2(12, 12), Vector2(24, 24)), false)
			draw_arc(cpos, 13.0, 0.0, TAU, 24, ThemeFactory.INK, 2.0, true)


func _draw_player(r: Rect2) -> void:
	if show_player and Game.player != null and is_instance_valid(Game.player) and Game.player is Node3D:
		var pp: Vector3 = (Game.player as Node3D).global_position
		var mp := _clamp_in(to_map(Vector2(pp.x, pp.z)), r)
		var ang := UiUtil.map_heading(_facing())
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(mp, 20.0 + pulse * 4.0, Color(Palette.K_JACKET, 0.22), true, -1.0, true)
		draw_arrow(mp, ang)


func _compass(r: Rect2, f: Font) -> void:
	var cc2 := Vector2(r.end.x - 52.0, r.position.y + 58.0)
	draw_circle(cc2, 30.0, Color(ThemeFactory.PAPER_LIGHT, 0.92), true, -1.0, true)
	draw_arc(cc2, 30.0, 0.0, TAU, 32, ThemeFactory.INK, 2.5, true)
	draw_colored_polygon(PackedVector2Array([cc2 + Vector2(0, -24), cc2 + Vector2(8, 2), cc2 + Vector2(-8, 2)]), ThemeFactory.ACCENT)
	draw_colored_polygon(PackedVector2Array([cc2 + Vector2(0, 24), cc2 + Vector2(8, 2), cc2 + Vector2(-8, 2)]), ThemeFactory.INK_SOFT)
	draw_string(f, cc2 + Vector2(-8, -34), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ThemeFactory.INK)


func draw_arrow(pos: Vector2, ang: float) -> void:
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var tip := pos + fwd * 20.0
	var back := pos - fwd * 12.0
	var pts := PackedVector2Array([tip, pos - fwd * 8.0 + right * 13.0, back, pos - fwd * 8.0 - right * 13.0])
	var outline := PackedVector2Array([tip, pos - fwd * 8.0 + right * 13.0, back, pos - fwd * 8.0 - right * 13.0, tip])
	draw_colored_polygon(pts, Palette.K_JACKET)
	draw_polyline(outline, ThemeFactory.INK, 3.0, true)
	draw_circle(pos, 3.0, ThemeFactory.CREAM, true, -1.0, true)


func _facing() -> Vector3:
	var pl: Node = Game.player
	if pl != null and pl.has_method("get_camera"):
		var cam: Variant = pl.get_camera()
		if cam is Camera3D and is_instance_valid(cam):
			return -(cam as Camera3D).global_transform.basis.z
	var vp := get_viewport()
	if vp != null and vp.get_camera_3d() != null:
		return -vp.get_camera_3d().global_transform.basis.z
	if pl is Node3D:
		return -(pl as Node3D).global_transform.basis.z
	return Vector3.FORWARD


func _clamp_in(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x + 18.0, r.end.x - 18.0), clampf(p.y, r.position.y + 18.0, r.end.y - 18.0))


func _soft_disc(c: Vector2, rad: float, col: Color) -> void:
	for i in 4:
		var k := 1.0 - float(i) * 0.16
		draw_circle(c, rad * k, Color(col, 0.28 + 0.12 * float(i)), true, -1.0, true)


func _ellipse(c: Vector2, rr: Vector2, fill: Color, line: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(a) * rr.x, sin(a) * rr.y))
	draw_colored_polygon(pts, fill)
	if line.a > 0.0:
		pts.append(pts[0])
		draw_polyline(pts, line, 3.0, true)


func _path_point(node: String) -> Vector2:
	if node.begins_with("@"):
		return Layout.STREAM_CROSSINGS[int(node.substr(1))]
	return Layout.LANDMARKS[node]["pos"]


func _near_stream(p: Vector2, d: float) -> bool:
	for i in _stream.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, _stream[i], _stream[i + 1]).distance_to(p) < d:
			return true
	var pond: Vector2 = Layout.LANDMARKS["pond"]["pos"]
	return p.distance_to(pond) < 16.0


func _in_landmark(p: Vector2, k: float) -> bool:
	for id in Layout.LANDMARKS:
		var lm: Dictionary = Layout.LANDMARKS[id]
		if p.distance_to(lm["pos"]) < float(lm["radius"]) * k + 6.0:
			return true
	return false


func _stream_dir(at: Vector2) -> Vector2:
	var best := 1e9
	var dir := Vector2.DOWN
	for i in _stream.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(at, _stream[i], _stream[i + 1])
		var d := q.distance_to(at)
		if d < best:
			best = d
			dir = (_stream[i + 1] - _stream[i]).normalized()
	return dir


static func _spline(points: Array, samples: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	if n < 2:
		return out
	for i in n - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, n - 1)]
		for s in samples:
			var t := float(s) / float(samples)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[n - 1])
	return out
