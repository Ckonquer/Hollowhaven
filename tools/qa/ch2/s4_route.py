"""SEGMENT S4 of the Chapter Two route: from "all three lamps lit" to free play after the Lanternwake.

Plays the game with normal inputs only (keyboard/mouse through the virtual-input transport; the bot perceives
the game through the read-only QA telemetry). No teleport / flag / item cheats. The START state may come from the
documented diagnostic fixture (tools/qa/ch2/s4_fixture.py) or from any save the game itself wrote on this route
(the game saves at every area change and lantern checkpoint; this script snapshots <run>/saves after each passed
checkpoint into <run>/checkpoints/<step>/ so a later run can resume with --start-save).

Checkpoints (each step is idempotent: it checks the world state first and passes through what is already done,
so a run may resume from any save of the route):
  link_lanterns    Conservatory pedestal: "Link the lanterns" -> ch2_lamps_linked
  service_gate     north road -> Sunken Bellhouse stair -> unlock the service gate with the Foreman's Key
                   (ch2_service_gate_open, key kept) -> go down -> hushed_works
  true_signal      Service Landing (light the lantern) -> Tool Lockers (Hollow Drudge) -> Humming Rails ->
                   the rail junction by Hask's lamp (ch2_true_signal)
  refuge           Pocket Conservatory: ch2_refuge_reached, read the refuge record (ch2_refuge_record), turn the
                   wheel (ch2_refuge_shortcut), rest at the refuge lantern
  line_water / line_bell / line_light    the three ward lines (valves, bell order, mirrors), any order
  winch            the lower ward door -> Threaded Winch: burn the threads (lantern raised) -> crossing_gate
                   checkpoint
  crossing         Weaver's Crossing Matron: braziers under the held anchor, dodge pounces, strike exposures
                   -> ch2_crossing_cleared
  wrong_landing    the false lift (short detour into the siding) and the walk back; --loop-b also rides the real
                   lift up to the refuge and the winch cage back down (--real-lift: only the real one)
  false_home       the Borrowed Porch: hold the lantern to the anchored flame -> ch2_false_home_revealed
  bell_throat      rest at the Bell Throat lantern, supplies crate, the miners' note
  choir            the Borrowed Choir: A lantern at anchors + pick the form, B resonators in the bell order,
                   C the kept flame -> ch2_choir_defeated
  return_reach     vault exit bell-lift -> the Reach (ch2_returned_to_reach, routes restored)
  travel_home      Lantern Road from a lit arch -> the Haven
  homecoming       speak to the Ward Stone (ch2_homecoming)
  lanternwake      Ward Stone -> Celebrate the Lanternwake -> celebration, ending card, credits skipped,
                   Continue exploring (chapter_two_complete)
  free_play        free play in the same save: pause-menu save, Ward Stone Lantern Road to the Commons, the refuge
                   hatch down into the Works and the drainage stair back up, light the Conservatory arch, Lantern
                   Road home; then (__main__) a relaunch + Continue check: same save, chapter complete, same items

run(bot, out_dir) -> dict is the library entry (the lead's chained route calls it with a Bot already in play).
__main__ launches the SOURCE build headless from a given save/fixture:
  python tools/qa/ch2/s4_route.py --out qa/tmp/bot/s4/run1 [--fixture | --start-save <dir or slot1.json>]
      [--attempt N] [--from STEP] [--until STEP] [--max-seconds 3000] [--seed N] [--loop-b | --real-lift]
      [--no-relaunch]
Outputs in --out: s4_result.json (checkpoints, timings, shot requests, problems, final state, relaunch check),
s4_bot.log, s4_telemetry.jsonl, s4_godot.log, checkpoints/<step>/ (save snapshots), s4_relaunch_* (the
Continue-after-relaunch check: free play resumes in the same save, items unchanged).
Headless: the game's own "shot" command is refused (no viewport image); the requests are kept so a visible run of
the same route captures them. Information advantage (label it when quoting results): the bot reads positions,
states and prompts from telemetry and the room layout from data/works_layout*.gd; it cannot see lights (Choir
Phase A lit plate, Phase C true flame) and guesses / eliminates there.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from s4_common import (HeadlessGame, Play, StepFailed, dist2, pick_port, place_save, write_json, xz,  # noqa: E402
                       ROOT)
import s4_nav as Nav  # noqa: E402

WORKS = "hushed_works"
REACH = "hallowmere_reach"
SURFACE = "surface"


class S4(Play):
    """The S4 route on top of the Play primitives."""

    # ------------------------------------------------------------------ area navigation
    def graph(self):
        a = self.area()
        if a == WORKS:
            return Nav.WORKS
        if a == REACH:
            return Nav.REACH
        return None

    def nav(self, target, tol: float = 1.2, sprint: bool = True, fight: bool = True, final_tol: float | None = None) -> bool:
        """Walks the area graph from here to `target` ((x, y, z) floor point)."""
        g = self.graph()
        me = self.pos()
        if g is None:
            return self.goto((target[0], target[2]), tol=final_tol or tol, sprint=sprint)
        pts = g.route(me, target, ignore_y=(self.area() != WORKS))
        if not pts:
            self.log(f"nav: no route from {me} to {target}")
            return False
        # skip nodes behind us: start from the node after the nearest one when we are already past it
        if len(pts) >= 2 and dist2(xz(me), xz(pts[1])) < dist2(xz(pts[0]), xz(pts[1])):
            pts = pts[1:]
        pts = list(pts) + [tuple(target)]
        for i, p in enumerate(pts):
            last = i == len(pts) - 1
            if dist2(xz(self.pos()), xz(p)) < (final_tol or tol if last else tol):
                continue
            if fight:
                self.handle_threats()
            ok = self.goto((p[0], p[2]), tol=(final_tol or tol) if last else tol, sprint=sprint, timeout=45)
            if not ok and self.handle_dialog():
                ok = self.goto((p[0], p[2]), tol=(final_tol or tol) if last else tol, sprint=sprint, timeout=45)
            if not ok:
                if fight and self.handle_threats():
                    ok = self.goto((p[0], p[2]), tol=(final_tol or tol) if last else tol + 0.4, sprint=False, timeout=45)
                if not ok:
                    self.problem("nav", f"could not reach {p} on the way to {target}")
                    return False
        return True

    # Dialogs the route expects to meet on the way (the choice a player of this route makes).
    KNOWN_CHOICES = ["Go on to the Choir Vault"]

    def handle_dialog(self) -> bool:
        """A confirm dialog opened on the way (e.g. the Bell Throat's one-time return/continue choice)."""
        if not self.ui():
            return False
        self.wait(lambda s: len(s.get("buttons") or []) > 0, 2.0)      # buttons are collected every 0.2 s
        time.sleep(0.3)
        texts = [b.get("text") for b in self.buttons()]
        for want in self.KNOWN_CHOICES:
            if self.find_button(want):
                self.log(f"dialog {self.ui()}: choosing {want!r} (buttons {texts})")
                self.click_button(want)
                self.wait(lambda s: not s.get("ui_stack"), 4.0)
                return True
        self.problem("dialog", f"unexpected dialog {self.ui()} with buttons {texts}")
        self.close_panels()
        return not self.ui()

    def handle_threats(self, radius: float = 9.0) -> bool:
        live = self.live_enemies(radius, lambda e: e.get("threat", False) or str(e.get("state", "")) in
                                 ("chase", "telegraph", "attack", "recover"))
        live = [e for e in live if "matron" not in str(e.get("name", "")).lower() and "choir" not in str(e.get("name", "")).lower()]
        if not live:
            return False
        self.log(f"threats: {[(e.get('name'), e.get('state'), e.get('dist')) for e in live]}")
        self.fight_smart(timeout=120.0)
        return True

    def fight_smart(self, timeout: float = 120.0, radius: float = 18.0, pred=None) -> bool:
        """Ordinary enemies: step out of telegraphs (sideways for lanes / wedges, back out of rings), punish the
        recovery, keep hp up with food."""
        b = self.bot
        t0 = time.time()
        quiet = time.time()
        side = 1
        while time.time() - t0 < timeout:
            live = self.live_enemies(radius, pred)
            live = [e for e in live if str(e.get("state", "")) not in ("idle", "wander", "return", "sleep") or e["dist"] < 6]
            if not live:
                if time.time() - quiet > 2.5:
                    return True
                time.sleep(0.2)
                continue
            quiet = time.time()
            me = self.pos()
            # 1) any wind-up close by: get out of it first (ring pulses: away from them; lanes / wedges: sideways)
            tele = [e for e in live if str(e.get("state", "")) in ("telegraph", "pulse", "windup", "wind_up") and e["dist"] < 5.6]
            if tele:
                rings = [e for e in tele if "bellcap" in str(e.get("name", "")).lower() or "sentry" in str(e.get("name", "")).lower()]
                if rings:
                    cx = sum(e["pos"][0] for e in rings) / len(rings)
                    cz = sum(e["pos"][2] for e in rings) / len(rings)
                    dx, dz = me[0] - cx, me[2] - cz
                    L = math.hypot(dx, dz) or 1.0
                    away = (me[0] + dx / L * 6.0, me[1], me[2] + dz / L * 6.0)
                    self.face(away, tol=15)
                    b.down("SHIFT")
                    b.hold("W", 0.7)
                    b.up("SHIFT")
                else:
                    self.face(tele[0]["pos"], tol=12)
                    side = -side
                    k = "A" if side < 0 else "D"
                    b.down(k)
                    time.sleep(0.3)
                    b.tap("CTRL")
                    time.sleep(0.3)
                    b.up(k)
                continue
            if self.hp() < 45 and self.eat_best():
                continue
            # 2) punish: prefer an enemy in its recovery
            rec = [e for e in live if str(e.get("state", "")) in ("recover", "flinch", "stunned")]
            e = rec[0] if rec else live[0]
            d = float(e["dist"])
            name = str(e.get("name", "")).lower()
            heavy = "bellcap" in name or "sentry" in name
            self.face(e["pos"], tol=10)
            if heavy and not rec and d < 5.0:
                # a sentry that is not recovering: keep just outside its ring and wait for the pulse
                b.hold("S", 0.25)
                time.sleep(0.1)
                continue
            if d > 2.1:
                b.down("SHIFT") if d > 4 else None
                b.hold("W", min(0.45, (d - 1.7) / 5.0 + 0.08))
                b.up("SHIFT") if d > 4 else None
            else:
                b.tap("LMB", 0.06)
                time.sleep(0.34)
        return False

    # ------------------------------------------------------------------ interactables
    def use(self, words, stand, target, check=None, tries: int = 5, stop: float = 1.0, pitch: float | None = None) -> bool:
        """Walks to `stand` (area graph), faces `target` and presses E on the prompt matching `words`."""
        if stand is not None and dist2(xz(self.pos()), xz(stand)) > 0.8:
            self.nav(stand, final_tol=0.6)
        return self.interact_with(target, words, check=check, tries=tries, stop=stop, pitch=pitch)

    def rest_lantern(self, pos, stand=None) -> bool:
        """Light / rest at a checkpoint lantern (saves)."""
        n0 = sum(1 for m in self.all_msgs if m.get("k") == "saved")
        ok = self.use(["Light the lantern", "Rest by the lantern"], stand, pos,
                      check=lambda: sum(1 for m in self.all_msgs if m.get("k") == "saved") > n0, stop=1.2)
        if not ok:
            self.problem("checkpoint", f"could not light/rest at the lantern at {pos}")
        return ok

    def wait_saved(self, n0: int, timeout: float = 10.0) -> bool:
        return self.wait(lambda s: sum(1 for m in self.all_msgs if m.get("k") == "saved") > n0, timeout) is not None

    def saved_count(self) -> int:
        self.st()
        return sum(1 for m in self.all_msgs if m.get("k") == "saved")

    def wait_area(self, area: str, timeout: float = 60.0) -> bool:
        ok = self.wait(lambda s: s.get("area") == area and s.get("mode") == "playing", timeout) is not None
        time.sleep(1.0)
        return ok

    def ch2_done(self) -> list:
        return list((self.st().get("chapter2") or {}).get("done", []))


# ====================================================================================== the steps
def step_start(p: S4):
    if not p.wait(lambda s: s.get("mode") == "playing" and s.get("area") in (REACH, WORKS, SURFACE), 90):
        raise StepFailed("never reached gameplay")
    time.sleep(1.5)
    p.close_panels()
    p.bot.calibrate_look()
    p.look_pitch(-8.0)
    return True


def step_link_lanterns(p: S4):
    if p.flag("ch2_lamps_linked"):
        return True
    if p.area() != REACH:
        raise StepFailed(f"link_lanterns needs the Reach, in {p.area()}")
    ped = (0.0, 0.0, 6.0)
    p.nav((0.0, 0.0, 8.5), final_tol=0.5)
    p.shot("conservatory_pedestal")
    ok = p.interact_with(ped, ["Link the lanterns"], check=lambda: p.flag("ch2_lamps_linked"), stop=2.3)
    if not ok:
        raise StepFailed(f"could not link: prompt={p.prompt()}")
    time.sleep(3.0)
    p.shot("lanterns_linked")
    return p.wait(lambda s: "ch2_lamps_linked" in (s.get("chapter2") or {}).get("done", []), 6) is not None


def step_service_gate(p: S4):
    if p.area() == WORKS or (p.flag("ch2_service_gate_open") and p.flag("ch2_true_signal")):
        return True
    if p.area() != REACH:
        raise StepFailed(f"service_gate needs the Reach, in {p.area()}")
    if p.inv("foreman_key") < 1:
        p.problem("key", "the Foreman's Key is not in the key pouch", keys=p.st().get("keys"))
    # out of the Conservatory's north door, north road, Bellhouse road, down the stair
    if not p.nav((72.0, 0.0, -72.0), tol=1.6):
        raise StepFailed("could not reach the Bellhouse forecourt")
    p.shot("bellhouse_forecourt")
    if not p.nav((72.0, 0.0, -83.3), tol=0.8, final_tol=0.6):
        raise StepFailed("could not walk down the Bellhouse stair")
    gate = (72.0, 0.0, -84.6)
    if not p.flag("ch2_service_gate_open"):
        ok = p.interact_with(gate, ["Unlock the gate", "Unlock the service gate"],
                             check=lambda: p.flag("ch2_service_gate_open"), stop=1.0)
        if not ok:
            raise StepFailed(f"service gate did not open: prompt={p.prompt()}")
        time.sleep(2.5)
    if p.inv("foreman_key") < 1:
        p.problem("key", "the Foreman's Key left the pouch after opening the service gate")
    p.shot("service_gate_open")
    down = (72.0, 0.0, -87.2)
    ok = p.interact_with(down, ["Go down to the service landing", "go down"], check=lambda: p.mode() != "playing" or p.area() == WORKS,
                         stop=1.0, tries=6)
    if not ok:
        raise StepFailed(f"no way down: prompt={p.prompt()} pos={p.pos()}")
    if not p.wait_area(WORKS, 60):
        raise StepFailed("never arrived in the Hushed Works")
    p.shot("service_landing")
    return p.flag("ch2_service_gate_open")


def step_true_signal(p: S4):
    if p.flag("ch2_true_signal") and p.area() != WORKS:
        return True
    if p.area() != WORKS:
        raise StepFailed(f"true_signal needs the Works, in {p.area()}")
    if not p.flag("cp_lit_hw_landing") and dist2(xz(p.pos()), (-72.5, 0.8)) < 12:
        p.rest_lantern((-70.2, -6.0, -4.6), stand=(-70.6, -6.0, -2.8))
    if p.flag("ch2_true_signal"):
        return True
    p.lantern(True)
    if not p.nav((-47.0, -7.0, 0.0)):
        raise StepFailed("could not reach the Tool Lockers")
    p.fight_smart(timeout=150.0, radius=16.0)
    if not p.flag("hw_lockers_cleared"):
        p.problem("lockers", "the Hollow Drudge fight did not set hw_lockers_cleared",
                  enemies=[(e.get("name"), e.get("state"), e.get("hp")) for e in p.live_enemies(30)])
    if not p.flag("cp_lit_hw_lockers"):
        p.rest_lantern((-54.0, -7.0, -3.8), stand=(-54.2, -7.0, -2.0))
    if not p.nav((1.5, -11.0, 0.0)):
        raise StepFailed("could not reach the rail junction")
    ok = p.wait_flag("ch2_true_signal", 5)
    p.shot("rail_junction")
    return ok


def step_refuge(p: S4):
    if p.area() != WORKS and p.flag("ch2_refuge_record") and p.flag("ch2_refuge_shortcut"):
        return True
    if not (p.flag("ch2_refuge_reached") and p.flag("ch2_refuge_record") and p.flag("ch2_refuge_shortcut")):
        if not p.nav((23.2, -18.0, -8.0)):
            raise StepFailed("could not reach the refuge")
        p.wait_flag("ch2_refuge_reached", 5)
        p.shot("pocket_conservatory")
    if not p.flag("ch2_refuge_record"):
        if not p.use(["Read the refuge record"], (20.6, -18.0, -5.6), (19.2, -18.0, -5.6),
                     check=lambda: p.flag("ch2_refuge_record"), stop=1.3):
            raise StepFailed("could not read the refuge record")
        time.sleep(2.0)
    if not p.flag("ch2_refuge_shortcut"):
        if not p.use(["Turn the wheel"], (24.6, -18.0, -10.6), (24.6, -18.0, -12.2),
                     check=lambda: p.flag("ch2_refuge_shortcut"), stop=1.2):
            raise StepFailed("could not open the drainage stair")
        time.sleep(1.5)
    if not p.flag("cp_lit_hw_refuge"):
        p.rest_lantern((25.4, -18.0, -5.2), stand=(25.4, -18.0, -3.8))
    p.shot("refuge_done")
    done = p.ch2_done()
    return "ch2_refuge" in done and "ch2_miners" in done or p.wait(
        lambda s: {"ch2_refuge", "ch2_miners"} <= set((s.get("chapter2") or {}).get("done", [])), 5) is not None


def step_line_water(p: S4):
    if p.flag("ch2_line_water"):
        return True
    p.nav((28.75, -20.0, -21.0))
    p.use(["Read the sluice plaque"], (26.3, -20.0, -23.6), (25.4, -20.0, -22.2), stop=1.2, tries=2)
    va, vb = (20.4, -20.0, -38.9), (36.3, -20.0, -32.9)
    for _round in range(4):
        if p.flag("ch2_line_water"):
            break
        # valve A must send the water to the middle channel, valve B to the ward basin
        p.nav((21.6, -20.0, -36.9), final_tol=0.6)
        p.approach(va, stop=1.3)
        t = p.prompt_text().lower()
        if "upper valve" not in t:
            p.interact_with(va, ["upper valve"], check=lambda: True, tries=3, stop=1.2)
            t = p.prompt_text().lower()
        if "upper valve" in t and "middle channel" not in t:
            p.bot.tap("E")
            time.sleep(1.2)
        if p.flag("ch2_line_water"):
            break
        p.nav((34.9, -20.0, -33.4), final_tol=0.6)
        p.approach(vb, stop=1.3)
        t = p.prompt_text().lower()
        if "lower valve" not in t:
            p.interact_with(vb, ["lower valve"], check=lambda: True, tries=3, stop=1.2)
            t = p.prompt_text().lower()
        if "lower valve" in t and "ward basin" not in t:
            p.bot.tap("E")
            time.sleep(1.2)
        p.wait_flag("ch2_line_water", 2)
    p.shot("sluice")
    return p.flag("ch2_line_water")


BELL_POSTS = {"moon": (6.5, -16.0, 29.5), "leaf": (17.5, -16.0, 29.5), "flame": (6.5, -16.0, 37.5), "key": (17.5, -16.0, 37.5)}


def _stand_for_post(post, centre=(12.0, 33.5), k: float = 1.7):
    dx, dz = centre[0] - post[0], centre[1] - post[2]
    L = math.hypot(dx, dz)
    return (post[0] + dx / L * k, post[1], post[2] + dz / L * k)


def step_line_bell(p: S4):
    if p.flag("ch2_line_bell"):
        return True
    p.nav((12.0, -16.0, 26.5))
    p.fight_smart(timeout=90.0, radius=12.0)
    # read the bellmaker's plaque: the order is in its text
    t0 = p.game_t()
    p.use(["Read the bellmaker's plaque"], (12.0, -16.0, 26.3), (12.0, -16.0, 24.9), stop=1.2, tries=3)
    time.sleep(1.0)
    order = []
    for txt in p.recent_text(t0 - 1, kinds=("say",)):
        m = re.search(r"the (\w+), the (\w+), the (\w+), the (\w+)", txt)
        if m:
            order = [w.lower() for w in m.groups()]
    if not order:
        p.problem("bells", "could not read the bell order from the plaque text; using the plaque glyph order from layout data")
        order = ["leaf", "moon", "key", "flame"]
    p.log(f"bell order: {order}")
    for attempt in range(3):
        for sym in order:
            p.fight_smart(timeout=60.0, radius=7.0)
            post = BELL_POSTS[sym]
            stand = _stand_for_post(post)
            p.goto((stand[0], stand[2]), tol=0.5, sprint=False)
            ok = p.interact_with(post, [f"Strike the {sym.capitalize()} bell"], check=lambda: True, stop=1.5, tries=4)
            if not ok:
                p.problem("bells", f"could not strike the {sym} bell", prompt=p.prompt())
            time.sleep(0.8)
        if p.wait_flag("ch2_line_bell", 3):
            break
    p.shot("bells")
    return p.flag("ch2_line_bell")


def step_line_light(p: S4):
    if p.flag("ch2_line_light"):
        return True
    p.nav((34.75, -20.0, 23.5))
    p.use(["Read the plaque"], (36.6, -20.0, 22.4), (37.8, -20.0, 21.4), stop=1.2, tries=2)
    want = {"first": "east", "second": "south"}
    spots = {"first": ((32.2, -20.0, 26.2), (30.5, -20.0, 28.0)), "second": ((34.6, -20.0, 26.4), (36.0, -20.0, 28.0))}
    for _round in range(3):
        for which in ("first", "second"):
            stand, mirror = spots[which]
            p.nav(stand, final_tol=0.5)
            for _k in range(5):
                if p.flag("ch2_line_light"):
                    break
                p.approach(mirror, stop=1.3)
                t = p.prompt_text().lower()
                if f"{which} mirror" not in t:
                    p.interact_with(mirror, [f"Turn the {which} mirror"], check=lambda: True, tries=2, stop=1.2)
                    t = p.prompt_text().lower()
                if f"{which} mirror" not in t:
                    break
                if f"facing {want[which]}" in t:
                    break
                p.bot.tap("E")
                time.sleep(1.0)
        if p.wait_flag("ch2_line_light", 2):
            break
    p.shot("light_well")
    if p.flag("ch2_line_light") and not p.flag("hw_lightwell_alcove"):
        # the alcove shutter opens with the light line: the keepsake trunk
        p.use(["Open the keepsake trunk"], (32.0, -20.0, 35.4), (32.0, -20.0, 36.9), stop=1.2, tries=3)
    return p.flag("ch2_line_light")


def step_winch(p: S4):
    """Through the lower ward door into the Threaded Winch; burn the threads over the exit (lantern raised); light
    the crossing_gate checkpoint lantern (BEFORE the arena)."""
    if p.flag("ch2_crossing_cleared"):
        return True
    if not all(p.flag(f) for f in ("ch2_line_water", "ch2_line_bell", "ch2_line_light")):
        raise StepFailed("the three lines are not all restored")
    if p.pos()[0] < 40.0:
        if not p.nav((42.0, -18.0, 0.0)):
            raise StepFailed("the lower ward door did not let her through")
    p.shot("threaded_winch")
    p.lantern(True)
    exit_t = (61.6, -18.0, 0.0)
    if not p.flag("hw_thread_winch_exit_burned") and p.pos()[0] < 61.0:
        p.nav((59.6, -18.0, 0.0), final_tol=0.5)
        ok = p.interact_with(exit_t, ["Burn the threads", "Burn the veil"], check=lambda: p.flag("hw_thread_winch_exit_burned"),
                             stop=1.6, tries=4)
        if not ok:
            # the ordinary (lantern down) cut is the taught fallback: they grow back, so go straight through
            p.problem("winch", f"could not burn the exit threads, prompt={p.prompt()}")
            p.lantern(False)
            p.interact_with(exit_t, ["Cut the threads", "Part the pale veil"], check=lambda: True, stop=1.6, tries=3)
            p.lantern(True)
        time.sleep(0.8)
    if not p.nav((63.5, -18.0, 0.0)):
        raise StepFailed("could not pass the winch exit")
    p.rest_lantern((65.6, -18.0, -1.75), stand=(65.2, -18.0, -0.3))      # light it (first time) / rest (save)
    p.shot("crossing_gate")
    return p.flag("cp_lit_hw_crossing_gate")


BRAZIERS = [(78.0, -18.0, -4.05), (88.0, -18.0, 4.05), (98.0, -18.0, -4.05)]
CEILING_STATES = ("dormant", "intro", "cling", "cast", "recover", "pounce_tele", "release")


def _brazier_stand(bz):
    return (bz[0], bz[1], bz[2] * 0.55)          # 1.8 m in from the rail, facing it


def step_crossing(p: S4):
    """Weaver's Crossing Matron: light / stoke the line-brazier under the anchor she holds (exposure), strike her
    while exposed or stranded, step out of pounce rings, deal with threads and minions, eat when low."""
    if p.flag("ch2_crossing_cleared"):
        return True
    b = p.bot
    p.lantern(True)
    t0 = time.time()
    last_state = ""
    exposures_seen = 0
    deaths0 = sum(1 for m in p.all_msgs if m.get("text") == "player died")
    p.nav((74.5, -18.0, 0.0), fight=False)
    last_log = 0.0
    while time.time() - t0 < 600:
        if p.flag("ch2_crossing_cleared"):
            break
        s = p.st()
        if s.get("mode") != "playing":
            time.sleep(0.3)
            continue
        if s.get("area") != WORKS:
            raise StepFailed(f"left the Works during the crossing ({s.get('area')})")
        me = p.pos()
        boss = next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "phase" in e), None)
        if boss is None:
            boss = next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "matron" in str(e.get("name", "")).lower()), None)
        if me[0] < 72.5 or boss is None:
            # after a fall / respawn at crossing_gate, or before the fight starts: walk onto the bridge
            p.nav((75.0, -18.0, 0.0), fight=False)
            time.sleep(0.5)
            continue
        st = str(boss.get("state", ""))
        if st != last_state:
            p.log(f"  matron state {last_state} -> {st} phase={boss.get('phase')} hp={boss.get('hp')} vuln={boss.get('vuln')} at {boss.get('pos')} me={me} hp={p.hp()}")
            last_state = st
        if time.time() - last_log > 10:
            last_log = time.time()
            p.log(f"  crossing: t={time.time() - t0:.0f}s boss {st} hp={boss.get('hp')} phase={boss.get('phase')} me hp={p.hp()}")
        minions = p.live_enemies(14.0, lambda e: "phase" not in e and e.get("kind") not in ("thread", "sac", "trip")
                                 and "matron" not in str(e.get("name", "")).lower())
        if st in ("exposed", "stranded") or boss.get("vuln"):
            bp = boss["pos"]
            d = dist2(xz(me), xz(bp))
            p.face(bp, tol=10)
            if d > 2.0:
                b.down("SHIFT")
                b.hold("W", min(0.5, (d - 1.5) / 6.0 + 0.1))
                b.up("SHIFT")
            else:
                b.tap("LMB", 0.06)
                time.sleep(0.32)
            continue
        if st == "pounce_tele" or st == "drop":
            near_bz = min(dist2(xz(me), xz(bz)) for bz in BRAZIERS)
            if near_bz > 1.9 and st == "pounce_tele":
                # sprint along the bridge out of the ring (its centre is where she was when the ring appeared)
                dirx = 1.0 if me[0] < 88.0 else -1.0
                p.face((me[0] + dirx * 10, me[1], me[2] * 0.5), tol=12)
                b.down("SHIFT")
                b.hold("W", 0.75)
                b.up("SHIFT")
                p.wait(lambda s2: not any(e.get("g") == "enemy" and "phase" in e and e.get("state") == "pounce_tele"
                                          for e in s2.get("nearby", [])), 2.5)
            else:
                time.sleep(0.15)
            continue
        if minions:
            p.fight_smart(timeout=25.0, radius=10.0, pred=lambda e: "phase" not in e and e.get("kind") not in ("thread", "sac", "trip"))
            continue
        if p.hp() < 45 and st not in ("pounce_tele", "drop", "cast"):
            p.eat_best()
            continue
        if st in ("cling", "cast", "recover", "intro", "release", "dormant", "climb", "rebound", "scorch_fall"):
            if st in ("climb", "scorch_fall", "rebound"):
                time.sleep(0.2)
                continue
            bp = boss["pos"]
            line = min(range(3), key=lambda i: abs(BRAZIERS[i][0] - bp[0]) + abs(BRAZIERS[i][2] - bp[2]) * 0.3)
            bz = BRAZIERS[line]
            stand = _brazier_stand(bz)
            if dist2(xz(me), xz(stand)) > 0.9:
                # along the centre line first (threads pen the brazier's lane from the rail to |z| 0.4)
                if abs(me[0] - bz[0]) > 1.5:
                    p.goto((bz[0], 0.0), tol=0.8, sprint=True, timeout=8)
                p.goto((stand[0], stand[2]), tol=0.6, sprint=False, timeout=5)
                if dist2(xz(p.pos()), xz(stand)) > 1.2:
                    th = p.find_text(["Burn the threads", "Cut the threads", "Burn the veil", "Part the pale veil"], maxd=3.5)
                    if th:
                        p.log(f"  clearing a thread at {th.get('pos')}")
                        p.interact_with(th, ["Burn the", "Cut the", "Part the"], check=lambda: True, stop=1.2, tries=2)
                continue
            p.face(bz, tol=5)
            t = p.prompt_text().lower()
            if ("light the brazier" in t or "stoke the brazier" in t) and p.prompt().get("enabled", True):
                p.log(f"  kindling line {line} brazier (boss {st})")
                b.tap("E")
                # stay close while it kindles (1.5 s; stoke 1 s)
                p.wait(lambda s2: "kindling" not in str((s2.get("player", {}).get("prompt") or {}).get("text", "")).lower()
                       and "stoking" not in str((s2.get("player", {}).get("prompt") or {}).get("text", "")).lower(), 2.5)
                time.sleep(0.2)
            elif "gathering heat" in t or "kindling" in t or "stoking" in t or "smouldering" in t:
                time.sleep(0.3)
            else:
                p.face(bz, tol=3)
                b.hold("W", 0.1)
                time.sleep(0.2)
            continue
        time.sleep(0.15)
    deaths = sum(1 for m in p.all_msgs if m.get("text") == "player died") - deaths0
    if deaths:
        p.problem("crossing", f"Krystal fell {deaths} time(s) during the Matron fight (retried from crossing_gate)")
    ok = p.flag("ch2_crossing_cleared")
    time.sleep(3.0)
    p.shot("crossing_cleared" if ok else "crossing_failed")
    return ok and p.wait(lambda s: "ch2_weaver_crossing" in (s.get("chapter2") or {}).get("done", []), 8) is not None


