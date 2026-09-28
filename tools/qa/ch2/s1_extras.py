"""Segment S1 extras - bug hunting around the S1 route with normal inputs only (no cheats), started from a save the
S1 route itself wrote (default: the newest qa/tmp/bot/s1/run*/save_at_quit.json, i.e. Krystal at the Commons after
the S1 route; NOT a fixture). Probes the things S1 touches but its main route does not exercise:

  festival_mirror   the Commons festival mirror opens the wardrobe; change the outfit, then "Wear" preset 1
  map_hotkey        M opens the map in the Reach, Esc closes it
  mirror_waygate    the Reach side of the waygate: "Return to Hollowhaven Woods" -> surface spawn "waygate"
  walk_home         from the surface waygate back to the Haven on foot
  ward_stone_look   Ward Stone menu -> "Change your look" opens the wardrobe; "Close" closes the menu
  road_back         Ward Stone -> "Travel the Lantern Road" -> "Lanternwake Commons"

  python tools/qa/ch2/s1_extras.py [--save <slot json>] [--out qa/tmp/bot/s1/extras1] [--attempt 20]
Writes <out>/s1_extras_result.json and <out>/bugs.json.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import s1_common as C  # noqa: E402
from s1_continuation import Seg, TO_WAYGATE, NEW_OUTFIT, NEW_HAIR  # noqa: E402
from playthrough import StepFailed  # noqa: E402

MIRROR_STAND = (-8.3, 68.2)     # between the festival mirror (-10.2, 69.9) and the pole it faces (0, 60)
TO_MIRROR_WAYGATE = [(0.0, 75.5), (0.0, 80.5), (0.0, 90.0), (0.0, 98.5)]


def newest_route_save() -> Path | None:
    cands = sorted((C.ROOT / "qa" / "tmp" / "bot" / "s1").glob("run*/save_at_quit.json"), key=lambda p: p.stat().st_mtime)
    return cands[-1] if cands else None


def run(bot, out: Path, save_dir: Path) -> dict:
    shots = []

    def shoot(label):
        p = out / "shots" / f"x_{len(shots) + 1:03d}_{label}.png"
        rec = {"label": label, "path": str(p)}
        try:
            bot.win.request({"shot": p.as_posix()}, timeout=20.0)
            rec["ok"] = True
        except Exception as e:  # noqa: BLE001
            rec["ok"] = False
            rec["error"] = str(e)[-100:]
        shots.append(rec)
        return str(p)

    p = Seg(bot, out, shoot)
    res = {"segment": "S1-extras", "checkpoints": p.checkpoints, "problems": p.problems, "bugs": p.bugs, "notes": p.notes,
           "data": p.data, "shots": shots}

    def step(name, fn):
        t0 = time.time()
        bot.log(f"=== X STEP {name} ===")
        ok, err = False, ""
        try:
            r = fn()
            ok = True if r is None else bool(r)
        except StepFailed as e:
            err = f"StepFailed: {e}"
        except Exception as e:  # noqa: BLE001
            err = f"{type(e).__name__}: {e}"
            bot.log(traceback.format_exc())
        cp = {"step": name, "ok": ok, "seconds": round(time.time() - t0, 1), "area": p.st().get("area"),
              "pos": p.st().get("player", {}).get("pos")}
        if err:
            cp["error"] = err
        p.checkpoints.append(cp)
        bot.log(f"=== X STEP {name}: {'OK' if ok else 'FAILED'} {err}")
        shoot(name)
        return ok

    def title_continue():
        if not bot.wait_state(lambda s: s.get("mode") == "title" and p.button("Continue") is not None, 120):
            raise StepFailed("no title")
        bot.click_button("Continue", exact=True)
        if not p.wait_playing(None, 120):
            raise StepFailed("no gameplay")
        time.sleep(1.5)
        p.data["start"] = {"area": p.st().get("area"), "pos": p.pos(), "appearance": p.appearance()}
        return True

    def festival_mirror():
        if not p.goto(MIRROR_STAND, tol=0.8, sprint=False):
            raise StepFailed(f"could not reach the mirror (at {p.pos()})")
        e = p.nearest_named("MirrorInteract", 15)
        if not e:
            raise StepFailed("no MirrorInteract")
        if not p.press_interact_on(e, ["Change your look"], lambda: "wardrobe" in p.ui(), stop=1.5):
            raise StepFailed(f"mirror did not open the wardrobe; prompt {p.prompt()}")
        time.sleep(0.6)
        preset_look = p.appearance()
        bot.click_button("Outfits", exact=True)
        time.sleep(0.4)
        t = p.button("Cloud Cardigan")
        if not t:
            raise StepFailed("no Cloud Cardigan tile")
        p.click_b(t)
        time.sleep(0.4)
        ap = p.appearance() or {}
        p.data["after_cloud_cardigan"] = ap
        if ap.get("outfit") != "cloud_cardigan":
            p.problem("festival_mirror", f"outfit is {ap.get('outfit')} after clicking Cloud Cardigan")
        if ap.get("hair") != NEW_HAIR[1]:
            p.problem("festival_mirror", f"choosing an outfit changed the hair to {ap.get('hair')}")
        wear = [b for b in p.buttons_named("Wear") if not b.get("disabled")]
        if not wear:
            raise StepFailed("no enabled Wear button (preset 1 missing?)")
        p.click_b(min(wear, key=lambda b: C.button_center(b)[1]))
        time.sleep(0.5)
        ap2 = p.appearance() or {}
        p.data["after_wear_preset"] = ap2
        if preset_look is not None and ap2 != preset_look:
            p.problem("festival_mirror", f"'Wear' preset 1 gave {ap2}, expected the saved preset {preset_look}")
        bot.click_button("Done", exact=True)
        if not p.wait_ui("wardrobe", 4, present=False):
            raise StepFailed("wardrobe did not close")
        return ap2.get("outfit") == NEW_OUTFIT[1]

    def map_hotkey():
        bot.tap("M")
        if not p.wait_ui("map", 3):
            raise StepFailed(f"M did not open the map (ui {p.ui()})")
        p.data["map_buttons"] = [b["text"] for b in bot.buttons()][:30]
        shoot("map_open")
        bot.tap("ESC")
        if not p.wait_ui("map", 3, present=False):
            raise StepFailed("Esc did not close the map")
        time.sleep(0.3)
        if p.ui():
            p.problem("map_hotkey", f"after Esc the UI stack is {p.ui()} (expected empty)")
            p.close_panels()
        return True

    def mirror_waygate():
        if not p.go(TO_MIRROR_WAYGATE, tol=1.2):
            raise StepFailed(f"could not walk to the mirror waygate (at {p.pos()})")
        e = p.nearest_named("WaygateMirror", 15)
        if not e:
            raise StepFailed("no WaygateMirror")
        p.data["mirror_waygate_prompt"] = e.get("text")
        since = p.msg_t()
        if not p.press_interact_on(e, ["Return to Hollowhaven Woods"], lambda: p.st().get("area") != "hallowmere_reach" or p.st().get("mode") != "playing", stop=2.0):
            raise StepFailed(f"no return; prompt {p.prompt()}")
        if not p.wait_playing("surface", 120):
            raise StepFailed("did not arrive in the woods")
        time.sleep(1.0)
        pos = p.pos()
        p.data["woods_arrival_pos"] = pos
        if C.dist2(C.xz(pos), (-4, -83)) > 3:
            p.problem("mirror_waygate", f"arrived at {pos}, expected the 'waygate' spawn near (-4, -83)")
        if not p.saved_after(since, 8):
            p.problem("mirror_waygate", "no autosave after returning through the waygate")
        gate = p.nearest_named("Waygate", 15)
        p.data["surface_gate_prompt_after_return"] = (gate or {}).get("text")
        bot.calibrate_look()
        return True

    def walk_home():
        pts = list(reversed(TO_WAYGATE))[1:] + [(-2.0, 2.0)]
        t0 = time.time()
        if not p.go(pts, tol=1.6):
            raise StepFailed(f"could not walk home (at {p.pos()})")
        p.data["walk_home_s"] = round(time.time() - t0, 1)
        return True

    def ward_stone_look():
        e = p.nearest_named("WardStone", 30)
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed("no Ward Stone menu")
        menu = p.wait_button("Change your look", 5)
        p.data["ward_stone_menu"] = menu
        bot.click_button("Change your look", exact=True)
        if not p.wait_ui("wardrobe", 4):
            raise StepFailed(f"'Change your look' did not open the wardrobe (ui {p.ui()})")
        time.sleep(0.5)
        bot.click_button("Done", exact=True)
        if not p.wait_ui("wardrobe", 4, present=False):
            raise StepFailed("wardrobe did not close")
        time.sleep(0.4)
        if p.ui():
            p.problem("ward_stone_look", f"after closing the wardrobe the UI stack is {p.ui()}")
            p.close_panels()
        # the menu's own "Close" entry
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed("no Ward Stone menu (2nd)")
        p.wait_button("Read the inscription", 5)
        closes = [b for b in p.buttons_named("Close") if not b.get("disabled")]
        p.data["ward_stone_close_buttons"] = [C.button_center(b) for b in closes]
        # the menu entry "Close" is the lowest one (the other is the card's corner close button)
        if closes:
            p.click_b(max(closes, key=lambda b: C.button_center(b)[1]))
        if not p.wait_ui("confirm", 3, present=False):
            p.problem("ward_stone_look", "the Ward Stone menu's Close did not close it")
            p.close_panels()
        return True

    def road_back():
        e = p.nearest_named("WardStone", 30)
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed("no Ward Stone menu")
        p.wait_button("Travel the Lantern Road", 5)
        bot.click_button("Travel the Lantern Road", exact=True)
        if not p.wait_button("Lanternwake Commons", 5):
            raise StepFailed("no travel list")
        bot.click_button("Lanternwake Commons", exact=True)
        if not p.wait_playing("hallowmere_reach", 120):
            raise StepFailed("did not arrive in the Reach")
        return True

    for name, fn in [("title_continue", title_continue), ("festival_mirror", festival_mirror), ("map_hotkey", map_hotkey),
                     ("mirror_waygate", mirror_waygate), ("walk_home", walk_home), ("ward_stone_look", ward_stone_look),
                     ("road_back", road_back)]:
        if not step(name, fn) and name in ("title_continue", "mirror_waygate", "walk_home"):
            break
    res["status"] = "all ok" if all(c["ok"] for c in p.checkpoints) and len(p.checkpoints) == 7 else "see checkpoints"
    res["seconds"] = round(time.time() - p.t_start, 1)
    return res


def run_shortage(bot, out: Path) -> dict:
    """Probe 2 (from the REAL v1 save): decline the Ward Stone first ("Stay a little longer"), then Esc on the
    choice, accept on the third reading, spend wood on a hand-crafted Crop Plot so the waygate is short of wood,
    read the disabled repair prompt at the gate, gather sticks nearby, repair."""
    p = Seg(bot, out, lambda label: "")
    res = {"segment": "S1-extras-shortage", "checkpoints": p.checkpoints, "problems": p.problems, "bugs": p.bugs,
           "notes": p.notes, "data": p.data}

    def step(name, fn):
        t0 = time.time()
        bot.log(f"=== X2 STEP {name} ===")
        ok, err = False, ""
        try:
            r = fn()
            ok = True if r is None else bool(r)
        except StepFailed as e:
            err = f"StepFailed: {e}"
        except Exception as e:  # noqa: BLE001
            err = f"{type(e).__name__}: {e}"
            bot.log(traceback.format_exc())
        cp = {"step": name, "ok": ok, "seconds": round(time.time() - t0, 1), "pos": p.st().get("player", {}).get("pos")}
        if err:
            cp["error"] = err
        p.checkpoints.append(cp)
        bot.log(f"=== X2 STEP {name}: {'OK' if ok else 'FAILED'} {err}")
        return ok

    def title_continue():
        if not bot.wait_state(lambda s: s.get("mode") == "title" and p.button("Continue") is not None, 120):
            raise StepFailed("no title")
        bot.click_button("Continue", exact=True)
        if not p.wait_playing("surface", 120):
            raise StepFailed("no gameplay")
        time.sleep(1.5)
        return True

    def decline_then_accept():
        e = p.nearest_named("WardStone", 30)
        since = p.msg_t()
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed("no choice")
        if not p.wait_button("Stay a little longer", 5):
            raise StepFailed(f"no 'Stay a little longer' ({[b['text'] for b in bot.buttons()]})")
        bot.click_button("Stay a little longer", exact=True)
        time.sleep(1.0)
        lines = [m["text"] for m in p.recent_msgs(since)]
        p.data["decline_lines"] = lines
        if "ch2_accepted" in p.flags():
            p.problem("decline_then_accept", "'Stay a little longer' accepted Chapter Two")
        if not any("The road will keep" in t for t in lines):
            p.problem("decline_then_accept", f"no decline line after 'Stay a little longer': {lines}")
        p.data["tracker_after_decline"] = p.st().get("tracker")
        # Esc on the choice counts as "stay" too
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed("choice not offered again (2nd)")
        p.wait_button("Follow the lantern road", 5)
        bot.tap("ESC")
        time.sleep(1.0)
        if "ch2_accepted" in p.flags() or p.ui():
            p.problem("decline_then_accept", f"Esc on the choice: accepted={'ch2_accepted' in p.flags()} ui={p.ui()}")
            p.close_panels()
        if not p.press_interact_on(e, ["Read the Ward Stone"], lambda: "confirm" in p.ui(), stop=2.2):
            raise StepFailed("choice not offered again (3rd)")
        if not p.wait_button("Follow the lantern road", 5):
            raise StepFailed("no 'Follow the lantern road' on the 3rd reading")
        bot.click_button("Follow the lantern road", exact=True)
        return bot.wait_state(lambda s: "ch2_accepted" in s.get("flags", []), 5) is not None

    def spend_wood():
        inv0 = p.inv_totals()
        if not p.open_panel("C", "crafting"):
            raise StepFailed("crafting did not open")
        time.sleep(0.5)
        bot.click_button("By Hand", exact=True)
        time.sleep(0.5)
        row = next((b for b in bot.buttons() if b["text"].startswith("Crop Plot")), None)
        if not row:
            raise StepFailed(f"no Crop Plot row: {[b['text'] for b in bot.buttons()][:40]}")
        if row.get("clipped"):
            p.problem("spend_wood", "Crop Plot row is scrolled out of view in By Hand")
        p.click_b(row)
        time.sleep(0.3)
        bot.click_button("Craft", exact=True)
        time.sleep(0.8)
        p.close_panels()
        inv1 = p.inv_totals()
        p.data["craft_delta"] = {k: inv1.get(k, 0) - inv0.get(k, 0) for k in set(inv0) | set(inv1) if inv1.get(k, 0) != inv0.get(k, 0)}
        return inv1.get("wood", 0) == inv0.get("wood", 0) - 3

    def short_gate():
        if not p.go(TO_WAYGATE, tol=1.5):
            raise StepFailed(f"could not reach the gate ({p.pos()})")
        e = p.nearest_named("Waygate", 15)
        p.approach(e, stop=2.0)
        time.sleep(0.5)
        pr = p.prompt()
        p.data["short_prompt"] = pr
        p.data["short_nearby"] = {k: e.get(k) for k in ("text", "enabled")}
        if pr.get("enabled", True):
            p.problem("short_gate", f"repair prompt enabled although 3 wood are missing: {pr}")
        since = p.msg_t()
        bot.tap("E")
        time.sleep(0.8)
        if "ch2_waygate_repaired" in p.flags():
            p.problem("short_gate", "the gate was repaired without enough wood")
        p.data["short_press_msgs"] = [m["text"] for m in p.recent_msgs(since)]
        return True

    def gather_and_repair():
        inv0 = p.inv_totals()
        p.gather_hand(["Stick"], "wood", 8, maxd=70)
        p.data["wood_after_gather"] = p.inv_totals().get("wood", 0)
        p.goto((-4.0, -82.5), tol=1.2)
        e = p.nearest_named("Waygate", 15)
        ok = p.press_interact_on(e, ["Repair the waygate"], lambda: "ch2_waygate_repaired" in p.flags(), stop=2.0)
        p.data["wood_before_gather"] = inv0.get("wood", 0)
        return ok

    for name, fn in [("title_continue", title_continue), ("decline_then_accept", decline_then_accept),
                     ("spend_wood", spend_wood), ("short_gate", short_gate), ("gather_and_repair", gather_and_repair)]:
        if not step(name, fn):
            break
    res["status"] = "all ok" if all(c["ok"] for c in p.checkpoints) and len(p.checkpoints) == 5 else "see checkpoints"
    res["seconds"] = round(time.time() - p.t_start, 1)
    return res


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", default="")
    ap.add_argument("--out", default=str(C.ROOT / "qa" / "tmp" / "bot" / "s1" / "extras1"))
    ap.add_argument("--attempt", type=int, default=20)
    ap.add_argument("--max-minutes", type=float, default=15.0)
    ap.add_argument("--probe", default="route", choices=["route", "shortage"],
                    help="route: festival mirror / map / mirror waygate / Ward Stone look (from the S1 route save); "
                         "shortage: decline + wood shortage at the waygate (from the real v1 save)")
    a = ap.parse_args(argv)
    if a.probe == "shortage" and not a.save:
        a.save = str(C.REAL_SAVE)
    src = Path(a.save) if a.save else newest_route_save()
    if src is None or not src.exists():
        print("no route save found; run s1_continuation.py first")
        return 2
    out = Path(a.out).resolve()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    save_dir = out / "saves"
    C.prepare_saves(save_dir, src)
    g = C.HeadlessGame(out, "x1", C.pick_port(1, a.attempt), save_dir=save_dir, max_seconds=int(a.max_minutes * 60))
    res = {}
    try:
        g.start()
        res = run(g.bot, out, save_dir) if a.probe == "route" else run_shortage(g.bot, out)
    finally:
        g.stop()
    res["start_save"] = str(src)
    (out / "s1_extras_result.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    (out / "bugs.json").write_text(json.dumps(res.get("bugs", []), indent=1), encoding="utf-8")
    print(json.dumps({k: res.get(k) for k in ("status", "seconds")}, indent=1))
    print(json.dumps(res.get("checkpoints"), indent=1))
    print(json.dumps(res.get("problems"), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
