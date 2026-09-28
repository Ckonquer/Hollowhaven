"""Segment S2 of the Chapter Two route bot: Hallowmere Reach west (Pumpkintide Orchard) + east (Ashbell Quarry).

Start: Lanternwake Commons with Chapter Two accepted, the waygate repaired, the Commons arch lit and the festival
map read (what segments S0/S1 leave behind). Route, with normal keyboard/mouse input only (virtual input):
  orchard: walk the west road to the orchard arch (light it) -> find the garden lamp -> open the seed box (note) ->
           raise the garden sluice gate + turn the junction sluice (water reaches the garden) -> plant the
           festival seed -> inspect a twitching pumpkin and clear the taught Pumpkin Mimic pocket -> light the
           garden lamp -> [optional] the Patchwalker field -> gather a little food
  quarry:  walk to the quarry arch (light it) -> chop wood if short -> mine iron on the lower terraces ->
           reach the winch (finds the quarry lamp) -> repair the winch (6 wood, 6 stone, 4 iron ore) -> defeat the
           Quarry Warden (WardenFight: its tells read from the telemetry "elite" entry - slam lesson, stand in front
           of a pillar and side-step across the locked charge lane, punish the exposed bell, step out of the pulse
           ring, climb back onto the bench after a fall) -> climb the gangway -> light the quarry lamp
  checks:  flags, seals (garden_seal / quarry_seal via the Chapter Two quest layer), tracker lamp group.
Every checkpoint is recorded with its time; the game's own "shot" command is requested at each (headless shots
fail - the calls stay so visible runs capture them).

run(bot, out_dir) -> dict  plays the segment on an already running game that is IN the Reach (any start state
                           past S1; it skips what is already done).
__main__                   launches the source build headless from a start save (default: the documented
                           diagnostic fixture of s2_fixture.py), clicks Continue on the title and calls run().
    python tools/qa/ch2/s2_orchard_quarry.py --run-dir qa/tmp/bot/s2/run1 [--save <slot1.json>] [--attempt 1]
Output: <run dir>/s2_result.json, <run dir>/bugs.json, <run dir>/s2_bot.log, telemetry, godot log.
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
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from s2_lib import HeadlessGame, Play, StepFailed, angle_diff, dist2, pick_port, port_free, xz, ROOT  # noqa: E402
import s2_fixture  # noqa: E402

AREA = "hallowmere_reach"

# ---- Reach coordinates (data/hallowmere_layout.gd, data/reach_west.gd, data/reach_east.gd), (x, z) -----------
COMMONS_OUT = [(2.5, 68.0), (2.5, 53.0), (0.0, 45.0), (0.0, 38.5)]
WEST_ROAD = [(-12.0, 41.0), (-22.0, 45.0), (-28.5, 48.3), (-34.0, 48.3), (-39.5, 48.3), (-46.0, 51.5),
             (-54.9, 53.2), (-58.5, 51.5)]
ORCHARD_ARCH = (-60.0, 50.0)
EAST_ROAD = [(12.0, 40.0), (26.0, 42.5), (40.0, 44.0), (50.0, 43.5), (57.4, 41.8), (60.8, 39.2)]
QUARRY_ARCH = (62.0, 38.0)
# orchard
GARDEN_LAMP = (-73.6, 42.2)
SEED_BOX = (-74.1, 46.2)
LEVER_GATE = (-77.9, 36.6)
LEVER_JUNCTION = (-82.1, 22.9)
LANE_TO_GATE = [(-69.5, 44.5), (-76.5, 40.5)]
LANE_TO_JUNCTION = [(-83.0, 33.5), (-85.5, 27.0)]
MIMIC_CENTER = (-103.0, 31.0)
LANE_TO_MIMICS = [(-83.0, 33.5), (-92.0, 33.5), (-97.0, 33.5)]
PATCH_CENTER = (-101.5, 53.0)
LANE_TO_PATCH = [(-81.0, 44.0), (-86.0, 46.0), (-92.0, 47.5)]
PUMPKINS = [(-88.0, 50.0), (-85.0, 51.5), (-82.0, 50.5), (-79.0, 52.0)]
# quarry (world = CENTER + U * AXIS_U + V * AXIS_V, data/reach_east.gd)
Q_CENTER = (86.0, 18.0)
AXIS_U = (0.478851, -0.877893)
AXIS_V = (0.877893, 0.478851)


def quv(u, v):
    return (Q_CENTER[0] + u * AXIS_U[0] + v * AXIS_V[0], Q_CENTER[1] + u * AXIS_U[1] + v * AXIS_V[1])


def to_uv(p):
    dx, dz = p[0] - Q_CENTER[0], p[1] - Q_CENTER[1]
    return (dx * AXIS_U[0] + dz * AXIS_U[1], dx * AXIS_V[0] + dz * AXIS_V[1])


ARENA = (90.0, 10.0)
PILLARS = [quv(12.6, -6.8), quv(12.3, 6.3), quv(3.3, -0.4)]
WINCH_STATION = quv(14.6, -15.6)
LAMP = quv(22.8, -4.5)
# lower terraces (L0/L1) iron veins far from the Bellcap pocket: hr_iron_0 and hr_iron_1 (L0), hr_iron_2 and
# hr_iron_3 (L1). The L0|L1 and L1|L2 step edges (1.4 m) are only climbable on the ramps (data/reach_east.gd RAMPS).
IRON_PREF = [quv(-20.5, -8.0), quv(-15.0, 10.0), quv(-8.5, -11.0), quv(-6.0, -22.5)]
RAMP_V = {"haul": 0.0, "west": -17.0, "east": 16.0}


def q_level(uv):
    u = uv[0]
    return 0 if u < -12.0 else (1 if u < -2.0 else 2)


def q_path(src, dst):
    """Waypoints (world x, z) from src to dst inside the quarry, climbing / descending only on the ramps."""
    a, b = to_uv(src), to_uv(dst)
    la, lb = q_level(a), q_level(b)
    if la == lb:
        return [dst]
    # pick the ramp whose V is closest to the average of both ends (east ramp only if both are east)
    vr = min((RAMP_V["haul"], RAMP_V["west"]), key=lambda v: abs(v - a[1]) + abs(v - b[1]))
    if a[1] > 10 and b[1] > 10:
        vr = RAMP_V["east"]
    pts = []
    step = 1 if lb > la else -1
    lvl = la
    edges = {0: (-19.5, -10.5), 1: (-9.0, 0.5)}      # (low side U, high side U) of the L0|L1 and L1|L2 ramps
    while lvl != lb:
        e = edges[lvl] if step > 0 else edges[lvl - 1]
        lo, hi = e
        if step > 0:
            pts += [quv(lo, vr), quv(hi, vr)]
        else:
            pts += [quv(hi, vr), quv(lo, vr)]
        lvl += step
    return pts + [dst]
# west ramps -> L2 bench west of the arena -> the winch drum (keeps > 14 m from the Warden's home)
TO_WINCH = [quv(-19.5, -17.0), quv(-10.5, -17.0), quv(-9.0, -17.0), quv(0.5, -17.0), quv(4.0, -18.0),
            quv(9.0, -18.0), quv(13.0, -17.5)]
# gangway: foot (U 17.75, V ~ -14.6) -> hinge on the deck (V -1.2); then the shelf and the lamp
GANGWAY = [quv(17.75, -16.0), quv(17.75, -13.5), quv(17.75, -7.0), quv(17.75, -2.0), quv(19.5, 0.0), quv(21.3, -2.5)]
# the Warden fight: where Krystal steps onto the bench (west, the winch side) and waits for the slam lesson
WARDEN_ENTRY = quv(8.0, -9.0)
LESSON_SPOT = quv(7.0, -4.0)

WINCH_COST = {"wood": 6, "stone": 6, "iron_ore": 4}

F = {
    "found_orchard": "ch2_found_orchard_lamp", "irrigated": "ch2_orchard_irrigated",
    "gate": "hr_sluice_gate_open", "junction": "hr_sluice_junction_garden", "note": "hr_read_garden_note",
    "seed": "hr_festival_seed_planted", "mimics": "ch2_orchard_mimics_cleared", "garden_lit": "ch2_garden_lamp_lit",
    "orchard_restored": "ch2_orchard_restored", "arch_orchard": "ch2_arch_orchard", "arch_quarry": "ch2_arch_quarry",
    "found_quarry": "ch2_found_quarry_lamp", "winch": "ch2_winch_repaired", "warden": "hr_warden_defeated",
    "quarry_lit": "ch2_quarry_lamp_lit", "quarry_restored": "ch2_quarry_restored",
    "patch_cleared": "spawner_cleared_hr_sp_orchard_patchwalkers",
}


class Segment:
    def __init__(self, bot, out_dir, opts=None):
        self.p = Play(bot, out_dir)
        self.bot = bot
        self.log = self.p.log
        self.opts = opts or {}
        self.checkpoints: list[dict] = []
        self.timings: dict = {}
        self.exposure_damage: list = []
        self.warden_log: list[str] = []

    # ------------------------------------------------------------------ bookkeeping
    def checkpoint(self, name, ok=True, detail=""):
        s = self.p.st()
        cp = {"name": name, "ok": bool(ok), "t": self.p.elapsed(), "area": s.get("area"), "zone": s.get("zone"),
              "pos": s.get("player", {}).get("pos"), "hp": s.get("player", {}).get("hp"), "detail": detail}
        self.checkpoints.append(cp)
        self.log(f"CHECKPOINT {'OK ' if ok else 'FAIL'} {name} t={cp['t']}s {detail}")
        self.p.shot(name)

    def step(self, name, fn, required=True):
        t = time.time()
        self.log(f"=== STEP {name} ===")
        ok = False
        err = ""
        try:
            r = fn()
            ok = True if r is None else bool(r)
        except StepFailed as e:
            err = str(e)
        except Exception as e:  # noqa: BLE001
            err = f"{type(e).__name__}: {e}"
            self.log(traceback.format_exc())
        self.p.bot.release_all()
        dur = round(time.time() - t, 1)
        self.timings[name] = dur
        if not ok:
            self.p.problems.append(f"{name}: {err or 'failed'}")
        self.checkpoint(name, ok, err or f"{dur}s")
        if not ok and required:
            raise StepFailed(f"{name}: {err or 'failed'}")
        return ok

    # ------------------------------------------------------------------ small helpers
    def flag(self, key):
        return self.p.flag(F.get(key, key))

    def interactable(self, words, near=None, maxd=40.0, radius=None):
        def pred(n):
            if n.get("g") not in ("interactable", "checkpoint", "crafting_station"):
                return False
            txt = (n.get("text", "") + " " + n.get("name", "")).lower()
            if not any(w.lower() in txt for w in words):
                return False
            if near is not None and radius is not None and dist2(xz(n["pos"]), near) > radius:
                return False
            return True
        c = self.p.nearby(pred, maxd)
        if near is not None:
            c.sort(key=lambda n: dist2(xz(n["pos"]), near))
        return c[0] if c else None

    def use(self, words, check, near=None, radius=4.0, maxd=40.0, stop=1.3, tries=4, need_enabled=True):
        e = self.interactable(words, near, maxd, radius)
        if e is None:
            raise StepFailed(f"no interactable {words} near {near} (pos {self.p.pos()})")
        return self.p.press_interact_on(e, words, check, tries=tries, stop=stop, need_enabled=need_enabled)

    def ensure_reach(self):
        s = self.p.st()
        if s.get("area") != AREA or s.get("mode") != "playing":
            raise StepFailed(f"not playing in the Reach (area={s.get('area')} mode={s.get('mode')})")

    def save_game(self, label):
        """Pause menu -> Save Game (a normal player action; also gives resumable checkpoints)."""
        self.p.dismiss_popups()
        self.bot.tap("ESC")
        if not self.p.wait(lambda s: "pause" in (s.get("ui_stack") or []), 3.0):
            self.log("pause menu did not open")
            return False
        ok = self.p.click("Save Game", exact=True, timeout=3.0)
        saved = self.p.wait(lambda s: any(m.get("k") == "saved" for m in s.get("messages", [])
                                          if m.get("t", 0) > 0), 4.0) is not None
        time.sleep(0.5)
        self.p.click("Resume", exact=True, timeout=2.0)
        time.sleep(0.4)
        self.p.dismiss_popups()
        try:
            src = self.p.out / "saves" / "slot1.json"
            if src.exists():
                dst = self.p.out / "checkpoints" / label
                dst.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst / "slot1.json")
        except Exception as e:  # noqa: BLE001
            self.log(f"checkpoint copy failed: {e}")
        self.log(f"save_game {label}: clicked={ok} saved_msg={saved}")
        return ok

    def near_route_start(self, route):
        here = xz(self.p.pos())
        i = min(range(len(route)), key=lambda k: dist2(route[k], here))
        return route[i:]

    # ================================================================== ORCHARD
    def to_orchard(self):
        self.ensure_reach()
        here = xz(self.p.pos())
        if dist2(here, ORCHARD_ARCH) < 12:
            return True
        if here[1] > 44 and abs(here[0]) < 25:
            if not self.p.walk_route(self.near_route_start(COMMONS_OUT)):
                raise StepFailed("could not leave the Commons")
        if not self.p.walk_route(self.near_route_start(WEST_ROAD)):
            raise StepFailed(f"west road blocked at {self.p.pos()}")
        return self.p.goto(ORCHARD_ARCH, tol=3.0)

    def light_arch(self, arch_id, pos):
        flag = f"ch2_arch_{arch_id}"
        if self.p.flag(flag):
            return True
        ok = self.use(["Light the lantern arch"], lambda: self.p.flag(flag), near=pos, radius=6.0, stop=1.8)
        time.sleep(1.0)
        self.p.dismiss_popups()
        return ok or self.p.flag(flag)

    def find_orchard_lamp(self):
        if not self.flag("found_orchard"):
            self.p.walk_route(LANE_TO_GATE[:1])
            self.p.goto(GARDEN_LAMP, tol=6.0)
        ok = self.p.wait(lambda s: F["found_orchard"] in s.get("flags", []), 6.0) is not None
        lamp = self.interactable(["garden lamp"], GARDEN_LAMP, 40, 5)
        if lamp:
            self.log(f"garden lamp prompt before repairs: {lamp.get('text')} enabled={lamp.get('enabled')}")
            if lamp.get("enabled", True) and not (self.flag("irrigated") and self.flag("mimics")):
                self.p.bug("Garden lamp prompt enabled before its conditions", "major", "hr_orchard",
                           "Reach the garden lamp before irrigation / mimics", "prompt disabled with a reason",
                           f"prompt {lamp}", "telemetry nearby")
        return ok

    def seed_box_note(self):
        if self.flag("note"):
            return True
        return self.use(["Open the seed box"], lambda: self.flag("note"), near=SEED_BOX, radius=4.0, stop=1.4)

    def lever_text(self, pos):
        e = self.interactable(["sluice"], pos, 60, 3.0)
        return (e or {}).get("text", "")

    def irrigation(self):
        if self.flag("irrigated"):
            return True
        # NOTE: telemetry "flags" lists flag KEYS (a lever flag set to false is listed too), so the lever state is
        # read from each lever's own prompt, like a player reads it.
        # lever 2 first (the gate), then lever 1 (junction to the garden): water arrives when both are set
        self.p.walk_route(LANE_TO_GATE)
        if "Raise the garden sluice gate" in self.lever_text(LEVER_GATE):
            if not self.use(["Raise the garden sluice gate"], lambda: "Lower" in self.lever_text(LEVER_GATE),
                            near=LEVER_GATE, radius=3.0, stop=1.5):
                raise StepFailed(f"gate lever did not respond ({self.lever_text(LEVER_GATE)!r})")
        self.p.walk_route(LANE_TO_JUNCTION)
        if "toward the garden" in self.lever_text(LEVER_JUNCTION):
            if not self.use(["send the water toward the garden"], lambda: "drain pond" in self.lever_text(LEVER_JUNCTION),
                            near=LEVER_JUNCTION, radius=3.0, stop=1.5):
                raise StepFailed(f"junction lever did not respond ({self.lever_text(LEVER_JUNCTION)!r})")
        ok = self.p.wait(lambda s: F["irrigated"] in s.get("flags", []), 5.0) is not None
        msgs = [m.get("text", "") for m in self.p.seen_msgs]
        self.log(f"irrigation: latched={ok} gate={self.lever_text(LEVER_GATE)!r} junction={self.lever_text(LEVER_JUNCTION)!r}")
        if ok and not any("Water reaches the festival garden" in m for m in msgs):
            self.p.problems.append("irrigation latched without the 'Water reaches the festival garden!' toast")
        return ok

    def plant_seed(self):
        if self.flag("seed"):
            return True
        self.p.walk_route([(-83.0, 33.5), (-76.5, 40.5)])
        ok = self.use(["Plant the festival seed"], lambda: self.flag("seed"), near=SEED_BOX, radius=4.0, stop=1.4)
        time.sleep(3.0)
        return ok

    def mimic_pocket(self):
        if self.flag("mimics"):
            return True
        self.p.heal_up(target=70.0, max_items=4)
        self.p.walk_route(self.near_route_start(LANE_TO_MIMICS))
        e = self.interactable(["Inspect twitching pumpkin"], MIMIC_CENTER, 40, 8)
        if e is None:
            raise StepFailed("no 'Inspect twitching pumpkin' prompt in the mimic pocket")
        self.log(f"twitching pumpkin: {e}")
        woke = self.p.press_interact_on(
            e, ["Inspect twitching pumpkin"],
            lambda: bool(self.p.live_enemies(lambda n: "mimic" in (n.get("name", "") + n.get("id", "")).lower() or True, 12))
            or self.flag("mimics"), stop=1.6)
        if not woke:
            self.log("inspect did not wake the pocket; waiting for the wake tell")
        # step back out of bite range while they wake (tell: stems twitch twice)
        self.bot.hold("S", 0.6)
        t_end = time.time() + 150
        is_mimic = lambda n: "mimic" in n.get("name", "").lower()  # noqa: E731
        while time.time() < t_end and not self.flag("mimics"):
            self.p.fight(is_mimic, timeout=40, flee_hp=30.0, maxd=25)
            if self.flag("mimics"):
                break
            if not self.p.live_enemies(is_mimic, maxd=40):
                # nothing visible: walk back to the pocket centre to find the rest
                self.p.goto(MIMIC_CENTER, tol=3.0, timeout=15)
                time.sleep(1.0)
        ok = self.p.wait(lambda s: F["mimics"] in s.get("flags", []), 5.0) is not None
        pw = [(x.get("name"), x.get("state"), x.get("dist")) for x in self.p.live_enemies(lambda n: "patch" in n.get("name", "").lower(), 40)
              if x.get("state") in ("chase", "telegraph", "rake", "throw")]
        if pw:
            self.p.problems.append(f"Patchwalkers joined the taught mimic lesson: {pw}")
        if not ok:
            en = self.p.live_enemies(maxd=60)
            raise StepFailed(f"mimic pocket not cleared (enemies: {[(x.get('name'), x.get('hp'), x.get('state')) for x in en]})")
        return True

    def light_garden_lamp(self):
        if self.flag("garden_lit"):
            return True
        self.p.walk_route([(-92.0, 33.5), (-83.0, 33.5), (-76.5, 40.5)])
        e = self.interactable(["garden lamp"], GARDEN_LAMP, 40, 5)
        if e and not e.get("enabled", True):
            raise StepFailed(f"garden lamp still refuses: {e}")
        ok = self.use(["Light the garden lamp"], lambda: self.flag("garden_lit"), near=GARDEN_LAMP, radius=4.0, stop=1.6)
        time.sleep(2.0)
        return ok

    def check_garden_seal(self):
        s = self.p.st()
        seal = self.p.inv("garden_seal")
        ch2 = s.get("chapter2", {})
        self.log(f"after garden lamp: garden_seal={seal} ch2.done={ch2.get('done')} current={ch2.get('current')} "
                 f"tracker={s.get('tracker')}")
        if seal < 1:
            self.p.bug("Garden Seal not granted when the garden lamp is lit (lamp group waits for all three lamps to be FOUND)",
                       "major", "hr_orchard / quest layer (data/quests_ch2.gd ch2_outer_lamps -> ch2_orchard)",
                       "From the S2 start (Commons, Chapter Two accepted, manor never visited): light the orchard garden lamp",
                       "Lighting a lamp completes 'Pumpkins With Opinions' and grants the Garden Seal (MP 9: each road supplies "
                       "one guaranteed seal, progress recorded independently; steps 5-7 are parallel branch records)",
                       f"ch2_garden_lamp_lit is set but no seal and no 'Goal complete'; chapter2.current={ch2.get('current')} "
                       f"(ch2_outer_lamps still needs the manor lamp FOUND, so the lamps group has not started); tracker still "
                       f"'{s.get('tracker', {}).get('title')}'",
                       "telemetry chapter2/tracker/inv after the lamp; s2_bot.log")
        return seal >= 1

    def patchwalkers(self):
        if self.p.flag(F["patch_cleared"]):
            return True
        self.p.heal_up(target=80.0, max_items=6)
        if self.p.hp() < 60:
            raise StepFailed(f"skipped: hp {self.p.hp()} too low for the optional Patchwalker field")
        self.p.walk_route(LANE_TO_PATCH)
        t_end = time.time() + 120
        seen = False
        while time.time() < t_end:
            en = self.p.live_enemies(lambda n: "patch" in n.get("name", "").lower(), 30)
            if en:
                seen = True
                self.p.fight(lambda n: "patch" in n.get("name", "").lower(), timeout=60, flee_hp=35, maxd=30)
            elif seen:
                break
            else:
                self.p.goto((-97.0, 50.5), tol=2.0, timeout=10)
                time.sleep(1.0)
                if not self.p.live_enemies(maxd=30) and time.time() > t_end - 90:
                    break
        return not self.p.live_enemies(lambda n: "patch" in n.get("name", "").lower(), 30)

    def gather_food(self):
        """A few wild pumpkins / roseberries for the quarry (renewable hand harvest)."""
        got = 0
        for tgt in PUMPKINS:
            if self.p.inv("pumpkin") >= 3:
                break
            e = self.p.nearest(lambda n: n.get("g") == "harvestable" and "pumpkin" in (n.get("id", "") + n.get("label", "")).lower()
                               and dist2(xz(n["pos"]), tgt) < 2.0, 60)
            if not e:
                continue
            before = self.p.inv("pumpkin")
            self.p.press_interact_on(e, ["Pumpkin", "Harvest", "Pick", "Gather"], lambda: self.p.inv("pumpkin") > before,
                                     stop=1.4, tries=2, need_enabled=False)
            if self.p.inv("pumpkin") <= before:
                # hand harvestables may prompt the attack action ("Gather ...")
                self.bot.tap("LMB", 0.06)
                time.sleep(0.8)
            got += self.p.inv("pumpkin") - before
        return self.p.inv("pumpkin") > 0 or self.p.inv("berries") > 0

    # ================================================================== QUARRY
    def to_quarry(self):
        self.ensure_reach()
        here = xz(self.p.pos())
        if dist2(here, QUARRY_ARCH) < 12:
            return True
        if here[0] < -20:
            back = list(reversed(WEST_ROAD)) + [(0.0, 38.5)]
            if not self.p.walk_route(self.near_route_start(back)):
                raise StepFailed(f"west road (back) blocked at {self.p.pos()}")
        elif here[1] > 44 and abs(here[0]) < 25:
            self.p.walk_route(self.near_route_start(COMMONS_OUT))
        if not self.p.walk_route(self.near_route_start(EAST_ROAD)):
            raise StepFailed(f"east road blocked at {self.p.pos()}")
        return self.p.goto(QUARRY_ARCH, tol=3.0)

    def gather_wood(self):
        need = WINCH_COST["wood"]
        if self.p.inv("wood") >= need or self.flag("winch"):
            return True
        # sticks first (hand), then trees near the quarry arch / east road
        ok = self.p.harvest_tool(["tree", "maple", "oak", "birch"], "wood", need, maxd=60.0, prefer_pos=xz(self.p.pos()),
                                 avoid=lambda n: dist2(xz(n["pos"]), Q_CENTER) < 30.0)
        return ok

    def qgoto(self, dst, tol=2.0, timeout=30):
        for pt in q_path(xz(self.p.pos()), dst):
            if not self.p.goto(pt, tol=tol if pt == dst else 1.6, timeout=timeout):
                return False
        return True

    def mine_iron(self):
        need = WINCH_COST["iron_ore"]
        if self.p.inv("iron_ore") >= need or self.flag("winch"):
            return True
        for tgt in IRON_PREF:
            if self.p.inv("iron_ore") >= need:
                break
            if dist2(xz(self.p.pos()), tgt) > 3.0:
                self.qgoto(tgt, tol=2.5)
            e = self.p.nearest(lambda n: n.get("g") == "harvestable" and "iron" in (n.get("id", "") + n.get("label", "")).lower()
                               and dist2(xz(n["pos"]), tgt) < 2.5, 20)
            if not e:
                self.log(f"no iron vein at {tgt} (depleted or not reached; at {self.p.pos()})")
                continue
            try:
                self.p.harvest_tool(["iron"], "iron_ore", need, maxd=6.0, prefer_pos=tgt)
            except StepFailed as ex:
                self.log(f"iron vein at {tgt}: {ex}")
        if self.p.inv("stone") < WINCH_COST["stone"]:
            self.gather_stone(WINCH_COST["stone"])
        return self.p.inv("iron_ore") >= need

    def gather_stone(self, want):
        guard = 0
        while self.p.inv("stone") < want and guard < 10:
            guard += 1
            e = self.p.nearest(lambda n: n.get("g") == "harvestable" and n.get("tool") == "hand" and "stone" in n.get("label", "").lower()
                               and dist2(xz(n["pos"]), ARENA) > 16, 50)
            if not e:
                break
            before = self.p.inv("stone")
            self.p.press_interact_on(e, ["Stone"], lambda: self.p.inv("stone") > before, stop=1.3, tries=2)
        return self.p.inv("stone") >= want

    def to_winch(self):
        if dist2(xz(self.p.pos()), WINCH_STATION) < 4:
            return True
        lvl = q_level(to_uv(xz(self.p.pos())))
        if lvl == 0:
            route = TO_WINCH
        elif lvl == 1:
            route = [quv(-11.0, -17.0)] + TO_WINCH[2:]
        else:
            route = self.near_route_start(TO_WINCH[3:])
        return self.p.walk_route(route, tol=1.8)

    def repair_winch(self):
        if self.flag("winch"):
            return True
        missing = {k: v - self.p.inv(k) for k, v in WINCH_COST.items() if self.p.inv(k) < v}
        if missing:
            raise StepFailed(f"materials missing for the winch: {missing}")
        self.to_winch()
        e = self.interactable(["winch"], WINCH_STATION, 30, 5)
        self.log(f"winch interactable: {e}")
        ok = self.use(["Repair the mineral winch"], lambda: self.flag("winch"), near=WINCH_STATION, radius=5.0, stop=1.6)
        time.sleep(3.5)       # the gangway lowers (LOWER_SECONDS 2.6)
        return ok

    # ---- the Quarry Warden ---------------------------------------------------------------------------------------
    def warden(self):
        ents = [e for e in self.p.nearby(lambda n: n.get("g") == "enemy", 60)
                if "warden" in (e.get("name", "") + e.get("id", "")).lower() or float(e.get("hp", 0)) > 150]
        return ents[0] if ents else None

    @staticmethod
    def elite(s):
        """The Warden as the telemetry "elite" entry shows it (fresh every line: state + wind-up timing, attack_kind,
        the drawn lane / ring, pillars, exposures, arena floor; game/src/qa/qa_telemetry.gd _elite_entry())."""
        e = s.get("elite") if s else None
        if isinstance(e, dict) and str(e.get("id", "")) == "quarry_warden":
            return e
        return None

    def warden_note(self, text):
        """Notable player-level recoveries in the fight (the chain wrapper also collects them)."""
        self.log(text)

    def fight_warden(self):
        if self.flag("warden"):
            return True
        self.p.heal_up(target=90.0, max_items=8)
        # enter the arena from the west side of the bench (the winch side)
        self.p.goto(WARDEN_ENTRY, tol=2.0, timeout=25)
        fight = WardenFight(self, float(self.opts.get("warden_timeout", 420)))
        ok = fight.run()
        self.exposure_damage = fight.exposure_damage
        self.warden_log = fight.wlog
        self.timings["warden_exposure_damage"] = fight.exposure_damage
        self.timings["warden_exposures"] = fight.stats["exposures"]
        self.timings["warden_fight_s"] = fight.fight_seconds()
        self.timings["warden_stats"] = fight.summary()
        big = [x for x in self.exposure_damage if x >= 150.0]
        if big:
            self.p.bug("Quarry Warden: one pillar exposure removes most of its 300 HP (pulse phase can be skipped)", "minor",
                       "hr_quarry (src/enemies/quarry_warden.gd EXPOSED_MULT / EXPOSE_CAP, data/enemies.gd quarry_warden hp)",
                       "Starting gear (copper sword): let the Warden slam once, bait its charge into a mineral pillar, "
                       "strike the exposed bell for the whole window",
                       "one exposure takes at most EXPOSE_CAP (35 %) of its health",
                       f"damage dealt per exposure window: {self.exposure_damage}",
                       "s2_bot.log 'warden' lines; telemetry elite hp per line")
        self.log(f"warden fight end: ok={ok} {json.dumps(fight.summary())}")
        if not ok:
            s = self.p.st()
            el = self.elite(s)
            raise StepFailed(f"Warden not defeated in time (warden {el and (el.get('hp'), el.get('state'))}, "
                             f"hp {s.get('player', {}).get('hp')})")
        return True

    def climb_to_bench(self):
        """Back up onto the arena bench (L2) by the nearest ramp - a roll / knockback can drop Krystal to L1."""
        me = xz(self.p.pos())
        uv = to_uv(me)
        dst = quv(max(2.5, min(uv[0], 6.0)), max(-5.0, min(uv[1], 5.0)))
        self.log(f"warden: Krystal is off the arena bench (uv {tuple(round(x, 1) for x in uv)}): back up by the ramp to "
                 f"uv {tuple(round(x, 1) for x in to_uv(dst))}")
        ok = self.qgoto(dst, tol=1.8, timeout=15)
        return ok

    def climb_and_light(self):
        if self.flag("quarry_lit"):
            return True
        if not self.flag("winch") or not self.flag("warden"):
            raise StepFailed("the lamp needs the winch and the Warden first")
        self.p.walk_route([quv(10.0, -14.0)] + GANGWAY[:1], tol=1.5)
        if not self.p.walk_route(GANGWAY[1:], tol=1.2, sprint=False):
            raise StepFailed(f"gangway / shelf blocked at {self.p.pos()} (uv {to_uv(xz(self.p.pos()))})")
        e = self.interactable(["quarry lamp"], LAMP, 30, 4)
        self.log(f"quarry lamp: {e}")
        ok = self.use(["Light the quarry lamp"], lambda: self.flag("quarry_lit"), near=LAMP, radius=4.0, stop=1.6)
        time.sleep(2.5)
        return ok

    def verify(self):
        s = self.p.st()
        ch2 = s.get("chapter2", {})
        res = {"garden_seal": self.p.inv("garden_seal"), "quarry_seal": self.p.inv("quarry_seal"),
               "flags": {k: (v in s.get("flags", [])) for k, v in F.items()},
               "chapter2_done": ch2.get("done"), "chapter2_current": ch2.get("current"), "tracker": s.get("tracker"),
               "objective": s.get("objective"), "optional": s.get("optional"), "music": s.get("music"),
               "inv": s.get("inv"), "keys": s.get("keys")}
        self.log(f"VERIFY {json.dumps(res)[:1500]}")
        self.result_verify = res
        if res["quarry_seal"] < 1 and self.flag("quarry_lit"):
            self.p.bug("Quarry Seal not granted when the quarry lamp is lit (lamp group waits for all three lamps to be FOUND)",
                       "major", "hr_quarry / quest layer (data/quests_ch2.gd ch2_outer_lamps -> ch2_quarry)",
                       "S2 route without visiting the manor: light the quarry lamp",
                       "Quarry Seal granted by the quest layer on lighting",
                       f"no quarry_seal; chapter2.current={ch2.get('current')} tracker={s.get('tracker', {}).get('title')}",
                       "telemetry after lighting; s2_bot.log")
        return True

    def reload_check(self):
        """Save through the pause menu, Quit to Title, Continue: the segment's world state must come back."""
        before = {k: self.flag(k) for k in ("irrigated", "mimics", "garden_lit", "winch", "warden", "quarry_lit",
                                              "found_orchard", "found_quarry", "arch_orchard", "arch_quarry")}
        inv_before = {k: self.p.inv(k) for k in ("garden_seal", "quarry_seal", "iron_ore", "wood", "stone")}
        self.p.dismiss_popups()
        self.bot.tap("ESC")
        if not self.p.wait(lambda s: "pause" in (s.get("ui_stack") or []), 3.0):
            raise StepFailed("pause menu did not open")
        if not self.p.click("Quit to Title", exact=True, timeout=3.0):
            raise StepFailed("no Quit to Title button")
        time.sleep(0.6)
        if not self.p.click("Save & Quit", exact=True, timeout=4.0):
            self.log(f"no Save & Quit confirm (saving refused here?); buttons={[b['text'] for b in self.p.buttons()][:15]}")
            self.p.problems.append("Quit to Title offered no 'Save & Quit' after the segment")
            self.p.click("Quit to Title", exact=True, timeout=3.0)
        if not self.p.wait(lambda s: s.get("mode") == "title" and any("Continue" in b.get("text", "") for b in s.get("buttons", [])), 40):
            raise StepFailed("title screen did not come back")
        time.sleep(1.0)
        if not self.p.click("Continue", timeout=8.0):
            raise StepFailed("no Continue on the title")
        if not self.p.wait(lambda s: s.get("mode") == "playing" and s.get("area") == AREA, 90):
            raise StepFailed("Continue did not return to the Reach")
        time.sleep(3.0)
        self.p.dismiss_popups()
        after = {k: self.flag(k) for k in before}
        inv_after = {k: self.p.inv(k) for k in inv_before}
        self.log(f"reload: flags before={before} after={after}; inv before={inv_before} after={inv_after} pos={self.p.pos()}")
        lost = [k for k in before if before[k] and not after[k]]
        if lost or inv_after != inv_before:
            self.p.bug("S2 world state lost across Save & Quit / Continue", "major", "hallowmere_reach",
                       "Finish S2, pause -> Quit to Title -> Save & Quit, Continue", "every flag / item kept",
                       f"lost flags {lost}; inventory {inv_before} -> {inv_after}", "s2_bot.log reload line")
        # the world objects read the state back
        checks = {}
        if dist2(xz(self.p.pos()), QUARRY_ARCH) < 60 or dist2(xz(self.p.pos()), LAMP) < 60:
            w = self.interactable(["winch"], WINCH_STATION, 80, 5)
            lampq = self.interactable(["quarry lamp"], LAMP, 80, 5)
            checks["winch_prompt"] = (w or {}).get("text")
            checks["quarry_lamp_prompt"] = (lampq or {}).get("text")
            checks["warden_present"] = self.warden() is not None
            if checks["warden_present"]:
                self.p.bug("Quarry Warden back after reload although defeated", "major", "hr_quarry",
                           "Defeat the Warden, save, Continue", "the arena stays empty (never respawns)",
                           f"warden entity present: {self.warden()}", "telemetry nearby")
        self.log(f"reload world checks: {checks}")
        return not lost

    def visit_manor_approach(self):
        """Optional check: walk the north road until the manor lamp is found, then see whether the seals arrive."""
        if self.p.flag("ch2_found_manor_lamp"):
            return True
        route = [(0.0, 38.5), (0.0, 30.0), (0.0, 22.0), (-8.0, 12.0), (-9.0, 2.0), (0.5, -8.0), (0.5, -12.0),
                 (2.5, -24.0), (5.0, -34.0), (8.1, -44.3), (10.0, -50.0), (12.0, -56.0), (15.0, -64.0), (17.0, -72.0)]
        here = xz(self.p.pos())
        if here[0] > 20:
            self.p.walk_route(self.near_route_start(list(reversed(EAST_ROAD))) + [(0.0, 38.5)])
        for pt in self.near_route_start(route):
            self.p.goto(pt, tol=2.5, timeout=30)
            if self.p.flag("ch2_found_manor_lamp"):
                break
        ok = self.p.wait(lambda s: "ch2_found_manor_lamp" in s.get("flags", []), 5.0) is not None
        time.sleep(3.0)
        return ok


