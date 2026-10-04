#!/bin/bash
# Archives the iPhone and iPad app and uploads it to App Store Connect for TestFlight.
#   Tools/testflight.sh
# Needs: your team in Config/Local.xcconfig, the app created in App Store Connect with the bundle identifier
# com.lukaskbl.GitIssues, and your Apple ID signed in under Xcode › Settings › Accounts.
# Each upload gets a new build number from the current date and time (2026.1004.1530), as App Store Connect
# requires a higher one each time.
set -euo pipefail
cd "$(dirname "$0")/.."

team=$(xcodebuild -project GitIssues.xcodeproj -scheme GitIssues -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null \
  | awk -F' = ' '/ DEVELOPMENT_TEAM = / { print $2; exit }')
if [ -z "$team" ]; then
  echo "No team set. Copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill in your team ID." >&2
  exit 1
fi

now=$(date +%Y:%m:%d:%H:%M)
IFS=: read -r year month day hour minute <<< "$now"
build=$year.$((10#$month * 100 + 10#$day)).$((10#$hour * 100 + 10#$minute))
archive=build/GitIssues-iOS-$build.xcarchive
workdir=$(mktemp -d)
options=$workdir/ExportOptions.plist
trap 'rm -rf "$workdir"' EXIT
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$team</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "Archiving build $build…"
xcodebuild archive -project GitIssues.xcodeproj -scheme GitIssues -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build" -quiet

echo "Uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" -allowProvisioningUpdates -quiet
echo "Uploaded build $build. It shows in TestFlight once App Store Connect has processed it."
