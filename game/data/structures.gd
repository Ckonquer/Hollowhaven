extends RefCounted
## Placeable structure definitions (the Haven build system).
## Building is only allowed inside the Haven build area (see data/world_layout.gd BUILD_AREA).
## Fields:
##   name, item        display name and the item refunded on dismantle (100% refund)
##   layer             occupancy layer: "floor" | "decor" (rugs: furniture may stand on them) | "object" | "edge" | "roof"
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
## Chapter Two (docs/CHAPTER_TWO_SPEC.md 4.4; new entries are appended, legacy entries never change):
##   layer "stair" / snap "stair2"  stairs: 2x4 m footprint on the even 2 m grid (the stairwell is exactly two
##                     floor tiles), rot 0 rises toward -Z, entry landing at +Z. Ramp collision under the treads.
##   stairs            true: walkable stair piece (never counts as a movement blocker)
##   upper             true: placed one storey up (y = wall base + 3 m), resting on supports (walls, posts,
##                     support pieces or a supported neighbour tile)
##   support           true: counts as support for an upper floor above it (legacy walls count by rule)
##   level_ok          true: may also be placed on an upper floor (default false = ground storey only)
##   mount             "wall": a thin decoration whose model hugs the back edge (-Z) of its cell, so it sits
##                     flush against the wall panel behind it (curtains, flower boxes, bunting, trim). It can only be
##                     placed where a wall panel of its storey stands on that back edge (src/building/placement.gd
##                     mount_reason; build mode snaps it onto the nearest wall and turns its back to it), and that
##                     wall can't be taken down while something hangs on it
##   mount_on          wall pieces: the panel kinds it may hang on (default ["wall"]): "wall" (plain wall), "window"
##                     (round window walls), "arch" (arched window), "door" (doorway), "half" (half wall)
##   mount_centre      true: on a window panel the model shifts half a metre so it centres on the 2 m window (one per
##                     window side); on a plain wall it stays on its own cell
##   mount_pair        true: on a window panel the model is drawn as one half of a pair framing the window (curtains:
##                     one drape on the side away from the window, the rail running over it)
##   sill              true: sits under a window's sill, so it can't go on the front of the Chapter One Window Wall
##                     (that window has its own flower box there)
##   panel             edge pieces: what wall-mounted decor sees ("wall" | "window" | "arch" | "door" | "half"); the
##                     Chapter One walls are mapped in placement.gd (their entries never change)
##   tintable          true: can be recoloured in place with an unlocked dye palette (data.tint), uid kept. Only the
##                     piece's own colour family is dyed (wood, or its main colour), accents keep theirs (tints.gd)
##   tint_family       "main": recolouring dyes the piece's main colour even when it has some wood (companion bed)
##   interact          new values: "wardrobe" (mirror & wardrobe), "nook" (companion bed/perch), "board"
##                     (expedition board), "music" (music box), "face" (pumpkin lantern face picker)
##   queue             furnace: max queued jobs (data.queue / data.output live in the structure record)
##   faces             pumpkin lantern: selectable face ids (data.face; default the first); festival faces
##                     (FESTIVAL_FACES below) are appended to the choices once unlocked
##   alt_name          arachnophobia display name (same rule as items)

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
	"rug": {"name": "Woven Rug", "item": "rug", "layer": "decor", "snap": "cell", "size": Vector2i(2, 2), "height": 0.03, "solid": false, "interact": ""},
	"table": {"name": "Table", "item": "table", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": true, "interact": ""},
	"stool": {"name": "Stool", "item": "stool", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.5, "solid": false, "interact": ""},
	"pebble_cairn": {"name": "Pebble Cairn", "item": "pebble_cairn", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.7, "solid": false, "interact": ""},
	"echo_chime": {"name": "Echo Chime", "item": "echo_chime", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.0, "solid": false, "interact": ""},
	"heartbloom_lamp": {"name": "Heartbloom Lamp", "item": "heartbloom_lamp", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.6, "solid": false, "interact": "", "light": {"color": Color("ffb3c7"), "energy": 1.4, "range": 6.0}},
	"haven_banner": {"name": "Haven Banner", "item": "haven_banner", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.6, "solid": true, "interact": ""},
	# ======================== Chapter Two (append only) ========================
	# --- Two storeys: stairs, upper floor, railings, porches ---------------------------------------------
	"wood_stairs": {"name": "Wooden Stairs", "item": "wood_stairs", "layer": "stair", "snap": "stair2", "size": Vector2i(2, 4), "height": 3.0, "solid": true, "interact": "", "stairs": true, "tintable": true},
	"upper_floor": {"name": "Upper Floor", "item": "upper_floor", "layer": "floor", "snap": "floor2", "size": Vector2i(2, 2), "height": 0.2, "solid": true, "interact": "", "upper": true, "level_ok": true, "tintable": true},
	"wood_railing": {"name": "Railing", "item": "wood_railing", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 1.0, "solid": true, "interact": "", "level_ok": true, "tintable": true},
	"half_wall": {"name": "Half Wall", "item": "half_wall", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 1.2, "solid": true, "interact": "", "level_ok": true, "tintable": true, "panel": "half"},
	"porch_post": {"name": "Porch Post", "item": "porch_post", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 3.0, "solid": true, "interact": "", "support": true, "level_ok": true, "tintable": true},
	"arched_window": {"name": "Arched Window", "item": "arched_window", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": "", "support": true, "level_ok": true, "tintable": true, "panel": "arch"},
	"gable_roof": {"name": "Gable Roof", "item": "gable_roof", "layer": "roof", "snap": "roof2", "size": Vector2i(2, 2), "height": 1.8, "solid": true, "interact": "", "level_ok": true, "tintable": true},
	"roof_corner": {"name": "Roof Corner", "item": "roof_corner", "layer": "roof", "snap": "roof2", "size": Vector2i(2, 2), "height": 1.2, "solid": true, "interact": "", "level_ok": true, "tintable": true},
	# --- Cozy furniture -------------------------------------------------------------------------------------
	"flower_box": {"name": "Window Flower Box", "item": "flower_box", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.15, "solid": false, "interact": "", "mount": "wall", "level_ok": true, "tintable": true, "mount_on": ["wall", "window", "arch"], "mount_centre": true, "sill": true},
	"curtain": {"name": "Curtains", "item": "curtain", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.4, "solid": false, "interact": "", "mount": "wall", "level_ok": true, "tintable": true, "mount_on": ["wall", "window", "arch"], "mount_pair": true},
	"bookshelf": {"name": "Bookshelf", "item": "bookshelf", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 2.0, "solid": true, "interact": "", "level_ok": true, "tintable": true},
	"wardrobe": {"name": "Wardrobe", "item": "wardrobe", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 2.2, "solid": true, "interact": "wardrobe", "level_ok": true, "tintable": true},
	"vanity_mirror": {"name": "Vanity Mirror", "item": "vanity_mirror", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.8, "solid": true, "interact": "wardrobe", "level_ok": true, "tintable": true},
	"kitchen_counter": {"name": "Kitchen Counter", "item": "kitchen_counter", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 1.0, "solid": true, "interact": "station", "station": "kitchen", "level_ok": true, "tintable": true},
	"furnace": {"name": "Furnace", "item": "furnace", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 1.8, "solid": true, "interact": "station", "station": "furnace", "queue": 4,
		"light": {"color": Color("ff9a52"), "energy": 0.9, "range": 4.0}},
	"loom": {"name": "Loom & Dye Bench", "item": "loom", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 1.6, "solid": true, "interact": "station", "station": "loom", "level_ok": true, "tintable": true},
	"companion_bed": {"name": "Companion Bed", "item": "companion_bed", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.4, "solid": false, "interact": "nook", "level_ok": true, "tintable": true, "tint_family": "main"},
	"companion_perch": {"name": "Companion Perch", "item": "companion_perch", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.4, "solid": false, "interact": "nook", "level_ok": true, "tintable": true},
	"sturdy_planter": {"name": "Sturdy Planter", "item": "sturdy_planter", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 0.6, "solid": false, "interact": "farm", "tintable": true},
	"cottage_bench": {"name": "Cottage Bench", "item": "cottage_bench", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 0.9, "solid": true, "interact": "", "level_ok": true, "tintable": true},
	"music_box": {"name": "Music Box", "item": "music_box", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.6, "solid": false, "interact": "music", "level_ok": true, "tintable": true},
	"expedition_board": {"name": "Expedition Board", "item": "expedition_board", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 2.2, "solid": true, "interact": "board", "tintable": true},
	"lanternwake_table": {"name": "Lanternwake Table", "item": "lanternwake_table", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 0.9, "solid": true, "interact": "", "level_ok": true, "tintable": true,
		"light": {"color": Color("ffd08a"), "energy": 0.7, "range": 4.0}},
	# --- Lights and keepsakes (story / optional rewards) ---------------------------------------------------
	"wardlight": {"name": "Wardlight", "item": "wardlight", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.4, "solid": true, "interact": "", "level_ok": true,
		"light": {"color": Color("ffe2a0"), "energy": 1.5, "range": 7.0}},
	"miner_lamp": {"name": "Miner's Lamp", "item": "miner_lamp", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.6, "solid": false, "interact": "", "level_ok": true,
		"light": {"color": Color("ffc978"), "energy": 1.3, "range": 6.0}},
	"thread_veil": {"name": "Thread Veil", "alt_name": "Pale Veil Drape", "item": "thread_veil", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.4, "solid": false, "interact": "", "mount": "wall", "level_ok": true, "tintable": true, "mount_on": ["wall"]},
	# --- Halloween decor (optional; nothing here ever becomes hostile) ----------------------------------------
	"pumpkin_lantern": {"name": "Carved Pumpkin", "item": "pumpkin_lantern", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.6, "solid": false, "interact": "face", "level_ok": true,
		"faces": ["friendly", "sleepy", "toothy", "cat", "moon", "ghost"], "light": {"color": Color("ffae4a"), "energy": 1.1, "range": 5.0}},
	"pumpkin_lights": {"name": "Pumpkin String Lights", "item": "pumpkin_lights", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.4, "solid": false, "interact": "", "mount": "wall", "level_ok": true, "mount_on": ["wall", "window"],
		"light": {"color": Color("ffb862"), "energy": 0.7, "range": 4.0}},
	"bat_bunting": {"name": "Bat Bunting", "item": "bat_bunting", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.6, "solid": false, "interact": "", "mount": "wall", "level_ok": true, "tintable": true, "mount_on": ["wall", "window"]},
	"ghost_lantern": {"name": "Ghost Lantern", "item": "ghost_lantern", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.8, "solid": false, "interact": "", "level_ok": true,
		"light": {"color": Color("bcd6ff"), "energy": 1.4, "range": 5.5}},
	"crescent_window": {"name": "Crescent Window", "item": "crescent_window", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": "", "support": true, "level_ok": true, "tintable": true, "panel": "window"},
	"candy_bowl": {"name": "Candy Bowl", "item": "candy_bowl", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.5, "solid": false, "interact": "", "level_ok": true, "tintable": true},
	"scarecrow": {"name": "Scarecrow", "item": "scarecrow", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.2, "solid": true, "interact": ""},
	"gothic_trim": {"name": "Gothic Porch Trim", "item": "gothic_trim", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 3.0, "solid": false, "interact": "", "mount": "wall", "level_ok": true, "tintable": true, "mount_on": ["wall"]},
}

## Crops grown in crop plots. grow_minutes = in-game minutes from planting to ripe
## (1 real second = 1 in-game minute by default, see data/world_layout.gd CLOCK).
const CROPS := {
	"sweetroot": {"name": "Sweetroot", "seed": "sweetroot_seeds", "grow_minutes": 360.0, "stages": 4, "yield": {"sweetroot": [2, 3], "sweetroot_seeds": [1, 2]}},
	# Chapter Two crops (5-10 active minutes before blessing/tending; every harvest returns at least one seed,
	# so a plot keeps itself planted). `plants` = plants shown per 2x2 plot, `tint` = produce colour for visuals.
	"sunflax": {"name": "Sunflax", "seed": "sunflax_seeds", "grow_minutes": 420.0, "stages": 4, "yield": {"sunflax": [3, 4], "sunflax_seeds": [1, 2]}, "plants": 9, "tint": Color("f2cf62")},
	"roseberry": {"name": "Roseberry", "seed": "roseberry_seeds", "grow_minutes": 480.0, "stages": 4, "yield": {"roseberries": [3, 5], "roseberry_seeds": [1, 2]}, "plants": 4, "tint": Color("e0607e")},
	"pumpkin": {"name": "Pumpkin", "seed": "pumpkin_seeds", "grow_minutes": 600.0, "stages": 4, "yield": {"pumpkin": [1, 2], "pumpkin_seeds": [1, 3]}, "plants": 1, "tint": Color("f08a2e")},
}

## Faces a carved pumpkin can show (structure data.face). Cosmetic and reversible.
const PUMPKIN_FACES := ["friendly", "sleepy", "toothy", "cat", "moon", "ghost"]

## Festival faces (MP §17 ending reward "carved-lantern patterns"): face id -> unlock flag. Once the flag is set
## they join the END of a pumpkin's `faces` choices (src/building/pumpkin_faces.gd); they are never part of
## `faces` / PUMPKIN_FACES, so nothing earlier changes before the Lanternwake. ch2_feast = the final Chapter Two
## step (data/unlocks.gd). A saved festival face that is not unlocked is shown as the first face (data kept).
const FESTIVAL_FACES := {"starry": "ch2_feast", "lanternwake": "ch2_feast"}
