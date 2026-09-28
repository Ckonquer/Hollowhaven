"""Segment S3 helpers: a HEADLESS virtual-input launcher and small play primitives (copied/adapted from
tools/qa/session.py and tools/qa/playthrough.py so the shared files stay untouched).

HeadlessGame starts the SOURCE build with the console editor binary:
    Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --qa-input-port=<port> --qa-no-focus
        --qa-telemetry=<file> --qa-interval=0.1 --save-dir=<run>/saves --settings-file=<run>/settings.cfg
        --no-focus-pause --max-seconds=<bound> [--seed=N]
No window is ever created (DisplayServer "headless"), no SendInput, no desktop screenshots: the bot drives the game
only through the localhost virtual-input server (src/qa/qa_input.gd) and reads the read-only QA telemetry.
Only the process started here is ever killed.
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from hhbot import Bot, Telemetry, VirtualInput, angle_diff  # noqa: E402

ROOT = HERE.parents[2]
CONSOLE_EXE = ROOT / ".tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"


class HeadlessGame:
    def __init__(self, run_dir: str | Path, port: int, name: str = "s3", max_seconds: int = 1800,
                 seed: int | None = None, extra: list[str] | None = None, exe: str | Path = CONSOLE_EXE):
        self.run = Path(run_dir).resolve()
        self.run.mkdir(parents=True, exist_ok=True)
        self.port = int(port)
        self.name = name
        self.max_seconds = int(max_seconds)
        self.seed = seed
        self.extra = extra or []
        self.exe = str(exe)
        self.tele_path = self.run / f"{name}_telemetry.jsonl"
        self.stdout_path = self.run / f"{name}_godot_stdout.log"
        self.proc: subprocess.Popen | None = None
        self.bot: Bot | None = None
        self._out = None

    def args(self) -> list[str]:
        user = [f"--qa-input-port={self.port}", "--qa-no-focus", f"--qa-telemetry={self.tele_path.as_posix()}",
                "--qa-interval=0.1", f"--save-dir={(self.run / 'saves').as_posix()}",
                f"--settings-file={(self.run / 'settings.cfg').as_posix()}", "--no-focus-pause",
                f"--max-seconds={self.max_seconds}"]
        if self.seed is not None:
            user.append(f"--seed={int(self.seed)}")
        return [self.exe, "--headless", "--path", str(ROOT / "game"), "--"] + user + self.extra

    def start(self) -> Bot:
        if self.tele_path.exists():
            self.tele_path.unlink()
        self._out = open(self.stdout_path, "w", encoding="utf-8", errors="replace")
        cmd = self.args()
        self.proc = subprocess.Popen(cmd, cwd=str(ROOT), stdout=self._out, stderr=subprocess.STDOUT,
                                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        tele = Telemetry(self.tele_path)
        vin = VirtualInput(self.port, proc=self.proc, tele=tele, connect_timeout=90.0)
        self.bot = Bot(vin, tele, self.run / f"{self.name}_bot.log")
        self.bot.log(f"launched HEADLESS pid={self.proc.pid} port={self.port}: {' '.join(cmd)}")
        return self.bot

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.bot is not None:
            try:
                self.bot.release_all()
                self.bot.win.close()
            except Exception as e:  # noqa: BLE001
                self.bot.log(f"release on stop: {e}")
        if self.proc is not None and self.proc.poll() is None:
            try:
                self.proc.terminate()
                self.proc.wait(10)
            except Exception:  # noqa: BLE001
                pass
            if self.proc.poll() is None:
                self.proc.kill()
        if self._out is not None:
            self._out.close()
            self._out = None


def xz(p):
    return (p[0], p[2]) if len(p) == 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def tail_log(path: Path, n: int = 40) -> list[str]:
    try:
        lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
        return lines[-n:]
    except OSError:
        return []


def grep_log(path: Path, words: tuple[str, ...] = ("ERROR", "SCRIPT ERROR", "WARNING")) -> list[str]:
    out = []
    try:
        for ln in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
            if any(w in ln for w in words):
                out.append(ln.strip())
    except OSError:
        pass
    return out


__all__ = ["HeadlessGame", "Bot", "Telemetry", "VirtualInput", "angle_diff", "xz", "dist2", "tail_log", "grep_log", "ROOT",
           "json"]
