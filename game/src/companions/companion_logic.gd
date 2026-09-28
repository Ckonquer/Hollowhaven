extends RefCounted
## Pure decision logic for the companions. No scene access: everything here takes plain values
## and returns plain values so it can be unit tested (tests/unit/test_companions_*.gd).
##   const Logic := preload("res://src/companions/companion_logic.gd")

const Reach := preload("res://data/hallowmere_layout.gd")

const ORDER := ["mochi", "pebble", "lumi"]
const SURFACE_AREAS := ["surface", "arena"]    # areas that have homes / wild spots / the threshold
## Area classes (docs/CHAPTER_TWO_SPEC.md §9 "Underground vs outdoor"). The Haven areas above keep every legacy
## rule (homes, wild spots, the mine threshold). Outdoor and interior areas take the follower along (Mochi
## too) plus anyone told to wait there; underground areas only take a follower that dares (Mochi needs
## courage). Unknown ids stay "underground": the legacy default for dungeon-like areas.
const OUTDOOR_AREAS := ["hallowmere_reach"]
const INTERIOR_AREAS := ["moonveil_manor", "echo_trial"]
const UNDERGROUND_AREAS := ["below", "tobin_annex", "hushed_works"]
## Where a timid follower waits when Krystal goes underground without it: the doorstep of that area, in the
## area it is entered from. "threshold": the surface mine threshold (Tobin's side door and hatch are at the
## same mine mouth); otherwise a fixed point of that outer area (grounded when spawned). "arrivals": arriving
## at one of these spawns of the outer area while the companion waits at the doorstep reunites it.
## "entries" {inner spawn: {"spawn", "arrivals"}}: entered through another door (the arrival spawn inside), the
## companion waits at THAT door instead (where Krystal left it), e.g. the Works' refuge shortcut hatch.
const SURFACE_REUNITE_ARRIVALS := ["mine_exit", "annex_door", "annex_hatch"]
const DOORSTEPS := {
	"below": {"area": "surface", "threshold": true},
	"tobin_annex": {"area": "surface", "threshold": true},
	"hushed_works": {"area": "hallowmere_reach", "spawn": "bellhouse_stair", "arrivals": ["bellhouse_stair"],
		"entries": {"refuge": {"spawn": "refuge_exit", "arrivals": ["refuge_exit"]}}},
}

const PET_BOND := 5
const FEED_BOND := 8
const WORK_BOND := 1
const WORK_BOND_DAILY_MAX := 5
const ZONE_BOND := 3

const STUCK_FAR := 20.0            # farther than this from Krystal -> recover immediately
const STUCK_SECONDS := 4.0         # no progress for this long while following -> recover
const STUCK_PROGRESS := 0.5        # metres of improvement that count as progress
const NO_LOS_SECONDS := 7.0        # can't see Krystal this long while near -> recover
const REFUSE_RADIUS := 8.0         # Mochi refuses when Krystal gets this close to the mine threshold
const REFUSE_RESET_RADIUS := 14.0  # ...and may refuse again once Krystal has walked this far away
const THRESHOLD_MATCH := 6.0       # a wait spot this close to the threshold counts as "at the threshold"
const PINNED_BOULDER_ID := "pebble_boulder"


## True for the Haven areas (homes, wild spots, the mine threshold). Hallowmere Reach is outdoor but has no
## homes: see area_class() / is_outdoor_area().
static func is_surface_area(area_id: String) -> bool:
	return SURFACE_AREAS.has(area_id)


## "haven" | "outdoor" | "interior" | "underground" (see the constants above).
static func area_class(area_id: String) -> String:
	if SURFACE_AREAS.has(area_id):
		return "haven"
	if OUTDOOR_AREAS.has(area_id):
		return "outdoor"
	if INTERIOR_AREAS.has(area_id):
		return "interior"
	return "underground"


## Open sky: the Haven woods and Hallowmere Reach (Mochi always comes along).
static func is_outdoor_area(area_id: String) -> bool:
	var c := area_class(area_id)
	return c == "haven" or c == "outdoor"


