---
name: extract-docs
description: Extract documentation from web pages and multimedia (Loom videos, YouTube, etc.) into structured markdown files matching project conventions. Use when the user says "extract docs from URL", "grab the docs from URL", "transcribe this video", or provides a documentation URL or video link to capture as a local reference file. Handles both web documentation pages and video/audio content via Whisper transcription.
---

# Extract Docs

Extract documentation from URLs and multimedia into clean markdown files that match the current project's conventions.

## Workflow

### 1. Detect project doc conventions

Before writing any output, scan the project for existing documentation patterns:

- Look for `docs/`, `documentation/`, `doc/`, or similar directories
- Check file naming: kebab-case, snake_case, PascalCase
- Check file extension: `.md`, `.mdx`, `.rst`
- Look at existing doc files for frontmatter style (YAML, none), heading structure, and formatting patterns
- If no conventions exist, default to: `docs/` directory, kebab-case `.md` files, no frontmatter

### 2. Classify the source

| Source type | Detection | Action |
|---|---|---|
| **Doc page** | Standard URL (no video host) | Fetch with WebFetch, extract content |
| **Video** | URL contains `loom.com`, `youtube.com`, `youtu.be`, `vimeo.com` | Extract audio → transcribe → structure |
| **Mixed** | Multiple URLs of different types | Process each source, merge into single doc |

### 3a. Web documentation extraction

1. Fetch the page with WebFetch — prompt: "Extract the complete documentation content preserving all headings, steps, code blocks, callouts, tables, and lists. Maintain the hierarchy."
2. Structure the extracted content into markdown:
   - Preserve the original heading hierarchy
   - Convert platform-specific callouts (tips, warnings, notes) to blockquotes with bold labels
   - Keep code blocks, tables, and lists intact
   - Strip navigation, footers, sidebars, and other chrome
   - Add source URL as a comment at the top: `<!-- Source: {url} -->`

### 3b. Multimedia extraction

1. Extract audio using the bundled script:
   ```bash
   scripts/extract_audio.sh "<video_url>" "/tmp/extract-docs-audio.%(ext)s"
   ```
2. Transcribe with Whisper:
   ```bash
   python3 scripts/transcribe.py /tmp/extract-docs-audio.mp3 --model base
   ```
3. Structure the raw transcript into clean documentation sections with proper headings
4. Clean up intermediate files (`/tmp/extract-docs-audio.*`)

### 4. Write the output

- Derive filename from the page title or feature name (e.g., "Offers and Offer Letters" → `offers-and-offer-letters.md`)
- Place in the detected docs directory matching project conventions
- If the user provided both a doc URL and a video for the same feature, merge them into a single file — use the doc page as the primary structure and supplement with transcript content where it adds detail

## Output format

```markdown
<!-- Source: https://example.com/docs/feature -->

# Feature Name

Brief summary of what this feature does.

## Section

Content...

> **Note:** Callout content preserved as blockquotes.

## Steps

1. Step one
2. Step two
```

## Scripts

- `scripts/extract_audio.sh <video_url> <output_path>` — extracts mp3 from video URLs via yt-dlp
- `scripts/transcribe.py <audio_path> [--model base] [--output file.txt]` — transcribes audio via local Whisper

### Dependencies

Required for multimedia extraction only (not needed for web pages):
- `yt-dlp` — `brew install yt-dlp`
- `ffmpeg` — `brew install ffmpeg`
- `openai-whisper` — `pip install openai-whisper`
