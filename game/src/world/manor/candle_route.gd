extends RefCounted
## Pure logic of the ballroom candle-routing puzzle (data/manor_layout.gd PUZZLE). No nodes, no state:
## the puzzle node keeps `arms` (candelabrum id -> arm index) and asks trace() what is lit.
## Rule (taught by the dance card): once the hearth candle is lit, its flame walks the gilt runner to
## the first candelabrum; every candelabrum it reaches lights up and passes the flame along the runner
## its brass hand points at. The flame stops when a hand points back the way it came, or at a candle
## that is already lit. Reaching "T" (the crescent lock on the Gallery doors) solves the puzzle.

const SOURCE := "S"
const TARGET := "T"


static func node_ids(puzzle: Dictionary) -> Array:
	var ids: Array = (puzzle["nodes"] as Dictionary).keys()
	ids.sort()
	return ids


static func initial_arms(puzzle: Dictionary) -> Dictionary:
	var arms := {}
	for id in node_ids(puzzle):
		arms[String(id)] = 0
	return arms


## Where candelabrum `id` currently points ("" if unknown).
static func arm_target(puzzle: Dictionary, arms: Dictionary, id: String) -> String:
	var n: Dictionary = puzzle["nodes"].get(id, {})
	var opts: Array = n.get("arms", [])
	if opts.is_empty():
		return ""
	return String(opts[posmod(int(arms.get(id, 0)), opts.size())])


## Arms after turning `id` one notch (a new dictionary).
static func turned(puzzle: Dictionary, arms: Dictionary, id: String) -> Dictionary:
	var out := arms.duplicate()
	var n: Dictionary = puzzle["nodes"].get(id, {})
	var opts: Array = n.get("arms", [])
	if opts.is_empty():
		return out
	out[id] = posmod(int(arms.get(id, 0)) + 1, opts.size())
	return out


## {"lit": [candelabrum ids in flame order], "runners": [[from, to], ...], "solved": bool}
static func trace(puzzle: Dictionary, arms: Dictionary, source_lit: bool) -> Dictionary:
	var out := {"lit": [], "runners": [], "solved": false}
	if not source_lit:
		return out
	var nodes: Dictionary = puzzle["nodes"]
	var prev := SOURCE
	var cur := String(puzzle["source"]["to"])
	(out["runners"] as Array).append([SOURCE, cur])
	var visited := {SOURCE: true}
	var guard := 0
	while guard < 64:
		guard += 1
		if cur == TARGET:
			out["solved"] = true
			break
		if visited.has(cur) or not nodes.has(cur):
			break
		visited[cur] = true
		(out["lit"] as Array).append(cur)
		var nxt := arm_target(puzzle, arms, cur)
		if nxt == "" or nxt == prev:
			break
		(out["runners"] as Array).append([cur, nxt])
		prev = cur
		cur = nxt
	return out


## Every undirected runner of the board: the source link plus each arm target ([a, b] sorted, unique).
static func runners(puzzle: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	var pairs: Array = [[SOURCE, String(puzzle["source"]["to"])]]
	for id in node_ids(puzzle):
		for t in puzzle["nodes"][id]["arms"]:
			pairs.append([String(id), String(t)])
	for p in pairs:
		var a := String(p[0])
		var b := String(p[1])
		var key := a + "|" + b if a < b else b + "|" + a
		if seen.has(key):
			continue
		seen[key] = true
		out.append([a, b] if a < b else [b, a])
	return out


## The first arm setting (in a fixed, deterministic order) that solves the board ({} if none).
static func solution(puzzle: Dictionary) -> Dictionary:
	var ids := node_ids(puzzle)
	var sizes: Array = []
	var total := 1
	for id in ids:
		var n: int = (puzzle["nodes"][id]["arms"] as Array).size()
		sizes.append(n)
		total *= n
	for k in total:
		var arms := {}
		var rest := k
		for i in ids.size():
			arms[String(ids[i])] = rest % int(sizes[i])
			rest /= int(sizes[i])
		if bool(trace(puzzle, arms, true)["solved"]):
			return arms
	return {}


## Fewest turns from `arms` to a solved board (breadth-first; -1 if unsolvable). Tests use it.
static func min_turns(puzzle: Dictionary, arms: Dictionary) -> int:
	var ids := node_ids(puzzle)
	var start := _key(ids, arms)
	var frontier: Array = [arms]
	var dist := {start: 0}
	while not frontier.is_empty():
		var cur: Dictionary = frontier.pop_front()
		var d: int = int(dist[_key(ids, cur)])
		if bool(trace(puzzle, cur, true)["solved"]):
			return d
		for id in ids:
			var nxt := turned(puzzle, cur, String(id))
			var k := _key(ids, nxt)
			if not dist.has(k):
				dist[k] = d + 1
				frontier.append(nxt)
	return -1


static func _key(ids: Array, arms: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in ids:
		parts.append(str(int(arms.get(id, 0))))
	return ",".join(parts)
