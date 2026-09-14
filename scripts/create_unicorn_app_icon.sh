#!/bin/bash
set -euo pipefail

# Generates the MAIN LOOP app icon from Haley's custom pink unicorn artwork.
# The source artwork is stored in the repo as base64 text so it can be committed
# through GitHub's text-file API. It is decoded during the build, then resized
# square-to-square for every AppIcon slot. No cropping is performed.

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ICON_DIR="$ROOT/OverrideAssetsLoop.xcassets/AppIcon.appiconset"
SOURCE_B64="$ROOT/scripts/pink_unicorn_master.jpg.b64"
SOURCE_JPG="$RUNNER_TEMP/pink-unicorn-source.jpg"
MASTER_PNG="$RUNNER_TEMP/pink-unicorn-master-1024.png"

if [ ! -d "$ICON_DIR" ]; then
  echo "::error::Main Loop AppIcon set not found at $ICON_DIR"
  exit 1
fi

if [ ! -f "$SOURCE_B64" ]; then
  echo "::error::Custom pink unicorn source not found at $SOURCE_B64"
  exit 1
fi

# Decode the custom artwork. Python is used instead of the platform-specific
# macOS base64 flags so this remains reliable on GitHub Actions runners.
python3 - "$SOURCE_B64" "$SOURCE_JPG" <<'PY'
import base64
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
raw = base64.b64decode(src.read_text().strip(), validate=True)
dst.write_bytes(raw)
print(f"Decoded custom pink unicorn source ({len(raw)} bytes).")
PY

# Validate the source and create one square 1024x1024 RGB master.
# Because the source itself is square, -z scales the entire image and does not crop.
sips -g pixelWidth -g pixelHeight "$SOURCE_JPG"
sips -z 1024 1024 "$SOURCE_JPG" --out "$RUNNER_TEMP/pink-unicorn-master-1024.jpg" >/dev/null
sips -s format png "$RUNNER_TEMP/pink-unicorn-master-1024.jpg" --out "$MASTER_PNG" >/dev/null

resize_icon() {
  local filename="$1"
  local pixels="$2"
  sips -z "$pixels" "$pixels" "$MASTER_PNG" --out "$ICON_DIR/$filename" >/dev/null
}

# Exact pixel sizes referenced by OverrideAssetsLoop.xcassets/AppIcon.appiconset/Contents.json
resize_icon "icon_20pt@2x.png" 40
resize_icon "icon_20pt@3x.png" 60
resize_icon "icon_29pt@2x.png" 58
resize_icon "icon_29pt@3x.png" 87
resize_icon "icon_38pt@2x.png" 76
resize_icon "icon_38pt@3x.png" 114
resize_icon "icon_40pt@2x.png" 80
resize_icon "icon_40pt@3x.png" 120
resize_icon "icon_60pt@2x.png" 120
resize_icon "icon_60pt@3x.png" 180
resize_icon "icon_64pt@2x.png" 128
resize_icon "icon_64pt@3x.png" 192
resize_icon "icon_68pt@2x.png" 136
resize_icon "icon_76pt@2x.png" 152
resize_icon "icon_83.5pt@2x.png" 167
cp "$MASTER_PNG" "$ICON_DIR/icon_1024pt.png"

# Verify every filename declared by the main Loop AppIcon set exists and that
# the 1024 master is exactly square. This makes the build fail here instead of
# wasting time archiving an app with a broken/missing icon.
python3 - "$ICON_DIR" <<'PY'
import json
import pathlib
import subprocess
import sys

icon_dir = pathlib.Path(sys.argv[1])
data = json.loads((icon_dir / "Contents.json").read_text())
missing = []
for image in data.get("images", []):
    filename = image.get("filename")
    if filename and not (icon_dir / filename).exists():
        missing.append(filename)
if missing:
    raise SystemExit("Missing generated Loop app icons: " + ", ".join(missing))

master = icon_dir / "icon_1024pt.png"
info = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(master)], text=True)
if "pixelWidth: 1024" not in info or "pixelHeight: 1024" not in info:
    raise SystemExit("Generated 1024 Loop app icon is not 1024x1024")

print("SUCCESS: Main Loop icon generated from the custom pink unicorn artwork (full square image, no crop).")
PY
