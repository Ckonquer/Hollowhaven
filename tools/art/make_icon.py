"""Draws the Hollowhaven app icon (lantern + leaves + heart) and writes game/icon.ico and game/icon_256.png.
Original artwork; mirrors game/icon.svg. Run: .tools/pyenv/Scripts/python.exe tools/art/make_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
S = 1024  # draw large, downsample for smooth edges


def c(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def main():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([32, 32, S - 32, S - 32], radius=224, fill=c('2b2a3f'))
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([180, 240, S - 180, S - 120], fill=(247, 195, 92, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    # leaves
    d.polygon([(512, 150), (640, 250), (780, 290), (740, 420), (600, 500), (512, 500)], fill=c('7dbb5b'))
    d.polygon([(512, 150), (384, 250), (244, 290), (284, 420), (424, 500), (512, 500)], fill=c('8fcf68'))
    d.line([(512, 170), (512, 480)], fill=c('5f9a45'), width=14)
    # lantern cap + body
    d.rounded_rectangle([448, 392, 576, 456], radius=24, fill=c('6b4428'))
    d.rounded_rectangle([368, 448, 656, 800], radius=72, fill=c('c48a55'), outline=c('6b4428'), width=24)
    d.rounded_rectangle([416, 504, 608, 736], radius=48, fill=c('ffe7a3'))
    # heart
    hx, hy = 512, 640
    d.ellipse([hx - 72, hy - 70, hx + 4, hy + 6], fill=c('e4665c'))
    d.ellipse([hx - 4, hy - 70, hx + 72, hy + 6], fill=c('e4665c'))
    d.polygon([(hx - 70, hy - 18), (hx + 70, hy - 18), (hx, hy + 70)], fill=c('e4665c'))
    out_png = ROOT / 'game' / 'icon_256.png'
    small = img.resize((256, 256), Image.LANCZOS)
    small.save(out_png)
    img.resize((256, 256), Image.LANCZOS).save(ROOT / 'game' / 'icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print('wrote', out_png, 'and icon.ico')


if __name__ == '__main__':
    main()
