extends RefCounted
## Pure state machines of the three ward-line puzzles (no nodes; the room controllers and the tests call
## these). Every state is reachable from every other one, nothing is ever lost or locked by a wrong move,
## and none of them has a timer (Settings timing_assist has nothing to remove). Solving sets the line flag;
## the flag is what persists (the controllers show the solved state from it on load).
##   Sluice (water line): two valves with two positions each.
##   Bells (bell line): strike four symbol bells in the plaque's order; a wrong strike simply restarts.
##   Light well (light line): two mirrors with four quarter-turn facings each + a reset lever.

const Layout := preload("res://data/works_layout.gd")

# --- Sluice Gallery ------------------------------------------------------------------------------------------
## Valve A (upper, at the header basin): 0 = inlet -> drain channel, 1 = inlet -> middle channel.
## Valve B (lower, end of the middle channel): 0 = middle -> overflow drain, 1 = middle -> ward basin.
const SLUICE_START := [0, 0]
const SLUICE_A_NAMES := ["the drain channel", "the middle channel"]
const SLUICE_B_NAMES := ["the overflow drain", "the ward basin"]


static func valve_next(v: int) -> int:
	return (v + 1) % 2


## Which channels carry water for a valve setting: {"drain", "middle", "ward"} -> bool.
static func sluice_flow(a: int, b: int) -> Dictionary:
	var mid := a == 1
	return {"drain": a == 0 or (mid and b == 0), "middle": mid, "ward": mid and b == 1}


static func sluice_solved(a: int, b: int) -> bool:
	return a == 1 and b == 1


# --- Bellmaker's Floor ---------------------------------------------------------------------------------------
## One strike: {"progress": int, "result": "advance" | "reset" | "solved" | "ignored"}. A wrong symbol
## restarts at 0 - unless it is the first symbol of the order, which starts a fresh attempt at 1.
static func bell_step(progress: int, struck: String, order: Array = Layout.BELL_ORDER) -> Dictionary:
	if progress >= order.size():
		return {"progress": order.size(), "result": "ignored"}
	if not order.has(struck):
		return {"progress": progress, "result": "ignored"}
	if String(order[progress]) == struck:
		var p := progress + 1
		return {"progress": p, "result": "solved" if p >= order.size() else "advance"}
	if String(order[0]) == struck:
		return {"progress": 1, "result": "reset"}
	return {"progress": 0, "result": "reset"}


# --- Light Well ---------------------------------------------------------------------------------------------------
## Facings: 0 north (-z), 1 east (+x), 2 south (+z), 3 west (-x). Daylight falls on mirror A; A sends it
## toward its facing. Mirror B sits east of A, the ward crystal south of B: solved = A east, B south.
const MIRROR_START := [0, 3]
const FACING_NAMES := ["north", "east", "south", "west"]
const DIRS := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]


static func mirror_next(d: int) -> int:
	return (d + 1) % 4


## The beam's path: {"hits": ["a", ...,"b", "target"], "ends": "wall" | "target" | "a", "solved": bool}.
static func beam_path(a: int, b: int) -> Dictionary:
	var hits: Array = ["a"]
	if a != 1:
		return {"hits": hits, "ends": "wall", "solved": false}
	hits.append("b")
	if b == 2:
		hits.append("target")
		return {"hits": hits, "ends": "target", "solved": true}
	if b == 3:
		return {"hits": hits, "ends": "a", "solved": false}     # straight back at mirror A: nothing happens
	return {"hits": hits, "ends": "wall", "solved": false}


static func beam_solved(a: int, b: int) -> bool:
	return bool(beam_path(a, b)["solved"])
