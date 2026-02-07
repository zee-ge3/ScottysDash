#!/bin/bash
set -e

echo "Building Infinite Ski..."

# Check for html-minifier-terser
if ! command -v html-minifier-terser &>/dev/null; then
    echo "Installing html-minifier-terser..."
    npm install -g html-minifier-terser
fi

# Minify
html-minifier-terser \
    --collapse-whitespace \
    --remove-comments \
    --remove-optional-tags \
    --remove-redundant-attributes \
    --remove-script-type-attributes \
    --remove-tag-whitespace \
    --minify-css true \
    --minify-js true \
    -o dist/index.html \
    index.html

echo "Minified size: $(wc -c < dist/index.html) bytes"

# Create tar
cd dist
tar cf ../dist.tar index.html
cd ..

echo "Tar size: $(wc -c < dist.tar) bytes"

# Brotli compress
brotli -f -q 11 -o dist.tar.br dist.tar

FINAL_SIZE=$(wc -c < dist.tar.br | tr -d ' ')
echo "Final .tar.br size: $FINAL_SIZE bytes"

if [ "$FINAL_SIZE" -le 15360 ]; then
    echo "SUCCESS: Under 15KB budget (${FINAL_SIZE}/15360 bytes)"
else
    echo "WARNING: Over 15KB budget! (${FINAL_SIZE}/15360 bytes)"
    exit 1
fi
