# Lays out the README images from the Mac captures that Tools/readme-images.sh takes and from the iPhone and iPad
# App Store screenshots that Tools/app-store-screenshots.sh takes.
#   python3 Tools/readme-images/build.py <captures folder>
# Writes Design/screenshots/*.webp and Design/social-preview.png. Every image comes in light and dark; the README
# shows the one that matches the reader's theme.
import glob
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from compose import THEMES, cut_rows, device, layout, place, rounded, scaled, shadow_onto, backdrop, trim_empty_rows

raw = sys.argv[1]
out = "Design/screenshots"
store = "Design/screenshots/app-store"
os.makedirs(out, exist_ok=True)


def webp(img, name):
    img.save(f"{out}/{name}.webp", quality=92, method=6)
    print(f"  {out}/{name}.webp")


def window(name):
    return Image.open(f"{raw}/{name}.png").convert("RGBA")


def crop_card(img, box, theme):
    return rounded(img.crop(box), 24, THEMES[theme]["border"])


# Points in the 1280 x 820 window at 2x where the palette and the new-issue dialog sit, with some context around. The
# due date picker opens in the palette and fits the same box.
PALETTE_BOX = (560, 224, 2000, 1350)
NEW_ISSUE_BOX = (480, 204, 2080, 944)


def drag_animation(theme, board, band):
    """The recorded drag as an animated WebP on the backdrop, trimmed to the motion."""
    video = f"{raw}/drag-{theme}.mov"
    fps, width = 30, 1600
    # Where the card moves: compare each frame with the one before, small and grey.
    small = subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vf", "fps=30,scale=320:205,format=gray",
                            "-f", "rawvideo", "-"], capture_output=True, check=True).stdout
    frames = np.frombuffer(small, np.uint8).reshape(-1, 205, 320).astype(int)
    moving = [k for k in range(1, len(frames)) if np.abs(frames[k] - frames[k - 1])[20:].mean() > 0.05]
    if not moving:
        sys.exit(f"The recording {video} shows no drag.")
    start, end = max(0, moving[0] / fps - 0.4), moving[-1] / fps + 0.7

    still = np.asarray(board)
    shape = np.asarray(cut_rows(board, band) if band else board)
    pad = (160, 130)
    W, H = shape.shape[1] + 2 * pad[0], shape.shape[0] + 2 * pad[1]
    # The backdrop, the shadow and the rim stay the same in every frame: draw them once on a canvas with the window
    # cut out, then put each frame underneath.
    empty = Image.fromarray(shape.copy(), "RGBA")
    base = place(empty, theme, pad, out_width=10 ** 6).convert("RGBA")
    with tempfile.TemporaryDirectory() as work:
        subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-to", str(end), "-i", video, "-vf", f"fps={fps}",
                        "-pix_fmt", "rgb24", f"{work}/f%04d.png"], check=True)
        paths = []
        for k, path in enumerate(sorted(glob.glob(f"{work}/f*.png"))):
            rgb = np.asarray(Image.open(path).convert("RGB"))
            frame = np.dstack([rgb, np.full(rgb.shape[:2], 255, np.uint8)])
            # A recording shows a capture indicator over the traffic lights; take them from the still.
            frame[:76, :200] = still[:76, :200]
            if band:
                frame = np.concatenate([frame[:band[0]], frame[band[1]:]])
            frame[..., 3] = shape[..., 3]
            img = base.copy()
            img.alpha_composite(Image.fromarray(frame, "RGBA"), pad)
            img = img.convert("RGB").resize((width, round(H * width / W)), Image.LANCZOS)
            paths.append(f"{work}/o{k:04d}.png")
            img.save(paths[-1])
        command = ["img2webp", "-loop", "0", "-lossy", "-q", "82", "-m", "6"]
        for path in paths:
            command += ["-d", str(round(1000 / fps)), path]
        command[-2] = "900"  # a moment's rest before it starts over
        subprocess.run(command + ["-o", f"{out}/drag-{theme}.webp"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"  {out}/drag-{theme}.webp")


print("Mac")
for theme in ["dark", "light"]:
    board, band = trim_empty_rows(window(f"board-{theme}"))
    webp(place(board, theme, (160, 130), 2000), f"hero-{theme}")
    drag_animation(theme, window(f"board-{theme}"), band)
    webp(place(window(f"issue-{theme}"), theme, (130, 110), 1800), f"issue-{theme}")
    webp(place(window(f"inbox-{theme}"), theme, (130, 110), 1800), f"inbox-{theme}")
    webp(place(window(f"repository-{theme}"), theme, (130, 110), 1800), f"repository-{theme}")
    webp(place(crop_card(window(f"palette-{theme}"), PALETTE_BOX, theme), theme, (110, 90), 1600, rim=False), f"palette-{theme}")
    webp(place(crop_card(window(f"due-{theme}"), PALETTE_BOX, theme), theme, (110, 90), 1600, rim=False), f"due-date-{theme}")
    webp(place(crop_card(window(f"new-{theme}"), NEW_ISSUE_BOX, theme), theme, (110, 90), 1600, rim=False), f"new-issue-{theme}")

# The list, light and dark in one picture, split on a slant.
dark = place(window("list-dark"), "dark", (130, 110), 1800)
light = place(window("list-light"), "light", (130, 110), 1800)
w, h = dark.size
ys, xs = np.mgrid[0:h, 0:w]
mask = np.clip(w * (0.60 - 0.20 * ys / h) - xs + 0.5, 0, 1)
light.paste(dark, (0, 0), Image.fromarray((mask * 255).astype(np.uint8), "L"))
webp(light, "list-appearance")

print("iPhone and iPad")
for theme, pad_shot, phone_shot in [("light", "ipad/1-board", "iphone/1-my-issues"),
                                    ("dark", "ipad/5-board-dark", "iphone/7-project-dark")]:
    ipad = scaled(device(f"{store}/{pad_shot}.png", "ipad"), 0.62)
    phone = scaled(device(f"{store}/{phone_shot}.png", "iphone"), 0.43)
    ix, iy = 170, 140
    hx, hy = ix + ipad.width - round(phone.width * 0.55), iy + ipad.height - phone.height + 150
    size = (hx + phone.width + 170, max(iy + ipad.height, hy + phone.height) + 150)
    webp(layout([(ipad, (ix, iy)), (phone, (hx, hy))], size, theme, 1800), f"devices-{theme}")
phones = [scaled(device(f"{store}/iphone/{s}.png", "iphone"), 0.42) for s in ["2-issue", "4-menu", "5-new-issue"]]
gap, px, py = 80, 150, 120
size = (sum(p.width for p in phones) + gap * (len(phones) - 1) + 2 * px, phones[0].height + 2 * py + 30)
for theme in ["light", "dark"]:
    x, items = px, []
    for p in phones:
        items.append((p, (x, py)))
        x += p.width + gap
    webp(layout(items, size, theme, 1600), f"iphone-{theme}")

print("Social preview")
S = 2  # drawn at 2x, saved at 1280 x 640
canvas = backdrop((1280 * S, 640 * S), "dark").convert("RGBA")
mac = scaled(window("board-dark"), 0.62)
canvas = shadow_onto(canvas, mac, (640 * S, 150 * S), "dark", rim=True)
phone = scaled(device(f"{store}/iphone/7-project-dark.png", "iphone"), 0.165 * S)
canvas = shadow_onto(canvas, phone, (585 * S, 268 * S), "dark")
icon = Image.open("Packages/GitIssuesKit/Sources/GitIssuesKit/Resources/icon-A-dark.png").convert("RGBA")
canvas.alpha_composite(icon.resize((176 * S, 176 * S), Image.LANCZOS), (66 * S, 128 * S))


def font(weight, size):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size * S)
    f.set_variation_by_name(weight)
    return f


d = ImageDraw.Draw(canvas)
d.text((86 * S, 318 * S), "Issues", font=font("Bold", 84), fill=(240, 241, 245))
d.text((88 * S, 422 * S), "GitHub Issues, fast and native", font=font("Medium", 32), fill=(200, 203, 214))
d.text((88 * S, 462 * S), "on Mac, iPhone and iPad.", font=font("Medium", 32), fill=(200, 203, 214))
d.text((88 * S, 530 * S), "Board, list and keyboard flow,", font=font("Regular", 22), fill=(140, 145, 160))
d.text((88 * S, 560 * S), "with everything kept in GitHub.", font=font("Regular", 22), fill=(140, 145, 160))
canvas.convert("RGB").resize((1280, 640), Image.LANCZOS).save("Design/social-preview.png", optimize=True)
print("  Design/social-preview.png")
