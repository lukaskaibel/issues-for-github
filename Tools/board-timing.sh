#!/bin/bash
# Times the Mac board with long columns: the pointer going down and up two columns, and the longest column scrolling,
# on the sample data ten times over (up to a hundred cards a column).
#   Tools/board-timing.sh [--debug]
# Builds an optimised copy with the debug remote in it (with --debug a debug copy) under its own bundle identifier, so
# it shares no settings with an Issues you have running, parks its window off screen and drives it through the debug
# remote, so the screen may be locked. For each run it prints how long the main thread was busy per pointer step, in
# its longest pass (one frame's work at 120 Hz) and in CPU time, apart for steps that bring another card or part under
# the pointer, and how long a card took to paint; then the scroll test. A frame lasts 8.3 ms at 120 Hz. Run it before
# and after a change to the board, a few times each: single runs differ by a millisecond or so.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration=Release
flags=(SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG)
if [ "${1:-}" = "--debug" ]; then configuration=Debug; flags=(); fi
bundle_id=com.lukaskbl.GitIssues.boardtiming
app=$PWD/build/mac-boardtiming/Build/Products/$configuration/Issues.app
work=$(mktemp -d)
commands=$work/commands
pid=
finish() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null && sleep 0.5
  defaults delete "$bundle_id" 2>/dev/null || true
  rm -rf "$work" "${HOME:?}/Library/Application Support/${bundle_id:?}"
}
trap finish EXIT

echo "Building…"
xcodebuild build -project GitIssues.xcodeproj -scheme GitIssues -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac-boardtiming \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual GI_MAC_ENTITLEMENTS= ${flags[@]+"${flags[@]}"} -quiet > "$work/build.log" 2>&1 \
  || { tail -30 "$work/build.log"; exit 1; }

: > "$commands"
open -g -n "$app" --args -demo.active YES -demo.copies 10 -appearance light \
  -AppleLanguages '(en)' -AppleLocale en_US -debugCommandFile "$commands"
for _ in $(seq 100); do
  pid=$(pgrep -f "$app/Contents/MacOS/Issues" || true)
  [ -n "$pid" ] && break
  sleep 0.1
done
[ -n "$pid" ] || { echo "The app didn't start." >&2; exit 1; }
for _ in $(seq 60); do
  printf 'dump\n' >> "$commands"
  sleep 0.5
  [ -s "$commands.log" ] && break
done
[ -s "$commands.log" ] || { echo "The app doesn't answer the debug remote." >&2; exit 1; }
# The window parked off screen at 1440 x 900 points: Todo's cards are around x 640, In Progress's around x 900.
printf '%s\n' "window 1440 900" "select Git Issues" "mode board" >> "$commands"
sleep 3

# run <title> <command> <text of its last line>
run() {
  : > "$commands.log"
  printf '%s\n' "$2" >> "$commands"
  until grep -q "$3" "$commands.log"; do sleep 1; done
  sleep 0.5
  echo "$1"
  cat "$commands.log"
}
run "Todo, the pointer down and up three times:" "boardsweep 640 100 880" "same cpu frames"
run "In Progress, with sub-issues and epics' headers:" "boardsweep 900 100 880" "same cpu frames"
run "The longest column scrolling, 40 points a step:" "scrolltest board" "scrolltest"
