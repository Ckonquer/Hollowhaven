#!/usr/bin/env python3
"""Hollowhaven save integrity check: version-1 (Chapter One) save vs its migrated version-2 save.

Compares every field the Chapter Two migration must preserve (MP section 2.1 / 20.1, docs/SAVE_MIGRATION.md)
and prints a machine-readable JSON difference report. Standard library only.

    python save_integrity.py <v1 slot1.json> <v2 slot1.json> [--out report.json]
    python save_integrity.py --self-test

Exit code: 0 = everything preserved, 1 = preserved-field mismatches (a FAILURE), 2 = unusable input.

Allowed (documented) changes, reported under "allowed_changes" instead of mismatches:
  * the new schema-v2 state sections (appearance, wardrobe, equipment, capacity, optional, chapter2, ledger,
    mastery, discovered, trials, orphans, stations, schema);
  * new companion keys (combat_mode, skill_ready_at, home_spot, ribbon, home_task) and records for creatures
    added later;
  * backpack / chest arrays grown with EMPTY slots (capacity upgrades);
  * stacks whose item id the new build does not know moved to `orphans` with the same slot (never dropped);
  * a baseline added for the current legacy quest step; next_uid never lower.
Run it on COPIES (see docs/SAVE_MIGRATION.md), before any gameplay advances the clock.
"""
import hashlib
import json
import sys

V2_SECTIONS = ["schema", "appearance", "wardrobe", "equipment", "capacity", "optional", "chapter2", "ledger",
               "mastery", "discovered", "trials", "orphans", "stations"]
V2_COMPANION_KEYS = ["combat_mode", "skill_ready_at", "home_spot", "ribbon", "home_task"]
EXACT_KEYS = ["player_name", "hotbar_index", "flags", "counters", "active_companion", "structures", "crops",
              "depleted", "lore", "total_minutes", "buffs"]


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def same(a, b):
    """Deep equality with JSON semantics: 3 == 3.0, but True != 1."""
    if _num(a) and _num(b):
        return float(a) == float(b)
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


class Report:
    def __init__(self):
        self.mismatches = []
        self.allowed = []

    def bad(self, path, v1, v2, why=""):
        self.mismatches.append({"path": path, "v1": v1, "v2": v2, "why": why})

    def ok_change(self, path, what):
        self.allowed.append({"path": path, "change": what})


def _dict(v):
    return v if isinstance(v, dict) else {}


def _list(v):
    return v if isinstance(v, list) else []


def _orphaned(orphans, where, slot, item_id, count):
    for o in orphans:
        if not isinstance(o, dict) or not isinstance(o.get("stack"), dict):
            continue
        if o.get("where") != where:
            continue
        if slot >= 0 and not same(o.get("slot", -1), slot):
            continue
        if o["stack"].get("id") == item_id and same(o["stack"].get("count"), count):
            return True
    return False


def _cmp_slots(rep, a, b, path, where, orphans):
    if len(b) < len(a):
        rep.bad(path, len(a), len(b), "slots removed")
    for i, x in enumerate(a):
        y = b[i] if i < len(b) else None
        if same(x, y):
            continue
        if isinstance(x, dict) and y is None and _orphaned(orphans, where, i, x.get("id"), x.get("count")):
            rep.ok_change("%s[%d]" % (path, i), "unknown item id kept as an orphan (%s)" % x.get("id"))
            continue
        rep.bad("%s[%d]" % (path, i), x, y)
    for i in range(len(a), len(b)):
        if b[i] is not None:
            rep.bad("%s[%d]" % (path, i), None, b[i], "a new slot must be empty")
    if len(b) > len(a):
        rep.ok_change(path, "grew from %d to %d empty-ended slots" % (len(a), len(b)))


