"""Coverage run "trials_expeditions" (MP 20.3 / 20.4 Run E): Echo Trials and Lanternwake Expeditions from a NATURAL
completed-chapter save, played with normal inputs only.

Start: a COPY of the chain run's final checkpoint (qa/tmp/bot/chain/run4/checkpoints/END_end/slot1.json - written
by the game itself at the end of the natural Chapter One -> Chapter Two chain: chapter two complete, free play at
the Haven). No fixtures, no debug flags (--flags / --give / --area are never passed), no teleports: the bot reads
the read-only QA telemetry and acts through the virtual keyboard / mouse (src/qa/qa_input.gd). Headless source
build (the working tree's game/), isolated --save-dir / --settings-file under the run folder, unique ports
8120.. (key index 1 * 20 + attempt), bounded by --max-seconds and the phase time budget, only our own process
tree is ever killed.

Phases (python tools/qa/ch2/cov_trials_expeditions.py --phase <name> [--start-save <slot1.json>] [--attempt N]):
  velour      Ward Stone -> Lantern Road -> Moonveil Manor -> front door -> ballroom rest candles (origin) -> the
              echo stone: menu, enter / leave by the pale door, WIN (first clear), WIN (repeat: gift paid on
              arrival), quit to title inside -> Continue, LOSE (let the Count win), save diffs after every visit.
  choir       Ward Stone -> Lantern Road -> the Reach -> refuge hatch -> the Works -> Bell Throat (origin) -> the
              echo stone: enter, leave through the pause menu, quit the PROCESS inside -> relaunch -> Continue.
  matron      Surface -> mine -> the Below -> the arena checkpoint (origin) -> the echo stone: enter, leave.
  expedition  the Tailor's Cache (Loom + woven cloth), wood / stone / copper, furnace, copper bar, Expedition Board
              (crafted and placed at home), Orchard Patrol: set out, stops, cache, rewards once, save/quit
              mid-run -> relaunch -> Continue resumes the route, abandon / restart.
Every phase snapshots <run>/saves after each visit into <run>/checkpoints/<label>/ and writes <run>/result.json
(checks with expected / observed numbers) and appends game bugs to qa/tmp/bot/cov_trials_expeditions/bugs.json.

INFORMATION ADVANTAGE (label for reports): the bot knows authored coordinates (data/*_layout.gd, the trial arena
builders), reads enemy / boss states and hp from telemetry and reads the saves the game writes (read-only).
"""
from __future__ import annotations

import argparse
import hashlib
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
import s1_common as C  # noqa: E402
import s1_continuation as S1  # noqa: E402
import s3_manor as S3  # noqa: E402
import s4_route as S4R  # noqa: E402
from hhbot import angle_diff  # noqa: E402

KEY = "trials_expeditions"
KEY_INDEX = 1
RUN_ROOT = ROOT / "qa" / "tmp" / "bot" / f"cov_{KEY}"
BUGS_FILE = RUN_ROOT / "bugs.json"
GAME_DIR = ROOT / "game"
NATURAL_SAVE = ROOT / "qa" / "tmp" / "bot" / "chain" / "run4" / "checkpoints" / "END_end" / "slot1.json"
SURFACE, REACH, MANOR, WORKS, BELOW, TRIAL = "surface", "hallowmere_reach", "moonveil_manor", "hushed_works", "below", "echo_trial"


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def xz(p):
    return (p[0], p[2]) if len(p) >= 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def write_json(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=1, default=str), encoding="utf-8")


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16] if p.exists() else ""


class Stop(Exception):
    pass


# ============================================================================================ save diffs
def inv_totals(state: dict) -> dict:
    out: dict = {}
    for s in state.get("inventory", []) or []:
        if isinstance(s, dict) and s.get("id"):
            out[s["id"]] = out.get(s["id"], 0) + int(s.get("count", 0))
    return out


def save_diff(a: dict, b: dict) -> dict:
    """What changed between two saves the game wrote (story flags, ledger, trials, inventory, keys, chapter two,
    optional goals, quests, player place, expeditions)."""
    sa, sb = a.get("state", {}), b.get("state", {})
    fa, fb = set(k for k, v in (sa.get("flags") or {}).items() if v), set(k for k, v in (sb.get("flags") or {}).items() if v)
    la, lb = set((sa.get("ledger") or {}).keys()), set((sb.get("ledger") or {}).keys())
    ia, ib = inv_totals(sa), inv_totals(sb)
    ka, kb = sa.get("key_items") or {}, sb.get("key_items") or {}
    d = {
        "flags_added": sorted(fb - fa), "flags_removed": sorted(fa - fb),
        "ledger_added": sorted(lb - la), "ledger_removed": sorted(la - lb),
        "trials_before": sa.get("trials"), "trials_after": sb.get("trials"),
        "inv_delta": {k: ib.get(k, 0) - ia.get(k, 0) for k in set(ia) | set(ib) if ib.get(k, 0) != ia.get(k, 0)},
        "keys_delta": {k: int(kb.get(k, 0)) - int(ka.get(k, 0)) for k in set(ka) | set(kb) if kb.get(k, 0) != ka.get(k, 0)},
        "ch2_done_added": sorted(set((sb.get("chapter2") or {}).get("done", [])) - set((sa.get("chapter2") or {}).get("done", []))),
        "ch2_done_removed": sorted(set((sa.get("chapter2") or {}).get("done", [])) - set((sb.get("chapter2") or {}).get("done", []))),
        "optional_changed": sorted(k for k in set(sa.get("optional") or {}) | set(sb.get("optional") or {})
                                   if (sa.get("optional") or {}).get(k) != (sb.get("optional") or {}).get(k)),
        "quests_same": sa.get("quests") == sb.get("quests"),
        "player_before": {k: (sa.get("player") or {}).get(k) for k in ("area", "spawn", "respawn_area", "respawn_spawn")},
        "player_after": {k: (sb.get("player") or {}).get(k) for k in ("area", "spawn", "respawn_area", "respawn_spawn")},
        "expeditions_before": sa.get("expeditions"), "expeditions_after": sb.get("expeditions"),
        "wardrobe_changed": sa.get("wardrobe") != sb.get("wardrobe"),
        "structures_changed": sa.get("structures") != sb.get("structures"),
        "deaths": [(sa.get("stats") or {}).get("deaths"), (sb.get("stats") or {}).get("deaths")],
        "saved_unix": [a.get("saved_unix"), b.get("saved_unix")],
    }
    return d


def inv_timeline(tele_paths, items=("lantern_wax", "moonpetal", "woven_cloth")) -> list:
    """(area, counts of `items`) each time either changes, from the telemetry files (read-only post-analysis): shows
    whether an echo's gift reached the backpack inside the echo or only on arrival at the origin."""
    import re
    ra = re.compile(r'"area":"([a-z_]*)"')
    ri = re.compile(r'"inv":\{([^}]*)\}')
    rt = re.compile(r'"t":([0-9.]+)')
    out, prev = [], None
    for path in tele_paths:
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for ln in fh:
                a, iv = ra.search(ln), ri.search(ln)
                if not (a and iv):
                    continue
                inv = {}
                for x in iv.group(1).split(","):
                    if ":" in x:
                        k, v = x.split(":", 1)
                        try:
                            inv[k.strip('"')] = int(float(v))
                        except ValueError:
                            pass
                key = (Path(path).name, a.group(1)) + tuple(inv.get(i, 0) for i in items)
                if key != prev:
                    t = rt.search(ln)
                    out.append({"file": key[0], "game_t": float(t.group(1)) if t else None, "area": key[1],
                                **{i: key[2 + n] for n, i in enumerate(items)}})
                    prev = key
    return out


