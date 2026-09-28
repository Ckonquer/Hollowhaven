extends Node3D
## Generic harvestable world node, shared by the surface and the Below: trees, rocks, ore veins,
## berry bushes, grass tufts, sticks, stones, glowcaps, silk clumps, crystals and rubble piles.
## Implements the interaction/harvest contract from docs/ARCHITECTURE.md:
##   groups "harvestable" (+ "interactable" for hand kinds) and "resource_node",
##   a StaticBody3D on layer 16 (interact) in its subtree (child "Interact"),
##   get_harvest_info(), harvest_hit(player, tool_item_id), get_interaction(player), interact(player).
## Depletion persists through GameState.deplete(node_id, respawn_minutes) with a STABLE node_id;
## on load the node checks GameState.is_depleted(node_id) and shows its depleted look instantly.
##
## Usage (call setup BEFORE add_child):
##   const ResourceNode := preload("res://src/world/common/resource_node.gd")
##   var n: Node3D = ResourceNode.new()
##   n.setup({"node_id": "rock_4", "kind": "rock"})      # everything else defaults from KIND_DEFAULTS
##   parent.add_child(n)
##   n.global_position = pos
##
## setup(params) keys (all optional except node_id, which must be stable across runs):
##   node_id: String          persistence id ("" = not persistent; respawns on a local timer)
##   kind: String             tree|rock|ore|bush|grass|stick|stone|glowcap|silk|crystal|rubble
##   tool: String             "axe" | "pickaxe" | "hand"
##   hits: int                hits needed (each hit counts the tool's ItemDB "power")
##   drops: Array             [{"item": "wood", "min": 3, "max": 5, "chance": 1.0}, ...]
##   respawn_minutes: float   in-game minutes until it comes back; < 0 = never (quest rubble)
##   visual: Node3D | String  custom visual node (used as-is) or a NodeVisuals id ("oak", "rubble", ...)
##                            Custom visuals may contain "Top"+"Stump" (trees) / "Berries" (bushes)
##                            and the metadata documented in node_visuals.gd (sensible defaults otherwise).
##   name: String             display name ("Oak Tree")
##   seed: int                variant of the built-in visual
##   scale: float             uniform scale of the whole node (visual + colliders)
##   yaw: float               rotation in degrees
##   tint: Color              rock colour for boulder/rubble/pebble visuals (e.g. Palette.MINE_ROCK)
##   solid: bool              blocks movement (default true for tree/rock/ore/crystal/rubble)
##   flag: String             GameState flag set when depleted by the player (e.g. "mine_opened")
##   counter: String          GameState counter incremented when depleted (trees: "trees_felled")
##   hit_sound, break_sound: String   Audio names;  fx: String particle kind (see fx.gd)
##   glow_light: bool         adds a small shadowless OmniLight3D (glowcaps / crystals in the dark)
##   verb: String             prompt verb for hand harvesting ("Pick up", "Pull", "Pick", "Gather")
##   min_tier: int            lowest tool tier that can harvest it (stone 1, copper 2, ironwood 3, moonsteel 4;
##                            ItemDB.item_tier). 0 = any tool of the right kind (every legacy kind).
## Chapter Two (equipment module):
##   * kinds from data/sources.gd NODES that are not legacy kinds ("iron_vein", "moon_crystal_vein",
##     "sap_stump", "sunflax_patch", ...) take tool / min_tier / hits / drops / respawn / name / verb from the
##     data and the look + behaviour of a legacy base kind (DATA_KIND_BASE); pass `visual` for a custom look.
##   * each hit adds StatsLayer.harvest_power(tool) = tool power x (1 + gather bonus): stone tools (power 1) keep
##     the legacy hit counts exactly (tree 4, rock 3, ore 4, crystal 3, rubble 4); copper / ironwood /
##     moonsteel tools (1.5 / 2 / 2.5) need fewer hits; the Gatherer's Charm and Gathering mastery add a little.
##   * a tool below min_tier (stored in `required_tier`) only wobbles the node and explains which tier is needed.
##   * Gathering mastery's bonus_yield_chance may add +1 of the main drop (never when the chance is 0, so
##     legacy drop rolls are unchanged).
## Signals: harvested_out(node) when fully harvested by the player; respawned(node).

