#!/bin/bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ICON_DIR="$ROOT/OverrideAssetsLoop.xcassets/AppIcon.appiconset"
CONTENTS="$ICON_DIR/Contents.json"
MASTER="${RUNNER_TEMP:-/tmp}/loop-unicorn-emoji-1024.png"
SWIFT_FILE="${RUNNER_TEMP:-/tmp}/make-loop-unicorn-emoji.swift"

if [ ! -d "$ICON_DIR" ]; then
  echo "::error::Loop AppIcon directory not found: $ICON_DIR"
  exit 1
fi
if [ ! -f "$CONTENTS" ]; then
  echo "::error::Loop AppIcon Contents.json not found: $CONTENTS"
  exit 1
fi

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit
import Foundation

let size = 1024
let output = CommandLine.arguments[1]

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 24
) else { fatalError("Could not create bitmap") }

guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// Baby-pink background, fully opaque for App Store/TestFlight compatibility.
NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.91, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

// Standard Apple unicorn emoji with generous margins so iOS cannot crop it.
let emoji = "🦄" as NSString
let font = NSFont(name: "Apple Color Emoji", size: 560) ?? NSFont.systemFont(ofSize: 560)
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let bounds = emoji.size(withAttributes: attrs)
let origin = NSPoint(
    x: (CGFloat(size) - bounds.width) / 2.0,
    y: (CGFloat(size) - bounds.height) / 2.0 - 8.0
)
emoji.draw(at: origin, withAttributes: attrs)

ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: output))
SWIFT

swift "$SWIFT_FILE" "$MASTER"

# Read the exact filenames and required pixel sizes from the asset catalog that
# Xcode will compile. This avoids relying on guessed icon filenames.
python3 - "$CONTENTS" > "${RUNNER_TEMP:-/tmp}/loop-icon-map.txt" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    data = json.load(f)
for image in data.get("images", []):
    filename = image.get("filename")
    size = image.get("size")
    scale = image.get("scale", "1x")
    if not filename or not size:
        continue
    points = float(size.split("x")[0])
    multiplier = float(scale.rstrip("x"))
    pixels = round(points * multiplier)
    print(f"{filename}|{pixels}")
PY

replaced=0
while IFS='|' read -r filename pixels; do
  [ -z "$filename" ] && continue
  target="$ICON_DIR/$filename"
  temp="${RUNNER_TEMP:-/tmp}/loop-unicorn-${replaced}.png"
  echo "UNICORN ICON: $filename -> ${pixels}x${pixels}"
  sips -s format png -z "$pixels" "$pixels" "$MASTER" --out "$temp" >/dev/null
  mv "$temp" "$target"
  replaced=$((replaced + 1))
done < "${RUNNER_TEMP:-/tmp}/loop-icon-map.txt"

if [ "$replaced" -lt 8 ]; then
  echo "::error::Only replaced $replaced app icon files; refusing to build."
  exit 1
fi

# Verify every filename declared by Contents.json exists after replacement.
python3 - "$CONTENTS" "$ICON_DIR" <<'PY'
import json, pathlib, sys
contents = pathlib.Path(sys.argv[1])
icon_dir = pathlib.Path(sys.argv[2])
data = json.loads(contents.read_text())
missing = [i["filename"] for i in data.get("images", []) if i.get("filename") and not (icon_dir / i["filename"]).exists()]
if missing:
    raise SystemExit("Missing generated icons: " + ", ".join(missing))
PY

echo "SUCCESS: generated and installed the full standard unicorn emoji into $replaced MAIN LOOP app-icon files."
