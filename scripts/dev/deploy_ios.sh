#!/usr/bin/env bash
# One-shot: refresh the game pack -> build the COMMITTED Xcode project -> install -> launch.
#
# IMPORTANT: TinkerLab.xcodeproj lives COMMITTED at the repo root with Firebase
# wired in (SPM FirebaseAnalytics + GoogleService-Info.plist + the native bridge
# files in TinkerLab/). We do NOT regenerate the Xcode project from Godot here —
# `--export-debug` would wipe the Firebase wiring. We only refresh the game code
# in TinkerLab.pck via `--export-pack`, exactly like gravity-flip.
#
# Usage: scripts/dev/deploy_ios.sh
set -euo pipefail

DEVICE_ID="B7CC8868-E918-5043-A37E-32AC17F755E7"   # iPhone 13 Pro
BUNDLE_ID="com.jfun.tinkerlab"
TEAM_ID="Y3T546NP6T"
SCHEME="TinkerLab"
CONFIG="Debug"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

DERIVED="build/derived"
APP_PATH="$DERIVED/Build/Products/${CONFIG}-iphoneos/${SCHEME}.app"

echo ">> refreshing game pack (TinkerLab.pck) — Firebase Xcode project left intact"
godot --headless --path . --export-pack "iOS" "./TinkerLab.pck" | tail -3

echo ">> building committed Xcode project (Firebase wired)"
xcodebuild \
  -project "TinkerLab.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates build \
  -quiet

echo ">> installing on device"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" | tail -5

echo ">> launching"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" | tail -1

echo ">> done"