const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Fx := preload("res://src/world/common/fx.gd")
const Palette := preload("res://src/art/palette.gd")
const StatsLayer := preload("res://src/core/stats.gd")
const EquipmentRules := preload("res://data/equipment.gd")

const LAYER_WORLD := 1
const LAYER_INTERACT := 16
const RESPAWN_CHECK_SECONDS := 2.0
const HIT_MEMORY_MS := 30000          # partial damage heals after 30 s without hits

const KIND_DEFAULTS := {
	"tree": {"tool": "axe", "hits": 4, "drops": [{"item": "wood", "min": 3, "max": 5, "chance": 1.0}],
		"respawn_minutes": 1440.0, "name": "Tree", "visual": "oak", "solid": true, "counter": "trees_felled",
		"hit_sound": "chop", "break_sound": "tree_fall", "fx": "leaves", "verb": "Chop"},
	"rock": {"tool": "pickaxe", "hits": 3, "drops": [{"item": "stone", "min": 2, "max": 4, "chance": 1.0}],
		"respawn_minutes": 1440.0, "name": "Boulder", "visual": "boulder", "solid": true,
		"hit_sound": "mine_hit", "break_sound": "rock_break", "fx": "chips", "verb": "Mine"},
	"ore": {"tool": "pickaxe", "hits": 4, "drops": [{"item": "copper_ore", "min": 2, "max": 3, "chance": 1.0}, {"item": "stone", "min": 1, "max": 1, "chance": 1.0}],
		"respawn_minutes": 1440.0, "name": "Copper Vein", "visual": "copper_vein", "solid": true,
		"hit_sound": "mine_hit", "break_sound": "rock_break", "fx": "copper", "verb": "Mine"},
	"bush": {"tool": "hand", "hits": 1, "drops": [{"item": "berries", "min": 2, "max": 4, "chance": 1.0}, {"item": "sweetroot_seeds", "min": 1, "max": 1, "chance": 0.25}],
		"respawn_minutes": 720.0, "name": "Berry Bush", "visual": "berry_bush", "solid": false,
		"hit_sound": "berry_pick", "break_sound": "", "fx": "berries", "verb": "Pick"},
	"grass": {"tool": "hand", "hits": 1, "drops": [{"item": "fiber", "min": 1, "max": 2, "chance": 1.0}],
		"respawn_minutes": 480.0, "name": "Tall Grass", "visual": "grass_tuft", "solid": false,
		"hit_sound": "grass_pull", "break_sound": "", "fx": "grass", "verb": "Pull"},
	"stick": {"tool": "hand", "hits": 1, "drops": [{"item": "wood", "min": 1, "max": 1, "chance": 1.0}],
		"respawn_minutes": 600.0, "name": "Stick", "visual": "stick", "solid": false,
		"hit_sound": "pickup", "break_sound": "", "fx": "leaves", "verb": "Pick up"},
	"stone": {"tool": "hand", "hits": 1, "drops": [{"item": "stone", "min": 1, "max": 1, "chance": 1.0}],
		"respawn_minutes": 600.0, "name": "Stone", "visual": "pebble", "solid": false,
		"hit_sound": "pickup", "break_sound": "", "fx": "dust", "verb": "Pick up"},
	"glowcap": {"tool": "hand", "hits": 1, "drops": [{"item": "glowcap", "min": 1, "max": 2, "chance": 1.0}],
		"respawn_minutes": 1440.0, "name": "Glowcaps", "visual": "glowcap", "solid": false,
		"hit_sound": "pickup", "break_sound": "", "fx": "sparkle", "verb": "Gather"},
	"silk": {"tool": "hand", "hits": 1, "drops": [{"item": "silk", "min": 1, "max": 2, "chance": 1.0}],
		"respawn_minutes": 1440.0, "name": "", "visual": "silk", "solid": false,
		"hit_sound": "grass_pull", "break_sound": "", "fx": "silk", "verb": "Gather"},
	"crystal": {"tool": "pickaxe", "hits": 3, "drops": [{"item": "echo_shard", "min": 1, "max": 2, "chance": 1.0}],
		"respawn_minutes": 1440.0, "name": "Echo Crystal", "visual": "crystal", "solid": true,
		"hit_sound": "mine_hit", "break_sound": "rock_break", "fx": "crystal", "verb": "Mine"},
	"rubble": {"tool": "pickaxe", "hits": 4, "drops": [{"item": "stone", "min": 2, "max": 3, "chance": 1.0}],
		"respawn_minutes": -1.0, "name": "Rubble", "visual": "rubble", "solid": true,
		"hit_sound": "mine_hit", "break_sound": "rock_break", "fx": "chips", "verb": "Clear"},
}

