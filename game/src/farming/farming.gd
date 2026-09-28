extends RefCounted
## Farming rules (static). Crop definitions: data/structures.gd CROPS (via ItemDB.crop).
## Plot state lives in GameState.crops[plot_uid] = {"crop": id|"" , "planted_at": total_minutes,
## "tended_minutes": float}. Nodes (src/farming/crop_plot.gd) are only views over this state.
##
## Growth progress = (now - planted_at + tended_minutes) * (1.5 if flag "ward_restored") / grow_minutes
## Stages: 0 sprout, 1 leaves, 2 bushy, 3 ripe (progress >= 1).
##
## PUBLIC API FOR COMPANIONS (Mochi tends crops while at home):
##   const Farming := load("res://src/farming/farming.gd")
##   Farming.tend(plot_uid, minutes) -> bool      adds care time to a growing (not ripe) crop.
##   Farming.plots_needing_care(area_id) -> Array  uids of planted, not-yet-ripe plots in that area.
##   Farming.plot_position(plot_uid) -> Vector3     where the plot is (for walking over to it).

const STAGE_SPROUT := 0
const STAGE_LEAVES := 1
const STAGE_BUSHY := 2
const STAGE_RIPE := 3
const STAGE_NAMES := ["Sprouting", "Leafy", "Bushy", "Ripe"]
## The restored Haven's blessing (legacy, unchanged): applied at READ time from the flag, never stored in a
## record, so loading any number of times can never compound it.
const WARD_GROWTH_MULT := 1.5
## Optional-goal flags set by a real harvest (data/optional_goals.gd): "A Gardener's Afternoon" (grow and harvest
## a sunflax or roseberry crop at home) and "A Pumpkin With a Face" (grow and harvest a pumpkin).
const HARVEST_FLAGS := {"sunflax": "c1x_grew_new_crop", "roseberry": "c1x_grew_new_crop", "pumpkin": "ch2_pumpkin_harvested"}


static func record(uid: String) -> Dictionary:
	var r: Variant = GameState.crops.get(uid)
	return r if r is Dictionary else {}


static func is_plot(uid: String) -> bool:
	return GameState.crops.has(uid) and GameState.structures.has(uid)


static func is_planted(uid: String) -> bool:
	return String(record(uid).get("crop", "")) != ""


static func crop_id(uid: String) -> String:
	return String(record(uid).get("crop", ""))


static func growth_mult() -> float:
	return WARD_GROWTH_MULT if bool(GameState.get_flag("ward_restored")) else 1.0


static func grow_minutes(crop: String) -> float:
	return maxf(float(ItemDB.crop(crop).get("grow_minutes", 360.0)), 1.0)


## 0..1 growth progress (0 for empty plots).
static func progress(uid: String) -> float:
	var r := record(uid)
	var crop: String = String(r.get("crop", ""))
	if crop == "":
		return 0.0
	var elapsed: float = GameState.total_minutes - float(r.get("planted_at", GameState.total_minutes)) + float(r.get("tended_minutes", 0.0))
	return clampf(maxf(elapsed, 0.0) * growth_mult() / grow_minutes(crop), 0.0, 1.0)


## -1 = empty, else STAGE_SPROUT..STAGE_RIPE.
static func stage(uid: String) -> int:
	if not is_planted(uid):
		return -1
	return stage_for_progress(progress(uid))


static func stage_for_progress(p: float) -> int:
	if p >= 1.0:
		return STAGE_RIPE
	return clampi(int(floorf(p * 3.0)), STAGE_SPROUT, STAGE_BUSHY)


static func is_ripe(uid: String) -> bool:
	return stage(uid) == STAGE_RIPE


static func stage_name(st: int) -> String:
	return STAGE_NAMES[st] if st >= 0 and st < STAGE_NAMES.size() else "Empty"


## In-game minutes until ripe at the current growth rate (0 when ripe/empty).
static func minutes_remaining(uid: String) -> float:
	var crop := crop_id(uid)
	if crop == "":
		return 0.0
	return (1.0 - progress(uid)) * grow_minutes(crop) / growth_mult()


## "2h 10m" / "45m" / "a moment".
static func format_minutes(m: float) -> String:
	var total := int(ceilf(m))
	if total <= 0:
		return "a moment"
	var h := total / 60
	var mm := total % 60
	if h <= 0:
		return "%dm" % mm
	if mm == 0:
		return "%dh" % h
	return "%dh %dm" % [h, mm]


## The main produce item of a crop: the first yield entry that isn't its seed ("sweetroot", "roseberries"...).
static func produce_item(crop: String) -> String:
	var def := ItemDB.crop(crop)
	var seed_item := String(def.get("seed", ""))
	var y: Dictionary = def.get("yield", {})
	if y.has(crop):
		return crop
	for item in y:
		if String(item) != seed_item:
			return String(item)
	return crop


