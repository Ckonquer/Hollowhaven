"""Keeps a QA game window from ever taking the owner's keyboard focus (Windows).

Measured 2026-09-28 (qa/tmp/perf notes): the PACKAGED build's first window becomes the OS foreground window
~0.6 s after launch even with override.cfg display/window/size/no_focus (a new process gets a startup activation
right). Two layers of protection, used by session.py (second-monitor / virtual-input launches) and perf_profile.py:

1. ForegroundLock: a FRESH helper process calls LockSetForegroundWindow(LSFW_LOCK) right before the game starts and
   holds it until the game has been stopped (only a process that still has foreground rights may lock; a new
   process has them for its first ~20-45 s; the lock ends when the locking process exits). The owner's own clicks /
   Alt+Tab still switch windows as usual (Windows lifts the lock on user action).
2. FocusWatchdog: a background thread that checks every 0.2 s whether the game process owns the foreground
   window; if it does, it immediately hands the foreground back to the owner's last window and counts the event
   (so any failure of layer 1 lasts a fraction of a second and is reported, never 28 minutes).
3. Primary-monitor guard (same thread): a QA window must never cover the owner's PRIMARY monitor either, focused or
   not. Measured 2026-09-28 afternoon: borderless windows exactly the second monitor's size (1920x1080), asked for
   at the second monitor's origin, sat at 0,0 on the primary monitor for 30+ minutes (telemetry window_pos [0,0])
   while smaller windows with the same arguments stayed put - the focus checks could not see it. Now any visible
   game window overlapping the primary monitor is moved to its target rect at once and, if it is still there after
   `grace` seconds, the game is killed (reported in stop()). second_monitor_rect() gives launchers a rect a little
   INSIDE the first non-primary monitor, read from the live monitor layout, and assert_on_second_monitor() refuses
   a rect that is not fully on a non-primary monitor before anything starts.
"""
from __future__ import annotations

import ctypes
import os
import signal
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


MONITORINFOF_PRIMARY = 1
SWP_NOZORDER, SWP_NOACTIVATE, SWP_NOOWNERZORDER = 0x0004, 0x0010, 0x0200
MIN_OVERLAP_PX = 32 * 32          # ignore stray 1-px helper windows


class _MONITORINFO(ctypes.Structure):
    _fields_ = [("cbSize", wt.DWORD), ("rcMonitor", wt.RECT), ("rcWork", wt.RECT), ("dwFlags", wt.DWORD)]


def monitors() -> list[dict]:
    """[{"rect": (left, top, right, bottom), "primary": bool}] in EnumDisplayMonitors order."""
    out: list[dict] = []
    proto = ctypes.WINFUNCTYPE(ctypes.c_int, wt.HMONITOR, wt.HDC, ctypes.POINTER(wt.RECT), wt.LPARAM)

    def cb(hmon, _hdc, _rc, _lp):
        mi = _MONITORINFO()
        mi.cbSize = ctypes.sizeof(mi)
        if user32.GetMonitorInfoW(hmon, ctypes.byref(mi)):
            r = mi.rcMonitor
            out.append({"rect": (r.left, r.top, r.right, r.bottom), "primary": bool(mi.dwFlags & MONITORINFOF_PRIMARY)})
        return 1

    user32.EnumDisplayMonitors(None, None, proto(cb), 0)
    return out


def primary_rect() -> tuple[int, int, int, int]:
    for m in monitors():
        if m["primary"]:
            return m["rect"]
    return (0, 0, int(user32.GetSystemMetrics(0)), int(user32.GetSystemMetrics(1)))


def second_monitor_rect(inset: int = 8) -> tuple[int, int, int, int] | None:
    """x, y, w, h of the first non-primary monitor, `inset` px inside each edge (never exactly the monitor's size,
    see the module doc), or None when there is only one monitor."""
    for m in monitors():
        if not m["primary"]:
            left, top, right, bottom = m["rect"]
            return (left + inset, top + inset, right - left - 2 * inset, bottom - top - 2 * inset)
    return None


def overlap_area(a: tuple, b: tuple) -> int:
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    return w * h if w > 0 and h > 0 else 0


