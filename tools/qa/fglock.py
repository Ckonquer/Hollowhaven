"""Keeps a QA game window from ever taking the owner's keyboard focus (Windows).

Measured 2026-09-28 (qa/tmp/perf notes): the PACKAGED build's first window becomes the OS foreground window
~0.6 s after launch even with override.cfg display/window/size/no_focus (a new process gets a startup activation
right). Two layers of protection, used by session.py (second-monitor / virtual-input launches) and perf_profile.py:

1. ForegroundLock: a FRESH helper process calls LockSetForegroundWindow(LSFW_LOCK) right before the game starts and
   holds it until the game has been stopped (only a process that still has foreground rights may lock; a new
   process has them for its first ~20-45 s; the lock ends when the locking process exits). The owner's own clicks /
   Alt+Tab still switch windows as usual (Windows lifts the lock on user action).
2. FocusWatchdog: a background thread that checks every 0.25 s whether the game process owns the foreground
   window; if it does, it immediately hands the foreground back to the owner's last window and counts the event
   (so any failure of layer 1 lasts a fraction of a second and is reported, never 28 minutes).
"""
from __future__ import annotations

import ctypes
import subprocess
import sys
import threading
import time
from ctypes import wintypes as wt

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

_HOLD_LOCK = ("import ctypes,sys;u=ctypes.WinDLL('user32',use_last_error=True);"
              "print(int(u.LockSetForegroundWindow(1)),ctypes.get_last_error(),flush=True);sys.stdin.read();"
              "print(int(u.LockSetForegroundWindow(2)),ctypes.get_last_error(),flush=True)")


def foreground_window() -> int:
    return int(user32.GetForegroundWindow() or 0)


def window_pid(hwnd: int) -> int:
    if not hwnd:
        return 0
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return int(pid.value)


def foreground_pid() -> int:
    return window_pid(foreground_window())


def give_back_foreground(hwnd: int) -> bool:
    """Hand the foreground back to `hwnd` (the owner's previous window)."""
    if not hwnd or not user32.IsWindow(hwnd):
        return False
    fg = user32.GetForegroundWindow()
    me = kernel32.GetCurrentThreadId()
    fg_thread = user32.GetWindowThreadProcessId(fg, None)
    user32.AttachThreadInput(me, fg_thread, True)
    ok = bool(user32.SetForegroundWindow(hwnd))
    user32.AttachThreadInput(me, fg_thread, False)
    return ok


class ForegroundLock:
    """Context manager: a fresh helper process holds LockSetForegroundWindow for the life of one game process."""

    def __init__(self):
        self.proc: subprocess.Popen | None = None
        self.locked = False
        self.unlocked: bool | None = None

    def __enter__(self):
        self.proc = subprocess.Popen([sys.executable, "-c", _HOLD_LOCK], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     text=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.locked = self.proc.stdout.readline().strip().startswith("1")
        return self

    def release(self):
        if self.proc is None:
            return
        try:
            out, _ = self.proc.communicate("", timeout=15)
            self.unlocked = out.strip().startswith("1")
        except Exception:  # noqa: BLE001
            self.proc.kill()
        self.proc = None

    def __exit__(self, *exc):
        self.release()


class FocusWatchdog:
    """Background thread: if the game process ever owns the foreground window, give it back at once."""

    def __init__(self, game_pid_fn, interval: float = 0.25):
        self._pid_fn = game_pid_fn
        self.interval = interval
        self.owner_hwnd = foreground_window()        # the owner's window at launch
        self.steals = 0
        self.returned = 0
        self.checks = 0
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()
        return self

    def _run(self):
        while not self._stop.is_set():
            try:
                pid = int(self._pid_fn() or 0)
                hwnd = foreground_window()
                fg_pid = window_pid(hwnd)
                self.checks += 1
                if pid and fg_pid == pid:
                    self.steals += 1
                    if give_back_foreground(self.owner_hwnd):
                        self.returned += 1
                elif hwnd and fg_pid and fg_pid != pid:
                    self.owner_hwnd = hwnd                  # follow the owner's own window changes
            except Exception:  # noqa: BLE001
                pass
            self._stop.wait(self.interval)

    def stop(self) -> dict:
        self._stop.set()
        self._thread.join(timeout=2.0)
        return {"checks": self.checks, "game_had_focus": self.steals, "handed_back": self.returned}
