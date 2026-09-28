"""Segment S2 start-state fixture generator ("diagnostic fixture start", not a natural route).

Builds the START state of segment S2 (Hallowmere west + east) from the REAL Chapter-One-complete save that the
earlier QA bot made (game/tests/fixtures/saves/16_real_handoff_c1_complete.json, a version-1 save, so loading it
also exercises the v1 -> v2 migration). Only what segments S0/S1 would have changed by natural play is edited:

  * flags ch2_accepted (Ward Stone accepted), ch2_waygate_repaired (waygate repaired),
    ch2_arch_commons (Commons arch lit), ch2_read_festival_map (festival board read) - set to true;
  * the waygate repair cost (game/src/world/surface/waygate.gd REPAIR_COST: 8 wood, 4 stone, 2 copper ore) is
    taken from the backpack, as the real repair would have;
  * Krystal stands in hallowmere_reach at the commons_arch spawn (her saved position is the spawn point: the
    game validates it and falls back to the spawn if the ground is not found) with the Reach return point
    commons_arch, like arriving through the waygate and lighting the Commons arch.

Nothing else is granted. The Chapter Two quest layer is NOT pre-filled: the migration adds an empty
"chapter2" section and ChapterLog.evaluate() completes the latched steps 1-3 on load (and pays rw_ch2_commons,
the stallkeeper's seed pouch) exactly as it does in a natural chain. The one-time wardrobe notice of a v1 save
stays pending (the bot dismisses it like a player would).

Usage:  python tools/qa/ch2/s2_fixture.py --out <run dir>/saves   (writes slot1.json there; never touches
        any other folder)
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "game" / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.json"
WAYGATE_COST = [("wood", 8), ("stone", 4), ("copper_ore", 2)]
S1_FLAGS = ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map"]
# data/hallowmere_layout.gd SPAWNS["commons_arch"] (the ground height is found by the game's validation)
COMMONS_ARCH_POS = [0.0, 3.0, 75.0]


def take(inv: list, item: str, n: int) -> int:
    """Removes n of item from the inventory array (slot order kept, emptied slots become None)."""
    left = n
    for i, st in enumerate(inv):
        if left <= 0:
            break
        if isinstance(st, dict) and st.get("id") == item:
            k = min(int(st.get("count", 0)), left)
            st["count"] = int(st["count"]) - k
            left -= k
            if st["count"] <= 0:
                inv[i] = None
    return n - left


def build(source: Path = SOURCE) -> dict:
    data = json.loads(source.read_text(encoding="utf-8"))
    out = copy.deepcopy(data)
    st = out["state"]
    flags = st.setdefault("flags", {})
    for f in S1_FLAGS:
        flags[f] = True
    inv = st.get("inventory", [])
    taken = {item: take(inv, item, n) for item, n in WAYGATE_COST}
    pl = st.setdefault("player", {})
    pl["area"] = "hallowmere_reach"
    pl["spawn"] = "commons_arch"
    pl["pos"] = list(COMMONS_ARCH_POS)
    pl["yaw"] = 0.0
    pl["respawn_area"] = "hallowmere_reach"
    pl["respawn_spawn"] = "commons_arch"
    pl["area_respawn"] = {"hallowmere_reach": "commons_arch"}
    meta = out.setdefault("meta", {})
    meta["qa_fixture"] = ("S2 diagnostic fixture start: real handoff save + S1 flags %s, waygate cost taken %s, "
                          "at hallowmere_reach/commons_arch (tools/qa/ch2/s2_fixture.py)") % (S1_FLAGS, taken)
    return out


def write(save_dir: str | Path, source: Path = SOURCE) -> Path:
    d = Path(save_dir)
    d.mkdir(parents=True, exist_ok=True)
    p = d / "slot1.json"
    p.write_text(json.dumps(build(source), indent=1), encoding="utf-8")
    return p


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="save folder to write slot1.json into")
    ap.add_argument("--source", default=str(SOURCE))
    a = ap.parse_args()
    print(write(a.out, Path(a.source)))