static func is_underground_area(area_id: String) -> bool:
	return area_class(area_id) == "underground"


## Whether a creature follows Krystal underground: brave by nature (enters_below) or, for Mochi, once
## Brave Little Steps gave it courage.
static func dares_underground(def: Dictionary, courage: bool) -> bool:
	return bool(def.get("enters_below", false)) or courage


## Where a timid follower waits when Krystal enters `area_id` without it: {"area", "pos": Vector3|null}.
## `threshold` is the surface mine threshold (or null); `reach_doorsteps` optional {spawn id: Vector3}
## overrides for the fixed outer points (else data/hallowmere_layout.gd SPAWNS, y = 0). `entry_spawn`: the
## spawn Krystal arrives at inside `area_id` (another door of it may have its own doorstep, "entries").
static func doorstep(area_id: String, threshold: Variant, reach_doorsteps: Dictionary = {}, entry_spawn: String = "") -> Dictionary:
	var d: Dictionary = DOORSTEPS.get(area_id, {"area": "surface", "threshold": true})
	if bool(d.get("threshold", false)):
		return {"area": String(d.get("area", "surface")), "pos": threshold if threshold is Vector3 else null}
	var sp := String(d.get("spawn", ""))
	var entries: Dictionary = d.get("entries", {})
	if entry_spawn != "" and entries.get(entry_spawn) is Dictionary:
		sp = String((entries[entry_spawn] as Dictionary).get("spawn", sp))
	var p: Variant = reach_doorsteps.get(sp)
	if not (p is Vector3):
		var s: Dictionary = Reach.SPAWNS.get(sp, {})
		var v: Variant = s.get("pos")
		p = Vector3(v.x, 0.0, v.y) if v is Vector2 else null
	return {"area": String(d.get("area", "surface")), "pos": p}


## Doorsteps that lie in `area_id` (an outer area): [{"pos": Vector3, "arrivals": [spawn ids]}].
static func doorsteps_in(area_id: String, reach_doorsteps: Dictionary = {}) -> Array:
	var out: Array = []
	for inner in DOORSTEPS:
		var d: Dictionary = DOORSTEPS[inner]
		if String(d.get("area", "")) != area_id or bool(d.get("threshold", false)):
			continue
		var ds := doorstep(String(inner), null, reach_doorsteps)
		if ds["pos"] is Vector3:
			out.append({"pos": ds["pos"], "arrivals": d.get("arrivals", [])})
		var entries: Dictionary = d.get("entries", {})
		for en in entries:
			var de := doorstep(String(inner), null, reach_doorsteps, String(en))
			if de["pos"] is Vector3:
				out.append({"pos": de["pos"], "arrivals": (entries[en] as Dictionary).get("arrivals", [])})
	return out


## Spawn ids of the doorsteps that lie in `area_id` (main door + other entries), for the spawner to resolve.
static func doorstep_spawns_in(area_id: String) -> Array:
	var out: Array = []
	for inner in DOORSTEPS:
		var d: Dictionary = DOORSTEPS[inner]
		if String(d.get("area", "")) != area_id or bool(d.get("threshold", false)):
			continue
		if d.has("spawn"):
			out.append(String(d["spawn"]))
		var entries: Dictionary = d.get("entries", {})
		for en in entries:
			var s := String((entries[en] as Dictionary).get("spawn", ""))
			if s != "" and not out.has(s):
				out.append(s)
	return out


static func vec_from(v: Variant) -> Variant:
	if v is Vector3:
		return v
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return null


# --- Spawning ---------------------------------------------------------------------------------------

