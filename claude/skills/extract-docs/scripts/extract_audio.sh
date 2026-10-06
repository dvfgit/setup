#!/usr/bin/env bash
# Extract audio from a video URL (Loom, YouTube, etc.) as mp3
# Usage: extract_audio.sh <video_url> <output_path>
# Requires: yt-dlp, ffmpeg

set -euo pipefail

VIDEO_URL="${1:?Usage: extract_audio.sh <video_url> <output_path>}"
OUTPUT_PATH="${2:?Usage: extract_audio.sh <video_url> <output_path>}"

if ! command -v yt-dlp &>/dev/null; then
  echo "ERROR: yt-dlp is not installed. Install with: brew install yt-dlp" >&2
  exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
  echo "ERROR: ffmpeg is not installed. Install with: brew install ffmpeg" >&2
  exit 1
fi

yt-dlp \
  --extract-audio \
  --audio-format mp3 \
  --audio-quality 4 \
  --no-playlist \
  --output "$OUTPUT_PATH" \
  "$VIDEO_URL"

echo "Audio extracted to: $OUTPUT_PATH"
