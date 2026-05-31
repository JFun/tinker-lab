#!/usr/bin/env bash
# Pulls TinkerLab crash logs (.ips) from the paired iPhone via devicectl.
# Uses systemCrashLogs domain — no Xcode UI sync needed, no libimobiledevice.
#
# Usage:
#   scripts/dev/pull_crash_logs.sh           # latest only, prints reason + thread 0
#   scripts/dev/pull_crash_logs.sh --all     # pull every TinkerLab .ips
#   scripts/dev/pull_crash_logs.sh --raw     # also dump full .ips path
set -euo pipefail

DEVICE_ID="B7CC8868-E918-5043-A37E-32AC17F755E7"   # iPhone 13 Pro
APP_NAME="TinkerLab"
OUT_DIR="build/crash-logs"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"

echo ">> pulling systemCrashLogs from device (this dumps all apps, will filter)"
TMP="$(mktemp -d)"
xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --source / \
  --destination "$TMP" \
  --domain-type systemCrashLogs \
  2>&1 | tail -3

# Copy just TinkerLab-related .ips files
cp "$TMP"/${APP_NAME}-*.ips "$OUT_DIR/" 2>/dev/null || true
cp "$TMP"/${APP_NAME}.*-*.ips "$OUT_DIR/" 2>/dev/null || true
rm -rf "$TMP"

LATEST="$(ls -t "$OUT_DIR"/${APP_NAME}-*.ips 2>/dev/null | head -1)"
if [[ -z "$LATEST" ]]; then
  echo "❌ no ${APP_NAME} crash logs found on device"
  exit 1
fi

echo
echo "=== latest crash: $(basename "$LATEST") ==="
python3 - "$LATEST" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    header, body = f.read().split('\n', 1)
hdr = json.loads(header)
ips = json.loads(body)
print(f"app:     {hdr.get('app_name')} {hdr.get('app_version')} build {hdr.get('build_version')}")
print(f"time:    {hdr.get('timestamp')}")
print(f"os:      {hdr.get('os_version')}")
exc = ips.get('exception', {})
term = ips.get('termination', {})
print(f"signal:  {term.get('indicator', '?')}  ({exc.get('type', '?')} {exc.get('subtype', '')})")
msg = exc.get('message', '')
if msg: print(f"message: {msg}")
ft = ips.get('faultingThread', 0)
threads = ips.get('threads', [])
t = threads[ft]
print(f"thread:  {ft} ({t.get('name') or t.get('queue', 'unnamed')})  — {len(t['frames'])} frames")
print()
print("=== top stack frames ===")
for i, fr in enumerate(t['frames'][:25]):
    img = ips['usedImages'][fr['imageIndex']]['name']
    sym = fr.get('symbol', '?')
    off = fr.get('symbolLocation', 0)
    print(f"{i:3d}  {img:18s}  {sym}  +{off}")
if len(t['frames']) > 25:
    print(f"     ... ({len(t['frames']) - 25} more frames; see {sys.argv[1]})")
PY

if [[ "${1:-}" == "--all" ]]; then
  echo
  echo "=== all ${APP_NAME} crashes ==="
  ls -lt "$OUT_DIR"/${APP_NAME}-*.ips
elif [[ "${1:-}" == "--raw" ]]; then
  echo
  echo "raw file: $LATEST"
fi
