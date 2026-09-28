extends Node3D
## Bell Throat stations (MP §10 room 13; safe room; checkpoint bell_throat is placed by rooms_deep.gd):
## * the miners' final supply crate: guaranteed healing food ONCE (GameState.grant_once of the reward id
##   Layout.THROAT_SUPPLIES_ID, data/sources.gd bundle when present, else Layout.THROAT_SUPPLIES_FALLBACK);
## * the miners' note (lore_ch2_bell_throat_note) on a lectern and "Before the Choir" (lore_ch2_before_choir)
##   carved over the vault stair - texts from data/lore_ch2_works.gd via LoreDB (fallback: the MP §17 line);
## * the practice reveal station (practice_station.gd) teaching the Choir's exposure rule;
## * the bellmakers' order board (the room 5 symbol order the vault's resonators answer to);
## * the bell-rope lift and the explicit RETURN / CONTINUE choice (Game.ui.confirm): "return" rides the lift
##   to the Pocket Conservatory (spawn refuge) and frees room 9's winch cage, which brings her straight back
##   down here; "continue" stays. Offered at the lift any time, and once automatically when Krystal first
##   nears the vault stair (flag hw_throat_choice_seen).
## The node sits at the area origin; positions come from data/works_layout_deep.gd THROAT.

signal choice_made(option: String)

const Layout := preload("res://data/works_layout_deep.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const LiftScript := preload("res://src/world/works/deep/deep_lift.gd")
const PracticeScript := preload("res://src/world/works/deep/practice_station.gd")

const CHOICE_FLAG := "hw_throat_choice_seen"
const CHOICE_Z := 40.5                 # nearing the vault stair (z) triggers the one-time choice
const ORDER_BOARD_OUT := 0.5          # the bellmakers' order board stands this far out of the east wall
const NOTE_FALLBACK := {"title": "A miners' note",
	"text": "Whatever sings in the vault knows our knocks and our festival songs, but it cannot carry a lamp. Raise yours at the anchors and watch the floor: only the true one's light touches the ground."}

var controller: Node = null
var practice: Node3D = null
var lift: Node3D = null
var crate: Node3D = null
var last_choice: String = ""
var _choosing: bool = false
var _crate_lid: Node3D = null


func setup(p: Dictionary) -> void:
	controller = p.get("controller", controller)


func _ready() -> void:
	add_to_group("hw_throat")
	_build_crate()
	_build_note()
	_build_inscription()
	_build_order_board()
	_build_lift()
	practice = PracticeScript.new()
	practice.setup({"anchor": Layout.THROAT["practice_anchor"], "forms": Layout.THROAT["practice_forms"],
		"genuine": int(Layout.THROAT["practice_genuine"])})
	practice.name = "Practice"
	add_child(practice)
	_refresh_crate()


# --- Supplies -------------------------------------------------------------------------------------------

static func supplies_bundle() -> Dictionary:
	var b: Dictionary = ItemDB.reward_bundle(Layout.THROAT_SUPPLIES_ID)
	if b.is_empty() or not (b.get("items", null) is Dictionary):
		return Layout.THROAT_SUPPLIES_FALLBACK
	return b


func supplies_taken() -> bool:
	return GameState.has_reward(Layout.THROAT_SUPPLIES_ID)


## Grants the final supplies once. True only the first time.
func take_supplies() -> bool:
	var b := supplies_bundle()
	var flags: Array = b.get("flags", []) if b.get("flags", []) is Array else []
	var ok := GameState.grant_once(Layout.THROAT_SUPPLIES_ID, b.get("items", {}), flags, "The miners left supplies for whoever came next.")
	if ok:
		Art.sfx3d("chest_open", (Layout.THROAT["supplies"] as Vector3) + Vector3.UP * 0.6, -3.0)
	_refresh_crate()
	return ok


func _crate_text() -> Dictionary:
	if supplies_taken():
		return {"text": "The crate is empty now", "enabled": false}
	return {"text": "Open the miners' supply crate", "enabled": true}


func _refresh_crate() -> void:
	if _crate_lid != null:
		_crate_lid.rotation_degrees.x = -70.0 if supplies_taken() else 0.0


# --- Notes -------------------------------------------------------------------------------------------------

static func lore_text(id: String) -> Dictionary:
	if LoreDB.has_lore(id):
		return LoreDB.get_lore(id)
	if id == Layout.LORE_BEFORE_CHOIR:
		return {"title": "Before the Choir", "text": Layout.BEFORE_CHOIR_LINE}
	return NOTE_FALLBACK


func read(id: String) -> Dictionary:
	var l := lore_text(id)
	if LoreDB.has_lore(id):
		GameState.discover_lore(id)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l.get("title", "")), String(l.get("text", "")), 9.0)
	return l


# --- Return / continue ----------------------------------------------------------------------------------

