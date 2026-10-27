#!/usr/bin/env swift
// Draw the Patter app icon and build an .icns from it.
//
//   swift scripts/make-icon.swift <output.icns>
//
// A dark teal rounded square with Clawd standing still and a cyan heartbeat
// line under him. The icon lives as code so nobody has to redraw a binary.
// Standalone on purpose (AppKit only, no package imports), so Clawd's pixel
// data is duplicated here: it mirrors the `Clawd` enum in the app's Clawd.swift.

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: swift scripts/make-icon.swift <output.icns>") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])

// Pixel columns per row, from Claude Code's startup art. Row 1 has the eye holes.
let body: [[Int]] = [
    Array(3...14),
    [3, 4] + Array(6...11) + [13, 14],
    Array(1...16),
    Array(3...14),
]
let legs = [4, 6, 11, 13]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Renders the icon at `pixels` x `pixels`. `scale` only sets the PNG's DPI.
func render(pixels n: Int, scale: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { fail("can't create a \(n) px bitmap") }
    rep.size = NSSize(width: n / scale, height: n / scale)

    let size = CGFloat(n)
    // Draw y-down, like the art. Shadow offsets stay in device space (y-up).
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    // Tile: inset ~10% like Apple's icon grid, continuous-ish corners.
    let inset = (size * 0.1).rounded()
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let s = tile.width
    let shape = CGPath(roundedRect: tile, cornerWidth: s * 0.225, cornerHeight: s * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.05, color: color(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x0F1A1E))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x16262C), color(0x0F1A1E)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    ctx.restoreGState()

    // At 16 px the heartbeat line is a smudge, so the smallest size is just Clawd.
    let pulse = n > 16

    // Clawd: 18 cells wide, ~66% of the tile. Cells snap to the nearest whole
    // pixel once they're about a pixel wide (32 px and up), so the art stays
    // crisp (rounding down would shrink him to a third of the tile at 64 px);
    // at 16 px a cell is under a pixel and anti-aliasing is unavoidable.
    var cw = s * 0.66 / 18
    if cw >= 0.9 { cw = cw.rounded() }
    let ch = cw * 2
    var ox = tile.minX + (s - 18 * cw) / 2
    var oy = tile.minY + (s - 5 * ch) / 2 - (pulse ? s * 0.07 : 0)
    if cw >= 1 { ox = ox.rounded(); oy = oy.rounded() }

    // One path, filled once: separate fills leave anti-aliased seams.
    let clawd = CGMutablePath()
    for (row, cols) in body.enumerated() {
        for col in cols { clawd.addRect(CGRect(x: ox + CGFloat(col) * cw, y: oy + CGFloat(row) * ch, width: cw, height: ch)) }
    }
    for col in legs { clawd.addRect(CGRect(x: ox + CGFloat(col) * cw, y: oy + 4 * ch, width: cw, height: ch)) }
    ctx.addPath(clawd)
    ctx.setFillColor(color(0xD97757))
    ctx.fillPath()

    if pulse {
        let y = oy + 5 * ch + s * 0.11
        let x0 = tile.minX + s * 0.14, w = s * 0.72
        let line = CGMutablePath()
        line.move(to: CGPoint(x: x0, y: y))
        line.addLine(to: CGPoint(x: x0 + w * 0.36, y: y))
        line.addLine(to: CGPoint(x: x0 + w * 0.43, y: y - s * 0.07))
        line.addLine(to: CGPoint(x: x0 + w * 0.52, y: y + s * 0.09))
        line.addLine(to: CGPoint(x: x0 + w * 0.59, y: y - s * 0.04))
        line.addLine(to: CGPoint(x: x0 + w * 0.64, y: y))
        line.addLine(to: CGPoint(x: x0 + w, y: y))
        ctx.addPath(line)
        ctx.setStrokeColor(color(0x22D3EE))
        // Thicker than proportional at 32 px so it doesn't fade to a hairline.
        ctx.setLineWidth(max(1.5, s * 0.03))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    guard let png = rep.representation(using: .png, properties: [:]) else { fail("can't encode a \(n) px PNG") }
    return png
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("patter-\(UUID().uuidString).iconset")
do {
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    fail("can't create \(iconset.path): \(error.localizedDescription)")
}
defer { try? fm.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        do {
            try render(pixels: points * scale, scale: scale).write(to: iconset.appendingPathComponent(name))
        } catch {
            fail("can't write \(name): \(error.localizedDescription)")
        }
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    fail("can't run iconutil: \(error.localizedDescription)")
}
guard iconutil.terminationStatus == 0 else { fail("iconutil exited with \(iconutil.terminationStatus)") }
