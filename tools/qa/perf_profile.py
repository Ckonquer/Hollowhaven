"""Performance profile of a bounded representative route (MP section 20.5).

For every graphics preset x starting state this launches ONE game process with an isolated --settings-file (the
preset: quality, render scale, window size, vsync off / uncapped) and --save-dir (a start save placed there),
presses Continue, records the load, then runs a scripted sample - a slow 360-degree camera pan, a short walk
(W / A / S / D) and a few idle seconds - while the game's QA telemetry (game/src/qa/qa_telemetry.gd with
--qa-perf) logs every frame's time, its own cost, the GPU / CPU render times and the Performance monitors. A
separate run per preset rides the Lantern Road Reach -> Haven -> Reach N times and compares node / object /
resource / orphan counts, memory, audio players and enemy AI at every arrival (leak check).

Transports (tools/qa/session.py):
* default: the PACKAGED build (builds/Hollowhaven/Hollowhaven.exe, a hard-linked copy with a no-focus
  override.cfg) as a borderless window on the second monitor (DISPLAY2 at x=1920), virtual input only - the owner
  keeps monitor 1, the window never takes focus. Process memory (private bytes / working set) is read from
  Windows every 0.5 s because a release build reports no static memory.
* --headless: the SOURCE project in the console editor binary, no window (frame times are meaningless there,
  60 fps cap, dummy renderer): only validates that the harness runs, loads every state and logs.

Start states (saves are written into each run's own save dir; DIAGNOSTIC FIXTURES built from the REAL
Chapter-One-complete save game/tests/fixtures/saves/16_real_handoff_c1_complete.json, except "haven", which is that
save unmodified - see STATES and the fixture note written into each save's meta.qa_fixture).

Outputs (qa/tmp/perf/<run>/): results.json (everything), summary.csv (area x preset), loads.csv,
roundtrip.csv, frames/<preset>__<state>.csv (per-frame), summary.md, and per process <preset>/<state>/ (telemetry,
bot log, perf log, saves, settings).

Examples:
  python tools/qa/perf_profile.py --headless --quick --out qa/tmp/perf/headless_check
  python tools/qa/perf_profile.py --mute --out qa/tmp/perf/packaged_1
  python tools/qa/perf_profile.py --mute --wait-build-after 2026-09-28T10:05:39 --out qa/tmp/perf/packaged_1
  python tools/qa/perf_profile.py --mute --presets high1080 --states orchard,quarry --round-trips 0 --out ...
"""
from __future__ import annotations

import argparse
import copy
import csv
import ctypes
import ctypes.wintypes as wt
import datetime as dt
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import threading
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
for p in (str(HERE), str(HERE / "ch2")):
    if p not in sys.path:
        sys.path.insert(0, p)

from hhbot import Bot, angle_diff  # noqa: E402
from session import Session, headless_session, override_cfg, game_log_errors  # noqa: E402
import s4_common  # noqa: E402  (Play: walk / face / interact primitives used by the round trips)

REAL_SAVE = ROOT / "game" / "tests" / "fixtures" / "saves" / "16_real_handoff_c1_complete.json"
DEFAULT_EXE = ROOT / "builds" / "Hollowhaven" / "Hollowhaven.exe"
APPDATA_USER = Path(os.environ.get("APPDATA", "")) / "Hollowhaven"

# ------------------------------------------------------------------------------------------------ presets
# id -> quality (Settings "quality": 0 Low, 1 Medium, 2 High), render_scale, window w x h (on DISPLAY2 at x=1920).
PRESETS = {
    "high1080": {"label": "High @1920x1080", "quality": 2, "render_scale": 1.0, "w": 1920, "h": 1080},
    "low1080": {"label": "Low @1920x1080", "quality": 0, "render_scale": 1.0, "w": 1920, "h": 1080},
    "high720": {"label": "High @1280x720", "quality": 2, "render_scale": 1.0, "w": 1280, "h": 720},
    "med1080": {"label": "Medium @1920x1080", "quality": 1, "render_scale": 1.0, "w": 1920, "h": 1080},
    "lowrs1080": {"label": "Low + render scale 0.7 @1920x1080 (auto_quality 'low')", "quality": 0, "render_scale": 0.7,
                  "w": 1920, "h": 1080},
}
SECOND_MONITOR_X = 1920

# ------------------------------------------------------------------------------------------------ start states
S2_FLAGS = ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map"]
S4_FLAGS = S2_FLAGS + [
    "ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp",
    "ch2_orchard_irrigated", "ch2_orchard_mimics_cleared", "ch2_garden_lamp_lit", "ch2_arch_orchard",
    "hr_warden_defeated", "ch2_winch_repaired", "ch2_quarry_lamp_lit", "ch2_arch_quarry",
    "ch2_velour_defeated", "ch2_moment_empty_waltz", "ch2_manor_lamp_lit", "ch2_arch_manor",
    "ch2_read_preparations"]
WORKS_FLAGS = S4_FLAGS + [
    "ch2_lamps_linked", "ch2_service_gate_open", "ch2_refuge_reached", "ch2_refuge_shortcut",
    "ch2_line_water", "ch2_line_bell", "ch2_line_light", "hw_eyes_route_open",
    "hw_thread_nook_burned", "hw_thread_winch_exit_burned", "ch2_crossing_cleared", "ch2_false_home_revealed",
    "ch2_true_signal", "cp_lit_hw_crossing_gate", "cp_lit_hw_bell_throat"]
# Reach spawns (data/hallowmere_layout.gd SPAWNS): the saved y=400 is deliberately unplaceable, so Continue (an
# outdoor area resumes at the saved spot when it validates) falls back to the spawn point.
REACH_SPAWN_XZ = {"waygate_arrival": (0.0, 96.2), "commons_arch": (0.0, 73.4), "orchard_arch": (-63.88, 47.53),
                  "quarry_arch": (65.53, 35.06), "manor_arch": (11.45, -54.36), "conservatory": (0.0, 15.4)}

STATES = {
    "haven": {"area": "surface", "label": "The Haven (surface) - REAL C1-complete save 16, unmodified (day 1 18:58, house)",
              "real": True},
    "reach_arrival": {"area": "hallowmere_reach", "spawn": "waygate_arrival", "flags": S2_FLAGS, "hour": 10.0,
                      "label": "Hallowmere Reach arrival (waygate_arrival, 10:00) - fixture: S2 flags"},
    "commons_dusk": {"area": "hallowmere_reach", "spawn": "commons_arch", "flags": S2_FLAGS, "hour": 19.3,
                     "label": "Lanternwake Commons at dusk (commons_arch, 19:18) - fixture: S2 flags"},
    "orchard": {"area": "hallowmere_reach", "spawn": "orchard_arch", "flags": S4_FLAGS, "hour": 11.0,
                "label": "Pumpkintide Orchard (orchard_arch, 11:00) - fixture: S4 flags (3 lamps lit)"},
    "quarry": {"area": "hallowmere_reach", "spawn": "quarry_arch", "flags": S4_FLAGS, "hour": 14.0,
               "label": "Ashbell Quarry (quarry_arch, 14:00) - fixture: S4 flags (3 lamps lit)"},
    "ballroom": {"area": "moonveil_manor", "spawn": "manor_ballroom", "flags": S4_FLAGS, "hour": 21.0,
                 "label": "Moonveil Manor ballroom (manor_ballroom, Velour defeated) - fixture: S4 flags"},
    "works_hub": {"area": "hushed_works", "spawn": "refuge", "flags": WORKS_FLAGS, "hour": 12.0,
                  "label": "Hushed Works hub / Refuge (room 7) - fixture: three lines lit, Choir alive"},
    "choir_approach": {"area": "hushed_works", "spawn": "bell_throat", "flags": WORKS_FLAGS, "hour": 12.0,
                       "label": "Choir vault approach (bell_throat checkpoint) - fixture: three lines lit, Choir alive"},
    "annex": {"area": "tobin_annex", "spawn": "annex_entry", "flags": S2_FLAGS, "hour": 12.0,
              "label": "Tobin's annex (annex_entry, first visit) - fixture: S2 flags"},
}
ROUNDTRIP_STATE = {"area": "hallowmere_reach", "spawn": "commons_arch", "flags": S2_FLAGS, "hour": 12.0,
                   "label": "Round trip start: Commons arch (12:00) - fixture: S2 flags (Commons arch lit)"}


