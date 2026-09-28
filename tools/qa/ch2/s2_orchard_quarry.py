"""Segment S2 of the Chapter Two route bot: Hallowmere Reach west (Pumpkintide Orchard) + east (Ashbell Quarry).

Start: Lanternwake Commons with Chapter Two accepted, the waygate repaired, the Commons arch lit and the festival
map read (what segments S0/S1 leave behind). Route, with normal keyboard/mouse input only (virtual input):
  orchard: walk the west road to the orchard arch (light it) -> find the garden lamp -> open the seed box (note) ->
           raise the garden sluice gate + turn the junction sluice (water reaches the garden) -> plant the
           festival seed -> inspect a twitching pumpkin and clear the taught Pumpkin Mimic pocket -> light the
           garden lamp -> [optional] the Patchwalker field -> gather a little food
  quarry:  walk to the quarry arch (light it) -> chop wood if short -> mine iron on the lower terraces ->
           reach the winch (finds the quarry lamp) -> repair the winch (6 wood, 6 stone, 4 iron ore) -> defeat the
           Quarry Warden (bait its charge into a mineral pillar, punish the exposed bell) -> climb the gangway ->
           light the quarry lamp
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

from s2_lib import HeadlessGame, Play, StepFailed, dist2, pick_port, xz, ROOT  # noqa: E402
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
        self.cracked: dict = {}          # pillar index -> time it cracked (telemetry has no pillar state)
        self._tele_kind = None
        self._expose_hp = None
        self._fight_t0 = 0.0
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

    def pillar_ok(self, i):
        t = self.cracked.get(i)
        return t is None or time.time() - t > 26.0

    def bait_point(self, w, i):
        """Where to stand so pillar i sits between the Warden and Krystal (2.6 m behind it, 1.4 m to the side)."""
        px, pz = PILLARS[i]
        wx, wz = xz(w["pos"])
        dx, dz = px - wx, pz - wz
        d = math.hypot(dx, dz) or 1.0
        ux, uz = dx / d, dz / d
        me = xz(self.p.pos())
        # choose the side nearer to where she is
        sx, sz = -uz, ux
        side = 1.0 if ((me[0] - px) * sx + (me[1] - pz) * sz) >= 0 else -1.0
        return (px + ux * 2.6 + sx * side * 1.4, pz + uz * 2.6 + sz * side * 1.4), d

    @staticmethod
    def on_bench(pt):
        u, v = to_uv(pt)
        return -1.0 <= u <= 19.0 and -11.0 <= v <= 11.0 and dist2(pt, ARENA) <= 11.0

    def fight_warden(self):
        if self.flag("warden"):
            return True
        self.p.heal_up(target=90.0, max_items=8)
        # enter the arena from the west side of the bench (the winch side)
        self.p.goto(quv(8.0, -9.0), tol=2.0, timeout=25)
        t_end = time.time() + float(self.opts.get("warden_timeout", 420))
        self._fight_t0 = self.p.elapsed()
        slams = 0
        exposures = 0
        last_state = ""
        tele_t = None
        mode = "slam_lesson"
        deaths0 = self.p.deaths
        while time.time() < t_end:
            if self.flag("warden"):
                break
            if self.p.ui_open():
                self.p.dismiss_popups()
            s = self.p.st()
            if s.get("mode") == "dead" or self.p.deaths > deaths0:
                self.log("Krystal was defeated in the Warden fight; waiting for the respawn")
                deaths0 = self.p.deaths
                self.p.wait(lambda st: st.get("mode") == "playing", 30)
                time.sleep(2.0)
                self.p.dismiss_popups()
                self.p.heal_up(target=90.0, max_items=8)
                self.to_quarry()
                self.p.walk_route(self.near_route_start(TO_WINCH)[:5], tol=2.0)
                self.p.goto(quv(8.0, -9.0), tol=2.0, timeout=25)
                slams = 0
                mode = "slam_lesson"
                continue
            w = self.warden()
            if w is None:
                self.p.goto(quv(6.0, -4.0), tol=2.0, timeout=10)
                time.sleep(0.5)
                continue
            st = str(w.get("state", ""))
            wp = xz(w["pos"])
            me = xz(self.p.pos())
            d = dist2(wp, me)
            hp = self.p.hp()
            if st != last_state:
                if last_state == "exposed" and self._expose_hp is not None:
                    dealt = round(self._expose_hp - float(w.get("hp", 0)), 1)
                    self.exposure_damage.append(dealt)
                    self._expose_hp = None
                if st == "exposed":
                    self._expose_hp = float(w.get("hp", 0))
                self.warden_log.append(f"{self.p.elapsed()} {st} d={d:.1f} whp={w.get('hp')} hp={hp}")
                self.log(f"warden {last_state}->{st} d={d:.1f} whp={w.get('hp')} my hp={hp} mode={mode}")
                if st == "telegraph":
                    tele_t = time.time()
                    self._tele_kind = None
                if st == "slam":
                    slams += 1
                if st == "exposed":
                    exposures += 1
                    # which pillar cracked: the intact one nearest to the Warden
                    cand = [i for i in range(len(PILLARS)) if self.pillar_ok(i)]
                    if cand:
                        i = min(cand, key=lambda k: dist2(PILLARS[k], wp))
                        self.cracked[i] = time.time()
                last_state = st
            if st in ("dead", "dying"):
                if self._expose_hp is not None:
                    self.exposure_damage.append(round(self._expose_hp, 1))
                    self._expose_hp = None
                time.sleep(1.0)
                continue
            if hp < 38 and st not in ("exposed",):
                # back off and eat (panels may pause; either way it is what a player would do)
                self.p.dodge("S")
                self.p.heal_up(target=75.0, max_items=4)
                continue
            if st in ("exposed", "recover", "stunned"):
                # punish window: run in and swing (around a pillar / its stump if one stands in between)
                if d > 2.9:
                    detour = self.detour_point(me, wp)
                    if detour is not None:
                        self.bot.walk_to((detour[0], 0, detour[1]), tol=0.6, timeout=1.0, sprint=True, avoid=False)
                    else:
                        self.p.face((wp[0], 0, wp[1]), tol=10)
                        self.bot.hold("W", min(0.45, (d - 2.4) / 6.0 + 0.1))
                else:
                    self.p.face((wp[0], 0, wp[1]), tol=12)
                    self.bot.tap("LMB", 0.06)
                    time.sleep(0.42)
                continue
            if st == "telegraph":
                since = time.time() - (tele_t or time.time())
                if tele_t is not None and self._tele_kind is None:
                    # the Warden picks slam / pulses within slam reach (3.6 m) and a charge beyond it
                    self._tele_kind = "close" if d <= 3.9 else "charge"
                    self.log(f"warden telegraph kind guess: {self._tele_kind} (d={d:.1f})")
                if self._tele_kind == "close":
                    # slam wedge (3.8 m) or phase-2 pulse ring (5 m): two rolls straight back
                    self.p.face((wp[0], 0, wp[1]), tol=15)
                    self.p.dodge("S")
                    time.sleep(0.12)
                    self.p.dodge("S")
                    self._tele_kind = "done"
                    time.sleep(0.2)
                    continue
                if self._tele_kind == "charge":
                    # the lane tracks her for 60 % of the 1.6 s tell, then locks: roll sideways after the lock
                    if since < 1.12:
                        time.sleep(0.03)
                        continue
                    if not self.lane_blocked(wp, me):
                        self.p.face((wp[0], 0, wp[1]), tol=20)
                        self.p.dodge("A" if (int(time.time() * 10) % 2) else "D")
                    self._tele_kind = "done"
                    time.sleep(0.2)
                    continue
                time.sleep(0.05)
                continue
            if st in ("slam", "pulses", "charge"):
                if st == "charge" and d < 4.0 and not self.lane_blocked(wp, me):
                    self.p.dodge("A")
                elif st == "pulses" and d < 5.5:
                    self.p.face((wp[0], 0, wp[1]), tol=20)
                    self.p.dodge("S")
                time.sleep(0.08)
                continue
            # chase / idle / return / wander: position
            if slams == 0 and exposures == 0 and mode == "slam_lesson":
                # the lesson: let it slam once (it charges only after a slam)
                if d > 3.0:
                    self.p.face((wp[0], 0, wp[1]), tol=10)
                    self.bot.hold("W", min(0.4, (d - 2.6) / 6.0 + 0.1))
                else:
                    self.p.face((wp[0], 0, wp[1]), tol=10)
                    self.bot.tap("LMB", 0.06)
                    time.sleep(0.35)
                continue
            mode = "bait"
            best = None
            for i in range(len(PILLARS)):
                if not self.pillar_ok(i):
                    continue
                pt, dwp = self.bait_point(w, i)
                if not self.on_bench(pt) or dwp < 3.5 or dwp > 10.5:
                    continue
                score = dist2(pt, me)
                if best is None or score < best[0]:
                    best = (score, pt, i)
            if best is None:
                # no usable pillar: fall back to punishing slams / missed charges
                if d > 3.0:
                    self.p.face((wp[0], 0, wp[1]), tol=10)
                    self.bot.hold("W", 0.25)
                else:
                    self.bot.tap("LMB", 0.06)
                    time.sleep(0.35)
                continue
            _, pt, i = best
            if dist2(pt, me) > 0.8:
                self.bot.walk_to((pt[0], 0, pt[1]), tol=0.7, timeout=1.2, sprint=True, avoid=False)
            else:
                self.p.face((wp[0], 0, wp[1]), tol=8)
                time.sleep(0.1)
        ok = self.p.wait(lambda st: F["warden"] in st.get("flags", []), 6.0) is not None
        if self._expose_hp is not None and ok:
            self.exposure_damage.append(round(self._expose_hp, 1))      # it fell during the exposure
            self._expose_hp = None
        self.timings["warden_exposure_damage"] = self.exposure_damage
        big = [x for x in self.exposure_damage if x >= 150.0]
        if big:
            self.p.bug("Quarry Warden: one pillar exposure removes most of its 300 HP (pulse phase can be skipped)", "minor",
                       "hr_quarry (src/enemies/quarry_warden.gd EXPOSED_MULT / EXPOSE_TIME, data/enemies.gd quarry_warden hp)",
                       "Starting gear (copper sword) + Lumi following: let the Warden slam once, bait its charge into a mineral pillar, "
                       "strike the exposed bell for the whole window",
                       "MP 12: side-step/punish lesson, then three spaced ground pulses, then the pillar bait - a multi-step elite fight",
                       f"damage dealt per exposure window: {self.exposure_damage} (x1.6 for 6 s at ~0.45 s per swing = up to ~350); "
                       f"fight length {self.p.elapsed() - self._fight_t0:.0f}s; the Warden often dies before or right after reaching phase 2",
                       "s2_bot.log 'warden' lines; telemetry enemy hp per frame")
        self.log(f"warden fight end: ok={ok} slams={slams} exposures={exposures} cracked={self.cracked} log={self.warden_log[-12:]}")
        self.timings["warden_exposures"] = exposures
        if not ok:
            w = self.warden()
            raise StepFailed(f"Warden not defeated in time (warden {w and (w.get('hp'), w.get('state'))}, hp {self.p.hp()})")
        return True

    @staticmethod
    def detour_point(me, wp):
        """A side step around any pillar (intact or a cracked stump) standing between Krystal and the Warden."""
        dx, dz = wp[0] - me[0], wp[1] - me[1]
        L = math.hypot(dx, dz) or 1.0
        ux, uz = dx / L, dz / L
        for (px, pz) in PILLARS:
            ax, az = px - me[0], pz - me[1]
            along = ax * ux + az * uz
            lat = -ax * uz + az * ux
            if 0.0 < along < L and abs(lat) < 1.5:
                side = -1.0 if lat > 0 else 1.0          # pass on the side away from the pillar centre
                return (px + (-uz) * side * 1.9, pz + ux * side * 1.9)
        return None

    def lane_blocked(self, wp, me):
        """Is an intact pillar between the Warden and Krystal, close enough to the line for its body to hit it?"""
        dx, dz = me[0] - wp[0], me[1] - wp[1]
        L = math.hypot(dx, dz) or 1.0
        ux, uz = dx / L, dz / L
        for i, (px, pz) in enumerate(PILLARS):
            if not self.pillar_ok(i):
                continue
            ax, az = px - wp[0], pz - wp[1]
            along = ax * ux + az * uz
            lat = abs(-ax * uz + az * ux)
            if 1.0 < along < L - 0.3 and lat < 1.6:
                return True
        return False

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
    g = HeadlessGame(run_dir, "s2", pick_port(2, a.attempt), max_seconds=a.max_seconds, seed=a.seed)
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
        opts = {"patchwalker": not a.no_patchwalker, "visit_manor": a.visit_manor,
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
