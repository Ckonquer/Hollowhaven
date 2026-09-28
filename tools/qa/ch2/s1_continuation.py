"""Segment S1 - Krystal's continuation start (MP 20.4 Run A, first part), played with normal inputs only.

Route (the bot perceives the game through the read-only QA telemetry and acts only through keyboard/mouse
input; no teleport / flag / item cheats):
  title Continue on a COPY of the real Chapter-One-complete save (v1 -> v2 migration)
  -> migration checks (home structures, crops, pets, pouch, inventory; chests: the real save has none)
  -> pause menu "Save Game" (migration snapshot, save_integrity diff against the original, pre_v2_backup)
  -> the one-time wardrobe notice ("Open the wardrobe"; headless builds switch the notice off, then the pause
     menu's "Wardrobe" button opens the same panel) -> change hair style + hair colour + outfit, save preset 1
     and rename it by typing
  -> equipment: equip an owned armor/charm piece (none owned; the cheapest one is not cheap - see notes)
  -> read the Ward Stone -> "Follow the lantern road"
  -> gather missing waygate materials (8 wood, 4 stone, 2 copper ore) -> walk north of the Moonlit Ruin and
     repair the Lanternwake waygate -> "Travel to Hallowmere Reach"
  -> walk to the Commons: light the Commons arch, read the festival map
  -> Lantern Road home ("The Haven (home)"), check the house is untouched -> Ward Stone "Travel the Lantern Road"
     -> "Lanternwake Commons"
  -> walk a few metres, pause menu "Save Game" -> "Quit Game" -> "Quit without saving"
  -> relaunch -> title Continue -> verify area / position / appearance / flags / inventory / step.

Native start (a version-2 save the game wrote after New Game - "Meet Krystal" -> Chapter One -> the ending -> Chapter
Two accepted at the Ward Stone, i.e. the path a first-time player takes; detected by save_kind()): nothing is migrated,
so the migration steps become load_checks (the look is the one saved in the file, Chapter Two active when it was
accepted) and first_save_checks (no pre_v2_backup folder appears, version 2 and stats.started_version preserved, the
look and notice_shown unchanged); no wardrobe notice is expected (visible runs check that none appears; the wardrobe
is opened from the pause menu); the wardrobe picks an alternative where the save already wears a NEW_* choice; the
Ward Stone step reads the stone's Chapter Two menu (acceptance happened in Chapter One) and closes it; missing waygate
wood is also chopped from trees when the Haven's sticks run out. Version-1 starts behave exactly as before.

API: run(bot, out_dir, launcher=None, game=None, options=None) -> dict (status, checkpoints with timings, shots,
problems, bugs, notes, data, save-file checks). `bot` should be an s1_common.S1Bot (float look/clicks for the headless
1/30-scale UI); a plain hhbot.Bot works in visible runs. `launcher()` must (re)start the game on the SAME save folder
and return a fresh bot at the title; without it the segment saves through the pause menu, RESUMES (no quit) and
skips the relaunch, so a chained run can continue with the next segment in the same process. options: save_dir
(for the save-file checks; else launcher.save_dir / game.save_dir / out_dir/saves), original_save (v1 file to diff
against, default the real fixture), force_notice, no_migration_save, until (stop after that step), placed_bak.

CLI (headless source build, isolated run dir, never a visible window):
  python tools/qa/ch2/s1_continuation.py [--out qa/tmp/bot/s1/run1] [--attempt 1] [--seed 7] [--max-minutes 25]
      [--save <v1 or v2 slot json>] [--force-notice]   (--force-notice adds the debug-only presentation hook
      --ui-show=wardrobe_notice, a DIAGNOSTIC run: headless builds never show the notice on their own)
Writes <out>/s1_result.json, <out>/bugs.json, the logs, telemetry and save copies.
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
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import s1_common as C  # noqa: E402
from playthrough import Play, StepFailed  # noqa: E402

LEGACY_LOOK = {"hair": "side_braid", "hair_color": "auburn", "skin": "skin_2", "eyes": "eye_1",
               "upper": "explorer_jacket", "lower": "explorer_trousers", "shoes": "explorer_boots", "hat": "",
               "hair_acc": "flower_clip", "back": "satchel",
               "palette": {"primary": "teal", "secondary": "sunflower", "accent": "plum"}, "outfit": "cozy_explorer"}
# Wardrobe choices (data/appearance.gd names; all starter options, free for everyone).
NEW_HAIR = ("High Ponytail", "high_ponytail")
NEW_HAIR_COLOR = ("Honey", "honey")
NEW_OUTFIT = ("Strawberry Picnic", "strawberry_picnic")
# Used instead of a NEW_* choice when the start save already wears it (a native save's creation look), so every pick
# changes the look. Never needed for the v1 fixture (LEGACY_LOOK: side_braid / auburn / cozy_explorer).
ALT_HAIR = ("Twin Braids", "twin_braids")
ALT_HAIR_COLOR = ("Chestnut", "chestnut")
ALT_OUTFIT = ("Ribboned Adventurer", "ribboned_adventurer")
PRESET_NAME = "Autumn Picnic"
WAYGATE_COST = {"wood": 8, "stone": 4, "copper_ore": 2}
ARMOR_OR_CHARM = ["padded_hood", "padded_vest", "padded_boots", "copperwood_hood", "copperwood_vest", "copperwood_boots",
                  "ironwood_helm", "ironwood_mail", "ironwood_boots", "moonsteel_helm", "moonsteel_mail", "moonsteel_boots",
                  "gatherers_charm", "swiftstep_charm", "kindling_charm"]
# Surface route (data/world_layout.gd, surface_layout.gd PATHS "ruin"; the waygate is CH2_POINTS (-4, -86), its
# spawn 3 m south). Around the Ward Stone ring (r 2.9 at (0,-6), open to the south), then the ruin path, then east
# of the ruin's column ring (r 6.8 around (-12,-66)) north to the gate.
TO_WAYGATE = [(-4.6, -3.5), (-4.6, -9.0), (-2.0, -13.0), (-4.0, -25.0), (-7.0, -39.0), (-10.0, -51.0), (-3.0, -56.0),
              (-1.0, -66.0), (-2.0, -76.0), (-4.0, -82.5)]
# Reach (data/hallowmere_layout.gd): arrival (0,98) -> arrival road -> Commons arch (0,78); board (3.9,74.6).
REACH_TO_ARCH = [(0.0, 92.0), (0.0, 81.2)]
BOARD_STAND = (0.6, 76.3)        # north of the arch, in front of the festival board (it faces south-west)
SAVE_SPOT = (1.5, 68.0)          # inside the Commons (safe), a few metres past the arch
TREE_WORDS = ["Oak", "Tree", "Pine", "Birch", "Blossom"]     # choppable trees (playthrough.py's Chapter One words)


def save_kind(save: dict) -> str:
    """'v1': a version-1 (Chapter One) save, migrated by the first Continue. 'native_v2': a version-2 save begun with
    New Game in a 2.x build (stats.started_version 2.x) - what a first-time player has. 'v2': a version-2 save whose
    journey began before 2.0 (migrated earlier; nothing is migrated on this Continue either)."""
    try:
        ver = int(save.get("version") or 1)
    except (TypeError, ValueError):
        ver = 1
    if ver < 2:
        return "v1"
    sv = str(((save.get("state") or {}).get("stats") or {}).get("started_version") or "")
    major = sv.split(".")[0]
    return "native_v2" if major.isdigit() and int(major) >= 2 else "v2"


def wardrobe_choices(look: dict | None) -> list:
    """[(tab, (label, id), appearance key)] for hair style, hair colour and outfit: the NEW_* picks, or the ALT_* one
    where the start look already wears that NEW_* id (so each pick is a real change)."""
    look = look or {}
    out = []
    for tab, choice, alt, key in (("Hair", NEW_HAIR, ALT_HAIR, "hair"), ("Hair Colour", NEW_HAIR_COLOR, ALT_HAIR_COLOR, "hair_color"),
                                  ("Outfits", NEW_OUTFIT, ALT_OUTFIT, "outfit")):
        out.append((tab, alt if look.get(key) == choice[1] else choice, key))
    return out


class Seg(Play):
    """playthrough.Play (the Chapter One route helpers) on an S1Bot, plus S1 bookkeeping."""

    def __init__(self, bot, out: Path, shoot):
        super().__init__(SimpleNamespace(bot=bot, shot=shoot))
        self.out = out
        self.shoot = shoot
        self.checkpoints: list[dict] = []
        self.problems: list[dict] = []
        self.bugs: list[dict] = []
        self.notes: list[str] = []
        self.data: dict = {}
        self.t_start = time.time()

    # -------------------------------------------------------------- bookkeeping
    def problem(self, step: str, what: str, evidence: str = ""):
        self.log(f"PROBLEM [{step}]: {what}")
        self.problems.append({"step": step, "what": what, "evidence": evidence})

    def bug(self, title, severity, area, steps, expected, actual, evidence):
        self.log(f"BUG ({severity}) {title}")
        self.bugs.append({"title": title, "severity": severity, "area": area, "steps": steps, "expected": expected,
                          "actual": actual, "evidence": evidence})

    def note(self, text: str):
        self.log(f"NOTE: {text}")
        self.notes.append(text)

    def msg_t(self) -> float:
        ms = self.st().get("messages", [])
        return max([float(m.get("t", 0.0)) for m in ms] + [-1.0])

    def wait_msg(self, pred, since: float, timeout: float = 8.0):
        s = self.bot.wait_state(lambda s: any(float(m.get("t", 0)) > since and pred(m) for m in s.get("messages", [])), timeout)
        if not s:
            return None
        return [m for m in s.get("messages", []) if float(m.get("t", 0)) > since and pred(m)]

    def saved_after(self, since: float, timeout: float = 10.0) -> bool:
        return self.wait_msg(lambda m: m.get("k") == "saved" and "journey saved" in m.get("text", ""), since, timeout) is not None

    def recent_msgs(self, since: float) -> list:
        return [m for m in self.st().get("messages", []) if float(m.get("t", 0)) > since]

    def flags(self):
        return set(self.st().get("flags", []))

    def inv_totals(self) -> dict:
        return dict(self.st().get("inv", {}))

    def appearance(self):
        return self.st().get("appearance")

    def ui(self) -> list:
        return list(self.st().get("ui_stack", []))

    def wait_ui(self, name: str, timeout: float = 5.0, present: bool = True):
        return self.bot.wait_state(lambda s: (name in s.get("ui_stack", [])) == present, timeout)

    def wait_playing(self, area: str | None = None, timeout: float = 60.0):
        return self.bot.wait_state(lambda s: s.get("mode") == "playing" and (area is None or s.get("area") == area)
                                   and not s.get("ui_stack"), timeout)

    def button(self, text: str, exact: bool = True, enabled_only: bool = False):
        for b in self.bot.buttons():
            t = b.get("text", "")
            if ((t == text) if exact else (text.lower() in t.lower())) and (not enabled_only or not b.get("disabled")):
                return b
        return None

    def wait_button(self, text: str, timeout: float = 5.0):
        """Waits until a button with exactly this text is listed (telemetry refreshes buttons every 0.2 s)."""
        s = self.bot.wait_state(lambda s: any(b.get("text") == text for b in s.get("buttons", [])), timeout)
        return [b.get("text") for b in s.get("buttons", [])] if s else None

    def buttons_named(self, text: str) -> list:
        return [b for b in self.bot.buttons() if b.get("text") == text]

    def click_b(self, b: dict):
        cx, cy = C.button_center(b)
        self.bot.win.click(cx, cy)
        time.sleep(0.3)

    def nearest_named(self, name: str, maxd: float = 80.0):
        return self.nearest(lambda n: n.get("name") == name, maxd)

    def type_text(self, text: str):
        for ch in text:
            if ch == " ":
                self.bot.tap("SPACE", 0.04)
            elif ch.isalpha() and ch.isupper():
                self.bot.down("SHIFT")
                self.bot.tap(ch, 0.04)
                self.bot.up("SHIFT")
            else:
                self.bot.tap(ch.upper(), 0.04)
            time.sleep(0.03)

    def open_pause(self) -> bool:
        if "pause" in self.ui():
            return True
        for _ in range(3):
            self.bot.tap("ESC")
            if self.wait_ui("pause", 3.0):
                return True
            if self.ui():
                self.close_panels()
        return False

    def resume(self) -> bool:
        if "pause" not in self.ui():
            return not self.ui()
        if not self.bot.click_button("Resume", exact=True, timeout=3):
            self.bot.tap("ESC")
        return self.wait_ui("pause", 3.0, present=False) is not None

    def go(self, pts, tol=1.3, sprint=True, timeout=60.0) -> bool:
        for p in pts:
            if not self.goto(p, tol=tol, sprint=sprint, timeout=timeout):
                return False
        return True


# ================================================================================================ the segment
def run(bot, out_dir, launcher=None, game=None, options: dict | None = None) -> dict:
    """Plays segment S1 from the title screen (a v1 / v2 save in the game's save folder). See the module doc."""
    opt = dict(options or {})
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    save_dir = Path(opt.get("save_dir") or getattr(launcher, "save_dir", None) or getattr(game, "save_dir", out / "saves"))
    original = Path(opt.get("original_save") or C.REAL_SAVE)
    shots: list[dict] = []

    def shoot(label):
        rec = {"label": label}
        p = out / "shots" / f"s1_{len(shots) + 1:03d}_{label}.png"
        rec["path"] = str(p)
        try:
            bot.win.request({"shot": p.as_posix()}, timeout=20.0)
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001  (headless: "no screenshot in a headless run")
            rec["ok"] = False
            rec["error"] = str(e)[-120:]
        shots.append(rec)
        return rec["path"]

    p = Seg(bot, out, shoot)
    orig = C.load_json(original)
    ost = orig["state"]
    kind = save_kind(orig)
    native = kind != "v1"          # a version-2 start: nothing to migrate (see the module doc "Native start")
    chk_step = "load_checks" if native else "migration_checks"
    save_step = "first_save_checks" if native else "migration_save"
    choices = wardrobe_choices(ost.get("appearance") if native else None)
    p.data["start_kind"] = kind
    p.data["wardrobe_choices"] = {key: value for _tab, (_label, value), key in choices}
    res = {"segment": "S1", "status": "running", "checkpoints": p.checkpoints, "problems": p.problems, "bugs": p.bugs,
           "notes": p.notes, "shots": shots, "data": p.data, "save_dir": str(save_dir), "original_save": str(original),
           "start_kind": kind}

    def step(name, fn):
        t0 = time.time()
        bot.log(f"=== S1 STEP {name} ===")
        ok, err = False, ""
        try:
            r = fn()
            ok = True if r is None else bool(r)
        except StepFailed as e:
            err = f"StepFailed: {e}"
        except Exception as e:  # noqa: BLE001
            err = f"{type(e).__name__}: {e}"
            bot.log(traceback.format_exc())
        s = p.st()
        cp = {"step": name, "ok": ok, "seconds": round(time.time() - t0, 1), "t": round(time.time() - p.t_start, 1),
              "area": s.get("area"), "pos": s.get("player", {}).get("pos"), "ch2": (s.get("chapter2") or {}).get("current")}
        if err:
            cp["error"] = err
        p.checkpoints.append(cp)
        bot.log(f"=== S1 STEP {name}: {'OK' if ok else 'FAILED'} in {cp['seconds']}s {err}")
        shoot(name)
        if not ok:
            raise StepFailed(f"{name}: {err or 'check failed'}")

    headless = [False]

    # ------------------------------------------------------------------------------------------ steps
    def title_continue():
        s = bot.wait_state(lambda s: s.get("mode") == "title" and p.button("Continue") is not None, 120)
        if not s:
            raise StepFailed("title with Continue never appeared")
        headless[0] = list(s.get("window", [1, 1])) == [0, 0]
        p.data["headless"] = headless[0]
        b = p.button("Continue")
        if b.get("disabled"):
            raise StepFailed("Continue is disabled")
        t0 = time.time()
        if not bot.click_button("Continue", exact=True):
            raise StepFailed("could not click Continue")
        if not p.wait_playing("surface", 90):
            raise StepFailed(f"never reached gameplay (mode {p.st().get('mode')}, area {p.st().get('area')}, ui {p.ui()})")
        p.data["continue_load_s"] = round(time.time() - t0, 1)
        time.sleep(1.5)
        if not p.ui():
            bot.calibrate_look()      # else (a card is up) the first walk calibrates (S1Bot.ensure_calibrated)
        return True

    def migration_checks():
        s = p.st()
        ok = True
        found = {}
        # structures (home) - same id/position as in the original save
        for uid, rec in (ost.get("structures") or {}).items():
            if rec.get("area") != "surface":
                continue
            e = p.nearest_named("S_" + uid, 90)
            if not e:
                p.problem(chk_step, f"structure {uid} ({rec.get('id')}) not found near the Haven")
                ok = False
                continue
            d = C.dist2(C.xz(e["pos"]), (rec["pos"][0], rec["pos"][2]))
            found[uid] = {"id": rec.get("id"), "text": e.get("text"), "pos": e["pos"], "moved_m": round(d, 2)}
            if d > 0.3:
                p.problem(chk_step, f"structure {uid} moved {d:.2f} m")
                ok = False
        p.data["home_structures"] = found
        # crops
        for uid, crop in (ost.get("crops") or {}).items():
            e = p.nearest_named("S_" + uid, 90)
            txt = (e or {}).get("text", "")
            p.data.setdefault("crops", {})[uid] = {"crop": crop.get("crop"), "prompt": txt}
            if crop.get("crop", "").lower() not in txt.lower():
                p.problem(chk_step, f"crop plot {uid} prompt {txt!r} does not mention {crop.get('crop')}")
                ok = False
        # chests
        p.data["chests_in_original"] = len(ost.get("storages") or {})
        if not ost.get("storages") and native:
            p.note("the start save has no chests (storages {}); chest contents are only covered by the save_integrity diff")
        elif not ost.get("storages"):
            p.note("the real Chapter-One-complete save has no chests (storages {}); chest migration is only covered by "
                   "the save_integrity diff here")
        # pets
        comps = s.get("companions", {})
        nodes = s.get("companion_nodes", {})
        pets = {}
        for cid, rec in (ost.get("companions") or {}).items():
            pets[cid] = {"assignment": comps.get(cid), "node": bool(nodes.get(cid)), "expected": rec.get("assignment")}
            if comps.get(cid) != rec.get("assignment") or not nodes.get(cid):
                p.problem(chk_step, f"companion {cid}: {pets[cid]}")
                ok = False
        p.data["pets"] = pets
        # inventory / pouch / flags / quest
        v1_inv = {}
        for st in ost.get("inventory", []):
            if st:
                v1_inv[st["id"]] = v1_inv.get(st["id"], 0) + int(st["count"])
        if p.inv_totals() != v1_inv:
            p.problem(chk_step, f"inventory totals differ: {p.inv_totals()} vs {v1_inv}")
            ok = False
        if s.get("keys") != ost.get("key_items"):
            p.problem(chk_step, f"key pouch differs: {s.get('keys')} vs {ost.get('key_items')}")
            ok = False
        missing_flags = [f for f, v in (ost.get("flags") or {}).items() if v and f not in s.get("flags", [])]
        if missing_flags:
            p.problem(chk_step, f"flags lost: {missing_flags}")
            ok = False
        p.data["start_step"] = s.get("step")
        p.data["start_chapter2"] = s.get("chapter2")
        p.data["start_tracker"] = s.get("tracker")
        p.data["start_equipment"] = s.get("equipment")
        # position: Continue uses the saved outdoor position
        sp = ost.get("player", {}).get("pos")
        if sp:
            d = C.dist2(C.xz(p.pos()), (sp[0], sp[2]))
            p.data["continue_pos_error_m"] = round(d, 2)
            if d > 1.0:
                p.problem(chk_step, f"continued {d:.2f} m away from the saved position")
        # appearance (telemetry "appearance" when this build's telemetry has it)
        ap = s.get("appearance")
        p.data["start_appearance"] = ap
        want_look = (ost.get("appearance") or {}) if native else LEGACY_LOOK
        if ap is None:
            p.note("telemetry has no 'appearance' in this build: the look is checked in the saved files only")
        elif native and not want_look:
            p.problem(chk_step, "the version-2 start save has no appearance section")
            ok = False
        elif any(ap.get(k) != v for k, v in want_look.items()):
            p.problem(chk_step, f"loaded look differs from the one in the save: {ap} vs {want_look}" if native
                      else f"migrated look is not LEGACY_LOOK: {ap}")
            ok = False
        ch2 = s.get("chapter2") or {}
        if not native:
            if not ch2.get("available") or ch2.get("active"):
                p.problem(chk_step, f"chapter2 state after load: {ch2}")
                ok = False
        else:
            # a native save may already have accepted Chapter Two (the Ward Stone choice right after the ending)
            accepted = bool((ost.get("flags") or {}).get("ch2_accepted"))
            p.data["start_ch2_accepted"] = accepted
            if not ch2.get("available") or bool(ch2.get("active")) != accepted:
                p.problem(chk_step, f"chapter2 state after load: {ch2} (ch2_accepted in the save: {accepted})")
                ok = False
            p.data["start_notice_shown"] = (ost.get("wardrobe") or {}).get("notice_shown")
            p.data["start_started_version"] = (ost.get("stats") or {}).get("started_version")
        return ok

    def migration_save():
        """Pause menu -> Save Game right after loading: the first v2 write (upgrade backup + integrity diff)."""
        if not p.open_pause():
            raise StepFailed("pause menu did not open")
        since = p.msg_t()
        if not bot.click_button("Save Game", exact=True):
            raise StepFailed("no Save Game button")
        if not p.saved_after(since, 10):
            raise StepFailed(f"no 'journey saved' message; messages {p.recent_msgs(since)}")
        time.sleep(0.5)
        snap = out / "save_after_migration.json"
        shutil.copyfile(save_dir / "slot1.json", snap)
        p.data["migration_save"] = str(snap)
        # upgrade backup (spec 3.2)
        bdir = save_dir / "pre_v2_backup"
        backups = sorted(bdir.glob("slot1.v1-*.json")) if bdir.exists() else []
        p.data["pre_v2_backup"] = [str(b) for b in backups]
        p.data["pre_v2_backup_all"] = sorted(f.name for f in bdir.glob("*")) if bdir.exists() else []
        placed_bak = opt.get("placed_bak")
        if placed_bak:
            bb = sorted(bdir.glob("slot1.bak.v1-*.json")) if bdir.exists() else []
            if not bb:
                p.problem("migration_save", "slot1.bak.json (v1) was present but no pre_v2_backup/slot1.bak.v1-*.json was made")
                p.bug("v1 backup file not copied into pre_v2_backup", "major", "save/migration",
                      "Save folder with slot1.json + slot1.bak.json (v1); Continue; pause > Save Game",
                      "pre_v2_backup/slot1.bak.v1-<unix>.json (spec 3.2)", f"folder has {p.data['pre_v2_backup_all']}", str(bdir))
            elif bb[0].read_bytes() != Path(placed_bak).read_bytes():
                p.problem("migration_save", "pre_v2_backup slot1.bak copy differs from the v1 .bak file")
        if not backups:
            p.problem("migration_save", "no pre_v2_backup/slot1.v1-*.json after the first v2 write")
            p.bug("No pre-v2 upgrade backup after the first v2 save", "major", "save/migration",
                  "Continue a v1 save, pause > Save Game", "pre_v2_backup/slot1.v1-<unix>.json (spec 3.2)",
                  "folder missing/empty", str(bdir))
        elif backups[0].read_bytes() != original.read_bytes():
            p.problem("migration_save", "pre_v2_backup copy differs from the original v1 file")
        rep = integrity(original, snap, out / "integrity_after_migration.json")
        p.data["integrity_after_migration"] = summarize_integrity(rep)
        return True

    def first_save_checks():
        """Native start: pause menu -> Save Game right after loading a version-2 save. Nothing is migrated, so no
        pre_v2_backup folder may appear; the file stays version 2 with the journey's started_version, look and
        notice state (the save_integrity diff against the start file is informational: v2 vs v2)."""
        if not p.open_pause():
            raise StepFailed("pause menu did not open")
        since = p.msg_t()
        if not bot.click_button("Save Game", exact=True):
            raise StepFailed("no Save Game button")
        if not p.saved_after(since, 10):
            raise StepFailed(f"no 'journey saved' message; messages {p.recent_msgs(since)}")
        time.sleep(0.5)
        snap = out / "save_after_first_save.json"
        shutil.copyfile(save_dir / "slot1.json", snap)
        p.data["first_save"] = str(snap)
        bdir = save_dir / "pre_v2_backup"
        p.data["pre_v2_backup_all"] = sorted(f.name for f in bdir.glob("*")) if bdir.exists() else []
        p.data["pre_v2_backup_exists"] = bdir.exists()
        if bdir.exists():
            p.problem(save_step, f"a pre_v2_backup folder appeared for a version-2 save: {p.data['pre_v2_backup_all']}")
            p.bug("pre_v2_backup made for a save that needs no migration", "minor", "save/migration",
                  "Continue a version-2 (New Game) save, pause > Save Game", "no pre_v2_backup folder (only v1 saves are upgraded)",
                  f"folder has {p.data['pre_v2_backup_all']}", str(bdir))
        doc = C.load_json(snap)
        st = doc.get("state") or {}
        sv0 = (ost.get("stats") or {}).get("started_version")
        sv1 = (st.get("stats") or {}).get("started_version")
        p.data["first_save_file"] = {"version": doc.get("version"), "game_version": doc.get("game_version"),
                                     "started_version": sv1, "appearance": st.get("appearance"),
                                     "notice_shown": (st.get("wardrobe") or {}).get("notice_shown")}
        if not isinstance(doc.get("version"), int) or doc.get("version") < 2:
            p.problem(save_step, f"saved file version is {doc.get('version')!r}, expected 2+")
        if sv1 != sv0:
            p.problem(save_step, f"stats.started_version changed from {sv0!r} to {sv1!r}")
        if ost.get("appearance") and st.get("appearance") != ost.get("appearance"):
            p.problem(save_step, f"saved look differs from the start look: {st.get('appearance')} vs {ost.get('appearance')}")
        n0 = (ost.get("wardrobe") or {}).get("notice_shown")
        if n0 is not None and (st.get("wardrobe") or {}).get("notice_shown") != n0:
            p.problem(save_step, f"wardrobe.notice_shown changed from {n0} to {(st.get('wardrobe') or {}).get('notice_shown')}")
        rep = integrity(original, snap, out / "integrity_after_first_save.json")
        p.data["integrity_after_first_save"] = summarize_integrity(rep)
        return True

    def wardrobe():
        """The one-time notice (visible builds) or the pause menu's Wardrobe (headless: the notice is off)."""
        via = ""
        if native and not opt.get("force_notice"):
            # a native save chose its look at creation and has notice_shown: the one-time notice must not appear
            if not headless[0]:
                if "pause" in p.ui():
                    p.resume()
                s = bot.wait_state(lambda s: "confirm" in s.get("ui_stack", []) and any(b.get("text") == "Open the wardrobe" for b in s.get("buttons", [])), 6)
                p.data["wardrobe_notice"] = "shown (unexpected for a native save)" if s else "not shown within 6 s (expected: native save)"
                if s:
                    shoot("wardrobe_notice_unexpected")
                    p.problem("wardrobe", "the one-time wardrobe notice appeared for a native save (notice_shown was true)")
                    if bot.click_button("Open the wardrobe", exact=True):
                        via = "notice"
            else:
                p.note("wardrobe notice: native save (none expected; headless builds switch it off anyway); opened the "
                       "wardrobe from the pause menu")
        elif headless[0] and not opt.get("force_notice"):
            p.note("wardrobe notice: headless builds switch the automatic notice off (ui_root.gd: wardrobe_notice_enabled "
                   "= DisplayServer.get_name() != 'headless'); opened the wardrobe from the pause menu instead")
        else:
            if "pause" in p.ui():
                p.resume()
            s = bot.wait_state(lambda s: "confirm" in s.get("ui_stack", []) and any(b.get("text") == "Open the wardrobe" for b in s.get("buttons", [])), 12)
            if s:
                p.data["wardrobe_notice"] = "shown"
                shoot("wardrobe_notice")
                if not bot.click_button("Open the wardrobe", exact=True):
                    raise StepFailed("could not click 'Open the wardrobe'")
                via = "notice"
            else:
                p.data["wardrobe_notice"] = "not shown within 12 s"
                p.problem("wardrobe", "the wardrobe notice did not appear within 12 s of safe play after Continue")
        if not via:
            if not p.open_pause():
                raise StepFailed("pause menu did not open")
            if not bot.click_button("Wardrobe", exact=True):
                raise StepFailed("no Wardrobe button in the pause menu")
            via = "pause menu"
        if not p.wait_ui("wardrobe", 5):
            raise StepFailed(f"wardrobe panel did not open (ui {p.ui()})")
        p.data["wardrobe_opened_via"] = via
        time.sleep(0.6)
        changed = {}
        # hair style, hair colour, outfit
        for tab, (label, value), key in choices:
            if not bot.click_button(tab, exact=True):
                raise StepFailed(f"no wardrobe tab {tab!r}")
            time.sleep(0.4)
            tile = p.button(label)
            if not tile:
                raise StepFailed(f"no tile {label!r} under {tab}; buttons {[b['text'] for b in bot.buttons()][:60]}")
            if tile.get("clipped"):
                p.problem("wardrobe", f"tile {label!r} is scrolled out of view")
            p.click_b(tile)
            time.sleep(0.4)
            ap = p.appearance()
            if ap is not None:
                if ap.get(key) != value:
                    # one retry (a click can land in the 10 px gap between tiles)
                    p.click_b(p.button(label) or tile)
                    time.sleep(0.4)
                    ap = p.appearance()
                changed[key] = ap.get(key)
                if ap.get(key) != value:
                    raise StepFailed(f"{key} is {ap.get(key)!r} after clicking {label!r}")
        ap = p.appearance()
        if ap is not None and ap.get("hair") != p.data["wardrobe_choices"]["hair"]:
            p.problem("wardrobe", f"choosing the outfit changed the hair style to {ap.get('hair')!r} (outfits must keep hair)")
        p.data["look_after_edit"] = ap
        shoot("wardrobe_new_look")
        # preset 1: "Save here" (the only enabled one while no preset exists), then Rename by typing
        saves = p.buttons_named("Save here")
        wears0 = [b.get("disabled") for b in p.buttons_named("Wear")]
        enabled = [b for b in saves if not b.get("disabled")]
        if not enabled:
            raise StepFailed(f"no enabled 'Save here' (buttons {len(saves)})")
        target = min(enabled, key=lambda b: C.button_center(b)[1])
        p.click_b(target)
        time.sleep(0.5)
        wears1 = [b.get("disabled") for b in p.buttons_named("Wear")]
        p.data["preset_wear_buttons_disabled_before_after"] = [wears0, wears1]
        if not wears1 or wears1[0] is not False:
            raise StepFailed(f"preset 1 not saved: Wear buttons disabled {wears1}")
        ren = [b for b in p.buttons_named("Rename") if not b.get("disabled")]
        if ren:
            p.click_b(min(ren, key=lambda b: C.button_center(b)[1]))
            time.sleep(0.4)
            # the LineEdit gets the focus with its text selected: typing replaces it, Enter commits
            p.type_text(PRESET_NAME)
            bot.tap("ENTER")
            time.sleep(0.5)
            p.data["preset_renamed_to"] = PRESET_NAME
        else:
            p.problem("wardrobe", "Rename stayed disabled after saving preset 1")
        shoot("wardrobe_preset")
        if not bot.click_button("Done", exact=True):
            raise StepFailed("no Done button")
        if not p.wait_ui("wardrobe", 4, present=False):
            raise StepFailed("wardrobe did not close")
        if "pause" in p.ui():
            p.resume()
        if not p.wait_playing(timeout=6):
            p.close_panels()
        p.data["look_changed"] = changed
        return True

    def equipment():
        s = p.st()
        owned = [i for i in ARMOR_OR_CHARM if s.get("inv", {}).get(i)]
        eq = s.get("equipment") or {}
        p.data["equipment_before"] = eq
        if not owned and native:
            p.note("equipment: skipped - no armor or charm is owned yet in this New-Game journey"
                   + (" (the Tailor's Cache is done, but no Woven Cloth has been woven)" if "c1x_tailor_cache" in p.flags() else ""))
            p.data["equipment"] = "skipped: none owned"
            return True
        if not owned:
            p.note("equipment: skipped - no armor or charm is owned (the save predates equipment) and none is cheap to "
                   "craft here: every armor recipe needs Woven Cloth (Loom, recipe unlocked by the optional Tailor's Cache "
                   "flag c1x_tailor_cache, plus 3 Sunflax per 2 cloth) and the cheapest charm (Gatherer's Charm) needs "
                   "2 Resin + 2 Copper Bars (Furnace)")
            p.data["equipment"] = "skipped: none owned / not cheaply craftable"
            return True
        # (a later chained run may own a piece: equip it from the backpack by double-clicking its slot)
        item = owned[0]
        if not p.open_panel("TAB", "inventory"):
            raise StepFailed("inventory did not open")
        time.sleep(0.4)
        r = None
        for b in bot.buttons():
            if b["text"].startswith("slot:bag:") and b.get("item") == item:
                r = b
        if r:
            p.click_b(r)
            time.sleep(0.1)
            p.click_b(r)
            time.sleep(0.6)
        p.close_panels()
        eq2 = p.st().get("equipment") or {}
        p.data["equipment_after"] = eq2
        if item not in eq2.values():
            p.problem("equipment", f"double-clicking {item} did not equip it: {eq2}")
        return True

    def ward_stone():
        e = p.nearest_named("WardStone", 40)
        if not e:
            raise StepFailed("no Ward Stone nearby")
        since = p.msg_t()
        if native and "ch2_accepted" in p.flags():
            return ward_stone_menu(e, since)

        def asked():
            return "confirm" in p.ui() or "ch2_accepted" in p.flags()
        if not p.press_interact_on(e, ["Read the Ward Stone"], asked, stop=2.2):
            raise StepFailed(f"could not read the Ward Stone (prompt {p.prompt()})")
        if "ch2_accepted" not in p.flags():
            if not p.wait_button("Follow the lantern road", 5):
                raise StepFailed(f"no acceptance choice; buttons {[b['text'] for b in bot.buttons()]}")
            shoot("ward_stone_choice")
            if not bot.click_button("Follow the lantern road", exact=True):
                raise StepFailed("could not click 'Follow the lantern road'")
        if not bot.wait_state(lambda s: "ch2_accepted" in s.get("flags", []), 5):
            raise StepFailed("ch2_accepted not set")
        s = bot.wait_state(lambda s: "ch2_waygate" in (s.get("chapter2") or {}).get("current", []), 8)
        p.data["ward_stone_lines"] = [m["text"] for m in p.recent_msgs(since) if m.get("k") in ("say", "notify", "quest", "hint")]
        if not s:
            p.problem("ward_stone", f"chapter2 current step is {(p.st().get('chapter2') or {}).get('current')} after accepting")
        p.wait_playing(timeout=6)
        return True

    def ward_stone_menu(e, since):
        """Native start: Chapter Two was accepted at the Ward Stone right after the Chapter One ending, so reading
        the stone now opens its Chapter Two menu (ward_stone.gd menu_options: Read the inscription / Change your look
        / [Travel the Lantern Road once an arch is lit] / Close). Records it and closes it."""
        p.data["ward_stone"] = "accepted before S1 (Chapter One ending flow)"
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed(f"the Ward Stone menu did not open (prompt {p.prompt()})")
        menu = p.wait_button("Close", 5) or [b.get("text") for b in bot.buttons()]
        p.data["ward_stone_menu_after_acceptance"] = menu
        shoot("ward_stone_menu")
        missing = [x for x in ("Read the inscription", "Change your look", "Close") if x not in menu]
        if missing:
            p.problem("ward_stone", f"the Ward Stone menu lacks {missing}: {menu}")
        if not bot.click_button("Close", exact=True):
            bot.tap("ESC")
        if not p.wait_playing(timeout=6):
            p.close_panels()
        cur = (p.st().get("chapter2") or {}).get("current") or []
        p.data["ward_stone_ch2_current"] = cur
        if "ch2_waygate" not in cur:
            p.problem("ward_stone", f"chapter2 current step is {cur}, expected ch2_waygate")
        p.data["ward_stone_lines"] = [m["text"] for m in p.recent_msgs(since) if m.get("k") in ("say", "notify", "quest", "hint")]
        return True

    def materials():
        have = {k: int(p.inv_totals().get(k, 0)) for k in WAYGATE_COST}
        miss = {k: v - have[k] for k, v in WAYGATE_COST.items() if have[k] < v}
        p.data["waygate_materials_before"] = have
        if not miss:
            p.note(f"waygate materials: nothing missing (the save carries {have})")
            return True
        p.log(f"gathering missing waygate materials {miss}")
        if "wood" in miss and not native:
            p.gather_hand(["Stick"], "wood", WAYGATE_COST["wood"], maxd=60)
        elif "wood" in miss:
            # a New-Game journey spends its wood in Chapter One: sticks first, then the axe on a tree (like a player)
            try:
                p.gather_hand(["Stick"], "wood", WAYGATE_COST["wood"], maxd=60)
            except StepFailed as ex:
                p.note(f"waygate wood: {ex} - chopping a tree for the rest")
            if p.inv("wood") < WAYGATE_COST["wood"]:
                if not any(v and k.endswith("_axe") for k, v in p.inv_totals().items()):
                    raise StepFailed(f"wood short ({p.inv('wood')}/{WAYGATE_COST['wood']}) and no axe")
                p.harvest_tool(TREE_WORDS, "wood", WAYGATE_COST["wood"], maxd=60)
        if "stone" in miss:
            p.gather_hand(["Stone"], "stone", WAYGATE_COST["stone"], maxd=60)
        if "copper_ore" in miss:
            if p.inv("stone_pickaxe") + p.inv("copper_pickaxe") < 1:
                raise StepFailed("copper ore needed but no pickaxe")
            p.harvest_tool(["Copper"], "copper_ore", WAYGATE_COST["copper_ore"], maxd=80)
        have2 = {k: int(p.inv_totals().get(k, 0)) for k in WAYGATE_COST}
        p.data["waygate_materials_after_gather"] = have2
        return all(have2[k] >= v for k, v in WAYGATE_COST.items())

    def waygate():
        t0 = time.time()
        if not p.go(TO_WAYGATE, tol=1.5):
            raise StepFailed(f"could not walk to the waygate (at {p.pos()})")
        p.data["walk_to_waygate_s"] = round(time.time() - t0, 1)
        e = p.nearest_named("Waygate", 20)
        if not e:
            raise StepFailed("no Waygate in telemetry near (-4,-86)")
        p.data["waygate_prompt_before"] = e.get("text"), e.get("enabled")
        inv0 = p.inv_totals()
        if not p.press_interact_on(e, ["Repair the waygate"], lambda: "ch2_waygate_repaired" in p.flags(), stop=2.0):
            raise StepFailed(f"repair failed; prompt {p.prompt()}")
        time.sleep(0.8)
        inv1 = p.inv_totals()
        spent = {k: inv0.get(k, 0) - inv1.get(k, 0) for k in WAYGATE_COST}
        p.data["waygate_spent"] = spent
        if spent != WAYGATE_COST:
            p.problem("waygate", f"repair took {spent}, expected {WAYGATE_COST}")
        shoot("waygate_repaired")
        return True

    def travel_reach():
        e = p.nearest_named("Waygate", 20)
        since = p.msg_t()
        t0 = time.time()
        if not p.press_interact_on(e, ["Travel to Hallowmere Reach"], lambda: p.st().get("mode") != "playing" or p.st().get("area") != "surface", stop=2.0):
            raise StepFailed(f"no travel; prompt {p.prompt()}")
        if not p.wait_playing("hallowmere_reach", 120):
            raise StepFailed(f"never arrived in the Reach (area {p.st().get('area')}, mode {p.st().get('mode')})")
        p.data["reach_load_s"] = round(time.time() - t0, 1)
        if not p.saved_after(since, 10):
            p.problem("travel_reach", "no autosave message after arriving in the Reach")
        time.sleep(1.0)
        pos = p.pos()
        p.data["reach_arrival_pos"] = pos
        if C.dist2(C.xz(pos), (0, 98)) > 4:
            p.problem("travel_reach", f"arrived at {pos}, expected near waygate_arrival (0, 98)")
        bot.calibrate_look()
        return True

    def commons_arch():
        if not p.go(REACH_TO_ARCH, tol=1.2):
            raise StepFailed(f"could not walk to the Commons arch (at {p.pos()})")
        e = p.nearest_named("LanternArch_commons", 20)
        if not e:
            raise StepFailed("no LanternArch_commons nearby")
        if not p.press_interact_on(e, ["Light the lantern arch"], lambda: "ch2_arch_commons" in p.flags(), stop=1.9):
            raise StepFailed(f"arch not lit; prompt {p.prompt()}")
        shoot("commons_arch_lit")
        return True

    def festival_map():
        # through the arch first (its posts stand at x = +-1.25 on the straight line to the board)
        p.goto(BOARD_STAND, tol=0.8, sprint=False)
        e = p.nearest_named("BoardInteract", 20)
        if not e:
            raise StepFailed("no festival board")
        since = p.msg_t()
        inv0 = p.inv_totals()
        if not p.press_interact_on(e, ["Read the festival map"], lambda: "ch2_read_festival_map" in p.flags(), stop=1.8):
            raise StepFailed(f"board not read; prompt {p.prompt()}")
        s = bot.wait_state(lambda s: "ch2_commons" in (s.get("chapter2") or {}).get("done", []), 6)
        if not s:
            p.problem("festival_map", f"ch2_commons not completed: {p.st().get('chapter2')}")
        time.sleep(0.8)
        inv1 = p.inv_totals()
        p.data["commons_reward"] = {k: inv1.get(k, 0) - inv0.get(k, 0) for k in inv1 if inv1.get(k, 0) != inv0.get(k, 0)}
        p.data["after_commons_chapter2"] = (p.st().get("chapter2") or {}).get("current")
        p.data["festival_lines"] = [m["text"] for m in p.recent_msgs(since)]
        shoot("festival_map")
        return True

    def lantern_road_home():
        e = p.nearest_named("LanternArch_commons", 25)
        if not e:
            raise StepFailed("no arch")
        if not p.press_interact_on(e, ["Travel the Lantern Road"], lambda: "confirm" in p.ui(), stop=1.9):
            raise StepFailed(f"no travel list; prompt {p.prompt()}")
        opts = p.wait_button("The Haven (home)", 5) or [b["text"] for b in bot.buttons()]
        p.data["lantern_road_list_at_commons"] = opts
        shoot("lantern_road_list")
        since = p.msg_t()
        t0 = time.time()
        if not bot.click_button("The Haven (home)", exact=True):
            raise StepFailed(f"no Haven destination; buttons {opts}")
        if not p.wait_playing("surface", 120):
            raise StepFailed("did not arrive at the Haven")
        p.data["haven_load_s"] = round(time.time() - t0, 1)
        if not p.saved_after(since, 10):
            p.problem("lantern_road_home", "no autosave after the Lantern Road trip home")
        time.sleep(1.5)
        p.data["haven_arrival_pos"] = p.pos()
        # the house is untouched
        ok = True
        home = {}
        for uid, rec in (ost.get("structures") or {}).items():
            e = p.nearest_named("S_" + uid, 60)
            if not e:
                ok = False
                p.problem("lantern_road_home", f"structure {uid} missing after the trip")
                continue
            d = C.dist2(C.xz(e["pos"]), (rec["pos"][0], rec["pos"][2]))
            home[uid] = {"text": e.get("text"), "moved_m": round(d, 2)}
            if d > 0.3:
                ok = False
                p.problem("lantern_road_home", f"structure {uid} moved {d:.2f} m")
        p.data["home_after_trip"] = home
        comps = p.st().get("companions", {})
        p.data["pets_after_trip"] = comps
        for cid, rec in (ost.get("companions") or {}).items():
            if comps.get(cid) != rec.get("assignment"):
                ok = False
                p.problem("lantern_road_home", f"companion {cid} is {comps.get(cid)}")
        shoot("haven_after_trip")
        if not ok:
            p.bug("Home changed after a Lantern Road trip", "major", "surface / lantern road",
                  "Commons arch > Travel the Lantern Road > The Haven (home)", "structures, crops and pets unchanged",
                  json.dumps(home), "telemetry nearby")
        return ok

    def lantern_road_back():
        bot.calibrate_look()
        e = p.nearest_named("WardStone", 40)
        if not e:
            raise StepFailed("no Ward Stone")
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed(f"no Ward Stone menu; prompt {p.prompt()}")
        menu = p.wait_button("Travel the Lantern Road", 5) or [b["text"] for b in bot.buttons()]
        p.data["ward_stone_menu"] = menu
        shoot("ward_stone_menu")
        if not bot.click_button("Travel the Lantern Road", exact=True):
            raise StepFailed(f"no 'Travel the Lantern Road' in the Ward Stone menu {menu}")
        s = bot.wait_state(lambda s: any(b.get("text") == "Lanternwake Commons" for b in s.get("buttons", [])), 5)
        if not s:
            raise StepFailed(f"no travel list after the Ward Stone menu; buttons {[b['text'] for b in bot.buttons()]}")
        p.data["lantern_road_list_at_haven"] = [b["text"] for b in s.get("buttons", [])]
        since = p.msg_t()
        t0 = time.time()
        if not bot.click_button("Lanternwake Commons", exact=True):
            raise StepFailed("could not click Lanternwake Commons")
        if not p.wait_playing("hallowmere_reach", 120):
            raise StepFailed("did not arrive back in the Reach")
        p.data["reach_again_load_s"] = round(time.time() - t0, 1)
        if not p.saved_after(since, 10):
            p.problem("lantern_road_back", "no autosave after the Lantern Road trip back")
        time.sleep(1.0)
        pos = p.pos()
        p.data["commons_arrival_pos"] = pos
        if C.dist2(C.xz(pos), (0, 75)) > 4:
            p.problem("lantern_road_back", f"arrived at {pos}, expected the commons_arch spawn (0, 75)")
        bot.calibrate_look()
        return True

    def save_and_quit():
        if not p.goto(SAVE_SPOT, tol=1.0, sprint=False):
            p.problem("save_and_quit", f"could not reach the save spot; saving at {p.pos()}")
        time.sleep(0.8)
        if not p.open_pause():
            raise StepFailed("pause menu did not open")
        since = p.msg_t()
        if not bot.click_button("Save Game", exact=True):
            raise StepFailed("no Save Game")
        if not p.saved_after(since, 10):
            raise StepFailed(f"no 'journey saved'; messages {p.recent_msgs(since)}")
        s = p.st()
        p.data["saved_state"] = {"area": s.get("area"), "pos": s.get("player", {}).get("pos"), "appearance": s.get("appearance"),
                                 "flags": sorted(s.get("flags", [])), "inv": s.get("inv"), "keys": s.get("keys"),
                                 "chapter2": s.get("chapter2"), "equipment": s.get("equipment"), "companions": s.get("companions"),
                                 "hp": s.get("player", {}).get("hp")}
        time.sleep(0.5)
        shutil.copyfile(save_dir / "slot1.json", out / "save_at_quit.json")
        shoot("pause_saved")
        if launcher is None:
            # chained use without a launcher: keep this process (and the bot) alive for the next segment
            p.note("quit + relaunch skipped (run() got no launcher): saved through the pause menu and resumed")
            p.resume()
            return True
        if not bot.click_button("Quit Game", exact=True):
            raise StepFailed("no Quit Game")
        s = bot.wait_state(lambda s: any(b.get("text") == "Quit without saving" for b in s.get("buttons", [])), 5)
        if not s:
            raise StepFailed(f"no quit confirmation; buttons {[b['text'] for b in bot.buttons()]}")
        p.data["quit_confirm_buttons"] = [b["text"] for b in s.get("buttons", []) if b.get("text") in ("Save & Quit", "Quit without saving", "Cancel")]
        bot.click_button("Quit without saving", exact=True)
        t0 = time.time()
        exited = False
        proc = getattr(game, "proc", None) or getattr(launcher, "proc", None)
        while time.time() - t0 < 20:
            if proc is not None and proc.poll() is not None:
                exited = True
                break
            time.sleep(0.3)
        p.data["quit_exit_s"] = round(time.time() - t0, 1) if exited else None
        if proc is not None and not exited:
            p.problem("save_and_quit", "the game did not exit within 20 s of 'Quit without saving'")
        return True

    def relaunch_continue():
        nonlocal bot
        if launcher is None:
            p.note("relaunch skipped: no launcher given to run()")
            return True
        bot2 = launcher()
        p.bot = bot2
        p.log = bot2.log
        bot = bot2
        s = bot2.wait_state(lambda s: s.get("mode") == "title" and any(b.get("text") == "Continue" for b in s.get("buttons", [])), 120)
        if not s:
            raise StepFailed("no title/Continue after relaunch")
        t0 = time.time()
        if not bot2.click_button("Continue", exact=True):
            raise StepFailed("could not click Continue")
        if not p.wait_playing(None, 120):
            raise StepFailed("relaunch Continue never reached gameplay")
        p.data["relaunch_continue_load_s"] = round(time.time() - t0, 1)
        time.sleep(2.0)
        s = p.st()
        saved = p.data.get("saved_state", {})
        v = {"area": s.get("area"), "pos": s.get("player", {}).get("pos"), "appearance": s.get("appearance"),
             "chapter2": (s.get("chapter2") or {}).get("current"), "equipment": s.get("equipment")}
        p.data["after_relaunch"] = v
        ok = True
        if s.get("area") != saved.get("area"):
            ok = False
            p.problem("relaunch_continue", f"area {s.get('area')} != saved {saved.get('area')}")
        if saved.get("pos") and v["pos"]:
            d = C.dist2(C.xz(v["pos"]), C.xz(saved["pos"]))
            p.data["relaunch_pos_error_m"] = round(d, 2)
            if d > 1.5:
                ok = False
                p.problem("relaunch_continue", f"continued {d:.2f} m from the saved position {saved['pos']} -> {v['pos']}")
        if saved.get("appearance") is not None and s.get("appearance") != saved.get("appearance"):
            ok = False
            p.problem("relaunch_continue", f"appearance differs after relaunch: {s.get('appearance')} vs {saved.get('appearance')}")
        lost = [f for f in saved.get("flags", []) if f not in s.get("flags", [])]
        if lost:
            ok = False
            p.problem("relaunch_continue", f"flags lost after relaunch: {lost}")
        if s.get("inv") != saved.get("inv"):
            ok = False
            p.problem("relaunch_continue", f"inventory differs after relaunch: {s.get('inv')} vs {saved.get('inv')}")
        if s.get("keys") != saved.get("keys"):
            ok = False
            p.problem("relaunch_continue", f"key pouch differs: {s.get('keys')} vs {saved.get('keys')}")
        if (s.get("chapter2") or {}).get("current") != (saved.get("chapter2") or {}).get("current"):
            ok = False
            p.problem("relaunch_continue", f"chapter2 step differs: {(s.get('chapter2') or {}).get('current')}")
        if s.get("companions") != saved.get("companions"):
            p.problem("relaunch_continue", f"companions differ: {s.get('companions')} vs {saved.get('companions')}")
        shoot("after_relaunch")
        return ok

    # --------------------------------------------------------------------------------------- driver
    steps = [("title_continue", title_continue), (chk_step, migration_checks)]
    if not opt.get("no_migration_save"):
        steps.append((save_step, first_save_checks if native else migration_save))
    steps += [("wardrobe", wardrobe), ("equipment", equipment), ("ward_stone", ward_stone), ("materials", materials),
              ("waygate", waygate), ("travel_reach", travel_reach), ("commons_arch", commons_arch),
              ("festival_map", festival_map), ("lantern_road_home", lantern_road_home),
              ("lantern_road_back", lantern_road_back), ("save_and_quit", save_and_quit),
              ("relaunch_continue", relaunch_continue)]
    stop_after = opt.get("until", "")
    try:
        for name, fn in steps:
            step(name, fn)
            if stop_after and name == stop_after:
                break
        res["status"] = "completes"
    except StepFailed as e:
        res["status"] = f"stops at {e}"
    except Exception as e:  # noqa: BLE001  (transport died etc.)
        res["status"] = f"stops: {type(e).__name__}: {e}"
        bot.log(traceback.format_exc())
    res["seconds"] = round(time.time() - p.t_start, 1)
    # post-run save diff against the original
    final = save_dir / "slot1.json"
    if final.exists():
        shutil.copyfile(final, out / "save_final.json")
        rep = integrity(original, out / "save_final.json", out / "integrity_final.json")
        res["integrity_final"] = summarize_integrity(rep)
        v2 = C.load_json(out / "save_final.json")["state"]
        res["final_save_look"] = v2.get("appearance")
        res["final_save_presets"] = (v2.get("wardrobe") or {}).get("presets")
        res["final_save_notice_shown"] = (v2.get("wardrobe") or {}).get("notice_shown")
        if res["status"] == "completes" and not stop_after:
            check_final_save(p, v2, res)
    res["checkpoints_reached"] = [c["step"] for c in p.checkpoints if c["ok"]]
    return res


# ================================================================================================ save checks
def integrity(v1: Path, v2: Path, out: Path) -> dict:
    import save_integrity  # tools/qa/save_integrity.py (read-only use)
    try:
        rep = save_integrity.build_report(str(v1), str(v2))
    except Exception as e:  # noqa: BLE001
        rep = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    out.write_text(json.dumps(rep, indent=1), encoding="utf-8")
    return rep


# Mismatch paths the route itself explains (gameplay after loading), everything else is suspicious.
ROUTE_EXPLAINED = ("total_minutes", "stats/", "player/", "flags/", "counters/", "inventory[", "hotbar_index",
                   "depleted/", "lore", "quests/baselines", "companions/")


def summarize_integrity(rep: dict) -> dict:
    mm = rep.get("preserved_mismatches", []) or []
    explained = [m for m in mm if any(str(m.get("path", "")).startswith(k) for k in ROUTE_EXPLAINED)]
    other = [m for m in mm if m not in explained]
    return {"ok": rep.get("ok"), "error": rep.get("error"), "missing_v2_sections": rep.get("missing_v2_sections"),
            "mismatches": len(mm), "explained_by_play": [m.get("path") for m in explained],
            "unexplained": other, "allowed_changes": len(rep.get("allowed_changes", []) or []),
            "v1_summary": (rep.get("v1") or {}).get("summary"), "v2_summary": (rep.get("v2") or {}).get("summary")}


def check_final_save(p: Seg, st: dict, res: dict):
    look = st.get("appearance") or {}
    want = p.data.get("wardrobe_choices") or {"hair": NEW_HAIR[1], "hair_color": NEW_HAIR_COLOR[1], "outfit": NEW_OUTFIT[1]}
    if look.get("hair") != want["hair"] or look.get("hair_color") != want["hair_color"] or look.get("outfit") != want["outfit"]:
        p.problem("final_save", f"saved look is not the wardrobe choice: {look}")
    pres = (st.get("wardrobe") or {}).get("presets") or []
    if not pres:
        p.problem("final_save", "no saved preset in the save file")
    elif p.data.get("preset_renamed_to") and pres[0].get("name") != p.data["preset_renamed_to"]:
        p.problem("final_save", f"preset 1 is named {pres[0].get('name')!r}, typed {p.data['preset_renamed_to']!r}")
    fl = st.get("flags") or {}
    for f in ("ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map"):
        if not fl.get(f):
            p.problem("final_save", f"flag {f} missing in the final save")
    if st.get("structures") != p_orig_structures(res):
        p.problem("final_save", "structures differ from the original save")


def p_orig_structures(res: dict):
    return C.load_json(Path(res["original_save"]))["state"].get("structures")


# ================================================================================================ CLI
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(C.ROOT / "qa" / "tmp" / "bot" / "s1" / "run1"))
    ap.add_argument("--attempt", type=int, default=1, help="port = 7100 + attempt (bumped if taken)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--save", default=str(C.REAL_SAVE), help="v1/v2 slot json to start from (a COPY is used)")
    ap.add_argument("--max-minutes", type=float, default=25.0, help="hard bound for each game process")
    ap.add_argument("--force-notice", action="store_true",
                    help="DIAGNOSTIC: add the debug-only --ui-show=wardrobe_notice (headless never shows the notice itself)")
    ap.add_argument("--no-migration-save", action="store_true")
    ap.add_argument("--until", default="")
    ap.add_argument("--with-bak", action="store_true",
                    help="also place the fixture's .bak.json as slot1.bak.json (a real player's folder has one)")
    a = ap.parse_args(argv)
    out = Path(a.out).resolve()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    save_dir = out / "saves"
    bak = Path(a.save).with_name(Path(a.save).name.replace(".json", ".bak.json")) if a.with_bak else None
    C.prepare_saves(save_dir, Path(a.save), bak)
    extra = ["--ui-show=wardrobe_notice"] if a.force_notice else []
    games: list[C.HeadlessGame] = []

    def launch() -> C.HeadlessGame:
        port = C.pick_port(1, a.attempt + 10 * len(games))
        g = C.HeadlessGame(out, f"s1_{len(games) + 1}", port, save_dir=save_dir, max_seconds=int(a.max_minutes * 60),
                           seed=a.seed, extra=extra)
        games.append(g)
        g.start()
        return g

    class Launcher:
        def __init__(self):
            self.save_dir = save_dir
            self.proc = None

        def __call__(self):
            if games and games[-1].alive():
                games[-1].stop()
            g = launch()
            self.proc = g.proc
            return g.bot

    t0 = time.time()
    g1 = launch()
    lnch = Launcher()
    lnch.proc = g1.proc
    res = {}
    try:
        res = run(g1.bot, out, launcher=lnch, game=g1,
                  options={"save_dir": str(save_dir), "original_save": a.save, "force_notice": a.force_notice,
                           "placed_bak": str(bak) if bak is not None and bak.exists() else "",
                           "no_migration_save": a.no_migration_save, "until": a.until})
    finally:
        for g in games:
            g.stop()
    res["wall_seconds"] = round(time.time() - t0, 1)
    res["diagnostic_fixture_start"] = Path(a.save).resolve() != C.REAL_SAVE.resolve()
    res["diagnostic_debug_args"] = extra
    res["godot_logs"] = [str(g.godot_log) for g in games]
    res["log_errors"] = log_errors(games)
    (out / "s1_result.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    (out / "bugs.json").write_text(json.dumps(res.get("bugs", []), indent=1), encoding="utf-8")
    print(json.dumps({k: res.get(k) for k in ("status", "seconds", "wall_seconds", "checkpoints_reached")}, indent=1))
    return 0 if res.get("status") == "completes" else 1


def log_errors(games) -> list:
    out = []
    for g in games:
        try:
            lines = g.godot_log.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for i, ln in enumerate(lines):
            if "SCRIPT ERROR" in ln or ln.startswith("ERROR") or "USER ERROR" in ln or "WARNING" in ln:
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                out.append(f"{g.name}: {ln.strip()} | {nxt}")
    return out[:80]


if __name__ == "__main__":
    sys.exit(main())