def step_wrong_landing(p: S4):
    """The Wrong Landing: ride the FALSE lift (its lamp lights nothing) -> a short detour into the service siding,
    then walk back into the landing (recoverable, no damage). With --real-lift (instead) or --loop-b (as well) it
    also rides the REAL lift (loop B up to the Pocket Conservatory) and the winch cage by the ward door back down."""
    if p.flag("ch2_false_home_revealed") or p.flag("ch2_choir_defeated"):
        return True
    if not p.flag("ch2_crossing_cleared"):
        raise StepFailed("the crossing is not cleared")
    if not p.nav((120.0, -22.0, 0.0)):
        raise StepFailed("could not reach the Wrong Landing (exit veil / stair)")
    p.shot("wrong_landing")
    real_only = bool(getattr(p, "real_lift", False))
    loop_b = bool(getattr(p, "loop_b", False)) or real_only
    if not real_only and not p.flag("hw_false_lift_ridden"):
        p.nav((133.0, -22.0, -8.2), final_tol=0.5)
        ok = p.interact_with((133.0, -22.0, -12.3), ["Ride the lift up"], check=lambda: p.mode() != "playing"
                             or p.flag("hw_false_lift_ridden"), stop=2.2)
        if not ok:
            raise StepFailed(f"could not ride the false lift: prompt={p.prompt()}")
        p.wait(lambda s: s.get("mode") == "playing" and dist2(xz(s.get("player", {}).get("pos", [0, 0, 0])), (146.0, -7.5)) < 4.0, 20)
        time.sleep(1.0)
        p.shot("false_lift_siding")
        if dist2(xz(p.pos()), (146.0, -7.5)) > 4.0:
            p.problem("lift", f"the false lift did not leave her in the siding: {p.pos()}")
        if not p.nav((129.0, -22.0, 8.0)):
            raise StepFailed("could not walk back from the siding")
    if loop_b and not p.flag("hw_loop_b_lift"):
        p.nav((123.0, -22.0, -8.2), final_tol=0.5)
        ok = p.interact_with((123.0, -22.0, -12.3), ["Ride the lift up"], check=lambda: p.mode() != "playing"
                             or p.flag("hw_loop_b_lift"), stop=2.2)
        if not ok:
            raise StepFailed(f"could not ride the real lift: prompt={p.prompt()}")
        p.wait(lambda s: s.get("mode") == "playing" and s.get("zone") == "hw_refuge", 20)
        time.sleep(1.0)
        p.shot("real_lift_refuge")
        if p.zone() != "hw_refuge":
            p.problem("lift", f"the real lift did not arrive at the refuge (zone {p.zone()}, pos {p.pos()})")
        # the winch cage by the ward door, back down to the Wrong Landing
        p.nav((58.0, -18.0, -5.4), final_tol=0.5)
        p.interact_with((58.0, -18.0, -7.2), ["Ride the winch cage down"], check=lambda: p.mode() != "playing" or bool(p.ui()),
                        stop=1.8)
        if p.ui():
            p.handle_dialog() if not p.find_button("Down to the Wrong Landing") else p.click_button("Down to the Wrong Landing", timeout=4)
        p.wait(lambda s: s.get("mode") == "playing" and s.get("zone") == "hw_wrong_landing", 20)
        time.sleep(1.0)
        if p.zone() != "hw_wrong_landing":
            raise StepFailed(f"the winch cage did not bring her back down (zone {p.zone()}, pos {p.pos()})")
    return p.nav((129.0, -22.0, 12.0))


