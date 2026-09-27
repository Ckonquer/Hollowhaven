"""hhbot - external automated player for Hollowhaven QA.

Drives the REAL game window with REAL OS-level input (Win32 SendInput keyboard + mouse) and observes
the game through the read-only QA telemetry stream (--qa-telemetry JSON lines) plus window screenshots.
It never calls game code, grants items, teleports or sets flags: everything happens through inputs.

Library layer only (window control, input, telemetry, navigation primitives). Scenarios live in
tools/qa/playthrough.py.
"""
from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import json
import math
import os
import subprocess
import time
from pathlib import Path

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

INPUT_MOUSE, INPUT_KEYBOARD = 0, 1
KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, KEYEVENTF_SCANCODE = 0x1, 0x2, 0x8
MOUSEEVENTF_MOVE, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP = 0x1, 0x2, 0x4
MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP, MOUSEEVENTF_WHEEL = 0x8, 0x10, 0x800

ULONG_PTR = ctypes.c_size_t


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wt.LONG), ("dy", wt.LONG), ("mouseData", wt.DWORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ULONG_PTR)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD), ("time", wt.DWORD),
                ("dwExtraInfo", ULONG_PTR)]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [("uMsg", wt.DWORD), ("wParamL", wt.WORD), ("wParamH", wt.WORD)]


class _U(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("hi", HARDWAREINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wt.DWORD), ("u", _U)]


VK = {**{chr(c): c for c in range(0x41, 0x5B)}, **{str(d): 0x30 + d for d in range(10)},
      "SPACE": 0x20, "ENTER": 0x0D, "ESC": 0x1B, "TAB": 0x09, "SHIFT": 0xA0, "CTRL": 0xA2, "ALT": 0xA4,
      "BACKSPACE": 0x08, "LEFT": 0x25, "UP": 0x26, "RIGHT": 0x27, "DOWN": 0x28,
      "F1": 0x70, "F2": 0x71, "F3": 0x72, "F5": 0x74, "F9": 0x78, "F10": 0x79, "F11": 0x7A, "F12": 0x7B}
EXTENDED = {0x25, 0x26, 0x27, 0x28}


def _send(inp: INPUT):
    n = user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
    if n != 1:
        raise OSError(ctypes.get_last_error(), "SendInput failed")


def key_event(name: str, up: bool):
    vk = VK[name.upper()]
    scan = user32.MapVirtualKeyW(vk, 0)
    flags = KEYEVENTF_SCANCODE | (KEYEVENTF_KEYUP if up else 0) | (KEYEVENTF_EXTENDEDKEY if vk in EXTENDED else 0)
    inp = INPUT(type=INPUT_KEYBOARD)
    inp.u.ki = KEYBDINPUT(wVk=vk, wScan=scan, dwFlags=flags, time=0, dwExtraInfo=0)
    _send(inp)


def mouse_move(dx: int, dy: int):
    inp = INPUT(type=INPUT_MOUSE)
    inp.u.mi = MOUSEINPUT(dx=int(dx), dy=int(dy), mouseData=0, dwFlags=MOUSEEVENTF_MOVE, time=0, dwExtraInfo=0)
    _send(inp)


def mouse_button(button: str, up: bool):
    if button == "left":
        f = MOUSEEVENTF_LEFTUP if up else MOUSEEVENTF_LEFTDOWN
    else:
        f = MOUSEEVENTF_RIGHTUP if up else MOUSEEVENTF_RIGHTDOWN
    inp = INPUT(type=INPUT_MOUSE)
    inp.u.mi = MOUSEINPUT(dx=0, dy=0, mouseData=0, dwFlags=f, time=0, dwExtraInfo=0)
    _send(inp)


def mouse_wheel(delta: int):
    inp = INPUT(type=INPUT_MOUSE)
    inp.u.mi = MOUSEINPUT(dx=0, dy=0, mouseData=ctypes.c_ulong(delta & 0xFFFFFFFF).value, dwFlags=MOUSEEVENTF_WHEEL, time=0, dwExtraInfo=0)
    _send(inp)


def _window_for_pid(pid: int) -> int:
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(hwnd, _):
        p = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True
    user32.EnumWindows(cb, 0)
    return found[0] if found else 0


