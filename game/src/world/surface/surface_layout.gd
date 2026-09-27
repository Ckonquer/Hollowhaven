extends RefCounted
## Surface-only layout details that extend data/world_layout.gd (which stays the shared source of truth
## for landmark centres, stream points, crossings and spawn hints). Coordinates: metres, x east, z south.

## Dirt paths from the Haven edge to every landmark (control points, smoothed with Catmull-Rom).
const PATHS := {
	"glade": [Vector2(-9, 2), Vector2(-19, 5), Vector2(-31, 9), Vector2(-42, 12), Vector2(-49, 12)],
	"ruin": [Vector2(-2, -13), Vector2(-4, -25), Vector2(-7, -39), Vector2(-10, -51), Vector2(-12, -58)],
	"mine": [Vector2(6, -12), Vector2(14, -22), Vector2(22, -30), Vector2(30, -40), Vector2(38, -50), Vector2(44, -58), Vector2(48, -63)],
	"quarry": [Vector2(11, -3), Vector2(17, -4.5), Vector2(21, -5), Vector2(28, -6), Vector2(40, -9), Vector2(51, -11), Vector2(58, -12)],
	"pond": [Vector2(9, 9), Vector2(17, 15), Vector2(24, 21), Vector2(28, 24), Vector2(33, 28), Vector2(39, 33), Vector2(44, 37)],
	"meadow": [Vector2(1, 13), Vector2(0, 23), Vector2(-3, 34), Vector2(-6, 45), Vector2(-8, 52)],
	"old_oak": [Vector2(-8, -9), Vector2(-17, -13), Vector2(-25, -17), Vector2(-29, -19)],
	"thicket": [Vector2(-39, -24), Vector2(-46, -31), Vector2(-52, -37), Vector2(-56, -41)],
	"loop": [Vector2(-3, 60), Vector2(8, 64), Vector2(20, 64), Vector2(29, 60), Vector2(33, 57)],
}
const PATH_HALF_WIDTH := 1.0
const PATH_EDGE := 1.0
const PATH_WIDTHS := {"loop": 0.85, "thicket": 0.85, "old_oak": 0.9}
## Paths leaving the Haven fade in over this many metres so they emerge naturally from the lawn.
const PATH_FADE_IN := {"glade": 7.0, "ruin": 7.0, "mine": 7.0, "quarry": 6.0, "pond": 7.0, "meadow": 7.0, "old_oak": 6.0, "thicket": 4.0, "loop": 4.0}
## Worn dirt patches: [centre, radius, strength].
const DIRT_PATCHES := [
	[Vector2(4, 3), 3.4, 1.0],          # campfire
	[Vector2(0, -6), 2.6, 0.55],        # in front of the Ward Stone (worn by visitors)
	[Vector2(51, -69), 6.5, 0.9],       # mine apron
	[Vector2(66, -12), 9.0, 0.55],      # quarry floor
	[Vector2(-12, -64), 5.0, 0.4],      # ruin courtyard
]

## Crossing styles, index-aligned with Layout.STREAM_CROSSINGS: (22,-30) mine path, (21,-5) quarry, (28,24) pond.
const CROSSING_STYLE := ["stones", "bridge", "bridge"]

## Stream end extends into Mirror Pond so the channel meets the water.
const STREAM_END := Vector2(41, 46)
const POND_RADIUS := 11.5

## Mine mouth: the tunnel faces toward the mine_exit spawn (south-west).
const MINE_MOUTH := Vector2(54, -74)
const MINE_FACING := Vector2(-6, 10)          # direction the entrance faces (normalised at use)

## Haven set pieces (inside the clearing).
const WARD_STONE := Vector2(0, -6)
const CAMPFIRE := Vector2(4, 3)
const SIGN := Vector2(-7.5, -14.5)

## Quarry terraces rise away from the quarry centre along this direction.
const QUARRY_TERRACE_DIR := Vector2(1.0, -0.55)

## Invisible boundary: a rounded square this far from the centre (the hills start rising around 92).
const BOUNDARY := 104.0
