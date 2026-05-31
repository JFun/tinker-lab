#!/usr/bin/env bash
# One-shot: export Godot iOS project → build → install → launch on paired iPhone.
# Usage: scripts/dev/deploy_ios.sh [--clean]
set -euo pipefail

DEVICE_ID="B7CC8868-E918-5043-A37E-32AC17F755E7"   # iPhone 13 Pro
BUNDLE_ID="com.jfun.tinkerlab"
TEAM_ID="Y3T546NP6T"
SCHEME="TinkerLab"
CONFIG="Debug"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

XCODE_DIR="build/ios"
APP_PATH="$XCODE_DIR/derived/Build/Products/${CONFIG}-iphoneos/${SCHEME}.app"

if [[ "${1:-}" == "--clean" ]]; then
  echo ">> clean: wiping $XCODE_DIR"
  rm -rf "$XCODE_DIR"
fi

echo ">> exporting Godot iOS Xcode project"
mkdir -p "$XCODE_DIR"
godot --headless --path . --export-debug "iOS" "$XCODE_DIR/${SCHEME}.xcodeproj" | tail -3

echo ">> building (xcodebuild)"
xcodebuild \
  -project "$XCODE_DIR/${SCHEME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$XCODE_DIR/derived" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates build \
  -quiet

echo ">> installing on device"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" | tail -5

echo ">> launching"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" | tail -1

echo ">> done"
