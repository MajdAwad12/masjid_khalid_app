#!/bin/sh
# With the release candidate open on the specified Simulator, navigate to
# the desired screen before running this command from the repository root.
set -eu
: "${SIMULATOR_ID:?Set SIMULATOR_ID to the booted iOS simulator UDID}"
case "${1:-}" in
  iphone) device=iphone; expected_width=1179; expected_height=2556 ;;
  ipad-13) device=ipad-13; expected_width=2064; expected_height=2752 ;;
  *) echo "Expected iphone or ipad-13" >&2; exit 2 ;;
esac
case "${2:-}" in 01-home|02-courses|03-activities|04-homework) screen=$2 ;; *) echo "Expected a screen filename from PRODUCTION.MD" >&2; exit 2 ;; esac
output="build/apple-captures/$device"
mkdir -p "$output"
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41'
# JPEG is accepted by App Store Connect and carries no alpha channel.
temp=$(mktemp -d)
trap 'rm -f "$temp/capture.png" "$temp/capture.jpg"; rmdir "$temp"' EXIT
xcrun simctl io "$SIMULATOR_ID" screenshot "$temp/capture.png"
sips -s format jpeg -s formatOptions 100 "$temp/capture.png" --out "$temp/capture.jpg" >/dev/null
width=$(sips -g pixelWidth "$temp/capture.jpg" | awk '/pixelWidth:/ {print $2}')
height=$(sips -g pixelHeight "$temp/capture.jpg" | awk '/pixelHeight:/ {print $2}')
if [ "$width" != "$expected_width" ] || [ "$height" != "$expected_height" ]; then
  echo "Select a portrait $device simulator at ${expected_width}x${expected_height}. Captured ${width}x${height}." >&2
  exit 1
fi
cp "$temp/capture.jpg" "$output/$screen.jpg"
echo "$output/$screen.jpg"
