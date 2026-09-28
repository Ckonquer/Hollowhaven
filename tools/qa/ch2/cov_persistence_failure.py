"""Coverage run "persistence_failure" (MP 20.4 Run E: persistence / failure) - headless QA bot, index 4.

What it exercises (each phase is a sub-command; `all` runs them in order):
  areas     save -> quit -> relaunch -> Continue in every area type: surface (the Haven), Hallowmere Reach (Commons),
            Hushed Works (the refuge, then the refuge lantern), Moonveil Manor (cloakroom, then the ballroom rest
            candles), the Echo Trial (Velour's, from the ballroom candles: no save inside, Continue lands at the
            origin), Tobin's Annex (lamp room). Checks area, position (outdoor: the saved spot; indoor: the arrival /
            checkpoint spawn), respawn fields in the save, items / keys / flags unchanged.
  kill      >= 20 hard kills (TerminateProcess of the real Godot child) DURING save writes triggered by the pause
            menu "Save Game", "Quit Game -> Save & Quit" and a Lantern Road arrival (area-change save), at random
            offsets (armed on the appearance of slot1.tmp, or blind after the click). After each kill: the save files
            are classified (python replica of SaveSystem._read_status / _best_available) and the next launch must show
            Continue and load the main save, the complete temp save or the backup (never nothing, never a partial),
            with the backup notice exactly when the backup was used.
  synth     DIAGNOSTIC (synthetic crash states written by this script, not by a kill): a torn temp file beside a good
            main, a complete temp with no main (crash between rotate and rename), a main with no backup and a torn
            temp - the windows a random kill rarely hits.
  corrupt   corrupt the main save (truncated / zero bytes / not a save) -> relaunch: backup used, backup notice,
            corrupt file preserved byte-identical as slot1.corrupt-<unix>.json; both files corrupt -> no Continue.
  future    a version-3 main save (+ a valid v2 backup) -> Continue visible but disabled, clicking does nothing, the
            v3 file and the backup untouched (hashes, mtimes, folder listing); a v3 backup with a torn main likewise.
  prev2     the real v1 fixture 16 (main + backup) -> Continue: pre_v2_backup/ copies made once, byte-identical;
            several saves + relaunches later still exactly those copies, unchanged.
  velour    natural start (chain run3 checkpoint T23_end): road to the manor, S3 route to Count Velour, die once on
            purpose, retry, win, lantern; ledger / item diff pre-fight vs post-win vs the chain's no-death baseline,
            then save -> quit -> relaunch -> Continue: no reward granted twice.
  crossing  natural start (chain run3 S4 checkpoint "winch", the crossing_gate lantern save): die once on the bridge,
            retry, win; the same ledger checks.

  areas_tail  resume of `areas` from its game-written ballroom-candles save: pause -> Leave the trial, then the annex.
  probe     where "Return to safety" (= Game.return_point, the fall respawn) sends her right after entering the Works by
            the refuge hatch / the manor by its front door (game-written saves of the areas run).
  recheck   re-evaluates three checks whose first rule in this script was wrong (kept beside the originals).
  bugs      merges <phase>/result.json bugs + manual_bugs.json (reviewed findings) into bugs.json.

Rules honoured: headless only (console Godot, --headless, virtual input on 127.0.0.1, no window, no SendInput, no
desktop screenshots); the working tree game/; ports 8180-8199 (index 4 * 20 + 8100); every process is started and
killed by this script only (its own PIDs: the console wrapper and its Godot child); isolated --save-dir and
--settings-file under qa/tmp/bot/cov_persistence_failure/<phase>/. No game code is touched; no cheats, no debug area
switches. Information advantage: the bot reads telemetry (positions, states) and the save files on disk.

  python tools/qa/ch2/cov_persistence_failure.py <phase> [--attempts N] [--seed N]
Outputs: qa/tmp/bot/cov_persistence_failure/<phase>/result.json (+ logs, telemetry, save snapshots) and
qa/tmp/bot/cov_persistence_failure/bugs.json (merged by `bugs`).
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.wintypes as wt
import hashlib
import json
import math
import os
import random
import shutil
import socket
import subprocess
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
QA_DIR = HERE.parent
ROOT = QA_DIR.parents[1]
for _p in (str(HERE), str(QA_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import s1_common as C  # noqa: E402
from hhbot import Telemetry, VirtualInputError  # noqa: E402
from chain import ChainBot  # noqa: E402
from s4_common import StepFailed, dist2, xz  # noqa: E402
import s4_route as R4  # noqa: E402

GAME_DIR = ROOT / "game"
CONSOLE = ROOT / ".tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
RUN = ROOT / "qa" / "tmp" / "bot" / "cov_persistence_failure"
CHAIN = ROOT / "qa" / "tmp" / "bot" / "chain"
FIXTURES = GAME_DIR / "tests" / "fixtures" / "saves"
PORT_BASE = 8100 + 4 * 20          # 8180 .. 8199
# port sub-ranges per phase (so phases can run side by side without colliding)
PORTS = {"areas": (0, 3), "areas_tail": (0, 3), "probe": (0, 3), "kill": (3, 9), "synth": (9, 11), "corrupt": (11, 13), "future": (13, 14), "prev2": (14, 15),
         "velour": (15, 17), "crossing": (17, 20)}
REACH, SURFACE, MANOR, WORKS, ANNEX, TRIAL = ("hallowmere_reach", "surface", "moonveil_manor", "hushed_works",
                                             "tobin_annex", "echo_trial")
BACKUP_NOTICE = "Your latest save was damaged, so your previous save was restored."
FOOD = ("hearty_stew", "pumpkin_soup", "roseberry_tart", "berry_snack", "glowcap_skewer", "pumpkin_biscuit",
        "candy", "sweetroot", "roseberries", "berries")
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


# ============================================================================================ small utils
def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def write_json(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".part")
    tmp.write_text(json.dumps(data, indent=1, default=str), encoding="utf-8")
    os.replace(tmp, p)


def sha(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


_port_turn: dict = {}


def pick_port(phase: str) -> int:
    lo, hi = PORTS[phase]
    n = hi - lo
    start = _port_turn.get(phase, 0)
    for k in range(n * 3):
        p = PORT_BASE + lo + (start + k) % n
        if port_free(p):
            _port_turn[phase] = (start + k + 1) % n
            return p
        time.sleep(0.3)
    raise RuntimeError(f"no free port in {PORT_BASE + lo}..{PORT_BASE + hi - 1}")


# ============================================================================================ processes (Win32)
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
TH32CS_SNAPPROCESS = 0x2
PROCESS_TERMINATE = 0x1
SYNCHRONIZE = 0x100000
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long), ("dwFlags", wt.DWORD),
                ("szExeFile", ctypes.c_wchar * 260)]


k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
k32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
k32.Process32NextW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
k32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
k32.CloseHandle.argtypes = [wt.HANDLE]


def child_pids(parent: int) -> list[tuple[int, str]]:
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    out = []
    if not snap or snap == wt.HANDLE(-1).value:
        return out
    try:
        e = PROCESSENTRY32W()
        e.dwSize = ctypes.sizeof(PROCESSENTRY32W)
        ok = k32.Process32FirstW(snap, ctypes.byref(e))
        while ok:
            if e.th32ParentProcessID == parent:
                out.append((int(e.th32ProcessID), e.szExeFile))
            ok = k32.Process32NextW(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    return out


class ProcHandle:
    """An open terminate handle on one of OUR processes (opened before arming a kill so the kill is one syscall)."""

    def __init__(self, pid: int):
        self.pid = pid
        self.h = k32.OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, False, pid)

    def terminate(self) -> bool:
        if not self.h:
            return False
        return bool(k32.TerminateProcess(self.h, 1))

    def wait(self, ms: int = 5000) -> bool:
        if not self.h:
            return True
        return k32.WaitForSingleObject(self.h, ms) == 0

    def close(self):
        if self.h:
            k32.CloseHandle(self.h)
            self.h = None


# ============================================================================================ save files
def read_status(path: Path) -> dict:
    """Python replica of SaveSystem._read_status (game/autoload/save_system.gd)."""
    out = {"status": "missing", "version": 0}
    p = Path(path)
    if not p.exists():
        return out
    raw = p.read_bytes()
    out.update({"size": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "mtime": p.stat().st_mtime})
    out["status"] = "corrupt"
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return out
    if text.strip() == "":
        return out
    try:
        d = json.loads(text, parse_constant=lambda c: (_ for _ in ()).throw(ValueError(c)))
    except ValueError:
        return out
    if not isinstance(d, dict):
        return out
    fmt = d.get("format", "")
    if not isinstance(fmt, str) or fmt != "hollowhaven-save":
        return out
    ver = d.get("version", 0)
    if isinstance(ver, bool) or not isinstance(ver, (int, float)) or not math.isfinite(ver) or int(ver) < 1:
        return out
    out["version"] = int(ver)
    if int(ver) > 2:
        out["status"] = "future"
        return out
    if not isinstance(d.get("state"), dict):
        return out
    out["status"] = "ok"
    st = d["state"]
    pl = st.get("player", {}) if isinstance(st.get("player"), dict) else {}
    out.update({"saved_unix": d.get("saved_unix", 0.0), "area": pl.get("area"), "spawn": pl.get("spawn"),
                "pos": pl.get("pos"), "respawn": [pl.get("respawn_area"), pl.get("respawn_spawn")],
                "area_respawn": pl.get("area_respawn"), "total_minutes": st.get("total_minutes"),
                "deaths": (st.get("stats") or {}).get("deaths"), "play_seconds": (st.get("stats") or {}).get("play_seconds")})
    return out


def folder_state(save_dir: Path) -> dict:
    sd = Path(save_dir)
    files = {}
    if sd.exists():
        for f in sorted(sd.rglob("*")):
            if f.is_file():
                rel = f.relative_to(sd).as_posix()
                files[rel] = read_status(f) if rel.startswith("slot1") and "/" not in rel else \
                    {"size": f.stat().st_size, "sha256": sha(f), "mtime": f.stat().st_mtime}
    return files


def expected_load(save_dir: Path) -> dict:
    """Python replica of SaveSystem._best_available: which file Continue must load."""
    sd = Path(save_dir)
    m = read_status(sd / "slot1.json")
    if m["status"] == "ok":
        return {"source": "main", "file": m}
    b = read_status(sd / "slot1.bak.json")
    t = read_status(sd / "slot1.tmp")
    for name, stt in (("main", m), ("tmp", t), ("bak", b)):
        if stt["status"] == "future":
            return {"source": "future", "file": stt, "which": name}
    if t["status"] == "ok" and (b["status"] != "ok" or float(t.get("saved_unix") or 0) >= float(b.get("saved_unix") or 0)):
        return {"source": "tmp", "file": t}
    if b["status"] == "ok":
        return {"source": "bak", "file": b}
    return {"source": "", "file": {}}


def load_save(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def copy_saves(src_dir: Path, dst_dir: Path) -> None:
    dst_dir = Path(dst_dir)
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    shutil.copytree(src_dir, dst_dir)


def ledger_diff(before: dict, after: dict) -> dict:
    """Reward ledger / item / key / flag differences between two game-written saves (dicts)."""
    sb, sa = before["state"], after["state"]
    lb, la = sb.get("ledger") or {}, sa.get("ledger") or {}

    def inv_totals(st):
        tot = {}
        for s in (st.get("inventory") or []):
            if isinstance(s, dict) and s.get("id"):
                tot[s["id"]] = tot.get(s["id"], 0) + int(s.get("count", 1))
        for sid, sto in (st.get("storages") or {}).items():
            for s in (sto if isinstance(sto, list) else (sto.get("slots") or [] if isinstance(sto, dict) else [])):
                if isinstance(s, dict) and s.get("id"):
                    tot[s["id"]] = tot.get(s["id"], 0) + int(s.get("count", 1))
        return tot

    ib, ia = inv_totals(sb), inv_totals(sa)
    kb, ka = sb.get("key_items") or {}, sa.get("key_items") or {}
    fb = set(sb.get("flags") or {}) if not isinstance(sb.get("flags"), list) else set(sb.get("flags"))
    fa = set(sa.get("flags") or {}) if not isinstance(sa.get("flags"), list) else set(sa.get("flags"))
    return {
        "ledger_added": sorted(k for k in la if k not in lb),
        "ledger_removed": sorted(k for k in lb if k not in la),
        "ledger_time_changed": sorted(k for k in la if k in lb and la[k] != lb[k]),
        "items_delta": {k: ia.get(k, 0) - ib.get(k, 0) for k in sorted(set(ia) | set(ib)) if ia.get(k, 0) != ib.get(k, 0)},
        "keys_delta": {k: int(ka.get(k, 0)) - int(kb.get(k, 0)) for k in sorted(set(ka) | set(kb))
                       if int(ka.get(k, 0)) != int(kb.get(k, 0))},
        "flags_added": sorted(fa - fb), "flags_removed": sorted(fb - fa),
        "deaths": [(sb.get("stats") or {}).get("deaths"), (sa.get("stats") or {}).get("deaths")],
        "trials": [sb.get("trials"), sa.get("trials")],
        "chapter2_done_added": sorted(set(((sa.get("chapter2") or {}).get("done") or []))
                                      - set(((sb.get("chapter2") or {}).get("done") or []))),
    }


# ============================================================================================ one game process
class Game:
    """One headless game process (console Godot wrapper + its Godot child), virtual input, telemetry, a ChainBot."""

    def __init__(self, phase: str, name: str, save_dir: Path, max_seconds: int = 1200, seed: int | None = None):
        self.phase = phase
        self.dir = RUN / phase
        self.dir.mkdir(parents=True, exist_ok=True)
        self.name = name
        self.save_dir = Path(save_dir).resolve()
        self.settings_file = self.dir / "settings.cfg"
        self.tele_path = self.dir / f"{name}_telemetry.jsonl"
        self.godot_log = self.dir / f"{name}_godot.log"
        self.bot_log = self.dir / f"{name}_bot.log"
        self.max_seconds = max_seconds
        self.seed = seed
        self.proc: subprocess.Popen | None = None
        self.child: int = 0
        self.child_exe = ""
        self.vin = None
        self.bot: ChainBot | None = None
        self.t_launch = 0.0
        self.port = 0
        self.cmd: list[str] = []
        self._fh = None

    def start(self) -> ChainBot:
        if self.tele_path.exists():
            self.tele_path.unlink()
        self.port = pick_port(self.phase)
        user = [f"--qa-input-port={self.port}", "--qa-no-focus", f"--qa-telemetry={self.tele_path.as_posix()}",
                "--qa-interval=0.1", f"--save-dir={self.save_dir.as_posix()}",
                f"--settings-file={self.settings_file.as_posix()}", "--no-focus-pause",
                f"--max-seconds={int(self.max_seconds)}", "--no-wardrobe-notice"]
        if self.seed is not None:
            user.append(f"--seed={int(self.seed)}")
        self.cmd = [str(CONSOLE), "--headless", "--path", str(GAME_DIR), "--max-fps", "60", "--"] + user
        self._fh = open(self.godot_log, "a", encoding="utf-8", errors="replace")
        self._fh.write(f"\n==== launch {now()}: {self.cmd}\n")
        self._fh.flush()
        self.t_launch = time.time()
        self.proc = subprocess.Popen(self.cmd, cwd=str(ROOT), stdout=self._fh, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW)
        tele = Telemetry(self.tele_path)
        try:
            self.vin = C.FloatVI(self.port, proc=self.proc, tele=tele, connect_timeout=120)
        except Exception:
            self.stop()
            raise
        self.bot = ChainBot(self.vin, tele, self.bot_log)
        # the console wrapper starts conhost.exe AND the real Godot exe: the game is the Godot child
        for _ in range(40):
            kids = [k for k in child_pids(self.proc.pid) if k[1].lower().startswith("godot")]
            if kids:
                self.child, self.child_exe = kids[0]
                break
            time.sleep(0.05)
        self.bot.log(f"launched {self.name} pid={self.proc.pid} child={self.child} ({self.child_exe}) port={self.port} "
                     f"cmd={self.cmd}")
        return self.bot

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

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
        if self.proc is not None and self.proc.poll() is None:
            try:
                subprocess.run(["taskkill", "/T", "/F", "/PID", str(self.proc.pid)], capture_output=True, timeout=20,
                               creationflags=CREATE_NO_WINDOW)
            except Exception:  # noqa: BLE001
                pass
            try:
                self.proc.wait(15)
            except Exception:  # noqa: BLE001
                pass
        if self._fh is not None:
            try:
                self._fh.close()
            except OSError:
                pass
            self._fh = None

    def log_errors(self) -> list[str]:
        out = []
        if not self.godot_log.exists():
            return out
        lines = self.godot_log.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, ln in enumerate(lines):
            if ln.startswith(("SCRIPT ERROR", "ERROR", "USER ERROR", "USER SCRIPT ERROR")):
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                out.append(ln.strip() + (" | " + nxt if nxt.startswith("at:") else ""))
        return out


# ============================================================================================ play helpers
class P(R4.S4):
    """The S4 play layer (area-graph walking, interact, UI, fights) + persistence helpers."""

    def saved_msgs(self) -> list:
        self.st()
        return [m for m in self.all_msgs if m.get("k") == "saved"]

    def notices(self, text_part: str) -> list:
        self.st()
        return [m for m in self.all_msgs if text_part.lower() in str(m.get("text", "")).lower()]

    def deaths(self) -> int:
        self.st()
        return sum(1 for m in self.all_msgs if m.get("text") == "player died")

    def observe(self) -> dict:
        s = self.st()
        pl = s.get("player") or {}
        return {"mode": s.get("mode"), "area": s.get("area"), "zone": s.get("zone"), "pos": pl.get("pos"),
                "hp": pl.get("hp"), "inv": s.get("inv"), "keys": s.get("keys"), "flags": sorted(s.get("flags") or []),
                "day": s.get("day"), "hour": s.get("hour"), "ui": s.get("ui_stack"),
                "ch2_done": len((s.get("chapter2") or {}).get("done") or []), "objective": (s.get("objective") or {}).get("id")}

    def open_pause(self) -> bool:
        if "pause" in self.ui():
            return True
        self.close_panels()
        self.bot.tap("ESC")
        return self.wait(lambda s: "pause" in (s.get("ui_stack") or []), 3.0) is not None

    def save_button(self) -> dict | None:
        for b in self.buttons():
            if str(b.get("text", "")).strip() == "Save Game":
                return b
        return None

    def pause_save(self) -> dict:
        """Esc -> Save Game; proves it by a new "saved" message. Returns what happened."""
        rec = {"pause_open": self.open_pause()}
        self.wait(lambda s: any(str(b.get("text")) == "Save Game" for b in s.get("buttons") or []), 2.0)
        b = self.save_button()
        rec["save_button"] = None if b is None else {"disabled": bool(b.get("disabled"))}
        n0 = len(self.saved_msgs())
        if b is not None and not b.get("disabled"):
            r = b.get("rf") or b.get("rect")
            x, y, w, h = [float(v) for v in r]
            self.g.vin.click(x + w / 2.0, y + h / 2.0)
            ok = self.wait(lambda s: len([m for m in self.all_msgs if m.get("k") == "saved"]) > n0, 6.0) is not None
            rec["saved"] = ok
            sm = self.saved_msgs()
            rec["saved_text"] = sm[-1].get("text") if len(sm) > n0 else None
        else:
            rec["saved"] = False
        self.close_panels()
        return rec

    def quit_via_menu(self, prefer_save: bool = True) -> dict:
        """Esc -> Quit Game -> Save & Quit (or Quit when saving is refused). Returns the choice offered / taken."""
        rec = {"pause_open": self.open_pause()}
        if not self.click_button("Quit Game", exact=True, timeout=3.0):
            rec["error"] = "no Quit Game button"
            return rec
        self.wait(lambda s: any(str(b.get("text")) in ("Save & Quit", "Quit") for b in s.get("buttons") or []), 3.0)
        texts = [str(b.get("text")) for b in self.buttons()]
        rec["dialog_buttons"] = texts
        n0 = len(self.saved_msgs())
        if prefer_save and "Save & Quit" in texts:
            rec["choice"] = "Save & Quit"
        elif "Quit without saving" in texts and not prefer_save:
            rec["choice"] = "Quit without saving"
        else:
            rec["choice"] = "Quit"
        self.click_button(rec["choice"], exact=True, timeout=3.0)
        rec["exited"] = self.g.wait_exit(25.0)
        rec["saved_msg"] = len(self.saved_msgs()) > n0
        return rec


def launch(phase: str, name: str, save_dir: Path, out: Path, seed=None, max_seconds: int = 1200) -> tuple[Game, P]:
    g = Game(phase, name, save_dir, max_seconds=max_seconds, seed=seed)
    g.start()
    p = P(g, out)
    return g, p


def title_state(p: P, timeout: float = 120.0) -> dict:
    s = p.wait(lambda s: s.get("mode") == "title" and len(s.get("buttons") or []) > 0, timeout)
    if not s:
        return {"title": False}
    time.sleep(1.2)          # the Continue line is refreshed on the title's ready; the button scan runs every 0.2 s
    s = p.st()
    bs = [{"text": b.get("text"), "disabled": bool(b.get("disabled"))} for b in s.get("buttons") or []]
    cont = next((b for b in bs if b["text"] == "Continue"), None)
    return {"title": True, "buttons": bs, "continue": cont}


def continue_game(p: P, timeout: float = 120.0) -> dict:
    t0 = time.time()
    ok = p.click_button("Continue", exact=True, timeout=10.0)
    s = p.wait(lambda s: s.get("mode") == "playing" and s.get("player"), timeout) if ok else None
    rec = {"clicked": ok, "playing": bool(s), "seconds": round(time.time() - t0, 1)}
    if s:
        time.sleep(2.0)
        o = p.observe()
        rec.update({"area": o["area"], "zone": o["zone"], "pos": o["pos"], "hp": o["hp"]})
        rec["backup_notices"] = len(p.notices("previous save was restored"))
    return rec


# ============================================================================================ phase: velour
class Result:
    def __init__(self, phase: str):
        self.phase = phase
        self.dir = RUN / phase
        self.dir.mkdir(parents=True, exist_ok=True)
        self.data: dict = {"phase": phase, "started": now(), "checks": [], "notes": [], "bugs": []}
        self.t0 = time.time()

    def check(self, name: str, ok: bool | None, expected: str, observed, evidence=None, kind: str = "natural"):
        row = {"check": name, "result": "PASS" if ok else ("FAIL" if ok is False else "INFO"), "kind": kind,
               "expected": expected, "observed": observed, "evidence": evidence or []}
        self.data["checks"].append(row)
        print(f"[{time.strftime('%H:%M:%S')}] {self.phase} CHECK {row['result']}: {name} - {str(observed)[:300]}", flush=True)
        self.save()
        return ok

    def note(self, text: str):
        self.data["notes"].append(text)
        print(f"[{time.strftime('%H:%M:%S')}] {self.phase} NOTE {text[:300]}", flush=True)
        self.save()

    def bug(self, title: str, severity: str, steps: str, expected: str, actual: str, evidence):
        self.data["bugs"].append({"title": title, "severity": severity, "steps": steps, "expected": expected,
                                  "actual": actual, "evidence": evidence})
        print(f"[{time.strftime('%H:%M:%S')}] {self.phase} BUG [{severity}] {title}", flush=True)
        self.save()

    def save(self):
        self.data["seconds"] = round(time.time() - self.t0, 1)
        write_json(self.dir / "result.json", self.data)


def snapshot(res: Result, save_dir: Path, label: str) -> str:
    dst = res.dir / "snapshots" / label
    copy_saves(save_dir, dst)
    return str(dst)


def s3_segment_class():
    """S3's Segment with the chain's adaptations (1080p-safe calibration, backpack eating)."""
    import s3_manor as S3
    import s2_lib
    from s1_common import angle_diff

    class CovS3(S3.Segment):
        def calibrate(self) -> bool:
            for amt in (0.25, 0.5, 1.0, 2.0, 4.0, 8.0):
                self.wait_frames(2)
                y0 = self.bot.cam_yaw()
                if y0 is None:
                    time.sleep(0.3)
                    continue
                self.bot.win.mouse_move(amt, 0)
                self.wait_frames(3)
                y1 = self.bot.cam_yaw()
                if y1 is None:
                    continue
                d = angle_diff(y1, y0)
                if 3.0 <= abs(d) <= 150.0:
                    self.ppd = amt / abs(d)
                    self.look_inv = -1.0 if d > 0 else 1.0
                    self.log(f"calibrated: {self.ppd:.4f} px/deg (motion {amt} -> {d:.1f} deg) invert={self.look_inv}")
                    return True
            self.problem("bot", "look calibration failed")
            return False

        def eat(self) -> bool:
            if getattr(self, "no_eat", False):
                return False
            if super().eat():
                return True
            if not hasattr(self, "_bag"):
                self._bag = s2_lib.Play(self.bot, self.out)
            ok = self._bag.eat_best(foods=FOOD)
            if ok:
                self.fight["eats"] += 1
            return ok

    return S3, CovS3


def find_boss(s: dict):
    b = s.get("boss")
    if b:
        return b
    return next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "phase" in e), None)


def stand_until_dead(p: P, where: str, spot=None, timeout: float = 360.0) -> dict:
    """Deliberate defeat: stand (optionally on `spot`) without attacking, dodging or eating until Krystal falls."""
    d0 = p.deaths()
    t0 = time.time()
    hp_trace = []
    last = 0.0
    boss_at_death = None
    while time.time() - t0 < timeout:
        s = p.st()
        if p.deaths() > d0:
            break
        if s.get("mode") == "dead":
            time.sleep(0.2)
            continue
        if s.get("ui_stack"):
            p.close_panels()
        if spot is not None and s.get("mode") == "playing" and dist2(xz(p.pos()), xz(spot)) > 2.5:
            p.goto((spot[0], spot[-1]), tol=1.0, sprint=True, timeout=6)
        b = find_boss(s)
        if b is not None:
            boss_at_death = {k: b.get(k) for k in ("name", "state", "hp", "max_hp", "phase")}
        if time.time() - last > 3.0:
            last = time.time()
            hp_trace.append([round(time.time() - t0, 1), p.hp(), boss_at_death and boss_at_death.get("state"),
                             boss_at_death and boss_at_death.get("hp")])
        time.sleep(0.25)
    died = p.deaths() > d0
    rec = {"where": where, "died": died, "seconds": round(time.time() - t0, 1), "hp_trace": hp_trace,
           "boss_before_fall": boss_at_death}
    p.wait(lambda s: s.get("mode") == "playing" and float((s.get("player") or {}).get("hp", 0)) > 0
           and not s.get("ui_stack"), 60)
    time.sleep(3.0)
    s = p.st()
    b = find_boss(s)
    rec["after"] = {"area": s.get("area"), "zone": s.get("zone"), "pos": (s.get("player") or {}).get("pos"),
                    "hp": (s.get("player") or {}).get("hp"),
                    "notices": [m.get("text") for m in p.all_msgs[-12:] if m.get("k") in ("notify", "event")],
                    "boss": b and {k: b.get(k) for k in ("name", "state", "hp", "max_hp", "phase", "pos", "dist")}}
    return rec


def no_dup(diff: dict) -> bool:
    return (not diff["ledger_added"] and not diff["ledger_time_changed"] and not diff["keys_delta"]
            and not {i: n for i, n in diff["items_delta"].items() if n > 0})


# ============================================================================================ phase: velour
def phase_velour(a) -> dict:
    res = Result("velour")
    out = res.dir
    saves = out / "saves"
    src = CHAIN / "run3" / "checkpoints" / "T23_end"
    copy_saves(src, saves)
    res.data["start"] = f"NATURAL: copy of {src} (the natural chain's save at the T23 boundary: Commons arch, manor not visited)"
    start_save = load_save(saves / "slot1.json")
    S3, CovS3 = s3_segment_class()
    g, p = launch("velour", "v1", saves, out, seed=a.seed, max_seconds=2400)
    try:
        ts = title_state(p)
        cg = continue_game(p)
        res.check("continue_from_T23_end", cg.get("area") == REACH, "Continue lands in the Reach", {"title": ts, "continue": cg})
        p.bot.calibrate_look()
        # the road from the Commons to the manor arch (chain T23 road_to_manor)
        pts = [(1.5, 70.0), (2.5, 68.0), (2.5, 53.0), (0.0, 45.0), (0.0, 38.5), (0.0, 30.0), (0.0, 22.0),
               (-8.0, 12.0), (-9.0, 2.0), (0.5, -8.0), (0.5, -12.0), (2.5, -24.0), (5.0, -34.0), (8.1, -44.3),
               (10.0, -50.0), (10.9, -52.8)]
        here = xz(p.pos())
        i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
        if not p.route(pts[i:], tol=1.8, sprint=True, fight=True):
            raise StepFailed(f"road to the manor arch blocked at {p.pos()}")
        seg = CovS3(p.bot, out / "s3", optional=False, time_budget=2000.0, tether="pool")
        for name, fn in (("start", seg.s_start), ("arch", seg.s_arch), ("enter", seg.s_enter), ("hall", seg.s_hall),
                         ("puzzle", seg.s_puzzle), ("rest_ballroom", seg.s_rest_ballroom)):
            seg.checkpoint(name, fn, True)
        time.sleep(1.0)
        pre_fight_dir = snapshot(res, saves, "pre_fight_ballroom_rest")
        pre = load_save(saves / "slot1.json")
        pl = pre["state"]["player"]
        res.note(f"ballroom rest save: spawn={pl.get('spawn')} respawn={pl.get('respawn_area')}/{pl.get('respawn_spawn')} "
                 f"deaths={(pre['state'].get('stats') or {}).get('deaths')}")
        seg.checkpoint("gallery", seg.s_gallery, True)
        # --- die once on purpose
        seg.no_eat = True
        rec = stand_until_dead(p, "Count Velour's gallery (phase 1 spot)", spot=(-2.2, 0.0, -62.3), timeout=420)
        seg.no_eat = False
        res.data["death"] = rec
        after = rec["after"]
        cp_dist = dist2(xz(after["pos"]), (7.0, -33.2)) if after.get("pos") else None
        res.check("velour_death_happened", rec["died"], "standing still in the fight, Krystal falls",
                  {"seconds": rec["seconds"], "boss_before_fall": rec["boss_before_fall"], "hp_trace": rec["hp_trace"][-6:]})
        res.check("velour_respawn_at_ballroom_candles", after.get("area") == MANOR and cp_dist is not None and cp_dist < 4.0,
                  "wakes in the manor at the ballroom rest candles (the last checkpoint), full health",
                  {"area": after.get("area"), "pos": after.get("pos"), "dist_to_candles": cp_dist, "hp": after.get("hp"),
                   "notices": after.get("notices")})
        res.data["save_after_death"] = {"main_unchanged_since_ballroom_rest": sha(saves / "slot1.json") == sha(Path(pre_fight_dir) / "slot1.json")}
        # walk back and look at the Count before the retry: does the encounter reset?
        seg.route(list(S3.FROM_BALLROOM_CP_TO_GALLERY), tol=0.9)
        time.sleep(1.5)
        v = seg.velour()
        s = p.st()
        res.data["velour_after_fall"] = {"telemetry_boss": s.get("boss"), "nearby_velour": v,
                                         "dark_candles": seg.dark_candles(),
                                         "flag_defeated": "ch2_velour_defeated" in s.get("flags", [])}
        full = v is None or float(v.get("hp", 0) or 0) >= float(v.get("max_hp") or v.get("hp") or 0)
        res.check("velour_resets_after_fall", full and "ch2_velour_defeated" not in s.get("flags", []),
                  "after the fall the Count is back to his start (dormant / full hp), not defeated", res.data["velour_after_fall"])
        # --- retry and win (boss_fight relights the teaching candle when he is dormant)
        won = seg.boss_fight(timeout=700)
        res.data["fight"] = seg.fight
        res.check("velour_won_after_retry", won, "the retry ends with ch2_velour_defeated",
                  {k: seg.fight.get(k) for k in ("deaths", "hp_min", "eats", "dodges", "phase_seen", "encounter_starts")})
        if not won:
            raise StepFailed("Velour not defeated")
        seg.checkpoint("lantern", seg.s_lantern, True)
        seg.checkpoint("rest_balcony", seg.s_rest_balcony, False)
        time.sleep(1.0)
        post_dir = snapshot(res, saves, "post_win_balcony")
        post = load_save(saves / "slot1.json")
        d_fight = ledger_diff(pre, post)
        d_run = ledger_diff(start_save, post)
        base_a = load_save(CHAIN / "run3" / "checkpoints" / "T23_end" / "slot1.json")
        base_b = load_save(CHAIN / "run3" / "checkpoints" / "S3_end" / "slot1.bak.json")   # its balcony rest save
        d_base = ledger_diff(base_a, base_b)
        res.data["ledger"] = {"pre_fight_to_post_win": d_fight, "start_to_post_win": d_run,
                              "baseline_chain_run3_T23_end_to_balcony_rest_no_death": d_base}
        seal = int(d_run["items_delta"].get("manor_seal", 0)) + int(d_run["keys_delta"].get("manor_seal", 0))
        res.check("velour_rewards_once", "rw_ch2_manor" in d_run["ledger_added"] and not d_run["ledger_removed"]
                  and not d_run["ledger_time_changed"] and seal == 1,
                  "rw_ch2_manor added once, Manor Seal +1, no ledger entry re-stamped (compare: the no-death baseline)",
                  {"this_run": {k: d_run[k] for k in ("ledger_added", "ledger_time_changed", "items_delta", "keys_delta", "deaths")},
                   "baseline": {k: d_base[k] for k in ("ledger_added", "items_delta", "keys_delta", "deaths")}},
                  evidence=[pre_fight_dir, post_dir])
        # --- save -> quit -> relaunch -> Continue twice: nothing granted again
        q = p.quit_via_menu(prefer_save=True)
        g.stop()
        reloads = []
        for k in range(2):
            g, p = launch("velour", f"v{k + 2}", saves, out, seed=a.seed, max_seconds=600)
            ts = title_state(p)
            cg = continue_game(p)
            p.bot.calibrate_look()
            ps = p.pause_save()
            time.sleep(0.5)
            cur = load_save(saves / "slot1.json")
            dd = ledger_diff(post, cur)
            reloads.append({"title_continue": ts.get("continue"), "continue": cg, "pause_save": ps,
                            "diff_vs_post_win": {k2: dd[k2] for k2 in ("ledger_added", "ledger_removed", "ledger_time_changed",
                                                                         "items_delta", "keys_delta", "flags_removed")}})
            if k == 0:
                p.quit_via_menu(prefer_save=True)
            g.stop()
        res.data["reloads"] = reloads
        res.check("velour_no_duplicate_after_reloads", all(no_dup(r["diff_vs_post_win"]) for r in reloads),
                  "two relaunch + Continue + save cycles add nothing to the ledger, items or keys", {"quit": q, "reloads": reloads})
    except Exception as e:  # noqa: BLE001
        res.note(f"phase stopped: {type(e).__name__}: {e}")
        res.data["traceback"] = traceback.format_exc()
    finally:
        g.stop()
        res.data["script_errors"] = g.log_errors()
        res.save()
    return res.data


# ============================================================================================ phase: crossing
def phase_crossing(a) -> dict:
    res = Result("crossing")
    out = res.dir
    saves = out / "saves"
    src = CHAIN / "run3" / "s4" / "checkpoints" / "winch"
    copy_saves(src, saves)
    res.data["start"] = (f"NATURAL: copy of {src} (the natural chain's game-written save at the crossing_gate lantern, "
                         "just before the Weaver's Crossing)")
    pre = load_save(saves / "slot1.json")
    g, p = launch("crossing", "c1", saves, out, seed=a.seed, max_seconds=2000)
    try:
        ts = title_state(p)
        cg = continue_game(p)
        res.check("continue_at_crossing_gate", cg.get("area") == WORKS, "Continue lands in the Works at the crossing_gate lantern",
                  {"title": ts, "continue": cg})
        R4.step_start(p)
        p.lantern(True)
        # --- die once on the bridge
        p.nav((74.5, -18.0, 0.0), fight=False)
        rec = stand_until_dead(p, "Weaver's Crossing bridge", spot=(76.0, -18.0, 0.0), timeout=420)
        res.data["death"] = rec
        after = rec["after"]
        gate_d = dist2(xz(after["pos"]), (65.2, -0.3)) if after.get("pos") else None
        res.check("crossing_death_happened", rec["died"], "standing still on the bridge, Krystal falls",
                  {"seconds": rec["seconds"], "boss_before_fall": rec["boss_before_fall"], "hp_trace": rec["hp_trace"][-6:]})
        res.check("crossing_respawn_at_gate", after.get("area") == WORKS and gate_d is not None and gate_d < 4.0,
                  "wakes at the crossing_gate lantern (the last checkpoint), full health",
                  {"pos": after.get("pos"), "dist_to_gate": gate_d, "hp": after.get("hp"), "notices": after.get("notices")})
        p.nav((72.0, -18.0, 0.0), fight=False)
        time.sleep(1.5)
        s = p.st()
        b = find_boss(s)
        res.data["matron_after_fall"] = b
        res.check("crossing_resets_after_fall", b is None or float(b.get("hp", 0) or 0) >= float(b.get("max_hp") or b.get("hp") or 0),
                  "after the fall the Matron is back at full health (reset)", b)
        cleared_before = "ch2_crossing_cleared" in s.get("flags", [])
        won = R4.step_crossing(p)
        arena_save = load_save(saves / "slot1.json")
        res.data["arena_save_at_win"] = {"ledger_has_crossing": "rw_ch2_crossing" in (arena_save["state"].get("ledger") or {}),
                                         "ledger_has_step_reward": "rw_ch2_weaver_crossing" in (arena_save["state"].get("ledger") or {}),
                                         "cleared_flag": "ch2_crossing_cleared" in arena_save["state"].get("flags", [])}
        res.check("crossing_won_after_retry", bool(won) and not cleared_before, "the retry clears the crossing",
                  {"won": won, "problems": p.problems[-5:]})
        time.sleep(2.0)
        p.nav((65.2, -18.0, -0.3), fight=False, final_tol=0.6)
        rested = p.rest_lantern((65.6, -18.0, -1.75), stand=(65.2, -18.0, -0.3))
        time.sleep(1.0)
        post_dir = snapshot(res, saves, "post_win_gate_rest")
        post = load_save(saves / "slot1.json")
        d = ledger_diff(pre, post)
        # the chain's arena save is written in the same frame BEFORE the step reward; its next save (bell_throat) holds it
        base = ledger_diff(load_save(CHAIN / "run3" / "s4" / "checkpoints" / "winch" / "slot1.json"),
                           load_save(CHAIN / "run3" / "s4" / "checkpoints" / "bell_throat" / "slot1.json"))
        res.data["ledger"] = {"winch_save_to_post_win": d, "baseline_chain_run3_winch_to_crossing_no_death": base,
                              "rested_after_win": rested}
        b_set, _ = rewards_at_stamp(load_save(CHAIN / "run3" / "s4" / "checkpoints" / "bell_throat" / "slot1.json"), "rw_ch2_crossing")
        m_set, _ = rewards_at_stamp(post, "rw_ch2_crossing")
        res.check("crossing_rewards_once", {"rw_ch2_crossing", "rw_ch2_weaver_crossing"} <= set(d["ledger_added"])
                  and not d["ledger_time_changed"] and not d["ledger_removed"] and d["items_delta"].get("thread_veil", 0) == 1
                  and b_set == m_set,
                  "rw_ch2_crossing + the step reward rw_ch2_weaver_crossing once, Thread Veil +1; the same ledger additions as "
                  "the no-death baseline (chain run3: winch save -> the next save that holds the step reward, bell_throat)",
                  {"this_run": {k: d[k] for k in ("ledger_added", "ledger_time_changed", "items_delta", "keys_delta", "deaths")},
                   "baseline": {k: base[k] for k in ("ledger_added", "items_delta", "keys_delta", "deaths")}},
                  evidence=[post_dir])
        q = p.quit_via_menu(prefer_save=True)
        g.stop()
        reloads = []
        for k in range(2):
            g, p = launch("crossing", f"c{k + 2}", saves, out, seed=a.seed, max_seconds=600)
            ts = title_state(p)
            cg = continue_game(p)
            time.sleep(1.0)
            p.bot.calibrate_look()
            p.rest_lantern((65.6, -18.0, -1.75), stand=(65.2, -18.0, -0.3))
            time.sleep(0.5)
            cur = load_save(saves / "slot1.json")
            dd = ledger_diff(post, cur)
            s = p.st()
            b = next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "matron" in str(e.get("name", "")).lower()), None)
            reloads.append({"continue": cg, "matron_present": b,
                            "diff_vs_post_win": {k2: dd[k2] for k2 in ("ledger_added", "ledger_removed", "ledger_time_changed",
                                                                         "items_delta", "keys_delta", "flags_removed")}})
            if k == 0:
                p.quit_via_menu(prefer_save=True)
            g.stop()
        res.data["reloads"] = reloads
        res.check("crossing_no_duplicate_after_reloads", all(no_dup(r["diff_vs_post_win"]) and not r["matron_present"] for r in reloads),
                  "two relaunch + Continue + rest cycles: nothing added to the ledger / items / keys, the Matron stays gone",
                  {"quit": q, "reloads": reloads})
    except Exception as e:  # noqa: BLE001
        res.note(f"phase stopped: {type(e).__name__}: {e}")
        res.data["traceback"] = traceback.format_exc()
    finally:
        g.stop()
        res.data["script_errors"] = g.log_errors()
        res.save()
    return res.data


# ============================================================================================ kill during saves
def summarize_files(fs: dict) -> dict:
    out = {}
    for name, st in fs.items():
        if "/" in name:
            out[name] = {"sha256": st.get("sha256", "")[:16], "size": st.get("size")}
            continue
        out[name] = {k: st.get(k) for k in ("status", "version", "size", "saved_unix", "area") if st.get(k) is not None}
        if st.get("sha256"):
            out[name]["sha256"] = st["sha256"][:16]
        if st.get("pos"):
            out[name]["pos"] = [round(float(v), 2) for v in st["pos"]]
    return out


def match_loaded(cg: dict, files: dict) -> dict:
    """Which of the complete files did Continue load? (area + xz position of Krystal right after the load)."""
    if not cg.get("playing") or not cg.get("pos"):
        return {"source": None}
    best = None
    for key, name in (("main", "slot1.json"), ("tmp", "slot1.tmp"), ("bak", "slot1.bak.json")):
        f = files.get(name) or {}
        if f.get("status") != "ok" or not f.get("pos"):
            continue
        d = dist2(xz(cg["pos"]), xz(f["pos"])) + (0.0 if f.get("area") == cg.get("area") else 1000.0)
        if best is None or d < best[0]:
            best = (d, key)
    if best is None:
        return {"source": None}
    # ambiguous when another candidate is as close
    amb = []
    for key, name in (("main", "slot1.json"), ("tmp", "slot1.tmp"), ("bak", "slot1.bak.json")):
        f = files.get(name) or {}
        if key != best[1] and f.get("status") == "ok" and f.get("pos") and f.get("area") == cg.get("area") \
                and abs(dist2(xz(cg["pos"]), xz(f["pos"])) - best[0]) < 0.3:
            amb.append(key)
    return {"source": best[1], "dist": round(best[0], 3), "ambiguous_with": amb}


def hop(p: P, rng: random.Random, center=None, radius: float = 5.0) -> None:
    """A short walk (so the next save's position differs from the previous one)."""
    me = p.pos()
    c = center or (me[0], me[2])
    for _ in range(4):
        ang = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(1.5, radius)
        tgt = (c[0] + math.cos(ang) * r, c[1] + math.sin(ang) * r)
        if dist2(tgt, xz(me)) > 1.2:
            break
    p.goto(tgt, tol=0.8, sprint=False, timeout=8)
    time.sleep(0.4)


def raw_click(g: Game, b: dict, cid: int = 900001) -> float:
    """Sends a click command WITHOUT waiting for the reply (the kill may come before it). Returns the send time."""
    r = b.get("rf") or b.get("rect")
    x, y, w, h = [float(v) for v in r]
    line = json.dumps({"click": [round(x + w / 2.0, 4), round(y + h / 2.0, 4)], "button": "left", "id": cid}) + "\n"
    t = time.perf_counter()
    g.vin.sock.sendall(line.encode("utf-8"))
    return t


def stat_sig(p: Path):
    try:
        st = os.stat(p)
        return (st.st_mtime_ns, st.st_size, st.st_ino)
    except OSError:
        return None


def fire_and_kill(g: Game, b: dict, save_dir: Path, mode: str, delay_ms: float, poll_timeout: float = 15.0,
                  kill: bool = True) -> dict:
    """Clicks `b` (Save Game / Save & Quit / a Lantern Road destination) and hard-kills the game's Godot process:
    mode "tmp": as soon as slot1.tmp is (re)written + delay_ms; mode "blind": delay_ms after sending the click.
    kill=False only measures the write window (tmp seen -> main replaced)."""
    tmp = save_dir / "slot1.tmp"
    main = save_dir / "slot1.json"
    h_child = ProcHandle(g.child) if g.child else None
    tmp0, main0 = stat_sig(tmp), stat_sig(main)
    t_send = raw_click(g, b)
    t_tmp = t_main = None
    trig = "timeout"
    deadline = t_send + poll_timeout
    if mode == "tmp" or not kill:
        while time.perf_counter() < deadline:
            s1 = stat_sig(tmp)
            if t_tmp is None and s1 is not None and s1 != tmp0:
                t_tmp = time.perf_counter()
                trig = "tmp"
                if kill:
                    break
            m1 = stat_sig(main)
            if m1 != main0:
                t_main = time.perf_counter()
                if trig == "timeout":
                    trig = "main_replaced (temp never seen)"
                break
        base = t_tmp if t_tmp is not None else (t_main if t_main is not None else time.perf_counter())
    else:
        base = t_send
        trig = "blind"
    rec = {"mode": mode, "delay_ms": round(delay_ms, 2), "trigger": trig,
           "tmp_seen_ms": None if t_tmp is None else round((t_tmp - t_send) * 1000, 2),
           "main_replaced_ms": None if t_main is None else round((t_main - t_send) * 1000, 2)}
    if not kill:
        return rec
    target = base + delay_ms / 1000.0
    while time.perf_counter() < target:
        pass
    t_kill = time.perf_counter()
    ok = h_child.terminate() if h_child else False
    rec["kill_ms_after_send"] = round((t_kill - t_send) * 1000, 2)
    rec["terminated_child"] = ok
    if h_child:
        rec["child_gone"] = h_child.wait(5000)
        h_child.close()
    rec["wrapper_exited"] = g.wait_exit(10.0)
    return rec


def classify_kill(files: dict, s1_sha: str) -> str:
    m, t, b = files.get("slot1.json", {"status": "missing"}), files.get("slot1.tmp", {"status": "missing"}), \
        files.get("slot1.bak.json", {"status": "missing"})
    if t["status"] == "corrupt":
        return "torn temp file (killed while the temp file was being written)"
    if t["status"] == "ok" and m["status"] == "missing":
        return "complete temp, no main (killed between rotating the backup and renaming the temp)"
    if t["status"] == "ok" and b["status"] == "missing":
        return "complete temp, no backup (killed between deleting the old backup and rotating)"
    if t["status"] == "ok":
        return "complete temp beside the old main (killed after writing/validating, before the rotation)"
    if m.get("sha256") == s1_sha:
        return "main unchanged, no temp (killed before the temp file was created)"
    return "save completed before the kill (new main, no temp)"


def verify_launch(res: Result, phase: str, name: str, saves: Path, check_prefix: str, kind: str = "natural") -> tuple:
    """Launch + title + Continue on the current save folder and check the load against the python replica."""
    before = folder_state(saves)
    exp = expected_load(saves)
    g, p = launch(phase, name, saves, res.dir, max_seconds=400)
    ts = title_state(p)
    cont = ts.get("continue") or {}
    rec = {"files_before_launch": summarize_files(before), "expected_source": exp["source"],
           "title_continue": cont}
    loadable = exp["source"] in ("main", "tmp", "bak")
    if loadable:
        cg = continue_game(p)
        rec["continue"] = cg
        m = match_loaded(cg, before)
        rec["loaded"] = m
        after = folder_state(saves)
        rec["files_after_load"] = summarize_files(after)
        notice = cg.get("backup_notices", 0) > 0
        ok_src = m.get("source") == exp["source"] or (exp["source"] in m.get("ambiguous_with", []))
        ok_notice = notice == (exp["source"] == "bak")
        tmp_left = "slot1.tmp" in after
        ok_files = True
        if exp["source"] == "tmp":
            ok_files = after.get("slot1.json", {}).get("sha256") == before.get("slot1.tmp", {}).get("sha256") and not tmp_left
        elif exp["source"] == "main":
            ok_files = not tmp_left
        rec["ok"] = bool(cont) and not cont.get("disabled") and cg.get("playing") and ok_src and ok_notice and ok_files
        res.check(f"{check_prefix}_continue", rec["ok"],
                  f"Continue enabled and loads the {exp['source']} save (python replica of _best_available); backup notice "
                  f"{'shown' if exp['source'] == 'bak' else 'not shown'}; no temp file left / temp promoted",
                  {"expected": exp["source"], "loaded": m, "notice_msgs": cg.get("backup_notices"), "area": cg.get("area"),
                   "pos": cg.get("pos"), "title_continue": cont, "tmp_left": tmp_left, "files_ok": ok_files}, kind=kind)
    else:
        rec["ok"] = not cont or cont.get("disabled")
        res.check(f"{check_prefix}_no_continue", rec["ok"], "nothing loadable: no (enabled) Continue",
                  {"expected": exp["source"], "title": ts}, kind=kind)
    return g, p, rec


def phase_kill(a) -> dict:
    res = Result("kill")
    saves = res.dir / "saves"
    src = CHAIN / "run3" / "checkpoints" / "END_end"
    copy_saves(src, saves)
    res.data["start"] = f"NATURAL: copy of {src} (the natural chain's final save: free play at the Haven)"
    rng = random.Random(a.seed if a.seed is not None else 4)
    n = a.attempts
    plan = []
    for i in range(n):
        # measured on the first runs: the temp file appears ~60 ms after the click is sent and the main file is
        # replaced ~5-7 ms later, so "tmp" delays of 0-7.5 ms land inside the write / validate / rotate / rename window
        # and "blind" delays of 45-85 ms land before, inside or just after it.
        if i % 6 == 4:
            plan.append({"trigger": "save_and_quit", "mode": "tmp", "delay_ms": rng.uniform(0.0, 7.5)})
        elif i % 6 == 5:
            plan.append({"trigger": "lantern_road", "mode": "tmp", "delay_ms": rng.uniform(0.0, 7.5)})
        elif i % 2 == 0:
            plan.append({"trigger": "pause_save", "mode": "tmp", "delay_ms": rng.uniform(0.0, 7.5)})
        else:
            plan.append({"trigger": "pause_save", "mode": "blind", "delay_ms": rng.uniform(45.0, 85.0)})
    res.data["plan"] = plan
    attempts = []
    res.data["attempts"] = attempts
    g = None
    for i in range(n + 1):
        att = {"i": i}
        attempts.append(att)
        try:
            g, p, vr = verify_launch(res, "kill", f"k{i:02d}", saves, f"kill{i:02d}_next_launch")
            att["verify"] = vr
            if i == n:
                break
            att.update(plan[i])
            if not vr.get("continue", {}).get("playing"):
                att["skipped"] = "Continue did not reach gameplay"
                g.stop()
                continue
            p.bot.calibrate_look()
            area = p.area()
            center = (0.0, 7.0) if area == SURFACE else None
            hop(p, rng, center=center)
            # save #1: completes (the write window is measured on it)
            if not p.open_pause():
                raise StepFailed("pause menu did not open")
            p.wait(lambda s: any(str(b.get("text")) == "Save Game" for b in s.get("buttons") or []), 2.0)
            b = p.save_button()
            if b is None or b.get("disabled"):
                raise StepFailed(f"Save Game unavailable: {b}")
            n0 = len(p.saved_msgs())
            win = fire_and_kill(g, b, saves, "tmp", 0.0, poll_timeout=5.0, kill=False)
            p.wait(lambda s: len([m for m in p.all_msgs if m.get("k") == "saved"]) > n0, 6.0)
            # the reply of the raw click arrives later: resync the command stream with a ping
            try:
                g.vin.request({"ping": True})
            except VirtualInputError:
                pass
            att["save1_window"] = win
            time.sleep(0.3)
            s1 = read_status(saves / "slot1.json")
            att["save1"] = {"sha256": s1.get("sha256", "")[:16], "pos": s1.get("pos"), "area": s1.get("area")}
            p.close_panels()
            hop(p, rng, center=center)
            trig = plan[i]["trigger"]
            if trig == "pause_save":
                p.open_pause()
                p.wait(lambda s: any(str(b.get("text")) == "Save Game" for b in s.get("buttons") or []), 2.0)
                b = p.save_button()
            elif trig == "save_and_quit":
                p.open_pause()
                p.click_button("Quit Game", exact=True, timeout=3.0)
                p.wait(lambda s: any(str(b.get("text")) == "Save & Quit" for b in s.get("buttons") or []), 3.0)
                b = next((x for x in p.buttons() if str(x.get("text")) == "Save & Quit"), None)
            else:
                b = open_lantern_road(p)
            if b is None:
                raise StepFailed(f"no button to fire for {trig}; buttons {[x.get('text') for x in p.buttons()]}")
            att["target_button"] = b.get("text")
            k = fire_and_kill(g, b, saves, plan[i]["mode"], plan[i]["delay_ms"], poll_timeout=20.0)
            att["kill"] = k
            g.stop()
            files = folder_state(saves)
            att["after_kill"] = summarize_files(files)
            att["classification"] = classify_kill(files, s1.get("sha256", ""))
            res.note(f"attempt {i}: {trig}/{plan[i]['mode']} delay {plan[i]['delay_ms']:.1f} ms -> {att['classification']} "
                     f"(tmp seen {k.get('tmp_seen_ms')} ms, killed {k.get('kill_ms_after_send')} ms after the click)")
        except Exception as e:  # noqa: BLE001
            att["error"] = f"{type(e).__name__}: {e}"
            att["traceback"] = traceback.format_exc()
            res.note(f"attempt {i} error: {e}")
        finally:
            if g is not None:
                g.stop()
            res.save()
    # summary
    kinds: dict = {}
    for at in attempts:
        c = at.get("classification")
        if c:
            kinds[c] = kinds.get(c, 0) + 1
    verified = [at for at in attempts[1:] if at.get("verify")]
    res.data["summary"] = {"kills": sum(1 for at in attempts if at.get("kill")), "classifications": kinds,
                           "next_launch_ok": sum(1 for at in verified if at["verify"].get("ok")),
                           "next_launch_total": len(verified),
                           "sources_loaded": [at["verify"].get("expected_source") for at in verified],
                           "save_write_window_ms": [at.get("save1_window", {}).get("tmp_seen_ms") for at in attempts
                                                    if at.get("save1_window")],
                           "save_complete_ms": [at.get("save1_window", {}).get("main_replaced_ms") for at in attempts
                                                if at.get("save1_window")]}
    res.check("kill_loop_every_relaunch_loads", res.data["summary"]["next_launch_ok"] == len(verified) and len(verified) >= 20,
              ">= 20 kills during save writes; every next launch shows Continue and loads main / complete temp / backup "
              "(never nothing, never a partial), backup notice exactly when the backup was used", res.data["summary"])
    res.data["script_errors"] = [e for at in attempts for e in []]
    errs = []
    for f in sorted(res.dir.glob("k*_godot.log")):
        errs += [f"{f.name}: {e}" for e in Game("kill", f.stem.replace("_godot", ""), saves).log_errors()]
    res.data["script_errors"] = errs
    res.save()
    return res.data


def open_lantern_road(p: P):
    """Opens the Lantern Road list (the Ward Stone at home, the Commons arch in the Reach) and returns the destination
    button to click (the Commons from home, the Haven from the Reach)."""
    area = p.area()
    if area == SURFACE:
        e = p.nearest(lambda n: n.get("name") == "WardStone" or "ward stone" in str(n.get("text", "")).lower(), 60)
        if e is None:
            p.goto((0.0, 4.0), tol=2.5, timeout=20)
            e = p.nearest(lambda n: n.get("name") == "WardStone" or "ward stone" in str(n.get("text", "")).lower(), 60)
        if e is None:
            raise StepFailed("no Ward Stone")
        if not p.interact_with(e, [""], check=lambda: bool(p.find_button("Travel the Lantern Road")) or bool(p.ui()), stop=2.2):
            raise StepFailed("the Ward Stone menu did not open")
        p.click_button("Travel the Lantern Road", exact=True, timeout=4)
        dest = "Lanternwake Commons"
    else:
        arch = (0.0, 0.0, 78.0)
        p.nav((0.0, 0.0, 75.0), tol=1.6, final_tol=1.0)
        if not p.interact_with(arch, ["Travel the Lantern Road"], check=lambda: bool(p.ui()), stop=1.9):
            raise StepFailed(f"Commons arch: prompt={p.prompt()}")
        dest = "The Haven (home)"
    p.wait(lambda s: any(str(b.get("text")) == dest for b in s.get("buttons") or []), 4.0)
    return next((x for x in p.buttons() if str(x.get("text")) == dest), None)


# ============================================================================================ synthetic crash states
def phase_synth(a) -> dict:
    """DIAGNOSTIC: crash states written by this script from two game-written saves (older = the chain's S4_end backup,
    the Reach; newer = the chain's END_end main, the surface) - the windows a random kill rarely hits."""
    res = Result("synth")
    older = CHAIN / "run3" / "checkpoints" / "S4_end" / "slot1.bak.json"
    newer = CHAIN / "run3" / "checkpoints" / "END_end" / "slot1.json"
    pre_v2 = CHAIN / "run3" / "checkpoints" / "END_end" / "pre_v2_backup"
    raw_new = newer.read_bytes()
    torn = raw_new[: int(len(raw_new) * 0.45)]
    cases = [
        ("torn_tmp_beside_good_main", {"slot1.json": raw_new, "slot1.bak.json": older.read_bytes(), "slot1.tmp": torn}, "main"),
        ("complete_tmp_no_main", {"slot1.bak.json": older.read_bytes(), "slot1.tmp": raw_new}, "tmp"),
        ("torn_tmp_no_backup", {"slot1.json": raw_new, "slot1.tmp": torn}, "main"),
        ("torn_tmp_no_main", {"slot1.bak.json": older.read_bytes(), "slot1.tmp": torn}, "bak"),
        ("older_complete_tmp_no_main", {"slot1.bak.json": raw_new, "slot1.tmp": older.read_bytes()}, "bak"),
    ]
    res.data["start"] = f"DIAGNOSTIC synthetic file states from game-written saves: older={older}, newer={newer}"
    for name, files, want in cases:
        d = res.dir / name / "saves"
        if d.parent.exists():
            shutil.rmtree(d.parent)
        d.mkdir(parents=True)
        shutil.copytree(pre_v2, d / "pre_v2_backup")
        for fn, data in files.items():
            (d / fn).write_bytes(data)
        exp = expected_load(d)["source"]
        g = None
        try:
            g, p, rec = verify_launch(res, "synth", name, d, f"synth_{name}", kind="diagnostic")
            rec["designed_expectation"] = want
            if exp != want:
                res.note(f"{name}: python replica expects {exp}, the case was designed for {want}")
            res.data[name] = rec
        except Exception as e:  # noqa: BLE001
            res.note(f"{name} error: {e}")
        finally:
            if g is not None:
                g.stop()
    res.save()
    return res.data


# ============================================================================================ corrupt main
def make_two_saves(res: Result, saves: Path, name: str, rng: random.Random) -> dict:
    """Continue, save twice at two spots (main = second, backup = first), quit WITHOUT saving."""
    g, p = launch(res.phase, name, saves, res.dir, max_seconds=400)
    try:
        title_state(p)
        continue_game(p)
        p.bot.calibrate_look()
        hop(p, rng, center=(0.0, 7.0))
        s_a = p.pause_save()
        pos_a = read_status(saves / "slot1.json").get("pos")
        hop(p, rng, center=(0.0, 7.0))
        s_b = p.pause_save()
        pos_b = read_status(saves / "slot1.json").get("pos")
        q = p.quit_via_menu(prefer_save=False)
        return {"save_a": s_a, "pos_a": pos_a, "save_b": s_b, "pos_b": pos_b, "quit": q}
    finally:
        g.stop()


def phase_corrupt(a) -> dict:
    res = Result("corrupt")
    rng = random.Random(a.seed if a.seed is not None else 7)
    src = CHAIN / "run3" / "checkpoints" / "END_end"
    variants = [("truncated_half", lambda b: b[: len(b) // 2]), ("zero_bytes", lambda b: b""),
                ("json_not_a_save", lambda b: b'{"hello": "world"}'),
                ("garbage_bytes", lambda b: bytes(rng.randrange(256) for _ in range(4096)))]
    res.data["start"] = f"NATURAL saves written by the game (Continue from a copy of {src}, two pause-menu saves), then the main file damaged by this script"
    for vname, damage in variants:
        vd = res.dir / vname
        saves = vd / "saves"
        copy_saves(src, saves)
        g = None
        rec: dict = {}
        res.data[vname] = rec
        try:
            rec["setup"] = make_two_saves(res, saves, f"{vname}_setup", rng)
            good_bak = read_status(saves / "slot1.bak.json")
            raw = (saves / "slot1.json").read_bytes()
            bad = damage(raw)
            (saves / "slot1.json").write_bytes(bad)
            bad_sha = hashlib.sha256(bad).hexdigest()
            rec["damaged_main"] = {"size": len(bad), "sha256": bad_sha[:16]}
            g, p, vr = verify_launch(res, "corrupt", f"{vname}_relaunch", saves, f"corrupt_{vname}")
            rec["relaunch"] = vr
            files = folder_state(saves)
            kept = [n for n, st in files.items() if n.startswith("slot1.corrupt-") and st.get("sha256") == bad_sha]
            rec["corrupt_copies"] = [n for n in files if n.startswith("slot1.corrupt-")]
            res.check(f"corrupt_{vname}_preserved", len(kept) == 1 and "slot1.json" not in files,
                      "the damaged main is moved aside once as slot1.corrupt-<unix>.json, byte-identical; no slot1.json until the next save",
                      {"corrupt_files": rec["corrupt_copies"], "identical": kept, "main_present": "slot1.json" in files})
            # the next save: new main, the good backup stays, the corrupt copy stays
            ps = p.pause_save()
            files2 = folder_state(saves)
            rec["after_next_save"] = summarize_files(files2)
            res.check(f"corrupt_{vname}_next_save", ps.get("saved") and files2.get("slot1.json", {}).get("status") == "ok"
                      and files2.get("slot1.bak.json", {}).get("sha256") == good_bak.get("sha256")
                      and any(n.startswith("slot1.corrupt-") and st.get("sha256") == bad_sha for n, st in files2.items()),
                      "the next save writes a valid main; the good backup is not replaced by junk; the corrupt copy is kept",
                      {"pause_save": ps, "files": rec["after_next_save"]})
            p.quit_via_menu(prefer_save=False)
            g.stop()
            g, p, vr2 = verify_launch(res, "corrupt", f"{vname}_relaunch2", saves, f"corrupt_{vname}_second_launch")
            rec["relaunch2"] = vr2
        except Exception as e:  # noqa: BLE001
            res.note(f"{vname} error: {type(e).__name__}: {e}")
            rec["traceback"] = traceback.format_exc()
        finally:
            if g is not None:
                g.stop()
            res.save()
    # both files damaged: nothing to continue; nothing touched at the title
    vd = res.dir / "both_damaged"
    saves = vd / "saves"
    copy_saves(src, saves)
    (saves / "slot1.json").write_bytes(b"{\"format\": \"hollowhaven-save\", \"version\": 2, \"state\": ")
    (saves / "slot1.bak.json").write_bytes(b"")
    before = folder_state(saves)
    g, p = launch("corrupt", "both_damaged", saves, res.dir, max_seconds=200)
    try:
        ts = title_state(p)
        p.click_button("Quit", exact=True, timeout=4)
        g.wait_exit(15)
    finally:
        g.stop()
    after = folder_state(saves)
    same = {k: v.get("sha256") for k, v in before.items()} == {k: v.get("sha256") for k, v in after.items()}
    res.data["both_damaged"] = {"title": ts, "files_unchanged": same, "files": summarize_files(after)}
    res.check("corrupt_both_damaged", not ts.get("continue") and same,
              "main and backup both damaged: no Continue offered (nothing loadable), New Game available, files untouched at the title",
              res.data["both_damaged"])
    res.save()
    return res.data


# ============================================================================================ future version
def phase_future(a) -> dict:
    res = Result("future")
    src = CHAIN / "run3" / "checkpoints" / "END_end"
    cases = []
    # A: v3 main (+ a valid v2 backup)
    d = load_save(src / "slot1.json")
    d["version"] = 3
    v3_main = json.dumps(d, indent="\t").encode("utf-8")
    cases.append(("v3_main_valid_v2_backup", {"slot1.json": v3_main, "slot1.bak.json": (src / "slot1.bak.json").read_bytes()}))
    # B: torn main + v3 backup
    b = load_save(src / "slot1.bak.json")
    b["version"] = 3
    cases.append(("torn_main_v3_backup", {"slot1.json": (src / "slot1.json").read_bytes()[:5000],
                                          "slot1.bak.json": json.dumps(b, indent="\t").encode("utf-8")}))
    res.data["start"] = f"END_end save of the natural chain ({src}) with its version field set to 3 by this script (a newer game's save)"
    for name, files in cases:
        saves = res.dir / name / "saves"
        if saves.parent.exists():
            shutil.rmtree(saves.parent)
        saves.mkdir(parents=True)
        shutil.copytree(src / "pre_v2_backup", saves / "pre_v2_backup")
        for fn, data in files.items():
            (saves / fn).write_bytes(data)
        before = folder_state(saves)
        g, p = launch("future", name, saves, res.dir, max_seconds=200)
        rec = {}
        try:
            ts = title_state(p)
            rec["title"] = ts
            cont = ts.get("continue") or {}
            b = p.find_button("Continue") or next((x for x in p.buttons() if x.get("text") == "Continue"), None)
            if b is not None:
                r = b.get("rf") or b.get("rect")
                x, y, w, h = [float(v) for v in r]
                g.vin.click(x + w / 2.0, y + h / 2.0)          # a click on the disabled button
            time.sleep(4.0)
            s = p.st()
            rec["after_click"] = {"mode": s.get("mode"), "area": s.get("area"), "ui": s.get("ui_stack"),
                                  "messages": [m.get("text") for m in s.get("messages") or []]}
            p.click_button("Quit", exact=True, timeout=4)
            rec["exited_via_title_quit"] = g.wait_exit(15)
        finally:
            g.stop()
        after = folder_state(saves)
        same = {k: (v.get("sha256"), v.get("mtime")) for k, v in before.items()} == \
               {k: (v.get("sha256"), v.get("mtime")) for k, v in after.items()}
        rec["files_before"] = summarize_files(before)
        rec["files_after"] = summarize_files(after)
        rec["untouched"] = same
        res.data[name] = rec
        res.check(f"future_{name}", bool(cont) and cont.get("disabled") and rec["after_click"]["mode"] == "title" and same,
                  "Continue visible but disabled (refused, no fallback to an older file), clicking it stays on the title, "
                  "every file byte-identical with the same mtime, nothing moved or created", rec)
    res.save()
    return res.data


# ============================================================================================ pre_v2 backup
def phase_prev2(a) -> dict:
    res = Result("prev2")
    saves = res.dir / "saves"
    if saves.exists():
        shutil.rmtree(saves)
    saves.mkdir(parents=True)
    main_src = FIXTURES / "16_real_handoff_c1_complete.json"
    bak_src = FIXTURES / "16_real_handoff_c1_complete.bak.json"
    shutil.copyfile(main_src, saves / "slot1.json")
    shutil.copyfile(bak_src, saves / "slot1.bak.json")
    want = {"main": sha(main_src), "bak": sha(bak_src)}
    res.data["start"] = f"NATURAL: the real v1 Chapter-One-complete save (fixture 16, main + backup) in a fresh save folder"
    res.data["source_sha"] = want
    rng = random.Random(11)

    def backups() -> dict:
        d = saves / "pre_v2_backup"
        if not d.exists():
            return {}
        return {f.name: {"sha256": sha(f), "mtime": f.stat().st_mtime, "size": f.stat().st_size} for f in sorted(d.iterdir())}

    history = []
    g = None
    try:
        g, p = launch("prev2", "p1", saves, res.dir, max_seconds=400)
        ts = title_state(p)
        history.append({"when": "title (before Continue)", "backups": backups()})
        cg = continue_game(p)
        history.append({"when": "after Continue (v1 loaded, nothing saved yet)", "backups": backups(), "continue": cg,
                        "main_version": read_status(saves / "slot1.json").get("version")})
        p.bot.calibrate_look()
        for k in range(2):
            hop(p, rng, center=(0.0, 7.0))
            ps = p.pause_save()
            history.append({"when": f"after pause save {k + 1}", "backups": backups(), "save": ps,
                            "main_version": read_status(saves / "slot1.json").get("version"),
                            "bak_version": read_status(saves / "slot1.bak.json").get("version")})
        q = p.quit_via_menu(prefer_save=True)
        history.append({"when": "after Save & Quit", "backups": backups(), "quit": q})
        g.stop()
        for k in range(2):
            g, p = launch("prev2", f"p{k + 2}", saves, res.dir, max_seconds=300)
            title_state(p)
            cg = continue_game(p)
            p.bot.calibrate_look()
            hop(p, rng, center=(0.0, 7.0))
            ps = p.pause_save()
            q = p.quit_via_menu(prefer_save=True)
            history.append({"when": f"relaunch {k + 1}: Continue, save, Save & Quit", "backups": backups(), "continue": cg,
                            "save": ps, "quit": q})
            g.stop()
    except Exception as e:  # noqa: BLE001
        res.note(f"error: {type(e).__name__}: {e}")
        res.data["traceback"] = traceback.format_exc()
    finally:
        if g is not None:
            g.stop()
    res.data["history"] = history
    final = backups()
    mains = [n for n in final if n.startswith("slot1.v1-")]
    baks = [n for n in final if n.startswith("slot1.bak.v1-")]
    first = next((h["backups"] for h in history if h["backups"]), {})
    stable = all(h["backups"] == first for h in history if h["backups"])
    res.check("prev2_backup_once_byte_identical",
              len(mains) == 1 and len(baks) == 1 and final[mains[0]]["sha256"] == want["main"]
              and final[baks[0]]["sha256"] == want["bak"] and stable and len(final) == 2,
              "exactly one slot1.v1-<unix>.json (== the v1 main) and one slot1.bak.v1-<unix>.json (== the v1 backup), made "
              "at the first load, never rewritten (same sha / mtime) through 3 saves and 2 relaunches",
              {"final": final, "stable_across_history": stable, "made_at": next((h["when"] for h in history if h["backups"]), None)})
    res.save()
    return res.data


# ============================================================================================ every area type
class Areas:
    """save -> quit -> relaunch -> Continue in every area type, one continuous natural journey from END_end."""

    def __init__(self, a, phase: str = "areas"):
        self.res = Result(phase)
        self.saves = self.res.dir / "saves"
        self.rng = random.Random(a.seed if a.seed is not None else 5)
        self.n = 0
        self.g: Game | None = None
        self.p: P | None = None
        self.rows: list = []
        self.res.data["rows"] = self.rows

    def launch(self):
        self.n += 1
        self.g, self.p = launch(self.res.phase, f"a{self.n:02d}", self.saves, self.res.dir, max_seconds=1500)
        return self.p

    def seg(self):
        S3, CovS3 = s3_segment_class()
        s = CovS3(self.p.bot, self.res.dir / "s3", optional=False, time_budget=1500.0)
        s.calibrate()
        return S3, s

    def arrival(self) -> dict:
        time.sleep(1.5)
        o = self.p.observe()
        return {"area": o["area"], "zone": o["zone"], "pos": o["pos"]}

    def cycle(self, label: str, expect_area: str, rule: str, ref=None, tol: float = 0.6, use_pause: bool = True,
              prefer_save: bool = True, expect_resp=None) -> dict:
        """rule: "saved_pos" (outdoor: Continue restores the saved spot) or "spawn" (indoor: the arrival / checkpoint
        spawn at `ref`)."""
        res, p = self.res, self.p
        row = {"area_type": label, "rule": rule, "expected_area": expect_area}
        self.rows.append(row)
        try:
            o_before = p.observe()
            row["before"] = {k: o_before[k] for k in ("area", "zone", "pos", "hp")}
            if use_pause:
                row["pause_save"] = p.pause_save()
            else:
                p.open_pause()
                p.wait(lambda s: any(str(b.get("text")) == "Save Game" for b in s.get("buttons") or []), 2.0)
                b = p.save_button()
                row["pause_save_button"] = None if b is None else {"disabled": bool(b.get("disabled"))}
                row["pause_buttons"] = [x.get("text") for x in p.buttons()]
                p.close_panels()
            sha_before_quit = read_status(self.saves / "slot1.json").get("sha256")
            row["quit"] = p.quit_via_menu(prefer_save=prefer_save)
            self.g.stop()
            main = read_status(self.saves / "slot1.json")
            row["save_on_disk"] = {k: main.get(k) for k in ("area", "spawn", "pos", "respawn", "area_respawn", "saved_unix")}
            row["save_changed_by_quit"] = main.get("sha256") != sha_before_quit
            row["snapshot"] = snapshot(res, self.saves, f"{label}_after_quit")
            p = self.launch()
            ts = title_state(p)
            cg = continue_game(p)
            row["title_continue"] = ts.get("continue")
            row["continue"] = cg
            o_after = p.observe()
            row["after"] = {k: o_after[k] for k in ("area", "zone", "pos", "hp")}
            if rule == "saved_pos":
                ref_pos = main.get("pos")
            else:
                ref_pos = ref
            d = dist2(xz(o_after["pos"]), xz(ref_pos)) if (o_after.get("pos") and ref_pos) else None
            row["dist_to_expected"] = None if d is None else round(d, 2)
            same_items = o_after["inv"] == o_before["inv"] and o_after["keys"] == o_before["keys"]
            lost = sorted(set(o_before["flags"]) - set(o_after["flags"]))
            row["items_same"] = same_items
            row["flags_lost"] = lost
            if not same_items:
                row["item_diff"] = {k: [(o_before["inv"] or {}).get(k), (o_after["inv"] or {}).get(k)]
                                    for k in set(o_before["inv"] or {}) | set(o_after["inv"] or {})
                                    if (o_before["inv"] or {}).get(k) != (o_after["inv"] or {}).get(k)}
            resp_ok = True
            if expect_resp is not None:
                resp_ok = list(main.get("respawn") or []) == list(expect_resp)
            row["respawn_ok"] = resp_ok
            # a quit WITHOUT a save (inside a trial) may lose what happened since the last save (the dialog says so)
            saved_quit = (row.get("quit") or {}).get("choice") == "Save & Quit"
            row["flags_lost_expected"] = bool(lost) and not saved_quit
            ok = cg.get("playing") and o_after["area"] == expect_area and d is not None and d <= tol and same_items \
                and (not lost or not saved_quit) and resp_ok
            res.check(f"areas_{label}", ok,
                      f"Continue -> {expect_area}, {'the saved spot' if rule == 'saved_pos' else f'the spawn near {ref}'} "
                      f"(<= {tol} m), same items / keys / flags" + (f", respawn {expect_resp}" if expect_resp else ""),
                      {k: row.get(k) for k in ("before", "after", "dist_to_expected", "save_on_disk", "items_same", "flags_lost",
                                               "respawn_ok", "quit", "pause_save", "pause_save_button", "save_changed_by_quit")},
                      evidence=[row["snapshot"]])
            p.bot.calibrate_look()
        except Exception as e:  # noqa: BLE001
            row["error"] = f"{type(e).__name__}: {e}"
            row["traceback"] = traceback.format_exc()
            res.note(f"{label}: {row['error']}")
        res.save()
        return row

    # ---------------------------------------------------------------- the journey
    def run(self, from_step: str = ""):
        res = self.res
        src = CHAIN / "run3" / "checkpoints" / "END_end"
        if from_step == "trial_leave":
            src = RUN / "areas" / "snapshots" / "echo_trial_after_quit"
            copy_saves(src, self.saves)
            res.data["start"] = (f"NATURAL (resumed): {src} - the game-written save at the manor's ballroom rest candles from "
                                 "the first areas run (its journey stopped at a bot click on the trial's confirm dialog)")
        else:
            copy_saves(src, self.saves)
            res.data["start"] = f"NATURAL: copy of {src} (the natural chain's final save: free play at the Haven, Chapter Two complete)"
        try:
            if from_step == "trial_leave":
                p = self.launch()
                title_state(p)
                res.data["first_continue"] = continue_game(p)
                p.bot.calibrate_look()
                return self.tail()
            p = self.launch()
            title_state(p)
            cg = continue_game(p)
            res.data["first_continue"] = cg
            p.bot.calibrate_look()
            # 1) the surface (the Haven): outdoor -> the saved spot; respawn stays the bed
            hop(p, self.rng, center=(-3.0, 8.0), radius=4.0)
            self.cycle("surface_haven", SURFACE, "saved_pos", expect_resp=["surface", "bed"])
            # 2) the Reach: Ward Stone -> Lantern Road -> Commons; outdoor -> the saved spot; respawn the Commons arch
            p = self.p
            b = open_lantern_road(p)
            if b is None:
                raise StepFailed("no Lanternwake Commons destination")
            g_click(self.g, b)
            if not p.wait_area(REACH, 90):
                raise StepFailed("did not arrive in the Reach")
            res.data["reach_arrival"] = self.arrival()
            p.bot.calibrate_look()
            hop(p, self.rng, radius=4.0)
            self.cycle("reach_commons", REACH, "saved_pos", expect_resp=["hallowmere_reach", "commons_arch"])
            # 3) the Hushed Works: the refuge hatch beside the Conservatory (arrival spawn), then the refuge lantern
            p = self.p
            p.nav((21.8, 0.0, 3.2), tol=1.6, final_tol=0.8)
            if not p.interact_with((24.0, 0.0, 2.0), ["Climb down to the refuge"], check=lambda: p.mode() != "playing" or p.area() == WORKS, stop=1.4):
                raise StepFailed(f"refuge hatch: prompt={p.prompt()}")
            if not p.wait_area(WORKS, 90):
                raise StepFailed("the hatch did not lead into the Works")
            arr = self.arrival()
            res.data["works_arrival"] = arr
            main_arr = read_status(self.saves / "slot1.json")
            res.data["works_arrival_save"] = {k: main_arr.get(k) for k in ("area", "spawn", "respawn", "area_respawn")}
            self.cycle("works_refuge_arrival", WORKS, "spawn", ref=arr["pos"], tol=1.0,
                       expect_resp=["hushed_works", main_arr.get("respawn", [None, None])[1]])
            p = self.p
            rested = p.rest_lantern((25.4, -18.0, -5.2), stand=(25.4, -18.0, -3.8))
            time.sleep(1.0)
            lan = read_status(self.saves / "slot1.json")
            res.data["works_lantern_rest"] = {"rested": rested, "save": {k: lan.get(k) for k in ("spawn", "respawn", "area_respawn", "pos")}}
            self.cycle("works_refuge_lantern", WORKS, "spawn", ref=(25.4, -18.0, -3.8), tol=2.0,
                       expect_resp=["hushed_works", lan.get("spawn")])
            # 4) the manor: drainage stair up, north road, grounds, front door; cloakroom (arrival), ballroom candles
            p = self.p
            p.nav((21.25, -18.0, -13.0), final_tol=0.6)
            if not p.interact_with((21.25, -15.4, -16.9), ["Take the drainage stair up"], check=lambda: p.mode() != "playing" or p.area() == REACH,
                                   stop=1.6, tries=6):
                raise StepFailed(f"drainage stair: prompt={p.prompt()}")
            if not p.wait_area(REACH, 90):
                raise StepFailed("the drainage stair did not lead to the Reach")
            p.bot.calibrate_look()
            if not p.nav((10.9, 0.0, -52.8), tol=1.8, final_tol=1.2):
                raise StepFailed(f"could not reach the manor arch (at {p.pos()})")
            S3, seg = self.seg()
            seg.s_enter()
            arr = self.arrival()
            res.data["manor_arrival"] = arr
            m1 = read_status(self.saves / "slot1.json")
            self.cycle("manor_cloakroom", MANOR, "spawn", ref=arr["pos"], tol=1.0, expect_resp=list(m1.get("respawn") or []))
            S3, seg = self.seg()
            seg.nav(S3.BALL_CP_STAND, tol=0.5)
            seg.s_rest_ballroom()
            time.sleep(1.0)
            m2 = read_status(self.saves / "slot1.json")
            res.data["manor_ballroom_rest_save"] = {k: m2.get(k) for k in ("spawn", "respawn", "area_respawn", "pos")}
            self.cycle("manor_ballroom_candles", MANOR, "spawn", ref=(5.0, 0.0, -33.9), tol=2.5,
                       expect_resp=["moonveil_manor", "manor_ballroom"])
            # 5) the Echo Trial (Velour's, from the ballroom candles): never saved; Continue returns to the origin
            p = self.p
            sha_origin = sha(self.saves / "slot1.json")
            self.enter_trial()
            o = p.observe()
            res.data["trial_arrival"] = {k: o[k] for k in ("area", "zone", "pos")}
            self.cycle("echo_trial", MANOR, "spawn", ref=(5.0, 0.0, -33.9), tol=2.5, use_pause=False, prefer_save=True,
                       expect_resp=["moonveil_manor", "manor_ballroom"])
            row = self.rows[-1]
            row["save_unchanged_by_trial"] = sha(Path(row["snapshot"]) / "slot1.json") == sha_origin
            res.check("areas_echo_trial_no_save", row.get("pause_save_button", {}) is not None
                      and (row.get("pause_save_button") or {}).get("disabled") is True and row["save_unchanged_by_trial"]
                      and (row.get("quit") or {}).get("choice") == "Quit",
                      "inside the trial Save Game is disabled, the quit dialog offers no Save & Quit, the save on disk is the "
                      "origin checkpoint's (byte-identical)", {k: row.get(k) for k in ("pause_save_button", "pause_buttons", "quit",
                                                                                       "save_unchanged_by_trial")})
            return self.tail()
        except Exception as e:  # noqa: BLE001
            res.note(f"journey stopped: {type(e).__name__}: {e}")
            res.data["traceback"] = traceback.format_exc()
        finally:
            self.finish()
        return res.data

    def finish(self):
        res = self.res
        if self.g is not None:
            self.g.stop()
        errs = []
        for f in sorted(res.dir.glob("a*_godot.log")):
            errs += [f"{f.name}: {e}" for e in Game(res.phase, f.stem.replace("_godot", ""), self.saves).log_errors()]
        res.data["script_errors"] = errs
        res.save()

    def tail(self):
        """Leave the trial through the pause menu, then Tobin's Annex (from the manor, via the Lantern Road home)."""
        res = self.res
        try:
            # "Leave the trial" from the pause menu returns to the origin with an arrival save
            p = self.p
            self.enter_trial()
            n0 = len(p.saved_msgs())
            p.open_pause()
            left = False
            if p.click_button("Leave the trial", exact=True, timeout=3):
                # the confirm dialog repeats the label: its button is the LAST one with that text
                p.wait(lambda s: sum(1 for b in s.get("buttons") or [] if str(b.get("text")) == "Leave the trial") >= 2, 3.0)
                bl = [b for b in p.buttons() if str(b.get("text")) == "Leave the trial" and not b.get("disabled")]
                if bl:
                    g_click(self.g, bl[-1])
                left = p.wait_area(MANOR, 60)
            time.sleep(1.5)
            o = p.observe()
            d = dist2(xz(o["pos"]), (5.0, -33.9)) if o.get("pos") else None
            res.check("areas_leave_trial_returns_to_origin", left and d is not None and d < 2.5 and len(p.saved_msgs()) > n0,
                      "pause -> Leave the trial -> back at the ballroom candles, an arrival save written",
                      {"left": left, "area": o["area"], "pos": o["pos"], "dist": d, "saved": len(p.saved_msgs()) > n0})
            # 6) Tobin's Annex: out of the manor, Lantern Road home, the side door by the mine mouth
            S3, seg = self.seg()
            seg.nav((0.0, -2.0), tol=0.6)
            if not seg.use("front door", ["Step back outside"], lambda: self.p.area() == REACH or self.p.mode() == "loading",
                           (0.0, -1.8), (0.0, -0.3)):
                raise StepFailed("manor front door")
            p = self.p
            if not p.wait_area(REACH, 60):
                raise StepFailed("did not step outside")
            p.bot.calibrate_look()
            pts = list(reversed(S3.GROUNDS_PATH)) + [(10.9, -52.8)]
            p.route(pts, tol=1.4, sprint=True, fight=True)
            if not p.interact_with((10.0, 0.0, -50.0), ["Travel the Lantern Road"], check=lambda: bool(p.ui()), stop=1.8):
                raise StepFailed(f"manor arch: prompt={p.prompt()}")
            p.click_button("The Haven", timeout=5)
            if not p.wait_area(SURFACE, 90):
                raise StepFailed("did not get home")
            p.bot.calibrate_look()
            mine = [(6, -12), (14, -22), (22, -30), (30, -40), (38, -50), (44, -58), (48, -63), (55.6, -63.5)]
            if not p.route(mine, tol=1.6, sprint=True, fight=True):
                raise StepFailed(f"could not walk to Tobin's side door (at {p.pos()})")
            door = p.nearest(lambda n: "tobin" in str(n.get("text", "")).lower(), 20) or {"pos": [58.5, 0.0, -68.3]}
            res.data["tobin_door_seen"] = door
            if not p.interact_with(door, ["Go through Tobin's side door"], check=lambda: p.mode() != "playing" or p.area() == ANNEX,
                                   stop=1.6, tries=6):
                raise StepFailed(f"Tobin's door: prompt={p.prompt()} at {p.pos()}")
            if not p.wait_area(ANNEX, 90):
                raise StepFailed("the side door did not lead into the annex")
            arr = self.arrival()
            res.data["annex_arrival"] = arr
            a1 = read_status(self.saves / "slot1.json")
            res.data["annex_arrival_save"] = {k: a1.get(k) for k in ("area", "spawn", "respawn", "area_respawn")}
            self.cycle("tobin_annex", ANNEX, "spawn", ref=arr["pos"], tol=1.0, expect_resp=["tobin_annex", "annex_entry"])
        except Exception as e:  # noqa: BLE001
            res.note(f"journey stopped: {type(e).__name__}: {e}")
            res.data["traceback"] = traceback.format_exc()
        finally:
            self.finish()
        return res.data

    def enter_trial(self):
        p = self.p
        S3, seg = self.seg()
        seg.nav((7.4, -35.4), tol=0.6)
        ok = seg.use("echo stone", ["Echo Trial"], lambda: bool(self.p.ui()), (7.6, -35.6), (8.6, -34.6))
        if not ok:
            raise StepFailed(f"echo stone: prompt={p.prompt()}")
        if not p.click_button("Enter the echo", exact=True, timeout=4):
            raise StepFailed(f"no 'Enter the echo': {[b.get('text') for b in p.buttons()]}")
        if not p.wait_area(TRIAL, 90):
            raise StepFailed("did not arrive in the trial")
        time.sleep(1.0)


def g_click(g: Game, b: dict):
    r = b.get("rf") or b.get("rect")
    x, y, w, h = [float(v) for v in r]
    g.vin.click(x + w / 2.0, y + h / 2.0)


def phase_areas(a) -> dict:
    return Areas(a).run()


def phase_areas_tail(a) -> dict:
    return Areas(a, "areas_tail").run(from_step="trial_leave")


def phase_probe(a) -> dict:
    """Where the remembered respawn sends Krystal right after entering an area by a non-arch door: the pause menu's
    "Return to safety" (it uses the same Game.return_point() as a fall). Starts from game-written saves of the areas run:
    the Works (Reach refuge hatch -> the refuge, respawn left at vault_exit) and the manor (front door -> cloakroom,
    respawn left at manor_balcony)."""
    res = Result("probe")
    out = {}
    cases = [("works_refuge_hatch", RUN / "areas" / "snapshots" / "reach_commons_after_quit", "works"),
             ("manor_front_door", RUN / "areas" / "snapshots" / "manor_cloakroom_after_quit", "manor")]
    res.data["start"] = "NATURAL: game-written saves from the areas run (snapshots)"
    for name, src, kind in cases:
        saves = res.dir / name / "saves"
        copy_saves(src, saves)
        g, p = launch("probe", name, saves, res.dir, max_seconds=400)
        rec: dict = {"start": str(src)}
        try:
            title_state(p)
            rec["continue"] = continue_game(p)
            p.bot.calibrate_look()
            if kind == "works":
                p.nav((21.8, 0.0, 3.2), tol=1.6, final_tol=0.8)
                if not p.interact_with((24.0, 0.0, 2.0), ["Climb down to the refuge"],
                                       check=lambda: p.mode() != "playing" or p.area() == WORKS, stop=1.4):
                    raise StepFailed(f"refuge hatch: prompt={p.prompt()}")
                p.wait_area(WORKS, 90)
            time.sleep(1.5)
            o = p.observe()
            rec["arrived"] = {k: o[k] for k in ("area", "zone", "pos")}
            sv = read_status(saves / "slot1.json")
            rec["save_after_arrival"] = {k: sv.get(k) for k in ("spawn", "respawn", "area_respawn")}
            p.open_pause()
            p.wait(lambda s: any(str(b.get("text")) in ("Return to safety", "Return to the Haven", "Return to last lantern")
                                 for b in s.get("buttons") or []), 3.0)
            label = next((str(b.get("text")) for b in p.buttons() if str(b.get("text")) in ("Return to safety", "Return to the Haven",
                                                                                                 "Return to last lantern")), "")
            rec["unstuck_label"] = label
            p.click_button(label, exact=True, timeout=3)
            p.wait(lambda s: any(str(b.get("text")) == "Take me there" for b in s.get("buttons") or []), 3.0)
            p.click_button("Take me there", exact=True, timeout=3)
            p.wait(lambda s: not s.get("ui_stack") and s.get("mode") == "playing", 10)
            time.sleep(2.0)
            o2 = p.observe()
            rec["after_return_to_safety"] = {k: o2[k] for k in ("area", "zone", "pos")}
            rec["moved_m"] = round(dist2(xz(o["pos"]), xz(o2["pos"])), 1) if o.get("pos") and o2.get("pos") else None
        except Exception as e:  # noqa: BLE001
            rec["error"] = f"{type(e).__name__}: {e}"
        finally:
            g.stop()
        out[name] = rec
        res.check(f"probe_{name}", None, "INFO: where 'Return to safety' (= the fall respawn point) sends her right after arrival",
                  rec)
    res.data.update(out)
    res.save()
    return res.data


def rewards_at_stamp(save: dict, key: str) -> tuple:
    """The ledger entries stamped in the same game minute as `key` (one grant moment), and that stamp."""
    led = save["state"].get("ledger") or {}
    t = led.get(key)
    return sorted(k for k, v in led.items() if t is not None and v == t), t


def phase_recheck(a) -> dict:
    """Re-evaluates three checks whose FIRST expectation in this script was wrong (not the game), from the files the
    runs left on disk; appends the corrected rows (kind "re-evaluation") and keeps the original rows."""
    out = {}
    # 1) crossing: the baseline must be the rewards of the SAME grant moment, not everything up to a later save
    f = RUN / "crossing" / "result.json"
    if f.exists():
        r = json.loads(f.read_text(encoding="utf-8"))
        r["checks"] = [c for c in r["checks"] if c.get("kind") != "re-evaluation"]
        base_save = load_save(CHAIN / "run3" / "s4" / "checkpoints" / "bell_throat" / "slot1.json")
        post = load_save(RUN / "crossing" / "snapshots" / "post_win_gate_rest" / "slot1.json")
        pre = load_save(CHAIN / "run3" / "s4" / "checkpoints" / "winch" / "slot1.json")
        b_set, b_t = rewards_at_stamp(base_save, "rw_ch2_crossing")
        m_set, m_t = rewards_at_stamp(post, "rw_ch2_crossing")
        d = ledger_diff(pre, post)
        ok = b_set == m_set and d["items_delta"].get("thread_veil", 0) == 1 and not d["ledger_time_changed"] \
            and not d["ledger_removed"]
        row = {"check": "crossing_rewards_once", "result": "PASS" if ok else "FAIL", "kind": "re-evaluation",
               "expected": "the Crossing grant moment holds exactly the no-death baseline's rewards (chain run3: "
                           "rw_ch2_crossing + rw_ch2_weaver_crossing in one game minute), Thread Veil +1, no entry re-stamped",
               "observed": {"this_run_grant_moment": m_set, "this_run_stamp": m_t, "baseline_grant_moment": b_set,
                            "baseline_stamp": b_t, "items_delta": d["items_delta"], "deaths": d["deaths"],
                            "why_reevaluated": "the first rule compared against every ledger addition up to the baseline's next "
                                               "save (bell_throat), which also holds rw_ch2_false_home, a later step"},
               "evidence": [str(RUN / "crossing" / "snapshots" / "post_win_gate_rest")]}
        r["checks"].append(row)
        write_json(f, r)
        out["crossing"] = row
    # 2) areas: the refuge lantern's checkpoint spawn IS "refuge" (the arrival point), not the lantern stand
    f = RUN / "areas" / "result.json"
    if f.exists():
        r = json.loads(f.read_text(encoding="utf-8"))
        r["checks"] = [c for c in r["checks"] if c.get("kind") != "re-evaluation"]
        rows = {x["area_type"]: x for x in r.get("rows", [])}
        lan = rows.get("works_refuge_lantern") or {}
        arr = (r.get("works_arrival") or {}).get("pos")
        after = (lan.get("after") or {}).get("pos")
        dd = dist2(xz(after), xz(arr)) if (after and arr) else None
        disk = lan.get("save_on_disk") or {}
        ok = dd is not None and dd < 0.5 and disk.get("spawn") == "refuge" and disk.get("respawn") == ["hushed_works", "refuge"] \
            and lan.get("items_same") and not lan.get("flags_lost")
        row = {"check": "areas_works_refuge_lantern", "result": "PASS" if ok else "FAIL", "kind": "re-evaluation",
               "expected": "Continue at the refuge checkpoint's spawn 'refuge' (23.2, -18, -8.0: the checkpoint lantern "
                           "registers that spawn), respawn moved from vault_exit to the refuge",
               "observed": {"after": lan.get("after"), "dist_to_refuge_spawn": dd, "save_on_disk": disk,
                            "why_reevaluated": "the first rule used the lantern's stand point (25.4, -3.8) as the spawn"}}
        r["checks"].append(row)
        tri = rows.get("echo_trial") or {}
        dist_t = tri.get("dist_to_expected")
        snap = RUN / "areas" / "snapshots" / "echo_trial_after_quit" / "slot1.json"
        saved_flags = set(load_save(snap)["state"].get("flags") or []) if snap.exists() else set()
        lost_saved = sorted(set(tri.get("flags_lost") or []) & saved_flags)
        ok2 = (tri.get("after") or {}).get("area") == MANOR and dist_t is not None and dist_t < 2.5 \
            and tri.get("items_same") and (tri.get("quit") or {}).get("choice") == "Quit" and not lost_saved
        row2 = {"check": "areas_echo_trial", "result": "PASS" if ok2 else "FAIL", "kind": "re-evaluation",
                "expected": "Continue after quitting inside the trial lands at the origin (ballroom candles); only what "
                            "was never saved (flags set after the last save) is gone - the quit dialog says so",
                "observed": {"after": tri.get("after"), "dist": dist_t, "flags_lost": tri.get("flags_lost"),
                             "lost_flags_that_were_in_the_save": lost_saved,
                             "quit": (tri.get("quit") or {}).get("choice"),
                             "why_reevaluated": "the first rule treated flags set after the last save as lost progress"}}
        r["checks"].append(row2)
        write_json(f, r)
        out["areas"] = [row, row2]
    print(json.dumps(out, indent=1, default=str)[:3000])
    return out


def phase_bugs(a) -> dict:
    """Merges the phases' bug lists (+ reviewed findings in RUN/manual_bugs.json) into RUN/bugs.json and prints a
    one-line summary per check."""
    bugs = []
    summary = {}
    for ph in ("areas", "areas_tail", "probe", "kill", "synth", "corrupt", "future", "prev2", "velour", "crossing"):
        f = RUN / ph / "result.json"
        if not f.exists():
            continue
        r = json.loads(f.read_text(encoding="utf-8"))
        summary[ph] = [(c["result"], c["check"]) for c in r.get("checks", [])]
        for b in r.get("bugs", []):
            bugs.append(dict(b, phase=ph))
        for e in r.get("script_errors", []) or []:
            bugs.append({"title": f"SCRIPT ERROR during {ph}: {e[:150]}", "severity": "major", "steps": f"cov_persistence_failure.py {ph}",
                         "expected": "no script errors", "actual": e, "evidence": str(RUN / ph), "phase": ph})
    man = RUN / "manual_bugs.json"
    if man.exists():
        bugs += json.loads(man.read_text(encoding="utf-8"))
    write_json(RUN / "bugs.json", bugs)
    write_json(RUN / "summary.json", summary)
    for ph, rows in summary.items():
        for res_, name in rows:
            print(f"{ph:9} {res_:5} {name}")
    print(f"{len(bugs)} bugs -> {RUN / 'bugs.json'}")
    return {"bugs": bugs, "summary": summary}


PHASES = {"velour": phase_velour, "crossing": phase_crossing, "kill": phase_kill, "synth": phase_synth,
          "corrupt": phase_corrupt, "future": phase_future, "prev2": phase_prev2, "areas": phase_areas,
          "areas_tail": phase_areas_tail, "recheck": phase_recheck, "probe": phase_probe, "bugs": phase_bugs}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase", choices=list(PHASES) + ["all"])
    ap.add_argument("--attempts", type=int, default=24)
    ap.add_argument("--seed", type=int, default=None)
    a = ap.parse_args(argv)
    RUN.mkdir(parents=True, exist_ok=True)
    phases = list(PHASES) if a.phase == "all" else [a.phase]
    for ph in phases:
        print(f"==== phase {ph} ====", flush=True)
        PHASES[ph](a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
