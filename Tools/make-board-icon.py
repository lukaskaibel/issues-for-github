#!/usr/bin/env python3
"""Draws the app icon: a planning board with an index card, a code screenshot and a sticky note, pinned and joined
with string. The board comes in several materials; the warm grey pinboard is the app's own icon, the others are the
choices in Settings (the Mac sets them as the Dock icon, iPhone and iPad as alternate icons).

    python3 Tools/make-board-icon.py [board …]     every board, or only those named (pinboard, cork, metal, …)

Writes an Icon Composer document per board: GitIssues/AppIcon.icon for the pinboard and GitIssues/AppIcon-<Name>.icon
for the others, each with a light and a dark look. Tools/render-icons.sh then renders the pictures the app, the README
and the website use. Needs numpy and Pillow (pip install numpy pillow).

Everything is drawn at 2048 px and scaled down to the 1024 px layers Icon Composer expects. Two layers per look: the
board's surface, and the things on it with their pins, string and shadows.

Size matters: Xcode stores every icon several times over (light, dark, tinted, each size), and grain that doesn't
compress made each board cost megabytes. So nothing finer than a few pixels is random: a surface is a smooth gradient
plus a texture that repeats every 256 px across, added in whole steps of colour so that the repeats are exact and
compress; the things on the board have no grain finer than their fibres.
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

N = 2048
YY, XX = np.mgrid[0:N, 0:N].astype(np.float32)
TWO_PI = 2 * np.pi
INDIGO = "#5B63D3"


# Noise and shapes -------------------------------------------------------------------------------------------------

def rng(seed):
    return np.random.default_rng(seed)


def value_noise(cell, seed):
    gh, gw = max(2, N // cell + 2), max(2, N // cell + 2)
    grid = rng(seed).random((gh, gw)).astype(np.float32)
    image = Image.fromarray((grid * 255).astype(np.uint8), "L").resize((gw * cell, gh * cell), Image.BICUBIC)
    return np.asarray(image, np.float32)[:N, :N] / 255


def fbm(cell, octaves, seed, gain=0.5):
    out, amplitude, total = np.zeros((N, N), np.float32), 1.0, 0.0
    for octave in range(octaves):
        out += amplitude * value_noise(max(1, cell >> octave), seed + octave * 101)
        total += amplitude
        amplitude *= gain
    return out / total


def _box(a, k, axis):
    pad = [(0, 0)] * a.ndim
    pad[axis] = (k + 1, k)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    hi = np.take(c, range(2 * k + 1, c.shape[axis]), axis=axis)
    lo = np.take(c, range(0, c.shape[axis] - 2 * k - 1), axis=axis)
    return ((hi - lo) / (2 * k + 1)).astype(np.float32)


def blur(a, r):
    """A Gaussian-like blur of a float field: three box passes per axis."""
    k = max(1, int(round(r * 0.9)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box(_box(out, k, 0), k, 1)
    return out


def shade(height, strength):
    """Light from above and a little to the left, from a height field."""
    gy, gx = np.gradient(height)
    return (gx * 0.35 + gy * 0.9) * strength


def mask(draw):
    image = Image.new("L", (N, N), 0)
    draw(ImageDraw.Draw(image))
    return np.asarray(image, np.float32) / 255


def rrect(x, y, w, h, r):
    return mask(lambda d: d.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=255))


def ellipse(x, y, w, h):
    return mask(lambda d: d.ellipse([x, y, x + w, y + h], fill=255))


def line(points, width):
    def draw(d):
        d.line(points, fill=255, width=int(width), joint="curve")
        for px, py in (points[0], points[-1]):
            d.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2], fill=255)
    return mask(draw)


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def solid(hex_colour, factor=1.0):
    return np.ones((N, N, 3), np.float32) * rgb(hex_colour) * factor


def ramp(t, stops):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        inside = (t >= p0) & (t <= p1)
        k = ((t - p0) / (p1 - p0 + 1e-9))[..., None]
        out[inside] = (rgb(c0) * (1 - k) + rgb(c1) * k)[inside]
    return out


def vertical(top, bottom, y0=0, y1=N):
    return ramp((YY - y0) / max(1, y1 - y0), [(0, top), (1, bottom)])


class Layer:
    def __init__(self):
        self.rgb = np.zeros((N, N, 3), np.float32)
        self.alpha = np.zeros((N, N), np.float32)

    def paint(self, colour, coverage):
        c = coverage[..., None]
        self.rgb = self.rgb * (1 - c) + colour * c
        self.alpha = self.alpha + coverage * (1 - self.alpha)

    def darken(self, amount):
        """A shadow: darkens what is there and adds to the coverage, so it also falls on the surface below."""
        self.rgb = self.rgb * (1 - amount[..., None])
        self.alpha = self.alpha + amount * (1 - self.alpha)

    def shadow(self, shape, dx, dy, r, opacity):
        self.darken(np.roll(np.roll(blur(shape, r), dy, 0), dx, 1) * opacity)

    def save(self, path):
        rgba = np.dstack([np.clip(self.rgb, 0, 1), np.clip(self.alpha, 0, 1)])
        image = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((1024, 1024), Image.LANCZOS)
        image.save(path, optimize=True)


# Surfaces ---------------------------------------------------------------------------------------------------------
# Each returns the board's smooth colour at 2048 px and its texture at 1024 px: how much lighter or darker each pixel
# is, as a fraction of the colour, repeating every TILE px across.

S = 1024
TILE = 256
sy, sx = np.mgrid[0:S, 0:S].astype(np.float32)


def small(a):
    """A 2048 px array of numbers scaled to 1024 px."""
    return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((S, S), Image.LANCZOS))


def repeating(texture):
    """The first TILE px of a 1024 px texture, repeated across."""
    return np.tile(texture[:, :TILE], (1, S // TILE))


def fabric(top, bottom, seed=11):
    """A fabric-covered pinboard: a fine linen weave over a soft felt tone."""
    a, b = np.sin(TWO_PI * (sx + 0.5) / 4), np.sign(np.sin(TWO_PI * (sy + 0.5) / 8))
    weave = 0.011 * (a * b + a.T * b.T)
    felt = small((fbm(60, 2, seed + 1) - 0.5) * 0.03)
    return vertical(top, bottom), weave + repeating(felt)


def granules(cell, seed, threshold=None):
    n = N // cell + 1
    grid = rng(seed).random((n, n)).astype(np.float32)
    if threshold is not None:
        grid = (grid > threshold).astype(np.float32)
    image = Image.fromarray((grid * 255).astype(np.uint8), "L").resize((n * cell, n * cell), Image.NEAREST)
    return blur(np.asarray(image, np.float32)[:N, :N] / 255, cell * 0.18)


def cork(top, bottom, seed=21):
    """Fine, quiet cork: small granules and little contrast."""
    fine, coarse = granules(6, seed) - 0.5, granules(11, seed + 1) - 0.5
    specks = granules(7, seed + 2, threshold=0.94)
    texture = fine * 0.07 + coarse * 0.05 - specks * 0.12 + (fbm(140, 2, seed + 3) - 0.5) * 0.05
    texture = (1 + texture) * (1 + shade(blur(fine + coarse, 1.0), 2.5)) - 1
    return vertical(top, bottom), repeating(small(texture))


def metal(base, dark, seed=31):
    """Brushed metal: fine streaks along the plate, each running all the way across, and a soft sheen."""
    rows = rng(seed).random(S + 2).astype(np.float32)
    rows = ((rows[:-2] + 2 * rows[1:-1] + rows[2:]) / 4)[:, None]
    falloff = (1.08 - 0.25 * np.clip(YY / N, 0, 1)) if dark else (1.04 - 0.12 * np.clip(YY / N, 0, 1))
    sheen = np.exp(-((XX * 0.35 + YY - 700) / 420) ** 2) * (0.04 if dark else 0.05)
    colour = rgb(base)[None, None, :] * (0.93 * falloff)[..., None] + sheen[..., None]
    return colour, np.broadcast_to((rows - 0.5) * 0.06, (S, S))


def whiteboard(top, bottom, dark, seed=41):
    reflection = np.exp(-((XX - YY * 0.55 - 760) / 300) ** 2) * (0.05 if dark else 0.04)
    ghosting = (fbm(220, 3, seed) - 0.5) * (0.02 if dark else 0.012)
    return vertical(top, bottom) + reflection[..., None] + ghosting[..., None], None


def save_surface(surface, path):
    """The smooth colour scaled down, then the texture added in whole steps of each channel's average, so the repeats
    stay exact."""
    colour, texture = surface
    image = Image.fromarray((np.clip(colour, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").resize((S, S), Image.LANCZOS)
    pixels = np.asarray(image, np.int16)
    if texture is not None:
        average = pixels.reshape(-1, 3).mean(0)
        pixels = pixels + np.round(texture[..., None] * average[None, None, :]).astype(np.int16)
    Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGB").convert("RGBA").save(path, optimize=True)


# Things on the board ----------------------------------------------------------------------------------------------

def paper(seed, dark, tint="#F8F3E7"):
    fibre = (fbm(40, 3, seed + 9) - 0.5) * 0.02
    colour = np.clip(rgb(tint if not dark else "#E6E0D2")[None, None, :] * (1 + fibre[..., None]), 0, 1)
    return colour


def index_card(layer, x, y, w, h, dark, seed):
    shape = rrect(x, y, w, h, 14)
    layer.shadow(shape, 4, 14, 16, 0.26)
    layer.paint(paper(seed, dark) * (1.01 - 0.03 * np.clip((YY - y) / h, 0, 1))[..., None], shape)
    head = y + h * 0.26
    rules = np.zeros((N, N), np.float32)
    for k in range(1, 4):
        ry = int(head + k * (h * 0.74) / 4)
        rules[ry - 2:ry + 2, int(x + 40):int(x + w - 40)] = 1
    rules = blur(rules, 0.8) * shape * 0.55
    layer.rgb = layer.rgb * (1 - rules[..., None]) + rgb("#BFCDE6") * rules[..., None]
    top_rule = np.zeros((N, N), np.float32)
    top_rule[int(head) - 5:int(head) + 5, int(x + 40):int(x + w - 40)] = 1
    top_rule = blur(top_rule, 0.8) * shape
    layer.rgb = layer.rgb * (1 - top_rule[..., None]) + rgb(INDIGO) * top_rule[..., None]


def code_screenshot(layer, x, y, w, h, dark):
    """A screenshot of code in dark mode, printed and pinned up: a window's three dots and lines of coloured code."""
    shape = rrect(x, y, w, h, 14)
    layer.shadow(shape, 4, 16, 18, 0.28)
    layer.paint(solid("#24262C" if not dark else "#202227"), shape)
    for k, colour in enumerate(("#ED6A5E", "#F4BE4F", "#61C554")):
        layer.paint(solid(colour, 0.85), ellipse(x + 44 + k * 44, y + 92, 26, 26))
    colours = ["#9EA3F2", "#E58FB0", "#7FD3A8", "#F0C76A", "#6B6F78"]
    lines = [(0, [(110, 0), (150, 1), (60, 4)]), (1, [(90, 0), (200, 2)]), (1, [(140, 3), (80, 4)]),
             (2, [(70, 0), (180, 2)]), (2, [(220, 1)]), (1, [(40, 4)]), (0, [(110, 0), (120, 1), (60, 4)]),
             (1, [(160, 3), (110, 2)]), (1, [(90, 1)])]
    for row, (indent, segments) in enumerate(lines):
        bx, by = x + 48 + indent * 44, y + 170 + row * 64
        for length, colour in segments:
            layer.paint(solid(colours[colour]), rrect(bx, by, length, 30, 15) * shape)
            bx += length + 16
    sheen = np.exp(-((XX - YY * 0.5 - (x + 120 - y * 0.5)) / 160) ** 2) * 0.05 * shape
    layer.rgb = np.clip(layer.rgb + sheen[..., None], 0, 1)


