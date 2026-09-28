"""Chapter Two route segment S3 - Moonveil Manor, played with NORMAL INPUTS by the external QA bot.

From the Reach (manor arch, the three lamps' locations known) to the Reach again (via the balcony shortcut):
  reach: light the manor arch, walk the grounds path, enter the manor
  cloakroom -> Looking-Glass Hall (read the card, light the practice candle: mm_mirror_clue; the hall's Velvet Wing)
  [optional] Powder Room velvet scrap 1
  Ballroom: read the dance card, light the hearth candle, turn candelabra c3 + c4 (flame S->c1->c3->c4->T)
            -> mm_ballroom_solved; rest at the ballroom candles (checkpoint + save)
  [optional] Musicians' Nook velvet scrap 2
  Count's Gallery: light the dark teaching candle -> Count Velour (dash sidesteps, tether breaks in a candle pool /
            with hits, bat lanes from a lane-safe spot, strikes in his windows, relight the candle he darkens)
  [optional] Dressing Room velvet scrap 3, talk to the freed Count
  Conservatory Balcony: wake the Moonveil lantern (ch2_manor_lamp_lit -> Manor Seal), rest, unbolt the shortcut gate,
            take the garden stair down to the grounds (back in the Reach).

The bot sees the game ONLY through the read-only QA telemetry (tools/qa/hhbot.py Telemetry; game/src/qa/qa_telemetry.gd)
and acts ONLY through the virtual keyboard/mouse (src/qa/qa_input.gd). No teleports, flags or items.
INFORMATION ADVANTAGE (label for reports): the bot knows the authored coordinates of the rooms / props from
data/manor_layout.gd and the puzzle solution from reading candle_route.gd; it reads enemy states, hp and "vuln" from
telemetry, and reads on-screen captions (the game's own accessibility captions) with their timestamps. It does not
see the bat lanes, the dash lane or the tether: it positions itself on a spot that is lane-safe by construction
(see LANE_SAFE_SPOTS) and sidesteps perpendicular to the Count.

API:   run(bot, out_dir) -> dict      (bot = hhbot.Bot on a running game at the title or already playing in the Reach)
CLI:   python tools/qa/ch2/s3_manor.py --run-dir qa/tmp/bot/s3/run1 --port 7301 [--save <slot1.json>] [--tether pool|hit|los]
       (headless, source build, virtual input). Without --save the start is s3_fixture.py (labelled "DIAGNOSTIC FIXTURE
       START"); with --save any slot1.json in the Reach or inside the manor works - steps already done are skipped by
       their flags (e.g. qa/tmp/bot/s3/start_ballroom/slot1.json, written by the game at the ballroom candles).
       Writes <run-dir>/s3_result.json, s3_auto_findings.json, s3_bot.log, s3_telemetry.jsonl, s3_godot_stdout.log.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from s3_botlib import HeadlessGame, angle_diff, dist2, grep_log, xz  # noqa: E402
import s3_fixture  # noqa: E402

MANOR = "moonveil_manor"
REACH = "hallowmere_reach"

# --- Reach (data/hallowmere_layout.gd, data/manor_layout.gd GROUNDS) --------------------------------------------
ARCH = (10.0, -50.0)
ARCH_STAND = (10.9, -51.7)
GROUNDS_PATH = [(12.4, -59.5), (14.8, -66.5), (16.9, -73.5), (17.9, -79.5), (18.0, -83.4)]
DOOR = (18.0, -85.95)
DOOR_STAND = (18.0, -84.2)

# --- Manor interior (data/manor_layout.gd) ------------------------------------------------------------------------
HALL_IN = [(0.0, -8.6), (0.0, -11.6), (0.0, -13.2)]
HALL_CARD = (-1.6, -14.0)
HALL_CARD_STAND = (-0.3, -14.0)
PRACTICE = (-2.1, -17.0)
PRACTICE_STAND = (-0.8, -16.9)
POWDER_IN = [(0.0, -20.2), (3.0, -20.2), (5.2, -20.2), (7.0, -19.6)]
SCRAP1 = (8.2, -19.2)
HALL_TO_BALLROOM = [(0.0, -20.2), (0.0, -26.0), (0.0, -29.5), (0.0, -32.4)]
BALLROOM_TO_CARD = [(-1.5, -36.8), (-6.4, -36.4)]
DANCE_CARD = (-7.4, -34.8)
DANCE_CARD_STAND = (-7.4, -36.1)
HEARTH = (-3.6, -34.2)
HEARTH_STAND = (-3.4, -35.6)
C3 = (-4.5, -44.6)
C3_STAND = (-3.0, -44.6)
C4 = (4.5, -44.6)
C4_STAND = (3.0, -44.6)
BALL_CP = (7.0, -33.2)
BALL_CP_STAND = (5.6, -33.6)
NOOK_IN = [(-2.0, -41.0), (-8.8, -43.8), (-8.8, -47.0), (-10.4, -48.1), (-12.2, -48.1), (-13.8, -48.0)]
SCRAP2 = (-15.2, -48.0)
TO_GALLERY = [(0.0, -41.0), (0.0, -47.5), (0.0, -49.8), (0.0, -52.4)]
ARENA_C = (0.0, -64.5)
CANDLES = {"north": (0.0, -72.0), "southwest": (-6.5, -60.75), "southeast": (6.5, -60.75)}
TEACH = "southwest"
TEACH_STAND = (-4.9, -59.9)
COVER = [(-8.5, -70.5), (8.5, -70.5), (-9.2, -57.4), (9.2, -57.4)]
POOL_R = 3.2
# bat_swarm.gd: lanes are thirds of a 24 m square around ARENA_C (the safe lane is 40 % wide, in the middle when
# Krystal stands in an OUTER third at sampling). A point with |dx|, |dz| in (4.0, 4.8) m from the centre is in an
# outer third for choose_safe() in BOTH orientations (so the safe lane is the middle one) AND inside that middle
# safe lane (|v| < 4.8) -> standing still there is never swept, for either pattern. Both spots also lie inside the
# SW / SE ward-candle pools (2.2 m from the candle): tether breaks, the true bat is revealed early.
LANE_SAFE_SPOTS = [(-4.4, -60.1), (4.4, -60.1)]
PHASE1_SPOTS = [(-2.2, -62.3), (2.2, -62.3)]          # just OUTSIDE the south pools (the drain can be chosen)
DRESSING_IN = [(0.0, -64.5), (8.0, -64.8), (12.3, -64.8), (14.4, -64.8), (16.4, -65.4)]
SCRAP3 = (18.0, -66.2)
RESIDENT = (-3.4, -73.6)
TO_BALCONY = [(2.2, -67.0), (2.2, -75.8), (0.0, -76.8), (0.0, -78.6), (0.0, -80.0), (0.0, -82.5), (0.0, -84.5),
              (0.0, -88.0), (0.0, -90.2)]
LANTERN = (0.0, -92.2)
LANTERN_STAND = (0.0, -90.3)
BALC_CP = (6.2, -85.4)
BALC_CP_STAND = (4.8, -85.9)
GATE = (9.25, -89.0)
GATE_STAND = (7.7, -89.0)
GARDEN_STAIR = (13.2, -89.0)
GARDEN_STAND = (11.9, -89.0)
FROM_BALLROOM_CP_TO_GALLERY = [(4.0, -36.0), (0.0, -41.0), (0.0, -49.8), (0.0, -52.4)]

# Room rectangles (x0, x1, z0, z1) and doorways (data/manor_layout.gd ROOMS / openings) for room-to-room navigation.
ROOMS = {
    "cloakroom": (-5.0, 5.0, -10.0, 0.0), "hall": (-3.5, 3.5, -30.5, -10.5), "powder": (4.0, 9.0, -23.0, -17.5),
    "ballroom": (-11.0, 11.0, -51.0, -31.0), "nook": (-16.5, -11.5, -50.5, -45.5), "gallery": (-13.0, 13.0, -77.5, -51.5),
    "dressing": (13.5, 19.5, -67.5, -61.5), "stair": (-2.0, 2.0, -83.0, -78.0), "balcony": (-9.0, 9.0, -97.0, -83.5),
    "landing": (9.5, 13.5, -91.5, -86.5),
}
# (room A, room B, points walked from A into B)
DOORS = [
    ("cloakroom", "hall", [(0.0, -9.2), (0.0, -11.4)]),
    ("hall", "powder", [(2.4, -20.2), (5.0, -20.2)]),
    ("hall", "ballroom", [(0.0, -29.6), (0.0, -32.2)]),
    ("ballroom", "nook", [(-8.8, -43.8), (-8.8, -47.0), (-10.4, -48.1), (-12.2, -48.1)]),
    ("ballroom", "gallery", [(0.0, -49.9), (0.0, -52.7)]),
    ("gallery", "dressing", [(12.0, -64.8), (14.5, -64.8)]),
    ("gallery", "stair", [(0.0, -76.4), (0.0, -78.9)]),
    ("stair", "balcony", [(0.0, -82.4), (0.0, -84.6)]),
    ("balcony", "landing", [(8.0, -89.0), (10.5, -89.0)]),
]


def room_of(p, grow: float = 0.3) -> str:
    for rid, (x0, x1, z0, z1) in ROOMS.items():
        if x0 - grow <= p[0] <= x1 + grow and z0 - grow <= p[1] <= z1 + grow:
            return rid
    return ""


def room_path(a: str, b: str) -> list:
    """Doorway point lists from room a to room b (breadth-first over DOORS)."""
    if a == b or not a or not b:
        return []
    prev = {a: None}
    queue = [a]
    while queue:
        r = queue.pop(0)
        for ra, rb, pts in DOORS:
            for x, y, seq in ((ra, rb, pts), (rb, ra, list(reversed(pts)))):
                if x == r and y not in prev:
                    prev[y] = (r, seq)
                    queue.append(y)
    if b not in prev:
        return []
    out = []
    cur = b
    while prev[cur] is not None:
        r, seq = prev[cur]
        out.insert(0, seq)
        cur = r
    return out


WINDOW_STATES = {"recoil", "drain_rest", "reform", "stagger", "channel_rest", "drain_tele", "drain", "channel"}
DASH_STATES = {"bow", "flourish", "final_tell", "dash"}
BAT_STATES = {"disperse", "bats"}
FOODS = ("hearty_stew", "pumpkin_soup", "roseberry_tart", "berry_snack", "glowcap_skewer", "pumpkin_biscuit",
         "roseberries", "sweetroot", "berries")


class StepFailed(Exception):
    pass


class Segment:
    def __init__(self, bot, out_dir: str | Path, optional: bool = True, time_budget: float = 1800.0, tether: str = "pool"):
        self.bot = bot
        self.tether = tether          # how the bot breaks the Count's drain tether: pool | hit | los
        self.out = Path(out_dir).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        self.optional = optional
        self.log = bot.log
        self.t0 = time.time()
        self.deadline = self.t0 + time_budget
        self.ppd = 0.26          # window px per degree (calibrated)
        self.look_inv = 1.0
        self._seq_ok = 0
        self.shots: list[dict] = []
        self.problems: list[dict] = []
        self.checkpoints: list[dict] = []
        self.fight: dict = {"dodges": 0, "strikes": 0, "eats": 0, "deaths": 0, "encounter_starts": 0,
                            "phase_seen": [], "states_seen": {}, "pool_breaks": 0, "relights": 0,
                            "hits_taken": 0, "hp_min": 100.0, "velour_hp_trace": []}
        self._last_msg_t = -1.0
        self._captions: list[dict] = []
        self._ignored: dict = {}

    # ================================================================ observation
    def st(self) -> dict:
        return self.bot.state()

    def seq(self) -> int:
        return int(self.st().get("seq", 0))

    def wait_frames(self, n: int = 1, timeout: float = 2.0):
        start = self.seq()
        t = time.time()
        while time.time() - t < timeout:
            if self.seq() >= start + n:
                return
            time.sleep(0.02)

    def flags(self) -> set:
        return set(self.st().get("flags", []))

    def flag(self, f: str) -> bool:
        return f in self.flags()

    def pos(self):
        return self.bot.pos()

    def me(self):
        return xz(self.pos())

    def hp(self) -> float:
        return float(self.st().get("player", {}).get("hp", 100.0))

    def area(self) -> str:
        return str(self.st().get("area", ""))

    def mode(self) -> str:
        return str(self.st().get("mode", ""))

    def prompt(self) -> dict:
        return self.st().get("player", {}).get("prompt", {}) or {}

    def inv(self, item: str) -> int:
        s = self.st()
        return int(s.get("inv", {}).get(item, 0)) + int(s.get("keys", {}).get(item, 0))

    def nearby(self, pred=None, maxd: float = 80.0) -> list:
        return [e for e in self.st().get("nearby", []) if e.get("dist", 999) <= maxd and (pred is None or pred(e))]

    def enemy(self, name_part: str):
        for e in self.st().get("nearby", []):
            if e.get("g") == "enemy" and name_part in e.get("name", ""):
                return e
        return None

    def new_messages(self) -> list:
        """Messages (captions, says, notifies, quest...) newer than the last call, oldest first."""
        out = []
        for m in self.st().get("messages", []):
            t = float(m.get("t", 0.0))
            if t > self._last_msg_t:
                out.append(m)
        if out:
            self._last_msg_t = max(float(m.get("t", 0.0)) for m in out)
            for m in out:
                if m.get("k") in ("caption", "say", "notify", "quest", "saved", "event"):
                    self._captions.append({"t": m.get("t"), "k": m.get("k"), "text": m.get("text")})
        return out

    def elapsed(self) -> float:
        return round(time.time() - self.t0, 1)

    # ================================================================ evidence
    def shot(self, label: str):
        p = self.out / f"s3_{len(self.shots) + 1:02d}_{label}.png"
        rec = {"label": label, "path": str(p), "t": self.elapsed(), "ok": False}
        try:
            self.bot.win.screenshot(p)
            rec["ok"] = p.exists()
        except Exception as e:  # noqa: BLE001  (headless: the game refuses shots - expected)
            rec["error"] = str(e)[:160]
        self.shots.append(rec)

    def problem(self, kind: str, text: str, **extra):
        rec = {"kind": kind, "text": text, "t": self.elapsed(), "pos": self.pos(), "area": self.area()}
        rec.update(extra)
        self.problems.append(rec)
        self.log(f"PROBLEM [{kind}] {text}")

    # ================================================================ looking / moving
    def calibrate(self) -> bool:
        """Window px of virtual mouse motion per degree of camera yaw (headless: ~0.26 px/deg)."""
        for amt in (0.25, 0.5, 1.0, 2.0, 4.0):
            self.wait_frames(2)
            y0 = self.bot.cam_yaw()
            if y0 is None:
                time.sleep(0.3)
                continue
            self.bot.win.mouse_move(amt, 0)
            self.wait_frames(3)
            y1 = self.bot.cam_yaw()
            d = angle_diff(y1, y0)
            if 3.0 <= abs(d) <= 150.0:
                self.ppd = amt / abs(d)
                self.look_inv = -1.0 if d > 0 else 1.0
                self.log(f"calibrated: {self.ppd:.4f} px/deg (motion {amt} -> {d:.1f} deg) invert={self.look_inv}")
                return True
        self.problem("bot", "look calibration failed")
        return False

    def _turn_cmd(self, d_deg: float):
        self.bot.win.mouse_move(round(-d_deg * self.ppd * self.look_inv, 4), 0)

    def turn_to(self, yaw: float, tol: float = 2.5, tries: int = 4) -> bool:
        for _ in range(tries):
            y = self.bot.cam_yaw()
            if y is None:
                time.sleep(0.1)
                continue
            d = angle_diff(yaw, y)
            if abs(d) <= tol:
                return True
            self._turn_cmd(d)
            self.wait_frames(2)
        y = self.bot.cam_yaw()
        return y is not None and abs(angle_diff(yaw, y)) <= tol * 2

    @staticmethod
    def yaw_to(src, dst) -> float:
        return math.degrees(math.atan2(-(dst[0] - src[0]), -(dst[1] - src[1])))

    def face(self, target, body: bool = False) -> bool:
        ok = self.turn_to(self.yaw_to(self.me(), target))
        if body:
            self.bot.hold("W", 0.05)      # a tiny step turns Krystal herself toward it
            time.sleep(0.15)
        return ok

    def go(self, target, tol: float = 0.7, sprint: bool = True, timeout: float = 30.0, react: bool = True,
           precise: bool = False) -> bool:
        """Walk to XZ `target` (camera-steered, W [+SHIFT]); fights threatening enemies on the way (react)."""
        b = self.bot
        t0 = time.time()
        best = 1e9
        last_prog = time.time()
        stuck = 0
        held = False
        next_seq = 0
        try:
            while time.time() - t0 < timeout:
                s = self.st()
                if s.get("ui_stack") or s.get("mode") != "playing":
                    if held:
                        b.release_all()
                        held = False
                    self.handle_interrupts()
                    time.sleep(0.1)
                    continue
                me = xz(s.get("player", {}).get("pos", [0, 0, 0]))
                d = dist2(me, target)
                if d <= tol:
                    break
                if react and self.threat(8.0):
                    if held:
                        b.release_all()
                        held = False
                    self.fight_minor(timeout=60.0)
                    last_prog = time.time()
                    continue
                if precise and d < 1.2:
                    if held:
                        b.release_all()
                        held = False
                    self.turn_to(self.yaw_to(me, target), tol=3.0)
                    b.hold("W", max(0.04, min(0.25, (d - tol * 0.5) / 4.2)))
                    time.sleep(0.2)
                    self.wait_frames(2)
                    if time.time() - last_prog > 3.0:
                        break
                    if d < best - 0.05:
                        best = d
                        last_prog = time.time()
                    continue
                seq = int(s.get("seq", 0))
                y = s.get("player", {}).get("cam_yaw")
                if y is not None and seq >= next_seq:
                    dd = angle_diff(self.yaw_to(me, target), y)
                    if abs(dd) > 4.0:
                        self._turn_cmd(dd)
                        next_seq = seq + 2
                if not held:
                    b.down("W")
                    held = True
                want_sprint = sprint and d > 2.5
                if want_sprint and "SHIFT" not in b.held:
                    b.down("SHIFT")
                elif not want_sprint and "SHIFT" in b.held:
                    b.up("SHIFT")
                if d < best - 0.25:
                    best = d
                    last_prog = time.time()
                elif time.time() - last_prog > 1.5:
                    stuck += 1
                    self.log(f"go stuck at {me} -> {target} (d {d:.1f}); unstick #{stuck}")
                    b.release_all()
                    held = False
                    b.tap("SPACE")
                    b.hold("A" if stuck % 2 else "D", 0.35 + 0.15 * stuck)
                    last_prog = time.time()
                    if stuck > 6:
                        self.problem("nav", f"stuck walking to {target}", at=me)
                        return False
                time.sleep(0.03)
        finally:
            b.release_all()
        ok = dist2(self.me(), target) <= max(tol, 0.35) * 1.6
        if not ok:
            self.log(f"go {target} ended at {self.me()} (d {dist2(self.me(), target):.2f})")
        return ok

    def route(self, pts, tol: float = 0.9, sprint: bool = True, react: bool = True) -> bool:
        for p in pts:
            if not self.nav(p, tol=tol, sprint=sprint, react=react):
                if not self.nav(p, tol=tol * 1.5, sprint=False, react=react):
                    return False
        return True

    def nav(self, target, tol: float = 0.7, sprint: bool = True, react: bool = True, precise: bool = False,
            timeout: float = 30.0) -> bool:
        """go() with room-to-room doorways inside the manor (a fight or a dodge may have pushed her elsewhere)."""
        for _ in range(3):
            if self.area() == MANOR:
                here = room_of(self.me())
                there = room_of(target)
                for seq in room_path(here, there):
                    for q in seq:
                        self.go(q, tol=0.6, sprint=sprint, react=react, timeout=15.0)
            if self.go(target, tol=tol, sprint=sprint, react=react, precise=precise, timeout=timeout):
                return True
            if self.area() != MANOR or room_of(self.me()) == room_of(target):
                break
        return dist2(self.me(), target) <= max(tol, 0.35) * 1.6

    # ================================================================ interaction
    def prompt_is(self, words) -> bool:
        p = self.prompt()
        t = str(p.get("text", "")).lower()
        return any(w.lower() in t for w in words) and bool(p.get("enabled", True))

    def use(self, label: str, words, check, stand, look_at, tries: int = 4, stand_tol: float = 0.35) -> bool:
        """Stand at `stand`, look at `look_at`, press E when the on-screen prompt says one of `words`."""
        for attempt in range(tries):
            if check():
                return True
            self.nav(stand, tol=stand_tol, sprint=False, precise=True)
            self.face(look_at, body=True)
            self.face(look_at)
            time.sleep(0.25)
            if not self.prompt_is(words):
                # nudge: a step toward it, or back off when standing on top of it
                d = dist2(self.me(), look_at)
                if d > 1.4:
                    self.bot.hold("W", 0.1)
                elif d < 0.9:
                    self.bot.hold("S", 0.15)
                self.face(look_at)
                time.sleep(0.3)
            if self.prompt_is(words):
                self.bot.tap("E")
                if self.bot.wait_state(lambda s: check(), 4.0):
                    self.log(f"used {label}")
                    return True
            self.log(f"use {label}: attempt {attempt + 1} prompt={self.prompt()} at {self.me()}")
        ok = check()
        if not ok:
            self.problem("interact", f"could not use {label}", prompt=self.prompt())
        return ok

    def handle_interrupts(self):
        """Close unexpected panels (notice cards, pause) and wait out loading / death."""
        s = self.st()
        if s.get("mode") == "dead":
            self.fight["deaths"] += 1
            self.log("Krystal fell - waiting for the respawn")
            self.bot.wait_state(lambda st: st.get("mode") == "playing", 30)
            time.sleep(1.0)
            return
        ui = s.get("ui_stack") or []
        if ui:
            self.log(f"ui open: {ui}; buttons {[b['text'] for b in s.get('buttons', [])][:12]}")
            for label in ("Got it", "OK", "Close", "Continue", "Resume", "Not now"):
                if self.bot.find_button(label):
                    self.bot.click_button(label, timeout=1.0)
                    time.sleep(0.4)
                    return
            self.bot.tap("ESC")
            time.sleep(0.5)

    # ================================================================ healing
    def eat(self) -> bool:
        s = self.st()
        hb = s.get("hotbar", [])
        for food in FOODS:
            if food in hb:
                i = hb.index(food)
                if i < 8:
                    before = self.inv(food)
                    self.bot.tap(str(i + 1))
                    time.sleep(0.15)
                    self.bot.tap("Q")
                    if self.bot.wait_state(lambda st: int(st.get("inv", {}).get(food, 0)) < before, 1.5):
                        self.fight["eats"] += 1
                        self.log(f"ate {food}; hp {self.hp()}")
                        time.sleep(0.5)
                        return True
        return False

    def heal_to(self, target: float = 90.0, max_items: int = 4):
        n = 0
        while self.hp() < target and n < max_items and self.eat():
            n += 1

    # ================================================================ small fights (Velvet Wings)
    def foe_ok(self, e: dict) -> bool:
        """An ordinary enemy worth fighting now: alive, not the Count, not ignored, and (in the manor) in her room
        or right beside her - a wing hovering behind a wall cannot be reached by a player either."""
        if e.get("g") != "enemy" or e.get("hp", 1) <= 0 or e.get("state") in ("dead", "dying") or "Velour" in e.get("name", ""):
            return False
        if self._ignored.get(e.get("name", ""), 0.0) > time.time():
            return False
        if self.area() == MANOR:
            here = room_of(self.me())
            there = room_of(xz(e.get("pos", [0, 0, 0])))
            if here and there and here != there and e.get("dist", 99) > 2.0:
                return False
        return True

    def threat(self, rng: float) -> bool:
        return bool(self.nearby(lambda e: e.get("threat") and self.foe_ok(e), rng))

    def sidestep_from(self, src, dur: float = 0.75, prefer_center=None):
        """Strafe (sprinting) perpendicular to the line from `src` to Krystal."""
        me = self.me()
        fx, fz = src[0] - me[0], src[1] - me[1]
        n = math.hypot(fx, fz) or 1.0
        fx, fz = fx / n, fz / n
        right = (-fz, fx)
        key = "D"
        if prefer_center is not None:
            r_pt = (me[0] + right[0] * 3, me[1] + right[1] * 3)
            l_pt = (me[0] - right[0] * 3, me[1] - right[1] * 3)

            def badness(p):
                c = dist2(p, prefer_center)
                cov = min(dist2(p, q) for q in COVER)
                return c + (6.0 if cov < 1.8 else 0.0)
            key = "D" if badness(r_pt) <= badness(l_pt) else "A"
        self.turn_to(self.yaw_to(me, src), tol=6.0, tries=2)
        b = self.bot
        b.down(key)
        b.down("SHIFT")
        time.sleep(dur)
        b.up("SHIFT")
        b.up(key)

    def strike_at(self, name: str, ok_states, max_t: float = 3.5) -> int:
        """Close in on the enemy while it stays in `ok_states` and swing (soft-lock aims within 3.2 m)."""
        t0 = time.time()
        swings = 0
        while time.time() - t0 < max_t:
            e = self.enemy(name)
            if e is None or e.get("state") not in ok_states or e.get("hp", 1) <= 0:
                break
            tgt = xz(e["pos"])
            d = dist2(self.me(), tgt)
            block = self.blocker_between(self.me(), tgt)
            if block is not None:
                # a candle stand / statue / pillar is in the line of the blade: step round to his flank
                fx, fz = tgt[0] - block[0], tgt[1] - block[1]
                n = math.hypot(fx, fz) or 1.0
                perp = (-fz / n, fx / n)
                flanks = [(tgt[0] + perp[0] * 1.6, tgt[1] + perp[1] * 1.6), (tgt[0] - perp[0] * 1.6, tgt[1] - perp[1] * 1.6)]
                fl = min(flanks, key=lambda q: dist2(self.me(), q))
                self.fight["flank_moves"] = self.fight.get("flank_moves", 0) + 1
                self.go(fl, tol=0.5, sprint=True, timeout=1.8, react=False)
                continue
            if d > 2.3:
                self.go(tgt, tol=1.9, sprint=True, timeout=1.6, react=False)
                continue
            self.face(tgt)
            self.bot.tap("LMB", 0.05)
            swings += 1
            time.sleep(0.42)
        self.fight["strikes"] += swings
        return swings

    @staticmethod
    def seg_dist(a, b, p) -> float:
        ax, az = b[0] - a[0], b[1] - a[1]
        L = ax * ax + az * az
        t = 0.0 if L < 1e-6 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * az) / L))
        return math.hypot(a[0] + ax * t - p[0], a[1] + az * t - p[1])

    def blocker_between(self, a, b):
        """A solid prop (ward-candle stand, cover) close to the line a->b (manor Gallery only), else None."""
        if self.area() != MANOR:
            return None
        for c in list(CANDLES.values()) + COVER:
            r = 0.55 if c in CANDLES.values() else 1.1
            if self.seg_dist(a, b, c) < r and dist2(a, c) < dist2(a, b) + 0.2:
                return c
        return None

    def fight_minor(self, timeout: float = 60.0) -> bool:
        """Velvet Wings (and any other ordinary enemy): sidestep telegraphs, strike in recover / drain."""
        t0 = time.time()
        quiet = time.time()
        seen_tele: dict = {}
        idle_since: dict = {}
        while time.time() - t0 < timeout:
            if self.mode() == "dead":
                self.handle_interrupts()
                return False
            foes = self.nearby(lambda e: self.foe_ok(e) and (e.get("threat") or e.get("dist", 99) < 4), 14)
            if not foes:
                if time.time() - quiet > 2.0:
                    return True
                time.sleep(0.2)
                continue
            quiet = time.time()
            if self.hp() < 45:
                self.eat()
            e = foes[0]
            name = e["name"]
            stt = e.get("state", "")
            if stt == "telegraph":
                first = seen_tele.setdefault(name, time.time())
                if time.time() - first < 0.25:
                    self.sidestep_from(xz(e["pos"]), 0.6, prefer_center=self.me())
                    self.fight["dodges"] += 1
                elif time.time() - first > 0.9:
                    self.strike_at(name, {"telegraph", "drain", "recover"}, 1.5)
                else:
                    time.sleep(0.1)
                continue
            seen_tele.pop(name, None)
            if stt not in ("chase", "idle", "wander"):
                idle_since.pop(name, None)
            if stt in ("recover", "drain", "flinch", "stunned"):
                self.strike_at(name, {"recover", "drain", "flinch", "stunned"}, 2.0)
                continue
            if stt == "dash":
                time.sleep(0.1)
                continue
            # chase / idle: it hovers out of reach; face it and wait (a swing only when it is right here). A foe that
            # just hovers for long (e.g. it cannot reach her) is left alone for a while - she walks on.
            since = idle_since.setdefault(name, time.time())
            if time.time() - since > 7.0:
                self._ignored[name] = time.time() + 25.0
                self.problem("enemy", f"{name} kept '{stt}' for 7 s at {e.get('dist')} m without attacking; walking on",
                             enemy_pos=e.get("pos"))
                idle_since.pop(name, None)
                continue
            self.face(xz(e["pos"]))
            if e.get("dist", 9) < 2.0:
                self.bot.tap("LMB", 0.05)
            time.sleep(0.15)
        return False

    # ================================================================ Count Velour
    def velour(self):
        return self.enemy("CountVelour")

    def _arena_candle_entries(self) -> dict:
        out = {}
        for e in self.nearby(lambda n: n.get("g") == "interactable" and n.get("name", "").startswith("WardCandle_"), 40):
            out[e["name"].replace("WardCandle_", "")] = e
        return out

    def dark_candles(self) -> list:
        return [k for k, e in self._arena_candle_entries().items() if e.get("enabled") and "light" in e.get("text", "").lower()]

    def relight(self, cid: str) -> bool:
        c = CANDLES[cid]
        me = self.me()
        # stand 1.3 m from the candle on the side facing the arena centre
        dx, dz = ARENA_C[0] - c[0], ARENA_C[1] - c[1]
        n = math.hypot(dx, dz) or 1.0
        stand = (c[0] + dx / n * 1.3, c[1] + dz / n * 1.3)
        if dist2(me, stand) > 0.6:
            self.go(stand, tol=0.5, sprint=True, timeout=5.0, react=False)
        self.face(c, body=True)
        self.face(c)
        time.sleep(0.15)
        if self.prompt_is(["Light the ward candle"]):
            self.bot.tap("E")
            if self.bot.wait_state(lambda s: cid not in self.dark_candles(), 1.5):
                self.fight["relights"] += 1
                self.log(f"relit the {cid} ward candle")
                return True
        self.log(f"relight {cid}: prompt {self.prompt()}")
        return False

    def nearest_spot(self, spots):
        me = self.me()
        return min(spots, key=lambda p: dist2(me, p))

    def boss_fight(self, timeout: float = 600.0) -> bool:
        t0 = time.time()
        dodged_bow_t = -1.0
        last_state = ""
        last_phase = 0
        last_log = 0.0
        last_hp = self.hp()
        while time.time() - t0 < timeout and time.time() < self.deadline:
            s = self.st()
            if "ch2_velour_defeated" in s.get("flags", []):
                self.log("Count Velour's enchantment is broken")
                return True
            hp_now = self.hp()
            self.fight["hp_min"] = min(self.fight["hp_min"], hp_now)
            if hp_now < last_hp - 0.5:
                self.fight["hits_taken"] += 1
                self.fight.setdefault("hits", []).append({"t": self.elapsed(), "dmg": round(last_hp - hp_now, 1),
                                                          "velour_state": last_state})
            last_hp = hp_now
            if s.get("mode") != "playing" or s.get("ui_stack"):
                self.handle_interrupts()
                continue
            if s.get("area") != MANOR or self.room_z() > -49.0:
                # respawned at a checkpoint (or pushed out of the Gallery): walk back in
                self.log(f"back to the Gallery from {self.me()}")
                self.heal_to(80.0)
                if self.area() == MANOR:
                    self.route([p for p in FROM_BALLROOM_CP_TO_GALLERY if p[1] < self.me()[1] + 1.0] or [(0.0, -52.4)])
                    self.go(self.nearest_spot(PHASE1_SPOTS), tol=0.6)
                continue
            msgs = self.new_messages()
            bow_t = None
            for m in msgs:
                txt = m.get("text", "")
                mt = float(m.get("t", 0.0))
                if m.get("k") == "caption" and ("sweeps into a bow" in txt or "crown flashes" in txt):
                    bow_t = mt
                elif m.get("k") == "caption" and "rush of velvet" in txt and mt - max(dodged_bow_t, bow_t or -1.0) > 2.0:
                    bow_t = mt          # a dash whose bow we missed
                if m.get("k") == "event" and "died" in txt:
                    self.fight["deaths"] += 1
            v = self.velour()
            if v is not None:
                stt = v.get("state", "")
                self.fight["states_seen"][stt] = self.fight["states_seen"].get(stt, 0) + 1
                ph = int(v.get("phase", 0) or 0)
                if ph and ph != last_phase:
                    last_phase = ph
                    self.fight["phase_seen"].append({"phase": ph, "t": self.elapsed(), "hp": v.get("hp")})
                    self.log(f"Velour phase {ph} (hp {v.get('hp')})")
                if stt != last_state:
                    self.fight["velour_hp_trace"].append([self.elapsed(), stt, v.get("hp"), round(self.hp(), 1)])
                    last_state = stt
                if time.time() - last_log > 5.0:
                    last_log = time.time()
                    self.log(f"velour {stt} hp={v.get('hp')} ph={ph} vuln={v.get('vuln')} d={v.get('dist')} | me hp={self.hp()} at {self.me()}")
            else:
                stt = ""
                ph = last_phase
            # 1) a bow / dash: sidestep perpendicular to him (once per bow)
            if bow_t is not None and bow_t > dodged_bow_t and v is not None:
                dodged_bow_t = bow_t
                self.sidestep_from(xz(v["pos"]), 0.85, prefer_center=ARENA_C)
                self.fight["dodges"] += 1
                continue
            if v is None:
                # not in the fight yet (dormant): stand in the arena; the area starts him once the teaching candle burns
                dark = self.dark_candles()
                if TEACH in dark:
                    self.relight(TEACH)
                else:
                    self.go(self.nearest_spot(PHASE1_SPOTS), tol=0.6, react=False, timeout=6)
                    time.sleep(0.3)
                continue
            if stt in DASH_STATES:
                if dodged_bow_t < 0 or float(s.get("t", 0)) - dodged_bow_t > 2.5:
                    dodged_bow_t = float(s.get("t", 0))
                    self.sidestep_from(xz(v["pos"]), 0.85, prefer_center=ARENA_C)
                    self.fight["dodges"] += 1
                else:
                    time.sleep(0.05)
                continue
            if stt in BAT_STATES:
                spot = self.nearest_spot(LANE_SAFE_SPOTS)
                if dist2(self.me(), spot) > 0.3:
                    self.go(spot, tol=0.25, sprint=True, timeout=4.0, react=False, precise=True)
                else:
                    time.sleep(0.1)
                continue
            if stt in ("drain_tele", "drain"):
                vd = dist2(self.me(), xz(v["pos"]))
                tl = self.fight.setdefault("tethers", [])
                if not tl or self.elapsed() - tl[-1]["t"] > 4.0:
                    tl.append({"t": self.elapsed(), "mode": self.tether, "dist": round(vd, 1)})
                if self.tether == "los":
                    # break the line of sight: put the nearest statue / pillar between him and her
                    vp = xz(v["pos"])
                    cv = min(COVER, key=lambda c: dist2(self.me(), c))
                    dx, dz = cv[0] - vp[0], cv[1] - vp[1]
                    n = math.hypot(dx, dz) or 1.0
                    hide = (cv[0] + dx / n * 1.5, cv[1] + dz / n * 1.5)
                    self.go(hide, tol=0.5, sprint=True, timeout=3.5, react=False)
                    self.fight["los_breaks"] = self.fight.get("los_breaks", 0) + 1
                    time.sleep(0.3)
                    continue
                if vd < 4.5 or self.tether == "hit":
                    self.strike_at("CountVelour", WINDOW_STATES, 2.5)
                else:
                    # break the tether: step into the nearest lit candle pool
                    lit = [k for k in CANDLES if k not in self.dark_candles()]
                    if lit:
                        k = min(lit, key=lambda c: dist2(self.me(), CANDLES[c]))
                        c = CANDLES[k]
                        tgt = (c[0] + (self.me()[0] - c[0]) * 0.4, c[1] + (self.me()[1] - c[1]) * 0.4)
                        self.go(tgt, tol=0.6, sprint=True, timeout=3.0, react=False)
                        self.fight["pool_breaks"] += 1
                continue
            if stt == "channel_fly" or stt == "channel":
                if stt == "channel" or dist2(self.me(), xz(v["pos"])) > 3.0:
                    self.strike_at("CountVelour", {"channel_fly", "channel", "stagger", "channel_rest"}, 4.5)
                continue
            if stt in WINDOW_STATES:
                self.strike_at("CountVelour", WINDOW_STATES, 3.5)
                continue
            # glide / intro / transition / hover: phase 3 relights first, heal if low, then take the phase's spot
            if ph >= 3:
                dark = self.dark_candles()
                if dark:
                    k = min(dark, key=lambda c: dist2(self.me(), CANDLES[c]))
                    self.relight(k)
                    continue
            if self.hp() < 55 and stt in ("glide", "transition", "intro", "dormant"):
                self.eat()
            spots = PHASE1_SPOTS if ph <= 1 else LANE_SAFE_SPOTS
            spot = self.nearest_spot(spots)
            if dist2(self.me(), spot) > 0.5:
                self.go(spot, tol=0.3 if ph >= 2 else 0.5, sprint=True, timeout=3.0, react=False, precise=ph >= 2)
            else:
                self.face(xz(v["pos"]))
                time.sleep(0.1)
        return self.flag("ch2_velour_defeated")

    def room_z(self) -> float:
        return float(self.pos()[2])

    # ================================================================ the segment
    def checkpoint(self, name: str, fn, required: bool = True):
        t = time.time()
        self.log(f"=== S3 step {name} (t={self.elapsed()}s) ===")
        ok = False
        err = ""
        try:
            r = fn()
            ok = True if r is None else bool(r)
        except StepFailed as e:
            err = f"StepFailed: {e}"
        except Exception as e:  # noqa: BLE001
            err = f"{type(e).__name__}: {e}"
            self.log(traceback.format_exc())
        dur = round(time.time() - t, 1)
        rec = {"step": name, "ok": ok, "seconds": dur, "at_s": self.elapsed(), "required": required,
               "area": self.area(), "pos": self.pos(), "hp": self.hp()}
        if err:
            rec["error"] = err
        self.checkpoints.append(rec)
        self.log(f"--- {name}: {'OK' if ok else 'FAILED'} in {dur}s {err}")
        self.shot(name)
        if not ok and required:
            raise StepFailed(name)
        return ok

    def run(self) -> dict:
        result = {"segment": "S3", "title": "Moonveil Manor", "start": time.strftime("%Y-%m-%d %H:%M:%S")}
        steps = [
            ("start_in_reach", self.s_start, True),
            ("light_manor_arch", self.s_arch, False),
            ("enter_manor", self.s_enter, True),
            ("looking_glass_hall", self.s_hall, True),
            ("velvet_scrap_1_powder_room", self.s_scrap1, False),
            ("ballroom_puzzle", self.s_puzzle, True),
            ("ballroom_rest", self.s_rest_ballroom, True),
            ("velvet_scrap_2_nook", self.s_scrap2, False),
            ("velour_encounter_start", self.s_gallery, True),
            ("velour_defeated", self.s_boss, True),
            ("velvet_scrap_3_dressing_room", self.s_scrap3, False),
            ("talk_to_the_count", self.s_resident, False),
            ("manor_lantern_lit", self.s_lantern, True),
            ("balcony_rest", self.s_rest_balcony, False),
            ("shortcut_open", self.s_gate, True),
            ("garden_stair_to_reach", self.s_exit, True),
        ]
        status = "completes"
        try:
            for name, fn, req in steps:
                if not self.optional and not req and name.startswith("velvet"):
                    continue
                self.checkpoint(name, fn, req)
        except StepFailed as e:
            status = f"stops at {e}"
        except Exception as e:  # noqa: BLE001
            status = f"stops at exception {type(e).__name__}: {e}"
            self.log(traceback.format_exc())
        s = self.st()
        result.update({
            "status": status,
            "total_seconds": self.elapsed(),
            "checkpoints": self.checkpoints,
            "timings": {c["step"]: c["seconds"] for c in self.checkpoints},
            "screenshot_requests": self.shots,
            "problems": self.problems,
            "fight": self.fight,
            "final": {"area": s.get("area"), "pos": s.get("player", {}).get("pos"), "hp": s.get("player", {}).get("hp"),
                      "keys": s.get("keys"), "inv": s.get("inv"),
                      "flags_manor": sorted(f for f in s.get("flags", []) if f.startswith(("mm_", "ch2_")) ),
                      "chapter2": s.get("chapter2"), "optional": s.get("optional"), "objective": s.get("objective")},
            "captions_tail": self._captions[-80:],
        })
        return result

    # ----------------------------------------------------------------- steps
    def s_start(self):
        s = self.st()
        if s.get("mode") == "title":
            if not self.bot.click_button("Continue", timeout=15):
                raise StepFailed("no Continue on the title")
        if not self.bot.wait_state(lambda st: st.get("mode") == "playing" and st.get("area") in (REACH, MANOR), 90):
            raise StepFailed("never reached the Reach")
        time.sleep(2.0)
        self.handle_interrupts()
        self.new_messages()
        self.calibrate()
        obj = self.st().get("objective", {})
        self.log(f"objective: {obj.get('title')} | current {self.st().get('chapter2', {}).get('current')} | area {self.area()}")
        return self.area() in (REACH, MANOR)

    def s_arch(self):
        if self.flag("ch2_arch_manor") or self.area() != REACH:
            return True
        return self.use("manor arch", ["Light the lantern arch"], lambda: self.flag("ch2_arch_manor"),
                        ARCH_STAND, ARCH, stand_tol=0.5)

    def s_enter(self):
        if self.area() != MANOR:
            if not self.route(GROUNDS_PATH, tol=1.2):
                raise StepFailed("grounds path")
            ok = self.use("manor front door", ["Enter Moonveil Manor"],
                          lambda: self.area() == MANOR or self.mode() == "loading", DOOR_STAND, DOOR, stand_tol=0.5)
            if not ok:
                raise StepFailed("front door")
        if not self.bot.wait_state(lambda st: st.get("area") == MANOR and st.get("mode") == "playing", 40):
            raise StepFailed("manor did not load")
        time.sleep(1.5)
        self.handle_interrupts()
        if not self.flag("ch2_found_manor_lamp"):
            self.problem("state", "ch2_found_manor_lamp not set after entering")
        return True

    def s_hall(self):
        if self.flag("mm_mirror_clue"):
            return True
        self.route(HALL_IN)
        b0 = self.msg_count("Looking-Glass")
        self.use("looking-glass card", ["Read the card"], lambda: self.said_new("Looking-Glass", b0),
                 HALL_CARD_STAND, HALL_CARD, tries=2)
        time.sleep(1.0)
        ok = self.use("practice candle", ["Light the candle before the looking-glass"], lambda: self.flag("mm_mirror_clue"),
                      PRACTICE_STAND, PRACTICE)
        time.sleep(7.5)            # let the two looking-glass lines play (the lesson for the fight)
        self.new_messages()
        return ok

    def msg_count(self, part: str, kinds=("say",)) -> int:
        """How many messages of these kinds containing `part` were shown since the segment started."""
        self.new_messages()
        return sum(1 for m in self._captions if m.get("k") in kinds and part.lower() in str(m.get("text", "")).lower())

    def said_new(self, part: str, base: int, kinds=("say",)) -> bool:
        return self.msg_count(part, kinds) > base

    def s_scrap1(self):
        if self.flag("ch2_velvet_scrap_1"):
            return True
        self.route(POWDER_IN, tol=0.6)
        ok = self.use("velvet scrap 1", ["Pick up the velvet scrap"], lambda: self.flag("ch2_velvet_scrap_1"),
                      (7.0, -19.4), SCRAP1)
        self.route(list(reversed(POWDER_IN))[1:], tol=0.7)
        return ok

    def s_puzzle(self):
        if self.flag("mm_ballroom_solved"):
            return True
        self.route(HALL_TO_BALLROOM)
        self.route(BALLROOM_TO_CARD, tol=0.6)
        b0 = self.msg_count("Dance Card")
        self.use("dance card", ["Read the dance card"], lambda: self.said_new("Dance Card", b0),
                 DANCE_CARD_STAND, DANCE_CARD, tries=2)
        time.sleep(1.0)
        hearth_ok = self.use("hearth candle", ["Light the hearth candle"], self._hearth_lit, HEARTH_STAND, HEARTH)
        if not hearth_ok:
            raise StepFailed("hearth candle")
        clicks0 = self._caption_count("candelabrum turns")
        self.use("candelabrum c3", ["Turn the candelabrum"], lambda: self._caption_count("candelabrum turns") > clicks0,
                 C3_STAND, C3)
        time.sleep(0.8)
        clicks1 = self._caption_count("candelabrum turns")
        self.use("candelabrum c4", ["Turn the candelabrum"],
                 lambda: self._caption_count("candelabrum turns") > clicks1 or self.flag("mm_ballroom_solved"),
                 C4_STAND, C4)
        if self.bot.wait_state(lambda st: "mm_ballroom_solved" in st.get("flags", []), 4.0):
            self.log("the ward-light reached the crescent lock")
            return True
        # not solved: fall back to the reset lever + the other route (c1 -> c2 -> c4 -> T) is not needed when the
        # rule holds; report it
        self.problem("puzzle", "c3+c4 turned with the hearth lit but mm_ballroom_solved is not set",
                     captions=[m for m in self._captions[-12:]])
        return False

    def _caption_count(self, part: str) -> int:
        self.new_messages()
        return sum(1 for m in self._captions if m.get("k") == "caption" and part in str(m.get("text", "")))

    def _caption_seen(self, part: str) -> bool:
        return self._caption_count(part) > 0

    def _hearth_lit(self) -> bool:
        e = next((n for n in self.nearby(maxd=12) if n.get("name") == "HearthCandle"), None)
        return e is not None and "burns" in str(e.get("text", "")).lower()

    def rested(self, base: int) -> bool:
        return self.msg_count("Candles lit", ("notify",)) + self.msg_count("Rested", ("notify",)) > base

    def s_rest_ballroom(self):
        base = self.msg_count("Candles lit", ("notify",)) + self.msg_count("Rested", ("notify",))
        s0 = self.msg_count("journey saved", ("saved",))
        ok = self.use("ballroom rest candles", ["Rest by the candles"], lambda: self.rested(base), BALL_CP_STAND, BALL_CP)
        saved = self.bot.wait_state(lambda st: self.msg_count("journey saved", ("saved",)) > s0, 5.0)
        if ok and not saved:
            self.problem("save", "no 'journey saved' message after resting at the ballroom candles")
        return ok and bool(saved) and self.flag("mm_cp_manor_ballroom")

    def s_scrap2(self):
        if self.flag("ch2_velvet_scrap_2"):
            return True
        self.route(NOOK_IN[:-1], tol=0.6)
        ok = self.use("velvet scrap 2", ["Pick up the velvet scrap"], lambda: self.flag("ch2_velvet_scrap_2"),
                      NOOK_IN[-1], SCRAP2)
        self.route(list(reversed(NOOK_IN))[1:], tol=0.7)
        return ok

    def s_gallery(self):
        if not self.flag("mm_ballroom_solved"):
            raise StepFailed("the Gallery doors are still sealed")
        self.heal_to(95.0)
        self.route(TO_GALLERY)
        ok = self.use("teaching ward candle", ["Light the ward candle"],
                      lambda: self.velour() is not None or TEACH not in self.dark_candles(), TEACH_STAND, CANDLES[TEACH])
        started = self.bot.wait_state(lambda st: any("CountVelour" in e.get("name", "") for e in st.get("nearby", [])), 6.0)
        self.fight["encounter_starts"] += 1
        if not started:
            self.problem("encounter", "teaching candle lit in the arena but Count Velour never joined the fight")
        return ok and bool(started)

    def s_boss(self):
        return self.boss_fight()

    def s_scrap3(self):
        if self.flag("ch2_velvet_scrap_3"):
            return True
        self.route(DRESSING_IN[:-1], tol=0.6)
        ok = self.use("velvet scrap 3", ["Pick up the velvet scrap"], lambda: self.flag("ch2_velvet_scrap_3"),
                      DRESSING_IN[-1], SCRAP3)
        self.route(list(reversed(DRESSING_IN))[1:], tol=0.8)
        return ok

    def s_resident(self):
        b0 = self.msg_count("Count Velour")
        return self.use("the freed Count", ["Talk to Count Velour"], lambda: self.said_new("Count Velour", b0),
                        (RESIDENT[0] + 1.3, RESIDENT[1] + 0.6), RESIDENT, tries=2)

    def s_lantern(self):
        self.route(TO_BALCONY[:-1])
        ok = self.use("Moonveil lantern", ["Wake the Moonveil lantern"], lambda: self.flag("ch2_manor_lamp_lit"),
                      LANTERN_STAND, LANTERN)
        seal = self.bot.wait_state(lambda st: int(st.get("keys", {}).get("manor_seal", 0)) + int(st.get("inv", {}).get("manor_seal", 0)) > 0, 6.0)
        if ok and not seal:
            self.problem("reward", "manor lantern lit but no Manor Seal arrived")
        done = self.bot.wait_state(lambda st: "ch2_manor" in (st.get("chapter2", {}) or {}).get("done", []), 3.0)
        if ok and not done:
            self.problem("quest", "ch2_manor_lamp_lit set but step ch2_manor not completed")
        return ok and bool(seal)

    def s_rest_balcony(self):
        base = self.msg_count("Candles lit", ("notify",)) + self.msg_count("Rested", ("notify",))
        return self.use("balcony rest candles", ["Rest by the candles"], lambda: self.rested(base),
                        BALC_CP_STAND, BALC_CP) and self.flag("mm_cp_manor_balcony")

    def s_gate(self):
        return self.use("shortcut gate", ["Slide back the bolt"], lambda: self.flag("mm_balcony_shortcut"),
                        GATE_STAND, GATE)

    def s_exit(self):
        self.go((10.3, -89.0), tol=0.6, sprint=False)
        ok = self.use("garden stair", ["Take the garden stair"], lambda: self.area() == REACH or self.mode() == "loading",
                      GARDEN_STAND, GARDEN_STAIR)
        arrived = self.bot.wait_state(lambda st: st.get("area") == REACH and st.get("mode") == "playing", 40)
        time.sleep(1.0)
        if arrived:
            self.log(f"back in the Reach at {self.pos()}")
        return ok and bool(arrived)


def run(bot, out_dir) -> dict:
    """Plays segment S3 on a running game (title screen or already playing in the Reach) and returns the report."""
    seg = Segment(bot, out_dir)
    return seg.run()


# ====================================================================================================================
def bugs_from(result: dict, stdout_log: Path, fixture_note: str) -> list:
    """Game bugs observed in a run (bot/navigation limitations are NOT listed as game bugs)."""
    bugs = []
    errs = [ln for ln in grep_log(stdout_log, ("SCRIPT ERROR", "ERROR:", "Parse Error")) if "qa_input" not in ln]
    if errs:
        uniq = []
        for e in errs:
            if e not in uniq:
                uniq.append(e)
        bugs.append({"title": "Engine/script errors printed during the manor segment", "severity": "major",
                     "area": "moonveil_manor", "steps": f"{fixture_note}; play segment S3 headless (tools/qa/ch2/s3_manor.py)",
                     "expected": "no SCRIPT ERROR / ERROR lines", "actual": f"{len(errs)} error lines, e.g. {uniq[:6]}",
                     "evidence": str(stdout_log)})
    return bugs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--port", type=int, default=7301)
    ap.add_argument("--save", default="", help="a slot1.json to start from (copied into <run-dir>/saves)")
    ap.add_argument("--fixture", action="store_true", help="diagnostic fixture start (s3_fixture.py, default when no --save)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--max-seconds", type=int, default=2400)
    ap.add_argument("--no-optional", action="store_true")
    ap.add_argument("--tether", default="pool", choices=["pool", "hit", "los"],
                    help="how to break the Count's drain tether (coverage of the three break rules)")
    a = ap.parse_args()
    run_dir = Path(a.run_dir).resolve()
    if run_dir.exists():
        for sub in ("saves",):
            if (run_dir / sub).exists():
                shutil.rmtree(run_dir / sub)
    run_dir.mkdir(parents=True, exist_ok=True)
    if a.save:
        (run_dir / "saves").mkdir(parents=True, exist_ok=True)
        shutil.copy2(a.save, run_dir / "saves" / "slot1.json")
        note = f"start from save {a.save}"
    else:
        s3_fixture.build(run_dir)
        note = "DIAGNOSTIC FIXTURE START: tools/qa/ch2/s3_fixture.py (real save 16 + chapter-two flags, player at manor_arch)"
    game = HeadlessGame(run_dir, a.port, name="s3", max_seconds=a.max_seconds, seed=a.seed)
    t0 = time.time()
    result: dict = {"segment": "S3", "start_kind": note}
    try:
        bot = game.start()
        bot.log(note)
        if not bot.wait_state(lambda s: s.get("mode") == "title" and s.get("buttons"), 120):
            raise RuntimeError("title screen never appeared")
        seg = Segment(bot, run_dir, optional=not a.no_optional, time_budget=a.max_seconds - 60, tether=a.tether)
        result.update(seg.run())
        result["start_kind"] = note
    except Exception as e:  # noqa: BLE001
        result["status"] = f"harness error {type(e).__name__}: {e}"
        result["traceback"] = traceback.format_exc()
    finally:
        game.stop()
    result["wall_seconds"] = round(time.time() - t0, 1)
    result["godot_errors"] = grep_log(game.stdout_path, ("SCRIPT ERROR", "ERROR:"))[:40]
    (run_dir / "s3_result.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    # automatic findings of this run (engine errors + the bot's own problem log); the curated, evidenced list of game
    # bugs for the segment lives in qa/tmp/bot/s3/bugs.json
    auto = bugs_from(result, game.stdout_path, note)
    for pr in result.get("problems", []) or []:
        auto.append({"title": f"[bot-observed, triage needed] {pr.get('kind')}: {pr.get('text')}", "severity": "minor",
                     "area": str(pr.get("area")), "steps": note, "expected": "no problem logged by the S3 bot",
                     "actual": json.dumps(pr)[:600], "evidence": str(run_dir / "s3_bot.log")})
    (run_dir / "s3_auto_findings.json").write_text(json.dumps(auto, indent=1), encoding="utf-8")
    print(json.dumps({k: result.get(k) for k in ("status", "total_seconds", "wall_seconds", "timings", "problems")}, indent=1))
    return result


if __name__ == "__main__":
    main()
