#!/usr/bin/env swift
// Renders App/Assets.xcassets/AppIcon.appiconset. Run from the repo root.
import AppKit

let canvas: CGFloat = 1024
let outDir = "App/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func draw() {
    // Tile
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0x0F766E).setFill()
    rounded(tile, 185).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    rounded(tile, 185).addClip()
    NSGradient(starting: color(0x5EEAD4), ending: color(0x0F766E))!.draw(in: tile, angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    // Phone
    let phone = NSRect(x: 342, y: 212, width: 340, height: 600)
    let phoneShadow = NSShadow()
    phoneShadow.shadowColor = color(0x000000, 0.3)
    phoneShadow.shadowOffset = NSSize(width: 0, height: -10)
    phoneShadow.shadowBlurRadius = 24
    NSGraphicsContext.saveGraphicsState()
    phoneShadow.set()
    color(0x0B1F24).setFill()
    rounded(phone, 66).fill()
    NSGraphicsContext.restoreGraphicsState()

    let screen = phone.insetBy(dx: 22, dy: 22)
    NSGraphicsContext.saveGraphicsState()
    rounded(screen, 46).addClip()
    NSGradient(starting: color(0xF0FDFA), ending: color(0xCCFBF1))!.draw(in: screen, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Camera
    color(0x0B1F24).setFill()
    NSBezierPath(ovalIn: NSRect(x: 502, y: 758, width: 20, height: 20)).fill()

    // Folder
    let back = NSRect(x: 382, y: 440, width: 260, height: 170)
    let tab = NSRect(x: 382, y: 592, width: 110, height: 46)
    color(0x0F766E).setFill()
    rounded(tab, 16).fill()
    rounded(back, 24).fill()
    color(0x14B8A6).setFill()
    rounded(NSRect(x: 382, y: 440, width: 260, height: 128), 24).fill()

    // Transfer arrows: upload left, download right
    let arrow = NSBezierPath()
    arrow.lineWidth = 28
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0x0F766E).setStroke()

    arrow.move(to: NSPoint(x: 432, y: 296))
    arrow.line(to: NSPoint(x: 432, y: 384))
    arrow.move(to: NSPoint(x: 406, y: 358))
    arrow.line(to: NSPoint(x: 432, y: 384))
    arrow.line(to: NSPoint(x: 458, y: 358))

    arrow.move(to: NSPoint(x: 592, y: 384))
    arrow.line(to: NSPoint(x: 592, y: 296))
    arrow.move(to: NSPoint(x: 566, y: 322))
    arrow.line(to: NSPoint(x: 592, y: 296))
    arrow.line(to: NSPoint(x: 618, y: 322))
    arrow.stroke()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / canvas
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

struct Slot { let size: Int; let scale: Int }
let slots = [16, 32, 128, 256, 512].flatMap { [Slot(size: $0, scale: 1), Slot(size: $0, scale: 2)] }

var images: [[String: String]] = []
for slot in slots {
    let name = "icon_\(slot.size)x\(slot.size)@\(slot.scale)x.png"
    try render(pixels: slot.size * slot.scale).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    images.append([
        "idiom": "mac", "size": "\(slot.size)x\(slot.size)",
        "scale": "\(slot.scale)x", "filename": name,
    ])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
try Data("{\"info\":{\"version\":1,\"author\":\"xcode\"}}".utf8)
    .write(to: URL(fileURLWithPath: "App/Assets.xcassets/Contents.json"))