## Legacy base kind (look, colliders, depletion behaviour) of the data/sources.gd node kinds that are not
## legacy kinds themselves. Unknown data kinds fall back by tool (axe -> tree, pickaxe -> rock, hand -> grass).
const DATA_KIND_BASE := {
	"iron_vein": "ore", "moon_crystal_vein": "crystal", "sap_stump": "stick", "sunflax_patch": "grass",
	"roseberry_bush": "bush", "sugarcap_patch": "glowcap", "moonpetal_patch": "grass", "pumpkin_vine": "bush",
}
## Data fields a data kind takes over from data/sources.gd NODES.
const DATA_KIND_FIELDS := ["tool", "hits", "drops", "respawn_minutes", "name", "verb"]

## Fallback collider metadata when a custom visual carries none.
const META_DEFAULTS := {
	"tree": {"solid": "cylinder", "solid_radius": 0.45, "solid_height": 3.0, "interact_radius": 0.9, "interact_y": 1.2, "fx_height": 3.5},
	"rock": {"solid": "cylinder", "solid_radius": 0.9, "solid_height": 1.2, "interact_radius": 1.35, "interact_y": 0.6, "fx_height": 0.8},
	"small": {"solid": "none", "interact_radius": 0.6, "interact_y": 0.3, "fx_height": 0.3},
}

signal harvested_out(node: Node3D)
signal respawned(node: Node3D)

var node_id: String = ""
var kind: String = "rock"
var base_kind: String = "rock"          # legacy kind whose look/behaviour this node uses (== kind for legacy kinds)
var tool: String = "pickaxe"
var hits: int = 3
var required_tier: int = 0            # setup key "min_tier" (own name, so subclasses may declare their own min_tier)
var drops: Array = []
var respawn_minutes: float = 1440.0
var display_name: String = "Boulder"
var depleted: bool = false
var params: Dictionary = {}

var _is_setup := false
var _def: Dictionary = {}               # resolved defaults (KIND_DEFAULTS[kind] for legacy kinds)
var _visual: Node3D
var _visual_scale := Vector3.ONE
var _solid_body: StaticBody3D
var _solid_shape: CollisionShape3D
var _interact_body: StaticBody3D
var _light: OmniLight3D
var _damage := 0.0
var _last_hit_ms := 0
var _busy := false
var _check_t := 0.0
var _local_respawn_at := -1.0
var _warn_ms := -100000
var _wobble_tw: Tween
var _anim_tw: Tween


## Configures the node (see header). Call before add_child; calling later rebuilds it.
func setup(p: Dictionary) -> void:
	params = p.duplicate()
	kind = String(params.get("kind", "rock"))
	_resolve_kind()
	var def: Dictionary = _def
	node_id = String(params.get("node_id", ""))
	tool = String(params.get("tool", def["tool"]))
	hits = maxi(1, int(params.get("hits", def["hits"])))
	drops = (params.get("drops", def["drops"]) as Array).duplicate(true)
	respawn_minutes = float(params.get("respawn_minutes", def["respawn_minutes"]))
	display_name = String(params.get("name", def["name"]))
	required_tier = maxi(0, int(params.get("min_tier", def.get("min_tier", 0))))
	if display_name == "" and base_kind == "silk":
		display_name = ItemDB.display_name("silk")
	_is_setup = true
	if is_inside_tree():
		_build()


