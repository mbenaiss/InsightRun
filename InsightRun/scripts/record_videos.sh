#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/fastlane/videos"
SCHEME="insightrun"
DEVICE="iPhone 16 Pro Max"
BUNDLE_ID="com.altcode.insightrun"

mkdir -p "$OUTPUT_DIR"

record_video() {
    local locale="$1"
    local output_file="$OUTPUT_DIR/${locale}.mov"

    echo "Recording App Preview for locale: $locale"

    # Boot simulator
    DEVICE_ID=$(xcrun simctl list devices available | grep "$DEVICE" | head -1 | sed 's/.*(\([A-F0-9-]*\)).*/\1/')

    if [ -z "$DEVICE_ID" ]; then
        echo "Error: Device '$DEVICE' not found. Available devices:"
        xcrun simctl list devices available
        exit 1
    fi

    echo "  Using device: $DEVICE_ID"
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

    # Wait for boot
    sleep 3

    # Override status bar for clean screenshots
    xcrun simctl status_bar "$DEVICE_ID" override \
        --time "9:41" \
        --batteryState charged \
        --batteryLevel 100 \
        --wifiBars 3 \
        --cellularBars 4

    # Set locale
    xcrun simctl spawn "$DEVICE_ID" defaults write com.apple.Preferences AppleLanguages -array "${locale%%-*}"
    xcrun simctl spawn "$DEVICE_ID" defaults write com.apple.Preferences AppleLocale -string "$locale"

    # Build and install app
    echo "  Building app..."
    xcodebuild build-for-testing \
        -project "$PROJECT_DIR/insightrun.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "id=$DEVICE_ID" \
        -quiet 2>/dev/null || true

    # Start recording
    echo "  Recording video..."
    xcrun simctl io "$DEVICE_ID" recordVideo --codec h264 "$output_file" &
    RECORD_PID=$!
    sleep 1

    # Run the video navigation test
    xcodebuild test-without-building \
        -project "$PROJECT_DIR/insightrun.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "id=$DEVICE_ID" \
        -only-testing:"insightrunUITests/VideoRecordingTests/testAppPreviewNavigation" \
        -quiet 2>/dev/null || true

    # Stop recording
    sleep 1
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true

    echo "  Video saved: $output_file"

    # Clear status bar override
    xcrun simctl status_bar "$DEVICE_ID" clear
}

echo "InsightRun App Preview Video Recording"
echo "======================================="

for locale in "en-US" "fr-FR"; do
    record_video "$locale"
done

echo ""
echo "All videos recorded!"
echo "  Output: $OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/"
