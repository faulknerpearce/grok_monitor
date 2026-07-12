#!/usr/bin/env swift
import AppKit
import Foundation

/// Black Grok singularity mark on a transparent canvas — same style as Coin Monitor's ₿ icon.

func grokPath(in rect: NSRect) -> NSBezierPath {
    let s = min(rect.width, rect.height) / 16
    let ox = rect.midX - 8 * s
    let oy = rect.midY - 8 * s

    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + x * s, y: oy + y * s)
    }

    let path = NSBezierPath()

    // Upper/right arm
    path.move(to: p(6.385, 6.066))
    path.line(to: p(11.104, 9.554))
    path.curve(to: p(11.777, 9.393), controlPoint1: p(11.336, 9.725), controlPoint2: p(11.666, 9.659))
    path.curve(to: p(10.943, 5.153), controlPoint1: p(12.357, 7.992), controlPoint2: p(12.098, 6.309))
    path.curve(to: p(6.714, 4.321), controlPoint1: p(9.789, 3.997), controlPoint2: p(8.182, 3.743))
    path.line(to: p(5.110, 3.577))
    path.curve(to: p(11.950, 4.141), controlPoint1: p(7.411, 2.003), controlPoint2: p(10.204, 2.392))
    path.curve(to: p(13.362, 9.121), controlPoint1: p(13.335, 5.528), controlPoint2: p(13.763, 7.417))
    path.line(to: p(13.366, 9.118))
    path.curve(to: p(14.993, 14.668), controlPoint1: p(12.785, 11.621), controlPoint2: p(13.509, 12.622))
    path.curve(to: p(15.098, 14.815), controlPoint1: p(15.028, 14.716), controlPoint2: p(15.063, 14.765))
    path.line(to: p(13.146, 12.859))
    path.line(to: p(13.146, 12.866))
    path.line(to: p(6.383, 6.065))
    path.close()

    // Lower/left arm
    path.move(to: p(5.411, 5.218))
    path.curve(to: p(5.453, 10.651), controlPoint1: p(3.759, 6.797), controlPoint2: p(4.044, 9.241))
    path.curve(to: p(9.692, 11.494), controlPoint1: p(6.495, 11.694), controlPoint2: p(8.202, 12.120))
    path.line(to: p(11.292, 12.234))
    path.curve(to: p(10.210, 12.824), controlPoint1: p(11.004, 12.442), controlPoint2: p(10.634, 12.667))
    path.curve(to: p(4.441, 11.662), controlPoint1: p(8.294, 13.614), controlPoint2: p(5.999, 13.221))
    path.curve(to: p(3.281, 5.887), controlPoint1: p(2.943, 10.162), controlPoint2: p(2.472, 7.855))
    path.curve(to: p(1.896, 2.324), controlPoint1: p(3.885, 4.415), controlPoint2: p(2.894, 3.375))
    path.curve(to: p(0.902, 1.185), controlPoint1: p(1.542, 1.952), controlPoint2: p(1.187, 1.580))
    path.line(to: p(5.409, 5.217))
    path.close()

    return path
}

func drawIcon(size: Int, path: String) {
    let pixels = CGFloat(size)

    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Failed to create context for \(size)\n", stderr)
        return
    }

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Leave a small margin so the mark doesn't clip at tiny sizes.
    let inset = pixels * 0.08
    let drawRect = NSRect(x: inset, y: inset, width: pixels - inset * 2, height: pixels - inset * 2)
    NSColor.black.setFill()
    grokPath(in: drawRect).fill()

    guard let cgImage = ctx.makeImage() else {
        fputs("Failed to make image for \(size)\n", stderr)
        return
    }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pixels, height: pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to create PNG data for \(size)\n", stderr)
        return
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("Saved \(path) (\(size)x\(size))")
    } catch {
        fputs("Failed to write \(path): \(error)\n", stderr)
    }
}

let sizes: [(size: Int, name: String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (pixels, name) in sizes {
    drawIcon(size: pixels, path: "\(outputDir)/\(name).png")
}

print("All icons generated to \(outputDir)")
