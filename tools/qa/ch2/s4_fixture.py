"""Segment S4 start-state generator - a DIAGNOSTIC FIXTURE START, not natural play.

S4 starts where S1-S3 end: all three regional lamps lit (garden / quarry / manor), NOT yet linked. This builds
<out>/saves/slot1.json from the REAL Chapter-One-complete save the earlier bot wrote
(game/tests/fixtures/saves/16_real_handoff_c1_complete.json, a version-1 save; loading it also exercises the
v1 -> v2 migration), changing only:

* flags added = the Chapter-Two world state earlier segments produce by play (every one is a flag a content
  module sets in normal play; nothing else is touched, the quest layer completes steps 1-8 from them on load and
  pays their ledger rewards - the three seals, seed pouches - itself):
    ch2_accepted, ch2_waygate_repaired, ch2_arch_commons, ch2_read_festival_map,
    ch2_found_orchard_lamp, ch2_found_quarry_lamp, ch2_found_manor_lamp,
    ch2_orchard_irrigated, ch2_orchard_mimics_cleared, ch2_garden_lamp_lit, ch2_arch_orchard,
    hr_warden_defeated, ch2_winch_repaired, ch2_quarry_lamp_lit, ch2_arch_quarry,
    ch2_velour_defeated, ch2_moment_empty_waltz, ch2_manor_lamp_lit, ch2_arch_manor,
    ch2_read_preparations
* player moved to the Reach: area hallowmere_reach, spawn "conservatory" (the saved position is deliberately
  unplaceable, y = 400, so Continue falls back to that spawn), respawn = conservatory
* hp topped up to 100 (the real save stopped at 66 hp right after the Chapter One ending)
* --supplies (default ON, documented diagnostic addition): 4 berry_snack + 2 hearty_stew in free backpack slots
  (what a player who cooked on the way would carry; the real save only has 7 berries). --no-supplies = off.

Everything else (copper sword, stone tools, lantern, key pouch with the Foreman's Key, Lumi following, Mochi at
home, structures, lore, stats) is the real save's content. Usage:
  python tools/qa/ch2/s4_fixture.py --out qa/tmp/bot/s4/fixture [--no-supplies]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "game" / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.json"

CH2_FLAGS = [
    "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map",
    "ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp",
    "ch2_orchard_irrigated", "ch2_orchard_mimics_cleared", "ch2_garden_lamp_lit", "ch2_arch_orchard",
    "hr_warden_defeated", "ch2_winch_repaired", "ch2_quarry_lamp_lit", "ch2_arch_quarry",
    "ch2_velour_defeated", "ch2_moment_empty_waltz", "ch2_manor_lamp_lit", "ch2_arch_manor",
    "ch2_read_preparations",
]
SUPPLIES = {"berry_snack": 4, "hearty_stew": 2}


def build(out_dir, source=SOURCE, hp: float = 100.0, supplies: bool = True, extra_flags=None, extra_items=None) -> Path:
    d = json.loads(Path(source).read_text(encoding="utf-8"))
    st = d["state"]
    flags = st.setdefault("flags", {})
    for f in CH2_FLAGS + list(extra_flags or []):
        flags[f] = True
    pl = st["player"]
    pl["area"] = "hallowmere_reach"
    pl["spawn"] = "conservatory"
    pl["pos"] = [0.0, 400.0, 17.0]          # no ground within the validation ray: Continue uses the spawn
    pl["yaw"] = 0.0
    pl["respawn_area"] = "hallowmere_reach"
    pl["respawn_spawn"] = "conservatory"
    pl["hp"] = float(hp)
    items = dict(SUPPLIES) if supplies else {}
    items.update(extra_items or {})
    inv = st["inventory"]
    for item, n in items.items():
        slot = next((i for i, s in enumerate(inv) if s is None), None)
        if slot is None:
            inv.append({"count": int(n), "id": item})
        else:
            inv[slot] = {"count": int(n), "id": item}
    d["meta"] = dict(d.get("meta", {}), area="hallowmere_reach")
    d["fixture_note"] = ("S4 diagnostic fixture start (all three lamps lit) built by tools/qa/ch2/s4_fixture.py "
                         "from 16_real_handoff_c1_complete")
    saves = Path(out_dir) / "saves"
    saves.mkdir(parents=True, exist_ok=True)
    p = saves / "slot1.json"
    p.write_text(json.dumps(d, indent=1), encoding="utf-8")
    return p


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-supplies", action="store_true")
    a = ap.parse_args()
    print(build(a.out, supplies=not a.no_supplies))