# ============================================================================================ the run
class Cov:
    def __init__(self, phase: str, attempt: int, start_save: Path, budget_min: float, seed: int | None):
        self.phase = phase
        self.attempt = attempt
        self.out = RUN_ROOT / f"{phase}_a{attempt}"
        if self.out.exists():
            shutil.rmtree(self.out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.save_dir = self.out / "saves"
        self.start_save = Path(start_save)
        self.cfg = SimpleNamespace(out=self.out, max_minutes=budget_min + 5, seed=seed, mute=True, headless=True, exe=None,
                                   godot=None, project=GAME_DIR, rect=None, dry_run=False)
        self.games: list = []
        self.game = None
        self.checks: list[dict] = []
        self.bugs: list[dict] = []
        self.notes: list[str] = []
        self.data: dict = {}
        self.t0 = time.time()
        self.deadline = self.t0 + budget_min * 60.0
        self._log = open(self.out / "cov.log", "a", encoding="utf-8")
        self.shots: list[dict] = []

    # ------------------------------------------------------------------ plumbing
    def log(self, msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] COV {msg}"
        print(line, flush=True)
        self._log.write(line + "\n")
        self._log.flush()
        try:
            if self.game is not None and self.game.bot is not None and self.game.bot.log_file:
                self.game.bot.log_file.write(line + "\n")
                self.game.bot.log_file.flush()
        except Exception:  # noqa: BLE001
            pass

    @property
    def bot(self):
        return self.game.bot

    def port(self) -> int:
        p = 8100 + KEY_INDEX * 20 + self.attempt + 3 * len(self.games)
        for _ in range(30):
            if CH.port_free(p):
                return p
            p += 1
        raise RuntimeError("no free port")

    def launch(self):
        g = CH.ChainGame(self.cfg, len(self.games) + 1, self.save_dir, self.port())
        self.games.append(g)
        self.game = g
        g.start()
        self.log(f"launched {g.name} pid={g.proc.pid} port={g.port}")
        self._players()
        return g

    def _players(self):
        out = self.out
        self.p1 = S1.Seg(self.bot, out, lambda label: self.shot(label)["path"])
        self.p4 = S4R.S4(self.game, out)
        self.s3 = TrialSeg(self.bot, out / "s3", optional=False, time_budget=max(60.0, self.deadline - time.time()))

    def stop_game(self):
        if self.game is not None:
            self.game.stop()

    def shot(self, label: str) -> dict:
        p = self.out / "shots" / f"{len(self.shots) + 1:03d}_{label}.png"
        rec = {"label": label, "path": str(p)}
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            self.game.vin.request({"shot": p.as_posix()}, timeout=10.0)
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001  (headless: refused, expected)
            rec["ok"] = False
            rec["error"] = str(e)[-120:]
        self.shots.append(rec)
        return rec

    def st(self) -> dict:
        try:
            return self.bot.state()
        except Exception:  # noqa: BLE001
            return {}

    def area(self) -> str:
        return str(self.st().get("area", ""))

    def pos(self):
        return (self.st().get("player") or {}).get("pos") or [0, 0, 0]

    def wait_playing(self, area=None, timeout: float = 90.0) -> bool:
        return self.bot.wait_state(lambda s: s.get("mode") == "playing" and not s.get("ui_stack")
                                   and (area is None or s.get("area") == area), timeout) is not None

    def msgs_since(self, t: float) -> list:
        return [m for m in self.st().get("messages", []) or [] if float(m.get("t", 0)) > t]

    def msg_t(self) -> float:
        return max([float(m.get("t", 0.0)) for m in self.st().get("messages", []) or []] + [-1.0])

    def save_json(self) -> dict:
        p = self.save_dir / "slot1.json"
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            self.log(f"save read failed: {e}")
            return {}

    def snapshot(self, label: str) -> Path:
        dst = self.out / "checkpoints" / label
        if dst.exists():
            shutil.rmtree(dst)
        if self.save_dir.exists():
            shutil.copytree(self.save_dir, dst)
        return dst / "slot1.json"

    def check(self, name: str, ok: bool, expected: str, observed, evidence=None, kind: str = "natural"):
        rec = {"check": name, "result": "PASS" if ok else "FAIL", "kind": kind, "expected": expected,
               "observed": observed, "evidence": evidence or [], "t": round(time.time() - self.t0, 1), "time": now()}
        self.checks.append(rec)
        self.log(f"CHECK {rec['result']}: {name} | observed: {json.dumps(observed, default=str)[:600]}")
        return ok

    def bug(self, title: str, severity: str, steps: str, expected: str, actual: str, evidence):
        rec = {"title": title, "severity": severity, "steps": steps, "expected": expected, "actual": actual,
               "evidence": evidence, "run": str(self.out), "phase": self.phase, "found": now()}
        self.bugs.append(rec)
        self.log(f"BUG ({severity}) {title}")

    def note(self, text: str):
        self.notes.append(text)
        self.log(f"NOTE {text}")

    def time_left(self) -> float:
        return self.deadline - time.time()

    # ------------------------------------------------------------------ common flows
    def prepare_save(self):
        self.save_dir.mkdir(parents=True, exist_ok=True)
        bak = self.start_save.with_name("slot1.bak.json")
        C.prepare_saves(self.save_dir, self.start_save, bak if bak.exists() else None)
        self.data["start_save"] = {"path": str(self.start_save), "sha": sha(self.start_save)}

    def title_continue(self) -> bool:
        if not self.bot.wait_state(lambda s: s.get("mode") == "title" and any(b.get("text") == "Continue" for b in s.get("buttons", [])), 120):
            raise Stop("no title / Continue")
        t0 = time.time()
        self.bot.click_button("Continue", exact=True, timeout=10)
        if not self.wait_playing(None, 120):
            # a card may be up (hint) - close it
            self.p1.close_panels()
            if not self.wait_playing(None, 30):
                raise Stop(f"Continue never reached gameplay (mode {self.st().get('mode')}, ui {self.st().get('ui_stack')})")
        self.data.setdefault("continue_s", []).append(round(time.time() - t0, 1))
        time.sleep(1.5)
        self.bot.calibrate_look()
        return True

    def close_cards(self):
        s = self.st()
        if s.get("ui_stack"):
            self.log(f"closing ui {s.get('ui_stack')} buttons {[b.get('text') for b in s.get('buttons', [])][:12]}")
            for label in ("Got it", "OK", "Close", "Not now", "Resume"):
                if self.bot.find_button(label):
                    self.bot.click_button(label, timeout=1.0)
                    time.sleep(0.4)
                    break
            self.p1.close_panels()

    def ward_stone_travel(self, dest: str, dest_area: str = REACH) -> bool:
        p1 = self.p1
        e = p1.nearest_named("WardStone", 60)
        if e is None:
            p1.goto((0.0, 4.0), tol=2.5, sprint=True, timeout=40)
            e = p1.nearest_named("WardStone", 60)
        if e is None:
            raise Stop(f"no Ward Stone near the Haven (at {p1.pos()})")
        if not p1.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p1.ui(), stop=2.2):
            raise Stop(f"the Ward Stone menu did not open (prompt {p1.prompt()})")
        if not p1.wait_button("Travel the Lantern Road", 5):
            raise Stop(f"no 'Travel the Lantern Road' {[b['text'] for b in self.bot.buttons()]}")
        self.bot.click_button("Travel the Lantern Road", exact=True)
        opts = p1.wait_button(dest, 5) or [b.get("text") for b in self.bot.buttons()]
        self.log(f"Lantern Road list at the Ward Stone: {opts}")
        self.data.setdefault("lantern_road_lists", []).append(opts)
        if not self.bot.click_button(dest, exact=True):
            self.p1.close_panels()
            raise Stop(f"no {dest!r} in the Lantern Road list {opts}")
        if not self.wait_playing(dest_area, 120):
            raise Stop(f"did not arrive in {dest_area}")
        time.sleep(1.5)
        self.bot.calibrate_look()
        return True

    def pause_quit_to_title(self) -> dict:
        """Pause -> Quit to Title -> whatever the confirm offers (trials: 'Quit to Title', no save)."""
        rec = {}
        if not self.p1.open_pause():
            raise Stop("pause menu did not open")
        if not self.bot.click_button("Quit to Title", exact=True, timeout=4):
            raise Stop("no Quit to Title")
        time.sleep(0.8)
        rec["confirm_buttons"] = [b.get("text") for b in self.bot.buttons()]
        labels = [b.get("text") for b in self.bot.buttons()]
        # the confirm repeats the pause panel's "Quit to Title": press the dialog's one (listed last)
        for label in ("Quit without saving", "Quit to Title"):
            if label in labels and (label != "Quit to Title" or labels.count(label) >= 2):
                rec["chose"] = label
                self.click_last(label, timeout=3)
                break
        ok = self.bot.wait_state(lambda s: s.get("mode") == "title", 30) is not None
        rec["at_title"] = ok
        return rec

    def click_last(self, text: str, timeout: float = 4.0) -> bool:
        """Clicks the LAST listed enabled button with exactly this text (a confirm dialog sits after the panel that
        opened it in the telemetry's tree order, and may repeat that panel's button text)."""
        s = self.bot.wait_state(lambda st: any(b.get("text") == text and not b.get("disabled") for b in st.get("buttons", [])), timeout)
        if not s:
            return False
        b = [b for b in s["buttons"] if b.get("text") == text and not b.get("disabled")][-1]
        cx, cy = C.button_center(b)
        self.bot.win.click(cx, cy)
        time.sleep(0.3)
        return True

    def tele_flags(self) -> set:
        return set(self.st().get("flags", []) or [])

    def pause_leave_trial(self) -> dict:
        rec = {}
        if not self.p1.open_pause():
            raise Stop("pause menu did not open")
        time.sleep(0.4)
        rec["pause_buttons"] = [b.get("text") for b in self.bot.buttons()]
        if not self.bot.click_button("Leave the trial", exact=True, timeout=4):
            rec["error"] = "no 'Leave the trial' in the pause menu"
            self.p1.close_panels()
            return rec
        time.sleep(0.8)
        rec["confirm_buttons"] = [b.get("text") for b in self.bot.buttons()]
        self.click_last("Leave the trial", timeout=3)
        return rec

    def pause_quit_game(self) -> dict:
        """Pause -> Quit Game -> the confirm's quit choice (inside a trial: 'Quit', no save offered) -> process exit."""
        rec = {}
        if not self.p1.open_pause():
            raise Stop("pause menu did not open")
        if not self.bot.click_button("Quit Game", exact=True, timeout=4):
            raise Stop("no Quit Game")
        time.sleep(0.8)
        rec["confirm_buttons"] = [b.get("text") for b in self.bot.buttons()]
        for label in ("Quit", "Quit without saving"):
            if self.p1.button(label):
                rec["chose"] = label
                self.click_last(label, timeout=3)
                break
        rec["exited"] = self.game.wait_exit(30.0)
        return rec

    def relaunch(self):
        old = self.game
        if old is not None:
            if old.alive() and not old.wait_exit(3.0):
                self.log(f"{old.name} still running before the relaunch: stopping it")
            old.stop()
        self.launch()

    def save_after(self, t_msg: float, timeout: float = 12.0) -> bool:
        return self.bot.wait_state(lambda s: any(m.get("k") == "saved" and float(m.get("t", 0)) > t_msg and "FAILED" not in m.get("text", "")
                                                 for m in s.get("messages", [])), timeout) is not None

    # ------------------------------------------------------------------ Echo Trials (shared)
    def trial_enter(self, stone_pos, stand, words=("Echo Trial",), label: str = "") -> dict:
        """At the echo stone: read the prompt, open the trial menu, record its buttons, 'Enter the echo'."""
        rec = {"label": label}
        p4 = self.p4
        if stand is not None:
            p4.goto((stand[0], stand[-1]), tol=0.5, sprint=False, timeout=30)
        ok = p4.interact_with(stone_pos, list(words), check=lambda: "confirm" in p4.ui(), stop=1.2, tries=6)
        rec["prompt_seen"] = self.data.get("_last_prompt")
        if not ok:
            rec["error"] = f"the echo stone menu did not open (prompt {p4.prompt()})"
            return rec
        time.sleep(0.6)
        rec["menu_buttons"] = [b.get("text") for b in self.bot.buttons()]
        save_before = self.save_dir / "slot1.json"
        rec["save_sha_before"] = sha(save_before)
        t_msg = self.msg_t()
        rec["flags_before"] = self.tele_flags()       # right before the echo (visit_diff)
        if not self.bot.click_button("Enter the echo", exact=True, timeout=4):
            rec["error"] = "no 'Enter the echo'"
            self.p1.close_panels()
            return rec
        t_in = time.time()
        if not self.wait_playing(TRIAL, 90):
            rec["error"] = f"did not arrive in the echo (area {self.area()}, mode {self.st().get('mode')})"
            return rec
        rec["load_s"] = round(time.time() - t_in, 1)
        time.sleep(1.2)
        rec["arrival_pos"] = self.pos()
        rec["arrival_msgs"] = [f"[{m.get('k')}] {m.get('text')}" for m in self.msgs_since(t_msg)]
        rec["save_sha_after_arrival"] = sha(save_before)
        rec["saved_on_arrival"] = rec["save_sha_after_arrival"] != rec["save_sha_before"]
        self.bot.calibrate_look()
        return rec

    def trial_leave_door(self) -> dict:
        """Walk to the pale door at the end of the corridor (z 27.86) and use it."""
        rec = {}
        t_msg = self.msg_t()
        self.p4.goto((0.0, 25.4), tol=0.6, sprint=False, timeout=25)
        ok = self.p4.interact_with((0.0, 1.0, 27.86), ["Leave the echo"], check=lambda: self.st().get("mode") != "playing" or self.area() != TRIAL,
                                   stop=1.4, tries=6)
        rec["door_used"] = ok
        rec["prompt"] = self.p4.prompt()
        return rec | self.trial_arrival(t_msg)

    def trial_arrival(self, t_msg: float, origin_area: str = "") -> dict:
        rec = {}
        ok = self.bot.wait_state(lambda s: s.get("mode") == "playing" and s.get("area") not in (TRIAL, ""), 90) is not None
        rec["returned"] = ok
        time.sleep(2.5)
        s = self.st()
        rec["area"] = s.get("area")
        rec["pos"] = (s.get("player") or {}).get("pos")
        rec["hp"] = (s.get("player") or {}).get("hp")
        rec["msgs"] = [f"[{m.get('k')}] {m.get('text')}" for m in self.msgs_since(t_msg)]
        rec["saved"] = any(m.get("k") == "saved" for m in self.msgs_since(t_msg))
        rec["inv"] = s.get("inv")
        return rec


# ============================================================================================ Velour in the echo
# The trial arena is the real Gallery relative to its centre (data/manor_layout.gd ARENA centre (0, 0, -64.5));
# the pale pad is at z 21.8 and the pale door at z 27.86 (src/world/trial/velour_trial.gd).
SHIFT_Z = 64.5
T_CANDLES = {k: (v[0], v[1] + SHIFT_Z) for k, v in S3.CANDLES.items()}
T_COVER = [(c[0], c[1] + SHIFT_Z) for c in S3.COVER]
T_LANE_SAFE = [(c[0], c[1] + SHIFT_Z) for c in S3.LANE_SAFE_SPOTS]
T_PHASE1 = [(c[0], c[1] + SHIFT_Z) for c in S3.PHASE1_SPOTS]
T_ARENA_C = (0.0, 0.0)
T_PAD = (0.0, 21.8)


class TrialSeg(S3.Segment):
    """s3_manor's Segment (manor navigation, the Velour fight rules) with the Echo Trial names and coordinates."""

    boss_name = "EchoVelour"

    def velour(self):
        return self.enemy(self.boss_name) if self.area() == TRIAL else self.enemy("CountVelour")

    def _arena_candle_entries(self) -> dict:
        prefix = "EchoCandle_" if self.area() == TRIAL else "WardCandle_"
        out = {}
        for e in self.nearby(lambda n: n.get("g") == "interactable" and n.get("name", "").startswith(prefix), 40):
            out[e["name"].replace(prefix, "")] = e
        return out

    def patch_trial(self, on: bool):
        """Point the s3_manor module constants at the echo Gallery while fighting there (and back)."""
        if on:
            self._saved = (S3.CANDLES, S3.COVER, S3.LANE_SAFE_SPOTS, S3.PHASE1_SPOTS, S3.ARENA_C)
            S3.CANDLES, S3.COVER, S3.LANE_SAFE_SPOTS, S3.PHASE1_SPOTS, S3.ARENA_C = T_CANDLES, T_COVER, T_LANE_SAFE, T_PHASE1, T_ARENA_C
        elif getattr(self, "_saved", None):
            S3.CANDLES, S3.COVER, S3.LANE_SAFE_SPOTS, S3.PHASE1_SPOTS, S3.ARENA_C = self._saved
            self._saved = None

    def trial_fight(self, timeout: float = 420.0, lose: bool = False) -> dict:
        """The Count in the echo: s3_manor's boss_fight rules on the echo Gallery. lose=True: stand in the hall
        without dodging or striking (a deliberate defeat). Returns {"outcome": won|lost|left|timeout, ...}."""
        self.patch_trial(True)
        try:
            return self._trial_fight(timeout, lose)
        finally:
            self.patch_trial(False)
            self.bot.release_all()

    def _trial_fight(self, timeout: float, lose: bool) -> dict:
        t0 = time.time()
        rec = {"outcome": "timeout", "phases": [], "hp_min": 100.0, "hits": 0, "dodges0": self.fight["dodges"],
               "strikes0": self.fight["strikes"], "trace": []}
        dodged_bow_t = -1.0
        last_state = ""
        last_phase = 0
        last_log = 0.0
        last_hp = self.hp()
        engaged_t = None
        self.new_messages()
        while time.time() - t0 < timeout:
            s = self.st()
            if s.get("mode") == "dead":
                rec["outcome"] = "lost"
                rec["seconds"] = round(time.time() - t0, 1)
                return rec
            if s.get("area") != TRIAL:
                rec["outcome"] = "left_area"
                rec["seconds"] = round(time.time() - t0, 1)
                return rec
            hp_now = self.hp()
            rec["hp_min"] = min(rec["hp_min"], hp_now)
            if hp_now < last_hp - 0.5:
                rec["hits"] += 1
            last_hp = hp_now
            if s.get("ui_stack"):
                self.handle_interrupts()
                continue
            msgs = self.new_messages()
            bow_t = None
            for m in msgs:
                txt = m.get("text", "")
                mt = float(m.get("t", 0.0))
                if m.get("k") == "notify" and ("The echo remembers you" in txt or "echo's gift waits" in txt or "The echo remembers" in txt):
                    rec["win_msg"] = txt
                if m.get("k") == "caption" and ("sweeps into a bow" in txt or "crown flashes" in txt):
                    bow_t = mt
                elif m.get("k") == "caption" and "rush of velvet" in txt and mt - max(dodged_bow_t, bow_t or -1.0) > 2.0:
                    bow_t = mt
            v = self.velour()
            if v is not None:
                stt = v.get("state", "")
                ph = int(v.get("phase", 0) or 0)
                if engaged_t is None and stt not in ("dormant", "idle", ""):
                    engaged_t = time.time()
                if stt in ("defeat", "gone") or float(v.get("hp", 1) or 0) <= 0:
                    rec["outcome"] = "won"
                    rec["seconds"] = round(time.time() - t0, 1)
                    rec["fight_seconds"] = round(time.time() - (engaged_t or t0), 1)
                    rec["final_state"] = stt
                    return rec
                if ph and ph != last_phase:
                    last_phase = ph
                    rec["phases"].append({"phase": ph, "t": round(time.time() - t0, 1), "hp": v.get("hp")})
                    self.log(f"Echo Velour phase {ph} (hp {v.get('hp')})")
                if stt != last_state:
                    rec["trace"].append([round(time.time() - t0, 1), stt, v.get("hp"), round(self.hp(), 1)])
                    last_state = stt
                if time.time() - last_log > 5.0:
                    last_log = time.time()
                    self.log(f"echo velour {stt} hp={v.get('hp')} ph={ph} d={v.get('dist')} | me hp={self.hp()} at {self.me()}")
            else:
                stt, ph = "", last_phase
                if rec.get("win_msg"):
                    rec["outcome"] = "won"
                    rec["seconds"] = round(time.time() - t0, 1)
                    return rec
            if lose:
                # stand still in the middle of the hall, facing him; never dodge, never strike, never eat
                if dist2(self.me(), (0.0, 1.0)) > 1.5:
                    self.go((0.0, 1.0), tol=0.8, sprint=False, timeout=6.0, react=False)
                time.sleep(0.2)
                continue
            if self.me()[1] > 12.5:
                # still in the corridor (or pushed there): walk into the Gallery (he wakes inside his radius)
                self.go(self.nearest_spot(T_PHASE1), tol=0.6, react=False, timeout=12)
                continue
            if bow_t is not None and bow_t > dodged_bow_t and v is not None:
                dodged_bow_t = bow_t
                self.sidestep_from(xz(v["pos"]), 0.85, prefer_center=T_ARENA_C)
                self.fight["dodges"] += 1
                continue
            if v is None:
                self.go(self.nearest_spot(T_PHASE1), tol=0.6, react=False, timeout=6)
                time.sleep(0.3)
                continue
            if stt in S3.DASH_STATES:
                if dodged_bow_t < 0 or float(s.get("t", 0)) - dodged_bow_t > 2.5:
                    dodged_bow_t = float(s.get("t", 0))
                    self.sidestep_from(xz(v["pos"]), 0.85, prefer_center=T_ARENA_C)
                    self.fight["dodges"] += 1
                else:
                    time.sleep(0.05)
                continue
            if stt in S3.BAT_STATES:
                spot = self.nearest_spot(T_LANE_SAFE)
                if dist2(self.me(), spot) > 0.3:
                    self.go(spot, tol=0.25, sprint=True, timeout=4.0, react=False, precise=True)
                else:
                    time.sleep(0.1)
                continue
            if stt in ("drain_tele", "drain"):
                vd = dist2(self.me(), xz(v["pos"]))
                if vd < 4.5:
                    self.strike_at(self.boss_name, S3.WINDOW_STATES, 2.5)
                else:
                    lit = [k for k in T_CANDLES if k not in self.dark_candles()]
                    if lit:
                        k = min(lit, key=lambda c: dist2(self.me(), T_CANDLES[c]))
                        c = T_CANDLES[k]
                        tgt = (c[0] + (self.me()[0] - c[0]) * 0.4, c[1] + (self.me()[1] - c[1]) * 0.4)
                        self.go(tgt, tol=0.6, sprint=True, timeout=3.0, react=False)
                        self.fight["pool_breaks"] += 1
                continue
            if stt in ("channel_fly", "channel"):
                if stt == "channel" or dist2(self.me(), xz(v["pos"])) > 3.0:
                    self.strike_at(self.boss_name, {"channel_fly", "channel", "stagger", "channel_rest"}, 4.5)
                continue
            if stt in S3.WINDOW_STATES:
                self.strike_at(self.boss_name, S3.WINDOW_STATES, 3.5)
                continue
            if ph >= 3:
                dark = self.dark_candles()
                if dark:
                    k = min(dark, key=lambda c: dist2(self.me(), T_CANDLES[c]))
                    self.relight(k)
                    continue
            if self.hp() < 55 and stt in ("glide", "transition", "intro", "dormant"):
                self.eat()
            spots = T_PHASE1 if ph <= 1 else T_LANE_SAFE
            spot = self.nearest_spot(spots)
            if dist2(self.me(), spot) > 0.5:
                self.go(spot, tol=0.3 if ph >= 2 else 0.5, sprint=True, timeout=3.0, react=False, precise=ph >= 2)
            else:
                self.face(xz(v["pos"]))
                time.sleep(0.1)
        rec["seconds"] = round(time.time() - t0, 1)
        return rec