# ================================================================================== the Quarry Warden fight
MOVE_KEYS = [("W",), ("W", "A"), ("A",), ("S", "A"), ("S",), ("S", "D"), ("D",), ("W", "D")]


def keys_for(cam_yaw, vec):
    """The camera-relative WASD keys (8 ways) that move Krystal along the world vector vec = (dx, dz)."""
    want = math.degrees(math.atan2(-vec[0], -vec[1]))
    rel = angle_diff(want, cam_yaw)           # + = to the camera's left (yaw 0 looks toward -Z, +90 toward -X)
    return set(MOVE_KEYS[int(round(rel / 45.0)) % 8])


def unit(dx, dz):
    n = math.hypot(dx, dz)
    return (dx / n, dz / n) if n > 1e-6 else (0.0, 0.0)


def seg_dist(p, a, b):
    """Flat distance from point p to the segment a-b."""
    ax, az = b[0] - a[0], b[1] - a[1]
    l2 = ax * ax + az * az
    t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * az) / l2))
    return math.hypot(p[0] - (a[0] + ax * t), p[1] - (a[1] + az * t))


def yaw_to(a, b):
    return math.degrees(math.atan2(-(b[0] - a[0]), -(b[1] - a[1])))


class WardenFight:
    """The Quarry Warden (game/src/enemies/quarry_warden.gd) played from its TELLS, read from the telemetry "elite"
    entry every line (state + wind-up timing, attack_kind, the drawn charge lane / pulse ring, pillars, exposures,
    whether Krystal stands on its arena floor) - never guessed from distance. Input: camera-relative WASD held for a
    world direction (8 ways, non-blocking), SHIFT, CTRL (roll along the held direction), LMB.
      slam lesson  it only slams until its first slam: let it come, step out of the wedge's reach, punish the recover;
      pillar bait  stand IN FRONT of an intact pillar (between the Warden and the pillar, BAIT_D from the pillar's
                   centre); the charge lane tracks her for 60 % of the wind-up, then locks: side-step ACROSS the locked
                   lane (roll + sprint, perpendicular - never back along it) so the committed charge cracks the pillar;
                   run in and strike the exposed bell until the shell grinds shut (EXPOSE_CAP) or the window ends;
      pulses       step out of the red ring (radius + margin, a point kept on the bench) before the first beat, or roll
                   on the beat when cornered; punish the recover;
      windows      every recover / stun / exposure is punished when it lasts long enough to get there;
      off floor    knocked / rolled down to L1: straight back up the nearest ramp (it gives up and resets after 5 s);
      low health   eat between attacks (backpack / hotbar) when nothing is winding up close by.
    All planned points stay on the bench: within SAFE_R of the arena centre, at quarry U >= EDGE_U (the L1|L2 step is
    at U -2, ~10.9 m west of the centre) and clear of every pillar / stump."""

    SPRINT = 6.0          # m/s the planner assumes (sprint 7.0 less key / telemetry latency)
    REACH = 2.45          # centre to centre: she swings from here (sword ~2.5 m + part of the Warden's 0.9 m body)
    SAFE_R = 8.3
    EDGE_U = 1.0
    BAIT_D = (2.2, 1.9)   # metres in front of the pillar's centre (the lane is clipped ~1.8 m in front of it)
    SIDE = 2.7            # lateral offset from the locked lane's centre line after the side-step (1.1 + 0.35 + margin)
    SWING_EVERY = 0.52
    EAT_HP = 45.0

    def __init__(self, seg, timeout: float):
        self.seg, self.p, self.bot, self.log = seg, seg.p, seg.bot, seg.log
        self.timeout = timeout
        self.keys: set = set()
        self.cam = 0.0
        self.facing = None
        self.stamina = 100.0
        self.ac = ARENA
        self.ay = 0.0
        self.pillars: list = []
        self.last_state = ""
        self.kind = ""
        self.side = None
        self.side_pt = None
        self.bait = None
        self.last_lane = None
        self.last_swing = 0.0
        self.last_roll = 0.0
        self.expose_hp = None
        self.exposure_damage: list = []
        self.wlog: list = []
        self.t_engaged = None
        self.t_won = None
        self.last_hp = None
        self.last_whp = None
        self.charges_seen = None
        self.give_ups_seen = None
        self.on_floor_since = None
        self.el_last: dict = {}
        self.deaths0 = self.p.deaths
        self.stats = {"exposures": 0, "slam_tells": 0, "charge_tells": 0, "pulse_tells": 0, "sidesteps": 0, "rolls": 0,
                      "swings": 0, "hits_taken": 0, "damage_taken": 0.0, "deaths": 0, "climbs": 0, "eats": 0,
                      "resets": 0, "charge_results": {}}

    # ------------------------------------------------------------------ input
    def set_move(self, vec, sprint=True):
        """Hold the keys that move her along world vector vec (None = stand still). Only changed keys are sent."""
        want: set = set()
        if vec is not None and math.hypot(vec[0], vec[1]) > 1e-3:
            want = keys_for(self.cam, vec)
            if sprint:
                want.add("SHIFT")
        for k in sorted(self.keys - want):
            self.bot.up(k)
        for k in sorted(want - self.keys):
            self.bot.down(k)
        self.keys = want

    def stand(self):
        self.set_move(None)

    def detour(self, me, pt):
        """A waypoint round the first pillar / stump standing on the straight line to pt (None: the line is clear)."""
        for q in self.pillars:
            c = q["pos"]
            if dist2(me, c) < q["r"] + 0.2 or dist2(pt, c) < q["r"] + 0.2:
                continue
            if seg_dist(c, me, pt) < q["r"] + 0.5:
                d = unit(pt[0] - me[0], pt[1] - me[1])
                n = (-d[1], d[0])
                lat = (me[0] - c[0]) * n[0] + (me[1] - c[1]) * n[1]
                s = 1.0 if lat >= 0 else -1.0
                return (c[0] + n[0] * s * (q["r"] + 1.0), c[1] + n[1] * s * (q["r"] + 1.0))
        return None

    def goto_pt(self, me, pt, tol=0.3, sprint=True):
        dd = dist2(me, pt)
        if dd <= tol:
            self.stand()
            return True
        wp = self.detour(me, pt) or pt
        self.set_move((wp[0] - me[0], wp[1] - me[1]), sprint and dd > 1.2)
        return False

    def roll(self, vec, why=""):
        """Roll along vec: hold its keys first (the roll takes the held direction), then CTRL."""
        self.set_move(vec, True)
        time.sleep(0.05)
        self.bot.tap("CTRL", 0.05)
        self.last_roll = time.time()
        self.stats["rolls"] += 1
        if why:
            self.log(f"warden: roll ({why})")
        return True

    def swing(self):
        if time.time() - self.last_swing >= self.SWING_EVERY:
            self.bot.tap("LMB", 0.05)
            self.last_swing = time.time()
            self.stats["swings"] += 1

    def look(self, me, pt, tol=35.0):
        """Turns the camera toward pt when far off (cosmetic for visible runs; never while moving)."""
        if self.keys:
            return
        d = angle_diff(yaw_to(me, pt), self.cam)
        if abs(d) > tol:
            step = max(-40.0, min(40.0, d))
            try:
                self.bot.mouse_move(-step * self.bot.px_per_deg * self.bot.invert * 0.8, 0)
            except Exception:  # noqa: BLE001
                pass

    # ------------------------------------------------------------------ geometry
    def plan_ok(self, pt, margin=0.75):
        if dist2(pt, self.ac) > self.SAFE_R:
            return False
        if to_uv(pt)[0] < self.EDGE_U:
            return False
        return all(dist2(pt, q["pos"]) >= q["r"] + margin for q in self.pillars)

    def escape_point(self, me, c, radius):
        """The nearest bench point at `radius` from c (not through the middle, clear of pillars), or None."""
        best = None
        for k in range(24):
            a = math.tau * k / 24.0
            pt = (c[0] + math.cos(a) * radius, c[1] + math.sin(a) * radius)
            if not self.plan_ok(pt):
                continue
            cost = dist2(me, pt)
            if seg_dist(c, me, pt) < radius * 0.55:
                cost += 6.0
            if self.detour(me, pt) is not None:
                cost += 2.0
            if best is None or cost < best[0]:
                best = (cost, pt)
        return best[1] if best else None

    def pillar_near(self, pt, tol):
        for q in self.pillars:
            if q["intact"] and dist2(pt, q["pos"]) <= q["r"] + tol:
                return q["id"]
        return None

    def lane_blocked(self, w, x, skip_id):
        """Does another pillar / stump stand in the Warden's way from w toward x (ahead of its body centre, within its
        0.9 m body + the obstacle's radius of the line)? A stump would bonk the charge, another pillar take the hit."""
        d = unit(x[0] - w[0], x[1] - w[1])
        length = dist2(w, x)
        for o in self.pillars:
            if o["id"] == skip_id:
                continue
            rel = (o["pos"][0] - w[0], o["pos"][1] - w[1])
            along = rel[0] * d[0] + rel[1] * d[1]
            if along <= 0.0 or along >= length:
                continue
            if abs(rel[0] * d[1] - rel[1] * d[0]) < o["r"] + 1.0:
                return True
        return False

    def bait_spot(self, el, me, w, min_ws, time_limit=None):
        """(spot, pillar pos, pillar id): stand here - on the line from the Warden to an intact pillar, BAIT_D in
        front of it - so the charge lane runs through her into the pillar. The lane must be free of other pillars /
        stumps and short enough for its charge; the spot at least min_ws from the Warden and reachable in time."""
        best = None
        reach = float(el.get("charge_distance", 12.0))
        for q in self.pillars:
            if not q["intact"]:
                continue
            x = q["pos"]
            dwx = dist2(w, x)
            if dwx < 0.5 or dwx - q["r"] - 0.9 > reach - 0.5:
                continue                          # its lane (clipped at the charge reach) would stop short of the pillar
            if self.lane_blocked(w, x, q["id"]):
                continue
            u = unit(w[0] - x[0], w[1] - x[1])
            for bd in self.BAIT_D:
                if dwx - bd < min_ws:
                    continue
                spot = (x[0] + u[0] * bd, x[1] + u[1] * bd)
                if not self.plan_ok(spot, margin=0.5):
                    continue
                travel = dist2(me, spot)
                if time_limit is not None and travel / self.SPRINT > time_limit:
                    continue
                # keep the current pillar (hysteresis); a spot beyond its 9 m charge reach means a long run with it following
                score = travel + (0.0 if q["id"] == self.bait else 1.5) + 0.5 * max(0.0, dwx - bd - 9.0)
                if best is None or score < best[3]:
                    best = (spot, x, q["id"], score)
                break
        return best

    # ------------------------------------------------------------------ the loop
    def fight_seconds(self):
        if self.t_engaged is None:
            return None
        return round((self.t_won or time.time()) - self.t_engaged, 1)

    def summary(self) -> dict:
        el = self.el_last or {}
        out = dict(self.stats)
        out["fight_s"] = self.fight_seconds()
        out["exposure_damage"] = self.exposure_damage
        out["game"] = {k: el.get(k) for k in ("exposures", "exposures_capped", "pulses_fired", "charges_done",
                                              "pillars_cracked", "slams_done", "give_ups", "ledge_stops", "edge_holds",
                                              "last_charge_result", "phase", "hp")}
        return out

    def run(self) -> bool:
        t_end = time.time() + self.timeout
        try:
            while time.time() < t_end:
                s = self.p.st()
                if F["warden"] in (s.get("flags") or []):
                    self.t_won = self.t_won or time.time()
                    break
                self.tick(s)
                time.sleep(0.02)
        finally:
            try:
                self.stand()
                self.bot.release_all()
            except Exception:  # noqa: BLE001
                pass
        ok = self.p.wait(lambda st: F["warden"] in st.get("flags", []), 6.0) is not None
        if ok and self.t_won is None:
            self.t_won = time.time()
        if self.expose_hp is not None and ok:
            self.exposure_damage.append(round(self.expose_hp, 1))       # it fell during the exposure
            self.expose_hp = None
        return ok

    def tick(self, s):
        if s.get("mode") == "dead" or self.p.deaths > self.deaths0:
            return self.on_death()
        if s.get("ui_stack"):
            self.stand()
            self.p.dismiss_popups()
            return
        pl = s.get("player") or {}
        pos = pl.get("pos") or [0.0, 0.0, 0.0]
        me = (pos[0], pos[2])
        self.cam = float(pl.get("cam_yaw") or 0.0)
        self.facing = pl.get("facing_yaw")
        self.stamina = float(pl.get("stamina", 100.0) or 0.0)
        hp = float(pl.get("hp", 100.0))
        el = self.seg.elite(s)
        if el is None:
            # not in view (just respawned, or walked away): back to the arena entry
            self.stand()
            if dist2(me, WARDEN_ENTRY) > 3.0:
                self.seg.qgoto(WARDEN_ENTRY, tol=2.0, timeout=20)
            else:
                time.sleep(0.3)
            return
        self.el_last = el
        ac = (el.get("arena") or {}).get("center") or [ARENA[0], 0.0, ARENA[1]]
        self.ac, self.ay = (ac[0], ac[2]), float(ac[1])
        self.pillars = [{"id": str(q.get("id")), "pos": (q["pos"][0], q["pos"][2]), "r": float(q.get("r", 0.85)),
                         "intact": bool(q.get("intact", True))} for q in el.get("pillars", []) if q.get("pos")]
        w = (el["pos"][0], el["pos"][2])
        on_floor = bool(el.get("player_on_arena_floor", True))
        self.track(el, me, w, hp, on_floor)
        if not on_floor:
            if pos[1] < self.ay - 0.9 or q_level(to_uv(me)) < 2:
                self.stand()
                self.stats["climbs"] += 1
                self.seg.warden_note(f"S2 Warden: climbed back onto the bench from uv {tuple(round(x, 1) for x in to_uv(me))} "
                                     f"(Warden {el.get('state')}, hp {el.get('hp')}, off its floor {el.get('off_floor_time')} s)")
                self.seg.climb_to_bench()
                return
            if dist2(me, self.ac) > float(el.get("arena_radius", 10.0)) + 4.0:
                self.goto_pt(me, LESSON_SPOT, tol=1.0)
                return
        if hp < self.EAT_HP and self.safe_to_eat(el, me, w, hp):
            self.stand()
            n = self.p.heal_up(target=80.0, max_items=3)
            self.stats["eats"] += n
            self.log(f"warden: ate {n} (hp {hp:.0f} -> {self.p.hp():.0f}; Warden {el.get('state')} d={dist2(me, w):.1f})")
            return
        self.act(el, me, w)

    def safe_to_eat(self, el, me, w, hp):
        st = str(el.get("state", ""))
        d = dist2(me, w)
        if st in ("telegraph", "slam", "pulses", "charge", "exposed"):
            return False
        if st in ("recover", "stunned"):
            return d >= 4.0 and float(el.get("state_len", 0)) - float(el.get("state_time", 0)) >= 1.2
        return d >= (4.5 if hp < 30 else 6.0)

    def track(self, el, me, w, hp, on_floor):
        """Transitions, counters and the game-rule checks (bugs) the fight can see."""
        st = str(el.get("state", ""))
        whp = float(el.get("hp", 0.0))
        mx = float(el.get("max_hp", 300.0)) or 300.0
        d = dist2(me, w)
        if self.last_hp is not None and hp < self.last_hp - 0.5:
            self.stats["hits_taken"] += 1
            self.stats["damage_taken"] = round(self.stats["damage_taken"] + self.last_hp - hp, 1)
            self.log(f"warden: Krystal hit {self.last_hp:.0f} -> {hp:.0f} (Warden {st}/{el.get('attack_kind')} d={d:.1f})")
        self.last_hp = hp
        if self.last_whp is not None and whp >= mx - 0.5 and self.last_whp < mx - 5.0:
            self.stats["resets"] += 1
            self.log(f"warden: back to full health ({self.last_whp} -> {whp}; state {st}) - the encounter reset")
        self.last_whp = whp
        if on_floor:
            self.on_floor_since = self.on_floor_since or time.time()
        else:
            self.on_floor_since = None
        # a charge ended: its result (and the pillar its locked lane ran into)
        cd = int(el.get("charges_done", 0) or 0)
        if self.charges_seen is None:
            self.charges_seen = cd
        elif cd != self.charges_seen:
            self.charges_seen = cd
            res = str(el.get("last_charge_result", ""))
            self.stats["charge_results"][res] = self.stats["charge_results"].get(res, 0) + 1
            lane_pillar = self.last_lane[2] if self.last_lane else None
            self.log(f"warden: charge ended '{res}' (locked lane ended at pillar {lane_pillar})")
            if res == "wall" and lane_pillar is not None:
                self.p.bug("Quarry Warden: a charge baited into an intact mineral pillar bonks like a wall (no exposure)", "major",
                           "hr_quarry (src/enemies/quarry_warden.gd _charge_stopped_at_wall / _pillar_ahead)",
                           "Stand in front of an intact pillar, side-step the locked charge lane",
                           "the pillar cracks and the Warden is exposed",
                           f"last_charge_result 'wall' with the locked lane ending at intact pillar {lane_pillar} "
                           f"({self.last_lane[0]} -> {self.last_lane[1]})", "s2_bot.log 'charge locked' / 'charge ended' lines")
        gu = int(el.get("give_ups", 0) or 0)
        if self.give_ups_seen is None:
            self.give_ups_seen = gu
        elif gu != self.give_ups_seen:
            self.give_ups_seen = gu
            self.seg.warden_note(f"S2 Warden: it gave up (Krystal off its floor {el.get('off_floor_time')} s) and reset")
            if self.on_floor_since is not None and time.time() - self.on_floor_since > 6.0:
                self.p.bug("Quarry Warden gives up although Krystal stands on its arena floor", "major",
                           "hr_quarry (src/enemies/quarry_warden.gd _tick_extra / player_on_arena_floor)",
                           "Fight the Warden on its arena bench", "it never gives up while she is on its floor",
                           f"give_ups {gu} while player_on_arena_floor was true for {time.time() - self.on_floor_since:.0f} s",
                           "telemetry elite give_ups / player_on_arena_floor")
        # the damage floors (CHAIN-002 shell floor until one exposure; the owed pulses' floor)
        if int(el.get("exposures", 0) or 0) == 0 and self.stats["exposures"] == 0 and bool(el.get("exposure_owed", False)) \
                and 0.0 < whp < mx * 0.5 - 1.0:
            self.p.bug("Quarry Warden drops below its shell floor (50 %) before any pillar exposure", "major",
                       "hr_quarry (src/enemies/quarry_warden.gd shell_floor / _limit_damage)",
                       "Fight the Warden without a pillar exposure", "blows stop at 50 % until the first exposure",
                       f"hp {whp} of {mx} with exposures 0", "telemetry elite hp / exposures")
        if bool(el.get("pulses_owed", False)) and 0.0 < whp < mx * 0.3 - 1.0:
            self.p.bug("Quarry Warden drops below its pulse floor (30 %) while its phase-2 pulses are owed", "major",
                       "hr_quarry (src/enemies/quarry_warden.gd pulse_floor / _limit_damage)",
                       "Take the Warden into phase 2 with an exposure", "blows stop at 30 % until the three pulses played",
                       f"hp {whp} of {mx} with pulses_owed", "telemetry elite hp / pulses_owed")
        if st == self.last_state:
            return
        if self.last_state == "exposed" and self.expose_hp is not None:
            self.exposure_damage.append(round(self.expose_hp - whp, 1))
            self.expose_hp = None
        if st == "exposed":
            self.expose_hp = whp
            self.stats["exposures"] += 1
        if st == "telegraph":
            self.kind = str(el.get("attack_kind", ""))
            self.side = None
            self.side_pt = None
            key = {"slam": "slam_tells", "charge": "charge_tells", "pulses": "pulse_tells"}.get(self.kind)
            if key:
                self.stats[key] += 1
            if not on_floor:
                self.p.bug("Quarry Warden starts an attack while Krystal is off its arena floor", "major",
                           "hr_quarry (src/enemies/quarry_warden.gd _can_start_attack)",
                           "Stand below the arena bench (L1) near the Warden", "no attack across levels",
                           f"telegraph {self.kind} with player_on_arena_floor false (d={d:.1f})", "telemetry elite")
        if st == "chase" and self.t_engaged is None:
            self.t_engaged = time.time()
        tag = f"{st}/{el.get('attack_kind')}" if st == "telegraph" else st
        line = (f"{self.p.elapsed()} {tag} d={d:.1f} whp={whp} ph={el.get('phase')} exp={el.get('exposures')} "
                f"owed={el.get('exposure_owed')} pulses_owed={el.get('pulses_owed')} hp={hp:.0f}")
        self.wlog.append(line)
        self.log("warden " + line)
        self.last_state = st

    def on_death(self):
        self.stand()
        self.bot.release_all()
        self.keys = set()
        self.stats["deaths"] += 1
        self.log("Krystal was defeated in the Warden fight; waiting for the respawn")
        self.deaths0 = self.p.deaths
        self.p.wait(lambda st: st.get("mode") == "playing", 30)
        time.sleep(2.0)
        self.p.dismiss_popups()
        self.p.heal_up(target=90.0, max_items=8)
        self.seg.to_quarry()
        self.p.walk_route(self.seg.near_route_start(TO_WINCH)[:5], tol=2.0)
        self.p.goto(WARDEN_ENTRY, tol=2.0, timeout=25)
        self.last_state = ""
        self.last_hp = None
        self.deaths0 = self.p.deaths

    # ------------------------------------------------------------------ what to do
    def act(self, el, me, w):
        st = str(el.get("state", ""))
        kind = str(el.get("attack_kind", ""))
        d = dist2(me, w)
        if st == "telegraph":
            if kind == "charge":
                return self.charge_tell(el, me, w)
            if kind == "pulses":
                return self.pulse_dodge(el, me, w)
            return self.slam_dodge(el, me, w, d)
        if st == "charge":
            return self.charging(el, me, w)
        if st == "pulses":
            return self.pulse_dodge(el, me, w)
        if st == "slam":
            return self.slam_dodge(el, me, w, d)
        if st in ("exposed", "recover", "stunned"):
            return self.punish(el, me, w, d)
        if st in ("dead", "dying"):
            return self.stand()
        return self.position(el, me, w, d)

    def charge_tell(self, el, me, w):
        """The charge wind-up: until the lane locks, get IN FRONT of a pillar on its line; then side-step across it."""
        lock_in = float(el.get("lock_in", 0.0) or 0.0)
        if not el.get("locked") and lock_in > 0.05:
            b = self.bait_spot(el, me, w, min_ws=2.5, time_limit=lock_in - 0.35)
            if b is not None and dist2(me, b[0]) > 2.6:
                b = None                          # a long run round the tracking Warden rarely ends on its line
            if b is None:
                self.stand()
                return
            if self.bait != b[2]:
                self.log(f"warden charge tell: bait pillar {b[2]} - stand at {tuple(round(x, 1) for x in b[0])} "
                         f"({dist2(me, b[0]):.1f} m away, lock in {lock_in:.2f}s)")
            self.bait = b[2]
            self.goto_pt(me, b[0], tol=0.3)
            return
        self.side_step(el, me, w)

    def lane_frame(self, el, w):
        lane = el.get("lane") or {}
        f = el.get("fwd") or [0.0, -1.0]
        a = xz(lane["from"]) if lane.get("from") else w
        b = xz(lane["to"]) if lane.get("to") else (w[0] + f[0] * 8.0, w[1] + f[1] * 8.0)
        dvec = unit(b[0] - a[0], b[1] - a[1])
        if dvec == (0.0, 0.0):
            dvec = unit(f[0], f[1])
        return a, b, dvec, (-dvec[1], dvec[0])

    def side_step(self, el, me, w):
        a, b, dvec, n = self.lane_frame(el, w)
        rel = (me[0] - a[0], me[1] - a[1])
        lat = rel[0] * n[0] + rel[1] * n[1]
        along = rel[0] * dvec[0] + rel[1] * dvec[1]
        length = dist2(a, b)
        half = float(el.get("lane_width", 2.2) or 2.2) / 2.0 + 0.35
        if self.side is None:
            if abs(lat) >= half + 0.9 or along < -1.2 or along > length + 2.0:
                self.stand()                      # not in its lane: nothing to dodge
                return
            opts = []
            for sgn in (1.0, -1.0):
                pt = (me[0] + n[0] * (sgn * self.SIDE - lat), me[1] + n[1] * (sgn * self.SIDE - lat))
                ok = self.plan_ok(pt, margin=0.45)
                cost = abs(sgn * self.SIDE - lat) + (0.0 if ok else 50.0) + 0.05 * dist2(pt, self.ac)
                opts.append((cost, sgn, pt, ok))
            opts.sort()
            _, sgn, pt, ok = opts[0]
            self.side, self.side_pt = sgn, pt
            vec = (pt[0] - me[0], pt[1] - me[1])
            rolled = False
            if self.stamina >= 22.0:
                rolled = self.roll(vec)
            else:
                self.set_move(vec, True)
            self.stats["sidesteps"] += 1
            end_pillar = self.pillar_near(b, 2.3)
            self.last_lane = (tuple(round(x, 1) for x in a), tuple(round(x, 1) for x in b), end_pillar)
            self.log(f"warden charge locked: lane {self.last_lane[0]}->{self.last_lane[1]} ({length:.1f} m) ends at "
                     f"pillar {end_pillar}; she is {lat:+.2f} m off its line, {along:.1f} m along: side-step "
                     f"{'roll' if rolled else 'sprint'} to {tuple(round(x, 1) for x in pt)} (bench ok={ok})")
            return
        if dist2(me, self.side_pt) > 0.35:
            self.set_move((self.side_pt[0] - me[0], self.side_pt[1] - me[1]), True)
        else:
            self.stand()

    def charging(self, el, me, w):
        lane = el.get("lane") or {}
        a, b, dvec, n = self.lane_frame(el, w)
        half = float(el.get("lane_width", 2.2) or 2.2) / 2.0 + 0.35
        rel = (me[0] - w[0], me[1] - w[1])
        lat = rel[0] * n[0] + rel[1] * n[1]
        ahead = rel[0] * dvec[0] + rel[1] * dvec[1]
        left = dist2(w, b)
        if lane.get("moving", True) and abs(lat) < half + 0.15 and -0.6 < ahead < left + 1.6:
            sgn = self.side or (1.0 if lat >= 0 else -1.0)
            if time.time() - self.last_roll > 0.5 and self.stamina >= 20.0:
                self.roll((n[0] * sgn, n[1] * sgn), why=f"still in the charging Warden's lane (lat {lat:+.2f}, ahead {ahead:.1f})")
            else:
                self.set_move((n[0] * sgn, n[1] * sgn), True)
            return
        if self.side_pt is not None and dist2(me, self.side_pt) > 0.35:
            self.set_move((self.side_pt[0] - me[0], self.side_pt[1] - me[1]), True)
            return
        self.stand()

    def pulse_dodge(self, el, me, w):
        """The pulse wind-up / the pulses: leave the ring before the next beat, else roll through that beat."""
        ring = el.get("ring") or {}
        c = xz(ring["center"]) if ring.get("center") else w
        radius = float(ring.get("radius", el.get("pulse_radius", 5.0)) or 5.0)
        nxt = float(ring.get("next_in", 1.0) or 0.0)
        dc = dist2(me, c)
        if dc >= radius + 0.9:
            self.stand()
            self.look(me, w)
            return
        pt = self.escape_point(me, c, radius + 1.4)
        if pt is not None and dist2(me, pt) / self.SPRINT < nxt - 0.08:
            self.goto_pt(me, pt, tol=0.3)
            return
        if nxt <= 0.22 and time.time() - self.last_roll > 0.45 and self.stamina >= 20.0:
            out = pt or (me[0] + (me[0] - c[0]), me[1] + (me[1] - c[1]))
            self.roll((out[0] - me[0], out[1] - me[1]), why=f"pulse beat in {nxt:.2f}s, {dc:.1f} m from the ring centre")
            return
        if pt is not None:
            self.goto_pt(me, pt, tol=0.3)
        else:
            self.stand()

    def slam_dodge(self, el, me, w, d):
        reach = float(el.get("slam_reach", 3.8) or 3.8)
        if d >= reach + 0.9:
            self.stand()
            self.look(me, w)
            return
        if str(el.get("state")) == "slam":
            f = el.get("fwd") or [0.0, -1.0]
            to = unit(me[0] - w[0], me[1] - w[1])
            ang = math.degrees(math.acos(max(-1.0, min(1.0, to[0] * f[0] + to[1] * f[1]))))
            if ang <= float(el.get("slam_arc", 70.0)) / 2.0 + 12.0 and time.time() - self.last_roll > 0.45 \
                    and self.stamina >= 20.0:
                pt = self.escape_point(me, w, reach + 1.25) or (me[0] + to[0] * 2.0, me[1] + to[1] * 2.0)
                self.roll((pt[0] - me[0], pt[1] - me[1]), why=f"inside the falling slam's wedge (d {d:.1f}, {ang:.0f} deg)")
            return
        pt = self.escape_point(me, w, reach + 1.25)
        if pt is not None:
            self.goto_pt(me, pt, tol=0.3)
        else:
            to = unit(me[0] - w[0], me[1] - w[1])
            self.set_move(to, True)

    def bait_min_ws(self, el):
        """How far from the Warden a bait spot must be: beyond slam reach (else it slams), unless its shell holds -
        then it charges at any range (CHAIN-002)."""
        return 2.8 if el.get("shell_holds") else float(el.get("slam_reach", 3.8) or 3.8) + 0.6

    def punish(self, el, me, w, d):
        """An open window (exposed / recover / stunned): run in and strike while it lasts. Recover / stun windows are
        left early enough to stand at the next bait spot when it ends (after a missed charge its cooldown is already
        over), and skipped while blows only glance off the shell floor (an exposure is owed and its health sits at
        the floor): the pillar bait comes first then."""
        st = str(el.get("state", ""))
        left = float(el.get("state_len", 0.0) or 0.0) - float(el.get("state_time", 0.0) or 0.0)
        if st != "exposed" and el.get("charge_unlocked") and not el.get("pulses_owed"):
            b = self.bait_spot(el, me, w, min_ws=self.bait_min_ws(el))
            if b is not None:
                mx = float(el.get("max_hp", 300.0) or 300.0)
                at_floor = bool(el.get("exposure_owed")) and float(el.get("hp", mx)) <= float(el.get("shell_floor", 0.0) or 0.0) + 1.0
                if at_floor or left <= dist2(me, b[0]) / self.SPRINT + 0.4:
                    if self.bait != b[2] or not getattr(self, "_left_window", False):
                        self.log(f"warden: {'blows glance off its shell floor' if at_floor else f'{left:.1f}s of {st} left'}"
                                 f" - to the bait spot of {b[2]} at {tuple(round(x, 1) for x in b[0])}")
                    self._left_window = True
                    return self.position(el, me, w, d)
        self._left_window = False
        if d > self.REACH:
            need = (d - self.REACH) / self.SPRINT + 0.2
            if st == "exposed" or left > need + 0.25:
                u = unit(me[0] - w[0], me[1] - w[1])
                tgt = (w[0] + u[0] * (self.REACH - 0.35), w[1] + u[1] * (self.REACH - 0.35))
                self.goto_pt(me, tgt, tol=0.25)
                return
            return self.position(el, me, w, d)            # too far for this window: get ready for the next bait
        if self.facing is not None and abs(angle_diff(yaw_to(me, w), float(self.facing))) > 75.0:
            self.set_move((w[0] - me[0], w[1] - me[1]), False)   # turn her body toward the bell
            time.sleep(0.06)
        self.stand()
        self.swing()

    def position(self, el, me, w, d):
        """Between attacks: the slam lesson, meeting the owed pulses, or standing in front of a pillar."""
        if not el.get("charge_unlocked", False):
            # the lesson: it only slams until its first slam - let it come (it slams from 3.4 m)
            if d > 3.3:
                if d > 7.0 and dist2(me, LESSON_SPOT) > 1.0:
                    self.goto_pt(me, LESSON_SPOT, tol=0.8)
                else:
                    u = unit(me[0] - w[0], me[1] - w[1])
                    self.goto_pt(me, (w[0] + u[0] * 3.0, w[1] + u[1] * 3.0), tol=0.4, sprint=False)
            else:
                self.stand()
                self.look(me, w)
            return
        if el.get("pulses_owed", False):
            # phase 2 opens with its three pulses (from ~4 m): meet it on open bench, room to step out of the ring
            best = None
            for k in range(16):
                a = math.tau * k / 16.0
                pt = (w[0] + math.cos(a) * 3.4, w[1] + math.sin(a) * 3.4)
                if not self.plan_ok(pt, margin=1.0):
                    continue
                cost = dist2(me, pt) + 0.8 * dist2(pt, self.ac)
                if best is None or cost < best[0]:
                    best = (cost, pt)
            if best is not None and d > 3.2:
                self.goto_pt(me, best[1], tol=0.5)
            else:
                self.stand()
                self.look(me, w)
            return
        b = self.bait_spot(el, me, w, min_ws=self.bait_min_ws(el))
        if b is not None:
            if self.bait != b[2]:
                self.log(f"warden: bait pillar {b[2]} - stand at {tuple(round(x, 1) for x in b[0])} "
                         f"(Warden {d:.1f} m off, {el.get('state')})")
            self.bait = b[2]
            if not self.goto_pt(me, b[0], tol=0.3):
                return
            self.look(me, w)
            return
        # no pillar to bait now (every one cracked, or it stands by them): keep ~5 m off and punish its openings
        if self.bait is not None:
            self.log(f"warden: no pillar to bait (intact {[q['id'] for q in self.pillars if q['intact']]}); keeping 5 m off")
        self.bait = None
        u = unit(me[0] - w[0], me[1] - w[1])
        tgt = (w[0] + u[0] * 5.0, w[1] + u[1] * 5.0)
        if not self.plan_ok(tgt):
            tgt = self.escape_point(me, w, 5.0) or tgt
        self.goto_pt(me, tgt, tol=0.6)


