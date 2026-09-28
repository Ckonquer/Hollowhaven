extends Node3D
## Krystal: an original stylised explorer (chibi-leaning, ~1.55 m, big head) built from Kit primitives
## with toon materials, outlines and fully procedural animation.
## The model faces +Z in its own space (the player rotates this node to its facing).
## Driven every frame by the player controller (speed, grounded, swing/roll phases ...), or standalone
## on the preview stage through play_anim(name):
##   idle, walk, run, jump, roll, axe, pickaxe, sword, hands, gather, wand, lantern, lantern_walk,
##   wave, cheer, flinch, sleep, eat, hurt, death
## Right hand = -X side (tools), left hand = +X side (lantern).
## WAND (Chapter Two, MP 5.1): set_held_tool("wand") while a wand is selected on the hotbar shows a small wand in the
## right hand between swings (src/player/avatar/wand_builder.gd, built lazily on first use so an avatar that never
## holds a wand keeps the exact Chapter One meshes); swing_kind "wand" plays a short flick-and-point cast pose.
##
## APPEARANCE (Chapter Two, MP 4; docs/CHAPTER_TWO_SPEC.md 4.1 / 8). The body is built from a look dictionary
## (GameState.appearance, ids from data/appearance.gd) in slot units - skin, eyes, hair (+ brows), hat,
## hair_acc, upper, lower, shoes, back, armor - each in its own container Node3D on the rig joints (builders in
## src/player/avatar/). apply_look() rebuilds only the units whose inputs changed and re-bakes only the joints
## they touch; the merged meshes are cached by CONTENT (mesh, transform, colour), so two avatars with different
## looks never share a mesh or a material that could bleed. ItemDB.LEGACY_LOOK reproduces the Chapter One avatar
## exactly (same parts, colours, proportions and ~82 draw calls). Appearance is cosmetic only: nothing here
## touches the player's collision, speed or reach. Unknown ids show the safe default of their slot and are
## reported by missing_ids() (the saved look itself is never modified).
## Driven (the player's avatar, driven = true before add_child) and follow_game_state: reads GameState.appearance
## + wardrobe.show_armor + equipment in _ready and on Events.appearance_changed / equipment_changed / game_loaded.
##
## PREVIEW API (non-driven mode; the appearance UI widget src/ui/widgets/avatar_preview.gd uses it):
##   var av = preload("res://src/player/krystal_avatar.gd").new()
##   av.apply_look(look)                       # before or after add_child; any look dict (partial ok)
##                                             # (same as setting av.appearance = look)
##   av.apply_armor(show_armor, equipment)     # optional: {"head": id, "body": id, "boots": id}
##   av.set_show_armor(on)                     # or av.show_armor = on (GameState.equipment if none given)
##   viewport_pivot.add_child(av)              # driven stays false: idle breathing, blinks, springs
##   av.play_anim("idle" | "walk" | "run" | "wave" | "cheer" | ...)
##   av.current_look() -> sanitized look shown, av.missing_ids() -> ["hair=future_curls", ...]
## Needs a SubViewport with own_world_3d = true; the camera's cull mask must include AVATAR_LAYER (1 << 11).

signal footstep(foot: int)          # 0 = left, 1 = right; emitted at each foot plant while walking

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const LookColors := preload("res://src/player/avatar/look_colors.gd")
const HairBuilder := preload("res://src/player/avatar/hair_builder.gd")
const GarmentBuilder := preload("res://src/player/avatar/garment_builder.gd")
const AccessoryBuilder := preload("res://src/player/avatar/accessory_builder.gd")
const ArmorBuilder := preload("res://src/player/avatar/armor_builder.gd")
const SkirtRig := preload("res://src/player/avatar/skirt_rig.gd")
const WandBuilder := preload("res://src/player/avatar/wand_builder.gd")

const OUTLINE := 0.011
## Render layer (12) used by Krystal's meshes: her own lantern ignores it as a shadow caster so her body
## never blacks out half of the light pool; the sun and every other light still shadow her normally.
const AVATAR_LAYER := 1 << 11
const FILL := 0.07
const FILL_TINT := Color(0.42, 0.34, 0.32)   # dim warm tint: same fill magnitude as the per-part albedo fill
const EYE_DARK := Color("2e2233")
const EYE_WARM := Color("7a4632")
const BLUSH := Color("f4a0ab")
const MOUTH := Color("8f3e4f")
const HAIR_DARK := Color("5e2c22")
const HAIR_LIGHT := Color("94503a")
const JACKET_DARK := Color("2e8781")
const SCARF_DARK := Color("d9a53a")
const BOOT_LIGHT := Color("8a5a36")
const BRASS := Color("e0b85a")
const LEATHER := Color("6e4a33")

## Appearance units, rebuilt independently (in this order).
const UNITS := ["skin", "eyes", "hair", "hat", "hair_acc", "upper", "lower", "shoes", "back", "armor"]
const UNIT_BOX := {"skin": "Skin", "eyes": "Eyes", "hair": "Hair", "hat": "Hat", "hair_acc": "HairAcc", "upper": "Upper",
	"lower": "Lower", "shoes": "Shoes", "back": "Back", "armor": "Armor"}
const BOX_META := &"avatar_slot"
const BAKE_CACHE_MAX := 600
const HULL_CENTRE := Vector3(0.0, 0.03, -0.03)
const HULL_MIN_DIST := 0.28

# Pose channel indices (PackedVector3Array) -------------------------------------------------------
const J_LEG_L := 0
const J_LEG_R := 1
const J_KNEE_L := 2
const J_KNEE_R := 3
const J_SH_L := 4
const J_SH_R := 5
const J_EL_L := 6
const J_EL_R := 7
const J_HIPS := 8
const J_SPINE := 9
const J_HEAD := 10
const J_HAND_L := 11
const J_HAND_R := 12
const J_COUNT := 13

## Swing keyframes per kind. "t" = normalized swing time; the strike lands at ~0.44 (see player_logic).
## Channels: right shoulder x/y/z, right elbow x, spine lean x / twist y, left shoulder x, left elbow x,
## knee bend, body height offset, head pitch.
const SWING_KEYS := {
	"axe": {"t": [0.0, 0.34, 0.46, 0.62, 1.0],
		"sh_x": [0.0, -2.95, -1.0, -0.8, 0.0], "sh_y": [0.0, -0.15, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.2, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -1.25, -0.2, -0.3, -0.15], "sp_x": [0.0, -0.15, 0.28, 0.2, 0.0], "sp_y": [0.0, -0.32, 0.24, 0.16, 0.0],
		"lsh_x": [0.0, -0.9, 0.35, 0.2, 0.0], "lel_x": [-0.15, -0.9, -0.3, -0.25, -0.15],
		"knee": [0.05, 0.12, 0.38, 0.3, 0.05], "body_y": [0.0, 0.02, -0.06, -0.05, 0.0], "head_x": [0.0, -0.14, 0.14, 0.08, 0.0]},
	"pickaxe": {"t": [0.0, 0.34, 0.46, 0.62, 1.0],
		"sh_x": [0.0, -3.0, -0.75, -0.6, 0.0], "sh_y": [0.0, -0.1, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.2, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -1.3, -0.15, -0.3, -0.15], "sp_x": [0.0, -0.16, 0.4, 0.3, 0.0], "sp_y": [0.0, -0.3, 0.2, 0.12, 0.0],
		"lsh_x": [0.0, -0.95, 0.3, 0.2, 0.0], "lel_x": [-0.15, -0.9, -0.3, -0.25, -0.15],
		"knee": [0.05, 0.14, 0.5, 0.4, 0.05], "body_y": [0.0, 0.02, -0.09, -0.07, 0.0], "head_x": [0.0, -0.12, 0.2, 0.12, 0.0]},
	"sword": {"t": [0.0, 0.34, 0.46, 0.62, 1.0],
		"sh_x": [0.0, -1.35, -1.45, -1.2, 0.0], "sh_y": [0.0, -1.05, 0.95, 1.0, 0.0], "sh_z": [-0.1, -0.3, -0.1, -0.1, -0.1],
		"el_x": [-0.15, -0.95, -0.1, -0.25, -0.15], "sp_x": [0.0, -0.05, 0.12, 0.08, 0.0], "sp_y": [0.0, -0.45, 0.42, 0.35, 0.0],
		"lsh_x": [0.0, 0.3, -0.45, -0.3, 0.0], "lel_x": [-0.15, -0.5, -0.6, -0.5, -0.15],
		"knee": [0.05, 0.16, 0.32, 0.26, 0.05], "body_y": [0.0, 0.0, -0.04, -0.03, 0.0], "head_x": [0.0, 0.0, 0.06, 0.03, 0.0]},
	"hands": {"t": [0.0, 0.3, 0.44, 0.6, 1.0],
		"sh_x": [0.0, 0.35, -1.55, -1.4, 0.0], "sh_y": [0.0, 0.0, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.15, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -1.8, -0.1, -0.3, -0.15], "sp_x": [0.0, -0.05, 0.15, 0.1, 0.0], "sp_y": [0.0, -0.35, 0.35, 0.25, 0.0],
		"lsh_x": [0.0, -0.9, 0.4, 0.3, 0.0], "lel_x": [-0.15, -1.6, -0.4, -0.3, -0.15],
		"knee": [0.05, 0.2, 0.3, 0.25, 0.05], "body_y": [0.0, -0.03, -0.05, -0.04, 0.0], "head_x": [0.0, 0.0, 0.0, 0.0, 0.0]},
	"gather": {"t": [0.0, 0.3, 0.46, 0.65, 1.0],
		"sh_x": [0.0, -0.5, -1.1, -1.0, 0.0], "sh_y": [0.0, 0.0, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.1, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -0.6, -0.2, -0.4, -0.15], "sp_x": [0.0, 0.12, 0.45, 0.4, 0.0], "sp_y": [0.0, -0.1, 0.05, 0.0, 0.0],
		"lsh_x": [0.0, -0.3, -0.7, -0.6, 0.0], "lel_x": [-0.15, -0.5, -0.3, -0.35, -0.15],
		"knee": [0.05, 0.3, 0.7, 0.65, 0.05], "body_y": [0.0, -0.05, -0.14, -0.13, 0.0], "head_x": [0.0, 0.1, 0.3, 0.25, 0.0]},
	# Wand cast (player_logic CAST_TIME 0.45 s, the spark leaves at CAST_RELEASE 0.16 s = t 0.36): a quick flick up by
	# the shoulder, then the arm snaps forward and points the wand at the target for a moment.
	"wand": {"t": [0.0, 0.2, 0.36, 0.56, 1.0],
		"sh_x": [0.0, -2.45, -1.5, -1.35, 0.0], "sh_y": [0.0, -0.2, 0.22, 0.18, 0.0], "sh_z": [-0.1, -0.25, -0.08, -0.1, -0.1],
		"el_x": [-0.15, -1.35, -0.05, -0.2, -0.15], "sp_x": [0.0, -0.06, 0.1, 0.08, 0.0], "sp_y": [0.0, -0.22, 0.16, 0.12, 0.0],
		"lsh_x": [0.0, -0.3, 0.2, 0.15, 0.0], "lel_x": [-0.15, -0.55, -0.4, -0.35, -0.15],
		"knee": [0.05, 0.1, 0.2, 0.16, 0.05], "body_y": [0.0, 0.0, -0.02, -0.015, 0.0], "head_x": [0.0, -0.08, 0.05, 0.03, 0.0]},
}
## Normalized cast time when the spark leaves the wand (the tip pulses around it).
const WAND_RELEASE_T := 0.36
const WAND_TIP_PULSE := 0.7
## Actions during which a held wand is put away (the right hand is busy or Krystal is lying down).
const HELD_HIDDEN_ACTIONS := ["eat", "sleep", "death"]

