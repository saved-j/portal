#!/usr/bin/env python3
"""Draw the Portal Connect mark once and write every icon the build expects.

The mark: a dark void, two arcs turning in opposite directions and a lit core —
the same shape the in-app portal button draws, so the launcher icon and the
connect control read as one thing.
"""
import pathlib
import math
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
S = 2048                # master size, downsampled everywhere
VOID = (7, 9, 14, 255)
CYAN = (0, 229, 255, 255)
PURPLE = (168, 85, 247, 255)
WHITE = (255, 255, 255, 255)


def draw_mark(size, background=True, inset=0.0, monochrome=False):
    img = Image.new("RGBA", (size, size), VOID if background else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size / 2
    r = size / 2 * (1 - inset)

    if background:
        # soft glow behind the ring
        glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        steps = 60
        for i in range(steps, 0, -1):
            t = i / steps
            rad = r * 0.95 * t
            alpha = int(26 * (1 - t) ** 2)
            gd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad],
                       fill=(CYAN[0], CYAN[1], CYAN[2], alpha))
        img = Image.alpha_composite(img, glow)
        d = ImageDraw.Draw(img)

    ring_color = WHITE if monochrome else CYAN
    inner_color = WHITE if monochrome else PURPLE
    w_outer = max(2, int(size * 0.055))
    w_inner = max(2, int(size * 0.04))

    box_o = [cx - r * 0.74, cy - r * 0.74, cx + r * 0.74, cy + r * 0.74]
    d.arc(box_o, start=200, end=110, fill=ring_color, width=w_outer)

    box_i = [cx - r * 0.48, cy - r * 0.48, cx + r * 0.48, cy + r * 0.48]
    d.arc(box_i, start=20, end=290, fill=inner_color, width=w_inner)

    core = max(2, int(size * 0.075))
    d.ellipse([cx - core, cy - core, cx + core, cy + core], fill=ring_color)
    return img


def write(img, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)


SOURCE = ROOT / "tool/branding/portal_icon_source.jpg"

def cut_white_corners(image):
    """The source was exported inside a rounded square on a white sheet. Launchers
    draw their own mask, so the white outside that square has to go: flood-fill it
    from the four corners and make it transparent."""
    img = image.convert("RGBA").copy()
    w, h = img.size
    # mask: 255 where the pixel is near-white
    mask = Image.new("L", (w, h), 0)
    src = img.convert("RGB").load()
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            if r > 240 and g > 240 and b > 240:
                mp[x, y] = 255
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if mask.getpixel(corner) == 255:
            ImageDraw.floodfill(mask, corner, 128, thresh=20)
    px = img.load()
    for y in range(h):
        for x in range(w):
            if mask.getpixel((x, y)) == 128:
                px[x, y] = (0, 0, 0, 0)
    return img


if SOURCE.exists():
    # The owner's mark (a lit door inside a nest of cables) is the brand; the drawn
    # fallback stays only for a checkout that lost the source file.
    cleaned = cut_white_corners(Image.open(SOURCE)).resize((S, S), Image.LANCZOS)
    # Launcher icons have no transparency to lean on: put the mark on the void.
    base = Image.new("RGBA", (S, S), VOID)
    base.alpha_composite(cleaned)
    master_square = base
    master_fg = cleaned
    grey = base.convert("L")
    mono = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    mono.putalpha(grey.point(lambda v: 0 if v < 40 else 255))
    master_mono = mono
else:
    master_square = draw_mark(S)
    master_fg = draw_mark(S, background=False, inset=0.10)
    master_mono = draw_mark(S, background=False, inset=0.10, monochrome=True)

# --- Android: legacy square icons
android_densities = {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
}
for density, px in android_densities.items():
    write(master_square, ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png", px)
    write(master_square, ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher_round.png", px)

# --- Android: adaptive foreground (108 dp) and monochrome
fg_densities = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
for density, px in fg_densities.items():
    write(master_fg, ROOT / f"android/app/src/main/res/drawable-{density}/ic_launcher_foreground.png", px)
    write(master_mono, ROOT / f"android/app/src/main/res/drawable-{density}/ic_launcher_monochrome.png", px)

# --- macOS
mac = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for px in (16, 32, 64, 128, 256, 512, 1024):
    write(master_square, mac / f"app_icon_{px}.png", px)

# --- Windows .ico (multi-size)
ico_path = ROOT / "windows/runner/resources/app_icon.ico"
ico_path.parent.mkdir(parents=True, exist_ok=True)
master_square.resize((256, 256), Image.LANCZOS).save(
    ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
)

print("icons written")
