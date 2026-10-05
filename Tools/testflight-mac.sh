#!/bin/bash
# Archives the Mac app for the App Store and uploads it to App Store Connect (TestFlight and App Review).
#   Tools/testflight-mac.sh
# The App Store configuration runs the Mac app in the App Sandbox, signs it with your team, shares the login
# through iCloud Keychain and leaves out the GitHub CLI sign-in, which can't work in the sandbox.
# Needs the same as Tools/testflight.sh: your team in Config/Local.xcconfig, the app in App Store Connect with
# the bundle identifier com.lukaskbl.GitIssues, and your Apple ID under Xcode › Settings › Accounts.
# Each upload gets a new build number from the current date and time (2026.1004.1530).
set -euo pipefail
cd "$(dirname "$0")/.."

settings=$(xcodebuild -project GitIssues.xcodeproj -scheme GitIssues -configuration AppStore \
  -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null)
setting() { awk -F' = ' -v key="$1" '$1 ~ "^ +" key "$" { print $2; exit }' <<< "$settings"; }
team=$(setting DEVELOPMENT_TEAM)
if [ -z "$team" ]; then
  echo "No team set. Copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill in your team ID." >&2
  exit 1
fi
if [ -z "$(setting GITHUB_CLIENT_ID)" ]; then
  echo "Note: GITHUB_CLIENT_ID is empty, so this build offers only sign-in with a token (and iCloud Keychain)."
fi

now=$(date +%Y:%m:%d:%H:%M)
IFS=: read -r year month day hour minute <<< "$now"
build=$year.$((10#$month * 100 + 10#$day)).$((10#$hour * 100 + 10#$minute))
archive=build/GitIssues-macOS-$build.xcarchive
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
xcodebuild archive -project GitIssues.xcodeproj -scheme GitIssues -configuration AppStore \
  -destination 'generic/platform=macOS' -archivePath "$archive" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build" -quiet

# The App Store rejects a Mac app outside the sandbox, so check before uploading.
app=$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
if ! codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - | grep -q '"com.apple.security.app-sandbox" => true'; then
  echo "The archived app is not sandboxed; not uploading it." >&2
  exit 1
fi

echo "Uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" -allowProvisioningUpdates -quiet
echo "Uploaded build $build. It shows in TestFlight once App Store Connect has processed it."
