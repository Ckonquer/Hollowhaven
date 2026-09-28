"""Segment S3 (Moonveil Manor) start-state generator - a DIAGNOSTIC FIXTURE START, not natural play.

Builds <out>/saves/slot1.json from the REAL Chapter-One-complete save the earlier bot wrote
(game/tests/fixtures/saves/16_real_handoff_c1_complete.json, a version-1 save), changing only what the
segment needs to start "in the Reach with the three lamps' locations known":

* flags added (the Chapter-Two story state an earlier segment would have produced by play):
  ch2_accepted, ch2_waygate_repaired, ch2_arch_commons, ch2_read_festival_map,
  ch2_found_orchard_lamp, ch2_found_quarry_lamp, ch2_found_manor_lamp
* player moved to the Reach: area hallowmere_reach, spawn manor_arch (the saved position is deliberately
  unplaceable so Continue falls back to the manor_arch spawn), respawn = commons_arch (the Reach default)
* hp topped up to 100 (the real save stopped at 66 hp right after the Chapter One ending)

Everything else (inventory: copper sword, lantern, 7 berries, tools...; companions: Lumi following; structures,
lore, quest index, stats) is the real save byte-for-byte in content. The file stays version 1, so loading it
also exercises the v1 -> v2 migration; the Chapter-Two quest layer then completes steps 1-4 from world state
(MP 11: "completing an action before reading its objective still counts").

Usage: python tools/qa/ch2/s3_fixture.py --out qa/tmp/bot/s3/runN
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "game" / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.json"

CH2_FLAGS = ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map",
             "ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp"]


def build(out_dir: str | Path, source: str | Path = SOURCE, hp: float = 100.0,
          extra_flags: list[str] | None = None, extra_items: dict[str, int] | None = None) -> Path:
    """Writes <out_dir>/saves/slot1.json and returns its path. extra_* are for other diagnostics only."""
    d = json.loads(Path(source).read_text(encoding="utf-8"))
    st = d["state"]
    flags = st.setdefault("flags", {})
    for f in CH2_FLAGS + list(extra_flags or []):
        flags[f] = True
    pl = st["player"]
    pl["area"] = "hallowmere_reach"
    pl["spawn"] = "manor_arch"
    pl["pos"] = [10.9, 400.0, -52.8]       # no ground within the validation ray: Continue uses the spawn
    pl["yaw"] = 0.0
    pl["respawn_area"] = "hallowmere_reach"
    pl["respawn_spawn"] = "commons_arch"
    pl["hp"] = float(hp)
    for item, n in (extra_items or {}).items():
        inv = st["inventory"]
        slot = next((i for i, s in enumerate(inv) if s is None), None)
        if slot is not None:
            inv[slot] = {"count": int(n), "id": item}
    d["meta"] = dict(d.get("meta", {}), area="hallowmere_reach")
    d["fixture_note"] = "S3 diagnostic fixture start built by tools/qa/ch2/s3_fixture.py from 16_real_handoff_c1_complete"
    saves = Path(out_dir) / "saves"
    saves.mkdir(parents=True, exist_ok=True)
    p = saves / "slot1.json"
    p.write_text(json.dumps(d, indent=1), encoding="utf-8")
    return p


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    print(build(a.out))
