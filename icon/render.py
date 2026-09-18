"""One artwork source, every icon variant and size.

art.svg holds the drawing. This composes it into the platform variants, writes
them out as plain .svg files for handoff, and rasterizes the PNG sets.
Edit art.svg to change the glyph; edit BG below to change the background.
"""
import pathlib
import re
import cairosvg
from PIL import Image, ImageChops

HERE = pathlib.Path(__file__).parent
OUT = HERE / "png"
BG = "#101725"
INK = "#EAF0FB"
ACCENT = "#4C8DFF"

# Adaptive icons only guarantee a 66dp circle on a 108dp canvas survives the
# launcher mask; the PWA maskable spec guarantees 80%. Both are measured from
# the canvas centre against the artwork's bounding box corners, so the artwork
# is drawn centred on the canvas (its own centre is the canvas centre) and the
# scaled variants scale about that same point.
ART_CENTER = (512, 512)
# 33/108 of the width, with slack for the antialiasing fringe and rounding.
# The block cursor made the art wider, so the scale came down to keep the
# mark the same visible size as before while staying inside the safe circle.
ANDROID_SCALE = 0.64
MASKABLE_SCALE = 0.86
# macOS does not mask icons, so the squircle has to be drawn in: Apple's grid
# is an 824px shape with a 185.4px radius, centred on a 1024px canvas. The art
# drawn for a 1024px plate scales down with it.
MACOS_PLATE = 824
MACOS_RADIUS = 185.4
MACOS_MARGIN = (1024 - MACOS_PLATE) / 2
MACOS_SCALE = MACOS_PLATE / 1024

APPLE = [1024, 180, 167, 152, 120, 76, 40, 29]
WEB = [1024, 512, 192, 128, 96, 64, 48, 32, 16]
DROID = [1024, 432, 324, 216, 144]
# Linux gets no help from flutter_launcher_icons, so it gets a freedesktop
# hicolor tree to install instead.
LINUX = [512, 256, 128, 64, 48, 32, 24, 16]


def artwork():
    src = (HERE / "art.svg").read_text()
    return src[src.index("<!-- artwork -->") + 17:src.rindex("</svg>")].strip()


def monochrome(art):
    """Android 13 themed icons tint a single-colour layer themselves."""
    return re.sub(r'(fill|stroke)="#[0-9A-Fa-f]{6}"', r'\1="#FFFFFF"', art)


def wrap(body, background):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        f'viewBox="0 0 1024 1024">\n{background}\n{body}\n</svg>\n'
    )


def variants():
    art = artwork()
    cx, cy = ART_CENTER

    def scaled(scale):
        return (f'<g transform="translate(512 512) scale({scale}) '
                f'translate(-{cx} -{cy})">\n{{body}}\n</g>')

    fg = scaled(ANDROID_SCALE).format(body=art)
    mono = scaled(ANDROID_SCALE).format(body=monochrome(art))
    maskable = scaled(MASKABLE_SCALE).format(body=art)
    plate = f'  <rect width="1024" height="1024" fill="{BG}"/>'
    rounded = f'  <rect width="1024" height="1024" rx="224" fill="{BG}"/>'
    return {
        # iOS / macOS / web: rounded square, transparent corners
        "icon.svg": wrap(art, rounded),
        # iOS ships opaque squares and masks the corners itself, so it needs a
        # full-bleed plate: App Store Connect rejects any alpha channel.
        "icon-square.svg": wrap(art, plate),
        # Android adaptive icon: background + foreground + themed monochrome
        "android-background.svg": wrap("", plate),
        "android-foreground.svg": wrap(fg, ""),
        "android-monochrome.svg": wrap(mono, ""),
        # PWA: full bleed background, art inside the safe circle
        "maskable.svg": wrap(maskable, plate),
        # macOS: the squircle is part of the artwork, inset on Apple's icon grid
        "macos.svg": wrap(
            scaled(MACOS_SCALE).format(body=art),
            f'  <rect x="{MACOS_MARGIN}" y="{MACOS_MARGIN}" width="{MACOS_PLATE}" '
            f'height="{MACOS_PLATE}" rx="{MACOS_RADIUS}" fill="{BG}"/>',
        ),
    }


