"""Test-session helpers: launch a Hollowhaven build with telemetry, record steps and evidence.

A Session owns one game process. Results are appended to <out>/results.jsonl (one row per check:
build, environment, steps, expected, observed, result, evidence) so QA_REPORT.md can quote them.

Input transports (see hhbot.py):
* default: SendInput into the focused game window (needs the PC's keyboard and mouse).
* virtual_input=True (--virtual-input / --second-monitor): the game is started with its localhost-only
  virtual-input server (--qa-input-port), --qa-no-focus, an isolated --settings-file and --save-dir under the
  run's out dir, and the bot sends JSON commands instead of OS input; qa_window places the borderless window
  (--second-monitor: 1920,0,1920,1080 = DISPLAY2 to the right of a 1080p primary).
"""
from __future__ import annotations

import json
import os
import platform
import shutil
import socket
import subprocess
import time
from pathlib import Path

from hhbot import Bot, GameWindow, Telemetry, VirtualInput

SECOND_MONITOR_RECT = "1920,0,1920,1080"
SW_SHOWNOACTIVATE = 4


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def parse_rect(text: str) -> tuple[int, int, int, int]:
    parts = [int(p.strip()) for p in str(text).split(",")]
    if len(parts) != 4 or parts[2] < 64 or parts[3] < 64:
        raise ValueError(f"window rect must be x,y,w,h (got {text!r})")
    return parts[0], parts[1], parts[2], parts[3]


def override_cfg(rect: tuple[int, int, int, int] | None) -> str:
    """Project-setting overrides for a QA copy of a packaged build: the engine creates its window windowed,
    non-activating (display/window/size/no_focus) and - with a rect - borderless, so the launch itself never
    takes focus or flashes fullscreen on the primary monitor. Position/size come from --position/--resolution."""
    lines = ["; Written by tools/qa/session.py (second-monitor QA mode) next to a linked copy of the game exe.",
             "; It only affects that copy. Never ship this file.", "[display]", "",
             "window/size/mode=0", "window/size/no_focus=true"]
    if rect is not None:
        lines.append("window/size/borderless=true")
    return "\n".join(lines) + "\n"


def prepare_qa_exe(exe: str | Path, dest_dir: str | Path, rect: tuple[int, int, int, int] | None) -> str:
    """Hard-links (same volume, no copy) or else copies a packaged build (and its .pck, if separate) into
    dest_dir and writes override.cfg next to it. Godot reads override.cfg from the executable's folder, so only
    this copy is affected; the original build folder is never touched. Returns the exe to launch."""
    src = Path(exe).resolve()
    dest = Path(dest_dir).resolve()
    dest.mkdir(parents=True, exist_ok=True)

    def place(s: Path, d: Path) -> Path:
        if d.exists():
            try:
                if os.path.samefile(s, d):
                    return d            # already this build
                d.unlink()              # an older build
            except OSError:
                # still in use (an earlier session's process): use a fresh name
                d = d.with_name(f"{d.stem}_{int(time.time())}{d.suffix}")
        try:
            os.link(s, d)
        except OSError:
            shutil.copy2(s, d)
        return d

    exe_copy = place(src, dest / src.name)
    pck = src.with_suffix(".pck")       # only for builds whose pack is not embedded in the exe
    if pck.exists():
        place(pck, exe_copy.with_suffix(".pck"))
    (dest / "override.cfg").write_text(override_cfg(rect), encoding="utf-8")
    return str(exe_copy)


def add_transport_args(ap) -> None:
    """--virtual-input / --second-monitor / --qa-window / --mute / --no-exe-copy for the scenario scripts."""
    g = ap.add_argument_group("second-monitor QA mode (virtual input; the owner keeps the PC)")
    g.add_argument("--virtual-input", action="store_true",
                   help="drive the game through its localhost virtual-input server (--qa-input-port) instead of SendInput; "
                        "the window never takes focus or captures the cursor; isolated settings + saves under --out")
    g.add_argument("--second-monitor", action="store_true",
                   help=f"--virtual-input with a borderless window on the second monitor (--qa-window, default {SECOND_MONITOR_RECT})")
    g.add_argument("--qa-window", default="", help="x,y,w,h desktop rect for the game window (implies --virtual-input)")
    g.add_argument("--mute", action="store_true", help="start the game with --qa-mute (silent session, settings untouched)")
    g.add_argument("--no-exe-copy", action="store_true",
                   help="launch the exe itself instead of a linked copy with a no-focus override.cfg (may flash focus once)")


def transport_kwargs(args) -> dict:
    rect = args.qa_window or (SECOND_MONITOR_RECT if args.second_monitor else "")
    return {"virtual_input": bool(args.virtual_input or args.second_monitor or rect), "qa_window": rect or None,
            "mute": bool(args.mute), "exe_copy": not args.no_exe_copy}


