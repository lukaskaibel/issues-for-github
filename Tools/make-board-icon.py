#!/usr/bin/env python3
"""Draws the app icon: a board with three columns divided only by two thin lines, as the lines in Notes and Reminders
divide a page, and three cards to do, two in progress and one done in the status colours. The board on its light page
is the app's own icon; on graphite and on indigo it is one of the choices in Settings (the Mac sets them as the Dock
icon, iPhone and iPad as alternate icons).

    python3 Tools/make-board-icon.py [board …]     every board, or only those named (board, graphite, indigo)

Writes an Icon Composer document per board: GitIssues/AppIcon.icon for the board and GitIssues/AppIcon-<Name>.icon for
the others, each with a light and a dark look. Tools/render-icons.sh then renders the pictures the app, the README and
the website use. Needs Pillow (pip install pillow).

The grid, on the 1024 px canvas: the outer cards end 128 px from the edge, Apple's margin; one gap of 32 px lies
between a card and a line and between two cards, so every card is 213 px wide. The lines are 20 px, the weight of
Notes' lines. Two layers per look: the cards, which are glass and cast Icon Composer's shadow, and the lines, flat.
Everything is drawn at four times the size and scaled down, for smooth edges.
"""

import json
import os
import sys

from PIL import Image, ImageDraw

SIZE, SCALE = 1024, 4
MARGIN, GAP, LINE = 128, 32, 20
TOP, BOTTOM = 136, 888          # the cards' rows
CARD_W = (SIZE - 2 * MARGIN - 4 * GAP) / 3
CARD_H = (BOTTOM - TOP - 2 * GAP) / 3
RADIUS = 36
COLUMNS = [MARGIN + i * (CARD_W + 2 * GAP) for i in range(3)]
LINES = [MARGIN + CARD_W + GAP, MARGIN + 2 * CARD_W + 3 * GAP]
COUNTS = (3, 2, 1)              # to do, in progress, done


def rgb(hex_colour, alpha=255):
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def vertical(top, bottom):
    """A gradient over the whole canvas, top to bottom, so a card shows the part of it where it sits."""
    a, b = rgb(top), rgb(bottom)
    strip = Image.new("RGBA", (1, SIZE * SCALE))
    for y in range(SIZE * SCALE):
        t = y / (SIZE * SCALE - 1)
        strip.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(4)))
    return strip.resize((SIZE * SCALE, SIZE * SCALE))


def rounded(image, box, radius, paint):
    """Paints a colour or a picture through a rounded rectangle."""
    x, y, w, h = (v * SCALE for v in box)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([x, y, x + w, y + h], radius=radius * SCALE, fill=255)
    if isinstance(paint, tuple):
        paint = Image.new("RGBA", image.size, paint)
    image.paste(paint, (0, 0), mask)


def save(image, path):
    image.resize((SIZE, SIZE), Image.LANCZOS).save(path, optimize=True)


def cards(fills):
    image = Image.new("RGBA", (SIZE * SCALE,) * 2, (0, 0, 0, 0))
    for column, count in enumerate(COUNTS):
        for row in range(count):
            rounded(image, (COLUMNS[column], TOP + row * (CARD_H + GAP), CARD_W, CARD_H), RADIUS, fills[column])
    return image


def lines(colour):
    image = Image.new("RGBA", (SIZE * SCALE,) * 2, (0, 0, 0, 0))
    for x in LINES:
        rounded(image, (x - LINE / 2, MARGIN, LINE, SIZE - 2 * MARGIN), LINE / 2, colour)
    return image


INDIGO = lambda: vertical("#7A82EE", "#4A52C2")
BRIGHT_INDIGO = lambda: vertical("#8F97FF", "#6870F0")
LIGHT_CARDS = lambda: (rgb("#BEC2F3"), rgb("#F0C77E"), INDIGO())
# On a dark plate the status colours turn brighter, not darker, so in progress and done still glow.
DARK_CARDS = lambda: (rgb("#5C62B0"), rgb("#F2B14A"), BRIGHT_INDIGO())
WHITE_CARDS = lambda: (rgb("#FFFFFF"),) * 3

# name, document, plate (light top and bottom, dark top and bottom), cards and lines per look
BOARDS = [
    ("board", "AppIcon", (("#F8F8F7", "#EFEFEF"), ("#3A3A3E", "#1F1F22")),
     {"light": (LIGHT_CARDS, rgb("#BCBCBE")), "dark": (DARK_CARDS, rgb("#5E5E64"))}),
    ("graphite", "AppIcon-Graphite", (("#4A4B55", "#25262C"), ("#3A3B44", "#18191D")),
     {"light": (DARK_CARDS, rgb("#6A6B75")), "dark": (DARK_CARDS, rgb("#5E5F68"))}),
    ("indigo", "AppIcon-Indigo", (("#7179E8", "#3F47B8"), ("#3A4090", "#171A44")),
     {"light": (WHITE_CARDS, rgb("#FFFFFF", 102)), "dark": (WHITE_CARDS, rgb("#FFFFFF", 90))}),
]


def icon_colour(hex_colour):
    return "srgb:" + ",".join(f"{v / 255:.5f}" for v in rgb(hex_colour)[:3]) + ",1.00000"


def gradient(top, bottom):
    return {"linear-gradient": [icon_colour(top), icon_colour(bottom)],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def layer_entry(name, glass):
    return {"name": name, "glass": glass, "image-name-specializations": [
        {"value": f"{name}-light.png"}, {"appearance": "dark", "value": f"{name}-dark.png"}]}


def document(path, plate):
    """The Icon Composer document: the cards in front as glass with a neutral shadow, the lines behind, flat."""
    (light_top, light_bottom), (dark_top, dark_bottom) = plate
    doc = {
        "fill-specializations": [{"value": gradient(light_top, light_bottom)},
                                 {"appearance": "dark", "value": gradient(dark_top, dark_bottom)}],
        "groups": [
            {"name": "Cards", "layers": [layer_entry("cards", True)],
             "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.4}},
            {"name": "Lines", "layers": [layer_entry("lines", False)], "specular": False,
             "shadow": {"kind": "none", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.4}},
        ],
        "supported-platforms": {"squares": "shared"},
    }
    with open(os.path.join(path, "icon.json"), "w") as file:
        json.dump(doc, file, indent=2, sort_keys=True)
        file.write("\n")


def main():
    wanted = set(sys.argv[1:])
    for name, file, plate, looks in BOARDS:
        if wanted and name not in wanted:
            continue
        path = f"GitIssues/{file}.icon"
        assets = os.path.join(path, "Assets")
        os.makedirs(assets, exist_ok=True)
        for old in os.listdir(assets):
            os.remove(os.path.join(assets, old))
        for look, (fills, line_colour) in looks.items():
            save(cards(fills()), os.path.join(assets, f"cards-{look}.png"))
            save(lines(line_colour), os.path.join(assets, f"lines-{look}.png"))
        document(path, plate)
        print(f"Wrote {path} ({name})")


if __name__ == "__main__":
    main()
