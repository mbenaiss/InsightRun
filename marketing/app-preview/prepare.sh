#!/bin/sh
set -eu
cd "$(dirname "$0")"
extract() {
  rm -rf "$2" && mkdir "$2"
  ffmpeg -v error -y -i "$HOME/Library/Application Support/Glint/captures/$1.mp4" \
    -vf "fps=30,scale=880:-2:flags=lanczos" -q:v 3 "$2/%04d.jpg"
  echo "$2: $(ls "$2" | wc -l) frames"
}
extract cap_01m3rq3t6nbesyzfez7a9mv5z3 footage
extract cap_01m3s3np091a0qttn10a98qq5k footage-light
extract cap_01m3vdrqaz5aznmsk5gyshxdj2 footage-switch
extract cap_01m3vpg0max67nhf3e0kxxz6qe footage-switch-ld
extract cap_01m3rq8a0zfhe6fvzre44ecxz8 footage-fr
extract cap_01m3s3r4wcq0qmz1k3d86tnyqr footage-fr-light
extract cap_01m3vnxfkqtbspd9c2dgjnh277 footage-fr-switch
