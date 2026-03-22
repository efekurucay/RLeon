#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let emoji = "🦁"
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outDir = repoRoot.appendingPathComponent("SwiftSpeechVisionDemo/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func renderBitmap(pixelSize: Int) throws -> NSBitmapImageRep {
    let w = pixelSize
    let h = pixelSize
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "CGContext"])
    }

    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    ctx.clear(rect)

    let corner = CGFloat(w) * 0.2237
    let rounded = CGPath(
        roundedRect: rect,
        cornerWidth: corner,
        cornerHeight: corner,
        transform: nil
    )
    ctx.addPath(rounded)
    ctx.clip()

    let c1 = CGColor(colorSpace: colorSpace, components: [0.11, 0.44, 0.54, 1])!
    let c2 = CGColor(colorSpace: colorSpace, components: [0.04, 0.18, 0.28, 1])!
    let loc: [CGFloat] = [0, 1]
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: [c1, c2] as CFArray, locations: loc) else {
        throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "gradient"])
    }
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: CGFloat(w), y: CGFloat(h)),
        options: []
    )
    ctx.resetClip()

    let str = emoji as NSString
    let fontSize = CGFloat(w) * 0.54
    let font = NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let sz = str.size(withAttributes: attrs)
    let x = (CGFloat(w) - sz.width) / 2
    let y = (CGFloat(h) - sz.height) / 2

    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = ns
    str.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else {
        throw NSError(domain: "icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "makeImage"])
    }
    return NSBitmapImageRep(cgImage: cgImage)
}

for (px, name) in sizes {
    let rep = try renderBitmap(pixelSize: px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("PNG encode failed: \(name)\n", stderr)
        exit(1)
    }
    let url = outDir.appendingPathComponent(name)
    try data.write(to: url)
    fputs("Wrote \(name) (\(px) px)\n", stderr)
}

print("OK: \(outDir.path)")
