extends RefCounted
## Krystal's wand model (Chapter Two, MP 5.1 Sparkseed Wand): a slim copper wand with a wooden grip, a brass
## collar and a glowing seed in a little copper cup at the tip, held in the right hand (the ToolAnchor, like the
## axe / pickaxe / sword). Purely visual and data-coloured (data/items.gd: `color` = the seed's cap,
## `projectile.color` = the glow). krystal_avatar.gd builds it LAZILY the first time a wand is held or cast, so an
## avatar that never holds a wand keeps the exact Chapter One mesh set (tests/unit/test_avatar_look_legacy.gd).
## No light (the spark itself carries the projectile's light), no collision.
##   var w: Node3D = WandBuilder.build(tool_anchor, "sparkseed_wand")   # "Wand" (hidden) with a child "Tip"

const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")

const NODE_NAME := "Wand"
const TIP_NAME := "Tip"
const DEFAULT_ID := "sparkseed_wand"
## Same hand orientation as the sword: the wand runs along the forearm, so a pointing arm aims it forward
## (about 22 degrees up) and a hanging arm carries it down along the leg.
const HOLD_ROT := Vector3(2.75, 0.0, 0.0)
const TIP_Y := 0.29                     # seed centre along the wand, metres from the grip centre
const GLOW_DEFAULT := Color("ffe08a")
const CAP_DEFAULT := Color("f2c14e")
const GLOW_ENERGY := 1.6


## Colours of a wand item: {"cap": Color, "glow": Color} (safe defaults for unknown ids).
static func style(item_id: String) -> Dictionary:
	var it: Dictionary = ItemDB.item(item_id) if item_id != "" and ItemDB.has_item(item_id) else {}
	var cap: Variant = it.get("color", CAP_DEFAULT)
	var glow: Variant = GLOW_DEFAULT
	var pd: Variant = it.get("projectile", {})
	if pd is Dictionary:
		glow = (pd as Dictionary).get("color", GLOW_DEFAULT)
	return {"cap": cap if cap is Color else CAP_DEFAULT, "glow": glow if glow is Color else GLOW_DEFAULT}


## Builds the wand under `anchor` (hidden; the avatar shows it). Parts are Kit primitives with Krystal's toon
## materials so the avatar's bake merges them like the other tools.
static func build(anchor: Node3D, item_id: String = DEFAULT_ID) -> Node3D:
	var st := style(item_id)
	var w := AKit.node(anchor, Vector3.ZERO, NODE_NAME)
	w.rotation = HOLD_ROT
	var copper := AKit.metal(Palette.COPPER)
	var brass := AKit.metal(AKit.BRASS)
	# Grip: dark wood with a round brass pommel and a brass collar where the copper starts.
	AKit.part(w, Kit.cylinder(0.016, 0.019, 0.1, AKit.m(Palette.WOOD_DARK), 10), Vector3(0, 0.0, 0))
	AKit.part(w, Kit.sphere(0.021, brass, 8, 12), Vector3(0, -0.058, 0))
	AKit.part(w, Kit.torus(0.012, 0.022, brass), Vector3(0, 0.052, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
	# Shaft: slim, gently tapering copper.
	AKit.part(w, Kit.cylinder(0.008, 0.012, 0.2, copper, 8), Vector3(0, 0.155, 0))
	# A small cup holding the seed, two sprout leaves and the seed's little cap (same material class as the grip,
	# so the avatar's bake merges them: the whole wand costs ~5 draw calls).
	AKit.part(w, Kit.cone(0.021, 0.035, copper, 10), Vector3(0, 0.27, 0), Vector3(180, 0, 0))
	var leaf := AKit.m(Palette.FOLIAGE_LIGHT)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(w, Kit.sphere(0.014, leaf, 8, 10), Vector3(0.02 * s, 0.268, 0.0), Vector3(0, 0, -32.0 * s), Vector3(1.7, 0.4, 0.85))
	AKit.part(w, Kit.sphere(0.022, AKit.m(st["cap"]), 8, 12), Vector3(0, TIP_Y + 0.026, 0), Vector3.ZERO, Vector3(1.25, 0.55, 1.25))
	# The seed: a soft glowing bead (own node: it swells briefly when a spark leaves it).
	var tip := AKit.node(w, Vector3(0, TIP_Y, 0), TIP_NAME)
	AKit.part(tip, Kit.sphere(0.03, Mat.glow(st["glow"], GLOW_ENERGY), 10, 14), Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.15, 0.9), false)
	w.visible = false
	return w
