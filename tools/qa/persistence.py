"""Persistence playthrough of the PACKAGED game with real OS input (or, with --second-monitor /
--virtual-input, through the game's localhost virtual-input server while the owner keeps the PC; hhbot.py).

1. New Game -> play (real inputs) through Pebble (workbench placed, 2 companions, resources).
2. Save from the pause menu, snapshot what the player can observe, quit the process through the menu.
3. Relaunch -> Continue -> verify inventory, companions, structures, objectives, position.
4. Play on into the Old Mine (lantern checkpoints), then HARD-KILL the process (crash-like).
5. Relaunch -> Continue -> verify we resume at the last lit lantern with the key/progress intact.
6. Play on to the ending and a final save.
Results are appended to <out>/results.jsonl like playthrough.py.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from playthrough import Play, StepFailed, build_steps, dist2, xz  # noqa: E402
from session import Session, add_transport_args, transport_kwargs  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def observe(p: Play) -> dict:
    s = p.st()
    structures = sorted({n.get("text", "") for n in s.get("nearby", []) if n.get("text", "").startswith(("Use", "Open", "Sleep", "Plant", "Sweetroot", "Craft"))})
    return {"step": s.get("step"), "area": s.get("area"), "inv": s.get("inv", {}), "keys": s.get("keys", {}),
            "companions": s.get("companions", {}), "pos": (s.get("player") or {}).get("pos"),
            "flags": sorted(s.get("flags", [])), "structures_seen": structures, "day": s.get("day"), "hour": s.get("hour")}


def compare(before: dict, after: dict) -> list[str]:
    problems = []
    for k in ("step", "area", "inv", "keys", "companions"):
        if before.get(k) != after.get(k):
            problems.append(f"{k}: before={before.get(k)} after={after.get(k)}")
    missing = set(before["flags"]) - set(after["flags"])
    if missing:
        problems.append(f"flags lost: {sorted(missing)}")
    return problems


def run(a):
    out = Path(a.out)
    exe = str(Path(a.exe).resolve())
    save_dir = out / "saves"
    results = []

    def launch(name):
        sess = Session(exe, out, save_dir, name, extra=["--windowed"], **transport_kwargs(a))
        sess.start(wait_for=lambda s: s.get("mode") == "title" and len(s.get("buttons", [])) > 0, timeout=60)
        return sess, Play(sess)

    class A:  # minimal args object for build_steps
        continue_save = False

    # ---- Session 1 ----------------------------------------------------------------------
    sess, p = launch("persist_s1")
    steps = dict(build_steps(p, A))
    order = ["title_new_game", "read_ward", "gather_basics", "craft_axe", "chop", "workbench", "mochi", "pebble"]
    for name in order:
        p.log(f"=== S1 {name}")
        if not steps[name]():
            sess.record(f"persist:s1:{name}", "interactive", name, "passes", "failed", "FAIL", [p.shot(name)])
            sess.stop()
            return
    p.travel_home()
    time.sleep(1)
    # Save from the pause menu
    p.bot.tap("ESC")
    time.sleep(0.8)
    ok_save = p.click("Save Game", timeout=3)
    saved = p.wait(lambda s: any(m.get("k") == "saved" for m in s.get("messages", [])), 6) is not None
    p.close_panels()
    time.sleep(0.8)
    before = observe(p)
    ev1 = p.shot("before_quit")
    sess.record("persist:save_from_pause_menu", "interactive", "Esc -> Save Game", "journey saved toast",
                f"clicked={ok_save} saved_event={saved}", "PASS" if (ok_save and saved) else "FAIL", [ev1])
    files = sorted(x.name for x in save_dir.iterdir()) if save_dir.exists() else []
    sess.record("persist:save_files_written", "auto", "inspect save folder", "slot1.json exists", str(files), "PASS" if "slot1.json" in files else "FAIL")
    # Quit through the menu (Quit Game -> confirm)
    p.bot.tap("ESC")
    time.sleep(0.8)
    p.click("Quit Game", timeout=3)
    time.sleep(1.0)
    for label in ("Quit", "Yes", "Quit Game"):
        if p.bot.find_button(label):
            p.click(label, timeout=2)
            break
    t0 = time.time()
    while sess.alive() and time.time() - t0 < 15:
        time.sleep(0.5)
    exited = not sess.alive()
    sess.record("persist:quit_via_menu", "interactive", "Esc -> Quit Game -> confirm", "process exits", f"exited={exited}", "PASS" if exited else "FAIL")
    sess.stop()

    # ---- Session 2: Continue -------------------------------------------------------------
    sess, p = launch("persist_s2")
    has_continue = p.bot.find_button("Continue") is not None
    p.click("Continue", timeout=4)
    ok = p.wait(lambda s: s.get("mode") == "playing", 40) is not None
    time.sleep(3)
    p.bot.calibrate_look()
    after = observe(p)
    problems = compare(before, after)
    moved = dist2(xz(before["pos"]), xz(after["pos"])) if before["pos"] and after["pos"] else 99
    ev2 = p.shot("after_continue")
    sess.record("persist:continue_restores_state", "interactive", "relaunch -> title Continue", "same step/inventory/companions/flags; near saved position",
                f"continue_button={has_continue} playing={ok} problems={problems} moved={moved:.1f}m structures={after['structures_seen']}",
                "PASS" if (has_continue and ok and not problems and moved < 3.0) else "FAIL", [ev1, ev2])
    (out / "persist_compare_1.json").write_text(json.dumps({"before": before, "after": after, "problems": problems}, indent=2))
    steps = dict(build_steps(p, A))
    for name in ["home", "lumi", "prepare", "descend", "old_mine"]:
        p.log(f"=== S2 {name}")
        if not steps[name]():
            sess.record(f"persist:s2:{name}", "interactive", name, "passes", "failed", "FAIL", [p.shot(name)])
            sess.stop()
            return
    time.sleep(2)
    before2 = observe(p)
    ev3 = p.shot("before_kill")
    # Hard kill (simulates a crash / power loss) - the last lantern save must hold
    sess.proc.kill()
    time.sleep(2)
    sess.record("persist:hard_kill", "interactive", "TerminateProcess while underground", "process gone", f"alive={sess.alive()}", "PASS" if not sess.alive() else "FAIL", [ev3])
    sess.proc = None

    # ---- Session 3: Continue after the crash ----------------------------------------------------
    sess, p = launch("persist_s3")
    p.click("Continue", timeout=4)
    ok = p.wait(lambda s: s.get("mode") == "playing", 40) is not None
    time.sleep(3)
    p.bot.calibrate_look()
    after2 = observe(p)
    at_cp = after2["pos"] is not None and dist2(xz(after2["pos"]), (14.6, -42.0)) < 3.0
    key_ok = int(after2["keys"].get("foreman_key", 0)) == 1
    ev4 = p.shot("after_crash_continue")
    sess.record("persist:resume_after_crash", "interactive", "hard kill underground -> relaunch -> Continue",
                "resumes at the office lantern with the Foreman's Key, same quest step",
                f"playing={ok} area={after2['area']} pos={after2['pos']} at_office_lantern={at_cp} key={key_ok} step={after2['step']} (before kill: {before2['step']})",
                "PASS" if (ok and after2["area"] == "below" and at_cp and key_ok and after2["step"] == before2["step"]) else "FAIL", [ev3, ev4])
    (out / "persist_compare_2.json").write_text(json.dumps({"before": before2, "after": after2}, indent=2))
    steps = dict(build_steps(p, A))
    for name in ["deeper", "silk_and_boss", "return_home", "ending", "free_play_save"]:
        p.log(f"=== S3 {name}")
        if not steps[name]():
            sess.record(f"persist:s3:{name}", "interactive", name, "passes", "failed", "FAIL", [p.shot(name)])
            sess.stop()
            return
    sess.record("persist:complete_after_reloads", "interactive", "finish the chapter after two reloads", "chapter complete",
                f"flags has chapter_one_complete={'chapter_one_complete' in p.flags()}", "PASS" if "chapter_one_complete" in p.flags() else "FAIL", [p.shot("final")])
    sess.stop()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=str(ROOT / "builds" / "Hollowhaven" / "Hollowhaven.exe"))
    ap.add_argument("--out", default=str(ROOT / "qa" / "tmp" / "e2e" / "persist"))
    add_transport_args(ap)
    run(ap.parse_args())