def sticky_note(layer, x, y, s, dark, seed=42, colour="#FFE36E", curl=0.55):
    """A square sticky note: flat under the glue strip, curling away from the board below it."""
    cx = x + s / 2
    t = np.clip((YY - (y + 0.3 * s)) / (s * 0.7), 0, 1)
    lift = t ** 2 * curl
    u = (XX - cx) / (s / 2)
    corner_lift = lift * (1 + 0.6 * u ** 2)
    half_width = s / 2 * (1 + 0.03 * lift)
    bottom = y + s - 26 * curl * u ** 2
    inside = ((np.abs(XX - cx) <= half_width) & (YY >= y) & (YY <= bottom)).astype(np.float32)
    shape = blur(inside, 1.0)
    cast = blur(np.roll(np.roll(shape * corner_lift ** 1.5, int(78 * curl), 0), int(8 * curl), 1), 52 * max(curl, 0.4)) * 0.62
    contact = blur(np.roll(shape, 4, 0), 4) * 0.2
    layer.darken(np.clip(cast + contact, 0, 0.85))
    fibre = (fbm(40, 2, seed + 1) - 0.5) * 0.02
    sheen = 0.02 * np.exp(-((t - 0.12) / 0.12) ** 2) * (t > 0)
    light = 1.02 - 0.13 * lift - 0.08 * (corner_lift - lift) + sheen + fibre
    paint = rgb(colour)[None, None, :] * light[..., None]
    paint = paint + (np.clip(1 - (bottom - YY) / 5, 0, 1) * inside)[..., None] * 0.05
    layer.paint(np.clip(paint * (0.92 if dark else 1), 0, 1), shape)


