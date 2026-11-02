#!/usr/bin/env python3
"""Draws the Nimbus app icon and builds assets/AppIcon.icns (macOS only: uses iconutil).

    python3 scripts/make_icon.py        # needs Pillow: pip3 install pillow

The icon is a dark rounded square with a soft cloud, and a notch-shaped island hanging from the top edge
with a live waveform inside, lit coral underneath.
"""
import math
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 2                     # draw at 2x and shrink, for smooth edges
W = 1024 * S
PAD, RADIUS = 100 * S, 185 * S   # Apple's icon grid: the shape sits inside a 100px margin


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def squircle_mask():
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).rounded_rectangle((PAD, PAD, W - PAD, W - PAD), radius=RADIUS, fill=255)
    return m


def background():
    top, bottom = (44, 46, 82), (9, 9, 14)
    img = Image.new("RGBA", (W, W))
    px = ImageDraw.Draw(img)
    for y in range(W):
        t = min(max((y - PAD) / (W - 2 * PAD), 0), 1)
        px.line((0, y, W, y), fill=lerp(top, bottom, t ** 0.9) + (255,))
    return img


def blurred(layer, radius):
    return layer.filter(ImageFilter.GaussianBlur(radius * S))


def cloud_layer():
    """Two banks of cloud along the bottom, with crisp tops so they read as clouds."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    floor = W - PAD

    def bank(circles, color):
        for dx, dy, r in circles:
            cx, cy = W // 2 + dx * S, floor + dy * S
            d.ellipse((cx - r * S, cy - r * S, cx + r * S, cy + r * S), fill=color)

    bank([(-330, -60, 175), (-130, -150, 225), (120, -165, 245), (330, -70, 185)], (170, 170, 235, 58))   # back
    bank([(-250, 10, 165), (-30, -60, 215), (210, -10, 185), (390, 40, 150)], (225, 222, 255, 78))        # front
    return blurred(layer, 3)


def glow_layer():
    """Coral light spilling from under the island."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = W // 2, PAD + 250 * S
    d.ellipse((cx - 380 * S, cy - 170 * S, cx + 380 * S, cy + 230 * S), fill=(255, 122, 89, 150))
    return blurred(layer, 70)


def island_layer():
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h, r = 600 * S, 330 * S, 150 * S
    x0, y0 = (W - w) // 2, PAD - 8 * S           # starts a hair above the edge so the top is flush
    box = (x0, y0, x0 + w, y0 + h)
    # a faint rim so the dark island reads against the dark icon
    d.rounded_rectangle((box[0] - 4 * S, box[1], box[2] + 4 * S, box[3] + 4 * S), radius=r + 4 * S,
                        fill=(70, 72, 108, 255), corners=(False, False, True, True))
    d.rounded_rectangle(box, radius=r, fill=(4, 4, 6, 255), corners=(False, False, True, True))

    # the waveform
    bars = [70, 150, 105, 190, 120]
    bw, gap = 38 * S, 32 * S
    total = len(bars) * bw + (len(bars) - 1) * gap
    bx = (W - total) // 2
    mid = y0 + 215 * S
    for i, bh in enumerate(bars):
        t = i / (len(bars) - 1)
        color = lerp((255, 122, 89), (255, 190, 90), t) + (255,)
        x = bx + i * (bw + gap)
        d.rounded_rectangle((x, mid - bh * S // 2, x + bw, mid + bh * S // 2), radius=bw // 2, fill=color)
    return layer


def build():
    mask = squircle_mask()
    body = background()
    for layer in (cloud_layer(), glow_layer(), island_layer()):
        body = Image.alpha_composite(body, layer)

    # fine top highlight along the rim, for depth
    hi = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(hi).rounded_rectangle((PAD, PAD, W - PAD, W - PAD), radius=RADIUS,
                                         outline=(255, 255, 255, 38), width=3 * S)
    body = Image.alpha_composite(body, hi)

    clipped = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    clipped.paste(body, (0, 0), mask)

    # soft drop shadow under the shape
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (0, 14 * S), mask)
    out = Image.alpha_composite(blurred(shadow, 16), clipped)
    return out.resize((1024, 1024), Image.LANCZOS)


def menu_bar_glyph(size=36):
    """A template image for the menu bar: the island shape, black on transparent."""
    big = Image.new("RGBA", (size * 8, size * 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    u = size * 8
    d.rounded_rectangle((u * 0.14, -u * 0.3, u * 0.86, u * 0.62), radius=u * 0.24, fill=(0, 0, 0, 255),
                        corners=(False, False, True, True))
    for i, h in enumerate([0.14, 0.26, 0.18]):          # waveform cut out of the island
        x = u * (0.34 + i * 0.14)
        d.rounded_rectangle((x, u * 0.40 - h * u / 2, x + u * 0.07, u * 0.40 + h * u / 2), radius=u * 0.035,
                            fill=(0, 0, 0, 0))
    # punch the bars out (draw above with transparent fill replaces alpha)
    return big.resize((size, size), Image.LANCZOS)


def main():
    icon = build()
    (ROOT / "assets").mkdir(exist_ok=True)
    icon.save(ROOT / "assets/icon-1024.png")
    icon.resize((512, 512), Image.LANCZOS).save(ROOT / "docs/icon.png")
    icon.resize((180, 180), Image.LANCZOS).save(ROOT / "docs/apple-touch-icon.png")
    icon.resize((64, 64), Image.LANCZOS).save(ROOT / "docs/favicon.png")

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for base in (16, 32, 128, 256, 512):
            icon.resize((base, base), Image.LANCZOS).save(iconset / f"icon_{base}x{base}.png")
            icon.resize((base * 2, base * 2), Image.LANCZOS).save(iconset / f"icon_{base}x{base}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ROOT / "assets/AppIcon.icns")], check=True)
    menu_bar_glyph().save(ROOT / "assets/MenuBarIcon.png")
    print("Wrote assets/AppIcon.icns, assets/icon-1024.png, assets/MenuBarIcon.png and the docs icons")


if __name__ == "__main__":
    sys.exit(main())
