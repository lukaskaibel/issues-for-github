#!/bin/bash
# Takes the README's screenshots of the Mac app and lays them out, with the iPhone and iPad App Store screenshots,
# as Design/screenshots/*.webp and Design/social-preview.png, and makes the website's pictures (Website/images).
#   Tools/readme-images.sh
# The Mac app runs on the sample data, so no GitHub account is needed and nothing is sent anywhere. It comes to the
# front for about a minute and the pointer goes to the right edge of the screen, beside its window; leave keyboard and
# mouse alone until the script is done. Needs an unlocked screen, a Retina display, Screen Recording permission for
# the terminal, Python 3 with Pillow and NumPy, ffmpeg and img2webp (brew install ffmpeg webp). Run
# Tools/app-store-screenshots.sh first when the iPhone or iPad app looks different.
set -euo pipefail
cd "$(dirname "$0")/.."

work=build/readme-images
raw=$work/raw
app=build/DerivedData/Build/Products/Debug/Issues.app

python3 -c "import PIL, numpy" 2>/dev/null || { echo "Needs Pillow and NumPy: pip3 install pillow numpy" >&2; exit 1; }
for tool in ffmpeg img2webp; do
  command -v $tool >/dev/null || { echo "Needs $tool: brew install ffmpeg webp" >&2; exit 1; }
done
[ -f Design/screenshots/app-store/iphone/1-board.png ] || { echo "Run Tools/app-store-screenshots.sh first." >&2; exit 1; }

echo "Building…"
xcodebuild -project GitIssues.xcodeproj -scheme GitIssues -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData build -quiet
bundle_id=$(defaults read "$PWD/$app/Contents/Info" CFBundleIdentifier)
mkdir -p "$raw"
swiftc -O Tools/readme-images/capture.swift -o "$work/capture" 2>/dev/null

# The debug app shares its settings with the real one. Note what the scenes change and put it back afterwards.
keys=(appearance viewMode selectedProject inbox.selected inbox.bucket roadmap.layout roadmap.zoom timeline.scale showsIssueInspector
  mine.display mine.filter "NSWindow Frame main")
saved=()
types=()
for key in "${keys[@]}"; do
  saved+=("$(defaults read "$bundle_id" "$key" 2>/dev/null || echo "<unset>")")
  # "Type is boolean", "Type is string"…: written back as what it was.
  types+=("$( (defaults read-type "$bundle_id" "$key" 2>/dev/null || true) | awk '{ print $3 }')")
done
previous=$(lsappinfo info -only bundlepath "$(lsappinfo front)" | sed -nE 's/.*"(.+)".*/\1/p')
pid=""

finish() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  for i in "${!keys[@]}"; do
    if [ "${saved[$i]}" = "<unset>" ]; then defaults delete "$bundle_id" "${keys[$i]}" 2>/dev/null || true; continue; fi
    case ${types[$i]} in
      boolean) type=-bool ;;
      integer) type=-int ;;
      float) type=-float ;;
      *) type=-string ;;
    esac
    defaults write "$bundle_id" "${keys[$i]}" "$type" "${saved[$i]}"
  done
  [ -n "$previous" ] && open -a "$previous" 2>/dev/null || true
}
trap finish EXIT

# say <command>…: drives the app through its debug remote (UI/Mac/DebugRemote.swift).
say() { for line in "$@"; do echo "$line" >> "$work/cmd"; done; }

# spot <number> <across> <down>: a point in an issue's card on the board, in board points, as fractions of its width
# and of the way down to the card under it, from where the debug remote says the cards are.
spot() {
  say dump; sleep 0.6
  python3 - "$work/cmd.log" "#$1" "$2" "$3" <<'PY'
import re, sys
log, number, across, down = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
for line in reversed(open(log).read().splitlines()):
    found = re.search(r"column .* frame=\(([-\d.]+), [-\d.]+, ([-\d.]+), [-\d.]+\) cards=(.*)", line)
    if not found or f" {number}:" not in f" {found[3]}":
        continue
    tops = {n: tuple(map(int, p.split(","))) for n, p in (card.split(":") for card in found[3].split())}
    x, y = tops[number]
    below = min((top for _, top in tops.values() if top > y), default=y + 100)
    # Sub-issues are indented on the left only: every card ends as far from the column's right edge as the outermost
    # one starts from its left edge.
    left, column = float(found[1]), float(found[2])
    width = left + column - (min(p[0] for p in tops.values()) - left) - x
    print(round(x + width * across), round(y + (below - y) * down))
    sys.exit()
sys.exit(f"No card {number} on the board.")
PY
}

front_pid() { lsappinfo info -only pid "$(lsappinfo front)" | sed -nE 's/.*pid ?= ?([0-9]+).*/\1/p'; }

forward() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(front_pid)" = "$pid" ] && return 0
    open "$app"
    sleep 0.5
  done
  echo "The app doesn't come to the front. Is the screen locked?" >&2
  exit 1
}

shot() {
  local code
  for _ in 1 2 3 4; do
    forward
    sleep 0.3
    if "$work/capture" shot "$pid" "$raw/$1.png"; then return 0; else code=$?; fi
    # 3: the window was drawn inactive, as when another app came to the front meanwhile.
    [ "$code" = 3 ] || exit "$code"
    sleep 0.5
  done
  echo "The window stayed inactive for $1." >&2
  exit 1
}

