#!/bin/bash
#
# Claude Code Skill: export-html
# Description: Export conversation segment to HTML with modern styling
# Usage: /export-html "topic-name"
#

set -e

# Get the topic from arguments
TOPIC="${1:-conversation-summary}"

# Configuration
TEMPLATE_FILE="$HOME/.claude/templates/export-to-html.txt"
OUTPUT_DIR="$HOME/Projects/personal/ingineering-topics"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create sanitized filename (replace spaces with hyphens, lowercase)
FILENAME=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}.html"

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found at $TEMPLATE_FILE"
    exit 1
fi

# Check if output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Error: Output directory not found at $OUTPUT_DIR"
    exit 1
fi

# Read template and substitute variables
PROMPT=$(cat "$TEMPLATE_FILE" | sed "s|{{TOPIC}}|$TOPIC|g" | sed "s|{{OUTPUT_PATH}}|$OUTPUT_FILE|g")

# Output the prompt for Claude to execute
echo "📄 Exporting conversation about: $TOPIC"
echo "📁 Output file: $OUTPUT_FILE"
echo ""
echo "$PROMPT"