def assert_on_second_monitor(rect: tuple[int, int, int, int]) -> None:
    """Raises unless the x, y, w, h rect lies fully on one non-primary monitor (checked before any launch)."""
    x, y, w, h = rect
    r = (x, y, x + w, y + h)
    for m in monitors():
        ml, mt, mr, mb = m["rect"]
        if not m["primary"] and ml <= r[0] and mt <= r[1] and r[2] <= mr and r[3] <= mb:
            return
    raise RuntimeError(f"refusing to open a QA window at {rect}: not fully on a non-primary monitor "
                       f"(monitors: {monitors()}); the owner's primary monitor must stay free")


def process_windows(pid: int) -> list[tuple[int, tuple[int, int, int, int]]]:
    """Visible top-level windows of `pid` and their screen rects."""
    found: list[tuple[int, tuple[int, int, int, int]]] = []
    proto = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)

    def cb(hwnd, _lp):
        if hwnd and user32.IsWindowVisible(hwnd) and window_pid(hwnd) == pid:
            rc = wt.RECT()
            if user32.GetWindowRect(hwnd, ctypes.byref(rc)):
                found.append((int(hwnd), (rc.left, rc.top, rc.right, rc.bottom)))
        return True

    user32.EnumWindows(proto(cb), 0)
    return found


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
    """Background thread: if the game process ever owns the foreground window, give it back at once; if one of its
    windows ever overlaps the primary monitor, move it to `target_rect` (x, y, w, h) and kill the game when it is
    still there `grace` seconds later (guard_primary; see the module doc)."""

    def __init__(self, game_pid_fn, interval: float = 0.2, target_rect: tuple[int, int, int, int] | None = None,
                 guard_primary: bool = True, grace: float = 0.4):
        self._pid_fn = game_pid_fn
        self.interval = interval
        self.owner_hwnd = foreground_window()        # the owner's window at launch
        self.steals = 0
        self.returned = 0
        self.checks = 0
        self.target_rect = tuple(target_rect) if target_rect else None
        self.forbidden = primary_rect() if guard_primary else None
        self.grace = grace
        self.on_primary_checks = 0
        self.window_seen_checks = 0                  # > 0 proves the guard could see the game's window at all
        self.moved = 0
        self.killed = False
        self.primary_events: list[dict] = []
        self._first_on_primary: float | None = None
        self._t0 = time.monotonic()
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
                if pid and self.forbidden is not None and not self.killed:
                    self._guard_primary(pid)
            except Exception:  # noqa: BLE001
                pass
            self._stop.wait(self.interval)

    def _guard_primary(self, pid: int):
        wins = process_windows(pid)
        if wins:
            self.window_seen_checks += 1
        bad = [(h, rc) for h, rc in wins if overlap_area(rc, self.forbidden) > MIN_OVERLAP_PX]
        if not bad:
            self._first_on_primary = None
            return
        now = time.monotonic()
        self.on_primary_checks += 1
        t = round(now - self._t0, 2)
        if self._first_on_primary is None:
            self._first_on_primary = now
            moved = 0
            if self.target_rect is not None:
                x, y, w, h = self.target_rect
                for hwnd, _rc in bad:
                    if user32.SetWindowPos(hwnd, None, x, y, w, h, SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER):
                        moved += 1
            self.moved += moved
            self.primary_events.append({"t": t, "action": "moved" if moved else "seen", "rects": [rc for _h, rc in bad]})
            return
        if now - self._first_on_primary >= self.grace:
            try:
                os.kill(pid, signal.SIGTERM)             # TerminateProcess on Windows
            except OSError:
                pass
            self.killed = True
            self.primary_events.append({"t": t, "action": "killed", "rects": [rc for _h, rc in bad]})

    def stop(self) -> dict:
        self._stop.set()
        self._thread.join(timeout=2.0)
        return {"checks": self.checks, "game_had_focus": self.steals, "handed_back": self.returned,
                "window_seen_checks": self.window_seen_checks, "on_primary_checks": self.on_primary_checks,
                "moved_off_primary": self.moved,
                "killed_on_primary": self.killed, "primary_events": self.primary_events[:20]}