## kind -> base_kind + resolved defaults. Legacy kinds use KIND_DEFAULTS untouched.
func _resolve_kind() -> void:
	if KIND_DEFAULTS.has(kind):
		base_kind = kind
		_def = KIND_DEFAULTS[kind]
		return
	var data: Dictionary = ItemDB.node_kind(kind)
	if data.is_empty():
		push_warning("ResourceNode: unknown kind '%s', using rock" % kind)
		kind = "rock"
		base_kind = "rock"
		_def = KIND_DEFAULTS["rock"]
		return
	var t := String(data.get("tool", "hand"))
	base_kind = String(DATA_KIND_BASE.get(kind, "tree" if t == "axe" else ("rock" if t == "pickaxe" else "grass")))
	var d: Dictionary = (KIND_DEFAULTS[base_kind] as Dictionary).duplicate(true)
	d["counter"] = ""
	for f in DATA_KIND_FIELDS:
		if data.has(f):
			d[f] = data[f]
	if bool(Settings.get_value("arachnophobia")) and data.has("alt_name"):
		d["name"] = data["alt_name"]
	d["min_tier"] = int(data.get("min_tier", 0))
	_def = d


func _ready() -> void:
	if not _is_setup:
		setup({})
	if params.has("yaw"):
		rotation.y = deg_to_rad(float(params["yaw"]))
	if params.has("scale"):
		scale = Vector3.ONE * float(params["scale"])
	add_to_group("resource_node")
	_build()
	if base_kind == "silk" and not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func _build() -> void:
	for c in get_children():
		if c == _visual or c == _solid_body or c == _interact_body or c == _light:
			remove_child(c)
			c.queue_free()
	_visual = null
	_solid_body = null
	_interact_body = null
	_light = null
	depleted = false
	_busy = false
	_build_visual()
	_build_colliders()
	if bool(params.get("glow_light", false)):
		_light = OmniLight3D.new()
		_light.name = "Glow"
		_light.light_color = Palette.GLOWCAP if base_kind != "crystal" else Color("c9b5ff")
		_light.light_energy = 0.7
		_light.omni_range = 3.5
		_light.shadow_enabled = false
		_light.position = Vector3(0, 0.5, 0)
		add_child(_light)
	_set_groups(true)
	if node_id != "" and GameState.is_depleted(node_id):
		_apply_depleted(false, Vector3.FORWARD)
	set_process(depleted)


func _build_visual() -> void:
	var v: Variant = params.get("visual", _def["visual"])
	if v is Node3D:
		_visual = v
		if _visual.get_parent() != null:
			_visual.get_parent().remove_child(_visual)
	else:
		var opts := {}
		if params.has("tint"):
			opts["tint"] = params["tint"]
		if base_kind == "silk":
			opts["arachno"] = bool(Settings.get_value("arachnophobia"))
		_visual = NodeVisuals.build(String(v), int(params.get("seed", 0)), opts)
	_visual.name = "Visual"
	add_child(_visual)
	_visual_scale = _visual.scale


func _meta(key: String) -> Variant:
	if _visual != null and _visual.has_meta(key):
		return _visual.get_meta(key)
	var group := "small"
	if base_kind == "tree":
		group = "tree"
	elif base_kind in ["rock", "ore", "crystal", "rubble"]:
		group = "rock"
	return META_DEFAULTS[group].get(key, 0.0)


func _build_colliders() -> void:
	var def: Dictionary = _def
	var want_solid := bool(params.get("solid", def["solid"]))
	var solid_kind := String(_meta("solid"))
	if want_solid and solid_kind != "none":
		_solid_body = StaticBody3D.new()
		_solid_body.name = "Solid"
		_solid_body.collision_layer = LAYER_WORLD
		_solid_body.collision_mask = 0
		_solid_body.set_meta("surface", "wood" if base_kind == "tree" else "stone")
		_solid_shape = CollisionShape3D.new()
		_solid_body.add_child(_solid_shape)
		add_child(_solid_body)
		_set_full_solid_shape()
	_interact_body = StaticBody3D.new()
	_interact_body.name = "Interact"
	_interact_body.collision_layer = LAYER_INTERACT
	_interact_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var r := float(_meta("interact_radius"))
	var y := float(_meta("interact_y"))
	if base_kind == "tree":
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = 3.4
		cs.shape = cap
		cs.position = Vector3(0, 1.7, 0)
	else:
		var sph := SphereShape3D.new()
		sph.radius = r
		cs.shape = sph
		cs.position = Vector3(0, y, 0)
	_interact_body.add_child(cs)
	add_child(_interact_body)


