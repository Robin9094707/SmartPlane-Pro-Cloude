"""Renders the 1024x1024 app icon (Liquid-Glass inspired) with Pillow.

Usage: python3 tools/make_icon.py SmartPlanePro/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background():
    img = Image.new("RGB", (S, S))
    px = img.load()
    top = (8, 30, 64)
    mid = (22, 104, 140)
    bottom = (54, 196, 120)
    for y in range(S):
        t = y / (S - 1)
        color = lerp(top, mid, t / 0.55) if t < 0.55 else lerp(mid, bottom, (t - 0.55) / 0.45)
        for x in range(S):
            # subtle diagonal light
            d = (x - y) / S * 0.08
            px[x, y] = tuple(max(0, min(255, int(c * (1 + d)))) for c in color)
    return img


def plane_polygon(cx, cy, scale, angle):
    # Top view of a high-wing RC plane, nose pointing up (normalized coords).
    pts = [
        (0, -0.50), (0.05, -0.44), (0.055, -0.12),
        (0.46, -0.04), (0.47, 0.04), (0.055, 0.02),
        (0.04, 0.33), (0.19, 0.39), (0.19, 0.45), (0.02, 0.43),
        (0, 0.47),
    ]
    full = pts + [(-x, y) for (x, y) in reversed(pts[:-1])]
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + (x * ca - y * sa) * scale, cy + (x * sa + y * ca) * scale) for x, y in full]


def main(path):
    img = background().convert("RGBA")

    # Glass disc
    glass = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = ImageDraw.Draw(glass)
    r = 360
    g.ellipse((S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r), fill=(255, 255, 255, 46), outline=(255, 255, 255, 120), width=6)
    glass = glass.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.alpha_composite(img, glass)

    # Specular highlight on the upper part of the disc
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    h = ImageDraw.Draw(hl)
    h.ellipse((S / 2 - 300, S / 2 - 340, S / 2 + 300, S / 2 - 40), fill=(255, 255, 255, 40))
    hl = hl.filter(ImageFilter.GaussianBlur(30))
    img = Image.alpha_composite(img, hl)

    angle = math.radians(32)
    # Shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(plane_polygon(S / 2 + 26, S / 2 + 40, 640, angle), fill=(0, 20, 30, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    img = Image.alpha_composite(img, shadow)

    # Plane
    plane = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(plane).polygon(plane_polygon(S / 2, S / 2, 640, angle), fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, plane)

    # Green accent stripes on the wings (TobyRich style)
    accent = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = ImageDraw.Draw(accent)
    for side in (1, -1):
        stripe = [(side * 0.20, -0.075), (side * 0.30, -0.055), (side * 0.30, 0.03), (side * 0.20, 0.025)]
        ca, sa = math.cos(angle), math.sin(angle)
        pts = [(S / 2 + (x * ca - y * sa) * 640, S / 2 + (x * sa + y * ca) * 640) for x, y in stripe]
        a.polygon(pts, fill=(70, 220, 130, 255))
    img = Image.alpha_composite(img, accent)

    img.convert("RGB").save(path, "PNG")


if __name__ == "__main__":
    main(sys.argv[1])
