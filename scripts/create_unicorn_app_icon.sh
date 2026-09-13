#!/bin/bash
set -euo pipefail

# Generates the MAIN LOOP app icon from Apple's unicorn emoji.
# The icon is drawn onto a square pink canvas first, then resized square-to-square.
# This avoids the crop that occurred when the previous image was used directly.

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ICON_DIR="$ROOT/OverrideAssetsLoop.xcassets/AppIcon.appiconset"
MASTER="$RUNNER_TEMP/loop-unicorn-icon-1024.png"
SWIFT_FILE="$RUNNER_TEMP/make-loop-unicorn-icon.swift"

if [ ! -d "$ICON_DIR" ]; then
  echo "::error::Main Loop AppIcon set not found at $ICON_DIR"
  exit 1
fi

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit
import Foundation

let pixelSize = 1024
let output = CommandLine.arguments[1]

// RGB (no alpha) so the App Store icon remains valid.
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 24
) else {
    fatalError("Could not create icon bitmap")
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

// Soft baby-pink background.
NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.90, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()

// Use Apple's built-in color emoji. Keep generous margins so iOS masking cannot crop it.
let emoji = "🦄" as NSString
let font = NSFont(name: "Apple Color Emoji", size: 650) ?? NSFont.systemFont(ofSize: 650)
let attributes: [NSAttributedString.Key: Any] = [.font: font]
let textSize = emoji.size(withAttributes: attributes)
let origin = NSPoint(
    x: (CGFloat(pixelSize) - textSize.width) / 2.0,
    y: (CGFloat(pixelSize) - textSize.height) / 2.0
)
emoji.draw(at: origin, withAttributes: attributes)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: output))
SWIFT

swift "$SWIFT_FILE" "$MASTER"

resize_icon() {
  local filename="$1"
  local pixels="$2"
  sips -z "$pixels" "$pixels" "$MASTER" --out "$ICON_DIR/$filename" >/dev/null
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
cp "$MASTER" "$ICON_DIR/icon_1024pt.png"

# Verify every filename declared by the main Loop AppIcon set now exists.
python3 - "$ICON_DIR" <<'PY'
import json
import pathlib
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
print("Generated full Apple unicorn emoji icon for the main Loop app (all sizes present).")
PY