## Roll: points on the head + hair silhouette (HeadCenter space) that must stay above the floor.
## Hats, buns, helms and ponytails add their own silhouette points on top of these (see _head_hull).
const ROLL_CLEARANCE := 0.02
const _HEAD_HULL := [Vector3(0, 0.33, -0.05), Vector3(0, -0.27, 0.0), Vector3(0, -0.3, -0.2), Vector3(0.28, 0.03, -0.03),
	Vector3(-0.28, 0.03, -0.03), Vector3(0, 0.03, 0.26), Vector3(0, 0.0, -0.33), Vector3(0, 0.24, 0.17), Vector3(0, 0.25, -0.26),
	Vector3(0, -0.2, 0.17), Vector3(0.2, 0.24, -0.05), Vector3(-0.2, 0.24, -0.05), Vector3(0.2, -0.2, -0.1), Vector3(-0.2, -0.2, -0.1)]

const ACTION_TIME := {"hurt": 0.42, "flinch": 0.9, "wave": 1.8, "cheer": 1.6, "eat": 1.1, "interact": 0.45, "sleep": -1.0, "death": -1.0, "tired": 0.8}

# --- Controller inputs (set by the player every frame) -------------------------------------------------
var driven: bool = false            # true when a controller feeds the fields below
var follow_game_state: bool = true  # driven avatars follow GameState.appearance / equipment (the player's avatar)
var speed: float = 0.0
var grounded: bool = true
var vertical_speed: float = 0.0
var turn_rate: float = 0.0
var sprinting: bool = false
var swing_kind: String = ""
var swing_t: float = -1.0           # 0..1 while swinging, < 0 otherwise
var roll_t: float = -1.0            # 0..1 while rolling, < 0 otherwise
var lantern_on: bool = false
var lantern_owned: bool = false     # shows the lantern clipped to the satchel when it is not raised
var lantern_energy_scale: float = 1.0   # set by the player (dimmer in surface daylight)
var look_target: Vector3 = Vector3.ZERO
var has_look_target: bool = false

## Duck-typed appearance API (src/ui/widgets/avatar_preview.gd): set `appearance` before add_child to build the
## look once (after add_child it applies in place, like apply_look); `show_armor` / set_show_armor(on) show the
## armor of apply_armor's equipment, or of GameState.equipment when none was given.
var appearance: Dictionary:
	get:
		return _look_src.duplicate(true)
	set(value):
		apply_look(value)
var show_armor: bool:
	get:
		return _armor_show
	set(value):
		set_show_armor(value)

# --- Rig ------------------------------------------------------------------------------------------------
var _body_root: Node3D
var _roll: Node3D
var _body: Node3D
var _joints: Array[Node3D] = []
var _pose := PackedVector3Array()
var _body_off := Vector3.ZERO
var _head_c: Node3D
var _eyes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth_smile: MeshInstance3D
var _mouth_open: MeshInstance3D
var _scarf_ends: Array = []          # [[seg0, seg1], ...] (explorer scarf; empty for other garments)
var _braid: Array[Node3D] = []       # segments of the first hair chain (the Chapter One braid)
var _tools: Dictionary = {}           # kind -> Node3D (in the right hand); "wand" only once one was held / cast
var _held_tool: String = ""           # tool carried between swings ("wand" or "")
var _wand_tip: Node3D = null
var _tool_anchor: Node3D
var _lantern: Node3D
var _lantern_belt: Node3D
var _lantern_light: OmniLight3D
var _food: MeshInstance3D

# --- Appearance -----------------------------------------------------------------------------------------
var _look: Dictionary = {}            # sanitized look being shown (every id valid)
var _look_src: Dictionary = {}        # the look as given (may hold unknown ids; never modified)
var _missing: Array = []              # ["key=id", ...] unknown ids shown as defaults
var _reported_missing: String = ""
var _armor_show: bool = false
var _armor_eq: Dictionary = {}        # head / body / boots -> armor item id
var _sigs: Dictionary = {}            # unit -> signature of its inputs (rebuild when it changes)
var _unit_boxes: Dictionary = {}      # unit -> [container Node3D, ...]
var _unit_res: Dictionary = {}        # unit -> builder result (chains, skirt, hull points, patch, belt)
var _hosts: Dictionary = {}           # host key -> rig Node3D (joints, head centre, eyes, brows)
var _host_baked: Dictionary = {}      # host instance id -> [merged MeshInstance3D]
var _detached: Dictionary = {}        # container instance id -> [source parts merged into their host's bake]
var _chains: Array = []               # spring chain records of every unit (avatar_kit.gd chain())
var _skirt: SkirtRig = null
var _skirt_pivots: Array = []
var _head_hull: Array = []
var _patch: Node3D
var _connected: bool = false

# --- Animation state -----------------------------------------------------------------------------------
var _t: float = 0.0
var _phase: float = 0.0
var _move_w: float = 0.0
var _run_w: float = 0.0
var _air_w: float = 0.0
var _lantern_w: float = 0.0
var _swing_w: float = 0.0
var _last_swing_kind: String = "hands"
var _last_swing_t: float = 1.0
var _tool_timer: float = 0.0
var _shown_tool: String = ""
var _sq: float = 0.0
var _sq_v: float = 0.0
var _blink_timer: float = 2.0
var _blink_t: float = -1.0
var _idle_look_timer: float = 6.0
var _idle_look := Vector2.ZERO
var _idle_look_hold: float = 0.0
var _head_look := Vector2.ZERO
var _action: String = ""
var _action_t: float = 0.0
var _action_w: float = 0.0
var _prev_gpos := Vector3.ZERO
var _prev_lv := Vector3.ZERO
var _has_prev: bool = false
var _lv := Vector3.ZERO               # last local velocity / acceleration of the secondary motion (skirt input)
var _acc := Vector3.ZERO
var _lant_ang := Vector2.ZERO
var _lant_vel := Vector2.ZERO
var _roll_blend: float = 0.0
var _demo: String = ""
var _demo_t: float = 0.0
var _eyes_closed: float = 0.0
var _mouth_amt: float = 0.0
var _brow_worry: float = 0.0
var _visible_body: bool = true
var _lant_scale: float = 1.0
var _wing_phase: float = 0.0        # accumulated flap phase (the flap rate follows the speed)

static var _bake_cache: Dictionary = {}     # "material class|content hash" -> merged ArrayMesh (colour-aware)
static var _dirs: Array = []


func _ready() -> void:
	_pose.resize(J_COUNT)
	if _following():
		_read_state()
	elif _look.is_empty():
		_set_look(ItemDB.legacy_look())
	_apply_debug_look()
	_build()
	if _held_tool != "":
		show_tool(_rest_tool(), 0.0)
	_blink_timer = randf_range(1.5, 4.0)
	if _following():
		_connect_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for k in _detached:
			for mi in _detached[k]:
				if is_instance_valid(mi):
					(mi as Node).free()
		_detached.clear()


# =====================================================================================================
# Public API
# =====================================================================================================

## Shows a look dictionary (GameState.appearance format; partial looks take the legacy value for missing keys).
## Rebuilds only the units whose inputs changed. Returns the rebuilt unit names ([] when nothing changed).
## Callable before add_child (the look is then built in _ready).
func apply_look(look: Dictionary) -> Array:
	_set_look(look)
	if _body_root == null:
		return []
	return _rebuild_units(false)


## "Show equipped armor": when `on` and an armor piece is in `equipment` (slot -> item id, like
## GameState.equipment), tier-coloured armor is drawn over / instead of the garment of that slot.
func apply_armor(on: bool, equipment: Dictionary = {}) -> Array:
	_armor_show = on
	_armor_eq = {}
	for s in ["head", "body", "boots"]:
		var v: Variant = equipment.get(s, "")
		_armor_eq[s] = v if v is String else ""
	if _body_root == null:
		return []
	return _rebuild_units(false)


## Toggles "show equipped armor" keeping the armor given to apply_armor (or GameState.equipment when none).
func set_show_armor(on: bool) -> Array:
	var eq := _armor_eq
	var any := false
	for s in eq:
		any = any or String(eq[s]) != ""
	if not any:
		eq = GameState.equipment
	return apply_armor(on, eq)


## Re-reads GameState.appearance / wardrobe.show_armor / equipment (the player's avatar does this on
## Events.appearance_changed, equipment_changed and game_loaded). Returns the rebuilt units.
func refresh_from_state() -> Array:
	if not _following():
		return []
	_read_state()
	if _body_root == null:
		return []
	return _rebuild_units(false)


## The look being shown (sanitized: unknown ids replaced by their slot's safe default). A copy.
func current_look() -> Dictionary:
	return _look.duplicate(true)


## Unknown ids of the last look ("key=id"), shown as the safe default of their slot.
func missing_ids() -> Array:
	return _missing.duplicate()


