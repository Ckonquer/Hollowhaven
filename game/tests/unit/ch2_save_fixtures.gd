extends RefCounted
## Synthetic save fixtures for the schema-v2 migration matrix (MP §20.2, docs/SAVE_MIGRATION.md).
## Not a test suite (no test_ prefix): test_save_v2_matrix.gd uses it.
##
## Every scenario is BUILT IN CODE from real GameState calls (new_game, give_item, add_structure,
## befriend, QuestLog.evaluate ...), then reduced to the exact shape the shipped v0.9.1 build writes
## (version 1: the 20 legacy state keys, legacy companion/player/stats keys, a 32-slot backpack) and
## serialised the way SaveSystem does. The same texts are committed under res://tests/fixtures/saves/
## (<name>.json = slot1.json, <name>.bak.json = slot1.bak.json) for tools/qa/save_integrity.py.
## test_save_v2_matrix checks that the committed files and these builders agree; regenerate them with
##   cd game && ../tools/godot.sh --headless --path . res://tests/runner.tscn -- --filter=save_v2_matrix --write-fixtures
## Builders mutate the global GameState (tests restore it). They keep GameState.active false while building
## so no deferred quest evaluation runs in between.

const FIXTURE_DIR := "res://tests/fixtures/saves"
const SAVED_UNIX := 1790000000.0
const GAME_VERSION := "0.9.1"
const LEGACY_STATE_KEYS := ["player_name", "inventory", "key_items", "hotbar_index", "player", "flags", "counters",
	"quests", "companions", "active_companion", "structures", "storages", "crops", "depleted", "dropped",
	"lore", "total_minutes", "stats", "buffs", "next_uid"]
const LEGACY_PLAYER_KEYS := ["hp", "max_hp", "stamina", "max_stamina", "area", "pos", "yaw", "spawn",
	"respawn_area", "respawn_spawn", "lantern_on", "below_respawn"]
const LEGACY_COMPANION_KEYS := ["befriended", "bond_xp", "assignment", "wait_area", "wait_pos", "last_pet_day",
	"last_gift_day", "last_fed_day", "work_day", "work_xp", "zones"]
const LEGACY_CREATURES := ["mochi", "pebble", "lumi"]
const LEGACY_STATS_KEYS := ["play_seconds", "deaths", "enemies_defeated", "items_crafted", "started_version"]
const V1_BACKPACK := 32
## Companion keys schema v2 adds (the only keys a migrated companion record may gain).
const V2_COMPANION_KEYS := ["combat_mode", "skill_ready_at", "home_spot", "ribbon", "home_task"]
## Temporary item ids the v2 fixtures use (the matrix test injects their definitions into ItemDB).
const FAKE_ITEMS := {"fixture_hood": {"name": "Fixture Hood", "cat": "armor", "slot": "head", "stack": 1},
	"fixture_charm": {"name": "Fixture Charm", "cat": "charm", "stack": 1}}

## Scenario -> what it covers. Order = MP §20.2 numbering, then extra cases from the state map.
const SCENARIOS := {
	"01_fresh_new_game": {"kind": "v1", "about": "Fresh profile: the first quiet save right after New Game."},
	"02_early_before_pets": {"kind": "v1", "about": "Early Chapter One before any pet: tools, a workbench, a since_start baseline."},
	"03_mid_home_full_bag": {"kind": "v1", "about": "Mid Chapter One: buildings, two chests, a crop, a FULL backpack and a waiting companion."},
	"04_before_matron": {"kind": "v1", "about": "In the Below just before the Matron with stone/copper gear, the key in the pouch, below_respawn."},
	"05_weaver_defeated": {"kind": "v1", "about": "Weaver defeated, Heartseed held but not yet returned."},
	"06_interrupted_restoration": {"kind": "v1", "about": "Heartseed returned (ward_restored) but the ending never finished: no chapter_one_complete, 'return' pending."},
	"07_c1_complete_free_play": {"kind": "v1", "about": "Chapter One complete at free_play; bond/heartbloom goals NOT done."},
	"08_c1_complete_goals_done": {"kind": "v1", "about": "Chapter One complete with both free_play goals already done (index 16)."},
	"09_dense_home_overflow": {"kind": "v1", "about": "Dense home with a raised storey, several filled chests, crops, a full bag and dropped overflow."},
	"10_custom_save_dir": {"kind": "v1", "about": "A save that lives in a custom --save-dir folder."},
	"11_current_schema_twice": {"kind": "v2", "about": "A current-schema (v2) save with Chapter Two progress, loaded twice."},
	"12a_malformed_main_good_bak": {"kind": "v1_bak", "about": "Torn main save with a valid version-1 backup."},
	"12b_future_main": {"kind": "future", "about": "A version-3 main save (newer game) with a valid version-1 backup: refused in place."},
	"13_state_empty": {"kind": "v1", "about": "A valid file whose state is {} (every section defaulted)."},
	"14_stuck_dungeon_ward_restored": {"kind": "v1", "about": "Sequence break: ward_restored set while the tracker still sits on old_mine."},
	"15_v2_unknown_ids": {"kind": "v2", "about": "A v2 save with item/structure ids this build doesn't know and unknown keys."},
}