class Session:
    def __init__(self, exe: str, out_dir: str | Path, save_dir: str | Path, name: str,
                 resolution: str = "1600x900", extra: list[str] | None = None, cwd: str | None = None,
                 pre_args: list[str] | None = None, virtual_input: bool = False, qa_window: str | None = None,
                 mute: bool = False, exe_copy: bool = True):
        self.exe = exe
        self.out = Path(out_dir).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        self.save_dir = Path(save_dir).resolve()
        self.name = name
        self.resolution = resolution
        self.extra = extra or []
        self.pre_args = pre_args or []
        self.cwd = cwd
        self.virtual_input = virtual_input or bool(qa_window)
        self.qa_window = qa_window
        self.mute = mute
        self.exe_copy = exe_copy
        self.settings_file = self.out / "qa_settings.cfg"
        self.proc: subprocess.Popen | None = None
        self.tele_path = self.out / f"{name}_telemetry.jsonl"
        self.results_path = self.out / "results.jsonl"
        self.bot: Bot | None = None
        self.shot_n = 0

    def start(self, wait_for=None, timeout: float = 60.0):
        if self.tele_path.exists():
            self.tele_path.unlink()
        if self.virtual_input:
            self._start_virtual()
        else:
            args = self.pre_args + ["--windowed", "--resolution", self.resolution, "--position", "80,60", "--",
                    f"--qa-telemetry={self.tele_path.as_posix()}", "--qa-interval=0.1",
                    f"--save-dir={self.save_dir.as_posix()}", "--no-focus-pause"] + (["--qa-mute"] if self.mute else []) + self.extra
            self.proc = subprocess.Popen([self.exe] + args, cwd=self.cwd)
            win = GameWindow(self.proc.pid)
            tele = Telemetry(self.tele_path)
            self.bot = Bot(win, tele, self.out / f"{self.name}_bot.log")
            self.bot.log(f"launched {self.exe} pid={self.proc.pid} args={args}")
        if wait_for is not None:
            ok = self.bot.wait_state(wait_for, timeout)
            if not ok:
                self.bot.log("start: wait condition not met")
        return self.bot

    def _start_virtual(self):
        """Second-monitor launch: no GameWindow lookup, no focus, no SendInput, no desktop screenshots."""
        port = free_port()
        rect = parse_rect(self.qa_window) if self.qa_window else None
        engine = ["--windowed"]
        user = [f"--qa-telemetry={self.tele_path.as_posix()}", "--qa-interval=0.1",
                f"--save-dir={self.save_dir.as_posix()}", f"--settings-file={self.settings_file.as_posix()}",
                f"--qa-input-port={port}", "--qa-no-focus", "--no-focus-pause"]
        if rect is not None:
            x, y, w, h = rect
            # The engine creates its first window on that rect (so nothing appears on the owner's monitor);
            # Settings.apply_video() then keeps it borderless there (--qa-window).
            engine += ["--position", f"{x},{y}", "--resolution", f"{w}x{h}"]
            user.append(f"--qa-window={x},{y},{w},{h}")
        else:
            engine += ["--resolution", self.resolution, "--position", "80,60"]
        if self.mute:
            user.append("--qa-mute")
        exe = self.exe
        if self.exe_copy and not self.pre_args:
            exe = prepare_qa_exe(self.exe, self.out / "qa_exe", rect)
        args = self.pre_args + engine + ["--"] + user + self.extra
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = SW_SHOWNOACTIVATE      # the first ShowWindow of the process must not activate it
        self.proc = subprocess.Popen([exe] + args, cwd=self.cwd, startupinfo=si)
        tele = Telemetry(self.tele_path)
        log_path = self.out / f"{self.name}_bot.log"
        try:
            vin = VirtualInput(port, proc=self.proc, tele=tele)
        except Exception as e:
            if self.proc.poll() is None:
                self.proc.kill()
            raise RuntimeError(f"{e} - is {self.exe} older than game/src/qa/qa_input.gd? Rebuild it "
                               "(tools/build_release.ps1) or run the sources with --dev --exe <editor binary>.") from e
        self.bot = Bot(vin, tele, log_path)
        self.bot.log(f"launched (virtual input, port {port}) {exe} pid={self.proc.pid} args={args}")

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def shot(self, label: str) -> str:
        self.shot_n += 1
        p = self.out / f"{self.name}_{self.shot_n:03d}_{label}.png"
        try:
            self.bot.win.screenshot(p)
        except Exception as e:  # noqa: BLE001
            self.bot.log(f"screenshot failed: {e}")
        return str(p)

    def focus_report(self) -> dict:
        """Evidence for the second-monitor mode: did the game window ever report focus / a captured cursor?"""
        frames = focused = captured = 0
        if self.tele_path.exists():
            with open(self.tele_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    frames += 1
                    if '"window_focused":true' in line:
                        focused += 1
                    if '"mouse_mode":2' in line:     # Input.MOUSE_MODE_CAPTURED
                        captured += 1
        return {"telemetry_frames": frames, "frames_focused": focused, "frames_mouse_captured": captured}

    def record(self, check: str, kind: str, steps: str, expected: str, observed: str, result: str, evidence: list[str] | None = None):
        row = {"session": self.name, "time": time.strftime("%Y-%m-%d %H:%M:%S"), "check": check, "kind": kind,
               "exe": self.exe, "env": f"{platform.platform()}", "steps": steps, "expected": expected,
               "observed": observed, "result": result, "evidence": evidence or [],
               "input": "virtual (qa_input, second monitor)" if self.virtual_input else "SendInput"}
        with open(self.results_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
        if self.bot:
            self.bot.log(f"RESULT {result}: {check} - {observed}")

    def stop(self, graceful: bool = True):
        if not self.proc:
            return
        if self.bot:
            try:
                self.bot.release_all()
                self.bot.win.close()
            except Exception as e:  # noqa: BLE001  (the game may already be gone)
                self.bot.log(f"release on stop: {e}")
            if self.virtual_input:
                self.bot.log(f"focus report: {self.focus_report()}")
        if graceful and self.alive():
            try:
                self.proc.terminate()
                self.proc.wait(10)
            except Exception:  # noqa: BLE001
                pass
        if self.alive():
            self.proc.kill()
        self.proc = None
