---
name: export-html
description: Export conversation segment to HTML with modern, minimalist styling. Use when the user wants to save discussion summaries, comparisons, or technical content as a formatted HTML document.
argument-hint: "[topic-name] [output-folder]"
allowed-tools: [Read, Write, Bash]
---

# Export Conversation to HTML

This skill exports conversation segments into professionally styled HTML documents with modern, minimalist design.

## When to Use

- User explicitly asks to "save a summary" or "create HTML"
- User wants to document a technical discussion
- User wants to create a comparison document
- User wants to save code examples and explanations

## How It Works

1. **Resolve the output folder FIRST — never assume the personal archive.**
   - If the user names a folder, use it.
   - Otherwise default to the **current work/project folder** (the repo/directory this conversation is working in, e.g. `$PWD`).
   - Use the personal archive `~/Projects/personal/engineering-topics/` **only** when the user says this is a **personal investigation**.
   - If it's unclear whether the export is work or personal, **ask the user which folder to use** before writing.
2. Read the detailed prompt template from `~/.claude/templates/export-to-html.txt`
3. Substitute the topic name and the resolved output path
4. Generate comprehensive HTML based on conversation content
5. Save to `<resolved-folder>/{topic-name}.html`

## Arguments

- **topic-name**: The subject of the HTML document (e.g., "npm vs pnpm", "TypeScript setup")
  - Spaces will be converted to hyphens in the filename
  - Lowercase and sanitized for safe filenames
- **output-folder** (optional): Destination directory. If omitted, default to the current work/project folder; confirm with the user when work-vs-personal is ambiguous. The personal archive is opt-in for personal investigations only.

## Output Specifications

The generated HTML will include:

### Design Elements
- Modern, clean responsive layout
- Professional color scheme with good contrast
- Self-contained (no external dependencies)
- Mobile and desktop friendly

### Content Structure
1. Header with gradient background and clear title
2. Overview section
3. Key differences and comparisons
4. Detailed analysis with subsections
5. Pros and cons in card format
6. Practical examples and code snippets
7. Recommendations section
8. Bottom line summary
9. Footer with timestamp

### Styling Features
- Comparison cards with hover effects
- Tables with highlighted important rows
- Color-coded pros/cons lists (✓ and ✗ icons)
- Code snippets with syntax highlighting
- Highlight boxes for important information
- Recommendation boxes with green background
- Architecture diagrams in monospace font

## Implementation

```bash
# Read the template
TEMPLATE_FILE="$HOME/.claude/templates/export-to-html.txt"

# Resolve the output directory — DO NOT hardcode the personal archive.
# Priority: folder the user named > current work/project folder ($PWD).
# Use "$HOME/Projects/personal/engineering-topics" ONLY for personal investigations.
OUTPUT_DIR="${USER_PROVIDED_FOLDER:-$PWD}"

# Sanitize topic name for filename
FILENAME=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}.html"

# Generate HTML using template specifications
# Template includes all styling and structure requirements
```

## Examples

### Example 1: Work export (default — current project folder)
```
/export-html "QC failure status"
```
Creates: `<current-work-folder>/qc-failure-status.html`

### Example 2: Explicit folder
```
/export-html "TypeScript Configuration Guide" ./docs/reports
```
Creates: `./docs/reports/typescript-configuration-guide.html`

### Example 3: Personal investigation (opt-in archive)
```
/export-html "npm vs pnpm" (personal)
```
Creates: `~/Projects/personal/engineering-topics/npm-vs-pnpm.html`

## Template Variables

When reading the template, substitute:
- `{{TOPIC}}` → The provided topic name
- `{{OUTPUT_PATH}}` → Full path to output file

## Output Location

The output folder is **resolved per call**, not fixed:
- **Work exports (default):** the current work/project folder, or a folder the user names → `<folder>/{sanitized-topic-name}.html`.
- **Personal investigations only (opt-in):** `~/Projects/personal/engineering-topics/{sanitized-topic-name}.html`.

When it is unclear whether the export is work or personal, ask the user for the folder before writing. Do not silently write to the personal archive for work.

## Success Criteria

After generation:
1. Confirm file was created
2. Show the output path to the user
3. HTML should be viewable in any modern browser
4. All styles should be embedded (no external CSS/JS)
5. Content should comprehensively cover the conversation topic

## Notes

- The template file must exist at `~/.claude/templates/export-to-html.txt`
- Resolve the output folder before writing (see "How It Works"); never default to the personal archive for work exports
- If the resolved output directory does not exist, create it (`mkdir -p`) or confirm the path with the user
- Generated HTML is fully self-contained and works offline
- Files use consistent, professional styling across all exports