func _set_full_solid_shape() -> void:
	if _solid_shape == null:
		return
	if String(_meta("solid")) == "convex" and _meta("convex") is Shape3D:
		_solid_shape.shape = _meta("convex")
		_solid_shape.position = Vector3.ZERO
		_solid_shape.transform = _visual.transform
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = float(_meta("solid_radius"))
		cyl.height = float(_meta("solid_height"))
		_solid_shape.shape = cyl
		_solid_shape.position = Vector3(0, cyl.height * 0.5, 0)


func _set_stump_shape() -> void:
	if _solid_shape == null:
		return
	var cyl := CylinderShape3D.new()
	cyl.radius = float(_visual.get_meta("stump_radius", 0.4)) if _visual != null else 0.4
	cyl.height = float(_visual.get_meta("stump_height", 0.55)) if _visual != null else 0.55
	_solid_shape.shape = cyl
	_solid_shape.position = Vector3(0, cyl.height * 0.5, 0)


func _set_groups(active: bool) -> void:
	if active:
		add_to_group("harvestable")
		if tool == "hand":
			add_to_group("interactable")
	else:
		if is_in_group("harvestable"):
			remove_from_group("harvestable")
		# Picked bushes stay focusable so the prompt can say they are regrowing.
		if base_kind != "bush" and is_in_group("interactable"):
			remove_from_group("interactable")


# --- Contract --------------------------------------------------------------------------------

func get_harvest_info() -> Dictionary:
	return {"tool": tool, "name": display_name, "kind": kind, "hits": hits, "depleted": depleted,
		"progress": clampf(_damage / float(hits), 0.0, 1.0), "min_tier": required_tier}


func get_interaction(_player: Node = null) -> Dictionary:
	if depleted:
		if base_kind == "bush":
			return {"text": "%s (regrowing)" % display_name, "enabled": false}
		return {}
	var verb := String(params.get("verb", _def["verb"]))
	if tool == "hand":
		return {"text": "%s %s" % [verb, display_name], "enabled": true}
	if StatsLayer.best_tool(tool, required_tier) != "":
		return {"text": "%s %s" % [verb, display_name], "enabled": true}
	return {"text": "%s - %s" % [display_name, _need_text()], "enabled": false, "reason": _need_text()}


func interact(player: Node = null) -> void:
	if tool == "hand":
		harvest_hit(player, "")
	else:
		var best := StatsLayer.best_tool(tool, required_tier)
		if best != "":
			harvest_hit(player, best)
		else:
			_warn_tool()


## True when `tool_item_id` is the right kind of tool and meets required_tier (hand nodes: always).
func tool_can_harvest(tool_item_id: String) -> bool:
	if tool == "hand":
		return true
	if tool_item_id == "" or not ItemDB.has_item(tool_item_id):
		return false
	if String(ItemDB.item(tool_item_id).get("tool", "")) != tool:
		return false
	return required_tier <= 0 or ItemDB.item_tier(tool_item_id) >= required_tier


## Hits a tool needs to finish this node from scratch (-1 = it can't). Tests / UI hints.
func hits_needed(tool_item_id: String) -> int:
	if tool == "hand":
		return hits
	if not tool_can_harvest(tool_item_id):
		return -1
	var pw := StatsLayer.harvest_power(tool_item_id)
	var n := 0
	var acc := 0.0
	while acc < float(hits) - 0.001 and n < 1000:
		acc += pw
		n += 1
	return n


## One harvesting action. Hand kinds ignore tool_item_id. Wrong/missing tools only wobble + warn.
func harvest_hit(player: Node, tool_item_id: String = "") -> void:
	if depleted or _busy:
		return
	var dir := _hit_dir(player)
	var power := 1.0
	if tool != "hand":
		var tdef: Dictionary = ItemDB.item(tool_item_id) if tool_item_id != "" and ItemDB.has_item(tool_item_id) else {}
		if String(tdef.get("tool", "")) != tool:
			_warn_tool()
			_wobble(dir, 0.4)
			return
		if required_tier > 0 and ItemDB.item_tier(tool_item_id) < required_tier:
			_warn_tool()
			_wobble(dir, 0.4)
			return
		power = StatsLayer.harvest_power(tool_item_id)
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms > HIT_MEMORY_MS:
		_damage = 0.0
	_last_hit_ms = now
	_damage += power
	var done := _damage >= float(hits) - 0.001
	_hit_feedback(dir, done)
	if done:
		_complete(dir)


