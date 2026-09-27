extends RefCounted
## Placeable structure definitions (the Haven build system).
## Building is only allowed inside the Haven build area (see data/world_layout.gd BUILD_AREA).
## Fields:
##   name, item        display name and the item refunded on dismantle (100% refund)
##   layer             occupancy layer: "floor" | "object" | "edge" | "roof"
##   snap              "cell"   - footprint snapped to the 1 m grid (rotation 0/90/180/270)
##                     "floor2" - 2x2 m tile on the even 2 m grid
##                     "edge2"  - 2 m wall on a 2 m grid line (rotation 0 = along X, 90 = along Z)
##                     "roof2"  - 2x2 m roof tile on the even 2 m grid at wall height (3 m)
##   size              footprint in 1 m cells (x, z) at rotation 0
##   height            approximate height (m) used for collision/preview
##   solid             true = blocks movement (collision on layer "structure")
##   interact          "" | "storage" | "sleep" | "farm" | "station"
##   station           crafting station id provided when interact == "station"
##   light             optional {"color": Color, "energy": float, "range": float}

const STRUCTURES := {
	"workbench": {"name": "Workbench", "item": "workbench", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 1.0, "solid": true, "interact": "station", "station": "workbench"},
	"storage_chest": {"name": "Storage Chest", "item": "storage_chest", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": true, "interact": "storage", "slots": 20},
	"bed": {"name": "Cozy Bed", "item": "bed", "layer": "object", "snap": "cell", "size": Vector2i(1, 2), "height": 0.7, "solid": true, "interact": "sleep"},
	"crop_plot": {"name": "Crop Plot", "item": "crop_plot", "layer": "object", "snap": "cell", "size": Vector2i(2, 2), "height": 0.25, "solid": false, "interact": "farm"},
	"wood_floor": {"name": "Wooden Floor", "item": "wood_floor", "layer": "floor", "snap": "floor2", "size": Vector2i(2, 2), "height": 0.15, "solid": true, "interact": ""},
	"wood_wall": {"name": "Wooden Wall", "item": "wood_wall", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": ""},
	"wood_window": {"name": "Window Wall", "item": "wood_window", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": ""},
	"wood_doorway": {"name": "Doorway", "item": "wood_doorway", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": "", "passable": true},
	"wood_roof": {"name": "Roof Tile", "item": "wood_roof", "layer": "roof", "snap": "roof2", "size": Vector2i(2, 2), "height": 1.2, "solid": true, "interact": ""},
	"fence": {"name": "Picket Fence", "item": "fence", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.9, "solid": true, "interact": ""},
	"lantern_post": {"name": "Lantern Post", "item": "lantern_post", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.2, "solid": true, "interact": "", "light": {"color": Color("ffc978"), "energy": 1.6, "range": 7.0}},
	"flower_pot": {"name": "Flower Pot", "item": "flower_pot", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": false, "interact": ""},
	"rug": {"name": "Woven Rug", "item": "rug", "layer": "object", "snap": "cell", "size": Vector2i(2, 2), "height": 0.03, "solid": false, "interact": ""},
	"table": {"name": "Table", "item": "table", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": true, "interact": ""},
	"stool": {"name": "Stool", "item": "stool", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.5, "solid": false, "interact": ""},
	"pebble_cairn": {"name": "Pebble Cairn", "item": "pebble_cairn", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.7, "solid": false, "interact": ""},
	"echo_chime": {"name": "Echo Chime", "item": "echo_chime", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.0, "solid": false, "interact": ""},
	"heartbloom_lamp": {"name": "Heartbloom Lamp", "item": "heartbloom_lamp", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.6, "solid": false, "interact": "", "light": {"color": Color("ffb3c7"), "energy": 1.4, "range": 6.0}},
	"haven_banner": {"name": "Haven Banner", "item": "haven_banner", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.6, "solid": true, "interact": ""},
}

## Crops grown in crop plots. grow_minutes = in-game minutes from planting to ripe
## (1 real second = 1 in-game minute by default, see data/world_layout.gd CLOCK).
const CROPS := {
	"sweetroot": {"name": "Sweetroot", "seed": "sweetroot_seeds", "grow_minutes": 360.0, "stages": 4, "yield": {"sweetroot": [2, 3], "sweetroot_seeds": [1, 2]}},
}
