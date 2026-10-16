#!/bin/bash
# Renders the Icon Composer documents into the PNGs the app offers in its icon pickers and the README shows.
#   python3 Tools/make-board-icon.py && Tools/render-icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
resources=Packages/GitIssuesKit/Sources/GitIssuesKit/Resources
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# render <document> <rendition> <output>: the icon at Dock proportions, an 824 px body on a 1024 px canvas.
render() {
  "$ictool" "$1" --export-image --output-file "$work/full.png" --platform macOS --rendition "$2" \
    --width 1024 --height 1024 --scale 1 >/dev/null
  swift Tools/pad-icon.swift "$work/full.png" "$3"
}

# Each board, light and dark, under the name AppIconChoice uses: AppIcon.icon is the pinboard, AppIcon-Cork.icon the cork.
rm -f "$resources"/icon-*.png
for document in GitIssues/AppIcon*.icon; do
  name=$(basename "$document" .icon)
  name=${name#AppIcon}
  name=${name#-}
  name=$(echo "${name:-pinboard}" | tr '[:upper:]' '[:lower:]')
  render "$document" Default "$work/$name-light.png"
  render "$document" Dark "$work/$name-dark.png"
  for look in light dark; do
    sips -z 512 512 "$work/$name-$look.png" --out "$resources/icon-$name-$look.png" >/dev/null
  done
done

sips -z 256 256 "$work/pinboard-light.png" --out Design/icon.png >/dev/null
sips -z 256 256 "$work/pinboard-dark.png" --out Design/icon-dark.png >/dev/null
echo "Rendered the board icons into $resources and Design/."
