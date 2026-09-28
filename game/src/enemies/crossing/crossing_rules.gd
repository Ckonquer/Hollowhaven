extends RefCounted
## Weaver's Crossing rematch (MP section 13.2) - the PURE rules of crossing_matron.gd: tables per horror
## intensity, phases by exposure count, sides, thread placement, pounce landings, the knockback axis, the
## route check and the minion spots. Static only (no scene needed): tests call these directly.
##   const Rules := preload("res://src/enemies/crossing/crossing_rules.gd")
## Geometry is the arena's service bridge (crossing_arena.gd): `bridge` = Rect2 of the walkable deck in
## (x, z), `rail` = |z| of the guardrails' inner face, `deck_y`. The bridge runs along X. Its two ROUTES are
## the lanes either side of the centre line: north (z < 0, side -1) and south (z > 0, side +1). Every
## line-brazier stands at the rail of one lane under its ceiling anchor (lines 0 and 2 north, line 1 south).
## Tables are [Gentle, Standard, Intense] (Settings horror_intensity 0 / 1 / 2).

# --- Encounter shape ------------------------------------------------------------------------------------
const START_SIDE := -1                     # phase 1 holds the north lane
const EXPOSURES_TARGET := 3                # data "exposures": two or three exposures + damage end it
const SCORCH_FRAC := 0.1                   # the flare that burns her off the ceiling (of max hp) ...
const SCORCH_FRAC_LATE := 0.25             # ... and after EXPOSURES_TARGET exposures: never a health sponge
const EXPOSED_MULT := 1.25                 # damage taken while exposed
const WINDOW_CAP_EXPOSED := 0.4            # one exposure window takes at most this much of her max hp
const WINDOW_CAP_STRANDED := 0.2           # a missed pounce's window, at most this much
## The core rule can't be skipped with a strong weapon (MP 13.1/13.3 "strong equipment helps but never
## bypasses the learned interaction"; 13.2 "two or three exposures"): blows alone never take her below
## HP_FLOOR[n] of her max hp while she has been exposed only n times (the flare's scorch still can). With
## [0.6, 0.25] every win needs at least two exposures; from exposure 2 on nothing holds her up.
const HP_FLOOR := [0.6, 0.25]
## Action rotation per phase ("release" happens once, only in phase 3, INSTEAD of a delayed pounce).
const ROTATION := {
	1: ["threads", "pounce", "pounce"],
	2: ["threads", "delayed", "pounce", "delayed"],
	3: ["threads", "release", "pounce", "delayed"],
}

# --- Timings [Gentle, Standard, Intense] (seconds; Settings timing_assist stretches the warnings,
#     openings and recovery beats by TIMING_ASSIST_MULT, never shortens anything) --------------------------
const TIMING_ASSIST_MULT := 1.5
const T_INTRO := 2.2
const T_CLING := [[3.0, 4.0], [2.0, 2.8], [1.4, 2.0]]      # idle between actions (Intense: less idle)
const T_THREAD_TELE := [1.4, 1.2, 1.1]                     # marks on the deck before the threads land
const T_POUNCE_TELE := [1.4, 1.3, 1.2]                     # the pounce ring (MP 1.0-1.4 s)
const T_DELAYED_TELE := [2.3, 1.9, 2.2]                    # the delayed pounce ring, total (Intense: + the feint)
const FINAL_LEAD := [0.75, 0.6, 0.55]                      # its final preparation comes this long before the drop
const FEINT_GAP := 0.4                                     # Intense: the feint's shiver (0.35 s) is over this long
                                                           # before the real final tell starts (two separate cues)
const T_DROP := [0.55, 0.45, 0.42]
const T_STRANDED := [3.5, 2.5, 2.3]                        # after a MISSED pounce (MP ~2.5 s)
const T_REBOUND := 0.9                                     # after a pounce that hit (no opening)
const T_SCORCH_FALL := 0.6
const T_EXPOSED := [7.0, 5.5, 5.0]                         # the longer opening after an exposure
const T_CLIMB := [1.6, 1.3, 1.2]
const SHIFT_SPEED := [3.2, 4.6, 5.2]                       # m/s along the ceiling (side changes)
const T_RECOVER := [1.8, 1.4, 1.2]                         # after every thread cast / release
const T_RELEASE := 1.0
const SAC_WARN := [3.6, 3.0, 2.8]
const THREAD_LIFE := [9.0, 12.0, 12.0]
const THREAD_CUT_LINGER := 1.2                             # a cut thread's stubs, then it is gone (no regrowth)
const REUSE_COOLDOWN := [8.0, 10.0, 11.0]                  # a lit line-brazier can be stoked again after this

