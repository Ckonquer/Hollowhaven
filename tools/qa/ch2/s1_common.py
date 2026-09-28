"""Segment S1 helpers: launch the SOURCE build HEADLESS with virtual input and QA telemetry, drive it with the
shared hhbot.Bot, stop it again (only the process tree this module started).

Owned by the S1 segment (tools/qa/ch2/s1_*.py). Copies/adapts small helpers instead of editing the shared
hhbot.py / session.py / playthrough.py (owned by the route "S0").

Launch line (AGENTS.md "second-monitor / virtual-input QA mode", headless variant):
  .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game [--max-fps 60] --
      --qa-input-port=<port> --qa-no-focus --qa-telemetry=<file> --qa-interval=0.1 --save-dir=<run>/saves
      --settings-file=<run>/settings.cfg --no-focus-pause --max-seconds=<n> [--seed=N]
Nothing here opens a window, sends OS input or takes desktop screenshots. The console exe is a wrapper that
starts the real Godot exe as a child, so stop() kills the whole tree of the pid this module created
(taskkill /T /F /PID <our pid>) - never any other Godot process.
"""
from __future__ import annotations

import json
import math
import os
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
REAL_SAVE = GAME_DIR / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.json"
REAL_SAVE_BAK = GAME_DIR / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.bak.json"

if str(QA_DIR) not in sys.path:
    sys.path.insert(0, str(QA_DIR))

from hhbot import Bot, Telemetry, VirtualInput, VirtualInputError  # noqa: E402


def port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def pick_port(segment: int, attempt: int) -> int:
    """segment * 100 + 7000 + attempt, bumped by 10 while taken (a parallel run or a dying earlier one)."""
    p = segment * 100 + 7000 + attempt
    for _ in range(9):
        if port_free(p):
            return p
        p += 10
    raise RuntimeError(f"no free port near {segment * 100 + 7000 + attempt}")


def prepare_saves(save_dir: Path, src: Path = REAL_SAVE, bak: Path | None = None) -> Path:
    """Places a COPY of `src` as <save_dir>/slot1.json (and optionally the .bak). Never touches `src`."""
    save_dir.mkdir(parents=True, exist_ok=True)
    for f in save_dir.glob("*"):
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)
    dst = save_dir / "slot1.json"
    shutil.copyfile(src, dst)
    if bak is not None and bak.exists():
        shutil.copyfile(bak, save_dir / "slot1.bak.json")
    return dst


def kill_tree(pid: int) -> None:
    """Kills pid and its children (only processes this module created: the console wrapper and its child)."""
    try:
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, timeout=20)
    except Exception:  # noqa: BLE001
        pass


class HeadlessGame:
    """One headless game process + virtual input + telemetry tail + a Bot."""

    def __init__(self, run_dir: str | Path, name: str, port: int, save_dir: str | Path | None = None,
                 max_seconds: int = 1800, seed: int | None = None, extra: list[str] | None = None,
                 max_fps: int = 60, exe: str | Path = GODOT_CONSOLE):
        self.run = Path(run_dir).resolve()
        self.run.mkdir(parents=True, exist_ok=True)
        self.name = name
        self.port = port
        self.save_dir = Path(save_dir).resolve() if save_dir else self.run / "saves"
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
        self.vin: VirtualInput | None = None
        self.shots: list[dict] = []
        self.t_launch = 0.0

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

    def start(self, connect_timeout: float = 90.0) -> Bot:
        if self.tele_path.exists():
            self.tele_path.unlink()
        cmd = [self.exe] + self.args()
        logf = open(self.godot_log, "a", encoding="utf-8", errors="replace")
        logf.write(f"\n==== launch {time.strftime('%Y-%m-%d %H:%M:%S')}: {cmd}\n")
        logf.flush()
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.t_launch = time.time()
        self.proc = subprocess.Popen(cmd, cwd=str(ROOT), stdout=logf, stderr=subprocess.STDOUT, creationflags=flags)
        tele = Telemetry(self.tele_path)
        try:
            self.vin = FloatVI(self.port, proc=self.proc, tele=tele, connect_timeout=connect_timeout)
        except Exception:
            self.stop()
            raise
        self.bot = S1Bot(self.vin, tele, self.log_path)
        self.bot.log(f"launched headless pid={self.proc.pid} port={self.port} cmd={cmd}")
        return self.bot

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def shot(self, label: str) -> dict:
        """The game's own 'shot' command. Headless runs refuse it (no viewport image); the request is kept so a
        visible run of the same route captures it."""
        p = self.run / "shots" / f"{self.name}_{len(self.shots) + 1:03d}_{label}.png"
        rec = {"label": label, "path": str(p), "t": round(time.time() - self.t_launch, 1)}
        try:
            self.vin.request({"shot": p.as_posix()}, timeout=20.0)
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001
            rec["ok"] = False
            rec["error"] = str(e)[:200]
        self.shots.append(rec)
        return rec

    def wait_exit(self, timeout: float) -> bool:
        if self.proc is None:
            return True
        try:
            self.proc.wait(timeout)
            return True
        except subprocess.TimeoutExpired:
            return False

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
        if self.bot is not None and self.bot.log_file:
            try:
                self.bot.log_file.flush()
            except Exception:  # noqa: BLE001
                pass


class FloatVI(VirtualInput):
    """VirtualInput with sub-pixel mouse motion and clicks. Headless runs draw the 1920x1080 UI into a 64x64 root
    window (1/30 scale), so one integer window pixel is 30 UI pixels and ~7.7 degrees of camera yaw; qa_input
    accepts float coordinates, the shared transport rounds them to int."""

    def mouse_move(self, dx, dy):
        self.request({"mm": [float(dx), float(dy)]})

    def click(self, x, y, button: str = "left"):
        self.request({"click": [float(x), float(y)], "button": button})

    def hover(self, x, y):
        self.request({"move": [float(x), float(y)]})


