extends RefCounted
## Slot-based inventory used for the player backpack (slots 0..7 are the hotbar) and storage chests.
## A slot is either null or {"id": String, "count": int}. All mutating calls emit `changed`.
## Quest (key) items never live here: GameState keeps them in a separate key pouch.

signal changed

var size: int = 0
var slots: Array = []


func _init(p_size: int = 32) -> void:
	size = p_size
	slots.resize(size)
	for i in size:
		slots[i] = null


# --- Queries -----------------------------------------------------------------

func count_of(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["id"] == id:
			n += int(s["count"])
	return n


func has(id: String, count: int = 1) -> bool:
	return count_of(id) >= count


## How many more of `id` fit in this inventory (existing stacks + empty slots).
func space_for(id: String) -> int:
	var mx := ItemDB.stack_max(id)
	var n := 0
	for s in slots:
		if s == null:
			n += mx
		elif s["id"] == id:
			n += max(0, mx - int(s["count"]))
	return n


func can_add(id: String, count: int) -> bool:
	return space_for(id) >= count


func is_empty() -> bool:
	for s in slots:
		if s != null:
			return false
	return true


func free_slots() -> int:
	var n := 0
	for s in slots:
		if s == null:
			n += 1
	return n


func get_slot(i: int) -> Variant:
	if i < 0 or i >= size:
		return null
	return slots[i]


## Summary {id: count} of everything held.
func totals() -> Dictionary:
	var out := {}
	for s in slots:
		if s != null:
			out[s["id"]] = int(out.get(s["id"], 0)) + int(s["count"])
	return out


# --- Mutations -----------------------------------------------------------------

## Adds up to `count` items, filling existing stacks first, then empty slots (hotbar first).
## Returns the number that did NOT fit (0 = everything was added).
## Unknown item ids never enter an inventory (they would be silently discarded on load): all `count` is returned.
func add(id: String, count: int) -> int:
	if count <= 0:
		return 0
	if not ItemDB.has_item(id):
		push_warning("Inventory: refusing unknown item '%s'" % id)
		return count
	var mx := ItemDB.stack_max(id)
	var left := count
	for i in size:
		if left <= 0:
			break
		var s = slots[i]
		if s != null and s["id"] == id and int(s["count"]) < mx:
			var put: int = min(left, mx - int(s["count"]))
			s["count"] = int(s["count"]) + put
			left -= put
	for i in size:
		if left <= 0:
			break
		if slots[i] == null:
			var put: int = min(left, mx)
			slots[i] = {"id": id, "count": put}
			left -= put
	if left != count:
		changed.emit()
	return left


## Removes exactly `count` of `id` or nothing at all. Takes from the last stacks first.
func remove(id: String, count: int) -> bool:
	if count <= 0:
		return true
	if count_of(id) < count:
		return false
	var left := count
	for i in range(size - 1, -1, -1):
		if left <= 0:
			break
		var s = slots[i]
		if s != null and s["id"] == id:
			var take: int = min(left, int(s["count"]))
			s["count"] = int(s["count"]) - take
			left -= take
			if int(s["count"]) <= 0:
				slots[i] = null
	changed.emit()
	return true


## Removes up to `count` from one slot; returns how many were removed.
func remove_from_slot(i: int, count: int) -> int:
	var s = get_slot(i)
	if s == null or count <= 0:
		return 0
	var take: int = min(count, int(s["count"]))
	s["count"] = int(s["count"]) - take
	if int(s["count"]) <= 0:
		slots[i] = null
	changed.emit()
	return take


## Sets a slot to `stack` ({"id", "count"}) or clears it (null / count <= 0).
## Malformed stacks (not a Dictionary, missing/unknown id) are ignored with a warning so data is never mangled.
func set_slot(i: int, stack: Variant) -> void:
	if i < 0 or i >= size:
		return
	if stack == null:
		slots[i] = null
		changed.emit()
		return
	if not (stack is Dictionary) or not _is_number(stack.get("count", 0)):
		push_warning("Inventory: set_slot ignored malformed stack %s" % str(stack))
		return
	if int(stack.get("count", 0)) <= 0:
		slots[i] = null
	elif not ItemDB.has_item(str(stack.get("id", ""))):
		push_warning("Inventory: set_slot ignored unknown item %s" % str(stack.get("id", "")))
		return
	else:
		slots[i] = {"id": str(stack["id"]), "count": int(stack["count"])}
	changed.emit()


func clear_slot(i: int) -> void:
	set_slot(i, null)


## Move/merge/swap slot `from` onto slot `to` within this inventory.
func move(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= size or to >= size:
		return
	var a = slots[from]
	var b = slots[to]
	if a == null:
		return
	if b != null and b["id"] == a["id"]:
		var mx := ItemDB.stack_max(a["id"])
		var put: int = min(int(a["count"]), mx - int(b["count"]))
		b["count"] = int(b["count"]) + put
		a["count"] = int(a["count"]) - put
		if int(a["count"]) <= 0:
			slots[from] = null
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## Moves as much of slot `i` as fits into `other`. Returns how many moved.
func transfer_slot_to(other: RefCounted, i: int) -> int:
	var s = get_slot(i)
	if s == null or other == null or other == self:
		return 0
	var id: String = s["id"]
	var n: int = int(s["count"])
	var left: int = other.add(id, n)
	var moved := n - left
	if moved > 0:
		remove_from_slot(i, moved)
	return moved


## Sort by category then name, merging partial stacks. Keeps the hotbar (0..7) untouched when keep_hotbar.
func sort_items(keep_hotbar: bool = true) -> void:
	var start := 8 if keep_hotbar and size > 8 else 0
	var t := {}
	for i in range(start, size):
		var s = slots[i]
		if s != null:
			t[s["id"]] = int(t.get(s["id"], 0)) + int(s["count"])
			slots[i] = null
	var ids := t.keys()
	var order: Array = preload("res://data/items.gd").CATEGORY_ORDER
	ids.sort_custom(func(x, y):
		var cx := order.find(ItemDB.category(x))
		var cy := order.find(ItemDB.category(y))
		if cx != cy:
			return cx < cy
		var nx := ItemDB.display_name(x)
		var ny := ItemDB.display_name(y)
		if nx != ny:
			return nx < ny
		return String(x) < String(y))   # deterministic tie-break
	var idx := start
	for id in ids:
		var left: int = t[id]
		var mx := ItemDB.stack_max(id)
		while left > 0 and idx < size:
			var put: int = min(left, mx)
			slots[idx] = {"id": id, "count": put}
			left -= put
			idx += 1
	changed.emit()


# --- Persistence ---------------------------------------------------------------------

func to_array() -> Array:
	var out := []
	for s in slots:
		out.append(null if s == null else {"id": s["id"], "count": int(s["count"])})
	return out


## Replaces the contents from a to_array() result. Malformed entries and unknown item ids are
## skipped safely (never a script error); counts are normalised to int (JSON loads them as float).
func from_array(arr: Array) -> void:
	for i in size:
		slots[i] = null
	for i in mini(arr.size(), size):
		var s = arr[i]
		if not (s is Dictionary) or not (s.get("id") is String) or not _is_number(s.get("count", 0)):
			continue
		if int(s.get("count", 0)) > 0 and ItemDB.has_item(String(s["id"])):
			slots[i] = {"id": String(s["id"]), "count": int(s["count"])}
	changed.emit()


static func _is_number(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v))   # JSON reads 1e99999 back as INF


## Deep copy of the slot array (for transactional operations).
func snapshot() -> Array:
	return to_array()


func restore(arr: Array) -> void:
	from_array(arr)