def svg_bytes(name):
    return variants()[name].encode()


def png(name, size, out, opaque=False):
    out.parent.mkdir(exist_ok=True)
    cairosvg.svg2png(bytestring=svg_bytes(name), write_to=str(out),
                     output_width=size, output_height=size)
    if opaque:
        Image.open(out).convert("RGB").save(out)


def linux_tree():
    """hicolor PNGs plus a desktop entry template, ready to install."""
    for size in LINUX:
        png("icon.svg", size, OUT / "linux" / f"noshell-{size}.png")
    desktop = HERE / "linux" / "noshell.desktop"
    desktop.parent.mkdir(exist_ok=True)
    desktop.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=NoShell\n"
        "Comment=Terminal session manager\n"
        "Exec=noshell\n"
        "Icon=noshell\n"
        "Categories=Development;Utility;\n"
        "Terminal=false\n"
    )


def contact_sheet():
    """Squint test: same icon at real UI sizes on light and dark chrome."""
    tiles = []
    for size in (128, 64, 48, 32, 16):
        path = OUT / f"icon-{size}.png"
        png("icon.svg", size, path)
        tiles.append(Image.open(path).convert("RGBA"))
    pad, gap = 24, 16
    tallest = max(t.height for t in tiles)
    width = pad * 2 + sum(t.width for t in tiles) + gap * (len(tiles) - 1)
    sheet = Image.new("RGBA", (width, tallest * 2 + pad * 2), (255, 255, 255, 255))
    sheet.paste(Image.new("RGBA", (width, tallest + pad * 2), (24, 26, 32, 255)), (0, tallest + pad * 2))
    for row in (0, tallest + pad * 2):
        x = pad
        for tile in tiles:
            sheet.alpha_composite(tile, (x, row + pad + (tallest - tile.height) // 2))
            x += tile.width + gap
    sheet.save(OUT / "_contact-sheet.png")


def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def lum(hex_color):
    r, g, b = (c / 255 for c in rgb(hex_color))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def outside_circle(path, safe_fraction, bg=None):
    """Max corner distance of the drawn content vs the masker's safe circle.

    bg=None reads the art from alpha (transparent-background SVG); pass a hex
    color when the background is baked in, so only the artwork is measured.
    """
    im = Image.open(path).convert("RGBA")
    if bg is None:
        # ignore the antialiasing fringe: alpha below 8/255 is not ink
        box = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    else:
        flat = Image.new("RGB", im.size, rgb(bg))
        diff = ImageChops.difference(im.convert("RGB"), flat).convert("L")
        box = diff.point(lambda v: 255 if v > 8 else 0).getbbox()
    if box is None:
        return 0.0, 0.0
    cx = cy = im.width / 2
    corners = [(box[0], box[1]), (box[2], box[1]), (box[0], box[3]), (box[2], box[3])]
    worst = max(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 for x, y in corners)
    return worst, safe_fraction * im.width


def check():
    full = Image.open(OUT / "icon-1024.png").convert("RGBA")
    assert full.getpixel((0, 0))[3] == 0, "rounded square must be transparent outside the corner"
    assert full.getpixel((512, 512))[3] == 255, "icon body must be opaque"

    # 33/108 is the real Android safe zone, measured on the box corners, which
    # is the worst case. The innermost check is the one that bites.
    worst, limit = outside_circle(OUT / "android-foreground-432.png", 33 / 108)
    assert worst <= limit, f"android foreground escapes the 66dp safe zone: {worst:.1f} > {limit:.1f}"
    worst, limit = outside_circle(OUT / "android-monochrome-432.png", 33 / 108)
    assert worst <= limit, f"monochrome layer escapes the 66dp safe zone: {worst:.1f} > {limit:.1f}"
    worst, limit = outside_circle(OUT / "maskable-512.png", 0.40, bg=BG)
    assert worst <= limit, f"maskable art escapes the 80% safe circle: {worst:.1f} > {limit:.1f}"

    mono = Image.open(OUT / "android-monochrome-432.png").convert("RGBA")
    assert mono.getchannel("A").getbbox() is not None, "monochrome layer is empty"
    # the themed-icon layer has to be one flat colour; Android supplies the tint.
    # dropping alpha leaves pure white for the ink and pure black for the
    # untouched canvas, so any third colour means the layer is not flat.
    listed = mono.convert("RGB").getcolors(maxcolors=16)
    assert listed is not None, "monochrome layer is not flat: more than 16 colours"
    counts = {color: n for n, color in listed}
    assert set(counts) <= {(255, 255, 255), (0, 0, 0)}, f"monochrome layer is not flat: {counts}"
    assert counts.get((255, 255, 255), 0) > mono.width * mono.height * 0.03, "monochrome layer is too sparse"

    small = Image.open(OUT / "icon-16.png").convert("RGB")
    assert len(small.getcolors(maxcolors=256)) >= 3, "icon flattens to a blob at 16px"

    ink, accent = rgb(INK), rgb(ACCENT)
    # N left leg, N diagonal, the block cursor, and the counter in between
    for xy, expected, what in (
        ((197, 512), ink, "N left leg"),
        ((392, 512), ink, "N diagonal"),
        ((587, 400), ink, "N right leg"),
        ((790, 700), accent, "cursor"),
        ((500, 460), rgb(BG), "background"),
    ):
        got = full.getpixel(xy)[:3]
        assert got == expected, f"{what} at {xy} is {got}, expected {expected}"

    ios = Image.open(OUT / "ios-1024.png")
    assert ios.mode == "RGB", f"App Store Connect rejects an alpha channel, got {ios.mode}"
    assert ios.getpixel((0, 0)) == rgb(BG), "iOS icon corners must stay filled, not transparent"
    assert ios.getpixel((197, 512)) == ink, "iOS icon lost the letterform"

    # macOS gets no mask from the system, so the plate is drawn and the space
    # outside it must stay transparent, with the art riding inside it.
    mac = Image.open(OUT / "macos-1024.png").convert("RGBA")
    assert mac.getpixel((0, 0))[3] == 0, "macOS icon must be transparent outside the squircle"
    assert mac.getpixel((24, 512))[3] == 0, "macOS icon needs the 100px margin on every side"
    assert mac.getpixel((150, 512))[:3] == rgb(BG), "macOS squircle plate is missing"
    assert mac.getpixel((259, 512))[:3] == ink, "macOS icon lost the letterform"

    assert contrast(INK, BG) >= 7.0, "letterform is not crisp enough on the background"
    assert contrast(ACCENT, BG) >= 3.0, "cursor lacks contrast on the background"


if __name__ == "__main__":
    for name, markup in variants().items():
        (HERE / name).write_text(markup)

    for name, sizes, pattern, opaque in (
        ("icon.svg", WEB, "icon-{}.png", False),
        ("icon-square.svg", APPLE, "ios-{}.png", True),
        ("maskable.svg", [512, 192], "maskable-{}.png", False),
        ("android-foreground.svg", DROID, "android-foreground-{}.png", False),
        ("android-background.svg", DROID, "android-background-{}.png", True),
        ("android-monochrome.svg", DROID, "android-monochrome-{}.png", False),
        ("macos.svg", [1024], "macos-{}.png", False),
    ):
        for size in sizes:
            png(name, size, OUT / pattern.format(size), opaque)

    linux_tree()
    contact_sheet()
    check()
    print("ok:", ", ".join(sorted(p.stem for p in HERE.glob("*.svg"))))
