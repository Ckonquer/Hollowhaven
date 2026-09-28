"""cov_equip_companions - MP 20.4 "Run C" (combat / companion regression) coverage bot. HEADLESS ONLY.

What it exercises (real play through the virtual keyboard / mouse, read-only QA telemetry in):
  A  equipment: a full backpack refuses a ground pickup; armor + charm worn through the Backpack UI (click a
     backpack slot, then click the equipment slot; the charm through the detail card's "Equip" button); the
     Sparkseed Wand moved onto the hotbar in the UI and cast (per-spark stamina cost / damage / one hit per spark);
     damage taken from the SAME enemy type (surface Brambling, 10 raw) with no armor, the Padded set and the
     Copperwood set; take-off refused with a full backpack (nothing lost), swaps padded -> copperwood in place.
     No pet: Lumi is sent home first, so the whole block is also the "no pet" regression.
  B  Lumi: measured walking speed (distance over time on the same straight Haven path) with no pet, Lumi's passive
     and Lumi + Glimmerstep (key T), T refused while recharging, Light Bolt damage on a Brambling.
  C  Pebble: damage taken with Pebble's passive (x armor), Stoneheart shield absorbing hits, Stone Bump damage,
     autocast and key T sharing ONE cooldown, cooldown survives a pause-menu save + quit + relaunch + Continue.
  D  Mochi: Spore Puff damage, Bloomguard heal total (autocast in a fight: sum of the heal ticks; manual T out of
     combat), Mochi's healing passive on food.
  E  Mochi's courage: Mochi refuses the Hollow Mine without courage (stays on the surface), the Comfort Ribbon is
     tied in the Friends panel, "Rest by the lantern with Mochi" at the courage lantern, Mochi then follows into
     the Below.
  F  take-off WITH room in the backpack (click the worn charm), then wear it again with the Equip button.
  Companion toggles ("Attacks on its own", "Uses its skill on its own") are clicked in the Friends panel only out
  of enemy reach: the panel closes itself as soon as Krystal is hurt.

START STATE (DIAGNOSTIC, labelled): a COPY of the NATURAL chain save qa/tmp/bot/chain/run3/checkpoints/END_end/
slot1.json (Chapter Two finished by the natural route; all three friends befriended; 27/32 backpack slots used)
with injected items - the natural save owns no armor, charm, wand or ribbon, and none can be crafted from it (no
loom / furnace / glowcap / copper bars). Injected: padded_hood, padded_vest, padded_boots, sparkseed_wand,
gatherers_charm into the 5 empty backpack slots (backpack becomes 32/32 FULL), and copperwood_hood / _vest / _boots
+ comfort_ribbon as persistent ground pickups (GameState.dropped entries) on the way to the Thornthicket. The
injection is written to <out>/injection.json. Nothing else is changed; no debug flags, no teleports, no cheats.

Phases run in ONE game process per --phases group; every phase boundary that sleeps in the Haven bed (full heal,
morning, the game's own save) copies the save folder to <out>/checkpoints/<phase>/, and --start-save resumes
from such a folder (still the same diagnostic lineage).

Launch: .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --max-fps 60 -- --qa-input-port=
<8100 + attempt> --qa-no-focus --qa-telemetry=<out>/<name>_telemetry.jsonl --save-dir=<out>/saves --settings-file=
<out>/settings.cfg --no-focus-pause --max-seconds=N. Kills only the process tree it started.

  python tools/qa/ch2/cov_equip_companions.py --out qa/tmp/bot/cov_equip_companions/run1 --phases A,B,C,D,E --attempt 5
  python tools/qa/ch2/cov_equip_companions.py --out <dir> --phases C --attempt 9       --start-save qa/tmp/bot/cov_equip_companions/run1/checkpoints/B_end
Ports: 8100 + --attempt (0..19); phase C's relaunch uses attempt + 1.
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
QA_DIR = HERE.parent
ROOT = QA_DIR.parents[1]
for _p in (str(HERE), str(QA_DIR)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import s4_common as S4  # noqa: E402
from hhbot import Bot, Telemetry, angle_diff  # noqa: E402

BASE_SAVE = ROOT / "qa" / "tmp" / "bot" / "chain" / "run3" / "checkpoints" / "END_end" / "slot1.json"
PORT_BASE = 8100
INJECT_BAG = ["padded_hood", "padded_vest", "padded_boots", "sparkseed_wand", "gatherers_charm"]
DROP_SPOT = (-47.0, -35.0)          # ground pickups: 18 m from the thicket spawner (outside its aggro)
INJECT_DROPS = [("copperwood_hood", (-47.0, -35.0)), ("copperwood_vest", (-46.2, -35.6)),
                ("copperwood_boots", (-47.8, -35.6)), ("comfort_ribbon", (-47.0, -36.3))]
HAVEN = (0.0, 4.0)
THICKET = (-62.0, -46.0)
QUARRY_BR = (77.0, 3.0)
BRAMBLEBACKS = (-75.0, -67.0)
BED = (-9.5, -5.0)
PATH_OLD_OAK = [(-8, -9), (-17, -13), (-25, -17), (-29, -19)]
PATH_THICKET = PATH_OLD_OAK + [(-38, -27), (-44, -32), DROP_SPOT]
PATH_QUARRY = [(11, -3), (17, -4.5), (21, -5), (28, -6), (40, -9), (51, -11), (58, -12), (66, -6)]
PATH_MINE = [(6, -12), (14, -22), (22, -30), (30, -40), (38, -50), (44, -58), (47, -62)]
MINE_THRESHOLD = (50.0, -66.0)
MINE_DOOR = (53.8, -73.7)
# speed test: a straight line south from the Haven along the meadow path
SPEED_START = (0.0, 9.0)
SPEED_DIR_TARGET = (-2.0, 45.0)
SPEED_SECONDS = 5.0
EQUIP_ORDER = ["head", "body", "boots", "charm"]
# documented numbers (data/equipment.gd, data/items.gd, data/companion_skills.gd, data/enemies.gd)
BRAMBLING_DMG = 10.0
PADDED = 0.06
COPPERWOOD = 0.12
WAND = {"damage": 9.0, "stamina": 8.0, "cooldown": 0.8}
WALK = 4.2
GEAR_MULT = 1.1                      # best owned weapon tier 2 (copper sword / wand)


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def write_json(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=1, default=str), encoding="utf-8")


def xz(p):
    return (p[0], p[2]) if len(p) >= 3 else (p[0], p[1])


def d2(a, b):
    a, b = xz(a), xz(b)
    return math.hypot(a[0] - b[0], a[1] - b[1])


def combine(*r):
    keep = 1.0
    for v in r:
        keep *= 1.0 - v
    return min(1.0 - keep, 0.45)


# ============================================================================================ save preparation
def prepare_save(save_dir: Path, out: Path, start_save: Path | None) -> dict:
    save_dir.mkdir(parents=True, exist_ok=True)
    for f in save_dir.glob("*"):
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f)
    if start_save is not None:
        src = start_save / "slot1.json" if start_save.is_dir() else start_save
        shutil.copyfile(src, save_dir / "slot1.json")
        bak = src.with_name("slot1.bak.json")
        if bak.exists():
            shutil.copyfile(bak, save_dir / "slot1.bak.json")
        return {"kind": "resume", "from": str(src)}
    d = json.loads(BASE_SAVE.read_text(encoding="utf-8"))
    st = d["state"]
    inv = st["inventory"]
    before = sum(1 for s in inv if s)
    free = [i for i, s in enumerate(inv) if not s]
    if len(free) < len(INJECT_BAG):
        raise RuntimeError(f"base save has only {len(free)} free slots")
    placed = []
    for item, i in zip(INJECT_BAG, free):
        inv[i] = {"count": 1, "id": item}
        placed.append({"slot": i, "item": item})
    uid = int(st.get("next_uid", 1))
    drops = []
    for item, (x, z) in INJECT_DROPS:
        rec = {"area": "surface", "count": 1, "item": item, "pos": [x, 0.0, z], "uid": f"d{uid}"}
        st["dropped"].append(rec)
        drops.append(rec)
        uid += 1
    st["next_uid"] = uid
    (save_dir / "slot1.json").write_text(json.dumps(d, indent="\t"), encoding="utf-8")
    info = {"kind": "DIAGNOSTIC: natural chain save + injected items", "base": str(BASE_SAVE),
            "base_bag_used": before, "bag_injected": placed, "drops_injected": drops,
            "bag_after": sum(1 for s in inv if s), "capacity": st["capacity"],
            "everything_else": "unchanged (flags, companions, bond, positions, time, stats)"}
    write_json(out / "injection.json", info)
    return info


# ============================================================================================ telemetry history
class Recorder:
    """Tails the telemetry file and keeps a compact record of EVERY line (hhbot.Telemetry keeps only the last)."""

    def __init__(self, path: Path):
        self.path = path
        self.pos = 0
        self.buf = ""
        self.recs: list[dict] = []
        self.msgs: list[dict] = []
        self._mseen: set = set()

    def poll(self):
        if not self.path.exists():
            return
        with open(self.path, "r", encoding="utf-8", errors="replace") as f:
            f.seek(self.pos)
            chunk = f.read()
            self.pos = f.tell()
        self.buf += chunk
        lines = self.buf.split("\n")
        self.buf = lines[-1]
        for ln in lines[:-1]:
            ln = ln.strip()
            if not ln:
                continue
            try:
                s = json.loads(ln)
            except json.JSONDecodeError:
                continue
            pl = s.get("player") or {}
            en = []
            for n in s.get("nearby") or []:
                if n.get("g") == "enemy":
                    en.append({"name": n.get("name"), "hp": n.get("hp"), "state": n.get("state"), "dist": n.get("dist"),
                               "pos": n.get("pos"), "threat": n.get("threat")})
            rec = {"t": s.get("t"), "seq": s.get("seq"), "mode": s.get("mode"), "area": s.get("area"),
                   "ui": s.get("ui_stack") or [], "paused": s.get("paused"), "hp": pl.get("hp"), "st": pl.get("stamina"),
                   "pos": pl.get("pos"), "vel": pl.get("vel"), "floor": pl.get("on_floor"), "yaw": pl.get("cam_yaw"),
                   "en": en, "cs": s.get("companion_skills") or {}, "cn": s.get("companion_nodes") or {},
                   "buffs": s.get("buffs") or {}, "eq": s.get("equipment") or {}, "hb": s.get("hotbar_index"),
                   "inv": s.get("inv") or {}, "flags_n": len(s.get("flags") or [])}
            self.recs.append(rec)
            for m in s.get("messages") or []:
                key = (m.get("k"), m.get("text"), m.get("t"))
                if key not in self._mseen:
                    self._mseen.add(key)
                    self.msgs.append(m)

    def last(self) -> dict:
        self.poll()
        return self.recs[-1] if self.recs else {}

    def t(self) -> float:
        r = self.last()
        return float(r.get("t") or 0.0)

    def window(self, t0: float, t1: float | None = None) -> list[dict]:
        self.poll()
        return [r for r in self.recs if r.get("t") is not None and r["t"] >= t0 and (t1 is None or r["t"] <= t1)]

    def hp_events(self, t0: float, t1: float | None = None) -> list[dict]:
        out = []
        prev = None
        for r in self.window(t0, t1):
            if r.get("mode") != "playing" or r.get("hp") is None:
                prev = None
                continue
            if prev is not None and prev.get("area") == r.get("area"):
                dv = round(float(r["hp"]) - float(prev["hp"]), 2)
                if abs(dv) >= 0.05:
                    act = [k for k, v in (r.get("cs") or {}).items() if v.get("active")]
                    out.append({"t": r["t"], "d": dv, "hp": r["hp"], "eq": dict(r.get("eq") or {}),
                                "companion": act[0] if act else "",
                                "near": sorted([(e.get("name"), e.get("state"), e.get("dist")) for e in r["en"] if (e.get("dist") or 99) < 4.0])})
            prev = r
        return out

    def stamina_drops(self, t0: float, t1: float | None = None) -> list[dict]:
        out = []
        prev = None
        for r in self.window(t0, t1):
            if prev is not None and r.get("st") is not None and prev.get("st") is not None:
                dv = round(float(r["st"]) - float(prev["st"]), 2)
                if dv <= -1.0:
                    out.append({"t": r["t"], "d": dv, "st": r["st"]})
            prev = r
        return out

    def enemy_hits(self, t0: float, t1: float | None = None) -> list[dict]:
        """Enemy hp decreases (per enemy name) between consecutive observations."""
        out = []
        last: dict = {}
        for r in self.window(t0, t1):
            for e in r["en"]:
                nm, hp = e.get("name"), e.get("hp")
                if hp is None:
                    continue
                if nm in last and hp < last[nm] - 0.05:
                    out.append({"t": r["t"], "enemy": nm, "d": round(last[nm] - hp, 2), "hp": hp, "state": e.get("state")})
                last[nm] = hp
        return out

    def kills(self, t0: float, t1: float | None = None) -> list[dict]:
        """Enemies that vanished from the (<= 80 m) nearby list within 16 m of Krystal right after being hit down
        to <= 9.5 hp (one spark / bump / puff from death), or that reported a 'dead' state."""
        win = self.window(t0, t1)
        if not win:
            return []
        t_end = win[-1]["t"]
        last: dict = {}
        for r in win:
            for e in r["en"]:
                last[e.get("name")] = (r["t"], e.get("hp"), e.get("dist"), e.get("state"))
        out = []
        for nm, (t, hp, dist, stt) in last.items():
            if stt == "dead" or (t < t_end - 1.0 and hp is not None and hp <= 9.5 and (dist or 99) < 16):
                out.append({"enemy": nm, "last_t": t, "last_hp": hp, "last_dist": dist, "state": stt})
        return out

    def messages(self, t0: float, kinds=None) -> list[dict]:
        self.poll()
        return [m for m in self.msgs if float(m.get("t", 0)) >= t0 and (kinds is None or m.get("k") in kinds)]


# ============================================================================================ bot + game
class CovBot(Bot):
    calibrated = False

    def calibrate_look(self) -> float:
        """Adaptive look calibration (the chain bot's): one window pixel is ~4 degrees in the 64 px headless window."""
        if not self.wait_state(lambda s: s.get("mode") == "playing" and not s.get("ui_stack"), 10.0):
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
        self.log(f"calibrated look: {self.px_per_deg:.4f} px/deg (motion {amt:.2f} -> dyaw {d:.1f}) ok={self.calibrated}")
        return self.px_per_deg

    def turn_to_yaw(self, target: float, tol: float = 3.0, timeout: float = 3.0) -> bool:
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
            self.win.mouse_move(round(-step * self.px_per_deg * self.invert * 0.85, 4), 0)
            time.sleep(0.12)
        return False


class Game(S4.HeadlessGame):
    def start(self, connect_timeout: float = 120.0):
        super().start(connect_timeout)
        self.bot = CovBot(self.vin, Telemetry(self.tele_path), self.log_path)
        return self.bot


class Stop(Exception):
    pass


class Cov(S4.Play):
    def __init__(self, game: Game, out: Path, results: dict):
        super().__init__(game, out)
        self.rec = Recorder(game.tele_path)
        self.R = results
        self.bugs: list[dict] = results.setdefault("bugs", [])

    # ---------------------------------------------------------------- bookkeeping
    def note(self, key: str, value):
        self.R.setdefault("checks", {})[key] = value
        self.log(f"CHECK {key}: {json.dumps(value, default=str)[:900]}")
        write_json(self.out / "result.json", self.R)

    def bug(self, title, severity, steps, expected, actual, evidence):
        b = {"title": title, "severity": severity, "steps": steps, "expected": expected, "actual": actual,
             "evidence": evidence}
        self.bugs.append(b)
        self.log(f"BUG [{severity}] {title}")
        write_json(self.out / "bugs.json", self.bugs)

    def gt(self) -> float:
        return self.rec.t()

    def eq(self) -> dict:
        return dict(self.st().get("equipment") or {})

    def active(self) -> str:
        cs = self.st().get("companion_skills") or {}
        a = [k for k, v in cs.items() if v.get("active")]
        return a[0] if a else ""

    def cskill(self, cid: str) -> dict:
        return (self.st().get("companion_skills") or {}).get(cid, {})

    def bag_used(self) -> int:
        return sum(1 for b in self.bag_buttons().values() if b.get("item"))

    # ---------------------------------------------------------------- UI: backpack
    def open_inv(self) -> bool:
        if "inventory" in self.ui():
            return True
        self.close_panels()
        self.bot.tap("TAB")
        ok = self.wait(lambda s: "inventory" in (s.get("ui_stack") or []), 3.0) is not None
        time.sleep(0.5)
        return ok

    def bag_buttons(self) -> dict:
        out = {}
        for b in self.buttons():
            t = str(b.get("text", ""))
            if t.startswith("slot:bag:"):
                out[int(t.split(":")[2])] = b
        return out

    def equip_buttons(self) -> dict:
        eqs = [b for b in self.buttons() if str(b.get("text", "")) == "slot:other:-1"]
        eqs.sort(key=lambda b: float((b.get("rf") or b.get("rect"))[0]))
        return {EQUIP_ORDER[i]: b for i, b in enumerate(eqs[:4])} if len(eqs) >= 4 else {}

    def click_b(self, b):
        r = b.get("rf") or b.get("rect")
        x, y, w, h = [float(v) for v in r]
        self.g.vin.click(x + w / 2.0, y + h / 2.0)
        time.sleep(0.35)

    def bag_index(self, item: str) -> int:
        for i, b in sorted(self.bag_buttons().items()):
            if b.get("item") == item:
                return i
        return -1

    def equip_ui(self, item: str, slot: str, via: str = "slot") -> dict:
        """Backpack UI: click the item's backpack slot (picks it up + shows its card), then click the equipment slot
        (via="slot") or the card's Equip button (via="button"). Returns what the telemetry shows afterwards."""
        self.open_inv()
        i = self.bag_index(item)
        if i < 0:
            return {"ok": False, "why": f"{item} not in the backpack"}
        before = self.eq()
        self.click_b(self.bag_buttons()[i])
        if via == "button":
            ok = self.click_button("Equip", exact=True, timeout=2.0)
            if not ok:
                return {"ok": False, "why": "no Equip button"}
        else:
            es = self.equip_buttons()
            if slot not in es:
                return {"ok": False, "why": "no equipment slots in telemetry"}
            self.click_b(es[slot])
        s = self.wait(lambda st: (st.get("equipment") or {}).get(slot) == item, 3.0)
        time.sleep(0.3)
        after = self.eq()
        return {"ok": s is not None, "item": item, "slot": slot, "via": via, "from_bag_slot": i, "before": before,
                "after": after, "bag_slot_now": self.bag_buttons().get(i, {}).get("item")}

    def unequip_ui(self, slot: str) -> dict:
        self.open_inv()
        es = self.equip_buttons()
        before = self.eq()
        inv0 = dict(self.st().get("inv") or {})
        used0 = self.bag_used()
        self.click_b(es[slot])
        time.sleep(0.8)
        after = self.eq()
        inv1 = dict(self.st().get("inv") or {})
        return {"slot": slot, "before": before.get(slot), "after": after.get(slot), "bag_used_before": used0,
                "bag_used_after": self.bag_used(), "inv_changed": {k: [inv0.get(k), inv1.get(k)] for k in set(inv0) | set(inv1)
                                                                      if inv0.get(k) != inv1.get(k)}}

    def to_hotbar(self, item: str, idx: int = 7) -> dict:
        self.open_inv()
        i = self.bag_index(item)
        if i < 0:
            return {"ok": False, "why": "not in bag"}
        if i == idx:
            return {"ok": True, "already": True}
        prev = self.bag_buttons().get(idx, {}).get("item")
        self.click_b(self.bag_buttons()[i])
        self.click_b(self.bag_buttons()[idx])
        time.sleep(0.4)
        bb = self.bag_buttons()
        return {"ok": bb.get(idx, {}).get("item") == item, "from": i, "to": idx, "swapped_out": prev,
                "slot_from_now": bb.get(i, {}).get("item")}

    def eat(self, food: str) -> dict:
        self.open_inv()
        hp0 = self.hp()
        n0 = self.inv(food)
        i = self.bag_index(food)
        if i < 0:
            self.close_panels()
            return {"ok": False}
        t0 = self.gt()
        self.click_b(self.bag_buttons()[i])
        self.click_button("Eat", exact=True, timeout=2.0)
        time.sleep(0.4)
        self.close_panels()
        time.sleep(0.6)
        return {"ok": self.inv(food) < n0, "food": food, "hp_before": hp0, "hp_after": self.hp(), "t": t0,
                "heal_events": [e for e in self.rec.hp_events(t0) if e["d"] > 0]}

    def heal_if_low(self, below: float = 40.0):
        if self.hp() >= below:
            return
        for food in ("pumpkin", "candy", "berry_snack", "hearty_stew", "berries"):
            if self.inv(food) > 0:
                r = self.eat(food)
                self.log(f"heal: {r}")
                if self.hp() >= below:
                    return

    # ---------------------------------------------------------------- UI: companions
    def companion_entry(self, cid: str):
        return self.nearest(lambda n: n.get("name") == f"Companion_{cid}", 80)

    def talk_to(self, cid: str) -> bool:
        self.close_panels()
        for _ in range(3):
            e = self.companion_entry(cid)
            if e is None:
                self.log(f"{cid} not nearby")
                return False
            ok = self.interact_with(e, [f"Talk to {cid.capitalize()}"],
                                    check=lambda: "companion" in self.ui(), tries=4, stop=1.4)
            if ok:
                time.sleep(0.5)
                return True
        return False

    def companion_cmd(self, cid: str, button: str) -> bool:
        if not self.talk_to(cid):
            return False
        ok = self.click_button(button, exact=True, timeout=3.0)
        time.sleep(0.6)
        if "companion" in self.ui():
            self.close_panels()
        return ok

    def settings_toggle(self, cid: str, text: str, want: bool) -> dict:
        """Friends panel check buttons (Settings, saved to the isolated settings file)."""
        key = {"Attacks on its own": "companion_auto_attack", "Uses its skill on its own": "companion_autocast"}[text]
        cur = self.setting(key)
        res = {"key": key, "before": cur, "want": want}
        if cur != want:
            if self.talk_to(cid):
                self.click_button(text, exact=True, timeout=3.0)
                time.sleep(0.5)
                self.close_panels()
        res["after"] = self.setting(key)
        return res

    def setting(self, key: str):
        f = self.g.settings_file
        if not f.exists():
            return True
        for ln in f.read_text(encoding="utf-8", errors="replace").splitlines():
            if ln.startswith(key + "="):
                return ln.split("=", 1)[1].strip() == "true"
        return True

    # ---------------------------------------------------------------- movement helpers
    def go(self, pts, tol=1.8, sprint=True, fight=False) -> bool:
        for pt in pts:
            if not self.goto(pt, tol=tol, sprint=sprint, timeout=45):
                if not self.goto(pt, tol=tol + 1.0, sprint=False, timeout=30):
                    return False
        return True

    def home(self) -> bool:
        self.close_panels()
        here = xz(self.pos())
        if d2(here, HAVEN) < 14:
            return True
        best = None
        for path in (PATH_THICKET, PATH_QUARRY, PATH_MINE):
            for k, p in enumerate(path):
                d = d2(p, here)
                if best is None or d < best[0]:
                    best = (d, path, k)
        if best and best[0] < 30:
            self.go(best[1][: best[2] + 1][::-1], sprint=True)
        return self.goto(HAVEN, tol=2.5, timeout=60)

    def sleep_bed(self, label: str) -> dict:
        self.close_panels()
        self.home()
        bed = self.nearest(lambda n: "sleep until morning" in str(n.get("text", "")).lower() or n.get("name") == "S_s2", 40)
        t0 = self.gt()
        hp0 = self.hp()
        ok = False
        if bed is not None:
            ok = self.interact_with(bed, ["Sleep until morning"], check=lambda: self.hp() >= 99.5, tries=4, stop=1.3)
        self.wait_playing(40)
        time.sleep(1.5)
        saved = [m for m in self.rec.messages(t0, ("saved",))]
        out = {"label": label, "ok": ok, "hp_before": hp0, "hp_after": self.hp(), "saved": [m.get("text") for m in saved]}
        self.snapshot(label)
        self.bot.calibrate_look()
        return out

    def snapshot(self, label: str):
        dst = self.out / "checkpoints" / label
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(self.g.save_dir, dst)
        self.log(f"checkpoint {label} -> {dst}")

    # ---------------------------------------------------------------- measurement helpers
    def bramblings(self, maxd=30.0):
        return [e for e in self.live_enemies(maxd) if str(e.get("name", "")).lower().startswith("brambl")
                or "brambling" in str(e.get("name", "")).lower()]

    def stand_and_take_hits(self, n: int, label: str, timeout: float = 45.0, min_hp: float = 30.0,
                            anchor=None) -> dict:
        """Krystal stands still (no attack) facing the nearest enemy until `n` hp drops happened."""
        t0 = self.gt()
        tw = time.time()
        while time.time() - tw < timeout:
            evs = [e for e in self.rec.hp_events(t0) if e["d"] < 0]
            if len(evs) >= n:
                break
            if self.hp() < min_hp:
                self.log(f"{label}: hp {self.hp()} < {min_hp}, stopping early")
                break
            live = self.live_enemies(25)
            if live:
                e = live[0]
                if float(e["dist"]) > 6.0:
                    self.approach(e, stop=2.0)
                else:
                    self.face(e["pos"], tol=10)
            elif anchor is not None and d2(self.pos(), anchor) > 4:
                self.goto(anchor, tol=2.0, sprint=False, timeout=20)
            time.sleep(0.3)
        t1 = self.gt()
        evs = self.rec.hp_events(t0, t1)
        hits = [e for e in evs if e["d"] < 0]
        return {"label": label, "t0": t0, "t1": t1, "hits": [round(-e["d"], 2) for e in hits], "events": evs,
                "eq": self.eq(), "companion": self.active()}

    def measure_walk(self, label: str, seconds: float = SPEED_SECONDS, sprint: bool = False) -> dict:
        """Same straight line every time: walk to SPEED_START, face SPEED_DIR_TARGET, hold W for `seconds`; speed =
        horizontal distance / game time over the steady part (0.6 s after the key down until the release)."""
        self.close_panels()
        self.goto(SPEED_START, tol=0.6, sprint=False, timeout=40)
        self.bot.hold("S", 0.05)
        time.sleep(0.6)
        yaw = Bot.yaw_to((SPEED_START[0], 0, SPEED_START[1]), (SPEED_DIR_TARGET[0], 0, SPEED_DIR_TARGET[1]))
        self.bot.turn_to_yaw(yaw, tol=1.0, timeout=4.0)
        time.sleep(0.4)
        buffs0 = self.st().get("buffs")
        t0 = self.gt()
        self.bot.down("W")
        if sprint:
            self.bot.down("SHIFT")
        time.sleep(seconds)
        self.bot.release_all()
        time.sleep(0.5)
        recs = [r for r in self.rec.window(t0 + 0.6, t0 + seconds - 0.1) if r.get("pos") and not r.get("paused")]
        res = {"label": label, "companion": self.active(), "buffs_at_start": buffs0, "n": len(recs)}
        if len(recs) >= 5:
            a, b = recs[0], recs[-1]
            dt = float(b["t"]) - float(a["t"])
            path = 0.0
            for r0, r1 in zip(recs, recs[1:]):
                path += d2(r0["pos"], r1["pos"])
            hv = [math.hypot(r["vel"][0], r["vel"][2]) for r in recs if r.get("vel")]
            res.update({"dt": round(dt, 3), "straight_m": round(d2(a["pos"], b["pos"]), 3), "path_m": round(path, 3),
                        "speed": round(path / dt, 3) if dt > 0 else None,
                        "vel_mean": round(sum(hv) / len(hv), 3) if hv else None,
                        "vel_min": round(min(hv), 3) if hv else None, "vel_max": round(max(hv), 3) if hv else None,
                        "buffs_seen": sorted({k for r in recs for k in (r.get("buffs") or {})})})
        self.log(f"walk {label}: {res}")
        return res


# ============================================================================================ phases
def phase_boot(c: Cov):
    s = c.bot.wait_state(lambda st: st.get("mode") == "title" and any(b.get("text") == "Continue" for b in st.get("buttons", [])), 150)
    if not s:
        raise Stop("no title / Continue")
    c.click_button("Continue", exact=True, timeout=10)
    if not c.wait(lambda st: st.get("mode") == "playing", 150):
        raise Stop("Continue never reached gameplay")
    time.sleep(2.5)
    c.dismiss = c.close_panels()
    c.bot.calibrate_look()
    st = c.st()
    c.note("boot", {"area": st.get("area"), "hp": (st.get("player") or {}).get("hp"), "equipment": st.get("equipment"),
                    "active": c.active(), "hour": st.get("hour"), "day": st.get("day"),
                    "companion_nodes": st.get("companion_nodes"), "companion_skills": st.get("companion_skills")})


def is_brambling(e) -> bool:
    return str(e.get("name", "")).startswith("Brambling")


def bramblings_near(c: Cov, center, radius: float = 16.0, maxd: float = 40.0) -> list:
    return [e for e in c.live_enemies(maxd) if is_brambling(e) and d2(e["pos"], (center[0], 0, center[1])) <= radius]


def danger(c: Cov) -> dict | None:
    """A non-Brambling enemy (Knotted Elder, Bramblebacks) hunting Krystal close by."""
    for e in c.live_enemies(14):
        if not is_brambling(e) and e.get("threat") and str(e.get("state")) in ("chase", "telegraph", "attack", "charge"):
            return e
    return None


def retreat_from(c: Cov, e, to=DROP_SPOT):
    c.log(f"retreat from {e.get('name')} ({e.get('state')}, {e.get('dist')} m)")
    c.goto(to, tol=2.0, sprint=True, timeout=25)


def stand_hits(c: Cov, n: int, label: str, center=THICKET, timeout: float = 45.0, min_hp: float = 25.0) -> dict:
    """Krystal holds a non-weapon hotbar item and stands still facing the nearest Brambling (never attacks) until
    `n` hp drops were recorded."""
    t0 = c.gt()
    tw = time.time()
    while time.time() - tw < timeout:
        hits = [e for e in c.rec.hp_events(t0) if e["d"] < 0]
        if len(hits) >= n:
            break
        if c.hp() < min_hp:
            c.log(f"{label}: hp {c.hp()} < {min_hp}: stop early")
            break
        dg = danger(c)
        if dg:
            retreat_from(c, dg)
            continue
        live = bramblings_near(c, center)
        if live:
            e = live[0]
            if float(e["dist"]) > 5.0:
                c.approach(e, stop=2.0)
            else:
                c.face(e["pos"], tol=12)
        else:
            c.goto(center, tol=4.0, sprint=False, timeout=15)
        time.sleep(0.3)
    t1 = c.gt()
    evs = c.rec.hp_events(t0, t1)
    return {"label": label, "t0": t0, "t1": t1, "hits": [round(-e["d"], 2) for e in evs if e["d"] < 0],
            "heals": [e["d"] for e in evs if e["d"] > 0], "eq": c.eq(), "companion": c.active(),
            "events": [{"t": e["t"], "d": e["d"], "hp": e["hp"], "near": e["near"]} for e in evs]}


def wand_fight(c: Cov, kills: int, center=THICKET, timeout: float = 150.0, keep_last: bool = False) -> dict:
    """Wand selected (hotbar 8): face the nearest Brambling of the group and cast (attack) about once a second
    until `kills` of them are gone. Stamina drops, enemy hp drops and kills come from the telemetry history."""
    c.bot.tap("8")
    time.sleep(0.3)
    t0 = c.gt()
    tw = time.time()
    presses = []
    while time.time() - tw < timeout:
        if len(c.rec.kills(t0)) >= kills:
            break
        if c.hp() < 35:
            c.heal_if_low(45)
        dg = danger(c)
        if dg:
            retreat_from(c, dg)
            continue
        live = bramblings_near(c, center)
        if not live:
            if time.time() - tw > 8 and not bramblings_near(c, center, 20, 60):
                break
            c.goto(center, tol=4.0, sprint=False, timeout=15)
            time.sleep(0.4)
            continue
        e = live[0]
        d = float(e["dist"])
        if d > 11:
            c.approach(e, stop=7.0)
            continue
        c.face(e["pos"], tol=5)
        tc = c.gt()
        c.bot.tap("LMB", 0.06)
        presses.append({"t": tc, "target": e["name"], "dist": d})
        time.sleep(1.0)
    t1 = c.gt()
    c.bot.tap("1")
    return {"t0": t0, "t1": t1, "presses": presses, "stamina_drops": c.rec.stamina_drops(t0, t1),
            "enemy_hits": c.rec.enemy_hits(t0, t1), "kills": c.rec.kills(t0, t1),
            "player_hits": [{"t": e["t"], "d": e["d"], "eq": e["eq"]} for e in c.rec.hp_events(t0, t1) if e["d"] < 0]}


def phase_A(c: Cov):
    """Equipment + wand + armor damage with NO pet."""
    c.R["sleep_A0"] = c.sleep_bed("A_start")          # full health from the Haven bed (natural), morning
    ok = c.companion_cmd("lumi", "Go home")
    time.sleep(1.0)
    c.note("A_no_pet", {"go_home_clicked": ok, "active_after": c.active(),
                        "lumi_assignment": (c.st().get("companion_nodes") or {}).get("lumi", {}).get("assignment")})
    c.R.setdefault("speed", []).append(c.measure_walk("none"))
    c.open_inv()
    used = c.bag_used()
    tb = c.to_hotbar("sparkseed_wand", 7)
    c.close_panels()
    c.note("A_bag_and_hotbar", {"bag_used_of_32": used, "wand_to_hotbar": tb})
    # over the ground pickups with a FULL backpack
    t0 = c.gt()
    c.bot.tap("1")
    c.go(PATH_THICKET[:-1])
    for dx, dz in ((0, 0), (0.8, -0.6), (-0.8, -0.6), (0, -1.3)):
        c.goto((DROP_SPOT[0] + dx, DROP_SPOT[1] + dz), tol=0.4, sprint=False, timeout=10)
        time.sleep(1.2)
    inv = c.st().get("inv") or {}
    on_ground = [(n.get("text"), n.get("pos")) for n in c.nearby(lambda n: n.get("g") == "interactable" and (
        "copperwood" in str(n.get("text", "")).lower() or "ribbon" in str(n.get("text", "")).lower()), 10)]
    c.note("A_full_bag_pickup", {"picked": {k: inv.get(k, 0) for k in ("copperwood_hood", "copperwood_vest", "copperwood_boots", "comfort_ribbon")},
                                 "still_on_ground": on_ground,
                                 "notify": sorted({m.get("text") for m in c.rec.messages(t0, ("notify",))})})
    # wand: two of the three Thornthicket Bramblings
    c.note("A_wand", wand_fight(c, kills=2))
    # armor on the third one: none -> padded -> copperwood (Krystal never attacks)
    c.heal_if_low(50)
    hits_none = stand_hits(c, 3, "none")
    c.heal_if_low(50)
    eqr = [c.equip_ui("padded_hood", "head", "slot"), c.equip_ui("padded_vest", "body", "slot"),
           c.equip_ui("padded_boots", "boots", "slot"), c.equip_ui("gatherers_charm", "charm", "button")]
    c.close_panels()
    c.note("A_equip_padded", eqr)
    hits_padded = stand_hits(c, 3, "padded")
    c.heal_if_low(50)
    # the ground pickups now fit (4 slots freed by wearing 4 pieces)
    t0 = c.gt()
    for dx, dz in ((0, 0), (0.8, -0.6), (-0.8, -0.6), (0, -1.3), (0, 0)):
        c.goto((DROP_SPOT[0] + dx, DROP_SPOT[1] + dz), tol=0.4, sprint=False, timeout=15)
        time.sleep(1.0)
    inv = c.st().get("inv") or {}
    c.open_inv()
    used = c.bag_used()
    unequip_full = c.unequip_ui("charm")
    notify_unequip = [m.get("text") for m in c.rec.messages(c.gt() - 2.0, ("notify",))]
    swaps = [c.equip_ui("copperwood_hood", "head", "slot"), c.equip_ui("copperwood_vest", "body", "slot"),
             c.equip_ui("copperwood_boots", "boots", "slot")]
    used2 = c.bag_used()
    c.close_panels()
    c.note("A_full_bag_equipment", {"picked": {k: inv.get(k, 0) for k in ("copperwood_hood", "copperwood_vest", "copperwood_boots", "comfort_ribbon")},
                                    "bag_used_after_pickups": used, "unequip_charm_full_bag": unequip_full,
                                    "notify_after_unequip": notify_unequip, "swaps": swaps, "bag_used_after_swaps": used2,
                                    "padded_back_in_bag": {k: c.inv(k) for k in ("padded_hood", "padded_vest", "padded_boots")}})
    c.heal_if_low(55)
    hits_copper = stand_hits(c, 3, "copperwood", min_hp=15)
    c.note("A_armor_hits", {"none": hits_none, "padded": hits_padded, "copperwood": hits_copper,
                            "expected": {"none": BRAMBLING_DMG, "padded": round(BRAMBLING_DMG * (1 - PADDED), 2),
                                         "copperwood": round(BRAMBLING_DMG * (1 - COPPERWOOD), 2)}})
    c.heal_if_low(40)
    c.note("A_wand_2", wand_fight(c, kills=1))
    c.R["sleep_A"] = c.sleep_bed("A_end")


def phase_B(c: Cov):
    """Lumi: speed (passive, Glimmerstep via T), T refused while recharging, Light Bolt damage."""
    c.home()
    ok = c.companion_cmd("lumi", "Follow me")
    time.sleep(1.5)
    c.note("B_lumi_follow", {"clicked": ok, "active": c.active(), "lumi": c.cskill("lumi"),
                             "bond": (c.st().get("companion_nodes") or {}).get("lumi", {}).get("bond")})
    c.R.setdefault("speed", []).append(c.measure_walk("lumi_passive"))
    c.R.setdefault("speed", []).append(c.measure_walk("lumi_passive_2"))
    c.goto(SPEED_START, tol=0.6, sprint=False, timeout=40)
    c.bot.hold("S", 0.05)
    time.sleep(0.6)
    yaw = Bot.yaw_to((SPEED_START[0], 0, SPEED_START[1]), (SPEED_DIR_TARGET[0], 0, SPEED_DIR_TARGET[1]))
    c.bot.turn_to_yaw(yaw, tol=1.0, timeout=4.0)
    time.sleep(0.3)
    left0 = c.cskill("lumi").get("left")
    tT = c.gt()
    c.bot.tap("T")
    time.sleep(0.25)
    c.R.setdefault("speed", []).append(measure_now(c, "lumi_glimmerstep", seconds=3.2))
    sk = c.cskill("lumi")
    tT2 = c.gt()
    c.bot.tap("T")
    time.sleep(1.0)
    c.note("B_glimmerstep", {"left_before_T": left0, "skill_msgs": [m.get("text") for m in c.rec.messages(tT, ("skill",))],
                             "state_after_T": sk, "second_T_notify": [m.get("text") for m in c.rec.messages(tT2, ("notify",))],
                             "buffs_after_T": [r.get("buffs") for r in c.rec.window(tT, tT + 1.0)][-1:]})
    # after the buff is over: passive only again
    time.sleep(3.0)
    c.R.setdefault("speed", []).append(c.measure_walk("lumi_passive_after_buff"))
    # Light Bolt on the quarry Bramblings (the wand helps; wand sparks do 9.0, Lumi's bolts 6.6)
    c.go(PATH_QUARRY)
    c.goto(QUARRY_BR, tol=6.0, sprint=False, timeout=30)
    dmg = companion_fight(c, "lumi", QUARRY_BR, kills=2, wand_kills=1)
    c.note("B_lumi_damage", dmg)
    c.R["sleep_B"] = c.sleep_bed("B_end")


def measure_now(c: Cov, label: str, seconds: float) -> dict:
    t0 = c.gt()
    c.bot.down("W")
    time.sleep(seconds)
    c.bot.release_all()
    time.sleep(0.4)
    recs = [r for r in c.rec.window(t0 + 0.6, t0 + seconds - 0.1) if r.get("pos")]
    res = {"label": label, "companion": c.active(), "n": len(recs)}
    if len(recs) >= 5:
        a, b = recs[0], recs[-1]
        dt = float(b["t"]) - float(a["t"])
        path = sum(d2(r0["pos"], r1["pos"]) for r0, r1 in zip(recs, recs[1:]))
        hv = [math.hypot(r["vel"][0], r["vel"][2]) for r in recs if r.get("vel")]
        res.update({"dt": round(dt, 3), "path_m": round(path, 3), "speed": round(path / dt, 3) if dt > 0 else None,
                    "vel_mean": round(sum(hv) / len(hv), 3) if hv else None,
                    "vel_min": round(min(hv), 3) if hv else None, "vel_max": round(max(hv), 3) if hv else None,
                    "buffs_seen": sorted({k for r in recs for k in (r.get("buffs") or {})}),
                    "glimmer": (recs[0].get("buffs") or {}).get("glimmerstep")})
    c.log(f"walk {label}: {res}")
    return res


def companion_fight(c: Cov, cid: str, center, kills: int, wand_kills: int = 0, timeout: float = 150.0,
                    stop_hp: float = 25.0, keep_one_until_hp: float | None = None, on_tick=None) -> dict:
    """Krystal next to a Bramblings group; the follower attacks. If wand_kills > 0 Krystal also casts the wand
    until that many are down (sparks do exactly 9.0, so the companion's hits are told apart by value). With
    keep_one_until_hp the last Brambling is left to the companion (Krystal only stands) until her hp is at or
    below that value (Mochi's Bloomguard autocast needs <= 60 %)."""
    t0 = c.gt()
    tw = time.time()
    while time.time() - tw < timeout:
        if on_tick is not None:
            on_tick()
        k = len(c.rec.kills(t0))
        if k >= kills:
            break
        if c.hp() < stop_hp:
            c.heal_if_low(stop_hp + 15)
            if c.hp() < stop_hp:
                c.log("hp too low: backing off")
                break
        dg = danger(c)
        if dg:
            retreat_from(c, dg, to=center if d2(center, dg["pos"]) > 15 else DROP_SPOT)
            continue
        live = bramblings_near(c, center, 18)
        if not live:
            if time.time() - tw > 10 and not bramblings_near(c, center, 24, 60):
                break
            c.goto(center, tol=4.0, sprint=False, timeout=15)
            time.sleep(0.4)
            continue
        e = live[0]
        use_wand = k < wand_kills and not (keep_one_until_hp is not None and len(live) <= 1 and c.hp() > keep_one_until_hp)
        if use_wand:
            c.bot.tap("8")
            if float(e["dist"]) > 10:
                c.approach(e, stop=6.0)
                continue
            c.face(e["pos"], tol=5)
            c.bot.tap("LMB", 0.06)
            time.sleep(1.0)
        else:
            c.bot.tap("1")
            if float(e["dist"]) > 5:
                c.approach(e, stop=2.5)
            else:
                c.face(e["pos"], tol=12)
            time.sleep(0.4)
    t1 = c.gt()
    c.bot.tap("1")
    node = [((r.get("cs") or {}).get(cid) or {}).get("node", {}) for r in c.rec.window(t1 - 1, t1)]
    hits = c.rec.enemy_hits(t0, t1)
    return {"t0": t0, "t1": t1, "kills": c.rec.kills(t0, t1), "enemy_hits": hits,
            "hit_values": sorted({h["d"] for h in hits}),
            "player_events": [{"t": e["t"], "d": e["d"], "hp": e["hp"], "companion": e["companion"], "eq": e["eq"]} for e in c.rec.hp_events(t0, t1)],
            "skill_msgs": c.rec.messages(t0, ("skill",)), "attacks_counter": node[-1].get("attacks") if node else None,
            "bond": (c.st().get("companion_nodes") or {}).get(cid, {}).get("bond")}


RETREAT = (-40.0, -29.0)             # beyond the thicket Bramblings' 22 m leash


def phase_C(c: Cov):
    """Pebble: passive x armor, Stoneheart absorbing hits, ONE cooldown for T and autocast (both directions),
    Stone Bump damage, the cooldown across a pause-menu save + quit + relaunch + Continue. The Friends panel closes
    itself when Krystal is hurt, so every toggle is set where nothing can reach her."""
    c.home()
    ok = c.companion_cmd("pebble", "Follow me")
    time.sleep(1.5)
    c.note("C_pebble_follow", {"clicked": ok, "active": c.active(), "pebble": c.cskill("pebble"), "equipment": c.eq(),
                               "bond": (c.st().get("companion_nodes") or {}).get("pebble", {}).get("bond")})
    c.note("C_toggles_1", [c.settings_toggle("pebble", "Attacks on its own", False),
                           c.settings_toggle("pebble", "Uses its skill on its own", True)])
    c.R.setdefault("speed", []).append(c.measure_walk("pebble_control"))
    c.note("C_berries", [pick_berries(c) for _ in range(3)])
    c.bot.tap("1")
    c.go(PATH_THICKET)
    c.goto(THICKET, tol=6.0, sprint=False, timeout=30)
    # 1) two Bramblings by the wand (9.0) while Pebble only supports (passive + AUTOCAST); T right after the first
    #    autocast must be refused (autocast -> manual share the cooldown)
    probe = {}
    t_f = c.gt()

    def after_autocast():
        if probe:
            return
        sk = [m for m in c.rec.messages(t_f, ("skill",)) if "stoneheart" in str(m.get("text", ""))]
        if sk:
            tt = c.gt()
            c.bot.tap("T")
            time.sleep(0.6)
            probe.update({"autocast": sk[0], "T_at": tt, "left_at_T": c.cskill("pebble").get("left"),
                          "T_notify": [m.get("text") for m in c.rec.messages(tt - 0.1, ("notify",))]})
    fight = companion_fight(c, "pebble", THICKET, kills=2, wand_kills=2, on_tick=after_autocast)
    ac = probe.get("autocast")
    if ac:
        tb = float(ac["t"])
        probe["hp_events_0_6s"] = [(e["t"], e["d"], e["hp"]) for e in c.rec.hp_events(tb, tb + 6.0)]
        probe["attack_cycles_0_6s"] = count_attacks(c.rec.window(tb, tb + 6.0))
    c.note("C_passive_fight", fight)
    c.note("C_autocast_then_T", probe)
    # 2) manual Stoneheart (T) out of reach once ready, then back to the last Brambling: the shield window, then
    #    ~15 s of attacks with autocast ON and no autocast allowed until 26 s after the manual cast
    c.goto(RETREAT, tol=2.0, sprint=True, timeout=25)
    c.heal_if_low(70)
    tw = time.time()
    while not c.cskill("pebble").get("ready") and time.time() - tw < 40:
        time.sleep(0.5)
    tS = c.gt()
    c.bot.tap("T")
    time.sleep(0.4)
    manual_ok = [m.get("text") for m in c.rec.messages(tS, ("skill",))]
    c.goto(THICKET, tol=5.0, sprint=True, timeout=20)
    shield = stand_hits(c, 3, "after_manual_T", timeout=max(3.0, 20.0 - (c.gt() - tS)), min_hp=20)
    early = [m for m in c.rec.messages(tS + 0.5, ("skill",))]
    evs = c.rec.hp_events(tS, tS + 6.2)
    c.note("C_stoneheart_manual", {"skill_msgs": manual_ok, "cast_t": tS,
                                   "hp_events_first_6s": [(e["t"], e["d"], e["hp"]) for e in evs],
                                   "attack_cycles_first_6s": count_attacks(c.rec.window(tS, tS + 6.2)),
                                   "stand_window": shield, "autocasts_before_26s": [m.get("text") for m in early
                                                                                     if float(m.get("t", 0)) < tS + 26.0]})
    # 3) out of reach until the cooldown is nearly over, then back: the first attack after it gets the autocast
    c.goto(RETREAT, tol=2.0, sprint=True, timeout=25)
    c.heal_if_low(60)
    while (c.cskill("pebble").get("left") or 0) > 1.0 and c.gt() - tS < 45:
        time.sleep(0.5)
    tR = c.gt()
    c.goto(THICKET, tol=5.0, sprint=True, timeout=20)
    auto = None
    tw = time.time()
    while time.time() - tw < 25:
        sk = [m for m in c.rec.messages(tS + 0.5, ("skill",))]
        if sk:
            auto = sk[0]
            break
        live = bramblings_near(c, THICKET)
        if live and float(live[0]["dist"]) > 3:
            c.approach(live[0], stop=1.8)
        elif live:
            c.face(live[0]["pos"], tol=12)
        else:
            c.goto(THICKET, tol=4.0, sprint=False, timeout=10)
        time.sleep(0.25)
    c.note("C_shared_cooldown", {"manual_T_t": tS, "autocasts_between": [m.get("text") for m in early],
                                 "back_in_reach_t": tR, "first_autocast_after_manual": auto,
                                 "autocast_after_manual_s": round(float(auto["t"]) - tS, 2) if auto else None,
                                 "cooldown_s": 26.0})
    # 4) Stone Bump: toggle attacks ON out of reach, then Pebble alone finishes the last Brambling
    c.goto(RETREAT, tol=2.0, sprint=True, timeout=25)
    c.note("C_toggles_2", c.settings_toggle("pebble", "Attacks on its own", True))
    c.heal_if_low(60)
    c.note("C_pebble_damage", companion_fight(c, "pebble", THICKET, kills=1, wand_kills=0, timeout=70, stop_hp=18))
    # 5) the cooldown across save / quit / relaunch: cast out of combat, save in the pause menu, quit
    c.home()
    c.settings_toggle("pebble", "Uses its skill on its own", False)
    tw = time.time()
    while not c.cskill("pebble").get("ready") and time.time() - tw < 40:
        time.sleep(1.0)
    tS2 = c.gt()
    c.bot.tap("T")
    time.sleep(3.0)
    pre = c.cskill("pebble")
    saved = pause_save(c)
    save = json.loads((c.g.save_dir / "slot1.json").read_text(encoding="utf-8"))
    ps = float(save["state"]["stats"]["play_seconds"])
    ra = float(save["state"]["companions"]["pebble"]["skill_ready_at"])
    c.R["C_saveload_pre"] = {"skill_msgs": [m.get("text") for m in c.rec.messages(tS2, ("skill",))],
                             "telemetry_left_before_save": pre.get("left"), "saved": saved,
                             "pause_save_play_seconds": ps, "pause_save_skill_ready_at": ra, "left_in_pause_save": round(ra - ps, 2)}
    c.note("C_saveload_pre", c.R["C_saveload_pre"])


def count_attacks(win: list[dict]) -> dict:
    """Brambling attack cycles in the telemetry ('recover' entries within 3.5 m) and 'stunned' entries."""
    last = {}
    rec = {}
    stun = {}
    for r in win:
        for e in r["en"]:
            nm, stt = e.get("name"), e.get("state")
            if last.get(nm) != stt:
                if stt == "recover" and (e.get("dist") or 99) < 3.5:
                    rec[nm] = rec.get(nm, 0) + 1
                if stt == "stunned":
                    stun[nm] = stun.get(nm, 0) + 1
            last[nm] = stt
    return {"recover_entries_within_3_5m": rec, "stunned_entries": stun}


def pause_save(c: Cov) -> bool:
    t0 = c.gt()
    c.close_panels()
    c.bot.tap("ESC")
    if not c.wait(lambda s: "pause" in (s.get("ui_stack") or []), 3.0):
        return False
    c.click_button("Save Game", exact=True, timeout=4.0)
    ok = c.wait(lambda s: any(m.get("k") == "saved" and float(m.get("t", 0)) >= t0 for m in s.get("messages", [])), 5.0) is not None
    c.close_panels()
    return ok


def phase_C_reload(c: Cov, pre: dict, save_dir: Path):
    save = json.loads((save_dir / "slot1.json").read_text(encoding="utf-8"))
    ps = float(save["state"]["stats"]["play_seconds"])
    ra = float(save["state"]["companions"]["pebble"]["skill_ready_at"])
    pre["quit_save_play_seconds"] = ps
    pre["quit_save_skill_ready_at"] = ra
    pre["left_in_quit_save"] = round(ra - ps, 2)
    samples = [dict(((r.get("cs") or {}).get("pebble") or {}), t=r.get("t")) for r in c.rec.window(0, None)
               if r.get("mode") == "playing" and ((r.get("cs") or {}).get("pebble") or {}).get("left") is not None]
    first = samples[0] if samples else {}
    c.note("C_saveload_post", {"pre": pre, "first_playing_sample": {k: first.get(k) for k in ("t", "left", "ready", "ready_at", "active")},
                               "now": {k: c.cskill("pebble").get(k) for k in ("left", "ready", "ready_at", "active")},
                               "active": c.active()})


def phase_D(c: Cov):
    """Mochi: Spore Puff, Bloomguard (autocast in a fight; manual T), healing passive on food."""
    c.R["sleep_D0"] = c.sleep_bed("D_start")
    ok = c.companion_cmd("mochi", "Follow me")
    time.sleep(1.5)
    c.note("D_mochi_follow", {"clicked": ok, "active": c.active(), "mochi": c.cskill("mochi"),
                              "bond": (c.st().get("companion_nodes") or {}).get("mochi", {}).get("bond")})
    c.note("D_toggles", [c.settings_toggle("mochi", "Attacks on its own", True),
                         c.settings_toggle("mochi", "Uses its skill on its own", True)])
    c.R.setdefault("speed", []).append(c.measure_walk("mochi_control"))
    c.note("D_berries_picked", pick_berries(c))
    c.bot.tap("1")
    c.go(PATH_THICKET)
    c.goto(THICKET, tol=6.0, sprint=False, timeout=30)
    # two Bramblings with the wand + Mochi; then the third one is Mochi's alone (Krystal only stands): food with
    # Mochi beside her once hurt, and the Bloomguard autocast when hp <= 60 %
    fight = companion_fight(c, "mochi", THICKET, kills=2, wand_kills=2, timeout=120, stop_hp=22)
    food = {}
    tw = time.time()
    tF = c.gt()
    while time.time() - tw < 60:
        if not food and c.hp() <= 88 and c.inv("berries") > 0:
            food = c.eat("berries")
            food["food_heal_on_item"] = 8.0
            food["mochi_present"] = c.active() == "mochi"
        if c.rec.messages(tF, ("skill",)):
            break
        live = bramblings_near(c, THICKET)
        if not live:
            break
        e = live[0]
        if float(e["dist"]) > 5:
            c.approach(e, stop=2.5)
        else:
            c.face(e["pos"], tol=12)
        if c.hp() < 25:
            c.heal_if_low(40)
        time.sleep(0.3)
    c.note("D_food_with_mochi", food)
    fight2 = companion_fight(c, "mochi", THICKET, kills=1, wand_kills=0, timeout=60, stop_hp=18)
    c.note("D_mochi_damage", {"wand_and_mochi": fight, "mochi_alone": fight2})
    # the autocast heal, from the whole history (hits and ticks told apart by sign)
    c.note("D_toggles_2", c.settings_toggle("mochi", "Uses its skill on its own", False))
    c.home()
    time.sleep(2.0)
    blooms = []
    for m in c.rec.messages(tF, ("skill",)):
        if "bloomguard" in str(m.get("text", "")):
            tb = float(m.get("t", 0))
            ev = c.rec.hp_events(tb - 0.3, tb + 6.9)
            hp_at = [r["hp"] for r in c.rec.window(tb - 0.3, tb) if r.get("hp") is not None]
            blooms.append({"cast_t": tb, "hp_at_cast": hp_at[-1] if hp_at else None,
                           "heal_sum": round(sum(e["d"] for e in ev if e["d"] > 0), 2),
                           "heal_ticks": [e["d"] for e in ev if e["d"] > 0], "hits_in_window": [e["d"] for e in ev if e["d"] < 0]})
    c.note("D_bloomguard_autocast", {"casts": blooms, "expected_base": 18.0, "expected_with_passive_8pct": 19.44})
    # manual Bloomguard (T) out of combat; T again right away is refused (one cooldown)
    tw = time.time()
    while not c.cskill("mochi").get("ready") and time.time() - tw < 40:
        time.sleep(1.0)
    hp0 = c.hp()
    tM = c.gt()
    c.bot.tap("T")
    time.sleep(1.0)
    c.bot.tap("T")
    time.sleep(6.8)
    ev = c.rec.hp_events(tM, tM + 7.6)
    c.note("D_bloomguard_manual", {"hp_before": hp0, "hp_after": c.hp(), "heal_ticks": [e["d"] for e in ev],
                                   "heal_sum": round(sum(e["d"] for e in ev if e["d"] > 0), 2),
                                   "capped": c.hp() >= 99.95,
                                   "skill_msgs": [m.get("text") for m in c.rec.messages(tM, ("skill",))],
                                   "notify": [m.get("text") for m in c.rec.messages(tM, ("notify",))],
                                   "expected_base": 18.0, "expected_with_passive_8pct": 19.44})
    # take a piece off with room in the backpack, then wear it again (Take off + Equip)
    c.open_inv()
    free = 32 - c.bag_used()
    off = c.unequip_ui("charm")
    back = c.equip_ui("gatherers_charm", "charm", "button")
    c.close_panels()
    c.note("D_unequip_with_room", {"free_slots": free, "take_off": off, "wear_again": back})


def pick_berries(c: Cov) -> dict:
    b0 = c.inv("berries")
    bush = c.nearest(lambda n: n.get("g") == "harvestable" and "berry bush" in str(n.get("label", "")).lower()
                     and "regrow" not in str(n.get("text", "")).lower() and n.get("enabled", True), 40)
    if bush is None:
        return {"ok": False, "why": "no ripe berry bush"}
    ok = c.interact_with(bush, ["Pick"], check=lambda: c.inv("berries") > b0, tries=3, stop=1.3)
    return {"ok": ok, "bush": bush.get("id"), "berries": c.inv("berries") - b0}


# ---------------------------------------------------------------------------------------------------------------
def phase_E(c: Cov):
    """Mochi's courage: refusal without it, ribbon + lantern, follows into the Below."""
    c.home()
    if c.active() != "mochi":
        c.companion_cmd("mochi", "Follow me")
        time.sleep(1.5)
    flags0 = set(c.st().get("flags") or [])
    c.bot.tap("1")
    t0 = c.gt()
    c.go(PATH_MINE, sprint=False)
    c.goto(MINE_THRESHOLD, tol=1.5, sprint=False, timeout=20)
    time.sleep(6.0)
    says = [m.get("text") for m in c.rec.messages(t0, ("say",))]
    mochi = (c.st().get("companion_nodes") or {}).get("mochi")
    door = c.nearest(lambda n: "enter the hollow mine" in str(n.get("text", "")).lower(), 30)
    entered = False
    if door:
        entered = c.interact_with(door, ["Enter the Hollow Mine"], check=lambda: c.area() == "below", tries=4, stop=1.2)
        c.wait(lambda s: s.get("mode") == "playing" and s.get("area") == "below", 30)
        if "comfort" in c.ui():
            c.click_button("Done", timeout=3)
        time.sleep(3.0)
    below = c.st()
    c.note("E_without_courage", {"courage_flag": "c1x_mochi_courage" in flags0, "mochi_before_door": mochi,
                                 "say_msgs": says, "entered": entered, "area": below.get("area"),
                                 "companion_nodes_below": below.get("companion_nodes"),
                                 "companions_state": below.get("companions")})
    # climb back out
    out_ = c.nearest(lambda n: "climb back up" in str(n.get("text", "")).lower(), 30)
    if out_:
        c.interact_with(out_, ["Climb back up"], check=lambda: c.area() == "surface", tries=4)
        c.wait(lambda s: s.get("mode") == "playing" and s.get("area") == "surface", 30)
        time.sleep(3.0)
    back = c.st()
    c.note("E_back_out", {"area": back.get("area"), "companion_nodes": back.get("companion_nodes"),
                          "companions": back.get("companions"), "active": c.active()})
    if c.active() != "mochi":
        c.companion_cmd("mochi", "Follow me")
        time.sleep(1.0)
    # ribbon in the Friends panel
    rib0 = c.inv("comfort_ribbon")
    tr = c.talk_to("mochi")
    tied = c.click_button("Tie the Comfort Ribbon", exact=True, timeout=3.0) if tr else False
    time.sleep(0.8)
    c.close_panels()
    flags1 = set(c.st().get("flags") or [])
    c.note("E_ribbon", {"ribbon_in_bag_before": rib0, "clicked": tied, "ribbon_in_bag_after": c.inv("comfort_ribbon"),
                        "c1x_ribbon_given": "c1x_ribbon_given" in flags1})
    # the courage lantern
    lan = c.nearest(lambda n: "lantern" in str(n.get("text", "")).lower() and "mochi" in str(n.get("text", "")).lower(), 30)
    t1 = c.gt()
    rest = False
    if lan:
        rest = c.interact_with(lan, ["Rest by the lantern with Mochi"], check=lambda: c.flag("c1x_mochi_courage"), tries=5, stop=1.2)
    time.sleep(3.0)
    c.note("E_lantern", {"lantern_entry": lan, "rested": rest, "courage_flag": c.flag("c1x_mochi_courage"),
                         "say_msgs": [m.get("text") for m in c.rec.messages(t1, ("say", "quest"))]})
    # into the mine again
    door = c.nearest(lambda n: "enter the hollow mine" in str(n.get("text", "")).lower(), 30)
    entered = False
    if door:
        entered = c.interact_with(door, ["Enter the Hollow Mine"], check=lambda: c.area() == "below", tries=4, stop=1.2)
        c.wait(lambda s: s.get("mode") == "playing" and s.get("area") == "below", 30)
        time.sleep(4.0)
    below = c.st()
    me = c.pos()
    mn = (below.get("companion_nodes") or {}).get("mochi")
    c.note("E_with_courage", {"entered": entered, "area": below.get("area"), "companion_nodes_below": below.get("companion_nodes"),
                              "mochi_dist": round(d2(me, mn["pos"]), 2) if mn else None, "active": c.active()})
    out_ = c.nearest(lambda n: "climb back up" in str(n.get("text", "")).lower(), 30)
    if out_:
        c.interact_with(out_, ["Climb back up"], check=lambda: c.area() == "surface", tries=4)
        c.wait(lambda s: s.get("mode") == "playing" and s.get("area") == "surface", 30)


def phase_F(c: Cov):
    """Take-off WITH room: free one backpack slot the player's way (eat a food stack), click the worn charm, then
    wear it again with the detail card's Equip button."""
    c.close_panels()
    c.open_inv()
    used0 = c.bag_used()
    eaten = []
    for food in ("candy", "berries", "pumpkin"):
        while c.bag_used() >= 32 and c.inv(food) > 0:
            r = c.eat(food)
            eaten.append({k: r.get(k) for k in ("food", "ok", "hp_before", "hp_after")})
            c.open_inv()
            if not r.get("ok"):
                break
    used1 = c.bag_used()
    off = c.unequip_ui("charm")
    idx = c.bag_index("gatherers_charm")
    again = c.equip_ui("gatherers_charm", "charm", "button")
    c.close_panels()
    c.note("F_unequip_with_room", {"bag_used_start": used0, "eaten_to_free_a_slot": eaten, "bag_used_before_take_off": used1,
                                   "take_off": off, "charm_now_in_bag_slot": idx, "wear_again": again})


# ============================================================================================ driver
def run(args) -> int:
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    results: dict = {"started": now(), "phases": args.phases, "start": None, "errors": [], "bugs": []}
    bugs_path = out / "bugs.json"
    if bugs_path.exists():
        results["bugs"] = json.loads(bugs_path.read_text(encoding="utf-8"))
    rpath = out / "result.json"
    if rpath.exists():
        try:
            old = json.loads(rpath.read_text(encoding="utf-8"))
            results.setdefault("previous", old.get("checks", {}))
        except Exception:  # noqa: BLE001
            pass
    phases = [p.strip() for p in args.phases.split(",") if p.strip()]
    attempt = args.attempt
    g = Game(out, f"g{attempt}", PORT_BASE + attempt, max_seconds=args.max_seconds, extra=["--no-wardrobe-notice"])
    results["start"] = prepare_save(g.save_dir, out, Path(args.start_save).resolve() if args.start_save else None)
    write_json(out / "result.json", results)
    g.start()
    c = Cov(g, out, results)
    rc = 0
    try:
        phase_boot(c)
        for ph in phases:
            fn = {"A": phase_A, "B": phase_B, "C": phase_C, "D": phase_D, "E": phase_E, "F": phase_F}[ph]
            c.log(f"######## phase {ph} ########")
            t0 = time.time()
            try:
                fn(c)
                results.setdefault("phase_status", {})[ph] = {"ok": True, "wall_s": round(time.time() - t0, 1)}
            except Exception as e:  # noqa: BLE001
                c.bot.release_all()
                results.setdefault("phase_status", {})[ph] = {"ok": False, "error": repr(e), "wall_s": round(time.time() - t0, 1)}
                results["errors"].append(traceback.format_exc())
                c.log(traceback.format_exc())
                rc = 1
                if not g.alive():
                    break
            write_json(out / "result.json", results)
            if ph == "C" and g.alive() and "C_saveload_pre" in results:
                # quit through the pause menu and relaunch: the cooldown must survive
                c.close_panels()
                c.bot.tap("ESC")
                if c.wait(lambda s: "pause" in (s.get("ui_stack") or []), 3.0) and c.click_button("Quit Game", exact=True, timeout=3.0):
                    c.click_button("Save & Quit", exact=True, timeout=4.0) or c.click_button("Quit without saving", exact=True, timeout=2.0)
                g.wait_exit = getattr(g, "wait_exit", None)
                t_q = time.time()
                while g.alive() and time.time() - t_q < 20:
                    time.sleep(0.5)
                g.stop()
                attempt += 1
                g2 = Game(out, f"g{attempt}", PORT_BASE + attempt, max_seconds=args.max_seconds, extra=["--no-wardrobe-notice"])
                g2.save_dir = g.save_dir
                g2.start()
                c2 = Cov(g2, out, results)
                phase_boot(c2)
                phase_C_reload(c2, results.get("C_saveload_pre", {}), g2.save_dir)
                g, c = g2, c2
                write_json(out / "result.json", results)
        errs = S4_errors(g.godot_log)
        results["script_errors"] = errs
    finally:
        results["finished"] = now()
        write_json(out / "result.json", results)
        write_json(out / "bugs.json", results.get("bugs", []))
        g.stop()
    return rc


def S4_errors(path: Path) -> list[str]:
    out = []
    if not path.exists():
        return out
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for i, ln in enumerate(lines):
        if ln.startswith(("SCRIPT ERROR", "ERROR", "USER ERROR", "USER SCRIPT ERROR")):
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            out.append(ln.strip() + (" | " + nxt if nxt.startswith("at:") else ""))
    return out[:80]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "qa" / "tmp" / "bot" / "cov_equip_companions" / "run1"))
    ap.add_argument("--phases", default="A,B,C,D,E")
    ap.add_argument("--start-save", default="", help="resume from a checkpoints/<phase>/ folder (or a slot1.json)")
    ap.add_argument("--attempt", type=int, default=0, help="port = 8100 + attempt (0..19)")
    ap.add_argument("--max-seconds", type=int, default=2400)
    args = ap.parse_args(argv)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
