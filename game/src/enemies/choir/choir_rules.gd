extends RefCounted
## The Borrowed Choir's numbers and pure rules (MP §13.3). Static only - the boss, its parts and the tests
## read the same tables, so what is tuned here is what plays.
##   const Rules := preload("res://src/enemies/choir/choir_rules.gd")
##
## HEALTH IS A PACING DISPLAY, NOT A SPONGE. The data hp (data/enemies.gd "borrowed_choir", 480-620) is split
## into three equal phase budgets (A 100%->67%, B 67%->33%, C 33%->0). The Choir can only be hurt while it is
## EXPOSED (a lantern reveal / both resonators / the kept flame), and every exposure is bounded both ways:
##   WINDOW_CAP    the most one exposure can take (good gear ends the window early - never skips the lesson)
##   WINDOW_FLOOR  the least one exposure takes: when the window closes the true light "sears" the borrowed
##                 shape down to at least this much of the phase budget (weak gear still progresses)
## => phases A and C need EXACTLY three exposures each (cap = floor = a third of the budget: the reveal is the
##    lesson, good gear only shortens each window; the third kept-flame exposure ends the fight whatever the
##    weapon), phase B one or two resonator cycles (strong gear can take the whole budget in one window).
## Health never crosses a phase boundary inside one hit (the boss health's floor_hp), so phases start with
## low overhead and never "bleed" into each other.
## Timings are [Gentle, Standard, Intense]. Committed attacks warn 1.1-1.4 s (never under MIN_TELL);
## Settings timing_assist multiplies every warning / window / recovery / wait by ASSIST_MULT, slows the rings
## and widens their gaps (no tight timing anywhere).

const PHASES := 3
const EXPOSURES_TO_END := 3
const WINDOW_CAP := [1.0 / 3.0, 1.0, 1.0 / 3.0]    # share of the phase budget one exposure may take, by phase
const WINDOW_FLOOR := [1.0 / 3.0, 0.5, 1.0 / 3.0]  # share one exposure always takes
const MIN_TELL := 1.0
const ASSIST_MULT := 1.5

# --- Timings [Gentle, Standard, Intense] (seconds) ------------------------------------------------------------
const T_INTRO := 2.4
const T_INTRO_RETRY := 1.2
const T_SHRIEK := 2.2
# Phase A "False welcome"
const T_GATHER := [1.8, 1.5, 1.3]
const T_WAIT := [18.0, 13.0, 10.0]          # forms stand revealed-able; then the Choir grows impatient (a sweep)
const T_SWEEP_TELE := [1.4, 1.3, 1.1]
const T_SWEEP := 0.35
const T_RECOVER_A := [2.4, 2.0, 1.6]
const T_WINDOW_A := [8.0, 6.5, 6.0]
const SWEEP_ARC := [100.0, 110.0, 110.0]
# Phase B "Stolen rhythm"
const T_B_GATHER := 2.0
const T_B_IDLE := [3.2, 2.4, 1.8]
const T_RING_TELE := [1.4, 1.3, 1.2]
const RING_SPEED := [3.0, 3.8, 4.4]         # m/s outward
const RING_GAP := [110.0, 85.0, 70.0]       # degrees of the marked opening
const RINGS_PER_VOLLEY := [1, 2, 2]
const RING_SPACING := 1.3                   # seconds between the rings of one volley
const RING_BAND := 0.6                      # width of the moving band that hits
const RING_START := 1.6
const INTENSE_GAP_SHIFT := 60.0             # Intense: the second ring's gap is turned this far (shown in advance)
const ASSIST_RING_SPEED := 0.7
const ASSIST_GAP_BONUS := 30.0
const T_STRIKE_DELAY := [1.4, 1.3, 1.2]
const T_STRIKE := 0.3
const STRIKE_COUNT := [1, 2, 3]
const STRIKE_RADIUS := 1.7
const STRIKE_SPREAD := 2.9
const T_WINDOW_B := [9.0, 7.5, 7.0]
const T_B_REFORM := 2.2
const WISPS := [1, 2, 2]                    # Borrowed Wisps released per phase-B attempt (never more, never refilled)
# Phase C "The kept flame"
const T_C_GATHER := 2.0
const T_SETTLE := [2.0, 1.6, 1.4]
const T_HUSH_TELE := [1.4, 1.3, 1.2]
const T_HUSH := 0.3
const T_OPEN := [12.0, 10.0, 8.0]
const T_WINDOW_C := [7.0, 6.0, 5.5]
const T_RECOVER_C := [2.2, 1.8, 1.5]
const LIT_ARC := [100.0, 80.0, 70.0]        # the true flame's lit sector (safe from the hush)
const FALSE_LIGHTS := [2, 2, 3]
const INTENSE_FEINT_AT := 0.55              # Intense: the flame swings to its real hook after this share of the settle
# Caps (MP §12: simultaneous committed attacks, counting the wisps' wind-ups). Intense adds a feint and less idle,
# never more overlap: it keeps Standard's cap, which is also enemy_base's shared MAX_ATTACKERS token table (2).
const MAX_COMMITTED := [1, 2, 2]
const MAX_RINGS := 2
const MAX_STRIKES := 3


static func idx(intensity: int) -> int:
	return clampi(intensity, 0, 2)


static func pick(table: Array, intensity: int) -> float:
	return float(table[idx(intensity)])


static func picki(table: Array, intensity: int) -> int:
	return int(table[idx(intensity)])