## Rolls this node's drop table: {item_id: count}. Chance/min/max per entry; zero counts omitted.
func roll_drops() -> Dictionary:
	var out := {}
	for d in drops:
		if not (d is Dictionary):
			continue
		var item := String(d.get("item", ""))
		if item == "" or not ItemDB.has_item(item):
			continue
		if randf() > float(d.get("chance", 1.0)):
			continue
		var n := randi_range(int(d.get("min", 1)), maxi(int(d.get("min", 1)), int(d.get("max", 1))))
		if n > 0:
			out[item] = int(out.get(item, 0)) + n
	return out


func _complete(dir: Vector3) -> void:
	_damage = 0.0
	var drop_pos := global_position + Vector3.UP * 0.6
	var got := roll_drops()
	_bonus_yield(got)
	for item in got:
		var n: int = got[item]
		# The "+3 Wood" pop comes from the HUD, which aggregates Events.item_added (emitted by give_item);
		# an extra Events.notify here would show every harvest twice.
		GameState.give_item(item, n, drop_pos)
		Events.harvested.emit(kind, item, n, global_position)
	if node_id != "":
		GameState.deplete(node_id, respawn_minutes)
	else:
		_local_respawn_at = GameState.total_minutes + respawn_minutes if respawn_minutes >= 0.0 else -1.0
	var flag := String(params.get("flag", ""))
	if flag != "":
		GameState.set_flag(flag, true)
	var counter := String(params.get("counter", _def.get("counter", "")))
	if counter != "":
		GameState.add_counter(counter)
	if base_kind == "tree":
		Events.tree_felled.emit(global_position)
	var bs := String(params.get("break_sound", _def["break_sound"]))
	if bs != "":
		Audio.play_3d(bs, global_position + Vector3.UP * 0.5, 0.0)
	_apply_depleted(true, dir)
	harvested_out.emit(self)


## Gathering mastery: a chance of +1 of the main drop (the first drop entry that was rolled). No random
## number is drawn while the chance is 0, so legacy drop rolls stay exactly as they were.
func _bonus_yield(got: Dictionary) -> void:
	var chance := StatsLayer.bonus_yield_chance()
	if chance <= 0.0 or got.is_empty() or randf() >= chance:
		return
	for d in drops:
		if d is Dictionary and got.has(String(d.get("item", ""))):
			var item := String(d["item"])
			got[item] = int(got[item]) + 1
			return


# --- Depletion & respawn ------------------------------------------------------------------------