def step_false_home(p: S4):
    if p.flag("ch2_false_home_revealed"):
        return True
    p.nav((129.0, -22.0, 20.0))
    # the porch's tells, as a player would check them: knock, look at the lamp (only explain, harmless)
    p.use(["Knock on the door"], None, (122.0, -22.0, 34.0), stop=1.8, tries=2)
    # the porch lamp hangs 1.2 m east of the door: look at it from the north-east so the door's prompt is not closer
    p.use(["Look at the porch lamp"], (124.6, -22.0, 31.0), (123.2, -22.0, 33.0), stop=1.9, tries=3, pitch=15.0)
    p.shot("borrowed_porch")
    ok = p.use(["Hold your lantern to the anchored flame", "This flame lights the ground"], (136.0, -22.0, 29.6),
               (137.6, -22.0, 30.3), check=lambda: p.flag("ch2_false_home_revealed"), stop=1.4)
    if not ok:
        raise StepFailed(f"could not reveal the true stair: prompt={p.prompt()}")
    time.sleep(2.0)
    p.shot("true_stair")
    return p.wait(lambda s: "ch2_false_home" in (s.get("chapter2") or {}).get("done", []), 6) is not None


def step_bell_throat(p: S4):
    if p.flag("ch2_choir_defeated"):
        return True
    if not p.nav((154.0, -28.0, 33.5)):
        raise StepFailed("could not reach the Bell Throat (true stair)")
    p.shot("bell_throat")
    p.rest_lantern((153.0, -28.0, 30.2), stand=(154.4, -28.0, 30.6))
    if not p.flag("hw_throat_supplies"):
        p.use(["Open the miners' supply crate"], (159.4, -28.0, 36.5), (160.7, -28.0, 36.5), stop=1.3, tries=3)
    p.use(["Read the miners' note"], (159.6, -28.0, 29.2), (160.8, -28.0, 28.4), stop=1.3, tries=3)
    p.use(["Read the bellmakers' order"], (160.4, -28.0, 31.75), (161.9, -28.0, 31.75), stop=1.4, tries=2)
    return p.flag("cp_lit_hw_bell_throat")