def build_fixture(state: dict) -> dict:
    d = json.loads(REAL_SAVE.read_text(encoding="utf-8"))
    if state.get("real"):
        d.setdefault("meta", {})["qa_fixture"] = "REAL save 16_real_handoff_c1_complete, unmodified (perf_profile.py)"
        return d
    st = d["state"]
    flags = st.setdefault("flags", {})
    for f in state.get("flags", []):
        flags[f] = True
    area, spawn = state["area"], state["spawn"]
    pl = st["player"]
    pl["area"] = area
    pl["spawn"] = spawn
    x, z = REACH_SPAWN_XZ.get(spawn, (0.0, 0.0))
    pl["pos"] = [x, 400.0, z]
    pl["yaw"] = 0.0
    pl["respawn_area"] = area
    pl["respawn_spawn"] = spawn
    pl["area_respawn"] = {area: spawn}
    pl["hp"] = 100.0
    if "hour" in state:
        st["total_minutes"] = 1440.0 + float(state["hour"]) * 60.0      # day 2
    d["meta"] = dict(d.get("meta", {}), area=area,
                     qa_fixture=f"PERF DIAGNOSTIC FIXTURE (tools/qa/perf_profile.py) from 16_real_handoff_c1_complete: "
                                f"{state['label']}; flags added {state.get('flags', [])}")
    return d


def write_settings(path: Path, preset: dict, vsync: bool) -> None:
    lines = ["[settings]", "", f"quality={int(preset['quality'])}", f"render_scale={float(preset['render_scale'])}",
             "fullscreen=false", f"vsync={'true' if vsync else 'false'}", "max_fps=0", "comfort_confirmed=true",
             "show_fps=false", "show_hints=true"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ------------------------------------------------------------------------------------------------ Windows probes
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)


class PMC_EX(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("PageFaultCount", wt.DWORD), ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t), ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t), ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t), ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t), ("PrivateUsage", ctypes.c_size_t)]


class MEMSTATUSEX(ctypes.Structure):
    _fields_ = [("dwLength", wt.DWORD), ("dwMemoryLoad", wt.DWORD), ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong), ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong), ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong), ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]


def proc_memory(pid: int) -> dict | None:
    h = kernel32.OpenProcess(0x1000 | 0x0010, False, int(pid))     # QUERY_LIMITED_INFORMATION | VM_READ
    if not h:
        return None
    try:
        c = PMC_EX()
        c.cb = ctypes.sizeof(PMC_EX)
        if not psapi.GetProcessMemoryInfo(h, ctypes.byref(c), c.cb):
            return None
        return {"private_mb": round(c.PrivateUsage / 1048576.0, 1), "ws_mb": round(c.WorkingSetSize / 1048576.0, 1),
                "peak_ws_mb": round(c.PeakWorkingSetSize / 1048576.0, 1)}
    finally:
        kernel32.CloseHandle(h)


user32 = ctypes.WinDLL("user32", use_last_error=True)


def foreground_pid() -> int:
    """Process id owning the OS foreground window (evidence that the game never took the owner's focus)."""
    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return 0
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return int(pid.value)


LSFW_LOCK, LSFW_UNLOCK = 1, 2
_HOLD_LOCK = ("import ctypes,sys;u=ctypes.WinDLL('user32',use_last_error=True);"
              "print(int(u.LockSetForegroundWindow(1)),ctypes.get_last_error(),flush=True);sys.stdin.read();"
              "print(int(u.LockSetForegroundWindow(2)),ctypes.get_last_error(),flush=True)")


class ForegroundLock:
    """Holds LockSetForegroundWindow(LSFW_LOCK) for the life of one game process, from a FRESH helper process.

    Measured on this PC (qa/tmp/perf notes, 2026-09-28): the packaged build's first window becomes the OS foreground
    window ~0.6 s after launch despite override.cfg display/window/size/no_focus (a new process gets a startup
    activation right). LockSetForegroundWindow blocks that, but only a process that itself still has foreground
    rights may call it - a new process has them for its first ~20-45 s, a long-running script loses them (this
    script's own calls failed with ERROR_ACCESS_DENIED after the first launch, and the game then took the focus in
    29 of 30 sessions of the first profile run) - and the lock ends when the locking process exits. So every launch
    starts a new helper that locks, stays alive until the game has been stopped, then unlocks and exits. While
    locked, the owner's own clicks / Alt+Tab still switch windows as usual (Windows lifts the lock on user action)."""

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


def give_back_foreground(hwnd: int) -> bool:
    """If the game took the foreground anyway, hand it back to the owner's previous window."""
    if not hwnd or not user32.IsWindow(hwnd):
        return False
    fg = user32.GetForegroundWindow()
    me = kernel32.GetCurrentThreadId()
    fg_thread = user32.GetWindowThreadProcessId(fg, None)
    user32.AttachThreadInput(me, fg_thread, True)
    ok = bool(user32.SetForegroundWindow(hwnd))
    user32.AttachThreadInput(me, fg_thread, False)
    return ok


def system_ram_gb() -> float:
    m = MEMSTATUSEX()
    m.dwLength = ctypes.sizeof(MEMSTATUSEX)
    kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return round(m.ullTotalPhys / 1024 ** 3, 1)


def system_times() -> tuple[int, int, int]:
    idle, kern, user = wt.FILETIME(), wt.FILETIME(), wt.FILETIME()
    kernel32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kern), ctypes.byref(user))
    f = lambda t: (t.dwHighDateTime << 32) | t.dwLowDateTime  # noqa: E731
    return f(idle), f(kern), f(user)


def cpu_busy_pct(a, b) -> float | None:
    di, dk, du = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    tot = dk + du
    return round(100.0 * (1.0 - di / tot), 1) if tot > 0 else None


def nvidia_smi() -> dict:
    try:
        r = subprocess.run(["nvidia-smi", "--query-gpu=name,driver_version,utilization.gpu,memory.used,memory.total,"
                            "clocks.gr,pstate", "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        v = [x.strip() for x in r.stdout.strip().splitlines()[0].split(",")]
        return {"name": v[0], "driver": v[1], "util_pct": v[2], "mem_used_mib": v[3], "mem_total_mib": v[4],
                "clock_mhz": v[5], "pstate": v[6]}
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)[:120]}


def cpu_name() -> str:
    try:
        import winreg
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0")
        return str(winreg.QueryValueEx(k, "ProcessorNameString")[0]).strip()
    except Exception:  # noqa: BLE001
        return platform.processor()


def copy_qa_exe(exe: Path, dest_dir: Path, rect) -> str:
    """Like session.prepare_qa_exe (same override.cfg: windowed, borderless, display/window/size/no_focus) but a
    real COPY instead of a hard link, so a running profile never holds the build folder's own file open while the
    lead rebuilds (build_release.ps1 deletes builds/Hollowhaven first). Returns the exe to launch."""
    import shutil
    dest_dir.mkdir(parents=True, exist_ok=True)
    dst = dest_dir / exe.name
    if dst.exists():
        dst.unlink()
    shutil.copy2(exe, dst)
    (dest_dir / "override.cfg").write_text(override_cfg(rect), encoding="utf-8")
    return str(dst)


def kill_tree(pid: int) -> None:
    """Kills pid and its children - only ever a pid this script started."""
    try:
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, timeout=20)
    except Exception:  # noqa: BLE001
        pass


