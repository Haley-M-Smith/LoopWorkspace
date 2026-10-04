#!/bin/bash
set -euo pipefail

# Restore Haley's saved pink unicorn artwork as the MAIN Loop app icon.
# This runs after lnl_icon so the custom icon wins every time.

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
SOURCE_B64="$ROOT/CustomAssets/pink-unicorn-app-icon.jpg.b64"
ICON_DIR="$ROOT/OverrideAssetsLoop.xcassets/AppIcon.appiconset"
CONTENTS="$ICON_DIR/Contents.json"
SOURCE_JPG="$RUNNER_TEMP/haley-pink-unicorn.jpg"
MASTER_PNG="$RUNNER_TEMP/haley-pink-unicorn-1024.png"

if [ ! -f "$SOURCE_B64" ]; then
  echo "::error::Saved pink unicorn artwork not found at $SOURCE_B64"
  exit 1
fi

if [ ! -f "$CONTENTS" ]; then
  echo "::error::Main Loop AppIcon catalog not found at $CONTENTS"
  exit 1
fi

# Decode the exact unicorn artwork that was saved with this customization.
base64 --decode "$SOURCE_B64" > "$SOURCE_JPG" 2>/dev/null || base64 -D "$SOURCE_B64" > "$SOURCE_JPG"

# Convert once to a square 1024 PNG, then create every size declared by Contents.json.
sips -s format png -z 1024 1024 "$SOURCE_JPG" --out "$MASTER_PNG" >/dev/null

python3 - "$CONTENTS" "$ICON_DIR" "$MASTER_PNG" <<'PY'
import json
import pathlib
import subprocess
import sys

contents = pathlib.Path(sys.argv[1])
icon_dir = pathlib.Path(sys.argv[2])
master = pathlib.Path(sys.argv[3])
data = json.loads(contents.read_text())

written = []
for image in data.get("images", []):
    filename = image.get("filename")
    if not filename:
        continue

    size = float(image["size"].split("x", 1)[0])
    scale = int(image.get("scale", "1x").rstrip("x"))
    pixels = round(size * scale)
    destination = icon_dir / filename
    temporary = destination.with_suffix(".generated.png")

    subprocess.run(
        ["sips", "-z", str(pixels), str(pixels), str(master), "--out", str(temporary)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    temporary.replace(destination)
    written.append((destination, pixels))

if not written:
    raise SystemExit("AppIcon Contents.json did not contain any filenames to replace")

errors = []
for path, expected in written:
    if not path.exists():
        errors.append(f"{path.name}: missing")
        continue
    info = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        text=True,
    )
    if f"pixelWidth: {expected}" not in info or f"pixelHeight: {expected}" not in info:
        errors.append(f"{path.name}: expected {expected}x{expected}")

if errors:
    raise SystemExit("Invalid unicorn app icons: " + "; ".join(errors))

print(f"SUCCESS: Restored saved pink unicorn artwork to {len(written)} Loop app-icon files.")
PY