def compare_states(v1, v2):
    """Returns a Report comparing a version-1 state dict with a version-2 state dict."""
    rep = Report()
    orphans = _list(v2.get("orphans"))
    for k in EXACT_KEYS:
        if k in v1 and not same(v1[k], v2.get(k)):
            if isinstance(v1[k], dict) and isinstance(v2.get(k), dict):
                for sub in sorted(set(v1[k]) | set(v2[k])):
                    if not same(v1[k].get(sub), v2[k].get(sub)):
                        rep.bad("%s/%s" % (k, sub), v1[k].get(sub), v2[k].get(sub))
            else:
                rep.bad(k, v1[k], v2.get(k))
    _cmp_slots(rep, _list(v1.get("inventory")), _list(v2.get("inventory")), "inventory", "inventory", orphans)
    st1, st2 = _dict(v1.get("storages")), _dict(v2.get("storages"))
    for uid in st1:
        if uid not in st2:
            rep.bad("storages/" + uid, "present", None, "chest binding lost")
        else:
            _cmp_slots(rep, _list(st1[uid]), _list(st2[uid]), "storages/" + uid, "storage:" + uid, orphans)
    k1, k2 = _dict(v1.get("key_items")), _dict(v2.get("key_items"))
    for item_id, n in k1.items():
        if not same(k2.get(item_id), n):
            if _orphaned(orphans, "key_items", -1, item_id, n):
                rep.ok_change("key_items/" + item_id, "unknown key item kept as an orphan")
            else:
                rep.bad("key_items/" + item_id, n, k2.get(item_id))
    for item_id in k2:
        if item_id not in k1:
            rep.bad("key_items/" + item_id, None, k2[item_id], "unexpected new key item")
    for section in ["player", "stats"]:
        s1, s2 = _dict(v1.get(section)), _dict(v2.get(section))
        for k, v in s1.items():
            if not same(v, s2.get(k)):
                rep.bad("%s/%s" % (section, k), v, s2.get(k))
    q1, q2 = _dict(v1.get("quests")), _dict(v2.get("quests"))
    if "quests" in v1:
        for k in ["index", "completed"]:
            if not same(q1.get(k), q2.get(k)):
                rep.bad("quests/" + k, q1.get(k), q2.get(k))
        b1, b2 = _dict(q1.get("baselines")), _dict(q2.get("baselines"))
        for sid, b in b1.items():
            if not same(b, b2.get(sid)):
                rep.bad("quests/baselines/" + sid, b, b2.get(sid))
        for sid in b2:
            if sid not in b1:
                rep.ok_change("quests/baselines/" + sid, "baseline added for the current step")
    c1, c2 = _dict(v1.get("companions")), _dict(v2.get("companions"))
    for cid, r1 in c1.items():
        r1, r2 = _dict(r1), _dict(c2.get(cid))
        if not r2:
            rep.bad("companions/" + cid, "record", None, "companion lost")
            continue
        for k, v in r1.items():
            if not same(v, r2.get(k)):
                rep.bad("companions/%s/%s" % (cid, k), v, r2.get(k))
        for k in r2:
            if k not in r1:
                if k in V2_COMPANION_KEYS:
                    rep.ok_change("companions/%s/%s" % (cid, k), "new companion key (default %s)" % json.dumps(r2[k]))
                else:
                    rep.bad("companions/%s/%s" % (cid, k), None, r2[k], "undocumented new companion key")
    for cid in c2:
        if cid not in c1:
            rep.ok_change("companions/" + cid, "record for a creature added later")
    kept = [d for d in _list(v1.get("dropped"))
            if not (isinstance(d, dict) and _orphaned(orphans, "dropped", -1, d.get("item"), d.get("count")))]
    if len(kept) != len(_list(v1.get("dropped"))):
        rep.ok_change("dropped", "unknown dropped items kept as orphans")
    if not same(kept, _list(v2.get("dropped"))):
        rep.bad("dropped", kept, v2.get("dropped"))
    n1, n2 = v1.get("next_uid"), v2.get("next_uid")
    if _num(n1) and (not _num(n2) or float(n2) < float(n1)):
        rep.bad("next_uid", n1, n2, "uids could collide")
    for k in V2_SECTIONS:
        if k in v2 and k not in v1:
            rep.ok_change(k, "new schema-v2 section")
    return rep


def _summary(st):
    inv = _list(st.get("inventory"))
    storages = _dict(st.get("storages"))
    return {
        "structures": len(_dict(st.get("structures"))),
        "chests": len(storages),
        "chest_stacks": sum(1 for arr in storages.values() for s in _list(arr) if s),
        "crops": len(_dict(st.get("crops"))),
        "backpack_slots": len(inv),
        "backpack_stacks": sum(1 for s in inv if s),
        "key_items": _dict(st.get("key_items")),
        "companions_befriended": sorted(k for k, r in _dict(st.get("companions")).items() if _dict(r).get("befriended")),
        "flags": len(_dict(st.get("flags"))),
        "quest_index": _dict(st.get("quests")).get("index"),
        "lore": len(_list(st.get("lore"))),
        "dropped": len(_list(st.get("dropped"))),
        "total_minutes": st.get("total_minutes"),
        "orphans": len(_list(st.get("orphans"))),
    }


def _load(path):
    with open(path, "rb") as f:
        raw = f.read()
    data = json.loads(raw.decode("utf-8-sig"))   # tolerate a BOM added by an editor
    if not isinstance(data, dict) or data.get("format") != "hollowhaven-save" or not isinstance(data.get("state"), dict):
        raise ValueError("not a hollowhaven save with a state")
    return data, hashlib.sha256(raw).hexdigest()


