"""The NATURAL end-to-end Chapter Two route (MP 20.4 Run A): S1 -> S2 -> S3 -> S4 in ONE continuous journey.

Start: a COPY of game/tests/fixtures/saves/16_real_handoff_c1_complete.json (the real Chapter-One-complete save the
Chapter One bot wrote; version 1, so the first load migrates it). No fixtures, no debug cheats, no teleports, no
flag or item grants: the bot only reads the QA telemetry and acts through the virtual keyboard / mouse
(src/qa/qa_input.gd). Every segment starts exactly where the previous one ended - in the same game process, except
where the route itself quits the game (S1's save / quit / relaunch + Continue, and the final relaunch check).

  S1   tools/qa/ch2/s1_continuation.py   title Continue (v1 -> v2 migration), wardrobe, Ward Stone acceptance,
                                          waygate, Commons arch + festival map, Lantern Road home and back,
                                          pause-menu save, Quit, relaunch, Continue (its own checks).
  S2   tools/qa/ch2/s2_orchard_quarry.py orchard (irrigation, seed, mimic pocket, garden lamp, Patchwalkers,
                                          food), quarry (wood, iron, winch, Quarry Warden - slam lesson, 1-3 pillar
                                          exposures, three pulses -, quarry lamp), Save & Quit -> Continue.
  T23  (this file)                        what the S3 fixture handed out (full health) is earned by play: down from
                                          the lamp shelf, Lantern Road home from the quarry arch, sleep in the bed
                                          (full heal + save), pick berries, harvest the ripe sweetroot, cook / craft
                                          (Hearty Stew at the campfire when there is sweetroot, Berry Snacks by
                                          hand), Ward Stone -> Lantern Road -> Commons, walk the road to the manor arch.
  S3   tools/qa/ch2/s3_manor.py          manor arch, the Looking-Glass Hall, ballroom puzzle, Count Velour, the
                                          Moonveil lantern, balcony shortcut, garden stair back to the Reach.
  T34  (this file)                        what the S4 fixture handed out (full health, 4 berry snacks + 2 stews): the
                                          manor arch -> Lantern Road home -> sleep / berries / cooking -> Ward Stone
                                          -> Commons.
  S4   tools/qa/ch2/s4_route.py          + the preparation notes at the Conservatory (the S4 fixture set that flag;
                                          here Krystal reads them), link the lanterns, the Hushed Works, the lines,
                                          the Weaver's Crossing (all its phases in the fixed build), the Choir, home,
                                          the Lanternwake, free play.
  END  (this file)                        relaunch + Continue: the same save, chapter complete, the same items.

The segment scripts were developed from diagnostic fixture starts; here they run from natural state. The
adaptation lives in this file (segment modules untouched): the transitions T23 / T34 (see above), S3's backpack
eating (its own eat() only uses hotbar food), a look calibration that also works on a 1080p second-monitor window
(the segment ones were tuned to the 64 px headless window), the preparation-notes step before S4 links the lanterns,
and S2's Warden-fight notes (the fight itself - tells read from the telemetry "elite" entry, pillar bait, side-steps
across the locked charge lane, the pulse ring, climbing back onto the bench after a fall - lives in S2.WardenFight).
Weapon upgrades: none of the fixtures handed any out; the Ironwood sword needs Woven Cloth (a Loom,
locked behind the optional Chapter One Tailor's Cache flag that the real save does not have), so the natural
chain keeps the copper sword like every fixture did.

Logged per run (in --out): chain_result.json (status, total and per-segment durations, checkpoints, HP / food /
area at every boundary, screenshot requests, SCRIPT ERRORs per segment, music cue changes, deaths), chain.log, the
per-process bot logs / game logs / telemetry, chain_events.jsonl (music cues, saves, deaths, area changes,
chapter-two steps, as they happen), <segment>/ (the segment's own result + shots), checkpoints/<segment>_end/ (the
game's own save folder at each boundary) and bugs.json (automatic findings: script errors, segment bug reports).

Modes
  --headless (default)  source project in the console editor binary, --headless, no window, dummy audio, virtual
                        input (the game's "shot" requests fail: they are kept so the visible run captures them).
  --visible             second-monitor mode: borderless window at --qa-window (default 1920,0,1920,1080 =
                        DISPLAY2), --qa-no-focus, virtual input only (never SendInput, never the owner's focus).
                        Sound stays ON (no --qa-mute) unless --mute is given.
  --dev (default)       run the SOURCE project (--project, default <repo>/game) with the Godot binary (--godot).
  --exe [PATH]          run a PACKAGED build (default builds/Hollowhaven/Hollowhaven.exe); visible runs start it
                        from a hard-linked copy with a no-focus override.cfg (session.prepare_qa_exe). The build must
                        contain game/src/qa/qa_input.gd (the 0.9.1 build does not: rebuild with tools/build_release.ps1).
  --out DIR             run folder (default qa/tmp/bot/chain/run_<timestamp>; an existing folder is replaced).
  --dry-run             print the launch command for the chosen mode and exit (starts nothing).
Diagnostics (not the natural route): --from SEG --start-save <save folder or slot1.json written by the game>
resumes at a segment boundary (the checkpoints/<seg>_end/ folders of an earlier run); --until SEG stops after SEG.

Examples
  headless (development):  python tools/qa/ch2/chain.py --headless --out qa/tmp/bot/chain/run1
  headless on a snapshot:  python tools/qa/ch2/chain.py --headless --project <snapshot>/game --out ...
  visible, sound on, packaged build on the second monitor (after tools/build_release.ps1):
      python tools/qa/ch2/chain.py --visible --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/visible1
"""
from __future__ import annotations

import argparse
import json
import math