# --- Caps [Gentle, Standard, Intense] ------------------------------------------------------------------
const THREADS_PER_CAST := [1, 2, 2]        # ONE hazard set: a new cast replaces what is left of the old one
const MINIONS := [1, 2, 2]                 # the capped release (Gentle: one slower minion)
const MINION_SPEED := [0.75, 1.0, 1.0]
const MINION_DAMAGE := [0.8, 1.0, 1.0]
const MAX_COMMITTED := 1                   # one committed attack (a pounce) at a time; none while minions live

# --- Geometry ----------------------------------------------------------------------------------------------
const POUNCE_RADIUS := 2.2                 # the marked ring = the hit test (+ HIT_BODY for her body)
const HIT_BODY := 0.15
const POUNCE_MAX_OFFSET := 1.8             # a landing forced farther than this from Krystal is not a pounce
const BRAZIER_CLEAR := 2.0                 # nothing lands on (or right beside) a line-brazier
const THREAD_CLEAR := 0.9                  # ...nor on a standing thread
const LANDING_END_INSET := 1.4             # ...nor at the very ends of the deck
const LANDING_RAIL_INSET := 1.0            # ...and always inside the rails
const PEN_HALF := 2.4                      # threads fall this far either side of the guarded brazier
const LANE_INNER := 0.4                    # a thread spans its lane from the rail to this |z| (the other lane stays open)
const KEEP_CLEAR := 2.0                    # a thread never lands within this of Krystal
const ROUTE_CELL := 0.4
const ROUTE_CLEARANCE := 0.35
const BRAZIER_SOLID := 0.6
const SAC_MIN_PLAYER_DIST := 5.0
const SAC_BRAZIER_CLEAR := 2.5
const SAC_THREAD_CLEAR := 1.2
const SAC_SEPARATION := 3.0
const PUSH_SAFE_DIST := 3.0                # tests: a knockback never leaves the walkable floor within this


static func ti(level: int) -> int:
	return clampi(level, 0, 2)


## Phase for an exposure count: 1 (none yet) -> 2 (after the first) -> 3 (after the second and on).
static func phase_for(exposures: int) -> int:
	return clampi(1 + maxi(exposures, 0), 1, 3)


## The lane she holds: north in phase 1, and she changes sides after every exposure.
static func side_for(exposures: int) -> int:
	return START_SIDE if maxi(exposures, 0) % 2 == 0 else -START_SIDE


static func side_of(p: Vector3, center_z: float = 0.0) -> int:
	return -1 if p.z < center_z else 1


## Line indices (into `line_anchors`) on `side`; all of them when that side has none (degenerate arenas).
static func lines_on_side(line_anchors: Array, side: int, center_z: float = 0.0) -> Array:
	var out: Array = []
	for i in line_anchors.size():
		if line_anchors[i] is Vector3 and side_of(line_anchors[i], center_z) == side:
			out.append(i)
	if out.is_empty():
		for i in line_anchors.size():
			out.append(i)
	return out


## The line she takes on `side`: the one farthest from Krystal (she keeps ahead of her, never behind a
## camera turn she has to make in a hurry), never `exclude` while another line exists; ties go to the
## line exposed fewer times, then the lower index. -1 when there are no lines.
static func pick_line(line_anchors: Array, side: int, from: Vector3, exclude: int = -1, exposed: Dictionary = {}, center_z: float = 0.0) -> int:
	var cands := lines_on_side(line_anchors, side, center_z)
	if cands.size() > 1 and cands.has(exclude):
		cands.erase(exclude)
	var best := -1
	var best_d := -1.0
	for i in cands:
		var d := flat(line_anchors[i], from)
		if best < 0 or d > best_d + 0.5:
			best = i
			best_d = d
		elif absf(d - best_d) <= 0.5:
			var ei := int(exposed.get(i, 0))
			var eb := int(exposed.get(best, 0))
			if ei < eb or (ei == eb and i < best):
				best = i
				best_d = maxf(d, best_d)
	return best


static func rotation(phase: int) -> Array:
	return ROTATION.get(clampi(phase, 1, 3), ROTATION[1])


## Share of max hp the flare burns off at exposure number `n` (1-based).
static func scorch_fraction(n: int) -> float:
	return SCORCH_FRAC if n <= EXPOSURES_TARGET else SCORCH_FRAC_LATE


