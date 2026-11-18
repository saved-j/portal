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
SRC = "/Volumes/Stuff/Downloads/Routers/@Graphics/@LOGO2.png"

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



def edge_extend(image: Image.Image, canvas: int, coverage: float) -> Image.Image:
    """Art kept at its own scale, its border pixels stretched out to the canvas edge.

    Android shows roughly the inner two thirds of a layer and applies an OEM mask on top.
    Centring the art with a margin leaves a ring of background colour (the "black frame"
    the owner saw), while scaling the art up crops the design. Stretching the outermost
    pixels keeps the picture's proportions and makes its lines run to the icon edge.
    """
    inner = max(1, int(canvas * coverage))
    art = image.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGB", (canvas, canvas))
    offset = (canvas - inner) // 2
    # fill first with the art's own average so corners are never a foreign colour
    out.paste(art.resize((canvas, canvas), Image.BILINEAR), (0, 0))
    out.paste(art, (offset, offset))
    if offset > 0:
        left = art.crop((0, 0, 1, inner)).resize((offset, inner), Image.NEAREST)
        right = art.crop((inner - 1, 0, inner, inner)).resize((offset, inner), Image.NEAREST)
        top = art.crop((0, 0, inner, 1)).resize((inner, offset), Image.NEAREST)
        bottom = art.crop((0, inner - 1, inner, inner)).resize((inner, offset), Image.NEAREST)
        out.paste(left, (0, offset))
        out.paste(right, (offset + inner, offset))
        out.paste(top, (offset, 0))
        out.paste(bottom, (offset, offset + inner))
        tl = art.crop((0, 0, 1, 1)).resize((offset, offset), Image.NEAREST)
        tr = art.crop((inner - 1, 0, inner, 1)).resize((offset, offset), Image.NEAREST)
        bl = art.crop((0, inner - 1, 1, inner)).resize((offset, offset), Image.NEAREST)
        br = art.crop((inner - 1, inner - 1, inner, inner)).resize((offset, offset), Image.NEAREST)
        out.paste(tl, (0, 0)); out.paste(tr, (offset + inner, 0))
        out.paste(bl, (0, offset + inner)); out.paste(br, (offset + inner, offset + inner))
    return out

# Notification small icon, in pixels per density. A small icon is 24x24 dp with ~1 dp of
# padding, and the system uses the alpha channel only: anything that is not transparent is
# drawn white. That is why the slot is a silhouette, not a picture — a coloured PNG becomes a
# white square, and content wider than the optical square is clipped by the circle the shade
# draws around it.
NOTIFICATION_DP = 24.0

# 24 dp in pixels per density bucket (mdpi .. xxxhdpi).
NOTIFICATION_PX = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
NOTIFICATION_PADDING_DP = 1.0