class GameWindow:
    def __init__(self, pid: int):
        self.pid = pid
        self.hwnd = 0
        for _ in range(100):
            self.hwnd = _window_for_pid(pid)
            if self.hwnd:
                break
            time.sleep(0.2)
        if not self.hwnd:
            raise RuntimeError(f"no window for pid {pid}")

    def focus(self):
        fg = user32.GetForegroundWindow()
        if fg == self.hwnd:
            return True
        fg_thread = user32.GetWindowThreadProcessId(fg, None)
        me = kernel32.GetCurrentThreadId()
        # ALT tap lets SetForegroundWindow succeed from a background process
        user32.keybd_event(0x12, 0, 0, 0)
        user32.keybd_event(0x12, 0, 2, 0)
        user32.AttachThreadInput(me, fg_thread, True)
        user32.ShowWindow(self.hwnd, 9)
        user32.BringWindowToTop(self.hwnd)
        user32.SetForegroundWindow(self.hwnd)
        user32.AttachThreadInput(me, fg_thread, False)
        time.sleep(0.15)
        return user32.GetForegroundWindow() == self.hwnd

    def is_foreground(self) -> bool:
        return user32.GetForegroundWindow() == self.hwnd

    def client_rect(self):
        r = wt.RECT()
        user32.GetClientRect(self.hwnd, ctypes.byref(r))
        pt = wt.POINT(0, 0)
        user32.ClientToScreen(self.hwnd, ctypes.byref(pt))
        return pt.x, pt.y, r.right, r.bottom

    def click(self, x: int, y: int, button: str = "left"):
        """Click at CLIENT coordinates (window pixels)."""
        self.focus()
        cx, cy, _, _ = self.client_rect()
        user32.SetCursorPos(int(cx + x), int(cy + y))
        time.sleep(0.06)
        mouse_button(button, False)
        time.sleep(0.05)
        mouse_button(button, True)

    def screenshot(self, path: str | Path):
        from PIL import ImageGrab
        x, y, w, h = self.client_rect()
        img = ImageGrab.grab(bbox=(x, y, x + w, y + h), all_screens=True)
        img.save(str(path))
        return str(path)