## Visible mesh instances plus outline passes under the body (a draw-call estimate for tests / profiling).
func draw_call_estimate() -> int:
	var n := 0
	if _body_root == null:
		return 0
	var stack: Array = [_body_root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
		if nd is MeshInstance3D and (nd as MeshInstance3D).is_visible_in_tree():
			n += 1
			var m: Material = (nd as MeshInstance3D).material_override
			if m != null and m.next_pass != null:
				n += 1
	return n

## Plays a one-shot or looping action: hurt, flinch, wave, cheer, eat, interact, sleep, death, tired.
## Also accepts "jump" / "land" (squash & stretch only).
func play_action(action_name: String, strength: float = 1.0) -> void:
	match action_name:
		"jump":
			_sq_v += 2.6
			return
		"land":
			_sq_v -= clampf(strength, 0.6, 3.4)
			return
		"hurt":
			if _action == "death":
				return
	if not ACTION_TIME.has(action_name):
		return
	_action = action_name
	_action_t = 0.0
	if action_name == "eat" and _food != null:
		_food.visible = true
		_food.scale = Vector3.ONE


## Alias used by the player contract (play_emote).
func play_emote(emote_name: String) -> void:
	play_action(emote_name)


## Ends a looping/ongoing action (sleep, wave...) - e.g. when the player starts moving.
func cancel_action(include_death: bool = false) -> void:
	if _action == "death" and not include_death:
		return
	_action = ""
	if _food != null:
		_food.visible = false


func current_action() -> String:
	return _action


## Tints the food morsel shown while eating.
func set_food_color(c: Color) -> void:
	if _food != null:
		_food.material_override = Mat.outlined(Mat.toon(c, {"rim": 0.5}), 0.006)


## Shows the tool for a swing kind ("axe", "pickaxe", "sword", "wand"; anything else = empty hands) for `seconds`,
## then the held tool (set_held_tool) comes back. The wand model is built the first time it is needed.
func show_tool(kind: String, seconds: float = 0.9) -> void:
	if kind == "wand":
		_ensure_wand()
	_shown_tool = kind if _tools.has(kind) else ""
	_tool_timer = seconds
	for k in _tools:
		(_tools[k] as Node3D).visible = (k == _shown_tool)


## The tool Krystal carries in her right hand between swings: "wand" while a wand is selected on the hotbar, ""
## (empty hand, the Chapter One behaviour) otherwise. A swing still shows its own tool and hands it back after.
func set_held_tool(kind: String) -> void:
	var k := "wand" if kind == "wand" else ""
	if k == _held_tool:
		return
	_held_tool = k
	if _tool_timer <= 0.0 and _body_root != null:
		show_tool(_rest_tool(), 0.0)


func held_tool() -> String:
	return _held_tool


## The tool shown while no swing shows one: the held tool, put away while the hand is busy (eating, sleeping).
func _rest_tool() -> String:
	if _held_tool == "" or HELD_HIDDEN_ACTIONS.has(_action):
		return ""
	return _held_tool


## Builds the wand model on first use (never for an avatar that holds no wand: legacy meshes stay identical).
func _ensure_wand() -> void:
	if _tools.has("wand") or _tool_anchor == null:
		return
	var w := WandBuilder.build(_tool_anchor)
	_bake_subtree(w)
	_set_layers(w)
	_tools["wand"] = w
	_wand_tip = w.get_node_or_null(WandBuilder.TIP_NAME) as Node3D


func set_body_visible(v: bool) -> void:
	_visible_body = v
	if _body_root != null:
		_body_root.visible = v


## Resets the pose and motion history (teleports, respawn).
func reset_motion() -> void:
	_has_prev = false
	_prev_lv = Vector3.ZERO
	for ch in _chains:
		ch["ang"] = Vector2.ZERO
		ch["vel"] = Vector2.ZERO
	if _skirt != null:
		_skirt.reset()
	_lant_ang = Vector2.ZERO
	_lant_vel = Vector2.ZERO
	_sq = 0.0
	_sq_v = 0.0


## World position of the lantern flame (for lights / effects).
func lantern_world_position() -> Vector3:
	if _lantern != null and _lantern.is_inside_tree():
		return _lantern.global_position + _lantern.global_basis.y * 0.09
	return global_position + Vector3.UP * 0.9


func get_lantern_light() -> OmniLight3D:
	return _lantern_light


## Preview-stage entry point (standalone animation without a controller).
func play_anim(anim_name: String) -> void:
	_demo = anim_name
	_demo_t = 0.0
	driven = false
	speed = 0.0
	sprinting = false
	grounded = true
	lantern_on = false
	lantern_owned = true
	match anim_name:
		"walk":
			speed = 4.2
		"run":
			speed = 7.0
			sprinting = true
		"lantern":
			lantern_on = true
		"lantern_walk":
			lantern_on = true
			speed = 4.2
		"wave", "cheer", "flinch", "sleep", "eat", "hurt", "death", "tired":
			play_action(anim_name)



# =====================================================================================================
# Building the model
# =====================================================================================================

## Toon material for Krystal. A faint self-fill (emission ~7% of the albedo) keeps her readable in the
## darkest places (the Below at night) without lighting the world around her.
func _m(c: Color, outline: bool = true, thick: float = OUTLINE) -> Material:
	return AKit.m(c, outline, thick)


func _flat(c: Color) -> Material:
	return AKit.flat(c)


func _node(parent: Node3D, pos: Vector3, nm: String = "") -> Node3D:
	return AKit.node(parent, pos, nm)


func _part(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	return AKit.part(parent, mi, pos, rot_deg, scl, shadow)


## The rig (joints, face nodes, hands with tools / lantern / food, the lantern light), then every appearance unit.
func _build() -> void:
	_body_root = _node(self, Vector3.ZERO, "Body")
	_roll = _node(_body_root, Vector3(0, 0.5, 0), "RollPivot")
	_body = _node(_roll, Vector3(0, -0.5, 0), "Rig")
	_joints.resize(J_COUNT)
	var hips := _node(_body, Vector3(0, 0.6, 0), "Hips")
	_joints[J_HIPS] = hips
	_hosts["hips"] = hips
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var leg := _node(hips, Vector3(0.092 * s, -0.005, 0), "Leg%d" % side)
		_joints[J_LEG_L + side] = leg
		var knee := _node(leg, Vector3(0, -0.235, 0), "Knee%d" % side)
		_joints[J_KNEE_L + side] = knee
		_hosts["leg%d" % side] = leg
		_hosts["knee%d" % side] = knee
	var spine := _node(hips, Vector3(0, 0.02, 0), "Spine")
	_joints[J_SPINE] = spine
	_hosts["spine"] = spine
	var chest := _node(spine, Vector3(0, 0.36, 0), "Chest")
	_hosts["chest"] = chest
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		_build_arm(chest, side, s)
	var head := _node(chest, Vector3(0, 0.04, 0), "Head")
	_joints[J_HEAD] = head
	_head_c = _node(head, Vector3(0, 0.23, 0.0), "HeadCenter")
	_hosts["head_c"] = _head_c
	_build_face(_head_c)
	# Lantern light lives outside the body so hiding the body (camera very close) keeps the light.
	_lantern_light = OmniLight3D.new()
	_lantern_light.name = "LanternLight"
	_lantern_light.light_color = Palette.LANTERN_GLOW
	_lantern_light.light_energy = 1.25
	_lantern_light.omni_range = 7.0
	_lantern_light.omni_attenuation = 1.5
	_lantern_light.shadow_enabled = true
	_lantern_light.shadow_bias = 0.08
	_lantern_light.light_specular = 0.25
	_lantern_light.shadow_caster_mask = 0xFFFFFFFF & ~AVATAR_LAYER
	_lantern_light.visible = false
	add_child(_lantern_light)
	_bake_subtree(_lantern)
	for k in _tools:
		_bake_subtree(_tools[k])
	_set_layers(_body_root)
	_rebuild_units(true)


func _build_arm(chest: Node3D, side: int, s: float) -> void:
	var sh := _node(chest, Vector3(0.195 * s, -0.02, 0.0), "Shoulder%d" % side)
	_joints[J_SH_L + side] = sh
	var el := _node(sh, Vector3(0, -0.195, 0), "Elbow%d" % side)
	_joints[J_EL_L + side] = el
	var hand := _node(el, Vector3(0, -0.2, 0), "Hand%d" % side)
	_joints[J_HAND_L + side] = hand
	_hosts["sh%d" % side] = sh
	_hosts["el%d" % side] = el
	_hosts["hand%d" % side] = hand
	if side == 1:
		_tool_anchor = _node(hand, Vector3(0, -0.02, 0.0), "ToolAnchor")
		_build_tools(_tool_anchor)
		_food = Kit.sphere(0.035, _m(Palette.BERRY), 10, 14)
		_part(hand, _food, Vector3(0.01, -0.03, 0.06), Vector3.ZERO, Vector3.ONE, false)
		_food.visible = false
	else:
		_lantern = _node(hand, Vector3(0, -0.04, 0.0), "Lantern")
		AKit.lantern_mesh(_lantern, true)
		_lantern.visible = false


func _build_tools(anchor: Node3D) -> void:
	var handle := _m(Palette.WOOD)
	var stone := _m(Palette.STONE)
	var fiber := _m(Palette.MEADOW_GOLD)
	# Stone axe: handle along +Y, lumpy stone head lashed with fiber, edge towards +Z.
	var axe := _node(anchor, Vector3.ZERO, "Axe")
	axe.rotation = Vector3(2.3, 0, 0)
	_part(axe, Kit.cylinder(0.02, 0.024, 0.5, handle, 10), Vector3(0, 0.2, 0))
	_part(axe, Kit.blob(0.07, stone, 11, 0.22, 1.0, 2), Vector3(0, 0.4, 0.055), Vector3.ZERO, Vector3(0.55, 1.05, 1.35))
	_part(axe, Kit.torus(0.02, 0.036, fiber), Vector3(0, 0.4, 0.0), Vector3(0, 0, 0), Vector3(1, 1.6, 1))
	# Stone pickaxe: curved head across the top, point towards +Z.
	var pick := _node(anchor, Vector3.ZERO, "Pickaxe")
	pick.rotation = Vector3(2.3, 0, 0)
	_part(pick, Kit.cylinder(0.02, 0.024, 0.52, handle, 10), Vector3(0, 0.21, 0))
	_part(pick, Kit.cone(0.035, 0.17, stone, 10), Vector3(0, 0.44, 0.08), Vector3(80, 0, 0))
	_part(pick, Kit.cone(0.032, 0.13, stone, 10), Vector3(0, 0.44, -0.06), Vector3(-100, 0, 0))
	_part(pick, Kit.sphere(0.045, stone), Vector3(0, 0.44, 0.0))
	_part(pick, Kit.torus(0.02, 0.034, fiber), Vector3(0, 0.41, 0.0), Vector3.ZERO, Vector3(1, 1.4, 1))
	# Copper sword: extends along the arm (blade -Y-ish), bright copper with a leather grip.
	var sword := _node(anchor, Vector3.ZERO, "Sword")
	sword.rotation = Vector3(2.75, 0, 0)
	var copper := Mat.outlined(Mat.toon(Palette.COPPER, {"rim": 0.8, "specular": 0.6, "noise": 0.02}), OUTLINE)
	_part(sword, Kit.cylinder(0.018, 0.018, 0.1, _m(LEATHER), 8), Vector3(0, 0.0, 0))
	_part(sword, Kit.sphere(0.026, _m(BRASS)), Vector3(0, -0.06, 0))
	_part(sword, Kit.box(Vector3(0.15, 0.03, 0.04), _m(BRASS)), Vector3(0, 0.06, 0))
	_part(sword, Kit.box(Vector3(0.078, 0.46, 0.02), copper), Vector3(0, 0.3, 0))
	_part(sword, Kit.prism(Vector3(0.078, 0.09, 0.02), copper), Vector3(0, 0.575, 0))
	_part(sword, Kit.box(Vector3(0.016, 0.42, 0.022), _flat(Color("f7cf9c"))), Vector3(0, 0.29, 0), Vector3.ZERO, Vector3.ONE, false)
	_tools = {"axe": axe, "pickaxe": pick, "sword": sword}
	for k in _tools:
		(_tools[k] as Node3D).visible = false


## Face nodes (animated: eye blink scale, brow position / tilt) and the mouth; their meshes come from the
## skin / eyes / hair units.
func _build_face(hc: Node3D) -> void:
	_eyes.clear()
	_brows.clear()
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var eye := _node(hc, Vector3(0.087 * s, -0.022, 0.206), "Eye%d" % side)
		eye.rotation = Vector3(0, deg_to_rad(21.0 * s), 0)
		_eyes.append(eye)
		_hosts["eye%d" % side] = eye
		var brow := _node(hc, Vector3(0.088 * s, 0.062, 0.222), "Brow%d" % side)
		brow.rotation = Vector3(-0.2, deg_to_rad(20.0 * s), 0)
		_brows.append(brow)
		_hosts["brow%d" % side] = brow
	_mouth_smile = MeshInstance3D.new()
	_mouth_smile.mesh = AKit.arc_mesh(0.03, 0.0072, 1.9)
	_mouth_smile.material_override = _flat(MOUTH)
	_part(hc, _mouth_smile, Vector3(0, -0.118, 0.212), Vector3(-22, 0, 0), Vector3.ONE, false)
	_mouth_open = Kit.sphere(0.026, _flat(MOUTH), 10, 14)
	_part(hc, _mouth_open, Vector3(0, -0.118, 0.205), Vector3(-20, 0, 0), Vector3(1.15, 0.85, 0.45), false)
	_mouth_open.visible = false


## Head skin (skull, nose, blush) and the hands.
func _build_skin(col: Dictionary) -> void:
	var hc := _box("head_c", "skin")
	var skin_c: Color = col["skin"]
	_part(hc, Kit.sphere(0.25, _m(skin_c, true, 0.012), 24, 32), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.94, 0.95))
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		_part(hc, Kit.sphere(0.036, _flat(col["blush"]), 10, 14), Vector3(0.138 * s, -0.085, 0.172), Vector3(0, 36 * s, 0), Vector3(1.35, 0.72, 0.4), false)
	_part(hc, Kit.sphere(0.017, _m(skin_c, false), 8, 12), Vector3(0, -0.068, 0.233), Vector3.ZERO, Vector3(1.1, 0.9, 0.8), false)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var hb := _box("hand%d" % side, "skin")
		_part(hb, Kit.sphere(0.056, _m(skin_c)), Vector3(0, -0.012, 0.004), Vector3.ZERO, Vector3(0.9, 1.0, 1.0))
		_part(hb, Kit.sphere(0.022, _m(skin_c)), Vector3(-0.045 * s, 0.0, 0.03), Vector3.ZERO, Vector3(1, 1.3, 1))   # thumb


func _build_eyes(col: Dictionary) -> void:
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var e := _box("eye%d" % side, "eyes")
		_part(e, Kit.sphere(0.047, _flat(col["eye_dark"]), 12, 18), Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.13, 0.46), false)
		_part(e, Kit.sphere(0.03, _flat(col["iris"]), 10, 14), Vector3(0, -0.02, 0.01), Vector3.ZERO, Vector3(0.85, 0.62, 0.5), false)
		_part(e, Kit.sphere(0.0145, Mat.glow(Color.WHITE, 1.1), 8, 10), Vector3(0.012 * s, 0.02, 0.02), Vector3.ZERO, Vector3.ONE, false)
		_part(e, Kit.sphere(0.0075, Mat.glow(Color.WHITE, 1.0), 6, 8), Vector3(-0.012 * s, -0.022, 0.019), Vector3.ZERO, Vector3.ONE, false)
		# A single cute lash flick at the outer corner
		_part(e, Kit.capsule(0.007, 0.042, _flat(col["eye_dark"])), Vector3(0.038 * s, 0.038, 0.0), Vector3(0, 0, -48.0 * s), Vector3.ONE, false)