## Decides which companions appear in an area, how, and which GameState changes that implies.
## records: id -> companion record (GameState.companions). active: current follower id.
## arrival_spawn: spawn id Krystal arrived at. defs: id -> creature definition (ItemDB.creature).
## boulder_gone: GameState.is_depleted("pebble_boulder"). threshold: mine threshold position or null.
## Returns {"spawns": [{"id", "mode", "pos"?}], "changes": [{"id", "assignment", "wait_area", "wait_pos"}], "boulder": bool}
## Modes: wild | pinned | home | wait | follow | reunite (rejoins as follower) | reunite_home
## Area classes (area_class): the Haven keeps every rule above. Outdoor / interior areas (Hallowmere Reach,
## the manor, trials): the follower comes along whoever it is, companions told to wait there reappear at
## their spot (one waiting at a doorstep reunites when Krystal comes back up through it), nobody lives
## there. Underground: only a follower that dares (defs[id].enters_below; the spawner passes true for Mochi
## once she has courage); a timid one waits at that area's doorstep in the outer area instead (the surface
## mine threshold for the Below and Tobin's annex, the Bellhouse stair in the Reach for the Hushed Works).
## `reach_doorsteps` (optional): {spawn id: Vector3} registered positions of the outer doorsteps.
static func plan_spawns(area_id: String, records: Dictionary, active: String, arrival_spawn: String,
		defs: Dictionary, boulder_gone: bool, threshold: Variant, reach_doorsteps: Dictionary = {}) -> Dictionary:
	var spawns: Array = []
	var changes: Array = []
	var boulder := false
	var ids: Array = []
	for id in ORDER:
		if records.has(id) or defs.has(id):
			ids.append(id)
	for id in records:
		if not ids.has(id) and defs.has(id):
			ids.append(id)
	if is_surface_area(area_id):
		var follower := active
		# A follower that is not befriended (corrupt data) is ignored.
		if follower != "" and not bool(records.get(follower, {}).get("befriended", false)):
			follower = ""
		for id in ids:
			var rec: Dictionary = records.get(id, {})
			if not bool(rec.get("befriended", false)):
				if id == "pebble" and not boulder_gone:
					boulder = true
					spawns.append({"id": id, "mode": "pinned"})
				else:
					spawns.append({"id": id, "mode": "wild"})
				continue
			var assignment := String(rec.get("assignment", "home"))
			if assignment == "follow" and follower == id:
				spawns.append({"id": id, "mode": "follow"})
				continue
			if assignment == "follow" and follower != id:
				changes.append({"id": id, "assignment": "home"})
				spawns.append({"id": id, "mode": "home"})
				continue
			if assignment == "wait":
				var wp: Variant = vec_from(rec.get("wait_pos"))
				if String(rec.get("wait_area", "")) == area_id and wp != null:
					var at_threshold := threshold is Vector3 and _flat_dist(wp, threshold) <= THRESHOLD_MATCH
					if at_threshold and SURFACE_REUNITE_ARRIVALS.has(arrival_spawn):
						if follower == "":
							follower = id
							changes.append({"id": id, "assignment": "follow"})
							spawns.append({"id": id, "mode": "reunite", "pos": wp})
						else:
							changes.append({"id": id, "assignment": "home"})
							spawns.append({"id": id, "mode": "reunite_home", "pos": wp})
					else:
						spawns.append({"id": id, "mode": "wait", "pos": wp})
					continue
				# Waiting somewhere that isn't this area: it found its way home safely.
				changes.append({"id": id, "assignment": "home"})
				spawns.append({"id": id, "mode": "home"})
				continue
			if assignment != "home":
				changes.append({"id": id, "assignment": "home"})
			spawns.append({"id": id, "mode": "home"})
	elif area_class(area_id) == "underground":
		# The Below (and any other dungeon-like area): only the follower, and only if it dares.
		if active != "" and bool(records.get(active, {}).get("befriended", false)):
			var def: Dictionary = defs.get(active, {})
			if bool(def.get("enters_below", false)):
				spawns.append({"id": active, "mode": "follow"})
			else:
				var ds := doorstep(area_id, threshold, reach_doorsteps, arrival_spawn)
				changes.append({"id": active, "assignment": "wait", "wait_area": String(ds["area"]), "wait_pos": ds["pos"]})
		# ...plus anyone Krystal told to wait down here (e.g. after continuing from a lantern save):
		# they are still where she left them, never silently gone.
		for id in ids:
			if id == active:
				continue
			var wrec: Dictionary = records.get(id, {})
			if not bool(wrec.get("befriended", false)) or String(wrec.get("assignment", "")) != "wait":
				continue
			if String(wrec.get("wait_area", "")) != area_id or not bool(defs.get(id, {}).get("enters_below", false)):
				continue
			var wpos: Variant = vec_from(wrec.get("wait_pos"))
			if wpos != null:
				spawns.append({"id": id, "mode": "wait", "pos": wpos})
	else:
		# Outdoor (Hallowmere Reach) and interiors: the follower comes along, whoever it is.
		var follower := active
		if follower != "" and not bool(records.get(follower, {}).get("befriended", false)):
			follower = ""
		if follower != "":
			spawns.append({"id": follower, "mode": "follow"})
		var steps := doorsteps_in(area_id, reach_doorsteps)
		for id in ids:
			if id == follower:
				continue
			var wrec: Dictionary = records.get(id, {})
			if not bool(wrec.get("befriended", false)) or String(wrec.get("assignment", "")) != "wait":
				continue
			if String(wrec.get("wait_area", "")) != area_id:
				continue
			var wpos: Variant = vec_from(wrec.get("wait_pos"))
			if wpos == null:
				continue
			var reunite := false
			for st in steps:
				if (st["arrivals"] as Array).has(arrival_spawn) and _flat_dist(wpos, st["pos"]) <= THRESHOLD_MATCH:
					reunite = true
			if reunite and follower == "":
				follower = id
				changes.append({"id": id, "assignment": "follow"})
				spawns.append({"id": id, "mode": "reunite", "pos": wpos})
			elif reunite:
				# Someone else is following: it heads home to the Haven, happily (nobody lives out here).
				changes.append({"id": id, "assignment": "home"})
			else:
				spawns.append({"id": id, "mode": "wait", "pos": wpos})
	return {"spawns": spawns, "changes": changes, "boulder": boulder}


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Bond --------------------------------------------------------------------------------------------