def string(layer, a, b, colour, width=15):
    shape = blur(line([a, b], width), 0.8)
    layer.darken(np.roll(np.roll(blur(shape, 5), 14, 0), 8, 1) * 0.3)
    twist = (np.sin((XX + YY) / 6.0) * 0.5 + 0.5)[..., None] * 0.1
    layer.paint(np.clip(rgb(colour)[None, None, :] * (0.92 + twist), 0, 1), shape)


def pin(layer, cx, cy, colour, r=60):
    """A round-headed pushpin seen from the front."""
    layer.darken(blur(ellipse(cx - r + 14, cy - r + 22, 2 * r, 2 * r), 12) * 0.35)
    dx, dy = (XX - cx) / r, (YY - cy) / r
    d2 = dx * dx + dy * dy
    coverage = np.clip((1 - d2) * r / 2, 0, 1)
    z = np.sqrt(np.clip(1 - d2, 0, 1))
    lambert = np.clip(-0.25 * dx - 0.55 * dy + 0.8 * z, 0, 1)
    colour_ = rgb(colour)[None, None, :] * (0.35 + 0.75 * lambert[..., None])
    highlight = np.exp(-(((dx + 0.28) ** 2 + (dy + 0.42) ** 2) / 0.035)) * 0.75
    rim = np.clip((d2 - 0.75) / 0.25, 0, 1) * 0.25
    layer.paint(np.clip((colour_ + highlight[..., None]) * (1 - rim[..., None]), 0, 1), coverage)