def run(bot, out_dir, opts=None) -> dict:
    """Plays segment S2 on a running game that is in the Reach. Returns the result dict."""
    opts = opts or {}
    seg = Segment(bot, out_dir, opts)
    p = seg.p
    t0 = time.time()
    status = "completes"
    stopped_at = ""
    seg.result_verify = {}
    try:
        p.dismiss_popups()
        bot.calibrate_look()
        seg.checkpoint("s2_start", True, f"inv={p.st().get('inv')} flags_ch2={[f for f in p.flags() if f.startswith('ch2_')]}")
        seg.step("to_orchard", seg.to_orchard)
        seg.step("light_orchard_arch", lambda: seg.light_arch("orchard", ORCHARD_ARCH), required=False)
        seg.step("find_orchard_lamp", seg.find_orchard_lamp)
        seg.step("seed_box_note", seg.seed_box_note, required=False)
        seg.step("irrigation", seg.irrigation)
        seg.step("plant_festival_seed", seg.plant_seed, required=False)
        seg.step("mimic_pocket", seg.mimic_pocket)
        seg.step("light_garden_lamp", seg.light_garden_lamp)
        seg.step("garden_seal", seg.check_garden_seal, required=False)
        if opts.get("save_checkpoints", True):
            seg.save_game("orchard_done")
        if opts.get("patchwalker", True):
            seg.step("patchwalkers_optional", seg.patchwalkers, required=False)
        seg.step("gather_food", seg.gather_food, required=False)
        seg.step("to_quarry", seg.to_quarry)
        seg.step("light_quarry_arch", lambda: seg.light_arch("quarry", QUARRY_ARCH), required=False)
        seg.step("gather_wood", seg.gather_wood)
        seg.step("mine_iron", seg.mine_iron)
        seg.step("to_winch_find_lamp", seg.to_winch)
        seg.step("quarry_lamp_found", lambda: p.wait(lambda s: F["found_quarry"] in s.get("flags", []), 6.0) is not None,
                 required=False)
        seg.step("repair_winch", seg.repair_winch)
        if opts.get("save_checkpoints", True):
            seg.save_game("winch_done")
        seg.step("quarry_warden", seg.fight_warden)
        seg.step("light_quarry_lamp", seg.climb_and_light)
        seg.step("verify", seg.verify, required=False)
        if opts.get("reload_check", True):
            seg.step("save_quit_continue", seg.reload_check, required=False)
        if opts.get("visit_manor"):
            seg.step("manor_lamp_found_optional", seg.visit_manor_approach, required=False)
            seg.step("verify_after_manor", seg.verify, required=False)
    except StepFailed as e:
        status = "stops"
        stopped_at = str(e)
        seg.log(f"SEGMENT STOPPED: {e}")
    except Exception as e:  # noqa: BLE001
        status = "stops"
        stopped_at = f"crash {type(e).__name__}: {e}"
        seg.log(traceback.format_exc())
    finally:
        try:
            bot.release_all()
        except Exception:  # noqa: BLE001
            pass
    s = {}
    try:
        s = p.st()
    except Exception:  # noqa: BLE001
        pass
    return {"segment": "S2", "status": status, "stopped_at": stopped_at, "seconds": round(time.time() - t0, 1),
            "checkpoints": seg.checkpoints, "timings": seg.timings, "screenshots": p.shots, "problems": p.problems,
            "bugs": p.bugs, "deaths": p.deaths, "warden_log": seg.warden_log, "verify": seg.result_verify,
            "final": {k: s.get(k) for k in ("area", "zone", "inv", "keys", "chapter2", "tracker", "objective")},
            "messages": p.seen_msgs[-80:]}


