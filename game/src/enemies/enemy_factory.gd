extends RefCounted
## Creates enemies by id (data/enemies.gd). Used by spawners, the horror director and the dungeon.
##   var Factory = load("res://src/enemies/enemy_factory.gd")
##   var e: Node = Factory.spawn("gloomling", area, Transform3D(Basis.IDENTITY, pos), {"alert": true})
## params are passed to the enemy's setup() before it enters the tree:
##   ground enemies: {"home": Vector3, "wander_radius": float, "alert": bool, "no_drops": bool}
##   "weaver" (stalker): {"route": [Vector3...], "ambush_points": [...], "zone": "silk"}
##   "weaver_matron" (boss): {"arena_center": Vector3, "anchors": [Vector3...], "braziers": [Node...]}
## Chapter One additions (ground enemies, same params) - every enemy_base enemy also takes "defeat_flag"
## (a flag set once when it is defeated) and "damage_scale":
##   "brambleback", "lantern_moth", "hollow_drudge"
##   "brood_skitter" (+ "speed_scale": e.g. 0.8 for the Matron's slower Gentle minion)
##   "knotted_elder" (+ "arena_center": Vector3, "arena_radius": float, "reward_id": "rw_c1x_elder" | "")
## Scripts are loaded lazily and guarded: a missing or broken script returns null (warning), never a crash.

const SCRIPTS := {
	"brambling": "res://src/enemies/brambling.gd",
	"gloomling": "res://src/enemies/gloomling.gd",
	"weaver": "res://src/enemies/stalker.gd",
	"weaver_matron": "res://src/enemies/weaver_boss.gd",
	# Chapter One additions (Chapter Two expansion)
	"brambleback": "res://src/enemies/brambleback.gd",
	"lantern_moth": "res://src/enemies/lantern_moth.gd",
	"hollow_drudge": "res://src/enemies/hollow_drudge.gd",
	"brood_skitter": "res://src/enemies/brood_skitter.gd",
	"knotted_elder": "res://src/enemies/knotted_elder.gd",
	# Chapter Two ordinary archetypes + the Ashbell elite (module C5). Setup keys beyond the ground ones:
	#   "pumpkin_mimic" (+ "dormant": true = sits as a twitching pumpkin until inspected / approached)
	#   "quarry_warden" (+ "arena": node, "arena_center": Vector3, "arena_radius": float, "pillars": [quarry_pillar nodes])
	"pumpkin_mimic": "res://src/enemies/pumpkin_mimic.gd",
	"patchwalker": "res://src/enemies/patchwalker.gd",
	"velvet_wing": "res://src/enemies/velvet_wing.gd",
	"bellcap_sentry": "res://src/enemies/bellcap_sentry.gd",
	"borrowed_wisp": "res://src/enemies/borrowed_wisp.gd",
	"quarry_warden": "res://src/enemies/quarry_warden.gd",
	# Chapter Two boss (module C6a): Moonveil Manor's Count's Gallery. Setup keys: "arena_center", "arena_radius",
	# "candles" (ward_candle nodes), "teach_candle", "curtains", "fixture", "cover", "helper_points", "entry",
	# "area" (+ optional "mode": "story" | "trial", "auto_start", "seed") - see the header of count_velour.gd.
	"count_velour": "res://src/enemies/count_velour.gd",
	# Weaver's Crossing rematch (module C6b): the arena's boss_params() ({"arena", "arena_center", "arena_radius",
	# "anchors", "braziers", "crack", "bridge", "deck_y", "landing_points", "alert"}) - a NEW encounter, never the
	# Chapter One "weaver_matron" - see the header of crossing_matron.gd.
	"crossing_matron": "res://src/enemies/crossing_matron.gd",
	# Chapter Two final boss (module C6c): the Choir Vault's choir_arena.gd boss_params() ({"arena_center",
	# "arena_radius", "perimeter_radius", "anchors", "anchor_nodes", "resonators", "symbols", "arena", "alert"})
	# (+ optional "mode": "story" | "trial", "seed") - see the header of borrowed_choir.gd.
	"borrowed_choir": "res://src/enemies/borrowed_choir.gd",
}