# --- Appearance units -------------------------------------------------------------------------------------

func _following() -> bool:
	return driven and follow_game_state


func _connect_state() -> void:
	if _connected:
		return
	_connected = true
	Events.appearance_changed.connect(_on_appearance_changed)
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.game_loaded.connect(_on_appearance_changed)


func _on_appearance_changed() -> void:
	refresh_from_state()


func _on_equipment_changed(_slot: String, _item_id: String) -> void:
	refresh_from_state()


func _read_state() -> void:
	var app: Variant = GameState.appearance
	_set_look(app if app is Dictionary else {})
	var wd: Variant = GameState.wardrobe
	_armor_show = wd is Dictionary and bool((wd as Dictionary).get("show_armor", false))
	_armor_eq = {}
	for s in ["head", "body", "boots"]:
		_armor_eq[s] = GameState.equipped(s)


func _set_look(look: Dictionary) -> void:
	_look_src = look.duplicate(true)
	var res := ItemDB.sanitize_look(look)
	_look = res["look"]
	_missing = res["missing"]
	var key := ", ".join(PackedStringArray(_missing))
	if key != "" and key != _reported_missing:
		push_warning("Krystal avatar: unknown appearance ids shown as safe defaults (kept in the save): " + key)
	_reported_missing = key


## Debug-only preview helper: --avatar-outfit=<outfit id> --avatar-hair=<id> --avatar-hair-color=<id>
## --avatar-skin=<id> --avatar-eyes=<id> --avatar-hat=<id> --avatar-armor=<armor set id> (non-driven avatars).
func _apply_debug_look() -> void:
	if driven or not Debug.is_cheat_allowed():
		return
	var any := false
	for a in ["avatar-outfit", "avatar-hair", "avatar-hair-color", "avatar-skin", "avatar-eyes", "avatar-hat", "avatar-armor"]:
		any = any or Debug.has_arg(a)
	if not any:
		return
	var look := _look.duplicate(true)
	var o := ItemDB.outfit(Debug.arg("avatar-outfit", ""))
	if not o.is_empty():
		for slot in o["parts"]:
			look[slot] = o["parts"][slot]
		look["palette"] = (o["palette"] as Dictionary).duplicate()
		look["hair"] = o["hair"]
		look["hair_color"] = o["hair_color"]
		look["outfit"] = Debug.arg("avatar-outfit")
	for pair in [["avatar-hair", "hair"], ["avatar-hair-color", "hair_color"], ["avatar-skin", "skin"], ["avatar-eyes", "eyes"], ["avatar-hat", "hat"]]:
		if Debug.has_arg(pair[0]):
			look[pair[1]] = Debug.arg(pair[0])
	_set_look(look)
	var st := ItemDB.armor_set(Debug.arg("avatar-armor", ""))
	if not st.is_empty():
		_armor_show = true
		_armor_eq = (st["pieces"] as Dictionary).duplicate()


## An armor item shown in `slot` ("" when show_armor is off, the slot is empty or the id is not armor of that slot).
func _armor_id(slot: String) -> String:
	if not _armor_show:
		return ""
	var id := String(_armor_eq.get(slot, ""))
	if id == "" or ItemDB.equip_slot(id) != slot:
		return ""
	return id


func _hides_hair() -> bool:
	if _armor_id("head") != "":
		return true
	var hat := String(_look.get("hat", ""))
	return hat != "" and bool(ItemDB.appearance_part(hat).get("hides_hair", false))


## What each unit is built from: a unit is rebuilt only when its signature changes.
func _signatures(col: Dictionary) -> Dictionary:
	var pal := String(col["palette_key"])
	var hat := String(_look.get("hat", ""))
	var head_armor := _armor_id("head")
	return {
		"skin": String(_look.get("skin", "")),
		"eyes": String(_look.get("eyes", "")),
		"hair": "%s|%s|%s|%s" % [_look.get("hair", ""), _look.get("hair_color", ""), _hides_hair(), pal],
		"hat": "%s|%s|%s" % [hat, head_armor, pal],
		"hair_acc": "%s|%s|%s|%s" % [_look.get("hair_acc", ""), pal, _look.get("hair", ""), head_armor if head_armor != "" else hat],
		"upper": "%s|%s|%s" % [_look.get("upper", ""), pal, _look.get("skin", "")],
		"lower": "%s|%s|%s" % [_look.get("lower", ""), pal, _look.get("skin", "")],
		"shoes": "%s|%s|%s|%s" % [_look.get("shoes", ""), pal, _armor_id("boots"), (col["leg"] as Color).to_html(false)],
		"back": "%s|%s" % [_look.get("back", ""), pal],
		"armor": _armor_id("body"),
	}


## Rebuilds the units whose signature changed (all with `force`), re-bakes the joints they touch and refreshes
## the secondary-motion rigs. Returns the rebuilt units.
func _rebuild_units(force: bool) -> Array:
	var col := LookColors.resolve(_look)
	var sigs := _signatures(col)
	var changed: Array = []
	for u in UNITS:
		if force or not _sigs.has(u) or String(_sigs[u]) != String(sigs[u]):
			changed.append(u)
	if changed.is_empty():
		return changed
	var touched: Dictionary = {}
	for u in changed:
		for b in _unit_boxes.get(u, []):
			if is_instance_valid(b):
				var host := (b as Node).get_parent()
				touched[host.get_instance_id()] = host
				_free_box(b)
		_unit_boxes[u] = []
		_unit_res[u] = _build_unit(u, col)
		_sigs[u] = sigs[u]
		for b in _unit_boxes[u]:
			var host2 := (b as Node).get_parent()
			touched[host2.get_instance_id()] = host2
	for u in changed:
		(_unit_res[u] as Dictionary)["hull_pts"] = _hull_points(u)
		for b in _unit_boxes[u]:
			for c in (b as Node).get_children():
				if c is Node3D and not (c is MeshInstance3D):
					_bake_subtree(c)
	for hid in touched:
		_rebake_host(touched[hid])
	for u in changed:
		for b in _unit_boxes[u]:
			_set_layers(b)
	_after_rebuild(changed)
	return changed