## Petting: bond xp to grant today (PET_BOND once per in-game day, else 0). Marks the record.
static func pet_bond(rec: Dictionary, day: int) -> int:
	if int(rec.get("last_pet_day", -1)) == day:
		return 0
	rec["last_pet_day"] = day
	return PET_BOND


## Feeding check: "ok" | "full" (already fed today) | "no_food".
static func feed_check(rec: Dictionary, day: int, has_food: bool) -> String:
	if int(rec.get("last_fed_day", -1)) == day:
		return "full"
	if not has_food:
		return "no_food"
	return "ok"


## Marks the record as fed today and returns the bond xp to grant.
static func feed_bond(rec: Dictionary, day: int) -> int:
	if int(rec.get("last_fed_day", -1)) == day:
		return 0
	rec["last_fed_day"] = day
	return FEED_BOND


## Working together (forage / mining assists): +1 per assist, at most WORK_BOND_DAILY_MAX per day.
static func work_bond(rec: Dictionary, day: int) -> int:
	if int(rec.get("work_day", -1)) != day:
		rec["work_day"] = day
		rec["work_xp"] = 0
	if int(rec.get("work_xp", 0)) >= WORK_BOND_DAILY_MAX:
		return 0
	rec["work_xp"] = int(rec.get("work_xp", 0)) + WORK_BOND
	return WORK_BOND


## Entering a zone together for the first time: +ZONE_BOND once per zone id.
static func zone_bond(rec: Dictionary, zone_id: String) -> int:
	if zone_id == "":
		return 0
	var zv: Variant = rec.get("zones")
	var zones: Array = zv if zv is Array else []    # tolerate a damaged save value
	if zones.has(zone_id):
		return 0
	zones.append(zone_id)
	rec["zones"] = zones
	return ZONE_BOND