def heal(cv: Cov, target: float = 90.0, max_items: int = 6) -> list:
    """Eat from the backpack (inventory panel -> Eat) until hp >= target. Returns what was eaten."""
    eaten = []
    for _ in range(max_items):
        hp = float((cv.st().get("player") or {}).get("hp", 100.0))
        if hp >= target:
            break
        inv0 = dict(cv.st().get("inv") or {})
        if not cv.p4.eat_best():
            break
        inv1 = dict(cv.st().get("inv") or {})
        eaten.append({k: inv0.get(k, 0) - inv1.get(k, 0) for k in inv0 if inv0.get(k, 0) > inv1.get(k, 0)})
        time.sleep(0.4)
    if eaten:
        cv.log(f"healed: {eaten} -> hp {(cv.st().get('player') or {}).get('hp')}")
        cv.data.setdefault("eaten", []).extend(eaten)
    return eaten


# ============================================================================================ phase: velour
BALL_CP = S3.BALL_CP                  # (7.0, -33.2) the ballroom rest candles
BALL_CP_STAND = S3.BALL_CP_STAND
VELOUR_STONE = (8.6, 0.0, -34.6)      # data/manor_layout.gd ECHO_ENTRY
VELOUR_STONE_STAND = (7.3, -35.9)


def phase_velour(cv: Cov):
    s3 = cv.s3
    # ---- to the origin -------------------------------------------------------------------------------------
    if cv.area() == SURFACE:
        cv.ward_stone_travel("Moonveil Manor", REACH)
    if cv.area() == REACH:
        s3.calibrate()
        if not s3.route(S3.GROUNDS_PATH, tol=1.2):
            raise Stop(f"grounds path blocked at {cv.pos()}")
        if not s3.use("manor front door", ["Enter Moonveil Manor"], lambda: s3.area() == MANOR or s3.mode() == "loading",
                      S3.DOOR_STAND, S3.DOOR, stand_tol=0.5):
            raise Stop("front door")
    if not cv.wait_playing(MANOR, 60):
        raise Stop(f"not in the manor (area {cv.area()})")
    time.sleep(1.5)
    s3.handle_interrupts()
    s3.calibrate()
    t_msg = cv.msg_t()
    ok = s3.use("ballroom rest candles", ["Rest by the candles"], lambda: cv.save_after(t_msg, 0.5), BALL_CP_STAND, BALL_CP)
    cv.check("velour.origin_rest", ok, "resting at the ballroom candles saves (the trial origin)",
             {"pos": cv.pos(), "area": cv.area(), "saved": ok})
    time.sleep(1.0)
    origin_save = cv.save_json()
    cv.snapshot("velour_origin")
    cv.data["velour_origin_player"] = (origin_save.get("state") or {}).get("player")

    def enter(label):
        heal(cv, 90.0)
        cv.s3.new_messages()
        e = cv.trial_enter(VELOUR_STONE, VELOUR_STONE_STAND, ("Echo Trial",), label)
        cv.log(f"enter {label}: { {k: v for k, v in e.items() if k != 'flags_before'} }")
        if e.get("error"):
            raise Stop(f"{label}: {e['error']}")
        return e

    # ---- 1) enter and leave by the pale door ------------------------------------------------------------------
    cv.data["_fb_velour_leave"] = cv.tele_flags()
    e1 = enter("velour_leave_door")
    cv.data["velour_menu_buttons"] = e1.get("menu_buttons")
    cv.check("velour.enter_no_save", not e1["saved_on_arrival"], "entering the echo writes no save (trials never save)",
             {"sha_before": e1["save_sha_before"], "sha_after": e1["save_sha_after_arrival"]})
    cv.check("velour.arrival_on_pad", dist2(xz(e1["arrival_pos"]), T_PAD) < 2.0, "arrival on the pale pad (0, 21.8)",
             {"pos": e1["arrival_pos"], "msgs": e1["arrival_msgs"]})
    before = cv.save_json()
    fb = e1.get("flags_before") or cv.data.pop("_fb_velour_leave", set())
    r = cv.trial_leave_door()
    after = cv.save_json()
    d = save_diff(before, after)
    vd = visit_diff(cv, fb, before)
    cv.data["velour_leave_visit_diff"] = vd
    cv.log(f"leave door: {r} diff {d}")
    ok = r["returned"] and r["area"] == MANOR and dist2(xz(r["pos"] or [0, 0, 0]), BALL_CP) < 4.0
    cv.check("velour.leave_door_returns_to_origin", ok, "the pale door returns to the ballroom candles (manor, within 4 m)",
             {"area": r["area"], "pos": r["pos"], "dist_to_candles": round(dist2(xz(r["pos"] or [0, 0, 0]), BALL_CP), 2)})
    # food eaten by the bot before entering (heal) is not an echo effect: only GAINED items count
    unchanged = not vd["tele_story_flags_added"] and not d["flags_removed"] and not d["ledger_added"] and \
        not any(v > 0 for v in d["inv_delta"].values()) and not (after.get("state") or {}).get("trials")
    cv.check("velour.leave_no_change", unchanged,
             "leaving: no story flag (telemetry flags just before entering vs after the return; hint_* UI flags ignored), "
             "no ledger / item / trial record change in the save written on the return",
             {"tele_flags_added": vd["tele_flags_added"], "save_flags_added": d["flags_added"], "flags_removed": d["flags_removed"],
              "ledger_added": d["ledger_added"], "inv_delta": d["inv_delta"], "trials_after": d["trials_after"]})
    cv.snapshot("velour_after_leave")

    # ---- 2) win: the first clear ------------------------------------------------------------------------------
    results = {}
    for n in range(1, int(cv.data.get("wins", 2)) + 1):
        if cv.time_left() < 240:
            cv.note(f"time budget: skipped win #{n}")
            break
        before = cv.save_json()
        fbw = cv.tele_flags()
        e = enter(f"velour_win{n}")
        t_msg = cv.msg_t()
        cv.s3.go(T_PHASE1[0], tol=0.8, react=False, timeout=15)
        f = cv.s3.trial_fight(timeout=min(480.0, cv.time_left() - 60))
        cv.log(f"win #{n} fight: {f}")
        if f["outcome"] != "won":
            cv.check(f"velour.win{n}", False, "the bot wins the echo fight", f)
            if f["outcome"] == "lost":
                cv.trial_arrival(t_msg)
            else:
                cv.pause_leave_trial()
                cv.trial_arrival(t_msg)
            break
        # the automatic return (RETURN_DELAY 6 s)
        r = cv.trial_arrival(t_msg)
        after = cv.save_json()
        d = save_diff(before, after)
        vdw = visit_diff(cv, e.get("flags_before") or fbw, before)
        results[n] = {"tele_flags_added": vdw["tele_flags_added"], "fight": {k: f.get(k) for k in ("seconds", "fight_seconds", "hp_min", "hits", "phases", "win_msg")},
                      "return": r, "diff": d}
        cv.snapshot(f"velour_after_win{n}")
        tr = ((after.get("state") or {}).get("trials") or {}).get("velour") or {}
        all_msgs = r["msgs"]
        clears_before = int((((before.get("state") or {}).get("trials") or {}).get("velour") or {}).get("clears", 0))
        clears = clears_before + 1
        if clears == 1:
            first_ok = vdw["tele_story_flags_added"] == ["ch2_trial_velour"] and d["ledger_added"] == ["rw_trial_velour_first"] and not d["flags_removed"]
            cv.check("velour.first_clear_reward_once", first_ok,
                     "first clear: exactly flag ch2_trial_velour + ledger rw_trial_velour_first; no other flag; no items",
                     {"tele_flags_added": vdw["tele_flags_added"], "save_flags_added": d["flags_added"], "ledger_added": d["ledger_added"],
                      "inv_delta": d["inv_delta"], "trial": tr, "msgs": all_msgs})
            cv.check("velour.first_clear_record", int(tr.get("clears", 0)) == 1 and "pending" not in tr,
                     "trials.velour = {clears 1, best_seconds > 0}, nothing pending", tr)
        else:
            # data/trials.gd: repeat {lantern_wax 2, moonpetal 2}; every 3rd clear adds woven_cloth 1
            want = {"lantern_wax": 2, "moonpetal": 2}
            if clears % 3 == 0:
                want["woven_cloth"] = 1
            paid_ok = all(d["inv_delta"].get(k, 0) == v for k, v in want.items()) and                 not vdw["tele_story_flags_added"] and not d["ledger_added"]
            paid_before = (((before.get("state") or {}).get("trials") or {}).get("velour") or {}).get("paid") or {}
            want_paid = {k: int(paid_before.get(k, 0)) + int(want.get(k, 0)) for k in set(paid_before) | set(want)}
            cv.check(f"velour.repeat_reward_paid_at_origin_clear{clears}", paid_ok,
                     f"clear #{clears}: {want} on arrival at the ballroom (not inside), no flag / ledger",
                     {"inv_delta": d["inv_delta"], "tele_flags_added": vdw["tele_flags_added"], "ledger_added": d["ledger_added"],
                      "trial": tr, "msgs": all_msgs})
            rp_before = int((((before.get("state") or {}).get("trials") or {}).get("velour") or {}).get("repeat_paid", 0))
            cv.check(f"velour.repeat_record_clear{clears}", int(tr.get("clears", 0)) == clears and int(tr.get("repeat_paid", 0)) == rp_before + 1
                     and (tr.get("paid") or {}) == want_paid and "pending" not in tr,
                     f"trials.velour clears {clears}, repeat_paid {rp_before + 1}, paid {want_paid}, no pending", tr)
        story_ok = not d["flags_removed"] and not d["ch2_done_added"] and not d["ch2_done_removed"] and d["quests_same"]
        cv.check(f"velour.win{n}_story_unchanged", story_ok, "story flags / chapter steps / quests unchanged by the echo",
                 {k: d[k] for k in ("flags_removed", "ch2_done_added", "ch2_done_removed", "quests_same")})
        back_ok = r["area"] == MANOR and dist2(xz(r["pos"] or [0, 0, 0]), BALL_CP) < 4.0
        cv.check(f"velour.win{n}_auto_return", back_ok, "after the win the echo returns Krystal to the ballroom candles",
                 {"area": r["area"], "pos": r["pos"]})
    cv.data["velour_wins"] = results

    # ---- 3) quit to title inside the echo -> Continue ---------------------------------------------------------
    if cv.time_left() > 150:
        before = cv.save_json()
        sha_before = sha(cv.save_dir / "slot1.json")
        enter("velour_quit_inside")
        cv.p4.goto((0.0, 16.0), tol=0.8, sprint=False, timeout=15)
        # the pause menu's Save Game inside the echo must refuse (Game.SAVE_REFUSALS)
        t_msg = cv.msg_t()
        sv = {}
        if cv.p1.open_pause():
            time.sleep(0.5)
            sb_btn = [b for b in cv.bot.buttons() if b.get("text") == "Save Game"]
            sv["save_button_disabled"] = bool(sb_btn and sb_btn[0].get("disabled"))
            sv["pressed"] = False if sv["save_button_disabled"] else cv.bot.click_button("Save Game", exact=True, timeout=3)
            time.sleep(1.2)
            sv["msgs"] = [f"[{m.get('k')}] {m.get('text')}" for m in cv.msgs_since(t_msg)]
            sv["save_changed"] = sha(cv.save_dir / "slot1.json") != sha_before
            cv.p1.resume()
            time.sleep(0.5)
        cv.check("velour.save_refused_inside", (sv.get("save_button_disabled") or sv.get("pressed")) and not sv.get("save_changed")
                 and not any(m.startswith("[saved]") for m in sv.get("msgs", [])),
                 "pause Save Game inside the echo is disabled / writes nothing (Trials aren't saved)", sv)
        q = cv.pause_quit_to_title()
        cv.log(f"quit inside: {q}")
        sha_after = sha(cv.save_dir / "slot1.json")
        cv.title_continue()
        s = cv.st()
        rec = {"quit": q, "save_unchanged": sha_before == sha_after, "area": s.get("area"),
               "pos": (s.get("player") or {}).get("pos"), "mode": s.get("mode")}
        ok = rec["area"] == MANOR and dist2(xz(rec["pos"] or [0, 0, 0]), BALL_CP) < 4.0
        cv.check("velour.quit_inside_continue_at_origin", ok and rec["save_unchanged"],
                 "quitting to the title inside the echo writes no save; Continue resumes at the ballroom candles", rec)
        d = save_diff(before, cv.save_json())
        cv.data["velour_quit_inside"] = rec | {"diff": d}

    # ---- 4) lose: let the Count win --------------------------------------------------------------------------
    if cv.time_left() > 200:
        before = cv.save_json()
        sha_before = sha(cv.save_dir / "slot1.json")
        enter("velour_lose")
        t_msg = cv.msg_t()
        f = cv.s3.trial_fight(timeout=min(300.0, cv.time_left() - 60), lose=True)
        cv.log(f"lose: {f}")
        if f["outcome"] == "lost":
            r = cv.trial_arrival(t_msg)
            after = cv.save_json()
            d = save_diff(before, after)
            ok = r["area"] == MANOR and dist2(xz(r["pos"] or [0, 0, 0]), BALL_CP) < 4.0 and float(r.get("hp") or 0) >= 99.0
            cv.check("velour.lose_wakes_at_origin", ok, "a defeat in the echo wakes Krystal at the ballroom candles with full hp",
                     {"area": r["area"], "pos": r["pos"], "hp": r["hp"], "msgs": r["msgs"], "fight_s": f.get("seconds"),
                      "hits": f.get("hits")})
            tr_b = ((before.get("state") or {}).get("trials") or {}).get("velour")
            tr_a = ((after.get("state") or {}).get("trials") or {}).get("velour")
            cv.check("velour.lose_no_record_change", tr_a == tr_b and not d["flags_added"] and not d["inv_delta"],
                     "a defeat changes no trial record, flag or item", {"trial_before": tr_b, "trial_after": tr_a,
                                                                          "diff": {k: d[k] for k in ("flags_added", "inv_delta", "deaths", "saved_unix")},
                                                                          "save_rewritten": sha(cv.save_dir / 'slot1.json') != sha_before})
            cv.data["velour_lose"] = {"fight": f, "return": r, "diff": d}
        else:
            cv.check("velour.lose", False, "standing still in the echo Gallery ends in a defeat", f)
            if cv.area() == TRIAL:
                cv.pause_leave_trial()
                cv.trial_arrival(t_msg)
    cv.snapshot("velour_end")
    return True