func _build_unit(u: String, col: Dictionary) -> Dictionary:
	var head_armor := _armor_id("head")
	var ctx := {"box": Callable(self, "_box").bind(u), "col": col, "look": _look, "id": "",
		"hides_hair": _hides_hair(), "hat": head_armor if head_armor != "" else String(_look.get("hat", ""))}
	match u:
		"skin":
			_build_skin(col)
		"eyes":
			_build_eyes(col)
		"hair":
			return HairBuilder.build(ctx)
		"hat":
			if head_armor != "":
				ctx["id"] = head_armor
				return ArmorBuilder.build_head(ctx)
			ctx["id"] = String(_look.get("hat", ""))
			if ctx["id"] != "":
				return AccessoryBuilder.build_hat(ctx)
		"hair_acc":
			ctx["id"] = String(_look.get("hair_acc", ""))
			if ctx["id"] != "":
				return AccessoryBuilder.build_hair_acc(ctx)
		"upper":
			ctx["id"] = String(_look.get("upper", ""))
			return GarmentBuilder.build_upper(ctx)
		"lower":
			ctx["id"] = String(_look.get("lower", ""))
			return GarmentBuilder.build_lower(ctx)
		"shoes":
			var boots := _armor_id("boots")
			if boots != "":
				ctx["id"] = boots
				return ArmorBuilder.build_boots(ctx)
			ctx["id"] = String(_look.get("shoes", ""))
			return GarmentBuilder.build_shoes(ctx)
		"back":
			ctx["id"] = String(_look.get("back", ""))
			var res := AccessoryBuilder.build_back(ctx)
			var belt: Node3D = res.get("belt")
			if belt != null:
				AKit.lantern_mesh(belt, false)
				belt.scale = Vector3.ONE * 0.8
				belt.visible = false
			return res
		"armor":
			var body := _armor_id("body")
			if body != "":
				ctx["id"] = body
				return ArmorBuilder.build_body(ctx)
	return {}


## The container of `unit` on a rig host (created on first use). Containers sit at the host origin.
func _box(host_key: String, unit: String) -> Node3D:
	var host: Node3D = _hosts.get(host_key)
	if host == null:
		push_error("Krystal avatar: unknown rig host '%s'" % host_key)
		host = _hosts["hips"]
	var list: Array = _unit_boxes[unit]
	for b in list:
		if (b as Node).get_parent() == host:
			return b
	var n := Node3D.new()
	n.name = String(UNIT_BOX.get(unit, unit))
	n.set_meta(BOX_META, unit)
	host.add_child(n)
	list.append(n)
	return n


func _free_box(b: Node) -> void:
	var did := b.get_instance_id()
	for mi in _detached.get(did, []):
		if is_instance_valid(mi):
			(mi as Node).free()
	_detached.erase(did)
	b.get_parent().remove_child(b)
	b.free()


## After a rebuild: the secondary-motion rigs (chains, skirt), the roll head hull, the back patch and the
## belt lantern follow the new parts.
func _after_rebuild(changed: Array) -> void:
	_chains = []
	for u in UNITS:
		_chains.append_array((_unit_res.get(u, {}) as Dictionary).get("chains", []))
	_scarf_ends = []
	_braid.clear()
	for ch in _chains:
		if String(ch["kind"]) == "scarf":
			_scarf_ends.append(ch["segs"])
		elif String(ch["kind"]) == "braid" and _braid.is_empty():
			for sg in ch["segs"]:
				_braid.append(sg)
	if changed.has("lower"):
		var sk: Dictionary = (_unit_res["lower"] as Dictionary).get("skirt", {})
		if sk.is_empty():
			_skirt = null
			_skirt_pivots = []
		else:
			_skirt = SkirtRig.new()
			_skirt.setup(sk)
			_skirt_pivots = sk["pivots"]
	_head_hull = _HEAD_HULL.duplicate()
	for u in ["hair", "hat", "hair_acc"]:
		_head_hull.append_array((_unit_res.get(u, {}) as Dictionary).get("hull_pts", []))
	if changed.has("upper"):
		_patch = (_unit_res["upper"] as Dictionary).get("patch")
	# A cape / shawl covers the jacket's back patch and the scarf ends (they would lie over / cut through the
	# rigid cape panels; map player_avatar.md recipe (a) 6). The scarf wraps at the neck stay.
	var caped := bool((_unit_res.get("back", {}) as Dictionary).get("cape", false))
	if is_instance_valid(_patch):
		_patch.visible = not caped
	for ends in _scarf_ends:
		((ends as Array)[0] as Node3D).visible = not caped
	if changed.has("back"):
		_lantern_belt = (_unit_res["back"] as Dictionary).get("belt")


