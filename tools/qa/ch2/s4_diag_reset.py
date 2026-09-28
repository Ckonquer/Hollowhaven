"""S4 diagnostic (NOT part of the natural route): the Borrowed Choir's reset policy after Krystal falls.

Starts from a game-written save at the Bell Throat (a checkpoint the S4 route snapshots, e.g.
qa/tmp/bot/s4/full1/checkpoints/bell_throat), plays Phase A with the route's ChoirBot, then deliberately stands
still inside the ring in Phase B until Krystal falls. Records where she wakes, what the Choir's phase / hp / state
is after the fall (MP 13.3 reset policy: back to the START of the phase she reached, hazards and wisps gone,
resonators reset), and then finishes the fight with the ChoirBot (the "finish after a failure" path).
  python tools/qa/ch2/s4_diag_reset.py --start-save qa/tmp/bot/s4/full1/checkpoints/bell_throat --out qa/tmp/bot/s4/diag_reset
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from s4_common import HeadlessGame, Play, pick_port, place_save, write_json, dist2, xz  # noqa: E402
import s4_route as R  # noqa: E402


def boss_of(s):
    return next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "phase" in e), None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start-save", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--attempt", type=int, default=40)
    a = ap.parse_args()
    out = Path(a.out).resolve()
    sp = Path(a.start_save)
    src = sp / "slot1.json" if sp.is_dir() else sp
    g = HeadlessGame(out, "diag", pick_port(a.attempt), max_seconds=1500, extra=["--no-wardrobe-notice"])
    place_save(g.save_dir, src, src.with_name("slot1.bak.json"))
    rec = {"kind": "diagnostic (deliberate fall in Choir Phase B)", "start": str(src)}
    g.start()
    try:
        p0 = Play(g, out)
        p0.wait(lambda s: s.get("mode") == "title" and s.get("buttons"), 90)
        p0.click_button("Continue", exact=True, timeout=10)
        p = R.S4(g, out)
        R.step_start(p)
        R.step_bell_throat(p)
        p.lantern(True)
        p.nav((157.0, -32.0, 53.7))
        cb = R.ChoirBot(p)
        # Phase A with the normal bot, until Phase B starts
        t0 = time.time()
        while time.time() - t0 < 400:
            s = p.st()
            b = boss_of(s)
            if b and int(b.get("phase", 1)) >= 2:
                break
            if s.get("mode") != "playing":
                time.sleep(0.3)
                continue
            if s.get("ui_stack"):
                p.handle_dialog()
                continue
            cb.read_msgs()
            if b and (b.get("vuln") or str(b.get("state", "")).endswith("_exposed")):
                cb.strike_boss(b)
            elif b:
                cb.phase_a(s, str(b.get("state", "")), p.pos(), __import__("random").Random(1))
            else:
                p.goto((157.0, 57.0), tol=1.0, sprint=True, timeout=10)    # walking in starts the encounter
                time.sleep(0.3)
        s = p.st()
        b = boss_of(s)
        rec["phase_b_reached"] = {"t": round(time.time() - t0, 1), "boss": b and {k: b.get(k) for k in ("state", "hp", "phase")}}
        # stand in the ring (radius ~5, north of the centre) and do nothing until she falls
        p.goto((157.0, 60.0), tol=0.8, sprint=True, timeout=8)
        deaths0 = sum(1 for m in p.all_msgs if m.get("text") == "player died")
        t1 = time.time()
        fell = False
        while time.time() - t1 < 240:
            p.st()
            if sum(1 for m in p.all_msgs if m.get("text") == "player died") > deaths0:
                fell = True
                break
            time.sleep(0.3)
        rec["fell"] = fell
        rec["seconds_to_fall"] = round(time.time() - t1, 1)
        p.wait(lambda s: s.get("mode") == "playing" and float(s.get("player", {}).get("hp", 0)) > 0, 30)
        time.sleep(3.0)
        s = p.st()
        b = boss_of(s)
        rec["after_fall"] = {"pos": s.get("player", {}).get("pos"), "zone": s.get("zone"), "hp": s.get("player", {}).get("hp"),
                             "boss": b and {k: b.get(k) for k in ("state", "hp", "phase", "pos")},
                             "enemies": [(e.get("name"), e.get("state"), e.get("hp")) for e in s.get("nearby", []) if e.get("g") == "enemy"][:8],
                             "flags_choir": "ch2_choir_defeated" in s.get("flags", [])}
        p.log(f"after the fall: {rec['after_fall']}")
        # finish the fight from wherever she woke
        ok = R.step_choir(p)
        s = p.st()
        rec["finished_after_fall"] = ok
        rec["deaths_total"] = sum(1 for m in p.all_msgs if m.get("text") == "player died") - deaths0
        rec["messages"] = p.all_msgs[-200:]
        rec["picks"] = getattr(p, "choir_picks", [])
    finally:
        g.stop()
        write_json(out / "diag_result.json", rec)
    print(json.dumps({k: rec.get(k) for k in ("phase_b_reached", "fell", "seconds_to_fall", "after_fall", "finished_after_fall", "deaths_total")},
                     indent=1, default=str))


if __name__ == "__main__":
    main()