import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
QA_DIR = HERE.parent
ROOT = QA_DIR.parents[1]
for _p in (str(HERE), str(QA_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import s1_common as C  # noqa: E402
from hhbot import Telemetry, angle_diff  # noqa: E402
from session import SECOND_MONITOR_RECT, parse_rect, prepare_qa_exe, port_free  # noqa: E402
from fglock import FocusWatchdog, ForegroundLock  # noqa: E402  (never take the owner's focus)

GODOT_DIR = ROOT / ".tools" / "godot"
CONSOLE_EXE = GODOT_DIR / "Godot_v4.7.2-stable_win64_console.exe"
EDITOR_EXE = GODOT_DIR / "Godot_v4.7.2-stable_win64.exe"
PACKAGED_EXE = ROOT / "builds" / "Hollowhaven" / "Hollowhaven.exe"
FIXTURE_NAME = "16_real_handoff_c1_complete.json"
REACH = "hallowmere_reach"
SURFACE = "surface"
MANOR = "moonveil_manor"
WORKS = "hushed_works"
SEGMENTS = ["S1", "S2", "T23", "S3", "T34", "S4", "END"]
TITLES = {"S1": "Continuation start (migration, wardrobe, Ward Stone, waygate, Commons, relaunch)",
          "S2": "Hallowmere west + east (orchard, quarry, Quarry Warden)",
          "T23": "Home to rest and cook, then the road to the manor",
          "S3": "Moonveil Manor (Count Velour)",
          "T34": "Home to rest and cook before the Hushed Works",
          "S4": "Link the lanterns, the Hushed Works, the Crossing, the Choir, the Lanternwake, free play",
          "END": "Relaunch + Continue check (free play resumes in the same save)"}
FOOD_ITEMS = ("hearty_stew", "pumpkin_soup", "roseberry_tart", "berry_snack", "glowcap_skewer", "pumpkin_biscuit",
              "sweetroot", "roseberries", "pumpkin", "berries", "candy")
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
SW_SHOWNOACTIVATE = 4


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def xz(p):
    return (p[0], p[2]) if len(p) >= 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def write_json(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=1, default=str), encoding="utf-8")


class ChainStop(Exception):
    pass


def cue_titles(project: Path) -> dict:
    """{"m15": "Welcome to Lanternwake (safe)", ...} from the project's data/music.gd (read-only, for the report)."""
    out = {}
    try:
        text = (Path(project) / "data" / "music.gd").read_text(encoding="utf-8")
        for m in re.finditer(r'"(m\d\d)":\s*\{"title":\s*"([^"]*)",\s*"kind":\s*"([^"]*)"', text):
            out[m.group(1)] = f"{m.group(2)} ({m.group(3)})"
    except OSError:
        pass
    return out


def music_changes(events: list[dict]) -> list[dict]:
    """Music cue changes from the game's own Events.music_cue_changed messages (every change, with its game time;
    "" = the director went quiet), plus changes only the 0.5 s "music" snapshot saw (marked snapshot_only)."""
    out: list[dict] = []
    last: dict = {}
    for e in events:
        if e["k"] not in ("msg_music", "music_cue"):
            continue
        g = e.get("game")
        if e["k"] == "msg_music":
            if last.get(g) == e["text"]:
                continue
            last[g] = e["text"]
            out.append({"cue": e["text"] or "(silence)", "seg": e["seg"], "game": g, "t": e.get("t"),
                        "area": e.get("area"), "wall": e["wall"]})
        elif e["text"] and last.get(g) != e["text"]:
            last[g] = e["text"]
            out.append({"cue": e["text"], "seg": e["seg"], "game": g, "t": e.get("t"), "area": e.get("area"),
                        "wall": e["wall"], "snapshot_only": True})
    return out


# ============================================================================================ bot + game process
class ChainBot(C.S1Bot):
    """The S1 float-precision bot (float look / clicks for the headless 1/30-scale UI) with a look calibration that
    adapts its motion: one window pixel turns the camera ~4 degrees in the 64 px headless window but only ~0.13
    degrees in a 1920 px second-monitor window, so a fixed probe (S1Bot: 3 px) cannot measure the visible case."""

    def calibrate_look(self) -> float:
        if not self.wait_state(lambda s: s.get("mode") == "playing" and not s.get("ui_stack"), 10.0):
            self.log("calibrate_look: not playing / a menu is open - calibration postponed")
            return self.px_per_deg
        amt = 3.0
        d = 0.0
        for _ in range(7):
            time.sleep(0.25)
            y0 = self.cam_yaw()
            if y0 is None:
                time.sleep(0.3)
                continue
            for _k in range(3):
                self.win.mouse_move(amt / 3.0, 0)
                time.sleep(0.04)
            time.sleep(0.4)
            y1 = self.cam_yaw()
            if y1 is None:
                continue
            d = angle_diff(y1, y0)
            if abs(d) < 3.0:
                amt *= 5.0
                continue
            if abs(d) > 150.0:
                amt /= 4.0
                continue
            self.px_per_deg = amt / abs(d)
            self.invert = -1.0 if d > 0 else 1.0
            self.calibrated = True
            break
        self.log(f"calibrated look: {self.px_per_deg:.4f} px/deg (motion {amt:.2f} px -> dyaw={d:.1f}) "
                 f"invert={self.invert} ok={self.calibrated}")
        return self.px_per_deg


def chain_s2_class(S2, notes: list):
    """S2's Segment from natural state. The Quarry Warden fight itself (S2.WardenFight) reads the Warden's tells from
    the telemetry "elite" entry, baits its charge into a pillar, side-steps across the locked lane, steps out of the
    pulse ring and climbs back onto the arena bench by the nearest ramp when a roll / knockback drops Krystal to L1
    (the Warden gives up and resets after 5 s off its floor - CHAIN-001 fix). This wrapper only collects that fight's
    player-level recoveries (climbs, give-ups) as chain notes."""

    class ChainS2(S2.Segment):
        def warden_note(self, text):
            super().warden_note(text)
            notes.append(text)

    return ChainS2


def kill_tree(pid: int) -> None:
    """Kills pid and its children - only the process this module started (the console wrapper and its child)."""
    try:
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, timeout=20,
                       creationflags=CREATE_NO_WINDOW)
    except Exception:  # noqa: BLE001
        pass


class ChainGame:
    """One game process (headless or visible, source or packaged) + float virtual input + telemetry + a ChainBot.
    Offers what the segment libraries expect of a "game": .bot, .vin, .proc, .t_launch, .save_dir, .godot_log."""

    def __init__(self, cfg, index: int, save_dir: Path, port: int):
        self.cfg = cfg
        self.index = index
        self.name = f"g{index}"
        self.out = cfg.out
        self.save_dir = Path(save_dir)
        self.port = port
        self.tele_path = self.out / f"{self.name}_telemetry.jsonl"
        self.godot_log = self.out / f"{self.name}_godot.log"
        self.stdout_log = self.out / f"{self.name}_stdout.log"
        self.bot_log = self.out / f"{self.name}_bot.log"
        self.settings_file = self.out / "qa_settings.cfg"
        self.proc: subprocess.Popen | None = None
        self.vin = None
        self.bot: ChainBot | None = None
        self.t_launch = 0.0
        self.cmd: list[str] = []
        self._fh = None

    def command(self) -> list[str]:
        cfg = self.cfg
        user = [f"--qa-telemetry={self.tele_path.as_posix()}", "--qa-interval=0.1",
                f"--save-dir={self.save_dir.as_posix()}", f"--settings-file={self.settings_file.as_posix()}",
                f"--qa-input-port={self.port}", "--qa-no-focus", "--no-focus-pause",
                f"--max-seconds={int(cfg.max_minutes * 60)}"]
        if cfg.seed is not None:
            user.append(f"--seed={int(cfg.seed)}")
        if cfg.mute:
            user.append("--qa-mute")
        if cfg.headless:
            exe = str(cfg.exe) if cfg.exe else str(cfg.godot or CONSOLE_EXE)
            engine = ["--headless", "--max-fps", "60"]
            if not cfg.exe:
                engine += ["--path", str(cfg.project)]
            else:
                engine += ["--log-file", str(self.godot_log)]
            return [exe] + engine + ["--"] + user
        x, y, w, h = cfg.rect
        engine = ["--windowed", "--position", f"{x},{y}", "--resolution", f"{w}x{h}", "--log-file", str(self.godot_log)]
        user.append(f"--qa-window={x},{y},{w},{h}")
        if cfg.exe:
            if getattr(cfg, "dry_run", False):
                exe = str(self.out / "qa_exe" / Path(cfg.exe).name)      # what prepare_qa_exe would place
            else:
                exe = prepare_qa_exe(cfg.exe, self.out / "qa_exe", cfg.rect)
            return [exe] + engine + ["--"] + user
        exe = str(cfg.godot or EDITOR_EXE)
        return [exe, "--path", str(cfg.project)] + engine + ["--"] + user

    def start(self, connect_timeout: float = 120.0) -> ChainBot:
        if self.tele_path.exists():
            self.tele_path.unlink()
        self.cmd = self.command()
        log_target = self.godot_log if (self.cfg.headless and not self.cfg.exe) else self.stdout_log
        self._fh = open(log_target, "a", encoding="utf-8", errors="replace")
        self._fh.write(f"==== launch {now()}: {self.cmd}\n")
        self._fh.flush()
        self.t_launch = time.time()
        if self.cfg.headless:
            self.proc = subprocess.Popen(self.cmd, cwd=str(ROOT), stdout=self._fh, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW)
        else:
            si = subprocess.STARTUPINFO()
            si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            si.wShowWindow = SW_SHOWNOACTIVATE      # the process's first ShowWindow must not activate it
            # tools/qa/fglock.py: a fresh helper holds the foreground lock for the game's life, and a watchdog hands
            # the foreground straight back to the owner if the game ever gets it (the packaged build activates itself
            # ~0.6 s after launch otherwise - measured 2026-09-28).
            self.fg_lock = ForegroundLock().__enter__()
            self.proc = subprocess.Popen(self.cmd, cwd=str(ROOT), stdout=self._fh, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL, startupinfo=si)
            _proc = self.proc
            self.fg_watch = FocusWatchdog(lambda: _proc.pid if _proc.poll() is None else 0).start()
        tele = Telemetry(self.tele_path)
        try:
            self.vin = C.FloatVI(self.port, proc=self.proc, tele=tele, connect_timeout=connect_timeout)
        except Exception as e:
            s = tele.poll()
            self.stop()
            if s and "qa_input" not in s:
                raise RuntimeError(f"{self.cmd[0]} writes QA telemetry but has no QA input server (--qa-input-port): the "
                                   "build predates game/src/qa/qa_input.gd. Rebuild it (powershell -ExecutionPolicy Bypass "
                                   "-File tools/build_release.ps1) or run the sources with --dev.") from e
            raise
        self.bot = ChainBot(self.vin, tele, self.bot_log)
        self.bot.log(f"launched {self.name} ({'headless' if self.cfg.headless else 'visible'}, "
                     f"{'packaged' if self.cfg.exe else 'source'}) pid={self.proc.pid} port={self.port} cmd={self.cmd}")
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
        watch = getattr(self, "fg_watch", None)
        if watch is not None:
            rep = watch.stop()
            self.fg_watch = None
            try:
                (self.out / f"{self.name}_focus_watchdog.json").write_text(json.dumps(rep), encoding="utf-8")
                if self.bot is not None:
                    self.bot.log(f"foreground watchdog: {rep}")
            except Exception:  # noqa: BLE001
                pass
        lock = getattr(self, "fg_lock", None)
        if lock is not None:
            lock.release()
            self.fg_lock = None
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
                    self.proc.wait(15)
                except Exception:  # noqa: BLE001
                    pass
        if self._fh is not None:
            try:
                self._fh.close()
            except OSError:
                pass
            self._fh = None
        if self.bot is not None and self.bot.log_file:
            try:
                self.bot.log_file.flush()
            except Exception:  # noqa: BLE001
                pass

    def log_files(self) -> list[Path]:
        """The game's output log: stdout (headless source runs) or the --log-file (packaged / visible runs; its
        stdout copy is only used when the engine wrote no log file)."""
        if self.cfg.headless and not self.cfg.exe:
            return [self.godot_log] if self.godot_log.exists() else []
        if self.godot_log.exists() and self.godot_log.stat().st_size > 0:
            return [self.godot_log]
        return [self.stdout_log] if self.stdout_log.exists() else []


