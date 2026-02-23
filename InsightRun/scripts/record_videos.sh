#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/fastlane/videos"
SCHEME="insightrun"
DEVICE="iPhone 17 Pro Max"
BUNDLE_ID="com.altcode.insightrun"
TARGET_DURATION=28
MAX_SPEED=3.0

mkdir -p "$OUTPUT_DIR"

process_video() {
    local raw_file="$1"
    local output_file="$2"

    if ! ffprobe -v error "$raw_file" >/dev/null 2>&1; then
        echo "  ERROR: Raw video is corrupted or unreadable: $raw_file"
        return 1
    fi

    local raw_duration
    raw_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$raw_file")
    raw_duration=${raw_duration%.*}

    echo "  Raw duration: ${raw_duration}s"

    local speed_factor
    speed_factor=$(echo "scale=2; $raw_duration / $TARGET_DURATION" | bc)

    if (( $(echo "$speed_factor > $MAX_SPEED" | bc -l) )); then
        speed_factor=$MAX_SPEED
        echo "  Speed capped at ${MAX_SPEED}x"
    fi
    if (( $(echo "$speed_factor < 1.0" | bc -l) )); then
        speed_factor="1.0"
    fi

    local pts_factor
    pts_factor=$(echo "scale=4; 1 / $speed_factor" | bc)

    echo "  Speed factor: ${speed_factor}x (PTS=${pts_factor})"

    local fade_out_start
    fade_out_start=$(echo "scale=2; ($raw_duration * $pts_factor) - 0.5" | bc)
    if (( $(echo "$fade_out_start < 1" | bc -l) )); then
        fade_out_start="1"
    fi

    echo "  Processing with ffmpeg..."
    ffmpeg -y -ss 5 -i "$raw_file" \
        -vf "setpts=${pts_factor}*PTS,fade=t=in:st=0:d=0.5,fade=t=out:st=${fade_out_start}:d=0.5" \
        -r 30 \
        -t 30 \
        -c:v libx264 -preset slow -crf 18 \
        -pix_fmt yuv420p \
        -movflags +faststart \
        -an \
        "$output_file" 2>/dev/null

    echo "  Processed video saved: $output_file"
}

validate_video() {
    local file="$1"
    local all_pass=true

    echo "  Validating: $file"

    local resolution
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file")
    if [ "$resolution" = "1320x2868" ]; then
        echo "    Resolution: $resolution  PASS"
    else
        echo "    Resolution: $resolution  WARNING (expected 1320x2868)"
        all_pass=false
    fi

    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file")
    local duration_int=${duration%.*}
    if [ "$duration_int" -ge 15 ] && [ "$duration_int" -le 30 ]; then
        echo "    Duration: ${duration_int}s  PASS"
    else
        echo "    Duration: ${duration_int}s  WARNING (expected 15-30s)"
        all_pass=false
    fi

    local codec
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$file")
    if [ "$codec" = "h264" ]; then
        echo "    Codec: $codec  PASS"
    else
        echo "    Codec: $codec  WARNING (expected h264)"
        all_pass=false
    fi

    local size
    size=$(du -h "$file" | cut -f1)
    echo "    File size: $size"

    if $all_pass; then
        echo "    Result: ALL PASS"
    else
        echo "    Result: HAS WARNINGS"
    fi
}

record_video() {
    local locale="$1"
    local raw_file="$OUTPUT_DIR/${locale}_raw.mov"
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

    # Map locale to test method name
    local test_method
    case "$locale" in
        en-US) test_method="testAppPreviewEN" ;;
        fr-FR) test_method="testAppPreviewFR" ;;
        *) echo "Error: Unsupported locale $locale"; exit 1 ;;
    esac

    # Build and install app
    echo "  Building app..."
    xcodebuild build-for-testing \
        -project "$PROJECT_DIR/insightrun.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "id=$DEVICE_ID" \
        -quiet 2>/dev/null || true

    # Start recording
    echo "  Recording video..."
    xcrun simctl io "$DEVICE_ID" recordVideo --codec h264 -f "$raw_file" &
    RECORD_PID=$!
    sleep 1

    # Run the video navigation test
    xcodebuild test-without-building \
        -project "$PROJECT_DIR/insightrun.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "id=$DEVICE_ID" \
        -only-testing:"insightrunUITests/VideoRecordingTests/$test_method" \
        -quiet 2>/dev/null || true

    # Stop recording
    sleep 1
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true

    echo "  Raw video saved: $raw_file"

    # Post-process video
    process_video "$raw_file" "$output_file"

    # Validate result
    validate_video "$output_file"

    # Clear status bar override
    xcrun simctl status_bar "$DEVICE_ID" clear
}

echo "InsightRun App Preview Video Recording"
echo "======================================="

# Check ffmpeg availability
if ! command -v ffmpeg &>/dev/null || ! command -v ffprobe &>/dev/null; then
    echo "Error: ffmpeg and ffprobe are required. Install with: brew install ffmpeg"
    exit 1
fi

for locale in "en-US" "fr-FR"; do
    record_video "$locale"
done

echo ""
echo "All videos recorded and processed!"
echo "  Output: $OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/"