static func gift_due(rec: Dictionary, day: int) -> bool:
	return bool(rec.get("befriended", false)) and int(rec.get("last_gift_day", -1)) != day


# --- Mochi at the mine ---------------------------------------------------------------------------------

static func should_refuse(enters_below: bool, assignment: String, dist_to_threshold: float, refused_this_approach: bool) -> bool:
	return not enters_below and assignment == "follow" and dist_to_threshold <= REFUSE_RADIUS and not refused_this_approach


static func approach_reset(dist_to_threshold: float) -> bool:
	return dist_to_threshold > REFUSE_RESET_RADIUS


# --- Following -------------------------------------------------------------------------------------------

static func new_stuck_tracker() -> Dictionary:
	return {"best": INF, "timer": 0.0}


static func reset_stuck(tr: Dictionary) -> void:
	tr["best"] = INF
	tr["timer"] = 0.0


## Feeds one frame of the follow distance into the tracker. Returns "" (fine), "far" (recover now:
## more than STUCK_FAR away) or "stuck" (no STUCK_PROGRESS of improvement for STUCK_SECONDS while
## lagging behind).
static func stuck_update(tr: Dictionary, dist: float, delta: float, follow_distance: float) -> String:
	if dist > STUCK_FAR:
		reset_stuck(tr)
		return "far"
	if dist <= follow_distance + 1.5:
		reset_stuck(tr)
		return ""
	if dist < float(tr.get("best", INF)) - STUCK_PROGRESS:
		tr["best"] = dist
		tr["timer"] = 0.0
		return ""
	tr["timer"] = float(tr.get("timer", 0.0)) + delta
	if float(tr["timer"]) >= STUCK_SECONDS:
		reset_stuck(tr)
		return "stuck"
	return ""


## Second stuck detector: wanting to move (goal > 1 m away) but the net displacement over
## STUCK_SECONDS stays under 1 m (e.g. hopping against a wall). Returns true when stuck.
static func progress_update(tr: Dictionary, pos: Vector3, wants_move: bool, delta: float) -> bool:
	if not wants_move or not tr.has("start"):
		tr["start"] = pos
		tr["t"] = 0.0
		return false
	tr["t"] = float(tr.get("t", 0.0)) + delta
	if float(tr["t"]) < STUCK_SECONDS:
		return false
	var start: Vector3 = tr["start"]
	tr["start"] = pos
	tr["t"] = 0.0
	return _flat_dist(pos, start) < 1.0


## Third detector: no line of sight to Krystal for NO_LOS_SECONDS while she's near (e.g. the
## companion ended up on the wrong side of a thin wall). Returns true when it should recover.
static func los_update(tr: Dictionary, has_los: bool, dist: float, delta: float) -> bool:
	if has_los or dist > STUCK_FAR:
		tr["no_los"] = 0.0
		return false
	tr["no_los"] = float(tr.get("no_los", 0.0)) + delta
	if float(tr["no_los"]) >= NO_LOS_SECONDS:
		tr["no_los"] = 0.0
		return true
	return false


