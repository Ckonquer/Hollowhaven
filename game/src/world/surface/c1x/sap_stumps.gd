extends RefCounted
## Renewable Resin (MP 16 "Marked tappable sap stumps"; spec 7.1): five old stumps with a carved spout and a little
## bucket, spread over Hollowhaven Woods (data/c1x_layout.gd SAP_STUMPS, never inside the Haven build area).
## Each is a harvestable resource node (ids c1x_resin_<n>, persistent in GameState.depleted) whose tool, hits,
## drops and respawn time come from data/sources.gd NODES["sap_stump"] (hand: "Tap"). Tapping empties the bucket
## and the bark drips; the sap refills after the data respawn time. Events.harvested reports "sap_stump".
##   SapStumps.build(area)
##   SapStumps.grass_clearings() -> Array

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")


static func build(area: Node3D) -> void:
	if area == null:
		return
	var parent := Common.sub_root(area, "SapStumps")
	for i in L.SAP_STUMPS.size():
		var d: Dictionary = L.SAP_STUMPS[i]
		var node := Common.harvest_node(L.SAP_KIND, String(d["id"]), Common.sap_stump_visual(i % 3),
			{"solid": true, "hit_sound": "pickup", "fx": "copper", "seed": i},
			"Sap Stump (the sap is still gathering)")
		Common.place(parent, node, area, d["pos"], float(d.get("yaw_deg", 0.0)), -0.04)


static func grass_clearings() -> Array:
	var out: Array = []
	for d in L.SAP_STUMPS:
		out.append([d["pos"], 1.0])
	return out
