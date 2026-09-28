#!/bin/sh
# Records the DemoRecordingTests flow in the Simulator and converts it to a GIF.
#   Tools/scripts/record-demo.sh [simulator name] [output.gif]
set -eu
SIM="${1:-iPhone 17 Pro}"
OUT="${2:-docs/media/demo.gif}"
VIDEO=".build/demo.mov"
mkdir -p .build "$(dirname "$OUT")"

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl ui "$SIM" appearance light
xcodegen generate --quiet
# Build first so recording starts right before the flow runs.
xcodebuild build-for-testing -project CleanCut.xcodeproj -scheme CleanCut \
    -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath .build/dd -quiet

xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$VIDEO" &
RECORDER=$!
sleep 2
TEST_RUNNER_CLEANCUT_DEMO=1 xcodebuild test-without-building -project CleanCut.xcodeproj -scheme CleanCut \
    -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath .build/dd \
    -only-testing:CleanCutUITests/DemoRecordingTests -quiet || true
kill -INT "$RECORDER"
wait "$RECORDER" 2>/dev/null || true

# Trim the app-launch and teardown seconds; tune with START/END if needed.
swift Tools/scripts/mp4-to-gif.swift "$VIDEO" "$OUT" --width "${WIDTH:-360}" --fps "${FPS:-12}" --start "${START:-4}" --end "${END:-33}"
