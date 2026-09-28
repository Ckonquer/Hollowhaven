"""Coverage run "arachnophobia_comfort" (MP 20.4 Run D, comfort half) - headless QA bot, normal inputs only.

Every scenario starts from a save the game itself wrote on a NATURAL route (no fixtures, no debug args), with an
ISOLATED settings file written BEFORE the game starts:
    arachnophobia ON, reduce_shake ON, reduce_flashing ON, captions ON, master_volume 0 (+ --qa-mute),
    timing_assist OFF unless the scenario says "assist on".
Scenarios (python tools/qa/ch2/cov_arachnophobia_comfort.py <scenario> [--attempt N]):
  matron      Chapter One Weaver Matron (arachnophobia: the Hollow Mother). Start: the S0 route's "deeper" checkpoint
              (qa/tmp/bot/s0/run11/checkpoints/deeper = the game's own save at the shrine lantern, fresh New Game
              route) -> the Silk Hollows walk -> the 3-phase boss ("thorough" style: fans, trip-lines, sacs + Brood
              Skitters / Pale Sprouts, channel). Mid-fight the bot opens Pause -> Comfort & Accessibility and turns
              arachnophobia OFF (preferably while a minion is alive) and a few seconds later ON again.
  works       Hushed Works from the chain run's refuge checkpoint (qa/tmp/bot/chain/run4/s4/checkpoints/refuge):
              water line, the BELL-SYMBOL puzzle solved from the board's glyph order (layout data = what the painted
              plaque shows; the bot never reads the plaque text or a caption to solve it), light line, the Threaded
              Winch, the Weaver's Crossing (arachnophobia toggled OFF/ON mid-fight).
  choir       The Borrowed Choir from the chain run's Bell Throat checkpoint. --assist on|off. Phase B includes a
              deliberate probe of the resonator sequence window: strike the first plate, wait out of the rings, then
              continue (assist off: the 12 s window should restart the sequence; assist on: no window).
  velour      Count Velour from the chain run's T23_end checkpoint (the Commons): the road to the manor arch, the
              manor route up to the Count defeated. --assist on|off.
  analyze     Post-process every run dir: spider-lexicon scan of all player-facing telemetry text (captions, hints,
              lines, toasts, prompts, interaction texts, objective / tracker titles, UI buttons) split by the
              arachnophobia state at that moment, enemy ids -> display names, boss state durations (timing assist
              ON vs OFF, incl. the chain runs' OFF baselines), game-log errors; writes summary.json + bugs.json.
Runs go to qa/tmp/bot/cov_arachnophobia_comfort/<scenario>[_<assist>]_<attempt>/, ports 8160 + attempt (key index 3).
Information advantage (label it when quoting): the bot reads positions, states, prompts and captions from the
read-only telemetry; it sees no pixels (headless: no rendering, no screenshots) and hears nothing.
Only the game processes started here are ever killed (s4_common.HeadlessGame.stop -> taskkill /T on our pid).
"""
from __future__ import annotations

