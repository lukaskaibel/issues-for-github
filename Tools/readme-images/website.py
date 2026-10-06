# Makes the website's pictures from the iPhone and iPad App Store screenshots and the app icon.
#   python3 Tools/readme-images/website.py
# Writes Website/images: the iPad and the iPhone in their frames on a transparent ground (the page draws the shadows),
# in light and dark, and the icons. Tools/readme-images.sh runs it after the README images.
import os
import subprocess
import tempfile

from PIL import Image

from compose import device, scaled

store = "Design/screenshots/app-store"
icons = "Packages/GitIssuesKit/Sources/GitIssuesKit/Resources"
out = "Website/images"
os.makedirs(out, exist_ok=True)


def save(img, name, **options):
    img.save(f"{out}/{name}", **options)
    print(f"  {out}/{name}")


for theme, pad_shot, phone_shot in [("light", "ipad/1-board", "iphone/1-my-issues"),
                                    ("dark", "ipad/5-board-dark", "iphone/7-project-dark")]:
    save(scaled(device(f"{store}/{pad_shot}.png", "ipad"), 0.62), f"ipad-{theme}.webp", quality=86, method=6)
    save(scaled(device(f"{store}/{phone_shot}.png", "iphone"), 0.46), f"iphone-{theme}.webp", quality=86, method=6)

for theme in ["light", "dark"]:
    icon = Image.open(f"{icons}/icon-A-{theme}.png").convert("RGBA")
    save(icon.resize((288, 288), Image.LANCZOS), f"icon-{theme}.png", optimize=True)
    save(icon.resize((64, 64), Image.LANCZOS), f"favicon-{theme}.png", optimize=True)

# The home-screen icon is the square iOS rendition; the system rounds it.
ictool = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip() \
    + "/../Applications/Icon Composer.app/Contents/Executables/ictool"
with tempfile.TemporaryDirectory() as work:
    subprocess.run([ictool, "GitIssues/AppIcon.icon", "--export-image", "--output-file", f"{work}/touch.png",
                    "--platform", "iOS", "--rendition", "Default", "--width", "180", "--height", "180", "--scale", "1"],
                   check=True, stdout=subprocess.DEVNULL)
    save(Image.open(f"{work}/touch.png").convert("RGBA"), "apple-touch-icon.png", optimize=True)