## A warning / window / recovery / wait length after timing assist.
static func assisted(base: float, assist: bool) -> float:
	return base * ASSIST_MULT if assist else base


## A committed attack's warning: the table value, never shorter than MIN_TELL, stretched by timing assist.
static func tell(table: Array, intensity: int, assist: bool) -> float:
	return assisted(maxf(pick(table, intensity), MIN_TELL), assist)


# --- Health / phases -----------------------------------------------------------------------------------------

static func budget(max_hp: float) -> float:
	return max_hp / float(PHASES)


static func phase_start_hp(phase: int, max_hp: float) -> float:
	return max_hp - budget(max_hp) * float(clampi(phase, 1, PHASES) - 1)


static func phase_end_hp(phase: int, max_hp: float) -> float:
	return maxf(max_hp - budget(max_hp) * float(clampi(phase, 1, PHASES)), 0.0)


## 1 above two thirds, 2 above one third, else 3 (a hair of tolerance for float rounding).
static func phase_for(hp: float, max_hp: float) -> int:
	var eps := maxf(max_hp, 1.0) * 0.0001
	if hp <= phase_end_hp(2, max_hp) + eps:
		return 3
	if hp <= phase_end_hp(1, max_hp) + eps:
		return 2
	return 1


static func window_cap(phase: int, max_hp: float) -> float:
	return budget(max_hp) * float(WINDOW_CAP[clampi(phase, 1, PHASES) - 1])


static func window_floor(phase: int, max_hp: float) -> float:
	return budget(max_hp) * float(WINDOW_FLOOR[clampi(phase, 1, PHASES) - 1])


## The lowest hp one exposure that began at `start_hp` may reach (never past the phase boundary).
static func window_min_hp(phase: int, start_hp: float, max_hp: float) -> float:
	return maxf(phase_end_hp(phase, max_hp), start_hp - window_cap(phase, max_hp))


## Hp after an exposure that began at `start_hp` and left `hp_now`: at least WINDOW_FLOOR of the budget is gone.
static func after_window_hp(phase: int, hp_now: float, start_hp: float, max_hp: float) -> float:
	var target := maxf(phase_end_hp(phase, max_hp), start_hp - window_floor(phase, max_hp))
	return minf(hp_now, target)


# --- Caps ------------------------------------------------------------------------------------------------------

## May the Choir start a committed attack while `committed_others` wisps are winding up / sweeping?
## Gentle: never overlaps; Standard and Intense: at most one wisp alongside.
static func may_commit(intensity: int, committed_others: int) -> bool:
	return committed_others + 1 <= picki(MAX_COMMITTED, intensity)


static func wisp_cap(intensity: int) -> int:
	return picki(WISPS, intensity)


static func ring_gap(intensity: int, assist: bool) -> float:
	return pick(RING_GAP, intensity) + (ASSIST_GAP_BONUS if assist else 0.0)


static func ring_speed(intensity: int, assist: bool) -> float:
	return pick(RING_SPEED, intensity) * (ASSIST_RING_SPEED if assist else 1.0)


static func strike_count(intensity: int) -> int:
	return mini(picki(STRIKE_COUNT, intensity), MAX_STRIKES)


# --- Geometry (flat XZ) -------------------------------------------------------------------------------------------

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Flat unit direction from `from` toward `to` (fallback when they coincide).
static func bearing(from: Vector3, to: Vector3, fallback: Vector3 = Vector3.FORWARD) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 0.0001 else fallback


## Is `pos` within `arc_deg / 2` of `dir` as seen from `center` (the centre point itself counts as outside)?
static func in_arc_of(center: Vector3, dir: Vector3, arc_deg: float, pos: Vector3) -> bool:
	var v := Vector2(pos.x - center.x, pos.z - center.z)
	if v.length_squared() < 0.0001:
		return false
	if arc_deg >= 359.0:
		return true
	var f := Vector2(dir.x, dir.z)
	if f.length_squared() < 0.000001:
		return false
	return rad_to_deg(absf(f.normalized().angle_to(v.normalized()))) <= arc_deg * 0.5


## The kept flame's lit sector: inside `radius`, within `arc_deg` around `lit_dir` from the centre.
static func in_lit_sector(center: Vector3, lit_dir: Vector3, arc_deg: float, radius: float, pos: Vector3) -> bool:
	return flat(center, pos) <= radius and in_arc_of(center, lit_dir, arc_deg, pos)


## The hush strikes everything inside `radius` (the perimeter walk is outside it) except the lit sector.
static func in_hush(center: Vector3, lit_dir: Vector3, lit_arc: float, radius: float, pos: Vector3) -> bool:
	return flat(center, pos) <= radius and not in_arc_of(center, lit_dir, lit_arc, pos)


## A resonance ring's gap (the marked safe opening).
static func in_gap(center: Vector3, gap_dir: Vector3, gap_deg: float, pos: Vector3) -> bool:
	return in_arc_of(center, gap_dir, gap_deg, pos)


## Did a ring band that moved from `r_prev` to `r` (band width `band`) pass over `pos` (+ her body radius)?
static func band_hit(center: Vector3, r_prev: float, r: float, band: float, pos: Vector3, body: float = 0.35) -> bool:
	var d := flat(center, pos)
	var lo := minf(r_prev, r) - band * 0.5 - body
	var hi := maxf(r_prev, r) + band * 0.5 + body
	return d >= lo and d <= hi
