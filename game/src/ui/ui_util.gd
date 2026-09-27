extends RefCounted
## Pure UI helpers (no scene tree needed) so they can be unit tested:
## hint token replacement, toast aggregation, inventory stack moves, clock / day formatting,
## input-binding codes and conflict detection, item stat lines, lore lookup and map projection.
##   const UiUtil := preload("res://src/ui/ui_util.gd")

const Layout := preload("res://data/world_layout.gd")

## Hint tokens -> input actions (see data/quests.gd). {move} is special (four movement keys).
const TOKEN_ACTIONS := {
	"interact": "interact", "attack": "attack", "inventory": "inventory", "craft": "craft", "build": "build",
	"sprint": "sprint", "jump": "jump", "dodge": "dodge", "lantern": "lantern", "journal": "journal",
	"map": "map", "use": "use_item", "help": "help", "pause": "pause", "companion": "companion_command",
	"rotate": "build_rotate", "dismantle": "build_dismantle",
}
const MOVE_ACTIONS := ["move_forward", "move_left", "move_back", "move_right"]

const CATEGORY_NAMES := {"resource": "Material", "tool": "Tool", "weapon": "Weapon", "food": "Food",
	"placeable": "Buildable", "seed": "Seed", "key": "Key Item", "equipment": "Equipment", "decor": "Decoration"}

const LORE_SCRIPT := "res://src/world/below/lore.gd"

## Tests set this to false so UI code never writes the player's real settings file.
static var allow_settings_save: bool = true


## Persists Settings (unless disabled for tests).
static func save_settings() -> void:
	if allow_settings_save:
		Settings.save()
const CRAFTING_SCRIPT := "res://src/crafting/crafting.gd"


# --- Hint tokens -------------------------------------------------------------------------------

## Replaces {interact}-style tokens with key labels from `label_fn(action) -> String`. Each label is
## wrapped in `open` + label + `close` (e.g. BBCode colour tags). Unknown tokens are left untouched.
static func fill_tokens(text: String, label_fn: Callable, open: String = "", close: String = "") -> String:
	var out := text
	if out.contains("{move}"):
		out = out.replace("{move}", open + move_label(label_fn) + close)
	for token in TOKEN_ACTIONS:
		var tag := "{%s}" % token
		if out.contains(tag):
			out = out.replace(tag, open + String(label_fn.call(TOKEN_ACTIONS[token])) + close)
	return out


## "WASD" when the four movement keys are single letters, otherwise "W / A / S / D".
static func move_label(label_fn: Callable) -> String:
	var labels: Array = []
	var all_single := true
	for a in MOVE_ACTIONS:
		var l := String(label_fn.call(a))
		labels.append(l)
		if l.length() != 1:
			all_single = false
	if all_single:
		return "".join(PackedStringArray(labels))
	return " / ".join(PackedStringArray(labels))


## Label function backed by the live Settings / InputMap.
static func settings_label(action: String) -> String:
	return Settings.action_label(action)


## Escapes text for use inside RichTextLabel BBCode.
static func bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


# --- Toasts ----------------------------------------------------------------------------------------

## "+3 Wood"
static func item_toast_text(item_id: String, count: int) -> String:
	var name := ItemDB.display_name(item_id) if ItemDB.has_item(item_id) else item_id.capitalize()
	return "+%d %s" % [count, name]


