#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="Tihsifhub_mobile_ready.lua"

if [ ! -f "$FILE" ]; then
  echo "❌ $FILE missing"
  exit 1
fi

LINES=$(wc -l < "$FILE")
echo "Lines: $LINES"

# hard requirement
if [ "$LINES" -ne 2086 ]; then
  echo "❌ Build rejected: expected 2086 lines, got $LINES"
  exit 1
fi

# marker requirement
if ! grep -q "startMegaInstantCatch" "$FILE"; then
  echo "❌ Build rejected: marker startMegaInstantCatch not found"
  exit 1
fi

echo "✅ Build accepted (2086 + marker found)"