static func has_enemy(enemy_id: String) -> bool:
	return SCRIPTS.has(enemy_id)


## Script path registered for an id ("" if unknown). Use this (or can_spawn) instead of indexing SCRIPTS with
## a constant key: a constant index into this const table is checked at compile time and breaks the caller's
## script when the id is not registered yet.
static func script_path(enemy_id: String) -> String:
	return String(SCRIPTS.get(enemy_id, ""))


## True when the id is registered AND its script exists and compiles (safe-load check for spawners).
static func can_spawn(enemy_id: String) -> bool:
	if not SCRIPTS.has(enemy_id):
		return false
	var path: String = SCRIPTS[enemy_id]
	if not ResourceLoader.exists(path):
		return false
	var script: Script = load(path)
	return script != null and script.can_instantiate()


## Spawns an enemy under `parent` at `xform` and returns it (null if the id or parent is invalid).
static func spawn(enemy_id: String, parent: Node, xform: Transform3D, params: Dictionary = {}) -> Node:
	if parent == null or not is_instance_valid(parent):
		push_warning("EnemyFactory: no parent for '%s'" % enemy_id)
		return null
	var node := create(enemy_id, params, xform.origin)
	if node == null:
		return null
	# Place it before _ready so self-positioning enemies (boss, stalker) can override it there.
	if node is Node3D:
		var local := xform
		if parent is Node3D and parent.is_inside_tree():
			local = (parent as Node3D).global_transform.affine_inverse() * xform
		(node as Node3D).transform = local
	parent.add_child(node)
	return node


## Builds the node (not yet in the tree) and calls setup(params).
static func create(enemy_id: String, params: Dictionary = {}, home: Vector3 = Vector3.ZERO) -> Node:
	if not SCRIPTS.has(enemy_id):
		push_warning("EnemyFactory: unknown enemy '%s'" % enemy_id)
		return null
	var path: String = SCRIPTS[enemy_id]
	if not ResourceLoader.exists(path):
		push_warning("EnemyFactory: missing script " + path)
		return null
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		push_error("EnemyFactory: script failed to load: " + path)
		return null
	var node: Node = script.new()
	node.name = "%s_%d" % [enemy_id.capitalize().replace(" ", ""), node.get_instance_id() % 100000]
	var p := params.duplicate()
	p["enemy"] = enemy_id
	if not p.has("home"):
		p["home"] = home
	if node.has_method("setup"):
		node.setup(p)
	return node


## Debug builds only: spawns enemies from the command line near the player, e.g.
##   --spawn-enemy=brambling:2,gloomling:1   (called by the debug harness / combat sandbox)
static func debug_spawn_from_args(parent: Node = null, around: Variant = null) -> Array:
	var out: Array = []
	if not Debug.is_cheat_allowed() or not Debug.has_arg("spawn-enemy"):
		return out
	var p: Node = parent
	if p == null:
		p = Game.area
	if p == null or not is_instance_valid(p):
		return out
	var center := Vector3.ZERO
	if around is Vector3:
		center = around
	elif Game.player != null and is_instance_valid(Game.player):
		center = Game.player.global_position
	var i := 0
	for entry in Debug.arg("spawn-enemy").split(",", false):
		var parts := String(entry).split(":")
		var n: int = int(parts[1]) if parts.size() > 1 else 1
		for k in n:
			var ang := 0.6 + float(i) * 0.9
			var pos := center + Vector3(sin(ang) * 6.0, 0.3, -cos(ang) * 6.0 - 2.0)
			var e := spawn(parts[0], p, Transform3D(Basis.IDENTITY, pos), {"home": pos, "wander_radius": 3.0})
			if e != null:
				out.append(e)
			i += 1
	return out