def phase_velour_standdown(cv: Cov):
    """In the Velour echo: engage, wound him, step back onto the pale pad (he stands down after LEAVE_TIME outside
    radius + margin) -> his wounds are kept while she stays; walk in again (retry hint); then leave by the pause menu
    and enter again: the echo starts afresh (full hp)."""
    s3 = cv.s3
    if cv.area() != MANOR:
        raise Stop(f"velour_standdown starts in the manor (area {cv.area()})")
    s3.calibrate()
    heal(cv, 95.0)
    e = cv.trial_enter(VELOUR_STONE, VELOUR_STONE_STAND, ("Echo Trial",), "velour_standdown")
    if e.get("error"):
        raise Stop(e["error"])
    rec = {}
    s3.go(T_PHASE1[0], tol=0.8, react=False, timeout=15)
    f = s3.trial_fight(timeout=22.0)            # fight ~20 s: he takes some damage
    rec["fight1"] = {k: f.get(k) for k in ("outcome", "trace", "hp_min")}
    v = s3.velour()
    rec["hp_before_retreat"] = v and v.get("hp")
    rec["state_before_retreat"] = v and v.get("state")
    t_msg = cv.msg_t()
    s3.go(T_PAD, tol=0.6, sprint=True, timeout=15, react=False)
    t0 = time.time()
    gone = cv.bot.wait_state(lambda s: not any(n.get("g") == "enemy" and "Velour" in str(n.get("name", "")) for n in s.get("nearby", [])), 15.0)
    rec["stood_down_after_s"] = round(time.time() - t0, 1) if gone else None
    rec["pos_on_pad"] = cv.pos()
    time.sleep(1.0)
    s3.go(T_PHASE1[0], tol=0.8, react=False, timeout=15)
    re_v = cv.bot.wait_state(lambda s: any(n.get("g") == "enemy" and "Velour" in str(n.get("name", "")) for n in s.get("nearby", [])), 12.0)
    v2 = s3.velour()
    rec["hp_on_reengage"] = v2 and v2.get("hp")
    rec["msgs"] = [f"[{m.get('k')}] {m.get('text')}" for m in cv.msgs_since(t_msg)]
    rec["retry_hint"] = any("keeps his wounds" in m for m in rec["msgs"])
    cv.check("velour.standdown_keeps_wounds", bool(gone) and v2 is not None and rec["hp_before_retreat"] is not None
             and float(rec["hp_on_reengage"] or 0) <= float(rec["hp_before_retreat"]) + 0.1 and float(rec["hp_before_retreat"]) < 380.0,
             "stepping back onto the pad makes him stand down within ~4 s; walking in again resumes with his wounds kept", rec)
    t_msg = cv.msg_t()
    s3.go(T_PAD, tol=0.6, sprint=True, timeout=15, react=False)
    cv.bot.wait_state(lambda s: not any(n.get("g") == "enemy" and "Velour" in str(n.get("name", "")) for n in s.get("nearby", [])), 15.0)
    lv = cv.pause_leave_trial()
    r = cv.trial_arrival(t_msg)
    e2 = cv.trial_enter(VELOUR_STONE, VELOUR_STONE_STAND, ("Echo Trial",), "velour_afresh")
    s3.go(T_PHASE1[0], tol=0.8, react=False, timeout=15)
    cv.bot.wait_state(lambda s: any(n.get("g") == "enemy" and "Velour" in str(n.get("name", "")) for n in s.get("nearby", [])), 12.0)
    v3 = s3.velour()
    rec2 = {"leave": lv, "returned_to": [r.get("area"), r.get("pos")], "hp_after_reentry": v3 and v3.get("hp")}
    cv.check("velour.leave_and_reenter_starts_afresh", v3 is not None and float(v3.get("hp") or 0) >= 379.9,
             "after leaving the echo, a new visit starts the Count at full hp (380)", rec2)
    t_msg = cv.msg_t()
    s3.go(T_PAD, tol=0.6, sprint=True, timeout=15, react=False)
    cv.bot.wait_state(lambda s: not any(n.get("g") == "enemy" and "Velour" in str(n.get("name", "")) for n in s.get("nearby", [])), 15.0)
    cv.trial_leave_door()
    cv.data["velour_standdown"] = rec | {"afresh": rec2}
    return True


# ============================================================================================ phase: choir
CHOIR_STONE = (153.6, -28.0, 27.6)          # data/trials.gd TRIALS.choir.entry
CHOIR_STONE_STAND = (155.2, -28.0, 27.4)
THROAT_CP = (153.0, -28.0, 30.2)            # data/works_layout_deep.gd hw_bell_throat
THROAT_CP_STAND = (154.4, -28.0, 30.6)
REFUGE_HATCH = (24.0, 0.0, 2.0)             # the Reach hatch beside the Conservatory (s4_route step_free_play)
REFUGE_HATCH_STAND = (21.8, 0.0, 3.2)


def visit_diff(cv: Cov, flags_before: set, save_before: dict) -> dict:
    """What one trial visit changed: telemetry flags (around the visit) + the save written on the way back."""
    fa = cv.tele_flags()
    after = cv.save_json()
    d = save_diff(save_before, after)
    added = sorted(fa - flags_before)
    return {"tele_flags_added": added, "tele_flags_removed": sorted(flags_before - fa),
            "tele_story_flags_added": [f for f in added if not f.startswith("hint_")], "save": d}


def phase_choir(cv: Cov):
    p4 = cv.p4
    if cv.area() == SURFACE:
        cv.ward_stone_travel("Ward-Keeper's Conservatory", REACH)
    if cv.area() == REACH:
        p4.nav(REFUGE_HATCH_STAND, tol=1.6, final_tol=0.8)
        ok = p4.interact_with(REFUGE_HATCH, ["Climb down to the refuge"], check=lambda: p4.mode() != "playing" or p4.area() == WORKS, stop=1.4)
        if not ok:
            raise Stop(f"refuge hatch: prompt {p4.prompt()} at {p4.pos()}")
    if not cv.wait_playing(WORKS, 90):
        raise Stop(f"not in the Works (area {cv.area()})")
    time.sleep(1.5)
    cv.bot.calibrate_look()
    t_walk = time.time()
    if not p4.nav((154.0, -28.0, 33.5)):
        raise Stop(f"could not reach the Bell Throat (at {cv.pos()})")
    cv.data["choir_walk_refuge_to_throat_s"] = round(time.time() - t_walk, 1)
    t_msg = cv.msg_t()
    ok = p4.rest_lantern(THROAT_CP, stand=THROAT_CP_STAND)
    cv.check("choir.origin_rest", ok and cv.save_after(t_msg, 3), "resting at the Bell Throat lantern saves (the trial origin)",
             {"pos": cv.pos(), "area": cv.area()})
    p4.close_panels()
    time.sleep(1.0)
    cv.snapshot("choir_origin")

    # ---- 1) enter, leave through the pause menu -------------------------------------------------------------
    fb, sb = cv.tele_flags(), cv.save_json()
    e = cv.trial_enter(CHOIR_STONE, CHOIR_STONE_STAND, ("Echo Trial",), "choir_leave_pause")
    cv.log(f"enter choir: { {k: v for k, v in e.items() if k != 'flags_before'} }")
    if e.get("error"):
        raise Stop(e["error"])
    cv.data["choir_enter"] = {k: v for k, v in e.items() if k != "flags_before"}
    cv.check("choir.enter_no_save", not e["saved_on_arrival"], "entering the Choir echo writes no save",
             {"sha_before": e["save_sha_before"], "sha_after": e["save_sha_after_arrival"], "arrival": e["arrival_pos"]})
    cv.p4.goto((0.0, 14.0), tol=0.8, sprint=False, timeout=15)      # into the corridor mouth (not the vault)
    t_msg = cv.msg_t()
    lv = cv.pause_leave_trial()
    r = cv.trial_arrival(t_msg)
    vd = visit_diff(cv, fb, sb)
    cv.log(f"choir leave: {lv} {r} {vd}")
    ok = r["area"] == WORKS and dist2(xz(r["pos"] or [0, 0, 0]), xz(THROAT_CP)) < 5.0
    cv.check("choir.pause_leave_returns_to_origin", ok, "pause 'Leave the trial' returns to the Bell Throat lantern (within 5 m)",
             {"pause": lv, "area": r["area"], "pos": r["pos"], "saved_on_return": r["saved"],
              "dist": round(dist2(xz(r["pos"] or [0, 0, 0]), xz(THROAT_CP)), 2)})
    cv.check("choir.leave_no_story_change", not vd["tele_story_flags_added"] and not vd["save"]["inv_delta"]
             and not vd["save"]["ledger_added"] and not ((cv.save_json().get("state") or {}).get("trials") or {}).get("choir"),
             "leaving the Choir echo: no story flag, item, ledger or trial-record change", vd)
    cv.snapshot("choir_after_leave")

    # ---- 2) quit the PROCESS inside the echo -> relaunch -> Continue ------------------------------------------
    sha_b = sha(cv.save_dir / "slot1.json")
    sb = cv.save_json()
    e = cv.trial_enter(CHOIR_STONE, CHOIR_STONE_STAND, ("Echo Trial",), "choir_quit_process")
    if e.get("error"):
        raise Stop(e["error"])
    cv.p4.goto((0.0, 14.0), tol=0.8, sprint=False, timeout=15)
    q = cv.pause_quit_game()
    cv.log(f"quit game inside the Choir echo: {q}")
    sha_a = sha(cv.save_dir / "slot1.json")
    cv.relaunch()
    cv.title_continue()
    s = cv.st()
    rec = {"quit": q, "save_unchanged_by_quit": sha_a == sha_b, "area": s.get("area"),
           "pos": (s.get("player") or {}).get("pos"), "hp": (s.get("player") or {}).get("hp")}
    ok = rec["area"] == WORKS and dist2(xz(rec["pos"] or [0, 0, 0]), xz(THROAT_CP)) < 5.0
    cv.check("choir.quit_process_inside_continue_at_origin", ok and rec["save_unchanged_by_quit"] and bool(q.get("exited")),
             "Quit Game inside the echo writes no save, the process exits; relaunch + Continue resumes at the Bell Throat", rec)
    d = save_diff(sb, cv.save_json())
    cv.data["choir_quit_inside"] = rec | {"diff": d}
    cv.snapshot("choir_end")
    return True


# ---------------------------------------------------------------------------------- the Choir echo, fought
# src/world/trial/choir_trial.gd builds the vault "turned half round": trial = (C.x - x, y - C.y, C.z - z) for a real
# vault point (x, y, z), C = (157, -32, 65). RotTele shows the bot the echo in REAL vault coordinates (positions
# mapped back, yaw + 180), so s4_route's ChoirBot rules (anchors, resonator frames, perimeter) apply unchanged.
VAULT_C = (157.0, -32.0, 65.0)