def magnet(layer, cx, cy, colour, r=70):
    """A round desk magnet seen from the front: a short cylinder with a glossy top."""
    layer.darken(blur(ellipse(cx - r + 10, cy - r + 26, 2 * r, 2 * r), 16) * 0.4)
    base = rgb(colour)
    layer.paint(np.clip(np.ones((N, N, 3)) * base * 0.62, 0, 1), ellipse(cx - r, cy - r + 16, 2 * r, 2 * r))
    d = np.sqrt(((XX - cx) / r) ** 2 + ((YY - cy) / r) ** 2)
    face = base[None, None, :] * (1.05 - 0.18 * np.clip((YY - (cy - r)) / (2 * r), 0, 1))[..., None]
    rim = np.clip((d - 0.82) / 0.18, 0, 1) * 0.12
    highlight = np.exp(-(((XX - (cx - r * 0.3)) / (r * 0.35)) ** 2 + ((YY - (cy - r * 0.45)) / (r * 0.18)) ** 2)) * 0.35
    layer.paint(np.clip(face - rim[..., None] + highlight[..., None], 0, 1), ellipse(cx - r, cy - r, 2 * r, 2 * r))


# The board --------------------------------------------------------------------------------------------------------

LIFT = 30  # the arrangement sits this much above the centre, since the shadows fall below it


def things(look, string_colour, fastener, fastener_colour):
    dark = look == "dark"
    layer = Layer()
    index_card(layer, 1000, 300 - LIFT, 820, 560, dark, 30)
    code_screenshot(layer, 200, 520 - LIFT, 640, 768, dark)
    sticky_note(layer, 820, 1130 - LIFT, 660, dark)
    points = [(1410, 362 - LIFT), (520, 576 - LIFT), (1150, 1196 - LIFT)]
    for a, b in ((0, 1), (1, 2), (2, 0)):
        string(layer, points[a], points[b], string_colour)
    for px, py in points:
        if fastener == "pin":
            pin(layer, px, py, fastener_colour)
        else:
            magnet(layer, px, py, fastener_colour)
    return layer