## Opens the explicit choice (awaits Game.ui.confirm; without a UI it defaults to "continue").
func offer_choice() -> String:
	if _choosing:
		return ""
	_choosing = true
	GameState.set_flag(CHOICE_FLAG, true)
	var option := "continue"
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("confirm"):
		var text := "%s\n\nThe Choir Vault lies below. The bell-rope lift climbs back to the Pocket Conservatory." % Layout.BEFORE_CHOIR_LINE
		var c: Variant = await Game.ui.confirm("Before the Choir", text,
			[["continue", "Go on to the Choir Vault", "AccentButton"], ["return", "Return to the refuge", ""]])
		option = "return" if String(c) == "return" else "continue"
	_choosing = false
	return choose(option)


## Applies a choice: "return" rides the lift to the refuge, anything else continues.
func choose(option: String) -> String:
	last_choice = "return" if option == "return" else "continue"
	GameState.set_flag(CHOICE_FLAG, true)
	if last_choice == "return":
		if controller != null and is_instance_valid(controller) and controller.has_method("ride"):
			controller.call("free_winch_cage")
			controller.call("ride", Layout.REFUGE_SPAWN, "[the bell-rope lift hauls you up toward the garden light]",
				"The Pocket Conservatory. Rest and restock - the winch cage by the ward door brings you back down.")
	else:
		Art.say("The vault stair waits below. Your lantern is ready.", 3.5)
	choice_made.emit(last_choice)
	return last_choice


## Controller hook: the first time Krystal nears the vault stair, ask once.
func check(p: Node3D) -> void:
	if p == null or _choosing or bool(GameState.get_flag(CHOICE_FLAG)):
		return
	if p.global_position.z > CHOICE_Z and absf(p.global_position.y - (Layout.THROAT["lift"] as Vector3).y) < 2.0:
		offer_choice()


func _on_lift(_lift: Node) -> void:
	offer_choice()


# --- Building -----------------------------------------------------------------------------------------------

func _build_crate() -> void:
	crate = Node3D.new()
	crate.name = "SupplyCrate"
	add_child(crate)
	crate.position = Layout.THROAT["supplies"]
	crate.rotation.y = PI * 0.5
	var wood := Mat.outlined(Mat.toon(Color("9a6a42")), 0.018)
	var band := Mat.outlined(Mat.toon(Art.BRASS, {"rim": 0.5}), 0.012)
	Kit.add(crate, Kit.box(Vector3(1.1, 0.6, 0.7), wood), Vector3(0, 0.3, 0))
	Kit.add(crate, Kit.box(Vector3(1.14, 0.08, 0.74), band), Vector3(0, 0.5, 0))
	_crate_lid = Node3D.new()
	_crate_lid.name = "Lid"
	crate.add_child(_crate_lid)
	_crate_lid.position = Vector3(0, 0.6, -0.35)
	Kit.add(_crate_lid, Kit.box(Vector3(1.14, 0.1, 0.74), wood), Vector3(0, 0.05, 0.35))
	Kit.add(crate, Kit.box(Vector3(0.9, 0.04, 0.02), Mat.toon(Art.RIBBONS[1])), Vector3(0, 0.35, 0.36))
	Kit.static_collider(crate, _box_shape(Vector3(1.1, 0.7, 0.7)), Vector3(0, 0.35, 0))
	var it: Node3D = Interactable.new()
	it.setup({"size": Vector3(1.6, 1.2, 1.4), "offset": Vector3(0, 0.6, 0), "handler": func(_p: Node) -> void: take_supplies(),
		"text_func": Callable(self, "_crate_text"), "accent": true, "id": "hw_throat_supplies"})
	it.name = "CrateInteract"
	crate.add_child(it)


func _build_note() -> void:
	var n := Node3D.new()
	n.name = "Lectern"
	add_child(n)
	n.position = Layout.THROAT["note"]
	n.rotation.y = -PI * 0.5
	var wood := Mat.outlined(Mat.toon(Color("7a5236")), 0.016)
	Kit.add(n, Kit.box(Vector3(0.2, 1.0, 0.2), wood), Vector3(0, 0.5, 0))
	Kit.add(n, Kit.box(Vector3(0.7, 0.06, 0.5), wood), Vector3(0, 1.05, 0), Vector3(-20, 0, 0))
	Kit.add(n, Kit.box(Vector3(0.5, 0.012, 0.36), Mat.toon(Color("efe0bd"), {"emission": Color("efe0bd"), "emission_energy": 0.15})), Vector3(0, 1.09, 0), Vector3(-20, 0, 0))
	Kit.static_collider(n, _box_shape(Vector3(0.5, 1.1, 0.5)), Vector3(0, 0.55, 0))
	var it: Node3D = Interactable.new()
	it.setup({"text": "Read the miners' note", "size": Vector3(1.2, 1.4, 1.2), "offset": Vector3(0, 0.8, 0),
		"handler": func(_p: Node) -> void: read(Layout.LORE_THROAT_NOTE), "accent": true, "accent_color": Color("ffe9b8"), "id": "hw_throat_note"})
	it.name = "NoteInteract"
	n.add_child(it)


