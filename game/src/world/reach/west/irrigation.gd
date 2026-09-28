extends RefCounted
## Pumpkintide Orchard irrigation puzzle - a pure state machine (no nodes, unit-tested directly).
## A cistern always feeds the trunk flume down to a junction. Lever 1 (junction sluice) sends the water west to
## the drain pond (where it starts) or south-east toward the festival garden; lever 2 raises / lowers the garden
## sluice gate. Water reaches the festival bed only when the junction points to the garden AND the gate is up;
## with the junction on the garden branch but the gate down, the water backs up and spills into a visible
## puddle in front of the gate (the "open the gate" clue). Levers are reversible at any time. The first time
## water reaches the garden, FLAG_IRRIGATED latches ("irrigation repaired") and stays true whatever the levers
## do later, so the lamp never un-qualifies. No timing anywhere (timing_assist has nothing to relax here).
## State = {"junction": "drain" | "garden", "gate": bool}; saved as the two lever flags (Data.FLAG_JUNCTION_GARDEN,
## Data.FLAG_GATE_OPEN).

const Data := preload("res://data/reach_west.gd")

const SEGMENTS := ["trunk", "drain", "garden_a", "garden_b"]


static func initial() -> Dictionary:
	return {"junction": "drain", "gate": false}


static func toggle_junction(state: Dictionary) -> Dictionary:
	var s := state.duplicate()
	s["junction"] = "drain" if String(state.get("junction", "drain")) == "garden" else "garden"
	return s


static func toggle_gate(state: Dictionary) -> Dictionary:
	var s := state.duplicate()
	s["gate"] = not bool(state.get("gate", false))
	return s


## Which parts hold water: flume segments (Data.FLUME_SEGMENTS ids) plus "drain_pond", "spill" and "garden".
static func flow(state: Dictionary) -> Dictionary:
	var to_garden := String(state.get("junction", "drain")) == "garden"
	var gate := bool(state.get("gate", false))
	return {
		"trunk": true,
		"drain": not to_garden,
		"drain_pond": not to_garden,
		"garden_a": to_garden,
		"spill": to_garden and not gate,
		"garden_b": to_garden and gate,
		"garden": to_garden and gate,
	}


static func reaches_garden(state: Dictionary) -> bool:
	return bool(flow(state)["garden"])


## Human-readable description of where the water goes now (for prompts and captions; never audio-only).
static func describe(state: Dictionary) -> String:
	var f := flow(state)
	if bool(f["garden"]):
		return "Water runs all the way to the festival garden."
	if bool(f["spill"]):
		return "Water runs toward the garden but pools against the closed sluice gate."
	return "Water runs off into the drain pond."


# --- Saved state (GameState flags) -------------------------------------------------------------------------

static func load_state() -> Dictionary:
	return {"junction": "garden" if _truthy(GameState.get_flag(Data.FLAG_JUNCTION_GARDEN)) else "drain",
		"gate": _truthy(GameState.get_flag(Data.FLAG_GATE_OPEN))}


## Saves the levers and latches "irrigation repaired" the first time water reaches the garden.
## Returns true when this call latched it.
static func store_state(state: Dictionary) -> bool:
	GameState.set_flag(Data.FLAG_JUNCTION_GARDEN, String(state.get("junction", "drain")) == "garden")
	GameState.set_flag(Data.FLAG_GATE_OPEN, bool(state.get("gate", false)))
	if reaches_garden(state) and not is_repaired():
		GameState.set_flag(Data.FLAG_IRRIGATED, true)
		return true
	return false


static func is_repaired() -> bool:
	return _truthy(GameState.get_flag(Data.FLAG_IRRIGATED))


## Puts both levers back to their starting positions (reset-safe: the "repaired" latch is kept).
static func reset() -> Dictionary:
	var s := initial()
	GameState.set_flag(Data.FLAG_JUNCTION_GARDEN, false)
	GameState.set_flag(Data.FLAG_GATE_OPEN, false)
	return s


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	return false
