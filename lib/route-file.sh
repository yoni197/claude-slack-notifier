#!/bin/bash
# lib/route-file.sh - Route uploaded files to the correct handler based on extension
# Usage: ./lib/route-file.sh <filename>
# Output: echoes the route name to stdout

set -euo pipefail

FILENAME="${1:-}"

if [ -z "$FILENAME" ]; then
  echo "Usage: route-file.sh <filename>" >&2
  exit 1
fi

# Get lowercase extension
EXT="${FILENAME##*.}"
EXT=".${EXT,,}"

# If no extension (dot not found or same as filename)
if [ "$EXT" = ".${FILENAME,,}" ] || [ "$EXT" = "." ]; then
  EXT=""
fi

case "$EXT" in
  .csv|.tsv)
    echo "data-analysis"
    ;;
  .xlsx|.xls)
    echo "spreadsheet"
    ;;
  .pdf)
    echo "pdf-skill"
    ;;
  .docx|.doc)
    echo "document-skill"
    ;;
  .pptx)
    echo "presentation-skill"
    ;;
  .json|.jsonl)
    echo "json-parser"
    ;;
  .sql)
    echo "sql-analysis"
    ;;
  .py|.js|.ts)
    echo "code-review"
    ;;
  .md|.txt)
    echo "text-analysis"
    ;;
  *)
    # Wildcard fallback for unknown/unmatched types
    echo "Received \`${FILENAME}\` — no specific handler for \`${EXT}\` files. Passing to generic handler." >&2
    echo "generic-handler"
    ;;
esac