ANCHORS = [(150.94, -32.0, 61.5), (163.06, -32.0, 61.5), (157.0, -32.0, 72.0)]
RESONATORS = {"west": (147.7, -32.0, 65.0), "east": (166.3, -32.0, 65.0)}
SYMBOLS = ["leaf", "moon", "key", "flame"]          # the plates' order on each frame (data bell_symbols())
VC = Nav.VAULT_C


def _out(pt, k: float):
    """The point `k` metres further out from the vault centre than `pt` (negative = inward)."""
    dx, dz = pt[0] - VC[0], pt[2] - VC[2]
    L = math.hypot(dx, dz) or 1.0
    return (pt[0] + dx / L * k, pt[1], pt[2] + dz / L * k)


def _plate_pos(res: str, idx: int, n: int = 4):
    """Plate centres: the frames face the centre; plate i sits (i - 1.5) * 1.25 m along the frame (resonator.gd)."""
    o = (idx - (n - 1) * 0.5) * 1.25
    x, y, z = RESONATORS[res]
    return (x, y, z - o) if res == "west" else (x, y, z + o)


def _plate_stand(res: str, idx: int):
    x, y, z = _plate_pos(res, idx)
    return (x + 1.3, y, z) if res == "west" else (x - 1.3, y, z)


def _behind_frame(res: str, me):
    """A spot past the end of the resonator frame at radius >= 10.4 (the rings fade at 9.7): the safe perimeter."""
    x, y, z = RESONATORS[res]
    zz = z - 3.6 if me[2] < z else z + 3.6
    return _out((x, y, zz), 10.9 - math.hypot(x - VC[0], zz - VC[2]))