def _to_real(p):
    if not isinstance(p, (list, tuple)) or len(p) < 3:
        return p
    return [round(VAULT_C[0] - p[0], 3), round(p[1] + VAULT_C[1], 3), round(VAULT_C[2] - p[2], 3)]


def _yaw180(y):
    if y is None:
        return y
    return ((float(y) + 180.0 + 180.0) % 360.0) - 180.0


class RotTele:
    """Wraps hhbot.Telemetry: inside the echo_trial area, positions / yaws are given in the real vault's frame."""

    def __init__(self, inner):
        self.inner = inner
        self.path = inner.path

    @property
    def last(self):
        return self._tf(self.inner.last)

    def poll(self):
        return self._tf(self.inner.poll())

    @staticmethod
    def _tf(s: dict) -> dict:
        if not s or s.get("area") != TRIAL:
            return s
        d = dict(s)
        if "pos" in d:
            d["pos"] = _to_real(d["pos"])
        pl = dict(d.get("player") or {})
        for k in ("pos", "cam_pos"):
            if k in pl:
                pl[k] = _to_real(pl[k])
        for k in ("cam_yaw", "facing_yaw"):
            if k in pl:
                pl[k] = _yaw180(pl[k])
        if isinstance(pl.get("focus"), dict):
            f = dict(pl["focus"])
            f["pos"] = _to_real(f.get("pos"))
            pl["focus"] = f
        d["player"] = pl
        d["nearby"] = [dict(e, pos=_to_real(e.get("pos"))) for e in (d.get("nearby") or [])]
        if isinstance(d.get("boss"), dict):
            d["boss"] = dict(d["boss"], pos=_to_real(d["boss"].get("pos")))
        d["companion_nodes"] = {k: dict(v, pos=_to_real(v.get("pos"))) for k, v in (d.get("companion_nodes") or {}).items()}
        return d


class ChoirTrialBot(S4R.ChoirBot):
    """s4_route's ChoirBot in the echo: the story flag is already set, so the end is read from the echo itself
    (the boss's defeat state / the echo's reward toast); a defeat or leaving the echo ends it too."""

    def run(self, timeout: float = 600.0) -> dict:
        import random
        p = self.p
        t0 = time.time()
        rng = random.Random(4)
        rec = {"outcome": "timeout", "phases": [], "hp_min": 100.0, "picks": self.picks}
        last_state, last_phase, last_log = "", 0, 0.0
        n0 = len(p.all_msgs)
        while time.time() - t0 < timeout:
            s = p.st()
            if s.get("mode") == "dead":
                rec["outcome"] = "lost"
                break
            if s.get("area") != TRIAL:
                rec["outcome"] = "left_area"
                break
            if s.get("mode") != "playing":
                time.sleep(0.3)
                continue
            if s.get("ui_stack"):
                p.close_panels()
                continue
            rec["hp_min"] = min(rec["hp_min"], p.hp())
            self.read_msgs()
            won_msg = [m.get("text") for m in p.all_msgs[n0:] if "The echo remembers you" in str(m.get("text", ""))
                       or "echo's gift waits" in str(m.get("text", ""))]
            me = p.pos()
            boss = next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "phase" in e), None)
            if won_msg or (boss is not None and (str(boss.get("state")) in ("defeat", "gone") or float(boss.get("hp", 1) or 0) <= 0)):
                rec["outcome"] = "won"
                rec["win_msg"] = won_msg[:1]
                break
            if boss is None:
                if dist2(xz(me), xz(S4R.VC)) > 9.5:
                    p.goto((157.0, 57.0), tol=1.0, sprint=True, timeout=10)
                time.sleep(0.3)
                continue
            st = str(boss.get("state", ""))
            ph = int(boss.get("phase", 1) or 1)
            if ph != last_phase:
                last_phase = ph
                rec["phases"].append({"phase": ph, "t": round(time.time() - t0, 1), "hp": boss.get("hp")})
            if st != last_state:
                self.log(f"  echo choir {last_state} -> {st} ph={ph} hp={boss.get('hp')} vuln={boss.get('vuln')} me={me} hp={p.hp()}")
                last_state = st
            if time.time() - last_log > 10:
                last_log = time.time()
                self.log(f"  echo choir t={time.time() - t0:.0f}s {st} ph {ph} hp={boss.get('hp')} me hp={p.hp()} res={self.res_prog} done={self.res_done}")
            if boss.get("vuln") or st.endswith("_exposed"):
                self.strike_boss(boss)
                continue
            if ph == 1:
                self.phase_a(s, st, me, rng)
            elif ph == 2:
                self.phase_b(s, st, me)
            else:
                self.phase_c(s, st, me)
        rec["seconds"] = round(time.time() - t0, 1)
        return rec


def phase_choir_win(cv: Cov):
    """From a save at the Bell Throat (e.g. choir_a5's checkpoints/choir_origin): read the order board in the echo,
    fight the Choir (s4_route rules, rotated frame), check the first-clear reward and the automatic return."""
    p4 = cv.p4
    if cv.area() != WORKS:
        raise Stop(f"choir_win starts at the Bell Throat (area {cv.area()})")
    heal(cv, 95.0)
    sb = cv.save_json()
    e = cv.trial_enter(CHOIR_STONE, CHOIR_STONE_STAND, ("Echo Trial",), "choir_win")
    if e.get("error"):
        raise Stop(e["error"])
    fb = e.get("flags_before") or set()
    # the bellmakers' order board in the corridor (faces +x at x -1.98, z 16)
    t_msg = cv.msg_t()
    p4.goto((-0.6, 16.0), tol=0.5, sprint=False, timeout=15)
    p4.interact_with((-1.98, 1.8, 16.0), ["Read the bellmakers' order"], check=lambda: any("bellmakers" in str(m.get("text", "")).lower()
                                                                                         for m in cv.msgs_since(t_msg)), stop=1.0, tries=4)
    order_txt = [m.get("text") for m in cv.msgs_since(t_msg) if "bellmakers" in str(m.get("text", "")).lower()]
    cv.data["choir_order_board"] = order_txt
    cv.p4.lantern(True)
    old_tele = cv.bot.tele
    cv.bot.tele = RotTele(old_tele)
    try:
        cb = ChoirTrialBot(p4)
        if order_txt:
            names = [w.lower() for w in __import__("re").findall(r"(Leaf|Moon|Key|Flame)", order_txt[0])]
            if len(names) == 4:
                cb.order = names
        t_msg = cv.msg_t()
        f = cb.run(min(600.0, cv.time_left() - 60))
    finally:
        cv.bot.tele = old_tele
        cv.bot.release_all()
    cv.log(f"echo choir fight: {f}")
    cv.data["choir_fight"] = f
    if f["outcome"] != "won":
        cv.check("choir.win", False, "the bot wins the Choir echo with normal inputs", f)
        if cv.area() == TRIAL:
            cv.pause_leave_trial()
        cv.trial_arrival(t_msg)
        return False
    r = cv.trial_arrival(t_msg)
    vd = visit_diff(cv, fb, sb)
    tr = ((cv.save_json().get("state") or {}).get("trials") or {}).get("choir") or {}
    cv.check("choir.win", True, "the bot wins the Choir echo with normal inputs", {k: f.get(k) for k in ("seconds", "phases", "hp_min", "win_msg", "picks")})
    ok = vd["tele_story_flags_added"] == ["ch2_trial_choir"] and vd["save"]["ledger_added"] == ["rw_trial_choir_first"] and \
        not vd["save"]["flags_removed"] and not any(v > 0 for v in vd["save"]["inv_delta"].values()) and int(tr.get("clears", 0)) == 1
    cv.check("choir.first_clear_reward_once", ok, "first Choir clear: flag ch2_trial_choir + ledger rw_trial_choir_first only, no item gained (food eaten in the fight excluded); trials.choir clears 1",
             {"visit": vd, "trial": tr, "return": {k: r[k] for k in ("area", "pos", "msgs")}})
    back = r["area"] == WORKS and dist2(xz(r["pos"] or [0, 0, 0]), xz(THROAT_CP)) < 5.0
    cv.check("choir.win_auto_return", back, "after the win the echo returns Krystal to the Bell Throat", {"area": r["area"], "pos": r["pos"]})
    cv.snapshot("choir_after_win")
    return True


# ============================================================================================ phase: matron
MINE_PATH = [(6, -12), (14, -22), (22, -30), (30, -40), (38, -50), (44, -58), (48, -63)]   # playthrough.PATHS["mine"]
LIFT_LANDING = (7.9, 0.0, 0.0)            # below_world.gd LiftLanding (role landing: "Ride the lift down")
MATRON_STONE = (101.1, -10.0, -112.4)     # below_world.gd ECHO_ENTRY_POS
MATRON_STONE_STAND = (102.6, -10.0, -111.6)
ARENA_CP = (100.9, -10.0, -115.5)         # the arena checkpoint lantern (playthrough light_cp)
CHAMBER_TO_ANTE = [(108.0, -12.0, -136.5), (106.5, -12.0, -131.0), (105.0, -12.0, -127.0), (105.0, -12.0, -122.0),
                   (105.0, -10.0, -118.5), (104.0, -10.0, -115.0)]


def phase_matron(cv: Cov):
    p1, p4 = cv.p1, cv.p4
    if cv.area() == SURFACE:
        # the Haven -> the mine path -> the Hollow Mine entrance
        here = xz(cv.pos())
        pts = MINE_PATH
        i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
        if dist2(here, (0.0, 4.0)) < 12:
            i = 0
        if not p4.route(pts[i:], tol=2.0, sprint=True, fight=True):
            raise Stop(f"mine path blocked at {cv.pos()}")
        ent = p4.nearest(lambda n: "enter the hollow mine" in str(n.get("text", "")).lower(), 25)
        if not ent:
            raise Stop(f"no mine entrance near {cv.pos()}")
        ok = p4.interact_with(ent, ["Enter the Hollow Mine"], check=lambda: p4.mode() != "playing" or bool(p4.ui()) or p4.area() == BELOW, stop=1.6)
        time.sleep(1.0)
        for label in ("Descend", "Continue", "Done", "Begin", "Enter"):
            if cv.bot.find_button(label):
                cv.bot.click_button(label)
                break
    if not cv.wait_playing(BELOW, 90):
        raise Stop(f"not in the Below (area {cv.area()}, ui {cv.st().get('ui_stack')})")
    time.sleep(1.5)
    cv.bot.calibrate_look()
    arrival = cv.pos()
    cv.data["below_arrival"] = arrival
    if dist2(xz(arrival), xz(ARENA_CP)) > 30:
        # the old lift down to the Heartseed Chamber (runs after the Weaver)
        t_msg = cv.msg_t()
        ok = p4.use(["Ride the lift down"], (5.8, 0.0, 0.0), LIFT_LANDING,
                    check=lambda: dist2(xz(cv.pos()), (116.2, -137.5)) < 12, stop=1.4, tries=6)
        cv.check("matron.lift_down", ok, "the mine landing lift rides down to the Heartseed Chamber", {"pos": cv.pos(), "prompt": p4.prompt()})
        if not ok:
            raise Stop("lift down")
        time.sleep(3.0)
        cv.bot.calibrate_look()
        if not p4.route([(p[0], p[2]) for p in CHAMBER_TO_ANTE], tol=1.0, sprint=False, fight=True):
            raise Stop(f"chamber to antechamber blocked at {cv.pos()}")
    t_msg = cv.msg_t()
    lantern = p4.nearest(lambda n: n.get("g") in ("checkpoint", "interactable") and "lantern" in str(n.get("text", "")).lower()
                         and dist2(xz(n["pos"]), xz(ARENA_CP)) < 3.0, 20)
    rest_ok = False
    if lantern:
        rest_ok = p4.interact_with(lantern, ["Rest", "Light"], check=lambda: cv.save_after(t_msg, 0.3), stop=1.4, tries=5)
    cv.check("matron.origin_rest", rest_ok, "resting at the arena checkpoint lantern saves (the trial origin)",
             {"pos": cv.pos(), "lantern": lantern and lantern.get("text")})
    time.sleep(1.0)
    cv.snapshot("matron_origin")

    fb, sb = cv.tele_flags(), cv.save_json()
    e = cv.trial_enter(MATRON_STONE, MATRON_STONE_STAND, ("Echo Trial",), "matron_leave_door")
    cv.log(f"enter matron: { {k: v for k, v in e.items() if k != 'flags_before'} }")
    if e.get("error"):
        raise Stop(e["error"])
    cv.data["matron_enter"] = {k: v for k, v in e.items() if k != "flags_before"}
    cv.check("matron.enter_no_save", not e["saved_on_arrival"], "entering the Matron echo writes no save",
             {"sha_before": e["save_sha_before"], "sha_after": e["save_sha_after_arrival"], "arrival": e["arrival_pos"]})
    r = cv.trial_leave_door()
    vd = visit_diff(cv, fb, sb)
    cv.log(f"matron leave: {r} {vd}")
    ok = r["area"] == BELOW and dist2(xz(r["pos"] or [0, 0, 0]), (103.0, -114.0)) < 4.0
    cv.check("matron.leave_door_returns_to_origin", ok, "the pale door returns to the arena checkpoint (cp_arena (103, -114))",
             {"area": r["area"], "pos": r["pos"], "saved_on_return": r["saved"]})
    cv.check("matron.leave_no_story_change", not vd["tele_story_flags_added"] and not vd["save"]["inv_delta"] and not vd["save"]["ledger_added"],
             "leaving the Matron echo: no story flag, item or ledger change; weaver_defeated kept",
             vd | {"weaver_defeated": "weaver_defeated" in cv.tele_flags()})
    cv.snapshot("matron_after_leave")
    # a defeat in the Matron echo (stand still in her chamber)
    if cv.time_left() > 240:
        fb, sb = cv.tele_flags(), cv.save_json()
        e = cv.trial_enter(MATRON_STONE, MATRON_STONE_STAND, ("Echo Trial",), "matron_lose")
        if e.get("error"):
            raise Stop(e["error"])
        t_msg = cv.msg_t()
        cv.p4.goto((0.0, 4.0), tol=1.0, sprint=False, timeout=20)
        t0 = time.time()
        died = cv.bot.wait_state(lambda s: s.get("mode") == "dead" or s.get("area") != TRIAL, min(240.0, cv.time_left() - 60)) is not None
        rec = {"died": died, "seconds": round(time.time() - t0, 1)}
        if died:
            r = cv.trial_arrival(t_msg)
            vd = visit_diff(cv, fb, sb)
            ok = r["area"] == BELOW and dist2(xz(r["pos"] or [0, 0, 0]), (103.0, -114.0)) < 4.0 and float(r.get("hp") or 0) >= 99
            cv.check("matron.lose_wakes_at_origin", ok, "a defeat in the Matron echo wakes Krystal at the arena checkpoint, full hp",
                     rec | {"area": r["area"], "pos": r["pos"], "hp": r["hp"], "msgs": r["msgs"]})
            cv.check("matron.lose_no_change", not vd["tele_story_flags_added"] and not vd["save"]["inv_delta"],
                     "a defeat changes no flag or item", vd)
        else:
            cv.check("matron.lose", False, "standing still in the echo chamber ends in a defeat", rec)
            if cv.area() == TRIAL:
                cv.pause_leave_trial()
                cv.trial_arrival(t_msg)
    cv.snapshot("matron_end")
    return True