# ============================================================================================ observers
class TeleMonitor(threading.Thread):
    """Follows the current game's telemetry file on its own handle and records, as they happen: music cue changes
    (the "music" snapshot field and the "music" messages), saves, deaths, area changes, chapter-two step messages,
    discoveries and the second-monitor focus evidence. Read-only; appends to <out>/chain_events.jsonl."""

    KINDS = ("music", "saved", "event", "quest", "discover")

    def __init__(self, out: Path):
        super().__init__(daemon=True)
        self.out = out
        self.path: Path | None = None
        self.game = 0
        self.segment = "-"
        self._pos = 0
        self._buf = ""
        self._lock = threading.Lock()
        self._halt = threading.Event()
        self._seen: set = set()
        self.events: list[dict] = []
        self.last_cue: str | None = None
        self.last_area: str | None = None
        self.frames = 0
        self.frames_focused = 0
        self.frames_captured = 0
        self.hp_min: dict = {}
        self._fh = open(out / "chain_events.jsonl", "a", encoding="utf-8")

    def follow(self, path: Path, game: int):
        with self._lock:
            self.path = Path(path)
            self.game = game
            self._pos = 0
            self._buf = ""
            self._gen = getattr(self, "_gen", 0) + 1

    def set_segment(self, seg: str):
        with self._lock:
            self.segment = seg

    def stop(self):
        self._halt.set()

    def _emit(self, ev: dict):
        ev = dict(ev, wall=now(), seg=self.segment, game=self.game)
        self.events.append(ev)
        try:
            self._fh.write(json.dumps(ev) + "\n")
            self._fh.flush()
        except Exception:  # noqa: BLE001
            pass

    def _handle(self, s: dict):
        self.frames += 1
        if s.get("window_focused"):
            self.frames_focused += 1
        if s.get("mouse_mode") == 2:
            self.frames_captured += 1
        hp = (s.get("player") or {}).get("hp")
        if hp is not None:
            self.hp_min[self.segment] = min(self.hp_min.get(self.segment, 999.0), float(hp))
        area = s.get("area")
        if area and area != self.last_area:
            self._emit({"k": "area", "text": f"{self.last_area} -> {area}", "t": s.get("t")})
            self.last_area = area
        for m in s.get("messages") or []:
            if m.get("k") not in self.KINDS:
                continue
            key = (self.game, m.get("k"), m.get("text"), m.get("t"))
            if key in self._seen:
                continue
            self._seen.add(key)
            self._emit({"k": "msg_" + str(m.get("k")), "text": m.get("text"), "t": m.get("t"), "area": area})
        cue = (s.get("music") or {}).get("cue") if isinstance(s.get("music"), dict) else None
        if cue is not None and cue != self.last_cue:
            self._emit({"k": "music_cue", "text": cue, "prev": self.last_cue, "t": s.get("t"), "area": area,
                        "zone": s.get("zone")})
            self.last_cue = cue

    def run(self):
        while not self._halt.is_set():
            with self._lock:
                path, pos, buf, gen = self.path, self._pos, self._buf, getattr(self, "_gen", 0)
            if path is not None and path.exists():
                try:
                    with open(path, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(pos)
                        chunk = f.read()
                        pos = f.tell()
                    buf += chunk
                    lines = buf.split("\n")
                    buf = lines[-1]
                    with self._lock:
                        if gen != getattr(self, "_gen", 0):
                            lines = [""]          # switched to a new game's file meanwhile: drop this read
                        else:
                            self._pos, self._buf = pos, buf
                    for ln in lines[:-1]:
                        ln = ln.strip()
                        if not ln:
                            continue
                        try:
                            self._handle(json.loads(ln))
                        except (ValueError, TypeError, AttributeError):
                            continue
                except OSError:
                    pass
            self._halt.wait(0.3)
        try:
            self._fh.close()
        except Exception:  # noqa: BLE001
            pass


class ErrScanner:
    """SCRIPT ERROR / ERROR / USER ERROR lines (with the following 'at:' line) and WARNING counts in the game logs,
    read incrementally so every new line is attributed to the segment that was running."""

    ERR_PREFIX = ("SCRIPT ERROR", "ERROR", "USER ERROR", "USER SCRIPT ERROR")

    def __init__(self):
        self.offsets: dict[str, int] = {}

    def collect(self, paths) -> tuple[list[dict], list[str]]:
        errs, warns = [], []
        for p in paths:
            p = Path(p)
            if not p.exists():
                continue
            off = self.offsets.get(str(p), 0)
            try:
                with open(p, "rb") as f:          # bytes: exact offsets whatever the line endings
                    f.seek(off)
                    data = f.read()
            except OSError:
                continue
            cut = data.rfind(b"\n")               # keep a partial last line for the next call
            if cut < 0:
                continue
            self.offsets[str(p)] = off + cut + 1
            lines = data[:cut + 1].decode("utf-8", errors="replace").splitlines()
            for i, ln in enumerate(lines):
                s = ln.strip()
                if s.startswith(self.ERR_PREFIX):
                    at = ""
                    for j in range(i + 1, min(i + 4, len(lines))):
                        if lines[j].strip().startswith("at:"):
                            at = lines[j].strip()
                            break
                    errs.append({"log": p.name, "line": s[:400], "at": at[:300]})
                elif s.startswith("WARNING"):
                    warns.append(s[:300])
        return errs, warns


# ============================================================================================ the chain
class Chain:
    def __init__(self, cfg):
        self.cfg = cfg
        self.out: Path = cfg.out
        self.save_dir = self.out / "saves"
        self.games: list[ChainGame] = []
        self.game: ChainGame | None = None
        self.monitor = TeleMonitor(self.out)
        self.errs = ErrScanner()
        self.segments: list[dict] = []
        self.shots: list[dict] = []
        self.all_errors: list[dict] = []
        self.warnings: list[str] = []
        self.bugs: list[dict] = []
        self.notes: list[str] = []
        self.t0 = time.time()
        self.deadline = self.t0 + cfg.max_minutes * 60.0
        self._log_fh = open(self.out / "chain.log", "a", encoding="utf-8")
        self.start_save = cfg.start_save

    # ------------------------------------------------------------------ plumbing
    @property
    def bot(self) -> ChainBot:
        return self.game.bot

    def log(self, msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] CHAIN {msg}"
        print(line, flush=True)
        self._log_fh.write(line + "\n")
        self._log_fh.flush()
        if self.game is not None and self.game.bot is not None and self.game.bot.log_file:
            try:
                self.game.bot.log_file.write(line + "\n")
                self.game.bot.log_file.flush()
            except Exception:  # noqa: BLE001
                pass

    def next_port(self) -> int:
        p = self.cfg.port + len(self.games)
        for _ in range(50):
            if port_free(p):
                return p
            p += 10
        raise RuntimeError(f"no free port near {self.cfg.port}")

    def launch(self) -> ChainGame:
        g = ChainGame(self.cfg, len(self.games) + 1, self.save_dir, self.next_port())
        self.games.append(g)
        self.game = g
        self.monitor.follow(g.tele_path, g.index)
        g.start()
        return g

    def relaunch(self) -> ChainGame:
        old = self.game
        if old is not None and old.alive():
            if not old.wait_exit(5.0):
                self.log(f"{old.name} still running before the relaunch: stopping it")
                old.stop()
        if old is not None:
            old.stop()
        g = self.launch()
        self.log(f"relaunched as {g.name} (port {g.port})")
        return g

    def shot(self, label: str) -> dict:
        """The game's own screenshot request (headless: refused; the visible run captures it)."""
        p = self.out / "shots" / f"chain_{len(self.shots) + 1:03d}_{label}.png"
        rec = {"label": label, "path": str(p), "seg": self.monitor.segment, "wall": now()}
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            self.game.vin.request({"shot": p.as_posix()}, timeout=20.0)
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001
            rec["ok"] = False
            rec["error"] = str(e)[-160:]
        self.shots.append(rec)
        return rec

    def st(self) -> dict:
        try:
            return self.bot.state()
        except Exception:  # noqa: BLE001
            return {}

    def state_summary(self) -> dict:
        s = self.st()
        inv = s.get("inv") or {}
        c2 = s.get("chapter2") or {}
        return {"area": s.get("area"), "zone": s.get("zone"), "mode": s.get("mode"),
                "pos": (s.get("player") or {}).get("pos"), "hp": (s.get("player") or {}).get("hp"),
                "food": {k: inv[k] for k in FOOD_ITEMS if inv.get(k)}, "keys": s.get("keys"),
                "equipment": s.get("equipment"), "ch2_current": c2.get("current"), "ch2_done": len(c2.get("done") or []),
                "chapter2_finished": c2.get("finished"), "music": (s.get("music") or {}).get("cue"),
                "game": self.game.name if self.game else None}

    def snapshot_saves(self, label: str):
        try:
            dst = self.out / "checkpoints" / label
            if dst.exists():
                shutil.rmtree(dst)
            if self.save_dir.exists():
                shutil.copytree(self.save_dir, dst)
        except Exception as e:  # noqa: BLE001
            self.log(f"save snapshot {label} failed: {e}")

    def collect_errors(self) -> tuple[list[dict], list[str]]:
        paths = []
        for g in self.games:
            paths += g.log_files()
        errs, warns = self.errs.collect(paths)
        return errs, warns

    # ------------------------------------------------------------------ segments
    def run_segment(self, seg: str, fn) -> bool:
        self.monitor.set_segment(seg)
        self.log(f"################ {seg}: {TITLES[seg]} ################")
        rec = {"id": seg, "title": TITLES[seg], "start": now(), "start_state": self.state_summary()}
        ev0 = len(self.monitor.events)
        shots0 = len(self.shots)
        pre, pre_w = self.collect_errors()      # lines logged before this segment (boot, between segments)
        for e in pre:
            e["seg"] = f"(before {seg})"
        self.all_errors += pre
        self.warnings += [f"(before {seg}): {w}" for w in pre_w]
        t = time.time()
        if seg != "END":
            self.shot(f"{seg}_start")
        ok, detail = False, {}
        try:
            ok, detail = fn()
        except Exception as e:  # noqa: BLE001
            detail = {"status": f"harness exception {type(e).__name__}: {e}"}
            self.log(traceback.format_exc())
        rec["seconds"] = round(time.time() - t, 1)
        rec["end"] = now()
        rec["ok"] = bool(ok)
        rec["status"] = detail.get("status") or ("completes" if ok else "stops")
        if self.game is not None and self.game.alive() and seg != "END":
            self.shot(f"{seg}_end")
        rec["end_state"] = self.state_summary()
        rec["checkpoints"] = detail.get("checkpoints", [])
        seg_shots = list(detail.get("shots", [])) + self.shots[shots0:]
        rec["screenshot_requests"] = {"total": len(seg_shots), "ok": sum(1 for s in seg_shots if s.get("ok")),
                                      "failed": sum(1 for s in seg_shots if not s.get("ok")),
                                      "labels": [s.get("label") for s in seg_shots]}
        errs, warns = self.collect_errors()
        rec["script_errors"] = errs
        rec["warnings"] = len(warns)
        for e in errs:
            e["seg"] = seg
        self.all_errors += errs
        self.warnings += [f"{seg}: {w}" for w in warns]
        evs = self.monitor.events[ev0:]
        rec["music_cues"] = music_changes(evs)
        rec["deaths"] = sum(1 for e in evs if e["k"] == "msg_event" and "died" in str(e.get("text")))
        rec["saves"] = sum(1 for e in evs if e["k"] == "msg_saved")
        rec["hp_min"] = self.monitor.hp_min.get(seg)
        rec["problems"] = detail.get("problems", [])
        rec["result_file"] = detail.get("result_file")
        for b in detail.get("bugs", []) or []:
            self.bugs.append(dict(b, segment=seg))
        self.segments.append(rec)
        self.snapshot_saves(f"{seg}_end")
        self.log(f"################ {seg}: {'OK' if ok else 'STOPPED'} in {rec['seconds']}s - {rec['status']} "
                 f"(script errors {len(errs)}, music cues {len(rec['music_cues'])}, shots {rec['screenshot_requests']['total']})")
        self.write_result("running")
        return ok

    # ---------------------------------------------------------------- S1
    def seg_s1(self):
        import s1_continuation as S1
        out = self.out / "s1"
        chain = self

        class Launcher:
            """S1's relaunch hook: a new process on the SAME save folder, returning its bot at the title."""

            def __init__(self):
                self.save_dir = chain.save_dir
                self.proc = chain.game.proc

            def __call__(self):
                g = chain.relaunch()
                self.proc = g.proc
                return g.bot

        lnch = Launcher()
        res = S1.run(self.bot, out, launcher=lnch, game=self.game,
                     options={"save_dir": str(self.save_dir), "original_save": str(self.start_save)})
        write_json(out / "s1_result.json", res)
        ok = res.get("status") == "completes"
        cps = [{"name": c.get("step"), "ok": c.get("ok"), "seconds": c.get("seconds"), "area": c.get("area"),
                "error": c.get("error", "")} for c in res.get("checkpoints", [])]
        probs = [f"{p.get('step')}: {p.get('what')}" for p in res.get("problems", [])]
        return ok, {"status": res.get("status"), "checkpoints": cps, "shots": res.get("shots", []), "problems": probs,
                    "bugs": res.get("bugs", []), "result_file": str(out / "s1_result.json")}

    # ---------------------------------------------------------------- S2
    def seg_s2(self):
        import s2_orchard_quarry as S2
        out = self.out / "s2"
        orig = S2.Segment
        S2.Segment = chain_s2_class(S2, self.notes)      # S2.run() builds its Segment by this module-level name
        try:
            res = S2.run(self.bot, out, {"patchwalker": True, "visit_manor": False, "save_checkpoints": True,
                                          "reload_check": True})
        finally:
            S2.Segment = orig
        write_json(out / "s2_result.json", res)
        ok = res.get("status") == "completes"
        tm = res.get("timings", {})
        cps = [{"name": c.get("name"), "ok": c.get("ok"), "seconds": tm.get(c.get("name")), "at_s": c.get("t"),
                "hp": c.get("hp"), "detail": str(c.get("detail", ""))[:200]} for c in res.get("checkpoints", [])]
        st = res.get("status") if ok else f"stops: {res.get('stopped_at')}"
        detail = {"status": st, "checkpoints": cps, "shots": res.get("screenshots", []), "problems": res.get("problems", []),
                  "bugs": res.get("bugs", []), "result_file": str(out / "s2_result.json")}
        # the Warden, as the fixed build plays it (MP 12: slam lesson, pillar exposures, three pulses)
        ws = tm.get("warden_stats") or {}
        detail["warden"] = {"fight_s": tm.get("warden_fight_s"), "step_s": tm.get("quarry_warden"),
                            "exposures": tm.get("warden_exposures"), "damage_per_exposure": tm.get("warden_exposure_damage"),
                            "stats": ws, "log": res.get("warden_log", [])}
        self.notes.append(f"S2 Warden: fight {tm.get('warden_fight_s')} s, exposures={tm.get('warden_exposures')} "
                          f"damage/exposure={tm.get('warden_exposure_damage')} pulses_fired={(ws.get('game') or {}).get('pulses_fired')} "
                          f"charges={ws.get('charge_results')} hits_taken={ws.get('hits_taken')} deaths={ws.get('deaths')} "
                          f"climbs={ws.get('climbs')}")
        return ok, detail

    # ---------------------------------------------------------------- S3
    def seg_s3(self):
        import s3_manor as S3
        import s2_lib

        class ChainS3(S3.Segment):
            """S3 from natural state: a look calibration that also measures a 1080p window, and eating from the
            backpack when no food sits on the hotbar (the inventory panel pauses the world)."""

            def calibrate(self) -> bool:
                for amt in (0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0):
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
                if super().eat():
                    return True
                if not hasattr(self, "_bag"):
                    self._bag = s2_lib.Play(self.bot, self.out)
                ok = self._bag.eat_best(foods=FOOD_ITEMS)
                if ok:
                    self.fight["eats"] += 1
                    self.fight["bag_eats"] = self.fight.get("bag_eats", 0) + 1
                return ok

        out = self.out / "s3"
        seg = ChainS3(self.bot, out, optional=True, time_budget=1800.0, tether="pool")
        res = seg.run()
        write_json(out / "s3_result.json", res)
        ok = res.get("status") == "completes"
        cps = [{"name": c.get("step"), "ok": c.get("ok"), "seconds": c.get("seconds"), "at_s": c.get("at_s"),
                "hp": c.get("hp"), "error": c.get("error", "")} for c in res.get("checkpoints", [])]
        probs = [f"{p.get('kind')}: {p.get('text')}" for p in res.get("problems", [])]
        fight = res.get("fight", {})
        self.notes.append(f"S3 Velour: hp_min={fight.get('hp_min')} eats={fight.get('eats')} deaths={fight.get('deaths')} "
                          f"phases={[p.get('phase') for p in fight.get('phase_seen', [])]}")
        return ok, {"status": res.get("status"), "checkpoints": cps, "shots": res.get("screenshot_requests", []),
                    "problems": probs, "result_file": str(out / "s3_result.json")}

    # ---------------------------------------------------------------- S4
    def seg_s4(self):
        import s4_route as S4
        out = self.out / "s4"

        def step_read_preparations(p):
            """MP 11 step 8 (the S4 fixture set ch2_read_preparations): read the Ward-Keeper's notes at the lectern
            inside the Conservatory before linking. Never blocking (a recommendation in the game too)."""
            if p.flag("ch2_read_preparations") or p.flag("ch2_lamps_linked"):
                return True
            if p.area() != REACH:
                raise S4.StepFailed(f"read_preparations needs the Reach, in {p.area()}")
            p.nav((0.0, 0.0, 8.5), final_tol=0.6)
            ok = p.interact_with((3.25, 0.0, 9.25), ["Read the preparation notes"],
                                 check=lambda: p.flag("ch2_read_preparations"), stop=1.4)
            time.sleep(2.0)
            p.shot("preparation_notes")
            if not ok:
                p.problem("prepare", f"could not read the preparation notes: prompt={p.prompt()}")
            done = p.wait(lambda s: "ch2_prepare" in (s.get("chapter2") or {}).get("done", []), 5) is not None
            if ok and not done:
                p.problem("prepare", "ch2_read_preparations set but step ch2_prepare not completed")
            return True

        steps = [S4.STEPS[0], ("read_preparations", step_read_preparations)] + list(S4.STEPS[1:])
        res = S4.run(self.game, out, steps=steps)
        write_json(out / "s4_result.json", res)
        ok = not res.get("stopped_at")
        cps = [{"name": c.get("step"), "ok": c.get("ok"), "seconds": c.get("seconds"), "hp": c.get("hp"),
                "area": c.get("area"), "error": c.get("error", "")} for c in res.get("checkpoints", [])]
        probs = [f"{p.get('kind')}: {p.get('text')}" for p in res.get("problems", [])]
        return ok, {"status": "completes" if ok else f"stops at {res.get('stopped_at')}", "checkpoints": cps,
                    "shots": res.get("shots", []), "problems": probs, "result_file": str(out / "s4_result.json")}

    # ---------------------------------------------------------------- transitions
    def _players(self, out: Path):
        """Play layers on the current bot: the Chapter One helpers (playthrough.Play via S1's Seg: interact, gather,
        craft, pause menu) and the S4 layer (area-graph walking that fights threats on the way)."""
        import s1_continuation as S1
        import s4_route as S4
        out.mkdir(parents=True, exist_ok=True)
        seg_shots = []

        def shoot(label):
            return self.shot(label)["path"]
        p1 = S1.Seg(self.bot, out, shoot)
        p4 = S4.S4(self.game, out)
        return p1, p4, seg_shots

    def run_steps(self, seg: str, steps) -> tuple[bool, dict]:
        cps = []
        t_seg = time.time()
        for name, fn in steps:
            if time.time() > self.deadline:
                return False, {"status": f"stops at {name}: chain time budget used up", "checkpoints": cps}
            t = time.time()
            self.log(f"=== {seg} step {name} ===")
            ok, err = False, ""
            try:
                r = fn()
                ok = True if r is None else bool(r)
            except Exception as e:  # noqa: BLE001
                err = f"{type(e).__name__}: {e}"
                self.log(traceback.format_exc())
            try:
                self.bot.release_all()
            except Exception:  # noqa: BLE001
                pass
            s = self.st()
            cps.append({"name": name, "ok": ok, "seconds": round(time.time() - t, 1), "at_s": round(time.time() - t_seg, 1),
                        "area": s.get("area"), "pos": (s.get("player") or {}).get("pos"),
                        "hp": (s.get("player") or {}).get("hp"), "error": err})
            self.log(f"=== {seg} step {name}: {'OK' if ok else 'FAILED'} in {cps[-1]['seconds']}s {err}")
            self.shot(f"{seg}_{name}")
            if not ok:
                return False, {"status": f"stops at {name}: {err or 'check failed'}", "checkpoints": cps}
        return True, {"status": "completes", "checkpoints": cps}

    def wait_playing(self, area=None, timeout: float = 120.0) -> bool:
        return self.bot.wait_state(lambda s: s.get("mode") == "playing" and not s.get("ui_stack")
                                   and (area is None or s.get("area") == area), timeout) is not None

    def arch_travel(self, p1, arch_id: str, dest: str, dest_area: str) -> bool:
        """At a lit Lantern Road arch in the Reach: 'Travel the Lantern Road' -> dest."""
        e = p1.nearest_named(f"LanternArch_{arch_id}", 30)
        if e is None:
            e = p1.nearest(lambda n: "travel the lantern road" in str(n.get("text", "")).lower(), 30)
        if e is None:
            raise ChainStop(f"no LanternArch_{arch_id} within 30 m of {p1.pos()}")
        if not p1.press_interact_on(e, ["Travel the Lantern Road"], lambda: "confirm" in p1.ui(), stop=1.9):
            raise ChainStop(f"the {arch_id} arch offered no Lantern Road (prompt {p1.prompt()})")
        opts = p1.wait_button(dest, 5) or [b.get("text") for b in self.bot.buttons()]
        self.log(f"Lantern Road list at the {arch_id} arch: {opts}")
        if not self.bot.click_button(dest, exact=True):
            raise ChainStop(f"no {dest!r} in the Lantern Road list {opts}")
        if not self.wait_playing(dest_area, 120):
            raise ChainStop(f"did not arrive in {dest_area} (area {self.st().get('area')}, mode {self.st().get('mode')})")
        time.sleep(1.5)
        self.bot.calibrate_look()
        return True

    def ward_stone_travel(self, p1, dest: str, dest_area: str = REACH) -> bool:
        e = p1.nearest_named("WardStone", 60)
        if e is None:
            # the telemetry lists only the 60 nearest objects: from the berry bushes the stone can drop out of it
            p1.goto((0.0, 4.0), tol=2.5, sprint=True, timeout=40)
            e = p1.nearest_named("WardStone", 60)
        if e is None:
            raise ChainStop(f"no Ward Stone near the Haven (at {p1.pos()})")
        if not p1.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p1.ui(), stop=2.2):
            raise ChainStop(f"the Ward Stone menu did not open (prompt {p1.prompt()})")
        if not p1.wait_button("Travel the Lantern Road", 5):
            raise ChainStop(f"no 'Travel the Lantern Road' in the Ward Stone menu {[b['text'] for b in self.bot.buttons()]}")
        self.bot.click_button("Travel the Lantern Road", exact=True)
        opts = p1.wait_button(dest, 5) or [b.get("text") for b in self.bot.buttons()]
        self.log(f"Lantern Road list at the Ward Stone: {opts}")
        if not self.bot.click_button(dest, exact=True):
            raise ChainStop(f"no {dest!r} in the Ward Stone's Lantern Road list {opts}")
        if not self.wait_playing(dest_area, 120):
            raise ChainStop(f"did not arrive in {dest_area}")
        time.sleep(1.5)
        self.bot.calibrate_look()
        return True

    def home_rest(self, p1, tag: str) -> bool:
        """At the Haven: sleep in the bed (full heal, saves), harvest a ripe crop, pick berries, cook a Hearty
        Stew at the campfire when there is sweetroot, craft Berry Snacks by hand. Only the bed is required."""
        rep = {"hp_before": p1.hp(), "food_before": {k: p1.inv(k) for k in FOOD_ITEMS if p1.inv(k)}}
        # 1) sleep
        bed = p1.nearest(lambda n: "sleep until morning" in str(n.get("text", "")).lower(), 70)
        if bed is None:
            raise ChainStop("no bed ('Sleep until morning') near the Haven")
        since = p1.msg_t()
        ok = p1.press_interact_on(bed, ["Sleep until morning"],
                                  lambda: p1.hp() >= 99.5 or any("Slept" in str(m.get("text", "")) for m in p1.recent_msgs(since)),
                                  stop=1.5)
        self.wait_playing(SURFACE, 30)
        time.sleep(1.0)
        rep["slept"] = bool(ok)
        rep["hp_after_sleep"] = p1.hp()
        rep["sleep_msgs"] = [m.get("text") for m in p1.recent_msgs(since) if m.get("k") in ("notify", "saved", "hint")]
        if not ok or p1.hp() < 99.0:
            raise ChainStop(f"sleeping did not restore health (hp {p1.hp()}, prompt {p1.prompt()})")
        self.bot.calibrate_look()
        # 2) a ripe crop in the plot (the real save planted sweetroot)
        plot = p1.nearest(lambda n: str(n.get("text", "")).startswith("Harvest"), 70)
        if plot is not None:
            n0 = sum(int(v) for v in (p1.st().get("inv") or {}).values())
            got = p1.press_interact_on(plot, ["Harvest"], lambda: sum(int(v) for v in (p1.st().get("inv") or {}).values()) > n0,
                                       stop=1.6)
            rep["harvest"] = {"prompt": plot.get("text"), "ok": bool(got), "sweetroot": p1.inv("sweetroot")}
            time.sleep(0.5)
        # 3) berries from the bushes west of the Haven (2-4 each, regrow in 12 h)
        b0 = p1.inv("berries")
        try:
            p1.gather_hand(["Berr"], "berries", b0 + 14, maxd=50, exclude=("rose", "regrow"))
        except Exception as e:  # noqa: BLE001  (fewer bushes ripe: take what there is)
            self.log(f"berries: {e}")
        rep["berries_picked"] = p1.inv("berries") - b0
        # 4) cooking / crafting (the Haven campfire; hand recipes anywhere)
        if p1.inv("sweetroot") >= 2 and p1.inv("berries") >= 3:
            try:
                p1.craft("Hearty Stew", station_tab="Campfire", item="hearty_stew")
            except Exception as e:  # noqa: BLE001
                self.log(f"hearty stew: {e}")
                p1.close_panels()
        n = p1.inv("berries") // 4
        if n > 0:
            try:
                p1.craft("Berry Snack", times=n, item="berry_snack")
            except Exception as e:  # noqa: BLE001
                self.log(f"berry snack: {e}")
                p1.close_panels()
        p1.close_panels()
        rep["hp_after"] = p1.hp()
        rep["food_after"] = {k: p1.inv(k) for k in FOOD_ITEMS if p1.inv(k)}
        self.home_reports[tag] = rep
        self.log(f"home rest {tag}: {rep}")
        return True

    def seg_t23(self):
        import s2_orchard_quarry as S2
        out = self.out / "t23"
        p1, p4, _ = self._players(out)
        self.home_reports = getattr(self, "home_reports", {})

        def quarry_to_arch():
            here = xz(p4.pos())
            u, v = S2.to_uv(here)
            if u > 16.0 and dist2(here, S2.LAMP) < 8:
                # down from the lamp shelf: the shelf, the lowered gangway to its foot (walking, like the climb)
                if not p4.route(list(reversed(S2.GANGWAY)), tol=1.2, sprint=False, fight=True):
                    raise ChainStop(f"could not walk down the gangway (at {p4.pos()}, uv {S2.to_uv(xz(p4.pos()))})")
            pts = []
            if S2.q_level(S2.to_uv(xz(p4.pos()))) >= 1:
                # the L2 bench west to the ramps (the winch route S2 came up by), down to the lower terrace
                pts += list(reversed(S2.TO_WINCH))
            pts += [S2.IRON_PREF[0], (64.3, 36.1)]
            if not p4.route(pts, tol=1.6, sprint=True, fight=True):
                raise ChainStop(f"could not walk from the quarry lamp to the quarry arch (at {p4.pos()})")
            return dist2(xz(p4.pos()), S2.QUARRY_ARCH) < 6.0

        def home_via_quarry_arch():
            return self.arch_travel(p1, "quarry", "The Haven (home)", SURFACE)

        def rest():
            return self.home_rest(p1, "T23")

        def to_commons():
            return self.ward_stone_travel(p1, "Lanternwake Commons")

        def road_to_manor():
            # the Commons -> the crossroads south of the Commons -> west round the Conservatory -> the north road ->
            # through the manor arch to its spawn point (where the S3 fixture used to start)
            pts = [(1.5, 70.0), (2.5, 68.0), (2.5, 53.0), (0.0, 45.0), (0.0, 38.5), (0.0, 30.0), (0.0, 22.0),
                   (-8.0, 12.0), (-9.0, 2.0), (0.5, -8.0), (0.5, -12.0), (2.5, -24.0), (5.0, -34.0), (8.1, -44.3),
                   (10.0, -50.0), (10.9, -52.8)]
            if not p4.route(pts, tol=1.8, sprint=True, fight=True):
                raise ChainStop(f"the road to the manor arch is blocked at {p4.pos()}")
            return dist2(xz(p4.pos()), (10.9, -52.8)) < 3.0

        return self.run_steps("T23", [("quarry_to_arch", quarry_to_arch), ("lantern_road_home", home_via_quarry_arch),
                                      ("home_rest", rest), ("lantern_road_commons", to_commons),
                                      ("road_to_manor_arch", road_to_manor)])

    def seg_t34(self):
        import s3_manor as S3
        out = self.out / "t34"
        p1, p4, _ = self._players(out)
        self.home_reports = getattr(self, "home_reports", {})

        def grounds_to_arch():
            if self.st().get("area") != REACH:
                raise ChainStop(f"T34 starts in the Reach, in {self.st().get('area')}")
            pts = list(reversed(S3.GROUNDS_PATH)) + [(10.9, -52.8)]
            here = xz(p4.pos())
            i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
            if not p4.route(pts[i:], tol=1.4, sprint=True, fight=True):
                raise ChainStop(f"could not walk from the manor door to the manor arch (at {p4.pos()})")
            return True

        def home_via_manor_arch():
            return self.arch_travel(p1, "manor", "The Haven (home)", SURFACE)

        def rest():
            return self.home_rest(p1, "T34")

        def to_commons():
            return self.ward_stone_travel(p1, "Lanternwake Commons")

        return self.run_steps("T34", [("grounds_to_manor_arch", grounds_to_arch), ("lantern_road_home", home_via_manor_arch),
                                      ("home_rest", rest), ("lantern_road_commons", to_commons)])

    # ---------------------------------------------------------------- the end: relaunch + Continue
    def seg_end(self):
        """Pause menu -> Save Game -> Quit Game -> Save & Quit (a player's way out), relaunch, Continue."""
        import playthrough
        pp = playthrough.Play(SimpleNamespace(bot=self.bot, shot=lambda label: self.shot(label)["path"]))
        saved = pp.pause_save()
        s = self.st()
        before = {"area": s.get("area"), "inv": s.get("inv"), "keys": s.get("keys"),
                  "pos": (s.get("player") or {}).get("pos")}
        self.shot("END_before_quit")
        quit_how = "killed (no quit path)"
        self.bot.tap("ESC")
        if self.bot.wait_state(lambda st: "pause" in (st.get("ui_stack") or []), 3.0) and \
                self.bot.click_button("Quit Game", exact=True, timeout=3.0):
            if self.bot.click_button("Save & Quit", exact=True, timeout=4.0):
                quit_how = "pause menu: Quit Game -> Save & Quit"
            elif self.bot.click_button("Quit without saving", exact=True, timeout=2.0):
                quit_how = "pause menu: Quit Game -> Quit without saving (after Save Game)"
        exited = self.game.wait_exit(20.0)
        g = self.relaunch()
        bot = g.bot
        rec = {"saved_before_quit": saved, "quit": quit_how, "exited_by_itself": exited, "before": before}
        if not bot.wait_state(lambda st: st.get("mode") == "title" and any(b.get("text") == "Continue" for b in st.get("buttons", [])), 120):
            return False, {"status": "no title / Continue after the relaunch", **rec}
        t0 = time.time()
        bot.click_button("Continue", exact=True, timeout=10)
        if not self.wait_playing(None, 120):
            return False, {"status": "Continue never reached gameplay", **rec}
        rec["continue_load_s"] = round(time.time() - t0, 1)
        time.sleep(2.0)
        s = self.st()
        c2 = s.get("chapter2") or {}
        after = {"area": s.get("area"), "inv": s.get("inv"), "keys": s.get("keys"), "pos": (s.get("player") or {}).get("pos"),
                 "finished": c2.get("finished"), "chapter_two_complete": "chapter_two_complete" in s.get("flags", []),
                 "ch2_done": len(c2.get("done") or []), "tracker": s.get("tracker")}
        rec["after"] = after
        same_items = after["inv"] == before["inv"] and after["keys"] == before["keys"]
        rec["same_items"] = same_items
        if not same_items:
            rec["item_diff"] = {k: [(before["inv"] or {}).get(k), (after["inv"] or {}).get(k)]
                                for k in set(before["inv"] or {}) | set(after["inv"] or {})
                                if (before["inv"] or {}).get(k) != (after["inv"] or {}).get(k)}
        self.bot.hold("W", 0.8)
        rec["moved"] = dist2(xz(self.bot.pos()), xz(after["pos"] or [0, 0, 0])) > 0.3
        ok = bool(after["finished"]) and after["chapter_two_complete"] and same_items and after["area"] == before["area"]
        cps = [{"name": "relaunch_continue", "ok": ok, "seconds": rec["continue_load_s"]}]
        self.end_check = rec
        return ok, {"status": "completes" if ok else f"relaunch check failed: {rec}", "checkpoints": cps}

    # ---------------------------------------------------------------- driver
    def run(self):
        cfg = self.cfg
        status = "running"
        order = SEGMENTS[SEGMENTS.index(cfg.from_seg):]
        if cfg.until:
            order = order[:order.index(cfg.until) + 1]
        fns = {"S1": self.seg_s1, "S2": self.seg_s2, "T23": self.seg_t23, "S3": self.seg_s3, "T34": self.seg_t34,
               "S4": self.seg_s4, "END": self.seg_end}
        self.monitor.start()
        try:
            self.save_dir.mkdir(parents=True, exist_ok=True)
            bak = Path(self.start_save).with_name("slot1.bak.json") if cfg.from_seg != "S1" else None
            C.prepare_saves(self.save_dir, Path(self.start_save), bak)
            self.launch()
            if cfg.from_seg != "S1":
                # diagnostic resume from a game-written save: Continue on the title first
                if not self.bot.wait_state(lambda s: s.get("mode") == "title" and any(b.get("text") == "Continue" for b in s.get("buttons", [])), 120):
                    raise ChainStop("no title / Continue")
                self.bot.click_button("Continue", exact=True, timeout=10)
                if not self.wait_playing(None, 120):
                    raise ChainStop("Continue never reached gameplay")
                time.sleep(2.0)
                self.bot.calibrate_look()
            for seg in order:
                if time.time() > self.deadline:
                    status = f"stops before {seg}: chain time budget ({cfg.max_minutes} min) used up"
                    break
                if not self.run_segment(seg, fns[seg]):
                    status = f"stops in {seg}: {self.segments[-1]['status']}"
                    break
            else:
                status = "completes" if order[-1] == "END" else f"completes up to {order[-1]} (--until)"
        except Exception as e:  # noqa: BLE001
            status = f"harness error {type(e).__name__}: {e}"
            self.log(traceback.format_exc())
        finally:
            for g in self.games:
                g.stop()
            time.sleep(0.8)
            self.monitor.stop()
            self.monitor.join(5.0)
            errs, warns = self.collect_errors()
            for e in errs:
                e["seg"] = "(after the last segment)"
            self.all_errors += errs
            self.warnings += warns
        self.write_result(status)
        return status

    def write_result(self, status: str):
        cfg = self.cfg
        total = round(time.time() - self.t0, 1)
        music = music_changes(self.monitor.events)
        titles = cue_titles(cfg.project) if not cfg.exe else cue_titles(ROOT / "game")
        for m in music:
            m["title"] = titles.get(m["cue"], "")
        err_groups: dict = {}
        for e in self.all_errors:
            key = e.get("at") or e.get("line")
            g = err_groups.setdefault(key, {"count": 0, "line": e.get("line"), "at": e.get("at"), "segments": []})
            g["count"] += 1
            if e.get("seg") not in g["segments"]:
                g["segments"].append(e.get("seg"))
        res = {
            "chain": "Chapter Two natural route (MP 20.4 Run A): S1 -> S2 -> T23 -> S3 -> T34 -> S4 -> relaunch",
            "status": status,
            "natural": cfg.from_seg == "S1" and Path(self.start_save).name == FIXTURE_NAME,
            "start_save": str(self.start_save),
            "resumed_from": None if cfg.from_seg == "S1" else cfg.from_seg,
            "mode": {"headless": cfg.headless, "packaged_exe": str(cfg.exe) if cfg.exe else None, "project": str(cfg.project),
                     "godot": str(cfg.godot or (CONSOLE_EXE if cfg.headless else EDITOR_EXE)), "muted": cfg.mute,
                     "qa_window": None if cfg.headless else cfg.rect, "seed": cfg.seed},
            "started": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(self.t0)),
            "total_seconds": total,
            "durations": {s["id"]: s["seconds"] for s in self.segments},
            "segments": self.segments,
            "home_rests": getattr(self, "home_reports", {}),
            "end_check": getattr(self, "end_check", None),
            "music_cue_changes": music,
            "script_errors": {"total": len(self.all_errors), "unique": list(err_groups.values())},
            "warnings": {"total": len(self.warnings), "sample": self.warnings[:30]},
            "screenshot_requests": {"total": sum(s["screenshot_requests"]["total"] for s in self.segments),
                                    "ok": sum(s["screenshot_requests"]["ok"] for s in self.segments),
                                    "failed": sum(s["screenshot_requests"]["failed"] for s in self.segments)},
            "focus_report": {"telemetry_frames": self.monitor.frames, "frames_focused": self.monitor.frames_focused,
                             "frames_mouse_captured": self.monitor.frames_captured},
            "notes": self.notes,
            "processes": [{"name": g.name, "port": g.port, "cmd": g.cmd, "godot_log": str(g.godot_log)} for g in self.games],
        }
        write_json(self.out / "chain_result.json", res)
        bugs = list(self.bugs)
        for g in err_groups.values():
            bugs.append({"title": f"SCRIPT ERROR during the natural chain: {g['line'][:160]}", "severity": "major",
                         "steps": f"python tools/qa/ch2/chain.py (segments {g['segments']})",
                         "expected": "no script errors", "actual": f"{g['count']}x {g['line']} {g['at']}",
                         "evidence": [str(x.godot_log) for x in self.games]})
        write_json(self.out / "bugs.json", bugs)