## Where a follower wants to stand: a little behind and beside Krystal (side = -1 left, +1 right).
static func follow_goal(player_pos: Vector3, player_fwd: Vector3, side: float, follow_distance: float) -> Vector3:
	var f := Vector3(player_fwd.x, 0.0, player_fwd.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var right := f.cross(Vector3.UP).normalized()
	return player_pos - f * follow_distance * 0.5 + right * side * follow_distance * 0.58


## Candidate follow spots around Krystal, best first: behind-beside (own side), behind-beside
## (other side), straight behind, beside, beside (other side), in front-beside. The companion uses
## the first one that Krystal can see (never a spot on the far side of a wall).
static func goal_candidates(player_pos: Vector3, player_fwd: Vector3, side: float, follow_distance: float) -> Array:
	var f := Vector3(player_fwd.x, 0.0, player_fwd.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var back := follow_distance * 0.5
	var lat := follow_distance * 0.58
	return [
		player_pos - f * back + r * side * lat,
		player_pos - f * back - r * side * lat,
		player_pos - f * follow_distance * 0.75,
		player_pos + r * side * lat * 1.1,
		player_pos - r * side * lat * 1.1,
		player_pos + f * back + r * side * lat,
	]


## Keeps a point out of the corridor between the camera and Krystal (so the companion never
## blocks the view). Returns the point pushed sideways to `clearance` if needed.
static func camera_safe(point: Vector3, player_pos: Vector3, cam_pos: Vector3, side: float, clearance: float = 1.1) -> Vector3:
	var a := Vector2(cam_pos.x, cam_pos.z)
	var b := Vector2(player_pos.x, player_pos.z)
	var p := Vector2(point.x, point.z)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.01:
		return point
	var t := (p - a).dot(ab) / len2
	if t < -0.1 or t > 0.92:
		return point
	var closest := a + ab * clampf(t, 0.0, 1.0)
	var off := p - closest
	var d := off.length()
	if d >= clearance:
		return point
	var n: Vector2
	if d > 0.001:
		n = off / d
	else:
		n = Vector2(-ab.y, ab.x).normalized() * (1.0 if side >= 0.0 else -1.0)
	var np := closest + n * clearance
	return Vector3(np.x, point.y, np.y)


static func in_camera_corridor(point: Vector3, player_pos: Vector3, cam_pos: Vector3, clearance: float = 1.1) -> bool:
	return camera_safe(point, player_pos, cam_pos, 1.0, clearance).distance_to(point) > 0.01


## Speed toward the follow goal: matches Krystal while she moves (never slower than her when
## lagging), sprints to catch up when far, and eases in on arrival when she stands still.
static func follow_speed(dist_to_goal: float, move_speed: float, player_speed: float) -> float:
	if dist_to_goal < 0.3 and player_speed < 0.5:
		return 0.0
	var catchup := clampf((dist_to_goal - 0.6) / 3.5, 0.0, 1.0)
	var cruise := clampf(player_speed, move_speed * 0.55, move_speed * 1.6)
	var spd := lerpf(cruise, move_speed * 1.9, catchup)
	if player_speed >= 0.5:
		return maxf(spd, player_speed * (1.0 + clampf(dist_to_goal - 0.3, 0.0, 0.3)))
	return spd * clampf(dist_to_goal / 1.2, 0.3, 1.0)


## Breadcrumbs: appends Krystal's position when she has moved at least `min_step`. Returns true if added.
static func trail_push(trail: Array, pos: Vector3, min_step: float = 0.4, max_len: int = 48) -> bool:
	if not trail.is_empty():
		var last: Vector3 = trail[trail.size() - 1]
		if last.distance_to(pos) < min_step:
			return false
	trail.append(pos)
	while trail.size() > max_len:
		trail.pop_front()
	return true


## Resumes the breadcrumb trail from the crumb nearest to the companion (crumbs pile up while it
## steers directly, so the oldest crumb may be far behind), drops everything before it (and the
## crumb itself once reached) and returns the next crumb to walk to, or null when used up.
static func trail_next(trail: Array, from: Vector3, reach: float = 0.7) -> Variant:
	if trail.is_empty():
		return null
	var best_i := -1
	var best_d := INF
	for i in trail.size():
		var c: Vector3 = trail[i]
		var d := _flat_dist(c, from) + absf(c.y - from.y) * 2.0
		if d <= best_d:
			best_d = d
			best_i = i
	var drop := best_i + (1 if best_d < reach else 0)
	for k in drop:
		trail.pop_front()
	if trail.is_empty():
		return null
	return trail[0]


## Safe-spot candidates for recovering / placing a companion near Krystal, best first:
## just behind the camera (out of view), then behind and beside Krystal.
static func placement_candidates(player_pos: Vector3, player_fwd: Vector3, cam_pos: Variant, side: float) -> Array:
	var out: Array = []
	var f := Vector3(player_fwd.x, 0.0, player_fwd.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var right := f.cross(Vector3.UP).normalized()
	if cam_pos is Vector3:
		var cp: Vector3 = cam_pos
		var cf := Vector3(player_pos.x - cp.x, 0.0, player_pos.z - cp.z)
		var cam_dist := cf.length()
		if cam_dist > 0.5 and cam_dist < 12.0:
			cf = cf / cam_dist
			var cr := cf.cross(Vector3.UP).normalized()
			var behind := Vector3(cp.x, player_pos.y, cp.z) - cf * 1.3
			out.append(behind + cr * side * 0.8)
			out.append(behind - cr * side * 0.8)
	out.append(player_pos - f * 2.0 + right * side * 1.0)
	out.append(player_pos - f * 2.0 - right * side * 1.0)
	out.append(player_pos + right * side * 1.6)
	out.append(player_pos - right * side * 1.6)
	out.append(player_pos - f * 1.1)
	return out


## True if `point` is roughly inside the camera's view cone.
static func in_view(cam_pos: Vector3, cam_fwd: Vector3, point: Vector3, half_fov_deg: float = 55.0) -> bool:
	var to := point - cam_pos
	if to.length() < 0.01:
		return true
	return cam_fwd.normalized().dot(to.normalized()) > cos(deg_to_rad(half_fov_deg))


# --- Befriending prompts ------------------------------------------------------------------------------------

## Interaction prompt for a creature that is not befriended yet.
## ctx: {"have": int (items owned), "need": int, "item_name": String, "scared": bool,
##       "ruin_cleared": bool, "pinned": bool}
static func wild_prompt(id: String, def: Dictionary, ctx: Dictionary) -> Dictionary:
	var how: Dictionary = def.get("befriend", {})
	match String(how.get("type", "")):
		"offer_item":
			if bool(ctx.get("scared", false)):
				return {"text": "It's too frightened right now", "enabled": false}
			var need := int(how.get("count", 1))
			var have := int(ctx.get("have", 0))
			var item_name := String(ctx.get("item_name", String(how.get("item", ""))))
			if have >= need:
				return {"text": "Offer %d %s" % [need, item_name], "enabled": true}
			return {"text": "Offer %d %s (%d/%d)" % [need, item_name, have, need], "enabled": false}
		"free_from_boulder":
			if bool(ctx.get("pinned", false)):
				return {"text": "Something is stuck under the boulder", "enabled": false}
			return {"text": "Help the little stone creature up", "enabled": true}
		"rescue":
			if not bool(ctx.get("ruin_cleared", false)):
				return {"text": "The little light is too frightened", "enabled": false}
			return {"text": "Reach out to the little light", "enabled": true}
	return {"text": "Say hello", "enabled": true}


# --- Combat & support (Chapter Two, MP §6) ------------------------------------------------------------------

## Seconds until a signature skill is ready. `ready_at` and `now` are on the GameState.stats.play_seconds
## timeline (it only advances while playing: pause, menus that pause and loading freeze it). Clamped to the
## skill's cooldown, so a damaged or rewound save can never lock a skill for longer than one cooldown.
static func cooldown_remaining(ready_at: float, now: float, cooldown: float) -> float:
	return clampf(ready_at - now, 0.0, maxf(cooldown, 0.0))


## Heal-over-time: the part of `total` that belongs between elapsed times `from_t` and `to_t` of a
## `duration`-second effect (linear). Summed over any tick pattern it gives exactly `total`.
static func hot_amount(total: float, duration: float, from_t: float, to_t: float) -> float:
	if duration <= 0.0:
		return total if from_t <= 0.0 and to_t >= 0.0 else 0.0
	var a := clampf(from_t / duration, 0.0, 1.0)
	var b := clampf(to_t / duration, 0.0, 1.0)
	return maxf(b - a, 0.0) * total


## Picks the basic-attack target. `cands`: [{"pos": Vector3 (feet), "engaged": bool (fighting Krystal or
## attacking her), "attacking": bool (telegraphing / striking right now), "valid": bool (alive, hittable,
## not a boss while invulnerable, not a dummy)}]. opts: "range" (attack range of this pet), "max_dy",
## "engage_radius" (from Krystal), "close" (Stay close mode: only enemies right at Krystal, within
## "close_radius"; the pet never strays farther than that), "melee" (bool: walks to its target, so no range
## check here; projectiles need the target within range of where the pet stands).
## Never a peaceful (not engaged) enemy. Prefers enemies attacking Krystal, then the one nearest to her.
## Returns the index in `cands` or -1.
static func pick_attack_target(me: Vector3, player: Vector3, cands: Array, opts: Dictionary) -> int:
	var rng := float(opts.get("range", 2.0))
	var max_dy := float(opts.get("max_dy", 1.6))
	var engage := float(opts.get("engage_radius", 12.0))
	var close := bool(opts.get("close", false))
	var close_r := float(opts.get("close_radius", 4.0))
	var melee := bool(opts.get("melee", false))
	var best := -1
	var best_score := INF
	for i in cands.size():
		var c: Dictionary = cands[i]
		if not bool(c.get("valid", false)) or not bool(c.get("engaged", false)):
			continue
		var p: Vector3 = c.get("pos", Vector3.INF)
		if p == Vector3.INF:
			continue
		var dp := _flat_dist(p, player)
		var dm := _flat_dist(p, me)
		if absf(p.y - me.y) > max_dy:
			continue
		if dp > (close_r if close else engage):
			continue
		if not melee and dm > rng:
			continue
		var score := dp + dm * 0.25 - (3.0 if bool(c.get("attacking", false)) else 0.0)
		if score < best_score:
			best_score = score
			best = i
	return best


## Whether the signature skill should cast itself. `sig`: the signature table at the current bond level.
## ctx: "hp_ratio", "missing_hp", "hot_active", "shield_active", "threats_near" (threatening enemies within
## ~6 m of Krystal), "attacking_near" (one of them telegraphing / striking), "shadow_near" (a light-fearing
## enemy threatening within the pulse radius).
##   Bloomguard: Krystal meaningfully hurt (hp <= autocast_hp_ratio) and missing at least 75% of what it
##               heals (no overheal spam), not while a heal is already running.
##   Stoneheart: a threat is right at Krystal and about to strike (or she is below half health), no shield.
##   Glimmerstep: a threat near and either a shadow enemy to expose or Krystal low (a burst to get away).
static func should_autocast(sig: Dictionary, ctx: Dictionary) -> bool:
	var hp := float(ctx.get("hp_ratio", 1.0))
	var threats := int(ctx.get("threats_near", 0))
	match String(sig.get("id", "")):
		"bloomguard":
			if bool(ctx.get("hot_active", false)):
				return false
			return hp <= float(sig.get("autocast_hp_ratio", 0.6)) and float(ctx.get("missing_hp", 0.0)) >= float(sig.get("heal", 18.0)) * 0.75
		"stoneheart":
			if bool(ctx.get("shield_active", false)) or threats <= 0:
				return false
			return bool(ctx.get("attacking_near", false)) or hp < 0.5
		"glimmerstep":
			if threats <= 0:
				return false
			return bool(ctx.get("shadow_near", false)) or hp < 0.4
	return false


## The next bond perk not reached yet: {"level", "text"} or {} when every perk is unlocked.
## `perks`: data/companion_skills.gd SKILLS[id]["perks"]; `levels`: PERK_LEVELS.
static func next_perk(perks: Dictionary, levels: Array, bond_level: int, arachno: bool = false) -> Dictionary:
	for lvl in levels:
		if int(lvl) > bond_level and perks.has(lvl):
			var p: Dictionary = perks[lvl]
			var t := String(p.get("alt_text", p.get("text", ""))) if arachno else String(p.get("text", ""))
			return {"level": int(lvl), "text": t}
	return {}