# --- Public helpers ------------------------------------------------------------------------------------

## Saves written by the REAL shipped builds (byte-for-byte copies, never regenerated): QA-bot playthroughs,
## NOT Krystal's personal save (MP §2.2 / §20.1). They prove the migration on the exact file shape the game
## writes, which the synthetic builders only reproduce. Source + SHA-256 of each copied file:
const REAL_SAMPLES := {
	"16_real_handoff_c1_complete": {"about": "REAL v0.9.0 build (QA bot): the handoff's Chapter-One-complete sample at free_play, backup at 'return' with the Heartseed. NOT Krystal's save.",
		"source": "Desktop/Hollowhaven_Part2_Handoff/save_chapter1_complete/slot1.json (+ slot1.bak.json)",
		"sha256": "a72362e5d32a9d76a2373b17be60aa67b2f4340003e20a8b7a5bce343eff8c7b", "sha256_bak": "db6e09cb2d7e084c10f11012c207d6300eaf56a17eda3b56d9758fd9e5962878"},
	"17_real_release_below_silk": {"about": "REAL v0.9.0 release build (QA bot): in the Below on 'silk' with the Foreman's Key and a dropped item; backup on 'deeper'.",
		"source": "qa/tmp/e2e/release4/checkpoints/silk_and_boss/slot1.json (+ slot1.bak.json)",
		"sha256": "012037c78af484932bbc1dac69d10036ec068783032ec9e6179dfc9aabd46d4e", "sha256_bak": "08458ff8cce69c175bb89d0ec47c3ef71de088a63505f8ee984b582a681a14e0"},
}


static func scenario_names() -> Array:
	return SCENARIOS.keys()


static func real_sample_names() -> Array:
	return REAL_SAMPLES.keys()


## {"main": text, "bak": text or ""} built from code.
static func build(name: String) -> Dictionary:
	var main_d: Variant = null
	var bak_d: Variant = null
	match name:
		"01_fresh_new_game":
			main_d = _s01()
		"02_early_before_pets":
			main_d = _s02()
		"03_mid_home_full_bag":
			main_d = _s03()
		"04_before_matron":
			main_d = _s04()
		"05_weaver_defeated":
			main_d = _s05()
		"06_interrupted_restoration":
			main_d = _s06()
		"07_c1_complete_free_play":
			main_d = _s07()
		"08_c1_complete_goals_done":
			main_d = _s08()
		"09_dense_home_overflow":
			main_d = _s09()
		"10_custom_save_dir":
			main_d = _s10()
		"11_current_schema_twice":
			main_d = _s11()
		"12a_malformed_main_good_bak":
			bak_d = _s02()
			main_d = "{\"format\": \"hollowhaven-save\", \"version\": 1, \"state\": {\"player_name\": \"Krystal\", \"inventory\": [{\"id\": \"wo"
		"12b_future_main":
			bak_d = _s07()
			main_d = _future_file()
		"13_state_empty":
			main_d = {"format": "hollowhaven-save", "version": 1, "game_version": GAME_VERSION, "saved_unix": SAVED_UNIX, "state": {}}
		"14_stuck_dungeon_ward_restored":
			main_d = _s14()
		"15_v2_unknown_ids":
			main_d = _s15()
		_:
			push_error("unknown fixture " + name)
	GameState.active = false
	return {"main": _text(main_d), "bak": _text(bak_d) if bak_d != null else ""}


## The committed files: {"main": text, "bak": text or ""} ("" when the file does not exist).
static func load_files(name: String) -> Dictionary:
	return {"main": _read(FIXTURE_DIR.path_join(name + ".json")), "bak": _read(FIXTURE_DIR.path_join(name + ".bak.json"))}