def _perimeter_point(me):
    dx, dz = me[0] - VC[0], me[2] - VC[2]
    L = math.hypot(dx, dz) or 1.0
    return (VC[0] + dx / L * 11.3, VC[1], VC[2] + dz / L * 11.3)


class ChoirBot:
    """The Borrowed Choir (MP 13.3), one decision per phase:
    A  raise the lantern at an anchor (from outside it), then point out a form. The bot CANNOT see which form's
       plate is lit (a light, not in telemetry): it guesses, and a wrong pick brings the marked sweep, which it
       leaves toward the perimeter walk.
    B  strike both resonators' plates in the taught order (read from the hint), 12 s per sequence; start a sequence
       right after a ring volley, keep striking through a volley once started, step out of strike zones, go past
       the frame's end (radius >= 10.4) to wait out volleys between sequences; fight the wisps near the frames.
    C  raise the lantern at an anchor; a wrong hook says so in a caption ("burns alone"), a right one answers
       ("answers your lantern"); wait out the hush in the true flame's lit sector or on the perimeter walk.
    Every exposure (vuln): strike."""

    def __init__(self, p):
        self.p = p
        self.b = p.bot
        self.order = list(SYMBOLS)
        self.wrong_anchors: set = set()
        self.last_flame_anchor = -1
        self.confirmed_anchor = -1
        self.cur_anchor = -1
        self.res_done = {"west": False, "east": False}
        self.res_prog = {"west": 0, "east": 0}
        self.seq_t0 = {"west": 0.0, "east": 0.0}
        self.picks: list = []
        self.n_seen = len(p.all_msgs)
        self.log = p.log

    def read_msgs(self):
        p = self.p
        new = p.all_msgs[self.n_seen:]
        self.n_seen = len(p.all_msgs)
        for m in new:
            txt = str(m.get("text", ""))
            if "choir_resonators" in txt:
                mm = re.search(r"\(([A-Za-z]+(?:, [A-Za-z]+)+)\)", txt)
                if mm:
                    self.order = [w.strip().lower() for w in mm.group(1).split(",")]
                    self.log(f"  resonator order from the hint: {self.order}")
            if "burns alone on this hook" in txt and self.cur_anchor >= 0:
                self.wrong_anchors.add(self.cur_anchor)
            if ("answers your lantern" in txt or "swings toward your lantern" in txt or "settles on the hook you lit" in txt) \
                    and self.cur_anchor >= 0:
                self.confirmed_anchor = self.cur_anchor
            if "warm, cozy lights bloom" in txt:
                if self.confirmed_anchor >= 0:
                    self.last_flame_anchor = self.confirmed_anchor
                self.confirmed_anchor = -1
                self.wrong_anchors = set()
            if "drawn down, exposed" in txt and self.cur_anchor >= 0:
                self.last_flame_anchor = self.cur_anchor
                self.confirmed_anchor = -1
                self.wrong_anchors = set()
            if "start the sequence again" in txt or "flat, wrong note" in txt:
                for r in ("west", "east"):
                    if not self.res_done[r]:
                        self.res_prog[r] = 0
            if "gathers its borrowed bells again" in txt:
                self.res_done = {"west": False, "east": False}
                self.res_prog = {"west": 0, "east": 0}

    # --- primitives ---------------------------------------------------------------------------------
    def strike_boss(self, boss):
        p, b = self.p, self.b
        bp = boss["pos"]
        d = dist2(xz(p.pos()), xz(bp))
        p.face(bp, tol=10)
        if d > 2.0:
            b.down("SHIFT")
            b.hold("W", min(0.5, (d - 1.5) / 6.0 + 0.1))
            b.up("SHIFT")
        else:
            b.tap("LMB", 0.06)
            time.sleep(0.3)

    def raise_at(self, k: int) -> bool:
        p = self.p
        a = ANCHORS[k]
        stand = _out(a, 1.25)
        self.cur_anchor = k
        if dist2(xz(p.pos()), xz(stand)) > 0.5:
            p.goto((stand[0], stand[2]), tol=0.4, sprint=True, timeout=6)
        p.face(a, tol=4, body=True)
        for _ in range(3):
            t = p.prompt_text()
            if "Raise your lantern at the anchor" in t and p.prompt().get("enabled", True):
                n0 = len(p.all_msgs)
                p.bot.tap("E")
                return p.wait(lambda s: "Your lantern burns on the anchor" in str((s.get("player", {}).get("prompt") or {}).get("text", ""))
                              or any("flares on the anchor" in str(m.get("text", "")) for m in p.all_msgs[n0:]), 1.5) is not None
            if "Your lantern burns on the anchor" in t:
                return True
            p.face(a, tol=3, body=True)
            time.sleep(0.15)
        self.log(f"  raise_at {k}: prompt {p.prompt()} me {p.pos()}")
        return False

    def around_frame(self, res: str, dest):
        """The frame (5.4 m wide, solid) stands between the perimeter and its plates: when the straight line from here
        to `dest` crosses it, walk round its nearer end first."""
        p = self.p
        me = p.pos()
        fx, _, fz = RESONATORS[res]
        if (me[0] - fx) * (dest[0] - fx) >= 0:
            return
        t = (fx - me[0]) / (dest[0] - me[0])
        zc = me[2] + (dest[2] - me[2]) * t
        if abs(zc - fz) > 3.0:
            return
        side = -1.0 if me[2] < fz else 1.0
        inner = 0.9 if res == "west" else -0.9
        outer = -0.9 if res == "west" else 0.9
        end_out = (fx + outer, fz + side * 3.5)
        end_in = (fx + inner, fz + side * 3.5)
        if (me[0] - fx) * outer > 0:        # behind the frame: its end, then round to the front
            p.goto(end_out, tol=0.6, sprint=True, timeout=4)
            p.goto(end_in, tol=0.6, sprint=True, timeout=4)
        else:
            p.goto(end_in, tol=0.6, sprint=True, timeout=4)
            p.goto(end_out, tol=0.6, sprint=True, timeout=4)

    def strike_plate(self, res: str, idx: int) -> str:
        """Strikes plate `idx` of resonator `res`: "ok" | "wrong" | "done" | "miss"."""
        p, b = self.p, self.b
        sym = SYMBOLS[idx]
        stand = _plate_stand(res, idx)
        plate = _plate_pos(res, idx)
        self.around_frame(res, stand)
        if dist2(xz(p.pos()), xz(stand)) > 0.35:
            p.goto((stand[0], stand[2]), tol=0.3, sprint=dist2(xz(p.pos()), xz(stand)) > 2.5, timeout=5)
        aim = (plate[0], plate[1] + 1.75, plate[2])
        for k in range(5):
            p.face(aim, tol=3, body=(k == 0))
            t = p.prompt_text()
            m = re.match(r"Strike the (\w+) plate", t)
            if m and m.group(1).lower() == sym:
                n0 = len(p.all_msgs)
                b.tap("E")
                p.wait(lambda s: any(re.search(r"\(\d of \d\)|wrong note|rings true", str(mm.get("text", "")))
                                     for mm in p.all_msgs[n0:]), 1.5)
                txts = " | ".join(str(mm.get("text", "")) for mm in p.all_msgs[n0:])
                if "rings true" in txts:
                    return "done"
                if "wrong note" in txts:
                    return "wrong"
                if re.search(r"\(\d of \d\)", txts):
                    return "ok"
                return "miss"
            if m and m.group(1).lower() in SYMBOLS:
                j = SYMBOLS.index(m.group(1).lower())
                b.hold("D" if j < idx else "A", 0.1)          # facing the frame, a higher plate index is to the right
            else:
                b.hold("W", 0.07)
            time.sleep(0.12)
        self.log(f"  plate {res}/{sym}: no prompt (prompt {p.prompt_text()!r}, me {p.pos()})")
        return "miss"

    # --- the fight ------------------------------------------------------------------------------------
    def run(self, timeout: float = 900.0) -> bool:
        p = self.p
        t0 = time.time()
        last_state = ""
        last_log = 0.0
        import random
        rng = random.Random(4)
        while time.time() - t0 < timeout:
            if p.flag("ch2_choir_defeated"):
                return True
            s = p.st()
            if s.get("mode") != "playing":
                time.sleep(0.3)
                continue
            if s.get("ui_stack"):
                p.handle_dialog()
                continue
            self.read_msgs()
            me = p.pos()
            if me[2] < 50.0 and me[1] > -31.0:
                self.log("  back to the vault after a respawn")
                p.nav((157.0, -32.0, 55.0), fight=False)
                continue
            boss = next((e for e in s.get("nearby", []) if e.get("g") == "enemy" and "phase" in e), None)
            if boss is None:
                if dist2(xz(me), xz(VC)) > 9.5:
                    p.goto((157.0, 57.0), tol=1.0, sprint=True, timeout=10)
                time.sleep(0.3)
                continue
            st = str(boss.get("state", ""))
            ph = int(boss.get("phase", 1) or 1)
            if st != last_state:
                self.log(f"  choir state {last_state} -> {st} phase={ph} hp={boss.get('hp')} vuln={boss.get('vuln')} me={me} hp={p.hp()}")
                last_state = st
            if time.time() - last_log > 10:
                last_log = time.time()
                self.log(f"  choir: t={time.time() - t0:.0f}s {st} phase {ph} hp={boss.get('hp')} me hp={p.hp()} res={self.res_prog} done={self.res_done}")
            if boss.get("vuln") or st.endswith("_exposed"):
                self.strike_boss(boss)
                continue
            if ph == 1:
                self.phase_a(s, st, me, rng)
            elif ph == 2:
                self.phase_b(s, st, me)
            else:
                self.phase_c(s, st, me)
        return p.flag("ch2_choir_defeated")

    def to_perimeter(self, me):
        if dist2(xz(me), xz(VC)) < 10.8:
            pp = _perimeter_point(me)
            self.p.goto((pp[0], pp[2]), tol=0.6, sprint=True, timeout=3.0)
        else:
            time.sleep(0.15)

    def phase_a(self, s, st, me, rng):
        p = self.p
        if st in ("a_sweep_tele", "a_sweep"):
            self.to_perimeter(me)
            return
        if p.hp() < 45 and p.eat_best():
            return
        if st not in ("a_gather", "a_wait", "intro", "dormant"):
            time.sleep(0.15)
            return
        raised = any("Your lantern burns on the anchor" in str(e.get("text", "")) for e in s.get("nearby", []))
        if not raised:
            k = min(range(3), key=lambda i: dist2(xz(me), xz(ANCHORS[i])))
            self.raise_at(k)
            return
        if st != "a_wait":
            time.sleep(0.15)
            return
        forms = [e for e in s.get("nearby", []) if "Point out this form" in str(e.get("text", ""))]
        if not forms:
            time.sleep(0.15)
            return
        f = rng.choice(forms)
        self.log(f"  pointing out the form at {f.get('pos')} (a guess among {len(forms)}: which plate is lit is not in telemetry)")
        n0 = len(p.all_msgs)
        stand = _out(f["pos"], 1.3)
        p.goto((stand[0], stand[2]), tol=0.5, sprint=True, timeout=5)
        p.face(f["pos"], tol=4, body=True)
        ok = False
        for _ in range(3):
            if "Point out this form" in p.prompt_text():
                p.bot.tap("E")
                ok = True
                break
            p.face(f["pos"], tol=3, body=True)
            time.sleep(0.15)
        p.wait(lambda s2: any("mask slips" in str(m.get("text", "")) or "false form bursts" in str(m.get("text", ""))
                              for m in p.all_msgs[n0:]), 1.5)
        txt = " | ".join(str(m.get("text", "")) for m in p.all_msgs[n0:])
        self.picks.append({"t": round(p.game_t(), 1), "pressed": ok, "result": "correct" if "mask slips" in txt else
                           ("wrong" if "false form bursts" in txt else "none")})

    def phase_b(self, s, st, me):
        p = self.p
        wisps = p.live_enemies(6.0, lambda e: "phase" not in e and "wisp" in str(e.get("name", "")).lower())
        todo = [r for r in ("west", "east") if not self.res_done[r]]
        if not todo:
            time.sleep(0.15)
            return
        r = min(todo, key=lambda k: dist2(xz(me), xz(RESONATORS[k])))
        i = self.res_prog[r]
        in_seq = i > 0 and time.time() - self.seq_t0[r] < 11.0
        if st == "b_strike_tele":
            # the marked zones fall around her: step along the frame, past the zones
            pr = _plate_stand(r, 0 if i >= 2 else 3)
            p.goto((pr[0], pr[2]), tol=0.6, sprint=True, timeout=2.0)
            return
        if st in ("b_ring_tele", "b_rings") and not in_seq:
            bf = _behind_frame(r, me)
            if dist2(xz(me), xz(VC)) < 10.3:
                self.around_frame(r, bf)
                p.goto((bf[0], bf[2]), tol=0.7, sprint=True, timeout=4.0)
            else:
                time.sleep(0.15)
            return
        if wisps and not in_seq:
            p.fight_smart(timeout=15.0, radius=6.0, pred=lambda e: "phase" not in e and "wisp" in str(e.get("name", "")).lower())
            return
        if p.hp() < 40 and p.eat_best():
            return
        if i > 0 and not in_seq:
            self.res_prog[r] = 0        # the 12 s window ran out: start again
            i = 0
        if i >= len(self.order):
            self.res_done[r] = True
            return
        sym = self.order[i]
        idx = SYMBOLS.index(sym) if sym in SYMBOLS else i
        res = self.strike_plate(r, idx)
        if res in ("ok", "done"):
            if i == 0:
                self.seq_t0[r] = time.time()
            self.res_prog[r] = i + 1
            if res == "done" or self.res_prog[r] >= len(self.order):
                self.res_done[r] = True
                self.log(f"  resonator {r} awake")
        elif res == "wrong":
            self.res_prog[r] = 0

    def phase_c(self, s, st, me):
        p = self.p
        if st in ("c_hush_tele", "c_hush"):
            if self.confirmed_anchor >= 0 and dist2(xz(me), xz(ANCHORS[self.confirmed_anchor])) < 2.2:
                time.sleep(0.15)       # in the true flame's lit sector
            else:
                self.to_perimeter(me)
            return
        if p.hp() < 45 and p.eat_best():
            return
        if st not in ("c_open", "c_settle"):
            time.sleep(0.15)
            return
        if self.confirmed_anchor >= 0:
            a = ANCHORS[self.confirmed_anchor]
            stand = _out(a, 1.25)
            if dist2(xz(me), xz(stand)) > 1.0:
                p.goto((stand[0], stand[2]), tol=0.6, sprint=True, timeout=5)
            if "Raise your lantern at the anchor" in p.prompt_text():
                self.raise_at(self.confirmed_anchor)
            time.sleep(0.2)
            return
        cands = [k for k in range(3) if k not in self.wrong_anchors and k != self.last_flame_anchor] or \
                [k for k in range(3) if k not in self.wrong_anchors] or [0, 1, 2]
        k = min(cands, key=lambda i: dist2(xz(me), xz(ANCHORS[i])))
        n0 = len(p.all_msgs)
        if not self.raise_at(k):
            if "Your lantern burns on the anchor" in p.prompt_text():
                self.wrong_anchors.add(k)
            return
        p.wait(lambda s2: any(w in str(m.get("text", "")) for m in p.all_msgs[n0:]
                              for w in ("burns alone", "answers your lantern", "swings toward", "drawn down, exposed")), 1.5)
        self.read_msgs()