## Timings of the delayed pounce: {"total", "final_at" (the final preparation), "feint_at" (Intense
## only: a small false shiver at the ordinary pounce time; -1 = none)}. `assist` = Settings timing_assist.
static func delayed_times(level: int, assist: bool) -> Dictionary:
	var i := ti(level)
	var m := TIMING_ASSIST_MULT if assist else 1.0
	var total := float(T_DELAYED_TELE[i]) * m
	var lead := float(FINAL_LEAD[i]) * m
	var feint := float(T_POUNCE_TELE[i]) * m if i == 2 else -1.0
	if feint >= total - lead - FEINT_GAP:
		feint = -1.0
	return {"total": total, "final_at": total - lead, "feint_at": feint}


## Weapon damage never takes her below this (absolute hp) after `exposures` exposures; 0 = no floor.
static func hp_floor(max_hp: float, exposures: int) -> float:
	if exposures < 0 or exposures >= HP_FLOOR.size():
		return 0.0
	return max_hp * float(HP_FLOOR[exposures])


# --- Geometry helpers -----------------------------------------------------------------------------------------

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.000001 else clampf(ap.dot(ab) / l2, 0.0, 1.0)
	return (ap - ab * t).length()


static func seg_closest(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.000001 else clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
	return a.lerp(b, t)


## On the deck: inside the bridge rect, between the rails, at deck height.
static func on_deck(p: Vector3, bridge: Rect2, rail: float, deck_y: float, max_dy: float = 2.0) -> bool:
	return bridge.has_point(Vector2(p.x, p.z)) and absf(p.z) <= rail and absf(p.y - deck_y) <= max_dy


static func _clamp_deck(p: Vector3, bridge: Rect2, rail: float, deck_y: float) -> Vector3:
	var zr := maxf(rail - LANDING_RAIL_INSET, 0.2)
	return Vector3(clampf(p.x, bridge.position.x + LANDING_END_INSET, bridge.end.x - LANDING_END_INSET), deck_y, clampf(p.z, -zr, zr))


# --- Threads ---------------------------------------------------------------------------------------------------

## Where one cast lands: `n` threads ACROSS the lane of `side` (from the rail to LANE_INNER, so the other
## lane always stays open), PEN_HALF either side of the guarded brazier - the one facing Krystal first. A
## thread that would land within KEEP_CLEAR of Krystal (or off the deck, or onto the brazier) is skipped.
## Returns [[a: Vector3, b: Vector3], ...] floor points.
static func thread_segments(brazier: Vector3, side: int, krystal: Vector3, n: int, bridge: Rect2, rail: float, deck_y: float) -> Array:
	var out: Array = []
	var toward := -1.0 if krystal.x < brazier.x else 1.0
	var s := float(signi(side)) if side != 0 else -1.0
	for dx in [toward * PEN_HALF, -toward * PEN_HALF]:
		if out.size() >= n:
			break
		var x := clampf(brazier.x + float(dx), bridge.position.x + 0.8, bridge.end.x - 0.8)
		if absf(x - brazier.x) < 1.4:
			continue
		var a := Vector3(x, deck_y, s * (rail - 0.05))
		var b := Vector3(x, deck_y, s * LANE_INNER)
		if seg_dist(a, b, krystal) < KEEP_CLEAR and absf(krystal.y - deck_y) < 3.0:
			continue
		out.append([a, b])
	return out


## Grid flood fill over the deck (the bridge rect between the rails): can someone at `from` still reach every
## point of `targets` (within 1.3 m) without crossing a segment of `segs` ([[a, b], ...], ROUTE_CLEARANCE
## wide) or entering a circle of `circles` ([[centre, radius], ...])? `from` outside the deck is clamped in.
static func route_ok(from: Vector3, targets: Array, bridge: Rect2, rail: float, segs: Array, circles: Array, cell: float = ROUTE_CELL) -> bool:
	var x0 := bridge.position.x
	var nx := int(ceil(bridge.size.x / cell)) + 1
	var nz := int(ceil(rail * 2.0 / cell)) + 1
	var free := PackedByteArray()
	free.resize(nx * nz)
	for j in nz:
		for i in nx:
			var p := Vector3(x0 + float(i) * cell, 0.0, -rail + float(j) * cell)
			var ok := absf(p.z) <= rail - ROUTE_CLEARANCE * 0.5
			if ok:
				for sg in segs:
					if seg_dist(sg[0], sg[1], p) <= ROUTE_CLEARANCE:
						ok = false
						break
			if ok:
				for c in circles:
					if flat(c[0], p) <= float(c[1]) + ROUTE_CLEARANCE:
						ok = false
						break
			free[j * nx + i] = 1 if ok else 0
	var fi := clampi(int(round((from.x - x0) / cell)), 0, nx - 1)
	var fj := clampi(int(round((from.z + rail) / cell)), 0, nz - 1)
	var start := -1
	var best := INF
	for dj in range(-5, 6):
		for di in range(-5, 6):
			var i := fi + di
			var j := fj + dj
			if i < 0 or j < 0 or i >= nx or j >= nz or free[j * nx + i] == 0:
				continue
			var d := Vector2(float(di), float(dj)).length()
			if d < best:
				best = d
				start = j * nx + i
	if start < 0:
		return false
	var found := PackedByteArray()
	found.resize(targets.size())
	var left := targets.size()
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size() and left > 0:
		var k := queue[head]
		head += 1
		var ci := k % nx
		var cj: int = int(k / nx)
		var here := Vector3(x0 + float(ci) * cell, 0.0, -rail + float(cj) * cell)
		for g in targets.size():
			if found[g] == 0 and flat(here, targets[g]) <= 1.3:
				found[g] = 1
				left -= 1
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = ci + int(d[0])
			var nj: int = cj + int(d[1])
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
				continue
			var nk := nj * nx + ni
			if seen[nk] == 1 or free[nk] == 0:
				continue
			seen[nk] = 1
			queue.append(nk)
	return left <= 0


## The targets that must stay reachable from Krystal: every line-brazier (from its open side) and both ends
## of the deck (the way back to the checkpoint and the way on).
static func route_targets(braziers: Array, bridge: Rect2) -> Array:
	var out: Array = []
	for b in braziers:
		if b is Vector3:
			var bv: Vector3 = b
			out.append(Vector3(bv.x, bv.y, bv.z - signf(bv.z) * 1.0))
	out.append(Vector3(bridge.position.x + 0.5, 0.0, 0.0))
	out.append(Vector3(bridge.end.x - 0.5, 0.0, 0.0))
	return out


static func brazier_circles(braziers: Array) -> Array:
	var out: Array = []
	for b in braziers:
		if b is Vector3:
			out.append([b, BRAZIER_SOLID])
	return out


# --- Pounces -----------------------------------------------------------------------------------------------------

## A valid pounce landing for Krystal at `krystal`: on the deck, inside the rails, clear of every line-brazier
## (BRAZIER_CLEAR) and of standing threads (THREAD_CLEAR), and no farther than POUNCE_MAX_OFFSET from her
## (otherwise it is not a pounce at her at all). {"ok": bool, "pos": Vector3, "reason": ""|"off_deck"|"no_landing"}.
## (The node adds the line-of-sight ray from her anchor; this is the pure part.)
static func pounce_landing(krystal: Vector3, bridge: Rect2, rail: float, deck_y: float, braziers: Array, segs: Array) -> Dictionary:
	if not on_deck(krystal, bridge, rail, deck_y):
		return {"ok": false, "pos": krystal, "reason": "off_deck"}
	var p := _clamp_deck(krystal, bridge, rail, deck_y)
	for pass_i in 3:
		for b in braziers:
			if not (b is Vector3):
				continue
			var bv: Vector3 = b
			if flat(p, bv) < BRAZIER_CLEAR:
				var d := Vector2(p.x - bv.x, p.z - bv.z)
				if d.length() < 0.05:
					d = Vector2(0.0, -signf(bv.z) if absf(bv.z) > 0.01 else 1.0)
				d = d.normalized() * BRAZIER_CLEAR * 1.001
				p = _clamp_deck(Vector3(bv.x + d.x, deck_y, bv.z + d.y), bridge, rail, deck_y)
		for sg in segs:
			var c := seg_closest(sg[0], sg[1], p)
			if flat(c, p) < THREAD_CLEAR:
				var d := Vector2(p.x - c.x, p.z - c.z)
				if d.length() < 0.05:
					d = Vector2(krystal.x - c.x, krystal.z - c.z)
				if d.length() < 0.05:
					d = Vector2(1.0, 0.0)
				d = d.normalized() * THREAD_CLEAR * 1.001
				p = _clamp_deck(Vector3(c.x + d.x, deck_y, c.z + d.y), bridge, rail, deck_y)
	if not landing_valid(p, bridge, rail, deck_y, braziers, segs):
		return {"ok": false, "pos": p, "reason": "no_landing"}
	if flat(p, krystal) > POUNCE_MAX_OFFSET:
		return {"ok": false, "pos": p, "reason": "no_landing"}
	return {"ok": true, "pos": p, "reason": ""}


static func landing_valid(p: Vector3, bridge: Rect2, rail: float, deck_y: float, braziers: Array, segs: Array) -> bool:
	if not on_deck(p, bridge, rail - LANDING_RAIL_INSET + 0.01, deck_y, 0.1):
		return false
	for b in braziers:
		if b is Vector3 and flat(p, b) < BRAZIER_CLEAR - 0.01:
			return false
	for sg in segs:
		if seg_dist(sg[0], sg[1], p) < THREAD_CLEAR - 0.01:
			return false
	return true


## Is Krystal (at `p`) caught by a pounce landing at `landing`? The marked ring is the hit test.
static func pounce_hits(landing: Vector3, p: Vector3, max_dy: float = 2.0) -> bool:
	return flat(landing, p) <= POUNCE_RADIUS + HIT_BODY and absf(p.y - landing.y) < max_dy


## The knockback axis: ALONG the bridge only (the rails and the pit are across it; both deck ends run
## onto solid ledges), away from the landing - dead centre pushes toward the middle of the deck.
static func push_dir(landing: Vector3, target: Vector3, bridge: Rect2) -> Vector3:
	var dx := target.x - landing.x
	if absf(dx) < 0.15:
		dx = (bridge.position.x + bridge.size.x * 0.5) - target.x
	if absf(dx) < 0.001:
		dx = 1.0
	return Vector3(signf(dx), 0.0, 0.0)


## Tests: `target` pushed `dist` along `dir` stays on walkable floor (`walk` = deck + end ledges, x/z rect).
static func push_is_safe(target: Vector3, dir: Vector3, dist: float, walk: Rect2, rail: float) -> bool:
	var q := target + Vector3(dir.x, 0.0, dir.z).normalized() * dist
	return q.x >= walk.position.x and q.x <= walk.end.x and absf(q.z) <= rail + 0.01


## Where she lands when a flare burns her off the ceiling: under her, inside the rails, clear of every
## line-brazier (the one Krystal is standing at).
static func scorch_landing(from: Vector3, bridge: Rect2, rail: float, deck_y: float, braziers: Array) -> Vector3:
	var p := _clamp_deck(Vector3(from.x, deck_y, from.z), bridge, rail, deck_y)
	for pass_i in 3:
		for b in braziers:
			if b is Vector3 and flat(p, b) < BRAZIER_CLEAR:
				var bv: Vector3 = b
				var d := Vector2(p.x - bv.x, p.z - bv.z)
				if d.length() < 0.05:
					d = Vector2(0.0, -signf(bv.z) if absf(bv.z) > 0.01 else 1.0)
				d = d.normalized() * BRAZIER_CLEAR * 1.001
				p = _clamp_deck(Vector3(bv.x + d.x, deck_y, bv.z + d.y), bridge, rail, deck_y)
	return p


# --- The release -----------------------------------------------------------------------------------------------------

## Up to `n` sac spots on the deck: >= SAC_MIN_PLAYER_DIST from Krystal (never underfoot), clear of the
## braziers and standing threads, inside the rails, SAC_SEPARATION apart - preferring spots IN FRONT of her
## (toward `toward`, where she is already looking at the Matron: no camera spin needed), nearest first.
static func sac_spots(from: Vector3, toward: Vector3, n: int, bridge: Rect2, rail: float, deck_y: float, braziers: Array, segs: Array) -> Array:
	var look := Vector2(toward.x - from.x, toward.z - from.z)
	look = look.normalized() if look.length() > 0.01 else Vector2(1.0, 0.0)
	var cands: Array = []
	var x := bridge.position.x + 2.0
	var zr := maxf(rail - 1.2, 0.5)
	while x <= bridge.end.x - 2.0:
		for z in [-zr, 0.0, zr]:
			var p := Vector3(x, deck_y, float(z))
			if flat(p, from) < SAC_MIN_PLAYER_DIST:
				continue
			var ok := true
			for b in braziers:
				if b is Vector3 and flat(p, b) < SAC_BRAZIER_CLEAR:
					ok = false
			for sg in segs:
				if seg_dist(sg[0], sg[1], p) < SAC_THREAD_CLEAR:
					ok = false
			if ok:
				var dir := Vector2(p.x - from.x, p.z - from.z).normalized()
				var front := dir.dot(look) >= 0.2
				cands.append([(0.0 if front else 1000.0) + flat(p, from), p])
		x += 2.0
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for c in cands:
		if out.size() >= n:
			break
		var p: Vector3 = c[1]
		var far := true
		for q in out:
			if flat(p, q) < SAC_SEPARATION:
				far = false
		if far:
			out.append(p)
	return out
