"""Segment S2 helpers (owned by S2: tools/qa/ch2/s2_*.py). Launches the SOURCE build HEADLESS with the
localhost virtual-input server and QA telemetry, and wraps the shared hhbot.Bot with the player-level actions the
S2 route needs (walk a route, approach + interact, fight, gather, eat, dismiss pop-ups). Small helpers are copied
and adapted from tools/qa/playthrough.py (the Chapter One route) instead of editing the shared hhbot.py /
session.py / playthrough.py / qa_telemetry.gd (owned by the route "S0").

Launch line (AGENTS.md "second-monitor / virtual-input QA mode", headless variant; nothing here opens a window,
sends OS input or takes desktop screenshots):
  .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --max-fps 60 --
      --qa-input-port=<port> --qa-no-focus --qa-telemetry=<file> --qa-interval=0.1 --save-dir=<run>/saves
      --settings-file=<run>/settings.cfg --no-focus-pause --qa-mute --max-seconds=<n> [--seed=N]
The console exe is a small wrapper that starts the real Godot exe as its child: stop() kills the process TREE of
the pid created here (taskkill /T /F /PID <ours>) - never any other Godot process. Ports: 7200 + attempt
(segment 2 * 100 + 7000), bumped by 10 while taken.

Natural-play rule: every action below is keyboard / mouse input through VirtualInput; the bot only READS the
telemetry (its information advantage: exact positions, prompts, enemy states - see the final report).
"""
from __future__ import annotations

import json
import math
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
QA_DIR = HERE.parent
ROOT = QA_DIR.parents[1]
GAME_DIR = ROOT / "game"
GODOT_CONSOLE = ROOT / ".tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
CREATE_NO_WINDOW = 0x08000000

if str(QA_DIR) not in sys.path:
    sys.path.insert(0, str(QA_DIR))

from hhbot import Bot, Telemetry, VirtualInput, VirtualInputError, angle_diff  # noqa: E402


class StepFailed(Exception):
    pass


def xz(p):
    return (p[0], p[2]) if len(p) == 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def pick_port(segment: int = 2, attempt: int = 1) -> int:
    p = segment * 100 + 7000 + attempt
    for _ in range(9):
        if port_free(p):
            return p
        p += 10
    raise RuntimeError(f"no free port near {segment * 100 + 7000 + attempt}")


def kill_tree(pid: int) -> None:
    try:
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, timeout=20,
                       creationflags=CREATE_NO_WINDOW)
    except Exception:  # noqa: BLE001
        pass


class HeadlessGame:
    """One headless game process (source build) + virtual input + telemetry tail + a Bot."""

    def __init__(self, run_dir, name: str, port: int, max_seconds: int = 3600, seed: int | None = None,
                 extra: list[str] | None = None, max_fps: int = 60, exe=GODOT_CONSOLE):
        self.run = Path(run_dir).resolve()
        self.run.mkdir(parents=True, exist_ok=True)
        self.name = name
        self.port = port
        self.save_dir = self.run / "saves"
        self.settings_file = self.run / "settings.cfg"
        self.tele_path = self.run / f"{name}_telemetry.jsonl"
        self.log_path = self.run / f"{name}_bot.log"
        self.godot_log = self.run / f"{name}_godot.log"
        self.max_seconds = max_seconds
        self.seed = seed
        self.extra = extra or []
        self.max_fps = max_fps
        self.exe = str(exe)
        self.proc: subprocess.Popen | None = None
        self.bot: Bot | None = None
        self._log_fh = None

    def args(self) -> list[str]:
        engine = ["--headless", "--path", str(GAME_DIR)]
        if self.max_fps > 0:
            engine += ["--max-fps", str(self.max_fps)]
        user = [f"--qa-input-port={self.port}", "--qa-no-focus", f"--qa-telemetry={self.tele_path.as_posix()}",
                "--qa-interval=0.1", f"--save-dir={self.save_dir.as_posix()}",
                f"--settings-file={self.settings_file.as_posix()}", "--no-focus-pause", "--qa-mute",
                f"--max-seconds={int(self.max_seconds)}"]
        if self.seed is not None:
            user.append(f"--seed={int(self.seed)}")
        return engine + ["--"] + user + self.extra

    def start(self, connect_timeout: float = 120.0) -> Bot:
        if self.tele_path.exists():
            self.tele_path.unlink()
        self._log_fh = open(self.godot_log, "w", encoding="utf-8", errors="replace")
        cmd = [self.exe] + self.args()
        self.proc = subprocess.Popen(cmd, cwd=str(ROOT), stdout=self._log_fh, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW)
        tele = Telemetry(self.tele_path)
        try:
            vin = VirtualInput(self.port, proc=self.proc, tele=tele, connect_timeout=connect_timeout)
        except Exception:
            self.stop()
            raise
        self.bot = Bot(vin, tele, self.log_path)
        self.bot.log(f"launched headless pid={self.proc.pid} port={self.port}: {' '.join(cmd)}")
        return self.bot

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.bot is not None:
            try:
                self.bot.release_all()
                self.bot.win.close()
            except Exception:  # noqa: BLE001
                pass
        if self.proc is not None:
            if self.proc.poll() is None:
                kill_tree(self.proc.pid)
                try:
                    self.proc.wait(15)
                except Exception:  # noqa: BLE001
                    pass
            self.proc = None
        if self._log_fh is not None:
            try:
                self._log_fh.close()
            except Exception:  # noqa: BLE001
                pass
            self._log_fh = None