def step_choir(p):
    """The Borrowed Choir: see ChoirBot."""
    if p.flag("ch2_choir_defeated"):
        return True
    p.lantern(True)
    if not p.nav((157.0, -32.0, 53.7)):
        raise StepFailed("could not reach the vault stair")
    p.shot("choir_vault_door")
    deaths0 = sum(1 for m in p.all_msgs if m.get("text") == "player died")
    cb = ChoirBot(p)
    ok = cb.run(900.0)
    deaths = sum(1 for m in p.all_msgs if m.get("text") == "player died") - deaths0
    if deaths:
        p.problem("choir", f"Krystal fell {deaths} time(s) during the Choir fight")
    p.log(f"  form picks: {cb.picks}")
    p.choir_picks = cb.picks
    time.sleep(5.0)
    p.shot("choir_defeated" if ok else "choir_failed")
    return ok


def step_return_reach(p: S4):
    if p.area() in (REACH, SURFACE) and p.flag("ch2_returned_to_reach"):
        return True
    if p.area() == WORKS:
        if not p.nav((157.0, -32.0, 80.0), final_tol=0.6):
            raise StepFailed("could not reach the vault exit lift")
        ok = p.interact_with((157.0, -32.0, 82.6), ["Ride the bell-lift up"], check=lambda: p.mode() != "playing" or p.area() == REACH,
                             stop=1.8)
        if not ok:
            raise StepFailed(f"exit lift: prompt={p.prompt()}")
        if not p.wait_area(REACH, 60):
            raise StepFailed("the exit lift did not reach the Reach")
    p.shot("reach_after_choir")
    ok = p.wait_flag("ch2_returned_to_reach", 10)
    p.wait(lambda s: "ch2_routes_restored" in (s.get("chapter2") or {}).get("done", []), 8)
    return ok


