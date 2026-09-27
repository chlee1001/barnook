// Modified by Chaehyeon Lee (2026): a bar above a sheltered nook for BarNook.
// Draws Resources/AppIcon.png in the macOS icon grid (824 of 1024 points).
//
//   swiftc -O -o build/iconrender scripts/make-icon-art.swift
//   build/iconrender Resources/AppIcon.png
//   scripts/make-icon.sh
import AppKit

let side: CGFloat = 1024
let outPath = CommandLine.arguments[1]

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = (side - 824) / 2
let square = NSRect(x: inset, y: inset, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: square, xRadius: 185, yRadius: 185)

let top = NSColor(srgbRed: 0x20/255, green: 0x43/255, blue: 0x50/255, alpha: 1)
let bottom = NSColor(srgbRed: 0x0D/255, green: 0x20/255, blue: 0x2B/255, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)

let ivory = NSColor(srgbRed: 0xF2/255, green: 0xF5/255, blue: 0xEB/255, alpha: 1)
ivory.setStroke()
let nook = NSBezierPath()
nook.lineWidth = 70
nook.lineCapStyle = .round
nook.move(to: NSPoint(x: 318, y: 326))
nook.line(to: NSPoint(x: 318, y: 500))
nook.curve(to: NSPoint(x: 706, y: 500), controlPoint1: NSPoint(x: 318, y: 746), controlPoint2: NSPoint(x: 706, y: 746))
nook.line(to: NSPoint(x: 706, y: 326))
nook.stroke()

ivory.setFill()
NSBezierPath(roundedRect: NSRect(x: 258, y: 610, width: 508, height: 74), xRadius: 37, yRadius: 37).fill()

NSColor(srgbRed: 0xFA/255, green: 0xB4/255, blue: 0x71/255, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 456, y: 344, width: 112, height: 112), xRadius: 26, yRadius: 26).fill()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