## Writes every built scenario to FIXTURE_DIR (developer action, see the header). Returns the paths.
static func write_all() -> Array:
	var out: Array = []
	var dir := ProjectSettings.globalize_path(FIXTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in SCENARIOS:
		var b := build(name)
		out.append(_write(dir.path_join(name + ".json"), b["main"]))
		if String(b["bak"]) != "":
			out.append(_write(dir.path_join(name + ".bak.json"), b["bak"]))
	var readme := "Synthetic save fixtures (generated by game/tests/unit/ch2_save_fixtures.gd; do not edit by hand).\n"
	readme += "<name>.json = slot1.json, <name>.bak.json = slot1.bak.json. See docs/SAVE_MIGRATION.md.\n\n"
	for name in SCENARIOS:
		readme += "%s  [%s]  %s\n" % [name, SCENARIOS[name]["kind"], SCENARIOS[name]["about"]]
	readme += "\nReal-build samples (byte-for-byte copies of files the shipped game wrote; NOT generated, never rewritten):\n"
	for name in REAL_SAMPLES:
		var r: Dictionary = REAL_SAMPLES[name]
		readme += "%s  [v1 real]  %s\n    from %s\n    sha256 %s (bak %s)\n" % [name, r["about"], r["source"], r["sha256"], r["sha256_bak"]]
	out.append(_write(dir.path_join("README.txt"), readme))
	return out


static func install_fake_items() -> void:
	for id in FAKE_ITEMS:
		var d: Dictionary = ItemDB.ITEM_DEFAULTS.duplicate()
		d.merge(FAKE_ITEMS[id], true)
		d["id"] = id
		ItemDB._items[id] = d


static func remove_fake_items() -> void:
	for id in FAKE_ITEMS:
		ItemDB._items.erase(id)


# --- Canonical comparison (MP §2.1 / §20.1): what migration must preserve --------------------------------

## Differences between a version-1 state and a loaded/migrated state (both JSON-normalised: numbers are
## floats). Allowed (documented) changes only: new schema-v2 sections; new companion keys; companion
## records for creatures added later; backpack/chest arrays grown with EMPTY slots; unknown-id stacks moved
## to `orphans` (same slot); a baseline added for the current legacy step; next_uid never lower.
## Returns [] when everything the player owns and has done is preserved.
static func preserved_diff(v1: Dictionary, v2: Dictionary) -> Array:
	var out: Array = []
	var orphans: Array = v2.get("orphans", []) if v2.get("orphans") is Array else []
	for k in ["player_name", "hotbar_index", "flags", "counters", "active_companion", "structures", "crops",
			"depleted", "lore", "total_minutes", "buffs"]:
		if v1.has(k):
			_cmp(v1[k], v2.get(k), k, out)
	_cmp_slots(_arr(v1.get("inventory")), _arr(v2.get("inventory")), "inventory", "inventory", orphans, out)
	var st1 := _dict(v1.get("storages"))
	var st2 := _dict(v2.get("storages"))
	for uid in st1:
		if not st2.has(uid):
			out.append("storages/%s: chest binding lost" % uid)
		else:
			_cmp_slots(_arr(st1[uid]), _arr(st2[uid]), "storages/" + str(uid), "storage:" + str(uid), orphans, out)
	var k1 := _dict(v1.get("key_items"))
	var k2 := _dict(v2.get("key_items"))
	for id in k1:
		if k2.get(id) != k1[id] and not _orphaned(orphans, "key_items", -1, id, k1[id]):
			out.append("key_items/%s: %s != %s" % [id, str(k1[id]), str(k2.get(id))])
	for id in k2:
		if not k1.has(id):
			out.append("key_items/%s: unexpected new key item" % id)
	var p1 := _dict(v1.get("player"))
	var p2 := _dict(v2.get("player"))
	for k in p1:
		_cmp(p1[k], p2.get(k), "player/" + str(k), out)
	var s1 := _dict(v1.get("stats"))
	var s2 := _dict(v2.get("stats"))
	for k in s1:
		_cmp(s1[k], s2.get(k), "stats/" + str(k), out)
	var q1 := _dict(v1.get("quests"))
	var q2 := _dict(v2.get("quests"))
	if v1.has("quests"):
		_cmp(q1.get("index"), q2.get("index"), "quests/index", out)
		_cmp(q1.get("completed"), q2.get("completed"), "quests/completed", out)
		var b1 := _dict(q1.get("baselines"))
		var b2 := _dict(q2.get("baselines"))
		for sid in b1:
			_cmp(b1[sid], b2.get(sid), "quests/baselines/" + str(sid), out)
	var c1 := _dict(v1.get("companions"))
	var c2 := _dict(v2.get("companions"))
	for id in c1:
		var r1 := _dict(c1[id])
		var r2 := _dict(c2.get(id))
		if r2.is_empty():
			out.append("companions/%s: record lost" % id)
			continue
		for k in r1:
			_cmp(r1[k], r2.get(k), "companions/%s/%s" % [id, k], out)
		for k in r2:
			if not r1.has(k) and not V2_COMPANION_KEYS.has(k):
				out.append("companions/%s/%s: undocumented new key" % [id, k])
	var d1 := _arr(v1.get("dropped"))
	var d2 := _arr(v2.get("dropped"))
	var kept: Array = []
	for rec in d1:
		if rec is Dictionary and _orphaned(orphans, "dropped", -1, rec.get("item"), rec.get("count")):
			continue
		kept.append(rec)
	_cmp(kept, d2, "dropped", out)
	var n1: Variant = v1.get("next_uid")
	var n2: Variant = v2.get("next_uid")
	if (n1 is float or n1 is int) and (not (n2 is float or n2 is int) or float(n2) < float(n1)):
		out.append("next_uid: %s < %s" % [str(n2), str(n1)])
	return out


## Schema-v2 sections that must exist after a migration.
static func missing_v2_sections(v2: Dictionary) -> Array:
	var out: Array = []
	for k in GameState.v2_section_defaults():
		if not v2.has(k):
			out.append(k)
	return out


static func _cmp_slots(a: Array, b: Array, path: String, where: String, orphans: Array, out: Array) -> void:
	if b.size() < a.size():
		out.append("%s: %d slots became %d" % [path, a.size(), b.size()])
	for i in a.size():
		var x: Variant = a[i]
		var y: Variant = b[i] if i < b.size() else null
		if _same(x, y):
			continue
		if x is Dictionary and y == null and _orphaned(orphans, where, i, x.get("id"), x.get("count")):
			continue
		out.append("%s[%d]: %s != %s" % [path, i, str(x), str(y)])
	for i in range(a.size(), b.size()):
		if b[i] != null:
			out.append("%s[%d]: new slot is not empty (%s)" % [path, i, str(b[i])])


static func _orphaned(orphans: Array, where: String, slot: int, id: Variant, count: Variant) -> bool:
	for o in orphans:
		if not (o is Dictionary) or not (o.get("stack") is Dictionary):
			continue
		if String(o.get("where", "")) != where:
			continue
		if slot >= 0 and int(o.get("slot", -1)) != slot:
			continue
		if o["stack"].get("id") == id and _same(o["stack"].get("count"), count):
			return true
	return false


static func _cmp(a: Variant, b: Variant, path: String, out: Array) -> void:
	if not _same(a, b):
		out.append("%s: %s != %s" % [path, _short(a), _short(b)])


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	return a == b


static func _short(v: Variant) -> String:
	var s := str(v)
	return s if s.length() <= 160 else s.substr(0, 157) + "..."


# --- File shape -----------------------------------------------------------------------------------------

## The current GameState reduced to exactly what v0.9.1 (save version 1) writes.
static func v1_state() -> Dictionary:
	var st := GameState.to_dict()
	var out := {}
	for k in LEGACY_STATE_KEYS:
		out[k] = st[k]
	out["inventory"] = (st["inventory"] as Array).slice(0, V1_BACKPACK)
	var comps := {}
	for id in LEGACY_CREATURES:
		var rec: Dictionary = st["companions"].get(id, {})
		var r := {}
		for k in LEGACY_COMPANION_KEYS:
			if rec.has(k):
				r[k] = rec[k]
		comps[id] = r
	out["companions"] = comps
	var p := {}
	for k in LEGACY_PLAYER_KEYS:
		p[k] = st["player"][k]
	out["player"] = p
	var s := {}
	for k in LEGACY_STATS_KEYS:
		s[k] = st["stats"][k]
	out["stats"] = s
	return out


## A version-1 save file for the current GameState (meta as v0.9.1 wrote it).
static func v1_file() -> Dictionary:
	var step: Dictionary = GameState.quests.current_step()
	return {"format": "hollowhaven-save", "version": 1, "game_version": GAME_VERSION, "saved_unix": SAVED_UNIX,
		"meta": {"day": GameState.day(), "step": String(step.get("id", "")),
			"step_title": String(step.get("title", "Chapter complete")) if not step.is_empty() else "Chapter complete",
			"play_seconds": float(GameState.stats.get("play_seconds", 0.0)), "area": String(GameState.player.get("area", "surface"))},
		"state": v1_state()}


## A version-2 save file for the current GameState (what this build writes). Companion records, player and
## stats keys are limited to the ones this schema defines, so a creature or stat added by a later module does
## not make the committed fixture stale.
static func v2_file() -> Dictionary:
	var d := SaveSystem.build_save_data()
	d["saved_unix"] = SAVED_UNIX
	d["game_version"] = GAME_VERSION
	var st: Dictionary = d["state"]
	var comps := {}
	for id in LEGACY_CREATURES:
		var rec: Dictionary = st["companions"].get(id, {})
		var r := {}
		for k in rec:
			if LEGACY_COMPANION_KEYS.has(k) or V2_COMPANION_KEYS.has(k):
				r[k] = rec[k]
		comps[id] = r
	st["companions"] = comps
	for section in [["player", LEGACY_PLAYER_KEYS], ["stats", LEGACY_STATS_KEYS]]:
		var src: Dictionary = st[section[0]]
		var trimmed := {}
		for k in section[1]:
			trimmed[k] = src[k]
		st[section[0]] = trimmed
	return d


static func _text(d: Variant) -> String:
	if d is String:
		return d
	return JSON.stringify(d, "\t")


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func _write(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	return path


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


# --- Scenario builders (real GameState calls) -------------------------------------------------------------

static func _fresh() -> void:
	GameState.new_game()
	GameState.player_name = "Krystal"   # reset() keeps the name (legacy); builders must not leak it
	GameState.active = false   # no deferred evaluation while building


static func _set_bag(stacks: Array) -> void:
	GameState.inventory.from_array([])
	for i in stacks.size():
		if stacks[i] != null:
			GameState.inventory.set_slot(i, {"id": stacks[i][0], "count": stacks[i][1]})


## Early game up to the "mochi" step (index 5), using the real quest chain.
static func _early() -> void:
	_fresh()
	GameState.set_flag("read_ward_intro")
	GameState.quests.evaluate()                      # -> gather_basics
	GameState.give_item("wood", 12)
	GameState.give_item("stone", 6)
	GameState.give_item("fiber", 5)
	GameState.quests.evaluate()                      # -> craft_axe
	GameState.take_item("wood", 3)
	GameState.take_item("stone", 2)
	GameState.take_item("fiber", 2)
	GameState.give_item("stone_axe", 1)
	GameState.stats["items_crafted"] = 1
	GameState.quests.evaluate()                      # -> chop (baseline trees_felled 0)
	GameState.add_counter("trees_felled", 3)
	GameState.give_item("wood", 10)
	GameState.quests.evaluate()                      # -> workbench
	GameState.take_item("wood", 8)
	GameState.take_item("stone", 2)
	GameState.add_structure("workbench", Vector3(3.0, 0.0, -2.0), 90.0)
	GameState.add_counter("structures_built")
	GameState.stats["items_crafted"] = 2
	GameState.quests.evaluate()                      # -> mochi
	GameState.deplete("tree_3", 600.0)
	GameState.deplete("tree_7", 600.0)
	GameState.total_minutes = 480.0 + 95.5
	GameState.stats["play_seconds"] = 380.25
	GameState.player["pos"] = [2.5, 0.125, 6.0]
	GameState.player["yaw"] = 0.75
	GameState.select_hotbar(1)


## A home with both first pets, up to the "lumi" step (index 8).
static func _home() -> void:
	_early()
	GameState.befriend("mochi")
	GameState.quests.evaluate()                      # mochi done (3 sweetroot_seeds) -> pebble
	GameState.give_item("stone_pickaxe", 1)
	GameState.befriend("pebble")                     # pebble follows, mochi goes home
	GameState.quests.evaluate()                      # pebble done (2 copper_ore) -> home
	var bed := GameState.add_structure("bed", Vector3(-6.0, 0.0, 5.0), 270.0)
	GameState.structures[bed]["data"] = {"respawn": true}
	var plot := GameState.add_structure("crop_plot", Vector3(-4.0, 0.0, 2.0), 0.0)
	GameState.crops[plot] = {"crop": "sweetroot", "planted_at": 1500.0, "tended_minutes": 30.0}
	GameState.add_counter("crops_planted")
	GameState.quests.evaluate()                      # -> lumi
	var a := GameState.add_structure("storage_chest", Vector3(2.0, 0.0, 3.0), 90.0)
	var inv_a: RefCounted = GameState.get_storage(a)
	inv_a.add("wood", 40)
	inv_a.add("stone", 25)
	inv_a.set_slot(5, {"id": "glowcap", "count": 3})
	inv_a.set_slot(19, {"id": "berries", "count": 12})
	GameState.structures[a]["data"] = {"label": "Pantry"}
	var b := GameState.add_structure("storage_chest", Vector3(4.0, 0.0, 3.0), 0.0)
	GameState.get_storage(b).set_slot(0, {"id": "copper_ore", "count": 6})
	for p in [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(2, 0, 2)]:
		GameState.add_structure("wood_floor", p, 0.0)
	GameState.add_structure("wood_wall", Vector3(1.0, 0.0, -1.0), 0.0)
	GameState.add_structure("wood_wall", Vector3(-1.0, 0.0, 1.0), 90.0)
	GameState.add_structure("wood_doorway", Vector3(3.0, 0.0, 1.0), 90.0)
	GameState.add_structure("wood_roof", Vector3(1.0, 2.5, 1.0), 180.0)
	GameState.add_structure("fence", Vector3(6.0, 0.0, -4.0), 0.0)
	GameState.add_structure("lantern_post", Vector3(-2.0, 0.0, 6.0), 0.0)
	GameState.add_structure("rug", Vector3(1.0, 0.0, 1.0), 0.0)
	GameState.add_counter("structures_built", 14)
	GameState.add_bond("mochi", 30)                  # bond 2
	GameState.add_bond("pebble", 12)                 # bond 1
	GameState.set_companion_assignment("mochi", "wait", "surface", Vector3(5.0, 0.25, -3.0))
	GameState.companion("mochi")["last_pet_day"] = 3
	GameState.companion("mochi")["last_fed_day"] = 2
	GameState.companion("pebble")["last_gift_day"] = 3
	GameState.deplete("pebble_boulder", -1.0)
	GameState.total_minutes = 2.0 * 1440.0 + 17.0 * 60.0 + 12.25
	GameState.stats["play_seconds"] = 4210.5
	GameState.stats["deaths"] = 1
	GameState.stats["enemies_defeated"] = 3
	GameState.stats["items_crafted"] = 41
	GameState.player["pos"] = [-3.0, 0.0625, 4.5]
	GameState.player["yaw"] = 2.125
	GameState.player["spawn"] = "bed"
	GameState.player["respawn_spawn"] = "bed"


## In the Below with the key, at the "silk" step (index 13).
static func _below() -> void:
	_home()
	GameState.set_flag("ruin_cleared")
	GameState.set_flag("spawner_cleared_ruin_bramblings")
	GameState.befriend("lumi")                       # lumi follows now
	GameState.quests.evaluate()                      # lumi done -> prepare
	GameState.set_flag("read_ward_warning")
	GameState.give_item("lantern", 1)
	GameState.give_item("berry_snack", 3)
	GameState.give_item("hearty_stew", 2)
	for f in ["mine_opened", "mine_comfort_seen", "entered_below", "moment_threshold", "cp_lit_landing",
			"cp_lit_office", "foreman_key_taken", "lower_gate_open", "gallery_cleared", "cp_lit_shrine",
			"reached_silk_hollows", "moment_crossing", "cp_lit_arena", "moment_silk_intro"]:
		GameState.set_flag(f)
	GameState.give_item("foreman_key", 1)
	GameState.quests.evaluate()                      # prepare, descend, old_mine, deeper -> silk
	for l in ["landing_notice", "foreman_order", "ward_keeper"]:
		GameState.discover_lore(l)
	GameState.add_dropped("glowcap", 2, "below", Vector3(-7.0, -20.0, 5.0))
	GameState.deplete("below_glowcap_4", 720.0)
	GameState.player["area"] = "below"
	GameState.player["spawn"] = "cp_arena"
	GameState.player["respawn_area"] = "below"
	GameState.player["respawn_spawn"] = "cp_arena"
	GameState.player["below_respawn"] = "cp_arena"
	GameState.player["pos"] = [12.0, -31.5, -40.25]
	GameState.player["lantern_on"] = true
	GameState.player["hp"] = 64.0
	GameState.player["stamina"] = 40.0
	GameState.stats["enemies_defeated"] = 14
	GameState.stats["deaths"] = 3
	GameState.total_minutes = 4.0 * 1440.0 + 22.0 * 60.0 + 3.5
	GameState.stats["play_seconds"] = 9120.0
	_set_bag([["stone_axe", 1], ["stone_pickaxe", 1], ["copper_sword", 1], ["lantern", 1], ["berry_snack", 4],
		["hearty_stew", 2], ["glowcap_skewer", 3], null, ["wood", 30], ["stone", 12], ["fiber", 9], ["glowcap", 5],
		["silk", 4], ["echo_shard", 2], ["copper_ore", 3]])
	GameState.select_hotbar(2)


static func _s01() -> Dictionary:
	_fresh()
	return v1_file()


static func _s02() -> Dictionary:
	_early()
	return v1_file()


static func _s03() -> Dictionary:
	_home()
	_set_bag([["stone_axe", 1], ["stone_pickaxe", 1], ["berries", 30], ["sweetroot", 8], ["berry_snack", 5],
		["hearty_stew", 2], ["crop_plot", 3], ["workbench", 1], ["wood", 99], ["wood", 99], ["stone", 99],
		["stone", 40], ["fiber", 60], ["copper_ore", 12], ["shiny_pebble", 4], ["glowcap", 6],
		["sweetroot_seeds", 5], ["storage_chest", 2], ["wood_floor", 20], ["wood_wall", 18], ["wood_window", 4],
		["wood_doorway", 2], ["wood_roof", 10], ["fence", 8], ["lantern_post", 3], ["flower_pot", 2], ["rug", 1],
		["table", 1], ["stool", 2], ["pebble_cairn", 1], ["echo_chime", 1], ["copper_sword", 1]])
	GameState.select_hotbar(2)
	return v1_file()


static func _s04() -> Dictionary:
	_below()
	return v1_file()


static func _s05() -> Dictionary:
	_below()
	for f in ["weaver_defeated", "heartseed_spawned_checked", "moment_nursery"]:
		GameState.set_flag(f)
	GameState.give_item("heartseed", 1)
	GameState.quests.evaluate()                      # silk done -> return
	GameState.discover_lore("hollows_page")
	GameState.stats["enemies_defeated"] = 22
	GameState.player["hp"] = 41.5
	return v1_file()


## ward_restored set, Heartseed used, but the ending never finished: 'return' still pending.
static func _interrupted() -> void:
	_below()
	for f in ["weaver_defeated", "heartseed_spawned_checked", "moment_nursery"]:
		GameState.set_flag(f)
	GameState.give_item("heartseed", 1)
	GameState.quests.evaluate()                      # -> return
	GameState.take_item("heartseed", 1)
	GameState.set_flag("ward_restored")
	GameState.set_flag("moment_return")
	GameState.player["area"] = "surface"
	GameState.player["spawn"] = "haven_respawn"
	GameState.player["respawn_area"] = "surface"
	GameState.player["respawn_spawn"] = "bed"
	GameState.player["pos"] = [0.5, 0.25, -3.0]
	GameState.player["lantern_on"] = false


static func _s06() -> Dictionary:
	_interrupted()
	return v1_file()


## Chapter One complete at free_play (banner placed at home).
static func _complete() -> void:
	_interrupted()
	GameState.quests.evaluate()                      # return done: banner + chapter_one_complete -> free_play
	GameState.take_item("haven_banner", 1)
	GameState.add_structure("haven_banner", Vector3(-1.0, 0.0, -9.0), 180.0)
	GameState.add_bond("lumi", 25)                   # bond 2 (max_bond stays 2: free_play not done)
	GameState.total_minutes = 6.0 * 1440.0 + 10.0 * 60.0
	GameState.stats["play_seconds"] = 14400.75


static func _s07() -> Dictionary:
	_complete()
	return v1_file()


static func _s08() -> Dictionary:
	_complete()
	GameState.add_bond("mochi", 100)                 # max bond
	GameState.add_structure("heartbloom_lamp", Vector3(2.0, 0.0, -7.0), 0.0)
	GameState.quests.evaluate()                      # free_play done (index 16)
	return v1_file()


static func _s09() -> Dictionary:
	_complete()
	# a raised storey: floors, walls and a roof on top of the ground floor
	for x in range(-4, 5, 2):
		for z in range(-4, 5, 2):
			GameState.add_structure("wood_floor", Vector3(float(x), 0.0, float(z)), 0.0)
			GameState.add_structure("wood_floor", Vector3(float(x), 3.0, float(z)), 90.0)
	for x in range(-4, 5, 2):
		GameState.add_structure("wood_wall", Vector3(float(x), 0.0, -5.0), 0.0)
		GameState.add_structure("wood_window", Vector3(float(x), 3.0, -5.0), 0.0)
		GameState.add_structure("wood_roof", Vector3(float(x), 6.0, 0.0), 180.0)
	var full := GameState.add_structure("storage_chest", Vector3(-8.0, 0.0, 6.0), 90.0)
	var half := GameState.add_structure("storage_chest", Vector3(-8.0, 0.0, 8.0), 90.0)
	var upper := GameState.add_structure("storage_chest", Vector3(-2.0, 3.0, 2.0), 270.0)
	GameState.add_structure("storage_chest", Vector3(-8.0, 0.0, 10.0), 90.0)   # empty
	var fill := ["wood", "stone", "fiber", "copper_ore", "berries", "sweetroot", "glowcap", "shiny_pebble", "silk", "echo_shard"]
	for i in 20:
		GameState.get_storage(full).set_slot(i, {"id": fill[i % fill.size()], "count": 7 + i})
	for i in range(0, 20, 2):
		GameState.get_storage(half).set_slot(i, {"id": fill[(i + 3) % fill.size()], "count": 1 + i})
	GameState.get_storage(upper).set_slot(13, {"id": "hearty_stew", "count": 4})
	GameState.structures[upper]["data"] = {"label": "Upstairs"}
	var plots := [[10.0, 0.0, 3.0], [12.0, 0.0, 3.0], [10.0, 0.0, 5.0], [12.0, 0.0, 5.0]]
	var plant := [["sweetroot", 7000.0, 12.5], ["", 0.0, 0.0], ["sweetroot", 9400.0, 0.0], ["sweetroot", 8600.25, 60.0]]
	for i in plots.size():
		var uid := GameState.add_structure("crop_plot", Vector3(plots[i][0], plots[i][1], plots[i][2]), 0.0)
		GameState.crops[uid] = {"crop": plant[i][0], "planted_at": plant[i][1], "tended_minutes": plant[i][2]}
	for s in ["table", "stool", "stool", "flower_pot", "pebble_cairn", "echo_chime"]:
		GameState.add_structure(s, Vector3(-1.0 + float(GameState.structures.size() % 7), 3.0, 1.0), 0.0)
	GameState.add_counter("structures_built", 60)
	GameState.add_counter("crops_planted", 3)
	GameState.add_counter("crops_harvested", 5)
	for i in 8:
		GameState.deplete("tree_%d" % (20 + i), 300.0 + float(i) * 10.0)
	GameState.add_dropped("haven_banner", 1, "surface", Vector3(0.5, 0.25, -2.5))   # banner overflow
	GameState.add_dropped("wood", 37, "surface", Vector3(1.0, 0.0, 1.0))
	GameState.add_dropped("stone", 12, "surface", Vector3(-1.5, 3.1, 0.5))
	var bag: Array = []
	for i in V1_BACKPACK:
		bag.append([fill[i % fill.size()], 50 - i])
	bag[0] = ["stone_axe", 1]
	bag[1] = ["stone_pickaxe", 1]
	bag[2] = ["copper_sword", 1]
	bag[3] = ["lantern", 1]
	_set_bag(bag)
	GameState.select_hotbar(3)
	return v1_file()


static func _s10() -> Dictionary:
	_home()
	GameState.player_name = "Krys"
	GameState.total_minutes = 3.0 * 1440.0 + 7.0 * 60.0 + 30.0
	GameState.set_flag("custom_dir_note", "kept in D:/Games/HollowhavenSaves")
	return v1_file()


## Chapter One complete with Chapter Two under way (current schema).
static func _s11() -> Dictionary:
	_complete()
	for f in ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map",
			"ch2_found_orchard_lamp", "ch2_found_quarry_lamp"]:
		GameState.set_flag(f)
	GameState.chapter2.done = ["ch2_light_beyond", "ch2_waygate", "ch2_commons"]
	GameState.chapter2.baselines = {"ch2_light_beyond": {}, "ch2_waygate": {}, "ch2_commons": {}, "ch2_outer_lamps": {}}
	GameState.ledger = {"rw_ch2_light_beyond": 9000.0, "rw_ch2_waygate": 9100.0, "rw_ch2_commons": 9250.5,
		"rw_opt_look_of_your_own": 8700.0}
	GameState.optional_goals.records = {"opt_look_of_your_own": {"done": true, "done_at": 8700.0}}
	GameState.set_flag("c1x_look_chosen")
	install_fake_items()
	GameState.set_backpack_capacity(40)
	GameState.inventory.set_slot(36, {"id": "fixture_charm", "count": 1})
	GameState.inventory.set_slot(39, {"id": "wood", "count": 20})
	GameState.equipment["head"] = "fixture_hood"
	GameState.appearance["hair"] = "twin_braids"
	GameState.appearance["hair_color"] = "lavender"
	GameState.appearance["outfit"] = "strawberry_picnic"
	GameState.wardrobe["owned"] = ["ribbon_bow"]
	GameState.wardrobe["presets"] = [{"name": "Picnic", "look": {"hair": "twin_braids"}}]
	GameState.wardrobe["notice_shown"] = true
	GameState.mastery["gathering"] = 40
	GameState.mastery["seen"]["gathering"] = ["oak_tree", "copper_vein"]
	GameState.mastery["legacy_credit"] = true
	GameState.discover("hallowmere_reach", "commons")
	GameState.discover("hallowmere_reach", "orchard")
	GameState.discover("surface", "haven")
	GameState.trials["matron"] = {"clears": 1, "best_seconds": 212.5}
	var m := GameState.companion("mochi")
	m["combat_mode"] = "close"
	m["skill_ready_at"] = 13900.0
	m["home_spot"] = [-5.0, 0.0, 4.0]
	m["ribbon"] = "comfort_ribbon"
	GameState.player["area"] = "hallowmere_reach"
	GameState.player["spawn"] = "commons_arch"
	GameState.player["pos"] = [0.0, 1.5, 70.0]
	GameState.total_minutes = 7.0 * 1440.0 + 9.0 * 60.0
	var d := v2_file()
	remove_fake_items()
	return d


static func _future_file() -> Dictionary:
	return {"format": "hollowhaven-save", "version": 3, "game_version": "1.4.0", "saved_unix": SAVED_UNIX + 86400.0,
		"meta": {"day": 41, "chapter": 3, "step": "ch3_tide", "step_title": "A Newer Journey", "play_seconds": 99999.0, "area": "tidewater"},
		"state": {"player_name": "Krystal", "schema": 3, "inventory": [{"id": "wood", "count": 3}],
			"chapter3": {"done": ["ch3_start"]}, "flags": {"chapter_one_complete": true, "chapter_two_complete": true}}}


static func _s14() -> Dictionary:
	_below()                                         # tracker at silk
	GameState.quests.from_dict({"index": 11, "completed": GameState.quests.completed.slice(0, 11), "baselines": {}})
	GameState.give_item("heartseed", 1)
	GameState.take_item("heartseed", 1)
	GameState.set_flag("weaver_defeated")
	GameState.set_flag("ward_restored")
	GameState.player["area"] = "surface"
	GameState.player["spawn"] = "haven_respawn"
	GameState.player["respawn_area"] = "surface"
	GameState.player["pos"] = [1.0, 0.25, -4.0]
	return v1_file()


static func _s15() -> Dictionary:
	_complete()
	GameState.set_flag("ch2_accepted")
	GameState.chapter2.done = ["ch2_light_beyond"]
	GameState.chapter2.baselines = {"ch2_light_beyond": {}, "ch2_waygate": {}}
	GameState.ledger = {"rw_ch2_light_beyond": 9000.0}
	var chest := ""
	for uid in GameState.structures:
		if GameState.structures[uid]["id"] == "storage_chest":
			chest = uid
			break
	var d := v2_file()
	var st: Dictionary = d["state"]
	st["inventory"][12] = {"id": "moon_harp", "count": 1}
	st["storages"][chest][3] = {"id": "star_jelly", "count": 7}
	st["equipment"]["body"] = "comet_mail"
	st["equipment"]["back"] = "cape_of_tomorrow"                     # a slot a newer build added
	st["key_items"]["sky_key"] = 1
	st["dropped"].append({"uid": "d900", "item": "meteor_chunk", "count": 2, "area": "hallowmere_reach", "pos": [4.0, 1.0, 8.0]})
	st["orphans"] = [{"where": "inventory", "slot": 30, "stack": {"id": "older_orphan", "count": 2}, "note": "kept"}]
	st["structures"]["s800"] = {"id": "sky_loom", "area": "surface", "pos": [9.0, 0.0, 9.0], "rot": 90.0, "data": {"tint": "rose"}}
	st["storages"]["s800"] = [{"id": "wood", "count": 3}, null, {"id": "moon_thread", "count": 2}]
	st["companions"]["mochi"]["mood"] = "sleepy"
	st["companions"]["pipkin"] = {"befriended": false, "bond_xp": 0, "assignment": "wild", "wait_area": "", "wait_pos": null,
		"last_pet_day": -1, "last_gift_day": -1, "last_fed_day": -1}
	st["chapter3"] = {"done": [], "note": "from a newer patch"}
	st["optional"]["opt_from_the_future"] = {"done": true, "done_at": 42.0}
	st["chapter2"]["done"].append("ch2_step_from_the_future")
	st["appearance"]["tail"] = "fox"
	st["mastery"]["fishing"] = 3
	st["trials"]["velour"] = {"clears": 3, "best_seconds": 101.25, "medal": "gold"}
	st["stations"]["s5"] = {"queue": []}
	return d
