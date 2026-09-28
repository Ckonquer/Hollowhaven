extends "res://src/world/common/resource_node.gd"
## An Ashbell Quarry harvest node (iron veins, Moon Crystal seams, copper veins, boulders, stones). Everything
## that matters lives in src/world/common/resource_node.gd: the data/sources.gd node kind ("iron_vein",
## "moon_crystal_vein", ...) gives tool / min_tier / hits / drops / respawn, each hit counts the tool's power
## (stone pickaxe 6 hits on an iron vein, copper 4, ...), a pickaxe below min_tier only wobbles the node and says
## which pickaxe is needed (nothing taken, nothing given), depletion persists through GameState.deplete with the
## stable node_id, Events.harvested reports the data kind, and the gathering charm / mastery bonuses apply.
## This subclass only adds, for UI and hints, why a tier-gated node can't be mined yet:
##   get_harvest_info() -> {... "min_tier", "tier_blocked": true, "reason": "Moon Crystal Seam needs an
##   Ironwood Pickaxe or better."} while no owned pickaxe meets min_tier.

const QD := preload("res://data/reach_east.gd")


## True when the best owned tool of this node's kind meets min_tier (always true for hand nodes / tier <= 1).
func tier_reachable() -> bool:
	if tool == "hand" or required_tier <= 1:
		return true
	return StatsLayer.best_tool(tool, required_tier) != ""


func blocked_reason() -> String:
	if tier_reachable():
		return ""
	return QD.TEXT["tier_needs"] % [display_name, tier_tool_name(tool, required_tier)]


func get_harvest_info() -> Dictionary:
	var info := super.get_harvest_info()
	if not depleted and not tier_reachable():
		info["tier_blocked"] = true
		info["reason"] = blocked_reason()
	return info
