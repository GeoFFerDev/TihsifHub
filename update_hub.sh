#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "[1] Sync repo to remote main..."
git fetch origin
git checkout main
git reset --hard origin/main

echo "[2] Ensure mobile file exists..."
if [ ! -f Tihsifhub_mobile_ready.lua ]; then
  cp -f Tihsifhub.lua Tihsifhub_mobile_ready.lua
fi
zip -q -j Tihsifhub_mobile_ready.zip Tihsifhub_mobile_ready.lua

echo "[3] Validate build markers..."
LINES=$(wc -l < Tihsifhub_mobile_ready.lua)
echo "Lines: $LINES"
grep -n "startMegaInstantCatch" Tihsifhub_mobile_ready.lua || true

echo "[4] Push to Downloads..."
termux-setup-storage >/dev/null 2>&1 || true
mkdir -p ~/storage/downloads
cp -f Tihsifhub_mobile_ready.lua ~/storage/downloads/
cp -f Tihsifhub_mobile_ready.zip ~/storage/downloads/

echo "[5] Done:"
ls -lh ~/storage/downloads/Tihsifhub_mobile_ready.lua ~/storage/downloads/Tihsifhub_mobile_ready.zip