class Play:
    """Player-level actions on top of hhbot.Bot (adapted from tools/qa/playthrough.py Play)."""

    POPUP_DISMISS = ("Maybe later", "Close", "OK", "Continue", "Got it", "Stay here", "Resume")

    def __init__(self, bot: Bot, out_dir):
        self.bot = bot
        self.out = Path(out_dir)
        self.out.mkdir(parents=True, exist_ok=True)
        self.log = bot.log
        self.t0 = time.time()
        self.shots: list[dict] = []
        self.problems: list[str] = []
        self.bugs: list[dict] = []
        self.shot_n = 0
        self.seen_msgs: list[dict] = []
        self._msg_keys: set = set()
        self.deaths = 0

    # ------------------------------------------------------------------ state
    def st(self) -> dict:
        s = self.bot.state()
        self._harvest_msgs(s)
        return s

    def _harvest_msgs(self, s):
        for m in s.get("messages", []) or []:
            k = (m.get("k"), m.get("text"), m.get("t"))
            if k in self._msg_keys:
                continue
            self._msg_keys.add(k)
            self.seen_msgs.append(m)
            if m.get("text", "") == "player died":
                self.deaths += 1
            self.log(f"MSG [{m.get('k')}] {m.get('text')}")

    def inv(self, item) -> int:
        s = self.st()
        return int(s.get("inv", {}).get(item, 0)) + int(s.get("keys", {}).get(item, 0))

    def flags(self) -> set:
        return set(self.st().get("flags", []))

    def flag(self, f) -> bool:
        return f in self.flags()

    def pos(self):
        return self.bot.pos()

    def hp(self) -> float:
        return float(self.st().get("player", {}).get("hp", 100.0))

    def area(self) -> str:
        return str(self.st().get("area", ""))

    def zone(self) -> str:
        return str(self.st().get("zone", ""))

    def nearby(self, pred=None, maxd=80.0):
        return [e for e in self.st().get("nearby", []) if e.get("dist", 999) <= maxd and (pred is None or pred(e))]

    def nearest(self, pred, maxd=80.0):
        lst = self.nearby(pred, maxd)
        return lst[0] if lst else None

    def prompt(self) -> dict:
        return self.st().get("player", {}).get("prompt", {}) or {}

    def wait(self, pred, timeout=8.0):
        return self.bot.wait_state(pred, timeout)

    def elapsed(self) -> float:
        return round(time.time() - self.t0, 1)

    def shot(self, label: str) -> str:
        """The game's own 'shot' command (headless: expected to fail - the request is kept for visible runs)."""
        self.shot_n += 1
        p = (self.out / "shots" / f"s2_{self.shot_n:03d}_{label}.png").resolve()
        p.parent.mkdir(parents=True, exist_ok=True)
        rec = {"label": label, "path": str(p), "t": self.elapsed()}
        try:
            self.bot.win.screenshot(p)
            rec["ok"] = p.exists()
        except Exception as e:  # noqa: BLE001
            rec["ok"] = False
            rec["error"] = str(e)[:160]
        self.shots.append(rec)
        return str(p)

    def bug(self, title, severity, area, steps, expected, actual, evidence):
        for b in self.bugs:
            if b["title"] == title:
                return
        self.bugs.append({"title": title, "severity": severity, "area": area, "steps": steps,
                          "expected": expected, "actual": actual, "evidence": evidence})
        self.log(f"BUG [{severity}] {title}: {actual}")

    # ------------------------------------------------------------------ UI / pop-ups
    def ui_open(self) -> bool:
        return bool(self.st().get("ui_stack"))

    def buttons(self):
        return self.st().get("buttons", [])

    def find_btn(self, text, exact=False):
        for b in self.buttons():
            t = b.get("text", "")
            if ((t == text) if exact else (text.lower() in t.lower())) and not b.get("disabled"):
                return b
        return None

    def click_b(self, b):
        """Clicks a telemetry button / slot (float rect "rf" when the shared Bot knows it)."""
        if hasattr(self.bot, "click_at_button"):
            self.bot.click_at_button(b)
        else:
            x, y, w, h = b["rect"]
            self.bot.win.click(x + w // 2, y + h // 2)

    def click(self, text, exact=False, timeout=4.0) -> bool:
        return self.bot.click_button(text, exact=exact, timeout=timeout)

    def dismiss_popups(self, tries=4) -> bool:
        """Closes whatever modal is open (wardrobe notice -> 'Maybe later', a confirm -> its cancel, panels ->
        Esc). Returns True when nothing is open any more."""
        for _ in range(tries):
            s = self.st()
            stack = s.get("ui_stack") or []
            if not stack:
                return True
            self.log(f"pop-up open: {stack}; buttons={[b['text'] for b in s.get('buttons', [])][:12]}")
            clicked = False
            for label in self.POPUP_DISMISS:
                b = self.find_btn(label, exact=True)
                if b:
                    self.click_b(b)
                    clicked = True
                    break
            if not clicked:
                self.bot.tap("ESC")
            time.sleep(0.6)
            if "pause" in (self.st().get("ui_stack") or []):
                self.click("Resume", exact=True, timeout=2.0)
                time.sleep(0.4)
        return not self.ui_open()

    # ------------------------------------------------------------------ movement
    def goto(self, target, tol=1.4, sprint=True, timeout=60.0) -> bool:
        tgt = (target[0], 0, target[1]) if len(target) == 2 else target
        t_end = time.time() + timeout
        while time.time() < t_end:
            ok = self.bot.walk_to(tgt, tol=tol, sprint=sprint, timeout=max(1.0, t_end - time.time()))
            if ok:
                return True
            if self.ui_open():
                self.dismiss_popups()
                continue
            break
        self.log(f"goto {target} failed at {self.pos()}")
        return False

    def walk_route(self, pts, tol=2.2, sprint=True, timeout_each=45.0) -> bool:
        for p in pts:
            if not self.goto(p, tol=tol, sprint=sprint, timeout=timeout_each):
                return False
        return True

    def face(self, pos, tol=4.0, turn_body=False):
        ok = self.bot.face_point(pos, tol)
        if turn_body:
            self.bot.hold("W", 0.08)
        return ok

    def approach(self, e, stop=1.3, calm=False):
        p = e["pos"]
        me = self.pos()
        d = dist2(xz(p), xz(me))
        if d > stop + 0.3:
            k = (d - stop) / d
            tgt = (me[0] + (p[0] - me[0]) * k, me[2] + (p[2] - me[2]) * k)
            self.goto(tgt, tol=0.6, sprint=(d > 8 and not calm), timeout=40)
        self.face(p, turn_body=dist2(xz(p), xz(self.pos())) <= stop + 0.5)
        time.sleep(0.25)

    # ------------------------------------------------------------------ interaction
    def prompt_matches(self, words) -> bool:
        p = self.prompt()
        t = str(p.get("text", "")).lower()
        return any(w.lower() in t for w in words)

    def press_interact_on(self, e, words, check, tries=4, stop=1.3, need_enabled=True) -> bool:
        for attempt in range(tries):
            if self.ui_open():
                self.dismiss_popups()
            self.approach(e, stop=stop)
            if not self.prompt_matches(words) and self.prompt().get("text"):
                me = self.pos()
                yaw = math.radians(self.bot.cam_yaw() or 0.0)
                fwd = (-math.sin(yaw), -math.cos(yaw))
                to = (e["pos"][0] - me[0], e["pos"][2] - me[2])
                side = fwd[0] * to[1] - fwd[1] * to[0]
                self.bot.hold("A" if side < 0 else "D", 0.18)
                self.face(e["pos"])
                time.sleep(0.3)
            if not self.prompt_matches(words):
                d = dist2(xz(e["pos"]), xz(self.pos()))
                if d < 0.9:
                    self.bot.hold("S", 0.35)
                    self.face(e["pos"])
                    self.bot.hold("W", 0.12)
                else:
                    self.bot.hold("W", 0.15)
                self.face(e["pos"])
                time.sleep(0.35)
            if self.prompt_matches(words):
                if need_enabled and not self.prompt().get("enabled", True):
                    self.log(f"prompt disabled: {self.prompt()}")
                    return False
                self.bot.tap("E")
                if self.wait(lambda s: check(), 4.0):
                    return True
            self.log(f"interact attempt {attempt + 1} on {e.get('name')} prompt={self.prompt()}")
            stop = max(0.8, stop - 0.2)
        return False

    # ------------------------------------------------------------------ gathering
    def harvest_tool(self, words, item, want, maxd=70.0, swings=16, prefer_pos=None, avoid=None, exclude_ids=()) -> bool:
        """Chop/mine with LMB until `item` count reaches `want`."""
        guard = 0
        tried: set = set(exclude_ids)
        while self.inv(item) < want and guard < 12:
            guard += 1
            pred = lambda n: (n.get("g") == "harvestable" and n.get("tool") in ("axe", "pickaxe")  # noqa: E731
                              and any(w.lower() in (n.get("label", "") + " " + n.get("id", "")).lower() for w in words)
                              and n.get("id") not in tried and (avoid is None or not avoid(n)))
            cands = self.nearby(pred, maxd)
            if prefer_pos is not None:
                cands.sort(key=lambda n: dist2(xz(n["pos"]), prefer_pos))
            if not cands:
                raise StepFailed(f"no {words} to harvest near {self.pos()}")
            e = cands[0]
            tried.add(e.get("id"))
            before = self.inv(item)
            self.log(f"harvest {e.get('label')} {e.get('id')} at {e['pos']} for {item} ({before}/{want})")
            self.approach(e, stop=1.6)
            n = 0.0
            while n < swings:
                p = self.prompt()
                if p.get("action") == "attack" and p.get("enabled", True):
                    self.bot.tap("LMB", 0.06)
                    time.sleep(0.6)
                    n += 1
                    if self.inv(item) >= want:
                        break
                    if self.inv(item) > before and not self._harvestable(e):
                        break
                else:
                    if p.get("action") == "attack" and not p.get("enabled", True):
                        self.log(f"harvest prompt disabled: {p}")
                        break
                    if not self._harvestable(e):
                        break
                    self.bot.hold("W", 0.12)
                    self.face(e["pos"])
                    time.sleep(0.2)
                    n += 0.5
            time.sleep(0.9)
        return self.inv(item) >= want

    def _harvestable(self, e) -> bool:
        for n in self.nearby(maxd=90):
            if n.get("id") and n.get("id") == e.get("id") and n.get("g") == "harvestable":
                return True
        return False

    # ------------------------------------------------------------------ food
    def slot_btn(self, item):
        for b in self.buttons():
            if b["text"].startswith("slot:bag:") and b.get("item") == item and not b.get("clipped"):
                return b
        return None

    def eat_best(self, foods=("pumpkin_soup", "berry_snack", "roseberries", "pumpkin", "berries", "candy")) -> bool:
        """Eats one food. Hotbar first (number key selects the slot, then use_item = Q), else the backpack panel
        (click the slot, then its 'Eat' / 'Use' button). Note: a double-click cannot be injected (qa_input clicks
        carry no double_click flag), so the Chapter One bot's double-click path does not work in this mode."""
        for food in foods:
            if self.inv(food) <= 0:
                continue
            before_n = self.inv(food)
            before_hp = self.hp()
            hb = self.st().get("hotbar", []) or []
            if food in hb:
                i = hb.index(food)
                self.bot.tap(str(i + 1))
                time.sleep(0.15)
                self.bot.tap("Q")
                if self.wait(lambda s: int(s.get("inv", {}).get(food, 0)) < before_n, 2.0):
                    self.log(f"ate {food} (hotbar {i + 1}); hp {before_hp} -> {self.hp()}")
                    return True
                self.log(f"hotbar eat of {food} did nothing (hp {self.hp()})")
            self.bot.tap("TAB")
            if not self.wait(lambda s: "inventory" in (s.get("ui_stack") or []), 3.0):
                self.dismiss_popups()
                continue
            time.sleep(0.4)
            b = self.slot_btn(food)
            if b:
                self.click_b(b)
                time.sleep(0.35)
                for label in ("Eat", "Use"):
                    ub = self.find_btn(label, exact=True)
                    if ub:
                        self.click_b(ub)
                        break
                time.sleep(0.5)
            else:
                self.log(f"no visible bag slot for {food}")
            self.dismiss_popups()
            if self.inv(food) < before_n:
                self.log(f"ate {food} (backpack); hp {before_hp} -> {self.hp()}")
                return True
        return False

    def heal_up(self, target=85.0, max_items=8) -> int:
        n = 0
        while self.hp() < target and n < max_items:
            before = self.hp()
            if not self.eat_best():
                break
            n += 1
            time.sleep(0.8)
            if self.hp() <= before:
                time.sleep(1.0)
        return n

    # ------------------------------------------------------------------ combat
    def live_enemies(self, pred=None, maxd=30.0):
        return [e for e in self.nearby(lambda n: n.get("g") == "enemy" and (pred is None or pred(n)), maxd)
                if e.get("hp", 1) > 0 and e.get("state") not in ("dead", "dying")]

    def dodge(self, direction="S"):
        self.bot.down(direction)
        self.bot.tap("CTRL")
        time.sleep(0.25)
        self.bot.up(direction)

    def fight(self, pred=None, timeout=90.0, flee_hp=35.0, maxd=30.0, leash=None) -> bool:
        """Fight nearby enemies with real inputs until none remain (adapted from playthrough.Play.fight)."""
        t0 = time.time()
        last_seen = time.time()
        while time.time() - t0 < timeout:
            if self.ui_open():
                self.dismiss_popups()
            live = self.live_enemies(pred, maxd)
            if not live:
                if time.time() - last_seen > 3.0:
                    return True
                time.sleep(0.3)
                continue
            last_seen = time.time()
            e = live[0]
            if self.hp() < flee_hp:
                self.dodge("S")
                self.heal_up(target=flee_hp + 25, max_items=3)
                continue
            d = e["dist"]
            self.face(e["pos"], tol=8)
            state = str(e.get("state", ""))
            if state in ("telegraph", "windup", "wind_up") and d < 3.6:
                self.dodge("S")
                continue
            if d > 2.0:
                self.bot.hold("W", min(0.5, (d - 1.6) / 5.0 + 0.1))
            else:
                self.bot.tap("LMB", 0.06)
                time.sleep(0.45)
        return False