# name, document, surface per look, plate colours (light, dark), fastener, string and fastener colour
BOARDS = [
    ("pinboard", "AppIcon", lambda look: fabric(*(("#CFC7BA", "#ADA493") if look == "light" else ("#4A453E", "#2A2622"))),
     (("#CFC7BA", "#ADA493"), ("#4A453E", "#2A2622")), "pin", "#4E56C9", "#5A62D8"),
    ("cork", "AppIcon-Cork", lambda look: cork(*(("#CDA87C", "#B08A61") if look == "light" else ("#6B5640", "#463826"))),
     (("#CDA87C", "#B08A61"), ("#6B5640", "#463826")), "pin", "#4E56C9", "#5A62D8"),
    ("metal", "AppIcon-Metal", lambda look: metal("#D9DCE1" if look == "light" else "#4B4E56", look == "dark"),
     (("#D9DCE1", "#B9BDC5"), ("#4B4E56", "#2A2C31")), "magnet", "#4E56C9", "#5A62D8"),
    ("whiteboard", "AppIcon-Whiteboard",
     lambda look: whiteboard(*(("#FBFBFC", "#E9EAEE") if look == "light" else ("#33353B", "#1B1C20")), look == "dark"),
     (("#FBFBFC", "#E9EAEE"), ("#33353B", "#1B1C20")), "magnet", "#4E56C9", "#5A62D8"),
    ("slate", "AppIcon-Slate", lambda look: fabric(*(("#A4ADBF", "#7C869B") if look == "light" else ("#3A3F4B", "#1F2229"))),
     (("#A4ADBF", "#7C869B"), ("#3A3F4B", "#1F2229")), "pin", "#F4F4F6", "#F2F2F4"),
    ("navy", "AppIcon-Navy", lambda look: fabric(*(("#434AA3", "#272C6E") if look == "light" else ("#262A5C", "#111330"))),
     (("#434AA3", "#272C6E"), ("#262A5C", "#111330")), "pin", "#F4F4F6", "#F2F2F4"),
    ("sage", "AppIcon-Sage", lambda look: fabric(*(("#BCC5B3", "#98A28D") if look == "light" else ("#3E443A", "#22261F"))),
     (("#BCC5B3", "#98A28D"), ("#3E443A", "#22261F")), "pin", "#4E56C9", "#5A62D8"),
]


def icon_colour(hex_colour):
    return "srgb:" + ",".join(f"{v:.5f}" for v in rgb(hex_colour)) + ",1.00000"


def gradient(top, bottom):
    return {"linear-gradient": [icon_colour(top), icon_colour(bottom)],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def layer_entry(name):
    return {"name": name, "glass": False, "image-name-specializations": [
        {"value": f"{name}-light.png"}, {"appearance": "dark", "value": f"{name}-dark.png"}]}


def document(path, plate):
    """The Icon Composer document: the things in front, the surface behind; neither is glass, since the pictures carry
    their own light and shadows."""
    (light_top, light_bottom), (dark_top, dark_bottom) = plate
    doc = {
        "fill-specializations": [{"value": gradient(light_top, light_bottom)},
                                 {"appearance": "dark", "value": gradient(dark_top, dark_bottom)}],
        "groups": [
            {"name": "Things", "layers": [layer_entry("things")],
             "shadow": {"kind": "none", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.5}},
            {"name": "Surface", "layers": [layer_entry("surface")],
             "shadow": {"kind": "none", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.5}},
        ],
        "supported-platforms": {"squares": "shared"},
    }
    with open(os.path.join(path, "icon.json"), "w") as file:
        json.dump(doc, file, indent=2, sort_keys=True)
        file.write("\n")


def main():
    wanted = set(sys.argv[1:])
    for name, file, surface, plate, fastener, string_colour, fastener_colour in BOARDS:
        if wanted and name not in wanted:
            continue
        path = f"GitIssues/{file}.icon"
        assets = os.path.join(path, "Assets")
        os.makedirs(assets, exist_ok=True)
        for old in os.listdir(assets):
            os.remove(os.path.join(assets, old))
        for look in ("light", "dark"):
            save_surface(surface(look), os.path.join(assets, f"surface-{look}.png"))
            things(look, string_colour, fastener, fastener_colour).save(os.path.join(assets, f"things-{look}.png"))
        document(path, plate)
        print(f"Wrote {path} ({name})")


if __name__ == "__main__":
    main()