class Telemetry:
    """Tails the --qa-telemetry JSON-lines file and keeps the latest snapshot."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._pos = 0
        self.last: dict = {}
        self._buf = ""

    def poll(self) -> dict:
        if not self.path.exists():
            return self.last
        with open(self.path, "r", encoding="utf-8") as f:
            f.seek(self._pos)
            chunk = f.read()
            self._pos = f.tell()
        self._buf += chunk
        lines = self._buf.split("\n")
        self._buf = lines[-1]
        for ln in lines[:-1]:
            ln = ln.strip()
            if ln:
                try:
                    self.last = json.loads(ln)
                except json.JSONDecodeError:
                    pass
        return self.last


def angle_diff(a: float, b: float) -> float:
    """Signed smallest difference a-b in degrees."""
    d = (a - b + 180.0) % 360.0 - 180.0
    return d


class Bot:
    """Primitive actions via real input. yaw convention: 0 = looking toward -Z, +90 = toward -X
    (matches qa_telemetry cam_yaw = atan2(-fwd.x, -fwd.z))."""

    def __init__(self, win: GameWindow, tele: Telemetry, log_path: str | Path | None = None):
        self.win = win
        self.tele = tele
        self.px_per_deg = 8.0         # calibrated by calibrate_look()
        self.invert = 1.0
        self.held: set[str] = set()
        self.log_file = open(log_path, "a", encoding="utf-8") if log_path else None

    # --- logging -----------------------------------------------------------------------
    def log(self, msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line, flush=True)
        if self.log_file:
            self.log_file.write(line + "\n")
            self.log_file.flush()

    # --- observation ---------------------------------------------------------------------
    def state(self) -> dict:
        return self.tele.poll()

    def wait_state(self, pred, timeout: float = 10.0, interval: float = 0.05) -> dict | None:
        t0 = time.time()
        while time.time() - t0 < timeout:
            s = self.state()
            try:
                if s and pred(s):
                    return s
            except (KeyError, TypeError, IndexError):
                pass
            time.sleep(interval)
        return None

    def player(self) -> dict:
        return self.state().get("player", {})

    def pos(self):
        p = self.player().get("pos")
        return p if p else [0, 0, 0]

    # --- keyboard ------------------------------------------------------------------------
    def down(self, key: str):
        if key in ("LMB", "RMB"):
            mouse_button("left" if key == "LMB" else "right", False)
        else:
            key_event(key, False)
        self.held.add(key)

    def up(self, key: str):
        if key in ("LMB", "RMB"):
            mouse_button("left" if key == "LMB" else "right", True)
        else:
            key_event(key, True)
        self.held.discard(key)

    def release_all(self):
        for k in list(self.held):
            self.up(k)

    def tap(self, key: str, hold: float = 0.07):
        self.win.focus()
        self.down(key)
        time.sleep(hold)
        self.up(key)

    def hold(self, key: str, seconds: float):
        self.win.focus()
        self.down(key)
        time.sleep(seconds)
        self.up(key)

    # --- looking -----------------------------------------------------------------------------
    def cam_yaw(self) -> float | None:
        return self.player().get("cam_yaw")

    def calibrate_look(self) -> float:
        """Measures pixels of mouse motion per degree of camera yaw."""
        self.win.focus()
        y0 = self.cam_yaw()
        time.sleep(0.2)
        for _ in range(4):
            mouse_move(50, 0)
            time.sleep(0.03)
        time.sleep(0.35)
        y1 = self.cam_yaw()
        if y0 is None or y1 is None:
            return self.px_per_deg
        d = angle_diff(y1, y0)
        if abs(d) > 0.5:
            self.px_per_deg = 200.0 / abs(d)
            self.invert = -1.0 if d > 0 else 1.0   # moving right should DEcrease yaw (turn right)
        self.log(f"calibrated look: {self.px_per_deg:.2f} px/deg (dyaw={d:.1f}) invert={self.invert}")
        return self.px_per_deg

    def turn_to_yaw(self, target: float, tol: float = 4.0, timeout: float = 3.0) -> bool:
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
            mouse_move(int(-step * self.px_per_deg * self.invert * 0.8), 0)
            time.sleep(0.06)
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
            mouse_move(0, int(-step * self.px_per_deg * 0.8))
            time.sleep(0.06)
        return False

    @staticmethod
    def yaw_to(src, dst) -> float:
        dx, dz = dst[0] - src[0], dst[2] - src[2]
        return math.degrees(math.atan2(-dx, -dz))

    def face_point(self, target, tol: float = 5.0) -> bool:
        return self.turn_to_yaw(self.yaw_to(self.pos(), target), tol)

    # --- movement ----------------------------------------------------------------------------
    def walk_to(self, target, tol: float = 1.2, timeout: float = 40.0, sprint: bool = False, avoid: bool = True) -> bool:
        """Walk to an XZ target with closed-loop steering; handles getting stuck by jumping/strafing."""
        self.win.focus()
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
                    if abs(d) > 2.0:
                        step = max(-25.0, min(25.0, d))
                        mouse_move(int(-step * self.px_per_deg * self.invert * 0.7), 0)
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

    def walk_path(self, points, tol: float = 1.5, sprint: bool = False) -> bool:
        for pt in points:
            if not self.walk_to(pt, tol=tol, sprint=sprint):
                return False
        return True

    # --- UI -------------------------------------------------------------------------------------
    def buttons(self):
        return self.state().get("buttons", [])

    def find_button(self, text: str, exact: bool = False):
        for b in self.buttons():
            t = b.get("text", "")
            if (t == text) if exact else (text.lower() in t.lower()):
                return b
        return None

    def click_button(self, text: str, exact: bool = False, timeout: float = 5.0) -> bool:
        s = self.wait_state(lambda st: any(((b["text"] == text) if exact else (text.lower() in b["text"].lower())) and not b.get("disabled") for b in st.get("buttons", [])), timeout)
        if not s:
            self.log(f"button not found: {text!r}; visible: {[b['text'] for b in self.buttons()][:30]}")
            return False
        b = next(b for b in s["buttons"] if ((b["text"] == text) if exact else (text.lower() in b["text"].lower())) and not b.get("disabled"))
        x, y, w, h = b["rect"]
        self.win.click(x + w // 2, y + h // 2)
        time.sleep(0.25)
        return True

    def messages(self):
        return self.state().get("messages", [])


def launch(exe: str, args: list[str], cwd: str | None = None) -> subprocess.Popen:
    return subprocess.Popen([exe] + args, cwd=cwd)