## Seed item id -> crop id ("" if the item is not a plantable seed).
static func crop_for_seed(item_id: String) -> String:
	if not ItemDB.has_item(item_id):
		return ""
	var c: String = String(ItemDB.item(item_id).get("crop", ""))
	return c if c != "" and not ItemDB.crop(c).is_empty() else ""


## The seed the player would plant: the selected hotbar item if it is a seed, else the first seed
## found in the backpack. "" if the player has none.
static func choose_seed() -> String:
	var sel: Variant = GameState.selected_slot()
	if sel is Dictionary and crop_for_seed(String(sel.get("id", ""))) != "":
		return String(sel["id"])
	for s in GameState.inventory.slots:
		if s != null and crop_for_seed(String(s["id"])) != "":
			return String(s["id"])
	return ""


## Plants one seed in an empty plot. Returns true on success.
static func plant(uid: String, seed_item: String = "", sound_pos: Variant = null) -> bool:
	if not GameState.crops.has(uid) or is_planted(uid):
		return false
	if seed_item == "":
		seed_item = choose_seed()
	var crop := crop_for_seed(seed_item)
	if crop == "":
		return false
	if not GameState.take_item(seed_item, 1):
		return false
	GameState.crops[uid] = {"crop": crop, "planted_at": GameState.total_minutes, "tended_minutes": 0.0}
	GameState.add_counter("crops_planted")
	Events.crop_planted.emit(uid, crop)
	_sound("dig", sound_pos)
	return true


## Rolls the harvest for a crop: {item_id: count}. rng optional (tests).
static func roll_yield(crop: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var out := {}
	var y: Dictionary = ItemDB.crop(crop).get("yield", {})
	for item in y:
		var range_v: Variant = y[item]
		var lo := 1
		var hi := 1
		if range_v is Array and range_v.size() >= 2:
			lo = int(range_v[0])
			hi = int(range_v[1])
		elif range_v is int or range_v is float:
			lo = int(range_v)
			hi = lo
		var n: int = rng.randi_range(lo, hi) if rng != null else randi_range(lo, hi)
		if n > 0:
			out[item] = n
	return out


## Harvests a ripe plot: gives the yield (overflow drops as pickups), resets the plot.
## Returns the items given ({} if nothing was harvested).
static func harvest(uid: String, drop_pos: Variant = null, rng: RandomNumberGenerator = null) -> Dictionary:
	if not is_ripe(uid):
		return {}
	var crop := crop_id(uid)
	var got := roll_yield(crop, rng)
	GameState.crops[uid] = {"crop": "", "planted_at": 0.0, "tended_minutes": 0.0}
	for item in got:
		GameState.give_item(String(item), int(got[item]), drop_pos)
	# The crop's produce (e.g. "sweetroot", "roseberries") is the headline count for listeners.
	var main_count: int = int(got.get(produce_item(crop), 0))
	GameState.add_counter("crops_harvested")
	if HARVEST_FLAGS.has(crop):
		GameState.set_flag(String(HARVEST_FLAGS[crop]), true)
	Events.crop_harvested.emit(uid, crop, main_count)
	_sound("harvest_crop", drop_pos)
	return got


## COMPANION HOOK: adds `minutes` of care to a planted crop that is still growing.
## Returns true if it helped (false for empty, ripe or unknown plots, or minutes <= 0).
static func tend(uid: String, minutes: float) -> bool:
	if minutes <= 0.0 or not GameState.crops.has(uid) or not is_planted(uid) or is_ripe(uid):
		return false
	var r: Dictionary = GameState.crops[uid]
	r["tended_minutes"] = float(r.get("tended_minutes", 0.0)) + minutes
	return true


## Planted plots that are still growing (optionally only in `area_id`).
static func plots_needing_care(area_id: String = "surface") -> Array:
	var out: Array = []
	for uid in GameState.crops:
		if not GameState.structures.has(uid):
			continue
		if area_id != "" and String(GameState.structures[uid].get("area", "surface")) != area_id:
			continue
		if is_planted(uid) and not is_ripe(uid):
			out.append(uid)
	return out


## Ripe plots (for companions to "point at", UI markers...).
static func ripe_plots(area_id: String = "surface") -> Array:
	var out: Array = []
	for uid in GameState.crops:
		if GameState.structures.has(uid) and (area_id == "" or String(GameState.structures[uid].get("area", "surface")) == area_id) and is_ripe(uid):
			out.append(uid)
	return out


static func plot_position(uid: String) -> Vector3:
	var s: Variant = GameState.structures.get(uid)
	if s is Dictionary:
		var p: Variant = s.get("pos")
		if p is Array and p.size() == 3:
			return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.ZERO


static func _sound(name: String, pos: Variant) -> void:
	if pos is Vector3:
		Audio.play_3d(name, pos)
	else:
		Audio.play_sfx(name)
