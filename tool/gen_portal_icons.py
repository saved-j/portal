#!/usr/bin/env python3
"""Generate every icon slot of the app from the owner's logo.

Source: /Volumes/Stuff/Downloads/Routers/@LOGO.png — the portal mark.
The FlClashX "X" disappears everywhere: the launcher, the splash, the Flutter asset,
the tray/desktop icon set and the Quick Settings tile (which gets a stylised П instead,
because a tile is a silhouette and the whole picture turns to mush at 24 dp).

Run: python3 tool/gen_portal_icons.py
"""
import os
from PIL import Image, ImageDraw, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = "/Volumes/Stuff/Downloads/Routers/@LOGO2.png"

ANDROID_RES = os.path.join(ROOT, "android/app/src/main/res")
MACOS_SET = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
ASSETS = os.path.join(ROOT, "assets/images")
WINDOWS = os.path.join(ROOT, "windows/runner/resources")

# The owner's file is used whole — no crop, no zoom, no padding. Each slot is exactly one
# resize of this image to its target size.
BASE = Image.open(SRC).convert("RGB")
BACKGROUND = BASE.getpixel((2, 2))
VOID = "#0B0F1E"


def square(size: int) -> Image.Image:
    return BASE.resize((size, size), Image.LANCZOS)


def rounded(image: Image.Image, radius_ratio: float = 0.5) -> Image.Image:
    size = image.size[0]
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    draw.rounded_rectangle((0, 0, size, size), radius=r, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def circle(image: Image.Image) -> Image.Image:
    size = image.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def letter_p(size: int, color=(255, 255, 255, 255)) -> Image.Image:
    """A stylised П: two posts and a rounded bar, drawn to read at 24 dp."""
    scale = 4
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = size * scale
    # A tile is inset by the system and shown at ~24 dp: the letter has to fill the
    # canvas, or it reads as a speck.
    stroke = int(s * 0.19)
    left = int(s * 0.10)
    right = int(s * 0.90)
    top = int(s * 0.12)
    bottom = int(s * 0.90)
    radius = int(stroke * 0.45)
    # bar
    draw.rounded_rectangle((left, top, right, top + stroke), radius=radius, fill=color)
    # posts
    draw.rounded_rectangle((left, top, left + stroke, bottom), radius=radius, fill=color)
    draw.rounded_rectangle((right - stroke, top, right, bottom), radius=radius, fill=color)
    return canvas.resize((size, size), Image.LANCZOS)


def save(image: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    print(f"{path.replace(ROOT + '/', ''):70s} {image.size[0]:4d}px")


ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)


def save_ico(path: str) -> None:
    """Every .ico frame is resampled from the original once — no frame is derived from
    another frame, so a 16 px entry carries the same detail as the 256 px one."""
    frames = [BASE.resize((side, side), Image.LANCZOS) for side in ICO_SIZES]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames[-1].save(path, sizes=[(side, side) for side in ICO_SIZES],
                    append_images=frames[:-1])
    print(f"{path.replace(ROOT + '/', ''):70s} multi")


def main() -> None:
    densities = {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }
    # launcher icons
    for dens, size in densities.items():
        save(square(size), f"{ANDROID_RES}/mipmap-{dens}/ic_launcher.png")
        save(circle(square(size * 2)), f"{ANDROID_RES}/mipmap-{dens}/ic_launcher_round.png")

    # adaptive foreground/monochrome (108 dp box, art inside the 66 dp safe zone)
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for dens, size in adaptive.items():
        # Full-bleed: the owner's mark is the icon, not a stamp inside a big margin.
        save(square(size), f"{ANDROID_RES}/drawable-{dens}/ic_launcher_foreground.png")
        save(letter_p(size // 2), f"{ANDROID_RES}/drawable-{dens}/ic_launcher_monochrome.png")

    # splash: the mark itself, sitting on the void
    splash = {"mdpi": 96, "hdpi": 144, "xhdpi": 192, "xxhdpi": 288, "xxxhdpi": 384}
    for dens, size in splash.items():
        save(rounded(square(size), 0.22), f"{ANDROID_RES}/drawable-{dens}/ic_splash.png")

    # Quick Settings tile: a silhouette, so the letter, not the picture
    for dens, size in densities.items():
        save(letter_p(size), f"{ANDROID_RES}/drawable-{dens}/ic_qs_portal.png")

    # Flutter asset + tray
    save(square(1024), f"{ASSETS}/icon.png")
    save_ico(f"{ASSETS}/icon.ico")

    # macOS appiconset
    mac = {
        "app_icon_16.png": 16, "app_icon_32.png": 32, "app_icon_64.png": 64,
        "app_icon_128.png": 128, "app_icon_256.png": 256, "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    for name, size in mac.items():
        save(rounded(square(size), 0.2), os.path.join(MACOS_SET, name))

    # Windows runner
    os.makedirs(WINDOWS, exist_ok=True)
    save_ico(os.path.join(WINDOWS, "app_icon.ico"))

    # A master for the site/tray to reuse
    save(square(2048), os.path.join(ROOT, "tool/branding/portal_icon_master.png"))


if __name__ == "__main__":
    main()