func _build_inscription() -> void:
	var n := Node3D.new()
	n.name = "Inscription"
	add_child(n)
	n.position = Layout.THROAT["inscription"]
	var stone := Mat.outlined(Mat.toon(Art.SAND_DARK, {"rim": 0.25}), 0.016)
	Kit.add(n, Kit.box(Vector3(4.2, 0.7, 0.3), stone), Vector3(0, 4.1, 0.3))
	var l := Art.label(n, "IT HAS LEARNED A WELCOME", Vector3(0, 4.15, 0.1), 40, Color("f3e6c8"))
	l.rotation_degrees = Vector3(0, 180, 0)
	var it: Node3D = Interactable.new()
	it.setup({"text": "Read the carving over the stair", "size": Vector3(3.0, 2.4, 1.2), "offset": Vector3(0, 1.2, -0.4),
		"handler": func(_p: Node) -> void: read(Layout.LORE_BEFORE_CHOIR), "id": "hw_throat_inscription"})
	it.name = "InscriptionInteract"
	n.add_child(it)


## The bellmakers' order, painted on the east wall: the symbol set taught on the Bellmaker's Floor (room 5)
## in its taught order - large symbols, numbers and names (never pitch, never colour alone) - so the vault's
## resonators can be answered even if she no longer remembers room 5.
func _build_order_board() -> void:
	var n := Node3D.new()
	n.name = "OrderBoard"
	add_child(n)
	# Stands on two posts ORDER_BOARD_OUT in front of the wall: the room's rock dressing bulges ~0.3-0.6 m out of
	# the wall and covered the heading and numbers (VISUAL_BUGS IN-11).
	n.position = Layout.THROAT["order_board"] + Vector3(-ORDER_BOARD_OUT, 0, 0)
	n.rotation.y = -PI * 0.5             # faces west (-x), into the room
	var wood := Mat.outlined(Mat.toon(Color("5a3b27")), 0.016)
	var sheet_c := Color("efe0bd")
	var sheet := Mat.toon(sheet_c, {"emission": sheet_c, "emission_energy": 0.12})
	Kit.add(n, Kit.box(Vector3(2.7, 1.35, 0.08), wood), Vector3(0, 1.9, -0.06))
	Kit.add(n, Kit.box(Vector3(2.5, 1.15, 0.02), sheet), Vector3(0, 1.9, -0.01))
	for sx in [-1.0, 1.0]:
		Kit.add(n, Kit.box(Vector3(0.12, 2.75, 0.12), wood), Vector3(sx * 1.3, 1.375, -0.12))
		Kit.add(n, Kit.box(Vector3(0.08, 0.08, ORDER_BOARD_OUT), wood), Vector3(sx * 1.1, 2.45, -0.1 - ORDER_BOARD_OUT * 0.5))
	Kit.add(n, Kit.box(Vector3(2.95, 0.1, 0.3), wood), Vector3(0, 2.66, -0.06))
	Kit.static_collider(n, _box_shape(Vector3(2.8, 2.7, ORDER_BOARD_OUT + 0.1)), Vector3(0, 1.35, -0.1 - ORDER_BOARD_OUT * 0.5 + 0.05))
	var title := Art.label(n, "THE BELLMAKERS' ORDER", Vector3(0, 2.36, 0.02), 24, Color("3a2a22"))
	title.outline_size = 0
	var syms: Array = Layout.bell_symbols()
	var k := syms.size()
	for i in k:
		var s: Dictionary = syms[i]
		var x := (float(i) - float(k - 1) * 0.5) * 0.6
		var num := Art.label(n, str(i + 1), Vector3(x, 2.14, 0.02), 26, Color("3a2a22"))
		num.outline_size = 0
		var sym := Art.symbol(n, String(s["id"]), 0.36, Color("b0703a"), String(s.get("name", String(s["id"]).capitalize())), sheet_c)
		sym.position = Vector3(x, 1.86, 0.03)
		var tag: Variant = sym.get_node_or_null("Name")
		if tag is Label3D:
			(tag as Label3D).font_size = 20
	var it: Node3D = Interactable.new()
	it.setup({"text": "Read the bellmakers' order", "size": Vector3(2.6, 1.6, 1.2), "offset": Vector3(0, 1.8, 0.5),
		"handler": func(_p: Node) -> void: read_order(), "id": "hw_throat_order"})
	it.name = "OrderInteract"
	n.add_child(it)


## The taught order as words ("Leaf, then Moon, then Key, then Flame").
static func order_text() -> String:
	var names: Array = []
	for s in Layout.bell_symbols():
		names.append(String((s as Dictionary).get("name", String(s["id"]).capitalize())))
	return ", then ".join(PackedStringArray(names))


func read_order() -> String:
	var t := "The bellmakers' order: %s. The vault's resonators still answer to it." % order_text()
	Art.say(t, 7.0)
	return t


func _build_lift() -> void:
	lift = LiftScript.new()
	lift.setup({"id": "hw_throat_lift", "kind": "bell", "text": "Use the bell-rope lift (return or go on)",
		"sign": "REFUGE", "handler": Callable(self, "_on_lift")})
	lift.name = "BellLift"
	add_child(lift)
	lift.position = Layout.THROAT["lift"]
	lift.rotation.y = PI * 0.5          # cage mouth (local -z) faces west, into the room


static func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s
