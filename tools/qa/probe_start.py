"""Launch the release build and walk the title -> new game flow with real input, printing what the
bot perceives at each step (used to discover UI labels)."""
import sys, time, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from session import Session

ROOT = Path(__file__).resolve().parents[2]
exe = str(ROOT / "builds" / "Hollowhaven" / "Hollowhaven.exe")
out = ROOT / "qa" / "tmp" / "e2e" / "probe"
sess = Session(exe, out, out / "saves", "probe", extra=["--windowed"])
bot = sess.start(wait_for=lambda s: s.get("mode") == "title" and len(s.get("buttons", [])) > 0, timeout=40)
time.sleep(2.0)
print("TITLE buttons:", [b["text"] for b in bot.buttons()])
sess.shot("title")
bot.click_button("New Game")
time.sleep(1.5)
print("AFTER NEW GAME buttons:", [b["text"] for b in bot.buttons()], "mode", bot.state().get("mode"))
sess.shot("comfort")
for label in sys.argv[1:]:
    bot.click_button(label)
    time.sleep(1.5)
    print(f"AFTER {label!r}:", [b["text"] for b in bot.buttons()], "mode", bot.state().get("mode"))
    sess.shot("after_" + label.replace(" ", "_"))
st = bot.wait_state(lambda s: s.get("mode") == "playing" and s.get("area") == "surface", 25)
print("PLAYING:", bool(st))
time.sleep(4)
sess.shot("ingame")
s = bot.state()
print(json.dumps({k: s.get(k) for k in ("mode", "area", "step", "ui_stack", "player")})[:1500])
print("alive:", sess.alive())
sess.stop()