# ============================================================================================ CLI
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--headless", action="store_true", help="no window (default)")
    mode.add_argument("--visible", action="store_true", help="second-monitor window, virtual input, sound on")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--dev", action="store_true", help="run the source project (default)")
    src.add_argument("--exe", nargs="?", const=str(PACKAGED_EXE), default=None,
                     help=f"run a packaged build (default {PACKAGED_EXE})")
    ap.add_argument("--project", default=str(ROOT / "game"), help="game folder of the source project (--dev)")
    ap.add_argument("--godot", default="", help="Godot binary for --dev (default: console exe headless, editor exe visible)")
    ap.add_argument("--out", default="", help="run folder (default qa/tmp/bot/chain/run_<timestamp>)")
    ap.add_argument("--port", type=int, default=7901, help="first QA input port (one per launched process)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--max-minutes", type=float, default=80.0, help="bound for the whole chain and each game process")
    ap.add_argument("--mute", action="store_true", help="--qa-mute (visible runs keep the sound on by default)")
    ap.add_argument("--qa-window", default=SECOND_MONITOR_RECT, help="visible: x,y,w,h of the game window")
    ap.add_argument("--start-save", default="", help="diagnostic resume: a save folder or slot1.json the game wrote")
    ap.add_argument("--from", dest="from_seg", default="S1", choices=SEGMENTS)
    ap.add_argument("--until", default="", choices=[""] + SEGMENTS)
    ap.add_argument("--dry-run", action="store_true", help="print the game launch command for these options and exit")
    a = ap.parse_args(argv)
    headless = not a.visible
    out = Path(a.out) if a.out else ROOT / "qa" / "tmp" / "bot" / "chain" / time.strftime("run_%Y%m%d_%H%M%S")
    out = out.resolve()
    if not a.dry_run:
        if out.exists():
            shutil.rmtree(out)          # a run folder is always fresh (only ever point --out at a QA folder)
        out.mkdir(parents=True)
    project = Path(a.project).resolve()
    if a.from_seg != "S1":
        if not a.start_save:
            ap.error("--from needs --start-save (a save the game wrote at that boundary, e.g. <run>/checkpoints/S2_end)")
        sp = Path(a.start_save)
        start_save = (sp / "slot1.json") if sp.is_dir() else sp
    else:
        start_save = Path(a.start_save) if a.start_save else project / "tests" / "fixtures" / "saves" / FIXTURE_NAME
    if not start_save.exists():
        ap.error(f"start save {start_save} not found")
    exe = Path(a.exe).resolve() if a.exe else None
    if exe is not None and not exe.exists():
        ap.error(f"packaged build {exe} not found")
    cfg = SimpleNamespace(out=out, headless=headless, exe=exe, project=project, godot=Path(a.godot) if a.godot else None,
                          port=a.port, seed=a.seed, max_minutes=a.max_minutes, mute=a.mute,
                          rect=parse_rect(a.qa_window), start_save=start_save.resolve(), from_seg=a.from_seg, until=a.until,
                          dry_run=a.dry_run)
    if a.dry_run:
        g = ChainGame(cfg, 1, out / "saves", a.port)
        print(json.dumps({"mode": "headless" if headless else f"visible at {cfg.rect}, sound {'off' if a.mute else 'on'}",
                          "build": str(exe) if exe else f"source {project}", "start_save": str(start_save),
                          "cmd": g.command()}, indent=1))
        return 0
    ch = Chain(cfg)
    ch.log(f"out={out} headless={headless} exe={exe} project={project} start_save={start_save} from={a.from_seg} until={a.until}")
    status = ch.run()
    res = json.loads((out / "chain_result.json").read_text(encoding="utf-8"))
    print(f"\n{'seg':4} {'ok':5} {'seconds':>8} {'deaths':>6} {'hp min':>6} {'errors':>6} {'cues':>5} {'shots':>5}  hp/food at the end")
    for s in res["segments"]:
        es = s.get("end_state") or {}
        print(f"{s['id']:4} {str(s['ok']):5} {s['seconds']:8} {s['deaths']:6} {str(s.get('hp_min')):>6} "
              f"{len(s['script_errors']):6} {len(s['music_cues']):5} {s['screenshot_requests']['total']:5}  "
              f"{es.get('hp')} {es.get('food')}")
    print(json.dumps({"status": status, "total_seconds": res["total_seconds"], "durations": res["durations"],
                      "script_errors": res["script_errors"]["total"], "music_cue_changes": len(res["music_cue_changes"]),
                      "screenshot_requests": res["screenshot_requests"], "out": str(out)}, indent=1))
    return 0 if status == "completes" else 1


if __name__ == "__main__":
    sys.exit(main())