## Aggregating toast queue (pure model; the HUD renders it).
## Item pickups of the same item within `window` seconds merge into one "+N Name" toast; identical
## notification texts merge into "text (x2)". Entries expire after their lifetime.
class ToastModel extends RefCounted:
	var entries: Array = []          # [{id, key, kind, item, count, base_text, text, age, life}]
	var window: float = 2.5
	var max_entries: int = 5
	var _next_id: int = 1

	## Adds or merges an item pickup. Returns the entry.
	func push_item(item_id: String, count: int, life: float = 3.6) -> Dictionary:
		for e in entries:
			if e["key"] == "item:" + item_id and float(e["age"]) <= window:
				e["count"] = int(e["count"]) + count
				e["text"] = ToastText.item(item_id, int(e["count"]))
				e["age"] = 0.0
				e["life"] = maxf(float(e["life"]), life)
				e["bumped"] = true
				return e
		return _add({"key": "item:" + item_id, "kind": "item", "item": item_id, "count": count,
			"base_text": "", "text": ToastText.item(item_id, count), "life": life})

	## Adds or merges a text notification. Returns the entry.
	func push_text(text: String, kind: String = "info", life: float = 4.2) -> Dictionary:
		for e in entries:
			if e["key"] == "text:" + kind + ":" + text and float(e["age"]) <= window * 2.0:
				e["count"] = int(e["count"]) + 1
				e["text"] = "%s (x%d)" % [text, int(e["count"])]
				e["age"] = 0.0
				e["bumped"] = true
				return e
		return _add({"key": "text:" + kind + ":" + text, "kind": kind, "item": "", "count": 1,
			"base_text": text, "text": text, "life": life})

	## Key (quest) item toast with its icon, e.g. "Obtained: Foreman's Key". Returns the entry.
	func push_key_item(item_id: String, text: String, life: float = 5.5) -> Dictionary:
		for e in entries:
			if e["key"] == "key:" + text:
				e["age"] = 0.0
				return e
		return _add({"key": "key:" + text, "kind": "item", "item": item_id, "count": 1,
			"base_text": text, "text": text, "life": life})

	func has_key(key: String) -> bool:
		for e in entries:
			if e["key"] == key:
				return true
		return false

	func _add(e: Dictionary) -> Dictionary:
		e["id"] = _next_id
		_next_id += 1
		e["age"] = 0.0
		e["bumped"] = false
		entries.append(e)
		while entries.size() > max_entries:
			entries.pop_front()
		return e

	## Advances time; returns the ids of entries that expired.
	func tick(dt: float) -> Array:
		var gone: Array = []
		for e in entries:
			e["age"] = float(e["age"]) + dt
		for i in range(entries.size() - 1, -1, -1):
			if float(entries[i]["age"]) >= float(entries[i]["life"]):
				gone.append(entries[i]["id"])
				entries.remove_at(i)
		return gone


## Text helpers usable from the inner class (inner classes can't call the outer statics directly).
class ToastText extends RefCounted:
	static func item(item_id: String, count: int) -> String:
		var name := ItemDB.display_name(item_id) if ItemDB.has_item(item_id) else item_id.capitalize()
		return "+%d %s" % [count, name]


# --- Inventory stack moves ---------------------------------------------------------------------------

## Moves `count` items from src slot si to dst slot di (src and dst may be the same inventory).
## Empty target: moves. Same item: merges up to the stack limit. Different item: swaps, but only when
## the whole stack is moved. Returns true if anything changed. Never creates or destroys items.
static func move_stack(src: RefCounted, si: int, dst: RefCounted, di: int, count: int) -> bool:
	if src == null or dst == null:
		return false
	var a: Variant = src.get_slot(si)
	if a == null or count <= 0:
		return false
	if src == dst and si == di:
		return false
	if di < 0 or di >= int(dst.size):
		return false
	var a_id := String(a["id"])
	var a_count := int(a["count"])
	count = mini(count, a_count)
	var b: Variant = dst.get_slot(di)
	if b == null:
		var moved := {"id": a_id, "count": count}
		src.remove_from_slot(si, count)
		dst.set_slot(di, moved)
		return true
	var b_id := String(b["id"])
	var b_count := int(b["count"])
	if b_id == a_id:
		var room := ItemDB.stack_max(a_id) - b_count
		var put := mini(room, count)
		if put <= 0:
			return false
		src.remove_from_slot(si, put)
		dst.set_slot(di, {"id": b_id, "count": b_count + put})
		return true
	if count < a_count:
		return false
	src.set_slot(si, {"id": b_id, "count": b_count})
	dst.set_slot(di, {"id": a_id, "count": a_count})
	return true


## Half of a stack for a right-click split (rounded up so a single item can still be picked).
static func split_half(n: int) -> int:
	return maxi(1, int(ceil(float(n) / 2.0)))


## Quick-move (shift-click) inside the backpack: hotbar row <-> backpack rows. Returns moved count.
static func quick_move_within(inv: RefCounted, i: int, hotbar_size: int = 8) -> int:
	var s: Variant = inv.get_slot(i)
	if s == null:
		return 0
	var id := String(s["id"])
	var left := int(s["count"])
	var start := hotbar_size if i < hotbar_size else 0
	var end := int(inv.size) if i < hotbar_size else hotbar_size
	var moved := 0
	var mx := ItemDB.stack_max(id)
	# merge into existing stacks first, then empty slots
	for pass_i in 2:
		for j in range(start, end):
			if left <= 0:
				break
			var t: Variant = inv.get_slot(j)
			if pass_i == 0 and t != null and String(t["id"]) == id and int(t["count"]) < mx:
				var put := mini(left, mx - int(t["count"]))
				inv.set_slot(j, {"id": id, "count": int(t["count"]) + put})
				left -= put
				moved += put
			elif pass_i == 1 and t == null:
				var put2 := mini(left, mx)
				inv.set_slot(j, {"id": id, "count": put2})
				left -= put2
				moved += put2
	if moved > 0:
		inv.remove_from_slot(i, moved)
	return moved


