"""Test-session helpers: launch a Hollowhaven build with telemetry, record steps and evidence.

A Session owns one game process. Results are appended to <out>/results.jsonl (one row per check:
build, environment, steps, expected, observed, result, evidence) so QA_REPORT.md can quote them.
"""
from __future__ import annotations

import json
import os
import platform
import subprocess
import time
from pathlib import Path

from hhbot import Bot, GameWindow, Telemetry


class Session:
    def __init__(self, exe: str, out_dir: str | Path, save_dir: str | Path, name: str,
                 resolution: str = "1600x900", extra: list[str] | None = None, cwd: str | None = None,
                 pre_args: list[str] | None = None):
        self.exe = exe
        self.out = Path(out_dir).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        self.save_dir = Path(save_dir).resolve()
        self.name = name
        self.resolution = resolution
        self.extra = extra or []
        self.pre_args = pre_args or []
        self.cwd = cwd
        self.proc: subprocess.Popen | None = None
        self.tele_path = self.out / f"{name}_telemetry.jsonl"
        self.results_path = self.out / "results.jsonl"
        self.bot: Bot | None = None
        self.shot_n = 0

    def start(self, wait_for=None, timeout: float = 60.0):
        if self.tele_path.exists():
            self.tele_path.unlink()
        args = self.pre_args + ["--windowed", "--resolution", self.resolution, "--position", "80,60", "--",
                f"--qa-telemetry={self.tele_path.as_posix()}", "--qa-interval=0.1",
                f"--save-dir={self.save_dir.as_posix()}", "--no-focus-pause"] + self.extra
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

    def record(self, check: str, kind: str, steps: str, expected: str, observed: str, result: str, evidence: list[str] | None = None):
        row = {"session": self.name, "time": time.strftime("%Y-%m-%d %H:%M:%S"), "check": check, "kind": kind,
               "exe": self.exe, "env": f"{platform.platform()}", "steps": steps, "expected": expected,
               "observed": observed, "result": result, "evidence": evidence or []}
        with open(self.results_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
        if self.bot:
            self.bot.log(f"RESULT {result}: {check} - {observed}")

    def stop(self, graceful: bool = True):
        if not self.proc:
            return
        if self.bot:
            self.bot.release_all()
        if graceful and self.alive():
            try:
                self.proc.terminate()
                self.proc.wait(10)
            except Exception:  # noqa: BLE001
                pass
        if self.alive():
            self.proc.kill()
        self.proc = None
