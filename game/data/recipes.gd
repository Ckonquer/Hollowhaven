extends RefCounted
## Recipe definitions. Keys are stable recipe ids.
## station: "hand" (anywhere) | "workbench" (near a placed workbench) | "campfire" (near the Haven campfire)
## unlock: "" = known from the start; otherwise a GameState flag that must be true to show/craft.
## A recipe consumes every ingredient exactly once and produces `count` of `result` exactly once.

const RECIPES := {
	# --- By hand -----------------------------------------------------------------
	"stone_axe": {"result": "stone_axe", "count": 1, "station": "hand", "ingredients": {"wood": 3, "stone": 2, "fiber": 2}, "unlock": ""},
	"stone_pickaxe": {"result": "stone_pickaxe", "count": 1, "station": "hand", "ingredients": {"wood": 3, "stone": 3, "fiber": 2}, "unlock": ""},
	"workbench": {"result": "workbench", "count": 1, "station": "hand", "ingredients": {"wood": 8, "stone": 2}, "unlock": ""},
	"berry_snack": {"result": "berry_snack", "count": 1, "station": "hand", "ingredients": {"berries": 4}, "unlock": ""},
	"crop_plot": {"result": "crop_plot", "count": 1, "station": "hand", "ingredients": {"wood": 3, "fiber": 3}, "unlock": ""},
	# --- Workbench -----------------------------------------------------------------
	"copper_sword": {"result": "copper_sword", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "copper_ore": 4, "fiber": 2}, "unlock": ""},
	"lantern": {"result": "lantern", "count": 1, "station": "workbench", "ingredients": {"copper_ore": 3, "fiber": 2, "wood": 2}, "unlock": ""},
	"storage_chest": {"result": "storage_chest", "count": 1, "station": "workbench", "ingredients": {"wood": 10, "copper_ore": 1}, "unlock": ""},
	"bed": {"result": "bed", "count": 1, "station": "workbench", "ingredients": {"wood": 8, "fiber": 6}, "unlock": ""},
	"wood_floor": {"result": "wood_floor", "count": 1, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"wood_wall": {"result": "wood_wall", "count": 1, "station": "workbench", "ingredients": {"wood": 3}, "unlock": ""},
	"wood_window": {"result": "wood_window", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "fiber": 1}, "unlock": ""},
	"wood_doorway": {"result": "wood_doorway", "count": 1, "station": "workbench", "ingredients": {"wood": 3}, "unlock": ""},
	"wood_roof": {"result": "wood_roof", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "fiber": 2}, "unlock": ""},
	"fence": {"result": "fence", "count": 2, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"lantern_post": {"result": "lantern_post", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "copper_ore": 1, "fiber": 1}, "unlock": ""},
	"flower_pot": {"result": "flower_pot", "count": 1, "station": "workbench", "ingredients": {"stone": 3, "fiber": 1}, "unlock": ""},
	"rug": {"result": "rug", "count": 1, "station": "workbench", "ingredients": {"fiber": 6, "berries": 2}, "unlock": ""},
	"table": {"result": "table", "count": 1, "station": "workbench", "ingredients": {"wood": 5}, "unlock": ""},
	"stool": {"result": "stool", "count": 1, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"pebble_cairn": {"result": "pebble_cairn", "count": 1, "station": "workbench", "ingredients": {"shiny_pebble": 3, "stone": 2}, "unlock": ""},
	"echo_chime": {"result": "echo_chime", "count": 1, "station": "workbench", "ingredients": {"echo_shard": 3, "wood": 1, "fiber": 1}, "unlock": ""},
	"heartbloom_lamp": {"result": "heartbloom_lamp", "count": 1, "station": "workbench", "ingredients": {"glowcap": 2, "silk": 2, "wood": 2}, "unlock": "ward_restored"},
	# --- Campfire (cooking) --------------------------------------------------------------
	"hearty_stew": {"result": "hearty_stew", "count": 1, "station": "campfire", "ingredients": {"sweetroot": 2, "berries": 3}, "unlock": ""},
	"glowcap_skewer": {"result": "glowcap_skewer", "count": 1, "station": "campfire", "ingredients": {"glowcap": 2, "wood": 1}, "unlock": ""},
}

## Human readable station names.
const STATIONS := {"hand": "By Hand", "workbench": "Workbench", "campfire": "Campfire"}