def tray_glyph(
    size_px: int,
    *,
    filled: bool = False,
    dot: bool = False,
    colour=(0, 0, 0, 255),
) -> Image.Image:
    """The portal mark as a menu-bar silhouette.

    A status item is 18 points at most and lives on a bar that may be light or dark, so the
    picture cannot be the app icon: it is drawn as one colour with transparency — a rounded
    frame, the planet inside it and, when the portal is carrying traffic, the planet filled.
    macOS reads the alpha as a template image and recolours it for the current appearance.
    """
    scale = 8
    edge = size_px * scale
    canvas = Image.new("RGBA", (edge, edge), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    margin = int(edge * 0.08)
    stroke = max(scale, int(edge * 0.11))
    radius = int(edge * 0.24)
    box = (margin, margin, edge - margin, edge - margin)
    draw.rounded_rectangle(box, radius=radius, outline=colour, width=stroke)
    planet = int(edge * 0.30)
    centre = edge // 2
    circle_box = (
        centre - planet,
        centre - planet,
        centre + planet,
        centre + planet,
    )
    if filled:
        draw.ellipse(circle_box, fill=colour)
    else:
        draw.ellipse(circle_box, outline=colour, width=max(scale, int(edge * 0.07)))
    if dot:
        r = max(scale, int(edge * 0.05))
        draw.ellipse(
            (centre - r, centre - r, centre + r, centre + r),
            fill=(255, 255, 255, 255) if filled else colour,
        )
    return canvas.resize((size_px, size_px), Image.LANCZOS)


def save_tray_ico(path: str, *, filled: bool, dot: bool) -> None:
    """A Windows tray .ico: white on transparency, several sizes in one file."""
    sizes = [16, 20, 24, 32, 48, 64]
    images = [
        tray_glyph(size, filled=filled, dot=dot, colour=(255, 255, 255, 255))
        for size in sizes
    ]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    images[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=images[:-1])


def notification_p(size_px: int, dp: float, color=(255, 255, 255, 255)) -> Image.Image:
    """A П drawn to the notification spec: 24 dp canvas, 1 dp padding, alpha only."""
    scale = 8
    canvas = Image.new("RGBA", (size_px * scale, size_px * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    edge = size_px * scale
    # 3 dp of margin on every side at 24 dp: the system draws the small icon inside a circle,
    # and a letter that reaches the edge has its corners cut by that circle. 3 dp leaves the
    # whole glyph inside the inscribed square (24/√2 ≈ 17 dp) with room to spare.
    # 5 dp of margin at 24 dp: content then spans 14 dp, inside the inscribed square of the
    # circle the system draws the small icon in (24/√2 ≈ 17 dp). Anything wider has its
    # corners clipped, which is exactly the "black corners" the owner saw in the shade.
    margin = edge * (5.0 / dp)
    left, right = int(margin), int(edge - margin)
    top, bottom = int(margin), int(edge - margin)
    stroke = max(2, int((right - left) * 0.30))
    radius = max(1, int(stroke * 0.4))
    draw.rounded_rectangle((left, top, right, top + stroke), radius=radius, fill=color)
    draw.rounded_rectangle((left, top, left + stroke, bottom), radius=radius, fill=color)
    draw.rounded_rectangle((right - stroke, top, right, bottom), radius=radius, fill=color)
    return canvas.resize((size_px, size_px), Image.LANCZOS)


def letter_p(size: int, color=(255, 255, 255, 255)) -> Image.Image:
    """A stylised П: two posts and a rounded bar, drawn to read at 24 dp."""
    scale = 4
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = size * scale
    # A tile is drawn inside a circle by the system: content wider than the inscribed square
    # (1/√2 ≈ 0.71 of the diameter) has its corners cut off, which reads as the glyph hitting
    # the rounding with black left in the corners. The letter therefore takes 62% of the
    # canvas — still large at 24 dp, and clear of the mask on every launcher.
    stroke = int(s * 0.15)
    left = int(s * 0.19)
    right = int(s * 0.81)
    top = int(s * 0.21)
    bottom = int(s * 0.81)
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
        save(edge_extend(BASE, size, 72 / 108), f"{ANDROID_RES}/drawable-{dens}/ic_launcher_foreground.png")
        save(letter_p(size), f"{ANDROID_RES}/drawable-{dens}/ic_launcher_monochrome.png")

    # splash: the mark itself, sitting on the void
    splash = {"mdpi": 96, "hdpi": 144, "xhdpi": 192, "xxhdpi": 288, "xxxhdpi": 384}
    for dens, size in splash.items():
        save(rounded(square(size), 0.22), f"{ANDROID_RES}/drawable-{dens}/ic_splash.png")

    # Quick Settings tile: a silhouette, so the letter, not the picture
    for dens, size in densities.items():
        save(letter_p(size), f"{ANDROID_RES}/drawable-{dens}/ic_qs_portal.png")

    # The notification's small icon (foreground service, and the status bar's own copy).
    # 24 dp per density, white on transparent, content inside the circle's inscribed square —
    # the size and the silhouette the system asks for.
    #
    # Two copies on purpose: the service module has its own R and the notification is built
    # there (`NotificationModule`), so the resource has to exist in both.
    for dens, px in NOTIFICATION_PX.items():
        icon = notification_p(px, NOTIFICATION_DP)
        save(icon, f"{ANDROID_RES}/drawable-{dens}/ic_service.png")
        save(icon, f"{ROOT}/android/service/src/main/res/drawable-{dens}/ic_service.png")

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

    # Tray / menu-bar icons. These were the last FlClashX leftovers: the status item still drew
    # the old "X", which is what the owner saw in the macOS menu bar. A status icon is a
    # silhouette a few pixels tall, so the picture is drawn as a mark, not resized: a rounded
    # portal frame with the planet inside, in one colour on transparency (macOS treats it as a
    # template and recolours it for light and dark menu bars).
    for scale, size in {1: 18, 2: 36, 3: 54, 4: 72}.items():
        folder = os.path.join(ASSETS, "tray/macos") if scale == 1 else os.path.join(
            ASSETS, f"tray/macos/{scale}.0x"
        )
        save(tray_glyph(size, filled=False), os.path.join(folder, "status_1.png"))
        save(tray_glyph(size, filled=True), os.path.join(folder, "status_4.png"))

    for scale, size in {1: 22, 2: 44, 3: 66, 4: 88}.items():
        folder = os.path.join(ASSETS, "tray/unix") if scale == 1 else os.path.join(
            ASSETS, f"tray/unix/{scale}.0x"
        )
        for state, fill in ((1, False), (2, False), (3, True), (4, True)):
            save(
                tray_glyph(size, filled=fill, dot=state >= 2, colour=(0, 0, 0, 255)),
                os.path.join(folder, f"status_{state}.png"),
            )

    for state, fill in ((1, False), (2, False), (3, True), (4, True)):
        save_tray_ico(
            os.path.join(ASSETS, f"tray/windows/status_{state}.ico"),
            filled=fill,
            dot=state >= 2,
        )

    # A master for the site/tray to reuse
    save(square(2048), os.path.join(ROOT, "tool/branding/portal_icon_master.png"))


if __name__ == "__main__":
    main()