# ============================================================================================ phase: expedition
import playthrough as PT  # noqa: E402

TAILOR_STAND = (-30.0, -23.2)
FURNACE_SPOT = (3.5, 9.0)
BOARD_SPOT = (6.5, 6.0)
ORCHARD_ARCH = (-60.0, 50.0)
ROUTES = {   # data/expeditions.gd TEMPLATES (stop lanterns, cache)
    "orchard_patrol": {"stops": [(-76.0, 70.0), (-123.0, 28.0), (-106.0, -6.0)], "cache": (-90.0, -2.0),
                       "ids": ["exp_op_meadow", "exp_op_hedgerow", "exp_op_cistern"],
                       "stop_names": ["Scarecrow Meadow", "Western Hedgerow", "Old Cistern Field"],
                       "cache_prompt": "Open the harvest crate", "arch": "Pumpkintide Orchard", "name": "Orchard Patrol"},
    "quarry_circuit": {"stops": [(78.0, 53.0), (55.0, 1.0), (92.0, -30.0), (114.0, -20.0)], "cache": (102.0, -12.0),
                       "ids": ["exp_qc_haul", "exp_qc_tailings", "exp_qc_cutting", "exp_qc_rise"],
                       "stop_names": ["Haul Road Meadow", "Tailings Meadow", "The North Cutting", "Bellfoot Rise"],
                       "cache_prompt": "Open the old ore cart", "arch": "Ashbell Quarry", "name": "Quarry Circuit",
                       # the North Cutting / Bellfoot Rise lie above the quarry terraces: walk round by the north road
                       "approach": {2: [(74.0, -15.0), (84.0, -14.0), (84.0, -28.0)], 3: [(95.0, -22.0), (103.0, -20.0)]},
                       "stand": {2: (81.0, -30.0), 3: (103.0, -20.0)}},
}


def exp_saved(cv: Cov) -> dict:
    return ((cv.save_json().get("state") or {}).get("expeditions")) or {}


def exp_tracker(cv: Cov) -> dict:
    return cv.st().get("tracker") or {}


def open_board(cv: Cov) -> bool:
    p1 = cv.p1
    e = p1.nearest(lambda n: "expedition board" in str(n.get("text", "")).lower(), 80)
    if e is None:
        p1.goto(BOARD_SPOT, tol=3.0, sprint=True, timeout=40)
        e = p1.nearest(lambda n: "expedition board" in str(n.get("text", "")).lower(), 80)
    if e is None:
        raise Stop(f"no Expedition Board near {cv.pos()}")
    ok = p1.press_interact_on(e, ["Expedition Board"], lambda: "expedition" in p1.ui(), stop=1.8)
    time.sleep(0.8)
    cv.data.setdefault("board_prompts", []).append(e.get("text"))
    return ok


def board_buttons(cv: Cov) -> list:
    return [(b.get("text"), bool(b.get("disabled"))) for b in cv.bot.buttons()]


def smelt_copper_bar(cv: Cov) -> dict:
    """At the placed furnace: crafting panel -> Furnace tab -> Copper Bar -> Add to queue; wait outside the menu;
    then the furnace itself offers "Collect 1 Copper Bar" (its prompt changes, so it is found by its node name)."""
    p1 = cv.p1
    rec = {}
    fur = p1.nearest(lambda n: "furnace" in (str(n.get("text", "")) + " " + str(n.get("name", ""))).lower()
                     and n.get("g") in ("interactable", "crafting_station"), 90)
    if fur is None:
        raise Stop(f"no placed furnace near {cv.pos()}")
    rec["furnace"] = {"name": fur.get("name"), "pos": fur.get("pos"), "text": fur.get("text")}
    p1.approach(fur, stop=2.2)
    if not p1.open_panel("C", "crafting"):
        raise Stop("crafting panel did not open at the furnace")
    time.sleep(0.5)
    p1.click("Furnace", exact=True)
    time.sleep(0.8)
    if not p1.click_scrolled("Copper Bar |") and not p1.click_scrolled("Copper Bar"):
        rec["error"] = f"no Copper Bar row: {[b.get('text') for b in cv.bot.buttons()][:40]}"
        p1.close_panels()
        return rec
    time.sleep(0.4)
    rec["buttons"] = [b.get("text") for b in cv.bot.buttons() if b.get("text") in ("Add to queue", "Craft", "Collect")]
    ok = cv.bot.click_button("Add to queue", exact=True, timeout=3)
    rec["queued"] = ok
    rec["ore_after_queue"] = p1.inv("copper_ore")
    p1.close_panels()
    t0 = time.time()
    name = fur.get("name")
    ready = cv.bot.wait_state(lambda s: any(n.get("name") == name and "collect" in str(n.get("text", "")).lower()
                                            for n in s.get("nearby", [])), 60.0)
    rec["ready_after_s"] = round(time.time() - t0, 1) if ready else None
    e = p1.nearest(lambda n: n.get("name") == name, 90)
    rec["prompt_when_ready"] = e and e.get("text")
    n0 = p1.inv("copper_bar")
    if e is not None:
        p1.press_interact_on(e, ["Collect"], lambda: p1.inv("copper_bar") > n0, stop=1.8)
    rec["copper_bar"] = p1.inv("copper_bar")
    e2 = p1.nearest(lambda n: n.get("name") == name, 90)
    rec["prompt_after_collect"] = e2 and e2.get("text")
    return rec


def clear_stop(cv: Cov, stop, n_total: int, timeout: float = 300.0, approach=None, stand=None) -> dict:
    """Stand ~11 m from the ribbon lantern, looking AWAY from it (groups appear only out of view, >= 5 m from her),
    fight whatever appears, until the game says the stop is quiet (or the route is clear)."""
    p4 = cv.p4
    t0 = time.time()
    t_msg = cv.msg_t()
    rec = {"stop": stop, "spawned": [], "fights": 0}
    turn = 0
    while time.time() - t0 < timeout:
        msgs = [m.get("text", "") for m in cv.msgs_since(t_msg)]
        done = [m for m in msgs if "is quiet again" in m or "The route is clear" in m]
        if done:
            rec["done_msg"] = done[0]
            rec["seconds"] = round(time.time() - t0, 1)
            return rec
        if cv.st().get("mode") == "dead":
            rec["deaths"] = rec.get("deaths", 0) + 1
            cv.wait_playing(None, 60)
            continue
        if cv.st().get("ui_stack"):
            cv.close_cards()
        live = p4.live_enemies(32)
        for e in live:
            key = (e.get("name"))
            if key not in [s[0] for s in rec["spawned"]]:
                rec["spawned"].append((key, e.get("state"), round(dist2(xz(e["pos"]), stop), 1)))
        active = [e for e in live if str(e.get("state", "")) not in ("idle", "wander", "return", "sleep", "dormant", "hidden")
                  or e["dist"] < 6]
        if active:
            rec["fights"] += 1
            heal(cv, 50.0, 2)
            p4.fight_smart(timeout=90.0, radius=30.0)
            continue
        if live:
            # a dormant one (e.g. a pumpkin mimic waiting as a pumpkin): walk up and wake it
            e = live[0]
            p4.goto(xz(e["pos"]), tol=1.8, sprint=True, timeout=20)
            cv.bot.tap("LMB", 0.06)
            time.sleep(0.4)
            continue
        me = xz(cv.pos())
        d = dist2(me, stop)
        if d > 25.0 and (approach or stand):
            # far away (e.g. woke at the arch after a fall): the authored way round, then the stand point
            rec["returns"] = rec.get("returns", 0) + 1
            for wp in approach or []:
                reach_walk(cv, wp, tol=2.0)
            if stand:
                reach_walk(cv, stand, tol=1.5)
            continue
        if d > 13.0 or d < 9.0:
            # a point 11 m from the lantern on our side of it
            k = 11.0 / max(d, 0.1)
            tgt = (stop[0] + (me[0] - stop[0]) * k, stop[1] + (me[1] - stop[1]) * k) if d > 0.5 else (stop[0] + 11.0, stop[1])
            p4.goto(tgt, tol=1.5, sprint=True, timeout=40)
            continue
        # face away from the lantern (the camera then looks away too), turning a little each time
        away = (me[0] + (me[0] - stop[0]), 0.0, me[1] + (me[1] - stop[1]))
        yaw = cv.bot.yaw_to((me[0], 0, me[1]), away) + (turn % 3 - 1) * 25.0
        cv.bot.turn_to_yaw(yaw, tol=6.0)
        turn += 1
        time.sleep(1.5)
    rec["seconds"] = round(time.time() - t0, 1)
    rec["timeout"] = True
    return rec


def reach_walk(cv: Cov, target, tol: float = 1.8) -> bool:
    """Walk across the open Reach: straight, then (if stuck) with a sidestep detour."""
    p4 = cv.p4
    if p4.goto(target, tol=tol, sprint=True, timeout=60):
        return True
    me = xz(cv.pos())
    dx, dz = target[0] - me[0], target[1] - me[1]
    L = math.hypot(dx, dz) or 1.0
    for side in (1, -1):
        mid = (me[0] + dx * 0.5 - dz / L * 8.0 * side, me[1] + dz * 0.5 + dx / L * 8.0 * side)
        if p4.goto(mid, tol=2.0, sprint=True, timeout=40) and p4.goto(target, tol=tol, sprint=True, timeout=60):
            return True
    return dist2(xz(cv.pos()), target) <= tol * 1.5


def safe_craft(cv: Cov, recipe_name: str, station_tab: str, item: str, times: int = 1) -> dict:
    """playthrough.Play.craft with a STABLE row click: the recipe row is clicked only once its rect is unclipped and
    unchanged across two telemetry reads 0.5 s apart (the harness once clicked a stale row mid-scroll and made a Loom).
    Returns {"ok", "gained", "wrong"}."""
    p1 = cv.p1
    p1.goto_station(station_tab)
    before = dict(cv.st().get("inv") or {})
    if not p1.open_panel("C", "crafting"):
        raise Stop("crafting panel did not open")
    time.sleep(0.5)
    p1.click(station_tab, exact=True)
    time.sleep(1.2)
    prefix = recipe_name.lower() + " |"
    clicked = False
    last_rect = None
    t0 = time.time()
    while time.time() - t0 < 30.0 and not clicked:
        bs = [b for b in cv.bot.buttons() if str(b.get("text", "")).lower().startswith(prefix)]
        if not bs:
            time.sleep(0.3)
            continue
        b = bs[0]
        r = tuple(round(v, 2) for v in cv.bot.rect_of(b))
        if b.get("clipped"):
            last_rect = None
            x, y, w, h = cv.bot.rect_of(b)
            rows = [o for o in cv.bot.buttons() if not o.get("clipped") and " | " in str(o.get("text", ""))]
            if rows:
                anchor = min(rows, key=lambda o: abs(cv.bot.rect_of(o)[1] - y))
                ax, ay, aw, ah = cv.bot.rect_of(anchor)
                cv.bot.hover(ax + aw / 2.0, ay + ah / 2.0)
                # one notch scrolls about one row: send as many as the distance needs (the list is long)
                n = max(1, min(30, int(abs(y - ay) / max(ah, 0.5))))
                cv.bot.wheel((-120 if y > ay else 120) * n)
            time.sleep(0.6)
            continue
        if r != last_rect:
            last_rect = r
            time.sleep(0.5)
            continue
        cv.bot.click_at_button(b)
        clicked = True
    time.sleep(0.5)
    for _ in range(times if clicked else 0):          # never press Craft on whatever happens to be selected
        if not cv.bot.click_button("Craft", exact=True, timeout=3):
            break
        time.sleep(0.4)
    time.sleep(0.4)
    p1.close_panels()
    time.sleep(0.3)
    after = dict(cv.st().get("inv") or {})
    gained = {k: after.get(k, 0) - before.get(k, 0) for k in after if after.get(k, 0) > before.get(k, 0)}
    rec = {"ok": gained.get(item, 0) >= times, "gained": gained, "row_clicked": clicked}
    if gained and item not in gained:
        rec["wrong"] = True
        cv.log(f"safe_craft {recipe_name}: WRONG item crafted {gained}")
    cv.log(f"safe_craft {recipe_name}: {rec}")
    return rec