import argparse
import configparser
import json
import math
import re
import shutil
import sys
import time
import traceback
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
QA_DIR = HERE.parent
for _p in (str(HERE), str(QA_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from s4_common import HeadlessGame, Play, StepFailed, dist2, place_save, write_json, xz, ROOT  # noqa: E402

KEY = "arachnophobia_comfort"
KEY_INDEX = 3
RUN_ROOT = ROOT / "qa" / "tmp" / "bot" / f"cov_{KEY}"
PORT_BASE = 8100 + KEY_INDEX * 20
GAME = ROOT / "game"

SAVE_MATRON = ROOT / "qa" / "tmp" / "bot" / "s0" / "run11" / "checkpoints" / "deeper" / "slot1.json"
SAVE_REFUGE = ROOT / "qa" / "tmp" / "bot" / "chain" / "run4" / "s4" / "checkpoints" / "refuge" / "slot1.json"
SAVE_THROAT = ROOT / "qa" / "tmp" / "bot" / "chain" / "run4" / "s4" / "checkpoints" / "bell_throat" / "slot1.json"
SAVE_T23 = ROOT / "qa" / "tmp" / "bot" / "chain" / "run4" / "checkpoints" / "T23_end" / "slot1.json"

# The chain's own settings file (all defaults) as the template; the comfort overrides go on top.
BASE_SETTINGS = {
    "mouse_sensitivity": "0.5", "invert_y": "false", "fov": "70.0", "camera_distance": "5.0", "show_hints": "true",
    "master_volume": "0.85", "music_volume": "0.6", "ambience_volume": "0.8", "sfx_volume": "0.85", "ui_volume": "0.7",
    "horror_intensity": "1", "arachnophobia": "false", "reduce_shake": "false", "reduce_flashing": "false",
    "captions": "true", "comfort_confirmed": "false", "high_visibility_cues": "false", "timing_assist": "false",
    "companion_auto_attack": "true", "companion_autocast": "true", "seasonal_decor": "false", "fullscreen": "true",
    "vsync": "true", "max_fps": "0", "render_scale": "1.0", "quality": "2", "show_fps": "false", "bindings": "{}",
}
COMFORT = {"arachnophobia": "true", "reduce_shake": "true", "reduce_flashing": "true", "captions": "true",
           "master_volume": "0.0", "comfort_confirmed": "true"}
TOGGLE_ORDER = ["arachnophobia", "reduce_shake", "reduce_flashing", "captions"]   # comfort_screen.gd right column


def write_settings(path: Path, assist: bool) -> dict:
    vals = dict(BASE_SETTINGS)
    vals.update(COMFORT)
    vals["timing_assist"] = "true" if assist else "false"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("[settings]\n\n" + "\n".join(f"{k}={v}" for k, v in vals.items()) + "\n", encoding="utf-8")
    return vals


def read_settings(path: Path) -> dict:
    out = {}
    try:
        for ln in Path(path).read_text(encoding="utf-8").splitlines():
            if "=" in ln and not ln.startswith("["):
                k, v = ln.split("=", 1)
                out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def game_t(s: dict) -> float:
    try:
        return float(s.get("t", 0.0))
    except (TypeError, ValueError):
        return 0.0


# ================================================================================================ comfort toggle
class Toggler:
    """Pause -> 'Comfort & Accessibility' -> flip the arachnophobia CheckButton -> Done -> Resume, through normal
    UI clicks. Every flip is recorded with the game time, the toggle texts before/after, the boss / minion state
    around it and the settings file content after the comfort screen closed (it saves on close)."""

    def __init__(self, g: HeadlessGame, log, settings_path: Path):
        self.g = g
        self.bot = g.bot
        self.log = log
        self.settings_path = settings_path
        self.records: list[dict] = []
        self.busy = False

    def _buttons(self) -> list:
        return list(self.bot.state().get("buttons", []) or [])

    def _click(self, b: dict):
        r = b.get("rf") or b.get("rect")
        x, y, w, h = [float(v) for v in r]
        self.g.vin.click(x + w / 2.0, y + h / 2.0)

    def _wait(self, pred, timeout: float):
        t0 = time.time()
        while time.time() - t0 < timeout:
            s = self.bot.state()
            try:
                if s and pred(s):
                    return s
            except (KeyError, TypeError, IndexError):
                pass
            time.sleep(0.05)
        return None

    def _find(self, text: str, exact: bool = True):
        for b in self._buttons():
            t = str(b.get("text", ""))
            if (t == text if exact else text.lower() in t.lower()) and not b.get("disabled"):
                return b
        return None

    def _toggles(self) -> list:
        tg = [b for b in self._buttons() if str(b.get("text", "")) in ("On", "Off")]
        return sorted(tg, key=lambda b: (float((b.get("rf") or b.get("rect"))[1]), float((b.get("rf") or b.get("rect"))[0])))

    def flip(self, want: bool, why: str) -> dict:
        """Sets arachnophobia to `want` through the pause menu. Returns the record."""
        self.busy = True
        rec: dict = {"want": want, "why": why, "ok": False}
        try:
            s = self.bot.state()
            rec["t_before"] = game_t(s)
            rec["boss_before"] = s.get("boss")
            rec["minions_before"] = [{"name": e.get("name"), "hp": e.get("hp"), "state": e.get("state"), "dist": e.get("dist")}
                                     for e in s.get("nearby", []) or [] if e.get("g") == "enemy" and "Skitter" in str(e.get("name", ""))]
            self.bot.release_all()
            if not s.get("ui_stack"):
                self.bot.tap("ESC")
            if not self._wait(lambda st: "pause" in (st.get("ui_stack") or []) and any(
                    b.get("text") == "Comfort & Accessibility" for b in st.get("buttons", []) or []), 4.0):
                rec["error"] = f"pause menu did not open (ui {self.bot.state().get('ui_stack')})"
                return rec
            time.sleep(0.3)
            b = self._find("Comfort & Accessibility")
            self._click(b)
            if not self._wait(lambda st: "comfort" in (st.get("ui_stack") or []) and len(
                    [x for x in st.get("buttons", []) or [] if x.get("text") in ("On", "Off")]) >= 4, 4.0):
                rec["error"] = f"comfort screen did not open (ui {self.bot.state().get('ui_stack')})"
                return rec
            time.sleep(0.4)
            tg = self._toggles()
            rec["toggles_before"] = {TOGGLE_ORDER[i]: tg[i].get("text") for i in range(min(4, len(tg)))}
            arach = tg[0]
            if (arach.get("text") == "On") != want:
                y0 = float((arach.get("rf") or arach.get("rect"))[1])
                self._click(arach)
                want_txt = "On" if want else "Off"
                if not self._wait(lambda st: any(x.get("text") == want_txt and abs(float((x.get("rf") or x.get("rect"))[1]) - y0) < 0.05
                                                 for x in st.get("buttons", []) or []), 3.0):
                    rec["error"] = "the arachnophobia toggle did not flip"
                time.sleep(0.3)
            rec["t_flip"] = game_t(self.bot.state())
            tg = self._toggles()
            rec["toggles_after"] = {TOGGLE_ORDER[i]: tg[i].get("text") for i in range(min(4, len(tg)))}
            done = self._find("Done")
            if done:
                self._click(done)
            self._wait(lambda st: "comfort" not in (st.get("ui_stack") or []), 3.0)
            time.sleep(0.3)
            rec["settings_file_after_close"] = {k: read_settings(self.settings_path).get(k) for k in
                                                ("arachnophobia", "reduce_shake", "reduce_flashing", "captions",
                                                 "master_volume", "timing_assist")}
            if "pause" in (self.bot.state().get("ui_stack") or []):
                r = self._find("Resume")
                if r:
                    self._click(r)
                else:
                    self.bot.tap("ESC")
            if not self._wait(lambda st: not st.get("ui_stack") and st.get("mode") == "playing" and not st.get("paused"), 4.0):
                self.bot.tap("ESC")
                self._wait(lambda st: not st.get("ui_stack"), 3.0)
            s = self.bot.state()
            rec["t_after"] = game_t(s)
            rec["boss_after"] = s.get("boss")
            rec["minions_after"] = [{"name": e.get("name"), "hp": e.get("hp"), "state": e.get("state"), "dist": e.get("dist")}
                                    for e in s.get("nearby", []) or [] if e.get("g") == "enemy" and "Skitter" in str(e.get("name", ""))]
            rec["ok"] = rec.get("toggles_after", {}).get("arachnophobia") == ("On" if want else "Off") and not s.get("ui_stack")
            return rec
        except Exception as e:  # noqa: BLE001
            rec["error"] = f"{type(e).__name__}: {e}"
            return rec
        finally:
            self.records.append(rec)
            self.log(f"COMFORT TOGGLE arachnophobia -> {want} ({why}): {json.dumps(rec, default=str)[:900]}")
            self.busy = False


class FightToggleHook:
    """Runs inside the Play layer's st() (between the route bot's actions, never while it holds a key): turns
    arachnophobia OFF once during the boss fight - preferably while a Brood Skitter / Pale Sprout is alive - and ON
    again `back_after` game seconds later."""

    def __init__(self, toggler: Toggler, boss_words: tuple, min_phase: int = 2, fallback_after: float = 30.0,
                 back_after: float = 9.0, earliest_boss_t: float = 6.0):
        self.tg = toggler
        self.boss_words = boss_words
        self.min_phase = min_phase
        self.fallback_after = fallback_after
        self.back_after = back_after
        self.earliest_boss_t = earliest_boss_t
        self.boss_first_t = None
        self.phase_t: dict = {}
        self.off_t = None
        self.done = False

    def __call__(self, s: dict):
        if self.done or self.tg.busy or not s or s.get("ui_stack") or s.get("mode") != "playing":
            return
        if self.tg.bot.held:
            return
        t = game_t(s)
        boss = s.get("boss") or {}
        is_boss = boss and any(w in (str(boss.get("id", "")) + str(boss.get("name", ""))).lower() for w in self.boss_words)
        if self.off_t is None:
            if not is_boss or str(boss.get("state", "")) in ("dormant", "defeated", "gone", "dead", "intro"):
                return
            if self.boss_first_t is None:
                self.boss_first_t = t
            ph = int(boss.get("phase", 1) or 1)
            self.phase_t.setdefault(ph, t)
            if t - self.boss_first_t < self.earliest_boss_t:
                return
            minion = any(e.get("g") == "enemy" and "Skitter" in str(e.get("name", "")) and float(e.get("hp", 0) or 0) > 0
                         and str(e.get("state", "")) not in ("dead", "dying") for e in s.get("nearby", []) or [])
            late = ph >= self.min_phase and t - self.phase_t.get(ph, t) > self.fallback_after
            if minion or late:
                why = "a Brood Skitter / Pale Sprout is alive" if minion else f"phase {ph} for {t - self.phase_t.get(ph, t):.0f} s"
                rec = self.tg.flip(False, "mid-fight: " + why)
                self.off_t = rec.get("t_flip", t)
                if not rec.get("ok"):
                    self.tg.flip(True, "restore after a failed flip")
                    self.done = True
            return
        if t - self.off_t >= self.back_after:
            self.tg.flip(True, f"mid-fight: back ON after {t - self.off_t:.1f} s")
            self.done = True


def hook_st(obj, hook):
    """Wraps obj.st() so `hook(state)` runs after every observation (instance attribute shadows the method)."""
    orig = obj.st

    def st(*a, **k):
        s = orig(*a, **k)
        try:
            hook(s)
        except Exception as e:  # noqa: BLE001
            obj.log(f"hook error: {e}")
        return s
    obj.st = st


# ================================================================================================ journal sweep
def journal_sweep(g: HeadlessGame, log) -> dict:
    """J -> every tab -> record the visible button texts (quest / lore / friend titles); Esc."""
    bot = g.bot
    out: dict = {}

    def buttons():
        return [str(b.get("text", "")) for b in bot.state().get("buttons", []) or [] if not b.get("clipped")]

    def click(text):
        for b in bot.state().get("buttons", []) or []:
            if str(b.get("text", "")).strip().lower() == text.lower():
                r = b.get("rf") or b.get("rect")
                g.vin.click(float(r[0]) + float(r[2]) / 2, float(r[1]) + float(r[3]) / 2)
                return True
        return False
    try:
        bot.release_all()
        bot.tap("J")
        t0 = time.time()
        while time.time() - t0 < 4 and "journal" not in (bot.state().get("ui_stack") or []):
            time.sleep(0.1)
        if "journal" not in (bot.state().get("ui_stack") or []):
            return {"error": f"journal did not open: {bot.state().get('ui_stack')}"}
        time.sleep(0.6)
        out["first"] = buttons()
        for tab in ("Story", "Optional", "Friends", "Lore", "Mastery", "Bestiary", "Creatures"):
            if click(tab):
                time.sleep(0.7)
                out[tab] = buttons()
        bot.tap("ESC")
        time.sleep(0.6)
        if bot.state().get("ui_stack"):
            bot.tap("ESC")
            time.sleep(0.5)
    except Exception as e:  # noqa: BLE001
        out["error"] = str(e)
    log(f"journal sweep: { {k: len(v) if isinstance(v, list) else v for k, v in out.items()} }")
    return out


# ================================================================================================ launch helpers
def prepare_run(name: str, attempt: int, save: Path, assist: bool, max_seconds: int) -> HeadlessGame:
    out = RUN_ROOT / f"{name}_{attempt}"
    if out.exists():
        for sub in ("saves", "checkpoints"):
            if (out / sub).exists():
                shutil.rmtree(out / sub)
    out.mkdir(parents=True, exist_ok=True)
    port = PORT_BASE + attempt
    from s4_common import port_free
    while not port_free(port):
        port += 1
        if port >= PORT_BASE + 20:
            raise RuntimeError("no free port in this key's range 8160-8179")
    g = HeadlessGame(out, name, port, max_seconds=max_seconds, extra=["--qa-mute", "--no-wardrobe-notice"])
    written = write_settings(g.settings_file, assist)
    place_save(g.save_dir, save, save.with_name("slot1.bak.json"))
    meta = {"scenario": name, "attempt": attempt, "port": port, "start_save": str(save), "start_kind": "natural",
            "settings_written_before_launch": written, "started": time.strftime("%Y-%m-%d %H:%M:%S")}
    write_json(out / "run_meta.json", meta)
    return g


def title_continue(g: HeadlessGame, log) -> dict:
    bot = g.bot
    s = bot.wait_state(lambda st: st.get("mode") == "title" and any(b.get("text") == "Continue" for b in st.get("buttons", []) or []), 120)
    rec = {"title_buttons": [b.get("text") for b in (s or {}).get("buttons", []) or []]}
    if not s:
        raise StepFailed("no title / Continue")
    time.sleep(0.5)
    b = next(b for b in bot.state().get("buttons", []) if b.get("text") == "Continue")
    r = b.get("rf") or b.get("rect")
    g.vin.click(float(r[0]) + float(r[2]) / 2, float(r[1]) + float(r[3]) / 2)
    if not bot.wait_state(lambda st: st.get("mode") == "playing" and bool(st.get("area")), 90):
        raise StepFailed("Continue did not reach gameplay")
    time.sleep(2.0)
    s = bot.state()
    rec.update({"area": s.get("area"), "zone": s.get("zone"), "pos": s.get("pos"), "objective": s.get("objective"),
                "tracker": s.get("tracker"), "settings_file": read_settings(g.settings_file)})
    log(f"continued: {json.dumps(rec, default=str)[:600]}")
    return rec


def finish(g: HeadlessGame, res: dict, extra_logs=()):
    out = g.run
    try:
        res["journal"] = journal_sweep(g, g.bot.log) if g.alive() else {"error": "game not running"}
    except Exception as e:  # noqa: BLE001
        res["journal"] = {"error": str(e)}
    s = g.bot.state() if g.bot else {}
    res["final"] = {k: s.get(k) for k in ("area", "zone", "mode", "objective", "tracker", "inv")}
    res["final"]["flags"] = sorted(f for f in s.get("flags", []) or [] if f.startswith(("ch2_", "hw_", "weaver", "hint_", "moment", "mm_")))
    res["settings_file_at_end"] = read_settings(g.settings_file)
    res["ended"] = time.strftime("%Y-%m-%d %H:%M:%S")
    g.stop()
    write_json(out / "result.json", res)


# ================================================================================================ scenario: matron
def scenario_matron(attempt: int, style: str = "thorough", fallback: float = 25.0) -> dict:
    import playthrough as PT
    from s0_fresh_c1 import _ShimSession
    g = prepare_run("matron", attempt, SAVE_MATRON, assist=False, max_seconds=1500)
    res: dict = {"scenario": "matron", "start": f"natural: {SAVE_MATRON} (the game's save at the shrine lantern, S0 fresh route run11)",
                 "matron_style": style, "toggle_fallback_s": fallback}
    g.start()
    log = g.bot.log
    try:
        res["continue"] = title_continue(g, log)
        shim = _ShimSession(g.bot, g.run, name="matron")
        play = PT.Play(shim)
        eater = Play(g, g.run)                       # backpack eating that works with injected clicks
        play.eat_best = lambda: eater.eat_best()
        tg = Toggler(g, log, g.settings_file)
        hook_st(play, FightToggleHook(tg, ("weaver",), min_phase=2, fallback_after=fallback, back_after=9.0))
        steps = dict(PT.build_steps(play, SimpleNamespace(continue_save=True, matron_style=style)))
        g.bot.calibrate_look()
        # the deeper step's tail (the corridor into the Silk Hollows), then the route's own "silk_and_boss" step
        for pt in [(63.0, -85.75), (66.0, -85.75), (78.0, -85.75), (81.0, -85.75)]:
            play.goto(pt, tol=1.2, sprint=True, timeout=30)
        t0 = time.time()
        ok = False
        try:
            ok = bool(steps["silk_and_boss"]())
        except StepFailed as e:
            res["error"] = f"StepFailed: {e}"
        except Exception as e:  # noqa: BLE001
            res["error"] = f"{type(e).__name__}: {e}"
            log(traceback.format_exc())
        res["boss_won"] = ok
        res["seconds"] = round(time.time() - t0, 1)
        res["notes"] = play.notes
        res["problems"] = play.problems
        res["toggles"] = tg.records
        res["events"] = play.events
        time.sleep(3.0)
    except Exception as e:  # noqa: BLE001
        res["error"] = f"{type(e).__name__}: {e}"
        log(traceback.format_exc())
    finally:
        finish(g, res)
    return res


# ================================================================================================ scenario: works
BELL_ORDER_FILE = GAME / "data" / "works_layout.gd"


def board_glyph_order() -> list:
    """The order painted on the Bellmaker's board (works_bells.gd _build_board draws Layout.BELL_ORDER's glyphs left
    to right): what a player SEES, read here from the layout data instead of pixels (headless)."""
    txt = BELL_ORDER_FILE.read_text(encoding="utf-8")
    m = re.search(r"const BELL_ORDER := \[([^\]]*)\]", txt)
    return [w.strip().strip('"') for w in m.group(1).split(",")] if m else []


def scenario_works(attempt: int) -> dict:
    import s4_route as R
    g = prepare_run("works", attempt, SAVE_REFUGE, assist=False, max_seconds=1700)
    res: dict = {"scenario": "works", "start": f"natural: {SAVE_REFUGE} (the chain run4 save at the refuge lantern, before the three lines)"}
    g.start()
    log = g.bot.log
    try:
        res["continue"] = title_continue(g, log)
        p = R.S4(g, g.run)
        tg = Toggler(g, log, g.settings_file)
        hook = FightToggleHook(tg, ("matron", "crossing"), min_phase=1, fallback_after=12.0, back_after=9.0, earliest_boss_t=8.0)
        R.step_start(p)

        def step_bells_visual(pp):
            """Bell line solved from the board's glyph order only (never reads the plaque text or a caption)."""
            if pp.flag("ch2_line_bell"):
                return True
            order = board_glyph_order()
            res["bell_board_order"] = order
            pp.nav((12.0, -16.0, 26.5))
            pp.fight_smart(timeout=90.0, radius=12.0)
            n0 = len(pp.all_msgs)
            strikes = []
            for attempt_ in range(3):
                for sym in order:
                    pp.fight_smart(timeout=60.0, radius=7.0)
                    post = R.BELL_POSTS[sym]
                    stand = R._stand_for_post(post)
                    pp.goto((stand[0], stand[2]), tol=0.5, sprint=False)
                    ok = pp.interact_with(post, [f"Strike the {sym.capitalize()} bell"], check=lambda: True, stop=1.5, tries=4)
                    strikes.append({"sym": sym, "pressed": ok, "t": round(pp.game_t(), 2)})
                    time.sleep(0.8)
                if pp.wait_flag("ch2_line_bell", 3):
                    break
            res["bell_strikes"] = strikes
            res["bell_captions"] = [m for m in pp.all_msgs[n0:] if m.get("k") in ("caption", "notify", "hint", "say")]
            return pp.flag("ch2_line_bell")

        def step_crossing_hooked(pp):
            hook_st(pp, hook)
            try:
                return R.step_crossing(pp)
            finally:
                if "st" in pp.__dict__:
                    del pp.st

        steps = [("line_water", R.step_line_water), ("line_bell_visual", step_bells_visual), ("line_light", R.step_line_light),
                 ("winch", R.step_winch), ("crossing", step_crossing_hooked)]
        res["checkpoints"] = []
        for name, fn in steps:
            t = time.time()
            ok, err = False, ""
            log(f"=== STEP {name} ===")
            try:
                ok = bool(fn(p))
            except StepFailed as e:
                err = f"StepFailed: {e}"
            except Exception as e:  # noqa: BLE001
                err = f"{type(e).__name__}: {e}"
                log(traceback.format_exc())
            res["checkpoints"].append({"step": name, "ok": ok, "seconds": round(time.time() - t, 1), "error": err, "hp": p.hp()})
            log(f"=== {name}: {'PASS' if ok else 'FAIL'} {err}")
            if not ok:
                break
        res["toggles"] = tg.records
        res["problems"] = p.problems
        res["messages"] = p.all_msgs
        time.sleep(2.0)
    except Exception as e:  # noqa: BLE001
        res["error"] = f"{type(e).__name__}: {e}"
        log(traceback.format_exc())
    finally:
        finish(g, res)
    return res


# ================================================================================================ scenario: choir
def make_probe_bot(R, p, assist: bool, rec: dict):
    class ProbeChoirBot(R.ChoirBot):
        """ChoirBot + one deliberate resonator-window probe in Phase B (see the module docstring)."""

        def __init__(self, p_):
            super().__init__(p_)
            self.probe_done = False

        def _msg_t(self, n0: int, pat: str):
            for m in self.p.all_msgs[n0:]:
                if re.search(pat, str(m.get("text", ""))):
                    return float(m.get("t", 0.0)), str(m.get("text", ""))
            return None, ""

        def phase_b(self, s, st, me):
            if self.probe_done or any(self.res_done.values()) or any(self.res_prog.values()):
                return super().phase_b(s, st, me)
            if st in ("b_ring_tele", "b_rings", "b_strike_tele"):
                return super().phase_b(s, st, me)        # with no plate progress it only dodges here
            if st not in ("b_idle", "b_reform", "b_gather"):
                time.sleep(0.15)                          # e.g. the phase shriek: wait for Phase B proper
                return
            self.probe_done = True
            p_ = self.p
            self.read_msgs()
            r = min(("west", "east"), key=lambda k: dist2(xz(me), xz(R.RESONATORS[k])))
            order = list(self.order)
            idx0 = R.SYMBOLS.index(order[0])
            n0 = len(p_.all_msgs)
            first = self.strike_plate(r, idx0)
            t1, txt1 = self._msg_t(n0, r"\(1 of \d\)")
            rec.update({"resonator": r, "order": order, "first_strike": first, "t_first": t1, "first_caption": txt1,
                        "assist": assist})
            self.log(f"  PROBE first plate {order[0]} on {r}: {first} t={t1}")
            if first not in ("ok",) or t1 is None:
                rec["aborted"] = "first strike not accepted"
                return
            self.res_prog[r] = 1
            wait_s = 20.0 if assist else 16.0
            safe = R._behind_frame(r, p_.pos())
            self.around_frame(r, safe)
            p_.goto((safe[0], safe[2]), tol=0.7, sprint=True, timeout=5.0)
            reset_t = None
            side = 1.0
            while True:
                s2 = p_.st()
                now = game_t(s2)
                if now - t1 >= wait_s:
                    break
                tr, _ = self._msg_t(n0, r"start the sequence again")
                if tr is not None and reset_t is None:
                    reset_t = tr
                    self.log(f"  PROBE reset caption at +{tr - t1:.2f} s")
                    if not assist:
                        break
                boss = s2.get("boss") or {}
                bst = str(boss.get("state", ""))
                if bst == "b_strike_tele":
                    mep = p_.pos()
                    pp_ = R._perimeter_point(mep)
                    ang = math.atan2(pp_[2] - R.VC[2], pp_[0] - R.VC[0]) + side * 0.35
                    side = -side
                    p_.goto((R.VC[0] + math.cos(ang) * 11.3, R.VC[2] + math.sin(ang) * 11.3), tol=0.6, sprint=True, timeout=2.0)
                    continue
                if p_.hp() < 40:
                    p_.eat_best()
                    continue
                wisps = p_.live_enemies(4.0, lambda e: "phase" not in e and "wisp" in str(e.get("name", "")).lower())
                if wisps:
                    p_.fight_smart(timeout=6.0, radius=4.0, pred=lambda e: "phase" not in e and "wisp" in str(e.get("name", "")).lower())
                    continue
                if dist2(xz(p_.pos()), xz(R.VC)) < 10.4:
                    safe = R._behind_frame(r, p_.pos())
                    self.around_frame(r, safe)
                    p_.goto((safe[0], safe[2]), tol=0.7, sprint=True, timeout=3.0)
                    continue
                time.sleep(0.15)
            now = game_t(p_.st())
            rec["waited_s"] = round(now - t1, 2)
            rec["reset_after_s"] = round(reset_t - t1, 2) if reset_t is not None else None
            self.read_msgs()
            if reset_t is not None:
                self.res_prog[r] = 0
            if assist and reset_t is None:
                # the sequence should still hold: strike the second symbol now
                n1 = len(p_.all_msgs)
                second = self.strike_plate(r, R.SYMBOLS.index(order[1]))
                t2, txt2 = self._msg_t(n1, r"\(2 of \d\)|wrong note|rings true")
                rec.update({"second_strike": second, "t_second": t2, "second_caption": txt2,
                            "second_after_s": round(t2 - t1, 2) if t2 is not None else None})
                if second == "ok":
                    self.res_prog[r] = 2
                    self.seq_t0[r] = time.time()
                else:
                    self.res_prog[r] = 0
            self.log(f"  PROBE result: {json.dumps(rec)}")
    return ProbeChoirBot(p)


def scenario_choir(attempt: int, assist: bool) -> dict:
    import s4_route as R
    name = f"choir_{'on' if assist else 'off'}"
    g = prepare_run(name, attempt, SAVE_THROAT, assist=assist, max_seconds=1500)
    res: dict = {"scenario": name, "timing_assist": assist,
                 "start": f"natural: {SAVE_THROAT} (the chain run4 save at the Bell Throat lantern)"}
    g.start()
    log = g.bot.log
    try:
        res["continue"] = title_continue(g, log)
        p = R.S4(g, g.run)
        R.step_start(p)
        probe: dict = {}
        p.lantern(True)
        if not p.nav((157.0, -32.0, 53.7)):
            raise StepFailed("could not reach the vault stair")
        cb = make_probe_bot(R, p, assist, probe)
        t0 = time.time()
        ok = cb.run(1000.0)
        res["choir_defeated"] = ok
        res["seconds"] = round(time.time() - t0, 1)
        res["probe"] = probe
        res["picks"] = cb.picks
        res["problems"] = p.problems
        res["messages"] = p.all_msgs
        time.sleep(4.0)
    except Exception as e:  # noqa: BLE001
        res["error"] = f"{type(e).__name__}: {e}"
        log(traceback.format_exc())
    finally:
        finish(g, res)
    return res


# ================================================================================================ scenario: velour
def scenario_velour(attempt: int, assist: bool) -> dict:
    import s3_manor as S3
    import s4_route as R
    import s2_lib
    name = f"velour_{'on' if assist else 'off'}"
    g = prepare_run(name, attempt, SAVE_T23, assist=assist, max_seconds=1300)
    res: dict = {"scenario": name, "timing_assist": assist,
                 "start": f"natural: {SAVE_T23} (the chain run4 save at the Commons after T23)"}
    g.start()
    log = g.bot.log
    try:
        res["continue"] = title_continue(g, log)
        p4 = R.S4(g, g.run)
        R.step_start(p4)
        pts = [(1.5, 70.0), (2.5, 68.0), (2.5, 53.0), (0.0, 45.0), (0.0, 38.5), (0.0, 30.0), (0.0, 22.0),
               (-8.0, 12.0), (-9.0, 2.0), (0.5, -8.0), (0.5, -12.0), (2.5, -24.0), (5.0, -34.0), (8.1, -44.3),
               (10.0, -50.0), (10.9, -52.8)]
        here = xz(p4.pos())
        i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
        if not p4.route(pts[i:], tol=1.8, sprint=True, fight=True):
            raise StepFailed(f"the road to the manor arch is blocked at {p4.pos()}")
        foods = ("hearty_stew", "pumpkin_soup", "roseberry_tart", "berry_snack", "glowcap_skewer", "pumpkin_biscuit",
                 "candy", "sweetroot", "roseberries", "berries")

        class CovS3(S3.Segment):
            def eat(self) -> bool:
                if super().eat():
                    return True
                if not hasattr(self, "_bag"):
                    self._bag = s2_lib.Play(self.bot, self.out)
                ok_ = self._bag.eat_best(foods=foods)
                if ok_:
                    self.fight["eats"] += 1
                return ok_

        seg = CovS3(g.bot, g.run / "s3", optional=False, time_budget=1100.0, tether="pool")
        cps = [("start_in_reach", seg.s_start, True), ("light_manor_arch", seg.s_arch, False), ("enter_manor", seg.s_enter, True),
               ("looking_glass_hall", seg.s_hall, True), ("ballroom_puzzle", seg.s_puzzle, True),
               ("ballroom_rest", seg.s_rest_ballroom, True), ("velour_encounter_start", seg.s_gallery, True),
               ("velour_defeated", seg.s_boss, True)]
        status = "completes"
        try:
            for nm, fn, req in cps:
                seg.checkpoint(nm, fn, req)
        except S3.StepFailed as e:
            status = f"stops at {e}"
        res["status"] = status
        res["checkpoints"] = seg.checkpoints
        res["fight"] = seg.fight
        res["problems"] = seg.problems
        res["captions"] = seg._captions
        time.sleep(3.0)
    except Exception as e:  # noqa: BLE001
        res["error"] = f"{type(e).__name__}: {e}"
        log(traceback.format_exc())
    finally:
        finish(g, res)
    return res


# ================================================================================================ analysis
SPIDER_RE = re.compile(r"\b(spiders?|arachn\w*|webs?|webbed|cobwebs?|silk\w*|weaver'?s?|matron'?s?|skitter\w*|brood\w*|"
                       r"egg ?sacs?|sacs?|legs?|leggy|fangs?|rattl\w*|chitter\w*|cocoon\w*|mandibles?)\b", re.I)
SOFT_RE = re.compile(r"\b(threads?|strands?|twang\w*|spun|spin\w*)\b", re.I)
PLAYER_KINDS = ("caption", "hint", "say", "notify")


def flip_times(tele: Path) -> list:
    """Exact arachnophobia flips from the telemetry itself: while the comfort screen is open its first On/Off
    CheckButton (top of the right column) IS the arachnophobia toggle. Returns [(t, "On"|"Off"), ...] changes."""
    out = []
    last = None
    with open(tele, "r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            if '"comfort"' not in ln:
                continue
            try:
                d = json.loads(ln)
            except json.JSONDecodeError:
                continue
            if "comfort" not in (d.get("ui_stack") or []):
                continue
            tg = [b for b in d.get("buttons", []) or [] if b.get("text") in ("On", "Off")]
            if len(tg) < 4:
                continue
            tg.sort(key=lambda b: (float((b.get("rf") or b.get("rect"))[1]), float((b.get("rf") or b.get("rect"))[0])))
            v = tg[0].get("text")
            if v != last:
                out.append((game_t(d), v))
                last = v
    return out


def scan_telemetry(tele: Path, toggles: list) -> dict:
    """Every player-facing string in the telemetry, by the arachnophobia state at that moment. The OFF intervals come
    from the comfort screen's own toggle text in telemetry (exact to one 0.1 s line): OFF from the first line showing
    "Off" (minus one line) to the first line showing "On" again (+0.5 s: prompts / nearby texts refresh every 0.4 s).
    Hint ids ("id: text") and toast kinds ("success: text") are stripped: the player sees only the text."""
    flips = flip_times(tele)
    off_iv = []
    cur = None
    for t, v in flips:
        if v == "Off" and cur is None:
            cur = t - 0.3          # the button list is collected every 0.2 s: the click can precede it
        elif v == "On" and cur is not None:
            off_iv.append((cur, t + 0.5))
            cur = None
    if cur is not None:
        off_iv.append((cur, 1e9))

    def is_off(t):
        return any(a <= t <= b for a, b in off_iv)
    seen_msgs = set()
    strings: dict = {}          # (source, text) -> {"on": n, "off": n, "first_t": t}
    enemy_names: dict = {}
    boss_ids: dict = {}
    hazards: dict = {}
    n = 0
    t_first = t_last = None

    def add(src, text, t, off):
        text = str(text or "").strip()
        if not text:
            return
        k = (src, text)
        e = strings.setdefault(k, {"on": 0, "off": 0, "first_t": t})
        e["off" if off else "on"] += 1
    with open(tele, "r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                d = json.loads(ln)
            except json.JSONDecodeError:
                continue
            n += 1
            t = game_t(d)
            t_first = t if t_first is None else t_first
            t_last = t
            off = is_off(t)
            for m in d.get("messages", []) or []:
                key = (m.get("k"), m.get("text"), m.get("t"))
                if key in seen_msgs:
                    continue
                seen_msgs.add(key)
                if m.get("k") in PLAYER_KINDS:
                    txt = str(m.get("text", ""))
                    if m.get("k") in ("hint", "notify") and ": " in txt:
                        txt = txt.split(": ", 1)[1]          # "hint_id: text" / "kind: text" -> the shown text
                    add("msg:" + str(m.get("k")), txt, float(m.get("t", t) or t), is_off(float(m.get("t", t) or t)))
            pr = (d.get("player") or {}).get("prompt") or {}
            for kk in ("text", "reason"):
                if pr.get(kk):
                    add("prompt", pr.get(kk), t, off)
            for e in d.get("nearby", []) or []:
                if e.get("text"):
                    add("interaction", e.get("text"), t, off)
                if e.get("label"):
                    add("harvest", e.get("label"), t, off)
                if e.get("g") == "enemy":
                    base = re.sub(r"[_@0-9]+$", "", str(e.get("name", "")))
                    enemy_names.setdefault(base, {"on": 0, "off": 0})["off" if off else "on"] += 1
                    if e.get("kind"):
                        hazards.setdefault(str(e.get("kind")) + ":" + base, 0)
                        hazards[str(e.get("kind")) + ":" + base] += 1
            for kk in ("objective", "tracker"):
                o = d.get(kk) or {}
                if o.get("title"):
                    add(kk + ".title", o.get("title"), t, off)
            c2 = d.get("chapter2") or {}
            if c2.get("title"):
                add("chapter2.title", c2.get("title"), t, off)
            for b in d.get("buttons", []) or []:
                tx = str(b.get("text", ""))
                if tx and not tx.startswith("slot:"):
                    add("button", tx, t, off)
            bs = d.get("boss") or {}
            if bs.get("id"):
                boss_ids.setdefault(f"{bs.get('id')} ({bs.get('name')})", {"on": 0, "off": 0})["off" if off else "on"] += 1
    rows = []
    for (src, text), e in strings.items():
        rows.append({"src": src, "text": text, "on": e["on"], "off": e["off"], "first_t": e["first_t"],
                     "spider_hits": sorted(set(w.lower() for w in SPIDER_RE.findall(text))),
                     "soft_hits": sorted(set(w.lower() for w in SOFT_RE.findall(text)))})
    rows.sort(key=lambda r: r["first_t"])
    return {"lines": n, "t_range": [t_first, t_last], "flips": flips, "off_intervals": off_iv, "strings": rows,
            "leaks_while_on": [r for r in rows if r["spider_hits"] and r["on"] > 0],
            "soft_while_on": [r for r in rows if r["soft_hits"] and r["on"] > 0 and not r["spider_hits"]],
            "spider_words_while_off": [r for r in rows if r["spider_hits"] and r["off"] > 0],
            "enemy_node_names": enemy_names, "boss_ids": boss_ids, "hazard_kinds": hazards,
            "counts": {"strings": len(rows), "messages": len(seen_msgs)}}


def enemy_display_table() -> dict:
    """data/enemies.gd: id -> name / alt_name (ItemDB.enemy_display_name: alt_name when arachnophobia is on and
    alt_name != ""), plus the node-name prefix -> id mapping used by the factory (CamelCase of the id)."""
    txt = (GAME / "data" / "enemies.gd").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'^\t"([a-z_]+)": \{\s*\n\t\t"name": "([^"]*)", "alt_name": "([^"]*)"', txt, re.M):
        eid, nm, alt = m.group(1), m.group(2), m.group(3)
        out[eid] = {"name": nm, "alt_name": alt, "shown_with_arachnophobia": alt or nm,
                    "node_prefix": "".join(w.capitalize() for w in eid.split("_"))}
    return out


def state_durations(tele: Path, name_words: tuple) -> dict:
    """Consecutive-snapshot runs of the nearest boss's "state" (telemetry "boss", every 0.1 s): per state the list of
    run lengths in game seconds (first seen -> first different; +-0.1 s sampling)."""
    runs: dict = {}
    cur = None
    t0 = None
    last_t = None
    last_st = None
    with open(tele, "r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            try:
                d = json.loads(ln)
            except json.JSONDecodeError:
                continue
            b = d.get("boss") or {}
            t = game_t(d)
            ok = b and any(w in (str(b.get("id", "")) + str(b.get("name", ""))).lower() for w in name_words)
            st = str(b.get("state", "")) if ok else None
            if d.get("paused") or (d.get("ui_stack") and st is not None):
                # a menu pauses the fight: drop the current run and the rest of it after the menu closes
                cur, t0 = "__skip__", None
                continue
            if cur == "__skip__" and st is not None and last_t is not None and st == last_st:
                last_t = t
                continue
            last_st = st
            if st != cur:
                if cur not in (None, "__skip__") and t0 is not None and last_t is not None:
                    runs.setdefault(cur, []).append(round(t - t0, 2))
                cur, t0 = st, t
            last_t = t
    stats = {}
    for k, v in runs.items():
        v2 = sorted(v)
        stats[k] = {"n": len(v2), "min": v2[0], "median": v2[len(v2) // 2], "max": v2[-1], "all": v2[:40]}
    return stats


def log_errors(path: Path) -> list:
    out = []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return out
    for i, ln in enumerate(lines):
        if ln.startswith(("SCRIPT ERROR", "ERROR", "USER ERROR", "USER SCRIPT ERROR")) or "Parse Error" in ln:
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            out.append(ln.strip() + (" | " + nxt if nxt.startswith("at:") else ""))
    return out


def log_spider_lines(path: Path) -> list:
    out = []
    try:
        for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if SPIDER_RE.search(ln) and not ln.startswith("==== launch"):
                out.append(ln.strip()[:240])
    except OSError:
        pass
    return out[:60]


def analyze() -> dict:
    summary: dict = {"generated": time.strftime("%Y-%m-%d %H:%M:%S"), "runs": {}, "enemy_display": enemy_display_table()}
    for rd in sorted(RUN_ROOT.glob("*_*")):
        if not rd.is_dir() or not (rd / "result.json").exists():
            continue
        res = json.loads((rd / "result.json").read_text(encoding="utf-8"))
        name = rd.name
        tele = next(iter(rd.glob("*_telemetry.jsonl")), None)
        glog = next(iter(rd.glob("*_godot.log")), None)
        entry: dict = {"scenario": res.get("scenario"), "start": res.get("start"), "error": res.get("error")}
        if tele:
            entry["scan"] = scan_telemetry(tele, res.get("toggles", []))
            words = {"matron": ("weaver",), "works": ("matron", "crossing"), "choir": ("choir",), "velour": ("velour",)}
            for k, w in words.items():
                if name.startswith(k):
                    entry["boss_states"] = state_durations(tele, w)
        if glog:
            entry["log_errors"] = log_errors(glog)
            entry["log_spider_lines"] = log_spider_lines(glog)
        summary["runs"][name] = entry
    # timing-assist baselines from the natural chain runs (timing_assist OFF, Standard)
    base = {}
    for run in ("run3", "run4"):
        t = ROOT / "qa" / "tmp" / "bot" / "chain" / run / "g2_telemetry.jsonl"
        if t.exists():
            base[f"chain_{run}_velour"] = state_durations(t, ("velour",))
            base[f"chain_{run}_choir"] = state_durations(t, ("choir",))
    summary["chain_baselines"] = base
    write_json(RUN_ROOT / "summary.json", summary)
    return summary


# ================================================================================================ main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scenario", choices=["matron", "works", "choir", "velour", "analyze"])
    ap.add_argument("--attempt", type=int, default=1)
    ap.add_argument("--assist", choices=["on", "off"], default="off")
    ap.add_argument("--style", default="thorough", choices=["thorough", "fast"])
    ap.add_argument("--toggle-fallback", type=float, default=25.0, help="matron: toggle after N s of phase 2 when no minion shows")
    a = ap.parse_args()
    RUN_ROOT.mkdir(parents=True, exist_ok=True)
    if a.scenario == "matron":
        r = scenario_matron(a.attempt, a.style, a.toggle_fallback)
    elif a.scenario == "works":
        r = scenario_works(a.attempt)
    elif a.scenario == "choir":
        r = scenario_choir(a.attempt, a.assist == "on")
    elif a.scenario == "velour":
        r = scenario_velour(a.attempt, a.assist == "on")
    else:
        r = analyze()
        print(json.dumps({k: (v if k != "runs" else list(v)) for k, v in r.items() if k != "enemy_display"}, default=str)[:3000])
        return
    print(json.dumps({k: r.get(k) for k in ("scenario", "error", "boss_won", "choir_defeated", "status", "seconds", "probe",
                                            "checkpoints", "toggles")}, default=str, indent=1)[:6000])


if __name__ == "__main__":
    main()