launch() {
  : > "$work/cmd"
  rm -f "$work/cmd.log"
  # The pointer out of the way first: what appears under it lights up, even though the window lets it through.
  "$work/capture" park
  open -n -g "$app" --args -demo.active YES -screenshotMode YES -viewMode board -timeline.scale 5 -appearance "$1" \
    -AppleLanguages '(en)' -AppleLocale en_US -debugCommandFile "$PWD/$work/cmd" "-NSWindow Frame main" "160 80 1280 820 0 0 1512 949"
  for _ in $(seq 40); do
    pid=$(pgrep -nf "$PWD/$app/Contents/MacOS" || true)
    [ -n "$pid" ] && break
    sleep 0.25
  done
  [ -n "$pid" ] || { echo "The app didn't start." >&2; exit 1; }
  for _ in $(seq 60); do
    say dump
    sleep 0.5
    grep -q "project=Git Issues" "$work/cmd.log" 2>/dev/null && return 0
    say "select Git Issues"
  done
  echo "The app didn't show the sample project." >&2
  exit 1
}

for theme in dark light; do
  echo "Scenes in ${theme}…"
  launch "$theme"
  forward
  # The same size, at the top left of the screen, and letting the pointer through, so wherever it rests it puts no
  # hover into the pictures.
  say "window 1280 820 onscreen"
  # The project's first view, as GitHub has it: the view and how it shows are remembered from the last run.
  say "view Board" "display reset"
  # Switching views lays the board out afresh, so the debug remote knows where every card is.
  say "mode list"; sleep 0.8; say "mode board" "focus"; sleep 1.5

  # A drag first, recorded: #9 and its two sub-issues to the end of In Review, then Esc. It goes below the cards there:
  # on its way up to a place between two of them it would cross the middle of one, which lights up to take it as its
  # sub-issue.
  rm -f "$raw/drag-$theme.mov"
  "$work/capture" rec "$pid" "$raw/drag-$theme.mov" 4.6 > "$work/rec.log" &
  recorder=$!
  for _ in $(seq 40); do grep -q recording "$work/rec.log" 2>/dev/null && break; sleep 0.1; done
  sleep 0.8
  say "drag 9 3 hold In Review"; sleep 1.8
  say "canceldrag"
  wait $recorder
  sleep 0.8
  # A cancelled drag ends for good only when the pointer lets go; until then no other drag starts.
  say "drop"; sleep 0.3

  shot "board-$theme"
  # A card held over the middle of another one goes under it when dropped: #24 lifted in Todo, then held low in #9 and
  # near its right edge, so #9's number and title show beside it.
  at=$(spot 9 0.95 0.68)
  say "drag 24 0 hold Todo"; sleep 1
  say "dragto $at"; sleep 1.2
  shot "nest-$theme"
  say "canceldrag"; sleep 0.8; say "drop"; sleep 0.5
  # The issue with its properties in the inspector beside it, whether or not the inspector was last left open.
  say "inspector on" "open 9"; sleep 1.5; shot "issue-$theme"
  # Issue #16's description, drawn as on GitHub, with the caret in "bold": its stars show beside it, faintly.
  say "close" "open 16"; sleep 2; say "mdfocus issue-description" "mdcaret old**"; sleep 1.2; shot "markdown-$theme"
  # The board takes the focus back once the issue and its inspector are gone; focus #9 only after that.
  say "close"; sleep 1; say "focus 9" "overlay palette"; sleep 1.2; shot "palette-$theme"
  say "overlay due 9"; sleep 1.2; shot "due-$theme"
  say "overlay none" "focus" "mode list"; sleep 1.2; shot "list-$theme"
  # All Issues of the project: the issues on no board first, with their count in the sidebar.
  say "select all"; sleep 1.2; shot "all-issues-$theme"
  # My Issues' overview as it arranges itself: Needs you, then a card for each project with work started, each on its
  # first page with the icons of its others, then the issues on no board.
  say "select mine" "filter" "display reset" "display layout overview"; sleep 1.5; shot "my-issues-$theme"
  say "display layout list"
  # The roadmap's timeline: the sample's epics over the milestones 0.3, 0.4 and 1.0.
  say "select Git Issues" "select roadmap" "roadmap timeline" "roadmap months"; sleep 1.5; shot "roadmap-$theme"
  # The project's views in the sidebar, "This Week" open with its filter and its cycle over the board.
  say "select Git Issues" "view This Week"; sleep 1.5; shot "views-$theme"
  # A roadmap view as a timeline: the issues of each milestone between their dates, today and the milestones marked.
  say "view Release Plan"; sleep 1.5; shot "timeline-$theme"
  say "view Board"
  say "select Git Issues" "mode board" "overlay new"; sleep 1
  say "key Haptic feedback when a card lands"; sleep 1; shot "new-$theme"
  say "overlay none"
  # The Inbox with Kai's assignment open beside the list.
  say "select inbox"; sleep 1.2; say "entry 25"; sleep 1.5; shot "inbox-$theme"
  say "select Git Issues"

  kill "$pid"
  pid=""
  sleep 1
done

size=$(sips -g pixelWidth -g pixelHeight "$raw/board-dark.png" | awk '/pixel/ { printf "%s ", $2 }')
if [ "$size" != "2560 1640 " ]; then
  echo "The window came out ${size% }px; the layout expects 1280 x 820 points on a Retina display." >&2
  exit 1
fi

echo "Laying out…"
python3 Tools/readme-images/build.py "$raw"
python3 Tools/readme-images/website.py
echo "Done. Check the images, then commit them with the change they show."