def exp_setup_home(cv: Cov):
    """Tailor's Cache -> materials -> furnace -> copper bar -> Expedition Board, all at / near the Haven."""
    p1 = cv.p1
    heal(cv, 80.0)
    if "c1x_tailor_cache" not in cv.tele_flags():
        inv0 = dict(cv.st().get("inv") or {})
        p1.travel("old_oak")
        p1.goto(TAILOR_STAND, tol=1.2, sprint=False, timeout=30)
        e = p1.nearest(lambda n: "tailor" in str(n.get("text", "")).lower(), 20)
        if not e:
            raise Stop(f"Tailor's Cache not found near {cv.pos()}")
        ok = p1.press_interact_on(e, ["Tailor's Cache"], lambda: "c1x_tailor_cache" in p1.flags(), stop=1.4)
        time.sleep(2.0)
        inv1 = dict(cv.st().get("inv") or {})
        opt = (cv.st().get("optional") or {})
        rec = {"opened": ok, "optional_done": "opt_tailors_cache" in (opt.get("done") or []),
               "inv_delta": {k: inv1.get(k, 0) - inv0.get(k, 0) for k in set(inv0) | set(inv1) if inv1.get(k, 0) != inv0.get(k, 0)}}
        cv.check("exp.tailor_cache", ok and rec["inv_delta"].get("woven_cloth", 0) >= 2,
                 "the Tailor's Cache opens (c1x_tailor_cache, Loom recipe) and its optional goal pays woven cloth x2", rec)
        p1.walk_route(PT.PATHS["old_oak"][::-1])
    has_board = p1.nearest(lambda n: "expedition board" in str(n.get("text", "")).lower(), 80) is not None
    if has_board:
        return
    need = {"wood": 12, "stone": 10, "copper_ore": 4} if p1.inv("copper_bar") < 1 and p1.inv("furnace") < 1 else {"wood": 8}
    mats = {"before": {k: p1.inv(k) for k in need}}
    if p1.inv("copper_ore") < need.get("copper_ore", 0) or p1.inv("stone") < need.get("stone", 0):
        p1.travel("quarry")
        for words, item in ((["Copper"], "copper_ore"), (["Boulder", "Rock", "Stone"], "stone")):
            if p1.inv(item) < need.get(item, 0):
                try:
                    p1.harvest_tool(words, item, need[item], maxd=40)
                except Exception as ex:  # noqa: BLE001
                    cv.log(f"{item} at the quarry: {ex}")
        p1.travel_home()
    if p1.inv("stone") < need.get("stone", 0):
        try:
            p1.gather_hand(["Stone"], "stone", need["stone"], maxd=70)
        except Exception as ex:  # noqa: BLE001
            cv.log(f"stones: {ex}")
    if p1.inv("wood") < need["wood"]:
        try:
            p1.harvest_tool(["Oak", "Tree", "Pine", "Birch", "Blossom", "Maple", "Willow"], "wood", need["wood"], maxd=60)
        except Exception as ex:  # noqa: BLE001
            cv.log(f"wood: {ex}")
        if p1.inv("wood") < need["wood"]:
            try:
                p1.gather_hand(["Stick"], "wood", need["wood"], maxd=70)
            except Exception as ex:  # noqa: BLE001
                cv.log(f"sticks: {ex}")
    mats["after"] = {k: p1.inv(k) for k in need}
    cv.data["materials"] = mats
    if any(p1.inv(k) < v for k, v in need.items()):
        raise Stop(f"materials short: {mats}")
    p1.goto((0.0, 4.0), tol=2.5)
    if p1.inv("copper_bar") < 1:
        fur_placed = p1.nearest(lambda n: "furnace" in (str(n.get("text", "")) + str(n.get("name", ""))).lower(), 60)
        if p1.inv("furnace") < 1 and not fur_placed:
            sc = safe_craft(cv, "Furnace", "Workbench", "furnace")
            cv.check("exp.craft_furnace", sc["ok"] and p1.inv("furnace") >= 1, "the Furnace is crafted at the workbench", sc | {"inv": p1.inv("furnace")})
        if p1.inv("furnace") >= 1:
            ok = p1.place("furnace", near=FURNACE_SPOT)
            cv.check("exp.place_furnace", ok, "the Furnace is placed at home", {"pos": cv.pos()})
        sm = smelt_copper_bar(cv)
        cv.check("exp.copper_bar", p1.inv("copper_bar") >= 1,
                 "the furnace smelts 2 copper ore into a Copper Bar (20 s queue) and it is collected at the furnace", sm)
        if p1.inv("copper_bar") < 1:
            raise Stop(f"no copper bar: {sm}")
    if p1.inv("expedition_board") < 1:
        sc = safe_craft(cv, "Expedition Board", "Workbench", "expedition_board")
        if not sc["ok"]:
            sc = safe_craft(cv, "Expedition Board", "Workbench", "expedition_board")
        ok = sc["ok"]
        cv.check("exp.craft_board", ok and p1.inv("expedition_board") >= 1,
                 "the Expedition Board (6 wood, 1 woven cloth, 1 copper bar; unlocked by ch2_choir_defeated) is crafted",
                 {"inv": p1.inv("expedition_board")})
    ok = p1.place("expedition_board", near=BOARD_SPOT)
    cv.check("exp.place_board", ok, "the Expedition Board is placed at home", {"pos": cv.pos()})
    p1.pause_save()
    cv.snapshot("exp_board_placed")


def exp_set_out(cv: Cov, rid: str, label: str) -> dict:
    """At home: board -> route card -> Set out -> the panel's Lantern Road button to the route's arch."""
    R = ROUTES[rid]
    if not open_board(cv):
        raise Stop(f"the board did not open the expedition panel (ui {cv.p1.ui()})")
    before_btns = board_buttons(cv)
    cv.bot.click_button(R["name"], timeout=3)
    time.sleep(0.6)
    sha0 = sha(cv.save_dir / "slot1.json")
    t_msg = cv.msg_t()
    ok = cv.bot.click_button("Set out", exact=True, timeout=3)
    time.sleep(1.0)
    msgs = [m.get("text") for m in cv.msgs_since(t_msg)]
    started = any("Expedition begun" in (m or "") for m in msgs)
    rec = {"msgs": msgs, "buttons_before": before_btns, "buttons_after": board_buttons(cv), "tracker": exp_tracker(cv),
           "save_written_by_set_out": sha(cv.save_dir / "slot1.json") != sha0}
    cv.check(f"exp.{label}.set_out", ok and started, f"'Set out' starts {R['name']} ('Expedition begun: ...' toast)", rec)
    trav = [b.get("text") for b in cv.bot.buttons() if str(b.get("text", "")).startswith("Lantern Road")]
    rec["travel_button"] = trav
    if trav and cv.bot.click_button(trav[0], exact=True, timeout=3):
        cv.wait_playing(REACH, 90)
    else:
        cv.p1.close_panels()
        cv.ward_stone_travel(R["arch"], REACH)
    time.sleep(1.5)
    cv.bot.calibrate_look()
    ex = exp_saved(cv)
    cv.check(f"exp.{label}.run_saved_on_arrival", (ex.get("active") or {}).get("template") == rid,
             "arriving in the Reach saves the running expedition (state.expeditions.active)", {"expeditions": ex, "pos": cv.pos()})
    return rec


def exp_home_from_reach(cv: Cov, arch_xz) -> bool:
    reach_walk(cv, (arch_xz[0] - 2.0, arch_xz[1] + 2.0), tol=2.0)
    arch = cv.p4.nearest(lambda n: "travel the lantern road" in str(n.get("text", "")).lower(), 25)
    if arch and cv.p4.interact_with(arch, ["Travel the Lantern Road"], check=lambda: bool(cv.p4.ui()), stop=1.9):
        cv.bot.click_button("The Haven", timeout=4)
        cv.wait_playing(SURFACE, 90)
    time.sleep(1.5)
    cv.bot.calibrate_look()
    return cv.area() == SURFACE


def exp_open_cache(cv: Cov, rid: str, label: str) -> dict:
    R = ROUTES[rid]
    p4 = cv.p4
    reach_walk(cv, (R["cache"][0] + 2.5, R["cache"][1] + 1.5), tol=1.5)
    inv0 = dict(cv.st().get("inv") or {})
    ex0 = exp_saved(cv)
    cv.data["_drops0"] = list((cv.save_json().get("state") or {}).get("dropped") or [])
    t_msg = cv.msg_t()
    cache = p4.nearest(lambda n: R["cache_prompt"].lower() in str(n.get("text", "")).lower(), 20)
    ok = False
    if cache:
        ok = p4.interact_with(cache, [R["cache_prompt"]], stop=1.4, tries=6,
                              check=lambda: any("Expedition complete" in m.get("text", "") for m in cv.msgs_since(t_msg)))
    time.sleep(1.5)
    inv1 = dict(cv.st().get("inv") or {})
    delta = {k: inv1.get(k, 0) - inv0.get(k, 0) for k in set(inv0) | set(inv1) if inv1.get(k, 0) != inv0.get(k, 0)}
    msgs = [m.get("text") for m in cv.msgs_since(t_msg)]
    cv.p1.pause_save()
    ex = exp_saved(cv)
    last = ex.get("last") or {}
    want = dict(last.get("items") or {})
    ks = last.get("keepsake") or {}
    if ks.get("kind") == "decor":
        want[ks["item"]] = want.get(ks["item"], 0) + int(ks.get("count", 1))
    n_before = int((ex0.get("completed") or {}).get(rid, 0))
    # a full backpack drops the overflow at her feet as a saved pickup (GameState.give_item): count those too
    drops0 = {d.get("uid") for d in ((cv.data.get("_drops0") or []))}
    dropped = {}
    for d in ((cv.save_json().get("state") or {}).get("dropped") or []):
        if d.get("uid") not in drops0 and d.get("area") == REACH and dist2((d["pos"][0], d["pos"][2]), R["cache"]) < 6.0:
            dropped[d["item"]] = dropped.get(d["item"], 0) + int(d.get("count", 0))
    got = {k: delta.get(k, 0) + dropped.get(k, 0) for k in set(delta) | set(dropped)}
    got = {k: v for k, v in got.items() if v}
    ok_all = ok and got == want and not ex.get("active") and int((ex.get("completed") or {}).get(rid, 0)) == n_before + 1
    cv.data.pop("_drops0", None)
    rec = {"opened": ok, "inv_delta": delta, "dropped_overflow": dropped, "last": last, "completed": ex.get("completed"), "active": ex.get("active"),
           "msgs": msgs, "palettes_after": ((cv.save_json().get("state") or {}).get("wardrobe") or {}).get("palettes")}
    cv.check(f"exp.{label}.cache_rewards_once", ok_all,
             "opening the cache pays exactly the saved roll once (inventory delta + overflow dropped at the cache == state.expeditions.last), ends the run, completed +1",
             rec)
    time.sleep(1.0)
    again = p4.nearest(lambda n: R["cache_prompt"].lower() in str(n.get("text", "")).lower(), 25)
    cv.check(f"exp.{label}.cache_gone", again is None, "the cache folds away after opening (no second prompt)", {"cache_again": again})
    return rec


def exp_run_stops(cv: Cov, rid: str, label: str, upto: int | None = None, save_quit_after: int | None = None) -> list:
    R = ROUTES[rid]
    out = []
    stops = R["stops"]
    while True:
        a = exp_saved(cv).get("active") or {}
        i = int(a.get("stop", 0)) if a.get("template") == rid else 0
        # the live run may be ahead of the save: the tracker names the current stop
        trk = exp_tracker(cv)
        ids = R.get("ids") or []
        if trk.get("kind") == "expedition" and trk.get("step") in ids:
            i = ids.index(trk["step"])
        elif trk.get("kind") == "expedition" and "cache" in str(trk.get("step", "")):
            i = len(stops)
        if i >= len(stops) or (upto is not None and i >= upto):
            return out
        if cv.time_left() < 120:
            cv.note(f"time budget: {label} stops cut short at stop {i + 1}")
            return out
        stop = stops[i]
        for wp in (R.get("approach") or {}).get(i, []):
            if dist2(xz(cv.pos()), stop) > 12.0:
                reach_walk(cv, wp, tol=2.0)
        reach_walk(cv, (R.get("stand") or {}).get(i, (stop[0] + 11.0, stop[1])))
        r = clear_stop(cv, stop, len(stops), timeout=min(300.0, cv.time_left() - 60),
                       approach=(R.get("approach") or {}).get(i), stand=(R.get("stand") or {}).get(i))
        cv.log(f"{label} stop {i + 1}: {r}")
        out.append(r)
        cv.check(f"exp.{label}.stop{i + 1}_cleared", "done_msg" in r, f"stop {i + 1} ({R['stop_names'][i]}) is cleared by normal fighting", r)
        if "done_msg" not in r:
            raise Stop(f"{label} stop {i + 1} not cleared")
        if save_quit_after is not None and i + 1 == save_quit_after:
            heal(cv, 70.0)
            saved = cv.p1.pause_save()
            pre = {"pos": cv.pos(), "tracker": exp_tracker(cv), "inv": dict(cv.st().get("inv") or {})}
            ex1 = exp_saved(cv)
            q = cv.pause_quit_game()
            cv.relaunch()
            cv.title_continue()
            time.sleep(2.0)
            post = {"area": cv.area(), "pos": cv.pos(), "tracker": exp_tracker(cv), "inv": dict(cv.st().get("inv") or {})}
            ex2 = exp_saved(cv)
            ok = post["area"] == REACH and int((ex2.get("active") or {}).get("stop", -1)) == i + 1 and \
                (post["tracker"] or {}).get("kind") == "expedition" and dist2(xz(post["pos"] or [0, 0, 0]), xz(pre["pos"] or [0, 0, 0])) < 3.0
            cv.check(f"exp.{label}.save_quit_mid_run_resumes", ok and pre["inv"] == post["inv"],
                     f"pause Save Game -> Quit Game mid-run -> relaunch -> Continue: same Reach spot, the run at stop {i + 2} of "
                     f"{len(stops)}, the tracker card, the same items",
                     {"saved": saved, "quit": q, "pre": pre, "post": post, "active_saved_before_quit": ex1.get("active"),
                      "active_after_continue": ex2.get("active"), "same_items": pre["inv"] == post["inv"]})
            cv.snapshot(f"exp_{label}_after_relaunch")


def exp_set_aside(cv: Cov) -> dict:
    open_board(cv)
    t_msg = cv.msg_t()
    first = cv.bot.click_button("Set it aside", exact=True, timeout=3)
    time.sleep(0.6)
    confirm_label = [b.get("text") for b in cv.bot.buttons() if "Really set it aside" in str(b.get("text", ""))]
    active_after_first = bool(exp_tracker(cv).get("kind") == "expedition")
    if confirm_label:
        cv.bot.click_button(confirm_label[0], exact=True, timeout=3)
    time.sleep(0.8)
    rec = {"first_press": first, "confirm_label": confirm_label, "active_after_first_press": active_after_first,
           "msgs": [m.get("text") for m in cv.msgs_since(t_msg)], "buttons_after": board_buttons(cv)}
    cv.p1.close_panels()
    return rec