def build_report(v1_path, v2_path):
    v1, h1 = _load(v1_path)
    v2, h2 = _load(v2_path)
    rep = compare_states(v1["state"], v2["state"])
    missing = [k for k in V2_SECTIONS if k not in v2["state"]]
    notes = []
    if not _num(v1.get("version")) or int(v1["version"]) != 1:
        notes.append("the first file is not version 1 (version %s)" % v1.get("version"))
    if not _num(v2.get("version")) or int(v2["version"]) < 2:
        notes.append("the second file is not version 2+ (version %s)" % v2.get("version"))
    ok = not rep.mismatches and not missing
    return {
        "tool": "save_integrity", "report_version": 1, "ok": ok,
        "v1": {"path": v1_path, "sha256": h1, "version": v1.get("version"), "game_version": v1.get("game_version"),
               "summary": _summary(v1["state"])},
        "v2": {"path": v2_path, "sha256": h2, "version": v2.get("version"), "game_version": v2.get("game_version"),
               "summary": _summary(v2["state"])},
        "preserved_mismatches": rep.mismatches,
        "missing_v2_sections": missing,
        "allowed_changes": rep.allowed,
        "notes": notes,
    }


def self_test():
    """Checks the checker: a faithful migration passes, every kind of loss is caught."""
    v1 = {"player_name": "Krystal", "hotbar_index": 2, "flags": {"ward_restored": True}, "counters": {"max_bond": 3},
          "active_companion": "mochi", "structures": {"s1": {"id": "storage_chest", "area": "surface", "pos": [1.0, 0.0, 2.0], "rot": 90.0, "data": {}}},
          "crops": {}, "depleted": {"tree_1": -1.0}, "lore": ["ward_keeper"], "total_minutes": 900.5, "buffs": {},
          "inventory": [{"id": "wood", "count": 5}, None, {"id": "old_thing", "count": 1}],
          "storages": {"s1": [None, {"id": "stone", "count": 3}]}, "key_items": {"foreman_key": 1},
          "player": {"hp": 90.0, "area": "surface"}, "stats": {"deaths": 1},
          "quests": {"index": 15, "completed": ["wake"], "baselines": {}},
          "companions": {"mochi": {"befriended": True, "bond_xp": 30}}, "dropped": [], "next_uid": 5}
    v2 = json.loads(json.dumps(v1))
    v2["inventory"] = [{"id": "wood", "count": 5}, None, None, None]
    v2["orphans"] = [{"where": "inventory", "slot": 2, "stack": {"id": "old_thing", "count": 1}}]
    v2["companions"]["mochi"]["combat_mode"] = "assist"
    v2["companions"]["pebble"] = {"befriended": False}
    v2["quests"]["baselines"] = {"free_play": {"max_bond": 3}}
    v2["hotbar_index"] = 2.0
    for k in V2_SECTIONS:
        v2.setdefault(k, {})
    results = []
    good = compare_states(v1, v2)
    results.append(("faithful migration passes", not good.mismatches))
    mutations = {
        "moved structure": lambda s: s["structures"]["s1"]["pos"].__setitem__(0, 9.0),
        "reordered backpack": lambda s: s.__setitem__("inventory", [None, {"id": "wood", "count": 5}, None, None]),
        "lost chest item": lambda s: s["storages"]["s1"].__setitem__(1, None),
        "lost key item": lambda s: s.__setitem__("key_items", {}),
        "bool became number": lambda s: s["flags"].__setitem__("ward_restored", 1),
        "quest index": lambda s: s["quests"].__setitem__("index", 14),
        "bond reset": lambda s: s["companions"]["mochi"].__setitem__("bond_xp", 0),
        "clock moved": lambda s: s.__setitem__("total_minutes", 901.0),
        "orphan dropped instead": lambda s: s.__setitem__("orphans", []),
        "extra companion key": lambda s: s["companions"]["mochi"].__setitem__("secret", 1),
        "next uid lowered": lambda s: s.__setitem__("next_uid", 2),
    }
    for name, mutate in mutations.items():
        bad = json.loads(json.dumps(v2))
        mutate(bad)
        results.append(("catches: " + name, bool(compare_states(v1, bad).mismatches)))
    failed = [n for n, ok in results if not ok]
    print(json.dumps({"tool": "save_integrity", "self_test": True, "ok": not failed,
                      "checks": [{"name": n, "ok": ok} for n, ok in results]}, indent=2))
    return 0 if not failed else 1


def main(argv):
    if len(argv) >= 2 and argv[1] == "--self-test":
        return self_test()
    args = [a for a in argv[1:] if not a.startswith("--out")]
    out = None
    for i, a in enumerate(argv):
        if a == "--out" and i + 1 < len(argv):
            out = argv[i + 1]
            args = [x for x in args if x != out]
        elif a.startswith("--out="):
            out = a.split("=", 1)[1]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        report = build_report(args[0], args[1])
    except (OSError, ValueError) as e:
        print(json.dumps({"tool": "save_integrity", "ok": False, "error": str(e)}, indent=2))
        return 2
    text = json.dumps(report, indent=2, sort_keys=False)
    print(text)
    if out:
        with open(out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
