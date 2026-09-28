"""Segment S0 - a FRESH integrated game (MP 20.4 Run B, first half), played with normal inputs only.

New Game -> overwrite confirmation (none in an isolated save dir) -> comfort screen -> "Meet Krystal" (a non-default
outfit + hairstyle picked through the UI, Confirm) -> the whole Chapter One route of tools/qa/playthrough.py
(updated for Chapter Two: the Tailor's Cache as the optional Chapter One activity, the reworked 3-phase Weaver
Matron) -> restoration + ending -> free play -> accept the Ward Stone's new inscription (choice UI) -> save from
the pause menu. No teleport / flag / item cheats anywhere in the claimed route.

Library use (the lead chains segments):
    from ch2.s0_fresh_c1 import run
    result = run(bot, out_dir)            # bot: a started hhbot.Bot on the TITLE screen of an empty save dir
    -> {"segment", "status", "stopped_at", "checkpoints", "timings", "screenshots", "problems", "notes", ...}

Standalone (headless, source project, nothing on screen):
    .tools/pyenv/Scripts/python.exe tools/qa/ch2/s0_fresh_c1.py --attempt 1 [--budget 5400]
    .tools/pyenv/Scripts/python.exe tools/qa/ch2/s0_fresh_c1.py --attempt 2 --from-save <run>/checkpoints/lumi/slot1.json --from-step prepare
        (development: Continue from a checkpoint save made by an earlier run of this route - still a natural save)
    .tools/pyenv/Scripts/python.exe tools/qa/ch2/s0_fresh_c1.py --attempt 3 --boss-fixture
        (DIAGNOSTIC FIXTURE START, not a natural run: debug args put Krystal at the arena lantern with a lantern and a
         copper sword - only for developing the Matron routine)
Runs go to qa/tmp/bot/s0/run<attempt>/ with port 7000 + attempt (segment 0 scheme).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from playthrough import Play, StepFailed, build_steps, run_steps  # noqa: E402
from session import game_log_errors, headless_session, install_save  # noqa: E402

ROOT = HERE.parents[2]
RUN_ROOT = ROOT / "qa" / "tmp" / "bot" / "s0"
SEGMENT = "S0"


class _ShimSession:
    """What Play needs from a Session when only a Bot is handed over: .bot, .shot(label), .record(...)."""

    def __init__(self, bot, out_dir: Path, name: str = "s0"):
        self.bot = bot
        self.out = Path(out_dir)
        self.name = name
        self.shot_n = 0
        self.results_path = self.out / "results.jsonl"

    def shot(self, label: str) -> str:
        """The game's own "shot" command (fails headless - kept so visible runs capture the evidence)."""
        self.shot_n += 1
        path = self.out / "shots" / f"{self.name}_{self.shot_n:03d}_{label}.png"
        try:
            self.bot.win.screenshot(path)
        except Exception as e:  # noqa: BLE001
            self.bot.log(f"screenshot {path.name} not taken: {e}")
        return str(path)

    def record(self, check, kind, steps, expected, observed, result, evidence=None):
        row = {"segment": SEGMENT, "time": time.strftime("%Y-%m-%d %H:%M:%S"), "check": check, "kind": kind,
               "steps": steps, "expected": expected, "observed": observed, "result": result, "evidence": evidence or []}
        with open(self.results_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")


def run(bot, out_dir, save_dir=None, from_step: str = "", continue_save: bool = False, budget: float = 5400.0,
        outfit: str | None = None, hair: str | None = None, until: str = "", matron_style: str = "thorough",
        checkpoint_saves: bool = True) -> dict:
    """Plays segment S0 from the title screen. Returns checkpoints reached, per-step timings, screenshot
    requests, problems (bug candidates) and notes."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    shim = _ShimSession(bot, out)
    play = Play(shim)
    args = SimpleNamespace(continue_save=continue_save, from_step=from_step, until=until,
                           outfit="Strawberry Picnic" if outfit is None else outfit,
                           hair="Braided Crown" if hair is None else hair, budget=budget, matron_style=matron_style,
                           checkpoint_saves=checkpoint_saves)
    t0 = time.time()
    results = run_steps(play, args, Path(save_dir) if save_dir else None, out, shim.record, budget=budget)
    total = time.time() - t0
    names = [n for n, _ in build_steps(play, args)]
    done = [r["step"] for r in results if r["ok"]]
    failed = [r for r in results if not r["ok"]]
    status = "completes" if (done and done[-1] == names[-1] and not failed) else (
        f"stops at {failed[0]['step']}" if failed else "incomplete")
    st = play.st()
    return {
        "segment": SEGMENT, "status": status, "stopped_at": failed[0]["step"] if failed else "",
        "total_seconds": round(total, 1), "checkpoints": done,
        "timings": {r["step"]: r["seconds"] for r in results},
        "screenshots": play.shots, "problems": play.problems, "notes": play.notes,
        "final_state": {k: st.get(k) for k in ("mode", "area", "step", "flags", "companions", "optional",
                                                "appearance", "chapter2", "tracker", "inv", "keys")},
        "events_tail": play.events[-60:], "all_events": play.events,
    }


def verify_continue(save_json: Path, out_dir: Path, port: int, expect: dict) -> dict:
    """Handoff check: a COPY of the segment's final save is continued through the real title (Continue) in a
    fresh headless process; the state the next segment starts from must match what S0 left behind."""
    out_dir = Path(out_dir)
    save_dir = out_dir / "saves"
    install_save(save_json, save_dir)
    sess = headless_session(out_dir, "continue", save_dir=save_dir, port=port, max_seconds=300)
    res: dict = {"save": str(save_json), "ok": False, "mismatches": []}
    try:
        bot = sess.start(wait_for=lambda st: st.get("mode") == "title" and any(b.get("text") == "Continue" for b in st.get("buttons", [])), timeout=120)
        t0 = time.time()
        if not bot.click_button("Continue", exact=True, timeout=10):
            res["mismatches"].append("no Continue button on the title")
            return res
        st = bot.wait_state(lambda x: x.get("mode") == "playing" and bool(x.get("area")), 60)
        time.sleep(4.0)
        st = bot.state()
        res["seconds_to_play"] = round(time.time() - t0, 1)
        got = {"area": st.get("area"), "step": st.get("step"), "ui_stack": st.get("ui_stack"),
               "hair": (st.get("appearance") or {}).get("hair"), "outfit": (st.get("appearance") or {}).get("outfit"),
               "chapter2_current": (st.get("chapter2") or {}).get("current"),
               "optional_done": sorted((st.get("optional") or {}).get("done", [])),
               "companions": st.get("companions"), "keys": st.get("keys")}
        flags = set(st.get("flags", []))
        for f in expect.get("flags", []):
            if f not in flags:
                res["mismatches"].append(f"flag {f} missing after Continue")
        for k, v in expect.items():
            if k == "flags":
                continue
            if got.get(k) != v:
                res["mismatches"].append(f"{k}: expected {v!r}, got {got.get(k)!r}")
        res["observed"] = got
        res["ok"] = not res["mismatches"]
        bot.log(f"continue check: {res}")
    finally:
        sess.stop()
        res["game_log_errors"] = game_log_errors(sess.game_log)
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--attempt", type=int, default=1)
    ap.add_argument("--out", default="", help=f"run dir (default {RUN_ROOT}/run<attempt>)")
    ap.add_argument("--budget", type=float, default=5400.0, help="seconds before no new step is started (90 min)")
    ap.add_argument("--from-save", default="", help="install this save JSON first and use Continue (development)")
    ap.add_argument("--from-step", default="", help="with --from-save: first step to run after the title")
    ap.add_argument("--until", default="", help="stop before this step")
    ap.add_argument("--boss-fixture", action="store_true", help="DIAGNOSTIC FIXTURE START at the arena lantern (debug args)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--matron-style", default="thorough", choices=["thorough", "fast"])
    ap.add_argument("--verify-continue-only", default="", help="only run the Continue handoff check on this run dir")
    a = ap.parse_args()
    out = Path(a.out) if a.out else RUN_ROOT / f"run{a.attempt}"
    out.mkdir(parents=True, exist_ok=True)
    if a.verify_continue_only:
        rd = Path(a.verify_continue_only)
        prev = json.loads((rd / "s0_result.json").read_text(encoding="utf-8"))
        fs = prev.get("final_state") or {}
        ap_ = fs.get("appearance") or {}
        expect = {"area": fs.get("area"), "step": fs.get("step"), "ui_stack": [], "hair": ap_.get("hair"),
                  "outfit": ap_.get("outfit"), "chapter2_current": (fs.get("chapter2") or {}).get("current"),
                  "optional_done": sorted((fs.get("optional") or {}).get("done", [])), "companions": fs.get("companions"),
                  "keys": fs.get("keys"),
                  "flags": ["chapter_one_complete", "ward_restored", "weaver_defeated", "ch2_accepted", "c1x_tailor_cache"]}
        cc = verify_continue(rd / "saves" / "slot1.json", rd / "continue_check", 7000 + a.attempt + 50, expect)
        prev["continue_check"] = cc
        (rd / "s0_result.json").write_text(json.dumps(prev, indent=2), encoding="utf-8")
        print(json.dumps(cc, indent=1))
        return
    save_dir = out / "saves"
    extra: list[str] = []
    label = "natural (fresh New Game)"
    from_step, cont = "", False
    if a.from_save:
        install_save(a.from_save, save_dir)
        from_step, cont = a.from_step, True
        label = f"natural continuation from a checkpoint save of this route ({a.from_save})"
    if a.boss_fixture:
        extra = ["--area=below", "--spawn=cp_arena", "--give=lantern:1,copper_sword:1,berry_snack:6",
                 "--flags=lower_gate_open,reached_silk_hollows"]
        from_step, cont = "silk_and_boss", False
        label = "DIAGNOSTIC FIXTURE START (debug --area/--give at the arena lantern) - not a natural run"
    sess = headless_session(out, "s0", save_dir=save_dir, port=7000 + a.attempt, seed=a.seed, extra=extra,
                            max_seconds=a.budget + 900)
    t_launch = time.time()
    if a.boss_fixture:
        bot = sess.start(wait_for=lambda s: s.get("mode") == "playing", timeout=120)
    else:
        bot = sess.start(wait_for=lambda s: s.get("mode") == "title" and len(s.get("buttons", [])) > 0, timeout=120)
    bot.log(f"S0 run: {label}")
    try:
        if a.boss_fixture:
            time.sleep(2.0)
            bot.calibrate_look()
            shim = _ShimSession(bot, out)
            play = Play(shim)
            build_steps(play, SimpleNamespace(continue_save=False, matron_style=a.matron_style))
            t0 = time.time()
            ok = False
            try:
                play.light_cp((100.9, -115.5))      # the arena lantern: respawn point if Krystal falls
                ok = bool(play.boss_fight())
            except StepFailed as e:
                bot.log(f"StepFailed: {e}")
            res = {"segment": SEGMENT, "status": "diagnostic boss fixture " + ("won" if ok else "not won"),
                   "total_seconds": round(time.time() - t0, 1), "problems": play.problems, "notes": play.notes,
                   "events_tail": play.events[-80:]}
        else:
            res = run(bot, out, save_dir=save_dir, from_step=from_step, continue_save=cont, budget=a.budget, until=a.until,
                      matron_style=a.matron_style)
    finally:
        sess.stop()
    res["start"] = label
    res["wall_seconds"] = round(time.time() - t_launch, 1)
    res["game_log_errors"] = game_log_errors(sess.game_log)
    res["focus_report"] = sess.focus_report()
    all_events = res.pop("all_events", None)
    if all_events is not None:
        (out / "events.txt").write_text("\n".join(all_events), encoding="utf-8")
    if not a.boss_fixture and res.get("status") == "completes" and (save_dir / "slot1.json").exists():
        fs = res.get("final_state") or {}
        ap = fs.get("appearance") or {}
        expect = {"area": fs.get("area"), "step": fs.get("step"), "ui_stack": [], "hair": ap.get("hair"),
                  "outfit": ap.get("outfit"), "chapter2_current": (fs.get("chapter2") or {}).get("current"),
                  "optional_done": sorted((fs.get("optional") or {}).get("done", [])), "companions": fs.get("companions"),
                  "keys": fs.get("keys"),
                  "flags": ["chapter_one_complete", "ward_restored", "weaver_defeated", "ch2_accepted", "c1x_tailor_cache"]}
        res["continue_check"] = verify_continue(save_dir / "slot1.json", out / "continue_check", 7000 + a.attempt + 50, expect)
    (out / "s0_result.json").write_text(json.dumps(res, indent=2), encoding="utf-8")
    print(json.dumps({k: res.get(k) for k in ("status", "total_seconds", "wall_seconds", "checkpoints", "timings", "problems", "notes",
                                              "continue_check")}, indent=1))


if __name__ == "__main__":
    main()
