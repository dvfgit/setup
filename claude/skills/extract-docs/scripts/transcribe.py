#!/usr/bin/env python3
"""Transcribe an audio file using local OpenAI Whisper.

Usage: transcribe.py <audio_path> [--model base] [--output transcript.txt]
Requires: pip install openai-whisper
"""

import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description="Transcribe audio with Whisper")
    parser.add_argument("audio_path", help="Path to audio file (mp3, wav, etc.)")
    parser.add_argument("--model", default="base", help="Whisper model size (tiny/base/small/medium/large)")
    parser.add_argument("--output", default=None, help="Output file path (default: stdout)")
    args = parser.parse_args()

    try:
        import whisper
    except ImportError:
        print("ERROR: openai-whisper is not installed. Install with: pip install openai-whisper", file=sys.stderr)
        sys.exit(1)

    model = whisper.load_model(args.model)
    result = model.transcribe(args.audio_path)
    text = result["text"].strip()

    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
        print(f"Transcript saved to: {args.output}", file=sys.stderr)
    else:
        print(text)

if __name__ == "__main__":
    main()