func _apply_depleted(animate: bool, dir: Vector3) -> void:
	depleted = true
	_set_groups(false)
	if _interact_body != null and base_kind != "bush":
		_interact_body.collision_layer = 0
	if _light != null:
		_light.visible = false
	match base_kind:
		"tree":
			_fell(animate, dir)
		"bush":
			var berries := _visual.get_node_or_null("Berries") as Node3D
			if berries != null:
				_kill_anim()
				if animate:
					_anim_tw = create_tween()
					_anim_tw.tween_property(berries, "scale", Vector3.ONE * 0.01, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					_anim_tw.tween_callback(func() -> void:
						berries.visible = false
						berries.scale = Vector3.ONE)
				else:
					berries.visible = false
		_:
			if _solid_body != null:
				_solid_body.collision_layer = 0
			_kill_anim()
			if animate:
				_busy = true
				_anim_tw = create_tween()
				_anim_tw.tween_property(_visual, "scale", _visual_scale * Vector3(1.18, 0.72, 1.18), 0.07)
				_anim_tw.tween_property(_visual, "scale", _visual_scale * 0.01, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				_anim_tw.tween_callback(func() -> void:
					_visual.visible = false
					_visual.scale = _visual_scale
					_busy = false)
			else:
				_visual.visible = false
	_check_t = 0.0
	set_process(true)


func _fell(animate: bool, dir: Vector3) -> void:
	var top := _visual.get_node_or_null("Top") as Node3D
	var stump := _visual.get_node_or_null("Stump") as Node3D
	_set_stump_shape()
	if stump != null:
		stump.visible = true
	if top == null:
		_visual.visible = animate
		return
	_kill_anim()
	if not animate:
		top.visible = false
		return
	_busy = true
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	axis = (_visual.global_transform.basis.inverse() * axis.normalized()).normalized()
	var fall := deg_to_rad(86.0)
	var fx_h := float(_meta("fx_height"))
	var leaf_fx := "blossom" if String(params.get("visual", "")) == "blossom" else "leaves"
	var set_fall := func(a: float) -> void:
		if is_instance_valid(top):
			top.transform.basis = Basis(axis, a)
	_anim_tw = create_tween()
	_anim_tw.tween_method(set_fall, 0.0, fall, 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tw.tween_callback(func() -> void:
		var land := top.global_transform * Vector3(0, fx_h, 0)
		Fx.burst(get_parent(), land, leaf_fx, 1.4)
		Fx.burst(get_parent(), land - Vector3(0, fx_h * 0.3, 0), "dust", 1.2)
		_shake_if_near(0.22, 0.3))
	_anim_tw.tween_method(set_fall, fall, fall - 0.08, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_anim_tw.tween_method(set_fall, fall - 0.08, fall, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_anim_tw.tween_interval(0.35)
	_anim_tw.tween_property(top, "scale", Vector3.ONE * 0.02, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_anim_tw.tween_callback(func() -> void:
		Fx.burst(get_parent(), global_position + dir * 2.0 + Vector3.UP * 0.4, "dust", 0.8)
		top.visible = false
		top.scale = Vector3.ONE
		top.transform.basis = Basis()
		_busy = false)


## Brings the node back (respawn). animate = grow in.
func restore(animate: bool = true) -> void:
	if not depleted:
		return
	depleted = false
	_damage = 0.0
	_local_respawn_at = -1.0
	_kill_anim()
	_busy = false
	_set_groups(true)
	if _interact_body != null:
		_interact_body.collision_layer = LAYER_INTERACT
	if _solid_body != null:
		_solid_body.collision_layer = LAYER_WORLD
		_set_full_solid_shape()
	if _light != null:
		_light.visible = true
	var grow: Node3D = _visual
	match base_kind:
		"tree":
			var top := _visual.get_node_or_null("Top") as Node3D
			var stump := _visual.get_node_or_null("Stump") as Node3D
			_visual.visible = true
			if stump != null:
				stump.visible = false
			if top != null:
				top.visible = true
				top.transform.basis = Basis()
				grow = top
		"bush":
			var berries := _visual.get_node_or_null("Berries") as Node3D
			if berries != null:
				berries.visible = true
				grow = berries
		_:
			_visual.visible = true
	if animate and grow != null:
		var target := grow.scale if grow != _visual else _visual_scale
		grow.scale = target * 0.05
		_anim_tw = create_tween()
		_anim_tw.tween_property(grow, "scale", target, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	set_process(false)
	respawned.emit(self)


func _process(delta: float) -> void:
	if not depleted:
		set_process(false)
		return
	_check_t += delta
	if _check_t < RESPAWN_CHECK_SECONDS or _busy:
		return
	_check_t = 0.0
	if not can_respawn_now():
		return
	restore(true)


## True when the respawn time has passed and nobody stands where the node would reappear.
func can_respawn_now() -> bool:
	if node_id != "":
		if GameState.is_depleted(node_id):
			return false
	elif _local_respawn_at < 0.0 or GameState.total_minutes < _local_respawn_at:
		return false
	if _solid_body != null or base_kind == "tree":
		for p in get_tree().get_nodes_in_group("player"):
			if p is Node3D and (p as Node3D).global_position.distance_to(global_position) < 2.2:
				return false
		for c in get_tree().get_nodes_in_group("companion"):
			if c is Node3D and (c as Node3D).global_position.distance_to(global_position) < 1.6:
				return false
	return true


# --- Feedback --------------------------------------------------------------------------------------

func _hit_dir(player: Node) -> Vector3:
	var d := Vector3.FORWARD
	if player != null and is_instance_valid(player) and player is Node3D:
		d = global_position - (player as Node3D).global_position
		d.y = 0.0
		if d.length() < 0.01:
			d = Vector3.FORWARD
	return d.normalized()


func _hit_feedback(dir: Vector3, final_hit: bool) -> void:
	var def: Dictionary = _def
	var hs := String(params.get("hit_sound", def["hit_sound"]))
	if hs != "":
		Audio.play_3d(hs, global_position + Vector3.UP * 0.8, -2.0)
	var fx_kind := String(params.get("fx", def["fx"]))
	if base_kind == "tree" and String(params.get("visual", "")) == "blossom":
		fx_kind = "blossom"
	var fx_h := float(_meta("fx_height")) * scale.y
	if base_kind == "tree":
		Fx.burst(get_parent(), global_position + Vector3.UP * fx_h, fx_kind, 0.7)
		Fx.burst(get_parent(), global_position + Vector3.UP * 1.1 - dir * 0.4, "chips", 0.5, -dir + Vector3.UP * 0.5)
	elif fx_kind != "":
		Fx.burst(get_parent(), global_position + Vector3.UP * fx_h, fx_kind, 1.0 if final_hit or tool != "hand" else 0.7)
	if tool != "hand":
		_shake_if_near(0.06, 0.1)
	if not final_hit or base_kind in ["tree", "bush"]:
		_wobble(dir, 1.0)


func _wobble(dir: Vector3, strength: float) -> void:
	if _visual == null:
		return
	if _wobble_tw != null and _wobble_tw.is_valid():
		_wobble_tw.kill()
	var target: Node3D = _visual
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	axis = (global_transform.basis.inverse() * axis.normalized()).normalized()
	var amp := deg_to_rad(5.0 if base_kind == "tree" else 7.0) * strength
	var base_basis := Basis().scaled(_visual_scale)
	var set_rot := func(a: float) -> void:
		if is_instance_valid(target):
			target.transform.basis = Basis(axis, a) * base_basis
	_wobble_tw = create_tween()
	_wobble_tw.tween_method(set_rot, 0.0, amp, 0.06)
	_wobble_tw.tween_method(set_rot, amp, -amp * 0.6, 0.12)
	_wobble_tw.tween_method(set_rot, -amp * 0.6, 0.0, 0.16).set_trans(Tween.TRANS_SINE)
	if base_kind != "tree":
		var sq := create_tween()
		sq.tween_property(target, "scale", _visual_scale * Vector3(1.08, 0.9, 1.08), 0.05)
		sq.tween_property(target, "scale", _visual_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill_anim() -> void:
	if _anim_tw != null and _anim_tw.is_valid():
		_anim_tw.kill()
	_anim_tw = null


func _shake_if_near(strength: float, duration: float) -> void:
	var p: Node = Game.player if Game.player != null and is_instance_valid(Game.player) else null
	if p is Node3D and (p as Node3D).global_position.distance_to(global_position) < 14.0:
		Events.camera_shake.emit(strength, duration)


func _need_text() -> String:
	if required_tier > 1:
		return "needs %s or better" % tier_tool_name(tool, required_tier)
	return "needs an axe" if tool == "axe" else "needs a pickaxe"


## "an Ironwood Pickaxe" for (pickaxe, 3); "a pickaxe" / "an axe" for tier <= 1.
static func tier_tool_name(tool_kind: String, tier: int) -> String:
	if tier <= 1:
		return "an axe" if tool_kind == "axe" else "a pickaxe"
	var t := "Axe" if tool_kind == "axe" else ("Pickaxe" if tool_kind == "pickaxe" else tool_kind.capitalize())
	var tn := String(EquipmentRules.TIERS.get(tier, ""))
	if tn == "":
		return "a better " + t.to_lower()
	return ("an " if "AEIOU".contains(tn.left(1)) else "a ") + tn + " " + t


func _warn_tool() -> void:
	var now := Time.get_ticks_msec()
	if now - _warn_ms < 2500:
		return
	_warn_ms = now
	if required_tier > 1 and StatsLayer.best_tool(tool) != "":
		Events.notify.emit("You need %s or better for that." % tier_tool_name(tool, required_tier), "warn")
		return
	Events.notify.emit("You need %s for that." % ("an axe" if tool == "axe" else "a pickaxe"), "warn")


func _on_settings_changed(key: String) -> void:
	if key != "arachnophobia" or base_kind != "silk" or params.get("visual") is Node3D:
		return
	display_name = String(params.get("name", "")) if String(params.get("name", "")) != "" else ItemDB.display_name("silk")
	var was_depleted := depleted
	if _visual != null:
		_visual.queue_free()
		remove_child(_visual)
	_build_visual()
	if was_depleted:
		_visual.visible = false
