"""Segment S4 helpers: launch the SOURCE build HEADLESS with virtual input + QA telemetry, a float-precise input
transport, and the small play primitives the S4 route needs (walk, face, interact, UI clicks, fight, eat).

Owned by the S4 segment (tools/qa/ch2/s4_*.py). Small helpers are COPIED/adapted here instead of editing the
shared hhbot.py / session.py / playthrough.py / qa_telemetry.gd (owned by the route "S0").

Launch line (AGENTS.md virtual-input QA mode, headless variant; nothing here opens a window, sends OS input or
takes desktop screenshots):
  .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --max-fps 60 --
      --qa-input-port=<port> --qa-no-focus --qa-telemetry=<file> --qa-interval=0.1 --save-dir=<run>/saves
      --settings-file=<run>/settings.cfg --no-focus-pause --max-seconds=<n> [--seed=N] [--no-wardrobe-notice]
The console exe wraps the real Godot exe as a child process, so stop() kills the TREE of the pid this module
created (taskkill /T /F /PID <our pid>) - never any other Godot process.

Headless specifics (observed; the S0 telemetry notes them too): the root window is 64x64 px while the UI is laid
out for 1920x1080, so one window pixel = 30 UI pixels. Button rects are therefore read from the float "rf" field
and clicks / relative mouse motion are sent as FLOATS (hhbot.VirtualInput rounds them to ints, which makes the
camera turn in ~4 degree steps and misses small buttons).
"""
from __future__ import annotations

import json
import math
import shutil
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
SEGMENT = 4

if str(QA_DIR) not in sys.path:
    sys.path.insert(0, str(QA_DIR))

from hhbot import Bot, Telemetry, VirtualInput, VirtualInputError, angle_diff  # noqa: E402


# ---------------------------------------------------------------------------------------------- process
def port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def pick_port(attempt: int) -> int:
    """segment * 100 + 7000 + attempt (S4: 7400 + attempt); bumped by 10 while taken."""
    p = SEGMENT * 100 + 7000 + (attempt % 100)
    for _ in range(9):
        if port_free(p):
            return p
        p += 10
    raise RuntimeError(f"no free port near {SEGMENT * 100 + 7000 + attempt}")


def kill_tree(pid: int) -> None:
    try:
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, timeout=20)
    except Exception:  # noqa: BLE001
        pass


def place_save(save_dir: Path, src: Path, bak: Path | None = None) -> Path:
    """Copies `src` to <save_dir>/slot1.json (clearing the folder first). Never touches `src`."""
    save_dir.mkdir(parents=True, exist_ok=True)
    for f in save_dir.glob("*"):
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)
    shutil.copyfile(src, save_dir / "slot1.json")
    if bak is not None and Path(bak).exists():
        shutil.copyfile(bak, save_dir / "slot1.bak.json")
    return save_dir / "slot1.json"


class FloatInput(VirtualInput):
    """VirtualInput that keeps sub-pixel precision (headless: 1 window px = 30 UI px)."""

    def mouse_move(self, dx, dy):
        self.request({"mm": [round(float(dx), 4), round(float(dy), 4)]})

    def click(self, x, y, button: str = "left"):
        self.request({"click": [round(float(x), 4), round(float(y), 4)], "button": button})

    def hover(self, x, y):
        self.request({"move": [round(float(x), 4), round(float(y), 4)]})


