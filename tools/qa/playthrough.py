"""Full Chapter One playthrough of the PACKAGED game with real OS input.

Every action is a real keyboard/mouse event sent to the game window (SendInput). The bot perceives the
game through the read-only QA telemetry (what's nearby, the on-screen prompt, objectives, button rects)
and screenshots. It never grants items, teleports, or sets flags.

Usage:
  python tools/qa/playthrough.py --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/run1 [--until STEP]
  python tools/qa/playthrough.py --continue-save ...   (start from the title's Continue instead of New Game)
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hhbot import mouse_move, mouse_wheel  # noqa: E402
from session import Session  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

# Surface paths (from game/src/world/surface/surface_layout.gd PATHS), Haven-first order.
PATHS = {
    "glade": [(-9, 2), (-19, 5), (-31, 9), (-42, 12), (-49, 12)],
    "ruin": [(-2, -13), (-4, -25), (-7, -39), (-10, -51), (-12, -58)],
    "mine": [(6, -12), (14, -22), (22, -30), (30, -40), (38, -50), (44, -58), (48, -63)],
    "quarry": [(11, -3), (17, -4.5), (21, -5), (28, -6), (40, -9), (51, -11), (58, -12)],
}
HAVEN = (0.0, 4.0)


def xz(p):
    return (p[0], p[2]) if len(p) == 3 else (p[0], p[1])


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


class StepFailed(Exception):
    pass


class Play:
    def __init__(self, sess: Session):
        self.s = sess
        self.bot = sess.bot
        self.log = self.bot.log
        self.t0 = time.time()

    # ------------------------------------------------------------------ state helpers
    def st(self):
        return self.bot.state()

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
        return self.s.shot(label)

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
            self.log(f"interact attempt {attempt + 1} on {e.get('name')} prompt={self.prompt()}")
            stop = max(0.8, stop - 0.2)
        return False

    def gather_hand(self, label_words, item, want, maxd=60.0):
        """Pick up hand-gatherables (sticks, stones, grass, berries) until inventory has `want` of item."""
        guard = 0
        while self.inv(item) < want and guard < 40:
            guard += 1
            e = self.nearest(lambda n: n.get("tool") == "hand" and n.get("enabled", True) and "regrow" not in n.get("text", "").lower()
                             and any(w.lower() in (n.get("label", "") + n.get("text", "")).lower() for w in label_words), maxd)
            if not e:
                raise StepFailed(f"no {label_words} nearby")
            before = self.inv(item)
            ok = self.press_interact_on(e, label_words, lambda: self.inv(item) > before or not self._still_there(e))
            if not ok:
                self.log(f"could not gather {e}")
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

    def click_scrolled(self, prefix, timeout=6.0):
        """Click a (possibly scrolled-out) list button whose text starts with prefix."""
        t0 = time.time()
        while time.time() - t0 < timeout:
            bs = [b for b in self.bot.buttons() if b["text"].lower().startswith(prefix.lower())]
            if bs:
                b = bs[0]
                if not b.get("clipped"):
                    x, y, w, h = b["rect"]
                    self.bot.win.click(x + w // 2, y + h // 2)
                    time.sleep(0.3)
                    return True
                # scroll the list: hover the list area and wheel down/up
                x, y, w, h = b["rect"]
                win_h = self.st().get("window", [1600, 900])[1]
                cx, cy, _, _ = self.bot.win.client_rect()
                import ctypes
                ctypes.windll.user32.SetCursorPos(int(cx + x + w // 2), int(cy + min(max(y, 250), win_h - 250)))
                mouse_wheel(-120 if y > win_h / 2 else 120)
                time.sleep(0.25)
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

    def craft(self, recipe_name, times=1, station_tab=None) -> bool:
        self.log(f"craft {recipe_name} x{times}")
        if station_tab:
            self.goto_station(station_tab)
        if not self.open_panel("C", "crafting"):
            raise StepFailed("crafting panel did not open")
        time.sleep(0.4)
        if station_tab:
            self.click(station_tab, exact=True)
        if not self.click_scrolled(recipe_name + " |") and not self.click_scrolled(recipe_name):
            self.close_panels()
            return False
        res = self.st().get("inv", {})
        for _ in range(times):
            if not self.click("Craft", exact=True):
                cb = [b for b in self.bot.buttons() if b["text"] == "Craft"]
                self.log(f"Craft button unavailable (disabled={cb[0]['disabled'] if cb else 'missing'}); inv={self.st().get('inv')}")
                break
            time.sleep(0.35)
        time.sleep(0.3)
        self.shot(f"craft_{recipe_name.replace(' ', '_')}")
        self.close_panels()
        return True

    def slot_rect(self, item):
        for b in self.bot.buttons():
            if b["text"].startswith("slot:bag:") and b.get("item") == item and not b.get("clipped"):
                return b["rect"]
        return None

    def eat_best(self):
        for food in ("hearty_stew", "glowcap_skewer", "berry_snack", "sweetroot", "berries"):
            if self.inv(food) > 0:
                if not self.open_panel("TAB", "inventory"):
                    return False
                time.sleep(0.4)
                r = self.slot_rect(food)
                if r:
                    x, y, w, h = r
                    self.bot.win.click(x + w // 2, y + h // 2)
                    time.sleep(0.08)
                    self.bot.win.click(x + w // 2, y + h // 2)
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
            mouse_wheel(-120)
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
            # adjust: turn a bit and look a bit lower/higher
            mouse_move(int(40 * self.bot.px_per_deg / 8), 0)
            if k % 3 == 2:
                self.bot.hold("S", 0.3)
            time.sleep(0.4)
        self.shot(f"placed_{item}")
        if self.st().get("build", {}).get("active"):
            self.bot.tap("B")
            time.sleep(0.4)
        return placed

    # ------------------------------------------------------------------ combat
    def fight(self, pred=None, timeout=90.0, flee_hp=35.0) -> bool:
        """Fight nearby threatening enemies with real inputs until none remain."""
        t0 = time.time()
        last_seen = time.time()
        while time.time() - t0 < timeout:
            enemies = self.nearby(lambda n: n.get("g") == "enemy" and (pred is None or pred(n)), 30)
            live = [e for e in enemies if e.get("hp", 1) > 0 and e.get("state") not in ("dead", "dying")]
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
    exe = str(Path(args.exe).resolve())
    save_dir = Path(args.save_dir) if args.save_dir else out / "saves"
    pre = ["--path", str(ROOT / "game")] if args.dev else []
    sess = Session(exe, out, save_dir, args.name, extra=["--windowed"], pre_args=pre)
    bot = sess.start(wait_for=lambda s: s.get("mode") == "title" and len(s.get("buttons", [])) > 0, timeout=60)
    play = Play(sess)
    results = []

    def check(name, fn, *a, **kw):
        t = time.time()
        sess.bot.log(f"=== STEP {name} (quest step {play.step()}) ===")
        try:
            ok = fn(*a, **kw)
            ok = True if ok is None else bool(ok)
        except StepFailed as ex:
            ok = False
            sess.bot.log(f"StepFailed: {ex}")
        except Exception as ex:  # noqa: BLE001
            ok = False
            sess.bot.log(f"EXCEPTION {type(ex).__name__}: {ex}")
        ev = play.shot(name)
        dur = time.time() - t
        results.append({"step": name, "ok": ok, "seconds": round(dur, 1), "quest": play.step(), "evidence": ev})
        sess.record(f"playthrough:{name}", "interactive", f"real-input scenario step {name}", "step completes",
                    f"quest step now {play.step()}; ok={ok}; {dur:.0f}s", "PASS" if ok else "FAIL", [ev])
        if not ok:
            raise StepFailed(name)
        # snapshot the save folder after each passed step (lets QA resume a scenario via Continue)
        try:
            import shutil
            if save_dir.exists() and any(save_dir.iterdir()):
                dst = out / "checkpoints" / name
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(save_dir, dst)
        except Exception as ex:  # noqa: BLE001
            sess.bot.log(f"checkpoint copy failed: {ex}")

    steps = build_steps(play, args)
    started = not args.from_step
    try:
        for name, fn in steps:
            if args.until and name == args.until:
                break
            if not started and name != "title_new_game":
                if name == args.from_step:
                    started = True
                else:
                    continue
            check(name, fn)
    except StepFailed as ex:
        sess.bot.log(f"PLAYTHROUGH STOPPED at {ex}")
    finally:
        (out / f"{args.name}_summary.json").write_text(json.dumps({"results": results, "final_state": {k: play.st().get(k) for k in ("step", "area", "inv", "keys", "flags", "companions")}}, indent=2))
        if not args.keep_open:
            sess.stop()
    return results


def build_steps(p: Play, args):
    b = p.bot

    def title_new_game():
        if args.continue_save:
            if not p.click("Continue"):
                raise StepFailed("no Continue button")
        else:
            p.click("New Game", exact=True)
            time.sleep(1.0)
            if p.click("Start a new journey", timeout=2.0):   # overwrite confirmation (if a save exists)
                time.sleep(0.8)
            if not p.click("Begin the journey", timeout=6.0):
                raise StepFailed("comfort screen missing")
        if not p.wait(lambda s: s.get("mode") == "playing" and s.get("area") in ("surface", "below"), 40):
            raise StepFailed("never reached gameplay")
        time.sleep(2.5)
        b.calibrate_look()
        return True

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
        p.craft("Stone Axe")
        return p.inv("stone_axe") >= 1

    def chop():
        p.harvest_tool(["Oak", "Tree", "Pine", "Birch", "Blossom"], "wood", 22, maxd=60)
        return p.wait(lambda s: s.get("step") != "chop", 6) is not None or p.inv("wood") >= 10

    def workbench():
        p.goto(HAVEN, tol=2.5)
        if p.inv("workbench") < 1:
            p.craft("Workbench")
        return p.place("workbench", near=(-6.0, 3.0)) and bool(p.wait(lambda s: s.get("step") != "workbench", 5))

    def mochi():
        p.travel("glade")
        # berries: gather until we have plenty (3 for Mochi, 8 for snacks, spare)
        p.gather_hand(["Berr"], "berries", 14, maxd=45)
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
            p.craft("Stone Pickaxe")
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
        p.craft("Cozy Bed", station_tab="Workbench")
        p.craft("Crop Plot")
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
            p.craft("Copper Sword", station_tab="Workbench")
        if p.inv("lantern") < 1:
            p.craft("Lantern", station_tab="Workbench")
        if p.inv("berry_snack") < 2 and p.inv("berries") >= 8:
            p.craft("Berry Snack", times=2)
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
            p.craft("Lantern", station_tab="Workbench")
        if p.inv("berry_snack") + p.inv("hearty_stew") < 2:
            if p.inv("berries") < 8:
                raise StepFailed("not enough berries for snacks")
            p.craft("Berry Snack", times=2)
        return p.wait(lambda s: s.get("step") == "descend", 8) is not None

    def descend():
        p.travel("mine")
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
            if fight and p.nearby(lambda n: n.get("g") == "enemy" and n.get("hp", 1) > 0 and n.get("state") not in ("dead", "dying"), 11):
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
        below_walk([(105.0, -10.0, -119.0), (105.0, -12.0, -125.0), (105.0, -12.0, -131.0)], fight=False)
        return boss_fight()

    BRAZIERS = [(111.1, -12.0, -134.0), (98.9, -12.0, -134.0), (105.0, -12.0, -144.5)]

    def boss_fight():
        t0 = time.time()
        lit = set()
        while time.time() - t0 < 360:
            if p.inv("heartseed") > 0:
                return True
            if "weaver_defeated" in p.flags():
                seed = p.nearest(lambda n: "heartseed" in n.get("text", "").lower(), 30)
                if seed:
                    p.press_interact_on(seed, ["Heartseed", "Take"], lambda: p.inv("heartseed") > 0, stop=1.4)
                time.sleep(1)
                continue
            if p.hp() < 45 and (not boss or boss.get("state") not in ("telegraph", "drop")):
                p.eat_best()
            boss = p.nearest(lambda n: n.get("g") == "enemy" and "boss" in (n.get("name", "") + n.get("state", "")).lower() or n.get("g") == "enemy" and n.get("hp", 0) > 60, 40)
            bstate = (boss or {}).get("state", "")
            me = p.pos()
            if (not boss or bstate == "dormant") and dist2(xz(me), (105.0, -137.5)) > 9.0:
                # after a respawn at the arena lantern: walk back down into the chamber to resume the fight
                p.log("re-entering the Heartseed Chamber")
                below_walk([(105.0, -10.0, -119.0), (105.0, -12.0, -125.0), (105.0, -12.0, -133.0)], fight=False)
                continue
            # the drop is aimed at where Krystal stands when the shadow appears: sprint sideways out of it
            if boss and bstate == "telegraph":
                side = "D" if int(time.time() * 10) % 2 else "A"
                b.win.focus()
                b.down(side)
                b.down("SHIFT")
                time.sleep(0.75)
                b.tap("CTRL")
                b.up("SHIFT")
                b.up(side)
                time.sleep(0.2)
                continue
            if boss and bstate in ("stunned", "stuck", "scorched", "fallen", "vulnerable") and boss["dist"] < 12:
                p.face(boss["pos"], tol=8)
                if boss["dist"] > 2.2:
                    b.hold("W", 0.35)
                b.tap("LMB", 0.06)
                time.sleep(0.4)
                continue
            # otherwise light the next unlit brazier
            target = None
            for i, bz in enumerate(BRAZIERS):
                if i in lit:
                    continue
                e = p.nearest(lambda n: "brazier" in n.get("text", "").lower() and dist2(xz(n["pos"]), (bz[0], bz[2])) < 2.5, 40)
                if e and "burns" in e.get("text", "").lower():
                    lit.add(i)
                    continue
                target = (i, e)
                break
            if target and target[1]:
                i, e = target
                p.approach(e, stop=1.6)
                if p.prompt_matches(["Light the brazier"]):
                    b.tap("E")
                    time.sleep(2.0)
            else:
                time.sleep(0.3)
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
        for _ in range(60):
            if p.find_btn("Continue exploring") or p.find_btn("Continue"):
                break
            time.sleep(1)
        p.shot("ending_credits")
        p.click("Continue exploring", timeout=3) or p.click("Continue", timeout=3)
        ok = p.wait(lambda s: s.get("mode") == "playing" and s.get("step") in ("free_play", ""), 20)
        time.sleep(2)
        return ok is not None and "chapter_one_complete" in p.flags()

    def free_play_save():
        # continue playing a moment, then save from the pause menu
        b.hold("W", 1.0)
        p.bot.tap("ESC")
        time.sleep(0.8)
        p.click("Save Game", timeout=3)
        time.sleep(1.5)
        p.close_panels()
        return True

    return [("title_new_game", title_new_game), ("read_ward", read_ward), ("gather_basics", gather_basics),
            ("craft_axe", craft_axe), ("chop", chop), ("workbench", workbench), ("mochi", mochi), ("pebble", pebble),
            ("home", home), ("lumi", lumi), ("prepare", prepare), ("descend", descend), ("old_mine", old_mine),
            ("deeper", deeper), ("silk_and_boss", silk), ("return_home", return_home), ("ending", ending),
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
    a = ap.parse_args()
    r = run(a)
    print(json.dumps(r, indent=1))
