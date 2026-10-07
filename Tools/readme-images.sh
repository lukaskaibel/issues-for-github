#!/bin/bash
# Takes the README's screenshots of the Mac app and lays them out, with the iPhone and iPad App Store screenshots,
# as Design/screenshots/*.webp and Design/social-preview.png, and makes the website's pictures (Website/images).
#   Tools/readme-images.sh
# The Mac app runs on the sample data, so no GitHub account is needed and nothing is sent anywhere. It comes to the
# front for about a minute; leave keyboard and mouse alone until the script is done. Needs an unlocked screen, a Retina
# display, Screen Recording permission for the terminal, Python 3 with Pillow and NumPy, ffmpeg and img2webp
# (brew install ffmpeg webp). Run Tools/app-store-screenshots.sh first when the iPhone or iPad app looks different.
set -euo pipefail
cd "$(dirname "$0")/.."

work=build/readme-images
raw=$work/raw
app=build/DerivedData/Build/Products/Debug/Issues.app

python3 -c "import PIL, numpy" 2>/dev/null || { echo "Needs Pillow and NumPy: pip3 install pillow numpy" >&2; exit 1; }
for tool in ffmpeg img2webp; do
  command -v $tool >/dev/null || { echo "Needs $tool: brew install ffmpeg webp" >&2; exit 1; }
done
[ -f Design/screenshots/app-store/iphone/1-my-issues.png ] || { echo "Run Tools/app-store-screenshots.sh first." >&2; exit 1; }

echo "Building…"
xcodebuild -project GitIssues.xcodeproj -scheme GitIssues -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData build -quiet
bundle_id=$(defaults read "$PWD/$app/Contents/Info" CFBundleIdentifier)
mkdir -p "$raw"
swiftc -O Tools/readme-images/capture.swift -o "$work/capture" 2>/dev/null

# The debug app shares its settings with the real one. Note what the scenes change and put it back afterwards.
keys=(appearance viewMode selectedProject "NSWindow Frame main")
saved=()
for key in "${keys[@]}"; do saved+=("$(defaults read "$bundle_id" "$key" 2>/dev/null || echo "<unset>")"); done
previous=$(lsappinfo info -only bundlepath "$(lsappinfo front)" | sed -nE 's/.*"(.+)".*/\1/p')
pid=""

finish() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  for i in "${!keys[@]}"; do
    if [ "${saved[$i]}" = "<unset>" ]; then defaults delete "$bundle_id" "${keys[$i]}" 2>/dev/null || true
    else defaults write "$bundle_id" "${keys[$i]}" -string "${saved[$i]}"; fi
  done
  [ -n "$previous" ] && open -a "$previous" 2>/dev/null || true
}
trap finish EXIT

# say <command>…: drives the app through its debug remote (UI/Mac/DebugRemote.swift).
say() { for line in "$@"; do echo "$line" >> "$work/cmd"; done; }

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
  forward
  sleep 0.3
  "$work/capture" shot "$pid" "$raw/$1.png"
}

launch() {
  : > "$work/cmd"
  rm -f "$work/cmd.log"
  open -n -g "$app" --args -demo.active YES -screenshotMode YES -viewMode board -appearance "$1" \
    -debugCommandFile "$PWD/$work/cmd" "-NSWindow Frame main" "160 80 1280 820 0 0 1512 949"
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
  # Switching views lays the board out afresh, so the debug remote knows where every card is.
  say "mode list"; sleep 0.8; say "mode board" "focus"; sleep 1.5

  # A drag first: after a cancelled drag the debug remote can't start another until the app restarts.
  rm -f "$raw/drag-$theme.mov"
  "$work/capture" rec "$pid" "$raw/drag-$theme.mov" 4.6 > "$work/rec.log" &
  recorder=$!
  for _ in $(seq 40); do grep -q recording "$work/rec.log" 2>/dev/null && break; sleep 0.1; done
  sleep 0.8
  say "drag 9 1 hold In Review"; sleep 1.8
  say "canceldrag"
  wait $recorder
  sleep 0.8

  shot "board-$theme"
  say "open 9"; sleep 1.5; shot "issue-$theme"
  say "close" "focus 9" "overlay palette"; sleep 1.2; shot "palette-$theme"
  say "overlay none" "focus" "mode list"; sleep 1.2; shot "list-$theme"
  say "select repo git-issues"; sleep 1.2; shot "repository-$theme"
  say "select Git Issues" "mode board" "overlay new"; sleep 1
  say "key Haptic feedback when a card lands"; sleep 1; shot "new-$theme"
  say "overlay none"

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