class HeadlessGame:
    """One headless game process + float virtual input + telemetry tail + an hhbot.Bot."""

    def __init__(self, run_dir, name: str, port: int, max_seconds: int = 1800, seed: int | None = None,
                 extra: list[str] | None = None, max_fps: int = 60):
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
        self.proc: subprocess.Popen | None = None
        self.bot: Bot | None = None
        self.vin: FloatInput | None = None
        self.t_launch = 0.0
        self.cmd: list[str] = []

    def args(self) -> list[str]:
        engine = ["--headless", "--path", str(GAME_DIR)]
        if self.max_fps > 0:
            engine += ["--max-fps", str(self.max_fps)]
        user = [f"--qa-input-port={self.port}", "--qa-no-focus", f"--qa-telemetry={self.tele_path.as_posix()}",
                "--qa-interval=0.1", f"--save-dir={self.save_dir.as_posix()}",
                f"--settings-file={self.settings_file.as_posix()}", "--no-focus-pause",
                f"--max-seconds={int(self.max_seconds)}"]
        if self.seed is not None:
            user.append(f"--seed={int(self.seed)}")
        return engine + ["--"] + user + self.extra

    def start(self, connect_timeout: float = 120.0) -> Bot:
        if self.tele_path.exists():
            self.tele_path.unlink()
        self.cmd = [str(GODOT_CONSOLE)] + self.args()
        logf = open(self.godot_log, "a", encoding="utf-8", errors="replace")
        logf.write(f"\n==== launch {time.strftime('%Y-%m-%d %H:%M:%S')}: {self.cmd}\n")
        logf.flush()
        self.t_launch = time.time()
        self.proc = subprocess.Popen(self.cmd, cwd=str(ROOT), stdout=logf, stderr=subprocess.STDOUT,
                                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        tele = Telemetry(self.tele_path)
        try:
            self.vin = FloatInput(self.port, proc=self.proc, tele=tele, connect_timeout=connect_timeout)
        except Exception:
            self.stop()
            raise
        self.bot = Bot(self.vin, tele, self.log_path)
        self.bot.log(f"launched headless pid={self.proc.pid} port={self.port} cmd={self.cmd}")
        return self.bot

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def stop(self) -> None:
        if self.vin is not None:
            try:
                self.vin.close()
            except Exception:  # noqa: BLE001
                pass
            self.vin = None
        if self.proc is not None:
            if self.proc.poll() is None:
                kill_tree(self.proc.pid)
                try:
                    self.proc.wait(10)
                except Exception:  # noqa: BLE001
                    pass
            self.proc = None


# ---------------------------------------------------------------------------------------------- geometry
def xz(p):
    return (p[0], p[2]) if len(p) >= 3 else (p[0], p[1])


def dist2(a, b):
    a, b = xz(a) if len(a) >= 3 else a, xz(b) if len(b) >= 3 else b
    return math.hypot(a[0] - b[0], a[1] - b[1])


class StepFailed(Exception):
    pass


# ---------------------------------------------------------------------------------------------- play layer
class Play:
    """Route-level primitives on top of hhbot.Bot (read-only telemetry in, keyboard/mouse out)."""

    def __init__(self, game: HeadlessGame, out_dir: Path):
        self.g = game
        self.bot: Bot = game.bot
        self.out = Path(out_dir)
        self.log = self.bot.log
        self.shots: list[dict] = []
        self.problems: list[dict] = []
        self.msg_seen: set = set()
        self.all_msgs: list[dict] = []

    # ------------------------------------------------------------------ state
    def st(self) -> dict:
        s = self.bot.state()
        self._harvest_msgs(s)
        return s

    def _harvest_msgs(self, s):
        for m in s.get("messages", []) or []:
            key = (m.get("k"), m.get("text"), m.get("t"))
            if key not in self.msg_seen:
                self.msg_seen.add(key)
                self.all_msgs.append(m)
                if len(self.all_msgs) > 4000:
                    self.all_msgs = self.all_msgs[-3000:]
                self.bot.log(f"  msg[{m.get('k')}] {str(m.get('text'))[:220]}")

    def flags(self) -> set:
        return set(self.st().get("flags", []))

    def flag(self, f: str) -> bool:
        return f in self.flags()

    def inv(self, item: str) -> int:
        s = self.st()
        return int((s.get("inv") or {}).get(item, 0)) + int((s.get("keys") or {}).get(item, 0))

    def pos(self):
        return self.bot.pos()

    def area(self) -> str:
        return str(self.st().get("area", ""))

    def zone(self) -> str:
        return str(self.st().get("zone", ""))

    def hp(self) -> float:
        return float(self.st().get("player", {}).get("hp", 100.0))

    def mode(self) -> str:
        return str(self.st().get("mode", ""))

    def ui(self) -> list:
        return list(self.st().get("ui_stack", []) or [])

    def prompt(self) -> dict:
        return self.st().get("player", {}).get("prompt", {}) or {}

    def nearby(self, pred=None, maxd: float = 80.0) -> list:
        out = []
        for e in self.st().get("nearby", []) or []:
            if e.get("dist", 999) <= maxd and (pred is None or pred(e)):
                out.append(e)
        return out

    def nearest(self, pred, maxd: float = 80.0):
        lst = self.nearby(pred, maxd)
        return lst[0] if lst else None

    def find_text(self, words, maxd: float = 80.0, groups=("interactable", "checkpoint", "crafting_station")):
        words = [w.lower() for w in ([words] if isinstance(words, str) else words)]
        return self.nearest(lambda n: n.get("g") in groups and any(w in str(n.get("text", "")).lower() for w in words), maxd)

    def wait(self, pred, timeout: float = 8.0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            s = self.st()
            try:
                if s and pred(s):
                    return s
            except (KeyError, TypeError, IndexError, ValueError):
                pass
            time.sleep(0.05)
        return None

    def wait_flag(self, f: str, timeout: float = 6.0) -> bool:
        return self.wait(lambda s: f in s.get("flags", []), timeout) is not None

    def wait_playing(self, timeout: float = 60.0) -> bool:
        return self.wait(lambda s: s.get("mode") == "playing" and not s.get("ui_stack"), timeout) is not None

    def recent_text(self, since_t: float = -1.0, kinds=None) -> list[str]:
        out = []
        for m in self.all_msgs:
            if (kinds is None or m.get("k") in kinds) and float(m.get("t", 0)) >= since_t:
                out.append(str(m.get("text", "")))
        return out

    def game_t(self) -> float:
        return float(self.st().get("t", 0.0))

    # ------------------------------------------------------------------ evidence
    def shot(self, label: str) -> dict:
        p = self.out / "shots" / f"{len(self.shots) + 1:03d}_{label}.png"
        rec = {"label": label, "path": str(p), "t": round(time.time() - self.g.t_launch, 1)}
        try:
            self.g.vin.request({"shot": p.as_posix()}, timeout=20.0)
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001  (headless has no viewport image: expected to fail)
            rec["ok"] = False
            rec["error"] = str(e)[:160]
        self.shots.append(rec)
        return rec

    def problem(self, kind: str, text: str, **extra):
        rec = {"kind": kind, "text": text, "t": round(time.time() - self.g.t_launch, 1), "pos": self.pos(),
               "area": self.area(), "zone": self.zone()}
        rec.update(extra)
        self.problems.append(rec)
        self.log(f"PROBLEM [{kind}] {text}")

    # ------------------------------------------------------------------ looking / moving
    def face(self, target, tol: float = 4.0, body: bool = False) -> bool:
        ok = self.bot.face_point(target, tol)
        if body:
            self.bot.hold("W", 0.06)
        return ok

    def look_pitch(self, deg: float) -> bool:
        return self.bot.look_pitch(deg, tol=3.0, timeout=2.0)

    def goto(self, target, tol: float = 1.2, sprint: bool = True, timeout: float = 60.0) -> bool:
        tgt = (target[0], 0.0, target[1]) if len(target) == 2 else tuple(target)
        ok = self.walk_to(tgt, tol=tol, sprint=sprint, timeout=timeout)
        if not ok:
            self.log(f"goto {target} failed at {self.pos()}")
        return ok

    def walk_to(self, target, tol=1.2, timeout=40.0, sprint=False, avoid=True) -> bool:
        """hhbot.Bot.walk_to with float steering (headless look precision) and ui/cutscene awareness."""
        b = self.bot
        t0 = time.time()
        last_prog_t = time.time()
        best = 1e9
        stuck = 0
        b.down("W")
        if sprint:
            b.down("SHIFT")
        try:
            while time.time() - t0 < timeout:
                s = self.st()
                if s.get("ui_stack") or s.get("mode") not in ("playing",):
                    b.release_all()
                    if s.get("ui_stack"):
                        return False
                    time.sleep(0.2)
                    b.down("W")
                    if sprint:
                        b.down("SHIFT")
                    continue
                p = self.pos()
                d = math.hypot(target[0] - p[0], target[2] - p[2])
                if d <= tol:
                    return True
                want = b.yaw_to(p, target)
                y = b.cam_yaw()
                if y is not None:
                    dd = angle_diff(want, y)
                    if abs(dd) > 1.5:
                        step = max(-30.0, min(30.0, dd))
                        b.win.mouse_move(-step * b.px_per_deg * b.invert * 0.7, 0)
                if d < best - 0.25:
                    best = d
                    last_prog_t = time.time()
                elif time.time() - last_prog_t > 1.8 and avoid:
                    stuck += 1
                    self.log(f"walk_to stuck at {p} -> {target} (d {d:.1f}); unstick #{stuck}")
                    b.tap("SPACE")
                    b.up("W")
                    b.hold("A" if stuck % 2 else "D", 0.5 + 0.15 * stuck)
                    b.down("W")
                    last_prog_t = time.time()
                    if stuck > 7:
                        return False
                time.sleep(0.05)
            return False
        finally:
            b.release_all()

    def route(self, pts, tol: float = 1.3, sprint: bool = True, fight: bool = False, timeout_each: float = 40.0) -> bool:
        for pt in pts:
            if fight:
                self.fight_if_threat(10.0)
            if not self.goto(pt, tol=tol, sprint=sprint, timeout=timeout_each):
                if fight:
                    self.fight_if_threat(14.0)
                if not self.goto(pt, tol=tol + 0.4, sprint=False, timeout=timeout_each):
                    return False
        return True

    # ------------------------------------------------------------------ interaction
    def prompt_text(self) -> str:
        return str(self.prompt().get("text", ""))

    def prompt_matches(self, words) -> bool:
        words = [words] if isinstance(words, str) else words
        t = self.prompt_text().lower()
        return any(w.lower() in t for w in words) and bool(self.prompt().get("enabled", True))

    def approach(self, e_or_pos, stop: float = 1.3, sprint: bool = False):
        p = e_or_pos["pos"] if isinstance(e_or_pos, dict) else e_or_pos
        me = self.pos()
        d = dist2(xz(p), xz(me))
        if d > stop + 0.3:
            k = (d - stop) / d
            tgt = (me[0] + (p[0] - me[0]) * k, me[2] + (p[2] - me[2]) * k)
            self.goto(tgt, tol=0.5, sprint=sprint and d > 6, timeout=40)
        self.face(p, tol=3.0)
        time.sleep(0.15)

    def interact_with(self, e_or_pos, words, check=None, tries: int = 5, stop: float = 1.3, settle: float = 0.25,
                      pitch: float | None = None) -> bool:
        """Walk up to a target, find the prompt that matches `words` (strafe / step / look around) and press E.
        check(): the result the press should produce (default: the prompt changed)."""
        p = e_or_pos["pos"] if isinstance(e_or_pos, dict) else e_or_pos
        for attempt in range(tries):
            self.approach(p, stop=stop)
            if pitch is not None:
                self.look_pitch(pitch)
            time.sleep(settle)
            if not self.prompt_matches(words):
                self._nudge_toward(p, attempt)
            if self.prompt_matches(words):
                before = self.prompt_text()
                n_msgs = len(self.all_msgs)
                self.bot.tap("E")
                if check is None:
                    # default: the prompt changed, a panel opened, or the game answered (a line, caption, toast)
                    ok = self.wait(lambda s: str((s.get("player", {}).get("prompt") or {}).get("text", "")) != before
                                   or s.get("ui_stack") or any(m.get("k") in ("say", "caption", "notify", "quest", "saved")
                                                               for m in self.all_msgs[n_msgs:]), 3.0) is not None
                else:
                    ok = self.wait(lambda s: check(), 4.0) is not None
                if ok:
                    return True
            self.log(f"interact attempt {attempt + 1} for {words} at {p}: prompt={self.prompt()} me={self.pos()}")
            stop = max(0.7, stop - 0.2)
        return False

    def _nudge_toward(self, p, attempt: int):
        me = self.pos()
        d = dist2(xz(p), xz(me))
        if self.prompt_text():
            # a neighbour holds the focus: strafe toward the target's side
            yaw = math.radians(self.bot.cam_yaw() or 0.0)
            fwd = (-math.sin(yaw), -math.cos(yaw))
            to = (p[0] - me[0], p[2] - me[2])
            side = fwd[0] * to[1] - fwd[1] * to[0]
            self.bot.hold("A" if side < 0 else "D", 0.15)
            self.face(p, tol=3.0)
            time.sleep(0.25)
            if self.prompt_text():
                return
        if d < 0.9:
            self.bot.hold("S", 0.3)
            self.face(p, tol=3.0)
            self.bot.hold("W", 0.1)
        else:
            self.bot.hold("W", 0.12)
        self.face(p, tol=3.0)
        # look slightly down / up in alternation (low targets such as floor valves, high plates)
        if attempt % 2 == 1:
            self.look_pitch(-25.0 if attempt % 4 == 1 else 5.0)
        time.sleep(0.25)

    # ------------------------------------------------------------------ UI
    def buttons(self) -> list:
        return list(self.st().get("buttons", []) or [])

    def find_button(self, text: str, exact: bool = False):
        for b in self.buttons():
            t = str(b.get("text", ""))
            if ((t.strip() == text.strip()) if exact else (text.lower() in t.lower())) and not b.get("disabled"):
                return b
        return None

    def click_button(self, text: str, exact: bool = False, timeout: float = 5.0) -> bool:
        t0 = time.time()
        while time.time() - t0 < timeout:
            b = self.find_button(text, exact)
            if b:
                r = b.get("rf") or b.get("rect")
                x, y, w, h = [float(v) for v in r]
                self.g.vin.click(x + w / 2.0, y + h / 2.0)
                time.sleep(0.3)
                return True
            time.sleep(0.15)
        self.log(f"button not found: {text!r}; visible: {[b.get('text') for b in self.buttons()][:30]}")
        return False

    def close_panels(self) -> bool:
        for _ in range(4):
            if not self.ui():
                return True
            self.bot.tap("ESC")
            time.sleep(0.4)
        if "pause" in self.ui():
            self.click_button("Resume", exact=True)
        return not self.ui()

    def slot_rect(self, item: str):
        for b in self.buttons():
            if str(b.get("text", "")).startswith("slot:bag:") and b.get("item") == item and not b.get("clipped"):
                return b.get("rf") or b.get("rect")
        return None

    def eat_best(self, foods=("hearty_stew", "pumpkin_soup", "roseberry_tart", "berry_snack", "glowcap_skewer",
                               "pumpkin_biscuit", "candy", "sweetroot", "roseberries", "berries")) -> bool:
        """Inventory (TAB) -> select the food slot -> the detail panel's "Eat" button (virtual input sends no OS
        double-click flag, so the slot double-click shortcut is not used)."""
        for food in foods:
            n0 = self.inv(food)
            if n0 > 0:
                hp0 = self.hp()
                self.bot.tap("TAB")
                if not self.wait(lambda s: "inventory" in (s.get("ui_stack") or []), 3.0):
                    self.close_panels()
                    return False
                time.sleep(0.35)
                r = self.slot_rect(food)
                if r:
                    x, y, w, h = [float(v) for v in r]
                    self.g.vin.click(x + w / 2, y + h / 2)
                    time.sleep(0.3)
                    self.click_button("Eat", exact=True, timeout=2.0)
                    time.sleep(0.3)
                self.close_panels()
                ate = self.inv(food) < n0
                self.log(f"eat {food}: {'ok' if ate else 'FAILED'}; hp {hp0} -> {self.hp()}")
                if not ate:
                    self.eat_failures = getattr(self, "eat_failures", 0) + 1
                return ate
        return False

    def lantern(self, on: bool) -> bool:
        for _ in range(3):
            if bool(self.st().get("player", {}).get("lantern")) == on:
                return True
            self.bot.tap("F")
            time.sleep(0.35)
        return bool(self.st().get("player", {}).get("lantern")) == on

    # ------------------------------------------------------------------ combat
    def live_enemies(self, maxd: float = 30.0, pred=None) -> list:
        return [e for e in self.nearby(lambda n: n.get("g") == "enemy", maxd)
                if float(e.get("hp", 1) or 0) > 0 and str(e.get("state", "")) not in ("dead", "dying", "gone")
                and (pred is None or pred(e))]

    def fight_if_threat(self, radius: float = 10.0) -> bool:
        if self.live_enemies(radius, lambda e: e.get("threat", True)):
            return self.fight(timeout=90.0)
        return True

    def fight(self, pred=None, timeout: float = 90.0, flee_hp: float = 35.0, radius: float = 26.0) -> bool:
        t0 = time.time()
        last_seen = time.time()
        b = self.bot
        while time.time() - t0 < timeout:
            live = self.live_enemies(radius, pred)
            if not live:
                if time.time() - last_seen > 3.0:
                    return True
                time.sleep(0.3)
                continue
            last_seen = time.time()
            e = live[0]
            if self.hp() < flee_hp:
                b.hold("S", 0.25)
                if not self.eat_best():
                    pass
                continue
            d = float(e["dist"])
            self.face(e["pos"], tol=8)
            state = str(e.get("state", ""))
            if state in ("telegraph", "windup", "wind_up", "tele", "swing_tele") and d < 3.5:
                b.down("S")
                b.tap("CTRL")
                time.sleep(0.25)
                b.up("S")
                continue
            if d > 2.0:
                b.hold("W", min(0.5, (d - 1.6) / 5.0 + 0.1))
            else:
                b.tap("LMB", 0.06)
                time.sleep(0.4)
        return False


def write_json(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=1, default=str), encoding="utf-8")
