extends Node3D
## QA-only preview helper (never used by gameplay): lines up every harvestable visual and item
## pickup so they can be rendered with the preview stage:
##   tools/godot.sh --path game -- --preview=res://src/world/common/props_showcase.gd --shot-dir=<dir>
## setup({"set": "trees" | "props" | "items"}) picks what to show.

const ResourceNode := preload("res://src/world/common/resource_node.gd")
const WorldItem := preload("res://src/world/common/world_item.gd")

var which := "trees"


func setup(p: Dictionary) -> void:
	which = String(p.get("set", "trees"))


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		return
	match which:
		"trees":
			var i := 0
			for sp in ["oak", "pine", "blossom", "birch"]:
				for v in 2:
					var n: Node3D = ResourceNode.new()
					n.setup({"kind": "tree", "visual": sp, "seed": v, "name": sp})
					add_child(n)
					n.position = Vector3((i % 4) * 4.5 - 6.75, 0, (i / 4) * 5.0 - 2.5)
					i += 1
		"props":
			var kinds := [["rock", "boulder"], ["ore", "copper_vein"], ["bush", "berry_bush"], ["grass", "grass_tuft"],
				["stick", "stick"], ["stone", "pebble"], ["glowcap", "glowcap"], ["silk", "silk"], ["crystal", "crystal"], ["rubble", "rubble"]]
			for i in kinds.size():
				var k: Array = kinds[i]
				var n: Node3D = ResourceNode.new()
				n.setup({"kind": k[0], "visual": k[1], "seed": i})
				add_child(n)
				n.position = Vector3((i % 5) * 2.4 - 4.8, 0, (i / 5) * 2.6 - 1.3)
		"items":
			var ids := ["wood", "stone", "fiber", "berries", "copper_ore", "sweetroot_seeds", "sweetroot", "shiny_pebble",
				"glowcap", "silk", "echo_shard", "stone_axe", "stone_pickaxe", "copper_sword", "lantern", "berry_snack",
				"hearty_stew", "glowcap_skewer", "foreman_key", "heartseed", "workbench"]
			for i in ids.size():
				var n: Node3D = WorldItem.spawn(ids[i], 1, Vector3((i % 7) * 0.8 - 2.4, 0, (i / 7) * 0.9 - 0.9), false, self)
				if n != null:
					n.set_process(false)