# --- Clock ------------------------------------------------------------------------------------------

static func format_clock(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	var hh := int(floor(h))
	var mm := int(floor((h - float(hh)) * 60.0))
	return "%02d:%02d" % [hh, mm]


static func day_phase(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h < 5.0:
		return "Night"
	if h < 7.0:
		return "Dawn"
	if h < 12.0:
		return "Morning"
	if h < 17.0:
		return "Afternoon"
	if h < 20.0:
		return "Evening"
	return "Night"


# --- Input bindings -----------------------------------------------------------------------------------

## Stable code for an input event ("key:<physical>" / "mouse:<button>"), matching Settings' format.
static func event_code(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return "key:%d" % code
	if ev is InputEventMouseButton:
		return "mouse:%d" % (ev as InputEventMouseButton).button_index
	return ""


## Codes of every event bound to `action` in the live InputMap.
static func action_codes(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		var c := event_code(ev)
		if c != "":
			out.append(c)
	return out


## Actions (from `actions`) other than `action` that use `code`. `codes_fn(action) -> Array`.
static func find_conflicts(action: String, code: String, actions: Array, codes_fn: Callable) -> Array:
	var out: Array = []
	if code == "":
		return out
	for a in actions:
		if String(a) == action:
			continue
		var codes: Array = codes_fn.call(String(a))
		if codes.has(code):
			out.append(String(a))
	return out


## True if a captured event may be used as a binding (not Escape, which always cancels capture).
static func is_bindable(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return k.pressed and not k.echo and code != KEY_ESCAPE and code != 0
	if ev is InputEventMouseButton:
		return (ev as InputEventMouseButton).pressed
	return false


# --- Items -----------------------------------------------------------------------------------------------

static func category_name(cat: String) -> String:
	return String(CATEGORY_NAMES.get(cat, cat.capitalize()))


## Short stat lines for tooltips / detail cards, all read from ItemDB.
static func item_stat_lines(item_id: String) -> Array:
	var out: Array = []
	if not ItemDB.has_item(item_id):
		return out
	var d := ItemDB.item(item_id)
	var heal := float(d.get("heal", 0.0))
	if heal > 0.0:
		out.append("Restores %d health" % int(round(heal)))
	var buff: Variant = d.get("buff", null)
	if buff is Dictionary and (buff as Dictionary).has("stamina_regen"):
		out.append("Faster stamina recovery for %s" % _duration(float((buff as Dictionary).get("seconds", 60.0))))
	var tool := String(d.get("tool", ""))
	if tool != "":
		out.append("Tool: %s" % ("Axe (fells trees)" if tool == "axe" else ("Pickaxe (breaks rocks)" if tool == "pickaxe" else tool.capitalize())))
	var dmg := float(d.get("damage", 0.0))
	if dmg > 0.0:
		out.append("Damage %d" % int(round(dmg)))
	if String(d.get("cat", "")) == "equipment" and item_id == "lantern":
		out.append("Equipment: always ready. Press %s to raise it." % Settings.action_label("lantern"))
	if String(d.get("cat", "")) == "placeable":
		out.append("Place it in the Haven with %s" % Settings.action_label("build"))
	if String(d.get("cat", "")) == "seed":
		out.append("Plant in a Crop Plot")
	var stack := int(d.get("stack", 1))
	if stack > 1:
		out.append("Stacks to %d" % stack)
	return out


static func _duration(seconds: float) -> String:
	if seconds >= 60.0:
		var m := int(round(seconds / 60.0))
		return "%d min" % m
	return "%d s" % int(round(seconds))


# --- Lore ---------------------------------------------------------------------------------------------------

## {title, text} for a lore id from res://src/world/below/lore.gd (static get_lore(id)) if available.
static func lore_entry(lore_id: String) -> Dictionary:
	var out := {"title": lore_id.replace("_", " ").capitalize(), "text": "The page is too faded to read."}
	if ResourceLoader.exists(LORE_SCRIPT):
		var s: Script = load(LORE_SCRIPT)
		if s != null and s.can_instantiate() and s.has_method("get_lore"):
			var d: Variant = s.call("get_lore", lore_id)
			if d is Dictionary:
				var t := String((d as Dictionary).get("title", ""))
				var x := String((d as Dictionary).get("text", ""))
				if t.strip_edges() != "":
					out["title"] = t
				if x.strip_edges() != "":
					out["text"] = x
	return out


# --- Crafting (defensive wrappers over src/crafting/crafting.gd) -----------------------------------------------

static func crafting_script() -> Script:
	if not ResourceLoader.exists(CRAFTING_SCRIPT):
		return null
	var s: Script = load(CRAFTING_SCRIPT)
	if s == null or not s.can_instantiate():
		return null
	return s


## Stations near a position ("hand" always included). `extra` is added (e.g. the workbench that opened us).
static func stations_near(pos: Variant, extra: String = "") -> Array:
	var out: Array = ["hand"]
	var s := crafting_script()
	if s != null and s.has_method("stations_near") and pos is Vector3:
		var r: Variant = s.call("stations_near", pos)
		if r is Array:
			for st in r:
				if not out.has(String(st)):
					out.append(String(st))
	if extra != "" and not out.has(extra):
		out.append(extra)
	return out


static func known_recipes() -> Array:
	var s := crafting_script()
	if s != null and s.has_method("known_recipes"):
		var r: Variant = s.call("known_recipes")
		if r is Array:
			return r
	var out: Array = []
	for rid in ItemDB.all_recipe_ids():
		if ItemDB.recipe_known(rid):
			out.append(rid)
	return out


## {"ok", "reason", "missing": {item: n}} (uses the crafting module when present).
static func craft_check(recipe_id: String, stations: Array) -> Dictionary:
	var s := crafting_script()
	if s != null and s.has_method("check"):
		var r: Variant = s.call("check", recipe_id, stations)
		if r is Dictionary:
			return r
	var rec := ItemDB.recipe(recipe_id)
	if rec.is_empty():
		return {"ok": false, "reason": "Unknown recipe.", "missing": {}}
	var missing := {}
	var ings: Dictionary = rec.get("ingredients", {})
	for id in ings:
		var have := GameState.count_item(id)
		if have < int(ings[id]):
			missing[id] = int(ings[id]) - have
	var st := String(rec.get("station", "hand"))
	if not stations.has(st):
		return {"ok": false, "reason": "You need to be near a %s." % ItemDB.station_name(st), "missing": missing}
	if not missing.is_empty():
		return {"ok": false, "reason": "Missing ingredients.", "missing": missing}
	return {"ok": true, "reason": "", "missing": {}}


## Crafts through the crafting module (transactional). Falls back to a careful local transaction.
static func craft(recipe_id: String, stations: Array) -> bool:
	var s := crafting_script()
	if s != null and s.has_method("craft"):
		return bool(s.call("craft", recipe_id, stations))
	if not bool(craft_check(recipe_id, stations).get("ok", false)):
		return false
	var rec := ItemDB.recipe(recipe_id)
	var snap: Array = GameState.inventory.snapshot()
	var ings: Dictionary = rec.get("ingredients", {})
	for id in ings:
		if not GameState.take_item(id, int(ings[id])):
			GameState.inventory.restore(snap)
			return false
	GameState.give_item(String(rec["result"]), int(rec.get("count", 1)))
	GameState.stats["items_crafted"] = int(GameState.stats.get("items_crafted", 0)) + 1
	Events.crafted.emit(recipe_id, String(rec["result"]), int(rec.get("count", 1)))
	return true


# --- Map ----------------------------------------------------------------------------------------------------

## World XZ -> map rect position (north = up). `half_extent` = world half size shown.
static func world_to_map(world_xz: Vector2, rect: Rect2, half_extent: float = Layout.WORLD_HALF_EXTENT + 8.0) -> Vector2:
	var u := (world_xz.x + half_extent) / (half_extent * 2.0)
	var v := (world_xz.y + half_extent) / (half_extent * 2.0)
	return rect.position + Vector2(u * rect.size.x, v * rect.size.y)


static func map_to_world(p: Vector2, rect: Rect2, half_extent: float = Layout.WORLD_HALF_EXTENT + 8.0) -> Vector2:
	var u := (p.x - rect.position.x) / maxf(rect.size.x, 0.001)
	var v := (p.y - rect.position.y) / maxf(rect.size.y, 0.001)
	return Vector2(u * half_extent * 2.0 - half_extent, v * half_extent * 2.0 - half_extent)


## Screen angle (radians, 0 = east/right, PI/2 = south/down) for a 3D forward vector.
static func map_heading(forward: Vector3) -> float:
	var f := Vector2(forward.x, forward.z)
	if f.length_squared() < 0.000001:
		return -PI * 0.5
	return f.angle()


## Landmark display name ("" if unknown).
static func landmark_name(id: String) -> String:
	var lm: Dictionary = Layout.LANDMARKS.get(id, {})
	return String(lm.get("name", ""))
