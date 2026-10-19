#!/bin/bash
# Takes the Mac App Store screenshots from the sample data, 2880 x 1800, into Design/screenshots/app-store/mac.
#   Tools/mac-app-store-screenshots.sh
# Builds a debug copy with its own bundle identifier, so it shares no settings with an Issues you have running,
# drives it through the debug remote, takes each window as it is on screen with Tools/readme-images/capture.swift (the
# sidebar and the glass of the toolbar don't show in the app's own snapshots) and frames it with
# Tools/store-frame.swift. Needs an unlocked screen: the app comes to the front for each picture, about a minute in all.
set -euo pipefail
cd "$(dirname "$0")/.."

out=Design/screenshots/app-store/mac
app=$PWD/build/mac-screenshots/Build/Products/Debug/Issues.app
work=$(mktemp -d)
commands=$work/commands
pid=
bundle_id=com.lukaskbl.GitIssues.screenshots
finish() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null && sleep 0.5
  defaults delete "$bundle_id" 2>/dev/null || true
  rm -rf "$work" "${HOME:?}/Library/Application Support/${bundle_id:?}"
}
previous=$(lsappinfo info -only bundlepath "$(lsappinfo front)" | sed -nE 's/.*"(.+)".*/\1/p')
trap 'finish; [ -n "$previous" ] && open -a "$previous" 2>/dev/null || true' EXIT

echo "Building…"
xcodebuild build -project GitIssues.xcodeproj -scheme GitIssues -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/mac-screenshots \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual GI_MAC_ENTITLEMENTS= -quiet
swiftc -O Tools/readme-images/capture.swift -o "$work/capture"

: > "$commands"
open -g -n "$app" --args -demo.active YES -screenshotMode YES -appearance light \
  -AppleLanguages '(en)' -AppleLocale en_US -debugCommandFile "$commands"
for _ in $(seq 100); do
  pid=$(pgrep -if "$app/Contents/MacOS/Issues" || true)
  [ -n "$pid" ] && break
  sleep 0.1
done
[ -n "$pid" ] || { echo "The app didn't start." >&2; exit 1; }

send() { printf '%s\n' "$@" >> "$commands"; }
# The remote skips lines written before it started, so knock until it answers.
for _ in $(seq 60); do
  send dump
  sleep 0.5
  [ -s "$commands.log" ] && break
done
[ -s "$commands.log" ] || { echo "The debug remote didn't answer." >&2; exit 1; }

# shot <name> <appearance> <width> <height> <command>…: sets the scene up, lets it settle and takes the window.
# front: brings the app to the front, so its window is drawn as the active one, with coloured traffic lights.
front() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(lsappinfo info -only pid "$(lsappinfo front)" | sed -nE 's/.*pid ?= ?([0-9]+).*/\1/p')" = "$pid" ] && return 0
    open "$app"
    sleep 0.5
  done
  echo "The app doesn't come to the front. Is the screen locked?" >&2
  exit 1
}

shot() {
  local name=$1 appearance=$2 width=$3 height=$4
  shift 4
  send "overlay none" "appearance $appearance" "window $width $height onscreen" "select Git Issues" "mode board"
  sleep 1
  for command in "$@"; do send "$command"; sleep 0.6; done
  local code
  for _ in 1 2 3 4; do
    front
    sleep 1.2
    if "$work/capture" shot "$pid" "$work/$name.png"; then code=0; break; else code=$?; fi
    # 3: the window was drawn inactive, as when another app came to the front meanwhile.
    [ "$code" = 3 ] || break
  done
  case $code in
    0) ;;
    3) echo "The window stayed inactive for $name." >&2; exit 1 ;;
    *) echo "No picture of $name. Is the screen locked?" >&2; exit 1 ;;
  esac
  mkdir -p "$out"
  swift Tools/store-frame.swift "$work/$name.png" "$out/$name.png" "$appearance" live
  echo "$out/$name.png"
}

echo "Taking screenshots…"
shot 1-board light 1282 760
shot 2-issue dark 1282 760 "open 9"
shot 3-list light 1282 760 "mode list" "scrolllist 0"
shot 4-palette dark 1282 760 "focus 9" "overlay palette"
shot 5-selection light 1282 760 "mode list" "scrolllist 0" "pick 7 8 15"
shot 6-peek dark 1282 760 "mode list" "scrolllist 0" "peek 16"
shot 7-inbox light 1282 760 "select inbox" "entry 25"