class MemSampler(threading.Thread):
    """Samples the game process's private bytes / working set every `interval` s (release builds report no static
    memory through Performance)."""

    def __init__(self, pid: int | None, interval: float = 0.5):
        super().__init__(daemon=True)
        self.pid = pid
        self.interval = interval
        self.samples: list[tuple[float, dict]] = []
        self.fg_checks = 0      # OS foreground-window checks (GetForegroundWindow) ...
        self.fg_game = 0        # ... in which the foreground window belonged to the game (focus stolen)
        self.fg_restored = 0
        self.restore_hwnd = 0   # the owner's foreground window before the launch
        self._stop = threading.Event()

    def run(self):
        while not self._stop.is_set() and self.pid:
            m = proc_memory(self.pid)
            if m:
                self.samples.append((time.time(), m))
            fg = foreground_pid()
            self.fg_checks += 1
            if fg == self.pid:
                self.fg_game += 1
                if self.restore_hwnd:
                    self.fg_restored += int(give_back_foreground(self.restore_hwnd))
            self._stop.wait(self.interval)

    def stop(self):
        self._stop.set()

    def at(self) -> dict:
        m = proc_memory(self.pid) if self.pid else None
        return m or (self.samples[-1][1] if self.samples else {})

    def window(self, t0: float, t1: float) -> list[dict]:
        return [m for (t, m) in self.samples if t0 <= t <= t1]


# ------------------------------------------------------------------------------------------------ telemetry file
def boundary(path: Path) -> int:
    """Byte offset just after the last complete line currently in the telemetry file."""
    try:
        size = path.stat().st_size
    except OSError:
        return 0
    with open(path, "rb") as f:
        back = min(size, 1 << 20)
        f.seek(size - back)
        chunk = f.read(back)
    nl = chunk.rfind(b"\n")
    return size - back + nl + 1 if nl >= 0 else size - back


def read_lines(path: Path, start: int, end: int) -> list[dict]:
    out = []
    if end <= start:
        return out
    with open(path, "rb") as f:
        f.seek(start)
        data = f.read(end - start)
    for ln in data.split(b"\n"):
        ln = ln.strip()
        if not ln:
            continue
        try:
            out.append(json.loads(ln.decode("utf-8", "replace")))
        except ValueError:
            continue
    return out


