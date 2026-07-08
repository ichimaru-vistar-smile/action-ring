#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.build/icon"
ICONSET_DIR="$OUT_DIR/AppIcon.iconset"
BASE_PNG="$OUT_DIR/AppIcon-1024.png"
ICNS_PATH="$ROOT_DIR/bundle/AppIcon.icns"

mkdir -p "$OUT_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - <<'SWIFT' "$BASE_PNG"
import AppKit

let outputPath = CommandLine.arguments[1]
let canvas = CGSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

let rect = CGRect(origin: .zero, size: canvas)
let insetRect = rect.insetBy(dx: 74, dy: 74)
let cornerRadius: CGFloat = 224

let basePath = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius, yRadius: cornerRadius)
context.saveGState()
basePath.addClip()

let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1.0),
    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.22, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)
])!
backgroundGradient.draw(in: insetRect, angle: 135)

let ambientTop = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 0.12),
    NSColor(calibratedWhite: 1.0, alpha: 0.03),
    .clear
])!
ambientTop.draw(from: CGPoint(x: insetRect.midX, y: insetRect.maxY),
                to: CGPoint(x: insetRect.midX, y: insetRect.midY),
                options: [])

let ambientBlue = NSGradient(colors: [
    NSColor(calibratedRed: 0.34, green: 0.55, blue: 0.98, alpha: 0.18),
    .clear
])!
ambientBlue.draw(from: CGPoint(x: insetRect.maxX, y: insetRect.minY + 120),
                 to: CGPoint(x: insetRect.midX, y: insetRect.midY),
                 options: [])

context.restoreGState()

NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
basePath.lineWidth = 3
basePath.stroke()

let ringCenter = CGPoint(x: rect.midX, y: rect.midY)
let ringRadius: CGFloat = 252
let ringLineWidth: CGFloat = 116

func drawArc(start: CGFloat, end: CGFloat, color: NSColor) {
    let glow = NSBezierPath()
    glow.appendArc(withCenter: ringCenter, radius: ringRadius, startAngle: start, endAngle: end, clockwise: false)
    context.saveGState()
    context.setLineWidth(ringLineWidth + 22)
    context.setLineCap(.round)
    context.addPath(glow.cgPath)
    context.replacePathWithStrokedPath()
    context.clip()

    let glowGradient = NSGradient(colors: [
        color.withAlphaComponent(0.28),
        color.withAlphaComponent(0.04),
        .clear
    ])!
    glowGradient.draw(in: CGRect(x: ringCenter.x - ringRadius - 120,
                                 y: ringCenter.y - ringRadius - 120,
                                 width: (ringRadius + 120) * 2,
                                 height: (ringRadius + 120) * 2),
                      relativeCenterPosition: .zero)
    context.restoreGState()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: ringCenter, radius: ringRadius, startAngle: start, endAngle: end, clockwise: false)
    arc.lineCapStyle = .round
    arc.lineWidth = ringLineWidth

    context.saveGState()
    context.addPath(arc.cgPath)
    context.replacePathWithStrokedPath()
    context.clip()

    let fillGradient = NSGradient(colors: [
        color.withAlphaComponent(0.96),
        color.withAlphaComponent(0.72)
    ])!
    fillGradient.draw(in: CGRect(x: ringCenter.x - ringRadius - 80,
                                 y: ringCenter.y - ringRadius - 80,
                                 width: (ringRadius + 80) * 2,
                                 height: (ringRadius + 80) * 2),
                      relativeCenterPosition: .zero)
    context.restoreGState()
}

drawArc(start: 54, end: 126, color: NSColor(calibratedRed: 0.39, green: 0.84, blue: 0.96, alpha: 1.0))
drawArc(start: 324, end: 36, color: NSColor(calibratedRed: 0.97, green: 0.57, blue: 0.50, alpha: 1.0))
drawArc(start: 234, end: 306, color: NSColor(calibratedRed: 0.54, green: 0.60, blue: 0.99, alpha: 1.0))
drawArc(start: 144, end: 216, color: NSColor(calibratedRed: 0.46, green: 0.88, blue: 0.74, alpha: 1.0))

let innerRadius: CGFloat = 150
let innerPath = NSBezierPath(ovalIn: CGRect(
    x: ringCenter.x - innerRadius,
    y: ringCenter.y - innerRadius,
    width: innerRadius * 2,
    height: innerRadius * 2
))
NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
innerPath.lineWidth = 2
innerPath.stroke()

let highlight = NSBezierPath()
highlight.appendArc(withCenter: ringCenter, radius: 312, startAngle: 72, endAngle: 128, clockwise: false)
highlight.lineCapStyle = .round
highlight.lineWidth = 8
NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
highlight.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 16 16 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Built icon:"
echo "  $ICNS_PATH"
