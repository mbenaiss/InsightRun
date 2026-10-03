#!/bin/sh
set -eu
VARIANT="${1:-dark}"
SUFFIX=""
[ "$VARIANT" = dark ] || SUFFIX="-$VARIANT"
case "$VARIANT" in
  dark) NAME=insightrun-app-preview-en ;;
  mix-fr) NAME=insightrun-app-preview-fr-mix ;;
  mix-ld) NAME=insightrun-app-preview-en-mix-light-dark ;;
  *) NAME="insightrun-app-preview-en-$VARIANT" ;;
esac
cd "$(dirname "$0")/out"
ffmpeg -v error -y -i "picture$SUFFIX.mp4" -i "music$SUFFIX.wav" \
  -map 0:v -map 1:a \
  -c:v libx264 -profile:v high -level:v 4.0 -pix_fmt yuv420p -r 30 \
  -b:v 10M -maxrate 12M -bufsize 20M -preset slow \
  -vf "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv" \
  -bsf:v "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0" \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
  -af "loudnorm=I=-14:TP=-1.5:LRA=7" -c:a aac_at -aac_at_mode cbr -b:a 256k -ar 48000 -ac 2 \
  -video_track_timescale 600 -brand mp42 -shortest -movflags +faststart+write_colr "$NAME.mp4"
ffprobe -v error -show_entries stream=codec_name,profile,level,width,height,r_frame_rate,pix_fmt,color_space,sample_rate,channels:format=duration,size -of default=nw=1 "$NAME.mp4"
