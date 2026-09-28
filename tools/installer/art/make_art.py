"""Builds the Hollowhaven installer wizard art (Inno Setup 6.7, WizardStyle=modern) from EXISTING images only.

    .tools/pyenv/Scripts/python.exe tools/installer/art/make_art.py [--screenshot <1920x1080 png>]

Sources (nothing is rendered by the game for this):
  * the scene: source_scene.png next to this script, a crop of the packaged-build screenshot
    qa/tmp/e2e/final_202_fresh/play_039_ending.png (the Ward Stone, Krystal, the bunting and a peeking Mochi; 1920x1080).
    It is always used, so a re-run is reproducible; --screenshot <png> re-crops a screenshot and replaces it.
  * the small image: game/icon_256.png (the game's own lantern icon).
  * text: the game's own fonts (Fredoka for the wordmark, Nunito for the dedication) and UI palette (src/art/palette.gd).

Outputs (24-bit BMP, no alpha; Setup picks the file closest to the wizard's image area at the user's DPI):
  wizard_<w>x<h>.bmp   left image of the Welcome / Finished pages (aspect 164:314)
  wizard_small_<n>.bmp square image in the top-right corner of the other pages
  (plus qa/tmp/installer/art_preview.png: all outputs side by side on white, for looking at them; scratch, not shipped)
"""
import argparse
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
DEFAULT_SHOT = os.path.join(ROOT, "qa", "tmp", "e2e", "final_202_fresh", "play_039_ending.png")
SOURCE_SCENE = os.path.join(HERE, "source_scene.png")
ICON = os.path.join(ROOT, "game", "icon_256.png")
FREDOKA = os.path.join(ROOT, "game", "assets", "fonts", "Fredoka-Variable.ttf")
NUNITO = os.path.join(ROOT, "game", "assets", "fonts", "Nunito-Variable.ttf")

# Crop of the 1920x1080 screenshot: full height, 564 px wide = the 164:314 aspect of the wizard image area.
# x 600..1164 keeps the Ward Stone, Krystal and Mochi and leaves out the HUD corners (health bar, clock, goal card).
CROP = (600, 0, 1164, 1080)
MASTER = (564, 1080)
# The bottom band hides the rest of the HUD (the "Read the Ward Stone" prompt and the hotbar start at y 865).
FADE_TOP = 752      # the scene starts fading here ...
FADE_SOLID = 858    # ... and is fully covered from here down

# Game UI palette (game/src/art/palette.gd, game/src/ui/theme_factory.gd)
PAPER = (251, 243, 226)      # between UI_PAPER f7ecd6 and CREAM fff4e0: blends into the white wizard page
INK = (59, 47, 53)           # UI_INK 3b2f35
INK_SOFT = (110, 93, 99)     # UI_INK_SOFT 6e5d63
ACCENT = (228, 102, 92)      # UI_ACCENT e4665c
HEART = (255, 143, 168)      # the title screen's "For Krystal" heart ff8fa8
LEAF = (181, 217, 119)       # the title screen's leaf glyphs b5d977

LARGE_SIZES = [(164, 314), (202, 386), (269, 515), (328, 628), (403, 772), (534, 1022)]
SMALL_SIZES = [55, 58, 77, 97, 110, 124, 143, 159]
SS = 4  # supersampling for the drawn overlay


def font(path: str, size: int, weight: int) -> ImageFont.FreeTypeFont:
	f = ImageFont.truetype(path, size)
	try:
		axes = f.get_variation_axes()
		f.set_variation_by_axes([weight if a["name"] in (b"Weight", "Weight") else a["default"] for a in axes])
	except (OSError, AttributeError):
		pass
	return f