def scan_godot_log(path) -> dict:
    """Unique SCRIPT ERROR / ERROR locations in the game's stdout log: {location: {count, message, first_line}}."""
    out: dict = {}
    try:
        lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return out
    for i, ln in enumerate(lines):
        if ln.startswith("SCRIPT ERROR:") or ln.startswith("ERROR:"):
            loc = ""
            for j in range(i + 1, min(i + 4, len(lines))):
                if lines[j].strip().startswith("at:"):
                    loc = lines[j].strip()[3:].strip()
                    break
            key = loc or ln
            e = out.setdefault(key, {"count": 0, "message": ln.strip(), "first_line": i + 1})
            e["count"] += 1
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run-dir", default=str(ROOT / "qa" / "tmp" / "bot" / "s2" / "run1"))
    ap.add_argument("--save", default="", help="start save (slot1.json) to copy into the run's save folder; default: "
                    "the S2 diagnostic fixture built by s2_fixture.py from the real handoff save")
    ap.add_argument("--attempt", type=int, default=1, help="port = 7200 + attempt")
    ap.add_argument("--port", type=int, default=0, help="QA input port (overrides --attempt; bumped by 10 while taken)")
    ap.add_argument("--warden-timeout", type=float, default=420.0, help="seconds the Quarry Warden fight may take")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--max-seconds", type=int, default=2400, help="game watchdog (--max-seconds)")
    ap.add_argument("--no-patchwalker", action="store_true")
    ap.add_argument("--visit-manor", action="store_true", help="afterwards walk until the manor lamp is found (seal check)")
    ap.add_argument("--no-save-checkpoints", action="store_true")
    ap.add_argument("--no-reload-check", action="store_true", help="skip the final Save & Quit -> Continue check")
    a = ap.parse_args()
    run_dir = Path(a.run_dir).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    save_dir = run_dir / "saves"
    if save_dir.exists():
        shutil.rmtree(save_dir)
    save_dir.mkdir(parents=True)
    if a.save:
        shutil.copy2(a.save, save_dir / "slot1.json")
        start_kind = f"save {a.save}"
    else:
        s2_fixture.write(save_dir)
        start_kind = "diagnostic fixture start (tools/qa/ch2/s2_fixture.py from 16_real_handoff_c1_complete.json)"
    port = pick_port(2, a.attempt)
    if a.port:
        port = next((p for p in range(a.port, a.port + 100, 10) if port_free(p)), a.port)
    g = HeadlessGame(run_dir, "s2", port, max_seconds=a.max_seconds, seed=a.seed)
    t_launch = time.time()
    result: dict = {"segment": "S2", "status": "stops", "stopped_at": "launch"}
    try:
        bot = g.start()
        s = bot.wait_state(lambda st: st.get("mode") == "title" and any("Continue" in b.get("text", "") for b in st.get("buttons", [])), 120)
        if not s:
            raise RuntimeError("title screen with Continue never appeared")
        t_title = time.time()
        if not bot.click_button("Continue", timeout=10):
            raise RuntimeError("could not click Continue")
        if not bot.wait_state(lambda st: st.get("mode") == "playing" and st.get("area") == AREA, 120):
            raise RuntimeError("never reached the Reach after Continue")
        time.sleep(2.5)
        t_play = time.time()
        opts = {"patchwalker": not a.no_patchwalker, "visit_manor": a.visit_manor, "warden_timeout": a.warden_timeout,
                "save_checkpoints": not a.no_save_checkpoints,
                "reload_check": not a.no_reload_check}
        result = run(bot, run_dir, opts)
        result["boot"] = {"launch_to_title_s": round(t_title - t_launch, 1), "continue_to_play_s": round(t_play - t_title, 1)}
    except Exception as e:  # noqa: BLE001
        result["stopped_at"] = f"{type(e).__name__}: {e}"
        traceback.print_exc()
    finally:
        g.stop()
    result["script_errors"] = scan_godot_log(g.godot_log)
    for loc, info in result["script_errors"].items():
        result.setdefault("bugs", []).append({
            "title": f"SCRIPT ERROR during the S2 route at {loc} ({info['count']}x)", "severity": "major",
            "area": loc.split(" (")[-1].rstrip(")") if " (" in loc else loc,
            "steps": "Play segment S2 (tools/qa/ch2/s2_orchard_quarry.py) headless from the S2 start",
            "expected": "no script errors", "actual": info["message"],
            "evidence": f"{g.godot_log} (first at line {info['first_line']})"})
    result["start"] = start_kind
    result["run_dir"] = str(run_dir)
    result["total_wall_s"] = round(time.time() - t_launch, 1)
    (run_dir / "s2_result.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    (run_dir / "bugs.json").write_text(json.dumps(result.get("bugs", []), indent=1), encoding="utf-8")
    print(json.dumps({k: result.get(k) for k in ("status", "stopped_at", "seconds", "total_wall_s", "problems", "timings")}, indent=1))


if __name__ == "__main__":
    main()