def step_travel_home(p: S4):
    if p.area() == SURFACE or p.flag("ch2_homecoming"):
        return True
    if p.area() != REACH:
        raise StepFailed(f"travel_home from {p.area()}")
    # the nearest lit arch on foot (from the Bellhouse: the manor arch), then the Lantern Road home
    arches = {"manor": (10.0, 0.0, -50.0), "conservatory": (0.0, 0.0, 20.0), "commons": (0.0, 0.0, 78.0),
              "quarry": (62.0, 0.0, 38.0), "orchard": (-60.0, 0.0, 50.0)}
    lit = [a for a in arches if p.flag(f"ch2_arch_{a}")]
    if not lit:
        raise StepFailed("no lit arch")
    a = min(lit, key=lambda k: dist2(xz(p.pos()), xz(arches[k])))
    ap = arches[a]
    stand = {"manor": (10.9, 0.0, -52.8), "conservatory": (0.0, 0.0, 17.0)}.get(a, (ap[0], 0.0, ap[2] + 3.0))
    p.nav(stand, tol=1.6, final_tol=1.0)
    ok = p.interact_with(ap, ["Travel the Lantern Road"], check=lambda: bool(p.ui()), stop=1.8)
    if not ok:
        raise StepFailed(f"arch {a}: prompt={p.prompt()}")
    p.shot("lantern_road_list")
    if not p.click_button("The Haven", timeout=5):
        raise StepFailed("no Haven destination in the Lantern Road list")
    if not p.wait_area(SURFACE, 60):
        raise StepFailed("did not arrive home")
    p.shot("home_haven")
    return True


def _ward_stone(p: S4):
    e = p.nearest(lambda n: n.get("name") == "WardStone" or "ward stone" in str(n.get("text", "")).lower(), 60)
    return e


def step_homecoming(p: S4):
    if p.flag("ch2_homecoming"):
        return True
    e = _ward_stone(p)
    if not e:
        p.goto((0.0, 4.0), tol=3.0)
        e = _ward_stone(p)
    if not e:
        raise StepFailed("no Ward Stone nearby")
    ok = p.interact_with(e, [""], check=lambda: p.flag("ch2_homecoming") or bool(p.ui()), stop=2.2)
    if p.ui() and not p.flag("ch2_homecoming"):
        p.problem("homecoming", f"the Ward Stone opened a menu instead of the homecoming: {[b.get('text') for b in p.buttons()]}")
        p.close_panels()
    time.sleep(3.0)
    p.shot("homecoming")
    return p.wait(lambda s: "ch2_homecoming" in (s.get("chapter2") or {}).get("done", []), 8) is not None


def step_lanternwake(p: S4):
    if p.flag("chapter_two_complete"):
        return True
    e = _ward_stone(p)
    if not e:
        raise StepFailed("no Ward Stone nearby")
    if not p.interact_with(e, [""], check=lambda: bool(p.find_button("Celebrate")), stop=2.2):
        raise StepFailed(f"no Celebrate option: buttons {[b.get('text') for b in p.buttons()]}")
    p.shot("ward_stone_menu")
    if not p.click_button("Celebrate the Lanternwake", timeout=4):
        raise StepFailed("could not click Celebrate")
    if not p.wait_flag("chapter_two_complete", 10):
        raise StepFailed("chapter_two_complete was not set by the celebration")
    time.sleep(2.0)
    p.shot("celebration")
    p.bot.tap("ENTER")          # skip the celebration (skippable after 1.2 s)
    time.sleep(6.0)
    p.shot("ending_card")
    p.bot.tap("ENTER")          # skip the ending card / credits (skippable after 4 s)
    time.sleep(1.5)
    btn = None
    for _ in range(40):
        btn = p.find_button("Continue exploring")
        if btn:
            break
        time.sleep(0.5)
        if _ % 8 == 7:
            p.bot.tap("ENTER")
    p.shot("chapter_two_complete")
    if not btn:
        raise StepFailed(f"no 'Continue exploring' button (buttons {[b.get('text') for b in p.buttons()]}, mode {p.mode()})")
    p.click_button("Continue exploring", timeout=3)
    ok = p.wait(lambda s: s.get("mode") == "playing" and not s.get("ui_stack"), 20) is not None
    return ok and p.wait(lambda s: bool((s.get("chapter2") or {}).get("finished")), 8) is not None


def step_free_play(p: S4):
    """Free play in the SAME save: save from the pause menu; the Reach through the Ward Stone's Lantern Road; the
    refuge shortcut both ways (Reach hatch -> Pocket Conservatory -> drainage stair -> Reach); light the
    Conservatory arch; the Lantern Road home."""
    p.bot.hold("W", 0.8)
    n0 = p.saved_count()
    p.bot.tap("ESC")
    if not p.wait(lambda s: "pause" in (s.get("ui_stack") or []), 3.0):
        raise StepFailed("pause menu did not open")
    if not p.click_button("Save Game", timeout=4):
        p.close_panels()
        raise StepFailed("no Save Game button")
    saved = p.wait_saved(n0, 6)
    p.close_panels()
    if not saved:
        p.problem("save", "Save Game from the pause menu did not report a save in free play")
    # the Reach: through the Ward Stone's Lantern Road
    e = _ward_stone(p)
    if not e:
        raise StepFailed("no Ward Stone")
    if not p.interact_with(e, [""], check=lambda: bool(p.find_button("Travel the Lantern Road")) or bool(p.ui()), stop=2.2):
        raise StepFailed("the Ward Stone menu did not open")
    if not p.click_button("Travel the Lantern Road", timeout=4):
        raise StepFailed(f"no Lantern Road option: {[b.get('text') for b in p.buttons()]}")
    time.sleep(0.8)
    if not p.click_button("Lanternwake Commons", timeout=4):
        raise StepFailed(f"no Commons destination: {[b.get('text') for b in p.buttons()]}")
    if not p.wait_area(REACH, 60):
        raise StepFailed("did not arrive in the Reach")
    p.shot("free_play_reach")
    # down the refuge hatch beside the Conservatory, up the drainage stair again
    p.nav((21.8, 0.0, 3.2), tol=1.6, final_tol=0.8)
    ok = p.interact_with((24.0, 0.0, 2.0), ["Climb down to the refuge"], check=lambda: p.mode() != "playing" or p.area() == WORKS, stop=1.4)
    if not ok:
        raise StepFailed(f"refuge hatch: prompt={p.prompt()}")
    if not p.wait_area(WORKS, 60):
        raise StepFailed("the refuge hatch did not lead into the Works")
    p.shot("free_play_refuge")
    if p.zone() != "hw_refuge":
        p.problem("shortcut", f"the Reach hatch arrived outside the refuge: zone {p.zone()} pos {p.pos()}")
    p.nav((21.25, -18.0, -13.0), final_tol=0.6)
    ok = p.interact_with((21.25, -15.4, -16.9), ["Take the drainage stair up"], check=lambda: p.mode() != "playing" or p.area() == REACH,
                         stop=1.6, tries=6)
    if not ok:
        raise StepFailed(f"drainage stair: prompt={p.prompt()} pos={p.pos()}")
    if not p.wait_area(REACH, 60):
        raise StepFailed("the drainage stair did not lead back to the Reach")
    # the Conservatory's own Lantern Road arch (lit here if it was not yet), then home
    arch = (0.0, 0.0, 20.0)
    p.nav((0.0, 0.0, 17.0), tol=1.6, final_tol=0.8)
    if not p.flag("ch2_arch_conservatory"):
        if not p.interact_with(arch, ["Light the lantern arch"], check=lambda: p.flag("ch2_arch_conservatory"), stop=1.8):
            p.problem("arch", f"could not light the Conservatory arch: prompt={p.prompt()}")
        time.sleep(1.5)
    if not p.interact_with(arch, ["Travel the Lantern Road"], check=lambda: bool(p.ui()), stop=1.8):
        raise StepFailed(f"conservatory arch: prompt={p.prompt()}")
    if not p.click_button("The Haven", timeout=4):
        raise StepFailed("no Haven destination")
    if not p.wait_area(SURFACE, 60):
        raise StepFailed("did not get back home")
    p.shot("free_play_home")
    s = p.st()
    return bool((s.get("chapter2") or {}).get("finished")) and "chapter_two_complete" in s.get("flags", [])


