#!/bin/bash
# Extract and serve the game
set -e

FILE="${1:-dist.tar.br}"

if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE"
    exit 1
fi

# Create temp directory for extraction
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Decompress brotli then extract tar
brotli -d -c "$FILE" | tar xf - -C "$TMPDIR"

echo "Serving at http://localhost:8000"
echo "Press Ctrl+C to stop"

cd "$TMPDIR"
python3 -m http.server 8000
