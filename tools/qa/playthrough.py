"""Full Chapter One playthrough (fresh game), driven only by keyboard/mouse input - updated for Chapter Two.

By default every action is a real OS keyboard/mouse event sent to the focused game window (SendInput).
With --second-monitor (or --virtual-input) the same scenario runs through the game's localhost virtual-input
server instead: the window sits borderless on the second monitor, never takes focus or the cursor, and the
owner keeps using the PC. With --headless the SOURCE project runs with no window at all (console editor
binary, virtual input, no screenshots; see session.py / hhbot.py). The bot perceives the game through the
read-only QA telemetry (what's nearby, the on-screen prompt, objectives, button rects, the boss state) and
screenshots. It never grants items, teleports, or sets flags.

Route (MP 20.4 Run B, first half): New Game -> overwrite confirmation (only when a save exists) -> comfort
screen -> "Meet Krystal" creation (a non-default outfit + hairstyle picked through the UI, Confirm) -> the
Chapter One route -> the Tailor's Cache (optional Chapter One activity, real inputs) -> ... -> the reworked
3-phase Weaver Matron (drops, web fans, trip-lines, sacs/minions, reusable braziers, channels) -> restoration
+ ending -> free play -> accept the Ward Stone's new inscription (choice UI) -> save from the pause menu.

Usage:
  python tools/qa/playthrough.py --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/run1 [--until STEP]
  python tools/qa/playthrough.py --continue-save --from-step STEP ...   (Continue from a checkpoint save)
  python tools/qa/playthrough.py --second-monitor [--mute] --out qa/tmp/e2e/run2   (owner keeps the PC)
  python tools/qa/playthrough.py --headless --out qa/tmp/bot/s0/run1 [--port 7001] [--budget 5400]
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from session import Session, add_transport_args, game_log_errors, transport_kwargs  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

# Surface paths (from game/src/world/surface/surface_layout.gd PATHS), Haven-first order.
PATHS = {
    "glade": [(-9, 2), (-19, 5), (-31, 9), (-42, 12), (-49, 12)],
    "ruin": [(-2, -13), (-4, -25), (-7, -39), (-10, -51), (-12, -58)],
    "mine": [(6, -12), (14, -22), (22, -30), (30, -40), (38, -50), (44, -58), (48, -63)],
    "quarry": [(11, -3), (17, -4.5), (21, -5), (28, -6), (40, -9), (51, -11), (58, -12)],
    "old_oak": [(-8, -9), (-17, -13), (-25, -17), (-29, -19)],
}
HAVEN = (0.0, 4.0)
# The Tailor's Cache (data/c1x_layout.gd TAILOR_CACHE): north roots of the Old Oak.
TAILOR_CACHE = (-31.5, -26.0)
# Heartseed Chamber (game/src/world/below/below_layout.gd): arena centre / radius / braziers / the way in.
ARENA_C = (105.0, -137.5)
ARENA_R = 11.0
BRAZIERS = [(111.1, -134.0), (98.9, -134.0), (105.0, -144.5)]
ARENA_WAY = [(105.0, -10.0, -119.0), (105.0, -12.0, -125.0), (105.0, -12.0, -129.5)]
# "Meet Krystal" choices made through the UI (non-default: the legacy look is Cozy Explorer + Side Braid).
DEFAULT_OUTFIT = "Strawberry Picnic"
DEFAULT_HAIR = "Braided Crown"
LOOK_IDS = {"Strawberry Picnic": "strawberry_picnic", "Ribboned Adventurer": "ribboned_adventurer",
            "Cloud Cardigan": "cloud_cardigan", "Moonflower Dress": "moonflower_dress",
            "Mushroom Dungarees": "mushroom_dungarees", "Cozy Explorer": "cozy_explorer",
            "Side Braid": "side_braid", "Bob": "bob", "Long Waves": "long_waves", "High Ponytail": "high_ponytail",
            "Twin Braids": "twin_braids", "Space Buns": "space_buns", "Braided Crown": "braided_crown",
            "Half-Up Ribbon": "half_up_ribbon"}
BOSS_CEILING = ("dormant", "intro", "cling", "reposition", "recover", "release", "phase_shriek", "trip_tele",
                "combo_gap", "climb")


def xz(p):
    return (p[0], p[2]) if len(p) == 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


class StepFailed(Exception):
    pass


class Play:
    def __init__(self, sess):
        """`sess`: a Session (or anything with .bot, .shot(label) and .record(...), see ch2/s0_fresh_c1.py)."""
        self.s = sess
        self.bot = sess.bot
        self.log = self.bot.log
        self.t0 = time.time()
        self.problems: list[dict] = []       # observations worth a bug report (title, area, detail)
        self.events: list[str] = []          # every distinct telemetry message seen (evidence)
        self._seen_msgs: set = set()
        self.shots: list[str] = []
        self.notes: dict = {}                # facts for the summary (boss phases seen, deaths, ...)

    # ------------------------------------------------------------------ state helpers
    def st(self):
        s = self.bot.state()
        for m in s.get("messages", []) or []:
            key = (m.get("t"), m.get("text"))
            if key not in self._seen_msgs:
                self._seen_msgs.add(key)
                self.events.append(f"{m.get('t')} [{m.get('k')}] {m.get('text')}")
        return s

    def problem(self, title, detail="", severity="minor", area=""):
        row = {"title": title, "detail": detail, "severity": severity, "area": area or self.st().get("area", ""),
               "t": round(time.time() - self.t0, 1), "step": self.st().get("step")}
        if not any(p["title"] == title for p in self.problems):
            self.problems.append(row)
            self.log(f"PROBLEM ({severity}): {title} - {detail}")

    def inv(self, item):
        s = self.st()
        return int(s.get("inv", {}).get(item, 0)) + int(s.get("keys", {}).get(item, 0))

    def step(self):
        return self.st().get("step", "")

    def flags(self):
        return set(self.st().get("flags", []))

    def pos(self):
        return self.bot.pos()

    def hp(self):
        return float(self.st().get("player", {}).get("hp", 100.0))

    def nearby(self, pred=None, maxd=80.0):
        out = []
        for e in self.st().get("nearby", []):
            if e.get("dist", 999) <= maxd and (pred is None or pred(e)):
                out.append(e)
        return out

    def nearest(self, pred, maxd=80.0):
        lst = self.nearby(pred, maxd)
        return lst[0] if lst else None

    def prompt(self):
        return self.st().get("player", {}).get("prompt", {}) or {}

    def wait(self, pred, timeout=8.0):
        return self.bot.wait_state(pred, timeout)

    def shot(self, label):
        p = self.s.shot(label)
        self.shots.append(p)
        return p

    def ui_open(self):
        return bool(self.st().get("ui_stack"))

    # ------------------------------------------------------------------ movement
    def goto(self, target, tol=1.4, sprint=True, timeout=60.0) -> bool:
        tgt = (target[0], 0, target[1]) if len(target) == 2 else target
        ok = self.bot.walk_to(tgt, tol=tol, sprint=sprint, timeout=timeout)
        if not ok:
            self.log(f"goto {target} failed at {self.pos()}")
        return ok

    def walk_route(self, pts, sprint=True) -> bool:
        for p in pts:
            if not self.goto(p, tol=2.2, sprint=sprint):
                return False
        return True

    def travel(self, dest: str):
        """Haven -> landmark along its path."""
        self.log(f"travel to {dest}")
        pts = PATHS[dest]
        here = xz(self.pos())
        # start from the closest point on the path
        i = min(range(len(pts)), key=lambda k: dist2(pts[k], here))
        if dist2(here, HAVEN) < 12:
            i = 0
        if not self.walk_route(pts[i:]):
            raise StepFailed(f"could not reach {dest}")

    def travel_home(self):
        here = xz(self.pos())
        best, bi = None, 0
        for name, pts in PATHS.items():
            for k, p in enumerate(pts):
                d = dist2(p, here)
                if best is None or d < best[0]:
                    best = (d, name)
                    bi = k
        if best and best[0] < 25:
            pts = PATHS[best[1]][: bi + 1][::-1]
            self.walk_route(pts)
        if not self.goto(HAVEN, tol=2.5):
            raise StepFailed("could not get home")

    def face(self, pos, tol=4.0, turn_body=False):
        ok = self.bot.face_point(pos, tol)
        if turn_body:
            self.bot.hold("W", 0.08)   # the camera turned; a tiny step turns Krystal to match
        return ok

    def turn_deg(self, deg: float):
        """Turn the camera by `deg` degrees (positive = right) through mouse motion."""
        self.bot.mouse_move(deg * self.bot.px_per_deg * self.bot.invert, 0)

    # ------------------------------------------------------------------ interaction
    def approach(self, e, stop=1.3, calm=False):
        """Walk up to `e`. calm=True never sprints within 12 m (shy creatures hide from sprinting)."""
        p = e["pos"]
        me = self.pos()
        d = dist2(xz(p), xz(me))
        if calm and d > 12:
            k = (d - 10) / d
            self.goto((me[0] + (p[0] - me[0]) * k, me[2] + (p[2] - me[2]) * k), tol=1.5, sprint=True, timeout=40)
            me = self.pos()
            d = dist2(xz(p), xz(me))
        if d > stop + 0.3:
            # aim at a point `stop` metres short of the target
            k = (d - stop) / d
            tgt = (me[0] + (p[0] - me[0]) * k, me[2] + (p[2] - me[2]) * k)
            self.goto(tgt, tol=0.6, sprint=(d > 8 and not calm), timeout=40)
        self.face(p, turn_body=d <= stop + 0.3)
        time.sleep(0.25)

    def companion_entry(self, cid):
        cn = self.st().get("companion_nodes", {}).get(cid)
        if not cn:
            return None
        return {"name": "Companion_" + cid, "pos": cn["pos"], "g": "companion"}

    def befriend(self, cid, words, timeout=60.0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.st().get("companions", {}).get(cid) not in (None, "wild"):
                return True
            e = self.companion_entry(cid)
            if not e:
                time.sleep(0.5)
                continue
            self.approach(e, stop=1.4, calm=True)
            time.sleep(0.4)
            if self.prompt_matches(words):
                self.bot.tap("E")
                if self.wait(lambda s: s.get("companions", {}).get(cid) not in (None, "wild"), 4.0):
                    return True
            else:
                self.log(f"befriend {cid}: prompt={self.prompt()}")
                time.sleep(1.0)
        return False

    def prompt_matches(self, words):
        t = str(self.prompt().get("text", "")).lower()
        return any(w.lower() in t for w in words) and self.prompt().get("enabled", True)

    def press_interact_on(self, e, words, check, tries=4, stop=1.3) -> bool:
        for attempt in range(tries):
            self.approach(e, stop=stop)
            if not self.prompt_matches(words) and self.prompt().get("text"):
                # a neighbouring interactable holds the focus: strafe toward our target's side
                me = self.pos()
                yaw = math.radians(self.bot.cam_yaw() or 0.0)
                fwd = (-math.sin(yaw), -math.cos(yaw))
                to = (e["pos"][0] - me[0], e["pos"][2] - me[2])
                side = fwd[0] * to[1] - fwd[1] * to[0]      # <0: target is to the left on screen (x east, z south)
                self.bot.hold("A" if side < 0 else "D", 0.18)
                self.face(e["pos"])
                time.sleep(0.3)
            if not self.prompt_matches(words):
                # nudge: step closer if far, back off a little if we're standing on top of it
                d = dist2(xz(e["pos"]), xz(self.pos()))
                if d < 0.9:
                    # too close: back off (turns around), then walk forward again so Krystal faces it
                    self.bot.hold("S", 0.35)
                    self.face(e["pos"])
                    self.bot.hold("W", 0.12)
                else:
                    self.bot.hold("W", 0.15)
                self.face(e["pos"])
                time.sleep(0.3)
            if self.prompt_matches(words):
                self.bot.tap("E")
                if self.wait(lambda s: check(), 4.0):
                    return True
            elif check():
                return True               # done meanwhile (e.g. picked by the previous press)
            self.log(f"interact attempt {attempt + 1} on {e.get('name')} prompt={self.prompt()}")
            stop = max(0.8, stop - 0.2)
        return False

    def gather_hand(self, label_words, item, want, maxd=60.0, exclude=()):
        """Pick up hand-gatherables (sticks, stones, grass, berries) until inventory has `want` of item.
        Nodes just gathered (the nearby list refreshes every 0.4 s, so it can still offer them) and nodes that
        refused twice are skipped for a while."""
        guard = 0
        skip: dict = getattr(self, "_gather_skip", {})
        self._gather_skip = skip
        while self.inv(item) < want and guard < 40:
            guard += 1
            now = time.time()

            def ok(n):
                t = (n.get("label", "") + " " + n.get("text", "")).lower()
                key = n.get("id") or n.get("name")
                return (n.get("tool") == "hand" and n.get("enabled", True) and "regrow" not in n.get("text", "").lower()
                        and skip.get(key, 0) < now
                        and any(w.lower() in t for w in label_words) and not any(x.lower() in t for x in exclude))
            e = self.nearest(ok, maxd)
            if not e:
                raise StepFailed(f"no {label_words} nearby")
            key = e.get("id") or e.get("name")
            before = self.inv(item)
            ok2 = self.press_interact_on(e, label_words, lambda: self.inv(item) > before or not self._still_there(e), tries=2)
            if ok2:
                skip[key] = time.time() + 20.0
                time.sleep(0.45)          # let the nearby list catch up before picking the next node
            else:
                self.log(f"could not gather {e}")
                skip[key] = time.time() + 90.0
                # step away and try another one
                self.bot.hold("S", 0.4)
        return self.inv(item) >= want

    def _still_there(self, e):
        for n in self.nearby(maxd=90):
            if n.get("id") == e.get("id") and e.get("id") and n.get("text", "") == e.get("text", ""):
                return True
        return False

    def harvest_tool(self, words, item, want, maxd=70.0, swings=14, prefer_pos=None):
        """Chop/mine with LMB until `item` count reaches want."""
        guard = 0
        while self.inv(item) < want and guard < 30:
            guard += 1
            pred = lambda n: n.get("g") == "harvestable" and n.get("tool") in ("axe", "pickaxe") and any(w.lower() in n.get("label", "").lower() for w in words)
            cands = self.nearby(pred, maxd)
            if prefer_pos is not None:
                cands.sort(key=lambda n: dist2(xz(n["pos"]), prefer_pos))
            if not cands:
                raise StepFailed(f"no {words} to harvest")
            e = cands[0]
            before = self.inv(item)
            self.approach(e, stop=1.6)
            n = 0
            while n < swings:
                p = self.prompt()
                if p.get("action") == "attack" and p.get("enabled", True):
                    self.bot.tap("LMB", 0.06)
                    time.sleep(0.6)
                    n += 1
                    if self.inv(item) >= want:
                        break
                    if self.inv(item) > before and not self._harvestable_at(e):
                        break
                else:
                    self.bot.hold("W", 0.12)
                    self.face(e["pos"])
                    time.sleep(0.2)
                    n += 0.5
                if self._node_gone(e):
                    break
            time.sleep(0.8)   # let pickups settle / auto-collect
        return self.inv(item) >= want

    def _harvestable_at(self, e):
        for n in self.nearby(maxd=90):
            if n.get("id") and n.get("id") == e.get("id") and n.get("g") == "harvestable":
                return True
        return False

    def _node_gone(self, e):
        p = self.prompt()
        return not p or "needs" in str(p.get("text", "")).lower()

    # ------------------------------------------------------------------ UI actions
    def open_panel(self, key, name, timeout=3.0):
        if name in self.st().get("ui_stack", []):
            return True
        self.bot.tap(key)
        return bool(self.wait(lambda s: name in s.get("ui_stack", []), timeout))

    def close_panels(self):
        for _ in range(4):
            if not self.st().get("ui_stack"):
                return True
            self.bot.tap("ESC")
            time.sleep(0.4)
        # pause menu may have opened: resume
        if "pause" in self.st().get("ui_stack", []):
            self.bot.click_button("Resume", exact=True)
        return not self.st().get("ui_stack")

    def click(self, text, exact=False, timeout=4.0):
        return self.bot.click_button(text, exact=exact, timeout=timeout)

    def click_scrolled(self, prefix, timeout=12.0):
        """Click a (possibly scrolled-out) list button whose text starts with prefix."""
        t0 = time.time()
        while time.time() - t0 < timeout:
            bs = [b for b in self.bot.buttons() if b["text"].lower().startswith(prefix.lower())]
            if bs:
                b = bs[0]
                if not b.get("clipped"):
                    self.bot.click_at_button(b)
                    time.sleep(0.3)
                    return True
                # scroll the list: hover a VISIBLE row of the same list (same column) nearest to the target, so the
                # wheel reaches the scroll container, then wheel toward the target
                x, y, w, h = self.bot.rect_of(b)
                same = [o for o in self.bot.buttons() if not o.get("clipped") and o is not b
                        and abs(self.bot.rect_of(o)[0] - x) < max(1.0, w * 0.05) and abs(self.bot.rect_of(o)[2] - w) < max(1.0, w * 0.05)]
                if same:
                    anchor = min(same, key=lambda o: abs(self.bot.rect_of(o)[1] - y))
                    ax, ay, aw, ah = self.bot.rect_of(anchor)
                    self.bot.hover(ax + aw / 2.0, ay + ah / 2.0)
                    down = y > ay
                else:
                    win_h = self.bot.view_size()[1]
                    margin = win_h * 0.28
                    self.bot.hover(x + w / 2.0, min(max(y, margin), win_h - margin))
                    down = y > win_h / 2
                self.bot.wheel(-120 if down else 120)
                time.sleep(0.2)
            else:
                time.sleep(0.2)
        self.log(f"list button {prefix!r} not found")
        return False

    def goto_station(self, word):
        """Walk to the nearest crafting station whose prompt mentions `word` (e.g. Workbench, Campfire)."""
        e = self.nearest(lambda n: word.lower() in (n.get("text", "") + " " + n.get("name", "")).lower() and n.get("g") in ("interactable", "crafting_station"), 90)
        if not e:
            self.travel_home()
            e = self.nearest(lambda n: word.lower() in (n.get("text", "") + " " + n.get("name", "")).lower() and n.get("g") in ("interactable", "crafting_station"), 90)
        if not e:
            raise StepFailed(f"no {word} found")
        self.approach(e, stop=2.2)
        return True

    def craft(self, recipe_name, times=1, station_tab=None, item=None, _retry=True) -> bool:
        """Crafting panel: (station tab) -> recipe row -> Craft x times. With `item` the result is verified from the
        inventory (a click on a stale row once crafted the wrong thing) and the selection retried once."""
        self.log(f"craft {recipe_name} x{times}")
        if station_tab:
            self.goto_station(station_tab)
        before = dict(self.st().get("inv", {}))
        if not self.open_panel("C", "crafting"):
            raise StepFailed("crafting panel did not open")
        time.sleep(0.4)
        if station_tab:
            self.click(station_tab, exact=True)
            # the list is rebuilt for the tab: wait for the telemetry's button list (refreshed every 0.2 s) to show
            # it, or a click could land on a stale row (seen: Window Walls crafted instead of the Lantern)
            time.sleep(0.7)
        if not self.click_scrolled(recipe_name + " |") and not self.click_scrolled(recipe_name):
            self.close_panels()
            return False
        time.sleep(0.3)
        for _ in range(times):
            if not self.click("Craft", exact=True):
                cb = [b for b in self.bot.buttons() if b["text"] == "Craft"]
                self.log(f"Craft button unavailable (disabled={cb[0]['disabled'] if cb else 'missing'}); inv={self.st().get('inv')}")
                break
            time.sleep(0.35)
        time.sleep(0.3)
        self.shot(f"craft_{recipe_name.replace(' ', '_')}")
        self.close_panels()
        time.sleep(0.3)
        after = self.st().get("inv", {})
        gained = {k: after.get(k, 0) - before.get(k, 0) for k in after if after.get(k, 0) > before.get(k, 0)}
        self.log(f"crafted: {gained}")
        if item and after.get(item, 0) <= before.get(item, 0):
            self.log(f"craft {recipe_name}: no {item} gained (got {gained})")
            if _retry:
                time.sleep(0.5)
                return self.craft(recipe_name, times, station_tab, item, _retry=False)
            return False
        return True

    def slot_button(self, item):
        for b in self.bot.buttons():
            if b["text"].startswith("slot:bag:") and b.get("item") == item and not b.get("clipped"):
                return b
        return None

    def eat_best(self):
        for food in ("hearty_stew", "glowcap_skewer", "berry_snack", "sweetroot", "berries"):
            if self.inv(food) > 0:
                if not self.open_panel("TAB", "inventory"):
                    return False
                time.sleep(0.4)
                b = self.slot_button(food)
                if b:
                    self.bot.click_at_button(b)
                    time.sleep(0.08)
                    self.bot.click_at_button(b)
                    time.sleep(0.5)
                self.close_panels()
                self.log(f"ate {food}; hp now {self.hp()}")
                return True
        return False

    def place(self, item, near=None, tries=12) -> bool:
        """Enter build mode, select `item`, aim at the ground and place it."""
        self.log(f"place {item}")
        if near:
            self.goto(near, tol=1.5, sprint=False)
        before = self.inv(item)
        self.bot.tap("B")
        if not self.wait(lambda s: s.get("build", {}).get("active"), 3.0):
            raise StepFailed("build mode did not start")
        # cycle selection with the wheel until the item is selected
        for _ in range(20):
            if self.st().get("build", {}).get("item") == item:
                break
            self.bot.wheel(-120)
            time.sleep(0.25)
        if self.st().get("build", {}).get("item") != item:
            self.bot.tap("B")
            raise StepFailed(f"could not select {item} in build mode")
        placed = False
        for k in range(tries):
            b = self.st().get("build", {})
            if b.get("valid"):
                self.bot.tap("LMB", 0.06)
                if self.wait(lambda s: int(s.get("inv", {}).get(item, 0)) < before, 2.0):
                    placed = True
                    break
            self.log(f"placement invalid: {b.get('reason')}")
            # adjust: turn a bit (about 5 degrees) and step back now and then
            self.turn_deg(5.0)
            if k % 3 == 2:
                self.bot.hold("S", 0.3)
            time.sleep(0.4)
        self.shot(f"placed_{item}")
        if self.st().get("build", {}).get("active"):
            self.bot.tap("B")
            time.sleep(0.4)
        return placed

    def pause_save(self) -> bool:
        """Save through the pause menu (Esc -> Save Game) and prove it with the "journey saved" message."""
        def last_saved(st):
            ts = [float(m.get("t", 0.0)) for m in st.get("messages", []) if m.get("k") == "saved" and "FAILED" not in m.get("text", "")]
            return max(ts) if ts else -1.0
        t_before = last_saved(self.st())
        self.bot.tap("ESC")
        if not self.wait(lambda s: "pause" in s.get("ui_stack", []), 3.0):
            self.log("pause menu did not open")
            return False
        if not self.click("Save Game", timeout=4):
            self.close_panels()
            return False
        # the message list holds only the last 12 messages: compare the newest "saved" time, not a count
        ok = self.wait(lambda s: last_saved(s) > t_before, 5.0) is not None
        self.close_panels()
        return ok

    # ------------------------------------------------------------------ combat
    def live_enemies(self, pred=None, maxd=30.0):
        return [e for e in self.nearby(lambda n: n.get("g") == "enemy" and (pred is None or pred(n)), maxd)
                if e.get("hp", 1) > 0 and e.get("state") not in ("dead", "dying")]

    def fight(self, pred=None, timeout=90.0, flee_hp=35.0) -> bool:
        """Fight nearby threatening enemies with real inputs until none remain."""
        t0 = time.time()
        last_seen = time.time()
        while time.time() - t0 < timeout:
            live = self.live_enemies(pred, 30)
            if not live:
                if time.time() - last_seen > 3.0:
                    return True
                time.sleep(0.3)
                continue
            last_seen = time.time()
            e = live[0]
            if self.hp() < flee_hp:
                self.bot.hold("S", 0.2)
                self.eat_best()
                continue
            d = e["dist"]
            self.face(e["pos"], tol=8)
            state = e.get("state", "")
            if state in ("telegraph", "windup", "wind_up") and d < 3.5:
                # dodge backwards/sideways
                self.bot.win.focus()
                self.bot.down("S")
                self.bot.tap("CTRL")
                time.sleep(0.25)
                self.bot.up("S")
                continue
            if d > 2.0:
                self.bot.hold("W", min(0.5, (d - 1.6) / 5.0 + 0.1))
            else:
                self.bot.tap("LMB", 0.06)
                time.sleep(0.45)
        return False


# ====================================================================== the chapter
def run(args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    save_dir = Path(args.save_dir) if args.save_dir else out / "saves"
    tk = transport_kwargs(args)
    if tk.get("headless"):
        exe = args.exe if "console" in Path(args.exe).name.lower() else ""
        pre = []
    else:
        exe = str(Path(args.exe).resolve())
        pre = ["--path", str(ROOT / "game")] if args.dev else []
    extra = ["--windowed"] if not tk.get("headless") else []
    sess = Session(exe or str(ROOT / ".tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"), out, save_dir,
                   args.name, extra=extra, pre_args=pre, **tk)
    sess.start(wait_for=lambda s: s.get("mode") == "title" and len(s.get("buttons", [])) > 0, timeout=90)
    play = Play(sess)
    results = run_steps(play, args, save_dir, out, sess.record)
    summary = {"results": results, "problems": play.problems, "notes": play.notes,
               "final_state": {k: play.st().get(k) for k in ("step", "area", "inv", "keys", "flags", "companions", "optional", "appearance", "chapter2")},
               "game_log_errors": game_log_errors(sess.game_log) if sess.headless else []}
    (out / f"{args.name}_summary.json").write_text(json.dumps(summary, indent=2))
    (out / f"{args.name}_events.txt").write_text("\n".join(play.events), encoding="utf-8")
    if not args.keep_open:
        sess.stop()
    return results


def run_steps(play: Play, args, save_dir: Path | None, out: Path, record=None, budget: float | None = None) -> list:
    """Runs the scenario steps (build_steps) with timing, evidence and checkpoint copies of the save folder.
    Stops at the first failed step, at args.until, or when `budget` seconds are used up."""
    results = []
    t_start = time.time()
    budget = budget if budget is not None else getattr(args, "budget", None)

    def check(name, fn):
        t = time.time()
        play.log(f"=== STEP {name} (quest step {play.step()}, +{t - t_start:.0f}s) ===")
        try:
            ok = fn()
            ok = True if ok is None else bool(ok)
        except StepFailed as ex:
            ok = False
            play.log(f"StepFailed: {ex}")
        except Exception as ex:  # noqa: BLE001
            ok = False
            import traceback
            play.log(f"EXCEPTION {type(ex).__name__}: {ex}\n{traceback.format_exc()}")
        ev = play.shot(name)
        dur = time.time() - t
        results.append({"step": name, "ok": ok, "seconds": round(dur, 1), "elapsed": round(time.time() - t_start, 1),
                        "quest": play.step(), "evidence": ev})
        if record:
            record(f"playthrough:{name}", "interactive", f"real-input scenario step {name}", "step completes",
                   f"quest step now {play.step()}; ok={ok}; {dur:.0f}s", "PASS" if ok else "FAIL", [ev])
        if not ok:
            raise StepFailed(name)
        # Headless runs skip the game's 5-minute quiet autosave, so a surface step would leave no save behind:
        # with checkpoint_saves the bot saves through the pause menu (a normal player action) where saving is allowed.
        if getattr(args, "checkpoint_saves", False) and name not in ("free_play_save",):
            st = play.st()
            if st.get("mode") == "playing" and not st.get("ui_stack") and st.get("area") in ("surface", "hallowmere_reach"):
                if not play.pause_save():
                    play.log(f"checkpoint save after {name} did not happen")
        # snapshot the save folder after each passed step (lets QA resume a scenario via Continue)
        try:
            if save_dir is not None and save_dir.exists() and any(save_dir.iterdir()):
                dst = out / "checkpoints" / name
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(save_dir, dst)
        except Exception as ex:  # noqa: BLE001
            play.log(f"checkpoint copy failed: {ex}")

    steps = build_steps(play, args)
    from_step = getattr(args, "from_step", "")
    started = not from_step
    try:
        for name, fn in steps:
            if getattr(args, "until", "") and name == args.until:
                break
            if not started and name != "title_new_game":
                if name == from_step:
                    started = True
                else:
                    continue
            if budget and time.time() - t_start > budget:
                play.log(f"time budget {budget:.0f}s used up before step {name}")
                results.append({"step": name, "ok": False, "seconds": 0, "elapsed": round(time.time() - t_start, 1),
                                "quest": play.step(), "evidence": "", "note": "time budget exhausted"})
                break
            check(name, fn)
    except StepFailed as ex:
        play.log(f"PLAYTHROUGH STOPPED at {ex}")
    return results


def build_steps(p: Play, args):
    b = p.bot
    continue_save = bool(getattr(args, "continue_save", False))
    outfit = getattr(args, "outfit", DEFAULT_OUTFIT) or ""
    hair = getattr(args, "hair", DEFAULT_HAIR) or ""
    # "thorough": one brazier in phase 1, missed drops only in phase 2 (fans, trip-lines, sacs/minions happen),
    # phase 3 waits for the channel before using braziers; "fast": a brazier whenever a phase starts.
    matron_style = getattr(args, "matron_style", "thorough") or "thorough"

    def title_new_game():
        if continue_save:
            if not p.click("Continue"):
                raise StepFailed("no Continue button")
        else:
            p.click("New Game", exact=True)
            time.sleep(1.0)
            # overwrite confirmation (only when a save exists; "Start fresh" in Chapter Two builds)
            if p.click("Start fresh", exact=True, timeout=2.0) or p.click("Start a new journey", timeout=0.5):
                p.notes["overwrite_confirm"] = "shown and accepted"
                time.sleep(0.8)
            else:
                p.notes["overwrite_confirm"] = "not shown (no save in the isolated save dir)"
            if not p.click("Begin the journey", timeout=6.0):
                raise StepFailed("comfort screen missing")
            time.sleep(1.2)
            meet_krystal()
        if not p.wait(lambda s: s.get("mode") == "playing" and s.get("area") in ("surface", "below", "tobin_annex"), 60):
            raise StepFailed("never reached gameplay")
        time.sleep(2.5)
        b.calibrate_look()
        if not continue_save and (outfit or hair):
            verify_look()
        return True

    def meet_krystal():
        """The "Meet Krystal" creation screen: pick the outfit, then the hairstyle, through the UI; Confirm."""
        if not p.wait(lambda s: any(x.get("text") == "Confirm" for x in s.get("buttons", [])) and
                      any(x.get("text") == "Outfits" for x in s.get("buttons", [])), 8.0):
            p.problem("'Meet Krystal' creation screen not shown after the comfort screen",
                      f"buttons: {[x['text'] for x in b.buttons()][:30]}", "major", "title")
            return
        p.shot("meet_krystal")
        if outfit:
            if not (p.click("Outfits", exact=True) and time.sleep(0.5) is None and p.click(outfit, exact=True)):
                raise StepFailed(f"could not pick outfit {outfit!r}")
            time.sleep(0.5)
        if hair:
            if not (p.click("Hair", exact=True) and time.sleep(0.5) is None and p.click(hair, exact=True)):
                raise StepFailed(f"could not pick hairstyle {hair!r}")
            time.sleep(0.5)
        p.shot("meet_krystal_chosen")
        if not p.click("Confirm", exact=True):
            raise StepFailed("no Confirm on Meet Krystal")

    def verify_look():
        look = p.wait(lambda s: bool(s.get("appearance")), 5.0)
        look = (look or {}).get("appearance") or {}
        want = {}
        if outfit:
            want["outfit"] = LOOK_IDS.get(outfit, outfit)
        if hair:
            want["hair"] = LOOK_IDS.get(hair, hair)
        got = {k: look.get(k) for k in want}
        p.notes["look"] = {"wanted": want, "got": got}
        if look and got != want:
            p.problem("Chosen look not applied on New Game", f"wanted {want}, telemetry appearance {got}", "major", "surface")
        if "opt_look_of_your_own" not in (p.st().get("optional", {}) or {}).get("done", []):
            p.problem("'A Look of Your Own' not completed by the creation screen", "optional.done lacks opt_look_of_your_own",
                      "minor", "surface")

    def read_ward():
        e = p.nearest(lambda n: n.get("name") == "WardStone" or "ward stone" in n.get("text", "").lower())
        if not e:
            raise StepFailed("no ward stone")
        ok = p.press_interact_on(e, ["Ward Stone", "Read"], lambda: "read_ward_intro" in p.flags(), stop=2.2)
        time.sleep(4.0)  # let the inscription lines play
        return ok

    def gather_basics():
        p.gather_hand(["Stick"], "wood", 4)
        p.gather_hand(["Stone"], "stone", 7)
        p.gather_hand(["Grass", "Fiber"], "fiber", 6)
        return p.wait(lambda s: s.get("step") != "gather_basics", 5)

    def craft_axe():
        p.craft("Stone Axe", item="stone_axe")
        return p.inv("stone_axe") >= 1

    def chop():
        p.harvest_tool(["Oak", "Tree", "Pine", "Birch", "Blossom"], "wood", 22, maxd=60)
        return p.wait(lambda s: s.get("step") != "chop", 6) is not None or p.inv("wood") >= 10

    def workbench():
        p.goto(HAVEN, tol=2.5)
        if p.inv("workbench") < 1:
            p.craft("Workbench", item="workbench")
        return p.place("workbench", near=(-6.0, 3.0)) and bool(p.wait(lambda s: s.get("step") != "workbench", 5))

    def tailor_cache():
        """Optional Chapter One activity (MP 7 "The Tailor's Cache"): follow the ribbons past the Old Oak and
        open the cache - real inputs only."""
        p.travel("old_oak")
        p.goto((-30.0, -23.2), tol=1.2, sprint=False, timeout=30)
        e = p.nearest(lambda n: "tailor" in n.get("text", "").lower(), 20)
        if not e:
            raise StepFailed(f"Tailor's Cache not found near {p.pos()}")
        ok = p.press_interact_on(e, ["Tailor's Cache"], lambda: "c1x_tailor_cache" in p.flags(), stop=1.4)
        time.sleep(2.0)
        done = "opt_tailors_cache" in (p.st().get("optional", {}) or {}).get("done", [])
        p.notes["tailor_cache"] = {"flag": "c1x_tailor_cache" in p.flags(), "optional_done": done}
        if ok and not done:
            p.problem("Tailor's Cache opened but opt_tailors_cache not marked done", str(p.st().get("optional")), "minor", "surface")
        p.walk_route(PATHS["old_oak"][::-1])
        return ok

    def mochi():
        p.travel("glade")
        # berries: gather until we have plenty (3 for Mochi, 8 for snacks, spare); never the new Roseberry bushes
        p.gather_hand(["Berr"], "berries", 14, maxd=45, exclude=("rose",))
        ok = p.befriend("mochi", ["Offer"])
        time.sleep(3)
        return ok

    def pebble():
        p.travel_home()
        if p.inv("stone") < 3:
            p.gather_hand(["Stone"], "stone", 3)
        if p.inv("fiber") < 2:
            p.gather_hand(["Grass", "Fiber"], "fiber", 4)
        if p.inv("stone_pickaxe") < 1:
            p.craft("Stone Pickaxe", item="stone_pickaxe")
        p.travel("quarry")
        p.goto((68, -16), tol=3)
        e = p.nearest(lambda n: "boulder" in (n.get("label", "") + n.get("text", "")).lower(), 40)
        if not e:
            raise StepFailed("boulder not found")
        p.approach(e, stop=1.8)
        for _ in range(16):
            if p.st().get("companions", {}).get("pebble") != "wild":
                break
            pr = p.prompt()
            if "help the little stone" in str(pr.get("text", "")).lower():
                break
            if pr.get("action") == "attack":
                b.tap("LMB", 0.06)
                time.sleep(0.7)
            else:
                p.approach(e, stop=1.5)
        time.sleep(1.5)
        peb = p.nearest(lambda n: "help the little stone" in n.get("text", "").lower(), 20)
        if peb:
            p.press_interact_on(peb, ["Help the little stone"], lambda: p.st().get("companions", {}).get("pebble") != "wild", stop=1.4)
        time.sleep(3)
        # copper for sword (4), lantern (3) + spare
        p.harvest_tool(["Copper", "Ore"], "copper_ore", 9, maxd=50)
        return p.st().get("companions", {}).get("pebble") != "wild"

    def home():
        p.travel_home()
        need_wood = 8 + 3 + 2 + 2 + 5   # bed, crop plot, sword, lantern, spare
        if p.inv("wood") < need_wood:
            p.harvest_tool(["Oak", "Tree", "Pine", "Birch", "Blossom"], "wood", need_wood, maxd=60)
            p.goto(HAVEN, tol=2.5)
        if p.inv("fiber") < 6 + 3 + 2 + 2:
            p.gather_hand(["Grass", "Fiber"], "fiber", 13)
        p.craft("Cozy Bed", station_tab="Workbench", item="bed")
        p.craft("Crop Plot", item="crop_plot")
        p.place("bed", near=(-9.0, -2.0))
        p.place("crop_plot", near=(-7.0, 9.0))
        plot = p.nearest(lambda n: n.get("text", "").lower().startswith("plant"), 25)
        if not plot:
            raise StepFailed("crop plot not found")
        seeds0 = p.inv("sweetroot_seeds")
        p.press_interact_on(plot, ["Plant"], lambda: p.inv("sweetroot_seeds") < seeds0, stop=1.8)
        return p.wait(lambda s: s.get("step") not in ("home",), 6) is not None

    def lumi():
        if p.inv("copper_sword") < 1:
            p.craft("Copper Sword", station_tab="Workbench", item="copper_sword")
        if p.inv("lantern") < 1:
            p.craft("Lantern", station_tab="Workbench", item="lantern")
        if p.inv("berry_snack") < 2 and p.inv("berries") >= 8:
            p.craft("Berry Snack", times=2, item="berry_snack")
        p.travel("ruin")
        p.goto((-12, -62), tol=2.5)
        p.fight(timeout=120)
        time.sleep(2)
        if "ruin_cleared" not in p.flags():
            # look for remaining bramblings around the ruin
            for spot in [(-6, -66), (-18, -66), (-12, -72)]:
                p.goto(spot, tol=2.5)
                p.fight(timeout=40)
                if "ruin_cleared" in p.flags():
                    break
        if "ruin_cleared" not in p.flags():
            raise StepFailed("ruin not cleared")
        time.sleep(3)
        ok = p.befriend("lumi", ["Reach out"])
        time.sleep(3)
        return ok

    def prepare():
        p.travel_home()
        e = p.nearest(lambda n: n.get("name") == "WardStone")
        p.press_interact_on(e, ["Ward Stone", "Listen", "Read"], lambda: "read_ward_warning" in p.flags(), stop=2.2)
        time.sleep(5)
        if p.inv("lantern") < 1:
            p.craft("Lantern", station_tab="Workbench", item="lantern")
        if p.inv("berry_snack") + p.inv("hearty_stew") < 3:
            need = 4 * (3 - p.inv("berry_snack") - p.inv("hearty_stew"))
            if p.inv("berries") < need:
                # go pick more: bushes around the Haven first, then the Berry Glade
                try:
                    p.gather_hand(["Berr"], "berries", need + 2, maxd=45, exclude=("rose",))
                except StepFailed:
                    p.travel("glade")
                    p.gather_hand(["Berr"], "berries", need + 2, maxd=45, exclude=("rose",))
                    p.travel_home()
            p.craft("Berry Snack", times=max(1, need // 4), item="berry_snack")
        return p.wait(lambda s: s.get("step") == "descend", 8) is not None

    def brave_steps():
        """Optional Chapter One activity #2 (MP 6.4 / 7 "Brave Little Steps"): build the Loom the Tailor's Cache
        unlocked, weave a Comfort Ribbon, tie it on Mochi in the Friends panel and take Mochi along (the courage
        lantern at the mine mouth is visited in `descend`). Never blocks the Chapter One route: a failure is
        recorded as a problem and the route goes on with Lumi."""
        stage = "start"
        try:
            if "c1x_tailor_cache" not in p.flags():
                p.notes["brave_steps"] = "skipped (no Tailor's Cache -> no Loom recipe)"
                return True
            p.travel_home()
            stage = "materials"
            if p.inv("loom") < 1:
                if p.inv("wood") < 8:
                    p.harvest_tool(["Oak", "Tree", "Pine", "Birch", "Blossom"], "wood", 8, maxd=60)
                    p.goto(HAVEN, tol=2.5)
                if p.inv("fiber") < 6:
                    p.gather_hand(["Grass", "Fiber"], "fiber", 6)
                stage = "craft_loom"
                p.craft("Loom & Dye Bench", station_tab="Workbench", item="loom")
                if p.inv("loom") < 1:
                    raise StepFailed("the Loom could not be crafted at the workbench")
            stage = "place_loom"
            if not p.nearest(lambda n: "loom" in n.get("text", "").lower(), 40):
                if not p.place("loom", near=(4.0, 9.0)):
                    raise StepFailed("the Loom could not be placed")
            if p.inv("berries") < 2:
                p.gather_hand(["Berr"], "berries", 2, maxd=45, exclude=("rose",))
            stage = "weave_ribbon"
            if p.inv("comfort_ribbon") < 1 and (p.st().get("companions") or {}).get("mochi") not in (None, "wild"):
                loom = p.nearest(lambda n: "loom" in n.get("text", "").lower(), 40)
                if not loom:
                    raise StepFailed("placed Loom not found")
                if not p.press_interact_on(loom, ["Loom"], lambda: "crafting" in p.st().get("ui_stack", []), stop=2.0):
                    raise StepFailed(f"the Loom's crafting panel did not open (prompt {p.prompt()})")
                time.sleep(0.5)
                if not p.click_scrolled("Comfort Ribbon"):
                    p.close_panels()
                    raise StepFailed(f"no Comfort Ribbon recipe at the Loom (buttons {[x['text'] for x in b.buttons()][:25]})")
                if not p.click("Craft", exact=True):
                    cb = [x for x in b.buttons() if x["text"] == "Craft"]
                    p.close_panels()
                    raise StepFailed(f"Comfort Ribbon: Craft unavailable (disabled={cb[0]['disabled'] if cb else 'missing'}; inv={p.st().get('inv')})")
                time.sleep(0.6)
                p.shot("comfort_ribbon")
                p.close_panels()
                if p.inv("comfort_ribbon") < 1:
                    raise StepFailed("no Comfort Ribbon after crafting")
            stage = "tie_ribbon"
            e = p.companion_entry("mochi")
            if not e:
                raise StepFailed("Mochi not found near the Haven")
            # Mochi pads around the Haven (inspecting new furniture): keep re-targeting its live position
            opened = False
            t_chase = time.time()
            while time.time() - t_chase < 30.0 and not opened:
                e = p.companion_entry("mochi") or e
                me = p.pos()
                d = dist2(xz(e["pos"]), xz(me))
                if d > 1.6:
                    k = (d - 1.2) / d
                    p.goto((me[0] + (e["pos"][0] - me[0]) * k, me[2] + (e["pos"][2] - me[2]) * k), tol=0.5,
                           sprint=d > 6, timeout=1.2)
                    continue
                p.face(e["pos"], tol=8, turn_body=True)
                time.sleep(0.2)
                if p.prompt_matches(["Talk to Mochi"]):
                    # the game re-picks the focus when E lands (player.gd _interact -> probe.refresh()), a telemetry
                    # frame or two after the prompt we read; Lumi follows ~2 m away and can win that re-pick while
                    # Mochi runs off (final_201_fresh): check whose panel opened and retry if it is not Mochi's
                    b.tap("E")
                    if p.wait(lambda st: "companion" in st.get("ui_stack", []), 3.0):
                        time.sleep(0.4)
                        btns = [x["text"] for x in b.buttons()]
                        if any(t.startswith("Use Glimmerstep") for t in btns):
                            p.log(f"E opened Lumi's panel instead of Mochi's ({btns[:8]}); retrying")
                            p.close_panels()
                            time.sleep(0.3)
                        else:
                            opened = True
                else:
                    time.sleep(0.3)
            if not opened:
                raise StepFailed(f"could not open Mochi's Friends panel (prompt {p.prompt()})")
            time.sleep(0.5)
            if not p.click("Tie the Comfort Ribbon", exact=True):
                btns = [x["text"] for x in b.buttons()][:30]
                p.close_panels()
                raise StepFailed(f"'Tie the Comfort Ribbon' not available (buttons {btns})")
            time.sleep(0.5)
            p.click("Follow me", exact=True, timeout=2.0)
            time.sleep(0.4)
            p.shot("mochi_ribbon")
            p.close_panels()
            ok = p.wait(lambda st: (st.get("companions") or {}).get("mochi") == "follow", 4.0) is not None
            p.notes["brave_steps"] = {"ribbon_tied": "c1x_ribbon_given" in p.flags(), "mochi_follows": ok}
            return True
        except StepFailed as ex:
            p.notes["brave_steps"] = f"failed at {stage}: {ex}"
            p.problem(f"Brave Little Steps blocked at '{stage}'", str(ex), "minor", "surface")
            p.close_panels()
            return True

    def courage_lantern():
        """With the ribbon tied and Mochi following: rest by the courage lantern at the mine mouth."""
        if "c1x_ribbon_given" not in p.flags() or "c1x_mochi_courage" in p.flags():
            return
        lan = p.nearest(lambda n: "lantern" in n.get("text", "").lower() and ("mochi" in n.get("text", "").lower() or "warm" in n.get("text", "").lower()), 40)
        if not lan:
            p.problem("Courage lantern not found at the mine mouth", f"near {p.pos()}", "minor", "surface")
            return
        for _ in range(3):
            ok = p.press_interact_on(lan, ["Rest by the lantern"], lambda: "c1x_mochi_courage" in p.flags(), tries=2, stop=1.6)
            if ok:
                break
            p.log(f"courage lantern: prompt {p.prompt()} mochi {p.st().get('companion_nodes', {}).get('mochi')}")
            time.sleep(2.0)
        time.sleep(4.0)
        done = "opt_brave_little_steps" in (p.st().get("optional") or {}).get("done", [])
        p.notes["courage_lantern"] = {"flag": "c1x_mochi_courage" in p.flags(), "optional_done": done}
        if "c1x_mochi_courage" not in p.flags():
            p.problem("Resting by the courage lantern with Mochi did not give Mochi courage",
                      f"prompt {p.prompt()}; mochi {p.st().get('companion_nodes', {}).get('mochi')}", "minor", "surface")

    def descend():
        p.travel("mine")
        courage_lantern()
        p.goto((51, -69), tol=2.0)
        e = p.nearest(lambda n: "rubble" in (n.get("label", "") + n.get("text", "") + n.get("name", "")).lower(), 20)
        if e:
            p.approach(e, stop=1.8)
            for _ in range(14):
                if "mine_opened" in p.flags():
                    break
                if p.prompt().get("action") == "attack":
                    b.tap("LMB", 0.06)
                    time.sleep(0.7)
                else:
                    p.approach(e, stop=1.5)
        if "mine_opened" not in p.flags():
            raise StepFailed("mine not opened")
        time.sleep(1.5)
        ent = p.nearest(lambda n: "enter" in n.get("text", "").lower() and "mine" in n.get("text", "").lower(), 20)
        if not ent:
            raise StepFailed("no mine entrance interaction")
        p.press_interact_on(ent, ["Enter"], lambda: bool(p.st().get("ui_stack")) or p.st().get("area") == "below", stop=1.6)
        time.sleep(1.0)
        # first time: comfort reminder
        for label in ("Descend", "Continue", "Done", "Begin", "Enter"):
            if p.find_btn(label):
                p.click(label)
                break
        ok = p.wait(lambda s: s.get("area") == "below" and s.get("mode") == "playing", 30) is not None
        # the area change autosaves right after the fade-in: wait for the "Journey saved" toast
        p.wait(lambda s: any("saved" in m.get("text", "").lower() for m in s.get("messages", [])), 10)
        time.sleep(1.0)
        return ok

    p.find_btn = lambda label: b.find_button(label)

    # ---- underground --------------------------------------------------------------------------
    def light_cp(cp_pos):
        e = p.nearest(lambda n: n.get("g") in ("checkpoint", "interactable") and "lantern" in n.get("text", "").lower() and dist2(xz(n["pos"]), cp_pos) < 3.0, 30)
        if e and "light" in e.get("text", "").lower():
            p.press_interact_on(e, ["Light"], lambda: True, stop=1.5)
            time.sleep(1.5)

    def below_walk(points, fight=True):
        for pt in points:
            if fight and p.nearby(lambda n: n.get("g") == "enemy" and n.get("hp", 1) > 0 and n.get("state") not in ("dead", "dying")
                                  and n.get("kind") not in ("trip", "thread", "sac"), 11):
                p.fight(timeout=90)
            if not p.goto((pt[0], pt[2]), tol=1.2, sprint=True, timeout=40):
                # try fighting / retry once
                p.fight(timeout=20)
                if not p.goto((pt[0], pt[2]), tol=1.5, sprint=False, timeout=30):
                    raise StepFailed(f"blocked below at {p.pos()} -> {pt}")

    CP = [(0.0, 0.0, 0.8), (0.0, 0.0, -5.0), (-1.0, 0.0, -8.0), (-1.0, 0.0, -34.0), (0.0, 0.0, -37.5), (0.0, 0.0, -43.0)]

    def old_mine():
        if not p.st().get("player", {}).get("lantern"):
            b.tap("F")
        light_cp((-5.6, -1.6))
        below_walk(CP[:5])
        # the Collapsed Gallery's Gloomlings: go in with the lantern raised and deal with them
        p.goto((0.0, -41.0), tol=1.2)
        p.fight(timeout=150)
        # office detour: rubble fills the passage at x = 8..12
        p.goto((6.6, -43.75), tol=0.8, sprint=False)
        for _ in range(24):
            if "gallery_cleared" in p.flags():
                break
            p.face((10.0, 0.0, -43.75), tol=3)
            pr = p.prompt()
            if "rubble" in str(pr.get("text", "")).lower() and pr.get("action") == "attack":
                b.tap("LMB", 0.06)
                time.sleep(0.7)
            else:
                if p.nearby(lambda n: n.get("g") == "enemy" and n.get("hp", 1) > 0, 8):
                    p.fight(timeout=40)
                b.hold("W", 0.2)
                time.sleep(0.3)
        if "gallery_cleared" not in p.flags():
            raise StepFailed("gallery rubble not cleared")
        p.goto((12.5, -43.75), tol=1.0)
        p.goto((15.0, -43.5), tol=1.0)
        light_cp((13.2, -40.0))
        # authored standing spot in front of the key board (left end of the foreman's desk)
        for spot in [(18.35, -44.6), (18.3, -44.9), (18.5, -44.3)]:
            if p.inv("foreman_key") > 0:
                break
            p.goto(spot, tol=0.35, sprint=False)
            p.face((19.6, 1.5, -44.55), tol=3)
            b.hold("W", 0.1)          # a tiny step so Krystal herself turns toward the key board
            time.sleep(0.4)
            if p.prompt_matches(["Foreman's Key"]):
                b.tap("E")
                p.wait(lambda s: int(s.get("keys", {}).get("foreman_key", 0)) > 0, 3)
        if p.inv("foreman_key") < 1:
            desk = p.nearest(lambda n: "key" in n.get("text", "").lower(), 15)
            if desk:
                p.press_interact_on(desk, ["Foreman's Key"], lambda: p.inv("foreman_key") > 0, stop=1.4)
        note = p.nearest(lambda n: "read" in n.get("text", "").lower() or "note" in n.get("text", "").lower(), 10)
        if note:
            p.press_interact_on(note, ["Read", "note"], lambda: True, stop=1.4)
        return p.inv("foreman_key") > 0

    def deeper():
        p.goto((12.5, -43.75), tol=1.0)
        p.goto((0.0, -43.75), tol=1.0)
        below_walk([(0.0, 0.0, -49.0), (0.0, 0.0, -53.0)])
        gate = p.nearest(lambda n: "gate" in n.get("text", "").lower(), 10)
        if gate:
            p.press_interact_on(gate, ["Unlock", "gate"], lambda: "lower_gate_open" in p.flags(), stop=1.5)
        time.sleep(2.0)
        path = [(0.0, 0.0, -57.2), (0.0, 0.0, -59.3), (0.0, 0.0, -60.6), (0.0, -2.0, -65.4), (0.0, -2.0, -66.7),
                (1.3, -2.0, -66.7), (6.1, -4.0, -66.7), (7.4, -4.0, -66.7), (7.4, -4.0, -65.4), (7.4, -6.0, -60.6),
                (7.4, -6.0, -59.3), (10.0, -6.0, -59.3), (13.0, -6.0, -59.3), (27.0, -6.0, -59.3), (41.0, -6.0, -59.3),
                (44.2, -6.0, -59.3), (44.2, -6.0, -70.0), (44.2, -6.0, -77.5), (50.0, -6.0, -80.0), (54.0, -6.0, -85.75),
                (57.0, -6.0, -85.75)]
        below_walk(path)
        light_cp((60.0, -82.75))
        below_walk([(63.0, -6.0, -85.75), (66.0, -6.0, -85.75), (78.0, -10.0, -85.75), (81.0, -10.0, -85.75)])
        return "reached_silk_hollows" in p.flags() or p.wait(lambda s: "reached_silk_hollows" in s.get("flags", []), 5) is not None

    def silk():
        below_walk([(99.0, -10.0, -85.75), (105.0, -10.0, -86.0), (105.0, -10.0, -95.0), (105.0, -10.0, -109.0), (105.0, -10.0, -114.0)])
        light_cp((100.9, -115.5))
        # heal up before the boss
        while p.hp() < 70 and p.eat_best():
            time.sleep(0.5)
        return boss_fight()

    # ---- the reworked Weaver Matron (MP 8) --------------------------------------------------------
    def boss_now():
        s = p.st()
        bs = s.get("boss")
        if bs and "weaver" in (bs.get("id", "") + bs.get("name", "")).lower():
            return bs
        e = p.nearest(lambda n: n.get("g") == "enemy" and n.get("name") == "WeaverBoss", 60)
        return e

    def braziers():
        out = []
        for i, bz in enumerate(BRAZIERS):
            e = p.nearest(lambda n: "brazier" in n.get("text", "").lower() and dist2(xz(n["pos"]), bz) < 2.5, 60)
            out.append((i, e))
        return out

    def arena_ok(pt, me=None):
        """A floor spot we may move to: inside the arena, off the cocoon, off the braziers."""
        if dist2(pt, ARENA_C) > ARENA_R - 1.6 or dist2(pt, ARENA_C) < 2.6:
            return False
        return all(dist2(pt, bz) > 1.4 for bz in BRAZIERS)

    def move_keys(vec):
        """Camera-relative movement keys (W/A/S/D, diagonals allowed) that push Krystal along world xz `vec`
        without turning the camera (turning first would waste the telegraph)."""
        yaw = math.radians(b.cam_yaw() or 0.0)
        fwd = (-math.sin(yaw), -math.cos(yaw))
        right = (math.cos(yaw), -math.sin(yaw))
        n = math.hypot(vec[0], vec[1]) or 1.0
        cf = (vec[0] * fwd[0] + vec[1] * fwd[1]) / n
        cr = (vec[0] * right[0] + vec[1] * right[1]) / n
        keys = []
        if cf > 0.38:
            keys.append("W")
        elif cf < -0.38:
            keys.append("S")
        if cr > 0.38:
            keys.append("D")
        elif cr < -0.38:
            keys.append("A")
        return keys or ["W"]

    def crosses_cocoon(a, c, r=1.9):
        dx, dz = c[0] - a[0], c[1] - a[1]
        L2 = dx * dx + dz * dz
        if L2 < 0.01:
            return False
        t = max(0.0, min(1.0, ((ARENA_C[0] - a[0]) * dx + (ARENA_C[1] - a[1]) * dz) / L2))
        return math.hypot(a[0] + dx * t - ARENA_C[0], a[1] + dz * t - ARENA_C[1]) < r

    def escape(mark, reason, clear=3.7, away_from=None, max_time=1.5):
        """Get `clear` metres away from `mark` (the drop / pounce lands where Krystal stood when its mark
        appeared) - or, for a fan, sideways out of the wedge from `away_from` (the boss) - by holding
        camera-relative keys with sprint and one dodge roll (i-frames) at the start."""
        me = xz(p.pos())
        if away_from is None and dist2(me, mark) >= clear:
            return False
        best, best_sc = None, -1e9
        for k in range(16):
            ang = k * math.pi / 8.0
            if away_from is not None:
                # sideways from the boss->Krystal line
                bx, bz = me[0] - away_from[0], me[1] - away_from[1]
                bn = math.hypot(bx, bz) or 1.0
                perp = (-bz / bn, bx / bn)
                if k % 8 not in (0,):
                    continue
                sgn = 1.0 if k == 0 else -1.0
                pt = (me[0] + perp[0] * sgn * clear, me[1] + perp[1] * sgn * clear)
            else:
                pt = (mark[0] + math.cos(ang) * (clear + 0.8), mark[1] + math.sin(ang) * (clear + 0.8))
            sc = -dist2(pt, me)                               # the nearest safe spot
            if not arena_ok(pt):
                sc -= 60.0
            if crosses_cocoon(me, pt):
                sc -= 30.0
            sc -= 0.4 * abs(dist2(pt, ARENA_C) - 6.5)
            if sc > best_sc:
                best, best_sc = pt, sc
        vec = (best[0] - me[0], best[1] - me[1])
        keys = move_keys(vec)
        p.notes.setdefault("dodges", {}).setdefault(reason, 0)
        p.notes["dodges"][reason] += 1
        for k in keys:
            b.down(k)
        b.down("SHIFT")
        t0 = time.time()
        rolled = False
        try:
            while time.time() - t0 < max_time:
                if not rolled and time.time() - t0 > 0.04:
                    b.tap("CTRL", 0.04)
                    rolled = True
                time.sleep(0.05)
                now = xz(p.pos())
                if away_from is None and dist2(now, mark) >= clear:
                    break
                if away_from is not None and dist2(now, me) >= clear:
                    break
                if dist2(now, best) < 0.6:
                    break
        finally:
            b.up("SHIFT")
            for k in keys:
                b.up(k)
        return True

    def arena_goto(target, tol=1.0, timeout=2.0, sprint=True):
        """Move inside the arena without walking into the Heartseed cocoon at its centre: when the straight
        line passes within 2.2 m of the centre, go round it by a waypoint on a 4.2 m circle first."""
        me = xz(p.pos())
        tx, tz = target[0], target[1]
        ax, az = me
        dx, dz = tx - ax, tz - az
        L2 = dx * dx + dz * dz
        if L2 > 0.01:
            t = max(0.0, min(1.0, ((ARENA_C[0] - ax) * dx + (ARENA_C[1] - az) * dz) / L2))
            cx, cz = ax + dx * t, az + dz * t
            if math.hypot(cx - ARENA_C[0], cz - ARENA_C[1]) < 2.2 and 0.05 < t < 0.95:
                a1 = math.atan2(az - ARENA_C[1], ax - ARENA_C[0])
                a2 = math.atan2(tz - ARENA_C[1], tx - ARENA_C[0])
                da = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
                mid = a1 + da / 2.0 if abs(da) > 0.2 else a1 + math.pi / 2.0
                wp = (ARENA_C[0] + math.cos(mid) * 4.2, ARENA_C[1] + math.sin(mid) * 4.2)
                p.goto(wp, tol=1.2, sprint=sprint, timeout=timeout)
        return p.goto((tx, tz), tol=tol, sprint=sprint, timeout=timeout)

    def strike(target_pos, max_time=1.6, reach=2.3):
        """Close in on target_pos and swing (the soft lock turns Krystal toward the nearest foe)."""
        t_end = time.time() + max_time
        while time.time() < t_end:
            me = p.pos()
            d = dist2(xz(target_pos), xz(me))
            if d > reach:
                arena_goto(xz(target_pos), tol=reach - 0.3, timeout=max(0.3, min(1.5, t_end - time.time() + 0.1)))
                continue
            p.face(target_pos, tol=12)
            fy = p.st().get("player", {}).get("facing_yaw")
            want = b.yaw_to(p.pos(), target_pos)
            if fy is None or abs((want - fy + 180.0) % 360.0 - 180.0) > 35.0:
                b.hold("W", 0.07)            # a tiny step turns Krystal's body (swings go where she faces)
            b.tap("LMB", 0.06)
            time.sleep(0.42)
            return True
        return False

    def ensure_lantern():
        if not p.st().get("player", {}).get("lantern"):
            b.tap("F")
            time.sleep(0.2)

    def enter_arena():
        p.log("entering the Heartseed Chamber")
        below_walk(ARENA_WAY, fight=False)

    def boss_fight():
        t0 = time.time()
        phases = set()
        lowest_hp = 100.0
        deaths = 0
        was_dead = False
        last_log = 0.0
        lit_once = set()
        mark = None
        fan_dodged = False
        phase_t = {}
        ensure_lantern()
        enter_arena()
        while time.time() - t0 < 600:
            s = p.st()
            if p.inv("heartseed") > 0:
                break
            mode = s.get("mode")
            if mode != "playing":
                if mode == "dead" and not was_dead:
                    deaths += 1
                    p.log(f"Krystal fell in the boss fight (death #{deaths})")
                was_dead = mode == "dead"
                time.sleep(0.3)
                continue
            if was_dead:
                was_dead = False
                time.sleep(1.5)
                while p.hp() < 70 and p.eat_best():
                    time.sleep(0.4)
                ensure_lantern()
                enter_arena()
                continue
            lowest_hp = min(lowest_hp, p.hp())
            if "weaver_defeated" in p.flags():
                seed = p.nearest(lambda n: "heartseed" in n.get("text", "").lower(), 40)
                if seed:
                    p.press_interact_on(seed, ["Heartseed", "Take"], lambda: p.inv("heartseed") > 0, stop=1.4)
                time.sleep(0.5)
                continue
            boss = boss_now()
            me = xz(p.pos())
            if not boss:
                if dist2(me, ARENA_C) > ARENA_R + 2:
                    enter_arena()
                time.sleep(0.2)
                continue
            bstate = boss.get("state", "")
            phase = int(boss.get("phase", 1) or 1)
            phases.add(phase)
            phase_t.setdefault(phase, time.time())
            in_phase = time.time() - phase_t[phase]
            bpos = boss.get("pos")
            if time.time() - last_log > 5.0:
                last_log = time.time()
                p.log(f"boss: state={bstate} phase={phase} hp={boss.get('hp')} me={me} hp_me={p.hp()} lantern={s.get('player', {}).get('lantern')}")
            if dist2(me, ARENA_C) > ARENA_R + 2.5:
                enter_arena()
                continue
            ensure_lantern()
            # heal between openings (never while a mark is on the floor)
            if p.hp() < 40 and bstate in ("cling", "recover", "climb", "reposition", "phase_shriek", "release"):
                p.eat_best()
                continue
            # 1) the drop / pounce mark (where Krystal stood when it appeared): get clear of it, once
            if bstate in ("telegraph", "drop"):
                if mark is None:
                    mark = me
                    p.notes["drops_seen"] = p.notes.get("drops_seen", 0) + 1
                if not escape(mark, "drop"):
                    if bpos:
                        p.face(bpos, tol=20)
                    time.sleep(0.05)
                continue
            mark = None
            # 2) a web fan wedge aimed at Krystal: step sideways out of it (once per wedge)
            if bstate == "fan_tele":
                if not fan_dodged and bpos:
                    escape(me, "fan", clear=3.0, away_from=xz(bpos), max_time=0.9)
                    fan_dodged = True
                time.sleep(0.05)
                continue
            fan_dodged = False
            # 3) an opening (stuck / scorched / snapped): strike
            if boss.get("vuln") or bstate in ("stuck", "scorched"):
                strike(bpos, max_time=1.2, reach=2.4)
                continue
            # 4) channel (phase 3): bring the lit lantern to the brazier it smothers (or strike its thread's knot)
            if bstate == "channel":
                th = p.nearest(lambda n: n.get("g") == "enemy" and n.get("kind") == "thread", 40)
                tgt = None
                if th:
                    tgt = min(BRAZIERS, key=lambda bz: dist2(bz, xz(th["pos"])))
                else:
                    lit = [(i, e) for i, e in braziers() if e and ("burns" in e.get("text", "").lower() or "heat" in e.get("text", "").lower() or "stoke" in e.get("text", "").lower())]
                    if lit:
                        tgt = max((BRAZIERS[i] for i, _ in lit), key=lambda bz: dist2(bz, me))
                if tgt:
                    p.notes["channels_seen"] = p.notes.get("channels_seen", 0) + 1
                    arena_goto(tgt, tol=2.2, timeout=3.0)
                    if th and th.get("dist", 99) < 2.6:
                        strike(th["pos"], max_time=0.6, reach=2.5)
                continue
            # 5) minions / shaking sacs close by
            skit = p.live_enemies(lambda n: n.get("name") != "WeaverBoss" and n.get("kind") not in ("trip", "thread")
                                  and (n.get("threat") or n.get("kind") == "sac"), 5.0)
            if skit:
                p.notes["minion_hits"] = p.notes.get("minion_hits", 0) + 1
                strike(skit[0]["pos"], max_time=0.8, reach=2.2)
                continue
            # 6) a trip-line right in our way: cut it
            trip = p.nearest(lambda n: n.get("g") == "enemy" and n.get("kind") == "trip", 2.0)
            if trip:
                strike(trip["pos"], max_time=0.5, reach=2.0)
                continue
            # 7) braziers: one per phase (phases 1-2), and in phase 3 every one that can be lit or stoked
            bz = braziers()
            lit_n = sum(1 for _, e in bz if e and not e.get("text", "").lower().startswith("light the brazier")
                        and "smoulder" not in e.get("text", "").lower())
            usable = [(i, e) for i, e in bz if e and e.get("enabled", True) and
                      (e.get("text", "").lower().startswith("light the brazier") or e.get("text", "").lower().startswith("stoke"))]
            if matron_style == "fast":
                want = (phase == 1 and lit_n < 1) or (phase == 2 and lit_n < 2) or phase >= 3
            else:
                want = ((phase == 1 and lit_n < 1)
                        or (phase == 2 and lit_n < 2 and (in_phase > 100 or (p.hp() < 45 and p.inv("berry_snack") == 0)))
                        or (phase >= 3 and (in_phase > 7 or p.notes.get("channels_seen", 0) > 0)))
            if usable and want and bstate in BOSS_CEILING:
                i, e = min(usable, key=lambda ie: dist2(xz(ie[1]["pos"]), me))
                bp = xz(e["pos"])
                d_b = dist2(bp, me)
                if d_b > 1.9:
                    k = (d_b - 1.5) / d_b
                    arena_goto((me[0] + (bp[0] - me[0]) * k, me[1] + (bp[1] - me[1]) * k), tol=0.6, timeout=3.0)
                p.face(e["pos"], tol=6, turn_body=True)
                time.sleep(0.15)
                if p.prompt_matches(["Light the brazier", "Stoke the brazier"]):
                    b.tap("E")
                    lit_once.add(i)
                    p.notes.setdefault("brazier_uses", []).append({"brazier": i, "phase": phase, "text": e.get("text")})
                    # stay close while it kindles (1.5 s / 1.0 s) unless a mark appears
                    t_k = time.time()
                    while time.time() - t_k < 1.7:
                        bb = boss_now() or {}
                        if bb.get("state") == "telegraph":
                            break
                        time.sleep(0.1)
                continue
            # 8) nothing to do: wait on the middle ring, facing the boss
            if abs(dist2(me, ARENA_C) - 6.0) > 2.5:
                ang = math.atan2(me[1] - ARENA_C[1], me[0] - ARENA_C[0])
                spot = (ARENA_C[0] + math.cos(ang) * 6.0, ARENA_C[1] + math.sin(ang) * 6.0)
                arena_goto(spot, tol=1.0, sprint=False, timeout=1.5)
            elif bpos:
                p.face(bpos, tol=15)
            time.sleep(0.1)
        p.notes["boss"] = {"seconds": round(time.time() - t0, 1), "phases_seen": sorted(phases), "deaths": deaths,
                           "lowest_hp": lowest_hp, "braziers_used": sorted(lit_once),
                           "defeated": "weaver_defeated" in p.flags()}
        p.log(f"boss summary: {p.notes['boss']}")
        if 3 not in phases and "weaver_defeated" in p.flags():
            p.problem("Weaver Matron defeated without reaching phase 3", str(p.notes["boss"]), "major", "below")
        return p.inv("heartseed") > 0

    def return_home():
        # take the lift if available, else walk back
        lift = p.nearest(lambda n: "lift" in n.get("text", "").lower() or "ride" in n.get("text", "").lower(), 25)
        if lift:
            p.press_interact_on(lift, ["lift", "Ride"], lambda: p.pos()[2] > -20, stop=1.6)
            p.wait(lambda s: s.get("mode") == "playing" and s.get("player", {}).get("pos", [0, 0, -100])[2] > -20, 20)
        up = p.nearest(lambda n: "climb" in n.get("text", "").lower() or "surface" in n.get("text", "").lower(), 20)
        if not up:
            raise StepFailed("no way up found")
        p.press_interact_on(up, ["Climb", "surface"], lambda: p.st().get("area") == "surface", stop=1.5)
        p.wait(lambda s: s.get("area") == "surface" and s.get("mode") == "playing", 30)
        time.sleep(2)
        rev = PATHS["mine"][::-1]
        p.walk_route(rev)
        p.goto(HAVEN, tol=3)
        e = p.nearest(lambda n: n.get("name") == "WardStone")
        p.press_interact_on(e, ["Heartseed", "Return"], lambda: "ward_restored" in p.flags(), stop=2.2)
        return True

    def ending():
        # restoration cutscene + ending/credits
        time.sleep(12)
        p.shot("restoration")
        for _ in range(90):
            if p.find_btn("Continue exploring") or p.find_btn("Continue"):
                break
            time.sleep(1)
        p.shot("ending_credits")
        p.click("Continue exploring", timeout=3) or p.click("Continue", timeout=3)
        ok = p.wait(lambda s: s.get("mode") == "playing" and not s.get("ui_stack"), 30)
        time.sleep(2)
        if "chapter_one_complete" not in p.flags():
            p.problem("chapter_one_complete not set after the Chapter One ending", f"flags={sorted(p.flags())}", "blocker", "surface")
        return ok is not None and "chapter_one_complete" in p.flags()

    def accept_ch2():
        """Free play: read the Ward Stone's new inscription and ACCEPT it through the choice UI (ch2_light_beyond)."""
        e = p.nearest(lambda n: n.get("name") == "WardStone", 40)
        if not e:
            p.goto(HAVEN, tol=3)
            e = p.nearest(lambda n: n.get("name") == "WardStone", 40)
        if not e:
            raise StepFailed("no Ward Stone")
        opened = p.press_interact_on(e, ["Ward Stone", "Read"], lambda: any(x.get("text") == "Follow the lantern road" for x in p.st().get("buttons", [])), stop=2.2)
        if not opened:
            raise StepFailed(f"the Ward Stone offered no choice (buttons {[x['text'] for x in b.buttons()][:12]}, flags {sorted(p.flags())})")
        p.shot("ward_stone_choice")
        if not p.click("Follow the lantern road", exact=True):
            raise StepFailed("could not click 'Follow the lantern road'")
        ok = p.wait(lambda s: "ch2_accepted" in s.get("flags", []), 6) is not None
        time.sleep(3.0)
        c2 = p.st().get("chapter2", {}) or {}
        p.notes["chapter2_after_accept"] = {"current": c2.get("current"), "done": c2.get("done"), "tracker": p.st().get("tracker")}
        if ok and "ch2_light_beyond" not in (c2.get("done") or []):
            # the step may complete on the next evaluation: give it a moment before calling it a problem
            if not p.wait(lambda s: "ch2_light_beyond" in ((s.get("chapter2") or {}).get("done") or []), 5):
                p.problem("Accepting the Ward Stone did not complete ch2_light_beyond", str(c2), "major", "surface")
        return ok

    def free_play_save():
        # continue playing a moment, then save from the pause menu - and PROVE the save happened
        b.hold("W", 1.0)
        return p.pause_save()

    p.boss_fight = boss_fight           # diagnostic fixtures call the Matron routine directly
    p.light_cp = light_cp
    return [("title_new_game", title_new_game), ("read_ward", read_ward), ("gather_basics", gather_basics),
            ("craft_axe", craft_axe), ("chop", chop), ("workbench", workbench), ("tailor_cache", tailor_cache),
            ("mochi", mochi), ("pebble", pebble), ("home", home), ("lumi", lumi), ("prepare", prepare),
            ("brave_steps", brave_steps), ("descend", descend), ("old_mine", old_mine), ("deeper", deeper), ("silk_and_boss", silk),
            ("return_home", return_home), ("ending", ending), ("accept_ch2", accept_ch2),
            ("free_play_save", free_play_save)]


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=str(ROOT / "builds" / "Hollowhaven" / "Hollowhaven.exe"))
    ap.add_argument("--out", default=str(ROOT / "qa" / "tmp" / "e2e" / "run"))
    ap.add_argument("--save-dir", default="")
    ap.add_argument("--name", default="play")
    ap.add_argument("--until", default="")
    ap.add_argument("--continue-save", action="store_true")
    ap.add_argument("--from-step", default="", help="with --continue-save: skip to this step after the title")
    ap.add_argument("--keep-open", action="store_true")
    ap.add_argument("--dev", action="store_true", help="run the project with the editor binary (for developing the bot)")
    ap.add_argument("--outfit", default=DEFAULT_OUTFIT, help="starter outfit picked on Meet Krystal ('' = keep)")
    ap.add_argument("--hair", default=DEFAULT_HAIR, help="hairstyle picked on Meet Krystal ('' = keep)")
    ap.add_argument("--budget", type=float, default=None, help="stop starting new steps after this many seconds")
    ap.add_argument("--checkpoint-saves", action="store_true",
                    help="save through the pause menu after every surface step (headless has no quiet autosave)")
    ap.add_argument("--matron-style", default="thorough", choices=["thorough", "fast"],
                    help="thorough: exercise phase 2/3 mechanics (default); fast: a brazier per phase")
    add_transport_args(ap)
    a = ap.parse_args()
    r = run(a)
    print(json.dumps(r, indent=1))