# ------------------------------------------------------------------------------------------------ statistics
def pct(sorted_vals: list[float], q: float) -> float:
    if not sorted_vals:
        return float("nan")
    k = (len(sorted_vals) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (k - lo)


def frame_stats(frames: list[float], self_ms: list[float] | None = None, gpu: list[float] | None = None,
                cpu_r: list[float] | None = None) -> dict:
    n = len(frames)
    if n == 0:
        return {"frames": 0}
    total = sum(frames)
    s = sorted(frames)
    worst_first = s[::-1]
    k1 = max(1, int(round(n * 0.01)))
    k01 = max(1, int(round(n * 0.001)))
    med = pct(s, 0.5)
    r = {"frames": n, "seconds": round(total / 1000.0, 2), "avg_fps": round(n / (total / 1000.0), 1),
         "avg_ms": round(total / n, 3), "median_ms": round(med, 3),
         "low1_fps": round(1000.0 / statistics.fmean(worst_first[:k1]), 1),
         "low01_fps": round(1000.0 / statistics.fmean(worst_first[:k01]), 1),
         "p95_ms": round(pct(s, 0.95), 2), "p99_ms": round(pct(s, 0.99), 2), "p999_ms": round(pct(s, 0.999), 2),
         "worst_ms": round(s[-1], 2), "over_16_7": sum(1 for f in frames if f > 16.7),
         "over_33": sum(1 for f in frames if f > 33.3), "over_50": sum(1 for f in frames if f > 50.0),
         "over_100": sum(1 for f in frames if f > 100.0),
         "spikes_2x_median": sum(1 for f in frames if f > 2.0 * med and f > 8.0)}
    if self_ms and len(self_ms) == n:
        tele = sum(self_ms)
        r["tele_pct"] = round(100.0 * tele / total, 2)
        r["tele_max_ms"] = round(max(self_ms), 2)
        # spikes (> 2x median) of which the telemetry's own work explains at least half of the excess
        r["tele_spikes"] = sum(1 for f, t in zip(frames, self_ms) if f > 2.0 * med and f > 8.0 and t >= 0.5 * (f - med))
        adj = sorted(max(0.05, f - t) for f, t in zip(frames, self_ms))
        r["low1_fps_minus_tele"] = round(1000.0 / statistics.fmean(adj[::-1][:k1]), 1)
        r["avg_fps_minus_tele"] = round(n / (sum(adj) / 1000.0), 1)
    if gpu:
        g = [x for x in gpu if x > 0]
        if g:
            gs = sorted(g)
            r["gpu_avg_ms"] = round(statistics.fmean(g), 3)
            r["gpu_p99_ms"] = round(pct(gs, 0.99), 2)
            r["gpu_share"] = round(statistics.fmean(g) / (total / n), 2)
    if cpu_r:
        c = [x for x in cpu_r if x > 0]
        if c:
            r["cpu_render_avg_ms"] = round(statistics.fmean(c), 3)
    return r


def collect_frames(lines: list[dict]) -> dict:
    out = {"frames": [], "self": [], "gpu": [], "cpu": [], "tick": []}
    for ln in lines:
        pf = ln.get("perf") or {}
        fr = pf.get("frames") or []
        out["frames"] += fr
        sm = pf.get("self_ms") or []
        out["self"] += sm if len(sm) == len(fr) else [0.0] * len(fr)
        g = pf.get("gpu_ms") or []
        out["gpu"] += g if len(g) == len(fr) else [0.0] * len(fr)
        c = pf.get("cpu_render_ms") or []
        out["cpu"] += c if len(c) == len(fr) else [0.0] * len(fr)
        out["tick"] += [pf.get("tick_ms", 0)] * len(fr)
    return out


def monitors(lines: list[dict]) -> dict:
    """Averages / maxima of the per-line monitors over a phase."""
    keys = ["draw_calls", "objects_drawn", "primitives", "nodes", "objects", "resources", "orphans", "static_mb",
            "video_mb", "texture_mb", "buffer_mb", "process_ms", "physics_ms", "phys_active", "phys_pairs"]
    vals: dict[str, list[float]] = {k: [] for k in keys}
    enemies, audio = [], []
    for ln in lines:
        pf = ln.get("perf") or {}
        for k in keys:
            v = pf.get(k)
            if isinstance(v, (int, float)):
                vals[k].append(float(v))
        if pf.get("enemies"):
            enemies.append(pf["enemies"])
        if pf.get("audio"):
            audio.append(pf["audio"])
    r = {}
    for k, v in vals.items():
        if v:
            r[k + "_avg"] = round(statistics.fmean(v), 1)
            r[k + "_max"] = round(max(v), 1)
    if enemies:
        for k in ("total", "alive", "active", "active_far", "active_offscreen"):
            r["enemies_" + k + "_max"] = max(int(e.get(k, 0)) for e in enemies)
        r["enemies_active_max_dist"] = max(float(e.get("active_max_dist", 0)) for e in enemies)
    if audio:
        r["audio_players_max"] = max(int(a.get("players", 0)) for a in audio)
        r["audio_playing_max"] = max(int(a.get("playing", 0)) for a in audio)
    return r


# ------------------------------------------------------------------------------------------------ driving
class Runner:
    def __init__(self, a):
        self.a = a
        self.out = Path(a.out).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        (self.out / "frames").mkdir(exist_ok=True)
        self.results: dict = {"started": dt.datetime.now().isoformat(timespec="seconds"), "args": vars(a), "runs": [],
                              "roundtrips": [], "env": {}}
        self.log_f = open(self.out / "perf_profile.log", "a", encoding="utf-8")
        self.qa_exe: str | None = None
        s = 0.35 if a.quick else 1.0
        self.pan_s = a.pan_seconds * s
        self.walk_s = a.walk_seconds * s
        self.idle_s = max(1.0, a.idle_seconds * s)
        self.settle_s = a.settle_seconds

    def log(self, msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line, flush=True)
        self.log_f.write(line + "\n")
        self.log_f.flush()

    def save_results(self):
        (self.out / "results.json").write_text(json.dumps(self.results, indent=1, default=str), encoding="utf-8")

    # ---------------------------------------------------------------- process
    def launch(self, run_dir: Path, name: str, preset: dict, save: dict) -> Session:
        run_dir.mkdir(parents=True, exist_ok=True)
        save_dir = run_dir / "saves"
        save_dir.mkdir(parents=True, exist_ok=True)
        for f in save_dir.glob("*.json"):
            f.unlink()
        (save_dir / "slot1.json").write_text(json.dumps(save, indent=1), encoding="utf-8")
        write_settings(run_dir / "qa_settings.cfg", preset, self.a.vsync == "on")
        extra = ["--qa-perf", "--qa-interval=0.2", "--no-wardrobe-notice", f"--perf-log={(run_dir / 'perf_log.jsonl').as_posix()}"]
        self.prev_fg = user32.GetForegroundWindow()
        self.fg_lock = None
        self.fg_locked = False
        if not self.a.headless:
            self.fg_lock = ForegroundLock().__enter__()
            self.fg_locked = self.fg_lock.locked
            if not self.fg_locked:
                self.log("WARNING: the foreground lock helper could not lock - the game may take the OS focus")
        if self.a.headless:
            sess = headless_session(run_dir, name=name, save_dir=save_dir, extra=extra, max_seconds=self.a.watchdog)
            sess.mute = bool(self.a.mute)
        else:
            rect = f"{SECOND_MONITOR_X},0,{preset['w']},{preset['h']}"
            if self.qa_exe is None:
                self.qa_exe = copy_qa_exe(Path(self.a.exe), self.out / "qa_exe", tuple(int(v) for v in rect.split(",")))
            sess = Session(self.qa_exe, run_dir, save_dir, name, extra=extra, virtual_input=True, qa_window=rect,
                           mute=bool(self.a.mute), exe_copy=False, max_seconds=self.a.watchdog)
        sess.start()
        return sess

    def stop(self, sess: Session | None):
        if sess is None:
            return
        pid = sess.proc.pid if sess.proc else None
        try:
            sess.stop(graceful=False)
        except Exception as e:  # noqa: BLE001
            self.log(f"stop: {e}")
        if pid and self.a.headless:
            kill_tree(pid)      # the console wrapper's child
        if getattr(self, "fg_lock", None) is not None:
            self.fg_lock.release()
            self.fg_unlocked = self.fg_lock.unlocked
            self.fg_lock = None
        time.sleep(1.0)

    # ---------------------------------------------------------------- helpers on the bot
    @staticmethod
    def perf(bot: Bot) -> dict:
        return bot.state().get("perf") or {}

    def wait_title(self, bot: Bot, timeout: float = 150.0) -> bool:
        return bot.wait_state(lambda s: s.get("mode") == "title" and any(b.get("text") == "Continue" and not b.get("disabled")
                                                                         for b in s.get("buttons", [])), timeout) is not None

    def wait_arrival(self, bot: Bot, area: str, load_n_before: int, timeout: float = 180.0) -> dict | None:
        return bot.wait_state(lambda s: s.get("mode") == "playing" and s.get("area") == area
                              and int(((s.get("perf") or {}).get("load") or {}).get("n", 0)) > load_n_before, timeout)

    def wait_post_load(self, bot: Bot, timeout: float = 8.0) -> dict:
        s = bot.wait_state(lambda s: bool(((s.get("perf") or {}).get("load") or {}).get("post_done")), timeout)
        return ((s or bot.state()).get("perf") or {}).get("load") or {}

    def dismiss_ui(self, bot: Bot, tag: str) -> list:
        """Closes cards / panels that opened on arrival (logged): Resume on the pause menu, a close-type button,
        else Esc."""
        seen = []
        for _ in range(5):
            s = bot.state()
            ui = s.get("ui_stack") or []
            if not ui:
                return seen
            seen.append(list(ui))
            texts = [b.get("text", "") for b in s.get("buttons", [])]
            self.log(f"{tag}: UI open {ui}; buttons {texts[:12]}")
            if "pause" in ui and bot.click_button("Resume", exact=True, timeout=2):
                time.sleep(0.5)
                continue
            for t in ("Close", "OK", "Got it", "Done", "Not now", "Continue", "Later"):
                if t in texts and bot.click_button(t, exact=True, timeout=1):
                    break
            else:
                bot.tap("ESC")
            time.sleep(0.6)
        return seen

    def pan(self, bot: Bot, seconds: float) -> dict:
        """Slow 360-degree camera pan at a constant rate (open loop on the calibrated px/deg, then topped up to 360
        from the measured yaw)."""
        rate = 360.0 / max(seconds, 1.0)
        hz = 30.0
        px = bot.px_per_deg
        sign = bot.invert          # +: moving by +dx lowers the yaw (turns right)
        turned = 0.0
        last = bot.cam_yaw()
        t0 = time.time()
        next_t = t0
        while True:
            now = time.time()
            if turned >= 360.0 or now - t0 > seconds * 1.8 or (now - t0 >= seconds and turned >= 359.0):
                break
            bot.win.mouse_move(round(rate / hz * px * sign, 3), 0)
            next_t += 1.0 / hz
            time.sleep(max(0.0, next_t - time.time()))
            y = bot.cam_yaw()
            if y is not None and last is not None:
                d = -angle_diff(y, last)     # turning right = yaw decreasing
                if abs(d) < 90.0:
                    turned += d
                last = y
            elif y is not None:
                last = y
        return {"turned_deg": round(turned, 1), "seconds": round(time.time() - t0, 1), "px_per_deg": round(px, 4)}

    def walk(self, bot: Bot, seconds: float) -> dict:
        """W, A, S, D in turn (the walk stays near the start point); stops early if a panel opens."""
        plan = [("W", 0.34), ("A", 0.13), ("S", 0.34), ("D", 0.13)]
        p0 = bot.pos()
        dist = 0.0
        last = p0
        interrupted = []
        for key, share in plan:
            t_end = time.time() + seconds * share
            bot.down(key)
            try:
                while time.time() < t_end:
                    time.sleep(0.1)
                    s = bot.state()
                    if s.get("ui_stack"):
                        interrupted.append(list(s["ui_stack"]))
                        break
                    p = (s.get("player") or {}).get("pos")
                    if p:
                        dist += math.hypot(p[0] - last[0], p[2] - last[2])
                        last = p
            finally:
                bot.up(key)
            if interrupted:
                break
        return {"walked_m": round(dist, 1), "start": p0, "end": bot.pos(), "interrupted_by_ui": interrupted}

    # ---------------------------------------------------------------- one area sample
    def run_state(self, pid: str, sid: str) -> dict:
        preset, state = PRESETS[pid], STATES[sid]
        run_dir = self.out / pid / sid
        rec = {"preset": pid, "preset_label": preset["label"], "state": sid, "state_label": state["label"],
               "area": state["area"], "ok": False}
        self.log(f"=== {pid} / {sid}: {state['label']}")
        sess = None
        mem = None
        try:
            t_launch = time.time()
            sess = self.launch(run_dir, f"{pid}_{sid}", preset, build_fixture(state))
            bot = sess.bot
            gpid = sess.proc.pid if (sess.proc and not self.a.headless) else None
            mem = MemSampler(gpid)
            mem.restore_hwnd = self.prev_fg
            mem.start()
            if not self.wait_title(bot):
                raise RuntimeError(f"no title / Continue (mode {bot.state().get('mode')})")
            rec["boot_to_title_s"] = round(time.time() - t_launch, 2)
            n0 = int((self.perf(bot).get("load") or {}).get("n", 0))
            t_click = time.time()
            bot.click_button("Continue", exact=True, timeout=10)
            s = self.wait_arrival(bot, state["area"], n0)
            if s is None:
                st = bot.state()
                raise RuntimeError(f"Continue never reached {state['area']} (mode {st.get('mode')}, area {st.get('area')})")
            rec["continue_to_playing_s"] = round(time.time() - t_click, 2)
            load = self.wait_post_load(bot)
            rec["load"] = load
            rec["zone_at_start"] = bot.state().get("zone")
            rec["pos_at_start"] = bot.pos()
            time.sleep(self.settle_s)
            rec["ui_on_arrival"] = self.dismiss_ui(bot, f"{pid}/{sid}")
            rec["mem_after_load"] = mem.at()
            bot.calibrate_look()
            tele = sess.tele_path
            phases = []
            b0 = boundary(tele)
            t0 = time.time()
            sys0 = system_times()
            rec["pan"] = self.pan(bot, self.pan_s)
            b1 = boundary(tele)
            rec["walk"] = self.walk(bot, self.walk_s)
            b2 = boundary(tele)
            time.sleep(self.idle_s)
            b3 = boundary(tele)
            t3 = time.time()
            rec["system_cpu_busy_pct"] = cpu_busy_pct(sys0, system_times())
            rec["gpu_after_sample"] = nvidia_smi() if not self.a.headless else {}
            phases = [("pan", b0, b1), ("walk", b1, b2), ("idle", b2, b3)]
            all_lines, rows = [], []
            rec["phases"] = {}
            for name, a, b in phases:
                lines = read_lines(tele, a, b)
                all_lines += lines
                fr = collect_frames(lines)
                rec["phases"][name] = frame_stats(fr["frames"], fr["self"], fr["gpu"], fr["cpu"])
                for i, f in enumerate(fr["frames"]):
                    rows.append([name, f, fr["self"][i], fr["gpu"][i], fr["cpu"][i], fr["tick"][i]])
            fr = collect_frames(all_lines)
            rec["stats"] = frame_stats(fr["frames"], fr["self"], fr["gpu"], fr["cpu"])
            rec["monitors"] = monitors(all_lines)
            ms = mem.window(t0, t3)
            if ms:
                rec["private_mb_avg"] = round(statistics.fmean(m["private_mb"] for m in ms), 1)
                rec["private_mb_max"] = max(m["private_mb"] for m in ms)
                rec["ws_mb_max"] = max(m["ws_mb"] for m in ms)
            rec["env"] = ((all_lines[-1].get("perf") or {}).get("env") if all_lines else None) or {}
            rec["sample_zones"] = sorted({str((ln.get("perf") or {}).get("zone", "")) for ln in all_lines})
            rec["sample_modes"] = sorted({str((ln.get("perf") or {}).get("mode", "")) for ln in all_lines})
            # the worst frames with their phase and time into the sample
            t_first = rows[0][5] if rows else 0
            worst = sorted(range(len(rows)), key=lambda i: -rows[i][1])[:8]
            rec["worst_frames"] = [{"phase": rows[i][0], "ms": rows[i][1], "tele_ms": rows[i][2], "gpu_ms": rows[i][3],
                                    "line_t_s": round((rows[i][5] - t_first) / 1000.0, 1)} for i in worst]
            with open(self.out / "frames" / f"{pid}__{sid}.csv", "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                w.writerow(["i", "phase", "frame_ms", "telemetry_ms", "gpu_ms", "cpu_render_ms", "line_tick_ms"])
                for i, r in enumerate(rows):
                    w.writerow([i] + r)
            rec["messages"] = [m.get("text") for m in (bot.state().get("messages") or [])][-12:]
            rec["ok"] = rec["stats"].get("frames", 0) > 0 or self.a.headless
            st = rec["stats"]
            self.log(f"    load {load.get('ms')} ms (click->playing {rec['continue_to_playing_s']} s, worst load frame "
                     f"{load.get('worst_frame_ms')} ms, post-load worst {load.get('post_worst_ms')} ms) | "
                     f"{st.get('frames')} frames avg {st.get('avg_fps')} fps, 1% low {st.get('low1_fps')}, worst {st.get('worst_ms')} ms, "
                     f"tele {st.get('tele_pct')}% | pan {rec['pan']} walk {rec['walk'].get('walked_m')} m | "
                     f"mem {rec.get('private_mb_max')} MB private, video {rec['monitors'].get('video_mb_max')} MB")
        except Exception as e:  # noqa: BLE001
            rec["error"] = f"{type(e).__name__}: {e}"
            self.log(f"    FAILED: {rec['error']}\n{traceback.format_exc()}")
        finally:
            if mem is not None:
                mem.stop()
                rec["os_foreground"] = {"checks": mem.fg_checks, "game_in_foreground": mem.fg_game,
                                        "given_back": mem.fg_restored, "foreground_lock": getattr(self, "fg_locked", None)}
            if sess is not None:
                rec["game_log_errors"] = game_log_errors(sess.game_log)[:20] if self.a.headless else []
                rec["focus_report"] = sess.focus_report()
                rec["telemetry"] = str(sess.tele_path)
            self.stop(sess)
        return rec

    # ---------------------------------------------------------------- Lantern Road round trips
    def checkpoint(self, bot: Bot, mem: MemSampler, label: str, load: dict | None) -> dict:
        pf = self.perf(bot)
        c = {"label": label, "area": pf.get("area"), "zone": pf.get("zone"), "t": round(time.time(), 1)}
        for k in ("nodes", "objects", "resources", "orphans", "static_mb", "video_mb", "texture_mb", "buffer_mb",
                  "draw_calls", "phys_active"):
            c[k] = pf.get(k)
        c["audio_players"] = (pf.get("audio") or {}).get("players")
        c["audio_playing"] = (pf.get("audio") or {}).get("playing")
        en = pf.get("enemies") or {}
        c["enemies"] = en.get("total")
        c["enemies_active"] = en.get("active")
        c["enemies_active_far"] = en.get("active_far")
        m = mem.at()
        c["private_mb"] = m.get("private_mb")
        c["ws_mb"] = m.get("ws_mb")
        if load:
            c["load_ms"] = load.get("ms")
            c["load_worst_frame_ms"] = load.get("worst_frame_ms")
            c["post_load_worst_ms"] = load.get("post_worst_ms")
        self.log(f"    checkpoint {label}: " + ", ".join(f"{k}={v}" for k, v in c.items() if k not in ("label", "t")))
        return c

    def run_roundtrip(self, pid: str, cycles: int) -> dict:
        preset = PRESETS[pid]
        run_dir = self.out / pid / "roundtrip"
        rec = {"preset": pid, "preset_label": preset["label"], "cycles": cycles, "checkpoints": [], "ok": False,
               "start": ROUNDTRIP_STATE["label"]}
        self.log(f"=== {pid} / Lantern Road round trips x{cycles}")
        sess = None
        mem = None
        try:
            sess = self.launch(run_dir, f"{pid}_roundtrip", preset, build_fixture(ROUNDTRIP_STATE))
            bot = sess.bot
            mem = MemSampler(sess.proc.pid if (sess.proc and not self.a.headless) else None)
            mem.restore_hwnd = self.prev_fg
            mem.start()
            if not self.wait_title(bot):
                raise RuntimeError("no title / Continue")
            n0 = int((self.perf(bot).get("load") or {}).get("n", 0))
            bot.click_button("Continue", exact=True, timeout=10)
            if self.wait_arrival(bot, "hallowmere_reach", n0) is None:
                raise RuntimeError("Continue never reached the Reach")
            load = self.wait_post_load(bot)
            time.sleep(self.settle_s + 1.0)
            self.dismiss_ui(bot, f"{pid}/roundtrip")
            bot.calibrate_look()
            g = type("G", (), {})()
            g.bot, g.vin, g.t_launch = bot, bot.win, time.time()
            p = s4_common.Play(g, run_dir)
            b_start = boundary(sess.tele_path)
            rec["checkpoints"].append(self.checkpoint(bot, mem, "reach_0", load))
            for i in range(1, cycles + 1):
                # Reach -> Haven from the Commons arch
                arch = p.nearest(lambda n: n.get("name") == "LanternArch_commons", 40)
                if arch is None:
                    p.goto((0.0, 74.5), tol=1.5, sprint=False, timeout=30)
                    arch = p.nearest(lambda n: n.get("name") == "LanternArch_commons", 40)
                if arch is None:
                    raise RuntimeError(f"cycle {i}: no LanternArch_commons near {bot.pos()}")
                if not p.interact_with(arch, ["Travel the Lantern Road"],
                                       check=lambda: "confirm" in p.ui() or p.find_button("The Haven (home)", exact=True)):
                    raise RuntimeError(f"cycle {i}: the Commons arch offered no Lantern Road (prompt {p.prompt()})")
                n0 = int((self.perf(bot).get("load") or {}).get("n", 0))
                if not p.click_button("The Haven (home)", exact=True, timeout=6):
                    raise RuntimeError(f"cycle {i}: no 'The Haven (home)' button")
                if self.wait_arrival(bot, "surface", n0, 150) is None:
                    raise RuntimeError(f"cycle {i}: did not arrive at the Haven")
                load = self.wait_post_load(bot)
                time.sleep(self.settle_s + 1.0)
                self.dismiss_ui(bot, f"{pid}/roundtrip haven {i}")
                rec["checkpoints"].append(self.checkpoint(bot, mem, f"haven_{i}", load))
                # Haven -> Reach from the Ward Stone
                bot.calibrate_look()
                ws = p.nearest(lambda n: n.get("name") == "WardStone", 60)
                if ws is None:
                    p.goto((0.0, 4.0), tol=2.5, sprint=True, timeout=40)
                    time.sleep(1.2)
                    ws = p.nearest(lambda n: n.get("name") == "WardStone", 60)
                if ws is None:
                    raise RuntimeError(f"cycle {i}: no Ward Stone near {bot.pos()}")
                if not p.interact_with(ws, ["Read the Ward Stone"], check=lambda: "confirm" in p.ui()):
                    raise RuntimeError(f"cycle {i}: the Ward Stone menu did not open (prompt {p.prompt()})")
                if not p.click_button("Travel the Lantern Road", exact=True, timeout=6):
                    raise RuntimeError(f"cycle {i}: no 'Travel the Lantern Road' in the Ward Stone menu")
                n0 = int((self.perf(bot).get("load") or {}).get("n", 0))
                if not p.click_button("Lanternwake Commons", exact=True, timeout=6):
                    raise RuntimeError(f"cycle {i}: no 'Lanternwake Commons' destination")
                if self.wait_arrival(bot, "hallowmere_reach", n0, 150) is None:
                    raise RuntimeError(f"cycle {i}: did not arrive back in the Reach")
                load = self.wait_post_load(bot)
                time.sleep(self.settle_s + 1.0)
                self.dismiss_ui(bot, f"{pid}/roundtrip reach {i}")
                bot.calibrate_look()
                rec["checkpoints"].append(self.checkpoint(bot, mem, f"reach_{i}", load))
            lines = read_lines(sess.tele_path, b_start, boundary(sess.tele_path))
            fr = collect_frames(lines)
            rec["all_frames"] = frame_stats(fr["frames"], fr["self"], fr["gpu"], fr["cpu"])
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001
            rec["error"] = f"{type(e).__name__}: {e}"
            self.log(f"    FAILED: {rec['error']}\n{traceback.format_exc()}")
        finally:
            if mem is not None:
                mem.stop()
                rec["os_foreground"] = {"checks": mem.fg_checks, "game_in_foreground": mem.fg_game,
                                        "given_back": mem.fg_restored, "foreground_lock": getattr(self, "fg_locked", None)}
            if sess is not None:
                rec["game_log_errors"] = game_log_errors(sess.game_log)[:20] if self.a.headless else []
                rec["focus_report"] = sess.focus_report()
            self.stop(sess)
        rec["leak_check"] = leak_check(rec["checkpoints"])
        return rec

    # ---------------------------------------------------------------- the whole profile
    def run(self):
        a = self.a
        env = {"host": platform.node(), "os": platform.platform(), "cpu": cpu_name(), "logical_cpus": os.cpu_count(),
               "ram_gb": system_ram_gb(), "gpu": nvidia_smi(), "python": platform.python_version(),
               "mode": "headless source (validation only)" if a.headless else "packaged build, second monitor, virtual input"}
        if not a.headless:
            ex = Path(a.exe)
            env["exe"] = str(ex)
            env["exe_mtime"] = dt.datetime.fromtimestamp(ex.stat().st_mtime).isoformat(timespec="seconds")
            env["exe_size_mb"] = round(ex.stat().st_size / 1048576.0, 1)
        for sub in ("shader_cache", "vulkan"):
            d = APPDATA_USER / sub
            if d.exists():
                files = [f for f in d.rglob("*") if f.is_file()]
                env[f"user_{sub}"] = {"files": len(files), "mb": round(sum(f.stat().st_size for f in files) / 1048576.0, 1),
                                      "newest": dt.datetime.fromtimestamp(max((f.stat().st_mtime for f in files), default=0)).isoformat(timespec="seconds")}
        self.results["env"] = env
        self.log(f"env: {json.dumps(env)}")
        presets = [x for x in a.presets.split(",") if x]
        states = [x for x in a.states.split(",") if x]
        for pid in presets:
            for sid in states:
                self.results["runs"].append(self.run_state(pid, sid))
                self.save_results()
            if a.round_trips > 0 and (not a.roundtrip_presets or pid in a.roundtrip_presets.split(",")):
                self.results["roundtrips"].append(self.run_roundtrip(pid, a.round_trips))
                self.save_results()
        self.results["finished"] = dt.datetime.now().isoformat(timespec="seconds")
        self.save_results()
        write_reports(self.out, self.results)
        self.log(f"done: {self.out / 'summary.md'}")


# ------------------------------------------------------------------------------------------------ leak check
LEAK_KEYS = ["nodes", "objects", "resources", "orphans", "static_mb", "video_mb", "private_mb", "audio_players",
             "enemies"]


def leak_check(cps: list[dict]) -> dict:
    """Compares arrivals of the same place across cycles (the first visit of each place warms caches up, so the
    trend is taken from visit 1 to the last). 'GROWING' = rises on every revisit by more than the tolerance per
    cycle; 'slow growth' = the least-squares trend over >= 4 revisits exceeds a third of the tolerance per cycle and
    the total rise exceeds the tolerance (a steady creep that single noisy steps would hide)."""
    out = {}
    for place in ("reach", "haven"):
        seq = [c for c in cps if str(c.get("label", "")).startswith(place + "_") and c.get("label") != "reach_0"]
        if len(seq) < 2:
            continue
        res = {}
        for k in LEAK_KEYS:
            vals = [c.get(k) for c in seq]
            if any(v is None for v in vals):
                continue
            vals = [float(v) for v in vals]
            diffs = [b - a for a, b in zip(vals, vals[1:])]
            per_cycle = (vals[-1] - vals[0]) / (len(vals) - 1)
            tol = {"nodes": max(25.0, 0.01 * vals[0]), "objects": max(100.0, 0.01 * vals[0]),
                   "resources": max(10.0, 0.01 * vals[0]), "orphans": 5.0, "static_mb": 8.0, "video_mb": 16.0,
                   "private_mb": 24.0, "audio_players": 2.0, "enemies": 2.0}.get(k, 0.0)
            growing = all(d > 0 for d in diffs) and per_cycle > tol
            n = len(vals)
            xm = (n - 1) / 2.0
            ym = sum(vals) / n
            den = sum((i - xm) ** 2 for i in range(n))
            slope = sum((i - xm) * (v - ym) for i, v in enumerate(vals)) / den if den else 0.0
            creep = n >= 4 and slope > tol / 3.0 and (vals[-1] - vals[0]) > tol
            res[k] = {"values": vals, "per_cycle": round(per_cycle, 1), "slope": round(slope, 2), "tolerance": round(tol, 1),
                      "verdict": "GROWING" if growing else ("slow growth" if creep else "stable")}
        out[place] = res
    verdicts = [v["verdict"] for pl in out.values() for v in pl.values()]
    out["overall"] = ("GROWTH SUSPECTED" if "GROWING" in verdicts else
                      "slow growth (see per-metric)" if "slow growth" in verdicts else ("stable" if verdicts else "n/a"))
    return out


# ------------------------------------------------------------------------------------------------ reports
def fmt(v, nd=1):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "-"
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def write_reports(out: Path, res: dict) -> None:
    runs = res.get("runs", [])
    # summary.csv
    cols = ["state", "preset", "ok", "avg_fps", "low1_fps", "low01_fps", "median_ms", "p99_ms", "worst_ms", "over_33",
            "over_50", "frames", "tele_pct", "gpu_avg_ms", "gpu_share", "load_ms", "continue_to_playing_s",
            "load_worst_frame_ms", "post_load_worst_ms", "private_mb_max", "video_mb_max", "static_mb_max",
            "draw_calls_avg", "objects_drawn_avg", "nodes_max", "enemies_total_max", "enemies_active_far_max",
            "enemies_active_offscreen_max", "audio_players_max", "system_cpu_busy_pct", "error"]
    with open(out / "summary.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for r in runs:
            st, mo, ld = r.get("stats") or {}, r.get("monitors") or {}, r.get("load") or {}
            w.writerow([r.get("state"), r.get("preset"), r.get("ok"), st.get("avg_fps"), st.get("low1_fps"), st.get("low01_fps"),
                        st.get("median_ms"), st.get("p99_ms"), st.get("worst_ms"), st.get("over_33"), st.get("over_50"),
                        st.get("frames"), st.get("tele_pct"), st.get("gpu_avg_ms"), st.get("gpu_share"), ld.get("ms"),
                        r.get("continue_to_playing_s"), ld.get("worst_frame_ms"), ld.get("post_worst_ms"), r.get("private_mb_max"),
                        mo.get("video_mb_max"), mo.get("static_mb_max"), mo.get("draw_calls_avg"), mo.get("objects_drawn_avg"),
                        mo.get("nodes_max"), mo.get("enemies_total_max"), mo.get("enemies_active_far_max"),
                        mo.get("enemies_active_offscreen_max"), mo.get("audio_players_max"), r.get("system_cpu_busy_pct"),
                        r.get("error", "")])
    with open(out / "roundtrip.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        keys = ["label", "area", "load_ms", "load_worst_frame_ms", "post_load_worst_ms", "nodes", "objects", "resources",
                "orphans", "static_mb", "video_mb", "private_mb", "ws_mb", "audio_players", "audio_playing", "enemies",
                "enemies_active", "enemies_active_far"]
        w.writerow(["preset"] + keys)
        for rt in res.get("roundtrips", []):
            for c in rt.get("checkpoints", []):
                w.writerow([rt.get("preset")] + [c.get(k) for k in keys])
    # summary.md
    env = res.get("env", {})
    e0 = next((r.get("env") for r in runs if r.get("env")), {}) or {}
    L = []
    L.append("# Hollowhaven performance profile (MP 20.5)\n")
    L.append(f"Run {res.get('started')} -> {res.get('finished', '(running)')}. Mode: **{env.get('mode')}**.\n")
    L.append("## Setup\n")
    L.append(f"* Build: `{env.get('exe', 'source project (headless)')}` (mtime {env.get('exe_mtime', '-')}, "
             f"{env.get('exe_size_mb', '-')} MB); engine {e0.get('engine', '-')}, debug build: {e0.get('debug_build', '-')}; "
             f"renderer {e0.get('method', '-')} / {e0.get('driver', '-')} (API {e0.get('api', '-')}).")
    g = env.get("gpu") or {}
    L.append(f"* Hardware: {env.get('cpu')} ({env.get('logical_cpus')} threads), {env.get('ram_gb')} GB RAM, "
             f"{g.get('name', e0.get('adapter', '-'))} (driver {g.get('driver', '-')}, {g.get('mem_total_mib', '-')} MiB); {env.get('os')}.")
    L.append(f"* Display: game window borderless on DISPLAY2 (x=1920), monitor refresh {e0.get('refresh_hz', '-')} Hz; "
             f"vsync {'ON' if res['args'].get('vsync') == 'on' else 'OFF'} and max_fps 0 (uncapped, so the numbers show headroom; "
             "the shipped default is vsync on = capped at the refresh rate); audio muted (--qa-mute); window never focused.")
    fgc = sum((r.get("os_foreground") or {}).get("checks", 0) for r in runs + res.get("roundtrips", []))
    fgg = sum((r.get("os_foreground") or {}).get("game_in_foreground", 0) for r in runs + res.get("roundtrips", []))
    L.append(f"* Focus: the OS foreground window (GetForegroundWindow, every 0.5 s) belonged to the game in {fgg} of {fgc} checks. "
             "A fresh helper process holds LockSetForegroundWindow for the life of each game process (ForegroundLock): without it "
             "the packaged build's first window became the OS foreground window ~0.6 s after launch despite override.cfg no_focus. "
             f"Lock taken in {sum(1 for r in runs + res.get('roundtrips', []) if (r.get('os_foreground') or {}).get('foreground_lock'))} "
             f"of {len(runs) + len(res.get('roundtrips', []))} game sessions. "
             "(The telemetry's window_focused is Godot's own flag and stayed true even while the game was not in front.)")
    L.append(f"* Shader caches in %APPDATA%\\Hollowhaven before the run: {env.get('user_shader_cache', '-')} / vulkan {env.get('user_vulkan', '-')}.")
    L.append(f"* Sample per state: settle {res['args'].get('settle_seconds')} s after the load, 360-degree pan "
             f"{res['args'].get('pan_seconds')} s, walk W/A/S/D {res['args'].get('walk_seconds')} s, idle {res['args'].get('idle_seconds')} s"
             f"{' (x0.35, --quick)' if res['args'].get('quick') else ''}. Frame time = interval between consecutive frames "
             "(telemetry node _process, Time.get_ticks_usec). 1% low = 1000 / mean of the slowest 1% frame times.")
    L.append("* Presets: " + "; ".join(f"`{k}` = {PRESETS[k]['label']} (quality {PRESETS[k]['quality']}, render scale "
                                       f"{PRESETS[k]['render_scale']})" for k in res['args'].get('presets', '').split(",") if k in PRESETS))
    L.append("")
    L.append("## Area x preset\n")
    L.append("| Area | Preset | Avg FPS | 1% low | 0.1% low | p99 ms | Worst ms | >16.7 ms | >33 ms | >50 ms | GPU ms avg | Load ms (in-game) | Click->play s | Post-load worst ms | Private MB | Video MB | Draw calls | Tele % |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in runs:
        st, mo, ld = r.get("stats") or {}, r.get("monitors") or {}, r.get("load") or {}
        if r.get("error"):
            L.append(f"| {r['state']} | {r['preset']} | FAILED: {r['error'][:120]} |" + " |" * 16)
            continue
        L.append(f"| {r['state']} | {r['preset']} | {fmt(st.get('avg_fps'))} | {fmt(st.get('low1_fps'))} | {fmt(st.get('low01_fps'))} | "
                 f"{fmt(st.get('p99_ms'), 2)} | {fmt(st.get('worst_ms'), 1)} | {fmt(st.get('over_16_7'))} | {fmt(st.get('over_33'))} | {fmt(st.get('over_50'))} | "
                 f"{fmt(st.get('gpu_avg_ms'), 2)} | {fmt(ld.get('ms'), 0)} | {fmt(r.get('continue_to_playing_s'), 2)} | "
                 f"{fmt(ld.get('post_worst_ms'), 1)} | {fmt(r.get('private_mb_max'), 0)} | {fmt(mo.get('video_mb_max'), 0)} | "
                 f"{fmt(mo.get('draw_calls_avg'), 0)} | {fmt(st.get('tele_pct'), 2)} |")
    L.append("")
    L.append("## Loading\n")
    L.append("In-game load ms = first frame seen in Game.mode 'loading' -> 'playing' (a Lantern Road trip includes its 0.45 s "
             "fade-out; from the title there is no fade and the frame that parses the save and swaps the scene is counted as the "
             "'worst frame during load'). Click->play s is the bot's wall clock (+ up to one 0.2 s telemetry line). The 0.6 s "
             "fade-in after 'playing' is inside the 'first 3 s after' window.\n")
    L.append("| Area | Preset | In-game load ms (mode loading->playing, incl. 0.45 s fade-out) | Worst frame during load ms | Frames >50 ms in load | Worst frame first 3 s after ms | >50 ms after |")
    L.append("|---|---|---|---|---|---|---|")
    for r in runs:
        ld = r.get("load") or {}
        L.append(f"| {r['state']} | {r['preset']} | {fmt(ld.get('ms'), 0)} | {fmt(ld.get('worst_frame_ms'), 1)} | "
                 f"{fmt(ld.get('long_frames'))} | {fmt(ld.get('post_worst_ms'), 1)} | {fmt(ld.get('post_long_frames'))} |")
    L.append("")
    L.append("## Lantern Road round trips (leak check)\n")
    for rt in res.get("roundtrips", []):
        L.append(f"### {rt.get('preset_label')} - {rt.get('cycles')} cycles - {'OK' if rt.get('ok') else 'FAILED: ' + str(rt.get('error'))}\n")
        L.append("| Checkpoint | Load ms | Post-load worst ms | Nodes | Objects | Resources | Orphans | Static MB | Video MB | Private MB | Audio players (playing) | Enemies (active far) |")
        L.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
        for c in rt.get("checkpoints", []):
            L.append(f"| {c.get('label')} | {fmt(c.get('load_ms'), 0)} | {fmt(c.get('post_load_worst_ms'))} | {fmt(c.get('nodes'))} | "
                     f"{fmt(c.get('objects'))} | {fmt(c.get('resources'))} | {fmt(c.get('orphans'))} | {fmt(c.get('static_mb'))} | "
                     f"{fmt(c.get('video_mb'))} | {fmt(c.get('private_mb'))} | {fmt(c.get('audio_players'))} ({fmt(c.get('audio_playing'))}) | "
                     f"{fmt(c.get('enemies'))} ({fmt(c.get('enemies_active_far'))}) |")
        lc = rt.get("leak_check") or {}
        L.append("")
        L.append(f"Verdict: **{lc.get('overall', 'n/a')}**. " + "; ".join(
            f"{place}: " + ", ".join(f"{k} {v['per_cycle']:+}/cycle ({v['verdict']})" for k, v in lc.get(place, {}).items())
            for place in ("reach", "haven") if lc.get(place)))
        af = rt.get("all_frames") or {}
        L.append(f"\nWhole round-trip run: {fmt(af.get('frames'))} frames, worst {fmt(af.get('worst_ms'))} ms, "
                 f">50 ms: {fmt(af.get('over_50'))}, >100 ms: {fmt(af.get('over_100'))} (loads included).\n")
    L.append("## Stalls / outliers (sample frames > 50 ms, worst 3 per run)\n")
    any_stall = False
    for r in runs:
        st = r.get("stats") or {}
        if (st.get("over_50") or 0) > 0:
            any_stall = True
            ws = ", ".join(f"{w['ms']:.1f} ms ({w['phase']} @{w['line_t_s']} s, tele {w['tele_ms']:.1f}, gpu {w['gpu_ms']:.1f})"
                           for w in (r.get("worst_frames") or [])[:3])
            L.append(f"* {r['state']} / {r['preset']}: {st.get('over_50')} frames > 50 ms; {ws}")
    if not any_stall:
        L.append("* none in the samples (see the Loading table for load-time and first-seconds hitches)")
    L.append("")
    L.append("## Enemy AI / audio during the samples\n")
    L.append("| Area | Preset | Enemies (max) | Alive | Processing | Processing > 60 m | Processing off-screen | Farthest processing m | Audio players | Playing |")
    L.append("|---|---|---|---|---|---|---|---|---|---|")
    for r in runs:
        mo = r.get("monitors") or {}
        L.append(f"| {r['state']} | {r['preset']} | {fmt(mo.get('enemies_total_max'))} | {fmt(mo.get('enemies_alive_max'))} | "
                 f"{fmt(mo.get('enemies_active_max'))} | {fmt(mo.get('enemies_active_far_max'))} | {fmt(mo.get('enemies_active_offscreen_max'))} | "
                 f"{fmt(mo.get('enemies_active_max_dist'))} | {fmt(mo.get('audio_players_max'))} | {fmt(mo.get('audio_playing_max'))} |")
    L.append("")
    L.append("## Files\n")
    L.append("results.json (everything), summary.csv, roundtrip.csv, frames/<preset>__<state>.csv (per frame), "
             "<preset>/<state>/ (telemetry jsonl, perf_log.jsonl, bot log, saves, settings).")
    (out / "summary.md").write_text("\n".join(L) + "\n", encoding="utf-8")


# ------------------------------------------------------------------------------------------------ main
def wait_for_build(exe: Path, after: str, max_minutes: float, log) -> bool:
    t_after = dt.datetime.fromisoformat(after).timestamp()
    t0 = time.time()
    while True:
        try:
            m = exe.stat().st_mtime
        except OSError:
            m = 0
        if m > t_after:
            # a fresh export is still being written for a while: wait until the size is stable
            s1, m1 = exe.stat().st_size, exe.stat().st_mtime
            time.sleep(20)
            if exe.exists() and exe.stat().st_size == s1 and exe.stat().st_mtime == m1:
                log(f"build {exe} mtime {dt.datetime.fromtimestamp(m).isoformat(timespec='seconds')} is newer than {after}")
                return True
            continue
        if time.time() - t0 > max_minutes * 60:
            log(f"gave up waiting for a build newer than {after} after {max_minutes} min")
            return False
        log(f"waiting for a build of {exe} newer than {after} (now {dt.datetime.fromtimestamp(m).isoformat(timespec='seconds') if m else 'missing'})")
        time.sleep(60)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "qa" / "tmp" / "perf" / time.strftime("run_%Y%m%d_%H%M")))
    ap.add_argument("--exe", default=str(DEFAULT_EXE), help="packaged build (ignored with --headless)")
    ap.add_argument("--headless", action="store_true", help="validate against the SOURCE project headless (fps meaningless)")
    ap.add_argument("--presets", default="high1080,low1080,high720", help=f"comma list of {list(PRESETS)}")
    ap.add_argument("--states", default=",".join(STATES), help=f"comma list of {list(STATES)}")
    ap.add_argument("--round-trips", type=int, default=3, help="Lantern Road Reach->Haven->Reach cycles per preset (0 = skip)")
    ap.add_argument("--roundtrip-presets", default="", help="only these presets get the round trips (default: all)")
    ap.add_argument("--pan-seconds", type=float, default=20.0)
    ap.add_argument("--walk-seconds", type=float, default=12.0)
    ap.add_argument("--idle-seconds", type=float, default=4.0)
    ap.add_argument("--settle-seconds", type=float, default=2.5)
    ap.add_argument("--quick", action="store_true", help="shorter samples (x0.35) for harness validation")
    ap.add_argument("--vsync", choices=["off", "on"], default="off")
    ap.add_argument("--mute", action="store_true", help="--qa-mute (silent session)")
    ap.add_argument("--watchdog", type=int, default=900, help="the game's own --max-seconds per process")
    ap.add_argument("--wait-build-after", default="", help="ISO time: first wait until --exe is newer (poll 60 s)")
    ap.add_argument("--wait-max-minutes", type=float, default=90.0)
    ap.add_argument("--report-only", action="store_true", help="rewrite summary.md / csv from <out>/results.json")
    a = ap.parse_args()
    if a.report_only:
        res = json.loads((Path(a.out) / "results.json").read_text(encoding="utf-8"))
        for rt in res.get("roundtrips", []):
            rt["leak_check"] = leak_check(rt.get("checkpoints", []))
        (Path(a.out) / "results.json").write_text(json.dumps(res, indent=1, default=str), encoding="utf-8")
        write_reports(Path(a.out), res)
        print(Path(a.out) / "summary.md")
        return
    for pid in a.presets.split(","):
        if pid and pid not in PRESETS:
            ap.error(f"unknown preset {pid}")
    for sid in a.states.split(","):
        if sid and sid not in STATES:
            ap.error(f"unknown state {sid}")
    r = Runner(a)
    if a.wait_build_after and not a.headless:
        if not wait_for_build(Path(a.exe), a.wait_build_after, a.wait_max_minutes, r.log):
            sys.exit(2)
    r.run()


if __name__ == "__main__":
    main()
