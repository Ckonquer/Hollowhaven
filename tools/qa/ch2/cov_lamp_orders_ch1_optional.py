"""Coverage run "lamp_orders_ch1_optional" (MP 20.3 "quarry/orchard/manor in all meaningful orders", MP 7 optional
Chapter One content). Headless only, virtual input only, isolated save dir / settings file, bounded time.

Two parts (run them as separate processes; each has its own run dir and ports):

--part ch2   NATURAL START: the game's own checkpoint save at the end of S1 of a natural chain run
             (qa/tmp/bot/chain/run3/checkpoints/S1_end/slot1.json: Commons, Chapter Two at "Three Roads, Three Lamps",
             no lamp found). Lamp order MANOR -> ORCHARD -> QUARRY (the chain plays orchard -> quarry -> manor):
               home   Commons arch -> Lantern Road home -> bed / crops / cooking -> Ward Stone -> Commons -> manor arch
               S3     tools/qa/ch2/s3_manor.py as the chain plays it (manor seal must arrive with ONLY that lamp lit)
               walk   manor grounds -> north road -> west round the Conservatory -> crossroads
               orch   tools/qa/ch2/s2_orchard_quarry.py orchard steps (garden seal as the SECOND lamp)
               quarry quarry arch, wood, iron, winch (finds the third lamp -> ch2_outer_lamps completes), repair the
                      winch - then STOP before the Quarry Warden (game/src/enemies/quarry_warden.gd was being edited by
                      another agent during this run): the quarry lamp is read (prompt + reason), not lit.
               checks seals / chapter2 done + current / tracker / objective rows after every lamp; the Conservatory
                      pedestal refuses with two seals; Save & Quit -> relaunch -> Continue keeps everything (no duplicate
                      seals).
--part ch1   NATURAL START: a COPY of game/tests/fixtures/saves/16_real_handoff_c1_complete.json (v1 -> v2 migration on
             Continue). Chapter One optional content (MP 7): Tailor's Cache (cloth for the armor piece), Bramblewatch
             (Knotted Elder + the Brambleback group), Sunny Meadow wild crops -> plant sunflax at home -> harvest,
             furnace + copper-bar queue, copper armor piece (Copper, Not Just Courage), stairs + porch post + upper floor
             placed in build mode and walked up, Tobin's annex (door, Hollow Drudge, letter, service note, hatch
             shortcut). Every optional goal's reward is counted once; Save & Quit -> relaunch -> Continue repeats the
             count (no duplicates).

The bot perceives the game ONLY through the read-only QA telemetry and acts ONLY through the virtual keyboard / mouse
(src/qa/qa_input.gd). Information advantage (label it in reports): authored coordinates from data/*.gd, exact enemy
states / prompts from telemetry.

  python tools/qa/ch2/cov_lamp_orders_ch1_optional.py --part ch2 --out qa/tmp/bot/cov_lamp_orders_ch1_optional/ch2_a1 --port 8141
  python tools/qa/ch2/cov_lamp_orders_ch1_optional.py --part ch1 --out qa/tmp/bot/cov_lamp_orders_ch1_optional/ch1_a1 --port 8151
Writes <out>/cov_result.json, <out>/bugs.json (+ chain-style logs, telemetry, checkpoints).
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
import time
import traceback
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
QA_DIR = HERE.parent
ROOT = QA_DIR.parents[1]
for _p in (str(HERE), str(QA_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import chain as CH  # noqa: E402
from session import SECOND_MONITOR_RECT, parse_rect  # noqa: E402

REACH = CH.REACH
SURFACE = CH.SURFACE
S1_END = ROOT / "qa" / "tmp" / "bot" / "chain" / "run3" / "checkpoints" / "S1_end" / "slot1.json"
FIXTURE16 = ROOT / "game" / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.json"
SEALS = ("garden_seal", "quarry_seal", "manor_seal")
# T23's road Commons -> manor arch, walked backwards (manor arch -> west round the Conservatory -> crossroads)
MANOR_ARCH_TO_CROSSROADS = [(10.9, -52.8), (10.0, -50.0), (8.1, -44.3), (5.0, -34.0), (2.5, -24.0), (0.5, -12.0),
                            (0.5, -8.0), (-9.0, 2.0), (-8.0, 12.0), (0.0, 22.0), (0.0, 30.0), (0.0, 38.5)]


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def xz(p):
    return (p[0], p[2]) if len(p) >= 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


class Stop(Exception):
    pass


# ================================================================================================ shared recording
class CovMixin:
    """Observation records + bugs on top of the chain driver."""

    def cov_init(self):
        self.obs: list[dict] = []
        self.cov_bugs: list[dict] = []
        self.cov_notes: list[str] = []

    def observe(self, label: str, extra: dict | None = None) -> dict:
        s = self.st()
        c2 = s.get("chapter2") or {}
        inv = s.get("inv") or {}
        keys = s.get("keys") or {}
        rec = {"label": label, "wall": now(), "area": s.get("area"), "zone": s.get("zone"),
               "pos": (s.get("player") or {}).get("pos"), "hp": (s.get("player") or {}).get("hp"),
               "seals": {k: int(inv.get(k, 0)) + int(keys.get(k, 0)) for k in SEALS},
               "ch2_done": list(c2.get("done") or []), "ch2_current": list(c2.get("current") or []),
               "ch2_title": c2.get("title"), "tracker": s.get("tracker"), "objective": s.get("objective"),
               "optional": s.get("optional"),
               "flags": sorted(f for f in (s.get("flags") or []) if f.startswith(("ch2_", "hr_", "c1x_", "ta_", "mm_"))),
               "t_game": s.get("t")}
        if extra:
            rec.update(extra)
        self.obs.append(rec)
        self.log(f"OBSERVE {label}: seals={rec['seals']} done={rec['ch2_done']} current={rec['ch2_current']} "
                 f"tracker={json.dumps(rec['tracker'])[:300]}")
        return rec

    def cov_bug(self, title, severity, steps, expected, actual, evidence):
        for b in self.cov_bugs:
            if b["title"] == title:
                return
        self.cov_bugs.append({"title": title, "severity": severity, "steps": steps, "expected": expected,
                              "actual": actual, "evidence": evidence})
        self.log(f"BUG [{severity}] {title}: {actual}")

    def cov_note(self, text: str):
        self.cov_notes.append(text)
        self.log(f"NOTE {text}")


# ================================================================================================ part ch2
EAST_ROAD = [(12.0, 40.0), (26.0, 42.5), (40.0, 44.0), (50.0, 43.5), (57.4, 41.8), (60.8, 39.2)]
WEST_ROAD = [(-12.0, 41.0), (-22.0, 45.0), (-28.5, 48.3), (-34.0, 48.3), (-39.5, 48.3), (-46.0, 51.5),
             (-54.9, 53.2), (-58.5, 51.5)]
CROSSROADS_TO_MANOR_ARCH = MANOR_ARCH_TO_CROSSROADS[::-1]


class LampOrder(CovMixin, CH.Chain):
    def __init__(self, cfg):
        super().__init__(cfg)
        self.cov_init()
        self.home_reports = {}
        self.order = list(getattr(cfg, "order", ["manor", "orchard"]))
        pos = {k: ("FIRST" if i == 0 else "SECOND") for i, k in enumerate(self.order)}
        CH.TITLES.update({
            "HOME": "Commons -> Lantern Road home -> rest / cook -> Ward Stone -> Commons",
            "S3": CH.TITLES["S3"] + f" - {pos.get('manor', '?')} lamp in this order",
            "ORCH": f"-> crossroads -> Pumpkintide Orchard ({pos.get('orchard', '?')} lamp)",
            "QPRE": "Ashbell Quarry up to the repaired winch (third lamp FOUND, not lit; stop before the Warden)",
            "CHECK": "Tracker / pedestal / quarry lamp reason with two lamps lit",
            "RELOAD": "Save & Quit -> relaunch -> Continue: nothing lost, nothing duplicated",
        })

    # ---------------------------------------------------------------- segments
    def seg_home(self):
        p1, p4, _ = self._players(self.out / "home")

        def to_home():
            return self.arch_travel(p1, "commons", "The Haven (home)", SURFACE)

        def rest():
            return self.home_rest(p1, "before_manor")

        def to_commons():
            return self.ward_stone_travel(p1, "Lanternwake Commons")

        return self.run_steps("HOME", [("lantern_road_home", to_home), ("home_rest", rest),
                                       ("lantern_road_commons", to_commons)])

    # ---------------------------------------------------------------- walking between the districts (Reach)
    def walk_to_crossroads(self, p4) -> bool:
        """From anywhere on the Reach roads (Commons, manor grounds, west road / orchard, east road / quarry) to
        the crossroads south of the Conservatory (0, 38.5)."""
        import s3_manor as S3
        here = xz(p4.pos())
        if dist2(here, (0.0, 38.5)) < 3.0:
            return True
        if here[1] < -40.0 and here[0] > 0.0:
            pts = list(reversed(S3.GROUNDS_PATH)) + MANOR_ARCH_TO_CROSSROADS
        elif here[0] < -8.0 and here[1] > 20.0:
            pts = list(reversed(WEST_ROAD)) + [(0.0, 38.5)]
        elif here[0] > 8.0 and here[1] > 20.0:
            pts = list(reversed(EAST_ROAD)) + [(0.0, 38.5)]
        elif here[1] > 44.0:
            pts = [(1.5, 70.0), (2.5, 68.0), (2.5, 53.0), (0.0, 45.0), (0.0, 38.5)]
        else:
            pts = MANOR_ARCH_TO_CROSSROADS
        if here[0] < -60.0:
            pts = [(-69.5, 44.5), (-60.0, 50.0)] + pts
        i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
        if not p4.route(pts[i:], tol=1.7, sprint=True, fight=True):
            raise CH.ChainStop(f"could not walk to the crossroads (at {p4.pos()})")
        return True

    def walk_to_manor_arch(self, p4) -> bool:
        here = xz(p4.pos())
        if dist2(here, (10.9, -52.8)) < 3.0:
            return True
        if not (here[1] < 0.0 and abs(here[0]) < 15.0):
            self.walk_to_crossroads(p4)
        pts = CROSSROADS_TO_MANOR_ARCH
        here = xz(p4.pos())
        i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
        if not p4.route(pts[i:], tol=1.8, sprint=True, fight=True):
            raise CH.ChainStop(f"the road to the manor arch is blocked at {p4.pos()}")
        ok = dist2(xz(p4.pos()), (10.9, -52.8)) < 3.0
        self.observe("at_manor_arch_before_manor")
        return ok

    def seg_s3_first(self):
        p1, p4, _ = self._players(self.out / "to_manor")
        okw, detw = self.run_steps("S3", [("walk_to_manor_arch", lambda: self.walk_to_manor_arch(p4))])
        if not okw:
            return okw, detw
        before = self.observe("before_manor")
        ok, det = self.seg_s3()
        after = self.observe("after_manor_lamp")
        if after["seals"]["manor_seal"] < 1 and "ch2_manor_lamp_lit" in after["flags"]:
            self.cov_bug(f"Manor Seal missing when the manor is lamp #{self.order.index('manor') + 1} lit", "major",
                         f"Chain S1_end checkpoint -> lamps in the order {self.order} -> light the Moonveil lantern",
                         "ch2_manor completes on ch2_manor_lamp_lit alone and grants the Manor Seal (MP 11 steps 5-7 are parallel)",
                         f"seals {after['seals']}, done {after['ch2_done']}, current {after['ch2_current']}",
                         [str(self.out / "cov_result.json")])
        if "ch2_manor" not in after["ch2_done"] and "ch2_manor_lamp_lit" in after["flags"]:
            self.cov_bug("Step ch2_manor not completed after lighting the manor lamp first", "major",
                         "Manor first from the S1_end checkpoint", "ch2_manor in chapter2.done",
                         f"done {after['ch2_done']} current {after['ch2_current']}", [str(self.out / "cov_result.json")])
        exp_cur = {"ch2_outer_lamps", "ch2_quarry"} | ({"ch2_orchard"} if "ch2_orchard" not in after["ch2_done"] else set())
        if set(after["ch2_current"]) != exp_cur:
            self.cov_note(f"after the manor the current steps are {after['ch2_current']} (expected {sorted(exp_cur)})")
        det = dict(det)
        det["before"] = {k: before[k] for k in ("seals", "ch2_done", "ch2_current")}
        det["after"] = {k: after[k] for k in ("seals", "ch2_done", "ch2_current", "tracker")}
        return ok, det

    def _s2(self, out_name: str):
        import s2_orchard_quarry as S2
        seg = S2.Segment(self.bot, self.out / out_name, {"patchwalker": False, "save_checkpoints": False})
        return S2, seg

    def seg_orchard(self):
        S2, seg = self._s2("orch")
        p1, p4, _ = self._players(self.out / "orch_walk")
        cps = []

        def grounds_to_crossroads():
            return self.walk_to_crossroads(p4)

        ok, det = self.run_steps("ORCH", [("grounds_to_crossroads", grounds_to_crossroads)])
        cps += det.get("checkpoints", [])
        if not ok:
            return ok, det
        try:
            self.bot.calibrate_look()
            seg.step("to_orchard", seg.to_orchard)
            seg.step("light_orchard_arch", lambda: seg.light_arch("orchard", S2.ORCHARD_ARCH), required=False)
            seg.step("find_orchard_lamp", seg.find_orchard_lamp)
            self.observe(f"orchard_lamp_found_{self.order.index('orchard') + 1}")
            seg.step("seed_box_note", seg.seed_box_note, required=False)
            seg.step("irrigation", seg.irrigation)
            seg.step("plant_festival_seed", seg.plant_seed, required=False)
            seg.step("mimic_pocket", seg.mimic_pocket)
            seg.step("light_garden_lamp", seg.light_garden_lamp)
            seg.step("garden_seal", seg.check_garden_seal, required=False)
            status = "completes"
        except S2.StepFailed as e:
            status = f"stops: {e}"
        after = self.observe(f"after_garden_lamp_{self.order.index('orchard') + 1}")
        for b in seg.p.bugs:
            self.cov_bug(b["title"], b["severity"], b["steps"], b["expected"], b["actual"], [b.get("evidence", "")])
        cps += [{"name": c["name"], "ok": c["ok"], "at_s": c["t"], "hp": c["hp"], "detail": str(c.get("detail"))[:200]}
                for c in seg.checkpoints]
        if after["seals"]["garden_seal"] < 1 and "ch2_garden_lamp_lit" in after["flags"]:
            self.cov_bug(f"Garden Seal missing when the orchard is lamp #{self.order.index('orchard') + 1}", "major",
                         f"S1_end checkpoint -> lamps in the order {self.order}", "Garden Seal granted on lighting",
                         f"seals {after['seals']} done {after['ch2_done']}", [str(self.out / "cov_result.json")])
        return status == "completes", {"status": status, "checkpoints": cps, "problems": seg.p.problems}

    def seg_quarry_pre(self):
        S2, seg = self._s2("qpre")
        cps = []
        status = "completes"
        found_msgs = []
        try:
            p1, p4, _ = self._players(self.out / "q_walk")
            here = xz(p4.pos())
            if here[1] < 20.0 or here[0] < -20.0:
                self.walk_to_crossroads(p4)
            self.bot.calibrate_look()
            seg.p.heal_up(target=80.0, max_items=4)
            seg.step("to_quarry", seg.to_quarry)
            seg.step("light_quarry_arch", lambda: seg.light_arch("quarry", S2.QUARRY_ARCH), required=False)
            seg.step("gather_wood", seg.gather_wood)
            seg.step("mine_iron", seg.mine_iron)
            t_before_found = self.st().get("t") or 0
            seg.step("to_winch_find_lamp", seg.to_winch)
            seg.step("quarry_lamp_found", lambda: seg.p.wait(lambda s: S2.F["found_quarry"] in s.get("flags", []), 6.0) is not None,
                     required=False)
            time.sleep(1.5)
            found_msgs = [m.get("text") for m in seg.p.seen_msgs if float(m.get("t", 0) or 0) >= float(t_before_found or 0)]
            self.observe("quarry_lamp_found_third", {"msgs_since_found": found_msgs[-12:]})
            seg.step("repair_winch", seg.repair_winch)
            lamp = seg.interactable(["quarry lamp"], S2.LAMP, 80, 5)
            w = seg.warden()
            self.observe("after_winch_before_warden", {"quarry_lamp_entity": lamp, "warden": w})
            # walk away from the Warden's bench (the winch route, backwards) - no fight in this run
            seg.p.walk_route(list(reversed(S2.TO_WINCH[:5])), tol=1.8)
            seg.p.walk_route([S2.IRON_PREF[0], (64.3, 36.1)], tol=1.8)
        except S2.StepFailed as e:
            status = f"stops: {e}"
        for b in seg.p.bugs:
            self.cov_bug(b["title"], b["severity"], b["steps"], b["expected"], b["actual"], [b.get("evidence", "")])
        cps += [{"name": c["name"], "ok": c["ok"], "at_s": c["t"], "hp": c["hp"], "detail": str(c.get("detail"))[:200]}
                for c in seg.checkpoints]
        return status == "completes", {"status": status, "checkpoints": cps, "problems": seg.p.problems,
                                       "found_msgs": found_msgs}

    def seg_check(self):
        p1, p4, _ = self._players(self.out / "check")
        rep = {}

        def lamp_reason():
            import s2_orchard_quarry as S2
            s = self.st()
            ent = None
            for n in s.get("nearby") or []:
                if "quarry lamp" in (str(n.get("text", "")) + " " + str(n.get("name", ""))).lower():
                    ent = n
            rep["quarry_lamp"] = ent
            return True

        def to_conservatory():
            here = xz(p4.pos())
            if here[0] > 40:
                back = list(reversed([(12.0, 40.0), (26.0, 42.5), (40.0, 44.0), (50.0, 43.5), (57.4, 41.8), (60.8, 39.2)]))
                i = min(range(len(back)), key=lambda k: dist2(back[k], here))
                p4.route(back[i:] + [(0.0, 38.5)], tol=1.8, sprint=True, fight=True)
            ok = p4.nav((0.0, 0.0, 8.5), final_tol=0.8)
            time.sleep(1.0)
            ped = None
            for n in self.st().get("nearby") or []:
                t = str(n.get("text", "")).lower()
                if "pedestal" in t or "link the lanterns" in t or "pedestal" in str(n.get("name", "")).lower():
                    ped = n
                    break
            rep["pedestal"] = ped
            rep["prompt_at_pedestal"] = p4.prompt()
            # inspect it (harmless with two lamps: the Ward-Keeper names what is missing)
            t0 = float(self.st().get("t") or 0.0)
            if ped is not None and "inspect" in str(ped.get("text", "")).lower():
                p4.interact_with((0.0, 0.0, 6.0), ["Inspect the linking pedestal"], check=lambda: any(
                    m.get("k") == "say" and float(m.get("t", 0) or 0) > t0 for m in self.st().get("messages") or []), stop=2.3)
                time.sleep(1.0)
                rep["inspect_msgs"] = [m.get("text") for m in self.st().get("messages") or [] if float(m.get("t", 0) or 0) > t0]
            if ped is not None and str(ped.get("text", "")).lower().startswith("link the lanterns"):
                self.cov_bug("Conservatory pedestal offers 'Link the lanterns' with only two seals", "major",
                             "S1_end -> manor + orchard lamps lit, quarry lamp not lit -> Conservatory pedestal",
                             "linking refused (needs all three restored lamps / seals) with a reason",
                             f"pedestal entry {ped}", [str(self.out / "cov_result.json")])
            self.observe("conservatory_two_seals", {"pedestal": ped, "prompt": p4.prompt()})
            return ok

        ok, det = self.run_steps("CHECK", [("quarry_lamp_reason", lamp_reason), ("conservatory_pedestal", to_conservatory)])
        det["report"] = rep
        return ok, det

    def seg_reload(self):
        import playthrough
        pp = playthrough.Play(SimpleNamespace(bot=self.bot, shot=lambda label: self.shot(label)["path"]))
        saved = pp.pause_save()
        before = self.observe("before_quit")
        s = self.st()
        inv_before, keys_before = dict(s.get("inv") or {}), dict(s.get("keys") or {})
        self.bot.tap("ESC")
        quit_how = "killed"
        if self.bot.wait_state(lambda st: "pause" in (st.get("ui_stack") or []), 3.0) and \
                self.bot.click_button("Quit Game", exact=True, timeout=3.0):
            if self.bot.click_button("Save & Quit", exact=True, timeout=4.0):
                quit_how = "pause menu: Quit Game -> Save & Quit"
        exited = self.game.wait_exit(20.0)
        g = self.relaunch()
        if not g.bot.wait_state(lambda st: st.get("mode") == "title" and any(b.get("text") == "Continue" for b in st.get("buttons", [])), 120):
            return False, {"status": "no title / Continue after relaunch"}
        g.bot.click_button("Continue", exact=True, timeout=10)
        if not self.wait_playing(None, 120):
            return False, {"status": "Continue never reached gameplay"}
        time.sleep(2.5)
        after = self.observe("after_continue")
        s = self.st()
        inv_after, keys_after = dict(s.get("inv") or {}), dict(s.get("keys") or {})
        diff = {k: [inv_before.get(k), inv_after.get(k)] for k in set(inv_before) | set(inv_after) if inv_before.get(k) != inv_after.get(k)}
        kdiff = {k: [keys_before.get(k), keys_after.get(k)] for k in set(keys_before) | set(keys_after) if keys_before.get(k) != keys_after.get(k)}
        same = (after["seals"] == before["seals"] and after["ch2_done"] == before["ch2_done"]
                and set(after["ch2_current"]) == set(before["ch2_current"]) and not diff and not kdiff
                and set(before["flags"]) <= set(after["flags"]))
        if not same:
            self.cov_bug("Lamp-order state changed across Save & Quit -> Continue", "major",
                         "S1_end -> manor, orchard lamps, quarry winch; pause Save Game; Quit Game -> Save & Quit; relaunch; Continue",
                         "identical seals, steps, flags and items",
                         f"seals {before['seals']} -> {after['seals']}; done {before['ch2_done']} -> {after['ch2_done']}; "
                         f"inv diff {diff}; key diff {kdiff}; lost flags {sorted(set(before['flags']) - set(after['flags']))}",
                         [str(self.out / "cov_result.json")])
        return same, {"status": "completes" if same else "state changed", "saved": saved, "quit": quit_how,
                      "exited": exited, "inv_diff": diff, "key_diff": kdiff}

    # ---------------------------------------------------------------- driver
    def run_cov(self):
        cfg = self.cfg
        status = "running"
        self.monitor.start()
        try:
            self.save_dir.mkdir(parents=True, exist_ok=True)
            CH.C.prepare_saves(self.save_dir, Path(self.start_save), Path(self.start_save).with_name("slot1.bak.json"))
            self.launch()
            if not self.bot.wait_state(lambda s: s.get("mode") == "title" and any(b.get("text") == "Continue" for b in s.get("buttons", [])), 120):
                raise CH.ChainStop("no title / Continue")
            self.bot.click_button("Continue", exact=True, timeout=10)
            if not self.wait_playing(None, 120):
                raise CH.ChainStop("Continue never reached gameplay")
            time.sleep(2.0)
            self.bot.calibrate_look()
            self.observe("start_S1_end")
            lamp_segs = {"manor": ("S3", self.seg_s3_first), "orchard": ("ORCH", self.seg_orchard)}
            order = [("HOME", self.seg_home)] + [lamp_segs[k] for k in self.order] + [
                ("QPRE", self.seg_quarry_pre), ("CHECK", self.seg_check), ("RELOAD", self.seg_reload)]
            for seg, fn in order:
                if time.time() > self.deadline:
                    status = f"stops before {seg}: time budget used up"
                    break
                if not self.run_segment(seg, fn):
                    status = f"stops in {seg}: {self.segments[-1]['status']}"
                    if seg in ("CHECK",):
                        continue
                    break
            else:
                status = "completes"
        except Exception as e:  # noqa: BLE001
            status = f"harness error {type(e).__name__}: {e}"
            self.log(traceback.format_exc())
        finally:
            for g in self.games:
                g.stop()
            time.sleep(0.8)
            self.monitor.stop()
            self.monitor.join(5.0)
            errs, warns = self.collect_errors()
            self.all_errors += errs
            self.warnings += warns
        self.write_result(status)
        res = json.loads((self.out / "chain_result.json").read_text(encoding="utf-8"))
        cov = {"part": "ch2", "natural": True, "start_save": str(self.start_save), "order": " -> ".join(self.order + ["quarry(pre-Warden)"]),
               "status": status, "observations": self.obs, "notes": self.cov_notes + self.notes,
               "segments": [{k: s.get(k) for k in ("id", "ok", "seconds", "status", "checkpoints", "hp_min", "deaths",
                                                   "script_errors", "problems")} for s in self.segments],
               "home_rests": self.home_reports, "script_errors": res.get("script_errors"),
               "warnings": res.get("warnings"), "total_seconds": res.get("total_seconds")}
        CH.write_json(self.out / "cov_result.json", cov)
        bugs = list(self.cov_bugs)
        for g in (res.get("script_errors") or {}).get("unique", []):
            bugs.append({"title": f"SCRIPT ERROR: {str(g.get('line'))[:150]}", "severity": "major",
                         "steps": f"lamp order run (segments {g.get('segments')})", "expected": "no script errors",
                         "actual": f"{g.get('count')}x {g.get('line')} {g.get('at')}",
                         "evidence": [str(x.godot_log) for x in self.games]})
        CH.write_json(self.out / "bugs.json", bugs)
        return status


# ================================================================================================ part ch1
# Surface coordinates (x east, z south; data/world_layout.gd, game/src/world/surface/surface_layout.gd PATHS,
# data/c1x_layout.gd, game/src/world/surface/c1x/tobin_door.gd).
PATHS = {
    "meadow": [(1, 13), (0, 23), (-3, 34), (-6, 45), (-8, 52)],
    "old_oak": [(-8, -9), (-17, -13), (-25, -17), (-29, -19)],
    "thicket": [(-39, -24), (-46, -31), (-52, -37), (-56, -41)],
    "mine": [(6, -12), (14, -22), (22, -30), (30, -40), (38, -50), (44, -58), (48, -63)],
    "quarry": [(11, -3), (17, -4.5), (21, -5), (28, -6), (40, -9), (51, -11), (58, -12)],
}
HAVEN = (0.0, 4.0)
CROP_PLOT = (-6.0, 12.0)
SUNFLAX = [(-17.4, 63.4), (-15.8, 62.6), (-14.5, 64.2), (-16.3, 65.4), (-17.9, 65.1)]
ROSEBERRY = [(-3.3, 69.3), (-0.8, 69.4), (-2.0, 71.5)]
TAILOR_STAND = (-30.0, -23.2)
ELDER_C = (-86.0, -34.0)
BRAMBLEBACK_C = (-75.0, -67.0)
MINE_MOUTH = (54.0, -74.0)


def _mine_frame():
    fx, fz = -6.0, 10.0
    n = math.hypot(fx, fz)
    fx, fz = fx / n, fz / n
    ox, oz = MINE_MOUTH[0] + fx * 0.4, MINE_MOUTH[1] + fz * 0.4
    yaw = math.atan2(fx, fz)
    rx, rz = math.cos(yaw), -math.sin(yaw)
    return (ox, oz), (rx, rz), (fx, fz)


def mine_local(lx, lz):
    (ox, oz), (rx, rz), (fx, fz) = _mine_frame()
    return (ox + rx * lx + fx * lz, oz + rz * lx + fz * lz)


TOBIN_DOOR = mine_local(6.8, 2.2)
TOBIN_DOOR_SPAWN = mine_local(6.8, 7.8)
TOBIN_HATCH = mine_local(-7.8, 3.6)
# Tobin's annex (src/world/annex/annex_layout.gd): floor points (x, y, z)
ANNEX_TO_LOCKERS = [(0.0, 0.0, -6.5), (0.0, 0.0, -7.5), (0.0, 0.0, -9.0)]
ANNEX_LETTER = (3.9, 0.0, -19.6)
ANNEX_LETTER_STAND = (3.0, 0.0, -19.6)
ANNEX_DOWN = [(0.0, 0.0, -22.5), (0.0, 0.0, -24.5), (0.0, -2.0, -30.5), (0.0, -2.0, -32.5), (1.5, -2.0, -34.5)]
ANNEX_NOTE = (6.05, -2.0, -34.6)
ANNEX_NOTE_STAND = (4.6, -2.0, -34.6)
ANNEX_MARK = (-0.8, -0.3, -41.97)
ANNEX_MARK_STAND = (-0.8, -2.0, -40.6)
ANNEX_LADDER = (5.0, -2.0, -41.72)
ANNEX_LADDER_STAND = (4.6, -2.0, -40.2)
# Build site: the south-west lawn region of the Haven (data/world_layout.gd BUILD_AREA extra (-9, 19) r 6.5).
# Stairs rot 0 (rise toward -Z) on the 2 m grid: footprint x -10..-8, z 18..22; landing tile x -10..-8, z 16..18
# (held up by a porch post in cell (-10, 16)). Alternatives shift the whole group by whole tiles.
BUILD_SITES = [(0.0, 0.0), (-2.0, 0.0), (0.0, 2.0), (2.0, -2.0)]
FURNACE_AIMS = [(-13.0, 8.5), (-12.5, 11.5), (-16.5, -4.0), (-14.0, 21.0)]
GOALS_CH1 = ["opt_tailors_cache", "opt_bramblewatch", "opt_gardeners_afternoon", "opt_tobins_shift", "opt_upstairs",
             "opt_copper_courage"]
GOAL_REWARDS = {"opt_tailors_cache": {"woven_cloth": 2}, "opt_bramblewatch": {"sturdy_planter": 1},
                "opt_gardeners_afternoon": {"sunflax_seeds": 3, "roseberry_seeds": 3}, "opt_tobins_shift": {},
                "opt_upstairs": {"wood_railing": 4}, "opt_copper_courage": {"copper_bar": 2}}


def yaw_to(src, dst) -> float:
    return math.degrees(math.atan2(-(dst[0] - src[0]), -(dst[1] - src[1])))


class Ch1Optional(CovMixin, CH.Chain):
    def __init__(self, cfg, only=None):
        super().__init__(cfg)
        self.cov_init()
        self.only = only or []
        self.obst: dict = {}
        self.goal_log: dict = {}
        self.build_report: dict = {}
        self.furnace_report: dict = {}
        self.fights: dict = {}
        self.p1 = None
        self.p4 = None
        CH.TITLES.update({
            "C1": "Continue the real Chapter-One-complete save (v1 -> v2) and read the optional goals",
            "GARDEN": "Sunny Meadow wild crops -> plant sunflax at home (A Gardener's Afternoon, part 1)",
            "REST": "Sleep until morning, harvest the sunflax (A Gardener's Afternoon, part 2)",
            "TAILOR": "The Tailor's Cache (cloth for the armor piece)",
            "BRAMBLE": "Bramblewatch: the Knotted Elder and the Brambleback group",
            "WOOD": "Chop wood for the furnace, stairs, post and upper floor",
            "BUILD": "Furnace + one copper bar; stairs, porch post, upper floor in build mode; walk upstairs",
            "FIX": "An upper floor tile on the stairs' real landing (neighbour-supported), then walk up",
            "ARMOR": "Collect the bar, Copperwood Hood, wear it (Copper, Not Just Courage)",
            "ANNEX": "Tobin's Lost Shift: side door, Hollow Drudge, letter, service note, mark, hatch shortcut",
            "SMELT": "Furnace queue: several copper bars, collected exactly once",
            "RELOAD": "Save & Quit -> relaunch -> Continue: goals, rewards and structures kept, nothing duplicated",
        })

    # ------------------------------------------------------------------ plumbing
    def players(self, name: str):
        self.p1, self.p4, _ = self._players(self.out / name)
        return self.p1, self.p4

    def s(self) -> dict:
        return self.st()

    def inv(self, item: str) -> int:
        s = self.st()
        return int((s.get("inv") or {}).get(item, 0)) + int((s.get("keys") or {}).get(item, 0))

    def inv_all(self) -> dict:
        s = self.st()
        out = dict(s.get("inv") or {})
        for k, v in (s.get("keys") or {}).items():
            out["key:" + k] = v
        return out

    def flags(self) -> set:
        return set(self.st().get("flags") or [])

    def opt_done(self) -> list:
        return list(((self.st().get("optional") or {}).get("done")) or [])

    def pos(self):
        return (self.st().get("player") or {}).get("pos") or [0, 0, 0]

    def hp(self) -> float:
        return float((self.st().get("player") or {}).get("hp") or 0.0)

    def msgs_since(self, t0: float) -> list:
        return [m for m in (self.st().get("messages") or []) if float(m.get("t", 0) or 0) > t0]

    def gt(self) -> float:
        return float(self.st().get("t") or 0.0)

    def goal_snapshot(self, goal: str, label: str, inv_before: dict):
        """Records a goal's state and the inventory change since inv_before (rewards counted once)."""
        inv_after = self.inv_all()
        delta = {k: inv_after.get(k, 0) - inv_before.get(k, 0) for k in set(inv_after) | set(inv_before)
                 if inv_after.get(k, 0) != inv_before.get(k, 0)}
        done = goal in self.opt_done()
        rec = {"goal": goal, "label": label, "done": done, "inv_delta": delta, "wall": now(), "game_t": self.gt(),
               "day": self.st().get("day"), "hour": self.st().get("hour")}
        self.goal_log.setdefault(goal, []).append(rec)
        self.log(f"GOAL {goal} [{label}] done={done} delta={delta}")
        return rec

    # ------------------------------------------------------------------ obstacle-aware walking (surface woods)
    def obst_update(self):
        for n in self.st().get("nearby") or []:
            g = n.get("g")
            label = (str(n.get("label", "")) + " " + str(n.get("name", ""))).lower()
            tool = n.get("tool")
            r = 0.0
            if g == "harvestable":
                if tool == "axe" or "tree" in label:
                    r = 1.05
                elif tool == "pickaxe":
                    r = 1.0
                elif "bush" in label:
                    r = 0.75
            elif g in ("crafting_station",):
                r = 1.2
            if r <= 0:
                continue
            p = n.get("pos") or [0, 0, 0]
            key = n.get("id") or f"{n.get('name')}@{round(p[0], 1)},{round(p[2], 1)}"
            self.obst[key] = (float(p[0]), float(p[2]), r)

    def plan(self, start, goal, cell=0.6, margin=10.0):
        x0, x1 = min(start[0], goal[0]) - margin, max(start[0], goal[0]) + margin
        z0, z1 = min(start[1], goal[1]) - margin, max(start[1], goal[1]) + margin
        nx, nz = int((x1 - x0) / cell) + 1, int((z1 - z0) / cell) + 1
        if nx * nz > 60000:
            return None
        blocked = set()
        for (ox, oz, r) in self.obst.values():
            if ox < x0 - 3 or ox > x1 + 3 or oz < z0 - 3 or oz > z1 + 3:
                continue
            rr = r + 0.5
            for i in range(max(0, int((ox - rr - x0) / cell)), min(nx, int((ox + rr - x0) / cell) + 2)):
                for j in range(max(0, int((oz - rr - z0) / cell)), min(nz, int((oz + rr - z0) / cell) + 2)):
                    cx, cz = x0 + i * cell, z0 + j * cell
                    if (cx - ox) ** 2 + (cz - oz) ** 2 <= rr * rr:
                        blocked.add((i, j))

        def cell_of(p):
            return (min(nx - 1, max(0, int(round((p[0] - x0) / cell)))), min(nz - 1, max(0, int(round((p[1] - z0) / cell)))))
        s, g = cell_of(start), cell_of(goal)
        for c in (s, g):
            for di in range(-1, 2):
                for dj in range(-1, 2):
                    blocked.discard((c[0] + di, c[1] + dj))
        import heapq
        openh = [(0.0, s)]
        gs = {s: 0.0}
        prev = {}
        found = False
        n_exp = 0
        while openh and n_exp < 60000:
            f, c = heapq.heappop(openh)
            n_exp += 1
            if c == g:
                found = True
                break
            for di, dj, w in ((1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)):
                nb = (c[0] + di, c[1] + dj)
                if nb[0] < 0 or nb[1] < 0 or nb[0] >= nx or nb[1] >= nz or nb in blocked:
                    continue
                ng = gs[c] + w
                if ng < gs.get(nb, 1e18):
                    gs[nb] = ng
                    prev[nb] = c
                    heapq.heappush(openh, (ng + math.hypot(nb[0] - g[0], nb[1] - g[1]), nb))
        if not found:
            return None
        path = [g]
        while path[-1] != s:
            path.append(prev[path[-1]])
        path.reverse()
        pts = [(x0 + c[0] * cell, z0 + c[1] * cell) for c in path]

        def clear(a, b):
            d = math.hypot(b[0] - a[0], b[1] - a[1])
            k = max(1, int(d / (cell * 0.5)))
            for t in range(k + 1):
                px, pz = a[0] + (b[0] - a[0]) * t / k, a[1] + (b[1] - a[1]) * t / k
                if cell_of((px, pz)) in blocked:
                    return False
            return True
        out = [pts[0]]
        i = 0
        while i < len(pts) - 1:
            j = len(pts) - 1
            while j > i + 1 and not clear(pts[i], pts[j]):
                j -= 1
            out.append(pts[j])
            i = j
        out[-1] = goal
        return out[1:]

    def walk_leg(self, target, tol=0.9, timeout=25.0, sprint=True) -> str:
        """Straight walk with steering. Returns 'ok', 'stuck', 'ui' or 'timeout' (no own unstick dance)."""
        b = self.bot
        t0 = time.time()
        last = time.time()
        best = 1e9
        jumped = False
        b.down("W")
        if sprint:
            b.down("SHIFT")
        try:
            while time.time() - t0 < timeout:
                s = self.st()
                if s.get("ui_stack"):
                    return "ui"
                if s.get("mode") != "playing":
                    b.release_all()
                    time.sleep(0.3)
                    b.down("W")
                    continue
                p = (s.get("player") or {}).get("pos") or [0, 0, 0]
                d = math.hypot(target[0] - p[0], target[1] - p[2])
                if d <= tol:
                    return "ok"
                want = yaw_to((p[0], p[2]), target)
                y = (s.get("player") or {}).get("cam_yaw")
                if y is not None:
                    dd = CH.angle_diff(want, y)
                    if abs(dd) > 1.5:
                        step = max(-30.0, min(30.0, dd))
                        b.win.mouse_move(-step * b.px_per_deg * b.invert * 0.7, 0)
                if d < best - 0.25:
                    best = d
                    last = time.time()
                elif time.time() - last > 1.4:
                    if not jumped:
                        b.tap("SPACE")
                        jumped = True
                        last = time.time()
                    else:
                        return "stuck"
                time.sleep(0.05)
            return "timeout"
        finally:
            b.release_all()

    def walk_nav(self, goal, tol=1.2, fight=True, replans=8, sprint=True) -> bool:
        goal = (float(goal[0]), float(goal[1]))
        for attempt in range(replans):
            if fight:
                self.fight_threats(12.0)
            if self.st().get("ui_stack"):
                self.p4.close_panels()
            self.obst_update()
            me = self.pos()
            if math.hypot(goal[0] - me[0], goal[1] - me[2]) <= tol:
                return True
            path = self.plan((me[0], me[2]), goal) or [goal]
            res = "ok"
            for k, wp in enumerate(path):
                last = k == len(path) - 1
                res = self.walk_leg(wp, tol=tol if last else 0.9, timeout=30.0, sprint=sprint)
                if res != "ok":
                    break
                if fight and self.p4.live_enemies(9.0, lambda e: e.get("threat", True)):
                    res = "threat"
                    break
            if res == "ok":
                return True
            me = self.pos()
            if res == "stuck":
                # an unseen obstacle (log, decor bush, fence, rock face): remember a blocker just ahead
                y = math.radians((self.st().get("player") or {}).get("cam_yaw") or 0.0)
                ax, az = me[0] - math.sin(y) * 0.9, me[2] - math.cos(y) * 0.9
                self.obst[f"virt{len(self.obst)}"] = (ax, az, 0.8)
                self.bot.hold("S", 0.35)
                self.log(f"walk_nav: stuck at {me} toward {goal}; virtual blocker at ({ax:.1f}, {az:.1f}) (replan {attempt + 1})")
            elif res == "ui":
                self.p4.close_panels()
        me = self.pos()
        return math.hypot(goal[0] - me[0], goal[1] - me[2]) <= tol * 2

    def walk_path(self, pts, tol=1.6, fight=True) -> bool:
        me = self.pos()
        i = min(range(len(pts)), key=lambda k: math.hypot(pts[k][0] - me[0], pts[k][1] - me[2]))
        for pt in pts[i:]:
            if not self.walk_nav(pt, tol=tol, fight=fight):
                return False
        return True

    def go_home(self):
        me = self.pos()
        best = None
        for name, pts in PATHS.items():
            for k, p in enumerate(pts):
                d = math.hypot(p[0] - me[0], p[1] - me[2])
                if best is None or d < best[0]:
                    best = (d, name, k)
        if best and best[0] < 30:
            pts = PATHS[best[1]][: best[2] + 1][::-1]
            for pt in pts:
                self.walk_nav(pt, tol=2.0)
        return self.walk_nav(HAVEN, tol=2.5)

    # ------------------------------------------------------------------ combat
    def fight_threats(self, radius=12.0):
        if self.p4 is None:
            return True
        live = self.p4.live_enemies(radius, lambda e: e.get("threat", True))
        if not live:
            return True
        return self.duel(lambda e: True, timeout=90.0, radius=radius + 8.0)

    def eat(self) -> bool:
        return self.p4.eat_best(foods=("hearty_stew", "berry_snack", "roseberries", "sweetroot", "berries"))

    def dodge(self, key: str):
        b = self.bot
        b.down(key)
        b.tap("CTRL")
        time.sleep(0.3)
        b.up(key)

    def duel(self, pred, timeout=240.0, radius=26.0, name="fight", flee_hp=40.0, elite=False) -> bool:
        """Fights the nearest matching enemy until none remain: dodge telegraphs (sweep/scrape: roll back; charge /
        narrow swing: roll sideways), punish recoveries and stuns, eat when low."""
        b = self.bot
        t0 = time.time()
        last_seen = time.time()
        rec = self.fights.setdefault(name, {"start": now(), "hp_min": 999.0, "eats": 0, "dodges": 0, "swings": 0,
                                           "states": {}, "deaths_before": 0})
        prev_state = {}
        while time.time() - t0 < timeout:
            s = self.st()
            if s.get("ui_stack"):
                self.p4.close_panels()
            if s.get("mode") != "playing":
                time.sleep(0.3)
                continue
            hp = float((s.get("player") or {}).get("hp") or 0)
            rec["hp_min"] = min(rec["hp_min"], hp)
            live = self.p4.live_enemies(radius, pred)
            if not live:
                if time.time() - last_seen > 3.0:
                    rec["seconds"] = round(time.time() - t0, 1)
                    return True
                time.sleep(0.25)
                continue
            last_seen = time.time()
            e = live[0]
            eid = e.get("name")
            st = str(e.get("state", ""))
            if prev_state.get(eid) != st:
                rec["states"][st] = rec["states"].get(st, 0) + 1
                prev_state[eid] = st
            d = float(e.get("dist", 99))
            if hp < flee_hp and st not in ("recover", "stunned"):
                # back off out of reach, then eat (the backpack panel pauses the game)
                self.face(e["pos"])
                self.dodge("S")
                if self.eat():
                    rec["eats"] += 1
                continue
            self.face(e["pos"], tol=8)
            if st in ("telegraph", "windup", "wind_up"):
                wide = elite and d < 5.5
                if "elder" in str(eid).lower():
                    key = "S" if d < 5.5 else "A"
                elif "drudge" in str(eid).lower():
                    key = "A" if d < 4.5 else None
                else:
                    key = "A" if d < 9.0 else None
                if wide:
                    key = "S"
                if key:
                    self.dodge(key)
                    rec["dodges"] += 1
                    if key == "S" and d < 3.0:
                        self.dodge("S")
                else:
                    time.sleep(0.1)
                continue
            if st in ("charge", "sweep", "scrape", "swing", "rooting", "attack"):
                if d < 3.0:
                    self.dodge("A")
                    rec["dodges"] += 1
                else:
                    time.sleep(0.1)
                continue
            if d > 2.2:
                b.hold("W", min(0.45, (d - 1.8) / 5.0 + 0.08))
            else:
                b.tap("LMB", 0.06)
                rec["swings"] += 1
                time.sleep(0.38)
        rec["seconds"] = round(time.time() - t0, 1)
        rec["timeout"] = True
        return False

    def face(self, target, tol=5.0):
        p = target if len(target) == 2 else (target[0], target[2])
        me = self.pos()
        return self.bot.turn_to_yaw(yaw_to((me[0], me[2]), p), tol=tol, timeout=1.0)

    # ------------------------------------------------------------------ UI helpers
    def buttons(self):
        return self.st().get("buttons") or []

    def click_btn(self, b):
        cx, cy = CH.C.button_center(b)
        self.bot.win.click(cx, cy)
        time.sleep(0.3)

    def slot_of(self, item: str, bag_only=True):
        for b in self.buttons():
            if str(b.get("text", "")).startswith("slot:bag:") and b.get("item") == item and not b.get("clipped"):
                return b
        return None

    def slot_index(self, idx: int):
        for b in self.buttons():
            if b.get("text") == f"slot:bag:{idx}":
                return b
        return None

    def open_inventory(self) -> bool:
        if "inventory" in (self.st().get("ui_stack") or []):
            return True
        self.bot.tap("TAB")
        return self.bot.wait_state(lambda s: "inventory" in (s.get("ui_stack") or []), 3.0) is not None

    def to_hotbar(self, item: str, idx: int) -> bool:
        """Click-to-pick the stack of `item`, click hotbar slot idx (swap), click the emptied slot (drop what is carried)."""
        hb = self.st().get("hotbar") or []
        if idx < len(hb) and hb[idx] == item:
            return True
        if not self.open_inventory():
            return False
        time.sleep(0.4)
        src = self.slot_of(item)
        dst = self.slot_index(idx)
        if src is None or dst is None:
            self.log(f"to_hotbar: slot missing (src {src}, dst {dst})")
            self.p4.close_panels()
            return False
        src_i = int(str(src["text"]).split(":")[-1])
        self.click_btn(src)
        time.sleep(0.3)
        self.click_btn(dst)
        time.sleep(0.3)
        back = self.slot_index(src_i)
        if back is not None:
            self.click_btn(back)
            time.sleep(0.3)
        self.p4.close_panels()
        time.sleep(0.3)
        hb = self.st().get("hotbar") or []
        ok = idx < len(hb) and hb[idx] == item
        self.log(f"to_hotbar {item} -> {idx}: {ok} hotbar={hb}")
        return ok

    def equip(self, item: str) -> bool:
        if not self.open_inventory():
            return False
        time.sleep(0.4)
        b = self.slot_of(item)
        if b is None:
            self.p4.close_panels()
            return False
        self.click_btn(b)
        time.sleep(0.3)
        ok = self.p4.click_button("Equip", exact=True, timeout=2.0)
        time.sleep(0.4)
        self.p4.close_panels()
        eq = self.st().get("equipment") or {}
        return ok and item in [str(v) for v in eq.values()]

    def save_game(self) -> bool:
        import playthrough
        pp = playthrough.Play(SimpleNamespace(bot=self.bot, shot=lambda label: self.shot(label)["path"]))
        return pp.pause_save()

    def read_save(self) -> dict:
        try:
            return json.loads((self.save_dir / "slot1.json").read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            self.log(f"read_save: {e}")
            return {}

    # ------------------------------------------------------------------ build mode aiming
    def cam(self):
        p = self.st().get("player") or {}
        return p.get("cam_pos"), p.get("cam_yaw"), p.get("cam_pitch"), p.get("pos")

    @staticmethod
    def ray_hit(cam_pos, yaw, pitch, ground_y):
        yr, pr = math.radians(yaw), math.radians(pitch)
        dx, dy, dz = -math.sin(yr) * math.cos(pr), math.sin(pr), -math.cos(yr) * math.cos(pr)
        if dy >= -0.02:
            return None
        t = (ground_y - cam_pos[1]) / dy
        return (cam_pos[0] + dx * t, cam_pos[2] + dz * t)

    def aim_at(self, point, tol=0.35, ground_y=None) -> tuple | None:
        """Turns / pitches the camera until its centre ray meets the ground at `point` (x, z). ground_y: the ground
        height there (sampled by standing on it; default Krystal's own feet - wrong on sloped lawns)."""
        hit = None
        for _ in range(10):
            cp, yaw, pitch, me = self.cam()
            if cp is None or yaw is None:
                time.sleep(0.2)
                continue
            want_yaw = yaw_to((cp[0], cp[2]), point)
            self.bot.turn_to_yaw(want_yaw, tol=1.0, timeout=1.5)
            cp, yaw, pitch, me = self.cam()
            gy = me[1] if ground_y is None else ground_y
            h = math.hypot(point[0] - cp[0], point[1] - cp[2])
            want_pitch = math.degrees(math.atan2(gy - cp[1], h))
            self.bot.look_pitch(want_pitch, tol=0.6, timeout=1.5)
            time.sleep(0.2)
            cp, yaw, pitch, me = self.cam()
            hit = self.ray_hit(cp, yaw, pitch, me[1] if ground_y is None else ground_y)
            if hit and math.hypot(hit[0] - point[0], hit[1] - point[1]) <= tol:
                return hit
        return hit

    def build_state(self) -> dict:
        return self.st().get("build") or {}

    def place_aimed(self, item: str, stand, aim, label: str, sample_ground: bool = False) -> dict:
        """Walk to `stand`, aim the camera ray at `aim`, enter build mode, select `item`, place with LMB if valid."""
        rep = {"item": item, "stand": stand, "aim": aim}
        n0 = self.inv(item)
        gy = None
        if sample_ground:
            # stand on the aim point first: Krystal's feet there = the ground height the camera ray will meet
            if self.walk_nav(aim, tol=0.5, fight=False, sprint=False):
                time.sleep(0.4)
                gy = float(self.pos()[1])
            rep["ground_y"] = gy
        self.walk_nav(stand, tol=0.6, fight=False, sprint=False)
        hit = self.aim_at(aim, ground_y=gy)
        rep["hit"] = hit
        self.bot.tap("B")
        if not self.bot.wait_state(lambda s: (s.get("build") or {}).get("active"), 3.0):
            rep["error"] = "build mode did not start"
            return rep
        for _ in range(24):
            if self.build_state().get("item") == item:
                break
            self.bot.wheel(-120)
            time.sleep(0.25)
        if self.build_state().get("item") != item:
            rep["error"] = f"could not select {item} (selected {self.build_state().get('item')})"
            self.bot.tap("B")
            return rep
        time.sleep(0.5)
        bs = self.build_state()
        rep["valid_before"] = bs.get("valid")
        rep["reason_before"] = bs.get("reason")
        placed = False
        if bs.get("valid"):
            self.bot.tap("LMB", 0.06)
            placed = self.bot.wait_state(lambda s: int((s.get("inv") or {}).get(item, 0)) < n0, 2.5) is not None
        rep["placed"] = placed
        rep["reason_after"] = self.build_state().get("reason")
        if self.build_state().get("active"):
            self.bot.tap("B")
            time.sleep(0.5)
        self.log(f"place {label}: {rep}")
        return rep

    # ================================================================== steps
    def step_start(self):
        s = self.st()
        rec = self.observe("c1_start", {"optional_all": s.get("optional"), "inv": s.get("inv"), "keys": s.get("keys"),
                                        "equipment": s.get("equipment"), "day": s.get("day"), "hour": s.get("hour")})
        self.inv0 = self.inv_all()
        for g in GOALS_CH1:
            if g in ((s.get("optional") or {}).get("done") or []):
                self.cov_bug(f"{g} already done on a save that never did it", "major",
                             "Continue the real Chapter-One-complete save (fixture 16)", "MP 7: 'Do not mark everything complete just because Chapter One is complete'",
                             f"optional.done = {(s.get('optional') or {}).get('done')}", [str(self.out / "cov_result.json")])
        return True

    def step_harvest_sweetroot(self):
        p1 = self.p1
        plot = p1.nearest(lambda n: str(n.get("text", "")).startswith("Harvest") and math.hypot(n["pos"][0] - CROP_PLOT[0], n["pos"][2] - CROP_PLOT[1]) < 3, 60)
        if plot is None:
            self.walk_nav((CROP_PLOT[0] + 1.8, CROP_PLOT[1] - 1.5), tol=1.0)
            plot = p1.nearest(lambda n: math.hypot(n["pos"][0] - CROP_PLOT[0], n["pos"][2] - CROP_PLOT[1]) < 3
                              and n.get("g") in ("interactable", "crafting_station"), 20)
            self.log(f"crop plot entry: {plot}")
            if plot is None or not str(plot.get("text", "")).startswith("Harvest"):
                self.cov_note(f"the fixture's sweetroot plot is not ripe / not found: {plot}")
                return True
        n0 = self.inv("sweetroot")
        ok = p1.press_interact_on(plot, ["Harvest"], lambda: self.inv("sweetroot") > n0, stop=1.6)
        self.log(f"sweetroot harvest ok={ok} sweetroot={self.inv('sweetroot')}")
        return True

    def step_meadow(self):
        t0 = self.gt()
        inv_before = self.inv_all()
        self.walk_path(PATHS["meadow"], tol=2.0)
        self.walk_nav((-12.0, 60.0), tol=1.5)
        self.walk_nav((-15.2, 61.0), tol=1.0)
        got = 0
        for tries in range(4):
            e = self.p1.nearest(lambda n: n.get("g") == "harvestable" and "sunflax" in (str(n.get("label", "")) + str(n.get("id", ""))).lower()
                                and "regrow" not in str(n.get("text", "")).lower(), 20)
            if e is None:
                break
            n0 = self.inv("sunflax")
            ok = self.p1.press_interact_on(e, ["Sunflax", "Gather"], lambda: self.inv("sunflax") > n0, tries=2, stop=1.3)
            if not ok:
                self.bot.tap("LMB", 0.06)
                time.sleep(0.8)
            if self.inv("sunflax") > n0:
                got += 1
            if got >= 2 and "c1x_found_new_crops" in self.flags():
                break
        # roseberries (food + the other wild crop)
        self.walk_nav((-2.0, 67.5), tol=1.2)
        for tries in range(2):
            e = self.p1.nearest(lambda n: n.get("g") == "harvestable" and "roseberr" in (str(n.get("label", "")) + str(n.get("id", ""))).lower()
                                and "regrow" not in str(n.get("text", "")).lower(), 15)
            if e is None:
                break
            n0 = self.inv("roseberries")
            self.p1.press_interact_on(e, ["Roseberr", "Pick"], lambda: self.inv("roseberries") > n0, tries=2, stop=1.3)
        time.sleep(1.0)
        msgs = [m.get("text") for m in self.msgs_since(t0)]
        rec = self.goal_snapshot("opt_gardeners_afternoon", "wild crops found", inv_before)
        rec["found_flag"] = "c1x_found_new_crops" in self.flags()
        rec["msgs"] = msgs
        self.observe("after_meadow", {"msgs": msgs})
        if not rec["found_flag"]:
            raise Stop(f"c1x_found_new_crops not set after harvesting the wild patch (sunflax {self.inv('sunflax')})")
        return True

    def step_plant(self):
        self.go_home()
        seed = "sunflax_seeds" if self.inv("sunflax_seeds") > 0 else ("roseberry_seeds" if self.inv("roseberry_seeds") > 0 else "")
        if not seed:
            raise Stop("no sunflax / roseberry seeds after the meadow")
        self.to_hotbar(seed, 5)
        hb = self.st().get("hotbar") or []
        if seed in hb:
            self.bot.tap(str(hb.index(seed) + 1))
            time.sleep(0.3)
        self.walk_nav((CROP_PLOT[0] + 1.8, CROP_PLOT[1] - 1.8), tol=1.0)
        plot = self.p1.nearest(lambda n: math.hypot(n["pos"][0] - CROP_PLOT[0], n["pos"][2] - CROP_PLOT[1]) < 3
                               and str(n.get("text", "")).startswith("Plant"), 20)
        if plot is None:
            raise Stop(f"no 'Plant' prompt at the crop plot: {[n for n in self.p1.nearby(maxd=8)]}"[:400])
        self.log(f"plot prompt: {plot.get('text')}")
        n0 = self.inv(seed)
        ok = self.p1.press_interact_on(plot, ["Plant"], lambda: self.inv(seed) < n0, stop=1.6)
        time.sleep(1.0)
        plot2 = self.p1.nearest(lambda n: math.hypot(n["pos"][0] - CROP_PLOT[0], n["pos"][2] - CROP_PLOT[1]) < 3 and n.get("g") == "interactable", 20)
        self.plant_report = {"seed": seed, "ok": ok, "prompt_before": plot.get("text"), "prompt_after": (plot2 or {}).get("text"),
                             "day": self.st().get("day"), "hour": self.st().get("hour")}
        self.log(f"planted: {self.plant_report}")
        return ok

    def step_sleep_harvest(self):
        self.go_home()
        bed = self.p1.nearest(lambda n: "sleep until morning" in str(n.get("text", "")).lower(), 70)
        rep = {"hour_before": self.st().get("hour"), "day_before": self.st().get("day"), "hp_before": self.hp()}
        if bed is not None:
            t0 = self.gt()
            self.p1.press_interact_on(bed, ["Sleep until morning"], lambda: any("Slept" in str(m.get("text", "")) for m in self.msgs_since(t0)), stop=1.5)
            self.wait_playing(SURFACE, 30)
            time.sleep(1.5)
            self.bot.calibrate_look()
        rep.update({"hour_after": self.st().get("hour"), "day_after": self.st().get("day"), "hp_after": self.hp()})
        inv_before = self.inv_all()
        self.walk_nav((CROP_PLOT[0] + 1.8, CROP_PLOT[1] - 1.8), tol=1.0)
        plot = self.p1.nearest(lambda n: math.hypot(n["pos"][0] - CROP_PLOT[0], n["pos"][2] - CROP_PLOT[1]) < 3 and n.get("g") == "interactable", 20)
        rep["plot_prompt"] = (plot or {}).get("text")
        waited = 0
        while plot is not None and not str(plot.get("text", "")).startswith("Harvest") and waited < 240:
            time.sleep(10)
            waited += 10
            plot = self.p1.nearest(lambda n: math.hypot(n["pos"][0] - CROP_PLOT[0], n["pos"][2] - CROP_PLOT[1]) < 3 and n.get("g") == "interactable", 20)
        rep["waited_s"] = waited
        if plot is None or not str(plot.get("text", "")).startswith("Harvest"):
            self.sleep_report = rep
            raise Stop(f"crop not ripe: {plot}")
        t0 = self.gt()
        ok = self.p1.press_interact_on(plot, ["Harvest"], lambda: "c1x_grew_new_crop" in self.flags(), stop=1.6)
        time.sleep(2.0)
        rep["harvest_ok"] = ok
        rep["msgs"] = [m.get("text") for m in self.msgs_since(t0)]
        self.sleep_report = rep
        g = self.goal_snapshot("opt_gardeners_afternoon", "grown crop harvested", inv_before)
        self.observe("after_sunflax_harvest", {"sleep": rep})
        if ok and not g["done"]:
            self.cov_bug("A Gardener's Afternoon not completed after harvesting a home-grown sunflax", "major",
                         "fixture 16 -> harvest wild sunflax in the Sunny Meadow -> plant the seed at home -> sleep -> harvest",
                         "opt_gardeners_afternoon done, reward 3 sunflax + 3 roseberry seeds once",
                         f"flags c1x_found_new_crops={'c1x_found_new_crops' in self.flags()} c1x_grew_new_crop={'c1x_grew_new_crop' in self.flags()}, optional.done={self.opt_done()}",
                         [str(self.out / "cov_result.json")])
        return ok

    def step_tailor(self):
        if "c1x_tailor_cache" in self.flags():
            return True
        inv_before = self.inv_all()
        self.walk_path(PATHS["old_oak"], tol=2.0)
        self.walk_nav(TAILOR_STAND, tol=1.0)
        e = self.p1.nearest(lambda n: "tailor" in str(n.get("text", "")).lower(), 20)
        if e is None:
            raise Stop(f"Tailor's Cache not found near {self.pos()}")
        ok = self.p1.press_interact_on(e, ["Tailor's Cache"], lambda: "c1x_tailor_cache" in self.flags(), stop=1.4)
        time.sleep(2.0)
        self.goal_snapshot("opt_tailors_cache", "cache opened", inv_before)
        return ok

    def step_bramble_found(self):
        self.walk_path(PATHS["old_oak"], tol=2.0)
        self.walk_path(PATHS["thicket"], tol=2.0)
        ok = self.walk_nav((-73.5, -37.0), tol=1.5)
        self.walk_nav((-76.0, -36.0), tol=1.5)
        found = self.bot.wait_state(lambda s: "c1x_bramblewatch_found" in (s.get("flags") or []), 5.0) is not None
        self.observe("bramblewatch_edge", {"found": found, "zone": self.st().get("zone")})
        return found

    def step_elder(self):
        if "c1x_elder_defeated" in self.flags():
            return True
        inv_before = self.inv_all()
        self.p4.eat_best() if self.hp() < 80 else None
        t0 = self.gt()
        elder = lambda e: "elder" in str(e.get("name", "")).lower() or float(e.get("hp", 0) or 0) > 150  # noqa: E731
        ent = self.p1.nearest(lambda n: n.get("g") == "enemy" and elder(n), 60)
        self.log(f"elder entity: {ent}")
        if ent is None:
            self.walk_nav((ELDER_C[0] + 6.0, ELDER_C[1]), tol=2.0, fight=False)
            ent = self.p1.nearest(lambda n: n.get("g") == "enemy" and elder(n), 60)
        if ent is None:
            raise Stop(f"no Knotted Elder near Bramblewatch (at {self.pos()})")
        self.fights["elder"] = {"start": now(), "hp_min": 999.0, "eats": 0, "dodges": 0, "swings": 0, "states": {},
                                "entity": ent}
        deaths0 = self.death_count()
        ok = self.duel(elder, timeout=420.0, radius=40.0, name="elder", flee_hp=45.0, elite=True)
        time.sleep(2.5)
        self.fights["elder"]["deaths"] = self.death_count() - deaths0
        self.fights["elder"]["msgs"] = [m.get("text") for m in self.msgs_since(t0)][-12:]
        g = self.goal_snapshot("opt_bramblewatch", "Knotted Elder", inv_before)
        self.observe("after_elder", {"fight": self.fights["elder"]})
        return "c1x_elder_defeated" in self.flags()

    def death_count(self) -> int:
        return sum(1 for e in self.monitor.events if e.get("k") == "msg_event" and "died" in str(e.get("text")))

    def step_bramblebacks(self):
        inv_before = self.inv_all()
        bb = lambda e: "brambleback" in str(e.get("name", "")).lower()  # noqa: E731
        self.walk_nav((-80.0, -52.0), tol=2.0)
        self.walk_nav((BRAMBLEBACK_C[0] - 2.0, BRAMBLEBACK_C[1] + 9.0), tol=2.0, fight=False)
        seen = self.p1.nearby(lambda n: n.get("g") == "enemy" and bb(n), 40)
        self.log(f"bramblebacks seen: {[(n.get('name'), n.get('hp'), n.get('state'), n.get('dist')) for n in seen]}")
        if not seen:
            self.walk_nav((BRAMBLEBACK_C[0], BRAMBLEBACK_C[1] + 4.0), tol=2.0, fight=False)
            seen = self.p1.nearby(lambda n: n.get("g") == "enemy" and bb(n), 40)
        self.fights["bramblebacks"] = {"start": now(), "hp_min": 999.0, "eats": 0, "dodges": 0, "swings": 0, "states": {},
                                       "seen": len(seen)}
        ok = self.duel(bb, timeout=300.0, radius=30.0, name="bramblebacks", flee_hp=45.0)
        time.sleep(1.5)
        left = self.p1.nearby(lambda n: n.get("g") == "enemy" and bb(n) and float(n.get("hp", 0) or 0) > 0, 40)
        self.fights["bramblebacks"]["left"] = len(left)
        self.fights["bramblebacks"]["cleared_flag"] = "spawner_cleared_c1x_sp_bramblebacks" in self.flags()
        self.goal_snapshot("opt_bramblewatch", "Brambleback group", inv_before)
        return ok and not left

    def step_wood(self, want=20):
        import s2_lib
        pl = s2_lib.Play(self.bot, self.out / "wood")
        guard = 0
        while self.inv("wood") < want and guard < 8:
            guard += 1
            self.obst_update()
            try:
                pl.harvest_tool(["tree", "oak", "birch", "pine", "maple", "willow", "fir"], "wood", want, maxd=40.0,
                                prefer_pos=(self.pos()[0], self.pos()[2]))
            except Exception as e:  # noqa: BLE001
                self.log(f"wood: {e}")
                self.walk_nav((self.pos()[0] + 8.0, self.pos()[2] + 8.0), tol=2.0)
        self.log(f"wood now {self.inv('wood')}")
        return self.inv("wood") >= want - 4

    def craft(self, name: str, item: str, times=1, tab="Workbench") -> bool:
        ok = self.p1.craft(name, times=times, station_tab=tab, item=item)
        self.p1.close_panels()
        return ok

    def step_build(self):
        rep = self.build_report
        self.go_home()
        # 1) furnace
        if self.inv("furnace") < 1 and not self.structures("furnace"):
            rep["craft_furnace"] = self.craft("Furnace", "furnace")
        for aim in FURNACE_AIMS:
            if self.structures("furnace") or self.inv("furnace") < 1:
                break
            stand = (aim[0] + 0.5, aim[1] + 4.5)
            r = self.place_aimed("furnace", stand, aim, "furnace")
            rep.setdefault("furnace_tries", []).append(r)
        # 2) stairs, post, upper floor
        for item, name in (("wood_stairs", "Wooden Stairs"), ("porch_post", "Porch Post"), ("upper_floor", "Upper Floor")):
            if self.inv(item) < 1 and not self.structures(item):
                rep[f"craft_{item}"] = self.craft(name, item)
        placed_ok = False
        for dx, dz in BUILD_SITES:
            if self.structures("wood_stairs") and self.structures("upper_floor"):
                placed_ok = True
                break
            post_aim = (-9.5 + dx, 16.5 + dz)
            tile_aim = (-9.0 + dx, 17.0 + dz)
            stair_aim = (-9.0 + dx, 20.0 + dz)
            site = {"offset": (dx, dz)}
            if not self.structures("porch_post"):
                site["post"] = self.place_aimed("porch_post", (-9.0 + dx, 21.0 + dz), post_aim, "porch_post")
            if not self.structures("upper_floor"):
                site["floor"] = self.place_aimed("upper_floor", (-9.0 + dx, 21.0 + dz), tile_aim, "upper_floor")
            if not self.structures("wood_stairs"):
                site["stairs"] = self.place_aimed("wood_stairs", (-9.0 + dx, 25.5 + dz), stair_aim, "wood_stairs")
            rep.setdefault("sites", []).append(site)
            if not (self.structures("wood_stairs") and self.structures("upper_floor")):
                # take back what did not form a working set before trying the next site (undo = exact refund)
                self.log(f"site {dx},{dz} incomplete: {site}")
        self.save_game()
        sv = self.read_save()
        recs = {u: r for u, r in ((sv.get("state") or {}).get("structures") or {}).items()
                if r.get("id") in ("wood_stairs", "upper_floor", "porch_post", "furnace")}
        rep["saved_structures"] = recs
        rep["flag_upstairs"] = "c1x_upstairs_reachable" in self.flags()
        return bool(self.structures("furnace")) and bool(self.structures("wood_stairs")) and bool(self.structures("upper_floor"))

    def structures(self, sid: str) -> list:
        """Structure uids of a kind, from the telemetry-independent save the game last wrote + this run's placements."""
        placed = getattr(self, "_placed", {})
        for tries in self.build_report.get("sites", []) + [{"f": t} for t in self.build_report.get("furnace_tries", [])]:
            for v in tries.values():
                if isinstance(v, dict) and v.get("placed"):
                    placed[v["item"]] = True
        self._placed = placed
        sv = self.read_save()
        uids = [u for u, r in ((sv.get("state") or {}).get("structures") or {}).items() if r.get("id") == sid]
        if placed.get(sid):
            uids = uids or ["(placed this session)"]
        return uids

    def step_walk_up(self):
        rep = self.build_report
        recs = rep.get("saved_structures") or {}
        stairs = [r for r in recs.values() if r.get("id") == "wood_stairs"]
        floor = [r for r in recs.values() if r.get("id") == "upper_floor"]
        if not stairs or not floor:
            raise Stop(f"no stairs / floor in the save: {recs}")
        sp = stairs[0]["pos"]
        fp = floor[0]["pos"]
        foot = (sp[0], sp[2] + 3.4)
        self.walk_nav(foot, tol=0.6, fight=False, sprint=False)
        self.face((fp[0], fp[2]))
        ys = []
        for pt in ((sp[0], sp[2] + 1.0), (sp[0], sp[2] - 1.0), (fp[0], fp[2])):
            self.walk_leg(pt, tol=0.5, timeout=8.0, sprint=False)
            ys.append(round(float(self.pos()[1]), 2))
        top = self.pos()
        rep["walk_up"] = {"stairs_pos": sp, "floor_pos": fp, "ys": ys, "top": top,
                          "on_floor": abs(top[0] - fp[0]) < 1.3 and abs(top[2] - fp[2]) < 1.3 and top[1] > fp[1] - 0.3}
        self.log(f"walk up: {rep['walk_up']}")
        # back down
        self.walk_leg((sp[0], sp[2] + 3.2), tol=0.6, timeout=10.0, sprint=False)
        rep["after_down"] = self.pos()
        inv_before = getattr(self, "inv_before_build", self.inv0)
        self.goal_snapshot("opt_upstairs", "stairs + upper floor", inv_before)
        return rep["walk_up"]["on_floor"]

    def step_landing_fix(self):
        """The first try put the stairs one tile south of the upper floor (the lawn rises ~0.5 m toward the north,
        so the camera ray met the ground earlier than the bot computed). A player would simply lay one more upper
        floor tile on the stairs' landing: it rests on the neighbouring tile (placement.gd: a neighbouring upper tile
        that is itself held up). Reads the placed pieces from the game's own save."""
        rep = self.build_report
        self.go_home()
        self.save_game()
        recs = {u: r for u, r in ((self.read_save().get("state") or {}).get("structures") or {}).items()
                if r.get("id") in ("wood_stairs", "upper_floor", "porch_post")}
        rep["before_fix"] = recs
        stairs = [r for r in recs.values() if r.get("id") == "wood_stairs"]
        floors = [r for r in recs.values() if r.get("id") == "upper_floor"]
        if not stairs:
            raise Stop(f"no stairs in the save: {recs}")
        sp = stairs[0]["pos"]
        rot = int(round(float(stairs[0].get("rot", 0)))) % 360
        if rot != 0:
            raise Stop(f"stairs rot {rot} (this fix handles rot 0 only)")
        x0, z0 = int(round(sp[0] - 1.0)), int(round(sp[2] - 2.0))
        landing = (x0, z0 - 2)
        have = any(int(math.floor(float(f["pos"][0]) / 2.0)) * 2 == landing[0] and int(math.floor(float(f["pos"][2]) / 2.0)) * 2 == landing[1]
                   for f in floors)
        rep["landing_tile"] = landing
        rep["landing_had_floor"] = have
        if not have:
            tries = 0
            while self.inv("upper_floor") < 1 and tries < 3:
                tries += 1
                if self.inv("wood") < 3:
                    self.step_wood(want=6)
                    self.go_home()
                rep.setdefault("craft_upper_floor_2", []).append(
                    {"ok": self.craft("Upper Floor", "upper_floor"), "inv_after": {k: self.inv(k) for k in ("wood", "upper_floor", "wood_railing")}})
            aim = (landing[0] + 1.0, landing[1] + 1.0)
            r = self.place_aimed("upper_floor", (aim[0], aim[1] - 3.2), aim, "upper_floor (landing)", sample_ground=False)
            rep["landing_place"] = r
            if not r.get("placed"):
                # from the north side instead (looking south)
                r2 = self.place_aimed("upper_floor", (aim[0], aim[1] - 4.5), aim, "upper_floor (landing, retry)")
                rep["landing_place_retry"] = r2
        self.save_game()
        recs2 = {u: r for u, r in ((self.read_save().get("state") or {}).get("structures") or {}).items()
                 if r.get("id") in ("wood_stairs", "upper_floor", "porch_post")}
        rep["saved_structures"] = recs2
        rep["flag_upstairs_after_fix"] = "c1x_upstairs_reachable" in self.flags()
        return rep["flag_upstairs_after_fix"]

    def is_furnace(self, n) -> bool:
        """The furnace's prompt: 'Use Furnace' / 'Furnace: Copper Bar 40% (2 queued)' / 'Collect 2 Copper Bars' (no
        'furnace' word!), so it is also matched by the node name remembered from the first sighting."""
        if n.get("g") not in ("crafting_station", "interactable"):
            return False
        t = str(n.get("text", "")).lower()
        if getattr(self, "furnace_name", None) and n.get("name") == self.furnace_name:
            return True
        return "furnace" in t or (t.startswith("collect") and "bar" in t)

    def find_furnace(self, maxd=60):
        e = self.p1.nearest(self.is_furnace, maxd)
        if e is not None and "furnace" in str(e.get("text", "")).lower():
            self.furnace_name = e.get("name")
        return e

    def open_furnace(self) -> bool:
        e = self.find_furnace()
        if e is None:
            self.go_home()
            fp = getattr(self, "furnace_pos", None)
            if not fp:
                for r in ((self.read_save().get("state") or {}).get("structures") or {}).values():
                    if r.get("id") == "furnace" and r.get("area", "surface") == "surface":
                        fp = r.get("pos")
                        self.furnace_pos = fp
            if fp:
                self.walk_nav((fp[0] + 2.5, fp[2] + 2.5), tol=1.2)
            e = self.find_furnace()
        if e is None:
            return False
        self.furnace_entity = e
        self.furnace_pos = e.get("pos")
        return self.p1.press_interact_on(e, ["Furnace", "furnace", "Smelt", "Collect", "bar"],
                                         lambda: "crafting" in (self.st().get("ui_stack") or []), stop=2.0)

    def furnace_queue(self, n: int) -> dict:
        rep = {"want": n, "ore_before": self.inv("copper_ore"), "bars_before": self.inv("copper_bar")}
        if not self.open_furnace():
            rep["error"] = "furnace panel did not open"
            return rep
        time.sleep(0.6)
        rep["buttons_open"] = [b.get("text") for b in self.buttons()][:40]
        self.p1.click_scrolled("Copper Bar")
        time.sleep(0.4)
        added = 0
        for _ in range(n):
            if self.p4.click_button("Add to queue", exact=True, timeout=2.0):
                added += 1
                time.sleep(0.4)
        rep["added"] = added
        rep["ore_after_queue"] = self.inv("copper_ore")
        rep["buttons_after"] = [b.get("text") for b in self.buttons()][:40]
        self.p1.close_panels()
        rep["queued_at_play_s"] = self.gt()
        return rep

    def furnace_collect(self) -> dict:
        b0 = self.inv("copper_bar")
        ok = self.open_furnace()
        time.sleep(0.8)
        if "crafting" in (self.st().get("ui_stack") or []):
            self.p4.click_button("Collect", exact=True, timeout=1.5)
            time.sleep(0.4)
        btns = [b.get("text") for b in self.buttons()][:40]
        self.p1.close_panels()
        return {"opened": ok, "bars_before": b0, "bars_after": self.inv("copper_bar"), "buttons": btns}

    def step_first_bar(self):
        self.furnace_report["first"] = self.furnace_queue(1)
        return self.furnace_report["first"].get("added", 0) >= 1

    def step_armor(self):
        inv_before = self.inv_all()
        time.sleep(max(0.0, 22.0 - 0.0))
        col = self.furnace_collect()
        self.furnace_report["first_collect"] = col
        if self.inv("copper_bar") < 1:
            time.sleep(15.0)
            self.furnace_report["first_collect_retry"] = self.furnace_collect()
        if self.inv("copperwood_hood") < 1:
            self.craft("Copperwood Hood", "copperwood_hood")
        ok = self.equip("copperwood_hood")
        time.sleep(1.5)
        self.goal_snapshot("opt_copper_courage", "furnace placed + hood worn", inv_before)
        self.observe("after_armor", {"equipment": self.st().get("equipment")})
        return ok

    def step_annex(self):
        rep = {}
        self.annex_report = rep
        inv_before = self.inv_all()
        if self.st().get("area") == SURFACE:
            self.go_home()
            self.walk_path(PATHS["mine"], tol=2.0)
            self.walk_nav(TOBIN_DOOR_SPAWN, tol=1.5)
            door = self.p1.nearest(lambda n: str(n.get("name", "")) == "TobinDoor" or "tobin" in str(n.get("text", "")).lower(), 30)
            rep["door"] = door
            if door is None:
                raise Stop(f"no Tobin's side door near {self.pos()} (expected {TOBIN_DOOR})")
            words = [str(door.get("text"))] if door.get("text") else ["door"]
            self.p1.press_interact_on(door, words, lambda: self.st().get("mode") == "loading" or self.st().get("area") == "tobin_annex"
                                      or bool(self.st().get("ui_stack")), stop=1.6)
            for _ in range(3):
                if self.st().get("ui_stack"):
                    rep.setdefault("popup_buttons", []).append([b.get("text") for b in self.buttons()][:12])
                    for lbl in ("Go in", "Enter", "Continue", "Yes", "OK"):
                        if self.p4.click_button(lbl, exact=False, timeout=1.0):
                            break
                time.sleep(1.0)
            if not self.bot.wait_state(lambda s: s.get("area") == "tobin_annex" and s.get("mode") == "playing", 60):
                raise Stop(f"did not arrive in the annex (area {self.st().get('area')}, ui {self.st().get('ui_stack')})")
            time.sleep(1.5)
            self.bot.calibrate_look()
        rep["entered_flag"] = "c1x_annex_entered" in self.flags()
        p4 = self.p4
        # the Hollow Drudge in the lockers
        p4.route([(x, z) for (x, _, z) in ANNEX_TO_LOCKERS], tol=1.0, sprint=False)
        dr = lambda e: "drudge" in str(e.get("name", "")).lower()  # noqa: E731
        ent = self.p1.nearest(lambda n: n.get("g") == "enemy" and dr(n), 30)
        rep["drudge_entity"] = ent
        self.fights["drudge"] = {"start": now(), "hp_min": 999.0, "eats": 0, "dodges": 0, "swings": 0, "states": {}}
        if ent is not None:
            self.duel(dr, timeout=180.0, radius=25.0, name="drudge", flee_hp=40.0)
        time.sleep(1.5)
        rep["drudge_flag"] = "c1x_drudge_defeated" in self.flags()
        # Tobin's letter (locker nine)
        p4.goto((ANNEX_LETTER_STAND[0], ANNEX_LETTER_STAND[2]), tol=0.6, sprint=False)
        rep["letter"] = p4.interact_with(ANNEX_LETTER, ["Open locker nine", "Read Tobin's letter"],
                                         check=lambda: "c1x_tobin_letter_found" in self.flags(), stop=1.0)
        time.sleep(1.5)
        p4.close_panels()
        # down to the sump: the service note by the dropped lamp
        p4.route([(x, z) for (x, _, z) in ANNEX_DOWN], tol=0.9, sprint=False)
        p4.goto((ANNEX_NOTE_STAND[0], ANNEX_NOTE_STAND[2]), tol=0.6, sprint=False)
        rep["note"] = p4.interact_with(ANNEX_NOTE, ["Read the note", "Read Tobin's note"],
                                       check=lambda: "c1x_tobin_shift" in self.flags(), stop=1.2)
        time.sleep(2.0)
        p4.close_panels()
        rep["lamp_after_note"] = {"miner_lamp": self.inv("miner_lamp")}
        # the scrawled mark (clue)
        p4.goto((ANNEX_MARK_STAND[0], ANNEX_MARK_STAND[2]), tol=0.6, sprint=False)
        rep["mark"] = p4.interact_with(ANNEX_MARK, ["Look at the scratched mark"],
                                       check=lambda: "c1x_lantern_mark_seen" in self.flags(), stop=1.2, pitch=0.0)
        time.sleep(1.5)
        p4.close_panels()
        # the hatch: slide the bolt, then climb up
        p4.goto((ANNEX_LADDER_STAND[0], ANNEX_LADDER_STAND[2]), tol=0.6, sprint=False)
        rep["bolt"] = p4.interact_with((ANNEX_LADDER[0], -0.5, ANNEX_LADDER[2]), ["Slide back the rusted bolt"],
                                       check=lambda: "ta_hatch_open" in self.flags(), stop=1.0, pitch=35.0)
        time.sleep(2.0)
        rep["climb"] = p4.interact_with((ANNEX_LADDER[0], -0.5, ANNEX_LADDER[2]), ["Climb up to the mine mouth"],
                                        check=lambda: self.st().get("mode") == "loading" or self.st().get("area") == SURFACE,
                                        stop=1.0, pitch=35.0)
        arrived = self.bot.wait_state(lambda s: s.get("area") == SURFACE and s.get("mode") == "playing", 60) is not None
        time.sleep(1.5)
        rep["surface_after_hatch"] = {"arrived": arrived, "pos": self.pos()}
        if arrived:
            self.bot.calibrate_look()
            rep["hatch_distance_m"] = round(math.hypot(self.pos()[0] - TOBIN_HATCH[0], self.pos()[2] - TOBIN_HATCH[1]), 1)
            hatch = self.p1.nearest(lambda n: "hatch" in str(n.get("text", "")).lower(), 15)
            rep["surface_hatch_prompt"] = (hatch or {}).get("text")
        self.goal_snapshot("opt_tobins_shift", "annex", inv_before)
        self.observe("after_annex", {"annex": {k: v for k, v in rep.items() if k != "drudge_entity"}})
        return "opt_tobins_shift" in self.opt_done()

    def step_copper(self):
        """Mines the Pebble Quarry copper veins (renewable, 1440 min) if they are back, for a multi-bar queue."""
        want = 6
        if self.inv("copper_ore") >= want:
            return True
        import s2_lib
        pl = s2_lib.Play(self.bot, self.out / "copper")
        self.walk_path(PATHS["quarry"], tol=2.0)
        self.walk_nav((64.0, -12.0), tol=2.0)
        veins = self.p1.nearby(lambda n: n.get("g") == "harvestable" and "copper" in str(n.get("label", "")).lower(), 40)
        self.copper_report = {"veins_seen": [(v.get("id"), v.get("text"), v.get("pos")) for v in veins],
                              "ore_before": self.inv("copper_ore"), "hour": self.st().get("hour"), "day": self.st().get("day")}
        try:
            pl.harvest_tool(["copper"], "copper_ore", want, maxd=40.0, prefer_pos=(64.0, -12.0))
        except Exception as e:  # noqa: BLE001
            self.log(f"copper: {e}")
        self.copper_report["ore_after"] = self.inv("copper_ore")
        return self.inv("copper_ore") >= 4

    def step_smelt(self):
        self.go_home()
        n = min(4, self.inv("copper_ore") // 2)
        rep = {"ore": self.inv("copper_ore"), "jobs": n}
        self.furnace_report["queue"] = rep
        if n < 2:
            self.cov_note(f"only {self.inv('copper_ore')} copper ore: queue of {n}")
        if n < 1:
            return False
        bars0 = self.inv("copper_bar")
        rep["queue"] = self.furnace_queue(n)
        added = rep["queue"].get("added", 0)
        # wait while playing (menus pause the furnace): 20 s per bar + margin, standing by the furnace
        fp = getattr(self, "furnace_pos", None)
        if fp:
            self.walk_nav((fp[0] + 2.5, fp[2] + 2.5), tol=1.2, fight=False)
        t_end = time.time() + 20.0 * added + 12.0
        mid = None
        while time.time() < t_end:
            time.sleep(2.0)
            if mid is None and time.time() > t_end - 20.0 * added / 2:
                mid = self.find_furnace()
                rep["prompt_mid"] = (mid or {}).get("text")
        rep["prompt_done"] = (self.find_furnace() or {}).get("text")
        rep["collect"] = self.furnace_collect()
        rep["bars_gained"] = self.inv("copper_bar") - bars0
        time.sleep(1.0)
        rep["collect_again"] = self.furnace_collect()
        rep["bars_after_second_collect"] = self.inv("copper_bar")
        if rep["bars_gained"] != added:
            self.cov_bug("Furnace queue did not yield exactly one bar per queued job", "major",
                         f"fixture 16 -> furnace at the Haven -> queue {added} copper bars -> wait {20 * added + 12} s playing -> interact / Collect",
                         f"{added} bars, collected once", f"gained {rep['bars_gained']} (second collect: {rep['collect_again']})",
                         [str(self.out / "cov_result.json")])
        if rep["bars_after_second_collect"] != bars0 + rep["bars_gained"]:
            self.cov_bug("Furnace paid out again on a second collect", "major", "queue bars, collect, collect again",
                         "the second collect gives nothing", f"{rep}", [str(self.out / "cov_result.json")])
        return added >= 1 and rep["bars_gained"] == added      # a queue that never opened is a failure, not a pass

    def step_reload(self):
        saved = self.save_game()
        before = self.observe("before_quit")
        s = self.st()
        inv_b, keys_b, eq_b = dict(s.get("inv") or {}), dict(s.get("keys") or {}), dict(s.get("equipment") or {})
        opt_b = sorted(self.opt_done())
        sv_b = self.read_save()
        self.bot.tap("ESC")
        quit_how = "killed"
        if self.bot.wait_state(lambda st: "pause" in (st.get("ui_stack") or []), 3.0) and \
                self.bot.click_button("Quit Game", exact=True, timeout=3.0):
            if self.bot.click_button("Save & Quit", exact=True, timeout=4.0):
                quit_how = "pause menu: Quit Game -> Save & Quit"
        exited = self.game.wait_exit(20.0)
        g = self.relaunch()
        if not g.bot.wait_state(lambda st: st.get("mode") == "title" and any(b.get("text") == "Continue" for b in st.get("buttons", [])), 120):
            raise Stop("no title after relaunch")
        g.bot.click_button("Continue", exact=True, timeout=10)
        if not self.wait_playing(None, 120):
            raise Stop("Continue never reached gameplay")
        time.sleep(3.0)
        self.p1, self.p4 = self.players("reload")
        after = self.observe("after_continue")
        s = self.st()
        inv_a, keys_a, eq_a = dict(s.get("inv") or {}), dict(s.get("keys") or {}), dict(s.get("equipment") or {})
        opt_a = sorted(self.opt_done())
        diff = {k: [inv_b.get(k), inv_a.get(k)] for k in set(inv_b) | set(inv_a) if inv_b.get(k) != inv_a.get(k)}
        kdiff = {k: [keys_b.get(k), keys_a.get(k)] for k in set(keys_b) | set(keys_a) if keys_b.get(k) != keys_a.get(k)}
        sv_a = self.read_save()
        st_b = ((sv_b.get("state") or {}).get("structures") or {})
        st_a = ((sv_a.get("state") or {}).get("structures") or {})
        self.reload_report = {"saved": saved, "quit": quit_how, "exited": exited, "inv_diff": diff, "key_diff": kdiff,
                              "equipment_before": eq_b, "equipment_after": eq_a, "optional_before": opt_b, "optional_after": opt_a,
                              "structures_before": len(st_b), "structures_after": len(st_a),
                              "ledger_c1x": {k: v for k, v in ((sv_a.get("state") or {}).get("ledger") or {}).items()
                                             if k.startswith(("rw_c1x", "rw_opt"))}}
        ok = not diff and not kdiff and opt_a == opt_b and eq_a == eq_b
        if not ok:
            self.cov_bug("Chapter One optional state changed across Save & Quit -> Continue", "major",
                         "fixture 16 -> optional goals -> pause Save Game -> Quit Game -> Save & Quit -> relaunch -> Continue",
                         "same items, goals and equipment", f"{self.reload_report}", [str(self.out / "cov_result.json")])
        return ok

    # ------------------------------------------------------------------ segments / driver
    def seg(self, sid, steps):
        def fn():
            self.p1, self.p4 = self.players(sid.lower())
            return self.run_steps(sid, steps)
        return fn

    def run_cov(self):
        status = "running"
        self.monitor.start()
        try:
            self.save_dir.mkdir(parents=True, exist_ok=True)
            bak = Path(self.start_save).with_name("slot1.bak.json")
            CH.C.prepare_saves(self.save_dir, Path(self.start_save), bak if bak.exists() else None)
            self.launch()
            if not self.bot.wait_state(lambda s: s.get("mode") == "title" and any(b.get("text") == "Continue" for b in s.get("buttons", [])), 120):
                raise CH.ChainStop("no title / Continue")
            self.bot.click_button("Continue", exact=True, timeout=10)
            if not self.wait_playing(None, 120):
                self.p1, self.p4 = self.players("boot")
                self.p4.close_panels()
                if not self.wait_playing(None, 60):
                    raise CH.ChainStop("Continue never reached gameplay")
            time.sleep(2.0)
            self.bot.calibrate_look()
            self.inv0 = self.inv_all()
            segs = [
                ("C1", [("start", self.step_start)]),
                ("GARDEN", [("harvest_sweetroot", self.step_harvest_sweetroot), ("meadow_wild_crops", self.step_meadow),
                            ("plant_at_home", self.step_plant)]),
                ("REST", [("sleep_and_harvest", self.step_sleep_harvest)]),
                ("TAILOR", [("tailor_cache", self.step_tailor)]),
                ("BRAMBLE", [("find_bramblewatch", self.step_bramble_found), ("knotted_elder", self.step_elder),
                             ("bramblebacks", self.step_bramblebacks)]),
                ("WOOD", [("chop_wood", self.step_wood)]),
                ("BUILD", [("place_furnace_stairs_floor", self.step_build), ("first_bar", self.step_first_bar),
                           ("walk_upstairs", self.step_walk_up)]),
                ("FIX", [("landing_tile", self.step_landing_fix), ("walk_upstairs", self.step_walk_up)]),
                ("ARMOR", [("hood", self.step_armor)]),
                ("ANNEX", [("tobins_shift", self.step_annex)]),
                ("SMELT", [("copper_ore", self.step_copper), ("furnace_queue", self.step_smelt)]),
                ("RELOAD", [("save_quit_continue", self.step_reload)]),
            ]
            for sid, steps in segs:
                if self.only and sid not in self.only:
                    continue
                if time.time() > self.deadline:
                    status = f"stops before {sid}: time budget used up"
                    break
                if sid == "BUILD":
                    self.inv_before_build = self.inv_all()
                if not self.run_segment(sid, self.seg(sid, steps)):
                    self.log(f"segment {sid} did not complete; continuing with the next (independent) segment")
                if self.game is None or not self.game.alive():
                    status = f"game process gone after {sid}"
                    break
            else:
                status = "completes"
        except Exception as e:  # noqa: BLE001
            status = f"harness error {type(e).__name__}: {e}"
            self.log(traceback.format_exc())
        finally:
            for g in self.games:
                g.stop()
            time.sleep(0.8)
            self.monitor.stop()
            self.monitor.join(5.0)
            errs, warns = self.collect_errors()
            self.all_errors += errs
            self.warnings += warns
        self.write_result(status)
        res = json.loads((self.out / "chain_result.json").read_text(encoding="utf-8"))
        goal_msgs = [e for e in self.monitor.events if e.get("k") == "msg_quest" and "optional completed" in str(e.get("text"))]
        cov = {"part": "ch1", "natural": Path(self.start_save).name == CH.FIXTURE_NAME, "start_save": str(self.start_save),
               "status": status, "goals": self.goal_log, "goal_completion_msgs": goal_msgs,
               "fights": self.fights, "build": self.build_report, "furnace": self.furnace_report,
               "plant": getattr(self, "plant_report", None), "sleep": getattr(self, "sleep_report", None),
               "annex": {k: v for k, v in (getattr(self, "annex_report", {}) or {}).items()},
               "copper": getattr(self, "copper_report", None), "reload": getattr(self, "reload_report", None),
               "observations": self.obs, "notes": self.cov_notes,
               "segments": [{k: s.get(k) for k in ("id", "ok", "seconds", "status", "checkpoints", "hp_min", "deaths",
                                                   "script_errors", "problems")} for s in self.segments],
               "script_errors": res.get("script_errors"), "warnings": res.get("warnings"),
               "total_seconds": res.get("total_seconds")}
        CH.write_json(self.out / "cov_result.json", cov)
        counts: dict = {}
        for e in goal_msgs:
            gid = str(e.get("text")).replace("optional completed ", "")
            counts[gid] = counts.get(gid, 0) + 1
        for gid, c in counts.items():
            if c > 1:
                self.cov_bug(f"Optional goal {gid} completed {c} times", "major", "see cov_result.json goal_completion_msgs",
                             "each goal completes (and pays) once", f"{c} 'optional completed {gid}' messages",
                             [str(self.out / "chain_events.jsonl")])
        bugs = list(self.cov_bugs)
        for g in (res.get("script_errors") or {}).get("unique", []):
            bugs.append({"title": f"SCRIPT ERROR: {str(g.get('line'))[:150]}", "severity": "major",
                         "steps": f"Chapter One optional run (segments {g.get('segments')})", "expected": "no script errors",
                         "actual": f"{g.get('count')}x {g.get('line')} {g.get('at')}",
                         "evidence": [str(x.godot_log) for x in self.games]})
        CH.write_json(self.out / "bugs.json", bugs)
        return status


# ================================================================================================ CLI
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--part", choices=["ch2", "ch1"], required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--max-minutes", type=float, default=45.0)
    ap.add_argument("--start-save", default="")
    ap.add_argument("--order", default="manor,orchard", help="ch2: lamp order before the quarry (manor,orchard | orchard,manor)")
    ap.add_argument("--only", default="", help="ch1: comma-separated segment ids to run (diagnostic resume)")
    a = ap.parse_args(argv)
    out = Path(a.out).resolve()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    if a.part == "ch2":
        start = Path(a.start_save) if a.start_save else S1_END
        cfg = SimpleNamespace(out=out, headless=True, exe=None, project=(ROOT / "game").resolve(), godot=None, port=a.port,
                              seed=None, max_minutes=a.max_minutes, mute=True, rect=parse_rect(SECOND_MONITOR_RECT),
                              start_save=start.resolve(), from_seg="S2", until="", dry_run=False,
                              order=[x for x in a.order.split(",") if x])
        run = LampOrder(cfg)
        run.log(f"cov ch2 out={out} start_save={start} port={a.port}")
        st = run.run_cov()
    else:
        start = Path(a.start_save) if a.start_save else FIXTURE16
        cfg = SimpleNamespace(out=out, headless=True, exe=None, project=(ROOT / "game").resolve(), godot=None, port=a.port,
                              seed=None, max_minutes=a.max_minutes, mute=True, rect=parse_rect(SECOND_MONITOR_RECT),
                              start_save=start.resolve(), from_seg="S1", until="", dry_run=False)
        run = Ch1Optional(cfg, only=[x for x in a.only.split(",") if x])
        run.log(f"cov ch1 out={out} start_save={start} port={a.port}")
        st = run.run_cov()
    print(json.dumps({"status": st, "out": str(out)}, indent=1))
    return 0 if st == "completes" else 1


if __name__ == "__main__":
    sys.exit(main())