def heart(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
	"""A plump heart centred at (cx, cy), about 2r wide."""
	draw.ellipse((cx - r, cy - r * 0.9, cx, cy + r * 0.1), fill=fill)
	draw.ellipse((cx, cy - r * 0.9, cx + r, cy + r * 0.1), fill=fill)
	draw.polygon([(cx - r * 0.97, cy - r * 0.25), (cx + r * 0.97, cy - r * 0.25), (cx, cy + r * 0.95)], fill=fill)


def leaf(draw: ImageDraw.ImageDraw, cx: float, cy: float, length: float, flip: bool, fill) -> None:
	"""A small almond leaf lying on its side (the title screen frames "For Krystal" with two)."""
	h = length * 0.36
	pts = []
	for i in range(33):
		t = i / 32.0
		x = cx - length / 2 + length * t
		y = cy - math.sin(math.pi * t) * h / 2
		pts.append((x, y))
	for i in range(32, -1, -1):
		t = i / 32.0
		x = cx - length / 2 + length * t
		y = cy + math.sin(math.pi * t) * h / 2 * 0.8
		pts.append((x, y))
	if flip:
		pts = [(2 * cx - x, y) for (x, y) in pts]
	draw.polygon(pts, fill=fill)


def load_scene(shot: str) -> Image.Image:
	# Default: the committed crop, so a re-run gives the same pictures on any clone (and never depends on what happens
	# to be in qa/tmp). Only an explicit --screenshot re-crops a screenshot and replaces source_scene.png.
	if shot:
		if not os.path.exists(shot):
			sys.exit(f"screenshot not found: {shot}")
		src = Image.open(shot).convert("RGB")
		if src.size != (1920, 1080):
			sys.exit(f"expected a 1920x1080 screenshot, got {src.size}: {shot}")
		scene = src.crop(CROP)
		scene.save(SOURCE_SCENE, optimize=True)
		print(f"scene: {shot} crop {CROP} (saved as {os.path.relpath(SOURCE_SCENE, ROOT)})")
		return scene
	if os.path.exists(SOURCE_SCENE):
		print(f"scene: {os.path.relpath(SOURCE_SCENE, ROOT)}")
		return Image.open(SOURCE_SCENE).convert("RGB")
	sys.exit(f"no scene source: {SOURCE_SCENE} is missing - pass --screenshot <1920x1080 png> (e.g. {DEFAULT_SHOT})")


def build_master(scene: Image.Image) -> Image.Image:
	w, h = MASTER
	base = scene.resize(MASTER, Image.LANCZOS) if scene.size != MASTER else scene.copy()
	# Paper band: a soft vertical fade over the lower HUD, then solid paper.
	band = Image.new("RGB", MASTER, PAPER)
	mask = Image.new("L", MASTER, 0)
	md = ImageDraw.Draw(mask)
	for y in range(FADE_TOP, h):
		t = min(1.0, (y - FADE_TOP) / float(FADE_SOLID - FADE_TOP))
		t = t * t * (3 - 2 * t)  # smoothstep
		md.line([(0, y), (w, y)], fill=int(255 * t))
	base = Image.composite(band, base, mask)
	# A very light warm vignette at the top so the sky does not look cut off against the white page.
	top = Image.new("L", MASTER, 0)
	td = ImageDraw.Draw(top)
	for y in range(0, 60):
		td.line([(0, y), (w, y)], fill=int(70 * (1 - y / 60.0) ** 2))
	base = Image.composite(Image.new("RGB", MASTER, PAPER), base, top)

	# Text + ornaments, drawn at SS x and scaled down for clean edges.
	ov = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
	d = ImageDraw.Draw(ov)
	title_f = font(FREDOKA, 72 * SS, 600)
	title = "Hollowhaven"
	tb = d.textbbox((0, 0), title, font=title_f)
	tw, th = tb[2] - tb[0], tb[3] - tb[1]
	ty = 878 * SS
	tx = (w * SS - tw) / 2 - tb[0]
	# soft glow behind the wordmark, like the title screen logo
	glow = Image.new("RGBA", ov.size, (0, 0, 0, 0))
	ImageDraw.Draw(glow).text((tx, ty - tb[1]), title, font=title_f, fill=(255, 200, 115, 110))
	glow = glow.filter(ImageFilter.GaussianBlur(7 * SS))
	ov = Image.alpha_composite(ov, glow)
	d = ImageDraw.Draw(ov)
	d.text((tx, ty - tb[1]), title, font=title_f, fill=ACCENT + (255,))

	ded_f = font(NUNITO, 36 * SS, 700)
	ded = "For Krystal"
	db = d.textbbox((0, 0), ded, font=ded_f)
	dw, dh = db[2] - db[0], db[3] - db[1]
	heart_r = 14 * SS
	gap = 12 * SS
	total = dw + gap + heart_r * 2
	dx = (w * SS - total) / 2
	dy = ty + th + 22 * SS
	d.text((dx - db[0], dy - db[1]), ded, font=ded_f, fill=INK_SOFT + (255,))
	heart(d, dx + dw + gap + heart_r, dy + dh * 0.5, heart_r, HEART + (255,))
	leaf_len = 34 * SS
	leaf(d, dx - 16 * SS - leaf_len / 2, dy + dh * 0.55, leaf_len, True, LEAF + (255,))
	leaf(d, dx + total + 16 * SS + leaf_len / 2, dy + dh * 0.55, leaf_len, False, LEAF + (255,))

	ov = ov.resize(MASTER, Image.LANCZOS)
	out = base.convert("RGBA")
	out = Image.alpha_composite(out, ov)
	return out.convert("RGB")


def build_small(size: int) -> Image.Image:
	icon = Image.open(ICON).convert("RGBA")
	bg = Image.new("RGBA", icon.size, (255, 255, 255, 255))  # the modern wizard's top panel is white
	flat = Image.alpha_composite(bg, icon).convert("RGB")
	return flat.resize((size, size), Image.LANCZOS)


def main() -> None:
	ap = argparse.ArgumentParser()
	ap.add_argument("--screenshot", default="", help="re-crop this 1920x1080 screenshot (replaces source_scene.png)")
	a = ap.parse_args()
	master = build_master(load_scene(a.screenshot))
	written = []
	for (w, h) in LARGE_SIZES:
		p = os.path.join(HERE, f"wizard_{w}x{h}.bmp")
		master.resize((w, h), Image.LANCZOS).save(p, format="BMP")
		written.append(p)
	for n in SMALL_SIZES:
		p = os.path.join(HERE, f"wizard_small_{n}.bmp")
		build_small(n).save(p, format="BMP")
		written.append(p)
	# Preview sheet: every output at 1:1 on a white page (how the modern wizard shows them).
	ims = [Image.open(p) for p in written]
	sw = sum(i.size[0] for i in ims) + 12 * (len(ims) + 1)
	sh = max(i.size[1] for i in ims) + 24
	sheet = Image.new("RGB", (sw, sh), (255, 255, 255))
	x = 12
	for i in ims:
		sheet.paste(i, (x, 12))
		x += i.size[0] + 12
	prev = os.path.join(ROOT, "qa", "tmp", "installer", "art_preview.png")
	os.makedirs(os.path.dirname(prev), exist_ok=True)
	sheet.save(prev)
	print(f"preview: {os.path.relpath(prev, ROOT)}")
	for p in written:
		im = Image.open(p)
		print(f"{os.path.relpath(p, ROOT)}  {im.size[0]}x{im.size[1]}  {im.mode}  {os.path.getsize(p)} bytes")


if __name__ == "__main__":
	main()