def button_center(b: dict) -> tuple[float, float]:
    """Centre of a telemetry button in window pixels: the float rect "rf" when the telemetry has it, else the
    truncated int rect corrected by the expected truncation error (true centre in [x+w/2, x+w/2+1.5))."""
    rf = b.get("rf")
    if isinstance(rf, list) and len(rf) == 4:
        return rf[0] + rf[2] / 2.0, rf[1] + rf[3] / 2.0
    x, y, w, h = b["rect"]
    return x + w / 2.0 + 0.75, y + h / 2.0 + 0.75


class S1Bot(Bot):
    """hhbot.Bot with float-precision look/steering and float clicks (see FloatVI)."""

    calibrated = False

    def calibrate_look(self) -> float:
        """Measures window px per degree of camera yaw with small FRACTIONAL motions. Only while the camera can turn
        (playing, no menu/card open: in menus the motion moves the pointer instead); retried by ensure_calibrated()."""
        if not self.wait_state(lambda s: s.get("mode") == "playing" and not s.get("ui_stack"), 10.0):
            self.log("calibrate_look: a menu is open - calibration postponed")
            return self.px_per_deg
        time.sleep(0.25)
        y0 = self.cam_yaw()
        step = 1.0     # window px; several degrees in a headless 64 px window
        for _ in range(3):
            self.win.mouse_move(step, 0)
            time.sleep(0.04)
        time.sleep(0.4)
        y1 = self.cam_yaw()
        if y0 is None or y1 is None:
            return self.px_per_deg
        d = angle_diff(y1, y0)
        if abs(d) > 0.5 and abs(d) < 170.0:
            self.px_per_deg = 3 * step / abs(d)
            self.invert = -1.0 if d > 0 else 1.0
            self.calibrated = True
        self.log(f"calibrated look: {self.px_per_deg:.4f} px/deg (dyaw={d:.1f}) invert={self.invert} ok={self.calibrated}")
        return self.px_per_deg

    def ensure_calibrated(self) -> bool:
        for _ in range(3):
            if self.calibrated:
                return True
            self.calibrate_look()
        return self.calibrated

    def turn_to_yaw(self, target: float, tol: float = 3.0, timeout: float = 3.0) -> bool:
        self.ensure_calibrated()
        t0 = time.time()
        while time.time() - t0 < timeout:
            y = self.cam_yaw()
            if y is None:
                time.sleep(0.05)
                continue
            d = angle_diff(target, y)
            if abs(d) <= tol:
                return True
            step = max(-60.0, min(60.0, d))
            self.win.mouse_move(-step * self.px_per_deg * self.invert * 0.85, 0)
            time.sleep(0.12)
        return False

    def look_pitch(self, target: float, tol: float = 4.0, timeout: float = 2.0) -> bool:
        t0 = time.time()
        while time.time() - t0 < timeout:
            p = self.player().get("cam_pitch")
            if p is None:
                return False
            d = target - p
            if abs(d) <= tol:
                return True
            step = max(-30.0, min(30.0, d))
            self.win.mouse_move(0, -step * self.px_per_deg * 0.8)
            time.sleep(0.12)
        return False

    def walk_to(self, target, tol: float = 1.2, timeout: float = 40.0, sprint: bool = False, avoid: bool = True) -> bool:
        """hhbot.Bot.walk_to with float steering (headless yaw resolution)."""
        self.ensure_calibrated()
        t0 = time.time()
        last_prog_t = time.time()
        best = 1e9
        stuck_tries = 0
        self.down("W")
        if sprint:
            self.down("SHIFT")
        try:
            while time.time() - t0 < timeout:
                s = self.state()
                if s.get("ui_stack"):
                    self.release_all()
                    return False
                p = self.pos()
                dist = math.hypot(target[0] - p[0], target[2] - p[2])
                if dist <= tol:
                    return True
                want = self.yaw_to(p, target)
                y = self.cam_yaw()
                if y is not None:
                    d = angle_diff(want, y)
                    if abs(d) > 1.5:
                        step = max(-30.0, min(30.0, d))
                        self.win.mouse_move(-step * self.px_per_deg * self.invert * 0.6, 0)
                if dist < best - 0.3:
                    best = dist
                    last_prog_t = time.time()
                elif time.time() - last_prog_t > 1.6 and avoid:
                    stuck_tries += 1
                    self.log(f"walk_to stuck at {p} (dist {dist:.1f}); unstick #{stuck_tries}")
                    self.tap("SPACE")
                    side = "A" if stuck_tries % 2 else "D"
                    self.up("W")
                    self.hold(side, 0.6 + 0.2 * stuck_tries)
                    self.down("W")
                    last_prog_t = time.time()
                    if stuck_tries > 8:
                        return False
                time.sleep(0.05)
            return False
        finally:
            self.release_all()

    def click_button(self, text: str, exact: bool = False, timeout: float = 5.0) -> bool:
        def match(b):
            t = b.get("text", "")
            return ((t == text) if exact else (text.lower() in t.lower())) and not b.get("disabled")
        s = self.wait_state(lambda st: any(match(b) for b in st.get("buttons", [])), timeout)
        if not s:
            self.log(f"button not found: {text!r}; visible: {[b['text'] for b in self.buttons()][:40]}")
            return False
        b = next(b for b in s["buttons"] if match(b))
        cx, cy = button_center(b)
        self.win.click(cx, cy)
        time.sleep(0.3)
        return True


def angle_diff(a: float, b: float) -> float:
    return (a - b + 180.0) % 360.0 - 180.0


def load_json(p: Path) -> dict:
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def xz(p):
    return (p[0], p[2]) if len(p) == 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])
