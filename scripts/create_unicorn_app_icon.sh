#!/bin/bash
set -euo pipefail

# Generate the MAIN LOOP app icon from Apple's standard unicorn emoji.
# The emoji is centered with comfortable padding on a baby-pink background.
# Every filename and pixel size is read directly from Loop's AppIcon Contents.json.

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ICON_DIR="$ROOT/OverrideAssetsLoop.xcassets/AppIcon.appiconset"
CONTENTS="$ICON_DIR/Contents.json"
MASTER_PNG="$ICON_DIR/Icon.png"

if [ ! -f "$CONTENTS" ]; then
  echo "::error::Main Loop AppIcon catalog not found at $CONTENTS"
  exit 1
fi

# Use macOS CoreText so this is the regular Apple unicorn emoji, not custom artwork.
swift - "$MASTER_PNG" <<'SWIFT'
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments[1]
let pixels = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let context = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    fatalError("Could not create icon drawing context")
}

// Baby-pink background.
context.setFillColor(CGColor(red: 250.0/255.0, green: 218.0/255.0, blue: 221.0/255.0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 650, nil)
let attributes = [kCTFontAttributeName: font] as CFDictionary
let text = CFAttributedStringCreate(nil, "🦄" as CFString, attributes)!
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .excludeTypographicLeading])

// Center the complete emoji. Correcting for bounds.minX/minY prevents clipping.
let x = (CGFloat(pixels) - bounds.width) / 2 - bounds.minX
let y = (CGFloat(pixels) - bounds.height) / 2 - bounds.minY
context.textPosition = CGPoint(x: x, y: y)
CTLineDraw(line, context)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fatalError("Could not create PNG output")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not save PNG output")
}
SWIFT

# Generate every exact image declared by this AppIcon catalog.
python3 - "$CONTENTS" "$ICON_DIR" "$MASTER_PNG" <<'PY'
import json
import pathlib
import subprocess
import sys

contents = pathlib.Path(sys.argv[1])
icon_dir = pathlib.Path(sys.argv[2])
master = pathlib.Path(sys.argv[3])
data = json.loads(contents.read_text())

for image in data.get("images", []):
    filename = image.get("filename")
    if not filename:
        continue

    size = float(image["size"].split("x", 1)[0])
    scale = int(image.get("scale", "1x").rstrip("x"))
    pixels = round(size * scale)
    destination = icon_dir / filename

    if destination == master and pixels == 1024:
        continue

    temporary = destination.with_suffix(".generated.png")
    subprocess.run(
        ["sips", "-z", str(pixels), str(pixels), str(master), "--out", str(temporary)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    temporary.replace(destination)

# Fail before archiving if any catalog entry is missing or has the wrong dimensions.
errors = []
for image in data.get("images", []):
    filename = image.get("filename")
    if not filename:
        continue

    expected = round(float(image["size"].split("x", 1)[0]) * int(image.get("scale", "1x").rstrip("x")))
    path = icon_dir / filename
    if not path.exists():
        errors.append(f"{filename}: missing")
        continue

    info = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        text=True,
    )
    if f"pixelWidth: {expected}" not in info or f"pixelHeight: {expected}" not in info:
        errors.append(f"{filename}: expected {expected}x{expected}")

if errors:
    raise SystemExit("Invalid main Loop app icons: " + "; ".join(errors))

print("SUCCESS: Main Loop icon is Apple's standard unicorn emoji on baby pink.")
PY