STEPS = [("start", step_start), ("link_lanterns", step_link_lanterns), ("service_gate", step_service_gate),
         ("true_signal", step_true_signal), ("refuge", step_refuge), ("line_water", step_line_water),
         ("line_bell", step_line_bell), ("line_light", step_line_light), ("winch", step_winch),
         ("crossing", step_crossing), ("wrong_landing", step_wrong_landing), ("false_home", step_false_home),
         ("bell_throat", step_bell_throat), ("choir", step_choir), ("return_reach", step_return_reach),
         ("travel_home", step_travel_home), ("homecoming", step_homecoming), ("lanternwake", step_lanternwake),
         ("free_play", step_free_play)]


# ====================================================================================== runner
def run(bot_or_game, out_dir, steps=None, from_step: str = "", until: str = "", options: dict | None = None) -> dict:
    """Runs the S4 checkpoints. `bot_or_game`: a HeadlessGame (this module's launcher) or any object with `.bot`
    (an hhbot.Bot on the virtual-input transport), `.vin` (that transport), `.t_launch` and optionally `.save_dir`
    (checkpoint snapshots). options: {"loop_b": bool, "real_lift": bool}.
    Returns {checkpoints, timings, shots, problems, stopped_at, total_seconds, final, messages}."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    g = bot_or_game
    p = S4(g, out)
    for k, v in (options or {}).items():
        setattr(p, k, v)
    steps = steps or STEPS
    res = {"segment": "S4", "checkpoints": [], "timings": {}, "shots": p.shots, "problems": p.problems,
           "stopped_at": "", "started": time.strftime("%Y-%m-%d %H:%M:%S")}
    t_run = time.time()
    started = not from_step
    for name, fn in steps:
        if until and name == until:
            break
        if not started and name not in ("start",):
            if name == from_step:
                started = True
            else:
                continue
        t = time.time()
        p.log(f"=== STEP {name} (area {p.area()}, zone {p.zone()}, ch2 current {(p.st().get('chapter2') or {}).get('current')}) ===")
        ok = False
        err = ""
        try:
            ok = bool(fn(p))
        except StepFailed as ex:
            err = f"StepFailed: {ex}"
        except Exception as ex:  # noqa: BLE001
            import traceback
            err = f"EXCEPTION {type(ex).__name__}: {ex}"
            p.log(traceback.format_exc())
        dur = round(time.time() - t, 1)
        res["timings"][name] = dur
        s = p.st()
        row = {"step": name, "ok": ok, "seconds": dur, "area": s.get("area"), "zone": s.get("zone"),
               "ch2_current": (s.get("chapter2") or {}).get("current"), "hp": p.hp(), "error": err}
        res["checkpoints"].append(row)
        p.log(f"=== {name}: {'PASS' if ok else 'FAIL'} in {dur}s {err}")
        if not ok:
            res["stopped_at"] = name
            p.shot(f"stopped_{name}")
            break
        save_dir = getattr(g, "save_dir", None)
        if save_dir and Path(save_dir).exists():
            try:
                dst = out / "checkpoints" / name
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(save_dir, dst)
            except Exception as ex:  # noqa: BLE001
                p.log(f"checkpoint copy failed: {ex}")
    res["total_seconds"] = round(time.time() - t_run, 1)
    s = p.st()
    res["final"] = {k: s.get(k) for k in ("area", "zone", "mode", "inv", "keys")}
    res["final"]["flags_ch2"] = sorted(f for f in s.get("flags", []) if f.startswith(("ch2_", "hw_", "chapter_")))
    res["final"]["chapter2"] = s.get("chapter2")
    res["messages"] = p.all_msgs[-400:]
    res["choir_picks"] = getattr(p, "choir_picks", [])
    return res


def verify_relaunch(out: Path, attempt: int) -> dict:
    """Free play resumes in the SAME save: relaunch on the run's own save folder, Continue, check the state."""
    g = HeadlessGame(out, "s4_relaunch", pick_port(attempt + 50), max_seconds=240, extra=["--no-wardrobe-notice"])
    rec = {"ok": False}
    t0 = time.time()
    g.start()
    try:
        p = Play(g, out)
        if not p.wait(lambda s: s.get("mode") == "title" and s.get("buttons"), 90):
            rec["error"] = "no title"
            return rec
        p.click_button("Continue", exact=True, timeout=10)
        s = p.wait(lambda s: s.get("mode") == "playing" and s.get("chapter2"), 90)
        time.sleep(2.0)
        s = p.st()
        c2 = s.get("chapter2") or {}
        rec.update({"area": s.get("area"), "zone": s.get("zone"), "finished": c2.get("finished"),
                    "chapter_two_complete": "chapter_two_complete" in s.get("flags", []),
                    "ch2_done": len(c2.get("done", [])), "tracker": s.get("tracker"), "seconds": round(time.time() - t0, 1)})
        rec["inv"] = s.get("inv")
        rec["keys"] = s.get("keys")
        rec["ok"] = bool(c2.get("finished")) and rec["chapter_two_complete"] and s.get("mode") == "playing"
        p.bot.hold("W", 0.8)
        rec["moved"] = dist2(xz(p.pos()), xz(s.get("player", {}).get("pos", [0, 0, 0]))) > 0.3
    finally:
        g.stop()
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "qa" / "tmp" / "bot" / "s4" / "run"))
    ap.add_argument("--fixture", action="store_true", help="diagnostic fixture start (s4_fixture.py)")
    ap.add_argument("--start-save", default="", help="a save folder (slot1.json [+ .bak]) or a slot1.json to start from")
    ap.add_argument("--attempt", type=int, default=1)
    ap.add_argument("--from", dest="from_step", default="")
    ap.add_argument("--until", default="")
    ap.add_argument("--max-seconds", type=int, default=3000)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--loop-b", action="store_true", help="also ride the Wrong Landing's real lift and the winch cage back down")
    ap.add_argument("--real-lift", action="store_true", help="skip the false lift; take the real one (loop B)")
    ap.add_argument("--no-relaunch", action="store_true", help="skip the Continue-after-relaunch check at the end")
    a = ap.parse_args()
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    if a.fixture or not a.start_save:
        import s4_fixture
        src = s4_fixture.build(out / "fixture_src")
        start_kind = "diagnostic fixture start (s4_fixture.py)"
        bak = None
    else:
        sp = Path(a.start_save)
        src = sp / "slot1.json" if sp.is_dir() else sp
        bak = src.with_name("slot1.bak.json")
        start_kind = f"game-written save {src}"
    g = HeadlessGame(out, "s4", pick_port(a.attempt), max_seconds=a.max_seconds, seed=a.seed,
                     extra=["--no-wardrobe-notice"])
    place_save(g.save_dir, src, bak)
    t0 = time.time()
    g.start()
    res = {}
    try:
        p0 = Play(g, out)
        if not p0.wait(lambda s: s.get("mode") == "title" and s.get("buttons"), 90):
            raise RuntimeError("title screen never showed")
        if not p0.click_button("Continue", exact=True, timeout=10):
            raise RuntimeError("no Continue button")
        res = run(g, out, from_step=a.from_step, until=a.until, options={"loop_b": a.loop_b, "real_lift": a.real_lift})
    finally:
        res["start"] = start_kind
        res["wall_seconds"] = round(time.time() - t0, 1)
        res["cmd"] = g.cmd
        g.stop()
        write_json(out / "s4_result.json", res)
    if not res.get("stopped_at") and not a.until and not a.no_relaunch:
        rl = verify_relaunch(out, a.attempt)
        fin = res.get("final") or {}
        rl["same_items_as_before_quit"] = rl.get("inv") == fin.get("inv") and rl.get("keys") == fin.get("keys")
        if not rl["same_items_as_before_quit"]:
            rl["item_diff"] = {k: [(fin.get("inv") or {}).get(k), (rl.get("inv") or {}).get(k)]
                               for k in set(fin.get("inv") or {}) | set(rl.get("inv") or {})
                               if (fin.get("inv") or {}).get(k) != (rl.get("inv") or {}).get(k)}
        res["relaunch"] = rl
        write_json(out / "s4_result.json", res)
    print(json.dumps({k: res.get(k) for k in ("checkpoints", "stopped_at", "total_seconds", "wall_seconds", "relaunch")}, indent=1, default=str))


if __name__ == "__main__":
    main()