def phase_expedition(cv: Cov):
    rid = "orchard_patrol"
    R = ROUTES[rid]
    if cv.area() == SURFACE:
        exp_setup_home(cv)
    # ---- run A: Orchard Patrol start to finish, with a save / quit / relaunch mid-run ------------------------------
    ex = exp_saved(cv)
    if int((ex.get("completed") or {}).get(rid, 0)) == 0:
        if not (ex.get("active") or {}):
            if cv.area() != SURFACE:
                raise Stop(f"run A needs the board at home (area {cv.area()})")
            cv.data["runA_set_out"] = exp_set_out(cv, rid, "runA")
            cv.snapshot("exp_runA_started")
        cv.data["runA_stops"] = exp_run_stops(cv, rid, "runA", save_quit_after=1)
        cv.data["runA_cache"] = exp_open_cache(cv, rid, "runA")
        cv.snapshot("exp_runA_complete")
        # the rewards stay paid once across a relaunch: (saved by exp_open_cache) quit, relaunch, Continue
        inv_a = dict(cv.st().get("inv") or {})
        q = cv.pause_quit_game()
        cv.relaunch()
        cv.title_continue()
        time.sleep(2.0)
        inv_b = dict(cv.st().get("inv") or {})
        ex_b = exp_saved(cv)
        again = cv.p4.nearest(lambda n: R["cache_prompt"].lower() in str(n.get("text", "")).lower(), 40)
        cv.check("exp.runA.rewards_once_after_relaunch", inv_a == inv_b and int((ex_b.get("completed") or {}).get(rid, 0)) == 1
                 and not ex_b.get("active") and again is None,
                 "after quit + relaunch + Continue: same inventory, completed 1, no run, no cache to open again",
                 {"quit": q, "same_inv": inv_a == inv_b,
                  "inv_diff": {k: [inv_a.get(k), inv_b.get(k)] for k in set(inv_a) | set(inv_b) if inv_a.get(k) != inv_b.get(k)},
                  "expeditions": ex_b, "cache_again": again, "pos": cv.pos()})
    elif not (ex.get("active") or {}) and cv.start_save.exists():
        # resumed from the save written right after the cache (a relaunch + Continue): the rewards stay paid once
        st0 = json.loads(cv.start_save.read_text(encoding="utf-8")).get("state") or {}
        inv_saved = inv_totals(st0)
        inv_live = dict(cv.st().get("inv") or {})
        again = cv.p4.nearest(lambda n: R["cache_prompt"].lower() in str(n.get("text", "")).lower(), 40)
        cv.check("exp.runA.rewards_once_after_relaunch", inv_saved == inv_live and int((ex.get("completed") or {}).get(rid, 0)) == 1
                 and again is None,
                 "relaunch + Continue on the save written after the cache: same inventory as saved, completed 1, no run, "
                 "no cache to open again", {"start_save": str(cv.start_save), "same_inv": inv_saved == inv_live,
                                            "inv_diff": {k: [inv_saved.get(k), inv_live.get(k)] for k in set(inv_saved) | set(inv_live)
                                                         if inv_saved.get(k) != inv_live.get(k)},
                                            "expeditions": ex, "cache_again": again, "area": cv.area(), "pos": cv.pos()})
    # ---- run B: set out again, clear one stop, go home, set it aside (progress dropped), start afresh -----------------
    if cv.time_left() > 300:
        if cv.area() != SURFACE and not exp_home_from_reach(cv, ORCHARD_ARCH):
            raise Stop(f"could not get home (area {cv.area()})")
        exp_set_out(cv, rid, "runB")
        exp_run_stops(cv, rid, "runB", upto=1)
        inv_mid = dict(cv.st().get("inv") or {})
        if not exp_home_from_reach(cv, ORCHARD_ARCH):
            raise Stop(f"could not get home for the set-aside test (area {cv.area()})")
        ex_a = exp_saved(cv)
        sa = exp_set_aside(cv)
        cv.p1.pause_save()
        ex_b = exp_saved(cv)
        inv_after = dict(cv.st().get("inv") or {})
        cv.check("exp.runB.set_aside", sa["first_press"] and bool(sa["confirm_label"]) and sa["active_after_first_press"]
                 and not ex_b.get("active") and int(ex_b.get("abandoned", 0)) == int(ex_a.get("abandoned", 0)) + 1 and inv_after == inv_mid,
                 "'Set it aside' asks once (two presses), then ends the run for free: active {}, abandoned +1, items unchanged",
                 {"saved_before": ex_a, "saved_after": ex_b, "set_aside": sa,
                  "inv_diff": {k: [inv_mid.get(k), inv_after.get(k)] for k in set(inv_mid) | set(inv_after) if inv_mid.get(k) != inv_after.get(k)}})
        open_board(cv)
        cv.bot.click_button(R["name"], timeout=3)
        cv.bot.click_button("Set out", exact=True, timeout=3)
        time.sleep(0.8)
        cv.p1.close_panels()
        cv.p1.pause_save()
        ex_c = exp_saved(cv)
        a = ex_c.get("active") or {}
        cv.check("exp.runB.restart_from_first_stop", a.get("template") == rid and int(a.get("stop", -1)) == 0
                 and int(a.get("run", 0)) == int(ex_b.get("runs", 0)) + 1 and int(a.get("defeated", -1)) == 0,
                 "a set-aside route starts again from its first stop as a new run (the cleared stop is not kept)", {"after_restart": ex_c})
        cv.snapshot("exp_runB_restart")
    # ---- run C: another route (Quarry Circuit) -------------------------------------------------------------------------
    if cv.time_left() > 600 and cv.data.get("second_route", True):
        rid2 = "quarry_circuit"
        if (exp_saved(cv).get("active") or {}) or exp_tracker(cv).get("kind") == "expedition":
            cv.data["runC_set_aside_first"] = exp_set_aside(cv)
        exp_set_out(cv, rid2, "runC")
        cv.data["runC_stops"] = exp_run_stops(cv, rid2, "runC")
        if cv.time_left() > 90:
            cv.data["runC_cache"] = exp_open_cache(cv, rid2, "runC")
        cv.snapshot("exp_runC_end")
    return True


QUARRY_ARCH = (62.0, 38.0)


def home_rest_simple(cv: Cov) -> dict:
    """At the Haven: sleep in the bed (full heal, saves), pick berries, make Berry Snacks by hand."""
    p1 = cv.p1
    rec = {"hp_before": (cv.st().get("player") or {}).get("hp")}
    bed = p1.nearest(lambda n: "sleep until morning" in str(n.get("text", "")).lower(), 70)
    if bed is not None:
        p1.press_interact_on(bed, ["Sleep until morning"], lambda: float((cv.st().get("player") or {}).get("hp", 0)) >= 99.5, stop=1.5)
        cv.wait_playing(SURFACE, 30)
        time.sleep(1.0)
        cv.bot.calibrate_look()
    rec["hp_after_sleep"] = (cv.st().get("player") or {}).get("hp")
    b0 = p1.inv("berries")
    try:
        p1.gather_hand(["Berr"], "berries", b0 + 12, maxd=50, exclude=("rose", "regrow"))
    except Exception as ex:  # noqa: BLE001
        cv.log(f"berries: {ex}")
    n = p1.inv("berries") // 4
    if n > 0:
        try:
            p1.craft("Berry Snack", times=n, item="berry_snack")
        except Exception as ex:  # noqa: BLE001
            cv.log(f"berry snack: {ex}")
            p1.close_panels()
    rec["berry_snack"] = p1.inv("berry_snack")
    cv.log(f"home rest: {rec}")
    return rec


def exp_travel_active(cv: Cov, rid: str) -> bool:
    """The running route: the board's 'Lantern Road to <arch>' button."""
    if not open_board(cv):
        return False
    trav = [b.get("text") for b in cv.bot.buttons() if str(b.get("text", "")).startswith("Lantern Road")]
    cv.data.setdefault("board_travel_buttons", []).append(trav)
    if trav and cv.bot.click_button(trav[0], exact=True, timeout=3):
        ok = cv.wait_playing(REACH, 90)
        time.sleep(1.5)
        cv.bot.calibrate_look()
        return ok
    cv.p1.close_panels()
    return False


def phase_expedition_c(cv: Cov):
    """Quarry Circuit on its own (resumes a saved run of it, or starts one), after a rest at home."""
    rid2 = "quarry_circuit"
    if cv.area() == REACH:
        if not exp_home_from_reach(cv, QUARRY_ARCH):
            raise Stop(f"could not get home (area {cv.area()}, pos {cv.pos()})")
    if cv.area() != SURFACE:
        raise Stop(f"expedition_c needs the Haven (area {cv.area()})")
    cv.data["home_rest"] = home_rest_simple(cv)
    a = exp_saved(cv).get("active") or {}
    if a.get("template") == rid2:
        ok = exp_travel_active(cv, rid2)
        cv.check("exp.runC.board_travel_resumes_saved_run", ok and exp_tracker(cv).get("kind") == "expedition",
                 "a saved Quarry Circuit run (from before the quit) is still under way: the board's Lantern Road button takes her to the quarry arch",
                 {"active": a, "tracker": exp_tracker(cv), "area": cv.area()})
    else:
        if a:
            cv.data["runC_set_aside_first"] = exp_set_aside(cv)
        exp_set_out(cv, rid2, "runC")
    cv.data["runC_stops"] = exp_run_stops(cv, rid2, "runC")
    if cv.time_left() > 90:
        cv.data["runC_cache"] = exp_open_cache(cv, rid2, "runC")
    cv.snapshot("exp_runC_end")
    return True


def phase_loom_probe(cv: Cov):
    """Opens the crafting panel's Loom tab and lists its rows (scrolling): are the trial patterns offered?"""
    p1 = cv.p1
    if not p1.open_panel("C", "crafting"):
        raise Stop("crafting panel did not open")
    time.sleep(0.5)
    p1.click("Loom", exact=True)
    time.sleep(1.2)
    rows = {}
    for _ in range(12):
        for b in cv.bot.buttons():
            t = str(b.get("text", ""))
            if " | " in t:
                rows[t] = bool(b.get("disabled"))
        vis = [b for b in cv.bot.buttons() if " | " in str(b.get("text", "")) and not b.get("clipped")]
        if vis:
            last = vis[-1]
            x, y, w, h = cv.bot.rect_of(last)
            cv.bot.hover(x + w / 2.0, y + h / 2.0)
            cv.bot.wheel(-120)
        time.sleep(0.5)
    p1.close_panels()
    flags = cv.tele_flags()
    names = {"velour": "Moonlit Masquerade", "choir": "Chime Chorister", "matron": "Moon Moth"}
    seen = {k: [r for r in rows if n.lower() in r.lower()] for k, n in names.items()}
    rec = {"trial_flags": sorted(f for f in flags if f.startswith("ch2_trial_")), "loom_rows": sorted(rows), "pattern_rows": seen}
    for k in names:
        has_flag = f"ch2_trial_{k}" in flags
        cv.check(f"loom.pattern_{k}", bool(seen[k]) == has_flag,
                 f"the {names[k]} pattern is offered at the Loom exactly when ch2_trial_{k} is set", {"flag": has_flag, "rows": seen[k]})
    cv.data["loom_probe"] = rec
    return True


# ============================================================================================ driver
PHASES = {"velour": phase_velour, "velour_standdown": phase_velour_standdown, "choir": phase_choir, "choir_win": phase_choir_win, "matron": phase_matron,
          "expedition": phase_expedition, "expedition_c": phase_expedition_c,
          "loom_probe": phase_loom_probe}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--phase", required=True, choices=sorted(PHASES))
    ap.add_argument("--attempt", type=int, default=1)
    ap.add_argument("--start-save", default=str(NATURAL_SAVE))
    ap.add_argument("--budget-min", type=float, default=30.0)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--wins", type=int, default=2, help="velour: how many echo wins in a row")
    a = ap.parse_args(argv)
    cv = Cov(a.phase, a.attempt, Path(a.start_save), a.budget_min, a.seed)
    cv.data["wins"] = a.wins
    status = "running"
    try:
        cv.prepare_save()
        cv.launch()
        cv.title_continue()
        cv.close_cards()
        PHASES[a.phase](cv)
        status = "completes"
    except Stop as e:
        status = f"stops: {e}"
        cv.log(status)
    except Exception as e:  # noqa: BLE001
        status = f"harness error {type(e).__name__}: {e}"
        cv.log(traceback.format_exc())
        cv.log(status)
    finally:
        for g in cv.games:
            g.stop()
    # SCRIPT ERRORs in the game logs
    script_errors = []
    for g in cv.games:
        for f in g.log_files():
            try:
                lines = Path(f).read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            for i, ln in enumerate(lines):
                if ln.startswith(("SCRIPT ERROR", "ERROR", "USER SCRIPT ERROR")):
                    nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                    script_errors.append({"game": g.name, "line": ln.strip(), "at": nxt})
    res = {"key": KEY, "phase": a.phase, "status": status, "natural_start": Path(a.start_save).resolve() == NATURAL_SAVE.resolve(),
           "start_save": str(a.start_save), "started": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(cv.t0)),
           "seconds": round(time.time() - cv.t0, 1), "checks": cv.checks, "data": cv.data, "notes": cv.notes, "bugs": cv.bugs,
           "script_errors": script_errors, "shots": cv.shots,
           "processes": [{"name": g.name, "port": g.port, "cmd": g.cmd} for g in cv.games]}
    if a.phase in ("velour", "choir_win"):
        try:
            res["inventory_timeline"] = inv_timeline([g.tele_path for g in cv.games])
        except Exception as e:  # noqa: BLE001
            res["inventory_timeline_error"] = str(e)
    write_json(cv.out / "result.json", res)
    # merge the run's bugs into the key's bugs.json
    allb = []
    if BUGS_FILE.exists():
        try:
            allb = json.loads(BUGS_FILE.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            allb = []
    for b in cv.bugs:
        if not any(x.get("title") == b["title"] for x in allb):
            allb.append({k: b[k] for k in ("title", "severity", "steps", "expected", "actual", "evidence")})
    write_json(BUGS_FILE, allb)
    passed = sum(1 for c in cv.checks if c["result"] == "PASS")
    print(f"STATUS {status}; checks {passed}/{len(cv.checks)} passed; script errors {len(script_errors)}; out {cv.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