## Silhouette points (HeadCenter space) a unit adds to the roll hull: support points of its static parts in 26
## directions (hats, buns, helms: "all" parts / hair: "direct" parts, never the spring chains) plus the rest
## positions of listed chain nodes. Only points outside the base hull's reach are kept.
func _hull_points(u: String) -> Array:
	var res: Dictionary = _unit_res.get(u, {})
	var mode := String(res.get("hull", ""))
	var out: Array = []
	if _dirs.is_empty():
		for x in [-1, 0, 1]:
			for y in [-1, 0, 1]:
				for z in [-1, 0, 1]:
					if x != 0 or y != 0 or z != 0:
						_dirs.append(Vector3(x, y, z).normalized())
	if mode != "":
		var best: Array = []
		var best_d := PackedFloat32Array()
		best.resize(_dirs.size())
		best_d.resize(_dirs.size())
		best_d.fill(-INF)
		for b in _unit_boxes.get(u, []):
			if (b as Node).get_parent() != _head_c:
				continue
			var stack: Array = (b as Node).get_children()
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if mode == "all":
					for c in n.get_children():
						stack.append(c)
				if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
					continue
				var xf := _xf_to(n as Node3D, _head_c)
				var mesh := (n as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
					for k in range(0, v.size(), 3):
						var p := xf * v[k]
						for di in _dirs.size():
							var d: float = p.dot(_dirs[di])
							if d > best_d[di]:
								best_d[di] = d
								best[di] = p
		for p in best:
			if p is Vector3 and ((p as Vector3) - HULL_CENTRE).length() > HULL_MIN_DIST and not out.has(p):
				out.append(p)
	for nr in res.get("hull_nodes", []):
		var nd: Node3D = nr[0]
		var p2 := _xf_to(nd, _head_c).origin
		var away := (p2 - HULL_CENTRE).normalized()
		out.append(p2 + away * float(nr[1]))
	return out


## Transform of `n` relative to an ancestor (walks the local transforms; works outside the tree too).
static func _xf_to(n: Node3D, ancestor: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != ancestor:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


# --- Draw-call baking -------------------------------------------------------------------------------------
# Parts are authored as primitives for readability. Parts that never move relative to their joint are merged
# per joint and material class into one vertex-coloured mesh (Chapter One: ~190 -> 82 draw calls): the parts of
# every unit container on a joint ("host") are merged together; when one unit is rebuilt, its host is re-baked
# from the other units' kept source parts. Nodes inside a container (satchel, patch, braid / skirt / cape
# segments, hats) are baked on their own. Animated / toggled pieces (eyes blink as a node, mouth shapes, food,
# glows) stay separate. Merged meshes are cached by content (mesh, transform, albedo): colour-aware.

func _bake_subtree(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			_bake_subtree(c)
	if not (n is Node3D):
		return
	var groups := _group_parts(n.get_children())
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		n.add_child(_merged_instance(list, key))
		for mi in list:
			n.remove_child(mi)
			(mi as Node).free()


## Merges the parts of every unit container on `host` into one mesh per material class.
func _rebake_host(host: Node) -> void:
	var hid := host.get_instance_id()
	for b in _host_baked.get(hid, []):
		if is_instance_valid(b):
			host.remove_child(b)
			(b as Node).free()
	_host_baked[hid] = []
	var parts: Array = []
	for box in host.get_children():
		if not box.has_meta(BOX_META):
			continue
		var did := box.get_instance_id()
		if _detached.has(did):
			for mi in _detached[did]:
				box.add_child(mi)
			_detached.erase(did)
		parts.append_array(box.get_children())
	var groups := _group_parts(parts)
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var merged := _merged_instance(list, key)
		host.add_child(merged)
		merged.layers = AVATAR_LAYER
		(_host_baked[hid] as Array).append(merged)
		for mi in list:
			var box2 := (mi as Node).get_parent()
			box2.remove_child(mi)
			var bid := box2.get_instance_id()
			if not _detached.has(bid):
				_detached[bid] = []
			(_detached[bid] as Array).append(mi)


## Mergeable parts grouped by material class (outline thickness, rim, noise, specular, shadow casting).
func _group_parts(nodes: Array) -> Dictionary:
	var groups: Dictionary = {}
	for c in nodes:
		if not (c is MeshInstance3D) or c == _mouth_smile or c == _mouth_open or c == _food:
			continue
		var mi := c as MeshInstance3D
		if not mi.visible or mi.get_child_count() > 0 or mi.mesh == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null or mat.shader != Mat.TOON:
			continue
		var thick := 0.0
		if mat.next_pass is ShaderMaterial:
			thick = float((mat.next_pass as ShaderMaterial).get_shader_parameter("thickness"))
		var rim := float(mat.get_shader_parameter("rim_strength"))
		var noise := float(mat.get_shader_parameter("noise_amount"))
		var spec_v: Variant = mat.get_shader_parameter("specular_amount")
		var spec := float(spec_v) if spec_v != null else 0.0
		var emis_v: Variant = mat.get_shader_parameter("emission_energy")
		if emis_v != null and float(emis_v) > FILL + 0.001:
			continue   # glowing cloth keeps its own material (the bake uses the plain fill)
		var key := "%.3f|%.2f|%.2f|%.2f|%d" % [thick, rim, noise, spec, mi.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(mi)
	return groups


## One merged MeshInstance3D for a group of parts (mesh cached by content, so identical looks share it and
## different colours never do).
func _merged_instance(list: Array, key: String) -> MeshInstance3D:
	var first := list[0] as MeshInstance3D
	var fmat := first.material_override as ShaderMaterial
	var sig := PackedStringArray()
	for item in list:
		var pmi := item as MeshInstance3D
		var c: Color = (pmi.material_override as ShaderMaterial).get_shader_parameter("albedo")
		sig.append("%d/%s/%s" % [pmi.mesh.get_instance_id(), str(pmi.transform), c.to_html()])
	var cache_key := "%s|%s" % [key, "#".join(sig).md5_text()]
	var mesh: ArrayMesh = _bake_cache.get(cache_key)
	if mesh == null:
		if _bake_cache.size() >= BAKE_CACHE_MAX:
			_bake_cache.clear()
		mesh = _merge_parts(list)
		_bake_cache[cache_key] = mesh
	var opts := {"rim": float(fmat.get_shader_parameter("rim_strength")), "noise": float(fmat.get_shader_parameter("noise_amount")),
		"vertex_color": true, "emission": FILL_TINT, "emission_energy": FILL}
	var spec_v2: Variant = fmat.get_shader_parameter("specular_amount")
	if spec_v2 != null and float(spec_v2) > 0.0:
		opts["specular"] = float(spec_v2)
	var base := Mat.toon(Color.WHITE, opts)
	var mat: Material = base
	if fmat.next_pass is ShaderMaterial:
		mat = Mat.outlined(base, float((fmat.next_pass as ShaderMaterial).get_shader_parameter("thickness")))
	var merged := MeshInstance3D.new()
	merged.name = "Baked"
	merged.mesh = mesh
	merged.material_override = mat
	merged.cast_shadow = first.cast_shadow
	return merged


## Merges parts (transforms relative to their shared parent) into one mesh; each part's albedo becomes
## its vertex colour (converted to linear because the toon shader multiplies raw COLOR).
static func _merge_parts(list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for item in list:
		var mi := item as MeshInstance3D
		var xf := mi.transform
		var nb := xf.basis.inverse().transposed()
		var c: Color = (mi.material_override as ShaderMaterial).get_shader_parameter("albedo")
		var lc := c.srgb_to_linear()
		for sidx in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(sidx)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ii: Variant = arr[Mesh.ARRAY_INDEX]
			var start := verts.size()
			for k in v.size():
				verts.append(xf * v[k])
				norms.append((nb * nn[k]).normalized() if k < nn.size() else Vector3.UP)
				cols.append(lc)
			if ii is PackedInt32Array and not (ii as PackedInt32Array).is_empty():
				for k in (ii as PackedInt32Array):
					idx.append(start + k)
			else:
				for k in v.size():
					idx.append(start + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = AVATAR_LAYER
	for c in n.get_children():
		_set_layers(c)


# =====================================================================================================
# Animation
# =====================================================================================================

func _process(delta: float) -> void:
	if _body == null:
		return
	var dt := minf(delta, 0.05)
	_t += dt
	if not driven:
		_run_demo(dt)
	_update_weights(dt)
	_reset_pose()
	_pose_locomotion(dt)
	_pose_air()
	_pose_lantern()
	_pose_swing(dt)
	_pose_action(dt)
	_pose_roll(dt)
	_apply_pose(dt)
	_keep_roll_above_ground()
	_update_face(dt)
	_update_secondary(dt)
	_update_props(dt)


func _update_weights(dt: float) -> void:
	var k := 1.0 - exp(-10.0 * dt)
	_move_w = lerpf(_move_w, clampf(speed / 4.2, 0.0, 1.0), k)
	_run_w = lerpf(_run_w, clampf((speed - 4.6) / 2.2, 0.0, 1.0), k)
	_air_w = lerpf(_air_w, 0.0 if grounded else 1.0, 1.0 - exp(-14.0 * dt))
	_lantern_w = lerpf(_lantern_w, 1.0 if lantern_on else 0.0, 1.0 - exp(-8.0 * dt))
	if swing_t >= 0.0:
		_swing_w = 1.0
		_last_swing_kind = swing_kind if SWING_KEYS.has(swing_kind) else "hands"
		_last_swing_t = swing_t
	else:
		_swing_w = move_toward(_swing_w, 0.0, dt * 8.0)
	# Squash & stretch spring
	_sq_v += (-_sq * 170.0 - _sq_v * 12.0) * dt
	_sq = clampf(_sq + _sq_v * dt, -0.28, 0.28)


func _reset_pose() -> void:
	for i in J_COUNT:
		_pose[i] = Vector3.ZERO
	_pose[J_SH_L] = Vector3(0.0, 0.0, 0.1)
	_pose[J_SH_R] = Vector3(0.0, 0.0, -0.1)
	_pose[J_EL_L] = Vector3(-0.15, 0.0, 0.0)
	_pose[J_EL_R] = Vector3(-0.15, 0.0, 0.0)
	_pose[J_KNEE_L] = Vector3(0.05, 0.0, 0.0)
	_pose[J_KNEE_R] = Vector3(0.05, 0.0, 0.0)
	_body_off = Vector3.ZERO


func _pose_locomotion(dt: float) -> void:
	var mw := _move_w
	var rw := _run_w
	# Walk cycle phase advances with distance travelled; footsteps at the plants.
	if speed > 0.05 and grounded and roll_t < 0.0:
		var cycle_len := lerpf(1.35, 2.05, rw)
		var prev := _phase
		_phase = fmod(_phase + dt * speed / cycle_len, 1.0)
		if speed > 0.6 and swing_t < 0.0:
			if prev < 0.25 and _phase >= 0.25:
				footstep.emit(0)
			elif prev < 0.75 and (_phase >= 0.75 or _phase < prev):
				footstep.emit(1)
	var cyc := _phase * TAU
	var sn := sin(cyc)
	var cs := cos(cyc)
	var leg_amp := lerpf(0.52, 0.9, rw) * mw
	var knee_amp := lerpf(0.55, 1.25, rw) * mw
	_pose[J_LEG_L].x += -sn * leg_amp
	_pose[J_LEG_R].x += sn * leg_amp
	_pose[J_KNEE_L].x += (maxf(0.0, cs) * knee_amp + 0.1 * mw)
	_pose[J_KNEE_R].x += (maxf(0.0, -cs) * knee_amp + 0.1 * mw)
	var arm_amp := lerpf(0.5, 0.95, rw) * mw
	_pose[J_SH_L].x += sn * arm_amp
	_pose[J_SH_R].x += -sn * arm_amp
	_pose[J_SH_L].z += 0.06 * mw
	_pose[J_SH_R].z -= 0.06 * mw
	_pose[J_EL_L].x += -(0.25 * mw + 0.95 * rw)
	_pose[J_EL_R].x += -(0.25 * mw + 0.95 * rw)
	_body_off.y += (absf(cs) - 0.6) * lerpf(0.035, 0.06, rw) * mw
	_pose[J_SPINE].x += 0.06 * mw + 0.16 * rw
	_pose[J_SPINE].y += sn * 0.12 * mw
	_pose[J_HIPS].y += -sn * 0.1 * mw
	_pose[J_HIPS].z += clampf(-turn_rate * 0.05, -0.22, 0.22) * mw
	_pose[J_HEAD].x += -0.05 * rw
	_pose[J_HEAD].y += -sn * 0.06 * mw
	# Idle: breathing, gentle sway and the odd curious look around.
	var iw := 1.0 - mw
	var br := sin(_t * 2.1)
	_body_off.y += br * 0.004 * iw
	_pose[J_SPINE].x += br * 0.015 * iw
	_pose[J_SH_L].z += (0.03 + br * 0.02) * iw
	_pose[J_SH_R].z -= (0.03 + br * 0.02) * iw
	_pose[J_HIPS].z += sin(_t * 0.55) * 0.025 * iw
	_pose[J_HEAD].z += sin(_t * 0.7 + 1.0) * 0.045 * iw
	_idle_look_timer -= dt
	if _idle_look_timer <= 0.0:
		_idle_look_timer = randf_range(5.0, 10.0)
		_idle_look = Vector2(randf_range(-0.14, 0.1), randf_range(-0.45, 0.45))
		_idle_look_hold = randf_range(1.2, 2.2)
	_idle_look_hold -= dt
	var want := Vector2.ZERO
	if _idle_look_hold > 0.0 and iw > 0.7:
		want = _idle_look
	if has_look_target and is_inside_tree():
		var local := global_transform.affine_inverse() * look_target
		var head_h := 1.25
		var flat := Vector2(local.x, local.z)
		if flat.length() > 0.3:
			var yaw := clampf(atan2(local.x, local.z), -0.7, 0.7)
			var pitch := clampf(atan2(local.y - head_h, flat.length()), -0.45, 0.3)
			want = Vector2(-pitch, yaw)
	_head_look = _head_look.lerp(want, 1.0 - exp(-5.0 * dt))
	_pose[J_HEAD].x += _head_look.x
	_pose[J_HEAD].y += _head_look.y
	_pose[J_SPINE].y += _head_look.y * 0.2


func _pose_air() -> void:
	var w := _air_w
	if w < 0.01:
		return
	var rising := clampf(vertical_speed / 4.0, -1.0, 1.0)
	var up := maxf(rising, 0.0)
	var down := maxf(-rising, 0.0)
	_pose[J_LEG_L] = _pose[J_LEG_L].lerp(Vector3(-0.55 * up - 0.1 * down, 0, 0.04), w)
	_pose[J_LEG_R] = _pose[J_LEG_R].lerp(Vector3(-0.1 * up + 0.12 * down, 0, -0.04), w)
	_pose[J_KNEE_L] = _pose[J_KNEE_L].lerp(Vector3(1.0 * up + 0.35 * down, 0, 0), w)
	_pose[J_KNEE_R] = _pose[J_KNEE_R].lerp(Vector3(0.45 * up + 0.3 * down, 0, 0), w)
	_pose[J_SH_L] = _pose[J_SH_L].lerp(Vector3(-0.4 * up - 0.2 * down, 0, 0.5 + 0.55 * down), w)
	_pose[J_SH_R] = _pose[J_SH_R].lerp(Vector3(0.3 * up - 0.2 * down, 0, -0.5 - 0.55 * down), w)
	_pose[J_EL_L] = _pose[J_EL_L].lerp(Vector3(-0.7, 0, 0), w)
	_pose[J_EL_R] = _pose[J_EL_R].lerp(Vector3(-0.7, 0, 0), w)
	_pose[J_SPINE].x += (0.06 * up - 0.05 * down) * w
	_pose[J_HEAD].x += (-0.1 * up + 0.08 * down) * w


func _pose_lantern() -> void:
	var w := _lantern_w
	if w < 0.01:
		return
	# Left arm holds the lantern forward at hip height; walking swings it only a little.
	var cur: Vector3 = _pose[J_SH_L]
	_pose[J_SH_L] = cur.lerp(Vector3(-0.5 + cur.x * 0.25, 0.1, 0.18), w)
	_pose[J_EL_L] = _pose[J_EL_L].lerp(Vector3(-0.85, 0, 0), w)


func _sample(keys: Array, times: Array, t: float) -> float:
	var n := times.size()
	if t <= float(times[0]):
		return float(keys[0])
	for i in range(1, n):
		var t1 := float(times[i])
		if t <= t1:
			var t0 := float(times[i - 1])
			var u := (t - t0) / maxf(t1 - t0, 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(keys[i - 1]), float(keys[i]), u)
	return float(keys[n - 1])


func _pose_swing(dt: float) -> void:
	if _tool_timer > 0.0:
		_tool_timer -= dt
		if _tool_timer <= 0.0:
			show_tool(_rest_tool(), 0.0)
	var w := _swing_w
	if _wand_tip != null:
		# The seed at the tip swells briefly as the spark leaves it.
		var pulse := 0.0
		if w >= 0.01 and _last_swing_kind == "wand":
			var u := (_last_swing_t - WAND_RELEASE_T) / 0.09
			pulse = exp(-u * u) * w
		_wand_tip.scale = Vector3.ONE * (1.0 + WAND_TIP_PULSE * pulse)
	if w < 0.01:
		return
	var d: Dictionary = SWING_KEYS[_last_swing_kind]
	var times: Array = d["t"]
	var t := _last_swing_t
	var shr := Vector3(_sample(d["sh_x"], times, t), _sample(d["sh_y"], times, t), _sample(d["sh_z"], times, t))
	_pose[J_SH_R] = _pose[J_SH_R].lerp(shr, w)
	_pose[J_EL_R] = _pose[J_EL_R].lerp(Vector3(_sample(d["el_x"], times, t), 0, 0), w)
	if _lantern_w < 0.5:
		_pose[J_SH_L] = _pose[J_SH_L].lerp(Vector3(_sample(d["lsh_x"], times, t), 0, 0.12), w)
		_pose[J_EL_L] = _pose[J_EL_L].lerp(Vector3(_sample(d["lel_x"], times, t), 0, 0), w)
	var sp: Vector3 = _pose[J_SPINE]
	_pose[J_SPINE] = Vector3(lerpf(sp.x, _sample(d["sp_x"], times, t), w), lerpf(sp.y, _sample(d["sp_y"], times, t), w), sp.z)
	var knee := _sample(d["knee"], times, t)
	var planted := (1.0 - _move_w * 0.7) * w
	_pose[J_KNEE_L].x = lerpf(_pose[J_KNEE_L].x, knee, planted)
	_pose[J_KNEE_R].x = lerpf(_pose[J_KNEE_R].x, knee * 0.8, planted)
	# Step into the swing: lead foot forward, back foot behind.
	_pose[J_LEG_L].x = lerpf(_pose[J_LEG_L].x, -knee * 0.55, planted)
	_pose[J_LEG_R].x = lerpf(_pose[J_LEG_R].x, knee * 0.35, planted)
	_body_off.y += _sample(d["body_y"], times, t) * w
	_pose[J_HEAD].x += _sample(d["head_x"], times, t) * w


func _pose_action(dt: float) -> void:
	if _action == "":
		_action_w = move_toward(_action_w, 0.0, dt * 6.0)
		_eyes_closed = move_toward(_eyes_closed, 0.0, dt * 8.0)
		_mouth_amt = move_toward(_mouth_amt, 0.0, dt * 6.0)
		_brow_worry = move_toward(_brow_worry, 0.0, dt * 5.0)
		return
	_action_t += dt
	var dur: float = float(ACTION_TIME.get(_action, 1.0))
	var w: float
	if dur > 0.0:
		w = smoothstep(0.0, minf(0.14, dur * 0.3), _action_t) * (1.0 - smoothstep(dur - minf(0.22, dur * 0.4), dur, _action_t))
		if _action_t >= dur:
			var finished := _action
			_action = ""
			if finished == "eat" and _food != null:
				_food.visible = false
			return
	else:
		w = smoothstep(0.0, 0.5, _action_t)
	_action_w = w
	var t := _action_t
	var eyes := 0.0
	var mouth := 0.0
	var worry := 0.0
	match _action:
		"hurt", "flinch":
			var trem := sin(t * 55.0) * 0.03 if _action == "flinch" else 0.0
			# Protective flinch: forearms folded in front of the face, leaning back and turning away.
			_blend(J_SPINE, Vector3(-0.22, 0.25, trem), w)
			_blend(J_HEAD, Vector3(0.12, 0.35, 0.12), w)
			_blend(J_SH_L, Vector3(-1.35, -0.55, 0.1), w)
			_blend(J_SH_R, Vector3(-1.2, 0.5, -0.1), w)
			_blend(J_EL_L, Vector3(-2.0, 0, 0), w)
			_blend(J_EL_R, Vector3(-1.9, 0, 0), w)
			_pose[J_KNEE_L].x += 0.25 * w
			_pose[J_KNEE_R].x += 0.25 * w
			_body_off.z -= 0.05 * w
			_body_off.y -= 0.03 * w
			eyes = 0.85
			mouth = 0.45
			worry = 1.0
		"wave":
			_blend(J_SH_R, Vector3(-0.2, 0.0, -2.55), w)
			_blend(J_EL_R, Vector3(-0.15, 0.0, 0.0), w)
			var wave := sin(t * 11.0) * 0.45
			_pose[J_EL_R].z += wave * w
			_pose[J_HAND_R].z += wave * 0.5 * w
			_blend(J_HEAD, Vector3(0.05, -0.15, -0.14), w)
			_pose[J_SPINE].z += 0.05 * w
			mouth = 0.55
		"cheer":
			var hop := absf(sin(t * 7.5))
			_blend(J_SH_L, Vector3(-0.25, 0.0, 2.65), w)
			_blend(J_SH_R, Vector3(-0.25, 0.0, -2.65), w)
			_blend(J_EL_L, Vector3(-0.3, 0, 0), w)
			_blend(J_EL_R, Vector3(-0.3, 0, 0), w)
			_blend(J_HEAD, Vector3(-0.18, 0, sin(t * 7.5) * 0.12), w)
			_body_off.y += hop * 0.1 * w
			_pose[J_KNEE_L].x += (1.0 - hop) * 0.4 * w
			_pose[J_KNEE_R].x += (1.0 - hop) * 0.4 * w
			eyes = 1.0
			mouth = 1.0
		"eat":
			var bite := absf(sin(t * 6.0))
			_blend(J_SH_R, Vector3(-1.25, 0.45, -0.1), w)
			_blend(J_EL_R, Vector3(-2.1 + bite * 0.25, 0.0, 0.0), w)
			_blend(J_HEAD, Vector3(0.12, 0.08, 0.05), w)
			eyes = 0.9
			mouth = bite
			if _food != null and _food.visible:
				var s := clampf(1.0 - t / dur, 0.15, 1.0)
				_food.scale = Vector3.ONE * s
		"interact":
			_blend(J_SH_R, Vector3(-1.1, 0.1, -0.1), w)
			_blend(J_EL_R, Vector3(-0.3, 0, 0), w)
			_pose[J_SPINE].x += 0.18 * w
			_pose[J_HEAD].x += 0.15 * w
		"tired":
			_blend(J_SPINE, Vector3(0.5, 0, 0), w)
			_blend(J_SH_L, Vector3(-0.5, 0, 0.1), w)
			_blend(J_SH_R, Vector3(-0.5, 0, -0.1), w)
			_blend(J_EL_L, Vector3(-0.2, 0, 0), w)
			_blend(J_EL_R, Vector3(-0.2, 0, 0), w)
			_pose[J_KNEE_L].x += 0.35 * w
			_pose[J_KNEE_R].x += 0.35 * w
			_body_off.y -= 0.05 * w
			_body_off.y += sin(t * 9.0) * 0.008 * w
			mouth = 0.5
		"sleep", "death":
			# Sit down on the ground, hug the knees, head tilted, eyes closed (death slumps sideways).
			var slow := sin(t * 1.3)
			_blend(J_LEG_L, Vector3(-1.45, -0.12, 0.08), w)
			_blend(J_LEG_R, Vector3(-1.45, 0.12, -0.08), w)
			_blend(J_KNEE_L, Vector3(1.9, 0, 0), w)
			_blend(J_KNEE_R, Vector3(1.9, 0, 0), w)
			# Arms hug the knees; the head rests tilted on them so the sleepy face stays visible.
			_blend(J_SPINE, Vector3(0.22 + slow * 0.02, 0, 0), w)
			_blend(J_SH_L, Vector3(-0.75, -0.55, 0.12), w)
			_blend(J_SH_R, Vector3(-0.75, 0.55, -0.12), w)
			_blend(J_EL_L, Vector3(-1.1, 0, 0), w)
			_blend(J_EL_R, Vector3(-1.1, 0, 0), w)
			_blend(J_HEAD, Vector3(0.12 + slow * 0.02, 0.1, 0.38), w)
			_body_off.y -= 0.36 * w
			_body_off.z -= 0.08 * w
			if _action == "death":
				_pose[J_HIPS].z += 0.9 * w
				_body_off.x += 0.18 * w
				_body_off.y -= 0.08 * w
			eyes = 1.0
	_eyes_closed = move_toward(_eyes_closed, eyes * w, dt * 10.0)
	_mouth_amt = move_toward(_mouth_amt, mouth * w, dt * 8.0)
	_brow_worry = move_toward(_brow_worry, worry * w, dt * 8.0)


func _blend(j: int, target: Vector3, w: float) -> void:
	_pose[j] = _pose[j].lerp(target, w)


func _pose_roll(dt: float) -> void:
	var active := roll_t >= 0.0
	_roll_blend = move_toward(_roll_blend, 1.0 if active else 0.0, dt * 14.0)
	if not active:
		_roll.rotation.x = 0.0
		_roll.scale = Vector3.ONE
		_roll.position = Vector3(0, 0.5, 0)
		return
	var t := clampf(roll_t, 0.0, 1.0)
	var env := sin(PI * t)
	var tuck := clampf(env * 1.5, 0.0, 1.0)
	_blend(J_LEG_L, Vector3(-1.5, 0, 0.05), tuck)
	_blend(J_LEG_R, Vector3(-1.5, 0, -0.05), tuck)
	_blend(J_KNEE_L, Vector3(2.2, 0, 0), tuck)
	_blend(J_KNEE_R, Vector3(2.2, 0, 0), tuck)
	_blend(J_SH_L, Vector3(-1.0, 0.4, 0.2), tuck)
	_blend(J_SH_R, Vector3(-1.0, -0.4, -0.2), tuck)
	_blend(J_EL_L, Vector3(-1.9, 0, 0), tuck)
	_blend(J_EL_R, Vector3(-1.9, 0, 0), tuck)
	_blend(J_SPINE, Vector3(0.55, 0, 0), tuck)
	_blend(J_HEAD, Vector3(0.45, 0, 0), tuck)
	var u := smoothstep(0.05, 0.92, t)
	_roll.rotation.x = u * TAU
	var sc := 1.0 - 0.46 * env
	_roll.scale = Vector3(1.0, sc, 1.0)
	# Lower the pivot while tucked so the little ball rolls along the ground instead of floating.
	_roll.position = Vector3(0, 0.5 - 0.15 * env, 0)


## The big chibi head sticks out of the tucked ball: while it swings under the pivot (upside-down part of
## the roll) it used to sink ~0.4 m into the ground. Lift the roll pivot just enough to keep the head and
## hair above the floor, so the roll reads as a tumble over the head.
func _keep_roll_above_ground() -> void:
	if roll_t < 0.0 or _head_c == null or _roll == null or not is_inside_tree():
		return
	var xf := global_transform.affine_inverse() * _head_c.global_transform
	var low := INF
	for p in _head_hull:
		low = minf(low, (xf * p).y)
	if low < ROLL_CLEARANCE:
		_roll.position.y += ROLL_CLEARANCE - low


func _apply_pose(_dt: float) -> void:
	for i in J_COUNT:
		var j := _joints[i]
		if j != null:
			j.rotation = _pose[i]
	_body.position = Vector3(0, -0.5, 0) + _body_off
	_body_root.scale = Vector3(1.0 - _sq * 0.5, 1.0 + _sq, 1.0 - _sq * 0.5)


func _update_face(dt: float) -> void:
	_blink_timer -= dt
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(0.22, 0.3) if randf() < 0.18 else randf_range(2.0, 5.0)
	var blink := 0.0
	if _blink_t >= 0.0:
		_blink_t += dt
		blink = sin(clampf(_blink_t / 0.13, 0.0, 1.0) * PI)
		if _blink_t >= 0.13:
			_blink_t = -1.0
	var closed := maxf(blink, _eyes_closed)
	var sy := lerpf(1.0, 0.1, closed)
	for e in _eyes:
		e.scale = Vector3(1.0, sy, 1.0)
	for i in _brows.size():
		var s := 1.0 if i == 0 else -1.0
		var b := _brows[i]
		b.position.y = 0.062 - 0.008 * closed + 0.01 * _mouth_amt * (1.0 - _brow_worry)
		b.rotation.z = 0.35 * _brow_worry * s
	var open := _mouth_amt > 0.2
	_mouth_open.visible = open
	_mouth_smile.visible = not open
	if open:
		_mouth_open.scale = Vector3(1.0 + 0.15 * _mouth_amt, 0.5 + 0.6 * _mouth_amt, 0.45)


func _update_secondary(dt: float) -> void:
	if not is_inside_tree():
		return
	var gp := global_position
	var lv := Vector3.ZERO
	if not driven:
		lv = Vector3(0, 0, speed)
	elif _has_prev:
		var v := (gp - _prev_gpos) / maxf(dt, 0.001)
		if v.length() > 14.0:
			v = Vector3.ZERO
		lv = global_basis.inverse() * v
	_prev_gpos = gp
	_has_prev = true
	var acc := (lv - _prev_lv) / maxf(dt, 0.001)
	acc = acc.limit_length(40.0)
	_prev_lv = lv
	_lv = lv
	_acc = acc
	var flutter := sin(_t * 17.0) * 0.1 * _run_w
	var fall := maxf(0.0, -lv.y) * 0.06
	# Wings flap faster with speed: integrate the phase (sin(_t * rate) would jump when the rate changes).
	_wing_phase = fmod(_wing_phase + dt * (3.0 + 4.0 * _move_w), TAU)
	# Hair chains (the Chapter One braid spring): heavier and slower; swing with the bob and lag behind turns.
	var bt := Vector2(clampf(lv.z * 0.08 + acc.z * 0.01 + fall * 0.8, -0.4, 0.9), clampf(-lv.x * 0.07 - acc.x * 0.008 + turn_rate * 0.03, -0.6, 0.6))
	bt.x -= _pose[J_SPINE].x * 0.8 + _pose[J_HEAD].x * 0.6
	for ch in _chains:
		match String(ch["kind"]):
			"scarf":
				_chain_scarf(ch, dt, lv, acc, fall, flutter)
			"braid":
				_chain_braid(ch, dt, bt)
			"cape":
				_chain_cape(ch, dt, lv, acc, fall, flutter)
			"wing":
				_chain_wing(ch)
	# Lantern: kept upright with a little pendulum lag.
	var lt := Vector2(clampf(lv.z * 0.05 + acc.z * 0.015, -0.6, 0.6), clampf(-lv.x * 0.05 - acc.x * 0.015, -0.6, 0.6))
	_lant_vel += ((lt - _lant_ang) * 55.0 - _lant_vel * 4.0) * dt
	_lant_ang += _lant_vel * dt
	_update_skirt(dt)


## Scarf ends: trail behind when moving, lag on acceleration, flutter when running (Chapter One formula).
func _chain_scarf(ch: Dictionary, dt: float, lv: Vector3, acc: Vector3, fall: float, flutter: float) -> void:
	var i := int(ch["i"])
	var target := Vector2(clampf(lv.z * 0.13 + acc.z * 0.012 + fall, -0.5, 1.35), clampf(-lv.x * 0.1 - acc.x * 0.01, -0.7, 0.7))
	target.x += flutter * (1.0 if i == 0 else -0.7)
	var a: Vector2 = ch["ang"]
	var v2: Vector2 = ch["vel"]
	v2 += ((target - a) * float(ch["k"]) - v2 * float(ch["d"])) * dt
	a += v2 * dt
	ch["ang"] = a
	ch["vel"] = v2
	var segs: Array = ch["segs"]
	var rest: Vector3 = (ch["rest"] as Array)[0]
	(segs[0] as Node3D).rotation = Vector3(rest.x + a.x * 0.7, rest.y, rest.z + a.y * 0.7)
	(segs[1] as Node3D).rotation = Vector3(a.x * 0.45 + sin(_t * 9.0 + i) * 0.05 * _move_w, 0.0, a.y * 0.4)


## Braids, ponytails, hair curtains, ribbon tails (the Chapter One braid formula around each segment's rest).
func _chain_braid(ch: Dictionary, dt: float, bt: Vector2) -> void:
	var ang: Vector2 = ch["ang"]
	var vel: Vector2 = ch["vel"]
	vel += ((bt - ang) * float(ch["k"]) - vel * float(ch["d"])) * dt
	ang += vel * dt
	ch["ang"] = ang
	ch["vel"] = vel
	var amp := float(ch["amp"])
	var sd := float(ch["side"])
	var segs: Array = ch["segs"]
	var rest: Array = ch["rest"]
	for i in segs.size():
		var f := 0.5 if i == 0 else (0.22 + 0.06 * i) * 0.5
		var wave := sin(_t * 5.5 - float(i) * 0.8) * 0.04 * _move_w
		var r: Vector3 = rest[i]
		(segs[i] as Node3D).rotation = Vector3(r.x + ang.x * f * amp, r.y, r.z + ang.y * f * amp * sd + wave)


## Capes and shawls: lift away from the back with speed, falls and running flutter; never swing into the back.
func _chain_cape(ch: Dictionary, dt: float, lv: Vector3, acc: Vector3, fall: float, flutter: float) -> void:
	var target := Vector2(clampf(lv.z * 0.1 + acc.z * 0.012 + fall * 1.2 + flutter * 0.5 - _pose[J_SPINE].x * 0.6, 0.0, 1.1),
		clampf(-lv.x * 0.08 - acc.x * 0.008 + turn_rate * 0.03, -0.45, 0.45))
	var a: Vector2 = ch["ang"]
	var v2: Vector2 = ch["vel"]
	v2 += ((target - a) * float(ch["k"]) - v2 * float(ch["d"])) * dt
	a += v2 * dt
	a.x = clampf(a.x, -0.02, 1.2)
	a.y = clampf(a.y, -0.5, 0.5)
	ch["ang"] = a
	ch["vel"] = v2
	var segs: Array = ch["segs"]
	var rest: Array = ch["rest"]
	var r0: Vector3 = rest[0]
	var r1: Vector3 = rest[1]
	(segs[0] as Node3D).rotation = Vector3(r0.x - a.x, r0.y, r0.z + a.y)
	(segs[1] as Node3D).rotation = Vector3(r1.x - a.x * 0.5 - flutter * 0.3, r1.y, r1.z + a.y * 0.5)


## Wings: a slow flap that quickens with speed (phase integrated in _update_secondary).
func _chain_wing(ch: Dictionary) -> void:
	var flap := sin(_wing_phase) * (0.12 + 0.1 * _run_w)
	var segs: Array = ch["segs"]
	var rest: Array = ch["rest"]
	for i in segs.size():
		var r: Vector3 = rest[i]
		(segs[i] as Node3D).rotation = Vector3(r.x, r.y + flap * (1.0 if i == 0 else -1.0), r.z)


## Skirt / dress panels (skirt_rig.gd): sway with the motion, pushed out by the legs, clamped.
func _update_skirt(dt: float) -> void:
	if _skirt == null:
		return
	# The trail / billow come from the travel velocity in the upright frame; while the body tumbles through a roll
	# that frame spins, so a "trailing" hem would swing into the ground (the back panels point down at 3/4 turn).
	# Fade the motion drive out while rolling: the panels keep their base flare and the leg push.
	var drive := 1.0 - _roll_blend
	_skirt.update(dt, _lv * drive, _acc * drive, _pose[J_LEG_L], _pose[J_LEG_R], _pose[J_KNEE_L], _pose[J_KNEE_R], _t, _run_w * drive, turn_rate * drive)
	for i in _skirt_pivots.size():
		(_skirt_pivots[i] as Node3D).rotation = Vector3(-_skirt.flare[i], _skirt.theta[i], _skirt.side[i])


func _update_props(dt: float) -> void:
	if _held_tool != "" and _tool_timer <= 0.0:
		var rest := _rest_tool()
		if rest != _shown_tool:
			show_tool(rest, 0.0)
	var raised := lantern_on and roll_t < 0.0
	if _lantern != null:
		_lantern.visible = raised
		if raised and _lantern.is_inside_tree():
			var up_basis := global_basis * Basis.from_euler(Vector3(_lant_ang.x, 0.0, _lant_ang.y))
			_lantern.global_basis = up_basis.orthonormalized()
	if _lantern_belt != null:
		_lantern_belt.visible = lantern_owned and not lantern_on
	if _lantern_light != null:
		_lantern_light.visible = lantern_on
		if lantern_on and _lantern != null and _lantern.is_inside_tree():
			_lantern_light.global_position = lantern_world_position() + Vector3(0, 0.02, 0)
			_lant_scale = lerpf(_lant_scale, lantern_energy_scale, 1.0 - exp(-2.0 * dt))
			_lantern_light.light_energy = (1.25 + sin(_t * 7.3) * 0.045 + sin(_t * 12.1 + 1.3) * 0.035) * _lant_scale


# =====================================================================================================
# Standalone demo (preview stage)
# =====================================================================================================

func _run_demo(dt: float) -> void:
	_demo_t += dt
	match _demo:
		"axe", "pickaxe", "sword", "hands", "gather", "swing", "wand":
			var kind := "axe" if _demo == "swing" else _demo
			var cycle := 0.5 + 0.45
			var t := fmod(_demo_t, cycle)
			if t < 0.5:
				swing_kind = kind
				swing_t = t / 0.5
				if _shown_tool != kind and (_tools.has(kind) or kind == "wand"):
					show_tool(kind, 0.9)
				_tool_timer = 0.5
			else:
				swing_t = -1.0
		"roll":
			var t := fmod(_demo_t, 0.45 + 0.5)
			roll_t = t / 0.45 if t < 0.45 else -1.0
		"jump":
			var t := fmod(_demo_t, 1.2)
			grounded = t > 0.8
			vertical_speed = 6.0 - 18.0 * t
			if absf(t - 0.0) < dt:
				play_action("jump")
			if absf(t - 0.8) < dt:
				play_action("land", 2.0)
		"wave", "cheer", "flinch", "eat", "hurt", "tired":
			if _action == "":
				play_action(_demo)
